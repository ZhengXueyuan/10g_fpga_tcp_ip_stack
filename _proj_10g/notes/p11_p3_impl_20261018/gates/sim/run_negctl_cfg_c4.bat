@echo off
REM G-P3-7 负控: 四配置选择/冲突硬门 (每次一个错误组合).
setlocal
cd /d %~dp0
set "BASE=-d P7B_10G -d P7B_SIM_NOPCS -d DEV_USP -d APP_MODE -d DP_156MHZ -d P6B_SIM_CLKGEN -d UDP_TX_OVL -d TCP_TX_OVL"
set "BAD=0"
call :run "0-select" "%BASE% -d P11_CFG_ENFORCE" "P11_CFG_SELECT_ONE"
call :run "C1+DUAL"  "%BASE% -d P11_CFG_C1 -d DUAL_SFP_A -d SFP2_MODE_A" "P11_CFG_C1_CONFLICTS_SECOND_PORT"
call :run "C2-noB"   "%BASE% -d P11_CFG_C2" "P11_CFG_C2_REQUIRES_MODE_B"
call :run "C2+DUAL"  "%BASE% -d P11_CFG_C2 -d DUAL_SFP_A" "P11_CFG_C2_CONFLICTS_DUAL_SFP_A"
call :run "C3-noDual" "%BASE% -d P11_CFG_C3 -d SFP2_MODE_A" "P11_CFG_C3_REQUIRES_MODE_A_DUAL"
call :run "C4-noP11" "%BASE% -d P11_CFG_C4 -d DUAL_SFP_A -d SFP2_MODE_A" "P11_CFG_C4_REQUIRES_DUAL_SFP_A"
REM C4+ModeB: C4 ∧ P11_DUAL ∧ MODE_B 必然也带 DUAL_SFP_A => 既有 DUAL+MODE_B
REM 门在 xvlog 先硬失败 (更宽的同义门); 负控期望该**预占**签名.
call :run "C4+ModeB" "%BASE% -d P11_CFG_C4 -d DUAL_SFP_A -d SFP2_MODE_B -d P11_DUAL" "DUAL_SFP_A_AND_SFP2_MODE_B_CONFLICT"
call :run "C3+C4"    "%BASE% -d P11_CFG_C3 -d P11_CFG_C4 -d P11_CFG_ENFORCE -d DUAL_SFP_A -d SFP2_MODE_A -d P11_DUAL" "P11_CFG_SELECT_ONE"
call :run "P11+ModeB" "%BASE% -d P11_DUAL -d SFP2_MODE_B" "P11_DUAL_AND_SFP2_MODE_B_CONFLICT"
if "%BAD%"=="1" exit /b 1
echo CFG_NEGCTL_PASS
exit /b 0

:run
call "%~dp0run_cfg_gate_c4.bat" "%~2" "%~3" > "%~dp0cfggate_%~1.log" 2>&1
if errorlevel 1 (
  echo [CFG NEGCTL FAIL] %~1
  set "BAD=1"
) else (
  echo [CFG NEGCTL OK] %~1 rejected by %~3
)
exit /b 0
