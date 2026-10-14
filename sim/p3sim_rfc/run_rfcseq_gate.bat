@echo off
setlocal
REM =====================================================================
REM run_rfcseq_gate.bat -- P7B-BUILDG-RFC-SEQ gate (self-locating)
REM   ARM A   (FIXED) : rtl/tcp_rx.v (RFC seq_lt)          TB -d SEQRF_TAIL
REM                     expect "RFSEQ ALL PASS" in xs1/xs2/xs3; model check
REM                     (SEQRFC_ARM=fixed) OK on nostall,stall; hard LINE-63
REM                     known divergence signature must be UNCHANGED.
REM   ARM AO  (A-OFF) : rtl/tcp_rx.v, TB WITHOUT -d SEQRF_TAIL (zero-perturbation
REM                     conservation): resp_{,stall,hard}.memh sha256 must equal
REM                     the frozen pre-change values (RSP_*_SHA below, taken from
REM                     a clean pre-change run of sim/p3sim + sim/p3sim_sw).
REM   ARM G   (LEGACY): frozen/tcp_rx_prefix.v (= pre-fix bytes; sha256 == G_SHA)
REM                     TB -d SEQRF_TAIL -d SEQRF_LEGACY; model env
REM                     SEQRFC_ARM=legacy. expect "RFSEQ LEGACY OK" + 3
REM                     XFAIL-REPRODUCED markers + model check RC=0.
REM   ARM M1..M4 (mutants): mut\mut_M1..M4.v (regenerated every run by
REM                     mk_mut_rfc.py from the RFC-fixed RTL; stale anchor =>
REM                     hard fail, nothing written):
REM     M1 (redundant term)         : == A arm incl. resp bytes (fc /b)
REM     M2 (half fix: ackresp only) : red set EXACTLY {F2}
REM     M3 (boundary inverted)      : red set EXACTLY {F5}
REM     M4 (seq_lt=1'b0)            : red set {F1,F2,F5}
REM     M2/M3/M4 model check must MISMATCH with the frozen first-divergence
REM     signature (backfilled constants M2_SIG/M3_SIG/M4_SIG).
REM Criteria:
REM   1) every arm: xvlog/xelab clean incl. 5-key implicit-wire scan; 3 xsim
REM      runs yield logs (no-run => hard fail); FATAL if python/RTL/TB/frozen
REM      missing ("nothing ran" must never pass)
REM   2) hash guards: A/M* arms check rtl/tcp_rx.v == A_SHA; G arm checks
REM      frozen/tcp_rx_prefix.v == G_SHA (7517c949... = pre-fix bytes)
REM   3) hard-mode known pre-existing divergence signature must be UNCHANGED
REM      (else: either somebody fixed it => update this gate, or a new
REM      divergence appeared => investigate; never silently re-pin)
REM   4) comment/implementation consistency (text criterion, design 5.3-6):
REM      rtl/tcp_rx.v contains "seq_diff[31]" and "RFC 793 SEQ_LT", and NO
REM      non-comment line contains "seq32 < ra_rcv_nxt"
REM   5) env-arm negative control (mirrors sim/p3sim_sw criterion 6): model
REM      check on the G arm resp files with SEQRFC_TAIL=1 but WITHOUT
REM      SEQRFC_ARM=legacy must MISMATCH (proves the oracle arm is load-bearing)
REM   6) exit code discipline: no unconditional PASS; FAIL count > 0 => exit 1
REM NOTE-G: design v3r2 5.3-4 writes "check legacy" for the G arm, but the CLI
REM   arm controls the SNDWND guard (not the seq arm). The G arm DUT (frozen
REM   pre-fix file) is compiled with guard=1 (TB default) => the CLI arm MUST
REM   stay "fixed" (same param as DUT, its documented contract); the "legacy"
REM   half is carried by the env SEQRFC_ARM=legacy. ("check legacy" on this
REM   DUT fails TCBF: guard=0 model vs guard=1 hardware.)
REM NOTE: never redirect into a name the tool itself uses (xvlog.log /
REM       xelab.log / xsim.log) -- cmd holds the handle and the tool then
REM       fails to open it.
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
set "GEN=%ROOT%\tools\gen_stim_tcp_rx.py"
set "RTL=%ROOT%\rtl\tcp_rx.v"
set "TB=%ROOT%\tb\tb_tcp_rx.v"
set "FRZ=%HERE%\frozen\tcp_rx_prefix.v"
REM ---- frozen hash constants (design v3r2 2.2-1 / 5.3-0; operands NOT empty) ----
set "A_SHA=793761589de8089325c9f2f94986a696e1b198b978bfef341f370d0975a2b9f1"
set "G_SHA=7517c94951598c7e42d11ba7d8e62164acc762cbbd8718356e4f8bf3bc6d1489"
set "RSP_DEF_SHA=7c95315f2f0761ca02a4a8c1c6845d030a5487434936ff9b23e14e33c36a7f80"
set "RSP_STALL_SHA=7c95315f2f0761ca02a4a8c1c6845d030a5487434936ff9b23e14e33c36a7f80"
set "RSP_HARD_SHA=2d96e7cc175027c6b8eb242efaefd36abbcfaa56dce8972f4c13b14e2db453ee"
REM ---- mutant first-divergence signatures (BACKFILLED at first green run) ----
set "M2_SIG=nostall LINE 315: exp 'FEND 0' resp None"
set "M3_SIG=nostall LINE 297: exp 'ACK 0 00000100' resp 'META 0a000001 3039 0064 0 00000100'"
set "M4_SIG=nostall LINE 245: exp 'ACK 0 00000A73' resp 'META 0a000001 d431 0014 1 00000000'"
cd /d "%HERE%"

if not exist "%GEN%" (echo [FAIL] generator missing: %GEN% & exit /b 1)
if not exist "%RTL%" (echo [FAIL] RTL missing: %RTL% & exit /b 1)
if not exist "%TB%"  (echo [FAIL] TB missing: %TB% & exit /b 1)
if not exist "%FRZ%" (echo [FAIL] frozen prefix missing: %FRZ% & exit /b 1)
if not exist "%PY%"  (echo [FAIL] python not found: %PY% & exit /b 1)

REM ---- criterion 4: comment/implementation consistency (live lines only) ----
"%PY%" -c "import sys;c=open(sys.argv[1],encoding='utf-8').read();L=c.splitlines();b=[l for l in L if not l.lstrip().startswith('//') and 'seq32 < ra_rcv_nxt' in l];sys.exit(0 if ('seq_diff[31]' in c and 'RFC 793 SEQ_LT' in c and not b) else 1)" "%RTL%"
if errorlevel 1 (echo [FAIL] criterion 4: rtl/tcp_rx.v comment/implementation consistency & exit /b 1)
echo   [PASS] criterion 4: seq_diff[31] + RFC 793 SEQ_LT present; no live old-compare line
REM ---- A-source hash guard: rtl/tcp_rx.v must be the RFC-fixed revision ----
"%PY%" -c "import hashlib,sys;sys.exit(0 if hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest()==sys.argv[2] else 1)" "%RTL%" "%A_SHA%"
if errorlevel 1 (echo [FAIL] A-source hash guard: rtl/tcp_rx.v != A_SHA a35cd980 & exit /b 1)
echo   [PASS] A-source hash guard: rtl/tcp_rx.v == %A_SHA%

REM ---- mutant generation (anchored + counted; stale anchor => hard fail) ----
"%PY%" "mut\mk_mut_rfc.py" "%ROOT%" > mut\mutgen.log 2>&1
if errorlevel 1 (type mut\mutgen.log & echo MUTGEN-FAIL & exit /b 1)
type mut\mutgen.log

call :run A   runA_a    "-d SEQRF_TAIL"  "%RTL%" ""       "%A_SHA%" "1" "fixed"
set "RCA=%errorlevel%"
call :run AO  runAO_off ""               "%RTL%" ""       "%A_SHA%" ""  "fixed"
set "RCAO=%errorlevel%"
call :run G   runG_g    "-d SEQRF_TAIL -d SEQRF_LEGACY" "%FRZ%" "legacy" "%G_SHA%" "1" "fixed"
set "RCG=%errorlevel%"
call :run M1  runM1_m1  "-d SEQRF_TAIL"  "%HERE%\mut\mut_M1.v" "" "" "1" "fixed"
set "RCM1=%errorlevel%"
call :run M2  runM2_m2  "-d SEQRF_TAIL"  "%HERE%\mut\mut_M2.v" "" "" "1" "fixed"
set "RCM2=%errorlevel%"
call :run M3  runM3_m3  "-d SEQRF_TAIL"  "%HERE%\mut\mut_M3.v" "" "" "1" "fixed"
set "RCM3=%errorlevel%"
call :run M4  runM4_m4  "-d SEQRF_TAIL"  "%HERE%\mut\mut_M4.v" "" "" "1" "fixed"
set "RCM4=%errorlevel%"

echo ==================== SUMMARY ====================
echo   A  FIXED   runA_a     RC=%RCA%    expect 0
echo   AO A-OFF   runAO_off  RC=%RCAO%   expect 0
echo   G  LEGACY  runG_g     RC=%RCG%    expect 0
echo   M1 REDUND  runM1_m1   RC=%RCM1%   expect 0 (== A arm)
echo   M2 HALF    runM2_m2   RC=%RCM2%   expect 0 (mechanism OK; red={F2})
echo   M3 BOUND   runM3_m3   RC=%RCM3%   expect 0 (mechanism OK; red={F5})
echo   M4 ZERO    runM4_m4   RC=%RCM4%   expect 0 (mechanism OK; red={F1,F2,F5})

set "FAILS=0"
if not "%RCA%"=="0"  set /a FAILS+=1
if not "%RCAO%"=="0" set /a FAILS+=1
if not "%RCG%"=="0"  set /a FAILS+=1
if not "%RCM1%"=="0" set /a FAILS+=1
if not "%RCM2%"=="0" set /a FAILS+=1
if not "%RCM3%"=="0" set /a FAILS+=1
if not "%RCM4%"=="0" set /a FAILS+=1
for %%A in (runA_a runAO_off runG_g runM1_m1 runM2_m2 runM3_m3 runM4_m4) do (
  for %%M in (xs1.log xs2.log xs3.log chk_ns.log chk_h.log gen.log chk_rc.txt) do (
    if not exist "%%A\%%M" (echo   [FAIL] %%A\%%M missing & set /a FAILS+=1)
  )
)

REM ---- ARM A verdicts (all 3 modes) ----
set "OK=1"
for %%M in (xs1 xs2 xs3) do (
  findstr /C:"RFSEQ ALL PASS" "runA_a\%%M.log" > NUL
  if errorlevel 1 (echo   [FAIL] A %%M: no "RFSEQ ALL PASS" & set "OK=0")
  findstr /C:"[FAIL] RFSEQ" "runA_a\%%M.log" > NUL
  if not errorlevel 1 (echo   [FAIL] A %%M: has [FAIL] RFSEQ line & set "OK=0")
  findstr /C:"SNDWND ALL PASS" "runA_a\%%M.log" > NUL
  if errorlevel 1 (echo   [FAIL] A %%M: SNDWND legs no longer all-pass & set "OK=0")
)
if "%OK%"=="1" (echo   [PASS] ARM A: RFSEQ ALL PASS + SNDWND ALL PASS in xs1/xs2/xs3) else (set /a FAILS+=1)
findstr /C:"CNS=0" "runA_a\chk_rc.txt" > NUL
if errorlevel 1 (echo   [FAIL] ARM A: model check nostall,stall RC != 0 & set /a FAILS+=1)
findstr /C:"MISMATCH" "runA_a\chk_ns.log" > NUL
if not errorlevel 1 (echo   [FAIL] ARM A: model check reports MISMATCH & set /a FAILS+=1)
findstr /C:" OK" "runA_a\chk_ns.log" > NUL
if errorlevel 1 (echo   [FAIL] ARM A: no OK verdict line & set /a FAILS+=1)
type runA_a\chk_ns.log

REM ---- hard-mode known pre-existing divergence: signature must be UNCHANGED ----
findstr /C:"hard LINE 63: exp 'META 0A000001 D431 0014 1 00000000' resp 'FEND 1'" "runA_a\chk_h.log" > NUL
if errorlevel 1 (
  echo   [FAIL] hard-mode divergence signature changed/absent -- the known pre-existing
  echo          red was: hard LINE 63 exp META ... resp FEND 1, identical at HEAD 7517c949.
  echo          If it is FIXED now, update this gate; else investigate.
  set /a FAILS+=1
) else (
  echo   [PASS] hard-mode: known pre-existing divergence signature unchanged, LINE 63
)

REM ---- ARM AO: zero-perturbation conservation (resp bytes == frozen baseline) ----
call :hashguard "runAO_off\resp_tcp_rx.memh"   "%RSP_DEF_SHA%"   "A-off resp_tcp_rx.memh == frozen pre-change"
call :hashguard "runAO_off\resp_tcp_rx_stall.memh" "%RSP_STALL_SHA%" "A-off resp_tcp_rx_stall.memh == frozen pre-change"
call :hashguard "runAO_off\resp_tcp_rx_hard.memh"  "%RSP_HARD_SHA%"  "A-off resp_tcp_rx_hard.memh == frozen pre-change"
findstr /C:"CNS=0" "runAO_off\chk_rc.txt" > NUL
if errorlevel 1 (echo   [FAIL] ARM AO: model check nostall,stall RC != 0 & set /a FAILS+=1)

REM ---- ARM G verdicts (defect-reproduced markers + model check RC=0) ----
set "OK=1"
for %%M in (xs1 xs2 xs3) do (
  findstr /C:"RFSEQ LEGACY OK" "runG_g\%%M.log" > NUL
  if errorlevel 1 (echo   [FAIL] G %%M: no "RFSEQ LEGACY OK" & set "OK=0")
  findstr /C:"RFSEQ F5 XFAIL-REPRODUCED" "runG_g\%%M.log" > NUL
  if errorlevel 1 (echo   [FAIL] G %%M: no F5 XFAIL marker & set "OK=0")
  findstr /C:"RFSEQ F1 XFAIL-REPRODUCED" "runG_g\%%M.log" > NUL
  if errorlevel 1 (echo   [FAIL] G %%M: no F1 XFAIL marker & set "OK=0")
  findstr /C:"RFSEQ F2 XFAIL-REPRODUCED" "runG_g\%%M.log" > NUL
  if errorlevel 1 (echo   [FAIL] G %%M: no F2 XFAIL marker & set "OK=0")
  findstr /C:"[FAIL] RFSEQ" "runG_g\%%M.log" > NUL
  if not errorlevel 1 (echo   [FAIL] G %%M: has [FAIL] RFSEQ line & set "OK=0")
)
if "%OK%"=="1" (echo   [PASS] ARM G: RFSEQ LEGACY OK + F5/F1/F2 XFAIL in xs1/xs2/xs3) else (set /a FAILS+=1)
findstr /C:"CNS=0" "runG_g\chk_rc.txt" > NUL
if errorlevel 1 (echo   [FAIL] ARM G: model check env-legacy RC != 0 & set /a FAILS+=1)
type runG_g\chk_ns.log

REM ---- ARM M1: legs identical to A + resp bytes identical to A ----
set "OK=1"
for %%M in (xs1 xs2 xs3) do (
  findstr /C:"RFSEQ ALL PASS" "runM1_m1\%%M.log" > NUL
  if errorlevel 1 (echo   [FAIL] M1 %%M: no "RFSEQ ALL PASS" & set "OK=0")
)
if "%OK%"=="1" (echo   [PASS] ARM M1: RFSEQ ALL PASS in xs1/xs2/xs3, legs == A) else (set /a FAILS+=1)
findstr /C:"CNS=0" "runM1_m1\chk_rc.txt" > NUL
if errorlevel 1 (echo   [FAIL] ARM M1: model check RC != 0 & set /a FAILS+=1)
for %%M in (resp_tcp_rx.memh resp_tcp_rx_stall.memh resp_tcp_rx_hard.memh) do (
  fc /b "runA_a\%%M" "runM1_m1\%%M" > NUL
  if errorlevel 1 (echo   [FAIL] M1 %%M: bytes differ from A arm & set /a FAILS+=1) else (echo   [PASS] M1 %%M bytes == A arm)
)

REM ---- ARM M2: red set EXACTLY {F2}; model MISMATCH w/ frozen signature ----
set "OK=1"
for %%M in (xs1 xs2 xs3) do (
  findstr /C:"[FAIL] RFSEQ F2" "runM2_m2\%%M.log" > NUL
  if errorlevel 1 (echo   [FAIL] M2 %%M: F2 not red & set "OK=0")
  findstr /C:"RFSEQ F5 PASS" "runM2_m2\%%M.log" > NUL
  if errorlevel 1 (echo   [FAIL] M2 %%M: F5 not green & set "OK=0")
  findstr /C:"RFSEQ F3 PASS" "runM2_m2\%%M.log" > NUL
  if errorlevel 1 (echo   [FAIL] M2 %%M: F3 not green & set "OK=0")
  findstr /C:"RFSEQ F4 PASS" "runM2_m2\%%M.log" > NUL
  if errorlevel 1 (echo   [FAIL] M2 %%M: F4 not green & set "OK=0")
  findstr /C:"RFSEQ F1 PASS" "runM2_m2\%%M.log" > NUL
  if errorlevel 1 (echo   [FAIL] M2 %%M: F1 not green & set "OK=0")
  findstr /C:"RFSEQ ALL PASS" "runM2_m2\%%M.log" > NUL
  if not errorlevel 1 (echo   [FAIL] M2 %%M: aggregate ALL PASS in a mutated arm & set "OK=0")
)
if "%OK%"=="1" (echo   [PASS] ARM M2: red set EXACTLY {F2}) else (set /a FAILS+=1)
findstr /C:"MISMATCH" "runM2_m2\chk_ns.log" > NUL
if errorlevel 1 (echo   [FAIL] M2: model check did not MISMATCH & set /a FAILS+=1)
findstr /C:"%M2_SIG%" "runM2_m2\chk_ns.log" > NUL
if errorlevel 1 (echo   [FAIL] M2: frozen first-divergence signature absent/changed & set /a FAILS+=1) else (echo   [PASS] M2: frozen first-divergence signature present)

REM ---- ARM M3: red set EXACTLY {F5}; model MISMATCH w/ frozen signature ----
set "OK=1"
for %%M in (xs1 xs2 xs3) do (
  findstr /C:"[FAIL] RFSEQ F5" "runM3_m3\%%M.log" > NUL
  if errorlevel 1 (echo   [FAIL] M3 %%M: F5 not red & set "OK=0")
  findstr /C:"RFSEQ F3 PASS" "runM3_m3\%%M.log" > NUL
  if errorlevel 1 (echo   [FAIL] M3 %%M: F3 not green & set "OK=0")
  findstr /C:"RFSEQ F4 PASS" "runM3_m3\%%M.log" > NUL
  if errorlevel 1 (echo   [FAIL] M3 %%M: F4 not green & set "OK=0")
  findstr /C:"RFSEQ F1 PASS" "runM3_m3\%%M.log" > NUL
  if errorlevel 1 (echo   [FAIL] M3 %%M: F1 not green & set "OK=0")
  findstr /C:"RFSEQ F2 PASS" "runM3_m3\%%M.log" > NUL
  if errorlevel 1 (echo   [FAIL] M3 %%M: F2 not green & set "OK=0")
  findstr /C:"RFSEQ ALL PASS" "runM3_m3\%%M.log" > NUL
  if not errorlevel 1 (echo   [FAIL] M3 %%M: aggregate ALL PASS in a mutated arm & set "OK=0")
)
if "%OK%"=="1" (echo   [PASS] ARM M3: red set EXACTLY {F5}) else (set /a FAILS+=1)
findstr /C:"MISMATCH" "runM3_m3\chk_ns.log" > NUL
if errorlevel 1 (echo   [FAIL] M3: model check did not MISMATCH & set /a FAILS+=1)
findstr /C:"%M3_SIG%" "runM3_m3\chk_ns.log" > NUL
if errorlevel 1 (echo   [FAIL] M3: frozen first-divergence signature absent/changed & set /a FAILS+=1) else (echo   [PASS] M3: frozen first-divergence signature present)

REM ---- ARM M4: red set {F1,F2,F5}; model MISMATCH w/ frozen signature ----
set "OK=1"
for %%M in (xs1 xs2 xs3) do (
  findstr /C:"[FAIL] RFSEQ F5" "runM4_m4\%%M.log" > NUL
  if errorlevel 1 (echo   [FAIL] M4 %%M: F5 not red & set "OK=0")
  findstr /C:"[FAIL] RFSEQ F1" "runM4_m4\%%M.log" > NUL
  if errorlevel 1 (echo   [FAIL] M4 %%M: F1 not red & set "OK=0")
  findstr /C:"[FAIL] RFSEQ F2" "runM4_m4\%%M.log" > NUL
  if errorlevel 1 (echo   [FAIL] M4 %%M: F2 not red & set "OK=0")
  findstr /C:"RFSEQ F3 PASS" "runM4_m4\%%M.log" > NUL
  if errorlevel 1 (echo   [FAIL] M4 %%M: F3 not green & set "OK=0")
  findstr /C:"RFSEQ F4 PASS" "runM4_m4\%%M.log" > NUL
  if errorlevel 1 (echo   [FAIL] M4 %%M: F4 not green & set "OK=0")
  findstr /C:"RFSEQ ALL PASS" "runM4_m4\%%M.log" > NUL
  if not errorlevel 1 (echo   [FAIL] M4 %%M: aggregate ALL PASS in a mutated arm & set "OK=0")
)
if "%OK%"=="1" (echo   [PASS] ARM M4: red set {F1,F2,F5}) else (set /a FAILS+=1)
findstr /C:"MISMATCH" "runM4_m4\chk_ns.log" > NUL
if errorlevel 1 (echo   [FAIL] M4: model check did not MISMATCH & set /a FAILS+=1)
findstr /C:"%M4_SIG%" "runM4_m4\chk_ns.log" > NUL
if errorlevel 1 (echo   [FAIL] M4: frozen first-divergence signature absent/changed & set /a FAILS+=1) else (echo   [PASS] M4: frozen first-divergence signature present)

REM ---- env-arm negative control: G resp + tail env but WITHOUT SEQRFC_ARM=legacy ----
if exist runG_neg rmdir /s /q runG_neg
mkdir runG_neg
copy /Y "runG_g\resp_tcp_rx.memh" "runG_neg\" > NUL
pushd runG_neg
set "SEQRFC_ARM="
set "SEQRFC_TAIL=1"
"%PY%" "%GEN%" . check fixed nostall > chk_envneg.log 2>&1
set "RCEN=%errorlevel%"
popd
set "SEQRFC_TAIL="
if "%RCEN%"=="0" echo   [FAIL] env-negctl: check fixed PASSED without legacy env -- arm mirror not load-bearing
if "%RCEN%"=="0" set /a FAILS+=1
if not "%RCEN%"=="0" (
  findstr /C:"MISMATCH" "runG_neg\chk_envneg.log" > NUL
  if errorlevel 1 (echo   [FAIL] env-negctl: check failed w/o MISMATCH line & set /a FAILS+=1) else (echo   [PASS] env-arm negative control: MISMATCH reported without legacy env)
)

echo ---- key readings ----
for %%A in (runA_a runAO_off runG_g runM1_m1 runM2_m2 runM3_m3 runM4_m4) do (
  echo   [%%A xs1]
  findstr /C:"RFSEQ ARM=" /C:"RFSEQ F5 " /C:"RFSEQ F3 " /C:"RFSEQ F4 " /C:"RFSEQ F1 " /C:"RFSEQ F2 " /C:"RFSEQ END" /C:"RFSEQ ALL PASS" /C:"RFSEQ LEGACY OK" /C:"[FAIL] RFSEQ" "%%A\xs1.log"
)

if "%FAILS%"=="0" (echo RFCSEQ-GATE: PASS & exit /b 0)
echo RFCSEQ-GATE: FAIL count=%FAILS%
exit /b 1

REM =====================================================================
:hashguard
"%PY%" -c "import hashlib,sys;sys.exit(0 if hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest()==sys.argv[2] else 1)" "%~1" "%~2"
if errorlevel 1 (echo   [FAIL] hash guard: %~3 & set /a FAILS+=1) else (echo   [PASS] hash guard: %~3)
exit /b 0

REM =====================================================================
:run  NAME WD DEFS RSRC EARM ESHA TENV CARM
set "NAME=%~1"
set "WD=%~2"
set "DEFS=%~3"
set "RSRC=%~4"
set "EARM=%~5"
set "ESHA=%~6"
set "TENV=%~7"
set "CARM=%~8"
if not exist "%WD%" mkdir "%WD%"
pushd "%WD%"
if exist xsim.dir rmdir /s /q xsim.dir
echo run all > run.tcl
echo quit >> run.tcl
echo RSRC=%RSRC% DEFS=%DEFS% > srcpath.log
if not "%ESHA%"=="" (
  "%PY%" -c "import hashlib,sys;sys.exit(0 if hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest()==sys.argv[2] else 1)" "%RSRC%" "%ESHA%"
  if errorlevel 1 (popd & echo HASHGUARD-FAIL [%NAME%] src=%RSRC% & exit /b 1)
  echo   [PASS] %NAME% hash guard: RSRC == %ESHA%
)
set "SEQRFC_ARM=%EARM%"
set "SEQRFC_TAIL=%TENV%"
"%PY%" "%GEN%" . > gen.log 2>&1
if errorlevel 1 (type gen.log & popd & echo GEN-FAIL [%NAME%] & exit /b 1)
if "%TENV%"=="1" (
  findstr /C:"RFSEQ rf_pos" gen.log > NUL
  if errorlevel 1 (type gen.log & popd & echo GEN-NOTAIL [%NAME%]: no rf_pos banner & exit /b 1)
)
call "%XV%\xvlog.bat" -work xil_defaultlib %DEFS% "%ROOT%\rtl\crc32_8b.v" "%ROOT%\rtl\fifo_sync.v" "%ROOT%\rtl\mac_rx_64.v" "%ROOT%\rtl\tcp_cam.v" "%ROOT%\rtl\tcb.v" "%RSRC%" "%TB%" > xv.log 2>&1
if errorlevel 1 (type xv.log & popd & echo XVLOG-FAIL [%NAME%] & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xv.log > NUL
if not errorlevel 1 (echo IMPLICIT-WIRE [%NAME%]: & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xv.log & popd & exit /b 1)
findstr /I /C:"ERROR" xv.log > NUL
if not errorlevel 1 (type xv.log & popd & echo XVLOG-ERROR [%NAME%] & exit /b 1)
call "%XV%\xelab.bat" -debug typical -timescale 1ns/1ps -L xil_defaultlib xil_defaultlib.tb_tcp_rx -s tb_tcp_rx -log xe.log > xe_out.log 2>&1
if errorlevel 1 (type xe_out.log & popd & echo XELAB-FAIL [%NAME%] & exit /b 1)
findstr /I /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"undeclared symbol" xe.log > NUL
if not errorlevel 1 (echo ELAB-IMPLICIT [%NAME%]: & findstr /I /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"undeclared symbol" xe.log & popd & exit /b 1)
call "%XV%\xsim.bat" tb_tcp_rx -tclbatch run.tcl > xs1.log 2>&1
call "%XV%\xsim.bat" tb_tcp_rx -tclbatch run.tcl -testplusarg STALL > xs2.log 2>&1
call "%XV%\xsim.bat" tb_tcp_rx -tclbatch run.tcl -testplusarg HARD > xs3.log 2>&1
for %%M in (xs1 xs2 xs3) do (
  findstr /C:"SNDWND ARM=" "%%M.log" > NUL
  if errorlevel 1 (echo XSIM-NORUN [%NAME% %%M%]: no SNDWND banner & popd & exit /b 1)
)
if "%TENV%"=="1" for %%M in (xs1 xs2 xs3) do (
  findstr /C:"RFSEQ ARM=" "%%M.log" > NUL
  if errorlevel 1 (echo XSIM-NORUN-RF [%NAME% %%M%]: no RFSEQ banner & popd & exit /b 1)
)
"%PY%" "%GEN%" . check %CARM% nostall,stall > chk_ns.log 2>&1
echo CNS=%errorlevel% > chk_rc.txt
"%PY%" "%GEN%" . check %CARM% hard > chk_h.log 2>&1
echo CH=%errorlevel% >> chk_rc.txt
set "SEQRFC_ARM="
set "SEQRFC_TAIL="
popd
exit /b 0
