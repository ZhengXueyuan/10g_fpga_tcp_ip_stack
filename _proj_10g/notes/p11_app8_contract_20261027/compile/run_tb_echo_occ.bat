@echo off
REM tb_echo_occ: P11 APP8 v6 tcp_echo per-conn occupancy unit gate
REM   (implicit nets and bit-width mismatches are hard failures)
cd /d %~dp0
set XV=C:\AMDDesignTools\2025.2\Vivado\bin
set ROOT=D:\repo\XCKU5PMini\udp_hls_10g
set D=%ROOT%\_proj_10g\notes\p11_app8_contract_20261027
call %XV%\xvlog.bat -work xil_defaultlib -d DEV_USP %ROOT%\rtl\fifo_sync.v %ROOT%\rtl\frame_fifo.v %ROOT%\rtl\tcp_echo.v %D%\tb_echo_occ.v > xvlog_occ.log 2>&1 || (type xvlog_occ.log & exit /b 1)
call %XV%\xvlog.bat -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" >> xvlog_occ.log 2>&1 || (type xvlog_occ.log & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xvlog_occ.log >NUL && (echo IMPLICIT-DECL-FAIL & type xvlog_occ.log & exit /b 1)
findstr /C:"10-3091" xvlog_occ.log >NUL && (echo BITWIDTH-MISMATCH-FAIL & type xvlog_occ.log & exit /b 1)
call %XV%\xelab.bat -debug typical -L unisims_ver xil_defaultlib.tb_echo_occ xil_defaultlib.glbl -s tb_echo_occ -log xelab_occ.log > NUL 2>&1 || (type xelab_occ.log & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xelab_occ.log >NUL && (echo IMPLICIT-DECL-FAIL-XELAB & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xelab_occ.log & exit /b 1)
call %XV%\xsim.bat tb_echo_occ -runall -log xsim_occ.log > NUL 2>&1
findstr /C:"TB_ECHO_OCC_FAIL" /C:"FAIL" xsim_occ.log >NUL && (findstr /C:"TB_ECHO_OCC_FAIL" /C:"FAIL" xsim_occ.log & echo TB_ECHO_OCC_FAIL & exit /b 1)
findstr /C:"TB_ECHO_OCC_PASS" xsim_occ.log >NUL && (findstr /C:"TB_ECHO_OCC_PASS" xsim_occ.log & echo TB_ECHO_OCC_PASS & exit /b 0)
echo TB_ECHO_OCC_NO_VERDICT & exit /b 1
