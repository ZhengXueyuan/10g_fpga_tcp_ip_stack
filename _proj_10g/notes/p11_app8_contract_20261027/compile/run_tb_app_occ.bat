@echo off
cd /d %~dp0
set XV=C:\AMDDesignTools\2025.2\Vivado\bin
set ROOT=D:\repo\XCKU5PMini\udp_hls_10g
set D=%ROOT%\_proj_10g\notes\p11_app8_contract_20261027
call %XV%\xvlog.bat -work xil_defaultlib %ROOT%\rtl\app_ctrl.v %D%\tb_app_ctrl_occ.v > xvlog_appocc.log 2>&1 || (type xvlog_appocc.log & exit /b 1)
call %XV%\xvlog.bat -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" >> xvlog_appocc.log 2>&1 || (type xvlog_appocc.log & exit /b 1)
call %XV%\xelab.bat -debug typical xil_defaultlib.tb_app_ctrl_occ xil_defaultlib.glbl -s tb_app_occ -log xelab_appocc.log > NUL 2>&1 || (type xelab_appocc.log & exit /b 1)
call %XV%\xsim.bat tb_app_occ -runall -log xsim_appocc.log > NUL 2>&1
findstr /C:"TB_APP_OCC_FAIL" /C:"FAIL" xsim_appocc.log >NUL && (findstr /C:"TB_APP_OCC_FAIL" /C:"FAIL" xsim_appocc.log & echo TB_APP_OCC_FAIL & exit /b 1)
findstr /C:"TB_APP_OCC_PASS" xsim_appocc.log >NUL && (findstr /C:"TB_APP_OCC_PASS" xsim_appocc.log & echo TB_APP_OCC_PASS & exit /b 0)
echo TB_APP_OCC_NO_VERDICT & exit /b 1
