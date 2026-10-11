@echo off
setlocal
set XV=C:\AMDDesignTools\2025.2\Vivado\bin
set ROOT=D:\repo\XCKU5PMini\udp_hls_10g
cd /d %~dp0
dir /b /s "%ROOT%\rtl\*.v"                                    > files.f
dir /b /s "%ROOT%\hls\slowstack_prj\solution1\syn\verilog\*.v" >> files.f
echo %~dp0wrapper_p4_head.v                                   >> files.f
echo %ROOT%\board\util_gmii_to_rgmii_us.v                     >> files.f
echo %ROOT%\board\util_gmii_to_rgmii.v                        >> files.f
echo %ROOT%\board\uart_dbg.v                                  >> files.f
echo %ROOT%\_proj_pcie\rtl\axi_regs.v                         >> files.f
echo %ROOT%\sim\p6e_pcie\xdma_0_sim_stub.v                    >> files.f
call %XV%\xvlog.bat -work xil_defaultlib -d PCIE_OBS -d DEV_USP -i %ROOT%\rtl -i %ROOT%\board -f files.f > xvlog_head_arm.log 2>&1
echo XVLOG_RC=%ERRORLEVEL%
findstr /C:"10-2989" xvlog_head_arm.log > err10_2989_head_arm.txt
find /c /v "" err10_2989_head_arm.txt
exit /b 0
