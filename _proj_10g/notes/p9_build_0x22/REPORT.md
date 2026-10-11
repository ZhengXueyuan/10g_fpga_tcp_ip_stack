# P9 构建轮（BID `0x22` = XDMA 用户接口 `AXI4-MM → AXI4-Stream`）—— REPORT

**边界声明**：未烧板 / 未连 JTAG / 未 ssh 对端 / 未写 QSPI / 未改 `rtl/**`（一律只读）/ 未改 `tb/**` ·
未改 `board/build_p7b_ku5p.tcl`（被验源）/ 未走 GUI `vivado_prj` 旧 wrapper（构建只走
`board/run_build_p7b_ku5p.bat`）/ git **只读**（未提交）。
**本轮不下 PASS/FAIL 裁定、不写"时序已解决"、不把"未观测到"写成"不存在"。**

| 项 | 值 |
|---|---|
| 位流 | sha256 **`c2e48a6961fdb26ad453aa71198b8552e4bdd9c47bbdaf287a7dbd145127635a`** / **15,431,261 B** |
| 位流身份 | 源码面 `BUILD_ID_V = 32'h00000022`（`board/wrapper_p4.v:4272`）；⚠️ **位流面回读（板上 `0x04`）本轮未做 —— 需烧录**（见 §7-1） |
| 构建 | `P7B_WNS = 0.025` / `P7B_WHS = 0.010`；**三类失败端点 `0 / 0 / 0`**（setup 0/257,862 · hold 0/257,862 · pulse-width 0/83,887）；`BUILD_EXIT=0` / `BAT_RC=0`；**一次收口**（`P7B_ROUND #1` 恰 1 次 / `BUILD_EXIT` 恰 1 行 / `P7B DONE` 恰 1 次；stdout 里 3 条 `Exiting Vivado` = 同一次运行的子进程：synth 22:07:40 / impl 22:33:09 / 父 22:34:25）；`P7B_CONVERGED_AT_ROUND=2` / `P7B_IS_LOCKED_POSTGEN=0` |
| ⭐ XDMA 断言组 | **全过**（本构建与以往最大的不同）：`RC_BASE=0` / `RC_INTF=0`（MSG=`<AXI_Stream>`）· 回读 **13/13**（`RB_MISMATCH_N=0`）· 生成产物 6 参数（`GEN_BAD_N=0`）· 与两份冻结参照 diff **只差预期行**（ST=1 `{Component_Name}` / MM=2 `{Component_Name, CONFIG.xdma_axi_intf_mm}`）· **无 `19-3461`/`19-3438`/`17-39` 命中**（`MSG_HIT` 0 条）⇒ **`P7B_XDMA_VERDICT = OK`**（静默回滚**未发生**：日志两层牙 + 回读 + 生成产物三层都绿） |
| 几何 | **不变**：71 字（`SNAP_NW_P6E = 71`）/ 未实现地址 `0x14C`（与 0x21 逐字相同） |
| DP 域 | `g_hw.clk_out0` setup WNS **`+0.025` = 全局最差**；最差路径 `u_tcp_tx/u_fifo_b/rptr_reg[1]/C → u_tcb/rcv_nxt_r_reg[1][17]/D`（lvl=16；logic 1.549 ns / route 4.728 ns = 75.3% 布线）；DP 组内 setup `0/144,484` 失败端点 |
| 本刀主角 `u_mir_axis` | **在网表里**（`get_cells *u_mir_axis*` = 365 cells，顶层单元 ref = `axis_c2h_stream`）；**定向锥（后布线）** FROM ≥ **`+0.914`**（lvl 7，宿 = XDMA `axist_c2h[0].dma_axist_slv/axi_rdy_100_reg/D`）/ TO ≥ **`+0.648`**（lvl 3，源 = `u_mir/u_fifo/rbin_r_reg[0]/C`）；⭐ **`u_mir`（含 `u_mir_axis`）在 global top5 / DP top10 / DP top50 = 全 0 命中** |
| 资源（placed，**board 口径** `board/p7b_ku5p_util.rpt`） | LUT **78,006** / FF **74,200** / BRAM tile **348**（R36 317 + R18 62）/ URAM **0** / DSP 4 / BUFGCE 4 / GTYE4 6；对照 0x21 **同口径**（78,699 / 74,795 / 352）⇒ **LUT −693 / FF −595 / BRAM −4**（⚠️ 跨网表差、**无拆刀臂 ⇒ 不归因**） |
| DRC | **0 Error / 0 Critical**（全 Warning：DPIP-2 4 / DPOP-3 2 / DPOP-4 4 / DPOR-2 18 / REQP-1858 41）；`route_design completed successfully` / `write_bitstream completed successfully` |

---

## §0 与派单描述的对齐检查（如实报）

1. **读侧脚本开工时末代 = `0x21`** ⇒ `--bid 0x22` 会直接 `SystemExit("不支持的 --bid")`。派单已预告
   "0x22 大概要再扩一代" ⇒ 本轮先扩**阶段 ⑦**（`EDITS_22`；**BID-only**，几何 = 71 字 / `0x14C`；
   **24 处 / 14 文件**，与 ⑥/⑤ 同名同形），再照脚本既定阶段顺序跑全阶段。**与派单一致。**
2. **阶段 ⑦ 的清单不是手抄的**：`EDITS_22` 由生成器 `gen_edits22.py` 从 `EDITS_21` 的 **new 侧逐条 +1 代**
   机械导出（代名 `P8-STG 16 B 弹性暂存` → `P9 XDMA MM→AXIS` + 值 `0x21 → 0x22` + 逐代历史链追加），
   自检 **24/24 old 侧锚点逐字在盘上**（= ⑥ 的 new 侧，roundtrip 0 bad）。拼装 = `splice_phase7.py`
   （幂等 + 锚点唯一性硬失败；5 处 splice 各自报 OK）。
3. **构建调用式**：按派单用 **`MSYS_NO_PATHCONV=1 cmd /c '…'`（单斜杠）**；未踩"加 env 再用 `cmd //c`
   互相抵消 ⇒ 静默不跑"的坑。新鲜性判据（#72）= **`ARCHIVE_DONE 20261011_215445`（本次独有串）+
   `board/p7b_ku5p_stdout.txt` mtime 18:27 → 21:55:33 + 控制台含 `BUILD_EXIT=0` / `BITSTREAM-OK`**；
   wrapper mtime 21:54:32 → 构建 21:54:45（晚 13 s）。
4. ⚠️ **HEAD 在轮内被推到 `447f76f`**（开工 = `eb4007b`）。两个提交：`04726a0`（21:49:59，台账 §10-24
   文档，+22 行）· `447f76f`（**22:21:52 = 构建进行中**，审查收录 + 工具侧 D1 修正：4 文件 =
   `p9_axis_impl_20261011/REVIEW.md` · `p9_axis_tool_20261011/{EVIDENCE_stdout.txt,TOOL_REPORT.md}` ·
   `_proj_pcie/p7b_biz/p7b_mir_dump.cpp`）。
   **逐条核过：两提交都不含 `board/` / `rtl/` / `sim/` 构建输入**（`git show --stat` 逐字）⇒
   **对本轮构建读数零影响**；`p7b_mir_dump.cpp` 是主机侧工具、不进位流。
   ⚠️ 但 **`GIT_HEAD` 因此 BEFORE=`447f76f`（矩阵轮）**，与"开工时"不同 —— 见 §4 的指纹绑定口径。
5. `board/wrapper_p4.v` 本轮的 B 项 = **2 个 hunk**（现读行号 `:2144` 版本戳 + `:4272` BID/注释块）；
   ⛔ **未动** M1 块 / `:1320-1321` app 总线 tie-off（现读 `app_reg_addr = 8'h00` / `app_reg_wr = 1'b0` 逐字）/
   P9 的 AXIS 端口表（diff 里 `u_mir_axis`/`s_axis_c2h`/`axis_c2h_stream` 的 3 处命中**全在我新增的注释行**里）。
6. `sim/p6e_pcie/tb_p6e_pcie_wrapper.v` 本轮**动了 1 行**（BID 期望 0x21→0x22）—— 但它与 0x21 轮的
   postapply 指纹不同（见 §1 交叉核对），差异 100% 来自 **P9 提交 `173b18d` 对该 TB 的正文改动**
   （M1-B → P9-B 8 组），**不是本轮读侧同步引入的**（工作树 diff 该文件 = 恰 1 行）。

---

## §1 A 读侧 BID-only 同步 `0x21 → 0x22`

### A0 阶段 ⑦（本轮新增，写进 `_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py`）

- `EDITS_22` + `E7()` + `STAGES` 追加 `("0x00000022", EDITS_22, "P9 XDMA MM→AXIS (2026-10-11)", 71, 0x14C)`
  （**BID-only**：几何与 0x21 逐字相同）；顶部 docstring 加 ⑦ 指针。`git diff --stat` = **+115 / −2 行**（该脚本；
  其中 109 行 = 阶段 ⑦，6 行 = 新 ALLOW 条目）。
- **覆盖的 14 文件（24 处，逐条）**：`_proj_10g/notes/p7b_affinity/j6_r6fix.sh`(2) ·
  `_proj_10g/notes/p7b_biz_tcpreg/tcpreg_j6.sh`(2) · `_proj_pcie/p7b_biz/p7b_snap.sh`(2) ·
  `_proj_pcie/p6e_snap_check.sh`(1) · `_proj_pcie/p7b_gate4_accept.sh`(1) · `_proj_pcie/p7b_gate4_selftest.sh`(2) ·
  `_proj_pcie/p7b_gate4_negctrl.sh`(2) · `_proj_pcie/p7b_gate4_livefake.sh`(2) · `_proj_pcie/p6e_snap_selftest_fix2.sh`(1) ·
  `_proj_10g/notes/p7b_gate4_3/final_state.sh`(1) · `_proj_10g/notes/p7b_gate4_criteria/gen_inputs.py`(4) ·
  `sim/p6e_pcie/tb_p6e_pcie_counters.v`(1) · `sim/p6e_pcie/tb_p6e_pcie_wrapper.v`(1) ·
  `_proj_10g/notes/p7b_a3_negctl_20261010/step0_selfcheck.sh`(2)。

### A1 逐阶段读数（原始件全在本目录）

| 阶段 | 命令 | RC | 读数 |
|---|---|---|---|
| dry-run（扩 ALLOW 前） | `--bid 0x22` | 1（**预期**：C 红 = 待改处） | 24 处 **hits=1/1 全 OK**；A 表长 5/5 OK；**B 报 9 条未登记命中**（+1 条新代暴露的侥幸命中，见下）；C = 24 条红；D `EDIT_COVERAGE 14/14` |
| B 面分类 + 核内容 | — | — | 9 条全**核过内容**（逐条在 §1-B）；新增 **5 条 ALLOW**（未改任何 ALLOW 外文件） |
| dry-run（扩 ALLOW 后） | `--bid 0x22` | 1（**预期**） | 24/24 OK · A 5/5 · **B 4 族 288 命中文件全登记（未登记 0）** · C 24 红 · D 14/14 |
| rehearse | `--rehearse` | **0** | 阶段 ⑦ `applied=24 / skipped=0`；A/B/C/D 全绿；`REHEARSE OK —— 清单完整且自洽 … 0 fail` |
| negctl（有牙） | `--negctl={table,bid,tier,face}` | **1/1/1/1** | 4 条全"有牙"：table = 删 WLABEL 末项（表长 71→70）⇒ 恰 1 红；bid = EXPECT_BID 改 `0x09` ⇒ 24 红**含目标** `j6_r6fix.sh[BID]`；tier = 档表首行改错代 ⇒ 24 红**含** `tcpreg_j6.sh[TIER_TOP]`；face = 造未登记新文件带上一代值 ⇒ 3 红。⚠️ **RC 语义按实现读**：该函数 docstring 写"0=有牙"，**代码实为 `return 1 if teeth else 0`**（末行 `NEGCTL_EXIT=1` + "真实运行会 FAIL 并非零退出"）= **RC=1 是"有牙"**；此处按**代码**读并已留档，docstring 与实现不一致（登记，不算本轮缺陷） |
| neg_rehearse | `neg_rehearse.py 0x22` | **0** | 故意漏末阶段最后一处 ⇒ **FAIL 恰 1 条**（`step0_selfcheck.sh[BID]`） |
| apply | `--bid 0x22 --apply` | **0** | `APPLY_READSIDE_BID OK (target 0x00000022, 1 阶段 / 24 处 edit, 0 fail)`；**14/14 件 SHA 全变** |
| assert（落盘后） | `--bid 0x22 --assert` | **0** | `0 阶段 / 0 处 edit, 0 fail`；搜索面 OK |
| face（落盘后） | `--bid 0x22 --face` | 0 | 280 行 / 139 文件 |
| negctl postapply | 同上 ×4 | **1/1/1/1** | 各只剩注入那条红：table 1 / bid 1（含目标）/ tier 1（含目标）/ face 3 ⇒ 落盘后断言面无其它红 |
| neg_rehearse postapply | `neg_rehearse.py 0x22` | **0** | 反演重建 apply 前态后同结论：**恰 1 条红** |

**交叉核对（"上一代同步未被破坏"）**：14 件 apply 前 SHA 逐条对 0x21 轮 `POSTAPPLY_SHA_BID21.txt` ——
**13/14 逐字相同**；**唯一差异 = `sim/p6e_pcie/tb_p6e_pcie_wrapper.v`**：本轮 apply 前 `dc312ea3…` vs 0x21 轮
postapply `3587a166…` ⇒ **已定位**：P9 提交 `173b18d` 改过该 TB 正文（M1-B 环/AR→R 段 → P9-B 8 组 AXIS 判据），
本轮读侧同步在该文件上**只改 BID 判据那一行**（`git diff` 该文件 = 恰 1 行）⇒ **差异是"树本身被合法推了一代"，
不是读侧同步漏改/多改**。

### A2 B 面分类（9 条未登记命中 —— 逐条核内容后的裁定）

| 文件（组） | 命中族 | **核过的内容** | 裁定 |
|---|---|---|---|
| `_proj_10g/notes/p8_board_0x21_20261011/`（3 件：`burn_0x21.sh` / `_tools/run_arm.sh` / `final_state.sh`） | geometry-NW + identity-BID | `WANT=fbb6fca81076a28b…4892c` = **0x21 位流 sha256**（逐字核）；`EXPBID=0x00000021`；`NW=71`；`BID=${BID:-0x00000021}` | **旧位流读法（位流绑定）** ⇒ ALLOW：改它反而毁掉那一轮取证 |
| `_proj_10g/notes/p8_tcp_0x21_20261011/`（5 件：`final_state_tcp.sh` + `_tools/run_tcp_{arm,bar,mid,pc1}.sh`） | geometry-NW + identity-BID + unimpl-addr | 同上代：`NW=71` / `BID=${BID:-0x00000021}` / `EXPECT_BID=0x00000021` | 同上（0x21 那一代的 TCP 臂现场） ⇒ ALLOW |
| `_proj_10g/notes/p9_axis_impl_20261011/head_negapp/`（2 件：`wrapper_p4_head.v` / `wrapper_p4_negapp_patched.v`） | identity-BID | `wrapper_p4_head.v` = **被 copy 那一刻的 HEAD 副本**（`:4332 .BUILD_ID_V (32'h00000021)` + `SNAP_NW_P6E = 71`）；`_negapp_patched.v` = 在其上打 ¬APP_MODE 的探针副本（同目录 `xelab_negapp.log` 为证） | **编过就丢的一次性诊断副本** ⇒ ALLOW（改它 = 伪造那次排练的产物） |
| `tb/tb_uart_dbg.v`（**本轮新代（家族扩到 0x21）才暴露**） | bid-oldvalue | `sc = 32'h00000021` = **UART diag TB 的 SC 计数器初值**（P4c diag18 行；同族 `sd=…22`/`sf=…23`/`sp=…24`；十进制 33） | **侥幸命中（同名不同物）** ⇒ ALLOW：与位流身份无关；改它会改动该门激励 |

⇒ **ALLOW 净增 4 条 + 1 条侥幸命中 = 5 条**；⭐ **无一条需要改文件**（全部"只登记不动"）。

### A3 交叉对照：本轮改的 15 件 vs 本轮 0x21→0x22 的语义

- `0x21 → 0x22` 面（值 + 注释代际）**只动 BID 字符串**：几何（71 字 / `0x14C` / 各表 71 项 / 假板子 11 条地址）
  **逐字未动**（A 断言 5/5 + D 派生式 `nnew_top+ntx+nnew == NW−51` 全绿）。

---

## §2 B `BUILD_ID_V` 0x21 → 0x22（`board/wrapper_p4.v`）

| 项 | 改前 | 改后 |
|---|---|---|
| `.BUILD_ID_V`（行 `:4272`） | `32'h00000021` | **`32'h00000022`** |
| 该行注释块 | 顶部 = `//   ⭐ 本轮构建 (2026-10-11): **0x20 → 0x21**。` | **新增 0x22 段（48 行）**：P9 XDMA MM→AXIS（内容 = 新件 `axis_c2h_stream` / 端口表 75→50 / 构建脚本断言组 / `axi_regs.ver` 3→4 / 几何不变 / 门与 synth 检查点读数 / **回退点** = 烧 0x21 归档位流 `fbb6fca8…892c` 或 `git revert 173b18d` / EDA 权威与实施件指针）+ 历史链；0x21 段整段降级进新的 `---- (以下为历史, 逐字保留) ----`（逐字未动，仅标签 `本轮构建` → `上一版`） |
| `:2144` persist 注释头 | `本版 **0x21** 沿用` | **`本版 **0x22** 沿用`**（先读后判：该句 = 版本戳性质） |

**核验**：`git diff --stat board/wrapper_p4.v` = **只有 2 个 hunk**（`:2144` 一行 + `:4272` BID 块）、
**51 insertions / 3 deletions**；**未动** M1 块与 `:1320-1321` app 总线 tie-off（现读逐字确认：
`app_reg_addr = 8'h00` / `app_reg_wr = 1'b0`；`git diff | grep -c app_reg` = **0**）与 P9 的 AXIS 端口表
（diff 里 `u_mir_axis`/`s_axis_c2h`/`axis_c2h_stream` 三处命中**全在新增注释行内**）。改后工作树 sha256 =
**`416e0b3deb3d7e119c343e99fabf7319865c688e812d34c2e0b7c2cb370c606d`**（4778 行）。
脚本面：`board/build_p7b_ku5p.tcl` **一个字节未改**（被验源；diff 0 命中）。

---

## §3 C 完整构建

- **入口**：`MSYS_NO_PATHCONV=1 cmd /c 'D:\repo\XCKU5PMini\udp_hls_10g\board\run_build_p7b_ku5p.bat'`（§0-3）。
- ⚠️ **端点总数对照（同口径，可比）**：setup/hold 端点 **261,899 → 257,862**（0x21 → 0x22，Δ **−4,037**）、
  pulse-width 端点 **84,934 → 83,887**（Δ **−1,047**）—— 方向与"MM 从机三件被 AXIS 成形器取代"一致
  （⛔ 仍属跨网表差、**无拆刀臂 ⇒ 不归因**）。
- **读数**（`board/p7b_ku5p_stdout.txt` + `board/p7b_ku5p_timing.rpt`；全量副本 = `board_stdout.txt` / `board_rpt/`）：
  `P7B_WNS = 0.025` / `P7B_WHS = 0.010` / 三类失败端点 **0/0/0**（257,862 · 257,862 · 83,887）/
  `P7B_BIT_EXISTS = 1` / timing rpt `:160` 逐字 **`All user specified timing constraints are met.`** /
  timing rpt **`Slack (VIOLATED)` = 0 条**。`P7B_WPWS` 打印的是**逐组 slack 列表**（34 个数，最小 0.010），
  与上一轮同形；**Design Timing Summary 行：WPWS 0.000 / TPWS 0.000 / TPWS 失败端点 0**（⚠️ 0x21 归档 rpt 逐字同形 ⇒ 是同形态、非本轮异常）。
- **硬门扫描（12 键，应全 0 命中）**：`12-4739` · `Synth 8-11241` · `undeclared symbol` ·
  `VRFC 10-3091] actual bit length 1 differs from formal bit length` · `VRFC 10-2989` · `implicitly declared` ·
  `NSTD-1` · `UCIO-1` · `AVAL-326` · `Opt 31-155` · `Opt 31-67` · `Route 35-7` ⇒ **各 0**（未触发任何 `*-FAIL` 标记）。
- **一次收口**：`P7B_ROUND #1` 恰 1 次 / `BUILD_EXIT` 恰 1 行 / `P7B DONE` 恰 1 次 ⇒ **未重跑**（3 条
  `Exiting Vivado` = synth / impl / 父进程三段，时间戳见上表）。
- ⭐ **XDMA 断言组逐条读数**（本构建与以往最大的不同；全部在 stdout，非仅报告文件）：

  | 断言 | 读数 | 判定口径 |
  |---|---|---|
  | `P7B_XDMA_RC_BASE` | **0** ; MSG `<>` | 12 项基线 `-dict` 设置无异常 |
  | `P7B_XDMA_RC_INTF` | **0** ; MSG `<AXI_Stream>` | 单独一行设接口模式无异常（= CONF 的 B 臂写法） |
  | `P7B_XDMA_MSG_HIT` | **0 条** | `19-3461` / `19-3438` / `Restoring to previous valid configuration` / `17-39` 四模式文本扫描全 0 = **静默回滚未发生** |
  | `P7B_XDMA_RB_MISMATCH_N` | **0** | 13 项 CONFIG 逐项回读（含 `xdma_axi_intf_mm`）全中 |
  | `P7B_XDMA_GEN_BAD_N` | **0** | 生成产物 `synth/xdma_0.sv` 的 `CORE_GENERATION_INFO` 6 参数（DMA_ST=1 / DMA_MM=0 / XDMA_AXI_INTF_MM=0 / AXI_DATA_WIDTH=128 / USER_CLK_FREQ=2 / XDMA_AXILITE_MASTER=TRUE）全中 |
  | `P7B_XDMA_CFGDIFF_ST_N` | **1** = `{CONFIG.Component_Name}` | 对 ST 冻结参照**只差预期那 1 行** |
  | `P7B_XDMA_CFGDIFF_MM_N` | **2** = `{CONFIG.Component_Name CONFIG.xdma_axi_intf_mm}` | 对 MM 冻结参照**只差预期那 2 行**（= CONF §2.1 决定性判据） |
  | `P7B_XDMA_VERDICT` | **`OK (AXI_Stream / 回读 13/13 / 生成参数 6/6 / 参照 diff 只差预期行)`** | 断言块本身的判定（本报告只转述，不另下裁定） |

  ⚠️ **两条读数属"pre-existing 同形"、不是本刀引入**：`P7B_ROUND #1 MISMATCH_N = 5` → `#2 = 0`
  （pcs64 配置收敛循环；0x21 归档 stdout 逐字同形）· `P7B_CONVERGED_AT_ROUND = 2` / `P7B_IS_LOCKED_POSTGEN = 0`。
- **资源（placed）对照（⚠️ 必须同口径比 —— 本轮实测两份 rpt 会差）**：

  | 口径 | 0x21 | **0x22** | Δ |
  |---|---|---|---|
  | `board/p7b_ku5p_util.rpt`（board 口径；上轮 REPORT 引的就是它） | LUT 78,699 / FF 74,795 / BRAM 352 | **78,006 / 74,200 / 348** | **−693 / −595 / −4** |
  | `impl_1/wrapper_p4_utilization_placed.rpt`（impl 口径） | LUT 78,666 / FF 74,795 / BRAM 352 | **77,989 / 74,199 / 348** | **−677 / −596 / −4** |

  ⇒ ⭐ **新发现（登记）**：同一构建产出的两份 placed rpt **LUT 差 17（0x21）/ 17（0x22）**、FF 差 0/1
  —— 两份各自内部自洽，**跨代比较必须同源**（本轮已按"board 口径对 board 口径"给 Δ）。
  细分：LUT as Logic 70,691 / LUT as Memory 7,315；URAM 0 / DSP 4 / BUFGCE 4 / GTYE4 6。
  ⚠️ **跨网表差值、无拆刀臂 ⇒ 不归因**（#63/#64 族）。⚠️ 与本刀 synth 检查点（pre-place：LUT −616 /
  FF −1,201 / BRAM −4）**不同流程，不可互相推算**，只并列登记。
- **DP 域最差路径**：`u_tcp_tx/u_fifo_b/rptr_reg[1]/C → u_tcb/rcv_nxt_r_reg[1][17]/D`（lvl=16）=
  **全局最差**；DP top10 里 #3–#6 与它同源（`rptr_reg[1] → u_tcb/{snd_nxt,snd_una,rcv_nxt}_r_reg`），
  #2/#7–#10 = 另一族（`u_app_udp/u_txf/dout_reg → u_udp_tx/ip_csum_r`、`u_tcp_tx/rx_bank_reg_rep__0 →
  u_app/stg_reg[*]`）。DP 组内：setup 0/144,484 · hold 0/144,484 · pulse-width 0/51,272。
  ⛔ 与 0x21 的 DP 最差（同族、不同成员：`…rptr_reg[0]/C → …rcv_nxt_r_reg[0][22]/CE`）**不是同一对象、
  绝对值不同流程比不得大小** ⇒ 只并列登记（#66）。
- ⚠️ **同名陷阱复核（按上一轮登记的坑）**：DP top10 里宿 = `u_app/stg_reg[*]` 的两族 **是 `app_pattern`
  自己的 staging 寄存器**，与本刀的 `u_mir`/STG（`u_mir/stg_data_reg`）**同名不同物** ⇒ 判据 = 逐条查宿主层次
  （`u_mir` 在 DP top10 / top50 **0 命中**）。
- ⭐ **`u_mir_axis` 定向锥（后布线，本刀主角）**：`get_cells *u_mir_axis*` = **365 cells**，顶层单元
  `u_mir_axis` ref = **`axis_c2h_stream`**（新件确在网表里）；
  **FROM ≥ `+0.914`**（lvl 7；源 = `u_mir_axis/b_v_reg/C`，宿 = XDMA `…dma_axist/axist_c2h[0].dma_axist_slv/
  axi_rdy_100_reg/D`）/ **TO ≥ `+0.648`**（lvl 3；源 = `u_mir/u_fifo/rbin_r_reg[0]/C`，宿 =
  `u_mir_axis/s1_data_reg[34]/D`）。
  ⚠️ 与实现轮 synth 检查点（pre-place **FROM ≥+1.531 / TO ≥+2.120**）**不同流程 ⇒ 不比大小**；
  方向一致的两条：① 两点都远离同域 WNS；② **`u_mir` 全族在 global top5 / DP top10 / DP top50 = 0 命中**。
  另：`mir_c2h_*` 网（134 nets / 287 pins）from_worst = **+0.914**（同上）；`to` = NOPATH。
- ⭐ **"MM 从机确实被移走了"的直接网表证据**：`*u_mir_ring*` / `*u_mir_c2h*` / `*u_mir_h2c*`
  = **NOCELL（0 命中）** —— 三个 P8 期 B 的 MM 从机（`mir_dma_ring`/`aximm_c2h_win`/`aximm_h2c_discard`）
  已不在网表里（文件仍在树、单元门仍在，只是不再例化）。
  ⛔ **同时暴露一条查询面缺陷（登记）**：族 `*mir_axi*` 现在**同时命中 `u_mir_axis`**（子串包含：
  `u_mir_axis` 含 `mir_axi`）⇒ `m1_axi_cell ncell=365`、`mir_axi_nets=469` **是 `u_mir_axis` 的网/cell、
  不是旧 MM 网** ⇒ 该族已**失去判别力**（#90"网名 ≠ RTL 信号"同族）⇒ 本轮用
  `u_mir_ring/c2h/h2c = NOCELL` + wrapper 端口表 75→50 作证据。
- **其它族挤动复核（只登记，不做归因）**：`stg_cnt` from +1.442 / to +1.693 · `stg_data` from +2.578 /
  **to +0.524**（= M1 族在 DP 组内最紧）/ `acc_cnt_r` from +1.239 / to +2.564 ·
  `ps_stage` to +0.228 · `ps_timer` to +0.396 · `whi_r` to **+0.316**（全族最紧，`u_clkgen/rel_sr_reg[3]/C →
  …/CLR` **异步复位族**、lvl=1，**非 DP setup ⇒ 与 DP WNS 不同对象**）· `pend_wnd` to +0.414 ·
  `ackok` to +0.568 · `ack_adv` to +0.529 · `dup_l_reg` to +0.558。
- **M1 面（含 `u_mir_axis`）**：`m1_all` = 2,164 cells；**DP 组内** from **+1.239** / to **+0.524**；
  **全钟面**最紧 = **+0.499**（`u_mir/u_fifo/rbin_r_reg[4]_rep/C → u_pcie_regs/s_axil_rdata_reg[29]/D`，
  = 镜像窗经 user BAR 的读通路，属 **pcie 域**）⇒ 与 DP WNS 差值 0.474 ns / 比值 **≈20.0×**。
  定向查询 RTL 面：`QUERY_EXIT = 0`，`N_DONE` 结清。
- **`BUILD_ID_V` 回读**：源码面 **`0x22`** ✅；**位流面 = 未做**（见 §7-1）。

---

## §4 D 常驻矩阵 17/17（不是 filter 子集）

- **入口**：`bash sim/p4sim/run_matrix_p4dfix.sh`（自定位 `[P4GUARD OK] root=… manifests=6`）；
  **`MATRIX_RC = 0`**；日志 = `sim/p4sim/matrix_p4dfix.log`（副本 `matrix_p4dfix.log` /
  `matrix_stdout_raw.txt`（gbk 原样）/ `matrix_stdout_utf8.txt`）。
- **逐门清单（17/17 全 `EXIT=0`）**：chain · burst200 · trunc50 · trunc100 · halfdrop · txdrop50 · gate4096 ·
  dupstorm · pcackoob · vlanchain · vlanburst · stallgate · unit_retx · unit_fifo · unit_vlan · unit_uart · p5_wrapper。
  `gate filter: (none -- all 17)` / **`gates run : 17 / 17`** / **`gates failed: 0`** / `MATRIX DONE 2026/10/11 23:12:21`。
- **跑动期间零漂移**：`DIGEST_COMPILE`(212) / `DIGEST_ALL`(257) BEFORE = AFTER 逐位相同；
  `GIT_HEAD` BEFORE = AFTER = **`447f76f`**。`VERDICT: FROZEN -- all 257 hashed files byte-identical across the run`。
  ⚠️ 日志自带 NOTE：**存盘里的 `DIGEST_ALL` 是旧方案（含 size/mtime）**，而 VERDICT 按 content-v1 判
  （"verdict is content identity only"）—— 如实登记，不当作缺陷。
- **静默门复核**：`unit_retx` = **`ALL 7 GROUPS PASS`**；`unit_fifo` = **`PASS_ALL frame_fifo unit:
  writes A=568139 B=595715 C=616302 pops A=567224 B=591216 C=611802 cycles=750700`**（C=616302 与既存基线
  **逐字相同**）；`unit_uart` = `ALL_OK`；`p5_wrapper` 尾 = `P5 WRAPPER OK (wrapper APP_MODE app-TX 通路端到端逐字节正确)`
  （wrapper GMII 3 帧 / 图案 3 帧 4380 B）。
- ⭐ **指纹绑定核对（派单点名）**：指纹件 `sim/p4sim/P4_MATRIX_FINGERPRINT_20261011_224513_{before,after}.txt`
  （已归档本目录）里 **257 件逐件 sha256 == 盘上现读**（本轮逐件复核，0 MISMATCH）
  ⇒ **矩阵 FROZEN 绑定【工作树】成立**。**逐面口径（如实分列）**：
  - **27 件 `rtl/`（本轮 RTL 提交面）：`git diff HEAD -- rtl/` = 0 件 ⇒ 指纹里这 27 件 == HEAD 逐字**
    ⇒ "本轮 RTL 已提交 ⇒ 指纹绑 HEAD"**在这个面上成立**；
  - **`board/wrapper_p4.v`：指纹 = `416e0b3d…`（工作树）≠ HEAD** —— 差异**恰好 = 本轮 B 项 2 个 hunk**
    （BID 0x21→0x22 + 注释；指纹件自己那行也写着 `M M board/wrapper_p4.v`）⇒ **这是派单要求的 B 项，不是"我还改了别的"**；
  - **其余我改的 15 件（14 读侧 + 脚本）根本不在 257 件指纹集内**（集 = 176 hls + 42 sim + 27 rtl + 6 tb + 3 tools + 3 board）
    ⇒ 指纹**对它们无覆盖**（读侧同步的正确性判据在 §1 的 A/B/C/D 四条断言里，不在矩阵指纹里）；
  - 指纹集内**其它**相对 HEAD 有改动的件 = 构建/矩阵自己的产物（`board/p7b_ku5p_{stdout,timing,util,drc,clkinteract}.rpt` ·
    `sim/p4sim/matrix_p4dfix.log`）—— 每轮同形（跑动即重写）。
- ⛔ **覆盖声明（空证据面，照实报）**：6 个 manifest 逐个现核 —— **本刀改/加的三件 RTL
  （`rtl/axis_c2h_stream.v` 新件 / `board/wrapper_p4.v` / `_proj_pcie/rtl/axi_regs.v`）在 6 个 manifest 里
  命中数：新件 0 · `axi_regs.v` 0 · `wrapper_p4.v` 仅 `p5wrapper_src.f`**，而该 manifest 头自述
  `-d APP_MODE ONLY. No DP_156MHZ / PCIE_OBS / P7B_10G …`；且 `board/wrapper_p4.v` 里
  `axis_c2h_stream u_mir_axis` 的例化**被 ``ifdef APP_MODE`` ∧ ``ifdef DP_156MHZ`` 双包**
  （现读 `:3842` 上下文）⇒ **该门里本刀根本没被 elaborate**（`APP_MODE ONLY` 不含 `DP_156MHZ`）。
  ⇒ **17/17 绿对本刀是空证据**；本刀的门证据在**实现轮**的
  `sim/p9_axis_stream/`（新件单元门 `PASS_ALL` + **7 突变臂全捕获**，红灯面互不相同）与
  `sim/p6e_pcie/`（p6e 真 wrapper 全链 `PASS_ALL` / 0 FAIL），另有独立对抗审查
  （`p9_axis_impl_20261011/REVIEW.md`，`447f76f` 入库）。
- **矩阵件归档**：before/after 指纹 + `matrix_p4dfix.log` + `matrix_stdout_raw.txt`（gbk）+ `matrix_stdout_utf8.txt`（全在本目录）。

---

## §5 E 归档（本目录，全部在本轮之内落盘 —— #54）

`wrapper_p4.bit`（15,431,261 B）· `wrapper_p4_routed.dcp`（62,829,797 B）· `board_rpt/`（13 件 = timing/util/drc/
clk-util/control-sets/power/route-status 的 routed+placed rpt + `runme_impl_1.log` + synth util + board 四份 rpt +
`p7b_ku5p_xdma_cfg_post_gen.txt`）· `board_stdout.txt`（构建全日志）· `build_console.txt` · 定向查询
`q_0x22.tcl` + `run_q.bat` + `query_out/`（`dp_top10.rpt` / `dp_top50.rpt` / `global_top5.rpt`）+ `q_stdout.txt` +
`q_bat_console.txt` · 矩阵件（before/after 指纹 + log + stdout ×2 编码）· 读侧件（dry-run ×2 / rehearse / apply /
assert / face / negctl×4 / negctl_post×4 / neg_rehearse×2 + `TARGET_SHA_BEFORE_BID22.txt` /
`POSTAPPLY_SHA_BID22.txt`）· 阶段 ⑦ 生成器与拼装器（`gen_edits22.py` / `splice_phase7.py` / `EDITS_22_BLOCK.txt`）·
`PROGRESS.txt` · **`SHA256SUMS.txt`**（本目录逐件）。
另：构建脚本自带归档 `_proj_10g/notes/p7b_build_archive/20261011_215445/`（**19 件 = 上一版 0x21 的 impl 产物**；
其 `wrapper_p4.bit` sha256 = `fbb6fca8…4892c` 已核 = 0x21 位流 ⇒ 归档的是**上一版**，符合脚本设计）。
⛔ 未烧板 / 未写 QSPI / 未碰 `rtl/**`、`tb/**`、`board/build_p7b_ku5p.tcl`。

---

## §6 口径声明（哪些变了 / 哪些逐字不变）

**变了**：① 14 个读侧文件（BID 0x21 → 0x22 + 注释代际）；② `board/wrapper_p4.v`（B 项：1 值 + 2 段注释）；
③ `apply_readside_bid1c.py`（+阶段⑦/+5 ALLOW/+文档，**+115/−2 行**）；④ 构建产物
`board/p7b_ku5p_{stdout.txt,timing,util,drc,clkinteract}.rpt` 与 `sim/p4sim/matrix_p4dfix.log`（跑动即重写，上一轮同形）；
⑤ 新文件全在 `_proj_10g/notes/p9_build_0x22/` 与 `_proj_10g/notes/p7b_build_archive/20261011_215445/`。

**逐字不变**：几何（71 字 / `0x14C` / 各读侧表 71 项 / 假板子 11 条地址）· M1 块与 `:1320-1321` tie-off ·
P9 的 AXIS 端口表 · `rtl/`（本轮**一个字节未写**）· `board/build_p7b_ku5p.tcl`（一个字节未写）·
`tb/**`（一个字节未写）· 两个 TB 的 UNIMPL/几何期望 · 所有"历史/逐字保留"注释行 · `unit_fifo` 的 C=616302 读数 ·
矩阵 `DIGEST_COMPILE`/`DIGEST_ALL`/`GIT_HEAD`。

**不许当已答**：本报告**不下时序裁定**（`+0.025` / `0/0/0` 是读数，不是"解决"；跨网表差值不归因）；
`WNS +0.025` = 周期 6.400 的 **0.39%** ⇒ **余量更薄了，后续任何改动都先落 `u_tcp_tx/u_fifo_b/rptr_reg[1] →
u_tcb/{rcv_nxt,snd_nxt,snd_una}_r_reg` 这条族**。
⚠️ **XDMA `VERDICT = OK` 的边界**：它只证明**综合期配置/回读/生成产物**三层一致（静默回滚未发生）；
**AXIS 通路的功能正确性不在它的覆盖里**（那要烧板 + 驱动实测，见 §7）。

---

## §7 未定项（没跑 / 没覆盖 / 只能写"未观测到"）

1. **位流面身份回读未做**：板上 `0x04` 门（真正的回读）**需烧录**，本轮不烧 ⇒ 只能写"源码面 = `0x22`；
   板面 = 未测"。
2. **板级完全未验**：`0x22` 位流**没有任何板级读数**（不烧板 = 派单边界）。下一轮起手式（供登记）=
   烧 0x22 + 身份门（`0x04`）→ **AXIS C2H 通路的端到端演示**（`p7b_mir_dump --stream`，工具侧已在
   `dd6fe3d`/`447f76f` 落地：平铺 read / 128 MB PC 缓冲 / 闭合式记账 / `level==0` 见证），
   并做 **AXIS 臂 vs 烧回 0x21 的 MM 臂对照**（0x21 位流仍在盘，可作负对照臂）。
3. ⛔ **实现轮 §8 的四条未定项仍在**（本构建**不改变**它们的身份，逐条照抄登记）：① **字节序的宿主侧落点**
   （XDMA 把 `tdata` 按小端写内存 —— **未 EDA 证**）；② **"永不 tlast"是否被引擎长期接受**（CONF 登记为需板级验证）；
   ③ `clr` 中途的残拍边界（≤16 B 会跟在 post-clr 窗口头部）；④ 停流 flush 覆盖不到"暂存全空"的情形。
4. **矩阵不覆盖本刀 RTL**（§4 覆盖声明）⇒ 17/17 绿**不能**当作本刀的回归证据（本刀的门证据 = 实现轮的单元门
   + p6e 全链 + 审查件）。
5. **时序余量**：`WNS +0.025`（0.39%）且 **DP 域 = 全局最差** ⇒ 加逻辑先看
   `u_tcp_tx/u_fifo_b/rptr_reg[1] → u_tcb/*_r_reg`（0.025–0.098，DP top10 里 **5 条**同源：`#1/#3/#4/#5/#6`）与
   `u_tcp_tx/rx_bank_reg_rep__0 → u_app/stg_reg[*]`（0.098，两条族）**两条旧族**；
   ⚠️ **本刀新锥不在其中**（`u_mir_axis` 两点 +0.914/+0.648，且 `u_mir` 在 DP top10/50 = 0 命中）。
6. **资源/时序跨网表差（LUT −693 / FF −595 / BRAM −4 / DP WNS 0.044 → 0.025）无拆刀臂 ⇒ 不归因**；
   synth(+0x…/−616/−1,201/−4) 与后布线(−693/−595/−4) 是两个流程，不可互推。
   ⚠️ **另加一条本轮新发现**：同一构建的**两份 placed rpt 会差**（board 口径 vs impl 口径，LUT 差 17/17）
   ⇒ **跨代比较必须同源**（已在 §3 表里分列）。
7. **`run_tb_p6e_pcie_counters` / `run_tb_p6e_pcie_wrapper`（TB 期望已 = `0x22`）本轮未跑**：
   两者不在 17 门矩阵内 ⇒ 只能写"常量已同步、**未运行验证**"（⚠️ 与上一轮同形：`tb_p6e_pcie_wrapper.v`
   还叠着"P9 提交改过正文"这一层 ⇒ 它的 xsim 复跑要等实现轮的桩/TB 一起跑）。
8. **`q_0x22.tcl` 的两条查询面缺陷（登记，非本刀缺陷）**：① 族 `*mir_axi*` 现在**同时命中 `u_mir_axis`**
   （子串包含）⇒ `m1_axi_cell ncell=365` / `mir_axi_nets=469` **不是旧 MM 网**，该族已失去判别力（#90 族）；
   ② `axis_all {*axis_c2h*}` = NOCELL（例化名是 `u_mir_axis`，模块名才是 `axis_c2h_stream`）——
   下轮改查询面时一并订正。
9. **`negctl` 的 docstring 与实现 RC 语义不一致**（文档写"0=有牙"，代码 `return 1 if teeth else 0`）——
   本轮按代码读（RC=1 = 有牙）；登记为工具文档债，**未改**（改它超出本轮可写面）。
10. **HEAD 在轮内位移**（`eb4007b` → `04726a0` → `447f76f`，其中 `447f76f` 落在构建窗口内）
    —— 逐条核过**不含构建输入**（§0-4），但**下一轮引用"本轮构建时的树"必须用 `447f76f`**，
    不要用开工时的 `eb4007b`。
