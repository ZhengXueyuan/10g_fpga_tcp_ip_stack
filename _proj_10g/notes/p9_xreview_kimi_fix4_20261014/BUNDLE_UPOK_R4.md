# 换流门 DESIGN v2r3 + 实施版 3a21614 对抗复审·第四轮（kimi-tl 组）

> 日期 2026-10-15 · 角色 = 对抗复审第四轮（找茬方；「TL 裁决参考」两节按派单给出结构化建议供 TL 裁定，其余不下 PASS/FAIL）
> 复审对象 = `DESIGN_v2r3.md`（树 `e0c94a6`）+ 其实施版 `3a21614`（app_pattern.v 冻结版 sha 61650b28…，E1–E11+E13；门 `sim/p9_swc_gate`；wrapper `.TX_SWCLOSE(1'b1)` @`:1221`、BID `:4329`=0x26 未 bump=0x27 在等裁决）
> 环境纪律：全程 `git show <commit>:<路径>`，⛔ 不碰工作树、⛔ 不跑仿真/构建。
> 关键复算：`git show 3a21614:rtl/app_pattern.v`（E13@:994 / E6@:823 / close_send@:510 / m_tlast@:701）、`git show 3a21614:rtl/tcp_tx_frame.v`（:1814 start_data / :1881 s_axis_tready / :2016 plen_n / :2420-2435 S_IDLE 帧首支 / :2494 S_PAY 零长支）、`git show e0c94a6:rtl/app_pattern.v`（close_send@:492 对照）。

---

## 结论摘要

1. **裁决B 的机制链我逐环独立现读，全部坐实**：frm_wait 收尾字 (keep=0,tlast=1) 在帧器 **S_IDLE 被当数据帧首字收**（接受门 `:1881`/启动门 `:1814` 均无 keep/tlast 边带条件）→ `plen_n = (start_data?0:plen)+pop8(keep) = 0`（`:2016`）→ `plen_r=0, tcp_len=20, total_len=40` → S_WAIT/S_HDR/**S_PAY 零长分支**（`:2494` 显式存在："纯 ACK 段 / 零长数据" 6 字节 w6+tlast）→ **54 B（14+20+20）空 PSH+ACK 数据帧**，snd_nxt 推进 0、不入 FIFO/ring。HEAD 同款成立（close_send 公式 `e0c94a6:492` vs `3a21614:510` 逐字相同 ⇒ ev_down-in-frm_wait 在 HEAD 就走这条路，**"非全新机制、只是新可达"主张成立**）。**建议选 (c)**（SWC 门控"frm_wait 不发收尾字"，一行）——评估表见 TL 节。
2. **裁决A（post-close 闲置翼）建议 = 采，改形 `!(SWC_OK && (closing || !active))`**（`sw_apply` 项被 `!active` 吸收，守卫更短且严格支配现版；误伤为零——`frm_wait∧!active` 恒等于 post-close idle，该态下 :922 无合法职能；默认关折叠）。一句依据：在本来就必改的同一行上加一个零误伤析取项，补全"opener 只属存活会话"不变量并消掉 ev_up 丢失（ev_full）时的帧器悬挂放大器。
3. **closing 守卫完备性终审：通过**。穷举 closing 全部置位/清点位 ⇒ 不存在"持有者提前清 0 而 closing 仍 1"的第三形态（closing 与收尾在飞严格同生共死）；主形态/交接/停滞/plain-closeout 四形态全覆盖；唯一未覆盖面 = post-close 翼（= 裁决A 对象，已登记）。
4. **E13 实施-文档一致性：逐字一致**（`:994` = `!(SWC_OK && (closing || sw_apply))`，RTL 注释还如实内嵌了 R3-1 交接反例的出处）。**errata E-upok-1..4 我逐条独立核，4/4 成立**（1、2 是真错误且修得对；3 是保护 M5 锚点的良性排版偏离、语义未动；4 拆批属实）。
5. 本轮新发现 2 条（R4-3 中低 / R4-4 低，都指向"该走裁决 (c)"）；此前两轮的 R4-1/R4-2 维持。

---

## TL 裁决参考

### 裁决A：post-close 闲置翼 `|| !active` 硬化 —— 建议：**采，改形 `!(SWC_OK && (closing || !active))`**

**机制**（独立复算，与 v2r3 §5-1 一致）：普通 `ev_down` → W3 收尾 → `active=0` 且 **`frm_wait` 残留 1**（W3 不清它）→ 该槽重建时 TCB ESTAB 先于 `ev_up` 落地（`app_tx_ready` 为 256-tick 轮扫快照 ⇒ 前窗实际量级 **0..256+ 拍**，v2r3 写"2-3 拍"偏小但不影响结论）→ 前窗内 `frm_wait∧tx_ok∧closing=0∧sw_apply=0` ⇒ closing 版守卫放行 ⇒ `:922` 抢发旧会话下一帧的 opener（`op_beat` 不判 active）⇒ 流浪 0 载荷 opener 以 act_id 打开帧；随后 `ev_up` 到、idle 立即应用、换流块全量覆盖 ⇒ **线上净效果 = 新连接流头多一个空 opener beat（对端不可见）**，但违反"opener 只属存活会话"时序不变量。

**危害**：同槽面 = 不变量卫生 + **ev_up 上游丢失（`ev_full`）时的帧器悬挂放大**（无翼时丢失=静默 idle 无害；有翼时孤儿 plen=0 帧钉死 S_RECV，head-of-line——v2r3 未登记，我补）；跨槽面 = 不可达（idle 态任意 pending 当拍 `sw_apply` 封死同拍，前窗内无 pending 可交错）。

**`|| !active` 精确语义**：封死 `active=0` 的一切 `:922`。误伤 = **零**：`frm_wait∧!active` 恒等于 post-close idle（证：收帧拍 session-end 支 `:839` 与 frm_wait 置位支 `:860` 互斥且 `asm_go` 含 `!frm_wait` ⇒ 正常会话结束态 frm_wait=0；W3 不清 ⇒ 唯一 `frm_wait∧!active` = 收尾后 idle），该态下 `:922` 无任何合法职能（旧会话已拆、新会话由 `sw_apply` 起帧）。**简化洞察**：`closing=1 ⟹ active=1`（两处置位都要求 active=1）且 `sw_apply ⟹ idle_now` ⇒ `(closing || sw_apply || !active) ≡ (closing || !active)`——采纳硬化后 `sw_apply` 项被吸收，守卫更短且**严格支配**现版。默认关：`SWC_OK=0` 门恒真 ⇒ 逐位折叠、legacy（SWC=0 面）翼照旧登记。

### 裁决B：54 B 空数据帧（§5-7）—— 建议：**(c) SWC 门控"frm_wait 不发收尾字"**

**机制链逐环验证（全部坐实，行号 = 3a21614）**：

| 环 | 主张 | 验证 |
|---|---|---|
| 1 | SWC 在 frm_wait 的事件 → W3 close_send 发 (keep=0,tlast=1) 字 | ✓ `close_send@:510`（与基线 :492 逐字同式）+ `m_tlast@:701`（close_send→1） |
| 2 | S_IDLE 接受门/启动门无边带条件 ⇒ 当数据帧首字收 | ✓ `s_axis_tready@:1881` / `start_data@:1814`：合取项含 wnd_open/!tx_blk_sid/仲裁负项，**无 keep/tlast 侧带**（keep!=0 只门 wr/tap，不门帧首接收） |
| 3 | f_plen=0 ⇒ 54B 空数据帧 | ✓ `plen_n@:2016 = (start_data?0:plen)+pop8(keep) = 0` ⇒ `plen_r=0/tcp_len=20/total_len=40`（`:2427-2429`）→ S_PAY **零长显式分支** `:2494`（6B w6+tlast→S_DONE，**不挂起**）⇒ 14+20+20=**54 B**（FCS 另 +4）；snd_nxt 推进 0（`upd_val=seq_r+plen_r`）、不入 FIFO/ring |
| 4 | 精确条件 = 接受拍 `wnd_open ∧ !tx_blk_sid(ESTAB)` + 仲裁负项 | ✓ 同上；**补充**：接受可被延迟（帧器还在发旧帧尾 / !wnd_open 时收尾字在呈交口等 m_tready——W3 的 `if(m_tready)` 让它持久呈现直到被收） |
| 5 | HEAD 同款（非全新机制） | ✓ `e0c94a6:492` vs `3a21614:510` 逐字相同 ⇒ HEAD 的 ev_down-in-frm_wait 就发同样的字、走同样的 S_IDLE 空帧路 |

**三选项评估**：

| 选项 | 机制改动量 | 风险面 | 与既有门/不变量交互 | 评 |
|---|---|---|---|---|
| (a) 接受并登记 | 0 | 每次 frm_wait 收尾多一个 54B 空帧（占帧器 ~15-20 拍、stat_frames/id_r +1——R4-4）；**接受延迟两态**：!wnd_open 时收尾停滞（应用被窗口拖）；极端活锁尾（R4-3：交接形态下旧槽在接受拍前死亡且不复用 ⇒ close word 永不被收 ⇒ W3 不完成 ⇒ 换流永不应用） | 无 | 容忍但邋遢；把已完全理解的线上行为留下 |
| (b) frm_wait 并入"无在飞帧"立即应用面 | 中（`sw_apply`/idle 语义 + **I1 改写**（"应用拍 asm_go=0"代替"active=0"）+ u_swc5 前提重构重跑） | frm_wait 立即应用在 asm_go=0 下确干净（R1 已证），但动了状态机核心语义与 I1 论证链 | u_swc5 激励前提消失需重设计；E13 closing 窗对 frm_wait 面消失（守卫仍须保 mid-frame 面） | 架构更漂亮，但 0x27 构建在等，不值这轮做 |
| **(c) frm_wait 不发收尾字（SWC 门控）** | **一行**：`close_send` 加 `&& !(SWC_OK && frm_wait)` | **零**（frm_wait ⇒ 帧已随末字 tlast 闭合、帧器必不在 S_RECV 等 tlast——收尾字纯冗余；W3 落 else 支做 idle 向清理，其动作在该态恰全对） | 默认关折叠（锚安全）；**额外收益**：收尾变 1 拍且不再等 m_tready/wnd_open ⇒ R4-3 两态（窗口拖尾/活锁尾）一并消失；u_swc5 的 P-C 判据不受影响（判的是 opener 不早于应用拍）；F 臂"nclw=1 收尾字见证"需按臂改期望（frm_wait 臂 1→0，mid-frame 臂仍 1）随 A 裁定一起重跑门 | **推荐** |

**给 TL 的裁定句**：选 **(c)**（一行、SWC 门控、零风险面、还顺带消掉 R4-3 的窗口拖尾与活锁尾）；(b) 留作下一轮简化刀；(a) 不推荐。若 A 同采，两行小改一起进门重跑后构建 0x27。

---

## closing 守卫完备性终审（任务 1：第三形态/第四形态穷举）

**方法**：穷举 `closing` 全部置位/清点位 ⇒ `closing=1 ⟹ active=1`（两置位点都要求 active=1）；清零只在 W3 三支（与 active→0 同拍）/换流块（应用拍、closing 本已 0）⇒ **closing 与"收尾在飞"严格同生共死**，"closing 提前清 0 的序列"不存在。

危险 `:922` 拍九形态表（前八形态守卫全覆盖，第九为合法放行）：

| # | 形态 | closing | sw_apply | 守卫 | 结论 |
|---|---|---|---|---|---|
| 1 | N-1 主形态（sw_pend 全程持有，收尾完成拍） | 1（拍内） | 0 | 封 | ✓ |
| 2 | **R3-1 交接形态**（停滞期 ev_other_act，持有者换成 up_pend_r） | 1（拍内） | 0 | 封 | ✓ closing 版关键增量 |
| 3 | 停滞形态（m_tready=0 拖长收尾） | 1 | 0 | 封 | ✓ |
| 4 | plain ev_down closeout（无换流） | 1 | 0 | 封 | ✓（收尾中启动旧会话下一帧永不合法） |
| 5 | 应用拍 | 0 | 1 | 封 | ✓ |
| 6 | 多次交接/同槽刷新于停滞期 | 1 | 0 | 封 | ✓ 与持有者无关 |
| 7 | 撤销交错（`:789-790` 只触 up_pend_r 且 `!ev_up`） | — | — | 无交互 | ✓ |
| 8 | **post-close 闲置翼**（idle∧frm_wait 残留∧tx_ok 前窗） | 0 | 0 | **不封** | = 裁决A 对象（已登记，危害见 TL 节） |
| 9 | 正常帧间 frm_wait∧tx_ok（存活会话） | 0 | 0 | 放行 | ✓ 零误杀 |

**第三形态检查结论：不存在**"持有者提前清 0 而 closing 仍 1"的第三形态；主动找到的第四形态 = 形态 8（post-close 翼）——已被对方如实登记，我的独立复算与其机制/危害/跨槽不可达判定一致。

---

## E13 实施-文档一致性（任务 1 附项）

`3a21614:rtl/app_pattern.v:994` 逐字 = `if (frm_wait && tx_ok && !(SWC_OK && (closing || sw_apply))) begin` == v2r3 附录 A 终稿 == 本组 R3 建议的 closing 版 ✓。RTL 注释（:985-993）如实内嵌危险窗推理与 R3-1 交接反例出处 ✓。E6（:823-845）SWC 面与 v2r3 E6 文本逐字一致、else 面 A3 五行逐字保留（含 M5 锚点保护注释）、撤销原行恢复 ✓。E7 并列新行 ✓。wrapper `.TX_SWCLOSE(1'b1)` @:1221 ✓、BID :4329=0x26（0x27 bump 在等裁决，符合"构建前落"的时序）✓。

## errata E-upok-1..4 逐条核（任务 3）

| # | 内容 | 我的独立核 | 判定 |
|---|---|---|---|
| 1 | §4.1 P-B 的 `8'h9E` 应为 `8'h7F` | `gen_byte = tx_lfsr[31:24]`（基线 :586 同式）；`SEED=64'h9E3779B97F4A7C15` ⇒ `SEED[31:24]=0x7F`，`0x9E=SEED[63:56]`（SEED>>56）⇒ 文档把值写错、括号本意（"SEED 的第 24 位偏移字节"）对；TB 模型比对也是 `[31:24]` ⇒ P-B 必须 `8'h7F` | **成立，修得对** |
| 2 | u_swc0 须打"流位置≠0"（第 2 帧装载拍） | 复算：流位置 0 处 P-3 覆盖写 `xs_next(SEED)`+stg 收 `gen_byte=SEED[31:24]=pattern[0]` ⇒ 新会话首字 = pattern[0..7] **与干净换流逐字节相同**（旧位置=新位置=0）⇒ 首帧装载拍 = 空判据 ✓；第 2 帧（位置 1460≠0）才可见 | **成立，锐利且正确** |
| 3 | E6 排版偏离（保 A3 原文 5 行防砸 M5 锚点） | 实施版 :834-841  else 面 = 原 :784-788 五行逐字（含缩进），仅加注释与包裹；语义未变；M5 门在他们 8 运行里通过 | **成立，良性** |
| 4 | E12 四计数器拆批 | 实施版 grep `stat_up_ev/stat_sw_req/stat_sw_apply/stat_up_pend` = **0 命中** ⇒ 确实未进本刀 | **成立** |

## 本轮新发现（2 条）

- **R4-3（中低，支撑裁决B (c)）**：收尾字的**接受延迟两态**——(i) 接受拍 `wnd_open=0` 时收尾停滞（`closing=1` 期间 E13 已封 `:922` 无 N-1，但换流应用被窗口拖住）；(ii) 极端**活锁尾**：交接形态下若 close word 的 tid 槽在接受拍前死亡（对端秒拆）且永不复用 ⇒ `m_tready` 恒 0 ⇒ W3 不完成 ⇒ `closing=1` 永续 ⇒ 换流永不应用。两态随 (c)（frm_wait 根本不发收尾字）一并消失。
- **R4-4（低）**：54B 空帧附带账 = 帧器被占 ~15-20 拍 + `stat_frames`/`id_r` 每帧 +1（账面轻微膨胀，板级判据不读这两字则不可见）；登记级。

## 折叠忠实性与其余核验（任务 4）

- R3-1 折叠：守卫 sw_pend→closing ✓、§1 论证① 四支重写（逐支核成立）、§1.1 反例序列逐拍与我的原始构造吻合、u_swc5 不动（正确）、可选硬化登记待裁**未擅自采纳** ✓。
- R3-2 折叠：§4 三行显式补回 ✓。
- 新登记 §5-7（=裁决B）与 post-close 翼（§5-1）：机制描述逐环现读核实（上两节），两处小补（R4-3/R4-4）均已列出。
- v2r2→v2r3 全量 diff：除声明 4 项外零语义改动 ✓；3a21614 实施版 vs 设计件编辑表（E1-E11+E13）逐项抽查一致 ✓。
- 维持前轮发现：R4-1（低，v2r2 §7-3 的 BID"实施前再核现读+核 RFC 0x26"指令在 v2r3 §5 失显式行——**时序上已被 3a21614 的事实部分覆盖**：RFC=0x26 已落在 `:4329`、本件 bump 待行，仍建议文档补行）；R4-2（低，翼前窗量级 0..256+ 拍 + ev_full 放大器——放大器已并入裁决A 节）。

## 覆盖面声明

**已现读（git 对象）**：`3a21614:rtl/app_pattern.v` 关键区（E13@:994 及注释、E6@:823-845、E7、close_send@:510、m_tlast@:701、参数表@:50、SWC 信号族 grep）；`3a21614:rtl/tcp_tx_frame.v` 串行 FSM 段（:1800-1900 门区、:2016 plen_n、:2130-2435 S_IDLE/S_RECV/S_WAIT/S_HDR 帧首支、:2490-2515 S_PAY 零长支）；`e0c94a6:rtl/app_pattern.v` close_send 对照；v2r3 全文 133 行；v2r2↔v2r3 全量 diff；`3a21614` 的 wrapper/gate 目录/文件清单 ls-tree。
**已推演（未仿真）**：裁决B 五环、裁决A 误伤/吸收两证、九形态守卫表、R4-3 接受延迟两态、errata 1/2 的数值核。
**未做**：⛔ 未跑 xsim/Vivado/构建（对方实施轮虽收口但构建在等裁决）；sim/p9_swc_gate 的 TB 内部（tb_p9_swc.v 的 P-B 常量是否已用 7F——errata 说文档错、门已过，推定 TB 侧已正确，未逐字核）；`hls/` 侧五代同款未闭合；若 TL 两裁决与我的建议相反，本件的部分结论（尤其 R4-3 随 (c) 消失这一条）需按最终裁定复述。
