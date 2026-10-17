# p9_c1_mech_doc_20261017 —— 「静默释放槽位偷取」机制档案 + 功能完备性审查

> 件名 `_proj_10g/notes/p9_c1_mech_doc_20261017/README_FOR_TL.md` · 日期 **2026-10-17** · 轮次 = 只读调查轮
> 上游：`p9_c1_board_20261017/README_FOR_TL.md`（板级两代臂读数）· `p9_p3win_redesign_20261017/README_FOR_TL.md`（机制初稿 §2.0）
> ⛔ **本件只读**：未碰板、未碰对端、未改任何 RTL/工具/设计件；**不下 PASS/FAIL 裁定**。
> ⛔ 标签口径：【已证（`文件:行`）】= 现读源码/现读原文可当场复核 ·【推断】= 有依据但未直接测（附证伪法）·【未判定】·【未测】。
> ⚠️ **行号一律本 agent 2026-10-17 现读**（读法与台账 §9-5-11 一致）；与旧文引用不同处按本件。
> ⚠️ **树态**：本树 HEAD = `2854ede3`，`board/wrapper_p4.v:2185` 现读 = `.PERSIST_EN(1'b0)`、`:4377` = `BUILD_ID_V = 32'h00000029`
> ⇒ **提交树 = 0x29 配置（persist 关）**；**板上现役 = 0x28（persist 开）**；C1 两个臂 = 0x28 / 0x24（均 persist 开）。
> 本件凡涉 persist 的语句都按此区分；**不被该差异影响的结论已逐条核对**。

---

## 一页答案（先读这一页）

**机制一句话**：板侧**被动** TCP 连接在 HLS 慢路径里**恒停在 `T_SYN_RCVD`**（第三个握手 ACK 是纯 ACK ⇒ 按 `rx_classify` 判据只进快路径，HLS 永远看不到它）；
而 `T_SYN_RCVD` 的定时重传**已被刻意废除**（P4b-5 历史实锤：定时重发 SYN+ACK 会 RST 掉活连接）⇒ 该状态**唯一出口**是 RTO 扫描的一次超时
⇒ 超时拍执行 **`state = T_FREE` 并 `continue`（不发任何 cfg 记录）** —— 这就是「静默释放」。
释放**只动 HLS 自己的槽结构**：快路径的 CAM/TCB、app_ctrl/app_pattern 的会话状态**一个字节都不动**。
被释放的槽随即成为 `tcp_find` 的"最低空闲槽"候选 ⇒ 下一个新连接 SYN（任意四元组）会把这个槽当**全新连接**接管，ADD 记录**就地覆盖** CAM+TCB
⇒ 对 app 来说 =「同一个槽 id 之下 TCB 被换人」，而 app 收到的唯一信号是这次 ADD 的 `ev_up`。

**通知链缺什么**：app 的全部通知面 = `ev_up` / `ev_down`（唯一生成点 = `slow_cfg_adp` 的两处 cfg 收尾授权拍）+ `app_tx_ready[slot]`（256 拍轮扫电平）。
**静默释放在这三处都不产生任何东西**。缺的**不是"事件"本身**，而是两件事：
① 「慢路径已不再拥有这个槽」这一事实无法告知 app（无事件、无电平变化 —— TCB 没动，`app_tx_ready` 照旧=1）；
② 「你脚下的 TCB 已被覆写」只能由**下游** ADD 的 `ev_up` + 槽号相同来**间接推断**（app 里就是 `ev_same_act`），没有独立信号。

**P-c（静默释放 + 无偷槽）的答案**：
- 快路径 TCB **还在**、`state=1`（ESTAB）、四元组 CAM 命中照旧（【已证】）：`tcb.v` 无任何"无害超时"，`tcp_rx.v` 只认 CAM 命中 + `state==ESTAB`；
- app **还在 active 并继续发**（若无在飞满窗）（【已证】`app_pattern.v:447/625` 的 `tx_ok` 链只读 TCB 扫描值）；
- 数据**照常上线**（用 TCB/CAM 现值组帧）；对端活着 = 正常收；对端死了 = 帧照发（进虚空）+ 每 **~20 ms**（`RTO_LIM=12207` @156.25MHz）整窗重放 —— ⛔ **2026-10-17 板级 D2 订正（TL 回灌，见文末 §D2）**：**总黑洞（iptables 双向 DROP）下实测只重传 16–21 个会话（~0.35–0.47 s）即静默**（0x28 负臂两跑：`W55` +17/+20 后 140–144 s 恒不变；pcap 16 个 20 ms 间隔包、跨度 0.407 s 后静默）⇒ **"每 20 ms 整窗重放、永不放弃"不成立**；停止分支（RTO 上限 / ring 排空 / 其它门）【未定位】。无自主回收 / 无 RST 自产 / 槽永久占用仍成立（负臂真实签名 = **不回收 + 槽静默卡死**）；**慢盆（有 ACK 推进）的持续重放读数 `W55=49.9/s` 不受此订正影响**；**死对端下 persist 阶梯是否永续【未测】**（D2 构型 = `snd_wnd≠0` 的 RTO 路径，未覆盖 persist）。窗口打满后 app 停在新帧门（`frm_wait`，W63 计数）；
- **回收：没有自主路径**【已证（源码穷举）】—— TCB 的 `state=0` 写口只有两个：**DEL 记录**（`slow_cfg_adp.v:158-163`）与 **`app_ctrl` 的 fc 通道**（`app_ctrl.v:871-874`），后者需要 `fin_sent`（app 主动关过）；本构型 app 永不 close（`TX_CONTINUOUS=1`）⇒ **槽/TCB 只能靠外部事件收场**：对端 RST（HLS 的 RST 扫描靠**残留 peer 字段**命中）/ 新 SYN 的 ADD 覆盖 / 人工。**对端若彻底消失 ⇒ 该槽位永久占用（慢路径 3 槽、快路径 16 组），并可能永久占用 app 的唯一会话**。

**P-d（静默释放后对端"迟到"仍活着）的答案**：两层状态不一致窗口**对数据面没有影响** —— 迟到数据/纯 ACK/第三 ACK 全部由快路径按老 TCB 正常处理（【已证】）。
真正有影响的是**控制帧**：迟到 **RST** ⇒ HLS 的 RST 扫描按残留 `peer_ip/peer_port` 命中 ⇒ `CFG_DEL` ⇒ `ev_down` ⇒ app 收尾（**唯一「记得」该连接的迟到控制帧**）；
迟到 **FIN** ⇒ **两层同时忽略**（快路径 `flags_ok` 结构上排除 FIN，见 `tcp_rx.v:307`；HLS 无匹配槽 ⇒ `:643` 直接 `return`）⇒ 对端半关闭后板侧无感。

**对 C1 2/40 的指向**：两解释都落在 ③-P-b 的"事件应用拍"两种子情形上 —— **解释 1（真覆盖写）** = 应用拍撞上装配写（`SWC_OK=0` 才可能，即 **0x24 臂**）；**解释 2（退化）** = 应用干净、但**重启后第 1 帧走了旧四元组**。
现有仪器（首 64 KB dump + 读出 K0/breaks）**两者字节级不可分**；判别点写在 §⑤（**前持有者尾部**才是分水岭）。

---

## ① 全链流水线（背景铺垫）

### 1.1 数据面/控制面总图（本 agent 现读拼装，逐段有出处）

```
        SFP28 J8 ── GTY/PCS ── XGMII ── mac_rx_10g ──┐
                                                     ▼
                                              rx_classify  (rtl/rx_classify.v)
  判据 (现读 :101-107):
     TCP 且 flags[2:0] (FIN|SYN|RST) 任一置位 ⇒ SLOW    ← 一切握手/拆除控制帧
     其余 TCP (纯 ACK / 数据)                ⇒ FAST
     非 IPv4 / 非 TCP (ARP/UDP/ICMP/…)       ⇒ SLOW (dec_w2, :103)
     短帧 (tlast 早于 w5)                    ⇒ SLOW (:106-107)

   FAST 路                                      SLOW 路
   ────────                                     ────────
   tcp_rx (rtl/tcp_rx.v)                        slow_rx_adp (rtl/slow_rx_adp.v)
     ├ tcp_cam 组合查询 (4 元组 → slot)            ├ 字节流 → HLS rx_stream (+看门狗 hls_rst_n)
     ├ tcb.v 读口 A (rcv_nxt/snd_nxt/wnd/state)  └ (回程) slow_tx_adp → tx_arb
     ├ 校验: state==ESTAB / flags / doff / 窗口
     ├ 推进 rcv_nxt / snd_una / snd_wnd；回 ACK
     └ emit ─► tcp_echo (frame_fifo 64KB, 零拷贝)
                  ├─► app_pattern.rx_* (演示 app 的 RX 校验器; eco2_*)
                  └─► tcp_tx_frame (rtl/tcp_tx_frame.v)   ← TX 引擎(数据/重放/控制帧)
                                                    ▲
   app_pattern (rtl/app_pattern.v) TX ─► axis_pipe ─┘   ← app 产出数据帧 (1 帧=1 段)
        │  (m_tid = act_id)
        └─ app_ctrl (rtl/app_ctrl.v) 提供 tx_ok=app_tx_ready[act_id]
   tx_arb (TCP fast 严格优先) ─► mac_tx_64/mac_tx_10g ─► XGMII ─► SFP28

   ── 控制面: HLS 慢路径 (hls/src/udp_echo.cpp → layer_tcp.cpp) ──
   udp_echo.cfg_stream (32bit AXIS, 8 词/记录) ─► slow_cfg_adp (rtl/slow_cfg_adp.v)
        ├─► cam_cfg_*  (CAM 五字段写; 单拍, 无仲裁)
        ├─► upd_*      (TCB 七字段写; 经 4 级仲裁 tx>rx>cfg>fc)
        └─► ev_up / ev_down / ev_slot (+peer ip/port/mac)  ─┐
                                                            ▼
                                          app_ctrl (转发+记账+超时)
                                            o_ev_up/o_ev_down/o_ev_slot ─► app_pattern
                                            且 scfg_ev_up ─► tcp_tx_frame.cfg_up (清 fin_sent_r/whi_r/rto_*/ps_*)
                                            且 scfg_ev_up ─► wrapper ack_seen_w[slot] 清位 (数据启动门 r6)
```
【已证】出处：`board/wrapper_p4.v:6-11`（链头注释）、`:1832`(u_tcp_rx)、`:1935`(u_tcp_echo)、`:2079+`(u_slow_cfg)、`:2185`(u_tcp_tx)、`:2774`(u_tx_arb)、`:1282-1284`/`:2101-2103`/`:2165`/`:2207-2208`（事件与清位三处消费）。

### 1.2 一条连接在两层里的**两份状态**（本机制的主角）

| | HLS 慢路径（`hls/src/layer_tcp.cpp`） | 快路径（RTL） |
|---|---|---|
| 状态表 | `tcp_conn[MAX_TCP_CONN=3]`（`:131`） | `tcb` 16 条 × 7 字段（`rtl/tcb.v:78-84`）+ `tcp_cam` 16 条 × 5 字段（`rtl/tcp_cam.v:36-40`） |
| 谁写 | HLS 状态机自己 | **只由 cfg 记录**（ADD/DEL）+ 数据面自身（数据/ACK 推进 rcv_nxt/snd_una/snd_wnd） |
| 建 | 被动连接：SYN 到达拍 `T_FREE→T_LISTEN`（`:617-621`），**同拍**进 `T_LISTEN` 分支发 **ADD 记录 + SYN\|ACK**（`:668-679`，"乐观建连"） | ADD 记录逐字段落地（见 1.3） |
| 拆 | 对端 FIN/RST（`:699-708`/`:633-641`）、同四元组 bare SYN（`:608-610`）⇒ **写 DEL 记录**；或 **RTO 超时静默释放（不发 DEL）**（`:531-535`） | DEL 记录 ⇒ CAM 五字段清零 + TCB **只写 state=0**（`slow_cfg_adp.v:145-152`/`:158-169`） |
| 同步语义 | cfg 流是**唯一**同步通道（【已证】`layer_tcp.cpp:150-164` 头注释："握手/拆除结果推送给 fast path；CAM/TCB 的唯一状态源在 fast 数据面"） | — |

⚠️ **两层的"连接"概念不同**：HLS 的槽是**握手簿记**（3 条），快路径的 slot 是**数据面实体**（16 条）；HLS 每条连接占一个**固定编号**的 fast slot（ADD 的 `slot` 字段 = HLS 槽号）。**"静默释放"只清前者**，后者原地不动 —— 这是全篇的机理根。

### 1.3 cfg 记录（8 词）与 ADD 的逐字段覆盖

- 记录布局【已证】`hls/src/layer_tcp.cpp:156-199`（`cfg_write`）：`w0=(wscale<<16)|(cmd<<8)|slot`（cmd 0=ADD / 1=DEL）· `w1=peer_ip` · `w2=local_ip` · `w3=(peer_port<<16)|local_port` · `w4=peer_mac[47:16]` · `w5=(peer_mac[15:0]<<16)|peer_wnd(已按 wscale 缩放)` · `w6=rcv_nxt(=对端 ISS+1)` · `w7=snd_nxt(=我方 SYN+ACK 后的 seq=ISS+1)`；DEL 只写 w0、其余写 0（定长 8 词）。
- 解析【已证】`rtl/slow_cfg_adp.v`：`S_RECV` 逐词收（`:108-128`）→ `S_CAM` 单拍写 CAM（`:129-155`）→ `S_TCB` 七字段逐字写（`:156-186`）→ `S_TCB_LAST` 写 wscale（`:187-198`）。
- **ADD 落地 = 全量覆盖**：
  - CAM[slot]：`sip/dip/sport/dport/dmac` 五字段**全写**（`:139-144`）⇒ **旧四元组被抹掉**（这正是"偷槽后旧对端包 CAM-miss"的原因）；
  - TCB[slot]：`rcv_nxt=w6` / `snd_nxt=w7` / **`snd_una=w7`** / `rcv_wnd=32'h0000C000`（48K，随后被 app_ctrl 的 `fc` 纠偏写覆盖）/ `snd_wnd=w5[15:0]` / `state=1` / `wscale` —— **七字段全写**（`:78-90`）。
- **DEL 落地 = 只写 state=0**（`:158-163`）+ CAM 五字段清零；TCB 的 `rcv_nxt/snd_nxt/snd_una/snd_wnd/rcv_wnd/wscale` **保留旧值**（DEL 不清）—— 同槽重连的时序安全由"ADD 全量覆盖"兜住，而不是由 DEL 清理兜。

### 1.4 事件(tick)与 app 的会话

- `ev_up` 生成拍 = **ADD 的最后一个字段(wscale)授权落地拍**（`slow_cfg_adp.v:187-198`，注释逐字"早于此 TCB 未配全, app 会拿 snd_nxt=0 组帧"）；
- `ev_down` 生成拍 = **DEL 的 state=0 授权落地拍**（`:158-168`）；
- 两者都是 **1 拍脉冲**（`:104-106` 每拍默认清零）；
- app 的"会话"= `active`/`act_id`/`tx_lfsr`/`remain`/`seg_len`/`seg_sent`/`frm_idx`（`app_pattern.v:388-404` 一带）；**它不认识 seq**（seq 在 TCB 里）⇒ 对它而言"同一槽号 = 同一条会话载体"。

---

## ② 通知链：app 是怎么（被/不被）通知的

### 2.1 全部通知面（穷举，逐条现读）

| # | 信号 | 生成点 | 消费点 | 语义 |
|---|---|---|---|---|
| 1 | `ev_up`（脉冲） | `slow_cfg_adp.v:193-195`（ADD 收尾授权拍） | app_ctrl `:973-999` → `o_ev_up` → app_pattern（wrapper `:1231`/`:1299`） | "槽 X 建连完成（TCB 已配全）" |
| 2 | `ev_down`（脉冲） | `slow_cfg_adp.v:164-168`（DEL state=0 授权拍） | 同上（app_ctrl `:1018-1022`） | "槽 X 已拆除" |
| 3 | 超时自产 `ev_down` | `app_ctrl.v:861-863`（`to_fire`）+ `:1062-1067`（投递） | 同上 | "半关闭超时（400 ms 无进展）⇒ 拆" |
| 4 | `app_tx_ready[15:0]`（电平） | `app_ctrl.v:557-585`（256 拍轮扫算） | app_pattern `:447` `tx_ok` | "这个槽现在能不能起新帧" |
| 5 | 事件字 FIFO（寄存器可读） | `app_ctrl.v:437-450`（102 位 × 16） | 板上无 CPU 消费者（`wrapper_p4.v:1345-1347` 现读 = `app_reg_addr=8'h00` / `app_reg_wr=1'b0` / `app_reg_wdata=32'd0` 三条静态钉死） | 只作观测 |

**没有第 6 条。** app_pattern 的端口表里与连接生命周期相关的输入就是 `ev_up/ev_down/ev_slot`（`app_pattern.v:55-57`）与 `app_tx_ready[15:0]`（`:67`）。

### 2.2 正常关闭路径（对端 FIN/RST → DEL → `ev_down`）时序

```
[对端]  FIN(或 RST) ─► rx_classify (FIN 位 ⇒ SLOW) ─► HLS
HLS: cid=tcp_find(四元组) 命中 (state!=T_FREE)            [layer_tcp.cpp:581,142-148]
     若 RST  : 扫描全部槽按 peer_ip/port 匹配 ⇒ state=T_FREE + cfg DEL + return  [:633-641]
     若 FIN  : T_SYN_RCVD 支 ⇒ cfg DEL + 发 FIN|ACK + state=T_FREE               [:699-708]
              (T_ESTABLISHED 支 ⇒ cfg DEL + FIN|ACK + state=T_LAST_ACK            [:718-722])
cfg DEL (8 词) ─► slow_cfg_adp: S_CAM 清 CAM ⇒ S_TCB 写 state=0 ⇒ gnt 拍 ev_down   [:129-168]
        同时 ─► TCB[slot].state=0 ⇒ 快路径此后对该四元组一律 stat_drop_nonmatch（不回 ACK）
ev_down ─► app_ctrl: 归还配额/清 redge 族/fin_req/rst_req ⇒ o_ev_down ─► app_pattern
app_pattern: closing<=1 [:904-906] ⇒ W3 收尾(当前帧带 tlast 闭合 / 0 载荷收尾字) ⇒ active=0 [:917-940]
终局: app idle、TCB state=0、CAM 该槽清零、HLS 槽 T_FREE（**四方一致**）
```
⚠️ 两个边界（本 agent 现读新登记，见 §④-4）：① 在 `T_SYN_RCVD` 里，**FIN+ACK 且 `ack==c.seq`** 会被**握手完成分支**先吃掉（`:680`），FIN 被吞、不发 DEL（对端重传 FIN 后由 `T_ESTABLISHED` 支补上）；② 若槽已静默释放，FIN 走不到任何分支（`:643` return）。

### 2.3 静默释放路径：**没有通知**

**触发链（逐拍）**【已证】：

```
被动连接建连:  SYN ─► T_FREE→T_LISTEN→T_SYN_RCVD ; cfg ADD 已发 ; tcp_send(SYN|ACK)
               ⇒ c.retrans_pending=true, c.rto_timer=0, c.rto=TCP_RTO_MIN=10,000,000  [:307, 619]
第三个 ACK:    纯 ACK (flags=0x10) ⇒ rx_classify 判 FAST ⇒ **HLS 永远看不到**
               ⇒ T_SYN_RCVD 的 `if((flags&TCP_ACK)&&ack==c.seq)` 分支结构性不可达
                 (能进 HLS 的 ACK 必须带 FIN/SYN/RST 位 ⇒ 不是第三个 ACK)         [:680-684]
               ⇒ c.retrans_pending 保持 true ⇒ 唯一的推进 = 空闲拍 RTO 扫描
RTO 扫描:      每 pass c.rto_timer++ ; 到 10,000,000 ⇒ 先做退避(c.rto*=2 等) [:513-523] 再:
               if(c.state==T_SYN_RCVD){ c.state=T_FREE; c.retrans_pending=false; continue; }  [:531-535]
               ⇒ **不发 DEL、不发 FIN/RST、不碰 CAM/TCB** —— 静默释放
```
- **名义 80 ms vs 实测 2.56 s**：`TCP_RTO_MIN=10000000` 的注释按"1 pass ≈ 1 拍 @125MHz"估的（`:39-40`）；板级 C1 实测每槽释放周期 **≈2.56 s**（`p9_c1_board §2`），反推 **pass ≈ 256 ns ≈ 40 拍 @156.25MHz**【推断：未直接测 pass 周期】。
- **扫描只在"空闲 pass"推进**：`tcp_rx_process` 的计时支在 `if(!ip_rx.valid||protocol!=6)` 里（`:505`），而空闲拍调用点被 `#if ACTIVE_CONNECT` 门控（`hls/src/udp_echo.cpp:262-267`）；现役 HLS 网表**含** `udp_echo_tcp_active_tick.v`（`hls/slowstack_prj/solution1/syn/verilog/` 现读存在）⇒ 该调用点在编译里【已证（网表文件存在）】、**正在跑**【推断（由 C1 事件率 ≈0.39/s/槽与 2.56 s 周期自洽反证；证伪法 = 直接测 HLS pass 周期或放出"释放计数器"）】。
- **释放时清了什么 / 没清什么**（逐字段）：

| 清掉（本次释放写） | 值/说明 |
|---|---|
| `c.state` | `T_FREE`（`:532`）|
| `c.retrans_pending` | `false`（`:533`）|
| `c.rto_timer` | 0（`:517` 超时入口先清）|
| `c.rto` | ×2（封顶 `TCP_RTO_MAX=80,000,000`）（`:518-519`；被复用时 init 会重置回 MIN）|
| `c.ssthresh / c.cwnd / c.flight_size / c.dup_ack_cnt` | 重算/归零（`:520-523`，仅 HLS 自用，无对外影响）|

| **没清**（保留旧值） | 谁还会读它 |
|---|---|
| `c.peer_ip` / `c.peer_port` | **RST 扫描**（`:633-641` 按这两个字段匹配，不看 state）—— 这是"静默释放后迟到 RST 仍能命中"的唯一原因 |
| `c.seq` / `c.peer_seq` / `c.last_ack_recv` / `c.peer_mss` / `c.peer_wscale` | 无消费者（复用走 init 覆盖，`:617-621`）|
| `c.retry_cnt` / `retrans_len` / `retrans_flags` | 惰性（`retrans_pending=0`）|
| **快路径 CAM[slot] / TCB[slot]** | **完全不动**：state 仍 1、rcv_nxt/snd_nxt/snd_una/wnd 仍是老连接的值 |
| app_ctrl 的 per-slot 流控/超时族（`winq/redge/wu_*/fc_*/fin_req/rst_req/st_pend/to_*`） | 完全不动（只在 ev_up/ev_down 脉冲清）|
| tcp_tx_frame 的 per-slot 族（`fin_sent_r/rst_sent_r/whi_r/epoch/rto_*/ps_*/ring`） | 完全不动（只在扫描/cfg_up 清）|
| wrapper `ack_seen_w[slot]` | 不动（只在 `scfg_ev_up` 清）|
| app_pattern 会话（`active/act_id/tx_lfsr/…`） | 不动（只在 `ev_up`/`ev_down` 驱动）|

⇒ **结论**：静默释放**不经过** `slow_cfg_adp` 的任何 ev 生成点（`:164-168` / `:193-195` 两处是本文件唯一的 ev 源，而它们只由**记录**触发；静默释放**不写记录**）【已证（源码穷举：`grep cfg_write` 在 `layer_tcp.cpp` 的调用点 = `:609/:637/:663/:677/:699/:721`，无一处在该分支）】。
⇒ app 在这一刻**得不到任何输入**：无脉冲、无电平变化、无 FIFO 项。

### 2.4 另一条"静默清槽"路径（性质同族，一并登记）

**HLS 看门狗复位**：`slow_rx_adp.v:150-175` 在"HLS 有字节可读却 ~16.8 ms 不读"（`WDOG=22'd2621440` @156.25MHz）时给 HLS 打 `RST_CNT=80` 拍复位脉冲；
HLS 复位支 `layer_tcp.cpp:498-503`：`if(!rst){ for(...) tcp_conn[i].state=T_FREE; return; }` ⇒ **全槽清空、同样不发任何 DEL**。
影响面 = 复现"所有活连接同时失去慢路径所有权"；与静默释放的唯一区别是**批量 + 有计数器**（W17 = `hls_rst_n` 低电平拍数 ÷80 ≈ 复位次数，`board/wrapper_p4.v:3455`/`:4237`、【已证（源码）；板级当前值未读】）。

---

## ③ 分路径时序/流程图（每条：触发 → 逐拍过程 → 终局）

图例：`H`=HLS 慢路径 · `F`=快路径(RTL) · `A`=app_pattern/app_ctrl · `P`=对端 · `★`=本机制的关节点。

### 3.1 P-a 正常关闭（对端 FIN/RST → DEL → app 收尾）

```
t0  P: FIN|ACK (或 RST)  ─────────────────────────────────────────────┐
t1  rx_classify: FIN 位 ⇒ SLOW;                                     │
t2  H: tcp_find 命中(旧槽 state!=T_FREE)                            │
      ├ FIN 且 state==T_SYN_RCVD 且 ack!=c.seq ⇒ ★cfg DEL + FIN|ACK + state=T_FREE
      ├ RST ⇒ 扫描匹配 peer 字段 ⇒ cfg DEL (+FIN 不适用) + state=T_FREE
      └ (边界) FIN 且 ack==c.seq ⇒ 被握手分支吃掉 ⇒ ★无 DEL(见 §④-4)
t3  加 ~20 拍: slow_cfg_adp 解析 DEL: S_CAM 清 CAM → S_TCB 写 state=0 → gnt 拍 ev_down
t4  F: TCB[slot].state=0 ⇒ 该四元组此后 CAM 仍命中但 state_ok=0 ⇒ 全部丢弃(不回 ACK)
t5  A: app_ctrl 归还配额/清会话族 ⇒ o_ev_down ⇒ app_pattern: closing=1 ⇒ W3 收尾
t6  A: 当前帧带 tlast 闭合(或 0 载荷收尾字) ⇒ active=0 (app 静默待命, tx_lfsr 不复位)
终局: HLS=T_FREE / CAM 清 / TCB state=0 / app idle  —— **四方一致, 无残留**
```
【已证】`layer_tcp.cpp:633-641,699-708,718-722` · `slow_cfg_adp.v:129-198` · `app_pattern.v:904-906,917-940`

### 3.2 ★P-b 静默释放 + 偷槽（C1 主路径）

```
t0  [活连接 C1(slot k)]: HLS=T_SYN_RCVD(永远), F=TCB[k] ESTAB, A=active=1 & act_id=k (流在发)
t1  H: RTO 扫描超时 ⇒ state=T_FREE, retrans_pending=0, **无 DEL**         ← 静默释放
      F/A: 一切照旧 ⇒ 这一刻 C1 仍在正常收发 (TCB 未动 ⇒ 数据面零扰动)
t2  新 SYN(对端 P2, 新临时端口) ─► SLOW
t3  H: tcp_find(四元组 P2) 无匹配 ⇒ 返回**最低空闲槽** = k (刚被释放)
      ⇒ init(k): state=T_LISTEN, seq=0x12345678|(k<<20), rto=TCP_RTO_MIN, ...  [:617-621]
      ⇒ 同 pass 进 T_LISTEN 分支: ★cfg ADD(k, P2) + SYN|ACK               [:668-679]
t4  slow_cfg_adp: S_CAM ⇒ CAM[k] 五字段 = P2 (★旧四元组 P1 就此消失)
      ⇒ S_TCB 七字段 ⇒ TCB[k] = 新连接 seq 空间 (snd_nxt=snd_una=新 ISS+1, rcv_nxt=新 ISS+1)
      ⇒ S_TCB_LAST ⇒ ★ev_up(k)
t5  F: TCB[k] 已是新连接; 此后 app 的下一帧用**新 TCB** 组帧 ⇒ 数据"无缝"接到新连接
      ★"无缝"的机理: app 只认槽号(act_id=k 不变) + 不持 seq(seq 在 TCB) + 无 ev_down(会话没断)
t6  A: ev_up 到达。两种 build 两种处置:
      ├ SWC_OK=1 (0x28): same_slot ∧ active ⇒ ev_same_act ⇒ sw_pend/closing ⇒
      │   换流收尾(丢残字 drop_pw + 0 载荷 tlast) ⇒ active=0 ⇒ 收尾完成后的那一拍应用 sw_apply:
      │   act_id<=k, remain<=TX_BYTES, tx_lfsr<=SEED, wc_buf 清 ⇒ **图案流重启**
      └ SWC_OK=0 (0x24): up_ok=0 (帧中且 seg_sent!=0) ⇒ 登记 up_pend_r ⇒
          在下一个 seg_sent==0/frm_wait 拍应用 ⇒ **图案流重启**(同块)
t7  F: ADD 的副作用由 wrapper/引擎各自清: ack_seen_w[k]=0 (数据启动门, 等新连接的首个 ACK)、
      tcp_tx_frame.cfg_up 清 fin_sent_r/whi_r/rto_pend/ps_*  [wrapper:2165 / tcp_tx_frame:1101-1124]
终局: 慢路径 HLS=T_SYN_RCVD(新连接) / CAM+TCB=P2 / app 会话换到 P2 (流从 SEED 重启)
      ⚠️ 旧连接 C1 的 TCB 值(未清字段) 只可能被**同槽后续 ADD** 再覆盖; 旧对端的包 ⇒ CAM miss ⇒ 静默丢
```
【已证】`layer_tcp.cpp:513-535,142-148,613-621,668-679` · `slow_cfg_adp.v:129-198` · `tcb.v:94-105` · `tcp_cam.v:49-55` · `app_pattern.v:544-554,800-868,882-897` · `wrapper_p4.v:2160-2166` · `tcp_tx_frame.v:1101-1124`
⚠️ 本路径**必然携带** `ev_up`（ADD 是它的唯一来源）——「静默」只属于 t1 那一步，**不**属于 t3-t4。

### 3.3 ★P-c 静默释放 + **无偷槽**（用户关注的功能面；逐问给答案）

```
t0  同 P-b t0/t1: HLS 槽被静默释放; F/A 毫不知情
t1  没有新 SYN 来 (对端真的死/不再重连/该槽始终不是最低空闲):
      问1 快路径 TCB 还在吗?          → 在, state=1 (ESTAB), CAM[k] 仍是原四元组   【已证 tcb.v/tcp_cam.v(无任何超时/回收逻辑)】
      问2 app 还在发吗?               → active=1 且 tx_ok=1 (在飞< min(snd_wnd,61440)) 【已证 app_ctrl.v:557-585 / app_pattern.v:447,625】
                                        (窗口打满 ⇒ tx_ok=0 ⇒ frm_wait 停发, W63 计数, 等 tx_ok 恢复)
      问3 数据发去哪?                 → 照常组帧上线 (header/seq 在帧首拍锁存自 TCB/CAM 现值) 【已证 tcp_tx_frame.v:2395-2416】
          对端活着      → 正常收、正常回 ACK ⇒ 连接**完全可用**(只是慢路径"看不见"它)
          对端死了      → 帧进虚空; RTO(≈20 ms) 整窗重放 —— ⛔ **D2 板级订正：总黑洞下只重传 16–21 会话（~0.35–0.47 s）即静默，非"永不放弃"；停止分支【未定位】**
                          （原【已证 tcp_tx_frame.v:1243-1257,1191-1200】只覆盖"每 RTO 重放整窗"的单次行为）
                          (arm 条件含 snd_wnd!=0; 若 snd_wnd==0 ⇒ 改走 persist 探询阶梯 20ms→5→10→20→40→60s 封顶；**死对端下 persist 是否永续【未测】**
                           〔D2 未覆盖 persist 路径〕; 0x29 树配置 persist 关 ⇒ 那种情形**完全静默**无重传)
      问4 谁、何时回收该槽与 TCB?     → ★**无自主回收**。穷举:
            ① 对端 RST → HLS RST 扫描按**残留 peer 字段**命中 ⇒ DEL ⇒ ev_down ⇒ TCB state=0  【已证 layer_tcp.cpp:633-641】
            ② 任意新 SYN 落进该槽(最低空闲) ⇒ ADD 就地覆盖                             【已证 :617-621】
            ③ app_ctrl 关闭超时(to_fire) ⇒ 需要 `fin_sent` ⇒ 要求 app 主动关过 ⇒ 本构型不成立(TX_CONTINUOUS=1 永不 close)
            ④ HLS 看门狗复位 ⇒ 只清 HLS 槽, TCB 更不管
            ⇒ 只要对端安静且没有新 SYN 抢该槽, **该槽位(慢 3 / 快 16)与 app 会话被永久占用**
      问5 RTO/重传怎么终局?           → **不终局**(设计如此: 无放弃、无自产 RST); 终局只能由外部事件给(RST/新 SYN/人工)
```
【已证】`tcb.v` 全文无超时; `tcp_rx.v` 无 RST 自产（只有 `ack_req` 回 ACK, `:404-415`）; `tcp_tx_frame.v` 无 give-up; `app_ctrl.v:861-863`（to_fire 需 fin_sent）; `slow_cfg_adp.v` 仅记录驱动。
【未判定】"本构型下这种孤儿态在 C1 三臂里出现过多少次"（无计数器；见 §④-7 的仪器建议）。

### 3.4 P-d 静默释放后对端"迟到"仍活着（两层状态不一致窗口）

```
前提: HLS 槽=T_FREE(已释放), 快路径 TCB/CAM 完好, app 会话完好

(a) 迟到**数据段/纯 ACK/第三 ACK**  ── 无影响 ──
    rx_classify ⇒ FAST ⇒ tcp_rx: CAM 命中 + state==ESTAB + 窗口校验 ⇒ 正常收/推进/回 ACK
    ⇒ 两层不一致对**数据面**不可见 (快路径自成闭环)                        【已证 rx_classify.v:101-107, tcp_rx.v:307-323】

(b) ★迟到 **FIN** ── 两层**同时忽略** ──
    F: FIN 帧被 rx_classify 判 SLOW ⇒ 快路径根本看不到 (且 tcp_rx 的 flags_ok 明确排除 FIN/RST/SYN, :307)
    H: tcp_find 因 state==T_FREE 不匹配(匹配子句含 state!=T_FREE, :146) ⇒ 返回空闲槽号;
       裸 SYN 分支不适用; RST 分支不适用 ⇒ 落到 `:643` `if(...state==T_FREE) return;` ⇒ **静默 return**
    ⇒ 后果: 对端半关闭后板侧无感 ⇒ app 继续发数据进一条已被对端关闭写向的连接
       (Linux 侧仍会 ACK 数据(半关闭合法), 直到对端进程也关闭/销毁 ⇒ 迟到 RST ⇒ 见 (c))
【已证】rx_classify.v:101-107 · tcp_rx.v:307 · layer_tcp.cpp:142-148,608-643

(c) ★迟到 **RST** ── 唯一"记得"M该连接的迟到控制帧 ──
    H: RST 分支**不要求 state!=T_FREE**, 只比 peer_ip/peer_port ⇒ 命中残留字段 ⇒
       state=T_FREE(已如此, 无变化) + **cfg DEL** ⇒ ev_down ⇒ app 收尾 + TCB state=0
    ⇒ 静默释放过的连接, 其"记忆"完全寄托于残留的 peer 字段 —— 直到该槽被新连接 ADD 覆盖
【已证】layer_tcp.cpp:633-641（注释逐字"含重传超限已释放槽, 其 peer_ip/peer_port 保留"）

(d) 迟到 **bare SYN (同四元组)**: ⇒ 走"全新连接"入口, **不**走 P-e 的 DEL+ADD(因为匹配子句要求 state!=T_FREE)
    ⇒ 若它落的槽 == 原槽: 直接 ADD 覆盖(同 P-b, 但 app 的 ev_up 因 same_slot 触发换流);
       若落的槽 != 原槽(更低号有空闲): **CAM 出现两条同四元组**(见 §④-5)
【已证】layer_tcp.cpp:142-148,608-621 · tcp_cam.v:58-69(低索引优先)
```

### 3.5 P-e 同 4-tuple 新 SYN 撞上**未释放**的槽（C3 形态：DEL+ADD 背靠背）

```
触发: 快路径已被本地拆除(app abort/CMD close 或 FIN 已走完) ⇒ CAM/TCB 已清/state=0,
      但 HLS 槽仍**占着**(state!=T_FREE): HLS 的槽只有"对端 FIN/RST"或"超时"能释放
t1  SYN(同四元组) ⇒ SLOW ⇒ tcp_find 命中旧槽(state!=T_FREE, peer 字段匹配)
t2  ★P5d-D6 入口: `if(cid>=0 && state!=T_FREE && bare SYN)` ⇒ cfg DEL(cid) + state=T_FREE  [:608-610]
t3  同 pass 继续: `if(state==T_FREE && bare SYN)` ⇒ init ⇒ T_LISTEN ⇒ 同 pass ADD + SYN|ACK [:617-621,668-679]
⇒ cfg 流里 **16+16 = 32 词背靠背** (slow_cfg_adp FIFO 深 16 ⇒ 恰好顶满, 不溢出)
   ev_down → ev_up 相隔 ≈ 2(S_CAM+S_TCB_{DEL}) + 8(S_RECV_{ADD}) + 1(S_CAM) + 8(S_TCB+LAST)
             ≈ **19 拍**（本 agent 逐态推算【推断】；设计件口径写"≥26 拍"，差在起算点：从 DEL 记录起算 ≈27 拍）
终局: 槽=新连接 / CAM+TCB 全量覆盖 / app 先收 ev_down(→closing) 再收 ev_up(→换流)
      ⇒ app 到达态 ∈ {closing}, **不可能在"组装中"**(cfg A 族结构性 P≡0 的根)
```
【已证】`layer_tcp.cpp:588-621` · `slow_cfg_adp.v:56-70`（FIFO 16 深、`s_axis_tready=!f_full`）· `p9_p3win_redesign §1`（cfg A 族 P≡0 论证）

---

## ④ ★功能缺失清单（用户的问题本体）

> 口径：**"有/无 + 源码证据 + 后果 + 严重度/影响面"**。严重度只写"影响面"与"是否阻断"，**不下裁定**。

### ④-1 如何通知 app —— 现状与缺口

| 项 | 有/无 | 证据 | 后果 |
|---|---|---|---|
| "连接建立"通知 | **有** | `ev_up`（`slow_cfg_adp.v:193-195` → `app_ctrl.v:973-999` → app） | — |
| "连接拆除"通知（对端 FIN/RST、超时拆、P5d-D6） | **有** | `ev_down` 三来源（`slow_cfg_adp.v:164-168` / `app_ctrl.v:861-863`+`:1062-1067` / 同一 DEL） | — |
| **"慢路径已释放该槽（我这边不再拥有它）"** | **无** | 静默释放分支 `layer_tcp.cpp:531-535` 只写两个字段 + `continue`；`grep cfg_write` 该分支无调用 | 见下两行 |
| 有偷槽接力时的后果 | 部分自愈 | t3 的 ADD 会发 `ev_up`；app 用 `same_slot` 判为"同槽事件"⇒ 收尾换流（`app_pattern.v:553,800-868`） | **"无缝续接"能实现，但靠的是"新连接的 ADD 事件"这个下游事件，不是释放本身的通知**；若 app 因为任一原因**没消费**这次 ev_up（A3 已修的历史缺陷 / up_ok 判据为假而登记失败）⇒ 新会话静默零数据、无自愈（`tb_app_cont u_rec1/u_rec2` 史证） |
| 无接力时的后果（★用户所指的"功能缺失"） | **无任何通知** | 见 3.3 | **孤儿会话**：TCB/槽位永久占用 + app 永久朝一条慢路径不认识、可能已死/已被对端关闭的连接发数据；且因为 app 单会话(`act_id`)，后续新连接的 ADD 只能走 `ev_other_act ⇒ up_pend_r` 登记（`:884-885`），**而应用需要 idle**（`up_ok=idle_now`，`:549`）⇒ **app 永不 idle ⇒ 后续连接拿不到 app 数据**【已证（源码链）；板级未专门验证】 |

**缺口的性质（本 agent 的判定口径）**：不是"忘了发信号"，而是**架构上慢路径无权单方面宣布会话结束** ——
`ev_down` 的唯一合法语义是"DEL 已落地"（= 快路径条目已拆）；而静默释放**故意不动快路径**（P4b-5 的板测教训：动它会 RST 掉活连接）。
⇒ 任何"补通知"的设计都必须回答："通知之后，快路径那条仍在 ESTAB 的 TCB 谁来拆、什么时候拆？"（现状 = 无人）

### ④-2 快路径 TCB/CAM 的生命周期与回收条件

| 问题 | 答案 | 证据 |
|---|---|---|
| 快路径有没有**独立的**超时/回收？ | **没有**。`tcb.v` 是纯寄存器组；`tcp_rx.v` 只做"接受/丢弃/回 ACK"；`tcp_tx_frame.v` 只做"发/重发/探询"，**无 give-up、无自产 RST** | `tcb.v` 全文 · `tcp_rx.v:404-415`（只有 ack_req）· `tcp_tx_frame.v`（RTO/persist 均 reload，不终止） |
| 唯一会写 `state=0` 的非 DEL 来源？ | `app_ctrl` 的 `fc` 通道（`st_req_now`，条件是 `rst_sent` 或 `st_grace`），其**触发上游** = `to_fire`（需 `fin_sent[c] && state==ESTAB && 400 ms 无进展`） | `app_ctrl.v:861-863`（to_fire）· `:871-874`（st_req_now）· `:701-717`（fc 通道合并注释） |
| 被释放的 HLS 槽与仍活的 TCB 会不会错配？ | **会**：HLS 槽号被复用后，ADD 记录会往**同一个 fast slot** 写新连接 —— 对齐的（不是随机错配），但**节奏由 HLS 定**（最低空闲槽） | `slow_cfg_adp.v:132`（`cam_cfg_addr <= slot`）/`tcb.v:94-105` |
| 后来同槽新 ADD 覆盖，**旧残留清干净了吗**？逐字段： | **CAM**：五字段全写 ✅；**TCB**：七字段全写 ✅（`rcv_nxt/snd_nxt/snd_una/rcv_wnd/snd_wnd/state/wscale`） | `slow_cfg_adp.v:139-144, 78-90, 176-197` |
| 那**别的** per-slot 状态谁清？ | `tcp_tx_frame`：`cfg_up` 清 `fin_sent_r / whi_r / rst_sent_r / fin_retx_pend / epoch / snd_una_prev / rto_pend / rto_timer / ps_timer / ps_phase / ps_rd_*`（`:1101-1124`）；扫描另清（state!=ESTAB 支） | `tcp_tx_frame.v:1101-1124,1243-1258` |
| | wrapper：`ack_seen_w[slot] = 0`（数据启动门，等新连接首个 ACK） | `wrapper_p4.v:2160-2166` + `tcp_tx_frame.v:564-565`（`acks_ok` ⇒ `start_data` 门） |
| | `app_ctrl`：`init_pend` 拍重设 `redge/wu_mark/c_rcv_nxt/wu_zero/wu_pend` + 挂 `fc_pend` 纠偏；ev_up 块清 `fin_req/rst_req` + 池授予（`winq[slot]`） | `app_ctrl.v:933-971, 973-1000` |
| | `app_pattern`：换流块清 `tx_lfsr/wc_buf/remain/seg_*/frm_wait/closing/op_*`（`:800-867`） | 同左 |
| ⚠️ **未覆盖/可疑的残留**（本 agent 逐一现读后登记，全部【推断】+证伪法） | ① **`retx_ram`（ring 内容）不清**：旧连接的载荷字节仍在 ring 里；`whi_r` 清零 + 上界比较（`tcp_tx_frame.v:1186-1187` 的 `ring_hi` 回退条款）挡住"伪重放"，但**ring 里的旧字节本身没清** ⇒ 若发生任何跨会话重放，重放的是**旧内容**。证伪法 = 在 ring_start 拍抓 `f_dmac/f_seq` 与 TCB 现值对比，或直接查"跨 ADD 的重放帧"。（**候选机理**，见 §⑤-3） | `tcp_tx_frame.v:1186-1187, 2276-2295` |
| | ② **`snd_wnd`/`wscale` 由 ADD 写入**（w5/w0[19:16]）⇒ 新连接的窗口语义正确；但若新 SYN 的 window 字段极小 ⇒ app 立刻 frm_wait（正常语义，非缺陷） | `slow_cfg_adp.v:86-88` |

### ④-3 迟到包是否造成**误配**（旧连接的数据被新连接收下？）

| 场景 | seq/4-tuple 校验会不会挡住 | 证据 |
|---|---|---|
| 旧对端(同 IP 不同端口)的数据/ACK **在 CAM 覆盖后**到达 | **挡住**：CAM 按 4 元组精确匹配（含 sport/dport），旧四元组已不在表里 ⇒ `cam_hit_l=0` ⇒ `base_ok=0` ⇒ 丢弃（`stat_drop_nonmatch`，不回 ACK） | `tcp_cam.v:58-69` · `tcp_rx.v:347` |
| 旧对端在**覆盖前**到达的迟到段 | 正常处理（TCB 也还是旧的）⇒ 无风险 | 同上 |
| 同槽新连接的数据 | 用新 TCB 的 `rcv_nxt`/窗口判 ⇒ 正确 | `tcp_rx.v:321-323` |
| **跨事件帧**（帧首拍锁存在 ADD 之前、数据拍在 ADD 之后） | ⚠️ **存在错配窗口**：帧首拍一次性锁存 `seq/ack/wnd/dmac/dip/sport/dport`（`tcp_tx_frame.v:2395-2416`）⇒ 该帧带**旧四元组 + 旧 seq** 上线（ADD 在锁存之后落地）；若帧首拍恰落在 CAM 写之后、TCB 七字段尚未写全的 ~8 拍窗口内，则可能是**新四元组 + 旧 seq**。**两者都会被对端窗口/seq 校验大概率丢弃**，但都会让"哪条连接收到什么"出现 1 帧级的错位 | `tcp_tx_frame.v:2395-2416` · `tcp_rx.v:321-323`（对端侧校验模型） |
| **RST 扫描的残留匹配**（④-1 的 (c)） | ⚠️ 旧对端的 RST 在**槽被覆写前**到达 ⇒ 命中 ⇒ DEL ⇒ **会拆掉新连接？不会**：覆盖后 `peer_port` 已是新值，旧 RST 不再匹配（除非新连接恰与旧同端口= C3 构型） | `layer_tcp.cpp:633-641` |
| **零推进窗口更新 ACK**（旧连接的纯 ACK 落到新连接 seq 空间） | 挡住：`ack_ok` 要求 `ack ∈ [snd_una, ack_hi]`；旧 seq 空间的 ack 与新 snd_una 差巨大 ⇒ `ack_ok=0`（回卷域另论） | `tcp_rx.v:330-336` |

⇒ 结论：**4 元组 + seq 双重校验把"旧连接数据被新连接收下"整类风险挡在门外**【已证（源码）】；
唯一残留 = **本板自己的**跨事件帧（1 帧级）与旧 ring 内容（候选机理，未定位）。

### ④-4 ⭐新登记：`T_SYN_RCVD` 中 `FIN+ACK` 且 `ack==c.seq` 被握手分支吞掉

- 现读（`:680-690`）：`case T_SYN_RCVD:` 的第一支是 `if((flags&TCP_ACK)&&ack==c.seq){...state=T_ESTABLISHED...}`，FIN 支在**第三个** `else if`。
- 因纯 ACK 进不了 HLS（`rx_classify.v:101-107`），该第一支的**唯一可达输入** = 带 FIN/SYN/RST 的帧；其中 `SYN+ACK` 已被第二支的 `!(flags&TCP_ACK)` 排除 ⇒ **实际可达的就是 FIN+ACK**。
- 对端"连上就关"（第三 ACK 与 FIN 之间没有本板数据被 ACK）⇒ FIN 的 ack 恰 = `c.seq`（= ISS+1）⇒ **FIN 被吞、无 DEL、槽转 T_ESTABLISHED 且不发 FIN+ACK**。
- 收敛：对端会重传 FIN（收不到确认）⇒ 第二次 FIN 走 `T_ESTABLISHED` 支 ⇒ `cfg DEL + FIN|ACK + T_LAST_ACK`（`:718-722`）⇒ 正常。
- 影响面：**多一次 FIN 往返的延迟**（对端 RTO 量级），而非丢连接；⚠️ 若对端把 FIN 重传交给我们没见过的路径（或 dead-peer 探测失败），会退化成 §3.3 的孤儿。【已证（源码链）】·【未测（板级未专门构造）】

### ④-5 ⭐新登记：同四元组新 SYN 落到**别的**槽 ⇒ CAM 双条目

- `tcp_find` 的匹配要求 `state!=T_FREE`（`:146`），空闲槽取**最低号**（`:147`）。
- 若旧槽 k 已静默释放、而存在更低号的空闲槽 j ⇒ 新 SYN 落 j、ADD 写 `CAM[j]=T`；**`CAM[k]` 仍是 T**（从未被清）⇒ **CAM 里两条同四元组**。
- 查询优先级 = **低索引优先**（`tcp_cam.v:58-69`，`if(!q_hit && ...)` 逐条覆盖）⇒ RX 全部解析到 j；TX 仍按 `act_id=k`（app 还在槽 k 的会话上）用 `rd_*[k]` 读 MAC/IP/端口 ⇒ **收/发两条腿落在不同槽**（MAC/IP 相同 ⇒ 线上仍指向同一对端，但 seq/窗口规则分属两条 TCB）。
- 后果：理论上可造成"ack 被写进 j 的 snd_una、数据由 k 发"的账目分裂；实际影响取决于谁先更新。**未定位/未测**（需专门构造：制造一个低号空闲槽 + 同四元组重连；判据 = `T1 = CAM 唯一性断言` 或 `Δ` 两槽 TCB 的 snd_una）。【已证（源码）；后果未测】

### ④-6 无自主回收 ⇒ 资源面影响（影响面量化）

- 慢路径槽：3 个（`MAX_TCP_CONN=3`，`layer_tcp.cpp:9-11`）；快路径 slot：16（`tcb.v:8`/`tcp_cam.v:6`）；app 会话：**1 个**（单会话设计，`up_ok` 只认同一槽或 idle 切换）。
- 无接力孤儿 ⇒ 该槽 + 其 TCB 永久占用；**若它恰是 app 的会话 ⇒ app 卡死在死连接上，后续连接即使被 HLS 接纳（ADD 顺利），app 也只会把它们登记成 `up_pend_r`（永不 idle ⇒ 永不应用）**【已证（源码链）】。**这是本机制最重的后果面**，且**与 C1 的观测相容**（C1 里 handoff 链表明 app 确实在换手 ⇒ 说明那些臂上"有接力"）。
- 【未判定】孤儿态在历史各轮（涓流/慢盆/S0C 等）里出现过几次 —— 无计数器。

### ④-7 观测面缺口（要什么仪器才能把以上各条变成读数）

| 想知道的量 | 现在有没有 | 建议（本 agent 提议，未实施） |
|---|---|---|
| 静默释放次数 | **无**（`tcp_stat_no_slot` 是"槽耗尽"计数，`layer_tcp.cpp:133-136`，不是本量） | HLS 侧在 `:531-535` 加一个 16 位计数 + 复用 `tcp_slot_drop_count()` 的先例接出（HLS 端口表变动有成本，先例已知） |
| 偷槽事件/到达态分布 | **有**：W71/W72/W73/W74（`app_pattern.v:561-591`；板级已读：144/47/47/96） | — |
| HLS 看门狗复位次数 | 半有：W17 = `hls_rst_n` 低电平拍数 ÷80（`wrapper_p4.v:4237`、`slow_rx_adp.v:33-37`） | 直接读 W17 即可 |
| **P-3 危险拍撞车次数**（应用拍 ∧ 装配拍同拍） | **无** | 在 `app_pattern.v` 应用块加 1 个事件计数（`if (up_do && asm_go) cnt++`；`SWC_OK=0` 构型才有意义）——**这是把"解释 1"从推断变直测的最短路径** |
| 帧级"发给谁"（旧四元组 vs 新四元组） | ctl pcap 有（`tcp port 8080`，snaplen 128 ⇒ 端口/seq/flags 全在） | 在 handoff 瞬间**逐包重建两条连接的 seq 时间线**（零构建） |
| app 会话是否卡死（孤儿） | 部分：W63（frm_wait 拍数）+ `active` 无快照 | 加 `active/act_id` 快照字（吃 WNS 余量） |

---

## ⑤ 与 C1 的 2/40 两解释的映射

**判定式原文（照录，`p9_c1_board_20261017 §4.3`）**：
> 0x24 臂 ≥1 条"首 4 KB 无重启 ∧ 离线复核 `K0≠0 ∧ breaks==0`" ⇒ "命中已现形"；0 条 ∧ 前件达标 ⇒ "本构型下未命中"；前件不达标 ⇒ "无判别力"。

**两解释 → 路径映射**：

| 解释 | 落哪条路径的哪一步 | 期望字节签名 | 说明 |
|---|---|---|---|
| **解释 1 = 真覆盖写**（P-3 命中） | **P-b 的 t6**（事件应用拍），且**必须 `SWC_OK=0`**（= **0x24 臂**【推断（版本时序：0x24 @10-13 早于 TX_SWCLOSE 引入的 0x27 @10-15），可由归档构建件核】；0x28 臂 I1 结构性排除：`sw_apply=idle_now&&up_ev` ⇒ 应用拍恒 `active=0` ⇒ `asm_go≡0`，且 `:1034` 还有 E10 的第二道门） | 新连接收到的 = **旧流的连续续接**（`K0` 任意相位、`breaks==0`）；**全流找不到 needle** | 危险拍 = `up_ok` 的 `same_slot && seg_sent==0` 子式与 `asm_go` 同拍为真（`app_pattern.v:549` vs `:625`）；两个写 `tx_lfsr` 同拍、**块序在后者胜**：事件块写 `tx_lfsr<=SEED` 在 `:832`（`if (sw_apply)` 块内），装配逐字节支写 `tx_lfsr<=xs_next` 在 **`:1034`**（该行注释逐字"**逐字节支是本文件唯一没有被 `!a2_hold` 挡住的装配写（P-3 的覆盖者就是这里）**"）⇒ SEED 被覆盖 【已证（源码）】 |
| **解释 2 = 退化情形** | **P-b 的 t4-t7**（覆盖与换流都正常，只是**第 1 帧的归属**出错） | 新连接首字节 = `pattern[1460]`（= 重启后第 2 帧），此后 `breaks==0`；**needle 不在窗口内**；**前持有者的尾部含 needle** | 与解释 1 在"本连接首 64 KB"内**字节级不可分**（C1 §4.5 已论证） |

**可区分点（= 未来"末 64 KB dump"分离实验要看什么）**：

1. ⭐ **前持有者的尾部**（唯一分水岭）：
   - 解释 1 ⇒ 前持有者尾部 = 无 needle 的连续流，且与新连接的头部**在图案流坐标系里首尾相接**（`K0_新 = K0_旧 + 旧持有者字节数`，误差 = 1 帧内的在飞损失）；
   - 解释 2 ⇒ 前持有者尾部应含 **needle（`pattern[0..]`）+ 恰好 1460 B**，而新连接头部 = `pattern[1460]`。
2. **两个 dump 的 `K0` 联合分布**：解释 1 的 `K0` 应均匀分布（两条独立命中落在同一帧栅格值的概率 ≲1e-6，C1 §4.5-1 已算）；解释 2 恒 `K0=1460`。
3. **pcap 侧（零构建）**：在 handoff 瞬间按端口重建两条 4 元组的 seq/字节时间线 ⇒ 直接看"重启后第 1 帧"发给了谁、旧 4 元组在 ADD 之后是否还收到过数据帧。
4. **板侧计数器（要构建）**：④-7 的"危险拍撞车计数" —— 若为 0，解释 1 在 0x24 臂上**不可达**（= 命中只能来自解释 2）。
5. ⚠️ 必须同时记账的第三条腿（C1 已登记、**未定位**：接收字节比 app 产出多 5.3–9.3% / 同块重复 / 回跳段）：它们指向"线上出现了 app 未产出的字节"，与本机制**相容的候选** = 跨 ADD 的 ring 重放（旧内容 + 新 seq，§④-2①）；**在分离实验里必须把这三条与本机制分开记账**，否则会污染两解释的判别。

**对 0x28 臂（0/16）的读法**：该臂 `SWC_OK=1` ⇒ 解释 1 **结构性不可能**；因此 0x28 的 0/16 **不能**当作"机制不存在"的证据（它测的是另一条构型），只能当"换流门 I1 生效"的侧面读数。

---

## ⑥ 结论表 + 待裁点

| 问题 | 结论（带标签） | 关键出处 |
|---|---|---|
| 机制是什么 | 被动连接恒停 `T_SYN_RCVD`（3rd ACK 只进快路径 + 定时重传被废除）⇒ RTO 超时拍 `state=T_FREE` + `continue`，**不发 DEL** | 【已证】`layer_tcp.cpp:531-535`（+`rx_classify.v:101-107`、`:680-684`） |
| 谁触发 | HLS 的 RTO 扫描（空闲 pass 推进，`c.rto` 初值 = `TCP_RTO_MIN=10,000,000`）；名义 80 ms、**板级实测 ≈2.56 s/槽** | 【已证源码】+【已证板级（C1 §2）】 |
| 释放时动了什么 | 只动 HLS 槽的 2 个字段（state/retrans_pending）+ 退避量；**快路径 CAM/TCB、app 会话、各 per-slot 外围全不动** | 【已证】逐字段表见 §2.3 |
| 通知谁 | **不通知任何消费者**（不写 cfg 记录 ⇒ 无 ev；TCB 不动 ⇒ `app_tx_ready` 不变） | 【已证】§2.3 |
| 谁被通知（偷槽时） | 只有 `ev_up`（ADD）—— 语义是"新连接"，不是"你的连接没了" | 【已证】§3.2 |
| 缺什么 | ① 无"慢路径失去所有权"通知；② 无"TCB 被覆写"独立信号；③ 迟到 FIN 两层同时忽略；④ 无自主回收（孤儿会话 ⇒ 后续连接拿不到 app 数据） | 【已证（源码链）】；④ 的板级后果【未测】 |
| 对 C1 结论的影响 | 2/40 两解释**都能**从 P-b 产出；**0x28 臂结构性排除解释 1** ⇒ 该臂 0/16 不是反证 | 【已证（源码）】+【已证（C1 §4.5）】 |
| 定案需要什么 | ⭐ ①**末 64 KB 尾部 dump**（前持有者尾部有无 needle = 分水岭，零构建）；② pcap 逐包 seq/port 重建（零构建）；③ 新增"危险拍撞车"计数器（需构建，`SWC_OK=0` 构型）；④ 与三条未定位观测分开记账 | §⑤ |
| 待裁点 | (a) 是否为"孤儿会话"补任何通知/回收（**会牵动快路径拆除语义**，风险高，必须先设计后实施）；(b) C1 分离实验是否排期；(c) 是否给"孤儿会话"加观测字（`active/act_id` 进快照，吃 WNS 余量） | 用户/TL |

---

## 未决清单（本件内所有未判定/未测项，逐条）

1. 【未测】静默释放的 pass 周期（≈256 ns 是反推值）；HLS 空闲调用点在现役位流里"正在跑"只有间接证据。
2. 【未判定】孤儿态（无接力）在历史轮次的出现频次 —— 无计数器。
3. 【未测】④-5 的 CAM 双条目后果（收/发两腿分裂的账目影响）。
4. 【未测】④-4 的 FIN+ACK 吸收分支在板级的可复现性（需专门构造"连上就关"客户端）。
5. 【未测】§⑤ 解释 1 的"危险拍撞车"从未被直接测量（只有字节流间接证据）。
6. 【未定位（C1 已登记，本件只挂账）】接收字节比 app 产出多 5.3–9.3% · 同块重复/同前缀 · 回跳段 —— 与本机制的关系未分离。
7. 【未测】`retx_ram` 旧内容在跨 ADD 重放中的可见性（§④-2①候选机理）。
8. 【未判定】快路径"永不停发"对线上资源的长期占用 —— ⛔ **2026-10-17 D2 板级订正：该前提不成立**（总黑洞下重放 ~0.35–0.47 s 后静默）；改挂【未判定】= **槽被静默卡死**的长期占用（负臂实测：`W55` 140–144 s 冻结、旧连接解除 DROP 后 0 B/5 s、槽不回收）。
9. 【未测】W17（看门狗复位计数）在 C1 三臂窗口内的取值（本件未读快照原始件）。

## §D2 板级订正（2026-10-17，TL 回灌；来源 = `p9_board_0x2A_20261017/README_FOR_TL.md` §2.3/§D2）

**订正对象 = 本件 P-c 与 §3.3 里"对端死了 ⇒ 每 ~20 ms 整窗重放、永不放弃"这句。**

- **实测（0x28 负臂 ×2：A_NEG 单边 INPUT DROP / A_NEG2 双向 DROP；正臂有 0x2A 时同构型）**：板在 DROP 后**只重传 16–21 个会话（`W55` +17/+20），约 0.35–0.47 s 即静默**；之后 140–144 s 内 `W51/W52/W55` **完全冻结**；pcap = 6.5–6.6k×1460 B 数据 + **16 个 20 ms 间隔包（跨度 0.407 s）**，之后静默；板侧 FIN/RST = 0。旧连接解除 DROP 后 **0 B/5 s**。
- **⇒ 负臂的真实签名 = "不回收 + 槽静默卡死"**（不是"永久重放"）。本件原"永不放弃"的表述**仅对"每次 RTO 重放整窗"这一单次行为有源码依据**；**重放停止的具体 RTO 分支（计数上限 / ring 排空 / 其它门）【未定位】**。
- **不受影响的读数**：慢盆（`snd_una` 在推进、有 ACK）的 `W55=49.9/s` 持续重放形态；persist 阶梯的 20ms→…→60s 退避表（活零窗对端 200 s 回归臂 IAT p99 = 60.000085 s 实测）。**未测** = 死对端下 persist 是否永续（D2 构型走的是 `snd_wnd≠0` 的 RTO 路径）。
- **对孤儿修复设计的影响**：正臂判别力（`ΔW75=+1` @ t_rel=61.68 s + 槽恢复）**不依赖** pcap 重放，故不受影响；受影响的只有"负臂 pcap 重放不止"这一格的期望，已在设计件 v4.2 补记里订正为"无 ΔW75 + 槽静默卡死"。

—— 完（本件 = 机制档案 + 功能完备性审查；**不含任何 PASS/FAIL 裁定**）
