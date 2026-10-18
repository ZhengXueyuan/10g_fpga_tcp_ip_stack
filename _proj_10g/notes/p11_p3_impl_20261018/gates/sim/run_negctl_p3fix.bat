@echo off
REM P11 P3 fix-round negative controls (H-1/H-2/M-5):
REM   1) win_pool_mgr stale  : accept cross-port late rel -> churn arm 5c must fail
REM   2) win_pool_mgr m5single: single read port -> churn M-5 asserts must fail
REM   3) retx staleowner     : no owner gate -> retx arm F must fail
REM   usage: run_negctl_p3fix.bat
setlocal
cd /d %~dp0
call "%~dp0..\..\..\..\..\sim\p4gates\p4env.bat" || exit /b 1
"%PY%" "%~dp0mk_mut_wpm.py" || exit /b 1
"%PY%" "%~dp0mk_mut_retx.py" || exit /b 1
"%PY%" "%~dp0mk_mut_static.py" || exit /b 1
set "BAD=0"

call "%~dp0run_p3fix_static_gate.bat" "%~dp0mut\wrapper_slowmerge_reset_bad.v" > "%~dp0negctl_p3_static_reset.log" 2>&1
if errorlevel 1 (echo [NEGCTL OK] slow_merge reset mutant rejected) else (echo [NEGCTL FAIL] slow_merge reset mutant accepted & set "BAD=1")
call "%~dp0run_p3fix_static_gate.bat" > "%~dp0p3fix_static_def.log" 2>&1
if errorlevel 1 (type "%~dp0p3fix_static_def.log" & set "BAD=1")

call "%~dp0run_tb_p3_churn.bat" "" "%~dp0mut\win_pool_mgr_stale.v" > "%~dp0negctl_p3_stale_churn.log" 2>&1
if errorlevel 1 (echo [NEGCTL OK] wpm stale rejected by churn) else (echo [NEGCTL FAIL] wpm stale accepted & set "BAD=1")

call "%~dp0run_tb_p3_churn.bat" "" "%~dp0mut\win_pool_mgr_m5single.v" > "%~dp0negctl_p3_m5single_churn.log" 2>&1
if errorlevel 1 (echo [NEGCTL OK] m5single rejected by churn) else (echo [NEGCTL FAIL] m5single accepted & set "BAD=1")

call "%~dp0run_tb_retx_pool_shared.bat" "%~dp0mut\retx_pool_shared_staleowner.v" > "%~dp0negctl_p3_staleowner_retx.log" 2>&1
if errorlevel 1 (echo [NEGCTL OK] retx staleowner rejected) else (echo [NEGCTL FAIL] retx staleowner accepted & set "BAD=1")

if "%BAD%"=="1" exit /b 1
echo P3_FIX_NEGCTL_PASS
exit /b 0
