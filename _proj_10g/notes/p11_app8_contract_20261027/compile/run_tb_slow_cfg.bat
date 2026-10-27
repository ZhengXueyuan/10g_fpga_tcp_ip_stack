@echo off
cd /d %~dp0
set XV=C:\AMDDesignTools\2025.2\Vivado\bin
set ROOT=D:\repo\XCKU5PMini\udp_hls_10g
set D=%ROOT%\_proj_10g\notes\p11_app8_contract_20261027
call %XV%\xvlog.bat -work xil_defaultlib %ROOT%\rtl\fifo_sync.v %ROOT%\rtl\slow_cfg_adp.v %D%\tb_slow_cfg_init.v > xvlog_slow.log 2>&1 || (type xvlog_slow.log & exit /b 1)
call %XV%\xvlog.bat -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" >> xvlog_slow.log 2>&1 || (type xvlog_slow.log & exit /b 1)
call %XV%\xelab.bat -debug typical xil_defaultlib.tb_slow_cfg_init xil_defaultlib.glbl -s tb_slow_cfg -log xelab_slow.log > NUL 2>&1 || (type xelab_slow.log & exit /b 1)
call %XV%\xsim.bat tb_slow_cfg -runall -log xsim_slow.log > NUL 2>&1
findstr /C:"TB_SLOW_CFG_FAIL" /C:"FAIL" xsim_slow.log >NUL && (findstr /C:"TB_SLOW_CFG_FAIL" /C:"FAIL" xsim_slow.log & echo TB_SLOW_CFG_FAIL & exit /b 1)
findstr /C:"TB_SLOW_CFG_PASS" xsim_slow.log >NUL && (findstr /C:"TB_SLOW_CFG_PASS" xsim_slow.log & echo TB_SLOW_CFG_PASS & exit /b 0)
echo TB_SLOW_CFG_NO_VERDICT & exit /b 1
