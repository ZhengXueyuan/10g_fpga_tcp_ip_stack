# FINDINGS — 红队审：孤儿会话修复设计件（`p9_orphan_fix_design_20261017/README_FOR_TL.md`）

> 审查模式 = 自对抗（kimi-tl 离线）；只读复核，未跑 xsim/综合/板级、未碰板/对端。⛔ 不下 PASS/FAIL、不含实施授权。
> 本件 = TL 代落（红队全文回报；平台拒写文件）。
> **TL 处置块在文首**；红队原文自「## 0. 结论摘要」起。

## TL 处置块（2026-10-17 11:0x 现读施工）

- **全 18 项采纳**。**设计件判定：不能按现文进入实施（红队读数意见），打回修订**——修订由原设计 agent 执行（已派，附本 FINDINGS 全文 + 12 条必改清单）。
- **阻断级 4 项（实施前必须闭）**：**F1** 60 s 时基算错 1000×（144×419.43 µs = 60.398 **ms**；8 位饱和 106.95 **ms** ⇒ 需 `ORPHAN_TICK_BITS≈18` = 61.85 s）；**F2** ADD 同槽竞态防线 2 前提与源码相反（`ev_up` 拍 `scfg_upd_wr=0` ⇒ fc state=0 可落在 ADD 后一拍 ⇒ 新连接静默死 ⇒ 必须**组合门**）；**F3** CAM 清可擦新 ADD（`ev_up` 拍 busy=0 且在 CAM 写之后 ⇒ `orphan_cam_clr` 必须**组合 abort 门** + U6 post-fire 变体）；**F4** NW 75→76 ⇒ MIR 自动下移 **0x150..0x15C**、**UNIMPL=0x160**（设计误把 MIR 真寄存器当空洞；B7 会读到 `mir_dma_cnt`）。
- **中危 7 项（补进设计/门/板级计划）**：F5 replay_full 不自持（重放帧自己推进 snd_nxt；retx 支理由改写为覆盖 inflight<cap 的周期 RTO 会话）· F6 真漏 = `inflight==0` 空闲死对端 + 零窗死对端（§9-6 误述纠正）· F7 `Δstat_ev_down` 板上不可观测（改 pcap + app closing）· F8 `ret_slot_q/pool_ret_x` use-point 漏 + `orph_down` 门漏 `!to_pushed_r`（可连续两拍 o_ev_down）+ st_done 文案 · F9 动作顺序须 state=0 先于 CAM 清（否则零 CAM TX 窗口出 0 MAC/IP 帧）· F10 M1/M2/M5 无牙 + M4 无效 + M6/M8 门归属 · F11 板级慢盆混淆（臂序 = 快态臂→进盆臂→重烧→孤儿臂；每次烧后核"盆不在场"）。
- **文案/限定 7 项**（F12–F18）：矩阵清单说法、ORPHAN_EN=0 零回归证据（需同激励全输出逐位对比 + 明确 wrapper 启用作用域）、B1 非严格单变量（+W75+BID）、+96 FF 的三分之二不在宿主网、scfg_busy 不含 wcnt、scan_now 非自由运行、M8/U2 标签。
- **红队战绩**：**第一版设计件 → 4 阻断 + 7 中危**——对抗审查流程价值实证（若直接实施：F1 会让门限成 60 ms（3×RTO，慢盆误杀风险）、F2/F3 会让偷槽新连接静默死/ CAM 被擦、F4 会让板级身份门读错地址）。
- **下一步**：修订版设计件 → 红队**复评（F1–F4 闭项 + F5–F11 落地检查）** → 实施 → 门 → 构建（前置：还原 `PERSIST_EN(1'b1)` + BID 0x2A）→ 板级。

---

## 0. 结论摘要（红队原文）

| # | 严重度 | 发现 | 状态 |
|---|---|---|---|
| F1 | 设计阻断 | `ORPHAN_LIM=144 × 419.43 µs = 60.398 ms`，不是 60.4 s；8 位饱和 = 106.95 ms | **不实** |
| F2 | 设计阻断 | `ev_up` 拍 `scfg_upd_wr=0`；fc state=0 可落在 ADD 最后一拍之后 | **不实** |
| F3 | 设计阻断 | `ev_up` 拍 busy=0（在 CAM 写之后）；寄存器式中止晚一拍 ⇒ 擦新 CAM | **不实（按字面）** |
| F4 | 高 | NW=76 ⇒ MIR 0x150..0x15C，UNIMPL=0x160；设计写 0x15C | **不实** |
| F5 | 中 | replay_full 不自持（重放帧推进 snd_nxt） | **不实** |
| F6 | 中 | inflight==0 / 零窗死对端永不回收；§9-6 误述 | **漏登记** |
| F7 | 中 | Δstat_ev_down 板上不可观测 | **不实** |
| F8 | 中 | ret_slot_q 漏；st_done 不清；to_pushed_r 隔离缺口 | **部分不实** |
| F9 | 中 | 先 CAM 后 state 的零 CAM TX 窗口 | **未覆盖** |
| F10 | 中 | M1/M2/M5 条件未写；M4 无效 | **部分不实** |
| F11 | 中 | 板级慢盆混淆 | **未覆盖** |
| F12 | 低 | 矩阵清单说法过时（p5wrapper 门含 app_ctrl/app_pattern/wrapper_p4） | **不实（部分）** |
| F13 | 低 | ORPHAN_EN=0 零回归证据不足（U10 弱；wrapper 传 1） | **部分不实** |
| F14 | 低 | B1 单变量 = orphan + W75 + BID | **需限定** |
| F15 | 低 | +96 FF 非全落宿主族（32/32/32） | 措辞级 |
| F16 | 低 | `scfg_busy` 不含 wcnt（结论仍安全） | 措辞级 |
| F17 | 低 | tcp_tx_frame `scan_now` 非自由运行 | **不实（界）** |
| F18 | 低 | M8/U2 的"app 收尾"标签错 | 措辞级 |

计数：属实 7 · 不实 8 · 部分不实/需限定 5 · 未覆盖/漏登记 3 · 措辞级 5（跨类条目见正文）。

---

## 1. 攻击线 1 —— Q2 失联判据的误杀风险

### 1.1 snd_una 回卷：攻击点假设的灾难不成立 —— 【不实（对攻击点）】，但设计未把口径写死

现读证据：
- 推进清零用**授权写脉冲**：`tcp_rx.v:486-490` 的 `upd_sel = drn==2 ? 3'd2 : …` 是组合输出；`wrapper_p4.v:2053` `rx_upd_gnt = sel_rx`；设计取 `una_adv = rx_upd_gnt && (rx_upd_sel==3'd2)`。
- 因此 snd_una 自身 32 位回卷**不会**被误判"不前进"——写脉冲照常到达、计数器照常清零。
- 唯一 32 位减法是 `inflight = rc_snd_nxt - rc_snd_una`；`win_closed` 显式带 `(inflight < 32'h8000_0000)` 守卫（设计 §3.2/附录 B），回绕安全。`work` 用 `!=`，安全。
- 结论：攻击线 1 第一颗子弹不成立。但设计**没有**写出"推进判定 = 写脉冲，不是 mod 差值/绝对比较"——建议补一行，防止实施者改成值比较（一改就真的回卷误杀）。
- 边缘（登记）：`tcp_rx.v:343` 在 `ack_hi < snd_una` 的重放期可接受一条旧 ACK 并把 snd_una 写回旧值，多清零一次 orphan 计数（延迟回收），不是误杀；该形态为既存 RTL 边界（`tcp_rx.v:328-341` 自认）。

### 1.2 慢盆不得被杀：意图层【属实】；现参数下不成立（F1）

- `p9_p3win_trickle_board_20261017/runs/T1_READINGS.txt:32` `W68=136.432/s` ⇒ 单条 trickle 平均推进 **7.3 ms**；20.07 ms 是最坏（每簇最后一段等 RTO 重放，`:113-135`）。
- `p9_basin_probe_20261017/README_FOR_TL.md:185` B1 `W68=84.8/s`；`:53` B2 `W68=86.1/s`（全局）。
- 结论：慢盆内 snd_una 推进间隔（单连接 ~7–20 ms）远小于设计**意图**的 60 s ⇒ "每次推进清零 ⇒ 不误杀"在 60 s 口径下成立。但现文实际是 **60.4 ms**（F1），对 20 ms 最坏簇只剩 3×；若多连接共享 `W52/W68`（B1 全局 84.8/s 分摊到 10 条爬行 ⇒ 单连接 ~118 ms > 60 ms）会被杀。60 s 口径修好后须重跑该臂。
- 边缘：`accrue` 的 `rc_snd_wnd!=0` 也清零；B2 对端窗 40% 为 0（`:53,69`），只会让误杀更少。

### 1.3 persist 零窗不得被杀：【属实】；反向洞未登记

- `accrue` 含 `rc_snd_wnd != 0`；`tcp_tx_frame.v:752-757` 的 `ps_arm` 只在 `rb_snd_wnd==0` 时武装 ⇒ 二者**互斥**，60 s vs persist 60 s 无边界竞态。
- 反向洞（设计未登记）：对端死前最后 ACK 给 **win=0** ⇒ `snd_wnd==0` 永久保持 ⇒ orphan 永不点火、persist 每 60 s 探一个死对端 ⇒ 槽永久占着 fast TCB/CAM/winq。见 F6。

### 1.4 点火覆盖缺口：攻击点的 `inflight<min(wnd,cap)` 其实被 retx 支覆盖；真漏是 `inflight==0` 与零窗死对端

- `inflight<cap` 但 `>0`：`win_closed=假`，但 RTO 仍武装（`tcp_tx_frame.v:1249-1259`：`scan_estab && ((snd_wnd!=0 && snd_nxt!=snd_una) || fin_retx_pend)`）⇒ 每 20 ms 一次 `svc` → `retx_active<=retx_begin`（`:1191-1192,2264`）。fire 第三项在任一次 RTO 会话的扫描采样为真 ⇒ 会回收。
  - 小在飞时 retx 会话 ≈1 帧（~1.24 µs）/20 ms；app_ctrl 每槽每 1.6384 µs 采一次，单次命中率 ~0.76；60 s 内约 3000 次 ⇒ 实际必中。若按现文 60.4 ms（仅 ~3 次会话）仍有 ~1.4% 的跑当拍没抓到，但计数不清零（accrue/work 仍真），下一次会话（≤20 ms）点火 ⇒ 延后不是丢失。
- 真漏掉的两类（设计未登记）：① `inflight==0` 的空闲 ESTAB 死对端（work=假，永不回收；无法与活的空闲连接区分；最多 3 个 HLS cid，有界）；② `snd_wnd==0` 的死对端（1.3）。
- 设计 §9-6"慢生产者（<1 KB/s）永不填窗 ⇒ 永不回收"【不实】：有未 ACK 数据就有 RTO/retx 支。§9-6 应换成上述两类。

### 1.5 ⭐⭐ 60 s 时基算错 1000× —— 【不实·设计阻断】

设计行 48："计数单位 = 256 个扫描轮 = 419.43 µs（scan_round[7:0]==0 那一轮；app_ctrl 扫描轮 = 1.6384 µs @156.25MHz）"；行 210："256 × 1.6384 µs = 419.43 µs ⇒ 60.40 s；8 位饱和上限 106.9 s"。

现读 RTL：
- `app_ctrl.v:455-457`：`tick_cnt` 4 位，`scan_tick=(tick_cnt==4'd15)` ⇒ 每 16 拍一次；`scan_id` 每个 scan_tick +1。
- `app_ctrl.v:1077-1079`：`if (scan_id==4'd15) scan_round<=scan_round+1;` ⇒ 每 16 scan_tick = 256 拍 = 1.6384 µs 加一。
- `orph_tick=scan_round[7:0]==0` ⇒ 每 256 round = 419.43 µs；每槽每个 tick round 采一次 ⇒ 每槽计数间隔 419.43 µs。
- `144 × 419.43 µs = 60.398 ms`（不是 s）；`255 × 419.43 µs = 106.954 ms`（不是 s）。

⇒ 按默认值实施出来的门限是 **60.4 ms**（3×RTO、<400 ms、<2.56 s）；8 位 tick 在 156.25 MHz 下最大只能 106.9 ms，物理上到不了 60 s。

**必须修**：`ORPHAN_TICK_BITS` 默认改 **18**（`scan_round[17:0]==0` = 262,144 轮 = 429.50 ms ⇒ 144× = 61.85 s；饱和 255× = 109.5 s），或 1 s 独立时基/更宽计数；重写 §3.3 阈值论证、§6.3/§7.4 时间表、§9-1。注意 #64：这是另一次构建的输入。设计里的"106.9 s / 60.4 s"恰好等于 tick=419.43 **ms** 的正确乘积 ⇒ 意图是 419 ms/tick，文字单位写错。

---

## 2. 攻击线 2 —— Q1 的"释放侧不通知"结论

### 2.1 rx_classify 纯 ACK ⇒ FAST：【属实】
`rx_classify.v:102` `cur_tcp_ctl=|tdata[2:0]`；`:107` `dec_val = dec_w5 ? (cur_tcp_ctl ? RT_SLOW : RT_FAST) : RT_SLOW`。纯 ACK/带数据 ACK 的 FIN|SYN|RST=0 ⇒ FAST；只有 SYN/FIN/RST 进 SLOW。

### 2.2 HLS 静默释放链：【属实】
`layer_tcp.cpp:668-679` 被动 T_LISTEN 发 cfg ADD+SYN|ACK 进 T_SYN_RCVD；第三个 ACK 纯 ACK ⇒ FAST ⇒ `:680` 不可达；超时 `:531-535` `state=T_FREE; retrans_pending=false; continue;` 不写 cfg（cfg_write 调用点 = `:609/:637/:663/:677/:699/:721`，无一处在此）。`MAX_TCP_CONN=3`（`:10-12`）；~2.56 s 与 C1 板级一致。

### 2.3 "DEL 是灾难"：【属实】
`slow_cfg_adp.v:145-168` DEL 清 CAM + state=0 + ev_down；每条健康被动连接都在 ~2.56 s 被静默释放 ⇒ 全部被拆。P4b-5 的"慢路径不能对看不见的连接做主动动作"同理。

### 2.4 REL 不必要：判断【属实】
快路径判死所需量都在快路径；省 2.56 s 相对 60 s = 4%。后备 B 注意：`slow_cfg_adp` 的 `is_add/is_del` 只有 0/1，**任何未知 cmd 会落进 DEL 的 else 支**（`:145-168`）——实施 cmd=2 必须同时改解析器，否则拆连。

### 2.5 orphan_down 并入 ev_down 块：【部分不实】
现读 `app_ctrl.v:973-1054`：ev_down 块做 `stat_ev_down++`、`o_ev_down/o_ev_slot`、`fin_req/rst_req<=0`、`pool<=pool_ret_x`、`winq<=0`、`wu_*<=0`、`fc_pend<=0`、`st_pend<=0`、`to_pend/to_fired/fin_to<=0`。但：
- **`st_done` 不被 ev_down 清**（`:1047-1052` 无 st_done，只在 ev_up `:1014` 清）⇒ 设计"清 st_*"过度声称。
- ⭐ **`ret_slot_q/pool_ret_x`（`:880-883`）在 ev_down 块之外，依赖原始 `ev_down ? winq[ev_slot] : winq[scan_id]`**。并入 ev_down_i 时必须同步改，否则 orphan 会走 scan_id 分支归还**错误槽**配额（或 0）。设计 §8-9 use-point 清单**漏了这一处**。
- `orph_down` 投递门 `!ev_up && !ev_down && !to_push && !ev1_v` 漏 `!to_pushed_r`：`to_push` 自身含 `!to_pushed_r`（`:698-699`），超时投递下一拍 `to_push=0`、ev1_v（按原始事件）也为 0 ⇒ orphan 可在那一拍投递 ⇒ `o_ev_down` **连续两拍高**，违反 F4 孤立脉冲契约。必须加 `!to_pushed_r`（或 ev1_v 改为"上拍有任何投递"）。
- `ev_push=(ev_up||ev_down)&&!ev_full`（`:437`）保持原始 ev_down、`stat_ev_drop` 条件改回原始事件：设计已写，本审确认为必需。
- 位宽/优先级：ev_slot 4 位、orphan_slot 4 位无截断；mux 优先级由 `!ev_up && !ev_down` 保证外部事件优先；这部分设计写对。

### 2.6 orphan_down 不进事件 FIFO：【设计已钉死，属实】
`ev_push/ev_din` 只看原始 ev_up/ev_down；peer 字段只在原始脉冲拍有效。

### 2.7 Q3 的"Δstat_ev_down 可观测"：【不实】
`wrapper_p4.v:1321-1322` `.stat_ev_up()/.stat_ev_down()` 空接；`:1346-1348` app_reg_addr=8'h00/wr=0/wdata=0 ⇒ 寄存器 0x91 板上不可读；PCIe 快照 75 字里没有 stat_ev_down（W71..W74 是 app_pattern 的 E12；app_ev_drop 只去 status UART，`:1454`）。Q3 §4.3 应改为"pcap RST seq + app closing/重连"；W75 只计孤儿回收，不能当 DEL 的 Δ 计数。

---

## 3. 攻击线 3 —— ADD/回收竞态三道防线

### 3.1 防线 1（scfg_busy 门）：【部分不实】
现读 `slow_cfg_adp.v`：`cam_cfg_wr` 是寄存器，S_CAM 拍 `cam_cfg_wr<=1; state<=S_TCB`（`:129-155`）⇒ `cam_cfg_wr=1` 那拍 state=S_TCB，busy=1，CAM 写在该拍结束沿落地。S_TCB_LAST 拍 `upd_wr<=1`，gnt 沿 `upd_wr<=0; ev_up<=1; state<=S_RECV`（`:187-197`）⇒ **ev_up 为高那拍 state=S_RECV、FIFO 空 ⇒ busy=0**，而 ADD 的 CAM 写已在此前约 10 拍完成。若 orph_cam_req 在等待（fire 在这条 ADD 记录期间），FSM 会看到 `!busy` 并在这一拍登记 `orphan_cam_clr` ⇒ 下一沿擦掉**新 ADD 的 CAM 条目**。设计的"形式化"只覆盖 S_CAM/S_TCB 期，没有覆盖"busy 在记录结束后落 0"这一拍。

### 3.2 防线 2（scfg>fc）：【不实·设计阻断】
设计 §3.6："`ev_up` 在 wscale 授权拍生成，而**该拍 scfg_upd_wr=1** ⇒ sel_fc=0 ⇒ fc 不可能同拍落地；下一拍 app_ctrl 已看到 ev_up 并清 st_pend/中止 ⇒ state=0 不会落在新 ADD 之后。"

现读时序（设 gnt 沿为 D）：
- 沿 D：TCB 写 wscale（upd_sel=6）落地，同时 `upd_wr<=0; ev_up<=1; state<=S_RECV`。
- 循环 D（ev_up 高）：`scfg_upd_wr=upd_wr=0`。
- `wrapper_p4.v:2060` `sel_fc = !sel_tx && !sel_rx && !scfg_upd_wr && fc_upd_wr` ⇒ 若 fc_v=1 且 tx/rx 空闲，**sel_fc=1**。
- 沿 E：`tcb_wr` 含 sel_fc（`:2061`）⇒ TCB 写 `fc_upd_sel=5/val=0` ⇒ **state=0 落在 wscale 写下一拍**。
- app_ctrl 在沿 E 才执行 `st_pend<=0; if (fc_v&&fc_id_r==ev_slot) fc_v<=0`（`:1007,1014-1016`）——撤不回同沿写。

⇒ 前提 (a) `ev_up` 拍 scfg_upd_wr=1 不成立；(b) 下一拍清 st_pend 不能阻止同沿 fc 写。新会话（C1 偷槽）被写成 state=0：CAM 仍是新条目，tcp_rx 全丢（`tcp_rx.v:309,347`），HLS 还停 T_SYN_RCVD ⇒ 新连接静默死。

**必须修**：orphan-sourced 的 fc state 写加**组合门**（如 `fc_upd_wr_eff = fc_v && !(ev_up&&ev_slot==fc_id_r) && !(ev_down&&...)`），或走带组合取消的专用通路。注意既有 FIN-timeout/abort 的 st_pend 走同一 fc 通道，**同族竞态可能是既存的**，应顺带复核。

### 3.3 防线 3（ev_up 同槽中止）：设计未钉死组合语义 ⇒ 按字面实现有洞
`app_ctrl.v:1014-1016` 的 st_done/st_pend 清、`:1007` 的 fc_v 清都是**寄存器**动作（下一沿）。设计 §3.2 步骤 3 只说"清全部 pending"，没有说 `orphan_cam_clr` 的 **issue 条件**要组合看 abort。结合 3.1/3.2：**组合 abort 是唯一能同时关掉 CAM 清与 fc 写的防线**。必须写成 `orphan_cam_clr <= orph_cam_req && !scfg_busy && !abort_comb`；fc orphan 源也带 `!abort_comb`；U6 加 **post-fire** 变体（fire 后 1–2 拍再来 ev_up），现有 U6 只测 pre-fire（cnt=LIM-1 时 ev_up）。

### 3.4 DEL 同槽竞态：【属实（幂等）】
DEL 记录期 busy=1 挡 CAM 清；记录结束 ev_down 拍 busy=0，若 orphan clr 登记，清的是正在被 DEL 的槽（S_CAM 已清）⇒ 二次清零无害；state=0 的 fc 写同理；ev_down 中止 FSM 不发通知。

### 3.5 Replay 会话竞态：state=0 停重放【属实】；但 replay_full 自持【不实】
- `tcp_tx_frame.v:783-795/1704-1709`：ring_start/replay_jump/ring_restore 全要求 scan_estab；state=0 后全 0。`ring_eval` else（`:1234/2337`）清 retx_active；已进 TX 引擎的 1 帧照常发完；rto_pend 在 rb_state!=1 时被扫描清（`:1245-1246`）⇒ 动作 3 功能结论成立。
- 但 §3.2 的"replay_full 只有 snd_nxt 被新 app 帧推进到 ring_hi 才收尾；app 停帧可能自持"**不实**：`tcp_tx_frame.v:634 upd_wr_data=(rx_state==RX_FIN)&&(fin_cnt==0)` **无 !retx_active**；`:639 upd_wr` 含它；`:644-649 upd_id=f_conn[rx_bank], upd_val=f_seq+f_plen`；`:1200-1213` ring_start 把 f_conn<=retx_id_r、f_seq<=rb_snd_nxt、f_plen<=plen_preset ⇒ **重放帧自己推进 snd_nxt**，ring_delta 随重放排空，会话自然收尾。被 !retx_active 门的只有 `:1135` 的 whi_r。⇒ retx_active 支的真实价值 = 覆盖 inflight<cap 的**周期 RTO 会话**，不是"自持态兜底"；§8-17/§9-11 应改写，点火时机是概率性/周期性而非结构恒真。

### 3.6 fc 饿死 + 动作顺序：【未覆盖（F9）】
动作 2 的两个动作并列：CAM 清先落、fc 写被 tx/rx/cfg 长期压住（§9-4 自认无超时）⇒ 窗口内 CAM 已清、state 仍 ESTAB、app 仍 active ⇒ tcp_tx start_data 仍可启动，`cam_rd_dmac/sip/sport/dport`（`wrapper_p4.v:2234-2238`）读回全 0 ⇒ 线上出现 dst MAC 00.. / IP 0.0.0.0 / port 0 的帧。对端已死无实际危害，但这是自造的无意义线上流量且窗口无上界。建议先 state=0 再清 CAM，或 TX 启动门加 orphan_pending。

---

## 4. 攻击线 4 —— app_ctrl 改动面与零回归

### 4.1 16×8 / ORPHAN_LIM / 时基：【数量属实；60 s 乘积不实（F1）】
16×8=128 FF；orph_saw 16；FSM ~15；stat_orphan 32；slot 4 ⇒ ~195（§0）/191（§3.4 不含 slot）。量级合理。时基 419.43 µs 的数量正确，但 144× = 60.398 ms、255× = 106.954 ms。

### 4.2 ~191 FF：【属实（量级）】
与设计两处数字一致（§0 195 / §3.4 191，差 4 FF 是 slot 是否计入）。

### 4.3 ORPHAN_EN=0 逐位退化：【部分不实】
- 显式与 ORPHAN_EN 相与的纪律方向正确。
- 但"默认 0 ⇒ 既有 TB 不改、逐位不变"只对直接例化 app_ctrl 的 TB 成立（≥8 个例化点：tb_app_fc / tb_app_wu×2 / tb_p5_adv / tb_p5_app / tb_p5_multi / tb_wu_f2 / tb_wu_p1p2×2 等）。wrapper `:1279` 的 u_app_ctrl 要改成 ORPHAN_EN(1'b1) ⇒ **所有编译 wrapper_p4 的 APP_MODE 门（含 p5_wrapper #19）都启用新逻辑**。
- 文件级 `fc /b` 对"被改文件"不适用；要证零回归应做：(a) ORPHAN_EN=0 同激励全输出逐位对比（o_ev_up/o_ev_down/o_ev_slot/stat_ev_up/stat_ev_down/pool/winq）；(b) 或综合后网表等价/位流对照。U10 只查新输出为 0，不能证明既有行为不变。
- 建议明确 wrapper 的启用作用域（全部 APP_MODE 还是仅板配置）。

### 4.4 replay_full 兜底：【不实（F5）】
见 3.5。retx 支保留，理由改为 inflight<cap 的周期 RTO 会话覆盖；§8-17/§9-11 可由源码判定"不存在自持"，不必再排 xsim 臂。

### 4.5 "8 个直接例化 app_ctrl 的 TB"：【属实（量级）】
现读例化点约 8–9 个（含 tb_app_wu/tb_wu_p1p2 各两臂）。

---

## 5. 攻击线 5 —— 判据与板级设计

### 5.1 U1–U10 / C1–C4 有牙性

- **M1（LIM=0 ⇒ U1 红）**：U1 只写"snd_una 每 32 轮 +1"，未写构造 `win_closed` 或 `retx_active`、也未写 orph_saw。fire 需 `saw && (win_closed||retx_active)`；若 U1 是小在飞无重传 ⇒ LIM=0 也不点火 ⇒ **M1 存活**。必须补见证。
- **M2（删 snd_wnd!=0 ⇒ U3 红）**：删后 cap_eff=0 ⇒ win_closed=(inflight<2^31)&&(inflight>=0)=真；fire 还需 saw。U3 表未写 retx 见证 ⇒ **M2 存活**。必须注入一次 retx。
- **M3（删 retx 覆盖 ⇒ U5 红）**：U5 有 retx_active=1、nxt==una；删 work 的 retx 项 ⇒ accrue 假 ⇒ 不点火 ⇒ 红。成立（需明确删的是 work/fire 的 retx 项）。
- **M4（删 win_closed、留 retx 支 ⇒ U4c 红）**：**无效**。U4c = 小在飞冻结、**无活动重传**；原式两项都假 ⇒ 不点火；mutant 只剩 retx ⇒ 仍假 ⇒ 仍不点火。mutant 存活。要杀 M4，U4c 必须构造"小在飞 + 本槽 retx_active=1"（但那是设计本来就该点火的臂），或把 mutant 改成"第三项强制为 1"。
- **M5（删 ev_up 中止 ⇒ U6 红）**：删后 fire 仍需 saw && (win_closed||retx)；U6 未写这两项 ⇒ **可能存活**。必须补。
- **M6/M7/M8**：M6 的 CAM 内容检查只能在链级（U2 无 CAM）；M7 顺序断言在 U7；M8 的"app 收尾"只能在 C1（U2 无 app_pattern）。设计表格把 M6/M8 写成 U2 红点，标签错（不影响 mutant 存在，但门的归属要改）。
- **C1–C4**：C1 的 force 方案可行，但只给 wrapper `ORPHAN_LIM_5`、没给 `ORPHAN_TICK_BITS`；tb_p5_wrapper（125 MHz 单域）下 LIM=4 也要 ~2 ms 仿真，µs 级需暴露 TICK_BITS。C3 的 `!(orphan_cam_clr && scfg_cam_wr)` 在"scfg 优先 mux + busy 门"下是构造性真，只测第一道门，mux 第二路分支永不被激励；若要测 mux，断言应写"两者同拍时 CAM 写入的是 scfg 的值"。

### 5.2 B1 的 0x28 负臂 vs 0x2A 正臂单变量：【需限定】
HEAD=0x29（`wrapper_p4.v:2185 .PERSIST_EN(1'b0)`、`:4377 BID 0x29`）；0x29 = 0x28 内容 + persist 关 + BID。0x2A = 0x29 + persist 还原 + orphan fix + W75 + BID ⇒ **相对 0x28 的差异 = orphan fix + W75（纯观测）+ BID**，不是"只差孤儿修复"。W75 增加 snap_words_r 32 FF 落在 0x28 的 WNS 宿主族；严格单变量应先决定：(a) 接受 W75 为非行为第二变量并写明；(b) 或按 §7.5 先砍 W75 再跑 B1。

### 5.3 0x2A 构建前置：【属实（已写死）】
§7.3 第 1/2 条明确；现读 HEAD 确为 0x29。

### 5.4 B7 身份/几何：【不实（F4）】
`_proj_pcie/rtl/axi_regs.v`：`SNAP_LAST_IDX = 8 + SNAP_NW - 1`；MIR_STATUS=+1、DATA=+2、CTRL=+3、DMA_CNT=+4、MIR_LAST_IDX=+4；`r_word=araddr[7:2]`，地址=4×word。NW=75 现役：W74@0x148、MIR@0x14C/0x150/0x154/0x158、UNIMPL=0x15C（与 wrapper `:3288-3290` 一致）。NW=76：W75@**0x14C**、MIR_STATUS=**0x150**、DATA=0x154、CTRL=0x158、DMA_CNT=**0x15C**、**UNIMPL=0x160**。设计写"0x150..0x158 仍未实现、0x15C 仍是负对照"把 MIR 四个真寄存器当空洞；B7 读 0x15C 会得 mir_dma_cnt。必须改 **UNIMPL=0x160** 并同步所有 UNIMPL_ADDR 读者。另：`SNAP_NW_P6E` 75→76 会让 axi_regs 自动下移 MIR，不需要（也不应该）写死 MIR 地址；设计"不要用 0x20+4*NW 自动推"的提示与源码的"由 SNAP_LAST_IDX 自动推"相反。

### 5.5 W75 落 WNS 宿主族：【量级属实，措辞需精确】
`p9_build_0x28/q_stdout_x28.txt:75-78` 全局 WNS +0.065 宿主 = `user_reset_reg → u_pcie_regs/snap_words_r_reg[2224/2066/2277]/CLR`（Recovery，lvl=0）。每字 96 FF = snap_words_r 32（宿主网）+ dout_a 32（pcie，另一族 0.067/0.092）+ hold_b 32（DP）⇒ 只有 32 落被点名的宿主网。"+96 落宿主族"应改成"+32 宿主网、+32 dout_a、+32 DP"。砍 W75 可执行，但前提是 F4 地址先改对。

### 5.6 B1 读数：`ΔW68=0` 只对单连接构型成立（W68 是全局 ACK 推进计数）；B1 应写死"单连接、无其它流量"。B4/B5 的 >60 s 必须按 F1 修后真实门限重写。

### 5.7 板级慢盆混淆：【未覆盖（F11）】
0x28 构上存在全局慢盆态（`p9_basin_probe_20261017/README_FOR_TL.md:8`）：进入 = 真异槽并行抢流 + 小窗 2920【已证 ×2】；持久 ≥14 min；**清除 = 重烧（唯一）**（`:174`）；1 MB rcvbuf 免疫；签名 = 爬行 1.55 Mbps / 20 ms 簇 / W55=49.9/s。影响：B3（9 Gbps 健康快流）在盆内结构性做不到，必须新烧后快态先跑；B4 需盆在场但进入不可控，设计未给进入配方/见证；B1 负臂的 V55 持续增长会与盆签名混淆；0x28→0x2A 两次重烧都会清盆 ⇒ 臂序必须是"快态臂（B3/B5）→ 进盆臂（B4）→ 重烧 → 负/正孤儿臂"，每次烧后先核"盆不在场"（900 Mbps 级二值，`:174`）。

---

## 6. 攻击线 6 —— 回卷/饱和/参数

### 6.1 60 s 算术：【不实（F1）】
144×419.43 µs = 60.398 ms；255× = 106.954 ms。

### 6.2 8 位饱和上限：【不实（同上）】
设计 106.9 s，实为 106.9 ms；8 位饱和在 419.43 µs tick 下不可能覆盖分钟级。

### 6.3 参数化与 TB 小值：【机制属实，但 tick 位宽必须改】
参数化可行；TB LIM=2、TICK_BITS=1 → 2×2×1.6384 µs ≈ 6.6 µs。生产默认必须 18 左右（见 F1），scan_round 是 32 位、18 位比较无成本。wrapper 参数 ORPHAN_LIM_5 可行（wrapper_p4 现无参数表，加 #(parameter …) 不破坏按名例化）；全链 C1 若想 µs 级，wrapper 还应暴露 ORPHAN_TICK_BITS_5。ORPHAN_EN 作用域要写清（见 F13）。

### 6.4 与 RTO_LIM/persist 60 s 的阈值序：【意图属实；现参数不实】
`tcp_tx_frame.v:219-223` RTO_LIM=12207 ≈ 20 ms @156.25 MHz；`:299-301` PS_MAX ≈ 60.0 s、`ps_reload :407-419` 阶梯 20 ms→5→10→20→40→60→60 s。orphan 只在 snd_wnd!=0 时计数、persist 只在 snd_wnd==0 时武装 ⇒ **互斥、无直接边界竞态**（设计可把"互斥"写出来）。设计的"≫ RTO/≫ FIN 400 ms/≫ 2.56 s"在意图 60 s 下成立；在现文 60.4 ms 下全部反向。

---

## 7. 其它现读核对（不构成主要发现）

| 设计引用 | 现读结果 | 状态 |
|---|---|---|
| tcp_tx_frame.v:752-757 ps_arm / :219-223 RTO_LIM | 一致 | 属实 |
| slow_cfg_adp.v:158-168 ev_down / :187-198 ev_up / :129-198 ADD | 一致 | 属实 |
| tcb.v:151-157 win_open | `win_diff < min(snd_wnd,WIN_CAP)` 32 位回绕；设计的 win_closed 多 `<2^31` 守卫（有意超集，不是"同一不等式"） | 属实（措辞需改） |
| tcp_cam.v:49-55/58-69 | 一致 | 属实 |
| wrapper_p4.v:2155-2166 ack_seen_w | 只在 scfg_ev_up 清 | 属实 |
| wrapper_p4.v:2185 PERSIST_EN(1'b0) / :4377 BID 0x29 | 一致（HEAD=0x29） | 属实 |
| wrapper_p4.v:3296/3317 NW=75/35；:3285-3290 UNIMPL=0x15C | 现役 75 字档一致；76 字档推导见 F4 | 属实（75）/不实（76） |
| app_ctrl.v:455-457,545 scan 时基 | 一致 | 属实 |
| app_ctrl.v:861-874 to_fire/st_grace；:973-1054 ev_down 块 | 一致 | 属实 |
| app_ctrl.v:701-726,1311-1336 fc | 一致；fc_gnt 同拍清 st_pend 仅当 fc_sel_r==5 | 属实 |
| app_ctrl.v:1069-1079 扫描采样让位 | 一致 | 属实 |
| app_pattern.v:388,896-940 closing/W3 | 一致 | 属实 |
| layer_tcp.cpp 各引用 | 一致 | 属实 |
| p9_build_0x28/READINGS_BID28.txt | WNS +0.065 / LUT 77631 / FF 75086 / BRAM 348 | 属实 |
| q_stdout_x28.txt:75-78 | 宿主 user_reset_reg→snap_words_r_reg[*]/CLR | 属实 |
| 矩阵编译清单"不含 app_pattern/wrapper_p4" | `sim/p4gates/p5wrapper_src.f` 含 rtl/app_ctrl.v、rtl/app_pattern.v、board/wrapper_p4.v | **不实（部分）**；真盲区是板配置 |

---

## 8. 局限登记

1. **只读**：未跑 xsim/综合/板级；F2/F3 是源码时序推演（寄存器/组合/仲裁优先级），不是波形。建议实施前用单元门/波形复核一次。
2. 慢盆数据：10 条爬行连接是否并发、各自 snd_una 间隔只能从全局 W52/W68 反推（B1 W68=84.8/s）；"~118 ms/连接"是上界推算，不是逐连接读数。F1 不依赖该推算。
3. F1 是算术复核（clock/分频/乘积），不依赖口径解释；若本意是 TICK_BITS=18，文字与默认值必须同改。
4. F5 的 replay 排空由源码链推得，未用 xsim 验证"重放一帧推进 snd_nxt"的波形；设计若坚持"自持"，需给出与该源码链相反的读数。
5. 未复核 p9_c1_mech_doc 的 451 行全文（只读 C1 板级 README 的静默释放/2.56 s 段落）；本审 Q1 事实均由 layer_tcp.cpp/rx_classify.v/slow_cfg_adp.v 现读直证。
6. F11 的盆态影响：basin probe 的 0x28 构读数是全部依据；0x2A 构上盆是否存在/同签名未测。
7. F4 的地址推导是 axi_regs.v:206-218,368-428 的源码算术，未仿真。
8. 本审无 ssh/板/对端操作；密码纪律未触发。

---

## 9. 必须修的条目（按实施顺序）

1. **F1**：ORPHAN_TICK_BITS 默认改到能产生 ~60 s 的值（如 18）；重写 §3.3、§6.3、§7.4、§9-1。
2. **F2**：删"ev_up 拍 scfg_upd_wr=1"论证；给 orphan-sourced fc state 写加**组合 ev_up/ev_down 门**（或专用通路）；复核既有 st_pend 同族竞态。
3. **F3**：orphan_cam_clr 的 issue 条件加**组合 abort 门**；U6 加 post-fire 变体；B6 加 post-fire 臂。
4. **F4**：UNIMPL=0x160；B7/读侧/P7B_BIZ_WINDOW.md/apply_readside.py 同步；W75@0x14C 不变。
5. **F5/F6**：改写 §3.2/§8-17/§9-11（replay 不自持）；§9-6 换成"inflight==0 / 零窗死对端"。
6. **F7**：Q3 可观测路径改为 pcap + app closing；删 Δstat_ev_down。
7. **F8**：ret_slot_q/pool_ret_x 的 ev_down_i；orph_down 门加 !to_pushed_r；st_done 文案订正。
8. **F9**：动作顺序 state=0 先于 CAM 清（或 TX 启动门加 orphan pending）。
9. **F10**：U1/U3/U6 补 retx/窗满见证；M4 改成能红的 mutant；M6/M8 门归属改到链级。
10. **F11**：板级臂序 + 盆态见证 + 每次烧后清盆核对。
11. **F13**：ORPHAN_EN=0 同激励全输出逐位对比臂；明确 wrapper 启用作用域。
12. **F14/F15/F16/F17/F18**：文案/限定级，实施时同步。

—— 完（本件只读；不含 PASS/FAIL 裁定，不含实施授权）
