# 文档迁移证明报告：14 份 AI 向根文档 → `agent_docs/`

**执行**：kimi 文档迁移子任务（t_46ffe7622b14 线）　**日期**：2026-10-13
**目标目录**：`agent_docs/`（本任务书指定；`_proj_10g/notes/DOCS_MIGRATION_PLAN.md` 的 `docs/` 方案未执行，方法论沿用）
**提交**（均为本地提交，**未 push**，由主 agent 统一推送）：

| 提交 | 消息 |
|---|---|
| `0c55470` | docs: 迁移 14 份 AI 向根文档到 agent_docs/（纯移动，R100） |
| `9205fb7` | docs: 引用改写至 agent_docs/（可写区净改写 355 处 + .gitignore 注释 10 处 + 链接深度修复 0 处） |
| （本报告） | docs: 迁移证明报告（agent_docs/checks/migration_proof.md） |

> ⚠️ 执行期间并发事件（详见 §10）：基线后主干推进了一个他人提交 `d7ebafd`（只动 `_proj_10g/` 边界区，0 引用）；README.md 被并发会话**整体重写**（582→46 行，其新内容已自行采用 `agent_docs/` 新形态）。

---

## 1. 引用基线（三层计数，DOCS_MIGRATION_PLAN §8 口径复测）

正则（与方案 §2.1 同）：`(?<![A-Za-z0-9_./\\-])(NAME1|…|NAME14)(\.md)?(?![A-Za-z0-9_.-])`（`git grep -I -o -P`）。

| 层 | 计数 | 备注 |
|---|---|---|
| 总量（已跟踪） | **1974** | 在基线 `f1d81cd` 实测；主干推进到 `d7ebafd` 后复测仍为 **1974** |
| `.md` 形式 | **1000** | |
| 裸名形式 | **974** | 占 49.3%（方案旧基线为 40%，仓库已增长） |
| 路径+行号形式 `Name.md:N` | **252** | 迁移只改路径，行号原样保留（§6） |

分区对账：**可写区 395**（29 文件）+ **边界区 1579**（246 文件）= 1974 ✓
可写区再分：**LIVE 364**（16 文件）+ **HISTORICAL 31**（13 文件）= 395 ✓
未跟踪文件：**0 命中**（18 个未跟踪路径逐一 grep 实测，含 `.claude/worktrees/`）。

## 2. 纯移动判据（提交① `0c55470`，R100）

`git mv` 14 份，前后零字节改动。`git diff --cached -M --name-status --diff-filter=R` 原始输出（恰好 14 行 R100）：

```
R100	ISSUE_RX_BYTE_CORRUPTION.md	agent_docs/ISSUE_RX_BYTE_CORRUPTION.md
R100	P6B_ACCEPT.md	agent_docs/P6B_ACCEPT.md
R100	P6B_CDC_AUDIT.md	agent_docs/P6B_CDC_AUDIT.md
R100	P6B_COMMIT_PLAN.md	agent_docs/P6B_COMMIT_PLAN.md
R100	P6B_INTEGRATION_REVIEW.md	agent_docs/P6B_INTEGRATION_REVIEW.md
R100	P6B_REVIEW.md	agent_docs/P6B_REVIEW.md
R100	P6B_SPEC.md	agent_docs/P6B_SPEC.md
R100	P6B_SUMMARY.md	agent_docs/P6B_SUMMARY.md
R100	P6E_OBS.md	agent_docs/P6E_OBS.md
R100	P7A_COMMIT_PLAN.md	agent_docs/P7A_COMMIT_PLAN.md
R100	P7A_RESULT.md	agent_docs/P7A_RESULT.md
R100	P7A_SPEC.md	agent_docs/P7A_SPEC.md
R100	P7B_SPEC.md	agent_docs/P7B_SPEC.md
R100	PORT_NOTES.md	agent_docs/PORT_NOTES.md
```

`--numstat` 全 `0 0`（14 行 `{旧 => agent_docs/新}`）；`--diff-filter=AMD` **空输出** ✓。提交后 `git diff -M --name-status HEAD^..HEAD` 复核同样 14 行 R100。佐证：`agent_docs/P6B_CDC_AUDIT.md` 因唯一命中是标题自指（§5）被回退后，其工作树内容与原始根文件**逐字节一致**（diff 为空）——旁证移动+回退的保真度。

## 3. 可写区 LIVE 逐文件 before→after

| 文件 | 改写前旧形态 | 现旧形态 | 现新形态 `agent_docs/` | 备注 |
|---|---|---|---|---|
| .gitignore | 10 | 0 | 10 | 全是注释行（§4） |
| README.md | 26 | 5 | 3 | 5=树图刻意排除（§5）；26 条中 23 条所在内容被并发重写删除，3 条以新形态幸存 |
| agent_docs/PORT_NOTES.md | 65 | 0 | 65 | |
| agent_docs/P6B_ACCEPT.md | 16 | 0 | 16 | |
| agent_docs/P6B_CDC_AUDIT.md | 1 | 1 | 0 | 旧形态 1=标题自指（刻意） |
| agent_docs/P6B_COMMIT_PLAN.md | 41 | 1 | 40 | 1=标题自指 |
| agent_docs/P6B_INTEGRATION_REVIEW.md | 5 | 1 | 4 | 1=标题自指 |
| agent_docs/P6B_REVIEW.md | 13 | 1 | 12 | 1=标题自指 |
| agent_docs/P6B_SPEC.md | 35 | 1 | 34 | 1=标题自指 |
| agent_docs/P6B_SUMMARY.md | 33 | 1 | 32 | 1=标题自指 |
| agent_docs/P6E_OBS.md | 27 | 0 | 27 | |
| agent_docs/P7A_COMMIT_PLAN.md | 42 | 1 | 41 | 1=标题自指 |
| agent_docs/P7A_RESULT.md | 12 | 0 | 12 | |
| agent_docs/P7A_SPEC.md | 3 | 1 | 2 | 1=标题自指 |
| agent_docs/P7B_SPEC.md | 31 | 1 | 30 | 1=标题自指 |
| agent_docs/ISSUE_RX_BYTE_CORRUPTION.md | 4 | 0 | 4 | |
| **合计** | **364** | **14（=9 标题+5 树图，均刻意）** | **332** | 364−9 标题回退=355 净改写；355−23 并发删除=332 ✓ 对账平 |

改写方式：对命中处一律**只插 `agent_docs/` 前缀**（`.md` 与裸名同改；`Name.md:123` 行号原样保留）。改写器内置 8 条反例自测（`udp_hls_eco/PORT_NOTES.md`、`agent_docs/...` 幂等、`./`、`xP6B_SPEC`、`P6B_SPECX.md`、`P6B_SPECIAL.md` 等）全部不命中；改写器幂等（复跑 0 改动）。

## 4. .gitignore（10 处，只动注释行）

10 行命中（行号 245/463/468/478/499/516/532/537/568/575），改写后 `git diff` 的 20 个 +/- 行**全部是 `#` 注释行**；`git diff -U0 -- .gitignore | grep -vP '^[+-]\s*#'` 为空 ✓。**未增删/重排任何模式行**。哨兵复测（改写后）：`p6b_accept_final/x.log`→由 `!` 行 471 放行、`audit_scratch/x.backup.log`→832 行忽略、`vivado_prj/x.dcp`→44 行忽略、`agent_docs/x.md` 与 `agent_docs/checks/migration_proof.md`→未忽略、`rtl|board|sim|tb|tools|_proj_pcie|hls` 下探名→未忽略（这些目录靠各自子树规则，不受本次注释改动影响）。

## 5. 刻意排除（2 类 14 条，均非"根相对裸名引用"）

| 类别 | 位置 | 条数 | 理由 |
|---|---|---|---|
| 文档标题自指 | `agent_docs/*.md` 第 1 行 ×9（P6B_CDC_AUDIT / P6B_COMMIT_PLAN / P6B_INTEGRATION_REVIEW / P6B_REVIEW / P6B_SPEC / P6B_SUMMARY / P7A_COMMIT_PLAN / P7A_SPEC / P7B_SPEC） | 9 | `# NAME — …` 是**自指命名**不是指针；加前缀渲染成 `# agent_docs/NAME — …` 属损坏（改写时曾机械改写，人工复览后逐字回退） |
| README 目录树路径段 | `README.md:25-40`（``` 围栏树图，并发会话新增）内 `P6B_SUMMARY.md / P6E_OBS.md / P7B_SPEC.md / PORT_NOTES.md / ISSUE_RX_BYTE_CORRUPTION.md` | 5 | 树内条目相对 `agent_docs/` **树根**；加前缀会渲染成 `agent_docs/agent_docs/…` |

## 6. 已知过期行号清单（迁移前既存，照抄方案 §2.5 两条，逐字登记）

1. `agent_docs/P6B_REVIEW.md:30`：「README 2026-09-30 结构性重写**前**为 `README.md:69,155`」
2. `_proj_10g/notes/P7B_COMMIT_PLAN2.md:170`：「(README 2026-09-30 重写前 :287,308)」

现状：`README.md` 已被并发会话重写为 46 行（2026-10-13），上述指向旧 README 行号的引用**今日更加过期**，但按方案纪律（行号订正=内容订正，另案处理）本迁移一律只改路径、原样保留行号。

## 7. Markdown 链接深度修复（判据 4）——实测为零

- 改写前对 16 份 LIVE 文件全量扫描 `](...)` 内联链接与 `[label]: path` 引用式链接：**0 个**（该仓文档体系用根相对裸名约定，不用 markdown 链接）。
- 移动后复查 14 份文档内部链接：无同目录互链、无指向 `README.md`/根文件/子目录的链接，**无需深度修复**（0 处）。
- 并发重写后的现行 README 含 2 个真链接：`[agent_docs/P6B_SUMMARY.md](agent_docs/P6B_SUMMARY.md)`（根相对，深度正确 ✓）与 `[docs/INDEX.md](docs/INDEX.md)`（属另一路 `docs/` 导读层迁移，非本任务范围，目标尚不存在，由该路负责）。
- **修复数 M = 0**（已验证，非"未检查"）。

## 8. dry-run diff 样本（改写器先 dry-run 人工过目后才 `--apply`，照抄 fix_docs.py 惯例）

```
-.gitignore 245:-# 见 ISSUE_RX_BYTE_CORRUPTION.md —— 只保留 TB/驱动源码与查询脚本/报告
+.gitignore 245:+# 见 agent_docs/ISSUE_RX_BYTE_CORRUPTION.md —— 只保留 TB/驱动源码与查询脚本/报告
-README.md:-| 10G 施工规格（闸序 / 66 条正判据 + 9 条负对照） | `P7B_SPEC.md` |
+README.md:+| 10G 施工规格（闸序 / 66 条正判据 + 9 条负对照） | `agent_docs/P7B_SPEC.md` |
-agent_docs/P6B_ACCEPT.md:-| E4 | 上板：最小帧洪泛下 `stat_drop_full`（W34）增量 **恒 0** | 【先例】`P6E_OBS.md:80` | ΔW34 = 0 |
+agent_docs/P6B_ACCEPT.md:+| E4 | 上板：最小帧洪泛下 `stat_drop_full`（W34）增量 **恒 0** | 【先例】`agent_docs/P6E_OBS.md:80` | ΔW34 = 0 |
-agent_docs/P6B_REVIEW.md:-         P6B_REVIEW.md §3.4 与附录 R (含"撤回修复即 FAIL"的负对照)。
+agent_docs/P6B_REVIEW.md:+         agent_docs/P6B_REVIEW.md §3.4 与附录 R (含"撤回修复即 FAIL"的负对照)。
-agent_docs/P7A_COMMIT_PLAN.md:-#   ⭐ 放行 P7A_SPEC §1.1/§1.2/§1.3/§10 逐字引用的**文本读数**(合计 324 KB):
+agent_docs/P7A_COMMIT_PLAN.md:+#   ⭐ 放行 agent_docs/P7A_SPEC §1.1/§1.2/§1.3/§10 逐字引用的**文本读数**(合计 324 KB):
```

（`.gitignore` 段、`README.md` 表格段、`P6B_ACCEPT` 的"路径+行号"段、`P7A_COMMIT_PLAN` 的裸名+§段均有代表；全部 592 个 +/- 行逐类抽查，无功能性读文档行——与方案 §2.3"零功能性依赖"结论一致。）

## 9. 负对照留证

**NC-主（悬挂引用归零）**：取 `P7A_RESULT`（避开 §5 两类刻意排除，13 份 HISTORICAL 中 0 命中）：

| 范围 | 改写前旧形态 | 现旧形态 |
|---|---|---|
| 可写区合计（旧 README 2 + .gitignore 1） | **3** | **0** |

**NC-检查器不空跑**：本任务未新建常驻检查器（方案 §5.1 的 `tools/check_docrefs.py` 属 `tools/` 边界区，本任务禁止新建）；以"改写器幂等复跑=0 改动 + 反例自测 8 条全不命中 + 三层计数对账 364=332+14+…"代替，且全部数字在报告中给出可复算口径。
**NC-守卫**：`sim/p4gates/` 属边界区，未跑未改（§10.6）。

## 10. 异常与新情况（停下登记，未自作主张扩大改动面）

1. **`.gitignore:839` CRLF 空模式怪象（git 2.54.0.windows.1）**：第 839 行是**空行**（od 实测仅 `\n`），但 `git check-ignore -v agent_docs/` 报告"`.gitignore:839:` + 空 pattern"命中；对**任何**带尾斜杠的新目录名（`newdirtest/`、`docs/`）同样报命中，而目录下文件（`agent_docs/x.md`）实测**未被忽略**，`git add agent_docs/checks/...` 正常入库（exit 0）。临时仓库对照实验证实：CRLF 行尾下空行会被 check-ignore 报成"空 pattern 命中目录"。结论：**纯报告层怪象，不影响 add/status**，未改动 .gitignore 任何模式行（仅改 10 行注释）。注意方案 §3.3 曾实测 `docs/` 未被忽略——该结论在当前 HEAD 已不成立（同一怪象所致），但如前述对实际入库无影响。
2. **执行中主干被并发推进**：基线 `f1d81cd` 后他人提交 `d7ebafd`（台架恢复轮，只动 `_proj_10g/`，0 引用命中，三层计数复测不变）。移动提交 `0c55470` 因此落在 `d7ebafd` 之上。
3. **README.md 被并发会话整体重写**（582→46 行，2026-10-13 01:24:52，落在我的改写 apply 之后 41 秒）：新 README 已采用 `agent_docs/` 新形态 + 新增目录树（§5 排除项）。其删除的 23 条已改写引用不再存在于库中（对账见 §3）。该文件随提交②一并入库。
4. **`agent_docs/` 在 .gitignore 中被"忽略"是假象**——同 10.1，不再赘述。
5. **工作树前置状态**：开工时非完全干净（`_proj_10g/.../tcpreg_program_stdout.txt` 有未暂存修改，属边界区，未触碰；已由 `d7ebafd` 一并提交）。
6. **`sim/p4gates/p4env.bat` 注释引用（1 处 `P6B_INTEGRATION_REVIEW.md`）**：方案 §3.2 曾建议改+指纹三件套；该文件在 `sim/` 边界区内，**本任务禁止修改**，登记为边界悬挂（计入 §11 的 sim 区 84 处）。
7. **非 git 层悬挂（仓库外，未处置）**：`D:\repo\XCKU5PMini\CLAUDE.md` 实测 **3 处**（行 169 `P6B_CDC_AUDIT.md`、328/346 `PORT_NOTES.md`；方案 §2.4 记的是 1 处/行 160，该文件已演变）。方案处置 A 需要把备份入库到 `_proj_10g/notes/evidence/`——**属本任务硬边界，未执行**；处置 B 的"头部注记"会改动 14 份文档内容、超出任务书改写范围，亦未执行。登记为**已知悬挂，待用户裁决**。
8. **记忆层（仓库外）**：`~/.claude/projects/D--repo-XCKU5PMini/memory/` 实测 **11 处 / 5 文件**（xcku5p-mini-10g-board 3、perfv-udp-eco-migration 4、feedback_agent_workflow 2、p4b7-p6-freeze-saga 1、udp-hls-10g-rx-byte-corruption 1），与方案 §2.4 一致。按方案 R7：不属仓库交付物，**不处置**。
9. **未发现**任务书/方案未覆盖的新形态：无二进制内引用（未跟踪 18 路径与已跟踪文本全覆盖 grep）；无 ` udp_hls_eco/` 外仓引用落在可写区（3 处均在 `board/*.xdc` 边界区，保持原样）。

## 11. HISTORICAL allowlist（可写区内 31 条，逐条 file:line，一律未改）

| 文件:行 | 命中名 | 类别判定 |
|---|---|---|
| audit_scratch/t1_bits/tb_cdc_bits.v:116 | P6B_CDC_AUDIT | P6b 审计轮 TB 留档（注释引文） |
| audit_scratch/t3_txcdc/tb_tx_cdc_chain.v:118 | P6B_CDC_AUDIT | 同上 |
| review_scratch/rw/tb_rvw_macrx.v:4 | P6B_SPEC | P6b 对抗审查 S3 TB 留档 |
| int_scratch/neg5/axi_regs.v:24 | P6B_SPEC | 负对照病理副本（方案 U9 判定不改） |
| int_scratch/neg5/axi_regs.v:31 | P6E_OBS.md | 同上 |
| int_scratch/negbase/axi_regs.v:24 | P6B_SPEC | 同上 |
| int_scratch/negbase/axi_regs.v:31 | P6E_OBS.md | 同上 |
| int_scratch/mutseq/snap_seq.v:5,39,44,51 | P6B_SPEC ×4 | 变异实验副本 |
| p6b_accept_final/srv_p6b_final_accept.sh:11,11,13,14,15,16,20,22,30,298 | P6E_OBS.md×4, P6B_INTEGRATION_REVIEW.md, P6B_SPEC×3, P6B_CDC_AUDIT, P6B_ACCEPT.md | 冻结验收证据束（frozen bit + 日志 + pcap 同目录）主机侧脚本 |
| p6b_final_verify/cdc_parse.py:8,86 | P6B_SPEC ×2 | 验收轮工具（与证据同束，判读对象已冻结） |
| p6b_final_verify/cdc_parsed.txt:35 | P6B_SPEC | 生成证据清单（方案 U10） |
| p6b_final_verify/t3_f2/tb_tx_cdc_chain.v:118 | P6B_CDC_AUDIT | 验收轮 TB 留档 |
| _tmp_w9probe/mut/app_udp_pattern_fix.v:125,191 | ISSUE_RX_BYTE_CORRUPTION ×2 | w9 变异/暂存副本 |
| _tmp_w9verify/head_rtl/app_udp_pattern.v:125,191 | ISSUE_RX_BYTE_CORRUPTION ×2 | w9 实验快照 |
| _tmp_w9verify/wt_rtl/app_udp_pattern.v:130,196 | ISSUE_RX_BYTE_CORRUPTION ×2 | w9 实验快照 |

## 12. 边界区悬挂登记（本任务硬边界，一律未改）

| 区域 | 文件数 | 旧形态命中数 |
|---|---|---|
| `_proj_10g/**` | 143 | **1395** |
| `sim/**`（含 `p4gates/evidence` 快照 26+1、`p4env.bat` 1、指纹快照 3、head_rtl 等） | 39 | **84** |
| `board/**`（含 `wrapper_p4.v` 28、eco xdc 外仓引用 3） | 11 | **41** |
| `rtl/**` | 9 | **26** |
| `_proj_pcie/**` | 4 | **12** |
| `tools/**` | 6 | **9** |
| `CLAUDE.md`（根，硬约束留根） | 1 | **8** |
| `tb/**` | 4 | **4** |
| `hls/` `vivado_prj/` | 0 | 0 |
| **合计（边界区）** | **217** | **1579** |

（全仓含旧形态命中的文件总数 = 217 边界 + 29 可写 = **246**。其中历史快照/证据类——`sim/p4gates/evidence/*` 27、指纹快照 3、`_proj_10g/notes/p7b_*` 实验副本与台账等——占绝大多数，本就不该改；其余为边界区内的活注释指针，按任务书登记为"边界约束接受的悬挂"。）

## 13. 复算口令（全部只读）

```bash
cd /d/repo/XCKU5PMini/udp_hls_10g
MOVED='PORT_NOTES|P6B_ACCEPT|P6B_CDC_AUDIT|P6B_COMMIT_PLAN|P6B_INTEGRATION_REVIEW|P6B_REVIEW|P6B_SPEC|P6B_SUMMARY|P6E_OBS|P7A_COMMIT_PLAN|P7A_RESULT|P7A_SPEC|P7B_SPEC|ISSUE_RX_BYTE_CORRUPTION'
OLD='(?<![A-Za-z0-9_./\\-])('"$MOVED"')(\.md)?(?![A-Za-z0-9_.-])'
NEW='(?<![A-Za-z0-9_./\\-])agent_docs/('"$MOVED"')(\.md)?(?![A-Za-z0-9_.-])'
git grep -c -P "$OLD" | wc -l                 # 全仓旧形态文件数（=217 边界+13 HIST+16 可写LIVE=246；本报告自述的命中名列/样本引用亦计自身, 属证据自引）
git grep -c -P "$NEW" | wc -l                 # 新形态（332 处改写产物 + 本报告内的新形态自述）
git diff -M --name-status 0c55470^..0c55470   # 14 行 R100
git show --stat 9205fb7 | tail -3             # 提交② diffstat
```
