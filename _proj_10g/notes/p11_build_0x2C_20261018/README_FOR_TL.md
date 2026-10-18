# P11 双 SFP+ · P2-甲 构建轮 0x2C —— 交付报告（README_FOR_TL）

- 日期：2026-10-18
- 仓库根：`D:\repo\XCKU5PMini\udp_hls_10g`，开工 HEAD `bfbceaf6`（与派单一致）
- 权威输入：`_proj_10g/notes/p11_p2a_design_20261018/DESIGN_v2r1.md`（§3.4/§3.5/§5.3/附录 E）· `_proj_10g/notes/p11_p2a_fix_20261018/FIX_REPORT.md`
- 纪律执行：只走 `board/run_build_p7b_ku5p.bat`；未烧板、未碰 QSPI、未上电；未改 RTL/构建脚本/判据；未写 git。
- 本报告**不下 PASS/FAIL 裁定**；"未观测到" ≠ "不存在"；纸面值已标注。

## 0. 一句话（分层口径）

1. **Vivado 构建物理结果：完成且位流已出** —— `P7B_VERDICT = OK`、bit 存在、`WNS +0.011 / WHS +0.010 / 三类失败端点 0/0/0`、DRC 0 Error/0 Critical、route 0 errors、黑盒日志 0、三件新模块解析 1/1/1。
2. **包装 bat 退出码 = 1**，但唯一失败行 `P7B-MODULE-MISSING-OR-BLACKBOX` 命中的是 **Tcl 源码自身的回显行**（`board/p7b_ku5p_stdout.txt:3794`，以 `# ` 开头），不是真实失败 → **构建脚本文本门误报**；我未修改该门。
3. **backstop 未触发**（四个预登记档都与"时序失败"对应；本构建无时序失败）。
4. **新发现（需 TL 裁定）**：`W83..W87` 在网表里**绕过 `u_snap_p7bdp` 的 CDC 束，直接由 dp 域寄存器进 axi 域快照阵列**；设计件要求的 p7bdp 槽 39..43 在布后网表里 **0 个寄存器**（详见 §5）。

## 1. 阶段 0（前置核对）

- `git status --porcelain`：**已跟踪文件零改动**；有 **171 个未跟踪项**（`_tmp_*.py`、sim 临时件、`_proj_10g/notes/p7b_build_archive/…` 等）。与派单描述"工作树应干净（除忽略项）"**不完全相符**：这些是未跟踪残留，不是已跟踪改动；如实登记。
- 无 `vivado/xsim/xelab/xvlog` 进程（构建前后各核一次）。
- 旧 HLS 网表已归档：
  - 目录 `_proj_10g/notes/p11_build_0x2C_20261018/hls_archive_single_ip/`（176 文件，3.5 MB；含 `SHA256SUMS.txt`）
  - **`HLS_OLD_NET_HASH = 2114789ab41ae2a6795e7e23bc17b47c72847a0292c1acfe922a2ff0c9f2b5c5`**（算法 = `build_p7b_ku5p.tcl` 的 `p7b_sha256_set`：ASCII 排序逐文件 sha256 小写拼接后再 sha256）
  - 注意：旧网表 mtime = 2026-09-20 17:53 ⇒ 它是 **P11 之前（bf64c368, P5d）的源**，不只是"少一个 BOARD_IP_DUAL 宏"。
- 只读核对（未改源）：
  - `build_p7b_ku5p.tcl:330` 的 `verilog_define` = **9 宏**：`APP_MODE=1 DEV_USP=1 PCIE_OBS=1 DP_156MHZ=1 P7B_10G=1 UDP_TX_OVL=1 TCP_TX_OVL=1 SFP2_MODE_A=1 DUAL_SFP_A=1` ✓
  - `board/wrapper_p4.v:5279` `BUILD_ID_V = 32'h0000002C` ✓
  - `SNAP_NW_P6E = 88`（`:3886`）✓；`SNAP_P7BDP_NW = 44`（`:3907`）✓
  - `run_build_p7b_ku5p.bat:73-75` 的 `P7B_VERDICT` 文本硬门在位 ✓（其误报见 §2.2）

## 2. 阶段 2（Vivado 构建，一次收口）

### 2.1 命令

```
cmd //c 'board\run_build_p7b_ku5p.bat'
```
控制台输出 = `_proj_10g/notes/p11_build_0x2C_20261018/build/BUILD_CONSOLE.txt`
Vivado 全量 stdout = `board/p7b_ku5p_stdout.txt`（并已复制到轮目录 `build/board_rpt/`）

### 2.2 退出码与硬门

| 项 | 读数 |
|---|---|
| `BUILD_EXIT`（Vivado rc） | **0** |
| bat 终判 | **`BUILD-GATE-FAIL`（rc=1）** |
| 触发行 | `P7B-MODULE-MISSING-OR-BLACKBOX` |
| 命中位置（唯一） | `board/p7b_ku5p_stdout.txt:3794`：`# if {$n1 < 1 \|\| ... } { puts "P7B_MODULE_MISSING_OR_BLACKBOX" ; exit 1 }` —— **Tcl 源码回显行**，不是 tcl 实际打印的判据行 |
| 实际模块解析 | `P7B_MODULE_RESOLVED rx_merge2=1 tx_demux2=1 maccnt_sync=1`；`P7B_BLACKBOX_COUNT 0` |
| 其它失败文本 | `DROPPED-CONSTRAINT-FAIL` / `IMPLICIT-NET-FAIL` / `DRC-KEY-FAIL` / `BUILD-RC-FAIL` / `P7B-VERDICT-FAIL` 均未出现 |

⇒ **这是构建 bat 的文本门缺陷（自匹配源码回显），不是设计/构建失败**。按纪律未改门、未重跑。

### 2.3 读数（全部来自本次构建）

| 键 | 值 |
|---|---|
| `P7B_VERILOG_DEFINE` | 9 宏（同上） |
| `HLS_SRC_HASH` | `556ed00c4ad6f26f52dee9290f0f813308514189c2505c116d2a38334b945218`（n=15；`hls/src/*.cpp|*.h` + `run_hls.tcl`） |
| `HLS_NET_HASH` | `452a11226a3ce4b2923ce3b026c39562d655065eb639581e9d2da879d0e64428`（n=175） |
| `P7B_BLACKBOX_LOG_HITS` | **0** |
| `P7B_MODULE_RESOLVED` | `rx_merge2=1 tx_demux2=1 maccnt_sync=1` |
| `P7B_BLACKBOX_COUNT` | **0** |
| `P7B_WNS` | **+0.011** |
| `P7B_WHS` | **+0.010** |
| `P7B_WPWS`（逐组列表最小） | 0.010 |
| 三类失败端点（WNS-TNS-Failing / WHS-THS-Failing / WPWS-TPWS-Failing） | **0 / 0 / 0**（总端点 274,515；TPWS 总 88,453） |
| 时序总结行 | `All user specified timing constraints are met.`；`Slack (VIOLATED)` 0 行 |
| `12-4739` | **0** |
| 隐式网 5 键 | **`Synth 8-11241`=0 · `undeclared symbol`=0 · `VRFC 10-3091] actual bit length 1 differs from formal bit length`=0 · `VRFC 10-2989`=0 · `implicitly declared`=0** |
| DRC | Checks found 69；**Error 0 / Critical 0** |
| Route | routing errors **0**；fully routed nets 145,574 |
| Clock interaction | 25 行；DP 自对 `g_hw.clk_out0→g_hw.clk_out0` = Clean，WNS 0.01 @ 6.40 ns，0 失败/179,774 端点；跨域对全部按设计记为 Asynchronous Groups / False Path |
| 位流 | `e92f588b58452e58b86bb96df11091eec1f2c72ae346d3740f36c3e6f2b8d6be`；**15,431,261 B**；**`SW_CRC=ccd5f297`** |
| 资源（placed） | LUT **83,165**（38.33%）· FF **77,927**（17.96%）· BRAM **346**（72.08%）· URAM **1**（1.56%）· DSP **4**（0.22%）· GTYE4_CHANNEL 6 / COMMON 2 |
| 资源（synth） | LUT 67,474 · FF 56,200 · BRAM 310 · URAM 1 · DSP 4 |

与上一代 0x2B 对照（同流程，仅并列、不裁定）：

| 项 | 0x2B | 0x2C | 差 |
|---|---|---|---|
| WNS | +0.048 | +0.011 | −0.037 |
| WHS | +0.010 | +0.010 | 0 |
| LUT (placed) | 80,024 | 83,165 | +3,141 |
| FF (placed) | 76,888 | 77,927 | +1,039 |
| BRAM | 348 | 346 | −2 |
| URAM / DSP | 1 / 4 | 1 / 4 | 0 / 0 |
| SW_CRC | f65e8188 | ccd5f297 | 换代 |

（0x2B 的 WPWS 总结值也是 0.000、0 失败端点 ⇒ 本代同前代，不是新变化。）

### 2.4 归档

- **#54 自动归档：成功** —— `ARCHIVE_SHA256_OK` + `ARCHIVE_DONE 20261018_120438 files=19`，目录 `_proj_10g/notes/p7b_build_archive/20261018_120438/`。其中 `wrapper_p4.bit` sha256 = `7dd2ea3316dbed3915239d39391c90765ad6b7c8a9d472fa1c8fecca54ba2c23`，与 `p9_build_0x2B_20261018/build/BIT_SHA256_BID2B.txt` 逐字相同 ⇒ 归档的确实是**前代 0x2B**。
- 本代产物（因脚本的归档发生在构建前，构建后已手工复制到轮目录）：
  - `build/wrapper_p4.bit` · `build/wrapper_p4_routed.dcp`
  - `build/BIT_SHA256_BID2C.txt`
  - `build/board_rpt/`（15 件：impl/synth 报告 + board 报告 + xdma cfg dump）
  - `build/READINGS_BID2C.txt`（机读汇总）
- **构建后的 git 状态（如实登记）**：5 个**已被跟踪的 board/ 报告/日志件**被构建脚本改写 —— `board/p7b_ku5p_{clkinteract,drc,stdout,timing,util}`（4×`.rpt` + 1×`.txt`）。这是 `run_build_p7b_ku5p.bat` 的设计行为（Vivado 每次写新报告），**不是** RTL/tcl/bat 源改动：`board/*.v`、`board/*.tcl`、`board/*.bat`、`rtl/`、`hls/src/` 全部零改动。`hls/slowstack_prj/` 网表是 ignored 产物。

## 3. 阶段 1（HLS 双 IP 重综合）

命令：`cmd //c 'hls\run_hls.bat'` → `vitis-run --mode hls --tcl ... run_hls.tcl`（`run_hls.tcl:10` 已带 `-DBOARD_IP_DUAL=1`）。
日志：`_proj_10g/notes/p11_build_0x2C_20261018/hls/run_hls_0x2C.log`（另存 `hls_run_tcl.log`）。

| 项 | 读数 |
|---|---|
| csynth 状态 | exit 0；`===== CSYNTH DONE =====`；**ERROR/Critical 0 条**；耗时 121.997 s |
| 资源估计 | BRAM_18K **43**（4%）· DSP **4** · FF **22,571**（5%）· LUT **50,341**（24%）· URAM **0** |
| 时序估计 | Target 8.00 ns / Estimated 6.373 ns / Uncertainty 2.16 ns ⇒ Slack **−0.53**（与改前基线同值；只是 HLS 125MHz 估计，不是 Vivado 签核） |
| 新网表 | 175 文件；**`HLS_NEW_NET_HASH = 452a11226a3ce4b2923ce3b026c39562d655065eb639581e9d2da879d0e64428`**；清单 `hls/NEW_NETLIST_FILES.txt` + `NEW_NETLIST_SHA256SUMS.txt` |

Latency / Interval（全局铁律口径）：
- `udp_echo` 顶层**无 `ap_start/ap_done`**（自由运行，与历史一致）⇒ 顶层 Latency/Interval 在 csynth 报告里是 `? / ?`，**没有可读的 body II**。本构建不是靠顶层 II 判定的设计。
- 循环级：**68 个 II=1**；**9 个 II>1**：`tcp_parse_opts_LOOP_404`(3) · `tcp_send_LOOP_112`(3) · `icmp_rx_LOOP_112`(3) · `udp_tx_LOOP_112`(3) · `tcp_send_1_LOOP_112`(3) · `l1_insert_LOOP_89`(2) · `stats_report_LOOP_31`(4) · `stats_report_..._LOOP_29`(2) · `arp_dump_LOOP_223`(49)。
- 与改前备份日志 `hls/logs/hls_run_tcl_23312.backup.log` 对照：**同一族 II 值相同**；loop 编号后缀因双 IP 提交改了 .cpp 行号而漂移。唯一结构差异 = 旧网表里的 `tcp_active_tick` 独立模块本轮被内联掉（函数仍在源码里，见 `hls/src/layer_tcp.cpp:459`）。

双 IP 语义核验（派单第 5 步）：
- IP_B `192.168.100.4 = 0xC0A86404 = 3232261124`：**新网表 6 个模块命中**（`udp_echo_{arp_rx,icmp_rx,igmp_rx,ip_rx,tcp_rx,udp_tx}_process.v`）；**旧网表 0 命中**。
- IP_A `192.168.100.2 = 0xC0A86402 = 3232261122`：新旧都有；新 `udp_echo_ip_rx_process.v:1163/1167` 同时比较 IP_B 与 IP_A。
- `udp_echo` 顶层端口表新旧**逐字相同**（设计 H-1：不新增顶层端口）；内部 `ip_rx_process` 新增 32 位 dst_ip 返回（`ap_return_2` 16→32 位，新增 `ap_return_4`）。
- 新网表 175 文件 vs 旧 176：除循环名换号外，`tcp_conn_*` RAM 从顶层移入 `udp_echo_tcp_rx_process_*`、`tcp_active_tick` 消失 —— 与已提交的双 IP 源变更（967e974e，9 个 HLS 源文件 +389/−32）一致；**无未提交 HLS 源改动**。

## 4. 定向 STA（只读 post-route dcp；`-from`/`-to` 定向，不靠 top-200）

原件：`gates/STA_DIRECTED_0x2C.txt`、`gates/STA_DIRECTED_FIX_0x2C.txt`、`gates/SNAP_PROBE_0x2C.txt`、`gates/FANOUT_PROBE_0x2C.txt`、`gates/BITMAP_PROBE_0x2C.txt`、`gates/CAM_PROBE_0x2C.txt`、`gates/CAM2_PROBE_0x2C.txt`。

### 4.1 全局与 DP 前 10

- 全局 WNS = **+0.011**：`u_app_udp/u_txf/dout_reg[65]/C → u_udp_tx/ip_csum_r_reg[1][8]/D` —— **老族**（历史就是 `app_udp/txf/dout → udp_tx/ip_csum_r`），不是本轮新件。
- DP 前 10 = 6 条该老族（0.011–0.036）+ 4 条 `u_tcp_tx/u_ackq/rptr_reg[0] → u_tcb/rcv_wnd_r_reg[*]`（0.029–0.032，旧 TCB 更新族）。
- **所有新件族都没有进 DP 前 10 / 全局 WNS 宿主。**

### 4.2 定向族（slack 单位 ns；FROM = 从该族出发的最差 setup；TO = 进入该族的最差）

| 族 | FROM | TO |
|---|---|---|
| `u_tcp_tx/f_lip_reg` | 1.620 | 0.326（`u_clkgen/rel_sr_reg[3] → CLR`，异步复位族） |
| `u_tcp_tx/ctrl_lip_reg` | 1.452 | 0.408（同上 CLR） |
| `u_rx_merge/*` | 2.677 | 2.986 |
| `u_tx_udp_arb/*` | 1.103 | 0.427（CLR） |
| `u_tx_udp_arb_p1/*` | 1.141 | 0.431（CLR） |
| `u_tx_arb/*` | 0.997 | 0.451（CLR） |
| `u_tx_arb_p1/*` | 0.858 | 0.440（CLR） |
| `u_hls/*` | 0.562 | 0.303（CLR） |
| `u_maccnt_ch0rx/*` | 4.820 | 0.202（CLR） |
| `u_maccnt_ch0tx/*` | 4.297 | 0.204（CLR） |
| `cam_rd_dip` 网 → `u_tcp_tx/*csum*` | 通过网 worst 0.581（`u_tcp_tx/u_ackq/rptr_reg[0] → u_tcp_tx/u_csum/acc_reg[31]`）；进入 csum 最差 0.177（`u_tcp_tx/nbeats_reg[4] → u_csum/acc_reg[31]`）；32 条 net 全部只落在 `u_tcp_tx` 下 | — |
| `u_snap_p7bdp/hold_b_reg[1248..1407]` | **0 个 cell**（见 §5） | — |

top-200 扫描：`f_lip/ctrl_lip/cam_rd_dip/u_rx_merge/u_tx_udp_arb/u_tx_arb/u_snap_p7bdp/u_hls/u_maccnt` **全部 0 命中**（与它们的 FROM slack ≥0.562 一致）。

## 5. ⚠️ 新发现：W83..W87 绕过 snap_cdc（请 TL 裁定）

**现象（网表实测）**：
- `u_snap_p7bdp/hold_b_reg` 布后共 **982** 个寄存器，**最大位号 1239**；按 32 位槽统计：**槽 39..43（W83..W87）各 = 0 个寄存器**（其余槽 0..38 与设计相符）。
- `tx_p0_frames_r_reg[0]/Q`（dp 域，W83 源）的全部扇出 = 自身计数器反馈 LUT + **`u_pcie_regs/snap_din[2422]`**；无任何 `u_snap_p7bdp/hold_b_reg` 负载。
- `snap_words_r_reg[2656]/D`（W83 bit0，pcie 域）= `net u_pcie_regs/snap_din[2422]` ← `tx_p0_frames_r_reg[0]/Q`；W84..W87 同形（2688→2454、2720→2486、2752→2518、2784→2550，常量偏移恒 −234）。
- `u_maccnt_ch0tx/dst_val_reg[0]` 也只进 `u_maccnt_ch0tx/snap_words_r[2784]_i_1`（打包 LUT），不经 `hold_b`。

**源码定位（`board/wrapper_p4.v`，HEAD 现状）**：
- `:4830-4855`：`p7bdp_din[39*32 +: 32] = w83_dp … [43*32] = w87_dp`（接了，但下游不用）。
- `:5034-5049`：`w83_snap … w87_snap` **直接 `assign = w8x_dp`**（dp 域寄存器输出）。
- `:5051-5056`：`snap_dout_all` 顶部 5 项用的是 `w8x_snap`（= dp 域直连），不是 `p7bdp_dout[39..43]`。
- 结果：`u_snap_p7bdp` 的槽 39..43 是**死逻辑**（输出无人读 ⇒ hold_b 位被优化），W83..W87 以**裸多比特异步采样**方式进 `pcie_axi_aclk` 域的 `snap_words_r`。

**与设计件的冲突**：DESIGN_v2r1 §3.4/§3.5 明确 `SNAP_P7BDP_NW 39→44`、槽 39..43 = W83..W87，并且 `snap_cdc` 的前提是"多比特不能裸同步"（`rtl/snap_cdc.v` 头注释硬契约）。当前实现与该条不符。

**性质与边界（不夸大）**：
- 这不是时序失败：两域在 XDC 里是 Asynchronous Groups，所以 WNS/端点 0 都不受影响。
- 风险在**可观测性**：计数器是自由运行的多比特量，裸采样可能读到"从未存在过的中间值"（位混），破坏"同代相干快照"的承诺；后续 B-2/B-5 用 W83/W84/W86/W87 做对账时，单次读数可能出现不可解释的跳变。
- **未做**：未改 RTL、未做板上读数、未做 CDC 仿真；"板级是否真的读出位混"**未观测**（≠ 不存在）。

**若 TL 认为需要修**：最小改法 = `snap_dout_all` 顶部 5 项改用 `p7bdp_dout[43..39]`（源码里 `p7bdp_din` 已经接好），使 `hold_b` 槽 39..43 复活；这属于 RTL 改动，需另起一轮（本轮的"不改源"纪律未授权）。回退/裁定量 = 0 个新字（W83..W87 仍可从 axi 域读到值，只是不相干）。

## 6. backstop 是否触发

**未触发。** 预登记四档（W86/W87 → W85 → W83/W84 → abort-to-0x2B）针对的是时序/资源失败；本次构建：
- `WNS = +0.011 > 0`、`WHS = +0.010 > 0`、三类失败端点 **0/0/0**、DRC 0 Error/Critical、route 0 errors；
- 唯一 `BUILD-GATE-FAIL` 是**门自身误报**（§2.2），与设计/时序无关。
⇒ 按预登记准则没有理由进入"删观测字"的阶梯；也**没有**重跑构建（避免"重跑到过为止"）。

## 7. 未测 / 未判定（不许当已答）

- **板级全部未测**：未烧 0x2C、未碰 QSPI、未上电；身份门（`0x04=0x2C` / 88 字 / `0x190`）/ B-0..B-8 / W83..W87 读数 **全部未跑**。
- HLS **csim 未跑**（本轮只 csynth；上次 csim 状态见 FIX_REPORT F-17）。
- W83..W87 的 CDC 后果（是否读出位混）**未观测**；板上实际表现未知。
- `P7B_WPWS` 总结列 = 0.000（0 失败端点）与 0x2B 相同，**未深究其语义**（同代同值，不是本轮新变化）。
- 构建 bat 的文本门缺陷**未修**（纪律：不改判据）；下一轮若仍用同一 bat，会**再次**误报。
- 本轮没有做 `D:\repo\perfv` 相关任何操作；没有写 git。

## 8. 证据文件索引（轮目录 `_proj_10g/notes/p11_build_0x2C_20261018/`）

- `hls/`：`run_hls_0x2C.log` · `hls_run_tcl.log` · `udp_echo_csynth.rpt` · `csynth.rpt` · `csynth.xml` · `csynth_design_size.rpt` · `HLS_READINGS.txt` · `NEW_NETLIST_FILES.txt` · `NEW_NETLIST_SHA256SUMS.txt`
- `hls_archive_single_ip/`：旧单 IP 网表 176 文件 + `SHA256SUMS.txt`；`HLS_OLD_NET_HASH.txt`
- `build/`：`BUILD_CONSOLE.txt` · `READINGS_BID2C.txt` · `BIT_SHA256_BID2C.txt` · `wrapper_p4.bit` · `wrapper_p4_routed.dcp` · `board_rpt/`（15 件） · `_collect_build_0x2C.py`
- `gates/`：`STA_DIRECTED_0x2C.txt` · `STA_DIRECTED_FIX_0x2C.txt` · `SNAP_PROBE_0x2C.txt` · `FANOUT_PROBE_0x2C.txt` · `BITMAP_PROBE_0x2C.txt` · `CAM_PROBE_0x2C.txt` · `CAM2_PROBE_0x2C.txt` · 各 `STA*/SNAP*/FANOUT*/BITMAP*/CAM*_CONSOLE_0x2C.txt` · 对应 `*.tcl`/`run_*.bat` · `TOP200_0x2C.rpt` / `TOP200_0x2C_fix.rpt`
