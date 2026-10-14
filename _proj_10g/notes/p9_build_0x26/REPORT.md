# 构建轮 `0x26` 报告（RFC seq 修复：读侧同步 + p6e 双门复跑 + 矩阵 + 构建 + 归档 + 定向 STA）

> **agent 原件由平台拒写 .md ⇒ 全文回传、TL 代落盘**（本件正文 = agent 原文；文末「TL 附加」= TL 独立抽核记录）。
> **口径**：本报告**不下 PASS/FAIL 裁定**；给的是读数与形态。「未观测到」≠「不存在」。
> 轮次目录 = `_proj_10g/notes/p9_build_0x26/`（90 件 + `SHA256SUMS.txt`）· HEAD = `ca3e60c`（全程未提交，改动留工作树）
> **纪律**：⛔ 未烧板 / 未写 QSPI / 未碰对端机；xsim 与 Vivado 全程按序（无并行）。
> ⛔ **被验源一字未动**：`rtl/tcp_rx.v` = `793761589de8089325c9f2f94986a696e1b198b978bfef341f370d0975a2b9f1`（= RFC 轮 rev2 A 值）· `sim/p3sim_rfc/frozen/tcp_rx_prefix.v` = `7517c949…` · `tools/gen_stim_tcp_rx.py` = `cbad26a5…` · `tools/gen_stim_tcp_chain.py` = `26109ac5…` · `tb/tb_tcp_rx.v` = `99cf45a8…` · `sim/p3sim_rfc/run_rfcseq_gate.bat` = `37d76b6d…` —— 六个 sha256 逐一现读复核 + 这六件 `git status` **全干净**。

---

## ① BID bump + 读侧同步 `--bid 0x26`（阶段 ⑪；24 处 / 14 文件；几何**一字未动**）

### ①-1 唯一被验源改动 = `board/wrapper_p4.v` 的 BID（**+10/−2，单 hunk**）

`git diff -- board/wrapper_p4.v` 只有一个 hunk（`:4319` 起）：

- 活行 **`:4322`**：`32'h00000025` → **`32'h00000026`**（行尾注释 `F-3 = 0x25` → `RFC seq 修复 = 0x26`）；
- 注释块顶部插新块（本轮 = RFC seq 修复：`rtl/tcp_rx.v` 的 `seq_lt = seq_diff[31]` 真差口径 / 唯一功能改点 1 行 / 设计件指针 / **几何不变 71 字 / 0x14C** / 读侧 `EXPECT_BID` 0x25 → 0x26），旧 F-3 块降级为「⭐ 上一轮」**逐字保留**。
- ⛔ **禁碰区核**：现读 `board/wrapper_p4.v:1321-1324` = app 寄存器总线静止块（`// P5 寄存器总线默认静止 (板级无 CPU/AXI…` + `assign app_reg_addr = 8'h00;` / `app_reg_wr = 1'b0;` / `app_reg_wdata = 32'd0;`）—— **一字未动**（diff 只有上面那一个 hunk）。⚠️ 派单写 `:1319-1322`；**现读 = `:1321-1324`**（行号随历史轮增长位移，**内容**核过 = 同一块）。

### ①-2 读侧同步（先例 = `p9_build_0x25`；⚠️ 工具实际路径 = `_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py`，派单写的 `_proj_10g/tools/…` 不存在 —— 与 0x25 轮同款笔误，按先例纠正）

- **生成器 `gen_edits26.py`**：取 `EDITS_25` 的 new 侧（= 盘上现状）当 ⑪ old 侧，**逐条显式**变换（0x25→0x26 值 + 代名 + 逐代历史链追加）。
  ⚠️ 与 0x25 轮的差异（有意）：25 轮用 `base()` 通配（值全替 + 代名全替），本轮**不用通配** —— 25 树注释里含大量 `0x1F..0x24` 历史链字面，通配会污染历史。
  自检 = **old 侧 24/24 逐字命中盘上现状**；new 侧 20 条 WARN 逐条人工核 = **全部是"逐字保留的历史"**。
- **`splice_phase11.py`**：6 锚点**唯一命中**（①a `EDITS_26 = []` / ①b `def E11(...)` / ② `STAGES` 追加 `("0x00000026", EDITS_26, "RFC seq 修复 (2026-10-15)", 71, 0x14C)` / ③ ⑰ 段（E11 块）插到 ⑧ 段前 / ④ 顶部 docstring ⑪ 指针 / ⑤ ALLOW 追加 1 条）⇒ 工具本体 **+99/−2**。⚠️ 首跑自伤 1 处（已修）：`f22` 把两条 edit（index 22/23）写成一个函数 ⇒ index 22 上第二个 `rep()` 锚点 0 命中（**响亮失败，未落盘**）⇒ 拆成 `f22`/`f23` 后重跑。

**逐文件 hunk 清单**（`git diff --numstat`；原件 `READ_SIDE_DIFF_NUMSTAT.txt`；每文件 = 1 hunk）

| # | 文件（仓根相对） | +/− | hunk 内容 |
|---|---|---|---|
| 1 | `_proj_10g/notes/p7b_affinity/j6_r6fix.sh` | +2/−1 | `EXPECT_BID` 默认 0x25→0x26 + GEOM_TIERS 顶部插 `71\|0x00000026\|…` 行 |
| 2 | `_proj_10g/notes/p7b_biz_tcpreg/tcpreg_j6.sh` | +2/−1 | 同上 |
| 3 | `_proj_pcie/p7b_biz/p7b_snap.sh` | +4/−2 | `EXPECT_BID` 裸行 + 头部「现役」块顶部插 RFC seq 块 |
| 4 | `_proj_pcie/p6e_snap_check.sh` | +1/−1 | `EXPECT_BID` 默认 + 历史链移一格 |
| 5 | `_proj_pcie/p7b_gate4_accept.sh` | +1/−1 | 同上 |
| 6 | `_proj_pcie/p7b_gate4_selftest.sh` | +4/−4 | 现役注释行 + `FAKE_BID` 活行 + 旧口径行 |
| 7 | `_proj_pcie/p7b_gate4_negctrl.sh` | +3/−2 | 几何注释块顶部插新行 + `echo "BID 0x…26"` 活行 |
| 8 | `_proj_pcie/p7b_gate4_livefake.sh` | +4/−2 | 注释块顶部插新块 + `bid = {71: "0x…26", …}` 活行 |
| 9 | `_proj_pcie/p6e_snap_selftest_fix2.sh` | +1/−1 | `FAKE_BID` 活行 |
| 10 | `_proj_10g/notes/p7b_gate4_3/final_state.sh` | +1/−1 | `EXPECT_BID` |
| 11 | `_proj_10g/notes/p7b_gate4_criteria/gen_inputs.py` | +6/−5 | docstring 几何行 + 夹具自述 + 逐代链 + `BID_FIX`（**含一处历史遗留拉正**：第二处非加粗的 "accept 默认也已是 …0x24" 0x25 轮未带改 ⇒ 本轮一并拉正到 0x26，见 ⑥-11） |
| 12 | `_proj_10g/notes/p7b_a3_negctl_20261010/step0_selfcheck.sh` | +2/−2 | 缺省档/默认档两行 |
| 13 | `sim/p6e_pcie/tb_p6e_pcie_wrapper.v` | +1/−1 | **:215** 活行 `chk("2  BUILD_ID (RFC seq 修复 构建 = 0x26)", v, 32'h00000026);` |
| 14 | `sim/p6e_pcie/tb_p6e_pcie_counters.v` | +1/−1 | **:206** 活行 `chk("0b BUILD_ID (RFC seq 修复 71-word = 0x26; 原 71-word=0x25(F-3 修复) / 0x24(P9 URAM 板内缓冲) / 63-word=9)"` |
| 15 | `_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py`（工具本体） | +99/−2 | 阶段 ⑪ 全部（声明 / E11 / STAGES / ⑰ 段 24 条 E11 / ⑪ 指针 / ALLOW 1 条） |

**全阶段读数**（原件 = 本目录同名 txt）

| 阶段 | 读数 |
|---|---|
| 预扫 | 目标 0x26 搜索面 4 族 **375 行 / 185 文件**；未登记 **2 件**（= 本轮生成器自身 `_scan_newhits26.py` / `gen_edits26.py`）⇒ ALLOW 追加 **1 条**（`^_proj_10g/notes/p9_build_0x26/`，覆盖两者） |
| dry-run | **24/24 `hits=1/1`**；B 面 4 族 **376 命中文件 未登记 0**；C 24 红 = 待改处；D 覆盖 14/14；A 5/5 绿 |
| rehearse | **全绿 0 fail**（`REHEARSE OK`） |
| negctl ×4 | `table` 1 红 · `bid` 24 红（含目标）· `tier` 24 红（含目标）· `face` 3 红 —— **四条全有牙** |
| neg_rehearse | **恰 1 红** = 末条（`step0_selfcheck.sh[BID]`） |
| apply | RC=0 / 0 fail（`APPLY_READSIDE_BID OK`）；**14/14 件 SHA256 全变**（`TARGET_SHA_BEFORE_BID26.txt` ↔ `POSTAPPLY_SHA_BID26.txt` 逐条比） |
| assert（after） | RC=0；A 5/5 · B 4 族 **368 命中 0 未登记** · C 全绿 · D 14/14 |
| face | **368 行 / 186 文件**（未登记 0） |
| post negctl ×4 + 反演重建 | 四条仍有牙（1/1/1/3 红，含目标）；反演重建恰 1 红 |

**几何不变量（派单点名核）**：NW 保持 **71**（权威源 `board/wrapper_p4.v:3266` `SNAP_NW_P6E = 71`）、未实现地址保持 **0x14C** —— A 表长断言 5/5 绿 + 权威源两侧现读一致。三个读侧默认哨兵现读 **0x00000026**（`j6_r6fix.sh:76` / `tcpreg_j6.sh:70` / `p7b_snap.sh:71`）。

---

## ② p6e 双门读数（修前 / 修后对）

**修前 = wrapper 已 bump 到 0x26、TB 仍期望 0x25**（= 同步前的同一棵树；TB 同步步骤的"咬合力"见证）；**修后 = TB 同步 0x26**。两次运行间**只差 TB 的两个期望值**。

| 门 | 修前 | 修后 |
|---|---|---|
| **全链门** `run_tb_p6e_pcie.bat` | **143 `[PASS]` / 1 `[FAIL]`**（唯一 FAIL = `2 BUILD_ID … = 00000026 (期望 00000025)`）**RC=1** | **144 `[PASS]` / 0 `[FAIL]` / `PASS_ALL`** **RC=0** |
| **counters 门** `run_tb_p6e_pcie_counters.bat` | **25 `[PASS]` / 1 `[FAIL]`**（唯一 FAIL = `0b BUILD_ID … = 38 (期望 37)`）**RC=1** | **26 `[PASS]` / 0 `[FAIL]` / `PASS_ALL`** **RC=0** |

**H 段读数两臂逐字相同**（派单点名"若有任何变化 ⇒ 停下报我" ⇒ **无变化**）：`H 读数(灌满后): W26=69 W27=256` · `H 读数(排空后): W30=257 W31=2056 W0=0` —— 修前/修后**逐字相同**（= F-3 轮修复 SOP 激励后的历史基线形态；对照 F-3 受损态 `W26=3 W27=5`）。

console 全量 diff（修前↔修后）**只含** ① BUILD_ID 那一行（FAIL→PASS）+ ② 末行汇总（`1 项失败`→`PASS_ALL`）+ ③ 内存/耗时/时间戳三行 ⇒ **本刀扰动面 = BID 期望值本身**。
原始证据：`P6E_{WRAPPER,COUNTERS}_{BEFORE,AFTER}_console.txt` + `_evidence_xsim_p6e_wrapper_{BEFORE_31484,AFTER}.log` + `_evidence_xsim_p6e_cnt_{BEFORE_31428,AFTER}.log`。

---

## ③ 常驻矩阵（18 门）：漂移核验 + 重基线记录

### ③-1 18 门 run1（04:01:21–04:26:19）

- **18/18 门 `EXIT=0` · `gates failed: 0`** · **`VERDICT: FROZEN`**（**264 件** before=after **逐位**；`DIGEST_COMPILE=f3c64b2dfc4327b15929bcad2f5600268c4b2af0de9522b82e6ac532b5c949f7` / `FILES_COMPILE=216` / `DIGEST_ALL=a99eab426c9b85a7e2b404b5561dc0674a7e06e08049d5df910dfcb10a3c4a2d` / `FILES_ALL=264` / `HEAD=ca3e60c`）。
- 归档副本：`P4_MATRIX_FINGERPRINT_20261015_040121_{before,after}.txt` + `matrix_stdout_run1.txt` + `MATRIX_TAIL_run1.txt`。
- **漂移集合核验（vs 0x25 轮基线 `P4_MATRIX_FINGERPRINT_20261015_014604_after.txt`；原件 `FP_DRIFT_vs_0x25.txt`）**：**CONTENT-CHANGED 恰 3 = `{board/wrapper_p4.v, rtl/tcp_rx.v, tools/gen_stim_tcp_chain.py}`**；**ADDED 0 / GONE 0**（264=264）。
  ⇒ 与派单预期面一致：前两件 = 本刀面（BID bump + 真差口径 1 行）；第三件 = **RFC 实施轮的 oracle 行**（`tools/gen_stim_tcp_chain.py:355` 的 `seq_lt` 真差式）—— **它在 `FINGERPRINT_GLOBS` 内**（`sim/p4gates/paths.txt` 含 `tools\gen_stim_tcp_chain.py`）⇒ 属派单允许项（"tools 若在指纹 globs 内也算预期"）。
  ⚠️ `tb/tb_tcp_rx.v` / `sim/p3sim_rfc/*` **未进指纹集**（不在任何 manifest/globs）⇒ 无漂移行。**超出该集合的漂移/红 = 0**。

### ③-2 重基线记录（理由 = 参数 + 行为；⛔ 不以"指纹变了"充当等价证据）

1. **参数面（RTL 语义）**：`rtl/tcp_rx.v:327` 唯一功能改点 —— `wire seq_lt = (seq32 &lt; ra_rcv_nxt)` → **`wire seq_lt = seq_diff[31]`**（RFC 793 SEQ_LT 真差口径）。等价域/分歧域/边界（差 = 0x80000000 判 seq_lt=1）由 RFC 轮的门与设计件背书，本轮**不复算**。
2. **行为面（本轮实测）**：`sim/p3sim_rfc` 7 臂在 RFC 轮全绿；本轮的**独立行为见证** = ① p6e 双门 144/0 + 26/0（真 wrapper 全链）；② 矩阵 18/18 门 EXIT=0（`chain` / `p5_wrapper` / `unit_vlan` / `f3_resync` 等**编译的就是本轮的 `rtl/tcp_rx.v`**）。
3. **BID 面**：`board/wrapper_p4.v` 的 `BUILD_ID_V` 0x25 → 0x26，几何/端口面零改动。
4. ⇒ **新基线 = `P4_MATRIX_FINGERPRINT_20261015_040121_after.txt`**（264 件；DIGEST 见上）。
5. **gate 相位输入完整性**：`INPUT_HASHES_BEFORE_GATES == AFTER_GATES`（**218 件，0 变**）⇒ 26 min 内无其它写入。

---

## ④ 构建 `0x26`（唯一入口 `board/run_build_p7b_ku5p.bat`，一次收口）

**调用式** = `MSYS_NO_PATHCONV=1 cmd /c 'board\run_build_p7b_ku5p.bat'`（**单斜杠式**；⛔ 未与 `//c` 并用）。**本次独有串** = `ARCHIVE_DONE 20261015_043241 files=19`（BAT_RC=0）。

**时间线**：

| 时刻 | 事件 |
|---|---|
| 04:32:41 | 归档块先跑（#54）：`p7b_build_archive/20261015_043241/`，19 件；**内含上一代位流 `wrapper_p4.bit` sha256 = `faefa444e0d02ef9969d069d773614d65ace9583f51fd58c553463299db54c85` = 0x25 位流**（provenance 已核） |
| 04:42:49 | synth `Exiting Vivado`（`P7B_ROUND #1 MISMATCH_N = 5` → `#2 = 0`；`P7B_CONVERGED_AT_ROUND = 2`，与 0x25 逐字同） |
| 05:07:05 | 位流落盘（`Writing bitstream ./wrapper_p4.bit` + `Bitgen Completed Successfully`）/ impl `Exiting Vivado` |
| 05:08:09 / 05:08:10 | 父进程 `Exiting Vivado` / bat console 收尾（`BITSTREAM-OK`，BAT_RC=0） |

**收口读数（逐项）**：

| 项 | 读数 |
|---|---|
| **BAT_RC / BUILD_EXIT** | **0 / 0**（console 末 = `BITSTREAM-OK`） |
| **一次收口（计数式）** | `^P7B_ROUND #1 ` 恰 **1** · `BUILD_EXIT` 恰 1 · `^P7B DONE$` 恰 **1**（⚠️ 裸 grep "P7B DONE" = 2，第二处 = tcl 源码回显 `# puts "P7B DONE"`）· `Exiting Vivado` 恰 **3** 条 |
| **P7B_WNS / P7B_WHS** | **+0.019 / +0.010**（`IS_LOCKED_POSTGEN = 0`；`P7B_NFILES = 443` = 0x25 同） |
| **三类失败端点** | **0 / 0 / 0**（setup `0/258,740` · hold `0/258,740` · pulse-width `0/84,285`；`Slack (VIOLATED)` **0 条**；`All user specified timing constraints are met.` 在档） |
| **位流** | sha256 = **`34e553eee8907b8a108303b43eb438199bea04285bbf213aa25585b6e9d94202`** · **15,431,261 B**（= 八档同尺寸）· **`SW_CRC=26a5e6ae`** · routed dcp 63,051,083 B |
| **硬门（12 键）** | `12-4739` / 隐式网五键 / DRC 六键 —— **全 0 命中**（bat 一行都没打；逐键 `grep -c` = 0 复核过） |
| **DRC（routed）** | **0 Error / 0 Critical**；Warning 五族（DPIP-2 4 · DPOP-3 2 · DPOP-4 4 · DPOR-2 18 · REQP-1858 41 = 69 checks）与 0x25 **逐数相同** |
| **Route status** | `# of nets with routing errors = 0`；fully routed 138,052 / routable 138,052 |
| **日志面** | impl runme 末步 `1602 Infos, 12 Warnings, 2 Critical Warnings, 0 Errors`；DRC `finished with 0 Errors`；CRITICAL WARNING = **既存** `Constraints 18-1056` + `Vivado 12-1790` |
| **XDMA 断言组** | `RC_BASE=0` · `RC_INTF=0`（`<AXI_Stream>`）· `RB_MISMATCH_N=0`（13/13）· `GEN_BAD_N=0`（6/6）· `CFGDIFF_ST_N=1` · `CFGDIFF_MM_N=2` · **`VERDICT=OK`**（与 0x25 逐字同） |
| **资源（只并列，不归因）** | placed **78,262 LUT / 74,570 FF** / 348 BRAM / 1 URAM / 4 DSP / 10 IOB / 6 GTYE4；synth **62,761 LUT / 53,107 FF** / 312 BRAM（0x25: placed 78,228/74,567/348/1；synth 62,760/53,114/312 ⇒ **+34 LUT / +3 FF（placed）· +1 LUT / −7 FF（synth）**） |
| **构建期间绑定** | `BUILD_INPUT_HASHES{,_AFTER}.txt`（**287 件**源集）**0 变**（窗口 04:32:41–05:08:10；`BUILD_INPUT_HASHES_DIFF.txt` = 空） |

**归档清单（`_proj_10g/notes/p9_build_0x26/`，#54）**：`wrapper_p4.bit` · `wrapper_p4_routed.dcp` · `board_rpt/`（**14 件**，与 0x25 同名集）· `p7b_ku5p_stdout.txt` · 全部读数/原件 txt · `SHA256SUMS.txt`（**90 件**）。
⚠️ 按仓规 `.gitignore`：`*.bit`（**现读 `:69`**）与 `*.dcp`（**现读 `:355`**）**均不入库**（`git check-ignore -v` 双证）——归档留盘。⚠️ 报告 .md 平台拒写 ⇒ 全文回传、TL 代落盘。

---

## ⑤ 定向 STA（`q_0x26.tcl`，**两代并列**：0x25 与 0x26 的 routed dcp 各跑一次）

> 沿用 0x24 轮 `q_0x24.tcl` 先例（调用式 = `run_q_*.bat`：`-nojournal -nolog` 在 `-source` 之前，⛔ 行内 `#` 注释陷阱已避）；**额外做法**：同一份脚本对 **0x25 归档 dcp** 与 **0x26 新 dcp** 各跑一次 ⇒ 两代读数直接并列（0x25 轮自己**没跑** q_0x25 —— 这是本轮补的对照面）。⛔ **无拆刀 ⇒ 差异含"本刀 + P&R 重排"两项、分不开 ⇒ 只登记不归因**（#66）。

### ⑤-1 全局 / DP 域（原件 `q_stdout_x25.txt` / `q_stdout_x26.txt`）

| 项 | **0x25（前代）** | **0x26（本件）** |
|---|---|---|
| 全局 setup WNS | +0.044 @ `u_tcp_tx/u_fifo_a/rptr_reg[0]/C → u_app/stg_reg[1]/D`（lvl 21） | **+0.019** @ `u_tcp_tx/u_fifo_a/wptr_reg[6]_replica/C → u_app/pw_data_reg[41]/D`（lvl 19） |
| DP 域 WNS（`g_hw.clk_out0`） | +0.044（= 全局，同一对象） | **+0.019**（= 全局，**仍是同一对象**） |
| DP top-50 **起点直方图** | **50/50 = `u_tcp_tx/u_fifo_a/rptr_reg[0]/C`** | **50/50 = `u_tcp_tx/u_fifo_a/wptr_reg[6]_replica/C`** |
| DP top-50 slack 带 | 0.044 … 0.111 | 0.019 … 0.040 |
| **本刀新锥在不在 DP 前 10** | —— | ⛔ **不在**：DP top-10 的 sp/ep 逐条无 `u_tcp_rx`/`seq_*` 字样（`dp_top10.rpt` grep = 0）；DP top-50 里也只有 **1 条**路径的**块内**出现 `u_tcp_rx` 网名（#46，且不是 sp/ep）——0x25 同形态（#44） |

⇒ **最差族未换族**（两代都是 `u_tcp_tx/u_fifo_a` → `u_app`/`u_tcb`），**但宿主对象换位**：起点 `rptr_reg[0]` → **`wptr_reg[6]_replica`**（一个 P&R 复制寄存器）、终点 `stg_reg[1]` → `pw_data_reg[41]`；且 top-50 整带的 slack 整体下移（0.111 → 0.040）。**只登记不归因**。

### ⑤-2 ⭐ 本刀面（三个判据 D 端 + 全 `u_tcp_rx` 族）—— 两代并列

| 族（`-to` 最差） | **0x25** | **0x26** | 差 |
|---|---|---|---|
| `rfc_accl`（`acc_l_reg/D`） | 1.290（lvl 10，sp=`u_tcp_rx/conn_id_l_reg[3]/C`） | **0.319（lvl 6，同一 sp/ep）** | **−0.971** |
| `rfc_ackresp`（`ackresp_l_reg/D`） | 1.307（lvl 10） | **0.343（lvl 6）** | **−0.964** |
| `rfc_w6a`（`w6a_ok_l_reg/D`） | 1.489（lvl 6，sp=`u_classify/u_wf/dout_reg[75]/C`） | **0.347（lvl 6，sp=`u_tcp_rx/conn_id_l_reg[3]/C`）** | **−1.142** |
| `rfc_u_tcp_rx`（全 4490 cell；from/to） | from 0.518 / to 0.447 | **from = to = 0.319** | — |

**最差那条的分解（`query_detail_*/accl.rpt`；同一 sp/ep）**：

| | 0x25 | 0x26 |
|---|---|---|
| slack | 1.290 | **0.319** |
| Data Path Delay | 4.957 ns | **5.738 ns** |
| logic | 1.219 ns（24.6%） | **0.541 ns（9.4%）** |
| route | 3.738 ns（75.4%） | **5.197 ns（90.6%）** |
| Logic Levels | 10（CARRY8=5 LUT2=2 LUT3=2 MUXF8=1） | **6（LUT3=1 LUT4=1 LUT5=2 LUT6=1 MUXF8=1）** |
| Clock Path Skew | −0.118 ns | **−0.308 ns** |

⇒ ⭐ **教科书式 #65 形态：逻辑级数 10→6、logic 1.219→0.541 ns（都变短），slack 反而 1.290→0.319** —— 被 route（3.738→5.197 ns）与 clock skew（−0.118→−0.308）吃掉。**只登记不归因**。

### ⑤-3 ⭐ 定向网查询（#90：驱动 + 负载两侧都打出来；原件 = `q_stdout_x*.txt` 的 `N` 段）

| | **0x25** | **0x26** |
|---|---|---|
| `u_tcp_rx/seq_lt` 网 | **存在**，**3 pins** | **存在**，**6 pins** |
| 驱动 | `w6a_ok_l_reg_i_4/CO[7]`（OUT）= **CARRY8 进位输出** | `w6a_ok_l_reg_i_4/O[7]`（OUT）= **CARRY8 和位输出** |
| 负载 | `ackresp_l_i_1/I1` · `w6a_ok_l_i_1/I3` | `acc_l_reg_i_2/DI[7]` · `acc_l_i_6/I0` · `w6a_ok_l_i_8/I0` · `ackresp_l_i_1/I1` · `w6a_ok_l_i_1/I3` |
| `seq_diff` 网族 | **15** 条（`seq_diff2_out[17..31]`）+ 60 pins（喂 acc_l/w6a LUT） | **0 条**（名字未存活 —— 归并） |
| `seq32` / `ra_rcv_nxt` 网族 | 0 / 0 | 0 / 0 |

⚠️ 两代"seq_lt 网"都存活且都能指名驱动/负载 —— 0x25 = **进位输出**（绝对比较的 carry-out）、0x26 = **和位输出**（真差 bit 31），**这个变化与 RTL 改动方向逐字吻合**（abs compare → true-difference bit 31）。⛔ 仍**不下"板上行为因此变好/变坏"的裁定**（本件只做结构/时序读数；行为面证据在 RFC 轮的门与后续板级轮）。

---

## ⑥ 偏离 / 异常（逐条如实）

1. ⚠️ **派单路径笔误（已按先例纠正）**：派单写 `_proj_10g/tools/apply_readside_bid1c.py` —— 实际工具在 `_proj_10g/notes/p7b_readside_bid1c_20261011/`（与 0x25 轮同款）。
2. ⚠️ **生成器自伤 1 处（已修，未落盘）**：`gen_edits26.py` 首版把 index 22/23 两条 edit 合成一个 `f22()` ⇒ index 22 上第二个 `rep()` 锚点 0 命中 ⇒ `AssertionError`（**响亮失败**，`EDITS_26_BLOCK.txt` 未写出、仓内零改动）⇒ 拆 `f22`/`f23` 后重跑（24/24 自检绿）。
3. ⚠️ **细节查询 tcl 自伤 1 处（已登记，未重跑）**：`q_0x26_detail.tcl` 用了 `get_property CLOCK_PATH_SKEW`（**不是 timing_path 属性** —— 与 q_0x24 头注的 `PATH_GROUP`/`PATH_TYPE` 同族坑 [Common 17-54]）⇒ 脚本在**第一条 pin（accl）打完 slack 后中止**；`accl.rpt` **已完整落盘**（⑤-2 的分解读数 = 从它读的），`ackresp/w6a/dup` 的**逐 pin 明细未采** —— 但这三者的 `-to` 最差 slack **在 ⑤-2 的主查询里逐条有**（族 `to_worst`），**不影响主读数**。未重跑（主读数已足；如需补齐 = 去掉该属性重跑 ≈4 min/dcp）。
4. ⚠️ **两个 bat 的写入自伤（已修，未影响执行）**：`run_q_*.bat` 的 REM 行里 `p9_build_0x24\run_q.bat` 被写成 `<CR>un_q.bat`（heredoc 吞了一个反斜杠 ⇒ 裸 CR）⇒ 已用字节级替换修真（复检 `bareCR=0 / nonascii=0 / CRLF=7`）。⚠️ 首次 `cmd /c 'run_q_x25.bat'`（**相对路径 + 后台**）报 `'run_q_x25.bat' 不是内部或外部命令` ⇒ 改**绝对路径**调用后正常（纪律：后台调用一律绝对路径）。
5. ⚠️ **归档/产物类 git 变更（预期内）**：构建重写 `board/p7b_ku5p_{timing,util,drc,clkinteract}.rpt` + `board/p7b_ku5p_stdout.txt`；矩阵重写 `sim/p4sim/matrix_p4dfix.log`。均非源码改动。工作树 tracked 修改 = **22 件** = 15 读侧/TB + wrapper + 5 板产物 + 1 矩阵日志。
6. ⚠️ **资源差分只登记不归因**：placed **+34 LUT / +3 FF**（synth +1 LUT / −7 FF）—— 无拆刀 A/B（#66）。
7. ⚠️ **WNS 代际并列 = 0.044 → 0.019（−0.025）**：⚠️ **两代的 WNS 宿主不是同一对象**（`rptr_reg[0]` vs `wptr_reg[6]_replica`）⇒ **只并列、不比较"好坏"、不归因**（#66）；同理 0x25 说过的"0x24 `+0.066` → 0x25 `+0.044`"亦非同对象。
8. ⚠️ **P7B_WPWS 读数口径提醒**：stdout 的 `P7B_WPPS` 列表最小 = 0.010，而 routed 报告表 pulse-width 段显示 `0.000`（failing 0）—— 两口径并列，不在此裁定（历史各轮同形态）。
9. ⚠️ **本机有 3 个长驻 `python.exe`**（启动时刻 = 2026-10-14 22:13/22:14/22:56，**早于本轮 session**；疑为其它会话 watcher）—— 全程两处完整性面（矩阵 26 min 冻结 / 构建 35 min 源集 0 变）**都证明它们没有写本仓**。如实登记，不处置。
10. ⚠️ **未烧板**：本轮到"位流 + 归档 + 定向 STA"为止；板上现役仍是上一态（**0x24**），烧录属后续板级轮。
11. ⚠️ **一处历史遗留拉正（有意，已在 ①-2 表内标注）**：`gen_inputs.py` 第 49 行的第二处措辞 `accept 默认也已是 71 字 / BID 0x24` 是 0x25 轮的半代残留（它没带粗体 ⇒ 上轮的 `base()` 只改了第一处）⇒ 本轮把两处一起拉到 0x26（该句是**对 accept 脚本默认值的事实陈述**，同步后它就是 0x26；不改反而是假陈述）。
12. ⚠️ **对端机 / 板子全程未碰**；无残留 Vivado/xsim 进程（收尾 `Get-Process vivado,xsim,xelab` = **0**）。

---

### 附：本目录原件索引（`SHA256SUMS.txt` = 90 件）

- 读侧：`PRESCAN_0x26.txt` · `GEN_EDITS26_OUTPUT.txt` · `EDITS_26_BLOCK.txt` · `_dump25.py`/`_EDITS25_DUMP.txt` · `splice_phase11.py`/`SPLICE_PHASE11_OUTPUT.txt` · `DRYRUN_BID26_OUTPUT.txt` · `REHEARSE_BID26_OUTPUT.txt` · `NEGCTL_{table,bid,tier,face}_0x26{,_postapply}.txt` · `NEG_REHEARSE_BID26{,_POSTAPPLY}.txt` · `APPLY_BID26_OUTPUT.txt` · `ASSERT_BID26_AFTER.txt` · `FACE_BID26_AFTER.txt` · `TARGET_SHA_BEFORE{,_BID26}.txt` · `POSTAPPLY_SHA_BID26.txt` · `READ_SIDE_DIFF_NUMSTAT.txt`
- p6e 双门：`P6E_{WRAPPER,COUNTERS}_{BEFORE,AFTER}_console.txt` · `_evidence_xsim_p6e_{wrapper,cnt}_{BEFORE_*,AFTER}.log`
- 矩阵：`matrix_stdout_run1.txt` · `MATRIX_TAIL_run1.txt` · `P4_MATRIX_FINGERPRINT_20261015_040121_{before,after}.txt` · `FP_DRIFT_vs_0x25.txt` · `INPUT_HASHES_{BEFORE,AFTER}_GATES.txt` + `..._GATES_DIFF.txt`
- 构建：`BUILD_CONSOLE_BID26.txt` · `p7b_ku5p_stdout.txt` · `BIT_SHA256_BID26.txt` · `board_rpt/`（14 件）· `wrapper_p4.bit`（15,431,261 B / `34e553ee…4202`）· `wrapper_p4_routed.dcp` · `BUILD_INPUT_HASHES{,_AFTER}.txt` + `..._DIFF.txt`
- 定向 STA：`q_0x26.tcl` / `q_0x26_detail.tcl` · `run_q_{x25,x26}.bat` / `run_qdetail_{x25,x26}.bat` · `q_stdout_x{25,26}.txt` · `q_detail_stdout_x{25,26}.txt` · `query_out_x{25,26}/`（dp_top10/dp_top50/global_top5）· `query_detail_x{25,26}/accl.rpt` · `DP_TOP50_COMPARE.txt`

---

**一句话状态**：BID 0x26 已落盘（wrapper 单 hunk）+ 读侧 24/24 同步（四负控有牙 / 几何不变量 71 / 0x14C 双核）；p6e 双门 **144/0** 与 **26/0** 全 PASS_ALL（修前两门各恰 1 红 = BID，H 段读数逐字不变）；矩阵 **18/18 EXIT=0 / FROZEN**，漂移恰 `{board/wrapper_p4.v, rtl/tcp_rx.v, tools/gen_stim_tcp_chain.py}`（第三件在 globs 内 = 预期）；构建一次收口 **WNS +0.019 / WHS +0.010 / 三类失败端点 0/0/0**，位流 `34e553eee8907b8a108303b43eb438199bea04285bbf213aa25585b6e9d94202`（15,431,261 B，`SW_CRC=26a5e6ae`），12 键硬门 0 命中 / DRC 0E0C / route 0 错 / XDMA VERDICT=OK / 构建窗口 287 件 0 变；归档 90 件（bit/dcp 经 .gitignore 留盘）。定向 STA（两代并列）：**本刀新锥不在 DP 前 10**，最差族未换（仍是 `u_tcp_tx/u_fifo_a`）但**宿主换位**（`rptr_reg[0]`→`wptr_reg[6]_replica`）；本刀面三个判据 D 端最差 slack **1.290–1.489 → 0.319–0.347**，且最差那条呈 #65 形态（logic 变短、route+skew 吃掉）—— **无拆刀 ⇒ 只登记不归因**。板子未烧。

----------------------------------------------------------------

## TL 附加（2026-10-15 05:3x；独立抽核记录）

- **位流核**：`sha256sum _proj_10g/notes/p9_build_0x26/wrapper_p4.bit` = `34e553eee8907b8a108303b43eb438199bea04285bbf213aa25585b6e9d94202` ✓（与报告逐字）；轮目录 91 文件 / 92 MB（含 bit + dcp，二者 `git check-ignore -v` 双证 = `.gitignore:69` / `:355`）。
- **被验源核**：`rtl/tcp_rx.v` = `79376158…b9f1` ✓ · `sim/p3sim_rfc/frozen/tcp_rx_prefix.v` = `7517c949…` ✓ · `tools/gen_stim_tcp_rx.py` = `cbad26a5…` ✓ · `tools/gen_stim_tcp_chain.py` = `26109ac5…` ✓ · `tb/tb_tcp_rx.v` = `99cf45a8…` ✓ · `sim/p3sim_rfc/run_rfcseq_gate.bat` = `37d76b6d…` ✓ —— 六件逐一现读，与报告口径逐字吻合。
- **BID 现读核**：`board/wrapper_p4.v:4322` = `32'h00000026` ✓（TL 亲读；RFC 注释块在顶、F-3 块降级为「⭐ 上一轮」逐字保留）。
- **门读数核**：`P6E_WRAPPER_AFTER_console.txt` 末 = `PASS_ALL tb_p6e_pcie_wrapper: 全链门全过` ✓；`P6E_COUNTERS_AFTER_console.txt` 末 = `PASS_ALL tb_p6e_pcie_counters: …全过` ✓；修前咬合见证 `P6E_COUNTERS_BEFORE_console.txt:2` = `[FAIL] … = 38 (期望 37)`（恰 BID 一处）✓。
- **矩阵核**：`MATRIX_TAIL_run1.txt` = `GIT_HEAD ca3e60c` / `gates run 18/18` / `gates failed: 0` / `VERDICT: FROZEN`（264 件）✓；`FP_DRIFT_vs_0x25.txt` = CONTENT-CHANGED (3) `{board/wrapper_p4.v, rtl/tcp_rx.v, tools/gen_stim_tcp_chain.py}` / ADDED 0 / GONE 0 ✓（第三件在 `sim/p4gates/paths.txt` globs 内 = 预期面）。
- **工作树核**：tracked 修改恰 **22 件**（= 报告清单：15 读侧/TB + `board/wrapper_p4.v` + 5 板产物 + `sim/p4sim/matrix_p4dfix.log`）✓。
- ⛔ **裁定口径**：本件不下 PASS/FAIL；"未观测到"≠"不存在"。⚠️ **本刀新锥不在 DP 前 10** 只到"结构/时序读数"层；板级行为面（RFC 注入 A/B）属后续板级轮。
- **裁定**：接受入库（22 件 + 本轮归档目录 + 两个 `p7b_build_archive/*/SHA256SUMS.txt` = 0x25 补笔与 0x26 本件）。
