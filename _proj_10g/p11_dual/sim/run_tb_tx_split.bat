@echo off
REM run_tb_tx_split.bat -- P11 P2-jia G3: tx_demux2 + per-port arb unit gate
REM   Standalone gate (NOT registered in the P4 matrix). Self-checking TB:
REM   prints TX_SPLIT TB PASS / FAIL. Arms A..D (port separation, frame
REM   atomicity under mid-frame s_port flip, per-port priority, crossed-wire
REM   mutant).
cd /d %~dp0
call "%~dp0..\..\..\sim\p4gates\p4env.bat" || exit /b 1
if not "%P4_WORKDIR%"=="" cd /d "%P4_WORKDIR%"
"%PY%" "%P4GATE_PY%" checkpaths --root "%REPO_ROOT%" --path "%CD%" --quiet || exit /b 1
call %XV%\xvlog.bat -work xil_defaultlib ^
  %REPO_ROOT%\rtl\tx_demux2.v ^
  %REPO_ROOT%\rtl\tx_arb.v ^
  %REPO_ROOT%\_proj_10g\p11_dual\sim\tb_tx_split.v > xvlog_split.log 2>&1 || (type xvlog_split.log & exit /b 1)
call %XV%\xelab.bat -debug typical xil_defaultlib.tb_tx_split -s tb_tx_split -log xelab_split.log > NUL 2>&1 || (type xelab_split.log & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xelab_split.log >NUL && (echo IMPLICIT-DECL-FAIL-SPLIT & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xelab_split.log & exit /b 1)
call %XV%\xsim.bat tb_tx_split -runall -log xsim_split.log > NUL 2>&1
findstr /C:"[FAIL]" /C:"TX_SPLIT TB" xsim_split.log
findstr /C:"TX_SPLIT TB PASS" xsim_split.log >nul || (echo TX_SPLIT_GATE_FAIL & exit /b 1)
echo TX_SPLIT_GATE_PASS
exit /b 0
