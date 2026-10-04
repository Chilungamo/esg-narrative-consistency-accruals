/*===========================================================================
  01_sp500_universe.sas
  Build the FULL Compustat firm-year universe (needed to estimate the Jones
  model on adequately sized industry-year cells) and flag S&P 500 members.

  Input:  &funda_tbl, &company_tbl, &ccm_link_tbl, &sp500_tbl
  Output: WORK.comp_full -- one row per gvkey-fyear, fyear &start_yr-1 ..
          &end_yr (the extra leading year supplies lags), with
          sic_final, cik_company, permno, and sp500 (1 = member at FYE)
===========================================================================*/

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
         coalesce(a.sich, input(b.sic, ?? 4.)) as sic_final,
         input(cats(b.cik), ?? 32.)            as cik_company
  from comp_raw a
  left join &company_tbl b
    on a.gvkey = b.gvkey;
quit;

/*---------------------------------------------------------------------------
  Step 1.3 -- CRSP/Compustat link -> PERMNO
  Only LU/LC links (LD = duplicate, LX = foreign-exchange listing,
  LN = no CRSP price data). If several links are valid at datadate,
  prefer linkprim 'P' over 'C'.
---------------------------------------------------------------------------*/
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

/*---------------------------------------------------------------------------
  Step 1.4 -- S&P 500 membership at fiscal year-end (flag, not a filter)
---------------------------------------------------------------------------*/
proc sql;
  create table sp500_hits as
  select distinct a.gvkey, a.fyear
  from comp_linked a
  inner join &sp500_tbl s
    on  a.permno = s.permno
    and a.datadate between s.start and s.ending
  where not missing(a.permno);

  create table comp_full as
  select a.*,
         (not missing(b.gvkey)) as sp500
  from comp_linked a
  left join sp500_hits b
    on  a.gvkey = b.gvkey
    and a.fyear = b.fyear
  order by gvkey, fyear;
quit;

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
