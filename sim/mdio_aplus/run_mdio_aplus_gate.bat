@echo off
REM ==========================================================================
REM run_mdio_aplus_gate.bat -- mdio A+ variant arm gate (xsim only; SIM round).
REM   round  = _proj_10g/notes/p9_simfill_20261015 (sim backfill, 2026-10-15)
REM   design = _proj_10g/notes/p9_fix_mdio_design_20261014/DESIGN_v2r4.md
REM            S2.2 E7/E8 + S4.3 A+ variant arm P1/P2/P3 + S4.2-J-D
REM   DUT    = mdio_vio_top.v (E7 working copy made by mk_e7_top.py: DIV becomes
REM            a top-level parameter, default stays 25 so production elaboration
REM            is unchanged)
REM
REM   Arms (separate work dirs; SEQUENTIAL xsim -- never parallel, pit 7):
REM     base : E7 copy, DIV taken at DEFAULT and one instance at 65537
REM            expect: APL VERDICT ALL=PASS + both SUMMARY lines verbatim
REM     zero : mut/mut_zero.v  {1'b0, 1'b0, mdio_i, ...}
REM            expect: ALL=FAIL, holes exactly {PROD ssl_drop, VAR pbad_t0}
REM                    -- this mutation IS the board-side ambiguity the design
REM                    names in S4.2-J-D ("bit present but constant 0")
REM     swap : mut/mut_swap.v  {param_bad, stat_start_lost, ...}
REM            expect: ALL=FAIL, holes include {VAR pbad_t0, VAR ssl_t0}
REM                    -- catches a packing-order regression
REM
REM   exit codes: 0 = all requested arms behaved as designed / 1 = otherwise
REM               97 = refusal (bad root / missing input / xsim or xelab running)
REM   Arm identity: each arm prints VSRC= and DUT-SHA256= of the exact DUT file
REM   it compiles; base also gates on the E7 copy sha256, mutants on their path.
REM   NOTE: verdicts are grepped as SINGLE literal strings from APL lines --
REM         no pipes / no nested parens in those strings (cmd mangles them).
REM ==========================================================================
setlocal
set "HERE=%~dp0"
if "%HERE:~-1%"=="\" set "HERE=%HERE:~0,-1%"
for %%I in ("%HERE%\..\..") do set "ROOT=%%~fI"

REM ---- root guards (vacuum-gate tripwire; another checkout must be refused) ----
if not exist "%ROOT%\sim\mdio_aplus\tb_mdio_aplus.v" (echo [FAIL] bad root: %ROOT% & exit /b 97)
if not exist "%ROOT%\rtl\vlan_strip.v" (echo [FAIL] bad root, no rtl: %ROOT% & exit /b 97)
if not exist "%ROOT%\board\wrapper_p4.v" (echo [FAIL] bad root, no board: %ROOT% & exit /b 97)
if not exist "%ROOT%\sim\f3_resync\run_tb_f3_resync.bat" (echo [FAIL] bad root, no sim: %ROOT% & exit /b 97)
echo ROOT=%ROOT%

set "XV=C:\AMDDesignTools\2025.2\Vivado\bin"
set "PY=C:\Users\zhxue\anaconda3\python.exe"
set "GLBL=C:\AMDDesignTools\2025.2\data\verilog\src\glbl.v"
if not exist "%XV%\xvlog.bat" (echo [FAIL] xvlog missing: %XV% & exit /b 97)
if not exist "%PY%" (echo [FAIL] python not found: %PY% & exit /b 97)
if not exist "%GLBL%" (echo [FAIL] glbl.v missing: %GLBL% & exit /b 97)
if not exist "%HERE%\mdio_vio_top.v" (echo [FAIL] E7 copy missing, run mk_e7_top.py & exit /b 97)

REM ---- serial discipline: no other xsim / xelab running ----
tasklist | findstr /I "xsim.exe xelab.exe" >NUL && (
  echo [FAIL] xsim/xelab already running -- refuse to start
  exit /b 97
)

set "ARM=%~1"
if "%ARM%"=="" set "ARM=base"

REM ---- regenerate mutants (anchored + counted; stale anchor = hard fail) ----
"%PY%" "%HERE%\mut\mk_mut_aplus.py" > "%HERE%\mut\mutgen.log" 2>&1
if errorlevel 1 (type "%HERE%\mut\mutgen.log" & echo MUTGEN-FAIL & exit /b 1)

set "RCB=SKIP"
set "RCZ=SKIP"
set "RCS=SKIP"
if /i "%ARM%"=="base" call :arm_base
if /i "%ARM%"=="base" set "RCB=%errorlevel%"
if /i "%ARM%"=="all"  call :arm_base
if /i "%ARM%"=="all"  set "RCB=%errorlevel%"
if /i "%ARM%"=="zero" call :arm_zero
if /i "%ARM%"=="zero" set "RCZ=%errorlevel%"
if /i "%ARM%"=="all"  call :arm_zero
if /i "%ARM%"=="all"  set "RCZ=%errorlevel%"
if /i "%ARM%"=="swap" call :arm_swap
if /i "%ARM%"=="swap" set "RCS=%errorlevel%"
if /i "%ARM%"=="all"  call :arm_swap
if /i "%ARM%"=="all"  set "RCS=%errorlevel%"

echo ==================== SUMMARY ====================
echo   base runbase RC=%RCB%   expect 0: VERDICT ALL=PASS + PROD/VAR summaries verbatim
echo   zero runzero RC=%RCZ%   expect 0: ALL=FAIL + holes exactly PROD ssl_drop / VAR pbad_t0
echo   swap runswap RC=%RCS%   expect 0: ALL=FAIL + holes include VAR pbad_t0 / VAR ssl_t0

set "FAILS=0"
if not "%RCB%"=="SKIP" if not "%RCB%"=="0" set /a FAILS+=1
if not "%RCZ%"=="SKIP" if not "%RCZ%"=="0" set /a FAILS+=1
if not "%RCS%"=="SKIP" if not "%RCS%"=="0" set /a FAILS+=1
if "%FAILS%"=="0" (echo MDIO-APLUS-GATE: PASS & exit /b 0)
echo MDIO-APLUS-GATE: FAIL count=%FAILS%
exit /b 1

REM ==========================================================================
:arm_base
set "WD=%HERE%\runbase"
if not exist "%WD%" mkdir "%WD%"
if exist "%WD%\xsim.dir" rmdir /s /q "%WD%\xsim.dir"
pushd "%WD%"
set "DUT=%HERE%\mdio_vio_top.v"
echo VSRC=%DUT% ARM=base > srcpath.log
"%PY%" -c "import hashlib,sys;print('DUT-SHA256', hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "%DUT%" >> srcpath.log 2>&1
type srcpath.log
call "%XV%\xvlog.bat" -work work "%HERE%\mdio_master.v" "%DUT%" "%HERE%\vio_0_sim_stub.v" "%GLBL%" "%HERE%\tb_mdio_aplus.v" > xv.log 2>&1
if errorlevel 1 (type xv.log & popd & echo XVLOG-FAIL [base] & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091" /C:"VRFC 10-2989" /C:"implicitly declared" xv.log >NUL && (echo IMPLICIT-DECL-FAIL [base] & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091" /C:"VRFC 10-2989" /C:"implicitly declared" xv.log & popd & exit /b 1)
call "%XV%\xelab.bat" -L unisims_ver work.tb_mdio_aplus work.glbl -s tb_mdio_aplus -log xe.log > xe_out.log 2>&1
if errorlevel 1 (type xe_out.log & popd & echo XELAB-FAIL [base] & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091" /C:"VRFC 10-2989" /C:"implicitly declared" xe.log >NUL && (echo ELAB-IMPLICIT-FAIL [base] & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091" /C:"VRFC 10-2989" /C:"implicitly declared" xe.log & popd & exit /b 1)
call "%XV%\xsim.bat" tb_mdio_aplus -runall -log xs.log > xs_console.log 2>&1
set "V="
findstr /C:"DUT-SHA256 4416710a230ff582" srcpath.log >NUL || set "V=%V% DUT-SHA-MISMATCH"
findstr /C:"APL ARM=PROD DIV=25 E7-default-no-override" xs.log >NUL || set "V=%V% NO-PROD-ARM-WITNESS"
findstr /C:"APL ARM=VAR DIV=65537 clamped-65536" xs.log >NUL || set "V=%V% NO-VAR-ARM-WITNESS"
findstr /C:"APL SUMMARY PROD pbad_t0=0 ssl_t0=0 ssl_mid=0 ssl_drop=1 ssl_clean=0 sticky_end=1 sticky_clr=0 frame_cyc=3200 mdc1_cyc=25 mdct_cyc=50" xs.log >NUL || set "V=%V% PROD-SUMMARY-MISMATCH"
findstr /C:"APL SUMMARY VAR pbad_t0=1 ssl_t0=0 ssl_mid=0 ssl_drop=1 ssl_clean=0 sticky_end=1 sticky_clr=0 frame_cyc=8388608 mdc1_cyc=65536 mdct_cyc=131072" xs.log >NUL || set "V=%V% VAR-SUMMARY-MISMATCH"
findstr /C:"APL VERDICT ALL=PASS" xs.log >NUL || set "V=%V% NO-ALL-PASS"
findstr /C:"APL MISMATCH" xs.log >NUL && set "V=%V% HAS-MISMATCH"
findstr /C:"TIMEOUT-APL" xs.log >NUL && set "V=%V% TIMEOUT"
findstr /C:"=== done ===" xs.log >NUL || set "V=%V% NO-DONE-MARKER"
echo ---- arm base evidence ----
findstr /C:"DUT-SHA256" srcpath.log
findstr /C:"APL SUMMARY" xs.log
findstr /C:"APL VERDICT" xs.log
findstr /C:"APL MISMATCH" xs.log
if not "%V%"=="" (echo   [FAIL] base:%V% & popd & exit /b 1)
echo   [PASS] base: ALL=PASS + PROD/VAR summaries verbatim
popd
exit /b 0

REM ==========================================================================
:arm_zero
set "WD=%HERE%\runzero"
if not exist "%WD%" mkdir "%WD%"
if exist "%WD%\xsim.dir" rmdir /s /q "%WD%\xsim.dir"
pushd "%WD%"
set "DUT=%HERE%\mut\mut_zero.v"
echo VSRC=%DUT% ARM=zero > srcpath.log
"%PY%" -c "import hashlib,sys;print('DUT-SHA256', hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "%DUT%" >> srcpath.log 2>&1
type srcpath.log
findstr /C:"{1'b0, 1'b0, mdio_i," "%DUT%" >NUL || (echo MUT-IDENTITY-FAIL [zero] & popd & exit /b 1)
call "%XV%\xvlog.bat" -work work "%HERE%\mdio_master.v" "%DUT%" "%HERE%\vio_0_sim_stub.v" "%GLBL%" "%HERE%\tb_mdio_aplus.v" > xv.log 2>&1
if errorlevel 1 (type xv.log & popd & echo XVLOG-FAIL [zero] & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091" /C:"VRFC 10-2989" /C:"implicitly declared" xv.log >NUL && (echo IMPLICIT-DECL-FAIL [zero] & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091" /C:"VRFC 10-2989" /C:"implicitly declared" xv.log & popd & exit /b 1)
call "%XV%\xelab.bat" -L unisims_ver work.tb_mdio_aplus work.glbl -s tb_mdio_aplus -log xe.log > xe_out.log 2>&1
if errorlevel 1 (type xe_out.log & popd & echo XELAB-FAIL [zero] & exit /b 1)
call "%XV%\xsim.bat" tb_mdio_aplus -runall -log xs.log > xs_console.log 2>&1
set "V="
findstr /C:"APL VERDICT ALL=FAIL" xs.log >NUL || set "V=%V% NO-ALL-FAIL"
findstr /C:"APL VERDICT ALL=PASS" xs.log >NUL && set "V=%V% UNEXPECTED-ALL-PASS"
findstr /C:"APL MISMATCH PROD ssl_drop exp=1 got=0" xs.log >NUL || set "V=%V% NO-PROD-SSLDROP-HOLE"
findstr /C:"APL MISMATCH VAR pbad_t0 exp=1 got=0" xs.log >NUL || set "V=%V% NO-VAR-PBAD-HOLE"
findstr /C:"APL MISMATCH VAR ssl_t0" xs.log >NUL && set "V=%V% UNEXPECTED-VAR-SSLT0-HOLE"
findstr /C:"APL SUMMARY PROD pbad_t0=0 ssl_t0=0 ssl_mid=0 ssl_drop=0 ssl_clean=0 sticky_end=1 sticky_clr=0 frame_cyc=3200 mdc1_cyc=25 mdct_cyc=50" xs.log >NUL || set "V=%V% PROD-SHAPE-NOT-AS-DESIGNED"
findstr /C:"APL MISMATCH PROD ssl_clean" xs.log >NUL && set "V=%V% EXTRA-PROD-SSLCLEAN-HOLE"
findstr /C:"TIMEOUT-APL" xs.log >NUL && set "V=%V% TIMEOUT"
echo ---- arm zero evidence ----
findstr /C:"DUT-SHA256" srcpath.log
findstr /C:"APL SUMMARY" xs.log
findstr /C:"APL VERDICT" xs.log
findstr /C:"APL MISMATCH" xs.log
if not "%V%"=="" (echo   [FAIL] zero:%V% & popd & exit /b 1)
echo   [PASS] zero: ALL=FAIL with exactly the designed holes
popd
exit /b 0

REM ==========================================================================
:arm_swap
set "WD=%HERE%\runswap"
if not exist "%WD%" mkdir "%WD%"
if exist "%WD%\xsim.dir" rmdir /s /q "%WD%\xsim.dir"
pushd "%WD%"
set "DUT=%HERE%\mut\mut_swap.v"
echo VSRC=%DUT% ARM=swap > srcpath.log
"%PY%" -c "import hashlib,sys;print('DUT-SHA256', hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "%DUT%" >> srcpath.log 2>&1
type srcpath.log
findstr /C:"{param_bad, stat_start_lost, mdio_i," "%DUT%" >NUL || (echo MUT-IDENTITY-FAIL [swap] & popd & exit /b 1)
call "%XV%\xvlog.bat" -work work "%HERE%\mdio_master.v" "%DUT%" "%HERE%\vio_0_sim_stub.v" "%GLBL%" "%HERE%\tb_mdio_aplus.v" > xv.log 2>&1
if errorlevel 1 (type xv.log & popd & echo XVLOG-FAIL [swap] & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091" /C:"VRFC 10-2989" /C:"implicitly declared" xv.log >NUL && (echo IMPLICIT-DECL-FAIL [swap] & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091" /C:"VRFC 10-2989" /C:"implicitly declared" xv.log & popd & exit /b 1)
call "%XV%\xelab.bat" -L unisims_ver work.tb_mdio_aplus work.glbl -s tb_mdio_aplus -log xe.log > xe_out.log 2>&1
if errorlevel 1 (type xe_out.log & popd & echo XELAB-FAIL [swap] & exit /b 1)
call "%XV%\xsim.bat" tb_mdio_aplus -runall -log xs.log > xs_console.log 2>&1
set "V="
findstr /C:"APL VERDICT ALL=FAIL" xs.log >NUL || set "V=%V% NO-ALL-FAIL"
findstr /C:"APL VERDICT ALL=PASS" xs.log >NUL && set "V=%V% UNEXPECTED-ALL-PASS"
findstr /C:"APL MISMATCH VAR pbad_t0 exp=1 got=0" xs.log >NUL || set "V=%V% NO-VAR-PBAD-HOLE"
findstr /C:"APL MISMATCH VAR ssl_t0 exp=0 got=1" xs.log >NUL || set "V=%V% NO-VAR-SSLT0-HOLE"
findstr /C:"APL MISMATCH PROD ssl_drop exp=1 got=0" xs.log >NUL || set "V=%V% NO-PROD-SSLDROP-HOLE"
findstr /C:"TIMEOUT-APL" xs.log >NUL && set "V=%V% TIMEOUT"
echo ---- arm swap evidence ----
findstr /C:"DUT-SHA256" srcpath.log
findstr /C:"APL SUMMARY" xs.log
findstr /C:"APL VERDICT" xs.log
findstr /C:"APL MISMATCH" xs.log
if not "%V%"=="" (echo   [FAIL] swap:%V% & popd & exit /b 1)
echo   [PASS] swap: ALL=FAIL with the packing-order holes
popd
exit /b 0
