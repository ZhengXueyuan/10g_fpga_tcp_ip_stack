# 构建轮 `0x25` 报告（F-3 修复：读侧同步 + 回归矩阵 + G1 进矩阵 + 构建 + 归档）

> agent 原件由平台拒写 .md ⇒ 全文回传、TL 代落盘（文末「TL 附加」= 抽核与裁定）。
> 轮次目录 = `_proj_10g/notes/p9_build_0x25/` · HEAD = `2a6eebe`（全程未提交，改动留工作树）
> **口径**：本报告**不下 PASS/FAIL 裁定**；给的是读数与形态。「未观测到」≠「不存在」。
> **纪律**：⛔ 未烧板 / 未写 QSPI / 未碰对端机 / 未动被验源（`git diff --stat -- board/wrapper_p4.v rtl/vlan_strip.v` = **空**）；xsim 与 Vivado 全程按序。

---

## ① 读侧同步 `--bid 0x25`（阶段 ⑩ = `EDITS_25`；24 处 / 14 文件；几何**一字未动**）

**做法照抄 0x24 轮**：`gen_edits25.py`（从 `EDITS_24` 的 new 侧逐条 +1 代；**old 侧自检 24/24 逐字命中盘上现状**）→ `splice_phase10.py`（6 锚点**唯一命中**：`EDITS_25` 声明 / `E10()` / `STAGES` 追加 `("0x00000025", …, 71, 0x14C)` / ⑯ 段插入 / docstring ⑩ 指针 / ALLOW 追加 4 条）。⚠️ 一处自伤已修：ALLOW 描述串里写了未转义 `"` ⇒ 工具 `SyntaxError`；修法 = 改用无内嵌引号的逐字叙述 + `ast.parse` 复检后全链重跑。

**调用式**：`C:/Users/zhxue/anaconda3/python.exe _proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py --bid 0x25 [--apply]`（⚠️ 派单写的 `_proj_10g/tools/apply_readside_bid1c.py` 不存在；实际 = 上路径，0x1C/0x1D 先例同目录）。

### 逐文件 hunk 清单（`git diff --numstat`；每文件 = 1 hunk）

| # | 文件（仓根相对） | +/− | hunk 内容（BID 值/代名 0x24→0x25 + 历史链追加） |
|---|---|---|---|
| 1 | `_proj_10g/notes/p7b_affinity/j6_r6fix.sh` | +2/−1 | `EXPECT_BID` 默认 0x24→0x25（注释换「F-3 修复」）+ GEOM_TIERS 顶部插 `71\|0x00000025\|…` 行 |
| 2 | `_proj_10g/notes/p7b_biz_tcpreg/tcpreg_j6.sh` | +2/−1 | 同上 |
| 3 | `_proj_pcie/p7b_biz/p7b_snap.sh` | +4/−2 | `EXPECT_BID` 裸行 + 头部「现役」块顶部插 F-3 块 |
| 4 | `_proj_pcie/p6e_snap_check.sh` | +1/−1 | `EXPECT_BID` 默认 + 历史链移一格 |
| 5 | `_proj_pcie/p7b_gate4_accept.sh` | +1/−1 | 同上 |
| 6 | `_proj_pcie/p7b_gate4_selftest.sh` | +4/−4 | 现役注释行 + `FAKE_BID` 活行 + 旧口径行 |
| 7 | `_proj_pcie/p7b_gate4_negctrl.sh` | +3/−2 | 几何注释块顶部插新行 + `echo "BID 0x…25"` 活行 |
| 8 | `_proj_pcie/p7b_gate4_livefake.sh` | +4/−2 | 注释块顶部插新块 + `bid = {71: "0x…25", …}` 活行 |
| 9 | `_proj_pcie/p6e_snap_selftest_fix2.sh` | +1/−1 | `FAKE_BID` 活行 |
| 10 | `_proj_10g/notes/p7b_gate4_3/final_state.sh` | +1/−1 | `EXPECT_BID` |
| 11 | `_proj_10g/notes/p7b_gate4_criteria/gen_inputs.py` | +6/−5 | docstring 几何行 + 夹具自述 + 逐代链 + `BID_FIX` |
| 12 | `_proj_10g/notes/p7b_a3_negctl_20261010/step0_selfcheck.sh` | +2/−2 | 缺省档/默认档两行 |
| 13 | `sim/p6e_pcie/tb_p6e_pcie_wrapper.v` | +1/−1 | **:215** 活行 `chk("2  BUILD_ID (F-3 修复 构建 = 0x25)", v, 32'h00000025);` |
| 14 | `sim/p6e_pcie/tb_p6e_pcie_counters.v` | +1/−1 | **:206** 活行 `chk("0b BUILD_ID (F-3 修复 71-word = 0x25; 原 71-word=0x24(P9 URAM 板内缓冲) / 0x23(P9 D4 clr 口径修正) / 63-word=9)"` |
| 15 | `_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py`（工具本体） | +111/−2 | 阶段 ⑩ 全部（声明/E10/STAGES/⑯ 段 24 条 E10/⑩ 指针/ALLOW 4 条） |

**全阶段读数**（原件 = 本目录同名 txt）

| 阶段 | 读数 |
|---|---|
| 预扫 | 目标 0x25 搜索面 4 族 361 行 / 178 文件 / **未登记 11 件** → 逐条核 → ALLOW 4 条 |
| dry-run | **24/24 `hits=1/1`**；B 面 4 族 364 命中文件 **未登记 0**；C 24 红 = 待改处；D 覆盖 14/14；A 5/5 绿 |
| rehearse | **全绿 0 fail** |
| negctl ×4 | `table` 1 红 · `bid` 24 红（含目标）· `tier` 24 红（含目标）· `face` 3 红 —— **四条全有牙** |
| neg_rehearse | **恰 1 红** = 末条（`step0_selfcheck.sh[BID]`） |
| apply | RC=0 / 0 fail；**14/14 件 SHA256 全变** |
| assert（after） | RC=0；A 5/5 · B 4 族 **356 命中 0 未登记** · C 全绿 · D 14/14 |
| face | 356 行 / 179 文件（未登记 0） |
| post negctl ×4 + 反演重建 | 四条仍有牙（1/1/1/3 红，含目标）；反演重建恰 1 红 |

**B 面 11 件未登记的处置（逐条核过）**：`p9_board_0x24_20261013/`（3 件，烧/读 **0x24** 位流现场，`WANT=e3b07957…f1db` 钉死）· `p9_uram_ab_20261014/`（4 件，同会话 A/B 六烧 **0x23↔0x24** 交替，各臂 WANT/EXPID = 那两代真值）· `p9_xverify_kimi_board24_20261013/`（2 件，kimi 组板级 0x24 复核轮）· `p9_build_0x25/`（2 件 = 本轮生成器自身）⇒ **ALLOW 4 条，全部只登记不动**。

**几何不变量（派单点名核）**：NW 保持 **71**、未实现地址保持 **0x14C** —— A 表长断言 5/5 绿 + `board/wrapper_p4.v:3266` 现读 `SNAP_NW_P6E = 71` / `:4322` `BUILD_ID_V = 32'h00000025`（权威源两侧一致）。三个读侧默认哨兵现读 0x00000025（`j6_r6fix.sh:76` / `tcpreg_j6.sh:70` / `p7b_snap.sh:69`）。

---

## ② p6e 门读数（修前 / 修后对）

**修前 = TB 保持 0x24 期望（= 提交态 2a6eebe 原样），修后 = TB 同步 0x25**（同一棵树、只差两处 TB 期望值；恢复后 sha 与 post-apply 逐字节相同，已核）。⚠️ 时间线里 00:55:34 的 `xsim_p6e_30788.backup.log`（144/0）经标签核 = **上一轮（F-3 实施轮）自己的 A/B 跑**，非本轮。

| 门 | 修前 | 修后 |
|---|---|---|
| **全链门** `run_tb_p6e_pcie.bat` | **143 `[PASS]` / 1 `[FAIL]`**（唯一 FAIL = `2 BUILD_ID … = 00000025 (期望 00000024)`）**RC=1** | **144 `[PASS]` / 0 `[FAIL]` / `PASS_ALL`** **RC=0** |
| **counters 门** `run_tb_p6e_pcie_counters.bat` | **24 `[PASS]` / 2 `[FAIL]`**（① `0b BUILD_ID = 37 (期望 36)`；② **`H1 W27 = 5 (期望 256)`**）**RC=1** | **25 `[PASS]` / 1 `[FAIL]`**（只剩 H1）**RC=1** |

原始证据（本目录）：`_evidence_xsim_p6e_wrapper_{BEFORE_18908,AFTER}.log`、`_evidence_xsim_p6e_cnt_{BEFORE_19636,AFTER}.log`；console 捕获 `P6E_*_{BEFORE,AFTER}.txt`。

⇒ **全链门修后 = 144/0 PASS_ALL（与派单预期一致）**。⛔ **counters 门 H1 红不是读侧同步引入**：修前态（同树）已红，且提交态 2a6eebe 原样下同样成立 —— 见 ⑤-异常#1。

---

## ③ 矩阵：17 门漂移核验 + 重基线记录 + G1 进矩阵（18 门）

### ③-1 17 门 run1（01:10:55–01:38:18）

- **17/17 门 `EXIT=0` · `gates failed: 0` · `VERDICT: FROZEN`**（257 件 before=after **逐位**；`DIGEST_COMPILE=e1e7c1e5…` / `DIGEST_ALL=83c80ce7…` / `HEAD=2a6eebe`）。
- **漂移集合核验（vs 0x24 基线 `P4_MATRIX_FINGERPRINT_20261013_075711_after.txt`）**：**CONTENT-CHANGED 恰 2 = `{rtl/vlan_strip.v, board/wrapper_p4.v}`**；ADDED 0 / GONE 0（257=257）⇒ 与派单预期一致（第二件 = 同一提交的另一半：wrapper 的 `VLAN_STRIP_RESYNC` 绑定）。原件 = `FP_DRIFT_vs_0x24.txt`。
- **重基线记录（理由 = 参数 + 门 + 计数；⛔ 不以"指纹变了/没变"充当等价证据）**：① 参数 = `rtl/vlan_strip.v` 新参数 `RESYNC_EN`（默认 0）+ wrapper `VLAN_STRIP_RESYNC` localparam（双域=1/单域=0）；② 门 = 新门 G1（5 臂：F 全绿 / L 逐字复现历史缺陷形态 / M1·M2 有牙 / CTRL 正对照）；③ 计数 = `stat_resync_words`（五臂闭合 `pop_post == taken_post + rsw`）。结构性等价证据（设计 §2.4-I1）：`RESYNC_EN=0 ⇒ fwd≡1 ⇒ acc_f≡acc` 常数折叠；行为证据：`unit_vlan` 逐字绿 + L 臂与 t9 历史形态逐字同形。
- **gate 相位输入完整性**：`INPUT_HASHES_BEFORE_GATES == AFTER_GATES`（217 件，**0 变**）⇒ 27 min 内无其它写入。

### ③-2 G3：G1 进矩阵（照 `faee172` 先例；门计数走派生值）

改动 4 处（全部机器验证过）：
1. **新件** `sim/p4gates/f3resync_src.f`（8 件声明清单；DUT 三变体各恰出现一次）。
2. **`sim/f3_resync/run_tb_f3_resync.bat` 重构**（+60/−29）：门头换 p4env + `selfcheck` tripwire + `checkpaths`；`ARMBASE=%P4_WORKDIR%`（matrix 私有 cwd；单跑=历史 `%HERE%`）；编译拆成**公共单元 1 行 + DUT 三变体互斥 3 行 + TB 1 行**；**五臂判据（:chkF/:chkL/:chkM1/:chkM2/:chkC + 见证）逐字未动**。
3. **`run_matrix_p4dfix.bat`**：p5_wrapper 行后追加第 18 行 `call :gate f3_resync … f3resync_src.f - -`（既有 17 行一字未动）。
4. **`sim/p4gates/paths.txt`**：`FINGERPRINT_GLOBS` +2 = `sim\f3_resync\run_*.bat` + `sim\f3_resync\mut\mk_mut_f3.py`。

**落地验证**：`manifestcheck` = `8 files == manifest`（RC=0）· `selfcheck` RC=0 · `checkpaths` RC=0 · `parse_gate_calls` = **18 行**（末行 = `('f3_resync', 'sim\\f3_resync\\run_tb_f3_resync.bat', 'f3resync_src.f', '-', '-')`）· **bat 保持 ASCII+CRLF**（189 CRLF / 0 非 ASCII）· **mut 重生成逐字节相同**（m1 `49fd69ce…` / m2 `4fdc480a…` = 入库件）⇒ 跑中重生成不破 freeze。

### ③-3 18 门 run2（01:46:04–02:12:33）

- **18/18 门 `EXIT=0` · `gates failed: 0` · `VERDICT: FROZEN`**（**264 件** before=after 逐位；`DIGEST_COMPILE=05c9dd30…` / `DIGEST_ALL=074a01d2…`（content-v1 摘要 `085883ac…`）/ `HEAD=2a6eebe`）。
- **`f3_resync` 门段**：`checkpaths 10 路径 OK` · `manifestcheck 8==8 OK` · `scanlog 1 文件 5 路径 0 外泄` · `EXIT=0`；五臂 RC 全 0；`F3R CHK` 五行与实施轮 + 单跑**逐字相同**（F `ALL=1` / L `J1=0 J2=0 J3eq=1 J3pos=0 J5=0 ALL=0` / M1 `J3eq=0` / M2 `J3eq=0 J3pos=1` / CTRL `ALL=1 J3pos=0`）；末行 **`F3-RESYNC-GATE: PASS`**。
- **run1→run2 指纹差（逐条）**：CHANGED 2 = `{sim/p4gates/paths.txt, run_matrix_p4dfix.bat}`（G3 自身）；ADDED 7 = `{rtl/fifo_async.v, mk_mut_f3.py, mut_m1.v, mut_m2.v, run_tb_f3_resync.bat, tb_f3_resync.v, f3resync_src.f}`；GONE 0（257→264）。原件 = `FP_DRIFT_run1_to_run2.txt` / `FP_DRIFT_vs_0x24_run2.txt`。⚠️ `rtl/fifo_async.v` 进清单是**首见**（此前不在任何 manifest）—— 它被新门编译，属新增覆盖、非漂移。

---

## ④ 构建 `0x25`（唯一入口 `board/run_build_p7b_ku5p.bat`，一次收口）

**调用式** = `MSYS_NO_PATHCONV=1 cmd /c 'board\run_build_p7b_ku5p.bat'`（**单斜杠式**；⛔ 未与 `//c` 并用）。**本次独有串** = `ARCHIVE_DONE 20261015_021446 files=19`（BAT_RC=0）。

**时间线**：

| 时刻 | 事件 |
|---|---|
| 02:14:46 | 归档块先跑（#54）：`p7b_build_archive/20261015_021446/`，19 件；**内含上一代位流 `wrapper_p4.bit` sha256 = `e3b07957…f1db` = 0x24 位流**（provenance 已核） |
| 02:25:08 | synth `Exiting Vivado`（`P7B_CONVERGED_AT_ROUND = 2`；`P7B_ROUND #1 MISMATCH_N = 5` → `#2 = 0`） |
| 02:44:14 / 02:44:17 | 位流落盘（bit 头时间戳）/ impl `Exiting Vivado` |
| 02:45:21 / 02:45:22 | 父进程 `Exiting Vivado` / bat console 收尾（`BITSTREAM-OK`） |

**收口读数（逐项）**：

| 项 | 读数 |
|---|---|
| **BAT_RC / BUILD_EXIT** | **0 / 0**（console 末 = `BITSTREAM-OK`） |
| **一次收口（计数式）** | `P7B_ROUND #1` 恰 **1** 次 · `BUILD_EXIT` 恰 1 · `P7B DONE` 恰 1 · `Exiting Vivado` 恰 **3** 条 |
| **P7B_WNS / P7B_WHS** | **+0.044 / +0.010**（`IS_LOCKED_POSTGEN = 0`；`P7B_NFILES = 443` = 0x24 同） |
| **三类失败端点** | **0 / 0 / 0**（setup 0/258,663 · hold 0/258,663 · pulse-width 0/84,255；`Slack (VIOLATED)` **0 条**；`All user specified timing constraints are met.` 在档） |
| **位流** | sha256 = **`faefa444e0d02ef9969d069d773614d65ace9583f51fd58c553463299db54c85`** · **15,431,261 B** · **`SW_CRC=742b1a69`** · routed dcp 62,992,977 B |
| **硬门（12 键）** | `DROPPED-CONSTRAINT-FAIL` / `IMPLICIT-NET-FAIL`（5 键）/ `DRC-KEY-FAIL`（6 键）**全 0 命中** |
| **DRC（routed）** | **0 Error / 0 Critical**；Warning 五族（DPIP-2 4 · DPOP-3 2 · DPOP-4 4 · DPOR-2 18 · REQP-1858 41 = 69 checks）与 0x24 **逐数相同** |
| **Route status** | `routing errors = 0` |
| **日志面** | impl 末步 `576 Infos, 12 Warnings, 2 Critical Warnings, 0 Errors`；2 条 CRITICAL WARNING = **既存** `18-1056` + `12-1790` |
| **XDMA 断言组** | `RC_BASE=0` · `RC_INTF=0`（`<AXI_Stream>`）· `RB_MISMATCH_N=0`（13/13）· `GEN_BAD_N=0`（6/6）· `CFGDIFF_ST_N=1` · `CFGDIFF_MM_N=2` · `VERDICT=OK` |
| **资源（只并列，不归因）** | placed 78,228 LUT / 74,567 FF / 348 BRAM / 1 URAM / 4 DSP / 10 IOB / 6 GTYE4；synth 62,760 LUT / 53,114 FF / 312 BRAM（0x24: placed 78,068/74,508/348/1；synth 62,763/53,113/312） |
| **构建期间绑定** | `BUILD_INPUT_HASHES{,_AFTER}.txt`（287 件源集）**0 变**（窗口 02:14:46–02:53:54） |

**归档清单（`_proj_10g/notes/p9_build_0x25/`，#54）**：`wrapper_p4.bit` · `wrapper_p4_routed.dcp` · `board_rpt/`（**14 件**）· `build_stdout_full.txt` · `p7b_ku5p_stdout.txt` · 全部读数/原件 txt · `SHA256SUMS.txt`（70 件）。⚠️ 按仓规 `.gitignore`：`*.bit`（:54）与 `*.dcp`（:340）**均不入库**（与 0x24 惯例同）——归档留盘。

---

## ⑤ 偏离 / 异常（逐条如实）

1. ⛔ **异常#1（最重要）：p6e counters 门 H1 红 = F-3 与合成激励的交互，且从未被登记**。
   - **读数**：修前/修后同形 —— `H 读数(灌满后): W26=3 W27=5`；`H1 W27 == DEPTH` 期望 256 实读 **5**（FAIL）；排空后 `W30=320 W31=2560`（H3/H4/H5 过）。全链门同轮 144/0（真 MAC 激励有 SOP）。
   - **不是我引入的**：`tb_p6e_pcie_counters.v` 全程**不含 `tuser` 字样**（grep 0 命中；H 段 force 的是 `rxsrc_tvalid/tdata/tkeep/tlast` + `vs_tready`，从不给 SOP）⇒ 与两处 BID 期望值无关。
   - **是 F-3 引起的（读数 + RTL 双向可核）**：合成激励下 vlan_strip（`RESYNC_EN=1`）的 `resync` 永不武装（`fwd = resync || s_axis_tuser`，tuser≡0）⇒ `s_axis_tready ≡ od_free ≡ 1`（不产生输出 ⇒ `m_axis_tvalid` 恒 0）⇒ 输入字**持续被消费后丢弃**，`u_rxcdc` 永不累积（W27=5）。数字自洽：`W30=320 = 400×125/156.25`、`W31 = 8×W30`。
   - **前 F-3 对照**：`sim/p6e_pcie/xsim_p6e_cnt_*.backup.log` 全 5 份（10-13 各时段）**逐字相同** `W26=69 W27=256 … PASS_ALL` ⇒ 该判据在 F-3 之前成立、之后不可达（同一激励）。
   - **登记面缺口**：设计件 §4.3-② 的"必须重跑"清单**不含 counters 门** ⇒ 该后果未被任何设计件/实施件登记；实施轮 G2 只跑了全链门（其"激励来自真 MAC ⇒ 首个交付字必是 SOP"的论证对本门合成激励**不成立**）。
   - **未做的事（自限）**：**没有**改 TB 激励语义（例如补 drive 一个 SOP）——那属于改判据/门本体，留裁定；本报告只登记形态。
2. ⚠️ **派单路径笔误（已按先例纠正）**：派单写 `_proj_10g/tools/apply_readside_bid1c.py` —— 实际工具在 `_proj_10g/notes/p7b_readside_bid1c_20261011/`。
3. ⚠️ **工具语法自伤一处（已修）**：splice 的 ALLOW 描述里内嵌未转义 `"` ⇒ `SyntaxError`；修 + `ast.parse` 复检后全链重跑。
4. ⚠️ **归档/产物类 git 变更（预期内）**：构建重写 `board/p7b_ku5p_{timing,util,drc,clkinteract}.rpt` + `p7b_ku5p_stdout.txt`；`sim/p4sim/matrix_p4dfix.log` 被 run2 重写。均非源码改动（源集 hash 0 变已证）。
5. ⚠️ **资源差分只登记不归因**：placed LUT +160 / FF +59（synth −3 LUT / +1 FF）—— **无拆刀 A/B ⇒ 不归因**（#66）。
6. ⚠️ **未做（明说）**：**定向时序查询（`q_0x25.tcl`）未跑** —— 派单收口清单未要求；`board_rpt/` 已有 routed 全量报告可供后续定向查询。
7. ⚠️ **未烧板**：本轮到"位流 + 归档"为止；板上现役仍是上一态，烧录属后续板级轮。
8. ⚠️ **P7B_WPWS 读数口径提醒**：stdout 的 `P7B_WPPS` 列表最小 = 0.010，而 routed 报告表 pulse-width 段显示 `0.000`（failing 0）—— 两口径并列，不在此裁定（历史各轮同形态）。

----------------------------------------------------------------

## TL 附加（2026-10-15 02:2x；抽核 + 裁定）

**抽核**：位流 `sha256sum` 现读 = **`faefa444…4c85`** 逐字吻合；工作树 24 个 `M` 与报告逐条对应（13 读侧 + 2 TB + 3 门件 + 5 板产物 + 1 sim 日志）；`*.bit`/`*.dcp` 经 `git check-ignore` 证实**均被 .gitignore 覆盖**（0x24 惯例同，归档留盘不入库）；无残留 Vivado/xsim 进程。
**裁定**：
1. **H1（counters 门）= 门激励面问题，非板面缺陷**：在轨证据 = 全链门（真 MAC 激励）144/0；板级唯一激励源 = 真 MAC ⇒ 首个交付字必是 SOP ⇒ 新 `resync` 门在板上自然满足。**处置 = 最小激励修复**：counters 门 H 段激励**前置一个 SOP（tuser 脉冲）** ⇒ 重跑预期 `PASS_ALL`；修后须带"激励 vs 历史基线差异"注记复核；**不改判据语义**。另登记：设计 §4.3-② 重跑清单缺 counters 门 = 设计覆盖缺口（列入设计文档订正项）。
2. **定向 STA**：接受"全量 routed 报告在档"；`q_0x25.tcl` 定向查询列为可选后补（不阻塞）。
3. **资源 +160 LUT / +59 FF**：登记不归因（#66）。
4. 读侧同步 24/24 唯一命中 + 四负控有牙 + 几何不变量双核 = **接受**；`/` 调用式的单斜杠纪律已照既有坑执行。
**口径**：以上为读数与形态；判据层裁定权在 owner。
