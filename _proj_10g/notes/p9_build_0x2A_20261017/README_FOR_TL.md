# 0x2A 构建轮（p9_build_0x2A_20261017）—— 构建 + 矩阵 + 读侧同步（**不烧板**）

- 轮次性质：**构建轮**。输入 = 孤儿修复实施轮收口提交 `0fad29b8`（工作树该三文件零改动已核）。
- 任务：0x2A 构建（唯一入口 `board/run_build_p7b_ku5p.bat`）+ 19 门矩阵（绑定构建输入）+
  读侧链式同步（实施轮未做）+ 归档。**未烧板、未碰 QSPI、构建期间未改任何源码**。
- 时间：2026-10-17 13:27 起。

---

## ① 构建前输入（现核，四个常量与派单描述一致）

| 项 | 现读 | 位置 |
|---|---|---|
| `.PERSIST_EN(1'b1)` | ✅（HEAD 是 0x29 拆刀态，已由实施轮还原） | `board/wrapper_p4.v:2276` |
| `BUILD_ID_V = 32'h0000002A` | ✅ | `board/wrapper_p4.v:4479` |
| `SNAP_NW_P6E = 76` | ✅ | `board/wrapper_p4.v:3394` |
| `SNAP_P7BDP_NW = 36` | ✅ | `board/wrapper_p4.v:3415` |

输入 sha256（构建前）：

```
214dac0964723f05f71153b6980bfed082a05940281e99064ba19ab410cafb71  board/wrapper_p4.v
3c58187ebd9f76af5130ed3d5b7bb7f62031123d566add9938bfd392c69ea430  rtl/app_ctrl.v
a2878bcd47df9d0135f2afeaf81fbefe63f8b7097eb56ca373a0b0c6d29f586c  rtl/slow_cfg_adp.v
```

（`env/INPUT_SHA256_3FILES.txt`；构建相位输入面 287 件 = `env/BUILD_INPUT_HASHES_BEFORE.txt`。）

## ② 构建读数

调用式 = `MSYS_NO_PATHCONV=1 cmd /c 'board\run_build_p7b_ku5p.bat'`（**单斜杠式**；未与 `//c` 并用）。
本次独有串 = `ARCHIVE_DONE 20261017_132801 files=19`。**BAT_RC = 0 / BUILD_EXIT = 0**（console 末 = `BITSTREAM-OK`）。

时间线：13:28:01 归档块（#54）→ 13:39:09 synth `Exiting Vivado`（`P7B_CONVERGED_AT_ROUND = 2`）→
14:05:56 routed DRC → 14:08:30 位流/`P7B DONE`。构建窗口 ~40 min。

| 项 | 读数 |
|---|---|
| **P7B_WNS / P7B_WHS** | **`+0.039` / `+0.010`**（`P7B_IS_LOCKED_POSTGEN = 0`） |
| **三类失败端点** | **`0 / 0 / 0`**（setup `0/262,227` · hold `0/262,227` · pulse-width `0/85,060`） |
| **`Slack (VIOLATED)`** | **0 条**；`All user specified timing constraints are met.` 在档 |
| **DRC（routed）** | **0 Error / 0 Critical**；`Checks found: 69`（五族 4/2/4/18/41 与 0x28 逐数相同） |
| **Route status** | `# of nets with routing errors = 0`；fully routed **139,173** |
| **XDMA 断言组** | `RC_BASE=0` · `RC_INTF=0`（`<AXI_Stream>`）· `RB_MISMATCH_N=0`（13/13）· `GEN_BAD_N=0`（6/6）· `CFGDIFF_ST_N=1` · `CFGDIFF_MM_N=2` · **`VERDICT = OK`** |
| **位流** | sha256 = **`aa44a0eda1604623eac951afc26b9f27d4798fc414a5eb9c7137ee47f9a2a3b6`** · **15,431,261 B** · **`SW_CRC=279a3872`** |
| **硬门（12 键）** | `DROPPED-CONSTRAINT-FAIL` / `IMPLICIT-NET-FAIL` / `DRC-KEY-FAIL` —— **全 0 命中** |
| **资源（只并列，不归因）** | placed **78,248 LUT / 75,360 FF** / 348 BRAM / 1 URAM / 4 DSP / 6 GTYE4；synth **62,681 LUT / 54,059 FF** / 312 BRAM / 1 URAM（0x28: placed 77,631/75,086/348/1；synth 62,180/53,628/312 ⇒ **+617 LUT / +274 FF（placed）· +501 LUT / +431 FF（synth）**） |
| **构建输入绑定** | `BUILD_INPUT_HASHES_BEFORE == AFTER`（**287 件，0 变**，`diff` rc=0） |

**全局 WNS 宿主（现读）** = `u_tcp_tx/u_fifo_b/rptr_reg[3]/C → u_app/stg_reg[26]/D`（`g_hw.clk_out0` 组，19 级，
logic 1.855 ns / route 4.371 ns，Slack +0.039）。⚠️ 与 0x28 的全局宿主（快照阵列异步复位族
`user_reset_reg → snap_words_r_reg[*]/CLR`）**是不同对象、不同检查类型**；按 #66 **只并列、不归因**
（WNS +0.065→+0.039 的差**不写成**"W75 的代价"）。

## ③ backstop（设计件 v4 §7.5）

- 预登记风险：W75 新增 1 字（+96 FF：32 宿主网 / 32 dout_a / 32 DP）落在 0x28 的全局 WNS
  宿主族（快照阵列异步复位族，0x28 = `+0.065` / 1.02%）。
- **结果：未触发**。一次构建收口：`WNS +0.039 / WHS +0.010 / 三类失败端点 0/0/0`，`Slack (VIOLATED) = 0`。
  WNS 为正且 0 失败端点 ⇒ **不需要砍 W75**（W75 在位，BID/几何 = 0x2A 完整形态）。
  ⚠️ 仍如实登记：WNS 从 0x28 的 `+0.065` 变为 `+0.039`（−0.026 ns = 周期 6.400 的 0.4%）；**宿主换族**
  （见 ② 末）⇒ 只并列不归因。

## ④ 矩阵（绑定构建输入）

调用式 = `MSYS_NO_PATHCONV=1 cmd /c 'sim\p4gates\run_matrix_p4dfix.bat'`（**单斜杠式**）。
时间 14:09:18–14:36:25（~27 min）。

| 项 | 读数 |
|---|---|
| **结果** | **19/19 门 `EXIT=0` · `gates failed: 0`** · `MATRIX_RC=0` |
| **冻结判据** | **`VERDICT: FROZEN`**（**272 件** before=after 逐位） · `DIGEST_COMPILE=23e5fefe9d4fd0e0260cd19826eb3631ea1a58084061eb6c282f555b5c0cd6bb` / `FILES_COMPILE=221` / `DIGEST_ALL=6d6ac35a0bdb0c52932f7f0d8136a0ed08a446e738f63bcb33a241ca97f522d3` / `GIT_HEAD=3d5a8262` |
| **swc 门** | `P9-SWC-GATE: PASS`（8 条编译见证在档） |
| **门相位输入完整性** | `GATES_INPUT_HASHES_BEFORE == AFTER`（**227 件，0 变**，`diff` rc=0） |

**漂移集合（vs `p9_build_0x28` 基线 `P4_MATRIX_FINGERPRINT_20261015_234333_after.txt`；原件 `gates/FP_DRIFT_vs_0x28.txt`）**：
**内容变化恰 4 件** · **ADDED 0 · GONE 0**（272 → 272）：
`board/wrapper_p4.v` · `rtl/app_ctrl.v` · `rtl/slow_cfg_adp.v` · `tb/tb_p5_wrapper.v`
= **孤儿修复实施轮交付面**（前 3 件 = 本刀构建输入；第 4 件 `tb/tb_p5_wrapper.v` **不在构建输入**、
只在本矩阵的 hash 宇宙，实施轮为基线臂显式传 `ORPHAN_EN_5=0/ZW_EN_5=0` 而改）。
另 5 件（`sim/f3_resync/mut/mut_m1.v`/`mut_m2.v` · `sim/p9_swc_gate/mut/m6_v1_eq.v`/`m6b_closing_drop.v`/`m7_guard_swpend.v`）
**hash 逐字相同、仅 mtime 变**（矩阵每轮重新生成 mutant）⇒ 不是内容漂移。
**vs 实施轮自己的 after 指纹**（`gates/FP_DRIFT_vs_implround_content.txt`）：**内容变化 0 件**（`grep -c '^[<>]'` = 0）。

## ⑤ 读侧同步（链式；实施轮未做，本轮补）

工具 = `_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py`。
本轮**新增两个链式阶段**（照 0x29 拆刀轮登记的"下一轮必须先把 0x29 落盘"要求）：

- **⑭ `0x00000029`（0x29 拆刀，75 字 / 0x15C）**：24 处 BID 面 edit；
- **⑮ `0x0000002A`（p9 孤儿修复，76 字 / 0x160）**：**初版 86 处 edit**（apply 时实际落盘 **110 处 = 24 + 86**）
  = BID 面 24 + 几何面 39 + **工具清单之外的 23 处常量读者**（p6e TB 的 **73 个 `32'h` MIR 地址 token**
  降序替换：`14C→150 / 150→154 / 154→158 / 158→15C / 15C→160`；`tb_biz_win.v` 的 BUILD_ID `0x08→0x2A`
  与 **MIR 地址改为由 NW 派生**）。⚠️ **门抓到的 3 处 TB 遗留常量已就地修正并补进 ⑮ 记录（现 88 处）**：
  ① `MIR_STATUS_A` 初版多写了 `+16`（= 未实现地址）⇒ 改 `0x20 + NW*4`；
  ② 11c 空读 MIR_DATA 还硬编码 `32'h140`（= W72）⇒ 改 `MIR_DATA_A`；
  ③ `MIR_STATUS.ver` 期望停在 3（P9 已 4）⇒ 改 4。
  （修正后 `tb_biz_win` 门 **40/40 PASS / `TB_BIZ_WIN_PASS`**。）

**阶段读数**：

| 阶段 | 读数 |
|---|---|
| 预检（spliced copy `--rehearse`，内存 overlay） | **全绿**（A 5/5 · B 4 族 495 命中 0 未登记 · C 全绿 · D 20/20） |
| apply | RC=0 · **2 阶段 / 110 处 edit / 0 fail**（`APPLY_READSIDE_BID OK`） |
| sha 快照 | apply 时快照 22 件中 **21 件变**（20 编辑目标 + 工具本体；第 22 件 = `P7B_BIZ_WINDOW.md` 在快照后另行 patch）⇒ **最终快照 22/22 全变**（`READ_SIDE_DIFF_FINAL.txt`，22 行；含 `tb_biz_win` 的 3 处门后修正） |
| assert（after） | RC=0 · **A 5/5**（WLABEL 76 / NAME {0..75} / W 表 76 / V 表 76 / FAKE_TAIL 16 条末条 0x160）· **B 4 族 495 命中 0 未登记** · **C 全绿** · **D 20/20** |
| negctl ×4（post） | `table` = **恰 1 红** · `bid` = **恰 1 红** · `tier` = **恰 1 红** · `face` = 3 红 —— **四条全有牙**（RC=1） |
| neg_rehearse（post，反演重建） | **`NEG_REHEARSE OK`**：故意漏 `final_state.sh` 的 UNIMPL 活行 ⇒ **恰 1 红**且落 `final_state.sh[UNIMPL]` |
| **p6e 双门（咬合见证）** | **wrapper `148 PASS / 0 FAIL` / `PASS_ALL` / RC=0** · **counters `26 PASS / 0 FAIL` / `PASS_ALL` / RC=0**（= 0x28 轮基数，MIR 地址迁移与 BID/UNIMPL 同步后逐字复现） |
| **`tb_biz_win` 门** | **`40 PASS / 0 FAIL` / `PASS_ALL` / `TB_BIZ_WIN_PASS` / RC=0**（窗口 76 字；含 MIR 四字地址↔值映射、UNIMPL 0x160、BID 0x2A）。⚠️ 初跑抓到我移植的 3 处常量错误（见上）⇒ **修正后全过** |
| 搜索面 census（`--face`） | **495 行 / 246 文件**（0x29 拆刀轮 census = 464/238；新增来自 0x29/0x2A 两轮目录） |

**同步清单（20 个编辑目标 + 工具 + 窗口文档）**：

1. `_proj_10g/notes/p7b_affinity/j6_r6fix.sh`
2. `_proj_10g/notes/p7b_biz_tcpreg/tcpreg_j6.sh`
3. `_proj_pcie/p7b_biz/p7b_snap.sh`
4. `_proj_pcie/p6e_snap_check.sh`
5. `_proj_pcie/p7b_gate4_accept.sh`
6. `_proj_pcie/p7b_gate4_selftest.sh`
7. `_proj_pcie/p7b_gate4_negctrl.sh`
8. `_proj_pcie/p7b_gate4_livefake.sh`
9. `_proj_pcie/p6e_snap_selftest_fix2.sh`
10. `_proj_10g/notes/p7b_gate4_3/final_state.sh`
11. `_proj_10g/notes/p7b_gate4_criteria/gen_inputs.py`
12. `_proj_10g/p7b_chain/sim/tb_p7b_chain.v`
13. `_proj_10g/notes/p7b_biz_win/run_xvlog_wrapper.bat`
14. `_proj_10g/notes/p7b_biz_win/run_tb_biz_win.bat`
15. `sim/p5wu_p1p2/run_xvlog_wrapper63.bat`
16. `_proj_10g/notes/p7b_biz_win/tb_biz_win.v`
17. `_proj_10g/notes/p7b_biz_win/check_window.py`
18. `sim/p6e_pcie/tb_p6e_pcie_counters.v`
19. `sim/p6e_pcie/tb_p6e_pcie_wrapper.v`
20. `_proj_10g/notes/p7b_a3_negctl_20261010/step0_selfcheck.sh`
+ `_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py`（工具本体：+2 阶段 / +24 调用 / STAGES / ALLOW / tb_biz_win BID 断言）
+ `_proj_10g/notes/P7B_BIZ_WINDOW.md`（§1 补 W70..W75 + 现役 76 字 / UNIMPL 0x160）

## ⑥ 归档与偏离

### 归档（`_proj_10g/notes/p9_build_0x2A_20261017/`）

- `build/`：`BUILD_CONSOLE.txt`（含 `BUILD_EXIT=0`/`BITSTREAM-OK`）· `READINGS_BID2A.txt` ·
  `BIT_SHA256_BID2A.txt` · `wrapper_p4.bit` · `wrapper_p4_routed.dcp` · `board_rpt/`（15 件：impl/synth 报告 +
  4 个 board 报告 + `p7b_ku5p_stdout.txt` + `p7b_ku5p_xdma_cfg_post_gen.txt`）· `_collect_build_0x2A.py`
- `gates/`：`MATRIX_STDOUT.txt` · `matrix_p4dfix.log` · `P4_MATRIX_FINGERPRINT_20261017_140918_{before,after}.txt` ·
  `MATRIX_TAIL.txt` · `FP_DRIFT_vs_0x28.txt` · `FP_DRIFT_vs_implround*.txt` · `GATES_INPUT_HASHES_{BEFORE,AFTER,DIFF}.txt`
- `readside/`：生成器/拼接器/负彩排器 · `APPLY_BID2A_OUTPUT.txt` · `ASSERT_BID2A_FINAL.txt` ·
  `TARGET_SHA_{BEFORE,AFTER,FINAL}_BID2A.txt` · `READ_SIDE_DIFF_{NUMSTAT,FINAL}.txt` · `NEGCTL_*_2A_POST.txt` ·
  `NEG_REHEARSE_2A_POST.txt` · `P6E_{WRAPPER,COUNTERS}_AFTER_console.txt` · `FACE_2A{,_FINAL}.txt` · `REHEARSE_2A.txt`
- `env/`：`INPUT_SHA256_3FILES.txt` · `BUILD_INPUT_HASHES_{BEFORE,AFTER,DIFF}.txt`
- 构建前自动归档（#54）= `_proj_10g/notes/p7b_build_archive/20261017_132801/`（19 件；其中 `wrapper_p4.bit`
  sha256 = `9c9675436b5084a483b50d846d52a2b27ca56992ba90fe1761b3d4d6cd595e7e` = **0x29 拆刀位流**，provenance 已核）。
- ⚠️ 按仓规 `.gitignore`：`*.bit` / `*.dcp` **不入库**，归档留盘；`p7b_build_archive/**/SHA256SUMS.txt` 是白名单件。

### 与派单/描述的偏离（如实）

1. **构建读数核到与描述一致**：`.PERSIST_EN(1'b1)` / `BUILD_ID_V=0x2A` / `SNAP_NW_P6E=76` /
   `SNAP_P7BDP_NW=36` 四处现读全中（行号 `:2276` / `:4479` / `:3394` / `:3415`）。
2. **backstop 未触发**（`WNS +0.039 > 0`、`0/0/0`）⇒ **未砍 W75**；W75 在位，BID/几何 = 完整 0x2A 形态。
3. **新增 0x29 阶段**：按 0x29 拆刀轮 README §1.4 的登记（"下一轮要落 0x2A 时必须先把 0x29 阶段落盘"）
   ⇒ 链表现有 15 个阶段（…0x28 → 0x29 → 0x2A），最终 tarBID = 0x2A。⚠️ 0x29 是 75 字 / 0x15C 的
   **非功能代**（0x28 内容 + `PERSIST_EN=0`），其 stage 只做 BID 面 24 处。
4. **`EDITS_28[41]` 的 new 侧是 stale**（0x28 审查轮 E-1 修掉了 `if/elif` 重放行但没回写工具）⇒
   ⑮ 的 75 分支改从**盘上现读**提取（`gen_edits_29_2A.py` 特例），未改 EDITS_28 历史阶段。
5. **`tb_biz_win.v` 原本落后两代**（NW 被 0x28 抬到 75，但 MIR 地址仍是 M1 的 0x13C/0x144/0x148/0x14C，
   `BUILD_ID_V` 仍是 0x08）⇒ 本轮一并纠正：MIR 地址**由 NW 派生**、BUILD_ID 0x08 → 0x2A，并**新增
   DEFAULT_SPECS 断言**（再漂就红）。⚠️ **初版派生式写成 `0x20+NW*4+16`（那是 UNIMPL）**，
   加上 11c 的硬编码 `32'h140` 与 `ver==3` 的 stale 期望 ⇒ **`tb_biz_win` 门初跑 11 项红**；
   按门的读数就地修正 3 处后 **40/40 PASS**（原件 = `readside/TB_BIZ_WIN_AFTER_console{,2,3}.txt`）。
   这正是"三件常量读者"被点名的原因 —— **不跑门就看不见**。
6. **p6e TB 的 73 个 `32'h` MIR 常量**用**降序 token 替换**（避免级联）；不是逐行手改。148/0 门已咬合。
7. **`P7B_BIZ_WINDOW.md` 的 §1 表此前停在 W69**（0x28 轮未更新）⇒ 本轮补 W70..W75 并把未实现地址
   改为 0x160（含逐代回溯）。
8. **矩阵漂移的"第 4 件"** = `tb/tb_p5_wrapper.v`：它**不在构建输入**（287 件不含），只在矩阵 hash 宇宙；
   实施轮为基线臂显式传 `ORPHAN_EN_5=0/ZW_EN_5=0` 而改 ⇒ 属本刀交付面、可解释。
9. **未提交 git**（按 0x28 轮纪律，提交归 TL）。tracked 修改恰 **30 件** = 20 读侧目标件 + 工具 +
   `P7B_BIZ_WINDOW.md` + 5 个 `board/p7b_ku5p_*.rpt/ stdout` 构建产物 + `sim/p4sim/matrix_p4dfix.log` +
   **2 个 `_proj_10g/notes/p7b_biz_win/{xelab,xsim}_biz.log`**（跑 `tb_biz_win` 门时被重写的 tracked 门日志）；
   轮目录整目录为 untracked（81 件，含 `SHA256SUMS.txt`）。
10. **未烧板 / 未碰 QSPI**（板当前现役 = 0x28，未动）。
