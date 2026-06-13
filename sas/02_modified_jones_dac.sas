/*===========================================================================
  02_modified_jones_dac.sas
  Modified Jones Model with performance-matched discretionary accruals
  (Jones 1991; Dechow, Sloan & Sweeney 1995; Kothari, Leone & Wasley 2005)

  Input:  WORK.universe (from 01_sp500_universe.sas)
  Output: WORK.DA_final — firm-year panel with DAC, ABS_DAC, PM_DAC, ABS_PM_DAC
===========================================================================*/

/*---------------------------------------------------------------------------
  Step 2.1 — Balance-sheet total accruals + Jones model regressors
---------------------------------------------------------------------------*/
proc sort data=universe out=univ_sorted; by gvkey fyear; run;

data accruals_raw;
  set univ_sorted;
  by gvkey fyear;

  retain at_lag act_lag che_lag lct_lag dlc_lag sale_lag rect_lag;

  if first.gvkey then do;
    at_lag=.; act_lag=.; che_lag=.; lct_lag=.; dlc_lag=.;
    sale_lag=.; rect_lag=.;
  end;

  if not missing(at_lag) and at_lag > 0 then do;
    dCA   = act  - act_lag;
    dCash = che  - che_lag;
    dCL   = lct  - lct_lag;
    dSTD  = dlc  - dlc_lag;
    Dep   = dp;
    dSALE = sale - sale_lag;
    dRECT = rect - rect_lag;

    /* Total accruals scaled by lagged assets */
    TA = (dCA - dCash - dCL + dSTD - Dep) / at_lag;

    /* Jones model regressors */
    dREV_adj  = (dSALE - dRECT) / at_lag;   /* DeltaREV net of DeltaREC */
    PPE_sc    = ppegt / at_lag;
    ASSETS_sc = 1 / at_lag;                  /* intercept deflator      */

    /* Performance control */
    ROA = ib / ((at + at_lag) / 2);
  end;

  at_lag   = at;
  act_lag  = act;
  che_lag  = che;
  lct_lag  = lct;
  dlc_lag  = dlc;
  sale_lag = sale;
  rect_lag = rect;

  /* 2-digit SIC for industry grouping */
  SIC2 = int(sich / 100);

  /* Exclude financials (SIC 60-69) and utilities (SIC 49) */
  if 60 <= SIC2 <= 69 then delete;
  if SIC2 = 49         then delete;

  if missing(TA) or missing(dREV_adj) or missing(PPE_sc) or missing(ASSETS_sc)
    then delete;

  label TA        = 'Total Accruals / Lagged Assets'
        dREV_adj  = '(dSALES - dREC) / Lagged Assets'
        PPE_sc    = 'Gross PP&E / Lagged Assets'
        ASSETS_sc = '1 / Lagged Assets (intercept deflator)'
        ROA       = 'Return on Assets';
run;

/*---------------------------------------------------------------------------
  Step 2.2 — Winsorize macro (1%/99% by fiscal year)
---------------------------------------------------------------------------*/
%macro winsorize(dsn=, var=, byvar=fyear, pct=1);
  %local lo hi;
  %let lo = &pct;
  %let hi = %eval(100 - &pct);

  proc sort data=&dsn; by &byvar; run;

  proc univariate data=&dsn noprint;
    by &byvar;
    var &var;
    output out=_wintmp_ pctlpts=&lo &hi pctlpre=_p_;
  run;

  data &dsn;
    merge &dsn _wintmp_;
    by &byvar;
    if not missing(_p_&lo) and not missing(_p_&hi) then
      &var = max(_p_&lo, min(&var, _p_&hi));
    drop _p_&lo _p_&hi;
  run;

  proc datasets library=work nolist; delete _wintmp_; run; quit;
%mend;

%winsorize(dsn=accruals_raw, var=TA,       byvar=fyear);
%winsorize(dsn=accruals_raw, var=dREV_adj, byvar=fyear);
%winsorize(dsn=accruals_raw, var=PPE_sc,   byvar=fyear);
%winsorize(dsn=accruals_raw, var=ROA,      byvar=fyear);

/*---------------------------------------------------------------------------
  Step 2.3 — Require >= 10 observations per SIC2-year cell
---------------------------------------------------------------------------*/
proc sql;
  create table ind_yr_n as
  select SIC2, fyear, count(*) as n_obs
  from accruals_raw
  group by SIC2, fyear;
quit;

data accruals_est;
  merge accruals_raw ind_yr_n;
  by SIC2 fyear;
  if n_obs < 10 then delete;
run;

/*---------------------------------------------------------------------------
  Step 2.4 — Cross-sectional Modified Jones OLS by SIC2 x year (no intercept)
---------------------------------------------------------------------------*/
proc sort data=accruals_est; by SIC2 fyear; run;

proc reg data=accruals_est outest=jones_coefs noprint;
  by SIC2 fyear;
  model TA = ASSETS_sc dREV_adj PPE_sc / noint;
  output out=jones_output r=NDA_error p=NDAC;
run;

data jones_output;
  set jones_output;
  DAC     = TA - NDAC;
  ABS_DAC = abs(DAC);
run;

/*---------------------------------------------------------------------------
  Step 2.5 — Performance-matched discretionary accruals (Kothari et al. 2005)
---------------------------------------------------------------------------*/
proc sort data=jones_output; by SIC2 fyear ROA; run;

proc rank data=jones_output out=jones_ranked groups=10;
  by SIC2 fyear;
  var ROA;
  ranks ROA_decile;
run;

proc sort data=jones_ranked; by SIC2 fyear ROA_decile; run;

proc means data=jones_ranked noprint;
  by SIC2 fyear ROA_decile;
  var DAC;
  output out=median_dac median=median_DAC;
run;

proc sort data=median_dac; by SIC2 fyear ROA_decile; run;

data DA_final;
  merge jones_ranked
        median_dac (keep=SIC2 fyear ROA_decile median_DAC);
  by SIC2 fyear ROA_decile;
  PM_DAC     = DAC - median_DAC;
  ABS_PM_DAC = abs(PM_DAC);
  label DAC        = 'Jones DA'
        ABS_DAC    = '|Jones DA|'
        PM_DAC     = 'Performance-Matched DA'
        ABS_PM_DAC = '|Performance-Matched DA|';
run;

proc means data=DA_final n mean std p25 median p75;
  var TA NDAC DAC ABS_DAC PM_DAC ABS_PM_DAC ROA;
  title 'Modified Jones Model — Summary Statistics';
run; title;
