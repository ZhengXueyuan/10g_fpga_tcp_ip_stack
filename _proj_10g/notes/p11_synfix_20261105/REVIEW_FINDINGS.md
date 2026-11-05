# p11_synfix：两路独立红队审查 FINDINGS（2026-11-05/06，只读）

被审件 = `DESIGN.md` v1。两路均未改文件、未提交、未上板。行号均为审查时现读。

## A. HLS 代码正确性（审查 A）

### 总裁定
- **F1（被动老化）不能按 v1 实施**：被动构建里 `T_SYN_RCVD` 是**所有已建立会话**的 HLS 态
  （第三个 ACK 走 fast：`rtl/rx_classify.v:102,107`；源码注释 `hls/src/layer_tcp.cpp:730-731`；
  TB 注释 `hls/tb/udp_echo_tb.cpp:1391-1394`），且 `retrans_pending` 自 SYN+ACK 起恒真
  （`tcp_send` `:341`），到 RTO（156.25 MHz 下 **64 ms**，不是 80 ms）就被扫描释放（`:566-570`）。
  加 DEL ⇒ 拆活连接；不加 DEL ⇒ 后续 FIN 被静默丢弃（`tcp_find` 返回空闲槽，`:643/:653` 均假，
  `:680` return），fast 侧永不拆除。两者都不可接受。
- **F2（FIN 优先级）方向正确、风险面小，建议单独先行**（`P11_FIN_FIX=1`、`P11_SLOT_AGING=0`）。
  它修 R2，而 R2 是唯一有确定性 csim 复现的泄漏。

### 阻断
1. F1 语义错误（活连接同态）：`DESIGN.md:60-66` vs `layer_tcp.cpp:719-747`、`udp_echo_tb.cpp:1391-1394`、`rx_classify.v:102,107`。
2. 空闲拍 `cfg_write` 与源码明文禁区冲突：`layer_tcp.cpp:637-642`；`slow_cfg_demux.v:68-73`、
   `slow_cfg_adp.v:76-80,169-211`（16 深、ap_ctrl_none 无握手）⇒ 一次释放 8 槽可卡死主 FSM。
3. v1 §4.3 说构建会“HLS 重综合”是错的：`run_build_p7b_ku5p.bat` → `build_p7b_ku5p.tcl:143-165`
   只从 `P11_HLS_VARIANT` 导入**冻结归档网表**（`board/p11_build_cfg.tcl:45-58`）。

### 高
4. `T_LAST_ACK` 老化结构性不可达：`tcp_send` 只在 SYN/数据时置 `retrans_pending`（`:341`），
   纯 FIN|ACK 不置；强行置位会重传 seq 递增的垃圾 FIN|ACK（`:321/:402`）。
5. csim `settle(300000)` 仅默认 RTO 的 3%（`udp_echo_tb.cpp:1348` vs `layer_tcp.cpp:55-57`）；
   FIX 臂需 `-DTCP_RTO_MIN=100000`（两臂同带）或 10.5M pass。
6. F2 修复前预期写错：单个零数据 FIN 旧码进 `T_ESTABLISHED`（`:719`），要到 `T_LAST_ACK` 需**第二个 FIN**
   （`:757-761`）；测试必须发两个 FIN。
7. 缺 `SLOT_AGING=0/FIN_FIX=1` 推荐臂；csim 无 fast path，看不到“活连接被 DEL”的致命回归 ⇒
   板级必须加“活连接空闲 > 阈值后仍能收发并正常关闭”的用例（F1 杀手判据）。
8. FIN 分支不校验 seq（`c.peer_seq` 在 T_SYN_RCVD 只有 SYN+1，fast 数据不更新）⇒ 伪造 FIN 可拆活连接；
   F2 扩大该暴露面。登记，考虑移到有 `rcv_nxt` 的 fast 侧。
9. “80 ms”应为 64 ms（156.25 MHz）——`TCP_RTO_MIN=10M` 拍 / 156.25 MHz。

### 中/低（择要）
- DEL 参数应为 `(int8_t)i` + `c.local_ip`；现有 DEL 行号 `:645/:674/:738/:760`（v1 引的行号各差一行）。
- `ev_down` 只是“配额幂等”，不是“事件无害”；DEL 先于 ADD、槽未复用的不变量要写死。
- “LEGACY 臂证明逐位等价”是过度声称；只能写“宏=0 时源码级 inert”。
- 被动构建新增第三个 `tcp_rx_process` 内联副本（`:271`）⇒ DP 域新逻辑，DP 余量薄，需 csynth 资源 + 定向 STA。
- 老化/SYN 洪泛会冲 `app_ctrl` 16 深事件 FIFO（`app_ctrl.v:520-526`）。
- `tcp_state_probe` 守卫是 `#if defined(ACTIVE_CONNECT) && defined(TCP_STATE_PROBE)`；因 ACTIVE_CONNECT 恒有定义，
  被动臂加 `-DTCP_STATE_PROBE` 即可用。
- `layer_tcp.cpp:559-565` 旧注释“槽位释放不影响 fast 数据面”在 P11 架构下已不成立，应订正。

### 推荐的完整修法（未来，B）
- 用现成的 `ack_seen_w`/`ack_seen2` 每槽 ACK 观测位（`board/wrapper_p4.v:2947-2953,3478-3483`；
  `rtl/tcp_rx.v:614-624` 的 r6 修复已覆盖握手 ACK）在 **fast 侧**判“从未见过合法 ACK”的半开槽；
  1–3 s 超时后由 fast 侧拆 TCB/CAM/配额并发 CONN_DOWN；
  HLS 侧只加 8 位输入掩码 `i_slot_dead`，空闲扫描里对 `T_SYN_RCVD` 且掩码中的槽 `state=FREE`，
  **不写 cfg_stream**（避开空闲拍背压与 II）。旧归档网表用 ifdef 隔离。
- 同四元组 SYN 重传会原地回收槽（DEL+ADD 刷新，不增占用）；真实对端放弃重试后泄漏才永久化。

## B. 验证计划审查（审查 B）

### 阻断
1. csim FIX 臂按现计划跑不出来：`settle(300000)` < 10M 阈值；且老化生效后现有 `test_p11_halfopen_leak`
   的 4–5 条断言必红（`udp_echo_tb.cpp:1356-1387`），`check_csim.py:44` 的 `failed==3` 基线破。
   需整段宏隔或拆 `_legacy/_fixed` 两函数。
2. 构建不重综合 HLS（同 A-3）。
3. 80 ms 老化 vs 探针 100 ms 步进（`raw_syn_table_probe.py:44-47`）⇒ 0x3C 上“填 8”结构不可达，
   正臂“新 connect 成功”会因根本没填满而成立（空判据）。
4. csim settle 阈值问题（同 A-5）。
5. FIX 臂断言/基线（同 A-1 的 TB 侧）。

### 高
- RST 抑制不在工装且被 `env_setup_robust.sh:12` 的 `ip netns delete` 清掉；需入脚本 + `iptables -C/-L -v` 见证。
- “8 SYN-ACK”只有 W7 单口径；host 侧 `drain_synack` 实测 0 命中 ⇒ 先修见证再写【已证】。
- 20 轮 churn 只有**无板→对端数据**的轮次有判别力（有数据时 FIN ack≠c.seq，LEGACY 也能过）；且必须两臂都跑。
- 缺“早释放”下界判据（0.5×阈值仍应 DROP）。
- csim 臂身份/产物名会互相覆盖；缺 `-D` 会静默两臂同跑 LEGACY ⇒ 需 arm 后缀 + `P11_ARM=` 打印。
- II/Latency 判据不可读（csynth 顶层是 `?`）⇒ 改判据：`ap_ctrl_none` + Loop 表 II + 资源三条。
- BID/几何无机器门（`wrapper_p4.v:6532`；构建不读 BUILD_ID）。
- 最锋利且最便宜的零构建见证 = **W52[15:0] = app_ctrl estab 计数**（组合重算，`app_ctrl.v:725-741`）：
  raw-SYN 填 8 → est=8；老化后 → 0。0x3B 应恒 8，0x3C 应 8→0。

### 中/低（择要）
- 缩比 RTO 会让 `capture_if` 的 120k 空转老化整表；改 RTO 后必须重跑 LEGACY 并核 3 条 XFAIL 逐字不变。
- REPORT §2 对 W51–W54 归属自相矛盾（W51–W53 在 0x3B 已复用为 DIAG3B，源是 `u_app_ctrl`，不是 app_pattern）。
- v1 §4 只测“新 SYN 成功”，不测“老化发出的是 DEL 而非静默 FREE”。
- 构建重试阶梯应事前写死（1=SpreadLogic_high，2=ExplorePostRoutePhysOpt，3=Performance_Explore），每臂登记为新输入。
