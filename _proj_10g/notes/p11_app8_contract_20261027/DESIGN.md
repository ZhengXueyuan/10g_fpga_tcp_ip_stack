# P11-APP8：8×12KB 合同 + 8 连接 app（0x34 候选）设计件

- 日期：2026-10-27
- 基线：HEAD `f986acf1`（E1a-1 收口；板 = 0x33 / NW 97）
- 目标：产品档 **8 连接 × 12KB 配额**（96KB 共享池）+ **8 连接数据面 app**（port0 8+0）
- 状态词：【设计】【已实施（RTL+TB）】【TB_APP8_PASS】【未构建】【未上板】

---

## 0. 一页结论

| 项 | 方案 |
|---|---|
| 合同 | `P11_EXPECTED_CONNS 2→8` ⇒ `WQ_CAP_5 = 96KB/8 = 0x3000`；HLS `i_tcp_adv_wnd` 同值（已在 C4 接线） |
| app | **8 × `app_pattern` 实例**（逐字复用，不改既有模块）+ 新 **`app_multi8.v`**（TX 帧级轮询仲裁 + RX 按 tid 分发 + close 申请队列） |
| 零回归 | 新宏 `P11_APP8`（默认未定义 ⇒ wrapper 走原单实例路径，逐位不变） |
| 资源预算 | 实测 `u_app` = **1,388 LUT / 765 FF**（routed dcp 层次报告）⇒ 8 实例 ≈ **11.1k LUT / 6.1k FF**；净增 ≈ **+9.7k LUT / +5.4k FF**（替换 1 实例） |
| 时序 | 0x33 WNS 仅 **+0.008**（0.125%）⇒ **先 synth 检查点**，再决定是否全构建 |
| BID | **0x34**（0x33 已被 E1a-1 占用） |
| 判据 | 单元 TB（8 连接、帧级公平、无跨帧切换、RX 无串扰、close 不丢）→ synth 检查点 → 全构建门 → 板级 8 并发连接 |

---

## 1. 合同：8×12KB

### 1.1 改动

`board/wrapper_p4.v`：

```verilog
localparam integer P11_EXPECTED_CONNS = 8;   // 2 -> 8 (产品档 8x12KB)
localparam [16:0] WIN_POOL_5 = 17'h18000;    // 96KB 不变
localparam [15:0] WQ_CAP_5   = WIN_POOL_5 / P11_EXPECTED_CONNS;  // 0x3000
```

- HLS `i_tcp_adv_wnd (WQ_CAP_5)` 已在 `P11_HLS_ADV_WND` 下接线（`wrapper_p4.v:3877-3878`）⇒
  SYN-ACK 通告窗 = 12KB，与 fast-path 配额一致。
- `win_pool_mgr` 的 `wq_cap` 输入同源 ⇒ 每连接授予 12KB；`PORT_CAP = 96KB` 允许 8+0。
- `app_ctrl.wq_cap_r`（寄存器 0x0C，板级无 CPU ⇒ 保持 `WIN_Q_MAX=0xC000`）在 `EXT_QUOTA=1`
  下**不参与** winq/授权（所有写点被 `!EXT_QUOTA` 旁路，`wcalc` 无调用点）⇒ 不需要 boot writer。
  ⚠️ 该结论需在实施轮用门复核（静态断言 + synth 后逻辑锥检查）。

### 1.2 合同边界（必须写进板级判据）

1. **retx 槽只有 8 个**（`retx_pool_shared.v`：`r_conn < 8`，超出计 `stat_slot_oor`），
   而 HLS `MAX_TCP_CONN=8` + 空闲槽分配 ⇒ 前 8 条连接的 cid ∈ 0..7 ⇒ 对齐。
   **第 9 条连接**：HLS 无空闲槽 ⇒ SYN 静默丢弃（`stat_no_slot++`），不是 RST。
2. **每口 128KB echo**（C4 已实现，`tcp_echo D=16384/AW=14`）：8×12KB=96KB < 128KB，
   物理余量 = 26934 B（`wrapper_p4.v:1653-1662` 的预算式）。
3. **一个 bitstream 一个合同**（用户 2026-10-18 裁定）：本构建 `EXPECTED_CONNS=8`；
   2×48KB 合同仍是 0x31/0x33 归档位流，不混用。
4. **窗口 12KB 下的 BDP**：12,288 B / 10 Gbps ⇒ RTT 上限 ≈ **9.83 µs** 才不贴窗；
   实测 srtt 16–27 µs ⇒ 单连接会被窗口限速（≈ 12KB/20µs ≈ 4.9 Gbps/conn 上界）。
   8 连接共享 10G 线 ⇒ 聚合仍可打满。**这是产品语义（8×12KB），不是缺陷**。
5. **app_ctrl 的 `EXPECTED_CONNS` 不参与窗口计算**：运行时配额来自 `win_pool_mgr`，
   合同只影响 `wq_cap` 常量与 HLS 通告；`WIN_CAP_5=0xF000` 仍是 TCB 的单连接硬帽（不冲突）。

---

## 2. 多连接 app：架构

### 2.1 为什么不改 `app_pattern`

`app_pattern` 是**单会话**状态机（`active/act_id/pw_*` + closing/换流 + 图案流
`tx_lfsr/rx_lfsr` 各一份；`rtl/app_pattern.v` 头部与 P5d-D2/Stage C 语义）。把它改成 8 会话
需要重写装配/收尾/换流/图案复位，风险远高于复用。**8 个逐字实例**把新逻辑限制在一个
新模块内，且每个实例的会话语义保持已验证的状态机。

### 2.2 结构（实施 = 3 个可单测小模块 + 顶层）

```
            app_ctrl.ev_up/ev_down/ev_slot
                      │
        ┌─────────────┴─────────────┐
        │  事件按 ev_slot 过滤       │
        │  ev_up_i = ev_up && slot==i│
        └─────────────┬─────────────┘
                      ▼
   ┌──────┐ ┌──────┐ ... ┌──────┐        (i = 0..7)
   │app[0]│ │app[1]│     │app[7]│  app_pattern #(TX_CONTINUOUS=1, TX_SWCLOSE=1)
   └──┬───┘ └──┬───┘     └──┬───┘
      │ m_*    │            │
      └────────┴── TX 仲裁 ─┴────────► axis_pipe → tcp_tx_frame
                      ▲
              close_req 队列 (每实例脉冲 → pending 位 → 逐拍发出)

   tcp_echo ──► RX 分发（按 rx_tid 帧级锁存）──► app[i].rx_*
```

### 2.3 TX 仲裁（帧级、非抢占）

- 状态：`sel[2:0]`、`busy`、`rr[2:0]`。
- `!busy`：从 `rr` 起找第一个 `m_tvalid[i]`，锁存 `sel=i`、`busy=1`。
- `busy`：把 `m_tready` 只给 `sel`；其余实例 `m_tready=0`（它们会保持 valid/data）。
  当 `m_tvalid[sel] && m_tready && m_tlast[sel]`：`busy=0`、`rr=sel+1`。
- **不抢占**：即使其它实例更急，也等当前帧 tlast。理由 = 下游 `tcp_tx_frame` 只接受
  完整帧；中途换源会破坏 tid/载荷流。
- **不会卡死**：`app_pattern` 的 W3 收尾保证任何已开始的帧最终给出 tlast
  （有载荷 ⇒ 当前字带 tlast；无载荷 ⇒ 0 载荷 tlast；`app_pattern.v:912-940`）。
- 公平性：轮询指针保证 8 个持续源在每 8 帧窗口内各得 ≥1 帧；单帧 ≤193 拍
  ⇒ 最坏等待 ≈ 7×193 ≈ 1.35k 拍 ≈ 8.6 µs（< 12KB 窗口的 BDP 尺度）。

### 2.4 RX 分发（按 tid 帧级）

- 锁存 `cur_tid`：`!in_frame && rx_tvalid` 时取 `rx_tid`；`rx_tvalid && rx_tready && rx_tlast` 后清 `in_frame`。
- `rx_tvalid_i = rx_tvalid && (cur_tid == i)`；`rx_tready = |rx_tready_i`（被选实例的 ready）。
- `cur_tid >= 8`（理论不可达，HLS MAX=8）：**消费并丢弃**该帧（`rx_tready=1`），
  计 `stat_rx_orphan_frames/bytes`；不静默死锁。
- 每实例的 `rx_lfsr` 在各自 `ev_up` 复位；对端每连接从图案偏移 0 起 ⇒ 校验语义正确。
- 反压：一个实例检查慢会暂停整条流（与今天单实例语义相同），不会丢字。

### 2.5 close 申请

- 每实例 `close_req` 是单拍脉冲。`app_multi8` 用 8 位 `close_pend` 锁存，
  逐拍发出 `{close_req, close_id}`（轮询），发出后清位。
- 连续模式（`TX_CONTINUOUS=1`）下 `close_req` 结构性不产生（`remain` 重装），
  但队列仍实现（默认通用；未来有限长度模式可用）。
- 同时到达的 8 个 close 在 8 拍内全部发出；`app_ctrl` 每次只处理一个。

### 2.6 统计

- 聚合：`stat_tx_bytes/tx_frames/rx_bytes/mismatch` = 8 实例之和（32 位回卷，软件按 Δ 处理）。
- 新增观测（本模块输出；**本轮不进快照**，见 §2.7）：`stat_arb_frames`（帧级换源/发帧数）、
  `stat_rx_orphan_frames/bytes`、`stat_close_pend_max`、`dbg_inst_mismatch[N*32]`（TB 用）。
- 每实例的 `active/closing` 不上快照；板级用聚合（W51..W54）+ PC 端逐连接计数。

### 2.7 快照几何（本轮**不新增**字）

- **NW 97 / 未实现 `0x1B4` 保持不变**；BID 只 bump 到 **0x34**。
- 理由：W51..W54 已经覆盖 `app_tx_bytes / app_tx_frames / app_rx_bytes / app_mismatch`
  （`p7b_snap.sh:158-159` 的标签表），8 实例聚合后语义不变 ⇒ 板级核心判据不需要新字；
  新增 `arb_frames / orphan_* / close_pend_max` 只在本模块/TB 观测（端口保留），
  避免 3 字 ×96 FF 与全部读侧地址链（NW 100 ⇒ MIR `0x1B0..0x1BC`）的连带风险。
- 若后续要板级归因仲裁/孤儿，另轮加字（届时 NW 100 / 未实现 `0x1C0`）。

---

## 3. 零回归与开关

- 新宏 `P11_APP8`（只在 `P11_CFG=c4` 且显式设置时定义；默认不定义）。
- wrapper：

```verilog
`ifdef P11_APP8
    app_multi8 #(...) u_app ( ... );   // 8 实例 + mux
`else
    app_pattern #(...) u_app ( ... );  // 现状，逐字不变
`endif
```

- `app_multi8` 内部例化 8 个 `app_pattern`，参数与现役 port0 一致：
  `TX_BYTES=32'h0FFFFFFF, TX_SEGSZ=1460, TX_CONTINUOUS=1, TX_TAILCARRY=0, TX_SWCLOSE=1`。
- `P11_APP8=0` 时 `app_multi8` 不参与编译（文件仍在 `rtl/`，不影响其它构建）。
- ⚠️ **不改变** `app_pattern.v` 一行（本轮零改动；避免动已验证模块）。

---

## 4. 资源 / 时序预算（纸面 + 实测锚）

- 实测（`wrapper_p4_routed.dcp` 的 `report_utilization -hierarchical`）：
  `u_app` = **1,388 LUT / 765 FF**；`u_app2` = 956 LUT / 293 FF；`u_app_ctrl` = 3,376 LUT / 3,201 FF。
  锚件 = `_proj_10g/notes/p11_app8_contract_20261027/util_hier.rpt`（本轮生成，见 §7）。
- 8 实例估算：LUT **8×1,388 ≈ 11.1k**（最坏按 port0 实例），FF **8×765 ≈ 6.1k**；
  替换现役 1 实例 ⇒ 净 **+9.7k LUT / +5.4k FF**（占 217k LUT 的 **4.5%**、434k FF 的 1.2%）。
- 仲裁/分发逻辑估算：64 位 8:1 mux + 控制 ≈ 300–600 LUT / 100 FF。
- 时序：0x33 WNS +0.008 = 0.125%。8 实例在 dp_clk 域，**可能**挤压布局。
  ⇒ **backstop：先 synth 检查点**（`synth_design` 后的 WNS 估计 + 逻辑级数），
  synth WNS < **−0.100** 或 LUT > **140k** ⇒ 停，回退到"合同-only"构建（0x34a），app 另轮。
- **synth 实测（2026-10-27）**：总 LUT **142,049 (65.5%)**、FF 108,743、`u_app` **15,328 LUT / 5,956 FF**；
  top-5 最差 **−0.706 / 23 级**（`u_tcp_tx2 FSM → u_app2/pw_data`，port1 现役 app，**不是新 8 实例**）。
  ⇒ synth slack 无判决力（0x33 通过臂 synth 也为负），**全构建 `P7B_TIMING_GATE` 才是判决**；
  构建策略预登记 `Performance_ExtraTimingOpt`（0x33 通过臂，新输入）。
- 若全构建 route 失败 ⇒ 按既有纪律不烧、归档、登记；不"重跑到过"。
- **审查 blocker**：H2（全口占用双重扣减）未裁定前**不构建/不烧**；见 `REVIEW_RESPONSE.md`。

---

## 5. 施工清单

1. `rtl/axis_frame_mux8.v`（新）：8→1 帧级轮询仲裁（不抢占；`m_tid` 帧内恒定）。
2. `rtl/axis_tid_demux8.v`（新）：1→8 按 tid 帧级分发；`tid>=8` 消费丢弃并计数。
3. `rtl/app_close_arb8.v`（新）：8 个单拍 close_req 锁存 + 逐拍发出，不丢。
4. `rtl/app_multi8.v`（新）：8×app_pattern + 上述三件 + 聚合统计（**不改 app_pattern**）。
5. `board/wrapper_p4.v`：
   - `P11_EXPECTED_CONNS` 2→8（合同）；`WQ_CAP_5 = 0x3000`；
   - `P11_APP8` 分支（port0 `u_app` 换 `app_multi8`；port1 不动；未定义时原路径逐字不变）；
   - **不加**快照字（NW 97 不变）；BID **0x34**。
6. `board/build_p7b_ku5p.tcl`：`P11_APP8=1` 只在 c4 时加入 define（否则硬失败）；
   新 RTL 加入 `import_files` 清单（**缺 = black box 静默**）。
7. TB：`tb_app_multi8.v`（A mux / B demux / C close / D 8 实例集成，已 **TB_APP8_PASS**）。
8. 构建：先 `P11_CFG=c4 P11_APP8=1 P11_STA_ONLY=1` 的 synth 检查点，通过后全构建 **0x34**。
9. 板级：8 并发连接（`p7b_tcp_sink_multi`），逐连接内容 + 窗口行为 + 第 9 条拒绝。

---

## 6. 板级测试载具（新 PC 工具）

现役 `p7b_tcp_sink` 是**逐连接串行**（`for c in conns: connect → drain → close`），
不能并发测 8 连接共享池。新工具 `_proj_pcie/p7b_biz/p7b_tcp_sink_multi.cpp`：

- 一次建立 N（默认 8）条连接（`SO_RCVBUF=1MB`、可选 `SO_MAX_PACING_RATE`）；
- `poll()` 多 fd，按连接读入并逐字节校验各自图案流（每连接 `P7bPat(0)`）；
- 每条连接达到 `--maxbytes` 或对端 FIN 后记录 `got/mism/first_mism`；全部结束或超时退出；
- 输出与 sink 同风格：`MULTI_CONN i ...` + `MULTI_SUM conns=... fail=... bytes=... mism=...`；
- 见证：`PIN_*` / `UNPINNED=1`（复用 `p7b_affinity.h`）、`--no-pin`；
- 判据：8/8 连接 `mism=0`、`first_mismatch=-1`、总字节 = 8×maxbytes（或按 FIN 截断）、
  板侧 `W52/W83` 与 PC 计数对账（±1 帧）。
- ⚠️ 不改现役 `p7b_tcp_sink.cpp`（它是对照臂）；新工具独立文件。

---

## 7. 判据（预注册，先写死）

### 7.1 单元门（必须全过）

| # | 判据 |
|---:|---|
| U1 | TX 帧级轮询：8 源持续 valid 时，连续 8 帧覆盖 8 个 tid（各 ≥1） |
| U2 | 不抢占：任何一帧内 `m_tid` 恒定、只在 tlast 后换源 |
| U3 | 单源撤 valid/慢：其余 7 源继续推进，不阻塞 |
| U4 | close 8 个同拍：8 个脉冲全部按序发出（8 拍内），无丢失 |
| U5 | RX 分发：8 tid 的帧各到各实例；注入 A 的错字只增 A 的 mismatch |
| U6 | tid=9 帧：被消费丢弃，`stat_rx_orphan_frames +1`，不阻塞后续合法帧 |
| U7 | 聚合统计 = 8 实例人工和；`stat_tx_frames` 与注入帧数一致 |

### 7.2 构建门（全部满足才可烧）

1. synth 检查点（`P11_STA_ONLY=1`）：synth LUT ≤ 140k、top-5 synth slack ≥ −0.100、无 blackbox；
2. 全构建：`P7B_TIMING_GATE=PASS`（WNS>0、setup/hold/PW 端点 0/0/0）、`P11_STA_TCB_GATE=PASS`、
   DRC 0 Error/Critical、`P7B_SNAP_TOP5_CDC` 槽 39..55、`P7B_VERDICT=OK`；
3. 矩阵 41 门 EXIT=0 + `p11_c4_elab` 的 P11_APP8 臂；
4. 位流 sha256 + BID 0x34 + NW 97 + 未实现 0x1B4 记录。

### 7.3 板级门（8 并发）

| # | 判据 |
|---:|---|
| B1 | 身份：BID 0x34 / NW 97 / `0x1B4=0xffffffff` / 2 BAR / x4 / `0x08=0` / carrier 1/1 |
| B2 | 8/8 连接建立；第 9 条 SYN 被丢弃（HLS 无槽），无 RST 风暴 |
| B3 | 8/8 连接 `mism=0`、`first_mismatch=-1`；总字节 = PC 计数（±1 帧） |
| B4 | 板侧 `ΔW52`（app 帧）与 PC 收帧对账 ≤1%；`ΔW83`（port0 帧）同理 |
| B5 | 每连接窗口行为：`W69` 不可用作判据；用 PC 侧 `ss -ti` 的 `rwnd`/`snd_wnd` 见证 12KB 配额 |
| B6 | 与 2×48KB 合同（0x33）对照：8×12KB 下单连接速率 ≤ ~5 Gbps（BDP 限制），聚合 ≥8 Gbps |
| B7 | 数据内容：逐连接图案流从偏移 0 起；跨连接无串扰（A 的失配不影响 B） |

---

## 8. backstop / 回退

| 情形 | 动作 |
|---|---|
| synth 检查点超预算（LUT>140k 或 WNS<−0.1） | 停；先出**合同-only 0x34a**（仅 `EXPECTED_CONNS=8`，app 不变），app 另轮 |
| 全构建时序 FAIL | 按纪律改名 `.TIMING_FAIL`、归档、不烧；合同-only 另行 |
| 单元门 FAIL | 修模块，不构建；不"重跑到过" |
| 板级 8 连接失败但单连接 OK | 记录为 app 缺陷；不烧回滚 0x33（产品合同构建仍有效，只是数据面未证） |

---

## 9. 风险

1. **时序**：8 实例 + mux 在 dp_clk；0x33 WNS 0.125%。synth 检查点是唯一低成本判据。
2. **仲裁公平性**：轮询是帧级；若某实例持续 193 拍/帧，最坏等待 8.6 µs，远小于窗口 BDP。
3. **RX 反压**：一个实例检查慢会暂停整条流（与单实例一致），不会丢字；但会拖慢其它连接，
   板级用 `mism=0` + 逐连接速率观察。
4. **合同语义**：12KB/条 ⇒ 单连接 ~4.9 Gbps 上限（RTT 20 µs），必须写进报告，不能拿
   "8 连接聚合 9G" 冒充"单连接 10G"。
5. **retx 8 槽**：只支持 cid 0..7；第 9 条被 HLS 拒。若将来 MAX_TCP_CONN>8，必须扩 retx。

---

## 10. 证据锚

- 层次资源：`_proj_10g/notes/p11_app8_contract_20261027/util_hier.rpt`
  （由 `wrapper_p4_routed.dcp` 生成；命令见 `util.tcl`）。
- 现役合同：`board/wrapper_p4.v:451-454`（EXPECTED_CONNS/WIN_POOL/WQ_CAP）。
- 本模块拆分与 TB：`rtl/axis_frame_mux8.v` / `axis_tid_demux8.v` / `app_close_arb8.v` /
  `app_multi8.v`；`tb_app_multi8.v` + `compile/xsim.log`（`TB_APP8_PASS`）。
- HLS adv_wnd 接线：`board/wrapper_p4.v:3877-3878`。
- app_ctrl 的 EXT_QUOTA 旁路：`rtl/app_ctrl.v:1224-1230/1273-1279/1392-1421/1466-1470`。
- W3 收尾保证 tlast：`rtl/app_pattern.v:912-940`。
- retx 8 槽：`rtl/retx_pool_shared.v:1-30`。
- sink 串行语义：`_proj_pcie/p7b_biz/p7b_tcp_sink.cpp:414-460`。
