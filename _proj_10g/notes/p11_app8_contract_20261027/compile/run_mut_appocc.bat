@echo off
cd /d D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p11_app8_contract_20261027\compile
set XV=C:\AMDDesignTools\2025.2\Vivado\bin
call %XV%\xvlog.bat -work xil_defaultlib "D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p11_app8_contract_20261027\compile\mutants\m8_appocc_global\app_ctrl.v" "D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p11_app8_contract_20261027\tb_app_ctrl_occ.v" > xvlog_mut_appocc.log 2>&1 || exit /b 1
call %XV%\xvlog.bat -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" >> xvlog_mut_appocc.log 2>&1 || exit /b 1
call %XV%\xelab.bat -debug typical xil_defaultlib.tb_app_ctrl_occ xil_defaultlib.glbl -s snap_mut_appocc -log xelab_mut_appocc.log > NUL 2>&1 || exit /b 1
call %XV%\xsim.bat snap_mut_appocc -runall -log xsim_mut_appocc.log > NUL 2>&1
exit /b 0
