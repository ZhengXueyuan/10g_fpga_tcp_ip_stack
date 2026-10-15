# p9_mdio_board_20261015 —— 板级轮 B3：mdio 修复收口（门 → 构建 → VIO 板测 → 收尾）

> **agent 原件由平台拒写 .md ⇒ 全文回传、TL 代落盘**（本件正文 = agent 原文；文末「TL 附加」= TL 独立抽核记录）。
> 轮 = 板级轮 B3 · 日期 = 2026-10-15 13:09-13:23 · 依据 = `_proj_10g/notes/p9_fix_mdio_design_20261014/DESIGN_v2r2.md`（经 v2r3/v2r4 增量修订）+ 实施轮 `p9_fix_mdio_impl_20261015/REPORT.md` + 交接件 `p9_board_rfcseq_20261015/REPORT.md` §7。
> ⛔ 本件 = **读数与形态**；一切 PASS/FAIL 裁定权在用户/判据所有者。全程只走 **JTAG 易失**，**QSPI 一字未写**。
> **状态一行话**：三件全部落地 —— ① elab 门 **PASS** 且**覆盖见证锚点 `vio_0.v:49` 逐字命中**（负对照精确变红）；② 位流重建 **`4c74c219…`**（`WNS +7.328 / WHS +0.029 / WPWS +4.427`，三列失败端点 **0/0/0**）；③ 板测三臂全中（**探针宽度 22** / **应答集恰 {0,1}** / **新鲜性序列逐字命中** / **新位恒 0**）；收尾已按"最新现役"口径回到 **0x27 + `0x08=0` + carrier=1**，三条硬判据 + 身份门全中。

---

## §1 覆盖见证锚点核实（第一件事；impl REPORT §4-A 的**未实跑**结论）

| 项 | 值 |
|---|---|
| 期望（impl REPORT §4-A） | `10-3609 … [vio_0.v:49]`（= patch 后的 stub 排到编译表**最后** ⇒ stub 成为生效定义） |
| **实测**（`gate/gate_run/xvlog.stdout.txt:103` 逐字） | `WARNING: [VRFC 10-3609] overwriting previous definition of module 'vio_0' [.../gate_run/vio_0.v:49]` |
| 结论 | ✅ **锚点 = `vio_0.v:49`，与派单要求的前置一致 ⇒ 继续（未停手）** |

**旁证（同一次跑）**：xelab 的 `Compiling module` 表里**不再出现** `unisims_ver.LUT6 / FDRE_default / GND`（骨架那一轮有 —— 那些原语只在冻结网表内部）⇒ 生效定义确实是 **stub**（22 位），不是 20 位网表；elab 全程 0 条 `10-3091`。
**含义**：v2 §3.4 的"只改 stub 不生效"（D1）与门的"换顺序 ⇒ 保文件集、留见证"处置**双双被实跑证实**。

---

## §2 门读数（`gate_elab_22/run.bat` ×3：正 → 负 → 还原）

> 运行位置 = **本轮副本** `gate/gate_run/`（文件集逐字未改；副本 `sha256sum -c SHA256SUMS.txt` **11/11 OK**）。
> 未在实施轮目录原地跑（避免给已封口的轮目录追加运行产物）。**门在 `_proj_mdio/gate_elab_22/` 不存在** —— 任务书路径偏差，见 §6-1。

| 跑 | 输入 | 判据尾行 | 退出码 | 关键行 |
|---|---|---|---|---|
| run1 正臂 | 编辑后（`79c360f8…`） | `GATE_PASS` | **0** | `XELAB_RC=0`；F1-F5 全中（`:88 [21:0]` · `:149` 拼接序 · `vio_0.v:60 [21:0]` · `tcl:30 {22}`） |
| run2 负对照 | `negctrl/mdio_vio_top.v`（恰删 1 行 `.param_bad (param_bad),`） | `GATE_FAIL: F2_PORT_UNCONNECTED_10-3645` | **1** | `xelab.log:8` = `WARNING: [VRFC 10-3645] port 'param_bad' remains unconnected … [mdio_vio_top.v:127]`；**`XELAB_RC` 仍 0**（红在警告行上 —— 与门注记/`APPLY_AND_EXPECT.txt` 预测逐条吻合） |
| run3 还原后 | 从实施轮目录回拷好件（现读 sha = `79c360f8…` ✓） | `GATE_PASS` | **0** | 锚点仍 `vio_0.v:49`；终态 11/11 自核 OK |

**负对照口径核实**：变异件与好件 diff = **恰 1 行**（`144a145`，即 `.param_bad` 接线行）；门对它的红**精确落在 F2**（不是别的判据乱红）。

---

## §3 构建读数（vs 旧基线）

配方 = `_proj_mdio/build_mdio.tcl`（`vivado -mode batch`，经 `build/run_build_mdio.bat`）；⚠️ `create_project -force` 已按纪律先把旧产物整组归档（`p9_fix_mdio_impl_20261015/archive_20260928/` 自核 **15/15 OK**，本轮再核一次）。

| 指标 | **新（2026-10-15）** | 旧基线（2026-09-28，归档件） |
|---|---|---|
| WNS | **+7.328** | +7.091 |
| TNS / 失败端点 | 0.000 / **0** | 0 / 0 |
| WHS | **+0.029** | +0.020 |
| THS / 失败端点 | 0.000 / **0** | 0 / 0 |
| WPWS | **+4.427** | +4.427 |
| TPWS / 失败端点 | 0.000 / **0** | 0 / 0 |
| 报告尾句 | `All user specified timing constraints are met.` | （同族） |

⇒ **无异常**：WNS 仍 +7 ns 级（与设计件 §3.2"只 +1 FF + 常量 + VIO 6 位"的预期一致），**未**掉到 <1 ns 判停界。

**产物**（`build/` 内已归档副本 + `pj_mdio/` 原件同 sha）：

| 件 | sha256 | 字节 | 备注 |
|---|---|---|---|
| `mdio_vio_top.bit` | **`4c74c219bf6cceb668b882cfa4d4a356ae128dfd8137578709453cf980e7132a`** | 15,431,263 | ≠ 旧 `46417aff…92ad2` ✓（新构建） |
| `mdio_vio_top.ltx` | `46f53c81b305fdf1f4260fd18f6c4c7c011c2f6d3ef2cc967c1972a3bb4f75fc` | 14,756 | 旧 14,414 B；**内容核查 = 恰 22 位** `vio_probe_in[0..21]` ⇒ 位宽同步已进构建产物 |
| `timing_summary.rpt` | （见 SHA256SUMS） | 80,594 | 上表出处 |
| `BUILD_STDOUT.txt` | （见 SHA256SUMS） | — | `TIMING_WNS 7.328 / TIMING_WHS 0.029`、`BITSTREAM_BYTES 15431263`、`=== BUILD DONE ===`，进程退出码 0 |

---

## §4 板测逐条（`board/PROBE_STDOUT.txt` 全程原始 stdout = **R-c 要求的第一份一手存档**）

### 4.0 前置（DESIGN v2r4 §4.0 / R4-M2）
对端可达 ✓ · `hw_server` = `active` ✓ · `get_hw_targets` 非空 ✓ · **对端工具基线在位** ✓（`/tmp/p7b_biz/p7b_tcp_src` md5 `79be2a09…`、`p7b_snap.sh` md5 `32b97715…`，与 B1/B2 交接值逐字相同；`$T/reg_rw` 在位）· **PRE 见证**（烧 mdio 前，`burn/BURN_mdio_20261015_131632.txt`）：`0x04 = 0x00000027`、`0x08 = 0x00000000`、`carrier = 1`。

### 4.1 烧 mdio 位流（`burn/burn_mdio.sh`，五判据照 B1/B2 先例）
sha/size 门：`WANT = GOT = 4c74c219…`、15,431,263 B ✓ ⇒ 烧录五判据：**`End of startup status: HIGH` + `TCPREG_PROG_DONE` + 位流路径匹配 + 无 `TCPREG-ABORT` + stdout 新鲜度** ⇒ `BURN_OK`。预期副作用（PCIe 端点消失）**不在此恢复**（设计件 §4.1 口径）。

### 4.2 VIO 读数（驱动 = `board/probe_mdio_v2.tcl`；基础 = `probe_phy.tcl` **去掉自带烧录段**，五坑配方原样）

| # | 判据（设计件 §4.2） | 实测 | 形态 |
|---|---|---|---|
| W | **探针位宽 = 22**（§2.4 直接判据） | `STATUS_WIDTH=22` | ✅ 逐字命中（位宽同步"已生效"不再靠推断） |
| W2 | 输出通路自证 | `WRITE_CHECK phyad set to 5, reads back <05>` | ✅ |
| W3 | 旧位位置语义（闲态） | `IDLE_STATUS rd=0000 done=0 busy=0 rstn=1 mdio=1 ssl=0 pbad=0` | ✅（mdio 闲高、rstn 高、busy 低 —— 旧 20 位位置未动） |
| **J-A** | 32 地址 × {reg2,reg3}：应答集**恰 = {0,1}**、两者均 `001C/C915`、2–31 两寄存器均 `FFFF`；每事务 `done=1` | `ARM_J_A_ANSWERED 0,1`；addr0/1 = `PHYID1=001C PHYID2=C915 (001CC915)`；addr 2–31 = `FFFF/FFFF`（30 静默）；`ARM_J_A_NO_RESPONSE`（空）⇒ **64/64 事务 done=1** | ✅ **逐条命中**（含 2–31 静默负对照，与历史同形） |
| **J-B** | 交错新鲜性：(1,r2)(7,r2)(0,r2)(7,r2)(0,r2)(1,r2)(31,r2) ⇒ `001C FFFF 001C FFFF 001C 001C FFFF` | `ARM_J_B_RD 001C FFFF 001C FFFF 001C 001C FFFF` | ✅ **逐字相同**（静默地址回 `FFFF` 而非陈旧 `001C`；每个 `001C` 与前一个之间至少隔一个 `FFFF`，除设计上相邻的末对 `(0,r2)→(1,r2)`） |
| **J-D** | 新增位可见性：每条记录 `ssl`(bit20)/`pbad`(bit21) 列存在；生产臂期望 0 | 全部 **71** 条 TX 记录 `ssl=0 pbad=0`；`ARM_J_A_SSL_SUM=0` / `ARM_J_A_PBAD_SUM=0` | ✅ 出现且**恒 0** —— ⛔ 恒 0 与"未接线"读数上不可区分（R-b），**不许**据此声称"新两位已在板上验过" |
| J-C | 写穿越（**可选/低优先**） | **未跑** | 见 §7-3 |

**逐事务原始记录**（首行样例，全 71 行在 `PROBE_STDOUT.txt`）：
`TX A_r2 phyad=00 regad=02 rd=001C done=1 busy=0 rstn=1 mdio=1 ssl=0 pbad=0`

### 4.3 收尾（`burn/burn_arm.sh 0x27`；**按任务"最新现役"口径**）
0x27 源件 sha256 **`5c17b14f0656cf6680b7d16f7f1659faa4ca9225cf0cb0461765be7a91943385`**（= 任务书锚 `5c17b14f…3385`，且与 `p9_build_0x27/SHA256SUMS.txt` 记录逐字相同）⇒ 烧录五判据 `BURN_OK` ⇒ PCIe 恢复 **设备级一次成功**（`LnkSta: Speed 5GT/s (downgraded), Width x4`、`2 BARs`、`/dev/xdma0_{user,control,c2h_0,h2c_0}` 全现）⇒ 身份门：`MAGIC 0x50360001` / **`BID 0x00000027`** / `MARKER 0xdeadbeef` / `UNIMPL 0x14C=0xffffffff` / `ID_RC=0` / `WINDOW_SCAN_NFF=0`（71 字）⇒ `0x08` 置 0。

**三条硬判据显式复算**（`burn/HARD_CRITERIA_CHECK.txt`，对 burn 日志 `grep -q`）：

| 硬判据 | 期望（本轮口径） | 实测行 | 形态 |
|---|---|---|---|
| 1 `ID_RC=0` | `ID_RC=0` | `:51 ID_RC=0` | ✅ `C1_PASS` |
| 2 终态链宽 | `LnkSta:…Width x4` | `:32 LnkSta: Speed 5GT/s (downgraded), Width x4` | ✅ `C2_PASS` |
| 3 `BID_0x04` | **`0x00000027`**（偏离后口径；设计件原文 = `0x24`） | `:42 BID_0x04=…: 0x00000027` | ✅ `C3_PASS` |
| 建议项 | MAGIC / UNIMPL / 2 BARs / NFF=0 | 全中（`:41/:44/:38/:52`） | ✅ |

**FINAL_STATE**（`FINAL_STATE_FINAL.txt`）：`0x04=0x00000027` · `0x08=0x00000000` · `ID_RC=0` · `LnkSta x4` · 四节点在位 · NIC `carrier=1` / `192.168.100.100/32` / unmanaged / Adaptive RX off · **无残留进程**。
⇒ **板上现态 = 0x27 + `0x08=0`（未受控停流）+ carrier=1 = 与 B1/B2 交接的现役态逐字一致**。

---

## §5 交付物 / 证据地图

| 路径 | 内容 |
|---|---|
| `gate/GATE_READINGS.txt` | 门读数汇总（含**锚点核实**结论） |
| `gate/GATE_STDOUT.txt` · `gate/logs_pass/` · `gate/logs_neg/` | run3 终态 / run1 正臂（含 `xvlog.stdout.txt`/`xelab.log`/`elab_rc.txt`）/ run2 负对照 |
| `gate/gate_run/` | 实跑的副本目录（文件集逐字未改 + 运行产物 + `xsim.dir` 快照） |
| `build/BUILD_STDOUT.txt` · `READINGS.txt` · `timing_summary.rpt` · `mdio_vio_top.{bit,ltx}` · `impl_runme.log` | 构建全部原件 |
| `board/PROBE_STDOUT.txt` | **VIO 全程原始 stdout（第一份一手存档）** |
| `board/BOARD_READINGS.txt` · `artifacts/{bit,ltx}` · `probe_mdio_v2.tcl` · `run_probe_mdio_v2.bat` · `read_final_state.sh` | 板测读数汇总 / 被烧副本 / 驱动与启动件 |
| `burn/BURN_mdio_*.txt` · `BURN_0x27_*.txt` · `HARD_CRITERIA_CHECK.txt` · `burn_mdio.sh` · `burn_arm.sh` · `wrapper_p4_0x27.bit` | 两次烧录原件、硬判据复算、脚本、0x27 副本 |
| `FINAL_STATE_FINAL.txt` · `SHA256SUMS.txt`（162 件） | 收尾态 / 全轮哈希面 |

---

## §6 异常与偏离（逐条，如实）

1. **任务书路径偏差**：任务书写门在 `_proj_mdio/gate_elab_22/run.bat` —— **该路径不存在**（`ls` 实测）。门实际在 `_proj_10g/notes/p9_fix_mdio_impl_20261015/gate_elab_22/`（实施轮 REPORT §3 与 `DESIGN_v2r2` §3.4 的记载一致）。⇒ 用实际路径执行；**门件一字未改**。
2. **收尾口径偏离（任务书已预先授权登记）**：设计件 §4.4 原写"收尾目标 **0x24 + 受控停流**"；因现役已到 0x27，**按任务指令改按"最新现役"口径** = **0x27 + `0x08=0`（未受控停流）+ carrier=1**（= B1/B2 交接态，逐字一致）。⇒ 硬判据 3 的期望值随之改为 `0x00000027`（原文 `0x00000024`）。
3. **`burn_arm.sh` 的 `BIT_WIN` 硬编码指向 B2 轮目录**（复制时只重定向了 `OUT`）⇒ 0x27 那次烧录**实际读的是** `p9_board_rfcseq_20261015/burn/wrapper_p4_0x27.bit`。**三份副本 sha 全同**（实际被烧件 / 本轮副本 / 权威源 = `5c17b14f…943385`，逐字核过）⇒ **零实质影响**，但按纪律登记（"脚本内路径与轮目录解耦"这条没做到）。
4. **写 bat 的转义事故（本轮自伤，已恢复）**：第一次用 `printf` 写 `run_build_mdio.bat`，`\\` 被上层塌缩 ⇒ `\r` 变成 CR ⇒ bat 内容坏（`cd /d D:` + CR）⇒ **构建根本没启动**（旧 `pj_mdio/` 未被触碰，实测原件 mtime 仍 2026-09-28）。改用 heredoc + `sed 's/$/\r/'` 重写并 `cat -A` 逐行核过。
5. **`cmd //c run.bat`（相对路径形态）在 Git Bash 下解析失败**（"不是内部或外部命令"，尽管 cmd 的 cwd 正确）⇒ 全程改用**全路径形态** `cmd //c "<abs>.bat"`（与既有纪律一致）。
6. **门在本轮副本目录运行**（非实施轮目录原地跑）—— 目的 = 不给已封口轮目录追加运行产物；副本已 11/11 自核，实跑前后文件集逐字未改。
7. 历史上"`p7b_snap.sh` 身份门不补零"的坑（B2 登记）：本轮 `EXPECT_BID=0x00000027` **已按 8 位补零**传参 ⇒ 未踩（`ID_RC=0` 即证）。

---

## §7 未观测 / 未做（"未观测到" ≠ "不存在"）

1. **两个新位（`param_bad`/`stat_start_lost`）的板上行为验证仍缺**（R-b）：生产臂只能给"**出现且恒 0**"，与未接线不可区分；行为级验证只在 xsim。**A+ 变体臂（E7/E8，`DIV=65537`）未做**（不在实施轮/本轮派单范围）⇒ 两个新位的**板上正控仍无**。
2. **VIO 网段未覆盖**（R-a，现状照旧）：`vio_phyad`（VIO core 输出 → 端口 → `sh[27:23]` 装载）**无 TB、无结构论证** ⇒ "{0,1} 答、2–31 静默"的真实等价类 = "**地址 bit0 在该网段被置 1**"，比"帧内 PHYAD 字段被改成 1"更宽 ⇒ **不许写"已排除地址字段伪影"**。
3. **J-C 写穿越未跑**（可选/低优先）：J-B 已覆盖"读值非陈旧/回显"这一主问；写 ANAR 有链路风险（R6）⇒ 按设计件的"可选"定位跳过。
4. **§3.5 TB 回归未跑**（可选）：本轮只碰 top 与构建脚本，`mdio_master.v`/`tb_mdio_master.v` 一字未动。
5. **`stat_start_lost` 的宿主不可触发**：busy 窗 32 µs ≪ JTAG commit 间隔（数十 ms）⇒ 生产臂结构性打不到（这正是 A+ 臂存在的理由）。
6. **mdio 阶段未采 PCIe/NIC 侧读数**（设计使然：mdio 设计无 PCIe，判活只走 JTAG/VIO；对 mdio 状态下的 1G link 状态**未观测**）。
7. **R-c 已解**：本轮 `PROBE_STDOUT.txt` = "{0,1} 同 ID" 的**第一份一手 stdout 存档**（此前只有二手登记）。
8. 旧 mdio 位流（`46417aff…`）与新位流（`4c74c219…`）**只有 sha256/字节数可判**（同为 15,431,263 B）。

---

## §8 不许声称（口径）

- ⛔ **不许写**"两个新信号已在板上验过"（= §7-1；只到"出现且恒 0"）。
- ⛔ **不许写**"地址字段伪影已排除"（= §7-2；只能是"确认 + 新鲜性"）。
- ⛔ **不许写**"mdio 修复已被判 PASS"（判据层裁定权在用户/判据所有者；本件只给读数与形态）。
- ⛔ **不许写**"0x24 + 受控停流已恢复"（本轮收尾 = **0x27 + 未受控停流**，见 §6-2）。
- ⛔ 不许把本轮的板级结论外推到"mdio_master 行为级"（行为级 = xsim 单元 TB；生产位流未做过功能仿真 —— 设计件 §7 ③ 照旧）。

----------------------------------------------------------------

## TL 附加（2026-10-15 13:4x；独立抽核 + 裁定）

- **现场核**：`git status` = 轮目录（163 件 / 49 MB）+ `tcpreg_program_stdout.txt`（烧录 stdout）；**mdio 位流现读 `4c74c219…` ✓ · 0x27 收尾副本现读 `5c17b14f…3385` ✓**；`*.bit`（`:69`）/`*.ltx`（`:532`）按 .gitignore 留盘 ✓。
- **裁定**：① **锚点核实**（`10-3609 … [vio_0.v:49]` 逐字命中 + 网表原语不复现旁证）**采纳** —— impl 轮 §4-A 的"未实跑验证"结论**已被实跑证实**；② 门三跑（正 → 负 → 还原）读数**采纳**（负对照恰 1 行 diff、红精确落 F2）；③ 构建读数（`WNS +7.328` 0/0/0、位流 `4c74c219…`、`ltx` 恰 22 位）**采纳**；④ 板测四判据（`STATUS_WIDTH=22` / 应答集恰 {0,1} / 新鲜性逐字 / 新位出现且恒 0）**采纳（读数层）**；⑤ 收尾"最新现役"口径（0x27 + `0x08=0`）**采纳**（任务书预授权；硬判据 3 期望值随之 0x27）；⑥ §8「不许声称」五条**全文采纳**（新两位=只到"出现且恒 0"/未排除地址伪影/不判 PASS/收尾态=0x27 非受控停流/不外推行为级）。
- **路径偏差**（`_proj_mdio/gate_elab_22/` 不存在；实际在实施轮目录）—— 我方派单笔误，agent 已按记载纠正并一字未改门件 ⇒ 采纳；`BIT_WIN` 硬编码（三副本 sha 全同、零实质影响）与 bat 转义自伤（已恢复）均**登记**。
- **入库面**：轮目录（除 bit/ltx）；ledger §10-73；**本件 = 板级验证最后一轮 ⇒ 按用户指令进入关机序（先远程、后本机）**。
