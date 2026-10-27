# P11 APP8 每连接接收占用 — v6 终版施工依据

- 日期：2026-10-28
- 审查件 = `REVIEW_V5.md`（独立只读 agent；判决 = **附条件可实现**，F1–F8 先改）
- **本 v6 覆盖 v3/v4/v5 正文与表中所有冲突处**（`DESIGN_OCC.md` 的 v3 §2.1/§3.1/§5.1/§7 按 v6 读）：
  - 8 位 `cur_words/rb_words` → **14 位**；
  - `fq ≤ 127` → **`fq ≤ 126`**；
  - “judged && cq_full 保持 tready 低直到有空间” → **删除**（不可实现；只留计数 + 断言）；
  - “Σwinq + occ_port ≤ WIN_POOL 逐拍不变量” → **只在 grant/释放事件时刻成立**；安全靠静态预算 + F6 量化；
  - 板级“1B 探针” → **默认删除**，主见证改为 **板→对端连续数据帧的 window 字段**（F9）；探针仅在需要时作兜底。
- 状态：【设计 v6·待施工】【未实施】【未构建】【未上板】；F1–F8 全部落实后才构建。

---

## v6.0 F1–F20 处置表

| # | 处置 |
|---|---|
| **F1** | **前置 RTL 修复（合同阻断项）**：`rtl/slow_cfg_adp.v` 加参数 `RCV_WND_INIT`（默认 `16'hC000`），`tcb_val_c` 的 `rcv_wnd` 用它；wrapper 两处例化传 `RCV_WND_INIT_5` = `P11_HLS_ADV_WND ? WQ_CAP_5 : 16'hC000`。2×48KB/非 c4 构建零回归（0xC000），0x34/0x35 = 12KB。TB 加“ev_up 后首帧/TCB window == WQ_CAP”断言。 |
| **F2** | `cur_words/rb_words` **14 位**；`cw_n` 14 位；`8*rb_words` 18 位；每项 delta **20 位有符号**；内部 occ 18 位；输出饱和 17 位（131,071）。 |
| **F3** | 板级前件改 **`W62 ≥ 12,288`**；记录 `W62` 上界（conn0 臂期望 ≤ `12,288 + ACC_MARGIN + 字填充`，实测登记，不预设硬上限）。**conn0 的板侧 window == 0 是硬正控**；不成立 ⇒ 整轮不可判。 |
| **F4** | 见证过滤：板→对端、`tcp.flags.syn==0`、时间 > 停读写入、4-tuple 精确；取停读 + **一整轮扫描（256 拍）** 之后的帧；**不取第一条 ACK**。 |
| **F5** | **occ 读口预流水（v6 终版）**：`tcp_echo` 内 `occ_rd_q <= occ[i_occ_rd_id]; occ_id_q <= i_occ_rd_id;`（每拍），输出 `o_occ_rd`/`o_occ_rd_id`。app_ctrl 的 fq 路径深度**不变**（用 occ 寄存器替换原 `rx_occ_bytes` 寄存器）：`fq_scan = fq_calc(winq_q_scan, occ_fq)`，`occ_fq = PER_CONN_OCC ? i_occ_rd : rx_occ_bytes`。扫描 tick 加 **id 匹配门** `(i_occ_rd_id == scan_id)`；不匹配则**跳过该 tick**（scan_id 不推进；下一 tick 16 拍后重采）。init 的 done 拍上 init_valid 已持续 ≥3 拍 ⇒ 寄存 id 必为 init_head，**结构匹配**（TB 断言）；init 的 winq 仍取组合 `i_winq_rd`（grant 在 done 拍才可见）。1 拍 occ staleness ≤ 8 B（ACC_MARGIN 3328 内；与 F6 一并登记）。16 路 RMW 用共享 delta + 16 路二选一。构建前定向 STA 门：`occ[*]` RMW 锥、`occ_rd_q/qid` 锥、`fq_scan → redge_n → pa_redge_n` 锥；若新增锥 slack < 0.300 ns ⇒ 按 v6.5 备份方案再构建（**不重跑到过**）。 |
| **F6** | **本设计不声称“8×12KB 物理安全已证”**。310 B 是 P3 静态预算；fc 从 T+2 挂请求到最低优先级 TCB 落地的 X 未量化（10G 下可能 KB 级），per-conn 设计**不新增**该项、也不修复它。处置 = ① 板上 8 连接上行臂测 `W62` 峰值/重传/丢帧（见 v6.6）；② `stat_fc_wait_max`（0x9D）当前**未接快照**（`wrapper_p4.v:3315` 仅 port1 悬空）⇒ 记入 `P7B_OPEN_ITEMS.md`；③ 报告只写“在观测到的 W62/重传范围内成立”，不写“物理界已证明”。 |
| **F7** | O6 终版：① 逐拍 `occ_port ≤ 130,762`、`Σwinq ≤ WIN_POOL`；② `S_COMMIT` 断言 `pool_after ≥ occ_live − 16`（commit 时实时 occ；16 B = 2 拍×8B 采样误差）+ `Σwinq + pool == WIN_POOL`（有牙）；**删**“Σwinq_after + s_occ ≤ WIN_POOL”（恒等式）。报告不得写“等价旧 O6”。 |
| **F8** | 删除“保持 tready 低”；只留 `if (judged && cq_full) stat_cq_ovf <= +1`；TB `assert(fq<=126)`；构造不可达靠帧首门（v6.2 证明）。 |
| **F9** | 板级主见证 = **板→对端连续数据帧**（8 个 app 都是 `TX_CONTINUOUS=1`）的 window 字段；探针默认不做。若做探针：只发该连接图案首字节（1 B），并单列 `ΔW54` 口径，不与“ΔW54=0”混判。 |
| **F10** | build tcl：默认 `P11_APP8_OCC=0`（**所有构建都定义**）；`P11_APP8_OCC=1` 时若 `!P11_APP8_ON || !P11_IS_DUAL` ⇒ 打印 `P11_APP8_OCC_REQUIRES_APP8_C4` + `P7B_VERDICT` + `exit 1`。wrapper 用宏值 `.PER_CONN_OCC(\`P11_APP8_OCC)`（不用 `ifdef`）。 |
| **F11** | §7 增：**短段洪泛 + app 停读 ⇒ 全口 RX HOL / MAC 丢帧（靠 TCP 重传）**；与 TX HOL 对称；测试中允许重传，不判“丢帧=缺陷”。 |
| **F12** | O 表按 v6.7 重写（含 `!rback` 与门阈值 `CQ_DEPTH-2→CQ_DEPTH` 两个变异；O3/O4 新断言；`fq≤126`）。 |
| **F13** | 接受：板上无 occ 记账快照；**记账精确性只在 TB 层有判据**；报告明写。0x36 可选加 1–2 字（occ[0]/Σocc + 两错误计数，96 FF/字）。 |
| **F14** | §7-1 改：“建连时本口有占用 ⇒ 新连接配额可能 <12KB，**可为 0**；EXT_QUOTA=1 无 C15 补授 ⇒ **0 配额不自动恢复，产品需重连**。” |
| **F15** | 本 v6 为终版；施工者只读 v6 + v6.2/v6.5 代码块。 |
| **F16** | 中间和 20 位有符号；内部 18 位；输出 17 位饱和。 |
| **F17** | `fq ≤ 126`；等待 = **一整轮（256 拍，含 16 槽×16 拍）**，不是 256 拍/槽。 |
| **F18** | §7 增：`occ_i` 只保证属于**本口 echo 的该槽**；跨口槽的 fq/redge 无意义；fc/wu 有 ST_ESTAB 门；`redge` 无 state 门是既存风险（不改）；TB 加 port0 扫 port1 槽用例（期望零 fc/wu 写）。 |
| **F19** | 0x34/0x35 的 tready 门只在 OCC=1 支（零回归优先）；**报告/板级判据明写“两臂差 = occ + tready 门”**；干净板级测无坏帧/cq 满，判别力不受影响。 |
| **F20** | 全部用 `generate` 分支；0x34 的默认 `s_axis_tready` 恰为 `!fifo_full`；默认臂显式接 0；施工记录列出 v6.8 例化点清单。 |

---

## v6.1 最终模型（不变）

- `occ_i` = 连接 i 在本口 echo FIFO 中未消费的**物理字数×8**（含 tkeep<8 与合成尾字）。
- 通告窗 `fq_i = max(0, winq_i − occ_i)`；`win_pool_mgr` **零改动**（`avail = pool + old − occ_port`，孤儿/授予折扣保留）。
- 物理安全 = P3 静态预算 `Σwinq 98,304 + 8×3328 + 2,816 + 1,518 + 1,500 = 130,762 ≤ 131,072`（余 310 B）；
  **F6 的 fc 过通告 X 未覆盖**，不写“已证明”。

---

## v6.2 tcp_echo 终版代码规格（PER_CONN_OCC=1）

```verilog
localparam integer CQ_DEPTH = 1 << CQ_AW;

generate if (PER_CONN_OCC) begin : g_occ
  // tready：帧首门 + 回卷写保护
  assign s_axis_tready = !fifo_full && !rback &&
                         (!first_b || (fq < CQ_DEPTH - 2));   // start fq<=125 => post-push <=126

  reg [17:0] occ [0:15];
  reg [3:0]  cur_cid, rb_cid, occ_id_q;
  reg [13:0] cur_words, rb_words;
  reg [17:0] occ_rd_q;
  wire [3:0]  cid_w = first_b ? meta_conn_id : cur_cid;
  wire [13:0] cw_n  = first_b ? 14'd1 : cur_words + 14'd1;
  wire        wr_ev = accept;          // == frame_fifo.wr; accept => wr_ok
  wire        rd_ev = fwd_rd;          // == frame_fifo.rd (m_axis_tvalid includes !empty)
  wire        rb_ev = rback;           // frame_fifo.rollback same edge
  wire [3:0]  rd_cid = cq_dout;        // FWFT head, stable inside frame

  integer k;
  reg signed [19:0] delta_k;
  reg signed [19:0] sum_k;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cur_cid<=0; cur_words<=0; rb_cid<=0; rb_words<=0;
      occ_rd_q<=0; occ_id_q<=0; stat_occ_underflow<=0; stat_cq_ovf<=0;
      for (k=0;k<16;k=k+1) occ[k]<=0;
    end else begin
      if (accept && first_b) cur_cid <= meta_conn_id;
      if (accept) begin
        if (judged) cur_words <= 14'd0;
        else        cur_words <= cw_n;
      end
      if (judged) begin rb_cid <= cid_w; rb_words <= cw_n; end
      if (judged && cq_full) stat_cq_ovf <= stat_cq_ovf + 32'd1;
      for (k=0;k<16;k=k+1) begin
        delta_k = 20'sd0;
        if (wr_ev && (cid_w  == k[3:0])) delta_k = delta_k + 20'sd8;
        if (rd_ev && (rd_cid == k[3:0])) delta_k = delta_k - 20'sd8;
        if (rb_ev && (rb_cid == k[3:0])) delta_k = delta_k - (20'sd8 * $signed({1'b0, rb_words}));
        sum_k = $signed({2'b0, occ[k]}) + delta_k;
        if (sum_k < 20'sd0) begin
          occ[k] <= 18'd0;
          stat_occ_underflow <= stat_occ_underflow + 32'd1;
        end else if (sum_k > 20'sd262143) begin
          occ[k] <= 18'h3FFFF;
        end else begin
          occ[k] <= sum_k[17:0];
        end
      end
      occ_rd_q <= occ[i_occ_rd_id];
      occ_id_q <= i_occ_rd_id;
    end
  end
  assign o_occ_rd    = occ_rd_q[17] ? 17'h1FFFF : occ_rd_q[16:0];
  assign o_occ_rd_id = occ_id_q;
end else begin : g_noocc
  assign s_axis_tready = !fifo_full;          // 与 0x34 逐位等价
  assign o_occ_rd = 17'd0;
  assign o_occ_rd_id = 4'd0;
  assign stat_occ_underflow = 32'd0;
  assign stat_cq_ovf = 32'd0;
end endgenerate
```

- **主判据（TB）**：逐拍 `Σ occ_i == (fifo_wptr − fifo_rptr) << 3`（全宽求和，≥20 位）；
  同时逐 tid 参考模型（防“全记 conn0”也能满足求和）；`stat_occ_underflow == 0`。
- 回卷拍写保护：`!rback` 必须存在（`frame_fifo.v:258-259` rollback 优先于写；无此门则该拍写被静默丢）。
- cq 门证明：同一时刻仅一帧在飞；帧首 fq≤125；帧内无新 push；judged 后 fq≤126 < CQ_DEPTH=128。
  正常路径 `judged && cq_full` 不可达；防御只计数，**不拉 tready**。

---

## v6.3 app_ctrl 终版（PER_CONN_OCC=1）

```verilog
// 新参数 PER_CONN_OCC；新输入 i_occ_rd[16:0]、i_occ_rd_id[3:0]
wire [16:0] occ_fq = PER_CONN_OCC ? i_occ_rd : rx_occ_bytes;

// 扫描：tick 加 id 匹配（不匹配则跳过；scan_id 不推进）
//   scan_tick_g = scan_tick && !init_valid && (!PER_CONN_OCC || (i_occ_rd_id == scan_id)) && ...
wire [16:0] fq_scan = fq_calc(winq_q_scan, occ_fq);
wire [31:0] redge_n = rc_rcv_nxt + {15'b0, fq_scan};

// init redge / fc：init_valid 已持续 >=3 拍 => occ_id_q == init_head（TB 断言）
redge[init_head] <= redge_calc(winq_q_init, rc_rcv_nxt, occ_fq);
fc_wq[init_head] <= fq_calc(winq_q_init, occ_fq);

// T+2 fc 仍用 pb_wscan（不加 occ_pb）
```

- `occ_fq` 是**寄存器**（tcp_echo 的 occ_rd_q）；fq 路径深度与现役 `fq_calc(winq, rx_occ_bytes)` 相同。
- init 的 `winq_q_init` 必须保持**组合**（grant 在 done 拍才可见，延一拍读旧值 0 ⇒ 零窗死锁）。
- 扫描 id 不匹配只可能发生在 init→scan 交接的第一拍；跳过该 tick 无害（下一 tick 16 拍后）。

---

## v6.4 wrapper / 开关 / 几何

- `P11_APP8_OCC`：所有构建定义（0/1）；`.PER_CONN_OCC(\`P11_APP8_OCC)`。
- 0x34 = `P11_APP8=1, P11_APP8_OCC=0`（负对照臂；含 F1 慢路径窗口修复 + RX stall 钩子）；
  0x35 = `P11_APP8=1, P11_APP8_OCC=1`（修复臂）。**先 0x34 构建/归档，再 0x35**。
- `win_pool_mgr` 零改动；快照 **NW 97 不变**；BID 0x34/0x35 逐构建 bump。
- RX stall：`app_rx_tvalid = eco2_tvalid && !stall` **且** `eco2_tready = app_rx_tready && !stall`；
  `app_rx_stall = (PCIE_OBS && P11_APP8) ? stall_sr[1] : 1'b0`；`pcie_scratch[2]` → dp_clk 2FF；
  `0x08` 写必须显式 bits[31:2]=0；停读期 `0x08` 读回 0x4，身份脚本改用 carrier 作 TX 见证。
- F1：slow_cfg_adp `RCV_WND_INIT`（默认 0xC000）；wrapper 传 `RCV_WND_INIT_5`（c4=WQ_CAP_5，其他 0xC000）。

---

## v6.5 时序预检与备份

- 构建前（synth 后、impl 前）定向 STA：
  ① `occ[*]/D`（16 路 RMW）；
  ② `occ_rd_q/qid`；
  ③ `occ_fq → fq_scan → redge_n → pa_redge_n`；
  ④ `s_axis_tready` 的 7 位比较。
- 若新增锥 slack < 0.300 ns ⇒ 启用备份（**新输入，不重跑到过**）：扫描路寄存
  `{pa_sid, pa_winq, pa_occ, pa_rcv_nxt, pa_rwnd, pa_state}` 一拍，fq/redge 在 T+1 计算，
  redge/pb 顺延一拍；事件让位窗延长一拍（ev1/ev2）。此方案需另写门，**默认不启用**。
- 构建策略预登记 `Performance_ExtraTimingOpt`（0x33 通过臂；作为新输入）。
- ⭐ **2026-10-28 实测登记（策略/布局实验）**：
  | 构建 | 策略 / 布局 | WNS | setup 端点 | 结论 |
  |---|---|---|---|---|
  | 0x33 | Extra（通过臂） | +0.008 | 0 | 基线 |
  | 0x34 #2 | ExtraTimingOpt | −0.337 | 6,642 | 8×app 进 DP ⇒ 拥塞 |
  | 0x34 #3 | Extra + `u_app` pblock | **−0.644** | **13,282** | **否定**（压小布局 + 与 DP 争区） |
  | 0x34 #4 | `Congestion_SpreadLogic_high`（无 pblock；落为 `AltSpreadLogic_high`） | **−0.205** | **5,162** | 改善但仍 FAIL；最差族换到 `u_tcp_tx/bank_rdy → app/tcb CE` |
  | 0x34 #5 | `Performance_NetDelay_high`（无 pblock） | 待判 | 待判 | 新输入（构建在飞） |
  - pblock 文件保留为**可复跑负实验**，构建脚本默认关闭（`P11_APP8_PBLOCK=1` 才启用）。
  - 结构结论：0x33→0x34 的边际 ≈ **0.345 ns / 7 个额外 app** ⇒ 余量问题不是布局能补的；
    下一轮首选 = **8×app 组独立 156.25 MHz 域 + AXIS CDC**，次选 = app 图案逻辑降面积/共享
    （两者均需独立设计 + 审查，未实施）。

---

## v6.6 板级协议（终版；主见证 = 连续下行帧的 window）

**工具**：`p7b_tcp_sink_multi` 增 `--send-conns N` / `--send-bytes B` / `--send-pattern`
（每连接从偏移 0 xorshift；conn0 臂 16,384 B；8 连接臂 12,288 B/连接）；
`SO_RCVBUF` 必须在 **connect 之前**；8 线程 send+recv 非阻塞；输出 `MULTI_SEND/MULTI_SUM`。
- **⭐ 端口映射（2026-10-28 现核，必须先钉死）**：8×12KB/多连接 app 在 **RTL port0**
  = `u_app`(app_multi8)/`u_tcp_echo`/`u_app_ctrl` = **SFP A(J7) = ch0 = 板 IP 192.168.100.4**（`IP_B_5`）；
  从对端 **nsb `enp1s0f0np0` = 192.168.100.101/32** 发（`b0_env_setup.sh:3-4` 的 IP_B/J7/ch0）。
  板 **port1(J8) = ch1 = 板 IP 192.168.100.2**（`IP_A_5`）= 对端 **nsa `enp1s0f1np1` = 192.168.100.1/32**，
  那里只有单 app `q1_app` —— **8 连接测试绝不能打到 nsa**（8 连接必失败）。
  ⚠️ **地址归属别读反**：`.101`/`.1` 是对端两个口，`.4`/`.2` 是板上两个口的 IP。
  `0x08 bit2` 的 RX 停读只门 **port0 app**（`app_rx_*` = `eco2_*`），正对应 8+0。
- `sent=` = 内核已接受；`unsent=` = `SIOCOUTQNSD`；**线上字节 = sent − unsent**。
  conn0 臂的 16,384 B 可能只上线 ~12KB（板窗关）——这是设计预期，不记为失败；
  8 连接上行臂的 12,288 B/连接应全部上线（`unsent≈0`）。
- 每连接 `lport=` 进输出：tcpdump 的 4-tuple 对账靠它定位"哪条是发送 conn"。

1. 0x34 构建/归档；0x35 构建。8 条连接**全部 connect() 返回后**才 send（grant 折扣前件）。
2. 身份：BID / NW 97 / 未实现 0x1B4 / 2 BAR / x4 / carrier 1/1；`0x08=0`。
3. `0x08=0x4`（RX_STALL，bits0/1=0 保 TX）；PC 只在 conn0 发 16,384 B（非阻塞；窗口可能提前关）；
   持续收下行（8 线程）。
4. 等 `W62 ≥ 12,288`，再等**一整轮扫描 256 拍**；记录 W62 序列。
5. **主见证**：tcpdump 抓板→对端、8 个 4-tuple 的**连续下行数据帧**（`syn==0`，时间 > 停读；
   每连接取停读后 ≥ N 帧的 `tcp.window`）：
   - 0x34：conn1..7 的 win → 0（全局 occ 扣）；
   - 0x35：conn1..7 的 win ≈ 12KB（per-conn occ）；conn0 两臂都 ≈0（硬正控）。
6. 清 `0x08=0`，排空；**8 连接上行臂**（app 活跃）：8 条各发 12,288 B 图案，记录
   `W62` 峰值 / `ΔW53==PC 发送字节` / `ΔW54=0` / `W55`（重传）/ 各连接窗。
7. 第 9 条 SYN：HLS `stat_no_slot` 增、无 RST 风暴；下行 8 连接回归（`mism=0`）。
8. 前件（W62≥12,288）不满足 / conn0 正控不为 0 ⇒ **【空判据/未执行】，不记 PASS**。
9. 报告明写：0x34 不是“现役 0x33”；两臂差 = occ + tready 门；记账精确性只在 TB 层；
   F6 的物理安全只按实测 W62/重传范围表述。

---

## v6.7 测试终版（O1–O11 + 变异）

| # | 判据 |
|---|---|
| O1 | 2 tid 交错（长帧 + 1B 短段）：逐拍 `occ_i` = 参考模型；同槽同拍读写净额 0；另一 tid 不受影响；**逐拍 `Σocc == (wptr−rptr)<<3`** |
| O2 | 单字/多字坏帧各一（紧跟 1–2B 好帧 + 反压恢复）：回卷后 occ 精确相等；**末字计入 rb_words**；无下溢；单字帧 cid 正确 |
| O3 | 128×1B 好帧 + app 停读 ⇒ 放行：app 实收 == tcp_rx 接受；`stat_cq_ovf=0`；**逐拍 `fq ≤ 126`**；门关闭周期 >0 |
| O4 | `fq=126` 时新帧 tready 低；app 排空后恢复；无死锁；门关闭时 `stat_cq_ovf` 恒 0 |
| O5 | app_ctrl：仅槽 2 occ=12KB ⇒ 槽 2 fq=0、其它 12KB；occ=6KB ⇒ 6KB；**init 拍 occ_id == init_head**；扫描 id 失配跳过一拍后恢复 |
| O6 | ① 逐拍 `occ_port ≤ 130,762`、`Σwinq ≤ WIN_POOL`；② `S_COMMIT: pool_after ≥ occ_live − 16` + `Σwinq+pool==WIN_POOL`；含 ev_up/ev_down/churn |
| O7 | win_pool_mgr 与 0x34 逐位相同（未改）；C18 同槽复用仍正确；**C15 在 EXT_QUOTA=1 关闭 ⇒ 0 配额不恢复** |
| O8 | `PER_CONN_OCC=0` 折叠：0x34 TB/位流等价锚；`s_axis_tready == !fifo_full` |
| O9 | 变异门（每个必须红）：① occ 用全局；② `rb_words<=cur_words`（少末字）；③ 删帧边界门；④ `rb_cid<=cur_cid`（单字帧）；⑤ 读侧不扣 occ；⑥ `s_axis_tready` 漏 `!rback`；⑦ 门阈值 `CQ_DEPTH-2→CQ_DEPTH` |
| O10 | **F1**：ev_up 后首帧/TCB `rcv_wnd == WQ_CAP`（0x34/0x35 c4；非 c4 = 0xC000）；F1 变异（写死 0xC000）必须红 |
| O11 | **跨口**：port0 app_ctrl 扫到 port1 槽 ⇒ 零 fc/wu 写；`redge` 污染登记（不改） |

- 新门登记进常驻矩阵（第 42/43 门；manifest/runner 同步）；矩阵的 `tb_biz_win` BID 逐构建同步。

---

## v6.8 例化点清单（施工时逐条核）

- `tcp_echo`：`board/wrapper_p4.v:2558`、`:3136`；TB `tb/tb_tcp_echo.v:199`、`tb/tb_p5_multi.v:509`、
  `tb/tb_p5_app.v:401`、`tb/tb_p5_adv.v:368`、`tb/tb_p4_chain.v:718`、`sim/p5e_pre/tb_p5_udp_split.v:489`、
  `sim/p5e_pre/tb_p5_baseline.v:398`、`sim/p5b_adv/tb_p5_app_wnd.v:325`。
- `app_ctrl`：`board/wrapper_p4.v:1852`、`:3269`；TB `tb/tb_app_orphan.v:113`、`tb/tb_app_fc.v:137`、
  `tb/tb_app_wu.v:104,132`、`tb/tb_p5_multi.v:644`、`tb/tb_p5_app.v:949`、`tb/tb_p5_adv.v:503`、
  `tb/tb_wu_p1p2.v:95,151`、`tb/tb_wu_f2.v:105`、`sim/p5c_t3/rev/tb_rev_g2g3.v:119`、
  `sim/p5b_adv/tb_p5_app_wnd.v:832`、`sim/p5b_adv/tb_p5b_ind.v:71`、`sim/p5wu_review/tb_wu_review.v:95,123`、
  `sim/p5wu_p1p2_review/tb_rev_p2_gate.v:74`、`sim/p5wu_p1p2_review/tb_rev_p1_winq0.v:204`、
  `sim/p5e_pre/tb_p5_udp_split.v:1035`、`sim/p5e_pre/tb_p5_baseline.v:944`。
- `slow_cfg_adp`：`board/wrapper_p4.v:2767`、`:3789`（传 `RCV_WND_INIT`）；TB 不传 = 默认 0xC000。

---

## v6.9 仍未解决 / 登记（不阻断 v6 施工，但不许写成“已证”）

1. **F6 fc 过通告 X**：10G/8 连接下未量化；310 B 静态余量可能不够；板级 8 连接上行臂只给观测，不是证明。
2. **F13 记账快照**：板上无 occ/下溢/溢出计数；精确性只在 TB。
3. **F14 0 配额不自动恢复**：EXT_QUOTA=1 关闭 C15；产品需重连。
4. **F18 跨口 redge 污染**：既存、无功能写；登记。
5. **F19 两臂差**：occ + tready 门；干净板级测不受影响。
6. 授权顺序：**0x34 先构建/归档，再 0x35**；0x34 构建若 `P7B_TIMING_GATE` 失败 ⇒ 不烧、归档、登记，
   0x35 不同批；0x34 的 synth 检查点 142k LUT 已登记，不作为停止条件。
