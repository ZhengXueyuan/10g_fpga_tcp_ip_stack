@echo off
cd /d %~dp0
set V=C:\AMDDesignTools\2025.2\Vivado\bin
call "%V%\xvlog.bat" --nolog ..\..\..\..\rtl\app_pattern.v ..\..\..\..\rtl\axis_frame_mux8.v ..\..\..\..\rtl\axis_tid_demux8.v ..\..\..\..\rtl\app_close_arb8.v ..\..\..\..\rtl\app_multi8.v > xvlog_rtl.log 2>&1
echo XVLOG_RC=%ERRORLEVEL%
exit /b %ERRORLEVEL%
