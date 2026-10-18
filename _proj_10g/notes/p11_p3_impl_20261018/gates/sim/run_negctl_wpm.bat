@echo off
REM G-P3-1 负控: 三个变异件必须让单元门变红.
setlocal
cd /d %~dp0
call "%~dp0..\..\..\..\..\sim\p4gates\p4env.bat" || exit /b 1
"%PY%" "%~dp0mk_mut_wpm.py" || exit /b 1
set "BAD=0"
for %%M in (c18 pcap dup) do (
  call "%~dp0run_tb_win_pool_mgr.bat" "%~dp0mut\win_pool_mgr_%%M.v" > "%~dp0negctl_wpm_%%M.log" 2>&1
  if errorlevel 1 (
    echo [NEGCTL OK] mutant %%M rejected
  ) else (
    echo [NEGCTL FAIL] mutant %%M was ACCEPTED ^(gate stayed green^)
    set "BAD=1"
  )
)
if "%BAD%"=="1" exit /b 1
echo WPM_NEGCTL_PASS
exit /b 0
