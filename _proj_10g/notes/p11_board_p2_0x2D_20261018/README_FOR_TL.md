# P11 / P2 板级验证轮（0x2D / NW 85）—— README_FOR_TL

- 日期：2026-10-18 21:16–21:51 CST（唯一板级写者；TL 不参与板侧写）
- 轮目录：`_proj_10g/notes/p11_board_p2_0x2D_20261018/`
- 施工权威：`p11_p2a_design_20261018/DESIGN_v2r1.md` 附录 **E-6**（0x2D backstop-2 几何 + P2-2 判据改写）
  + 0x2D 构建件 `p11_build_0x2D_20261018/retry/ladder2/wrapper_p4.bit`
- 纪律：**QSPI 零写入**（全部 JTAG 易失，1 MHz）；未跑 Vivado 构建、未跑 xsim、未写 git、
  未碰 `D:\repo\perfv`；密码只作命令前缀、未落盘。
- 状态词：【已证】/【未判定】/【未定位】/【未测】。**本件不下 PASS/FAIL 裁定。**
  “未观测到” ≠ “不存在”。

---

## 0. 摘要（逐项状态词，不是裁定）

| # | 项 | 本轮读数（摘要） | 状态 |
|---|---|---|---|
| B-0 | 烧录 + 身份门 0x2D | sha256 前后逐字一致；HIGH+DONE+无 ABORT；BID `0x2D` / **85 字** / `0x184=0xffffffff` / MIR `0x174..0x180` 可读 / NFF=0 / 2 BARs / `LnkSta x4` / `0x08=0` / carrier 1/1 | 【已证】 |
| B-1 | 单口零回归（p1↔IP_A） | 0x2D n=3：1034.0 / 1041.4 / 1027.6 Mbps；`mism=0`、`stall=0`；W51 收尾 `0x77359b5d`；W84 **恒 0** 且 p0 NIC Δ=0、p1 NIC 逐帧配对 | 【已证】 |
| B-1-A/B | 同会话 0x2B 对照臂 | 0x2B n=3：1041.5 / 941.8 / 1089.9 Mbps；**同臂散布 14%** ⇒ 预登记 ≤0.5% 结构差无法判定（中位差 −0.72%） | 【未判定】（≤0.5% 界） |
| B-2 | 双口身份 A-1 + 池归还 | 两条 SYN-ACK 各自只在对端口出现、源 IP 正确；第二条双 1 字节探针收到 **fast-path 纯 ACK**：`ack=ISN+2, win=49152`、**ip.id 滚动 52856/52859/52860/52861**（HLS 帧 ip.id=0）；`ss -ti snd_wnd:49152` 与 ACK win 逐字相等 | 【已证】（池已归还） |
| B-2b | 每口数据臂 | 端口 A：200,001,020 B / `mism=0` / 955.3 Mbps / W83 Δ=136,990、W84 Δ=0；端口 B：200,001,020 B / `mism=0` / 1076.5 Mbps / W84 Δ=136,990、W83 Δ=0 | 【已证】 |
| B-2c | 每口 1 条同时建连 | 两口 `CONNECT_OK`，`ss` 双 established；W83 +45、W84 +48 | 【已证】 |
| B-3 | 错口负对照 | ① ARP 身份：p1 who-has IP_B，**应答只出现在 p0/J7**（dst MAC=p1），p1 零应答；② 出口：p1→IP_B 的 SYN 在 p1 可见，**SYN-ACK 只从 p0 出且 dst MAC=p1**，p1 收不到并超时；反向对称 | 【已证】 |
| B-4A | 两口同时 TCP 下行 | **结构性不可做**：演示 app 的 TCP TX 是单会话；两口同拉时 W84 仅 +3、W55 重传 +3,353、sink 0 字节、p0 建连超时 | 【已证】（结构性限制） |
| B-4B | 两口同时 UDP 灌入（RX 合并） | 静默对逐字相等（W83=W84=0x32）；4 s 窗 ΔW79=**495,746**、ΔW0=**509,685**（49.3/50.7）；W82=+34、W4=+47 可读；ΔW83=+1,668,043、ΔW84=+1,660,290 都前进；总量 `W0+W4=868,847≈868,832`、`W79+W82=844,077≈844,064` | 【已证】（两计数器都前进/可读） |
| B-4-offer | “≥ 聚合容量”前件 | 两口 UDP 源合计仅 **2.96 Gbps**（1.50+1.46），板全吸收 ⇒ **未达聚合容量** | 【未测】（前件未达） |
| B-5 | 慢路径每口 | 侧 B（p0→IP_B）：ping 3/3（rtt 0.095–0.153 ms）、ARP/ICMP 只在 p0、源 IP `.4`、UDP echo 7 B 逐字节匹配；板 W7 +5、W84 +5、W83 +0。侧 A 对称（W83 +5、W84 +0、源 `.2`） | 【已证】 |
| B-6 | UDP app 逐口学习/翻转 | 学自 IP_B：p0 抓 911,269 帧、p1 **0 帧**；W84 +4,860,514、W83 +0。学自 IP_A：W83 +7,441,729、W84 +929,763（过渡尾），`W8 = W83+W84+1` | 【已证】（翻转；过渡尾已登记） |
| B-7 | TX_DIS 单口隔离 | bit0=1 ⇒ **p0 carrier 1→0（chg 17→18）**、p1 不动（carrier 1、chg 69、rxpk 继续涨）；bit1=1 ⇒ **p1 carrier 1→0（chg 69→70）**、p0 不动（chg 19）；两次恢复均 0→1 且各 +1 | 【已证】（bit0/bit1 都有牙） |
| B-8 | 错误源 IP 可观测 | pcap 逐字节扫描：p1 侧 board 帧源 IP **只有 `.2`**、p0 侧 **只有 `.4`**；大 pcap 各抽样 200k 帧，**0 例错源**（未观测到 ≠ 不存在） | 【已证】（观测面）；单元门 G5 本轮**未跑**（xsim 禁跑） |
| HLS 双 IP | IP_B 的 ARP/ICMP/UDP/TCP | B-5 覆盖 ARP/ICMP/UDP echo（8080）；B-2/B-2b 覆盖 TCP；B-6 覆盖 UDP app（8081）；`MAX_TCP_CONN=3` 下每口 1 条同时建连 = B-2c | 【已证】 |
| 终态 | 板 / 对端 | 板 = 0x2D + `0x08=0` + carrier 1/1；netns 已删、p1 恢复 `.100.100/32`、无残留进程；**无需再 remove/rescan** | 【已证】 |

---

## 1. 入口态与烧录（B-0）

### 1.1 入口（21:16 前）

- 板：`MAGIC=0x50360001` / `BID=0x0000002a` / `SCRATCH_0x08=0`；`/dev/xdma0_user`、`/dev/xdma0_control` 在位；
  `hw_server=active`、`xdma` 已加载。**与派单描述“当前应为 0x2A”一致。**
- 对端：`enp1s0f1np1` = UP，carrier=1，10 Gb/s，`192.168.100.100/32`；
  `enp1s0f0np0` = UP，carrier=1，10 Gb/s，无 IPv4。`ss … dport :8080` established = 0；
  `iptables` 仅三条默认策略；无 `p7b_*`/`tcpdump` 残留。

### 1.2 烧录 0x2D（本轮 8 次烧录中的第 1 次；模板 `burn/burn_p2_board.sh`）

- 位流：`_proj_10g/notes/p11_build_0x2D_20261018/retry/ladder2/wrapper_p4.bit`
  sha256 **`ecef15f2339435edb70727e6a979b363375be2a0f8bd875d352f63a293b0e76f`**，15,431,261 B（核过）；
  本地副本 `burn/wrapper_p4_0x2D.bit` 同 sha（**副本不是独立锚**，与历轮口径一致）。
- 烧录：JTAG `192.168.0.38:3121`，1 MHz；`End of startup status: HIGH`；`TCPREG_PROG_DONE`；
  路径匹配、无 ABORT、stdout freshness=134 s。
- PCIe：**device-level `remove`+`rescan` 一次成功**（无需升到根端口）；`LnkSta 5GT/s x4`；
  `identify_bars: 2 BARs: config 1, user 0`；`/dev/xdma0_user` + `/dev/xdma0_control` 均在。
- 身份门（0x2D / NW 85 / UNIMPL `0x184`）：

| 项 | 读数 | 期望 |
|---|---|---|
| `0x00` MAGIC | `0x50360001` | `0x50360001` |
| `0x04` BID | `0x0000002d` | `0x0000002D` |
| `0x14` MARKER | `0xdeadbeef` | `0xdeadbeef` |
| `0x184` UNIMPL | `0xffffffff` | SLVERR |
| `0x08` SCRATCH | `0x00000000` | 0 |
| `0x174` MIR_STATUS | `0x00200000` | 可读 |
| `0x178` MIR_DATA | `0x5a5a5a5a` | 可读 |
| `0x17C` MIR_CTRL | `0x00000000` | 可读 |
| `0x180` MIR_DMA_CNT | `0x00000000` | 可读 |
| 窗口扫描 | **NFF=0**（85 字） | 0 |
| BAR / 链路 | 2 BARs / `5GT/s x4` | 2 / x4 |
| carrier | p1=1 / p0=1 | 1 |

> 本轮共 **8 次 JTAG 烧录**（0x2D ×7 + 0x2B ×1，见 §3/§9）；每次都是 device-level remove+rescan
> 一次成功、无升根端口、无 QSPI 写入。

---

## 2. B-1 单口零回归（p1 ↔ IP_A / J8）

### 2.1 偏离登记（必须如实说）

派单写“**只插 J8**（p1↔IP_A）”。**实际物理上 J7 的 AOC 仍在位**（p0 carrier=1，B-5 的 p0 ARP/ICMP/UDP
全部可用）⇒ 本轮是**逻辑单口**：只有 p1 有 IP/有流量、p0 无 IP/无流量，**不是物理拔纤**。
（P1 轮已登记“无物理拔插条件”，本轮同样无远端拔插能力。）

### 2.2 构造与读数

`sink = p7b_tcp_sink --host 192.168.100.2 --port 8080 --rcvbuf 2920 --conns 1 --maxbytes 2000000000 --check lane8`。
板侧主口径 = 稳态窗两点快照（A→B，约 8.07 s，`ΔW43/156.25e6` 为时基；`ΔW20` 为 MAC TX 帧）：

| 臂 | run | sink Mbps | 板侧 fps | 拍/帧 | 载荷 Mbps（fps×1460×8） |
|---|---|---|---|---|---|
| **0x2D** | r1 | 1034.028 | 88,629.6 | 1762.96 | 1035.19 |
| 0x2D | r2 | 1041.427 | 89,224.8 | 1751.19 | 1042.14 |
| 0x2D | r3 | 1027.612 | 87,954.7 | 1776.48 | 1027.31 |
| **0x2B** | r1 | 1041.502 | 89,310.6 | 1749.51 | 1043.15 |
| 0x2B | r2 | 941.785 | 81,320.8 | 1921.40 | 949.84 |
| 0x2B | r3 | 1089.930 | 93,689.9 | 1667.74 | 1094.30 |

- 同臂散布：0x2D 1.3%（1027.6–1041.4），0x2B **14%**（941.8–1089.9）⇒ **单跑不可比**。
  中位差（0x2D vs 0x2B）= **−0.72%**（sink）/ **−0.76%**（板侧 fps）。
  **预登记“≤0.5% 结构性差值”=【未判定】**：不是“超标”，是**本方法分辨不出**（同臂噪声 14×）。
  参照：P1 S-6 在同 0x2B 位流上曾得 1084.6 Mbps，进一步证明臂内散布主导。
- 内容/隔离（全部 3 跑一致）：
  - `first_mismatch=-1` / `mism_bytes=0` / `stall_conns=0` / `fail_conns=0`；
  - **`W84` 全程 = 0**（ch0 TX 帧），且 p0 NIC Δbytes=Δpackets=0；
  - p1 NIC 与 W83/W52 配对：W83 收尾 `0x14e711`=1,369,873、W52 `0x14e709`=1,369,865、
    p1 NIC Δpackets=1,369,869、Δbytes/Δpkts=**1517.99**；
  - W51 收尾 **`0x77359b5d` = 2,000,001,885**（与 P1 S-6 逐字相同）；W54=0；W55=1/2/3。
- 见证：每次 sink 打印 `PIN_CPU=7`、`PIN_THREAD io=4 / work=6`；`SINK_RCVBUF_ORDER=before_connect`。

> 口径：`W43` 是 tx 域拍钟（每拍无条件 +1），`ΔW43/ΔW20` 是“每帧拍数/帧率换算”，
> **不是线占空测量**（与工程既有订正一致）。

---

## 3. B-2 双口身份 A-1（B-2 阶段 I/II）

### 3.1 环境（netns，design §4.6 配方）

```
nsa: enp1s0f1np1 = 192.168.100.1/32   route 192.168.100.2/32   （p1 ↔ IP_A / J8）
nsb: enp1s0f0np0 = 192.168.100.101/32 route 192.168.100.4/32   （p0 ↔ IP_B / J7）
静态邻居（错口测试用）: nsa → .4 / nsb → .2 = 00:0a:35:01:fe:c0 PERMANENT
rp_filter=0 / arp_ignore=1 / arp_announce=2；adaptive-rx off, rx-usecs 0
```
两接口移入 netns 成功（carrier 1 / speed 10000）。

### 3.2 阶段 I 身份（21:29）

- conn1：p1 `.1:60222 → .2:8080`；p1 pcap 依次见 **ARP who-has `.2` → ARP reply → SYN → SYN-ACK**；
  **p0 pcap 0 帧**。SYN-ACK：src `192.168.100.2:8080`、dst MAC = p1 MAC、win 49152。
- conn2：p0 `.101 → .4:8080`；p0 pcap 见 SYN/SYN-ACK；**p1 pcap 0 帧**。
  SYN-ACK：src `192.168.100.4:8080`、dst MAC = p0 MAC、win 49152。
- ⇒ **每条 SYN-ACK 只在该连接的对端口出现、源 IP = 该连接本地 IP** 【已证】。

### 3.3 阶段 II 池归还（N-1：双 1 字节探针 + fast-path 纯 ACK）

- 第一条连接 FIN 后等 0.3 s + pcap 起停（≥10 ms 扫描周期）再建第二条。
- 第二条上发 1 字节 → 隔 0.4 s → 再 1 字节。p0 pcap 抓到 **4 个板源纯 ACK**：
  - `ack = SYN seq + 2`（两字节都被确认）；
  - **`tcp.win = 49152 > 0`** ⇒ **池已归还**；
  - **`ip.id` = 52856 / 52859 / 52860 / 52861**（滚动、非 0）⇒ 帧源 = **fast path**；
    同 pcap 的 HLS SYN-ACK `ip.id = 0`（与 N-1 的判别法逐字吻合）。
- 二次核对：连接打开时 `ss -ti` 逐字 `snd_wnd:49152` = ACK 的 `tcp.win`。
- **无 ACK ⇒ 未判定**的分支本轮未触发（ACK 抓到了）。
- ⚠️ **板侧 DEL/CONN_DOWN 无直接仪器**（app 总线在板上不可用）：以 FIN 收尾 + 0.3 s 等待替代，
  登记为“无直接见证”。

### 3.4 每口数据臂（B-2b，21:29）

| 口 | sink 读数 | 板侧 Δ（PRE→POST） | 对端 NIC（静置后） |
|---|---|---|---|
| A（p1→IP_A） | 200,001,020 B / `mism=0` / 955.3 Mbps / 1.675 s | W83 **+136,990**、W84 **+0**、W52 +136,988、W51 **+200,002,480** | p1 Δbytes=207,949,366 / Δpkts=136,990 |
| B（p0→IP_B） | 200,001,020 B / `mism=0` / 1076.5 Mbps / 1.486 s | W84 **+136,990**、W83 **+0**、W52 +136,988、W51 **+200,002,480** | p0 Δbytes=207,949,430 / Δpkts=136,991 |

- `W51 − sink bytes = 1,460 B`（恰好 1 MSS，关闭时在飞的那一帧），与 P1 S-6 同族。
- **仪器坑（登记）**：NIC `port_rx_*` 的读取**滞后约 1 s**。刚跑完立即读只得 92k/137k 帧；
  静置后再读才补到 136,990/136,991。**判据必须用“静置后”读数**（或 `ip -s link`）。

### 3.5 每口 1 条同时建连（B-2c，21:47）

- 两次失败尝试的教训（登记）：**静态邻居会跳过 ARP ⇒ 重烧后的板 HLS ARP 表为空 ⇒ SYN-ACK 走
  `layer_tcp.cpp:326` 的广播兜底（dst MAC `ff:ff:ff:ff:ff:ff`）⇒ 客户端拒收、建连失败**。
  这是**既有行为**，不是 P2-2 缺陷；正常路径必须让板先学到对端 MAC（真实 ARP）。
- 最终成功臂：先 `ping -c1` 触发真实 ARP，再两口同时 connect-hold：
  - nsa：`192.168.100.1:48358 ↔ 192.168.100.2:8080` established；
  - nsb：`192.168.100.101:55566 ↔ 192.168.100.4:8080` established；
  - 两条都 `CONNECT_OK`，板侧 W83 5→50（+45）、W84 2→50（+48）⇒ **每口 1 条同时成立** 【已证】。
- 另一次失败（B2C2，无重烧）板侧**完全没发 SYN-ACK**（W20/W83/W84 不动）：前一次失败的半开 TCB
  可能占满连接槽；重烧后即恢复。机理【未定位】（未做拆刀）。

---

## 4. B-3 错口负对照（H-2 两段）

### 4.1 身份（ARP 层隔离）

- p1 删静态邻居后 `ping -c1 192.168.100.4`：p1 发出 **ARP who-has `192.168.100.4`**；
  **p0 pcap 看到板应答 `Reply 192.168.100.4 is-at 00:0a:35:01:fe:c0`（dst = p1 MAC）**；
  **p1 pcap 无任何应答**；`ip neigh` 保持 INCOMPLETE。
  ⇒ 板确实应答了 IP_B，但**只在 ch0/J7 出**（`slow_tx_adp` 端口提取 = 1）【已证】。
- 反向 p0→IP_A 未单独做 ARP 段（B-5 的 A 侧 ARP 只在该口出现，可作同族正向对照）。

### 4.2 出口（真负对照）

- 补 `nsa→.4/32`、`nsb→.2/32` 两条临时路由（错误的“正常方向”路由不存在），静态邻居就位。
- **p1→IP_B**：p1 pcap 见 6 次 SYN（重试）；**p0 pcap 见 6 次 SYN-ACK，src `.4`、dst MAC = p1 MAC**；
  p1 **收不到 SYN-ACK**；`connect` timeout。⇒ 出口正确（SYN 进 ch1，SYN-ACK 出 ch0）。
- **p0→IP_A**：对称 —— p0 pcap 见 SYN；p1 见 6 次 SYN-ACK，src `.2`、dst MAC = p0 MAC；
  p0 收不到；timeout。
- 板侧 W83/W84 只记录 SYNs/SYN-ACKs 的小增量（+9 帧级），不影响结论。

---

## 5. B-4 合并公平 / 丢帧

### 5.1 Part A：两口同时 TCP 下行 = **结构性不可做**（如实登记）

- 两口同时各起一个 `p7b_tcp_sink`（p1→IP_A、p0→IP_B）：
  - p1 sink connected 但 **0 字节**、15 s 后 STALL；p0 sink **connect timeout**；
  - 板侧 W84（ch0 TX）仅 **+3 帧**；W55（重传）**+3,353**；W83 增长但 p1 sink 收不到。
- 根因（工程既有结论，本轮复现）：**演示 app 的 TCP TX 是单会话**（Stage C 已登记
  “TCP 数据 × TCP 数据构型结构性做不了”）。⇒ 本项不是板级缺陷，是 app 能力边界。

### 5.2 Part B：两口同时 UDP 灌入（RX 合并）——干净窗口

- 取窗前静默：两次快照（gen 3→4，间隔 >1 ms）`W83=W84=W20=0x32` **逐字相等** 【已证】。
- 灌入：`p7b_udp_src --host IP --port 8081 --seconds 7 --mbps 0` 两口并行（各绑 `PIN_CPU=7`）。
  - p1：868,832 pkts / 7.002 s / wire **1,502.9 Mbps**；
  - p0：844,064 pkts / 7.000 s / wire **1,460.5 Mbps**；
  - 合计 **2.96 Gbps < 板聚合容量**（板全吸收）⇒ “**≥聚合容量**”前件【未测】。
- 中部 4 s 窗（MID1→MID2）读数：

| 量 | Δ | 说明 |
|---|---|---|
| `ΔW0`（ch1 MAC 帧） | **509,685** | 前进 |
| `ΔW79`（ch0 merge 接受好帧） | **495,746** | 前进 |
| `ΔW82`（ch0 MAC drop） | **+34** | 可读（非 0） |
| `ΔW4`（ch1 drop） | **+47** | 可读（非 0） |
| `ΔW83`（ch1 TX 帧） | **+1,668,043** | 前进（UDP app 学到 peer 后 TX） |
| `ΔW84`（ch0 TX 帧） | **+1,660,290** | 前进 |

- 公平份额（接受帧）= **49.3% / 50.7%**（两口径各自与注入量对齐后）。
- 总量对账（PRE→POST）：
  - ch1：`W0 + W4 = 868,643 + 204 = 868,847` vs p1 注入 **868,832**（+15 = 背景/ARP）；
  - ch0：`W79 + W82 = 843,920 + 157 = 844,077` vs p0 注入 **844,064**（+13）。
  ⇒ **接受 + MAC 丢 = 注入**，逐帧闭合（±15 帧背景）。
- **W85 守恒**：W85 在 0x2D 已删 ⇒ **结构性不可评估**（按 E-6.2 登记为“观测面已删除，判据作废”）。
- **ch0 abort**：W87 不可读 ⇒ 只能写“**未观测到（无该仪器）**”，不得写“abort=0”。

### 5.3 关于 E-6.2 的“ch0 对账 = W84 + W82 + INFLIGHT_MAX_FRAMES=33”

**如实指出语义不符**：`W84` 是 **TX port1/ch0 帧数**，`W82` 是 **ch0 RX MAC drop**，两者方向不同，
相加不构成任何方向的对账式。本轮按两个方向分别给账：

- **RX ch0**：`ΔW79 + ΔW82 ≈ 对端 p0 注入帧数`（本轮 844,077 vs 844,064）。
- **TX ch0**：`ΔW84` vs 对端 p0 NIC 收帧；本轮 NIC 读取窗与快照窗**未对齐**（NIC 滞后 ~1 s），
  故 `INFLIGHT_MAX_FRAMES=33` 的界**未判定**（不伪造成立）。
  （过程值：PRE→POST `ΔW84=2,825,089`，p0 NIC 同段 Δpkts=2,825,089 量级，差值落在未对齐窗内。）

---

## 6. B-5 慢路径逐口（ARQ/ICMP/UDP echo）

| 侧 | ping | ARP 应答 | ICMP 回包源 IP | UDP echo（8080） | 板侧 Δ |
|---|---|---|---|---|---|
| B：p0→IP_B | 3/3，rtt 0.095/0.120/0.153 ms | 只在 p0 | `.4`，只在 p0 | `HELLO-B` 7 B 逐字节匹配，from `.4:8080` | W7 +5；**W84 +5、W83 +0**；W79 +5 |
| A：p1→IP_A | 3/3，rtt 0.099/0.130/0.188 ms | 只在 p1 | `.2`，只在 p1 | `HELLO-A` 7 B 逐字节匹配，from `.2:8080` | W7 +5；**W83 +5、W84 +0**；W0 +5 |

- 对端口 pcap 全程 0 帧（双向均核）。
- ⇒ 慢路径的**接收口身份**（W79/W0 各 +5）与**回包出口身份**（W84/W83 各自 +5）都在板侧计数上闭合。
- 长阻塞用例（G4）本轮未做（build 已覆盖），登记为【未测】。

---

## 7. B-6 UDP app 逐口学习 / 翻转

| 臂 | 对端口 pcap | 板侧 Δ | 结论 |
|---|---|---|---|
| 学自 IP_B（p0 发 8081） | p1 **0 帧**；p0 **911,269 帧**（板源 `.4`） | W8 +**4,860,516**、W84 +**4,860,514**、W83 **+0**；W10 +832、W11 +1,224,704（=832×1472） | app TX **只在 ch0** 【已证】 |
| 学自 IP_A（p1 发 8081） | p1 抓 1,336,865 行（含本端 832 帧 + 板 app TX）；p0 550,978 帧（过渡尾，板源 `.4`） | W83 +**7,441,729**、W84 +**929,763**（过渡）、W8 +8,371,493；`W83+W84 = W8 −1` | 翻转到 ch1 【已证】（有过渡尾） |

- `W13`（app RX mismatch）在第二次学习后 **+1,220,053**：app 的 RX 校验器把 8081 载荷当**一条连续流**，
  peer 从 B 切到 A 后新流从偏移 0 开始 ⇒ 与旧流偏移不接 ⇒ 失配。**登记为 app 语义，不是端口缺陷**
  （B 臂 `W13=0` 且 832×1472 逐字节对账）。
- **副作用（登记）**：app 一旦学到 peer，就**持续满速 TX**（W8/W84 每分钟数百万帧），直到重烧清 peer 表。
  这会影响后续任何需要安静窗口的测试；本轮用完即重烧。

---

## 8. B-7 TX_DIS 单口隔离

判据 = **对端 carrier / carrier_changes / NIC 收包**（RTL 明确 `sfp1_tx_dis=scratch[0]`、
`sfp2_tx_dis=scratch[1]`；`W83/W84` 在 arb 输出端、**位于 TX_DIS 门之前**，故不能用 W 计数判 TX_DIS）。

| 步 | `0x08` | p1 | p0 |
|---|---|---|---|
| 基线 | 0x0 | carrier 1，chg 69，rxpk 增长 | carrier 1，chg 17 |
| **bit0=1** | 0x1 | carrier 1，chg 69，rxpk **继续增长**（399.6M→402.3M） | **carrier 1→0，chg 17→18，rxpk 冻结** |
| 恢复 | 0x0 | carrier 1，chg 69 | carrier **0→1，chg 18→19** |
| **bit1=1** | 0x2 | **carrier 1→0，chg 69→70，rxpk 冻结** | carrier 1，chg 19，rxpk 冻结（无流量） |
| 恢复 | 0x0 | **carrier 0→1，chg 70→71，rxpk 恢复增长** | carrier 1，chg 19 |

- **bit0 停 J7/ch0、p1 不受影响**；**bit1 停 J8/ch1、p0 不受影响** —— 两位都有牙 【已证】。
  （P1 只证过 bit0；**bit1 本轮首次板级坐实**。）
- 观察：bit1=1 期间 `W83` 仍增长（+262,144）—— 这是**仪器口径**（计数器在 TX_DIS 门上游），
  不是“没停”；carrier/NIC 是正确仪器。

---

## 9. B-8 错误源 IP 可观测 + HLS 双 IP

- pcap 逐字节扫描（`raw/B8_SRCIP_SCAN.log`）：
  - p1 侧全部 board-sourced 帧源 IP = **`192.168.100.2`**（B2P1 p1、B3B_b_p1、B5_A_arpA）；
  - p0 侧全部 = **`192.168.100.4`**（B2P1 conn2、B3B_a_p0、B5_B_arpB、B6 p0）；
  - 大 pcap（B6 每口）各抽样 **200k 帧**，同样零例外。
  ⇒ **0 例错源 IP 被观测到**（“未观测到” ≠ “不存在”）；若存在错源，pcap 会逐字节可见。
- **单元门 G5 本轮未跑**（派单禁跑 xsim）；只引用 0x2D 构建时已存在的门/构建件，不冒充本轮读数。
- HLS 双 IP：IP_B 的 ARP/ICMP/UDP(8080)/TCP 回包全部实测（§6/§3）；UDP app(8081) 双口学习实测（§7）；
  `MAX_TCP_CONN=3` 下每口 1 条同时建连实测（§3.5）。

---

## 10. 偏离 / 意外发现 / 仪器坑（必须读）

1. **“只插 J8”不是物理事实**：J7 AOC 仍在位（p0 carrier=1）。本轮是逻辑单口（p0 无 IP/无流量）。
2. **静态邻居 ⇒ 跳过 ARP ⇒ 板 HLS ARP 表空 ⇒ SYN-ACK 广播兜底**（`hls/src/layer_tcp.cpp:326`），
   建连必失败。正常测试必须先让板学到对端 MAC（真实 ARP/ping）。这是既有行为，不是本轮缺陷。
3. **演示 app TCP TX 单会话**：两口同时拉 TCP 下行时第二口拿不到数据、重传暴涨。
   与 Stage C 的“TCP 数据×TCP 数据结构性做不了”一致。
4. **UDP app 学到 peer 后会持续满速 TX**，直到重烧清 peer 表；测试顺序必须考虑（本轮用后即重烧）。
5. **NIC `port_rx_*` 计数滞后约 1 s**：刚跑完立即读会少算（本例 92k vs 137k 帧）；静置后读数才完整。
6. **W83/W84 不能判 TX_DIS**：计数器在 TX_DIS 门上游；TX_DIS 判据 = 对端 carrier/NIC。
7. **B-4 ch0 对账式语义不符**（见 §5.3）：W84 是 TX、W82 是 RX，不能相加成一条对账式。
8. **E-6.2 的“INFLIGHT_MAX_FRAMES=33”**：本轮 NIC 窗与快照窗未对齐 ⇒ 该界【未判定】，不伪造成立。
9. **B-2c 两次失败**（广播 SYN-ACK / 半开 TCB 占槽）机理未完全分离；重烧后恢复。
10. **W13 的 app 语义失配**（§7）已登记，不是端口/源 IP 缺陷。

---

## 11. 未测项（不许当已答）

- **B-1 的 ≤0.5% 结构差**：同臂散布 14% ⇒ 本方法分辨不出（【未判定】）。
- **B-4 的“≥聚合容量”前件**：本轮只灌到 2.96 Gbps，板全吸收（【未测】）。
- **ch0 abort（W87）**：0x2D 已删该字（【未观测到（无该仪器）】）。
- **W85 守恒**：观测面已删除（【结构性不可评估】）。
- **B-4 TX 侧 INFLIGHT_MAX_FRAMES 界**：NIC 窗未与快照窗对齐（【未判定】）。
- **板侧 DEL/CONN_DOWN 确认**：无直接仪器，只有 FIN + 池归还探针的间接见证。
- **G5 单元门 / G2/G3/G4/G6/G7 等仿真门**：本轮禁跑 xsim，未重新执行。
- **B-5 长阻塞用例（H-3/G4）**：未做。
- **物理拔纤（LOS）/停钟**：无物理条件（同 P1 S-4/S-5）。
- **板上温度/功耗**：无仪器。

---

## 12. 终态

- 板：**0x2D**（`0x04=0x0000002d`）/ **85 字** / `0x184=0xffffffff` / NFF=0 / 2 BARs / `LnkSta 5GT/s x4` /
  **`0x08=0`** / **carrier p1=1、p0=1**；最后一次快照 `gen=1 status=0x00010056 ch0_stale=0`，
  `W0=2 W20=4 W83=4 W84=0 W51=W52=W54=W55=0`（干净）。
- 对端：**netns 已删除**；p1 恢复 `192.168.100.100/32` + `192.168.100.2/32 dev` 路由；p0 无 IPv4；
  两口 carrier=1；`iptables` 仅默认策略；**无残留 `p7b_*`/`tcpdump`**。
- **QSPI 零写入**（8 次烧录全部 JTAG 易失）。
- **是否需要 remove/rescan**：本轮每次烧录后 device-level remove+rescan 均一次成功；
  **当前状态正常，不需要再 remove/rescan**（板侧 BAR/链路/身份门已复算）。

---

## 13. 文件清单

```
p11_board_p2_0x2D_20261018/
├── README_FOR_TL.md              本件
├── FINAL_STATE.txt               终态一页纸（机器可读）
├── burn/
│   ├── burn_p2_board.sh          本轮烧录脚本（sha 前后核 + 身份门 + NFF + MIR）
│   ├── BURN_0x2D_20261018_*.txt  7 次 0x2D 烧录日志（0x2B 那次的日志在 p9_board_p1_20261018/burn/）
│   ├── BURN_stdout_copy_*.txt    Vivado 原始 stdout 拷贝
│   └── wrapper_p4_0x2D.bit       本轮位流副本（sha256 = ecef…e76f；**非独立锚**）
├── raw/
│   ├── B1_PORT_A_0x2D{,_r2,_r3}.log / B1_PORT_A_0x2B{,_r2,_r3}.log
│   ├── B2_NETNS_SETUP.log / B2_PHASE1.log / B2_POOL_ACK_DETAIL.log / B2B_DATA.log
│   ├── B2C_DUALCONN.log / B2C2_DUALCONN.log / B2C3_DUALCONN.log
│   ├── B3_WRONGPORT.log / B3B_OUTLET.log
│   ├── B4_MERGE.log / B4A_TX2PORT.log / B4B_RXFLOOD.log
│   ├── B5_SLOWPATH.log / B6_UDPAPP.log / B7_TXDIS.log / B8_SRCIP_SCAN.log
│   ├── FINAL_BURN_0x2D.log / FINAL_STATE_READ.log / CLEANUP_NETNS.log
│   └── *.pcap（小件：B2P1_*、B3_arp_*、B3B_*、B5_*、B2C_single；大 pcap 已在板侧删除）
└── tools/                        本轮上传到对端的脚本（与对端 /tmp/p2b_* 同源）
```

- 读侧工具：`_proj_pcie/p7b_biz/p7b_snap.sh`（md5 `8318e8ffd01a40015a09bca0be91cfbb`）上传为
  对端 `/tmp/p2b_snap.sh`；sink md5 `f62299291fcb9e02afe109c4ea1f90ab`（未改）。
- 大件：`wrapper_p4.bit`（15,431,261 B）按轮保留，**不入库**（与历轮口径一致）。
