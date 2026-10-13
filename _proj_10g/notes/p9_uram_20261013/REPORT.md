# P9 追加轮 —— URAM 板内缓冲：设计块 + RTL 实施 + 单元门（实施报告）

**日期**：2026-10-13 · **工作树**：`D:\repo\XCKU5PMini\udp_hls_10g`（HEAD = `afa766f`）
**⚠️ 复核轮订正 (2026-10-13, 同日)**：本件已被 `REVIEW.md`（对抗复核）+ `gate_stdout_fix/` 的
**修订轮**跟进；逐条修订与门重跑读数见 **`FIX_REPORT.md`**。就地订正两处：§5.3 的"只差那一行 +
3 行注释"→ **1 行代码 (注入量) + 4 行注释**（`diff 722,726c722`；复核 F7②）；§1.6 的
"clr 拍不取数"只覆盖 **up 侧**，dn 侧已补门（`pop &&= !clr`，见 FIX_REPORT F3；复核 F7③）。
**本件性质**：设计块（先写）+ RTL 实施 + 单元门 + 既有门回归。⛔ 未跑综合/未布线/未上板/未烧录；
本机全程只有 xsim（无 Vivado 并行）。不下 PASS/FAIL 裁定、不写"时序已解决"。未测处写"未测"，未观测处写"未观测到"。

**⭐ FIX 轮订正块 (2026-10-13, 同日; 依据 = `_proj_10g/notes/p9_xverify_claude_20261013/A_URAM_VERIFY.md` 的独立验证)**：
就地订正两类（正文其余逐字保留，各处以 ⛔ 标记 + 原文引述）——
① **缓冲占用上界 `4099 字` → `4100 字 = 32800 B`**（§1.3 口径句 / §1.7② / §3；真上界 = `DEPTH(4096) + CAP(=OQ=4)`
且 „`occ==4096 ∧ inv==4`" 联合可达 —— **"4099"是低估 1 字 (8 B)**；单元门 G2b 判据 `[4096,4100]` 本就按真上界设 ⇒
**是文本错、不是门错**；本件不改 RTL 逻辑、不改 TB 判据）；
② **式 B 中途上界口径精化**（§3：中途差额 ≤`32824` → **≤34872 B** = 32800 + 镜像 FIFO ≤2048 + acc/stg ≤24；
且 `--resid-max-mirror` 默认 `24` **只对"停源 + 排空到 early-stop"的终态成立**。工具侧只改注释/帮助文字，
**默认值未动**；新选项 `--resid-max-mirror-mid` 本轮**只登记、不实现**）。
③ **门补强 + 复跑（A-K5/A-K6，本件 §4/§8 按 FIX 轮口径读）**：`mut_uram.py` 补 **3 臂**
（`mut_clrv` = clr 分支部分清/`mut_omem` = FWFT 读错槽/`mut_oocc` = `o_occ` 丢 `+arr_v` ——
补上验证点名的"clr 分支内部"与"64 位数据面"两类零覆盖）；TB 加 **G4b/G8b 换种子复跑**（相位覆盖 ≥3 对种子）。
**FIX 轮门读数：real = PASS_ALL（66 判据 / 0 FAIL）+ 15 突变臂全 MUTANT-CAUGHT + guard 两臂按预期；
`p9_axis_stream` real / `p6e_counters` / `p6e_fullchain` 三门 PASS_ALL**（详见 FIX 轮原件 §3）。
（订正轮原件 = `_proj_10g/notes/p9_xverify_claude_20261013/FIX_20261013.md`。）
**任务口径**（TL 派单）：镜像 aux 口与 `axis_c2h_stream` 之间加一个 URAM288（≈32 KB 载荷）板内缓冲，吸收
主机 `read()` 空档造成的丢字节；合同必须保持（aux 合同 / `MIR_DMA_CNT` 口径 / 不新增丢字节计数器 / 读侧语义 /
两条工具恒等式）；改动面最小；单元门 + 负对照。
（落盘说明：REPORT.md 由 TL 代落盘 —— 平台拒写 .md 的已知间歇故障；正文逐字为实施 agent 回传。）

## §0 一页结论

| 项 | 结论 |
|---|---|
| 改动面 | 新增 `rtl/mir_uram_fifo.v`（245 行）；`board/wrapper_p4.v` 功能性 **4 处**（u_mir 3 根 aux 接线改指缓冲 + 缓冲例化；`u_mir_axis` 一行未改）；新增门 `sim/p9_uram/`；`sim/p6e_pcie/*.bat` 4 个各 +4/−1（xpm 库登记） |
| 模块 | 单时钟同步 FIFO：URAM288 4096×64（**32 KB 载荷**）+ 4 字弹性寄存器堆 + 3 级读流水；写口 = 镜像 aux 口（有空间才拉），读口 = 与镜像同款同拍 FWFT 合同喂成形器 |
| 容量账 | 32 KB ÷ 1.25 GB/s ≈ **25.6 µs**（改前 = 镜像 FIFO 2 KB ⇒ ≈1.6 µs）⇒ ×16 |
| 吞吐 | 稳态 **1 字/拍**（xsim 实测 300 弹 / 300 拍）；首字延迟 **4 拍** |
| CDC | ⭐ **不需要**：接线点两侧都在 `pcie_axi_aclk`（250 MHz）。基线里"写侧 dp_clk / 读侧 pcie"说的是 `u_mir` 内部那条边界（其 `u_fifo` = `fifo_async`）；本模块在它之后（§1.2 行号证据） |
| 丢字 | 不新增任何计数器：满 ⇒ 不拉 `up_req` ⇒ 镜像 FIFO 自然满 ⇒ 丢字节仍只记 `W70`；"取走必交付"有结构性保证（门 G9e 终态账闭合 0 差） |
| 门（新增） | real = **PASS_ALL（43 判据 / 0 FAIL）**；7 突变臂**全红**（含 2 臂走 RTL 结构性 FATAL 路径）〔⛔ FIX 轮现读数：real = **66 判据 / 0 FAIL**；突变臂 = **15 条全 MUTANT-CAUGHT** + guard 两臂按预期 —— 期间经复核轮 F2/F3/F4 与 FIX 轮 A-K5/A-K6 扩门，本条按"当时"读，现口径见顶部 FIX 轮块〕 |
| 门（既有） | `p6e_counters` **PASS_ALL** · `axis_shaper_real` **PASS_ALL** · `mir_unit_real` **PASS_ALL** · `p5_wrapper` **EXIT 0** · `aliasgate` **OK** · ⚠️ `p6e_fullchain` = 1 红（`P9-B-3d`，判据前提；诊断复跑 ⇒ 整门 PASS_ALL，见 §5.3） |

## §1 设计块

### 1.1 信号级接口图

```
  数据面 dp_clk 156.25MHz            pcie_axi_aclk 250MHz（本刀新增的一切都在这一侧）
        app RX 流 ──snoop(只读)──► app_rx_mirror ──u_fifo(fifo_async 64b×256=2KB; dp→pcie 的 CDC 在此模块内)──► aux 读口(rd 域)
                                                                              │                  │
                                                                    ①主机 BAR 口              ②aux 口
                                                                    (MIR_DATA/level)     up_req/up_gnt/up_data
                                                                              │                  ▼
                                                                              │      ┌──────────────────────────────┐
                                                                              │      │ u_mir_buf = mir_uram_fifo    │
                                                                              │      │ URAM288 4096×64 = 32 KB 载荷 │
                                                                              │      │ + 4 字弹性堆 + 3 级读流水     │
                                                                              │      └───────┬──────────────┬───────┘
                                                                              │        dn_req│        dn_gnt│/dn_data(同拍)
                                                                              │      ┌───────▼──────────────▼───────┐
                                                                              │      │ u_mir_axis = axis_c2h_stream │
                                                                              │      │ (2 grant = 16 B = 1 个 128 位拍)│
                                                                              │      └───────┬──────────────────────┘
                                                                              └──────────────│ s_axis_c2h_*
                                                                                    u_pcie_xdma → 宿主内存 → read()
```

**逐信号合同**（两侧都是"照抄旧合同"）：`clk/rst_n` = `pcie_axi_aclk`/`pcie_axi_aresetn`；`en` = `MIR_CTRL[3]`（0 ⇒ 不拉 `up_req` ⇒ 不取数 ⇒ 镜像 FIFO 保持）；`clr` = 镜像 `clr_pulse_rd`（clr 拍全清 + **不拉 req** + 清 valid 链）；`up_req` = 有空间才拉；`up_gnt/up_data` = 镜像同拍成交（1 个 64 位字 = 2 逻辑字 = 8 B）；`dn_req` = 成形器 `dma_req`；`dn_gnt/dn_data` = **同拍 FWFT**（`dn_gnt = dn_req && 弹性堆非空`）；`dbg_occ/dbg_oocc` 纯线束（wrapper 里显式空接）。

### 1.2 位置裁决 + 与基线的一处偏离（CDC 勘误）

**(a) 二选一取"接在 aux 口与成形器之间"**：既有件 0 改动；读延迟由缓冲自己吸收（§1.5），成形器看不见；反方案（替换成形器内部暂存）要动它 G1–G12 逐拍判过的同拍时序合同 + 全部 12 个突变臂作废。

**(b) ⛔ 偏离登记：本模块不需要 CDC。** 证据（现读）：`board/wrapper_p4.v:3795-3825`（u_mir）`.rd_clk(pcie_axi_aclk)` ⇒ **aux 口全在 rd 域**；跨域是 u_mir 内部 `u_fifo`（`fifo_async 64b×256`，dp→rd）**已完成的事**；u_mir_axis 例化 `.clk(pcie_axi_aclk)` ⇒ 两侧同钟 ⇒ **无灰码指针/无 2FF/无新 CDC 面**。若 TL 本意是"替换镜像内部那条 2 KB FIFO"（真 CDC 边界加 URAM），那是另一处接口（要动 `level` 9 位口径 + MIR_STATUS）——本刀没做，登记为备选。

### 1.3 容量 / 拍数账

| 量 | 值 |
|---|---|
| URAM288 本体 | 288 Kb = 36 KB（4096×72）；载荷用 64/72 位 ⇒ **32 KB** |
| 额外弹性 | 4 字（OQ）+ 在飞 ≤2 ⇒ 总在囊 ≈ **32.8 KB** |
| 吸收时长 @1.25 GB/s | **25.6 µs**（改前 ≈1.6 µs ⇒ ×16） |
| 填满拍数 | 4096 拍（16.4 µs @250 MHz）；源速率下 6554 拍 ≈ 26.2 µs |
| `clr` 丢弃面 | ≤32.8 KB（按定义丢弃、不计数；同成形器/镜像的边界登记） |

### 1.4 URAM 例化方式 = XPM_MEMORY（不是 ram_style），且结构性满足 ≥3 级流水

`xpm_memory_sdpram`：`MEMORY_PRIMITIVE("ultra")` · `READ_LATENCY_B=3` · `WRITE_MODE_B("read_first")` · `CLOCKING_MODE("common_clock")` · `ADDR_WIDTH_A/B=12` · `MEMORY_SIZE=64*4096`。
**为什么不用 `(* ram_style="ultra" *)`**：本仓既有实测 `retx_ram` 被工具拒（`Synth 8-6793`：`Available pipeline stages = 0, Minimum required pipeline stages = 3`）；且若**静默落回 BRAM** 是"安静失效"（BRAM 已用 348/480）。XPM 把 `READ_LATENCY_B=3` 写成合同 ⇒ 综合与 xsim 用同一份源；对 URAM SDP 有 DRC（`xpm_memory.sv:618-620`：URAM SDP 必须 ≥3）。
**实测读延迟契约（2026-10-13，xsim 行为模型）**：单发第 N 拍 `enb` ⇒ `doutb` 在 **N+3**；背靠背 3 发连续 3 拍按序；空闲 `doutb` **保持**旧值（⇒ 必须自建 valid 链）；读址 ≠ 写址（结构性）。
⚠️ 工具链坑：本机预编译 `-L xpm` 在个别情形 elaborate 失败（`value for parameter 'rstb_val' is not constant`）⇒ 门里显式 `xvlog -sv -work xpm <xpm_memory.sv>` 且 `-L xpm`（§5.4）。

### 1.5 读延迟 ↔ 下游握手的匹配论证

```
写 wp ─► URAM(4096×64) ─enb=issue─► [3 级读流水] ─► 弹性寄存器堆 OQ=4 (FWFT 头字) ─► dn_gnt/dn_data
          ▲ 地址 = rp              ▲ v_sr <= {v_sr[1:0], issue}（有效位与 XPM 同拍走）
          └ up_gnt 写入
账：occ = wp − rp（URAM 待发起）· inflight = popcount(v_sr)（在飞）· o_occ（弹性堆）
    inv = o_occ + inflight = "取走未弹走"总数
发起门：issue = (occ != 0) && ((inv − pop) < CAP) && !clr        （CAP = OQ = 4）
```

**三条不变式**：①（写侧不丢）`up_req = rst_n && en && !clr && !ufull` [⛔ FIX 轮订正 (验证 A-K1 §10): 原写
`up_req = en && !clr && occ<4096` = **F2 修复前的旧公式**（缺 `rst_n`；且 `occ<4096` ≡ `!ufull`）—— 现版 RTL
见 `rtl/mir_uram_fifo.v:169`]，满时不拉 ⇒ 上游不会给字 ⇒ 不覆盖未读字；②（到达安全）到达拍必有 `inflight ≥ 1` ⇒ `o_occ ≤ CAP−1 < OQ` ⇒ 弹性堆永不溢出（删掉上门 = 静默丢字，正是 `mut_issue_free` 打到的点：FATAL ×3444 + 16 条判据红）；③（存储回收点 = 读发起）`occ==0` 时无 issue、`occ==4096` 时无写 ⇒ 读写址**结构性不相撞**（`read_first` 安全的前提）；在囊 = occ(≤4096) + inv(≤CAP) **≤ 4100 字 = 32800 B**（在飞/弹性堆不占 URAM 地址；⛔ FIX 轮订正: 原写"4096 + inv(≤4)"——同一件事的另一种写法，本句与其后两处 `4099` 统一按 **4100 字** 口径）。

**匹配逐项**：首字 4 拍延迟 → 成形器本就容忍 `_req/_gnt` 任意间隔（只要求 gnt 那拍数据有效），实测 **4 拍**；稳态 1 字/拍 → `inv − pop = 3 < CAP` ⇒ 每拍可再 issue ⇒ 3 拍后准时补上，实测 **300/300**；下游长停 → 弹性堆 4 字 + URAM 4096 字，`inv` 顶到 4 就停发（不覆盖）；释放 → 先吐弹性堆/在飞，URAM 继续 1 字/拍补（G2f 全排空一个不少）。

### 1.6 `clr` / `en` / 复位

`clr`（窗口边界 = 丢弃，与成形器 D4 同口径）：指针/valid 链/弹性堆全清 + **不拉 `up_req`**（⇒ 上游也不成交 ⇒ "clr 拍不取数"结构性；⚠️ F7③ 订正：本句只覆盖 **up 侧**，dn 侧同轮已补门 `pop &&= !clr` ⇒ clr 拍 `dn_gnt` 强制 0，见 FIX_REPORT F3）；在飞 ≤3 字靠清 valid 链丢弃（`ram_dout` 上有旧值但不算到达）⇒ 不会有"上一窗口尾巴漏进新窗口"（板级 D4 抓到的形态）。
`en`：只门"是否取数"；`en=0 ⇒ up_req=0` ⇒ 镜像 FIFO 保持 ⇒ `MIR_STATUS/MIR_DATA` 读侧语义不变；`en=1 ∧ cap_en=0` 照常取数（与成形器 `dma_req` 门同款，正是"非 clr 停流排空"所需）。
复位 = `pcie_axi_aresetn`（同 u_mir_axis）；⚠️ u_mir 的 rd 侧用 `reset_n`（既存同钟不同复位域边界，本刀不加宽）；URAM 本体不复位（有效性由 valid/账保证，空态旧值永不弹给下游）。

### 1.7 丢字节语义保持（对 TL 合同逐条）

① 上游 aux 合同不变（2 grant = 16 B = 1 拍）——缓冲对成形器完全扮演镜像（成形器一行未改；门 G1/G2 逐字对账）。
② `MIR_DMA_CNT` 口径不变——计数器留在成形器（0 改动）；**登记**：它数的是"从本缓冲取走"，与"从镜像取走"之差 = 缓冲占用（**≤4100 字 = 32800 B**；⛔ FIX 轮订正 (验证 A-K1): 原写"≤4099 字 = 32.8 KB" = 低估 1 字 —— 真上界 = `DEPTH(4096)+CAP(4)`），**静默/排空终态下相等**。
③ 不新增丢字节计数器——满 ⇒ 不拉 req；模块内无任何 drop 计数器（唯二观测口空接）。
④ 读侧语义不动——不碰镜像 FIFO/stash/level/主机弹出；`en=0` 不取数（门 G6a）。
⑤ 两条恒等式——见 §3。

## §2 RTL 实施

**改动件**：`rtl/mir_uram_fifo.v`（新，245 行，sha256 `22ca56949dae44ec…`）· `board/wrapper_p4.v`（u_mir 3 根 aux 接线改指 + 3 根新线 + `u_mir_buf` 例化；⛔ 禁碰区 `:1319-1322` 一字未动）· `sim/p9_uram/{tb_mir_uram_fifo.v(337), run_tb_mir_uram_fifo.bat(61, ASCII+CRLF), mut_uram.py(81)}` · `sim/p6e_pcie/run_tb_p6e_pcie{,_counters,_mut,_mut2}.bat` 各 +4/−1。
⚠️ 并行修改登记：本轮期间**另一会话**对 `board/wrapper_p4.v` 做了**纯注释**编辑（引用改 `agent_docs/…`；mtime 01:48:58）；已核"diff 的非注释行全是本刀的 4 处"，并在当前内容（sha256 `598185021bcfa742`）上重跑 `p6e_counters` = PASS_ALL（跑动期间该文件哈希未变）。

**"默认路径"**：本刀**没有**新宏 —— 缓冲只存在于 `APP_MODE ∧ PCIE_OBS ∧ DP_156MHZ` 真支块内；两个 ¬ 支（tie-off 常量表）**逐字未动**（结构性：¬ 支里没有这个实例）。参数（`AW=12/LAT=3/OQ=4`）wrapper 显式传；`LAT≠3` / `OQ∉[2,7]` / `AW<4` 在仿真里**响亮地死**（`ifndef SYNTHESIS` 自检，同 `fifo_async` 手法）。

**代码要点**：单一 always 块驱动全部状态（rst/clr 同款整块清零）；声明全前置（坑 24）；组合面 = 3 短加法器 + 1 比较 + 4:1 的 64 位 FWFT mux，无乘法/宽移位/大 case 表；`ifndef SYNTHESIS` 三条结构性守卫（到达拍弹性堆满 / 满态还写 / 上游违契）。

## §3 两条工具恒等式（`--stream` 判据）在本刀下

- **式 A（`taken − pc ∈ [0,32]`）：逐字不受影响** —— 两端都在计数点下游，缓冲占用不出现。
- **式 B（`K − taken − ΔW70 ∈ [0,24]`）：终态下逐字成立；中途评估差额 = 缓冲占用 O。** 推导：`K − taken(mirror) − ΔW70 = 镜像残余`（原形）；工具用的 `taken(shaper)` 在缓冲下游 ⇒ `taken(mirror) − taken(shaper) = O` ⇒ 差额 = 镜像残余 + O；**源停 + 排空到 early-stop 的终态下 O = 0**。
  ⚠️ 登记：中途（源仍在流）式 B 的差额可到 **O ≤ 4100 字 = 32800 B**（⛔ FIX 轮订正 (验证 A-K1): 原写"O ≤ 4099 字 = 32.8 KB"，按真上界改 4100）⇒ `--resid-max-mirror` 默认 24 只对终态成立。
  ⛔ **FIX 轮口径精化 (验证 A-K2 §2)**: 中途差额的**严格上界 = ≤ 34872 B** —— 一般式 = `镜像残余 + O`，其中镜像残余在**镜像未静默**时还要含其 FIFO（`app_rx_mirror.v:359` 的 `fifo_async 64b×256 = 2048 B`），即 `O(≤32800) + FIFO(≤2048) + acc/stg(≤24) = 34872 B`（**算术非实测**）。
  ⭐ 与工具的实际关系（现状口径）：默认 24 只在"停源 + 排空到 early-stop"的终态成立 —— **中途/停排空评估跑必现假红**（`closed_b=false, rc=1`），且错误信息会指向"镜像残余越界/K 口径不对"（误导归因；`premise_level0` 只管镜像 FIFO/stash，**不排除 `O > 0`**）。
  建议（**工具侧本轮只落"文字面"、默认值不动**）：① 保持"停源 → 排空到 early-stop"收尾协议（现状已如此）；② 非静默跑法下**显式**放宽式 B 上界并注明（如 `--resid-max-mirror 34872`），工具 `--help`/注释已按此加限定（见 FIX 轮）；③ 或（更强）给缓冲占用加只读观测口 —— 会改快照几何，不在本刀；④ 新选项 `--resid-max-mirror-mid`（中途默认上界）**本轮只登记、不实现**（改默认值会动判据语义）。
- `en=0` 时本模块不取数 ⇒ `MIR_DMA_CNT` 不会虚增。

## §4 新增门读数（原始件 = `gate_stdout/{arm_*.txt, xsim_*.log}`）

**real = PASS_ALL（43 判据 / 0 FAIL）**，关键读数：

```
[DBG] G1: taken=199 popped=194 seq_err=0 over_err=0
[DBG] G2: require-drop after 4096 cyc; occ=4096 inv=4 taken=4099     ← ⭐ 白盒钉容量: occ 恰 = 4096
[DBG] G2-end: taken=4107 popped=4108 occ=0 inv=0                     ← ⭐ 停源全排空: 账闭合 (p0=1)
[DBG] G4: taken=2671 popped=1949 seq_err=0 over_err=0                ← 3000 拍双侧独立 LFSR 空档, 零错
[DBG] G5: eq_drop=774 (clr 丢弃的悬空字)                              ← clr 确实按定义丢掉了悬空字
[DBG] G7: popped=300 / 300 cyc                                       ← ⭐ 稳态 1 字/拍 (理论上限 300)
[DBG] G8: taken=16130 popped=16131 seq_err=0 over_err=0              ← 24000 拍, 多次绕回, 零错
URAM_FIFO_GATE: PASS_ALL
```

判据分组：G0 复位 / G1 基本流 / **G2 恰好满（`occ==4096`）+ 长停收 + 释放** / **G3 恰空 + 首字延迟 4 拍** / G4 双侧独立随机空档 / **G5/G5b `clr` ⇒ 丢弃** / G6 `en=0` 不取数 / G7 吞吐 / G8 长流跨绕回 / **G9 结构性监视 5 条全 0**（`arr_full`/`wr_full`/`pop_empty`/`clr_take`/终态账闭合）。判据名已改**纯 ASCII**（xsim 会把经 `[255:0]` 端口传的非 ASCII 逐字节损坏）。

**突变臂（7，每臂恰 1 行恰 1 处命中）**：

| 臂 | 打的性质 | 结果 |
|---|---|---|
| `mut_full_off` | 满也取数（覆盖未读字） | ✅ 红：12 判据 + **RTL FATAL `URAM write while FULL`** |
| `mut_full_e1` | 容量少 1 | ✅ 红：**只 `G2a CAPACITY-PIN: occ==4095(期望 4096)` 1 条**（白盒钉容量的牙） |
| `mut_issue_free` | 到达覆盖弹性堆 | ✅ 红：16 判据 + **FATAL `arrival into FULL elastic FIFO` ×3444** |
| `mut_val1` | 到达早一拍 | ✅ 红：逐字对账（seq_err 195→6671） |
| `mut_clr_off` | clr 不丢弃 | ✅ 红：逐字对账 + `G4c` 幻影弹 |
| `mut_clr_take` | clr 拍取数 | ✅ 红：**`G9d clr_take=5`** + 账 |
| `mut_dnreq` | 无数据也成交 | ✅ 红：`G1c`/`G3b`/`G3d` + 逐字对账 |

## §5 既有门回归

**5.1 先核"哪些门编到被改文件"**：常驻 P4 矩阵唯一的 wrapper 门 = `p5_wrapper`（**APP_MODE-only**）⇒ 本刀全在 `ifdef DP_156MHZ` 内 ⇒ 对本刀**空/弱证据**（矩阵本轮未跑；新文件是否影响其 FROZEN 指纹清单**未核**）。真编到真支的门 = `sim/p6e_pcie/run_tb_p6e_pcie*.bat`（`-d …DP_156MHZ` + `dir /b /s %ROOT%\rtl\*.v` 自动收新件），TB = 真 wrapper 全链。

**5.2 逐门读数**：`p6e_counters`（真支）**PASS_ALL**（补丁前 = 硬失败 `Module <xpm_memory_sdpram> not found`）· `axis_shaper_real` **PASS_ALL**（被测件未改）· `mir_unit_real` **PASS_ALL**（被测件未改）· `p5_wrapper` **EXIT 0** · `aliasgate` **ALIASGATE OK** · ⚠️ `p6e_fullchain` **1 条红**（下条）。

**5.3 ⚠️ `P9-B-3d` 那条红的归因（判据前提；已诊断坐实）**：判据 = "下游停收 + 灌 **700** 拍 `mir_word`（每拍 4 B ≈ 2.8 KB）⇒ 期望 `ΔW70 > 0`"（它是 W70 计数路径"还活着"的见证，注释里写明当时推理"下游弹性只有几十字节"）。本刀把下游弹性从 ≈2 KB 加到 ≈34 KB ⇒ **2.8 KB 不再够填满** ⇒ 无丢字 ⇒ 见证失效（**物理/口径都没变，是激励的"够不够满"前提变了**；同门其余全绿，`delivered words=720`/`keep_bad=0`）。
**诊断（不改门不改判据）**：TB 复制到 `diag_p9b3d/`，只把注入量 700 → **20000**（=80 KB ≈ 2.4× 新弹性）⇒ 复跑同一门：`W70: 4d494e79 -> 4d49fea1` + `[PASS] P9-B-3d` + **`PASS_ALL  tb_p6e_pcie_wrapper: 全链门全过`**（原件 `diag_p9b3d/DIAG_stdout.txt`；副本与原件 diff = **1 行代码 (注入量) + 4 行注释**，`722,726c722`、899 vs 895 行 —— ⚠️ F7② 订正：原写"3 行注释"）。⇒ **W70 计数路径活着**；⛔ 改该判据（注入量或改成"`ΔW70 ≥ 注入 − 弹性上界`"）属判据改动，**归裁定者**。

**5.4 ⛔ 必须登记的副作用：XPM 例化 ⇒ 编到真支的 bat 需要 xpm 库。** 现象（实测）：未打补丁 = 硬失败 `VRFC 10-2063 Module <xpm_memory_sdpram> not found`（响亮）；且本机**预编译** `-L xpm` 在个别情形 elaborate 失败（`VRFC 10-3812 rstb_val is not constant`）。补丁（已做，4 个件各 +4/−1）：主 xvlog 前加 `call %XV%\xvlog.bat -sv -work xpm "%XV%\..\data\ip\xpm\xpm_memory\hdl\xpm_memory.sv" > xvlog_xpm.log 2>&1 || (… exit /b 1)`，xelab 加 `-L xpm` ⇒ 之后 `p6e_counters` PASS_ALL。**未打补丁的其余含 `DP_156MHZ` 的历史 bat**（`sim/p5wu_p1p2*`、`sim/p7b_*_regress/extra*`、`_proj_10g/notes/...` 下的旧件）若被重跑需照抄两行。**Vivado 构建脚本不需要改**（XPM 工具自带）。

## §6 时序与资源（⛔ 未评）

无综合/实现报告 ⇒ 时序、资源、URAM 推断**全部未测**；不写"时序没问题"。新锥清单（构建后定向查）：① `wp/rp → occ → ufull → up_req`；② `o_occ/v_sr → inv → issue → rp/URAM enb`（发起门反馈环）；③ `o_mem[4] → 4:1 mux → dn_data`；④ `up_data → URAM 写口`。基线 0x23 = `WNS +0.098`、DP 域为全局最差（余量 ~1.5%）；本刀全在 pcie 域，且**替下了**原 aux 口的组合路径（`u_mir_axis.dma_req → u_mir` 已解耦）⇒ 净效应要实测。资源预期：**URAM 0→1**；FF ≈ +274 量级；**BRAM 不应增加**（若 BRAM 上升而 URAM 没动 ⇒ xpm 落错 primitive ⇒ 回来查 `MEMORY_PRIMITIVE`）。构建后必查：0 条 `Synth 8-6793` + `URAM288 = 1`。

## §7 未竟项（⛔ 不许当已答）

1. **URAM 推断未测**（无综合）；XPM 行为模型 ↔ 综合后网表的读延迟一致性未做门后仿真。
2. **时序未评**；`u_mir_buf` 是 pcie 域新锥（清单见 §6）。
3. **`P9-B-3d` 判据改动权归裁定者**（本件未改该 TB，只给归因 + 诊断）。
4. **其余含 `DP_156MHZ` 的历史 bat 未加 xpm 补丁**（配方见 §5.4）。
5. **常驻矩阵对本刀 = 空/弱证据，且其 FROZEN 指纹是否收进新 `rtl/*.v` 未核**。
6. **中途评估式 B 的账目偏差 = O（≤32800 B；加镜像 FIFO/acc/stg 的精化上界 ≤34872 B）已登记未量化**；只在终态排空下逐字成立。（⛔ FIX 轮订正 (A-K1/A-K2): 原写"≤32.8 KB"按 4100 字口径改，并补精化上界。）
7. **缓冲水位无观测口**（`dbg_occ/dbg_oocc` 空接；接快照会改窗口几何 71 字/0x14C）——已登记的仪器缺口。
8. 镜像读侧与缓冲的"混用"语义与改前同类（`en=1` 时 level 恒低；"两条读出口不许混用"是既存登记）。
9. 备选（未做）：`AW=13`⇒2 URAM（64 KB）；替换镜像内部 2 KB `fifo_async`（真 CDC 边界加 URAM，要动 `level` 9 位口径与 MIR_STATUS）；缓冲占用进快照。

## §8 复跑命令

```bash
cd /d/repo/XCKU5PMini/udp_hls_10g
cmd //c 'sim\p9_uram\run_tb_mir_uram_fifo.bat real'          # PASS_ALL (FIX 轮后 = 66 判据)
cmd //c 'sim\p9_uram\run_tb_mir_uram_fifo.bat mut_full_off'  # 其余 14 臂 (权威清单 = mut_uram.py 的 MUTS 全表):
#   mut_full_e1/mut_issue_free/mut_val1/mut_clr_off/mut_clr_take/mut_dnreq/mut_rstn_off/mut_en_off/
#   mut_dnclr/mut_wp_nmc/mut_guard_off + FIX 轮新增 mut_clrv/mut_omem/mut_oocc (+ guard_rogue 臂)
cmd //c 'sim\p6e_pcie\run_tb_p6e_pcie_counters.bat'          # PASS_ALL (已带 xpm 补丁)
cmd //c 'sim\p6e_pcie\run_tb_p6e_pcie.bat'                   # 预期 1 条红 (P9-B-3d 激励前提, §5.3)
cmd //c 'sim\p9_axis_stream\run_tb_axis_c2h_stream.bat real' # PASS_ALL
cmd //c 'sim\p7b_mir\run_tb_app_rx_mirror.bat real'          # PASS_ALL
cmd //c '_proj_10g\notes\p9_uram_20261013\diag_p9b3d\run_diag.bat'   # 预期 PASS_ALL (容量感知激励)
```

*本件 = 设计块 + 实施 + 门读数；不下 PASS/FAIL 裁定（构建/板级读数归 TL 那轮）；未测写"未测"，未观测写"未观测到"。*
