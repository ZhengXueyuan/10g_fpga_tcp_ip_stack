# P11 HLS 慢路径延迟实测（xsim，2026-10-26）

- 目的：回答“控制面 HLS 在延迟里占多少”。**不改产品 RTL、不构建、不上板**；只对 0x32 构建实际使用的 P3 HLS 归档做行为级 xsim。
- 被测件：`_proj_10g/notes/p11_p3_build_20261019/hls_archive_p3_dual_ip_max8/udp_echo.v`（与 0x32 构建同目录；173 个 `.v` + 3 个 `.dat`）。
- TB：`tb_hls_latency.v`（6.4 ns 时钟；held-valid，`rx_tready` 接受就前进；单帧刺激；记录 RX/TX 帧首末拍）。
- 复跑：`C:/Users/zhxue/anaconda3/python.exe sim/p11_hls_latency/run_hls_latency.py`（xsim only；不与 Vivado 并跑）。
- 证据：`READINGS.txt`（= run2）、`READINGS_run1/2.txt`、`hls_latency_{arp,udp,udp1500,full}.txt`、`xvlog_*_run1/2.log`、`xelab_run1/2.log`、`xsim_*_run1/2.log`、`RERUN.txt`、`SHA256SUMS.txt`。

## 1. 关键读数（HLS-only，理想 1 B/拍供给，6.4 ns/拍）

| 用例（喂 HLS 字节） | RX 持续 | RX 速率 | TX 持续 | TX 速率 | first→first | last→last |
|---|---|---|---|---|---|---|
| ARP 68 B | 1566 拍 = **10.02 µs** | **23.0 拍/B** ≈ 54.3 Mbps | 2047 拍 = **13.10 µs** | **72 B / 28.43 拍/B** ≈ 44.0 Mbps | 11.04 µs | **14.12 µs** |
| UDP 74 B | 1710 拍 = **10.94 µs** | **23.1 拍/B** ≈ 54.1 Mbps | 2227 拍 = **14.25 µs** | **78 B / 28.55 拍/B** ≈ 43.8 Mbps | 17.27 µs | **20.58 µs** |
| UDP 1500B（1522 B fed） | 36462 拍 = **233.36 µs** | **23.96 拍/B** ≈ 52.2 Mbps | 45667 拍 = **292.27 µs** | **1526 B / 29.93 拍/B** ≈ 41.8 Mbps | 244.32 µs | **303.23 µs** |

- `rx_tready` 在帧内约 **95%** 的拍为低（ARP `wait=1499/1567`、UDP `wait=1637/1711`、1500B `wait=34941/36463`）。
- **HLS 实际吞吐 ≈ 52–54 Mbps（RX）/ 42–44 Mbps（TX）**，不是 1.5 Gbps；**“1 B/拍”只是宽松上界**。
- 交叉印证：`rtl/slow_rx_adp.v:179-181` 记录 HLS 读速约 **1 B/20 拍**，与本实测 ~23 拍/B 同量级（probe TB 的 `k>=25` 是复位后启动延迟，不是喂数节拍）。
- **同输入重跑 2 次**（同一刺激/同一 TB）：`READINGS_run1.txt` 与 `READINGS_run2.txt` **逐字节相同**，两套日志都在 `*_run1/2.log`，xsim 退出码 0；不是“跑一次就写结论”。

## 2. 边界（不许外推）

- **HLS-only**：不含 `slow_rx_adp`/`slow_tx_adp` 整帧缓冲、`slow_merge2`/`slow_demux2`、`tx_arb`、MAC/PCS/PHY/SFP。板级只会**更慢**，不会更快。
- xsim 是行为级；`tx_tready=1` 理想；不是板级测量。板级定量必须 E1（`P11_LATENCY_RESEARCH_20261026.md` §4.5）。
- 单帧刺激避免多帧配对歧义；`full` 用途是复核“ARP+UDP 背靠背”：ARP RX 不变，但 UDP 帧 RX **2159 拍 vs 单帧 1710（+449 拍 = +2.87 µs）**，说明 HLS 发 ARP 应答时收下一帧会排队；板级多帧突发还要加适配器/仲裁。
- **per-pass 计数**：`TX_PACING_COUNT=625,000,000` 只在 `udp_tx_process` 里每 pass +1（`layer_udp.cpp:126`），不是每时钟；按 ~20 拍/pass 估 HELLO 周期 **80–100 s**（纸面），不是 4.0 s。DHCP delay 同。UDP echo 立即回（`layer_udp.cpp:111-123`），不受 pacing 影响。
- **staging 词数**不是 `ceil(N/4)`：`mac_rx_process` 只把以太网头之后的字节写 `frame_fifo`，`slow_rx_adp` 补 8B 前导、无 FCS ⇒ ≈`ceil((N−22)/4)`。本件以 xsim 实测为准，不用该纸面公式。

## 3. 对主研究件的修订

`_proj_10g/notes/P11_LATENCY_RESEARCH_20261026.md` §3.4 已按本件重写：

- 删除“HLS 1 B/拍 = 1.5625 Gbps（错误换算；正确 1.25 Gbps）/ 小帧 1–3 µs / 1500B 22–26 µs”这组纸面数。
- 改为：小帧 HLS-only **14–21 µs**、1500B UDP echo **303 µs**；ping RTT 中 HLS 可能 **~8–32%**（0x32 64–117 µs 端；188 µs 历史端更低；此前“<5%”撤回）。
- 硬件化 ARP/ICMP 的收益下界至少 **~14–21 µs（HLS-only 下界）**；1500B UDP 必须绕开 HLS（fast path/8081 或 RTL echo）。
- §5.2-8 TCP echo 基线改为 **≈3.6 µs**（不是 4.8；echo 读出与 tx FIFO 写同路并发），缓冲合并省 ~1.2 µs ⇒ ~2.4 µs。
- §5.2-9 UDP cut-through 改为**现状前提不成立**：`udp_tx_frame` 的长度/IP checksum 在 TLAST 才得，`cfg_csum_en` 板级硬接 1，长度守卫整帧 abort；要做需新契约。
- §4.5 E1a 按独立审查补：`stat_commit/stat_frames` 是计数器不是脉冲、`tx_arb` 无 grant 输出、单 start/end 会跨帧错配、min/max/sum/count 无 p99、32 位 sum 回卷、快照 96 FF/字、VIO 64 位撕裂、M6 环回是往返不是单程、C4 需 port tag。

## 4. 独立审查（只读 agent）发现与处置

| # | 发现 | 处置 |
|---|---|---|
| 1 | HLS 实际速率被写成 1 B/拍，量化结论整体偏低一个数量级 | **已修**：本 xsim 实测 ~23/30 拍/B；§0/§3.4/§5.1/§7 重写 |
| 2 | `TX_PACING_COUNT`/DHCP 是 per-pass 计数，不是 per-clock | **已修**：§3.4/§5.4 改为 per-pass、HELLO ~80–100 s（纸面） |
| 3 | staging 不是 `ceil(N/4)`，字节边界错 | **已修**：§3.4 给出 `ceil((N−22)/4)`；以 xsim 实测为准 |
| 4 | TCP echo 4.8 µs 重复计入 tx FIFO 填充 | **已修**：§3.3/§5.2-8 改为 ≈3.6 → ≈2.4 |
| 5 | UDP cut-through 现状前提不成立 | **已修**：§5.2-9 重写为需新长度 sideband/IP checksum/运行路径/超长语义 |
| 6 | 漏适配器整帧、slow_merge2/demux2 HOL、tx_arb 无 aging | **部分修**：§3.4/§5.10 已列；精确值待 E1/E11 |
| 7 | E1a 观测清单不足（计数/无 grant/错配/无 p99/sum 回卷/快照 96FF/VIO 撕裂） | **已修**：§4.5 E1a 重写；p99 直方图/标签/64 位 sum/快照门 |
| 8 | “UDP 泛洪 ping 5/5”不能推出慢帧延迟有界 | **已修**：§5.10 明确只是通/不通；tx_arb 无 aging；E11 |
| 9 | HLS 顶层报告 `?`，不能从子函数 loop 推 2N | **已修**：§3.4 以 xsim 实测；顶层 47 状态 FSM；E1 先测 idle/RX/TX pass |
| 10 | E1a 边界/M6 单程标定问题 | **部分修**：§4.5 明确 M6 是往返、需 E1b/单向标定；C4 port tag 已列 |

## 5. 未做 / 下一步

- **板级 E1 未做**：需要观测构建（dp_clk 计数器 + 快照/直方图），本轮**未开工**。
- HLS 顶层 idle pass / 单字节 RX pass / 单字节 TX pass 的精确拍数：本 TB 只测整帧；下一步可加“空刺激/1 字节刺激”用例（研究，不实施）。
- `slow_*`/`tx_arb` 的真实等待：需 E1/E11 板级或带适配器的全链 xsim。
- 本件**不是**延迟优化实施授权；所有 RTL 改动需用户裁定并过 `P11_STA_TCB_GATE` + 完整 timing gate。
- 本测试**不在**常驻回归矩阵（`run_matrix_p4dfix.bat`）里：它是研究件，依赖 P3 HLS 归档目录；若后续要常驻，需单独登记门名/指纹/预算。
