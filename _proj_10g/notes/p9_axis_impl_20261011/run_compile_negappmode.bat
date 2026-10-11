@echo off
REM run_compile_negappmode.bat -- P9 compile-coverage arm: PCIE_OBS + DEV_USP (no APP_MODE / no DP_156MHZ)
REM   Reason: the standing lint (board\run_lint_p6e.bat) and the p6e chain gate each cover
REM   ONE macro combo only; this round added AXIS constant tables to BOTH neg-branches =>
REM   the PCIE_OBS AND NOT APP_MODE branch has no standing gate. Compile+elaborate only.
REM   Criteria: implicit-net 5-key + 10-3091 width + no ERROR + elaborate wrapper_p4 OK.
setlocal
set XV=C:\AMDDesignTools\2025.2\Vivado\bin
set ROOT=D:\repo\XCKU5PMini\udp_hls_10g
cd /d %~dp0
if not exist xdir_negapp mkdir xdir_negapp
cd xdir_negapp
if exist xsim.dir rmdir /s /q xsim.dir
dir /b /s "%ROOT%\rtl\*.v"                                    > files.f
dir /b /s "%ROOT%\hls\slowstack_prj\solution1\syn\verilog\*.v" >> files.f
echo %ROOT%\board\wrapper_p4.v                                >> files.f
echo %ROOT%\board\util_gmii_to_rgmii_us.v                     >> files.f
echo %ROOT%\board\util_gmii_to_rgmii.v                        >> files.f
echo %ROOT%\board\uart_dbg.v                                  >> files.f
echo %ROOT%\_proj_pcie\rtl\axi_regs.v                         >> files.f
echo %ROOT%\sim\p6e_pcie\xdma_0_sim_stub.v                    >> files.f
call %XV%\xvlog.bat -work xil_defaultlib -d PCIE_OBS -d DEV_USP -i %ROOT%\rtl -i %ROOT%\board -f files.f > xvlog_negapp.log 2>&1 || (type xvlog_negapp.log & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xvlog_negapp.log >NUL && (echo IMPLICIT-DECL-FAIL & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xvlog_negapp.log & exit /b 1)
findstr /C:"10-3091" xvlog_negapp.log >NUL && (echo BITWIDTH-MISMATCH-FAIL & findstr /C:"10-3091" xvlog_negapp.log & exit /b 1)
findstr /I /C:"ERROR" xvlog_negapp.log >NUL && (echo XVLOG-ERROR-FAIL & findstr /I /C:"ERROR" xvlog_negapp.log & exit /b 1)
call %XV%\xvlog.bat -d PCIE_OBS -d DEV_USP -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" >> xvlog_negapp.log 2>&1 || (type xvlog_negapp.log & exit /b 1)
call %XV%\xelab.bat -debug typical -L unisims_ver xil_defaultlib.wrapper_p4 xil_defaultlib.glbl -s negapp -log xelab_negapp.log > NUL 2>&1 || (type xelab_negapp.log & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" xelab_negapp.log >NUL && (echo IMPLICIT-DECL-FAIL-XELAB & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" xelab_negapp.log & exit /b 1)
echo NEGAPPMODE-COMPILE-OK
exit /b 0
