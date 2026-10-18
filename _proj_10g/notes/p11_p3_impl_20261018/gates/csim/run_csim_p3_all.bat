@echo off
REM M-2: run all 3 csim arms; criterion = FAIL set == P2 baseline (3).
REM   verdict: CSIM_P3_ALL_PASS / FAIL
setlocal
cd /d %~dp0
set "BAD=0"
call "%~dp0run_csim_p3.bat" 8 1 > "%~dp0all_8_1.log" 2>&1
if errorlevel 1 (echo [CSIM ARM FAIL] MAX=8 DUAL=1 & type "%~dp0all_8_1.log" & set "BAD=1") else (findstr /C:"CSIM_BASELINE_OK" "%~dp0all_8_1.log")
call "%~dp0run_csim_p3.bat" 3 1 > "%~dp0all_3_1.log" 2>&1
if errorlevel 1 (echo [CSIM ARM FAIL] MAX=3 DUAL=1 & type "%~dp0all_3_1.log" & set "BAD=1") else (findstr /C:"CSIM_BASELINE_OK" "%~dp0all_3_1.log")
call "%~dp0run_csim_p3.bat" 3 0 > "%~dp0all_3_0.log" 2>&1
if errorlevel 1 (echo [CSIM ARM FAIL] MAX=3 DUAL=0 & type "%~dp0all_3_0.log" & set "BAD=1") else (findstr /C:"CSIM_BASELINE_OK" "%~dp0all_3_0.log")
if "%BAD%"=="1" (echo CSIM_P3_ALL FAIL & exit /b 1)
echo CSIM_P3_ALL_PASS
exit /b 0
