@echo off
REM M-6: slow-path negative controls (each mutant must turn its positive gate red).
REM   cfg_w2rev / cfg_delw2 / sm2_mix / sd2_nolock
setlocal
cd /d %~dp0
call "%~dp0..\..\..\..\..\sim\p4gates\p4env.bat" || exit /b 1
"%PY%" "%~dp0mk_mut_slow.py" || exit /b 1
set "BAD=0"

call "%~dp0run_tb_slow_cfg_demux.bat" "%~dp0mut\slow_cfg_demux_w2rev.v" > "%~dp0negctl_slow_cfg_w2rev.log" 2>&1
if errorlevel 1 (echo [NEGCTL OK] cfg w2rev rejected) else (echo [NEGCTL FAIL] cfg w2rev accepted & set "BAD=1")

call "%~dp0run_tb_slow_cfg_demux.bat" "%~dp0mut\slow_cfg_demux_delw2.v" > "%~dp0negctl_slow_cfg_delw2.log" 2>&1
if errorlevel 1 (echo [NEGCTL OK] cfg delw2 rejected) else (echo [NEGCTL FAIL] cfg delw2 accepted & set "BAD=1")

call "%~dp0run_tb_slow_merge2.bat" "%~dp0mut\slow_merge2_mix.v" > "%~dp0negctl_slow_sm2.log" 2>&1
if errorlevel 1 (echo [NEGCTL OK] merge mix rejected) else (echo [NEGCTL FAIL] merge mix accepted & set "BAD=1")

call "%~dp0run_tb_slow_demux2.bat" "%~dp0mut\slow_demux2_nolock.v" > "%~dp0negctl_slow_sd2.log" 2>&1
if errorlevel 1 (echo [NEGCTL OK] demux nolock rejected) else (echo [NEGCTL FAIL] demux nolock accepted & set "BAD=1")

if "%BAD%"=="1" (echo SLOW_NEGCTL FAIL & exit /b 1)
echo SLOW_NEGCTL_PASS
exit /b 0
