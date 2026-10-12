@echo off
REM run_tb_mir_uram_fifo.bat -- P9 URAM board-buffer unit gate (+ 12 mutation arms + 2 guard-teeth arms)
REM   unit gate for the URAM buffer between the mirror aux port and axis_c2h_stream
REM   usage: run_tb_mir_uram_fifo.bat [real|guard_rogue|mut_full_off|mut_full_e1|mut_issue_free|
REM            mut_val1|mut_clr_off|mut_clr_take|mut_dnreq|mut_rstn_off|mut_en_off|mut_dnclr|
REM            mut_wp_nmc|mut_guard_off]
REM     real        : compile rtl\mir_uram_fifo.v                    -> expect PASS_ALL (+ name-visibility guard)
REM     mut_*       : compile a single-point mutant from mut_uram.py -> expect a HARD failure signature
REM     guard_rogue : real RTL + `-d URAM_TB_ROGUE` (TB drives up_gnt w/o up_req)
REM                   -> expect the RTL guard string "FATAL mir_uram_fifo: upstream grant without req"
REM     mut_guard_off: mutant (guard $display removed) + `-d URAM_TB_ROGUE`
REM                   -> expect the guard string ABSENT (proves the rogue arm can tell)
REM   exit 0 only when the observed verdict matches the arm expectation.
REM   (2026-10-13 review round F1): a mutant arm is only "caught" with HARD evidence --
REM     the log must carry the `URAM_FIFO_GATE` verdict line, must NOT carry PASS_ALL, and must
REM     carry either a `[FAIL]` line or the RTL guard string. Anything else (crash / empty /
REM     truncated log) = INFRA-FAIL => exit /b 1. The old rule ("anything but PASS_ALL counts
REM     as caught") silently reported crashes as "caught" = false green in the negative-control
REM     direction (mute-gate family, project trap #53).
REM   (2026-10-13 review round F5): criterion names must be <= 32 chars -- names longer than
REM     32 bytes get their ID prefix TRUNCATED by the [255:0] name port. The real arm counts
REM     "[PASS]/[FAIL]" lines vs "] G" lines and hard-fails on mismatch.
REM   Each arm runs in its OWN dir (trap 7: shared xsim.dir => false failures).
REM   NOTE (2026-10-13, measured): the precompiled `-L xpm` library failed to elaborate in one
REM     observed case ("value for parameter 'rstb_val' is not constant") => this gate EXPLICITLY
REM     registers the xpm source into the local xpm library (xvlog -sv -work xpm) AND uses -L xpm.
setlocal
set XV=C:\AMDDesignTools\2025.2\Vivado\bin
set ROOT=D:\repo\XCKU5PMini\udp_hls_10g
set PY=C:\Users\zhxue\anaconda3\python.exe
set XPM=%XV%\..\data\ip\xpm\xpm_memory\hdl\xpm_memory.sv
set VAR=%1
if "%VAR%"=="" set VAR=real
set DUT=%ROOT%\rtl\mir_uram_fifo.v
set TB=%ROOT%\sim\p9_uram\tb_mir_uram_fifo.v
cd /d %~dp0
set RDEF=
set EXPECT=PASS
if /i "%VAR%"=="real" goto arm_ok
if /i "%VAR%"=="guard_rogue" ( set EXPECT=ROGUE & set RDEF=-d URAM_TB_ROGUE & goto arm_ok )
if /i "%VAR%"=="mut_guard_off" ( set EXPECT=MUTROGUE & set RDEF=-d URAM_TB_ROGUE & goto arm_gen )
set EXPECT=MUT
:arm_gen
%PY% "%~dp0mut_uram.py" --arm %VAR% --repo "%ROOT%" > mut_%VAR%_gen.txt 2>&1
type mut_%VAR%_gen.txt
findstr /C:"MUT_URAM_OK" mut_%VAR%_gen.txt >NUL || (echo MUT-URAM-GENFAIL & exit /b 1)
set DUT=%ROOT%\sim\p9_uram\mut\mir_uram_fifo_%VAR%.v
:arm_ok
if not exist xdir_%VAR% mkdir xdir_%VAR%
cd xdir_%VAR%
if exist xsim.dir rmdir /s /q xsim.dir
call %XV%\xvlog.bat -sv -work xpm "%XPM%" > xvlog_xpm.log 2>&1 || (type xvlog_xpm.log & exit /b 1)
call %XV%\xvlog.bat %RDEF% -work xil_defaultlib "%DUT%" "%TB%" > xvlog_out.log 2>&1 || (type xvlog_out.log & exit /b 1)
call %XV%\xvlog.bat %RDEF% -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" >> xvlog_out.log 2>&1 || (type xvlog_out.log & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xvlog_out.log >NUL && (echo IMPLICIT-DECL-FAIL & type xvlog_out.log & exit /b 1)
findstr /C:"10-3091" xvlog_out.log >NUL && (echo BITWIDTH-MISMATCH-FAIL & type xvlog_out.log & exit /b 1)
findstr /I /C:"ERROR" xvlog_out.log >NUL && (echo XVLOG-ERROR-FAIL & findstr /I /C:"ERROR" xvlog_out.log & exit /b 1)
call %XV%\xelab.bat -debug typical -L unisims_ver -L xpm xil_defaultlib.tb_mir_uram_fifo xil_defaultlib.glbl -s tb_mir_uram_fifo -log xelab.log > NUL 2>&1 || (type xelab.log & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" xelab.log >NUL && (echo IMPLICIT-DECL-FAIL-XELAB & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" xelab.log & exit /b 1)
> xsim.log echo ERROR: [XSIM 43-3322] Fatal run-time error inside the simulation kernel
findstr /C:"URAM_FIFO_GATE" xsim.log
findstr /C:"TIMEOUT" xsim.log >NUL && (echo URAM-GATE-TIMEOUT & exit /b 1)
if "%EXPECT%"=="ROGUE"    goto rogue_arm
if "%EXPECT%"=="MUTROGUE" goto mutrogue_arm
findstr /C:"PASS_ALL" xsim.log >NUL
set RC=%ERRORLEVEL%
if "%EXPECT%"=="MUT" goto mut_arm
REM ---- real arm ----
REM an RTL structural FATAL is a hard failure (silent-loss class must not pass)
findstr /C:"FATAL mir_uram_fifo" xsim.log >NUL && (echo URAM-FIFO-FATAL & findstr /C:"FATAL mir_uram_fifo" xsim.log & exit /b 1)
REM F5 guard: every [PASS]/[FAIL] line must carry a visible criterion ID ("] G...")
REM   (implemented in a tiny python file -- the `for /f ('... ^| ...')` pipe idiom HUNG
REM    in an observed run of this very gate: find.exe sat waiting on the console)
%PY% "%~dp0namecheck.py" xsim.log || (echo URAM-GATE-NAME-CHECK-FAIL & exit /b 1)
if %RC%==0 (echo URAM-GATE-VERDICT: PASS-as-expected & exit /b 0)
echo URAM-GATE-VERDICT: FAIL-UNEXPECTED
findstr /C:"[FAIL]" xsim.log
exit /b 1
:mut_arm
REM mutant arm (F1 hardened): "caught" requires HARD evidence, see header note.
findstr /C:"URAM_FIFO_GATE" xsim.log >NUL || (echo URAM-GATE-INFRA-FAIL: no URAM_FIFO_GATE verdict line & exit /b 1)
findstr /C:"PASS_ALL" xsim.log >NUL && (echo URAM-GATE-VERDICT: MUTANT-NOT-CAUGHT & findstr /C:"[FAIL]" xsim.log & exit /b 1)
findstr /C:"[FAIL]" xsim.log >NUL && (echo URAM-GATE-VERDICT: MUTANT-CAUGHT-as-expected & findstr /C:"[FAIL]" xsim.log & exit /b 0)
findstr /C:"FATAL mir_uram_fifo" xsim.log >NUL && (echo URAM-GATE-VERDICT: MUTANT-CAUGHT-as-expected-guardstring & findstr /C:"FATAL mir_uram_fifo" xsim.log & exit /b 0)
echo URAM-GATE-INFRA-FAIL: verdict line seen but no FAIL/FATAL signature
type xsim.log
exit /b 1
:rogue_arm
REM guard-teeth positive arm: TB violates the aux contract (up_gnt w/o up_req) => RTL guard must fire.
findstr /C:"URAM_FIFO_GATE" xsim.log >NUL || (echo URAM-GATE-INFRA-FAIL: no URAM_FIFO_GATE verdict line & exit /b 1)
findstr /C:"FATAL mir_uram_fifo: upstream grant without req" xsim.log >NUL || (echo URAM-GUARD-VERDICT: GUARD-NOT-FIRED & exit /b 1)
echo URAM-GUARD-VERDICT: GUARD-FIRED-as-expected
exit /b 0
:mutrogue_arm
REM guard-teeth control arm: guard $display removed => same scenario must be BLIND to the string.
findstr /C:"URAM_FIFO_GATE" xsim.log >NUL || (echo URAM-GATE-INFRA-FAIL: no URAM_FIFO_GATE verdict line & exit /b 1)
findstr /C:"FATAL mir_uram_fifo: upstream grant without req" xsim.log >NUL && (echo URAM-GUARD-VERDICT: MUTANT-GUARD-NOT-CAUGHT & exit /b 1)
echo URAM-GUARD-VERDICT: GUARD-BLIND-CAUGHT-as-expected
exit /b 0
