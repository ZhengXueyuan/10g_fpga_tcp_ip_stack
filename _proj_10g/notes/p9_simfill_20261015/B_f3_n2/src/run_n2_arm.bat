@echo off
REM ==========================================================================
REM run_n2_arm.bat -- F-3 N-2: I5' DEFAULT-OFF arm, measured (xsim only, zero build).
REM   round  = _proj_10g/notes/p9_simfill_20261015
REM   design = _proj_10g/notes/p9_fix_f3_design_20261014/DESIGN_v2r4.md (= v2r2+v2r3+v2r4)
REM            S2 N-2 / N-3  + v2r3 S1-4 cheap-falsification recipe, friction (a)
REM   DUT    = board/wrapper_p4.v **COPY** -- NOT the tree file (see below)
REM
REM   WHY A COPY: the design's recipe is "feed the counters gate a wrapper copy that
REM   passes RESYNC_EN=0". N-3 says the gate's explicit file table line 20
REM   (echo %ROOT%\board\wrapper_p4.v >> files.f) must be redirected for that copy.
REM   The original gate lives in sim/p6e_pcie/ (sealed for this round), so this
REM   runner re-implements that exact command sequence in its OWN directory with
REM   line 20 pointed at the arm's wrapper copy. Everything else -- file glob,
REM   macros, xpm/glbl handling, TB, stub -- is kept identical; the TB and stub are
REM   used from frozen\ copies (sha-checked against sim/p6e_pcie at run time) so an
REM   in-flight edit in that directory cannot silently change this arm's evidence.
REM
REM   Arms (separate work dirs; SEQUENTIAL xsim, never two at once):
REM     off       wrapper OFF (VLAN_STRIP_RESYNC=0), frozen TB (H1-fixed: opening SOP)
REM               expect PASS_ALL + W26=69 W27=256 + W30=257 W31=2056
REM     on        wrapper ON  (byte-identical copy),      frozen TB
REM               expect the same readings (SAME-SESSION control; the H1 fix makes
REM               the ON arm reproduce the baseline too, so the OFF reading is a
REM               controlled contrast, not a lone number)
REM     off_nosop wrapper OFF, NOSOP TB (historical stimulus: tuser never asserted)
REM               *** THE discriminating arm for I5' *** -- the 5 on-disk backups
REM               were taken SOP-less; I5' says the OFF arm must reproduce them
REM               verbatim.  expect PASS_ALL + the same readings.
REM     on_nosop  wrapper ON,  NOSOP TB -- stimulus VARIABLE control: proves the
REM               SOP-less stimulus really is the shape that trips the gate when
REM               the gate is ON (so the off_nosop PASS above is not vacuous).
REM               expect: NO PASS_ALL + the gate's own H1 criterion red.
REM
REM   exit codes: 0 = arm(s) behaved as designed / 1 = otherwise
REM               97 = refusal (bad root / missing input / xsim or xelab running)
REM   NOTE: verdicts are grepped as SINGLE literal strings; no pipes / no nested
REM         parens in the grepped text (cmd mangles those).
REM ==========================================================================
setlocal
set "HERE=%~dp0"
if "%HERE:~-1%"=="\" set "HERE=%HERE:~0,-1%"
for %%I in ("%HERE%\..\..\..") do set "ROOT=%%~fI"

REM ---- root guards (vacuum-gate tripwire) ----
if not exist "%ROOT%\board\wrapper_p4.v" (echo [FAIL] bad root, no wrapper: %ROOT% & exit /b 97)
if not exist "%ROOT%\rtl\vlan_strip.v" (echo [FAIL] bad root, no rtl: %ROOT% & exit /b 97)
if not exist "%ROOT%\sim\f3_resync\run_tb_f3_resync.bat" (echo [FAIL] bad root, no sim: %ROOT% & exit /b 97)
if not exist "%ROOT%\CLAUDE.md" (echo [FAIL] bad root, no CLAUDE.md: %ROOT% & exit /b 97)
if not exist "%HERE%\frozen\tb_p6e_pcie_counters.FROZEN.v" (echo [FAIL] frozen TB missing & exit /b 97)
if not exist "%HERE%\mk_wr_n2.py" (echo [FAIL] mk_wr_n2.py missing & exit /b 97)
if not exist "%HERE%\mk_tb_nosop.py" (echo [FAIL] mk_tb_nosop.py missing & exit /b 97)
echo ROOT=%ROOT%

set "XV=C:\AMDDesignTools\2025.2\Vivado\bin"
set "PY=C:\Users\zhxue\anaconda3\python.exe"
set "GLBL=C:\AMDDesignTools\2025.2\data\verilog\src\glbl.v"
if not exist "%XV%\xvlog.bat" (echo [FAIL] xvlog missing: %XV% & exit /b 97)
if not exist "%PY%" (echo [FAIL] python not found: %PY% & exit /b 97)
if not exist "%GLBL%" (echo [FAIL] glbl.v missing: %GLBL% & exit /b 97)

REM ---- serial discipline: no other xsim / xelab running ----
tasklist | findstr /I "xsim.exe xelab.exe" >NUL && (
  echo [FAIL] xsim/xelab already running -- refuse to start
  exit /b 97
)

set "ARM=%~1"
if "%ARM%"=="" set "ARM=off"
if /i "%ARM%"=="pair" set "ARM=both"

REM ---- wrapper copies (anchored + counted; stale anchor = hard fail) ----
"%PY%" "%HERE%\mk_wr_n2.py" "%ROOT%" > "%HERE%\wrgen.log" 2>&1
if errorlevel 1 (type "%HERE%\wrgen.log" & echo WRGEN-FAIL & exit /b 1)
type "%HERE%\wrgen.log"
findstr /C:"MK-WR-N2: OK" "%HERE%\wrgen.log" >NUL || (echo WRGEN-MARKER-MISSING & exit /b 1)

REM ---- SOP-less (historical stimulus) TB variant ----
"%PY%" "%HERE%\mk_tb_nosop.py" > "%HERE%\nosopgen.log" 2>&1
if errorlevel 1 (type "%HERE%\nosopgen.log" & echo NOSOPGEN-FAIL & exit /b 1)
type "%HERE%\nosopgen.log"
findstr /C:"MK-TB-NOSOP: OK" "%HERE%\nosopgen.log" >NUL || (echo NOSOPGEN-MARKER-MISSING & exit /b 1)

REM ---- frozen-input identity witness (copy vs the tree's live p6e files) ----
"%PY%" -c "import hashlib,sys;h=lambda x:hashlib.sha256(open(x,'rb').read()).hexdigest();a=h(sys.argv[1]);b=h(sys.argv[2]);print('FROZEN-TB-SHA256 ',a);print('LIVE-TB-SHA256   ',b);print('FROZEN-TB-MATCH' if a==b else 'FROZEN-TB-DIFFERS')" "%HERE%\frozen\tb_p6e_pcie_counters.FROZEN.v" "%ROOT%\sim\p6e_pcie\tb_p6e_pcie_counters.v" > "%HERE%\frozen_sha.log" 2>&1
"%PY%" -c "import hashlib,sys;h=lambda x:hashlib.sha256(open(x,'rb').read()).hexdigest();a=h(sys.argv[1]);b=h(sys.argv[2]);print('FROZEN-STUB-SHA256',a);print('LIVE-STUB-SHA256  ',b);print('FROZEN-STUB-MATCH' if a==b else 'FROZEN-STUB-DIFFERS')" "%HERE%\frozen\xdma_0_sim_stub.FROZEN.v" "%ROOT%\sim\p6e_pcie\xdma_0_sim_stub.v" >> "%HERE%\frozen_sha.log" 2>&1
type "%HERE%\frozen_sha.log"

set "RCO=SKIP"
set "RCN=SKIP"
set "RCF=SKIP"
set "RCX=SKIP"
if /i "%ARM%"=="off"       call :runarm off       "%HERE%\wr_off\wrapper_p4_resync0.v" "%HERE%\frozen\tb_p6e_pcie_counters.FROZEN.v" pass
if /i "%ARM%"=="off"       set "RCO=%errorlevel%"
if /i "%ARM%"=="on"        call :runarm on        "%HERE%\wr_on\wrapper_p4.v"          "%HERE%\frozen\tb_p6e_pcie_counters.FROZEN.v" pass
if /i "%ARM%"=="on"        set "RCN=%errorlevel%"
if /i "%ARM%"=="off_nosop" call :runarm off_nosop "%HERE%\wr_off\wrapper_p4_resync0.v" "%HERE%\frozen\tb_p6e_pcie_counters.NOSOP.v"  pass
if /i "%ARM%"=="off_nosop" set "RCF=%errorlevel%"
if /i "%ARM%"=="on_nosop"  call :runarm on_nosop  "%HERE%\wr_on\wrapper_p4.v"          "%HERE%\frozen\tb_p6e_pcie_counters.NOSOP.v"  fail
if /i "%ARM%"=="on_nosop"  set "RCX=%errorlevel%"
if /i "%ARM%"=="both"      call :runarm off       "%HERE%\wr_off\wrapper_p4_resync0.v" "%HERE%\frozen\tb_p6e_pcie_counters.FROZEN.v" pass
if /i "%ARM%"=="both"      set "RCO=%errorlevel%"
if /i "%ARM%"=="both"      call :runarm on        "%HERE%\wr_on\wrapper_p4.v"          "%HERE%\frozen\tb_p6e_pcie_counters.FROZEN.v" pass
if /i "%ARM%"=="both"      set "RCN=%errorlevel%"
if /i "%ARM%"=="all"       call :runarm off       "%HERE%\wr_off\wrapper_p4_resync0.v" "%HERE%\frozen\tb_p6e_pcie_counters.FROZEN.v" pass
if /i "%ARM%"=="all"       set "RCO=%errorlevel%"
if /i "%ARM%"=="all"       call :runarm on        "%HERE%\wr_on\wrapper_p4.v"          "%HERE%\frozen\tb_p6e_pcie_counters.FROZEN.v" pass
if /i "%ARM%"=="all"       set "RCN=%errorlevel%"
if /i "%ARM%"=="all"       call :runarm off_nosop "%HERE%\wr_off\wrapper_p4_resync0.v" "%HERE%\frozen\tb_p6e_pcie_counters.NOSOP.v"  pass
if /i "%ARM%"=="all"       set "RCF=%errorlevel%"
if /i "%ARM%"=="all"       call :runarm on_nosop  "%HERE%\wr_on\wrapper_p4.v"          "%HERE%\frozen\tb_p6e_pcie_counters.NOSOP.v"  fail
if /i "%ARM%"=="all"       set "RCX=%errorlevel%"

set "RC=0"
if not "%RCO%"=="SKIP" if not "%RCO%"=="0" set "RC=1"
if not "%RCN%"=="SKIP" if not "%RCN%"=="0" set "RC=1"
if not "%RCF%"=="SKIP" if not "%RCF%"=="0" set "RC=1"
if not "%RCX%"=="SKIP" if not "%RCX%"=="0" set "RC=1"

echo ==================== SUMMARY ====================
echo   arm=%ARM% RC=%RC%
echo   off RC=%RCO%       expect 0: PASS_ALL + W26=69 W27=256 + W30=257 W31=2056
echo   on RC=%RCN%        expect 0: same readings, same session
echo   off_nosop RC=%RCF% expect 0: historical SOP-less stimulus also reproduces baseline
echo   on_nosop RC=%RCX%  expect 0: SOP-less stimulus trips the gate with the gate ON
if "%RC%"=="0" (echo N2-ARM-GATE: PASS & exit /b 0)
echo N2-ARM-GATE: FAIL
exit /b 1

REM ==========================================================================
:runarm
REM %1 = arm tag   %2 = wrapper file   %3 = TB file   %4 = expected mode (pass|fail)
set "TAG=%~1"
set "WRP=%~2"
set "TBF=%~3"
set "MODE=%~4"
set "WD=%HERE%\run_%TAG%"
if not exist "%WD%" mkdir "%WD%"
if exist "%WD%\xsim.dir" rmdir /s /q "%WD%\xsim.dir"
pushd "%WD%"
echo ARMTAG=%TAG% > arm_identity.log
echo WRP=%WRP% >> arm_identity.log
echo TBF=%TBF% >> arm_identity.log
"%PY%" -c "import hashlib,sys;h=lambda x:hashlib.sha256(open(x,'rb').read()).hexdigest();print('WRP-SHA256',h(sys.argv[1]));print('TB-SHA256 ',h(sys.argv[2]))" "%WRP%" "%TBF%" >> arm_identity.log 2>&1
type arm_identity.log

REM ---- arm identity (hard, checked BEFORE compiling) -------------------------
if /i "%TAG%"=="off"       findstr /C:"FROZEN-OFF" "%WRP%" >NUL || (echo OFF-IDENTITY-FAIL-no-marker & popd & exit /b 1)
if /i "%TAG%"=="off"       findstr /C:"VLAN_STRIP_RESYNC = 1'b1" "%WRP%" >NUL && (echo OFF-IDENTITY-FAIL-still-1b1 & popd & exit /b 1)
if /i "%TAG%"=="off_nosop" findstr /C:"FROZEN-OFF" "%WRP%" >NUL || (echo OFF-IDENTITY-FAIL-no-marker & popd & exit /b 1)
if /i "%TAG%"=="on"        findstr /C:"VLAN_STRIP_RESYNC = 1'b1" "%WRP%" >NUL || (echo ON-IDENTITY-FAIL-no-1b1 & popd & exit /b 1)
if /i "%TAG%"=="on_nosop"  findstr /C:"VLAN_STRIP_RESYNC = 1'b1" "%WRP%" >NUL || (echo ON-IDENTITY-FAIL-no-1b1 & popd & exit /b 1)
if /i "%TAG%"=="off_nosop" findstr /C:"historical SOP-less stimulus" "%TBF%" >NUL || (echo NOSOP-IDENTITY-FAIL-no-marker & popd & exit /b 1)
if /i "%TAG%"=="on_nosop"  findstr /C:"historical SOP-less stimulus" "%TBF%" >NUL || (echo NOSOP-IDENTITY-FAIL-no-marker & popd & exit /b 1)

REM ---- file table: original gate's lines 18-25, its line 20 redirected -------
dir /b /s "%ROOT%\rtl\*.v"                                     > files.f
dir /b /s "%ROOT%\hls\slowstack_prj\solution1\syn\verilog\*.v" >> files.f
echo %WRP%                                                     >> files.f
echo %ROOT%\board\util_gmii_to_rgmii_us.v                      >> files.f
echo %ROOT%\board\uart_dbg.v                                   >> files.f
echo %ROOT%\_proj_pcie\rtl\axi_regs.v                          >> files.f
echo %HERE%\frozen\xdma_0_sim_stub.FROZEN.v                    >> files.f
echo %TBF%                                                     >> files.f
REM NOTE: do NOT use the `find` utility here -- under git-bash-launched cmd, PATH
REM can resolve `find` to GNU find (which then walks whole drives; measured: a
REM 37 MB growing log). Count with python instead.
"%PY%" -c "import sys;print('FILES_F_LINES',sum(1 for _ in open(sys.argv[1])))" files.f > files_f_count.txt
echo ---- files.f line count ----
type files_f_count.txt

REM ---- compile-input fingerprint (the tree is shared with other work streams) --
git -C "%ROOT%" rev-parse HEAD > git_head.txt 2>&1
type git_head.txt
"%PY%" -c "import hashlib,sys;ls=[l.strip() for l in open(sys.argv[1]) if l.strip()];h=lambda p:hashlib.sha256(open(p,'rb').read()).hexdigest();print('\n'.join(h(p)+' *'+p for p in ls));agg=hashlib.sha256(''.join(h(p)+' '+p+'\n' for p in ls).encode()).hexdigest();print('FP-NFILES',len(ls));print('FP-AGG',agg)" files.f > fingerprint.log
echo ---- fingerprint ----
findstr /C:"FP-NFILES" /C:"FP-AGG" fingerprint.log

call "%XV%\xvlog.bat" -sv -work xpm "%XV%\..\data\ip\xpm\xpm_memory\hdl\xpm_memory.sv" > xvlog_xpm.log 2>&1 || (type xvlog_xpm.log & popd & echo XVLOG-XPM-FAIL [%TAG%] & exit /b 1)
call "%XV%\xvlog.bat" -work xil_defaultlib -d PCIE_OBS -d DEV_USP -d APP_MODE -d DP_156MHZ -d P6B_SIM_CLKGEN -i %ROOT%\rtl -i %ROOT%\board -f files.f > xvlog_n2.log 2>&1 || (type xvlog_n2.log & popd & echo XVLOG-FAIL [%TAG%] & exit /b 1)
call "%XV%\xvlog.bat" -d PCIE_OBS -d DEV_USP -d APP_MODE -d DP_156MHZ -d P6B_SIM_CLKGEN -work xil_defaultlib "%GLBL%" >> xvlog_n2.log 2>&1 || (type xvlog_n2.log & popd & echo XVLOG-GLBL-FAIL [%TAG%] & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xvlog_n2.log >NUL && (echo IMPLICIT-DECL-FAIL [%TAG%] & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xvlog_n2.log & popd & exit /b 1)
call "%XV%\xelab.bat" -debug typical -L unisims_ver -L xpm xil_defaultlib.tb_p6e_pcie_counters xil_defaultlib.glbl -s tb_p6e_pcie_counters -log xelab_n2.log > NUL 2>&1 || (type xelab_n2.log & popd & echo XELAB-FAIL [%TAG%] & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xelab_n2.log >NUL && (echo ELAB-IMPLICIT-FAIL [%TAG%] & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xelab_n2.log & popd & exit /b 1)
call "%XV%\xsim.bat" tb_p6e_pcie_counters -runall -log xsim_n2_%TAG%.log > NUL 2>&1

REM ---- verdict ---------------------------------------------------------------
set "V="
if /i "%MODE%"=="pass" goto :verdict_pass
goto :verdict_fail

:verdict_pass
findstr /C:"PASS_ALL" "xsim_n2_%TAG%.log" >NUL || set "V=%V% NO-PASS_ALL"
findstr /C:"W26=69 W27=256" "xsim_n2_%TAG%.log" >NUL || set "V=%V% NO-W26-69-W27-256"
findstr /C:"W30=257 W31=2056" "xsim_n2_%TAG%.log" >NUL || set "V=%V% NO-W30-257-W31-2056"
findstr /C:"=== done ===" "xsim_n2_%TAG%.log" >NUL || set "V=%V% NO-DONE-MARKER"
findstr /C:"TIMEOUT" "xsim_n2_%TAG%.log" >NUL && set "V=%V% TIMEOUT"
findstr /C:"FAIL" "xsim_n2_%TAG%.log" >NUL && set "V=%V% HAS-FAIL-TEXT"
goto :verdict_report

:verdict_fail
echo expected-fail arm: gate must red on the SOP-less stimulus
REM NOTE: do NOT grep the chk() name prefix here -- tb_p6e_pcie_counters.v passes
REM names as a 256-bit reg (32 bytes) and its long Chinese check names get
REM truncated/mangled, so "[FAIL] H1 W27 == DEPTH" is NOT what lands in the log.
REM Use the printed reading instead (historic shape, identical to the archived
REM pre-fix PREFIX log: W26=3 W27=5 W30=320 W31=2560).
findstr /C:"PASS_ALL" "xsim_n2_%TAG%.log" >NUL && set "V=%V% UNEXPECTED-PASS_ALL"
findstr /C:"W26=3 W27=5" "xsim_n2_%TAG%.log" >NUL || set "V=%V% NO-HISTORIC-RED-SHAPE"
findstr /C:"FAIL      tb_p6e_pcie_counters" "xsim_n2_%TAG%.log" >NUL || set "V=%V% NO-TB-FAIL-LINE"
findstr /C:"[FAIL]" "xsim_n2_%TAG%.log" >NUL || set "V=%V% NO-FAIL-LINE"
findstr /C:"=== done ===" "xsim_n2_%TAG%.log" >NUL || set "V=%V% NO-DONE-MARKER"
findstr /C:"TIMEOUT" "xsim_n2_%TAG%.log" >NUL && set "V=%V% TIMEOUT"

:verdict_report
echo ---- arm %TAG% readings ----
findstr /C:"[INFO] H" "xsim_n2_%TAG%.log"
findstr /C:"W26=" "xsim_n2_%TAG%.log"
findstr /C:"W30=" "xsim_n2_%TAG%.log"
findstr /C:"[FAIL]" "xsim_n2_%TAG%.log"
findstr /C:"PASS_ALL" "xsim_n2_%TAG%.log"
findstr /C:"FAIL      tb_p6e_pcie_counters" "xsim_n2_%TAG%.log"
if not "%V%"=="" (echo   [FAIL] arm %TAG%:%V% & popd & exit /b 1)
echo   [PASS] arm %TAG%
popd
exit /b 0
