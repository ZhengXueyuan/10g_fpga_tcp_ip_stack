@echo off
REM run_tb_p11_dual.bat -- P11 P2-jia G6: real wrapper + DUAL dual-port chain gate
REM   Config adds -d DUAL_SFP_A **and -d SFP2_MODE_A** (F-9: the true build macro set;
REM   P7B_10G + P7B_SIM_NOPCS + PCIE_OBS + DEV_USP + APP_MODE + DP_156MHZ +
REM   P6B_SIM_CLKGEN + UDP_TX_OVL + TCP_TX_OVL + SFP2_MODE_A + DUAL_SFP_A).
REM   Prints P11_DUAL TB PASS/FAIL (exit code follows).
cd /d %~dp0
call "%~dp0..\..\..\sim\p4gates\p4env.bat" || exit /b 1
set "ROOT=%REPO_ROOT%"
if not "%P4_WORKDIR%"=="" (cd /d "%P4_WORKDIR%") else (cd /d %~dp0)
"%PY%" "%P4GATE_PY%" checkpaths --root "%ROOT%" --path "%CD%" --quiet || exit /b 1
"%PY%" "%P4GATE_PY%" checkpaths --root "%ROOT%" --manifest "%GATES%\p11dual_src.f" --path "%CD%" --quiet || exit /b 1
set "DEFS=-d P7B_10G -d P7B_SIM_NOPCS -d PCIE_OBS -d DEV_USP -d APP_MODE -d DP_156MHZ -d P6B_SIM_CLKGEN -d UDP_TX_OVL -d TCP_TX_OVL -d SFP2_MODE_A -d DUAL_SFP_A"
REM 2026-10-19 P3 fix (H-4 gate-side): pin the archived P2 netlist. Live
REM   solution1 was re-run with P3 cflags (MAX=8 + i_tcp_adv_wnd) and this TB's
REM   udp_echo instantiation has no such port => Z/X and g6 went red.
set "HLSA=%ROOT%\_proj_10g\notes\p11_p3_build_20261019\hls_archive_p2_dual_ip_max3"
if not exist "%HLSA%\udp_echo.v" (echo P11_HLS_P2_ARCHIVE_MISSING & exit /b 1)
dir /b /s "%HLSA%\*.v" > hls_p11dual.f
REM HLS netlist ROM images: without these xsim warns "cannot be opened" and the
REM HLS MAC emits garbage preamble/src-MAC (P4 chain bats copy them too).
copy /y "%HLS%\*.dat" . >nul 2>&1
call %XV%\xvlog.bat -sv -work xpm "%XV%\..\data\ip\xpm\xpm_memory\hdl\xpm_memory.sv" > xvlog_xpm.log 2>&1 || (type xvlog_xpm.log & exit /b 1)
call %XV%\xvlog.bat -work xil_defaultlib %DEFS% -i %ROOT%\rtl -i %ROOT%\board ^
  %ROOT%\rtl\app_ctrl.v %ROOT%\rtl\app_pattern.v %ROOT%\rtl\app_rx_mirror.v ^
  %ROOT%\rtl\app_status_uart.v %ROOT%\rtl\app_udp_pattern.v ^
  %ROOT%\rtl\aximm_c2h_win.v %ROOT%\rtl\aximm_h2c_discard.v ^
  %ROOT%\rtl\axis_c2h_stream.v %ROOT%\rtl\axis_pipe.v ^
  %ROOT%\rtl\checksum16.v %ROOT%\rtl\clk_gen_p6b.v %ROOT%\rtl\crc32_8b.v ^
  %ROOT%\rtl\fifo_async.v %ROOT%\rtl\fifo_sync.v %ROOT%\rtl\frame_fifo.v ^
  %ROOT%\rtl\mac_rx_64.v %ROOT%\rtl\mac_tx_64.v ^
  %ROOT%\rtl\maccnt_sync.v %ROOT%\rtl\rx_merge2.v %ROOT%\rtl\tx_demux2.v ^
  %ROOT%\rtl\mir_dma_ring.v %ROOT%\rtl\mir_uram_fifo.v %ROOT%\rtl\retx_ram.v ^
  %ROOT%\rtl\rx_classify.v %ROOT%\rtl\slow_cfg_adp.v %ROOT%\rtl\slow_rx_adp.v ^
  %ROOT%\rtl\slow_tx_adp.v %ROOT%\rtl\snap_cdc.v %ROOT%\rtl\snap_seq.v ^
  %ROOT%\rtl\tcb.v %ROOT%\rtl\tcp_cam.v %ROOT%\rtl\tcp_echo.v %ROOT%\rtl\tcp_rx.v ^
  %ROOT%\rtl\tcp_synp.v %ROOT%\rtl\tcp_tx_frame.v %ROOT%\rtl\tx_arb.v ^
  %ROOT%\rtl\udp_echo.v %ROOT%\rtl\udp_rx.v %ROOT%\rtl\udp_split.v ^
  %ROOT%\rtl\udp_tx_cfg.v %ROOT%\rtl\udp_tx_frame.v %ROOT%\rtl\vlan_strip.v ^
  %ROOT%\board\wrapper_p4.v %ROOT%\board\util_gmii_to_rgmii_us.v %ROOT%\board\uart_dbg.v ^
  %ROOT%\board\p7b_pcs_stub.v ^
  %ROOT%\_proj_pcie\rtl\axi_regs.v ^
  %ROOT%\_proj_10g\p7b_mac\rtl\crc32_64.v %ROOT%\_proj_10g\p7b_mac\rtl\mac_rx_10g.v %ROOT%\_proj_10g\p7b_mac\rtl\mac_tx_10g.v ^
  %ROOT%\sim\p6e_pcie\xdma_0_sim_stub.v ^
  %ROOT%\_proj_10g\p11_dual\sim\tb_p11_dual.v ^
  -f hls_p11dual.f > xvlog_p11dual.log 2>&1 || (type xvlog_p11dual.log & exit /b 1)
call %XV%\xvlog.bat %DEFS% -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" >> xvlog_p11dual.log 2>&1 || (type xvlog_p11dual.log & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xvlog_p11dual.log >NUL && (echo IMPLICIT-DECL-FAIL & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xvlog_p11dual.log & exit /b 1)
findstr /I /C:"ERROR" xvlog_p11dual.log >NUL && (echo XVLOG-ERROR-FAIL & findstr /I /C:"ERROR" xvlog_p11dual.log & exit /b 1)
call %XV%\xelab.bat -debug typical -L unisims_ver -L xpm xil_defaultlib.tb_p11_dual xil_defaultlib.glbl -s tb_p11_dual -log xelab_p11dual.log > NUL 2>&1 || (type xelab_p11dual.log & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xelab_p11dual.log >NUL && (echo IMPLICIT-DECL-FAIL-XELAB & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xelab_p11dual.log & exit /b 1)
REM ---- F-7 (H-1): the new input `peer_my_ip` must never be reported unconnected ----
REM   Targeted joint assertion: VRFC 10-3645 is noisy on clean designs, so it only counts
REM   when the SAME LINE names peer_my_ip (project note: bare 10-3645 has many benign hits).
findstr /C:"peer_my_ip" xelab_p11dual.log | findstr /C:"VRFC 10-3645" >NUL && (echo PEER_MY_IP-UNCONNECTED-FAIL & findstr /C:"peer_my_ip" xelab_p11dual.log & exit /b 1)
call %XV%\xsim.bat tb_p11_dual -runall -log xsim_p11dual.log > NUL 2>&1 || (type xsim_p11dual.log & exit /b 1)
REM ---- F-14 / P11 review-fix (2026-10-18): unified simulator-error hard gate ----
REM   The ONLY allowed exception is the documented benign RAMB36E2-11 bypass
REM   collision in tb_p11_dual.u_dut.u_slow_rx.u_ff.gen_mem[0].u_main:
REM   frame_fifo same-address write (port B) + read (port A) => DOA X for one
REM   cycle, memory survives, masked by bypass_r, never leaks (rtl/frame_fifo.v
REM   header "cycle semantics" bullet; the unisim model compares *_last
REM   addresses but prints the current ones => the printed 0040/0000 are one
REM   cycle after the collision).  Any other Error/Critical/Unisim/Memory
REM   Collision/Address Overlap in the log = hard failure.
"%PY%" "%REPO_ROOT%\_proj_10g\p11_dual\sim\scan_xsim_errors.py" --log xsim_p11dual.log --mode p11dual || (echo XSIM-ERROR-GATE-FAIL & exit /b 1)
findstr /C:"[FAIL]" /C:"P11_DUAL TB" xsim_p11dual.log
findstr /C:"P11_DUAL TB PASS" xsim_p11dual.log >nul || exit /b 1
exit /b 0
