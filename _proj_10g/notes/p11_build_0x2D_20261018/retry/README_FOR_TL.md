# P11 双 SFP+ · 0x2D 重建轮（retry）交付报告

- 日期：2026-10-18
- 仓库根：`D:\repo\XCKU5PMini\udp_hls_10g`；开工 HEAD = `82e5579d`（与派单一致）
- 唯一构建入口：`cmd //c 'board\run_build_p7b_ku5p.bat'`（每次不同输入各调用一次）
- 纪律：未烧板、未碰 QSPI、未写 git、未改 `D:\repo\perfv`；构建期间未写任何源文件；
  xsim 与 Vivado 未并行；无 PASS/FAIL 裁定。
- 本报告不含"时序已解决"之类措辞；只列读数与事实。

## 0. 一句话（分层口径）

1. **首跑（未改 0x2D 输入）构建完整走完**：F-21 综合后门正读数通过（五槽各 32 cells、
   `hold_b=1 snap_din=0`、`FANOUT_OK`），实现/布线/位流全部产出。
   时序 **WNS -0.013 / WHS +0.008 / setup 失败端点 37 / hold 0 / PW 0**。
2. 因 **WNS<0**，按派单预登记 backstop 阶梯执行（每档 = 新输入）：
   - backstop-1（删 W86/W87）⇒ **WNS -0.089 / TNS -30.513 / 726 个 setup 失败端点**（更差）。
   - backstop-2（再删 W85）⇒ **WNS +0.042 / WHS +0.009 / 三类失败端点 0/0/0**，
     `All user specified timing constraints are met.`。**阶梯在此停止**（未进入第 3/4 档）。
3. 最终位流（backstop-2 输入）：sha256 **`ecef15f2339435edb70727e6a979b363375be2a0f8bd875d352f63a293b0e76f`**，
   15,431,261 B，`SW_CRC=e7658864`，BID `0x2D`。**未烧板、构建完即停。**
4. 首跑 37 个失败端点（200-worst 枚举恰好全捕获）**全部落在既存族**
   `u_tcp_tx/u_fifo_b/* → u_tcb/*`（35 条）+ `u_app_ctrl/o_ev_up → orph_cnt/pw_*`（2 条）；
   backstop-1 报告列出的 10 条违例路径也全部是 `u_fifo_b → u_tcb` 族（726 个端点未逐一枚举）。
   P11 各新定向族余量健康（见 §5 定向 STA）。
   两档 backstop 是不同网表；**删除 W85 与 WNS 由 -0.089 变 +0.042 之间的因果未做拆刀，
   只登记、不归因**（全局 #94）。

## 1. 阶段 0 前置核对

| 项 | 读数 | 结论 |
|---|---|---|
| `git status --porcelain`（开工） | 已跟踪改动 **0** 项；未跟踪残留存在（历史 notes/产物） | 与"无已跟踪改动"相符 |
| vivado/xsim/xelab/xvlog | 构建前全无；每次构建结束确认 | 无并行 |
| `BUILD_ID_V` | `32'h0000002D`（`board/wrapper_p4.v:5271`） | 相符 |
| `SNAP_NW_P6E` | 首跑 88（backstop-2 后 85） | 相符 |
| `SNAP_P7BDP_NW` | 首跑 44（backstop-2 后 41） | 相符 |
| `rx_merge2 .TO_CYCLES` | `4096`（`board/wrapper_p4.v:1188`） | 相符 |
| tcl 9 宏 | `APP_MODE DEV_USP PCIE_OBS DP_156MHZ P7B_10G UDP_TX_OVL TCP_TX_OVL SFP2_MODE_A DUAL_SFP_A`（全 =1） | 相符 |
| F-21 门段 | `board/build_p7b_ku5p.tcl` 含 `get_pins -leaf` 与 `snap_words_r` 白名单 | 相符 |
| HLS 网表 | `HLS_NET_HASH = 452a11226a3ce4b2923ce3b026c39562d655065eb639581e9d2da879d0e64428`（n=175）；`HLS_SRC_HASH = 556ed00c…5218`（n=15） | 与 0x2C 逐字相同 ⇒ 复用，未重跑 csynth；构建日志自己也打印同两值 |

## 2. 构建调用与退出

| # | 输入 | 入口调用 | 退出 | 说明 |
|---|---|---|---|---|
| 1 | 未改 0x2D（NW 88 / P7BDP 44） | `cmd //c 'board\run_build_p7b_ku5p.bat'` | `BUILD_EXIT=0` / `BITSTREAM-OK` | 首跑基数 |
| 2 | backstop-1：删 W86/W87（NW 86 / P7BDP 42） | 同上（新输入） | `BUILD_EXIT=0` / `BITSTREAM-OK` | 阶梯第 1 档 |
| 3 | backstop-2：再删 W85（NW 85 / P7BDP 41） | 同上（新输入） | `BUILD_EXIT=0` / `BITSTREAM-OK` | 阶梯第 2 档，满足预设停止条件即停 |

说明：派单"唯一入口一次"已按"首跑一次"执行；第 2/3 次是 backstop 预登记阶梯要求的
**新输入**（不是同一输入重跑）。三档输入 diff 分别存档：
`BACKSTOP1_INPUT_DIFF.txt`（第 1→2 档）、`BACKSTOP1_2_INPUT_DIFF.txt`（相对 HEAD 的累计 diff）。

## 3. 首跑读数（未改 0x2D 输入；实现完整走完）

| 键 | 值 |
|---|---|
| `P7B_VERDICT` | `OK` |
| `P7B_WNS` / `P7B_WHS` | **-0.013** / **+0.008** |
| WNS/TNS/失败端点（setup） | -0.013 / -0.286 / **37** / 273,415 |
| WHS/失败端点（hold） | +0.008 / **0** |
| WPWS/失败端点（PW） | 0.000 / **0** |
| 全局最差路径 | `u_tcp_tx/u_fifo_b/wptr_reg[1]/C → u_tcb/snd_una_r_reg[3][15]/CE`（20 级，logic 2.000 ns / route 4.276 ns） |
| 37 个失败端点族 | `u_tcp_tx/u_fifo_b/* → u_tcb/*`（35 条）+ `u_app_ctrl/o_ev_up_reg → orph_cnt/pw_*`（2 条） |
| `12-4739` / 隐式网 5 键 / black box / 8-3491 | 全 **0** |
| `P7B_BLACKBOX_LOG_HITS` / `P7B_BLACKBOX_COUNT` | 0 / 0 |
| `P7B_MODULE_RESOLVED` | `rx_merge2=1 tx_demux2=1 maccnt_sync=1` |
| DRC | checks 69；Error 0 / Critical 0 / Warning 5 |
| route | fully routed 146,260；routing errors **0** |
| placed 资源 | LUT 83,122 (38.31%)；FF 78,242 (18.03%)；BRAM 346 (72.08%)；URAM 1；DSP 4；IOB 12；GTYE4 6 |
| F-21 门正读数 | slot 39/40/41/42/43 各 **cells=32**；`SLOTS_OK=5`；`FANOUT tx_p0_frames_r_reg[0]/Q loads=2 hold_b=1 snap_din=0`；`FANOUT_OK` |
| 位流 | sha256 **`b81399d1e4a3f156338f71c8f3953ffdaf9d1b7b34e67c1074e04029626681df`**；15,431,261 B；`SW_CRC=b11503ce` |

首跑器材：`build/READINGS_BID2D.txt`、`build/board_rpt/`、`build/wrapper_p4.bit`、
`build/wrapper_p4_routed.dcp`、`gates/STA_DIRECTED_0x2D_retry.txt`。

## 4. backstop 阶梯（预登记顺序：W86/W87 → W85 → W83/W84 → abort-to-0x2B）

### 4.1 第 1 档：删 W86/W87（NW 88→86，P7BDP 44→42）

- 删除内容：快照 W86/W87 两个字（p7bdp 槽 42/43）、`sat16`、两个 `maccnt_sync` 实例
  （`u_maccnt_ch0rx` / `u_maccnt_ch0tx`）及其源域 tick 计数器与 `*_dp` 镜像线。
- 门同步（属新输入，已写进构建脚本注释）：
  - F-21 门剩余槽集 = **39..41**（位 1248..1343），`P7B_SNAP_TOP5_SLOTS_OK = 3`；
  - 模块解析门：`maccnt_sync` 只作读数打印、不再强制 ≥1（其原因：唯一消费者已删，
    综合会剪除无负载实例；`rx_merge2`/`tx_demux2` 仍强制 ≥1，黑盒判据不变）。
- 读数：`WNS -0.089 / WHS +0.007 / setup 失败端点 726 / TNS -30.513`；
  最差路径仍为既存族 `u_tcp_tx/u_fifo_b/rptr_reg[2]/C → u_tcb/snd_una_r_reg[10][10]/CE`。
  DRC Error 0/Critical 0；route 0 错；LUT 83,691 / FF 77,375。
- 位流：sha256 **`4f87308ec6ba50f9871b05af099af532fac8b44bdfef6fe5a84f9cbc18c7cbee`**，
  15,431,261 B，`SW_CRC=f6f7ac99`。
- 器材：`ladder1/READINGS_LADDER1.txt`、`ladder1/build/`、`ladder1/wrapper_p4.bit`。

### 4.2 第 2 档：再删 W85（NW 86→85，P7BDP 42→41）—— 满足预设停止条件（WNS>0、三类端点 0/0/0），阶梯停止

- 删除内容：快照 W85（classify 总帧数，p7bdp 槽 41）；保留 W83/W84。
- 门同步：F-21 剩余槽集 = **39..40**（位 1248..1311），`P7B_SNAP_TOP5_SLOTS_OK = 2`。
- 读数见 §5；**未进入第 3 档（删 W83/W84）与第 4 档（abort-to-0x2B）**。

## 5. 最终构建读数（backstop-2 = 本轮交付位流）

| 键 | 值 |
|---|---|
| `P7B_VERDICT` | `OK` |
| `BUILD_EXIT` / bat 终判 | 0 / `BITSTREAM-OK` |
| `HLS_SRC_HASH` | `556ed00c4ad6f26f52dee9290f0f813308514189c2505c116d2a38334b945218`（n=15） |
| `HLS_NET_HASH` | `452a11226a3ce4b2923ce3b026c39562d655065eb639581e9d2da879d0e64428`（n=175） |
| `P7B_BLACKBOX_LOG_HITS` | **0** |
| 模块解析 | `rx_merge2=1 tx_demux2=1 maccnt_sync=0`（0 = 预期，非黑盒/漏导入） |
| `P7B_BLACKBOX_COUNT` | **0** |
| `P7B_WNS` / `P7B_WHS` | **+0.042** / **+0.009** |
| setup（WNS/TNS/失败端点/总数） | +0.042 / 0.000 / **0** / 273,248 |
| hold（WHS/失败端点） | +0.009 / **0** |
| PW（WPWS/失败端点） | 0.000 / **0** |
| 时序总判 | `All user specified timing constraints are met.` |
| `12-4739` / `Synth 8-11241` / `undeclared symbol` / `VRFC 10-3091(actual=1)` / `VRFC 10-2989` / `implicitly declared` / `black box` / `8-3491` | 全 **0** |
| DRC | checks 69；Error **0** / Critical **0** / Warning 5；methodology DRC Error 0 |
| route | fully routed 144,324；routing errors **0** |
| clock interaction | `g_hw.clk_out0 → g_hw.clk_out0` = `Timed/Clean`，slack 0.04、0 失败端点；跨钟对全为 `Ignored / Asynchronous Groups`（36 行） |
| placed 资源 | LUT 82,013 (37.80%)；FF 77,361 (17.83%)；BRAM 346 (72.08%)；URAM 1 (1.56%)；DSP 4；IOB 12；GTYE4 6 |
| F-21 正读数 | slot 39 = **32 cells**（位 1248..1279）；slot 40 = **32 cells**（位 1280..1311）；`SLOTS_OK=2`；`FANOUT tx_p0_frames_r_reg[0]/Q loads=2 hold_b=1 snap_din=0`；`FANOUT_OK` |
| 位流 sha256 | **`ecef15f2339435edb70727e6a979b363375be2a0f8bd875d352f63a293b0e76f`** |
| 位流字节数 | **15,431,261** |
| `SW_CRC` | **`e7658864`** |
| #54 归档行 | `ARCHIVE_DONE 20261018_192215 files=19 dir=...\_proj_10g\notes\p7b_build_archive\20261018_192215`（归档到的是 backstop-1 位流/报告）；首跑前的归档 = `ARCHIVE_DONE 20261018_182241 files=19` |

### 5.1 定向 STA（post-route dcp，构建后只读执行）

- 全局 WNS 宿主：`u_tcp_tx/u_fifo_b/wptr_reg[4]/C → u_tcb/snd_nxt_r_reg[15][29]/CE`
  （仍是既存族；`Global slack = +0.042`）。
- `u_tcp_tx/f_lip_reg`：cells=64，slack **+1.837**
- `u_tcp_tx/ctrl_lip_reg`：cells=32，slack **+1.442**
- `cam_rd_dip → u_tcp_tx/*csum*`：**src_cells=0 / NO_PATH**（该网名在本网表中不存在 ⇒ 这一格是
  "未找到"，不是通过；首跑同读数）
- `u_rx_merge`：cells=39，slack **+2.065**
- 每口 arb：`u_tx_udp_arb` +2.211 / `u_tx_udp_arb_p1` +2.270 / `u_tx_arb` +1.551 / `u_tx_arb_p1` +1.649
- `u_hls`：cells=43,526，slack **+0.485**
- `u_snap_p7bdp/hold_b_reg[1248..1311]`：**64 cells**（剩余两字 W83/W84）；
  入族最差 slack **+2.951**
- `maccnt_sync` / `u_maccnt_ch0rx` / `u_maccnt_ch0tx`：**NO_CELL**（随 W86/W87 删除，预期）
- TOP200 清单对上述定向族的命中数全 **0**（编号 #66：清单不是 oracle，只用定向查询）

## 6. 本轮改动的门（新输入，显式登记）

1. **F-21 综合后门槽集**：随 backstop 逐档同步为 39..41 → 39..40。
   不改则门会因已删槽位不存在而假红（派单明确要求同步）。
2. **模块解析门**：`maccnt_sync` 由"必须 ≥1"改为"只读数打印"。
   原因：删 W86/W87 后其唯一消费者消失，综合必然剪除；若仍强制 ≥1，会逼出死逻辑或假红。
   仍强制 `rx_merge2/tx_demux2 ≥1` 且所有实例 `IS_BLACKBOX=0`。恢复 W86/W87 时必须把
   `maccnt_sync ≥1` 条件加回（脚本注释已写）。

未同步项（不在本构建执行面，**上板前必须同步**）：`_proj_10g/p7b_chain/sim/check_snap_top5_wired.py`、
读侧工具/`check_window.py`/`tb_p7b_chain.v` 的几何（现行为 NW 85 / MIR `0x174..0x180` /
UNIMPL `0x184`；这些地址是 `SNAP_LAST_IDX` 推导值，**未板级验证**）。

## 7. 诚实口径与未测项

- 首跑 37 个失败端点（全部枚举）**全部是既存族**（`u_fifo_b → u_tcb` 35 条 + `o_ev_up → orph_cnt` 2 条）；
  backstop-1 的 726 个失败端点未逐一枚举，但报告中列出的 10 条违例路径同为 `u_fifo_b → u_tcb` 族；
  P11 新族的定向 STA 余量都在 +1.4 ns 以上。因此 backstop 删观测字**并未针对真正的最差族**；
  它是按预登记协议执行的实验，不是根因修复。
- backstop-1（-0.089 / 726）与 backstop-2（+0.042 / 0）是**两个不同输入**；
  删除 W85 的"收益"没有拆刀 A/B ⇒ **不归因**（全局 #94：改动的跨网表位移可超历史带）。
- 删除观测字的代价（如实登记）：
  - W85（classify 总帧）不再可读；
  - W86/W87（ch0 FIFO ovf / ch0 MAC TX abort+frames）不再可读 ⇒ P2-2 的 ch0 abort
    "可观测"退回"未观测到"；
  - `maccnt_sync` 模块不在最终网表内。
- `cam_rd_dip` 定向 STA 为 `NO_CELL`（两代位流同）⇒ 该项"未测"，不是通过。
- DRC 仍有 5 条 Warning（Error/Critical 0）；未逐条裁定。
- 未烧板、未做板级身份门（BID `0x2D` / NW 85 / UNIMPL `0x184` 均为纸面推导，未上板核）。
- 构建改写了工作区里被 git 跟踪的 `board/p7b_ku5p_{timing,util,drc,clkinteract}.rpt`
  与 `board/p7b_ku5p_stdout.txt`（构建产物）；未提交、未写 git 历史。
- 源文件改动仅两个：`board/wrapper_p4.v`、`board/build_p7b_ku5p.tcl`（累计 +45/−73 行）。

## 8. 器材地图（retry/）

| 路径 | 内容 |
|---|---|
| `README_FOR_TL.md` | 本报告 |
| `BUILD_CONSOLE.txt` | 首跑控制台（含 ARCHIVE_SKIP/ARCHIVE_DONE、BUILD_EXIT、读数行） |
| `build/READINGS_BID2D.txt` | 首跑全量读数（含时序表、DRC、route、资源、F-21） |
| `build/board_rpt/` | 首跑报告副本（timing summary / util / DRC / route / clock interaction / runme） |
| `build/wrapper_p4.bit` / `.dcp` | 首跑位流与 routed dcp |
| `gates/sta_directed_0x2D_retry.tcl` + `STA_DIRECTED_0x2D_retry.txt` + `TOP200_0x2D_retry.rpt` | 首跑定向 STA 与器材 |
| `BACKSTOP1_INPUT_DIFF.txt` / `BACKSTOP1_2_INPUT_DIFF.txt` | 各档输入 diff（相对 HEAD） |
| `ladder1/` | backstop-1 的控制台、读数、报告副本、位流、routed dcp |
| `ladder2/` | backstop-2（最终）的控制台、读数、报告副本、位流、routed dcp |
| `gates/sta_directed_ladder2.tcl` + `STA_DIRECTED_LADDER2.txt` + `TOP200_LADDER2.rpt` | 最终构建定向 STA 与器材 |
