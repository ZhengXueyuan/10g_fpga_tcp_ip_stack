@echo off
setlocal
cd /d %~dp0
call "%~dp0..\..\..\..\..\sim\p4gates\p4env.bat" || exit /b 1
set "ROOT=%REPO_ROOT%"
if not "%P4_WORKDIR%"=="" (cd /d "%P4_WORKDIR%") else (cd /d %~dp0)
"%PY%" "%P4GATE_PY%" checkpaths --root "%ROOT%" --path "%CD%" --quiet || exit /b 1
call %XV%\xvlog.bat -work xil_defaultlib "%ROOT%\rtl\fifo_sync.v" "%ROOT%\rtl\slow_cfg_demux.v" "%ROOT%\_proj_10g\notes\p11_p3_impl_20261018\gates\sim\tb_slow_cfg_demux.v" > xvlog_scd.log 2>&1 || (type xvlog_scd.log & exit /b 1)
call %XV%\xvlog.bat -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" >> xvlog_glbl.log 2>&1 || (type xvlog_glbl.log & exit /b 1)
call %XV%\xelab.bat -debug typical -L unisims_ver -L xpm xil_defaultlib.tb_slow_cfg_demux xil_defaultlib.glbl -s tb_scd -log xelab_scd.log > NUL 2>&1 || (type xelab_scd.log & exit /b 1)
call %XV%\xsim.bat tb_scd -runall -log xsim_scd.log > NUL 2>&1
findstr /C:"SLOW_CFG_DEMUX TB PASS" xsim_scd.log >nul || (type xsim_scd.log & exit /b 1)
findstr /C:"SLOW_CFG_DEMUX TB PASS" xsim_scd.log
exit /b 0
