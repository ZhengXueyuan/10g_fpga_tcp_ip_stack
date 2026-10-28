@echo off
set XV=C:\AMDDesignTools\2025.2\Vivado\bin
set R=D:\repo\XCKU5PMini\udp_hls_10g
cd /d %~dp0
call "%XV%\xvlog.bat" "%R%\rtl\app_clk_gen.v" "%R%\rtl\app_multi8_cdc.v" "%R%\rtl\app_multi8.v" "%R%\rtl\app_pattern.v" "%R%\rtl\axis_frame_mux8.v" "%R%\rtl\axis_tid_demux8.v" "%R%\rtl\app_close_arb8.v" "%R%\rtl\fifo_async.v" > xvlog_stdout.txt 2>&1
echo XVLOG_RC=%ERRORLEVEL%
call "%XV%\xelab.bat" -L unisim app_multi8_cdc -s check_cdc > xelab_cdc_stdout.txt 2>&1
echo XELAB_CDC_RC=%ERRORLEVEL%
call "%XV%\xelab.bat" -L unisim app_clk_gen -s check_clk > xelab_clk_stdout.txt 2>&1
echo XELAB_CLK_RC=%ERRORLEVEL%
