@echo off
REM (non-ascii note removed; see FIX_REPORT)
setlocal
cd /d %~dp0
call "%~dp0..\..\..\..\..\sim\p4gates\p4env.bat" || exit /b 1
set "ROOT=%REPO_ROOT%"
"%PY%" "%~dp0mk_mut_accmargin.py" || exit /b 1
call "%~dp0run_accmargin_gate.bat" "%~dp0mut\wrapper_accmargin_bad.v" > "%~dp0negctl_accmargin.log" 2>&1
if errorlevel 1 (
  echo [NEGCTL OK] acc_margin single-port mutant rejected
) else (
  echo [NEGCTL FAIL] acc_margin single-port mutant ACCEPTED
  exit /b 1
)
call "%~dp0run_accmargin_gate.bat" > "%~dp0accmargin_def.log" 2>&1
if errorlevel 1 (type "%~dp0accmargin_def.log" & exit /b 1)
echo ACC_MARGIN_NEGCTL_PASS
exit /b 0
