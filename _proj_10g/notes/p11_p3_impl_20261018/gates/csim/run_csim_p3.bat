@echo off
REM P11 P3 G-P3-5: HLS csim (MSVC). Usage: run_csim_p3.bat <MAX> <DUAL>
REM   MAX  = MAX_TCP_CONN (3 = legacy, 8 = P3)
REM   DUAL = BOARD_IP_DUAL (0/1)
setlocal
set HERE=%~dp0
set REPO=%~dp0..\..\..\..\..\
pushd "%REPO%"
set VCV="C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat"
set HLSINC=C:\AMDDesignTools\2025.2\Vitis\include
set MAX=%1
if "%MAX%"=="" set MAX=8
set DUAL=%2
if "%DUAL%"=="" set DUAL=1
call %VCV% >nul 2>&1
cl /nologo /EHsc /std:c++14 /O2 /utf-8 /DMAX_TCP_CONN=%MAX% /DBOARD_IP_DUAL=%DUAL% ^
   /I"%HLSINC%" /Ihls\src /Ihls\tb ^
   hls\tb\udp_echo_tb.cpp hls\src\udp_echo.cpp /Fe:"%HERE%csim_max%MAX%_dual%DUAL%.exe" /Fo%HERE%obj\ > "%HERE%cl_max%MAX%_dual%DUAL%.log" 2>&1
if errorlevel 1 (
  echo [CSIM BUILD FAIL] see cl_max%MAX%_dual%DUAL%.log
  type "%HERE%cl_max%MAX%_dual%DUAL%.log"
  popd
  exit /b 1
)
"%HERE%csim_max%MAX%_dual%DUAL%.exe" > "%HERE%out_max%MAX%_dual%DUAL%.txt" 2>&1
set RC=%ERRORLEVEL%
echo [CSIM %MAX%/%DUAL%] RC=%RC%
findstr /C:"P11_SUMMARY" "%HERE%out_max%MAX%_dual%DUAL%.txt"
findstr /C:"FAIL:" "%HERE%out_max%MAX%_dual%DUAL%.txt"
popd
exit /b %RC%
