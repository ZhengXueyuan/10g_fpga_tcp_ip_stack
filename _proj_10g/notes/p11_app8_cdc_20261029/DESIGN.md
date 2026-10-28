# P11 APP8 时序攻坚：8×app 独立时钟域 + CDC（实施级设计件 v3）

- 日期：2026-10-29（v1/v2 同日；**v3 = 独立复审回灌**）
- 状态：**设计件 v3（未实施、未构建、未上板）**。v3 已按两级审查逐条改字：
  ① `%TEMP%/bridge/xr12/REVIEW_APP8_CDC.md`（高 2 / 中 4 / 低 6）；
  ② **独立复审 F1–F17（阻断 1 / 高 3 / 中 7 / 低 6）**（v2 复审未通过；见 `REVIEW.md` §2）。
  **v3 复审通过后才进实施**（设计件自身 DoD）。
- 上游：`../p11_app8_contract_20261027/NEXT_TIMING_STUDY.md`（研究件，方案 A）
- 触发：0x34 构建轮 = **1 次模块解析门失败（#1，无档案）+ 4 次时序门构建（#2–#5，均有 `FAILURE.md` 档案）**；
  最好 = `Congestion_SpreadLogic_high` **−0.205 / 5,162**；策略/布局搜索已关闭
- 目标：把 8×app（15,328 LUT / 5,956 FF）移出 `dp_clk` 的时序与拥塞竞争，使 DP 的 WNS 回到
  0x33 量级（+0.008），从而让 OCC A/B（本设计的 0x36/0x37）有可烧的位流
- 非目标：不改 8×12KB 合同、不改 `app_pattern`、不改 `win_pool_mgr`、不改 OCC 语义、
  不修 F6/F14/F18（见 `DESIGN_OCC_V6.md` §6.9）
- ⭐ **与上游方案 A 的偏离（v2 显式声明，L-3）**：① TX/RX FIFO 深 **512→256**（一帧 183 字已够）；
  ② 事件 FIFO 深 **8→16**（H-2 复位窗重放需要）；③ **不含 `app_multi8` pblock** ——
  理由 = build_fail2 实测 pblock 反噬（−0.644 / 13,282 vs −0.337 / 6,642）+ CDC 后 DP↔app
  已无时序关系，pblock 不再是收益前提；若 CDC 后 DP 仍差 0.0x ns，再把 pblock 作为
  **独立输入**评估（不是 v3 的一部分）。
- ⭐ **OCC A/B 取代声明（F16）**：原计划 0x34（OCC=0）/0x35（OCC=1）**从未产出可烧位流**
  （#2–#5 全部 TIMING_FAIL）⇒ **本设计把 A/B 改为 0x36/0x37**；`build_p7b_ku5p.tcl:88`
  的"1 = 0x35 修复臂"注释在实施时同步订正。

---

## 0. 一句话方案

新增 **`clk_app`（第二 MMCM，156.25 MHz，输入 = 现有 `clk_in_100`）**，把
`app_multi8`（含 mux/demux/close arb）整体搬进该域；DP↔app 之间只保留
**2 条 77-bit AXIS 异步 FIFO + 事件/close 小 FIFO + `app_tx_ready` 逐位 2FF +
统计快照握手**；`clk_app` 与 `dp_clk` 用 **`set_false_path` 双向**摘出时序（不改现有
`set_clock_groups`）；功能复位沿用“异步置位/同步释放”，CDC FIFO 两侧复位**都用板级
`reset_n`**（P6B 硬规则）。

---

## 1. 为什么不是在 `dp_clk` 里继续挤

| 输入（同一 RTL） | WNS | setup 端点 | 最差族 |
|---|---|---|---|
| ExtraTimingOpt | −0.337 | 6,642 | `u_tcp_tx2/u_fifo_b → u_tcb2/rcv_nxt CE` |
| + pblock（左下） | −0.644 | 13,282 | 同族（pblock 反噬） |
| Congestion_SpreadLogic_high | −0.205 | 5,162 | `u_tcp_tx/bank_rdy → app/tcb CE` |
| Performance_NetDelay_high | −0.886 | 14,630 | `u_tcp_tx/u_fifo_a → u_tcb/snd_nxt CE` |

- 0x33（2 app，同族 **+0.008**）→ 0x34（9 app）的边际 ≈ **0.345 ns / 7 app**。
- #4 的最差 10 条里，**同一根 `u_tcp_tx/bank_rdy_reg[1]_replica` 同时打 TCB 写使能与 app 的
  TX CE** —— 这正是 CDC 能**整族删除**的路径（跨域后 DP↔app 不再有时序关系）。
- 布局实验（pblock #3 / NetDelay #5）已证伪“换个摆法就能过”；剩下的只有**域隔离**或**降面积**。
- **档案口径（L-2）**：`build_fail1/` = #2（Extra）、`build_fail2/` = #3（pblock）、
  `build_fail3/` = #4（Spread）、`build_fail4/` = #5（NetDelay）；**#1 是模块解析门失败**
  （`app_close_arb8=0` 合法常数折叠被旧门误判；无位流、无时序报告、未归档），不计入上表。

---

## 2. 时钟方案（关键决策）

### 2.1 选定：第二 MMCM，输入 = 现有 `clk_in_100`

- 新模块 `rtl/app_clk_gen.v`：输入 `clk_in_100`（`clk_gen_p6b` 的 BUFG 输出，已有端口）、
  `rst_ext`；输出 `clk_app`（156.25 MHz）、`locked_app`、`rst_app`（**高有效**，异步置位/4 拍
  同步释放）。**包装层取反为 `app_rst_n`**（低有效，§4.1/§4.3 用后者；F13 统一极性命名）。
- 参数与 `clk_gen_p6b` 完全一致：`CLKFBOUT_MULT_F=12.500` / `DIVCLK_DIVIDE=1` /
  `CLKOUT0_DIVIDE_F=8.000` / `CLKIN1_PERIOD=10.000`。
- 为什么不是“同一 MMCM 的 CLKOUT1”：同源锁相、相位确定 ⇒ 不能诚实地当异步域。
- 为什么不是 `pcie_axi_aclk`（≈250 MHz）：数据面不应依赖 PCIe 链路/时钟；且 app 内部
  路径在 250 MHz 下要重新收时序（收益不确定）。
- 为什么不是直接用 `clk_in_100`（100 MHz）：mux 是 8 B/cycle ⇒ 聚合上限
  **6.4 Gbps**，丢掉 8 连接 10G 的产品目标。
- 为什么**不改 `clk_gen_p6b`**（2026-10-29 现核）：它是共享件 —— 构建主件 **1 处**
  （`board/wrapper_p4.v:990`）+ 专用单元门 **4 例**（`tb/tb_clk_gen_p6b.v:109/120/132/144`）
  + probe 工程 4 件（`board/ku5p_probe/clkgen_p6b/`）+ `sim/aliasgate/_selftest` 与
  `sim/f3_resync` 夹具副本；`_proj_10g/notes/` 下是历史副本（不编译）。
  ⚠️ **`sim/p6e_pcie/tb_p6e_pcie_counters.v` 与 `sim/f3_resync/tb_f3_resync.v` 只在注释里
  提到它、不是例化**（grep 命中 ≠ 例化）。本设计要求该文件**逐字节不变**；新模块只吃它已有的
  `clk_in_100` 输出 ⇒ **既有模块零改动、零回归**。

### 2.2 约束：只加 `set_false_path`，不动现有 `set_clock_groups`

新增 `board/ku5p_p7b_app8_cdc.xdc`（**只在该构建加入**，`used_in_synthesis false`）：

```tcl
# clk_app ↔ dp_clk：唯一跨域连接全部是 CDC（FIFO/2FF/handshake）⇒ 双向 false_path。
# ⚠️ 不写 set_clock_groups：clk_app 是 sys_clk_100 的 generated clock，若用
#    -include_generated_clocks 重组，会有“同一 clock 进两个 group”的风险。
set app_clk_c [get_clocks -of_objects [get_pins u_appclkgen/u_bufg_out/O]]
set dp_clk_c  [get_clocks -of_objects [get_pins u_clkgen/u_bufg_out/O]]
set_false_path -from $app_clk_c -to $dp_clk_c
set_false_path -from $dp_clk_c  -to $app_clk_c
```

- 仍保留 `ku5p_p7b_cdc.xdc` 的四域 async group（clk_app 因是 sys_clk_100 的派生，
  自动留在第一组 ⇒ 对 pcie/gt 仍是 async）。
- **门**：`P11_APP8_CDC_GATE`（见 §7）必须验证 `report_clock_interaction` 里
  dp_clk↔clk_app 不再是 “Timed (unsafe)”，且无 `12-4739`。
- ⚠️ `set_false_path` 会摘掉**所有**该对时钟的路径 ⇒ 必须先做 **§3** 的边界普查，
  任何“没有同步器的跨域”都必须在实施前消灭。

---

## 3. 边界清单（CDC 的全部内容）

`app_multi8` 的对外接口（`rtl/app_multi8.v:16-79`）逐条处置：

| 信号 | 方向 | 位宽 | CDC 方案 | 说明 |
|---|---|---|---|---|
| `m_tdata/tkeep/tvalid/tready/tlast/tid` | app→DP | 77 | **`fifo_async` WIDTH=77 DEPTH=256 FWFT=1** | 一帧最大 1460 B = 183 字 < 256 ⇒ 整帧可入 |
| `rx_tdata/tkeep/tvalid/tready/tlast/tid` | DP→app | 77 | 同上 | DP 写侧受 `rx_stall` 门控（见 §4.4） |
| `ev_up/ev_down/ev_slot` | DP→app | 6 | **`fifo_async` WIDTH=6 DEPTH=16 FWFT=1** | 写 `(ev_up\|\|ev_down)`；读侧 `ev_up=!empty && dout_up`，每拍弹一个 |
| `close_req/close_id` | app→DP | 5 | **`fifo_async` WIDTH=5 DEPTH=16 FWFT=1** | 深度 16 > 最大 8 连接；溢出用 `drop_cl` 记 W97[3]（F1） |
| `app_tx_ready[15:0]` | DP→app | 16 | **逐位 2FF**（`ASYNC_REG`） | 电平；每连接独立，无跨位语义 |
| 统计 10×32 + `stat_close_pend_max[3:0]` + `led[3:0]` | app→DP | — | **hold + toggle 握手**（见 §4.5） | 相干快照；不是逐位同步；`close_pend_max` → W97[19:16]（L-4） |
| `i_bad_frame[127:0]` | — | — | 常量 `0`（板级） | 不需要 CDC |
| **空接端口 8 个** | — | — | 经 CDC 包装**保持空接** | `active` / `act_id` / `done` / `dbg_lfsr` / `stat_arb_frames` / `stat_rx_orphan_frames` / `stat_rx_orphan_bytes` / `dbg_inst_mismatch`（`stat_close_pend_max` 例外：接 W97，L-4） |

**统计列表**（与快照/状态行现有消费点一致，共 10×32 + 4 位）：`stat_tx_bytes` ·
`stat_tx_frames` · `stat_rx_bytes` · `stat_mismatch` · `stat_frmwait_cyc` ·
`stat_bp_cyc` · `stat_up_ev` · `stat_sw_req` · `stat_sw_apply` · `stat_up_pend` ·
`stat_close_pend_max[3:0]`。

---

## 4. 实施结构

### 4.1 新模块 `rtl/app_multi8_cdc.v`

对外端口 = **DP 侧**（名字与现 `u_app` 完全一致，wrapper 只换例化名）：

```
dp_clk, dp_rst_n, reset_n,            // reset_n = 板级复位（CDC FIFO 两侧都用它）
app_clk, app_rst_n,                   // 来自 app_clk_gen
ev_up, ev_down, ev_slot[3:0],
m_tdata[63:0], m_tkeep[7:0], m_tvalid, m_tready, m_tlast, m_tid[3:0],
app_tx_ready[15:0],
close_req, close_id[3:0],
rx_tdata[63:0], rx_tkeep[7:0], rx_tvalid, rx_tready, rx_tlast, rx_tid[3:0],
rx_stall,                             // 0x08 bit2（DP 域，2FF 已在 wrapper）
stat_*（10×32 + close_pend_max[3:0]）, led[3:0],
cdc_status[31:0]                      // → W97（见 §4.6）
```

内部：

```
u_core : app_multi8 (.clk(app_clk), .rst_n(app_rst_n), ...)
u_tx  : fifo_async #(WIDTH=77, DEPTH=256, FWFT=1)  // wr=app_clk, rd=dp_clk
u_rx  : fifo_async #(WIDTH=77, DEPTH=256, FWFT=1)  // wr=dp_clk, rd=app_clk
u_ev  : fifo_async #(WIDTH=6,  DEPTH=16,  FWFT=1)  // wr=dp_clk, rd=app_clk
u_cl  : fifo_async #(WIDTH=5,  DEPTH=16,  FWFT=1)  // wr=app_clk, rd=dp_clk
```

**TX 映射**：
```
wr_en = m_tvalid && !full;  din = {m_tkeep, m_tlast, m_tdata, m_tid}  // 77 bit
m_tready = !full
// 无 drop 计数器：wr_en 与握手接受式（valid && !full）**同式** ⇒ 结构上不丢字；
// `src && full` 对遵守反压的源只是 stall 计数，不是丢字（v3 收紧，见下）。
// DP 侧：
s_axis_tvalid = !empty;  {tkeep,tlast,tdata,tid} = dout;
rd_en = s_axis_tready && dp_rst_n;   // F8：DP 功能复位期间不得弹字
```
**RX 映射**：
```
wr_en = eco2_tvalid && !full && !rx_stall;  din = {eco2_tkeep, eco2_tlast, eco2_tdata, eco2_tid}
eco2_tready = !full && !rx_stall
// 同样不设 drop 计数器：wr_en 与握手接受式同式；`src && full` 是 stall 计数，不是丢字。
// app 侧：
app_rx_tvalid = !empty;  tready → rd_en
```
⚠️ **F1（阻断项修法，v3 再收紧）**：`fifo_async` 的 `ovf_pulse = wr_en && full` 在本设计里
**结构性恒 0**（`wr_en` 已带 `!full`）⇒ **不得把 `ovf_pulse` 当见证**。
- **事件 / close**（无 ready 的源）：`drop_ev` / `drop_cl` = `src_valid && full` 是**真实丢失**，
  在各自写域置粘滞（W97[2]/[3]）。
- **TX / RX**（有反压）：`src_valid && full` **不是丢字**（源会保持字等 `full` 落下）⇒
  **不设 drop 计数器**；不丢字由"`wr_en` 与握手接受式同式"保证，用**静态门**核对两条
  表达式，不用计数器（否则是 stall 计数/空判据）。
**事件映射（v2：H-2 复位窗语义 = 重放）**：
```
wr_en = (ev_up || ev_down) && !full;  din = {ev_up, ev_down, ev_slot}
drop_ev = (ev_up || ev_down) && full;     // DP 域（写侧）→ W97[2]：事件丢失
// app 侧（FWFT）：
rd_en = !empty && app_rst_n_q;            // app_rst_n_q = app_rst_n 延迟 1 个 app 拍
ev_up_app = !empty && dout[5]; ev_down_app = !empty && dout[4]; ev_slot_app = dout[3:0]
```
- **复位窗语义 = ① 重放**（H-2 要求显式二选一）：
  - app 功能复位期间 `rd_en=0` ⇒ 事件留在 FIFO，不在复位期被空转弹掉；
  - 复位释放后按原顺序重放；`app_rst_n_q` 的 1 拍延迟保证"释放沿那一拍"不消费事件；
  - **边界**：重放只保证"复位窗内及之后"的事件不丢、顺序不变。**复位前已 ESTAB 的连接状态
    无法由事件流恢复**（app 状态已清零）⇒ 产品语义 = **该口全部连接重连**；板级该轮按
    W97[6] 作废（§7）。
  - **满的处置**：事件写侧无反压（`app_ctrl` 的事件输出没有 ready）⇒ 复位窗内 >16 事件会满；
    **`drop_ev = src_valid && full`** 置 W97[2]（故障见证，F1 修法）。一旦 [2] 置位 ⇒
    事件流不完整 ⇒ 同样"全部重连"（= 重烧后整机复位，F3），该臂作废。
  - **为什么不选 ② 丢弃（v1 现状）**：丢弃 = 静默脱同步、无见证、P9 互核恒等式断裂。
- ⚠️ 事件是**脉冲**：读侧每拍弹一个，脉冲宽度 = 1 个 app 拍（与今天 DP 拍的单拍脉冲等价；
  app_pattern 的事件逻辑是边沿/条件采样，已在现有 TB 覆盖）。
- ⚠️ 同拍 `ev_up && ev_down` 是**结构性不可达**（`app_ctrl` 的 `o_ev_up/o_ev_down` 是
  if/else 互斥寄存器输出，M-3）⇒ 单字 `{up,down,slot}` 格式仍保留，但 TB 不写该不可达判据。
- 配套 TB：**C10**（复位窗 N≤16 事件 ⇒ 释放后全部按序重放；N=17 ⇒ W97[2] 置位）。

**close 映射**：
```
wr_en = close_req && !full;  din = {close_req, close_id}
drop_cl = close_req && full;                 // app 域 → W97[3]：close 丢失
// DP 侧：close_req_dp = !empty && dout[4]; close_id_dp = dout[3:0];
//         rd_en = !empty && dp_rst_n;         // F8：DP 复位期间不得弹掉 close
```
⚠️ 若 `full`，`close_req` 会丢 ⇒ 用 `drop_cl` 记 `cdc_status[3]`；深度 16 > 8 连接，
正常不可达满（app 在 reset 时另说，见 §6）。

### 4.2 复位策略（必须按 P6B 硬规则）

- **CDC FIFO 的 `wr_rst_n` / `rd_rst_n` 全部接板级 `reset_n`**（同一代）——
  与 `u_rxcdc/u_txcdc` 完全一致；`mmcm_locked` **绝不进 FIFO 复位**。
- `app_multi8` 的功能复位 = `app_rst_n`（`~locked_app | rst_ext` 的 4 拍同步释放）。
- `dp` 侧功能复位 = 现有 `dp_rst_n`。
- ⚠️ **残余（登记，不修；v3 按独立复审 F3/F8 改写）**：`locked_app` 单独失锁 ⇒ app 功能复位
  而 FIFO 不复位（与 F-3 的 dp 失锁同类）：
  1. **RX**：FIFO 里的在飞字会在恢复后交给已复位的 app ⇒ 图案相位断一次；产品行为 =
     断线重连（M-2 的跨会话残留是它的"正常换流"版本，见 §8.1）。
  2. **TX 半帧（Q8/F3，结构性可达）**：若 app 在一帧中途复位，TX FIFO 里可能留下
     **无 `tlast` 的半帧**；消费者是 **`tcp_tx_frame` 的 `S_RECV`**
     （`rtl/tcp_tx_frame.v:1466-1477`，只有 `tlast` 或 `len_over` 两个出口），**无帧超时/abort**。
     后果：① wedge（等不到 tlast）；② 若复位后重放/新事件把**另一条连接**的帧接上，
     `f_conn/f_seq` 已在 `recv_first` 拍锁旧连接 ⇒ 合成为**旧 tid/旧 seq + 新载荷**的帧
     （长度 ≤1500 时 `len_over` 拦不住）⇒ **跨连接错帧**。触发条件 = app 复位时任一
     app_pattern 有在飞帧。**v3 处置 = 登记残余 + 硬规则**（观测到 [6] ⇒ 停流、作废、重烧）；
     有界恢复（`app_tx_abort` / `S_RECV` 按 `rst_req` 中止）**另开设计，不在 v3**。
  3. **DP 功能复位（F8，对称残余）**：`dp_rst_n` 期间 app 仍可写 TX FIFO，而 DP 读侧若不受
     门控会把字弹进复位中的 pipe / 把 close 弹掉 ⇒ 丢帧、漏关。**v3 修法 = DP 侧读使能
     加 `dp_rst_n` 门控**（§4.1 的 `rd_en=...&&dp_rst_n`），并把 `dp_rst_seen`（W97[20]，
     armed）列为复位见证；**硬规则 = [20]=1 ⇒ 该轮作废、重烧重跑**。
  4. 板级读数必须按"该事件未发生"口径写（W97 的 `app_rst_seen` 粘滞位提供见证）。

### 4.3 `app_tx_ready` 逐位 2FF

```
// DP 侧先打一拍（F6）：app_ctrl 的 app_tx_ready 是组合减法+比较，直接跨域会带毛刺，
// 且 set_false_path 后它将完全不被时序分析；寄存后 DP 域仍有可分析的端点。
always @(posedge dp_clk or negedge dp_rst_n)
  if (!dp_rst_n) app_tx_ready_dp_r <= 16'd0;
  else           app_tx_ready_dp_r <= app_tx_ready;

// app 侧逐位 2FF（16 位 = 16 条独立链）：
reg [31:0] ready_sr;   // 2×16（F12：必须 32 位，16 位写法会截掉 src[15]）
always @(posedge app_clk or negedge app_rst_n)
  if (!app_rst_n) ready_sr <= 32'd0;
  else            ready_sr <= {ready_sr[15:0], app_tx_ready_dp_r};
assign app_tx_ready_app = ready_sr[31:16];
```
- 逐位（不是整字）同步；每位单独变化、互不依赖；延迟 = DP 1 拍 + app 2 拍。
- ⚠️ **位宽（F12）**：`ready_sr` 必须 32 位；16 位写法会把 `src[15]` 截掉。
- TB 必须用逐位 walk-1 验证 16 条链各自独立、无错位。

### 4.4 RX 停读钩子（测试专用）

- 保留 wrapper 里 `pcie_scratch[2]` 的 2FF（DP 域），但**只门控 CDC RX FIFO 的 DP 写侧**：
  `wr_en`/`eco2_tready` 都带 `!rx_stall`。
- **wrapper 编辑点（F10）**：现 `board/wrapper_p4.v:1596/1600` 在源头上把
  `app_rx_tvalid` 与 `eco2_tready` 都门了 `!app_rx_stall` ⇒ 必须改成：
  - `eco2_tvalid`（raw）进入 CDC 包装；stall 门**只在 CDC 包装的 RX 写侧**施加；
  - `eco2_tready` 由 CDC 包装回驱（`!full && !rx_stall`）；
  - 否则包装层里的 `&& !rx_stall` 是冗余，**变异 #2（只门 tready 不门 wr_en）行为无差别
    ⇒ 空变异**。
- 目的仍是把 **echo FIFO（128 KB）** 灌满（W62 ≥ 12,288 的前件）；CDC FIFO 只装
  已从 echo FIFO 取出的字（≤ 256 字 = 2 KB），不影响 W62 语义。
- **停读不是瞬时（F15）**：停读后 app 仍会把 CDC RX FIFO 里已有的字消费完（**最多 ≤256 字
  = 2 KB**）才完全停住；若停读落在帧中，FIFO 里还可能有半帧。W62 前件不受影响（128 KB 缓冲），
  但板级判读不得把"停读"当成"立刻零消费"。

### 4.5 统计快照（相干性）

- app 域：10×32 + `close_pend_max[3:0]`（共 **324 位**）计数器；收到 req toggle 后，**一拍内**把全部字段锁进 `hold`，
  再翻 ack toggle。
- DP 域：每 1024 个 `dp_clk` 发一次 req toggle（≈6.55 µs 一次）；看到 ack 翻回后，
  把 `hold` 一起锁进 `shadow`（DP 域），快照/状态行读 `shadow`。
- 超时（如 4096 拍无 ack）⇒ 保持上次 `shadow`，置 `cdc_status[7]`（粘滞）。
- 成本：app 324 FF + DP 324 FF + 握手 ~30 FF；**LED 4 位走独立 2FF（不进 hold，F7）**；
  `close_pend_max` **随 hold/shadow 一起过 CDC**（不得 4 位直连）。
- 位语义（M-4）：**[4] 是当前位**（恢复后必须自清）；**[7] 是粘滞位**（曾发生）。两者不可
  并列读：**复位伴随的 [7]** 按 H-1 的复位见证豁免一次，非复位伴随的 [7] 才是故障。
- ⚠️ **不加新快照字也能工作**（读的是 DP 侧 shadow），但 W97 见 §4.6。

### 4.6 W97（CDC 健康字，板级验收必需）

新增 1 个快照字（**NW 97→98**，未实现地址 0x1B4→**0x1B8**）。

**落点（F7）**：W97 必须落 **`p7bdp` 束的槽 53**（`board/wrapper_p4.v:6195-6258` 的
`snap_dout_all`），`SNAP_P7BDP_NW` **53→54**（`:5036-5073` 的 localparam）；
`check_window.py` 的束宽等式与顶端槽号映射必须同步。

| 位 | 语义 | 域 / 见证类别 |
|---|---|---|
| 0 | **保留 0**（TX 无丢字：`wr_en` 与握手同式，静态门核对；计数器会是空判据） | — |
| 1 | **保留 0**（RX 同上） | — |
| 2 | 事件 FIFO 写被丢弃（`drop_ev`，事件丢失） | **DP 域**（写侧，F5）；**故障** |
| 3 | close FIFO 写被丢弃（`drop_cl`，close 丢失） | app 域 → 2FF；**故障** |
| 4 | 统计 stale（当前） | DP；**当前位** |
| 5 | `locked_app` 同步值（当前） | DP；**当前位** |
| 6 | `app_rst_seen`（**armed** 后 app 复位曾发生） | DP；**复位见证** |
| 7 | 统计握手超时（**app_alive 门控**） | DP；**故障** |
| 15:8 | 保留 0 | — |
| 19:16 | `stat_close_pend_max[3:0]`（随 stats hold/shadow 过 CDC） | app→DP；观测 |
| 20 | `dp_rst_seen`（**armed** 后 DP 功能复位曾发生） | DP；**复位见证**（F8） |
| 31:21 | 保留 0 | — |

- **F1 修法（阻断；v3 收紧）**：**不使用 `fifo_async.ovf_pulse`** —— 它与本设计的
  `wr_en = src && !full` 互斥（`ovf_pulse = wr_en && full ≡ 0`）⇒ 恒 0。仅**事件/close**
  （无 ready 的源）设 `drop_ev` / `drop_cl`（W97[2]/[3]），在各自写域置粘滞；**TX/RX 不设
  计数器** —— `src && full` 是 stall 计数、不是丢字，其不丢字由握手同式 + 静态门保证（§4.1）。
- **F2 修法（可执行性）**：
  - **arming**：粘滞位在板级 `reset_n`（各域同步释放）后先观察 **≥1024 个本域时钟** 才允许
    置位 ⇒ **上电/重烧不置**；[6]/[20] 只在 armed 之后的功能复位沿置位。
  - **无 clear 位**：不新增寄存器。**硬规则 = 观测到 [6]=1 / [20]=1 / [5]=0 ⇒ 立即停流、
    该轮作废、必须重烧重跑**（重烧 = 整机复位 = 连接全部拆除；这也是"全部重连"的
    **执行机制**，F3）。**删除 v2 的"无法重跑则重开窗"分支**（粘滞位无法回 0，该分支必败）。
  - **[7] 门控**：超时计数器仅在 `app_alive`（app_rst_n 同步 + armed）时计数 ⇒ app 复位窗内
    不会置 [7]；[7] 只表示"app 活着但不响应"。
- ⚠️ **判据分层（H-1 / M-4）**：故障见证 = **[2]/[3]、[7]**；复位见证 = [6]、[20]；
  当前位 = [4]/[5]。板级判据 = §7.1；不得再写"任何粘滞位 = FAIL"。
- 成本 ≈ 96 FF/字（`snap_cdc.hold_b` 32 + `dout_a` 32 + `snap_words_r` 32）+ drop/arming
  ≈ 30 FF + `app_tx_ready` DP 寄存器 16 FF。
- **读侧必须链式同步（F7 扩）**：
  - `apply_readside ... --bid 0x36`（NW 98 / UNIMPL 0x1B8）；`p7b_snap.sh` 用
    `NW=98 UNIMPL_ADDR=0x1B8`；
  - **MIR 四字随 NW 平移**：NW=97 时 `MIR_STATUS=0x1A4 … MIR_DMA_CNT=0x1B0`；NW=98 时
    **全部 +4 = 0x1A8 … 0x1B4**（v2 只写了 UNIMPL，漏了这四格）；
  - `_proj_pcie/p7b_biz/p7b_mir_dump.cpp:157` 仍硬编码 NW=71 代的
    `0x13C/0x140/0x144/0x148` ⇒ **本批不用/重指**，不得照跑；
  - `tb_biz_win` 的 `NW` 是 localparam ⇒ **一个二进制只能验一套几何**；本批要求
    `+define+NW=98` 参数化（或编译两份变体），否则"两种几何都过"是空话。

---

## 5. 实施清单（逐文件）

### 5.1 新增

| 文件 | 内容 |
|---|---|
| `rtl/app_clk_gen.v` | 第二 MMCM + BUFG + `locked`/复位同步；`SIM_BYPASS` 参数供 TB |
| `rtl/app_multi8_cdc.v` | §4.1 的 CDC 包装（含统计握手、W97 状态） |
| `board/ku5p_p7b_app8_cdc.xdc` | §2.2 的两条 `set_false_path`（只在该构建加入） |
| `sim/p11_app8_cdc/run_tb_app_cdc.bat` 等 | 单元门（§6） |

### 5.2 修改

| 文件 | 改动 |
|---|---|
| `board/wrapper_p4.v` | `P11_APP8` 分支里：`ifdef P11_APP8_CDC` ⇒ 例化 `u_appclkgen` + `app_multi8_cdc`；`else` ⇒ 现有 `app_multi8`（**逐字保留**）。**`:1596/1600` 的 `rx_stall` 双门改为"raw `eco2_tvalid` 进包装、tready 由包装回驱"**（F10）。快照：W97 → **`p7bdp` 槽 53 / `SNAP_P7BDP_NW 53→54`**；`NW` 97→98（宏分支，见 §5.3） |
| `board/build_p7b_ku5p.tcl` | 新 env `P11_APP8_CDC`（默认 0；=1 需 `P11_APP8=1 && P11_DUAL && DP_156MHZ && P7B_10G` —— **F13：`clk_in_100` 在 `ifdef P7B_10G` 内**）；加 define；加 CDC XDC；快照几何检查（W97）；**顺手修 `:88` 的陈旧注释"1 = 0x35 修复臂"（F16）** |
| `_proj_10g/notes/p7b_biz_win/tb_biz_win.v` | `NW` 改为 `+define+NW` 可参数化（或两份变体），否则"两套几何都过"无机制（F7） |
| `_proj_pcie/p7b_biz/p7b_mir_dump.cpp` | 现硬编码 NW=71 代地址（`:157`）；**本批不用/重指**（F7） |
| `board/ku5p_p7b_app8_cdc.xdc` | 仅 CDC 构建加入，`used_in_synthesis false` |
| 读侧 20 文件 | NW 98 / UNIMPL 0x1B8 / W97 标签 |

### 5.3 快照几何的取舍

- W97 只在 CDC 构建有意义。若把 NW 从 97 改成 98 编进**所有**构建，会让 0x34 老位流的
  读侧失效（地址错位）。⇒ **两种方案二选一，必须在实施前定**：
  - **A（推荐）**：`SNAP_NW` 由 `P11_APP8_CDC` 宏选择 97/98；读侧按 BID 区分
    （0x34/0x35 = 97；0x36/0x37 = 98）。风险 = 宏分支的几何必须两套都过门。
  - **B**：CDC 构建沿用 97，W97 只上 LED/不观测；板级验收少一个见证（不推荐）。
- 本设计取 **A**，并把“两种几何都过 `tb_biz_win`/`check_window`”列为门。

---

## 6. 验证计划（施工前/后都要）

### 6.1 单元 TB（新）

| # | 用例 | 判据 |
|---|---|---|
| C1 | TX 流：随机 `tready`，跨帧 `tlast/tid/tkeep`，长短帧混合 | 逐字等价、帧边界不破、无丢/重 |
| C2 | RX 流：同上，含 `rx_stall` 注入 | 停读期间 app 零新字、echo 侧 tready=0；恢复后逐字续 |
| C3 | 事件：8 槽 up/down 随机、背靠背、FIFO 近满（**同拍 up+down 不写判据**：结构性不可达，M-3） | 顺序保持、不丢、每事件恰一拍 |
| C4 | close：8 连接逐个 close、背靠背 | 顺序/ID 保持、`ovf=0` |
| C5 | `app_tx_ready`：逐位翻转、跨域延迟 2 拍 | 无毛刺、每位独立 |
| C6 | 统计：计数器每拍变化 + req/ack 握手 | 同一次 `shadow` 的所有字段来自**同一 app 拍**（用斜坡编码检验）；超时置 stale |
| C7 | 复位：两域独立复位/偏斜释放/FIFO 两侧同 `reset_n` | 无陈旧字重现、无死锁；`app_rst_seen` 置位 |
| C8 | 时钟比：156.25/156.25（随机相位）、156.25/100 | 全部判据仍成立（验证不依赖 1:1） |
| C9 | **数据与事件交叠**（M-3）：TX/RX 流进行中插入 ev_up/ev_down，±1~2 拍偏斜 | 事件顺序不丢、数据逐字、无死锁 |
| C10 | **app 复位窗事件重放**（H-2）：窗内 N≤16 事件 ⇒ 释放后全部按序；N=17 ⇒ W97[2] | 重放顺序/次数精确；溢出见证置位 |
| C11 | **跨会话 RX 残留**（M-2）：快关快开 + FIFO 预填，旧会话字 ≤256 | 残留只出现在新会话头 ≤256 字内；不增长；记录 mismatch 窄窗 |

### 6.2 变异门（每个必须红）

1. TX FIFO `wr_en` 去掉 `!full`；2. RX 的 `rx_stall` **只门 tready 不门 wr_en**
（施加点 = CDC 包装 RX 写侧，F10 后才有判别力）；3. 事件 FIFO 丢 `ev_slot`；4. close FIFO
丢 `close_id`；5. **`app_tx_ready` 同步去掉一级（单 FF）或去掉 `ASYNC_REG`**（F11：
"整字 2FF"与逐位 2FF 硬件等价，不能当变异）；6. 统计不做 hold（直连）；7. 统计握手无超时；
8. `set_false_path` 只写一个方向（静态门）；9. **`drop_ev/drop_cl` 改回 `ovf_pulse`**
（F1：必须使 W97[2]/[3] 恒 0、C10 的 N=17 不红，证明该变异有牙）；10. **TX/RX 的 `wr_en`
与握手接受式改成不同表达式**（静态门必须红）。

### 6.3 集成/结构门

- `tb_app_multi8` 现有 A/B/C/D 用例在 **CDC 包装**下复跑（时钟比 1:1 + 相位偏移）。
- 结构检查（Tcl/脚本）：
  - `u_app` 的 clock pin = `clk_app`，reset = `app_rst_n`；
  - `u_appclkgen` 存在且 `u_mmcm` 参数 = 156.25；`clk_in_100` 连接在 `P7B_10G` 宏下（F13）；
  - **`P11_APP8_CDC=0` 构建：`u_appclkgen` 0 cell、`u_app.clk=dp_clk`、`u_app_cdc` 0 cell**（零回归）；
  - **`report_cdc -details` 落盘 + 白名单**（4 个 FIFO、逐位 2FF、stats 握手、`app_tx_ready`、
    事件/RX 的 drop 计数器）：白名单外的跨域即 FAIL（F9）；
  - **`report_clock_interaction` 全配对表**：所有含 `clk_app` 的配对必须是 Asynchronous /
    False Path（dp↔app 由 `set_false_path`；clk_app↔pcie/gt 由 sys_clk_100 组）——**不只查
    dp↔app 一对**；
  - `set_false_path` 的承载见证 = `report_cdc`/`report_timing` 中该对无时序路径 + 无 `12-4739`；
    **不得把报告的分类字符串当唯一判据**（F9）。
- 常驻矩阵：新门入册（第 42/43/44 门）。

### 6.4 构建门与综合确认

`P7B_TIMING_GATE`（WNS>0 ∧ 0/0/0）· `P11_STA_TCB_GATE` · DRC · `P7B_SNAP_TOP5_CDC` ·
**`P11_APP8_CDC_GATE`**（§6.3 的结构/CDC 检查）。

**L-1 综合确认（v2 新增）**：`fifo_async` 是双时钟 + 组合读（FWFT），**只能推断为分布式
RAM**（`rtl/fifo_async.v:98/100` 自注：双时钟 LUTRAM 推断**未过综合验证**）⇒ 0x36 构建
必须在 synth 后核对：
- **LUTRAM 计数**落在估算带（≈ **+1,080 LUT**）；cell 类型只作 INFO 打印 —— UltraScale
  合法分布式 RAM 还有 `RAM32X1D` / `RAM128X1D` / `RAM256X1S`，白名单过窄会假红（F14）；
- **FF 增量 < 200/条**；若出现 ≥1k FF 阵列（触发器推断）⇒ **立即停构建、重评估**
  （77×256 触发器阵列 = 19,712 FF/FIFO，超阈值 50×）；
- BRAM 不因此增加（BRAM 109 不变）。

### 6.5 不变量（L-6）

1. **app 复位期间 RX 侧持续排空**：`app_pattern` 复位态 `rxs=0` ⇒ `rx_tready=1` ⇒ CDC RX FIFO
   继续排空 ⇒ 复位后不留下 RX 积压（与 M-2 的跨会话残留不同）。
   ⛔ 任何改动 `rxs` 复位值、或在包装层用 `app_rst_n` 门 `rx_tready` 的改动，都必须重新评估
   M-2 与复位窗行为（v3 的 W97 已不设 RX drop 位，F1 收紧）。
2. **FIFO 只认板级 `reset_n`**（§4.2）；不得把 `app_rst_n` / `dp_rst_n` / `locked` 接进新的
   CDC FIFO 复位。
3. **`app_tx_ready` 必须在 DP 侧先寄存一拍，再进 app 侧逐位 2FF**（F6）；
   **不得把组合信号直接跨域**（"整字 2FF"与逐位 2FF 等价，F11 —— 它不能当变异）。
4. **drop 见证**：`W97[2]/[3]`（事件/close）只能用各自写域的 `drop_* = src_valid && full`
   （F1）；**不得用 `fifo_async.ovf_pulse`**（与本设计的 `wr_en` 互斥，恒 0）。
   **TX/RX 不设 drop 计数器**：`src && full` 是 stall 计数，不是丢字；由 `wr_en` 与握手
   接受式同式 + 静态门保证（变异 10）。
5. **复位见证 arming**：`[6]`/`[20]` 必须在板级 `reset_n` 后 ≥1024 本域拍才允许置位；
   **无 clear 位**；观测到即停流/作废/重烧（F2）。

---

## 7. 构建与板级顺序

1. **0x36**：`P11_APP8=1 P11_APP8_OCC=0 P11_APP8_CDC=1`，策略先用 `Performance_ExtraTimingOpt`
   （新路径集下的基线）；**若失败，只允许一次重试且必须用 `Congestion_SpreadLogic_high`**
   （不得引入第三种策略；L-5）。
2. 0x36 过门 ⇒ **0x37**：同 CDC + `P11_APP8_OCC=1`。
3. 板级 A/B（0x36 vs 0x37）按 `DESIGN_OCC_V6.md` §6.6 的协议（端口映射：port0/J7 =
   板 .4 ← nsb .101），W97 判据按 **§7.1**（复位见证 vs 故障见证；**不再用"任何粘滞位 = FAIL"**）。
4. 通过后：8×12KB 合同、第 9 连接拒绝、F1（TCB rcv_wnd=12KB）、F6/F14/F18 的观测项。

### 7.1 W97 板级判据（v3；H-1 / F1 / F2 / M-4）

| 类别 | 位 | 处置 |
|---|---|---|
| **故障见证**（粘滞） | [2] 事件 drop · [3] close drop · [7] 统计超时 | 有效臂内增量必须 **0**，否则 **FAIL** |
| **复位见证**（粘滞） | [6] `app_rst_seen` · [20] `dp_rst_seen` | **硬规则：任一为 1 ⇒ 立即停流、该轮作废、必须重烧重跑**（不记 PASS/FAIL；**无"重开窗"分支**） |
| **当前位** | [4] 统计 stale · [5] `app_locked` | [4] 恢复后必须自清（连续两帧为 1 ⇒ FAIL）；[5] 每次读数必须 1（=0 ⇒ 作废 + 重烧） |

**每臂流程**：
1. 开跑前基线（重烧后）：`[2]=[3]=0 ∧ [7]=0 ∧ [6]=0 ∧ [20]=0 ∧ [5]=1`（[0]/[1] 恒 0）。
   **arming 保证上电/重烧不置 [6]/[20]**（§4.6）。
2. 跑中任一帧 `[6]=1` / `[20]=1` / `[5]=0` ⇒ **立即停流、本臂作废、重烧重跑**
   （重烧 = 整机复位 = 连接全部拆除 ⇒ 这就是"全部重连"的执行机制）。
3. 有效臂：`[2]/[3]` 增量 = 0、`[7]` = 0、`[4]` 不得连续两帧为 1。
4. 报告必须写：W97 基线/终值逐位、是否发生 app/DP 复位、作废轮次（如有）。

---

## 8. 预期与风险

**预期收益**：DP 的 app CE 族（#4 的最差 10 条）整族消失 ⇒ WNS 回到 0x33 量级
（+0.008 附近）。**不是保证**：8×app 的 15k LUT 仍在 die 上占面积，DP 的 TCB 族
（0x31 +0.031 / 0x33 +0.008）仍可能只剩 0.0x ns。

**新增成本（v2 入账；L-1）**：两条 77×256 FWFT 双时钟 FIFO = **分布式 RAM，约 +1,080 LUT**
（`fifo_async` 组合读 ⇒ 不能进 BRAM）→ 另加 dp_clk 侧 77 位读口布线；事件/close 小 FIFO +
2FF + 统计 hold/shadow ≈ **+700 FF / 少量 LUT**；MMCM+BUFG 1 组；W97 ≈ +96 FF。
**BRAM 109 不变**（不恶化也不改善）。

**风险（按严重度）**：
1. **DP 仍差 0.0x–0.1 ns**：backstop = 0x36 用 `Congestion_SpreadLogic_high` 再试一次；
   仍不过 ⇒ 转方案 B（图案引擎共享，降面积 ~9k LUT）。
2. **CDC 漏网**：任何未经同步器的跨域都会被 `set_false_path` 摘掉 ⇒ **边界普查 + 结构门**
   是硬前置；审查必须逐条核对 §3 清单。
3. **统计握手在 app 复位时 stale**：v3 改为 **[7] alive 门控**（复位窗内不计数）+ [4]
   当前位自愈；复位本身由 [6]/[20] 见证，硬规则 = 重烧（§7.1）。
4. **app 时钟失锁 = 相位断一次**（F-3 同类）：登记，不做修复；W97[5]/[6] 见证。
5. **latency 基线漂移**：CDC 增加 TX/RX 各 1–2 拍 + 同步延迟（≈20–30 ns）。E1a 的
   p50/p99（2.46–3.27 µs）**不可与 0x33 直接比较**，必须重新标基线。
6. **W97 几何**：NW 97→98 与读侧 20 文件同步；两套几何都要过门（§5.3-A）。
7. **第二 MMCM 资源/时钟质量**：KU5P MMCM 数量足够（审查现核 **1/4 已用 ⇒ 剩 3**）；
   输入走 BUFG，MMCM 输入路径需在 STA 里确认。
8. **TX 半帧（Q8/F3，结构性可达）**：消费者是 **`tcp_tx_frame` 的 `S_RECV`**（不是 tcp_echo），
   只有 `tlast`/`len_over` 出口；app 一帧中途复位 ⇒ 半帧残留 ⇒ **wedge 或跨连接错帧**（旧
   tid/seq + 新载荷）。**v3 = 登记残余 + 硬规则**（[6] ⇒ 停流/作废/重烧）；有界恢复
   （`app_tx_abort`）另开设计，**不在 v3**。
9. **LUTRAM 推断（L-1）**：若综合把 77×256 FIFO 推成触发器阵列，面积/时序会炸 ⇒ 由 §6.4 的
   综合确认门拦截（≥1k FF 阵列即停）。
10. **drop 见证的牙（F1）**：W97[2]/[3] 依赖 `drop_ev/drop_cl = src_valid && full`；变异 9
    （改回 `ovf_pulse`）必须使见证恒 0、C10 的 N=17 不红；TX/RX 由握手同式 + 静态门保证
    （变异 10）。
11. **CDC 门白名单维护（F9）**：`report_cdc -details` 白名单必须随任何新跨域信号同步；
    白名单外即 FAIL，避免新增 CDC 静默漏检。

### 8.1 跨会话 RX 残留（M-2；登记残余）

- **现象**：`ev_down → ev_up`（同槽快速重连）时 CDC RX FIFO 不冲刷；最多 **256 个旧会话字**
  （2 KB）会在新会话头后交给 app ⇒ 以新会话 SEED 判读 ⇒ `stat_mismatch` 污染 / 该连接 RX 错位。
- **对比**：今天同域路径在飞 ≤1–2 字；CDC 后上限 = 256 字，是**新增**风险（不是既存缺陷的放大）。
- **判据口径（F4 订正）**：
  - **OCC A/B 两臂（8 连接建立后不换流）**：`stat_mismatch` 必须 **0**（无换流 ⇒ 残留不触发）。
  - **换流/重连臂**：**不得用 `stat_mismatch` 作内容判据** —— 旧残留字在 `ev_up` 之后交付，
    LFSR 前进了 ≤2048 B 步且**没有重同步**（`rtl/app_pattern.v:790-792/1116-1146`）⇒ 该连接
    余下**全部**字节都会失配（不是"一次性"）。判据改为：
    ① 残留长度 ≤256 字（用 RX FIFO 占用/首帧偏移见证）；
    ② **该槽自换流起 mismatch 持续增长属预期**，把该连接的 RX 内容结果**整体排除**；
    ③ 未换流的连接 mismatch 仍必须 0。
- **单元门**：C11（快关快开 + FIFO 预填，判据按上面三条）。
- **根治（不在 v3）**：`ev_up` 时冲刷 RX FIFO / 丢到新会话首帧边界（`fifo_async` 无 flush
  端口 ⇒ 需新增 flush 逻辑）；下一轮评估。

---

## 9. 待审查裁定的开放问题

| # | 问题 | 本设计倾向 |
|---|---|---|
| Q1 | `set_false_path` vs 重组 `set_clock_groups` | **false_path**（不动既有四域分组） |
| Q2 | W97 与 NW 97→98 是否本批做 | **做**（板级验收需要 CDC 见证；方案 A） |
| Q3 | 第二 MMCM 输入用 `clk_in_100` 是否可接受 | **可**（不改 `clk_gen_p6b`） |
| Q4 | TX/RX FIFO 深度 256 是否够 | 够（一帧 183 字）；**不能升 512**：双时钟 FWFT 只能 LUTRAM，加深 = LUT 线性翻倍（L-1） |
| Q5 | app 复位时 TX/RX FIFO 是否要与功能复位同代 | **不**（P6B 硬规则：FIFO 只认 `reset_n`） |
| Q6 | 统计握手周期 1024 拍 / 超时 4096 拍 | 倾向值；可按快照节奏调 |
| Q7 | 0x36 的 BID/位流命名与读侧链 | 0x36/0x37；`--bid 0x36` |
| Q8 | **TX 半帧**（v2 自核；独立复审 F3 改判）：消费者 = `tcp_tx_frame/S_RECV`，后果 = wedge **或跨连接错帧** | **【已判定 · 结构性可达】**（触发 = app 复位时任一 app 有在飞帧）；v3 登记残余 + 硬规则（[6] ⇒ 重烧）；有界恢复另开 `app_tx_abort`（不在 v3） |

> **xr12 审查意见（v2 记录）**：Q1–Q7 **全部同意设计倾向、无需用户裁定**；Q4 的 "BRAM 允许"
> 前提已按 L-1 删除。Q8 已由独立复审 F3 改判为"结构性可达"（见上）。

---

## 10. 施工完成定义（DoD）

- [ ] **v1 审查（xr12）+ 独立复审 F1–F17 逐条处置落库（`REVIEW.md`）+ v3 复审通过**
- [ ] 新模块 + 门 + 变异全绿；`P11_APP8_CDC=0` 零回归结构门全绿
- [ ] **§6.4 LUTRAM 综合确认门**：LUTRAM 计数落在估算带、无 ≥1k FF 阵列
- [ ] 0x36 全构建 `P7B_TIMING_GATE` PASS（WNS>0 ∧ 0/0/0），归档（含 dcp）
- [ ] 0x37 同策略 PASS
- [ ] 板级：身份（BID/NW/UNIMPL/2BAR/x4/carrier）、**W97 按 §7.1**（故障见证 0；
      [6]=[20]=0；[5]=1）、8×12KB、OCC A/B（0x36 vs 0x37）、第 9 连接拒绝、F1
- [ ] **局限登记（F17）**：无 0x34/0x35 非 CDC 8-app 位流（均未过时序门）⇒ 板级**无法**把
      功能差异归因给 CDC；只能拿 0x33（2 app）做"没把系统打死"的冒烟前后对照，**不得**
      写成"CDC 等价已板级证明"
- [ ] 文档：README/OPEN_ITEMS/台账/审查队列同步；所有读数带文件:行
