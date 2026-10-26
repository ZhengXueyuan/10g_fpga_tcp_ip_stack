# P11 延迟缩减研究（研究件；**未开工**）

- 日期：2026-10-26
- 仓库：`D:\repo\XCKU5PMini\udp_hls_10g`；基线 HEAD = `4cfa92e2`（0x32 修复轮工作树）
- 用户口径（2026-10-26 逐字）：**“研究如何缩小延时，这部分工作不要直接开工，也不要管工程量大不大影响大不大，从各个角度持续研究，从工程设计到具体功能的实现等等。”**
- 本件是**研究/方案/实验设计**，**没有实施任何延迟改动**；所有“预期收益”均为纸面/推断，未在板上验证。
- 状态词：**【已证·板级】【已证·源码】【推断】【未判定】【未测】【纸面】**。
- 与吞吐件的关系：0x32 板级已证**每口 9G 级 egress**（A 9.395 Gbps / B 9.431/9.393 Gbps）；本件不改变该结论。

---

## 0. 一页结论（先读）

1. **现状可测延迟**：0x32 板级 ping RTT = **p1 0.073/0.093/0.117 ms、p0 0.064/0.066/0.070 ms**（3/3）；0x2D 历史 0.095–0.188 ms；P7b 的 `ss -ti` `minrtt` 0.073–0.138 ms **只是握手/慢路径 RTT，不是数据面 RTT**（`p7b_longflow_board/ACCEPT.md` §C8 已定“未判定”）。**数据面（TCP echo / 大帧）的板内驻留和端到端 RTT 没有直接测量**。
2. **最大的不确定不是“哪个优化”，而是“延迟花在哪”**。当前没有 FPGA 侧时间戳；对端 SFC9120 的 `ethtool -T` 显示 **无 PTP 硬件时钟、无硬件 TX/RX 时间戳**（只有 software-receive/software-system-clock）。因此第一步必须是**测量基础设施**（FPGA 驻留计数器 + 对端软件/DPDK 时间戳 + 分段 A/B），否则任何“优化收益”都无法归因。
3. **结构性的 TCP 下限**：`tcp_echo` 逐帧 store-and-forward（源码注释明确“端到端延迟 = 帧长”，`rtl/tcp_echo.v:3`），`tcp_tx_frame` 也要整帧入 FIFO 后算完 TCP 校验和才发（`rtl/tcp_tx_frame.v:4-8`）。1500B 帧在 10G 上串行时间 **1.2 µs**；echo 至少 RX 串行 + 整帧读出 + TX 串行 ⇒ 纸面 **≈3.6 µs + 流水/CDC/队列**（§3.3）。TCP 校验和 + FCS 正确性使“真 cut-through”在 TCP echo 上**不可行**（除非牺牲正确性）；UDP（IPv4 checksum=0）是唯一可 cut-through 的候选。
4. **控制面（ARP/ICMP/TCP SYN）走 HLS 慢路径；xsim 实测推翻了“1 B/拍”纸面**（§3.4）：P3 HLS 网表实际 **~23 拍/B RX、~28–30 拍/B TX**（≈52–54 / 42–44 Mbps），ARP 小帧 HLS-only **14.1 µs**、UDP 74B **20.6 µs**、1500B UDP echo **303 µs**（last→last；无适配器/仲裁/MAC）。⇒ ping RTT 中 HLS 可能占 **~8–32%**（0x32 64–117 µs 端；188 µs 历史端更低），此前“板内 <5%、host >95%”的推断**撤回**；硬件化 ARP/ICMP 的收益下界改为 **≥14–21 µs（HLS-only 下界；板级可能更高）**，但仍须 E1 板级实测。**1500B UDP echo 必须绕开 HLS**（fast path/8081 或 RTL echo）。
5. **不建议先动大工程**：先做 E0/E1（测量）、E6（对端软件 A/B）、E2（FIFO/CDC 占用）三件低成本实验；只有测量证明“板内 > 对端”时，才进入控制面硬件化/时钟域合并/cut-through 研究。**不要**先改 RTL 再找证据；任何 RTL 改动必须过 `P11_STA_TCB_GATE`（0x32 余量仅 +0.019 ns）。

---

## 1. 延迟的定义与口径

必须先钉死“哪个延迟”，否则数字不可比：

| 口径 | 定义 | 本工程可测性 |
|---|---|---|
| `L_app` | 应用层请求发出到响应可读（socket API 两侧） | 可测（`clock_gettime`），含两端内核 |
| `L_wire` | 线上第一字节进 → 响应第一字节出（同一物理点） | **无硬件 timestamp**；需 FPGA 计数器/外部仪器 |
| `L_board` | 板内 MAC RX 首字 → MAC TX 首字 | 需新增 FPGA 时间戳（研究） |
| `L_ctrl` | ARP/ICMP/SYN 的板内驻留 | 需 HLS 路径计数器 |
| `L_data` | TCP 数据/echo 的板内驻留 | 需 `tcp_rx`/`tcp_echo`/`tcp_tx_frame` 分段计数器 |
| `L_queue` | 排队/窗口/背压导致的额外时延（尾延迟） | 需 occupancy 时间序列/直方图 |
| `L_setup` | SYN→SYN-ACK→ACK 建连 | 可用 socket/pcap 软件时间；板内 HLS 未分离 |

**统计口径**：至少 min / median / p99 / max；均值会被慢路径/软件调度污染。报告必须带：
- 对端 `rx-usecs`/`adaptive-rx`/`tx-usecs` 值；
- `PIN_CPU`/`PIN_THREAD` 见证（或 `UNPINNED=1` + taskset mask）；
- 同会话 A/B（同一 bitstream、同一路径、同一 sink 配置）；
- 负载档（空载 / 单流 9G / 双流）；
- 是否含 ARP、是否静态邻居、是否 TCP_NODELAY/QUICKACK。

---

## 2. 现有读数（只列有出处的）

| 读数 | 值 | 出处/口径 |
|---|---|---|
| 0x32 ping p1 | 0.073/0.093/0.117 ms（3/3） | `p11_board_p3_0x32_20261026/README_FOR_TL.md` §4.2 + 会话原始 ping |
| 0x32 ping p0 | 0.064/0.066/0.070 ms（3/3） | 同上 |
| 0x2D ping | p0 0.095/0.120/0.153 ms；p1 0.099/0.130/0.188 ms | `p11_board_p2_0x2D_20261018/README_FOR_TL.md` B-5 |
| P7b 长流 `ss -ti` minrtt | 0.073–0.138 ms | `p7b_longflow_board/ACCEPT.md` §RTT；**纯接收方向，仅握手/慢路径，不是数据 RTT（C8 未判定）** |
| 对端 NIC coalescing | `Adaptive RX: on, rx-usecs: 60, rx-usecs-irq: 60` 历史值；本轮板测已 `adaptive-rx off, rx-usecs 0` | `p7b_longflow_board/ACCEPT.md` + `b0_env_setup.sh` |
| 0x32 单口 TCP 下行 | A 9.395 Gbps（40GB）/ B 9.431、9.393 Gbps（5GB）；**E0.5 单口：快态 9.4405/9.4437/9.4453、慢态 9.2560/9.0701 Gbps（±0.2% 墙钟）** | `p11_board_p3_0x32_20261026/raw/SP3_sink.txt`、`B1/B2.txt`；`p11_e05_latency_20261027/` |
| 0x32 双口同时 | **D9R raw（2026-10-27）：A 8.9367 / B 8.9352 = 17.8719G（host-side sum）**；旧 D9 8.798/8.925（sink raw 0 B）仅历史；auto-pin 撞核 3.94+3.94=7.87G | `raw/D9R_A_sink.txt`/`D9R_B_sink.txt`/`D9R_CONSOLE_*`；**2×9G 同时【已证·板级 8.9G 档】；2×9.4G 线速同时仍【未判定】**；聚合不是板内计数器；降速归因 = host SMT 聚合（B 段） |
| 合同 | SYN-ACK `win=49152`、`mss 1460`、无 wscale | `raw/SYN_OPTS.txt`、`SYN_P0.txt` |
| 板内 `WIN_CAP` | 0xF000 = 61,440 B（P7b 既有） | `board/wrapper_p4.v` 的 WIN_CAP 单一来源；0x32 W69 `0xf53cf000` 低 16 位 0xF000（⚠️ W69 为单点锁存 + 扫描伪拍污染，仅旁证；H-1） |
| 0x32 TCB 余量 | +0.019 ns 全局 / A–F min +0.115 ns | `build0x32/P7B_STDOUT.txt`、`gates/sta_0x32_tcb.txt` |

> **不要在延迟报告里引用 `9.395 Gbps` 反推 RTT 为“已测”**：`61440 B / 9.395 Gbps ≈ 52.3 µs` 只是**若吞吐恰好被 61,440 B 窗帽住**的换算式（纸面），不证明数据 RTT=52.3 µs；P7b C8 已因纯接收方向判定“数据 RTT 未判定”。

---

## 3. 架构图与延迟贡献点

### 3.1 时钟域（先看这个）

```
PCS/GTY ── rx_clk_out ──► FE RX 域 (gmii_clk) ── rxcdc (256×76, FWFT) ──► DP 域 (156.25MHz)
PCS/GTY ── tx_clk_out ──► FE TX 域 (tx_fe_clk) ◄── txcdc (256×73, FWFT) ◄── DP 域
Y1 100MHz ── MMCM ×1.5625 ──► DP 域 (clk_gen_p6b; 100→1250→156.25MHz)
PCIe ── pcie_axi_aclk ──► 观测/快照/XDMA
```

- `board/wrapper_p4.v:517-539`（FE RX/TX 域与 DP 域别名）；`:975-1001`（MMCM）。
- `u_rxcdc` / `u_txcdc` 深度 **256**、FWFT（`wrapper_p4.v:1285/4355`；`rtl/fifo_async.v:101-109`）。
- 两个 CDC 都是 **2 级同步 + 灰码指针**；固定同步延迟约 **2–3 个读时钟**（≈13–19 ns）**加上 FIFO 占用**（最多 256 字 = **1.64 µs @156.25MHz**）。

### 3.2 关键路径模块与延迟类型

| 级 | 模块 | 缓冲/延迟类型 | 纸面/源码依据 |
|---|---|---|---|
| RX MAC | `mac_rx_10g` | 16 深字 FIFO；流式 | `_proj_10g/p7b_mac/rtl/mac_rx_10g.v:484-498` |
| RX CDC | `fifo_async` 256 | 2 级同步 + 占用排队 | `rtl/fifo_async.v:3-33`；`wrapper_p4.v:1285` |
| VLAN | `vlan_strip` | 非 VLAN 1 拍直通 | `wrapper_p4.v:1361-1390` 注释 |
| 分类 | `rx_classify` | 字 FIFO 16；TCP 控制/数据判据在 **widx=5**（第 6 字）才定案 | `rtl/rx_classify.v:99-107`、`:70-90` |
| TCP RX | `tcp_rx` | 头部 6 字解析；载荷**流式**；坏帧在 TLAST 才回卷 | `rtl/tcp_rx.v:1-14`、`:380-432` |
| Echo | `tcp_echo` | **整帧 store-and-forward**（fend 后才转发）；C4 D=16384/AW=14=128KB | `rtl/tcp_echo.v:2-3`、`board/wrapper_p4.v` 的 `u_tcp_echo` |
| TCP TX | `tcp_tx_frame` | 整帧入 payload FIFO + checksum 落定才发（帧级递交） | `rtl/tcp_tx_frame.v:4-8` |
| 仲裁 | `tx_arb` | 帧级锁定；fast 严格优先；帧间 1 拍重仲裁 | `rtl/tx_arb.v:1-6` |
| TX CDC | `fifo_async` 256 | 同 RX | `wrapper_p4.v:4355` |
| TX MAC | `mac_tx_10g` | 16 深 FIFO；可在 FIFO 非空即发前导（cut-through 倾向，但欠载会 abort） | `_proj_10g/p7b_mac/rtl/mac_tx_10g.v:89-132` |
| 慢路径 | `slow_rx_adp`→HLS→`slow_tx_adp` | RX/TX 适配器整帧缓冲；HLS 逐字节 FSM；`TX_PACING_COUNT=625,000,000`（周期 HELLO，echo 立即） | `rtl/slow_rx_adp.v`、`rtl/slow_tx_adp.v:95`、`hls/src/eth_types.h:222`、`layer_udp.cpp:111-112` |
| 配额 | `win_pool_mgr` | 三拍事件机（S_LOAD/S_CALC/S_COMMIT）；**只影响建连/配额，不在数据帧热路径** | `rtl/win_pool_mgr.v:200-430` |
| 共享 retx | `retx_pool_shared` | 写口/读口 2 拍读延迟；仅重传路径 | `rtl/retx_pool_shared.v`、`rtl/retx_ram.v` |

### 3.3 纸面延迟预算（**不是测量**）

**TCP echo 1500B（板内，理想无排队）**：

| 段 | 纸面 | 说明 |
|---|---|---|
| 线上串行 1518B @10G | 1.214 µs | 0.8 ns/B；收发各一次 ⇒ 2.43 µs |
| MAC RX 16 深 + CDC 固定 | 0.1–0.3 µs | 16 字 FIFO + 2–3 拍同步 |
| 分类 6 字 + FIFO | 0.04–0.14 µs | 6 拍 + 16 深 |
| `tcp_rx` 头部 6 字 + 载荷流 | 0.04 µs + 串行 | 载荷不整帧缓冲 |
| `tcp_echo` 整帧缓冲 | **1.2 µs** | 源码明确 fend 后才转发 |
| `tcp_tx_frame` 载荷 FIFO 写 | **与 echo 读出同路并发** | 不是额外 1.2 µs；TLAST 后仅 ~5 拍 checksum 落定 |
| TX CDC + MAC TX | 0.1–0.3 µs + 1.6 µs 最坏占用 | 256 深 FIFO |
| `tcp_tx_frame` TLAST→S_HDR | ~5 拍 ≈ 32 ns | checksum 落定（`tcp_tx_frame.v:2581-2586`），**不是**整帧再缓冲 |
| **合计（首→末，无排队）** | **≈3.6 µs** | RX 1.2 + echo 读出 1.2 + TX 1.2；另加流水/CDC/仲裁 ~0.2–0.6 µs ⇒ **~4 µs 量级**；不含对端/PHY/光模块；**纸面** |

**小帧（64B）**：串行 ≈51 ns ×2；主要变成**流水/CDC/仲裁/软件**；纸面板内 ≈0.5–1.5 µs（不含 HLS/对端）。

**控制面（ARP/ICMP/SYN）**：慢路径 + HLS 逐字节 FSM + 慢适配器整帧 + `tx_arb` 帧锁；**没有分段计数器**。ping RTT 73–188 µs 中板内占多少 **【未判定】**。

**关键结论**：对 1500B TCP echo，**帧串行 + echo 整帧读出是结构性下限**；把 CDC 从 256 降到 64 或合并时钟只能省 **几十 ns + 队列**，不可能把 ~3.6 µs 变成 1 µs。**HLS 8080 的 1500B UDP echo 是 303 µs（xsim 实测，HLS-only）**，TCP echo 约 **3.6–4.5 µs**（纸面）；**小帧控制面 HLS-only 是 14–21 µs（xsim）**，不是 1–3 µs。TCP/UDP 快路径的数字仍需 E1 板级确认；HLS 的 303 µs 已由 xsim 直接测到。

### 3.4 HLS 慢路径：源码预算 + xsim 实测（2026-10-26；**“1 B/拍”假设已被实测推翻**）

这一节回答“控制面 HLS 到底占多少”。它不改变任何 RTL；先用源码把**时间基准**钉死，再用 xsim 直接测 P3 HLS 网表。

**时钟与时间基准（源码/构建锚点）**
- HLS 顶层 `u_hls` 的 `.ap_clk(dp_clk)`（`board/wrapper_p4.v:3849`），`dp_clk` = **156.25 MHz**（`DP_156MHZ=1`）；HLS 综合目标 8 ns（125 MHz，`hls/run_hls.tcl:19`）只是**综合约束**，实际网表在 6.4 ns 域闭合（0x32 构建 0 失败端点）。
- `mac_rx_process` 每次调用最多读 **1 字节**（`hls/src/layer_mac.cpp:67`）；`mac_tx_process` 每次调用最多写 **1 字节**（`:233/266/286/308`）。但“每次调用 1 字节”**不等于**“每拍调用”：生成的顶层是 **47 状态 FSM**（`ap_CS_fsm[46:0]`），无帧路径也要经过约 20 个状态；`slow_rx_adp.v:179-181` 自己就记录 HLS 读速约 **1 B/20 拍**。⇒ **1 B/拍只是宽松上界，不是实际吞吐**（独立审查 2026-10-26 同结论）。
- `arp_rx_process` 单帧 37–582 拍（报告明细；0.24–3.72 µs @6.4ns），是**单次调用/单帧**（`arp_update` 学习 + 可选应答构包），不是整表跨帧累计；最大 582 含 L1 满时扫 L2 的空槽。
- **每 pass 计数**：`TX_PACING_COUNT=625,000,000`（`hls/src/eth_types.h:222`）只在 `udp_tx_process` 里 `time_cnt++`（`layer_udp.cpp:126`），即**每个 HLS 顶层 pass 加 1**，不是每时钟加 1；按 ~20 拍/pass 估，HELLO 周期约 **80–100 s**（纸面，不是 4.0 s）。DHCP 的 `dhcp_delay > 100000000`（`udp_echo.cpp:132-135`）同样按 pass 计，实际约十几秒，不是注释里的“~1 s”。UDP echo 在 `layer_udp.cpp:111-123` 明确**立即回**，不等 pacing。
- staging 词数不是 `ceil(N/4)`：`mac_rx_process` 只把以太网头**之后**的字节写 `frame_fifo`（`layer_mac.cpp:135-162`），`slow_rx_adp` 另补 8B 前导且不带 FCS（`slow_rx_adp.v:2-8`）⇒ staging ≈ `ceil((N−22)/4)`。下面的 xsim 实测不受这个纸面公式影响。
- **字节契约（避免再算错边界）**：wire = 8B 前导 + 14B MAC 头 + L3/L4/载荷 + 4B FCS；`slow_rx_adp` 送给 HLS 的是 **8B 前导 + 内容（不含 FCS）**；HLS `mac_rx_process` 剥 MAC 头后，`frame_fifo` 只装 **L3 及以后**；HLS `mac_tx_process` 输出 **8B 前导 + 14B MAC + pad 到 46B + 4B FCS**；`slow_tx_adp` 再剥前导/FCS，`mac_tx_64` 重算 FCS。xsim 表里的 "fed" 与 "TX bytes" 分别按这两个边界计。

**xsim 实测（P3 网表 `hls_archive_p3_dual_ip_max8`；HLS-only，无适配器/仲裁/MAC）**

被测件 = 0x32 构建实际使用的 P3 HLS 归档；TB = `sim/p11_hls_latency/tb_hls_latency.v`；时钟 6.4 ns；输入按 held-valid、`rx_tready` 接受就前进（理想 1 B/拍供给）；单帧刺激（ARP-only / UDP-only / UDP-1500B），避免多帧配对歧义。读法 = `sim/p11_hls_latency/READINGS.txt` + `hls_latency_{arp,udp,udp1500,full}.txt` + `xvlog_*`/`xelab`/`xsim_*` 日志。

| 帧（喂 HLS 字节） | RX 持续时间 | RX 速率 | TX 持续时间 | TX 速率 | first→first | last→last |
|---|---|---|---|---|---|---|
| ARP 68 B | 1566 拍 = **10.02 µs** | **23.0 拍/B** = 54.3 Mbps | 2047 拍 = **13.10 µs** | **72 B / 28.43 拍/B** = 44.0 Mbps | 11.04 µs | **14.12 µs** |
| UDP 74 B | 1710 拍 = **10.94 µs** | **23.1 拍/B** = 54.1 Mbps | 2227 拍 = **14.25 µs** | **78 B / 28.55 拍/B** = 43.8 Mbps | 17.27 µs | **20.58 µs** |
| UDP 1500B（1522 B fed） | 36462 拍 = **233.36 µs** | **23.96 拍/B** = 52.2 Mbps | 45667 拍 = **292.27 µs** | **1526 B / 29.93 拍/B** = 41.8 Mbps | 244.32 µs | **303.23 µs** |

- **HLS 实际吞吐 ≈ 52–54 Mbps（RX）/ 42–44 Mbps（TX）**，不是 1.5 Gbps；`rx_tready` 在帧内约 **95%** 的拍为低（ARP `wait=1499/1567`、UDP `wait=1637/1711`、1500B `wait=34941/36463`）。
- **HLS-only 小帧延迟**：ARP 14.1 µs、UDP 74B 20.6 µs（last→last）；1500B UDP echo **303 µs**。这是**下界**：板级还要加 `slow_rx_adp`/`slow_tx_adp` 整帧缓冲、`slow_merge2`/`slow_demux2` 排队、`tx_arb` 等待、MAC/PCS/PHY。
- **交叉印证**：`rtl/slow_rx_adp.v:179-181` 记录 HLS 读速约 **1 B/20 拍**，与本次实测 ~23 拍/B 同量级；说明这不是 TB 人为慢，而是 HLS 网表的结构速率。
- **背靠背（full）**：ARP 帧 RX 1566 拍不变；随后 UDP 帧 RX **2159 拍**（单帧 1710，**+449 拍 = +2.87 µs**），TX 2227 拍不变 ⇒ HLS 在发 ARP 应答时不能全速收下一帧；板级多帧/控制面突发会排队（这是“帧级”而非“字节级”的额外项）。
- **方法边界**：xsim 是 RTL 行为级、理想 `tx_tready=1`、无 `slow_*`/MAC；它**不能**代替板级 E1。但它足以**否定**“HLS 1 B/拍 / 小帧 1–3 µs / 1500B 24 µs”这组纸面数。

**适配器/仲裁（纸面，未含在上表）**
- `slow_rx_adp`：整帧 `frame_fifo`（512×73b）commit 后才起播；`slow_tx_adp`：HLS 字节先入 2048B FIFO，再整帧 `frame_fifo` 才对 `tx_arb` 可见（`rtl/slow_rx_adp.v:3-8,94-100,176-192`；`rtl/slow_tx_adp.v:5-12,95-115,305-307`）。1500B 的整帧缓冲在 DP 8B/拍下约 1.2 µs/次，且 HLS 字节率远低于 DP ⇒ **大帧的适配器等待被 HLS 串行掩盖，但整帧 commit/起播仍加一次帧级延迟**；小帧是“几拍到几十拍 + 整帧缓冲”。
- `slow_merge2` 是**帧级 RR**（`rtl/slow_merge2.v:8-14,63-71`）：一口大帧可把另一口挡在 HLS 前；`slow_demux2` 是**无缓冲组合 mux + 端口锁存**（`rtl/slow_demux2.v:11,46-57`），单份 HLS 输出被某口 arb 反压时会 HOL 阻塞另一口。
- `tx_arb` 严格快优先、**无 aging/预留窗**（`rtl/tx_arb.v:2-4,42-50`）：慢帧可能连续等多个 fast 帧，不是“最坏一个 1500B 帧”。**板级 300 s UDP 泛洪下 ping 5/5 只证“通/不通”，不是延迟上界**（`p7b_udp_longrun_20261009/tables.txt:59-61`）。
- 因此板级 HLS 小帧驻留 = xsim 14–21 µs **+ 适配器/仲裁/排队**；具体加多少必须 E1 测，不能从 xsim 直接外推。

**结论（已改口径）**
1. **小帧控制面 HLS-only = 14–21 µs（xsim）**，不是 1–3 µs；ping RTT 中 HLS 可能占 **~8–32%**（0x32 64–117 µs 端；188 µs 历史端更低；板级还会加适配器/仲裁）。此前“板内 <5%、host >95%”的推断**撤回**，改为“host 仍是候选主项，但 HLS 绝不可忽略，E1 必须实测”。
2. **硬件化 ARP/ICMP 的收益估计从“~1–2 µs”改为“至少 14–21 µs（HLS-only 下界；板级可能更高）”**；SYN 类似。控制面硬件化的优先级**回升**，但仍应由 E1 板级数据决定。
3. **HLS 8080 的 1500B UDP echo = 303 µs（HLS-only 下界）**，不是 24 µs；低延迟大帧 UDP **必须**绕开 HLS（fast path/8081 或 RTL echo），这不是“优化 HLS 循环”能救的。
4. `TX_PACING_COUNT` 的 4.0/5.0 s 算术虽对（625M/156.25M、/125M），但**时间基准是 pass 不是时钟**；按 ~20 拍/pass，实际 HELLO 约 **80–100 s**（纸面）。旧文“2.048 µs”错误，已删。
5. 以上 xsim 数是**行为级、理想供给**；板级 E1 必须测“空 pass / 单字节 RX pass / 单字节 TX pass”与真实适配器/仲裁，才能把 HLS 从“候选”变“定量”。

**证据/复跑**
- `sim/p11_hls_latency/tb_hls_latency.v`、`run_hls_latency.py`、`READINGS.txt`、`hls_latency_{arp,udp,udp1500,full}.txt`、`xvlog_*.log`、`xelab.log`、`xsim_*.log`。
- 复跑：`C:/Users/zhxue/anaconda3/python.exe sim/p11_hls_latency/run_hls_latency.py`（xsim only；不与 Vivado 并跑）。

---

## 4. 测量基础设施（E0：先做这个，不碰 RTL 产品路径）

### 4.1 为什么不能直接用 `ping`/`ss`

- `ping` RTT 含对端内核调度/NAPI/ICMP 栈，且板内走 HLS 慢路径；**不是数据面**。
- `ss -ti` 的 `minrtt` 在**纯接收方向**只有握手/慢路径采样（P7b C8 已定案）；不能当数据 RTT。
- 对端 SFC9120 `ethtool -T` 实测：`PTP Hardware Clock: none` / `Hardware Transmit Timestamp Modes: none` / `Hardware Receive Filter Modes: none` ⇒ **没有 NIC 硬件时间戳**。不要设计依赖它的实验。
- 软件 `clock_gettime` 含 syscall/调度/NAPI，误差 µs–几十 µs；只能做**同会话 A/B**，不能当绝对板内。

### 4.2 候选测量手段（按独立性/成本排序）

| # | 手段 | 能测什么 | 成本/风险 | 备注 |
|---|---|---|---|---|
| M1 | **FPGA 驻留计数器**（新增，观测构建） | 板内 `MAC RX 首字 → MAC TX 首字`；按端口/连接/控制/数据分桶 | 中；需新 BID + 时序门；32 位直方图/64 位时间戳 | **首选**；不改变数据路径 |
| M2 | **分段 FPGA 时间戳** | `tcp_rx` 首/末、`tcp_echo` fend、`tcp_tx_frame` 首/末、`tx_arb` 等待 | 中高；多域时间戳需 CDC/灰度 | 定位“TCP ~3.6–4.5 µs / HLS 14–303 µs 花在哪” |
| M3 | 对端 `SO_TIMESTAMPING`（software） | 应用/内核边界 | 低 | 含内核；只做相对 A/B |
| M4 | 对端 DPDK / AF_XDP 忙轮询 | 用户态收发边界（TSC） | 中；SFC9120 DPDK 支持需核实 | 低开销，但仍非线上 |
| M5 | 外部流量发生器/第二块 FPGA 硬件时间戳 | 真 `L_wire` | 高（无设备） | 最权威；当前不可用 |
| M6 | 板内 MAC TX→RX 内部环回 | MAC/PCS/CDC 流水预算 | 低（可配置） | 可分离 PHY/对端；不是端到端 |
| M7 | `pcap` 软件时间戳 | 帧序/ACK 节奏 | 低 | 不用于 ns |

### 4.3 M1/M2 设计草案（研究，不实施）

- **一个全局 64 位自由计数器**（`dp_clk` 域），通过 Gray 码跨到 FE RX/TX 域采样；或每个域本地 64 位计数器 + 启动对齐（不要求绝对同步，只求差值）。
- **事件点**：
  - `mac_rx_10g` 首字/TLAST（FE RX）：`t_rx_first/t_rx_last`
  - `rx_classify` `m_fast_tvalid` 首字、`tcp_rx` `meta_valid`、`tcp_rx` 载荷首/末
  - `tcp_echo` `fend`/`fwd_rd` 首/末
  - `tcp_tx_frame` `S_IDLE` 启动、首字、末字
  - `tx_arb` 等待拍、`mac_tx_10g` 首字/TLAST
  - 慢路径：`slow_rx_adp` commit、HLS `tx_stream` 首/末、`slow_tx_adp` commit、`tx_arb`
- **存储**：每个事件点一组 `min/max/sum(64 位)/count` + **log2 直方图**（p99），或 64 位时间戳两字；32 位 `sum` 会回卷（§4.5）；**不要**每帧写大 FIFO（会改变时序/面积）。
- **读法**：快照新增字（需新 NW/BID，按观测预算另裁）；或 PCIe BAR 读一个 debug 寄存器组。
- **门**：观测构建必须 `P11_STA_TCB_GATE` + timing gate；计数器不得进数据路径（只读寄存器）。
- **判据**：同一帧的 `t_tx_first - t_rx_first` 为板内驻留；分段差值给出每级；直方图给出 p99。

### 4.4 对端测量草案

- **软件**：`clock_gettime(CLOCK_MONOTONIC_RAW)` 包住 `sendmsg`/`recvmsg`；`SO_TIMESTAMPING` software；`TCP_NODELAY`、`TCP_QUICKACK`、`SO_RCVLOWAT=1`；busy poll（`SO_BUSY_POLL`）。
- **DPDK**：SFC9120 的 `sfc` PMD（需确认 DPDK 23.11 支持）；用 TSC 包住 `rte_eth_tx_burst`/`rx_burst`；对 UDP echo（HLS 慢路径）做控制面基线；TCP 数据面需要用户态 TCP 栈（工程大，先不做）。
- **环境**：`isolcpus`/`nohz_full`/`rcu_nocbs`、`intel_idle.max_cstate=0`、`processor.max_cstate=1`、`pcie_aspm=off`、`cpufreq` performance、`irqbalance` off、IRQ affinity 固定、`rx-usecs 0`/`adaptive-rx off`/`tx-usecs 0`、GRO/LRO 视实验；记录 `PIN_CPU`。
- **SMT**：E3-1275 v3 4C/8T；测试 `nosmt` 对延迟/吞吐的影响（可能降低尾延迟，但减少并行）。

### 4.5 E1 最小观测构建清单（纸面，未实施）

目标：用**最小改动**先回答“板内占多少”，不追求全分段。分两级，第一级不跨时钟域。

**E0.5（零构建，最先做）**：0x32 快照已有 `W65=mac_tx_idle`、`W66=tx_stat_winstall`、`W67=tx_winstall_cap`、`W68=rx_stat_ack_adv`、`W69=tx_win_at_winstall`、`W27/W28`（CDC 占用 max）。在 9G 灌流下取两个相隔 ≥10 s 的快照，算 `ΔW66/ΔW65`（窗口等待占空闲比）、`ΔW65/ΔW5`（空闲占空）、`ΔW67/ΔW66`（阈值归属）、`W28` 占用。**这不能给 p99**，但能先用零成本判断“满载延迟是否窗口/队列主导”；若 `ΔW66/ΔW65` 高（P7b A7 已见 0.88–0.90），则 §5.10 的窗口/BDP 方向优先于流水线优化。**不需要新构建**。

**E0.5 执行结果（2026-10-27，已做，零构建；原件 `_proj_10g/notes/p11_e05_latency_20261027/README_FOR_TL.md`）**：（⛔ 2026-10-27 kimi xr11 审查回灌：W69 判词撤回、扫描伪拍、误差棒/9.49285/52 µs 措辞订正；见同目录 `REVIEW_RESPONSE.md`）
- 4 跑 x 24GB 单口下行（A 口，THREADED sink + lane8，IRQ 4-7，coalescing off），每跑 MID1/MID2 相隔约 10 s，时间基 `ΔW43/156.25MHz`（W43 = tx 拍钟，不是字数）。
- **两个稳定态（同一 bitstream/参数）**：**快态** E05/E05D = 9.4405/9.4437 Gbps，`ΔW65/ΔW43` = **0.143/0.142%**、`ΔW66/ΔW65` = 70.90/71.16%、`ΔW67/ΔW66` = 61.78/61.69%；**慢态** E05B/E05C = 9.2560/9.0701 Gbps，`ΔW65/ΔW43` = **2.035/4.978%**、`ΔW66/ΔW65` = 89.95/92.19%、`ΔW67/ΔW66` = 92.04/93.09%。
- ⇒ **快态下窗口等待只占 0.101% 拍钟**（其中约 1/3 是扫描伪拍；H-1），不能把 P7b A7 的 0.88–0.90 外推到 0x32 满载；它只在**慢态**重现（0.90–0.92）。慢态 92–93% 的等窗拍归属板自己的 `WIN_CAP`（W67），不是对端窗；剩余 7–8% 非板帽侧主要是伪拍（真实对端窗 ≤3.1–3.2 ms，审查估算）。
- `W27/W28` 在 9G 窗口内 **Δ=0**（历史最大 6 / 36 字，256 深 = 2.3% / 14.1%）⇒ 没有 CDC 队列增长证据；但它们是 sticky max，**不能给本窗真实峰值/p99**。
- **`W69` 不可用**（H-1/H-2）：单点锁存 + 扫描拍陈旧 win 样本（win 口晚 1 拍 + 每 16 拍扫描）⇒ W69=0 不能读作“对端零窗”；`0xf53cf000` 是 cap-blocked episode 的采样（42×1460=61,320 < 61,440；43×1460=62,780 ≥ 61,440）。本轮 E05C_MID1 与 E05L L1/L3/L4 = `0xf53cf000`，其余 MID/L = 0；只登记、不作判据。
- **快/慢态翻转机理【未定位】**：6 个连接 = 3 快 3 慢；慢态 ACK/帧 0.13–0.17 vs 快态 0.21–0.23（相关，非因果）；两口 coalescing 已关，排除 P7b #68 的合并帽；无逐包 ACK 见证。假设清单见报告 §3.2（sink 缩窗被 W67 episode 排除；RSS 队列候选未登记；ACK 路径动力学唯一相容但缺对端 pcap；CPU 调度无取证）。
- **E05L/E05M 单连接 60GB 长跑（补跑）**：E05L（慢态）9.1655 Gbps / 52.371 s，4 个窗口 idle 2.892–3.209%、win/idle 90.98–91.15%、cap/win 92.57–92.69%、ACK/frm 0.1667–0.1680；E05M（快态）9.4453 Gbps / 50.819 s，4 个窗口 idle 0.080–0.135%、win/idle 54.05–69.96%、cap/win 19.37–59.39%、ACK/frm 0.2128–0.2134；两者 ΔW27/W28=0、mism=0。⇒ **两种态都能持续 ≥40 s（整条连接），不是瞬态；未观察连接内翻转** ⇒ E1 必须在**不同连接**上重复到各态，不能只靠同一连接长窗。
- 52 µs（61,440 B / 9.44 Gbps）是**整窗排空最坏值**，不是附加等待下界：随机到达附加等待 ∈ [0,52] µs、均值 ~26；前提 = ACK 回路线速/窗口立即重开；**p99 未测**。E1 必须能分辨快/慢态（**不同连接**上重复到各态至少一次；阈值带 1/16 扫描伪拍地板），否则单跑可能把慢态误读成板内流水延迟。

**E1 执行结果（2026-10-27，零构建；原件 `_proj_10g/notes/p11_e1_latency_20261027/README_FOR_TL.md`）**：
- 5 个空载基线 + 5 个 60GB 单口下行（A 口；端口 B 探针 ping/TCP/UDP echo 64/996/1472；探针 CPU2；coalescing off）。**5 个 load 全部 slow 态（8.60–9.25 Gbps），未采到 fast 态**。
- p99（base → load，µs）：ping **47–83 → 50–112**；TCP **300–336 → 110–187**；UDP64 **169–262 → 104–180**；UDP996 **607–612 → 434–505**；UDP1472 **777–782 → 602–671**；全部 0 丢包。
- ⇒ **9G 慢态负载没有抬高 HLS 控制面 p99**（负载下反而更低；机理【未定位】）；HLS 服务时间（64B ~0.1 ms、996B ~0.4 ms、1472B ~0.6 ms）是尾延迟主项，不是 9G 排队。
- **fast-path 单包延迟仍未测**（探针走端口 B 的 HLS；A 口 fast-path 数据帧无逐包时间戳）⇒ **E1a 仍必要**。
- **E1 新发现（已登记未修）**：HLS UDP echo 精确上限 **996 B**（`TX_UDP_BASE=512` + 256 words = 1024 B，减 28 B IP/UDP 头）；≥997 B 回包长度不变但 offset ≥996 全为 0（`E1_UDP_ECHO_SIZES.txt`）⇒ 此前“1500B UDP echo”只测延迟、内容未校验；`udp_echo.cpp:203-207` 无界拷贝。
- 快态 E1 / 同口探针 / fast-path p99 = **未测**。

**E1a（最小，只测 DP 域；推荐先做；⛔ 不是“几百 FF”的小改）**
- ⚠️ **H-1 强制推论**：E1a 若要解析快态窗口等待，必须带“扫描 polluted 拍”标记/计数器，或在 E1 阈值里减 **1/16 伪拍地板**；否则伪拍会被计入“等对端窗”（快态 ≈ΔW20/16、慢态 ≈ΔW66/16）。
- 一个 `dp_clk`（156.25MHz）**64 位自由计数器** `ts_ctr`；事件采样在 DP 域内，不跨域。
- 事件点（都在 `dp_clk` 域）：
  - `u_rxcdc` 读口首字 / `rx_classify` 入口（DP RX 起点）
  - `tcp_rx` `meta_valid`（数据帧头解析完）
  - `tcp_echo` `fend` / `S_FWD` 首字（echo 起转）
  - `tcp_tx_frame` `S_IDLE→S_*` 启动拍 / 首字输出
  - `u_txcdc` 写口首字（DP TX 终点）
  - HLS 慢路径：`slow_rx_adp.stat_commit` / `slow_tx_adp.stat_frames` 是 **32 位计数器，不是脉冲**（`rtl/slow_rx_adp.v:56,240`；`rtl/slow_tx_adp.v:32,307`）⇒ 用**增量**做事件；`tx_arb` **没有慢口 grant 输出**（`rtl/tx_arb.v` 端口表），必须新增 tap。另采 `slow_rx_adp.stat_drop`、`slow_tx_adp.stat_purge`、两适配器 occupancy、`hls_rst_n`/`dbg_starv`，否则只测到“成功帧”、拥塞/看门狗复位被样本选择掩盖。
- **同帧/同端口 tagging**：至少给事件加 `frame_id` + `port` + `conn_id`；C4 是双口共享一份 HLS，没有 port 标签就无法归因 `slow_merge2`/`slow_demux2` 的跨口排队。单对全局 `start_ts` 在多帧在飞/ACK 插入时会跨帧错配。
- 统计：`min/max/sum/count` **给不出 §1 要求的 median/p99**；加 log2 直方图（如 16 桶）或小规模采样环；定义窗口清零/有效位。`sum` 用 64 位（32 位在 27.5 s 内回卷，全局 #55），delta 32 位足够（单帧 <<27.5 s）。
- 读法：现有 `axi_regs` 快照新增 8–16 字（新 `SNAP_NW`/BID），或 lab 用 VIO。⚠️ **新增快照字约 96 FF/字**（P11 既有：`snap_cdc.hold_b` + `dout_a` + `snap_words_r` 三份）⇒ 8–16 字就是 **768–1536 FF**，不是“几百 FF”；必须复用 `snap_cdc`/`hold_b`，不能顶层直连（P11 0x2C 的 F-21 直连陷阱），并加“top5/所有新字必须经过 hold_b”的静态 + 综合后 fanout 门。VIO 读 64 位自由计数器有多比特撕裂 ⇒ 只读稳定锁存值或 Gray/握手。
- 时序：0x32 全局 WNS 仅 **+0.019 ns**；E1a 计数器 + 6 个 64 位事件采样 + 4 组统计 + 快照字远超“几百 FF”，必须跑**完整 timing gate**（不只 `P11_STA_TCB_GATE`），并定向看 DP/pcie 异步复位族。
- 覆盖边界：E1a 不含 MAC/PCS/PHY/SFP；**M6 板内 MAC 环回标定的是 RX+TX 往返**（还含环回路径），不能直接加到 E1a 得到单程 `L_board`。要么用 E1b 的 FE SOP/TLAST 时间戳，要么分别标定 RX/TX 单向固定延迟。

**E1b（跨域，后做）**
- FE RX/TX 域（`rx_clk_out_*` / `tx_mii_clk_*`，156.25MHz 恢复钟）需要 `mac_rx_10g` SOP/TLAST 和 `mac_tx_10g` SOP/TLAST 的时间戳。
- 跨域方案二选一：① **64 位 Gray 码计数器**从 `dp_clk` 同步到 FE 域（同频异相，2 级同步 + Gray 保证多比特一致）；② **事件握手**（FE 域锁存事件，`dp_clk` 侧读走并回 ack），事件率 <1M/s，握手开销可接受。**不要**直接对 64 位二进制计数器做 2 级同步（多比特不一致）。
- 只对“每帧第一个/最后一个事件”做，不要每拍采样；否则 CDC 带宽爆炸。

**E1 判据（先写死，避免“测了再找解释”；已按 xsim 14–21 µs / 303 µs 更新）**
- ICMP ping 板内 `L_board` **≤5 µs** ⇒ 与 xsim 的 HLS-only 14–21 µs **矛盾**：先查 TB/事件点/标定（不要据此判“控制面不是问题”）。
- **14–30 µs** ⇒ 与 xsim 同量级；控制面硬件化可省其中大部分（还要扣适配器/仲裁已有开销），E3 在 E0 之后**值得做**。
- **>40 µs** ⇒ 适配器/仲裁/排队/其他路径占主导；先按 `slow_merge2`/`slow_demux2`/`tx_arb`/HLS `frame_fifo`/`stats_report`/看门狗逐项查，再谈 E3。
- 1500B UDP echo 8080 的 `L_board` **≥300 µs** 才与 xsim 303 µs 一致；若明显更低，先确认是否真的走 HLS（而不是 fast path/端口 8081），或事件点漏了适配器整帧缓冲。
- TCP echo 1500B 的 `L_board` **≥4 µs** ⇒ 缓冲合并（§5.2-8）才有意义；若实测 <3 µs，纸面高估，先别动 RTL。

---

## 5. 候选方向（按“杠杆/代价/风险”分层）

### 5.1 控制面硬件化（xsim 实测后**回升**；仍待 E1 板级定量）

**现状**：`rx_classify` 把 TCP 控制帧（SYN/FIN/RST）和非 TCP（ARP/ICMP）全部送慢路径（`rtl/rx_classify.v:99-107`）；慢路径经 `slow_rx_adp`→HLS `udp_echo`→`slow_tx_adp`，HLS 逐字节 FSM + 帧级适配器。ping RTT 73–188 µs；0x32 SYN-ACK `win=49152`、无 wscale。

**方向**：
1. **硬件 ARP 应答器**：解析 who-has，查小表（IP→MAC），直接构造 reply；1–2 帧时间；不经过 HLS。预期把 ARP 解析从 HLS 的数十 µs 降到 <1 µs；但 ping RTT 还含对端软件。
2. **硬件 ICMP echo 应答器**：swap MAC/IP、重算 IP/ICMP checksum、回发；同样绕过 HLS。**与 ARP 同批**可覆盖 ping 全链。
3. **硬件 TCP SYN/SYN-ACK**：在 RTL 分配 TCB 槽、生成 SYN-ACK（含 MSS/WS/SACK 选项）、把 cfg 写 TCB/CAM；数据面照旧。**建连 RTT** 的板内 HLS 段可从 xsim 的 14–21 µs 降到 ~1–2 µs；但需处理重传/半开/backlog/选项，工程大。
4. **只优化 HLS**：减少 HLS 主循环每 pass 的工作、去掉不必要的 `tcp_active_tick`/`stats_report`、缩短 RX/TX 适配器帧缓冲、把 ARP/ICMP 在 HLS 里提前处理。收益小但风险低；需先测 HLS 驻留。
5. **SYN cookie / backlog**：防半开占满 TCB；不直接降延迟，但避免建连排队。

**预期/风险（2026-10-26 按 §3.4 **xsim 实测**订正）**：
- **xsim 实测（P3 网表，HLS-only）**：ARP 小帧 **14.1 µs**、UDP 74B **20.6 µs**（last→last），不是 1–3 µs；板级还要加适配器/仲裁。⇒ 硬件化 ARP/ICMP 的**收益下界 ≥14–21 µs（HLS-only 下界；板级可能更高）**，控制面硬件化**重新成为有分量的候选**；但仍须 E1 板级测出“HLS 在 ping RTT 中占多少”再决定。
- **真正的大 HLS 项 = 1500B UDP echo（8080）303 µs（xsim，HLS-only）** ⇒ 低延迟大帧 UDP **必须**改走 fast path（端口 8081）或 RTL echo；不是优化 HLS 循环能救的。
- 硬件 ARP/ICMP 与 HLS 双实现有**语义分叉**风险（ARP 表/老化/广播/代理 ARP），需要单一来源或明确边界。
- SYN 硬件化涉及 TCB/CAM/窗口/选项，风险高；xsim 下界 ~14–21 µs（SYN 未单独测），优先级仍应低于 E0/E1。
- 0x32 时序余量 0.019 ns；任何新逻辑先过 TCB gate + 完整 timing gate。

### 5.2 数据面缓冲/流水

**现状**：`tcp_echo` 整帧缓冲（源码注释），`tcp_tx_frame` 整帧缓冲 + checksum；CDC 256 深；MAC RX/TX 16 深。

**方向**：
1. **CDC 深度扫描**：256→128/64/32；在 2×9G 下测 `W27/W28` occupancy 与吞吐/延迟；若 occupancy 峰值远低于 64，缩小可省队列延迟（每字 6.4 ns；256 字最坏 1.64 µs）。
2. **时钟域合并**：让 DP 直接使用 PCS `rx_clk_out`（或统一 156.25），去掉 RX CDC；TX 仍跨到 `tx_clk_out`，或使用 PCS 弹性缓冲。风险：PCS 时钟/用户时钟关系、时序、复位；**先做时钟架构研究，不实施**。
3. **分类提前**：当前 `rx_classify` 到第 6 字才判 TCP 控制/数据；若把“所有 TCP”先送 fast path，由 fast path 的 SYN 硬件处理器接管控制帧，则分类只需 2–3 字，省 ~3 字（19 ns）；与 5.1-SYN 绑定。
4. **`tcp_echo` 小帧快路径**：小帧整帧缓冲成本低（64B=51ns），不必改；大帧的 1.2µs 是结构下限，除非放弃 TCP checksum/FCS 正确性。
5. **`tcp_tx_frame` checksum 流水**：**已经**在载荷写入 FIFO 的同时并行计算 checksum，TLAST 后仅 `S_WAIT` 0..4 = **5 拍**落定（`rtl/tcp_tx_frame.v:2581-2586`），不是整帧再等；无需再改。
6. **`tx_arb` 帧级锁定**：`tx_arb` **无 aging/预留窗**（`rtl/tx_arb.v:2-4,42-50`），控制帧可能**连续等多个 fast 帧**，不是“最坏一个 1500B 帧 = 1.2 µs”；以太网帧不可抢占（除非 802.3br），只能给控制帧更高优先级/预留间隙，或加 aging。当前 fast 优先于 slow，控制帧走 slow，数据 fast 会压控制帧 ⇒ 控制帧延迟被数据帧阻塞。可考虑：ACK/控制帧走高优先级队列、帧间预留控制窗口、或 `tx_arb` aging；但会牺牲吞吐。
7. **MAC TX 16 深 FIFO**：已接近 cut-through；不需要改。
8. **合并 `tcp_echo` 与 `tcp_tx_frame` 的整帧缓冲（研究，未实施）**：当前 `tcp_echo` 整帧进 `frame_fifo`、`fend` 后才 `S_FWD`（`rtl/tcp_echo.v:88,142-177`），读出的同时**就在写** `tcp_tx_frame` 的 FIFO（`board/wrapper_p4.v:2544-2552`），`tcp_tx_frame` 在 TLAST 后约 5 拍 `S_WAIT` 等 checksum 落定（`rtl/tcp_tx_frame.v:2581-2586`），**不是**再额外花 1.2 µs 填 tx FIFO。按首→末字节：RX 1.2 + echo 读出 1.2 + TX 1.2 = **≈3.6 µs**（另加流水/CDC ~0.2–0.6 µs）。若让 `tcp_echo` 在接收的同时直接流入 `tcp_tx_frame`（由后者在 TLAST 后即发，并支持 `ferr`/坏帧 rollback），可省掉 echo FIFO 的整帧读 ≈1.2 µs @1500B ⇒ 下界约 **2.4 µs**。风险 = 坏帧回卷/半帧中止/ACK 优先/零窗；必须先有 xsim 门与定向 STA。
9. **`udp_tx_frame` 的 cut-through（研究，未实施；⛔ 现状前提不成立）**：当前模块**没有** cut-through —— IP `total_len`/UDP length 与 IP checksum 都在 TLAST 拍才锁存/计算（`rtl/udp_tx_frame.v:537-571`），帧头在 `:576-604` 才发；`cfg_csum_en=0` 只把 **UDP checksum** 置 0（`:282,578`），不能省掉 TLAST；板级还把 `cfg_csum_en` 硬接 1（`board/wrapper_p4.v:3661,4078`），没有运行时置 0 的路径。长度守卫 `PLEN_MAX` 当前是**整帧 abort + flush、一个字节都不发**（`:181-182,556-565`），而 `mac_tx_64` 会给实际发出的帧算**正确 FCS**（`rtl/mac_tx_64.v:3-8,55-58`）⇒ 超长帧若放过去会是“有效 FCS 的巨帧”，不是坏 FCS。**要做 cut-through，必须新增一整套契约**：帧首长度 sideband（或固定最大长度）、IP checksum 提前计算、`cfg_csum_en=0` 的真实运行路径、最小帧 pad/FCS/超长 abort 语义、`udp_tx_cfg` 冻结、多端口路由。收益仍是 1500B ≈1.2 µs / 100B ≈0.08 µs，但**风险/工程量远大于“加一个分支”**；不是当前可直接落的一刀。

**预期/风险**：CDC 缩深/时钟合并的收益是**亚 µs**；不要期待解决 100 µs 控制面。缩小 FIFO 会增加 underrun/丢帧风险；必须在 2×9G 下验证。

### 5.3 TCP 协议/栈参数

**现状**：HLS 明确“不通告 WS”（`hls/src/layer_tcp.cpp:63/236/313`）；fast path `snd_wnd` 16 位、`WIN_CAP=0xF000`；SYN-ACK `win=49152`、`mss 1460`；`tcp_rx` 每数据段回 ACK；echo 用 `cfg_suppress_data_ack` 抑制纯 ACK。

**方向**：
1. **Window scaling**：HLS 因 P4b-6 死锁前科移除 WS；0x32 SYN-ACK 实测 `win=49152`、options 仅 `mss 1460`（`raw/SYN_OPTS.txt` / `SYN_P0.txt`）。对端 SYN 带 `wscale 10` 但**未被确认** ⇒ 双方都不缩放；对端通告窗被 16 位字段硬顶（实测 `win 64240`）。板侧 fast path `snd_wnd` 16 位、`WIN_CAP=0xF000=61,440`。⇒ **板→对端发送窗 ≈61,440 B**；单口 9.395G 隐含 `61440/9.395G≈52.3µs`（纸面换算式，不是 RTT 测量）。若数据 RTT >52µs，吞吐会被窗帽住；若恢复 WS，必须同时把 `tcb`/`tcp_tx_frame` 的 snd_wnd 扩到 >16 位并验证 P4b-6 的“通告被放大 128× 塞满管道”死锁前科。**收益是吞吐/RTT 容忍，不是单包延迟**；大窗可能增加 bufferbloat/尾延迟。研究，不实施。
2. **Initial window / slow start**：HLS `c.cwnd=c.peer_mss`（`layer_tcp.cpp:662`）⇒ 初始 1 MSS；短流建连后慢启动会增加完成时间。RFC 6928 IW10 可降低短流延迟；但板侧 cwnd 只影响板→对端，sink 侧 Linux IW10 已默认。研究。
3. **Delayed ACK / QUICKACK**：板 `tcp_rx` 对每个数据段回 ACK（低延迟、较多流量）；对端 Linux 可能延迟 ACK。对端测试加 `TCP_QUICKACK`/`TCP_NODELAY`；板侧已有 `cfg_suppress_data_ack`。
4. **RTO / 重传**：P7b `RTO_LIM=20ms`；丢包时 20ms 停摆。SACK/RACK/TLP 可降低恢复延迟，但 HLS 选项/状态机工程大；先测丢包场景。
5. **TSO/GRO/coalescing**：对端关闭 coalescing（已做）；GRO 可能增加延迟，测试关闭。
6. **Jumbo frames**：9000B 减少帧数/中断，可能降低大流量尾延迟；但增加单帧串行（7.2 µs），对小消息无益；需按业务权衡。
7. **TCP Fast Open / SYN cookies**：建连延迟/半开；研究。

**风险**：任何 WS/窗口改动都可能重现 P4b-6 死锁；必须有小流量/零窗/重传回归，且 fast path 16 位扩展是大改。

### 5.4 应用/生成器

- `app_pattern` 8B/cycle 生成（约 10G 上限）；对**发送延迟**，生成一帧 1500B 需 ~190 拍（1.2 µs）后才能交给帧器；若应用是“请求-响应”而非连续流，这 1.2 µs 进入关键路径。可用更宽的生成（16B/cycle）或预生成/双缓冲；`app_udp_pattern` 已有 8 路。
- `tcp_echo` 是硬件 echo；对端应用/内核仍是主延迟。
- `app_rx_mirror`/PCIe 观测路径不参与业务；若未来业务走 PCIe，另算。
- **控制面 app**：HLS 的 `TX_PACING_COUNT = 625,000,000`（`hls/src/eth_types.h:222`）只在 `udp_tx_process` 里**每 pass** `time_cnt++`（`layer_udp.cpp:126`），不是每时钟；按 ~20 拍/pass 估 **HELLO ≈80–100 s**（纸面），不是 4.0 s。UDP echo 在 `layer_udp.cpp:111` 明确“reply immediately”，不等 pacing（`:127` 才是 HELLO 分支）。⚠️ 旧版“2.048 µs”和“4.0 s”两个口径都错，已订正；不要误改该常数。

### 5.5 PCIe 数据通路（若业务走 PC）

- 当前 XDMA 用户接口 **AXI-MM → AXIS**（P9），C2H/H2C；PCIe link 实测 **5GT/s x4（PCIe 2.0 x4）**，不是 Gen3。
- 延迟组成：BAR/描述符写入 → XDMA 引擎 → AXIS → 板内；C2H 反向。未测。
- 方向：MSI-X 中断合并关闭、描述符批处理/环大小、`O_NONBLOCK`/poll、AXIS 背压、URAM 缓冲（已有 `mir_uram_fifo` 32KB 观测件）；DPDK/`vfio` 用户态；PCIe ASPM 关闭；大 TLPs。
- **注意**：M1 镜像/URAM 是观测路径，不要当业务低延迟通路；若业务要 PCIe，需要独立设计。

### 5.6 对端主机/软件（通常是最便宜的杠杆）

- **中断合并**：历史 `rx-usecs 60` 可加 ~60 µs；已在本轮板测关闭。任何延迟读数必须记录 `ethtool -c`。
- **C-states / P-states**：`intel_idle.max_cstate=0`、`processor.max_cstate=1`、`cpufreq` performance；可显著降低唤醒延迟（tens of µs）。
- **IRQ affinity / irqbalance**：固定 NIC IRQ 到非业务核；`irqbalance` off；`taskset`/cpuset；避免 IRQ 与 sink 线程抢核（本轮 0x32 双口已实测核冲突，见 `raw/D_A/D_B`）。
- **SMT**：`nosmt` 可能降低尾延迟；测试。
- **NAPI/busy poll**：`SO_BUSY_POLL`、`net.core.busy_poll`；`SO_PREFER_BUSY_POLL`；`SO_INCOMING_CPU`。
- **TCP**：`TCP_NODELAY`、`TCP_QUICKACK`、`SO_RCVLOWAT=1`、关闭 `TCP_CORK`；`tcp_notsent_lowat` 影响发送延迟。
- **qdisc**：`mq`/`noqueue`；避免 `fq_codel` 排队（对延迟敏感）。
- **内核旁路**：DPDK/AF_XDP；SFC9120 支持需核实；可把“台架延迟”降到 µs 级，但仍不是板内。
- **PCIe ASPM / power**：`pcie_aspm=off`、`pcie_port_pm=off`。
- **虚拟化/容器**：无。

### 5.7 PHY/光模块/板级

- SFP+ 模块/AOC 的固定延迟未测；更换低延迟模块可能有效但不可控。
- 10GBASE-R 无 FEC；64b/66b gearbox 固定；GTY RX/TX 延迟固定。
- 板对板连接器/PCB 是 SI 问题，不是延迟；但 re-timer/gearbox 会增加。
- **不要在 PHY 上先投入**；先测板内/对端。

### 5.8 P3/双栈特有（本轮新增的延迟面）

P3 C4 相对 P7b 单栈新增：两套同模块快路径、共享 96KB 池 `win_pool_mgr`、共享 8 槽 retx、慢路径 2:1 merge / 1:2 demux、第二个 app 实例。对延迟的影响要分开看：

| 新增件 | 是否在数据帧热路径 | 延迟影响 | 备注 |
|---|---|---|---|
| `win_pool_mgr` 三拍事件机 | **否**（建连/配额/释放） | 建连/配额事件 +3 拍（19 ns）+ 事件 FIFO 排队；不碰数据帧 | 0x32 板级 ping/数据正常；不因它变慢 |
| 共享 retx 8 槽 | 仅重传路径 | 2 拍读延迟；正常无重传时不进路径 | 0x32 W55 很小 |
| `slow_merge2`/`slow_demux2` | 仅慢路径（控制面） | 帧级 RR/锁存；控制帧可能多等 1 帧 | ARP/ICMP/SYN 延迟的候选之一 |
| 第二个 `app_pattern` | 数据生成侧 | 每口独立；共享 `tcp_tx_frame`? 否，每口一套 | 两连接同时已证 8.8/8.9G |
| 共享池 48KB/连接 | 数据面窗口 | 不是延迟直接项；但 48KB 窗在 RTT > 39µs 时会限吞吐（10G） | 0x32 实测 9.4G 隐含 RTT ~52µs；61,440 帽更紧（见 §5.3） |
| 两个 app_ctrl/init 队列 | 建连 | init 等 `ev_up_done`；若 done 丢失，连接静默（M-5 已挂）；不碰已建连接数据 | 0x32 清洁重连 B 两次正常；早期非清洁会话曾见 B 0 字节，重烧后未复现（【未定位】） |

**P3 特有测量建议**：
- 同一 ping 分别打**只有端口0有连接**、**端口0+端口1都有连接**时的 p0/p1 RTT，看慢 merge/demux 的排队贡献。
- 两连接同时 9G 时，测**第三个连接**的 SYN/ARP 延迟（控制帧在 `tx_arb` 里被 fast 数据帧压）；这是“控制面尾延迟”的直接场景。
- 两连接同时 9G 时，测 ping（ICMP 走慢路径）的 p99；若明显高于空载，说明 `tx_arb`/慢路径被数据压，候选改法是控制帧高优先级/预留窗口。

### 5.9 架构级替代（研究，不实施）

1. **UDP 低延迟通路**：UDP IPv4 checksum 可置 0，允许 **cut-through**（无 TCP 校验和/ACK/窗口）；若业务允许 UDP，可把 echo/转发延迟降到 ~1 帧串行 + 流水。风险：无重传/拥塞控制；需应用层可靠性。
2. **RoCEv2 / 硬件 RDMA**：FPGA 实现 RoCEv2 栈，绕过内核 TCP；低延迟高吞吐；工程极大，且需要支持 DCB/PFC/ECN；不是当前产品范围。
3. **PCIe P2P / 共享内存**：若 PC↔FPGA 是主路径，PCIe DMA 比网络栈低延迟；但产品要求 SFP 网络。
4. **TSN/802.1Qbv**：调度保证，不降低单包处理延迟；可能降低排队尾延迟。
5. **PTP/1588 硬件时间戳**：不是降低延迟，而是**测量**；当前 SFP/NIC 无硬件时钟；FPGA 可加。
6. **Cut-through 交换机式转发（C2 镜像）**：FCS 正确性需要整帧缓冲；镜像口可接受“先转发后 FCS 丢弃”的应用才可 cut-through；需明确语义。

### 5.10 负载下的尾延迟（queueing；**空载延迟不能代表满载**）

前面 §3.3 的 ~3.6–4.5 µs（TCP echo，纸面）与 §3.4 的 **14–21 µs（HLS 小帧）/ 303 µs（HLS 1500B UDP echo）（xsim，HLS-only）** 都是**空载/单帧**数。真实低延迟业务通常在**线速或高负载**下运行，此时尾延迟由排队决定，而不是流水线：

- **`tx_arb` 帧级等待（无 aging）**：fast 数据帧严格优先，`tx_arb` **没有 aging/预留窗**（`rtl/tx_arb.v:2-4,42-50`）；慢帧可能连续等多个 fast 帧，**不是“最坏一个 1500B 帧 = 1.2 µs”**。P7b 板级“UDP 泛洪 300 s 中 ping 5/5、TCP 建连成功”（`p7b_udp_longrun_20261009/tables.txt:59-61`）只证**通/不通**，不是延迟上界；E1/E11 在 9G 负载下测 ping/SYN 的 p99 才能定量。
- **E1 实测（2026-10-27，零构建；慢态 8.60–9.25 Gbps）**：端口 B 的 ping/TCP/UDP echo p99 在 9G 负载下**不高于**空载基线（TCP 300–336→110–187、UDP996 607–612→434–505、UDP1472 777–782→602–671 µs；ping 47–83→50–112）；0 丢包。⇒ **HLS 控制面未被 9G fast-path 饿死**；尾延迟主项 = HLS 服务时间（~0.1/0.4/0.6 ms），不是负载排队。⛔ **fast-path 单包延迟仍未测**（探针走 B 口 HLS；A 口无逐包戳），E1a 仍必要；**快态 E1 未采到**。另：HLS UDP echo 精确上限 996 B（≥997 B 回填 0），此前 1500B UDP echo 内容判据为空。
- **窗口/BDP（TCP 最大的负载相关项，但必须分态）**：P7b A7 板级三跑 `ΔW66/ΔW65` = **0.876 / 0.899 / 0.881**（TX 空闲里 88–90% 是“只差 `wnd_open` 这一格”），跨 5.7–9.3 Gbps 稳定（`p7b_a7_board_20261010/`；`p7b_buildE_board_20261010/`）。⚠️ **0x32 E0.5（2026-10-27）改写**：4 跑 24GB 单口下行里，**快态**（9.44G）`ΔW66/ΔW65` = 70.9/71.2%、等窗仅 **0.101% 拍钟**；**慢态**（9.07–9.26G）才到 89.95/92.19%、等窗 1.83/4.59% 拍钟，且 92–93% 归属板帽侧。⇒ 快态下窗口/BDP **不是吞吐墙**，但 61,440 B 在飞上限使随机到达的新消息附加等待为 **[0,52] µs、均值 ~26**（52 µs = 整窗排空最坏值，不是下界）；慢态下窗口门是空闲第一来源。⚠️ 快态等窗 0.101% 中约 1/3 是扫描伪拍（H-1），非板帽侧列含伪拍、不能当对端窗；E1 阈值带 **1/16 伪拍地板**。**快/慢态机理未定位，E1 必须分连接重复**。**空载 ping 的 73–188 µs 不能外推到满载**。
- **CDC/适配器占用**：`rxcdc`/`txcdc` 256 深 = 1.64 µs 最坏；0x32 终态 `W27=6` / `W28=36` 字（`FINAL_STATE_0x32`）。⭐ **0x32 E0.5（2026-10-27）在 9G 窗口内实测 `ΔW27=ΔW28=0`**（历史最大仍 6/36 字）⇒ **没有 CDC 队列增长证据**；但它们是 sticky max（不是 p99 占用），且不能给本窗真实峰值。E2 仍需要在 9G 下采 `W27/W28` 的实时 max/p99（现有快照只有 sticky max；要 p99 需新观测口）。
- **对端 ACK/中断节奏**：对端 `rx-usecs`/NAPI/quickack 会改变窗口重开时刻；同一条板内流水，对端合并 60 µs 就能让“端到端 RTT”多 60 µs（P7b 已实测 coalescing 是“读数低”第一主因，`p7b_longflow_board/ACCEPT.md`）。
- **结论（研究口径）**：延迟目标必须分**空载单帧**与**满载 p99** 两档；TCP 在 61,440B 窗 + ~52 µs RTT 下，满载低延迟与 9.4G 吞吐是**结构性 trade-off**（要低延迟就得小窗/低在飞量，要大吞吐就得大窗/排队）。若业务要求“10G + 低尾延迟”，UDP（无窗口、可 cut-through）或更大 BDP + 拥塞控制才是正确方向；这不是改 `tcp_echo` 流水能解决的。**待用户定义目标（§9-11）**。

---

## 6. 实验路线（建议顺序；均未开工）

| 阶段 | 实验 | 产出/判据 | 依赖 |
|---|---|---|---|
| E0 | 对端环境基线：coalescing off、C-state、IRQ affinity、SMT、busy poll 的 A/B；ping/TCP echo 软件 RTT | 分离“对端软件”下限；记录 `PIN_CPU`/`rx-usecs` | 无 |
| E1 | FPGA 驻留计数器（M1/M2）观测构建（BID 新；观测 only） | `L_board` 控制/数据；**重点：ICMP 小帧 / ARP / SYN / 1500B UDP echo 8080** 的分段差值；p99 | 时序门 |
| E2 | CDC/FIFO 深度扫描（不改产品，先读 occupancy W27/W28；再评估缩深） | 队列延迟 vs 吞吐；是否可缩到 64/32 | E1 |
| E3 | 硬件 ARP/ICMP 原型（独立模块/门；先 xsim + synth） | 控制面 RTT 变化；与 HLS 语义对照；**E1 测到 ICMP 板内 14–30 µs 时值得开工**（xsim HLS-only 14–21 µs） | E1 证明板内占比 |
| E4 | 硬件 SYN/SYN-ACK 研究（TCB/选项/backlog） | 建连 RTT；半开/重传/选项回归；**优先级低于 E0/E3**（xsim 同族 HLS-only ~14–21 µs，但工程大） | E3 |
| E5 | 分类提前 + TCP 控制帧优先级/预留窗口 | 控制帧被数据帧阻塞的尾延迟 | E3 |
| E6 | TCP 参数 A/B（IW10、QUICKACK、GRO、jumbo） | 短流完成时间/尾延迟；吞吐不降 | 对端 |
| E7 | UDP cut-through 可行性（checksum 0；镜像/转发语义） | 单帧延迟下界；正确性/丢包 | 独立 |
| E8 | 时钟域合并研究（PCS rx_clk 统一/弹性缓冲） | 时序/资源/CDC 延迟预算；不实施 | 架构评审 |
| E9 | PCIe 数据通路延迟（若业务需要） | DMA/中断/描述符延迟 | P9 件 |
| E10 | 2×9.4G 同时的台架方案（第二对端/DPDK；IRQ 兄弟核已到 8.8/8.9G） | 2×9.4G 同时吞吐；尾延迟 | 硬件 |
| E11 | **负载尾延迟**：9G 灌流时测 ping/SYN/小消息 p99；同窗读 `W27/W28/W66/W67`；压窗/开窗两臂 | 尾延迟 vs 窗口/CDC/仲裁；分离“流水”与“排队” | E1/E2 |

**门**：每个 RTL 实验必须：
1. 先 xsim 单元/全链门（不在跑 Vivado 时并行）；
2. synth `P11_STA_TCB_GATE`（A–F ≥0）+ timing gate；
3. 板级同会话 A/B（同 bitstream/路径/sink 配置）；
4. 记录 `PIN_CPU`/`rx-usecs`/负载档；
5. 不改变 FCS/TCP checksum 正确性（除非明确产品语义变更）。

---

## 7. 预期收益/代价（纸面 / xsim；禁止当板级结论）

| 方向 | 预期收益 | 代价/风险 | 置信度 |
|---|---|---|---|
| 对端 C-state/coalescing/IRQ 调优 | **可能数十 µs**（若当前未调） | 低；环境相关 | 中（coalescing 历史已见 60µs 量级） |
| 硬件 ARP/ICMP | **收益下界 ≥14–21 µs（xsim，HLS-only；板级还要加适配器/仲裁）** | 中；语义分叉/ARP 表 | 中–高（xsim 实测；待 E1 板级） |
| 硬件 SYN/SYN-ACK | **收益下界 ≥14–21 µs（HLS-only；SYN 未单独测）** | 高；TCB/选项/backlog/重传 | 中（xsim 同族外推） |
| CDC 缩深/时钟合并 | 亚 µs（固定 ~20ns + 队列） | 中；时序/CDC 风险 | 高（机制清楚，收益小） |
| 分类提前 | ~19 ns | 低–中；需 SYN 硬件化 | 高（收益小） |
| TCP echo **缓冲合并**（非 cut-through） | 1500B **≈1.2 µs**（≈3.6 → ≈2.4 µs） | 中；坏帧回卷/ACK 优先 | 中（§5.2-8 纸面） |
| TCP 真 cut-through | **不可行**（TCP checksum 覆盖全载荷） | 正确性 | 高（结构） |
| HLS 8080 的 1500B UDP echo | **303 µs（xsim，HLS-only）** ⇒ 低延迟大帧必须走 fast path/8081 或 RTL echo | 低（改走别路） | 高（xsim 实测） |
| UDP cut-through | 收益 1500B ≈1.2 µs / 100B ≈0.08 µs，但**当前模块无长度 sideband/IP checksum 提前/运行路径** ⇒ 需新契约 | 高；长度 sideband/IP checksum/超长语义/cfg 冻结 | 低（§5.2-9 已证现状前提不成立） |
| TCP WS/IW10 | 吞吐/RTT 容忍；短流完成时间 | P4b-6 死锁前科；大改 | 中（需回归） |
| 应用生成加宽 | 1.2µs/帧生成 → 0.6µs | 资源/时序 | 中（仅生成侧） |
| PCIe 低延迟 | 若业务走 PCIe，可省网络栈 | 需独立设计 | 未测 |

---

## 8. 风险/约束（必须写进任何后续设计）

1. **0x32 时序余量 0.019 ns（0.297%）**：任何 RTL 延迟优化都可能把 TCB 族推负；先跑 `board/p11_sta_tcb_probe.tcl`（A–F，阈值 0.0）。
2. **正确性**：TCP checksum/FCS 不能为了 cut-through 放弃；坏帧/重传/零窗/半开必须有门。
3. **吞吐不许回退**：任何 FIFO 缩深/优先级改动必须在 2×9G（或单口 9.4G）下 A/B；当前单口 9.395G 是锚。
4. **观测本身不能改变延迟**：计数器只读、不打数据路径；新快照字可能吃时序（P11 backstop 史）。
5. **对端台架是变量**：coalescing/C-state/IRQ/核冲突可淹没板内收益；所有读数带环境见证。
6. **不要用 `ss minrtt` 当数据 RTT**（P7b C8 已定案）；不要用吞吐反推 RTT 当测量。
7. **2×9G 同时已到 8.8/8.9G（17.72G 聚合，IRQ 兄弟核 + taskset）；2×9.4G 线速同时未判定**：先解决台架（第二对端/DPDK），否则不要用同时臂评延迟/上限。
8. **HLS 语义分叉**：硬件 ARP/ICMP/SYN 与 HLS 版本必须双跑/单来源，避免两个栈行为漂移。
9. **研究件不是实施授权**：本件所有方向都需用户/评审裁定后才开工；不要顺手改 RTL。
10. **空载/满载不可混读**：§3.3 是空载单帧纸面（TCP echo ≈3.6–4.5 µs），§3.4 是 xsim HLS-only（小帧 14–21 µs、1500B 303 µs）；满载 p99 另由 `tx_arb`（无 aging）等待、窗口/BDP、CDC 占用、对端 ACK 节奏共同决定（§5.10）。任何延迟验收必须写清负载档、窗口、对端 coalescing；**不要用空载 ping 的 73 µs 推断满载业务延迟**，也不要用吞吐反推 RTT。

---

## 9. 开放问题（必须先答）

1. ping RTT 73–188 µs 中，**板内 vs 对端软件**各占多少？——E0/E1；**xsim 下界** HLS 小帧 14–21 µs（HLS-only），板级还要加适配器/仲裁；host 仍是候选主项，但不能再写 <5%。
2. TCP echo 1500B 的板内驻留实际是多少？——E1；纸面 ≈3.6–4.5 µs（§3.3；不是 4.8）。
3. CDC 256 深在 9.4G/2× 下的实际 occupancy/p99 是多少？——W27/W28 + E2。
4. `tcp_echo`/`tcp_tx_frame` 的帧级缓冲是否是主要板内项？——E1 分段；纸面 ≈3.6 µs，缓冲合并可省 ~1.2 µs（§5.2-8）。
5. ARP/ICMP/SYN 的 HLS 驻留各多少？——E1 慢路径分段；**xsim 实测** ARP 14.1 µs、UDP 74B 20.6 µs（last→last，HLS-only）；SYN/ICMP 未单独测，同族外推。
6. 1500B UDP echo（8080）是否实测 ~303 µs（xsim，HLS-only）？——E1 板级确认；低延迟 UDP 必须绕开 HLS（§3.4/§5.9）。
7. UDP cut-through 是否值得做？——当前模块无长度 sideband/IP checksum 提前/运行路径，需新契约；先由用户裁定业务语义（§5.2-9）。
8. 对端 SFC9120 是否有可用的低延迟路径（DPDK/AF_XDP）？——E0。
9. 2×9G 同时的台架能否用第二台机器/IRQ 隔离实现？——E10。
10. WS/窗口扩展是否值得冒 P4b-6 风险？——先测 RTT/窗口帽，再裁。
11. 延迟目标是多少（p50/p99，空载/满载，控制/数据）？——用户定义；没有目标就无法裁定“收口”。

---

## 10. 参考（可核）

- 0x32 板级/构建：`_proj_10g/notes/p11_fix_0x31_rom_0x32_20261026/README_FOR_TL.md`、`p11_board_p3_0x32_20261026/raw/`
- P7b 长流/台架：`_proj_10g/notes/p7b_longflow_board/ACCEPT.md`（C8 RTT 未判定）、`_proj_10g/notes/p7b_affinity/ACCEPT.md`、`_proj_10g/notes/p7b_affinity/BUILD.md`
- 数据面结构：`rtl/tcp_echo.v:2-3`（整帧转发）、`rtl/tcp_tx_frame.v:4-8`（帧级递交/checksum）、`rtl/tcp_rx.v:1-14`、`rtl/rx_classify.v:99-107`、`rtl/win_pool_mgr.v:200-430`、`rtl/fifo_async.v:3-33`
- 时钟：`board/wrapper_p4.v:517-539`、`:975-1001`、`:1285/4355`（CDC 256）
- HLS：`hls/src/layer_tcp.cpp:63/236/313`（无 WS）、`hls/src/eth_types.h:222`（`TX_PACING_COUNT=625,000,000`，per-pass；`udp_echo.h:89` 的旧宏是死宏，`udp_echo.cpp` 未包含该头）、`hls/src/layer_udp.cpp:111-135`（echo 立即 / HELLO pacing）
- HLS 延迟实测（xsim，本件新增）：`_proj_10g/notes/p11_hls_latency_20261026/`（`README.md`、`READINGS.txt`、`tb_hls_latency.v`、`run_hls_latency.py`、`SHA256SUMS.txt`）
- 对端 NIC：`ethtool -T enp1s0f1np1`（PTP Hardware Clock: none；software only）
- 全局经验：`~/.claude/fpga_net_dev.md` #43/#58/#59/#68/#82（台架帽/首跑/拆帽/coalescing/wscale）等

---

## 11. 一句话给下一棒

**先造“能看见延迟”的仪器，再决定改什么；TCP echo 约 3.6–4.5 µs（纸面），HLS 小帧实测 14–21 µs、HLS 1500B UDP echo 实测 303 µs（xsim，HLS-only）——控制面 HLS 不再是“1–3 µs”，必须 E1 板级定量；对端软件/台架仍可能更大。**
