# W51–W54 / W71–W74 恒 0 —— 证据、排除项与下一轮判别计划

状态：**【未定位】**（2026-10-29 0x36 板级新发现；`P7B_OPEN_ITEMS §0-80`）。
影响：观测面（app 统计字不可用）；**数据面已用独立 oracle 验证**（下行 `p7b_tcp_sink` 逐字节、
上行 W97[15:8]）。OCC A/B 的主见证是 tcpdump 窗口，本缺陷不阻断它（另有 §0-81 阻断）。

## 1. 现象（板级，0x36）

- 触发快照（`0x18=1`，等 `0x1C done`，gen 恰好 +1）后读：**W51–W54 = 0、W71–W74 = 0**。
- **流量进行中** 3 次采样（8 连接下行已收 3,221,334,960 B；`W84` 0x16a7d → 0x244872）仍全 0；
  同一快照里 W65/W76/W79/W80/W83/W84 均非 0 ⇒ 快照装配/触发本身正常。
- 同刻 **W97 = 0x20**（locked=1、无 stale/超时/复位/失配）⇒ 统计握手"没有报错"。
- 数据内容：`p7b_tcp_sink` 100 连接 × ~1 MiB = 107,052,876 B，`mismatch_bytes=0`、`stall=0`；
  8 连接 `seq` 8/8 status=0、mism=0；上行 8×12,288 B（`unsent=0`）⇒ W97[15:8]=0。
  即：**app 在产数据且内容正确，只有它的统计字读不到**。

## 2. 已排除 / 已核（综合网表，0x37 构建前从 routed DCP 查得）

- `u_app/st_hold_reg[*]`：C = `u_app/clk_app`（来自 `u_appclkgen/g_real.u_bufg_out/O`，BUFGCE），
  CE = `st_ack_i_1`（`st_req_sync[1] != st_ack` 的 LUT2），D = `u_app/core_tx_bytes[*]`
  （= 8 个 app 实例计数器的求和锥，CARRY8 输出）。
- `u_app/st_shadow_reg[*]`：C = `u_app/dp_clk`，CE = `st_req1`，D = `st_hold[*]`。
- 两 bank 各 **320 cell**（4 位 close_pend_max 因常量 0 被优化），不是被剪掉。
- `stat_tx_bytes_reg[0]`（app0）为 **FDCE**，CE = `u_app/u_core/g_app[0].u_app_i/pw_take`
  （RTL `pw_valid && m_tready && !closing`），该网存在且 47 个负载。
- 单元 TB（`tb_app_multi8_cdc`）在 **6.23/6.4 ns 漂移** 与 **6.4/6.4 ns 同频** 两种时钟比下，
  "stats handshake live（shadow 非 0 且有界滞后）"均 **PASS**。
- ⇒ 结构（时钟/CE/数据锥/复位域）在网表上是对的；**板上行为与仿真不一致**，未定位。

## 3. 候选假设（都未证）与判别实验

| # | 假设 | 判别（一次构建 + 板读） |
|---|---|---|
| H1 | `st_req` 在板上不翻转（DP 侧 stats 机停） | 把 `{st_ack_sync[1], st_req}` 接到 **W97[1:0]**（现保留 0），重建后**多次读**：req 应每 ~6.55 µs 翻转、ack 跟随。若 req 不动 ⇒ 看 `st_tick`/`st_wait`。 |
| H2 | app 侧不 ack（`st_ack` 不翻） | 同上：req 翻而 ack 不动 ⇒ app 时钟域 stats 机停（但 app 数据在跑 ⇒ 可疑点 = `st_req_sync`/`rstn_app_board`）。 |
| H3 | hold 采样到 0（计数器 CE 不触发） | 新字 W98（调试构建）= `{pw_take, st_tick[9:0], core_tx_bytes[0]}` 或 `pw_take` 的粘滞计数；若 `pw_take` 从不脉冲而数据在流 ⇒ 数据走的是别的接受路径（与 RTL 阅读冲突，必须查）。 |
| H4 | 320 位 hold 总线的综合/布局问题（数据在 ack 时未稳定） | 把 hold 改成"两级"（ack 前一拍先寄存数据）或把 hold 拆成两半；或读 `st_hold` 的原始位（加 W98/W99）。 |
| H5 | 快照装配把 W51–54 接错源（比如接到另一个 app） | `check_window` 已核对源码装配（`biz_w51 = app_tx_bytes`）；若要板级证，加 W98 = `{app_tx_bytes[0], app_tx_bytes[1]}` 直连（不经 stats 握手）。 |

**推荐顺序**：H1/H2 用 W97[1:0]（零新增字，一次构建即可判别"握手有没有动"）；若握手在动，
再做 W98 直连 `core_tx_bytes[0]`/`pw_take` 判别 H3/H5；最后才动 H4（改结构需重新审查）。

## 4. 构建设计约束（下一轮）

- 新增观测位会动快照装配（NW/UNIMPL/MIR 平移）与读侧几何门 ⇒ 按 0x36 的同一套清单：
  `top_hi`、`check_window --cdc`、`check_snap_top5_wired --cdc`、`check_build_0x36.py` 的基线。
- W97[1:0] 现在是保留 0；改成握手观测**必须同步改 DESIGN §4.6 表与 §7.1 的"保留"判据**
  （否则门会按"必须为 0"假红）。
- 板级判据：在 **无流量** 时 req/ack 就应持续翻转（统计机不看业务）⇒ 空载即可判 H1/H2，
  不需要跑业务，节省板级时间。
