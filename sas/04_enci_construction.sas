/*===========================================================================
  04_enci_construction.sas
  ESG Narrative Consistency Index (ENCI):
    ENCI_it = -|Z(ESG_int_MDA)_it - Z(ESG_int_RF)_it|
  Z-scores standardized within fiscal year.
  Higher ENCI (-> 0) = more consistent narrative across sections.
  Lower (more negative) ENCI = greater divergence.

  Input:  WORK.DA_final, WORK.esg_panel
  Output: WORK.panel_enci — full panel with ENCI, sub-pillar ENCI,
          temporal ENCI, and overall ESG_INTENSITY
===========================================================================*/

/* Merge ESG panel onto accruals panel */
proc sort data=DA_final; by gvkey fyear; run;
proc sort data=esg_panel; by gvkey fyear; run;

data main_panel;
  merge DA_final esg_panel;
  by gvkey fyear;
run;

/*---------------------------------------------------------------------------
  Step 4.1 — Standardize ESG intensities within fiscal year
---------------------------------------------------------------------------*/
proc sort data=main_panel; by fyear gvkey; run;

proc stdize data=main_panel out=panel_std method=std;
  by fyear;
  var esg_int_mda esg_int_rf
      env_int_mda env_int_rf
      soc_int_mda soc_int_rf
      gov_int_mda gov_int_rf;
run;

data panel_std;
  set panel_std;
  rename esg_int_mda = Z_esg_mda
         esg_int_rf  = Z_esg_rf
         env_int_mda = Z_env_mda
         env_int_rf  = Z_env_rf
         soc_int_mda = Z_soc_mda
         soc_int_rf  = Z_soc_rf
         gov_int_mda = Z_gov_mda
         gov_int_rf  = Z_gov_rf;
run;

/*---------------------------------------------------------------------------
  Step 4.2 — Compute ENCI (cross-section: MD&A vs Risk Factors, same year)
---------------------------------------------------------------------------*/
data panel_enci;
  set panel_std;

  if nmiss(Z_esg_mda, Z_esg_rf) = 0 then
    ENCI = -abs(Z_esg_mda - Z_esg_rf);

  if nmiss(Z_env_mda, Z_env_rf) = 0 then
    ENCI_env = -abs(Z_env_mda - Z_env_rf);

  if nmiss(Z_soc_mda, Z_soc_rf) = 0 then
    ENCI_soc = -abs(Z_soc_mda - Z_soc_rf);

  if nmiss(Z_gov_mda, Z_gov_rf) = 0 then
    ENCI_gov = -abs(Z_gov_mda - Z_gov_rf);

  label ENCI     = 'ESG Narrative Consistency Index'
        ENCI_env = 'Environmental Narrative Consistency'
        ENCI_soc = 'Social Narrative Consistency'
        ENCI_gov = 'Governance Narrative Consistency';
run;

/*---------------------------------------------------------------------------
  Step 4.3 — Temporal ENCI (year-over-year stability within firm)
---------------------------------------------------------------------------*/
proc sort data=panel_enci; by gvkey fyear; run;

data panel_enci;
  set panel_enci;
  by gvkey fyear;

  retain _z_mda_lag _z_rf_lag;

  if first.gvkey then do;
    _z_mda_lag = .;
    _z_rf_lag  = .;
  end;

  if nmiss(Z_esg_mda, _z_mda_lag) = 0 then
    ENCI_t_mda = -abs(Z_esg_mda - _z_mda_lag);

  if nmiss(Z_esg_rf, _z_rf_lag) = 0 then
    ENCI_t_rf  = -abs(Z_esg_rf  - _z_rf_lag);

  _z_mda_lag = Z_esg_mda;
  _z_rf_lag  = Z_esg_rf;

  drop _z_mda_lag _z_rf_lag;

  label ENCI_t_mda = 'Temporal ESG Consistency (MD&A year-over-year)'
        ENCI_t_rf  = 'Temporal ESG Consistency (RF year-over-year)';
run;

/*---------------------------------------------------------------------------
  Step 4.4 — Overall ESG_INTENSITY = average of MD&A and RF intensities
---------------------------------------------------------------------------*/
data panel_enci;
  set panel_enci;
  if nmiss(esg_int_mda, esg_int_rf) = 0 then
    ESG_INTENSITY = (esg_int_mda + esg_int_rf) / 2;
run;
