@echo off
REM run_build_0x40.bat -- R1 half-open aging (BID 0x40).
REM   P11_APP8_CDC build + new HLS variant p11fix_fin_r1 (i_slot_dead port).
REM   Strategy = the 0x3F passing one (Congestion_SpreadLogic_low).
REM   F2 kept (P11_FIN_FIX=1); P11_DIAG_TX not set.
set P11_CFG=c4
set P11_APP8=1
set P11_APP8_OCC=0
set P11_APP8_CDC=1
set P11_HLS_VARIANT=p11fix_fin_r1
set P11_IMPL_STRATEGY=Performance_NetDelay_high
call "%~dp0..\..\..\board\run_build_p7b_ku5p.bat"
exit /b %ERRORLEVEL%
