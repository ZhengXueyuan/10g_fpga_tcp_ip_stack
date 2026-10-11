@echo off
setlocal
set XV=C:\AMDDesignTools\2025.2\Vivado\bin
set ROOT=D:\repo\XCKU5PMini\udp_hls_10g
cd /d %~dp0
call %XV%\xvlog.bat -d PCIE_OBS -d DEV_USP -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" >> xvlog_head.log 2>&1
call %XV%\xelab.bat -debug typical -L unisims_ver xil_defaultlib.wrapper_p4 xil_defaultlib.glbl -s negapp_patched -log xelab_negapp.log > NUL 2>&1
echo XELAB_RC=%ERRORLEVEL%
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" xelab_negapp.log >NUL && (echo IMPLICIT-DECL-FAIL-XELAB & exit /b 1)
findstr /C:"Built simulation snapshot" xelab_negapp.log
exit /b 0
