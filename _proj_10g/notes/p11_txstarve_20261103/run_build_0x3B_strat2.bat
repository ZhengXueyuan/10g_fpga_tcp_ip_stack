@echo off
REM run_build_0x3B_strat2.bat -- same 0x3B RTL/netlist, strategy arm 2:
REM   Performance_ExplorePostRoutePhysOpt (marginal DP route paths; new build input).
set P11_CFG=c4
set P11_APP8=1
set P11_APP8_OCC=0
set P11_APP8_CDC=1
set P11_IMPL_STRATEGY=Performance_ExplorePostRoutePhysOpt
call D:\repo\XCKU5PMini\udp_hls_10g\board\run_build_p7b_ku5p.bat
exit /b %ERRORLEVEL%
