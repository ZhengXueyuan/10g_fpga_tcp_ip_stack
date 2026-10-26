@echo off
cd /d %~dp0
set XV=C:\AMDDesignTools\2025.2\Vivado\bin
set RTL=D:\repo\XCKU5PMini\udp_hls_10g\rtl
set TBD=D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p11_e1a_design_20261027
call "%XV%\xvlog.bat" -work xil_defaultlib -d TCP_TX_OVL -d DP_156MHZ -d APP_MODE -log xvlog_tb.log ^
  "%RTL%\crc32_8b.v" "%RTL%\fifo_sync.v" "%RTL%\checksum16.v" ^
  "%RTL%\frame_fifo.v" "%RTL%\retx_ram.v" "%RTL%\axis_pipe.v" ^
  "%RTL%\tcp_tx_frame.v" "%TBD%\tb_e1a_draft.v"
if errorlevel 1 (echo XVLOG_FAIL & type xvlog_tb.log & exit /b 1)
call "%XV%\xvlog.bat" -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" -log xvlog_glbl.log
call "%XV%\xelab.bat" -debug typical -L unisims_ver xil_defaultlib.tb_e1a_draft xil_defaultlib.glbl -s tb_e1a_draft -log xelab.log
if errorlevel 1 (echo XELAB_FAIL & type xelab.log & exit /b 1)
call "%XV%\xsim.bat" tb_e1a_draft -R -log xsim.log
echo XSIM_RC=%ERRORLEVEL%
type xsim.log
