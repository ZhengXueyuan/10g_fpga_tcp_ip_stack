@echo off
REM run_elab_c4.bat -- P11 P3 G-P3-7 (part): C4 (cfg_dual) full elaboration.
REM   Config = board build macro set + P11_DUAL + P11_CFG_C4 + P11_CFG_ENFORCE.
REM   Verdict lines: "P11_C4_ELAB PASS" / "P11_C4_ELAB FAIL".
REM   Elaboration-only (xelab with wrapper_p4 as top); no simulation.
cd /d %~dp0
call "%~dp0..\..\..\..\..\sim\p4gates\p4env.bat" || exit /b 1
set "ROOT=%REPO_ROOT%"
if not "%P4_WORKDIR%"=="" (cd /d "%P4_WORKDIR%") else (cd /d %~dp0)
"%PY%" "%P4GATE_PY%" checkpaths --root "%ROOT%" --path "%CD%" --quiet || exit /b 1
set "DEFS=-d P7B_10G -d P7B_SIM_NOPCS -d PCIE_OBS -d DEV_USP -d APP_MODE -d DP_156MHZ -d P6B_SIM_CLKGEN -d UDP_TX_OVL -d TCP_TX_OVL -d SFP2_MODE_A -d DUAL_SFP_A -d P11_DUAL -d P11_CFG_C4 -d P11_CFG_ENFORCE"
dir /b /s "%ROOT%\hls\slowstack_prj\solution1\syn\verilog\*.v" > hls_c4.f
copy /y "%HLS%\*.dat" . >nul 2>&1
call %XV%\xvlog.bat -sv -work xpm "%XV%\..\data\ip\xpm\xpm_memory\hdl\xpm_memory.sv" > xvlog_xpm_c4.log 2>&1 || (type xvlog_xpm_c4.log & exit /b 1)
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
  %ROOT%\rtl\win_pool_mgr.v %ROOT%\rtl\retx_pool_shared.v ^
  %ROOT%\rtl\slow_merge2.v %ROOT%\rtl\slow_demux2.v %ROOT%\rtl\slow_cfg_demux.v ^
  %ROOT%\board\wrapper_p4.v %ROOT%\board\util_gmii_to_rgmii_us.v %ROOT%\board\uart_dbg.v ^
  %ROOT%\board\p7b_pcs_stub.v ^
  %ROOT%\_proj_pcie\rtl\axi_regs.v ^
  %ROOT%\_proj_10g\p7b_mac\rtl\crc32_64.v %ROOT%\_proj_10g\p7b_mac\rtl\mac_rx_10g.v %ROOT%\_proj_10g\p7b_mac\rtl\mac_tx_10g.v ^
  %ROOT%\sim\p6e_pcie\xdma_0_sim_stub.v ^
  -f hls_c4.f > xvlog_c4.log 2>&1 || (type xvlog_c4.log & echo P11_C4_ELAB FAIL & exit /b 1)
call %XV%\xvlog.bat %DEFS% -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" >> xvlog_c4.log 2>&1 || (type xvlog_c4.log & echo P11_C4_ELAB FAIL & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xvlog_c4.log >NUL && (echo IMPLICIT-DECL-FAIL & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xvlog_c4.log & echo P11_C4_ELAB FAIL & exit /b 1)
findstr /I /C:"ERROR" xvlog_c4.log >NUL && (echo XVLOG-ERROR-FAIL & findstr /I /C:"ERROR" xvlog_c4.log & echo P11_C4_ELAB FAIL & exit /b 1)
call %XV%\xelab.bat -debug typical -L unisims_ver -L xpm xil_defaultlib.wrapper_p4 xil_defaultlib.glbl -s wrapper_c4_elab -log xelab_c4.log > NUL 2>&1 || (type xelab_c4.log & echo P11_C4_ELAB FAIL & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xelab_c4.log >NUL && (echo IMPLICIT-DECL-FAIL-XELAB & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xelab_c4.log & echo P11_C4_ELAB FAIL & exit /b 1)
echo P11_C4_ELAB PASS
exit /b 0
