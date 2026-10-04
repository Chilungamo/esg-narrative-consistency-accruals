/*===========================================================================
  05_regression_models.sas
  Final analysis panel, descriptive statistics, and fixed-effects
  regressions with standard errors clustered by firm.

  Input:  WORK.panel_enci (from 04), WORK.jones_coefs (from 02)
  Output: WORK.analysis_panel, WORK.reg_coefs, and
          &out_path./ESG_DA_panel.xlsx with sheets
          MainPanel / JonesCoefficients / Coefficients
===========================================================================*/

/*---------------------------------------------------------------------------
  Step 5.1 -- Analysis panel with controls
---------------------------------------------------------------------------*/
data analysis_panel;
  set panel_enci;

  /* SIZE = log(total assets) */
  if at > 0 then SIZE = log(at);

  /* LEVERAGE = total liabilities / total assets */
  if at > 0 and not missing(lt) then LEVERAGE = lt / at;

  /* MARKET-TO-BOOK. prcc_f x csho is populated throughout the sample;
     mkvalt is sparse in early years and is only a fallback.            */
  if nmiss(prcc_f, csho) = 0 then MKTVAL = prcc_f * csho;
  else if not missing(mkvalt)  then MKTVAL = mkvalt;
  if ceq > 0 and not missing(MKTVAL) then MTB = MKTVAL / ceq;

  keep gvkey fyear datadate file_date sich sic_final SIC2 permno cik_company
       DAC ABS_DAC PM_DAC ABS_PM_DAC TA NDAC ROA
       ENCI ENCI_env ENCI_soc ENCI_gov ENCI_t_mda ENCI_t_rf
       ESG_INTENSITY esg_int_mda esg_int_rf
       env_int_mda env_int_rf soc_int_mda soc_int_rf
       gov_int_mda gov_int_rf
       Z_esg_mda Z_esg_rf words_mda words_rf
       SIZE LEVERAGE MTB
       at lt ceq MKTVAL oancf;
run;

/* Winsorize at 1/99 within fiscal year (matches docs/variable_definitions.md) */
%winsorize(dsn=analysis_panel,
           vars=ABS_DAC ABS_PM_DAC ENCI ENCI_env ENCI_soc ENCI_gov
                ESG_INTENSITY LEVERAGE MTB,
           byvar=fyear);

/* Interaction term (after winsorizing its components) */
data analysis_panel;
  set analysis_panel;
  if nmiss(ESG_INTENSITY, ENCI) = 0 then ESG_x_ENCI = ESG_INTENSITY * ENCI;
run;

/*---------------------------------------------------------------------------
  Step 5.2 -- Descriptive statistics (Table 1, Table 2)
---------------------------------------------------------------------------*/
proc means data=analysis_panel n mean std p25 median p75 min max;
  var ABS_DAC ABS_PM_DAC ENCI ENCI_env ENCI_soc ENCI_gov
      ESG_INTENSITY SIZE LEVERAGE MTB ROA;
  title 'Table 1 -- Summary Statistics';
run;
title;

proc corr data=analysis_panel pearson spearman;
  var ABS_DAC ENCI ESG_INTENSITY SIZE LEVERAGE MTB ROA;
  title 'Table 2 -- Correlation Matrix';
run;
title;

/*---------------------------------------------------------------------------
  Step 5.3 -- Firm + year fixed effects, SEs clustered by firm.
  PROC GLM's SEs assume independent, homoskedastic errors, which overstates
  significance in a firm panel; PROC SURVEYREG gives cluster-robust SEs.
  The ~1,000 firm-dummy rows are captured but not printed.
---------------------------------------------------------------------------*/
%let controls = SIZE LEVERAGE MTB ROA;

%macro fe_reg(dv=, x=, tag=, title=);
  ods exclude all;
  proc surveyreg data=analysis_panel;
    cluster gvkey;
    class gvkey fyear;
    model &dv = &x &controls gvkey fyear / solution clparm;
    ods output ParameterEstimates=_pe_&tag
               FitStatistics=_fit_&tag
               DataSummary=_ds_&tag;
  run;
  ods exclude none;

  data _pe_&tag;
    length model dv $16 Parameter $64;
    set _pe_&tag;
    model = "&tag";
    dv    = "&dv";
    if scan(Parameter, 1, ' ') in ('gvkey', 'fyear') then delete;
  run;

  title "&title  (firm and year FE, SEs clustered by firm)";
  proc print data=_ds_&tag  noobs; run;
  proc print data=_fit_&tag noobs; run;
  proc print data=_pe_&tag  noobs; run;
  title;
%mend fe_reg;

/* H1 -- baseline */
%fe_reg(dv=ABS_DAC, x=ENCI, tag=H1, title=Table 3 -- Baseline: |DA| on ENCI);

/* H2 -- ESG intensity x ENCI */
%fe_reg(dv=ABS_DAC, x=ESG_INTENSITY ENCI ESG_x_ENCI, tag=H2,
        title=Table 4 -- Main: |DA| on ESG Intensity x ENCI);

/* Sub-pillars */
%fe_reg(dv=ABS_DAC, x=ENCI_env, tag=ENV, title=Sub-pillar: |DA| on ENCI_env);
%fe_reg(dv=ABS_DAC, x=ENCI_soc, tag=SOC, title=Sub-pillar: |DA| on ENCI_soc);
%fe_reg(dv=ABS_DAC, x=ENCI_gov, tag=GOV, title=Sub-pillar: |DA| on ENCI_gov);

/* Robustness -- performance-matched |DA| */
%fe_reg(dv=ABS_PM_DAC, x=ESG_INTENSITY ENCI ESG_x_ENCI, tag=H2_PM,
        title=Robustness -- |PM-DA| as dependent variable);

data reg_coefs;
  set _pe_H1 _pe_H2 _pe_ENV _pe_SOC _pe_GOV _pe_H2_PM;
run;

/*---------------------------------------------------------------------------
  Step 5.4 -- Export panel + Jones coefficients + regression coefficients.
  The LIBNAME XLSX engine writes one sheet per data set; the workbook is
  deleted first so no stale sheets survive a re-run.
---------------------------------------------------------------------------*/
%macro export_xlsx;
  %local xf fref rc;
  %let xf = &out_path./ESG_DA_panel.xlsx;
  %if %sysfunc(fileexist(&xf)) %then %do;
    %let fref = _xlsdel;
    %let rc = %sysfunc(filename(fref, &xf));
    %let rc = %sysfunc(fdelete(&fref));
    %let rc = %sysfunc(filename(fref));
  %end;

  libname xl xlsx "&xf";
  data xl.MainPanel;         set analysis_panel; run;
  data xl.JonesCoefficients; set jones_coefs;    run;
  data xl.Coefficients;      set reg_coefs;      run;
  libname xl clear;

  %put NOTE: [05] Exported &xf;
%mend export_xlsx;
%export_xlsx;
