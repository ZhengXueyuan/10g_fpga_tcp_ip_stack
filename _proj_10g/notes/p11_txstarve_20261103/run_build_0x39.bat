@echo off
REM run_build_0x39.bat -- P11 APP8 CDC DIAGNOSTIC arm (0x39): per-slot app_tx_ready + init counters.
REM   tx_arb STARVE_GUARD is DISABLED (review overturn, DESIGN section 9). OCC=0.
set P11_CFG=c4
set P11_APP8=1
set P11_APP8_OCC=0
set P11_APP8_CDC=1
set P11_IMPL_STRATEGY=Performance_ExtraTimingOpt
call D:\repo\XCKU5PMini\udp_hls_10g\board\run_build_p7b_ku5p.bat
exit /b %ERRORLEVEL%
