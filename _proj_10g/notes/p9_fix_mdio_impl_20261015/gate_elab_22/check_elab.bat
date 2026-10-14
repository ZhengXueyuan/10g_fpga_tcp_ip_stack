@echo off
REM ===========================================================================
REM gate_elab_22 / check_elab.bat -- HARD verdict for the elab gate.
REM Exit 0 = GATE_PASS ; exit 1 = GATE_FAIL with a reason list.
REM
REM Why a separate judge: the inherited skeleton ends with "exit /b 0" and only
REM PRINTS XELAB_RC -- and a printed warning nobody greps is not a gate (repo
REM lesson: "prints FAIL yet exits 0" is a dumb gate). Every criterion below
REM echoes the exact line it judged, and the verdict walks all the way from the
REM evidence to the exit code.
REM
REM Criteria -- F1..F3 are the elab side, F4..F5 are TEXT checks for things
REM elaboration can never see:
REM  F1  elab_rc.txt == 0
REM  F2  no "VRFC 10-3645" (unconnected port) anywhere in xelab.log
REM  F3  no "VRFC 10-3091" (width mismatch) anywhere in xelab.log
REM  F4  RTL: bus declared [21:0]; no stale [19:0] declaration left; concat
REM      order is {stat_start_lost, param_bad, mdio_i, ...} (E5 decision:
REM      new bits at the MSB end so every old bit keeps its position)
REM  F5  vio_0.v stub declares "input [21 : 0] probe_in0;" AND build_mdio.tcl
REM      carries CONFIG.C_PROBE_IN0_WIDTH {22} -- the RTL / build-script sync
REM      (E2 vs E6) that neither elab nor any simulation can ever detect
REM ===========================================================================
setlocal enabledelayedexpansion
cd /d %~dp0
set FAIL=

set RC=
for /f "tokens=1" %%r in (elab_rc.txt) do set RC=%%r
if not "!RC!"=="0" set FAIL=!FAIL! F1_XELAB_RC_NOT_0

findstr /C:"VRFC 10-3645" xelab.log >nul 2>&1
if not errorlevel 1 set FAIL=!FAIL! F2_PORT_UNCONNECTED_10-3645
findstr /C:"VRFC 10-3091" xelab.log >nul 2>&1
if not errorlevel 1 set FAIL=!FAIL! F3_WIDTH_MISMATCH_10-3091

findstr /C:"wire [21:0] vio_probe_in;" mdio_vio_top.v >nul 2>&1
if errorlevel 1 set FAIL=!FAIL! F4_BUS_NOT_22
findstr /C:"wire [19:0] vio_probe_in;" mdio_vio_top.v >nul 2>&1
if not errorlevel 1 set FAIL=!FAIL! F4_STALE_20BIT_DECL
findstr /C:"assign vio_probe_in = {stat_start_lost, param_bad, mdio_i, eth_rstn, busy, done_sticky, rd_data};" mdio_vio_top.v >nul 2>&1
if errorlevel 1 set FAIL=!FAIL! F4_CONCAT_ORDER_WRONG

findstr /C:"input [21 : 0] probe_in0;" vio_0.v >nul 2>&1
if errorlevel 1 set FAIL=!FAIL! F5_STUB_NOT_22
findstr /C:"CONFIG.C_PROBE_IN0_WIDTH {22}" build_mdio.tcl >nul 2>&1
if errorlevel 1 set FAIL=!FAIL! F5_TCL_WIDTH_NOT_22

echo ---- gate evidence: the exact lines judged ----
echo XELAB_RC=!RC!
findstr /N /C:"overwriting previous definition" xvlog.stdout.txt
findstr /N /C:"VRFC 10-3645" xelab.log
findstr /N /C:"VRFC 10-3091" xelab.log
findstr /N /C:"wire [21:0] vio_probe_in;" mdio_vio_top.v
findstr /N /C:"assign vio_probe_in" mdio_vio_top.v
findstr /N /C:"input [21 : 0] probe_in0;" vio_0.v
findstr /N /C:"CONFIG.C_PROBE_IN0_WIDTH" build_mdio.tcl

if "!FAIL!"=="" (
  echo GATE_PASS
  exit /b 0
)
echo GATE_FAIL:!FAIL!
exit /b 1
