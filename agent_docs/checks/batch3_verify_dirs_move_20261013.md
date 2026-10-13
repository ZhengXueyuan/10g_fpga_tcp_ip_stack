# 第三批证明报告：15 个验证/审查目录 → agent_docs/（2026-10-13）

**指令**：owner「要的」= 同族目录同批处置（桥内 ack）。**边界**：`_proj_10g/**` 与 `_proj_pcie/` 不重写不移动。
**提交**（本地，未 push）：

| 提交 | 消息 |
|---|---|
| `dcb3fde` | docs: 第三批 15 个验证/审查目录迁入 agent_docs/（纯移动，441 件 R100） |
| `30d2253` | docs: 第三批引用改写至 agent_docs/<名>/（_proj_10g 与 _proj_pcie 之外 312 处） |
| （本报告 + MAPPING/INDEX） | docs: 第三批迁移证明 + 索引/映射同步 |

## 0. 摸底对账（独立复测 vs 桥内口径）

| 口径 | 桥内 | 独立复测 | 差异说明 |
|---|---|---|---|
| 引用文件总数 | 127 文件 | `git grep -l <名>/`（含 `_pcie/` 误吞 `_proj_pcie/` 前缀）752；裸前缀修正后 **295** | 桥内疑似只数了 notes 相关子集或不含目录自身引用 |
| 其中 _proj_10g | "约 25 件" | **459 文件**（裸前缀口径 848 处） | 桥内数字与实测差一个量级；以实测为准 |
| 目录自身引用 | — | 191 文件（在 15 目录内） | 桥内未列 |
| 跟踪件数 | 441（22+9+5+51+132+40+66+6+26+32+18+13+21） | **441 ✓ 逐目录吻合** | — |
| 忽略目录盘上有内容 | 已提示 | p5d_verify 42 件 · whs_reroll_probe 3067 件 ✓ | 已随目录 mv |

## 1. 纯移动判据（提交① `dcb3fde`）

逐目录 `git mv <名> agent_docs/<名>`（13 个有跟踪件目录）+ 裸 `mv`（p5d_verify/ whs_reroll_probe/ 两个全忽略目录）。
**目录形 git mv 把被忽略残渣一并带走**（旧路径零残留实测）；p6b_accept_final/ 的 8 个未跟踪件
（含 `frozen_p6b_final.bit` 15 MB）随迁，跟踪状态不变。

`git diff --cached -M --name-status --diff-filter=R` = **441 行 R100**；`--numstat` 437 件 `0 0` +
4 件 xvlog.log 二进制记 `- -`（相似度仍 100%）；`--diff-filter=AMD` **空**。逐目录行数：
audit_scratch 132 · p5diag_verify 66 · _tmp_w9verify 51 · int_scratch 40 · p6_verify 32 ·
p5f_verify 26 · _p7a_probe 22 · p6a_ku5p_verify 18 · p6b_accept_final 13 · p6b_final_verify 21 ·
_p7a_probe 22 · _pcie 9 · p5e_verify 6 · _tmp_w9probe 5 = 441 ✓（全量输出 = 提交①本身）。

## 2. 功能性依赖分诊（27 个脚本逐个过）

判定树：注释/散文 → 随改写；功能行按解析基准 —— `%ROOT%`/`%REPO_ROOT%`/绝对路径（仓根锚定）→ **随改写**
（不改写则移动后脚本必断）；`%~dp0` 自定位（工作目录随脚本走，无需改）；一次性工具/证据快照 → 不改。

| 文件 | 判定 | 依据 |
|---|---|---|
| audit_scratch/run_t{1,2,3,4}.bat | **改**（功能行+%~dp0 并存） | `set ROOT=D:\repo\...` 硬编码仓根 + `cd %~dp0t1_bits\...`（自定位工作目录随迁，无需动）；`%ROOT%\audit_scratch\t1_bits\tb_cdc_bits.v` 等编译源路径**不随迁必断** → 随改写（P1 反斜杠段规则，保界符） |
| p6b_final_verify/run_t3_f2.bat · _gen_t3bat.py | **改** | `set P=%ROOT%\p6b_final_verify\t3_f2`（工作根）；生成器字符串同改保持再生成一致 |
| p6_verify/run_p6_verify.bat · run_p6_worst_ep.bat | **改** | `%REPO_ROOT%\p6_verify\*.tcl`（仓根锚定） |
| p6a_ku5p_verify/run_p6a_verify.bat | **改** | `D:\repo\XCKU5PMini\udp_hls_10g\p6a_ku5p_verify\p6a_verify.tcl` 硬编码绝对路径 |
| p5e_verify/hier_util_p5e.tcl | **改** | `%REPO_ROOT%/p5e_verify/p5e_util_hier.rpt` |
| p6b_accept_final/program_p6b_final.tcl | **改** | `set bit D:/.../udp_hls_10g/p6b_accept_final/frozen_p6b_final.bit` —— .bit 已随迁，不改则烧录脚本断 |
| tools/board_rounds_v{4..7}_batch.sh | **改** | `cd %REPO_ROOT%` + `P=p5diag_verify/vN`（仓根相对） |
| tools/rxp_digest.py · regress_mactx.py ×2 · run_controls.py · 全部 verify .tcl · 构建 tcl/xdc | **改**（注释/字符串/散文） | 根相对指针与用法示例 |
| sim/run_tb_tx.bat 注记的 ECO 句 | **不改 ECO 侧** | `D:\repo\ECO\udp_hls_10g\...` = 外仓（仍在磁盘）；P1 加 `(?<!ECO.udp_hls_10g)` 定宽负 lookbehind 免疫；该句只改写本仓侧的 `audit_scratch/regress_mactx.py` 指针 |

## 3. 引用改写（提交② `30d2253`，47 文件 312 处）

改写器三规则（幂等，复跑 0；反例自测含 `agent_docs/<名>` 新形态 / ECO 锚定 / 双前缀）：
P1 路径段 `(?<!agent_docs)(?<!ECO.udp_hls_10g)([/\\])(NAME)(?=[/\\])`（覆盖 `%ROOT%`、
`%REPO_ROOT%`、绝对路径两种斜杠）；P2 裸前缀正斜杠；P3 裸前缀反斜杠。字节级保真（rb/wb）。

构成：18 md（含 CLAUDE.md 1 与 12 份已迁文档 + _pcie/README）· 27 脚本 · 4 v/xdc 注释 ·
.gitignore 47 行（模式+注释路径保鲜，逐行 diff 核验无越界行）。

**不改登记**：证据类工具输出 175 文件（.log/.rpt/.out/.txt/.jou——绝对路径段与命令行回显，
改写=伪造运行记录）· `sim/p7b_stagec_tx_regress/head_rtl/` 冻结副本（前两轮已定 HISTORICAL）·
`sim/p4gates/evidence/` 全部快照 · `agent_docs/checks/out_of_repo_fixes_20261013/` 改前副本
（必须与父仓原件逐字节一致，供回滚）· 未跟踪 `_tmp_*.py` ×2 · `.claude/worktrees/` 镜像。

## 4. .gitignore 保鲜（提交②内，47 行 +/-）

涉及行（逐条改 `agent_docs/` 前缀，不重排）：注释 109/138/139/232/257/265/268/339/404/420/
446/463/499/580/581/645 等 + 模式行 `whs_reroll_probe/`(233) `p5d_verify/`(234)
`p5diag_verify/*` 块(261–272) `p5f_verify/*`(284–288) `p5e_verify/*`(310–312)
`!_pcie/*.log`(370) `!p6b_accept_final/*`(471–472) `!audit_scratch/**/*.log`(483)
`!int_scratch/**/*.log`(485) `audit_scratch/**/*.backup.log`(584) `_p7a_probe/` 块(524–542)。
`_proj_pcie/` 诸行（377–402/467–474/488–491/836–837）**不动**（该目录不迁）。

哨兵（`git check-ignore -v`，移动+改写前后一致）：

```
BEFORE  p5d_verify/x.rpt               <- .gitignore:234:p5d_verify/
        whs_reroll_probe/logs/x.log    <- .gitignore:233:whs_reroll_probe/
AFTER   agent_docs/p5d_verify/x.rpt               <- .gitignore:234:agent_docs/p5d_verify/
        agent_docs/whs_reroll_probe/logs/x.log    <- .gitignore:233:agent_docs/whs_reroll_probe/
```

且 `git status` 实测两目录 3109 件残渣**未被开始跟踪** ✓。

## 5. 终态 grep 证明（裸前缀口径 `(?<![A-Za-z0-9_/\\])<名>/`，Python 实测）

- **`_proj_10g/` 与 `_proj_pcie/` 之外：356 处 / 21 文件，LIVE 悬空 = 0**，全部登记：

  ```
  313  sim/p4gates/evidence/ sweep_absolute_paths 120 · sweep_code_files 74 · sweep_summary 26
       · inventory_eco_class / pathfix_applied / pathfix_dryrun / sweep_eco_files 各 23   (审计快照)
   21  agent_docs/p5f_verify/*.log ×7 (bramscan/hold_scan/hold_uniq/rxhold/rxsetup/ufpin/verify_p5f)
   16  agent_docs/checks/migration_proof.md              (本系列报告自述引用)
    2  sim/p7b_stagec_tx_regress/head_rtl/mac_tx_64.v    (第二轮 HISTORICAL 冻结副本)
    2  agent_docs/checks/out_of_repo_fixes_20261013/ 改前副本 ×2 (owner 证据束, 须逐字节一致)
    1  agent_docs/checks/review_scratch_move_20261013.md (自述)
    1  agent_docs/p5diag_verify/samples_v2_model.txt     (仪器原始读数)
    1  agent_docs/p5f_verify/holdfix_build.log           (工具输出)
  ```

- 新形态 `agent_docs/<名>/`：仓外 291 处（改写 312 处中的功能型引用部分计入各自文件）。
- `_proj_10g/` 内 848 处 · `_proj_pcie/` 内 5 处：不动，MAPPING.md 第 16–30 行兜底。
- 根 README.md：0 引用（核实，未动）。

## 6. 复算口令（只读）

```bash
cd /d/repo/XCKU5PMini/udp_hls_10g
git diff -M --name-status dcb3fde^..dcb3fde | grep -c '^R100'   # 441
git show --stat 30d2253 | tail -2                                  # 47 files 288/288
git ls-files agent_docs | wc -l                                    # 14+78+441+checks/...
git check-ignore -v agent_docs/p5d_verify/x.rpt                    # 234 行命中
```
