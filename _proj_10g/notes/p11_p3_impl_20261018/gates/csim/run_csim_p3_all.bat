@echo off
REM M-2: run all csim arms: 3 netlist arms (P11_FIN_FIX=0) + 1 FIX arm.
REM   criterion per arm = FAIL set == P2 baseline (3); verdict = CSIM_P3_ALL_PASS.
REM   P11 R2 (2026-11-06): the 4th arm compiles with -DP11_FIN_FIX=1; the other
REM   three stay at 0 (LEGACY) and must still reproduce the 3 baseline XFAILs.
setlocal
cd /d %~dp0
set "BAD=0"
echo [CSIM ARM] MAX=8 DUAL=1 FIN=0 LEGACY
call "%~dp0run_csim_p3.bat" 8 1 0 > "%~dp0all_8_1.log" 2>&1
if errorlevel 1 (echo [CSIM ARM FAIL] MAX=8 DUAL=1 FIN=0 LEGACY & type "%~dp0all_8_1.log" & set "BAD=1") else (findstr /C:"CSIM_BASELINE_OK" "%~dp0all_8_1.log")
echo [CSIM ARM] MAX=3 DUAL=1 FIN=0 LEGACY
call "%~dp0run_csim_p3.bat" 3 1 0 > "%~dp0all_3_1.log" 2>&1
if errorlevel 1 (echo [CSIM ARM FAIL] MAX=3 DUAL=1 FIN=0 LEGACY & type "%~dp0all_3_1.log" & set "BAD=1") else (findstr /C:"CSIM_BASELINE_OK" "%~dp0all_3_1.log")
echo [CSIM ARM] MAX=3 DUAL=0 FIN=0 LEGACY
call "%~dp0run_csim_p3.bat" 3 0 0 > "%~dp0all_3_0.log" 2>&1
if errorlevel 1 (echo [CSIM ARM FAIL] MAX=3 DUAL=0 FIN=0 LEGACY & type "%~dp0all_3_0.log" & set "BAD=1") else (findstr /C:"CSIM_BASELINE_OK" "%~dp0all_3_0.log")
echo [CSIM ARM] MAX=8 DUAL=1 FIN=1 FIX
call "%~dp0run_csim_p3.bat" 8 1 1 > "%~dp0all_8_1_fin1.log" 2>&1
if errorlevel 1 (echo [CSIM ARM FAIL] MAX=8 DUAL=1 FIN=1 FIX & type "%~dp0all_8_1_fin1.log" & set "BAD=1") else (findstr /C:"CSIM_BASELINE_OK" "%~dp0all_8_1_fin1.log")
if "%BAD%"=="1" (echo CSIM_P3_ALL FAIL & exit /b 1)
echo CSIM_P3_ALL_PASS
exit /b 0
