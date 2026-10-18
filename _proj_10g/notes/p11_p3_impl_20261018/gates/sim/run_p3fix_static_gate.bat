@echo off
REM P3 fix static wiring gate (H-2 / M-9 / M-10).
setlocal
cd /d %~dp0
call "%~dp0..\..\..\..\..\sim\p4gates\p4env.bat" || exit /b 1
set "ROOT=%REPO_ROOT%"
set "WARG="
if not "%~1"=="" set "WARG=--wrapper %~1"
"%PY%" "%~dp0check_p3fix_static.py" --root "%ROOT%" %WARG% || exit /b 1
exit /b 0
