# port0 (.2 / app_multi8) 数据停顿调查（2026-11-06，进行中）

> 状态：**根因未定位**；现场证据已抓（V2 轮），诊断构建 **0x3D** 在跑（W98/W99）。
> 本文只记录【已证】读数与【推断】假设，假设均标注可证伪点。

## 1. 现象（【已证·板级】）

- `.2` 口一轮 8×256MB：TCP 三次握手全部成功（`conn_ms` 0.09–0.17 ms），但部分/全部连接
  **收不到任何数据**（`bytes=0` 或部分后停）；对端窗口恒 65535、无 RST、无重传帧。
- 抓包（`/tmp/wedge.pcap`，板 0x3C 楔死态单连接）：SYN / SYN-ACK / ACK 后 **板侧 9 s 零数据帧**，
  第 9 s 对端发 FIN（sink 超时），板回 FIN-ACK ⇒ 慢路径/HLS 活着，**只有快路径数据不出**。
- 同刻 `.4` 口（port1，独立实例）**8.8 Gbps / mism=0** ⇒ 不是 MAC/GT/线/对端。
- 一次严重楔死态（02:51–02:56）持续 ≥5 min，单连接 0 字节；重烧清除。

## 2. 停顿轮的现场采样（【已证·板级】，V2 轮，0x3C）

```
S 03:17:47 W51=0x00 W52=0x003e0000 W55=0x0e W66=0x03237b93 W67=0x02efdb7e W68=0x00037bd6
S 03:17:48 W51=0x00 W52=0x00410001 W55=0x0f W66=0x036b0948 W67=0x03327420 W68=0x00042540
S 03:17:48 W51=0x01 W52=0x00440001 W55=0x11 W66=0x04786b9f W67=0x042f7267 W68=0x00046f4d
S 03:17:49 W51=0x05 W52=0x00450002 ... 此后 W55/W66/W67/W68 全部冻结
S 03:17:50..58 W51=0x3d W52=0x00480005（estab=5）—— 冻结 ~10 s 直到连接关闭
```

- **W66/W67（帧器窗口门）冻结** ⇒ 不是"在窗口门等"（winstall 只数**帧首启动点**的等窗拍）。
- **W68（tcp_rx 推进 ACK）冻结**、**W55（retx）冻结** ⇒ 快路径无在飞数据、无 ACK 处理、无重传。
- **W51=0x3d**（5 槽"可接收新帧"）、**W52 estab=5** ⇒ app_ctrl 侧仍有 5 条 ESTAB；
  但 8 条连接里 2 条完成、6 条停顿 ⇒ **app 的信用位与快路径实际放行不一致**。

## 3. 关键结构（源码，【已证·源码】）

- `tcp_tx_frame.tready`（`rtl/tcp_tx_frame.v:731`）：
  - 帧首拍（`recv_first=1`）要求完整启动门：`wnd_open && !tx_blk_sid && !ack_pend_r &&
    !svc && !ring_eval && !scan_now && !rx_flush && !fifo_full && !bank_rdy[rx_bank]`；
  - **帧内拍（`recv_first=0`）只要求 `!fifo_full && !bank_rdy[rx_bank]`** ⇒ 一旦开帧，
    后续拍不再看连接状态。
- ⇒ 若某槽 `wnd_open`/`tx_blk` 与 app_ctrl 的 `app_tx_ready` 不一致，该槽的帧会**开了头**，
  但若 TX 引擎不排空该 bank（`bank_rdy`）或 FIFO 满，`tready` 掉 ⇒ **整条 app TX 合并总线
  被这一帧占住（AXIS 不可撤）⇒ 所有槽饿死**。
- `tx_arb`（`rtl/tx_arb.v`）：一旦选中某流即锁定到 TLAST；慢流若中途断 valid 会永久锁死
  （但 `slow_tx_adp` 是**整帧缓冲后才可见**，`rtl/slow_tx_adp.v:10`，慢流结构性不断供）。
- `slow_cfg_adp`：ADD 逐字段写 TCB，每字段等 `cfg_gnt`（tx>rx>cfg）；`ev_up` 在
  **最后一字段（wscale）落地拍**发出 ⇒ app_ctrl 认为 ESTAB 时，TCB 字段**理论上**已配全。

## 4. 触发规律（【已证·统计】）

| 会话/臂 | 换烧后第 1–2 轮 | 第 ≥3 轮 |
|---|---|---|
| 0x3C 02:22 烧 → d(1) 8/8，26 min 后 d2(2) **0/8** | **停顿** | （未测 3） |
| 0x3C 02:56 烧 → c1 **6/8**，c2 **6/8** | **停顿** | — |
| 0x3C 03:04 烧 → t1 **7/8**、t2 **7/8**、t3–t6 8/8 | **停顿** | 全 8/8 |
| 0x3C 03:16 烧 → V1 8/8、V2 **2/8**，随后 x/y/z 300 轮 | **停顿** | 全 8/8 |
| 0x3B 02:53 烧 → b1/b2 8/8；03:02 烧 → s1–s6 8/8 | 干净 | 干净 |

- 300 轮（2400 连接）里只有 1 次停顿（V2），**且落在换烧后第 2 轮**。
- ⚠️ 反例：02:51 楔死后（同一 02:22 烧）第 3 次活动（单连接）仍 0 字节 ⇒ "2 轮后必好"**不成立**；
  实际规律 = **停顿风险集中在换烧后的头几次活动，且可能一次楔死后持续**。

## 5. 假设（未证，按可证伪点排序）

1. **H1 快路径 TCB 与 app_ctrl 视图不一致**（`snd_wnd=0` / `tx_blk` / `state≠ESTAB`），
   app 照常呈交帧 ⇒ 帧首被接（若不一致发生在首拍判据**之前**不会开帧；更可能发生在
   `wnd_open=1` 开帧后、TX 引擎不排空 ⇒ FIFO 满 ⇒ 帧内停）。
   证伪/证实 = W98/W99 的 `wnd_open`/`tx_blk_sid`/`rb_state`/`rx_state`/`fifo_full`。
2. **H2 RX_FLUSH 死锁**：`len_over/len_bad` 进入 RX_FLUSH 后等 `fifo_empty_rx`，而该 bank
   无 `bank_rdy` ⇒ TX 引擎不排空 ⇒ 永久等。证伪 = W98 的 `rx_state==RX_FLUSH` 且 `fifo_full`。
3. **H3 TX 引擎卡在 T_DONE**（等 `m_axis_tready`），下游 arbiter/MAC 不收。
   证伪 = W99 的 `tx_state` + `m_axis_tvalid/tready`；若 `tvalid=1/tready=0` ⇒ 指向下游。
4. **H4 换烧 warm-up**（HLS/BRAM/对端瞬态）：只解释"高发窗口"，不解释单次楔死持续。

## 6. 追加实验（2026-11-06 06:3x–07:0x）

### 6.1 换烧周期统计（0x3C，每周期 2 轮 8×256MB）【已证·板级】

| 周期 | R1 | R2 |
|---|---|---|
| C1 | **7/8** | **7/8** |
| C2 | 8/8 | 8/8 |
| C3 | 8/8 | 8/8 |
| C4 | 8/8 | **7/8** |
| C5 | 8/8 | **7/8** |

- 4/10 轮有停顿，**全部**落在换烧后的第 1–2 轮（与 §4 一致）。停顿既有"0 字节"也有
  "传了大半后停"（如 R2 的 P4/P5/P6 = 223–264 MB 后停）。

### 6.2 poke 实验（`--poke-ms`，给停滞连接制造一个 ACK）【未判定】

- 工具 = `_proj_pcie/p7b_biz/p7b_tcp_sink.cpp` 新增 `--poke-ms N`（默认 0）：连接后 N ms
  仍 **0 字节**则发 1 字节，打印 `SINK_POKE ...`。
- 结果（0x3C，换烧后）：一次 **0 字节停顿**在 3.003 s 发出 poke（`rc=1`），到 9 s 仍是 **0 字节**
  ⇒ **poke 未救回**。原始件 = `raw/poke_rounds_0x3C.txt`。
- 但**该 poke 的 ACK 是否被 tcp_rx 看到未取证**（无同窗 pcap）；且板侧连 poke 字节的
  **echo 都没有** ⇒ 更像 rx 路径根本不认这条连接（CAM/TCB 不一致），而不是 `acks_ok` 单点。
  `ack_obs` 的置位源含 `ackok_l`（零推进 ACK 也算，`rtl/tcp_rx.v:612-626`）⇒ 若 poke 真被
  rx 看到，`acks_ok` 假说即被证伪。**当前口径 = 未判定**。

### 6.3 诊断构建 0x3D 两次 TIMING_FAIL【已证·构建】

| 方案 | 几何 | 结果 |
|---|---|---|
| a：新增 p7bdp 槽 54/55（W98/W99） | NW 100 / UNIMPL 0x1C0 | **WNS −0.390 / setup 7537**；最差族 = 既存 `u_tcp_tx/rx_state_reg[1] → u_app_ctrl/orph_cnt_reg[9][3]/CE`（22 级 / route 4.49 ns） |
| b：零几何复用 W71/W72（`P11_DIAG_TX=1`） | NW 98 / UNIMPL 0x1B8 **不变** | **WNS −0.046 / setup 477**（仅差 0.046 ns） |

- 两次位流均被时序门隔离（`.TIMING_FAIL`，禁烧）；报告 = `build_fail_0x3D_{a,b}/`。
- ⇒ 下一轮：**同输入换策略重试**（`Performance_Explore` 或 `Performance_ExtraTimingOpt`），
  或把束缩到 1 个字（只留 word A 的 22 位关键门）。

### 6.4 0x3D 诊断结果（2026-11-07 02:0x）【已证·根因锁定】

- **构建**：第三次 0x3D（零几何紧凑束，`P11_DIAG_TX=1`，只复用 W71）**PASS**：
  WNS **+0.016** / 三类端点 0/0/0；位流 **`39a7a9f5…8090`**；BID 0x3D / NW 98 / UNIMPL 0x1B8。
- **板级**：换烧后第 2/3 轮抓到停顿（C1_R2 6/8、C1_R3 5/8，均"传 100–260 MB 后停"）。
  W71 解码（两例一致）：
  ```
  rx_state=RX_IDLE  recv_first=1  s_axis_tvalid=1  s_axis_tready=0
  wnd_open=1  tx_blk_sid=1  acks_ok=1  st_ok=0
  fifo_full=0  bank_rdy0/1=0  tx_state=T_IDLE  start_id=2/0
  ```
- **判读**：app 挂着帧、但该槽 **TCB 状态已非 ESTAB**（`st_ok=0`）⇒ `tx_blk_sid=1` ⇒ 快路径
  永久拒收；同刻 app_ctrl 该槽 ready=0（W51）、estab 不含它（W52）⇒ **两侧都认为连接已不在**
  ⇒ 这是**已死连接的陈旧帧**占住共享 AXIS 总线 ⇒ 全口饿死。
  **排除**：窗口门（wnd_open=1）、r6 `acks_ok`（=1）、FIFO（full=0）、RX_FLUSH（state=IDLE）、
  TX 引擎卡死（T_IDLE）。

## 6.5 修复 0x3E（实施完成、构建中）

- `rtl/tcp_tx_frame.v`：新增输入 `app_tx_ready_i[15:0]` + `drain_r`/`drain_cnt`：
  帧挂起（`rx_state==RX_IDLE && recv_first && s_axis_tvalid`）且
  **`st_ok==0 && app_tx_ready_i[s_axis_tid]==0`** 持续 **16384 拍（≈105 µs）** ⇒ 置 `drain_r`，
  把该帧所有拍**接收并丢弃**（`tready=1`；`wr_act`/`wr_tap`/收帧体/E1a `first_present` 均以
  `!drain_r` 门控），到 `tlast` 复位。
- **代价** = 该连接丢一帧（其 TCB 已死、本来发不出去）；**收益** = 端口不再楔死。
- 判据要求"两侧都认为不在"⇒ 不会误伤活连接的窗口关闭（窗口=0 时 `st_ok` 仍=1，不触发）。
- wrapper 两实例接 `app_tx_ready`/`a2_tx_ready`；BID **0x3E**；诊断宏关闭（W71/W72 恢复原义）。
- **未覆盖**：帧内形态（`recv_first=0`，由 FIFO/bank 门决定）。
- **上一层未定位**：**TCB 状态为何被清**（哪条 DEL/state=0 落到活连接槽）—— 排水把"整口楔死"
  降级为"单连接丢一帧"，根因仍需下一轮查（HLS FIN/槽复用/静默释放路径）。

## 7. 下一步

1. 0x3D 用不同实现策略重建（预计 WNS 余量足够 → 上板）。
2. 上板后按 §6.1 的换烧周期跑（每周期前 2 轮），命中即读 **W71/W72**（word A/B 位序 =
   `rtl/tcp_tx_frame.v` 的 `o_dbg_tx` assign 注释；解码器 `decode_w98_w99.py`）。
3. 判读：`rx_state==RX_FLUSH` ⇒ 冲洗死锁；`m_axis_tvalid=1 & tready=0` ⇒ 下游；
   `s_axis_tvalid=0` ⇒ app 合并总线头阻塞；`wnd_open=0`/`tx_blk_sid=1` ⇒ 门控（含 `acks_ok`）。
