# P11 E1 零构建满载尾延迟（0x32 / 9G 级下行 + 端口 B 探针）

- 日期：2026-10-27 01:58–02:13（对端机本地时间）
- 板：P11 0x32（BID `0x32` / 85 字 / `0x184` 未实现 / 2 BARs / x4 / `0x08=0` / carrier 1/1）
- 性质：**零构建、零烧录、QSPI 零写**；只灌流 + 端口 B 探针
- 状态词：延迟/字节/丢包 = **【已证·板级·raw】**；基线双峰与“负载下更低”的机理 = **【未定位】**；
  快态 E1、fast-path 单包延迟 = **【未测】**
- 前序：E0.5（`p11_e05_latency_20261027/`）已经给出 0x32 的窗口/占用基线

---

## 1. 方法

- **负载**：60 GB TCP 下行，A 口（`nsa` → 板 `192.168.100.2`），THREADED sink、
  `--check lane8`、`rcvbuf 1048576`、`taskset -c 0,1`、`--no-pin`。
- **探针**：B 口（`nsb` → 板 `192.168.100.4`），`taskset -c 2`：
  - ICMP ping 2000 @5 ms；
  - TCP connect() 2000 @5 ms（**注意：8080 是数据 app 的 TCP 口，不是控制面监听口**）；
  - UDP echo 64 B 2000 @5 ms、996 B 1000 @10 ms；
  - UDP echo 1472 B 500 @10 ms，`--no-check`（>996 B 内容会零填充，见 §4）。
- 每个 run：PRE → 3 s → MID1 → 探针序列（约 45 s）→ MID2 →（load）sink 收尾 → POST。
- 探针与 sink 同机不同口/不同核；NIC IRQ 40–52 → CPU 4–7；coalescing off。
- 延迟工具：`p7b_lat_probe`（TCP 非阻塞 connect / UDP send+echo；单调时钟；CSV 保留逐样本）。
- **状态分类**：用 sink 速率（E0.5：快态 9.44、慢态 9.07–9.26）判定；
  ⚠️ 本轮 MID1→MID2 约 45 s **超过 W43/W65 的 27.49 s 回卷周期**，W65/W43 不用于状态
  （E0.5 的 10 s 窗口才是 W65 参考）。**本轮 5 个 load run 全部落慢态（8.60–9.25 Gbps）**，
  **没有采到快态 load**。

---

## 2. 结果（单位 µs；p50/p99）

| run | 模式 | 状态 | sink Gbps | ping p50/p99 | TCP p50/p99 | UDP64 p50/p99 | UDP996 p50/p99 | UDP1472 p50/p99 |
|---|---|---|---:|---:|---:|---:|---:|---:|
| E1BASE  | base | idle | — | 46 / 79 | 244 / 300 | 207 / 258 | 583 / 609 | 755 / 782 |
| E1BASE2 | base | idle | — | 46 / 79 | 104 / 304 | 216 / 260 | 583 / 612 | 756 / 778 |
| E1BASE3 | base | idle | — | 46 / 78 | 225 / 332 | 145 / 169 | 581 / 609 | 752 / 781 |
| E1BASE4 | base | idle | — | 46 / 47 | 249 / 336 | 148 / 171 | 584 / 608 | 756 / 780 |
| E1BASE5 | base | idle | — | 46 / 83 | — | 215 / 262 | 583 / 607 | 754 / 777 |
| E1L1 | load | slow | 9.2539 | 48 / 50 | 105 / 184 | 105 / 171 | 434 / 497 | 598 / 671 |
| E1L2 | load | slow | 8.9134 | 67 / 112 | 72 / 112 | 77 / 105 | 406 / 434 | 574 / 603 |
| E1L3 | load | slow | 8.9846 | 63 / 75 | 73 / 110 | 77 / 104 | 406 / 435 | 574 / 602 |
| E1L4 | load | slow | 8.5971 | 47 / 50 | 103 / 187 | 105 / 180 | 433 / 505 | 600 / 671 |
| E1L5 | load | slow | 9.1494 | 47 / 50 | — | 94 / 168 | 425 / 501 | 592 / 667 |

- 所有探针 **0 loss / 0 bad**（E1L5 没有 TCP 臂）；ping 2000/2000。
- 5 个 load：各 60 GB，合计 **300,000,026,585 B**，`first_mismatch=-1 / mism_bytes=0 / fail_conns=0`。
- 基线 5 跑 TCP p50 104–249（双峰）、UDP64 p50 145–216（双峰）；load 跑更集中
  （TCP 72–105、UDP64 77–105）。**基线双峰机理【未定位】**（板内 HLS pass/状态机、对端栈、
  探针顺序均未分离）。

### 2.1 关键比较

- **9G 级慢态负载没有抬高 HLS 控制面 p99**：  
  TCP 300–336 → **110–187**；UDP64 169–262 → **104–180**；UDP996 607–612 → **434–505**；
  UDP1472 777–782 → **602–671**；ping p99 47–83 → 50–112（E1L2 一次 112，其余 50–75）。
- **负载下更低**是稳定形态（E1L2/L3 两次几乎逐值相同；E1L1/L4 另一档），但机理**未定位**；
  不能写成“负载降低延迟”，只能写“本构型下未观测到 9G 负载把 HLS 控制面 p99 抬高”。
- **尾延迟主项 = HLS 服务时间本身**：64 B ≈0.08–0.17 ms、996 B ≈0.41–0.50 ms、
  1472 B ≈0.57–0.67 ms（p99，load 与 base 同量级）。这与 xsim HLS-only 的 14–21 µs / 303 µs
  不同量级；板级多出 MAC/适配器/HLS 调度/对端栈，**不能拿 HLS-only 数当板级延迟**。
- **fast-path 单包延迟仍未测**：探针走端口 B 的 HLS 路径；A 口的 9G fast-path 数据帧
  没有任何逐包时间戳。E1 的负结果只说明“HLS 控制面不被 9G fast-path 饿死”，
  不能外推到 A 口 fast-path 的消息延迟。

---

## 3. 结论与状态

1. **【已证·板级·raw】** 本构型下，9G 级（8.60–9.25 Gbps，慢态）TCP 下行同时，
   端口 B 的 ping/TCP/UDP echo 全部 **0 丢包**，p99 不高于空载基线；HLS 控制面未被饿死。
2. **【未定位】** 基线 TCP/UDP64 双峰、以及 load 下 p99 反而更低：候选 = HLS pass/状态、
   对端栈/CPU 状态、探针顺序；**本轮没有逐包/逐 pass 见证**。
3. **【未测】** 快态 load（≥9.35 Gbps）的 E1；A 口 fast-path 的单包/尾延迟；同口探针。
4. **【已证·板级·raw】新缺陷（HLS UDP echo >996 B）**：见 §4。

---

## 4. 新发现：HLS UDP echo 精确上限 996 B

`raw/E1_UDP_ECHO_SIZES.txt`（端口 B、`ip netns exec nsb python3`）：

| payload B | rx len | bad bytes | first bad | tail |
|---:|---:|---:|---:|---|
| 64 | 64 | 0 | — | — |
| 512 | 512 | 0 | — | — |
| **996** | **996** | **0** | — | — |
| 997 | 997 | 1 | 996 | — |
| 1024 | 1024 | 28 | 996 | `00000000` |
| 1400 | 1400 | 404 | 996 | `00000000` |
| 1472 | 1472 | 476 | 996 | `00000000` |

- **≥997 B：回包长度仍等于请求长度，但 offset ≥996 全为 0**（不是丢包、不是截断长度）。
- 根因（读源码）：HLS TX UDP 区 = `TX_UDP_BASE=512` + `TX_UDP_SIZE=256` words = **1024 B**，
  IP+UDP 头占 7 words = 28 B ⇒ **payload 容量 249 words = 996 B**；
  `hls/src/udp_echo.cpp:203-207` 按 `(payload_len+3)>>2` 无界拷贝，>996 B 写出 TX 区/留下 0。
- **影响**：此前“1500B UDP echo 303 µs（HLS-only）”只测了延迟，**没有校验回包内容**；
  板级 1472 B echo 不是干净回显。所有依赖 1500B UDP echo 内容的判据必须先修此边界。
- 本轮 **未修**（属 HLS 慢路径；修复需扩 TX 区或加长度守卫/整帧丢弃，涉及 HLS 重综合）；
  登记为未收口项。

---

## 5. 证据与复跑

```
raw/E1BASE..E1BASE5_*.txt/.csv     # 5 个空载基线：ping/TCP/UDP 原始逐样本 + sink(无)
raw/E1L1..E1L5_*.txt/.csv          # 5 个 load：同上 + 60GB sink
raw/E1*_PRE/MID1/MID2/POST.txt     # 板侧快照（W0/W5/W20/W43/W65..W69/W27/W28）
raw/E1*_CONSOLE.txt                # 每次会话完整输出
raw/E1_UDP_ECHO_SIZES.txt          # 996B 边界证据
raw/E1_METRICS.txt                 # e1_metrics.py 输出（本文件 §2 表）
e1_metrics.py                      # 从 raw 复算（状态按 sink 速率）
e1_latency.sh                      # 部署到对端 /tmp 的同一份脚本（md5 4df5b92a…）
artifacts/p7b_lat_probe            # 延迟工具（md5 a8c61af6…）
artifacts/p7b_lat_probe.cpp        # 源快照（md5 db5792b2…）
LAT_PROBE_BUILD.txt                # 构建命令/哈希说明
SHA256SUMS.txt / raw/SHA256SUMS.txt
```

复跑：

```bash
# 对端 root；p2b_snap/p7b_biz 已在 /tmp
PEER_PW=... python tools/peer_ssh.py --put \
  _proj_10g/notes/p11_board_p3_0x32_20261026/tools/e1_latency.sh /tmp/e1_latency.sh
PEER_PW=... python tools/peer_ssh.py --sudo --timeout 180 "bash /tmp/e1_latency.sh E1BASE baseline"
PEER_PW=... python tools/peer_ssh.py --sudo --timeout 220 "bash /tmp/e1_latency.sh E1Lx load"
# 无 TCP SYN 臂：SKIP_TCP=1 ...
python _proj_10g/notes/p11_e1_latency_20261027/e1_metrics.py \
  _proj_10g/notes/p11_e1_latency_20261027/raw
```

⚠️ `p7b_lat_probe --no-check` 只对 UDP 1472 使用；996 臂必须带内容校验。
⚠️ E1 的 MID 窗 45 s > W43/W65 的 27.49 s 回卷周期；本件状态分类用 sink 速率，
**不要**用该窗的 W65 算 idle（E0.5 的 10 s 窗才是 W65 参考）。

---

## 6. 对“缩小时延”的下一步含义

1. **HLS 控制面**：9G 慢态负载没有可观测的尾延迟恶化；若业务控制面走 HLS，
   主项是服务时间（64 B ~0.1 ms、996 B ~0.4 ms、1472 B ~0.6 ms），不是 9G 排队。
2. **fast-path**：E1 没测到 A 口数据帧的逐包延迟；要回答“9G 下单条消息延迟”，
   必须 E1a 的 DP 域时间戳/计数器（或专用 RTL latency probe）。
3. **E1 仍缺快态**：5 个 load 全是 8.60–9.25（慢态）；需要重跑/改构型拿 ≥9.35 的快态。
4. **HLS echo 996B 边界**：任何 1500B UDP 内容判据先修此缺陷，否则“内容正确”是空判据。
