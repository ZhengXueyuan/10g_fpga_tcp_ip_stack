# P11 · 0x31 HLS ROM 未初始化缺陷 → 0x32 修复构建 + 板级验证

- 日期：2026-10-26 01:35–04:1x CST（0x32 构建/板级 01:35–03:0x；延迟研究/xsim 04:0x–04:4x）
- 仓库根：`D:\repo\XCKU5PMini\udp_hls_10g`；HEAD = `4cfa92e2`（本轮改动未提交）
- 板：KU5P（`xcku5p-ffvb676-1-e`），对端 `192.168.0.38`
- 纪律：QSPI 零写入（全部 JTAG 易失、1 MHz）；**0x32 构建/板级轮未跑 xsim**（2026-10-26 追加的 HLS 延迟研究跑了 xsim：`sim/p11_hls_latency/`，独立于本轮构建）；未碰 `D:\repo\perfv` / license；密码只作命令前缀、未落盘
- 状态词：【已证】/【未判定】/【未定位】/【未测】。本件是 TL 记录，不下产品 PASS/FAIL 裁定。

---

## 0. 摘要（逐项状态词）

| # | 项 | 读数 | 状态 |
|---|---|---|---|
| 0x31 根因 | HLS `$readmemh` `.dat` 未与 RTL 同目录 | synth 日志 3 条 `Synth 8-4445` + 3 条 `rom0 ... does not have driver`；0x31 板级 `W7=0 / W20=0`，`W18` 非 0（会话读数，未逐帧归档；`stat_purge` 也计 FIFO-full，故不把“全部是前导 purge”写成已证；ROM 全 0 是充分原因） | 【已证】（构建根因/板级无 TX）；purge 成分【未定位】 |
| 修复 | `board/build_p7b_ku5p.tcl` 显式 `.dat` 导入目录 + 拷贝校验 + synth 日志 `P7B_HLS_ROM_LOG_GATE` | `P11_HLS_DAT_COPIED=3`；`P7B_HLS_ROM_LOG_HITS=0` | 【已证·构建】 |
| 0x32 构建 | `P11_CFG=c4` / `p3_dual_max8` / 合同 2（48KB） / BID 0x32 | WNS **+0.019** / TNS 0.000 / setup 0 / hold 0 / PW 0；WHS +0.010；TCB **stack1 A–F min +0.115 / stack2 A2–G2 min +0.019（= 全局 WNS 宿主 G2）**；`P7B_VERDICT=OK`；位流 `cee8acfd…f581950`（15,431,261 B） | 【已证·构建】 |
| 0x32 身份 | 板上 | BID `0x00000032` / NW 85 / `0x184=0xffffffff` / 2 BARs / `LnkSta 5GT/s x4` / `0x08=0` / carrier p0=p1=1 | 【已证·板级】 |
| 慢路径 | ARP/ICMP/UDP echo | p1 ping 3/3（0.073/0.093/0.117 ms）、p0 ping 3/3（0.064/0.066/0.070 ms）；UDP echo 8080 两口 8 B 逐字节匹配；`W18=0`、`W7=0x15`、`W20=0x68bb9f`（终态快照） | 【已证·板级】 |
| 单口 TCP 下行 | 每口 40GB/5GB | A（p1/IP_A）**9.395 Gbps** / 40,000,005,735 B，`mism=0`、`stall=0`；B（p0/IP_B）5GB 两跑 **9.431 / 9.393 Gbps**，`mism=0` | 【已证·板级】 |
| 双口同时 | 两连接同时（D9R raw 重跑，各 10GB） | **A 8.9367 / B 8.9352 Gbps，聚合 17.8719 Gbps（host-side sum）**，`mism=0`、无 STALL；sink `taskset -c 0,1/2,3` + `--no-pin`；NIC IRQ 40–52 移到兄弟核 4–7；板侧 `W83 +6,850,548` / `W84 +6,850,528` 帧、`W54=0`、`W21=0`、`W4=0`、`W81=0`。⚠️ 旧 D9 会话读数 8.798/8.925 与 0 B 的 `D9_A/D9_B` 是历史（见 §4.4）；**D9R 有 raw sink 日志 + console/env** | **【已证·板级·raw D9R】**（8.9G 同时；2×9.4G 未达，host/SMT 限制） |
| 合同 | SYN-ACK | `win=49152`（0xC000=48KB/连接）、options 仅 `mss 1460`（**无 wscale**）；2×48KB 合同 | 【已证·板级】 |
| TX_DIS 隔离 | `0x08` bit0/bit1 | bit0 ⇒ p0 carrier 0、p1=1；bit1 ⇒ p1=0、p0=1；恢复 0 ⇒ 1/1（`raw/TX_DIS_0x32.txt`） | 【已证·板级】 |
| 0x31 位流 | 功能无效 | 已改名 `*.HLS_ROM_FAIL` 并写 `QUARANTINE_0x31.txt`；**禁烧** | 【已证·构建+板级】 |
| 回归（构建后） | P11 子集 + 其余 | **P11 17/17 + 其余非 BID 22/22 EXIT=0**（`gates/matrix_p11_subset_0x32.log`、`gates/matrix_rest_0x32.log`）；ROM 门负/正控 PASS；读侧 0x32 assert RC=0；旧 build `.dat` 静态门 PASS | 【已证·仿真】 |
| 门逻辑单测 | 抽真实 Tcl 块 + tclsh stub | ROM 四臂 + TCB 四臂 **8/8 PASS**（`gates/gate_unit_test/RESULTS.txt`）；PASS/缺 pin/负 slack/SKIP 均有牙 | 【已证·单测】；**不证 Vivado 集成** |
| 延迟 xsim（追加） | P3 HLS 归档，HLS-only | ARP **14.1 µs**、UDP 74B **20.6 µs**、1500B UDP echo **303 µs**（last→last；无适配器/仲裁/MAC）；实际 ~23 拍/B RX、~28–30 拍/B TX ⇒ 推翻“1 B/拍”纸面 | 【已证·xsim】；板级 E1 未做 |

---

## 1. 0x31 根因（已证）

### 1.1 构建侧物证

`_proj_10g/notes/p11_fix_0x30_0x31_20261025/build0x31_clean/p7b_ku5p_stdout.txt`：

- 第 1352/1358/1548 行：3 条 `CRITICAL WARNING: [Synth 8-4445] could not open $readmem data file './udp_echo_*_ROM_AUTO_1R.dat' ... ignoring`
- 第 1699/1700/1732 行：3 条 `INFO: [Synth 8-3848] Net rom0 ... does not have driver`

原因 = 构建脚本旧回退式路径选择：

```tcl
set src_dir [file dirname [lindex [glob .../imports/verilog/udp_echo.v] 0]]
if {$src_dir eq ""} { ... }
```

`imports/verilog/udp_echo.v` 不存在时 `file dirname ""` 返回 **`"."`（不是空串）** ⇒ `if` 不触发 ⇒ `.dat` 被拷到构建 CWD（`board/`），综合按 RTL 目录找 `./*.dat` 找不到。3 个 `.dat` 散落在 `board/`（已归档到 `evidence/`，sha256 与 HLS 归档逐字相同）。**0x31 构建时** `imports/hls_archive_p3_dual_ip_max8/` 下 0 个 `.dat`（物证 = 0x31 synth 日志 3×`8-4445` + `rom0` no-driver）；**现 0x32 工程已含 3 个 `.dat`（修复后），因此“现读”不可复核 0x31 现场**。

0x2D 构建日志无 `8-4445`（`grep` 0 命中）且板级慢路径工作 ⇒ 该缺陷是 **P3 变体目录命名 + 旧回退路径** 的组合触发；0x2F/0x30 构建日志同样有 `8-4445`（0x2F `BUILD_STDOUT.txt:1353/1359/1549` + `rom0` 行），但两者已因时序失败禁烧。

### 1.2 板级物证（0x31）

`_proj_10g/notes/p11_board_p3_0x31_20261026/raw/B0_SNAP.log`（0x31 上板后，ping/TCP/UDP 全无回包）：

- `W6=0x6d`（109 帧进 HLS）、`W16=0x3ce5`（HLS 读走 15,589 B）
- **`W7=0`**（`slow_tx_adp` 成功转出 0 帧）、**`W18=0x0f`（非 0）**、**`W20=0`**（MAC TX 0 帧）；`W6=0x6d` / `W16=0x3ce5` 证明 HLS 在收/读。
- 会话记录里每次 UDP echo 后 `W18` 继续上涨、`W7` 恒 0（该逐请求读数**未归档**）；TCP SYN 也无 SYN-ACK ⇒ 慢路径全断（建连/ARP/ICMP 都走慢路径）。
- ⚠️ `stat_purge` 也计“帧内容 <1 字 / frame_fifo 满回卷”（`rtl/slow_tx_adp.v:33,310,318`），所以归档的 `W18` **不能单独证明“全部是前导非法”**；但 **ROM 全 0 足以预测前导非法**，且 `W7=0/W20=0` 与“HLS TX 全部不可用”一致。结论 = **0x31 位流功能无效**（不是 board/RTL 数据面缺陷），purge 的逐帧成分【未定位】。

`B0_TCP_UDP_PROBE.log`：TCP connect timeout、UDP echo timeout。⇒ 与 HLS 前导 ROM 全 0 一致；0x32 修复后同板同类测试全部通过（§4）。**不是 board/RTL 行为缺陷。**

---

## 2. 修复（构建脚本）

`board/build_p7b_ku5p.tcl`：

- 第 237–275 行：`.dat` 导入改为**确定目录** `imports/<hls_dir basename>`；不存在时只在唯一 `imports/*/udp_echo.v` 命中时回退；仍不唯一 ⇒ `P7B_VERDICT=HLS_IMPORT_DIR_MISSING` 硬失败。逐个 `file copy` + `file exists` + `file size` 校验；打印 `P11_HLS_DAT_COPIED=<n> dir=...`。
- 第 492–510 行：新增 `P7B_HLS_ROM_LOG_GATE`：读 `synth_1/runme.log`，正则 `8-4445|could not open $readmem|rom0.*does not have driver`，任一命中 ⇒ 打印命中行 + `P7B_VERDICT=HLS_ROM_UNINIT` + exit 1（在 impl 前拦下）。
- 0x32 构建实测：`P11_HLS_DAT_COPIED = 3`（`build0x32/P7B_STDOUT.txt:614`）、`P7B_HLS_ROM_LOG_HITS = 0`（`:4057`）⇒ 门有正控；0x31 日志按同一正则是 6 命中 ⇒ 负控在原件。
- 归档回放负/正控：`gates/check_hls_rom_gate.py` 读 0x31/0x32 日志，**0x31=6 命中 / 0x32=0 命中**、**0x31 `8-3876` 正读=0 / 0x32=3**、`HLS_ROM_GATE_CONTROL=PASS`（`gates/check_hls_rom_gate.txt`）。注意：门实际读 `synth_1/runme.log`；回放脚本跳过构建 stdout 里被 echo 的 Tcl 源行（否则会把正则自身当命中）。
- 2026-10-26 审查 M-6：build tcl 的 ROM 门已增加**正读** `8-3876 ... read successfully` 计数（必须 ≥ 本次拷贝的 `.dat` 数；否则 `HLS_ROM_READ_MISSING` 硬失败）；0x32 实测 3 条（`build0x32/runme_synth_1.log:590/596/786`）。

`board/wrapper_p4.v:6286`：`BUILD_ID_V` 0x31 → **0x32**。

**门的逻辑单测（2026-10-26 追加，不等同 Vivado 构建）**：`gates/gate_unit_test/` 用 `tclsh` 从 `board/build_p7b_ku5p.tcl` **按标记抽取真实门块**，在 stub 的 `get_pins`/`get_timing_paths`/`get_property` 下运行；`RESULTS.txt` **8/8 PASS**：
- ROM 门：good（3 正读）PASS；`8-4445` ⇒ `HLS_ROM_UNINIT`；2 正读/3 `.dat` ⇒ `HLS_ROM_READ_MISSING`；日志缺失 ⇒ `HLS_ROM_LOG_MISSING`。
- TCB 门：全族 PASS（`MIN=0.019`）；A2 pin 缺失 ⇒ `FAIL (family pins missing)` + 位流改名 `.STA_FAMILY_FAIL`；slack `-0.01` ⇒ `FAIL (min=-0.01 < 0.0)` + 改名；`P11_CFG=c3` ⇒ `SKIP`。
⚠️ 这证明的是**门逻辑/退出码/改名路径**，**不是** Vivado 集成；真正的 A2–G2/ROM 门仍必须在下一构建里跑一次（见 §5）。

---

## 3. 0x32 构建读数

来源：`build0x32/P7B_STDOUT.txt`（行号现读）+ `build0x32/p7b_ku5p_*.rpt` + `gates/sta_0x32_tcb.txt`。

| 项 | 读数 |
|---|---|
| 配置 | `P11_CFG=c4`（dual）/ `P11_HLS_VARIANT=p3_dual_max8` / `P11_HLS_ADV_WND_HITS=3` / 合同 `P11_EXPECTED_CONNS=2`（48KB） |
| BID / 几何 | `BUILD_ID_V bound to: 50 (0x32)` / `SNAP_NW=85`（`:1672-1673`） |
| WNS / TNS | **+0.019 / 0.000**（Design Timing Summary 表值，`:5652`） |
| setup / hold / PW 失败端点 | **0 / 0 / 0**（`:5657/5659/5661`）；`P7B_VERDICT=OK`（`:5786`） |
| WHS | +0.010 |
| TCB stack1 A–F | 0.133 / **0.115** / 0.164 / 0.607 / 0.276 / 0.273；`MIN=0.115`（`:5751-5776`） |
| TCB stack2 A2–G2（**v2 probe**） | A2 **0.047** / B2 0.100 / C2 **0.041** / D2 0.109 / E2 0.234 / F2 0.159 / **G2 0.019**；`MIN=0.019`（= 全局 WNS）；`GATE=PASS`（`gates/sta_0x32_tcb_v2.txt:161`） |
| 独立 probe（routed DCP） | stack1 A–F 逐字同上；`MGR_REL=1.113`、`MGR_UP0=1.083`、`MGR_UP1=1.640`；v2 `TCB_MIN=0.019`、`GATE=PASS` |
| 资源 placed | LUT **122,056** / FF **98,583** / BRAM **109** / URAM **17** / DSP **4**（`p7b_ku5p_util.rpt`） |
| DRC | 0 Error / 0 Critical；57 条 `REQP-1858` advisory（`p7b_ku5p_drc.rpt`） |
| 位流 | **`cee8acfd28511559df49fc0ce60eac293b154c2605f6e3083db3a9397f581950`**，15,431,261 B（`bits/wrapper_p4_0x32.bit`） |
| 门 | ROM 0 命中、blackbox 0、模块解析 C4 预期 0/0/0、TCB gate PASS、timing gate PASS、`BITSTREAM-OK`、`BUILD_EXIT=0` |

时序余量 = **0.019/6.4 = 0.297%**；比 0x31 的 +0.031 小 0.012 ns（ROM 初始化 + 放置变化，方向不利但仍在门内）。**全局 WNS 宿主 = stack2 G2 `u_tcp_tx2/u_fifo_b/rptr[0] → u_tcb2/rcv_wnd[9][0]` +0.019 / 16 级**。**后续任何 RTL 改动必须先跑 `p11_sta_tcb_probe.tcl` v2（A–F + A2–G2，阈值 0.0）**；build tcl 的 `P11_STA_TCB_GATE` 已同步加入 stack2/G2。

---

## 4. 板级验证（0x32）

### 4.1 身份 / 环境

`raw/FINAL_STATE_0x32.txt`：`ID_BID=0x00000032`、`ID_UNIMPL=0xffffffff`、`ID_OK`、`NFF=0`（85 字）、2 BARs、`LnkSta 5GT/s x4`、`0x08=0`、carrier p1=p0=1。 ⚠️ **该件是 2026-10-26 02:58 的旧终态（早于 D9R），且无进程检查**；同会话 C 的 `p11_e05_latency_20261027/raw/E05_FINAL_STATE.txt` 三次收尾均含 `NO_SINK_PROC`，B `raw/POST_SESSION_20261027.txt` 是 **post-session**（非 B 时刻）补充检查（2026-10-27 01:42：BID 0x32 / 0x08=0 / carrier 1/1 / NO_SINK_PROC）。烧录 `BURN_*` 日志在 `burn/`：sha256 前后一致、`End of startup status: HIGH`、`TCPREG_PROG_DONE`、路径匹配、无 ABORT；**无 QSPI 写路径**。

网络环境：`nsa` p1 `192.168.100.1/32 ↔ 192.168.100.2 (J8/ch1)`；`nsb` p0 `192.168.100.101/32 ↔ 192.168.100.4 (J7/ch0)`；`adaptive-rx off, rx-usecs 0`；真实 ARP 先 ping 预热。

### 4.2 慢路径

| 侧 | 读数 | 锚 |
|---|---|---|
| p1→IP_A | ping 3/3，rtt 0.073/0.093/0.117 ms | `raw/PING_UDPECHO_0x32.txt` |
| p0→IP_B | ping 3/3，rtt 0.064/0.066/0.070 ms | `raw/PING_UDPECHO_0x32.txt` |
| UDP echo 8080 | 两口均 `match=True`（8 B） | `raw/PING_UDPECHO_0x32.txt`（`UDP_ECHO_OK` 两行） |
| 板侧 | `W18=0`（purge 0）、`W7=0x15`、`W20=0x68bb9f`、`W83=0x68bb9f`、`W84=0x010585bb`（**D9 前**终态累计；逐跑增量未单独归档；D9 后见 §4.4 `D9_AFTER`） | `raw/FINAL_STATE_0x32.txt:18/31/94/95` |

### 4.3 单口 TCP 下行（每口独立）

| 口 | sink 读数 | 板侧 | 锚 |
|---|---|---|---|
| A = p1/IP_A | **9.395 Gbps**（40,000,005,735 B，34.06 s），`mism=0`，`stall=0`，`--check lane8`，`--core 6`（`PIN_CPU=6`，IO=7/work=0） | 逐跑 W83/W84 **未归档**；终态累计见 §4.2；逐跑判据以 sink 原始日志为准 | `raw/SP3_sink.txt` |
| B = p0/IP_B | **9.431 Gbps**（5,000,002,450 B）与 **9.393 Gbps**（5,000,003,910 B）两跑，`mism=0`，`--core 2`（`PIN_CPU=2`，IO=7/work=4） | 逐跑 W83/W84 **未归档**；终态累计见 §4.2；逐跑判据以 sink 原始日志为准 | `raw/B1.txt` / `raw/B2.txt` |

口径：sink 的 `Mbps` 是**线上帧载荷字节/墙钟**（板→对端方向）；`W51/W52` 是板侧 app TX；`W54=0` 为最终态（早期一次非清洁会话曾读到 6，重烧后未复现，见 §5）。
40GB 轮 = 9.395 Gbps = `9.493 Gbps` 天花板的 **98.97%**；与 P7b S3 单口 9.1–9.3G 同量级。

### 4.4 双口同时

| 臂 | A（p1） | B（p0） | 聚合 | 备注/锚 |
|---|---|---|---|---|
| 同会话 auto-pin（`--core 6`/`--core 2`） | 3.936 Gbps | 3.936 Gbps | 7.87 Gbps | 两进程 **IO 都绑 7、work 都绑 4**（`PIN_THREAD` 逐字）⇒ 台架核冲突 | `raw/D_A.txt` / `raw/D_B.txt` |
| 同会话 taskset 分核（A 2,3；B 0,1；`--no-pin`） | 5.081 Gbps | 7.538 Gbps | **12.62 Gbps** | 两口均 `mism=0`、无 STALL；`UNPINNED=1` + `PIN_ALLOWED_MASK` 见证 | `raw/SW_A.txt` / `raw/SW_B.txt` |
| **IRQ 兄弟核 + taskset 分核**（各 10GB） | **8.798 Gbps**（会话读数） | **8.925 Gbps**（会话读数） | **17.72 Gbps**（host-side sum） | sink A `taskset -c 0,1`、B `-c 2,3`、`--no-pin`；NIC IRQ 41–52 全部移到 CPU `4-7`（兄弟核）；`adaptive-rx off / rx-usecs 0 / tx-usecs 0`；`mism=0`、无 STALL（**均为会话读数**）；板侧 `W83 0x68bb9f→0xd144b8`、`W84 0x010585bb→0x016e0daa`、`W54=0`（**有 raw**）。⚠️ `raw/D9_A.txt`/`D9_B.txt` = **0 B**（03:09 capture failed） | `raw/D9_A.txt`（0 B） / `raw/D9_B.txt`（0 B） / `raw/IRQ_AFF_2x9G.txt` / `raw/D9_AFTER.txt` |
| **D9R raw 重跑**（2026-10-27，各 10GB） | **8.9367 Gbps** | **8.9352 Gbps** | **17.8719 Gbps（host-side sum）** | sink A `taskset -c 0,1`、B `-c 2,3`、`--no-pin`；IRQ 40–52→CPU 4–7；`adaptive-rx off / rx-usecs 0 / tx-usecs 0`；`mism=0`、无 STALL；板侧 `W83 0x7→0x6887fb`（+6,850,548）、`W84 0x3→0x6887e3`（+6,850,528）、`W54=0`、`W21=0`、`W4=0`、`W81=0`、`W82=0`；NIC `P1_RX ≈10.399 GB / 6.8505M pkts`、`P0_RX ≈10.399 GB / 6.8505M pkts` | `raw/D9R_A_sink.txt` / `raw/D9R_B_sink.txt` / `raw/D9R_CONSOLE_*.txt` / `raw/D9R_ENV.txt` / `raw/D9_AFTER.txt` |

**结论口径**：
- 表中“聚合”列一律 = 两个 sink 的 `Mbps` 相加（**host-side sum**），不是板内聚合计数器；板内只有 `W83/W84` 帧数增量。12.62/17.72/17.8719 都是 host-side；D9R 的板侧增量见上表。
- 板侧**每口 egress 9G 级**【已证】（A 40GB 9.395G；B 5GB 9.431/9.393G）。
- **2×9G 同时 = D9R raw【已证·板级】**：IRQ 40–52→CPU 4–7，sink A `taskset -c 0,1`、B `-c 2,3`、`--no-pin`；各 10GB ⇒ **A 8.9367 / B 8.9352 Gbps，聚合 17.8719 Gbps（host-side）**、`mism=0`、无 STALL；板侧 `W83/W84` 各 +6.85M 帧、`W54=0`、`W21=0`、`W4=0`、`W81=0`。旧 D9（8.798/8.925，`D9_A/D9_B` 0 B）保留为历史会话读数，**不再作为判据**。**未达到 2×9.4G 线速**：对端 4 物理核（E3-1275 v3，SMT 8T）+ 两个双线程 sink + NIC IRQ 的 SMT 争用是剩余限制；按 P3 B-P3-7 caveat，**8.9G 是台架可证的下界，不写成“板子上限”**。
- 所有同时臂都未见板侧 `W54` 增长（最终 `W54=0`）；D9R 的 sink `mism=0` 有 raw。

#### 4.4a 非清洁/低率臂登记（**不作为板级判据**）

| 日志 | 现象 | 环境/见证 | 处置 |
|---|---|---|---|
| `raw/BPORT.txt` | p0 40GB 臂：connect OK，0 B，15 s STALL | `PIN_CPU=2`，IO=7/work=4（与同时臂共享核）；此前已有多轮连接/重烧外的残留会话 | **未定位**；不作为板级失败；clean 重烧后 B 两次 9.431/9.393G（`B1/B2`）证明该口数据路正常 |
| `raw/DP_A.txt` | 双口首测 p1 200MB 臂：connect OK，0 B | 两 sink 都自动选 IO=7/work=4（`D_B` 同）；同一对核 | **未定位**；同一轮 B 有数据；后续清洁 A-first 两口均有数据（会话输出未归档，见 §5） |
| `raw/STG_A_B.txt` | 交错 A-first 中 p0 20GB 臂：connect OK，0 B | 两 sink 共享 IO=7/work=4 | **未定位**；B-first 清洁两跑 9.43/9.39G；D9 同时 8.8/8.9G |
| `raw/B_AFTER.txt` | p0 5GB 8.384 Gbps（低于 9.4） | `PIN_CPU=2`，IO=7/work=4；同轮有前序连接 | 台架/核争用下的低率读数；内容 `mism=0`，不作为板级上限 |

> 口径：这些臂的 **connect 成功但 0 B / 低率** 不能简单归因于板或台架；**未定位**。可复现的清洁证据是：`B1/B2`（单口 9.43/9.39G）、`SP3`（40GB 9.395G）、`D9R`（双口 8.9367/8.9352G，raw），均 `mism=0`；旧 `D9`（8.798/8.925，`D9_A/D9_B` 0 B）只作历史，不再作为判据。**不把 0 B 臂写成“板子正常”或“板子故障”**；登记待后续同一环境拆刀（先看 `PIN_THREAD` 是否撞核 + 重烧后单口）。

### 4.5 回归 / 门（构建后跑，非板级）

- **P11 子集 17/17 EXIT=0**（`gates/matrix_p11_subset_0x32.log`）：`p11_c4_elab` / `p11_wpm` / `p11_retx_pool` / `p11_slow_merge2` / `p11_slow_demux2` / `p11_slow_cfg_demux` / `p11_churn` / `p11_c4_wrap` / `p11_negctl_wpm` / `p11_negctl_churn` / `p11_negctl_cfg` / `p11_negctl_slow` / `p11_negctl_p3fix` / `p11_static` / `p11_accmargin` / `p11_buildcfg` / `p11_ext0`。当前 work dir 的 `p11_c4_elab` xelab 日志实测 `BUILD_ID_V=32'b0110010`（0x32），即门编的是本轮 wrapper。
- **其余非 BID 敏感门 22/22 EXIT=0**（`gates/matrix_rest_0x32.log`）：chain/burst200/trunc50/trunc100/halfdrop/txdrop50/gate4096/dupstorm/pcackoob/vlanchain/vlanburst/stallgate/unit_retx/unit_fifo/unit_vlan/unit_uart/p5_wrapper/f3_resync/swc/g2_rx_merge2/g5_tcp_srcip/g6_p11_dual；`p7b_chain`/`biz_win`/`p6e` 等硬编码 0x2D 的 BID 门**未纳入**（read-side 未同步，见 §5.2）。
- **ROM 门负/正控**：`gates/check_hls_rom_gate.txt` = 0x31 6 命中 / 0x32 0 命中、0x31 正读 0 / 0x32 正读 3 / PASS。
- **门逻辑单测**：`gates/gate_unit_test/RESULTS.txt` = ROM 4 臂 + TCB 4 臂 **8/8 PASS**（含缺 pin/负 slack 的位流改名）；**只证门逻辑，不证 Vivado 集成**。清单范围：`gates/SHA256SUMS.txt` 是非递归 10 件（不含 `gate_unit_test/`）；`gates/gate_unit_test/SHA256SUMS.txt` 单独覆盖 4 件；两者各自 `sha256sum -c` 通过。
- **旧 build 脚本 `.dat` 静态门**：`gates/check_build_dat_pattern.py` = `OLD_PATTERN_HITS=none` / `ROBUST_FILES=12` / PASS（含 P7b、10 个 review 列出的旧脚本、`timing_p5.tcl`）；**未逐脚本重建**。
- **读侧 0x32**：`gates/readside_assert_0x32.log` = RC 0 / 0 fail；J6/tcpreg J6 26 档顶格 0x32。

### 4.6 合同 / 隔离

- p1 SYN-ACK：`win 49152`、options `[mss 1460]`、`ip.id=0`（HLS）；p0 同（`win 49152`、`mss 1460`）。⇒ **2×48KB 合同**，**无 wscale**（HLS 设计上移除；见 §5）。
- TX_DIS：`0x08=1` ⇒ p0 carrier 0、p1 保持 1；`0x08=2` ⇒ p1 0、p0 1；`0x08=0` ⇒ 1/1。

---

## 5. 未收口 / 边界（不许当已答）

1. **2×9G 同时**：已证到 **8.798/8.925 Gbps（17.72G 聚合）**（IRQ 兄弟核 + taskset 分核）；**2×9.4G 线速同时未证**（对端 4 物理核/SMT/双线程 sink 限制）。需要第二台对端或更低开销 sink（DPDK）才能判“板子上限”。
2. **读侧 0x32 已同步（2026-10-26）**：`p7b_snap.sh` / `p6e_snap_check.sh` / `p7b_gate4_accept.sh` / `final_state.sh` / `tb_biz_win.v` / `tb_p6e_pcie_*.v` / `gen_inputs.py` 默认值，`j6_r6fix.sh` + `tcpreg_j6.sh` 档表（**26 档，0x32 顶格**）；`apply_readside_bid1c.py --bid 0x32 --assert` **RC=0 / 0 fail**（`gates/readside_assert_0x32.log`）。0x31/0x2D 的历史/轮目录已分类进 `ALLOW`（未改其真值）。`EDITS_32` 是**空阶段**（默认值由本轮受控同步脚本落盘，工具只做 0x32 断言）；不是重放整条 0x1C→0x32 链。
3. **8×12KB 合同**未构建（本 0x32 = 2×48KB）；8 连接数据面 app 未交（现有 `app_pattern` 每口单会话）。
4. **wscale 缺失**：HLS `TCP_MAX_HDR` 注释与 `layer_tcp.cpp:236/313` 明说"不再通告 WS"（P4b-6 死锁前科）；本轮 64KB 窗在 9.4G 下够用（61440 帽 / ~52 µs RTT），但**不是**未来高 RTT 的保障。未改。
5. **W54=6 的早期读数**：首次双口/未清洁会话后出现，重烧 0x32 后最终 `W54=0`，未复现；**未定位**（不写成"已修"）。
6. **0x31 位流**已隔离；0x2F/0x30 位流/构建也受同一 ROM 缺陷影响（0x2F `BUILD_STDOUT` 有 8-4445；0x30 未逐行复核，因原始报告已不可恢复），均禁烧。
7. **0x32 时序余量 0.019 ns（0.297%）**：TCB 族仍是宿主；后续 RTL 改动先跑定向 STA 门。
8. **ping RTT 0.064–0.117 ms（0x32 本件两口实测）**：慢路径/HLS + 对端软件混合，未分离；0x2D 历史上限 0.188 ms 见 `p11_board_p2_0x2D_20261018/README_FOR_TL.md` B-5。这是下一阶段延迟研究的首要测量对象；**xsim 实测**（`p11_hls_latency_20261026/`）HLS 小帧 14–21 µs（HLS-only）、1500B UDP echo 303 µs ⇒ HLS 占比可能 ~8–32%（0x32 64–117 µs 端；188 µs 历史端更低），此前“<5%”撤回；E1 观测构建必须先证实/证伪。

---

## 6. 证据地图

| 件 | 路径 |
|---|---|
| 0x31 synth ROM 物证 | `_proj_10g/notes/p11_fix_0x30_0x31_20261025/build0x31_clean/p7b_ku5p_stdout.txt:1352/1358/1548/1699/1700/1732` |
| 0x31 板级物证 | `_proj_10g/notes/p11_board_p3_0x31_20261026/raw/B0_SNAP.log`、`B0_TCP_UDP_PROBE.log` |
| 0x31 散落 .dat + hash | `p11_fix_0x31_rom_0x32_20261026/evidence/`（`STRAY_DAT_SHA256.txt`） |
| 0x32 构建日志/报告 | `p11_fix_0x31_rom_0x32_20261026/build0x32/`（`P7B_STDOUT.txt`、`p7b_ku5p_timing/util/drc/clkinteract.rpt`、`runme_synth_1.log`、`runme_impl_1.log`） |
| 0x32 TCB 定向 STA（stack1） | `.../gates/sta_0x32_tcb.txt` |
| 0x32 TCB 定向 STA（stack2 v2） | `.../gates/sta_0x32_tcb_v2.txt`（A2–G2，G2=0.019） |
| 0x32 位流 | `.../bits/wrapper_p4_0x32.bit`（sha256 见上；15,431,261 B） |
| 0x31 隔离 | `p11_fix_0x30_0x31_20261025/bits/QUARANTINE_0x31.txt` + `*.HLS_ROM_FAIL` |
| 板级 sink 原始日志 | `p11_board_p3_0x32_20261026/raw/*.txt`（`SP3/B1/B2` = 单口 rate raw；`D9R_A_sink.txt`/`D9R_B_sink.txt` = 双口 rate raw；`D9R_CONSOLE_*.txt`/`D9R_ENV.txt` = 环境/快照；**`D9_A/D9_B` = 0 B，历史 capture failed**；`D9_AFTER` = 旧 D9 板侧增量） |
| P11 回归子集 17 门 | `.../gates/matrix_p11_subset_0x32.log` |
| 其余非 BID 门 22 门 | `.../gates/matrix_rest_0x32.log` |
| 读侧 0x32 断言 | `.../gates/readside_assert_0x32.log`（RC=0） |
| 旧 build `.dat` 静态门 | `.../gates/check_build_dat_pattern.txt`（PASS） |
| ROM 门负/正控 | `.../gates/check_hls_rom_gate.py` + `.txt` |
| 终态/身份 | `.../raw/FINAL_STATE_0x32.txt` |
| 烧录日志 | `.../burn/BURN_0x32_*.txt`、`BURN_stdout_copy_*.txt` |
| HLS 延迟 xsim（追加，研究） | `_proj_10g/notes/p11_hls_latency_20261026/`（`README.md`、`READINGS.txt`、TB/runner、日志、`SHA256SUMS.txt`） |
| 门逻辑单测（追加） | `.../gates/gate_unit_test/RESULTS.txt` + `SHA256SUMS.txt` |
| 终验汇总（追加） | `FINAL_VERIFICATION.txt`（门单测 8/8、HLS 重跑 identical、四份 manifest、147 位流扫描、git 状态） |

---

## 7. 下一棒（顺序）

1. ~~**read-side 0x32 阶段**~~ **已做（2026-10-26）**：默认值/J6 档表/TB 同步，`--bid 0x32 --assert` RC=0（见 §5.2）。
2. **8×12KB 合同构建**（`P11_EXPECTED_CONNS=8`，新 BID，建议 0x33）+ 多连接 app；先跑 `P11_STA_TCB_GATE`。
3. **2×9G 同时**：**D9R raw 8.9367/8.9352G（17.8719G host-side）**，`mism=0`、无 Stall；旧 D9 8.8/8.9G/0 B 只作历史。**2×9.4G** 仍需第二台对端 / DPDK 低开销 sink；按 B-P3-7 口径分开写。
4. **延迟研究**（研究件，见 `_proj_10g/notes/P11_LATENCY_RESEARCH_20261026.md`）：先做 **E1a 板内驻留**（dp_clk 计数器；ICMP/SYN/1500B UDP echo 8080）。**2026-10-26 追加 xsim 实测**（`_proj_10g/notes/p11_hls_latency_20261026/`）：P3 HLS 实际 ~23 拍/B RX、~28–30 拍/B TX（52–54 / 42–44 Mbps），ARP HLS-only **14.1 µs**、UDP 74B **20.6 µs**、**1500B UDP echo 303 µs**（last→last，无适配器/仲裁）⇒ **“HLS 1 B/拍 / 小帧 1–3 µs / 1500B 24 µs”纸面被推翻**；控制面硬件化收益至少 ~14–21 µs（HLS-only 下界），1500B UDP 必须走 fast path/8081 或 RTL echo。cut-through（UDP `csum_en=0` 现状前提不成立）与 TCP echo 缓冲合并（≈3.6 → ≈2.4 µs）均为研究项，**未开工**。
5. **0x31/0x2F/0x30 归档**：ROM 缺陷写入台账；0x30 原始报告不可恢复，保留【未独立复核】。

> Tier B：关键构建/时序数字挂 `build0x32/P7B_STDOUT.txt` 行号与 `gates/sta_0x32_tcb.txt`；板级速率挂 `raw/*` 原始 sink 输出。**尚未归档的会话输出**（首轮 ping/UDP echo/TX_DIS、0x31 的 W18 +1/+2 逐请求、逐跑 W83/W84 增量）在本轮后补/登记；在这些补件落地前，相关条目按“会话读数、无 raw 复查”读，不冒充独立复核。
