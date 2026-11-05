@echo off
REM run_build_0x3C.bat -- P11 FIN-priority fix (P11_FIN_FIX=1) build; BID 0x3C.
set P11_CFG=c4
set P11_APP8=1
set P11_APP8_OCC=0
set P11_APP8_CDC=1
set P11_HLS_VARIANT=p11fix_fin
set P11_IMPL_STRATEGY=Congestion_SpreadLogic_high
call "%~dp0..\..\..\board\run_build_p7b_ku5p.bat"
exit /b %ERRORLEVEL%
