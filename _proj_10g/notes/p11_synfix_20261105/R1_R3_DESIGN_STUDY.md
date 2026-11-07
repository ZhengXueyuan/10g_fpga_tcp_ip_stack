# R1 半开泄漏 / R3 pending 单槽 / FIN-RST seq 校验 —— 只读设计研究（2026-11-07）

> ⛔ **本件已被 `R1_R3_DESIGN_STUDY_v2.md` 取代**（v2 = 对 `R1_R3_DESIGN_REVIEW_xr13.md`
> 的逐条处置 + 修订设计）；本件保留为 v1 原始研究/证据链，**施工以 v2 为准**。
>
> 来源 = 独立只读子代理（未改任何文件、未构建、未上板）；行号为**本次现读**。
> 用途 = 下一轮施工的候选设计；**未实施**，不得当作已收口。
> 关联 = `P7B_OPEN_ITEMS.md` §0-90（R1）/ §0-91（R3）/ §0-88（SYN-under-load）。

## 0. 结论速览（按产品价值/风险排序）

| 排名 | 项 | 建议 | 风险 |
|---|---|---|---|
| 1 | R3-1b（pending 服务前移到新帧入 stage 之前） | 最小改动、csim 可证，先上 | 极低 |
| 2 | R1-O1（fast 侧 `ack_seen` 半开老化 + 复用 orphan 拆除机 + HLS `i_slot_dead`） | 唯一语义正确方向；与 R3-1 同批一次 HLS 重综合 + 一次构建 | 中 |
| 3 | R3-1a（2 深 pending + 帧拷贝） | 补 R3-1b 覆盖不到的"忙窗内两帧" | 中低 |
| 4 | R3-2b/a（FIN/RST seq 校验） | 安全硬化，放 R1 之后单独设计 | 中高 |
| — | 纯 HLS 老化（题目提案的"e.g."） | **否决**：机制可做，语义必杀活连接 | — |

## 1. R1：半开槽永不老化

### 1.1 源码事实链

- 【事实】`tcp_rx_process` 在被动构建只有两个调用点，且都在 TCP 帧完成/补做路径
  （`hls/src/udp_echo.cpp:188`、`:257-260`）⇒ **没有空闲 tick**。
- 【事实】RTO 扫描支在 `hls/src/layer_tcp.cpp:551` 的 `if(!ip_rx.valid||ip_rx.protocol!=6)` 内
  ⇒ 被动构建下结构性不可达；`:560-562` 的 `rto_timer++` 永不执行；`:577-581` 的
  `T_SYN_RCVD` 超时释放是**死代码**（与 §0-90 一致）。
- 【事实】唯一空闲拍调用被 `#if ACTIVE_CONNECT` 包住（`udp_echo.cpp:263-277`），
  宏默认 0（`layer_tcp.cpp:91-93`）。
- 【事实】HLS 无通用时间基：`dhcp_delay` 每 pass +1 但 1e8 后永久关闭（`udp_echo.cpp:133-136`）；
  `layer_stats.cpp:27` 的 `timer` 事件驱动；`tcp_active_tick` 只在 `ACTIVE_CONNECT` 下编译
  （`layer_tcp.cpp:490-539`）。
- 【事实】`T_LAST_ACK` 既不可达也不会老化（`T_ESTABLISHED` 在 P11 是死代码；
  进 `T_LAST_ACK` 的 FIN|ACK 不武装 `retrans_pending`，`layer_tcp.cpp:352`）。
- 【事实】fast 侧唯一可用判别量 = `ack_seen_w`（`board/wrapper_p4.v:2943-2957`；
  置位源 = `rtl/tcp_rx.v:617-623` 的 `ack_obs`；`ev_up` 清位）。
  TCB 的 `state` 在 cfg ADD 时就写成 ESTAB（`rtl/slow_cfg_adp.v:100`、`rtl/tcb.v:101`）
  ⇒ **`rc_state==ST_ESTAB` 区分不了半开与已建立**。

### 1.2 推荐设计 R1-O1（最小可行）

1. 【RTL·app_ctrl】复用 orphan 拆除机（`rtl/app_ctrl.v:1586-1687`），新增半开模式：
   - `reg [15:0] ho_ack_seen`：`ack_obs` 置位、`ev_up/ev_down_i` 清零。
   - `reg [7:0] ho_cnt[0:15]`：`ho_accrue = orph_scan_gate && rc_state==ST_ESTAB &&
     !ho_ack_seen[scan_id] && !fin_sent && !rst_sent && !st_done && !to_fired`；
     tick 复用 `ORPHAN_TICK_BITS`（默认 18 ⇒ 429.5 ms/计数，`app_ctrl.v:322`、`:1019`）。
   - `ho_fire` 接到既有 `else if (orph_fire)`（`:1642`），**不走 `to_fire`**（那会发 RST）；
     **静默拆除**（state=0 + CAM 清 + CONN_DOWN），让对端 SYN 重传重建。
   - 阈值建议 `HO_LIM=8`（≈3.44 s）：1 s/3 s 的 SYN 重传会在到期前重新 `ev_up` 复位；
     7 s 档被拆后仍能重新建连。
2. 【RTL·wrapper】`slot_dead[15:0]` 共享一份（不能两端口各一份后 OR）：置位 = 任一端口
   `ho_fire`；清零 = 任一端口 `ev_up/ev_down` 同槽 **且 cfg ADD 命令字到达 demux 时立即清**。
3. 【HLS】新增 `i_slot_dead`（8 位，宏 `P11_SLOT_DEAD` 门控，端口存在性门仿
   `wrapper_p4.v:4042-4046`、`p11_build_cfg.tcl:15-35/69-85`）；应用点放 `tcp_rx_process`
   的 TCP 帧入口或 `tcp_find`（`layer_tcp.cpp:170-178`）循环内：`state=T_FREE;
   retrans_pending=false`，**绝不 cfg_write**。建议在 pass 开头先应用掩码，再处理本帧
   （避免"刚分配的同槽被同 pass 掩码杀掉"）。
4. 【代价/风险】app_ctrl ≈16+128 FF、数百 LUT（与 `fin_to[16]` 288 FF 同量级）；
   DP 域余量薄（0x3E WNS +0.038）⇒ 必须定向 STA + timing gate。

### 1.3 验证

- csim：新增 `test_p11_slot_dead_mask`（`hls/tb/udp_echo_tb.cpp`，兼容壳 `:30-38` 加默认 0
  的 `slot_dead` 形参）；填 8 个半开（复用 `:1352-1357`）后断言新 SYN DROP+1；
  置 mask 位后再发 SYN ⇒ SYNACK=1、**DEL=0**、ADD=1、槽 T_FREE。mask=0 臂保持
  `P11_TB_HALFOPEN_*`（`:1344-1405`）。
- 板级 A/B（`raw_syn_burst.py` / `raw_probe_table.sh` / `leak_then_rawprobe.sh`）：
  原始 SYN 填 8 → 等 >3.5 s → 再打 8 个原始 SYN。负臂 W7 +0..2；正臂 W7 +8、W52 estab=8。
  **必带活连接杀手臂**：8 条真实连接带数据、空闲 > 阈值后仍能收发并正常 FIN 关闭。
  另加"SYN → 1.5 s → 同 tuple SYN"臂：能建立且线上无 RST。

## 2. R3

### 2.1 `tcp_proc_pending` 单槽

- 【事实】单标量（`udp_echo.cpp:87-89`）；**任何**新帧完成都无条件清 pending
  （`:159-162`），随后 MAC 忙时再设为新帧（`:184-187`）；补做在 `:257-260`。
  csim ARM_B2（`udp_echo_tb.cpp:1269-1291`）用 900B UDP 回显造 954 pass 忙窗 ⇒
  2 个 SYN 只活 1 个且**后到者胜**。
- 方案：
  - **R3-1b（先做）**：把 `:257-260` 整块前移到 `:157` 之前（新帧入 `frame_buf` 之前）。
    零新增存储，修掉"pending 被下一个慢帧清掉"的最常见路径；修不了 ARM_B2。
  - **R3-1a（补全）**：2 深 pending FIFO，每项存 `{ip_rx_t, smac, nwords, 帧字拷贝}`；
    控制帧只需头 32 字（`eth_types.h:25` `FRAME_BUF_WORDS=400`），2×32 字 ≈ 1 BRAM tile。
  - **R3-1c（更干净、更大）**：拆 `tcp_rx_process` 为"状态处理 + 延迟应答队列
    `{cid,flags}`"，由 `tcp_maintenance`（`layer_tcp.cpp:404-424`）空闲补发；需改 6 个
    `tcp_send` 调用点。
- 验证：csim ARM_B2 期望 2/2；`P11_PENDING_FIX=0/1` 双宏臂；板级空闲同时 connect 2 条
  ×20 轮，两臂 `conn_ms` 均应 <10 ms；再加"8×256MB 数据流中 connect 2 条"。

### 2.2 FIN/RST 不校验 seq

- 【事实】`T_SYN_RCVD` 的 FIN 分支（`layer_tcp.cpp:753-765`）只看 flags + 四元组命中
  （`:627`），不校验 seq/ack；`T_ESTABLISHED` 的 FIN 分支同理（`:767-779`）。
- 【事实】正确期望值 `rcv_nxt` 只在 fast 侧（`rtl/tcp_rx.v:303-315` 有 `seq_eq/win_ok`），
  且 fast 明确拒绝 FIN（`flags_ok` 要求 FIN=0，`:307`）；`rx_classify` 把控制标志路由到
  慢路径（`rtl/rx_classify.v:102-107`）⇒ HLS 拿不到该值。
- 方案：
  - **R3-2b（较易）**：把每槽 `rcv_nxt` 快照送给 HLS（`app_ctrl.v:643` 已有 `c_rcv_nxt[0:15]`，
    每 256 拍刷新，零新增状态），HLS FIN 分支加 `seq==i_rcv_nxt[cid]`。
  - **R3-2a（战略）**：FIN/RST 交 fast 校验并拆除（fast 已有 `seq_eq`、CAM/TCB、配额、
    CONN_DOWN），HLS 槽由 R1 的 `i_slot_dead` 释放；需改 `flags_ok`/RX 路由 + xsim 门。
  - **R3-2c（否决）**：HLS 内只查 `ack==c.seq` —— 只对零数据连接成立，带数据连接的真实
    FIN 会被拒 ⇒ F2 泄漏复活。
- 验证：xsim 单元门喂 window 内/外 FIN/RST；板级原始注入伪造 FIN/RST。

## 3. 同源区其它产品级问题（OPEN_ITEMS 未登记）

1. 【事实】**RST 分支同样不校验 seq，且比 FIN 更宽**：`layer_tcp.cpp:678-690` 只按
   `peer_port/peer_ip/local_ip` 匹配（甚至不限 `state!=T_FREE`）就 `CFG_DEL` + `T_FREE`；
   RFC 5961 §3.2 要求 `seq==RCV.NXT`。建议与 R3-2 同批设计。
2. 【事实】**TCP 校验和全链不校验**：HLS 只算 TX（`layer_tcp.cpp:328`），fast 只校验 IP 头
   （`tcp_rx.v:297/690-692`），UDP 同（`udp_rx.v:183/292-294`）。推断为性能取舍，
   应作为显式产品决策登记。
3. 【事实】`T_LAST_ACK` 无重传武装（`layer_tcp.cpp:352`）—— 若未来重启该状态必须配专用计时器。
4. 【推断】R3-1 的"任意帧清 pending"是 §0-88 的强候选机制，但未证；建议先做 R3-1b，
   再用同一 2-connect 工装看 `conn_ms` 是否从 ~1058 ms 掉到 <10 ms。

## 4. 实施建议

- **一批做完**：R1-O1 + R3-1b（可选 R3-1a）共用一次 HLS 重综合（新 archive/变体，
  `p11_build_cfg.tcl:37-66` 加映射 + 端口存在性门）和一次 RTL 构建；沿用 timing gate
  与事前重试阶梯。
- **R3-2 单独一批**（动 fast 语义，与 R1 拆除机有交叠，必须独立审查 + xsim 单元门）。
- **观测**：`ho_fire` 当前会计入 `stat_orphan`（`app_ctrl.v:1686`），语义会混；
  若加新统计字会改快照几何（NW=98 / UNIMPL 0x1B8），按纪律须同步刷新 Tier A ——
  本轮建议先不扩几何，用 W52 ev/estab + W7 做判据。
