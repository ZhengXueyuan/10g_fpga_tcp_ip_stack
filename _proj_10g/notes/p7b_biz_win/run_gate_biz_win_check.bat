@echo off
REM ===========================================================================
REM run_gate_biz_win_check.bat -- P4 matrix gate #21 (P11/P1 fix round, 2026-10-18)
REM
REM   Two complementary halves of the snapshot-window verification layer, which
REM   were BOTH outside every standing gate before this round (FINDINGS high-1):
REM     A. check_window.py -- static assembly check of wrapper_p4.v's
REM        `snap_dout_all` (item count / bundle width equation / slot mapping /
REM        frozen-anchor "old words did not move" / declared-before-use).
REM        Runs 1 positive (expected RC=0 / CHECK_WINDOW_PASS) and 3 mutation
REM        negative controls (--mutate drop|swap|declpatho; each MUST return
REM        RC=1, otherwise this gate fails = the checker lost its teeth).
REM     B. run_tb_biz_win.bat -- axi_regs unit gate: per-word "address <-> word"
REM        readback (tb_biz_win.v, NW = SNAP_NW_P6E = 83; PASS_ALL expected).
REM
REM   Scope note: this gate does NOT compile the wrapper. Its compile set is the
REM   axi_regs + tb_biz_win pair listed below (executed by run_tb_biz_win.bat);
REM   the manifest sim\p4gates\bizwinsrc.f declares exactly that pair, and the
REM   literal xvlog row below lets p4gate.py manifestcheck see it.
REM   All comments are ASCII on purpose (project rule for .bat files).
REM ===========================================================================
setlocal EnableDelayedExpansion
call "%~dp0..\..\..\sim\p4gates\p4env.bat" || exit /b 1
set "ROOT=%REPO_ROOT%"
if not "%P4_WORKDIR%"=="" (cd /d "%P4_WORKDIR%") else (cd /d %~dp0)

REM ---- compile set (executed inside run_tb_biz_win.bat) ----------------------
set "RTL=%REPO_ROOT%\_proj_pcie\rtl\axi_regs.v"
set "TB=%REPO_ROOT%\_proj_10g\notes\p7b_biz_win\tb_biz_win.v"
REM xvlog.bat "%RTL%" "%TB%"
if not exist "%RTL%" (echo [PATHGUARD FAIL] no axi_regs.v & exit /b 90)
if not exist "%TB%"  (echo [PATHGUARD FAIL] no tb_biz_win.v & exit /b 90)

set "RC=0"

REM ---- A. check_window.py positive run --------------------------------------
echo === A. check_window.py (static assembly, positive) ===
"%PY%" "%~dp0check_window.py" --repo "%ROOT%" > cw_pos.log 2>&1
set "CWRC=%ERRORLEVEL%"
type cw_pos.log
if not "%CWRC%"=="0" (echo [CHECK_WINDOW POSITIVE FAIL] RC=%CWRC% & set "RC=1")
findstr /C:"CHECK_WINDOW_PASS" cw_pos.log >NUL || (echo [CHECK_WINDOW POSITIVE FAIL] no CHECK_WINDOW_PASS & set "RC=1")

REM ---- A'. three mutation negative controls (each MUST be red) --------------
REM   NOTE: no literal parentheses in echo text inside this block -- cmd would
REM   treat the first ')' as the end of the FOR body (measured: it silently
REM   truncated the loop and printed '%M' literally).
for %%M in (drop swap declpatho) do (
  echo === A'. check_window.py --mutate %%M : negative control, expect RC=1 ===
  "%PY%" "%~dp0check_window.py" --repo "%ROOT%" --mutate %%M > cw_neg_%%M.log 2>&1
  set "NRC=!ERRORLEVEL!"
  if "!NRC!"=="0" (echo [NEGCTL FAIL] --mutate %%M returned RC=0 -- checker lost its teeth & set "RC=1") else (echo [NEGCTL OK] --mutate %%M RC=!NRC!)
  findstr /C:"FAILED:" cw_neg_%%M.log >NUL || (echo [NEGCTL FAIL] --mutate %%M produced no FAILED: line & set "RC=1")
)

REM ---- B. tb_biz_win unit gate ----------------------------------------------
echo === B. run_tb_biz_win.bat (axi_regs address <-> word readback) ===
call "%~dp0run_tb_biz_win.bat" > tb_biz_win_console.log 2>&1
set "BRC=%ERRORLEVEL%"
type tb_biz_win_console.log
if not "%BRC%"=="0" (echo [TB_BIZ_WIN FAIL] RC=%BRC% & set "RC=1")
findstr /C:"TB_BIZ_WIN_PASS" tb_biz_win_console.log >NUL || (echo [TB_BIZ_WIN FAIL] no TB_BIZ_WIN_PASS & set "RC=1")

if not "%RC%"=="0" (echo BIZ_WIN_CHECK_FAIL & exit /b 1)
echo BIZ_WIN_CHECK_PASS
exit /b 0
