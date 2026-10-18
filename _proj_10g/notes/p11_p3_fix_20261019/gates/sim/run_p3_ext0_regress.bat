@echo off
REM H-5: EXT_QUOTA=0 (default) regression wrapper gate.
REM   Runs the three app_ctrl EXT=0 gates used by the P3 implementation report,
REM   archives stdout under ..\logs\, and requires each gate's own PASS line.
REM   Verdict: P11_EXT0_REGRESS PASS / FAIL
setlocal
cd /d %~dp0
call "%~dp0..\..\..\..\..\sim\p4gates\p4env.bat" || exit /b 1
set "ROOT=%REPO_ROOT%"
set "LOG=%~dp0..\logs"
if not exist "%LOG%\" mkdir "%LOG%"
set "BAD=0"

call "%ROOT%\sim\p5sim\run_tb_p5_fc.bat" > "%LOG%\h5_tb_p5_fc.txt" 2>&1
if errorlevel 1 (echo [EXT0 FAIL] tb_p5_fc & set "BAD=1") else (findstr /C:"P5 FC UNIT GATE PASS" "%LOG%\h5_tb_p5_fc.txt" >nul || (echo [EXT0 FAIL] tb_p5_fc verdict & set "BAD=1"))

call "%ROOT%\sim\p5sim\run_tb_p5_flow.bat" > "%LOG%\h5_tb_p5_flow.txt" 2>&1
if errorlevel 1 (echo [EXT0 FAIL] tb_p5_flow & set "BAD=1") else (findstr /C:"P5 FLOW OK" "%LOG%\h5_tb_p5_flow.txt" >nul || (echo [EXT0 FAIL] tb_p5_flow verdict & set "BAD=1"))

call "%ROOT%\sim\p5wu\run_tb_app_wu.bat" > "%LOG%\h5_tb_app_wu.txt" 2>&1
if errorlevel 1 (echo [EXT0 FAIL] tb_app_wu & set "BAD=1") else (findstr /C:"P7B WU GATE PASS" "%LOG%\h5_tb_app_wu.txt" >nul || (echo [EXT0 FAIL] tb_app_wu verdict & set "BAD=1"))

if "%BAD%"=="1" (echo P11_EXT0_REGRESS FAIL & exit /b 1)
echo P11_EXT0_REGRESS PASS
exit /b 0
