@echo off
REM ==========================================================================
REM sim\p4gates\run_matrix_p4dfix.bat
REM   P4 DEFAULT-BUILD REGRESSION MATRIX -- Windows-side runner.
REM   The gate list is the 'call :gate' rows of this file (declared once); the
REM   count printed in the log is DERIVED from those rows, never typed.
REM
REM   usage:  cmd //c 'sim\p4gates\run_matrix_p4dfix.bat' [/canonical]
REM           cmd //c 'sim\p4gates\run_matrix_p4dfix.bat' /only chain+unit_vlan
REM   NOTE: the /only separator is '+' -- cmd splits ',' and ';' as token
REM   separators, so a comma separated list cannot survive the command line.
REM   From git bash use the shim sim/p4sim/run_matrix_p4dfix.sh (or the '-'
REM   spelling) -- MSYS rewrites a '/switch' into a path-like token
REM   (C:/Program Files/Git/only) before cmd.exe sees it, and any token this
REM   script does not recognize is now REFUSED (exit 97) instead of ignored.
REM   git-bash entry point (unchanged for callers):
REM     bash sim/p4sim/run_matrix_p4dfix.sh          <- self-locating shim
REM
REM   Per gate:
REM     1. every path is resolved from REPO_ROOT, which is derived from this
REM        file's own location (sim\p4gates\p4env.bat) -- no repository path
REM        literal exists anywhere in the chain any more;
REM     2. pre-flight guard: checkpaths (manifest + bat + cwd must be INSIDE
REM        the repo and must exist) + manifestcheck (the declared file list
REM        must equal the list literally present in the gate .bat);
REM     3. run the gate in a PRIVATE cwd (sim\p4gates\work_<stamp>\<gate>) so
REM        xsim.dir locks and stale .memh files cannot cross-contaminate;
REM     4. post-flight guard: scanlog -- every absolute path in this gate's
REM        logs must be inside the repo (a foreign path = FAIL, not silence).
REM
REM   The matrix log header carries a revision fingerprint (path + SHA256 of
REM   the whole compile set, git HEAD, tracked-modified list).  A second
REM   fingerprint is taken at the end; if anything changed while the matrix ran
REM   the runner exits 2 and reports DRIFT -- the per-gate results are then not
REM   bound to any single revision.  /canonical runs the gates in their
REM   historical directories instead (refused while another xsim.exe runs).
REM
REM   exit codes: 0 ok, 1 a gate failed, 2 revision drift, 97 precheck refusal
REM   (97 covers: unrecognized/valueless command-line switch, a gate name the
REM   runner does not declare, and the per-gate path/manifest precheck).
REM ==========================================================================
setlocal EnableDelayedExpansion

REM capture the script name+path BEFORE the arg loop (shift moves %0 as well --
REM after 'shift' %~f0 is the leftover ARGUMENT, not this file: the gate-name
REM check below once read 'bogus' as its own source file because of it)
set "RUNNER_NAME=%~nx0"
set "RUNNER_PATH=%~f0"

call "%~dp0p4env.bat"
if errorlevel 1 exit /b 1

for /f "usebackq eol=# tokens=1,* delims==" %%a in ("%PATHS_TXT%") do (
  if "%%a"=="MATRIX_LOG" set "MATRIX_LOG_NAME=%%b"
)
set "MATRIX_LOG=%OUTDIR%\%MATRIX_LOG_NAME%"
set "FRAME_FIFO=%RTL%\frame_fifo.v"

REM ---- arguments: [/isolated|/canonical] [/only gate1+gate2,...] -----------
REM   An UNRECOGNIZED token is REFUSED (exit 97), never quietly stepped over.
REM   Why: 'run_matrix_p4dfix.bat /only unit_vlan' typed in git bash arrives
REM   here as '"C:/Program Files/Git/only" unit_vlan' (MSYS rewrites the
REM   POSIX-style switch before cmd.exe is even spawned); the old loop shifted
REM   past both tokens without a word and the run went on to execute the FULL
REM   16 gates while its own header said 'gate filter : (none -- all 16)' --
REM   the caller believed one gate had been selected.  Selecting the wrong
REM   gate set is the "empty gate" failure mode in its most expensive form
REM   (25 minutes of matrix, all of it answering a question nobody asked).
REM   Both spellings of every switch stay valid (/only and -only): a token is
REM   only refused when it is neither spelling.
set "MODE=isolated"
set "GATE_ONLY="
set "ONLY_SEEN="
set "BADARG="
:argloop
if "%~1"=="" goto :args_done
if /i "%~1"=="/canonical" (set "MODE=canonical" & shift & goto :argloop)
if /i "%~1"=="-canonical" (set "MODE=canonical" & shift & goto :argloop)
if /i "%~1"=="/isolated"  (set "MODE=isolated"  & shift & goto :argloop)
if /i "%~1"=="-isolated"  (set "MODE=isolated"  & shift & goto :argloop)
if /i "%~1"=="/only"      (set "ONLY_SEEN=1" & set "GATE_ONLY=%~2" & shift & shift & goto :argloop)
if /i "%~1"=="-only"      (set "ONLY_SEEN=1" & set "GATE_ONLY=%~2" & shift & shift & goto :argloop)
set "BADARG=%~1"
goto :args_done
:args_done
if defined BADARG (
  echo [P4GUARD FAIL] unrecognized argument : !BADARG!
  echo   usage : run_matrix_p4dfix.bat [-isolated ^| -canonical] [-only gate1+gate2]
  echo   NOTE  : from git bash a /switch is rewritten by MSYS into a path-like
  echo           token ^(e.g. "C:/Program Files/Git/only"^) before cmd.exe sees
  echo           it -- use the -switch spelling, or the shim
  echo           sim\p4sim\run_matrix_p4dfix.sh
  echo   gate names : the 'call :gate' rows of this file -- see p4gate.py table
  exit /b 97
)
if defined ONLY_SEEN if not defined GATE_ONLY (
  echo [P4GUARD FAIL] [-only] needs a gate list : -only chain+unit_vlan
  exit /b 97
)
REM cmd treats ',' and ';' as token separators, so a comma separated list can
REM never arrive intact: the documented separator is '+'; ',' is normalised.
if defined GATE_ONLY set "GATE_ONLY=%GATE_ONLY:,=+%"
REM   ... and every name in the filter must be a gate THIS file declares (the
REM   names come from the file itself -- the gate list is declared once, so
REM   there is no second list here to drift).  '-only bogus' used to run zero
REM   gates and still exit 0: 'gates run 0 / 16' is not a pass.
if defined GATE_ONLY (
  set "UNKNOWN_GATE="
  for %%T in (%GATE_ONLY:+= %) do (
    findstr /i /b /c:"call :gate %%T " "%RUNNER_PATH%" >nul || set "UNKNOWN_GATE=!UNKNOWN_GATE! %%T"
  )
  if defined UNKNOWN_GATE (
    echo [P4GUARD FAIL] -only names gate^(s^) this runner does not declare :!UNKNOWN_GATE!
    echo   refusing: a filter matching nothing would run 0 gates and still exit 0
    exit /b 97
  )
)

if /i not "%MODE%"=="canonical" goto :mode_done
tasklist /fi "imagename eq xsim.exe" 2>nul | findstr /i "xsim.exe" >nul
if errorlevel 1 goto :mode_done
echo [P4GUARD NOTE] another xsim.exe is running -- /canonical refused, using a private work dir
set "MODE=isolated"

:mode_done
set "ISOLATED="
if /i "%MODE%"=="isolated" set "ISOLATED=1"

"%PY%" "%P4GATE_PY%" stamp > "%OUTDIR%\_p4stamp.txt" 2>nul
set "STAMP="
for /f "usebackq delims=" %%t in ("%OUTDIR%\_p4stamp.txt") do set "STAMP=%%t"
del /q "%OUTDIR%\_p4stamp.txt" >nul 2>&1
if not defined STAMP set "STAMP=nostamp"
set "WORKROOT=%GATES%\work_%STAMP%"
if defined ISOLATED if not exist "%WORKROOT%\" mkdir "%WORKROOT%"
set "FP_BEFORE=%OUTDIR%\P4_MATRIX_FINGERPRINT_%STAMP%_before.txt"
set "FP_AFTER=%OUTDIR%\P4_MATRIX_FINGERPRINT_%STAMP%_after.txt"

set "GATE_FAIL=0"
set "GATE_RUN=0"
set "DRIFT=0"

REM ---- gate count: DERIVED, never typed (no second list to drift) ----------
REM   The count is the number of 'call :gate' rows in THIS file.  It used to be
REM   the literal 16 in the header and the summary -- i.e. a second copy of the
REM   declared list, which silently goes stale the moment a gate is added (the
REM   very drift p4gate.py manifestcheck exists to prevent for file lists).
REM   Counted with findstr /b /c: (literal, anchored -- the same idiom the
REM   -only gate-name check below uses) and a counter, NOT with findstr /n:
REM   /n prints the line number IN THE FILE, so "last number" gave 309 here
REM   (measured 2026-10-10, first attempt) -- and a bare 'findstr "a b"' splits
REM   on spaces and ORs the words.  NOT `find`: when this runner is launched
REM   from Git Bash, MSYS find.exe comes first in PATH and `find /c` reads /c
REM   as a path and traverses C: recursively.
set "GATE_TOTAL=0"
for /f "delims=" %%C in ('findstr /b /c:"call :gate " "%RUNNER_PATH%"') do set /a GATE_TOTAL+=1
if "%GATE_TOTAL%"=="0" (
  echo [P4GUARD FAIL] no 'call :gate' rows found in %RUNNER_NAME%
  exit /b 97
)

>"%MATRIX_LOG%" echo ==== P4 DEFAULT-BUILD REGRESSION MATRIX (%GATE_TOTAL% gates) ====
call :log "started     : %DATE% %TIME%"
call :log "repo root   : %REPO_ROOT%"
call :log "root source : %P4_SELF_ROOT%  (derived from this script's own location)"
call :log "run mode    : %MODE%"
call :log "work root   : %WORKROOT%"
call :log "matrix log  : %MATRIX_LOG%"
call :log "gate list   : the %GATE_TOTAL% 'call :gate' rows in %RUNNER_NAME% (declared once)"
set "GATE_FILTER=%GATE_ONLY%"
if "%GATE_ONLY%"=="" set "GATE_FILTER=(none -- all %GATE_TOTAL%)"
call :log "gate filter : %GATE_FILTER%"
call :log "guard       : checkpaths + manifestcheck before, scanlog after each gate"
call :log "note        : gates unit_retx / unit_fifo exit 0 unconditionally (their"
call :log "              .bat ends in 'type xsim*.log') -- read their console tail."
call :log "note        : unit_uart is NOT one of them any more (P7B 2026-09-29): it prints"
call :log "              its verdict line and exits non-zero on FAIL:."

call :log "--- revision fingerprint (before) ---"
"%PY%" "%P4GATE_PY%" fingerprint --root "%REPO_ROOT%" --out "%FP_BEFORE%" --label before >>"%MATRIX_LOG%" 2>&1
if errorlevel 1 goto :fatal_fp

call :log "--- gates ---"
call :gate chain       sim\p4sim\run_tb_p4_chain.bat       chain_src.f -                           -
call :gate burst200    sim\p4sim\run_tb_p4_burst.bat       chain_src.f -                           "200"
call :gate trunc50     sim\p4sim\run_tb_p4_burst.bat       chain_src.f "TRUNC=50;TRUNCM=8"          "200"
call :gate trunc100    sim\p4sim\run_tb_p4_burst.bat       chain_src.f "TRUNC=100;TRUNCM=8"         "200"
call :gate halfdrop    sim\p4sim\run_tb_p4_burst.bat       chain_src.f "HALFDROP=100;HALFDROPK=990" "200"
call :gate txdrop50    sim\p4sim\run_tb_p4_burst.bat       chain_src.f -                           "200 -1 0 4000 0 0 50"
call :gate gate4096    sim\p4sim\run_tb_p4_burst.bat       chain_src.f -                           "200 -1 0 10"
call :gate dupstorm    sim\p4sim\run_tb_p4_burst.bat       chain_src.f -                           "200 0 0 4000 608 dup"
call :gate pcackoob    sim\p4sim\run_tb_p4_burst.bat       chain_src.f "PCACKOOB=1"                "200"
call :gate vlanchain   sim\p4sim\run_tb_p4_chain_vlan.bat  chain_src.f -                           -
call :gate vlanburst   sim\p4sim\run_tb_p4_burst_vlan.bat  chain_src.f -                           "200"
call :gate stallgate   sim\p4sim\run_tb_p4_chain_stall.bat chain_src.f -                           -
call :gate unit_retx   sim\retxsim\run_retx_tb.bat         retx_src.f  -                           -
call :gate unit_fifo   sim\retxsim2\run_tb_frame_fifo.bat  fifo_src.f  -                           "%FRAME_FIFO%"
call :gate unit_vlan   sim\vlansim\run_tb_vlan_strip.bat   vlan_src.f  -                           -
call :gate unit_uart   sim\tbgate\run_tb_uart_dbg.bat      uart_src.f  -                           -
REM ---- p5_wrapper (registered 2026-10-10; HANDOFF ledger #19) ---------------
REM   The ONLY standing gate that compiles board\wrapper_p4.v AND
REM   rtl\app_pattern.v through a real wrapper instance (module-level TBs and
REM   the P4 chain never see either file).  It was RED for a real reason until
REM   2026-10-10 (wrapper_p4.v:2771-2775 aliases reversed => TX undriven); the
REM   fix landed before this registration.
REM   ⚠️ CONFIG COVERAGE = `-d APP_MODE` ONLY (single-domain / legacy branch).
REM   It does NOT cover the board wrapper configuration (DP_156MHZ), does not
REM   compile PCIE_OBS / P7B_10G / UDP_TX_OVL, and with TCP_TX_OVL off the r6
REM   tcp_tx_frame `ack_seen` start gate is NOT in it either.  Do not quote it
REM   as a board-config wrapper gate -- see sim\p4gates\p5wrapper_src.f header.
call :gate p5_wrapper  sim\p5sim\run_tb_p5_wrapper.bat     p5wrapper_src.f -                           -
REM ---- f3_resync (registered 2026-10-15; F-3 fix G1 gate / ledger #20) ------
REM   F-3 (MMCM unlock/relock) DP-side resync gate: rtl\vlan_strip.v RESYNC_EN
REM   (+ board\wrapper_p4.v VLAN_STRIP_RESYNC).  Five arms, sequential:
REM     F    = new RTL RESYNC_EN=1           -> CHK line all green
REM     L    = new RTL RESYNC_EN=0           -> verbatim historical defect shape (XFAIL-REPRODUCED)
REM     M1   = mutant fwd=1'b1               -> teeth: J1 red, J3eq=0, ALL=0
REM     M2   = mutant fwd=...||s_axis_tlast -> teeth: J1 red, J3eq=0, ALL=0
REM     CTRL = RESYNC_EN=1 + injection in IFG -> positive control (J3pos=0, zero loss)
REM   Arm identity travels via -d defines (NOT testplusarg -- xsim splits on '=').
REM   Registered the p5_wrapper way (#19): private cwd (P4_WORKDIR) + declared
REM   manifest sim\p4gates\f3resync_src.f (8 files; each DUT variant appears as
REM   exactly one literal in the gate .bat).
call :gate f3_resync  sim\f3_resync\run_tb_f3_resync.bat   f3resync_src.f -                            -
REM ---- swc (registered 2026-10-15; switch-door R5 gate / ledger #21) --------
REM   P9 switch-door (TX_SWCLOSE / close-out-then-switch) gate: rtl\app_pattern.v
REM   (live) vs the frozen pre-edit copy sim\p9_swc_gate\head_app_pattern.v, plus
REM   three mutant DUTs.  Eight runs, each RC=0 WITH the run-level criterion
REM   ("measured red set == expected red set") checked INSIDE the TB -- a
REM   mutant's "must be red" is never decided by a nonzero exit code:
REM     F/F10 = live RTL + P9_SWC_ARM (P7B_10G on F10) -> all green
REM     H/H10 = frozen pre-edit RTL  -> EXP_HEAD red set (XFAIL shape)
REM     OFF   = live RTL + constant-level SWC=0 -> red set same as HEAD
REM     M6    = mutant v1-equations  -> all arms red
REM     M6B   = mutant closing-drop  -> arms {3,4} red
REM     M7    = mutant v2r2-guard    -> arm {10} red (R5: bite migrated)
REM   Arm identity travels via -d defines (NOT testplusarg -- xsim splits on '=').
REM   Registered the p5_wrapper way (#19): private cwd (P4_WORKDIR) + declared
REM   manifest sim\p4gates\swcg_src.f (6 files; each DUT variant appears as
REM   exactly one literal xvlog row in the gate .bat).
call :gate swc         sim\p9_swc_gate\run_tb_p9_swc.bat   swcg_src.f  -                            -
REM ---- p7b_chain (registered 2026-10-18; P1 impl round #22) -------------------
REM   The ONLY standing gate that compiles the P7B_10G BOARD configuration
REM   (P7B_10G + DP_156MHZ + PCIE_OBS + APP_MODE + UDP_TX_OVL + TCP_TX_OVL
REM   + P7B_SIM_NOPCS). Covers ch0 (J7) RX MAC / 76-bit tap / sink counters,
REM   W76..W82, the snapshot gather timeout and the LOS edge counters.
REM   The other wrapper gate (p5_wrapper) compiles -d APP_MODE only and cannot
REM   see anything inside `ifdef P7B_10G` / `ifdef PCIE_OBS`.
REM   HLS netlist is passed as a generated -f list; see p7bchain_src.f header.
call :gate p7b_chain   _proj_10g\p7b_chain\sim\run_tb_p7b_chain.bat p7bchain_src.f -                     -
REM ---- biz_win (registered 2026-10-18; P11 P1 fix round / FINDINGS high-1) ---
REM   The snapshot-window verification layer used to live entirely OUTSIDE the
REM   matrix: `check_window.py` (static assembly check of snap_dout_all) was RED
REM   (RC=1 / 9 FAIL) and `tb_biz_win` (axi_regs address <-> word readback) was
REM   not run in this round. This gate runs BOTH:
REM     A. check_window.py positive (RC=0 / CHECK_WINDOW_PASS) + THREE mutation
REM        negative controls (--mutate drop|swap|declpatho) that MUST return RC=1
REM        (a checker that cannot go red is a toothless checker).
REM     B. run_tb_biz_win.bat -> TB_BIZ_WIN_PASS (NW=83 per-word readback).
REM   See _proj_10g/notes/p7b_biz_win/run_gate_biz_win_check.bat header.
call :gate biz_win     _proj_10g\notes\p7b_biz_win\run_gate_biz_win_check.bat bizwinsrc.f -                  -
REM ---- P11 P2-甲 (2026-10-18) three new gates (#23/#24/#25; 21 -> 24) --------
REM   G2 rx_merge2 unit (RR / work-conserving / atomicity / STRICT=1 N-13 negctl).
REM   G5 tcp_tx_frame per-conn source IP (OVL+default bodies, N-6, replay, mutant red).
REM   G6 real wrapper + DUAL_SFP_A dual-port chain (HLS arm A = IP_A only; IP_B
REM      needs the re-synthesised dual-IP HLS netlist => build round).
REM   G3/G4 are standalone (not registered; registered debt per design M-5):
REM      _proj_10g/p11_dual/sim/{tb_tx_split,tb_slow_tx_port}.v
call :gate g2_rx_merge2 _proj_10g\p11_dual\sim\run_tb_rx_merge2.bat p11merge_src.f -                  -
call :gate g5_tcp_srcip _proj_10g\p11_dual\sim\run_tb_tcp_tx_srcip.bat p11srcip_src.f -                -
call :gate g6_p11_dual _proj_10g\p11_dual\sim\run_tb_p11_dual.bat p11dual_src.f -                     -

REM ---- P11 P3 (C4 甲双栈; 2026-10-19; 24 -> 32) -----------------------------
REM   G-P3-1  win_pool_mgr 单元 / G-P3-1b 8 连接 churn / G-P3-3 共享 retx /
REM   G-P3-4 慢 merge+demux+cfg demux / G-P3-6 C4 wrapper 全链 /
REM   G-P3-7 C4 elaboration 正控.
REM   ⚠️ 负控驱动 (run_negctl_{wpm,churn,cfg_c4}.bat) 为独立门、未入册 (P2 G3/G4
REM      同款登记债: 它们 cd 到 %~dp0 编译, 不满足矩阵私有 cwd 约定).
call :gate p11_c4_elab   _proj_10g\notes\p11_p3_impl_20261018\gates\sim\run_elab_c4.bat            p11c4elab_src.f - -
call :gate p11_wpm       _proj_10g\notes\p11_p3_impl_20261018\gates\sim\run_tb_win_pool_mgr.bat     p11wpm_src.f    - -
call :gate p11_retx_pool _proj_10g\notes\p11_p3_impl_20261018\gates\sim\run_tb_retx_pool_shared.bat p11retx_src.f   - -
call :gate p11_slow_merge2 _proj_10g\notes\p11_p3_impl_20261018\gates\sim\run_tb_slow_merge2.bat    p11sm2_src.f    - -
call :gate p11_slow_demux2 _proj_10g\notes\p11_p3_impl_20261018\gates\sim\run_tb_slow_demux2.bat    p11sd2_src.f    - -
call :gate p11_slow_cfg_demux _proj_10g\notes\p11_p3_impl_20261018\gates\sim\run_tb_slow_cfg_demux.bat p11scd_src.f - -
call :gate p11_churn    _proj_10g\notes\p11_p3_impl_20261018\gates\sim\run_tb_p3_churn.bat          p11churn_src.f  - -
call :gate p11_c4_wrap  _proj_10g\notes\p11_p3_impl_20261018\gates\sim\run_tb_p11_c4_wrap.bat      p11c4w_src.f    - -

call :log "--- revision fingerprint (after) ---"
"%PY%" "%P4GATE_PY%" fingerprint --root "%REPO_ROOT%" --out "%FP_AFTER%" --label after >>"%MATRIX_LOG%" 2>&1
if errorlevel 1 goto :fatal_fp2

call :log "--- freeze check ---"
"%PY%" "%P4GATE_PY%" compare --a "%FP_BEFORE%" --b "%FP_AFTER%" >>"%MATRIX_LOG%" 2>&1
if errorlevel 1 set "DRIFT=1"

call :log "--- summary ---"
call :log "gate filter : %GATE_FILTER%"
call :log "gates run   : %GATE_RUN% / %GATE_TOTAL%"
call :log "gates failed: %GATE_FAIL%"
call :log "MATRIX DONE %DATE% %TIME%"
echo ---- summary ----
findstr /b "GATE " "%MATRIX_LOG%"

if not "%DRIFT%"=="0" (
  echo [P4GUARD FAIL] REVISION DRIFT: sources changed while the matrix ran
  exit /b 2
)
if not "%GATE_FAIL%"=="0" exit /b 1
exit /b 0

REM --------------------------------------------------------------------------
:fatal_fp
call :log "FATAL: pre-run fingerprint failed -- nothing was tested"
echo [P4GATE FATAL] pre-run fingerprint failed -- nothing was tested
exit /b 1
:fatal_fp2
call :log "FATAL: post-run fingerprint failed"
echo [P4GATE FATAL] post-run fingerprint failed
exit /b 1

REM --------------------------------------------------------------------------
:gate
REM %1=name %2=bat(repo-rel) %3=manifest %4=env(VAR=VAL;...) or - %5=args or -
set "GN=%~1"
set "GBAT=%REPO_ROOT%\%~2"
set "GMAN=%GATES%\%~3"
set "GENV=%~4"
set "GARGS=%~5"
if "%GENV%"=="-" set "GENV="
if "%GARGS%"=="-" set "GARGS="
for %%D in ("%GBAT%") do set "GDIR=%%~dpD"

REM optional gate selection: /only a,b,c  (exact name match)
if "%GATE_ONLY%"=="" goto :gate_sel_done
echo +%GATE_ONLY%+ | findstr /i /c:"+%GN%+" >nul
if errorlevel 1 (
  echo GATE %GN% SKIPPED -- not selected by /only %GATE_ONLY%
  exit /b 0
)
:gate_sel_done

REM every stimulus env var any P4 gate reads -- cleared, then this gate's own
set "TRUNC="
set "TRUNCM="
set "HALFDROP="
set "HALFDROPK="
set "PCACKOOB="
set "P4_WORKDIR="
REM NB: no inline 'if ... for %%V in ()' -- cmd parses the whole line first and an
REM empty for-set is a syntax error even when the 'if' is false.
if "%GENV%"=="" goto :gate_env_done
for %%V in (%GENV:;= %) do set "%%V"
:gate_env_done

set "GWORK=%GDIR%"
if defined ISOLATED set "GWORK=%WORKROOT%\%GN%"
if not exist "%GWORK%\" mkdir "%GWORK%"
set "P4_WORKDIR=%GWORK%"
set "GLOG=%GWORK%\_gate_console.log"
set /a GATE_RUN=GATE_RUN+1

call :log "=== GATE %GN% : %~2 %GARGS%   [env %GENV%]   [cwd %GWORK%]"

set "PRECHK=ok"
"%PY%" "%P4GATE_PY%" checkpaths --root "%REPO_ROOT%" --manifest "%GMAN%" --path "%GBAT%" --path "%GWORK%" >>"%MATRIX_LOG%" 2>&1
if errorlevel 1 set "PRECHK=checkpaths"
"%PY%" "%P4GATE_PY%" manifestcheck --root "%REPO_ROOT%" --manifest "%GMAN%" --bat "%GBAT%" >>"%MATRIX_LOG%" 2>&1
if errorlevel 1 if "%PRECHK%"=="ok" set "PRECHK=manifestcheck"

set "RC=0"
if not "%PRECHK%"=="ok" (
  call :log "PRECHECK-FAIL %GN% [%PRECHK%] -- gate NOT run"
  set "RC=97"
) else (
  pushd "%GWORK%"
  call "%GBAT%" %GARGS% > "%GLOG%" 2>&1
  set "RC=!errorlevel!"
  popd
)

"%PY%" "%P4GATE_PY%" scanlog --root "%REPO_ROOT%" --logdir "%GWORK%" >>"%MATRIX_LOG%" 2>&1
if errorlevel 1 if "%RC%"=="0" set "RC=98"

call :log "EXIT=%RC%"
REM gatebrief prints to stdout; the runner's own >> does the appending (a
REM second writer would get PermissionError on the open matrix log)
"%PY%" "%P4GATE_PY%" gatebrief --log "%GLOG%" --lines 6 >>"%MATRIX_LOG%" 2>&1
call :log "---"
if not "%RC%"=="0" set /a GATE_FAIL=GATE_FAIL+1
echo GATE %GN% EXIT=%RC%
REM let file handles / xsim.dir locks settle before the next gate
ping -n 4 127.0.0.1 >nul
exit /b 0

:log
>>"%MATRIX_LOG%" echo %~1
exit /b 0
