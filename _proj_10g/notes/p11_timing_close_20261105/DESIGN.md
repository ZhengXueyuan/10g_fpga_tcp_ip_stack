# P11 DP 时序收口（0x3B 诊断/产品共用）—— 设计件 v1（2026-11-05）

状态：**【已定位·构建读数】**：0x36 之后任何 netlist 扰动都使既有 DP app/TCB 路径失败；
0x39 −0.629 / 0x3A placement 停 / 0x3B ExtraTimingOpt −1.359 / **ExplorePostRoutePhysOpt −0.153**
（2789 setup，WHS +0.004）。目标 = 让 0x3B（W51..W53 诊断）先过一个 **WNS>0、0 失败端点**的门。

## 1. 失败族（实测，按严重度）

- **F1 = TCB 写侧 CE 族**（主导）：`u_tcp_tx/u_fifo_b/rptr_reg[4] → u_tcb/rcv_nxt_r_reg[*]/CE`，
  WNS −0.175（9/10 条 top path）。路径穿过 `u_fifo_b → u_fifo_a(bank_rdy/ctrl_doff) →
  u_ackq(start_ack_d1) → u_tcb(f_seq/rcv_nxt CE)`；route 5.0/6.4 ns，17 级。
- **F2 = port1 app 读侧**：`u_tcp_tx2/u_ackq/rptr → u_app2/stg_reg[14]`，−0.176；
  穿过 `u_tcb2(ring_rem/rb2_state) → u_ackq(scan_estab/win_open) → u_app2(q1_app_tready/
  seg_sent/pw_n/tx_lfsr)`。
- 既有证据（`board/build_p7b_ku5p.tcl:824-831`）：**F1 的 RTL 写延迟会破坏 retx 序列**
  （txdrop50 实测 3/5 帧失配）⇒ **禁止**对 TCB 写路径加寄存器延迟。

## 2. 收口策略（按风险/代价排序）

1. **P1 策略搜索（零 RTL）**：同 synth 网表 + 多 impl strategy 并行（NetDelay_high /
   Congestion_SpreadLogic_high / Performance_Explore，必要时 RefinePlacement）。
   先例：同 RTL 换 strategy 摆动 0.197–0.464 ns、方向不可控（P7B_MAC_TIMING_FIX §7.3）；
   当前缺口 0.153 ⇒ 预登记：**任一臂 WNS>0 且 0 失败端点即通过**；否则进 P2。
2. **P2 安全复制（无功能延迟）**：对 F1/F2 链上的高扇出**控制寄存器**加
   `(* max_fanout = … *)`（`start_ack_d1` fo=88、`bank_rdy`、`ctrl_doff`、`f_seq[0:1]`；
   port1 的 `win_open`/`q1_app_tready` 驱动侧）。复制 = 同时钟域、同逻辑、只降 route，
   **不改变任何写时序** ⇒ 不触 retx 禁区。代价 = 若干 FF 副本（资源 24% 有余量）。
3. **P3 app 读侧 A7 式重定时**（仅 F2）：把 app 的 `tx_ok` 判定打一拍（窗口/信用准静态；
   需 A7 式逐拍论证 + 行为等价门），**不碰 TCB 写**。
4. **P4 floorplan/pblock**（最后手段）：把 `u_tcp_tx*`/`u_tcb*`/`u_app*` 约束到邻近区域，
   消除 route 绕行；需布局实验。

## 3. 验收

- 先决：从同一 synth 网表出发，bitstream 的 BID 仍 0x3B（RTL 未变；策略是构建输入），
  臂与 sha 记入 `SWEEP.txt`；**未过门的臂不得烧板**。
- 过门 = `P7B_TIMING_GATE = PASS`（WNS>0 / 0 失败端点）+ 既有 `P7B_DIAG3B_SRC 111` /
  `P7B_SNAP_TOP5_SLOTS_OK=15` / no blackbox。
- 过门后：烧 0x3B → `verify_0x3B.sh`（8×0.5 s 交错 + 快照）→ 读 W51（ready 向量）/
  W52（ev/estab）/ W53（init_ovf），判定 app TX 缺陷分支。
