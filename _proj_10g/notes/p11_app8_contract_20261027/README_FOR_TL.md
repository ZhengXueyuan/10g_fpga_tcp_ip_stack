# P11-APP8：8×12KB 合同 + 8 连接 app（0x34 候选）

- 日期：2026-10-27
- 基线：HEAD `f986acf1`（E1a-1：0x33 / NW 97 / WNS +0.008）
- 状态词：【设计 v6 已实施】【已证·单元 TB（APP8 app；tcp_echo OCC 20,146 checks + 8 变异全红；F1 slow_cfg；app_ctrl OCC；既有 app_fc 回归）】【synth 检查点已跑（数据见 §3）】【v5 独立审查 = 附条件可实现（`REVIEW_V5.md`，F1–F8 已按 v6 处置）】【**0x34 构建 #2 = TIMING_FAIL（WNS −0.337 / setup 6642；`build_fail1/`）；#3 app8 pblock 实验 = 更差（−0.644 / 13,282；`build_fail2/`，pblock 已默认关闭）；#4 `Congestion_SpreadLogic_high` = 改善但仍 FAIL（−0.205 / 5,162；`build_fail3/`）；#5 `Performance_NetDelay_high`（无 pblock，新输入）构建在飞**】【0x35 未构建】【未上板】

---

## 0. 摘要

| 项 | 结果 | 状态 |
|---|---|---|
| 合同 | `P11_EXPECTED_CONNS 2→8` ⇒ `WQ_CAP_5 = 0x3000`（12KB）；HLS `i_tcp_adv_wnd` 同值 | 【已改】 |
| app | 8 × `app_pattern` + 新 `axis_frame_mux8` / `axis_tid_demux8` / `app_close_arb8` / `app_multi8` | 【已实施】 |
| 零回归 | `P11_APP8` 宏默认关；`app_pattern` 一行未改 | 【已实施】 |
| 单元 TB | A mux / B demux / C close / D 8 实例集成 = **TB_APP8_PASS** | 【已证·单元】 |
| synth 检查点 | **已跑**：总 LUT **142,049 (65.5%)**；`u_app` **15,328 LUT / 5,956 FF**；最差 top-5 **slack −0.706 / 23 级**（`u_tcp_tx2 → u_app2/pw_data`，**port1 现役 app，不是新 8 实例**） | 【已证·synth】 |
| 构建 | 0x34（BID 0x34 / NW 97 不变 / 未实现 0x1B4） | 【未构建】 |
| 板级 | 8 并发连接（新工具 `p7b_tcp_sink_multi`） | 【未上板】 |

---

## 1. 合同（8×12KB）

- `board/wrapper_p4.v:452-454`：`P11_EXPECTED_CONNS=8`；`WIN_POOL_5=0x18000`（96KB）；
  `WQ_CAP_5 = 0x3000`。
- `i_tcp_adv_wnd(WQ_CAP_5)` 已在 `P11_HLS_ADV_WND` 下接线（`wrapper_p4.v:3877-3878`）⇒
  SYN-ACK 通告 12KB，与 fast-path 配额一致。
- `win_pool_mgr.wq_cap` 同源 ⇒ 每连接授予 12KB；`PORT_CAP=96KB` 允许 8+0。
- **边界**（写进板级判据）：
  1. retx 只有 8 槽（`retx_pool_shared.v` 的 `r_conn<8`），与 HLS `MAX_TCP_CONN=8` 的 cid 0..7 对齐；
     第 9 条 SYN 被 HLS 丢弃（`stat_no_slot++`），不是 RST。
  2. 每口 echo 128KB（C4 已有）≥ 96KB 配额，物理余量 26,934 B（`wrapper_p4.v:1653-1662`）。
  3. 12KB/条 ⇒ RTT > 9.83 µs 时单连接贴窗（实测 srtt 16–27 µs ⇒ 单连接 ≈4.9 Gbps 上界）；
     8 连接聚合可打满 10G。**这是产品语义，不是缺陷。**
  4. 一个 bitstream 一个合同：本构建 8×12KB；2×48KB 仍是 0x31/0x33 归档。

---

## 2. 8 连接 app

### 2.1 结构

- `rtl/app_multi8.v`：8 个 **逐字复用**的 `app_pattern`（每个只收自己 `ev_slot` 的事件）
  + 3 个新小模块：
  - `rtl/axis_frame_mux8.v`：8→1 **帧级轮询、非抢占**（一帧 tlast 后才换源）；选择拍不输出，
    每帧 1 拍气泡。
  - `rtl/axis_tid_demux8.v`：1→8 按 `rx_tid` **帧级**分发；`tid>=8` 整帧消费丢弃并计
    `stat_rx_orphan_frames/bytes`（不死锁）。
  - `rtl/app_close_arb8.v`：8 个单拍 `close_req` → pending 位 → 逐拍发出，不丢同拍申请。
- 聚合统计：`stat_tx_bytes/tx_frames/rx_bytes/mismatch` = 8 实例之和（对应快照 W51..W54）。
- 新观测（`arb_frames/orphan/close_pend_max/dbg_inst_mismatch`）**本轮不进快照**（NW 97 不变）。
- **不改 `app_pattern.v`**（零改动；`TX_CONTINUOUS=1` / `TX_SWCLOSE=1`，与现役 port0 同参）。

### 2.2 关键论证

- **不会卡死**：`app_pattern` 的 W3 收尾保证任何已开始帧最终给出 tlast
  （有载荷 ⇒ 当前字带 tlast；无载荷 ⇒ 0 载荷 tlast；`app_pattern.v:912-940`）。
- **帧内 tid 恒定**：仲裁器只在 tlast 后换源；TB 对每个发送帧逐拍断言 tid 不变。
- **RX 不串扰**：按 tid 锁存分发；TB 向 tid2 注错，只有实例 2 的 mismatch 增加。
- **公平**：轮询指针 ⇒ 8 源在 8 帧窗口内各 ≥1；单帧 ≤193 拍 ⇒ 最坏等待 ≈8.6 µs。

### 2.3 单元门（已证）

`tb_app_multi8.v`（`compile/xsim.log`）：**TB_APP8_PASS**，含：

| 段 | 判据 | 结果 |
|---|---|---|
| A | mux 帧级轮询（8 源各 ≥25 帧）、无帧内换 tid、单源空闲不阻塞 | PASS |
| B | demux 8 tid 各 4 beat、无串扰、tid=9 帧丢弃计 1 帧/16 B、后续合法帧继续 | PASS |
| C | 8 个同拍 close 全部发出、每 id 恰 1 次 | PASS |
| D | 8 实例 TX 覆盖 8 tid、帧内 tid 恒定、`tx_frames≈arb_frames`、8 连接 RX 图案 0 失配、注错只影响本连接 | PASS |

- `xvlog`：5 个 RTL 文件 + TB **RC=0、0 warning**。
- wrapper 编译（c4 宏，带/不带 `P11_APP8`）：`xvlog` **RC=0**（`compile/xvlog_wrap*.log`）。

---

## 3. 资源 / 时序

- 实测层次资源（`util_hier.rpt`，由 0x33 routed dcp 生成）：
  `u_app` = **1,388 LUT / 765 FF**；`u_app2` = 956 / 293；`u_app_ctrl` = 3,376 / 3,201。
- 8 实例估算：**≈11.1k LUT / 6.1k FF**；替换现役 1 实例净 **+9.7k LUT / +5.4k FF**
  （占 LUT 4.5%、FF 1.2%）。
- 0x33 WNS **+0.008**（0.125%）⇒ 先跑 synth 检查点：
  `P11_CFG=c4 P11_APP8=1 P11_STA_ONLY=1`（日志 `gates/synth_app8.log`；
  synth 资源 `board/p11_synth_util.rpt`）。
- **synth 结果**（`gates/synth_app8.log`）：总 LUT **142,049 (65.5%)**、FF 108,743、BRAM 84×R36+54×R18、
  URAM 17；`u_app`（app_multi8）= **15,328 LUT / 5,956 FF**（8 实例各 1,588–2,166）。
  最差 top-5 = `u_tcp_tx2/FSM_sequential_rx_state_reg[1]/C → u_app2/pw_data_reg[*]/CE`，
  **slack −0.706 / 23 级** —— **port1 现役 app 族**（0x33 synth top = −0.535 同族），不是新 8 实例。
  ⇒ **synth slack 对 0x33 的 +0.008 路线没有判别力**（0x33 通过臂 synth 也远负），
  时序判决必须走全构建；**构建策略预登记 = `Performance_ExtraTimingOpt`**（0x33 通过臂，作为新输入）。
- **backstop（修正）**：全构建 `P7B_TIMING_GATE` 是唯一判决；synth LUT 142k 已超初版 140k 阈值，
  但器件余量仍足（65.5%）⇒ 不作为停止条件，仅登记。

---

## 4. 构建计划（0x34）

- 命令：`P11_CFG=c4 P11_APP8=1 board/run_build_p7b_ku5p.bat`（`P11_IMPL_STRATEGY` 默认
  Performance_Explore；若门失败，**只允许**按既有"另一输入"策略重跑一次并有记录）。
- 门：`P7B_TIMING_GATE`（WNS>0 / 0/0/0）、`P11_STA_TCB_GATE`、DRC、`P7B_SNAP_TOP5_CDC`
  （槽 39..52 不变）、`P7B_BLACKBOX_LOG_HITS=0`、`P7B_VERDICT=OK`、矩阵 41 门。
- 位流/几何：BID **0x34**，NW **97**，未实现 **0x1B4**（MIR 0x1A4..0x1B0 不变）。
- 新增 RTL 已加入 `import_files` 清单（`build_p7b_ku5p.tcl:233-235`）；
  **缺一行就是 black box 静默失效**（先例：0x24 URAM）。

---

## 5. 板级计划（8 并发）

- 新工具 `_proj_pcie/p7b_biz/p7b_tcp_sink_multi.cpp`（未改现役 sink）：
  8 线程各一条连接，`poll+recv+逐连接图案`，每连接从偏移 0 校验；输出
  `MULTI_CONN ... / MULTI_SUM ...`；`PIN_RULE=none UNPINNED=1`（速率只作形态描述）。
- 判据（**v6.6 为终版**；B5 已按 REVIEW_V5 F3/F4/F9 改写）：
  - B0 **端口映射**：8 连接必须打 **port0 = SFP A(J7) = 对端 nsb `enp1s0f0np0` 192.168.100.4**；
    对端 nsa `enp1s0f1np1` 192.168.100.2 是 port1(J8) 单 app，**不能用于 8 连接测试**。
    `0x08 bit2` 的 RX 停读只门 port0 app。
  - B1 身份：BID 0x34/0x35 / NW 97 / `0x1B4=0xffffffff` / 2 BAR / x4 / carrier 1/1；
  - B2 8/8 建连；第 9 条 SYN 被丢（工具 `--conns 9 --send-conns 0`，9th CONNECT_FAIL，无 RST 风暴）；
  - B3 8/8 `mism=0` / `first=-1` / 字节数对账；
  - B4 板侧 `ΔW52`（app 帧）与 PC 收帧对账 ≤1%；`ΔW83` 同理；
  - B5 **主见证 = 板→对端连续数据帧的 window 字段**（8 个 app 都是 `TX_CONTINUOUS=1`；
        tcpdump 过滤 `syn==0`、停读后、按 4-tuple）：0x34 conn≠发送者 → ~0；
        0x35 → ≈12KB；发送 conn 两臂都 ~0（硬正控）。前件 `W62 ≥ 12,288`；
        不满足 ⇒ 【空判据】。`ss -ti` 只作辅助，不作主判据。
  - B6 A/B = 0x34（OCC=0，全局 occ）vs 0x35（per-conn）；0x33 是 2×48KB 不同合同，不作本 A/B 对照；
        8 连接上行臂：各发 12,288 B 图案，`unsent≈0`、`ΔW53==98304`、`ΔW54=0`、`W62` 峰值登记；
  - B7 跨连接：发送 conn 的 4-tuple 由工具 `lport=` 唯一确定（thread0 ≠ 板侧 cid 必等 0）。
- 工具部署/编译配方：`_proj_10g/notes/p7b_affinity/BUILD.md`（对端 `g++ -O2 -pthread`）。

---

## 6. 风险 / 未定

1. **时序**：8 实例 + mux 在 dp_clk；0x33 余量仅 0.125%。synth 检查点是唯一低成本判据。
2. **RX 反压**：一个实例检查慢会暂停整条流（与单实例语义相同），可能拖慢其它连接；
   板级用 `mism=0` + 逐连接速率观察。
3. **合同语义**：12KB/条 ⇒ 单连接 ~4.9 Gbps 上限；报告不能拿"8 连接聚合 9G"冒充单连接 10G。
4. **retx 8 槽**：仅 cid 0..7；HLS MAX=8 对齐。
5. **工具**：`p7b_tcp_sink_multi` 尚未在 Linux 编译/实跑（本轮只写源码）；板级轮首件事 =
   编译 + `--help` + 单连接 1 条冒烟。

---

## 6.1 独立审查（2026-10-27）

- **裁定原文：不可（当前版本）** —— H1/H2/H3/H6 未闭环前不建议 0x34 构建/上板。
- **已修**：H1 mux 活性（首拍接收前撤 valid ⇒ 释放；TB A3）；H5 单元门配置（`P7B_10G` + D2 反压/ev_down）；
  H3 观测面（**不加字，NW 97**）；H4 零回归口径（只承诺 app 数据通路折叠）。
- **未修（产品级，待用户裁定）**：**H2 = 8×12KB 接收方向被"全口占用"双重扣减**
  （`fq_i = winq_i − occ_global`；`grant = min(wq_cap, pool − occ_global)`）⇒ occ ≥12KB 时 8 条窗全 0；
  **纯下行（occ=0）不受影响**，但"8 连接可接收/双向"不成立。H6 = 板级只测下行，RX/12KB 无判据。
  M5 = 单帧器共享的 TX 队头阻塞（一条零窗可挡其余 7 条）。
- 逐条处置 = `REVIEW_RESPONSE.md`（含 A/B/C 三个选项）。
- **用户 2026-10-27 裁定 = C**：暂停 0x34 构建/烧板，先做 **A（每连接占用）设计 + 独立审查**。
- **v5 独立审查（2026-10-28）= 附条件可实现**：`REVIEW_V5.md`（F1–F20；驳回 v5 直接施工）。
  阻断/高档 = **F1 ADD 期 TCB 窗口仍写死 48KB**（`rtl/slow_cfg_adp.v:91`，8×12KB 合同命题不成立）、
  F2 8 位计数器 vs v4 的 14 位、F3 前件 `W62>12KB` 应为 `≥12,288`、F4 见证未排除 SYN-ACK、
  F5 occ 读口未预流水（0x33 WNS +0.008）、F6 fc 过通告 staleness 未量化（310B 余量不成立）、
  F7/F8 O6 与 cq_full 分支、F10 OCC 宏/构建门。
- **v6 终版 = `DESIGN_OCC_V6.md`**（终版施工依据；`DESIGN_OCC.md` 的 v3–v5 = 历史）：
  F1 slow_cfg `RCV_WND_INIT=WQ_CAP_5`；occ 14 位/内部 18 位/中间和 20 位；
  **occ 读口在 tcp_echo 内寄存 + id**（app_ctrl fq 路径深度不变）；帧首门 `fq<126`；
  板级主见证改为**连续下行数据帧的 window**（探针默认删）；F6 只登记不声称；
  0x34（OCC=0）先构建/归档 → 0x35（OCC=1）。
  当前状态 = **v6 已实施**：
  - RTL：`slow_cfg_adp.RCV_WND_INIT`（F1）、`tcp_echo` per-conn occ（14 位/内部 18/中间和 20；occ 读口寄存+id；帧首门 `fq<126`；`!rback`）、
    `app_ctrl` `occ_fq`+扫描 id 匹配门、wrapper 接线 + `0x08 bit2` RX 双门 + 2FF CDC、build tcl `P11_APP8_OCC` 硬门 + app8 模块解析门。
  - 单元门：`tb_echo_occ` **PASS**（20,146 checks / 133 帧 / 137 beats / gate 13 / drop 3；逐拍 `Σocc==(wptr−rptr)<<3`）；
    8 个变异 **全 RED**；`tb_slow_cfg_init` PASS + F1 变异 RED；`tb_app_ctrl_occ` PASS + 全局 occ 变异 RED；既有 `tb_app_fc` PASS。
  - 台架：`p7b_tcp_sink_multi` 已加 send（`--send-conns/--send-bytes/--send-pattern`）、`SO_RCVBUF` 前移、`sent/unsent/lport` 见证；
    对端 nsa/nsb 已重建（port0=nsb 192.168.100.4 / port1=nsa 192.168.100.2）。
  - 构建：0x34 首跑在 **模块解析门假阳性**（`app_close_arb8=0`：连续 app 的 close_req 恒 0 ⇒ 合法常数折叠）停住；
    门已改为只硬要求 app_multi8/axis_frame_mux8/axis_tid_demux8 ≥1（close arb 只登记）。
    **0x34 构建 #2 = `P7B_VERDICT = TIMING_FAIL`**：WNS **−0.337 / TNS −973.039 / setup 6,642 / WHS +0.008 / hold·PW 0**；
    最差路径 = 既存 DP 族 `u_tcp_tx2/u_fifo_b/rptr → u_tcb2/rcv_nxt_r_reg[9][11]/CE`
    （18 级 / logic 1.690 / **route 4.907 = 74.4%**）；0x33 同族 +0.008 ⇒ 8×app（15,328 LUT）进 DP 后布线拥塞。
    位流已 quarantine（`.TIMING_FAIL`，**禁烧**），全量报告/日志 + SHA256 = `build_fail1/`。
    首个修复实验（**新输入**）= `board/ku5p_p7b_app8.xdc`：`u_app` 组 pblock `SLICE_X0Y0:SLICE_X49Y79`；
    判决仍为全构建时序门；**0x35 不同批、板级 A/B 暂停到 0x34 过门**。
    **pblock 构建 #3 = 实测否定**：WNS **−0.644 / TNS −4357.255 / setup 13,282 / WHS +0.001 / hold·PW 0**
    （对照 #2 = −0.337 / 6,642，**反而更差**）⇒ 隔离 8×app 压小可选布局、且与 DP 争同一区域。
    归档 = `build_fail2/`（FAILURE.md + 全量报告 + SHA256；位流 quarantine）。
    构建脚本已改为 **默认不加该 XDC**（只有 `P11_APP8_PBLOCK=1` 才重新启用，保留为可复跑负实验）。
    **#4 = `Congestion_SpreadLogic_high`（落为 `place_design -directive AltSpreadLogic_high`，无 pblock）
    = 改善但仍 FAIL**：WNS **−0.205 / TNS −506.882 / setup 5,162 / WHS +0.005 / hold·PW 0**；
    最差路径换族 = `u_tcp_tx/bank_rdy_reg[1]_replica → u_app/g_app[4].u_app_i/pw_data_reg[29]/CE`
    （22 级 / logic 2.098 / **route 4.381 = 67.6%**）⇒ 打散布局方向有效（−0.132 ns / −1,480 端点），
    但不足以补 8×app 的边际。归档 = `build_fail3/`（含 routed dcp）。**仍不烧板**。
    **#5 = `Performance_NetDelay_high`（无 pblock，新输入）构建中**（直接压 route）；
    判决仍为全构建时序门；失败则再归档、**仍不烧板**。
  - 结构结论（登记，未实施）：0x33（2 app，同族 +0.008）→ 0x34（9 app，−0.337）的边际 ≈ **0.345 ns / 7 个 app**
    ⇒ **不是"再挤一点余量"能解决**；下一轮首选 = **8×app 组独立 156.25 MHz 域 + AXIS CDC**（把 15,328 LUT
    移出 DP 的 route 竞争），次选 = app 图案逻辑降面积/共享。两条都要独立设计 + 审查，不在本窗口。
  - 下一步 = 0x34 门结果 → 0x35（`P11_APP8_OCC=1`）→ 板级 A/B（B0 端口映射 + B5 连续下行帧 window）。

---

## 7. 证据索引

```
DESIGN.md                       # 设计/判据/backstop
tb_app_multi8.v                 # 单元门 A/B/C/D
compile/xsim.log                # TB_APP8_PASS
compile/xvlog*.log              # 0 warning
compile/compile_rtl.bat / run_tb_app8.bat
util_hier.rpt / util.tcl        # 层次资源实测
gates/synth_app8.log            # synth 检查点（已跑：LUT 142,049 / top −0.706）
REVIEW_RESPONSE.md              # 独立审查逐条处置 + H2 裁定请求
board/p11_synth_util.rpt        # synth 资源（由构建脚本生成）
```
