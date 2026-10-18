@echo off
setlocal
cd /d %~dp0
"C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat" -mode batch -source "%~dp0sta_cam_probe_0x2C.tcl" -nojournal -nolog > "%~dp0CAM_PROBE_CONSOLE_0x2C.txt" 2>&1
echo CAM_PROBE_EXIT=%ERRORLEVEL%
exit /b 0
