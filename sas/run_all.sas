/*===========================================================================
  run_all.sas -- runs the full SAS pipeline (00 -> 05) in one session.

  Batch (WRDS Cloud):  qsub run_all.sh        (see run_all.sh)
  Interactive (SAS Studio): define code_path first, then include this file:
      %let code_path = /home/<inst>/<user>/esg_accruals/sas;
      %include "&code_path./run_all.sas";

  Each step is bracketed by "[run_all] >>>" / "<<<" log markers so that
  check_log.py can attribute errors and warnings to a program. The includes
  are in open code (not a macro loop) so each marker is written after the
  previous program's steps have actually run.
===========================================================================*/
%macro _set_code_path;
  %global code_path;
  /* Resolution order: macro var already set > env var CODE_PATH > default */
  %if %length(&code_path) = 0 %then %let code_path = %sysget(CODE_PATH);
  %if %length(&code_path) = 0 %then %let code_path = %sysget(HOME)/esg_accruals/sas;
%mend _set_code_path;
%_set_code_path
%put NOTE: [run_all] code_path = &code_path;

%macro _start(p);
  %global _t0;
  %let _t0 = %sysfunc(datetime());
  %put NOTE: [run_all] >>> &p start %sysfunc(datetime(), datetime20.);
%mend _start;
%macro _end(p);
  %put NOTE: [run_all] <<< &p end syscc=&syscc elapsed=%sysevalf(%sysfunc(datetime()) - &_t0, ceil)s;
%mend _end;

%_start(00_setup_libraries)
%include "&code_path./00_setup_libraries.sas" / source2;
%_end(00_setup_libraries)

%_start(01_sp500_universe)
%include "&code_path./01_sp500_universe.sas" / source2;
%_end(01_sp500_universe)

%_start(02_modified_jones_dac)
%include "&code_path./02_modified_jones_dac.sas" / source2;
%_end(02_modified_jones_dac)

%_start(03_esg_text_intensity)
%include "&code_path./03_esg_text_intensity.sas" / source2;
%_end(03_esg_text_intensity)

%_start(04_enci_construction)
%include "&code_path./04_enci_construction.sas" / source2;
%_end(04_enci_construction)

%_start(05_regression_models)
%include "&code_path./05_regression_models.sas" / source2;
%_end(05_regression_models)

%put NOTE: [run_all] Finished. Final SYSCC=&syscc;
