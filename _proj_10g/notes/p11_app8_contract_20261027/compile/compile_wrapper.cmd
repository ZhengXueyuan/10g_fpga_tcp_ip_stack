@echo off
cd /d %~dp0
set V=C:\AMDDesignTools\2025.2\Vivado\bin
call "%V%\xvlog.bat" --nolog -L work -d APP_MODE -d DEV_USP -d PCIE_OBS -d DP_156MHZ -d P7B_10G -d UDP_TX_OVL -d TCP_TX_OVL -d P11_CFG_C4 -d P11_CFG_ENFORCE -d SFP2_MODE_A -d DUAL_SFP_A -d P11_DUAL -d P11_HLS_ADV_WND ..\..\..\..\board\wrapper_p4.v > xvlog_wrap.log 2>&1
echo WRAP_RC=%ERRORLEVEL%
call "%V%\xvlog.bat" --nolog -L work -d APP_MODE -d DEV_USP -d PCIE_OBS -d DP_156MHZ -d P7B_10G -d UDP_TX_OVL -d TCP_TX_OVL -d P11_CFG_C4 -d P11_CFG_ENFORCE -d SFP2_MODE_A -d DUAL_SFP_A -d P11_DUAL -d P11_HLS_ADV_WND -d P11_APP8 ..\..\..\..\board\wrapper_p4.v > xvlog_wrap_app8.log 2>&1
echo WRAP8_RC=%ERRORLEVEL%
exit /b 0
