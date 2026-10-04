/*===========================================================================
  04_enci_construction.sas
  ESG Narrative Consistency Index (ENCI):
    ENCI_it = -|Z(ESG_int_MDA)_it - Z(ESG_int_RF)_it|
  Z-scores standardized within fiscal year.
  Higher ENCI (-> 0) = more consistent narrative across sections.
  Lower (more negative) ENCI = greater divergence.
  ENCI is defined only for FYE >= &rf_start_date (Item 1A requirement).

  Input:  WORK.DA_final, WORK.esg_panel
  Output: WORK.panel_enci -- DA_final rows with raw intensities, Z-scores,
          ENCI, pillar ENCI, temporal ENCI, and ESG_INTENSITY
===========================================================================*/

proc sort data=DA_final;  by gvkey fyear; run;
proc sort data=esg_panel; by gvkey fyear; run;

/*---------------------------------------------------------------------------
  Step 4.1 -- Merge (keep accrual-sample rows only) and create Z_ copies.
  PROC STDIZE overwrites its VAR variables in place, so we standardize
  COPIES and keep the raw intensities for ESG_INTENSITY and the export.
---------------------------------------------------------------------------*/
data main_panel;
  merge DA_final  (in=in_da)
        esg_panel (keep=gvkey fyear file_date words_mda words_rf
                        esg_int_mda esg_int_rf env_int_mda env_int_rf
                        soc_int_mda soc_int_rf gov_int_mda gov_int_rf);
  by gvkey fyear;
  if in_da;

  Z_esg_mda = esg_int_mda;  Z_esg_rf = esg_int_rf;
  Z_env_mda = env_int_mda;  Z_env_rf = env_int_rf;
  Z_soc_mda = soc_int_mda;  Z_soc_rf = soc_int_rf;
  Z_gov_mda = gov_int_mda;  Z_gov_rf = gov_int_rf;
run;

proc sort data=main_panel; by fyear gvkey; run;

proc stdize data=main_panel out=panel_std method=std;
  by fyear;
  var Z_esg_mda Z_esg_rf
      Z_env_mda Z_env_rf
      Z_soc_mda Z_soc_rf
      Z_gov_mda Z_gov_rf;
run;

/*---------------------------------------------------------------------------
  Step 4.2 -- Cross-sectional ENCI (MD&A vs Risk Factors, same filing)
---------------------------------------------------------------------------*/
data panel_enci;
  set panel_std;

  if nmiss(Z_esg_mda, Z_esg_rf) = 0 then ENCI     = -abs(Z_esg_mda - Z_esg_rf);
  if nmiss(Z_env_mda, Z_env_rf) = 0 then ENCI_env = -abs(Z_env_mda - Z_env_rf);
  if nmiss(Z_soc_mda, Z_soc_rf) = 0 then ENCI_soc = -abs(Z_soc_mda - Z_soc_rf);
  if nmiss(Z_gov_mda, Z_gov_rf) = 0 then ENCI_gov = -abs(Z_gov_mda - Z_gov_rf);

  /* Step 4.4 -- overall ESG intensity from the RAW (unstandardized) values */
  if nmiss(esg_int_mda, esg_int_rf) = 0 then
    ESG_INTENSITY = (esg_int_mda + esg_int_rf) / 2;

  label ENCI          = 'ESG Narrative Consistency Index'
        ENCI_env      = 'Environmental Narrative Consistency'
        ENCI_soc      = 'Social Narrative Consistency'
        ENCI_gov      = 'Governance Narrative Consistency'
        ESG_INTENSITY = 'Mean of MD&A and RF ESG intensity (raw)';
run;

/*---------------------------------------------------------------------------
  Step 4.3 -- Temporal ENCI (year-over-year stability within firm).
  Lag only from the immediately preceding fiscal year.
---------------------------------------------------------------------------*/
proc sort data=panel_enci; by gvkey fyear; run;

data panel_enci;
  set panel_enci;
  by gvkey fyear;

  _yr_lag    = lag(fyear);
  _z_mda_lag = lag(Z_esg_mda);
  _z_rf_lag  = lag(Z_esg_rf);

  if first.gvkey or _yr_lag ne fyear - 1 then call missing(_z_mda_lag, _z_rf_lag);

  if nmiss(Z_esg_mda, _z_mda_lag) = 0 then ENCI_t_mda = -abs(Z_esg_mda - _z_mda_lag);
  if nmiss(Z_esg_rf,  _z_rf_lag)  = 0 then ENCI_t_rf  = -abs(Z_esg_rf  - _z_rf_lag);

  drop _yr_lag _z_mda_lag _z_rf_lag;

  label ENCI_t_mda = 'Temporal ESG Consistency (MD&A year-over-year)'
        ENCI_t_rf  = 'Temporal ESG Consistency (RF year-over-year)';
run;

%assert_unique(dsn=panel_enci, keys=gvkey fyear);

proc sql;
  title 'ENCI coverage by fiscal year';
  select fyear, count(*) as n_firm_years, n(ENCI) as n_enci,
         n(esg_int_mda) as n_mda, n(esg_int_rf) as n_rf
  from panel_enci
  group by fyear;
  title;
quit;
