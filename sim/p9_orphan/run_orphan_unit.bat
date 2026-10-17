@echo off
REM ==========================================================================
REM run_orphan_unit.bat -- p9 orphan fix unit gate single-run driver
REM   usage: run_orphan_unit.bat <app_ctrl_src> <scen> <EN> <ZW> <LIM> <tag> <PASS|FAIL>
REM   compile: fifo_sync + <app_ctrl_src> + frozen anchor + tb/tb_app_orphan.v
REM   xelab generics: ORPHAN_EN_TB / ORPHAN_ZW_EN_TB / ORPHAN_LIM_TB
REM   exit: 0 = got matches expect; 1 = mismatch; 2 = compile/elaborate error
REM   NOTE: redirect logs must NOT be named xvlog.log/xelab.log (the tools open
REM         those names themselves; a held handle makes them fail with 17-183).
REM ==========================================================================
setlocal
pushd "%~dp0..\.."
set "ROOT=%CD%"
popd
set "XV=C:\AMDDesignTools\2025.2\Vivado\bin"
for %%I in ("%~1") do set "SRC=%%~fI"
set "SCEN=%~2"
set "EN=%~3"
set "ZW=%~4"
set "LIM=%~5"
set "TAG=%~6"
set "EXPECT=%~7"
set "FROZEN=%ROOT%\_proj_10g\notes\p9_orphan_impl_20261017\frozen\app_ctrl_head_cc7af9a8__as_app_ctrl_frozen.v"
set "WD=%~dp0work_%TAG%"
if not exist "%WD%" mkdir "%WD%"
cd /d "%WD%"
if exist xsim.dir rmdir /s /q xsim.dir
if exist xsim.log del /q xsim.log

call "%XV%\xvlog.bat" -work xil_defaultlib "%ROOT%\rtl\fifo_sync.v" "%SRC%" "%FROZEN%" "%ROOT%\tb\tb_app_orphan.v" > xvlog_gate.log 2>&1
if errorlevel 1 ( echo GATE_RESULT ERROR_XVLOG %TAG% & type xvlog_gate.log & exit /b 2 )
call "%XV%\xelab.bat" -debug typical xil_defaultlib.tb_app_orphan -s tb_orphan -generic_top "ORPHAN_EN_TB=%EN%" -generic_top "ORPHAN_ZW_EN_TB=%ZW%" -generic_top "ORPHAN_LIM_TB=%LIM%" > xelab_gate.log 2>&1
if errorlevel 1 ( echo GATE_RESULT ERROR_XELAB %TAG% & type xelab_gate.log & exit /b 2 )
call "%XV%\xsim.bat" tb_orphan -runall -testplusarg "SCEN=%SCEN%" -log xsim.log > xsim_console.log 2>&1
findstr /C:"TB_RESULT" xsim.log
findstr /C:"CHECK FAIL" xsim.log
findstr /C:"TB_RESULT PASS" xsim.log > nul
if errorlevel 1 ( set "RES=FAIL" ) else ( set "RES=PASS" )
echo GATE_RESULT %TAG% scen=%SCEN% expect=%EXPECT% got=%RES%
if "%RES%"=="%EXPECT%" ( exit /b 0 ) else ( exit /b 1 )
