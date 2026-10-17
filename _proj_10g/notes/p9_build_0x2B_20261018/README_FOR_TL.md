# 0x2B 构建轮（P11 / P1-甲：ch0 bring-up）—— 构建 + 矩阵 21 门 + 读侧 + 门（**不烧板**）

- 轮次性质：**构建轮**。输入 = 修复轮收口 `a3ac6db3`（含 `4ff38912`；工作树该三文件零改动已核）。
- 施工权威 = `_proj_10g/notes/p9_dual_sfp_p1_impl_20261018/DESIGN_v5.md`（v5.1）；修复报告 = `p9_dual_sfp_p1_fix_20261018/FIX_REPORT.md`。
- 唯一入口 = `board/run_build_p7b_ku5p.bat`（**未用 GUI / 未重编 `vivado_prj`**）。**未烧板、未碰 QSPI、未碰对端、未写 git**。
- 本轮独有串：`P1BUILD0x2B-*`；时间：构建 2026-10-18 04:05:15 → 04:52:05；矩阵 05:01:39 → 05:30:50。

---

## ① 构建前输入（现核）

| 项 | 现读 | 位置 |
|---|---|---|
| `BUILD_ID_V` | **`32'h0000002B`** | `board/wrapper_p4.v:4824` |
| `SNAP_NW_P6E` | **83**（W0..W82） | `board/wrapper_p4.v:3522` |
| 未实现地址 | **`0x17C`**（word 95 = `0x20+4*83+16`） | 同上注释 |
| MIR 四字 | `0x16C/0x170/0x174/0x178` | `SNAP_LAST_IDX` 自动下移 |
| SFP2 mode | **A**（`SFP2_MODE_A_DEF=1`） | 宏追加（下条） |

**宏追加（唯一源码编辑，授权项）**——`board/build_p7b_ku5p.tcl:286`：
```
-set_property verilog_define {APP_MODE=1 DEV_USP=1 PCIE_OBS=1 DP_156MHZ=1 P7B_10G=1 UDP_TX_OVL=1 TCP_TX_OVL=1} [current_fileset]
+set_property verilog_define {APP_MODE=1 DEV_USP=1 PCIE_OBS=1 DP_156MHZ=1 P7B_10G=1 UDP_TX_OVL=1 TCP_TX_OVL=1 SFP2_MODE_A=1} [current_fileset]
```
`git diff --stat` = **1 file, 1 insertion, 1 deletion**（既有 7 宏一字未动）。
构建日志回读 `P7B_VERILOG_DEFINE = APP_MODE=1 DEV_USP=1 PCIE_OBS=1 DP_156MHZ=1 P7B_10G=1 UDP_TX_OVL=1 TCP_TX_OVL=1 SFP2_MODE_A=1` ✅

**构建读的 wrapper = `board/wrapper_p4.v`**（`import_files ${script_dir}/wrapper_p4.v`，`script_dir` = `board/`）：
sha256 = **`c45203e53580bf4f7077e154d8c8f51f2440fe842f1e31eea625740e31120ae4`**。
⚠️ `vivado_prj/p7b_ku5p_prj.srcs/sources_1/imports/board/wrapper_p4.v` 是 **0x2A 代旧副本**
（sha256 `214dac09…`）——**未被本构建读取**（`create_project -force` 每次重建 imports 面）。

HEAD = **`a3ac6db3331d3bc8d644532ca38574219e92b847`**（`4ff38912` 是其祖先，已核）。
构建前工作树 tracked 修改 = **仅 `board/build_p7b_ku5p.tcl`**（上述 1 行）；其余为既存 untracked 残渣。
进程预检：04:01 `tasklist` 无 vivado / xsim / xelab（EXIT=1，零命中）。

---

## ② 构建读数（`build/BUILD_CONSOLE.txt` · `build/READINGS_BID2B.txt`）

| 项 | 读数 |
|---|---|
| 调用式 | `cmd //c 'board\run_build_p7b_ku5p.bat'`（Git Bash；**未**与 `MSYS_NO_PATHCONV` 并用） |
| 时间线 | **START 04:05:15** → synth `Complete!` ~04:24 → impl → **write_bitstream Complete** → **END 04:52:05**（≈46m50s） |
| `BAT_RC` / `BUILD_EXIT` | **0 / 0**；console 末 = **`BITSTREAM-OK`** |
| IP | `P7B_CONVERGED_AT_ROUND = 2`；`P7B_IS_LOCKED_POSTGEN = 0` |
| XDMA | `RC_BASE=0` · `RC_INTF=0`（`<AXI_Stream>`）· `RB_MISMATCH_N=0`（13/13）· `GEN_BAD_N=0`（6/6）· `CFGDIFF_ST_N=1` · `CFGDIFF_MM_N=2` · **`VERDICT = OK`** |
| **P7B_WNS / P7B_WHS** | **`+0.048` / `+0.010`** |
| **三类失败端点** | **`0 / 0 / 0`** —— WNS `0.048`/TNS `0.000`/**0/265,977**；WHS `0.010`/THS `0.000`/**0/265,977**；WPWS `0.000`/TPWS `0.000`/**0/86,604** |
| `Slack (VIOLATED)` | **0 条**；`All user specified timing constraints are met.` 在档 |
| 硬门 `12-4739` | **0 命中** |
| 隐式网五键 | `Synth 8-11241` = 0 · `undeclared symbol` = 0 · `VRFC 10-3091] actual bit length 1 differs…` = 0 · `VRFC 10-2989` = 0 · `implicitly declared` = 0 |
| DRC（routed） | **0 Error / 0 Critical**；`Checks found: 69`（与 0x2A 同数） |
| Route | `# of nets with routing errors = 0`；fully routed **142,079** |
| 位流 | sha256 **`7dd2ea3316dbed3915239d39391c90765ad6b7c8a9d472fa1c8fecca54ba2c23`** · **15,431,261 B** · **`SW_CRC=f65e8188`** |

**CRITICAL WARNING 对照**：本构建 2 条 = ① `Constraints 18-1056` gtrefclk0 覆盖 pcs64.xdc 同名钟 ② `12-1790` Evaluation License；与 0x2A 归档 `runme_impl_1.log` **逐字同族同数**（非新增）。

---

## ③ 时序细节 / DP 定向观察（DESIGN §10.3）

**全局 WNS 宿主** = `u_tcp_tx/u_fifo_a/wptr_reg[0]_replica/C → u_app/bcnt_reg[1]/CE`（`g_hw.clk_out0` 组；`+0.048`）。
⚠️ 与 0x2A 的宿主（`u_tcp_tx/u_fifo_b/rptr_reg[3]/C → u_app/stg_reg[26]/D`，`+0.039`）**是不同对象** ⇒ 按 #66 **只并列、不归因**。

**DP 组（`g_hw.clk_out0`）top10 by slack**：`+0.048 … +0.084`，全部是既存族
（`u_tcp_tx/u_fifo_a` → `u_app/bcnt|pw_*|orph_cnt`；`u_app_udp/u_txf` → `u_udp_tx/ip_csum_r`）。
**新 ch0 构造一条都没进 DP top10**（原件 `gates/STA_DP_OBSERVE_0x2B.txt`）。

**ch0 RX 域（`rxoutclk_out[0]_2`）**：intra-clock **WNS `+0.181` / WHS `+0.013`**，4,834 端点，**0 失败**；
最差路 = `pcs64… → u_mac_rx_ch0/stat_crc_err_reg[10]/CE`（13 级；logic 1.667 / route 4.338 ns）。
ch1 域 `rxoutclk_out[0]_3`：WNS `+0.515` / WHS `+0.010`，9,673 端点，0 失败。

**定向 `-from` 查询（DESIGN §10.3 清单）**：全部远离临界 ——
`pcs0_ferr_sr` +5.456 · `pcs0_bad_sr` +4.627 · `pcs0_badv_sr` +5.808 · `pcs0_erv_sr` +5.593 ·
`pcs0_vcc_sr` +5.687 · `pcs0_fifo_sr` +5.884 · `los1_sr` +5.593 · `los2_sr` +4.979 ·
`los1_evt` +5.352 · `los2_evt` +4.787 · `pcs0_ferr_evt` +5.276 · `pcs0_bad_evt` +4.991 ·
`pcs0_erv_evt` +5.130 · `pcs0_vcc_cyc` +5.494（单位 ns）。
`u_snap_p7bdp/hold_b_reg*`：INTO 最差 `+0.801`（`rstb_sync → CLR`）；FROM 命中的是
`hold_b_reg[708]/C → dout_a_reg[708]/D` 的**异步跨域**（SLACK 属性为空 = 被 `set_clock_groups` 排除）。
**top-200 最差路清单**里 15 个 ch0 家族名 **0 命中**（原件 `gates/TOP200_0x2B.rpt` / `gates/STA_FOLLOWUP_0x2B.txt`）。
⚠️ 脚本里两个名字是拼写壳（`pcs0_errv_sr` / `las_prim_cnt` 各 0 匹配）；实信号 `pcs0_erv_sr` 已覆盖。

**`report_clock_interaction`**：新 ch0 钟 `rxoutclk_out[0]_2` 的所有跨域行全部
`Ignored / Asynchronous Groups`（→`g_hw.clk_out0` 13 端点、→`pcie_axi_aclk` 129、→`sys_clk_100` 4）。
唯一的 `Timed (unsafe)` 行 = `txoutclk_out[0]_3 → rxoutclk_out[0]_3`（64 端点 / 6.40）——
**与 0x2A 的 `txoutclk_out[0]_1 → rxoutclk_out[0]_1`（64 / 6.40）逐项同签名** = 既存、非本刀新增。
原件 `gates/CLKINTERACT_CH0_2B.txt`。

**Methodology 计数（同报告，只登记）**：TIMING-7 = 1（= 上行那条既存 tx→rx No-Common-Node）、
DPIR-2 = 64 · LUTAR-1 = 20 · SYNTH-4 = 18 · SYNTH-6 = 100 · SYNTH-10 = 4 · SYNTH-15 = 256 · TIMING-9 = 1。
⚠️ 0x2A 轮的 methodology 报告未被归档（`create_project -force` 清掉）⇒ **无跨构建逐项对照**；不据此下结论。

---

## ④ 资源（只并列，不归因）

| 指标 | **0x2B（placed）** | 0x2A（placed） | Δ | **0x2B（synth）** | 0x2A（synth） | Δ |
|---|---|---|---|---|---|---|
| CLB LUTs | **80,024** | 78,248 | **+1,776** | **64,331** | 62,681 | **+1,650** |
| CLB Registers | **76,888** | 75,360 | **+1,528** | **55,133** | 54,059 | **+1,074** |
| Block RAM Tile | **348** | 348 | 0 | **312** | 312 | 0 |
| URAM | **1** | 1 | 0 | **1** | 1 | 0 |
| DSP | **4** | 4 | 0 | **4** | 4 | 0 |
| GTYE4_CHANNEL | **6** | 6 | 0 | 0（synth 不报 GT） | 0 | — |

（纸面估计 ≈ +1.5k LUT / +1.8k FF / +0 BRAM / +0 URAM；本刀 ch0 `mac_rx_10g` 第二实例复用既有源码。）
⚠️ Δ 与纸面不逐项相同；**无拆刀 A/B ⇒ 不归因**。

---

## ⑤ backstop —— **未触发**

`WNS +0.048 > 0` 且三类失败端点 `0/0/0`、`Slack (VIOLATED) = 0`
⇒ **未执行 B1/B2/B3/B4，也未 abort-to-P0**；W76..W82 与 ch0 MAC 全部在位，几何 = 完整 0x2B 形态（83 字 / `0x17C`）。

---

## ⑥ 门（全部读数为本轮现跑）

### 6.1 矩阵 21 门（`gates/MATRIX_STDOUT.txt` · `gates/matrix_p4dfix.log`）

- **21/21 门 `EXIT=0` · `gates failed: 0` · 矩阵 RC = 0**（05:01:39 → 05:30:50）。
- **`VERDICT: FROZEN`** —— **308 hashed files byte-identical across the run**；
  **content digest = `3f3ba871763654814d3f25c810afdb15f500882a9a4e1161d20e6fde3b2e4869`**
  （与修复轮 Run 1/Run 2 **逐字相同**）；`DIGEST_ALL` = `4af1b9cd…` / `DIGEST_COMPILE` = `c24d6517…` /
  `FILES_COMPILE=241` / `FILES_ALL=308` / **`GIT_HEAD = a3ac6db3`**。
- 指纹 before/after diff（`gates/FINGERPRINT_DIFF.txt`，22 行）= **仅 2 行头**（label/run-at）+ **5 件 mutant 文件仅 mtime 变、sha256 逐字相同**
  （`sim/f3_resync/mut/{mut_m1,mut_m2}.v` · `sim/p9_swc_gate/mut/{m6_v1_eq,m6b_closing_drop,m7_guard_swpend}.v`；矩阵每轮重生成 mutant）⇒ **无内容漂移**。
- 关键门读数：`p7b_chain` = **`tb_p7b_chain done: 161 checks, 0 fail` / `VERDICT = PASS`**；
  `swc` = `P9-SWC-GATE: PASS`；`p5_wrapper` EXIT=0；`unit_vlan` EXIT=0（**本轮未复现修复轮 Run 1 的瞬时非零**）。
- ⚠️ 修复轮登记过 Run 1 的 `unit_vlan` 工具瞬态；本轮单跑 21/21 全 EXIT=0 —— 与该瞬时故障的判定相容，但**不作"已证不存在"**。

### 6.2 读侧（`readside/`）

- **assert RC=0：52 × OK / 0 × FAIL** —— A 表长 5/5（83）· B 四族全扫命中 **160/129/175/61 文件，未登记 0** ·
  C 默认值一致性全绿（NW=83 / EXPECT_BID=0x0000002B / UNIMPL 0x17C）· D 清单-断言覆盖 **17/17**。
- **负控 4/4 有牙**：`table` RC=1（恰 1 红）· `bid` RC=1（恰 1 红，含 `j6_r6fix.sh[BID]`）·
  `tier` RC=1（恰 1 红，含 `tcpreg_j6.sh[TIER_TOP]`）· `face` RC=1（3 红）。
- `--face` census = **525 行 / 256 文件**。
- `--apply` 面 = `APPLY_READSIDE_BID OK (target 0x0000002B, 0 阶段 / 0 处 edit, 0 fail)` = **已同步，无待落编辑**。

### 6.3 p6e 双门（咬合见证；BID/几何换代后）

- **wrapper：`PASS_ALL` · 155 × `[PASS]` / 0 × `[FAIL]` · RC=0**（0x2A 基数 148；+7 = ch0/几何新断言，**未逐条归因**）。
- **counters：`PASS_ALL` · 26 × `[PASS]` / 0 × `[FAIL]` · RC=0**（= 0x2A 基数逐字复现）。

### 6.4 tb_biz_win / check_window（几何 83 字）

- `check_window.py`：**`PASS=108 FAIL=0 INFO=1` / `CHECK_WINDOW_PASS`**；
  三变异负控 `drop` / `swap` / `declpatho` **各 RC=1**。
- `tb_biz_win`：**`PASS_ALL  tb_biz_win: 40 项判据全过 (窗口 83 字)` / `TB_BIZ_WIN_PASS`**；
  门级 `BIZ_WIN_CHECK_PASS`、`GATE biz_win EXIT=0`。
- ⚠️ 门 console 里夹了一行 `系统找不到指定的文件。`（位置在 check_window 负控之后、tb 输出之前）；
  **两个 checker 均全过、门 EXIT=0** ⇒ 登记为**未归因的良性 cmd 噪声**（不当作判据）。

---

## ⑦ 归档与输入绑定

- **构建前自动归档（#54，脚本自带）** = `_proj_10g/notes/p7b_build_archive/20261018_040515/`（**19 件**，含 `SHA256SUMS.txt`）。
  其中 `wrapper_p4.bit` sha256 = **`aa44a0eda1604623eac951afc26b9f27d4798fc414a5eb9c7137ee47f9a2a3b6`** = **0x2A 位流**（provenance 已核）。
- **构建输入绑定**：`env/BUILD_INPUT_HASHES_{BEFORE,AFTER}.txt` = **222 件**（`build_p7b_ku5p.tcl` 显式 import 面：
  HLS 173 `.v` + 3 `.dat` + rtl 27 + obs 7 + `axi_regs.v` + mac 3 + board 4 + xdc 4）；
  **BEFORE == AFTER（`diff` rc=0，0 变）**。
  ⚠️ 0x2A 轮用的是 **287 件** universe、生成器未记录 ⇒ **本轮口径 = 222 件自洽快照，不与 287 逐件对比**（如实登记）。

轮目录内容：`build/`（位流副本 + `wrapper_p4_routed.dcp` + `board_rpt/` 15 件 + `READINGS_BID2B.txt` + `BIT_SHA256_BID2B.txt` + collector）·
`gates/`（矩阵 stdout/log/tail/指纹/diff · STA 三件 + top200 · 时钟交互对照 · biz_win 日志）·
`readside/`（assert/negctl/face/p6e 双门）· `env/`（前态 + 输入哈希）· `SHA256SUMS.txt`。

---

## ⑧ 偏离 / 未测 / 残余（不许当已答）

1. **输入哈希 universe 口径不同**：本轮 222 件（显式 import 面）vs 0x2A 的 287 件（生成器未留存）⇒ 只做本轮的 before/after 绑定。
2. **p6e wrapper PASS 数 148 → 155**（+7）：与修复轮新增的 ch0/几何断言相容，但**未逐条对照**是哪 7 条。
3. **Directed STA 脚本两个拼写壳**：`pcs0_errv_sr` / `las_prim_cnt` 0 匹配（实信号 `pcs0_erv_sr` / `los_prim_cnt` 已覆盖）；`los_prim_cnt` 未单独查询。
4. **Methodology 计数无 0x2A 对照**（旧报告被 `create_project -force` 清掉）⇒ 只登记绝对值，不判"新增/未新增"。
5. **WPWS 汇总值 0.000**（0 失败端点 / 86,604）—— 与 0x2A `0/85,060` 同形态；**未判定**其是否属于"0 需求"类检查。
6. **biz_win 门 console 的一行 cmd 噪声未归因**（见 6.4）；不影响两个 checker 的读数。
7. **板级全部未测**：位流身份（BID/几何）、ch0 link、W76..W82 语义、LOS、负对照、ch1 业务回归、BER、功耗/温度 —— 全部**未测**。
8. **QSPI / 对端 / git 提交**：均未触碰（按纪律；提交归 TL）。
9. 矩阵在本轮**只跑一次**（21/21 EXIT=0）；未做第二次重复。

---

## ⑨ 板级前置清单（下一轮；本文件**不烧板**）

1. 重烧本轮位流：`_proj_10g/notes/p9_build_0x2B_20261018/build/wrapper_p4.bit`
   sha256 = **`7dd2ea3316dbed3915239d39391c90765ad6b7c8a9d472fa1c8fecca54ba2c23`**（15,431,261 B；`SW_CRC=f65e8188`）。
2. 身份门期望：`0x04 = 0x0000002B` · 快照 **83 字** · 未实现地址 **`0x17C` 读 `0xffffffff`** · **2 BARs**（config 1 / user 0）· `LnkSta` **x4**。
3. **读 W79..W82 前必须先核 `SNAP_STATUS[7] = 0`**（ch0 束本代；否则读到陈旧/半更新）。
4. ch1 保持现役配方；`0x08` **bit1 保持 0**；对端 p0 `managed no` + `ip link up`（每次现取，见既有配方）。
5. 判据草案与负对照表 = DESIGN_v5 §10.4（S-1…S-7）；本轮**未**改写任何判据。
