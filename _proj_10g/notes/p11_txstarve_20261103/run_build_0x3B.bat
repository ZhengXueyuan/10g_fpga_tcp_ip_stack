@echo off
REM run_build_0x3B.bat -- P11 APP8 CDC DIAGNOSTIC 0x3B: W51..W53 reuse (zero new FF).
set P11_CFG=c4
set P11_APP8=1
set P11_APP8_OCC=0
set P11_APP8_CDC=1
set P11_IMPL_STRATEGY=Performance_ExtraTimingOpt
call D:\repo\XCKU5PMini\udp_hls_10g\board\run_build_p7b_ku5p.bat
exit /b %ERRORLEVEL%
