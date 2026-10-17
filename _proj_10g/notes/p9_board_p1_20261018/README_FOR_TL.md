# P11 / P1 板级验证（0x2B）—— README_FOR_TL

- 日期：2026-10-18 05:44–06:07 CST（唯一板级写者；TL 不参与板侧写）
- 轮目录：`_proj_10g/notes/p9_board_p1_20261018/`
- 施工权威：`p9_dual_sfp_p1_impl_20261018/DESIGN_v5.md` §10.4（v5.1 判据）+ 0x2B 构建件
  `p9_build_0x2B_20261018/build/wrapper_p4.bit`
- 纪律：**QSPI 零写入**（全部 JTAG 易失，1 MHz）；未跑 Vivado/xsim、未构建；未碰其他 agent 文件；
  `D:\repo\perfv` 未触碰；密码只作命令前缀、未落盘。
- 状态词：【已证】/【未判定】/【未定位】/【未测】。**本件不下 PASS/FAIL 裁定**。
  "未观测到" ≠ "不存在"；"不支持" ≠ "证伪"。
- 每件日志带本轮独有串 `P1BOARD-*` 与 mtime（见 `env/ROUND_TIMELINE.txt`）。

---

## 0. 摘要（逐项状态词，不是裁定）

| # | 项 | 本轮读数（摘要） | 状态 |
|---|---|---|---|
| 入口 | 板/对端 | BID `0x2A` / `0x08=0` / carrier p0=p1=1；无残留进程；无 iptables 规则；本机无 Vivado | 【已证】 |
| 烧录 | 0x2B | sha256 `7dd2ea33…2c23`（15,431,261 B）；`End of startup status: HIGH`；DONE；device-level remove+rescan；`LnkSta 5GT/s x4` / 2 BARs | 【已证】 |
| 身份门 | 0x2B | `0x04=0x2B` / **83 字** / `0x17C=0xffffffff` / MIR `0x16C..0x178` 可读 / `0x08=0` / CARRIER p1=p0=1 / **NFF=0（83 字）** | 【已证】 |
| S-1 | 静置背景 567 s / 40 样本 | `W77[31:8]` **绝对值 0** ×40；W76 事件/错误位 `[20:13]`/`[11:7]`=0；W78=0；W81=W82=0；`SNAP_STATUS[7]=0` ×40；gens 逐触发 +1 | 【已证】 |
| S-2 | p0 注入 2000 帧 | ΔW79=**+2000**；ΔW80=**+256000**；`ΔW80+4×ΔW79 = 264000 = Δport_tx_bytes` **逐字节精确**；W81=W82=0；stale=0；pcap 2000/2000、0 drop | 【已证】 |
| S-3 | TX_DIS 负对照（`0x08` bit0） | p0 carrier 1→0→1；`carrier_changes` **19→20→21**（+1/+1，记录实际值）；p1 全程 55 不变；板侧 W78=0、窗口 fresh | 【已证】（负对照有牙） |
| S-4 | LOS（拔 J7 AOC） | 远程两种近似（netdev down / 移除 p0 PCI function）都**不能停对端 TX**：W78[0] 恒 0、`los1_evt` 恒 0、ch0 束始终 fresh | 【未测】（无物理拔插条件） |
| S-5 | 停钟/快照超时 | 同上两臂：`rx_clk_out_0` 未停 ⇒ 超时未触发 ⇒ `SNAP_STATUS[7]` **从未置 1** | 【未测】（停钟不可实现） |
| S-6 | ch1 TCP 快流 1 臂 | **1084.6 Mbps**（sink 自报，2,000,000,425 B / 14.751 s）；`mism_bytes=0`、`stall_conns=0`、`fail_conns=0`；ss 逐秒 1064.0–1103.9（中位 1094.3） | 【已证】（单臂） |
| S-7 | 温度/功耗 | 板上无 XADC/sysmon/功耗仪器 | 【未测】（不造假读数） |
| 收尾 | 0x2A 回烧 | sha256 `aa44a0ed…a3b6`；HIGH+DONE；身份门 `0x2A` / 76 字 / `0x160=0xffffffff` / 2 BARs / `LnkSta x4` / `0x08=0` / carrier p1=p0=1 | 【已证】 |

---

## 1. 入口态（`env/ENTRY_CHECK.txt`）

`P1BOARD-ENTRY` t=1792273498.21（2026-10-18 05:44:58 CST）

- 板：`MAGIC=0x50360001` / `BID=0x0000002a` / `SCRATCH_0x08=0` / `UNIMPL_0x160=0xffffffff`；
  `p1b_snap.sh id`（`NW=76 EXPECT_BID=0x2A UNIMPL_ADDR=0x160`）= `ID_OK` / `ID_RC=0`
- 对端：`enp1s0f0np0` / `enp1s0f1np1` 均 `UP LOWER_UP`，10 Gb/s full，carrier=1/1，
  `carrier_changes` p0=17 / p1=53
- 残留：`p7b_tcp_sink` / `p7b_tcp_churn` / `p7b_udp_src` / `p7b_tcp_src` / `p7b_rate2_bench` /
  `tcpdump` 全部 NONE；`ss … dport :8080` established = 0
- `iptables -S`：仅三条默认策略（INPUT/FORWARD/OUTPUT ACCEPT），无规则
- 本机 `tasklist | grep -i vivado`：空

---

## 2. 烧录 0x2B 与身份门（`burn/BURN_0x2B_20261018_054501.txt`）

- 位流：`p9_build_0x2B_20261018/build/wrapper_p4.bit`
  sha256 **`7dd2ea3316dbed3915239d39391c90765ad6b7c8a9d472fa1c8fecca54ba2c23`**，15,431,261 B，
  mtime 2026-10-18 04:50:36（构建轮产物）。
- **锚的性质**：只有 **1 个独立锚**（构建产物）；`burn/wrapper_p4_0x2B.bit` 是本脚本刚拷的字节副本，
  **不是独立锚**（与 0x2A 晋级时同一登记口径）。
- 烧录：JTAG `192.168.0.38:3121`，1 MHz，`End of startup status: HIGH`，`TCPREG_PROG_DONE`，
  路径匹配、无 ABORT、stdout freshness=133 s（t0=1792273506，mtime=1792273639）。
- PCIe：device-level `remove` + `rescan` 一次成功：`LnkSta: Speed 5GT/s (downgraded), Width x4`，
  `identify_bars: 2 BARs: config 1, user 0`，`/dev/xdma0_user` + `/dev/xdma0_control` 均在。
- 身份门读数：

| 项 | 读数 | 期望 |
|---|---|---|
| `0x00` MAGIC | `0x50360001` | `0x50360001` |
| `0x04` BID | `0x0000002b` | `0x0000002B` |
| `0x14` MARKER | `0xdeadbeef` | `0xdeadbeef` |
| `0x17C` UNIMPL | `0xffffffff` | `0xffffffff` |
| `0x08` SCRATCH | `0x00000000` | 0 |
| `0x16C` MIR_STATUS | `0x00200000` | 可读（非 0xffffffff） |
| `0x170` MIR_DATA | `0x5a5a5a5a` | 可读 |
| `0x174` MIR_CTRL | `0x00000000` | 可读 |
| `0x178` MIR_DMA_CNT | `0x00000000` | 可读 |
| 窗口扫描 | **NFF=0**（83 字，0x20..0x168） | 0 |
| BAR / 链路 | 2 BARs / `5GT/s x4` | 2 / x4 |
| carrier | p1=1 / p0=1 | 1 |

- 烧后释放受控停流：`0x08 <- 0`（回读 0）。

---

## 3. 逐项读数

### S-1 静置背景（`raw/S1_STATIC_10min.log`，40 样本，span **567.17 s**）

- `P1BOARD-S1-BEGIN` 1792273673.51（05:47:53），`END` 1792274255.23（05:57:35）；
  采样 = W39/W76/W77/W78/W79/W80/W81/W82，每 ~14.5 s 一次。
- **主判据（DESIGN v5.1 / FINDINGS 中-4）：`W77[31:8]` 绝对值 == 0 —— 40/40 成立**。
  `W77` 全部样本的高 24 位为 0；低 8 位 `vcc_cyc` 是**自由计数 mod 256**（样本集合
  {2,3,9,10,22,33,37,73,84,98,107,109,111,112,113,114,124,125,141,143,144,153,156,161,166,167,170,187,190,199,202,206,210,227,233,235,241,250}，
  属活动指示，不作判据）。
- `W76` 恒为 `0x2000100c`：`[2]block_lock=1`、`[3]rx_status=1`、`[4]hi_ber=0`、`[5]rx_local_fault=0`、
  `[6]tx_local_fault=0`、`[20:13]rx_error=0`、`[11]fifo_error=0`、`[10:9]bad_code(_valid)=0`、
  `[8:7]framing_err(_valid)=0`、`[12]valid_ctrl_code=1`（level，健康链路预期）、`[29]gtpowergood=1`、
  `[30]ch0_sig=0`。**事件/错误位 = 0，40/40**。
- `W78` 恒 `0x00000000`：LOS1/LOS2 level=0、`los1_evt`/`los2_evt`=0。
- `W81`/`W82` 恒 0（每样本都先核 `SNAP_STATUS[7]=0`）。
- `SNAP_STATUS[7]`（ch0_stale）= **0 × 40**；每样本 `gen` 恰好 +1（2→41，无并发写者）。
- 背景（记录，不是判据）：`W79` 20→144（+124 帧）、`W80` 3253→22942（+19,689 B）；
  分布为两段活动（0–160 s、450–567 s）+ 中间 ~290 s 平坦 ⇒ 对端 p0 的 IPv6/DHCP 背景。
- ch1 交叉核对：`W39` 与 `W76` 逐样本同为 `0x2000100c`。
- carrier p0/p1 全程 =1/1，`carrier_changes` 19/55 全程不变。
- **偏离登记**：目标 10 min，实测 **567 s（9.45 min）**（40×14.5 s + 每次快照开销）。
  全部判据为"绝对值为 0 且 40 个样本全同"，该时长不改变判据方向；如实登记。

### S-2 p0 已知帧注入（`raw/S2_INJECT.log`，`raw/p1b_S2.pcap`）

构造：AF_PACKET raw（`p1b_rawsend.py`），dst=broadcast、ethertype `0x88B5`、内容长 128 B/帧
（14 头 + 114 载荷，线上含 FCS 132 B），N=**2000**，src MAC `02:00:00:00:00:01`。

| 仪器 | PRE | POST | Δ | 换算 |
|---|---|---|---|---|
| 板 W79 ch0 好帧 | `0xa9` = 169 | `0x879` = 2169 | **+2000** | 与 N 逐帧相等 |
| 板 W80 ch0 载荷字节 | `0x6951` = 26,961 | `0x45151` = 282,961 | **+256,000** | = 2000×128（wire−4） |
| 对端 p0 `port_tx_packets` | 12,534 | 14,534 | **+2000** | 与 N 相等 |
| 对端 p0 `port_tx_bytes` | 2,050,634 | 2,314,634 | **+264,000** | = 2000×132（含 FCS） |
| pcap | — | 2000 packets captured / 0 dropped | 2000 | 仅"已发出"见证（抓包点在驱动队列，非线上） |
| 板 W81/W82 | 0 / 0 | 0 / 0 | 0 | FCS 错/丢帧均为 0 |
| `SNAP_STATUS[7]` | 0 | 0 | — | 本代 ch0 束 fresh |

**恒等式**：`ΔW80 + 4×ΔW79 = 256,000 + 8,000 = 264,000 = Δport_tx_bytes` —— 逐字节精确。
（`p1b_S2.pcap` md5 `e4d1970c8328f585e3b4fe2e44c7dc26`，288,024 B，仅 2000 帧，随轮保存、不入库大件清单。）

### S-3 TX_DIS 负对照（`raw/S3_TXDIS.log`）

| 时刻 | `0x08` | p0 carrier | p0 carchg | p1 carrier | p1 carchg | 板 W76 | 板 W78 | W79/W80 | stale |
|---|---|---|---|---|---|---|---|---|---|
| PRE | 0x0 | 1 | 19 | 1 | 55 | `0x2000100c` | 0 | 0x879/0x45151 | 0 |
| SET bit0=1（回读 `0x1`） | 1 | — | — | — | — | — | — | — | — |
| t+4 s | 1 | **0** | **20** | 1 | 55 | `0x2000100c` | 0 | 冻结 | 0 |
| t+6 s | 1 | 0 | 20 | 1 | 55 | `0x2000100c` | 0 | 冻结 | 0 |
| RESTORE 0x0（回读 `0x0`）→ t+6 s | 0 | **1** | **21** | 1 | 55 | `0x2000100c` | 0 | +12 帧背景 | 0 |

- 判据成立：对端 p0 `carrier 1→0`、`carrier_changes` **单调增 +1（实际 19→20）**；恢复后
  `0→1`、再 `+1（20→21）`。**p1 不受影响**（carrier 恒 1、carchg 恒 55）⇒ 单口隔离成立。
- 说明：`0x08` bit0 = `sfp1_tx_dis`（J7/ch0 的本端 TX）；板侧 `W78` LOS 仍为 0 是**预期**
  （LOS 输入来自对端 TX，不受本端 TX_DIS 影响），且 ch0 快照仍 fresh（RX 时钟未停）。

### S-4 LOS / S-5 停钟（`raw/S4_S5_LINKDOWN.log`、`raw/S4_S5_PCIREMOVE.log`）

两次"尽力"动作，均**未能**在板侧产生 LOS 或停钟：

1. **对端 `ip link set enp1s0f0np0 down`（12 s）**：p0 管理态 down（`carrier` 读为
   `Invalid argument`），但 `carrier_changes` 恒 21（模块物理链路未断）；板侧 12/12 样本：
   `W76=0x2000100c`（block_lock 仍 1）、`W78=0`、`W79` 冻结 `0x887`、`SNAP_STATUS[7]=0`。
   up 后 carrier=1、carchg 仍 21。
2. **仅移除 p0 PCI function `0000:01:00.0`（15 s）**：`P0_IFACE=GONE`、`P1_IFACE=PRESENT`；
   板侧 15/15 样本：`W76=0x2000100c`、`W78=0`、`W79` 冻结 `0x8a7`、`SNAP_STATUS[7]=0`。
   `rescan` 后 p0 回（carrier=1；新设备实例 ⇒ `carrier_changes` 由 21 重置为 1），p1 全程 55 不变。
   ⇒ 即使 MAC/PCIe 功能被移除，SFP+ 模块仍持续发送（CDR 时钟未停、无 LOS）。

结论：
- **S-4 = 【未测】**：LOS 电平/沿未被激励（`W78[0]` 与 `W78[23:16]` 恒 0）。"未观测到 ≠ 不存在"；
  LOS 通路（引脚 B11 → 3FF → 事件）板级仍未证。需要**物理拔 J7 AOC**（本轮无此条件）。
- **S-5 = 【未测】**：`rx_clk_out_0` 未停，快照超时机制未被触发；`SNAP_STATUS[7]` 从未置 1。
  （超时逻辑本身已在 G1-f 仿真门覆盖；板级触发条件未达。）

### S-6 ch1 TCP 快流（`raw/S6_CH1_FAST.log`）

配方 = 0x2A C-fast 同一臂：`p7b_tcp_sink --host 192.168.100.2 --port 8080 --rcvbuf 2920
--conns 1 --maxbytes 2000000000 --check lane8`，单连接，DUR=30 s 采样。

- **sink 自报**：`bytes=2,000,000,425` / `dur_ms=14,751.495` / **`Mbps=1084.636`** /
  `first_mismatch=-1` / **`mism_bytes=0`** / `stall_conns=0` / `fail_conns=0` / `poll_tmo=0` /
  `checked_bytes=2,000,000,425` / `THREADED=on` / `check=lane8`。
- **ss 逐秒**：14 个整秒样本，**min 1064.0 / max 1103.9 / mean 1086.5 / median 1094.3 Mbps**。
- **对端 p1 NIC**：`port_rx_bytes` 505,456,469,945→507,535,934,818（**+2,079,464,873**）；
  `port_rx_packets` 333,094,144→334,464,019（**+1,369,875**）；Δbytes/Δpackets = **1517.99**
  （≈1518 = 1514 载荷帧 + FCS；与历史 J0 的 1518.0009 同族）。
- **板侧**：`W51` 0→`0x77359b5d`（2,000,001,885，≈2 GB）；`W52` 0→`0x14e709`（1,369,865）；
  `W53=0`；**`W54=0`**；`W55` 0→7；`W75=0`；`W71/W73`=1。
  `W51 − sink bytes = 1,460 B`（**恰好 1 MSS**，= 对端 maxbytes 关闭时在飞的那一帧）。
- 计数自洽：`W43`/`W36` 的 mod 2³² 增量 660.08M/660.13M，窗口 31.7 s ⇒ ≈156.25 MHz 计数
  （`W65/W43 = 59.9%` 空闲，与"14.75 s 传输 + 17 s 停流"一致）。
- 判据：目标 ≥800 Mbps、`mism_bytes=0`、无 stall —— **本条单臂全部成立**。
- 说明：本轮**没有**跑 0x2A 同会话 A/B 臂（任务口径为"至少 1 臂"）。历史 0x2A C-fast 中位
  801.2 Mbps 与本轮 1084.6 Mbps **不是同会话 A/B**，不对差异作归因。

### S-7 温度/功耗 + 双口并存

- **温度/功耗 = 【未测】**：板上无 XADC/sysmon、无功耗仪器；不造假读数。
- 双口并存静置/轻载：由 S-1 覆盖（567 s 两口 carrier=1、ch1 无业务；W81/W82 全程 0）。
  S-3/S-4/S-5 期间 p1 始终 carrier=1、carchg 不变 ⇒ 无"ch0 动作打坏 ch1"的观测。

---

## 4. 收尾态（`env/FINAL_LIVE_READ.txt`，`burn/BURN_0x2A_20261018_060332.txt`）

- 回烧 **0x2A**：`p9_build_0x2A_20261017/build/wrapper_p4.bit`
  sha256 **`aa44a0eda1604623eac951afc26b9f27d4798fc414a5eb9c7137ee47f9a2a3b6`**（15,431,261 B）；
  `End of startup status: HIGH`、DONE、freshness 132 s；device-level remove+rescan 一次成功。
- 身份门：`MAGIC=0x50360001` / `BID=0x0000002A` / `MARKER=0xdeadbeef` /
  `0x160=0xffffffff` / `0x08=0` / MIR `0x150..0x15C` 可读（`0x00200000/0x5a5a5a5a/0/0`）/
  NFF=0（76 字）/ 2 BARs / `LnkSta 5GT/s x4` / carrier p1=1、p0=1。
- 一次快照（`NW=76 EXPECT_BID=0x2A`）：`SNAP_STATUS gen=1 … ch0_stale=0`（0x2A 无 ch0 束，
  bit7 = 不适用，恒 0）；`W0/W1/W51/W55/W75=0`、`W20=2`、`W43=0x04ef9a3d`。
- `iptables -S`：仍只有三条默认策略（本轮**从未**添加任何规则，无需清理）。
- 残留进程：`p7b_tcp_sink`/`p7b_tcp_churn`/`p7b_udp_src`/`tcpdump` 全部 NONE。
- **QSPI：零写入**（两次烧录均 JTAG 易失；无任何 QSPI 工具调用）。

---

## 5. 偏离 / 未测 / 需 TL 裁定的事项

1. **S-1 时长 567 s（目标 600 s）**：40 样本 × 14.5 s + 开销；判据为"绝对值为 0"，40/40 全同。
2. **S-4 = 【未测】**：无物理拔插 AOC 条件。远程近似（netdev down、移除 p0 PCI function）
   均不能停对端 TX（模块持续发 idle）⇒ LOS 未激励。证据见上（W78 恒 0、ch0_stale 恒 0）。
3. **S-5 = 【未测】**：同上，`rx_clk_out_0` 未停 ⇒ 超时未触发。需要物理断纤/停激光才能测。
4. **S-7 = 【未测】**：无板上温度/功耗仪器。
5. **任务书里 0x2A 收尾括号与现役态不符**：任务写"双独立锚 `79c9cf43…bec8`；身份门 0x28/75 字/
   `0x15C`" —— 那是 **0x28** 的身份。本轮按**实际现役 0x2A**（sha `aa44a0ed…a3b6` / BID 0x2A /
   76 字 / UNIMPL `0x160`）收尾，与任务环境描述一致。请 TL 确认这是任务书笔误。
6. **0x2B 烧录只有 1 个独立锚**（构建产物）；`burn/` 里的位流副本是本轮拷贝，**不是独立锚**。
7. **p0 的 NM 管理态**：PCI-remove 臂前执行过 `nmcli device set enp1s0f0np0 managed no`；
   rescan 后 NM 又显示 `connecting (getting IP configuration)`（与入口态相同）。p1 全程 unmanaged。
8. **p0 `carrier_changes` 在 PCI remove/rescan 后重置**（21→1，新设备实例）⇒ 跨臂不能直接比较
   carchg 绝对值；S-3 的 19→20→21 是**同一臂内**读数。
9. **背景流量**：S-1 的 W79/W80 增量（+124 帧 / +19,689 B）来自对端 p0 的 IPv6/DHCP 背景；
   它不是板侧错误，S-2 的 4 s 注入窗内背景为 0（Δ 逐帧精确）。
10. **pcap 抓包点在驱动队列，不在线上**（工程教训 #8）：仅作"已发出"见证；S-2 的线上见证
    是板侧 W79/W80 + NIC `port_tx_*`。
11. **S-6 只跑了 0x2B 单臂**（任务口径"至少 1 臂"）；未做同会话 0x2A A/B，不对 1084.6 Mbps 与
    历史 801.2 Mbps 的差异作归因。
12. 本轮全部板级命令的唯一写者 = 本 agent；未在 S-1 等长窗口内并发触发快照（每样本 gen +1 自证）。

---

## 6. 文件清单

```
p9_board_p1_20261018/
├── README_FOR_TL.md            本件
├── FINAL_STATE.txt             终态一页纸（机器可读）
├── burn/
│   ├── burn_p1_board.sh        本轮烧录脚本（0x2B / 0x2A 两 case）
│   ├── BURN_0x2B_20261018_054501.txt / BURN_0x2A_20261018_060332.txt
│   ├── BURN_stdout_copy_*.txt  Vivado 原始 stdout 拷贝
│   └── wrapper_p4_0x2B.bit / wrapper_p4_0x2A.bit   （sha256 见 READINGS/BURN 日志）
├── env/
│   ├── ENTRY_CHECK.txt         入口态（P1BOARD-ENTRY）
│   ├── FINAL_LIVE_READ.txt     收尾态（P1BOARD-FINAL-LIVE）
│   └── ROUND_TIMELINE.txt      时刻线/独有串
├── raw/
│   ├── S1_STATIC_10min.log     S-1 40 样本（567 s）
│   ├── S2_INJECT.log           S-2 注入 + NIC/pcap 对账
│   ├── p1b_S2.pcap             S-2 抓包（288,024 B，2000 帧）
│   ├── S3_TXDIS.log            S-3 TX_DIS 负对照
│   ├── S4_S5_LINKDOWN.log      S-4/S-5 臂 1（netdev down）
│   ├── S4_S5_PCIREMOVE.log     S-4/S-5 臂 2（移除 p0 PCI function）
│   └── S6_CH1_FAST.log         S-6 ch1 TCP 快流
└── tools/
    ├── p1b_rawsend.py          S-2 AF_PACKET 帧注入器
    ├── p1b_s2.sh / p1b_s3.sh / p1b_s5_pci.sh / p1b_s6.sh
    └── （快照读侧 = `_proj_pcie/p7b_biz/p7b_snap.sh` md5 58ad0951…，上传为对端 /tmp/p1b_snap.sh）
```

- 大件/对端临时件：对端 `/tmp/p1b_S2.pcap`（已取回本地 `raw/`）、`/tmp/p1b_*.log`；
  0x2B/0x2A 位流各 15,431,261 B，按轮保留在 `burn/`，**不入库**（与历轮口径一致）。
- 读侧工具 md5（对端）：`/tmp/p1b_snap.sh` `58ad0951d87fcef797271dc252b9c4a3`；
  `/tmp/p7b_biz/p7b_tcp_sink` `f62299291fcb9e02afe109c4ea1f90ab`（未改动）。

---

## 7. 状态词汇总（供 TL 引用，不是裁定）

| 项 | 状态词 | 一句话 |
|---|---|---|
| 0x2B 烧录/身份门 | 【已证】 | 83 字 / 0x17C / 2 BARs / x4 / NFF=0 全中 |
| S-1 | 【已证】 | W77[31:8]=0、W76 事件位=0、W78=0、W81/W82=0、stale=0，40/40 |
| S-2 | 【已证】 | 2000 帧逐帧对账，ΔW80+4ΔW79=Δport_tx_bytes 精确 |
| S-3 | 【已证】 | p0 carrier 1→0→1、carchg +1/+1，p1 隔离 |
| S-4 | 【未测】 | LOS 未被激励（无物理拔插；远程两法不停光） |
| S-5 | 【未测】 | 停钟超时未被触发（rx_clk 未停） |
| S-6 | 【已证】（单臂） | 1084.6 Mbps / mism=0 / stall=0 |
| S-7 | 【未测】 | 无板上温度/功耗仪器 |
| 0x2A 收尾 | 【已证】 | BID 0x2A / 76 字 / 0x160 / 0x08=0 / carrier=1 |
