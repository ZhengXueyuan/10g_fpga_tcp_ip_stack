@echo off
REM run_tb_tcp_tx_srcip.bat -- P11 P2-jia G5: tcp_tx_frame per-conn source IP
REM   Three runs:
REM     1) OVL body (rtl/tcp_tx_frame.v, -d TCP_TX_OVL)      -> SRCIP TB PASS
REM     2) default body (no define)                          -> SRCIP TB PASS
REM     3) MUTANT (mk_mut_srcip.py copy; wrong source IP)    -> MUST be red
REM   The mutant arm is judged by BOTH a non-zero exit AND the "SRCIP TB FAIL"
REM   signature; "stopped for another reason" does not count as teeth.
cd /d %~dp0
call "%~dp0..\..\..\sim\p4gates\p4env.bat" || exit /b 1
if not "%P4_WORKDIR%"=="" cd /d "%P4_WORKDIR%"
"%PY%" "%P4GATE_PY%" checkpaths --root "%REPO_ROOT%" --path "%CD%" --quiet || exit /b 1
"%PY%" "%P4GATE_PY%" checkpaths --root "%REPO_ROOT%" --manifest "%GATES%\p11srcip_src.f" --path "%CD%" --quiet || exit /b 1
set "RTL=%REPO_ROOT%\rtl\tcp_tx_frame"
set "TB=%REPO_ROOT%\_proj_10g\p11_dual\sim\tb_tcp_tx_srcip"
set "MUT=%CD%\mut\tcp_tx_frame_mut"
set "MUTN6=%CD%\mut\tcp_tx_frame_mutn6"
set "VEXT=v"
if not exist "mut" mkdir "mut"
"%PY%" "%REPO_ROOT%\_proj_10g\p11_dual\sim\mk_mut_srcip.py" "%RTL%.%VEXT%" "%MUT%.%VEXT%" > mk_mut.log 2>&1
if errorlevel 1 (type mk_mut.log & echo SRCIP MUTGEN FAIL & exit /b 1)
type mk_mut.log
"%PY%" "%REPO_ROOT%\_proj_10g\p11_dual\sim\mk_mut_srcip.py" "%RTL%.%VEXT%" "%MUTN6%.%VEXT%" --n6 > mk_mut_n6.log 2>&1
if errorlevel 1 (type mk_mut_n6.log & echo SRCIP MUTGEN N6 FAIL & exit /b 1)
type mk_mut_n6.log

set "RC=0"

REM ---- arm 1: OVL body ----
call :run ovl 1 "%RTL%.%VEXT%" "" pass
if errorlevel 1 set "RC=1"
REM ---- arm 2: default body ----
call :run def 0 "%RTL%.%VEXT%" "" pass
if errorlevel 1 set "RC=1"
REM ---- arm 3: full mutant (must be red) ----
call :run mut 1 "%MUT%.%VEXT%" "" fail
if errorlevel 1 set "RC=1"
REM ---- arm 4: N-6 precise mutant (default body, csum_sip = lip_r) MUST be red ----
call :run mutn6 0 "%MUTN6%.%VEXT%" "" fail
if errorlevel 1 set "RC=1"

if "%RC%"=="0" (echo SRCIP_GATE_PASS) else (echo SRCIP_GATE_FAIL)
exit /b %RC%

REM ---------------------------------------------------------------
REM :run TAG OVL RTLFILE DEFS EXPECT(pass|fail)
REM ---------------------------------------------------------------
:run
set "TAG=%~1"
set "OVL=%~2"
set "RTLF=%~3"
set "EXTRA=%~4"
set "EXPECT=%~5"
set "DEFS=-d PER_CONN_SRCIP_TB"
if "%OVL%"=="1" set "DEFS=%DEFS% -d TCP_TX_OVL"
if not "%EXTRA%"=="" set "DEFS=%DEFS% %EXTRA%"
if exist "xsim_%TAG%" rmdir /s /q "xsim_%TAG%"
del /q "xvlog_%TAG%.log" "xelab_%TAG%.log" "xsim_%TAG%.log" 2>nul
REM   manifestcheck only trusts LITERAL .v tokens; live arms use literal paths.
REM   NOTE: there are TWO mutant tags: mut (all 6 sites) and mutn6 (N-6 exact one site, default body).
REM     2026-10-18 trap: only mut used %RTLF% => mutn6 compiled the ORIGINAL => false UNEXPECTED-PASS.
set "USEMUT=0"
if /i "%TAG%"=="mut"   set "USEMUT=1"
if /i "%TAG%"=="mutn6" set "USEMUT=1"
if "%USEMUT%"=="1" goto :run_xvlog_mut
call %XV%\xvlog.bat -work xil_defaultlib %DEFS% %REPO_ROOT%\rtl\tcp_tx_frame.v %REPO_ROOT%\rtl\fifo_sync.v %REPO_ROOT%\rtl\retx_ram.v %REPO_ROOT%\rtl\checksum16.v %REPO_ROOT%\_proj_10g\p11_dual\sim\tb_tcp_tx_srcip.v > "xvlog_%TAG%.log" 2>&1
goto :run_xvlog_done
:run_xvlog_mut
call %XV%\xvlog.bat -work xil_defaultlib %DEFS% "%RTLF%" "%TB%.%VEXT%" > "xvlog_%TAG%.log" 2>&1
:run_xvlog_done
if errorlevel 1 (type "xvlog_%TAG%.log" & echo SRCIP %TAG% XVLOG_FAIL & exit /b 1)
findstr /I /C:"VRFC 10-2989" /C:"Synth 8-11241" /C:"implicitly declared" "xvlog_%TAG%.log" >NUL && (echo SRCIP %TAG% IMPLICIT & exit /b 1)
call %XV%\xelab.bat -debug typical xil_defaultlib.tb_tcp_tx_srcip -s "tb_srcip_%TAG%" -log "xelab_%TAG%.log" > NUL 2>&1
if errorlevel 1 (type "xelab_%TAG%.log" & echo SRCIP %TAG% XELAB_FAIL & exit /b 1)
findstr /I /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" "xelab_%TAG%.log" >NUL && (echo SRCIP %TAG% IMPLICIT_XELAB & exit /b 1)
REM ---- F-7 (H-1): targeted "new port peer_my_ip unconnected" assertion ----
findstr /C:"peer_my_ip" "xelab_%TAG%.log" | findstr /C:"VRFC 10-3645" >NUL && (echo SRCIP %TAG% PEER_MY_IP_UNCONNECTED & exit /b 1)
call %XV%\xsim.bat "tb_srcip_%TAG%" -runall -log "xsim_%TAG%.log" > NUL 2>&1
REM   Verdict source = the TB's own terminal line, NOT xsim's exit code.
REM   Measured 2026-10-18: xsim.bat returns a NON-ZERO errorlevel on this TB
REM   even when it prints "SRCIP TB PASS" (all three arms), so an exit-code
REM   gate here would be a false criterion in both directions.
findstr /C:"[FAIL]" /C:"SRCIP TB" "xsim_%TAG%.log"
if /i "%EXPECT%"=="pass" (
  findstr /C:"SRCIP TB FAIL" "xsim_%TAG%.log" >nul && (echo SRCIP %TAG% RED-UNEXPECTED & exit /b 1)
  findstr /C:"SRCIP TB PASS" "xsim_%TAG%.log" >nul || (echo SRCIP %TAG% NO-PASS-LINE & exit /b 1)
  echo SRCIP %TAG% OK
  exit /b 0
)
REM expect fail: the FAIL signature must be the TB's terminal verdict
findstr /C:"SRCIP TB PASS" "xsim_%TAG%.log" >nul && (echo SRCIP %TAG% UNEXPECTED-PASS & exit /b 1)
findstr /C:"SRCIP TB FAIL" "xsim_%TAG%.log" >nul || (echo SRCIP %TAG% FAIL-SIG-MISSING & exit /b 1)
echo SRCIP %TAG% EXPECTED-FAIL OK
exit /b 0
