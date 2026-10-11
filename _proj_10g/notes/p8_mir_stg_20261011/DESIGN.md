# P8 镜像「相位鲁棒」弹性暂存 —— 设计件 (DESIGN)

**日期**：2026-10-11（本轮） · **工作树**：`D:\repo\XCKU5PMini\udp_hls_10g`（HEAD = `db955fc`）
**本件性质**：**纯纸面设计件 + 只读复核**。⛔ 未改任何 `rtl/` `tb/` `board/` `sim/` 文件；⛔ 未跑 Vivado/xsim；
仅跑**只读 Python 模型**（本机 anaconda，脚本见附录 A，可重跑）。
**口径**：本件**不下 PASS/FAIL 裁定**、**不写「时序已解决」**；每条结论标 【事实】/【推断】/【估算】。
行号/内容一律**本轮现读**（`rtl/app_rx_mirror.v` sha256 `821d7593cbfd7fab7a24a6d665ccd6f0ed05a31efc757bcf73560e712b136519`；
`tb/tb_app_rx_mirror.v` sha256 `fe813267864a525e46bba92e744ac76e9903a6ba685b70f449a5a1faeb5b0b05`）。
⚠️ **板级 A/B 在飞**（`_proj_10g/notes/p8_board_0x20_20261011/` 本轮现读为未跟踪的新目录）——
本件的**触发面可达性**结论会随那一轮改变（见 §7-R1 的搁置分支）。

---

## §0 一页结论

| 项 | 结论 |
|---|---|
| **选案** | **A**：把 8 B 单槽 `pend` 换成 **16 B 字节粒度弹性暂存**（`stg_data[127:0]` + `stg_cnt[4:0]`），每拍 `kk = min(8−acc_cnt, stg_cnt)` 从头部搬进累加器、当拍源拍顶 `n_b` 字节**追加到尾部**；`admit ⇔ keep + n_b ≤ 16`（`keep = stg_cnt − kk`）|
| **容量上界**（我自己重算，不是照抄审查）| **正常态 `stg_cnt ≤ 15`**（紧界：`phase=7` 轨迹可达、且 CAP=14 时该轨迹必丢）；**FIFO 满饱和期可达 16**（= CAP，由 admit 规则封顶）。⇒ **CAP = 16 足**（= 128 位整数宽度，1 B 裕量）|
| **能否 8 B/拍** | **能，且对任意相位/任意逐帧长度**：模型对 `phase=0..7` × 帧长 `{1436,1460,1470,1477}`（稠密、含帧间 0/1/2/4 拍间隙）× 600 拍背靠背 = **全 0 丢**；BFS 穷举（对抗性 `n`+`full`）复核：`full=0` 且未经历满饱和的**全部 79 个可达态**里 `keep+n ≤ 15 ≤ 16` 恒成立 |
| **代价**（【估算】，无 EDA）| FF **+61**（算得：+128 `stg_data` +5 `stg_cnt` −72 `pend_*`）；LUT **≈ 500–900**（【估算】；参照上一轮同类改动 synth 面实测 +672）；BRAM/端口/读侧/环 **0 改动** |
| **DP 时序** | **未评估、不裁定**。要定向看的三条锥与"现役最紧 M1 族"见 §4.3（`0x20` 构建读数：DP WNS `+0.154` = 全局最差；M1 族 DP 隔离度 `+0.515` = 3.34×）|
| **门** | 新增 **G15–G19**（相位建立+背靠背 / 帧长 ≢0 mod 8 长流 / phase 1..7 扫描 / **最坏轨迹锚** / FIFO 满·cap_en·clr 交叉）+ 既有 G13/G8/G11 复跑（**身份式残余项要改**：`acc_cnt → acc_cnt + stg_cnt`）|
| **突变** | 既有三件 `gate`/`order` 锚点**存活**、`cap4` 锚点**移一行**；新增 `admit14`/`apos0`/`dropcnt`；**每件恰 1 行、恰 1 处命中**（表见 §6.2）；模型级已预验每件的红灯面 |
| **悬而未决** | ① 板级 A/B（触发面可达性）；② A′（满态恢复沿精化）取舍；③ DP 时序；④ p6e/工具同步（`K%8`）；⑤ `cap_en` 中途开关的暂存残余量 8→15 B（登记）|

---

## §1 缺陷复核（我独立重算，与 REVIEW 对齐 + 两处比 REVIEW 更细）

### 1.1 机制（【事实】· 源码 + 循环级模型双证）

现役（0x20 已修 8 B/拍版，`rtl/app_rx_mirror.v:154-164`）：
`kk = min(n_cur, room)`、`drain_all = (kk == n_cur)`、`pend_after = pend_valid && !drain_all`、
`load = src_beat && !pend_after`、`drop_now = src_beat && pend_after`。
⇒ **新拍只有在「本拍把暂存整块搬空」那一拍才被接收**。当 `n_cur=8 > room(=8−acc_cnt)`（相位 ≠0）时：
本拍只搬 `room` 字节、**同拍到来的整个源拍被拒收**；且下一拍 `room=0 ⇒ kk=0 ⇒ drain_all` 仍为假
（`0 == 8` 为假）⇒ **再拒一拍**，直到字被写走才轮到新拍。稳态 = **2 拍吃 1 拍**（丢 50%）。
**它只在 `acc_cnt == 0` 时不存在** ⇒ 与头注释 `:16-18` 的"结构吞吐类对 ≤8 B/拍源不可达"**冲突**
（该句范围说宽了 —— 这正是审查 §⑤-1 的判词，我复算成立）。

### 1.2 我的模型读数（与 REVIEW 逐条对齐；脚本可重跑）

| 用例 | OLD（现役 0x20 逻辑） | REVIEW 原件 | 对齐 |
|---|---|---|---|
| 1×4 B 残拍 + 60×8 B 背靠背 | `drop=240 / offered=484` | `240/484` | ✓ 逐字 |
| `phase=1..7` 各自 | `drop=240`（对 480 个 8 B 拍 = **恰好 0.500**）| "丢幅恒 0.500" | ✓ |
| `phase=0` | `drop=0` | 0 | ✓ |
| 6 段 1460 B（=8×182+4）稠密 | `drop=2184/8760 = 24.93%` | `2184/8760 = 0.249` | ✓ 逐字 |
| 同流稀疏 1 拍/9 拍 | `drop=0` | 0 | ✓ |
| **板级签名复现** | 拍序列 = `TTD TDTDTD…`（首 2 收后**严格交替**）| 板级"偶数组全收奇数组全丢" | ✓ 形态一致 |

⭐ **两处我的增量（REVIEW 未给）**：

1. **触发面比"拍流密集"更锐**（【事实】· 模型）：**必须是「拍与拍背靠背」（1 拍/周期）**。
   把全部拍按 **1 拍/2 周期**拉稀 ⇒ `drop=0`（旧版自愈：暂存 2 拍内重新排空）。
   但**帧内 burst 就够了**：1460 B 帧之间插 0/1/2/4 拍间隙 ⇒ 丢幅**恒 24.93% 不变**（帧内 182 拍背靠背）。
   ⇒ 判据措辞应为"**存在连续 ≥2 拍的背靠背段且相位 ≠0**"，不是"平均速率高"。
2. **板级 A/B 臂的效应量（预测）**：`paylen=1470`（=8×183+6，相位 6）稠密 ⇒ OLD 预测 **`drop = 3670/8820 = 41.6%`**；
   `paylen=1472`（相位 0）稠密 ⇒ **`drop = 0`**。⇒ 两臂分离度极大（0% vs 41.6%），比审查建议的 1460 档（24.9%）更锐。

### 1.3 两路源的稠密度取证（【事实】· 源码现读）

镜像 tap 由 `MIR_CTRL[2]=src_sel` 选（`board/wrapper_p4.v:3799-3803` 现读）：
`sel=0 → app_udp_rx_*`（UDP app RX 口）/ `sel=1 → app_rx_*`（TCP app RX 口）。两路的**消费者**（app 校验器）都按
`tvalid && tready` 采样驱动镜像 ⇒ 稠密度 = 消费者的 `tready` 节奏：

- **TCP 路**：`rtl/app_pattern.v:608` `assign rx_tready = (rxs == 2'd0);`，且 `:611-620` 的 `P7B_10G` 宽路径注释**逐字**写着
  "**1 拍/字: 宽路径保持 rxs==0（不进比较态）⇒ rx_tready 恒 1 ⇒ 背靠背**"（仅尾字/0 长字回落串行路径）。
  ⇒ **满 8 B 拍 = 稠密** ✓。
- **UDP 路**：`rtl/app_udp_pattern.v:658` `assign rx_tready = !nx_v || cmp_ld_w;`（宽路径前瞻/比较装载让位）⇒ 满拍可背靠背 ✓；
  ⭐ 板级旁证 = `0x1F` 位流读数"偶数组全收奇数组全丢"（旧版对**稀疏**源不丢 ⇒ 该口当时确实是 1 拍/周期量级的源）。
- ⚠️ **仍属【推断】的一环**：以上是"消费者会给 tready"的源码面 + 旧板级旁证；**1470 臂上"源真的稠密"没有单独仪器**
  ⇒ 若 1470 臂出现"0 丢"，先查稠密度再下结论（见 §6.3 搁置判据）。

---

## §2 算法与不变量（本设计件核心）

### 2.1 精确逐拍更新式（规格级；所有推进在 `else if (cap_on) begin … end` 内，`clr_pulse` 优先）

```
src_beat   = s_tvalid && s_tready && cap_on                 // snoop: 只采样, 永不驱动
n_b[3:0]   = src_beat ? pop8(s_tkeep) : 4'd0                // 当拍源字节数 0..8
sc4[3:0]   = (stg_cnt >= 5'd8) ? 4'd8 : stg_cnt[3:0]        // min(stg_cnt, 8)
room[3:0]  = 4'd8 - acc_cnt_r
kk[3:0]    = (sc4 < room) ? sc4 : room                      // c: 本拍搬进累加器的字节数 0..8
keep[4:0]  = stg_cnt - {1'b0, kk}                           // 搬走后留在暂存的字节数 0..16
admit      = src_beat && (keep + {1'b0, n_b} <= 5'd16)      // ⭐ 追加能否装下 (容量定理见 2.2)
drop_now   = src_beat && !admit
acc_have[3:0] = acc_cnt_r + kk
have       = (acc_have == 4'd8)
wr_en      = have && !fifo_full && cap_on                   // ⭐ 本行与现役**逐字不变**

// 数据面 (组合): 源字先 ^XORC, 再按 keep 定位到尾部
xbeat      = s_tdata ^ {8{XORC}}
stg_ret    = stg_data << 8*kk                               // 9 路 case, 128 位 (头部搬走 kk 字节)
beat_pl    = {xbeat, 64'd0} >> 8*keep                       // 17 路 case, 128 位 ⇒ 源拍顶 n_b 字节落在 lane keep..
stg_next   = lane i: (i < keep) ? stg_ret[i] : (admit ? beat_pl[i] : 8'd0)      // 16 个 8 位 lane
// (等价表述: stg_next = (stg_ret & mask_hi(keep)) | (admit ? beat_pl : 0), mask_hi 顶 keep 字节为 1)

// 寄存器推进
stg_data  <= stg_next
stg_cnt   <= keep + (admit ? {1'b0, n_b} : 5'd0)            // ≤ 16
acc_r     <= wr_en ? 64'd0 : (kk != 4'd0 ? acc_next : acc_r)// acc_next = acc_r | acc_sh(kk, acc_cnt_r) —— 旧表**逐字不变**
acc_cnt_r <= wr_en ? 4'd0   : (kk != 4'd0 ? acc_have : acc_cnt_r)
// 丢字节块: else if (drop_now) begin drop_bytes <= drop_bytes + {28'd0, pop8(s_tkeep)}; any_drop <= 1'b1; end
```

⭐ **实现层的两个关键观察**（决定了代价与改动面）：

1. **搬走侧（读侧/累加器侧）零改动**：`mv` 表（取暂存头 kk 字节，b0 在 LSB）与 `acc_sh` 表（按 `acc_cnt_r` 上移）
   **输入只换成 `stg_data` 的头部字节** —— 只要把 `b0..b7` 重定义为 `stg_data[127:120..63:56]`，**两张表连行文都不用动**。
2. **`stg_next` 的合并 = 16 个字节 lane 的二选一**（`i < keep`），**其中"不追加"分支直接灌 0** ⇒ 寄存器**无效位恒 0**
   （可归纳证明）= 免费得到一条结构性断言（TB 可 hierarchical 断言 `stg_data[127 : 8*stg_cnt] == 0`），
   也让"垃圾位被后续移位搬进有效区"这一整类担心**不成立**。

### 2.2 容量定理（我自己重推 + 机器穷举复核）

**设定**：`acc_cnt_r ∈ [0,8]`、`stg_cnt ∈ [0,16]`、`room = 8 − acc_cnt`、`kk = min(stg_cnt, room)`、`admit ⇔ keep + n ≤ CAP`。
**记**：`(a, s)` = 周期开始时的 (acc_cnt, stg_cnt)。

**定理 1（不变量，正常态）**：若 FIFO 不满且**未经历"满饱和"**，则可达态满足
**(a ≥ 1 ⇒ s ≤ 8)**，且 `stg_cnt ≤ 15`。
*推导*：本拍 FIFO 不满 ⇒ 若 `kk = room`（恰好填满累加器）则 `have=1 ⇒ wr_en=1` ⇒ `a' = 0`；
若 `kk < room` ⇒ `kk = min(s,8)` 且 `a' = a + kk < 8`，此时 `kk = s`（因为 `s < room`）⇒ `keep = 0` ⇒ `s' = n ≤ 8`。
**⇒ 任何一拍结束后，要么 `a' = 0`，要么 `s' = n ≤ 8`** ⇒ 下一拍开始时 `a ≥ 1 ⇒ s ≤ 8`。
于是本拍的追加需求 `keep + n = max(s − room, 0) + n`：
`a ≥ 1 ⇒ s ≤ 8`；更强地，`a ≥ 1 ⇒ room = 8 − a ≥ 1` ⇒ `keep = max(s − room, 0) ≤ max(8 − room, 0) ≤ 7`
（`s ≤ room` 时 `keep = 0`）⇒ **需求 ≤ 7 + 8 = 15**。`a = 0 ⇒ room = 8 ⇒ keep = s − 8 ≤ 8` ⇒ 需求 ≤ 16。
⇒ **正常态紧界 = 15**，且 **CAP=15 即可零丢**。

**定理 2（紧性 witness）**：`phase=7` 的**可达轨迹**必然达到需求 15：
`n=7` 残拍（`a=0, s=0` ⇒ `kk=0, keep=0` ⇒ 收下 ⇒ `s'=7`）→ 背靠背 8 B：
`(0,7)`: `kk=7, keep=0`, 需求 8 ⇒ `a'=7, s'=8` → `(7,8)`: `kk=1, keep=7`, **需求 15** ⇒ `a'=0（字被写走）, s'=15` →
`(0,15)`: `kk=8, keep=7`, 需求 15 ⇒ 自持（`s≡15`, 每拍吐 1 字）。
⇒ **CAP=14 时该轨迹在第 2 步丢**（模型实测：cap=14 ⇒ 套件总丢 976 B；cap=15/16 ⇒ 0）。

**定理 3（满态与恢复沿）**：FIFO 满时 `wr_en=0` ⇒ `a=8` 挂住、`kk=min(0,s)=0` ⇒ `s` 每拍 +8 涨到 **CAP=16** ⇒ 再来的拍 `keep+n = 16+8 = 24 > 16` **被计丢**（= 「排空不够快」类）。
释放后（FIFO 不满那拍）：**A 变体** `kk` 仍取 `min(8−a=0, s)=0` ⇒ 该拍源拍 `s+n` 可到 24 > 16 ⇒ **恢复沿可再丢 ≤1 拍**；
**A′ 变体**（见 §4.4-iv）在释放拍同时"写走挂住的字 + 把 `min(8,s)` 字节装进清空的累加器" ⇒ 需求退回 ≤16 ⇒ **零丢**。

**机器复核（BFS 穷举，对抗性输入）**（【事实】· 附录 A 脚本 ⑥）：
- 状态空间 `(a, s, full)`，每拍 `n ∈ {0..8, 无拍}` × `full ∈ {0,1}` 全取值：A 变体 **194 态 / A′ 192 态**；
- `max_s = 16`（两变体，均只在满饱和期）；
- **`full=0` 且源拍被拒的实例：A = 72 个（全部满足 `a=8 ∧ s>8` = 满态恢复沿态）；A′ = 0 个** ⇒
  **A′ 把"只要本拍 FIFO 不满，源拍必被接收"变成定理**（此时 CAP=16 **恰紧**）。
- **未经历满饱和的可达态 = 79 个，`max_s = 15`，最大追加需求 = 15** ⇒ 与定理 1 的紧界一致 ✓。

**各档 `stg_cnt` 上界汇总表**（Q1 点名要求）：

| 工况 | `stg_cnt` 上界 | 依据 |
|---|---|---|
| `phase = 0..6` + 饱和 8 B/拍 | **≤ 8**（实测轨迹：8 或更小；`(0,s<8)→` 型）| 模型 + BFS 可达集 |
| `phase = 7` + 饱和 8 B/拍 | **15**（唯一触顶档：`(0,7)→(7,8)→(0,15)`）| 定理 2 + BFS |
| 帧长 1436/1460/1470/1477 稠密长流（任意相位演进）| **≤ 15**（同上，相位只经 0..7 八档）| 模型全套 0 丢、BFS |
| FIFO 满饱和期 | **16**（= CAP，admit 规则封顶）| 定理 3 + BFS `max_s=16` |
| 满态恢复沿（A 变体）| 仍 ≤ 16，但可发生 ≤1 拍拒收（计入 drop）| 定理 3 + BFS 72 实例 |
| 满态恢复沿（A′ 变体）| ≤ 16 且**零拒收**| BFS A′ = 0 实例 |

### 2.3 「keep 合同」在哪些地方承重（Q1 点名要求；前提 = **顶 n 字节有效、非连续 keep 不在合同内**）

| # | 使用位置 | 承重方式 |
|---|---|---|
| ① | `n_b = pop8(s_tkeep)` | 计数 = popcount；有洞时计数仍对而**位置**错 |
| ② | `beat_pl = {xbeat,64'd0} >> 8*keep` 落到 lane `keep..keep+8` | 只有"**顶**连续 n 字节"才能靠一次移位贴到尾部；有洞 ⇒ 无效字节落进有效区 |
| ③ | 全域 ^XORC（含无效低字节） | 安全**只因**无效字节永不进有效区（顶对齐 ⇒ 无效在低位 ⇒ 移位后落在 `≥ keep+n`） |
| ④ | `mv`/`acc`/FIFO 写 = 纯字节流切 8 B 字 | 流必须无洞，否则字内容错 |
| ⑤ | `stg_cnt` 账 = 字节数（lane 数与内容解耦） | 有洞 ⇒ 计数与布局失同步（②的放大） |
| ⑥ | TB/golden（`tb:135-165`）| 按 `tv_keep[bi]` 逐位收集 ⇒ 同样假定顶连续 |

生产者侧合同 = `rtl/app_udp_pattern.v:416-428 kmask8`（顶 n 置 1）与 `rtl/app_pattern.v` 的 `bmask64/ljust8`；
全仓两个生产者都按此生成（模块头 `:28-29` 已声明）。⛔ 若未来引入"带洞 keep"的源，本设计（与现役版）**都在合同外**。

---

## §3 与现有语义的逐条兼容表（Q2 点名要求）

| # | 语义 | 旧（现役）| 新结构 | 判定/证据 |
|---|---|---|---|---|
| 1 | **snoop 合同**（只读 `s_tready`、永不驱动握手）| 只采样 | 只采样（`src_beat` 仅被读）| ✓ 逐字不变 |
| 2 | **`clr`**（toggle ⇒ dp 域恰 1 脉冲）| 清 `pend_valid/pend_data/pend_keep/acc_r/acc_cnt_r` + `any_drop`；`drop_bytes` 不归零 | 清 `stg_data/stg_cnt/acc_r/acc_cnt_r` + `any_drop`；`drop_bytes` 不归零 | ✓ 同性质。**语义登记**：暂存里被清的字节**按定义丢弃**（"清打包态"），不计 drop —— 与旧版清 `pend` 残余**同款** |
| 3 | **`clr` 的排空式冲刷（rd 域）**| 读到空为止，不碰 FIFO 复位 | 不涉及采集侧 | ✓ 0 改动 |
| 4 | **`cap_en` 冻结** | 状态块 `else if (cap_on)` ⇒ 整块不推进（不暂存/不打包/不写/不计丢）；FIFO 里已有字照读；`clr` 不受其影响 | 同（块结构不变）；暂存与累加器**都冻结**（不涨不降）| ✓ 与头注释 `:41-44` 逐字一致："冻结期不写、被握住的字节留在暂存" |
| 5 | **中途开/关 `cap_en`** | 累加器残余跨暂停拼接（已知语义边界）| 同，且暂存残余（**正常态 ≤15 B、满饱和冻结时 ≤16 B**，旧 ≤8 B）也跨暂停拼接 | ⚠️ **登记**（Q2 点名）：性质不变、**量变大**；"正确用法 = `clr` → `cap_en=1` 后不再动"仍然适用。**无下游依赖**（无人按"≤8 B"设计） |
| 6 | **FIFO 满** | `wr_en` 被 `!fifo_full` 挡 ⇒ 字挂累加器（`acc_cnt=8`）；暂存涨；暂存满则拒收（计 drop）| 同（写门逐字不变）；暂存弹性 **8→16 B**（满态多吸收 1 拍）；拒收条件 = `keep+n>16` | ✓ 同类；明细见 §2.2 定理 3 |
| 7 | **`tlast` 不消费** | 无 tlast 逻辑 | 无 tlast 逻辑 | ✓（本设计**不引入**任何 tlast 分支）|
| 8 | **空态哨兵** | rd 侧按 `empty` 选路（`0x5A5A5A5A` 由消费者选）| 不碰 rd 侧 | ✓ |
| 9 | **`level`**（`2×dbg_occ_r + stash_v`，单位 32 位字）| 只少报（`pend`/`acc` 里的字节不计）| 只少报**方向不变**（新增不可见量 = `stg_cnt` ≤ 16 B = ≤2 逻辑字；加 acc ≤ 1 字 ⇒ 最多多欠报 3 字）；clamp 511 仍只少报 | ✓ **核对结论：仍只少报、永不多报**（`level` 只由 FIFO+stash 构成，二者都是真实可读量）|
| 10 | **`drop_bytes` 口径** | 只剩"FIFO 满"一类（旧头注释 `:39-40`）| **仍只有一类**：暂存装不下当拍源拍。**结构性证明**：只要 FIFO 不满且未经历满饱和，`admit` 恒成立（§2.2 定理 1 + BFS）⇒ **不引入第二类**。按字节计、**整拍拒收**（不部分接收）| ✓ 口径不变；`+1 bit sticky` `any_drop` 不变 |
| 11 | **粒度与字节账** | 输出 8 B 字；`K % 8 == 0` 前置；账 = `offered == 8×字数 + drop + acc_cnt` | 同上，**唯一口径位移**：残余项 = `acc_cnt + stg_cnt` | ⚠️ **门/工具侧的身份式要跟着改**（§6.1 G19b、§7-R3）|
| 12 | **读侧/`MIR_DATA`/`stash`/DMA 2 字口/环/`level` 单位** | —— | 逐项 0 改动 | ✓（本设计只在采集侧内部）|
| 13 | **端口面** | —— | **0 新增/删除端口**（与上一轮 +234 行含新端口不同）| ✓ wrapper/环/p6e 接线预计 0 改动（复跑确认，§7-R7）|
| 14 | **`MIR_STATUS.ver`** | 现 `4'd3` | 本设计**不改位语义/地址表** ⇒ 按既定规则不 bump；但上一轮已改"K%4→K%8"这一**主机可观测契约**且未裁定 | ⚠️ 转登（不在本件裁定范围）|

---

## §4 实现式与代价

### 4.1 RTL 草图（规格级，供实施者/突变生成器逐字对齐）

```verilog
    // ---------------- 采集侧状态 (dp 域) ----------------
    reg  [127:0] stg_data;       // ⭐ P8-STG: 16 B 弹性暂存 (head 在 MSB; 顶部 stg_cnt 字节有效; 无效位恒 0)
    reg  [4:0]   stg_cnt;        // 0..16
    reg  [63:0]  acc_r;          // 累加器 (与现役**逐位同义**)
    reg  [3:0]   acc_cnt_r;      // 0..8

    wire [3:0] n_b    = src_beat ? pop8(s_tkeep) : 4'd0;            // 当拍源字节数 (0..8)
    wire [3:0] sc4    = (stg_cnt >= 5'd8) ? 4'd8 : stg_cnt[3:0];    // min(stg_cnt, 8)
    wire [3:0] kk     = (sc4 < room) ? sc4 : room;                  // 本拍搬到累加器的字节数 (0..8)
    wire [4:0] keep   = stg_cnt - {1'b0, kk};                       // 搬走后留在暂存的字节数 (0..16)
    wire       admit  = src_beat && (keep + {1'b0, n_b} <= 5'd16);  // ⭐ 追加能否装下 (容量=16 B)
    wire       drop_now = src_beat && !admit;

    wire [63:0] xbeat = s_tdata ^ {8{XORC}};
    wire [7:0]  b0 = stg_data[127:120];  // … b7 = stg_data[63:56]  (与旧同名 ⇒ mv/acc_sh 两表逐字不变)
    wire [3:0]  acc_have = acc_cnt_r + kk;
    wire        have     = (acc_have == 4'd8);
    wire        wr_en    = have && !fifo_full && cap_on;            // (行逐字不变)

    // 暂存整体前移 kk 字节 (9 路 case, 128 位)
    reg [127:0] stg_ret;
    always @* begin
        case (kk)
            4'd0: stg_ret = stg_data;
            4'd1: stg_ret = {stg_data[119:0], 8'd0};
            // … 4'd2..4'd7 同型 …
            4'd8: stg_ret = {stg_data[63:0], 64'd0};
            default: stg_ret = 128'd0;
        endcase
    end
    // 源拍顶 n_b 字节贴到 keep 之后的尾部 (= {xbeat,64'd0} >> 8*keep; 17 路 case)
    reg [127:0] beat_pl;
    always @* begin
        case (keep)
            5'd0:  beat_pl = {xbeat, 64'd0};
            5'd1:  beat_pl = {8'd0,  xbeat, 56'd0};
            5'd2:  beat_pl = {16'd0, xbeat, 48'd0};
            5'd3:  beat_pl = {24'd0, xbeat, 40'd0};
            5'd4:  beat_pl = {32'd0, xbeat, 32'd0};
            5'd5:  beat_pl = {40'd0, xbeat, 24'd0};
            5'd6:  beat_pl = {48'd0, xbeat, 16'd0};
            5'd7:  beat_pl = {56'd0, xbeat, 8'd0};
            5'd8:  beat_pl = {64'd0, xbeat};
            5'd9:  beat_pl = {72'd0, xbeat[63:8]};
            5'd10: beat_pl = {80'd0, xbeat[63:16]};
            // … 5'd11..5'd15 同型 (每档右移 8) …
            5'd16: beat_pl = 128'd0;
            default: beat_pl = 128'd0;
        endcase
    end
    // lane 合并: i<keep 保留, 否则接源拍 (不接收 ⇒ 灌 0 ⇒ 无效位恒 0)
    wire [127:0] stg_next;
    genvar gi;
    generate for (gi = 0; gi < 16; gi = gi + 1) begin: g_stg
        assign stg_next[8*gi +: 8] = (gi < keep) ? stg_ret[8*gi +: 8]
                                                 : (admit ? beat_pl[8*gi +: 8] : 8'd0);
    end endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin stg_data <= 128'd0; stg_cnt <= 5'd0; acc_r <= 64'd0; acc_cnt_r <= 4'd0; end
        else if (clr_pulse) begin stg_data <= 128'd0; stg_cnt <= 5'd0; acc_r <= 64'd0; acc_cnt_r <= 4'd0; end
        else if (cap_on) begin
            stg_data  <= stg_next;
            stg_cnt   <= keep + (admit ? {1'b0, n_b} : 5'd0);
            if (wr_en) begin acc_r <= 64'd0; acc_cnt_r <= 4'd0; end
            else if (kk != 4'd0) begin acc_r <= acc_next; acc_cnt_r <= acc_have; end
        end
    end
```

### 4.2 资源量级

| 项 | 量 | 依据 |
|---|---|---|
| FF | **+61** | 算得：+128 (`stg_data`) +5 (`stg_cnt`) −72 (`pend_data[63:0]`+`pend_keep[7:0]`) |
| LUT | **≈ 500–900**【估算】| 表：`stg_ret` 9 路×128 位 + `beat_pl` 17 路×128 位 + 16 lane 二选一 + `admit/keep/kk` 比较器。参照：上一轮同类改动（含读侧拆分 + 2 字 DMA 口 + 环加宽 + 写门修复）synth 面实测 **+672 LUT** ⇒ 本轮改动面更小（无读侧/无端口），量级可比或略小 |
| BRAM/URAM | **0** | FIFO 仍 256×64；无新存储 |
| 端口/接线 | **0** | 无新端口；`wrapper_p4.v` / `mir_dma_ring` / `p6e` 期望值**预计 0 改动**（复跑确认）|

⛔ 以上 LUT 是【估算】，**本轮无 EDA**；真正的量由下一轮 synth 检查点给出。

### 4.3 DP 域时序风险（只给"要看的族"，不裁定）

【事实】`0x20` 构建读数（`_proj_10g/notes/p8_build_0x20/REPORT.md:14-15,113-115`）：
- **DP 域（`g_hw.clk_out0`）setup WNS `+0.154` = 全局最差**；宿主 `u_tcp_tx/u_fifo_a/rptr_reg[3]/C → u_tcb/rcv_nxt_r_reg[5][9]/CE`（lvl=16）；
- **M1 族 DP 组内最紧 `+0.515`**（`u_mir/acc_cnt_r_reg[0]/C → u_mir/u_fifo/mem_reg…/WE`）⇒ 与全局最差隔离 **0.361 ns（3.34×）**；M1 cell 在全局 top5 **0 命中**。

新结构**变/增**的三条锥（下一轮构建要定向查，⛔ 本件不预判结论）：
1. **`stg_cnt → sc4 → kk → acc_have → have → wr_en → u_fifo WE`** —— 恰好落在**现役最紧 M1 族**上（+0.515）。
   旧版该路径的输入是 `n_cur = pop8(pend_keep)`（也是寄存器+树）；新版换成 `stg_cnt` 饱和比较 ⇒ 深度**预计中性**，但**必须实测**。
2. **`acc_r/acc_cnt_r → acc_sh → acc_next → u_fifo.din`（128 位 lane 合并并入 `mv` 的取头）**—— 数据锥。
3. **`stg_data → stg_ret/beat_pl/lane → stg_data` 自环**（4–6 级 mux，独立于上面两条）。
⚠️ 前两轮 M1 改动**都没有**成为 DP 最差锥（top20 0 命中）—— 但那是**过去**，不构成保证。
**处置建议（不改本设计的形状）**：构建后按 M1 定向查询（`q_*.tcl` 模式）核 `u_mir` 三族新 slack；若族 1 吞掉 >0.2 ns ⇒ 退回 §4.4-iii 之外的选项（A′ 不并入即是为此留的余量）。

### 4.4 降代价替代（Q3 点名：各自能否 8 B/拍）

| 替代 | 能否 8 B/拍 | 说明 |
|---|---|---|
| **(i) 两槽 + 跨槽同拍消费（无压缩）** | ⛔ **不能** | 模型（附录 A）：`phase=1..7` 各丢 240/481 ≈ **0.500**；1460 B 稠密 **24.93%**；1470 B **41.6%** —— **与旧版同病**。根因：追加要求"**尾部槽整空**"= 旧的"整块才可接收"同一约束；跨槽消费只解了"消耗侧"，没解"追加侧"的字节对齐 |
| **(ii) 8 字节粒度（按整字/整槽搬运）** | ⛔ **不能** | 同 (i)（两者互为换写）：相位 ≠0 时"槽粒度"永远贴不上 phase 的 1..7 字节错位 |
| **(iii) 指针/旋转式 16 B 环形（不搬数据）** | ✅ 能 | 容量/策略同 A（等价），但把 mux 代价**搬到读侧**：`mv` 之前要先按 head 指针选字节（16 lane × ~16 值 mux）⇒ 落在 `acc→FIFO din` 更敏感的锥上 ⇒ **否决**（登记理由：把代价从反馈环挪进关键锥）|
| **(iv) A′ 恢复沿精化** | ✅ 能（同 A，另把"满态恢复沿"也做成零丢）| 改动：`room1 = rel ? (fifo_full ? 0 : 8) : (8 − acc_cnt_r)`，`rel = (acc_cnt_r == 4'd8)`；`wr_en = (have \|\| rel) && !fifo_full && cap_on`；`acc_r <= (rel && !fifo_full) ? mv : (wr_en ? 0 : acc_next)`；`u_fifo.din <= rel ? acc_r : acc_next`（挂住的字必须写真身，不能写合并值）。代价 ≈ 2×64 位 mux + rel 逻辑（**+0 FF**）⇒ **恰在族 1 与族 2 上各 +1~2 级** |

**取舍结论（给裁定者的输入）**：A 已满足本刀目标（结构吞吐类丢字节对任意相位不可达；剩下一类 = FIFO 满，与旧版同类）；
A′ 的**唯一**增量 = 满态恢复沿省 ≤1 拍/次（模型：full 2/4/8/16 拍 ⇒ A 丢 8/24/56/120 B，A′ 丢 0/16/48/112 B）。
板级演示里 FIFO 是否瞬时满**不由本设计决定**（drainer 2 词/rd 拍 = 2 GB/s vs 源 1.25 GB/s，余量 1.6×）。
⇒ **建议：A 作基线；A′ 作为"同批可选增量"，裁决权在构建轮的 DP 读数** —— 若族 1 有余量则并入（更干净的判据面），否则留待下一刀。

---

## §5 替代案 A/B/C 总对比（Q4）

| 维度 | **A（选）16 B 字节粒度** | B 两槽 + 跨槽同拍消费 | C 分布式 RAM 小缓冲 + 打包器 |
|---|---|---|---|
| 任意相位维持 8 B/拍 | ✅ **是**（BFS+模型双证，紧界 15/16）| ⛔ **否**（原样；见 §4.4-(i) 模型读数）。**加"槽内压缩(close-gap)"后 = 与 A 功能等价**（换写法，不省代价且引入"搬移"新失败形态）| ✅ 原理上可行（字奇偶双 bank ⇒ 一拍内各写 1 字，读侧双读口）**但**：追加 = **任意字节偏移的 8 B 写** ⇒ LUTRAM 单写口做不到，必须奇偶双 bank + 两字 RMW + 读侧双读口 + 字节级占用记账 |
| 面积 | FF +61 / LUT ≈500–900（估）| 同量级（压缩版）；原样版略小但**不达标**| **显著更大**（双 bank + 2×RMW 合并边 + 双侧双读口 + 记账状态）|
| DP 时序风险 | 三条锥（§4.3），两条落在现役 M1 族附近 | 同量级 | 更高：RMW 合并 + 读侧对齐器，且**两侧**都加级别 |
| 改动面（头注释/端口/TB/p6e/环）| 头注释结论句 + 状态块重写；**端口 0**；TB 新增用例 + 身份式残余项；p6e 预计 0 值改；环 0 | 同 A；但"压缩"路径要多写 3~4 条用例（槽角色翻转 × 压缩）| 大：新存储实例 + 新控制状态机 + 新用例族 |
| 与 snoop 合同（永不驱动握手）| ✅ 不变 | ✅ | ✅ |
| 结论 | **选 A**：唯一"策略可证 + 代价居中 + 变更面最小（含突变锚点存活）"的方案 | ⛔ 原样不达标；压缩版与 A 等价 ⇒ 无选它的理由 | ⛔ 只有需要"暂存 ≫16 B"（长时满容忍）时才值得；本刀不需要 |

**A 的选型理由（一句话）**：容量需求是**字节级**的（相位 1..7 ⇒ 追加位置任意），而"槽/字粒度"结构在相位 ≠0 时结构性贴不上；
A 把 16 B 做成一个可任意字节对齐的窗口，代价 = 两条显式 case 表 + 一个 lane 合并，且**读侧（`mv`/`acc_sh`/`wr_en`）逐字不变**
⇒ 改动面与突变锚点都最小。

---

## §6 门 + 突变计划（关键交付）

### 6.1 新 TB 用例（`tb/tb_app_rx_mirror.v`；沿用现有 golden/`offered`/aux 监视脚手架）

| ID | 用例 | 判据（含已有脚手架字段）|
|---|---|---|
| **G15** | **先喂残拍建相位 → 再灌背靠背 8 B/拍**（`4 B` 残拍 + 600 拍背靠背，fast sink）| `d_drop == 0`；`offered == 8×(排空字数) + (acc_cnt_r + stg_cnt)`（**身份式带新残余项**）；golden 逐字（`dword_mis == 0`，aux 口）|
| **G16** | **帧长 ≢0 mod 8 长流**：`L ∈ {1436, 1460, 1470, 1477}` × 6 帧（每帧 `⌊L/8⌋` 满拍 + 尾拍），稠密；**两变体**：帧间 0 拍 / 帧间 4 拍 | 每档 `d_drop == 0` + golden + 身份式（模型：两变体全 0）|
| **G17** | **phase = 1..7 扫描**（残拍 ph 字节 + 背靠背）| 7 档全 `d_drop == 0`；至少 `ph=0`/`ph=7` 两档加**手算字锚**（golden 逐字已在，锚 = 万一 golden 与 DUT 同错的第二道）|
| **G18** | ⭐ **最坏轨迹锚**（`ph=7` + 背靠背）| hierarchical 断言轨迹：`stg_cnt` = 7 → 8 → **15** → 15(稳态)；`acc_cnt_r` 同步轨迹；`d_drop == 0`。**这是 `mut_admit14` 的唯一红灯**（模型预验）⇒ 必做 |
| **G19** | **FIFO 满 / `cap_en` / `clr` 交叉** | (a) 满态灌流 ⇒ drop 有界且**无静默丢**（身份式 `Δdrop` 精确，`any_drop`=1）；(b) **满→释放沿**：按所选变体断言（**A**：释放沿 ≤1 拍丢**且计入**；**A′**：0 丢）⇒ 本条 **pin 住变体**；(c) `cap_en=0` 冻结（暂存非空时）⇒ 不涨/不降/不写，恢复后 golden 连续；(d) `clr` 在暂存非空时 ⇒ `stg_cnt→0` + golden 从该点重开；(e) `tlast` 落在暂存有字节的拍 ⇒ 不 flush |
| **G20**（结构性断言，可并入各用例）| `stg_data[127 : 8*stg_cnt] == 0`（**无效位恒 0**）| 由 §2.1-② 的"灌 0"结构免费给出 ⇒ 抓 mask/lane 选错类突变 |

**既有用例复跑 / 必改清单**：
- **G13**（相位 0 dense ⇒ `d_drop==0`）：**逐字保留**（新设计必须继续过，预期读数不变）。
- **G8 / G11 / G8d（身份式）**：**必须把残余项从 `acc_cnt_r` 改成 `acc_cnt_r + stg_cnt`**（否则新结构会假红/假绿）。
- **G2..G5 手锚、G12（混用）、G14（cap_on 冻结）**：预期读数不变（`b0..b7` 改名后手锚按新头部字节重算 —— 若实施者保持 b0..b7 命名与 `mv` 表逐字不变，**锚值不变**）。
- **p6e 全链 108 PASS**：**只复跑、预计 0 值改**（M1 断言以计数/内容锚为主；满拍发射延迟新旧同为 1 拍）——但**若有周期级断言则要现读重算**（本轮未逐条核 ⇒ 列为实施时第一步）。
- **环门 `tb_mir_dma`**：复跑（字序列不变 ⇒ 预计 0 值改）。

### 6.2 突变臂表（每件**恰 1 行、恰 1 处命中**；锚文本 = §4.1 规格行）

| 臂 | 改哪一行（old → new）| 打的性质 | 期望红灯（模型预验/依据）|
|---|---|---|---|
| `mut_gate`（**锚存活**）| `wire       wr_en     = have && !fifo_full && cap_on;` → `have && cap_on;` | 空间门（静默丢字）| 身份式 G11/G8d 红（与现役同款；行文逐字不变 ⇒ 锚不用动）|
| `mut_order`（**锚存活**）| `            4'd2:    mv = {48'd0, b1, b0};` → `{48'd0, b0, b1};` | 字节序 | 手锚 G3c/G4c/G5c 红（b0/b1 现取暂存头部；表文不变 ⇒ 锚不动）|
| `mut_cap4`（**锚移 1 行**）| `wire [3:0] kk     = (sc4 < room) ? sc4 : room;` → `wire [3:0] kk     = (((sc4 < room) ? sc4 : room) > 4'd4) ? 4'd4 : ((sc4 < room) ? sc4 : room);` | **4 B/拍结构上限复活** | **G13/G15/G17 全红**（模型：套件总丢 19,465 B；含 phase=0）|
| ⭐ `mut_admit14`（新）| `wire       admit  = src_beat && (keep + {1'b0, n_b} <= 5'd16);` → `… <= 5'd14);` | 容量紧界（差 1 会漏，差 2 必抓）| **只**由 G18/G17(ph=7)/G16(1477) 红（模型：总丢 1,136 B；**ph=0..6 与 1460/1470 全绿** ⇒ 这就是为什么必须做 G18）|
| ⭐ `mut_apos0`（新）| `            5'd0:  beat_pl = {xbeat, 64'd0};` → `            5'd0:  beat_pl = {xbeat[55:0], xbeat[63:56], 64'd0};` | 尾部追加位置 | G13/G15 逐字 golden 立刻红（相位 0 dense 每拍都走 `keep=0` 档）|
| ⭐ `mut_dropcnt`（新）| `        end else if (drop_now) begin` → `        end else if (1'b0 && drop_now) begin` | **不静默丢** | G19a 身份式 + `any_drop` 红 |
| （可选）`mut_keep1` | `wire [4:0] keep   = stg_cnt - {1'b0, kk};` → `… + 5'd1;` | 保留计数 | 身份式 + G20 结构化断言红（模型：总丢 4,824 B + 账不平）|

**构造纪律**（沿用 `sim/p7b_mir/mut/make_mutants.py` 现有框架，sha256 `0ed60f17…`）：
① 每次从**现役** `rtl/app_rx_mirror.v` 重生成（产物件不入留档逻辑）；② 每件打印 `MUT_*_HITS`，**必须恰好 1**（0 = 锚陈旧、>1 = 改错地方 ⇒ `GENFAIL` 退出 1）；
③ 只做 1 次字符串替换；④ `mut_cap4`/`mut_admit14` 的**期望红灯面**已由附录 A 模型预验（不是猜）；
⚠️ 既有 `make_mutants.py:7-14` 的"只该由 X 翻红"措辞与实测不符（审查 ⑤-3）⇒ 本轮一并改成"**至少**由 X 翻红"。

### 6.3 板级 A/B（触发面可达性）与**搁置分支判据**

**臂设计**（在飞轮 `p8_board_0x20_20261011/` 之外另排；同板同线同工具）：
- **臂 1**：位流 `0x20`（现役 8 B/拍修复版）+ **`p7b_udp_src --paylen 1472`**（相位 0）⇒ 预测 `ΔW70(drop_bytes) == 0` + `MIR_VERIFY rc=0 / first_mismatch=-1`。
- **臂 2**：同位流 + **`--paylen 1470`**（相位 6）⇒ 预测 **`ΔW70 > 0` 且量级 ≈ 41.6% 的采集字节**（模型值；1460 档为 24.9%）+ 内容相位错（`first_mismatch` 小/固定）。
  （工具支持 `--paylen 1..1472` —— `_proj_pcie/p7b_biz/p7b_udp_src.cpp:144` 现读。）
- 两臂**只差一个参数**，其余（频率、路径、`--dma`、快照窗）全同。

**判据与三条出路**：
1. 臂 2 出现 `ΔW70 > 0` ⇒ **相位缺陷板级坐实** ⇒ 本设计件转实施（构建 `0x21`：本设计 + G15–G19 + 突变新锚；⚠️ 只走 `board/run_build_p7b_ku5p.bat`）。
2. 臂 2 `ΔW70 == 0` **且内容 PASS**，且**有独立见证证明该臂的源确实稠密、逐帧长度确实 ≢0 mod 8**（见证 = 1472 臂与 1470 臂的帧率/线上字节率同量级 + `0x1F` 同位流"50% 丢"历史读数 + 可选：加一个"背靠背拍密度"临时计数器）⇒ **本设计件应被搁置**（登记为"触发面在该链路上缺席 ⇒ 空判据"，⛔ **不写"证伪"**，全局 #92）。
3. 臂 2 `ΔW70 == 0` **但无稠密度见证** ⇒ **判不了**（可能是源稀疏）⇒ 先补见证（G18 的板级类比：把源换成 xsim 侧注入或加临时仪器），**不许**据此搁置设计件。

---

## §7 风险与未定项（不许当已答）

- **R1（最高优先）**：**板级 A/B 未回**（`p8_board_0x20_20261011/` 本轮现读 = 未跟踪新目录，在进行中）⇒ 触发面可达性 = **未测**。
  本设计件的**存在理由**全部建立在【模型级已证 + 板级未测】（审查原话）之上 ⇒ 搁置分支判据见 §6.3-2/3。
- **R2（时序）**：DP WNS `+0.154` = 全局最差；三条新锥（§4.3）**未评估**。⛔ 本件**不裁定时序**，也不写"预计无风险"——只给"要看的族 + 定向查询方法"。
- **R3（同批同步项，非本设计范围）**：`p7b_mir_dump.cpp:418-419` 硬门仍 `K % 4` ⇒ `K ≡ 4 (mod 8)` 会被**接受**、然后表现为**安静的短读**（审查 ⑤-6 登记形态）。与本设计正交，但同批做最省。
- **R4（A′ 取舍）**：见 §4.4-iv 与 §4 结论；裁决输入 = 构建后族 1 的 slack。**A 与 A′ 必须二选一并写进头注释**（防"两版混淆"）。
- **R5（登记·语义）**：`cap_en` 中途开关的跨暂停拼接残余量 **8 → 15 B**（性质不变、量变大）；`clr` 清掉的暂存字节（≤15 B）按定义不计 drop（与旧 `pend` 残余同款）。
- **R6（满态行为）**：A 变体在**满态恢复沿**可再丢 ≤1 拍（计入 drop_bytes，**不静默**）；若验收把"满态过后 drop 仍为 0"当硬指标 ⇒ 必须并 A′（§4.4-iv）。
- **R7（待复跑确认的"0 改动"）**：p6e 全链 / 环门 / `wrapper_p4.v` 接线 —— 预计 0 值改，但**必须复跑**；p6e 若有周期级 M1 断言需现读重算（本轮只核了 M1-0/2/3 的形态，未逐条判周期依赖）。
- **R8（未核）**：`mir_dma_ring` / `axi_regs` 是否有任何对"字发射周期/节奏"的隐含假设（本设计只改**何时**写、不改字序列）——列为实施第一步的现读项。
- **R9（范围外）**：`MIR_STATUS.ver` 是否 bump（上一轮 K%4→K%8 的裁定遗留）不在本件；本设计不改位语义 ⇒ 不新增 bump 需求。

---

## 附录 A：可重跑模型（本件全部读数的**唯一**来源；只读、无 EDA）

```python
# 放在 %TEMP% 下跑: python mir_stg_model.py  (本机 anaconda)
CAP = 16
def sim_old(beats, sink_full=lambda i: False):          # 现役 0x20 逻辑 (64b acc + 8B 单槽 pend)
    pend_v, pend_n, acc = 0, 0, 0; drops = offered = words = 0
    for i, n in enumerate(beats):
        full = sink_full(i)
        n_cur = pend_n if pend_v else 0; room = 8 - acc
        kk = min(n_cur, room); drain_all = (kk == n_cur)
        pend_after = pend_v and (not drain_all)
        src = n is not None
        if src: offered += n
        load = src and (not pend_after)
        if src and pend_after: drops += n
        ah = acc + kk; wr = (ah == 8) and (not full)
        if wr: words += 1
        if load: pend_v, pend_n = 1, n
        elif pend_v:
            if drain_all: pend_v = 0
            else: pend_n = n_cur - kk
        if wr: acc = 0
        elif kk: acc = ah
    resid = (pend_n if pend_v else 0) + acc
    assert offered - drops == 8*words + resid          # 身份式 (每跑自检)
    return drops, offered, words, resid

def sim_new(beats, variant='A', sink_full=lambda i: False, cap=16, kkcap=None):
    acc = s = drops = offered = words = 0; maxs = 0
    for i, n in enumerate(beats):
        full = sink_full(i)
        rel = (variant == 'AP') and (acc == 8) and (not full)
        c = min(8, s) if rel else min(8 - acc, s)
        if kkcap is not None: c = min(c, kkcap)
        k = s - c; src = n is not None
        if src: offered += n
        admit = src and (k + n <= cap)
        if src and not admit: drops += n
        s2 = k + (n if admit else 0)
        if rel: words += 1; acc = c
        else:
            ah = acc + c
            if ah == 8 and not full: words += 1; acc = 0
            elif c: acc = ah
        s = s2; maxs = max(maxs, s)
    resid = acc + s
    assert offered - drops == 8*words + resid
    return drops, offered, words, resid, maxs

def frames(lengths, reps, gap=0):                        # 逐帧: ⌊L/8⌋ 满拍 + 尾拍 (+ 间隙)
    b = []
    for _ in range(reps):
        for L in lengths:
            for _ in range(L // 8): b.append(8)
            if L % 8: b.append(L % 8)
            if gap: b += [None] * gap
    return b
```

**BFS（对抗性 `n` × `full`）**：`state=(acc,s,full)`；对每态枚举 `n∈{0..8,无拍}` 与下一拍 `full∈{0,1}`；
A 变体 194 态 / A′ 192 态；`full=0` 的拒收实例 A=72（全为 `acc=8 ∧ s>8`）· A′=0；`max_s=16`；
未经历满饱和可达态 79 个、`max_s=15`、最大追加需求 15。
（本轮脚本 = `%TEMP%\mir_stg_model.py`（模型 + 套件 + BFS）、`mir_stg_model2.py`（密度扫描 + A/B 预测）、
`mir_stg_model3.py`（突变牙齿预验）—— **scratch，不入库**；三段的 `sim_old/sim_new` 核心与上面函数同源，
按上面的函数重写即可逐位复跑。）

**读数汇总（附录 B）**：OLD：`240/484`（4B+60×8B）· phase 1..7 各 240/481..487（**丢幅 0.500**）· 1460 B×6 稠密 `2184/8760=24.93%` · 1470 B×6 稠密 `3670/8820=41.6%` · 1472 B×6 `0/8832` · 稀疏(1/9) `0` · 1 拍/2 周期 `0` · 帧间 gap 0/1/2/4 ⇒ 24.93% 恒 · 拍序列 `TTD TDTDTD…`（复现板级"偶奇"签名）。
NEW_A：上列**全 0 丢**；cap=14 套件丢 976（⇒ 紧界 15/16）；A′（cap≥15）全 0；`mut_cap4`/`mut_admit14`/`mut_keep+1` 的套件红灯面见 §6.2。

---

## 附录 C：引用出处（现读绑定）

- 缺陷与机制：`rtl/app_rx_mirror.v`（sha `821d7593…`）`:154-164`（写侧边界）、`:143-147`（`pend` 状态）、`:226-248`（推进块）、`:164`（写门）、`:16-18`（过宽结论句）、`:28-29`（keep 合同）、`:40-44`（drop/cap_en）、`:45-49`（clr）、`:52-55`（level）。
- 审查/报告：`_proj_10g/notes/p8_mir8b_impl_20261011/REVIEW.md` §②-2.1/§③/§④/§⑤-1/⑤-6；`REPORT.md` §0/§2/§3/§8-C2；`SELECTION.md:8`。
- 门/突变：`tb/tb_app_rx_mirror.v`（sha `fe813267…`）`:135-165`（golden/offered）、`:226-239`（aux 监视）、`:154`（`u_dut.cap_on`）；`sim/p7b_mir/mut/make_mutants.py`（sha `0ed60f17…`）。
- 源稠密度：`rtl/app_pattern.v`（sha `811a84e4…`）`:608` + `:611-620`；`rtl/app_udp_pattern.v`（sha `0a520f5f…`）`:416-428`、`:658`、`:881-886`；`board/wrapper_p4.v:3799-3803`。
- 构建读数：`_proj_10g/notes/p8_build_0x20/REPORT.md:14-15,113-115`（DP `+0.154` 全局最差 / M1 族 `+0.515` / M1 top5 0 命中）。
- 工具：`_proj_pcie/p7b_biz/p7b_udp_src.cpp:144`（`--paylen 1..1472`）；`p7b_mir_dump.cpp:418-419`（`K%4` 硬门）。

*本件由设计 agent 于 2026-10-11 撰写；未改动任何 RTL/TB/工具；未跑 EDA。*
