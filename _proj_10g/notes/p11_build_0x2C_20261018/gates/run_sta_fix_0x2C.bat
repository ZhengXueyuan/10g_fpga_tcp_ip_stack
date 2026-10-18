@echo off
setlocal
cd /d %~dp0
"C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat" -mode batch -source "%~dp0sta_directed_fix_0x2C.tcl" -nojournal -nolog > "%~dp0STA_FIX_CONSOLE_0x2C.txt" 2>&1
echo STA_FIX_EXIT=%ERRORLEVEL%
exit /b 0
