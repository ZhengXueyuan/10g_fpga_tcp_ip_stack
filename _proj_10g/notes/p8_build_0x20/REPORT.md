# P8 构建轮（BID `0x20` = 镜像采集侧 8 B/拍修复）—— REPORT

**边界声明**：未烧板 / 未连 JTAG / 未 ssh 对端 / 未写 QSPI / 未改 `rtl/`（一律只读）/ 未走 GUI `vivado_prj`
旧 wrapper / 仓内无 `prj_*` scratch。构建只走 `board/run_build_p7b_ku5p.bat`。git **只读（未提交）**。
**本轮不下 PASS/FAIL 裁定、不写"时序已解决"、不把"未观测到"写成"不存在"。**

| 项 | 值 |
|---|---|
| 位流 | sha256 **`998ff90f31907750f31024d2aa62828a8e08c3cd097b03fc9eb15a82b037d244`** / **15,431,261 B** |
| 位流身份 | `BUILD_ID_V = 32'h00000020`（源码面）；⭐ **编进合成的那份副本逐字已核**：`vivado_prj/p7b_ku5p_prj.srcs/sources_1/imports/board/wrapper_p4.v` = `8d9374c5…`（= 工作树 `board/wrapper_p4.v` 同 hash / 同 300,699 B），其 `:4332` 现读 `32'h00000020`。⚠️ **位流面回读（板上 `0x04`）本轮未做 —— 需烧录**（见 §7） |
| 构建 | `P7B_WNS = 0.154` / `P7B_WHS = 0.010`；**三类失败端点 `0 / 0 / 0`**（setup 0/261,754 · hold 0/261,754 · pulse-width 0/84,862）；`BUILD_EXIT=0` / `BAT_RC=0`；**一次收口**（未重跑）；`CONVERGED_AT_ROUND=2` / `IS_LOCKED_POSTGEN=0` |
| 矩阵 | **17/17 门 EXIT=0，`gates failed: 0`，`VERDICT: FROZEN`，`MATRIX_RC=0`** |
| 几何 | **不变**：71 字（`SNAP_NW_P6E = 71`）/ 未实现地址 `0x14C`（与 0x1F 逐字相同） |
| DP 域 | `g_hw.clk_out0` setup WNS **`+0.154` = 全局最差**；最差路径 `u_tcp_tx/u_fifo_a/rptr_reg[3]/C → u_tcb/rcv_nxt_r_reg[5][9]/CE`（lvl=16，路径组 `g_hw.clk_out0`） |
| M1 族 | **DP 组内**最紧 slack **`+0.515`**（`u_mir/acc_cnt_r_reg[0]/C → u_mir/u_fifo/mem_reg_64_127_35_41/RAMA/WE`）⇒ 与 DP WNS 隔离度 **0.361 ns（3.34×）**；**全钟面**最紧 `+0.161`（lvl=0 的异步复位 CLR 路径 `u_pcie_xdma/…/user_reset_reg/C → u_mir_c2h/rresp_reg[1]/CLR`，**非 DP setup** ⇒ 与 DP WNS 不同对象，只登记不比大小） |
| 资源（placed） | LUT **78,156** / FF **74,723** / BRAM tile **352**（R36 321 + R18 62）/ URAM **0** / DSP 4 / BUFGCE 4 / GTYE4 6；对照 0x1F 后布线（LUT 77,536 / FF 74,657 / BRAM 352）⇒ **跨网表差值 LUT +620 / FF +66 / BRAM ±0，无拆刀臂 ⇒ 不归因** |
| DRC | 69 checks，**全 Warning（0 Error / 0 Critical）**；`route_design completed successfully` / `write_bitstream completed successfully` |

---

## §0 与派单描述不符的四点（如实报，未迁就）

1. **读侧脚本没有 `0x20` 阶段**。`apply_readside_bid1c.py` 的阶段链（`STAGES`）开工时**末代 = `0x1F`**，
   `--bid 0x20` 会直接 `SystemExit("不支持的 --bid")`。⇒ 本轮**先扩脚本再加一阶段 ⑤**（见 §1-A0），
   然后按脚本既定阶段顺序跑（dry-run → rehearse → negctl → apply → assert → face → neg_rehearse）。
   **"按既定阶段跑"不是能直接完成的事** —— 扩阶段这一步是新增工作（24 处 edit + 1 条 ALLOW + 文档/用法两处）。
2. **`sim/p4sim/run_matrix_p4dfix.bat` 不存在**。`sim/p4sim/` 下只有 **shim** `run_matrix_p4dfix.sh`
   （它 exec `cmd //c` 真 runner）；真 runner = **`sim/p4gates/run_matrix_p4dfix.bat`**。本轮用 shim（= CLAUDE.md 文档口径）。
3. ⛔ **派单给的构建调用式 `MSYS_NO_PATHCONV=1 cmd //c '…'` 静默不执行**（#72 族新变种）：
   两个保护**互相抵消** —— `cmd //c` 之所以能跑，靠的正是 MSYS 把 `//c` 改写回 `/c`；加了 `MSYS_NO_PATHCONV=1`
   就不改写 ⇒ `//c` 原样进 cmd ⇒ **cmd 起成交互式 shell、bat 一行没跑，而 `$?` 仍 = 0**。
   实测三式 A/B：`MSYS_NO_PATHCONV=1 cmd /c` ✅ / `cmd //c`（无 env）✅ / **`MSYS_NO_PATHCONV=1 cmd //c` ❌**。
   抓它的判据 = **`board/p7b_ku5p_stdout.txt` 的 mtime 仍是上一次构建（12:01）** + 控制台只有 cmd banner
   （无 `ARCHIVE_*` / `P7B_*`）。⇒ 改用 **`MSYS_NO_PATHCONV=1 cmd /c`**（同为 0x1F 轮的实际用法）。
4. **`sim/p6e_pcie/run_tb_p6e_pcie_counters.bat` 里没有 BID 常量**（grep 0 命中）。
   BID 期望常量在**它驱动的 TB** `sim/p6e_pcie/tb_p6e_pcie_counters.v:206`。
   开工时该 TB = `32'h0000001F` = 树值 ⇒ **在 HEAD 上并不"落后一版"**（登记的"落后"观察写于**上一轮读侧同步
   `0x1F` 之前**，见 `p7b_build_0x1F/REPORT.md:173` ⑥；阶段 ④ 在 10:53 已把它带到 `0x1F`）。
   ⇒ 结论：**该 TB 常量被覆盖**（阶段 ⑤ 已把它 0x1F → 0x20）；**那个 .bat 本身未动**（它没有该常量，按派单不顺手改）。
   ⚠️ 该 TB 不在 17 门矩阵内、本轮**未跑**（见 §7-4）。

---

## §1 A 读侧 BID-only 同步 `0x1F → 0x20`

### A0 阶段 ⑤（本轮新增，写进 `_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py`）

- `EDITS_20` + `E5()` + `STAGES` 追加 `("0x00000020", EDITS_20, "P8 镜像 8 B/拍 (2026-10-11)", 71, 0x14C)`
  （**BID-only**：几何与 0x1F 逐字相同）；用法行改为由 `STAGES` 派生；顶部 docstring 加"本头顶只写到阶段②、
  权威阶段表 = 文件中部 `STAGES`"的指针。`git diff --stat` = **+138 行**（该脚本）。
- **本阶段 24 处 edit / 14 文件**（= 阶段 ④ 的 BID 面逐条 +1 代；④ 里 3 个**纯几何**目标
  `p7b_biz_win/run_xvlog_wrapper.bat` · `sim/p5wu_p1p2/run_xvlog_wrapper63.bat` · `_proj_10g/p7b_chain/sim/tb_p7b_chain.v`
  几何未动 ⇒ 本阶段不列）。
- **覆盖的 14 文件**（逐条）：`_proj_10g/notes/p7b_affinity/j6_r6fix.sh`(2 处) ·
  `_proj_10g/notes/p7b_biz_tcpreg/tcpreg_j6.sh`(2) · `_proj_pcie/p7b_biz/p7b_snap.sh`(2) ·
  `_proj_pcie/p6e_snap_check.sh`(1) · `_proj_pcie/p7b_gate4_accept.sh`(1) · `_proj_pcie/p7b_gate4_selftest.sh`(2) ·
  `_proj_pcie/p7b_gate4_negctrl.sh`(2) · `_proj_pcie/p7b_gate4_livefake.sh`(2) · `_proj_pcie/p6e_snap_selftest_fix2.sh`(1) ·
  `_proj_10g/notes/p7b_gate4_3/final_state.sh`(1) · `_proj_10g/notes/p7b_gate4_criteria/gen_inputs.py`(4) ·
  `sim/p6e_pcie/tb_p6e_pcie_counters.v`(1) · `sim/p6e_pcie/tb_p6e_pcie_wrapper.v`(1) ·
  `_proj_10g/notes/p7b_a3_negctl_20261010/step0_selfcheck.sh`(2)。
- 另加 **1 条 ALLOW**（分类动作，见 A1-B）；**未改**任何 ALLOW 外的件。

### A1 逐阶段读数（原始件全在本目录）

| 阶段 | 命令 | RC | 读数 |
|---|---|---|---|
| **dry-run** | `--bid 0x20` | 1（**预期**：C 红 = 待改处） | 24 处 **hits=1/1 全 OK**；A 表长 5/5 OK；B 搜索面 4 族 257 命中文件，**3 条未登记命中**（见下）；C = 24 条红（= 待改清单）；D `EDIT_COVERAGE 14/14` |
| **B 面分类** | — | — | 未登记命中 = `_proj_10g/notes/p8_board_20261011/burn_0x1F.sh`（bid-oldvalue + geometry-NW 两族）与 `…/p8_board_20261011/_tools/static_protocol_probe.sh`（unimpl-addr 族）。**核过内容**：前者 `WANT=<0x1F 位流 sha256>` + `EXPBID=0x0000001F` + `NW=71`，**烧的就是 0x1F 归档位流**；后者是该轮部署件快照（硬地址 0x13C/0x140/0x144/0x14C）。⇒ 三档归为 **"旧位流读法/位流绑定（只登记不改）"**，加 1 条 ALLOW（**未改那两个文件**） |
| **rehearse** | `--rehearse` | **0** | 阶段 ⑤：`applied=24 / skipped=0`；搜索面 4 族 249 命中文件 **全登记**；A/B/C/D 全绿；`REHEARSE OK —— 清单完整且自洽 … 0 fail` |
| **negctl（有牙）** | `--negctl={table,bid,tier,face}` | **1 / 1 / 1 / 1** | **4 条全"有牙"**：table = 删 WLABEL 末项 ⇒ 恰 1 条红；bid = 把 `j6_r6fix.sh` 的 EXPECT_BID 改成 0x09 ⇒ 24 条红**含目标断言** `j6_r6fix.sh[BID]`；tier = 把档表首行改错代 ⇒ 24 条红**含** `tcpreg_j6.sh[TIER_TOP]`；face = 造未登记新文件带上一代值 ⇒ 3 条红 |
| **neg_rehearse** | `neg_rehearse.py 0x20` | **0** | 故意漏末阶段最后一处 ⇒ **FAIL 恰 1 条**（`step0_selfcheck.sh[BID]`）⇒ "漏一处 = 恰好那处红" |
| **apply** | `--bid 0x20 --apply` | **0** | `APPLY_READSIDE_BID OK (target 0x00000020, 1 阶段 / 24 处 edit, 0 fail)`；**14/14 件 SHA 全变**（before/after = `TARGET_SHA_BEFORE_BID20.txt` / `POSTAPPLY_SHA_BID20.txt`） |
| **assert（落盘后）** | `--bid 0x20 --assert` | **0** | `0 阶段 / 0 处 edit, 0 fail`；搜索面 OK（4 族 249） |
| **face（落盘后）** | `--bid 0x20 --face` | 0 | 249 行 / 123 文件（每行 = 族 + 文件 + 分类） |
| **negctl postapply** | 同上 ×4 | **1 / 1 / 1 / 1** | **各只剩注入的那条红**：table 1 / bid **1（含目标）** / tier **1（含目标）** / face 3 ⇒ 落盘后断言面无其它红 |
| **neg_rehearse postapply** | `neg_rehearse.py 0x20` | **0** | 反演重建 apply 前态后同结论：**恰 1 条红** |

**交叉核对（读侧"上一代同步未被破坏"）**：14 件 apply 前 SHA 与 0x1F 轮的 `POSTAPPLY_SHA_BID1F.txt` 逐条对 ——
**13/14 逐字相同**；唯一差异 = `sim/p6e_pcie/tb_p6e_pcie_wrapper.v`（`bb645968…` vs 该轮 `cbd6ffd9…`）
= **本刀（镜像修复轮）对它做过 4 B→8 B 注入期望改动**，属预期。⇒ 读侧 0x1F 那一代在 HEAD 上**完好**。

**落盘后权威源复读**：脚本现读 `AUTHORITY board/wrapper_p4.v: SNAP_NW_P6E = 71 / BUILD_ID_V = 0x00000020`
且**不再打警告行**（dry-run 时打的"wrapper ≠ 目标"警告 = 当时 B 项还没做）⇒ 设代收口。

---

## §2 B `BUILD_ID_V` 0x1F → 0x20（`board/wrapper_p4.v`）

| 项 | 改前 | 改后 |
|---|---|---|
| `.BUILD_ID_V`（行 `:4332`） | `32'h0000001F` | **`32'h00000020`** |
| 该行注释块 | 顶部 = `//   ⭐ 本轮构建 (2026-10-11): **0x1E → 0x1F**。` | **新增 0x20 段（22 行）**：P8 镜像采集侧 8 B/拍修复（写口 32→64 位 / 读侧 64→2×32 拆分 / DMA 口 2 逻字拍 / 环写口 64 位 / 同批 `cap_on` 并入写门）+ 成因（位流 0x1F 的板级三条签名：丢字恒一半 / 偶数组全收奇数组全丢 / `first_mismatch` 恒 8）+ **几何不变（71 字 / 0x14C）** + 回退点（回滚本刀提交 `193f06a`）+ 历史链；0x1F 段**整段降级进新的 `---- (以下为历史, 逐字保留) ----`**（逐字未动） |
| `:2144` 一带 persist 注释头 | `// ⭐ 现役构建配置 (persist 自 **0x1D** 起开; 本版 **0x1E** 沿用):` | **`本版 **0x20** 沿用`** —— 先读后判：该句 = **版本戳性质**（"本版"指当前构建配置；当时已落后一版），按派单顺带更新 |

**核验**：`git diff --stat board/wrapper_p4.v` = **只有 2 个 hunk**（`:2141` 一行 + `:4332` BID 块）、**29 insertions / 2 deletions**；
**未动** M1 块与 `:1319-1322` app 总线 tie-off（逐字保持）。改后工作树 sha256 = **`8d9374c5…`**（300,699 B），
与**合成实际读到的那份 import 副本 hash 逐字相同**（见上表"位流身份"行）。

---

## §3 C 完整构建

- **入口**：`MSYS_NO_PATHCONV=1 cmd /c 'D:\repo\XCKU5PMini\udp_hls_10g\board\run_build_p7b_ku5p.bat'`（见 §0-3）。
- **新鲜性判据（#72）**：`ARCHIVE_DONE 20261011_153318 files=19`（本次独有串；归档的是上一版 0x1F 的 impl 产物）+
  `board/p7b_ku5p_stdout.txt` 由**陈旧 12:01** 变为 **16:07:58** 收尾 + 控制台含 `BUILD_EXIT=0` / `BITSTREAM-OK`。
  **时间线**：`board/wrapper_p4.v` mtime **15:32:34**（B 项）→ 构建启动 **15:33:18**（晚 44 s）⇒ 编的是 0x20 树。
- **读数**（`board/p7b_ku5p_stdout.txt` + `board/p7b_ku5p_timing.rpt`）：
  `P7B_WNS = 0.154` / `P7B_WHS = 0.010` / 三类失败端点 **0/0/0** / `P7B_BIT_EXISTS = 1` /
  **`All user specified timing constraints are met.`** / DRC 69 checks **全 Warning**。
  `P7B_WPWS` 打印的是**逐组 slack 列表**（34 个数，最小 0.010），**不是**单一 WPWS —— 逐字留档在 stdout 副本里。
- **DP 域最差路径**：`u_tcp_tx/u_fifo_a/rptr_reg[3]/C → u_tcb/rcv_nxt_r_reg[5][9]/CE`（lvl=16，= 全局最差）；
  DP 组内 setup `0/144,352` 失败端点，hold `0/144,352`，pulse-width `0/51,202`。
- **M1 面（定向查询 `q_0x20.tcl` / `query_out/`，`QUERY_EXIT=0`）**：M1 cell **1905** 个；
  DP 组内最紧 `+0.515`；`m1_app_core to_worst = +0.329`；环 from `+1.091`；c2h from `+0.881`；
  **M1 cell 在全局 top5 = 0 命中**（G#1 = DP +0.154；G#2–#4 = `+0.161` 异步复位族；G#5 = +0.162 DP）。
  其它族挤动复核：`ps_*`（persist）最紧 `+0.268` · `whi_r`/`ring_hi`（缺陷刀）`+1.215`/`+1.230` · `pend_wnd`（snd_wnd 守卫）`+1.151`
  —— **都远离最差面**（只登记读数，不做归因）。
- **`BUILD_ID_V` 回读**：源码面 `0x20` ✅ + **合成副本面 `0x20`** ✅；**位流面 = 未做**（见 §7-1）。

---

## §4 D 常驻矩阵 17/17（不是 filter 子集）

- **入口**：`bash sim/p4sim/run_matrix_p4dfix.sh`（内部 = 真 runner `sim\p4gates\run_matrix_p4dfix.bat`）；
  **`MATRIX_RC = 0`**；日志 = `sim/p4sim/matrix_p4dfix.log`（副本 `matrix_p4dfix.log` / `matrix_stdout{,_utf8}.txt`）。
- **逐门清单（17/17 全 `EXIT=0`）**：chain · burst200 · trunc50 · trunc100 · halfdrop · txdrop50 · gate4096 ·
  dupstorm · pcackoob · vlanchain · vlanburst · stallgate · unit_retx · unit_fifo · unit_vlan · unit_uart · p5_wrapper。
  `gates run : 17 / 17` / `gates failed: 0` / `VERDICT: FROZEN -- all 257 hashed files byte-identical across the run`。
- **跑动期间零漂移**：`DIGEST_COMPILE`(212) / `DIGEST_ALL`(257) BEFORE = AFTER 逐位相同；`HEAD` BEFORE = AFTER = `20d880f`。
- **静默门复核**：`unit_retx` = **`ALL 7 GROUPS PASS`**（`$finish` @111,486 ns）；
  `unit_fifo` = **`PASS_ALL  frame_fifo unit: writes A=568139 B=595715 C=616302 pops A=567224 B=591216 C=611802 cycles=750700`**
  （C=616302 与既存基线**逐字相同**）。`p5_wrapper` 尾 = `P5 WRAPPER OK`。
- **环境变量警告 = 14 行 / 4 组**（trunc50/trunc100/halfdrop 各 4 + pcackoob 2），与上一轮同量、既存显示瑕疵。
- ⭐ **#52/#54-第三形态检查（指纹里的文件 ≠ 提交版本）—— 逐条对完，如实报**：
  - 指纹里 `board/wrapper_p4.v` 行 = `SHA256 8d9374c5… board/wrapper_p4.v 300699`；
    **工作树现读 = `8d9374c5…` ⇒ 逐字相同**（指纹 = 绑工作树，证据绑定成立）。
  - `git show HEAD:board/wrapper_p4.v`（按工作树 CRLF 口径复算）= **`a3f49322…` ≠ `8d9374c5…`**。
    ⇒ **本轮的矩阵 FROZEN 绑定的是【工作树】修订，不是 HEAD**：0x20 那一版差异（B 项）**尚未提交**。
    （`a3f49322…` 正是上一轮报告里记的 0x1F-era 工作树值 ⇒ 佐证差异 = 本轮的 B 项。**这不是新缺陷，是口径**；
    要与"提交版本"绑，必须先把这批改动提交、或提交后重跑。）
  - ⚠️ **并发面**：HEAD 由开工 `193f06a` → 矩阵跑动前已推到 **`20d880f`**（审查 agent 的提交，
    `git show --stat` = **只有 `_proj_10g/notes/p8_mir8b_impl_20261011/{REPORT.md,REVIEW.md}` 两个文档**，
    **不涉 RTL/顶层/构建**）⇒ 矩阵的漂移判据不受影响。
- ⛔ **覆盖声明（空证据面，照实报）**：6 个 manifest（chain/fifo/p5wrapper/retx/uart/vlan_src.f）**逐个现核**：
  `app_rx_mirror` / `aximm_c2h_win` / `mir_dma_ring` / `aximm_h2c_discard` / `axi_regs` 命中数 **全 0**
  ⇒ **17 门里没有一门编译本刀改的两个文件**（`rtl/app_rx_mirror.v` / `rtl/mir_dma_ring.v`）；
  唯一编译 `board/wrapper_p4.v` 的门 = `p5_wrapper`，而它是 **`-d APP_MODE` 单域遗留分支**（其 manifest 头自述）
  ⇒ **本刀的 8 B/拍改动在该门里根本没被 elaborate**。⇒ **17/17 绿对本刀是空证据**
  （本刀的门证据在 `sim/p7b_mir/` 与 `sim/p6e_pcie/`，见 `p8_mir8b_impl_20261011/REPORT.md` §4）。

---

## §5 E 归档（本目录，全部在本轮之内落盘 —— #54）

`wrapper_p4.bit`（15,431,261 B）· `wrapper_p4_routed.dcp` · `board_rpt/`（timing/util/drc/clk-util/control-sets/
power/route-status/runme.log + `board/` 五份 rpt + synth util）· 定向查询 `q_0x20.tcl` + `run_q.bat` + `query_out/`
（`dp_top10.rpt` / `dp_top50.rpt` / `global_top5.rpt`）+ `q_stdout.txt` · 矩阵件（before/after 指纹 + `matrix_p4dfix.log` +
`matrix_stdout.txt` / `_gbk_original` / `_utf8`）· 读侧件（dry-run/rehearse/apply/assert/face/negctl×4/neg_rehearse×2 +
`TARGET_SHA_BEFORE` / `POSTAPPLY_SHA`）· `build_console.txt` · `stage1F_edits_dump.txt` · `PROGRESS.txt` ·
**`SHA256SUMS.txt`**。另：构建脚本自带归档 `_proj_10g/notes/p7b_build_archive/20261011_153318/`（19 件 = 上一版 0x1F 的 impl 产物）。

---

## §6 口径声明（哪些变了 / 哪些逐字不变）

**变了**：① 14 个读侧文件（BID 0x1F → 0x20 + 注释代际）；② `board/wrapper_p4.v`（B 项：1 值 + 2 段注释）；
③ `apply_readside_bid1c.py`（+阶段⑤/+ALLOW/+文档，**+138 行**）；④ 构建产物 `board/p7b_ku5p_{stdout.txt,timing,util,drc,clkinteract}.rpt`
与 `sim/p4sim/matrix_p4dfix.log`（跑动即重写，上一轮同形）；⑤ 新文件全在 `_proj_10g/notes/p8_build_0x20/` 与
`_proj_10g/notes/p7b_build_archive/20261011_153318/`。

**逐字不变**：几何（71 字 / `0x14C` / 各读侧表 71 项 / 假板子 11 条地址）· M1 块与 `:1319-1322` tie-off ·
`rtl/`（本轮**一个字节未写**）· 两个 TB 的 UNIMPL/几何期望 · 所有"历史/逐字保留"注释行 ·
`unit_fifo` 的 C=616302 读数（与既存基线逐字同）· 矩阵 `DIGEST_COMPILE`/`DIGEST_ALL`。

**不许当已答**：本报告**不下时序裁定**（`+0.154 / 0/0/0` 是读数，不是"解决"；跨网表差值不归因）。

---

## §7 未定项（没跑 / 没覆盖 / 只能写"未观测到"）

1. **位流面身份回读未做**：板上 `0x04` 门（真正的回读）**需烧录**，本轮不烧 ⇒ 只能写"源码面 + 合成副本面 = `0x20`；
   板面 = 未测"。
2. **板级完全未验**：本刀（8 B/拍）与 BID `0x20` 位流**都没有任何板级读数**；`0x20` 的板级演示 = 另派一轮。
3. **矩阵不覆盖本刀 RTL**（§4 覆盖声明）⇒ 17/17 绿**不能**当作本刀的回归证据。
4. **`run_tb_p6e_pcie_counters`（TB 期望已 = 0x20）本轮未跑**：它不在 17 门内 ⇒ 只能写"常量已同步、未运行验证"。
5. **矩阵指纹 ≠ HEAD**（本轮改动未提交）⇒ FROZEN 绑工作树；提交后若要"绑定提交版本"需重核/重跑（§4）。
6. **首跑（form-3）的原始控制台被覆盖**：证据只剩 `PROGRESS.txt` 里的引文 + 当时记下的 stdout mtime（12:01）；
   `build_console.txt` 现内容是**成功那次**的。
7. **继承未收口**（不属本轮范围，登记不清零）：`cap_on` 写门修复的**板级可达性未证**（前轮 §3）；
   读侧/工具**8 字节对齐**未做（前轮 §6-2）；`sim/p6b_lint` 清单不含这两件；H2C 写通道从未激励。
8. **并发面**：HEAD 开工后由 `193f06a` → `20d880f`（文档 only，已核）；本轮所有改动**未提交**（git 只读）。
