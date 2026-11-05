# 0x3B DIAG3B 板级诊断报告（2026-11-05）

- 位流 = `bits/wrapper_p4_0x3B.bit`（sha256 `8540ee90…4057`，BID `0x3B`，**WNS +0.027 / 0 失败端点**，
  `Congestion_SpreadLogic_high`）；QSPI 零写入；每次上板前/后核 sha 与 BID。
- 仪器 = 复用**恒 0 的 app 统计字**：`W51={16'd0, app_tx_ready}` · `W52={app_ev_cnt, app_estab_cnt}` ·
  `W53=app_init_ovf`（零新 FF；源码 = `board/wrapper_p4.v:6049-6053`）。
- 原始件 = 本目录 `raw/verify_0x3B*_board.txt`、`raw/verify_0x3B_p0_*.txt`。

## 0. 结论速览（先读）

1. **【已证·板级】DIAG3B 仪器工作正常**，且与独立观测量逐项吻合（见 §2）。
2. **【已证·板级】W51–W53 采样的是 `u_app_ctrl`（ch1/X0Y5/J8 = IP .2 = `app_multi8` 所在口）**；
   0x3B 首跑 W51..W53 全 0 的原因是**测试流量打在 .4 口**，不是缺陷读数（§1/§3.2）。
3. **【已证·板级】干净复位后，.2 口 8 条并发连接全部建立并全部拿到数据**：
   8×16 MB 一轮全部收满（每条 4.6–9.1 Gbps 峰值），**不重烧复跑仍 8/8**；8×256 MB 错开启动 8/8 收满。
   ⇒ 历史“2/8 下行”不能作为 app8 的缺陷判据（它取自 .4 的单会话 app）。
4. **【已证·板级】真正薄弱点 = 数据流占线时的新建连接**：8 条同时 connect 时 `conn_ms` 呈
   0.1/0.1/1024/1003/2069/3072/3051/4117 ms 阶梯（1 s 量级 = SYN 重传），末端连接在 5 s
   连接超时下会 `ETIMEDOUT`（对端 `TcpExtTCPSynRetrans` 单轮 +24 = 6×4）。
   ⇒ 与历史“并发 8 只 2–4 条建立”同族，但**发生在 .2 口**，且指向**慢路径 SYN 处理/排队**。
5. **【未定位】首跑 .2 的 2/8（6 条 SYN 超时）后续 4 次复跑（含 .4 污染之后）均未复现**；
   重烧后恢复。候选 = 会话级残留态（与“慢盆”同类）/ 配额泄漏；**不写成已解决**。
6. **【未判定】内容相位**：`TX_CONTINUOUS` 下 per-connection 期望序列只在部分连接上对齐
   （mism=0 与 99.6% 相位错混合）——按既有口径，连续模式 `mism_bytes` **不是**内容判据。

## 1. 端口映射（本轮纠正的关键事实）

| 层 | wrapper port0 | wrapper port1 |
|---|---|---|
| 物理 | ch1 / X0Y5 / **J8** | ch0 / X0Y4 / **J7** |
| IP | **.2**（IP_A） | **.4**（IP_B） |
| app | **u_app = app_multi8[_cdc]（8 会话）** | u_app2 = app_pattern（单实例） |
| ctrl | u_app_ctrl | u_app_ctrl2 |

- 源码证据：IP 常量 `board/wrapper_p4.v:292-300`；port0/port1 分段 `:1340` / `:3102`；
  port1 app `:3428-3460`；`cfg_my_ip` `:3829` / `:4245`；P7B 前端 ch1=J8 `:558` / `:706`。
- **板级反证（本轮新）**：打 .4 的整轮测试中 W51/W52 **恒 0**；打 .2 时 W51/W52 立即出现与
  sink 状态一致的读数（§3）。
- **历史影响**：0x36/0x37 的 8 连接测试、`ss` 探针、并发上限结论与 0x36 报告 §8.x 全部取自 **.4**
  ⇒ 它们测的是**单会话 app_pattern 口**，不能用于 app8 产品判据。0x36 §8.3 已记录 .2 的图案与
  sink 失配（“port1 是另一份 app”），当时未意识到这正是 app8 口。

## 2. 仪器自检（DIAG3B 是否可信）

- **自洽验证**：8 条连接中 4 条已完成关闭、4 条仍活跃时，读数
  `W51=0x0000001e`（bit1..4 = 仍活跃槽）· `W52=0x001c0004`（`ev=28, estab=4`）
  —— 与 sink 的“4 条在跑、4 条已结束”**逐槽吻合**（`raw/verify_0x3B_p0_b_board.txt`）。
- **因果验证**：.4 有 8 条连接时 W51/W52 恒 0；.2 有连接时立即非 0（§3.2 vs §3.1）。
- **早前“app 统计字恒 0”的解释（限定）**：W51–W54 / W71–W74 的源是 **app_pattern 实例**；
  P11 数据面走 `app_multi8`，这些实例不被使用 ⇒ 恒 0 不是快照通路坏，也不能用作 P11 判据。

## 3. 板级读数

### 3.1 干净态（每次先重烧 0x3B，BID 复核）

| 轮 | 构型 | 结果 | 原始件 |
|---|---|---|---|
| c1 | 8×16 MB，0.5 s 错开，`--no-pin --check lane8` | **8/8** 建立并收满；每条 15–29 ms（4.6–9.1 Gbps 峰值）；`poll_tmo=0` | `raw/verify_0x3B_p0_c_board.txt` |
| c2 | 同 c1，**不重烧** | **8/8** 再次全部收满 | `raw/verify_0x3B_p0_c_run2.txt` |
| d | 8×256 MB，0.3 s 错开 | **8/8** 收满；每条 5.6–9.4 Gbps（各自独占窗口） | `raw/verify_0x3B_p0_d_board.txt` |
| e | 8×256 MB，**同时启动** | 7/8 收到数据（6 条收满，P7 `STALL` 0 字节）；`conn_ms` 阶梯 0.1/0.1/1024/1003/2069/3072/3051/4117 ms | `raw/verify_0x3B_p0_e_board.txt` |
| b | 8×16 MB，默认绑核 + `seq` 校验 | 8/8 建立；4 条在 96% 处被判 STALL（15 s 无数据） | `raw/verify_0x3B_p0_b_board.txt` |

- **b 轮的“STALL”是台架自伤**：8 个 sink × 2 线程被自动绑到**同一对核**（IO=5/WORK=6），
  逐字节 `seq` 校验 CPU 上限导致读不动 ⇒ 对端窗口关闭 ⇒ 板合法不发 ⇒ sink 的 poll 超时计数。
  改为 `--no-pin --check lane8` 后（c/d 轮）全部 `poll_tmo=0`。**该假停顿不得当板侧缺陷**。

### 3.2 .4 口（单会话 app_function 对照）

- `raw/verify_0x3B_board.txt`（05:4x）：8 条 4 GiB 错开，**8/8 建立**，仅 P0/P7 收到数据
  （4.97 / 3.51 Gbps），P1–P6 15 s 零数据；整轮 W51/W52 恒 0。
- ⇒ **.4 的“2/8”是单实例 app_pattern 的服务上限**，不是 app8 缺陷；同时再次证明 DIAG3B 采的不是 .4。

## 4. 新发现：数据占线时的新建连接被拖慢

- e 轮 `conn_ms` 阶梯（0.1 ms → 4.1 s）与对端 `TcpExtSynRetrans` 增量（失败轮 +24 = 6×4）
  指向 **SYN/SYN-ACK 在数据洪泛期间被丢或排队**。
- 机理候选（**未证**）：快路径数据 + 对端 ACK 洪泛占满 RX/TX 处理 ⇒ 慢路径 SYN 处理/慢 RX FIFO 排队；
  旧“慢路径会被饿死”的**证伪只覆盖 UDP 泛洪构型**（ping 5/5 + TCP 建连成功），不覆盖
  “TCP 数据 + ACK 双向满载时的新建连接”。
- **判据缺口**：板侧没有“慢路径见到 SYN / SYN 被丢 / 慢 FIFO 溢出”的计数器 ⇒ 现只能观测到
  对端 SYN 重传与 conn 时间阶梯。修它需一次构建（观测面 NW+）。

## 4.1 补充判别：**同时到达的两个 SYN，慢路径只应答一个；另一个靠 1 s 重传**（3/3 复现）

- **空闲对照（无任何数据流）**：每轮同时启动 2 条 `--no-pin lane8` 连接（各 16 MB），3 轮：

| 轮 | A `conn_ms` | B `conn_ms` |
|---|---|---|
| 1 | **1058.039** | 0.110 |
| 2 | **1041.582** | 1.412 |
| 3 | **1042.457** | 0.093 |

- 同一轮里一条立即可建立，另一条**稳定吃 1 s 量级**（= 首个 SYN 未被应答、由重传成功）。
  3/3 复现 ⇒ **慢路径一次只能应答一个 SYN，同时到达的其余 SYN 被丢弃（不是排队）**。
- **占线对照**：2 条长流（2 GiB）运行中，t=1 s 插入第 3 条连接 ⇒ `conn_ms = 3104.199 ms`
  （同轮长流自身 conn 0.093 / 2057.333 ms；空闲对照 0.116/0.159/0.147 ms）。
  ⇒ 数据占线把"1 s 级"进一步放大到多秒；5 s 连接超时下即表现为 ETIMEDOUT。
- ⇒ 当时读作"慢路径一次只应答一个 SYN"；**23:0x 的持续退化态（§8）给出更强解释**：
  更可能是 **HLS 连接表/槽位耗尽或泄漏**（当时可能只剩 1 个空槽，故一条立即、一条等重传；
  重传时前一条已关闭释放 ⇒ 第二条成功）。两者不互斥，**§8 的计数证据（W6/W16 涨、W7 零）优先**。
  原件 = `raw/syn_pair_idle.txt`、`raw/syn_under_load.txt`。

## 5. 未复现事件（如实登记）

- 首跑 .2（05:48，`raw/verify_0x3B_p0_board.txt`）：只有 P0/P1 建立并收满，P2–P7 全部
  `why=110 Connection timed out`（5.005 s），对端 `TcpExtTCPSynRetrans=24`。
- 其后 4 次复跑（含一次 .4 污染轮之后）全部 **8/8**；重烧不是必要条件（c2 轮未重烧仍 8/8）。
- 候选 = 会话级残留态（“慢盆”同类）/ 4 轮之前长期测试留下的配额/槽残留；**【未定位】**。

## 6. 下一步（按优先级）

1. **给慢路径加 SYN 观测**（板侧：SYN 收到/被丢、慢 RX FIFO 溢出、慢路径 TX 排队）—— 一次构建。
2. 把 `win_pool` 的 `pool / Σwinq / port_win` 接进快照（0x36 §8.2 已建议），判别配额泄漏假设。
3. **用 .2 口重做 8 连接产品判据**（0x36/0x37 的 8 连接结论只在 .4 ⇒ 只能当“单会话 app 行为”引用）。
4. 若 SYN 丢失落在慢 RX FIFO：评估深度/优先级改动（需时序与面积评估）。

## 7. 口径与限制

- 连续模式下 `mism_bytes` 不是内容判据（相位错形态：`first_mismatch` 0/1 + ~99.6%）；单次收满
  不证明内容正确。
- 本报告所有 Gbps 为 **sink 墙钟读数**；绑核状态见各 raw 文件的 `PIN_*` / `UNPINNED` 行。
- 未烧任何 TIMING_FAIL 位流；QSPI 零写入；每次上板前核 sha256/BID。
- 板现态 = **0x3B（BID 0x3B）+ `0x08=0` + carrier=1**。

## 8. 2026-11-05 23:0x 追加：**退化态持续复现 —— HLS 收下 SYN 但不回 SYN-ACK（W6/W16 涨、W7 零）**

- 复现序列（同一 0x3B 位流、重烧后约 10 min）：配对测试 R1 两条 0.1 ms 建立并收满 → R2 一条失败 →
  R3 两条都 `why=110`（5.005 s）⇒ **此后持续**：再跑两条同时 connect 仍全失败。
- **同刻判别**：`ping 192.168.100.2` **2/2 通、rtt 0.073–0.105 ms**（ICMP/ARP 慢路径正常）；
  紧接着两条 connect 均 5 s 超时。
- **计数（触发快照后）**：PRE `W6=0x1ab W7=0x4c W16=0x8eab W17=0` → POST `W6=0x1b5 W7=0x4c
  W16=0x91df W17=0` ⇒ **W6 +10（提交给 HLS 的慢帧）/ W16 +0x334（HLS 读走的字节）/
  W7 增量 0（HLS 发出的帧）/ W17=0（无饥饿复位）**。
- ⇒ **丢失点已夹到 HLS 内部（或其输出口）**：SYN 帧被慢路径接收并被 HLS 读走，但没有产生 SYN-ACK。
  ⛔ **2026-11-05 23:5x 订正（独立复核指出口径错位）**：**不能用 W59/W60=0 排除慢 FIFO 溢出** ——
  它们只是 `fifo_sync` 写门自检（`wr && full`，结构性恒 0）。正确排除式 = **W18（slow_tx_adp purge）=0
  ∧ W19（slow_rx_adp 丢帧）=0**（§9 已实测）；全窗另证 W0/W1 有增量而 **W4/W32-35/W38=0、
  W46–W49=0、W22 不变**。ARP/ICMP 仍通。
- **机理候选（未证）**：HLS 慢路径**连接表/槽位耗尽或泄漏**（新 SYN 无槽 ⇒ 静默丢弃）；新鲜重烧后
  **8 槽全空** ⇒ 8 连接、双 SYN 均即时成功（本轮 3/3）；状态累积后逐渐降级（先丢一条 → 全丢）。
  这与 06:47 的 3/3 1 s 重传（= 当时只剩 1 个空槽）以及历史"并发 2–4 条上限"**同一机制**。
- **下一步**：读 `hls/src/layer_tcp.cpp` 的连接表/槽分配与释放路径 + csim/TB 复现；把
  `stat_no_slot`（若存在）接进快照；修法（排队/扩表/释放漏点）+ 构建 0x3C + 板级 A/B。
- 原始件：本轮命令输出与 `raw/syn_pair_counters.txt`、本 §8；**未烧任何 TIMING_FAIL 位流**。

## 9. 2026-11-05 23:4x 追加：**退化态把缺陷夹到 HLS 的 TCP 接收入口**（UDP/ICMP 正常，TCP 连 RST 都不回）

- 退化态下三项同刻判别（同一位流、同一会话）：
  1) `ping 192.168.100.2` **2/2 通**（0.074–0.095 ms）—— ICMP/ARP 正常；
  2) HLS **UDP echo 8080 逐字节回环成功**（发送 `P11PROBE1234567`，收到同 15 B）—— 通用慢路径
     `rx_classify → slow_rx_adp → HLS → slow_tx_adp` 与 HLS 本身**活着**；
  3) TCP 到 **未监听端口 12345** 也 `TimeoutError`（**无 RST**）、TCP 8080 超时；
     tcpdump 抓到 5 个 SYN（1 s 间隔重传）**板侧零回包**。
- 计数：W18（slow_tx_adp purge）=0、W19（slow_rx_adp 丢帧）=0、W17（HLS 饥饿复位）=0；
  W6/W16 照涨、W7 基本不动；W52（HLS cfg ADD/DEL 事件数）不涨。
- ⇒ **缺陷局限在 HLS 的 TCP 接收处理**：连"未知端口应回 RST"都做不到 ⇒ 新 SYN 在 TCP 入口
  被**静默丢弃**（不是 TX 侧丢、不是适配器 purge、不是通用慢路径、不是 HLS 整体死）。
- 与源码侧候选一致（待 agent 复核）：`layer_tcp.cpp` 的 `tcp_find` 返回 −1 时静默丢弃
  （内部 `tcp_stat_no_slot`，无顶层端口）；`udp_echo.cpp` 的 `tcp_proc_pending` 单槽在
  新帧完成时会清掉挂起控制帧。**表满 vs 单槽覆盖**二者仍需 csim/源码定案。
- 下一步（零构建）：用 csim/TB 做 connect/close churn，检查连接表占用与 `tcp_find` 结果；
  一次构建时把 `tcp_stat_no_slot`/`stat_add`/`stat_del` 接进快照。

## 10. 2026-11-05 23:5x 追加：退化态**全计数器窗**（前端/CDC/classify 全部排除）

- 脚本 `degraded_full_window.sh`；原始件 `raw/degraded_full_window.txt`。单项 connect（5 s 超时）前后：
  - **PRE**  `W0=0x69832 W1=0x1a7ee7e W6=0x2f7 W7=0x8f W16=0x2ba47 W17=0 W18=0 W19=0
    W22=0x69598 W32-35=0 W38=0 W46-49=0 W52=0x00dc0000 W59=0 W60=0 W83=0x0a9b707a W84=0x0059c792`
  - **POST** `W0=0x6983c W1=0x1a7fb9e W6=0x301 W7=0x8f W16=0x2c78f W17=0 W18=0 W19=0
    W22=0x69598 W32-35=0 W38=0 W46-49=0 W52=0x00dc0000 W59=0 W60=0 W83=0x0adc0119 W84=0x0059c792`
- **增量**：W0 +10（MAC RX 帧）、W1 +3360、W6 +10（提交给 HLS）、W16 +0x1D48（HLS 读走）、
  **W7 +0、W18 +0、W19 +0、W17 +0、W46–W49 +0、W4/W32-35/W38 +0、W22 不变、W52 不变**。
- ⇒ **前端 MAC/CDC、rx_classify、慢 RX 适配器、慢 TX 适配器 purge 均无丢帧计数增量**；HLS 收到并读走
  全部 10 个慢帧；**HLS 没有写出任何帧、也没有写 cfg ADD（W52 不变）**。
  ⇒ 与 §9 的 UDP/ICMP 存活 + “TCP 连未监听端口也不回 RST”合并，**丢失点在 HLS 的 TCP 接收入口
  （`tcp_find`/连接表）**，而非 RTL。
- ⚠️ **口径限制（未判定）**：W1/W16 的“字节/拍”换算与 SYN 帧长（74B+8B 前导）**不自洽**
  （10 帧却 +3360/+7496）—— 可能计数单位/窗口含其它流量，**不得用它反推帧长**；本格的判据只用
  **增量有无**（0 vs 非 0）与 W6 帧数（+10 与 W0 +10 吻合）。
- 零构建剩余判别（独立复核建议，尚未做）：① 单项 connect 的 W52 已做（Δ=0）；② **旧源端口复用**
  （需先重烧建立基线再 churn；若旧四元组成、新四元组失败 ⇒ 表满实锤）；③ 双 SYN 间隔扫描
  （极小间隔才失败 ⇒ `tcp_proc_pending`；任意间隔都失败 ⇒ 持久表状态）。

## 11. 2026-11-05 23:5x 追加：**板级决定性复现 —— 8 个半开 SYN 填满 HLS 表；RST 释放一槽即恢复**

- 方法：重烧 0x3B → nsa 内 `iptables -I OUTPUT -p tcp --tcp-flags RST RST -d 192.168.100.2 -j DROP`
  抑制内核 RST（板子的 SYN-ACK 回给**真实对端 MAC**，不是伪造源 MAC —— 单帧实测 pcap
  `02:00:00:00:00:01 > board` 后板回 `board > 00:0f:53:2c:68:01`），再用 `raw_syn_table_probe.py` 发 8 个
  原始 SYN（sport 40000..40007，dport 8080，伪造源 MAC）。
- **结果（原始件 `raw/raw_syn_fill_rst_suppressed.txt`）**：
  - `BASE_CONNECT OK`（新鲜态正常）；
  - `RAW_SYN_SENT 8`（8 个 SYN 各得一个 SYN-ACK：**W7 `0x0a→0x13` = +9** = 1 个基线 + 8 个原始）；
  - **`CONNECT_AFTER_FILL TimeoutError`**（第 9 条正常 connect 的 SYN 无应答 ⇒ 表满静默丢）；
  - `RST_SENT 40000` → **`CONNECT_AFTER_RST OK`**（释放 1 槽后立即恢复）；
  - 计数 PRE `W6=0x20 W7=0x0a W52=0` → POST `W6=0x2d W7=0x13 W52=0x000a0008`
    （ev=10 / estab=8 ⇒ 8 个半开连接在 app_ctrl 侧被计为 ESTAB）。
- ⇒ **【已证·板级】HLS 连接表容量 = 8；半开连接占槽且不老化；表满后新 SYN 静默丢；RST 可释放。**
  与 csim（§12）和源码链（`layer_tcp.cpp:540/680`、`udp_echo.cpp:263-277`）**三方一致**。
- 注：本实验结束时表内仍有 7 个半开槽（仅 RST 释放了 1 个）⇒ 板子现处于“只剩 1 槽”的退化态；
  后续板级轮开始前必须重烧。

## 12. 2026-11-05 23:5x 追加：**csim 判别用例实跑（TB 扩展 +331 行；基线 3 XFAIL 不动）**

- 文件 = `hls/tb/udp_echo_tb.cpp`（新增 `test_p11_syn_pair_same_window` / `test_p11_halfopen_leak` /
  `test_p11_conn_churn`；`tcp_slot_drop_count()` 作为 csim 专用探针链接）。运行 =
  `run_csim_p3_all.bat` ⇒ **RC=0 / `CSIM_P3_ALL_PASS`，passed=106/103/82，failed=3（基线）**，两次重跑逐字节相同。
- 原始判据行（MAX=8/DUAL=1）：
  ```
  P11_TB_SYNPAIR_ARM_A  SYNACK=2 ADD=2 DEL=0 DROP=0        # 空闲对照：2/2
  P11_TB_SYNPAIR_ARM_B  SYNACK=2 ADD=2 DROP=0 ARP=1        # ARP busy 72 拍：不足以覆盖（负结果）
  P11_TB_SYNPAIR_ARM_B2 SYNACK=1 ADD=1 DROP=0 UDP=1        # UDP busy 954 拍：pending 覆盖（幸存=第二个 SYN）
  P11_TB_SYNPAIR_ARM_C  SYNACK=1 ADD=1 DROP=1 PREFILL=7/7  # 近满：只准入一个
  P11_TB_SYNPAIR_ARM_C_FULL SYNACK=0 ADD=0 DROP=2          # 表满：静默丢
  P11_TB_HALFOPEN_FILL  SYNACK=8/8 ADD=8 DEL=0 DROP=0
  P11_TB_HALFOPEN_FULL  SYNACK=0 ADD=0 DROP=1              # 30 万 idle pass 后仍 0/0 ⇒ 不老化
  P11_TB_HALFOPEN_RESYN SYNACK=1 ADD=1 DEL=1               # 同四元组 SYN 回收
  P11_TB_HALFOPEN_RST   DEL=1                              # RST 释放
  P11_TB_HALFOPEN_RECOVER SYNACK=1 ADD=1                   # 恢复
  P11_TB_CHURN          ROUNDS=8 SYNACK=8 ADD_BAD=0 DEL_BAD=0 DROP=0
  P11_TB_RESULT PASS (failed_delta=0)
  ```
- 结论：**(a) 半开槽永久泄漏**（被动构建无老化）与 **(b) `tcp_proc_pending` 单槽覆盖**两条候选
  **均被 csim 证实**；(a) 是累积/永久机制（主因），(b) 需要足够长的 TX busy 覆盖两个 SYN 完成拍
  （偶发，不累积）。遗留：**FIN 顺序 bug**（零数据 FIN 的 `ack==ISS+1` 被 `:719` ACK 分支吃掉）
  尚未在 csim 用例中覆盖，修法设计需一并处理。
