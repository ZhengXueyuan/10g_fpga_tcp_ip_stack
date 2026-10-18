@echo off
setlocal
cd /d %~dp0
"C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat" -mode batch -source "%~dp0sta_fanout_probe_0x2C.tcl" -nojournal -nolog > "%~dp0FANOUT_PROBE_CONSOLE_0x2C.txt" 2>&1
echo FANOUT_PROBE_EXIT=%ERRORLEVEL%
exit /b 0
