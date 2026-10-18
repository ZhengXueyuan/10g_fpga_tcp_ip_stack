@echo off
REM run_tb_p7b_chain.bat - P7b REAL-wrapper full-chain gate (project trap 8).
REM   Compile defines MUST match the real build: PCIE_OBS + DEV_USP + APP_MODE
REM   + DP_156MHZ + P7B_10G + UDP_TX_OVL + TCP_TX_OVL, plus the two
REM   simulation-only ones:
REM     P6B_SIM_CLKGEN  - clk_gen_p6b uses its behavioural clock model
REM     P7B_SIM_NOPCS   - the official xxv_ethernet PCS socket holds
REM                       board/p7b_pcs_stub.v (same port list) instead of the
REM                       encrypted GT IP (which was never simulated).
REM   2026-10-18 (P1 impl round): `TCP_TX_OVL` added so this gate compiles
REM      the SAME tcp_tx_frame body the board runs (build_p7b_ku5p.tcl:286).
REM      Before this, the gate covered only the default (serial) body.
REM   2026-10-18: matrix-ready. Repo root comes from sim\p4gates\p4env.bat
REM      (self-locating); when the P4 matrix exports P4_WORKDIR the gate runs
REM      in that private cwd (pit 7: no xsim.dir locks across gates). The
REM      compile set is: every compile unit is a LITERAL %ROOT%\..\.v token on
REM      the xvlog line (so p4gate.py manifestcheck can see it), while the
REM      HLS netlist is a generated -f list (173 files; declared in the
REM      manifest header as out of the literal cross-check).
REM   from Git Bash: cmd //c '_proj_10g\p7b_chain\sim\run_tb_p7b_chain.bat'
setlocal
call "%~dp0..\..\..\sim\p4gates\p4env.bat" || exit /b 1
set "ROOT=%REPO_ROOT%"
if not "%P4_WORKDIR%"=="" (
  cd /d "%P4_WORKDIR%"
) else (
  cd /d %~dp0
)
if exist xsim.dir rmdir /s /q xsim.dir
if exist xsim_p7bchain.log del /q xsim_p7bchain.log
REM   P7B_MUT: optional override (mutation testing) -- when set, wrapper_p4.v
REM            and the MAC rtl are taken from that scratch directory instead.
set "WRAP=%ROOT%\board\wrapper_p4.v"
set "MACD=%ROOT%\_proj_10g\p7b_mac\rtl"
if not "%P7B_MUT%"=="" set "WRAP=%P7B_MUT%\wrapper_p4.v"
if not "%P7B_MUT%"=="" set "MACD=%P7B_MUT%"
if not exist "%WRAP%" (echo [PATHGUARD FAIL] no wrapper_p4.v & exit /b 1)
if not exist "%MACD%\mac_rx_10g.v" (echo [PATHGUARD FAIL] no mac_rx_10g.v in %MACD% & exit /b 1)
REM ---- P11 F-21 static structure gate (source level, BEFORE compiling) ------
REM   0x2D backstop-2: TOPN=2 -> W84/W83 must read p7bdp_dout[40..39]
REM   (coherent CDC), never w8x_snap. W85..W87 are deleted from the snapshot.
REM   Teeth were verified on the pre-fix HEAD wrapper (see the fix-round report).
"%PY%" "%ROOT%\_proj_10g\p7b_chain\sim\check_snap_top5_wired.py" --root "%ROOT%"
if errorlevel 1 (echo SNAP_TOP5_STATIC_GATE_FAIL & exit /b 1)
REM Provenance: every log must carry which RTL set it compiled (P7B_CHAIN_COVERAGE 2026-09-30).
echo [RTL] WRAP=%WRAP%
echo [RTL] MACD=%MACD%
REM  HLS netlist: generated -f list (173 files). Kept OUT of the literal
REM  cross-check below on purpose (manifestcheck only parses .v tokens on the
REM  xvlog line; inlining 173 generated names would make the manifest rot on
REM  every HLS rebuild). HLS inputs are pinned by the hls tree itself.
dir /b /s "%ROOT%\hls\slowstack_prj\solution1\syn\verilog\*.v" > hls_p7bchain.f
REM 2026-10-18 gate debt: rtl/mir_uram_fifo.v instantiates xpm_memory_sdpram
REM (URAM buffer, in the tree since 0x24) => register xpm into a local library
REM and elaborate with -L xpm, exactly as sim/p6e_pcie/run_tb_p6e_pcie.bat does.
call %XV%\xvlog.bat -sv -work xpm "%XV%\..\data\ip\xpm\xpm_memory\hdl\xpm_memory.sv" > xvlog_xpm_p7bchain.log 2>&1 || (type xvlog_xpm_p7bchain.log & exit /b 1)
call %XV%\xvlog.bat -work xil_defaultlib -d P7B_10G -d P7B_SIM_NOPCS -d PCIE_OBS -d DEV_USP -d APP_MODE -d DP_156MHZ -d P6B_SIM_CLKGEN -d UDP_TX_OVL -d TCP_TX_OVL -i %ROOT%\rtl -i %ROOT%\board ^
  %ROOT%\rtl\app_ctrl.v %ROOT%\rtl\app_pattern.v %ROOT%\rtl\app_rx_mirror.v ^
  %ROOT%\rtl\app_status_uart.v %ROOT%\rtl\app_udp_pattern.v ^
  %ROOT%\rtl\aximm_c2h_win.v %ROOT%\rtl\aximm_h2c_discard.v ^
  %ROOT%\rtl\axis_c2h_stream.v %ROOT%\rtl\axis_pipe.v ^
  %ROOT%\rtl\checksum16.v %ROOT%\rtl\clk_gen_p6b.v %ROOT%\rtl\crc32_8b.v ^
  %ROOT%\rtl\fifo_async.v %ROOT%\rtl\fifo_sync.v %ROOT%\rtl\frame_fifo.v ^
  %ROOT%\rtl\mac_rx_64.v %ROOT%\rtl\mac_tx_64.v ^
  %ROOT%\rtl\mir_dma_ring.v %ROOT%\rtl\mir_uram_fifo.v %ROOT%\rtl\retx_ram.v ^
  %ROOT%\rtl\rx_classify.v %ROOT%\rtl\slow_cfg_adp.v %ROOT%\rtl\slow_rx_adp.v ^
  %ROOT%\rtl\slow_tx_adp.v %ROOT%\rtl\snap_cdc.v %ROOT%\rtl\snap_seq.v ^
  %ROOT%\rtl\tcb.v %ROOT%\rtl\tcp_cam.v %ROOT%\rtl\tcp_echo.v %ROOT%\rtl\tcp_rx.v ^
  %ROOT%\rtl\tcp_synp.v %ROOT%\rtl\tcp_tx_frame.v %ROOT%\rtl\tx_arb.v ^
  %ROOT%\rtl\udp_echo.v %ROOT%\rtl\udp_rx.v %ROOT%\rtl\udp_split.v ^
  %ROOT%\rtl\udp_tx_cfg.v %ROOT%\rtl\udp_tx_frame.v %ROOT%\rtl\vlan_strip.v ^
  %WRAP% %ROOT%\board\util_gmii_to_rgmii_us.v %ROOT%\board\uart_dbg.v ^
  %ROOT%\board\p7b_pcs_stub.v ^
  %ROOT%\_proj_pcie\rtl\axi_regs.v ^
  %MACD%\crc32_64.v %MACD%\mac_rx_10g.v %MACD%\mac_tx_10g.v ^
  %ROOT%\sim\p6e_pcie\xdma_0_sim_stub.v ^
  %ROOT%\_proj_10g\p7b_chain\sim\tb_p7b_chain.v ^
  -f hls_p7bchain.f > xvlog_p7bchain.log 2>&1 || (type xvlog_p7bchain.log & exit /b 1)
call %XV%\xvlog.bat -d P7B_10G -d P7B_SIM_NOPCS -d PCIE_OBS -d DEV_USP -d APP_MODE -d DP_156MHZ -d P6B_SIM_CLKGEN -d UDP_TX_OVL -d TCP_TX_OVL -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" >> xvlog_p7bchain.log 2>&1 || (type xvlog_p7bchain.log & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xvlog_p7bchain.log >NUL && (echo IMPLICIT-DECL-FAIL & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xvlog_p7bchain.log & exit /b 1)
findstr /I /C:"ERROR" xvlog_p7bchain.log >NUL && (echo XVLOG-ERROR-FAIL & findstr /I /C:"ERROR" xvlog_p7bchain.log & exit /b 1)
call %XV%\xelab.bat -debug typical -L unisims_ver -L xpm xil_defaultlib.tb_p7b_chain xil_defaultlib.glbl -s tb_p7b_chain -log xelab_p7bchain.log > NUL 2>&1 || (type xelab_p7bchain.log & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xelab_p7bchain.log >NUL && (echo IMPLICIT-DECL-FAIL-XELAB & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xelab_p7bchain.log & exit /b 1)
call %XV%\xsim.bat tb_p7b_chain -runall -log xsim_p7bchain.log > NUL 2>&1
findstr /C:"PASS" /C:"FAIL" /C:"VERDICT" /C:"TIMEOUT" xsim_p7bchain.log
findstr /C:"VERDICT = PASS" xsim_p7bchain.log >NUL || exit /b 1
exit /b 0
