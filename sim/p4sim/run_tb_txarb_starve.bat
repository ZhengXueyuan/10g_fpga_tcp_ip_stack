@echo off
rem tb_tx_arb_starve: slow-path starvation discrimination (zero-build)
cd /d %~dp0
set VIV_BIN=C:\AMDDesignTools\2025.2\Vivado\bin
rmdir /s /q xsim.dir 2>nul
del /q xsim_starve.log xelab_starve.log 2>nul
call "%VIV_BIN%\xvlog.bat" -work xil_defaultlib ..\..\rtl\tx_arb.v ..\..\tb\tb_tx_arb_starve.v
if errorlevel 1 exit /b 1
call "%VIV_BIN%\xelab.bat" -debug typical -timescale 1ns/1ps -L xil_defaultlib xil_defaultlib.tb_tx_arb_starve -s tb_tx_arb_starve -log xelab_starve.log
if errorlevel 1 (type xelab_starve.log & exit /b 1)
call "%VIV_BIN%\xsim.bat" tb_tx_arb_starve -tclbatch run.tcl -log xsim_starve.log
if errorlevel 1 (type xsim_starve.log & exit /b 1)
findstr /C:"STARVE_RESULT" xsim_starve.log
findstr /C:"LEGACY_STARVE_CONFIRMED" xsim_starve.log >nul || exit /b 2
findstr /C:"SLOW_SERVED" xsim_starve.log >nul && exit /b 3
exit /b 0
