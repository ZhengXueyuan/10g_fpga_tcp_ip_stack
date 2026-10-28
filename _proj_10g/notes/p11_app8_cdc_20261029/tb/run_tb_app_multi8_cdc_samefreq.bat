@echo off
cd /d %~dp0
set V=C:\AMDDesignTools\2025.2\Vivado\bin
set R=..\..\..\..
if exist xsim.dir rmdir /s /q xsim.dir
call "%V%\xvlog.bat" --nolog -L work -d P7B_10G %R%\rtl\app_pattern.v %R%\rtl\axis_frame_mux8.v %R%\rtl\axis_tid_demux8.v %R%\rtl\app_close_arb8.v %R%\rtl\app_multi8.v %R%\rtl\app_multi8_cdc.v %R%\rtl\fifo_async.v tb_app_multi8_cdc_samefreq.v > xvlog.log 2>&1
if errorlevel 1 (echo XVLOG_FAIL & type xvlog.log & exit /b 1)
call "%V%\xelab.bat" --nolog -L work tb_app_multi8_cdc_samefreq -s tb_app8_cdc_sf > xelab.log 2>&1
if errorlevel 1 (echo XELAB_FAIL & type xelab.log & exit /b 2)
call "%V%\xsim.bat" --nolog tb_app8_cdc_sf -R > xsim.log 2>&1
echo XSIM_RC=%ERRORLEVEL%
exit /b %ERRORLEVEL%
