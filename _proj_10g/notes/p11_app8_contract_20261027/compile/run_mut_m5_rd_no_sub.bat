@echo off
cd /d D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p11_app8_contract_20261027\compile
set XV=C:\AMDDesignTools\2025.2\Vivado\bin
call %XV%\xvlog.bat -work xil_defaultlib -d DEV_USP "D:\repo\XCKU5PMini\udp_hls_10g\rtl\fifo_sync.v" "D:\repo\XCKU5PMini\udp_hls_10g\rtl\frame_fifo.v" "D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p11_app8_contract_20261027\compile\mutants\m5_rd_no_sub\tcp_echo.v" "D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p11_app8_contract_20261027\tb_echo_occ.v" > xvlog_mut_m5_rd_no_sub.log 2>&1 || exit /b 1
call %XV%\xvlog.bat -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" >> xvlog_mut_m5_rd_no_sub.log 2>&1 || exit /b 1
call %XV%\xelab.bat -debug typical -L unisims_ver xil_defaultlib.tb_echo_occ xil_defaultlib.glbl -s snap_m5_rd_no_sub -log xelab_mut_m5_rd_no_sub.log > NUL 2>&1 || exit /b 1
call %XV%\xsim.bat snap_m5_rd_no_sub -runall -log xsim_mut_m5_rd_no_sub.log > NUL 2>&1
exit /b 0
