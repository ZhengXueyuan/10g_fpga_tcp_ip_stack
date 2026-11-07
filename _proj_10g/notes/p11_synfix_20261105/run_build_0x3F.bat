@echo off
REM run_build_0x3F.bat -- P11 STALL-FIX v2: drain predicate corrected (0x3E -> 0x3F).
REM   Attempt E (steal-condition predicate, Congestion_SpreadLogic_high) reached
REM   WNS 0.000 / 0 failing endpoints / "constraints met" -- but the project gate
REM   requires WNS > 0, so it was quarantined. Attempt F = Congestion_SpreadLogic_medium.
set P11_CFG=c4
set P11_APP8=1
set P11_APP8_OCC=0
set P11_APP8_CDC=1
set P11_HLS_VARIANT=p11fix_fin
set P11_IMPL_STRATEGY=Congestion_SpreadLogic_low
call "%~dp0..\..\..\board\run_build_p7b_ku5p.bat"
exit /b %ERRORLEVEL%
