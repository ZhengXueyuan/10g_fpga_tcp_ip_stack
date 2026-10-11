# P8-STG（16 B 字节粒度弹性暂存）—— 实施报告

**日期**：2026-10-11 · **工作树**：`D:\repo\XCKU5PMini\udp_hls_10g`
**规格**：`_proj_10g/notes/p8_mir_stg_20261011/DESIGN.md`（§4.1 实现草图 / §2 算法与容量定理 / §6 门+突变）
**本轮性质**：改 `rtl/app_rx_mirror.v` + `tb/tb_app_rx_mirror.v` + `sim/p7b_mir/**`（门/突变）+ synth 检查点
（`_proj_10g/notes/p8_stg_synth/`）。⛔ **未出位流 / 未 bump BID / 未做读侧同步 / 未烧板 / 未连 JTAG**。
⛔ 本件**不下 PASS/FAIL 裁定**、**不写"时序已解决"**、**不把"未观测到"写成"不存在"**。

## §0 一页结论

| 项 | 结果 |
|---|---|
| 选案 A 实施 | ✅ `stg_data[127:0]` + `stg_cnt[4:0]` + `sc4/keep/admit/nbmask/stg_ret/beat_pl/keep_bmask/stg_next` |
| **端口面** | **0 新增/删除**（`wrapper_p4.v` / 环 / p6e 接线 0 改动 —— 复跑实证）|
| 单元门 | **real = `PASS_ALL`**；新增 **G15–G20** + 既有 G8/G11/G13/G14/G19 残余项改 `acc_cnt_r + stg_cnt` |
| 突变 | **7 臂全 `MUTANT-CAUGHT-as-expected`**，且**红灯面性质互不相同**（见 §3.2）|
| 环门 `tb_mir_dma` | **`PASS_ALL` (checks=45)** —— **0 值改** |
| p6e 全链 | **`PASS_ALL` / `RC=0`** —— **0 值改**（116 条 PASS 行；判据与期望无一改动）|
| synth 检查点 | LUT **+432** / FF **+67** / BRAM **±0** / URAM **±0**；synth WNS **−0.371 → −0.377**、WHS **−0.661 不动** |
| 新锥 | **DP 域前 20 = 0 个 `u_mir` cell**；§4.3 点名的三条族最紧 **≥ +3.37 ns**（与 DP 最差 −0.377 隔离 ≈11×）|
| 未定项 | 见 §6（含 **两处实现 bug 的机理未定位**、p6e/环门的"0 值改"是**本轮树**的实证、后布线时序未裁定）|

## §1 改动清单

| 文件 | 行数 | 内容 |
|---|---|---|
| `rtl/app_rx_mirror.v` | **+149 / −56**（457 行）| ① 头注释**契约段重写**（详见 §1.1）；② 采集侧状态 `pend_*` → `stg_data/stg_cnt`；③ 组合逻辑 `n_cur/drain_all/pend_after/load` → `n_b/sc4/keep/admit/drop_now`；④ 新增 `nbmask`（源拍字节掩码）；⑤ `pend_sh/keep_sh` → `stg_ret/beat_pl/keep_bmask/stg_next`；⑥ 状态块改 `stg_data<=stg_next; stg_cnt<=keep+(admit?n_b:0)`；⑦ 文末"变更登记"块 |
| `tb/tb_app_rx_mirror.v` | **+438 / −19**（1071 行）| 头注释 + **G15–G20** + `bval/kmaskn/pbeatn/dense8/dense8_frz/endstream/gapw/acct_ident/wait_drain` 脚手架 + `dma_first` 首对字锚 + G18 采样器 + G20 监视器 + G8/G11/G13/G14/G19 残余项与手算数更新 |
| `sim/p7b_mir/mut/make_mutants.py` | +32 / −14 | 7 件（新增 `admit14/apos0/dropcnt/keep1`；措辞改"**至少**由 X 翻红"）|
| `sim/p7b_mir/run_tb_app_rx_mirror.bat` | 重写 | 8 臂入口（real + 7 突变），突变由 `make_mutants.py` 从**现役 rtl** 现生成 + `MUT_ALL_OK` 硬门 |
| `_proj_10g/notes/p8_stg_synth/` | 新目录 | `synth_only_ku5p.tcl` / `run_synth.bat` / `pb_query.tcl`（arm=`p8stg`）+ 全部读数件 |

哈希（本轮终态）：`rtl/app_rx_mirror.v` = `d0310dd4…aa373` · `tb/tb_app_rx_mirror.v` = `4aee89ce…8ac10` ·
`make_mutants.py` = `7140dcb2…4ce4640` · `run_tb_app_rx_mirror.bat` = `bb962ac5…f2676e5`。

### §1.1 头注释契约段重写（派单 ①②③）

- ① 删除/改窄旧句（`_proj_10g/notes/p8_board_0x20_20261011/REPORT.md` 已证旧版相位 ≠0 恒丢 50%）——
  新写法**带三条前提**：**(a)** 源一拍 ≤8 B **且** keep 顶 n 连续；**(b) 本模块对任意相位可续接**
  （= 字节粒度追加；8 B 单槽版不满足 (b)）；**(c)** 未被 FIFO 满打停。
  ⇒ 剩余丢字节来源 = **FIFO 满** + **`admit` 上限**（正常态结构不可达）。
- ② `stg_cnt` 容量界：**正常态 ≤15**（紧界，`phase=7` 轨迹 `(0,7)→(7,8)→(0,15)` 可达）/
  **满饱和期 ≤16**（= CAP，由 `admit ⇔ keep+n_b ≤ 16` 封顶）；**推导指针** = 设计件 §2.2 定理 1/2/3。
- ③ `cap_en` 中途开关残余语义：**性质不变、量变大** —— 正常态 ≤15 B（满饱和冻结时 ≤16 B），
  旧单槽版 ≤8 B；无下游按"≤8 B"设计。同段登记 `clr` 清掉的暂存字节**按定义不计 drop**。

### §1.2 逐字不变项（证"下游语义 0 改动"）

`mv` 表 · `acc_sh` 表 · 写门行 `wire wr_en = have && !fifo_full && cap_on;` · 端口表（0 增删）·
FIFO 例化（64×256）· rd 域冲锋/拆分/stash/两条读出口仲裁 · `level` 式 · `clr`/`any_drop` 路径 ·
`drop_bytes` 口径（仍一类）。

### §1.3 口径位移（判据/工具侧要跟）

**残余项 `acc_cnt_r` → `acc_cnt_r + stg_cnt`**。本元件的下游可见面里，
`_proj_pcie/p7b_biz/p7b_mir_dump.cpp` **只用 `K % 4` 前置 + 读 W70**、**不建残余恒等式**
（现读核实）⇒ **工具侧 0 改动**；设计件 §7-R3 的 `K % 4 → K % 8` 仍是既存项（正交、未动）。

## §2 实现注记（本轮抓到的自伤，全部有实测）

1. **`b7` 取错 lane（真 bug，已修）**：lane i = `[127-8i -: 8]` ⇒ `b7 = stg_data[71:64]`，
   而初版写成 `[63:56]`（= lane 8）。症状 = 每对字的**高字最高字节恒 0**
   （G2d `word_b` 读出 `008796E1` vs 期望 `B48796E1`）。
2. ⭐ **`generate for` + `(gi < keep)` 三元式合并：xsim 取不到当拍 `stg_ret`（已改用掩码式规避）**：
   定向逐拍 dump（negedge 采样、全部值已 settle）：`keep=4`、`stg_ret=04050607…` 全对，
   而 `stg_next` **恒 = `beat_pl`**（⇒ 该分支从未被选中）⇒ 数据面每拍多吞 8 B 零字节。
   **改法** = 语义逐位等价的掩码式 `stg_next = (stg_ret & keep_bmask) | (admit ? (beat_pl & ~keep_bmask) : 0)`
   （`keep_bmask` = 顶 `keep` 字节为 1，由 `keep_msk = (16'd1<<keep)-16'd1` 每比特扩 8 位）——
   同一激励下逐拍正确。**隔离复现未成功**（独立模块里 `genvar < wire` 比较、二级链、
   `always @*` reg 三种都正常）⇒ **机理未定位，只登记**；规避写法同时更省综合面积。
   ⚠️ 这正是"门上先红"的价值：**real 臂在修复前有 1100+ 条 golden 失配**。
3. **TB 记账 bug（自伤，已修）**：`pbeatn` 为"残拍接稠密"设计成**保持 valid**；
   G19d/G19e 单发使用后未 `endstream` ⇒ 同一拍被反复接收（残余 5 B 变 10 B）。
4. **G20 判据自己写反（已修）**：无效区 = **低位** `[8*stg_cnt-1:0]`（头部在 MSB）⇒ 必须用**左移**；
   初版右移 = 测有效区 ⇒ 结构性假红 6438。修正后 **全跑 0 违例**（= `nbmask` 层确实成立）。
5. **G14b2 的期望随结构变**（登记）：paced 填充停在"写被挡"那一拍后，新结构残余 = **8 B**
   （`acc=8, stg=0`；旧单槽版是 16 B）⇒ 该判据降为**下界见证**（`acc+stg ≥ 8`），
   真判据仍是 G14c 的 **512 逻辑字**。

## §3 门读数

### §3.1 real 臂（`MIRROR-GATE-VERDICT: PASS-as-expected` / `APP_RX_MIRROR_GATE: PASS_ALL`）

| 门 | 读数（关键） |
|---|---|
| G2..G5/G9/G12 | 手算锚逐条 PASS（`F0C3D22D`/`B48796E1`/`E19687B4`/`2DD2C3F0`/`78691E0F`/`F01E0FB4`/`691E0F3C`…）|
| G13 (phase 0 dense) | `drop=0` · `gnt=600` · `dword_mis=0` · 首对字锚 `2DD2C3F0E19687B4` ✓ |
| **G8** (300 拍无排空) | `d_drop = 328`（手算 ✓）· 饱和态 `stg=16 / acc=8` ✓ · `level=511` ✓ · 排空 **518 字** · 恒等式 ✓ |
| G11/G14 | 恒等式 ✓ · G14 `drained=512`（冻结不复制）✓ |
| **G15** (残拍 4 B + 600 背靠背) | `offered=4804` · `d_drop=0` · `gnt=600` · `mis=0` · `resid=4` · 首对锚 ✓ |
| **G16** (4 帧长 × 6 帧 × 2 变体) | **8/8 全绿**：`d_drop=0` · `mis=0` · `gnt` 逐档对（1077/1095/1102/1107）· 恒等式 ✓ |
| **G17** (phase 1..7) | **7/7 全绿**：`d_drop=0` · `mis=0` · `gnt=200` · 首对锚（相位无关）✓ |
| **G18** ⭐ 最坏轨迹锚 | 采样 idx=0：**`(0,7) → (7,8) → (0,15) → 15 稳态`**、`max=15`、`d_drop=0` —— 与设计件 §2.2 定理 2 **逐字吻合** |
| **G19ab** 满→释放沿 | 饱和丢 `328` + **释放沿恰丢 1 拍（8 B，计入）** = 合计 **336** · 排空 518 字 · 恒等式 ✓ |
| **G19c/d/e** | 冻结期 `stg/acc/level/offered/drop` 全冻 ✓ 解冻恒等式 ✓ · `clr` 清零 ✓ + 新字节锚 ✓ · `tlast` 不 flush ✓ |
| **G20** 结构性不变式 | **0 违例**（`stg_data` 无效位恒 0 —— `nbmask` 层的实测背书）|

### §3.2 突变臂（7/7 `MUTANT-CAUGHT-as-expected`，红灯面**性质互不相同**）

| 臂 | 改哪一行 | FAIL 数 | 红灯面（打的性质）|
|---|---|---|---|
| `mut_gate`（**锚存活**）| `wr_en = have && cap_on;` | 16 | G8b/G8e/G8h/G19a2/G19b1/G19b4/G14b **恒等式 + 饱和锚 + 被握字** = **静默丢字**类 |
| `mut_order`（**锚存活**）| `4'd2: mv = {48'd0, b0, b1};` | 9 | G4c/G5c **手算锚** + G16(1470/1477)/G17(ph2/6) 逐字 = **字节序**类 |
| `mut_cap4`（**锚移 1 行**）| `kk` 上限钉 4 | 73 | G13/G15/G16 的 `d_drop`+`gnt`+golden = **4 B/拍结构上限复活**类 |
| ⭐ `mut_admit14`（新）| `<= 5'd14` | 19 | **G18 轨迹断（max=8，无 15）** + **G17 ph=7** + **G16(1477)** +（**额外**）G8/G19 饱和环 = **容量紧界差 1** 类 |
| ⭐ `mut_apos0`（新）| `5'd0: beat_pl = {xbeat[55:0], xbeat[63:56], 64'd0};` | 55 | G2/G3/G4/G5 手算锚 + G12/G13/G15/G17 golden+首对锚 = **追加位置**类 |
| ⭐ `mut_dropcnt`（新）| `else if (1'b0 && drop_now)` | 7 | G8b/G8c/G19b1/G19b3 + 恒等式 = **丢字节不计数（静默丢）**类 |
| `mut_keep1`（可选臂）| `keep = … + 5'd1` | 163 | 记账全错（level/手算锚/恒等式）类 |
| —— | 锚唯一性 | —— | 7 件**各恰好 1 处命中**（`MUT_*_HITS = 1` ×7，`MUT_ALL_OK`）|

⭐ **与设计件 §6.2 预验的一处差异（登记）**：设计件预测 `mut_admit14` **只**由 G18/G17(ph7)/G16(1477) 翻红；
实测**另有 G8/G19 的满饱和构造**翻红（`stg_cnt` 只到 8、丢 336 vs 328、排空 516 vs 518）——
因为 CAP 同时界定**满饱和环**，而设计件的模型预验没跑 G8 那条构造。方向 = "**至少**由 … 翻红" ✓。

### §3.3 复跑三支（契约未变 ⇒ 期望原则上不该变）

| 门 | 结果 | 值改 |
|---|---|---|
| 单元门 real | `PASS_ALL` | 新判据见 §3.1（G8 手算数随容量界变：336→328 / 516→518 —— 设计件已预告）|
| 环门 `tb_mir_dma` | `PASS_ALL (checks=45)` | **0 值改** |
| p6e 全链 | `PASS_ALL` / `RC=0` | **0 值改**（`MIR_*` 断言与全部 PASS 行无一条改动）|

## §4 synth 检查点（`_proj_10g/notes/p8_stg_synth/`，只读配方照抄 + arm=`p8stg`）

**同流程 A/B（pre-place synth-only；与后布线读数不可直接比大小）**：

| 项 | `p8mir8b`（0x20 源） | **`p8stg`（本轮）** | Δ |
|---|---|---|---|
| CLB LUTs | 84,162 | **84,594** | **+432** |
| CLB Registers | 79,080 | **79,147** | **+67** |
| Block RAM tile | 354 | **354** | **0** |
| URAM | 0 | **0** | **0** |
| DSP | 4 | 4 | 0 |
| synth WNS / WHS | −0.371 / −0.661 | **−0.377 / −0.661** | −0.006 / 0 |
| `M1SYNTH_MIR_PINS` | 19,090 | **21,829** | +2,739 |
| `M1SYNTH_MIR_IMPORTED` | 1 | **1** | — |
| **DP 域（`g_hw.clk_out0`）最差** | −0.371 / lvl 22 / `u_tcp_tx/FSM_sequential_rx_state_reg[0]/C → u_app/stg_reg[0]/CE` | **−0.377 / lvl 22 / 同一宿主对** | −0.006 |

**DP 域前 20 是否出现新锥**：**`grep -c u_mir dp_worst_p8stg.rpt = 0`** —— 前 20 全是**旧族**
（`u_tcp_tx/FSM_sequential_rx_state_reg[0]/C → u_app/stg_reg[*]/CE`，lvl=22）。**新锥一条都没进**。

**§4.3 点名三条族的定向读数（pre-place，`pb_query` 新 tag）**：

| 族 | 读数 | 与 DP 最差（−0.377）的隔离 |
|---|---|---|
| ① `stg_cnt → … → u_fifo` | FROM `stg_cnt` **+3.498**（lvl 8）；TO `u_fifo/mem` **+3.367**（lvl 8，宿主 `acc_cnt_r_reg[0]/C`）| **≈3.74 ns ≈ 10.9×** |
| ② `acc_r/acc_cnt_r → acc_sh → acc_next → fifo din` | FROM `acc_r` **+5.194**；TO `acc_r` **+3.543** | ≥3.92 ns |
| ③ `stg_data → stg_ret/beat_pl → stg_data` 自环 | FROM `stg_data` **+4.662**；TO `stg_data` **+2.176**（lvl 13）| ≥2.55 ns |
| M1 面最紧（本流程内）| **+2.147**（`u_udp_split/u_uf/wptr_reg[1]/C → u_mir/stg_cnt_reg[4]/D`，lvl 13）| **≈2.52 ns ≈ 6.7×** |
| （对照）pcie 域最差 | +1.061（lvl 8，需求 4.000）| 不同域 |

⛔ **读法纪律**：① 本表是 **synth/pre-place**，**逐档不可与 0x20 后布线的 `+0.515 / 3.34×` 比大小**
（#66：WNS 是不同对象）；② `−0.371 → −0.377` 是**两个不同网表之间**的位移，**没有拆刀臂 ⇒ 不归因**
（#63 / 全局纪律）；③ 真正判决 = **后布线构建**（本轮**未做**，不出位流）。

## §5 口径声明

**逐字不变**：端口表（0 增删）· `mv` 表 · `acc_sh` 表 · `wr_en` 行 · FIFO 例化 · rd 域（冲锋/拆分/stash/双出口仲裁）·
`level` 式 · `clr`/`any_drop` · `drop_bytes` 口径（仍一类）· 工具侧（现读核实 `p7b_mir_dump.cpp` 不建残余恒等式）。

**变了**（逐条登记）：
① 采集侧暂存 8 B 单槽 → **16 B 字节粒度**（相位 ≠0 的恒丢 50% 消失 —— 单元门 G15/G16/G17 是直接牙）；
② **残余项 `acc_cnt_r` → `acc_cnt_r + stg_cnt`**（判据/文档层口径位移；工具无依赖）；
③ 满饱和期的暂存吸收量 8→16 B、被握字的残余姿态 `(8,8)`→`(8,0)`（G8/G14 手算数随之改，见 §3.3）；
④ `cap_en` 跨暂停残余 8→15 B（性质不变）；⑤ `clr` 清掉的暂存字节按定义不计 drop（同旧版 `pend`）。
**未变但需注意**：`MIR_STATUS.ver` **未 bump**（本设计不改位语义/地址表）；`K % 8` 前置**未改**（设计件 §7-R3 正交项）。

## §6 未定项（不许当已答）

1. **§2-2 的 xsim 现象机理未定位**（`generate`+genvar 三元式取不到当拍 `stg_ret`；隔离复现失败）——
   已用**语义等价**的掩码式规避并有逐拍实证；**未在综合面验证**过原写法（也不需要）。
2. **后布线时序未裁定**（本轮只有 synth/pre-place；`0x20` 的 DP 全局最差 `+0.154` 与本轮读数不可直接比）。
   **M1 族是否被新锥吃掉余量** ⇒ 只能由**后布线构建**回答（设计件 §4.3 的处置建议仍待执行）。
3. **板级未做**（不动 BID / 不烧板）⇒"相位 ≠0 遇帧内密集源不再丢字节"在**板级**上仍是**未测**。
4. `mut_admit14` 的**额外红灯面**（G8/G19 饱和环）与设计件 §6.2 的预验**不一致**（方向是"至少"✓，
   但预验清单**不全**：设计件的模型没跑 G8 那条构造）。
5. 环门/p6e 的"**0 值改**"是**本轮树**的实证；⚙️ 若下游把残差恒等式写进 p6e/TB 的白盒断言，
   **同一改动会波及**（本轮现读未发现这样的断言）。
6. ⚠️ **`nbmask` 是相对设计件 §4.1 草图的加严**（草图直接用未掩码 `xbeat`）—— 设计件 §2.1-② 声称的
   "无效位恒 0" 在草图上**不成立**（无效低字节会以垃圾值留在无效位）；本实现补掩码后才成立，
   G20 因此有牙。**此为规格级偏离，已写进 RTL 头注释与变更登记块。**
