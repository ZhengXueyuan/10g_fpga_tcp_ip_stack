@echo off
REM ==========================================================================
REM run_orphan_suite.bat -- p9 orphan fix unit gate full suite
REM   U1..U12 (incl U10'/U12b/U9B) must PASS; M1..M14 mutants must FAIL.
REM   Writes a summary and exits 0 only if every arm matched its expectation.
REM ==========================================================================
setlocal EnableDelayedExpansion
set "HERE=%~dp0"
set "PY=C:\Users\zhxue\anaconda3\python.exe"
set "RTL=%~dp0..\..\rtl\app_ctrl.v"
set "MUT=%~dp0mutants"
set "LOG=%~dp0runs\unit_suite.txt"
if not exist "%~dp0runs" mkdir "%~dp0runs"
"%PY%" "%~dp0gen_mutants.py" > "%~dp0runs\gen_mutants_stdout.txt" 2>&1
if errorlevel 1 ( echo SUITE_FAIL gen_mutants & type "%~dp0runs\gen_mutants_stdout.txt" & exit /b 1 )
> "%LOG%" echo ==== p9 orphan unit suite ====
set "NFAIL=0"
call :run "%RTL%" 1  1 0 2 U1    PASS
call :run "%RTL%" 2  1 0 2 U2    PASS
call :run "%RTL%" 3  1 0 2 U3    PASS
call :run "%RTL%" 4  1 0 2 U4    PASS
call :run "%RTL%" 5  1 0 2 U5    PASS
call :run "%RTL%" 6  1 0 2 U5b   PASS
call :run "%RTL%" 7  1 0 2 U6    PASS
call :run "%RTL%" 8  1 0 2 U6b   PASS
call :run "%RTL%" 9  1 0 2 U6c   PASS
call :run "%RTL%" 10 1 0 2 U7    PASS
call :run "%RTL%" 11 1 0 2 U8    PASS
call :run "%RTL%" 12 1 0 2 U9    PASS
call :run "%RTL%" 13 0 0 2 U10   PASS
call :run "%RTL%" 14 1 1 2 U11   PASS
call :run "%RTL%" 15 1 1 2 U12   PASS
call :run "%RTL%" 16 1 1 2 U12b  PASS
call :run "%RTL%" 17 0 0 2 U10P  PASS
call :run "%RTL%" 18 1 0 2 U9B   PASS
REM M1 = ORPHAN_LIM=0 on the pristine RTL (no text patch, see gen_mutants.py)
call :run "%RTL%" 1 1 0 0 M1 FAIL
call :mut "M2"  3  1 0 2 FAIL
call :mut "M3"  5  1 0 2 FAIL
call :mut "M4"  4  1 0 2 FAIL
call :mut "M5"  7  1 0 2 FAIL
call :mut "M6"  2  1 0 2 FAIL
call :mut "M7"  10 1 0 2 FAIL
call :mut "M8"  2  1 0 2 FAIL
call :mut "M9"  18 1 0 2 FAIL
call :mut "M10" 15 1 1 2 FAIL
call :mut "M11" 9  1 0 2 FAIL
call :mut "M12" 8  1 0 2 FAIL
call :mut "M13" 2  1 0 2 FAIL
call :mut "M14" 8  1 0 2 FAIL
echo SUITE_DONE fails=%NFAIL% >> "%LOG%"
type "%LOG%"
if "%NFAIL%"=="0" ( exit /b 0 ) else ( exit /b 1 )

:run
cmd /c "%~dp0run_orphan_unit.bat %~1 %~2 %~3 %~4 %~5 %~6 %~7" > "%~dp0runs\unit_%~6.txt" 2>&1
set "RC=!errorlevel!"
findstr /C:"GATE_RESULT" "%~dp0runs\unit_%~6.txt" >> "%LOG%"
if not "!RC!"=="0" set /a NFAIL+=1
goto :eof

:mut
set "MF=%~dp0mutants\mut_%~1.v"
cmd /c "%~dp0run_orphan_unit.bat %MF% %~2 %~3 %~4 %~5 %~1 %~6" > "%~dp0runs\unit_%~1.txt" 2>&1
set "RC=!errorlevel!"
findstr /C:"GATE_RESULT" "%~dp0runs\unit_%~1.txt" >> "%LOG%"
if not "!RC!"=="0" set /a NFAIL+=1
goto :eof
