/*===========================================================================
  05_regression_models.sas
  Final analysis panel construction, descriptive stats, and regressions.

  Input:  WORK.panel_enci (from 04_enci_construction.sas)
  Output: WORK.analysis_panel, regression tables, and
          &out_path./ESG_DA_panel.xlsx (MainPanel + JonesCoefficients)
===========================================================================*/

/*---------------------------------------------------------------------------
  Step 5.1 — Build analysis panel with control variables
---------------------------------------------------------------------------*/
data analysis_panel;
  set panel_enci;

  /* SIZE = log(total assets) */
  if at > 0 then SIZE = log(at);

  /* LEVERAGE = total liabilities / total assets */
  if at > 0 and not missing(lt) then LEVERAGE = lt / at;

  /* MARKET-TO-BOOK = market value of equity / book equity */
  if ceq > 0 and not missing(mkvalt) then MTB = mkvalt / ceq;

  keep gvkey fyear datadate sich SIC2
       DAC ABS_DAC PM_DAC ABS_PM_DAC TA NDAC ROA
       ENCI ENCI_env ENCI_soc ENCI_gov ENCI_t_mda ENCI_t_rf
       ESG_INTENSITY esg_int_mda esg_int_rf
       env_int_mda env_int_rf soc_int_mda soc_int_rf
       gov_int_mda gov_int_rf
       Z_esg_mda Z_esg_rf
       SIZE LEVERAGE MTB ROA
       at lt ceq mkvalt oancf permno cik;
run;

%winsorize(dsn=analysis_panel, var=LEVERAGE,      byvar=fyear);
%winsorize(dsn=analysis_panel, var=MTB,           byvar=fyear);
%winsorize(dsn=analysis_panel, var=ESG_INTENSITY, byvar=fyear);
%winsorize(dsn=analysis_panel, var=ENCI,          byvar=fyear);

/* Interaction term */
data analysis_panel;
  set analysis_panel;
  ESG_x_ENCI = ESG_INTENSITY * ENCI;
run;

/*---------------------------------------------------------------------------
  Step 5.2 — Descriptive statistics (Table 1, Table 2)
---------------------------------------------------------------------------*/
proc means data=analysis_panel n mean std p25 median p75 min max;
  var ABS_DAC ABS_PM_DAC ENCI ENCI_env ENCI_soc ENCI_gov
      ESG_INTENSITY SIZE LEVERAGE MTB ROA;
  title 'Table 1 -- Summary Statistics';
run; title;

proc corr data=analysis_panel pearson spearman;
  var ABS_DAC ENCI ESG_INTENSITY SIZE LEVERAGE MTB ROA;
  title 'Table 2 -- Correlation Matrix';
run; title;

/*---------------------------------------------------------------------------
  Step 5.3 — Baseline regression (H1): |DA| on ENCI + controls + FE
---------------------------------------------------------------------------*/
proc glm data=analysis_panel;
  class gvkey fyear;
  model ABS_DAC = ENCI SIZE LEVERAGE MTB ROA gvkey fyear
                / solution ss3 clparm;
  output out=reg1_out p=pred1 r=resid1;
  title 'Table 3 -- Baseline: |DA| on ENCI';
run; title;

/*---------------------------------------------------------------------------
  Step 5.4 — Main model (H2): ESG Intensity x ENCI interaction
---------------------------------------------------------------------------*/
proc glm data=analysis_panel;
  class gvkey fyear;
  model ABS_DAC = ESG_INTENSITY ENCI ESG_x_ENCI
                  SIZE LEVERAGE MTB ROA gvkey fyear
                / solution ss3 clparm;
  output out=reg2_out p=pred2 r=resid2;
  title 'Table 4 -- Main: |DA| on ESG Intensity x ENCI';
run; title;

/*---------------------------------------------------------------------------
  Step 5.5 — Sub-pillar regressions (Environment / Social / Governance)
---------------------------------------------------------------------------*/
%macro pillar_reg(pillar=);
proc glm data=analysis_panel;
  class gvkey fyear;
  model ABS_DAC = ENCI_&pillar SIZE LEVERAGE MTB ROA gvkey fyear
                / solution ss3 clparm;
  title "Sub-pillar: |DA| on ENCI_&pillar";
run; title;
%mend;
%pillar_reg(pillar=env);
%pillar_reg(pillar=soc);
%pillar_reg(pillar=gov);

/*---------------------------------------------------------------------------
  Step 5.6 — Robustness: performance-matched |DA|
---------------------------------------------------------------------------*/
proc glm data=analysis_panel;
  class gvkey fyear;
  model ABS_PM_DAC = ESG_INTENSITY ENCI ESG_x_ENCI
                     SIZE LEVERAGE MTB ROA gvkey fyear
                   / solution ss3 clparm;
  title 'Robustness -- |PM-DA| as dependent variable';
run; title;

/*---------------------------------------------------------------------------
  Step 5.7 — Export final panel + Jones coefficients to Excel
---------------------------------------------------------------------------*/
%let rc = %sysfunc(dcreate(esg_accruals, &wrds_path.));

proc export data=analysis_panel
  outfile="&out_path./ESG_DA_panel.xlsx"
  dbms=xlsx replace;
  sheet='MainPanel';
run;

proc export data=jones_coefs
  outfile="&out_path./ESG_DA_panel.xlsx"
  dbms=xlsx replace;
  sheet='JonesCoefficients';
run;
