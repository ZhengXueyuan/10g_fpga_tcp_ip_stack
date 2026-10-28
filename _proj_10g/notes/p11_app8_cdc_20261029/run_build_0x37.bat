@echo off
REM run_build_0x37.bat -- P11 APP8 CDC+OCC arm, OCC=1 (0x37).
REM   Build inputs are explicit here (strategy = a build input, not "retry until pass").
REM   Does NOT program the board.
set P11_CFG=c4
set P11_APP8=1
set P11_APP8_OCC=1
set P11_APP8_CDC=1
set P11_IMPL_STRATEGY=Performance_ExtraTimingOpt
call D:\repo\XCKU5PMini\udp_hls_10g\board\run_build_p7b_ku5p.bat
exit /b %ERRORLEVEL%
