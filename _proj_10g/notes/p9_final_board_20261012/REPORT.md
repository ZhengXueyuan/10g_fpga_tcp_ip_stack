# P9 收尾板级轮报告 —— 位流 `0x23`（AXIS + clr 新口径）上补两格"从未测过"的 PCIe 面：
# T1 = H2C 写通道首次激励 · T2 = AXIS 读出口（`--stream`）上的 TCP 源臂

> **边界声明**：本轮**未换烧**（板上现役就是 `0x23`，现读核过：`0x04 = 0x00000023`）⇒ 未写 QSPI、未动 `rtl/` · `tb/` · `board/` 与任何工具源码
> （**只读**引用上轮脚本/配方）；`/tmp/p7b_biz` 与历史目录（`/tmp/p9_board_0x23` · `/tmp/p8_tcp_0x21` · `/tmp/p8_board`）全程只读、部署前后 md5 复读未动；
> 本轮一切对端改动落在**自己的** `/tmp/p9_final/`，逐条可回退（§5）。未碰 `D:\repo\perfv`；git 只读；口令只作 `--sudo` 前缀、未落盘。
> **本报告不下 PASS/FAIL 裁定**；"未观测到"一律写成"未观测到"，不写成"不存在"；不把"H2C 写成功"外推成"数据被正确处理"（数据是**故意丢弃**的）。

---

## 0. 一句话结论（观测，非裁定）

1. **T1（H2C 首次激励）= 6/6 跑干净**：4 KiB / 64 KiB / 1 MiB 各 **2 跑**（两趟写同一份数据件），**全部 RC=0**、工具内 pwrite **73.5 µs / 113.4 µs / 808.8 µs**（55.7 / 578.1 / 1296.4 MB/s）、**0 新 dmesg 行**、无 hang/超时；写前/写后**寄存器与触发式快照逐字不变**（`MIR_STATUS` / `MIR_CTRL` / `MIR_DMA_CNT` / `SCRATCH_0x08` / `BID` + `W53/W54/W70/W11/W13`）。
   ⇒ 观测口径 = **"恒 `tready=1` 的 H2C 吞噬器没卡死、也没扰到别的通道"**；**不是**"数据被正确处理"（板上无 H2C 计数点、数据按设计丢弃）。
2. **T2（AXIS TCP 源臂）= 3/3 跑干净**：`ΔW70 ≡ 0`（三跑）、**式 A / 式 B 两条恒等式全闭**（T2C 的 `式A = 8` 是**残拍见证**，证明这两条式有牙）、`pc == taken == K`、`level_end = 0 / premise_level0 = 1`、`MIR_VERIFY rc=0 first_mismatch=-1` ×3、**离线独立复算（另一条路径）3/3 逐字节全等**、`ΔW53` 与发端 `tx_bytes` 逐跑逐位闭合；**T2A 与 T2B 的抓取样 md5 相同**（`c859f418…`）。
3. **与 MM 轮的 TCP 读数并列（非严格 A/B：位流/读出口/背景都不同）**：MM 轮（`0x21` · `--dma` 环）8 跑 `ΔW70 = 0`、K=8192/16384 三跑 `rc=0 fm=-1`；本轮（`0x23` · `--stream`）同样 `ΔW70 = 0` 且**把 `pc` 做到了 `= K`**（MM 轮的 DMA 环对 `K > 16 KiB` 结构性拿不到"从偏移 0 捕获"）。
4. ⭐ **一条环境差异（登记，不归因）**：本轮**全程未观测到 UDP 泛洪背景**（NIC `port_rx_bytes` 在 2 s 窗内逐字不动；全程增量 ~5.6 MB / 5.5 min ≈ 17 KB/s，与 809k fps 差 4 个数量级）—— 与 p8 TCP 轮"背景 = 板侧 UDP 泛洪在跑"**不同**。两个辅助探针把**最便宜的那一半机理**钉住了：**对端 ARP 邻居当时是 `cache`/无 `lladdr`** ⇒ 第一次探针的 UDP 包**根本没出宿主**；补 ARP 后同一个探针 ⇒ 板侧 `W11 = 0x1000`（真收到了）+ NIC 3 s 窗 **+3.68 GB / +2.43 M 帧 ≈ 808,782 fps**（泛洪起来了）。**"泛洪何时起"的机理本身仍未分离**（表空 vs 需新 learn vs ARP 前提）。

---

## 1. 现读身份与现态（step0，原始件 `runs/STEP0_20261012_020452.txt`）

| 判据 | 期望（派单） | 现读 | 结论 |
|---|---|---|---|
| `0x04` BID | `0x00000023` | `0x00000023` | 中 |
| 快照几何 | 71 字 | 逐字扫 `0x20..0x138` 共 71 字，`WINDOW_SCAN_NFF = 0` | 中 |
| 未实现地址 | `0x14C` | `0x14C = 0xffffffff` | 中 |
| PCIe 链路 | `LnkSta x4` | `LnkSta: Speed 5GT/s (downgraded), Width x4`（`LnkCap: 8GT/s x4`） | 中 |
| BAR | 2 BARs | `Region 0: 1M` / `Region 1: 64K`；dmesg `identify_bars: 2 BARs: config 1, user 0` | 中 |

- `MAGIC_0x00 = 0x50360001`；`SCRATCH_0x08 = 0x00000002`（**受控停流**，`CARRIER=0` / `Link detected: no`）；
  `MIR_CTRL(0x144) = 0x00000000`；`MIR_STATUS(0x13C) = 0x00200000`（`ver=4` = ST/`cap=0`/`any_drop=0`/`unf=0`/`level=0`/`src_sel=0`）；`MIR_DMA_CNT = 0`。
- 触发式快照（本轮共用 `p7b_snap.sh`，`NW=71 EXPECT_BID=0x00000023`）：`W53 = W54 = W70 = W11 = W13 = 0`；`W5 = 0x68c13258`（FE 自由计数）。
- 归档位流双核：`_proj_10g/notes/p9_build_0x23/wrapper_p4.bit` 与 `p9_board_0x23_20261011/burn/wrapper_p4_0x23.bit` **同为** `066a3923…3126`（15,431,261 B）—— **本轮只核不烧**。
- 无残留进程（`PROC_SCAN_DONE`）；dmesg 基线 **3288 行**；`/tmp/p7b_biz` 四件 md5 基线 = `a3faafd3…` / `ba2faf79…` / `b2f2e962…` / `b0322279…`。

**读侧版本一处订正（如实报）**：第一趟 T1 我用的是 `/tmp/p7b_biz/p7b_snap.sh`（md5 `ba2faf79…`）—— 它是**旧修订**（`W70` 无标签，打 `?`）。随后换成**权威现役件** = 仓库 `_proj_pcie/p7b_biz/p7b_snap.sh`（md5 `6325658a…`，= `/tmp/p9_board_0x23` 那份，含 `[70]=mir_drop_bytes`）并**整批重跑 T1**（第二趟）。两趟数值逐字相同（标签不影响取值）；报告一律以第二趟（权威件）为准。

---

## 2. T1 —— H2C 写通道**首次激励**

### 2.1 结构前提（读源码核过，不是假定）

- AXIS 版 H2C = IP 的 `m_axis_h2c` 输出 + 板上**恒 `tready=1` 的吞噬器**：`board/wrapper_p4.v:3860` `assign mir_h2c_tready = 1'b1;`（另两个宏分支 `:3880` / `:3897` 同值常量）⇒ **与 `MIR_CTRL` / `carrier` / 停流态全部无关，结构上恒 ready**。
- 因此本轮**不需要**恢复 carrier、也**不需要**动任何寄存器：直接在"受控停流 + `MIR_CTRL=0`"的现态下写。
- 工具 = XDMA 配带 `dma_to_device`（`-d /dev/xdma0_h2c_0 -f <file> -s <size> -c 1`，内部 = 一次 `pwrite`）；数据 = 对端 `/dev/urandom` 现生成。

### 2.2 读数（两趟 × 3 档；原始 stdout = `runs/T1_H2C_20261012_020630.txt`（第一趟）/ `…_020701.txt`（第二趟））

数据件（两趟**同一份**，mtime 02:06 未再生成）：`h2c_4096.bin` `8876f4d1…` · `h2c_65536.bin` `fb07903b…` · `h2c_1048576.bin` `46f51092…`

| 档 | 趟 | `dma_to_device` RC | pwrite 耗时（工具自报） | BW（工具口径） | 前后 ELAPSED | dmesg 新行 | `MIR_*`/`0x08`/`BID` 前后 | 快照前后 |
|---|---|---|---|---|---|---|---|---|
| 4 KiB | t1 / t1r2 | 0 / 0 | 73,517 ns / 80,535 ns | 55.72 / 50.86 MB/s | 0.00203 s / 0.00206 s | **0 / 0** | 逐字相同 | 逐字相同 |
| 64 KiB | t1 / t1r2 | 0 / 0 | 113,364 ns / 112,181 ns | 578.10 / 584.20 MB/s | 0.00208 s / 0.00202 s | **0 / 0** | 逐字相同 | 逐字相同 |
| 1 MiB | t1 / t1r2 | 0 / 0 | 808,839 ns / 819,822 ns | 1296.40 / 1279.03 MB/s | 0.00316 s / 0.00318 s | **0 / 0** | 逐字相同 | 逐字相同 |

- 不变量的逐跑原始行（每档 pre/post 各一次）：`MIR_STATUS = 0x00200000`、`MIR_CTRL = 0x00000000`、`MIR_DMA_CNT = 0x00000000`、`SCRATCH_0x08 = 0x00000002`、`BID = 0x00000023`；快照 `W53/W54/W70/W11/W13 = 0`（`SNAP_END … nff=0`）；`W5/W43` 作为自由计数照跑、`W20 = 0x15 = 21` 恒定。
- 每跑带**本次独有串** `UQ=t1_<size>_<epoch>` / `t1r2_…`（防"读了上一次的陈旧件"）；快照 `gen` 逐次 +1 自证新鲜（`gen=5,6,7,8,9` 第一趟；`10..15` 第二趟）。
- `dmesg` 核验：三档 × 两趟 `NEWDMESG_COUNT = 0`（按行数差分）；收尾复读**全量** dmesg 的 `xdma` 涉错面 = 最新一条 `transfer_abort` 停在 `[188044.96]`（**上一轮** P2B 首跑那笔），本会话无新 `error/timeout/abort/fail` 行（本会话新增行只有 §4 的两组 `sfc link down/up`）。

### 2.3 与派单描述一致 / 需要点明的三处

1. **一致**：工具（`dma_to_device`）、档位（4 KiB / 64 KiB / 1 MiB，每档一跑 ⇒ 本轮做成每档两跑）、判据（返回码 + dmesg + 其它通道不受影响）都按派单执行；**未出现 hang/超时** ⇒ 未触发"记原始 dmesg + 复现次数 + 停下报你"那条分支。
2. **部署首调用失败（如实登记）**：第一次 `run_h2c.sh` 在 `peer_ssh.py --put` 上失败 —— 本机是 **Windows Python**，`--put` 的 local 参数不吃 git-bash 的 `/d/…` 形式（`FileNotFoundError: '/d/repo/…'`）。该次日志（`runs/T1_H2C_20261012_020617.txt`）里的 3 个"档"全是 `RC=127`（远端脚本根本没到）⇒ **未执行任何写**，**不作测量**；改成 `D:/…` 后才跑出 §2.2。
3. **一处不能外推**（派单已点名，此处坐实）：**板侧没有 H2C 计数点**、数据按设计丢弃 ⇒ 本档**只**证明"吞噬器没卡死 + 没扰到别的通道"。**"写成功" ≠ "数据被正确处理"**；`H2C 写 1 MiB @1296 MB/s` 也只是**工具侧 pwrite 完成时间**（含 IP/驱动的分片开销），**不是**链路带宽读数。

---

## 3. T2 —— AXIS 读出口（`--stream`）上的 TCP 源臂（`src_sel=1`）

### 3.1 配置与协议（逐跑同构）

- 对端：`p7b_tcp_src --host 192.168.100.2 --port 8080 --bytes K --pace-bps 2500000 --no-verify-down`（**口 = 8080**：板上 TCP 服务口，与 p8 轮实测一致；`8081` 是 UDP app 口，本臂不用）。
- 板侧：`p7b_mir_dump --bid 0x23 --bytes K --stream --src tcp --pat-off 0 [--k-bytes N] --buf-mb 128 --seconds 40`（**TCP 路 `--pat-off` = 0**，= 每连接从偏移 0 起；工具对 TCP + `--stream` **无额外要求**，`K % 8 == 0` 是 stream 合同的硬门，K 全取 8 的倍数）。
- 顺序：**先 arm（工具内部 `clr → cap_en + dma_en + src_sel`）→ `sleep 2` → 再建连**（保证首字节起就被抓）。
- 前置：恢复 `carrier`（`0x08 = 0`）+ 临时 `fq` 根 qdisc（`SO_MAX_PACING_RATE` 生效前置；与 p8 TCP 轮同手法）。**pacing 生效的活见证** = `ss` 的 `pacing_rate 20000000bps/20000000bps`（= 2.5 MB/s × 8，**逐字**）。

### 3.2 读数（3 跑；原始件 = `runs/T2_TCPSTREAM_20261012_020900.txt` + `runs/mir_T2*.log` / `src_T2*.log` / `ss_T2*.log`）

| 跑 | K / 源交付 | 工具 `MIR_STREAM_*` 原始行（逐字摘要） | 离线独立复算 |
|---|---|---|---|
| **T2A** | 1,048,576 / 同 | `DONE pc=1048576 reads=1 partial=0 short=0 read_error=0` · `ACCT pc=1048576 taken_bytes=1048576 dW70=0 w70a=0 w70b=0 words1=262144 dwords=262144 K=1048576` · `QUIESCE level_end=0 quiesced=1 premise_level0=1 waited_ms=0.0` · `IDA … -> 0 band=[0,32] closed_a=1` · `IDB … -> 0 band=[0,24] closed_b=1` · `WRAP wrap_seen=0 dword_max_step=262144` · `GAP host_miss_bytes=0` · **`VERIFY rc=0 first_mismatch=-1 of pc=1048576`** | `first_mismatch=-1 mism_bytes=0`（1048576/1048576）md5 `c859f418…` |
| **T2B** | 1,048,576 / 同（重复） | 逐行与 T2A 同（`pc/taken/dW70/两式/quiesce/verify` 全部同值） | `first_mismatch=-1 mism_bytes=0`；**md5 与 T2A 逐位相同** |
| **T2C** | 262,144 / **262,152**（残拍见证） | `ACCT pc=262144 taken_bytes=262152 dW70=0 words1=65538 K=262152` · `IDA -> 8 band=[0,32] closed_a=1` · `IDB -> 0 closed_b=1` · `GAP host_miss_bytes=8` · `VERIFY rc=0 first_mismatch=-1 of pc=262144` | `first_mismatch=-1 mism_bytes=0`（262144/262144）；抓取样尾后 8 B（图案 `[262144,262152)` = `a6af48c234f08abf`）**只进式 A** |

- **板侧账（触发式快照）**：`W53`（`app_rx_bytes`）= `0 → 0x100000 → 0x200000 → 0x240008`，逐跑与发端 `tx_bytes` **逐位闭合**（1,048,576 / 1,048,576 / 262,152）；**`W54`（`app_mismatch`）三跑全 0**；**`W70`（`mir_drop_bytes`）三跑全 0**；`W11/W13`（UDP 侧）三跑全 0（本臂不碰 UDP）。
- **发端**：`SRC_CONNECTED 192.168.100.2:8080` · `SRC_DRAINED tx_bytes = K` · `send_err=0 poll_tmo=0` · **`PIN_CPU=5`** 见证逐跑在位（`--no-pin` 未用）；`rx_bytes`（板→对端下行图案）≈ 1.5 MB/跑。
- **运行中形态（`ss -tinp`）**：`mss:1460`（⇒ 逐段 1460 B ⇒ 相位 4）· `pacing_rate 20000000bps` · `snd_wnd:49152` · `rtt 0.055–0.087 ms` · `rwnd_limited 2.4–2.7%` · T2A 采样 `rcv_ooopack:22`（**登记**：对端栈侧有 22 个乱序包计数，本轮未追）。
- **`MIR_VERIFY` 的语义**（源码口径）：内容判据 = **纯内容**（对 `pc` 个字节逐字节）；"不足量"由式 B 解释、不单独判红。
- ⭐ **一条只有本轮能做出来的旁证**：T2B 与 T2A 抓取样 **md5 逐位相同** ⇒ 两次独立会话（两次建连、两次 arm）产出的字节流**位级一致**。

### 3.3 与 MM 轮（p8 TCP 轮）并列 —— **非严格 A/B**（位流 / 读出口 / 背景三处都不同）

| 量 | `0x1F`（镜像 v1 · **user-BAR 路径**） | `0x21`（STG · **`--dma` 环**） | **`0x23`（本轮 · `--stream`）** |
|---|---|---|---|
| `ΔW70` | 240,932（= K 的 **91.9%**） | **0**（8 跑，≈2.92 MB）／BAR1 臂 213,968（81.6%） | **0**（3 跑，≈2.36 MB） |
| `pc`（抓取字节） | 21,212 | 8,192–262,144（K>16 KiB 结构性拿不到全流） | **= K**（三跑） |
| `MIR_VERIFY` | `rc=1 fm=8` | `rc=0 fm=-1`（K=8192/8192/16384） | **`rc=0 fm=-1` ×3** |
| `ΔW53`（板 app 收字节） | = K | = K（逐跑） | **= K（逐跑逐位闭合）** |
| `ΔW54`（板 app 自检） | 0 | 0（10 跑） | **0（3 跑）** |
| 结构上界 | 主机逐字 mmap 弹出（无排空器） | 16 KB 环 | AXIS C2H 平铺流 + 128 MB 预触页缓冲 |

**三处不同（必须一起读）**：① 位流 `0x1F`/`0x21` → `0x23`；② 读出口 `BAR`/`--dma` → `--stream`；③ **背景**：p8 轮**有** UDP 泛洪（≈809k fps），本轮**未观测到**（§4）⇒ 本表只作"整体对打"，**逐因归属不成立**。

---

## 4. 背景条件登记 + 两个辅助探针（`runs/AUX_UDP_PROBE_*.txt` / `AUX_UDP_PROBE2_*.txt`）

**现象（观测）**：本轮 T1/T2 全程**未观测到** UDP 泛洪背景 —— `port_rx_bytes` 在 2 s 窗内**逐字不动**（`25424583063552`），全程增量 ~5.6 MB / 5.5 min ≈ **17 KB/s**；而 p8 轮的背景读数 ≈ **809k fps / 9.8 Gbps**。两次 `0x08=0`（恢复 carrier）期间也一样（T2 期 ~60 s、探针 1 期 ~13 s）。

**探针 1（停流态下先发包）**：发了 64 个 UDP 包（4096 B 到 8081；工具自报 `pkts=64 pay_bytes=4096 call_errors=0`）→ 恢复 carrier 后 NIC **仍逐字不动** ⇒ 当时结论"没起泛洪"**成立但归因错**。

**探针 2（先查邻居 + 先恢复 carrier 再发包）**：⭐ 关键读数 ——
- `ip neigh show 192.168.100.2` **当时 = `dev enp1s0f1np1 src 192.168.100.100 uid 1000  cache`（无 `lladdr`）** ⇒ **探针 1 的包根本没出宿主**（ARP 未解）。
- 恢复 carrier（`0x08=0`，`CARRIER=1` / `Link detected: yes`）→ 发同一探针 ⇒ **板侧 `W11`（`udpapp_rx_bytes`）`0 → 0x1000 = 4096` 逐位等于我发的载荷**（**板确实收到了**）；邻居表变 `lladdr 00:0a:35:01:fe:c0 REACHABLE`。
- NIC 3 s 窗：`+3,683,194,746 B / +2,426,347 帧` ⇒ **808,782 fps / ≈9.82 Gbps**（泛洪**起来了**）。
- 写回 `0x08=0x2` 后 NIC **逐字冻结**（两次读相同）⇒ 受控停流有效。

**仍未分离（不许当已答）**：泛洪"何时起"的机理 —— 候选 =（a）板侧 peer 表当时为空、（b）需要一次**新** learn、（c）ARP 可达是前提；三者本轮**没有拆刀**。
**另一条登记**：carrier=0 期间 `W20`（`mac_tx_frames`）仍以 **~817k fps**（三次 3 s 窗：+2,509,502 / +2,395,186 帧）**板内递增**、线上为 0 —— 与 LONGSEND 轮登记的"**carrier=0 时板内计数照跑 809,577.7 fps 而对端全 0**"同形态（**该半边的机理本轮亦未定位**）。
**由此产生的现态差异（登记）**：辅助探针把对端**学进了板侧 UDP peer 表** ⇒ 后续 carrier 恢复会立刻泛洪（与 p8 轮前置同）；同时 `W11` 现为 `0x1000`（≠ 开工时的 0）。

---

## 5. 收尾态（`runs/FINAL_STATE_20261012021129.txt` + 收尾复核）

| 项 | 值 |
|---|---|
| 板上现役 | `0x04 = 0x00000023`（**未换烧**） |
| 受控停流 | `SCRATCH_0x08 = 0x00000002`；`CARRIER = 0`；`Link detected: no`；NIC `port_rx_bytes` 两次读**逐字相同** |
| 采集口 | `MIR_CTRL(0x144) = 0x00000000`（写 `0x0` 后读回 `0x2` 只剩 bit1 电平 ⇒ 再翻一次 toggle 落到 **恰 0x0**）；`MIR_STATUS = 0x00200000`（`cap=0 / any_drop=0 / level=0 / ver=4`）；`MIR_DMA_CNT = 0`（最后一次 clr 已归零） |
| 残留进程 | **无**（对端 `PROC_SCAN_DONE`） |
| qdisc | 已撤临时 `fq`，回 `qdisc mq 0: root` |
| 只读核对 | `/tmp/p7b_biz` 四件 md5 **与开工基线逐字相同**；`/tmp/p9_board_0x23`、`/tmp/p8_tcp_0x21` 关键件 md5 未变 |
| dmesg | 本轮新增行 = 仅两组 `sfc … link down/up`（§4 的 carrier 恢复/停流）；**无新 `xdma` 报错** |

**对端改动台账（逐条可回退）**：
1. 新增 `/tmp/p9_final/`（工具**只读**拷贝：`p7b_snap.sh 6325658a…` · `p7b_mir_dump 5ea97067…`（= p9 件）· `p7b_tcp_src 79be2a09…`（= p8 件）· `p7b_udp_src e0d4da58…` · 两个头文件 + 本轮 4 个远端脚本 + `h2c_*.bin` + `mir_*/src_*/ss_*` 日志与抓样）；**回退 = `rm -rf /tmp/p9_final`**。
2. 板上 `0x08`：`0x2` →（T2 恢复 carrier）`0x0` → **已写回 `0x2`**；辅助探针期间又开了两次 carrier（各 ~13 s / ~20 s），**结束已写回 `0x2`**。
3. 板上 `MIR_CTRL(0x144)`：被 T2 工具 arm/收尾若干次 → **已写回 `0x0`（读回恰 0）**。
4. 临时 `fq` 根 qdisc（pacing 前置）→ **已撤**（回 `mq`）。
5. **未动**：`sysctl` / `nmcli`（`10 unmanaged` 保持）/ 中断合并（`Adaptive RX: off` / `rx-usecs: 0`，本来就关）/ `/32` 地址（`192.168.100.100/32` 在位）。
6. 板侧**易失**寄存器副作用（登记）：UDP peer 表被辅助探针**填入**（对端 MAC `00:0a:35:01:fe:c0`）；`W11 = 0x1000`；`W20` 涨到 `0x02b98ddc` 档（受控停流下内部产帧的计数残值）。

---

## 6. 未定项 / 未观测到（不许当已答）

1. **H2C 的"内容被正确处理"无处可验** —— 设计上丢弃、板侧无 H2C 计数点 ⇒ 本档结论上限 = "吞噬器没卡死 + 别通道没被扰"。
2. **T1 期间"C2H 不受影响"只有快照面**（`MIR_*`/`W*` 不动）**+ T2 的整条 C2H 流间接证**；**没有** T1 期内的直接 C2H 读数（`--stream` 读需要 `cap_en/dma_en`，会与"`MIR_CTRL` 应不动"的判据冲突 ⇒ 本轮按判据字面执行，未做）。
3. **T1 只覆盖 3 档、各 2 跑** —— 未做大档（>1 MiB）、未做背靠背连续写、未做"写期间同时读 C2H"的并发臂。
4. **T2 的 `ΔW70 = 0` 只覆盖 2.5 MB/s 定速**（与 p8 轮同量级）；**线速档未测** —— 环/成形器会不会被持续回绕覆盖**未观测**；⚠️ 且板侧**没有**"丢字节"以外的丢计数。
5. **`rcv_ooopack:22`**（对端栈侧乱序计数，T2A 采样）**未追**。
6. **泛洪起/停的机理未分离**（§4）；**`W20` 内跑与线上发射的分离机制未定位**。
7. **`MIR_CTRL[1]` 是 toggle** ⇒ 逐跑读回电平奇偶交替（实测 `0xF → 0xD → 0xF`；机制 = 跨域 2FF + **XOR 沿检测**（`rtl/app_rx_mirror.v:178` `clr_pulse = clrt_sr[2] ^ clrt_sr[1]`）⇒ **每次 toggle 恰 1 个脉冲、两个方向都发**，故每跑确实恰 1 个 clr）。登记理由：**"读回 = 0"与"clr 电平"是两件事**，下游若拿"`MIR_CTRL == 0`"当"复位态"判据需知此。收尾已把电平落到 0。
8. **未做**：`0x23` 上的 MM 臂（`--dma`）复跑对照、UDP 源臂在 `--stream` 下的同批复跑（上轮已做，本轮不重做）、拆刀臂（只换读出口 / 只换位流）。

---

## 7. 文件清单（本目录）

| 文件 | 内容 |
|---|---|
| `REPORT.md` | 本件 |
| `PROGRESS.txt` | 时间线台账（含未定项） |
| `SHA256SUMS.txt` | 全目录指纹（生成后追加） |
| `runs/STEP0_20261012_020452.txt` | step0 只读自检（身份五判据 / 现态 / dmesg 基线 / md5 基线） |
| `runs/T1_H2C_20261012_020617.txt` | T1 部署**失败**那一趟（`--put` 路径错；3 档 RC=127，**未执行任何写**，不作测量） |
| `runs/T1_H2C_20261012_020630.txt` · `…_020701.txt` | T1 两趟 × 3 档原始 stdout（§2.2 表） |
| `runs/T2_TCPSTREAM_20261012_020900.txt` | T2 三跑原始 stdout（mir_dump 逐字日志 + ss 采样 + 发端见证 + 前后快照） |
| `runs/mir_T2{A,B,C}.bin` · `mir_T2*.log` · `src_T2*.log` · `ss_T2*.log` | 抓取样 + 板上工具日志 + 发端日志 + `ss` 采样（从对端取回） |
| `runs/ANALYZE_T2.txt` | 离线独立复算（`_tools/t2_analyze.py`；自检向量先过） |
| `runs/FINAL_STATE_*.txt` | 收尾态（停流 + `MIR_CTRL=0` + 撤 fq + 台账 + dmesg） |
| `runs/AUX_UDP_PROBE_*.txt` · `AUX_UDP_PROBE2_*.txt` | 两个辅助探针（泛洪缺席排查；含 ARP/邻居与 NIC 窗口读数） |
| `_tools/step0.sh` · `run_h2c.sh` · `t1_remote_step.sh` · `run_tcp_stream.sh` · `t2_remote_step.sh` · `final_state.sh` · `aux_udp_probe*.sh` | 本轮脚本（对端脚本与它们逐字一致） |
| `_tools/byteorder_analyze.py`（`903fbf15…` 逐字复制自 p9 轮） · `_tools/t2_analyze.py` | 离线复算（图案流 LFSR 独立实现 + 自检） |
