@echo off
setlocal
cd /d %~dp0
call "%~dp0..\..\..\..\..\sim\p4gates\p4env.bat" || exit /b 1
set "ROOT=%REPO_ROOT%"
set "APC=%ROOT%\rtl\app_ctrl.v"
set "TAG=def"
if not "%~1"=="" set "APC=%~1"
if not "%~1"=="" set "TAG=mut"
if not "%P4_WORKDIR%"=="" (cd /d "%P4_WORKDIR%") else (cd /d %~dp0)
"%PY%" "%P4GATE_PY%" checkpaths --root "%ROOT%" --path "%CD%" --quiet || exit /b 1
call %XV%\xvlog.bat -work xil_defaultlib "%ROOT%\rtl\fifo_sync.v" "%ROOT%\rtl\win_pool_mgr.v" > xvlog_churn_%TAG%.log 2>&1 || (type xvlog_churn_%TAG%.log & exit /b 1)
if "%~1"=="" (
  call %XV%\xvlog.bat -work xil_defaultlib "%ROOT%\rtl\app_ctrl.v" >> xvlog_churn_%TAG%.log 2>&1 || (type xvlog_churn_%TAG%.log & exit /b 1)
) else (
  call %XV%\xvlog.bat -work xil_defaultlib "%~1" >> xvlog_churn_%TAG%.log 2>&1 || (type xvlog_churn_%TAG%.log & exit /b 1)
)
call %XV%\xvlog.bat -work xil_defaultlib "%ROOT%\_proj_10g\notes\p11_p3_impl_20261018\gates\sim\tb_p3_churn.v" >> xvlog_churn_%TAG%.log 2>&1 || (type xvlog_churn_%TAG%.log & exit /b 1)
call %XV%\xvlog.bat -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" >> xvlog_glbl.log 2>&1 || (type xvlog_glbl.log & exit /b 1)
call %XV%\xelab.bat -debug typical -L unisims_ver -L xpm xil_defaultlib.tb_p3_churn xil_defaultlib.glbl -s tb_churn_%TAG% -log xelab_churn_%TAG%.log > NUL 2>&1 || (type xelab_churn_%TAG%.log & exit /b 1)
call %XV%\xsim.bat tb_churn_%TAG% -runall -log xsim_churn_%TAG%.log > NUL 2>&1
findstr /C:"P3_CHURN TB PASS" xsim_churn_%TAG%.log >nul || (type xsim_churn_%TAG%.log & exit /b 1)
findstr /C:"P3_CHURN TB PASS" xsim_churn_%TAG%.log
exit /b 0
