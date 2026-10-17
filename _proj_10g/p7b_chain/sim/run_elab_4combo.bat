@echo off
REM run_elab_4combo.bat -- P11/P1: SEVEN-combo elaboration gate for wrapper_p4.
REM   Combos (P7B_10G x PCIE_OBS x SFP2 mode macros), with the board-constant
REM   macro set DEV_USP + APP_MODE + DP_156MHZ + P6B_SIM_CLKGEN + UDP_TX_OVL
REM   + TCP_TX_OVL:
REM     1) P7B_10G=1 PCIE_OBS=1                         (board body; NOPCS stub)  OK
REM     2) P7B_10G=0 PCIE_OBS=1                                                   OK
REM     3) P7B_10G=1 PCIE_OBS=0                                                   OK
REM     4) P7B_10G=0 PCIE_OBS=0                         (default/single-domain)   OK
REM     5) P7B_10G=1 PCIE_OBS=1 -d SFP2_MODE_A          (THE BUILD COMBO)         OK
REM     6) P7B_10G=1 PCIE_OBS=1 -d SFP2_MODE_A -d SFP2_MODE_B  MUST FAIL
REM        signature: SFP2_MODE_A_AND_B_CONFLICT (undefined module)
REM     7) P7B_10G=0 PCIE_OBS=1 -d SFP2_MODE_B          MUST FAIL
REM        signature: SFP2_MODE_B_REQUIRES_P7B_10G (undefined module)
REM   Purpose: catch implicitly-declared nets / undeclared ch0 signals in the
REM   macro combinations that no standing gate compiles (FINDINGS mid-9), and
REM   cover the SFP2_MODE hard gates + the ACTUAL build macro combination
REM   (FINDINGS mid-6; build_p7b_ku5p.tcl:286 passes SFP2_MODE_A=1).
REM   Expected-fail combos are judged by BOTH (a) non-zero exit at xvlog/xelab
REM   AND (b) the named signature appearing in the log; "failed for another
REM   reason" and "did not fail" both count as gate failures.
REM   Each combo gets a private work dir (xsim.dir locks); xelab top = wrapper_p4.
setlocal EnableDelayedExpansion
call "%~dp0..\..\..\sim\p4gates\p4env.bat" || exit /b 1
set "ROOT=%REPO_ROOT%"
if not "%P4_WORKDIR%"=="" (cd /d "%P4_WORKDIR%") else (cd /d %~dp0)
dir /b /s "%ROOT%\rtl\*.v" > elab_files.f
dir /b /s "%ROOT%\hls\slowstack_prj\solution1\syn\verilog\*.v" >> elab_files.f
echo %ROOT%\board\wrapper_p4.v >> elab_files.f
echo %ROOT%\board\util_gmii_to_rgmii_us.v >> elab_files.f
echo %ROOT%\board\uart_dbg.v >> elab_files.f
echo %ROOT%\board\p7b_pcs_stub.v >> elab_files.f
echo %ROOT%\_proj_pcie\rtl\axi_regs.v >> elab_files.f
echo %ROOT%\_proj_10g\p7b_mac\rtl\crc32_64.v >> elab_files.f
echo %ROOT%\_proj_10g\p7b_mac\rtl\mac_rx_10g.v >> elab_files.f
echo %ROOT%\_proj_10g\p7b_mac\rtl\mac_tx_10g.v >> elab_files.f
echo %ROOT%\sim\p6e_pcie\xdma_0_sim_stub.v >> elab_files.f
call %XV%\xvlog.bat -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" > xvlog_glbl.log 2>&1 || (type xvlog_glbl.log & exit /b 1)

set "COMMON=-d DEV_USP -d APP_MODE -d DP_156MHZ -d P6B_SIM_CLKGEN -d UDP_TX_OVL -d TCP_TX_OVL"
set "FAILS=0"

call :one c1 1 1 ""              ok
call :one c2 0 1 ""              ok
call :one c3 1 0 ""              ok
call :one c4 0 0 ""              ok
REM ---- SFP2 mode coverage (FINDINGS mid-6) ---------------------------------
REM   NOTE: xvlog's define syntax is `-d NAME` (presence = defined). It does NOT
REM   accept `-d NAME=VALUE` -- measured 2026-10-18: `-d SFP2_MODE_A=1` makes
REM   xvlog treat `1` as a file and fail with "Can not find file: 1". The board
REM   build uses `verilog_define SFP2_MODE_A=1` (synth_design syntax); the RTL
REM   only tests `ifdef`, so `-d SFP2_MODE_A` is the exact equivalent here.
call :one c5 1 1 "-d SFP2_MODE_A"              ok
call :one c6 1 1 "-d SFP2_MODE_A -d SFP2_MODE_B" fail
call :one c7 0 1 "-d SFP2_MODE_B"              fail

echo ELAB_COMBO_FAILS=%FAILS% (7 combos: 4 macro + 3 SFP2 mode)
if not "%FAILS%"=="0" exit /b 1
echo ELAB_4COMBO_PASS
exit /b 0

REM ---------------------------------------------------------------------------
REM :one TAG P7B PCIE EXTRA EXPECT(ok|fail)
REM ---------------------------------------------------------------------------
:one
set "TAG=%~1"
set "P7B=%~2"
set "PCIE=%~3"
set "EXTRA=%~4"
set "EXPECT=%~5"
if "%EXPECT%"=="" set "EXPECT=ok"
set "DEFS=%COMMON%"
if "%P7B%"=="1"  set "DEFS=%DEFS% -d P7B_10G -d P7B_SIM_NOPCS"
if "%PCIE%"=="1" set "DEFS=%DEFS% -d PCIE_OBS"
if not "%EXTRA%"=="" set "DEFS=%DEFS% %EXTRA%"
if exist "xsim_%TAG%" rmdir /s /q "xsim_%TAG%"
del /q "xvlog_%TAG%.log" "xelab_%TAG%.log" 2>nul
call %XV%\xvlog.bat -work xil_defaultlib %DEFS% -i %ROOT%\rtl -i %ROOT%\board -f elab_files.f > "xvlog_%TAG%.log" 2>&1
if errorlevel 1 goto :one_xvlog_fail
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" "xvlog_%TAG%.log" >NUL && goto :one_imp_xvlog
findstr /I /C:"ERROR" "xvlog_%TAG%.log" >NUL && goto :one_err_xvlog
call %XV%\xelab.bat -debug typical -L unisims_ver -L xpm xil_defaultlib.wrapper_p4 xil_defaultlib.glbl -s wrap_%TAG% -log "xelab_%TAG%.log" > NUL 2>&1
if errorlevel 1 goto :one_xelab_fail
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" "xelab_%TAG%.log" >NUL && goto :one_imp_xelab
REM ---- combo elaborated cleanly --------------------------------------------
if /i "%EXPECT%"=="fail" (
  echo [ELAB %TAG%] UNEXPECTED-PASS -- expected a hard elaboration failure
  set /a FAILS+=1
  exit /b 0
)
echo [ELAB %TAG%] P7B=%P7B% PCIE=%PCIE% EXTRA=[%EXTRA%] OK
exit /b 0

:one_xvlog_fail
if /i "%EXPECT%"=="fail" (
  echo [ELAB %TAG%] EXPECTED-FAIL OK at xvlog
  findstr /I /C:"SFP2_MODE_A_AND_B_CONFLICT" /C:"SFP2_MODE_B_REQUIRES_P7B_10G" "xvlog_%TAG%.log"
  findstr /I /C:"SFP2_MODE_A_AND_B_CONFLICT" /C:"SFP2_MODE_B_REQUIRES_P7B_10G" "xvlog_%TAG%.log" >NUL || (echo [ELAB %TAG%] SIG-MISSING & set /a FAILS+=1)
  exit /b 0
)
echo [ELAB %TAG%] XVLOG_FAIL
type "xvlog_%TAG%.log"
set /a FAILS+=1
exit /b 0

:one_err_xvlog
echo [ELAB %TAG%] XVLOG_ERROR
findstr /I /C:"ERROR" "xvlog_%TAG%.log"
set /a FAILS+=1
exit /b 0

:one_imp_xvlog
echo [ELAB %TAG%] IMPLICIT-XVLOG
set /a FAILS+=1
exit /b 0

:one_xelab_fail
if /i "%EXPECT%"=="fail" (
  echo [ELAB %TAG%] EXPECTED-FAIL OK at xelab
  findstr /I /C:"SFP2_MODE_A_AND_B_CONFLICT" /C:"SFP2_MODE_B_REQUIRES_P7B_10G" "xelab_%TAG%.log"
  findstr /I /C:"SFP2_MODE_A_AND_B_CONFLICT" /C:"SFP2_MODE_B_REQUIRES_P7B_10G" "xelab_%TAG%.log" >NUL || (echo [ELAB %TAG%] SIG-MISSING & set /a FAILS+=1)
  exit /b 0
)
echo [ELAB %TAG%] XELAB_FAIL
type "xelab_%TAG%.log"
set /a FAILS+=1
exit /b 0

:one_imp_xelab
echo [ELAB %TAG%] IMPLICIT-XELAB
set /a FAILS+=1
exit /b 0
