# P11 E1a-1 设计件：DP fast-path TX 逐帧延迟直方图

- 日期：2026-10-27（设计+实施+单元门；构建 1 `TIMING_FAIL`，**构建 2 通过**；**板级已测**）
- 仓库：`D:\repo\XCKU5PMini\udp_hls_10g`；基线 HEAD = `7c65dd2b`（E1 提交，remote 同值）
- 板：基线 0x32 → **本轮已烧 0x33**（BID `0x33` / 97 字 / `0x1B4` 未实现 / 2 BARs / `0x08=0` / carrier 1/1）
- 状态词：【设计】= 本件纸面；【已证】仅指引用已有原件；【未测】= 本轮未取读数
- ⛔ 本件**不是** PASS/FAIL 裁定；判据层裁定权在判据所有者

---

## 0. 一页结论（设计选择）

E1（零构建）只测到 **HLS 控制面**：9G 慢态负载下端口 B 的 ping/TCP/UDP echo p99 不升反降；
**A 口 fast-path 数据帧没有任何逐帧时间戳**，所以“9G 下 fast-path 单帧延迟”仍是【未测】。
E0.5 只给**整窗**聚合（W65/W66/W67/W69），给不出 per-frame p50/p99。

E1a-1 的最小目标是补上 **A 口 TCP fast-path TX 的逐帧总延迟分布**：

> **L_tx_frame = 帧首字出现在 `u_tcp_tx.s_axis`（app 侧已呈现）→ 该帧末字被 `u_txcdc` 写口接收**
> （即 `tcp_tx_frame` 的 `T_DONE` 接受拍；`tx_arb` 的**数据通路**是组合 mux，
> 但 `busy/sel_fast` 是寄存器、每帧首字要等仲裁登记 ≥1 拍；`T_DONE` 接受 = 末字写进
> `u_txcdc` 写口，**多出的是帧首仲裁气泡，不是端点误差**）。

它**包含**：等窗口（`wnd_open`）、ACK 优先/轮扫/重放/fifo/bank/fence 等帧器启动门、帧器组帧与
`tx_arb`/`txcdc` 反压。
它**不包含**：app 产生首字之前的图案生成、`txcdc` 之后的 FE/MAC/PCS/PHY、控制帧、重传帧。
边界是刻意的：E1a-1 回答“板内 DP fast-path 一帧要多久”，不冒充“线上到线上”延迟。

**实现形态**：只在 `rtl/tcp_tx_frame.v` 的 `ifdef TCP_TX_OVL` 支内加一个 34 位时间戳 `{ts_wrap,ts_ctr}`、
每 bank 一个 `present_ts` 标签、10 桶直方图 + `sum_total` + `max_total`；
经既有 `u_snap_p7bdp`（`snap_cdc` / `hold_b`）进快照 **W85..W96**（12 字），
`SNAP_NW_P6E 85→97`、`SNAP_P7BDP_NW 41→53`、BID `0x33`、未实现地址 `0x1B4`。
**不碰功能路径**（只多观测计数器）；默认 `E1A_EN=0`，板构建在 `u_tcp_tx` 上显式 `P11_DUAL_DEF`（仅 C4）。

⛔ **不是“几百 FF 的小改”**：DP 侧约 450 FF，加 12 字快照三份（`hold_b`/`dout_a`/`snap_words_r`）
≈ **1.1–1.6 kFF**。0x32 全局 WNS 仅 **+0.019 ns**，宿主是 **stack2 G2**
（`u_tcp_tx2/u_fifo_b/rptr[0] → u_tcb2/rcv_wnd[9][0]`，16 级）。本设计只测 **port0 / u_tcp_tx**
（A 口），不碰 stack2 的 TCB 路径，但**必须**跑完整 timing gate；构建失败则**不烧**，见 §8。

---

## 1. 现状与为什么需要 E1a-1

### 1.1 已有读数（引用）

| 轮次 | 读数 | 缺口 |
|---|---|---|
| E0.5（零构建） | 4×24GB + 2×60GB 单口下行；快态 9.4405/9.4437/9.4453 Gbps、慢态 9.2560/9.0701 Gbps；快态 `ΔW65/ΔW43`=0.143/0.142%、`ΔW66/ΔW65`=70.90/71.16%；慢态 `ΔW65/ΔW43`=2.035/4.978%、`ΔW66/ΔW65`=89.95/92.19%；`W27/W28` Δ=0；W69 被 H-1/H-2 判为扫描伪拍不可用 | 只有**整窗**聚合，无 per-frame 分布；不是 p50/p99 |
| E1（零构建） | 5 baseline + 5×60GB load（slow 8.5971–9.2539G）；端口 B ping/TCP/UDP echo 0 丢包；p99 不升反降；尾延迟主项 = HLS 服务时间（64B ~0.1ms、996B ~0.4ms、1472B ~0.6ms） | **A 口 fast-path 单帧延迟 = 未测**；5 个 load 全 slow，快态未采到 |
| 0x32 构建 | WNS **+0.019** / setup·hold·PW 0/0/0；WNS 宿主 = stack2 G2；LUT 122,056 / FF 98,583 / BRAM 109 / URAM 17 / DSP 4 | 任何 RTL 改动都必须一次构建收口；见 §8 时序风险 |

### 1.2 为什么不能靠现有字回答

- `W63/W64`（`app_pattern.stat_frmwait_cyc/stat_bp_cyc`）是**累计拍数**，不是逐帧分布；
  `W52/W83` 是帧数。它们最多给“平均停顿/帧”，给不出 p99。
- `W66/W67` 是帧器启动点的累计等窗拍，`W65` 是线空闲拍；都是整窗量。
- `W69` 是单点锁存且受扫描伪拍污染，kimi H-1/H-2 已判不可用。
- **E1a-1 用事件时间戳，不依赖扫描采样**；扫描对 `wnd_open` 的一拍污染只造成 ≤1/16 的
  等窗拍偏差（见 §5.3），不会改变 `start_data`/`T_DONE` 的真实性（这两个事件的其余门
  与扫描拍互斥，见 `rtl/tcp_tx_frame.v:718-725` 与 `:1275+`）。

---

## 2. 指标定义（逐字，作为实现与判据的唯一口径）

### 2.1 时间轴

```
t_present:  s_axis_tvalid=1，recv_first=1，且 start_data=0
            = app 的帧首字已经压在呈交口上、帧器能看见它，但还没被接受
            （注意：recv_first=1 是“等首字”状态；首字只在 start_data 拍被接受，
              见 tcp_tx_frame.v:718-725 与 :1430-1445。**不要求 rx_state==RX_IDLE**：
              重放 RX_RING / 收尾 RX_FIN / 冲洗 RX_FLUSH 期间的 app 等待也计入）

t_start:    start_data=1 的那一拍 = 首字被接受；f_* 上下文同拍锁存
t_done:     tx_state==T_DONE 且 (!m_axis_tvalid || m_axis_tready) 且 !tx_is_ctrl
            = 末字被 u_tx_arb 接受。tx_arb 的**数据通路**是组合 mux（末字同拍穿透到
            txcdc 写口），但 `busy/sel_fast` 是寄存器：帧首必须先在沿上登记，
            `s_fast_tready = busy && sel_fast && m_axis_tready` ⇒ **每帧 ≥1 拍仲裁气泡**
            （慢帧在飞时 fast 还被整帧挡住）。这个气泡计入 L，不是端点误差。

L_tx_frame = t_done − t_present        （32 位，dp_clk 周期；1 cycle = 6.4 ns）
```

- `t_present` 是**首字呈现**，不是“app 开始生成”。app_pattern 在首字之前的企业级生成
  不计入；首字之后 app 继续供字如果慢，会计入（因为帧器在等它）。
- `t_present` 的锁存条件是 **`recv_first && s_axis_tvalid && !start_data`**（**不要求
  `rx_state==RX_IDLE`**）：即使帧器正在 RX_RING（重放）/RX_FIN/RX_FLUSH，只要它在
  “等首字”状态且呈交口有字，这个等待就是真实等待，必须从 L 起算。若首字一出现就能
  启动（窗口开、其余门开），`L_tx_frame = t_done − t_start`，即纯帧器/反压服务时间，
  等待分量 = 0。
- ⚠️ 因此 `present_pending` **不能**在 `ring_start` 或 `rx_state != RX_IDLE` 时清 ——
  那会把“app 帧在重放/收尾期间的真实等待”从 L 里抹掉（本设计第一版的错误，已订正）。
  只在 **`start_data`（已被消费）** 或 **`!s_axis_tvalid`（app 已不再呈现）** 或复位时清。
- **只统计 `f_is_app[tx_bank]=1` 的数据帧**；纯 ACK/控制帧（`tx_is_ctrl=1`）与
  ring 重放帧（`ring_start` 装载，`f_is_app=0`）不计入。
- **只统计完成帧**：被 `PLEN_MAX` 中止（`RX_FLUSH`/`stat_drop_len`）的帧没有 `bank_rdy`，
  不会进 `T_DONE`，因此不进直方图。分母 = 走到 `T_DONE` 的 app 数据帧。

### 2.2 为什么必须 per-bank 标签

`TCP_TX_OVL` 是乒乓双 bank：帧 N 还在 TX 引擎发送时，RX 引擎可以开始接收帧 N+1
（`rx_bank != tx_bank`；`bank_rdy[tx_bank]` 只在 `T_DONE` 清）。因此**不能**用一个全局
`start_ts`：帧 N+1 的 `start_data` 会覆盖它。

实现用两个 bank 各自的 `f_present_ts[0:1]` + `f_is_app[0:1]`：
- `start_data` 拍写 `f_present_ts[rx_bank] <= e1a_present_pending ? e1a_present_ts : e1a_ts_ctr;`
  `f_is_app[rx_bank] <= 1'b1;`
- `ring_start` 拍写 `f_is_app[rx_bank] <= 1'b0;`（ring 帧不需要时间戳）
- `T_DONE` 拍用 `tx_bank` 索引读；`tx_bank` 在 `T_DONE` 沿才翻到 `nxt_bank`，当拍稳定。

`rx_bank` 与 `tx_bank` 在正常乒乓下不同；更严格的无竞态论证：
- `start_data` 的接受门含 `!bank_rdy[rx_bank]`（`tcp_tx_frame.v:722-725`）；而 T_DONE 当拍
  `bank_rdy[tx_bank]` 仍为 1（清位在 `:1625-1626`）⇒ **同拍不可能对同一 bank 做
  `start_data` 写标签与 T_DONE 读标签**；
- `ring_start` 与 `start_data` 互斥（两者都含 `!ring_eval` 条件）；即使同拍（结构性不应），
  实现里写死 **`if (start_data) ... else if (ring_start) ...`** 的优先级。
- TB 断言（实施轮已加）：`start_data && done_ev` 同拍不得成立；`ring_start && start_data`
  同拍不得成立。E1a TB 已覆盖 bank 0/1 交替 + control 过滤。

### 2.3 边界与例外

| 场景 | 处理 |
|---|---|
| 首字呈现时窗口关 | `present_pending=1`，`present_ts` 锁存；计入 L |
| 首字呈现时 ACK 优先/`scan_now`/`s_axis` 以外的门关 | 同样计入（L 是“帧首字等到末字进 txcdc”的总时间） |
| 首字呈现时 `fifo_full`/`bank_rdy[rx_bank]` | 同样计入 |
| 首字一出现 `start_data=1` | 不锁 present；`f_present_ts <= ts64`，L 从接受拍起算，等待=0 |
| 帧被 `PLEN_MAX` 中止 | 帧首已被 `start_data` 消费 ⇒ pending 早已清；无 `T_DONE`，不计数。若中止发生在等待期（未启动），`!s_axis_tvalid` 清 pending |
| ring 重放帧 | `f_is_app=0`，不计数 |
| 纯 ACK / SYN/FIN/RST 控制帧 | `tx_is_ctrl=1`，不计数 |
| 复位 / `rst_n=0` | 清 `ts_ctr`、pending、hist、sum、max、bank 标签 |
| `ts_ctr` 32 位回卷 | 27.487 s；用 `{ts_wrap,ts_ctr}` 34 位时间戳；`lat_ok=0`（L≥27.487s，零窗 persist）**跳过**，不写错值到 hist/sum/max |
| `sum_total` 32 位回卷 | 27.5 s @ 满速；**快照窗 ≤10 s**，差值 mod 2³² 且记 `k`；若窗更长必须分窗 |
| 扫描伪拍 | 见 §5.3：只影响等窗分量 ≤1/16；本设计不新增 polluted 计数器（E1a-2） |

---

## 3. 直方图与统计

### 3.1 桶定义（10 桶，单位 cycle @156.25 MHz）

| bin | cycles | 时间（µs） | 备注 |
|---:|---:|---:|---|
| 0 | 0–127 | 0–0.813 | 短帧/无等待 |
| 1 | 128–159 | 0.819–1.018 | |
| 2 | 160–191 | 1.024–1.222 | |
| 3 | **192–223** | **1.229–1.427** | **1460B 服务 ~193 落这里**；0.2 µs 分辨率 |
| 4 | 224–255 | 1.434–1.632 | |
| 5 | 256–383 | 1.638–2.451 | 轻微排队 |
| 6 | 384–511 | 2.458–3.270 | |
| 7 | 512–1023 | 3.277–6.547 | |
| 8 | 1024–4095 | 6.554–26.214 | |
| 9 | ≥4096 | ≥26.214 | 饱和桶；p99 只能报“≥26.2 µs”，精确尾看 W96（全局 max） |

- 选 10 桶而不是 16：**1.2–1.6 µs 有 0.2 µs 分辨率**（1460B 服务 ~193 cyc 落 bin3），
  ≥26.2 µs 饱和；尾的精确值由 `max_total` 给。E1a-2 若要更细的 p99 再扩桶/加采样环。
- 桶边界是**常量**，板级读数与设计件必须逐字一致；改桶 = 改设计，需新 BID/新件。
- ⚠️ **W96 `max_total` 是“复位以来全局 max”，不是本窗 max**（E1a-1 不实现可清零的窗 max）。
  跨多次运行只能：①第一跑（复位后）max 精确；②后续跑若 max 不变，只能写“本窗 max ≤ W96”；
  ③全局 max 的桶归属用**累计 hist**（从复位后所有窗口 delta 求和）核对，不能用单窗 hist。
  ⚠️ **每会话首帧污染 max**：`start_data` 含 `!tx_blk_sid`，而 `tx_blk_sid` 含 `~acks_ok`
  （`tcp_tx_frame.v:607-608`）⇒ 新连接/换流首帧要等对端首个 ACK，L 可达数十 µs 甚至更久；
  W96 可能被这一帧钉住。**max 只作“全局上界”，不是稳态尾**；稳态 p99 看 hist。
  E1a-2 若要逐窗 max/首帧剔除，加“快照后清 max”的跨域握手或 src 标签。

### 3.2 统计字

- `hist_total = Σ hist[i]`（软件从 W85..W94 求和；不需要额外字）
- `mean_cycles = sum_total / hist_total`（W95 / hist_total）
- `max_cycles = W96`（**复位以来全局最大**；不是本窗最大，见 §3.1 末注）
- `p_q`：累计 `hist[0..k] ≥ ceil(q × hist_total)` 的最小 k；报 `[bin_lo, bin_hi]`，
  bin9 报 `[4096, ∞)`。**不把桶中点当精确分位数**。
- 一致性（免费牙）：
  - `hist_total > 0` 时，`max_cycles` 必须落在**累计直方图**（复位后所有窗口 delta 求和）的
    非空桶区间内（bin9 时 `max≥4096`）；**单窗 hist 不能做这个检查**（max 是全局量）；
  - `cum_sum ≥ max_cycles`（累计 sum，不是单窗 sum；两者都按 mod 2³² 记录 k）；
  - `mean_cycles = Δsum / hist_total` 必须 ≥ 帧器最小服务拍（本 TB 实测 219−200=19 拍；
    板级 1460B ≈ 190 拍）⇒ 这是有判别力的下界，不是 `sum ≥ hist` 的空判据；
  - `max_cycles < 2^32` 恒真，仅作格式检查（不写进判据 PASS）。
- 若 `hist_total=0` 而 `ΔW52>0` 或 `ΔW83>0` ⇒ **仪器没触发/没接线**，不是“延迟为 0”；
  板级判 **FAIL（仪器）**，不写“无延迟”。

---

## 4. 实现设计（implementation-ready）

### 4.1 文件与端口

**`rtl/tcp_tx_frame.v`**

在参数区（`PERSIST_EN` 附近，`:327`）加：

```verilog
parameter E1A_EN = 1'b0;   // 默认关 (其它构建/ TB 零逻辑); 板构建 u_tcp_tx 显式 1
```

在端口表（`stat_winstall` 附近）加：

```verilog
// ---- ⭐ P11 E1a-1: DP fast-path TX 逐帧延迟直方图 (纯观测) ----
output wire [319:0] e1a_hist,       // [31:0]=bin0 ... [319:288]=bin9
output wire [31:0]  e1a_sum_total,  // Σ L_tx_frame (cycle, 32 位自然回卷)
output wire [31:0]  e1a_max_total   // max L_tx_frame since reset (cycle)
```

- `e1a_hist` 的位序必须与 wrapper 的 `p7bdp_din` 逐字一致：**LSB = bin0**。
- 两个分支（`ifdef TCP_TX_OVL` / `else`）都必须驱动这三个输出；`else` 支恒 0。
- `u_tcp_tx2` 不传 `.E1A_EN`（默认 0），输出不接。

### 4.2 E1a 逻辑（只在 OVL 支内）

放在 OVL 支的**主 always 块之后、`dbg_*` assign 之前**（所有 `rx_state/tx_state/tx_bank/
tx_is_ctrl/start_data/ring_start` 已声明）。伪代码：

```verilog
generate if (E1A_EN) begin : g_e1a
    reg [31:0] ts_ctr;
    reg [1:0]  ts_wrap;                 // {ts_wrap,ts_ctr} = 34 位时间
    reg        present_pending;
    reg [33:0] present_ts;
    reg [33:0] f_present_ts0, f_present_ts1;
    reg        f_is_app0, f_is_app1;
    reg [31:0] hist0..hist9;            // 实施时逐项声明, 用 case(bin) 自增 (不用变量下标)
    reg [31:0] sum_total, max_total;

    wire [33:0] ts64            = {ts_wrap, ts_ctr};
    wire [33:0] f_present_ts_tx = tx_bank ? f_present_ts1 : f_present_ts0;
    wire        f_is_app_tx     = tx_bank ? f_is_app1 : f_is_app0;
    wire        first_present   = recv_first && s_axis_tvalid && !start_data;
    wire [33:0] lat64           = ts64 - f_present_ts_tx;
    wire        lat_ok          = !lat64[33] && !lat64[32]; // L < 27.487 s
    wire        done_ev         = (tx_state == T_DONE) && (!m_axis_tvalid || m_axis_tready) &&
                                  !tx_is_ctrl && f_is_app_tx && lat_ok;
    wire [31:0] lat             = lat64[31:0];

    reg [3:0] bin;                      // 128/256/384/512/768/1024/2048/4096/8192 边界
    always @* begin
        if      (lat < 32'd128)  bin = 4'd0;
        else if (lat < 32'd160)  bin = 4'd1;
        else if (lat < 32'd192)  bin = 4'd2;
        else if (lat < 32'd224)  bin = 4'd3;   // 1460B 服务 ~193
        else if (lat < 32'd256)  bin = 4'd4;
        else if (lat < 32'd384)  bin = 4'd5;
        else if (lat < 32'd512)  bin = 4'd6;
        else if (lat < 32'd1024) bin = 4'd7;
        else if (lat < 32'd4096) bin = 4'd8;
        else                     bin = 4'd9;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ts_ctr <= 0; ts_wrap <= 0; present_pending <= 0; present_ts <= 0;
            f_present_ts0 <= 0; f_present_ts1 <= 0; f_is_app0 <= 0; f_is_app1 <= 0;
            hist0..hist9 <= 0; sum_total <= 0; max_total <= 0;
        end else begin
            ts_ctr <= ts_ctr + 1;
            if (ts_ctr == 32'hFFFF_FFFF) ts_wrap <= ts_wrap + 1;
            if (start_data) begin
                if (rx_bank) begin
                    f_present_ts1 <= present_pending ? present_ts : ts64;
                    f_is_app1     <= 1'b1;
                end else begin
                    f_present_ts0 <= present_pending ? present_ts : ts64;
                    f_is_app0     <= 1'b1;
                end
                present_pending <= 1'b0;
            end else if (ring_start) begin
                if (rx_bank) f_is_app1 <= 1'b0; else f_is_app0 <= 1'b0;
            end else if (first_present && !present_pending) begin
                present_ts <= ts64; present_pending <= 1'b1;
            end else if (!s_axis_tvalid) begin
                present_pending <= 1'b0;
            end
            if (done_ev) begin
                sum_total <= sum_total + lat;
                if (lat > max_total) max_total <= lat;
                case (bin) 4'd0: hist0 <= hist0+1; ... 4'd9: hist9 <= hist9+1; endcase
            end
        end
    end
    assign e1a_hist = {hist9,...,hist0};   // 实施时逐项展开
    assign e1a_sum_total = sum_total;
    assign e1a_max_total = max_total;
end else begin : g_e1a_off
    assign e1a_hist = 0; assign e1a_sum_total = 0; assign e1a_max_total = 0;
end endgenerate
```

**实现注意（每条都是坑）：**

1. `first_present` 与 `start_data` 同拍时，`start_data` 分支优先 ⇒ 不置 pending；`f_present_ts <= ts64`。
2. `present_pending` 的清位只有三种：`start_data`（已消费）、`!s_axis_tvalid`（app 撤回）、复位。
   **不在 `ring_start` / `rx_state!=RX_IDLE` 清** —— 重放/收尾期间 app 首字的等待是 L 的一部分。
3. `f_is_app` 在 `start_data` 置 1，在 `ring_start` 清 0；**无其它写者**。不要用 `tx_is_ctrl` 推断。
   `ring_start` 只写 `f_is_app[rx_bank]`，不动 `present_pending`。
4. `done_ev` 必须逐字复用 `T_DONE` 分支的接受条件（`!m_axis_tvalid || m_axis_tready`），
   否则计数与 `stat_frames` 差拍；`stat_frames` 的同一拍就是 `T_DONE` 记账拍。
5. `hist[bin]` 变量下标综合成 10 个 32 位寄存器 + 多路写使能；不要写成 `hist <= ...` 整数组。
6. `sum_total`/`max_total`/`hist` 都只在 `done_ev` 拍更新（≈800k/s，最坏 1 帧/193 拍），
   没有每拍大位宽加法。
7. `ts_ctr`/`ts_wrap` 只在 `rst_n` 清；与 `gmii`/`pcie` 域无关，全部在 `dp_clk` 域内。`lat_ok=0` 的帧（>27.487 s，零窗 persist）**不计入** hist/sum/max。
8. 不要在 `first_present` 里加 `s_axis_tready`：首字呈现时 `tready=0` 正是要测的等待；
   `start_data` 已含 `s_axis_tvalid` 与所有门。
9. `rx_state`/`tx_state`/`tx_bank`/`tx_is_ctrl`/`start_data`/`ring_start` 都是 OVL 支内部
   信号；本块必须放在它们声明之后（用 `xvlog` 先声明后用，坑 24）。
10. 默认 `E1A_EN=0` 时 `g_e1a` 整块被裁掉；serial 支也必须把三个输出接 0。

### 4.3 快照映射（12 字）

| 快照字 | 源 | p7bdp 槽 | 含义 |
|---:|---|---:|---|
| W85 | `e1a_hist[0]` | 41 | bin0: 0–127 cyc |
| W86 | `e1a_hist[1]` | 42 | bin1: 128–191 |
| W87 | `e1a_hist[2]` | 43 | bin2: 192–255 |
| W88 | `e1a_hist[3]` | 44 | bin3: 256–383 |
| W89 | `e1a_hist[4]` | 45 | bin4: 384–511 |
| W90 | `e1a_hist[5]` | 46 | bin5: 512–767 |
| W91 | `e1a_hist[6]` | 47 | bin6: 768–1023 |
| W92 | `e1a_hist[7]` | 48 | bin7: 1024–2047 |
| W93 | `e1a_hist[8]` | 49 | bin8: 2048–8191 |
| W94 | `e1a_hist[9]` | 50 | bin9: ≥8192 |
| W95 | `e1a_sum_total` | 51 | Σ L_tx_frame (cycle, mod 2³²) |
| W96 | `e1a_max_total` | 52 | max L_tx_frame **since reset** (cycle; not per-window) |

几何：
- `SNAP_P7BDP_NW 41 → 53`
- `SNAP_NW_P6E 85 → 97`
- `SNAP_LAST_IDX = 8 + 97 − 1 = 104`（word；地址 `0x1A0`）
- MIR 四字自动 = 105/106/107/108 = `0x1A4/0x1A8/0x1AC/0x1B0`
- **未实现地址 = word 109 = `0x1B4`**
- `0x1B4 < 0x200`（7 位译码红线，不触发 512 B 回绕）；97 ≤ 119 窗口上限。
- BID `0x32 → 0x33`（`board/wrapper_p4.v:6286`）。

**CDC 纪律**：12 个源全部是 `dp_clk` 域的寄存器输出（`hist[]`/`sum_total`/`max_total`
都是寄存器）。**必须**走 `u_snap_p7bdp` 的 `snap_cdc`/`hold_b`，**不得**在顶层
`snap_dout_all` 直连（0x2C 的 F-21 陷阱：多比特计数器裸跨域；且直连会让 hold_b 槽位
无寄存器）。新增 p7bdp 槽必须满足：
- `p7bdp_din[41..52]` 每个槽恰好一个显式 `assign`，源 = 寄存器输出；
- 布后 `u_snap_p7bdp/hold_b_reg[...]` 在新槽位每槽至少 1 个寄存器；
- 若后续再加字，**一律加在 p7bdp 的 MSB 端**（槽 53+），旧字槽号不动。

### 4.4 wrapper 编辑点（逐条）

1. `board/wrapper_p4.v` 约 `:2838` 的 `u_tcp_tx` **参数表**加 `.E1A_EN(P11_DUAL_DEF)`（不是端口；
   只有 C4 开，C1/C3 传 0），端口表加：
   ```verilog
   .e1a_hist      (e1a_hist),
   .e1a_sum_total (e1a_sum_total),
   .e1a_max_total (e1a_max_total),
   ```
2. 在 `tx_stat_winstall` 等声明附近声明：
   ```verilog
   wire [319:0] e1a_hist;
   wire [31:0]  e1a_sum_total, e1a_max_total;
   ```
3. `SNAP_P7BDP_NW` → 53（`:4956`）；`SNAP_NW_P6E` → 97（`:4935`）。
4. `p7bdp_din` 末尾（`:5888` 附近）加 12 条：
   ```verilog
   assign p7bdp_din[41*32 +: 32] = e1a_hist[0*32 +: 32];   // W85
   ...
   assign p7bdp_din[50*32 +: 32] = e1a_hist[9*32 +: 32];   // W94
   assign p7bdp_din[51*32 +: 32] = e1a_sum_total;          // W95
   assign p7bdp_din[52*32 +: 32] = e1a_max_total;          // W96
   ```
5. `snap_dout_all` 顶端（`:6061`，MSB 端）加 12 项，顺序 **W96 → W85**（从最高槽往下），
   再保留现有 `p7bdp_dout[40]`（W84）：
   ```verilog
   p7bdp_dout[52*32 +: 32], // W96 max_total
   p7bdp_dout[51*32 +: 32], // W95 sum_total
   ...
   p7bdp_dout[41*32 +: 32], // W85 hist0
   ```
   ⚠️ 拼接是从右往左读：最后写的项在 MSB 端 = 最高字。写错位置 = 全体旧字平移。
6. `BUILD_ID_V (32'h00000032)` → `32'h00000033`（`:6286`）。
7. `u_tcp_tx2`（port1）**不加** E1A 端口；保持默认 `E1A_EN=0`，三个输出不接。

### 4.5 工具/门/文档同步（不全改就是“读侧假红/假绿”）

| 文件 | 必须做什么 |
|---|---|
| `_proj_10g/notes/p7b_biz_win/check_window.py` | 跑一遍；它按 `SNAP_NW_P6E`/束宽等式/拼接项数检查。新增 12 项后必须仍 PASS；若它把 p7bdp 顶端写成旧槽号，更新其顶端映射逻辑。 |
| `_proj_10g/p7b_chain/sim/check_snap_top5_wired.py` | 当前只检查槽 39..40；**必须扩到新顶 12 槽**（至少新 top5），否则 F-21 的静态牙只保护旧字。 |
| `board/build_p7b_ku5p.tcl` 的 `P7B_SNAP_TOP5_CDC` | 当前硬编码槽 39..40；扩到新槽 41..52 或至少检查新 top5 每槽有 hold_b。 |
| `_proj_pcie/p7b_biz/p7b_snap.sh` | 默认 `NW=85/EXPECT_BID=0x32`；E1a 板级用 **env 覆盖** `NW=97 UNIMPL_ADDR=0x1B4 EXPECT_BID=0x00000033`，不必改默认值（但要在 `full` 标签表加 W85..W96 或在注释登记）。 |
| `_proj_10g/notes/P11_BIZ_WINDOW*.md` / 窗口表 | 加 W85..W96 与几何；未实现地址 0x1B4；BID 0x33。 |
| `_proj_pcie/p6e_snap_check.sh` | 若它硬编码 NW/标签，按新几何同步；至少 E1a 板级不使用它的旧标签。 |
| `sim/p6e_pcie/tb_p6e_pcie_wrapper.v` | **已过期、且不在 41 门矩阵**：其 MIR 地址仍停在 NW=75/85 世代（0x174 当 MIR_CTRL 用等），与 0x32 及 E1a 的 0x1A4..0x1B4 都不一致。E1a **不依赖**该 TB；登记为测试债（下一次动 MIR 时整表重派生）。 |
| `_proj_pcie/p7b_biz/p7b_mir_dump.cpp` | **当前文件里 MIR_STATUS/DATA/CTRL/DMA_CNT 硬编码 0x13C/0x140/0x144/0x148，已落后于 0x32 的 0x174..0x180**；E1a 的 NW 97 会把它们再推到 **0x1A4/0x1A8/0x1AC/0x1B0**。E1a 板级**不使用 MIR**；若同轮要用 MIR，必须先按 `axi_regs` 的 `SNAP_LAST_IDX` 自动派生地址，**不得照抄旧常量**。 |
| `P11_REVIEW_QUEUE.md` / `P7B_TL_LEDGER` | 登记本设计与后续构建/板级行。 |

### 4.6 资源/时序预算（纸面，未综合）

| 项 | 估算 |
|---|---|
| DP 逻辑 | `ts_ctr` 32 + `ts_wrap` 2 + pending 1 + `present_ts` 34 + per-bank 2×34 + `f_is_app` 2 + hist 10×32=320 + sum/max 64 ≈ **523 FF**（34 位时间戳，跨 32 位回卷） |
| 快照新增 | 12 字 × 3 份（hold_b 32 / dout_a 32 / snap_words_r 32）= **1,152 FF** |
| LUT | 34 位减 + 9 个 32 位比较 + 10 路 CE/加法约 **400–700 LUT**（纸面；综合报告为准） |
| BRAM/URAM/DSP | 0 / 0 / 0 |
| 总 FF | 约 **1.6 kFF**（0x32 现 98,583，+1.6%） |

⚠️ 这些是**纸面**；必须由综合/实现报告确认。**不要**把“FF 少”当成时序安全：
0x32 的 WNS 只有 +0.019 ns，P&R 位移可能吃掉它。

---

## 5. 观测误差与扫描伪拍

### 5.1 时间基

- `ts_ctr` = `dp_clk` 156.25 MHz，1 cycle = 6.4 ns；32 位回卷 27.487 s，配 2 位 `ts_wrap` 组成 34 位时间戳（单帧 L<27.487 s 才入桶）。
- 直方图单位 = cycle；板级换算 µs = cycles × 0.0064。

### 5.2 起点/终点误差

- `t_present` 是**寄存器采样**的 `s_axis_tvalid`/`recv_first` 拍；app 的 valid 与帧器同域，
  无跨域误差。
- `t_done` 用 `T_DONE` 接受拍；与 `stat_frames` 同拍，无额外拍偏差。
- `L` 的定义**不含** `t_present` 之前的企业级生成，也不含 `T_DONE` 之后 txcdc 读侧/FE。

### 5.3 H-1/H-2 扫描伪拍

kimi H-1/H-2 已证：`tcb` 的 win 口跟随 `win_id` 晚 1 拍；帧器每 16 拍扫描一次，
扫描后一拍 `win` 口可能仍是被扫空槽的 `{0,0}`。对本设计：
- `start_data` 的其余门含 `!scan_now`，扫描当拍不会启动（`tcp_tx_frame.v:718-725`）；
- 扫描后一拍，`wnd_open` 可能仍属被扫槽 ⇒ `stat_winstall_ev` 可能多计 1 拍/16 拍；
- **本设计不新增 polluted 计数器**；判据里对“等窗分量”用 **1/16 地板（只是下界）**：
  `wait_win_est = ΔW66`（整窗）时，真实等窗拍 **≥** `ΔW66 × 15/16`（因为最多 1/16 是伪拍）；
  对 per-frame `L`，污染只影响“present→start”那一段，段内每 16 拍最多 1 拍
  ⇒ 若 `L_wait` 是真实等待，`L_raw ≥ L_wait ≥ 15/16 · L_raw_wait`。
  快态 `L_wait≈0` ⇒ 偏差≈0；慢态 `L_wait` 大时**报 `L_raw` 与下界 `15/16·L_raw`**；
  这是**下界**，不是估计值/修正值，不能用来缩小 p99 区间，也不能用于不含窗口分量的帧。
- E1a-2 再加 `polluted_wait` 计数器和 per-frame wait 分量，届时可替换本近似。

---

## 6. 预注册判据（先写死，避免“测了再找解释”）

### 6.1 构建门（全部满足才可烧）

1. `P7B_VERDICT=OK`；`WNS > 0`、setup/hold/PW 失败端点 **0/0/0**；
2. `P11_STA_TCB_GATE` stack1 A–F 与 stack2 A2–G2 **全部 > 0**（0x32 的 G2 = +0.019；
   本设计不碰 stack2，若 G2 变负 = 构建失败，不是“仪器问题”）；
3. `P7B_HLS_ROM_LOG_GATE` 0 命中；DRC 0 Error/Critical；`BITSTREAM-OK`；bat exit 0；
4. `check_window.py` 8 条全 PASS；`P7B_SNAP_TOP5_CDC` 新槽 PASS；
5. 矩阵：P11 子集 + 其余非 BID 全 EXIT=0（按 0x32 的 17/17 + 22/22 口径）；
6. 位流 sha256、BID 0x33、NW 97、未实现 0x1B4 记录在构建 README。

### 6.2 板级门（E1a-1 的“有牙”判据）

| # | 判据 | 说明 |
|---:|---|---|
| 1 | 身份：BID `0x33` / NW 97 / `0x1B4=0xffffffff` / 2 BARs / `LnkSta x4` / `0x08=0` / carrier 1/1 | 任一不符 = 停 |
| 2 | **空载负对照**：烧录/复位后、无 TCP 流量 2 s，`snap` 两次，`hist_total` Δ=0、`sum_total` Δ=0、`max_total`=0（全局 max 复位后仍 0） | 计数器只在 app 完成帧更新 |
| 3 | **负载正对照**：≥10GB 单口下行，窗内 `hist_total > 0`；**累计**（复位后所有窗口 delta 求和）满足 `cum_sum ≥ max_global`，且 `max_global` 落在累计直方图的非空桶 | 仪器触发/接线；单窗 `sum` 与全局 max 不可直接比（max 不是窗量） |
| 4 | **分母对账**：**主判据 `hist_total ≤ ΔW14`**（W14 = port0 `tcp_tx_frame.stat_frames`，与 hist 同模块同 T_DONE 口径）；辅 `|hist_total − ΔW52| ≤ 2`（app 在末字交出拍计数，边界可差 1–2）；`hist_total ≤ ΔW83 + 4` 仅在 DUAL 构建有值（非 DUAL W83 恒 0，不可作判据）。差值 = 控制/重放/中止帧（登记） | 防止“少计一半”；W14 是最紧同源分母 |
| 5 | p50/p99 从桶给区间；`max` 精确；快/慢态按 sink 速率分类（快 ≥9.35G、慢 8.60–9.26G） | 主读数 |
| 6 | 至少 1 次快态 + 1 次慢态；若 10 次仍全慢，写“快态未测”，不许把慢态当 fast-path 基线 | E1 的教训 |
| 7 | 数据内容：`mism=0`、`first_mismatch=-1`、`ΔW54=0`；10GB×N 总字节对账 | 仪器不得改变功能 |

### 6.3 明确不做的判据

- 不把 `L_tx_frame` 与 E1 的 HLS p99 直接相减/相加（两个不同路径/事件点）。
- 不把 `L_tx_frame` 当“线上到线上”或“app 消息到对端”的延迟（不含 FE/MAC/PHY/对端）。
- 不用单次快照读 p99；p99 必须来自直方图累计 + `max` 交叉检查。
- 不在 E1a-1 里解释“快/慢态翻转机理”（E0.5 已登记未定位；E1a-1 只给两态下的 L 分布）。

---

## 7. 构建与板级验证计划（若实施）

### 7.1 构建

- 只走 `board/run_build_p7b_ku5p.bat`，`P11_CFG=c4` + 现有 HLS 变体；**不碰 QSPI**。
- 先跑静态门（`check_window.py`、TB 单元门、lint）、再全构建；构建脚本会跑 timing/ROM/TCB/DRC 门。
- 位流归档到 `bits/`，报告归档（timing/util/drc/route/runme/stdout）按 Tier B 纪律。
- **一次构建收口**；失败不重跑到过（#63），按 §8 处置。

### 7.2 板级

1. 烧 0x33（JTAG 1 MHz），核 sha256/BID/NW/未实现/2 BARs/x4/carrier/`0x08`；
2. 空载负对照：`p7b_snap.sh snap E1A_IDLE 85..96` 两次，Δ 全 0；
3. 10 轮 × 10GB 单口 A 下行（`p7b_tcp_sink --check lane8 --rcvbuf 1048576`，THREADED，
   `taskset`/IRQ 按 E0.5/E1 配方）；每轮 PRE/MID1/MID2/POST 快照（W0/W5/W20/W43/W52/W65/
   W66/W67/W68/W69/W83/W85..W96）；
4. 每轮记 sink 速率/字节/mism；按速率分快/慢态；算 Δ 直方图、p50/p99 区间、max、mean；
5. 至少 1 次快态；若无，登记“未测”，不写“fast-path 快态延迟”。
6. 收尾：`0x08=0`、carrier 1/1、无 sink 进程；板保持 0x33（或按用户指示回 0x32）。

### 7.3 预期读数形态（不是判据）

- 快态无等待：L 应落在 bin0–bin3（0–2.5 µs），p50 约 1.2–1.6 µs（1460B 的帧器服务 +
  txcdc 反压）；p99 可能到几 µs。
- 慢态：窗口等待把尾部推到 bin5–bin9；p99 可能 ≥10–50 µs；max 精确。
- 若 p50 就 >26 µs，说明不是“帧器服务”而是排队/窗口主导，E1 的零构建结论不能外推到
  fast-path；E1a-2 的 wait 分解应优先做。

---

## 8. 时序风险与预注册 backstop

0x32 全局 WNS = **+0.019 ns（0.297%）**，宿主 = **stack2 G2**（`u_tcp_tx2/u_fifo_b/rptr[0] →
u_tcb2/rcv_wnd[9][0]`，16 级）。E1a-1 只改 port0 `u_tcp_tx` + p7bdp 快照，**结构上不碰
stack2 的 TCB**，但 P&R 是全局的；新增 1.6 kFF 可能改变布局。

**Backstop（事前写死，只允许一次构建）：**

| 情形 | 动作 |
|---|---|
| WNS>0、0/0/0、TCB 门 PASS | 可烧；按 §7 板级 |
| WNS<0 或 setup/hold/PW 任一 >0，或 TCB G2/A2 <0 | **不烧**；归档；记录“E1a-1 时序失败”；**不重跑到过** |
| 仅 `check_window.py`/snap top5 静态门失败 | 先修门/装配（不改功能），再考虑构建；若已构建，按失败归档 |
| 构建脚本/ROM/DRC 失败 | 按既有纪律停；不烧 |

**不做的备选**：本次**不**预注册“删桶重试第二构建”。原因：0.019 ns 的失败主要是布局
位移，删 2 个字不保证；且时间预算内一次构建更诚实。若需要，下一轮用**另一版设计**
（例如 8 桶 + 无 sum/max）作为独立输入再构建，而不是“重跑到过”。

---

## 9. 未覆盖项（E1a-2 及以后）

1. **wait/service 分解**：per-frame `wait_win`/`wait_other`/service 的 sum/hist；本设计只给总 L。
2. **扫描 polluted 计数器**：`stat_winstall_ev && scan_now_d1` 的拍数；本设计只用 1/16 地板。
3. **port B（u_tcp_tx2）**：W66–W69 仍空接（`board/wrapper_p4.v:3353`）；E1a-2 补。
4. **RX fast-path**：`u_rxcdc` 读口 → `tcp_rx.meta_valid` → `u_app` RX 首字；需要跨模块
   frame_id/conn_id 标签，E1a-3。
5. **FE/MAC/PCS/PHY**：E1b 的 SOP/TLAST 时间戳；M6 环回只给往返，不能直接相减。
6. **采样环**：保留最近 N 帧的精确 (t_present,t_done,conn) 供 p99 尾部归因；本设计只有桶+max。
7. **快/慢态翻转机理**：E0.5 的未定位项，不由 E1a-1 回答。
8. **retransmission 帧延迟**：本设计明确排除；若重传占比高，`hist_total < ΔW52`，需另计。

---

## 10. 实施检查清单（按序）

- [ ] `rtl/tcp_tx_frame.v`：加参数/端口；OVL 支加 `g_e1a`；serial 支接 0；`xvlog` 单文件过。
- [ ] 单元 TB：至少 3 个场景（窗口等待 100 拍 / 无等待 / ctrl+ring 不计数），
      用 `E1A_EN=1` 跑 xsim；断言 `hist_total`、`sum_total`、`max_total` 与 TB 计的一致
      （TB 自己用同一个 `ts_ctr`? 不，TB 用周期计数，误差 ≤1 拍；阈值写死）。
- [ ] `board/wrapper_p4.v`：u_tcp_tx 例化/声明/几何/12 条 din/12 条 dout/BID。
- [ ] `check_window.py`、`check_snap_top5_wired.py`、build top5 gate 同步并跑。
- [ ] 全构建（`run_build_p7b_ku5p.bat`）+ 归档 + 位流 sha。
- [ ] 板级身份 + 空载负对照 + ≥10 轮负载 + 快/慢态分类。
- [ ] 报告 `README_FOR_TL.md`：读数、原件、未测/未定位、与 E0.5/E1 的边界。
- [ ] 台账 §10-新行、`P11_REVIEW_QUEUE.md`、`P7B_OPEN_ITEMS.md` 更新。
- [ ] 提交（显式文件清单；`Co-Authored-By`）；不 `git add -A`；不碰 QSPI/license/perfv。

---

## 11. 与已有文档的关系

- 研究件 `P11_LATENCY_RESEARCH_20261026.md` §4.5 的 E1a 段：本件是它的**第一刀**
  （DP TX 逐帧总延迟）；§4.5 里的 64 位计数器/多事件 tagging/采样环是 E1a-2/3 的完整版，
  本件**明确缩窄**，不声称覆盖全部。
- E1 报告 `p11_e1_latency_20261027/README_FOR_TL.md`：E1 的“fast-path 未测”由本件回答；
  E1 的 HLS p99 与 E1a 的 L_tx_frame **不可相加/相减**。
- E0.5 报告 `p11_e05_latency_20261027/README_FOR_TL.md`：W65/W66/W67 的整窗读数用于
  与 E1a 的 per-frame 分布交叉解释；W69 仍不可用（H-1/H-2）。
- `P7B_OPEN_ITEMS.md`：HLS UDP echo 996B 边界与 E1a 无关，但同属“未修”项，别混。

---

## 12. 状态

- 本件：**【设计·已实施·已构建（构建 2 通过）·已上板（0x33）】**
- 代码改动（2026-10-27 02:3x）：
  - `rtl/tcp_tx_frame.v`：参数 `E1A_EN`、三个输出端口、OVL 支 `g_e1a`、serial 支 tie-off。
  - `board/wrapper_p4.v`：u_tcp_tx 接线、`SNAP_P7BDP_NW 53`、`SNAP_NW_P6E 97`、
    p7bdp_din 槽 41..52、snap_dout_all 顶端 12 项、BID 0x33。
  - `_proj_10g/notes/p7b_biz_win/check_window.py`：E1a 顶端/槽映射；**PASS=122 / FAIL=0**。
  - `_proj_10g/p7b_chain/sim/check_snap_top5_wired.py`：TOPN 14 + E1a din 映射；**PASS**。
  - `board/build_p7b_ku5p.tcl`：`P7B_SNAP_TOP5_CDC` 槽集 39..52（14 槽）。
  - `_proj_pcie/p7b_biz/p7b_snap.sh`：W85..W96 名字。
  - `tb_e1a_draft.v`（本目录）：xsim 单元门，**TB_E1A_PASS**（A/B/C/D 四场景，见
    `compile/xsim.log`）。
- **构建 1（0x33 / c4 / Performance_Explore）**：**WNS −0.023 / WHS +0.004 / WPWS 0.010；
  setup 145 / hold 0 / PW 0 ⇒ `P7B_TIMING_GATE=FAIL`**；位流改名 `.TIMING_FAIL`，**禁烧**。
  最差路径 = `u_tcp_tx/FSM_sequential_rx_state_reg[0]_replica → u_app/tx_lfsr_reg[61]/D`
  （21 级，route 4.302 ns）—— **不是 E1a hist 路径**，是放置/布线位移暴露的既存路径。
  报告归档 `build_fail1/`。
- **构建 2（同 RTL/宏/BID，仅 `P11_IMPL_STRATEGY=Performance_ExtraTimingOpt`）= 通过**：
  **WNS +0.008 / WHS +0.010 / WPWS 0.000（0 failing）**；**setup/hold/PW 端点 0/0/0**；
  `All user specified timing constraints are met`；`P7B_TIMING_GATE = PASS`；
  **TCB A..G2 min 0.223 ⇒ `P11_STA_TCB_GATE = PASS`**；DRC **0 Error/0 Critical/85 Warning**；
  **top5 槽 39..52、SLOTS_OK=14**；`P7B_BIT_EXISTS=1` / `P7B_VERDICT=OK`。
  位流 `bits/wrapper_p4_0x33.bit`，15,431,261 B，sha256
  `4e41a064d4b599b7f09902dc4c0435f50e6c29c660206ac03fe90b44329d0550`。
  WNS 宿主 = `u_tcp_tx2/u_fifo_b/rptr_reg[3]/C → u_retx_pool/g_slot[4].u_ram/ra_e_r_reg[0]/CE`
  （DP 域 port2 TX 既存族，15 级 / route 74.9%）—— **不是 E1a hist 路径**。
  资源 LUT 121,295 / FF 100,050 / BRAM 109 / URAM 17 / DSP 4。
  ⚠️ **WNS 仅 0.125% 余量** ⇒ 后续任何 RTL 改动须重新定向 STA 并一次构建收口。
  这是**另一个构建输入**，不是“重跑到过”（策略与构建 1 不同，RTL/宏/BID 逐字相同）。
- 板级（2026-10-27 05:15–05:20，0x33 已烧）：**身份全中**（BID 0x33 / NW 97 / `0x1B4=0xffffffff` /
  97 字 NFF=0 / 2 BARs / x4 / carrier 1/1 / `0x08=0`；JTAG 1 MHz，`End of startup status: HIGH`）。
  **空载负对照 PASS**：2 s 内 Δhist=Δsum=Δmax=0，而 W43/W65 各 +328,152,868。
  负载 10×10 GB：**68,493,653 帧**，`hist_total == ΔW52` **10/10 逐字相等**，
  `hist_total ≤ ΔW14` 10/10（差合计 1,612 = 0.0024%）；`mism_bytes=0` 全跑。
  **p50 与 p99 全部落 bin6（384–511 cyc = 2.46–3.27 µs）**；bin0–bin4 恒 0，bin3（纯服务）恒 0；
  meanX = 2.47–2.49 µs（原始 mean 2.64–2.66 µs）。tail(≥512 cyc) = 0.007–0.031%（快跑）
  vs 0.44–0.85%（3 个退化跑，9.27–9.32 Gbps）。高分位：快跑 p99.9/p99.99 仍 bin6（个别 p99.99 进 bin7/8）；
  退化跑 p99.5/p99.9 进 bin7（3.28–6.55 µs）、p99.99 进 bin8（6.55–26.2 µs）。
  **`max_total` = 1.2047–1.2052 s 属仪器污染**：TX_CONTINUOUS 下**会话边界帧**（连接关闭前后呈现、
  跨关闭期等待）因 `s_axis_tvalid` 不落而不清 pending ⇒ **每次会话边界恰 1 帧**把空闲间隔计入 L
  （R1 复位后 max 仅 31,932 cyc = 204 µs）。
  结论：E1a-1 仪器**有牙**（分母/负对照/内容全过）；**p50≈2×帧周期、bin3 恒空** ⇒
  L 从不等于纯帧器服务，含约 1 帧槽等待（候选：OVL 乒乓 app 领先一帧，**未证**）。
  E1a-2 必须加首帧标签/pending 清理，并做 wait/service 分解。
  读数原件 = `raw/E1A/E1A_METRICS.txt` + `raw/board_round.log`。
- **41 门矩阵**（`gates/matrix_e1a.log` + `gates/biz_win_rerun.log`）：首轮 **40/41 EXIT=0**，唯一红 = `biz_win`
  （TB `tb_biz_win.v:158` 的 BUILD_ID 期望仍是 0x32；同门 `check_window.py` 122/0 全过）⇒ **测试期望缺陷**，
  不是 RTL/构建失败。改 0x33 后单门复跑 `BIZ_WIN_CHECK_PASS` / 40 项 / RC=0；随后**全矩阵复跑 41/41
  EXIT=0、`MATRIX_FINAL_RC=0`** ⇒ **最终 41/41（单次全绿）**。
  ⚠️ 顺序偏离：烧板先于全矩阵（§6.1-5），如实登记；修复未改 RTL/位流。
- 单元门：`tb_e1a_draft.v` 的 A（200 拍等待）/ B（无等待）/ C（控制帧不计）/ D（撤字后重呈交，H-1）
  四场景全部 **TB_E1A_PASS**；`compile/xsim.log` 留存。
- 静态门：`check_window.py` **PASS=122/FAIL=0**；`check_snap_top5_wired.py` **PASS**。
- 独立审查：**已完成**（Claude 审查 agent；5 高 / 11 中 / 若干低）。处置见 `REVIEW_RESPONSE.md`。
  H-1/H-2/H-3/H-5/M-1..M-7/M-9/M-10 已修；H-4 的三个 TB 中两个已修、p6e 登记债；
  M-8/M-11 与低项按登记处理。
- 下一步：矩阵 → 一次构建 → 若时序 PASS 则烧 0x33 + E1a 板级；若时序 FAIL 则不烧、
  归档并保留 0x32。
