@echo off
setlocal
cd /d %~dp0
call "%~dp0..\..\..\..\..\sim\p4gates\p4env.bat" || exit /b 1
set "ROOT=%REPO_ROOT%"
set "DUT=%ROOT%\rtl\slow_demux2.v"
if not "%~1"=="" set "DUT=%~1"
if not "%P4_WORKDIR%"=="" (cd /d "%P4_WORKDIR%") else (cd /d %~dp0)
"%PY%" "%P4GATE_PY%" checkpaths --root "%ROOT%" --path "%CD%" --quiet || exit /b 1
call %XV%\xvlog.bat -work xil_defaultlib "%DUT%" "%ROOT%\_proj_10g\notes\p11_p3_impl_20261018\gates\sim\tb_slow_demux2.v" > xvlog_sd2.log 2>&1 || (type xvlog_sd2.log & exit /b 1)
call %XV%\xvlog.bat -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" >> xvlog_glbl.log 2>&1 || (type xvlog_glbl.log & exit /b 1)
call %XV%\xelab.bat -debug typical -L unisims_ver -L xpm xil_defaultlib.tb_slow_demux2 xil_defaultlib.glbl -s tb_sd2 -log xelab_sd2.log > NUL 2>&1 || (type xelab_sd2.log & exit /b 1)
call %XV%\xsim.bat tb_sd2 -runall -log xsim_sd2.log > NUL 2>&1
findstr /C:"SLOW_DEMUX2 TB PASS" xsim_sd2.log >nul || (type xsim_sd2.log & exit /b 1)
findstr /C:"SLOW_DEMUX2 TB PASS" xsim_sd2.log
exit /b 0
