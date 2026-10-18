@echo off
REM run_tb_slow_tx_port.bat -- P11 P2-jia G4: slow_tx_adp per-port source-IP
REM   extraction. Standalone gate (NOT in the P4 matrix). Arms A..G:
REM   IPv4/ARP source-IP -> o_port, unknown/short -> 0, VLAN sticky -> 0,
REM   wrong-offset negative, H-3 long block (SIDE_DEPTH=128, no overflow),
REM   SIDE_DEPTH=16 overflow negative control.
cd /d %~dp0
call "%~dp0..\..\..\sim\p4gates\p4env.bat" || exit /b 1
if not "%P4_WORKDIR%"=="" cd /d "%P4_WORKDIR%"
"%PY%" "%P4GATE_PY%" checkpaths --root "%REPO_ROOT%" --path "%CD%" --quiet || exit /b 1
call %XV%\xvlog.bat -work xil_defaultlib ^
  %REPO_ROOT%\rtl\slow_tx_adp.v ^
  %REPO_ROOT%\rtl\fifo_sync.v ^
  %REPO_ROOT%\rtl\frame_fifo.v ^
  %REPO_ROOT%\_proj_10g\p11_dual\sim\tb_slow_tx_port.v > xvlog_slowport.log 2>&1 || (type xvlog_slowport.log & exit /b 1)
call %XV%\xvlog.bat -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" >> xvlog_slowport.log 2>&1 || (type xvlog_slowport.log & exit /b 1)
REM frame_fifo holds RAMB36E1 prims -> xelab needs unisims_ver + glbl (same as sim\p4sim)
call %XV%\xelab.bat -debug typical -L unisims_ver xil_defaultlib.tb_slow_tx_port xil_defaultlib.glbl -s tb_slow_tx_port -log xelab_slowport.log > NUL 2>&1 || (type xelab_slowport.log & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xelab_slowport.log >NUL && (echo IMPLICIT-DECL-FAIL-SLOWPORT & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xelab_slowport.log & exit /b 1)
set "TPA="
if /i "%1"=="bypdbg" set "TPA=-testplusarg BYPDBG"
call %XV%\xsim.bat tb_slow_tx_port -runall %TPA% -log xsim_slowport.log > NUL 2>&1
REM ---- P11 review-fix (2026-10-18): unified simulator-error hard gate ----
REM   Only whitelisted: RAMB36E1 Memory Collision read-A vs write-B same-address
REM   in the two frame_fifo instances tb_slow_tx_port.u_dut.u_wf / u_small.u_wf
REM   (SDP bypass cycle; masked by bypass_r; see rtl/frame_fifo.v and the
REM   review-fix report). Any other Error/Critical/Unisim/Address Overlap = fail.
"%PY%" "%REPO_ROOT%\_proj_10g\p11_dual\sim\scan_xsim_errors.py" --log xsim_slowport.log --mode slowport || (echo XSIM-ERROR-GATE-FAIL & exit /b 1)
findstr /C:"[FAIL]" /C:"SLOW_TX_PORT TB" xsim_slowport.log
findstr /C:"SLOW_TX_PORT TB PASS" xsim_slowport.log >nul || (echo SLOW_TX_PORT_GATE_FAIL & exit /b 1)
echo SLOW_TX_PORT_GATE_PASS
exit /b 0
