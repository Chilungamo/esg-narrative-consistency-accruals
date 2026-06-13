/*===========================================================================
  01_sp500_universe.sas
  Build the S&P 500 firm-year panel from Compustat + CRSP/Compustat Merged
  + CRSP S&P 500 constituent history.

  Input:  comp.funda, comp.ccmxpf_linktable, crsp.msp500list
  Output: WORK.universe  (one row per gvkey-fyear, S&P 500 member at FYE)
===========================================================================*/

%include "00_setup_libraries.sas";

/* Step 1.1 — Pull Compustat annual fundamentals */
data comp_raw;
  set comp.funda (
    keep = gvkey fyear datadate conm sich
           at ni oancf dlcch act lct che dlc dp
           sale rect ppegt ceq lt csho mkvalt
           revt xsga ib xidoc
           indfmt datafmt popsrc consol
  );
  where indfmt  = 'INDL'
    and datafmt = 'STD'
    and popsrc  = 'D'
    and consol  = 'C'
    and fyear between &start_yr and &end_yr
    and not missing(gvkey)
    and not missing(at) and at > 0;
run;

/* Step 1.2 — CRSP/Compustat merged link table -> PERMNO */
proc sql;
  create table comp_linked as
  select a.*,
         b.lpermno as permno,
         b.linktype,
         b.linkprim
  from comp_raw a
  left join comp.ccmxpf_linktable b
    on  a.gvkey = b.gvkey
    and b.linktype in ('LU','LC','LD','LN','LS','LX')
    and b.linkprim in ('P','C')
    and (b.linkdt    <= a.datadate or missing(b.linkdt))
    and (b.linkenddt >= a.datadate or missing(b.linkenddt));
quit;

/* Step 1.3 — S&P 500 membership periods from CRSP */
proc sql;
  create table sp500_periods as
  select permno,
         start  as sp500_start,
         ending as sp500_end
  from crsp.msp500list;
quit;

/* Step 1.4 — Filter to S&P 500 members at fiscal year-end */
proc sql;
  create table universe as
  select distinct a.*
  from comp_linked a
  inner join sp500_periods b
    on  a.permno = b.permno
    and a.datadate between b.sp500_start and b.sp500_end
  where not missing(a.permno)
  order by a.gvkey, a.fyear;
quit;

proc sql;
  title 'Universe Summary';
  select count(*) as n_obs, count(distinct gvkey) as n_firms
  from universe;
  title;
quit;
