# P9 换流门 R5 收尾报告（`fix_r5`）

> **agent 原件由平台拒写 .md ⇒ 全文回传、TL 代落盘**（本件正文 = agent 原文；文末「TL 附加」= TL 独立抽核记录）。
> **口径**：本报告**不给 PASS/FAIL 裁定**（裁定权在用户/判据所有者）；下面给的是**读数与形态**。
> **运行环境纪律**：全程只跑 xsim/xvlog/xelab；**未跑任何综合/实现/位流**、未烧板、未碰对端机、未提交 git。
> 收尾核：**0 个残留 xsim/xelab/vivado 进程**；跑门期间**未改任何源**。
> **R5 最终冻结修订 = `rtl/app_pattern.v` 现读 `sha256 be0b5f9c642dcd97bec2c3ffb3beec73d57df22e9e39d3be75a5f46c16d8aa6c`**（90524 B；与 07:58 SWC 门 stdout 的 SRC 行、与锚门重跑期间逐次一致，收尾再核不变）。
> 上游 = `3a21614`（R4/fold3，`app_pattern.v` `61650b28…`）+ `REPORT.md`（同目录，TL 代落盘版）。

---

## §0 停点现场核对（先读；与派单描述逐条对照）

| 派单描述 | 现读核对 | 结论 |
|---|---|---|
| `rtl/app_pattern.v` +19/−1 = ① `:994` E13 改形 `sw_apply→!active`（替换式，非三析取追加）+ 注释；② W3 `close_send` 追加 `&& !(SWC_OK && frm_wait)` | `git diff --numstat` = **19/1**；hunk1 = `close_send` 追加（R5 于 `:516-519`）；hunk2 = `:1012` 守卫 `!(SWC_OK && (closing \|\| !active))`（R4 行号 `:994`，**替换式**，无三析取） | **一致** |
| `sim/p9_swc_gate/` 四件改动 + `mut/{m6,m6b,m7}` 重生成 | 现读一致（TB `b28bff35…` / bat `92fd3e3d…` / mk_mut `bad2ab6d…` / 3 个 mut 件 mtime 07:58） | **一致** |
| `sim/p7b_longsend/mut/m1..m5` = M（自生成待还原） | 停点时 `M`；**已在本轮收尾还原**（§7） | **一致（已处理）** |
| `fix_r5/` 已落 5 件：`gate_swc_r5_stdout.txt`(07:58) · `gate_cont_postexp_stdout.txt`(08:01) · `patch_tb_r5.py` · `r5_hunk{1,2}.txt` | 5 件全在 | **一致** |
| 回报值：F/F10={}；H/H10/OFF={0,1,2,9,10}；M6 全红；M6B {3,4}；M7 {10} | **全部核实为真**（`gate_swc_r5_stdout.txt` + 各 `run*/xs.log` 原件；H/H10 的红集由 TB 内部"实测红集==期望红集"判据 + RC=0 反证，OFF 有显式逐臂表） | **一致** |

**三处与派单描述不符/未含（如实回报）**：

1. **`gate_cont_postexp_stdout.txt`（08:01）是半成品，不是完整锚门记录**：内容只到 `---- TB FAIL detail [M3]`（第 56 行截止），**缺** `[M4]`/`[M5]` 详单、**缺** SUMMARY、**缺** 2a/2b/2c/3/5 六条判据、**缺** `CONT-GATE: PASS/FAIL` 与退出码。旁证：`sim/p7b_longsend/runM5/` 停点时仍是上一轮 **05:58** 的产物（未被 R5 轮重跑；`runM4` mtime 08:01 = 上轮 agent 恰好停在其上）。⇒ 按派单"缺则补跑"，**已整轮重跑锚门至完成**（§6；半成品已保全为 `gate_cont_postexp_stdout_partial_0801.txt`）。
2. **第一轮 `REPORT.md` §2 一处字段与日志不符（勘误登记）**：报告写 "`R2 orc=8 nst=0 act=0 bb0v=0`（P-2 撤销形态）"，而**两轮日志**（`sim_run_logs/runH/xs.log` 与 R5 `runH/xs.log`）**逐字均为 `bb0v=1`**（`bb0=34`）。该字段不进 `arm_red`（arm2 红因 = P-A `orc=8`），结论不受影响，但**引用该句须按本勘误读**。
3. **两处陈旧字样（表面债，登记不修）**：`tb_p9_swc.v` 文件头 "臂表 (NALL=10, …)"（代码 `NALL = 11`）；`run_tb_p9_swc.bat` 第 97 行 `[M6 reds] (expect all 10 arms red)`（现为 11 臂全红）。**不修的理由** = 门已跑毕，事后改 TB/bat 会破坏"TB sha ↔ stdout"绑定（R4 轮"跑动期间改注释 ⇒ 整轮作废重跑"的同款纪律）。

---

## §1 两处 diff + sha 改前改后

**`rtl/app_pattern.v`：`61650b28…2de1b9e2`（R4）→ `be0b5f9c…6d8aa6c`（R5，现读冻结）· 90524 B · +19/−1 · 两个 hunk**

**hunk 1（裁决 B，`close_send`；R4 `:509` 附近 → R5 `:510-519`）**：

```
     wire        close_send = closing && !op_beat &&
+                             !(SWC_OK && frm_wait) &&
                              (drop_pw || (!pw_valid &&
                                           (op_sent || (seg_sent != 12'd0))));
```
+ 6 行注释（全文在 `r5_hunk1.txt`；要点 = frm_wait 态本帧已整帧交付、S_IDLE 接受门无 tlast 条件（`rtl/tcp_tx_frame.v:1814/:1880` 一带）⇒ 收尾字会被当帧启动收下 ⇒ 落零长数据帧；W3 的 `else` 支即正确动作；对 HEAD 的 `ev_down`-in-frm_wait 路径不生效（SWC_OK=0 折叠，**那条既存形态不修**））。

**hunk 2（裁决 A，E13 守卫；R4 `:994` → R5 `:1012`）**：

```
-            if (frm_wait && tx_ok && !(SWC_OK && (closing || sw_apply))) begin
+            if (frm_wait && tx_ok && !(SWC_OK && (closing || !active))) begin
```
+ 11 行注释（要点 = (i) 覆盖 post-close 闲置翼 `frm_wait ∧ !active`（旧形态两项全假 ⇒ 抢置 op_pend ⇒ 流浪 opener）；(ii) `sw_apply ⇒ !active` 支配关系 ⇒ `!active` 严格覆盖 `sw_apply`；SWC_OK=0 门恒真）。
注释里的 `:922` = **HEAD 冻结件行号**（`head_app_pattern.v:922` = 同一块），与现役 `:1012` 是同一求值点，属既有锚记惯例（第一轮报告同用 `:922`）。

**门侧文件 sha（改前=R4/`3a21614`，改后=R5 现读）**：

| 文件 | 改前 | 改后 | 变化 |
|---|---|---|---|
| `sim/p9_swc_gate/tb_p9_swc.v` | `84dc9d79…` | `b28bff35…` | +165/−15（P1–P20，§2） |
| `sim/p9_swc_gate/run_tb_p9_swc.bat` | `82c2e115…` | `92fd3e3d…` | +3/−3（C10 入表 / OFF 期望注释 / M7 注释） |
| `sim/p9_swc_gate/mk_mut_swc.py` | `7516d9a3…` | `bad2ab6d…` | +3/−2（M7 锚点随改，§2） |
| `sim/p9_swc_gate/head_app_pattern.v` | `811a84e4…` | `811a84e4…` | 未动（TB 内硬断言） |
| `sim/p9_swc_gate/mut/{m6,m6b,m7}.v` | （R4 生成版） | `59f2b2c9…`/`327f130d…`/`c5c4365b…` | R5 源重生成 |
| `sim/p9_swc_gate/runF_dbg_witness.bat` | — | `68ce0b71…` | **本轮新增**（见证运行器，§4；ASCII+CRLF；不触碰门目录） |
| `board/wrapper_p4.v` | `dc1cd516…` | `dc1cd516…` | **一字未动**（`.TX_SWCLOSE(1'b1)` 启用点在 R4 已就位；R5 不改 BID） |

---

## §2 锚点变更表（`mk_mut_swc.py`）

**变异集（3 件 / 5 个 sub，`hits==expect` 全中；`MUTGEN OK`）**：

| 变异 | subs | 锚点变更 | 期望红（R5） |
|---|---|---|---|
| M6 `m6_v1_eq` | 3 | **不变**（E4/E5/E6 字面方程锚未被 R5 触及） | 全 11 臂 |
| M6B `m6b_closing_drop` | 1 | **不变**（`ev_same_act` 行未被 R5 触及） | {3,4} |
| M7 `m7_guard_swpend` | 1 | **锚点文本随改**：旧 `!(SWC_OK && (closing \|\| sw_apply))` → 新 `!(SWC_OK && (closing \|\| !active))`；变异目标文本不变（`!(SWC_OK && (sw_pend \|\| sw_apply))`）；note 更新为"R5 后咬点 = u_swcwing" | {10}（咬点迁移，§3-c） |

**TB 端（`patch_tb_r5.py` P1–P20 全表 + 一处就地改写）**：

- **P1** 文件头臂表 → 新增 idx10 `u_swcwing` 行 + arm9 R5 重定时注；**P2** `NALL 10→11`；
- **P3/P12** 见证引线（`w_fw`=DUT `frm_wait`、`w_swa`=DUT `sw_apply`；`P9_HEAD_RTL` 下 `w_swa` 钉 0 防 elaborate 挂）；
- **P4** idx10 激励（frm_wait 冻结 → ev_down 收尾 → idle 稳 5 拍拉高 tx_ok（翼触发）→ 20 拍后同槽 ev_up）；**P5–P11** 向量接线（`rdy[10]`/`txok[10]`/`ev_u|d[10]`/`ev_slotw`/`ev_own[10]`/`up_w[10]`）；
- **P6（arm9 重定时）** `txok[9]`：`!pk8 || h8_rel` → `!pk8 || o8_done`（"收尾完成拍 E+1 回升"）——**原因 = 裁决 B 让 frm_wait 收尾变 1 拍 `else` 支、不等 `m_tready`**，arm9 的"停滞期交接"窗口随之收窄到收尾完成拍 E+1；
- **P13–P16** 记账/窗口/监视：新增 `M_nclwf/M_wbad/M_domv/wing_win`；nclw 按 `w_fw` 拆分两类；翼窗口（`u10_dn` 开、`u10_up` 关）内 `active==0` 时接受的 opener 计 `M_wbad`；**每拍支配监视**（`P9_SWC_ARM` 专属：`w_swa[gi] && w_act[gi]` ⇒ `M_domv++` + `[DOM-VIOL]`）；
- **P17** 期望红集：`EXP_HEAD` `{0,1,2,9}` → `{0,1,2,9,10}`；`EXP_M7` `{9}` → `{10}`；**P18** `arm_red(10) = (M_wbad==0)`；
- **P19** 打印扩展（R 行加 `nclwf/wbad/domv`；C 行加 `WING` 列，P-C 列收窄到 `ii∈[6,9]`）；**P20** 新增 W2（nclwf==0 逐臂）+ W1（支配逐臂）。
- ⚠️ **就地改写（未脚本化，登记）**：`patch_tb_r5.py` 的 P20 原形把 **W2 写成"全模式硬判"**；最终 TB 里 W2 是 **`ifdef P9_SWC_ARM` 包裹 + SWC=0 侧打 `[ n/a ]` 行并把 `nclwf arm10=` 作为裁决 B 的**正控**读出**。**原因**：H/H10/OFF 的 `frm_wait` 收尾字是**登记不修的 HEAD 既存形态**（arm10 实测 `nclwf=1`），全模式硬判会把三条**合法**运行判红。现读 TB = `b28bff35…`（即门实际跑的版本）。

---

## §3 8 运行读数表（SWC 门 · 全部 RC=0 · `P9-SWC-GATE: PASS`）

运行级判据 = "实测红集 == 期望红集"（TB 内 `-d P9_EXP_*`）；**突变臂的"必红"由 TB 自己比对**（不是"非零 RC = 好"）。权威记录 = `gate_swc_r5_stdout.txt`（07:58），本文所引逐臂读数 = `sim/p9_swc_gate/run*/xs.log` 原件。

| 运行 | RTL/构型 | 期望红集 | 实测红集 | RC | 关键逐臂读数（R 行摘要） |
|---|---|---|---|---|---|
| **F** | 活 RTL + SWC=1 | {} | **{}** | 0 | 11 臂 `orc=0 bb0=7f pcv=0 wbad=0 domv=0`；`nclw` = R0–R5:1 / R6–R10:0；`nclwf≡0`；R9 `tid=1` |
| **F10** | F + `P7B_10G` | {} | **{}** | 0 | 同形（A2 整字路：`nst` 逐臂 5/7/7/6/6/5 → 59/61/61/59/59/59） |
| **H** | 未修冻结件 | {0,1,2,9,10} | **{0,1,2,9,10}** | 0 | R0 `orc=4905 bb0=03` · R1 `orc=6320 bb0=34` · R2 `orc=8 nst=0 act=0` · R9 **TID 红**（`tid=0`）· R10 `pcv=1 nclwf=1 wbad=1` + `[WING-VIOL] cyc=1878`；`domv=0`（W1 为 n/a，SWC=0） |
| **H10** | 未修 + `P7B_10G` | 同 | 同 | 0 | R0 `orc=59384 bb0=00` · R1 `orc=60838` · R2 `orc=8` · R9 TID 红 · R10 `pcv=1 nclwf=1 wbad=1` + `[WING-VIOL] cyc=240` |
| **OFF** | 活 RTL + SWC=0（常量级负对照） | 同 | 同 | 0 | **逐臂与 H 逐字相同**（含 `[WING-VIOL] cyc=1878`）⇒ 常量门是折叠点 |
| **M6** | `m6_v1_eq` | 全 11 臂 | **全 11 红** | 0 | 全臂 `act=0 nst=0 bb0v=0`（会话全起不来）；红因 = P-B（全臂）+ STARTS（2/3/4） |
| **M6B** | `m6b_closing_drop` | {3,4} | **{3,4}** | 0 | R3/R4：`bb0v=0 nst=0`（closing 态事件被丢、静默）；其余全绿 |
| **M7** | `m7_guard_swpend` | {10} | **{10}** | 0 | R10 `pcv=1 wbad=1` + `[WING-VIOL]/[PC-VIOL] cyc=1878`；R9 转**绿**（`pcv=0 nclw=0 tid=1`） |

**F 臂逐臂 R 行（现读，逐字）**：`R{i} orc=0 bb0=7f bb0v=1 nst={5,7,7,6,6,5,5,5,5,5,5} pcv=0 nclw={1,1,1,1,1,1,0,0,0,0,0} nclwf=0 wbad=0 domv=0 tidv=1 tid={0×9,1(R9),0} act=1 done=0`；C 表 C0–C10 全 `P-A=1 P-B=1 P-C=1 STARTS=1 TID=1 WING=1 red=0 exp_red=0`；F 运行 `[DOM-VIOL]/[PC-VIOL]/[WING-VIOL]/[MISMATCH]` 计数 = **0**。

### 与第一轮的逐项差异（每处给"为什么"）

**(a) 臂数 10→11、新增 idx10 `u_swcwing`** —— 为什么：裁决 A 的缺陷场景（post-close 闲置翼）在旧门里**没有臂覆盖** ⇒ 修复无牙可验（设计件 v2r3 §5-1 是裁决依据）。
**(b) `EXP_HEAD` `{0,1,2,9}`→`{0,1,2,9,10}`** —— 为什么：新臂在未修 RTL 上**必须红**（HEAD 无守卫 ⇒ 翼触发拍 `:922` 抢置 ⇒ `M_wbad+1`）⇒ 期望红集随臂扩；同时 H/H10/OFF 三构型同红 = `M_wbad` 判据的正控。
**(c) `EXP_M7` `{9}`→`{10}`（咬点迁移）** —— 为什么（三层）：① 裁决 B 让 frm_wait 收尾变 "1 拍 `else` 支、不等 `m_tready`" ⇒ arm9 的"停滞期交接"窗口收窄为**收尾完成拍 E+1**（TB P6 把 `txok[9]` 改挂 `o8_done` 以对齐新完成拍）；② 重定时后 arm9 上 M7 守卫与现役守卫**在每个求值拍重合**——关键拍上 `sw_apply=1` 恰好顶住 M7 的 `(sw_pend || sw_apply)` 项（`sw_pend` 已被交接清零、`sw_apply` 在同拍为 1）；③ 而**闲置翼拍**上 `sw_pend=0 ∧ sw_apply=0` ⇒ 只有 `!active` 能拦 ⇒ M7 在 arm10 咬（`wbad=1`）。⇒ **M7 仍必红，红在翼臂**（这也是"裁决 A 的牙"的独立见证，见 §4）。
**(d) 新增判据/见证**：W1（支配，SWC=1 专属）/ W2（nclwf==0，SWC=1 专属 + SWC=0 侧正控读出）/ `WING` 列（arm10 红因）；P-C 列对 arm10 强制 1（该臂用 WING 判，`M_pcv[10]` 仍计数）。
**(e) 打印格式**：R 行加 `nclwf/wbad/domv`，C 行加 `WING` 列；runner 的 criteria findstr 加 `C10`。
**(f) 勘误**：第一轮 `REPORT.md` §2 的 "R2 … bb0v=0" 与两轮日志（均 `bb0v=1`）不符（§0-2）。

### nclw 逐臂旧（R4）新（R5）对比（F 运行；F10/M6B/M7 同形）

| 臂 | R0 | R1 | R2 | R3 | R4 | R5 | **R6** | **R7** | R8 | **R9** | R10 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 旧 nclw | 1 | 1 | 1 | 1 | 1 | 1 | **1** | **1** | 0 | **1** | —（新臂） |
| 新 nclw | 1 | 1 | 1 | 1 | 1 | 1 | **0** | **0** | 0 | **0** | **0** |
| 新 nclwf | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

变化 = **R6/R7/R9 `1→0`**（= 裁决 B 的直接行为读数：这三臂的收尾字原本在 **frm_wait 态**被接受）；R0–R5 不动（**非** frm_wait 类收尾字，合法且保留——如 §4 轨迹 `cyc=84 CLW2ACC act=1`）；R8 `0→0`（R4 起该臂的收尾字路径本就由 W3 `else` 支解决，机制未变）。**`nclwf`（R5 新列）在全部 SWC=1 运行 ≡ 0**；未修构型（H/H10/OFF）的 R10 `nclwf=1` = 正控（§5）。（未修构型逐臂读数两轮**逐字相同**（新增列除外），arm0–9 一条未动。）

---

## §4 支配见证（裁决 A）：`sw_apply=1 ⇒ active=0`（任何拍不得同真）

**① 门内逐拍监视器（等效见证，覆盖全部 SWC=1 运行）**：`tb_p9_swc.v:613-618`——`P9_SWC_ARM` 专属，每拍对 11 臂逐个采样 DUT 的 `sw_apply` 与 `active`：`if (w_swa[gi] && w_act[gi]) { M_domv[gi]++; [DOM-VIOL] }`；收口判据 `tb_p9_swc.v:850-854`（W1 逐臂 `chk(M_domv[ii]==0)`，**违例即硬失败**）。
**读数**：F/F10/M6/M6B/M7 **5 个运行 × 11 臂 = 55 条 W1 全部 `[ ok ]`**；全部运行日志 `[DOM-VIOL]` 命中 = **0**。SWC=0 侧（H/H10/OFF）W1 打 `[ n/a ]`（理由正确：SWC=0 时 `sw_apply ≡ up_do`，可合法与 `active` 同真——那是 A3 同槽重启语义，**不属于**本支配命题）。
**② 代数依据（RTL 级）**：`rtl/app_pattern.v:540/:543` —— `idle_now = !active`；`sw_apply = SWC_OK ? (idle_now && up_ev) : up_do` ⇒ SWC_OK=1 时 `sw_apply ⇒ !active` 是**直接代数推论**（旧 `sw_apply` 项被 `!active` 严格覆盖，"不多拦一拍、不漏一拍"）。
**③ 非空性（监视器不是空判据）**：`act_id` 的唯一写点 = `if (sw_apply)` 块内 `act_id <= up_slot`（`rtl/app_pattern.v:753/783`）⇒ arm9 观测到的 **`tid=1`（首个 opener 携带目标槽 1）** 证明**这些运行里 `sw_apply` 确实断言过**（F/F10/M6B/M7 四构型；M6 为"会话全死"突变构型，其 `domv=0` 属空真——已登记，由其"全臂红"承担该运行的意义）。
**④ `-d P9_DBG` 轨迹（R5 版；新目录 `runF_dbg_witness/`，不动门目录、不改任何源；日志耐久件 = `fix_r5/runF_dbg_witness_r5.log`）**：

```
DBG cyc=84  CLW2ACC act=1 sw_pend=1                      ← arm2 收尾字被接受（非 frm_wait 类, 合法）
DBG cyc=85  ACT2 1->0 closing=0 sw_pend=1 op_pend=0 op_sent=0 pwv=0 rdy=1 upok=1 swapp=1 upev=1
                                                          ← 应用拍: sw_apply=1 且 active=0 (同拍直读)
DBG cyc=86  ACT2 0->1 closing=0 sw_pend=0 ... swapp=0     ← 新会话起（opener）
DBG cyc=1870 EV9HANDOFF slot=1 closing=1 sw_pend=1 up_pend=0   ← 异槽交接到达时收尾正在飞
DBG cyc=1875 OP9 acc tid=1 act=1                          ← arm9 首个被接受的 opener 携带目标槽 1
```
（`cyc=85` 一行 = 支配命题的**正向直读**：`sw_apply` 断言时 `active` 已为 0；与监视器"从无同真"互为两面。arm9 两行相对第一轮 `cyc=1872/1877` 各前移 2 拍 = 裁决 B 重定时的直接痕迹。）
**⑤ 求值点因果隔离（单行突变）**：`diff rtl/app_pattern.v mut/m7_guard_swpend.v` = **恰 1 行**（`:1012` 守卫）。同激励下，F `wbad=0` vs M7 `wbad=1`（`[WING-VIOL] cyc=1878`，且 H/OFF 亦在同拍 `1878` 咬）⇒ **守护点的"拦/放"唯一由守卫第三项决定**。
**结论**：**未出现反例**——任何拍均无 `sw_apply ∧ active` 同真（55 臂次硬判 + 全周期监视 + 应用拍轨迹）。

---

## §5 裁决 B 的牙（`frm_wait` 态收尾字禁发）

**判据**：`tb_p9_swc.v:841-845` —— W2 逐臂 `chk(M_nclwf[ii]==0, "arm%0d no frm_wait-state close word accepted")`，**SWC=1 专属**（55 条全 `[ ok ]`）。
**读数（结构上可行，非"未测"）**：
- 修复侧：F/F10/M6/M6B/M7 全臂 `nclwf ≡ 0`（含 R6/R7/R9/R10）；
- **正控**：H/H10/OFF 的 `[ n/a ]` 行读出 **`nclwf arm10=1`** —— 同一激励在**未修**构型上确会发出 frm_wait 态收尾字 ⇒ 该计数器对"这事件"有牙（非空判据）；
- 行为面：F 运行 R6/R7/R9 的 `nclw` `1→0`（§3 表）+ 裁决 B 断言的机制（W3 `else` 支清理：`closing<=0/active<=0` 一拍完成、`frm_wait` 残留 → 后续由 `sw_apply`/换流块接管）。
- ⚠️ 口径：对 **HEAD 的 `ev_down`-in-frm_wait 路径**（arm10 的既存形态）本项**不生效也不判**（登记不修，H/OFF 的 `nclwf arm10=1` 即它的读数）。

---

## §6 96-dump 退化重申（裁决 A 条件）+ 锚门整轮补跑

**A. 锚门整轮重跑（R5 修订，SWC=0 默认）** —— `sim/p7b_longsend/run_cont_gate.bat`（09 运行），完整 stdout = `fix_r5/gate_cont_postexp_stdout.txt`（180 行，**末尾 `CONT-GATE: PASS`，退出码 0**）：
- 运行级：A/B/C **RC=0**；G **RC=1**（红 = 恰 `A13a/A13b` 两条）；M1=22 errs / M2=1 / M3=2 / M4=22 / M5=2（**M2 详单 `cyc=9242/14726/20210/25694` 与第一轮逐字相同** ⇒ 确定性复现）。
- 六个判据全 `[PASS]`：19 文件 A-vs-G 逐字节等价锚 · A3 差恰 `{d7,d8,f7,f8}+stats I7/I8` · arm G reds==2 · reds=A13a/A13b 对 · zero-arm（z_zero_c==z_zero_d on A/B/C/G）· 编译源见证（A/B/C=活 `rtl/app_pattern.v`，G=冻结锚 `frozen/app_pattern_rev0e804099.v`）。
- runB 关键读数与第一轮逐字相同：`I0..I9`（含 I3 `7999/7999`、I7/I8 `32/31704`）· `REC ×3 => RESUMED` · `RATE tl1_base=1252 tl1_cont=1252` · `TOK tok_dropped=1`。
- 归档：R5 九运行产物（同第一轮口径镜像，328 件）→ `fix_r5/gate_cont_r5/`。（半成品 stdout 保全为 `gate_cont_postexp_stdout_partial_0801.txt`。）

**B. 96 文件逐字节 `cmp`（主判据，复用第一轮 24 文件白名单）**：

```
4 臂 (A/B/C/G) × 24 文件 {d0..d9.hex, f0..f9.txt, rate.txt, stats.txt, z_zero_c.txt, z_zero_d.txt}
对比对象: R5 修订 (sim/p7b_longsend/run*) × 前代 (gate_cont_postexp/run*, R4 轮归档)
结果: compared=96  diffs=0
```
**C. 扩展比对（超出第一轮口径，加做）**：另 20 个公共文件（`xe.log/xe_out.log/xs.log/xs_out.log/xv_out.log/xvlog.log/srcpath.log` × 4 臂）——12 个逐字节相同；8 个（`xs.log`/`xs_out.log` × 4 臂）差异**仅限运行元数据 4 类行**（`# Start of session at…` / `# Process ID` / `# Available Virtual` / `Exiting xsim at…`）；**剥离这 4 类行后 8/8 逐字节相同**。
**口径**：证明的是"**默认（`TX_SWCLOSE=0`）逐位退化**"；**不证明**板上行为不变（板上传 1）。

---

## §7 卫生与环境（收尾核）

- `sim/p7b_longsend/mut/m1..m5`（锚门自生成）→ **已 `git checkout --` 还原**（现 `git status` 该目录 0 修改）。
- **0 个残留 xsim/xelab/vivado 进程**（含见证运行与锚门重跑之后逐次核）。
- 跑门期间（07:58 SWC 门 / 08:10 锚门 / 08:13 见证）**未改任何源**；RTL sha 在收尾再核 = `be0b5f9c…`（不变）。
- **未提交 git**（工作树 = 7 个已跟踪文件被改（`rtl/app_pattern.v` + 6 个 `sim/p9_swc_gate/` 件）+ `fix_r5/`、`sim/p9_swc_gate/runF_dbg_witness.bat` 未跟踪；`sim/**/*.log` 被 `.gitignore:404` 忽略）。
- **R5 最终冻结修订 = `rtl/app_pattern.v` `sha256 be0b5f9c642dcd97bec2c3ffb3beec73d57df22e9e39d3be75a5f46c16d8aa6c`（90524 B）**。
- **`fix_r5/` 交付清单**：`REPORT_FIX_R5.md`（本件）· `gate_swc_r5_stdout.txt` · `gate_cont_postexp_stdout.txt`（完整 180 行）+ `_partial_0801.txt`（半成品保全）· `gate_cont_r5_full_stdout.txt`（= 完整版同名副本）· `gate_cont_r5/`（328 件归档）· `patch_tb_r5.py` · `r5_hunk1.txt` · `r5_hunk2.txt` · `runF_dbg_witness_r5.log`。

---

## §8 未测项 / 未做（防误读）

- **未构建/未综合/未实现/未出位流/未上板**（纪律）；时序与资源 = 零读数。
- **E12（可选观测计数器）仍未做**（R4 已登记；本轮未动）。
- `board/wrapper_p4.v` **一字未动**（含 BID；R5 不需要它在场）。
- **DOM 监视器在 M6 臂为空真**（该突变下 `sw_apply` 从未断言；登记如上）。
- arm10 的 **P-C 列不进该臂红因**（用 WING 判；`M_pcv[10]` 仍被计数并在未修/M7 构型上 =1）。
- 两处陈旧字样（§0-3）**登记不修**；第一轮报告勘误 1 处（§0-2）。
- W2 的"SWC=1 专属 + n/a 正控"最终形态**未脚本化**（就地改写；TB 现读 sha 为准，§2 注）。
- `-d P9_DBG` 见证只覆盖 arm2/arm9 打印点（TB 既有 DBG 块）；支配的**全臂全周期**覆盖由 W1 监视器承担（§4-①），二者是"点轨迹 + 全覆盖判据"的组合，不是替代关系。

---

## §9 一句话状态

**R5（裁决 A：`:1012` 守卫 `sw_apply→!active` 替换式改形；裁决 B：W3 `close_send` 追加 `!(SWC_OK && frm_wait)`）已冻结于 `rtl/app_pattern.v` `be0b5f9c…`；SWC 门 8 运行全 RC=0（F/F10 全绿；未修/常量关红集 = {0,1,2,9,10} 含新翼臂；M6 全红 / M6B {3,4} / M7 咬点迁移到 {10}），支配关系 F 族 55 臂次硬判 + 0 违例 + 应用拍轨迹直读（`cyc=85 swapp=1/active=0`）+ 单行突变因果隔离，frm_wait 收尾字类 W2 全 0 且带未修正控（`nclwf arm10=1`），锚门在 R5 修订上**整轮补跑至 `CONT-GATE: PASS`**（前次停在 M4 的半成品已保全），**96/96 dump 逐字节全同**（扩展 20 日志文件归一化后亦全同）；环境卫生 = mut 已还原 / 0 残留进程 / 未提交；口径 = 现象与读数层，PASS/FAIL 裁定权在判据所有者。**

----------------------------------------------------------------

## TL 附加（2026-10-15 08:4x；独立抽核 + 裁定）

- **抽核（逐件现读）**：`rtl/app_pattern.v` = **`be0b5f9c…d8aa6c`** ✓（报告逐字）· hunk1 现读 `:516-519` = `close_send` 含 `!(SWC_OK && frm_wait)` ✓（裁决 B 规定形态）· hunk2 现读 `:1012` = `!(SWC_OK && (closing || !active))` ✓（裁决 A 规定形态、替换式）· 工作树 = **7 个已跟踪修改**（`rtl/app_pattern.v` + 6 个 `sim/p9_swc_gate/` 件）+ `fix_r5/`（336 件 / 6.4 MB）+ `runF_dbg_witness.bat`（未跟踪）✓ · `sim/p7b_longsend/mut/m1..m5` **已还原**（不在 status）✓ · **0 残留进程** ✓。
- **三项不符处置采纳**：① 08:01 半成品 ⇒ 已整轮补跑至 `CONT-GATE: PASS`、半成品保全（TL 认可"缺则补跑"处置）；② 首轮报告勘误（`bb0v`）⇒ **已在首轮 `REPORT.md` TL 附加块就地追加勘误行**；③ TB/bat 两处陈旧字样 ⇒ 登记不修（保 TB-sha↔stdout 绑定）认可。
- **裁定**：接受入库（R5 两处 + 门件 + `fix_r5/` + 见证 bat）。**R5 冻结 = `be0b5f9c…`**；下一步 = **0x27 构建轮**（本刻派；BID `:4329` 0x26→0x27 + 读侧 + 矩阵 + 构建 + 归档 + 定向 STA）。⛔ 本件不给 PASS/FAIL 裁定。
