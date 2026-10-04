/*===========================================================================
  01_sp500_universe.sas
  Build the FULL Compustat firm-year universe (needed to estimate the Jones
  model on adequately sized industry-year cells) and flag S&P 500 members.

  Input:  &funda_tbl, &company_tbl, and for S&P 500 membership either
          &ccm_link_tbl + &sp500_tbl (CRSP) or &sp500_idx_tbl (Compustat)
  Output: WORK.comp_full -- one row per gvkey-fyear, fyear &start_yr-1 ..
          &end_yr (the extra leading year supplies lags), with
          sic_final, cik_company, permno (missing without CRSP access),
          and sp500 (1 = member at FYE)
===========================================================================*/

%require_readable(&funda_tbl &company_tbl);

/*---------------------------------------------------------------------------
  Step 1.1 -- Compustat annual fundamentals (standard filters)
---------------------------------------------------------------------------*/
data comp_raw;
  set &funda_tbl (
    keep = gvkey fyear datadate conm sich
           at ib oancf xidoc act lct che dlc dp
           sale rect ppegt ceq lt csho prcc_f mkvalt
           indfmt datafmt popsrc consol
  );
  where indfmt  = 'INDL'
    and datafmt = 'STD'
    and popsrc  = 'D'
    and consol  = 'C'
    and fyear between %eval(&start_yr - 1) and &end_yr
    and not missing(gvkey)
    and not missing(at) and at > 0;
  drop indfmt datafmt popsrc consol;
run;

/* One row per gvkey-fyear: on a fiscal-year-end change keep the later FYE */
proc sort data=comp_raw; by gvkey fyear descending datadate; run;
data comp_raw;
  set comp_raw;
  by gvkey fyear;
  if first.fyear;
run;

/*---------------------------------------------------------------------------
  Step 1.2 -- Industry and CIK from the company header.
  sich (historical SIC) is frequently missing in early years; a missing
  SIC2 would otherwise slip past the financials/utilities filter in 02.
---------------------------------------------------------------------------*/
proc sql;
  create table comp_sic as
  select a.*,
         /* ?? is DATA-step-only; in PROC SQL a blank SIC/CIK simply
            converts to missing. CATS() makes this work whether the
            column is stored as character or numeric.                    */
         coalesce(a.sich, input(cats(b.sic), 4.)) as sic_final,
         input(cats(b.cik), 12.)                  as cik_company
  from comp_raw a
  left join &company_tbl b
    on a.gvkey = b.gvkey;
quit;

/*---------------------------------------------------------------------------
  Steps 1.3-1.4 -- S&P 500 membership at fiscal year-end (flag, not filter)

  Route A (CRSP licensed): CCM link -> PERMNO -> crsp.msp500list.
    Only LU/LC links (LD = duplicate, LX = foreign listing, LN = no CRSP
    prices); if several are valid at datadate, prefer linkprim 'P'.
  Route B (Compustat only): comp.idxcst_his, S&P 500 = gvkeyx '000003',
    matched on GVKEY with from <= datadate <= thru (missing thru = still
    a member). No PERMNO needed.
---------------------------------------------------------------------------*/
%macro flag_sp500;

  %if %can_read(&ccm_link_tbl) = 1 and %can_read(&sp500_tbl) = 1 %then %do;
    %put NOTE: [01] %nrstr(S&P) 500 membership from CRSP (&sp500_tbl via &ccm_link_tbl).;

    proc sql;
      create table comp_linked as
      select a.*,
             b.lpermno  as permno,
             b.linkprim as linkprim
      from comp_sic a
      left join &ccm_link_tbl b
        on  a.gvkey = b.gvkey
        and b.linktype in ('LU','LC')
        and b.linkprim in ('P','C')
        and (missing(b.linkdt)    or b.linkdt   <= a.datadate)
        and (missing(b.linkenddt) or a.datadate <= b.linkenddt)
      order by gvkey, fyear, linkprim desc;
    quit;

    data comp_linked;
      set comp_linked;
      by gvkey fyear;
      if first.fyear;
      drop linkprim;
    run;

    proc sql;
      create table sp500_hits as
      select distinct a.gvkey, a.fyear
      from comp_linked a
      inner join &sp500_tbl s
        on  a.permno = s.permno
        and a.datadate between s.start and s.ending
      where not missing(a.permno);
    quit;
  %end;

  %else %if %can_read(&sp500_idx_tbl) = 1 %then %do;
    %put NOTE: [01] CRSP not readable -- %nrstr(S&P) 500 membership from &sp500_idx_tbl (gvkeyx &sp500_gvkeyx).;

    /* PERMNO is not needed on this route; keep the column for a stable schema */
    data comp_linked;
      set comp_sic;
      permno = .;
    run;

    /* FROM is a reserved word in PROC SQL, so rename in a DATA-step view */
    data _sp500_spells / view=_sp500_spells;
      set &sp500_idx_tbl (keep=gvkey gvkeyx from thru
                          where=(gvkeyx = "&sp500_gvkeyx"));
      idx_from = from;
      idx_thru = thru;
      keep gvkey idx_from idx_thru;
    run;

    proc sql;
      create table sp500_hits as
      select distinct a.gvkey, a.fyear
      from comp_linked a
      inner join _sp500_spells s
        on  a.gvkey = s.gvkey
        and s.idx_from <= a.datadate
        and (missing(s.idx_thru) or a.datadate <= s.idx_thru);
    quit;
  %end;

  %else %do;
    %put ERROR: [01] No readable %nrstr(S&P) 500 source: need &ccm_link_tbl + &sp500_tbl, or &sp500_idx_tbl.;
    %abort cancel;
  %end;

  proc sql;
    create table comp_full as
    select a.*,
           (not missing(b.gvkey)) as sp500
    from comp_linked a
    left join sp500_hits b
      on  a.gvkey = b.gvkey
      and a.fyear = b.fyear
    order by gvkey, fyear;
  quit;
%mend flag_sp500;
%flag_sp500;

%assert_unique(dsn=comp_full, keys=gvkey fyear);

proc sql;
  title 'Universe Summary';
  select count(*)                                          as n_obs,
         count(distinct gvkey)                             as n_firms,
         sum(sp500)                                        as n_sp500_obs,
         count(distinct case when sp500 = 1 then gvkey end) as n_sp500_firms
  from comp_full
  where fyear >= &start_yr;
  title;
quit;
