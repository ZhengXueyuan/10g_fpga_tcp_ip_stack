@echo off
cd /d %~dp0
set XV=C:\AMDDesignTools\2025.2\Vivado\bin
set RTL=D:\repo\XCKU5PMini\udp_hls_10g\rtl
call "%XV%\xvlog.bat" -work xil_defaultlib -d TCP_TX_OVL -d DP_156MHZ -d APP_MODE -log xvlog.log ^
  "%RTL%\crc32_8b.v" "%RTL%\fifo_sync.v" "%RTL%\checksum16.v" ^
  "%RTL%\frame_fifo.v" "%RTL%\retx_ram.v" "%RTL%\axis_pipe.v" ^
  "%RTL%\tcp_tx_frame.v"
echo XVLOG_RC=%ERRORLEVEL%
