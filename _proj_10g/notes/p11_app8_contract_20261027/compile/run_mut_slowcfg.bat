@echo off
cd /d D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p11_app8_contract_20261027\compile
set XV=C:\AMDDesignTools\2025.2\Vivado\bin
call %XV%\xvlog.bat -work xil_defaultlib "D:\repo\XCKU5PMini\udp_hls_10g\rtl\fifo_sync.v" "D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p11_app8_contract_20261027\compile\mutants\m0_slowcfg_fixed48\slow_cfg_adp.v" "D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p11_app8_contract_20261027\tb_slow_cfg_init.v" > xvlog_mut_slow.log 2>&1 || exit /b 1
call %XV%\xvlog.bat -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" >> xvlog_mut_slow.log 2>&1 || exit /b 1
call %XV%\xelab.bat -debug typical xil_defaultlib.tb_slow_cfg_init xil_defaultlib.glbl -s snap_mut_slow -log xelab_mut_slow.log > NUL 2>&1 || exit /b 1
call %XV%\xsim.bat snap_mut_slow -runall -log xsim_mut_slow.log > NUL 2>&1
exit /b 0
