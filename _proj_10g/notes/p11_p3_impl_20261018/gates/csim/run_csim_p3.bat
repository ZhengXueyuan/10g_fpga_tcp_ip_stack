@echo off
REM P11 P3 G-P3-5: HLS csim (MSVC). Usage: run_csim_p3.bat <MAX> <DUAL> <FIN>
REM   MAX  = MAX_TCP_CONN (3 = legacy, 8 = P3)
REM   DUAL = BOARD_IP_DUAL (0/1)
REM   FIN  = P11_FIN_FIX (0 = LEGACY arm, 1 = FIX arm; default 0)
REM P11 R2 (2026-11-06): FIN selects the zero-data-FIN arm at compile time.
REM   -DTCP_STATE_PROBE enables tcp_state_probe() for the T_FREE/T_ESTABLISHED
REM   /T_LAST_ACK assertions (csim-only hook; not part of any HLS build).
REM NOTE: keep ")" out of echoed text inside parenthesized blocks (cmd closes
REM   the block at the first ")" and the following lines then run unconditionally).
setlocal
set HERE=%~dp0
set REPO=%~dp0..\..\..\..\..\
pushd "%REPO%"
set VCV="C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat"
set HLSINC=C:\AMDDesignTools\2025.2\Vitis\include
if not defined PY set "PY=C:\Users\zhxue\anaconda3\python.exe"
set MAX=%1
if "%MAX%"=="" set MAX=8
set DUAL=%2
if "%DUAL%"=="" set DUAL=1
set FIN=%3
if "%FIN%"=="" set FIN=0
if "%FIN%"=="1" (set ARMTAG=FIX) else (set ARMTAG=LEGACY)
call %VCV% >nul 2>&1
cl /nologo /EHsc /std:c++14 /O2 /utf-8 /DMAX_TCP_CONN=%MAX% /DBOARD_IP_DUAL=%DUAL% /DP11_FIN_FIX=%FIN% /DTCP_STATE_PROBE ^
   /I"%HLSINC%" /Ihls\src /Ihls\tb ^
   hls\tb\udp_echo_tb.cpp hls\src\udp_echo.cpp /Fe:"%HERE%csim_max%MAX%_dual%DUAL%_fin%FIN%.exe" /Fo%HERE%obj\ > "%HERE%cl_max%MAX%_dual%DUAL%_fin%FIN%.log" 2>&1
if errorlevel 1 goto csim_build_fail
"%HERE%csim_max%MAX%_dual%DUAL%_fin%FIN%.exe" > "%HERE%out_max%MAX%_dual%DUAL%_fin%FIN%.txt" 2>&1
set RC=%ERRORLEVEL%
echo [CSIM %MAX%/%DUAL%/%ARMTAG%] RC=%RC% (expected 1: 3 baseline XFAILs)
REM Arm identity: the TB must have been compiled with the requested -D.
findstr /C:"P11_FIN_ARM=%ARMTAG%" "%HERE%out_max%MAX%_dual%DUAL%_fin%FIN%.txt" >nul
if errorlevel 1 goto csim_armid_fail
findstr /C:"P11_FIN_ARM=%ARMTAG%" "%HERE%out_max%MAX%_dual%DUAL%_fin%FIN%.txt"
findstr /C:"P11_TB_ZDFIN " "%HERE%out_max%MAX%_dual%DUAL%_fin%FIN%.txt"
findstr /C:"P11_SUMMARY" "%HERE%out_max%MAX%_dual%DUAL%_fin%FIN%.txt"
findstr /C:"FAIL:" "%HERE%out_max%MAX%_dual%DUAL%_fin%FIN%.txt"
REM M-2: criterion = FAIL set == 3 P2 baseline XFAILs (unexpected => nonzero).
"%PY%" "%HERE%check_csim.py" --out "%HERE%out_max%MAX%_dual%DUAL%_fin%FIN%.txt"
set CK=%ERRORLEVEL%
popd
exit /b %CK%

:csim_build_fail
echo [CSIM BUILD FAIL] see cl_max%MAX%_dual%DUAL%_fin%FIN%.log
type "%HERE%cl_max%MAX%_dual%DUAL%_fin%FIN%.log"
popd
exit /b 1

:csim_armid_fail
echo [CSIM ARM ID FAIL] expected P11_FIN_ARM=%ARMTAG% -- missing -DP11_FIN_FIX?
popd
exit /b 1
