# P11 APP8「每连接接收占用」设计 v5 — 独立对抗审查（只读）

- 日期：2026-10-28
- 审查者：独立 Claude agent（只读；未改任何文件）
- 对象：`DESIGN_OCC.md`（v3 正文 + v4/v5 修订）+ `REVIEW_RESPONSE.md` + `README_FOR_TL.md` + 现树 RTL
- 方法：逐条读源码/设计件，结论均带 `文件:行`；无证据的标【推断】
- **总判决：附条件可实现** —— 核心模型（`fq_i = winq_i − occ_i`、`win_pool_mgr` 零改动、不建 orphan 项）
  在代数与物理上成立；tcp_echo 写/读/回卷记账在按 §3.1 正确实现时可逐拍一致；cq 帧边界门证明成立。
  但 **v5 文本不能直接施工**，必须先处置 F1–F8（见下），其中 **F1 是"8×12KB 合同"命题的阻断级缺陷**。

---

## 一、发现表（按严重度）

| # | 严重度 | 发现 | 证据 | 后果 | 最小修法 |
|---|---|---|---|---|---|
| F1 | **阻断（合同命题）** | 8×12KB 合同下，ADD 期 TCB `rcv_wnd` 仍写死 `0xC000`（48KB）；`i_tcp_adv_wnd` 只改 HLS 的 SYN-ACK，不改 TCB。首个快路径帧（opener）若抢在 app_ctrl init 的 fc 纠偏之前装配，其 window 字段 = 48KB | `rtl/slow_cfg_adp.v:91`；`hls/src/layer_tcp.cpp:315`；`rtl/app_ctrl.v:1184-1190`；`rtl/tcp_tx_frame.v:1296`/`:1417`/`:1449`；`rtl/app_pattern.v:838-851` | 合同不是"每连接始终 12KB"；对端可能按 48KB 发送 ⇒ 窗口收缩后的重传/物理压力；tcpdump 若取到该帧会得到 48KB（两臂都 48KB ⇒ 假绿/无判别力） | 给 `slow_cfg_adp` 加 `RCV_WND_INIT`（默认 0xC000）并在两处例化传 `WQ_CAP_5`；2×48KB 构建时它恰是 0xC000 ⇒ 零回归；TB 增"ev_up 后首帧 window == WQ_CAP"断言 |
| F2 | **高（施工正确性）** | v4 已决定 `cur_words/rb_words` 改 14 位（覆盖 4096B=512 字），v5 §3.1 操作代码仍是 `[7:0]` | `DESIGN_OCC.md:82-87` vs `:210` | 若按 §3.1 实现：>255 字坏帧回卷时 `8*rb_words` 回卷 ⇒ occ 少减/多减 ⇒ 永久窗口泄漏（板上无 occ 快照，只 TB 能抓） | §3.1 改 `[13:0]`；`8*rb_words` 18 位；中间和 20 位有符号 |
| F3 | **高（板级判据）** | 前件写 `W62 > 12KB`；严格合同下每连接未消费数据上限 = `winq = 12,288`（SYN-ACK 通告 12KB），`>12KB` 可能为假；且 `occ==12,288` 时 fq 已 =0，缺陷在该点即显形 | `DESIGN_OCC.md:208,248,262`；`board/wrapper_p4.v:452-454`、`:3928`；`rtl/app_ctrl.v:774`；`board/wrapper_p4.v:5843` | 前件不满足 ⇒ 整轮记【空判据】；或只有靠 F1 的 48KB 泄漏才偶然满足，含义错误 | 前件改 `W62 ≥ 12,288`，并检查 `W62 ≤ winq + ACC_MARGIN`（合同上界）；conn0 win==0 作硬正控 |
| F4 | **高（判据假绿）** | 见证只写"src=板 MAC、对应 4-tuple 的 ACK 的 win"，未排除 SYN-ACK 与停顿前帧；HLS SYN-ACK 窗口恒 12KB（两臂相同） | `DESIGN_OCC.md:248,260`；`board/wrapper_p4.v:245-247,2470`；`rtl/rx_classify.v:103-107` | 若工具取第一条 ACK（SYN-ACK）⇒ 0x34 读成 12KB，A/B 假绿 | 过滤 `tcp.flags.syn==0 && ack==1`、时间 > 停读写入、`tcp.ack >= 探针 seq+1`；只取停读+一轮扫描后的板→对端帧 |
| F5 | **高（时序）** | 0x33 WNS 仅 +0.008 ns（0.125%）；v5 的 occ 读口是组合 16:1 mux → 跨模块 → 17 位饱和减 → redge_n → 寄存器；v5 只写"若 STA 需要再流水" | `README_FOR_TL.md:4,85-95`；`rtl/app_ctrl.v:669-676,973-974,1350-1356`；`DESIGN_OCC.md:252` | 首构建极可能时序失败，而 backstop 只允许换一次策略，不是重跑到过 ⇒ 白烧一轮 | **构建前**把 occ 读口在 tcp_echo 内打一拍并同时输出 id；app_ctrl 用 id 匹配（扫描失配则跳过该 tick；init 在 done 前 id 已稳定）；app_ctrl 的 fq 路径深度不变（occ 寄存器替换原 `rx_occ_bytes` 寄存器）；16 路 RMW 用共享 delta + 16 路二选一 |
| F6 | **高（既有、承重且被 v5 误量化）** | v4 L-3 的"fc T+2 写入 ⇒ ≤16 B staleness"是错的：T+2 只写 `fc_pend/fc_wq`，真正落 TCB 还要 `fc_load` + `fc_upd_wr` + **最低优先级** TCB 仲裁；其间 rcv_nxt 可先推进 X，窗口值相对新 rcv_nxt 偏高 | `rtl/app_ctrl.v:1480-1483`（T+2 仅挂请求）、`:853,:1694-1700`；`board/wrapper_p4.v:2717-2725`；`:1645`（Δ=2816 = 1G 上界） | 310 B 余量只吸收 X≤310 B；10G/8B 每拍 + fc 被 tx/rx 抢占时 X 可达 KB 级 ⇒ 物理界可能被突破。**既有 P5b 机制，非 per-conn 引入，但 v5 的安全论证依赖它** | 用 `stat_fc_wait_max`（0x9D）在 8 连接 10G 负载下测 K，重算 X=8·K B；若 X>310，给 fc 保证时隙/提高优先级，或扫描时重取 occ，或缩小 Σwinq 扩余量。未解决前不得写"8×12KB 物理安全已证" |
| F7 | **中高（判据失效）** | v5 M-2 删逐拍 `Σwinq+occ≤130,762`，改 I `occ_port≤130,762`、II `Σwinq≤WIN_POOL`；而 `S_COMMIT: Σwinq_after+s_occ≤WIN_POOL` 在 `c_g≤s_avail` 前提下是代数恒等式 | `DESIGN_OCC.md:251`；`rtl/win_pool_mgr.v:260-274,357,403-414` | O6 失去承重能力；真正要守的"事件时刻 + 采样误差"没人断言 | S_COMMIT 断言改为对 commit 时**实时** occ 的界：`pool_after ≥ occ_live − 16`（2 拍×8B 采样误差）；保留 `Σwinq+pool==WIN_POOL`（有牙）；报告不得写成"等价于旧 O6" |
| F8 | **中（不可实现分支）** | v5 §3.1 仍写"`judged && cq_full` 保持 tready 低直到有空间"；v4 L-1 已要求删 | `DESIGN_OCC.md:105-106` vs `:214`；`rtl/tcp_echo.v:88,118-125`；`rtl/fifo_sync.v:45-59` | `judged` 要求该拍 `accept`（tready 高），无法事后拉低；`cq_push && !cq_full` 时 cid 已被丢，救不回 | 删除该句；只保留 `stat_cq_ovf <= judged && cq_full` + `assert(fq<=126)`；构造不可达靠帧首门 |
| F9 | 中（板级协议/工具） | 探针机制基于"0 窗也因 ACC_MARGIN 被收下"（对），但工具无探针模式；1B 载荷若不是图案首字节会把 `ΔW54` 打成非 0 | `DESIGN_OCC.md:248`；`REVIEW_RESPONSE.md:33`；`board/wrapper_p4.v:1573-1578` | ΔW54 假红；或探针根本没发 | **直接用板→对端连续数据帧的 window 字段做见证**（8 个 app 都 TX_CONTINUOUS=1，`wrapper_p4.v:1735-1736`）；探针删除/仅兜底；工具若发送则发图案首字节 |
| F10 | 中（构建门） | `P11_APP8_OCC` 的 build 硬门未实现（现树 grep 0 命中）；且 wrapper 若写 `.PER_CONN_OCC(P11_APP8_OCC)`，宏必须在所有构建定义，否则 xvlog 报未定义 | `build_p7b_ku5p.tcl:72-84`；`DESIGN_OCC.md:125-128` | 0x34（OCC=0）也可能编不过；或硬门缺失让 OCC=1 进非 APP8 构建 | build tcl 默认 `P11_APP8_OCC=0`；OCC=1 时硬失败条件 = `!P11_APP8_ON || !P11_IS_DUAL`；wrapper 用宏值而非 `ifdef` |
| F11 | 中（v4 条件未落实） | v4 M3 的"短段洪泛 + app 停读 ⇒ mac 丢帧 / 全口 RX HOL 对称"没写进 v5 §7 | `DESIGN_OCC.md:192-199` vs `:211` | 板级"短段+停读"工况会静默出现（允许重传），报告若不登记会被误读成 occ 缺陷 | §7 增一条，写清"允许重传、不判丢帧" |
| F12 | 中（v4 条件未落实） | v4 M5 的 2 个变异、O3/O4 新断言只在修订表，v3 O 表未更新；O3 的 `fq≤127` 与 v4 L-2 的 `≤126` 矛盾 | `DESIGN_OCC.md:148-159` vs `:213-215`、`:104` | TB 按 O 表实现会漏 `!rback`/门阈值两个变异 | O 表重写终版（含 2 变异、`fq≤126`） |
| F13 | 中（可观测性） | 无 occ 记账快照；`stat_occ_underflow/stat_cq_ovf` 板上不可见 | `DESIGN_OCC.md:130,174-175` | 板上只能证"全局 vs per-conn"语义，不能证记账精确；少减一字时 A/B 仍可能"通过" | 报告写"记账精确性只在 TB 层有判据"；建议 0x36 加 1–2 字（occ[0]/Σocc + 两错误计数，96 FF/字） |
| F14 | 中（产品边界被低估） | §7-1 只说"可能 <12KB"；grant 可给 0，且 EXT_QUOTA=1 **没有 C15 补授**（`:1468` 的 `if (!EXT_QUOTA...)`），0 配额连接**不会自愈** | `DESIGN_OCC.md:194-195`；`rtl/app_ctrl.v:1468-1477`；`rtl/win_pool_mgr.v:23,260-274` | churn/孤儿场景新连接可能永久零窗，被描述成"可能 <12KB"会误导产品 | §7-1 改"可能为 0 且不自动恢复（无建连后借还）；产品需重连" |
| F15 | 中（文档一致性） | v5 = v3 正文 + v4/v5 表：§3.1 的 8 位计数器、`fq≤127`、"保持 tready 低"三处与 v4 表冲突；§2.1 的"Σwinq+occ≤WIN_POOL"没有 v4 要求的"授予/释放事件时刻"限定 | `DESIGN_OCC.md:50-53` vs `:209`；`:82-87` vs `:210`；`:104-106` vs `:214-215` | 施工者读正文会实现错；两份"同一设计" | 正文就地改终版（v6），不靠读者拼 |
| F16 | 低（宽度） | occ 内部 18 位 + delta（含 `−8·rb_words`，rb_words 14 位）的中间和需 ≥19 位有符号；§3.1 只写"内部 18 位" | `DESIGN_OCC.md:77,94-95` | 若 18 位加，边界可能溢出 | 明确"中间和 20 位有符号，再饱和回 18 位；输出饱和 17 位" |
| F17 | 低（判据口径） | "fq ≤ 127" → 正确上界 126；"≥256 拍/槽"含义不清（扫描是 16 拍/槽，整轮 256 拍） | `DESIGN_OCC.md:104,259`；`rtl/app_ctrl.v:523` | 文档错；测试等待可能理解错 | 改 `fq≤126`；改"≥一整轮（256 拍）" |
| F18 | 低（跨口） | port0 的 app_ctrl 会扫到 port1 拥有的全局槽：`winq[k]` 是 port1 的配额、`occ_port0[k]=0 ⇒ fq=12KB`；`redge[k]` 在 T+1 被写且无 state 守卫 | `rtl/win_pool_mgr.v:173-176`；`rtl/app_ctrl.v:1434-1446`（:1438 无 state 门）；`DESIGN_OCC.md:123` | 无功能写（fc/wu 有 ST_ESTAB 门），但 redge 被污染；跨口同槽换手的短窗口内可能给"旧口 TCB"写窗（既有风险，per-conn 不加重的也需登记） | §3.2/§7 明写"occ_i 只保证属于本口 echo 的该槽；跨口槽的 fq/redge 无意义"；TB 加 port0 扫 port1 槽用例（期望零 fc/wu 写） |
| F19 | 低（A/B 双变量） | `!rback` 与帧边界门只加在 `PER_CONN_OCC=1` 支，0x34 保留现役 `s_axis_tready = !fifo_full`（含"回卷拍写被 FIFO 静默丢"的既有缺陷） | `DESIGN_OCC.md:98,107-108`；`rtl/tcp_echo.v:90`；`rtl/frame_fifo.v:258-259`（rollback 优先于写） | 0x34 vs 0x35 的差异不止 occ（还有 tready/回卷保护），坏帧工况 A/B 不可归因；干净跑无影响 | 两臂都开 `!rback`/门，或报告写明"两臂差 = occ + tready 门" |
| F20 | 低（默认路径逐位等价） | "PER_CONN_OCC=0 逐位等价"若用 `||`/三目依赖综合常量折叠，不保证网表逐位；新端口在 10+ TB 例化点悬空（Z） | `DESIGN_OCC.md:136-140`；例化点见 §三-G | 名义零回归、实际网表变了；xsim 的 Z | 用 `generate` 生成 occ 块与门；默认臂显式接 0；施工记录列出全部例化点 |

---

## 二、A–I 重点结论（审查原文摘要）

### A. occ 记账
- 写 +8 的 `accept` 与 `frame_fifo.wr` 同拍，`s_axis_tready` 用同一拍 `fifo_full` ⇒ `accept ⇒ wr_ok`，无"本拍决定、下拍落笔"错位（`tcp_echo.v:81,90`；`frame_fifo.v:105,288`）。
- cid = `first_b ? meta_conn_id : cur_cid`；`meta_valid` 在 w6、`meta_conn_id=conn_id_l`（`tcp_rx.v:422-428`），首载荷拍在 w6 之后（或 1–2B 短帧首=末拍），两种都成立。单字帧 `cw_n=1`、多字帧逐拍 `cw_n=cur_words+1` 正确。
- 读 −8：`rd_ev=fwd_rd`，cid=`cq_dout`（FWFT 头，帧内稳定；`tcp_echo.v:95,119`；`fifo_sync.v:53-57,73`）。
- 回卷 −8·rb_words：`rb_cid/rb_words` 在 judged 拍采样（本拍组合 cid_w/cw_n，含末字）；`rback` 下一拍；`frame_fifo` 该拍 `wptr<=wsnap`（`frame_fifo.v:258-263`）；rb_words 恰等于 wsnap→judged 的接受拍数（含合成尾字）。
- **`Σocc_i == (wptr−rptr)<<3` 应断言，且按每拍**；它**不检验归属**（全记 conn0 也满足），必须配 O1 的逐 tid 参考模型（主判据）。成立前提：无丢写、无 8 位 rb_words 回卷、`!rback` 门在、无 cid≥16。

### B. id 对齐
- `o_winq_rd_id` 是组合；`winq_q_scan/init` 取 `i_winq_rd`；manager 的 `winq_rd0` 也是组合读（`win_pool_mgr.v:173-176`）⇒ 扫描/init 拍同址同拍成立。扫描在 init_valid 时跳过。
- T+2 fc 用 `pb_wscan` 是 T 拍锁存；对 app 消费/回卷方向保守；对**数据到达**方向不是 16B（见 F6）。
- 16 槽/8 全局槽：槽号 ≥8 时 manager 返回 0、occ[8..15]=0 ⇒ 一致。port0 扫到 port1 的 k<8 槽时 `winq[k]` 是 port1 配额、occ=0 ⇒ fq=12KB；fc/wu 有 ST_ESTAB 门不写，但 `redge[k]` 无 state 门（`app_ctrl.v:1438`）⇒ 见 F18。
- **若打拍，不能只打 occ 不打 winq**；最小安全 = 仅扫描路打 `{winq,occ}`（或 fq），init 路保留组合 winq（grant 在 done 拍才可见，延一拍会读到旧值 0 ⇒ 零窗死锁，`app_ctrl.v:394-397`）。

### C. 帧边界门
- 证明成立：同一时刻只有一帧在飞；帧首门 `fq<126` ⇒ `fq≤125`；帧内无新 push；judged 拍 push 后 ≤126 <128；7 位 fq 不回卷。
- 唯一失配源 = `cq_push && cq_full` 丢 push 但 fq +1（`tcp_echo.v:118-125,161-165`）；门排除后不可能。
- 坏帧回卷不引入死锁（rback 一拍释放门）；app 永久停读 ⇒ RX HOL（v4 M3 已知边界，v5 §7 未登记 = F11）。
- `judged && cq_full` 的"保持 tready 低"**不可实现**（F8）。

### D. 窗口语义
- `redge` 单调只增（`app_ctrl.v:1438`），但**从不写 TCB**；写 TCB 的是 `fc_wq=pb_wscan`（`:1481-1482`），edge = `rcv_nxt + fq(T)`；occ_i 增大时 rcv_nxt 同步推进 ⇒ 不会越 redge。**但 0x99 `dbg_redge0` 不再是"当前通告窗"的见证**。
- **板级 ACK/data window 字段 = TCB.rcv_wnd**（`tcp_tx_frame.v:1296/1417/1449`）；HLS 的 `tcp_adv_wnd_cur` 只进 SYN-ACK（`layer_tcp.cpp:315`）。见证必须排除 SYN/SYN-ACK（F4）。
- 1B 数据段 ⇒ `RT_FAST`（`rx_classify.v:103-107`）⇒ `tcp_rx→ack_req→tcp_tx_frame`；APP_MODE 下 `cfg_suppress_data_ack=0` ⇒ 每段立即纯 ACK。
- 0x34 空闲连接 TCB 窗**会**被 fc 写成 0（`pb_state=ST_ESTAB`、`pb_wscan=0`、`pb_rwnd=12,288` ⇒ `fc_pend/fc_wq=0`，`app_ctrl.v:1480-1482`）。空闲连接无数据时板不主动 ACK ⇒ 对端仍以为 12KB，1B 探针照发，板按 `rcv_wnd(0)+ACC_MARGIN` 收下并回 win=0。**另外：8 个 app 都是 TX_CONTINUOUS ⇒ 板→对端连续数据帧本身就带 window 字段，可直接作见证（F9）**。
- 0x35 空闲连接 occ_i=0 ⇒ fq=12,288=rwnd ⇒ 不写，TCB 保持 12KB；探针后 occ_i=8 ⇒ 12,280。
- 正控：0x35 的 conn0 窗必须为 0；若仍 12KB，说明 fc 没落地，整轮不可判。

### E. 物理安全
- `Σwinq + occ_port ≤ WIN_POOL` **不是逐拍不变量**：只在 grant 事件时刻、且用 grant 采样的 occ 成立；数据到达后 Σwinq=96KB、occ>0 时立刻"违反"。正确终态：grant 时 `pool_after ≥ occ_sampled`；真实不变量 = "每连接物理占用 ≤ winq_i + ACC_MARGIN"，由此得预算 130,762。
- per-conn fq 删 orphan 项后仍 ≤130,762（在 F6 之外）：孤儿占用在 occ_port；grant 的 `−occ_port` 保证"孤儿占用 + 活连接总配额 ≤96KB"；Σwinq_live + occ_orphan ≤96KB + 一项 ACC_MARGIN，加其余 margin = 96KB+8×3328=124,928，加 Δ+U+SEG=5,834 ⇒ 130,762。前提 = 孤儿 ≤ 旧 winq+ACC_MARGIN（tcp_rx 接受门）。
- 310 B 会被：① grant S_LOAD→COMMIT 采样误差 ≤16B（余 294B）；② `u_eco_pipe` 1 字（8B，W62 不含但物理在板上，余 286B）；③ **F6 的 fc 过通告 X（KB 级，未覆盖）**；④ occ 流水 +8B（保守方向）；⑤ 任何 per-conn 少减（F2）永久泄漏。**结论：310 B 只在 X≤286B 且记账精确时安全；v5 证明不足以支持 10G/8 连接。**

### F. 板级协议
- conn0 持续发流在 12KB 合同成立时**不会**填满 128KB FIFO（自身窗口 12KB + margin）；但 F1 的 48KB 泄漏会带来重传噪声。**仍建议 `--send-bytes` 限 ~16KB 并等 `W62≥12,288`**。
- 扫描是 16 拍/槽、整轮 256 拍（`app_ctrl.v:523`+`:1324`）；v5 的"≥256 拍/槽"表述含糊（F17）。等一整轮 ≈1.64 µs；fc 落 TCB 还受最低优先级仲裁（F6），建议同时看 0x9D 或 conn0 正控。
- `0x08=0x4` 可行：`pcie_scratch[1:0]`=TX_DIS、bit2 空闲（`wrapper_p4.v:6350-6368`）；写 0x4 保 TX 开。双门 `app_rx_tvalid=eco2_tvalid && !stall` + `eco2_tready=app_rx_tready && !stall` 在 eco2 单点施加；demux 纯组合；`u_eco_pipe` 只多存 1 字；tvalid=0 期间无握手；app 实例 `rx_tready=(rxs==0)`（`app_pattern.v:693`），无内 skid ⇒ 不会看到半字。
- tcpdump 过滤：`tcp.flags.syn==0`、时间 > 停读、`tcp.ack >= 探针 seq+1`；不要取第一条 ACK。

### G. 零回归与例化
- 必须用 `generate/ifdef` 生成（不能靠三目"应该"折掉）；默认 `s_axis_tready` 必须恰为 `!fifo_full`；app_ctrl 三处默认必须走原 `fq_calc(...,rx_occ_bytes)`；win_pool 不动；wrapper 新口显式接 0。
- 现树活件例化点：
  - `tcp_echo`：`board/wrapper_p4.v:2558`、`:3136`；TB：`tb/tb_tcp_echo.v:199`、`tb/tb_p5_multi.v:509`、`tb/tb_p5_app.v:401`、`tb/tb_p5_adv.v:368`、`tb/tb_p4_chain.v:718`、`sim/p5e_pre/tb_p5_udp_split.v:489`、`sim/p5e_pre/tb_p5_baseline.v:398`、`sim/p5b_adv/tb_p5_app_wnd.v:325`。
  - `app_ctrl`：`board/wrapper_p4.v:1852`、`:3269`；TB 十余处（见审查原文），全部具名端口，追加在末尾即可；`i_occ_rd` 默认臂不接就是 Z ⇒ 显式接 0。
- `P11_APP8_OCC` 门不够（F10）：需默认 0 / `OCC=1⇒APP8&&DUAL` / 否则硬失败。

### H. 时序与最小改动
- 真正危险的是跨模块组合：`tcp_echo.occ_reg[16] → 16:1 mux → app_ctrl.fq_occ → redge_n → pa_redge_n`。以 +0.008 ns 余量，首构建失败先验高；synth 检查点无判决力。
- 建议：① 扫描路寄存器化 `{winq,occ}`（scan_id 16 拍才变，1 拍仍同槽）；② init 路保留组合 winq（grant 在 done 拍才可见）；③ 16 路 RMW 用共享 delta + 16 路二选一；④ 构建前定向 STA 门；若 slack < ~0.3 ns 就按①加寄存器。成本 ≈34 FF + 8B staleness，换掉首构建失败风险。

### I. 其它
- F1/F3/F4/F6/F9/F14；0x34 不是"现役 0x33"，报告不得把它说成当前行为；grant 折扣要求"先建连后灌流"；7 条探针各 8B 对 cq 无影响；8 连建连 init 队列 4 深可能溢出但扫描自愈（M4，建议错峰建连并注明）。

---

## 三、v4/v5 条件落实核对（未落实项）

| 条件 | v5 状态 | 证据 |
|---|---|---|
| v3 H-1 judged 取样/含末字/单字帧 | 表落实；`cw_n/cur_words` 仍 8 位（F2） | `DESIGN_OCC.md:15,82-87` |
| v3 H-2 cq 满/fq 回卷 | 门落实；`fq≤127` 错；"保持 tready 低"不可实现（F8） | `:16,104-106` |
| v3 M-1 物理证明 | 预算落实；§2.1 逐拍不变量未加"事件时刻"限定且稳态为假（F15） | `:17,50-53,209` |
| v3 M-2 删 orphan | 落实 | `:18,43-46` |
| v3 M-5 板级协议 | 落实 | `:20,165-176` |
| v3 M-6 必红项 O1–O9 | 表未更新；v4 的 2 变异 + O3/O4 新断言只在修订表（F12） | `:21,148-159` vs `:213-215` |
| v3 L-3 cur_words 宽度 | **未落实**（仍 8 位，F2） | `:22,87` |
| v3 L-4 宏蕴含 | **未落实**（无 OCC 门，F10） | `:125-128` |
| v4 V3-M1 O6 两段 | 逐拍预算形被删；S_COMMIT 断言为恒等式（F7） | `:209,251` |
| v4 V3-M2 14 位 | **未进 §3.1 正文**（F2） | `:210` vs `:82-87` |
| v4 V3-M3 帧边界门→MAC 丢帧/HOL 登记 | **未进 §7**（F11） | `:211` vs `:192-199` |
| v4 V3-M4 occ 读口定向 STA | 仅"若需要再流水"，未做构建前门（F5） | `:212,252` |
| v4 V3-M5 变异/门生效 | 只在修订表，O 表未改（F12） | `:213` |
| v4 L-1 删"保持 tready 低" | **未删**（F8） | `:214` vs `:105-106` |
| v4 L-2 fq ≤126 | **正文仍 127**（F17） | `:215` vs `:104` |
| v4 L-3 2 拍/16B staleness | **论证错（F6）**；事件时刻限定未落正文 | `:216` vs `:50-53` |
| v4 L-4 授予折扣量化 | 部分；未写"0 配额不自动恢复"（F14） | `:217` |
| v4 L-5 OPEN_ITEMS | 本文件内不可核 | `:218` |
| v4 L-6 例化点清单 | **未列**（本审查代列） | `:219` |

---

## 四、最终判决

**附条件可实现** —— 先改 **F1（ADD 期 48KB→WQ_CAP）、F2（14 位）、F3（前件 ≥12,288）、F4（见证排除 SYN-ACK/停顿前帧）、
F5（occ 读口预流水 + 定向 STA 门）、F6（fc staleness 重新量化/限制，否则物理界不成立）、F7/F8/F12（O6/防御分支/O 表终稿）、
F10（OCC 宏与 build 硬门）**，其余 F9/F11/F13/F14/F15 可在施工记录与报告中登记；改完后可施工，并具备可判别的 0x34/0x35 A/B。

---

## 五、审查时点状态

- 未改 RTL / 未构建 / 未上板；板 = 0x33（BID 0x33 / NW 97）+ `0x08=0` + carrier 1/1。
- 设计件 v5 未通过本次审查；处置见 `DESIGN_OCC.md` 的 v6 修订。
