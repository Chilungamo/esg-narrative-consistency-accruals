#!/bin/bash
#------------------------------------------------------------------------------
# run_all.sh -- submit the SAS pipeline as a batch job on the WRDS Cloud grid.
#
#   cd ~/esg_accruals/sas
#   qsub run_all.sh          # submit (returns immediately)
#   qstat                    # check whether it is still running
#
# When it finishes, run_all.log / run_all.lst are in this directory and a
# summary of errors/warnings is in run_all.check.txt.
#------------------------------------------------------------------------------
#$ -cwd
#$ -N esg_accruals
#$ -j y
#$ -o run_all.job.out
# Uncomment to be emailed when the job ends or aborts:
##$ -m ea
##$ -M you@example.edu

set -u
cd "$(dirname "$0")" 2>/dev/null || true
# Under qsub, $0 is a spool copy; -cwd already put us in the submit directory.
[ -f run_all.sas ] || cd "${SGE_O_WORKDIR:-$PWD}"

export CODE_PATH="$PWD"
echo "[run_all.sh] $(date) host=$(hostname) CODE_PATH=$CODE_PATH"

sas run_all.sas -log run_all.log -print run_all.lst -noterminal
rc=$?
echo "[run_all.sh] $(date) sas exit code=$rc  (0=ok, 1=warnings, 2=errors)"

if command -v python3 >/dev/null 2>&1; then
  python3 check_log.py run_all.log > run_all.check.txt
  echo "[run_all.sh] log summary written to run_all.check.txt"
  cat run_all.check.txt
fi
exit $rc
