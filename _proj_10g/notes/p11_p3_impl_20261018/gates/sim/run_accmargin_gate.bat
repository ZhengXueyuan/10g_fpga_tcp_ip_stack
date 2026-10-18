@echo off
REM (non-ascii note removed; see FIX_REPORT)
REM   usage: run_accmargin_gate.bat [wrapper.v]
setlocal
cd /d %~dp0
call "%~dp0..\..\..\..\..\sim\p4gates\p4env.bat" || exit /b 1
set "ROOT=%REPO_ROOT%"
set "W=%ROOT%\board\wrapper_p4.v"
set "TAG=def"
if not "%~1"=="" set "W=%~1"
if not "%~1"=="" set "TAG=mut"
"%PY%" "%~dp0check_accmargin.py" --wrapper "%W%" --tag %TAG% || exit /b 1
exit /b 0
