@echo off
cd /d %~dp0
set V=C:\AMDDesignTools\2025.2\Vivado\bin
call "%V%\xvlog.bat" --nolog ..\..\..\..\rtl\slow_cfg_adp.v ..\..\..\..\rtl\tcp_echo.v ..\..\..\..\rtl\app_ctrl.v > xvlog_occ_rtl.log 2>&1
echo OCC_RTL_RC=%ERRORLEVEL%
call "%V%\xvlog.bat" --nolog -d APP_MODE -d DEV_USP -d PCIE_OBS -d DP_156MHZ -d P7B_10G -d UDP_TX_OVL -d TCP_TX_OVL -d P11_CFG_C4 -d P11_CFG_ENFORCE -d SFP2_MODE_A -d DUAL_SFP_A -d P11_DUAL -d P11_HLS_ADV_WND -d P11_APP8 -d P11_APP8_OCC ..\..\..\..\board\wrapper_p4.v > xvlog_wrap_occ1.log 2>&1
echo OCC_WRAP1_RC=%ERRORLEVEL%
call "%V%\xvlog.bat" --nolog -d APP_MODE -d DEV_USP -d PCIE_OBS -d DP_156MHZ -d P7B_10G -d UDP_TX_OVL -d TCP_TX_OVL -d P11_CFG_C4 -d P11_CFG_ENFORCE -d SFP2_MODE_A -d DUAL_SFP_A -d P11_DUAL -d P11_HLS_ADV_WND -d P11_APP8 ..\..\..\..\board\wrapper_p4.v > xvlog_wrap_occ0.log 2>&1
echo OCC_WRAP0_RC=%ERRORLEVEL%
exit /b 0
