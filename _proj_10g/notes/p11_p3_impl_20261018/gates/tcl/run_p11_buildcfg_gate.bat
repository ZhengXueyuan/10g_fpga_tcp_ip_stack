@echo off
REM H-4/M-14 gate: build config / HLS netlist pairing (+ negative controls).
setlocal
cd /d %~dp0
set "VIV=C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat"
if not exist "%VIV%" (
  echo P11_BUILDCFG_GATE FAIL vivado-not-found
  exit /b 1
)
call "%VIV%" -mode batch -source "%~dp0run_p11_buildcfg_gate.tcl" -nojournal -nolog > "%~dp0p11_buildcfg_gate.log" 2>&1
findstr /C:"P11_BUILDCFG_GATE PASS" "%~dp0p11_buildcfg_gate.log" >nul || (type "%~dp0p11_buildcfg_gate.log" & exit /b 1)
findstr /C:"P11_BUILDCFG_GATE PASS" "%~dp0p11_buildcfg_gate.log"
exit /b 0
