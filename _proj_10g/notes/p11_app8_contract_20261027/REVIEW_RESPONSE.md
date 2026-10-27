# P11-APP8 独立审查处置（2026-10-27）

- 审查者：独立 Claude agent（只读；DESIGN 初版 + 现树实现交叉核对）
- 结论原文：**不可（当前版本）** —— H1/H2/H3/H6 未闭环前不建议 0x34 构建/上板
- 本件 = 逐条处置；**H2 是产品级 blocker，需用户裁定**；其余按下列状态推进

---

## 高

| # | 结论 | 处置 |
|---|---|---|
| H1 | 共享 TX 活性：选中后源撤 valid 可永久锁 mux | **已修（RTL）**：`axis_frame_mux8` 加 `started`；**首拍被接收前**源撤 valid ⇒ 释放并重仲裁（`rtl/axis_frame_mux8.v:62-103`）。TB A3 已覆盖（撤字→`stat_abort_sel+1`→其它源继续服务）⇒ `TB_APP8_PASS`。**H1-b（已进下游帧器的帧被零窗/死连接永久拒收）未修**：mux 无法撤销已交接的帧；登记为**共享单帧器的产品语义边界**（见 §M5/H2），待产品裁定。 |
| H2 | **8×12KB 合同在接收方向被"全口占用"双重扣减**：`fq = winq − rx_occ_global`；`grant = min(wq_cap, pool − occ_global)` | **未修 —— 产品级 blocker，待用户裁定**（见 §裁定请求）。源码证据：`rtl/app_ctrl.v:769-774,973,1190,1480-1483`；`rtl/win_pool_mgr.v:20-26,300-330`；`board/wrapper_p4.v:1514-1516`。**纯下行（对端不发载荷）时 occ=0 ⇒ 本轮下行判据不受影响**；但 8 连接接收/双向会塌窗。 |
| H3 | 设计与实现几何/观测面矛盾（3 vs 4 字、NW 97 vs 100） | **已解决（文档）**：本轮**不加**快照字 ⇒ **NW 97 / 未实现 0x1B4**；4 个新观测只在模块/TB（`stat_arb_frames/abort`、`orphan_frames/bytes`、`close_pend_max`、`dbg_inst_mismatch`）。DESIGN §2.7/§5/§7.2 已改写。 |
| H4 | "P11_APP8 默认关 ⇒ 既有构建逐位不变"不成立：合同常量不在宏内，BID 已 bump | **口径已订正**：零回归只承诺"**app 数据通路**折叠"（`app_pattern` 逐字 + `P11_APP8` 未定义 ⇒ `u_app` 原例化）；**合同 8×12KB 与 BID 0x34 是本轮有意的产品输入**。需同步的常量已列：`tb_biz_win.v:29/61/158`（NW 97 / BID 0x34）、`p7b_snap.sh:92-94` 默认值、`p6e_snap_check.sh:60/308`（若使用）。 |
| H5 | 单元门跑的不是板级配置：无 `P7B_10G`；D 段无反压/无 ev_down | **已修（TB）**：`compile/run_tb_app8.bat` 加 `-d P7B_10G`；新增 **A3**（撤字）与 **D2**（300 拍反压 + ev_down + 恢复，≥6 连接继续出帧、无死锁）⇒ `TB_APP8_PASS`。**仍未做**：wrapper 级 APP8 门（层级引用 TB 不兼容，见 M13）。 |
| H6 | 板级判据只覆盖下行；RX 分发 / 12KB 实际窗无判据 | **未做 —— 待裁定**。下行时 `tcp_echo` 无载荷，8 个 RX 校验器不工作；B5 的 `ss` 窗在纯下行是空判据。需加 **8 连接上行臂**（PC 多连接 source + 板侧 W53/W54/逐连接 `snd_wnd`）才能证 12KB 合同。 |

---

## 中

| # | 处置 |
|---|---|
| M1 | **synth 检查点已跑**（`P11_CFG=c4 P11_APP8=1 P11_STA_ONLY=1`）：**synth 总 LUT 142,049（65.5%）**、`u_app` = **15,328 LUT / 5,956 FF**；最差 top-5 = `u_tcp_tx2/FSM_sequential_rx_state_reg[1]/C → u_app2/pw_data_reg[*]/CE`，**slack −0.706 / 23 级**（**port1 现役 app，不是新 8 实例**；0x33 synth top 为 −0.535 同族）。⇒ **synth 阈值 −0.100 无判别力**（0x33 通过臂 synth 也远低于 0）；判决必须走全构建。**构建策略预登记 = `Performance_ExtraTimingOpt`**（0x33 的通过臂；作为新输入，不是重试）。 |
| M2 | 本轮**不加**快照字 ⇒ 无 96 FF/字成本；观测面与 0x33 相同（W51..W54 为聚合 app 计数）。 |
| M3 | 文档已改为"8 连接时 margin 预算只剩 **310 B**"（`8×3328 = 26,624 ≤ 26,934`）。 |
| M4 | **init 队列 4 深**（`rtl/app_ctrl.v:576-589`）：8 并行 connect 可在 ~12 拍内溢出（`stat_init_ovf` 未接快照）。**未修**；板级测试工具将**串行/错峰建连**并在报告中注明"测试顺序，不是产品限制"；产品若要求同时建连，需加深队列（另轮）。 |
| M5 | **TX 队头阻塞（共享单帧器）**：一条零窗/死连接可挡住其余 7 条（H1-b 同族）。**未修**；登记为产品语义边界，与 H2 一并待裁定。若要求隔离，需每连接独立帧器/缓冲（大改）。 |
| M6 | `tcp_echo` 的 cq（128 深）对短段可静默丢 cid；data/tid 两 FIFO 对齐此前未被验证。**未修**；需真 `tcp_echo` 背靠背多 tid 短段测试（另轮）。 |
| M7 | 8 实例同 SEED ⇒ 内容级串扰不可判。**未修**；建议下一轮 per-instance `SEED ^ i` + 工具匹配（`p7b_pattern.h` 加 seed 参数）。本轮 TB 用逐 tid 输出/层级 mismatch 断言，仍能抓 demux 错路由。 |
| M8 | 新工具 `p7b_tcp_sink_multi`：**SO_RCVBUF 必须在 connect 前**（已记 TODO，未改源码）；默认 UNPINNED（速率只作形态）；默认跑 ~109 ms 偏短（板级脚本用 256MB/conn）。 |
| M9 | **方向订正**：12KB 是板→对端通告的**接收**窗；下行（板→PC）发送窗由对端 rcvbuf 决定，不受 12KB 限制。B6 的"单连接 ≤5 Gbps"只适用于**上行**；下行判据 = 聚合 ≥8 Gbps + 帧级公平。 |
| M10 | W63/W64/W71..W74 在 APP8 下语义变化（聚合；W64 含仲裁等待；`stat_up_pend` 结构性 0）⇒ 不与历史读数直接比较，窗口表注释待更新。 |
| M11 | `sw_pend` 不因 ev_down 清（P-2 继承风险）；8 实例/频繁 churn 下需关闭后重连用例（D2 只做了 ev_down，不做同槽 ev_up）。 |
| M12 | `P7B_MODULE_RESOLVE` 未包含 4 个新件（import 已加，但"缺文件=黑盒"硬门未覆盖）⇒ 构建前补。top5 CDC 槽不变（NW 97）。 |
| M13 | wrapper 级 TB 直接引用 `u_dut.u_app.*`（`tb_p5_wrapper` / `tb_p5_orphan_wrapper` / `tb_p6e_pcie_wrapper`）⇒ **APP8 宏下不可复用**；需独立 wrapper 门（未做）。 |
| L8 | 新 TB **未入 41 门矩阵** ⇒ "矩阵全绿"对本刀是空证据；需作为第 42 门登记（矩阵 manifest + runner）。 |

---

## 低（登记）

L1 资源估算偏低（实测 `u_app` 15,328 LUT，因 8 实例各 1,588–2,166）；L2 `stat_arb_switch` vs `stat_arb_frames` 命名；L3 "8.6 µs < BDP" 比较对象不当（改为轮询延迟）；L4 `dbg_winq0/dbg_pool/0x0C` 在 EXT_QUOTA=1 下不是合同见证；L5 0x34a 回落 BID 未定义；L6 `EXPECTED_CONNS` 整数除法需整除校验；L7 retx 8 槽 ×64KB 刚好装 `WIN_CAP`，无余量。

---

## 裁定请求（H2 / H6 / M5）

**问题**：8×12KB 合同的**接收方向**当前被"全口占用"扣减：`fq_i = winq_i − occ_global`，
任何连接的数据一进共享 echo FIFO，所有连接的窗同时缩小；occ ≥ 12KB 时 8 条窗全 0。
`win_pool_mgr` 的授予也减去 `occ_global`。纯下行测试（对端不发载荷）occ=0，因此**本轮下行判据
不受影响**，但"8 连接可接收/双向"不成立。

**选项**：
- **A（推荐，正确产品语义）**：加 **per-connection occupancy**（`tcp_echo` 按 `meta_conn_id`
  记写/读字节，含 rollback；`app_ctrl`/`win_pool_mgr` 用 `occ_i`）⇒ 8 条窗各自 = 12KB − 本连接占用；
  物理界由 `Σwinq + N*ACC_MARGIN` 保证（310 B 余量）。改动面 = `tcp_echo`/`app_ctrl`/`win_pool_mgr`
  + 多连接 TB + 上行板级臂；默认参数关 ⇒ 单连接/2 连接行为可保持逐位。
- **B（分级交付）**：0x34 只做**下行 8 连接**（内容/公平/聚合吞吐），接收方向与 12KB 合同
  明确写"未验证/不成立"，H2/H6 留到下一轮。构建与板级可先做，但报告不得称"8×12KB 合同已验证"。
- **C（暂停）**：不构建；先完成 A 的设计审查再实施。

**用户裁定前，本轮不进行 0x34 全构建/烧板。**
