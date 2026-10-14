@echo off
setlocal
REM =====================================================================
REM run_tb_p9_swc.bat -- P9 switch-door (TX_SWCLOSE / close-out-then-switch) gate
REM   (self-locating; shape follows sim\p7b_longsend\run_cont_gate.bat)
REM
REM   8 runs, each in its own work dir (xsim.dir file-lock pitfall):
REM     F   : live rtl/app_pattern.v + P9_SWC_ARM  + EXP_FIXED  (expect all green)
REM     F10 : same + P7B_10G (A2 whole-word path config)
REM     H   : sim\p9_swc_gate\head_app_pattern.v (frozen pre-edit) + EXP_HEAD
REM     H10 : same + P7B_10G
REM     OFF : live RTL + P9_SWC_OFF (=.TX_SWCLOSE(1'b0)) + EXP_HEAD (constant-level control)
REM     M6  : mutant m6_v1_eq        + P9_SWC_ARM + EXP_M6
REM     M6B : mutant m6b_closing_drop + P9_SWC_ARM + EXP_M6B
REM     M7  : mutant m7_guard_swpend + P9_SWC_ARM + EXP_M7
REM
REM   RULE: every run must end RC=0. The run-level criterion "measured red set ==
REM   expected red set" lives INSIDE the TB (-d P9_EXP_*), so a mutant's "must be
REM   red" is checked by the TB itself, never by "nonzero RC == good" (no dumb gate:
REM   neither "FAIL printed but exit 0" nor "red is good").
REM   Witnesses: run<X>\srcpath.log records which RTL source was compiled (anti
REM   vacuum-gate); the frozen head file has a hard sha256 assertion.
REM =====================================================================
set "HERE=%~dp0"
if "%HERE:~-1%"=="\" set "HERE=%HERE:~0,-1%"
set "ROOT=%HERE%\..\.."
for %%I in ("%ROOT%") do set "ROOT=%%~fI"
if not exist "%ROOT%\CLAUDE.md" (
  echo [PATHGUARD FAIL] cannot locate repo root from %~f0
  echo   derived ROOT = %ROOT%
  exit /b 1
)
set "XV=C:\AMDDesignTools\2025.2\Vivado\bin"
set "PY=C:\Users\zhxue\anaconda3\python.exe"
set "RTL=%ROOT%\rtl\app_pattern.v"
set "HEADF=%HERE%\head_app_pattern.v"
set "TB=%HERE%\tb_p9_swc.v"
set "HEAD_SHA=811a84e4bd0e8b20ba8ac007cbb16a8f310091b141f7a6d59964dd8288f317bc"
cd /d "%HERE%"

if not exist "%PY%" (echo [FAIL] python not found: %PY% & exit /b 1)
if not exist "%RTL%" (echo [FAIL] live RTL missing & exit /b 1)
if not exist "%HEADF%" (echo [FAIL] frozen head RTL missing & exit /b 1)
if not exist "%TB%" (echo [FAIL] TB missing & exit /b 1)

REM ---- frozen head sha256 hard assertion ----
"%PY%" -c "import hashlib,sys;h=hashlib.sha256(open(r'%HEADF%','rb').read()).hexdigest();print('HEADSHA '+h);sys.exit(0 if h=='%HEAD_SHA%' else 1)"
if errorlevel 1 (echo [FAIL] head_app_pattern.v sha256 mismatch & exit /b 1)

REM ---- mutant generation (all-or-nothing; anchor hit count mismatch = hard fail) ----
"%PY%" "%HERE%\mk_mut_swc.py" > mutgen.log 2>&1 || (type mutgen.log & echo MUTGEN-FAIL & exit /b 1)
findstr /C:"MUTGEN OK" mutgen.log > NUL || (type mutgen.log & echo MUTGEN-NOTOK & exit /b 1)
type mutgen.log

call :run F   "%RTL%"   "-d P9_SWC_ARM -d P9_EXP_FIXED"
set "RCF=%errorlevel%"
call :run F10 "%RTL%"   "-d P9_SWC_ARM -d P9_EXP_FIXED -d P7B_10G"
set "RCF10=%errorlevel%"
call :run H   "%HEADF%" "-d P9_HEAD_RTL -d P9_EXP_HEAD"
set "RCH=%errorlevel%"
call :run H10 "%HEADF%" "-d P9_HEAD_RTL -d P9_EXP_HEAD -d P7B_10G"
set "RCH10=%errorlevel%"
call :run OFF "%RTL%"   "-d P9_SWC_OFF -d P9_EXP_HEAD"
set "RCOFF=%errorlevel%"
call :run M6  "%HERE%\mut\m6_v1_eq.v"         "-d P9_SWC_ARM -d P9_EXP_M6"
set "RCM6=%errorlevel%"
call :run M6B "%HERE%\mut\m6b_closing_drop.v" "-d P9_SWC_ARM -d P9_EXP_M6B"
set "RCM6B=%errorlevel%"
call :run M7  "%HERE%\mut\m7_guard_swpend.v"  "-d P9_SWC_ARM -d P9_EXP_M7"
set "RCM7=%errorlevel%"

echo ==================== SUMMARY ====================
echo   F   live RTL + SWC=1            RC=%RCF%    (expect 0; EXP_FIXED)
echo   F10 live RTL + SWC=1 + P7B_10G  RC=%RCF10%    (expect 0; EXP_FIXED)
echo   H   frozen pre-edit RTL         RC=%RCH%    (expect 0; EXP_HEAD)
echo   H10 frozen pre-edit + P7B_10G   RC=%RCH10%    (expect 0; EXP_HEAD)
echo   OFF live RTL + SWC=0            RC=%RCOFF%    (expect 0; EXP_HEAD)
echo   M6  mutant v1-equations         RC=%RCM6%    (expect 0; EXP_M6)
echo   M6B mutant closing-drop         RC=%RCM6B%    (expect 0; EXP_M6B)
echo   M7  mutant v2r2-guard           RC=%RCM7%    (expect 0; EXP_M7)

set "FAILS=0"
if not "%RCF%"=="0"    set /a FAILS+=1
if not "%RCF10%"=="0"  set /a FAILS+=1
if not "%RCH%"=="0"    set /a FAILS+=1
if not "%RCH10%"=="0"  set /a FAILS+=1
if not "%RCOFF%"=="0"  set /a FAILS+=1
if not "%RCM6%"=="0"   set /a FAILS+=1
if not "%RCM6B%"=="0"  set /a FAILS+=1
if not "%RCM7%"=="0"   set /a FAILS+=1

echo   ---- criteria table (F run) ----
findstr /C:"CFG=" /C:"C0 " /C:"C1 " /C:"C2 " /C:"C3 " /C:"C4 " /C:"C5 " /C:"C6 " /C:"C7 " /C:"C8 " /C:"C9 " "runF\xs.log"
echo   ---- OFF run arm reds (expect ARM0/1/2/9 red) ----
findstr /C:"ARM" "runOFF\xs.log"
echo   ---- mutant red sets ----
echo   [M6 reds]  (expect all 10 arms red)
findstr /C:"ARM" "runM6\xs.log"
echo   [M6B reds] (expect ARM3/ARM4 red)
findstr /C:"ARM" "runM6B\xs.log"
echo   [M7 reds]  (expect ARM9 red)
findstr /C:"ARM" "runM7\xs.log"
echo   ---- compile-source witness ----
for %%A in (F F10 H H10 OFF M6 M6B M7) do findstr /C:"RSRC=" "run%%A\srcpath.log"

if "%FAILS%"=="0" (echo P9-SWC-GATE: PASS & exit /b 0)
echo P9-SWC-GATE: FAIL count=%FAILS%
exit /b 1

REM =====================================================================
:run
set "NAME=%~1"
set "RSRC=%~2"
set "DEFS=%~3"
if not exist "run%NAME%" mkdir "run%NAME%"
pushd "run%NAME%"
if exist xsim.dir rmdir /s /q xsim.dir
echo RSRC=%RSRC% DEFS=%DEFS% > srcpath.log
call "%XV%\xvlog.bat" -work xil_defaultlib %DEFS% "%RSRC%" "..\tb_p9_swc.v" > xv_out.log 2>&1 || (type xv_out.log & popd & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xv_out.log > NUL
if not errorlevel 1 (echo IMPLICIT-WIRE [%NAME%]: & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xv_out.log & popd & exit /b 1)
findstr /I /C:"ERROR" xv_out.log > NUL
if not errorlevel 1 (echo XVLOG-ERROR [%NAME%]: & type xv_out.log & popd & exit /b 1)
call "%XV%\xelab.bat" -debug typical xil_defaultlib.tb_p9_swc -s tbswc -log xe.log > xe_out.log 2>&1 || (type xe_out.log & popd & exit /b 1)
findstr /I /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"undeclared symbol" xe.log > NUL
if not errorlevel 1 (echo ELAB-IMPLICIT [%NAME%]: & findstr /I /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"undeclared symbol" xe.log & popd & exit /b 1)
call "%XV%\xsim.bat" tbswc -runall -log xs.log > xs_out.log 2>&1
findstr /C:"TB_P9_SWC: OK" xs.log > NUL
if errorlevel 1 (echo ---- TB FAIL detail [%NAME%]: & findstr /C:"TB_P9_SWC" /C:"[FAIL]" xs.log & popd & exit /b 1)
findstr /C:"TB_P9_SWC CFG=" /C:"TB_P9_SWC_SUM" /C:"TB_P9_SWC: OK" xs.log
popd
exit /b 0
