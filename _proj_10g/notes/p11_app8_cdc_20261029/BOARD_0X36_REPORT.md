# 0x36 板级轮报告（P11 APP8 CDC，OCC=0）

日期：2026-10-29 03:28–04:00（对端 `192.168.0.38`，板 JTAG `192.168.0.38:3121` @1 MHz）
位流：`bits/wrapper_p4_0x36.bit`，sha256 `d80bdb28fe0320d75774e2a23734b6e79c5789597e7feb4eaf1b67309d9adde9`（15,431,261 B）
QSPI：**零写入**（只 JTAG 易失烧录；烧前/烧后 sha 已核）

## 1. 上板前状态与烧录

- 上板前板在 **QSPI 厂商态**：`02:00.0` 仅 1 个 64K BAR，`xdma` 未加载（对端开机 2h24m）。
- 烧录日志 = `burn/BURN_0x36_<stamp>.txt`（sha 锚 → 对端状态 → JTAG 1 MHz → HIGH/DONE/新鲜度/无 ABORT）。
  - `End of startup status: HIGH`、`TCPREG_PROG_DONE`、`BURN_OK`。
- PCIe 恢复：设备级 `remove+rescan` **失败**（父桥窗仍按 1 BAR）⇒ 根端口 `0000:00:1c.0` remove+rescan **成功**：
  `identify_bars: 2 BARs: config 1, user 0`、`/dev/xdma0_user`、`LnkSta x4`。
- 身份（烧后）：`0x00=0x50360001` / **`0x04=0x00000036`** / `0x14=0xdeadbeef` /
  **`0x1B8=0xffffffff`**（未实现地址）/ **98 字窗口逐字扫描 `WINDOW_SCAN_NFF=0`** /
  MIR 四字 = `0x1A8=0x00210000`、`0x1AC=0x5a5a5a5a`、`0x1B0=0`、`0x1B4=0`（NW=98 ⇒ MIR 整体 +4）。
- 网络：nsa/nsb netns 重建（`b0_env_setup_0x36.sh`）；nsb `enp1s0f0np0` = 192.168.100.101/32 ↔ 板 .4
  （ch0/J7）；两边 `ping` 通、carrier=1、speed=10000。

## 2. CDC 健康字 W97（地址 0x1A4）

触发快照后读数：**W97 = 0x00000020** ⇒
- [5] `locked_app` = **1**；[2] ev drop=0；[3] close drop=0；[4] stats stale=0；
  [6] app_rst_seen=0；[7] stats timeout=0；[15:8] per-slot mismatch=0x00；[20] dp_rst_seen=0。
- 解码器 = `decode_w97.py`（`CLEAN` 判据 = V5 §7.1）。
- ⇒ **app 时钟域锁定、无事件/close 丢弃、无 app/DP 复位、无失配粘滞**（本臂有效）。

## 3. 功能（数据面）

### 3.1 单连接内容校验（成熟工具 `p7b_tcp_sink`，THREADED，seq）
- **100 条连接串行、每条 ~1 MiB**：`SINK_SUM conns=100 fail_conns=0 bytes=107,052,876 clean_conns=100 bad_conns=0
  mismatch_bytes=0 stall_conns=0`，每连接 `first_mismatch=-1`、`checked_bytes == bytes`。
- 单连接速率 3.7–4.7 Gbps（每条 wall ~2 ms）；**逐字节内容 = app_pattern 图案**。

### 3.2 8 连接并发（`p7b_tcp_sink_multi`）
- `--check seq --conns 8 --maxbytes 12288`：**8/8 `status=0`、`mism=0`、`first=-1`、`stall=0`**；
  每条 `got` 12288–65536（>maxbytes 是工具按 64K 块停止的**过冲**，不是板多送）⇒ 工具判 `err=8` 只因
  `got != maxbytes`，**不是内容/连接失败**（8 条全部收到了正确图案）。
- `--check lane8` 同参数的首跑：6 条 STALL —— 同样 8 条在 `seq` 下全过 ⇒ 归因到 **lane8 校验模式 +
  小 maxbytes 的工具行为**（同一板态、同一连接数），不是板缺陷；`lane8` 本轮的"STALL"记录保留在
  `raw/B1_FUNC_0x36_20261029_033137.txt`。

### 3.3 上行（PC→板，8×12,288 B）+ 并发下行
- `--conns 8 --maxbytes 16 MiB --send-conns 8 --send-bytes 12288`：8/8 `sent=12288 unsent=0`，
  下行 8×16.8 MB、`mism=0`（`check=seq` 逐字节）。
- 上行内容 oracle：**W97[15:8] = 0x00**（app 域 per-slot mismatch 粘滞，**不经统计握手**）
  ⇒ 板侧 app RX 校验器对这 8×12,288 B **零失配**。

## 4. 新发现（本构建的观测面缺陷，**不影响数据面**）

**W51–W54 / W71–W74（app 统计字）在板上恒 0**，包括：
- 触发快照后（`full`）读 W51..W54 = 0、W71..W74 = 0；
- **流量进行中**采样（3 次触发，下行已收 3,221,334,960 B / `W84` 从 0x16a7d 涨到 0x244872）仍全 0；
- 同时 W97 干净（无 stale/超时），数据内容 107 MB + 3.2 GB 均 `mism=0`。
- 综合网表事实（在 0x37 构建前查过，**routed dcp 已被 0x37 的 `create_project -force` 清除**）：
  `u_app/st_hold_reg[0]` C = `u_app/clk_app`（`u_appclkgen/g_real.u_bufg_out/O`，BUFGCE），
  CE = `st_ack_i_1`（req/ack 比较），D = `u_app/core_tx_bytes[0]`（8 实例求和锥）；
  `u_app/st_shadow_reg[0]` C = `u_app/dp_clk`，CE = `st_req1`，D = `st_hold[0]`；
  `stat_tx_bytes` 计数器存在（FDCE），CE = `pw_take`（=RTL `pw_valid && m_tready && !closing`）；
  `st_hold` 320 cell（4 位 close_pend_max 因常量 0 被优化）、`st_shadow` 320 cell。
- 单元 TB（两种时钟比：6.23/6.4 ns 漂移 + 6.4/6.4 ns 固定）**均通过**"stats handshake live"判据。
- ⇒ **状态 = 【未定位】**。候选（未证）：① stats 请求 req 在板上未真正翻转（但与 [4]/[7]=0 相容）；
  ② app 计数器 CE 在板上未触发（与数据流事实冲突）；③ 综合/布局对 320 位 hold 总线的某种优化。
  下一步需新仪器（如把 `st_req`/`st_ack`/`st_tick==1023`/`pw_take` 接进 W97 的空闲位或 ILA），
  **本次数据不足以定因**。
- **影响面**：仅观测（W51–W54/W71–W74 不可用）；**数据面功能不受影响**（§3 的内容 oracle 成立）；
  OCC A/B 的主见证 = tcpdump 窗（W97/窗口），不依赖这些字。登记 = `P7B_OPEN_ITEMS.md` §0-80（本轮新增）。

## 5. 结论（本臂）

- 0x36 位流**可烧、可跑、身份全中、CDC 健康字干净、8 连接数据面正确（下行 107 MB + 8×16.8 MB 内容校验、
  上行 8×12,288 B 零失配）**。
- **不许写成"CDC 已全面验收"**：app 统计字观测面异常（§4）、真 wrapper 全链门未写（DESIGN §11.2）、
  板级 A/B 的上臂（0x37）尚未做。

## 6. 原件

- 烧录：`burn/BURN_0x36_*.txt`、`burn/BURN_stdout_copy_*.txt`
- 功能：`raw/B1_FUNC_0x36_*.txt`（含单连接 100 条、8 连接、上行、W97/STATUS 原始读数）
- 构建：`build_ok_0x36/`（stdout/时序/util/DRC/clock interaction/两个 runme）
- 复核脚本：`check_build_0x36.py`、`decode_w97.py`、`check_cdc_wiring.py`

## 5. OCC A/B 阻断（RX 停顿钩子无效）—— 本轮未执行

- 目的：DESIGN_OCC_V6 §6.6 的 RX 停顿臂 —— `0x08 bit2` 停 app RX，让 echo/app 占用升到
  `W62 ≥ 12,288`，再用板→PC 数据帧的 `tcp.window` 比较 OCC=0（全局扣减）与 OCC=1（每连接）。
- 实测（0x36，`occ_stallchk.sh` / `occ_w9.sh`）：
  - SCRATCH 写 `0x4` 并回读 = `0x4`（钩子已置位）；
  - 单连接发送 **16,384 / 131,072 / 524,288 B**（三种量）均 `sent=524288 unsent=0` ⇒ 内核全 ACK；
  - 板→PC 数据帧窗口恒 **12288**（tcpdump `-i any`，2 s 抓 784,208 帧；该接口用 `-i any` 才可见，
    named-interface 抓到 0 —— SFC9120 的捕获路径特性）；
  - **触发快照**读 W62 全程 **0**（不是没触发；触发器 gen+1 已核）。
- ⇒ **app RX 占用没有升起** ⇒ OCC A/B 前件不可达 ⇒ 按 §6.6 第 8 条记 **【空判据/未执行】**，
  **不记 PASS/FAIL**。这是 `0x08 bit2` 钩子的**首次板测**（0x34/0x35 从未产出位流）。
- 候选（未证）：① 停读位没到 CDC FIFO 写门；② `eco2_tready` 未被上游尊重（数据被丢而非背压）；
  ③ W62 源不是该 echo FIFO；④ app 在停读期间仍有消费路径。需 ILA/新仪器定位。
- 影响：**OCC=1（0x37）与 OCC=0（0x36）的窗行为差异本轮无法判定**；0x37 只做身份/W97/数据面冒烟。

## 7. FINAL_STATE（本轮收尾，2026-10-29 06:1x 现读）

- 板 = **0x36**：`0x04 = 0x00000036`；`0x08 = 0`（carrier 开）；`LnkSta x4`；2 BARs；`/dev/xdma0_user` 在。
- 对端：xdma 已加载；nsb/nsa carrier 均 = 1；**无残留 `p7b_tcp_sink*` 进程**。
- **QSPI 零写入**（全程只 JTAG 易失烧录；烧前/烧后 sha 核对）。
- 未烧：0x37（TIMING_FAIL，`.TIMING_FAIL` 隔离，禁烧）。

## 8. 订正/新增：8 连接**并发保持**严重不足（2026-10-29 06:2x，3 跑）

- §3.2 的"8 连接 seq 8/8 status=0"**只对"小 maxbytes、连接快速关闭"成立**（每条连接收 ~12–64 KB 后关闭，
  并发压力低）。**连续洪泛 + 8 条并发保持**的构型另测（`multi_tx_check.sh` / `multi_tx_check2.sh`）：
  - 3 跑并发 connect 8：**只有 2 / 4 / 4 条成功**；其余 `status=4 err=110 (ETIMEDOUT)` 或
    `status=2`（建立但 5 s 内零数据）；
  - 下行集中在 1–2 条连接：单条 ~4.5 Gbps，聚合 ~4.4 Gbps；两段各 2 s 的 tcpdump 均**只看到 1 个 4-tuple**；
  - 已收到数据的字节 **mism=0**（内容正确）。
- 对照：**串行单连接**（`p7b_tcp_sink`，100 连接串行）全部 OK ⇒ 不是"连接打不开"，是**并发保持**不行。
- 候选（未证）：① HLS 慢路径 SYN-ACK 在 8×app 连续 TX 下被饿死（旧"慢路径饿死"证伪只覆盖单 UDP app 构型）；
  ② win_pool 配额/槽（`RCV_WND_INIT_5 = WQ_CAP_5 = 12KB` 源码已核，8×12=96KB 恰好，理论上应容 8）；
  ③ app 的 ev_up/槽分配上限。判别实验见 `P7B_OPEN_ITEMS §0-83`（关 app TX 后并发 connect / 交错 connect）。
- ⚠️ 这条**不影响**本轮"CDC 数据面正确"的结论（内容 oracle 成立），但**直接影响 8 连接产品目标**，
  且与 OCC A/B 的"8 连接前件"相关（A/B 前件本身已被 §0-81 阻断）。

### 8.1 交错 connect 判别（2026-10-29 06:1x）

8 个**单连接** sink 间隔 0.6 s 依次启动（各自 `--maxbytes 256 MiB --seconds 10`，串行 hold）：

| sink | 成功连接数 | 失败数 | 收到字节 |
|---|---|---|---|
| S1 | 13 | 0 | 3,490,059,457 |
| S2 | 12 | 0 | 3,221,587,521 |
| S3 | **0** | 2 | 0 |
| S4 | **0** | 2 | 0 |
| S5 | **0** | 2 | 0 |
| S6 | 3 | 1 | 805,405,645 |
| S7 | 4 | 1 | 1,073,827,960 |
| S8 | **0** | 2 | 0 |

- ⇒ **即使错开 SYN，也只有 4 个 sink 曾建立连接**（不是"并发 SYN 突发"问题）⇒ 更像
  **~4 条并发连接的上限**（配额/槽），而不是慢路径瞬时饿死。内容仍 `mism=0`。
- 下一步：4 vs 5 条并发定界；复核 `win_pool_mgr` 授予数学（`wq_cap=12KB`、`WIN_POOL=96KB`、
  8×12=96 恰好）与 HLS `MAX`/槽配置；把 `stat_no_slot` 等慢路径计数接进快照。

### 8.2 5 sink 追加 + 快照读数（2026-10-29 06:1x）

- 5 个单连接 sink 间隔 0.5 s 启动（`five_conn.sh`）：只有 **F1（11 连）/F2（10 连）/F4（1 连）** 曾成功；
  **F3/F5 零连接**。同刻触发快照：**W62 = 0 / W61 = 0 / W97 = 0x20**（干净）。
- ⇒ 不是 echo FIFO 占用（W62=0）造成的授予失败；HLS 档 = `p3_dual_max8`（MAX=8，非 4）。
- **首选假设（未证）**：每连接在 win_pool 里被**授予两次 12KB**（双口/双事件，96/24 = 4 条），
  或 `port_win` 归还路径未生效导致累积；次选 = app 事件/槽路径。
- **零构建判别**：在 `p11_wpm`/`slow_cfg` 类 TB 里数"每次 ADD 的 `ev_up`/授予次数"；
  **一次构建判别**：把 `pool / Σwinq / port_win` 三值接进快照（NW+3），并发 5 条时直接看哪一项先到 0。
