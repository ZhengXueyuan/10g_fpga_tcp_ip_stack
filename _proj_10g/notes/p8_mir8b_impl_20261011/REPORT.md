# P8 阶段三 · 采集侧 8 B/拍修复（`app_rx_mirror` 4 B/拍结构缺陷）—— REPORT

> ⚠️ **报告出处声明（必须随本件一起读）**：**本 REPORT.md 由 TL 撰写**，不是原实现 agent 交出的。
> 过程史实（如实登记）：实现 agent 在 **13:29 完成综合、13:33–13:34 落完全部查询报告**后，
> 自 13:34 起 ~50 分钟无任何落盘/进程活动 ⇒ **TL 于 14:20 误判挂死并停掉它**；随即发消息恢复，
> 它回"正在收尾"并发出**一条含 `rm -rf` 的 Bash**（清 scratch）—— 该命令**18 分钟未返回**
> （疑似卡在权限/工具返回）⇒ **TL 于 14:45 二次停掉它并接管收尾**。
> ⇒ **本报告全部内容取自 13:10–13:34 的原始落盘件 + 现读源码**，每条附路径/行号；
> **凡 agent 只在"脑子里"、未落盘的口径声明，本件不代它主张**。
> scratch 清理 = 用户 2026-10-11 裁定「照历史做法：删盘 + 加忽略」（TL 执行；`prj_p8mir8b` 282 MB 已删）。

## §0 缺陷（板级实测）与定性

镜像采集侧结构上限 = **4 B/拍**（32 位 FIFO 写口 + 跨拍累加器），而源（`app` RX 口）**一拍吐 8 B** ⇒
对 8 B/拍连续源**恒丢 50%**。板级三条独立签名（`p8_board_20261011/REPORT.md` §9，位流 `0x1F`）：
丢字恒 = 采集量一半 / 偶数组全收奇数组全丢 / `first_mismatch` 恒 8。

⇒ 这是**结构吞吐类**缺陷（不是时序、不是概率），修复 = 把写侧做到 8 B/拍。

## §1 改动清单（`git diff --stat` 现读；BID 未 bump = 仍 `0x1F`，本刀不出位流）

| 文件 | 行数 | 内容 |
|---|---|---|
| `rtl/app_rx_mirror.v` | +234/− | 写口 32→**64 位**（一拍吸收 0..8 B）；读侧 **64→2×32 拆分（stash）**；DMA 口改 **2 逻字/拍**（新端口 `dma_data[63:0]`）；**`cap_on` 并入写门**（第二修复，见 §3）；`level` 改 `2×occ64 + stash_v`（clamp 511）；头注释契约重写 + 旧契约逐字留档 |
| `rtl/mir_dma_ring.v` | +33/− | 环写口 32→**64 位**（一拍写 2 个逻字）；`wr_words` 计数单位**仍 = 32 位字** |
| `board/wrapper_p4.v` | +30/− | M1 块接线：新端口 `mir_dma_data[63:0]`；¬M1 两支 tie-off 同步补 `64'd0`；注释同步。**`:1319-1322` app 总线 tie-off 未动**（逐字保持）|
| `tb/tb_app_rx_mirror.v` | +520/− | 8 B/拍新契约：**G13**（新主判据）/ **G8 改写**（旧"结构必丢"构造已不可达 ⇒ 改 FIFO 满类）/ G2/G4/G11/G12a..k 手锚重算 |
| `tb/tb_mir_dma.v` | +20/− | 与 64 位写口/2 字对齐 |
| `sim/p7b_mir/mut/*` | 3 改 + 2 新 | 突变臂 `gate`/`order` 更新 + 新 `cap4`（cap_on 门反转）+ `make_mutants.py` |
| `sim/p7b_mir/run_tb_app_rx_mirror.bat` | +11/− | 四臂驱动 |
| `sim/p6e_pcie/tb_p6e_pcie_wrapper.v` | +93/− | 4 B→8 B 注入期望（含 dma 口 2 字对）|
| `sim/p6e_pcie/mut_bwire.py` | +6/− | b-wire 突变锚点随 M1 块更新 |

## §2 契约与口径（哪些变了、哪些逐字不变）

**变了**：
1. **粒度 4 B → 8 B**：发端总字节数 K 的**前置条件 = `K % 8 == 0`**；尾部 1–7 B 停在累加器（无读出通路）——与旧版 `< 4 B` **同性质**的已知语义。⇒ **PC 工具 `--bytes` 硬门与字节账协议需 8 对齐 = 读侧/工具同步项，本轮按派单明确不做**（见 §6）。⚠️ **补充（见 §8-C2）**：`K%8==0` 只约束**总量**，**管不住逐帧相位** ⇒ 该前置**不足以**保证 `drop==0`。
2. **"结构吞吐类"丢字节对 ≤8 B/拍源不可达** ⇒ `drop_bytes` 只剩 **FIFO 满**一类；头注释旧版"①暂存忙（4 B/拍上限）"已删并逐字留档在文末。⛔ **本句 2026-10-11 被审查判定"过宽"（见 §8-C2）：只对"8 字节相位对齐"的源成立** —— 相位 ≠ 0 遇 8 B/拍密集源仍恒丢 50%（结构性；`drop_bytes` 照常计数、不静默）。
3. 新增端口 `dma_data[63:0]`（DMA 口 2 逻字/拍；`[31:0]` 先出）。

**逐字不变（下游语义）**：
- `MIR_DATA` 读 = 弹出**一个 32 位逻字**；`MIR_STATUS.level` **单位仍是 32 位字**（内部 = `2×dbg_occ_r + stash_v`，悲观口径 ⇒ 只少报 ⇒ "读恰好 level 字"不下溢；9 位满量程 clamp 511 = 只少报）；
- 环 `wr_words`（→`MIR_DMA_CNT` 0x148）**单位仍是 32 位字**；
- snoop 合同（只读 `s_tready`、永不驱动握手）、`clr` 排空式冲刷、`cap_en` 冻结语义、空态哨兵 `0x5A5A5A5A` 由消费者选路 —— 全部未动。

## §3 第二个修复：`cap_on` 并入写门（本轮同批发现）

**旧版**（`git show HEAD:rtl/app_rx_mirror.v`）：写门 `wire wr_en = have && !fifo_full;`（`:133`）**不含 `cap_on`**，
而状态推进块是 `else if (cap_on)`（`:186`）⇒ 存在一条序列：
**`acc` 凑满一个整字且 FIFO 满（字被"握住"）→ 主机写 `cap_en=0` → 主机随后读 FIFO 腾出空间**
⇒ `wr_en` 仍组合为 1 ⇒ **同一个字被反复写入**（主机每读一个字就补一个重复字，最多 DEPTH 份）。
**本版**：`wire wr_en = have && !fifo_full && cap_on;` ⇒ 冻结期**不写**，被握住的字留在累加器（`cap_en` 回来再写）——与头注释"0 = 不写"逐字一致。

⚠️ **口径（不许过度声称）**：该序列**在板级未观测到**（`0x1F` 位流读数以"丢 50%"为主，未见重复签名）；
**"未观测到" ≠ "不存在"**，也**没有**在板上复现该序列。⇒ 登记为**同族潜伏修复**，触发条件的板级可达性 = **未定**。

## §4 门读数（全部为 **2026-10-11 13:10–13:34** 的本次落盘件）

| 门 | real | 突变臂（证明门有牙） | 原始件 |
|---|---|---|---|
| 单元门 `tb_app_rx_mirror`（新契约） | **PASS_ALL**（81 PASS / 0 FAIL） | `gate` **FAIL 6** / `order` **FAIL 2** / `cap4` **FAIL 6** | `sim/p7b_mir/xdir_{real,mut_gate,mut_order,mut_cap4}/xsim.log` |
| 环门 `tb_mir_dma` | **PASS_ALL**（checks=45） | `row` **FAIL 11** / `rlast` **FAIL 8** / `rid` **FAIL 9** | `sim/p7b_mirdma/xdir_*/xsim.log` |
| p6e 全链 `tb_p6e_pcie_wrapper` | **115 PASS / 0 FAIL / PASS_ALL** | `srcinv` **FAIL 27** / `bwire` **FAIL 5**（⛔ **本行 2026-10-11 已更正**：原写反，见 §8-C1；认臂依据 = `dir_mut/files.f:211`=srcinv、`dir_mut2/files.f:211`=bwire） | `sim/p6e_pcie/xsim_p6e.log`、`dir_mut{,2}/xsim_mut*.log` |
| p5_wrapper（矩阵内**唯一**编 `wrapper_p4.v` 的常驻门） | **P5 WRAPPER OK** + `[P4GUARD OK]` | —（含于矩阵 17 门） | `sim/p4gates/work_20261011_131319/p5_wrapper/{xsim_w.log,_gate_console.log}` |
| 矩阵指纹 before/after | **`DIGEST_ALL` 逐字相同** `b2b957a6…`；清单含 `wrapper_p4.v` @ `sha256 a3f49322…` = **现读文件值**（证据绑定） | — | `sim/p4sim/P4_MATRIX_FINGERPRINT_20261011_131319_{before,after}.txt` |

⭐ **新主判据 G13**（本刀存在理由）：**持续 8 B/拍源（背靠背 600 拍）+ 2 字/拍排空 ⇒ `drop_bytes == 0`** —
`offered=4800 gold_n=4800 gnt=600 level=0 d_drop=0 dword_mis=0`（`xdir_real/xsim.log:90-98`）。
**G8 已改写**：旧构造（"8 B/拍超 4 B/拍上限 ⇒ 必丢"）随修复**结构性不可达** ⇒ 换成 FIFO 满类构造，仍 `drop>0` 有读数（`:510-538`）。

## §5 synth 检查点（`_proj_10g/notes/p8_mir8b_synth/`，13:17–13:34）

- ⭐ **`M1SYNTH_MIR_IMPORTED = 1`**（`synth_outer.txt`）= **编的就是带 M1 的 wrapper**（防"跑了却没跑"）。
- **资源（synth 面）**：CLB LUT **84,162**（logic 76,226 / memory 7,936）、FF **79,080**、BRAM tile **354**、URAM 0、DSP 4、BUFGCE 2（`synth_p8mir8b_util.rpt`）。
  对照：**0x1F 后布线** LUT 77,536 / FF 74,657 / BRAM 352（`p7b_build_0x1F/REPORT.md`）；m1p2b synth 臂 83,490 / 79,011 / 354。
  ⇒ synth 面 LUT **+672**（vs m1p2b 臂）、BRAM **持平 354**（64 位 FIFO 深度不变仍 256 ⇒ 宽度变化没吃 BRAM）。
- **时序（synth 面）**：WNS **−0.371** / WHS −0.661（`synth_p8mir8b_timing_summary.rpt`；0x1F synth 臂 −0.377）。
- ⭐ **DP 域（`g_hw.clk_out0`）synth 前 20 = 单一旧族**：`u_tcp_tx/FSM_sequential_rx_state_reg[0]/C → u_app/stg_reg[*]/CE`
  （20 条 = 20 个不同宿，全 −0.371；`dp_worst_p8mir8b.rpt`）；**`u_mir*` 在所有 20 条里 0 命中**
  ⇒ **M1 改动没有成为 DP 域 synth 最差锥**（与前两轮同形态）。
- ⚠️ **口径**：synth 面负 slack 是**既有现象**（0x1F 的 −0.377 在**后布线兑现为 DP `+0.108` / 0 失败端点**）
  ⇒ **不许把本行 −0.371 当"时序坏了"**；真正的判据 = **后布线**（下一轮构建 0x20）。
- 另归档：`pb_query_stdout.txt` / `pair_*` / `dp_worst_*` / `pcie_worst_*` / `pb_{fifo,ring,c2h,h2c,accreg,stash}_{to,from}_*`（按 M1 端口定向查询，19,090 个 M1 引脚）。

## §6 未定项 / 盲区（不许当已答）

1. **板级未验**（本轮到 synth 检查点为止）⇒ 下一步 = **构建 0x20 → 重跑板级演示**（§7）。
2. **读侧 / 工具同步未做**（范围外，按派单）：`K % 8` 前置 ⇒ PC 工具 `--bytes` 硬门与字节账协议要 8 对齐；
   `p7b_mir_dump.cpp` **本轮未改**（12:33 之后再无改动）⇒ **工具 selftest 本轮的运行证据 = 未找到（按"未跑"读）**。
3. **lint 未复跑**（`sim/p6b_lint/` 日志仍是 **09-30**）；且其 `files.f` **不含** `app_rx_mirror.v` / `mir_dma_ring.v`
   ⇒ **即便复跑也覆盖不到本刀新件**（常驻矩阵/lint 清单盲区，已登记项，随 OPEN_ITEMS）。
4. **`cap_on` 写门修复的板级可达性未证**（§3）。
5. **H2C 写通道从未激励**（沿用既登记）；**clobber 检测器全程未触发**（沿用）。
6. **DMA 口与主机口混用**的语义边界（登记在头注释：cap_en=1 且 dma 常高时两出口抢同一队列 ⇒ 不许混用；
   混用时唯一停摆点 = 高位半字进 stash 后 FIFO 恰好空）。**产品路径（dma 单独用）不受影响**。
7. 本轮**未做**：读侧 BID-only 同步、BID bump、出位流、烧录 —— 均按派单排除。

## §7 下一步（TL 排程）

1. **提交本刀**（显式清单；含 `.gitignore` 新增 `_proj_10g/notes/p8_*_synth/prj_*/`）。
2. **构建轮：BID → `0x20`**（`BUILD_ID_V = 32'h00000020`；构建铁律：只走 `board/run_build_p7b_ku5p.bat`，
   **不从被构建的工程烧位流**）+ **读侧 BID-only 同步**（`apply_readside_bid1c.py --bid 0x20` 链式前进）
   + 矩阵回归 + 完整构建 + 归档 `p8_build_0x20/`。
3. **重跑 P8 板级演示**（判据不变）：`p7b_udp_src` 定速发（**K % 8 == 0**）→ `p7b_mir_dump --dma --src udp`，
   判 **`MIR_VERIFY rc=0 first_mismatch=-1`** + `clobber=0 / short=0 / 计数闭合`。

---

## §8 审查后更正与追加（2026-10-11 晚；全件 = `REVIEW.md`，只读对抗审查，未跑 EDA）

### C1【证据·已改】p6e 两突变臂 FAIL 数写反（⚠️ 同错也在 commit `193f06a` 的信息里）
原写 `bwire` 27 / `srcinv` 5 —— **原件相反**：`dir_mut/files.f:211` 编 `wrapper_p4_mut_srcinv.v` ⇒ `xsim_mut.log` = **27**；
`dir_mut2/files.f:211` 编 `wrapper_p4_mut_bwire.v` ⇒ `xsim_mut2.log` = **5**（5 条恰为 `M1-B-2e` + `M1-B-3d`×4 内容对账）。
两边都红 ⇒ **牙口结论不变**，数字对调。**上表 §4 已就地更正**；commit 信息**不改历史**（已推送），以本行为准。

### C2【高·结构性】⭐⭐ 相位 ≠ 0 时，8 B/拍密集源仍**恒丢 50%** —— 本刀"消除结构吞吐类丢字节"的范围被说宽了
- **位置**：`rtl/app_rx_mirror.v:154-164`（`room/kk/drain_all/pend_after`）；结论句 `:16-18` + `SELECTION.md:8`（两句都**过宽**）。
- **机制**：`pend` 只在"本拍搬空"（`drain_all`）那拍才接新拍；`n_cur=8 > room(=8−acc_cnt)` 时本拍只搬 `room` 字节 **并拒收同拍到来的整个拍** ⇒ 相位 ≠ 0 的密集流下**稳态 2 拍吃 1 拍**。
- **触发面**：镜像源**逐帧长度 ≢ 0 mod 8**（**TCP 满段 1460 B = 8×182+4** 是危险档；UDP 1472 B 安全）**且拍流密集**。
  ⚠️ `0x1F` 板级"偶数组全收奇数组全丢"本身就是"源拍密集"的旁证（旧版对稀疏源不丢）。
- **证据强度**：审查 agent 的**循环级模型复算**（`phase=1..7` 丢幅恒 0.500；`phase=0` 为 0；6 段 1460 B 稠密 = 24.9%；同流稀疏 = 0）
  + **TL 现读 RTL 逐拍手推一致**。⛔ **板级未观测**（0x1F 是 4 B/拍旧版、结构性测不到本项）⇒ 性质 = **"模型级已证 + 板级未测"**，不许写成"板上已出现"。
- **影响**：a) §2 的前置 `K%8==0` **不足**（8 帧 ×1001 B 也满足 K%8==0）；b) `src_sel=1`（TCP，本里程碑既定第二源）**按现设计不可用**；
  c) 本轮起的板级验收**必须**含一个"逐帧长度 ≢0 mod 8 **且**拍流密集"的用例，否则判据会给出"通过"的假象。
- **两条出路（待板级 A/B 后裁定）**：① **先板级 A/B 证伪/证实**（0x20 位流 + `--paylen 1472`（相位 0）vs `--paylen 1470`（相位 6）两臂，看 `ΔW70/drop_bytes` 与 `MIR_VERIFY`）——
  ⭐ 这一步同时把"0x20 的修复在相位 0 档真的成立"与"相位 ≠ 0 真的丢"两件事**同时**变成板级观测；
  ② 若证实 ⇒ **真修**（把 8 B 单槽 `pend` 换成 ≥16 B **字节粒度**弹性暂存：每拍"从头部消耗 `min(room, stg_cnt)` 字节 + 尾部追加新拍"，审查已给出容量界 `stg_cnt ≤ 16`；
  代价 ≈ 数百 LUT，落 **DP 域**、要吃 DP 余量）⇒ 构建 `0x21`（可与 §5-5 的 `ver` 裁定、§5-6 的工具 8 对齐、`:16-18` 注释更正**同批**）。

### C3【证据强度·更正】`M1SYNTH_MIR_IMPORTED=1` 不是"网表见证"
它只是 `synth_only_ku5p.tcl:88-94` 的 **`file exists`** 分支（"文件被 import"）。**网表级见证**应为 `:177-179` 的
`get_pins -hierarchical -filter {NAME =~ *u_mir*}` ⇒ `M1SYNTH_MIR_PINS = 19090`。⚠️ 且该通配**同时命中** `u_mir_ring/c2h/h2c` ⇒ 19,090 是**整个 M1 块**的引脚数，**不是** `app_rx_mirror` 内部。
（§5 那句"编的就是带 M1 的 wrapper"应读作：**文件在、且 M1 块进了网表**，两件事都有读数，但强度分属两件。）

### C4【待裁定】`MIR_STATUS.ver` 未 bump（仍 `4'd3`）
既定规则 = "位语义变了才 bump"（`_proj_pcie/rtl/axi_regs.v:304-311`）；本刀不改位语义 ⇒ **不 bump 可辩护**，
但改了**字节粒度契约（K%4→K%8，主机可观测）** ⇒ 缺一句明写裁定（见 C2 的"同批"）。

### C5【登记】工具 `p7b_mir_dump.cpp:418-419` 硬门仍 `K % 4` ⇒ `K ≡ 4 (mod 8)` **会被接受**，然后在板上表现为**安静的短读**
（而非响亮的 FATAL）。"8 对齐属范围外"已登记，**该失败形态**此前未登记。

### C6【登记·环境】审查期间工作树被并行构建轮改写（`board/wrapper_p4.v` BID 0x1F→0x20）
⇒ **"指纹 = 现读值"的绑定只在该时刻成立**，后续引用一律**现读重核**。

### C7【未覆盖清单】见 `REVIEW.md` ④ 全表（相位 ≠0 密集流 / `K%8≠0` 尾字节端到端 / `cap_en` 中途开关 / `flush ∧ host 弹` 同拍 / 环 `wbank==3` 死码 / `level` clamp 513 档 / 两读出口整链混用 / H2C 与 clobber）——**本轮一律"未覆盖/未判"**。
