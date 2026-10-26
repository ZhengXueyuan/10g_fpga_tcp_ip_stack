# P11 E1a-1：DP fast-path TX 逐帧延迟（0x33 候选）

- 日期：2026-10-27（设计/审查/实施/单元门/构建/板级/矩阵；见 §4/§5/§6）
- 板：P11 **0x33 现役**（NW 97 / BID `0x33` / 未实现 `0x1B4`；`0x08=0` / carrier 1/1）
- 状态词：【设计】【已证·单元】【已证·静态】【已证·构建】【已证·板级】【已证·矩阵】

---

## 0. 摘要

| 项 | 读数/结论 | 状态 |
|---|---|---|
| E1 的空白 | E1 只测 HLS 控制面；A 口 fast-path 单帧延迟未测 | 引用 E1 |
| E1a-1 指标 | `L = T_DONE 接受拍 − 帧首字呈现拍`（port0 `u_tcp_tx`；含窗口/启动门/帧器/tx_arb 气泡/txcdc 反压） | 【设计】 |
| 实现 | `tcp_tx_frame` E1A_EN + OVL `g_e1a`；12 字 → W85..W96；NW 97；BID 0x33 | 【已实施】 |
| 独立审查 | 高 5 / 中 11 / 低若干；处置见 `REVIEW_RESPONSE.md` | 【已审】 |
| 单元门 | A/B/C/D 四场景 `TB_E1A_PASS`（200 拍等待、无等待、控制帧、撤字重呈交） | 【已证·单元】 |
| 静态门 | `check_window.py` 122/0；`check_snap_top5_wired.py` PASS | 【已证·静态】 |
| 构建 | **构建 1 WNS −0.023 / setup 145 ⇒ TIMING_FAIL（禁烧，`build_fail1/`）**；**构建 2（ExtraTimingOpt）WNS +0.008 / 0/0/0 / TCB 0.223 / VERDICT OK**；位流 `4e41a064…d0550` | 【已证·构建】 |
| 板级 | **已测**：身份全中；空载负对照 0/0/0；10×10GB（68.49M 帧）p50/p99 全落 bin6（2.46–3.27 µs）；`hist==ΔW52` 10/10；`mism=0`；max 受会话首帧污染（1.2 s） | 【已证·板级】 |
| 矩阵 | 首轮 40/41（唯一红 = `biz_win` TB 期望仍 0x32）；修 `tb_biz_win.v:158`→0x33 后**全矩阵复跑 41/41 EXIT=0** | 【已证·矩阵】 |

---

## 1. 指标与边界（逐字）

```
t_present  = recv_first && s_axis_tvalid && !start_data   （不要求 RX_IDLE；
             RX_RING/RX_FIN/RX_FLUSH 期间 app 首字的等待也计入）
t_done     = tx_state==T_DONE && (!m_axis_tvalid || m_axis_tready) && !tx_is_ctrl
L          = t_done − t_present   （cycle @156.25MHz；1 cyc = 6.4ns）
```

- 只统计 `f_is_app[tx_bank]=1` 的 app 数据帧；控制帧、ring 重放帧、中止帧不计。
- 34 位时间戳 `{ts_wrap,ts_ctr}`；`lat_ok=0`（L ≥27.487 s，零窗 persist）的帧跳过，不写错值。
- 不含：app 首字前生成、txcdc 之后 FE/MAC/PCS/PHY、重传帧。
- 桶：0:0-127 / 1:128-159 / 2:160-191 / **3:192-223（1460B 服务 ~193）** / 4:224-255 /
  5:256-383 / 6:384-511 / 7:512-1023 / 8:1024-4095 / 9:≥4096。
- `W96 max_total` = **复位以来全局 max**，不是单窗 max；每会话首帧可能被 `acks_ok` 等待污染。
- 扫描伪拍（H-1/H-2）：只影响等窗分量 ≤1/16；E1a-1 不新增 polluted 计数器，报下界。

---

## 2. 改动清单

- `rtl/tcp_tx_frame.v`：参数 `E1A_EN`（默认 0）、三输出、OVL `g_e1a`、serial tie-off。
- `board/wrapper_p4.v`：`.E1A_EN(P11_DUAL_DEF)`、`SNAP_P7BDP_NW 41→53`、`SNAP_NW_P6E 85→97`、
  W85..W96、BID 0x33。
- `board/build_p7b_ku5p.tcl`：`P7B_SNAP_TOP5_CDC` 槽集 39..52（E1A 构建=14 槽；非 E1A c1/c3 只查 39..40，避免常量槽假红）。
- `_proj_10g/notes/p7b_biz_win/check_window.py` + `tb_biz_win.v` / `run_tb_biz_win.bat`：
  E1a 槽/地址/NW 97。
- `_proj_10g/p7b_chain/sim/check_snap_top5_wired.py` + `tb_p7b_chain.v`：TOPN=14、0x1A4/0x1B4。
- `_proj_pcie/p7b_biz/p7b_snap.sh`：W85..W96 标签。
- 本目录：`DESIGN.md` · `REVIEW_RESPONSE.md` · `tb_e1a_draft.v` · `e1a_latency.sh` · `e1a_metrics.py`。

---

## 3. 单元门（已证）

`tb_e1a_draft.v`（`E1A_EN=1`、`TCP_TX_OVL`、静态 rb/CAM、`win_open` 直驱）：
- A：首字 hold 200 拍 ⇒ hist_total=1、sum=max=219、bin3=1；
- B：无等待帧 ⇒ hist_total=2、sum 236、max 不变；
- C：纯 ACK ⇒ hist_total 不变、stat_ack=1；
- D：先呈现 100 拍→撤字 10 拍→重呈交 ⇒ hist_total=3、sum delta 19、max 不变（H-1）。
- M-1 同拍断言 `start_data && done_ev` = 0。
- 运行件：`compile/xsim.log`（`TB_E1A_PASS`；`XSIM_RC=0`）。
- 边界：TB 用静态 `win_open`，不覆盖 tcb/scan/ring；这些由 RTL 结构论证 + 板级正对照覆盖。

---

## 4. 静态门（已证）

- `check_window.py`：**PASS=122 / FAIL=0 / INFO=1**；NW 97、p7bdp 53、W85..W96 din 映射、
  `snap_dout_all` 顶端 31 项、未实现 0x1B4；`--mutate drop/swap/declpatho` 三个负控 RC=1。
- `check_snap_top5_wired.py`：**SNAP_TOP5_STATIC_PASS**（TOPN 14 + E1a din 3b）。
- `xvlog`：`tcp_tx_frame`（E1A_EN=0 默认）与 wrapper（c4 宏）均 `RC=0`。
- **41 门矩阵**（`sim/p4gates/run_matrix_p4dfix.bat`，日志 `gates/matrix_e1a.log`）：
  **首轮全跑 40/41 EXIT=0**，唯一红 = **`biz_win` EXIT=1**，原因是 **TB 期望陈旧**：
  `tb_biz_win.v:158` 仍 `chk("1b BUILD_ID", 32'h00000032)`，而 DUT/参数已是 0x33
  （同门内 `check_window.py` 122/0 全过）⇒ **测试期望缺陷，不是 RTL/构建失败**。
  把该行改为 `32'h00000033` 后单门复跑：**`BIZ_WIN_CHECK_PASS` / `TB_BIZ_WIN_PASS`（40 项）/ RC=0**
  （`gates/biz_win_rerun.log`）；随后**全矩阵复跑 = 41/41 EXIT=0、`MATRIX_FINAL_RC=0`**
  （`gates/matrix_e1a_final.log`）⇒ **矩阵最终口径 = 41/41（单次全绿）**。
  ⚠️ **顺序偏离（如实登记）**：烧板发生在全矩阵之前（§6.1-5 要求矩阵先过）；
  首轮矩阵在烧板后 ~40 min 完成，修复的只是 TB 期望，**未改 RTL/位流**。

---

## 5. 构建（构建 2 = PASS）

| 项 | 值 |
|---|---|
| 命令 | `P11_CFG=c4 board/run_build_p7b_ku5p.bat` |
| 配置 | **c4 / p3_dual_max8 / 合同 2 / BID 0x33 / NW 97**（构建日志 `P11_CFG_INPUT = c4`） |
| 综合 | `synth_design completed successfully`；`P7B_BLACKBOX_LOG_HITS=0` |
| 快照结构门 | `P7B_SNAP_TOP5_E1A_ON=1 (slots 39..52)`；槽 39..52 各 **32 cells**；`SLOTS_OK=14`；`FANOUT hold_b=1 snap_din=0` |
| STA 预检（synth） | `MGR_REL=2.345 / MGR_UP0=2.936 / MGR_UP1=3.139`；top5 估计 `-0.535`（`u_tcp_tx2/u_ackq/wptr → u_app2/bcnt`，**port1 既存路径，不是 E1a**） |
| **构建 1（Performance_Explore）** | **WNS −0.023 / WHS +0.004 / WPWS 0.010**；**setup 145 / hold 0 / PW 0** ⇒ `TIMING_GATE=FAIL`；位流已改名 `wrapper_p4.bit.TIMING_FAIL`（**禁烧**）。最差路径 = `u_tcp_tx/FSM_sequential_rx_state_reg[0]_replica → u_app/tx_lfsr_reg[61]/D`（21 级，route 4.302 ns）—— **不是 E1a hist 路径**，是放置/布线位移暴露的既存路径。报告归档 `build_fail1/` |
| **构建 2（Performance_ExtraTimingOpt）** | **WNS +0.008 / WHS +0.010 / WPWS 0.000（0 failing）**；**setup/hold/PW 失败端点 0/0/0**；`All user specified timing constraints are met`；`P7B_TIMING_GATE = PASS`。仅改 implementation strategy（新输入，不是“重跑到过”）；其余 RTL/宏/BID 不变 |
| WNS 宿主 | `u_tcp_tx2/u_fifo_b/rptr_reg[3]/C → u_retx_pool/g_slot[4].u_ram/ra_e_r_reg[0]/CE`（DP 域，15 级，route 4.528 ns / 74.9%）—— **port2 TX 既存族，不是 E1a hist**（`build2/wrapper_p4_timing_summary_routed.rpt:14031-14043`） |
| TCB stack1/stack2 min | **A..G2 = 0.283/0.308/0.234/0.250/0.267/0.223/0.340/0.254/0.375/0.451/0.294/0.292/0.286**；**min 0.223 ≥ 0** ⇒ `P11_STA_TCB_GATE = PASS` |
| 资源（placed） | LUT **121,295 (55.91%)** / FF **100,050 (23.06%)** / BRAM **109 (22.71%)** / URAM **17 (26.56%)** / DSP **4 (0.22%)** |
| DRC | **0 Error / 0 Critical / 85 Warning**（`build2/p7b_ku5p_drc.rpt`） |
| 位流 | `bits/wrapper_p4_0x33.bit`，15,431,261 B，sha256 **`4e41a064d4b599b7f09902dc4c0435f50e6c29c660206ac03fe90b44329d0550`** |
| 门 | ROM/blackbox `P7B_BLACKBOX_LOG_HITS=0`；timing `PASS`；TCB `PASS`；top5 **14 槽 / SLOTS_OK=14**；`P7B_BIT_EXISTS=1`；`P7B_VERDICT=OK` |
| 结论 | **构建门通过，可烧**（WNS>0、0 失败端点、TCB≥0）。⚠️ **WNS 仅 +0.008（0.125%）⇒ 后续任何 RTL 改动必须重新定向 STA + 一次构建收口** |

---

## 6. 板级（已测）

身份（BURN log）：`ID_MAGIC 0x50360001` / **BID 0x33** / marker `0xdeadbeef` /
`0x1B4=0xffffffff` / **97 字窗口 NFF=0** / 2 BARs / `LnkSta x4` / carrier 1/1 / `0x08=0`。
烧录：JTAG **1 MHz**，`End of startup status: HIGH`，sha256 与 `bits/SHA256.txt` 逐字相同；**QSPI 零写**。
空载负对照（2 s，无流量）：**Δhist=0 / Δsum=0 / Δmax=0**（同窗 `W43`/`W65` 各 +328,152,868 ⇒ 计数器在跑，只是不计数）。

负载：10 跑 × 10 GB 单连接 A 口下行（THREADED sink、`--check lane8`、rcvbuf 1 MB、IRQ 4–7、
coalescing off；`taskset -c 0,1` + `--no-pin` ⇒ 日志 `UNPINNED=1`，**无 `PIN_CPU=` 见证**，
因此速率只作形态分类、不作速率判据）。每跑 PRE/MID1/POST 三快照。

| run | state | sink Gbps | frames | ΔW14 | gap | meanX µs | p50 | p99 | tail% (≥3.28 µs) | max cyc |
|---|---|---:|---:|---:|---:|---:|---|---|---:|---:|
| R1 | fast | 9.4456 | 6,849,365 | 6,849,394 | 29 | 2.47 | bin6 2.46–3.27 µs | bin6 2.46–3.27 µs | 0.007 | 31,932 |
| R2 | fast | 9.4423 | 6,849,364 | 6,849,393 | 29 | 2.47 | bin6 | bin6 | 0.010 | 188,238,282 |
| R3 | degraded | 9.3220 | 6,849,368 | 6,849,713 | 345 | 2.48 | bin6 | bin6 | 0.616 | 188,238,282 |
| R4 | fast | 9.3573 | 6,849,369 | 6,849,623 | 254 | 2.48 | bin6 | bin6 | 0.439 | 188,238,282 |
| R5 | fast | 9.4347 | 6,849,365 | 6,849,381 | 16 | 2.47 | bin6 | bin6 | 0.009 | 188,238,282 |
| R6 | degraded | 9.3167 | 6,849,363 | 6,849,691 | 328 | 2.48 | bin6 | bin6 | 0.652 | 188,245,564 |
| R7 | fast | 9.4422 | 6,849,363 | 6,849,422 | 59 | 2.47 | bin6 | bin6 | 0.010 | 188,248,890 |
| R8 | fast | 9.4423 | 6,849,365 | 6,849,424 | 59 | 2.47 | bin6 | bin6 | 0.012 | 188,248,890 |
| R9 | fast | 9.4365 | 6,849,367 | 6,849,426 | 59 | 2.47 | bin6 | bin6 | 0.031 | 188,308,998 |
| R10 | degraded | 9.2737 | 6,849,364 | 6,849,798 | 434 | 2.49 | bin6 | bin6 | 0.848 | 188,308,998 |
| **合计** | | | **68,493,653** | **68,495,265** | **1,612** | | | | | |

读数与判据（`raw/E1A/E1A_METRICS.txt`，脚本 `e1a_metrics.py`）：

1. **分母对账（同模块）**：`hist_total == ΔW52`（`app_tx_frames`）**10/10 逐字相等**；
   `hist_total ≤ ΔW14`（port0 `tcp_tx_frame.stat_frames`）**10/10**，差 16–434 帧（合计 1,612 = 0.0024%，
   控制/重放/中止帧）。`ΔW20` 与 `ΔW14` 差 1–2。
2. **延迟主读数**：**p50 与 p99 在全部 10 跑都落 bin6（384–511 cyc = 2.46–3.27 µs）**；
   `bin0..bin4 ≡ 0`、`bin3（192–223，纯帧器服务）≡ 0`；`bin5` 仅 16–37 帧/跑。
   meanX（扣掉 1 个污染帧）= **2.47–2.49 µs**；原始 mean = 2.64–2.66 µs。
3. **尾部**：`tail%`（≥512 cyc = ≥3.28 µs）= **0.007–0.031%**（7 个快跑）vs **0.44–0.85%**（3 个退化跑，
   sink 9.274–9.322 Gbps；R4 9.357 Gbps 也有 0.439%）。**p99 仍全部 ≤3.27 µs**。
   更高分位：**快跑 p99.5/p99.9/p99.99 仍在 bin6**（R8/R9 的 p99.99 进 bin7/bin8）；
   **退化跑 p99.5 与 p99.9 进 bin7（3.28–6.55 µs）**、p99.99 进 bin8（6.55–26.2 µs，R10 p99.9 已进 bin8）。
   观测：tail% 与速率亏损近似成比例（**tail ≈ 5 × 亏损%**，10 点，仅作形态描述、不作模型）。
4. **`max_total` = 1.2047–1.2052 s，是仪器污染，不是 fast-path 延迟**：W96 在 R2 的 MID1 从 31,932
   一次跳到 188,238,282 并只在后续会话略微抬升（R6/R7/R9 各 +7k/+3k/+60k cyc）；R1（复位后第一跑）
   max = 31,932 cyc = **204 µs**。机理（**推断**，与 H-1 同族）：`TX_CONTINUOUS=1` 下**会话边界**帧（连接关闭前后呈现、跨关闭期等待）
   因 `s_axis_tvalid` 不落而没有清 pending，要等下一次连接开窗才 T_DONE，
   于是 L ≈ 会话间空闲（≈1.2 s）。**每次会话边界恰 1 帧** ⇒ 直方图 bin9 里 1 帧，**p50/p99 不受影响**，
   但**原始 mean 被抬高 +0.17 µs**（故表内用 meanX）。E1a-2 必须清 pending 或给首帧打标签。
5. **数据内容**：10 跑 `mism_bytes=0` / `first_mismatch=-1` / `fail_conns=0` / `stall_conns=0`；
   sink 合计 **100,000,034,410 B**，`sink_bytes/ΔW20 = 1459.955 B/帧`（1460 载荷，末帧截断差）。
   `ΔW43/ΔW20 = 218.4–222.0`（含会话间空闲；in-run 帧周期 ≈194 cyc，与 801 kfps 一致）。
6. **与预注册预期（DESIGN §7.3）的差**：预期 p50 1.2–1.6 µs（bin0–bin3），实测 **2.46–3.27 µs（bin6，
   ≈2× 帧周期）**。bin3 全空 ⇒ **L 从不等于纯帧器服务时间**，始终含约 1 个帧槽的等待。
   候选机理（**未证**）：OVL 乒乓使 app 领先帧器约 1 帧，呈现时前一帧仍在流水内。
   E1a-2 的 wait/service 分解应首先检验这一条。

---

## 7. 未测/未定位/边界

- **状态**：本组 10 跑 = 7 个快跑（9.357–9.446 Gbps，tail ≤0.44%）+ 3 个退化跑（9.274–9.322 Gbps，
  tail 0.62–0.85%）；**E0.5 的慢态带（8.60–9.26 Gbps）本轮未复现** ⇒ 不能宣称“慢态已测”。
  退化跑是否 = E0.5 慢态的同一种状态，**未判定**（需要 E1a-2 的 wait/service 分解或更长窗口）。
- `max_total` 全局、首帧污染（§6-4，1.2 s 级）；p99 用 hist；max 只作上界。
- 扫描 1/16 只报下界，不修正 p99；空载负对照同时证明扫描自身不产生计数。
- `taskset` 绑核但 `--no-pin` ⇒ **无 `PIN_CPU=` 见证**，速率不作判据（全局 #62 口径）。
- E1a-2：wait/service 分解、polluted 计数器、port B W66–W69、RX fast-path、采样环、逐窗 max、
  **会话首帧标签/pending 清理**（本轮实测到的唯一仪器缺陷）。
- HLS UDP echo 996 B 缺陷与本件无关，仍登记在 `P7B_OPEN_ITEMS.md`。

---

## 8. 证据索引

```
DESIGN.md                       # 设计/实现/判据
REVIEW_RESPONSE.md              # 独立审查 5 高/11 中/低 逐条处置
tb_e1a_draft.v                  # 单元门 A/B/C/D
compile/xsim.log                # TB_E1A_PASS
e1a_latency.sh / e1a_metrics.py # 板级跑法与复算（待用）
compile/xvlog.log / xvlog_wrap.log
check_window / snap_top5 输出   # 见 §4
bits/wrapper_p4_0x33.bit        # 构建 2 位流（sha256 见 bits/SHA256.txt）
build2/                         # 构建 2 归档（stdout/timing/util/drc/routed/util-placed + READINGS.txt）
build_fail1/                    # 构建 1（TIMING_FAIL）归档
raw/                            # 板级 raw（进行中）
```
