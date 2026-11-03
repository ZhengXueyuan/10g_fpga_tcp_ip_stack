@echo off
rem tb_tx_arb_starve REALGAP arm: realistic 2-cycle fast hole -> LEGACY must serve slow.
cd /d %~dp0
set VIV_BIN=C:\AMDDesignTools\2025.2\Vivado\bin
rmdir /s /q xsim.dir\realgap 2>nul
del /q xsim_starve_realgap.log xelab_starve_realgap.log 2>nul
call "%VIV_BIN%\xvlog.bat" -work realgap -d TB_REALGAP ..\..\rtl\tx_arb.v ..\..\tb\tb_tx_arb_starve.v
if errorlevel 1 exit /b 1
call "%VIV_BIN%\xelab.bat" -debug typical -timescale 1ns/1ps -L realgap -L xil_defaultlib realgap.tb_tx_arb_starve -s tb_starve_realgap -log xelab_starve_realgap.log
if errorlevel 1 (type xelab_starve_realgap.log & exit /b 1)
call "%VIV_BIN%\xsim.bat" tb_starve_realgap -tclbatch run.tcl -log xsim_starve_realgap.log
if errorlevel 1 (type xsim_starve_realgap.log & exit /b 1)
findstr /C:"STARVE_RESULT" xsim_starve_realgap.log
findstr /C:"LEGACY_SERVES_WITH_GAP" xsim_starve_realgap.log >nul || exit /b 6
exit /b 0
