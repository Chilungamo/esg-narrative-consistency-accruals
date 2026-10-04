/*===========================================================================
  03_esg_text_intensity.sas
  ESG word intensity in the MD&A and Risk Factor sections of each firm's
  10-K, using compiled Perl regexes (PRXPARSE + PRXNEXT).

  Alignment: each gvkey-datadate is matched to the FIRST original 10-K
  filed within &file_window days AFTER the fiscal year-end, and MD&A and
  Risk Factor text are taken from that same filing. (year(file_date) is
  NOT the fiscal year: a Dec-FYE firm files its FY t 10-K in year t+1.)

  Input:  WORK.DA_final (from 02), &cik_link_tbl, &mda_tbl, &rf_tbl
  Output: WORK.esg_panel -- one row per gvkey-fyear with section word
          counts and ESG / E / S / G intensities
===========================================================================*/

/*---------------------------------------------------------------------------
  Step 3.1 -- Candidate CIKs per gvkey-datadate:
  date-valid links from &cik_link_tbl  UNION  comp.company CIK
---------------------------------------------------------------------------*/
%macro build_gvkey_cik;
  proc sql;
    create table _cik_cand as
    select distinct gvkey, fyear, datadate, cik_company as cik_n
    from DA_final
    where not missing(cik_company);
  quit;

  %if %sysfunc(exist(&cik_link_tbl)) %then %do;
    proc sql;
      create table _cik_hist as
      select distinct a.gvkey, a.fyear, a.datadate,
             input(cats(b.cik), ?? 32.) as cik_n
      from DA_final a
      inner join &cik_link_tbl b
        on  a.gvkey = b.gvkey
        and (missing(b.&cik_link_start) or b.&cik_link_start <= a.datadate)
        and (missing(b.&cik_link_end)   or a.datadate <= b.&cik_link_end);
    quit;
  %end;
  %else %do;
    %put WARNING: [03] &cik_link_tbl not found -- using comp.company CIK only (no CIK history).;
    data _cik_hist; set _cik_cand (obs=0); run;
  %end;

  proc sql;
    create table gvkey_cik as
    select * from _cik_cand
    union
    select * from _cik_hist where not missing(cik_n);

    create table _cik_list as
    select distinct cik_n from gvkey_cik;
  quit;
%mend build_gvkey_cik;
%build_gvkey_cik;

/*---------------------------------------------------------------------------
  Step 3.2 -- ESG dictionaries

  Every truncated stem carries \w* so it matches its inflections
  ("emiss" -> emission, emissions); multi-word terms use [\s-]+ so they
  match across a space or hyphen. The whole alternation is wrapped in
  \b(...)\b, so terms WITHOUT \w* match as complete words only.
  With the previous  \b(emiss|...)\b  a stem could only match if the word
  ended exactly at the stem, so emissions / employees / sustainability /
  "audit committee" etc. were never counted.
  'whistleblow' is counted once (Governance), not in both S and G.
---------------------------------------------------------------------------*/
%macro esg_regex_init;
  rx_env = prxparse('/\b(' ||
    'carbon[\s-]+neutral\w*|low[\s-]+carbon|carbon[\s-]+footprint\w*|' ||
    'water[\s-]+usage|energy[\s-]+effic\w*|clean[\s-]+energ\w*|'        ||
    'net[\s-]+zero|scope[\s-]*[123]|'                                     ||
    'emiss\w*|carbon|greenhouse|climate|renewab\w*|sustainab\w*|'         ||
    'pollut\w*|biodiversit\w*|fossil|deforestat\w*|recycl\w*|ecolog\w*|'  ||
    'tcfd|ghg|methane|environmental'                                      ||
    ')\b/i');

  rx_soc = prxparse('/\b(' ||
    'health\s+and\s+safety|human[\s-]+rights?|gender[\s-]+pay|'          ||
    'pay[\s-]+equit\w*|human[\s-]+capital|social[\s-]+impact\w*|'         ||
    'supply[\s-]+chains?|modern[\s-]+slaver\w*|'                          ||
    'employe\w*|workforce|diversit\w*|inclusion|communit\w*|labou?r|'     ||
    'safety|training|talent|suppliers?|philanthrop\w*|csr|dei|'           ||
    'discriminat\w*'                                                      ||
    ')\b/i');

  rx_gov = prxparse('/\b(' ||
    'independ\w*\s+directors?|audit\s+committ\w*|exec\w*\s+compensation|' ||
    'anti[\s-]*corrupt\w*|risk\s+management|internal\s+controls?|'        ||
    'data\s+privac\w*|esg\s+report\w*|integrat\w*\s+report\w*|'           ||
    'boards?|governance|shareholders?|transparenc\w*|briber\w*|'          ||
    'complianc\w*|whistle[\s-]*blow\w*|prox(y|ies)|ethic\w*|'             ||
    'cyber[\s-]*secur\w*|fiduciar\w*|accountab\w*|gri|sasb'               ||
    ')\b/i');

  if missing(rx_env) or missing(rx_soc) or missing(rx_gov) then do;
    put 'ERROR: [03] ESG regex failed to compile.';
    stop;
  end;
%mend esg_regex_init;

/*---------------------------------------------------------------------------
  Step 3.3 -- Count matches per text row, then sum to one row per filing.
  Works whether a section is stored in one row or in several chunks.
---------------------------------------------------------------------------*/
%macro count_esg_section(tbl=, text_var=, suffix=);

  data _cnt_&suffix (keep=cik_n file_date form total_words
                          env_count soc_count gov_count trunc_flag);
    if 0 then set _cik_list;                    /* cik_n into the PDV    */
    if _n_ = 1 then do;
      declare hash h_cik(dataset: '_cik_list');
      h_cik.defineKey('cik_n');
      h_cik.defineDone();
    end;

    set &tbl (keep=&txt_cik &txt_date &txt_form &text_var
              where=(&txt_form in (&txt_forms)
                     and year(&txt_date) between &start_yr and %eval(&end_yr + 1)));

    length form $12;
    retain rx_env rx_soc rx_gov;
    array rx[3] rx_env rx_soc rx_gov;
    array ct[3] env_count soc_count gov_count;

    if _n_ = 1 then do;
      %esg_regex_init;
    end;

    cik_n = input(cats(&txt_cik), ?? 32.);
    if h_cik.check() ne 0 then delete;          /* not a sample firm     */

    file_date = &txt_date;
    form      = &txt_form;
    format file_date yymmdd10.;

    /* Words: split on blanks, tabs, CR/LF, form feeds ('s' modifier) */
    total_words = countw(&text_var, ' ', 's');

    /* A SAS character value tops out at 32,767 bytes; flag rows that hit
       the cap (possible truncation of the section text).                 */
    trunc_flag = (lengthn(&text_var) >= 32767);

    _stop = lengthn(&text_var);
    do _k = 1 to 3;
      ct[_k] = 0;
      if _stop > 0 then do;
        _start = 1;
        call prxnext(rx[_k], _start, _stop, &text_var, _pos, _len);
        do while (_pos > 0);
          ct[_k] = ct[_k] + 1;
          call prxnext(rx[_k], _start, _stop, &text_var, _pos, _len);
        end;
      end;
    end;
  run;

  proc sql;
    create table _sec_&suffix as
    select cik_n, file_date, form,
           sum(total_words) as words_&suffix,
           sum(env_count)   as env_n_&suffix,
           sum(soc_count)   as soc_n_&suffix,
           sum(gov_count)   as gov_n_&suffix,
           max(trunc_flag)  as trunc_&suffix
    from _cnt_&suffix
    where not missing(cik_n) and not missing(file_date)
    group by cik_n, file_date, form
    order by cik_n, file_date, form;
  quit;

  /* One filing per cik x file_date */
  data _sec_&suffix;
    set _sec_&suffix;
    by cik_n file_date;
    if first.file_date;
    drop form;
  run;

  proc sql;
    title "Section &suffix: filings and rows at the 32,767-byte cap";
    select count(*) as n_filings, sum(trunc_&suffix) as n_possibly_truncated
    from _sec_&suffix;
    title;
  quit;
%mend count_esg_section;

%count_esg_section(tbl=&mda_tbl, text_var=&mda_var, suffix=mda);
%count_esg_section(tbl=&rf_tbl,  text_var=&rf_var,  suffix=rf);

/*---------------------------------------------------------------------------
  Step 3.4 -- Combine sections by filing, then match filings to FYEs
---------------------------------------------------------------------------*/
proc sql;
  create table filings as
  select coalesce(m.cik_n, r.cik_n)         as cik_n,
         coalesce(m.file_date, r.file_date) as file_date format=yymmdd10.,
         m.words_mda, m.env_n_mda, m.soc_n_mda, m.gov_n_mda,
         r.words_rf,  r.env_n_rf,  r.soc_n_rf,  r.gov_n_rf
  from _sec_mda m
  full join _sec_rf r
    on m.cik_n = r.cik_n and m.file_date = r.file_date;

  create table _match as
  select g.gvkey, g.fyear, g.datadate, f.*
  from gvkey_cik g
  inner join filings f
    on  g.cik_n = f.cik_n
    and f.file_date >  g.datadate
    and f.file_date <= g.datadate + &file_window
  order by gvkey, datadate, file_date;
quit;

/* First filing after each FYE ... */
data _match;
  set _match;
  by gvkey datadate;
  if first.datadate;
run;

/* ... and each filing assigned to at most one FYE (the latest one before it) */
proc sort data=_match; by gvkey file_date datadate; run;
data _match;
  set _match;
  by gvkey file_date;
  if last.file_date;
run;

%macro section_intensity(sec);
  if words_&sec > 0 then do;
    esg_int_&sec = (env_n_&sec + soc_n_&sec + gov_n_&sec) / words_&sec;
    env_int_&sec = env_n_&sec / words_&sec;
    soc_int_&sec = soc_n_&sec / words_&sec;
    gov_int_&sec = gov_n_&sec / words_&sec;
  end;
%mend section_intensity;

proc sort data=_match; by gvkey fyear; run;

data esg_panel;
  set _match;
  by gvkey fyear;

  %section_intensity(mda);
  %section_intensity(rf);

  /* No mandatory Item 1A before FYE &rf_start_date */
  if datadate < "&rf_start_date"d then
    call missing(words_rf, env_n_rf, soc_n_rf, gov_n_rf,
                 esg_int_rf, env_int_rf, soc_int_rf, gov_int_rf);

  label esg_int_mda = 'ESG words / total words, MD&A'
        esg_int_rf  = 'ESG words / total words, Risk Factors';
run;

%assert_unique(dsn=esg_panel, keys=gvkey fyear);
