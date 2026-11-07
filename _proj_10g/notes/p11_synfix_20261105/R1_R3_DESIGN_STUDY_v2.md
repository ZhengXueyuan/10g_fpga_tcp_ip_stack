# R1 半开泄漏 / R3 pending / FIN-RST seq —— 设计 v2（对 xr13 审查的逐条处置，2026-11-08）

> 输入 = `R1_R3_DESIGN_STUDY.md`（v1，只读研究）+ `R1_R3_DESIGN_REVIEW_xr13.md`（对抗审查）。
> 本文 = **开发组处置 + 修订设计**；仍未实施、未构建。状态词按工程口径。
> 行号均为本次现读。

## 0. xr13 处置总表

| # | 级别 | 处置 | 要点 |
|---|---|---|---|
| H-1 | 高 | **接受**（设计改） | `slot_dead` 改**边沿语义**（HLS 自持 `dead_seen`），并把清零点定在 **demux 捕获 ADD 记录（S_ROUTE）那一拍**；补延迟预算（§2.3）。板级加竞争臂。 |
| H-2 | 高 | **接受**（补映射表） | 槽号是**恒等映射**：`cfg w0[3:0] = HLS cid = slow_cfg_adp 的 cam/TCB 索引 = app_ctrl 的 4 位槽号`；cid 全局唯一（同一时刻只属一个端口）。`slot_dead` 用**全局 8 位 cid 位图**（cid 0..7；demux 已结构性丢弃 slot≥8 的记录），任一端口的 ADD 记录可清该 cid（不按端口分维）。见 §2.1/§2.2。 |
| H-3 | 高 | **接受**（R3-1b 加互斥门 + 排序改判） | R3-1b 必须加 `!tx_req.request` 门；它只修"忙窗恰在 B 完成前结束"的同 pass 竞态，**ARM_B2/§0-88 必须 R3-1a**。v1 的"风险极低"改判 **中低**。 |
| M-1 | 中 | **驳回（前提不成立）** | `o_ev_down` 去的是 **app 事件口**（`wrapper_p4.v:1986 → app_ev_down → app_multi8/app_pattern 的 ev_down`，`:1788/1828/1893`），**不是** `slow_cfg_adp`。`slow_cfg_adp` 的 `ev_down` 是它**输出给 app_ctrl** 的（`slow_cfg_adp.v:22-23,179-181`）。⇒ orphan fire 不会释放 HLS 槽，`i_slot_dead` 是**必要**路径，不存在"双释放路径"。 |
| M-2 | 中 | **接受** | 把"ADD init 立即刷新快照（`app_ctrl.v:1185`）"与"false-reject 由 RST 无校验分支兜底"写进判据与验证清单。 |
| M-3 | 中 | **接受** | `ack_obs` 只在 `` `ifdef TCP_TX_OVL `` 内（`rtl/tcp_rx.v:620-623`）⇒ 构建门必须 `P11_R1_AGING ⇒ TCP_TX_OVL=1`，否则禁用老化。 |
| M-4 | 中 | **接受** | SYN 重传复位不是自动的：经 bare-SYN 回收（`hls/src/layer_tcp.cpp:657-677` DEL+ADD）才有新 `ev_up`；代价 = 半开态 CAM/TCB 每次重传闪断一次（无在途数据 ⇒ 安全）。 |
| L-1 | 低 | **驳回（已核）** | HLS `ap_clk = dp_clk`（`board/wrapper_p4.v:4025`），与 app_ctrl 同域 ⇒ **无需 CDC**。 |
| L-2 | 低 | **接受** | 存储估计重写：2 深 pending 需 `{ip_rx_t, smac, nwords, 头 32 字}`，≈2×(32×32 + 32) FF ≈ 2.2k FF（或 1 BRAM tile + 少量 FF）；仅控制面帧走 pending（数据帧走 `tcp_queue`，`:153-156`）。 |
| L-3 | 低 | **接受** | 验证清单加：H-1 竞争臂（老化 fire 与 SYN 重传同槽相邻）、H-2 跨端口同号臂。 |

## 1. 槽号空间映射（H-2 的答案）

| 项 | 值 | 证据 |
|---|---|---|
| HLS 连接号 `cid` | 0..7（现役 `MAX_TCP_CONN=8`） | `hls/src/layer_tcp.cpp:13-14` + 构建宏 |
| cfg 记录 w0 | `(wscale<<16) | (cmd<<8) | slot`，`slot = w0[3:0]` | `slow_cfg_adp.v:5-8, 99, 190` |
| slow_cfg_adp 索引 | `slot` 直接作 `cam_cfg_addr` / `upd_id`（**本端口 16 槽空间**） | `slow_cfg_adp.v:158, 176-178` |
| 端口选择 | demux 按 `local_ip` 路由；每端口独立 `slow_cfg_adp` + `u_tcb`/`u_tcb2` | `wrapper_p4.v:2843, 3960` |
| app_ctrl 视图 | 每端口 16 槽，索引 = 同一 `cid` | `app_ctrl.v` `c_rcv_nxt[0:15]` / `orph_*[15:0]` |
| 全局唯一性 | 一个 cid 同一时刻只属一个端口（HLS 表项唯一） | HLS 单表 |
| **`slot_dead`** | **全局 8 位、按 cid 索引（0..7）**；置位 = 任一端口的 `ho_fire`（cid）；清零 = **demux 在 S_ROUTE 捕获到 `is_add` 的那一拍** + 同 cid 的 `ev_up/ev_down`（demux 已丢弃 slot≥8 的记录 ⇒ cid 域天然 0..7） | 本文 §2；`slow_cfg_demux.v:6-14,70-80` |
| 时钟域 | `ap_clk = dp_clk`（HLS 与 app_ctrl 同域） | `wrapper_p4.v:4025` |

⇒ 不存在 16↔8 换算；H-2 指出的"裸 cid 会撞车"在**全局唯一性**下不成立；但 v1 文档没写这张表 = 真缺口，本表补上。

## 2. R1-O1 修订设计（H-1/H-2/M-3/M-4 处置后）

### 2.1 快路径（`rtl/app_ctrl.v`）
- 复用 orphan 拆除机（`:1586-1687`），新增半开模式：
  - `reg [15:0] ho_ack_seen`：`ack_obs` 置位、`ev_up/ev_down_i` 清零。
  - `reg [7:0] ho_cnt[0:15]`：`ho_accrue = orph_scan_gate && c_state==ST_ESTAB &&
    !ho_ack_seen[scan_id] && !fin_sent && !rst_sent && !st_done && !to_fired`；
    tick = `ORPHAN_TICK_BITS`（18 ⇒ 429.5 ms/计数）。
  - `ho_fire` 与 `orph_fire` 同形（state=0 + CAM 清 + `o_ev_down` 通知 app），
    **不走 `to_fire`**（不发 RST）；**静默**语义 = 不对对端发任何帧（app 通知是本地语义，见 M-1 驳回）。
  - 阈值 `HO_LIM=8`（≈3.44 s）。
- 新增输出 `o_slot_dead`（8 位 cid 视图；置位语义由 wrapper/demux 汇成全局 8 位位图）。

### 2.2 wrapper 的全局 `slot_dead`（H-1 边沿语义的基础）
(注: cid 域 = 0..7; slow_cfg_demux 已结构性丢弃 slot>=8 的记录 ⇒ 位图 8 位足够)

```
reg [7:0] slot_dead;
always @(posedge dp_clk ...) begin
  if (ho_fire_p0 & (ho_cid_p0<4'd8)) slot_dead[ho_cid_p0[2:0]] <= 1'b1;
  if (ho_fire_p1 & (ho_cid_p1<4'd8)) slot_dead[ho_cid_p1[2:0]] <= 1'b1;
  if (cfg_add_hit)  slot_dead[cfg_cid[2:0]] <= 1'b0;     // demux S_ROUTE is_add, 见 2.3
  if (ev_up_pX | ev_down_pX) slot_dead[ev_slot[2:0]] <= 1'b0; // 同 cid, 任一端口
end
```
- `cfg_add_hit` = `slow_cfg_demux` 在 **S_ROUTE 捕获完整 8 词记录**且 `is_add`（`rec0[15:8]==0`）那一拍给出的脉冲 + `slot`。
  这是现有模块内即可加的一根线（`slow_cfg_demux.v:70-80` 已解析 cmd/slot）。
- 该位图喂给 `u_hls.i_slot_dead[7:0]`（新端口，宏 `P11_R1_AGING` 门控）。

### 2.3 HLS 侧（`hls/src/udp_echo.cpp` + `layer_tcp.cpp`）
- 新增输入 `i_slot_dead[7:0]`（宏 `P11_SLOT_DEAD` 门控，端口存在性门仿 `P11_HLS_ADV_WND`：
  `wrapper_p4.v:4042-4046`、`board/p11_build_cfg.tcl:15-35/69-85`）。
- 每个 pass 开头、处理本帧之前：
  ```
  for i in 0..MAX_TCP_CONN-1:
      if (i_slot_dead[i] && !dead_seen[i]) { tcp_conn[i].state = T_FREE;
                                             tcp_conn[i].retrans_pending = false; }
      dead_seen[i] = i_slot_dead[i];        // 边沿/回退两态都跟随 ⇒ 下次 0→1 再触发一次
  ```
  **绝不 `cfg_write`**（H-1 的连环杀根因就是电平重复杀；边沿后同一电平只杀一次）。
- **延迟预算（H-1 要求）**：清零发生在 `slow_cfg_demux` **捕获完整 8 词记录**的 S_ROUTE 拍。
  预算 = demux 输入 FIFO 最多 16 词（2 条旧记录）+ 本记录 8 词捕获 = **≤24 拍 ≈154 ns**
  （1 词/拍，dp 156.25 MHz）；而"重建该 cid 的新 SYN" 触发的下一 HLS pass 至少相隔一个
  控制帧到达周期（10G 下 ≥ 数百拍；8 连同时建连时也 ≥ 数十拍）⇒ **清零先于下一 pass 观测**。
  ⚠️ 原先 v2 草稿把清零点写成"w0 第一词"，现按 demux 实际结构（整记录捕获后 S_ROUTE 才判口）
  订正为 S_ROUTE 拍。
  ⚠️ 这是**拍级预算论证**，不是形式证明；板级竞争臂必须做（§3 L-3）。
- 若预算被打破（极端背压）：失败形态 = 新建连被误杀 ⇒ 对端 SYN 重传（1 s）重建 ⇒
  **秒级建连延迟，自愈**；不会永久占槽（老化只对 `!ack_seen` 的 ESTAB 生效，活连接 ACK 后不再老化）。

### 2.4 构建门（M-3）
- `P11_R1_AGING=1` 要求：`P11_APP8=1 && P11_CFG=c4 && TCP_TX_OVL=1`（`ack_obs` 非恒 0）。
  构建脚本加断言，否则 `P11_VERDICT = R1_REQUIRES_OVL` 并停。
- 默认关闭（参数/宏默认 0）⇒ 既有构建逐位不变。

## 3. 验证清单（补 L-3/M-2）

| 项 | 判据 |
|---|---|
| csim mask 语义 | 填 8 个半开 → 置 mask 位 → 新 SYN：SYNACK=1、**DEL=0**、ADD=1、槽 T_FREE；mask=0 臂保持 `P11_TB_HALFOPEN_*` 原断言 |
| csim 边沿语义 | 同一位保持 1 连续 3 个 pass：只释放一次（`del_count=0`、`free_count=1`） |
| 板级正臂 | 8 个原始 SYN 填半开 → 等 >3.5 s → 再打 8 个原始 SYN：W7 +8、W52 estab=8（负臂 0x3F：+0..2） |
| 板级活连接安全臂 | 8 条真实连接带数据、空闲 >3.5 s（有 ACK 历史）→ 仍能收发、正常 FIN 关闭 |
| **板级竞争臂（H-1/L-3）** | 老化 fire 与同槽 SYN 重传相邻到达：强制 `ho_fire` 后 0–2 pass 内发回同四元组 SYN，断言不出现"秒级建连延迟"或卡死 |
| **跨端口同号臂（H-2/L-3）** | port0 cid=3 老化 + port1 新建同号 cid：port1 连接不受影响 |
| R3-1b | csim ARM_B2 期望改 2/2？**不**（R3-1a 才改）：R3-1b 单独仍 1/2（H-3），判据 = "忙窗在 B 完成前结束" 臂 1/1；ARM_B2 归 R3-1a |
| R3-2b | 伪造 FIN（错 seq）连接存活；正确 FIN 正常关闭；ADD 后立即发旧 FIN 被拒（`app_ctrl.v:1185` 刷新） |

## 4. R3 修订

### R3-1b（互斥门）
在把 `:257-260` 前移之后，补做完成后**本 pass 不得再处理新帧 B 的 tcp_send**：
`if (served_pending && tx_req.request) → 把 B 挂 pending（或直接 return）`。
同时把 v1 §0 排序表的"风险极低"改 **中低**，并注明 **ARM_B2/§0-88 闭环 = R3-1a**。

### R3-1a（补全）
2 深 pending FIFO，元素 = `{ip_rx_t, smac, nwords, 头 32 字}`；仅在 `mac_tx_busy` 或
`tx_req.request` 时入队；服务时一次一项。存储 ≈ 2×(32×32 + 32) FF（或 1 BRAM + 少量 FF）。
数据帧不走本路径（`tcp_queue` 拷贝前提，`:153-156`）。

### R3-2b（FIN/RST seq 校验）
- 判据加两条消解论据（M-2）：
  1. ADD init 立即刷新该槽 `c_rcv_nxt` 快照（`app_ctrl.v:1185`）⇒ 快速重连 + 旧 FIN 必被拒；
  2. 合法 FIN 的 false-reject 由 RST 无校验分支兜底（`layer_tcp.cpp:678-690` 注释自承）。
- **RST 分支**同样需要 seq 校验（v1 §3-1 已登记；与 R3-2b 同批设计，独立审查）。

## 5. 施工顺序建议（不变 + H 处置）

1. **一批**：R1-O1（含 §2.1–2.4）+ R3-1b（含互斥门）⇒ 一次 HLS 重综合 + 一次 RTL 构建；
   timing 先沿用 0x3F 的通过档 `Congestion_SpreadLogic_low`。
2. **单独一批**：R3-1a + R3-2b（含 RST seq）。
3. 每批前：定向 STA `u_tcp_tx/u_fifo_* → u_tcb/*`、`u_app_ctrl/init_*→orph_*`；
   0x3F 的 WNS +0.037 是薄余量，新逻辑必须一次构建收口。

## 6. 仍未闭合（不许当已答）

- H-1 的拍级预算是**论证**，板级竞争臂未做；若板级出现秒级建连延迟，按"自愈但需定位"登记。
- H-2 的"cid 全局唯一"依赖 HLS 表项语义；现役 demux 已硬性丢弃 slot≥8（`slow_cfg_demux.v:12-14`），
  若未来 MAX_TCP_CONN>8，位图与 demux 的丢弃门必须同步扩（并带端口维）。
- L-2 的存储数字是估算，未综合。
- 观测面：`ho_fire` 计入 `stat_orphan`（`app_ctrl.v:1686`）会混语义；**本轮不扩快照几何**
  （NW=98 / UNIMPL 0x1B8），用 W52/W7 做判据。
