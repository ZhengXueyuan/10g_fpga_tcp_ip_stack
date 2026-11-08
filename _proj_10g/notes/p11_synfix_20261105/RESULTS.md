# p11_synfix（F2）构建 + 板级结果（0x3C，2026-11-06）

- 设计 = `DESIGN_v2.md`；审查 = `REVIEW_FINDINGS.md`；本文 = 实施/构建/板级原始结论。
- 单变量 = **F2（FIN 优先级）**：`hls/src/layer_tcp.cpp` 的 `T_SYN_RCVD` 握手 ACK 分支加
  `!(flags&TCP_FIN)`（宏 `P11_FIN_FIX`，默认 0；`hls/run_hls.tcl` cflags 传 1）。
  旧码在 `#else`，源码级 inert。**未改任何 RTL、未改快照几何。**

## 1. 实施与 csim（已证）

- csim 双臂（MSVC，`run_csim_p3_all.bat`）：**4/4 臂 PASS，RC=0**；基线 3 条 XFAIL 逐字不变；
  `passed=114/113`（LEGACY/FIX，含新增 `test_p11_zero_data_fin`）。
- 原始判据行：
  ```
  LEGACY: P11_FIN_ARM=LEGACY  P11_TB_ZDFIN FIN1_DEL=0 STATE1=3 FIN2_DEL=1 STATE2=4 NEW_SYNACK=-1
  FIX   : P11_FIN_ARM=FIX     P11_TB_ZDFIN FIN1_DEL=1 STATE1=0 FIN2_DEL=-1 NEW_SYNACK=1
  ```
  STATE：0=T_FREE / 3=T_ESTABLISHED / 4=T_LAST_ACK（`TCP_STATE_PROBE` 直测）。
  ⇒ LEGACY 精确复现 R2（一个 FIN 不释放、槽停在 ESTABLISHED；第二个 FIN 才 DEL 并停 LAST_ACK）；
  FIX 一个 FIN 即 DEL + FREE，新 SYN 可建连。
- 现有用例（CHURN/SYNPAIR/HALFOPEN/P3）在两臂下逐行相同（除新增 ZDFIN 行）。

## 2. 构建 0x3C（已证）

- **HLS 重综合**（构建 bat 不会自动做，v1 的阻断项）：`hls/run_hls.bat` RC=0；
  **All loop constraints satisfied**；Estimated Fmax **156.92 MHz**；
  新归档 `hls_archive_p11fix_fin`（173 .v + 3 .dat）。
- 哈希：`HLS_SRC_HASH = 93dc1327…4e17`、`HLS_NET_HASH = 3fe03211…228d`
  （0x3B 为 `125a71f8…f8c3` ⇒ 网表确实变化）；`udp_echo.v` `a3b55f03…048f`
  vs 旧 `38767094…0538`；`udp_echo_tcp_rx_process.v` `a1925414…b190` vs `00f6d4a1…14ba`。
- 时序：**WNS +0.046 / TNS 0.000 / setup 失败端点 0 / 总端点 400,560；
  WHS +0.010 / hold 0；WPWS 0.000 / PW 0；"All user specified timing constraints are met."**
  路由 0 错。LUT 136,759（0x3B 136,748，+11）、FF/BRAM/URAM 见 `build_ok_0x3C/READINGS_0x3C.txt`。
- 位流：`bits/wrapper_p4_0x3C.bit`，sha256 **`d09d787ceb4cb871d2c5ef9f6ef8a6082bfa92a270d3b9860147f1dbbf9f6a8e`**
  （15,431,261 B）；已烧：BID `0x3C` / MAGIC / marker / UNIMPL 全中、`WINDOW_SCAN_NFF=0`、
  2 BAR、LnkSta x4、两 carrier=1、`0x08=0`。QSPI 零写入。

## 3. 板级 F2 A/B（同工装、同构型、单变量）【已证】

工装 = `leak_then_rawprobe.sh`：`.4` 口 8×4 GiB 一轮（单会话 app 只服务 1–2 条，其余零数据连接被关闭）
→ 板空闲 → 8 个原始 SYN（nsa 内 iptables 抑制内核 RST）→ **W7 增量 = 该时刻 HLS 空闲槽数**。

| 臂 | .4 零数据连接 | 原始探针 W7 增量 | W52（ev/estab） | 结论 |
|---|---|---|---|---|
| 0x3B（负臂） | P1–P6 = 6 条 0 字节 | **+2** | `0x0002/0x0002` | 只剩 2 槽 ⇒ 6 槽被零数据 FIN 泄漏 |
| 0x3C（正臂） | P1–P6 = 6 条 0 字节 | **+8** | `0x0008/0x0008` | 8 槽全空 ⇒ FIN 全部释放 |

原始件 = `raw/leak_then_rawprobe_0x3B.txt`、`raw/leak_then_rawprobe_0x3C.txt`。
（同一工装曾先在 0x3C 的 .4 泄漏轮后测到 W7 +8，见 `raw/raw_probe_after_f2_0x3C.txt`。）
⇒ **F2 修复在板级坐实**：零板→对端数据的连接关闭后不再泄漏 HLS 槽。

## 4. 回归（0x3C）

- 新鲜态 8×16 MB（`verify_0x3B_p0_c.sh`）：**8/8 建立并收满**，conn 0.11–1.45 ms，`poll_tmo=0`。
- 新鲜态 8×256 MB（`verify_0x3B_p0_d.sh`）：**8/8 收满**，`poll_tmo=0`，每条 268 MB。
  （mism 为 `TX_CONTINUOUS` 相位错，按既有口径不是内容判据。）
- ⚠️ **c→d 连续两轮**（先 8×16 MB 再 8×256 MB）：第二轮 3 条完成 / 5 条停顿（8 条均建立成功）；
  **单独重跑 d（新鲜态）= 8/8** ⇒ 状态依赖，属既有 A7 类（上一轮连接关闭时的槽/事件状态），
  **不是 F2 回归**。登记为观测（未定位到行）。

## 5. 残余（未解决，不许当已收口）

1. **R1 半开泄漏**（本轮未修）：原始 SYN/对端放弃重试后，`T_SYN_RCVD` 槽无老化（被动构建）；
   真实对端在重试期间会以同四元组 SYN 原地回收，但放弃后永久占槽。未来方案 = fast 侧
   `ack_seen` 半开回收 + HLS `i_slot_dead` 掩码（不写 cfg），见 `REVIEW_FINDINGS.md` §A。
2. **R3 pending 单槽**（本轮未修）：长 TX busy 下同时两个 SYN 只处理一个（csim ARM_B2 已证）。
3. FIN 分支不校验 seq（F2 扩大了伪造 FIN 的暴露面）。
4. `tcp_stat_no_slot` 仍不可板读（无观测几何变化，本轮未动 Tier A）。
5. `T_LAST_ACK` 老化结构性不可达（若未来需要，用专用计时器）。

## 6. 文件索引

- 源码：`hls/src/layer_tcp.cpp`（宏 + 分支）、`hls/run_hls.tcl`（cflags）、
  `hls/tb/udp_echo_tb.cpp`（ZDFIN 用例 + 臂名）。
- 构建：`run_build_0x3C.bat`、`board/p11_build_cfg.tcl`（`p11fix_fin`）、`board/wrapper_p4.v`（BID 0x3C）。
- 位流/报告：`bits/`、`build_ok_0x3C/`、`hls_archive_p11fix_fin/`、`hls_build/`。
- 板级：`leak_then_rawprobe.sh`、`raw_probe_table.sh`、`raw_syn_burst.py`、`verify_0x3C_f2.sh`、`raw/`。
- 负臂原始件：`raw/verify_f2_neg_0x3B.txt`（.4 轮后 .2 8×4GiB 探针 2/8→0/8，历史签名复现）。

## 7. 收尾板态（2026-11-06 02:3x 现读，fresh 8×256 MB 回归之后）

```
BID=0x0000003c  SCRATCH(0x08)=0x00000000  W6=0x00000038  W7=0x00000011
W52=0x002d0000（高半 = ADD/DEL 事件 45；低半 = 当前 ESTAB 0）
CARRIER_P1=1  CARRIER_P0=1
```

- ⇒ 板 = **0x3C + `0x08=0` + 两 carrier=1**；当前无已建立连接（W52 低半 0）。
  fresh 8×256 MB 的 8 条均带数据正常关闭 ⇒ 按 F2 各自释放槽（W7 为累计 SYN-ACK 数，不是空闲槽读数）。
- **未再跑破坏性探针**（原始 SYN 探针会给表留半开槽），故收尾态按"干净"留板；QSPI 零写入。

## 8. 0x3E 陈旧帧排水（2026-11-07，§0-93/§0-94）

- **构建**：尝试 A–F；**F = `Congestion_SpreadLogic_high` PASS**（WNS **+0.038** / WHS +0.010 /
  三类端点 **0/0/0**）。位流 **`572a7e91…ed2b`**（BID 0x3E / NW 98 / UNIMPL 0x1B8）。
  关键参数 = `DRAIN_EN`（port0=1 / port1=0 常数折叠；`tcp_tx_frame` 被两端口共例化，
  排水逻辑曾给 port1 既存族 `u_tcp_tx2/u_fifo→u_tcb2` 加负载）。
- **板级身份**：BID 0x3E / NW 98 / UNIMPL 0x1B8 / NFF=0 / 2 BAR / LnkSta x4 / 两 carrier=1 /
  `0x08=0`；QSPI 零写入。
- **主判据（板级）**：换烧周期 **64 轮 × 8×256 MB = 512 连接，64/64 轮 `OK=8 STALL=0`**
  （零停顿）。原件 = `raw/burn_cycle_0x3E_cycle*.txt`。
- **同工装 A/B**：0x3D（`39a7a9f5…8090`）两窗口 **48 轮 / 35 停顿连接** vs 0x3E **0/64**；
  0x3D 的 96 条 W71 采样去重 16 值，全部满足 `st_ok=0 / tx_blk_sid=1 / recv_first=1 /
  tvalid=1 / tready=0 / RX_IDLE / T_IDLE / fifo_full=0`（`wnd_open` 可 0 可 1）。
- **§0-92 c→d 判别**：0x3E 上 `f2_disc6.sh cd` 连跑 3 次 = **48/48 连接 OK、0 STALL**
  （c 轮 24/24 + d 轮 24/24，`mism_bytes=0`）vs 0x3C 旧 3/8 ⇒ **未复现**；
  ⛔ 归因后来被 §9 限定（0x3E 的排水判据有缺陷、未必参与），0x3F 上已重跑 3 次复现同样结果。
  原件 = `raw/cd_0x3E_3runs.txt`（0x3F 的 3 次在 `raw/board_0x3F_run.txt`）。
- **未覆盖**：帧内形态（`recv_first=0`）；§0-90（R1 半开泄漏）/ §0-91（pending 单槽 + FIN seq）
  / §0-88（SYN-under-load）仍开放。

## 9. 0x3F 排水判据订正（2026-11-07，§0-94 最终版）

- **0x3E 缺陷**：`frame_pending` 直接用 `!st_ok`，而 `rb_id` 每 16 拍被 `scan_now`
  （及 svc/ring_eval/probe）借走 ⇒ 扫描到任一 ESTAB 槽就把 `drain_cnt` 清零 ⇒
  **多连接同时活着时排水从不触发**。板级：0x3E 同时 8 连 13 轮 = 13 个停顿连接
  （含 sim8 0/8 整口停顿）；0x3D 同时 8 连复现（simd R4 2/8，W71=0x94103884）。
- **0x3F 修法**：采样判据 = 借走条件的补集 `!svc && !ring_eval && !scan_now &&
  !probe_sel && !ack_pend_r`（此时 `rb_id ≡ start_id`）；借走拍**保持**计数；
  本槽明确 ESTAB 或帧消失才清零。
- **构建 G PASS**（`Congestion_SpreadLogic_low`）：WNS **+0.037** / WHS +0.010 /
  三类端点 0/0/0；位流 **`b87987c8…0d8f`**；BID 0x3F / NW 98 / UNIMPL 0x1B8。
  尝试 A–G 全记录在 `build_fail_0x3F_*/` 与 `build_0x3F_stdout*.txt`；
  E 档曾达 0.000 / 0 端点但被 "WNS>0" 硬门拒。
- **板级（行为面）**：同时 8 连 40 轮 / 320 连接 ⇒ **2 个单连接零字节停顿、无整口楔死**；
  错开 8×256 MB 16 轮 / 128 连接全 OK；c→d 3 连跑 48/48 OK（活连接未误排）。
  原件 = `raw/board_0x3F_run.txt`；分析 = `STALL_INVESTIGATION.md` §6.5/§6.8。
- **残余**：2/320 单连接零字节（**未定位**；⚠️ 2026-11-08 复核：**"A7 `ev_up` 吞"这个候选不成立**
  —— 构建 E 的 A3 修复（`app_pattern.up_pend_r/up_pend_id`）就在 0x3F/0x40 的同一棵 RTL 里，
  `app_multi8` 也把每个槽的 `evu` 送进各自 core 的同一逻辑 ⇒ 该形态已被修掉，残余是**另一个**机制）；
  帧内形态（`recv_first=0`）未覆盖。

## 10. 0x40 = R1 半开槽老化（2026-11-08）—— 构建 PASS + 板级判据

- **设计**：`R1_R3_DESIGN_STUDY_v2.md`（xr13 审查逐条处置：H-1 边沿语义 / H-2 cid 映射 /
  H-3 R3-1b 归下批 / M-1 驳回 / M-2/M-3/M-4 接受 / L-1 驳回）。
- **实现**：`rtl/app_ctrl.v`（`HO_EN/HO_LIM`、`ho_ack_seen`、`ho_cnt`、`o_ho_fire/o_ho_slot`）、
  `rtl/slow_cfg_demux.v`（`o_add_hit/o_add_slot`）、`board/wrapper_p4.v`（全局 `slot_dead[7:0]`，
  清优先；`HO_EN_DEF` 仅 CDC 构建 + 结构防呆）、`hls/src/udp_echo.cpp`（`i_slot_dead` 边沿释槽，
  不写 cfg）。csim 4/4 PASS；RTL 单元门 `tb/tb_app_ho.v` 远端 xsim PASS（A/B/C 三臂）。
- **老化时延**：`HO_LIM(8) × ORPHAN_TICK(429.4967 ms) ≈ 3.44 s`（tick = 2^26 拍 @156.25 MHz，
  `scan_round` 每 256 拍 +1，tick 轮内 16 槽都被扫到）。
- **构建（0x40）= PASS**：`Performance_Auto_1` + **修剪前净表（commit `3a004050`）**；
  **WNS +0.021 / WHS +0.010 / setup·hold·pw 端点 0/0/0**（401,202 端点）；
  `All user specified timing constraints are met`；位流 **`0fd075f8…47b9`**（15,431,261 B）；
  LUT 138,011 / FF 106,541 / BRAM 109。报告 = `build_ok_0x40_o/`。
- **梯子（记录在案）**：修剪后净表全部 TIMING_FAIL（low −0.892 / high −0.659 / Explore −0.458 /
  Extra −0.107 / refine −0.237 / remap −0.255 / WLBlock −1.441 / NetDelay_high −1.042 / medium −0.960）；
  修剪前：low −0.395 / **high 0.000（0 端点、约束全满足，被 `WNS>0` 门拒）** / remap −0.031 /
  **Auto_1 +0.021（PASS）**；`Flow_RunPostRoutePhysOpt` −1.851（PCS RX 域）。
  ⇒ **trim 经三组配对判定为回归**，已回退（提交 `54cc8a74`）。
- **板级（0x40；BID 0x40 / NW 98 / UNIMPL 0x1B8 / NFF=0 / 2 BAR / 两 carrier=1；QSPI 零写入）**：
  - **ARM A 正臂【已证 ×3】**：8 个原始 SYN 填半开（W6/W7 各 +8）→ 等 6.0 s →
    8 个新原始 SYN ⇒ **dW7 = +8**（0x3F 基线 +0）；同时 **W52 estab 8 → 0**（等待期直接见证释槽）。
    三次复现：`raw/r1_accept_0x40/accept_run1.txt`、`arm_a_repeat.txt`。
  - **ARM B 活连接安全【已证】**：单连接带 ACK 历史、空闲 6.0 s（> 3.44 s）⇒ 恢复收数据（+65,536 B）。
  - **ARM B2 八连接同步空闲【已证 ×2】**：8 条并发活连接、同步空闲 6.0 s ⇒ **8/8 恢复**
    （`arm_b2_v2.txt`）。⚠️ 首版用 `threading.Barrier` 的写法**不可用**（一个 worker 异常就级联
    abort ⇒ 0/8），是测试工具的缺陷，**不是板子**。
  - **ARM T 老化时延 + race**：首次成功探测在 T0 后 **2.14 s**，而 T0 距最后一批 ADD ≈2.2 s
    ⇒ 实际 ≈**4.3 s**（与 3.44 s + 突发展布相容）；**其前一次探测 connect 成功但 2.0 s 零字节**
    （见"残余"）。
  - **ARM C 跨端口 race【已证】**：port0 8 个半开老化期间，port1 连续 12 次 1 MB 传输 **12/12 OK**；
    反向 port1 半开、port0 **6/6 OK**。⚠️ 板侧无 cid 读出 ⇒ 概率型，不是精确同号构造。
  - **回归**：8 连接同时 256 MB **3 轮 / 24 连接全 OK**（`mism_bytes=0`、`poll_tmo=0`、7.7–9.45 Gbps）；
    **c→d 3 轮 48/48 OK、0 STALL**（16 MB 轮 + 256 MB 轮）。原件 = 对端
    `/home/a/p11_bench/r1c*`、`r1cd*`（摘要见台账 §10-194）。
  - **长时活连接（R1 安全性的最强一支）**：8 条并发、每条 **12 GB**、时长 **46.4–83.7 s**
    （= 老化时延 3.44 s 的 **13–24 倍**）⇒ **8/8 OK、`mism_bytes=0`、`poll_tmo=0`**、
    聚合 ≈9.7 Gbps。⇒ **活连接不会被误老化**（连续 ACK 使 `ho_ack_seen` 保持置位）。
    原件 = 对端 `/home/a/p11_bench/soak40b_*.txt`。
  - **同时 8 连的重复计数**：20 轮 ×8 = **160/160 OK、0 STALL**；40 轮 ×8 = **320/320 OK、0 STALL**
    （与 0x3F 的 2/320 同规模样本；⚠️ 0 vs 2 在 Fisher 意义下**不显著**，只能写
    "0x40 上 320 连接**未观测到**该残余"，不能写"已消除"）。原件 = 对端 `sx40r*`、`sx40b*`。
  - **观测面副产物**：0x40 上流量后 **W71=W73=0x142（322，非零）** ⇒ **`§0-80` 的
    "W71–W74 恒 0"在本位上不复现**（该结论来自 0x36；本件按"未复现"登记，不写"已修"）。
    W51/W53/W54 仍为 0（未判定其语义是否与本构型相关）。
  - **残余（本次观测到 1 次）**：ARM T 的第 1 次探测 **connect 成功（0.176 ms）但 2.0 s 零字节**，
    下一次即正常（8.5 Gbps）⇒ 与 §0-94 的"8 路同建连初始化窗 / 单连接零字节"同族，
    **未定位**；本轮未做 0x3F A/B（0x3F 无 R1，但该形态在 0x3F 也存在）。
