@echo off
setlocal
cd /d %~dp0
call "%~dp0..\..\..\..\..\sim\p4gates\p4env.bat" || exit /b 1
set "ROOT=%REPO_ROOT%"
if not "%P4_WORKDIR%"=="" (cd /d "%P4_WORKDIR%") else (cd /d %~dp0)
"%PY%" "%P4GATE_PY%" checkpaths --root "%ROOT%" --path "%CD%" --quiet || exit /b 1
set "DEFS=-d P7B_10G -d P7B_SIM_NOPCS -d PCIE_OBS -d DEV_USP -d APP_MODE -d DP_156MHZ -d P6B_SIM_CLKGEN -d UDP_TX_OVL -d TCP_TX_OVL -d SFP2_MODE_A -d DUAL_SFP_A -d P11_DUAL -d P11_CFG_C4 -d P11_CFG_ENFORCE -d P11_HLS_ADV_WND"
REM H-4: use P3 archived netlist (MAX=8 + i_tcp_adv_wnd) + P11_HLS_ADV_WND.
REM   Old version used live solution1 (overwritten by next HLS run; no macro = dangling).
set "HLS3=%ROOT%\_proj_10g\notes\p11_p3_build_20261019\hls_archive_p3_dual_ip_max8"
if not exist "%HLS3%\udp_echo.v" (echo P11_HLS_P3_ARCHIVE_MISSING & exit /b 1)
findstr /C:"i_tcp_adv_wnd" "%HLS3%\udp_echo.v" >nul || (echo P11_HLS_PORT_MISSING & exit /b 1)
dir /b /s "%HLS3%\*.v" > hls_c4w.f
copy /y "%HLS3%\*.dat" . >nul 2>&1
call %XV%\xvlog.bat -sv -work xpm "%XV%\..\data\ip\xpm\xpm_memory\hdl\xpm_memory.sv" > xvlog_xpm_c4w.log 2>&1 || (type xvlog_xpm_c4w.log & exit /b 1)
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
  %ROOT%\_proj_10g\notes\p11_p3_impl_20261018\gates\sim\tb_p11_c4_wrap.v ^
  -f hls_c4w.f > xvlog_c4w.log 2>&1 || (type xvlog_c4w.log & exit /b 1)
call %XV%\xvlog.bat %DEFS% -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" >> xvlog_c4w.log 2>&1 || (type xvlog_c4w.log & exit /b 1)
call %XV%\xelab.bat -debug typical -L unisims_ver -L xpm xil_defaultlib.tb_p11_c4_wrap xil_defaultlib.glbl -s tb_p11_c4_wrap -log xelab_c4w.log > NUL 2>&1 || (type xelab_c4w.log & exit /b 1)
call %XV%\xsim.bat tb_p11_c4_wrap -runall -log xsim_c4w.log > NUL 2>&1
REM M-1: unified simulator-error hard gate (same as P2 G6; only allowed = u_slow_rx.u_ff
REM   RAMB36E2-11 bypass collision; see scan_xsim_errors.py header).
"%PY%" "%ROOT%\_proj_10g\p11_dual\sim\scan_xsim_errors.py" --log xsim_c4w.log --mode c4wrap || (echo XSIM-ERROR-GATE-FAIL & exit /b 1)
REM H-3 behavioural: wrapper initial self-check must print OK (8+0 => 3328).
findstr /C:"P11_ACC_MARGIN_SELFCHK OK" xsim_c4w.log >nul || (echo P11_ACC_MARGIN_SELFCHK_MISSING & type xsim_c4w.log & exit /b 1)
findstr /C:"P11_C4_WRAP TB PASS" xsim_c4w.log >nul || (type xsim_c4w.log & exit /b 1)
findstr /C:"P11_C4_WRAP TB PASS" xsim_c4w.log
exit /b 0
