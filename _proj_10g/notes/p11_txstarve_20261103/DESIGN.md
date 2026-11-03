# P11 8 连接并发缺陷：tx_arb 慢路径饿死 —— 根因、修法与验收（v1，2026-11-03）

状态：**【已证·板级 + 单元 TB】**（根因）；修法已实现（`rtl/tx_arb.v` 参数 `STARVE_GUARD`），
待独立审查 + 构建 **0x38** + 板级 A/B。对应 `P7B_OPEN_ITEMS.md §0-83`。

## 1. 结论（一句话）

`rtl/tx_arb.v` 的 **fast 严格优先**在 fast 源“帧间零气泡”时退化为**无限期饿死**：
HLS 慢路径的 SYN-ACK/FIN/RST 永远拿不到 TX 线 ⇒ 任一 TCP 连接持续发送时，
**新连接无法建立**（8 并发洪泛下 6/8 ETIMEDOUT；已建立的连接也可能零数据）。
这不是 win_pool 配额、HLS MAX=8、app 槽位或内容通路的缺陷。

## 2. 板级证据（2026-11-03，0x36 现役位流，全新 JTAG 烧录）

- 身份：`BID=0x36` / NW=98 / UNIMPL=0x1B8 / NFF=0；`0x08=0`；nsb(192.168.100.101) ↔ 板 .4，10G carrier。
- **冷启动例外**：烧后第一次 8 并发小传输（`--maxbytes 12288 --seconds 8`）= **2/8** 有数据；
  随后同构 4 跑全部 **8/8**（`mism=0`；工具 `err=8` 是 `got>maxbytes` 的已知过冲口径）。
  ⇒ 冷启动首跑不作判据（全局 #58 同类）。
- **洪泛 8 并发**（`--maxbytes 4 GiB --seconds 12`，`p7b_tcp_sink_multi`）：
  - id1：4.295 GB / 3287 Mbps / status=0；
  - id0：887 MB / 592 Mbps / status=2（建立后 12 s 截止）；
  - id2–id7：**status=4 err=110 ETIMEDOUT（lport=0，从未建立）**。
- **洪泛结束后立即同构小传输 2 跑：8/8 再次全过（mism=0）** ⇒ **不是槽泄漏/配额永久耗尽**，
  是**负载相关**的建立失败。
- 单连接洪泛中插入 1 条新连接：新连接能建立（慢路径偶尔抢到空隙），但 5 s 内 **0 字节**；
  洪泛停止后立即恢复。⇒ 与“慢路径只偶尔拿到线”一致；“已建立但零数据”的确切二次机理
  本轮**未证**（候选：SYN-ACK 侥幸出线后该连接的 ADD/ACK 时序或 app 启动门；修法验收时一并观察）。

### 2.1 SYN / SYN-ACK 判别（决定性；2026-11-03）

洪泛窗口只抓 SYN 标志包（`raw/syn8.pcap`，`tcpdump -i any 'tcp[tcpflags] & tcp-syn != 0'`）：

- peer 发出 **8 个唯一 SYN**（源端口 33824/33836/33846/33860/33874/33880/33890/33892，同一毫秒内）；
- 板只回 **1 个 SYN-ACK**（→ 33824，即第一个 SYN）；
- 其余 7 个各重传 5 次（共 36 个 SYN 包）**全程无 SYN-ACK**。

⇒ **8 个 SYN 全部到达板上；失败在板侧慢路径，不是对端 CPU/网卡/connect 超时**。
时间线 = 第 1 条 SYN-ACK 出线 → 对端 ACK → 该连接 app 开始流 → fast 路径从此不断帧 →
剩余 7 个 SYN-ACK 在 `slow_tx_adp` 里被无限期压住 —— 与 §3 的 `tx_arb` 机理逐字一致。
这是本缺陷最强的单条板级证据（同窗口、同板、同链路，只差“fast 是否在流”）。

## 3. 源码根因（`rtl/tx_arb.v` 修改前）

帧边界重仲裁：

```verilog
if (!busy) begin
    if (s_fast_tvalid)      begin busy<=1; sel_fast<=1; end   // 严格优先
    else if (s_slow_tvalid) begin busy<=1; sel_fast<=0; end
end
```

`tcp_tx_frame` 在持续发送时 `s_fast_tvalid` 跨帧保持高（帧间只有 1 拍仲裁气泡，
而该气泡里 fast 仍然 valid）⇒ `s_slow_tvalid` **永远不被采样**。慢路径的
`slow_tx_adp` 是整帧 store-and-forward，帧在 FIFO 里等到 fast 停为止。

与既有结论的关系：`P7B_OPEN_ITEMS.md` 的“慢路径被 tx_arb 饿死 = 已证伪”只覆盖
**单 UDP app 809k fps** 构型（UDP app 帧间有结构性空隙，慢路径靠它拿线）；
**TCP app 连续流没有该空隙**，该证伪不适用于本构型（§0-83 已写明）。

## 4. 单元 TB（零构建，已跑）

`tb/tb_tx_arb_starve.v`：fast = 组合连续 4 字帧（tvalid 恒 1，帧间零气泡），
slow = 单帧 held-valid，2525 拍：

| STARVE_GUARD | fast 帧 | slow 帧 | 判决 |
|---|---|---|---|
| 0（历史） | 505 | **0** | `LEGACY_STARVE_CONFIRMED` |
| 1（修法） | 255 | **250** | `SLOW_SERVED` |

跑法：`sim/p4sim/run_tb_txarb_starve.bat`（legacy）/ `run_tb_txarb_starve_guard.bat`（guard）。

## 5. 修法

`rtl/tx_arb.v` 新增参数 `STARVE_GUARD`（默认 0）：
- 0 = 历史严格优先，`generate` 分支与旧逻辑逐位一致（非 P11 构建零回归）。
- 1 = **饥饿保护**：fast 帧期间 slow 已挂起（`slow_wait=1`）⇒ 下一个帧边界
  **无条件先发一帧 slow**；slow 不挂起时 fast 仍 100% 独占。
  - 上限：slow 最多等 **1 个 fast 帧**（10G 最大帧 ~1.2 µs）；
  - slow 连续挂起时 fast/slow 帧级 1:1 交替（有意公平，不是优先级反转）；
  - `slow_wait` 在 slow 帧服务期间或 slow 撤 valid 时清零；复位清零。

接线（`board/wrapper_p4.v`）：**仅 P11_DUAL 的 4 个实例**（`u_tx_udp_arb` /
`u_tx_udp_arb_p1` / `u_tx_arb` / `u_tx_arb_p1`）传 `STARVE_GUARD=1`；其余构建保持默认 0。

同一构建附带观测修正：`W97[1:0] = {st_ack_sync[1], st_req}`（原保留 0），
用于 §0-80 的 H1/H2 判别（空载即可读）。

## 6. 风险 / 取舍

1. **fast 吞吐**：仅当 slow 有挂起帧时，每 fast 帧让 1 帧给 slow。控制帧稀疏 ⇒ 预期 <0.1%。
   若 slow 本身灌数据（HLS echo），fast 份额降到 ~50% —— 这是**有意的**公平性变更；
   本轮产品目标（8 连接）优先。登记：若不可接受，退化为“每 K 帧让 1 帧”（K 可配）。
2. **时序**：`slow_wait` 1 位寄存器 + 少量组合逻辑在 TX 路径；0x36 WNS 仅 +0.017 ⇒
   必须核 0x38 的 WNS/失败端点；若失败，按预登记退路：把 guard 只加在**上层**两个
   `u_tx_arb*`（HLS 饿死的主因），下层保持严格优先。
3. **跨构建**：`STARVE_GUARD=0` 用独立 generate 分支 ⇒ 默认构建逻辑不新增。
4. **验收口径**：板级判据 = 洪泛中 8/8 建立 + 8/8 有数据（不再以 `MULTI_SUM ok` 判，
   因工具 `err=8` 过冲口径）；单连接基线速率不得显著低于 0x36（同板同线 A/B）。

## 7. 构建 / 板级计划（0x38）

- env：`P11_CFG=c4 P11_APP8=1 P11_APP8_OCC=0 P11_APP8_CDC=1 P11_IMPL_STRATEGY=Performance_ExtraTimingOpt`；
  BID `0x38`；快照几何不变（NW=98 / UNIMPL=0x1B8）。
- 门：`tb_tx_arb_starve`（两臂）+ 既有 `tb_tx_arb` 回归（GUARD=0）+ wrapper 静态检查
  + `check_window --cdc on` / `check_snap_top5_wired --cdc on` + 构建后 `check_build_0x36.py` 同族。
- 综合网表见证（已在单实例 smoke synth 验证）：`*slow_wait_reg*` = 每实例恰 1 个 FDCE
  （`slow_wait` 还会命中组合中间网 LUT5/LUT1 ⇒ 只数 `_reg`）；构建 tcl 硬门要求 ≥4。
- 板级：重烧 → 身份 → 冷启动弃第一跑 → E1a（8×小）→ E1b（8 洪泛，判 8/8 建立/有数据）
  → E1c（洪泛后小）→ 单连接速率基线；W97[1:0] 空载两次触发快照，应看到 req/ack 翻转。

## 8. 未证 / 不在本件范围

- “建立后零数据”的二次机理（见 §2 末）；
- 双口同时洪泛的全局公平（port0/port1 各自独立 TX，HLS 处理是共享单实例）；
- win_pool 2×12KB 假设（本件证据已将其从主因降级：洪泛停止后 8/8 恢复）。

### 8.1 2026-11-03 追加：两个独立病态（本件修法不覆盖）

1. **冷启动“建立但零数据” warm-up**：**重烧后**（干净 nsb 环境）连续 3 跑 8 并发小传输 =
   **4/8 → 6/8 → 8/8** 成功，**0 个 ETIMEDOUT**（8 个 SYN-ACK 全部出线）。⇒ 零数据
   **不是** SYN-ACK 丢失；候选 = HLS cfg ADD 与对端首个纯 ACK 的竞态（`ack_seen` 门错过
   唯一 ACK ⇒ 该连接永不发数据）。**未定位**，独立于 tx_arb。
2. **会话累积后的槽表疑似泄漏**：同一会话跑完数十次连接（含强杀 sink）后，一次 idle 8 并发
   小传输 = **5/8 成功、3 个源端口各重传 5 次 SYN 全程无 SYN-ACK**；**重烧后恢复**
   （8/8 SYN-ACK、0 timeout）。⇒ 候选 = HLS `tcp_conn` 槽表泄漏（T_SYN_RCVD 且对端从未
   建立 ⇒ 无 FIN/RST 可回收）；**未判定**（需暴露 HLS `tcp_stat_no_slot` 或给 HLS 加
   T_SYN_RCVD 超时回收 —— 两者都要 HLS 重综合）。登记 = `P7B_OPEN_ITEMS §0-85`。
   ⚠️ **对 0x38 板级判据的影响**：0x38 测试必须**从新鲜烧录开始**、预热跑数固定（≤3 跑），
   并把 flood 判据限定在“8 个 SYN 都有 SYN-ACK + 8 条都有数据”；不把累积态读数混入。


## 9. ⛔ 2026-11-03 审查订正 + 转向（本件 §1–§7 的根因**被推翻**；以本节为准）

### 9.1 审查裁决 HOLD（独立 agent，已逐条复核）

- **S1（阻断）成立**：`tcp_tx_frame` 的 `m_axis_tvalid` 在每帧末**必经 2 拍 0**
  （T_DONE 记账拍 + T_HDR 首字装载拍；`rtl/tcp_tx_frame.v:1222` 清位、
  `:1531-1534` 在 T_HDR 末才置 1、`:1621-1656` T_DONE 不预装）。`tx_arb` 的重仲裁拍
  正好落在这 2 拍空洞里 ⇒ **legacy 严格优先在真实源上会服务 slow**；"无限期饿死"不成立。
  本件 §3 的承重句（"fast valid 跨帧保持高"）错误；TB `tb_tx_arb_starve` 的
  零气泡 fast 源是**人为激励**，505/0 只对那个源成立。guard 在真实源上 = **no-op**。
- **S5（高）**：板级 W6/W7 判别已补做（见 9.2）⇒ HLS **确实产出了 8 个 SYN-ACK 帧**
  （ΔW6=+8 / ΔW7=+8 / ΔW18=0），与审查提出的"HLS 只产 1 个"相反；但真正的新发现是
  8 条连接都建立、只有 **2 个 app 槽**在发数据。
- S2/S3/S4/S8/S9（门无牙 / TB 判据 / guard=1 无数据背压门 / W97 采样概率 /
  `slow_wait` 注释）**全部接受**，处置见 9.4。

### 9.2 2026-11-03 新板级事实（0x36 重烧后新鲜态；W 地址 = 0x20+4n）

1. **8 并发洪泛（新鲜态）**：8/8 **全部建立**（无 ETIMEDOUT）；W6 +8（SYN 进慢路径）、
   **W7 +8（8 个 SYN-ACK 帧 commit 进 slow_tx_adp）**、W18=0（无 purge）、W59=0；
   但只有 **conn0（4.29GB）与 conn7（982MB）有下行数据**，conn1–6 全程 0 字节。
2. **8 个单连接 sink 间隔 0.5 s 启动（新鲜态）**：P0 OK（4.29GB）、**P7 OK（4.29GB）**、
   **P1–P6 全部 STALL/0 字节**（连接都建立，conn_ms≈0.1ms）。
   ⇒ 不是 SYN 突发/init 队列瞬时溢出（0.5 s 间隔足够），是**逐槽的系统性问题**。
3. **对端主动灌 4096B ×8（新鲜态）**：仍然只有 conn0/conn7 有下行（其余 6 条
   `sent=4096 unsent=0` 但 `got=0`）⇒ 不是"对端无 ACK ⇒ `ack_seen` 门"单独能解释。
4. **早前"8 SYN→1–2 SYN-ACK"是会话累积态**：同板重烧后 8/8 SYN-ACK；累积态下
   idle 8 并发只 5/8 拿到 SYN-ACK。⇒ 那是**第二个独立病态**（`OPEN_ITEMS §0-85`），
   不是本轮的 2/8 下行缺陷。

### 9.3 新首选假设（未证）

**`app_tx_ready[15:0]`（app_ctrl 每槽 TX 就绪）在槽 1–6 上为 0**：
`app_pattern.tx_ok = app_tx_ready[act_id]`（`rtl/app_pattern.v:447`）；若 app_ctrl 的
每槽 TCB 状态/init 未落到 ESTAB（init 等待队列 `INIT_QD=4`、
`stat_init_ovf`/`stat_init_mismatch` 当前**未接快照**），对应槽的 app 永不产帧。
"槽 0 与槽 7 工作、1–6 不工作"与"首个 + 末个事件成功、中间被 init 队列吞掉"的形态吻合，
但**尚无逐槽读数**。次选 = per-slot window/TCB 扫描。

### 9.4 处置

- **不采用 0x38（guard 构建）**：guard 根因被推翻；0x38 构建已停止（未上板）。
  `STARVE_GUARD` 代码保留（默认 0；仅作为"零气泡病理源"的防御性公平选项，禁用作产品修法）。
- TB/门修正：starve TB 增加**真实 2 拍帧间空洞**臂（legacy 应服务 slow ⇒ 反证 hunger）；
  判据改 `slow_txn>=4`；两个 runner 的 findstr 进退出码；guard=1 的数据/背压门补上。
- **新诊断构建 0x39**（见 §10）：暴露 port0/port1 `app_tx_ready[15:0]`、
  `app_estab_cnt`/`app_ev_cnt`、`stat_init_ovf`/`stat_init_mismatch`（5 字，NW 98→103）。
  板级用 9.2-2 的 8×0.5 s 单连接构型，读 ready 向量：若 bits1–6=0 ⇒ 假设成立。


## 10. 0x39 → 0x3A（2026-11-03 22:0x）

- **0x39 构建 = TIMING_FAIL**：WNS **−0.629** / 7780 setup 端点（hold/pw 0）；
  最差 = `u_tcp_tx/u_fifo_b/rptr_reg[4] → u_tcb/snd_nxt_r_reg[15][16]/CE`（17 级，route 5.015ns）。
  资源 vs 0x36：LUT +32 / **FF +1496** / LUTRAM +708。根因 = 新加的 **port1 ready 向量**
  （`dbg_ready1_r`）被综合复制成 **1056 个 cell**（16 bit × 66 副本）⇒ DP 域扰动把 0x36 的
  +0.017 余量压穿。报告归档 = `build_fail_0x39/`。
- **0x3A（本构建）**：删除 port1 ready（W99）与 init_mismatch（W102），只保留 3 字：
  W98 = port0 `app_tx_ready[15:0]`、W99 = `{app_ev_cnt, app_estab_cnt}`、W100 = `init_ovf`。
  几何 NW=101 / UNIMPL 0x1C4 / p7bdp 57 / top_hi 56；BID 0x3A。
  静态门：`check_window --cdc on` 122/0、`check_snap_top5_wired --cdc on` TOPN=18、
  `check_txstarve_wiring --negctl`、wrapper xvlog 全过；构建 tcl 门 `P7B_DBG39_CELLS` 3 名。
  若 0x3A 仍 TIMING_FAIL：预登记退路 = ① 只留 W98（1 字）② 换
  `P11_IMPL_STRATEGY=Congestion_SpreadLogic_high`（新输入，非重跑到过）③ 对该 DP 旧族做
  定向 retiming（A7 R-1 先例 +0.099）。

- ⭐ **0x3B 备选（零几何扰动的诊断）**：若 0x3A 仍 TIMING_FAIL，改用**复用 0x36 的破观测字**
  （W51/W52/W53 的 app 统计字在板上恒 0，§0-80）承载 ready/estab/init_ovf：
  快照几何回到 **NW=98 / p7bdp=54 / top_hi=53 / UNIMPL=0x1B8**（与 0x36 逐字同），
  只加 ~80 个 debug FF（无新 hold 槽、无新拼接项），把时序扰动压到最小。
  需要同步改 `snap_dout_all` 的三项源（W51..W53）；读侧脚本沿用 0x36 几何。

- **0x3A 也停**：impl 在 Global Iteration 7 仍有 **4882 overlaps**、中间 WNS **−1.078**；
  判定 placement 扰动不可接受，停止（未出位流；partial log = `build_fail_0x3A/`）。
- **0x3B（本构建，零新 FF）**：把 3 个**恒 0 的 app 统计字**（§0-80）复用为诊断：
  W51 = `{16'd0, app_tx_ready}`（组合，快照采样仅诊断）、W52 = `{app_ev_cnt, app_estab_cnt}`、
  W53 = `init_ovf`；快照几何回到 **NW=98 / p7bdp=54 / top_hi=53 / UNIMPL=0x1B8**（与 0x36 同）。
  只改 3 条 `p7bdp_din` 源 + app_ctrl 的 init 计数接线，**无新寄存器/无新槽**。
  BID 0x3B；构建门 `P7B_DIAG3B_SRC 111`（wrapper 三条源赋值）。
  板级读 W51=0xEC / W52=0xF0 / W53=0xF4。

### 9.2b 2026-11-04 01:5x 零构建判别（决定性）：快路径 TCB/ACK 对 8 槽全部正常

- 0x36 重烧新鲜态，8 并发 + 每连 `--send-bytes 4096`；t≈4 s 对端 `ss -tin`：
  **8/8 全部 `bytes_sent:4096 bytes_acked:4097`、无 retrans、`snd_wnd≈10.9–11.7KB`**
  ⇒ 板侧**快路径 TCB/CAM/ACK 与 app RX 窗口更新对 8 个槽全部工作**（不是 cfg ADD / TCB /
  win_pool / HLS 的问题）。
- 同时下行仍只有 2 条（id0 60952 / id7 32778 有 `bytes_received`；其余 6 条
  `rcv_space:14600` 空、`app_limited`、0 字节）⇒ **板子只是不发 app 下行数据**。
- ⇒ 缺陷被压到 **app TX 产生/就绪**（`app_tx_ready[act_id]`、app 核的 ev_up/active、
  或 mux/framer 的逐槽调度）。0x3B 的 W51（ready 向量）是判定这三者的第一刀。


## 11. ⛔ 2026-11-04 03:4x：诊断构建被**既有 DP 时序余量**挡住（三个臂全 TIMING_FAIL）

| 臂 | 诊断字 | 策略 | WNS | 失败端点 | 最差族 |
|---|---|---|---|---|---|
| 0x39 | 5 字（含 port1 ready） | ExtraTimingOpt | −0.629 | 7780 | `u_tcp_tx/u_fifo_b/rptr → u_tcb/snd_nxt_r[15][16]/CE` |
| 0x3A | 3 字 + debug regs | ExtraTimingOpt | 停于 placement（中间 −1.078 / 4882 overlaps） | — | — |
| 0x3B | 3 字复用 W51..W53（**零新 FF**） | ExtraTimingOpt | −1.359 | 13223 | `u_tcp_tx/u_fifo_a/wptr_replica → u_app_ctrl/orph_cnt_reg[3][2]/CE` |
| 0x3B | 同上 | **ExplorePostRoutePhysOpt** | **−0.153** | 2789（hold 0） | `u_tcp_tx2/u_ackq/rptr → u_app2/stg_reg[14]/D` |

- 0x36 的 +0.017 是**贴边**；任何 netlist 扰动（哪怕零新 FF 的 3 条 din 源）都会让 placement
  落到 failing 一侧。最好的策略臂（ExplorePostRoutePhysOpt）已把 WNS 从 −1.359 拉到 **−0.153**，
  但仍有 2789 setup 端点（hold 0）⇒ **未过门，位流全部隔离（.TIMING_FAIL），禁烧**。
- 失败族全部是**既有** DP app/TCB 路径（`u_tcp_tx*` ↔ `u_tcb`/`u_app_ctrl`/`u_app2`），
  不是本轮诊断逻辑；0x37 的 OCC 臂（−0.629，`u_tcp_tx2→u_app2/stg`）同族。
- **结论**：要拿到逐槽 ready/active 读数，必须先做 **DP 时序收口**（或换观测通道）。
  下一阶段候选（需用户裁定/设计审查）：
  1. **时序收口**：对 `u_tcp_tx* ↔ app/tcb` 的 ackq/fifo 指针路径做寄存器切片/retiming
     （A7 R-1 先例 +0.099；必须设计+审查+变异门）；或
  2. **降扰动的诊断构建**：单口（去掉 port1 app/TCP）+ W51 复用，减小拥塞后重试；或
  3. **换观测通道**：VIO/ILA over JTAG（同样需构建，但可只侦测 DP 信号；风险相当）。
- 旁证（本轮零构建，已足够定位方向）：8 连 + 每连 4096B ⇒ 对端 `ss` 显示 **8/8
  `bytes_acked:4097`、无 retrans** ⇒ 快路径 TCB/ACK 与 app RX 对 8 槽全部正常；下行仍只有 2 条
  ⇒ 缺陷在 **app TX 产生/就绪**（ready/ev_up/active/mux），不需要再查 HLS/cfg/TCB/win_pool/对端。
