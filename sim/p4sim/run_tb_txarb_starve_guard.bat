@echo off
rem tb_tx_arb_starve GUARD arm: STARVE_GUARD=1 must serve the pending slow frame
cd /d %~dp0
set VIV_BIN=C:\AMDDesignTools\2025.2\Vivado\bin
rmdir /s /q xsim.dir\guard_lib 2>nul
del /q xsim_starve_guard.log xelab_starve_guard.log 2>nul
call "%VIV_BIN%\xvlog.bat" -work guard_lib -d TB_GUARD ..\..\rtl\tx_arb.v ..\..\tb\tb_tx_arb_starve.v
if errorlevel 1 exit /b 1
call "%VIV_BIN%\xelab.bat" -debug typical -timescale 1ns/1ps -L guard_lib -L xil_defaultlib guard_lib.tb_tx_arb_starve -s tb_starve_guard -log xelab_starve_guard.log
if errorlevel 1 (type xelab_starve_guard.log & exit /b 1)
call "%VIV_BIN%\xsim.bat" tb_starve_guard -tclbatch run.tcl -log xsim_starve_guard.log
if errorlevel 1 (type xsim_starve_guard.log & exit /b 1)
findstr /C:"STARVE_RESULT" xsim_starve_guard.log
findstr /C:"SLOW_SERVED" xsim_starve_guard.log >nul || exit /b 4
findstr /C:"LEGACY_STARVE_CONFIRMED" xsim_starve_guard.log >nul && exit /b 5
exit /b 0
