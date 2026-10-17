# FINDINGS_V2 — 红队复评：孤儿修复设计件 v2（`8658c373`）

> 被审件 = `p9_orphan_fix_design_20261017/README_FOR_TL.md`（636 行，v2）；方法 = 只读源码/留存读数；行号现读；未碰板/对端。⛔ 不裁 PASS/FAIL。
> 本件 = TL 代落（红队全文回报，平台拒写）。

## TL 处置块（2026-10-17 11:3x 现读施工）

- **全 15 项新发现（N1–N15）采纳 + 逐 F 条状态接受**。**v2 判定：需再修（v3）后才能进入实施**。
- **必修 6 组**：**F6-b（N1 阈值/persist 60 s 关系；N2 `ack_obs` 非 OVL 恒 0；N7 C2 零窗臂）** · **F9（N4 `state_done` 缺项 + C3 空判）** · **N3（`fireA/fireB` 缺 `!orph_busy` ⇒ 双槽同时达限 ⇒ 第一槽半回收——正是本设计要消灭的形态）** · **F10（N6 U1/U4/U12 量纲冲突）** · **F2/F13（fc 门作用域 + p5wrapper 重基线）** · **N5（`orph_down` 须钉成寄存器，否则组合环）**；其余 N8–N15 文案级随修。
- **v3 修订已派**（原设计 agent，附本 FINDINGS_V2 全文 + 选定修法指引）；v3 回来后由**红队做闭项抽查**（只核必修 6 组 + 是否引入新竞态），不再全文三审。
- 关键教训登记：**F6-b 的"误杀活零窗对端"是阈值–探询周期的耦合问题**（61.85 s vs 60 s 封顶 = 1.85 s 余量；一次丢探询 = 120 s 间隔 ⇒ 必杀）——设计新判据时必须先算**最坏重试间隔**（不是"典型间隔"），并把计数器位宽的上限一并算进可行性（8 位 × 429.5 ms = 109.5 s 物理到不了 120 s）。

---

## 0. ≤30 行摘要（红队原文）

1. **F1 闭项属实**：262,144 × 1.6384 µs = **429.4967 ms**/tick；144× = **61.8475 s**；255× = **109.5217 s**；3092×/155×/24× 比值复算全中；v2 活句无 "60.4 s"。**闭**。
2. **F2 主体闭**：`fc_upd_wr = fc_v && !(ev_up&&ev_slot==fc_id_r) && !(ev_down&&…)` 逐拍推演正确。**但**该门是对**既有 FIN-timeout/abort 路径**的行为改动，v2 未说明它是否在 `ORPHAN_EN` 内 ⇒ 与 F13 的 U10'（ORPHAN_EN=0 逐位相同）**互斥**；必须钉死作用域。
3. **F3 主体闭**：`orph_cam_clr = req && !scfg_busy && !abort_comb` 的组合门正确；`wcnt!=0` 补 busy 正确。**但** issue 表达式（§3.2 步骤 3）**漏 `state_done` 项** ⇒ F9 的 state-first 顺序可退回 v1 的零 CAM 窗口。
4. **F4 闭项属实**：W75@0x14C；MIR 0x150/0x154/0x158/0x15C；UNIMPL=**0x160**；MIR 由 `SNAP_LAST_IDX` 自动推（`axi_regs.v:206,214-218`）。**部分**：读侧清单未点名已知三件（`check_window.py`/`tb_biz_win.v`/`tb_p6e_pcie_wrapper.v`）。
5. **F5 闭项属实**：删"自持"、改写 retx 支价值，与 `tcp_tx_frame.v:634,648,1200-1213,1385` 源码链一致。
6. ⭐ **F6-b 未闭（阻断）**：61.85 s vs persist **60 s 封顶**只余 **1.85 s**；**任意一次 60 s 档探询或其 ACK 丢失** ⇒ ack_obs 间隔 **120 s > 61.85 s** ⇒ **误杀活零窗对端**。v2 的残余"61.85 s 内所有 ACK 都丢"**严重低估**。8 位计数器最大 109.5 s，**物理上到不了 >120 s** ⇒ 必须加宽 ZW 计数/换 ZW 专用 tick（或改判据）。
7. ⭐ **F6-b 第二问题**：`tcp_rx.ack_obs` **只在 `TCP_TX_OVL` 支置位**（`tcp_rx.v:617-626`；`else` 支恒 0）。v2 §9-12"OVL/默认两支都置位"**不实**。p5wrapper 门（无 TCP_TX_OVL）里 `ack_obs≡0` ⇒ **Mode B 会误杀其零窗臂**；C2 零窗臂未按 Mode B 更新。
8. **F6-a 登记属实**：界（≤3 HLS cid / 无线上流量 / 连续 app 瞬态 / FIN/to_fire 收尾）站得住；建议补"winq 由同槽 ADD 的 C18 归还"一句；"不许算已闭"措辞到位。
9. **F7 闭项属实**：Q3 改 pcap + app closing；`Δstat_ev_down` 删除。
10. **F8 闭项属实**（`ret_slot_q/pool_ret_x`、`!to_pushed_r`、`st_done` 文案均已改）。**但** `stat_ev_drop` 行号写成 `:1376`（实为 `ev_ovf`；stat_ev_drop 在 `:974`），且 `ev_ovf` 这个 use point 未列入"保持原始"；另 `to_push ← !orph_down` 与 `orph_down ← !to_push` 互为条件，**必须把 orph_down 钉成寄存器**否则组合环。
11. **F9 部分闭（未闭）**：state-first 的**中间态安全**（tcp_rx `state_ok=假` 丢弃；tcp_tx `st_ok=假` 不开帧；app_tx_ready 扫描后落 0）——F9 的零 CAM 帧窗口确实关闭。**但** CAM 清 issue 表达式缺 `state_done`；且 C3 断言写"`st_pend` 且 state 已 0"——`st_pend` 在 fc gnt 沿已被清（`app_ctrl.v:1323`），该断言会**恒假/空判**。必须新增 `orph_state_done` 寄存器并进 issue 条件。
12. **F10 部分闭**：U1/U3/U6 的 witness 已写（M1/M2 可红、M4' 可红），但 **U1"每 4096 轮"、U4"每 1000 轮(<LIM)"、U12"每 5 s" 与 §3.3 声明的 TB 小值（LIM=2/TICK_BITS=1 ⇒ 6.6 µs）量纲冲突**：U1/U4 会在第一次进度前就达 LIM；U12 的 5 s 注入永远等不到 ⇒ 基线即红/负对照空转。U6 只写"fire 后 1–2 拍"，未覆盖"state gnt 后、CAM 清前"这段（F9 的真实窗口）。**必须按 tick 单位重写刺激**。
13. **F11 闭项属实**：臂序（快态→进盆→重烧→孤儿臂）+ 盆见证 + 重烧清盆；B5b 未列入 §6.3 编号臂序（只在 §7.4 出现），B5 在 §7.4 又漏；时长 2×LIM 已按 61.85 s 改为 ≥124 s。
14. **F12 闭项属实**（p5wrapper_src.f 含三文件；真盲区=板宏配置）。
15. **F13 部分闭**：U10' 可执行（需快照当前 HEAD app_ctrl，项目有 `app_ctrl_base` 先例）；但 F2 的 fc 门作用域未钉、p5wrapper 全 APP_MODE 启用后"重基线"会削弱该回归门（建议 wrapper 暴露 `ORPHAN_EN_5` 或该门显式传 0）。
16. **F14–F18 闭项属实**。
17. ⭐ **v2 新引入（须修）**：N1 Mode B 阈值 vs persist 60 s；N2 `ack_obs` 非 OVL 恒 0 + C2 零窗臂；N3 **`fireA/fireB` 无 `!orph_busy`**（单 FSM 被第二槽覆盖 ⇒ 第一槽 state=0 半回收、winq 不还、无 orph_down）；N4 CAM 清缺 `state_done`；N5 `orph_down` 必须为寄存器；N6 U1/U4/U12 量纲；N7 C2 零窗语义；N8 `stat_ev_drop`/`ev_ovf` 行号；N9 B5/B5b 臂序；N10 wrapper 未暴露 `ORPHAN_ZW_EN_5`；N11 U10' 冻结锚未点名；N12 p5wrapper 重基线削弱回归门；N13 F6-a 界未提 winq；N14 行号漂移；N15 U2 "visits" 无定义。
18. **结论（读数层，不裁 PASS/FAIL）**：**需再修后才能进入实施**——必须修：**F6-b（N1/N2/N7）· F9（N4）· N3（FSM 串行）· F10（N6）· F2/F13（fc 门作用域）· N5（orph_down 寄存器）**；其余为文案/清单级。

---

## 1. F1 闭项核（时基/阈值）

**闭项属实。** 复算：
- `scan_tick` 每 16 拍（`app_ctrl.v:455-457`）；`scan_round` 每 16 个 scan_tick = 256 拍 = 1.6384 µs（`:1077-1079`）。
- `ORPHAN_TICK_BITS=18` ⇒ 2^18 = 262,144 轮 × 1.6384 µs = **429.4967296 ms**。
- ×144 = **61.8475 s**；×255 = **109.5217 s**。
- 比值：61.85/0.02 = 3092.4；61.85/0.4 = 154.6；61.85/2.56 = 24.16 —— §3.3 的 ≈3092×/≈155×/≈24× 全中。
- 全文 grep：`60.4` 只出现在 F1 问题列与订正句；`419.43` 只在 v1 错误句；活值统一 61.85/429.4967/109.52。**无残句。**
- §6.3 B1/B3/B4/B5 的 2×LIM = ≥124 s；§7.4 同步。✅
- 一个未写但安全的边缘：`scan_round` 在 `init_pend`/同槽事件拍不增（`:1069-1079`），tick 会拉长，方向安全；v2 §3.2 已写（F17）。✅

## 2. F2/F3 闭项核（竞态）

### 2.1 F2（fc 组合门）：机制闭，作用域未钉
- 现读时序同 v1 审查：`slow_cfg_adp.v:187-197` 的 gnt 沿 `upd_wr<=0; ev_up<=1; state<=S_RECV` ⇒ ev_up 拍 `scfg_upd_wr=0`；`wrapper_p4.v:2060` `sel_fc` 可开；`:2061` `tcb_wr` 含 sel_fc ⇒ 无门时 state=0 落在 wscale 写后一拍。
- v2 门 `fc_upd_wr = fc_v && !(ev_up&&ev_slot==fc_id_r) && !(ev_down&&ev_slot==fc_id_r)`：ev_up 拍把 `fc_upd_wr` 关死 ⇒ `sel_fc=0` ⇒ 沿 E 无 fc 写；事件块沿 E 清 `fc_v/st_pend`。**逐拍正确**。
- 组合环：`fc_upd_wr`（app_ctrl 输出）→ wrapper `sel_fc` → TCB；`ev_up/ev_slot` 是 slow_cfg_adp 的寄存器输出；`fc_id_r` 是寄存器 ⇒ 无环。✅（§8-2 论证成立）
- ⭐ **未钉的一点**：该门同时修改**既有 FIN-timeout/abort 的 `st_pend`** 路径（v2 明说"同批闭"）。若门不在 `ORPHAN_EN` 内 ⇒ `ORPHAN_EN=0` 的新 RTL 与冻结锚在"ev_up + fc_pending 同拍"刺激下**必然不同** ⇒ F13 的 U10'"逐位相同"不成立。若门在 `ORPHAN_EN` 内 ⇒ 既有路径的修复只在孤儿构建（板构建）生效，U10' 可成立。v2 两处均未写。**必须钉死**。
- 现有 `fc_v` 的清除是沿 E 的寄存器动作（`app_ctrl.v:1007,1014-1016`），不能撤沿 E 的写——v2 的门正是在组合侧解决，✅。

### 2.2 F3（CAM 清组合 abort + wcnt）：机制闭
- ev_up 拍 `state=S_RECV`、`f_empty` ⇒ `busy=0`，而 ADD 的 CAM 写已在此前约 10 拍完成；v2 加 `!abort_comb`（组合，含同槽 ev_up/ev_down/fin_sent/rst_sent）⇒ 该拍不登记 clr；寄存器的 pending 清位在沿 E 生效 ⇒ 下一拍无 clr。**正确**。
- `scfg_busy` 补 `(wcnt != 3'd0)`：记录中途（w0..w7 之间）FIFO 空时 busy=1，覆盖了 v1 的缺口。✅
- 与 F2 自洽：abort_comb 同时关 clr 与（经 F2 门）fc 写。✅
- **但** §3.2 步骤 3 的 clr issue 表达式只写 `orph_cam_req && !scfg_busy && !abort_comb`，**没有 state_done 项**——见 F9。

## 3. F4 闭项核（地址几何）

**闭项属实（算术与源码一致）。**
- `SNAP_LAST_IDX = 8 + SNAP_NW - 1`（`_proj_pcie/rtl/axi_regs.v:206`）；MIR_STATUS=+1、DATA=+2、CTRL=+3、DMA_CNT=+4（`:214-218`）；`r_word=araddr[7:2]`，地址=4×word。
- NW=75 现役：W74@0x148、MIR 0x14C/0x150/0x154/0x158、UNIMPL=0x15C（与 `wrapper_p4.v:3288-3290` 一致）。
- NW=76：W75@**0x14C**、MIR_STATUS=**0x150**、DATA=0x154、CTRL=0x158、DMA_CNT=**0x15C**、**UNIMPL=0x160**（word 88）。v2 §1.5/§3.7/§5/§6.3 B7/§7.3 均一致，且明确"MIR 自动推、不写死"。✅
- B7：`0x14C=W75`、`MIR 0x150..0x15C`、`0x160=0xffffffff`；0x28 负臂 `NW=75/UNIMPL=0x15C`。✅
- **同步清单（部分）**：v2 列出 `p6e_snap_check.sh` WLABEL、`apply_readside.py`、`P7B_BIZ_WINDOW.md` §1、"一切 NW/UNIMPL/EXPECT_BID 读者"，并写"重新穷举，不要照抄 63 处/20 文件"。但 `board/wrapper_p4.v:3279-3280,3293-3295` 自己点名的三处已知常量（`check_window.py`、`tb_biz_win.v`、`tb_p6e_pcie_wrapper.v`）**未点名**。建议补入清单。

## 4. ⭐ F6-b 新设计（模式 B：零窗失联）攻防

### 4.1 `ack_obs` 存在性与语义：**部分不实（v2 声称"OVL/默认两支都置位"）**
- `tcp_rx.v:129-130` 端口；`:617-623` **`ifdef TCP_TX_OVL` 支**：`ack_obs<=1; ack_obs_id<=conn_id_l`，条件 = `fend && s_axis_tcrs && !fend_trunc && (dup_l || ack_adv_l || ackok_l)`。
- `:624-626` **`else` 支：`ack_obs <= 1'b0; ack_obs_id <= 4'd0;` 恒 0。** ⇒ v2 §9-12"OVL/默认两支都置位"**事实错误**。
- 语义上（OVL 支）：`ackok_l` 是 `ack_ok` 锁存（ack 在 `[snd_una, ack_hi]`），`dup_l`/`ack_adv_l` 都是其子集 ⇒ **任一合法 ACK（含零推进/零窗）**脉冲。persist 探询的 ACK（对端对重复段的 ACK）ack ∈ 范围 ⇒ `ack_obs` 会脉冲。✅ 与 v2 的描述一致（但仅限 OVL）。
- **影响**：板构建（`TCP_TX_OVL=1`）可用；`tb_p5_wrapper`/p5wrapper 门（`p5wrapper_src.f` 头注释明写不含 `TCP_TX_OVL`）里 `ack_obs≡0` ⇒ **Mode B 在任何零窗臂上都会点火**。C2 的"零窗 ⇒ 无点火"在该配置下**结构性失败**。必须：(a) 该门配置定义 `TCP_TX_OVL`（改变门的性质），或 (b) wrapper 暴露 `ORPHAN_ZW_EN_5` 并在非 OVL 门传 0（并另设 OVL 全链臂测 Mode B），或 (c) TB 直接 force `ack_obs`（不测真 tcp_rx 路径）。v2 未选。

### 4.2 模式 B 判据可综合性：**属实**
- `zw_accrue = scan_tick && !init_pend && !(ev_blk&&ev_slot_i==scan_id) && state==ESTAB && snd_wnd==0 && snd_nxt!=snd_una && !fin/!rst/!st_done/!to_fired`；`orph_zw_cnt` 8 位饱和、同一 `orph_tick`；`ack_obs` 逐拍清。可实现。
- 与模式 A 的互斥：`snd_wnd!=0` vs `==0`；同一采样拍只能一个 accrue。窗口翻转时两个计数器都被各自的 `!accrue` 清零。✅
- 与 persist 的共存：persist `ps_arm` 只在 `snd_wnd==0 && nxt!=una` 武装（`tcp_tx_frame.v:752-757`），与 Mode B 同条件；探询 ACK 是 Mode B 的唯一活证。✅（但见 4.3）

### 4.3 ⭐⭐ 误杀场景：**阈值 vs persist 60 s 封顶 —— 未闭（阻断）**
- persist 退避：`ps_reload`（`tcp_tx_frame.v:407-419`）= 20 ms → 5 → 10 → 20 → 40 → **60 → 60 … s**；`PS_MAX ≈ 60.0 s`（`:299-301`）。
- 活零窗对端在稳态只靠 **60 s 一次的 persist 探询** 产生 ACK。Mode B 阈值 **61.85 s** ⇒ 余量 **1.85 s（3.0%）**。
- **任意一次 60 s 档探询或其 ACK 丢失** ⇒ 相邻 `ack_obs` 间隔 **120 s > 61.85 s** ⇒ **在下一探询的 ACK 到达之前就点火** ⇒ **误杀活对端**。
- v2 残余都写"61.85 s 内**所有** ACK 都丢"——**严重低估**（实际是"**任意一次** 60 s 档探询/ACK 丢失"）。
- 8 位 `orph_zw_cnt` + 18 位 tick 的**物理上限 = 255 × 429.4967 ms = 109.52 s < 120 s** ⇒ **现参数化无法容忍一次丢探询**。必须改：
  (a) ZW 专用 tick（如 `ORPHAN_ZW_TICK_BITS=20` ⇒ 1.718 s/tick；`ORPHAN_ZW_LIM=105` ⇒ 180.4 s；8 位饱和 438 s）；或
  (b) 加宽 `orph_zw_cnt` 到 9/10 位（10 位 + 18 位 tick：LIM≈326 ⇒ 140 s，饱和 440 s）；或
  (c) 改判据（如 `ps_phase==5` 且连续 ≥2 个 PS_MAX 周期无 ack_obs 才回收）。
- **B5**（活零窗）若只跑 124 s、恰好两次探询都成功，会给出"未误杀"的**假安全**读数——B5 必须显式跑至少 2×60 s 且**记录探询/ACK 计数**，并在残余里写"单次丢失即误杀"。

### 4.4 `ack_obs` 的 OVL 依赖 + 测试配置（第二处新问题）
见 4.1。C2 的"零窗"臂与 U11/U12 的语义都要按 OVL/非 OVL 分开。**U12"每 5 s 注入一次"与 TB 的 `LIM=2/TICK_BITS=1`（6.6 µs）量纲冲突**（见 F10）——5 s 远大于 LIM，基线就点火。

### 4.5 模式 B 的回收动作与共享 FSM：**新增竞态（必须修）**
- v2 的 `fireA/fireB` 表达式**没有 `!orph_busy`（或任何全局忙门）**；FSM 只有一个 `orph_slot`/`orph_state_req`/`orph_cam_req`（§3.4 ~18 FF）。
- 两个槽在相邻扫描拍（16 拍 = 102.4 ns，或 1.6 µs 的槽间隔）都达 LIM 时：第一个 fire 挂起；第二个 fire 覆盖 `orph_slot`/pending；第一个槽的 fc 请求（若已装载，`fc_id_r=X`）不再与 `orph_slot=Y` 匹配 ⇒ 第一个槽的 state=0 可能已落或未落，但 **orph_down 永不发** ⇒ **winq 不归还、app 不通知、st_done=1 阻止重试** ⇒ 该槽"半回收"（state=0 + CAM 残留 + 配额占用）。这正是本设计要消灭的形态。
- v2 §9-6a 的"最多 3 个 cid"不覆盖这个**同时点火**（两个/三个 cid 同时黑洞是 B1/B5b 的自然场景）。
- **修法**：`fireA = ... && !orph_busy`、`fireB = ... && !orph_busy`（第二槽计数保持饱和，等第一槽完成后下一拍/下一扫描再点火）；或把 FSM 改成 per-slot 队列。必须写进 §3.2 与 U6（新增"双槽同时达限"臂）。

## 5. F9 闭项核（state=0 先、CAM 清后）

- **中间态安全性属实**：state=0 落、CAM 未清时——tcp_rx `state_ok=假`（`tcp_rx.v:309,347`）丢弃；tcp_tx `st_ok=假` 不开帧；app_tx_ready 扫描后落 0 ⇒ **不会出现 v1 的"零 CAM 帧"窗口**。✅
- **fc 被长期压住**：state=0 未落 ⇒ 连接仍 ESTAB、正常收发，**不是半死**（比 v1 的 CAM-first 更安全）；只是回收/通知延迟，`winq` 未还（§9-4 已登记无超时）。✅（残余，不阻断）
- ⭐ **未闭**：CAM 清 issue 表达式（§3.2 步骤 3）**缺 `state_done`**。`st_pend` 在 fc gnt 沿被清（`app_ctrl.v:1323`），因此：若照字面写，**state=0 未落时也可能发 CAM 清** ⇒ F9 回归；C3 断言③写"`orphan_cam_clr` 只在该槽 `st_pend` 且 state 已 0 之后出现"——**`st_pend` 在 gnt 沿已清**，该断言恒假/空判。
- **必须**：fire 设 `orph_state_req`；fc gnt 时置 `orph_state_done<=1`（寄存器）；CAM 清 issue = `orph_cam_req && orph_state_done && !scfg_busy && !abort_comb`；C3 改判 `orph_state_done`。

## 6. F10 闭项核（判据有牙）

- **M1/M2 的 witness 已写**（U1"每进度间隔内制造一次窗满 + 一次 retx_active"、U3"注入一次 retx_active"），按 tick 重写后可红。✅（意图）
- **M4' 有效**：U4c 有 saw=1、小在飞、无活动 retx、cnt≥LIM；第三因子强制 1 ⇒ 点火 ⇒ 红。✅
- **M5**：U6 的 pre/post-fire 必须显式带 saw+win_closed（否则删 abort 也不点火）；v2 未写。**部分**。
- ⭐ **量纲问题（必须修）**：§3.3 声明 TB 用 `LIM=2`、`TICK_BITS=1`（tick ≈3.3 µs；LIM=2 ⇒ 6.6 µs），但：
  - **U1 "每 4096 轮 +1，跑 2×LIM"**：LIM=2 ticks = **4 轮**；4096 轮 ≫ 4 轮 ⇒ 第一次进度前计数器已达 LIM ⇒ 正常臂就会点火（期望 stat_orphan=0 失败）。
  - **U4 "每 1000 轮 +1（<LIM）"**：1000 轮 > 4 轮 ⇒ 不是 "<LIM"；若注入 saw ⇒ 点火（负对照失败）；若未注入 saw ⇒ 负对照**因 saw=0 而假绿**（空判据）。
  - **U12 "每 5 s 注入 ack_obs"**：5 s ≫ 6.6 µs ⇒ 基线即点火，M10 的红无判别力。
  - **修法**：所有 U1/U4/U12 的刺激改写成 **tick 单位**（如 "snd_una 每 `LIM/2` ticks +1"、"ack_obs 每 `LIM/2` ticks 一次"、"保持 `2×LIM` ticks"）。
- **U6 post-fire**：只写"fire 后 1–2 拍"，未覆盖 **state gnt 后、CAM 清前**（F9 引入的新窗口）；必须加该臂（或 C3 ③ 的 state_done 断言覆盖）。**部分**。
- **U2 "每 12207 visits"**：在 app_ctrl 单元里 "visits" 无定义；TB 应写 "每 N ticks"。**措辞级**。
- **C3 mux 分支**：TB force 同拍碰撞、读 CAM 内容判 scfg 侧值——可实现。✅
- **C1 `ORPHAN_TICK_BITS_5`**：v2 已暴露。✅

## 7. F13 闭项核（零回归）

- **U10' 可执行性**：用**改前冻结锚** + 新 RTL（ORPHAN_EN=0）同激励、比全部输出——可执行（项目有 `sim/p5wu_p1p2/app_ctrl_base.v` 先例；但那是旧版，**必须快照当前 HEAD app_ctrl**，不能直接用旧的）。v2 未点名冻结锚文件。**部分**。
- ⭐ **与 F2 的冲突**：`fc_upd_wr` 组合门若是**全局**改动（不在 ORPHAN_EN 内），U10' 在"ev_up + fc_pending 同拍"刺激下**不可能逐位相同**。v2 必须二选一：(a) 门放进 `ORPHAN_EN` 内 ⇒ U10' 逐位成立、板构建有既存路径修复；(b) 门全局 ⇒ U10' 改"除同拍竞态外的逐位相同"+ 定向臂证明行为改动是期望修复。
- **p5wrapper 重基线**：v2 说"全部 APP_MODE 构建（含 p5wrapper #19）都启用新逻辑 ⇒ 期望输出要按 U10' 重新基线"——**这是回归门的削弱**（p5wrapper 是现役 19 门之一）。更稳：wrapper 暴露 `ORPHAN_EN_5`，p5wrapper 显式传 `1'b0`（保旧基线），板构建传 1；或"仅板宏配置（P7B_10G/DP_156MHZ）启用"。**建议修**。

## 8. F6-a 未闭登记核

- 界逐条站得住；补一句 **winq 归还在同槽 ADD 的 C18（`app_ctrl.v:987-991`）**；"不许算已闭"措辞到位。**登记属实**。

## 9. v2 新引入问题清单（按严重度）

| # | 严重度 | 问题 | 必须修 |
|---|---|---|---|
| **N1** | **阻断** | Mode B 61.85 s vs persist 60 s 封顶：余量 1.85 s；**一次 60 s 档探询/ACK 丢失即误杀**；8 位 ZW 计数器最大 109.5 s 无法到 >120 s | 换 ZW 专用 tick（20 位 ≈1.718 s/LIM 105 ⇒ 180 s）或加宽 ZW 计数到 9/10 位；重写残余为"单次丢失即误杀"；B5 跑 ≥2×60 s 并记探询/ACK 计数 |
| **N2** | **阻断（门/测试）** | `ack_obs` 仅 `TCP_TX_OVL` 支置位；`else` 恒 0（`tcp_rx.v:624-626`）。v2 §9-12 不实 ⇒ p5wrapper/C2 零窗臂在非 OVL 配置下 Mode B 误杀 | 该门定义 `TCP_TX_OVL` 或 wrapper 暴露 `ORPHAN_ZW_EN_5` 非 OVL 门传 0；C2 零窗臂注入 ack_obs；订正 §9-12 |
| **N3** | **高** | `fireA/fireB` 无 `!orph_busy`：单 FSM 被第二槽 fire 覆盖 ⇒ 第一槽半回收（state=0 + CAM 残留 + winq 不还 + 无 orph_down + st_done 阻止重试） | fire 加 `!orph_busy`；U6 加"双槽同时达限"臂 |
| **N4** | **高** | CAM 清 issue 缺 `state_done`；C3 ③ 用 `st_pend`（gnt 沿已清）⇒ F9 顺序可回归/断言空判 | `orph_state_done` 寄存器进 issue；C3 改判它 |
| **N5** | 高 | `to_push ← !orph_down` 与 `orph_down ← !to_push` 互为条件 ⇒ 若 `orph_down` 非寄存器则组合环 | 钉死 `orph_down` 为寄存器 |
| **N6** | 高（测试可执行性） | U1"4096 轮"、U4"1000 轮(<LIM)"、U12"每 5 s" 与 TB 小值量纲冲突 ⇒ 基线即红/负对照空判 | 全部按 tick 单位重写 |
| **N7** | 中 | C2 零窗臂的"无点火"在 Mode B 下只有"活零窗 + ack_obs"成立；v2 未更新 | C2 注入 ack_obs 或关闭 ZW；另设 Mode B 全链臂 |
| **N8** | 中 | §3.6 use-point 把 `stat_ev_drop` 写成 `:1376`（实为 `ev_ovf`；stat_ev_drop 在 `:974`）；`ev_ovf` 未列入"保持原始" | 两处都改 |
| **N9** | 低 | B5b 未进 §6.3 编号臂序；§7.4 汇总漏 B5；2×LIM 时长未在 §6.3 统一 | 补臂序与时长 |
| **N10** | 低 | wrapper 未暴露 `ORPHAN_ZW_EN_5` | 加参数或非 OVL 门定义 OVL |
| **N11** | 低 | U10' 的"改前冻结锚"未点名（现有 `app_ctrl_base.v` 早于 HEAD） | 快照当前 app_ctrl 为锚 |
| **N12** | 低 | p5wrapper "重基线"削弱回归门 | wrapper 传 `ORPHAN_EN=0` 保旧基线 |
| N13 | 低 | F6-a 界未提 winq 归还 | 补 C18 一句 |
| N14 | 低 | §3.3 的 `app_ctrl.v:1345-1347` 行号漂 1（现读 1346-1348） | 订正 |
| N15 | 低 | U2 "每 12207 visits" 无定义 | 改为 tick 数 |

## 10. 逐 F 条闭项裁定（汇总）

| F | 状态 | 说明 |
|---|---|---|
| F1 | **闭项属实** | 算术/比值/全文残句/时长全核 |
| F2 | **部分闭** | 门机制正确；作用域未钉，与 U10' 冲突 |
| F3 | **主体闭** | abort_comb + wcnt 正确；clr issue 缺 state_done（见 F9） |
| F4 | **闭项属实** | 地址/自动推/B7/75 字档全核；读侧清单建议补三件 |
| F5 | **闭项属实** | 自持删除 + retx 支价值改写与源码一致 |
| F6-b | **未闭（阻断）** | 阈值 vs persist 60 s（N1）；ack_obs 非 OVL 恒 0（N2）；C2 未更新（N7） |
| F6-a | **登记属实（未闭）** | 界站得住；补 winq 归还；措辞到位 |
| F7 | **闭项属实** | Q3 可观测路径修正 |
| F8 | **闭项属实（附行号错）** | 三处已改；stat_ev_drop/ev_ovf 行号与 use point 需订正 |
| F9 | **部分闭（未闭）** | 中间态安全；缺 state_done 项与 C3 断言修正 |
| F10 | **部分闭** | M1/M2/M4'/C3/C1 已写；U1/U4/U12 量纲、U6 后窗、C2 零窗未修 |
| F11 | **闭项属实** | 臂序/盆见证/重烧纪律；B5/B5b 臂序小遗漏 |
| F12 | **闭项属实** | p5wrapper_src.f 含三文件；真盲区=板宏配置 |
| F13 | **部分闭** | U10'/作用域/p5wrapper 重基线需再定 |
| F14 | **闭项属实** | W75 第二变量已写明 |
| F15 | **闭项属实** | 32/32/32 分布 |
| F16 | **闭项属实** | wcnt 补入 busy |
| F17 | **闭项属实** | 名义时基/scan_now 说明 |
| F18 | **闭项属实** | M6→C3 / M8→C1 / U2 只查脉冲 |

## 11. 局限登记

1. 只读；未跑 xsim/综合/板级。F2/F3 的逐拍结论是源码时序推演，建议实施前用单元门或波形复核一次。
2. Mode B 的 persist 60 s 封顶推自 `ps_reload`/`PS_MAX`（`tcp_tx_frame.v:299-301,407-419`）与 1.6384 µs/visit；未用板级探询间隔独立复测（B5b 才会给）。
3. `ack_obs` 的 OVL/默认支结论是 `tcp_rx.v:617-626` 现读；非 OVL 支是常量 0，理应无需仿真。
4. 未复核 v2 的"对账说明"中"F1–F8、F10–F18 红队结论全部接受"的逐条；本复评按源码独立判，发现 F2/F3/F6-b/F9/F10/F13 的闭项不完整。
5. 未对 `tb_p5_wrapper` 的实际宏配置做 xvlog；`p5wrapper_src.f` 头注释明写不含 `TCP_TX_OVL`，按此判。
6. 本审不裁 PASS/FAIL；"必须修"清单只表示实施/构建前应闭合的设计/门项。
