/*===========================================================================
  run_all.sas -- runs the full SAS pipeline in one WRDS SAS Studio session.
  Edit code_path to the folder holding these scripts.
===========================================================================*/
%let code_path = /home/youruser/esg_accruals/sas;

%include "&code_path./00_setup_libraries.sas";
%include "&code_path./01_sp500_universe.sas";
%include "&code_path./02_modified_jones_dac.sas";
%include "&code_path./03_esg_text_intensity.sas";
%include "&code_path./04_enci_construction.sas";
%include "&code_path./05_regression_models.sas";
