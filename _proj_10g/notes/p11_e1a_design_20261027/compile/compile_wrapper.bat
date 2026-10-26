@echo off
cd /d %~dp0
set XV=C:\AMDDesignTools\2025.2\Vivado\bin
call "%XV%\xvlog.bat" -work xil_defaultlib -d APP_MODE -d DEV_USP -d PCIE_OBS -d DP_156MHZ -d P7B_10G -d UDP_TX_OVL -d TCP_TX_OVL -d P11_CFG_C4 -d P11_CFG_ENFORCE -d SFP2_MODE_A -d DUAL_SFP_A -d P11_DUAL -d P11_HLS_ADV_WND -log xvlog_wrap.log ^
  "D:\repo\XCKU5PMini\udp_hls_10g\board\wrapper_p4.v"
echo XVLOG_WRAP_RC=%ERRORLEVEL%
type xvlog_wrap.log
