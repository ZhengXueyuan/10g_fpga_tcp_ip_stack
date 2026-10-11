@echo off
REM run_rehearsal.bat -- P9 D-fix round: mutation rehearsal for the p6e clr checks
REM   RTL swap: %ROOT%tlxis_c2h_stream.v  ->  %~dp0axis_c2h_stream_OLDCLR.v
REM     (= git 173b18d version = old semantics 'clr emits the residue as a short tail'; rest identical)
REM   Expect: new P9-B-5h/5i/5m1/5m2/5m6... MUST go red (proves the checks catch 'clr emits residue again')
setlocal
set XV=C:\AMDDesignTools\2025.2\Vivado\bin
set ROOT=D:\repo\XCKU5PMini\udp_hls_10g
cd /d %~dp0
if exist xsim.dir rmdir /s /q xsim.dir
dir /b /s "%ROOT%\rtl\*.v"                                    > files.f
findstr /V /I /C:"axis_c2h_stream.v" files.f                  > files2.f
echo %~dp0axis_c2h_stream_OLDCLR.v                           >> files2.f
dir /b /s "%ROOT%\hls\slowstack_prj\solution1\syn\verilog\*.v" >> files2.f
echo %ROOT%\board\wrapper_p4.v                                >> files2.f
echo %ROOT%\board\util_gmii_to_rgmii_us.v                     >> files2.f
echo %ROOT%\board\uart_dbg.v                                  >> files2.f
echo %ROOT%\_proj_pcie\rtl\axi_regs.v                         >> files2.f
echo %ROOT%\sim\p6e_pcie\xdma_0_sim_stub.v                    >> files2.f
echo %ROOT%\sim\p6e_pcie\tb_p6e_pcie_wrapper.v                >> files2.f
call %XV%\xvlog.bat -work xil_defaultlib -d PCIE_OBS -d DEV_USP -d APP_MODE -d DP_156MHZ -d P6B_SIM_CLKGEN -i %ROOT%\rtl -i %ROOT%\board -f files2.f > xvlog_reh.log 2>&1
echo XVLOG_RC=%ERRORLEVEL%
call %XV%\xvlog.bat -d PCIE_OBS -d DEV_USP -d APP_MODE -d DP_156MHZ -d P6B_SIM_CLKGEN -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" >> xvlog_reh.log 2>&1
call %XV%\xelab.bat -debug typical -L unisims_ver xil_defaultlib.tb_p6e_pcie_wrapper xil_defaultlib.glbl -s tb_p6e_reh -log xelab_reh.log > NUL 2>&1
echo XELAB_RC=%ERRORLEVEL%
call %XV%\xsim.bat tb_p6e_reh -runall -log xsim_reh.log > NUL 2>&1
findstr /C:"PASS_ALL" /C:"FAIL      " xsim_reh.log
echo --- FAIL lines ---
findstr /C:"[FAIL]" xsim_reh.log
exit /b 0
