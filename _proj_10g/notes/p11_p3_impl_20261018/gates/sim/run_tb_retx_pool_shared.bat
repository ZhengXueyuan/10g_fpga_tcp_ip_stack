@echo off
REM G-P3-3: retx_pool_shared unit gate (+ optional mutant).
setlocal
cd /d %~dp0
call "%~dp0..\..\..\..\..\sim\p4gates\p4env.bat" || exit /b 1
set "ROOT=%REPO_ROOT%"
set "DUT=%ROOT%\rtl\retx_pool_shared.v"
set "TAG=def"
if not "%~1"=="" set "DUT=%~1"
if not "%~1"=="" set "TAG=mut"
if not "%P4_WORKDIR%"=="" (cd /d "%P4_WORKDIR%") else (cd /d %~dp0)
"%PY%" "%P4GATE_PY%" checkpaths --root "%ROOT%" --path "%CD%" --quiet || exit /b 1
call %XV%\xvlog.bat -work xil_defaultlib "%ROOT%\rtl\retx_ram.v" > xvlog_rps_%TAG%.log 2>&1 || (type xvlog_rps_%TAG%.log & exit /b 1)
if "%~1"=="" (
  call %XV%\xvlog.bat -work xil_defaultlib "%ROOT%\rtl\retx_pool_shared.v" >> xvlog_rps_%TAG%.log 2>&1 || (type xvlog_rps_%TAG%.log & exit /b 1)
) else (
  call %XV%\xvlog.bat -work xil_defaultlib "%~1" >> xvlog_rps_%TAG%.log 2>&1 || (type xvlog_rps_%TAG%.log & exit /b 1)
)
call %XV%\xvlog.bat -work xil_defaultlib "%ROOT%\_proj_10g\notes\p11_p3_impl_20261018\gates\sim\tb_retx_pool_shared.v" >> xvlog_rps_%TAG%.log 2>&1 || (type xvlog_rps_%TAG%.log & exit /b 1)
call %XV%\xvlog.bat -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" >> xvlog_glbl.log 2>&1 || (type xvlog_glbl.log & exit /b 1)
call %XV%\xelab.bat -debug typical -L unisims_ver -L xpm xil_defaultlib.tb_retx_pool_shared xil_defaultlib.glbl -s tb_rps_%TAG% -log xelab_rps_%TAG%.log > NUL 2>&1 || (type xelab_rps_%TAG%.log & exit /b 1)
call %XV%\xsim.bat tb_rps_%TAG% -runall -log xsim_rps_%TAG%.log > NUL 2>&1
findstr /C:"RETX_POOL_SHARED TB PASS" xsim_rps_%TAG%.log >nul || (type xsim_rps_%TAG%.log & exit /b 1)
findstr /C:"RETX_POOL_SHARED TB PASS" xsim_rps_%TAG%.log
exit /b 0
