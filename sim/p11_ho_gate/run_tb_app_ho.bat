@echo off
REM run_tb_app_ho.bat -- R1 half-open aging unit gate (app_ctrl HO_EN=1).
REM   Local Windows xsim. Do NOT run while a Vivado build is running on this machine.
setlocal
set HERE=%~dp0
set REPO=%~dp0..\..
pushd "%REPO%"
set XV=C:\AMDDesignTools\2025.2\Vivado\bin
if not exist "%XV%\xvlog.bat" (
  echo [XVLOG MISSING] %XV%
  popd & exit /b 2
)
call "%XV%\xvlog.bat" -work xil_defaultlib rtl\fifo_sync.v rtl\app_ctrl.v tb\tb_app_ho.v > "%HERE%xvlog.log" 2>&1
if errorlevel 1 ( echo [XVLOG FAIL] & type "%HERE%xvlog.log" & popd & exit /b 1 )
call "%XV%\xelab.bat" -debug typical -L xil_defaultlib xil_defaultlib.tb_app_ho -s tb_ho > "%HERE%xelab.log" 2>&1
if errorlevel 1 ( echo [XELAB FAIL] & type "%HERE%xelab.log" & popd & exit /b 1 )
call "%XV%\xsim.bat" tb_ho -runall > "%HERE%xsim.log" 2>&1
findstr /C:"TB_RESULT PASS" "%HERE%xsim.log" >nul
if errorlevel 1 ( echo [SIM FAIL] & findstr /C:"CHECK FAIL" /C:"TB_APP_HO" "%HERE%xsim.log" & popd & exit /b 1 )
findstr /C:"TB_RESULT PASS" /C:"^A:" /C:"^B:" /C:"^C:" "%HERE%xsim.log"
popd
exit /b 0
