@echo off
REM run_tb_axis_c2h_stream.bat -- P9 unit gate: axis_c2h_stream (+ 12 mutation arms; D4-fix round)
REM   usage: run_tb_axis_c2h_stream.bat [real|mut_last|mut_keep|mut_order|mut_req|mut_cnt|mut_clr|mut_stop|mut_drain|mut_tlast|mut_quiet|mut_clrdrop|mut_qrst]
REM     real   : compile rtl\axis_c2h_stream.v                   -> expect PASS_ALL
REM     mut_*  : compile a single-point mutant from mut_axis.py  -> expect NOT PASS_ALL
REM   exit 0 only when the observed verdict matches the arm expectation
REM   (a mutant that PASSES = gate with no teeth => hard failure, project trap #18).
REM   Each arm runs in its OWN dir (trap 7: shared xsim.dir => false failures).
setlocal
set XV=C:\AMDDesignTools\2025.2\Vivado\bin
set ROOT=D:\repo\XCKU5PMini\udp_hls_10g
set PY=C:\Users\zhxue\anaconda3\python.exe
set VAR=%1
if "%VAR%"=="" set VAR=real
set AXIS=%ROOT%\rtl\axis_c2h_stream.v
set TB=%ROOT%\sim\p9_axis_stream\tb_axis_c2h_stream.v
cd /d %~dp0
set EXPECT=PASS
if /i not "%VAR%"=="real" (
  set EXPECT=MUT
  %PY% "%~dp0mut_axis.py" --arm %VAR% --repo "%ROOT%" > mut_%VAR%_gen.txt 2>&1
  type mut_%VAR%_gen.txt
  findstr /C:"MUT_AXIS_OK" mut_%VAR%_gen.txt >NUL || (echo MUT-AXIS-GENFAIL & exit /b 1)
  set AXIS=%ROOT%\sim\p9_axis_stream\mut\axis_c2h_stream_%VAR%.v
)
if not exist xdir_%VAR% mkdir xdir_%VAR%
cd xdir_%VAR%
if exist xsim.dir rmdir /s /q xsim.dir
call %XV%\xvlog.bat -work xil_defaultlib "%AXIS%" "%TB%" > xvlog_out.log 2>&1 || (type xvlog_out.log & exit /b 1)
call %XV%\xvlog.bat -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" >> xvlog_out.log 2>&1 || (type xvlog_out.log & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xvlog_out.log >NUL && (echo IMPLICIT-DECL-FAIL & type xvlog_out.log & exit /b 1)
findstr /C:"10-3091" xvlog_out.log >NUL && (echo BITWIDTH-MISMATCH-FAIL & type xvlog_out.log & exit /b 1)
findstr /I /C:"ERROR" xvlog_out.log >NUL && (echo XVLOG-ERROR-FAIL & findstr /I /C:"ERROR" xvlog_out.log & exit /b 1)
call %XV%\xelab.bat -debug typical -L unisims_ver xil_defaultlib.tb_axis_c2h_stream xil_defaultlib.glbl -s tb_axis_c2h_stream -log xelab.log > NUL 2>&1 || (type xelab.log & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" xelab.log >NUL && (echo IMPLICIT-DECL-FAIL-XELAB & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" xelab.log & exit /b 1)
call %XV%\xsim.bat tb_axis_c2h_stream -runall -log xsim.log > NUL 2>&1
findstr /C:"AXIS_C2H_STREAM_GATE" xsim.log
findstr /C:"TIMEOUT" xsim.log >NUL && (echo AXIS-GATE-TIMEOUT & findstr /C:"INFO" xsim.log & exit /b 1)
findstr /C:"PASS_ALL" xsim.log >NUL
set RC=%ERRORLEVEL%
if "%EXPECT%"=="MUT" goto mut_arm
if %RC%==0 (echo AXIS-GATE-VERDICT: PASS-as-expected & exit /b 0)
echo AXIS-GATE-VERDICT: FAIL-UNEXPECTED
findstr /C:"[FAIL]" xsim.log
exit /b 1
:mut_arm
if %RC%==0 (echo AXIS-GATE-VERDICT: MUTANT-NOT-CAUGHT & findstr /C:"[FAIL]" xsim.log & exit /b 1)
echo AXIS-GATE-VERDICT: MUTANT-CAUGHT-as-expected
findstr /C:"[FAIL]" xsim.log
exit /b 0
