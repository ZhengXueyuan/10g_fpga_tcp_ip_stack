@echo off
REM run_build_0x3F.bat -- P11 STALL-FIX v2: drain predicate corrected (0x3E -> 0x3F).
REM   0x3E bug: drain_cnt was cleared on every scan/service cycle because st_ok follows
REM   rb_id (muxed away from start_id every 16 cycles by scan_now) => the backstop
REM   never fired while any other slot was ESTAB. 0x3F samples st_ok only when
REM   rb_id == s_axis_tid and HOLDS the counter on svc/scan/probe steals.
REM   F2 kept (P11_FIN_FIX=1); P11_DIAG_TX not set (W71/W72 keep original meaning).
REM   Attempts: A Congestion_SpreadLogic_high = -0.097; B Performance_ExtraTimingOpt
REM   = -0.874; C Performance_Explore (default) = -0.337. D = NetDelay_high.
set P11_CFG=c4
set P11_APP8=1
set P11_APP8_OCC=0
set P11_APP8_CDC=1
set P11_HLS_VARIANT=p11fix_fin
set P11_IMPL_STRATEGY=Performance_NetDelay_high
call "%~dp0..\..\..\board\run_build_p7b_ku5p.bat"
exit /b %ERRORLEVEL%
