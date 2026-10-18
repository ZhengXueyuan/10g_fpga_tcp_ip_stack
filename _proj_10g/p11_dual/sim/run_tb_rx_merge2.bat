@echo off
REM run_tb_rx_merge2.bat -- P11 P2-jia G2: rx_merge2 unit gate (xsim, self-checking)
REM   Arms A..F; prints RX_MERGE2 TB PASS / FAIL (exit code follows).
cd /d %~dp0
call "%~dp0..\..\..\sim\p4gates\p4env.bat" || exit /b 1
if not "%P4_WORKDIR%"=="" cd /d "%P4_WORKDIR%"
"%PY%" "%P4GATE_PY%" checkpaths --root "%REPO_ROOT%" --path "%CD%" --quiet || exit /b 1
"%PY%" "%P4GATE_PY%" checkpaths --root "%REPO_ROOT%" --manifest "%GATES%\p11merge_src.f" --path "%CD%" --quiet || exit /b 1
call %XV%\xvlog.bat -work xil_defaultlib ^
  %REPO_ROOT%\rtl\rx_merge2.v ^
  %REPO_ROOT%\_proj_10g\p11_dual\sim\tb_rx_merge2.v > xvlog_tb.log 2>&1 || (type xvlog_tb.log & exit /b 1)
call %XV%\xelab.bat -debug typical xil_defaultlib.tb_rx_merge2 -s tb_rx_merge2 -log xelab_run.log > NUL 2>&1 || (type xelab_run.log & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xelab_run.log >NUL && (echo IMPLICIT-DECL-FAIL-XELAB & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xelab_run.log & exit /b 1)
call %XV%\xsim.bat tb_rx_merge2 -runall -log xsim_run.log > NUL 2>&1 || (type xsim_run.log & exit /b 1)
findstr /C:"[FAIL]" /C:"RX_MERGE2 TB" xsim_run.log
findstr /C:"RX_MERGE2 TB PASS" xsim_run.log >nul || exit /b 1
exit /b 0
