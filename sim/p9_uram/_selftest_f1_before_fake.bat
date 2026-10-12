@echo off
REM run_tb_mir_uram_fifo.bat -- P9 URAM board-buffer unit gate (+ 7 mutation arms)
REM   unit gate for the URAM buffer between the mirror aux port and axis_c2h_stream
REM   usage: run_tb_mir_uram_fifo.bat [real|mut_full_off|mut_full_e1|mut_issue_free|mut_val1|mut_clr_off|mut_clr_take|mut_dnreq]
REM     real   : compile rtl\mir_uram_fifo.v                    -> expect PASS_ALL
REM     mut_*  : compile a single-point mutant from mut_uram.py -> expect NOT PASS_ALL
REM   exit 0 only when the observed verdict matches the arm expectation
REM   (a mutant that PASSES = gate with no teeth => hard failure, project trap #18).
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
set EXPECT=PASS
if /i not "%VAR%"=="real" (
  set EXPECT=MUT
  %PY% "%~dp0mut_uram.py" --arm %VAR% --repo "%ROOT%" > mut_%VAR%_gen.txt 2>&1
  type mut_%VAR%_gen.txt
  findstr /C:"MUT_URAM_OK" mut_%VAR%_gen.txt >NUL || (echo MUT-URAM-GENFAIL & exit /b 1)
  set DUT=%ROOT%\sim\p9_uram\mut\mir_uram_fifo_%VAR%.v
)
if not exist xdir_%VAR% mkdir xdir_%VAR%
cd xdir_%VAR%
if exist xsim.dir rmdir /s /q xsim.dir
call %XV%\xvlog.bat -sv -work xpm "%XPM%" > xvlog_xpm.log 2>&1 || (type xvlog_xpm.log & exit /b 1)
call %XV%\xvlog.bat -work xil_defaultlib "%DUT%" "%TB%" > xvlog_out.log 2>&1 || (type xvlog_out.log & exit /b 1)
call %XV%\xvlog.bat -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" >> xvlog_out.log 2>&1 || (type xvlog_out.log & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xvlog_out.log >NUL && (echo IMPLICIT-DECL-FAIL & type xvlog_out.log & exit /b 1)
findstr /C:"10-3091" xvlog_out.log >NUL && (echo BITWIDTH-MISMATCH-FAIL & type xvlog_out.log & exit /b 1)
findstr /I /C:"ERROR" xvlog_out.log >NUL && (echo XVLOG-ERROR-FAIL & findstr /I /C:"ERROR" xvlog_out.log & exit /b 1)
call %XV%\xelab.bat -debug typical -L unisims_ver -L xpm xil_defaultlib.tb_mir_uram_fifo xil_defaultlib.glbl -s tb_mir_uram_fifo -log xelab.log > NUL 2>&1 || (type xelab.log & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" xelab.log >NUL && (echo IMPLICIT-DECL-FAIL-XELAB & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" xelab.log & exit /b 1)
> xsim.log echo ERROR: [XSIM 43-3322] Fatal run-time error inside the simulation kernel
findstr /C:"URAM_FIFO_GATE" xsim.log
findstr /C:"TIMEOUT" xsim.log >NUL && (echo URAM-GATE-TIMEOUT & exit /b 1)
findstr /C:"PASS_ALL" xsim.log >NUL
set RC=%ERRORLEVEL%
if "%EXPECT%"=="MUT" goto mut_arm
REM real arm: an RTL structural FATAL is a hard failure (silent-loss class must not pass)
findstr /C:"FATAL mir_uram_fifo" xsim.log >NUL && (echo URAM-FIFO-FATAL & findstr /C:"FATAL mir_uram_fifo" xsim.log & exit /b 1)
if %RC%==0 (echo URAM-GATE-VERDICT: PASS-as-expected & exit /b 0)
echo URAM-GATE-VERDICT: FAIL-UNEXPECTED
findstr /C:"[FAIL]" xsim.log
exit /b 1
:mut_arm
REM mutant arm: anything other than PASS_ALL (incl. the RTL FATAL path) counts as caught
findstr /C:"FATAL mir_uram_fifo" xsim.log >NUL && (echo URAM-FIFO-FATAL & goto mut_caught)
if %RC%==0 (echo URAM-GATE-VERDICT: MUTANT-NOT-CAUGHT & findstr /C:"[FAIL]" xsim.log & exit /b 1)
:mut_caught
echo URAM-GATE-VERDICT: MUTANT-CAUGHT-as-expected
findstr /C:"[FAIL]" xsim.log
exit /b 0
