/*===========================================================================
  03_esg_text_intensity.sas
  ESG Intensity from 10-K MD&A and Risk Factor sections using a compiled
  PRXPARSE bag-of-words approach (Environment / Social / Governance).

  Input:  WORK.DA_final (from 02_modified_jones_dac.sas)
          wrdsapp.wciklink, wrdssec.mda_clean, wrdssec.rfactor
  Output: WORK.esg_panel — gvkey-fyear panel with ESG word intensities
===========================================================================*/

/*---------------------------------------------------------------------------
  Step 3.1 — GVKEY -> CIK crosswalk and filing-level text pulls
---------------------------------------------------------------------------*/
proc sql;
  create table gvkey_cik as
  select distinct a.gvkey, a.fyear, a.datadate,
         b.cik
  from DA_final a
  left join wrdsapp.wciklink b
    on a.gvkey = b.gvkey
  where not missing(b.cik);
quit;

proc sql;
  create table cik_list as select distinct cik from gvkey_cik;
quit;

/* MD&A section text */
proc sql;
  create table mda_raw as
  select a.cik,
         year(a.file_date) as fyear,
         a.file_date,
         a.mda_text
  from wrdssec.mda_clean a
  inner join cik_list b on a.cik = b.cik
  where year(a.file_date) between &start_yr and &end_yr
    and a.form_type in ('10-K','10-K405','10-KSB');
quit;

/* Risk Factor section text */
proc sql;
  create table rf_raw as
  select a.cik,
         year(a.file_date) as fyear,
         a.file_date,
         a.rf_text
  from wrdssec.rfactor a
  inner join cik_list b on a.cik = b.cik
  where year(a.file_date) between &start_yr and &end_yr
    and a.form_type in ('10-K','10-K405','10-KSB');
quit;

/*---------------------------------------------------------------------------
  Step 3.2 — ESG bag-of-words counter using PRXPARSE + PRXNEXT

  IMPORTANT: SAS string literals passed directly to PRXMATCH() are capped
  at 262 bytes. The dictionaries below exceed that, so each pattern is
  compiled ONCE per data step with PRXPARSE() (concatenated from short
  pieces) and retained, then scanned with PRXNEXT() to count ALL matches
  (not just the first).
---------------------------------------------------------------------------*/
%macro count_esg_section(dsn_in=, text_var=, dsn_out=, suffix=);
data &dsn_out;
  set &dsn_in;

  retain rx_env rx_soc rx_gov;

  if _n_ = 1 then do;
    /* ENVIRONMENT dictionary */
    rx_env = prxparse('/\b(emiss|carbon|greenhouse|climate|renewab|sustainab|'||
                      'pollut|biodiversit|water.usage|energy.effic|fossil|'||
                      'deforestat|recycl|ecolog|clean.energ|net.zero|'||
                      'scope_1|scope_2|scope_3|tcfd|carbon.neutral|'||
                      'low.carbon|ghg|methane|carbon.footprint|environmental)\b/i');

    /* SOCIAL dictionary */
    rx_soc = prxparse('/\b(employe|workforce|diversit|inclusion|human.right|'||
                      'communit|labour|labor|safety|health.and.safety|training|'||
                      'talent|gender.pay|pay.equit|supplier|human.capital|'||
                      'philanthrop|csr|social.impact|dei|discriminat|'||
                      'whistleblow|supply.chain|modern.slaver)\b/i');

    /* GOVERNANCE dictionary */
    rx_gov = prxparse('/\b(board|governance|independ.director|audit.committ|'||
                      'exec.compensation|shareholder|transparenc|'||
                      'anti.corrupt|briber|complianc|risk.management|'||
                      'internal.control|whistleblow|proxy|ethic|'||
                      'cybersecur|data.privac|fiduciar|accountab|'||
                      'esg.report|integrat.report|gri|sasb)\b/i');
  end;

  text_lc = lowcase(&text_var);
  if missing(text_lc) then text_lc = '';

  total_words = countw(text_lc, ' ');

  /* Environment matches */
  env_count = 0;
  _start = 1; _stop = length(text_lc);
  call prxnext(rx_env, _start, _stop, text_lc, _pos, _len);
  do while(_pos > 0);
    env_count + 1;
    call prxnext(rx_env, _start, _stop, text_lc, _pos, _len);
  end;

  /* Social matches */
  soc_count = 0;
  _start = 1;
  call prxnext(rx_soc, _start, _stop, text_lc, _pos, _len);
  do while(_pos > 0);
    soc_count + 1;
    call prxnext(rx_soc, _start, _stop, text_lc, _pos, _len);
  end;

  /* Governance matches */
  gov_count = 0;
  _start = 1;
  call prxnext(rx_gov, _start, _stop, text_lc, _pos, _len);
  do while(_pos > 0);
    gov_count + 1;
    call prxnext(rx_gov, _start, _stop, text_lc, _pos, _len);
  end;

  esg_count = env_count + soc_count + gov_count;

  if total_words > 0 then do;
    esg_int_&suffix = esg_count / total_words;
    env_int_&suffix = env_count / total_words;
    soc_int_&suffix = soc_count / total_words;
    gov_int_&suffix = gov_count / total_words;
  end;
  else do;
    esg_int_&suffix = .;
    env_int_&suffix = .;
    soc_int_&suffix = .;
    gov_int_&suffix = .;
  end;

  drop text_lc _start _stop _pos _len rx_env rx_soc rx_gov;
run;
%mend;

%count_esg_section(dsn_in=mda_raw, text_var=mda_text, dsn_out=mda_esg, suffix=mda);
%count_esg_section(dsn_in=rf_raw,  text_var=rf_text,  dsn_out=rf_esg,  suffix=rf);

/*---------------------------------------------------------------------------
  Step 3.3 — Merge MD&A + RF intensities, link back to GVKEY
---------------------------------------------------------------------------*/
proc sort data=mda_esg; by cik fyear; run;
proc sort data=rf_esg;  by cik fyear; run;

data esg_combined;
  merge mda_esg (keep=cik fyear esg_int_mda env_int_mda soc_int_mda gov_int_mda)
        rf_esg  (keep=cik fyear esg_int_rf  env_int_rf  soc_int_rf  gov_int_rf);
  by cik fyear;
run;

proc sort data=gvkey_cik;    by cik fyear; run;
proc sort data=esg_combined; by cik fyear; run;

data esg_panel;
  merge esg_combined gvkey_cik (keep=gvkey fyear cik);
  by cik fyear;
  if missing(gvkey) then delete;
run;
