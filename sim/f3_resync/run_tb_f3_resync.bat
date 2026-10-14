@echo off
REM ==========================================================================
REM run_tb_f3_resync.bat -- F-3 RESYNC gate G1 (self-locating; xsim only)
REM   design doc = _proj_10g/notes/p9_fix_f3_design_20261014/DESIGN_v2.md  S3.2-G1
REM   DUT        = rtl/vlan_strip.v RESYNC_EN resync gate (+ board/wrapper_p4.v wiring)
REM
REM   Arms (each in its own work dir; SEQUENTIAL, never parallel xsim -- trap 7):
REM     F    : new RTL, RESYNC_EN=1  expect: CHK line all green
REM     L    : new RTL, RESYNC_EN=0  expect: J1/J2/J5 red, ALL=0, and the verbatim
REM                                      historical t9 case_old defect shape
REM     M1   : mutant mut\mut_m1.v (fwd = 1'b1)                 expect: J1 red, J3eq=0, ALL=0
REM     M2   : mutant mut\mut_m2.v (fwd = ... || s_axis_tlast)  expect: J1 red, J3eq=0, ALL=0
REM     CTRL : new RTL, RESYNC_EN=1 + injection moved into an inter-frame gap
REM            (FIFO empty + FE frozen)  expect: CHK line green with J3pos=0
REM
REM   exit codes: 0 = gate PASS (all arm verdicts as designed) / 1 = otherwise / 97 = refusal
REM   NOTE: arm identity travels via -d defines, NOT -testplusarg NAME=VALUE --
REM         xsim.bat's loader splits any arg containing '=' (repo-documented trap,
REM         see sim/d2run/p4prv/run_tb_p4_burst.bat:66-68 "...found 5").
REM   NOTE: verdicts are grepped as SINGLE literal strings from the TB's
REM         "F3R CHK ..." line -- no pipes / no nested parens in echoed text
REM         (cmd parses those inside a block and mangles them silently).
REM   from Git Bash: cmd //c 'sim\f3_resync\run_tb_f3_resync.bat'
REM ==========================================================================
setlocal
set "HERE=%~dp0"
if "%HERE:~-1%"=="\" set "HERE=%HERE:~0,-1%"
set "ROOT=%HERE%\..\.."
for %%I in ("%ROOT%") do set "ROOT=%%~fI"
if not exist "%ROOT%\CLAUDE.md" (
  echo [PATHGUARD FAIL] cannot locate repo root from %~f0
  echo   derived ROOT = %ROOT%
  exit /b 1
)
cd /d "%HERE%"
set "XV=C:\AMDDesignTools\2025.2\Vivado\bin"
set "PY=C:\Users\zhxue\anaconda3\python.exe"
set "RTL=%ROOT%\rtl\vlan_strip.v"
set "TB=%HERE%\tb_f3_resync.v"
set "MUTGEN=%HERE%\mut\mk_mut_f3.py"
if not exist "%XV%\xvlog.bat" (echo [FAIL] xvlog missing: %XV% & exit /b 1)
if not exist "%RTL%" (echo [FAIL] RTL missing: %RTL% & exit /b 1)
if not exist "%TB%"  (echo [FAIL] TB missing: %TB% & exit /b 1)
if not exist "%PY%"  (echo [FAIL] python not found: %PY% & exit /b 1)

REM ---- preflight: no other xsim/xelab running (serial discipline) ----
tasklist | findstr /I "xsim.exe xelab.exe" >NUL && (
  echo [FAIL] xsim/xelab already running -- refuse to start
  exit /b 97
)

REM ---- mutant generation (anchored + counted; stale anchor => hard fail) ----
if not exist "%HERE%\mut" mkdir "%HERE%\mut"
"%PY%" "%MUTGEN%" "%ROOT%" > "%HERE%\mut\mutgen.log" 2>&1
if errorlevel 1 (type "%HERE%\mut\mutgen.log" & echo MUTGEN-FAIL & exit /b 1)
type "%HERE%\mut\mutgen.log"

call :run F     runF "-d F3_ARMID_F" "%RTL%" F
set "RCF=%errorlevel%"
call :run L     runL "-d F3_RESYNC_L -d F3_ARMID_L" "%RTL%" L
set "RCL=%errorlevel%"
call :run M1    runM1 "-d F3_ARMID_M1" "%HERE%\mut\mut_m1.v" M1
set "RCM1=%errorlevel%"
call :run M2    runM2 "-d F3_ARMID_M2" "%HERE%\mut\mut_m2.v" M2
set "RCM2=%errorlevel%"
call :run CTRL  runC "-d F3_STOP_IFG -d F3_ARMID_CTRL" "%RTL%" CTRL
set "RCC=%errorlevel%"

echo ==================== SUMMARY ====================
echo   F    runF  RC=%RCF%    expect 0: CHK all green
echo   L    runL  RC=%RCL%    expect 0: XFAIL-REPRODUCED historical shape
echo   M1   runM1 RC=%RCM1%   expect 0: J1 red, J3eq=0, ALL=0
echo   M2   runM2 RC=%RCM2%   expect 0: J1 red, J3eq=0, ALL=0
echo   CTRL runC  RC=%RCC%    expect 0: CHK green with J3pos=0

set "FAILS=0"
if not "%RCF%"=="0"  set /a FAILS+=1
if not "%RCL%"=="0"  set /a FAILS+=1
if not "%RCM1%"=="0" set /a FAILS+=1
if not "%RCM2%"=="0" set /a FAILS+=1
if not "%RCC%"=="0"  set /a FAILS+=1

echo ---- key readings ----
for %%A in (runF runL runM1 runM2 runC) do (
  echo   [%%A]
  findstr /C:"F3R ARM=" /C:"F3R WITNESS" /C:"F3R SHAPE" /C:"F3R POP-ACCT" /C:"F3R CHK " /C:"F3R XFAIL-REPRODUCED" "%%A\xs.log"
)

if "%FAILS%"=="0" (echo F3-RESYNC-GATE: PASS & exit /b 0)
echo F3-RESYNC-GATE: FAIL count=%FAILS%
exit /b 1

REM ==========================================================================
:run
REM %1=armname %2=workdir %3=defs %4=vlan_strip source %5=arm id tag
set "NAME=%~1"
set "WD=%~2"
set "DEFS=%~3"
set "VSRC=%~4"
set "ARMID=%~5"
if not exist "%HERE%\%WD%" mkdir "%HERE%\%WD%"
pushd "%HERE%\%WD%"
if exist xsim.dir rmdir /s /q xsim.dir
echo VSRC=%VSRC% DEFS=%DEFS% ARM=%ARMID% > srcpath.log
"%PY%" -c "import hashlib,sys;p=sys.argv[1];print('SRC-SHA256', p, hashlib.sha256(open(p,'rb').read()).hexdigest()[:16])" "%VSRC%" >> srcpath.log 2>&1
call "%XV%\xvlog.bat" -work xil_defaultlib %DEFS% "%ROOT%\rtl\crc32_8b.v" "%ROOT%\rtl\fifo_sync.v" "%ROOT%\rtl\fifo_async.v" "%ROOT%\rtl\mac_rx_64.v" "%VSRC%" "%TB%" > xv.log 2>&1
if errorlevel 1 (type xv.log & popd & echo XVLOG-FAIL [%NAME%] & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xv.log >NUL && (echo IMPLICIT-WIRE-FAIL [%NAME%]: & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xv.log & popd & exit /b 1)
call "%XV%\xelab.bat" -debug typical -timescale 1ns/1ps -L xil_defaultlib xil_defaultlib.tb_f3_resync -s tb_f3_resync -log xe.log > xe_out.log 2>&1
if errorlevel 1 (type xe_out.log & popd & echo XELAB-FAIL [%NAME%] & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xe.log >NUL && (echo ELAB-IMPLICIT-FAIL [%NAME%]: & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xe.log & popd & exit /b 1)
call "%XV%\xsim.bat" tb_f3_resync -runall -log xs.log > xs_console.log 2>&1
REM ---- run witnesses: arm banner + stimulus + termination ----
findstr /C:"F3R ARM=%ARMID%" xs.log >NUL || (echo NO-RUN [%NAME%]: no arm banner & popd & exit /b 1)
findstr /C:"F3R TB-STIM" xs.log >NUL || (echo NO-STIM [%NAME%] & popd & exit /b 1)
findstr /C:"TIMEOUT" xs.log >NUL && (echo TIMEOUT [%NAME%] & popd & exit /b 1)
findstr /C:"TB-CRC-SELFTEST-FAIL" xs.log >NUL && (echo TB-CRC-FAIL [%NAME%] & popd & exit /b 1)

REM ---- per-arm verdicts ----
if /i "%NAME%"=="F"    call :chkF && (popd & exit /b 0) || (popd & exit /b 1)
if /i "%NAME%"=="L"    call :chkL && (popd & exit /b 0) || (popd & exit /b 1)
if /i "%NAME%"=="M1"   call :chkM1 && (popd & exit /b 0) || (popd & exit /b 1)
if /i "%NAME%"=="M2"   call :chkM2 && (popd & exit /b 0) || (popd & exit /b 1)
if /i "%NAME%"=="CTRL" call :chkC && (popd & exit /b 0) || (popd & exit /b 1)
popd
echo UNKNOWN-ARM [%NAME%]
exit /b 1

:chkF
findstr /C:"F3R ARM=F resync_en=1 ctrl_ifg=0" xs.log >NUL || (echo   [FAIL] F: compiled config mismatch & exit /b 1)
findstr /C:"F3R CHK J1=1 J2=1 J3eq=1 J3pos=1 J4=1 J5=1 J6=1 ALL=1" xs.log >NUL || (echo   [FAIL] F: CHK line not all green & exit /b 1)
findstr /C:"F3R XFAIL-REPRODUCED" xs.log >NUL && (echo   [FAIL] F: defect marker present & exit /b 1)
exit /b 0

:chkL
findstr /C:"F3R ARM=L resync_en=0" xs.log >NUL || (echo   [FAIL] L: compiled config mismatch & exit /b 1)
findstr /C:"F3R CHK J1=0 J2=0 J3eq=1 J3pos=0 J4=1 J5=0 J6=1 ALL=0" xs.log >NUL || (echo   [FAIL] L: CHK line not the designed red set & exit /b 1)
findstr /C:"F3R XFAIL-REPRODUCED frag=1 trunc_with_crs=1 stale_frag=1" xs.log >NUL || (echo   [FAIL] L: historical defect shape absent & exit /b 1)
exit /b 0

:chkM1
findstr /C:"F3R ARM=M1 resync_en=1" xs.log >NUL || (echo   [FAIL] M1: compiled config mismatch & exit /b 1)
findstr /C:"F3R CHK J1=0 J2=0 J3eq=0 J3pos=0 J4=1 J5=0 J6=1 ALL=0" xs.log >NUL || (echo   [FAIL] M1: CHK line not the designed red set & exit /b 1)
findstr /C:"F3R XFAIL-REPRODUCED" xs.log >NUL || (echo   [FAIL] M1: no defect shape marker & exit /b 1)
exit /b 0

:chkM2
findstr /C:"F3R ARM=M2 resync_en=1" xs.log >NUL || (echo   [FAIL] M2: compiled config mismatch & exit /b 1)
findstr /C:"F3R CHK J1=0 J2=0 J3eq=0 J3pos=1 J4=1 J5=0 J6=1 ALL=0" xs.log >NUL || (echo   [FAIL] M2: CHK line not the designed red set & exit /b 1)
findstr /C:"F3R XFAIL-REPRODUCED" xs.log >NUL || (echo   [FAIL] M2: no defect shape marker & exit /b 1)
exit /b 0

:chkC
findstr /C:"F3R ARM=CTRL resync_en=1 ctrl_ifg=1" xs.log >NUL || (echo   [FAIL] CTRL: compiled config mismatch & exit /b 1)
findstr /C:"F3R CHK J1=1 J2=1 J3eq=1 J3pos=0 J4=1 J5=1 J6=1 ALL=1" xs.log >NUL || (echo   [FAIL] CTRL: CHK line not as designed & exit /b 1)
findstr /C:"ctrl-precond" xs.log >NUL || (echo   [FAIL] CTRL: no precond witness & exit /b 1)
findstr /C:"stable4=1" xs.log >NUL || (echo   [FAIL] CTRL: FIFO-empty precondition not met & exit /b 1)
exit /b 0
