/*===========================================================================
  00_setup_libraries.sas
  ESG Narrative Consistency & Discretionary Accruals — Albert Limani

  Purpose: declare all WRDS library references and provide diagnostic
  commands to verify table names on your specific WRDS node before running
  the rest of the pipeline. Table names below are the most common defaults;
  uncomment the proc datasets calls to confirm.
===========================================================================*/

options notes stimer source;

/*---------------------------------------------------------------------------
  MACRO PARAMETERS — edit these for your environment
---------------------------------------------------------------------------*/
%let wrds_path = /home/youruser;
%let out_path  = /home/youruser/esg_accruals;
%let start_yr  = 1994;
%let end_yr    = 2024;

/* Create output folder if it does not exist */
options dlcreatedir;
libname _outdir "&out_path.";
libname _outdir clear;

/*===========================================================================
  WRDS LIBRARY DECLARATIONS
===========================================================================*/
libname comp    '/wrds/comp/sasdata';        /* Compustat                  */
libname crsp    '/wrds/crsp/sasdata';        /* CRSP (monthly/daily)       */
libname ccm     '/wrds/comp/sasdata';        /* CCM link table lives here  */
libname wrdsapp '/wrds/wrdsapps/sasdata';    /* WRDS Apps (CIK link, etc.) */
libname wrdssec '/wrds/sec/sasdata';         /* SEC full-text filings      */

/*===========================================================================
  DIAGNOSTICS — run once to confirm table names on your node
===========================================================================*/
/*
proc datasets library=comp;    run;   -- look for: funda, ccmxpf_linktable
proc datasets library=crsp;    run;   -- look for: msp500list, mseind
proc datasets library=wrdsapp; run;   -- look for: wciklink, wciklinkhist
proc datasets library=wrdssec; run;   -- look for: mda_clean, rfactor, mda
*/

/*
  Common alternative table names encountered on different WRDS nodes:
    comp.ccmxpf_lnkhist       (older link table format)
    crsp.mseind                (index constituents, filter portno='0500')
    wrdsapp.wciklinkhist       (historical CIK crosswalk)
    wrdssec.mda                (may be mda / mda_clean / mda_text)
    wrdssec.rf                 (risk factor section)
*/
