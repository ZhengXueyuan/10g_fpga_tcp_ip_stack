# p9_orphan_fix_design_20261017 —— 孤儿会话/槽泄漏修复设计件

> 件名 `_proj_10g/notes/p9_orphan_fix_design_20261017/README_FOR_TL.md` · 日期 **2026-10-17** · 轮次 = **纯设计件（只读，修订版 v4）**
> 上游：`p9_c1_mech_doc_20261017/README_FOR_TL.md`（机制档案，451 行）· `p9_c1_board_20261017/README_FOR_TL.md`（C1 板级两代臂）
> 审查：`p9_review_orphan_fix_design_20261017/FINDINGS.md`（F1–F18）· `FINDINGS_V2.md`（N1–N15）· `FINDINGS_V3.md`（必修 7 条）—— TL 处置 = **全部采纳**
> ⛔ **本件只读**：未碰板/对端，未改任何 RTL/HLS/工具/构建脚本；**不含 PASS/FAIL 裁定，不含实施授权**。
> 标签口径：【已证（`文件:行`）】= 本 agent 2026-10-17 现读源码可当场复核 ·【推断】= 有依据但未直接测（附证伪法）·【未判定】·【未测】。
> ⚠️ 行号一律本 agent 2026-10-17 现读；与旧文引用不同处按本件。
> ⚠️ **树态（现读）**：HEAD 的 `board/wrapper_p4.v:2185` = `.PERSIST_EN(1'b0)`、`:4377` = `BUILD_ID_V = 32'h00000029`
> ⇒ **提交树 = 0x29 拆刀幽灵配置（persist 关）**；**板上现役 = 0x28（persist 开）**【已证】（本件现读 + CLAUDE.md 2026-10-17 块）。
> 本设计凡涉构建的都按"先还原 persist + BID bump"为**硬前置**（§7.3）。

---

## 修订版 v4（2026-10-17，按 FINDINGS_V3 必修 7 条）—— 逐条闭项表

> 被审件 = v3（736 行）；复评件 = `p9_review_orphan_fix_design_20261017/FINDINGS_V3.md`（**机制层已全闭**；必修 7 条全部是"附录伪代码 / 测试配置 / 措辞"级）。
> 本版 = **纯纸面修订**；只改这 7 条及其直接相关句（附录 B 的 FSM/清零顺序、§3.2 模式 B 折叠、§3.3/§6.3/§7.4/§9 的 B5 与两连丢措辞、§6.1 使能、§6.2 参数臂与 C2b 刺激）。**N4 机制 / N2 机制 / F2 作用域 / C1–C4 断言 / U6b–c / B5b–B5c 时长 / 死零窗占槽登记 / N14 已闭项不动。**
> ⚠️ **红队认账 N14**：现读 `board/wrapper_p4.v:1345-1347` 属实（v3 对、FINDINGS_V2 差一行）。
> ⚠️ 本版附录 B 是"实现直接照此写"的权威；正文与附录冲突处**按附录读**（FINDINGS_V3 教训①）。

| # | 严重度 | v3 残留问题 | v4 处置（闭法） | 闭项位置 |
|---|---|---|---|---|
| **V4-1（N3/N5）** | **阻断** | 附录 FSM 缺 `orph_wait_cam<=0`（照抄 ⇒ wait_cam 永 1 ⇒ busy 永 1 ⇒ FSM 永挂、无 orph_down/stat_orphan）；`orph_notify_pend` 置/清**完全没写**；`orph_ready` **未定义**；`orph_down_r` 清位/默认不全 | `if (cam_clr_done) begin orph_wait_cam<=0; orph_notify_pend<=1; end`（**同沿交接**，busy 连续无 1 拍空档）；**`orph_ready = orph_notify_pend`**；投递沿 `orph_down_r<=1` 且**同沿清 `orph_notify_pend<=0`** ⇒ `orph_down_r` 严格 1 拍脉冲；`orph_down_r` 每分支清位/默认写全（fire/abort 清 0；非投递拍默认 0）；U6b 加"**第一槽停在 wait_cam→notify_pend 交接拍时第二槽达限**"臂 | 附录 B、§3.2 步骤 3/4、§6.1 U6b |
| **V4-2（N2）** | **阻断（门/测试）** | 附录 `zw_accrue`/`orph_zw_cnt` 计数/`fireB` **未包 `ORPHAN_ZW_EN`** ⇒ 照附录实现时 p5wrapper 的 `ORPHAN_ZW_EN_5=0` 关不掉 Mode B（N2 误杀回归）；v3 缺"OVL 内将来禁用 ack_obs ⇒ 默认推导失效"自评（红队 grep 0 命中，属实） | Mode B 的**全部**（`accrueB`/计数/清零/`fireB`）包进 **`if (ORPHAN_ZW_EN)`**（常数折叠）；补自评：结构性防呆依赖不变量"`TCP_TX_OVL=1 ⇒ ack_obs 置位`"——若将来在 OVL 支内加开关禁用 ack_obs 置位，默认推导会静默给出 1 ⇒ Mode B 打开而 ack_obs 恒 0 ⇒ **误杀**；建议 wrapper 加 `ORPHAN_ZW_EN_5 && ack_obs_available` 结构断言，或至少在 `tcp_rx` 端口注释里写死该不变量 | §3.2 模式 B、附录 B、§8-19、§9-12 |
| **V4-3（N6）** | 高（测试可执行性） | §6.1 未写活动单元臂的 **`ORPHAN_EN=1`**（app_ctrl 默认 0 ⇒ 全部活动门空判）；U11/U12 未写 `ORPHAN_ZW_EN=1`；附录"清零块在计数块之前"在 NBA 下清零无效（U1/U12 每 tick 撞车 ⇒ 会点火） | §6.1 明写：**活动臂（U1–U9/U11/U12）以 `ORPHAN_EN=1` 例化；U11/U12 另 `ORPHAN_ZW_EN=1`；U10/U10' 用 0**；附录清零改为 **`if (clr) 0; else if (tick) +1;`（clr 优先）**，且**清零块物理上放在计数块之后** | §6.1、附录 B |
| **V4-4（N1）** | 中 | B5 时长 ≥120 s **测不到 persist 60 s 档**（累计探询 0.02/5.02/15.02/35.02/**75.02/135.02**/195.02 s；120 s 窗只含 75 s，上一间隔 40 s）；"连续 2 次丢失 ⇒ 180 s，余量 0.39 s ⇒ 不覆盖"**符号/表述矛盾**（180 < 180.39 ⇒ 数学覆盖 0.39 s）；"活零窗对端"未限定 socket 状态 | **B5 ≥135 s**（含 75/135 两次探询 = 一个完整 60 s 间隔；要两个 60 s 间隔 ⇒ ≥195 s）；措辞改为"**2 次丢失 = 180 s < 180.39 s，数学上覆盖 0.39 s；该余量对 ACK 延迟/抖动敏感，按不覆盖处理**"，并补"**≥3 次丢失（240 s）必误杀**"；"活零窗对端"限定为"**socket 未 close** 的活对端"（app close ⇒ 内核回 **RST** ⇒ Mode B 回收是**对的**，不是误杀） | §3.3、§6.3 B5、§7.4、§9-6b、§8-6 |
| **V4-5（X6）** | 中（测试配置） | v3 让 p5wrapper 同时传 `ORPHAN_EN_5=0`/`ORPHAN_ZW_EN_5=0` ⇒ C2a 的"Mode A 无点火"是**空判**（全块关）；C1/C3/C4 的孤儿臂未逐条点名 | **C2a 用 `ORPHAN_EN_5=1 + ORPHAN_ZW_EN_5=0`**（Mode A 开 / B 关）；**基线臂（保旧 p5wrapper）才用 0/0**；**C1/C3/C4 用孤儿臂 A 覆盖并逐条点名**（C1/C2a/C3/C4 均 `ORPHAN_EN_5=1, ORPHAN_ZW_EN_5=0`） | §6.2 |
| **V4-6（X3）** | 中 | `ORPHAN_EN`/`ORPHAN_ZW_EN` 嵌套折叠未写；`ZW_EN=0` 时 `orph_zw_cnt` 是否仍计数未写 | 明写四组合：**00** 全关（零回归，`ev_down_i≡ev_down`）；**01** 外关内"开" = **外层胜出 ⇒ 全关**（内层被外层折叠，等价 00）；**10** Mode A 开 / Mode B 全关（`accrueB`/计数/清零/`fireB` 常数折叠，`orph_zw_cnt` **完全不动**、寄存器被优化掉；C2a 用此）；**11** 全开（板 / C2b）。**`ZW_EN=0` ⇒ `orph_zw_cnt` 不计数、不清零、不点火（整块折叠；不是"计数但无火"）** | §3.2、§3.3、§5、附录 B |
| **V4-7（X7）** | 中（门级） | C2b 的 `ack_obs` 未写刺激方式（force vs 真 ACK 帧）；force 则"真路径门"名不副实 | C2b 的 `ack_obs` 用**真纯 ACK 帧注入**（现有 TB 帧注入设施：按 4 元组构造 flags=ACK、无载荷的以太帧注入 RX 路径，使 `tcp_rx` **真置位** `ack_obs`），**不用 force**；活零窗臂 = 周期注入真 ACK，死零窗臂 = 完全不注入。TB 注入设施不足时先补 helper，并把"**注入后 `ack_obs` 真出现脉冲**"作为前置断言（防"注入过 ≠ 测到了"） | §6.2 C2b |

**v4 对账说明**：FINDINGS_V3 的 7 条必修**全部接受**（逐条现读复核，未发现需要反驳的条目）；N14 的红队认账与 v3 现读一致。v3 的机制层结论（模式 A 四因子、模式 B 判据、FSM 串行化、state-first 顺序）**不变**，本版只补附录权威文本与测试配置。

---

## v4.1（2026-10-17 实施期补充，TL 亲记）

- **F1（实施轮发现：孤儿回收后 `active=0` 不可达）**：`tcp_tx_frame.s_axis_tready` 的 S_IDLE 子句要求 `wnd_open`（`rtl/tcp_tx_frame.v:674/:1880`；`wnd_open = state==ESTAB && inflight < min(snd_wnd,WIN_CAP)`）⇒ 回收写 state=0 后，app 的收尾字**永远进不去** ⇒ `closing` 保持到下一次 ADD（**已实测自愈**：新 ADD 后 active=1/closing=0/重新发帧）。**TL 裁定 = 选项①：接受"下一次 ADD 自愈"** —— 核心回收（state/CAM/配额）已落地、无线上危害；**板级臂把"下一次 ADD 自愈"列为正式观测项**；**选项②（tcp_tx_frame S_IDLE 对 0 载荷收尾字放宽 `wnd_open`）登记为后续候选**（动核心帧器 + 全局 WNS 余量 1.02% ⇒ 不与本刀捆绑；若板级发现 closing 卡死有实际危害再单开）。
- **F2（实施补强，v5 正式修订时并入 §3.6）**：`fc_upd_wr` 组合门之外，实施补了 `fc_load_blk`（事件拍不装载 `fc_v` 的"请求撤销"必要条件，`rtl/app_ctrl.v:774`）。
- **F7（登记未修）**：投递门在 A 拍 / 事件块 A+1 消费；若 `ev_up` 恰落 A+1 ⇒ 孤儿 DOWN 的 pool/winq 归还与 `o_ev_down` 丢失（核心 state/CAM 已落地；配额由下次 ADD 的 C18 归还）。未构造臂。
- **新门入册 = 暂缓**（依赖轮目录 frozen 锚 + 13 个文本锚点变异体；锚点固化到 `tb/frozen/` + 独立 manifest 后按 `swc` 先例入册）。**wrapper 级 ORPHAN_EN=0 逐位对比臂未做**（单元级 U10' 已做，4207 拍 0 mismatch）。

---

## 修订版 v3（2026-10-17，按 FINDINGS_V2 N1–N15）—— 逐条闭项表（**历史；与 v4 冲突处按 v4 块读**）

> 被审件 = v2（636 行，`8658c373`）；复评件 = `p9_review_orphan_fix_design_20261017/FINDINGS_V2.md`（N1–N15，TL 全采纳）。
> 本版 = **纯纸面修订**；v3 只改 N1–N15 与由此引出的 §3.2/§3.3/§5/§6/§7/§8/§9 对应句；F1/F4/F5/F7/F8/F11/F12/F14–F18 按复评"闭项属实"**不动**。
> ⚠️ 行号一律 2026-10-17 现读；对账见文末"v3 对账说明"。

| # | 严重度 | v2 问题 | v3 处置（闭法） | 闭项位置 |
|---|---|---|---|---|
| **N1** | **阻断** | Mode B 阈值 61.85 s vs persist **60 s 封顶**只余 1.85 s；**任意一次** 60 s 档探询/ACK 丢失 ⇒ ack_obs 间隔 **120 s** ⇒ 误杀活零窗对端；8 位 ZW 计数 + 18 位 tick 上限 109.5 s **物理到不了 120 s** | 选 **(a) ZW 专用 tick**：`ORPHAN_ZW_TICK_BITS=20` ⇒ 2^20 × 1.6384 µs = **1.718 s/tick**；`ORPHAN_ZW_LIM=8'd105` ⇒ **180.39 s**；8 位饱和 **438.1 s**。最坏单次丢失 120 s ⇒ 余量 60.4 s；**连续 2 次丢失（180 s）不在覆盖内**（余量 0.39 s）⇒ 残余措辞改为"**单次**探询/ACK 丢失可容忍；连续两次 = 误杀风险"；B5 跑 ≥2×60 s + 记录探询/ACK 计数；B5c 加"单次丢失"臂。**⚠️ v4 订正：2 次丢失 = 180 < 180.39（数学覆盖 0.39 s、按不覆盖处理）、≥3 次必误杀；B5 ≥135 s** | §3.2-模式B、§3.3、§6.3、§9-6b |
| **N2** | **阻断（门/测试）** | `ack_obs` 只在 `TCP_TX_OVL` 支置位，`else` 恒 0（`tcp_rx.v:617-626`）；v2 §9-12"两支都置位"**不实** ⇒ 非 OVL 的 p5wrapper/C2 零窗臂 Mode B 必误杀 | wrapper 暴露 **`ORPHAN_ZW_EN_5`**（默认由 `` `ifdef TCP_TX_OVL `` 推出：OVL=1 / 非 OVL=0）；p5wrapper 显式传 **0**；板构建（TCP_TX_OVL=1）默认 1；**另设一个定义 `TCP_TX_OVL` 的全链臂**测 Mode B；C2 零窗臂改判"仅 Mode A 负对照（Mode B 在本门关闭）"；§9-12 订正为"仅 OVL 支" | §3.2-模式B、§5、§6.2、§9-12 |
| **N3** | 高 | `fireA/fireB` 无 `!orph_busy`：两槽相邻扫描拍都达 LIM ⇒ 第二槽覆盖第一槽的 FSM ⇒ 第一槽 state=0 半回收（CAM 残留、winq 不还、无 orph_down、st_done 阻止重试） | `orph_busy = orph_state_req || orph_cam_req || orph_wait_cam || **orph_notify_pend** || orph_down_r`；`fireA/fireB` 都加 **`!orph_busy`**（第二槽计数保持饱和、等第一槽完成后下一扫描再点火）；U6 加"双槽同时达限"臂；串行化最坏 = 3 槽 ×（fc 等待 + CAM 清），无半回收。**`orph_notify_pend`** = "state_done+CAM 清都完成、等 `orph_down_r` 投递拍"的寄存器（防止投递被 `to_push/ev1_v` 顺延时 busy 短暂落 0，第二槽乘虚而入） | §3.2、§3.4、§6.1 U6b |
| **N4** | 高 | CAM 清 issue 缺 `state_done`；C3 ③ 用 `st_pend`（fc gnt 沿已清，`app_ctrl.v:1323`）⇒ F9 顺序可回归 / 断言恒假 | 新增寄存器 **`orph_state_done`**：`fc_gnt && fc_sel_r==5 && fc_id_r==orph_slot` 时置 1；fire/abort 清 0。CAM 清 issue = `orph_cam_req && orph_state_done && !scfg_busy && !abort_comb`；C3 ③ 改判 `orph_state_done` | §3.2 步骤 2/3、§3.5、§6.2 C3 |
| **N5** | 高 | `to_push ← !orph_down` 与 `orph_down ← !to_push` 互为条件 ⇒ 若 `orph_down` 非寄存器则**组合环** | **`orph_down` 钉成寄存器**（`orph_down_r`，1 拍脉冲）：`orph_down_r <= orph_ready && !ev_up && !ev_down && !to_push && !ev1_v && !to_pushed_r`；`ev_down_i = ev_down | orph_down_r`；`to_push` 的 `!orph_down_r` 是寄存器项 ⇒ 无环 | §3.2 步骤 4、§3.6、§5 |
| **N6** | 高（测试可执行性） | U1"每 4096 轮"、U4"每 1000 轮(<LIM)"、U12"每 5 s"与 TB 小值（LIM=2/TICK_BITS=1 ⇒ 6.6 µs）量纲冲突 ⇒ 基线即红/负对照空转；U6 无"state gnt 后、CAM 清前"臂；U2"visits"无定义 | 全部按 **tick 单位**重写：U1/U4 进度每 `max(1,LIM/2)` ticks；U12 `ack_obs` 每 `max(1,LIM/2)` ticks；U2 `retx_active` 每 `max(1,LIM/2)` ticks；U6 加 state-gnt→CAM-clear 窗口臂；U6b 加双槽同时达限；TB 参数显式 `ORPHAN_LIM=2/TICK_BITS=1`、`ORPHAN_ZW_LIM=2/ZW_TICK_BITS=1` | §6.1 |
| N7 | 中 | C2 零窗臂的"无点火"在 Mode B 下只有"活零窗 + ack_obs"成立；v2 未更新 | C2 拆两行：**C2a（p5wrapper，Mode B 关闭）只测 Mode A 零窗排除**；**C2b（新 OVL 全链臂，Mode B 开）测活零窗（注入 ack_obs）不点火 + 死零窗点火** | §6.2 |
| N8 | 中 | §3.6 use-point 把 `stat_ev_drop` 写成 `:1376`（实为 `ev_ovf`；stat_ev_drop 在 `:974`）；`ev_ovf` 未列入"保持原始" | 两处都改：**保持原始 = `ev_push`(:437)、`stat_ev_drop`(:974)、`ev_ovf`(:1376)**；内部用 `_i` 的清单照旧 | §3.6 |
| N9 | 低 | B5b 未进 §6.3 编号臂序；§7.4 汇总漏 B5；2×LIM 时长未在 §6.3 统一 | §6.3 臂序补 B5/B5b/B5c；§7.4 补 B5；时长统一（模式 A ≥2×LIM = ≥124 s；B5 ≥2×60 s = ≥120 s；B5c ≥200 s；B5b ≥2×180.39 s ≈ ≥361 s）。**⚠️ v4 订正：B5 ≥135 s（120 s 测不到 60 s 档）** | §6.3、§7.4 |
| N10 | 低 | wrapper 未暴露 `ORPHAN_ZW_EN_5` | 加 wrapper 参数 `ORPHAN_ZW_EN_5`（见 N2） | §5 |
| N11 | 低 | U10' 的"改前冻结锚"未点名（现有 `app_ctrl_base.v` 早于 HEAD） | U10' 冻结锚 = **快照当前 HEAD 的 `rtl/app_ctrl.v`**（实施时按 sha256 命名，如 `tb/frozen/app_ctrl_head_<sha8>.v`）；**不用** `sim/p5wu_p1p2/app_ctrl_base.v` | §6.1 U10'、§7.2 |
| N12 | 低 | p5wrapper "重基线"削弱回归门 | wrapper 暴露 **`ORPHAN_EN_5`**（默认 1）；**p5wrapper 显式传 `1'b0`**（保旧基线，不重基线）；板构建与新 OVL 臂传 1 | §5、§6.2、§7.2 |
| N13 | 低 | F6-a 界未提 winq 归还 | 补一句：同槽 ADD 的 C18 记账会先归还旧配额（`app_ctrl.v:987-991`：`pool <= pool - g_grant + winq[ev_slot]`）⇒ F6-a 的 winq 不会永久蒸发，只占用到下一次 ADD | §9-6a |
| N14 | 低 | 行号漂移 | **对账**：本 agent 现读 `board/wrapper_p4.v:1345-1347` 是三条 `app_reg_*` assign（1344 注释、1348 空行）；FINDINGS 记 `:1346-1348` 与现读差 1 行。v3 正文按**现读 1345-1347**，同块语义不变；若实施时行号再漂，按 `grep -n "app_reg_addr"` 现取 | 全文引用 |
| N15 | 低 | U2 "每 12207 visits" 无定义 | 改为 **`retx_active` 每 `max(1,LIM/2)` ticks 一次**（app_ctrl 单元没有 visit 概念） | §6.1 U2 |

**v3 对账说明**：N1–N13、N15 的红队结论全部接受（逐条现读复核）；**N14 的行号与现读差 1 行**（`board/wrapper_p4.v` 的 `app_reg_*` assign 现读 1345–1347，FINDINGS 记 1346–1348），语义一致，正文按现读并注明。其余未发现需要反驳的条目。

---

## 修订版 v2（2026-10-17，按 FINDINGS F1–F18）—— 逐条闭项表（**历史；冲突处按 v3 块读**）

> ⚠️ **本块 = v2 历史**。凡冲突处**按 v4 → v3 的顺序读**（v4 最新），尤其：F6-b 阈值（v2 的 61.85 s → v3 的 180.39 s）· F9 的 CAM 清 issue（v2 无 `state_done` → v3 加 `orph_state_done`）· F3 的 issue 门（v3 加 `orph_state_done`）· F2 的作用域（v3 放进 `ORPHAN_EN` + `ORPHAN_EN_5`）· N3/N4/N5（v2 未覆盖）。
> 被审件 = 本文件 v1；审查件 = `p9_review_orphan_fix_design_20261017/FINDINGS.md`（18 项，TL 全采纳）。
> 本版 = **纯纸面修订**；下列每条给出"v1 问题 → v2 处置 → 闭项位置"。红队判"不实"的条目按**红队结论**改（若本 agent 复核后认为红队某条不实，在该行写"对账"并给源码依据）。

| # | 严重度 | v1 问题（FINDINGS） | v2 处置（闭项） | 闭项位置 |
|---|---|---|---|---|
| **F1** | **阻断** | 时基 1000× 错：`144 × 419.43 µs = 60.398 ms`，不是 60.4 s；8 位饱和只有 106.95 ms | `ORPHAN_TICK_BITS` 默认 **18**（`scan_round[17:0]==0` = 262,144 轮 = **429.4967 ms**/tick）⇒ `ORPHAN_LIM=144` = **61.85 s**；8 位饱和 **109.52 s**；重写全部阈值论证/板级时长 | §3.3、§6.3、§7.4、§9-1 |
| **F2** | **阻断** | v1"`ev_up` 拍 `scfg_upd_wr=1`"与源码相反：`ev_up` 是 wscale 写**后一拍**的寄存器输出（`slow_cfg_adp.v:187-197`），该拍 `scfg_upd_wr=0`、`sel_fc` 可开（`wrapper_p4.v:2060`）⇒ fc state=0 落在 ADD 最后一拍**之后** | orphan 源（以及共用 fc 通道）加**组合门**：`fc_upd_wr = fc_v && !(ev_up&&ev_slot==fc_id_r) && !(ev_down&&ev_slot==fc_id_r)`；既有 FIN-timeout/abort 同族竞态**复核为既存**并同批闭；U6 加"同拍"断言 | §3.2、§3.6、§5、§6.1 |
| **F3** | **阻断** | `ev_up` 拍 `busy=0`（CAM 写已在此前完成）⇒ 若 `orph_cam_clr` 在等待，会在 ev_up 拍擦掉**新 ADD 的 CAM 条目** | `orphan_cam_clr` 的 issue 条件 = `orph_cam_req && !scfg_busy && !abort_comb`（`abort_comb` 含同槽 ev_up/ev_down/fin_sent/rst_sent）；U6 加 **post-fire** 变体；B6 加 post-fire 臂；`scfg_busy` 补 `wcnt!=0` | §3.5、§3.6、§6.1、§6.3 |
| **F4** | 高 | NW 75→76 ⇒ MIR 四寄存器自动下移到 `0x150..0x15C`，**UNIMPL=0x160**；v1 把 MIR 真寄存器当空洞（0x15C 会读到 `mir_dma_cnt`） | W75 @ **0x14C** 不变；MIR_STATUS=0x150 / DATA=0x154 / CTRL=0x158 / DMA_CNT=0x15C；**UNIMPL=0x160**；B7/读侧/`P7B_BIZ_WINDOW.md`/`apply_readside.py` 同步；**MIR 地址由 `SNAP_NW` 自动推，不写死**（`axi_regs.v:206,214-218`） | §3.7、§5、§6.3 |
| **F5** | 中 | v1"`replay_full` 在 app 停帧时可能自持"**不实**：重放帧自己在 RX_FIN 用 `upd_wr_data` 推进 `snd_nxt`（`tcp_tx_frame.v:634,648,1200-1213,1383-1385`），`ring_delta` 随重放排空，会话自然收尾 | 删"自持"说；`retx_active` 点火支的**真实价值**改写为"覆盖 `inflight<cap` 的周期 RTO 会话"；点火时机 = 概率性/周期性（61.85 s / 20 ms ≈ 3092 次会话，扫描命中率 ~0.76/次），非结构恒真；§8-17/§9-11 改写 | §3.2、§8-17、§9-11 |
| **F6** | 中 | v1 漏两类真泄漏：① `inflight==0` 的空闲 ESTAB 死对端（work=假，永不回收）；② `snd_wnd==0` 的死对端（accrue 结构性为假，persist 每 60 s 探一个死对端）；§9-6 误述"慢生产者永不回收" | **F6-b 闭**：新增**零窗失联模式 B**——`snd_wnd==0 && snd_nxt!=snd_una && ESTAB`，用 `tcp_rx.ack_obs`（每槽合法 ACK 脉冲）清零，>61.85 s 无 ACK ⇒ 回收（活零窗对端会回 persist 探询的 ACK，死对端不会）；**F6-a 登记未闭**：无在飞数据 ⇒ 与健康空闲不可区分，本批不回收（给界与候选） | §3.2-模式B、§3.4、§9-6a/6b、§6.3 B5b |
| **F7** | 中 | v1 Q3"`Δstat_ev_down` 可观测"**不实**：`wrapper_p4.v:1321-1322` 空接、`:1346-1348` app 寄存器总线静态钉死、快照无此字 | Q3 可观测路径改为 **pcap RST seq + app closing/重连**；删 `Δstat_ev_down`；W75 只计孤儿回收，不是 DEL 计数 | §4.3、§4.4 |
| **F8** | 中 | v1 三处漏：① `ret_slot_q/pool_ret_x`（`app_ctrl.v:880-883`）在 ev_down 块之外，未改 `_i` ⇒ 归还错槽；② `orph_down` 门漏 `!to_pushed_r`（`to_push` 自身含它，`app_ctrl.v:698-699`）⇒ 可连续两拍 `o_ev_down`；③ `st_done` 不被 ev_down 清（`:1014` 只在 ev_up 清），v1"清 st_*"过度声称 | ① 改 `ev_down_i`/`ev_slot_i`；② 门补 `!to_pushed_r`；③ 文案改为"清 `st_pend`（`st_done` 保留到下一次 ev_up）"；use-point 清单补 `ret_slot_q` | §3.2、§3.5、§3.6、§8-9 |
| **F9** | 中 | v1 动作顺序并列：CAM 清先落、fc 被压住 ⇒ 零 CAM 窗口内 `start_data` 仍可启动，`cam_rd_*` 读回全 0 ⇒ 线上出 0 MAC/IP/port 帧 | **state=0 先、CAM 清后**：fire 只挂 `st_pend`；等 fc gnt（state=0 落地）后，才在 `!scfg_busy && !abort_comb` 下发 CAM 清；notify 等两者 | §3.5、§3.6、§6.1 U7 |
| **F10** | 中 | v1 判据无牙：M1/M2/M5 条件未写（U1/U3/U6 缺 retx/窗满见证）；M4 的 mutant 不可红；M6/M8 归属错 | U1 补"周期进度 + 窗满 + 一次 retx"；U3 补"注入一次 retx"；U6 补 pre/post-fire 见证；**M4' = 第三因子强制 1**（U4c 红）；M6→C3、M8→C1；C3 加 mux 分支断言；C1 暴露 `ORPHAN_TICK_BITS_5` | §6.1、§6.2、§6.4 |
| **F11** | 中 | v1 未覆盖慢盆混淆：0x28 构上的全局慢盆态（进入=真异槽并行+小窗 2920，持久 ≥14 min，清除=**重烧（唯一）**）；B3 在盆内结构性做不到；B1 负臂 `W55` 增长会与盆签名混淆 | 臂序 = **快态臂（B3/B5）→ 进盆臂（B4）→ 重烧（清盆）→ 负/正孤儿臂（B1/B2/B6）**；每次烧后先核"盆不在场"（900 Mbps 级二值）；B4 给进入配方 + 见证 | §6.3 |
| **F12** | 低 | v1"矩阵编译清单不含 `app_pattern/wrapper_p4`"**不实（部分）**：`sim/p4gates/p5wrapper_src.f:39-43` 含 `rtl/app_ctrl.v`/`rtl/app_pattern.v`/`board/wrapper_p4.v` | 纠正：p5wrapper 门（#19）确实编译这些文件；**真盲区 = 板宏配置**（`P7B_10G`/`TCP_TX_OVL`/`DP_156MHZ`），不是文件清单；新门仍必须断言"被改文件在编译清单" | §5、§6.2 |
| **F13** | 低 | v1 ORPHAN_EN=0 零回归证据不足（U10 只查新输出为 0；wrapper 传 1 ⇒ 所有 APP_MODE 门都启用新逻辑） | 加**同激励全输出逐位对比臂**（改前冻结锚 vs 新 RTL `ORPHAN_EN=0`，比 `o_ev_up/o_ev_down/o_ev_slot/stat_ev_up/stat_ev_down/pool/winq/app_tx_ready`）；明确作用域 = **全部 APP_MODE 构建**（含 p5wrapper #19，需重基线）；默认非 APP 构建无 app_ctrl | §5、§6.1 U10'、§7.2 |
| **F14** | 低 | B1 不是严格单变量：0x2A vs 0x28 = orphan + W75 + BID | 接受 W75 为**纯观测第二变量**并写明（或按 §7.5 先砍 W75 再跑 B1）；B1 表加"变量清单" | §6.3、§7.5 |
| **F15** | 低 | v1"+96 FF 落宿主族"不精确：只有 32 落被点名的宿主网 | 改为 **+32 宿主网（`snap_words_r`）+32 `dout_a`（pcie 另一族）+32 `hold_b`（DP）** | §3.7、§7.1 |
| **F16** | 低 | `scfg_busy` 不含 `wcnt`（部分记录时可为 0） | 定义补 `|| (wcnt != 3'd0)`；结论仍安全（部分记录尚未到 CAM 写；即使 clear 先发，后续 ADD 的 CAM 写会覆盖） | §3.2、§3.6、§5 |
| **F17** | 低 | `tcp_tx_frame.scan_now` 非自由运行；v1 的"每槽每 1.6384 µs"是名义值 | 写明：app_ctrl `scan_tick` 自由运行 /16，但采样/`scan_round` 可被 `init_pend`/同槽事件跳过 ⇒ orphan tick 会拉长（安全方向）；tcp_tx 的 `scan_now` 确实非自由（被 rx_idle/ack/svc/ring 门控），本设计**不用它**做 orphan 时基 | §3.2、§8-7 |
| **F18** | 低 | M8/U2 的"app 收尾"标签错（U2 单元门无 app_pattern）；M6 的 CAM 内容检查也不在 U2 | M8→C1；M6→C3；U2 只查 `st_pend`/CAM 清脉冲表达 | §6.1、§6.4 |

**对账说明（红队也可能错，本 agent 复核后的分歧）**：本版对 F1–F8、F10–F18 的**红队结论全部接受**（逐条现读复核，未发现需要反驳的条目）。唯一需要限定的是 F14 与 F15 的**措辞范围**：F14 的"单变量"严格说不成立，但 W75 是纯读侧观测量、不参与任何行为判据；F15 的 +96 FF 里只有 32 落在被点名的宿主网（另 64 在 pcie 的 `dout_a` 与 DP 的 `hold_b`），三者都属于 0x28 报告面的异步复位族邻近，但**不是同一个端点族**。这两点已按"限定"写进正文，不构成对红队结论的反驳。

---

## 一页答案（Q1/Q2/Q3，v4 口径）

### Q1「释放 ≠ 死亡」——推荐语义（v1 结论不变）

| | 事件 A = 慢路径放弃跟踪 | 事件 B = 对端失联（会话死亡） |
|---|---|---|
| 判定者 | HLS（`T_SYN_RCVD` RTO 超时 / 看门狗复位） | **快路径**（数据面判据，§3） |
| 含义 | HLS 自己的握手簿记丢失；**快路径 TCB 可能仍然完全健康** | 会话已无法推进（长时间无 `snd_una` 进展 / 零窗无 ACK + 有未决数据） |
| 应该做什么 | **什么都不做**（不发 cfg 记录、不动 CAM/TCB、不产生 ev） | 快路径回收（state=0 + CAM 清）→ app CONN_DOWN → 槽可复用 |
| 通知谁 | **不通知任何消费者** | app（复用 `o_ev_down`/`o_ev_slot`） |

**推荐载体 = 完全不发释放记录；B 的通知由 app_ctrl 自产 `orph_down`，并入 app_ctrl 的 ev_down 内部事件块；`slow_cfg_adp.ev_down` 的"DEL 已落地"语义原样保留。**
**为什么 DEL 绝对不行**：被动连接的第三个握手 ACK 是纯 ACK ⇒ `rx_classify` 判 FAST（`rtl/rx_classify.v:101-107`）⇒ HLS 永远停在 `T_SYN_RCVD`、约 2.56 s 后被静默释放（`hls/src/layer_tcp.cpp:531-535`）⇒ 释放时发 DEL 会把每一条健康被动连接拆掉（灾难）。
**后备变体 B（REL 记录）的 v2 补充**：`slow_cfg_adp` 的 `is_add/is_del` 只有 0/1，**任何未知 cmd 会落进 DEL 的 else 支**（`slow_cfg_adp.v:145-168`）⇒ 实施 cmd=2 必须**同时改解析器**，否则 REL 会变成拆连。本批仍不推荐（HLS 重综合 + 记录协议）。

### Q2 快路径"失联回收"——v4 判据与阈值

**判据（模式 A：非零窗；四因子，缺一不点火）：**
1. **长期停滞**：`state==ESTAB` ∧ `snd_wnd != 0` ∧ 有未决数据（`snd_nxt != snd_una`，或本槽重传会话进行中）∧ 无 FIN/RST 在飞；`snd_una` 持续不前进超过阈值。`snd_una` 每次推进（`tcp_rx` 的 `upd_sel==2` 授权写，`rtl/tcp_rx.v:486-490`）⇒ **计数清零**。
2. **重传见证**：停滞区间内至少见过一次本槽的重传会话（`retx_active && retx_id==slot`；逐拍置 `orph_saw[slot]`，不靠扫描采样）。
3. **点火时"正在努力但出不去"**：`inflight >= min(snd_wnd, WIN_CAP)` **或** 本槽重传会话正在进行（`retx_active && retx_id==slot`）。
   - `win_closed` 支排除"慢盆最后一段（小在飞、永不重传）"。
   - `retx_active` 支覆盖 `inflight<cap` 的**周期 RTO 会话**——它是**概率性/周期性**的（每次会话 ~1.24 µs、每 20 ms 一次；61.85 s ≈ 3092 次会话，app_ctrl 每 1.6384 µs 采一次、单次命中率 ~0.76 ⇒ 实际必中；若某拍没抓到，下一次会话 ≤20 ms 后再判，计数不清零）。**它不是"自持态兜底"**（见 F5）。
4. **排除重传次数作为充分条件**（反例）：慢盆 `W55=49.9/s` 但 `snd_una` 在推进；Stage C 自持环重传 13.8–19.3× 但 ACK 在回来；persist 探询也是"重传"，对端活着。⇒ 重传只能当**必要见证**。

**模式 B（零窗死对端，F6-b 闭法，v3 修 N1/N2）**：`state==ESTAB ∧ snd_wnd==0 ∧ snd_nxt!=snd_una ∧ !fin_sent ∧ !rst_sent`，且**本槽在 180.39 s 内没有收到任何合法 ACK**（`tcp_rx.ack_obs` 每槽脉冲清零）⇒ 回收。
- **阈值（v3 修正 N1，v4 修正措辞）**：`ORPHAN_ZW_TICK_BITS=20` ⇒ 2^20 × 1.6384 µs = **1.718 s/tick**；`ORPHAN_ZW_LIM=8'd105` ⇒ **180.39 s**；8 位饱和 **438.1 s**。
  - persist 退避 `ps_reload` = 20 ms→5→10→20→40→**60→60… s**（`tcp_tx_frame.v:407-419`、`PS_MAX` `:299-301`）⇒ 稳态 ACK 间隔 **60 s**；**任意一次 60 s 档探询或其 ACK 丢失 ⇒ ack_obs 间隔 120 s** ⇒ 180.39 s 阈值**可容忍 1 次**（余量 60.39 s）。
  - **连续 2 次丢失 ⇒ 间隔 180 s；180 < 180.39 ⇒ 数学上覆盖 0.39 s**。该余量对 ACK 延迟/抖动敏感（内核延迟 ACK、调度卡顿可吃掉它）⇒ **按"不覆盖"处理**（v4 修正符号/表述）。**≥3 次丢失（240 s）⇒ 必误杀**（v4 补）。
  - **socket 未 close** 的活零窗对端会对 persist 探询回 ACK（win=0）⇒ `ack_obs` 清零 ⇒ 不误杀。【推断：RFC 1122 §4.2.2.17 / Linux 行为；本板未单独测；验证臂 = U12 + B5/B5c】**app 已 close 的 socket ⇒ 内核回 RST 而非 ACK ⇒ Mode B 回收是"对的"（会话确实死了），不是误杀**（v4 限定）。
- **N2（ack_obs 仅 OVL）**：`tcp_rx.v:617-626` 的 `ack_obs` **只在 `ifdef TCP_TX_OVL` 支置位**，`else` 恒 0 ⇒ 模式 B 只在板构建（`TCP_TX_OVL=1`）有效；wrapper 用 `ORPHAN_ZW_EN_5`（由 `ifdef TCP_TX_OVL` 推出默认）把非 OVL 门关掉，另设 OVL 全链臂测模式 B。
- 死零窗对端没有任何 ACK ⇒ 180.39 s 后回收（v1 的永久占槽被闭）。

**模式 A 阈值（v2 修正 F1，v3 不变）**：默认 **61.85 s** = `ORPHAN_LIM = 8'd144` × `429.4967 ms/tick`；tick = `ORPHAN_TICK_BITS=18`（`scan_round[17:0]==0` = 262,144 轮 × 1.6384 µs = 429.4967 ms）；8 位饱和 **109.52 s**。
依据（v2 重算）：61.85 s ≫ RTO 20 ms（≈3092×）、≫ app FIN 超时 400 ms（≈155×）、≫ HLS 释放周期 2.56 s（≈24×）、> 慢盆 20 ms 簇尺度；< Linux `tcp_retries2` ~13 min。

**成本（v4）**：模式 A 128 FF + 模式 B 128 FF（`ORPHAN_ZW_EN=0` 时折叠）+ saw 16 + FSM ~22 + `stat_orphan` 32 + `orph_state_done`/`orph_busy`/`orph_down_r`/`orph_notify_pend` ~7 ≈ **330 FF**；`ORPHAN_EN=0` 整块折叠为 0。
**F6-a 登记未闭**：`inflight==0` 的空闲 ESTAB 死对端无法与健康空闲区分，本批不回收（影响界/候选见 §9-6a；winq 由同槽 ADD 的 C18 归还，`app_ctrl.v:987-991`）；**不许把它算作已闭**。

### Q3 迟到 RST 误杀——**不同批，登记**（F7 可观测路径修正）

- 迟到 RST 按残留 `peer_ip/port` 命中 ⇒ 4 元组复用时可能误杀新连接（`hls/src/layer_tcp.cpp:631-641`）。
- **不同批的理由**：本修复不产生任何 RST；该向量在静默释放后就已存在（HLS 槽 2.56 s 就空出）；可信修法需要快路径的 seq 窗口，而 HLS 从未见过第三 ACK/数据（`peer_seq` 停在 SYN+1）；同批会扩到 HLS 重综合。
- **可观测（v2 修正 F7）**：`Δstat_ev_down` 板上**不可读**（`wrapper_p4.v:1321-1322` 空接、`:1346-1348` app 总线静态钉死）。改用 **pcap**（"新连接建立后立刻收到 seq 属于旧空间的 RST"）+ **app closing/重连**。W75 只计孤儿回收，不是 DEL 计数。

---

## 1 事实基线（逐条现读复证）

### 1.1 静默释放链（HLS）

- 被动建连：SYN 在 `T_LISTEN` 分支发 `cfg ADD + SYN|ACK`（`hls/src/layer_tcp.cpp:668-679`），HLS 进 `T_SYN_RCVD`。
- 第三个 ACK（纯 ACK）由 `rx_classify` 判 **FAST**（`rtl/rx_classify.v:101-107`：`cur_tcp_ctl = |flags[2:0]`）；`tcp_rx` 只认 CAM 命中 + `state==ESTAB`（`rtl/tcp_rx.v:307,347`）⇒ **HLS 永远看不到第三个 ACK**。
- `T_SYN_RCVD` 的握手完成分支结构性不可达（`layer_tcp.cpp:680-684`）；定时重传已被 P4b-5 废除（`:524-530`）⇒ 唯一出口 = 空闲拍 RTO 扫描的一次超时：`c.state=T_FREE; c.retrans_pending=false; continue;`（`:531-535`）。
- **该分支不写 cfg 记录**（`grep cfg_write` 调用点 = `:609/:637/:663/:677/:699/:721`，无一处在此）⇒ `slow_cfg_adp` 的 ev 源（`:164-168` / `:193-195`）不产生任何脉冲。
- 释放只动 HLS 的 `state/retrans_pending`（+退避量），**快路径 CAM/TCB、app 会话、各 per-slot 外围一个字节不动**（机制档案 §2.3 逐字段表）。
- `MAX_TCP_CONN = 3`（`layer_tcp.cpp:10-12`），ADD 的 slot 字段 = HLS cid（0..2，`cfg_write` w0 低 4 位，`:170`）；快路径 CAM/TCB 是 **16** 槽（`tcb.v:8-19`、`tcp_cam.v:6-7`）⇒ **现役可达槽只有 0..2**；本设计仍按 16 槽统一处理（未来 `MAX_TCP_CONN` 变大自动覆盖）。

### 1.2 app 的通知面

- `ev_up`：ADD 的 wscale 授权拍（`slow_cfg_adp.v:187-198`）→ `app_ctrl` → `app_pattern`。
- `ev_down`：DEL 的 state=0 授权拍（`slow_cfg_adp.v:158-168`）+ `app_ctrl` 自己的超时 CONN_DOWN（`app_ctrl.v:861-863,1056-1067`）。
- `app_tx_ready[15:0]`：256 拍轮扫电平（`app_ctrl.v:557-585`）。
- **没有第四条**（`app_pattern.v:55-57,67`）。静默释放不经过这三处中的任何一处。

### 1.3 快路径的 `state=0` 写口（穷举）

1. **DEL 记录**：`slow_cfg_adp.v:158-163`（`upd_sel=5`，`val=0`，`ev_down` 同拍）。
2. **app_ctrl 的 `fc` 通道**：`st_pend` 位图 + `fc_sel_r=5`（`app_ctrl.v:701-726,871-874,1311-1336`），现有触发 = `rst_sent[slot]` 或 `st_grace`（`to_fired` 且宽限到点），而 `to_fire` 要求 `fin_sent[slot]`（`app_ctrl.v:861-863`）。
3. **无第三条**。⇒ 连续模式（`TX_CONTINUOUS=1`）下，**没有任何自主路径写 state=0**。

### 1.4 与既有机制的交互

- **persist 零窗探询**：`ps_arm = PERSIST_EN && scan_estab && snd_wnd==0 && snd_nxt!=snd_una && !fin_sent_r && !rst_sent_r`（`tcp_tx_frame.v:752-757`）；退避 20ms→5→10→20→40→60s 封顶（`:408-417`）。⇒ 零窗是"对端活着但窗关"；本设计模式 A 在 `snd_wnd==0` 时清零，模式 B 用 `ack_obs` 判活。
- **慢盆**：20 ms 锁步重放是常态（`W55≈49.9/s`），但 `snd_una` 在推进（爬行 1.55 Mbps）⇒ 模式 A 每次 `snd_una` 推进清零 ⇒ 不误杀；慢盆"最后一段永不重传"的小在飞停滞由 `win_closed` 支排除。
- **C1 偷槽（ADD 覆盖）**：HLS 释放后的槽是"最低空闲"，新 SYN 会 ADD 同名槽；ADD 全量覆盖 CAM+TCB 并发 `ev_up`（`slow_cfg_adp.v:129-198`）⇒ 本设计在 `ev_up` 同槽时**组合中止**（§3.6），绝不与新会话抢。
- **app 的 `closing`/`ack_seen` 门**：`ev_down && active && slot==act_id` ⇒ `closing<=1` ⇒ W3 收尾 ⇒ `active=0`（`app_pattern.v:388,896-940`）；`ack_seen_w` 只在 `scfg_ev_up` 清（`wrapper_p4.v:2155-2166`）。
- **D1 同槽重连清理**：`cfg_up`（= `scfg_ev_up`）清 `fin_sent_r/whi_r/rst_sent_r/...`（`tcp_tx_frame.v:1101-1128`）。
- **E12 四计数器**：`stat_up_ev/stat_sw_req/stat_sw_apply/stat_up_pend`（`app_pattern.v:556-591`，W71..W74）。本设计不改 ev_up 链；新增 `stat_orphan`（回收提交数）。

### 1.5 观测面（现役 75 字）与 v4 的几何

`SNAP_NW_P6E=75`（`wrapper_p4.v:3296`）、`SNAP_P7BDP_NW=35`（`:3317`）、W74 @ `0x148`。
**v2 加 W75 后**（F4）：`SNAP_NW_P6E=76`、`SNAP_P7BDP_NW=36`；W75 @ **`0x14C`**；MIR_STATUS=**`0x150`** / MIR_DATA=**`0x154`** / MIR_CTRL=**`0x158`** / MIR_DMA_CNT=**`0x15C`**；**UNIMPL=0x160**（`axi_regs.v:206,214-218` 的 `SNAP_LAST_IDX=8+SNAP_NW-1` 自动推导；**不写死 MIR 地址**）。
W55 = `tcp_tx_frame.stat_retx`、W68 = `tcp_rx.stat_ack_adv`——板级判据的现成仪器（`P7B_BIZ_WINDOW.md` §1）。

---

## 2 Q1：「释放 ≠ 死亡」的语义设计

### 2.1 定义

- **事件 A（释放）**：HLS 的 `T_SYN_RCVD` RTO 超时（`layer_tcp.cpp:531-535`）与 HLS 看门狗复位全槽清空（`:498-503`）。只说明慢路径不再拥有该槽。
- **事件 B（失联）**：快路径判据（§3）成立。说明会话已无法推进。
- 关系：A 不蕴含 B；B 不蕴含 A。健康连接会先经历 A（2.56 s）再无限期 B=假；死连接可能 A 之前就 B=真。

### 2.2 载体候选

| 方案 | 内容 | 代价 | 结论 |
|---|---|---|---|
| **A（推荐）** | 释放不写任何记录；B 由快路径 app_ctrl 自产 `orph_down`，并入 app_ctrl 的 ev_down 内部事件块；`slow_cfg_adp.ev_down` 语义不动 | 零 HLS 改动；app_ctrl + wrapper + slow_cfg_adp 一个 busy 输出 | **采用** |
| B | 新增 `CFG_REL`（cmd=2）记录：HLS 释放分支发 8 词；`slow_cfg_adp` 只置 per-slot `slow_released` 电平（不拆连、不通知 app） | HLS 改源码+重综合；记录协议+解析器；**必须同时改 `is_add/is_del` 的 else 支**（F2.4） | **后备**（仅当 TL 要求"释放时通知"字面语义） |
| C | 复用/变体 DEL（cmd=1 带新字段，或释放时直接 DEL） | 看似最小 | **禁止**：会把全部健康连接在 2.56 s 后拆掉（§2.3） |

### 2.3 为什么 DEL 是灾难

- 被动连接在 `T_LISTEN` 就乐观建连（ADD+SYN|ACK，`layer_tcp.cpp:668-679`）；第三个 ACK 只进快路径 ⇒ HLS 永远停在 `T_SYN_RCVD`。
- 因此**每一条**健康被动连接都会在 ~2.56 s 被静默释放（C1 板级实测；名义 80 ms 是注释按 125MHz/pass 的错估）。
- 若释放时发 DEL：`slow_cfg_adp` 清 CAM + 写 state=0 + 发 `ev_down`（`:129-168`）⇒ 快路径立刻停止收/发该连接，app 收尾。**线上所有连接每 2.56 s 被拆一次**。
- 与 P4b-5 的"定时重发 SYN+ACK 会招 RST 杀连接"同族（`layer_tcp.cpp:524-530` 注释）：慢路径不能对慢路径看不见的连接做主动动作。

### 2.4 为什么 REL 记录不必要（但保留为后备）

- 快路径判死所需的一切（`snd_una/snd_wnd/snd_nxt/state/retx 会话/ack_obs`）都在它自己手里；REL 只多告诉它"慢路径不看了"，对判死不是必要条件。
- 代价：HLS 源码+重综合 + 新记录类型 + `slow_cfg_adp` 解析 + 新事件语义；收益 = 定时器从"释放后"起算（省 2.56 s，相对 61.85 s = 4%）。
- **后备变体 B 的最小定义**：`w0 = (wscale<<16)|(cmd=2<<8)|slot`，其余 7 词 0；`slow_cfg_adp` 在 S_CAM 锁存 slot 并输出 `rel_slot/rel_pulse`（1 拍）；app_ctrl 收到后只做 `orph_cnt[slot]<=0; orph_saw[slot]<=0;`（重新武装），不碰 TCB/CAM、不动 ev。**实施时必须同时改解析器**：`is_add/is_del` 之外的 cmd 目前落进 DEL 的 else 支（`slow_cfg_adp.v:145-168`）。验证锚 = csim 对照 + 板级 `Δstat_orphan` 不变。

### 2.5 `ev_down` 语义的边界

- **`slow_cfg_adp.ev_down`** 仍是"DEL 的 state=0 已落地"（唯一生成点 `:164-168`）。
- **app 看到的 `o_ev_down`** 语义是"会话结束"（DEL 或快路径失联回收）。这是 app 原本消费的语义（`app_pattern.v:896-940`）。
- 新增的 `orph_down` **不进入事件 FIFO**（`ev_push` 仍只看原始 `ev_up/ev_down`），只走内部事件块与 `o_ev_down`。

---

## 3 Q2：快路径失联判据与回收（v4）

### 3.1 判据候选与反例

| 候选 | 反例（必须不误杀） | 结论 |
|---|---|---|
| `retx` 次数 / `W55` 高 | 慢盆 `W55=49.9/s` 但 `snd_una` 在推进；Stage C 自持环重传 13.8–19.3×；persist 探询也是重传 | 不能当判据（只能当见证） |
| 仅 `snd_una` 停滞 | persist 零窗：`snd_una` 不前进但对端活着 | 需加 `snd_wnd != 0`（模式 A）或 `ack_obs`（模式 B） |
| `snd_una` 停滞 + 非零窗 | 慢盆最后一段：小在飞、永不重传 | 需加 `win_closed` |
| `snd_una` 停滞 + 非零窗 +（窗满或本槽重传会话中） | "对端安静且本端也没重试"（app 已停、在飞恰好未清） | 需加 `saw` |
| **模式 A：四因子** | —— | **采用** |
| **模式 B：零窗 + 180.39 s 无 `ack_obs`** | **socket 未 close** 的活零窗对端会回 ACK（persist 探询）；app close ⇒ RST ⇒ 回收正确 | **采用（F6-b 闭）** |

### 3.2 正式判据（逐条可综合）

记 `scan_id` 为 app_ctrl 当前扫描槽（`app_ctrl.v:455-457,538`）。**名义**每槽每 1.6384 µs 采一次（`scan_tick` 是 16 分频自由运行；但采样/`scan_round` 会被 `init_pend` 或同槽事件跳过 ⇒ **时间基会拉长，方向安全**；F17）。

**输入（app_ctrl 新增，均来自现役线）：**
- `rc_state/rc_snd_nxt/rc_snd_una/rc_snd_wnd`（现有 TCB 组合读口 C，`:343-350`）。
- `retx_active` + `retx_id[3:0]`（`tcp_tx_frame` 现成输出，`tcp_tx_frame.v:113-114,1008-1010`；wrapper `:1761,2132,2219,2264`）。
- `una_adv` + `una_adv_id[3:0]`（wrapper 从 `rx_upd_gnt && (rx_upd_sel==3'd2)` 取；`wrapper_p4.v:1782-1784,2052-2053`，`tcp_rx.v:486-490`）。
- `ack_obs` + `ack_obs_id[3:0]`（`tcp_rx.v:129-130,618-622`；wrapper `:1829-1830` —— **声明必须前置到 `u_app_ctrl` 之前**）。
- `scfg_busy`（`slow_cfg_adp` 新增输出：`(state != S_RECV) || !f_empty || (wcnt != 3'd0)`；F16）。

**组合量（模式 A）：**
```
inflight   = rc_snd_nxt - rc_snd_una
cap_eff    = min(rc_snd_wnd, WIN_CAP)
win_closed = (inflight < 32'h8000_0000) && (inflight >= {16'b0, cap_eff})
work       = (rc_snd_nxt != rc_snd_una) || (retx_active && (retx_id == scan_id))
accrue     = scan_tick && !init_pend && !(ev_blk && (ev_slot_i == scan_id)) &&
             (rc_state == ST_ESTAB) && (rc_snd_wnd != 0) && work &&
             !fin_sent[scan_id] && !rst_sent[scan_id] &&
             !st_done[scan_id] && !to_fired[scan_id]
```
（同槽事件守卫，不是全局 `!ev_blk`；`fire` 同款。`win_closed` 比 `tcb.win_open` 多一个 `<2^31` 回绕守卫，是**有意超集**，不是"同一不等式"——F7 表。）

**计数（模式 A，每槽 8 位饱和）：**
```
if (scan_tick && 采样未被阻塞) begin
  if (!accrue)            orph_cnt[scan_id] <= 8'd0;
  else if (orph_tick)     orph_cnt[scan_id] <= (orph_cnt==8'hFF) ? 8'hFF : orph_cnt+1;
end
orph_tick = (scan_round[ORPHAN_TICK_BITS-1:0] == 0)   // 默认 18 位 = 262,144 轮 = 429.4967 ms
```
**见证（逐拍，不靠扫描采样）：**
```
if (retx_active) orph_saw[retx_id] <= 1'b1;   // 按 retx_id 解码/one-hot 置位
```
**清零（优先于计数）：**
- `una_adv && (una_adv_id == <slot>)` ⇒ `orph_cnt[slot]<=0; orph_saw[slot]<=0;`（snd_una 推进 = 新停滞区间）。
- 扫描时 `!accrue` ⇒ 清（含 `snd_wnd==0`）。
- `ev_up || ev_down` 同槽、`cfg_up` 同槽 ⇒ 清。
- 点火/中止 ⇒ 清。

**全局忙门（N3）**：
```
orph_busy = orph_state_req || orph_cam_req || orph_wait_cam || orph_notify_pend || orph_down_r
```
`orph_wait_cam` = "CAM 清脉冲已发、等 clr 回落"的短状态（clr 高 1 拍 + 回落后检测拍，共约 2 拍；在 `cam_clr_done` 沿与 `orph_notify_pend` 同沿交接）；`orph_notify_pend` = "state_done + CAM 清都完成、等 `orph_down_r` 投递拍"的寄存器（投递被 `to_push/ev1_v` 顺延时 busy 不落 0，第二槽不能乘虚而入）。

**点火（模式 A，N3 加 `!orph_busy`）：**
```
fire_a = scan_tick && !init_pend && !(ev_blk && (ev_slot_i == scan_id)) && accrue &&
         orph_saw[scan_id] && (orph_cnt[scan_id] >= ORPHAN_LIM) &&
         (win_closed || (retx_active && (retx_id == scan_id))) && !orph_busy;
```
- `win_closed` 在停滞区间绝大多数采样为真；若某拍为假且没有活动 retx ⇒ 不点火、不清零，下一轮再判。
- 活动 retx 支是**周期性概率**命中，不是结构恒真（F5）：61.85 s / 20 ms ≈ 3092 次会话、单次命中率 ~0.76 ⇒ 实际必中；某拍漏抓则下一会话 ≤20 ms 后再判。
- **不是**"replay_full 自持兜底"——重放帧自己推进 `snd_nxt`（`tcp_tx_frame.v:634,648,1200-1213,1383-1385`），会话自然收尾。
- `!orph_busy`：第二槽达限时计数保持饱和、**等第一槽 FSM 完成后下一扫描再点火** ⇒ 不会覆盖第一槽的 `orph_slot`/pending（N3）。

**模式 B（零窗死对端，F6-b；N1/N2；v4 全块包 `ORPHAN_ZW_EN`）：**
```
if (ORPHAN_ZW_EN) begin : g_orph_zw          // 常数折叠：=0 ⇒ 整块不存在（不计数、不清零、不点火）
  zw_accrue = scan_tick && !init_pend && !(ev_blk && (ev_slot_i == scan_id)) &&
              (rc_state == ST_ESTAB) && (rc_snd_wnd == 0) &&
              (rc_snd_nxt != rc_snd_una) &&
              !fin_sent[scan_id] && !rst_sent[scan_id] &&
              !st_done[scan_id] && !to_fired[scan_id]
  zw_tick   = (scan_round[ORPHAN_ZW_TICK_BITS-1:0] == 0)   // 默认 20 位 = 1,048,576 轮 = 1.718 s
  zw_reset  = ack_obs && (ack_obs_id == <slot>)            // 任何合法 ACK（含零窗 ACK）重置
  fire_b    = ... && zw_accrue && (orph_zw_cnt[scan_id] >= ORPHAN_ZW_LIM) && !orph_busy
end
```
- `orph_zw_cnt` 16×8 位饱和，**独立 `zw_tick`**（`ORPHAN_ZW_TICK_BITS=20`，1.718 s/tick；`ORPHAN_ZW_LIM=105` ⇒ 180.39 s；8 位饱和 438.1 s）；`ack_obs` 逐拍清零（清零优先于计数，见附录 B）。**名称映射：本节 `zw_accrue/zw_tick/fire_b` = 附录 B 的 `accrueB/orph_zw_tick/fireB`（同一量）。**
- **N2**：`ack_obs` 只在 `TCP_TX_OVL` 支置位（`tcp_rx.v:617-626`）⇒ `ORPHAN_ZW_EN` 由 wrapper 的 `ORPHAN_ZW_EN_5` 控制（默认 `ifdef TCP_TX_OVL` 1/0）；非 OVL 门显式 0。**`ORPHAN_ZW_EN=0` 时 `orph_zw_cnt` 完全不动（寄存器被优化掉），不是"仍计数但无火"**（X3 钉死）。
- **嵌套折叠（X3）**：`ORPHAN_EN` 是外层、`ORPHAN_ZW_EN` 是内层 ⇒ **00** 全关（零回归）；**01** 外层关 ⇒ **外层胜出、全关**（等价 00，内层不打开任何逻辑）；**10** Mode A 开 / Mode B 全关（C2a 用此）；**11** 全开（板 / C2b）。`ORPHAN_EN=0` 时一切新输出恒 0、`ev_down_i≡ev_down`。
- **活零窗（socket 未 close）** 对 persist 探询回 win=0 的 ACK ⇒ `ack_obs` ⇒ 不点火；死对端无 ACK ⇒ 180.39 s 后回收。**单次 60 s 档探询/ACK 丢失 ⇒ 120 s 间隔，180.39 s 可容忍（余量 60.39 s）；连续 2 次丢失 = 180 s < 180.39 s（数学覆盖 0.39 s，余量不足、按不覆盖处理）；≥3 次（240 s）必误杀**（v4 修正措辞，残余见 §9-6b）。
- **N2 自评（v4 补；红队查证 v3 0 命中）**：结构性防呆依赖不变量"**`TCP_TX_OVL=1` ⇒ `ack_obs` 置位**"。若将来有人在 `TCP_TX_OVL` 支内加开关/参数**禁用 `ack_obs` 置位**，`ORPHAN_ZW_EN_5` 的默认推导会**静默**给出 1 ⇒ Mode B 打开而 `ack_obs` 恒 0 ⇒ **误杀**。建议在 wrapper 加 `ORPHAN_ZW_EN_5 && ack_obs_available` 结构断言，或在 `tcp_rx` 端口注释里写死该不变量（实施时二选一，登记为构建期硬门）。

**点火动作（v4 顺序 = state=0 先、CAM 清后 + N3/N4/N5）：**
1. **fire 拍**：`st_pend[slot]<=1; st_done[slot]<=1;` + `orph_slot<=slot; orph_state_req<=1; orph_cam_req<=1; orph_state_done<=0; orph_wait_cam<=0; orph_notify_pend<=0; orph_down_r<=0; orphan_cam_clr<=0; orph_cnt/orph_zw_cnt/orph_saw<=0;`。**不写 pool、不发 `o_ev_down`**。
2. **等 state=0 落地（N4）**：`fc_gnt && fc_sel_r==5 && fc_id_r==orph_slot` ⇒ `orph_state_req<=0; **orph_state_done<=1**`（**寄存器**）。**在 `orph_state_done=0` 期间不发 CAM 清**（否则零 CAM 窗口内 `start_data` 仍可启动，`cam_rd_*` 全 0 ⇒ 线上出 0 MAC/IP/port 帧——F9）。
3. **state_done 后**：`orph_cam_req && orph_state_done && !scfg_busy && !abort_comb` ⇒ 发 1 拍 `orphan_cam_clr`（寄存器输出；CAM 写在该拍结束沿落地），清 `orph_cam_req`、置 `orph_wait_cam`；等 clr 回落 ≥1 拍（`cam_clr_done`）⇒ **同沿 `orph_wait_cam<=0; orph_notify_pend<=1;`**（**N3：必须同沿**；先清 wait_cam 下一拍才置 notify_pend ⇒ 中间 1 拍 `orph_busy=0` ⇒ 第二槽乘虚改写 `orph_slot` ⇒ 第一槽半回收）。
4. **两者都已落地** ⇒ `orph_ready = orph_notify_pend`（**v4 定义，N5**）。在投递门开的那一拍 `orph_down_r <= 1`（**寄存器，1 拍脉冲**）并**同沿清 `orph_notify_pend<=0`**；`orph_down_r` 非投递拍默认 0 ⇒ **严格 1 拍高**（不会多拍、不会丢脉冲）。由事件块做 pool/winq/wu/fc/st 清理 + `o_ev_down` + `stat_ev_down++`；`orph_down_r` 高拍 `stat_orphan++`。
5. **中止**：等待期同槽 `ev_up`/`ev_down`/`fin_sent`/`rst_sent` 上升 ⇒ 清全部 pending（含 `orph_state_done/orph_cam_req/orph_state_req/orph_down_r/orph_wait_cam/orph_notify_pend/orphan_cam_clr`），**不发通知**。
   - `abort_comb = (ev_up&&ev_slot==orph_slot) || (ev_down&&ev_slot==orph_slot) || fin_sent[orph_slot] || rst_sent[orph_slot]`（**组合**，F3）。
   - `orph_down_r` 是寄存器 ⇒ `to_push` 的 `!orph_down_r` 项与 `orph_down_r` 的 `!to_push` 项**不构成组合环**（N5）。

### 3.3 阈值（v4：模式 A = F1；模式 B = N1）

**模式 A（非零窗，v2 修正 F1，v3 不变）**
- `ORPHAN_TICK_BITS = 18`：`scan_round[17:0]==0` 每 **262,144 轮** = **429.4967 ms**（262,144 × 1.6384 µs）。
- `ORPHAN_LIM = 8'd144` ⇒ **61.8475 s**；8 位饱和 **255 × 429.4967 ms = 109.5217 s**。
- 依据：61.85 s ≫ RTO 20 ms（`RTO_LIM=12207`，`tcp_tx_frame.v:219-223`；≈3092×）；≫ app FIN 超时 400 ms（`FIN_TO_LIM=244141`，`app_ctrl.v:315-319`；≈155×）；≫ HLS 释放周期 2.56 s（≈24×）；> 慢盆 20 ms 簇；< Linux `tcp_retries2` ~13 min。
- **v1 错误**：`144 × 419.43 µs = 60.398 ms`（不是 s）；`255 × = 106.95 ms`。v2 用 18 位 tick 修正到分钟级。

**模式 B（零窗，N1 修正）**
- `ORPHAN_ZW_TICK_BITS = 20`：`scan_round[19:0]==0` 每 **1,048,576 轮** = **1.7180 s**（1,048,576 × 1.6384 µs）。
- `ORPHAN_ZW_LIM = 8'd105` ⇒ **180.39 s**；8 位饱和 **255 × 1.7180 s = 438.1 s**。
- **persist 60 s 封顶的算术**：`ps_reload` = 20 ms→5→10→20→40→**60→60… s**（`tcp_tx_frame.v:407-419`；`PS_MAX` `:299-301`）⇒ 稳态 ACK 间隔 60 s；**任意一次探询/ACK 丢失 ⇒ 120 s**；180.39 s 可容忍 **1 次**（余量 60.39 s）。
- **连续 2 次丢失（v4 修正符号/表述）**：间隔 = 3×60 = **180 s**；`180 < 180.39` ⇒ **数学上覆盖 0.39 s**。该 0.39 s 余量对 ACK 延迟/抖动敏感（内核 delayed ACK ≤40 ms + 调度卡顿即可吃掉）⇒ **按"不覆盖"处理**（不是"180 > 180.39"）。**≥3 次丢失（240 s）⇒ 必误杀**。
- **活零窗对端（v4 限定）**：仅指 **socket 未 close** 的活对端（内核会 ACK persist 探询）；**app 已 close ⇒ 内核回 RST，不是 ACK** ⇒ `ack_obs` 不脉冲、Mode B 在 180.39 s 回收 —— 这是**正确回收**（会话确实死了），不是误杀；HLS 的 RST 扫描兜底（`layer_tcp.cpp:631-641`）同向。
- v2 的"61.85 s 内所有 ACK 都丢"措辞作废（严重低估）；v3/v4 的残余 = "**单次丢失可容忍**；**2 次丢失数学覆盖 0.39 s、按不覆盖处理**；**≥3 次必误杀**"。

**可配置（v4 钉死默认值与嵌套语义）**
- `app_ctrl`：`ORPHAN_EN`（**默认 0**）、`ORPHAN_LIM[7:0]`（144）、`ORPHAN_TICK_BITS`（18，≥1）、`ORPHAN_ZW_EN`（**默认 0；仅 `ORPHAN_EN=1` 时有效**）、`ORPHAN_ZW_LIM[7:0]`（105）、`ORPHAN_ZW_TICK_BITS`（20，≥1）。
- wrapper：`ORPHAN_EN_5`（默认 1；p5wrapper 显式 0）、`ORPHAN_LIM_5`（144）、`ORPHAN_TICK_BITS_5`（18）、`ORPHAN_ZW_EN_5`（默认由 `` `ifdef TCP_TX_OVL `` 推出：OVL=1/非 OVL=0；p5wrapper 显式 0）、`ORPHAN_ZW_LIM_5`（105）、`ORPHAN_ZW_TICK_BITS_5`（20）。
- TB：`ORPHAN_LIM=2`、`ORPHAN_TICK_BITS=1`（tick 每 2 轮 ≈3.2768 µs；LIM=2 ⇒ 6.55 µs）；`ORPHAN_ZW_LIM=2`、`ORPHAN_ZW_TICK_BITS=1`（Mode B 同量级）。**活动臂必须显式 `ORPHAN_EN=1`（U11/U12 另 `ORPHAN_ZW_EN=1`）；U10/U10' 用 0**（§6.1）。
- **嵌套折叠（X3）**：外层 `ORPHAN_EN`、内层 `ORPHAN_ZW_EN`。**00** 全关 = 零回归；**01** 外层关 ⇒ 全关（外层胜出，不是"Mode B 单开"）；**10** Mode A 开 / Mode B 全关（`orph_zw_cnt` 不计数、不清零、不点火，寄存器折叠掉）；**11** 全开。⚠️ 不存在"只开 Mode B"的组合（00/01/10/11 中 01 与 00 等价）。
- **不做运行时寄存器**：板 app 总线静态钉死（`wrapper_p4.v:1345-1347`，N14 对账见上）；调阈值 = 一次构建（#64）。

### 3.4 计数器成本（v4）

| 项 | 位宽×份数 | FF |
|---|---|---|
| `orph_cnt[0:15]`（模式 A） | 8×16 | 128 |
| `orph_zw_cnt[0:15]`（模式 B） | 8×16 | 128 |
| `orph_saw[0:15]` | 1×16 | 16 |
| FSM（act/cam_req/state_req/state_done/slot/clr/wait_cam/notify_pend/orph_down_r/abort） | ~15 | ~22 |
| `stat_orphan` | 32 | 32 |
| 合计 | | **≈326–330 FF** |

`ORPHAN_EN=0` ⇒ 全部折叠；`ORPHAN_EN=1 && ORPHAN_ZW_EN=0` ⇒ **Mode B 的 128 FF 一并折叠**（`orph_zw_cnt` 不计数、不清零、不点火，X3/V4-2）。参数常量化，与 `PERSIST_EN` 同款零回归手法。**关键纪律**：`orph_down_r`/`orphan_cam_clr` 显式与 `ORPHAN_EN` 相与，保证 `ORPHAN_EN=0` 时 `ev_down_i ≡ ev_down`、`ev_slot_i ≡ ev_slot`；否则既有 8–9 个直接例化 `app_ctrl` 的 TB 未接新输入（Z）时 Z 可经 `ev_down_i` 传播。
**N5**：`orph_down_r` 是寄存器；`to_push` 的 `!orph_down_r` 与 `orph_down_r` 的 `!to_push` 不构成组合环。
**N3**：`orph_busy` 只串行化 FSM，不丢计数（第二槽的 8 位计数饱和保留）。

### 3.5 回收动作清单（v4）

| # | 动作 | 实现 | 备注 |
|---|---|---|---|
| 1 | **TCB[slot].state = 0** | `st_pend[slot]<=1; st_done[slot]<=1`，走既有 `fc` 通道（`fc_sel_r=5`, `val=0`；`app_ctrl.v:701-726,1311-1336`） | fc 是 TCB 第 4 级仲裁（最低）；**v2 加组合门**（F2，作用域见 §3.6）；fc gnt 时置 `orph_state_done`（N4） |
| 2 | **CAM[slot] 清零** | `orphan_cam_clr` 脉冲 + slot；wrapper mux（scfg 优先）；**issue 门 = `orph_cam_req && orph_state_done && !scfg_busy && !abort_comb`**（F3+N4） | **state=0 已落地（`orph_state_done=1`）后**才发（F9）；只清该槽五字段（`tcp_cam.v:49-55`） |
| 3 | **tcp_tx_frame 重传状态** | 不新增端口：下一次扫描（≤1.6384 µs 名义）看到 `rb_state != ESTAB` ⇒ 清 `fin_sent_r/rst_sent_r/fin_retx_pend/rto_pend/rto_timer`（`tcp_tx_frame.v:1240-1259`）；`ring_start/replay_jump/ring_restore` 全要求 `scan_estab`（`:783-795,1198-1236`）⇒ 不再起新重放帧，当前会话在 ≤1 帧内排空 | `whi_r` 不清（`:1186-1187` 回绕安全上界；下一次 `cfg_up` 清，`:1103`） |
| 4 | **app_ctrl 租约/流控清理** | `orph_down_r`（寄存器）并入 `ev_down_i` ⇒ 复用现有 ev_down 块：归还 `pool`、`winq=0`、清 `wu_*/fc_pend/st_pend/to_*/fin_req/rst_req`、`o_ev_down`、`stat_ev_down++`（`app_ctrl.v:973-1054`） | **`st_done` 不被 ev_down 清**（`:1014` 只在 ev_up 清）⇒ 回收后保留到下一次 ev_up（防止重复点火）；F8 |
| 5 | **app 收尾** | `app_pattern` 现有 `closing`→W3 收尾→`active=0`（`app_pattern.v:896-940`） | 单会话被释放后，`up_pend_r`（别的槽的 ev_up）才能被应用 |
| 6 | **槽复用** | 1+2+4 完成后即可；新 ADD 全量覆盖 + `cfg_up` 清 per-slot TX 状态（`tcp_tx_frame.v:1101-1128`） | 与 C1 偷槽/D1 同槽重连完全同路径 |
| 7 | **发不发 RST** | **不发**（§3.8） | 见论证 |
| 8 | **ack_seen_w[slot]** | 不清（下一次 `scfg_ev_up` 清，`wrapper_p4.v:2160-2166`） | 若槽长期不复用，该位悬空无消费者 |
| 9 | **retx_ram ring 内容** | 不清（新 `cfg_up` 清 `whi_r`；ring_hi 回绕安全上界挡住伪重放） | 残余登记 §9-8 |
| 10 | **HLS** | **零改动** | 见 Q1 |

### 3.6 竞态/时序论证（v4，含 F2/F3/F8/F9/N3/N4/N5）

**ADD（同槽新连接）——四道防线（v3）：**
1. **CAM 清 issue 门**：`orph_cam_req && orph_state_done && !scfg_busy && !abort_comb`（N4 加 `orph_state_done`；`st_pend` 在 fc gnt 沿已清，`app_ctrl.v:1323`，不能当判据）。`scfg_busy` 覆盖 `S_CAM/S_TCB/S_TCB_LAST` 与 FIFO 非空、`wcnt!=0`（F16）。**光有 busy 不够**：ev_up 拍 state=S_RECV、busy=0，而 ADD 的 CAM 写已在此前完成 ⇒ 必须加 `abort_comb` 的 **组合** ev_up/ev_down 门（F3）。
2. **state=0 的 fc 组合门**（F2；**作用域 = `ORPHAN_EN` 内**，F13）：`fc_upd_wr = fc_v && (!ORPHAN_EN || (!(ev_up && ev_slot==fc_id_r) && !(ev_down && ev_slot==fc_id_r)))`。`ev_up` 是 wscale 写**后一拍**的寄存器输出（`slow_cfg_adp.v:187-197`），该拍 `scfg_upd_wr=0`、`sel_fc` 可开（`wrapper_p4.v:2060-2061`）⇒ 没有这个门，fc state=0 会落在 ADD 最后一拍之后（新连接静默死）。加门后：同拍 fc 不落地，事件块清 `st_pend`/`fc_v`，请求撤销。
   - **作用域选择（F2/F13 二选一，选 (a)）**：门放进 `ORPHAN_EN` ⇒ `ORPHAN_EN=0` 时门旁路 ⇒ U10' 逐位成立；板构建（ORPHAN_EN=1）有既存路径修复。既有的 FIN-timeout/abort 同族竞态只在孤儿构建被修（登记，见 §9-4）。
3. **`ev_up`/`ev_down` 同槽中止**：FSM 的 `abort_comb` 是组合的（含 ev_up/ev_down/fin_sent/rst_sent），同时关掉 CAM 清与（经 2 的）fc 写；寄存器的 pending 清位是第二道。
4. **优先级**：scfg（ADD/DEL）在 TCB 仲裁中永远高于 fc；`ev_up` 拍 scfg 的 wscale 写已落地，下一拍 fc 被门挡。
5. **N3 串行化**：`fire_a/fire_b` 的 `!orph_busy` 保证第二槽不会覆盖第一槽的 `orph_slot`/pending；第二槽计数饱和保留，第一槽完成后下一扫描再点火。

**DEL（同槽拆除）**：`scfg_busy` 在整条记录期间为高 ⇒ CAM 清被挡；`ev_down` 到达 ⇒ 中止 FSM（DEL 自己会通知 app）。重复的 state=0/CAM 清即使发生也无害（幂等）。

**Replay 会话进行中**：state=0 落地后 `scan_estab=0` ⇒ `ring_start/replay_jump/ring_restore` 全 0；`ring_eval` 排空支（`tcp_tx_frame.v:1222-1236`）在 ≤1 拍收尾；已进 TX 引擎的 1 帧照常发完。`rto_pend` 在下一扫描被 `!scan_estab` 清（`:1245-1246`）。**重放帧自身会推进 `snd_nxt`**（`upd_wr_data` 在 RX_FIN，`:634,648,1200-1213,1383-1385`），所以 `replay_full` 不会因 app 停帧而自持（F5）。

**fc 饿死**：TCB 更新口每拍最多 1 写；tx 数据写每帧 1 次（~193 拍 1 次）、rx 每帧几次、cfg 每条记录 8 次，fc 是第 4 级，仍有大量空拍。`fc_sel5` 是 round-robin（`app_ctrl.v:701-726`），同槽最多 16 个 gnt 内被选中。**不设超时**（残余风险 §9-4）。**v2 顺序**：state=0 先落，CAM 清后发 ⇒ 即使 fc 被压住，也不会出现"CAM 已清、state 仍 ESTAB 且 `start_data` 可启动"的零 CAM 帧窗口（F9）。

**通知顺序（v4）**：`orph_wait_cam` 在 CAM 清脉冲回落（写入沿已过）后**同沿**清 0 并置 `orph_notify_pend<=1`（`cam_clr_done` 交接，N3）；**`orph_ready = orph_notify_pend`**（v4 定义）。`orph_down_r` 只在 **`orph_state_done=1` + notify_pend=1** 且投递门开的那一拍置 1（寄存器，1 拍脉冲），**同沿清 `orph_notify_pend<=0`**；非投递拍 `orph_down_r` 默认 0 ⇒ 严格 1 拍。投递门：`orph_ready && !ev_up && !ev_down && !to_push && !ev1_v && !to_pushed_r`（F8：补 `!to_pushed_r`，防止 `to_push` 下一拍与 orphan 连续两拍 `o_ev_down`）。
- **N5 无环**：`to_push` 的 `!orph_down_r` 与 `orph_down_r` 的门里的 `!to_push` 都是**寄存器项**（`orph_down_r` 是寄存器）⇒ 组合环不存在。
- **N4**：`orph_state_done` 也是寄存器（fc gnt 时置 1，fire/abort 清 0）；C3 断言用它，不用 `st_pend`（`st_pend` 在 gnt 沿已清，`app_ctrl.v:1323`）。

**ev_down_i 的 use-point 清单（实施时 grep 穷举，漏一处 = 配错/毒化；N8）**：
- 必须改成 `_i`/`ev_slot_i`：事件块（`:973-1054`）、`ev_blk`（`:836`）、`ev1_v/ev1_slot`（`:926-927`）、`hit_b/hit_c`（`:837-839`）、`to_push` 门（`:698-699`，加 `!orph_down_r`）、**`ret_slot_q/pool_ret_x`（`:880-883`）**（F8）。
- **保持原始**：`ev_push`（`:437`）、**`stat_ev_drop` 条件（`:974`）**、**`ev_ovf`（`:1376`）**。⚠️ N8：v2 把 `stat_ev_drop` 写成 `:1376`（那是 `ev_ovf`）；两处都列出。

### 3.7 观测字 W75（v4，F4/F15）

- 新增 **1 个字 W75 = `app_ctrl.stat_orphan`**（32 位，提交回收计数），落 **`0x14C`**，进 `p7bdp` 束（槽 35）。
- 几何：`SNAP_P7BDP_NW 35→36`、`SNAP_NW_P6E 75→76`；**MIR 四寄存器自动下移**：MIR_STATUS=**0x150**、DATA=**0x154**、CTRL=**0x158**、DMA_CNT=**0x15C**；**UNIMPL=0x160**（`axi_regs.v:206,214-218`：`SNAP_LAST_IDX = 8 + SNAP_NW - 1`，MIR 由它 +1..+4 推导）。**不要写死 MIR 地址，也不要再把 0x15C 当空洞**（F4）。
- 读侧：`_proj_pcie/p6e_snap_check.sh` 的 `WLABEL`、`apply_readside.py`、`P7B_BIZ_WINDOW.md` §1、一切 `NW=`/`UNIMPL_ADDR=`/`EXPECT_BID=` 的读者——实施时**重新穷举**（0x28 轮是 63 处/20 文件；不要照抄）。
- **WNS 宿主（F15）**：0x28 全局 WNS = +0.065 ns（1.02%），宿主 = `user_reset_reg → snap_words_r_reg[...]/CLR` 的异步复位 Recovery 族；每字 ≈ **96 FF**，分布 = **+32 宿主网（`snap_words_r`）+32 `dout_a`（pcie，另一族）+32 `hold_b`（DP）**。**只有 32 落在被点名的宿主网**；v1 的"96 FF 全落宿主族"是不精确的（F15）。
  - 推荐：**先按 +1 字做一次构建**；若三类失败端点非 0 或 WNS 转负 ⇒ **第一刀砍 W75**（纯观测，功能修复不受影响），板级改用 `W55/W68/W71..W74` + pcap。
  - 不推荐：把 `stat_orphan` 塞进现有字（改既有字语义 = 违反"旧字逐项未动"）。

### 3.8 是否对端发 RST（v1 结论不变）

**推荐不发**：对端按定义不 ACK/不推进；state=0 + CAM 清后迟到数据被静默丢弃，RST 不改变这一点；`rst_push` 要求 `rb_state==1`（`tcp_tx_frame.v:980`）⇒ 要发 RST 必须"先 RST 后 state=0"，需要 `rst_sent`/`st_grace` 宽限（`app_ctrl.v:864-874`），复杂度/时序都增加，且与 Q3 的迟到 RST 纠缠。后备：若板级发现对端 socket 长期悬挂有实际危害，可把 `rst_req[slot]` 在 fire 时置 1，单独一轮 + 单独 A/B。

---

## 4 Q3：迟到 RST 误杀新连接（v4）

### 4.1 现状

- RST 扫描**不要求 `state != T_FREE`**，只比 `peer_ip/peer_port`（`layer_tcp.cpp:631-641`，注释逐字"含重传超限已释放槽"）⇒ 静默释放后残留 peer 字段仍能命中。
- 槽被新连接（同 4 元组）复用时，迟到的旧 RST 会命中，`cfg DEL` ⇒ `ev_down` ⇒ 新连接被拆；不同 4 元组则不匹配（安全）。

### 4.2 为什么不同批

1. 本修复不产生 RST（§3.8）⇒ 不新增该向量。
2. 该向量与本修复无关地存在：HLS 槽在静默释放（~2.56 s）时就已空出、可复用；快路径回收没有改变 HLS 槽复用率。
3. 可信修法需要快路径的 seq 窗口：HLS 的 `peer_seq` 停在 SYN+1（第三 ACK 与数据都不进 HLS），`seq==peer_seq` 会拒掉合法 RST、破坏现有兜底。
4. 同批会扩到 HLS + 重综合。

### 4.3 风险登记（F7 可观测路径）

- **窗口**：同一 4 元组在静默释放后复用时，旧 RST 到达。
- **后果**：新连接被拆（app 收 `ev_down`，可重连；不是静默错误）。
- **可观测**：**pcap**（"新连接建立后立刻收到一个 seq 属于旧空间的 RST"）+ **app closing/重连**。⛔ `Δstat_ev_down` **板上不可读**（`wrapper_p4.v:1321-1322` 空接；`:1346-1348` app 总线静态钉死；快照无此字），v1 的这条判据删除。
- **概率**：需要同源端口+同目的端口复用 + 旧 RST 迟到；工程上低，但不可忽略。

### 4.4 后续候选（不在本批）

- **候选 1（推荐后续做）**：快路径在 `cfg ADD` 时把 `rcv_nxt` 通过一个新读口暴露给 HLS，HLS 的 RST 扫描加 RFC 5961 窗口检查（`seq ∈ [rcv_nxt, rcv_nxt+rcv_wnd]`）。需要 HLS 端口/记录改动，单独一轮。
- **候选 2**：HLS 侧记录"本槽曾被静默释放"并在复用时要求 RST 的 seq 与新连接的 `peer_seq` 同侧；信息不足，不推荐。
- **候选 3**：本修复之后 RST 不再是清残留 TCB 的唯一兜底 ⇒ 可更激进地忽略未在窗口内的 RST；这正是把 Q3 放到 Q1/Q2 之后的价值。

---

## 5 改动面清单（v4，逐文件/逐块）

| 文件 / 块 | 类型 | 改动 | 需 HLS 重综合？ |
|---|---|---|---|
| `hls/src/layer_tcp.cpp` | HLS | **不动**（Q1 结论 A） | **否** |
| `rtl/app_ctrl.v` | DP RTL | 参数 `ORPHAN_EN/ORPHAN_LIM/ORPHAN_TICK_BITS/ORPHAN_ZW_EN/ORPHAN_ZW_LIM/ORPHAN_ZW_TICK_BITS`；输入 `retx_active/retx_id/una_adv/una_adv_id/ack_obs/ack_obs_id/scfg_busy`；输出 `orphan_cam_clr/orphan_cam_slot/stat_orphan`；`orph_cnt`/`orph_zw_cnt` 各 16×8、`orph_saw` 16；回收 FSM + **`orph_state_done`（N4）+ `orph_busy`（N3）+ `orph_down_r` 寄存器（N5）**；**`fc_upd_wr` 组合门放在 `ORPHAN_EN` 内（F2/F13）**；`orph_down_r` 并入 `ev_down_i`（含 `ret_slot_q` 的 use-point，F8）；CAM 清 issue 门含 `orph_state_done`（F3/N4）；**Mode B 全块包 `if (ORPHAN_ZW_EN)`（V4-2）；`orph_zw_cnt` 计数用 clr 优先（V4-3）**；`0xA0` 读回 `stat_orphan`（可选） | 否 |
| `rtl/slow_cfg_adp.v` | RTL | 只新增 `output wire o_busy = (state != S_RECV) || !f_empty || (wcnt != 3'd0);`（无输入/行为改动；F16） | 否 |
| `rtl/tcp_tx_frame.v` | RTL | **不动**（`o_retx_active/o_retx_id` 已是现成输出；state=0 后由现有扫描清状态） | 否 |
| `rtl/tcp_rx.v` | RTL | **不动**（`ack_obs/ack_obs_id` 与 `rx_upd_*` 都是现成输出；⚠️ `ack_obs` **只在 `TCP_TX_OVL` 支置位**，`else` 恒 0，N2） | 否 |
| `rtl/tcb.v` / `rtl/tcp_cam.v` | RTL | **不动**（state=0 走现有 upd 口；CAM 清走现有 cfg 口，wrapper 做 mux） | 否 |
| `rtl/app_pattern.v` | RTL | **不动**（现有 ev_down→closing→W3 收尾） | 否 |
| `board/wrapper_p4.v` | RTL | ① **前置声明** `rx_upd_wr/id/sel`、`rx_upd_gnt`、`rx_ack_obs/id`、`tx_retx_active`、`tx_retx_id_o`、`scfg_busy`、`orphan_cam_*` **到 `u_app_ctrl` 之前**（现声明在 `:1761/:1782-1784/:1829-1830/:2052/:2132`，晚于 `:1279` 的例化——**不前置就是隐式 1 位网静默截断**，坑 #24）；② `una_adv = rx_upd_gnt && (rx_upd_sel==3'd2)`；③ `u_app_ctrl` 加新端口 + **`ORPHAN_EN_5`（默认 1；p5wrapper 传 0，N12）/`ORPHAN_LIM_5`/`ORPHAN_TICK_BITS_5`/`ORPHAN_ZW_EN_5`（默认由 `ifdef TCP_TX_OVL` 推，N2/N10）/`ORPHAN_ZW_LIM_5`/`ORPHAN_ZW_TICK_BITS_5`**；**N2 自评的防呆**：加结构断言 `ORPHAN_ZW_EN_5 && ack_obs_available`（或在 `tcp_rx` 端口注释写死不变量"`TCP_TX_OVL=1 ⇒ ack_obs` 置位"）；将来 OVL 内禁用 ack_obs 置位 ⇒ 默认推导静默失效 ⇒ 误杀（V4-2）；④ CAM 写 mux（scfg 优先）；⑤ W75 装配 + `SNAP_P7BDP_NW 35→36` + `SNAP_NW_P6E 75→76`（MIR 自动下移，UNIMPL=0x160）；⑥ **`.PERSIST_EN(1'b1)` 还原** + **`BUILD_ID_V` bump 到 `0x2A`** | 否 |
| 快照读侧（`_proj_pcie/p6e_snap_check.sh`、`apply_readside.py`、`P7B_BIZ_WINDOW.md`、`check_window.py`、`tb_biz_win.v`、`tb_p6e_pcie_wrapper.v`、一切 NW/UNIMPL/EXPECT_BID 读者） | 工具/文档 | 同步到 NW=76 / BID=0x2A / W75=0x14C / **UNIMPL=0x160** / MIR=0x150..0x15C；**不要写死 MIR**（F4 补三件点名） | 否 |
| `tb/tb_app_orphan.v`（新）+ 门 bat（新） | TB | 单元门：判据/阈值/竞态/变异 + **ORPHAN_EN=0 同激励全输出对比臂**（F13，锚 = 当前 HEAD app_ctrl 快照，N11） | 否 |
| `tb/tb_p5_wrapper.v`（或新 wrapper 门） | TB | 全链门：真 app_ctrl+tcb+cam+app_pattern；**基线臂显式 `ORPHAN_EN_5=0/ORPHAN_ZW_EN_5=0` 保旧基线（N12）**；**孤儿臂 A = `ORPHAN_EN_5=1 + ORPHAN_ZW_EN_5=0` 覆盖 C1/C2a/C3/C4（X6，逐条点名见 §6.2）** | 否 |
| **新 OVL 全链臂**（定义 `TCP_TX_OVL`） | TB | **Mode B 真路径门（N2/N7）**：`ORPHAN_EN_5=1 + ORPHAN_ZW_EN_5=1`；`ack_obs` 用**真纯 ACK 帧注入**（不用 force，X7）；活零窗 + 真 ACK 不点火 / 死零窗点火 | 否 |
| `sim/p4gates/run_matrix_p4dfix.bat` | 矩阵 | 新门入册（19→20）；**纠正**：`p5wrapper_src.f:39-43` 已含 app_ctrl/app_pattern/wrapper_p4（F12）；真盲区 = 板宏配置，新门仍要断言被改文件在编译清单 | 否 |

**不需要改的**：`rtl/mac_tx_10g.v`、`rtl/mac_rx_10g.v`、`rtl/persist` 相关、`rtl/fifo_*`、任何 HLS IP 网表。

---

## 6 判据（三层）+ 变异有牙（v4）

### 6.1 单元门（xsim，新 `tb/tb_app_orphan.v`）

**TB 量纲（N6 钉死）**：`ORPHAN_LIM=2`、`ORPHAN_TICK_BITS=1`（模式 A：1 tick = 2 轮 = 3.2768 µs；LIM=2 ⇒ **6.55 µs**）；`ORPHAN_ZW_LIM=2`、`ORPHAN_ZW_TICK_BITS=1`（模式 B 同量级）。表中所有"tick"按此单位；不再写"4096 轮/1000 轮/5 s/12207 visits"。
**TB 使能（v4 补，N6 必修）**：**活动单元臂（U1–U9、U11、U12）的 `app_ctrl` 以 `ORPHAN_EN=1` 例化；U11/U12 另加 `ORPHAN_ZW_EN=1`；U10/U10' 以 `ORPHAN_EN=0`（U10' 同时 `ORPHAN_ZW_EN=0`）例化**。⚠️ 不写 = app_ctrl 默认 0 ⇒ 活动门全部空判（U1 期望 0 通过、U11 期望 1 失败、U12 空转、M1–M12 全不红）——红队 §6 必修，v3 正是漏了这一行。

| 判据 | 激励（tick 单位） | 期望 | 判别力 |
|---|---|---|---|
| U1 健康推进 | `snd_una` 每 **`max(1,LIM/2)` ticks** +1（LIM=2 ⇒ 每 tick），跑 **4×LIM ticks**；每个进度间隔内制造一次**窗满** + 一次 `retx_active` | `stat_orphan=0`；**M1（LIM=0）⇒ 点火 ⇒ 红** | 基础 + M1 牙 |
| U2 孤儿（模式 A） | ESTAB、`snd_wnd=0xF000`、`snd_nxt=snd_una+0xF000`、`snd_una` 冻结；每 **`max(1,LIM/2)` ticks** 一次 `retx_active`（回卷期间 `snd_nxt==snd_una`） | **恰 1 次 `fc sel=5 val=0` → `orph_state_done=1` → 才 1 个 CAM 清脉冲**（顺序断言）、恰 1 个 `o_ev_down`、`stat_orphan=1` | **主判据** |
| U3 persist 零窗（模式 A 负对照） | `snd_wnd=0`、`snd_nxt!=snd_una` 冻结，跑 **4×LIM ticks**；**注入一次 `retx_active`** | 0 次模式 A 点火；**M2（删 snd_wnd!=0）⇒ 点火 ⇒ 红** | 负对照 + M2 牙 |
| U4 慢盆 | `snd_una` 每 **`max(1,LIM/2)` ticks** +1（<LIM），跑 **4×LIM ticks**；U4b "小在飞冻结、无重传"（saw=0，保持 **2×LIM ticks**）；U4c "先有一次重传（saw=1）再小在飞冻结、无活动重传"（`inflight<cap`，保持 **2×LIM ticks**） | 0 次点火 | **负对照** |
| U5 回卷重放 | `retx_active=1` 且 `snd_nxt==snd_una` 持续 **`LIM/2` ticks**，再回到正常 | 计数不清零、按时点火 | 防"回卷清计数" |
| U5b 活动 retx 支 | `inflight<cap`、saw=1、每 **`max(1,LIM/2)` ticks** 一次 `retx_active`（每次 1–2 ticks） | 在 LIM 后 ≤N 次会话内点火（概率性；记录实际命中次数） | F5 口径 |
| U6 ADD 竞态（pre/post） | **pre-fire**：`cnt=LIM-1` 时同槽 `ev_up`；**post-fire**：fire 后 1–2 拍同槽 `ev_up`（带 saw+win_closed 见证） | 中止：无 `o_ev_down`、无 CAM 清、`st_pend` 被清；**删 abort_comb ⇒ 红** | F3 牙 |
| **U6b 双槽同时达限（N3）** | 两个 cid 在**相邻扫描拍**都达 LIM（各自 saw+win_closed）；**另加交接拍臂（v4）**：让第一槽**恰好停在 `cam_clr_done`（`wait_cam→notify_pend` 同沿交接）那一拍**时第二槽达 LIM | 两槽**最终都完成**回收（各 1 次 state=0 + 1 个 CAM 清 + 1 个 `o_ev_down`，`stat_orphan=2`）；无"state=0 已落但 CAM 残留/winq 不还"的半回收；**删 `!orph_busy` ⇒ 第一槽半回收 ⇒ 红**；**把交接拆成两拍（先清 wait_cam、下一拍才置 notify_pend）⇒ 交接拍 `orph_busy=0` ⇒ 第二槽改写 `orph_slot` ⇒ 第一槽半回收 ⇒ 红（v4 牙）** | N3 牙 |
| **U6c state-gnt→CAM 清窗口（N4/F9）** | fire 后等 state gnt；然后 `scfg_busy` 保持 N ticks | `orph_state_done=1` 前无 CAM 清；busy 期间无 CAM 清；释放后恰 1 个 CAM 清；**把 issue 门里的 state_done 删掉 ⇒ 红**（或 C3 ③ 空判） | N4/F9 牙 |
| U7 通知顺序 | 点火后 `scfg_busy` 保持 20 拍，state gnt 后 CAM 清延迟 | `o_ev_down` 严格晚于 `orph_state_done` **和** CAM 清回落；无重复脉冲；**删 state-first 顺序 ⇒ 红**（F9） | 语义 |
| U8 DEL 竞态 | 等待期同槽 `ev_down` | 中止，不发第二次通知 | 幂等 |
| U9 饱和 | 孤儿保持 **>255 ZW/A ticks** | 计数饱和、只点火一次 | 回卷 |
| U10 `ORPHAN_EN=0` 冒烟 | 同 U2 激励 | 新输出全 0 | 冒烟（**不是**零回归证据） |
| **U10' 零回归（F13/N11）** | **同一激励**同时跑 **当前 HEAD `app_ctrl.v` 的快照锚**（实施时按 sha256 命名，如 `tb/frozen/app_ctrl_head_<sha8>.v`；**不用**旧的 `app_ctrl_base.v`）+ 新 RTL `ORPHAN_EN=0` | `o_ev_up/o_ev_down/o_ev_slot/stat_ev_up/stat_ev_down/pool/winq/app_tx_ready` **逐拍逐位相同** | **零回归主判据** |
| **U11 模式 B（F6-b，单元臂：`ORPHAN_EN=1`+`ORPHAN_ZW_EN=1`，TB 直接驱动 `ack_obs` 端口模拟 OVL 行为）** | `snd_wnd=0`、`snd_nxt!=snd_una`、**无 `ack_obs`** 跑 **>ORPHAN_ZW_LIM ticks**（TB: 2 ticks） | 点火、`stat_orphan=1` | 闭 F6-b |
| **U12 模式 B 负对照（同一单元臂）** | 同上，但每 **`max(1,ZW_LIM/2)` ticks** 注入一次 `ack_obs` 脉冲（模拟活零窗对端回 persist ACK；TB: 每 tick） | 0 次点火 | 防误杀 + M10 牙 |
| **U12b 模式 B 单次丢失（N1）** | 同上；在 **`2×ZW_LIM` ticks 窗口内只漏 1 次 `ack_obs`**（其余每 tick 注入；模拟一次 60 s 档探询/ACK 丢失） | 0 次点火（180.39 s 容忍 1 次；TB 按 tick 比例缩） | N1 牙 |

### 6.2 全链门（xsim，真 wrapper + 真 app_ctrl/tcb/cam/app_pattern）

- **参数臂（v4 钉死，X6/N12；必须逐条点名）**：全链门 = `tb_p5_wrapper`（APP_MODE，`sim/p5sim/run_tb_p5_wrapper.bat`；`p5wrapper_src.f:39-43` 已含被改文件）。
  - **基线臂（保旧 p5wrapper）**：`ORPHAN_EN_5=1'b0`、`ORPHAN_ZW_EN_5=1'b0` ⇒ **只**证明零回归/旧基线，**不承担任何活动判据**。
  - **孤儿臂 A（Mode A 开 / Mode B 关）**：`ORPHAN_EN_5=1`、`ORPHAN_ZW_EN_5=0`、`ORPHAN_LIM_5=2~4`、`ORPHAN_TICK_BITS_5=1` ⇒ **C1、C2a、C3、C4 全部用这一套**（逐条点名如下）。
  - **孤儿臂 B（全开，仅 C2b）**：`ORPHAN_EN_5=1`、`ORPHAN_ZW_EN_5=1`、`ORPHAN_ZW_LIM_5=2`、`ORPHAN_ZW_TICK_BITS_5=1`。
- **C1**（**孤儿臂 A**）：层次 force 槽 0 为 ESTAB + 窗满 + `snd_una` 冻结 + 周期 `retx_active` ⇒ 期望 `o_ev_down` + `app_pattern.closing` + 后续 `active=0`；再发 `scfg ADD` ⇒ `ev_up` 被应用、`app_pattern` 重新发帧。**app 收尾/新会话应用 = C1（F18）**。
- **C2a**（**孤儿臂 A，`ORPHAN_EN_5=1` + `ORPHAN_ZW_EN_5=0`，X6 必修**）：健康推进 / 零窗 / 慢盆三种 force 模式 ⇒ **Mode A** 无点火；零窗行**只**验证 Mode A 的 `snd_wnd!=0` 排除（Mode B 在本门关闭，N7）。⚠️ **若照 v3 传 0/0，本行是空判（全块关）**。
- **C3**（**孤儿臂 A**）：CAM 仲裁断言：① `!(orphan_cam_clr && scfg_cam_wr)`（busy 门）；② **强制同拍碰撞**（TB force）时 CAM 写入的是 scfg 值（mux 分支，F10）；③ `orphan_cam_clr` 只在 **`orph_state_done=1`** 且 CAM 未清之后出现（**N4**；不用 `st_pend`——gnt 沿已清）。
- **C4**（**孤儿臂 A**）：`scfg_busy` 保持期间 `orphan_cam_clr` 不出现；`wcnt!=0` 也算 busy。
- **C2b（新 OVL 全链臂，孤儿臂 B）**：**定义 `TCP_TX_OVL`**（使 `ack_obs` 真置位），wrapper 传 `ORPHAN_EN_5=1`、`ORPHAN_ZW_EN_5=1`、`ORPHAN_ZW_LIM_5=2`、`ORPHAN_ZW_TICK_BITS_5=1`；测**活零窗 + 周期 ack_obs ⇒ 不点火**、**死零窗（无 ack_obs）⇒ 点火**。这是 Mode B 的唯一真路径门（N2/N7）。
  - **刺激方式（X7 必修）**：`ack_obs` **用真纯 ACK 帧注入** —— 用现有 TB 帧注入设施按该槽 4 元组构造 `flags=ACK`、无载荷的以太帧注入 RX 路径，让 `tcp_rx` **真置位** `ack_obs`；**不用 `force ack_obs`**。活零窗臂 = 周期注入真 ACK；死零窗臂 = 完全不注入。
  - **前置断言**：每次注入后必须观测到 `ack_obs` 真脉冲（防"注入过 ≠ 测到了"）；TB 现有注入设施不足时先补 helper，并把该断言列为 C2b 的**第一条**判据。
- **门面纪律**：新门必须断言"编译文件清单含 `rtl/app_ctrl.v`、`rtl/slow_cfg_adp.v`、`board/wrapper_p4.v`"；**纠正 F12**：p5wrapper 门确实编译这些文件，真盲区是**板宏配置**（`P7B_10G`/`TCP_TX_OVL`/`DP_156MHZ`）——C2b 用 `TCP_TX_OVL` 覆盖其一，其余由构建 + 板级臂覆盖。

### 6.3 板级臂（v4，F11/F14/N1）

**臂序（v3，必须按此，否则慢盆混淆；N9）**：
1. **烧 0x2A**（或先 0x28 负臂）→ 核"盆不在场"（900 Mbps 级二值；`p9_basin_probe §174`）。
2. **快态臂 B3/B5/B5c**（盆不在场才做：B3 9 Gbps 健康快流；B5 零窗 persist 活对端；B5c 零窗单次丢失）。
3. **进盆臂 B4**（真异槽并行 + 小窗 2920；见证 = 爬行 1.55 Mbps / 20 ms 簇 / `W55=49.9/s`；**只有 B4 希望盆在场**）。
4. **重烧**（清盆的唯一手段）→ 核"盆不在场"。
5. **孤儿臂 B1/B2/B5b/B6**（负臂 0x28 与正臂 0x2A 各一次烧；**每次烧后先核盆不在场**）。

| 臂 | 构型 | 主读数 | 期望（新臂 0x2A） | 期望（负臂 0x28） |
|---|---|---|---|---|
| **B1 孤儿复现** | 单连接（8080）持续下行 → 对端黑洞屏蔽该 4 元组（不发 FIN/RST；pcap 确认回收前无 RST）→ 静默 **≥ 2×LIM（≥124 s）** | `ΔW75`、`ΔW55`、pcap 重放帧、`ΔW68` | `ΔW75=1`；`ΔW55` 在回收后**停止**；pcap 重放停止；`ΔW68=0`（单连接、无其它流量） | `ΔW75` 不存在；⛔ **D2 板级实测（2026-10-17）：不回收 + 槽静默卡死**（`W55` DROP 后 ~0.4 s 内 +17/+20 然后 140+ s 冻结；pcap 重放 16 个 20 ms 包、0.407 s 后静默）—— 原"pcap 20 ms 重放不止"期望**不成立**（见文末 v4.2） |
| **B2 回收后新连接** | B1 之后解除黑洞、新客户端建连 | `ΔW71`、`ΔW73/ΔW74`、`ΔW51/52`、逐字节 | ev_up 被应用、图案数据恢复、`mism=0` | 若新连接落同槽（C1 偷槽）也可能恢复 ⇒ 不作主判别 |
| **B3 健康快流** | 9 Gbps 连续下行 > 2×LIM | `ΔW75`、`ΔW68`、`ΔW55` | `ΔW75=0`；`ΔW68` 大；`ΔW55` 低 | 同左 |
| **B4 慢盆爬行** | 进盆配方（真异槽并行 + 小窗 2920）> 2×LIM | `ΔW75`、吞吐、`W55`、盆签名 | `ΔW75=0`，连接不被杀 | 同左 |
| **B5 零窗 persist（socket 未 close 的活对端）** | 对端停读 → 窗 0 → 保持 **≥135 s（v4 修正；≥120 s 不够）** → 恢复读；**记录探询/ACK 计数**。⚠️ persist 累计探询时刻 = **0.02/5.02/15.02/35.02/75.02/135.02/195.02 s**；**60 s 档第一对在 75.02/135.02 s**，120 s 窗只含 75 s（上一间隔 40 s）⇒ 测不到 60 s 档。要覆盖两个 60 s 间隔 ⇒ **≥195 s** | `ΔW75`、persist 探询计数、对端 ACK 计数、恢复后吞吐 | `ΔW75=0`，恢复后照常（活零窗回 ACK） | 同左 |
| **B5c 零窗 persist 单次丢失（N1）** | 同 B5，但**人为丢 1 个 60 s 档探询或其 ACK**（**只能在对端用 iptables 精确丢一帧**；⚠️ "板侧只记录不注入"需改 RTL、板上不可实现，仅可作 TB 臂）；保持 **≥200 s**（覆盖 135/195 s） | `ΔW75`、探询/ACK 计数、恢复后吞吐 | `ΔW75=0`（180.39 s 阈值容忍 1 次 120 s 间隔） | 同左 |
| **B5b 零窗死对端（F6-b）** | 对端先停读（窗 0）→ 再黑洞；保持 **≥ 2×180.39 s ≈ ≥361 s** | `ΔW75`、pcap persist 探询（应约 6 次 60 s 档） | `ΔW75=1`（模式 B）；persist 停止 | `ΔW75` 不存在；persist 永续 |
| **B6 C1 偷槽并存** | 孤儿等待期发新 SYN（< LIM）；**post-fire** 臂：在 LIM+ε 附近连续重试新 SYN | `ΔW75`、新连接功能 | 中止回收（`ΔW75=0`）或新连接存活；app 换流 | 新连接正常 |
| **B7 身份/几何** | 烧 0x2A | `0x04=BID 0x2A`、NW=76、`0x14C`=W75、**MIR 0x150..0x15C**、**`0x160=0xffffffff`**、2 BAR、LnkSta x4 | 全中 | 0x28：NW=75、BID 0x28、UNIMPL=0x15C |

**读数纪律**：`stat_orphan` 32 位 @156.25MHz 回卷 27.5 s ⇒ 差值 mod 2³² 并记原始值；`ΔW55/ΔW68` 同（#55）。每次测量前重烧并核 sha256/BID（#58）。
**B1 变量清单（F14）**：0x2A vs 0x28 的差异 = **orphan fix + W75 + BID**。W75 是纯读侧观测量（不参与任何行为判据），BID 只改身份；**接受 W75 为第二变量并写明**；若要严格单变量，按 §7.5 先砍 W75 再跑 B1（多一次构建）。
**B5/B5c/B5b 的时间预算（v4 修正 B5）**：**B5 ≥135 s**（60 s 档第一对在 75/135 s）、B5c ≥200 s、B5b ≥361 s；B5b 的长时窗是**模式 B 阈值的直接代价**（180.39 s），必须在排期里预留（不是"跑 124/135 s 看不到点火"就判失败）。

### 6.4 变异有牙（v4，F10/F18）

| 变异 | 期望红在哪 |
|---|---|
| M1 `ORPHAN_LIM=0` | **U1**（已补窗满 + retx 见证）点火 ⇒ 红 |
| M2 删 `snd_wnd != 0` | **U3**（已注入一次 retx）点火 ⇒ 红 |
| M3 删 `work` 的 `retx_active` 覆盖 | U5 回卷把计数清零 ⇒ 不点火 ⇒ 红 |
| **M4' 第三因子强制 1**（`win_closed||retx` → `1'b1`） | **U4c**（saw=1、小在飞、无活动 retx）点火 ⇒ 红。⚠️ v1 的"删 win_closed 留 retx"**不可红**，已弃用 |
| M5 删 `abort_comb` | U6（pre/post-fire）与 U6c（state-gnt 窗口）通知杀掉新会话 / 擦 CAM ⇒ 红 |
| M6 删 CAM 清 | **C3**（链级 CAM 内容/仲裁）红；U2 只查脉冲表达，不承担内容判据（F18） |
| M7 通知早于 state gnt | U7 顺序断言红 |
| M8 删 `o_ev_down` | **C1**（app closing/active=0）红；U2 无 app_pattern（F18） |
| M9 删 `!to_pushed_r` 门 | 连续两拍 `o_ev_down` 断言红（F8） |
| M10 删 `ack_obs` 清零 | **C2b/U12（OVL 臂，活零窗）** 点火 ⇒ 红（F6-b/N2；p5wrapper 里 Mode B 关闭，不承担此变异） |
| **M11 删 `orph_state_done` 项（CAM 清 issue 只用 `orph_cam_req`）** | **U6c/C3 ③**：state=0 未落时出现 CAM 清 ⇒ 红（N4/F9） |
| **M12 删 `!orph_busy`** | **U6b（双槽同时达限）**：第一槽半回收 ⇒ 红（N3） |
| **M13 删 `orph_down_r` 的寄存器（改组合）** | 综合/仿真出现 `to_push ↔ orph_down` 环或 `o_ev_down` 多拍/错拍 ⇒ 门红（N5） |

### 6.5 判据边界

- **CAM 清的板级判据是弱环**：CAM 不可读；**权威层 = xsim C3**；板级只证行为（重放停止、app 收尾、槽复用）。
- **B4 慢盆若点火**：不是 PASS/FAIL，而是设计输入（阈值/窗满门需重定）；先登记再改。
- **B5/B5c/B5b 零窗** 必须在 `PERSIST_EN=1` 的构建上跑；0x29（persist 关）上该臂无判别力。
- **B5 的 ≥135 s 是"能测到 60 s 档"的下界，不是"余量已证"**：必须记录探询/ACK 计数（见证 75.02/135.02 s 两次探询），并跑 B5c（单次丢失）才能对 180.39 s 的容错下结论（N1）。⚠️ **120 s 窗结构性测不到 60 s 档**（只含 75 s，上一间隔 40 s）——若照此跑，"未误杀"是**假安全**读数。
- **B5b** 的 ≥361 s 是模式 B 阈值的直接代价；**不许**用 124 s 的短窗判"未点火"。
- **B1 黑洞** 必须确保板上收不到 RST/FIN；用对端 `iptables` 双向 DROP 或 raw 工具，并在 pcap 确认回收前无 RST。
- **W75 若被砍**：B1 主判据退化为 `ΔW55` 停止 + pcap；`stat_orphan` 用 xsim 读数；不许写"无法验证"。
- **F6-a 未闭**：B1/B5b 都不能覆盖 `inflight==0` 空闲死对端；该格写"未测/未闭"（§9-6a）。

---

## 7 成本/风险/排期 + 构建前置（v4）

### 7.1 构建预算

- 0x28 基线：`WNS +0.065`（1.02%）、`WHS +0.010`、三类失败端点 `0/0/0`、资源 77,631 LUT / 75,086 FF / 348 BRAM（`p9_build_0x28/READINGS_BID28.txt`）。
- 0x29（HEAD）：`WNS +0.060`、三类失败端点 `0/0/0`（CLAUDE.md 2026-10-17 块）。
- 本设计增量：app_ctrl ≈ **+330 FF**（模式 A 128 + 模式 B 128 + saw 16 + FSM/state_done/busy/notify_pend/orph_down_r ~22 + stat 32）+ 小组合；slow_cfg_adp 1 根 `o_busy`；wrapper CAM mux ~2 级；W75 ≈ **+96 FF**（**+32 宿主网 / +32 dout_a / +32 DP**，F15）。
- **WNS 宿主**：全局最差 = 快照阵列异步复位族（0x28 已换族）；W75 的 32 FF 落在该宿主网，另 64 在 pcie `dout_a` 与 DP `hold_b`（邻近但不同端点族）。DP setup 是另一对象（0x23 曾 `+0.311`；**不可与全局 WNS 比大小**，#66）。
- **一次构建收口**（同输入重跑位级复现，方差 0）。

### 7.2 HLS 重综合与行为漂移

- **Q1 方案 A ⇒ 零 HLS 改动 ⇒ 无重综合 ⇒ 无 HLS 行为漂移风险。**
- 若选后备 B（`CFG_REL`）：+1 轮 HLS 构建 + csim 锚 + **必须改 `slow_cfg_adp` 的 `is_add/is_del` else 支**（未知 cmd 目前落进 DEL）。排期 +1 天。
- **F13 零回归作用域（v3 钉死 = (a)）**：`fc_upd_wr` 组合门**放进 `ORPHAN_EN` 内**（`fc_upd_wr = fc_v && (!ORPHAN_EN || ...)`）⇒ `ORPHAN_EN=0` 时门旁路，U10' 逐位成立。
  - wrapper 暴露 **`ORPHAN_EN_5`**（默认 1 = 板构建）；**p5wrapper #19 显式传 `1'b0`** ⇒ 保旧基线、**不重基线**（N12）；新"孤儿臂"与 OVL 臂传 1。默认非 APP 构建不例化 app_ctrl。
  - U10' 的冻结锚 = **当前 HEAD `rtl/app_ctrl.v` 的快照**（实施时按 sha256 命名；**不用**旧的 `sim/p5wu_p1p2/app_ctrl_base.v`，N11）。

### 7.3 硬前置（构建第一动作）

1. **`board/wrapper_p4.v:2185`：`.PERSIST_EN(1'b0)` → `1'b1`**。HEAD = 0x29 拆刀幽灵配置（persist 关）；不还原就交付一个"零窗完全静默"的幽灵位流。**阻断级前置。**
2. **`BUILD_ID_V 32'h00000029` → `32'h0000002A`**（`:4377`）。每次构建必 bump（BID 是唯一身份门；位流长度恒 15,431,261 B）。
3. 快照几何：`SNAP_P7BDP_NW 35→36`、`SNAP_NW_P6E 75→76`、W75 @ `0x14C`、**MIR 自动 0x150..0x15C、UNIMPL=0x160**（F4）；读侧同步。
4. 构建**只走** `board/run_build_p7b_ku5p.bat`（`create_project -force` 会清上一轮取证 ⇒ 归档必须在构建脚本内，#54）。
5. 矩阵：19 门 + 新门 = 20 门；**新门必须断言被改文件在编译清单**（p5wrapper_src.f 已含，F12；真盲区是板宏配置）。
6. 烧录前核 `.PERSIST_EN`/BID/W75/UNIMPL 四处现读值。

### 7.4 排期建议（TL 裁定，只给量级）

- 设计审查+红队复评：0.5 天；实施+单元/全链门：1–1.5 天；构建+矩阵+归档：0.5–1 天；板级 B3→B5→B5c→B4→重烧→B1/B2/B5b/B6/B7：**1.5 天**（慢盆进入不可控 + 多次重烧 + B5b 的 ≥361 s 长窗）。**总 ~4 天**（不含审查往返）。
- 板级必须同一会话完成；每次重烧后核 sha256/BID + 盆不在场；模式 A 的 B1/B3/B4 静默时长按 **2×LIM（≥124 s）** 计；**B5 ≥135 s（v4：覆盖 75.02/135.02 s 的 60 s 档；120 s 测不到）**、B5c **≥200 s**、B5b **≥361 s**（N9/N1）。

### 7.5 失败回退顺序（事前准则）

1. **先砍 W75**（纯观测；功能修复 + xsim/`W55/W68` 证据保留）。
2. 若时序仍不够：把 32 位减法/比较拆一级流水（扫描节拍 256 拍，中间大量空闲，流水免费）；**不改** `ORPHAN_LIM`/`ORPHAN_TICK_BITS` 的实际值（#64）。
3. 若仍有功能问题：`ORPHAN_EN=0` 回到零回归网表，保留设计件与门。
- ⛔ 不允许"重跑到过为止"；每档 = 不同输入，按事前准则取值。

---

## 8 威胁清单（供红队，v4）

1. **ADD 竞态**：`scfg_busy` 门 + **组合 abort_comb** + scfg>fc + fc 组合门（F2/F3）。红队要查 `cam_cfg_wr` 的寄存器延迟、ev_up 拍 busy=0 的窗口。
2. **fc 同拍**：`ev_up` 晚一拍（F2）；组合门 `fc_upd_wr` 不得与事件块形成环（ev_up/ev_down 是输入，fc_id_r 是寄存器）。
3. **通知早于落地**：等 state gnt + CAM 清回落 + `!to_pushed_r`（F8/F9）。
4. **replay 竞态**：state=0 与 `retx_active` 同拍/前后拍；`ring_start/replay_jump/ring_restore` 的 `scan_estab`；**重放自身推进 snd_nxt**（F5）。
5. **计数器回卷/饱和**：模式 A/B 各 8 位饱和；`stat_orphan` 32 位 mod 2³²；`scan_round` 模式 A 18 位 tick / 模式 B 20 位 tick。
6. **阈值误伤**：网络分区但活着、对端内核卡死、慢盆末端；模式 A 61.85 s + 窗满/saw；模式 B **180.39 s**（容忍 1 次 60 s 探询/ACK 丢失；**2 次丢失 = 180 s < 180.39 s 只覆盖 0.39 s、按不覆盖处理**；**≥3 次必误杀**）；**活零窗仅限于 socket 未 close**（app close ⇒ RST ⇒ 回收正确）；红队可构造"分区 62 s 后恢复"臂（成本高）。
7. **假阴性**：慢生产者永不填窗且从无 retx（模式 A 不点火，模式 B 也要求 snd_wnd==0）；扫描时间基被 init/事件拉长（安全方向，F17）；`retx_active` 周期采样漏抓（F5：下一会话再判）。
8. **HLS/RTL 语义漂移**：本批为零；后备 B 要审 `CFG_REL` 的解析器 else 支与 FIFO 16 深（`slow_cfg_adp.v:64`）。
9. **app closing 交互**：`ev_down_i` 的 use-point 清单（§3.6）**必须穷举**，尤其 `ret_slot_q/pool_ret_x`（F8）；`orph_down_r` 是**寄存器**（N5），`to_push` 的 `!orph_down_r` 不构成环；投递门含 `!to_pushed_r`（F8）。
10. **观测字成本**：W75 的 32 FF 落在 0x28 宿主网（另 64 在 dout_a/DP，F15）；读侧 NW/UNIMPL/MIR 同步漏一处 = 读到 MIR 寄存器/越界。
11. **池记账**：`ret_slot_q` 用 `ev_down_i`/`ev_slot_i`；`st_done` 不在 ev_down 清（F8）；orphan 的 pool 归还与后续真 ev_down 不 double-return。
12. **`whi_r`/ring 内容**：不清 ⇒ 跨 ADD 伪重放？现有 `ring_hi` 回绕安全上界 + `cfg_up` 清 `whi_r`；红队构造"回收后同槽 ADD 且首帧 seq 小于旧 whi"的臂。
13. **CAM 双条目（④-5）**：本修复只清本槽；别的槽的同 4 元组残留仍在；红队判断是否污染 B1。
14. **迟到 RST（Q3）**：本批不修；B6/post-fire 臂可能引出。
15. **非 APP_MODE 构建**：app_ctrl 不存在 ⇒ 功能缺席；默认构建不受影响。
16. **`o_busy` 组合路径**：slow_cfg_adp.state/FIFO/wcnt → app_ctrl；无环（app_ctrl 只读做门）。
17. **`replay_full` 不自持【已证源码】**：重放帧在 RX_FIN 用 `upd_wr_data` 推进 `snd_nxt`（`tcp_tx_frame.v:634,648,1200-1213,1383-1385`），`ring_delta` 随重放排空；v1 的"自持"说法删除。红队若要证伪，需给出与该源码链相反的读数。
18. **F6-a 未闭**：`inflight==0` 空闲 ESTAB 死对端无法与健康空闲区分；本批不回收（见 §9-6a）；红队不要把它算作本设计的"已闭"。
19. **模式 B 的 `ack_obs` 语义（v3/v4）**：`ack_obs` 是"任一合法 ACK（含零推进/零窗）"（`tcp_rx.v:618-622`），但**只在 `TCP_TX_OVL` 支置位**（`else` 恒 0，`:624-626`；N2）；活零窗（socket 未 close）的 persist ACK 会重置；若对端在 **180.39 s** 内一个 ACK 都不发（即使活着），或**2 次丢失（180 s，余量 0.39 s、按不覆盖处理）/ ≥3 次丢失（240 s，必误杀）**，模式 B 会误杀——登记（N1）。**N2 自评见 §3.2：OVL 内将来禁用 ack_obs 置位 ⇒ 默认推导失效**。
20. **N3 双槽串行**：`!orph_busy` 使两个/三个槽同时达限时串行回收；若第一槽的 fc 被长期压住（§9-4），第二槽的计数饱和等待，**不会半回收**但会延迟；最坏 = 3 槽 ×（fc 等待 + CAM 清）。登记。
21. **N4 `orph_state_done`**：CAM 清必须在 state=0 的 fc gnt 之后；`st_pend` 在 gnt 沿已清（`app_ctrl.v:1323`），不能当判据；C3 ③ 用 `orph_state_done`。
22. **N5 `orph_down_r` 寄存器**：`to_push ↔ orph_down` 的互条件在两处都是寄存器项 ⇒ 无组合环；若实施时误写成组合，综合/时序门必须红。
23. **N1 的 60 s 封顶**：`PS_MAX` 是 persist 的封顶（`tcp_tx_frame.v:299-301,407-419`），不是"平均"；模式 B 的 180.39 s 是按 2×60 s 最坏间隔选的，**不是**按典型 60 s 选的。

---

## 9 未判定/未测清单（v4）

1. 【未测】模式 A 61.85 s 与模式 B **180.39 s** 阈值在真实慢盆/分区/零窗现场是否足够（C1 2.56 s + 慢盆 20 ms + persist 60 s 的读数；无"分区 62 s"臂；无板级零窗单次丢失臂）。**B5 ≥135 s** / B5c ≥200 s / B5b ≥361 s。
2. 【未判定】"窗满"门对慢盆末端的排除是否 100%（慢盆末段的 `snd_wnd`/在飞值未逐连接读）。
3. 【未测】CAM 清的板级直接判据（CAM 不可读；行为 + xsim C3）。
4. 【未判定】fc 状态写的最坏延迟（tx 每帧 1 写、rx/cfg 突发）；无超时，理论可无限等待（实测应 <µs 级）。**F2 组合门后，fc 被 ev_up 同拍挡掉是"取消"而不是"延迟"**；**N3 下第二/第三槽会等第一槽的 fc**（串行最坏 3 槽）。
5. 【未判定】回收发生在 `retx_active` 会话中时，已进 TX 引擎的那 1 帧是否造成对端"半段"（对端已死无影响；误判场景另论）。
6. **F6 两类真漏（v3 分列）**：
   - **6a【未闭】** `inflight==0` 的空闲 ESTAB 死对端：`snd_nxt==snd_una`、无 RTO/无 ACK 期望 ⇒ 与健康空闲不可区分；本批不回收。影响界：只有 HLS 3 个 cid / 快路径 16 槽，且无线上流量；连续 app 下这是瞬态；有限 app 由 FIN/to_fire 收尾；**winq 不会永久蒸发**——同槽 ADD 的 C18 会先归还旧配额（`app_ctrl.v:987-991`：`pool <= pool - g_grant + winq[ev_slot]`），只是占用到下一次 ADD。候选闭法 = app 级 keepalive/`active` 空闲定时器（单独设计，需防误杀合法空闲）。
   - **6b【已闭（模式 B），N1 修正，v4 措辞订正】** `snd_wnd==0` 的死对端：`ack_obs` **180.39 s** 无 ACK ⇒ 回收；**socket 未 close** 的活零窗对端回 persist ACK ⇒ 不误杀。残余：**单次** 60 s 档探询/ACK 丢失 ⇒ 120 s 间隔，180.39 s 可容忍；**2 次丢失 = 180 s < 180.39 s（数学覆盖 0.39 s；余量对 ACK 延迟敏感、按不覆盖处理）**；**≥3 次丢失（240 s）必误杀**；若活对端在 180.39 s 内一个 ACK 都不发，也会误杀（登记）。**app 已 close ⇒ RST 而非 ACK ⇒ Mode B 回收正确，不是误杀。**
7. 【未测】W75 对全局 WNS 的实际增量（+32 宿主/+32 dout_a/+32 DP 的构造估计；一次构建）。
8. 【未测】`retx_ram` 旧内容在"回收→同槽 ADD→重放"中的可见性（本设计不清 ring）。
9. 【未判定】Q3 迟到 RST 的实际发生率（pcap 查 RST seq）。
10. 【未判定】`scfg_busy` 长期为高（HLS 半条记录卡住）：CAM 清/通知等待；`slow_cfg_adp.rst_n = reset_n & hls_rst_n`（`wrapper_p4.v:2083`）在看门狗复位时清掉；"HLS 没卡死、只是记录滞留"未测。实现时加等待周期**观测**（不进动作）。
11. 【已证源码，无需 xsim 臂】**`replay_full` 不自持**（F5）；v1 的 §9-11 xsim 臂删除。若红队坚持，需给反证读数。
12. 【未判定，N2 订正，v4 收紧】**模式 B 的 `ack_obs` 只在 `TCP_TX_OVL` 支置位**（`tcp_rx.v:617-626`；`else` 恒 0）⇒ 板构建可用；非 OVL 的 p5wrapper 必须 `ORPHAN_ZW_EN_5=0`（C2a 用 `ORPHAN_EN_5=1 + ORPHAN_ZW_EN_5=0`），Mode B 的真路径只在 C2b（定义 `TCP_TX_OVL` + **真纯 ACK 帧注入**）验证；板级未单独验。**自评：OVL 内将来禁用 ack_obs 置位 ⇒ 默认推导静默失效 ⇒ 误杀（§3.2 N2 自评）**。
13. 【未判定，N3】**双槽/三槽同时达限**的串行化最坏延迟 = Σ（fc 等待 + CAM 清 + 通知）；`!orph_busy` 保证不半回收，但若第一槽的 fc 长期被压住，第二/三槽会一直等待（计数饱和）。U6b 只覆盖 xsim 的完成性，板级未构造三槽同时黑洞。
14. 【未判定，N1】**模式 B 的 persist 相位**：180.39 s 是按 2×60 s 最坏间隔选的；实际探询/ACK 间隔由 `ps_reload` 的 60 s 封顶决定，板级未独立复测（B5/B5c 会给）。
15. 【未判定，N4/N5】`orph_state_done`/`orph_down_r` 的寄存器时序：源码推演正确，但未跑 xsim 波形；U6c/U7 是实施后的门。

---

## 附录 A 现读行号表（v3 引用）

| 事实 | 位置 |
|---|---|
| `MAX_TCP_CONN=3` | `hls/src/layer_tcp.cpp:10-12` |
| `tcp_find` | `hls/src/layer_tcp.cpp:142-148` |
| cfg 记录布局 | `hls/src/layer_tcp.cpp:163-187` |
| 被动建连 ADD+SYN|ACK | `hls/src/layer_tcp.cpp:668-679` |
| `T_SYN_RCVD` 握手分支 | `hls/src/layer_tcp.cpp:680-684` |
| `T_SYN_RCVD` FIN 分支 | `hls/src/layer_tcp.cpp:696-708` |
| **静默释放（不发 DEL）** | `hls/src/layer_tcp.cpp:531-535` |
| RST 扫描（残留 peer） | `hls/src/layer_tcp.cpp:631-641` |
| HLS 看门狗清槽 | `hls/src/layer_tcp.cpp:498-503` |
| `ev_down` = DEL state=0 gnt | `rtl/slow_cfg_adp.v:158-168` |
| `ev_up` = ADD wscale gnt（**后一拍寄存器输出**） | `rtl/slow_cfg_adp.v:187-197` |
| cfg FIFO 16 深 / `is_add/is_del` else | `rtl/slow_cfg_adp.v:62-68,145-168` |
| TCB 16 槽 / 更新口 | `rtl/tcb.v:8-19,78-105` |
| `win_open` 注册门 | `rtl/tcb.v:151-157` |
| CAM 16 槽 / 写 / 匹配 | `rtl/tcp_cam.v:6-7,49-55,58-69` |
| 纯 ACK ⇒ FAST | `rtl/rx_classify.v:101-107` |
| tcp_rx `ack_adv` / `ack_hi` | `rtl/tcp_rx.v:342-344` |
| tcp_rx TCB 更新口（sel 0/2/4） | `rtl/tcp_rx.v:486-490` |
| tcp_rx `ack_obs` / `ack_obs_id`（**仅 OVL 支置位；else 恒 0**） | `rtl/tcp_rx.v:129-130,617-626` |
| `RTO_LIM=12207` / persist 参数 / `ps_reload` 阶梯 | `rtl/tcp_tx_frame.v:219-223,299-301,407-419` |
| `scan_now` / `scan_tick` | `rtl/tcp_tx_frame.v:536,576` |
| `ps_arm`/`ps_fire` | `rtl/tcp_tx_frame.v:752-757` |
| `cfg_up` 清 per-slot | `rtl/tcp_tx_frame.v:1101-1128` |
| svc/epoch/replay 门 | `rtl/tcp_tx_frame.v:1180-1236` |
| RTO 扫描/persist 段 | `rtl/tcp_tx_frame.v:1239-1296` |
| **重放帧推进 snd_nxt** | `rtl/tcp_tx_frame.v:634,648,1200-1213,1383-1385` |
| 帧首四元组/seq 锁存（OVL） | `rtl/tcp_tx_frame.v:2392-2415` |
| `o_retx_active/o_retx_id` | `rtl/tcp_tx_frame.v:1008-1010,113-114` |
| app_ctrl 扫描节拍/单位 | `rtl/app_ctrl.v:78-88,455-457,545` |
| `FIN_TO_LIM=244141` | `rtl/app_ctrl.v:305-319` |
| `to_fire` / `st_req_now` | `rtl/app_ctrl.v:861-874` |
| **ev_down 不切 st_done** | `rtl/app_ctrl.v:1014`（仅 ev_up）/ `:1047-1052` |
| 事件块 | `rtl/app_ctrl.v:973-1054` |
| `to_push`（含 `!to_pushed_r`） | `rtl/app_ctrl.v:698-699` |
| `st_pend` 在 fc gnt 沿清除 | `rtl/app_ctrl.v:1323` |
| `stat_ev_drop`（保持原始） | `rtl/app_ctrl.v:974` |
| `ev_ovf`（保持原始） | `rtl/app_ctrl.v:1376` |
| C18 winq 归还 | `rtl/app_ctrl.v:987-991` |
| **`ret_slot_q/pool_ret_x`** | `rtl/app_ctrl.v:880-883` |
| 扫描采样 | `rtl/app_ctrl.v:1069-1079` |
| `st_req_now` 落地块 | `rtl/app_ctrl.v:1156-1177` |
| fc 选择/请求寄存器 / `fc_upd_wr` | `rtl/app_ctrl.v:701-726,715,1311-1336` |
| app 寄存器映射 | `rtl/app_ctrl.v:760-790` |
| app `closing`/W3 | `rtl/app_pattern.v:388,896-940` |
| app `tx_ok` / `ev_same_act`/`up_ok`/`sw_apply` | `rtl/app_pattern.v:447,544-554` |
| wrapper app_ctrl 例化 | `board/wrapper_p4.v:1279-1301` |
| `rx_upd_*` 声明/授予 | `board/wrapper_p4.v:1782-1784,2052-2053` |
| `rx_ack_obs/id` 声明 | `board/wrapper_p4.v:1829-1830` |
| `tx_retx_active/id` | `board/wrapper_p4.v:1761,2132,2219,2264` |
| TCB 四级仲裁 / `sel_fc` | `board/wrapper_p4.v:2047-2074`（`sel_fc` `:2060-2061`） |
| `slow_cfg_adp` 例化 / `rst_n` | `board/wrapper_p4.v:2080-2103`（`:2083`） |
| `ack_seen_w` | `board/wrapper_p4.v:2155-2166` |
| **`.PERSIST_EN(1'b0)`** | `board/wrapper_p4.v:2185` |
| **`BUILD_ID_V=0x29`** | `board/wrapper_p4.v:4377` |
| 快照 NW=75 / p7bdp=35 | `board/wrapper_p4.v:3296,3317` |
| 未实现地址（75 字档）= 0x15C | `board/wrapper_p4.v:3285-3290` |
| **MIR 由 SNAP_LAST_IDX 推导 / UNIMPL=+1** | `_proj_pcie/rtl/axi_regs.v:206,214-218` |
| p5wrapper 源清单含被改文件 | `sim/p4gates/p5wrapper_src.f:39-43` |
| 慢盆进入/清除/签名 | `p9_basin_probe_20261017/README_FOR_TL.md:8,174`（F11 引） |

## 附录 B 判据表达式（v4，实现直接照此写，不要改写语义）

> ⚠️ **本附录 = 实现权威**（FINDINGS_V3 教训①：附录必须与正文同等自洽）。v4 相对 v3 的改动：① 模式 B 全块包 `if (ORPHAN_ZW_EN)`（V4-2）；② 清零改 **clr 优先**、且物理放在计数块之后（V4-3）；③ FSM 补 **`cam_clr_done` 同沿交接**、**`orph_ready` 定义**、**投递沿同沿清 `orph_notify_pend`**、**`orph_down_r` 默认/清位写全**（V4-1）。

```
// ===== 0. 参数折叠（X3）=====
// ORPHAN_EN=0        ⇒ 本附录全部逻辑不存在；ev_down_i≡ev_down、ev_slot_i≡ev_slot。
// ORPHAN_EN=1, ZW=0  ⇒ 第 4 节整块不存在：orph_zw_cnt 不计数、不清零、不点火（寄存器被优化掉）。
// ORPHAN_EN=0, ZW=1  ⇒ 外层胜出 ⇒ 全关（等价 00；不存在"只开 Mode B"）。

// ===== 1. 逐拍见证（模式 A）=====
if (retx_active)  orph_saw[retx_id] <= 1'b1;         // 按 retx_id 解码 / one-hot 置位

// ===== 2. 扫描组合量 =====
scan_gate = scan_tick && !init_pend && !(ev_blk && (ev_slot_i == scan_id));
inflight  = rc_snd_nxt - rc_snd_una;
cap_eff   = (rc_snd_wnd < WIN_CAP) ? rc_snd_wnd : WIN_CAP;
win_closed= (inflight < 32'h8000_0000) && (inflight >= {16'b0, cap_eff});
work      = (rc_snd_nxt != rc_snd_una) || (retx_active && (retx_id == scan_id));
accrueA   = scan_gate &&
            (rc_state == ST_ESTAB) && (rc_snd_wnd != 0) && work &&
            !fin_sent[scan_id] && !rst_sent[scan_id] &&
            !st_done[scan_id] && !to_fired[scan_id];
// accrueB 定义在下面第 4 节的 `if (ORPHAN_ZW_EN)` 内（V4-2：不放在外层，确保随使能常数折叠）
orph_busy    = orph_state_req || orph_cam_req || orph_wait_cam || orph_notify_pend || orph_down_r;  // N3
orph_tick    = (scan_round[ORPHAN_TICK_BITS-1:0]    == 0);    // 默认 18 位 ⇒ 429.4967 ms

// ===== 3. 计数（模式 A）—— 清零优先（N6：NBA 下"清零在前"等于清零无效）=====
// 3.1 逐拍 snd_una 推进清零（立即生效）
if (una_adv) begin
  orph_cnt[una_adv_id] <= 8'd0;
  orph_saw[una_adv_id] <= 1'b0;
end
// 3.2 扫描计数（物理放在 3.1 之后；同拍"清零+计数"时 clr 赢）
if (scan_gate) begin
  if (!accrueA || (una_adv && (una_adv_id == scan_id)))
       orph_cnt[scan_id] <= 8'd0;
  else if (orph_tick)
       orph_cnt[scan_id] <= (orph_cnt[scan_id] == 8'hFF) ? 8'hFF : orph_cnt[scan_id] + 8'd1;
  if (!accrueA) orph_saw[scan_id] <= 1'b0;                   // 与 3.1 同目标同值
end

// ===== 4. 模式 B（accrueB + 计数 + fireB）—— 全块包 ORPHAN_ZW_EN（V4-2）=====
if (ORPHAN_ZW_EN) begin : g_orph_zw
  orph_zw_tick = (scan_round[ORPHAN_ZW_TICK_BITS-1:0] == 0);   // 默认 20 位 ⇒ 1.7180 s
  accrueB = scan_gate &&
            (rc_state == ST_ESTAB) && (rc_snd_wnd == 0) &&
            (rc_snd_nxt != rc_snd_una) &&
            !fin_sent[scan_id] && !rst_sent[scan_id] &&
            !st_done[scan_id] && !to_fired[scan_id];
  if (ack_obs) orph_zw_cnt[ack_obs_id] <= 8'd0;              // 逐拍清零（含零窗 ACK）
  if (scan_gate) begin
    if (!accrueB || (ack_obs && (ack_obs_id == scan_id)))
         orph_zw_cnt[scan_id] <= 8'd0;
    else if (orph_zw_tick)
         orph_zw_cnt[scan_id] <= (orph_zw_cnt[scan_id] == 8'hFF) ? 8'hFF : orph_zw_cnt[scan_id] + 8'd1;
  end
  fireB = scan_gate && accrueB && (orph_zw_cnt[scan_id] >= ORPHAN_ZW_LIM) && !orph_busy;
end
else begin : g_orph_zw_off
  fireB = 1'b0;      // 常数折叠：orph_zw_cnt 不存在；不计数、不清零、不点火（V4-6 钉死）
end

// ===== 5. 点火 =====
fireA = scan_gate && accrueA && orph_saw[scan_id] && (orph_cnt[scan_id] >= ORPHAN_LIM) &&
        (win_closed || (retx_active && (retx_id == scan_id))) && !orph_busy;
fire  = fireA || fireB;

// ===== 6. FSM（N3/N4/N5）—— 逐拍
// 寄存器：orph_slot[3:0], orph_state_req, orph_cam_req, orph_state_done,
//         orph_wait_cam, orph_notify_pend, orph_down_r, orphan_cam_clr
// 组合：
orph_ready   = orph_notify_pend;        // v4 定义（N5）：电平 = notify_pend
abort_comb   = (ev_up && (ev_slot == orph_slot)) || (ev_down && (ev_slot == orph_slot)) ||
               fin_sent[orph_slot] || rst_sent[orph_slot];
orph_active  = orph_state_req || orph_cam_req || orph_wait_cam || orph_notify_pend;  // 不含 down_r
cam_clr_done = orph_wait_cam && !orphan_cam_clr;    // clr 1 拍脉冲已回落（写沿已过）
deliver_gate = orph_ready && !ev_up && !ev_down && !to_push && !ev1_v && !to_pushed_r;

// 每拍默认（脉冲契约）：clr / down_r 非置位拍恒 0
orphan_cam_clr <= 1'b0;
orph_down_r    <= 1'b0;

if (abort_comb && orph_active) begin       // 中止：清全部 pending，不发通知
  orph_state_req <= 0; orph_cam_req <= 0; orph_state_done <= 0;
  orph_wait_cam <= 0;  orph_notify_pend <= 0; orph_down_r <= 0; orphan_cam_clr <= 0;
end
else if (fire) begin                       // fire 拍（!orph_busy 已保证无进行中 FSM）
  st_pend[scan_id] <= 1'b1; st_done[scan_id] <= 1'b1;
  orph_slot       <= scan_id;
  orph_state_req  <= 1'b1;  orph_cam_req <= 1'b1;
  orph_state_done <= 1'b0;  orph_wait_cam <= 1'b0; orph_notify_pend <= 1'b0;
  orph_down_r     <= 1'b0;  orphan_cam_clr <= 1'b0;
end
else begin
  // (a) fc gnt：TCB state=0 已在本拍落地 ⇒ 下一拍起 state_done=1
  if (fc_gnt && fc_sel_r == 3'd5 && fc_id_r == orph_slot) begin
    orph_state_req  <= 1'b0;
    orph_state_done <= 1'b1;
  end
  // (b) CAM 清 issue：必须在 state_done=1 之后（F9）
  if (orph_cam_req && orph_state_done && !scfg_busy && !abort_comb) begin
    orphan_cam_clr <= 1'b1;                // 1 拍脉冲；CAM 写在本拍结束沿落地
    orph_cam_req   <= 1'b0;
    orph_wait_cam  <= 1'b1;
  end
  // (c) wait_cam → notify_pend 交接：必须同沿（N3；拆两拍 ⇒ busy 1 拍空档 ⇒ 第二槽乘虚）
  if (cam_clr_done) begin
    orph_wait_cam    <= 1'b0;
    orph_notify_pend <= 1'b1;
  end
  // (d) 通知投递：orph_ready = notify_pend；同沿清 notify_pend ⇒ down_r 严格 1 拍
  if (deliver_gate) begin
    orph_down_r      <= 1'b1;
    orph_notify_pend <= 1'b0;
  end
end

// ===== 7. 计数 =====
if (orph_down_r) stat_orphan <= stat_orphan + 32'd1;       // 只在提交拍（1 拍脉冲）
```

> **逐拍检查（照此实现的预期波形）**：fire 拍 `state_req=1` ⇒ busy=1；fc gnt 拍 `state_req<=0, state_done<=1`（cam_req 仍 1）⇒ busy=1；CAM 清拍 `cam_req<=0, wait_cam<=1` ⇒ busy=1；`cam_clr_done` 拍 `wait_cam<=0, notify_pend<=1`（**同沿，busy 连续**）⇒ busy=1；投递拍 `down_r<=1, notify_pend<=0` ⇒ busy=1；下一拍 `down_r<=0` ⇒ busy=0。**交接处任何一拍都没有 busy=0**。**`orphan_cam_clr`/`orph_down_r` 严格 1 拍**；`orph_notify_pend` 在投递门长期关闭时保持 1（busy 保持），直到投递或 abort。
> **与正文的对应**：§3.2 步骤 3 的"等 clr 回落"= 本附录 `cam_clr_done`；步骤 4 的 `orph_ready` = 本附录定义；§3.4 的 busy 五项 = 本附录 `orph_busy`；§3.6 的投递门 = `deliver_gate`。

## 文末补记 v4.2（2026-10-17 板级轮后，TL 回灌；非设计变更）

- **实施/构建/板级状态**：实施轮 `0fad29b8`（单元 18/18 + 变异 M1–M14 全红 + 全链 5 臂 + 矩阵 19/19）；构建 **0x2A** `aa44a0ed…a3b6`（`WNS +0.039 / WHS +0.010 / 0/0/0`，backstop 未触发 ⇒ W75 保留）；板级轮 = `p9_board_0x2A_20261017/README_FOR_TL.md`。
- **板级主结果【已证】**：正臂（0x2A，单边 DROP 与双向 DROP 两跑）`ΔW75 = +1`，**点火 t_rel = 61.68 s**（设计 61.85 s，差 0.17 s ≈ 0.4 tick）两次独立复现；点火后新连接 **802.2 Mbps / 200,001,020 B / mism=0** ⇒ **槽恢复【已证】**（W71/W73 各 +2，W75 对新连接不重复点火）。负臂（0x28）无 W75、槽保持占用。回归四臂全 `ΔW75 = 0`：健康快流 801 Mbps / 慢盆爬行 1.554 Mbps 140 s / 零窗 persist 活对端 200 s（p99 IAT 60.000085 s，恢复 891 Mbps）/ churn 12,000 连。
- **⭐ D2 新发现（订正本件 B1 负臂期望）**：**总黑洞下不存在"20 ms 周期重放不止"** —— 板只重传 **16–21 个会话（~0.35–0.47 s）即静默**，`ΔW55` 140+ s 不增长；**负臂真实签名 = 不回收 + 槽静默卡死**；"回收后 pcap 重放停止"格 = **【未判定】**（回收前已停）。正臂判别力来自 `ΔW75 + 槽恢复`，**不依赖 pcap**，故不受影响。停止的具体 RTO 分支【未定位】（见机制档案 §D2）。
- **F1 行为面**：孤儿回收写 state=0 后 app 收尾字进不去 `tcp_tx_frame` ⇒ closing 保持到下一次 ADD —— **板级已观测自愈**（新连接后 active=1/closing=0/重新发帧）；残余按 TL 裁定选项①接受自愈，选项②（帧器放宽）登记后续候选。
- **未决照录**：0x2A 仅一个独立锚（第二份是字节副本）· app 内部 closing/active 无快照字（仅行为证据）· B5c/361 s 未跑 · F6-a 未测 · 0x2A 现役资格待用户裁（板已收尾烧回 0x28）。

—— 完（本件 = 纯设计修订版 v4；**不含任何 PASS/FAIL 裁定，不含实施授权**）
