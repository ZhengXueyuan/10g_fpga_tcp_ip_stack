# 构建轮 `0x28` 报告（E12 观测计数器位流收口：BID bump + 读侧同步 + p6e 双门复跑 + 19 门矩阵 + 构建 + 归档 + 定向 STA）

> **agent 原件由平台拒写 .md ⇒ 全文回传、TL 代落盘**（本件正文 = agent 原文；文末 = TL 抽核附加块）。
> **口径**：本报告**不下 PASS/FAIL 裁定**（裁定权在用户/判据所有者）；给的是读数与形态。「未观测到」≠「不存在」。
> 轮次目录 = `D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_build_0x28\` · HEAD = `4b22d1a`（全程未提交，改动留工作树）
> **纪律**：⛔ 未烧板 / 未写 QSPI / 未碰对端机；xsim 与 Vivado **严格串行**（门→矩阵→构建→STA 全程无并行）；收尾复核 **0 个残留 `xsim/xelab/vivado` 进程**。
> **被验源（冻结）双核**：`rtl/app_pattern.v` = **`c932c3ab304a321344ab4b8061cd759f1ea3a29000037e6ea1e28f73c8023582`**（E12 后；收尾现读复核）· `board/wrapper_p4.v` 改前 = **`bbf6e3cb953f9c8ce071be26f601d017ab84e764ab00b3a8f50047a63525ae47`**（= 派单值，逐字；另有改前备份件 `_wrapper_p4_pre_wrapper.bak` 同 sha 佐证）⇒ 改后 = **`3b39c85f509c09b0ce5ffb31014034f34d976f36bd1a2954b504c6e323dd68a2`**。`rtl/` 全目录**零改动**（唯一 diff 面 = wrapper 的 BID 单 hunk）。

---

## ① BID bump（`board/wrapper_p4.v`，**单 hunk +28/−2**）

`git diff --numstat` = **28 / 2**；`git diff -U0 | grep -c "^@@"` = **1**（`:4377` 起）：

- 活行 **`:4377`**：`32'h00000027` → **`32'h00000028`**（行尾注释 `换流门 R5 = 0x27` → `E12 观测计数器 = 0x28`）；
- 注释块顶部插新块（本轮 = **E12 四计数器**：`stat_up_ev`/`stat_sw_req`/`stat_sw_apply`/`stat_up_pend`；`rtl/app_pattern.v` +48/−1；**几何变 71 → 75 字 / `SNAP_P7BDP_NW` 31 → 35 / 未实现地址 0x14C → 0x15C**；读侧 = `EXPECT_BID` 0x27→0x28 + NW 默认值 + 标签表；依据 = `p9_impl_e12_20261015/REPORT.md`），旧块（R5）前插 `//   ---- (以下为历史, 逐字保留) ----` 分隔并**降级为「⭐ 上一轮」逐字保留**。
- ⛔ **禁碰区核**（app 寄存器总线静止块）：`assign app_reg_addr = 8'h00;` / `app_reg_wr = 1'b0;` / `app_reg_wdata = 32'd0;` 现读 **`:1345-1347`**，`git diff | grep -c "app_reg"` = **0** ⇒ 一字未动（全文件仅 1 hunk 即证；派单写的 `:1319-1322` 是历史轮行号，**内容**核过 = 同一块）。
- 行尾纪律：编辑后 **CRLF 5025 / loneCR 0**（首次写入曾引入 26 处裸 LF，已现场归一为全 CRLF 并复核；最终计数逐字）。

---

## ② 读侧同步 `--bid 0x28`（阶段 ⑬；**BID + 几何**：24 + 39 = **63 处 / 20 文件**）

工具 = `_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py`（本阶段工具本体 +255/−3，含 EDITS_28 块 63 条 + 4 处顶层 splice + ALLOW 7 条）。

### ②-1 **本轮读侧面比历轮宽**（E12 §2.3 第 4-7 条为准）—— 逐条现读实施

- **BID 面 24 处 / 14 文件** = 阶段 ⑫ 清单逐条 +1 代（生成器 `gen_edits28.py` 的 f0..f23，逐条**显式**变换；old 侧自检 **24/24 逐字命中盘上现状**）；
- **几何面 39 处（本轮新增，手写锚点）** =
  · **NW 默认值 71 → 75**：`j6_r6fix.sh:75` · `tcpreg_j6.sh:69` · `p7b_snap.sh:72` · `p6e_snap_check.sh:72` · `p7b_gate4_accept.sh:137` · `p7b_gate4_selftest.sh:37` · `p7b_gate4_negctrl.sh`（`awk -v NW=` + 循环界）· `gen_inputs.py`（`NW_FIX`）· `tb_biz_win.v` · 三个指纹 bat（`SNAP_NW_P6E = 75`）；
  · **未实现地址 0x14C → 0x15C**：`final_state.sh`（`rd 0x14c→0x15c` 活行 + 注 + W71..W74 读数行）· `tb_p7b_chain.v`（`axil_read 0x14C→0x15C` + 判据名 + 界注）· 各脚本 UNIMPL 注释/formula 注；
  · **标签表补 W71..W74**：`p6e_snap_check.sh` `WLABEL += 4`（表长 71→75）· `p7b_snap.sh` `NAME[] += [71..74]` · `p7b_gate4_selftest.sh` **新 FAKE_TAIL 分支 `if -ge 75`**（旧 `-ge 71` 分支逐字保留降为 elif；新表 15 条地址 = 0X114..0X148 + 0X15C）· `p7b_gate4_negctrl.sh` `V=` +8 项 / 循环界 75 · `p7b_gate4_livefake.sh` `[0]*20 → [0]*24` · `p6e_snap_selftest_fix2.sh` 假板地址表（+0X13C..0X148 / 0X14C→0X15C）· `check_window.py` `nnew_top 5→9`（派生式 `nnew_top+ntx+nnew == NW-51` 现 = 9+1+14 = **24 = 75-51** ✓）。
- ⚠️ **生成器首版 G6 写错并当场废弃**（把 75 表塞进 `-ge 71` 分支尾 + 复制了一个 71 分支 ⇒ rehearse 抓出 `表长断言异常: substring not found`）⇒ 改为「新分支 + 旧分支逐字保留」的构造式（从盘上现读的 `_TAIL71` 派生）后 **rehearse 全绿**。**仓内文件在 dry-run/rehearse 阶段零写入**（只 print 块文本）。

### ②-2 全阶段读数（原件 = 本目录同名 txt）

| 阶段 | 读数 |
|---|---|
| 预扫（`--face --bid 0x28`，`PRESCAN_0x28.txt`） | 4 族 **436 行 / 216 文件**；**未登记 0**（新增 ALLOW **7 条**：本轮轮目录 + `p9_impl_e12_20261015/` + `p9_board_0x27_k0_20261015/` + `p9_board_rfcseq_20261015/` + `p9_mdio_board_20261015/` + `p9_simfill_20261015/` + `sim/f3_resync/`；另订正 `check_window` 的 ALLOW 措辞「几何本轮不动」→「E12 起几何动了」） |
| dry-run | **63/63 `hits=1/1`**；48 `FAIL` = **待改处**（A 5 表 + C 43 默认值/派生）；B 4 族 436 命中 **未登记 0**；D `EDIT_COVERAGE 20/20 OK` |
| rehearse | **`REHEARSE OK —— 全绿 ⇒ 清单完整且自洽`（0 fail）** |
| negctl ×4（apply 前） | `table` **NEGCTL_EXIT=1**（5 红：4 表待改 + 注入的末项删除）· `bid` =1（43 红）· `tier` =1（43 红）· `face` =1（3 红 = 合成未登记件被抓）—— **四条全有牙** |
| neg_rehearse（apply 前） | **`NEG_REHEARSE OK`**：故意漏 `final_state.sh` 的 UNIMPL 活行 ⇒ **恰 1 红**且落 `final_state.sh[UNIMPL]` |
| apply | RC=0 / **0 fail**（`APPLY_READSIDE_BID OK (target 0x00000028, 1 阶段 / 63 处 edit, 0 fail)`）；**20/20 件 SHA256 全变**（`TARGET_SHA_BEFORE_BID28.txt` ↔ `AFTER` 逐条比，0 件未变） |
| assert（after；`ASSERT_BID28_FINAL.txt`） | RC=0；**A 5/5**（含 `FAKE_TAIL 地址条数 = 15 / 期望 15 (末条 0x15C)`）· **B 4 族 436 命中 0 未登记** · **C 全绿** · **D 20/20** |
| post negctl ×4 | `table`/`bid`/`tier` 各 **恰 1 红**（注入项）+ `face` 3 红 —— **仍有牙** |
| 反演重建（post；new→old，内存） | **`NEG_REHEARSE(post) OK`**：恰 1 红且落 `final_state.sh` |

**几何不变量（双核 + 机器核）**：**NW = 75**（权威源 `board/wrapper_p4.v:3296` `localparam SNAP_NW_P6E = 75;` 现读 **+** 工具 A 表长断言 5/5 绿）· **未实现地址 = 0x15C**（wrapper 装配注 `= word 87` + C 段 4 处 UNIMPL 规格全绿）。三个读侧默认哨兵现读 **0x00000028**（`j6_r6fix.sh:76` / `tcpreg_j6.sh:70` / `p7b_snap.sh:77`）。`GEOM_TIERS` 顶部新行 = `"75|0x00000028|61 62|…"`（旧 0x27 行逐字保留于下）。

**残留审查**（新侧提到 `0x00000027` 的 8 处逐条核）：**全部是刻意的历史/映射保留**（2 处 EXPECT_BID 行尾历史链 · 2 处 `GEOM_TIERS` 历史档行 · 1 处 EXPECT_BID「原默认」链 · 1 处 selftest 注释的旧口径指引 · 1 处 livefake 按 NW 索引的 `71: "0x00000027"` 槽 · 1 处 `BID_FIX` 历史值）⇒ 无一处是"漏改的活值"。

---

## ③ p6e 双门读数（修前 / 修后对）

**修前 = wrapper 已 bump 到 0x28、两 TB 仍期望 0x27**（= 同步前的同一棵树；TB 同步步骤的"咬合力"见证）；**修后 = TB 同步 0x28**（阶段 ⑬ 的 24 处 BID 面同批落盘）。两次运行间**只差 TB 的两个期望值**。

| 门 | 修前 | 修后 |
|---|---|---|
| **全链门** `run_tb_p6e_pcie.bat` | **147 `[PASS]` / 1 `[FAIL]`**（唯一 FAIL = BID 判据：`= 00000028 (期望 00000027)`）**RC=1** | **148 `[PASS]` / 0 `[FAIL]` / `PASS_ALL`** **RC=0**（= E12 后的新基数 148） |
| **counters 门** `run_tb_p6e_pcie_counters.bat` | **25 `[PASS]` / 1 `[FAIL]`**（唯一 FAIL = BID 判据：`= 40 (期望 39)`）**RC=1** | **26 `[PASS]` / 0 `[FAIL]` / `PASS_ALL`** **RC=0** |

**H 段读数两臂逐字相同**（派单点名"任何变化 ⇒ 停下报我" ⇒ **无变化**）：`H 读数(灌满后): W26=69 W27=256` · `H 读数(排空后): W30=257 W31=2056 W0=0`。
原始证据：`P6E_{WRAPPER,COUNTERS}_{BEFORE,AFTER}_console.txt`。

---

## ④ 常驻矩阵（**19 门**；run1 23:43:33–00:12:53）

- **19/19 门 `EXIT=0` · `gates failed: 0`** · **`VERDICT: FROZEN`**（**272 件** before=after 逐位；`DIGEST_COMPILE=cf79c89853a5bae98094c03961178ccb2aa71c0aaf0be601ef1f2831a279bec3` / `FILES_COMPILE=221` / `DIGEST_ALL=92510c517db9f98e2750d7e5f482ea2841fce57ee95afece3a5a7dcd8d8663df` / `FILES_ALL=272` / `HEAD=4b22d1a`）。
- swc 门在矩阵里：`P9-SWC-GATE: PASS` + **8 条编译见证**（`RSRC=…app_pattern.v` / `head_app_pattern.v` / 三 mutant，逐行 DEFS 全对；`SWC_GATE_MATRIX_console.log` 已归档）。
- 归档副本：`P4_MATRIX_FINGERPRINT_20261015_234333_{before,after}.txt` + `matrix_stdout_run1.txt` + `MATRIX_TAIL_run1.txt`。
- **漂移集合核验（vs 0x27 轮基线 `sim/p4sim/P4_MATRIX_FINGERPRINT_20261015_083428_after.txt`；原件 `FP_DRIFT_vs_0x27.txt`）**：**CONTENT-CHANGED 恰 7** · **ADDED 0** · **GONE 0**（272 → 272）：
  - 7 件 = **E12 实施面**：`board/wrapper_p4.v`（E12 几何 + 本刀 BID）· `rtl/app_pattern.v`（E12 +48/−1）· `sim/p9_swc_gate/{tb_p9_swc.v, run_tb_p9_swc.bat, mut/m6_v1_eq.v, mut/m6b_closing_drop.v, mut/m7_guard_swpend.v}`（E12 交付面）⇒ **全部可解释、0 超出**。
  - ⚠️ **两处与派单预期的实测差异（如实登记）**：① 派单列的 **`sim/p6e_pcie/tb_p6e_pcie_wrapper.v` 不在**矩阵指纹的 hash 宇宙（8 个 manifest 均不含 `sim/p6e_pcie/`，fp globs 也不含）⇒ **结构性不出现**（其同步证据 = ③ 双门 148/0）；② **读侧 20 文件同样不在**该宇宙（逐 manifest `grep -l` 核过）⇒ **"读侧面（14+ 文件）"不会出现在指纹漂移里**。⇒ 本轮指纹漂移的**可判面只有 7 件**。
- **门相位输入完整性**：`INPUT_HASHES_BEFORE_GATES == AFTER_GATES`（**227 件，0 变**，`diff` rc=0）⇒ 26 min 内无其它写入。

---

## ⑤ 构建 `0x28`（唯一入口 `board/run_build_p7b_ku5p.bat`，一次收口）

**调用式** = `MSYS_NO_PATHCONV=1 cmd /c 'board\run_build_p7b_ku5p.bat'`（**单斜杠式**；⛔ 未与 `//c` 并用）。**本次独有串** = `ARCHIVE_DONE 20261016_001456 files=19`（BAT_RC=0）。

**时间线**：00:14:56 归档块先跑（#54）→ synth `Exiting Vivado` ~00:28:49（`P7B_ROUND #1 MISMATCH_N = 5` → `#2 = 0`，`P7B_CONVERGED_AT_ROUND = 2`，与 0x27 逐字同）→ 位流落盘 ~00:52 → `P7B DONE` / 报告落盘 ~00:54。

**收口读数（逐项）**：

| 项 | 读数 |
|---|---|
| **BAT_RC / BUILD_EXIT** | **0 / 0**（console 末 = `BITSTREAM-OK`） |
| **一次收口（计数式）** | `^P7B_ROUND #1 ` 恰 **1** · `^P7B DONE$` 恰 **1**（裸 grep "P7B DONE" = 2，第二处 = tcl 源码回显）· `Exiting Vivado` 恰 **3** |
| **P7B_WNS / P7B_WHS** | **+0.065 / +0.010**（`P7B_IS_LOCKED_POSTGEN = 0`） |
| **三类失败端点** | **0 / 0 / 0**（setup `0/261,189` · hold `0/261,189` · pulse-width `0/84,774`；`Slack (VIOLATED)` **0 条**；`All user specified timing constraints are met.` 在档） |
| **位流** | sha256 = **`79c9cf434eb66723b97f654cbece9ea061632e2297c0a8ab0ea0dc198c43bec8`** · **15,431,261 B**（= 全代同尺寸）· **`SW_CRC=5a5cd561`**（`.bit` 头逐字读）· routed dcp 63,323,489 B 量级 |
| **硬门（12 键）** | `12-4739` / 隐式网五键 / DRC 六键 —— **全 0 命中**（逐键 `grep -c` = 0 复核过；console 0 条 `*-FAIL`） |
| **DRC（routed）** | **0 Error / 0 Critical**；**`Checks found: 69`**，五族 **4/2/4/18/41**（DPIP-2/DPOP-3/DPOP-4/DPOR-2/REQP-1858）与 0x27 **逐数相同** |
| **Route status** | `# of nets with routing errors = 0`；fully routed 138,098 |
| **XDMA 断言组** | `RC_BASE=0` · `RC_INTF=0`（`<AXI_Stream>`）· `RB_MISMATCH_N=0`（13/13）· `GEN_BAD_N=0`（6/6）· `CFGDIFF_ST_N=1` · `CFGDIFF_MM_N=2` · **`VERDICT = OK`**（与 0x27 逐字同） |
| **资源（只并列，不归因）** | placed **77,631 LUT / 75,086 FF** / 348 BRAM / 1 URAM / 4 DSP / 6 GTYE4；synth **62,180 LUT / 53,628 FF** / 312 BRAM / 1 URAM（0x27: placed 78,112/74,553/348/1；synth 62,790/53,114/312 ⇒ **−481 LUT / +533 FF（placed）· −610 LUT / +514 FF（synth）**） |
| **构建期间绑定** | `BUILD_INPUT_HASHES{,_AFTER}.txt`（**287 件**源集）**0 变**（窗口 00:14:56–00:54；`BUILD_INPUT_HASHES_DIFF.txt` = 空，`diff` rc=0） |

**归档清单（`_proj_10g/notes/p9_build_0x28/`，#54）**：`wrapper_p4.bit` · `wrapper_p4_routed.dcp` · `board_rpt/`（**15 件**：`p7b_ku5p_{timing,util,drc,clkinteract}.rpt` + `p7b_ku5p_stdout.txt` + `p7b_ku5p_xdma_cfg_post_gen.txt`（未跟踪产物）+ `runme_impl_1.log` + 8 件 impl_1/synth_1 wrapper 报告）· `p7b_ku5p_stdout.txt` · 全部读数/原件 txt · `SHA256SUMS.txt`（**84 件**）。
⚠️ 按仓规 `.gitignore`：`*.bit`（`:69`）与 `*.dcp`（`:355`）**均不入库** —— 归档留盘。另：**`_proj_10g/notes/p7b_build_archive/20261016_001456/SHA256SUMS.txt`**（sha256 `68bcaa5298f744a3342da7d77a203ce4a13e79a52f309cd0dd38d954dca27ce6`）是白名单件（`.gitignore:810 !…/SHA256SUMS.txt`）⇒ 随轮提交入库（**路径信息供 TL**）。**归档内 `wrapper_p4.bit` = `5c17b14f0656cf6680b7d16f7f1659faa4ca9225cf0cb0461765be7a91943385` = 0x27 位流**（provenance 已核 ✓ —— 归档跑在构建清空 `impl_1/` 之前）。

---

## ⑥ 定向 STA（`q_0x28.tcl`，**两代并列**：0x27 归档 dcp × 0x28 新 dcp）

> 调用式 = `run_q_x{27,28}.bat`（`-nojournal -nolog` 在 `-source` 之前；两 bat 复核 `bareLF=0 / nonascii=0 / CRLF=7`）。⛔ **无拆刀 ⇒ 差异含"本刀 + P&R 重排"两项、分不开 ⇒ 只登记不归因**（#66）。原件 = `q_stdout_x{27,28}.txt` + `query_out_x{27,28}/`。

### ⑥-1 ⭐ **核心判据：四个 E12 计数器锥是否进 DP/WNS 报告面** —— **没进**

| 项 | **0x27（前代）** | **0x28（本件）** |
|---|---|---|
| `e12_up_ev` / `sw_req` / `sw_apply` / `up_pend` 族 | **NOCELL**（0 cell —— 该代结构性不存在） | 各 **37 cell**；`from_worst` **5.261 / 5.250 / 5.352 / 5.259**（lvl 0–4）；`to_worst` **2.166 / 2.003 / 2.158 / 2.154** ⇒ **离 WNS(+0.065) ≥ 30×** |
| 四族 **DP 组内** from / to | NOCELL | `dp_from` 同上（5.25–5.35）· `dp_to` **2.003–4.098** ⇒ 同样远离 |
| **DP top-10 / top-50 / 全局 top-5 精确命中**（`stat_up_ev\|stat_sw_req\|stat_sw_apply\|stat_up_pend\|biz_w7\|app_up_ev`） | 0（两代**逐项 0 命中**） | **0 / 0 / 0** ⇒ **四计数器锥不在任何报告面** ✓ |
| `DP top50` 内 `u_app/` 精确命中 | 0 | **0**（松模式 `*u_app*` 的两代 20/0 全来自 `u_app_udp`/`u_app_ctrl`） |

⚠️ **但必须并列登记一条"进面"事实（不是四计数器本身的锥）**：本件**全局 WNS 宿主换成了快照阵列的异步复位族** ——
`G #1..3 = u_pcie_xdma/inst/pcie4_ip_i/inst/user_reset_reg/C → u_pcie_regs/snap_words_r_reg[{2224,2066,2277}]/CLR`（**+0.065 / lvl 0**）· `G #4 = …… → u_snap_p7bdp/dout_a_reg[961]/CLR`（+0.067）—— **E12 恰好把这个阵列扩大了**（`u_snap_p7bdp` 1521 → **1776** cell = +255 ≈ 4 字 × 32 × 2 级 CDC；`snap_words_r` 数组 2272 → 2400 位）。同一 slack 上并列的端点是 **2 个旧字（2066 = W64 位 18 / 2224 = W69 位 16）+ 1 个 E12 新字（2277 = W71 位 5）** ⇒ 形态 = **整个阵列的复位网**，不是 E12 字专属。**前代这一族 = `ref_snap_p7bdp to_worst 0.142`**（同宿主 `user_reset_reg → …dout_a_reg[*]/CLR`），前代全局 WNS 是 **DP setup +0.069**。⇒ **WNS 宿主换了对象且换了检查类型**（setup ↔ recovery），**⛔ 只并列、不归因**（无拆刀臂）；但**下一轮加逻辑时这一族就是新的第一观察对象**（余量 **+0.065 = 周期的 1.02%**）。

### ⑥-2 全局 / DP 域（原件 `q_stdout_x{27,28}.txt`）

| 项 | **0x27** | **0x28** |
|---|---|---|
| 全局 setup WNS | **+0.069** @ `u_tcp_tx/u_ackq/wptr_reg[1]/C → u_tcb/snd_nxt_r_reg[8][25]/CE`（lvl 14） | **+0.065** @ `u_pcie_xdma/…/user_reset_reg/C → u_pcie_regs/snap_words_r_reg[2224]/CLR`（**lvl 0**，recovery/异步复位族） |
| DP 域 WNS（`g_hw.clk_out0`） | **+0.069**（= 全局，同一对象） | **+0.068** @ `u_tcp_tx/u_retx/g_byte[1].mem_e_reg_2_bram_8/CLKBWRCLK → u_tcp_tx/ring_d_r_reg[61]/D`（lvl 11）⇒ **DP 与全局已不是同一对象** |
| DP top-10 起点 | 10/10 = `u_tcp_tx/u_ackq/wptr_reg[1]/C` | 3× `u_retx/g_byte[*].mem_e_reg_*_bram_8/CLKBWRCLK` + 7× `u_tcp_tx/u_fifo_a/wptr_reg[6]/C` |
| DP top-10 宿 | `u_tcb/*` + `u_tcp_tx/u_retx/*` | 全在 `u_tcp_tx/{ring_d_r, ps_stage_byte, u_retx}` 与 `u_tcb/{snd_nxt_r, snd_una_r}` |

### ⑥-3 `u_app`（app_pattern 实例）族 —— 两代并列

| 族 | **0x27** | **0x28** |
|---|---|---|
| `u_app/*` ncell | 2358 | **2496**（+138 ≈ 4×32 FF + 少量） |
| `u_app/*` from_worst | 1.676（sp=`u_app/FSM_sequential_rxs_reg/C`，ep=`u_mir/stg_data_reg[0]/D`） | **1.785**（sp=`u_app/rx_lfsr_reg[3]/C`，ep=`u_app/stat_mismatch_reg[31]/D`） |
| `u_app/*` to_worst | 0.146（sp=`u_app_ctrl/c_snd_una_reg[8][1]`，ep=`u_app/tx_lfsr_reg[21]/CE`） | **0.246**（sp=`u_tcp_tx/u_fifo_a/wptr_reg[6]/C`，ep=`u_app/bcnt_reg[2]/CE`） |

### ⑥-4 参考族并列（跨代只登记）

| 族 | **0x27** from/to | **0x28** from/to |
|---|---|---|
| `ref_tcp_tx`（16296 → 16143） | 0.069 / 0.092 | **0.068 / 0.068**（= DP WNS 宿主族） |
| `ref_fifo_a`（739 → 738） | 0.260 / 0.341 | 0.164 / 0.702 |
| `ref_tcp_rx`（4485 → 4409） | 0.237 / 0.444 | 0.409 / 0.623 |
| `ref_tcbcsum`（35 = 35） | 4.385 / 0.313 | 5.025 / 0.304 |
| `ref_app_udp`（2723 → 2718） | 0.110 / 0.983 | 0.202 / 1.024 |
| `ref_udp_tx`（2613 → 2585） | 0.598 / 0.110 | 0.402 / 0.202 |
| `ref_tcb`（5402 → 5395） | 0.696 / 0.069 | 0.938 / 0.164 |
| `ref_fifo_b`（1647 → 1643） | 0.147 / 0.518 | 0.261 / 0.393 |
| `ref_mac_rx`（2573 = 2573） | 1.096 / 0.572 | 0.890 / 0.309 |
| **`ref_snap_p7bdp`（1521 → 1776）** | 0.466 / **0.142** | 1.190 / **0.067**（= 本件全局 WNS 宿主族） |
| `ref_snap_dp`（1313 = 1313） | 0.495 / 0.130 | 0.281 / 0.092 |

### ⑥-5 ⭐ 定向网查询（`#90`：驱动 + 负载两侧都打出来）

| 网族 | **0x27** | **0x28** |
|---|---|---|
| `stat_up_ev` / `stat_sw_req` / `stat_sw_apply` / `stat_up_pend` | **0 / 0 / 0 / 0**（该代不存在 ⇒ 结构性缺席） | **36 / 36 / 36 / 36 网**（逐网 pin 已打；存活） |
| `biz_w71..w74` | 0（同上） | **32 / 32 / 32 / 32 网**（= 每字 32 位，与 wrapper 的 `wire [31:0] biz_w7x` 逐位对应） |
| `app_up_ev` / `app_sw_req` / `app_sw_apply` / `app_up_pend` | 0 / 0 / 0 / 0 | **0 / 0 / 0 / 0** ⇒ ⚠️ **结构性缺席（#92）**：wrapper 里 `wire [31:0] biz_w71 = app_up_ev;` 是**别名**，综合把网名归并到 `biz_w71[*]` ⇒ 该条定向查询**只能写「未观测到」**，不能读成"没接上"（接线证据 = 族 `e12_*` 的 from_worst 起/宿 `u_app/stat_up_ev_reg[29]/C → u_snap_p7bdp/hold_b_reg[1021]/D` 逐字可见） |
| `ev_up` | **69 网** | **69 网**（两代同 —— 事件线本身） |
| `ev_same_act` / `ev_other_act` | 0 / 0 | **0 / 0** ⇒ **两代都结构性缺席**（表达式被合并进驱动锥、网名未存活）—— 同 #92 口径 |
| `sw_apply` | **0** | **36 网**（本件存活） |

---

## ⑦ 偏离 / 异常（逐条如实）

1. ⚠️ **派单与实测的两处不符（已在 ④ 登记）**：① `sim/p6e_pcie/tb_p6e_pcie_wrapper.v` **不在**矩阵指纹/编译宇宙 ⇒ 不会出现在漂移里；② **读侧 20 文件同样不在** ⇒ "读侧面（14+ 文件）"这一项在指纹漂移里**实测为空**（不是漏同步 —— 判据在 ②：A/B/C/D 全绿 + 20/20 sha 全变）。**"超出期望的漂移 = 0"**；但**"期望内的那两格"也实测为空**，故一并写明。
2. ⚠️ **生成器首版 G6 写错、当场废弃**（详见 ②-1）—— rehearse 抓出 ⇒ **改正后才有 final**；仓内文件未受污染（该阶段全程只 print）。
3. ⚠️ **BID 行首次写入引入 26 处裸 LF**（我的新块用了 `\n`）：当场归一为全 CRLF 并复核 `CRLF 5025 / loneCR 0`；**最终文件逐字干净**。
4. ⚠️ **`_proj_pcie/rtl/axi_regs.v` 的 stale 头注释 = 本轮【未做】**（E12 §2.3 表第 4 条，处置写"登记（归构建轮/文档轮）"）：该件是**活 RTL**（`board/build_p7b_ku5p.tcl:96` 导入），其注释仍写 `SNAP_NW=71 ⇒ 未实现 = 0x14C` 一代口径（`MIR_STATUS@0x13C` 等 "W71/W72/W73/W74" 标签也整体错位 4 格）。**本轮不改**（理由：① 派单可写面不含 `_proj_pcie/rtl/`；② 往活 RTL 插注释性 diff 会改变构建源集绑定；③ 0x25/0x26/0x27 三轮先例同样未动）⇒ **仍登记为未收口文档债**（⚠️ 它现在**错得更远**：75 字下 MIR 四字实际在 0x14C/0x150/0x154/0x158、未实现 0x15C）。
5. ⚠️ **`run_tb_biz_win.bat:18` 一处既存裸 LF**（M1 轮的 REM 行）—— **非本轮引入**（本轮对该件只动 `:25` 单行；git numstat = 1/1）。**登记不改**（改它 = 超出本刀面）。
6. ⚠️ **`sim/p9_swc_gate/runF_dbg_witness.bat` 的 glob 覆盖缺口仍存**（0x27 轮登记）：不匹配 `run_*.bat` ⇒ 未进指纹。**本轮未修**（此刻改 globs 会作废本轮矩阵的修订绑定）。
7. ⚠️ **资源差分只登记不归因**（#66）：placed **−481 LUT / +533 FF**、synth **−610 LUT / +514 FF** —— 无拆刀 A/B；量级与"4×32 FF + 快照两侧各 32 位/字"的纸面估算同阶（**登记，不作因果**）。
8. ⚠️ **WNS 代际并列**：见 ⑥-1 末（**不同对象 + 不同检查类型** ⇒ 只并列；⛔ 不许写"时序变差/变好"，也不许把快照阵列复位族归因给 E12）。
9. ⚠️ **`P7B_WPWS` 读数口径提醒**：stdout 的 `P7B_WPPS` 列表最小 = 0.010，而 routed 报告 pulse-width 段 = `0.000`（failing 0）—— 两口径并列，不在此裁定（历史各轮同形态）。
10. ⚠️ **未烧板**：本轮到"位流 + 归档 + 定向 STA"为止；**未写 QSPI / 未碰对端机**。烧录属后续板级轮。
11. ⚠️ **未提交 git**（按本轮纪律，提交归 TL）；改动全部留工作树（tracked 修改恰 **28 件** = 20 读侧目标件 + 工具本体 + `wrapper_p4.v` + 5 板产物 + 1 矩阵日志）。

---

## ⑧ 未做 / 未观测（明示）

- **未做**：板级（烧/读）· 对端机 · `sim/p9_swc_gate/runF_dbg_witness.bat` 的 glob 收口 · `axi_regs.v` 注释同步 · `rtl/axis_c2h_stream.v:140` 等历史 stale 注释轮扫。
- **未观测（不是"不存在"）**：`app_up_ev`/`ev_same_act`/`ev_other_act` 的定向网查询（**结构性缺席**，#92）· E12 计数器"**在板上被激励**"（门里证的是接线/分类/折叠；**板级 W71..W74 读数未取**）。
- **未证**：E12 与"全局 WNS 换宿主"之间的因果（**无拆刀臂**，只登记形态）· 资源差分归因。

---

## 附：本目录原件索引

- 前置/读侧：`PRE_STATE.txt` · `_bid_bump.py` · `gen_edits28.py`/`GEN_EDITS28_OUTPUT.txt` · `EDITS_28_BLOCK.txt` · `splice_phase13.py`/`SPLICE_PHASE13_OUTPUT.txt` · `splice_allow28.py` · `_tool_backup_pre_splice13.py` · `PRESCAN_0x28.txt` · `DRYRUN_BID28_OUTPUT.txt` · `REHEARSE_BID28_OUTPUT.txt` · `NEGCTL_{table,bid,tier,face}_0x28{,_postapply}.txt` · `neg_rehearse28.py`/`NEG_REHEARSE_BID28.txt` · `neg_rehearse28_post.py`/`NEG_REHEARSE_BID28_POSTAPPLY.txt` · `APPLY_BID28_OUTPUT.txt` · `ASSERT_BID28_FINAL.txt` · `TARGET_SHA_{BEFORE,AFTER}_BID28.txt` · `_target_sha.py` · `READ_SIDE_DIFF_NUMSTAT.txt` · `_wrapper_p4_pre_wrapper.bak`
- p6e 双门：`P6E_{WRAPPER,COUNTERS}_{BEFORE,AFTER}_console.txt`
- 矩阵：`matrix_stdout_run1.txt` · `MATRIX_TAIL_run1.txt` · `P4_MATRIX_FINGERPRINT_20261015_234333_{before,after}.txt` · `FP_DRIFT_vs_0x27.txt` · `INPUT_HASHES_{BEFORE,AFTER}_GATES.txt` + `..._GATES_DIFF.txt` · `SWC_GATE_MATRIX_console.log` · `mk_input_hashes.py` · `fp_diff.py`
- 构建：`BUILD_CONSOLE_BID28.txt` · `READINGS_BID28.txt` · `BIT_SHA256_BID28.txt` · `board_rpt/`（15 件）· `wrapper_p4.bit`（15,431,261 B / `79c9cf43…bec8`）· `wrapper_p4_routed.dcp` · `BUILD_INPUT_HASHES{,_AFTER}.txt` + `..._DIFF.txt` · `_collect_build_0x28.py`
- 定向 STA：`q_0x28.tcl` · `run_q_x{27,28}.bat` · `_mk_qbats.py` · `q_stdout_x{27,28}.txt` · `query_out_x{27,28}/`（global_top5 / dp_top10 / dp_top50）
- 目录工具：`_mksums.py` · `SHA256SUMS.txt`（84 件）

---

**一句话状态**：BID 0x28 已落盘（wrapper 单 hunk +28/−2；禁碰区一字未动）+ 读侧 **63 处 / 20 文件**同步（BID 24 + 几何 39：NW 75 / 未实现 0x15C / 标签表补 W71..W74 / `check_window.nnew_top 5→9`）—— dry-run 63/63 · rehearse 全绿 · 四负控全有牙 · 反演重建恰 1 红 · apply 0 fail · **20/20 sha 全变**；p6e 双门 **148/0** 与 **26/0** 全 PASS_ALL（修前两门各恰 1 红 = BID 咬合见证；H 段读数逐字不变）；矩阵 **19/19 EXIT=0 / FROZEN**（272 件），漂移恰 **7 件 = E12 实施面**（ADDED/GONE 0；⚠️ 派单点名的 p6e TB 与读侧 20 文件**不在指纹宇宙** ⇒ 实测为空，如实登记）；构建一次收口 **WNS +0.065 / WHS +0.010 / 三类失败端点 0/0/0**，位流 `79c9cf434eb66723b97f654cbece9ea061632e2297c0a8ab0ea0dc198c43bec8`（15,431,261 B，`SW_CRC=5a5cd561`），12 键硬门 0 命中 / DRC 0E0C（69 Warning 五族与 0x27 逐数相同）/ route 0 错 / XDMA VERDICT=OK / 构建窗口 287 件 0 变；归档 84 件（归档内位流 = 0x27 `5c17b14f…3385`，provenance 已核；bit/dcp 按 .gitignore 留盘；`p7b_build_archive/20261016_001456/SHA256SUMS.txt` 白名单入库）。定向 STA（两代并列）：⭐ **四个 E12 计数器锥不进任何报告面**（四族 from/to ≥ 2.0 = WNS 的 30×；精确 0 命中；且各自有 36 网存活），**但**本件**全局 WNS 宿主换成了快照阵列的异步复位族**（`user_reset_reg → snap_words_r_reg[2224/2066/2277]/CLR` 列 +0.065/lvl 0，含 1 个 E12 新字端点；该阵列正是 E12 扩了 4 字的地方）—— 不同对象 + 不同检查类型 ⇒ **只并列不归因**，并登记为下一轮第一观察对象（余量 1.02%）。**板子未烧。**

---

## TL 抽核附加块（2026-10-16 01:0x，TL 亲核）

- **位流现读**：`sha256sum _proj_10g/notes/p9_build_0x28/wrapper_p4.bit` = `79c9cf434eb66723b97f654cbece9ea061632e2297c0a8ab0ea0dc198c43bec8` ✓（与 ⑤ 逐字一致）
- **被验源现读**：`rtl/app_pattern.v` = `c932c3ab…3582` ✓（本轮未动，全文零改动）；`board/wrapper_p4.v` = `3b39c85f…68a2` ✓（= 改后值）
- **BID 亲读**：`board/wrapper_p4.v:4377` = `32'h00000028` ✓；`:3296` = `localparam SNAP_NW_P6E = 75;` ✓
- **矩阵尾亲读**：`MATRIX_TAIL_run1.txt` = `gates run: 19 / 19` · `gates failed: 0` · `MATRIX DONE` ✓
- **漂移亲读**：`FP_DRIFT_vs_0x27.txt` = CONTENT-CHANGED 恰 7 件（wrapper + app_pattern + 5 个 swc 门件）· ADDED 0 · GONE 0 ✓
- **工作树**：tracked 修改 = 28 件 ✓（与 ⑦-11 清单一致：20 读侧 + 工具本体 + wrapper + 5 板产物 + 1 矩阵日志）
- **TL 裁定**：以上抽核读数全部与 agent 报告一致、无冲突；提交按显式清单执行（轮目录 + `p7b_build_archive/20261016_001456/SHA256SUMS.txt` 白名单件）。板子未烧 —— 烧录属后续板级轮。

---

## TL ERRATA 追加（2026-10-16 01:5x；依据 = 独立对抗审查 `_proj_10g/notes/p9_review_build0x28_20261016/FINDINGS.md`）

> 审查结论一句话：**数字面全部经独立复算成立**（读侧 63/63 无漏改 · 几何不变量 · 矩阵 7/0/0 冻结 · 双门 148/0+26/0 · WNS +0.065/0/0/0 · 位流三重一致 · STA 0 命中 · "不在指纹宇宙"属实）；抓到 **1 条高 + 4 条低**。

- **E-1（高，已修于后续提交）**：`_proj_pcie/p7b_gate4_selftest.sh` 自本提交起**不能解析** —— `bash -n` **RC=2**（`line 278: … from 'if' command on line 73`；`git show 4b22d1a:…` RC=0）⇒ 上文 **②-1 的"新分支 + 旧分支逐字保留"构造正是缺陷源**（实际做出 = 新增 `elif [ "$SW" -ge 71 ]` 行 **+ 重放旧 `if [ "$SW" -ge 71 ]` 行** ⇒ `:73` 外层 `if` 无 `fi`。**本轮的文本级 A 断言与 REHEARSE 结构性看不见"文件不可解析"**）。修复 = ① 删重放行（0/1）；② ⚠️ 暴露出的第二条（TL 新发现，自 M1 起陈旧、非本轮引入）：`UNIMPL_A` 公式未跟 `+16` 档 ⇒ 正例断言③ 结构性 BAD；改分档公式后**端到端自证 `OK=14 BAD=0` RC=0**（正例 0 FAIL + 负对照有牙）。修复件 sha256 = `187c9d35…9a0a`（⚠️ ≠ ②-2 的 `TARGET_SHA_AFTER_BID28.txt` 记录 = 设计如此，修复件取代；修复只动两行 ⇒ 读侧文本锚全不受影响）。
- **E-2（低，转录）**：②-2 assert 行 "B 4 族 **436** 命中" 应为 **429**（原件 `ASSERT_BID28_FINAL.txt` 末行 = `121+112+147+49`）；436 是 dry-run 侧值。实质结论（未登记 0）两侧原件均成立。
- **E-3（低，登记）**："一次收口（计数式）"三计数对"重跑"无判别力（`>` 截断重定向的必然产物）；**独立旁证支持单次调用**（`p7b_build_archive/20261016_*` 仅一个目录 + 时间线连续）⇒ 结论成立，引用时按"旁证"口径。
- **E-4（低，登记）**：`MATRIX_TAIL` 的 `DIGEST_ALL NOTE` 误归因（`af08f8ee…` 与 `92510c51…` 都是 content-only、差异只在排序键；"含 size/mtime"说法错）＝ `p4gate.py` **预存 wart**，FROZEN 判决不受影响。
- **E-5（低，登记）**：`READINGS_BID28.txt` 的"三类失败端点"小节为空（真值在 `board_rpt/p7b_ku5p_timing.rpt:157` 与 `MATRIX_TAIL`）。
- **E-6（低，登记）**：⑥-1 末"只并列不归因"段 = 最接近边界但**未越界**（显式拒因句在位）。
- **过程登记（采纳审查建议）**：**建议把 `bash -n`（及 .py `compile`）加进读侧 A 段对改动脚本的断言** —— 登记、未实施（改读侧工具归下一轮）。
