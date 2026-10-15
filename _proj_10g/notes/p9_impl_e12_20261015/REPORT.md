# P9 E12 实施轮报告（可选观测计数器落地）

> **agent 原件由平台拒写 .md ⇒ 全文回传、TL 代落盘**（本件正文 = agent 原文；文末「TL 附加」= TL 独立抽核记录）。
> **派单**：E12 实施轮 —— 把换流门设计件里的 E12（4 只观测计数器）落地，作为"触发条件本身"研究的关键仪器 + K0 判据"负对照未现形"的破题件。
> **口径**：本报告**不给 PASS/FAIL 裁定**（裁定权在判据所有者）；下面给的是**改动 + 读数与形态**。
> **运行环境纪律**：全程只跑 xsim/xvlog/xelab；**未跑任何综合/实现/位流**、未烧板、未碰对端机、**未提交 git**。
> 收尾核：**0 个残留 xsim/xelab/vivado 进程**；**跑门期间未改任何源**（源文件 mtime ≤ 23:10:53，全部门运行 ≥ 23:12:22）。
> **E12 最终修订** = `rtl/app_pattern.v` `sha256 c932c3ab304a321344ab4b8061cd759f1ea3a29000037e6ea1e28f73c8023582`（94146 B）。
> 上游 = `be0b5f9c…d8aa6c`（R5 冻结）+ `a138496`（HEAD；wrapper 与门件的提交基线）。
> ⛔ **未做（明示）**：读侧链式同步（`apply_readside_bid1c.py`）**不属本轮**（归构建轮）；**BID 一字未动**（bump 归构建轮）；台账未写。

---

## §0 停点现场核对（与派单描述逐条对照）

| 派单描述（二手） | 现读核对 | 结论 |
|---|---|---|
| 4 计数 = `stat_up_ev / stat_sw_req / stat_sw_apply / stat_up_pend` | 设计件 v2 §2.3-E12 + §4.4 逐字一致（v1 §4.3 的旧名 `stat_sw_now`/`stat_up_pend_withdraw` 已被 v2 取代） | **一致** |
| 快照 **71→75 字** | 现读 `SNAP_NW_P6E = 71` → 改为 **75**；`SNAP_P7BDP_NW = 31 → 35` | **一致** |
| 未实现地址 **0x14C → 0x15C** | 双核成立（§2）；且 `axi_regs.v` 侧**参数化自动跟随**（无须改逻辑） | **一致** |
| 4 端口 wrapper 接线 | 已接（`u_app` + `p7bdp_din` 槽 31..34 + 装配 MSB 端 4 项） | **一致** |
| `rtl/app_pattern.v` 冻结 = `be0b5f9c…` | 现读 = `be0b5f9c…`（改前，与派单逐字相同） | **一致** |
| `board/wrapper_p4.v` BID = `0x27`；BID 行与注释块不许动 | 现读 `:4377` 一带 = `32'h00000027`，**本轮一字未动**（diff 里 0 hunk 落在 BID 块） | **一致** |

**与派单描述不符/需补充的（如实）**：
1. **设计件对 4 只计数器的"各计数事件定义"只给了名字级描述**（v1 §4.3：`up_ev` 计数 / `sw_now` 计数 / `sw_apply` 计数 / `up_pend_withdraw` 计数；v2 §4.4 给了括注）。**本轮把它落成逐条可核的事件式**（见 §5），并在 RTL 注释里写死口径 —— 这是"按件实施"所必需的补全，**已登记为本轮的实现选择**（不是设计件原文）。两条最可能的替代读法（`stat_sw_req` 计"W3 收尾字发出数"、`stat_up_pend` 计"所有模式的登记"）**未采**，理由见 §5-注。
2. **几何连带面比派单列举的更宽**：p6e wrapper TB 里除"窗口断言/NFF 扫描"外，还有 **73 处 MIR 寄存器地址常量**（0x13C/0x140/0x144/0x148）**必须**同批下移（MIR 块随 `SNAP_NW` 参数化推导而移动）—— 漏一处 = 读到"另一个字的正确值"（假 PASS）。已全部改（§1、§2）。
3. **`_proj_10g/notes/p7b_biz_win/check_window.py`（窗口静态核对器）不在本轮所有权内**，且它有一处**本代常量**（`nnew_top=5` = M1 代口径）⇒ 对 75 字会 FAIL。处置 = **不改原件**，在本轮目录放**本代副本**跑独立证据（§3-D）。原件与 `tb_biz_win.v`/`neg/*` 一并**登记**（§2.3 表第 7 条）。

---

## §1 改动清单（文件 / hunk / sha 改前改后）

**8 个已跟踪文件被改（+ 本轮目录）；`git status` 除本轮目录外无其它改动。**
⚠️ 行尾约定：`.v` 文件为 **LF**、`.bat` 为 **CRLF + 纯 ASCII**（改前改后同款，逐件已核；见 §8）。
⚠️ `board/wrapper_p4.v` 在 git 里存 **LF**、工作树检出为 **CRLF** ⇒ "改前 sha" 一栏给**工作树口径**（= HEAD blob 的 CRLF 变换，已用会话开始时实测值互证）。

| # | 文件 | 改前 sha256（工作树） | 改后 sha256（工作树） | numstat | 内容 |
|---|---|---|---|---|---|
| 1 | `rtl/app_pattern.v` | `be0b5f9c…d8aa6c`（**实测**，= R5 冻结/派单值） | `c932c3ab…8023582` | **+48/−1** | ① 端口表 +4 出（E12 四计数器，含口径注释）；② `ev_other_act` 之后插入 E12 计数块（1 个新 `always`，async-reset，`else if (SWC_OK)` 常量门）；③ `stat_bp_cyc` 行补逗号 |
| 2 | `board/wrapper_p4.v` | `305123dc…c699f162`（**实测**，会话开始值；= HEAD `dd1d6e84…` 的 CRLF 变换） | `bbf6e3cb…525ae47` | **+63/−12** | ① 4 根线声明；② `u_app` 例化 +4 端口；③ `biz_w71..biz_w74`（APP_MODE 支 + else 常量支）；④ `p7bdp_din` 槽 31..34 显式 assign；⑤ `SNAP_P7BDP_NW 31→35`、`SNAP_NW_P6E 71→75`（含预算复算注释）；⑥ `snap_dout_all` **MSB 端 +4 项**（旧 71 项逐项未动）；⑦ 几何注释订正（`75 字装配`、`后 39 个字读回恒 0`、`.SNAP_NW` 算式注、`p7bdp 的 35 个槽` 等）。⛔ **BID 行与其注释块 0 hunk** |
| 3 | `sim/p6e_pcie/tb_p6e_pcie_wrapper.v` | `c427a12f…34423e2b1`（= HEAD，LF） | `40549510…de6446af` | **+114/−79** | ① **MIR 地址常量 73 处整体下移**（`32'h13C/140/144/148` → `32'h14C/150/154/158`，机械替换逐类报数 23/9/23/16，另 `32'h14C→32'h15C` 2 处）；② 判据 9 未实现地址 `0x14C→0x15C`；③ M1-4 全字数读 `71→75`；④ **新增判据 6 的 W71..W74 四条映射断言**（force `u_app.stat_*` 生产者为 4 个互异常数 + 读回 + release）；⑤ 头部/就地订正注释 |
| 4 | `sim/p9_swc_gate/tb_p9_swc.v` | `b28bff35…c428e080`（= HEAD，= R5 值） | `be1ea6f0…282f7e62` | **+155/−23** | ① `P9_E12_PORTS(i)` 宏（单行；`P9_HAS_SWC` 下展开）；② 11 个实例接 4 端口 + `.act_id(w_aid[i])`（**全模式**可接）；③ `evs_v[11]` 槽号数组（单一来源）；④ TB 侧 4 个独立复算计数器 `M_upn/M_swac/M_req/M_pend`；⑤ `E%0d` 逐臂读数行；⑥ **W3/W4/W5/W6 判据**（仅 F/F10）+ **W6o/W6p**（仅 OFF）；⑦ 头部判据表 + `NALL=11` 陈旧字样订正 |
| 5 | `sim/p9_swc_gate/run_tb_p9_swc.bat` | `d053e9be…4b28dd9`（= HEAD `18bad423…` 的 CRLF 变换） | `67bee849…730c9d` | **+5/−0** | 汇总段新增 3 行 `findstr`（`E0..E10` 读数行 / `W3..W6` 判据行 / OFF 的 `W6o/W6p`） |
| 6-8 | `sim/p9_swc_gate/mut/{m6_v1_eq,m6b_closing_drop,m7_guard_swpend}.v` | `59f2b2c9…` / `327f130d…` / `c5c4365b…`（= HEAD） | `f06115a5…` / `af50d99b…` / `2c14f699…` | 各 **+48/−1** | **由新 RTL 重生成**（`MUTGEN OK (3 mutants)`；5 个 sub 全 `hits==expect`）—— 与 R5 轮同样的交付形态 |

**未改（明示）**：`sim/p4gates/swcg_src.f`（文件集**不变** ⇒ 注册清单与 bat 里的字面 xvlog 行仍 1:1）；`_proj_pcie/rtl/axi_regs.v`（**参数化**，逻辑无须改；仅注释 stale → 登记）；BID；读侧工具；设计件目录；台账。
补丁：`diff_app_pattern.patch` · `diff_wrapper_p4.patch` · `diff_tb_p6e_pcie_wrapper.patch` · `diff_p9_swc_gate.patch`。

---

## §2 几何推导（**双核 + 机器核**）与几何依赖逐条表

### 2.1 三条独立推导（值 = `0x15C`）

| 核 | 源（现读） | 推导 | 结果 |
|---|---|---|---|
| **核 1（权威源 RTL）** | `_proj_pcie/rtl/axi_regs.v`：`SNAP_LAST_IDX = 8 + SNAP_NW - 1`（`:206`）；`MIR_STATUS/DATA/CTRL/DMA_CNT_IDX = SNAP_LAST_IDX + 1..4`（`:214-217`）；未实现 = `MIR_LAST_IDX+1`（`:218`） | NW=75 ⇒ 快照 word 8..82（0x20..0x148）⇒ MIR = word 83..86 = **0x14C/0x150/0x154/0x158** ⇒ 未实现 = word 87 = **0x15C** | **0x15C** |
| **核 2（读侧工具口径）** | `apply_readside_bid1c.py`：阶段表逐行带 `(BID, nw, unimpl)`（`:121-129`）+ 约定注（`:130-131`）"0x1F 起 … 未实现地址 = **0x20 + 4*NW + 16**" | NW=75 ⇒ 0x20+4×75+16 = **0x15C**；`_proj_pcie/p6e_snap_check.sh:73` 的 `UNIMPL_ADDR` 同公式 ⇒ 两处工具同口径 | **0x15C** |
| **核 3（设计件 L-1）** | `DESIGN_v2.md` L-1 行逐字：**"71→75 字：MIR 四字（0x13C..0x148）在中间 ⇒ 新未实现地址 = `0x14C → 0x15C`"** | 逐字 | **0x15C** |

### 2.2 机器核（本代副本 `check_window.py`）
`check_window_e12.py`（= 原件 + `nnew_top 5→9` 一处本代常量，**原件不改**）实跑：**`PASS=96 FAIL=0` / `CHECK_WINDOW_PASS`**，关键行逐字：
`1 总字数 == SNAP_NW_P6E (项数=40, 逐项字数之和=75, NW=75)` · `3 束宽等式 == NW (14+22+3+(35-4)+5 = 75)` · `4 * 旧字未移位 (HEAD 36 项, 新表 40 项 => 新增 4 项全在 MSB 端)` · `5a 最上面 9 项 = p7bdp 槽 34/33/32/31 打头` · `5c 槽号映射 W51..W74 (24 条)` · `6 p7bdp_din 驱动项数 == SNAP_P7BDP_NW (generate 12 + 显式 23 = 35)` · `8 * 未实现地址不回绕 (addr=0x15C => word 87 < 2^7=128)` · `8c snap_base 装得下 (need=2368 < 4096)`。

### 2.3 **几何依赖件逐条表**（搜索口径 = `71 字`/`NW=71`/`0x14C`/`0x13C`/`0x140`/`0x144`/`0x148`；排除 `.claude/worktrees/**` 与 `vivado_prj/**`）

| # | 文件（现读） | 依赖形态 | 处置 |
|---|---|---|---|
| 1 | `board/wrapper_p4.v` | **硬**（`SNAP_NW_P6E`/`SNAP_P7BDP_NW`/装配/`p7bdp_din`/注释） | ✅ **本轮已改**；⛔ BID 块一字未动 |
| 2 | `sim/p6e_pcie/tb_p6e_pcie_wrapper.v` | **硬**（73 处地址常量 + 判据 9 + M1-4 + 头部注） | ✅ **本轮已改** + **新增** W71..W74 映射断言 |
| 3 | `sim/p6e_pcie/tb_p6e_pcie_counters.v` | 无几何依赖（只读 W0/W5/W16/W17/W19） | ⚠️ 仅 BID 期望值 `0x27` 与标签属构建轮（bump 时**两 TB 必须同批**） |
| 4 | `_proj_pcie/rtl/axi_regs.v` | **逻辑参数化** ⇒ 无须改；**头注释**（`:46-49`/`:56-102`/`:214-217` 例值与 §M1 段）71 字代口径 stale | 📋 **登记**（归构建轮/文档轮） |
| 5 | `_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py` | 读侧链式同步（需新增阶段行 `0x28`：nw=75 / unimpl=0x15C + 目标文件编辑） | 📋 **登记**（派单明示归构建轮） |
| 6 | `_proj_pcie/p6e_snap_check.sh`（`SNAP_WORDS` 默认 + `WLABEL` 表到 W70）· `p7b_biz/p7b_snap.sh`（NW/BID 默认 + 逐代注）· `p7b_gate4_*.sh` | 未实现地址公式自动跟，但 **NW 默认值与标签表要手改**；WLABEL 需补 W71..W74 | 📋 **登记**（读侧面，归构建轮） |
| 7 | `_proj_10g/notes/p7b_biz_win/check_window.py`（`nnew_top=5`）· `tb_biz_win.v` · `neg/axi_regs_mut_*.v` | **本代常量** + 地址硬编码 | 📋 **登记**（未注册进矩阵；本轮用本代副本出证据） |
| 8 | `sim/p6e_pcie/mut/wrapper_p4_mut_{bwire,srcinv}.v` | 由 `mut_*.py` **运行时从活 wrapper 重生成** | ℹ️ **auto-sync**（无须手改） |
| 9 | `_proj_10g/p7b_chain/sim/tb_p7b_chain.v:1521`（`"7b 0x14C reads 0 no wrap"`） | **0x14C 现在是真寄存器 MIR_STATUS** ⇒ 负控语义漂移（idle 读数仍可能 0 ⇒ **假绿**） | 📋 **登记**（需把负控地址抬到 ≥0x15C） |
| 10 | `rtl/axis_c2h_stream.v:140`（注释 "→ MIR_DMA_CNT @0x148"） | 纯注释（地址现为 0x158） | 📋 **登记** |
| 11 | `sim/f3_resync/n2_arm/wr_{on,off}/wrapper_p4*.v` | 另一 agent 目录里的被测副本（禁碰） | 📋 **登记**（本轮未触碰） |
| 12 | `sim/p4sim/P4_MATRIX_FINGERPRINT_*.txt` · `_proj_10g/notes/**` 历史件 · `agent_docs/**` · `CLAUDE.md`/`docs/modules.md`/台账 | **历史/文档记录**（描述当时那一代） | ℹ️ 不改（改它 = 篡改取证） |
| 13 | `sim/p4gates/swcg_src.f` | 编译清单（文件集不变） | ✅ 核对无须改 |

---

## §3 门读数

### A. SWC 门（8 运行）—— **全 RC=0 / `P9-SWC-GATE: PASS`**
完整 stdout = `gate_swc_e12_stdout.txt`；逐运行原件 = `gate_swc_e12_runs/run*/`（**本轮归档**；⚠️ 该门此前无归档惯例，R5 时代 run 目录已被本轮重跑覆盖，见 §6-3）。

| 运行 | 构型 | 期望红集 | 实测红集 | RC | 与 R5 差异 |
|---|---|---|---|---|---|
| **F** | 活 RTL + SWC=1 | {} | **{}** | 0 | **R 行与 R5 引用值逐字相同**（nst `5,7,7,6,6,5,5,5,5,5,5` · nclw `1,1,1,1,1,1,0,0,0,0,0` · nclwf=0 · wbad=0 · domv=0 · R9 tid=1）；**新增** E 行与 W3..W6 |
| **F10** | F + `P7B_10G` | {} | **{}** | 0 | R 行同 R5（`nst=59/61/61/59/59/59`）；E 行与 F **逐字相同** |
| **H / H10** | 未修冻结件（±10G） | {0,1,2,9,10} | 同 | 0 | 与 R5 逐字相同（含 R10 `pcv=1 nclwf=1 wbad=1`） |
| **OFF** | 活 RTL + SWC=0 | 同 | 同 | 0 | **逐臂与 H 逐字相同**（含 `[WING-VIOL]`）⇒ 常量门仍折叠点；**新增** W6o/W6p |
| **M6 / M6B / M7** | 突变件 | 全 11 / {3,4} / {10} | 同 | 0 | 与 R5 相同（M7 咬点仍在闲置翼臂） |

**E12 新增判据（F 运行）**：`W3`（`stat_up_ev == TB ev_up` 计数）· `W4`（`stat_sw_apply == TB sw_apply` 拍数）· `W5`（`req/pend` 分类同源）各 **11/11 `[ ok ]`**；`W6 E12 non-vacuous (sum srq=9>=1, sum sup=1>=1, TB ev_up=23>=1)` ✓。
**F 逐臂 E 行（DUT 4 数 = TB 复算 4 数）**：E0–E4、E6–E8：`uev=2 srq=1 sap=2 sup=0`；**E5（idle 到达）`srq=0`**；**E9（R3-1 交接）`uev=3 srq=1 sap=2 sup=1`**；E10（闲置翼）`srq=0`。读法：每臂 2 个 `ev_up`（全局起点 + 自有）各应用 1 次 ⇒ `sap=2`；同槽存活事件 = 收尾请求；idle 到达不产生请求；**异槽存活（交接）登记为 `up_pend`**。
**OFF 折叠见证**：`W6o … folded (SWC_OK=0): sum=0` + `W6p positive control: TB-observed ev_up = 23 (>0 => W6o is not vacuous)`（同一激励下的正控 ⇒ 不是空真）。

### B. p6e 全链门 —— **`PASS_ALL` / RC=0 · 148 PASS / 0 FAIL**
新增 4 条映射断言逐字通过：`W71 = 71717171` · `W72 = 72727272` · `W73 = 73737373` · `W74 = 74747474`（force 生产者节点、4 值互异 ⇒ "地址 ↔ 字 ↔ 槽"逐字证明）；`9 unimpl 0x15C => SLVERR` · `M1-5a 0x15C SLVERR` · M1-4 全 75 字读 + level 不变 · M1-0..M1-11 全过。⚠️ PASS 计数 144 → **148** = +4（就是本轮新增的 4 条）。⚠️ 渲染瑕疵（非功能性）：`W73` 行被 xsim 吃掉行首 `6 `（同 TB 既有的"chk 名走 `[1023:0]` 向量"注）。

### C. p6e counters 门 —— **`PASS_ALL` / RC=0 · 26 PASS / 0 FAIL**（无几何依赖 ⇒ 读数逐项未变；BID 期望 `0x27` 仍成立）
### D. 窗口静态核对（本代副本）—— **`PASS=96 FAIL=0`**（§2.2）
### E. 默认关退化锚门 —— **`CONT-GATE: PASS` / RC=0**，6/6 判据逐字：19 文件 A-vs-G 逐字节等价锚 · A3 差恰 {d7,d8,f7,f8}+stats I7/I8 · arm G reds==2 · reds=A13a/A13b · zero-arm · 编译源见证。运行级 RC 全同 R5（A/B/C=0 · G=1 · M1=22/M2=1/M3=2/M4=22/M5=2 errs）；`I7/I8 = 32/31704` ✓。

---

## §4 默认关（`SWC_OK=0`）退化证明
1. **锚门复跑**（§3-E）：6/6 PASS。
2. **96 dump 逐字节对照**（本轮修订 vs `fix_r5/gate_cont_r5/` 归档；4 臂 A/B/C/G × 24 文件）：**`compared=96 diffs=0`**。
3. **扩展比对**（超 R5 口径，加做）：另 28 个公共日志 —— **20 个逐字节相同**；8 个（`xs.log`/`xs_out.log` × 4 臂）差异**仅限运行元数据行**（session start / Process ID / Available Virtual / Exiting xsim at；`xs_out.log` 多一类 `**** Start of session at:` 同义行），**剥离后 8/8 相同**。
4. **门内常量级对照**：OFF 运行与 H 逐字相同 + W6o/W6p 正控。
**口径**：证明的是"**默认（`TX_SWCLOSE=0`）逐位退化**"；**不证明**板上行为不变（板上传 `1'b1`）。

---

## §5 E12 计数器语义（本轮落成的逐条口径）
| 计数器 | 事件（每拍 +1 条件） | 判读 |
|---|---|---|
| `stat_up_ev` | `ev_up`（raw 输入口）脉冲 | 与 `app_ctrl.stat_ev_up`（`0x90`）**互核** ⇒ 两数一致 = 事件确实送达 app |
| `stat_sw_req` | `ev_same_act`（同槽 + 存活，含 closing）= **E7 新行同一条件** | 收尾请求数；与 `sw_apply` 之差 = "请求了没落地" |
| `stat_sw_apply` | `sw_apply` 拍数（当拍应用 + 登记完成后应用） | 换流真的发生了几次 |
| `stat_up_pend` | `ev_other_act`（异槽 + 存活 ⇒ 进 `up_pend_r`） | A3 路径用了几次（R3-1 交接） |

**恒等式（板级一次读数即可见 I2 反例）**：每个 `ev_up` 恰落进 {当拍应用（`idle_now`）、`ev_same_act`、`ev_other_act`} 之一（三态互斥）⇒ `Δstat_up_ev == Δ(ev_up∧sw_apply) + Δstat_sw_req + Δstat_up_pend`（门里落成 W3+W4+W5，不写死常数、只要求"两数同源"）。**示例判读**：`Δup_ev=1` 而其余三项全 0 ⇒ **事件凭空消失**（I2 反例，真缺陷）；`Δup_ev=1 ∧ Δsw_apply=1 ∧ 相位仍错` ⇒ 复位被覆盖（P-3 类）。
⚠️ 全是**事件数**；32 位自然回卷（156.25 MHz 下 **27.487 s**）⇒ 判据必须 `mod 2^32` 且记原始值。
**实现选择（登记）**：① `stat_sw_req` 不计"W3 收尾字发出数"（会混入 `ev_down` 拆连收尾，失去"因换流而收尾"的判别力）；② `stat_up_pend` 不计 `SWC_OK=0` 的 legacy 登记支（计数器整块在常量门里 = 折叠前提；板构建恒 `SWC_OK=1` ⇒ 不受影响）。

---

## §6 异常与偏离（逐条）
1. 设计件计数器定义为"名字级" ⇒ 本轮落成事件式（§5），**属实现选择**；若裁定不同读法 ⇒ 改 RTL 两行 + W5 期望式（成本极低）。
2. p6e wrapper TB 的连带面比派单列举的宽（73 处 MIR 地址常量必须下移）；只改判据 9 + M1-4 会让 M1-1 起全线假红/假绿。
3. **R5 时代的 `sim/p9_swc_gate/run*/` 日志已被本轮重跑覆盖**（该门无归档惯例）⇒ 本轮把 8 个运行目录归档到 `gate_swc_e12_runs/`；**登记**：引用 R5 读数一律以 `fix_r5/gate_swc_r5_stdout.txt` + R5 报告 §3 为准（R5 原始 `xs.log` 已不可得）。
4. R5 登记的两处陈旧字样：`tb_p9_swc.v` 的 `NALL=10` 已随本轮 TB 修订**顺手订正为 11**（当年不修的理由是保 TB-sha↔stdout 绑定，本轮因新增判据本来就要重铸，明示）；bat 的 `[M6 reds] (expect all 10 arms red)` 在现读 HEAD 里**已不存在**（0x27 构建轮已改）。
5. `check_window.py` 对本代 FAIL（`nnew_top=5`）⇒ **不改原件**，用本代副本出证据（§3-D）+ 登记。
6. `SWC_OK` 折叠的**综合期性质未证**（未跑 Vivado；本轮只证行为等价 + dump 级退化）⇒ 归构建轮 synth 检查点。
7. `rtl/axis_c2h_stream.v:140` 注释 stale（0x148→0x158）⇒ 登记。
8. `tb_p7b_chain.v:1521` 的"0x14C reads 0 no wrap"负控语义漂移 ⇒ 登记。

---

## §7 未做 / 未观测
- **未跑**：Vivado（时序/资源零读数）· 板级 · 对端机 · 读侧链式同步 · p4gates 全矩阵（19 门）· `p7b_chain`/`tb_biz_win`/两个 p6e mut 门 · 其它编译 `wrapper_p4.v` 的镜像门。
- ⛔ **E12 计数器"在板上被激励"未证**（门里证的是接线+分类+折叠；**板级 W71..W74 读数未取**）。
- ⛔ **未逐门重跑**从 wrapper 派生的其它副本/镜像件（不属所有权）—— 已按 §2.3 逐条登记。
- ⚠️ **p4gates 矩阵未跑** ⇒ "矩阵 FROZEN" 本轮为空。

---

## §8 环境卫生
- **0 个残留 xsim/xelab/vivado 进程**（跑前跑后各核）。
- **跑门期间未改任何源**：8 个被改文件 mtime ≤ `23:10:53`；四轮门 stdout mtime = `23:12:22 / 23:13:41 / 23:14:11 / 23:15:18`。
- **门自生成件还原**：`sim/p7b_longsend/mut/m1..m5` 已 `git checkout --` 还原；`sim/p9_swc_gate/mut/{m6,m6b,m7}` = **本轮交付件**。
- **行尾/编码**：`.v` 全 LF；`run_tb_p9_swc.bat` = CRLF + 纯 ASCII。
- **未提交 git**；台账未写。
- **交付清单**（`_proj_10g/notes/p9_impl_e12_20261015/`）：`REPORT.md`（本件）· `diff_{app_pattern,wrapper_p4,tb_p6e_pcie_wrapper,p9_swc_gate}.patch` · `gate_swc_e12_stdout.txt` · `gate_swc_e12_runs/`（8 运行 × 5 日志 + `mutgen.log`）· `gate_p6e_wrapper_e12_stdout.txt` · `gate_p6e_counters_e12_stdout.txt` · `gate_cont_e12_stdout.txt` · `check_window_e12.py` + 其 stdout · `SHA256SUMS.txt`（51 条目）。

---

## §9 一句话状态
**E12（4 只换流门观测计数器）已按设计件落地 `rtl/app_pattern.v` `c932c3ab…`（+48/−1）并接线到快照 W71..W74（几何 71→75 字 / `SNAP_P7BDP_NW` 31→35 / 未实现地址 0x15C，三源双核 + 机器核 96/0）；SWC 门 8 运行全 RC=0（红集与 R 行读数逐字同 R5，新增 34 条 E12 判据 + OFF 折叠正控全绿）；p6e 全链门 PASS_ALL 148/0 · counters 门 PASS_ALL 26/0 · 本代窗口静态核对 PASS=96/0；默认关退化 = 锚门 CONT-GATE PASS（6/6）+ 96/96 dump 与 R5 归档逐字节全同；BID 一字未动、未构建/未上板/未提交；口径 = 现象与读数层，PASS/FAIL 裁定权在判据所有者。**

----------------------------------------------------------------

## TL 附加（2026-10-15 24:1x；独立抽核记录）

- **抽核（逐件现读）**：`rtl/app_pattern.v` = **`c932c3ab…8023582`** ✓ · `board/wrapper_p4.v` = **`bbf6e3cb…525ae47`** ✓ · BID 现读 `:4377` = `32'h00000027` **一字未动** ✓ · `SNAP_NW_P6E = 75`（`:3296`，注释含 `0x15C = word 87`）✓ · `SNAP_P7BDP_NW = 35`（`:3317`）✓ · 四计数器端口（`:102-105`，含口径注释）+ 计数块（`:561+`，含三态恒等式注释）现读在位 ✓ · 工作树 tracked 修改恰 8 件（报告清单逐条吻合）+ 在飞轮的目录（sim-fill/RV2）未混入 ✓。
- **口径**：本件不下 PASS/FAIL；"默认关退化"只证配置层（板上传 `1'b1`）；E12 计数器"板上被激励"= 未证（板级轮取数）。
- **裁定**：接受入库（8 件 + 轮目录）；**下一步 = 0x28 构建轮**（BID `:4329→`〔现读 `:4377`，行号随本轮位移〕bump + 读侧阶段 `0x28` 同步〔nw=75/unimpl=0x15C/WLABEL 补 W71..W74〕+ 19 门矩阵 + 构建 + 归档 + 定向 STA）—— ⏸ **挂起等三件在飞轮（sim-fill / RV2 / fold-5）完成**（构建窗口须零仓库写入）。
