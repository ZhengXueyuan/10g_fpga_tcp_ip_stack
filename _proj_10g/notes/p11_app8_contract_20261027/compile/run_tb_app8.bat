@echo off
cd /d %~dp0
set V=C:\AMDDesignTools\2025.2\Vivado\bin
if exist xsim.dir rmdir /s /q xsim.dir
call "%V%\xvlog.bat" --nolog -L work -d P7B_10G ..\..\..\..\rtl\app_pattern.v ..\..\..\..\rtl\axis_frame_mux8.v ..\..\..\..\rtl\axis_tid_demux8.v ..\..\..\..\rtl\app_close_arb8.v ..\..\..\..\rtl\app_multi8.v ..\tb_app_multi8.v > xvlog.log 2>&1
if errorlevel 1 (echo XVLOG_FAIL & type xvlog.log & exit /b 1)
call "%V%\xelab.bat" --nolog -L work tb_app_multi8 -s tb_app8 > xelab.log 2>&1
if errorlevel 1 (echo XELAB_FAIL & type xelab.log & exit /b 2)
call "%V%\xsim.bat" --nolog tb_app8 -R > xsim.log 2>&1
echo XSIM_RC=%ERRORLEVEL%
exit /b %ERRORLEVEL%
