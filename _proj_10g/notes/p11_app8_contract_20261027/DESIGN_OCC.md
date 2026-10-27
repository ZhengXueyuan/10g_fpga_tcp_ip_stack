# P11-APP8-A v3：每连接接收占用（设计件；待终审，不施工）

> ⛔ **本文件的 v3/v4/v5 文字 = 历史。终版施工依据 = `DESIGN_OCC_V6.md`（2026-10-28，
> 独立审查 `REVIEW_V5.md` 的 F1–F20 处置）。凡本文件与 v6 冲突处，一律按 v6 读。**

- 日期：2026-10-27（v2 复审后的修订版）
- 依据：`REVIEW_RESPONSE.md` H2；用户裁定 **C = 先审 A 设计，不构建**
- v2 复审：附条件（H-1 rb 取样、H-2 cq 满丢好帧/fq 回卷、M-1 物理证明、M-2 删 orphan、
  M-5 板级协议、M-6 必红项）；v3 按条件重写
- 状态：【设计·待终审】【未实施】【未构建】【未上板】

---

## 0. v2 条件的处置

| 条件 | v3 |
|---|---|
| H-1 `judged` 拍取样错 | `rb_cid <= cid_w; rb_words <= cw_n;`（**本拍组合值**，含末字/单字帧）；`cur_words` 8 位 |
| H-2 cq 满丢好帧 + fq 128 回卷 | **帧边界前置门**：`first_b` 拍若 `fq >= CQ_DEPTH-2` 则 `s_axis_tready=0`（**反压不丢**，tcp_rx 保字）；cq 永不满、fq 永不过 127；**不**回卷好帧 |
| M-1 物理证明代数错 | §2.1 改用**未改的授予式**：`Σwinq + occ_port ≤ WIN_POOL` + margin/Δ/U/SEG ⇒ 130,762 ≤ 131,072 |
| M-2 `occ_orphan` 冗余且伤活性 | **删除**；`fq_i = max(0, winq_i − occ_i)`；live_mask/orphan 和全部不要 |
| M-4 孤儿和时序 | 随 M-2 删除 |
| M-5 板级协议 | §5.3：0x34 先构建/归档；**8 条全部建连后**再灌流；上行臂 = **双向**（APP8 TX_CONTINUOUS=1 不可单关，明写） |
| M-6 必红项 | O1–O9 补：单字坏帧、末字计账、fq≤127、内容不丢、`Σwinq+occ_port` 断言、5 个变异 |
| L-1..L-5 | 复用 `o_winq_rd_id`（不新增输出）；有符号饱和；cur_words 宽度；宏蕴含；O4 改物理界 |

---

## 1. 问题（已证·源码）

`fq_calc(q, oc)` 的求值点只有 3 处：扫描 `rtl/app_ctrl.v:973`、init redge `:1166-1167`
（`redge_calc` 内 `:783`）、init fc `:1190`。`:1480-1483` 不是 fq_calc（写 `pb_wscan`）。
`rx_occ_bytes` 是**本口** echo FIFO 的 `(wptr−rptr)<<3`（`board/wrapper_p4.v:1513-1516`，
port1 `:3158-3159`），对本口所有连接共享。

8×12KB：`winq_i=0x3000`；本口 FIFO 有 ≥12KB 未消费数据时，`fq_i=0` 对 8 条同时成立。
`win_pool_mgr` 的 `− occ_port`（`:253-266,400-413`）同时是**孤儿占用**的闸门
（`app_ctrl.v:1161-1165`）⇒ **保留不改**。

---

## 2. 模型

- `occ_i` = 连接 i 在共享 echo FIFO 中未消费的**字数×8**（与现役 `wptr−rptr` 同口径；
  含 `tkeep<8` 与合成尾字，是物理存储量，不是有效字节）。
- **通告窗**：`fq_i = max(0, winq_i − occ_i)`。
- **授予**：`win_pool_mgr` **零改动**（`avail = pool + old − occ_port`）。
- **不做孤儿项**：孤儿占用由授予式的 `− occ_port` 守住（新连接拿不到被孤儿占用的配额）；
  对已建立连接的 fq 不再二次扣孤儿（否则一次 churn 会把全口窗缩小 ~12KB、触发现在飞段被拒）。

### 2.1 物理安全（v2 复审的 M-1 修正版）

承重机制 = **未改的授予式**，不是 fq 代数：

1. 授予 `g ≤ pool + old − occ_port`，释放按槽 `winq` 归还 ⇒ 不变量
   **`Σ winq_i + occ_port ≤ WIN_POOL (96KB)`**（`rtl/win_pool_mgr.v:260-261,402-404`）。
2. `fq_i ≤ winq_i` 恒真（公式保证）；活连接最多超额 `ACC_MARGIN + SEG_MAX`
   （`rtl/tcp_rx.v:317-318` 的接受界）。
3. 物理预算（与 `board/wrapper_p4.v:1649-1662` 同式）：

```
Σwinq 98,304 + N*ACC_MARGIN 26,624 + Δ 2,816 + U 1,518 + SEG 1,500
= 130,762 ≤ FIFO 131,072  ⇒ 余 310 B
```

孤儿数据：其占用在 `occ_port` 里，授予式保证 `Σwinq + occ ≤ 96KB`；孤儿随 app 消费
（每个实例的 RX 校验器即使 inactive 也消费）而下降，`winq` 不因此增长（C15 在 EXT 关闭）。
⇒ **不需要 `occ_orphan`**。

---

## 3. 实现

### 3.1 tcp_echo（`PER_CONN_OCC=1` 生成；默认 0 逐位不变）

新参数 `PER_CONN_OCC`；新端口：
`input [3:0] i_occ_rd_id`（复用 wrapper 的 `o_winq_rd_id`）、`output [16:0] o_occ_rd`、
`output reg [31:0] stat_occ_underflow`、`output reg [31:0] stat_cq_ovf`。

**计数器**：`occ[0:15]`，内部 18 位，输出饱和 17 位（131,071）。

**帧内快照（H-1 修正）**：
```
wire       cid_w = first_b ? meta_conn_id : cur_cid;
wire [7:0] cw_n  = first_b ? 8'd1          : cur_words + 8'd1;
```
- `accept && first_b`：`cur_cid <= meta_conn_id;`
- `accept`：`if (judged) cur_words <= 8'd0; else cur_words <= cw_n;`
- `judged`：`rb_cid <= cid_w; rb_words <= cw_n;`（**含末字**；单字帧 first_b=1 ⇒ cid/count 正确）
- `cur_words` 8 位（1518B=190 字）。

**每项单写口 delta 合成（H3c）**：
```
for k in 0..15:
  delta_k = (wr_ev && cid_w==k ? +8 : 0)
          + (rd_ev && rd_cid==k ? -8 : 0)
          - (rb_ev && rb_cid==k ? 8*rb_words : 0);   // rb_ev = rback 拍
  occ[k] <= sat_signed(occ[k] + delta_k);             // 下溢钳 0 + stat；上溢饱和
```
- `rd_cid = cq_dout`（帧内稳定，`tcp_echo.v:95,119`）。
- 同槽同拍读写净额 0；回卷拍 `s_axis_tready=0` ⇒ 回卷与写不同拍（H5）。

**cq 安全（H-2 修正）**：
- **帧边界前置门**：`s_axis_tready = !fifo_full && !rback && (!first_b || (fq < CQ_DEPTH-2))`。
  - `fq` 是已判定好帧数（队列占用）；`CQ_DEPTH = 1<<CQ_AW`（128）。
  - 满门在**帧首**挡住，tcp_rx 保字（AXIS 反压），**不丢好帧**；app 排空后继续。
  - 由此 `fq ≤ 127`、cq 永不满 ⇒ **fq 7 位不回卷、cq 无静默丢 cid**。
- `judged && cq_full` 只为防御：置 `stat_cq_ovf` 并**保持 tready 低直到有空间**（不设
  `rback`、不丢帧）；正常路径由前置门保证不可达。
- 默认（PER_CONN_OCC=0）**不加**前置门 ⇒ 与 0x34 逐位等价；现役 128 深/fq 7 位的
  潜伏问题登记到 OPEN_ITEMS（下一轮或无条件修）。

**occ 读口**：`o_occ_rd = occ[i_occ_rd_id]`（16:1 mux，组合；与 winq 读口同址同拍）。

### 3.2 app_ctrl（`PER_CONN_OCC=1`）

- 新参数 `PER_CONN_OCC`；新输入 `i_occ_rd[16:0]`（地址复用 `o_winq_rd_id`）。
- `fq_occ(q) = max(0, q − i_occ_rd)`（17 位饱和减法）：
  - 扫描 `:973`、init redge `:1166-1167`、init fc `:1190`；
  - **T+2 fc 仍用 `pb_wscan`**（锁存值），不加 occ_pb。
- `rx_occ_bytes` 保留（默认路径；OCC=1 时只作诊断）。
- 不改扫描/init 流水、不改 `wu/redge` 结构；不新增 live_mask（v3 无孤儿项）。

### 3.3 wrapper / 开关 / 几何

- `tcp_echo`/`app_ctrl`：`.PER_CONN_OCC(P11_APP8_OCC)`；`i_occ_rd_id/o_winq_rd_id`
  同一根线；`o_occ_rd → i_occ_rd`。
- 新宏 **`P11_APP8_OCC`**（独立于 `P11_APP8`）：必须同时 `P11_APP8=1 && P11_DUAL=1`
  （build tcl 硬失败）。
  - **0x34** = `P11_APP8=1, OCC=0`（同合同同 app）→ 负对照臂，**必须先构建/归档**；
  - **0x35** = `P11_APP8=1, OCC=1` → 修复臂。
- `win_pool_mgr` 零改动。
- 快照 **NW 97 不变**；`stat_occ_underflow/stat_cq_ovf` 不进快照（§5.3 明写无直接见证）。

---

## 4. 零回归

- `PER_CONN_OCC=0`：tcp_echo 不生成 occ/门；app_ctrl 不生成 occ 口；win_pool 未改
  ⇒ **与 0x34 逐位等价**（锚 = 0x34 位流；不是 0x33 的 2×48KB）。
- 核对折叠面：`tcp_echo` 的 `fq/cq/s_axis_tready`、`app_ctrl` 的 3 个 fq 求值点、
  `win_pool_mgr` 全文件、wrapper 的 `rx_occ/NW/BID`；新增口在所有 `tcp_echo` 例化点
  悬空（具名连接；grep 清单）。

---

## 5. 验证

### 5.1 单元/结构门（含必红项）

| # | 判据 |
|---|---|
| O1 | 2 tid 交错（长帧 + 1B 短段）：逐拍 occ_i = 参考模型；同槽同拍读写净额 0；另一 tid 不受影响 |
| O2 | **坏帧单字/多字各一**（紧跟 1–2B 好帧 + 反压恢复）：回卷后 occ_i 精确相等；**末字计入 rb_words**；无下溢 |
| O3 | **内容不丢**：128 个 1B 好帧 + app 停读 → 放行：app 实收字节 == tcp_rx 接受字节；`stat_cq_ovf=0`；`fq ≤ 127` 逐拍断言 |
| O4 | 帧边界门：`fq=126` 时新帧 tready 低；app 排空后自动恢复；无死锁 |
| O5 | app_ctrl：仅槽 2 occ=12KB ⇒ 槽 2 fq=0，其它槽 fq=12KB；occ=6KB ⇒ 6KB |
| O6 | `Σwinq + occ_port ≤ WIN_POOL` 逐拍断言（含 ev_up/ev_down/churn） |
| O7 | win_pool_mgr 与 0x34 逐位相同（未改）；C18 同槽复用仍正确 |
| O8 | `PER_CONN_OCC=0` 折叠：0x34 TB/位流等价锚 |
| O9 | 变异门（每个必须使对应门红）：① occ 用全局；② `rb_words<=cur_words`（少末字）；③ 删帧边界门；④ `rb_cid<=cur_cid`（单字帧）；⑤ 读侧不扣 occ |

### 5.2 全链/矩阵

- `p5d_multi` 主臂+三负控；8 连接 xsim（8 EVUP + 上行灌数据 + 逐连接窗/occ）；
- 41 门矩阵 + 新门 `app8`/`echo_occ`（42/43，manifest/runner 同步）。

### 5.3 板级（0x34 负对照 vs 0x35）

- **施工顺序**：先构建/归档 **0x34**（OCC off），核 BID 0x34/NW 97；再 0x35。
- **前置**：8 条连接**全部建连完成后**再开始灌流（否则第 8 条的授予 <12KB 与缺陷不可分）。
- **上行臂 = 双向**（APP8 的 8 个 app_pattern 写死 `TX_CONTINUOUS=1`，无法单关；
  TX_DIS/`0x08` 会断 carrier）⇒ 明写"双向流量 + ACK 共享 TX 线"，窗观测用 tcpdump。
- **主见证 = tcpdump 逐连接 ACK 的 window 字段**（不是 `ss -ti`；全局 #82）；
  辅助 = W62（全局 occ ≤128KB）、`ΔW53 == PC 发送字节`、`ΔW54=0`。
- **负对照**：0x34 在高 occ 时多连接窗塌；0x35 不塌才构成判别。
- **无直接记账快照**（明写）：`stat_occ_underflow/cq_ovf` 板上不可见；要直接见证另轮加 1 字
  （NW 98 / BID 0x36，96 FF/字）。
- 第 9 条拒绝；0x35 下行 8 连接回归。

---

## 6. 时序 / 资源 / backstop

- 改动：tcp_echo 16×18 计数器 + 每项 delta 合成 + 16:1 读 mux + 帧边界门（1 个比较）；
  app_ctrl 的 `fq_occ`（17 位饱和减法，与现役 fq_calc 同量级）。
- **验收 = 全构建 `P7B_TIMING_GATE`**（WNS>0 ∧ 0/0/0）；synth 只作资源检查
  （0x33 通过臂 synth 也为负 ⇒ 无判决力）。
- 策略预登记 `Performance_ExtraTimingOpt`（0x33 通过臂；新输入）。
- backstop：WNS<0 或端点>0 ⇒ 不烧/归档/登记；不重跑到过。
- 定向 STA：`occ[*]` RMW 锥、`occ 读口 → fq_occ → redge_n` 锥。

---

## 7. 已知边界（写进报告）

1. **授予折扣**：win_pool 保留 `− occ_port` ⇒ 建连时有占用则新连接可能 <12KB；
   板级协议要求"先建连后灌流"。
2. **默认路径的 cq/fq 潜伏问题**（128 深/7 位）不在本件修（PER_CONN_OCC=0 保持逐位）；
   登记 OPEN_ITEMS。
3. **TX HOL**：单帧器共享，一条零窗连接可挡其余 7 条（上一轮 M5）；产品语义边界。
4. **无直接记账快照**（见 §5.3）。


---

# v4 修订（终审条件处置）

| 终审条件 | v4 |
|---|---|
| **V3-H1 板级前件不可达（occ 常≈0）** | 增加**测试专用 RX 停顿注入**：复用 `0x08` SCRATCH 的**空闲 bit2**（bit0/1 = SFP1/2 TX_DIS），`app_rx_stall = pcie_scratch[2]`，在 wrapper 把 `eco2_tready` 与 `!app_rx_stall` 相与（APP_MODE；复位 0 ⇒ 零回归）。板级判据**前件 = 测量窗内 W62 > 12KB**，不满足记【空判据/未执行】，不记 PASS。判别构型 = **一条连接灌流、其余 7 条空闲**（单 conn occ 涨、其它 0）：0x34 全局扣 ⇒ 空闲 7 条窗也塌；0x35 per-conn ⇒ 空闲 7 条窗保持≈12KB。 |
| **V3-M1 O6 时刻错** | O6 分两段：① 在 manager `S_COMMIT`（用 `s_occ`）断言 `Σwinq_after + s_occ ≤ WIN_POOL`；② 逐拍只断**预算形** `Σwinq + occ ≤ 130,762`（或 FIFO 131,072）。§2.1 加"不变量在授予/释放**事件时刻**成立"限定。 |
| **V3-M2 cur_words 8 位不足** | `cur_words/rb_words` 改 **14 位**（`8*rb_words` 18 位）；覆盖 MAC 超长帧（4096B=512 字）。 |
| **V3-M3 帧边界门 → 上游 MAC 丢帧/HOL** | **登记为已知边界**（短段洪泛 + app 停读 ⇒ mac 丢帧，靠 TCP 重传；全口 RX HOL 与 TX HOL 对称）；**不**把 cq 余量并入通告窗（本轮范围）。TB 增加 200×1B 段 + 停读臂：断言门接住、恢复后全部收齐（允许重传）。 |
| **V3-M4 occ 读口跨模块组合跳** | 先**定向 STA 预量** `occ_reg[*] → i_occ_rd → fq_occ → pa_fq_reg`；若为瓶颈，再在 app_ctrl 给 occ 打一拍（带同拍 id 延迟）。§6 措辞改为"新增 16:1 mux + 17 位减法 + 跨模块布线，待 STA"。 |
| **V3-M5 变异/门生效** | O9 增 2 个变异：`s_axis_tready` 漏 `!rback`；门阈值 `CQ_DEPTH-2→CQ_DEPTH`。O3 增"门关闭周期数>0 且 127/128 帧最终全部收齐"；O4 增"门关闭时 `stat_cq_ovf` 恒 0"。 |
| L-1 `cq_full` 防御分支不可实现 | 删"保持 tready 低"叙述；只留 `stat_cq_ovf` 计数 + `assert(fq<=126)`（构造不可达）。 |
| L-2 阈值 | 统一 **fq ≤ 126**（门阈值 `CQ_DEPTH-2`；1 格给在飞帧、1 格给 cq_full 判据）。 |
| L-3 证明限定 | ① 不变量是**事件时刻**；② fc T 采样/T+2 写入的 2 拍 staleness 最多 +2 字 = **16 B**，落在 `ACC_MARGIN` 3328 B 内（stale-high ≤16B，安全）。 |
| L-4 授予折扣量化 | 第 k 条建连 `winq_k = min(0x3000, pool+old−occ_port)`：occ_port 每多 1 B，该条配额少 1 B。测试工具必须 8 条 `connect()` 全部返回后才 `send()`。 |
| L-5 默认 cq/fq 潜伏项 | 写入 `P7B_OPEN_ITEMS.md`（条目名 = "P11 APP8: tcp_echo cq 128/fq 7 位在 PER_CONN_OCC=0 下的短段洪泛潜伏"），不只在设计件里。 |
| L-6 例化点 | 列出全部 `tcp_echo` 例化（`board/wrapper_p4.v` ×2、`tb/*.v`、`sim/` 镜像件）；`PER_CONN_OCC=0` 时新输入悬空/接 0 均可，未接不得引入 X 消费者；grep 清单入施工记录。 |

## v4 板级判别臂（V3-H1 的具体化）

1. 0x34 先构建/归档；0x35 后构建。
2. 8 条连接**全部建连**（PC 工具 `--conns 8`，全部 connect 返回后再 send）。
3. 设 `0x08 = 0x4`（bit2=1，RX_STALL；bit0/1=0 保 TX 开）→ 板内 app 停读。
4. PC 只在 **conn0** 发图案（`--send-conns 1`，按 maxbytes/seconds），其它 7 条不发；
   PC 同时读取板的下行（双向臂，明写）。
5. 等 W62 > 12KB（tcpdump/快照），用 **tcpdump 逐连接 ACK 的 window** 读 8 条窗：
   - 0x34：conn1..7 的窗也塌到 0（全局 occ 扣）；
   - 0x35：conn1..7 的窗保持≈12KB，conn0 塌（per-conn occ）。
6. 清 `0x08=0`（释放停读），排空；第 9 条拒绝。
7. 前件不满足（W62 未 >12KB）⇒ 记【空判据/未执行】，不记 PASS。

## v4 新增工具需求

- `p7b_tcp_sink_multi` 增 `--send-conns N` / `--send-bytes B` / `--send-pattern`（每连接从偏移 0
  xorshift），同线程内 send+recv；输出 `MULTI_SEND ...` 与 `MULTI_SUM`。
- 板级脚本设/清 `0x08 bit2`，并记录 `W62` 序列。


---

# v5 修订（v4 终检条件处置）

| 条件 | v5 |
|---|---|
| **H-1 停读只门 tready 打断握手** | **双门**：`app_rx_tvalid_i = eco2_tvalid && !stall` **且** `eco2_tready = app_rx_tready && !stall`（两侧同时看不见该字；pipe 保持、app 不消费）。不改 app_pattern。 |
| **H-2 空闲连接无 ACK，窗不可观测** | 停读并等 `W62>12KB` **再等一轮扫描**（≤256 拍/槽）后，对 conn1..7 **各发 1 B 探针**（窗内会被收下并回 ACK；0 窗也因 ACC_MARGIN 被收下）；tcpdump 只取 **src=板 MAC、对应 4-tuple 的 ACK** 的 `win` 作见证。判据 = conn1..7 的板侧 ACK win：0x34≈0 / 0x35≈12KB。 |
| **H-3 pcie_scratch 仅在 PCIE_OBS 内声明** | `app_rx_stall = (PCIE_OBS && P11_APP8) ? stall_sync : 1'b0`；其它构建恒 0（含 APP_MODE-only 的 p5_wrapper 门）。 |
| **M-1 跨时钟域** | `pcie_scratch[2]`（pcie_axi_aclk）→ dp_clk **2-FF 同步**（`stall_sr <= {stall_sr[0], pcie_scratch[2]}`），复位 0。 |
| **M-2 O6 断言仍假** | 逐拍：Ⅰ `occ_port ≤ 130,762`；Ⅱ `Σwinq ≤ WIN_POOL`。`S_COMMIT`：`Σwinq_after + s_occ ≤ WIN_POOL` **且** `Σwinq + pool == WIN_POOL`（后者独立有牙）。删“逐拍 Σwinq+occ ≤ 130,762”。 |
| **M-3 只打拍 occ 会混槽** | 若 STA 需要流水，**同时寄存 `{id, winq, occ}`**（或直接寄存 fq 结果）；**不单打 occ**。 |
| L-1..L-5 | `0x08` 读回在停读期为 0x4：身份/负对照脚本不得再以 `0x08==0` 作“TX 开”的唯一见证（用 carrier）；写 `0x08` 必须显式 bits[31:2]=0；停读只对 port0/APP8；探针前等扫描传播；v5 的“零回归”写成“PCIE_OBS∧P11_APP8 之外恒 0”。 |

## v5 板级判别臂（最终）

1. 0x34 构/归档 → 0x35 构建；8 连接全部建连后才灌流。
2. `0x08 = 0x4`（RX_STALL；bits0/1=0 保 TX），PC 只在 conn0 发图案并持续读取。
3. 等 `W62 > 12KB`，再等 ≥256 拍/槽的扫描传播。
4. 对 conn1..7 各发 1 B 探针；tcpdump 抓 **板→对端 ACK**，按 4-tuple 取 `win`。
5. 期望：0x34 conn1..7 win≈0；0x35 conn1..7 win≈12KB（conn0 两臂都≈0）。
6. 清 `0x08=0`；排空；第 9 条拒绝；下行回归。
7. 前件（W62>12KB）不满足 ⇒ 【空判据/未执行】，不记 PASS。
