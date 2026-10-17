@echo off
REM ==========================================================================
REM run_p5_orphan_scen.bat <OVL:0|1> <SCEN> <EXPECT:PASS|FAIL>
REM   run an already-built tb_p5_orphan_wrapper snapshot and grep TB_RESULT
REM ==========================================================================
setlocal
set "XV=C:\AMDDesignTools\2025.2\Vivado\bin"
set "OVL=%~1"
set "SCEN=%~2"
set "EXPECT=%~3"
set "WD=%~dp0work_p5orphan_%OVL%"
cd /d "%WD%" || ( echo GATE_RESULT ERROR_NOWORKDIR & exit /b 2 )
if not exist xsim.dir ( echo GATE_RESULT ERROR_NOSNAPSHOT & exit /b 2 )
if exist xsim.log del /q xsim.log
call "%XV%\xsim.bat" tb_p5_orphan_wrapper -runall -testplusarg "SCEN=%SCEN%" -log xsim.log > xsim_console.log 2>&1
findstr /C:"TB_RESULT" xsim.log
findstr /C:"CHECK FAIL" xsim.log
findstr /C:"TB_RESULT PASS" xsim.log > nul
if errorlevel 1 ( set "RES=FAIL" ) else ( set "RES=PASS" )
echo GATE_RESULT OVL=%OVL% scen=%SCEN% expect=%EXPECT% got=%RES%
if "%RES%"=="%EXPECT%" ( exit /b 0 ) else ( exit /b 1 )
