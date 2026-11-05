@echo off
REM run_build_0x3D.bat -- P11 DIAG: same as 0x3C (P11_FIN_FIX=1) + W98/W99 TX stall bundle.
REM   Zero-geometry diag: W71/W72 repurposed (P11_DIAG_TX=1); NW 98 / UNIMPL 0x1B8 unchanged.
set P11_CFG=c4
set P11_APP8=1
set P11_APP8_OCC=0
set P11_APP8_CDC=1
set P11_HLS_VARIANT=p11fix_fin
set P11_DIAG_TX=1
set P11_IMPL_STRATEGY=Congestion_SpreadLogic_high
call "%~dp0..\..\..\board\run_build_p7b_ku5p.bat"
exit /b %ERRORLEVEL%
