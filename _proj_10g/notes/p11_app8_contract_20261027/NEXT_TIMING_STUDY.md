# P11 APP8 时序攻坚：下一轮方案研究（**研究件，不是实施授权**）

- 日期：2026-10-28
- 触发：0x34（8×12KB + 8 app）四次构建全部 `P7B_TIMING_GATE = FAIL`（见 `build_fail{1,2,3}/FAILURE.md`）
- 口径：**所有数字都来自构建原件**；本件只做方案研究，未改 RTL、未构建、未上板。

## 1. 已测事实（三次布局/策略实验）

| # | 输入（同一 RTL/合同） | WNS | setup 端点 | 最差族 |
|---|---|---|---|---|
| 2 | `Performance_ExtraTimingOpt`，无 pblock | −0.337 | 6,642 | `u_tcp_tx2/u_fifo_b/rptr → u_tcb2/rcv_nxt[9][11]/CE`（route 4.907 / 74.4%） |
| 3 | 同 #2 + `u_app` pblock（左下 `X0Y0:X49Y79`） | −0.644 | 13,282 | 同族，**更差** |
| 4 | `Congestion_SpreadLogic_high`（`AltSpreadLogic_high`），无 pblock | **−0.205** | **5,162** | `u_tcp_tx/bank_rdy[1]_replica → u_app/g_app[4]/pw_data CE`（22 级 / logic 2.098 / route 4.381 / 67.6%） |

- 参照：0x33（2 个 app）同族 **+0.008**；0x34 是 9 个 app（port0 8 + port1 1）。
- 边际 ≈ **0.345 ns / 7 个额外 app** ⇒ **不是布局运气问题**。
- 打散（spread）方向有效（−0.132 ns / −1,480 端点），但最差族换到 **port0 的 `bank_rdy`
  扇出锥**（同一根 net 同时驱动 TCB 写使能与 8 个 app 的 TX CE）⇒ 多点同时受压。

## 2. 为什么"只换布局"天花板不高

- 失败只在 `g_hw.clk_out0`（DP）；`pcie_axi_aclk` 等全 0。
- 8×app 的 **15,328 LUT / 5,956 FF** 与 DP 的 tcb/tcp_tx 同域、同区域竞争；布局只能挪位置，
  不能减少"同域大扇出 + 大量负载"本身。
- pblock 反噬的机理（推断，未做拆刀）：硬隔离把 app 压进更小区域，且 DP 的关键 cell 仍要
  与该区域通信 ⇒ 局部拥塞更重。

## 3. 方案 A（首选）：8×app 组独立时钟域 + CDC + pblock

**边界天然干净**：`rtl/app_multi8.v` 对外只有：
- TX 一条 77-bit AXIS（`m_tdata/tkeep/tvalid/tready/tlast/tid`）
- RX 一条 77-bit AXIS（`rx_*`）
- `ev_up/ev_down/ev_slot`（事件）、`close_req/close_id`（事件）
- `app_tx_ready[15:0]`（电平）、若干 32-bit 统计

**时钟源**：新增第二个 MMCM（同一 100 MHz 参考），输出 156.25 MHz 作为 `app_clk`。
它与 `dp_clk` 频率相同但相位独立 ⇒ 可合法 `set_clock_groups -asynchronous`。
（⛔ 不能用同一个 MMCM 的另一个输出冒充异步：那是同源锁相，静态时序仍必须关。）

**CDC 清单**：
| 信号 | 方向 | 方案 |
|---|---|---|
| TX 77-bit AXIS | app→DP | `rtl/fifo_async.v`（77 位 × 深度待定，512 拍 ≈ 39 kbit） |
| RX 77-bit AXIS | DP→app | 同上 |
| `ev_up/ev_down/ev_slot` | DP→app | 6-bit 小异步 FIFO（深度 8）或 toggle 握手 |
| `close_req/close_id` | app→DP | 5-bit 小异步 FIFO（深度 8） |
| `app_tx_ready[15:0]` | DP→app | 逐位 2FF（电平；每位独立、无跨位语义） |
| 统计 32-bit × ~14 | app→DP | app 域计数 + 快照请求/应答握手（低频） |

**然后**把 `app_multi8`（含 mux/demux/close）pblock 到专用区域。此时边界全在异步 FIFO 上，
DP 的关键路径不再穿到 app 区 ⇒ pblock 不再"拉长 DP 路径"（与 #3 失败的关键区别）。

**代价**：
- +1 MMCM、2 个 77-bit 异步 FIFO（BRAM/分布式）、~6 位事件 CDC、16 位电平 CDC、统计握手；
- 设计/验证：CDC 审计 + 每个 FIFO 的满/空/复位语义 + 事件不丢/不重 + 统计相干性；
- 吞吐：app 仍 156.25 MHz，**聚合 8 B/cycle 不变**（mux 本来就是 8→1 单流）⇒ 不影响 10G 目标；
- 风险：新增 MMCM 的时钟质量/复位序；CDC 若做错会产生**静默丢事件**（必须专门门）。

## 4. 方案 B（备选）：app 图案引擎共享/降面积

- 单实例 ≈ **1,916 LUT / 745 FF**（8 实例 15,328 / 5,956）。
- LFSR 的 M⁸ 推进是**线性**的：`next = M⁸ · state`。8 个实例可用**一套** M⁸ 常量 XOR 网
  分时复用（8 拍轮转），每实例每 8 拍推进 8 字节 ⇒ **每连接 1 B/cycle**，8 连接聚合
  **8 B/cycle = 10 Gbps** —— 与 mux 的单流上限**恰好相等**。
- 代价：每连接突发 12,288 B 需要 12,288 拍（78 µs）；窗口/BDP 语义要重新核算
  （v6.6 已写 12KB/条、RTT 9.83 µs 贴窗，单条 4.9 Gbps 上界；1 B/cycle 下 1.25 Gbps/条，
  8 条聚合仍 10G）⇒ **合同可能仍成立，但产品时延变差**。
- 收益：可能省下 ~7×1.3k ≈ 9k LUT，是从"面积"上解决问题；但与"app_pattern 零改动"
  的现约束冲突（需新增变体 + 逐位等价证明 + 新门）。改动比方案 A 更深。

## 5. 建议顺序

1. **方案 A**（独立域 + CDC + pblock）：改动局限在 wrapper + 新 CDC 包装，app_pattern 不动；
   先写设计件 + 对抗审查，再实施、门、一次构建。
2. 若 A 后 8×app 自身域内时序仍紧（synth 检查点看 `u_app` 域 WNS）⇒ 再叠 **方案 B**。
3. 任何构建仍只认全构建 `P7B_TIMING_GATE`；失败即归档、不烧板。

## 6. 未判定项（不许当已答）

- 方案 A 的 CDC FIFO 深度：TX/RX 各 512 拍是**估值**，未按突发/背压实测标定。
- 第二个 MMCM 的可用位置与时钟质量：未查 `clk_gen` 现状与 MMCM 余量。
- pblock 区域选择：**未做数据驱动的 placement 查询**（build_fail3 的 routed dcp 已归档，
  可先查 `u_app/g_app[*]`、`u_tcp_tx/bank_rdy_reg[1]`、`u_tcb2/rcv_nxt_r_reg[9][11]` 的 LOC）。
- 方案 B 的"1 B/cycle/conn 仍满足 8×12KB 合同"只是纸面推算，未做窗口/时延复核。
