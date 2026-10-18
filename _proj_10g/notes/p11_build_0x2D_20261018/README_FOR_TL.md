# P11 双 SFP+ · 重建 0x2D 构建轮 —— 交付报告（README_FOR_TL）

- 日期：2026-10-18
- 仓库根：`D:\repo\XCKU5PMini\udp_hls_10g`；开工 HEAD = **`5a64a395`**（与派单一致）
- 权威输入：`_proj_10g/notes/p11_p2a_design_20261018/DESIGN_v2r1.md`（含附录 E）·
  `_proj_10g/notes/p11_fix_f21_20261018/FIX_REPORT.md` ·
  `_proj_10g/notes/p11_reviewfix_20261018/FIX_REPORT.md` ·
  `_proj_10g/notes/p11_build_0x2C_20261018/`（0x2C 构建件）
- 纪律：只走 `board/run_build_p7b_ku5p.bat`（唯一入口）；未烧板、未碰 QSPI、未写 git；
  未改 `D:\repo\perfv`；构建期间未写任何源文件；xsim 与 Vivado 未并行。
- 本报告**不下 PASS/FAIL 裁定**；「未观测到」≠「不存在」；纸面/派生值已标注。

## 0. 一句话（分层口径）

1. **HLS 网表 = 复用**：现树 `HLS_NET_HASH = 452a1122…4428`、`HLS_SRC_HASH = 556ed00c…5218`，
   与 0x2C 构建件逐字相同 ⇒ **未重跑 csynth**（构建日志自己也打印了同两值）。
2. **构建在 F-21 布后（实为布后综合）结构门失败并停止**：
   `P7B_SNAP_TOP5_FANOUT_BAD hold_b=0 snap_din=0` → `BUILD_EXIT=1` → **实现从未启动**
   （`impl_1` 文件数 = 0），**无时序/资源/DRC/route/位流读数**。
3. **门失败经只读核查判为「门判据的层次网名别名假红」**（事实诊断，不是裁定）：
   同一 synth checkpoint 上，`tx_p0_frames_r_reg[0]/Q` 的**叶子负载**明确包含
   `u_snap_p7bdp/hold_b_reg[1248]/D`；门匹配到的是**非叶子层次网钉**
   `u_snap_p7bdp/tx_p0_frames_r_reg[0]`（`IS_LEAF=0`），其名字不含 `hold_b_reg` ⇒ 名字匹配失败。
   五个槽本身的读数全为正：**slot 39..43 各 32 个 `hold_b_reg` 寄存器**、`SLOTS_OK = 5`。
4. **未执行任何 backstop 档、未重跑**：backstop 四档绑定「WNS<0 / 三类失败端点非 0」，
   本轮实现未启动、这些量不存在；且删 W83..W87 不会让本门变绿（门检查的正是槽 39..43
   与 `tx_p0_frames_r_reg[0]`），还会偏离已评审的设计。见 §5。

## 1. 阶段 0（前置核对）

| 项 | 读数 | 结论 |
|---|---|---|
| `git status --porcelain` | **已跟踪改动 0 项**（开工时）；未跟踪 **364** 项 | ⚠️ 与派单「工作树应干净（忽略项除外）」**不完全相符**：这些是历史未跟踪残留（`.claude/`、`_tmp_*.py`、notes 归档、sim 临时件等）；**无任何被跟踪文件改动**。构建前核过一次，构建后见 §6 |
| `tasklist` vivado/xsim/xelab/xvlog | 构建前全无；构建后全无 | ✅ 无并行 |
| `BUILD_ID_V` | `32'h0000002D`（`board/wrapper_p4.v:5271`） | ✅ |
| `SNAP_NW_P6E` / `SNAP_P7BDP_NW` | `88`（`:3888`）/ `44`（`:3909`） | ✅ |
| wrapper `.TO_CYCLES` | **`4096`**（`:1188`） | ✅ 与派单一致（⚠️ 同行注释仍写「下一构建 = 16'hFFFF」，见 §7-1） |
| tcl 9 宏 | `APP_MODE DEV_USP PCIE_OBS DP_156MHZ P7B_10G UDP_TX_OVL TCP_TX_OVL SFP2_MODE_A DUAL_SFP_A`（全 =1，`board/build_p7b_ku5p.tcl:330`） | ✅ |
| HLS 网表 | **`HLS_NET_HASH = 452a11226a3ce4b2923ce3b026c39562d655065eb639581e9d2da879d0e64428`（n=175）**，与 0x2C 相同 ⇒ **复用，未跑 csynth**；源 `HLS_SRC_HASH = 556ed00c…5218`（n=15）亦相同 | ✅ 复用路径（细节 + 算法复现见 `build/HLS_REUSE_CHECK.txt`） |
| F-21 布后门 | tcl 有 `sec "P7B_SNAP_TOP5_CDC"`（`board/build_p7b_ku5p.tcl:401` 起）；bat 有 `/B` 锚定的 `P7B_SNAP_TOP5_CDC_MISSING` / `P7B_SNAP_TOP5_FANOUT_BAD` 硬门（`board/run_build_p7b_ku5p.bat:79`，读数行 `:85`） | ✅ 就位（⚠️ 实际执行点是 `open_run synth_1` = **综合网表**，非布局后，见 §7-2） |

## 2. 构建命令与退出

```
cmd //c 'board\run_build_p7b_ku5p.bat'
```

- 控制台原件 = `build/BUILD_CONSOLE.txt`；Vivado 全量 stdout = `board/p7b_ku5p_stdout.txt`
  （已复制到 `build/board_rpt/`）。
- **`BUILD_EXIT=1`**（Vivado rc=1 —— tcl 在 F-21 门 `exit 1`）。
- bat 终判 = **`BUILD-GATE-FAIL`**；触发行 = `P7B-SNAP-TOP5-CDC-FAIL`
  （`P7B_SNAP_TOP5_FANOUT_BAD hold_b=0 snap_din=0`）。
- ⚠️ 控制台还出现一行 `'oken' 不是内部或外部命令`：源自 `run_build_p7b_ku5p.bat:76` 的中文 REM 行
  （含 `**以 token 开头**`）在 cmd OEM(GBK) 代码页被拆包执行。**它不设置 TRIP**（门当时已红），
  属已知「bat 中文注释拆包」族（review-fix 报告 §1-5④ 同族），仅登记，不改源。

## 3. 构建读数（本次实际拿到的全部）

> 构建在 **综合后、实现前** 停止 ⇒ 本表没有 WNS/WHS/三类端点/DRC/route/clock interaction/
> 资源 placed/位流。**下列「未测」不是 0，也不是通过。**

| 键 | 值 |
|---|---|
| `HLS_SRC_HASH` | `556ed00c4ad6f26f52dee9290f0f813308514189c2505c116d2a38334b945218`（n=15） |
| `HLS_NET_HASH` | `452a11226a3ce4b2923ce3b026c39562d655065eb639581e9d2da879d0e64428`（n=175） |
| `P7B_CONVERGED_AT_ROUND` | 2 |
| `P7B_IS_LOCKED_POSTGEN` | 0 |
| `P7B_VERILOG_DEFINE` | 9 宏（含 `DUAL_SFP_A=1`、`SFP2_MODE_A=1`） |
| `P7B_NFILES` | 445 |
| `P7B_BLACKBOX_LOG_HITS` | **0** |
| `P7B_MODULE_RESOLVED` | `rx_merge2=1 tx_demux2=1 maccnt_sync=1` |
| `P7B_BLACKBOX_COUNT` | **0** |
| `P7B_VERDICT` | **未打印**（tcl 在 F-21 门 `exit 1`；bat 端报 `P7B-VERDICT-OK-MISSING`） |
| 硬门 8 键（synth_1/runme.log） | `12-4739=0` · `Synth 8-11241=0` · `undeclared symbol=0` · `VRFC 10-3091…=0` · `VRFC 10-2989=0` · `implicitly declared=0` · `black box=0` · `8-3491=0` |
| synth 资源（估计；**非 placed**） | LUT **67,493** · FF **56,499** · BRAM **310** · URAM **1** · DSP **4** · GTYE4 0（synth 报告不计 GT） |
| `P7B_WNS` / `P7B_WHS` / `P7B_WPWS` | **未测（实现未启动）** |
| 三类失败端点 | **未测** |
| DRC / route / clock interaction | **未测**（磁盘上 `board/p7b_ku5p_{timing,util,drc,clkinteract}.rpt` 是 **0x2C 的 12:50 旧件**；已按 `STALE_0x2C_*` 归档，见 §4） |
| 位流 | **无**（`impl_1/wrapper_p4.bit` 不存在；sha256/字节数/SW_CRC = 未测） |
| 定向 STA（`-from` 系列） | **未跑**（无 routed dcp；脚本已备：`gates/sta_directed_0x2D.tcl`，待有成功实现后执行） |

### 3.1 F-21 门读数（本轮的判别核心）

```
P7B_SNAP_TOP5_SLOT slot=39 bits=1248..1279 cells=32
P7B_SNAP_TOP5_SLOT slot=40 bits=1280..1311 cells=32
P7B_SNAP_TOP5_SLOT slot=41 bits=1312..1343 cells=32
P7B_SNAP_TOP5_SLOT slot=42 bits=1344..1375 cells=32
P7B_SNAP_TOP5_SLOT slot=43 bits=1376..1407 cells=32
P7B_SNAP_TOP5_SLOTS_OK = 5
P7B_SNAP_TOP5_FANOUT tx_p0_frames_r_reg[0]/Q loads=2 hold_b=0 snap_din=0
P7B_SNAP_TOP5_FANOUT_BAD hold_b=0 snap_din=0
```

- **正读数**：槽 39..43 每槽 **32** 个 `u_snap_p7bdp/hold_b_reg`；`SLOTS_OK=5`。
  ⇒ 五个新字（W83..W87）在综合网表里**确有** p7bdp CDC 寄存器（0x2C 时这些槽为 0）。
- **红读数**：`tx_p0_frames_r_reg[0]/Q` 的即时负载里 `hold_b=0`、`snap_din=0`。

## 4. 红读数的只读诊断（不裁定，只列事实）

在同一份 **synth_1 checkpoint**（`build/wrapper_p4_synth_0x2D.dcp`，sha256
`d1ccc7999cf27ae450434e788e5852549faec723614a81cc847e43eb5602f8ab`）上做四次只读查询
（原件：`gates/SNAP_TOP5_DIAG_0x2D.txt` / `SNAP_TOP5_DIAG2_0x2D.txt` / `SNAP_TOP5_DIAG3_0x2D.txt` /
`SNAP_TOP5_DIAG4_0x2D.txt`）：

1. `tx_p0_frames_r_reg[0]/Q` 的 net = `tx_p0_frames_r_reg[0]`，其 **IN 引脚（默认口径）** =
   `tx_p0_frames_r[0]_i_3/I0`（叶子）与 **`u_snap_p7bdp/tx_p0_frames_r_reg[0]`（`IS_LEAF=0`，层次网钉）**。
2. 同一 net 的 **`-leaf` 引脚列表** = `{tx_p0_frames_r[0]_i_3/I0, tx_p0_frames_r_reg[0]/Q,
   u_snap_p7bdp/hold_b_reg[1248]/D}`。
3. `u_snap_p7bdp/hold_b_reg[1248]` 是 FDCE；其 **D 引脚存在**，D 侧内部网名 =
   `u_snap_p7bdp/tx_p0_frames_r_reg[0]`（跨层次边界后的同一条网的内部名）；Q →
   `u_snap_p7bdp/dout_a_reg[1248]/D`（CDC 捕获级）。
4. 全设计 **无** `u_snap_p7bdp/tx_p0_frames_r_reg[0]` 这个 cell
   （`get_cells -hier` 0 命中）⇒ 它是**网/网钉名**，不是复制寄存器。

**事实归纳**：门的扇出检查用 `get_pins -of_objects <net> -filter DIRECTION==IN`（非 `-leaf`）
枚举负载，命中的第一个 IN 对象是**层次边界网钉**，其名字不含 `hold_b_reg`；真正的叶子负载
`u_snap_p7bdp/hold_b_reg[1248]/D` 在 `-leaf` 列表里存在。⇒ 门红是**名字别名导致的假红**
（与 F-21 报告 §2.2 预先登记的「综合别名/复制形态」同类；实际别名形态 = 层次网钉，不是 `_rep`）。
`snap_din=0` 这一半仍成立（无直连 PCIe 快照阵列）。

补充（`gates/SNAP_TOP5_DIAG4_0x2D.txt`）：五个槽的 **bit0 D 网**分别是
`u_snap_p7bdp/tx_p0_frames_r_reg[0]`（槽 39，与上面同一条网）· `u_snap_p7bdp/O42[0]`（槽 40）·
`u_snap_p7bdp/w85_dp[0]`（槽 41，W85 真源）· `u_snap_p7bdp/hold_b_reg[1344]_0`（槽 42）·
`u_snap_p7bdp/hold_b_reg[1376]_0`（槽 43）—— 五个 D 网存在且互不相同（非常量、非同一网）。
⚠️ 该查询的 `driver=` 回溯在层次边界上未解析出 OUT 引脚（与 §4 同一别名机制），故 diag4 只记 D 网名。

⚠️ **诊断覆盖面**：bit 1248 已逐位证明到叶子 D 引脚；其余位由「每槽 32 个寄存器」+ diag4 的五槽
bit0 D 网 + 源码侧静态门（上一轮 `SNAP_TOP5_STATIC_PASS`）覆盖，**不是**本查询逐位证明。
且这是**综合网表**证据，**不是**布局/布线后证据（见 §7-2）。

## 5. FAIL 处置：backstop 未执行（理由）

派单的预登记 backstop 四档（删 W86/W87 → 删 W85 → 删 W83/W84 → abort 0x2B）绑定的是
**时序失败**（「若 WNS 为负或三类端点非 0」）。本轮：

- 实现从未启动 ⇒ WNS/WHS/端点类别**不存在**，backstop 的触发条件无法成立；
- 删 W83..W87 不会让本门变绿：门检查的正是槽 39..43 与 `tx_p0_frames_r_reg[0]`；
  删字反而偏离已评审设计（且 F-21 的设计修法被本轮正读数支持）；
- 未做任何「重跑到过」：**本轮只调用了一次构建**。

⇒ **停在这里，等 TL 处置**。可选方向（供裁定，不是建议裁定）：

1. **改门**（最小、与 F-21 报告 §2.2 的既定口径一致）：用 `get_pins -leaf -of_objects $net`
   枚举负载，或直接检查 `u_snap_p7bdp/hold_b_reg[1248]/D` 的驱动网是否就是
   `tx_p0_frames_r_reg[0]/Q` 的网；**不放宽判据**。改后重跑 = 新输入（tcl 变更需评审/授权）。
   参考片段（**未应用**，仅供评审；替换 `f_loads` 的枚举口径）：

   ```tcl
   set f_loads {}
   foreach n $f_nets {
       foreach l [get_pins -quiet -leaf -of_objects $n] {
           if {[get_property DIRECTION $l] eq "IN"} { lappend f_loads $l }
       }
   }
   ```

   该口径在本轮 synth dcp 上会给出 `loads=3`（含驱动 Q），其中
   `u_snap_p7bdp/hold_b_reg[1248]/D` 命中 `*hold_b_reg*` ⇒ `hold_b>=1`、`snap_din=0`。
2. 若要「真正的布局后/布线后」结构证据：把同一检查移到 `open_run impl_1` 之后（routed dcp）。
3. 若裁定门实现不可改：退回 0x2B（保留 P1），或按新口径重新预登记 backstop。

## 6. 归档与工作树状态

- **#54 构建前自动归档：成功** —— `ARCHIVE_SHA256_OK` + `ARCHIVE_DONE 20261018_160226 files=19`，
  目录 `_proj_10g/notes/p7b_build_archive/20261018_160226/`；其中 `wrapper_p4.bit` sha256 =
  **`e92f588b58452e58b86bb96df11091eec1f2c72ae346d3740f36c3e6f2b8d6be`** ⇒ 归档的确实是**前代 0x2C**位流。
- 本代产物：**无位流**。synth checkpoint 已另存 `build/wrapper_p4_synth_0x2D.dcp`（72,717,259 B，
  sha256 `d1ccc799…f8ab`）——若 TL 决定只改门，可在这份 dcp 上先行复核，不必重建综合。
- `board_rpt/` = 7 件：`p7b_ku5p_stdout.txt`（本次）· `p7b_ku5p_xdma_cfg_post_gen.txt`（本次）·
  `wrapper_p4_utilization_synth.rpt`（本次）· `runme_synth_1.log`（本次）+
  **4 件 `STALE_0x2C_*`**（0x2C 的 12:50 报告，**不得**读作 0x2D 读数）。
- 构建后 `git status --porcelain`：**被跟踪文件 1 项被改写 = `board/p7b_ku5p_stdout.txt`**
  （bat/Vivado 每次构建写新日志，设计行为；源 `board/*.v`、`board/*.tcl`、`board/*.bat`、`rtl/`、
  `hls/src/` 全部零改动）。未跟踪项 366（原 364 + 本轮 notes 新件）。
- 本报告未写入任何源码；未写 git。

## 7. 核到与描述/既有陈述不符的项（如实登记，未改）

1. **`.TO_CYCLES` 的注释与代码矛盾**：`board/wrapper_p4.v:1184-1185` 的注释写
   「⭐ 2026-10-18 用户批准: 下一构建 (0x2D) 阈值 = 16'hFFFF …」，但实际例化
   `.TO_CYCLES(4096)`（`:1188`）。**代码 = 4096，与派单/附录 E-2 一致**；注释是 F-21 轮遗留的
   陈旧句。另：`p11_fix_f21_20261018/FIX_REPORT.md` §1.1 A4 与 `p11_reviewfix_20261018/FIX_REPORT.md`
   §1-1/§4-1 都写「现读仍是 16'hFFFF」——**与 git 不符**（`a35f9a14` 与 HEAD 该行都是 4096；
   `git diff a35f9a14..HEAD` 里该行是上下文行）。本轮按 4096 构建。
2. **F-21「布后门」实际是「布后综合门」**：tcl 段在 `open_run synth_1` 之后、`launch_runs impl_1`
   之前执行（`board/build_p7b_ku5p.tcl:395-443`）。它能证明**综合网表**里寄存器未被优化掉，
   **不能**证明布局/布线后仍存在（本轮更因门红而未进入实现）。引用时请按「post-synth」写。
3. **bat 中文 REM 拆包**：见 §2（`'oken'` 噪声），已知族，未改源。
4. **工作树未跟踪项 364（构建前）**：见 §1；不是已跟踪改动。

## 8. 未测 / 不许当已答

- 0x2D 的**综合后 WNS/WHS/WPWS、三类失败端点、DRC、route、clock interaction、placed 资源**：未测（实现未启动）。
- **位流**：不存在（sha256/字节数/SW_CRC 均未测）。
- **定向 STA**（`f_lip_reg` / `ctrl_lip_reg` / `cam_rd_dip→csum` / `u_rx_merge` / 每口 arb /
  `hold_b_reg[1248..1407]` / `maccnt_sync` / `u_hls` / 全局 WNS 宿主）：未测（无 routed dcp）。
- **F-21 的布局后/布线后结构状态**：未测；本轮只有 post-synth 正读数（槽 39..43 各 32）+ 假红诊断。
- **板级相干性**（W83..W87）：未测；本轮未烧板。
- **「裸 CDC 是否真的读出过位混」**：0x2C 从未上板 ⇒ 未观测到 ≠ 不存在（沿用 F-21 口径）。

## 9. 证据索引（全部绝对路径前缀 `D:\repo\XCKU5PMini\udp_hls_10g\`）

| 文件 | 内容 |
|---|---|
| `_proj_10g/notes/p11_build_0x2D_20261018/build/BUILD_CONSOLE.txt` | bat 控制台（含 `BUILD_EXIT=1`、`P7B-SNAP-TOP5-CDC-FAIL`、ARCHIVE_*） |
| `_proj_10g/notes/p11_build_0x2D_20261018/build/READINGS_BID2D.txt` | 机读汇总（77 行；含 IMPL STATUS/STALE 标注） |
| `_proj_10g/notes/p11_build_0x2D_20261018/build/HLS_REUSE_CHECK.txt` | HLS 哈希复算算法 + 复用决定 + 方法自曝 |
| `_proj_10g/notes/p11_build_0x2D_20261018/build/wrapper_p4_synth_0x2D.dcp` | 本轮 synth checkpoint（供只改门后复核） |
| `_proj_10g/notes/p11_build_0x2D_20261018/build/board_rpt/` | 本次 4 件 + `STALE_0x2C_*` 4 件 |
| `_proj_10g/notes/p11_build_0x2D_20261018/gates/SNAP_TOP5_DIAG{,_CONSOLE}.txt` | 诊断 #1 及控制台 |
| `_proj_10g/notes/p11_build_0x2D_20261018/gates/SNAP_TOP5_DIAG2{,_CONSOLE}.txt` | 诊断 #2（D 引脚驱动链） |
| `_proj_10g/notes/p11_build_0x2D_20261018/gates/SNAP_TOP5_DIAG3{,_CONSOLE}.txt` | 诊断 #3（`-leaf` 举证） |
| `_proj_10g/notes/p11_build_0x2D_20261018/gates/SNAP_TOP5_DIAG4{,_CONSOLE}.txt` | 诊断 #4（五槽 bit0 D 网） |
| `_proj_10g/notes/p11_build_0x2D_20261018/gates/sta_directed_0x2D.tcl` | 定向 STA 脚本（**未运行**；待成功实现后执行） |
| `board/p7b_ku5p_stdout.txt` | Vivado 全量日志（本次；已被构建改写 = 唯一被跟踪改动） |
| `_proj_10g/notes/p7b_build_archive/20261018_160226/` | 构建前归档（0x2C 位流 `e92f588b…` + 报告 19 件） |

> 若本报告未能落盘（平台拒写），以最终回复原文为准；上述门/诊断日志均已归档在磁盘。
