@echo off
REM ==========================================================================
REM build_p5_orphan_wrapper.bat <OVL:0|1>
REM   compile + elaborate tb_p5_orphan_wrapper (APP_MODE; OVL=1 also -d TCP_TX_OVL)
REM   work dir: sim\p9_orphan\work_p5orphan_<OVL>
REM ==========================================================================
setlocal
pushd "%~dp0..\.."
set "ROOT=%CD%"
popd
set "XV=C:\AMDDesignTools\2025.2\Vivado\bin"
set "OVL=%~1"
set "WD=%~dp0work_p5orphan_%OVL%"
set "HLS=%ROOT%\hls\slowstack_prj\solution1\syn\verilog"
if not exist "%WD%" mkdir "%WD%"
cd /d "%WD%"
if exist xsim.dir rmdir /s /q xsim.dir
copy /y "%HLS%\*.dat" . > nul
(dir /b /s "%HLS%\*.v") > hls_files_p5orphan.f
if not exist hls_files_p5orphan.f ( echo GATE_RESULT ERROR_NO_HLS & exit /b 2 )

set "DFLAGS=-d APP_MODE"
if "%OVL%"=="1" set "DFLAGS=-d APP_MODE -d TCP_TX_OVL"

call "%XV%\xvlog.bat" -work xil_defaultlib %DFLAGS% -f hls_files_p5orphan.f > xvlog_hls.log 2>&1
if errorlevel 1 ( echo GATE_RESULT ERROR_XVLOG_HLS & type xvlog_hls.log & exit /b 2 )
call "%XV%\xvlog.bat" -work xil_defaultlib %DFLAGS% ^
  "%ROOT%\rtl\crc32_8b.v" "%ROOT%\rtl\fifo_sync.v" "%ROOT%\rtl\checksum16.v" "%ROOT%\rtl\frame_fifo.v" ^
  "%ROOT%\rtl\mac_rx_64.v" "%ROOT%\rtl\mac_tx_64.v" "%ROOT%\rtl\tcp_cam.v" "%ROOT%\rtl\tcb.v" ^
  "%ROOT%\rtl\tcp_rx.v" "%ROOT%\rtl\tcp_tx_frame.v" "%ROOT%\rtl\retx_ram.v" "%ROOT%\rtl\tcp_echo.v" ^
  "%ROOT%\rtl\axis_pipe.v" "%ROOT%\rtl\rx_classify.v" "%ROOT%\rtl\vlan_strip.v" ^
  "%ROOT%\rtl\slow_rx_adp.v" "%ROOT%\rtl\slow_cfg_adp.v" "%ROOT%\rtl\slow_tx_adp.v" ^
  "%ROOT%\rtl\udp_rx.v" "%ROOT%\rtl\udp_split.v" "%ROOT%\rtl\tx_arb.v" ^
  "%ROOT%\rtl\udp_tx_cfg.v" "%ROOT%\rtl\udp_tx_frame.v" ^
  "%ROOT%\rtl\app_ctrl.v" "%ROOT%\rtl\app_pattern.v" "%ROOT%\rtl\app_udp_pattern.v" "%ROOT%\rtl\app_status_uart.v" ^
  "%ROOT%\board\wrapper_p4.v" "%ROOT%\board\util_gmii_to_rgmii.v" "%ROOT%\board\uart_dbg.v" ^
  "%ROOT%\tb\tb_p5_orphan_wrapper.v" > xvlog_gate.log 2>&1
if errorlevel 1 ( echo GATE_RESULT ERROR_XVLOG & type xvlog_gate.log & exit /b 2 )
call "%XV%\xvlog.bat" -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" >> xvlog_gate.log 2>&1
if errorlevel 1 ( echo GATE_RESULT ERROR_XVLOG_GLBL & type xvlog_gate.log & exit /b 2 )

call "%XV%\xelab.bat" -debug typical -L unisims_ver xil_defaultlib.tb_p5_orphan_wrapper xil_defaultlib.glbl -s tb_p5_orphan_wrapper -generic_top "ZW_EN_TB=%OVL%" -log xelab_gate.log > nul 2>&1
if errorlevel 1 ( echo GATE_RESULT ERROR_XELAB & type xelab_gate.log & exit /b 2 )
REM implicit-net / bit-width gate (pit #24, 5-key table)
findstr /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xelab_gate.log > implicit_hits.txt
for %%F in (implicit_hits.txt) do if %%~zF GTR 0 ( echo GATE_RESULT IMPLICIT_FAIL & type implicit_hits.txt & exit /b 2 )
echo GATE_BUILD_OK OVL=%OVL%
exit /b 0
