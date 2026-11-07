@echo off
REM run_build_0x3E.bat -- P11 STALL-FIX: stale-frame drain backstop (BID 0x3E).
REM   F2 kept (P11_FIN_FIX=1); P11_DIAG_TX not set (W71/W72 keep their original meaning).
set P11_CFG=c4
set P11_APP8=1
set P11_APP8_OCC=0
set P11_APP8_CDC=1
set P11_HLS_VARIANT=p11fix_fin
REM 2026-11-07: retry as a NEW INPUT -- first run (Congestion_SpreadLogic_high) had
REM   WNS -0.632/8909 with the worst family u_tcp_tx2/u_fifo_a -> u_tcb2 (0 hits of the new logic).
REM 2026-11-07 retry 3: drain predicate simplified to st_ok-only (no app_tx_ready input);
REM   strategy = Performance_ExtraTimingOpt (timing-focused).
REM 2026-11-07 retry 5: same netlist (DRAIN_EN port0-only); strategy with post-route phys opt
REM   targeted at the remaining -0.039 ns (route-dominated port1 u_fifo_b->u_app2/stg).
REM 2026-11-07 retry 6: back to the strategy that passed 0x3D (+0.016) on this exact lineage;
REM   attempt D (same netlist, ExtraTimingOpt) was only -0.039.
set P11_IMPL_STRATEGY=Congestion_SpreadLogic_high
call "%~dp0..\..\..\board\run_build_p7b_ku5p.bat"
exit /b %ERRORLEVEL%
