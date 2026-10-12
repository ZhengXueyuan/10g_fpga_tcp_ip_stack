# 追加轮证明报告：review_scratch/ → agent_docs/review_scratch/（2026-10-13）

**指令**：owner「review_scratch 也是 agent 文档，要挪到 agent_docs 去」（经桥确认并入）。
**提交**（本地，未 push）：

| 提交 | 消息 |
|---|---|
| `68b5f4d` | docs: review_scratch（78 件）迁入 agent_docs/review_scratch（纯移动，R100） |
| `af50848` | docs: review_scratch 引用改写至 agent_docs/review_scratch/（_proj_10g 之外 19 处） |
| （本报告 + MAPPING/INDEX） | docs: review_scratch 迁移证明 + 索引/映射同步 |

> 摸底复核**独立复测与 claude-main 侦察数字不符**：其"总 29 文件（_proj_10g 6 + 外 23）"
> 实测为 `git grep -l review_scratch`（含裸词）**64 文件** = review_scratch 自 38 · _proj_10g 18 ·
> agent_docs 5 · sim 2 · .gitignore 1；按本任务改写口径 `review_scratch/`（带斜杠裸前缀）
> = **58 文件 104 处** = 目录自 37 · _proj_10g 14 · agent_docs 5 · sim 1 · .gitignore 1。
> 本报告全部按实测口径登记。

## 1. R100 纯移动判据（提交① `68b5f4d`）

`git ls-files review_scratch | wc -l` = **78**；`git mv review_scratch agent_docs/review_scratch`。
`git diff --cached -M --name-status --diff-filter=R` **恰好 78 行 R100**（全量附于文末附录 A）；
`--numstat` 非零行数 **0**（全 `0 0`）；`--diff-filter=AMD` **空输出**。提交后
`git diff -M --name-status HEAD^..HEAD` 复核一致（78 files changed, 0 insertions, 0 deletions）。

## 2. 引用改写（提交② `af50848`，7 文件 19 处）

改写规则：裸前缀 `review_scratch/`（lookbehind `(?<![A-Za-z0-9_./\\-])`，防双前缀、
防 `udp_hls_10g/review_scratch/` 绝对路径段被二次套接）→ `agent_docs/review_scratch/`。
字节级保真（rb/wb）；dry-run 人工过目 19/19 后 apply；**幂等复跑 0**；反例自测
（`agent_docs/review_scratch/`、`udp_hls_10g/review_scratch/x`、`xreview_scratch/`）全不命中。

| 文件 | 改前 | 改后 | 性质 |
|---|---|---|---|
| agent_docs/review_scratch/_sec_R.md | 2 | 0 | 目录自述的根相对自引用（owner 指示沿用根相对约定） |
| agent_docs/P6B_REVIEW.md | 8 | 0 | LIVE 散文引用（含 `review_scratch/rw/tb_rvw_macrx.v` 等） |
| agent_docs/P6B_COMMIT_PLAN.md | 4 | 0 | LIVE 散文引用 |
| agent_docs/PORT_NOTES.md | 1 | 0 | LIVE |
| agent_docs/P6B_SUMMARY.md | 1 | 0 | LIVE |
| agent_docs/checks/migration_proof.md | 1 | 0 | 报告自述 |
| .gitignore | 2 | 0 | 注释行 1（`# 临时目录 (int_scratch/ review_scratch/ …)`）+ **模式行 1**（`!review_scratch/**/*.log` → `!agent_docs/review_scratch/**/*.log`，路径保鲜不改语义） |
| **合计** | **19** | **0** | |

.gitignore 哨兵实测：`git check-ignore -v agent_docs/review_scratch/probe/x.log` →
由 `!agent_docs/review_scratch/**/*.log`（行 484）放行，新路径下 .log 入库能力保持 ✓。

## 3. 不改判定（逐类登记）

| 类别 | 件数 | 命中 | 判定依据 |
|---|---|---|---|
| 目录内 `.log` 证据文件 | 36 文件 | 84 处 | 内容为 xsim/vivado **历史工具输出的绝对路径**（`D:/repo/XCKU5PMini/udp_hls_10g/review_scratch/rd_*/...` 的 Current directory/Log file/$finish 记录）。改写 = 伪造"当日在何处运行"的证据（方案风险 R1）；owner 指示的"目录内部自引用沿用根相对约定"针对的是指针性引用，不涵盖历史输出记录。路径解析由 MAPPING.md 兜底。 |
| sim/p4gates/evidence/sweep_absolute_paths.txt | 1 | 1 | 审计快照（行 2080 `review_scratch/run.bat 1 line(s)`），与前两轮对其 26+1 处文档引用的处置一致：留档。 |
| sim/p4gates/evidence/_pathfix_tool.py | （0 处带斜杠） | 0 | **一次性历史工具**（evidence 留档的 `_tmp_path_fix.py` 副本；2026-09 空门路径修复已跑完）。其 `review_scratch` 仅是目录遍历排除项（`p.startswith('review_scratch')`，行 40-43），非按位置解析的路径依赖；移动后路径段 `review_scratch` 仍命中该排除，重跑行为不变 → 不改。 |
| `_proj_10g/**` | 14 文件 | 209 处（裸前缀口径） | 只读事实源，纪律禁改；全部进 MAPPING 兜底。清单见 §5。 |
| `_tmp_p4_sweep.py` · `_tmp_path_fix.py`（未跟踪） | 2 | 裸词若干 | 未跟踪临时件，按指示不动。 |
| `.claude/worktrees/`（未跟踪镜像） | — | — | 镜像不动。 |

## 4. 终态 grep 证明（提交③前实测）

改写口径：裸前缀 `review_scratch/`（上述 lookbehind 正则）。

- **`_proj_10g/` 之外：7 处 / 3 文件，LIVE 悬空 = 0**：

  ```
  5  agent_docs/INDEX.md     ← 同目录互链标签+目标（[review_scratch/](review_scratch/) 等，判据4规则，零悬空）
  1  agent_docs/MAPPING.md   ← 映射表自述旧名（本文档的职责即记录旧名）
  1  sim/p4gates/evidence/sweep_absolute_paths.txt  ← HISTORICAL 审计快照
  ```

  （注：上列为 `git grep` 已跟踪层；`.log` 证据文件的 84 处均为**绝对路径段**
  `udp_hls_10g/review_scratch/...`，带路径前缀，本就落在裸前缀正则之外，另按 §3 登记。）
- 新形态 `agent_docs/review_scratch/`：**20 处 / 8 文件**（改写 19 + MAPPING 表行 1）。
- `_proj_10g/` 内裸前缀 **209 处 / 14 文件**：不动，MAPPING.md 第 15 行兜底。
- 根 README.md：`grep -c review_scratch README.md` = **0**（确认无链，无需改）。
- 自述口径：本报告入库后自身含 90 处裸前缀引用（§1–§5 的引用记录与清单原文，正是证明文档的职责），
  与 migration_proof.md 自述同类别；复算时预期 `_proj_10g/` 之外 = 97 处 / 4 文件
  （INDEX 5 + MAPPING 1 + sweep 1 + 本报告 90），无新增 LIVE。

## 5. `_proj_10g/**` 引用清单（14 文件，MAPPING 兜底登记）

```
_proj_10g/notes/P7B_COMMIT_PLAN2.md                        (3 处)
_proj_10g/notes/P7B_IMPLICIT_GATE_FIX.md                   (7)
_proj_10g/notes/P7B_IMPLICIT_GATE_ROLLOUT.md               (1)
_proj_10g/notes/p7b_implicit_repro/apply_log.txt           (15)
_proj_10g/notes/p7b_implicit_repro/dryrun.txt              (15)
_proj_10g/notes/p7b_implicit_repro/dryrun2.txt             (15)
_proj_10g/notes/p7b_implicit_repro/dryrun3.txt             (15)
_proj_10g/notes/p7b_implicit_repro/dryrun_before_apply.txt (15)
_proj_10g/notes/p7b_implicit_repro/fix_gates_changelog.txt (15)
_proj_10g/notes/p7b_implicit_repro/integrity_final.txt     (7)
_proj_10g/notes/p7b_readside_harden_20261010/_scan_fileset.txt   (92)
_proj_10g/notes/p7b_readside_harden_20261010/scan/scripts_only.txt (9)
_proj_10g/notes/p7b_rollout/logs/classify_3091.txt
_proj_10g/notes/p7b_rollout/logs/corpus_scan2.txt
```
（多数为扫描清单/日志中的路径罗列，属历史记录性质，恰是 MAPPING 兜底的预期对象。）

## 6. 索引同步

- `agent_docs/MAPPING.md`：新增第 15 行 `udp_hls_10g/review_scratch/`（整目录 78 件）→
  `agent_docs/review_scratch/`，附 .log 绝对路径原文的解析注记。
- `agent_docs/INDEX.md`：新增「review_scratch/（对抗审查原始证据目录，78 件）」小节 +
  checks/ 小节补链本报告。

## 7. 复算口令（只读）

```bash
cd /d/repo/XCKU5PMini/udp_hls_10g
RX='(?<![A-Za-z0-9_./\\-])review_scratch/'
git grep -o -P "$RX" | cut -d: -f1 | sort | uniq -c   # 全仓分布（_proj_10g 之外应只剩 §4 三行）
git grep -o -P '(?<![A-Za-z0-9_./\\-])agent_docs/review_scratch/' | wc -l   # 新形态
git ls-files agent_docs/review_scratch | wc -l        # 78
git diff -M --name-status 68b5f4d^..68b5f4d | grep -c '^R100'  # 78
```

---

## 附录 A：R100 原始输出（78 行，`git diff --cached -M --name-status --diff-filter=R`）
R100	review_scratch/_sec_R.md	agent_docs/review_scratch/_sec_R.md
R100	review_scratch/macrx_stim/expected_stats.txt	agent_docs/review_scratch/macrx_stim/expected_stats.txt
R100	review_scratch/rd_base_bal/xe_rv.log	agent_docs/review_scratch/rd_base_bal/xe_rv.log
R100	review_scratch/rd_base_bal/xs_rv.log	agent_docs/review_scratch/rd_base_bal/xs_rv.log
R100	review_scratch/rd_base_bal/xv_rv.log	agent_docs/review_scratch/rd_base_bal/xv_rv.log
R100	review_scratch/rd_base_bal/xvlog.log	agent_docs/review_scratch/rd_base_bal/xvlog.log
R100	review_scratch/rd_cons/xe.log	agent_docs/review_scratch/rd_cons/xe.log
R100	review_scratch/rd_cons/xs.log	agent_docs/review_scratch/rd_cons/xs.log
R100	review_scratch/rd_cons/xv.log	agent_docs/review_scratch/rd_cons/xv.log
R100	review_scratch/rd_cons/xvlog.log	agent_docs/review_scratch/rd_cons/xvlog.log
R100	review_scratch/rd_fullnext/xe_fn.log	agent_docs/review_scratch/rd_fullnext/xe_fn.log
R100	review_scratch/rd_fullnext/xs_fn.log	agent_docs/review_scratch/rd_fullnext/xs_fn.log
R100	review_scratch/rd_fullnext/xv_fn.log	agent_docs/review_scratch/rd_fullnext/xv_fn.log
R100	review_scratch/rd_fullnext/xvlog.log	agent_docs/review_scratch/rd_fullnext/xvlog.log
R100	review_scratch/rd_macrx/crc_log.txt	agent_docs/review_scratch/rd_macrx/crc_log.txt
R100	review_scratch/rd_macrx/xe.log	agent_docs/review_scratch/rd_macrx/xe.log
R100	review_scratch/rd_macrx/xe_rv.log	agent_docs/review_scratch/rd_macrx/xe_rv.log
R100	review_scratch/rd_macrx/xs.log	agent_docs/review_scratch/rd_macrx/xs.log
R100	review_scratch/rd_macrx/xs_rv.log	agent_docs/review_scratch/rd_macrx/xs_rv.log
R100	review_scratch/rd_macrx/xv.log	agent_docs/review_scratch/rd_macrx/xv.log
R100	review_scratch/rd_macrx/xv_rv.log	agent_docs/review_scratch/rd_macrx/xv_rv.log
R100	review_scratch/rd_macrx/xvlog.log	agent_docs/review_scratch/rd_macrx/xvlog.log
R100	review_scratch/rd_macrx_old/crc_log.txt	agent_docs/review_scratch/rd_macrx_old/crc_log.txt
R100	review_scratch/rd_macrx_old/xe.log	agent_docs/review_scratch/rd_macrx_old/xe.log
R100	review_scratch/rd_macrx_old/xs.log	agent_docs/review_scratch/rd_macrx_old/xs.log
R100	review_scratch/rd_macrx_old/xv.log	agent_docs/review_scratch/rd_macrx_old/xv.log
R100	review_scratch/rd_macrx_old/xvlog.log	agent_docs/review_scratch/rd_macrx_old/xvlog.log
R100	review_scratch/rd_macrx_probe/crc_log.txt	agent_docs/review_scratch/rd_macrx_probe/crc_log.txt
R100	review_scratch/rd_macrx_probe/xe.log	agent_docs/review_scratch/rd_macrx_probe/xe.log
R100	review_scratch/rd_macrx_probe/xs.log	agent_docs/review_scratch/rd_macrx_probe/xs.log
R100	review_scratch/rd_macrx_probe/xv.log	agent_docs/review_scratch/rd_macrx_probe/xv.log
R100	review_scratch/rd_macrx_probe/xvlog.log	agent_docs/review_scratch/rd_macrx_probe/xvlog.log
R100	review_scratch/rd_mutC_C_BAL/xe_rv.log	agent_docs/review_scratch/rd_mutC_C_BAL/xe_rv.log
R100	review_scratch/rd_mutC_C_BAL/xs_rv.log	agent_docs/review_scratch/rd_mutC_C_BAL/xs_rv.log
R100	review_scratch/rd_mutC_C_BAL/xv_rv.log	agent_docs/review_scratch/rd_mutC_C_BAL/xv_rv.log
R100	review_scratch/rd_mutC_C_BAL/xvlog.log	agent_docs/review_scratch/rd_mutC_C_BAL/xvlog.log
R100	review_scratch/rd_mutC_C_BOUND/xe_rv.log	agent_docs/review_scratch/rd_mutC_C_BOUND/xe_rv.log
R100	review_scratch/rd_mutC_C_BOUND/xs_rv.log	agent_docs/review_scratch/rd_mutC_C_BOUND/xs_rv.log
R100	review_scratch/rd_mutC_C_BOUND/xv_rv.log	agent_docs/review_scratch/rd_mutC_C_BOUND/xv_rv.log
R100	review_scratch/rd_mutC_C_BOUND/xvlog.log	agent_docs/review_scratch/rd_mutC_C_BOUND/xvlog.log
R100	review_scratch/rd_mutC_C_WRFAST/xe_rv.log	agent_docs/review_scratch/rd_mutC_C_WRFAST/xe_rv.log
R100	review_scratch/rd_mutC_C_WRFAST/xs_rv.log	agent_docs/review_scratch/rd_mutC_C_WRFAST/xs_rv.log
R100	review_scratch/rd_mutC_C_WRFAST/xv_rv.log	agent_docs/review_scratch/rd_mutC_C_WRFAST/xv_rv.log
R100	review_scratch/rd_mutC_C_WRFAST/xvlog.log	agent_docs/review_scratch/rd_mutC_C_WRFAST/xvlog.log
R100	review_scratch/rd_mutF_C_BAL/xe_rv.log	agent_docs/review_scratch/rd_mutF_C_BAL/xe_rv.log
R100	review_scratch/rd_mutF_C_BAL/xs_rv.log	agent_docs/review_scratch/rd_mutF_C_BAL/xs_rv.log
R100	review_scratch/rd_mutF_C_BAL/xv_rv.log	agent_docs/review_scratch/rd_mutF_C_BAL/xv_rv.log
R100	review_scratch/rd_mutF_C_BAL/xvlog.log	agent_docs/review_scratch/rd_mutF_C_BAL/xvlog.log
R100	review_scratch/rd_mutF_C_RESET/xe_rv.log	agent_docs/review_scratch/rd_mutF_C_RESET/xe_rv.log
R100	review_scratch/rd_mutF_C_RESET/xs_rv.log	agent_docs/review_scratch/rd_mutF_C_RESET/xs_rv.log
R100	review_scratch/rd_mutF_C_RESET/xv_rv.log	agent_docs/review_scratch/rd_mutF_C_RESET/xv_rv.log
R100	review_scratch/rd_mutF_C_RESET/xvlog.log	agent_docs/review_scratch/rd_mutF_C_RESET/xvlog.log
R100	review_scratch/rd_term/xe_tm.log	agent_docs/review_scratch/rd_term/xe_tm.log
R100	review_scratch/rd_term/xs_tm.log	agent_docs/review_scratch/rd_term/xs_tm.log
R100	review_scratch/rd_term/xv_tm.log	agent_docs/review_scratch/rd_term/xv_tm.log
R100	review_scratch/rd_term/xvlog.log	agent_docs/review_scratch/rd_term/xvlog.log
R100	review_scratch/run.bat	agent_docs/review_scratch/run.bat
R100	review_scratch/run_base_bal/xvlog.log	agent_docs/review_scratch/run_base_bal/xvlog.log
R100	review_scratch/runcons.bat	agent_docs/review_scratch/runcons.bat
R100	review_scratch/runfn.bat	agent_docs/review_scratch/runfn.bat
R100	review_scratch/runmac.bat	agent_docs/review_scratch/runmac.bat
R100	review_scratch/runmacrx.bat	agent_docs/review_scratch/runmacrx.bat
R100	review_scratch/runmacrx_old.bat	agent_docs/review_scratch/runmacrx_old.bat
R100	review_scratch/runmacrx_probe.bat	agent_docs/review_scratch/runmacrx_probe.bat
R100	review_scratch/runmuts.bat	agent_docs/review_scratch/runmuts.bat
R100	review_scratch/runterm.bat	agent_docs/review_scratch/runterm.bat
R100	review_scratch/rw/base_fifo_async.v	agent_docs/review_scratch/rw/base_fifo_async.v
R100	review_scratch/rw/mac_rx_64_asold.v	agent_docs/review_scratch/rw/mac_rx_64_asold.v
R100	review_scratch/rw/mac_rx_64_old.v	agent_docs/review_scratch/rw/mac_rx_64_old.v
R100	review_scratch/rw/mutC_full1stage.v	agent_docs/review_scratch/rw/mutC_full1stage.v
R100	review_scratch/rw/mutF_rst1stage.v	agent_docs/review_scratch/rw/mutF_rst1stage.v
R100	review_scratch/rw/tb_fifo_async.v	agent_docs/review_scratch/rw/tb_fifo_async.v
R100	review_scratch/rw/tb_mrx_probe.v	agent_docs/review_scratch/rw/tb_mrx_probe.v
R100	review_scratch/rw/tb_rvw_conserve.v	agent_docs/review_scratch/rw/tb_rvw_conserve.v
R100	review_scratch/rw/tb_rvw_fullnext.v	agent_docs/review_scratch/rw/tb_rvw_fullnext.v
R100	review_scratch/rw/tb_rvw_macrx.v	agent_docs/review_scratch/rw/tb_rvw_macrx.v
R100	review_scratch/rw/tb_rvw_term.v	agent_docs/review_scratch/rw/tb_rvw_term.v
R100	review_scratch/wt.txt	agent_docs/review_scratch/wt.txt
