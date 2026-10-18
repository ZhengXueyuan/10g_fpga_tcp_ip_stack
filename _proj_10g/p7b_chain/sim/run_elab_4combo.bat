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

REM ---- P11 P2-A: DEFS built EXPLICITLY per combo (no string subtraction from COMMON) ----
REM   F-9/FIX: every combo gets its OWN work dir + library. 2026-10-18 measured: reusing
REM   one shared xil_defaultlib made xvlog HANG on c2 (0-byte log, idle CPU) after c1.
set "ELIST=%CD%\elab_files.f"
set "B=-d DEV_USP -d APP_MODE -d DP_156MHZ -d P6B_SIM_CLKGEN -d UDP_TX_OVL -d TCP_TX_OVL"
set "P7=-d P7B_10G -d P7B_SIM_NOPCS"
set "PCS=-d PCIE_OBS"
set "S0=-d SFP2_MODE_A"
set "S1=-d SFP2_MODE_B"
set "DU=-d DUAL_SFP_A"
set "FAILS=0"

call :one c1 "%B% %P7% %PCS%"                ok
call :one c2 "%B% %PCS%"                     ok
call :one c3 "%B% %P7%"                      ok
call :one c4 "%B%"                           ok
call :one c5 "%B% %P7% %PCS% %S0%"           ok
call :one c6 "%B% %P7% %PCS% %S0% %S1%"      fail
call :one c7 "%B% %PCS% %S1%"                fail
REM ---- P11 P2-A DUAL coverage: c8 = REAL 9-macro build combo (F-9: includes SFP2_MODE_A),
REM      c13 = DUAL without SFP2_MODE_A positive control, c9..c12 four hard gates
call :one c8  "%B% %P7% %PCS% %S0% %DU%"     ok
call :one c13 "%B% %P7% %PCS% %DU%"          ok
call :one c9  "%B% %DU%"                     fail
call :one c10 "%B% %P7% %PCS% %DU% %S1%"     fail
call :one c11 "-d DEV_USP -d APP_MODE -d P6B_SIM_CLKGEN -d UDP_TX_OVL -d TCP_TX_OVL %P7% %PCS% %DU%" fail
call :one c12 "-d DEV_USP -d DP_156MHZ -d P6B_SIM_CLKGEN -d UDP_TX_OVL -d TCP_TX_OVL %P7% %PCS% %DU%" fail

REM ---- N-9: .STRICT static assertion (rx_merge2 instance must be hard-wired to 0) ----
set "S0C=0"
"%PY%" -c "s=open(r'%ROOT%/board/wrapper_p4.v',encoding='utf-8',errors='replace').read();print(s.count('.STRICT(1'+chr(39)+'b0)'))" > strict0.tmp
set /p S0C=<strict0.tmp
set "S1C=0"
"%PY%" -c "s=open(r'%ROOT%/board/wrapper_p4.v',encoding='utf-8',errors='replace').read();print(s.count('.STRICT(1'+chr(39)+'b1)'))" > strict1.tmp
set /p S1C=<strict1.tmp
echo [ELAB STRICT] count_0=%S0C% count_1=%S1C% (expect 1 / 0)
if not "%S0C%"=="1" (echo [ELAB STRICT] FAIL count_STRICT0_NE_1 & set /a FAILS+=1)
if not "%S1C%"=="0" (echo [ELAB STRICT] FAIL count_STRICT1_NE_0 & set /a FAILS+=1)

REM ---- F-8: implicit-net structural self-check (declarations must be OUTSIDE ifdef DUAL_SFP_A) ----
"%PY%" "%~dp0check_decl_outside_ifdef.py" "%ROOT%\board\wrapper_p4.v" rx_p0_tvalid tx_p0_frames tx_p1_frames
if errorlevel 1 (echo [ELAB DECL] FAIL declaration-inside-ifdef-DUAL & set /a FAILS+=1)

echo ELAB_COMBO_FAILS=%FAILS% (13 combos: 4 macro + 3 SFP2 mode + 2 DUAL positive (c8 = true build with SFP2_MODE_A, c13 = DUAL without) + 4 DUAL hard gates)
if not "%FAILS%"=="0" exit /b 1
echo ELAB_4COMBO_PASS
exit /b 0

REM ---------------------------------------------------------------------------
REM :one TAG DEFS EXPECT(ok|fail)
REM ---------------------------------------------------------------------------
:one
set "TAG=%~1"
set "DEFS=%~2"
set "EXPECT=%~3"
if "%EXPECT%"=="" set "EXPECT=ok"
set "GD=%CD%"
if exist "d_%TAG%" rmdir /s /q "d_%TAG%"
mkdir "d_%TAG%"
del /q "xvlog_%TAG%.log" "xelab_%TAG%.log" 2>nul
cd /d "%GD%\d_%TAG%"
REM   glbl must live in the SAME private library as the design (top-level compile goes to the
REM   shared dir; 2026-10-18: per-combo dirs => "Cannot find xil_defaultlib.glbl" for all).
call %XV%\xvlog.bat -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" > glbl_%TAG%.log 2>&1
call %XV%\xvlog.bat -work xil_defaultlib %DEFS% -i %ROOT%\rtl -i %ROOT%\board -f "%ELIST%" > "..\xvlog_%TAG%.log" 2>&1
set "XRC=%ERRORLEVEL%"
cd /d "%GD%"
if not "%XRC%"=="0" goto :one_xvlog_fail
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" "xvlog_%TAG%.log" >NUL && goto :one_imp_xvlog
findstr /I /C:"ERROR" "xvlog_%TAG%.log" >NUL && goto :one_err_xvlog
cd /d "%GD%\d_%TAG%"
call %XV%\xelab.bat -debug typical -L unisims_ver -L xpm xil_defaultlib.wrapper_p4 xil_defaultlib.glbl -s wrap_%TAG% -log "..\xelab_%TAG%.log" > NUL 2>&1
set "ERC=%ERRORLEVEL%"
cd /d "%GD%"
if not "%ERC%"=="0" goto :one_xelab_fail
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" "xelab_%TAG%.log" >NUL && goto :one_imp_xelab
REM ---- combo elaborated cleanly --------------------------------------------
if /i "%EXPECT%"=="fail" (
  echo [ELAB %TAG%] UNEXPECTED-PASS -- expected a hard elaboration failure
  set /a FAILS+=1
  exit /b 0
)
echo [ELAB %TAG%] DEFS=[%DEFS%] OK
exit /b 0

:one_xvlog_fail
if /i "%EXPECT%"=="fail" (
  echo [ELAB %TAG%] EXPECTED-FAIL OK at xvlog
  findstr /I /C:"SFP2_MODE_A_AND_B_CONFLICT" /C:"SFP2_MODE_B_REQUIRES_P7B_10G" /C:"DUAL_SFP_A_REQUIRES_P7B_10G" /C:"DUAL_SFP_A_AND_SFP2_MODE_B_CONFLICT" /C:"DUAL_SFP_A_REQUIRES_DP_156MHZ" /C:"DUAL_SFP_A_REQUIRES_APP_MODE" "xvlog_%TAG%.log"
  findstr /I /C:"SFP2_MODE_A_AND_B_CONFLICT" /C:"SFP2_MODE_B_REQUIRES_P7B_10G" /C:"DUAL_SFP_A_REQUIRES_P7B_10G" /C:"DUAL_SFP_A_AND_SFP2_MODE_B_CONFLICT" /C:"DUAL_SFP_A_REQUIRES_DP_156MHZ" /C:"DUAL_SFP_A_REQUIRES_APP_MODE" "xvlog_%TAG%.log" >NUL || (echo [ELAB %TAG%] SIG-MISSING & set /a FAILS+=1)
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
  findstr /I /C:"SFP2_MODE_A_AND_B_CONFLICT" /C:"SFP2_MODE_B_REQUIRES_P7B_10G" /C:"DUAL_SFP_A_REQUIRES_P7B_10G" /C:"DUAL_SFP_A_AND_SFP2_MODE_B_CONFLICT" /C:"DUAL_SFP_A_REQUIRES_DP_156MHZ" /C:"DUAL_SFP_A_REQUIRES_APP_MODE" "xelab_%TAG%.log"
  findstr /I /C:"SFP2_MODE_A_AND_B_CONFLICT" /C:"SFP2_MODE_B_REQUIRES_P7B_10G" /C:"DUAL_SFP_A_REQUIRES_P7B_10G" /C:"DUAL_SFP_A_AND_SFP2_MODE_B_CONFLICT" /C:"DUAL_SFP_A_REQUIRES_DP_156MHZ" /C:"DUAL_SFP_A_REQUIRES_APP_MODE" "xelab_%TAG%.log" >NUL || (echo [ELAB %TAG%] SIG-MISSING & set /a FAILS+=1)
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
