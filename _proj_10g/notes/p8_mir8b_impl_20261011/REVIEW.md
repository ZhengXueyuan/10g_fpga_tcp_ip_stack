# P8 阶段三（镜像采集侧 8 B/拍修复）—— 只读对抗审查 REVIEW

审查对象 = `HEAD = 193f06a`（`P8 阶段三：镜像采集侧 8 B/拍修复`），工作目录 `D:\repo\XCKU5PMini\udp_hls_10g`。
审查方式 = **只读**：不跑 xsim/vivado；只读源码/日志/报告 + 跑 `git`/`grep`/`python` 做不启动 EDA 的分析。
**本件不下 PASS/FAIL 裁定**；"未观测到"一律不写成"不存在"。
⚠️ 审查期间工作树**正被并行构建轮改写**（` M board/wrapper_p4.v`：BID 0x1F→0x20；我两次 `sha256sum` 得到不同值：`a3f49322…`(298,226 B) → `8d9374c5…`(300,699 B)）⇒ 下文一切行号/内容都是**现读**，引用者必须再核。

---

## ① 事实核对表（报告/commit message 的读数 vs 原件）

| # | 报告/commit 的说法 | 原件 | 判定 |
|---|---|---|---|
| 1 | 单元门 `tb_app_rx_mirror` `PASS_ALL`（81 PASS / 0 FAIL） | `sim/p7b_mir/xdir_real/xsim.log`：`[PASS]`×81、`[FAIL]`×0、`:132 APP_RX_MIRROR_GATE: PASS_ALL` | ✓ 逐字 |
| 2 | 突变 `gate`/`order`/`cap4` = FAIL **6/2/6** | `xdir_mut_gate/xsim.log` 6 FAIL（`:101,102,105,106,112,116`）· `xdir_mut_order` 2（`:53,60`）· `xdir_mut_cap4` 6（`:94,95,96,97,103,106`） | ✓ 逐字 |
| 3 | G13 读数 `offered=4800 gold_n=4800 gnt=600 level=0 d_drop=0 dword_mis=0`（引 `:90-98`） | `xdir_real/xsim.log:90-98` = `--- G13: …` 块，`:91` 就是那一行 | ✓ 逐字 |
| 4 | G8 已改写为 FIFO 满类、`drop>0` 有读数（引 `:510-538`） | `xdir_real/xsim.log:99-107`：`offered=2400 d_drop=336 level=511`、排空 516 字、`G8d 恒等式 2400` ✓（行号区间略有出入） | ✓ 内容一致（行号 ✓/✗ 混合） |
| 5 | 环门 `PASS_ALL`（checks=45）；突变 `row/rlast/rid` = FAIL **11/8/9** | `sim/p7b_mirdma/xdir_real/xsim.log:80 MIR_DMA_GATE PASS_ALL tb_mir_dma (checks=45)`；三臂 `[FAIL]` = 11 / 8 / 9 | ✓ 逐字 |
| 6 | p6e 全链 **115 PASS / 0 FAIL / PASS_ALL** | `sim/p6e_pcie/xsim_p6e.log`：`[PASS]`×115、`[FAIL]`×0、`:163 PASS_ALL` | ✓ 逐字 |
| 7 | **`bwire` FAIL 27 / `srcinv` FAIL 5** | **原件相反**：`dir_mut/files.f:211` 编的是 `wrapper_p4_mut_srcinv.v` ↔ `xsim_mut.log` = **27** FAIL；`dir_mut2/files.f:211` 编的是 `wrapper_p4_mut_bwire.v` ↔ `xsim_mut2.log` = **5** FAIL | ✗ **两值对调**（详见 ⑤-2） |
| 8 | `p5_wrapper`：`P5 WRAPPER OK` + `[P4GUARD OK]` | `sim/p4gates/work_20261011_131319/p5_wrapper/_gate_console.log`（两行都在） | ✓ 逐字 |
| 9 | 矩阵指纹 before/after `DIGEST_ALL` 逐字相同 `b2b957a6…`；含 `wrapper_p4.v @ a3f49322…` = 现读值 | 两个指纹件 `diff` 只差 `label`/`run at` 两行；`DIGEST_ALL = b2b957a610ad1c0b040e89669300d503588750b582e497ed087bb6f8584faa30`（两件同）；`SHA256 a3f49322… board/wrapper_p4.v 298226` | ✓ 逐字（⚠️ 我的现读值现在是 `8d9374c5…`，因为并行构建轮已改盘，见 ⑤-7） |
| 10 | synth 检查点：`M1SYNTH_MIR_IMPORTED=1`；LUT 84,162 / FF 79,080 / BRAM 354 / URAM 0 / DSP 4 / BUFGCE 2；WNS −0.371 / WHS −0.661；DP 前 20 单一旧族、`u_mir` 0 命中；19,090 M1 引脚 | `synth_outer.txt`（IMPORTED 1 / WNS −0.371 / WHS −0.661 / MIR_PINS 19090）；`synth_p8mir8b_util.rpt:35,36,37,40,80,85,96,142`；`synth_p8mir8b_timing_summary.rpt:141`（−0.371 / 325 端点 / −0.661）；`dp_worst_p8mir8b.rpt`（20 条全 −0.371，宿 `u_app/stg_reg[0..27]/CE`，`grep u_mir` = **0**） | ✓ 逐字（⚠️ IMPORTED 的强度问题见 ⑤-4） |
| 11 | 对照数：0x1F 后布线 LUT 77,536 / FF 74,657 / BRAM 352；m1p2b synth 83,490 / 79,011 / 354 | `p7b_build_0x1F/REPORT.md:168`；`p7b_m1p2b_synth/synth_m1p2b_util.rpt:35,40,80` | ✓ 逐字 |
| 12 | "BID 未 bump = 仍 `0x1F`" | `git show HEAD:board/wrapper_p4.v | grep BUILD_ID_V` = `32'h0000001F`（`:4332`）；`HEAD~1` 也是 0x1F（本刀 diff 不含该行） | ✓ 对 HEAD 成立（⚠️ 盘上现态已被并行轮改成 0x20，别照抄） |
| 13 | §3 旧版可达性：旧 `wr_en = have && !fifo_full` 不含 cap_on、状态块 `else if (cap_on)` | `git show 193f06a^:rtl/app_rx_mirror.v`：写门逐字 `wire wr_en = have && !fifo_full;`、推进块逐字 `end else if (cap_on) begin` | ✓ 结构性成立（板级可达性仍未证，与报告口径一致） |
| 14 | 工具本轮未改（12:33 之后再无改动）；K%8 同步"按范围外未做" | `_proj_pcie/p7b_biz/p7b_mir_dump.cpp` mtime **12:33**、最后提交 `fb23ad4`；硬门现读 `:418-419` = **`want % 4 != 0` 才拒**；报告 §2.1/§6.2 已明写"本轮不做" | ✓ 登记属实（⚠️ 具体失败形态未登记，见 ⑤-6） |
| 15 | 报告 §1 改动清单（4 个 RTL/TB 文件 + 突变件 + bat） | `git show 193f06a --numstat`：`rtl/app_rx_mirror.v 234`、`rtl/mir_dma_ring.v 33`、`board/wrapper_p4.v 30`、`tb/tb_app_rx_mirror.v 520`、`tb/tb_mir_dma.v 20`、`sim/p6e_pcie/tb_p6e_pcie_wrapper.v 93`、`mut_bwire.py 6` | ✓ 量级一致 |

**证据绑定专项**（本工程#52/#57 家族）：`sim/p6e_pcie/mut/wrapper_p4_mut_bwire.v`（13:16 由**当时现役** wrapper 生成）= 我把 CRLF 归一后与 `git show HEAD:board/wrapper_p4.v` 逐行 `diff` ⇒ **只差那 1 行突变**（`3855`）⇒ **门/synth 跑的内容 = 提交的内容**（行尾差异：工作树 CRLF 298,226 B = HEAD blob LF 293,492 B + 4,734 行）。✓ 这一条我正面核实成立。

---

## ② RTL 逐项发现（含行号）

### 2.1 写侧边界（`rtl/app_rx_mirror.v:154-164` + `:226-248`）
逐条自洽（我按行转写了一个循环级模型并在同一激励上复算，见 ③/附录）：
- `kk=0`（`n_cur=0` 或 `room=0`）、`kk=8`（`n_cur≥8 且 acc_cnt=0`）、`acc_cnt=8`（"握字"态：`room=0⇒kk=0`、`have=(8+0==8)=1`、`wr_en=!full&&cap_on` ⇒ 空间一来就落笔）、`FIFO full`（`wr_en=0` ⇒ `kk==0` 分支不推进 ⇒ 字留在累加器）、`cap_on=0`（整块冻结 + 写门再门一次）——五种边界**无相互矛盾**。
- `drop_now = src_beat && pend_after` 的字节数 = `pop8(s_tkeep)`（`:257`）= **当拍被拒的源拍字节**，语义正确（`offered` 口径 = 所有握手拍、含被拒拍 ⇒ `offered == 8×写入字数 + drop_bytes + 残余` 在整拍拒收下逐字成立，G8d/G11c 已见证）。⚠️ **部分拍被拒**（`pop8<8`）在 TB 里**没有用例**（G8/G11 的拒收都是 8B 整拍）⇒ 该计数只在源码面核过。
- ⛔ **唯一不自洽的边界 = 相位 ≠ 0**：`room = 8 − acc_cnt_r`，`kk = min(n_cur, room)`，而 `pend` 只在 `drain_all` 那拍腾出来接新拍 ⇒ 当 `n_cur=8 > room`（room=1..7）时，本拍只搬 room 个字节 + **拒收同拍到来的新拍**。稳态 = 每 2 拍吃 1 个 8B 拍。**这不是文档里任何一条边界，且与头注释的结论冲突**（见 ⑤-1）。

### 2.2 读侧拆分与仲裁（`:294-340`）
四种情形我逐条对过，**顺序恒等于逻辑字流**，`stash_v` 推进正确：
| 情形 | `dout`/`dma_data` | `rd_go` | `stash_v` 后续 |
|---|---|---|---|
| host 弹、`stash_v=0` | `head_lo` | 1（弹整 64 位字） | →1，`stash_d<=head_hi` ✓ |
| host 弹、`stash_v=1` | `stash_d` | 0（**不弹 FIFO**） | →0 ✓ |
| dma、`stash_v=0` | `{head_hi, head_lo}` | 1 | 不变（0）✓ |
| dma、`stash_v=1` | `{head_lo, stash_d}` | 1 | 不变（1），`stash_d<=head_hi` ✓ |
| flush/clr | —— | `flush_r ? !fifo_empty` | 强制清 0 ✓（`clr_pulse_r||flush_r` 优先级最高，`:328`） |
- `level = 2×dbg_occ_r + stash_v`（`:339`）：`dbg_occ_r` 是读域 2FF 同步占用（悲观）⇒ 该式**只少报**；`stash_v=1` 时也成立（半字只数 1 且 FIFO 侧仍悲观）。**持有在累加器里的整字（`acc_cnt=8`）与 `pend` 里的字节都不计** ⇒ 同样只少报（这正是"读恰好 level 字不下溢"需要的方向）✓。clamp（`:340`）只对 `occ=256` 生效（512/513→511）✓ 仍只少报。
- `rd_go` 三项或（`:322`）：**双弹不可能**（`dma_gnt_i` 显含 `!rd_en`；flush 分支独占 `rd_go`）；**漏弹**也不存在（`host_gnt_i && !stash_v` 与 `dma_gnt_i` 互斥且覆盖非冲刷路径）✓。⚠️ 唯一边界：`flush_r=1` 且主机同拍 `rd_en=1` ⇒ FIFO 只弹一次（flush 那次），主机会读到**即将被丢弃**的头字（无 FIFO 双弹，但两方共用同一 word）——出协议（协议 = clr→cap_en），登记为**未覆盖**。
- 与 `axi_regs` 的合同我回核过：`_proj_pcie/rtl/axi_regs.v:293-295` `mir_pop = mir_rd_sel && !mir_empty` ✓（`!empty` 同门成立），且 `empty` 已含 stash ✓ ⇒ 新拆分不会让主机在"只剩 stash"时空读。

### 2.3 新端口 `dma_data[63:0]` 接线（`board/wrapper_p4.v`）
实接支：`:3829 .dma_data(mir_dma_data)` → `:3855 .src_data(mir_dma_data)` ✓；两个 tie-off 支各补 `wire [63:0] mir_dma_data = 64'd0;`（`:3908` / `:3932`，本支无消费者）✓。`mir_dout` 仍只接 `axi_regs` 的 MIR_DATA ✓。**接线完整，无隐式网风险**（声明在例化前，`:3788`）。

### 2.4 环写口（`rtl/mir_dma_ring.v:83-106`）
- `wr_words` 一次 `+2`（`:105`）⇒ **单位仍是 32 位逻辑字** ✓；TB 有结构性牙：`tb/tb_mir_dma.v:195 chk("A0 wr_words == 32")`（16 次 `push_pair`）、`:327 chk("H3 clr 后计数从 0 起", 2)` ✓。
- bank 对恒 `{0,1}` 或 `{2,3}`：复位/clr 归零 + 每次 +2 ⇒ `wbank[0]≡0` ⇒ `default: (wbank==3)` 那一支（写 `mem3[wrow]` + `mem0[wrow_n]`，`:97`）**结构性不可达**（防御性死码，登记；同时它也保证"两字不同 bank"⇒ 同拍双写不撞同一 BRAM）✓。
- 两个字的顺序：`src_data[31:0]` = 先出（=`{dma_w1,dma_w0}` 的低半）✓ 与 TB `:133 src_data <= {d1, d0}` 一致。

### 2.5 第二修复（`cap_on` 并入写门）有没有引入新问题
- 新写门 `:164` `have && !fifo_full && cap_on`：冻结期**不写**，被握住的字留在累加器（`cap_on` 回来再写）——与头注释"0 = 不写"一致 ✓。
- 冻结期 `acc_*` 不推进而 FIFO 里字照读：`level` 完全按 `fifo_occ_r + stash` 算，**不含**被握住的字 ⇒ **不会多报**（不会把"冻结字"当成可读字）✓。
- ⚠️ 与写门同批的一处**语义放大**：`cap_on=0` 时 `src_beat=0` ⇒ 冻结期到达的源拍**既不计 offered 也不算 drop**（`offered` 口径在 TB 侧同样带 `u_dut.cap_on`，`tb:154` ⇒ 两侧口径一致 ✓）。这是设计选择（"不采集就不计"），但意味着**冻结期丢的字节在 `drop_bytes` 里不可见** —— 头注释已把 `cap_en` 定义为"整段冻结"（含"不计丢"）✓ 一致。

---

## ③ 判据牙口评估

1. **三个镜像突变件确实打在被断言的性质上**（我逐一 `diff` 现役 RTL → 每件**只差 1 行**，且改的正是断言面向的量）：
   `mut_gate:164`（去掉 `!fifo_full`）· `mut_order:182`（`kk==2` 的 b0/b1 交换）· `mut_cap4:156`（`kk` 上限钉 4）。锚点 = `sim/p7b_mir/mut/make_mutants.py:26-36`（要求恰好 1 处命中，命中数打印）✓。
2. ⭐ **G13 有独立牙**（推理链 + 独立复算双证）：
   - 直接证据：`mut_cap4`（复现"4 B/拍结构上限"）⇒ `xdir_mut_cap4/xsim.log:94-97` G13c/d/e/f 全红，`d_drop = 0x960 = 2400 B = 4800 的一半`。
   - 独立复算（我按行转写的循环级模型，同一激励 = 600 拍背靠背 8B）：**新版 `drop=0` / 旧版（32 位写口 + 32 位 accumulator，`kk≤4`）`drop=2400`（恰 50%）** ⇒ **"把写口退回 32 位，G13 必红"**成立 ✓。（口径：真旧版另有 32 位 FIFO/dout 与无 stash 之差；但 G13 命中的性质 = 4 B/拍结构上限，正是本刀靶子。）
   - 反向隔离（好性质）：`mut_gate` 臂里 **G13 全 PASS**（`xdir_mut_gate/xsim.log:92-98`）⇒ 新主判据不是"什么突变都红"的万能灯。
3. 环三突变（`row/rlast/rid`）打在行地址/突发属性上：`xdir_mut_row` 的红灯全是 **A6 逐拍行内容**（`:41-47`）与 **B2 wrap 内容**（`:80-82`）⇒ 有内容牙 ✓（⚠️ 我只核了红灯面与 `mut_aximm.py` 的锚点框架，**未**逐行核三个锚点文本）。
4. p6e 的 **b-wire 突变是"新 64 位写数据口"的独立内容牙**：锚点 = `mut_bwire.py` 改的那一行（新端口那行）✓；其 5 条红 = `M1-B-2e` + `M1-B-3d`×4 = **逐行内容对账**，而计数器判据（M1-B-1/3a）照过 ⇒ **计数 ≠ 内容**已被证明能被分开抓 ✓（这正是它自述的期望 footprint）。
5. ⚠️ **两处"隔离性预期"与实测不符**（不影响力结论，只影响表述精度）：
   - `make_mutants.py:12-14` 写 mut_cap4"只该由 G13 翻红" —— 实测还红 **G8c**（`level==511` 见证变 300）与 **G8e**（`516→300`）。
   - `make_mutants.py:7-9` 写 mut_gate"只该由字节账恒等式（G11c/G8d）翻红" —— 实测 6 条红：G8a/G8b/G8d/G8e/G11c/**G14b**。

---

## ④ 未覆盖 / 未判清单

| # | 路径 | 状态 | 依据 |
|---|---|---|---|
| 1 | **相位 ≠ 0 之后接背靠背 8 B/拍源**（本刀最大盲区） | **未覆盖** | G13 从 `acc=0` 起跑；`tb_app_rx_mirror.v` 无"先喂残拍再灌饱和流"用例（见 ⑤-1） |
| 2 | `K % 8 != 0` 尾字节（1–7 B 停累加器，无读出通路） | **部分覆盖**：G9a 只覆盖 2 B 残余 + clr 清除；端到端"工具字节账差 1–7 B"**未覆盖**（工具也还没改） | `tb:610-636` |
| 3 | `cap_en` 中途开关（跨暂停拼接） | **未覆盖**（门只有"满态冻结不复制"G14）；头注释登记为已知语义边界 | `app_rx_mirror.v:41-44` |
| 4 | `flush ∧ host 弹` 同拍 | **未覆盖/未判**（我推断无 FIFO 双弹，但主机会读到被冲刷的字） | `app_rx_mirror.v:322,330` |
| 5 | 环 `wbank==3` 跨行分支 | **未判**（结构性不可达 ⇒ 也无用例） | `mir_dma_ring.v:97` |
| 6 | `level` clamp 的 `occ=256 ∧ stash_v=1`（=513）档 | **未覆盖**（同分支，`occ=256` 档有 G8c 见证=511 ✓） | `app_rx_mirror.v:340` |
| 7 | 两读出口**混用** | **单元层已覆盖**（G12i–p：G12l 见证 stall=1 gnt，G12n/p 见证"不丢字"）；**整链层（p6e）未覆盖**（p6e 只分别用 DMA 路与主机路） | `tb:446-463` |
| 8 | H2C 写通道从未激励 / clobber 检测器未触发 | **未覆盖**（报告 §6.5 已登记） | —— |

---

## ⑤ 新发现问题（按严重度）

### ⑤-1【高 · 结构性 + 文档过宽】写侧只有"相位 0"能吃满 8 B/拍；相位 ≠ 0 遇饱和源 = **恒丢 50%**（与旧版同族的残余）
- **位置**：`rtl/app_rx_mirror.v:154-164`（`room/kk/drain_all/pend_after`）；**结论句**在 `:16-18`（"**'结构吞吐类'丢字节对 ≤ 8 B/拍的源不可达**"）与 `_proj_10g/notes/p8_mir8b_impl_20261011/SELECTION.md:8`。
- **机制（逐拍）**：`room = 8 − acc_cnt_r`，`kk = min(n_cur, room)`；`pend` 只在 `drain_all`（本拍搬空）那拍才接新拍 ⇒ `n_cur=8 > room`（room=1..7）时：本拍搬 room 个字节 **+ 拒收同拍到来的新拍**，下一拍才轮到 ⇒ 稳态 2 拍/8B 拍。**它只在 `acc_cnt=0` 时不存在**。
- **最小复现（不跑 EDA；我另跑的循环级模型，源码见附录）**：
  ```
  先喂 1 个 4B 拍，再 60 个背靠背 8B 拍:
    新版: drop = 240 / offered = 484   （8B 流丢 50%）
    相位扫描 phase=1..7: 丢幅恒 0.500 ; phase=0: 0.000
  6 段 1460B（=8×182+4，满 TCP 段）无间隙: drop 2184/8760 = 24.9%
  同 1460B 但拍稀疏到"每 9 拍 1 个": drop 0
  ```
- **现实触发面**：镜像源**逐帧长度 ≢ 0 mod 8** 且拍流**密集**。现役默认源（UDP，1472 B = 184×8）**安全**；`src_sel=1` 的 TCP 源满段 **1460 B** 是危险档（本刀设计里明确要用的第二源）。⚠️ **0x1F 板级读数"偶数组全收奇数组全丢"本身就是"源拍密集"的证据**（旧版对稀疏源不丢）⇒ 该端口确实是 1 拍/周期量级的源。
- **对验收的直接影响**：报告 §7 的前置 "**K % 8 == 0**" 只约束**总量**，管不住**逐帧相位**（8 帧 ×1001 B 也满足 K%8==0）；下轮板级若用"帧长 ≢0 mod 8"的载荷，会出现 "drop_bytes > 0 / MIR_VERIFY 失配"，而这不是时序也不是随机噪声。
- **口径**：`drop_bytes` 照常计数（**不静默**）✓；本项**不是回归**（旧版在相位 0 就恒丢 50%），但**本刀"消掉结构吞吐类丢字节"的范围被文档说宽了**。建议二选一：① 把结论句改成"**≤8 B/拍且 8 字节相位对齐**的源不可达"并在验收里加"逐帧长度 % 8 == 0"前置 + 一个反例用例；② 真修（例如给 `pend` 加深或允许"半字落袋 + 续接"）。

### ⑤-2【中 · 证据】报告与 commit message 把 p6e 两突变臂的 FAIL 数**写反**
- 原件按 `files.f` 认臂：`sim/p6e_pcie/dir_mut/files.f:211` = `wrapper_p4_mut_srcinv.v` ⇒ 该目录 `xsim_mut.log` = **27 FAIL**（含 M1-2a/3a/7a/9a…、M1-10b/c/d/e、M1-B-1/2e/3a/3d —— 与"源选反了"的级联一致）；`dir_mut2/files.f:211` = `wrapper_p4_mut_bwire.v` ⇒ `xsim_mut2.log` = **5 FAIL**（恰为 M1-B-2e + M1-B-3d×4 = 内容对账 = `mut_bwire.py` 自述的期望 footprint）。
- 报告 §4 / commit message 写的是 "`bwire` **FAIL 27** / `srcinv` **FAIL 5**" ⇒ **两个数字对调**。牙口结论（两边都红）不受影响，但这是**报告读数与原件不符**。

### ⑤-3【低 · 文档】`make_mutants.py` 的"只该由 X 翻红"隔离性预期与实测不符
mut_cap4 还红 G8c/G8e；mut_gate 还红 G8a/G8b/G8e/G14b（见 ③-5）。建议改措辞为"至少由 X 翻红"。

### ⑤-4【低 · 证据强度】`M1SYNTH_MIR_IMPORTED=1` 被当成"编的就是带 M1 的 wrapper"的见证 —— 它本身只是"文件存在并被 import"
`_proj_10g/notes/p8_mir8b_synth/synth_only_ku5p.tcl:88-94` 是 `file exists` 分支；真正的**网表**见证是同脚本 `:177-179` 的 `get_pins -hierarchical -filter {NAME =~ *u_mir*}` ⇒ `M1SYNTH_MIR_PINS = 19090`。报告两句都给了，但把 IMPORTED 说成 Netlist 见证**偏宽**。⚠️ 另注：`*u_mir*` 通配同时命中 `u_mir_ring / u_mir_c2h / u_mir_h2c` ⇒ 19,090 是"整个 M1 块"的引脚数，**不是** `app_rx_mirror` 内部（若要更硬，应按 `u_mir/` 精确查一次）。

### ⑤-5【低 · 契约】`MIR_STATUS.ver` 未 bump（仍 `4'd3`），且**两个交付件都没提这件事**
`_proj_pcie/rtl/axi_regs.v:304-311`：`mir_status = {8'd0, mir_ctrl_r[2], 4'd3, …}`，注释写明既定规则 = "**位语义变了就 bump**"。本刀**不改任何位语义/地址表** ⇒ **不 bump 可辩护**；但本刀改了**字节粒度契约（K%4 → K%8）**，这是主机可观测的（K≡4 mod 8 由"合法"变"尾部滞留"）⇒ **"bump 还是不 bump"应当有一个明写裁定**（现 REPORT/SELECTION 都没写），否则下一个工具作者只能猜。

### ⑤-6【低 · 工具】`p7b_mir_dump.cpp` 的硬门仍是 `K % 4 == 0` ⇒ **K ≡ 4 (mod 8) 会被接受**，然后在板上表现成"短 4 B 的账目/失配"
`_proj_pcie/p7b_biz/p7b_mir_dump.cpp:418-419`（`if (want % 4 != 0) … FATAL`）与 `:447-450` 的 selftest T3 都是 K%4 口径。报告 §2.1/§6.2 已登记"8 对齐属范围外未做"✓，但**没有登记这个具体失败形态**（下轮板级若用 K≡4 mod 8 会踩到一个"响亮的 FATAL 变成安静的短读"）。

### ⑤-7【登记 · 环境】审查期间工作树被并行轮改写（不是本刀的问题，但会污染后续取证）
`board/wrapper_p4.v` 在我审查期间从 `a3f49322…`(BID 0x1F) 变成 `8d9374c5…`(BID **0x20** + 新注释)，`git status` 现为 ` M board/wrapper_p4.v`（另有多件 `_proj_*/*.sh` 也 dirty）。⇒ **任何"指纹 = 现读值"的引用在本轮之后都必须现读重核**（本件 ①-9 的 ✓ 只在"13:13 时刻"成立）。

---

## ⑥ 我的保留意见（不下 PASS/FAIL；若要裁定，缺什么证据）

1. 本刀**不出位流**（HEAD 的 `BUILD_ID_V = 0x1F`）⇒ "板级已修"**不在本刀范围**；板上 0x1F 是**含缺陷版**。裁定"修复生效"至少还缺：**0x20 位流 + 板级 `drop_bytes == 0`**，且该板级用例**必须**包含一个"**逐帧长度 ≢ 0 mod 8 且拍流密集**"的载荷（否则 ⑤-1 的盲区会被原样带过去，判据会给出"通过"的假象）。
2. 要判 ⑤-1 是"设计边界"还是"缺陷"，缺：① 现役源（UDP app RX 口）在**满速**下的**逐拍 tkeep 序列**（可 xsim 从 `app_udp_pattern` 打真实流，或 p6e 层注入）；② TCP 支（1460 B 段）的**拍密度**证据；③ 判据所有者的一句裁定（"帧长按 8 字节对齐"是否可接受为前置条件）。
3. 要判 ⑤-2/⑤-3：只需重跑两臂并在 `files.f` 现场认臂（我已认过，报告侧是一行修正）。
4. 要判 ⑤-5/⑤-6：`ver` 的明写裁定 + 工具 `--bytes` 的 8 对齐 + 一组 `K ≡ 0/4 (mod 8)` 的正负用例。
5. 未判项（④ 全表）在**同一批**里没有判据，若下一轮要把它们写进验收，需先立判据（尤其 ④-4 的 flush∧host、④-3 的 cap_en 中途开关）。

---

## 附录：本次审查用到的**非 EDA** 复算（可重跑）

```bash
# 1) 事实核对（全部只读）
grep -c "\[PASS\]" /c/.../sim/p7b_mir/xdir_real/xsim.log      # 81
grep -c "\[FAIL\]" /c/.../sim/p7b_mir/xdir_real/xsim.log      # 0
grep -n "GATE:" /c/.../sim/p7b_mir/xdir_{mut_gate,mut_order,mut_cap4}/xsim.log
grep -n "mut_bwire\|mut_srcinv" /c/.../sim/p6e_pcie/dir_mut{,2}/files.f   # ← 认臂的唯一依据
# 2) 证据绑定：归一化行尾后与 HEAD blob 逐行 diff（应只差 1 行突变）
sed 's/\r$//' sim/p6e_pcie/mut/wrapper_p4_mut_bwire.v > /tmp/m.v
git show HEAD:board/wrapper_p4.v > /tmp/h.v && diff /tmp/m.v /tmp/h.v   # 只差 3855 行
# 3) 单点突变核对（每件只差 1 行）
diff rtl/app_rx_mirror.v sim/p7b_mir/mut/app_rx_mirror_mut_{gate,order,cap4}.v
```
循环级模型（写侧逐行转写；`/c/Users/zhxue/anaconda3/python.exe` 跑，含 `kk/room/drain_all/pend_after/load/drop_now/have/wr_en` 与单状态块）：
- 结果：`aligned 600×8B`：新版 `drop=0` / 旧版 `drop=2400`；`phase=1..7` 各 `drop=320/640 = 0.500`；`1460B 稠密 6 段`：`drop=2184/8760 = 24.9%`；`1460B 每 9 拍 1 拍`：`drop=0`。
- ⚠️ 该模型是**我的复算**（不是本刀交付件）；它只覆盖**写侧**（假设 FIFO 不满）；与 G13 日得读数互不矛盾（G13 = 相位 0 特例）。
```
本件由只读审查 agent 于 2026-10-11 写；未改动任何其他文件。
```
