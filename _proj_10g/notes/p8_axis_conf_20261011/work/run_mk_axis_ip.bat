@echo off
set MSYS_NO_PATHCONV=1
set WDIR=D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p8_axis_conf_20261011\work
call "C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat" -mode batch -source "%WDIR%\mk_axis_ip.tcl" -nojournal -nolog
echo P8AXIS_EXITCODE=%ERRORLEVEL%
