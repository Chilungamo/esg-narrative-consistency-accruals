/*===========================================================================
  00_setup_libraries.sas
  ESG Narrative Consistency & Discretionary Accruals -- Albert Limani

  Purpose: global parameters, WRDS library references, and the shared
  utility macros (%winsorize, %assert_unique) used by scripts 01-05.
  Run once per session before 01-05 (see run_all.sas).
===========================================================================*/

options notes stimer source mprint;

/*---------------------------------------------------------------------------
  PARAMETERS -- edit these for your environment
---------------------------------------------------------------------------*/
%let wrds_path = /home/youruser;
%let out_path  = &wrds_path./esg_accruals;
%let start_yr  = 1994;
%let end_yr    = 2024;

/* Item 1A (Risk Factors) is required in Form 10-K for fiscal years ending
   on or after 1 Dec 2005. Risk-Factor intensities -- and therefore ENCI --
   are set to missing for fiscal year-ends before this date.               */
%let rf_start_date = 01DEC2005;

/* Each gvkey-datadate is matched to the first 10-K filed within this many
   days AFTER the fiscal year-end.                                          */
%let file_window = 365;

/* Minimum firm-years per SIC2 x fyear cell for the Jones regressions      */
%let min_cell_n = 10;

/*---------------------------------------------------------------------------
  SOURCE TABLES -- VERIFY on your WRDS node with the diagnostics below.
---------------------------------------------------------------------------*/
%let funda_tbl    = comp.funda;
%let company_tbl  = comp.company;
%let ccm_link_tbl = crsp.ccmxpf_lnkhist;
%let sp500_tbl    = crsp.msp500list;

/* GVKEY -> CIK link with validity dates. If this table does not exist,
   03 falls back to comp.company.cik (current CIK only, no history).       */
%let cik_link_tbl   = wrdssec.wciklink_gvkey;
%let cik_link_start = datadate1;
%let cik_link_end   = datadate2;

/* 10-K section-text tables and their column names.
   &txt_date must be a SAS date (not a datetime).
   If text is stored in several rows (chunks) per filing, that is handled:
   counts are summed by cik x file_date x form in 03.                      */
%let mda_tbl   = wrdssec.mda_clean;
%let mda_var   = mda_text;
%let rf_tbl    = wrdssec.rfactor;
%let rf_var    = rf_text;
%let txt_cik   = cik;
%let txt_date  = file_date;
%let txt_form  = form_type;
%let txt_forms = '10-K','10-K405','10-KT';

/* Create output folder if it does not exist */
options dlcreatedir;
libname _outdir "&out_path.";
libname _outdir clear;

/*===========================================================================
  WRDS LIBRARIES
  WRDS SAS Studio pre-assigns comp / crsp / wrdssec. Re-pointing them at a
  parent directory (e.g. /wrds/comp/sasdata) hides the tables, so we only
  assign a library if it is NOT already assigned.
===========================================================================*/
%macro assign_lib(lib=, path=);
  %if %sysfunc(libref(&lib)) ne 0 %then %do;
    libname &lib &path access=readonly;
    %put NOTE: [setup] &lib was not pre-assigned -- assigned to &path..;
  %end;
  %else %put NOTE: [setup] Using pre-assigned library &lib..;
%mend assign_lib;

%assign_lib(lib=comp,    path='/wrds/comp/sasdata/d_na');
%assign_lib(lib=crsp,    path=('/wrds/crsp/sasdata/a_stock'
                               '/wrds/crsp/sasdata/a_ccm'
                               '/wrds/crsp/sasdata/a_indexes'));
%assign_lib(lib=wrdssec, path='/wrds/sec/sasdata');

/*===========================================================================
  DIAGNOSTICS -- run once to confirm table and column names
===========================================================================*/
/*
proc contents data=&ccm_link_tbl  short; run;   -- gvkey lpermno linktype linkprim linkdt linkenddt
proc contents data=&sp500_tbl     short; run;   -- permno start ending
proc contents data=&cik_link_tbl  short; run;   -- gvkey cik datadate1 datadate2
proc contents data=&mda_tbl;              run;   -- cik / date / form / text column names + text LENGTH
proc contents data=&rf_tbl;               run;
*/

/*===========================================================================
  %winsorize -- clip VARS at the PCT / (100-PCT) percentiles within BYVAR.

  Missing values stay missing. (SAS MIN/MAX skip missing arguments, so the
  naive  x = max(p1, min(x, p99))  turns a missing x into p99.)
===========================================================================*/
%macro winsorize(dsn=, vars=, byvar=fyear, pct=1);
  %local lo hi n i v;
  %let lo = &pct;
  %let hi = %eval(100 - &pct);
  %let n  = %sysfunc(countw(&vars, %str( )));

  proc sort data=&dsn; by &byvar; run;

  proc univariate data=&dsn noprint;
    by &byvar;
    var &vars;
    output out=_wintmp_ pctlpts=&lo &hi
           pctlpre=%do i = 1 %to &n; _wz&i._ %end;;
  run;

  data &dsn;
    merge &dsn _wintmp_;
    by &byvar;
    %do i = 1 %to &n;
      %let v = %scan(&vars, &i, %str( ));
      if not missing(&v) and nmiss(_wz&i._&lo, _wz&i._&hi) = 0 then
        &v = min(max(&v, _wz&i._&lo), _wz&i._&hi);
    %end;
    drop _wz:;
  run;

  proc datasets library=work nolist; delete _wintmp_; run; quit;
%mend winsorize;

/*===========================================================================
  %assert_unique -- write an ERROR to the log if DSN is not unique on KEYS.
  Data-step MERGE with duplicate keys on both sides is silently wrong, so
  every join output is checked.
===========================================================================*/
%macro assert_unique(dsn=, keys=);
  %local keylist nrows nkeys;
  %let keylist = %sysfunc(translate(%sysfunc(compbl(&keys)), %str(,), %str( )));
  proc sql noprint;
    select count(*) into :nrows trimmed from &dsn;
    select count(*) into :nkeys trimmed
      from (select distinct &keylist from &dsn);
  quit;
  %if &nrows ne &nkeys %then
    %put ERROR: [assert_unique] &dsn has %eval(&nrows - &nkeys) duplicate row(s) on (&keys).;
  %else
    %put NOTE: [assert_unique] &dsn is unique on (&keys): &nrows rows.;
%mend assert_unique;
