# P11（双 SFP+）· F-21 修复 + 0x2D 准备轮 —— FIX_REPORT

- 日期：2026-10-18
- 仓库根：`D:\repo\XCKU5PMini\udp_hls_10g`，开工 HEAD = `a35f9a14`（与派单一致）
- 权威输入：`_proj_10g/notes/p11_build_0x2C_20261018/README_FOR_TL.md` §4/§5 +
  `gates/{SNAP_PROBE,FANOUT_PROBE}_0x2C.txt` · `DESIGN_v2r1.md` §3.4/§3.5 + 附录 E · 台账 §10-139
- 纪律：**未跑 Vivado 构建、未烧板、未碰 QSPI、未写 git**；门期间零 RTL 写入；
  xsim 与 Vivado 不并行。本报告**不下 PASS/FAIL 裁定**；"未观测到" ≠ "不存在"。

## 0. 一句话（分层口径）

1. **F-21 修法已实施（源码面）**：`snap_dout_all` 顶部 5 项改为 `p7bdp_dout[43..39]`，
   `w8x_snap` 直连块已删除；非 DUAL 的 N-10 tie-off 仍经 `w8x_dp → p7bdp_din[39..43] → CDC`。
2. **两层结构门已就位**：静态门 `check_snap_top5_wired.py` 已挂进 p7b_chain 门（24 门矩阵内，
   矩阵日志里有 `SNAP_TOP5_STATIC_PASS`）；布后门 `P7B_SNAP_TOP5_CDC` 已写进构建 tcl，
   **正读数要等 0x2D 构建**；本轮用 0x2C 的 synth checkpoint 做了**负对照**（门有牙，见 §2）。
3. **BID = 0x2D**（0x2C 从未烧板；乙顺延 **0x2E**）；**`TO_CYCLES = 16'hFFFF`**（用户已批；
   模块默认仍 0）；读侧已链式同步 0x2D：`--assert` **0 fail**、从 0x2C 重放 **20/20 逐字节相同**。
4. **门**：G2/G3/G4/G5/G6/G7 全 EXIT=0；G9 静态门 PASS（负对照 FAIL）；24 门矩阵跑完
   **23/24 EXIT=0**，唯一红 = `f3_resync` 的 M2 臂**没跑起来**（xs.log 无 arm banner + 残留
   `xsimk.exe`；杀残留后同门 standalone **PASS**）—— 登记为工具级瞬态，**不写成 24/24**（见 §5）。
5. **未构建 0x2D、未上板**：布后门正读数、0x2D 时序/资源、W83..W87 板级相干性全部未测。

## 1. 改动清单

### 1.1 RTL / 构建（A1–A5）

| # | 文件 | 改动 |
|---|---|---|
| A1 | `board/wrapper_p4.v:5032-5056` | `snap_dout_all` 顶部 5 项 `w87_snap..w83_snap` → `p7bdp_dout[43*32 +: 32] … [39*32 +: 32]`；删除 `ifdef DUAL_SFP_A`/`else` 两支的 `w8x_snap` 声明与 `assign`（整文件 **+17 / −25**） |
| A2 | `_proj_10g/p7b_chain/sim/check_snap_top5_wired.py`（新） | 静态结构门：①顶部 5 项 = `p7bdp_dout[43..39]`；②无 `w8x_snap` / 无 `assign w8x_snap = w8x_dp`；③`p7bdp_din[39..43] = w83_dp..w87_dp` 五条在位；④N-10 tie-off 存在性（`w83/84/86/87 = 0` 各 2 处、`w85` 真 3 处）。PASS/FAIL 行 + 退出码 |
| A2 | `_proj_10g/p7b_chain/sim/run_tb_p7b_chain.bat:38-43` | 在编译前调用上面的静态门；失败 = `SNAP_TOP5_STATIC_GATE_FAIL` + exit 1（⇒ 进入 24 门矩阵） |
| A2 | `sim/p4gates/paths.txt:FINGERPRINT_GLOBS` | 加 `_proj_10g\p7b_chain\sim\*.py`（否则新门文件不在矩阵指纹里 = #52 盲） |
| A2 | `board/build_p7b_ku5p.tcl:391-443` | 新增 `P7B_SNAP_TOP5_CDC` 段（`open_run synth_1` 内、`close_design` 前）：槽 39..43（位 1248..1407）各至少 1 个 `u_snap_p7bdp/hold_b_reg` 寄存器；`tx_p0_frames_r_reg[0]/Q` 扇出含 `hold_b`、不含 `u_pcie_regs/snap_din`；失败 = `P7B_SNAP_TOP5_CDC_MISSING` / `P7B_SNAP_TOP5_FANOUT_BAD` + exit 1 |
| A3 | `board/wrapper_p4.v:5271` | `BUILD_ID_V = 32'h0000002D`（注释写明 0x2C 从未烧板、乙顺延 0x2E） |
| A4 | `board/wrapper_p4.v:1188` | `rx_merge2 #(.STRICT(1'b0), .TO_CYCLES(16'hFFFF))`（65535 拍 ≈ 419 µs @156.25 MHz；**`rtl/rx_merge2.v` 默认仍 0**） |
| A5 | `board/run_build_p7b_ku5p.bat:74-80` | `P7B-MODULE-MISSING-OR-BLACKBOX` 改 **`/B` 行首锚定**；并新增 `/B` 锚定的 `P7B_SNAP_TOP5_CDC_MISSING`/`P7B_SNAP_TOP5_FANOUT_BAD` 硬门与 `P7B_SNAP_TOP5_` 读数行 |

### 1.2 读侧（A6）

- `_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py`：
  新增阶段 ⑱ `0x0000002D` = **`EDITS_2D` 显式增量 26 处 / 15 文件**（BID-only；几何仍 88 字 / 0x190）；
  新增 ALLOW 条目（本轮生成器/证据件含补丁左值）。**历史注释逐字保留**；只改被 `DEFAULT_SPECS`
  断言的"现役代自述"行与两个 j6 台架 `GEOM_TIERS` 顶端**新增**一行。
- 15 个文件：`step0_selfcheck.sh` · `j6_r6fix.sh` · `tcpreg_j6.sh` · `tb_biz_win.v` ·
  `final_state.sh` · `gen_inputs.py` · `p6e_snap_check.sh` · `p6e_snap_selftest_fix2.sh` ·
  `p7b_snap.sh` · `p7b_gate4_accept.sh` · `p7b_gate4_livefake.sh` · `p7b_gate4_negctrl.sh` ·
  `p7b_gate4_selftest.sh` · `tb_p6e_pcie_counters.v` · `tb_p6e_pcie_wrapper.v`。
- **20 文件同步口径**：D-4 的 20 文件清单全部复核；其中 5 个（`check_window.py` /
  `run_tb_biz_win.bat` / `run_xvlog_wrapper.bat` / `tb_p7b_chain.v` / `run_xvlog_wrapper63.bat`）
  只有 NW/UNIMPL 几何、无 BID 默认值 ⇒ 本 BID-only 阶段不动（已由 `--assert` 复核为 88/0x190）。
- 生成器 / 证据：`gen_edits_2d.py`、`EDITS_2D_block.py`。

### 1.3 门/判据联动修复（非派单条目，但为矩阵绿所必需）

- `_proj_10g/notes/p7b_biz_win/check_window.py`：判据 **5a** 原来期望顶部 5 项 =
  `w87_snap..w83_snap` —— 那正是 **0x2C 的缺陷形态**（等于把 F-21 锁死）。已改为期望
  `p7bdp_dout[43..39]`；这是本轮矩阵第一次跑的**唯一红**（见 §5.1），修后 `PASS=113 FAIL=0`。
- `_proj_10g/p7b_chain/sim/elab_files.f` 被 G7 重新生成（运行时 `dir /b /s rtl\*.v` 的产物）：
  内容从 0x2B 的 HLS 网表名转到现役 0x2C 网表名（`LOOP_219→223` 等），属**生成物更新**，不是手改。

### 1.4 文档（A7）

- `DESIGN_v2r1.md`：附录 E 新增 **E-5 F-21**（见 §8 的编号说明）。
- `P7B_OPEN_ITEMS.md` §0-72：追加"修法已实施、待重建验证"的状态行（原句保留）。
- `P7B_BIZ_WINDOW.md`：§1 **本来没有 W83..W87 行、且标题停在 83 字 / BID 0x2B**
  ⇒ 补 5 行 + F-21 CDC 注 + 几何/未实现地址更新（0x190），顶部加 0x2D 更新块。

## 2. F-21 两层门的实际读数

### 2.1 静态门（源码面；已挂进 p7b_chain 门）

正例（现树）：`_proj_10g/notes/p11_fix_f21_20261018/gates/snap_top5_static_POS.txt`

```
[ok] [1] snap_dout_all 顶部 5 项 = ['p7bdp_dout[43*32 +: 32]', 'p7bdp_dout[42*32 +: 32]',
                                   'p7bdp_dout[41*32 +: 32]', 'p7bdp_dout[40*32 +: 32]',
                                   'p7bdp_dout[39*32 +: 32]']
[ok] [2] 无 w8x_snap (code hits=0) / 无 assign w8x_snap=w8x_dp (hits=0)
[ok] [3] p7bdp_din[39..43] = w83_dp..w87_dp (缺 无)
[ok] [4] N-10 tie-off: zero_hits={83: 2, 84: 2, 86: 2, 87: 2} w85_true_hits=3 (期望 2/2/2/2 与 3)
SNAP_TOP5_STATIC_PASS
```

负对照（HEAD 的 0x2C wrapper，`gates/negctl_prefix_tree/board/wrapper_p4.v`）：

```
[FAIL] [1] snap_dout_all 顶部 5 项 = ['w87_snap', 'w86_snap', 'w85_snap', 'w84_snap', 'w83_snap']
[FAIL] [2] 无 w8x_snap (code hits=25) / 无 assign w8x_snap=w8x_dp (hits=6)
SNAP_TOP5_STATIC_FAIL (top5,direct-wire)   RC=1
```

⇒ 门对 0x2C 缺陷形态**有牙**；矩阵内也真的被执行：`gates/matrix_p7b_chain_run2.log:6`
= `SNAP_TOP5_STATIC_PASS (source=…\board\wrapper_p4.v)` 且该门 `EXIT=0`。

### 2.2 布后门（构建 tcl；本轮**无正读数**，只有 0x2C 网表负对照）

- 门代码 = `board/build_p7b_ku5p.tcl` 的 `P7B_SNAP_TOP5_CDC` 段；**0x2D 构建轮执行**。
- 本轮用 **0x2C 的 synth checkpoint**（`vivado_prj/p7b_ku5p_prj.runs/synth_1/wrapper_p4.dcp`，
  read-only `open_checkpoint`，不是构建）跑了**同一段逻辑**做负对照：
  `gates/SNAP_TOP5_PROBE_0x2C.txt`：

```
slot=39 bits=1248..1279 cells=0
slot=40 bits=1280..1311 cells=0
slot=41 bits=1312..1343 cells=0
slot=42 bits=1344..1375 cells=0
slot=43 bits=1376..1407 cells=0
tx_p0_frames_r_reg[0]/Q pins=1
  LOAD tx_p0_frames_r[0]_i_3/I0
  LOAD u_pcie_regs/snap_din[2422]
LOADCOUNT hold_b=0 snap_din=1
```

⇒ ① 布后门在 0x2C 网表上**会红**（槽全 0、扇出 hold_b=0/snap_din=1）；② Tcl 语法与对象名
（`u_snap_p7bdp/hold_b_reg[<bit>]`、`tx_p0_frames_r_reg[0]/Q`）**实测可解析**。
⚠️ 这**不是** 0x2D 的正读数：0x2D 网表是否存在槽 39..43 的 `hold_b`，要等构建轮。
⚠️ 一个**待构建轮确认**的假红风险：若综合把 `tx_p0_frames_r_reg[0]` 复制（`_rep`）以拆扇出，
精确 pin 检查可能只看到复制件而误红 —— 0x2C synth 网表里它是单件（探针实测 pins=1），
但 0x2D 多接了一条 hold_b 负载；构建轮若命中此形态，应按复制件名扩展（不是放宽判据）。

## 3. BID / 读侧重放证据

| 项 | 读数 |
|---|---|
| `BUILD_ID_V` | **`32'h0000002D`**（`board/wrapper_p4.v:5271`）；0x2C 从未烧板；乙顺延 **0x2E** |
| 读侧阶段 | ⑱ `0x0000002D`，**BID-only**，26 处 / 15 文件；几何 88 字 / 未实现 `0x190` |
| `--assert --bid 0x2D` | **`APPLY_READSIDE_BID OK (target 0x0000002D, 0 阶段 / 0 处 edit, 0 fail)`**，`gates/apply_readside_assert_0x2D.log` |
| 搜索面 | 4 族全扫，未登记命中 **0**（`SEARCH_FACE OK`） |
| 从 0x2C 重放 | `git worktree` @ HEAD a35f9a14（`git -c core.autocrlf=false` 保证 LF）；应用 0x2D 阶段 = **26 处 / 1 阶段**，`gates/rehearse_from_0x2C_apply.log` |
| 逐字节比较 | **20/20 相同**（`gates/replay_byte_compare.txt`）。⚠️ 重放前把 3 个 `.bat` 归一成 CRLF 以复现 0x2C 磁盘态（git blob 是 LF、`core.autocrlf=true` 的 checkout 态是 CRLF）；其余文件 LF |
| j6 档表 | 两个 j6 台架 `GEOM_TIERS` 顶端新增 `"88|0x0000002D|61 62|…"`（旧 `88|0x0000002C` 行逐字保留为历史档） |

## 4. `TO_CYCLES` 值

- `board/wrapper_p4.v:1188`：`rx_merge2 #(.STRICT(1'b0), .TO_CYCLES(16'hFFFF))`。
- `rtl/rx_merge2.v` 的 `parameter TO_CYCLES = 0` **未动**（默认关；其它例化零行为变化）。
- 语义：`busy && !sel_tvalid` 连续 ≥ 65535 拍（≈419 µs @156.25 MHz）⇒ 释放 busy、`stat_abort+1`、
  不产生帧计数。回退 = `.TO_CYCLES(4096)` 或 `.TO_CYCLES(0)`（一行）。

## 5. 门 / 矩阵读数

### 5.1 24 门矩阵（两跑；最终树 = 第二跑）

| 跑 | 时间 | 结果 | 说明 |
|---|---|---|---|
| run1 | 13:32–14:02 | 24/24 跑，**23 EXIT=0**，1 FAIL = `biz_win` | 唯一红 = `check_window.py` 判据 5a 期望 `w87_snap..w83_snap`（= 0x2C 缺陷形态）；TB 本体 `PASS_ALL 40 项`、`TB_BIZ_WIN_PASS`。FROZEN 341 文件 |
| run2（**最终树**） | 14:04–~14:34 | 24/24 跑，**23 EXIT=0**，1 FAIL = `f3_resync` | biz_win 已绿（`BIZ_WIN_CHECK_PASS`）；`p7b_chain` 绿且含 `SNAP_TOP5_STATIC_PASS`；唯一红 = M2 臂没跑起来（见下）。FROZEN 341 文件（before=after，`DIGEST_COMPILE=593d907a…`） |

**f3_resync 的那条红（如实登记，不写成 24/24）**：
- `sim/p4gates/work_20261018_140442/f3_resync/_gate_console.log`：`M2 runM2 RC=1 expect 0`；
  `NO-RUN [M2]: no arm banner`；M2 的 `xs.log` 只有 xsim 启动头、**无任何 TB 输出**；
  运行后残留 `xsimk.exe`（PID 31936，创建时刻 = 该臂运行时刻）。
- 该门在 **run1**（同 RTL、同编译集、同 mutant 生成）是 `EXIT=0`；杀残留 xsimk 后
  **standalone 重跑 = PASS**（五臂全过，`gates/f3_resync_standalone_after_run2.log`）。
- 口径：**工具级瞬态（xsim 引擎悬挂，臂未执行）**，不是设计回归；**没有重跑整个矩阵**去凑 24/24
  （避免"重跑到过为止"）。⇒ 最终树的分门证据 = run1（f3）+ run2（其余 23 门）+ f3 standalone 重跑。

### 5.2 定向门

| 门 | 读数 | 证据 |
|---|---|---|
| G2 `rx_merge2` | `RX_MERGE2 TB PASS`，EXIT=0 | `gates/g2_rx_merge2.log` |
| G3 `tx_split` | `TX_SPLIT TB PASS` / `TX_SPLIT_GATE_PASS`，EXIT=0 | `gates/g3_tx_split.log` |
| G4 `slow_tx_port` | `SLOW_TX_PORT TB PASS` / `SLOW_TX_PORT_GATE_PASS`，EXIT=0 | `gates/g4_slow_tx_port.log` |
| G5 `tcp_tx_srcip` | `SRCIP ovl OK` / `def OK` / `mut EXPECTED-FAIL OK` / `mutn6 EXPECTED-FAIL OK` / `SRCIP_GATE_PASS`，EXIT=0 | `gates/g5_tcp_srcip.log` |
| G6 `p11_dual`（真 wrapper + DUAL） | `P11_DUAL TB PASS`，EXIT=0；**臂 B 的 W83/W84 经 p7bdp CDC 仍过**：`[ ok ] B: W84 (ch0 TX frames) +2` · `[ ok ] B: W83 (ch1 TX frames) +1`（整个 TB 21 条 `[ ok ]`，0 FAIL） | `gates/g6_p11_dual.log` + `gates/g6_xsim_p11dual.log` |
| G7 elaboration | **13 组合**：c1..c5/c8/c13 OK；c6/c7/c9/c10/c11/c12 `EXPECTED-FAIL OK`；`ELAB_COMBO_FAILS=0`；`DECLCHECK_EXIT=0`；`ELAB_4COMBO_PASS` | `gates/g7_elab_13combo.log` |
| G9 静态门 | POS `SNAP_TOP5_STATIC_PASS`（4 项全 ok）；NEGCTL `SNAP_TOP5_STATIC_FAIL`（top5 + direct-wire，RC=1）；矩阵内亦执行 | `gates/snap_top5_static_{POS,NEGCTL_prefix}.txt`、`gates/matrix_p7b_chain_run2.log` |

## 6. 与派单描述不符处（如实登记）

1. **附录 E 的编号**：派单写"加 **E-4** F-21"，但 `DESIGN_v2r1.md` 的 **E-4 已被
   「实施级偏离与未测」占用** ⇒ 本轮新增编号 **E-5**（不覆盖既有编号）；已在 E-5 开头写明。
2. **`P7B_BIZ_WINDOW.md` 不只是"补 CDC 描述"**：该文件 §1 当时仍停在 **83 字 / BID 0x2B**，
   **W83..W87 五行根本不存在**（0x2C 构建轮没同步）⇒ 本轮补了 5 行 + 几何/未实现地址更新。
3. **`check_window.py` 的 5a 判据曾把 F-21 缺陷锁死**（期望 `w8x_snap`）⇒ 不修它矩阵不可能全绿；
   这是派单"跑 24 门矩阵"隐含的必修项，已作为 §1.3 登记。
4. 派单说"20 文件同步 0x2D"：本阶段实际改 **15 个文件**；其余 5 个无 BID 默认值
   （已逐项 `--assert` 复核，几何不变）。不是漏改。

## 7. 未测 / 未判定（不许当已答）

- **0x2D 构建未跑**：综合/实现/时序/资源/位流全部未测；`P7B_SNAP_TOP5_CDC` 段的**正读数未取**
  （本轮只有 0x2C 网表负对照）。
- **板级全部未测**：W83..W87 经 CDC 后的相干性、`TO_CYCLES=16'hFFFF` 的实际触发、
  B-0..B-8 对账均未跑；0x2C/0x2D 位流都从未烧板。
- **"裸 CDC 是否真的读出过位混"未观测**（0x2C 从未上板）⇒ "未观测到 ≠ 不存在"。
- F-21 修复的**时序代价未知**：新增 `hold_b`/`dout_a` 槽 39..43 会复活约 **5×32×2 = 320 FF**
  （p7bdp `hold_b` + `dout_a`；`snap_words_r` 本就有）⇒ 0x2D 构建的第一观察对象仍是快照阵列族。
- **f3_resync 瞬态的根因未定位**（xsim 引擎悬挂；已登记残留 xsimk 现象，未做进一步复现）。
- 本轮**未跑** HLS csim（只改 wrapper/读侧，未动 HLS 源）；未跑 `D:\repo\perfv` 相关操作。

## 8. 证据索引（`_proj_10g/notes/p11_fix_f21_20261018/`）

- `gates/snap_top5_static_POS.txt` · `gates/snap_top5_static_NEGCTL_prefix.txt`
- `gates/SNAP_TOP5_PROBE_0x2C.txt` · `gates/SNAP_TOP5_PROBE_CONSOLE_0x2C.txt` · `gates/run_snap_top5_probe_0x2C.tcl`
- `gates/apply_readside_assert_0x2D.log` · `gates/rehearse_from_0x2C_apply.log` · `gates/replay_byte_compare.txt`
- `gates/check_window_pos_after_fix.log` · `gates/biz_win_gate_after_fix.log`
- `gates/g2_rx_merge2.log` · `gates/g3_tx_split.log` · `gates/g4_slow_tx_port.log` ·
  `gates/g5_tcp_srcip.log` · `gates/g6_p11_dual.log` · `gates/g6_xsim_p11dual.log` ·
  `gates/g7_elab_13combo.log` · `gates/g7_xsim_p7bchain.log`
- `gates/matrix_console_run1_pre_checkwindow_fix.log`（run1 控制台）·
  `gates/matrix_console.log`（run2 控制台）· `gates/matrix_p4dfix_run2.log`（run2 权威矩阵日志）·
  `gates/matrix_p7b_chain_run2.log`（矩阵内 p7b_chain 门日志，含静态门 PASS）
- `gates/f3_resync_standalone_after_run2.log`
- `gen_edits_2d.py` · `EDITS_2D_block.py` · `gates/negctl_prefix_tree/board/wrapper_p4.v`

---

## TL 注（2026-10-18，0x2D 首跑后回灌）

- **术语订正**：`P7B_SNAP_TOP5_CDC` 的执行点是 `open_run synth_1` = **综合后（post-synth）**，不是布局后；本报告原文的"布后门"按"综合后门"读（设计附录 E-5 已就地订正）。
- **0x2D 首跑假红（已修）**：门用非 `-leaf` 枚举，命中层次边界 pin `u_snap_p7bdp/tx_p0_frames_r_reg[0]`（`IS_LEAF=0`），漏掉真正的 `u_snap_p7bdp/hold_b_reg[1248]/D`。修法 = `get_pins -leaf`；已用 0x2D 综合 checkpoint 正控（`hold_b=1`）与 0x2C routed dcp 负控（槽 39..43 全 0、直连 `u_pcie_regs/snap_words_r_reg[2656]/D`）验证。
- **0x2D 首跑结果**：构建在综合后门停止，**实现未启动、无位流、无时序/资源读数**；未执行 backstop（四档均绑定时序失败，且删字不会让本门变绿）。
