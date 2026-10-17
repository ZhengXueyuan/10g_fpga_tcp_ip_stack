# FINDINGS_V3 — 红队闭项抽查：孤儿修复设计件 v3（`3349b787`）

> 被审件 = `p9_orphan_fix_design_20261017/README_FOR_TL.md`（736 行）；方法 = 只读源码/留存读数；行号现读；未碰板/对端。⛔ 不裁 PASS/FAIL。
> 本件 = TL 代落（红队全文回报，平台拒写）。

## TL 处置块（2026-10-17 12:0x 现读施工）

- **全 10 项（含 X1–X10）采纳**。**v3 判定：需再修（v4）后才能进入实施**——但性质已收敛：**机制层全部闭合**，剩下的 7 项必修**全部是"附录伪代码/测试配置/措辞"级**。
- **v4 必修 7 条**（红队 §10）：① N3/N5 附录 FSM 缺项（`orph_wait_cam<=0` / `orph_notify_pend` 置清 / `orph_ready=orph_notify_pend` / **wait_cam 清与 notify_pend 置同沿**）② N2（fireB/accrueB/计数全包 `ORPHAN_ZW_EN` + 补"OVL 内禁用 ack_obs ⇒ 默认失效"自评）③ N6（单元 TB 显式 `ORPHAN_EN=1`/`ZW_EN=1` + 清零块移到计数块之后或 clr 优先）④ N1（B5 ≥135 s + "2 次丢失覆盖 0.39 s 对延迟敏感 / ≥3 次必误杀"措辞）⑤ X6（C2a 用 `ORPHAN_EN_5=1 + ZW_EN_5=0`）⑥ X3（嵌套折叠四组合 + ZW_EN=0 时 ZW 计数语义）⑦ X7（C2b 真 ACK 帧注入）。
- **流程调整**：v4 回来后由 **TL 亲核**这 7 条（均为"某行是否写出"的检查，不需第四轮红队全文审）；通过即进入实施。
- **红队认账**：N14 行号是 FINDINGS_V2 差一行（v3 的 1345–1347 属实）。
- **教训登记**：① "设计件的**附录伪代码**才是实现的权威"——红队把附录当"照此写"审，抓出永挂/多拍；以后设计件的附录必须与正文同等自洽。② 测试配置的**使能参数**（ORPHAN_EN/ZW_EN）漏写 ⇒ 活动单元门全体空判——**"默认关"的零回归设计会反过来吃掉测试覆盖**，必须显式在测试台账里写"活动臂传 1"。

---

## 0. ≤25 行摘要（红队原文）

1. **N1 ZW 阈值：部分闭。** 2^20×1.6384 µs = **1.7179869 s**（文中 1.7180 ✓）；×105 = **180.3886 s** ✓；×255 = **438.0867 s** ✓；1 次丢失 120 s ⇒ 余量 60.39 s ✓。**但"连续 2 次丢失=180 s，余量 0.39 s ⇒ 不覆盖"的符号错**：180 < 180.39 ⇒ **2 次丢失实际被覆盖 0.39 s**（该余量 < ACK 延迟/抖动预算，按"不覆盖"处理可以，但理由要改写成"余量 0.39 s 不足"，不是"180>180.39"）。
2. **N1 臂设计：B5 的 ≥120 s 不够**。persist 累计探询时刻 = 0.02/5.02/15.02/35.02/**75.02/135.02/195.02 s**；60 s 档的第一对在 **75/135 s**，120 s 窗只含 75 s（上一间隔 40 s）⇒ **测不到 60 s 档**。B5 应 ≥135 s；B5c ≥200 s（覆盖 135/195）可；B5b ≥361 s 可。死零窗占槽 180 s = 已登记的设计选择 ✓；"活零窗必回 ACK"是【推断】，需加"socket 未 close"限定（app close → RST 非 ACK；此时回收是**对的**，不是误杀）。
3. **N2 ZW_EN：当前源闭，但两处未闭**：(a) v3 正文**没有**"将来有人定义 OVL 却禁用 ack_obs 则默认失效"这条自评（grep `将来/失效` N2 段 0 命中）—— 派单说其已登记，**与文件不符**；(b) **fireB/附录的 accrue/count 没有 `ORPHAN_ZW_EN`** —— 若照附录实现，p5wrapper 的 `ORPHAN_ZW_EN_5=0` **关不掉 Mode B**，N2 的误杀门复现。结构性防呆（默认由同一宏推）本身成立。
4. **N3 orph_busy：部分闭。** 五项覆盖命名状态；**但附录 FSM 草图没有清 `orph_wait_cam`、没有置/清 `orph_notify_pend`、`orph_ready` 未定义** ⇒ 照"实现直接照此写"会 **busy=1 永挂**（无通知）或在 wait_cam→notify_pend 交接处出现 **1 拍 busy=0**（第二槽乘虚）。交接必须**同沿**（清 wait_cam 的同时置 notify_pend），v3 未钉。U6b 可判、串行延迟已登记。
5. **N4 orph_state_done：机制闭。** 置位 `fc_gnt&&fc_sel_r==5&&fc_id_r==orph_slot` 时序正确；`!orph_busy` 保证等待期 `orph_slot` 不被新 fire 改写；fire/abort 清 0；C3③ 改用它 ✓。**依附 N3 的附录缺项**（cam_req 清后到 notify_pend 置之间的 busy 连续未写）。
6. **N5 orph_down_r：部分闭。** 寄存器断环 ✓；`to_push`/`ev_down_i` 用寄存器项 ✓。**但附录的 `orph_down_r <= orph_ready && …` 未定义 `orph_ready`、未写 notify_pend 清位** ⇒ 若 `orph_ready` 是电平，"1 拍脉冲"不成立（可多拍）；必须钉 `orph_ready = orph_notify_pend` 且在同一沿清它。
7. **N6 量纲：部分闭。** tick 单位已改写 ✓；U6c 已加 ✓。**但单元 TB 的 `ORPHAN_EN=1`（U1–U9/U11/U12）与 `ORPHAN_ZW_EN=1`（U11/U12）未写** —— app_ctrl 默认 `ORPHAN_EN=0`（§3.3 "（0）"）⇒ 照 §6.1 的量纲表，**所有活动单元门都是关的/空判**。另：**附录的"清零优先"未实现**——`una_adv`/`ack_obs` 清零块在计数块**之前**，NBA 后写赢 ⇒ 同拍"清零+计数"时**计数赢**；U1/U12 的"每 tick 进度/每 tick ack"正好每 tick 撞车 ⇒ 会点火（门红，但设计件"照此写"是错的）。
8. **F2 作用域：闭。** `fc_upd_wr = fc_v && (!ORPHAN_EN || ...)` ⇒ ORPHAN_EN=0 旁路，U10' 逐位成立；既有 FIN-timeout 修复只在孤儿构建（板构建）生效并已登记。**但 C1/C2a/C3/C4 的分组配置有误**：p5wrapper 显式 `ORPHAN_EN_5=0/ZW_EN_5=0` 只保旧基线；**C2a 需要 `ORPHAN_EN_5=1` + `ZW_EN_5=0`**（Mode A 开、B 关），否则 C2a 的"Mode A 无点火"是**空判**（全块关）。C1/C3/C4 也必须用孤儿臂覆盖；v3 的"另用一套覆盖"未逐条点名。
9. **新洞**：C2b 的"唯一真路径门"未写刺激方式（force `ack_obs` vs 注入真 ACK 帧；后者才是真路径）；`ORPHAN_EN`/`ORPHAN_ZW_EN` 的**嵌套折叠**（外 EN、内 ZW）未写；ZW_EN=0 时 `orph_zw_cnt` 是否仍计数未写；B5 120 s（见 2）；2 次丢失符号（见 1）；N2 自评缺失（见 3）。
10. **N14 对账：v3 对、我 v2 错。** 现读 `board/wrapper_p4.v` 的 `app_reg_*` 三条 assign 确在 **1345–1347**（1344 注释、1348 空行）；我 FINDINGS_V2 记 1346–1348 是**差一行**，v3 的订正属实。
11. **结论（读数层，不裁 PASS/FAIL）**：**需再修后才能进入实施**。必修：**N1（B5≥135 s + 2 次丢失措辞）、N2（fireB/附录加 ZW_EN 门 + 补自评）、N3/N5（附录 FSM 的 wait_cam→notify_pend 同沿交接 + orph_ready/1 拍脉冲）、N6（单元 TB 的 ORPHAN_EN/ZW_EN 使能 + 清零优先的代码顺序）、C2a 配置**。其余（C2b 刺激、嵌套折叠、B5b/B5c 时长）为实施/门级补充。

---

## 1. N1（ZW 阈值）逐项核

### 1.1 算术：**基本属实**
- `ORPHAN_ZW_TICK_BITS=20`：2^20 = 1,048,576 轮；×1.6384 µs = **1.7179869184 s**（v3 写 1.7180 s ✓）。
- `ORPHAN_ZW_LIM=105`：×105 = **180.3886 s**（v3 180.39 s ✓）。
- 8 位饱和：×255 = **438.0867 s**（v3 438.1 s ✓）。
- 1 次丢失：2×60 s = 120 s；余量 60.39 s ✓。
- **2 次丢失**：3×60 s = 180 s；180.3886 − 180 = **+0.3886 s** ⇒ **数学上覆盖**，v3 写"余量 0.39 s ⇒ 不覆盖"是**符号错/表述矛盾**。若按"ACK 延迟/抖动可能吃掉 0.39 s"（Linux delayed ACK ≤40 ms，但内核卡顿/调度可更长）保守处理，可以写"不覆盖"，理由必须改成"余量 0.39 s 不足"，而不是"180 > 180.39"。
- 3 次丢失：240 s ⇒ 明确不覆盖（v3 未写这一档；§9-6b 只写"连续 2 次"）。建议残余写：**≤2 次丢失可容忍（第 2 次余量 0.39 s，对 ACK 延迟敏感）；≥3 次丢失必误杀**。

### 1.2 B5/B5c/B5b 臂设计：**B5 时长不够（未闭）**
- persist 累计探询时刻（按 `ps_reload` 20 ms→5→10→20→40→60→60…，`tcp_tx_frame.v:407-419`）：**0.02 / 5.02 / 15.02 / 35.02 / 75.02 / 135.02 / 195.02 s**。
- **60 s 档的第一对 = 75.02 s 与 135.02 s**；B5 的 120 s 窗只含 75.02 s，前一间隔是 35→75 = **40 s** ⇒ **B5 根本没测到 60 s 档**。v3 的"≥2×60 s = ≥120 s、跨至少 2 个 persist 60 s 档"**不成立**。
- **修正**：B5 ≥ **135 s**（含 75/135 两探询，覆盖一个完整 60 s 间隔）；若要覆盖两个 60 s 间隔 ⇒ ≥195 s。B5c ≥200 s 已覆盖 135/195 与一次丢失 ✓；B5b ≥361 s ✓（死对端无 ACK，180.39 s 点火；约 6 个 60 s 档探询）。
- B5/B5c 的"记录探询/ACK 计数"见证是好设计；B5c 的"人为丢 1 个 60 s 档探询或其 ACK"可判（对端 iptables 精确丢一帧）；"板侧只记录不注入"在板上不可实现（需改 RTL），只能作 TB 臂，v3 的两种写法要分开。

### 1.3 新阈值副作用 / "活零窗必发 ACK"论证
- 死零窗对端占槽 **180 s**（vs 61.85 s）：v3 已作为 B5b 的直接代价登记 ✓（设计选择）；附加影响 = 该槽的 winq 也占用到 180 s（同槽 ADD 的 C18 归还，`app_ctrl.v:987-991`）——v3 的 F6-a 已写 winq 归还，但**零窗死对端的 180 s winq 占用未量化**（小项）。
- **"活零窗对端会回 persist ACK"的论证漏洞**：
  - **socket 未 close** 的活对端：内核会 ACK 重复段/窗口探询（RFC 1122 §4.2.2.17、Linux 行为）【推断，v3 已标】⇒ 成立。
  - **app 已 close**（socket 关闭）：内核回 **RST**，不是 ACK ⇒ `ack_obs` 不脉冲（RST 帧 flags 不满足 `ackok/dup/ack_adv`）；Mode B 在 180.39 s 回收。**这不是误杀**（session 确实死了），但 v3 的"活零窗对端"措辞应限定为"**socket 未 close 的活对端**"；app-close 的回收由 Mode B 或 HLS 的 RST 兜底（`layer_tcp.cpp:631-641`）完成，两者都正确。
  - **app 冻结但 socket 开**：内核照常 ACK ⇒ 不误杀 ✓。
  - **对端内核卡死 / 中间盒丢探询**：无 ACK ⇒ 误杀，v3 的"180.39 s 内一个 ACK 都不发（即使活着）"与 §8-6 已登记 ✓；但应把"连续 2 次丢失"与"内核卡死/中间盒"分开列。
- **结论 N1**：**部分闭**。阈值选择/单次丢失算术/占槽代价登记/B5b-B5c 可判性成立；**B5 120 s 测不到 60 s 档（必修）**；**2 次丢失的符号/措辞（必修）**；**活对端 socket-open 限定（建议）**。

## 2. N2（ZW_EN 默认）逐项核

- **结构性防呆（当前源）成立**：wrapper 的 `ORPHAN_ZW_EN_5` 默认由 `ifdef TCP_TX_OVL` 推出（OVL=1 / 非 OVL=0）；`tcp_rx.v:617-626` 的 ack_obs 也由同一宏分叉（OVL 置位 / else 恒 0）。⇒ 非 OVL 门忘传 ⇒ 0 ⇒ Mode B 关，不会误杀；OVL 门忘传 ⇒ 1 ⇒ ack_obs 可用，正确。p5wrapper 显式 0 ✓；板构建 OVL=1 默认 1 ✓；C2b 定义 OVL 显式 1 ✓。
- ⭐ **自评缺失**：派单说 v3 有"将来有人定义 OVL 却禁用 ack_obs 置位则默认失效"的登记 —— **README 中未找到**（N2 段 grep 0 命中；只有 §9-12/§8-19 的"仅 OVL 支"订正）。这条**未登记**：结构性防呆依赖"TCP_TX_OVL ⇒ ack_obs 置位"这一不变量；若将来在 OVL 支内加一个禁用 ack_obs 的开关/参数，默认推导会静默给出 1 ⇒ Mode B 打开而 ack_obs 恒 0 ⇒ 误杀。**必须补登记**（并建议在 wrapper 里加一条 `ORPHAN_ZW_EN_5 && ack_obs_available` 的结构断言，或至少在 `tcp_rx` 端口注释里写死该不变量）。
- ⭐ **更实质的未闭**：v3 的 **fireB / 附录 accrueB/count 都没有 `ORPHAN_ZW_EN` 项**（§3.2 行 273-280、附录行 703-721）。app_ctrl 的 `ORPHAN_ZW_EN` 默认是 0/1 未写清（§3.3 "（0/1）"）；若照附录实现，`ORPHAN_ZW_EN=0` **不会关掉 Mode B**（accrueB/fireB 仍工作）⇒ **p5wrapper 的 `ORPHAN_ZW_EN_5=0` 失效 ⇒ C2a 的零窗臂重新变成 Mode B 会点的场景**（N2 误杀回归）。必须：
  - 把 Mode B 的 `zw_accrue`/`orph_zw_cnt` 计数/`fireB` **全部包在 `if (ORPHAN_ZW_EN)`**（常数折叠），或至少在火条件里 `&& ORPHAN_ZW_EN`；
  - 明确 `ORPHAN_EN` 外层、`ORPHAN_ZW_EN` 内层的**嵌套折叠**（四组合：00/01/10/11 的语义）。
- **结论 N2**：**当前源的结构性防呆闭；但（a）自评未登记（与派单不符），（b）ZW_EN 门未进 fireB/附录（会复现 N2 误杀）⇒ 部分闭/必修**。

## 3. N3（orph_busy）逐项核

### 3.1 五项覆盖
`orph_busy = orph_state_req || orph_cam_req || orph_wait_cam || orph_notify_pend || orph_down_r`。
- fire 沿：state_req=1、cam_req=1 ⇒ busy=1 ✓。
- fc gnt 沿：state_req=0、state_done=1、cam_req=1 ⇒ busy=1 ✓。
- CAM 清沿：cam_req=0、wait_cam=1 ⇒ busy=1 ✓。
- wait_cam 清 + notify_pend 置（**必须同沿**）：之后 notify_pend=1 ⇒ busy=1 ✓（**同沿条件 v3 未写**）。
- down_r 脉冲：down_r=1 ⇒ busy=1 ✓；脉冲后全 0 ⇒ 空闲 ✓。
- abort：清全部 ⇒ busy=0，FSM 已 abort ✓（第二槽可进）。
- **未覆盖的路径**：如果 wait_cam 清与 notify_pend 置**不同沿**（先清 wait_cam 一拍、下一拍才置 notify_pend），中间有 **1 拍 busy=0** ⇒ 第二槽的 fire 可乘虚改写 `orph_slot` ⇒ 第一槽半回收（N3 原病复发）。v3 的正文说"等 clr 回落 ≥1 拍后清 wait_cam"与"两者都已落地 ⇒ 置 notify_pend"两句话**没有钉同沿**；附录更**没有**清 wait_cam/置 notify_pend 的赋值。**必修**：`if (cam_clr_done) begin orph_wait_cam<=0; orph_notify_pend<=1; end`（同沿），并在 U6b 里加"第一槽停在 wait_cam→notify_pend 交接拍时第二槽达限"的臂（现有 U6b 是"相邻扫描拍都达 LIM"，未必恰好覆盖交接拍）。
- **abort 后 fire 前**：abort 清全部 ⇒ busy=0；FSM 已 abort（无 pending），第二槽/同槽新 fire 合法 ✓。**无洞**。
- **`orph_wait_cam` 的清位缺失（附录）**：附录行 723-733 只写 `orph_wait_cam<=1` 与 `else if (orph_wait_cam) orphan_cam_clr<=0;`，**没有 `orph_wait_cam<=0`**；照抄 ⇒ wait_cam 永 1 ⇒ busy 永 1 ⇒ **FSM 永挂、无 orph_down、无 stat_orphan**。这是"实现直接照此写"的**阻断级缺项**。
- **`orph_notify_pend` 的置/清缺失（附录）**：附录完全没提；照抄 ⇒ busy 项恒 0；即便 wait_cam 被清，busy 也会在交接处落 0（第二槽乘虚）。**必修**。
- **`orph_ready` 未定义**（附录行 731）：v3 正文行 290 说"两者都已落地 ⇒ 置 notify_pend；在投递门开的那一拍 orph_down_r<=1 并清 notify_pend"，但附录的 `orph_down_r <= orph_ready && …` 没有定义 `orph_ready`；若 `orph_ready` 是 `notify_pend` 则 1 拍脉冲成立（同沿清 notify_pend），若是一个电平（state_done+cam_done）则 down_r 可能多拍。**必须写 `orph_ready = orph_notify_pend`**（并在同一沿清 notify_pend）。
- **U6b 判据可判性**：两槽各 1 次 state=0 + 1 CAM 清 + 1 o_ev_down、stat_orphan=2、删 `!orph_busy` ⇒ 第一槽半回收 ⇒ 红。**可判**（前提是上面交接同沿，否则 U6b 本身就会暴露 busy 洞——但也说明设计未闭）。串行最坏 3 槽延迟无上界：v3 §8-20/§9-13 已登记 ✓。
- **结论 N3**：**部分闭**。五项本身合理，但**附录 FSM 的 wait_cam/notify_pend/orph_ready 三处缺失 + 交接同沿未钉** ⇒ 照字面实现会挂/会漏 busy。**必修**。

## 4. N4（orph_state_done）逐项核

- 置位：`fc_gnt && fc_sel_r==5 && fc_id_r==orph_slot` ⇒ `state_req<=0; state_done<=1`。时序：`fc_gnt` 是写拍组合，`fc_sel_r/fc_id_r` 是寄存器，`orph_slot` 在 `!orph_busy` 下稳定（第二 fire 被挡）✓。写入沿 = TCB state=0 落地沿，state_done 从下一拍起为 1 ⇒ CAM 清最早下一拍，顺序正确 ✓。
- fire/abort 清 0：fire 行 725 `state_done<=0`；abort 行 732 清 state_done ✓。
- C3③ 改判 `orph_state_done`（不用 `st_pend`，后者在 fc gnt 沿已清，`app_ctrl.v:1323`）✓。
- **依赖项**：`orph_state_done` 不在 `orph_busy` 五项里 —— 这是**可以**的，因为 `orph_cam_req`（fire 时置 1，直到 CAM 清）在 state_done 之后仍保持 busy；但必须保证 **cam_req 在 notify_pend 置位之前不被清**（当前顺序：cam 清沿清 cam_req + 置 wait_cam；wait_cam 在之后清；notify_pend 在 wait_cam 清的同沿置 —— 只要同沿，busy 连续）。见 N3 的交接要求。
- **结论 N4**：**机制闭**（置位/清除/稳定性/C3 断言）；**依赖 N3 的交接同沿**，若 N3 修好则全闭。

## 5. N5（orph_down_r）逐项核

- 无环：`orph_down_r` 是寄存器；`to_push` 的 `!orph_down_r`（§3.6 use-point）与 `orph_down_r` 的 `!to_push` 都是寄存器项 ⇒ 无组合环 ✓。注意 `ev_down_i = ev_down | orph_down_r` 必须用**寄存器输出**，v3 §3.6 已写 ✓。
- **1 拍脉冲**：附录行 731 `orph_down_r <= orph_ready && !ev_up && !ev_down && !to_push && !ev1_v && !to_pushed_r;`；若 `orph_ready=notify_pend` 且在同沿清 notify_pend，则 down_r 高 1 拍 ✓；若 `orph_ready` 是电平（state_done && cam done），则 **多拍高**（每拍都满足）⇒ `o_ev_down` 多拍/stat_orphan 多计。**必须定义 `orph_ready` 且在脉冲沿清它**。v3 正文说"并清 orph_notify_pend"，但附录没有该赋值。**必修**。
- **`orph_down_r` 的清除**：fire 行 725 置 0；投递沿置 1；下一拍或沿由 `orph_ready` 清（见上）。附录未显式写 `orph_down_r<=0` 的默认/清位；若 `orph_ready` 保持，多拍。
- **`to_pushed_r`/`ev1_v`**：投递门含 `!to_pushed_r` ✓；`ev1_v` 用 ev_down_i（含寄存器 orph_down_r）✓（§3.6 use-point 已列）。
- **结论 N5**：**部分闭**。寄存器断环 ✓；**1 拍脉冲契约与 orph_ready 定义未在附录落地（必修）**。

## 6. N6（量纲）逐项核

- **tick 单位改写**：U1/U4 的进度改为 `max(1,LIM/2)` ticks；U12 的 ack_obs 每 `max(1,ZW_LIM/2)` ticks；U2 的 retx 每 `max(1,LIM/2)` ticks；U5/U5b/U6/U6b/U6c/U9 均 tick/拍单位。✅（逐条读 §6.1：一致）
- **TB 小值**：LIM=2/TICK_BITS=1 ⇒ 6.55 µs；ZW_LIM=2/ZW_TICK_BITS=1 ⇒ 6.55 µs。✅
- ⭐ **使能参数缺失（必修）**：app_ctrl 的 `ORPHAN_EN` 默认 0（§3.3 "（0）"）、`ORPHAN_ZW_EN` 默认 "0/1" 未写清。§6.1 的"TB 量纲"只列 LIM/TICK，**没有 `ORPHAN_EN=1`**（U1–U9/U11/U12）与 **`ORPHAN_ZW_EN=1`**（U11/U12）。若照 §6.1 直接例化（默认 0），**整块折叠 ⇒ 所有活动单元门都是空判**（U1 期望 0 通过、U11 期望 1 失败、U12 空转、M1–M12 全不红）。**必须**在 §6.1 写明"活动臂 app_ctrl 以 `ORPHAN_EN=1`（U11/U12 另 `ORPHAN_ZW_EN=1`）例化；U10/U10' 用 0"。
- ⭐ **清零优先的代码顺序（必修）**：附录行 690（`una_adv` 清零）/692（`ack_obs` 清零）在计数块（708-713）**之前**；同一 always 块里 NBA 后写赢 ⇒ **同拍"清零 + 计数"时计数赢**，与 §3.2 行 248 的"清零（优先于计数）"**相反**。U1/U4/U12 的"每 tick 进度/每 tick ack"恰好**每 tick 撞车** ⇒ 按附录实现，计数器每 tick +1 而不清零 ⇒ U1/U12 在 LIM 后点火（门红；但说明设计件"照此写"是错的）。**修法**：把清零放在计数块之后，或在计数条件里用 `clr_a/clr_b` 优先（`if (clr) 0; else if (tick) +1;`）。
- U6c（state-gnt→CAM 清窗口）已加 ✓；U6b 双槽已加 ✓；M11/M12/M13 已加 ✓。
- **结论 N6**：**部分闭**。单位改写 ✓；**单元门使能参数（ORPHAN_EN/ZW_EN）与清零优先的代码顺序未闭（必修）**；U6c/U6b 可判。

## 7. 新逻辑交叉扫描（v3 新引入）

| # | 新逻辑 | 发现 | 状态 |
|---|---|---|---|
| X1 | `orph_state_done` × `cam_req` × abort | 置位/清除/优先级正确；但附录 cam 清后 `wait_cam` 不清、`notify_pend` 不置 ⇒ 照抄会挂；abort 清 state_done 与 cam_req 同沿 ✓ | **部分闭** |
| X2 | `notify_pend` ↔ `orph_down_r` 握手 | 无环 ✓；1 拍脉冲依赖 `orph_ready=notify_pend` + 同沿清 notify_pend —— **未定义/未写**；可能多拍或丢脉冲；`to_pushed_r`/`ev1_v` 已覆盖 ✓ | **未闭（附录）** |
| X3 | `ORPHAN_EN=0`/`ORPHAN_ZW_EN=0` 四组合 | ORPHAN_EN 外层折叠 ✓（F2 门也在内）；**ZW_EN 未进 fireB/accrueB/计数**（见 N2）⇒ 10/01 组合语义不可预期；`ORPHAN_ZW_EN=0` 时 `orph_zw_cnt` 是否仍计数未写 | **未闭** |
| X4 | `fc_upd_wr` 门作用域 | 放进 ORPHAN_EN ✓；U10'（ORPHAN_EN=0）逐位成立 ✓；既有 FIN-timeout 修复只在孤儿构建（已登记）✓ | **闭** |
| X5 | `orph_busy` 交接 | 五项命名状态 ✓；wait_cam→notify_pend 同沿未钉（N3） | **部分闭** |
| X6 | C2a/C2b 配置 | C2a 需要 `ORPHAN_EN_5=1` + `ZW_EN_5=0`（Mode A 开/B 关）；v3 的 p5wrapper 行同时传 0/0 ⇒ C2a 的"Mode A 无点火"空判（全块关）。C1/C3/C4 需孤儿臂覆盖；v3 的"另用一套"未逐条点名 | **未闭（测试配置）** |
| X7 | C2b "唯一真路径门"刺激 | 未写 `ack_obs` 是 force 还是真 ACK 帧注入；若 force，不测 tcp_rx 的真路径，与"真路径门"自述矛盾。建议注入真纯 ACK 帧 | **部分闭（门级）** |
| X8 | 死零窗 180 s 占槽 | 已登记为 B5b 代价 ✓；winq 占用时长未量化（小项） | 已登记 |
| X9 | 2 次丢失符号 | 见 N1；180 < 180.39，v3 写"不覆盖"符号错 | **措辞/量化** |
| X10 | B5 120 s | 见 N1；测不到 75/135 s 的 60 s 档 | **未闭（臂）** |

## 8. F2 作用域专项

- v3 §3.6 行 349：`fc_upd_wr = fc_v && (!ORPHAN_EN || (!(ev_up && ev_slot==fc_id_r) && !(ev_down && ev_slot==fc_id_r)))`。
  - `ORPHAN_EN=0` ⇒ `fc_upd_wr=fc_v` ⇒ 与 HEAD 的 app_ctrl 逐位相同（除其他折叠逻辑）⇒ U10' 恢复成立 ✓。
  - `ORPHAN_EN=1` ⇒ ev_up/ev_down 同槽拍 fc 写被挡；`sel_fc=0`；事件块沿清 `fc_v/st_pend`；ADD 的 state=1 不被覆盖 ✓。
  - 既有 FIN-timeout/abort 的同族竞态**只在孤儿构建**修；ORPHAN_EN=0（p5wrapper 基线）保留旧行为 ✓（已登记）。
- **结论**：**F2 作用域闭**。唯一附注：C2a 的配置（见 X6）必须与基线臂分开，否则 C2a 空判。

## 9. 与派单不符之处（如实说）

1. **N2 的自评"将来有人定义 OVL 却禁用 ack_obs 置位则默认失效"在 v3 README 中不存在**（N2 段 grep 0 命中）；派单说其已登记 —— **与文件不符**；应补登记。
2. **N14 的行号：v3 对、我 v2 错**。现读 `board/wrapper_p4.v:1345-1347` = 三条 `assign app_reg_*`（1344 注释、1348 空行）；FINDINGS_V2 的 1346–1348 是差一行。向 v3 认账。
3. **N1 的"2 次丢失=180 s，余量 0.39 s ⇒ 不覆盖"**：180 < 180.39，**2 次实际被覆盖 0.39 s**；表述符号错（保守方向，但会误导 B5c 判读）。
4. **N1 的 B5 120 s**：persist 的 60 s 档第一对在 75/135 s，120 s 窗**测不到 60 s 档**；v3 的"≥2×60 s"不成立（应为 ≥135 s）。

## 10. 总结论（读数层，不裁 PASS/FAIL）

**v3 → 需再修（v4）后才能进实施。** 必修（按优先级）：
1. **N3/N5 附录 FSM**：补 `orph_wait_cam<=0`、`orph_notify_pend` 置/清、`orph_ready=orph_notify_pend`；**wait_cam 清与 notify_pend 置同沿**；保证 `orph_down_r` 1 拍脉冲（附录是"实现直接照此写"的权威，现文照抄会永挂/多拍）。
2. **N2**：fireB/accrueB/`orph_zw_cnt` 计数加 `ORPHAN_ZW_EN`（否则 p5wrapper 的 ZW=0 关不掉 Mode B，N2 误杀回归）；补"OVL 内禁用 ack_obs ⇒ 默认失效"自评。
3. **N6**：单元 TB 明确 `ORPHAN_EN=1`（活动臂）/`ORPHAN_ZW_EN=1`（U11/U12）；附录清零块移到计数块之后（或写 `clr` 优先），否则 U1/U12 每 tick 撞车。
4. **N1**：B5 ≥135 s（覆盖 75/135 s 的 60 s 档）；2 次丢失措辞改为"覆盖 0.39 s、对 ACK 延迟敏感 / 按不覆盖处理"，或加"≥3 次必误杀"。
5. **X6**：C2a 用 `ORPHAN_EN_5=1 + ORPHAN_ZW_EN_5=0`（Mode A 开/B 关）；C1/C3/C4 用孤儿臂覆盖；基线臂（旧 p5wrapper）才用 0/0。
6. **X3**：写明 `ORPHAN_EN` 外层、`ORPHAN_ZW_EN` 内层的嵌套折叠；`ZW_EN=0` 时 Mode B 计数器不动（或计数但无火，明确其一）。
7. **X7**：C2b 的 ack_obs 用真 ACK 帧注入（非 force），否则"真路径门"名不副实。

**其余**（N4 机制、F2 作用域、C1/C3/C4 断言、U6b/U6c、B5b/B5c 时长、死零窗占槽登记、N14 对账）**已闭或仅需文案级同步**。

**局限**：只读、未跑 xsim/综合/板；FSM 逐拍结论是源码/时序推演；persist 探询累计时刻按 `ps_reload` + 1.6384 µs/visit 算，未用板级 pcap 独立复测（B5/B5c 会给）；v3 的附录是"实现直接照此写"的权威，本评按该文本判定，若实施者改按正文散文实现则 N3/N5 的缺项可被绕过——但那就不是"照此写"了。
