@echo off
REM G-P3-1b 负控: 四个 app_ctrl 释放路径变异件必须让 churn 门变红.
setlocal
cd /d %~dp0
call "%~dp0..\..\..\..\..\sim\p4gates\p4env.bat" || exit /b 1
"%PY%" "%~dp0mk_mut_churn.py" || exit /b 1
set "BAD=0"
for %%M in (noevd noto nost dup) do (
  call "%~dp0run_tb_p3_churn.bat" "%~dp0mut\app_ctrl_%%M.v" > "%~dp0negctl_churn_%%M.log" 2>&1
  if errorlevel 1 (
    echo [NEGCTL OK] mutant %%M rejected
  ) else (
    echo [NEGCTL FAIL] mutant %%M was ACCEPTED ^(gate stayed green^)
    set "BAD=1"
  )
)
if "%BAD%"=="1" exit /b 1
echo CHURN_NEGCTL_PASS
exit /b 0
