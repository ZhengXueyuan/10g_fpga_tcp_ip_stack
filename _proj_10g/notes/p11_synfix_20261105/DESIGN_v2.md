# P11 SYN/连接槽泄漏修复设计（v2，2026-11-05/06）—— 本轮只做 F2

- 状态：**v2（取代 v1）**；两路红队 FINDINGS = 同目录 `REVIEW_FINDINGS.md`。
- v1 的 F1（被动老化）**整体撤回**：`T_SYN_RCVD` 在 P11 被动架构里是**已建立会话**态
  （第三个 ACK 走 fast；HLS 只在 FIN/RST 时回来），任何时间老化都会杀活连接；
  且空闲拍写 `cfg_stream` 是源码明文禁区（会卡死 ap_ctrl_none 主 FSM）；`T_LAST_ACK` 老化结构性不可达。
- 本轮实施 = **F2（FIN 优先级）**，修 R2；R1（半开泄漏）保留为独立未解决项，未来按
  `REVIEW_FINDINGS` 的 B 方案（fast 侧 `ack_seen` 半开回收 + HLS `i_slot_dead` 掩码，不写 cfg）处理。

## 1. R2（本轮修）：无板→对端数据的连接，FIN 被握手 ACK 分支抢占

- **范围比“零数据”更广**：HLS 的 `c.seq` 只到 `ISS+1`（数据由 fast TCB 发，HLS 不更新）；
  只要板上没有向对端发过数据，对端 FIN 的 `ack == c.seq`。
- 旧码 `layer_tcp.cpp:719`：`(flags&TCP_ACK)&&ack==c.seq` ⇒ `T_ESTABLISHED`（不 DEL、不释放）；
  FIN 分支 `:735-747` 不可达；后续 FIN 进 `T_ESTABLISHED`（`:757-761`）才 DEL，但槽停在
  `T_LAST_ACK`，最终纯 ACK 走 fast ⇒ **HLS 槽永久泄漏**。
- 板级历史对应：.4 单会话口 6 条无数据连接被关闭；.2 被饿死连接（0 字节）被关闭 ⇒ 累积 8 次表满。

## 2. 修法（F2）

- `hls/src/layer_tcp.cpp`：新增宏
  ```c
  #ifndef P11_FIN_FIX
  #define P11_FIN_FIX 0
  #endif
  ```
  `T_SYN_RCVD` 首分支改为
  ```c
  #if P11_FIN_FIX
  if((flags&TCP_ACK)&&ack==c.seq&&!(flags&TCP_FIN)){...
  #else
  if((flags&TCP_ACK)&&ack==c.seq){...
  #endif
  ```
- `hls/run_hls.tcl`：`add_files` 的 cflags 增加 `-DP11_FIN_FIX=1`（与现有 `BOARD_IP_DUAL=1 -DMAX_TCP_CONN=8` 同一行）。
- 语义：FIN+ACK 且 `ack==c.seq` ⇒ 走 `:735` FIN 分支：`cfg_write(DEL)` → `tcp_send(FIN|ACK)` → `state=T_FREE`。
  纯 ACK/ACK+数据不变；`T_ESTABLISHED` 的 FIN 路径不变。
- 已知暴露（登记）：FIN 分支不校验 seq（`c.peer_seq` 在 T_SYN_RCVD 只有 SYN+1）；伪造 FIN 可拆连接，
  F2 扩大了该面。未来可把 FIN 校验放到有 `rcv_nxt` 的 fast 侧。

## 3. 构建流程（修正 v1 的“bat 会重综合”错误）

1. 改 `hls/src/layer_tcp.cpp` + `hls/run_hls.tcl`；
2. 跑 `cmd //c 'hls\run_hls.bat'`（vitis-run --mode hls --tcl）生成新网表；
3. csynth 判据：`ap_ctrl_none` 仍在；本刀触及的循环 II==1；资源增量登记（**不要**读顶层 `?` 的 Latency 行）；
4. 新归档目录 `_proj_10g/notes/p11_synfix_20261105/hls_archive_p11fix_fin/`（只收 verilog/*.v|*.dat）；
5. `board/p11_build_cfg.tcl` 增 `p11fix_fin` 变体分支（不改默认 c4 映射）；
6. 构建 `0x3C`：`P11_HLS_VARIANT=p11fix_fin` + `P11_IMPL_STRATEGY=Congestion_SpreadLogic_high`；
   **断言 `HLS_NET_HASH` ≠ 0x3B**（新增门）；BID grep `32'h0000003C`；几何不变（NW=98）；
7. 时序门沿用现有 `P7B_TIMING_GATE`；失败重试阶梯事前写死（Spread → ExplorePostRoutePhysOpt → Performance_Explore），
   每臂新输入、归档 reports、失败位流禁烧。

## 4. 验证

### 4.1 csim（本刀无定时器，不涉及 settle/RTO 阈值）

- 新增 `test_p11_zero_data_fin()`（在现有 P11 用例之后）：
  - 发 SYN→SYN-ACK；记录 `ISS+1`；
  - **LEGACY 臂（P11_FIN_FIX=0）**：发一个 FIN+ACK(ack=ISS+1) ⇒ 断言 **DEL=0** 且（加 `-DTCP_STATE_PROBE`）状态
    ≠ FREE；再发第二个 FIN ⇒ 断言 DEL=1、状态进 `T_LAST_ACK`（**不是** FREE）——复现泄漏；
  - **FIX 臂（=1）**：发一个 FIN+ACK(ack=ISS+1) ⇒ 断言 **DEL=1** 且状态 FREE；再发新 SYN ⇒ 能建连。
- 双臂身份：runner 传 `-DP11_FIN_FIX=0/1`，输出文件带 `_legacy/_fix` 后缀，TB 打印 `P11_FIN_ARM=LEGACY|FIX`，
  runner 断言该行；`check_csim.py` 的 3 条基线 XFAIL 集合逐字不变。
- LEGACY 臂必须仍复现 R2（负对照有牙）；FIX 臂不得多红。

### 4.2 板级 A/B（0x3B 负臂 / 0x3C 正臂）

- **主判据（F2）**：.4 口天然产生“无板→对端数据”的连接（单会话 app 只服务 2 条，其余 6 条零数据）。
  每轮 8 条连接（8×4GiB/20s；或等价的零数据构造）→ 全部关闭 → 轮末在 **.2** 发一条正常 connect：
  - 0x3B：**第 2 轮后 .2 connect 失败**（6/轮泄漏，2 轮填满 8 槽）；
  - 0x3C：**每轮 .2 connect 都成功**（FIN 全部释放），连续 ≥3 轮。
- **辅助见证**：W52[15:0]=app_ctrl estab（注意 .4 的事件在 app_ctrl2，主判据用 .2 的 connect 行为）；
- **F1 杀手回归（防未来重蹈）**：8 条活连接建立后**空闲 ≥1 s**，仍能继续传输并正常关闭（0x3C 必须过）。
- 回归：8×16MB 8/8、8×256MB 8/8、单连速率、W97 健康字、连续 20 轮 connect/close（每轮日志 ADD/DEL）。
- 每轮板级脚本首行断言 `0x04==0x3C`（负臂 0x3B 同理），否则 exit 2。

### 4.3 不做的验证（登记）
- 半开槽老化（F1）不做；raw-SYN 表满实验保留为“R1 诊断”，不作为本轮修复判据。
- `tcp_stat_no_slot` 不接出（不改几何，不触发 Tier A）；未来观测构建再议。
- R3（pending 单槽）不做。

## 5. 风险与回退

- F2 只影响 `T_SYN_RCVD` 的 FIN+ACK==c.seq 形态；活连接（有板→对端数据）不变。
- FIN|ACK 的 seq 是旧值（fast 已推进），对端可能 out-of-window 丢弃——无害（旧注释同结论）。
- 回退：`P11_FIN_FIX=0` + 重建（源码级 inert）。
- 若构建时序失败：按事前阶梯重试；HLS 网表变化会整体位移 DP 网表，历史 WNS 不作依据。

## 6. 未解决项（登记）
- R1 半开泄漏（对端放弃 SYN 重试后永久化；raw-SYN 可复现）——未来 B 方案。
- FIN 不校验 seq 的伪造面。
- `T_LAST_ACK` 老化不可达（若未来需要，用专用计时器，不复用 `retrans_pending`）。
- `tcp_stat_no_slot` 不可板读。
- `layer_tcp.cpp:559-565` 旧注释订正。
