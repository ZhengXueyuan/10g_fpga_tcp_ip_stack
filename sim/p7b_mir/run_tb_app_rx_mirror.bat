@echo off
REM run_tb_app_rx_mirror.bat -- M1 payload-mirror unit gate (self-checking TB)
REM   usage: run_tb_app_rx_mirror.bat [real|mut_gate|mut_order|mut_cap4|mut_admit14|mut_apos0|mut_dropcnt|mut_keep1]
REM     real        : compile rtl\app_rx_mirror.v                    -> expect PASS_ALL
REM     mut_gate    : wr_en drops the space gate `!fifo_full`  -> MUST be caught (byte-account identity G11c/G8g)
REM     mut_order   : 2-byte mv branch b0/b1 swapped            -> MUST be caught (hand anchors G3c/G4c/G5c)
REM     mut_cap4    : kk capped at 4 (4B/beat structural cap)    -> MUST be caught (G13/G15 dense 8B/beat)
REM     mut_admit14 : admit CAP 16 -> 14                        -> MUST be caught (G18 trajectory / G16(1477) / G8e)
REM     mut_apos0   : keep=0 append position rotated            -> MUST be caught (G13/G15/G17 golden)
REM     mut_dropcnt : drop accounting bypassed                  -> MUST be caught (G8b/G19a2/G19b4 identity)
REM     mut_keep1   : keep count +1 (staging bookkeeping)       -> MUST be caught (identity + G20)
REM   Mutants are (re)generated from the LIVE rtl by mut\make_mutants.py (single-point + hit-count check).
REM   exit 0 only when the observed verdict matches the arm's expectation
REM   (a mutant that PASSES is a gate with no teeth => hard failure, project trap #18).
REM   Each arm runs in its OWN dir (project trap 7: shared xsim.dir => false failures).
setlocal
set XV=C:\AMDDesignTools\2025.2\Vivado\bin
set ROOT=D:\repo\XCKU5PMini\udp_hls_10g
set PY=C:\Users\zhxue\anaconda3\python.exe
set VAR=%1
if "%VAR%"=="" set VAR=real
set DUT=%ROOT%\rtl\app_rx_mirror.v
set EXPECT=PASS
if /i not "%VAR%"=="real" (
  set EXPECT=MUT
  %PY% "%~dp0mut\make_mutants.py" --repo "%ROOT%" > mut_gen.txt 2>&1
  type mut_gen.txt
  findstr /C:"MUT_ALL_OK" mut_gen.txt >NUL || (echo MUT-GENFAIL & exit /b 1)
  set DUT=%ROOT%\sim\p7b_mir\mut\app_rx_mirror_%VAR%.v
)
cd /d %~dp0
if not exist xdir_%VAR% mkdir xdir_%VAR%
cd xdir_%VAR%
if exist xsim.dir rmdir /s /q xsim.dir
call %XV%\xvlog.bat -work xil_defaultlib "%DUT%" %ROOT%\rtl\fifo_async.v %ROOT%\tb\tb_app_rx_mirror.v > xvlog_out.log 2>&1 || (type xvlog_out.log & exit /b 1)
call %XV%\xvlog.bat -work xil_defaultlib "%XV%\..\data\verilog\src\glbl.v" >> xvlog_out.log 2>&1 || (type xvlog_out.log & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" /C:"implicitly declared" xvlog_out.log >NUL && (echo IMPLICIT-DECL-FAIL & type xvlog_out.log & exit /b 1)
findstr /C:"10-3091" xvlog_out.log >NUL && (echo BITWIDTH-MISMATCH-FAIL & type xvlog_out.log & exit /b 1)
findstr /I /C:"ERROR" xvlog_out.log >NUL && (echo XVLOG-ERROR-FAIL & findstr /I /C:"ERROR" xvlog_out.log & exit /b 1)
call %XV%\xelab.bat -debug typical -L unisims_ver xil_defaultlib.tb_app_rx_mirror xil_defaultlib.glbl -s tb_app_rx_mirror -log xelab.log > NUL 2>&1 || (type xelab.log & exit /b 1)
findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" xelab.log >NUL && (echo IMPLICIT-DECL-FAIL-XELAB & findstr /I /C:"Synth 8-11241" /C:"undeclared symbol" /C:"VRFC 10-3091] actual bit length 1 differs from formal bit length" /C:"VRFC 10-2989" xelab.log & exit /b 1)
call %XV%\xsim.bat tb_app_rx_mirror -runall -log xsim.log > NUL 2>&1
findstr /C:"APP_RX_MIRROR_GATE" xsim.log
findstr /C:"TIMEOUT" xsim.log >NUL && (echo MIRROR-GATE-TIMEOUT & findstr /C:"INFO" xsim.log & exit /b 1)
findstr /C:"PASS_ALL" xsim.log >NUL
set RC=%ERRORLEVEL%
if "%EXPECT%"=="MUT" goto mut_arm
if %RC%==0 (echo MIRROR-GATE-VERDICT: PASS-as-expected & exit /b 0)
echo MIRROR-GATE-VERDICT: FAIL-UNEXPECTED
findstr /C:"[FAIL]" xsim.log
exit /b 1
:mut_arm
if %RC%==0 (echo MIRROR-GATE-VERDICT: MUTANT-NOT-CAUGHT & findstr /C:"[FAIL]" xsim.log & exit /b 1)
echo MIRROR-GATE-VERDICT: MUTANT-CAUGHT-as-expected
findstr /C:"[FAIL]" xsim.log
exit /b 0
