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
/* Defaults to your WRDS home directory ($HOME); override by setting
   wrds_path before including this file.                                  */
%macro _set_wrds_path;
  %global wrds_path;
  %if %length(&wrds_path) = 0 %then %let wrds_path = %sysget(HOME);
%mend _set_wrds_path;
%_set_wrds_path
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
/* S&P 500 membership. 01 uses CRSP (msp500list via the CCM link) when
   both CRSP tables are readable, otherwise the Compustat index-constituent
   history (&sp500_idx_tbl, S&P 500 = gvkeyx '000003'), which needs no
   PERMNO link. Run %access_report (below) to see which you are licensed for. */
%let ccm_link_tbl  = crsp.ccmxpf_lnkhist;
%let sp500_tbl     = crsp.msp500list;
%let sp500_idx_tbl = comp.idxcst_his;
%let sp500_gvkeyx  = 000003;

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
proc contents data=&sp500_idx_tbl short; run;   -- gvkey iid gvkeyx from thru
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
  %can_read -- function-style macro: resolves to 1 if DS can be opened for
  reading, 0 if it is missing OR the user is not licensed for it.
  (EXIST() returns 1 for a table you cannot read; OPEN() fails silently.)
===========================================================================*/
%macro can_read(ds);
  %local dsid rc;
  %let dsid = %sysfunc(open(&ds));
  %if &dsid > 0 %then %do;
    %let rc = %sysfunc(close(&dsid));
    1
  %end;
  %else 0
%mend can_read;

/*===========================================================================
  %access_report -- one log line per source table: readable or not.
===========================================================================*/
%macro access_report;
  %local tbls i t;
  %let tbls = &funda_tbl &company_tbl &sp500_idx_tbl &ccm_link_tbl &sp500_tbl
              &cik_link_tbl &mda_tbl &rf_tbl;
  %do i = 1 %to %sysfunc(countw(&tbls, %str( )));
    %let t = %scan(&tbls, &i, %str( ));
    %if %can_read(&t) = 1 %then %put NOTE: [access] &t is readable.;
    %else %put WARNING: [access] &t is NOT readable (missing or not licensed).;
  %end;
%mend access_report;
%access_report;

/*===========================================================================
  %require_readable -- stop the submission if any listed table cannot be
  read, instead of letting every downstream step fail on empty inputs.
===========================================================================*/
%macro require_readable(tbls);
  %local i t bad;
  %let bad = 0;
  %do i = 1 %to %sysfunc(countw(&tbls, %str( )));
    %let t = %scan(&tbls, &i, %str( ));
    %if %can_read(&t) = 0 %then %do;
      %put ERROR: [require_readable] Cannot read &t (missing or not licensed).;
      %let bad = 1;
    %end;
  %end;
  %if &bad = 1 %then %abort cancel;
%mend require_readable;

/*===========================================================================
  %assert_unique -- write an ERROR to the log if DSN is not unique on KEYS.
  Data-step MERGE with duplicate keys on both sides is silently wrong, so
  every join output is checked. A missing data set or failed query is
  itself an ERROR (previously two empty counts compared equal and the
  macro reported a false pass).
===========================================================================*/
%macro assert_unique(dsn=, keys=);
  %local keylist nrows nkeys;
  %if not %sysfunc(exist(&dsn)) %then %do;
    %put ERROR: [assert_unique] &dsn does not exist -- an upstream step failed.;
    %return;
  %end;

  %let keylist = %sysfunc(translate(%sysfunc(compbl(&keys)), %str(,), %str( )));
  %let nrows = ;
  %let nkeys = ;
  proc sql noprint;
    select count(*) into :nrows trimmed from &dsn;
    select count(*) into :nkeys trimmed
      from (select distinct &keylist from &dsn);
  quit;

  %if %length(&nrows) = 0 or %length(&nkeys) = 0 %then
    %put ERROR: [assert_unique] could not count rows/keys of &dsn (check keys: &keys).;
  %else %if &nrows ne &nkeys %then
    %put ERROR: [assert_unique] &dsn has %eval(&nrows - &nkeys) duplicate row(s) on (&keys).;
  %else
    %put NOTE: [assert_unique] &dsn is unique on (&keys): &nrows rows.;
%mend assert_unique;
