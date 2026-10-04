/*===========================================================================
  02_modified_jones_dac.sas
  Cross-sectional modified Jones model and performance-matched
  discretionary accruals.
  (Jones 1991; Dechow, Sloan & Sweeney 1995; Kothari, Leone & Wasley 2005;
   Hribar & Collins 2002 for cash-flow total accruals)

  The model is estimated on the FULL non-financial Compustat universe by
  SIC2 x fyear; the S&P 500 sample is selected only afterwards. Estimating
  on S&P 500 firms alone leaves most SIC2-year cells below &min_cell_n and
  makes decile-based performance matching degenerate.

  Input:  WORK.comp_full (from 01_sp500_universe.sas)
  Output: WORK.DA_final    -- S&P 500 firm-years with DAC, ABS_DAC,
                              PM_DAC, ABS_PM_DAC
          WORK.jones_coefs -- coefficients by SIC2 x fyear
===========================================================================*/

/*---------------------------------------------------------------------------
  Step 2.1 -- Total accruals + Jones regressors.
  Lags come from the immediately preceding FISCAL YEAR, not the preceding
  row: a gap in the panel leaves the lag missing.
---------------------------------------------------------------------------*/
proc sort data=comp_full; by gvkey fyear; run;

data accruals_raw;
  set comp_full;
  by gvkey fyear;

  /* LAG() is a queue: call it on every iteration, then null it out when
     the previous row is not the previous fiscal year of the same firm.   */
  fyear_lag = lag(fyear);
  at_lag    = lag(at);
  sale_lag  = lag(sale);
  rect_lag  = lag(rect);

  if first.gvkey or fyear_lag ne fyear - 1 then
    call missing(at_lag, sale_lag, rect_lag);

  if not missing(at_lag) and at_lag > 0 then do;
    /* Total accruals, cash-flow approach (post-SFAS 95), scaled by lagged
       assets: TA = [IB - (OANCF - XIDOC)] / AT_{t-1}                       */
    if nmiss(ib, oancf) = 0 then
      TA = (ib - (oancf - coalesce(xidoc, 0))) / at_lag;

    /* Jones model regressors */
    if nmiss(sale, sale_lag, rect, rect_lag) = 0 then
      dREV_adj = ((sale - sale_lag) - (rect - rect_lag)) / at_lag;
    if not missing(ppegt) then
      PPE_sc = ppegt / at_lag;
    ASSETS_sc = 1 / at_lag;

    /* Performance control: IB / average total assets */
    if not missing(ib) then
      ROA = ib / ((at + at_lag) / 2);
  end;

  /* 2-digit SIC; drop missing industry, financials (60-69), utilities (49) */
  SIC2 = int(sic_final / 100);
  if missing(SIC2)     then delete;
  if 60 <= SIC2 <= 69  then delete;
  if SIC2 = 49         then delete;

  /* The leading year (&start_yr - 1) only supplies lags */
  if fyear < &start_yr then delete;

  if nmiss(TA, dREV_adj, PPE_sc, ASSETS_sc) > 0 then delete;

  drop fyear_lag sale_lag rect_lag;

  label TA        = 'Total Accruals (IB - CFO excl. XI) / Lagged Assets'
        dREV_adj  = '(dSALES - dREC) / Lagged Assets'
        PPE_sc    = 'Gross PP&E / Lagged Assets'
        ASSETS_sc = '1 / Lagged Assets'
        ROA       = 'IB / Average Total Assets';
run;

/*---------------------------------------------------------------------------
  Step 2.2 -- Winsorize model inputs at 1/99 by fiscal year (full universe)
---------------------------------------------------------------------------*/
%winsorize(dsn=accruals_raw, vars=TA dREV_adj PPE_sc ASSETS_sc ROA, byvar=fyear);

/*---------------------------------------------------------------------------
  Step 2.3 -- Require >= &min_cell_n firm-years per SIC2 x fyear cell
  (ORDER BY leaves the table sorted for the BY-group regression.)
---------------------------------------------------------------------------*/
proc sql;
  create table accruals_est as
  select *, count(*) as n_cell
  from accruals_raw
  group by SIC2, fyear
  having count(*) >= &min_cell_n
  order by SIC2, fyear;
quit;

/*---------------------------------------------------------------------------
  Step 2.4 -- Cross-sectional modified Jones OLS by SIC2 x fyear.
  Intercept included alongside 1/A_{t-1} (Kothari et al. 2005).
---------------------------------------------------------------------------*/
proc reg data=accruals_est outest=jones_coefs edf noprint;
  by SIC2 fyear;
  model TA = ASSETS_sc dREV_adj PPE_sc;
  output out=jones_output p=NDAC r=DAC;
run;
quit;

/*---------------------------------------------------------------------------
  Step 2.5 -- Performance matching (Kothari, Leone & Wasley 2005):
  each firm-year is matched to the OTHER firm in its SIC2 x fyear cell with
  the closest ROA, and PM_DAC = DAC - DAC_match.

  After sorting by (SIC2, fyear, ROA), the nearest-ROA neighbour is always
  the previous or the next row in the same cell, so the match is one sort
  plus a lag/lead pass -- O(n log n), no self-join.
---------------------------------------------------------------------------*/
proc sort data=jones_output (where=(nmiss(ROA, DAC) = 0)) out=pm_base;
  by SIC2 fyear ROA gvkey;
run;

data pm_match (keep=gvkey fyear DAC_match);
  /* Look-ahead idiom: a second SET starting at row 2 supplies lead values */
  set pm_base (keep=gvkey fyear SIC2 ROA DAC) end=_last;
  if not _last then
    set pm_base (firstobs=2 keep=SIC2 fyear ROA DAC
                 rename=(SIC2=_sic_next fyear=_yr_next ROA=_roa_next DAC=_dac_next));
  else call missing(_sic_next, _yr_next, _roa_next, _dac_next);

  _sic_prev = lag(SIC2);
  _yr_prev  = lag(fyear);
  _roa_prev = lag(ROA);
  _dac_prev = lag(DAC);

  has_prev = (_n_ > 1 and _sic_prev = SIC2 and _yr_prev = fyear);
  has_next = (_sic_next = SIC2 and _yr_next = fyear);

  if has_prev and has_next then do;
    if abs(ROA - _roa_prev) <= abs(_roa_next - ROA) then DAC_match = _dac_prev;
    else DAC_match = _dac_next;
  end;
  else if has_prev then DAC_match = _dac_prev;
  else if has_next then DAC_match = _dac_next;
run;

proc sql;
  create table jones_pm as
  select a.*, b.DAC_match
  from jones_output a
  left join pm_match b
    on a.gvkey = b.gvkey and a.fyear = b.fyear;
quit;

/*---------------------------------------------------------------------------
  Step 2.6 -- Keep S&P 500 members
---------------------------------------------------------------------------*/
data DA_final;
  set jones_pm;
  where sp500 = 1;

  ABS_DAC = abs(DAC);
  if nmiss(DAC, DAC_match) = 0 then do;
    PM_DAC     = DAC - DAC_match;
    ABS_PM_DAC = abs(PM_DAC);
  end;

  label DAC        = 'Modified Jones DA'
        ABS_DAC    = '|Modified Jones DA|'
        PM_DAC     = 'Performance-Matched DA (nearest ROA, same SIC2-year)'
        ABS_PM_DAC = '|Performance-Matched DA|';
run;

%assert_unique(dsn=DA_final, keys=gvkey fyear);

proc means data=DA_final n mean std p25 median p75;
  var TA NDAC DAC ABS_DAC PM_DAC ABS_PM_DAC ROA;
  title 'Modified Jones Model (S&P 500 firm-years) -- Summary Statistics';
run;
title;
