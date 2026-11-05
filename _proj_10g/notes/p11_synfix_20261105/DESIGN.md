# P11 SYN/连接槽泄漏修复设计（v1，2026-11-05）

- 状态：**设计件 v1（未实施）**；待独立红队审查后进入实施。
- 上游证据：
  - 板级：`_proj_10g/notes/p11_txstarve_20261103/REPORT_0x3B_diag.md` §8–§12（含 raw-SYN 表满复现）。
  - csim：`hls/tb/udp_echo_tb.cpp` 新增用例（ARM_A/B/B2/C、HALFOPEN、CHURN），实跑 `P11_TB_RESULT PASS`。
  - 源码：`hls/src/layer_tcp.cpp` / `hls/src/udp_echo.cpp` 现读行号见下。
- 板上 HLS 与当前源码逐位对应（构建日志 `HLS_SRC_HASH=b7dd1542…1728` / `HLS_NET_HASH=125a71f8…f8c3`，独立重算命中）；
  构建 cflags = `BOARD_IP_DUAL=1 / MAX_TCP_CONN=8 / ACTIVE_CONNECT=0`（`hls/run_hls.tcl:14`）。

## 0. 一句话

被动（ACTIVE_CONNECT=0）HLS 的 8 槽连接表**没有任何老化/超时释放**，且零数据连接的 FIN 被握手 ACK 分支抢占；
任何一次半开/零数据连接都会永久占槽，累积 8 次后新 SYN 在 `tcp_find=-1` 处静默丢弃 ⇒ 只有重烧能恢复。
修法 = **被动模式启用半开/T_LAST_ACK 老化（释放时补 CFG_DEL）+ 修正 FIN 优先级**；默认宏关、构建启用、csim 双臂验证。

## 1. 根因（三条，均已证）

- **R1【主因·结构性】被动构建无空闲 tick ⇒ 超时释放全是死代码。**
  `layer_tcp.cpp:540` 的释放扫描只在 `!ip_rx.valid || protocol!=6` 时进入；`tcp_rx_process` 的两个常规调用点
  （`udp_echo.cpp:188` / `:258`）都带 `valid=1, protocol=6`；唯一的空闲拍调用在 `#if ACTIVE_CONNECT` 内
  （`udp_echo.cpp:263-277`），板级 cflags 未定义 ⇒ 编译掉。网表层面正常调用硬接 `valid=1/protocol=2'd2`
  （归档网表 `udp_echo_tcp_rx_process.v:7094,7518`）。
  ⇒ `T_SYN_RCVD` 的释放（`layer_tcp.cpp:566-570`）与 `T_LAST_ACK` 的限次重传/释放（`:582-589`）**永不发生**。
  csim 实证：8 个半开槽 + 300k 空闲 pass 后新 SYN 仍 `SYNACK=0 ADD=0 DROP+1`。
- **R2【主因·确定性 bug】零数据 FIN 被握手 ACK 分支抢占。**
  `T_SYN_RCVD` 首分支 `layer_tcp.cpp:719`：`(flags&TCP_ACK)&&ack==c.seq` ⇒ `T_ESTABLISHED`。
  零数据连接对端 FIN 的 `ack = ISS+1 = c.seq` ⇒ FIN 被当作握手 ACK；后续 `else if(FIN)`（`:735-747`）
  不可达 ⇒ 不发 FIN|ACK、不 CFG_DEL、不释放；对端重传 FIN 才进入 `T_LAST_ACK`（`:757-761`，此处发 DEL），
  而最终纯 ACK 被 `rx_classify` 送 fast path（`rtl/rx_classify.v:102-107`）⇒ HLS 停在 `T_LAST_ACK` 且无老化
  ⇒ **永久泄漏**。现有 csim 的 `build_fin` 写 `ack=0`，恰好绕开真实路径（测试盲区）。
- **R3【次因·偶发】`tcp_proc_pending` 单槽覆盖。**
  `udp_echo.cpp:157-162` 任何新 RX 帧完成即 `tcp_proc_pending=false`；`:182-186` 在 MAC 忙时挂起 TCP 帧。
  csim 实证（ARM_B2）：TX busy 954 拍时两个 SYN 只处理第二个（1 SYN-ACK / 1 ADD）；ARP busy 72 拍不足以触发（ARM_B）。
  ⇒ 只在长 TX busy 窗口内偶发丢 SYN，不累积。

板级签名对账：8 个原始 SYN（伪造源 MAC + nsa 内抑制 RST）⇒ W7 +9（1 基线 + 8 SYN-ACK）、
**第 9 条正常 connect TimeoutError**、原始 RST 释放一槽后 **CONNECT OK**、W52=`0x000a0008`（ev=10/estab=8）
（`raw/raw_syn_fill_rst_suppressed.txt`）⇒ 表容量 8、半开占槽不老化、表满静默丢、RST 可释放。

## 2. 目标 / 非目标

- 目标：
  1. 半开（`T_SYN_RCVD`）与 `T_LAST_ACK` 槽在被动构建中**按超时释放**，并**同时通知 fast/app 侧**（CFG_DEL）；
  2. 零数据 FIN 走 FIN 分支（DEL + FIN|ACK + 立即释放）；
  3. 不改变合法 8 连接建连/数据面行为；不改变 ACTIVE_CONNECT=1 语义；
  4. 老构建可一键回退（宏默认 0）。
- 非目标（本轮不做，登记）：
  - R3 的 pending 单槽改造（需 II=1 重新排流水，单独评估）；
  - 表满时对未知端口回 RST；
  - 按口配额（H6，8 槽两口共享）；
  - `SYN|RST` 组合的 T_LISTEN 残留（低概率）。

## 3. 修法（v1 提案）

### F1 被动老化（`P11_SLOT_AGING`，默认 0；`run_hls.tcl` 传 1）

- `layer_tcp.cpp`：
  - 新增宏 `#ifndef P11_SLOT_AGING #define P11_SLOT_AGING 0 #endif`。
  - 释放扫描内，当 `P11_SLOT_AGING` 时对 `T_SYN_RCVD` 超时：**先 `cfg_write(cfg_stream, CFG_CMD_DEL, cid, ...)`
    再 `state=T_FREE`**（现有 `:566-570` 缺 DEL —— 半开连接已在 T_LISTEN 发过 ADD，不 DEL 会泄漏 fast/app 侧）。
  - `T_LAST_ACK` 超时释放：进入 T_LAST_ACK 时已发 DEL（`:757-761`），释放时不需要重复 DEL；
    保留现有 `retry_cnt>TCP_MAX_RETRY` 逻辑，确保可达。
  - 为避免被动模式误触数据重传：`P11_SLOT_AGING && !ACTIVE_CONNECT` 时，扫描**只处理**
    `T_SYN_RCVD`/`T_LAST_ACK`，跳过 `T_ESTABLISHED` 的 `tcp_retrans_due` 分支
    （被动模式下数据面归 fast path；现有注释已说明该分支为主动/echo 用）。
- `udp_echo.cpp`：
  - 空闲拍调用从 `#if ACTIVE_CONNECT` 改为 `#if ACTIVE_CONNECT || P11_SLOT_AGING`；
    调用条件沿用 `!do_process && !tcp_proc_pending && !mac_tx_busy && !tx_req.request`。
- 超时值：沿用 `c.rto`（`tcp_send` 对 SYN 置 `retrans_pending=true`、`rto_timer=0`；`TCP_RTO_MIN=10,000,000` 拍 ≈80 ms）。
  ⇒ 半开槽 ~80 ms 释放。**审查点：80 ms 是否过短（对端 SYN 重传 1 s 后才到；释放后再建新槽，语义正确；
  但会放大 SYN 洪泛下的建连抖动）——备选 = 专用老化计数 1–3 s。**

### F2 FIN 优先级（`P11_FIN_FIX`，默认 0；构建传 1）

- `layer_tcp.cpp:719`：`if((flags&TCP_ACK)&&ack==c.seq && !(flags&TCP_FIN))` ⇒ 零数据 FIN 落到 `:735` FIN 分支
  （DEL + FIN|ACK + 立即 FREE）。纯 ACK 行为不变；T_ESTABLISHED 的 FIN 路径不变。
- csim 需新增“零数据 FIN（ack=ISS+1）”用例：修复前 = 无 DEL、状态进 `T_LAST_ACK`；修复后 = 1 DEL、FREE。

### 观测（本轮不改几何）

- 判据用现有字：W6（慢帧提交）、W7（HLS 出帧）、W16（HLS 读字节）、W18（purge）、W19（慢 RX 丢）、
  W52（cfg 事件数/estab）。
- 板的判据用行为：raw-SYN 填 8 → **不注入 RST、空闲 > 1 s** → 新 connect 成功（修复臂）；0x3B 负臂等待后仍失败。
- `tcp_stat_no_slot` 仍不可板读；如后续需要，另立“观测几何”构建并同步刷新 Tier A（人读层）。

## 4. 验证计划

1. **csim（实施门）**：同一 TB 双编译臂：
   - LEGACY 臂 `-DP11_SLOT_AGING=0 -DP11_FIN_FIX=0`：现 3 条基线 XFAIL + `HALFOPEN_FULL` 仍 0/0（负对照）；
   - FIX 臂 `=1/=1`：HALFOPEN 填满 + 空闲 > 老化阈值 ⇒ 新 SYN `SYNACK=1 ADD=1`；
     零数据 FIN ⇒ `DEL=1`、槽 FREE；CHURN 与 ARM_A 不回归；
   - 检查 `HALFOPEN_FULL` 的期望随宏切换（TB 内 `#if`），并保留 `P11_TB_RESULT`。
2. **csynth 铁律**：`udp_echo` 顶层 `ap_ctrl_none` 必须 **Latency 0 / Interval 1**（csynth 报告逐字核）；
   HLS 资源增量登记。
3. **构建 0x3C**：`board/run_build_p7b_ku5p.bat`（HLS 重综合 + 全流程）；
   时序门沿用 `Congestion_SpreadLogic_high`（0x3B WNS +0.027/0 端点）；BID 0x3C；失败位流禁烧。
4. **板级 A/B**：
   - 负臂 0x3B：raw-SYN 填 8 → 空闲 2 s → 新 connect **仍失败**（已证）；
   - 正臂 0x3C：同构型 → 空闲 2 s → 新 connect **成功**（核心判据）；
   - 回归：8×16 MB 8/8、8×256 MB 8/8、连续 20 轮 connect/close 后仍可建连、单连速率回归、W97 健康字。
5. **文档**：报告、台账、OPEN_ITEMS §0-88；若改几何则提醒用户同步 Tier A。

## 5. 风险与回退

- 风险 1：空闲扫描启用后误触 `tcp_maintenance` 的数据重传 ⇒ 与 fast path 重复发帧。缓解：被动分支只处理
  `T_SYN_RCVD`/`T_LAST_ACK`，`TESTABLISHED` 的 due 逻辑保持编译外/条件关闭；csim + 板级内容判据验证。
- 风险 2：80 ms 老化过短 ⇒ 合法慢握手被误杀。缓解：阈值参数化（宏），板级用 8 连接受控测试；
  备选 1–3 s。
- 风险 3：超时 DEL 与 fast 侧状态竞争（DEL 到达时 fast 已自清）⇒ app_ctrl 对无匹配 DEL 的处理需核；
  `app_ctrl` 的 ev_down 对未知槽应幂等（审查点）。
- 风险 4：HLS 顶层 II/时序变化 ⇒ 构建门拦截；失败则回退宏=0。
- 回退：`P11_SLOT_AGING=0 / P11_FIN_FIX=0` 重建 = 现网表行为（csim LEGACY 臂证明逐位等价）。

## 6. 待审查裁定

1. 老化阈值：80 ms（沿用 RTO_MIN）vs 专用 1–3 s？
2. `T_LAST_ACK` 是否也纳入被动老化（进入时已 DEL，释放只需 FREE）？
3. 是否本轮就把 `tcp_stat_no_slot` 接出（改观测几何、触发 Tier A）？
4. pending 单槽（R3）是否本轮不做（推荐不做）？
5. 被动分支跳过 `T_ESTABLISHED` 数据重传的写法（宏组合）是否引入了不可达/未覆盖分支？

> ⛔ **2026-11-06 订正：本件 v1 已被 `DESIGN_v2.md` 取代**（F1 老化撤回；本轮只做 F2）。理由见 `REVIEW_FINDINGS.md`。
