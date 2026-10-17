# 双光口「出口身份」两方案对比 —— CAM+1 vs A-1

- 日期：2026-10-18 · 角色：**只读架构分析**（未改任何 RTL/脚本/工具，未跑 xsim/Vivado，未碰板/对端/烧录，未写 git）。
- 基线：工作树 **0x2A**（`BUILD_ID_V = 32'h2A`，`board/wrapper_p4.v:4479`；快照 **76 字** / 未实现地址 `0x160`，`:3394`；**WNS `+0.039` / WHS `+0.010` / 三类失败端点 0/0/0**，周期 6.400 ns ⇒ 余量 **0.61%**；placed **78,248 LUT / 75,360 FF**，出处 `_proj_10g/notes/p9_build_0x2A_20261017/README_FOR_TL.md`）。
- 判据层口径：**本件不下 PASS/FAIL 裁定**（裁定权在用户/判据所有者）。「未观测到」≠「不存在」；纸面数字一律标 **纸面**。
- 状态词：**【已证·源码】/【已证·构建】/【已证·板级】/【推断】/【未判定】/【未测】**。
- 写入面：仅本目录。

---

## 0. 一页结论

| 维度 | 证据性结论 | 等级 |
|---|---|---|
| **流程更短** | **A-1 更短**。RX 侧 A-1 **零新增操作**（76 位流、CAM 键、`rx_classify`/`vlan_strip` 全不动）；CAM+1 要在 5 个流模块各加 1 位 + CAM 键加 1 位。TX 侧两方案**基本等价**（都要把 1 位 sideband 送过两级 `tx_arb` 到 split）。建连路径：若 CAM+1 的端口位由 `local_ip` 派生 ⇒ 与 A-1 等价；若要“物理口绑定”则 CAM+1 需新增 SYN 标签关联表 ⇒ 更长。 | 【已证·源码】+【推断】 |
| **耦合更低** | **A-1 更低**。身份相关改动：A-1 ≈ **9 个既有 RTL 文件 / ~11 个接口点 / 4 条不变式**；CAM+1 ≈ **14 个既有 RTL 文件 / ~20 个接口点 / 5 条不变式**，且**改变 CAM 4 元组键语义**（回归语料从 4 元组变 5 元组）。⚠️ **A-1 必须补上 P1 漏掉的 `tcp_tx_frame` 源 IP/校验和改动**（审查高-4 成立）；但在“每口独立 IP”裁定下，**这组改动是两方案共同前置**（CAM+1 也不能用单一源 IP），不是 A-1 独有成本。 | 【已证·源码】+【推断】 |
| **延时最小** | **稳态 0 拍差异**（两方案都不新增流水级）。组合深度：CAM+1 的 CAM 键多 1 位**不增加比较树级数**（32→33 位仍落在同一 LUT6 深度）【推断】；A-1 若用“每帧比 IP”则多 32 位比较（≈2 级 LUT），但可寄存、不在帧发射关键路径；若用“建连时存 1 位”（TCB/槽数组）则连这 2 级也没有。**结论：延时打平，A-1 可用存储换掉比较、CAM+1 天然是 1 位查表**。两方案选口 mux 都在**两级 arb 之后、`u_txcdc` 之前**——对前端零影响。 | 【推断】 |
| **1-2 口兼容** | **A-1 更天然**。单口时只有一个 IP，`port` 常量化 ⇒ 选口逻辑整体折叠；76 位流/CAM/分类器**源码级不动**。CAM+1 单口时端口位恒 0，综合可裁，但**源码里 5 处流宽 + CAM 5 元组语义仍在**，单口构建不是“逐字原样”。两方案都能做“一个位流同时兼容 1/2 口”（第二位无流量 ⇒ 端口位恒 0）。 | 【已证·源码】+【推断】 |
| **推荐** | ⭐ **A-1（无标签、IP 即身份）**，并把端口位**在建连时派生并存储**（推荐 wrapper 16 槽 1 位数组，`tcb.v` 改 1 位为备选），发送路径用该位选口 + 选源 IP 常量；慢路径用“HLS 帧源 IP → 端口”提取。**前提**：用户“每口独立 IP”裁定不变 + 授权 HLS 双 IP 改动。**反向前提**：若将来要同 IP 双口/N 口，A-1 不成立，必须回到 CAM+1。 | — |

**最关键的 3 个事实（先读）**

1. **CAM+1 的“建连绑口”在本架构里没有一个已存在的写入源**：CAM 的 ADD 由 `slow_cfg_adp` 写，而它的输入是 **HLS 的 8 词记录**（`rtl/slow_cfg_adp.v:4-16`）；HLS 的记录里只有 `w2 = local_ip`，**没有物理端口**（`hls/src/layer_tcp.cpp:156,177`）。`tcp_rx` 的 SYN 输出（`syn_v/syn_sip/...`）**已悬空**（`board/wrapper_p4.v:1873-1878,1967-1973`，`tcp_synp` 已拆除）。⇒ CAM+1 若把端口位写成“物理口”，必须新增 **SYN 标签关联表**（SYN 到达时记住 4 元组→口，ADD 到达时查），或者让 HLS 多带一位；若从 `w2` 派生端口位，则它和 A-1 的 `dip` 是**同一个信息**，CAM+1 的“显式端口”退化为冗余编码。
2. **A-1 的 `dip` 通路已经现成且闭合**：`slow_cfg_adp` 在 **S_CAM 同一拍**把 `w2` 写进 `cam_cfg_dip`（`rtl/slow_cfg_adp.v:122,148`）；`tcp_rx` 用帧的**目的 IP** 组 CAM 键（`rtl/tcp_rx.v:213,443-446`）；`tcp_cam` 已有 `rd_dip` 读回（`rtl/tcp_cam.v:36,73`）；wrapper 里 `cam_rd_dip` 已连好但**零消费者**（`board/wrapper_p4.v:1904,2088`）。A-1 只是把这个已有的 32 位字段接到 TX 侧。
3. **TX 侧的 1 位必须穿过两级 `tx_arb`，这是两方案共同的结构债**：`tx_arb` 是 73 位硬编码（64 data + 8 keep + 1 last，`rtl/tx_arb.v:9-25`），`u_tx_udp_arb`（`:2814`）与 `u_tx_arb`（`:2865`）串联后才到 `u_txcdc`（`:2891`，WIDTH=73）。split 在 arb 之后 ⇒ 端口位要么把两级 arb 加到 **74 位**，要么把 split/demux 提前到每个生产者（复制 arb 树）。P1 的“73 位、两条、端口位在 split 消费”**漏了 arb 这一段**（审查高-3 成立）。

---

## 1. 前提、边界与“共同成本”

### 1.1 用户裁定（2026-10-17，plan §0.5）

- **甲模式：每口独立板 IP**（第二口配独立 IP，对端用该 IP 寻址第二口）；乙模式无 IP、只转发 RX。
- **不做独立连接池**（`WIN_POOL = 49152 B` 全局共享）；单栈 + **一条 10G TX 线**。
- 本轮只比较“甲模式下出口身份”，不比较 RX 合并公平性/速率上限（那些是共享问题）。

### 1.2 被比较的到底是什么

被比较的**不是**“要不要双口接入”的总成本，而是**“会话身份/出口选择”这一个子问题**。以下成本两方案**共同承担**，不进入对比计数：

| 共同项 | 位置/依据 | 说明 |
|---|---|---|
| ch0 `mac_rx_10g` + `fifo_async(76×256)` | `wrapper_p4.v:854-943` 旁新增 | P1 已设计；与身份无关 |
| `rx_merge2`（新件） | 插在 `u_rxcdc` 输出与 `vlan_strip` 之间 | 76 位或 77 位由方案决定（**唯一的共享件宽度差**） |
| `tx_split2`（新件）+ 第二 `fifo_async(73)` + 第二 `mac_tx_10g` | 插在 `u_tx_arb` 与 `u_txcdc` 之间；`wrapper_p4.v:2883-2891` | 与身份无关；端口位在 split 处被消费 |
| HLS **双本地 IP** | `hls/src/eth_types.h:119-123`、`layer_ip.cpp:76-83`、`layer_arp.cpp:149,194,201`、`layer_icmp.cpp:142-143`、`layer_igmp.cpp:121-122`、`layer_udp.cpp:168-169`、`layer_tcp.cpp:177,277,292` | **两方案共同前置**：只要“独立 IP”，HLS 必须接受第二个目的 IP、并在 ARP/ICMP/SYN-ACK/数据帧里用匹配到的本地 IP 作源 IP，且 `cfg_write.w2` 写匹配到的 local_ip |
| UDP app 的**本地 IP 集** | `wrapper_p4.v:2470` 的 `cfg_dst_ip = 32'hC0A86402`（单值）；`rtl/udp_rx.v:181` `ip_match` 只比一个 `cfg_dst_ip` | 第二口的 UDP app 帧现在会被过滤掉；两方案都要把过滤从“单值”改成“二值集合” |
| 每口 TX 计数/观测 | 第二 `mac_tx_10g.stat_frames` 等（`_proj_10g/p7b_mac/rtl/mac_tx_10g.v:45-52`） | 建议同批进快照（否则“发错口”不可观测，见 §6） |
| 构建/读侧/BID | `build_p7b_ku5p.tcl:286`、`wrapper_p4.v:4479` | 共享 |

⚠️ **一句话**：A-1 的“源 IP/校验和改动”是**独立 IP 世界的入场费**，不是 A-1 相对 CAM+1 的额外成本；CAM+1 在“同 IP 双口”世界才不需要它——而那个世界与用户裁定冲突。

---

## 2. A-1 机制（无标签，IP 即身份）

### 2.1 建连（ADD → 事件 → app）

| 步骤 | 现读事实 | A-1 增量 |
|---|---|---|
| HLS 写 8 词记录 | `slow_cfg_adp.v:4-16`：`w0=cmd/slot/wscale`、`w1=peer_ip`、`w2=local_ip`、`w3=ports`、`w4/w5=mac/wnd`、`w6/w7=seq` | **0**（`w2` 已是匹配到的本地 IP——前提是 HLS 双 IP 改动已完成） |
| S_CAM 写 CAM | `slow_cfg_adp.v:137-163`：`cam_cfg_dip <= w2`（`:148`） | **0** |
| TCB 7 字段 | `:164-206`（6 字段 + `S_TCB_LAST` 的 wscale） | **0**（CAM 版）；**+1 字段**（TCB 版，见 §2.6） |
| `ev_up` → `app_ctrl` | `:195-205`；事件字 102 位 `{kind,slot,peer_mac,peer_port,peer_ip}`（`rtl/app_ctrl.v:28-35`） | **0**；若要 app 看端口：`ev_port` 可从同一拍的 `w2` 派生，**+1 位/零拍**（可选） |
| 连接身份 | CAM 键 = `(sip,dip,sport,dport)`（`rtl/tcp_cam.v:58-69`），`dip` 就是本地 IP | **0**；两口 IP 不同 ⇒ 同 4 元组也不会撞 |

**结论**：A-1 在建连路径上**不增加任何 RTL 步骤**。“绑定”= `CAM.dip` 在 ADD 拍被写入；TX 按 `conn_id` 读回该字段。

**A-1 写入点/宽度（逐文件，供核对）**

| 写入点 | 文件:行 | 承载宽度 | 备注 |
|---|---|---|---|
| `CAM.dip` | `rtl/slow_cfg_adp.v:148`（`cam_cfg_dip <= w2`） | **32 位 ×16 槽**（`rtl/tcp_cam.v:36-40`） | **既有**，A-1 的直接依赖 |
| 槽端口数组（推荐） | `board/wrapper_p4.v:2061-2067`（同 `cam_cfg_wr_mux` 拍并行写） | **1 位 ×16** | 零改 `slow_cfg_adp` |
| TCB 端口（备选） | `rtl/tcb.v:36-75,94-105` | **1 位 ×16** | 需 `upd_sel` 接口选择（§2.6） |
| 事件端口（可选） | `rtl/app_ctrl.v:28-35` | **1 位**（102→103） | app 可见性 |
| TX 帧边带 | `rtl/tcp_tx_frame.v`（新 `o_port`）、`rtl/udp_tx_cfg.v`、`rtl/slow_tx_adp.v` | **1 位/帧** | 送进两级 `tx_arb`（74 位）到 split |

### 2.2 每帧发送路径（TCB 扫描 → tcp_tx_frame → 两级 arb → split）

现读路径与新增点（**OVL 体 = 板上生效体**，`TCP_TX_OVL=1` 见 `build_p7b_ku5p.tcl:286`）：

| 环节 | 现读锚点 | A-1 增量 |
|---|---|---|
| 帧启动取 CAM 字段 | OVL：`f_dmac/f_dip/f_sport/f_dport <= cam_rd_*` 两个装载点 `rtl/tcp_tx_frame.v:1205-1208,1354-1357`；控制槽 `ctrl_dip <= cam_rd_sip` `:1324`；默认体：`:2284,2411` | 增 `f_local_ip[0:1]`、`ctrl_local_ip`（各 32 位）并**同一拍**从 `cam_rd_dip` 装载 ⇒ **+96 FF 纸面**（OVL：2 bank + 1 ctrl）；端口位可由 `local_ip` 派生并寄存 1 位 |
| IP 校验和（数据帧） | `ip_csum_calc(f_totlen,f_idcap,f_dip)` `:1396-1397`（函数体内用 `cfg_src_ip`，`:400-401`） | 改用**已寄存的 `f_local_ip[rx_bank]`** 作源 IP；函数加一个 `src_ip` 入参（或读模块寄存器）。`RX_FIN fin_cnt==4` 时该值早已寄存 ⇒ **不进关键路径** |
| IP 校验和（控制帧） | `ctrl_ipcsum_now = ip_csum_calc(...,ctrl_dip)` `:900`；装载拍 `start_ack+1` | 用已寄存的 `ctrl_local_ip`；R-1 重定时结构保持不变 |
| TCP 伪头种子（数据） | `csum_init_val = cfg_src_ip + cam_rd_sip + 6` `:817-819`，在 `start_data || ring_start` 拍被 `checksum16.init` 采样 | **这一拍 `f_local_ip` 尚未落地** ⇒ 需组合读 `cam_rd_dip`（与现有 `cam_rd_sip` 同型，多一个 32 位 CAM 读 mux 操作数）→ **+0-1 级 LUT（纸面/推断）**；或用“建连存 1 位”的变体（§2.6）把这里变成 1 位 mux |
| TCP 伪头种子（控制） | `csum_init_ctrl = cfg_src_ip + ctrl_dip + 6` `:874-876` | 用已寄存的 `ctrl_local_ip` |
| 头字发射（源 IP 字段） | `:1440` `{h_ipcsum, cfg_src_ip, h_dip[31:16]}`；默认体 `:2481` | `cfg_src_ip` → `h_local_ip`（控制/数据 mux），1 个 32 位二选一 |
| 源 MAC | `cfg_src_mac = 48'h000A3501FEC0` `wrapper_p4.v:2330`；头字 `:1437-1438` | 两方案都**未要求** per-port MAC；同 MAC 直连可接受（⚠️ 未来接交换机/同 L2 需另裁） |
| 端口位 → 两级 arb | `rtl/tx_arb.v:9-25`（73 位）、`:29-34`（组合 mux）；`wrapper_p4.v:2814,2865` | **+1 位**（74 位）穿过两级 arb；**两方案相同** |
| split | 计划插在 `u_tx_arb.m_axis` 与 `u_txcdc` 之间（`wrapper_p4.v:2883-2891`） | 1 位选择 2 路；**两方案相同** |
| 重放（ring） | ring 帧用 bank 里的 `f_*` 字段（`f_ipcsum` 在 `RX_FIN` 算好，`:1395-1397`） | **必须**把 `f_local_ip/f_port` 按 bank 锁存（否则重放会用“当前 CAM”的 IP，与首帧不一致）；本设计已覆盖 |

### 2.3 慢路径（HLS：ARP/ICMP/SYN-ACK/UDP echo）

- HLS 出帧是**完整以太网帧的字节流**（`slow_tx_adp.v:1-15`，16 位/字节，`bit8=TLAST`），RTL 侧**拿不到“端口”边带**。
- A-1 的取法 = **从 HLS 帧的源 IP 反推端口**：内容帧第 4 个 64 位字（`w3`，0 起；字节 24..31）的 `[47:16]` = 字节 26..29 = IPv4 源地址（无 VLAN 时）。`slow_tx_adp` 已有字节 FSM/帧缓冲，加一个字节位置计数 + 32 位锁存 + 比较即可（**纸面 ≈ +40 FF / +10 LUT**）。
- ⚠️ **前提/风险**：HLS 的 `mac_tx_req_t.insert_vlan`（`hls/src/eth_types.h:217`）当前**从未被置 1**（全仓 `grep insert_vlan` 只有定义与读取 `layer_mac.cpp:218`）⇒ 当前帧无 VLAN、偏移固定；若将来打开 VLAN，源 IP 偏移 +4 字节，提取器会**静默选错口** ⇒ 必须写死“HLS TX 不加 VLAN”的不变式或让提取器处理 tag。**【已证·源码】+【推断】**
- A-1 也可以用 `dst_ip → port` 学习表（plan §2-S2 的备选），但若两个对端口同 IP（或同一对端 IP 出现在两口）会退化；**源 IP 反推更稳**（源 IP 就是板自己，必定唯一标识口）。

### 2.4 UDP app

- 现读：`udp_split` 的 meta 只有 `src_mac/src_ip/src_port/len`（`rtl/udp_split.v:209-213`），**没有 dst_ip**；`udp_tx_cfg` 的 peer 表只有 `{peer_mac, peer_ip}`（`rtl/udp_tx_cfg.v:66-77`）；`cfg_my_ip` 是常量（`wrapper_p4.v:2762`）。
- A-1 增量：`udp_rx` 把已经在 `ip_match` 里算过的目的 IP 引出成 `meta_dst_ip`（**纯线束，零逻辑**，`rtl/udp_rx.v:181,210-213`）→ `udp_split` 透传 → `udp_tx_cfg` 的 peer 表存 `{peer_mac, peer_ip, my_ip}`；`udp_tx_frame` **已有 `cfg_src_ip` 输入**（`rtl/udp_tx_frame.v:37`），帧器本身不必改（端口位由 `udp_tx_cfg` 在**帧窗口内冻结**输出，cfg 冻结语义见 `rtl/udp_tx_cfg.v:45-55`）；端口位 = `(my_ip == IP1)`，与 `cfg_src_ip` 同源。
- 单 peer 表的限制不变（两口的 UDP 会话同时活跃时，仍是“最后学习者赢”——这是既有语义，不是 A-1 引入）。
- ⚠️ 共享前置：`udp_split.cfg_dst_ip`（`wrapper_p4.v:2470`）必须从单值改为二值集合（见 §1.2）。

### 2.5 单口退化

- 单口构建：`IP1` 不存在 ⇒ `port` 是常量 0；`f_local_ip` 恒为 `IP0`（HLS 单 IP 时 `w2` 也是 `IP0`）。**若整段用宏/参数关掉，单口构建可与现树逐位等价**（源 IP 回到 `cfg_src_ip` 常量）。
- 单口运行时（一位流、双口硬件但只插一根线）：`port` 全 0，merge 只有一路有效，split 只走 ch1 —— 天然兼容。

### 2.6 用户问题 1 的直接回答：能否在 ADD 拍把 port 存进 TCB？

**可以**，且成本可核：

| 存法 | 写入源/通路 | 成本 | 代价/风险 |
|---|---|---|---|
| **TCB 1 位**（推荐备选） | `slow_cfg_adp` 在 S_CAM 用 `w2` 比 IP 常量得到 1 位；ADD 序列在 `S_TCB` 加一个字段写 | `rtl/tcb.v`：`reg port_r[0:15]`（**+16 FF**）、复位、`upd_sel` 新分支、`rb_port`/`rc_port` 输出；`slow_cfg_adp.v`：+1 个 `upd_sel` 字段（S_TCB 多一次 `cfg_gnt` 握手，**建连 +1-2 拍**，相对 HLS 的 ms 级可忽略） | `upd_sel` 是 **3 位、7 已保留**（`rtl/tcb.v:103` 显式拒写防误落 wscale）⇒ 三种选择：(a) 占用 sel=7 并撤销该守卫；(b) 加独立 `port_wr` 口；(c) 把 wscale 扩 1 位。三种都要动接口 ⇒ **不是纯内部改动** |
| **wrapper 16 槽 1 位数组**（推荐） | **零改 `slow_cfg_adp`**：wrapper 已有 `cam_cfg_wr_mux/cam_cfg_addr_mux/cam_cfg_dip_mux`（`board/wrapper_p4.v:2061-2067`）——在同一个 `cam_cfg_wr_mux` 拍写 `port_arr[cam_cfg_addr_mux] <= (cam_cfg_dip_mux == IP1)`；读口按 `rb_id` 组合读 | +16 FF + 1 位读 mux；DEL/孤儿清会写 `dip=0` ⇒ 端口自动清 0 | 多一个“与 CAM 同拍”的数组（不变式：同拍同址同源）；tcp_tx_frame 仍需 +1 位 `port` 输入并在帧启动拍锁存 |
| **每帧比较 `cam_rd_dip == IP1`**（最省状态） | 帧启动拍寄存 | **+32 位比较（≈2 级 LUT）+ 1 FF/bank** | 比较落在帧启动/CSUM init 那一拍；可用“先寄存 local_ip、下一拍再比”把比较移出该拍（但 csum init 那一拍仍要组合 `cam_rd_dip`，见 §2.2） |

**关键判断**：TCB 版**不能**省掉 `tcp_tx_frame` 的源 IP 改动（帧头仍要 per-conn local IP），所以它省掉的只是“每帧 32 位比较”，代价是 TCB 接口 + 一份冗余状态（`TCB.port` 必须与 `CAM.dip` 保持一致）。**若选 A-1，推荐 wrapper 槽数组**（不碰 TCB 的 sel=7 守卫，也不在数据路径上加比较）；**若选“最小状态”**，则用每帧比较并把 `local_ip` 先寄存一拍。

---

## 3. CAM+1 机制（端口标签贯穿）

### 3.1 RX 侧标签（77 位）

- 现状 76 位 bundle = `{tdata[63:0], tkeep[7:0], tuser, tlast, tcrs, terr}`（`wrapper_p4.v:921-925`；`fifo_async(76)` `:932`）。
- CAM+1 加 1 位后 = **77 位**。注意：历史规格书里的“77 位”曾是**算术错**（那条注释 `:922-925` 明确警告 77 与 76 的拼接会静默截掉 `tdata[63]`）——CAM+1 会让 77 变成“正确宽度”，但**必须把该注释与所有拼接顺序一起改**，否则重演“最高位被截”的全线错位。
- 逐级改动（无流水级增加）：
  1. `u_rxcdc`（2 条）WIDTH 76→77（`:932`）；
  2. `rx_merge2`（新件）77 入/77 出；
  3. `vlan_strip` +1 入/出（`rtl/vlan_strip.v:68-80`）；它是**1 深输出寄存器 + `S_PASS/S_W1/S_SHIFT/S_TAIL` 重定时**结构（`:94-97`）⇒ 标签必须与数据**同拍同伸展**（+1 FF hold，且 S_TAIL 的尾字也要带同一标签）——**标签错位 = 整帧错口，线上不可见**；
  4. `rx_classify` +1 入/出，字 FIFO `FW=76→77`（`rtl/rx_classify.v:26-66,70,76-94`）；
  5. `tcp_rx` +1 入（`rtl/tcp_rx.v` 端口表/`cam_q_port`）；
  6. `udp_split` 在 SOP 锁存 1 位并引出 `meta_port`（`rtl/udp_split.v:209-213` 旁）；
  7. `slow_rx_adp` 收 1 位（但**进不了 HLS 的字节流**，见 §3.4）。

### 3.2 ADD 拍：端口位写到哪里？

| 候选写入点 | 承载宽度 | 通道 | 问题 |
|---|---|---|---|
| `tcp_cam.port_r[0:15]` | 1 位 ×16 = **+16 FF** | `slow_cfg_adp` S_CAM（`rtl/slow_cfg_adp.v:137-163`）同拍写 | **源从哪来？** HLS 记录无端口（`layer_tcp.cpp:156,177`）；`tcp_rx` 的 SYN 输出已悬空（`wrapper_p4.v:1873-1878`） |
| TCB port | 1 位 ×16 | 同 A-1 §2.6 | CAM+1 计划里 TX 读 CAM 的 `rd_port`，TCB 不是必需 |
| 事件字 `ev_port` | 1 位 | `slow_cfg_adp` S_CAM 锁存 | 只影响 app 可见性，不解决出口 |
| 流标签 | 1 位/字 | RX 流 | 到不了 ADD（ADD 是 HLS 异步产生的） |

**三条可行源（必须显式选一条，plan 未指定）**：

1. **HLS 在 `w0` 空位带 1 位**（`w0[31:20]` 空闲）：HLS 必须知道端口。若 HLS 已经为“独立 IP”改成双 IP，它可以从“匹配到的 dst IP”推出端口 ⇒ **这仍是 IP 派生，不是物理口**；同 IP 场景下它拿不到端口（HLS 帧里没有物理来源）。
2. **RTL 用 `w2` 比 IP 常量**：等价于 A-1 的 TCB 派生，**与 `dip` 信息冗余**。
3. **wrapper 新增 SYN 标签关联表**：SYN 走慢路径（`rx_classify` slow → `udp_split` → `slow_rx_adp`），在该处按 4 元组记录“来自哪个物理口”，ADD 到达时查表写 CAM。这才是 plan 字面意义上的“物理口绑定”；代价：新表（16 项 × 4 元组 + 口 + 老化）、SYN 重传/乱序/多 SYN 并发、DEL 清理、以及“ADD 早于/晚于标签到达”的竞态。**未在 plan/P1 中设计或估计。**

> 另一条（**不推荐，= 架构回退**）：恢复 fast-path SYN 安装器——`tcp_synp` 在现 wrapper 里**已废除**（`board/wrapper_p4.v:1880-1881` 逐字“syn_v sideband 端口留空”；`rtl/tcp_synp.v` 仍在但只被 `wrapper_tcp.v` 使用）。由 SYN 帧自己的标签在 ADD 之前直接写 CAM/TCB 可以拿到真正的物理口，但把 P4b 已合并到 HLS 的握手又拆回两套，不在本比较范围。

**CAM+1 写入点/宽度（逐文件，供核对）**

| 写入点 | 文件:行 | 承载宽度 | 源（三种之一，§3.2） |
|---|---|---|---|
| CAM 端口数组 `port_r[0:15]` | `rtl/tcp_cam.v:36-40` 旁（新阵列） | **1 位 ×16** | w2 派生 / HLS w0 位 / SYN 关联表 |
| CAM 配置口 `cam_cfg_port` | `rtl/slow_cfg_adp.v:27-33,146-151` | **1 位** | 同上（S_CAM 与 sip/dip/… 同拍） |
| TCB 端口（若用） | `rtl/tcb.v:36-75` | **1 位 ×16** | 同上 |
| 事件端口 | `rtl/app_ctrl.v:28-35` | **1 位**（102→103） | 同上 |
| RX 流标签 | `vlan_strip` / `rx_classify` / `tcp_rx` / `udp_split` / `slow_rx_adp` | **1 位/字** | 物理口（来自 `rx_merge2` 的输入侧） |
| TX 帧边带 | `tcp_tx_frame` / `udp_tx_cfg` / `slow_tx_adp` → `tx_arb`×2 | **1 位/帧** | CAM `rd_port` / peer 表 / 慢路径学习 |

⚠️ 表里“源”一列是**三条候选**，不是“已存在”：除 `w2` 派生外，其余两条都需要新增机制（HLS 字段或 SYN 关联表），**plan/P1 未给出其中任何一条的实现点**。

### 3.3 TX 侧（TCP/UDP/慢路径 → 两级 arb → split）

- `tcp_tx_frame` 增 `cam_rd_port` 输入（`tcp_cam.rd_port`，`rtl/tcp_cam.v:36` 旁）+ 1 位 per-bank 锁存 + `o_port`；与 A-1 的 `cam_rd_dip` 同型（把 32 位 CAM 读换成 1 位）。
- 源 IP/校验和：**在独立 IP 世界同样要改**（OVL 体 4 处：函数/数据 init/控制 init/头字；默认体 3 处：函数/伪头 init/头字）；CAM+1 若把“端口→源 IP”做成 2:1 常量 mux，则 csum init 那一拍只需 `cam_rd_port` 1 位（比 A-1 的 32 位 `cam_rd_dip` 便宜 **1 个 mux 宽度 + 无比较**）——这是 CAM+1 在 TX 侧**唯一**的实质优势（纸面）。
- UDP app：peer 表加 1 位 port（与 my_ip 一起）；`udp_tx_frame` 加 `o_port`（或由 `udp_tx_cfg` 冻结输出）。
- 慢路径：与 A-1 **同样**无法从 HLS 字节流里拿到端口 ⇒ 仍需“源 IP 提取/学习表/HLS 边带”之一。**CAM+1 并不自动解决慢路径**。
- 两级 arb + txcdc：与 A-1 相同（74 位或前移 demux）。

### 3.4 为什么 CAM+1 也绕不开慢路径的 IP/HLS 改动

- HLS 的 `tx_stream` 是 16 位字节流（`bit8=TLAST`、`bit7:0=byte`，`rtl/slow_tx_adp.v:1-15`；`hls/src/layer_mac.cpp:233,266,286,308` 逐字节写），**没有端口位**。CAM+1 的 77 位标签在 `slow_rx_adp` 就被“字节化”丢掉了（HLS 的 RX 接口 = 16 位字，`bit8=TLAST`、`bit7:0=byte`；`rtl/slow_rx_adp.v:133` 逐字 `assign hls_rx_tdata = {7'b0, o_dout};`）。
- 因此慢路径出口在**两方案**下都只能是：源 IP 反推（A-1 的自然做法）/ 学习表 / HLS 双 IP + 新增端口位（需 HLS 接口改动 + 重综合）。
- 而“独立 IP”本身已经强制 HLS 双 IP ⇒ 源 IP 反推在两方案下成本相同，CAM+1 的标签对慢路径**零帮助**。

---

## 4. 四维对比表

### 4.1 流程长度（逐段操作数）

| 段 | CAM+1 新增 | A-1 新增 | 谁更短 |
|---|---|---|---|
| RX 合并/分类 | 77 位流贯穿 `fifo×2 → merge → vlan_strip → rx_classify → tcp_rx/udp_split`（5 个模块 + 2 条 FIFO 宽度） | **0**（76 位原样） | **A-1** |
| CAM 查询 | 键 5 元组（16 个比较器各多 1 输入） | 0（4 元组不变） | **A-1** |
| ADD/事件 | 端口位写入 = 同一拍（前提：源可得）；物理绑定版本 +SYN 关联表 | 0（`dip` 已写）；可选 TCB/槽数组 +1 字段 | **A-1**（物理绑定版 CAM+1 明显更长） |
| 每帧 TX | 1 位 CAM 读 + 1 位锁存 + 74 位 arb + split | `cam_rd_dip`(32 位) 比较或槽数组(1 位) + 1 位锁存 + 74 位 arb + split | **平**（A-1 多一个比较/多一个存储，二选一） |
| 源 IP/校验和 | 独立 IP 世界同样要改（OVL 4 处 / 默认 3 处） | 同左 | **平**（共享前置） |
| 慢路径 | 仍需 IP 反推/学习表/HLS 边带 | 同左 | **平** |

**哪一段更长**：从“新增操作数”看，**CAM+1 的 RX 段最长**（跨 5 个流模块 + CAM 键）；TX 段两方案一样长；建连段在“IP 派生”前提下一样，在“物理绑定”前提下 CAM+1 最长。**A-1 的总操作数更少。**

### 4.2 耦合度（文件/接口/不变式）

| 指标 | CAM+1 | A-1 |
|---|---|---|
| 身份相关**既有 RTL 文件** | **14**（wrapper、`vlan_strip`、`rx_classify`、`tcp_rx`、`tcp_cam`、`slow_cfg_adp`、`udp_split`、`slow_rx_adp`、`app_ctrl`*、`tx_arb`、`tcp_tx_frame`、`udp_tx_cfg`、`udp_tx_frame`、`slow_tx_adp`） | **9**（wrapper、`tcp_tx_frame`、`udp_rx`、`udp_split`、`udp_tx_cfg`、`tx_arb`、`slow_tx_adp`、`app_ctrl`*、`udp_tx_frame`*）**+1 可选**（`tcb`） |
| 新增模块 | `rx_merge2`、`tx_split2`（**与 A-1 共享**） | 同左 |
| **接口点（宽度/端口/字段）** | **≈20 组**：5 个 RX 流口、CAM 3 组、`slow_cfg_adp` 1、`udp_split/meta` 1、`slow_rx_adp` 1、事件 1、`tx_arb` 2、`tcp_tx_frame` 2、UDP 2、慢路径 2、split 1 | **≈11 组**：`tcp_tx_frame` 2、`udp_rx` 1、`udp_split` 2、`udp_tx_cfg` 2、`tx_arb` 2、`slow_tx_adp` 1、事件 1（可选）、TCB 2（可选） |
| 受影响模块数（含间接） | 15（RX 5 + CAM/配置 3 + UDP 2 + TX 4 + 事件 1） | 9-10 |
| 新增**不变式** | ① RX 标签与字流严格同拍（`vlan_strip` 重定时/S_TAIL）；② CAM 5 元组唯一性；③ 标签 = 帧头端口 = 出口；④ ADD 端口与 SYN 物理口关联（物理绑定版）；⑤ 端口↔源 IP 一致 | ① `CAM.dip` = `HLS w2` = 帧头源 IP；② 出口 = f(local_ip)；③ UDP peer `my_ip` 一致；④ HLS TX 无 VLAN（源 IP 提取） |
| 回归语料影响 | **CAM 4 元组 → 5 元组**（`tb_tcp_cam_tcb`、`p7b_chain` 的 CAM 断言、任何按 4 元组构造的 TB） | CAM/TB 语料不变；新增的是“源 IP/端口”断言 |
| **判定** | — | **A-1 耦合更低** |

`*` = 可选（仅当 app 需要看端口 / UDP 路径需要显式 port 输出）。

### 4.3 延时（拍数 / 组合级数）

| 项 | CAM+1 | A-1 |
|---|---|---|
| 稳态每帧新增拍 | **0** | **0** |
| RX 组合深度 | CAM 比较 32→33 位：**同一 LUT6 深度**（6 个 LUT 覆盖 33 位）【推断】；标签只是并行 1 位寄存器 | **0**（不动 RX） |
| TX 帧启动 | `cam_rd_port` 1 位 CAM mux → 锁存（**1 级 mux**） | 槽数组：1 位 mux → 锁存（同）；或 `cam_rd_dip` 32 位 CAM mux → 32 位比较 → 锁存（**+2 级 LUT**）【推断】 |
| CSUM init 那一拍 | `src_ip = port?IP1:IP0` = **1 位 mux**（若端口已存） | 若端口已存 ⇒ 同 1 位 mux；若用 `cam_rd_dip` 现比 ⇒ +32 位比较 + 32 位 mux |
| split 选口 | 1 位组合 select（帧首字前已稳定，余量 ≥2 拍） | 同 |
| 慢路径端口 | 需等源 IP 字（第 3 字）；`slow_tx_adp` 整帧缓冲后才交给 arb ⇒ **不增加可见延时** | 同 |
| **判定** | 打平；**A-1 的“槽数组/TCB 1 位”变体才能与 CAM+1 的 1 位查表同等便宜**；A-1 的“每帧比 IP”变体多 2 级（可寄存但 CSUM init 那拍仍要组合读） | — |

⚠️ **不许把上面的级数当 WNS 预测**：0x2A 的 +0.039 是唯一可信输入；新增逻辑的布局影响不可纸面预测（P1 附录 C-2 同款口径）。任何构建都必须一次收口 + 预登记 backstop。

### 4.4 1/2 口兼容

| 项 | CAM+1 | A-1 |
|---|---|---|
| 单口构建（宏关） | 端口位恒 0；若用参数 `PORT_W=0/1` 需**参数化 5 个流模块 + CAM**；不参数化则源码里的 77 位/5 元组仍在，靠综合裁 | **无宽度/键语义改动**；`IP1` 未定义 ⇒ 选口常量 0、split 折叠；宏关时源 IP 回到 `cfg_src_ip` ⇒ 可与现树逐位等价 |
| 单口运行（同一位流） | 标签恒 0，功能正确；77 位 LUTRAM 宽度仍在（纸面 +几 LUT） | 端口恒 0，功能正确；76 位不变 |
| 两口运行 | 需要 ADD 绑定源（§3.2） | 两个 IP 天然区分 |
| “更天然” | — | **A-1** |

---

## 5. 改动面计数与逐文件清单

> 计数口径：**只列“身份”相关**；`rx_merge2`/`tx_split2`/第二 MAC/第二 FIFO/HLS 双 IP 是共享项（§1.2）。行号 = 2026-10-18 现读 HEAD（0x2A）。

### 5.1 CAM+1（14 既有 + 2 新共享）

| # | 文件 | 现读锚点 | 改动 | 接口变化 |
|---|---|---|---|---|
| 1 | `board/wrapper_p4.v` | `:932`（rxcdc 76）、`:975`（vlan_strip）、`:998`（classify）、`:2069`（CAM）、`:2814/2865`（arb）、`:2891`（txcdc） | 2 条 77 位 rxcdc、merge 实例、split 实例、常量 | 5+ 组 |
| 2 | `rtl/vlan_strip.v` | `:68-80` 端口表；1 深输出寄存器/S_TAIL | +1 入/出、hold 标签、S_TAIL 同标签 | +2 |
| 3 | `rtl/rx_classify.v` | `:26-66` 端口；`:70` FW=76；`:76-94` 字 FIFO | +1 入/出、FW 77 | +2 |
| 4 | `rtl/tcp_rx.v` | `:133-138` CAM 输出；`:443-446` 查询 | +1 入（tport）、`cam_q_port` | +2 |
| 5 | `rtl/tcp_cam.v` | `:9-33` 三组端口；`:58-69` 比较；`:71-75` 读回 | cfg/q/rd 各 +1 位、`port_r[0:15]` | +3（16 FF） |
| 6 | `rtl/slow_cfg_adp.v` | `:4-16` 记录布局；`:137-163` S_CAM | +`cfg_port` 输出/写入（源待定，§3.2） | +1 |
| 7 | `rtl/udp_split.v` | `:209-213` meta | +1 入、`meta_port` | +2 |
| 8 | `rtl/slow_rx_adp.v` | `:52-60` HLS RX 端口；`:133` 逐字节打包 | +1 入（仅用于关联/学习；进不了 HLS） | +1 |
| 9 | `rtl/app_ctrl.v` | `:28-35` 102 位事件 | 可选 +1 位（103） | +1 |
| 10 | `rtl/tx_arb.v` | `:9-25` 73 位；`:29-34` mux | +1 位（74）×2 实例 | +2 |
| 11 | `rtl/tcp_tx_frame.v` | OVL `:1205-1208,1324,1354-1357`；默认 `:2284,2411`；头字 `:1440,2481` | +`cam_rd_port`、per-bank/ctrl 1 位锁存、`o_port`；源 IP 改动（共享） | +2 |
| 12 | `rtl/udp_tx_cfg.v` | `:66-77` peer 表 | +1 位 port（与 my_ip） | +1 |
| 13 | `rtl/udp_tx_frame.v` | `:36-38` cfg 端口 | +`o_port` 透传 | +1 |
| 14 | `rtl/slow_tx_adp.v` | `:23-40` AXIS 输出 | +端口边带/提取 | +1 |
| 15 | 新 `rtl/rx_merge2.v` | 不存在（`ls rtl` 无 merge） | 77 位帧级 2:1 | 共享 |
| 16 | 新 `rtl/tx_split2.v` | 不存在 | 74→2×73 | 共享 |

### 5.2 A-1（9 既有 + 1 可选 + 2 新共享）

| # | 文件 | 现读锚点 | 改动 | 接口变化 |
|---|---|---|---|---|
| 1 | `board/wrapper_p4.v` | `:2325-2331`（CAM 读回 + `cfg_src_ip`）、`:2470`（UDP 过滤）、`:2762`（UDP my_ip）、`:2814/2865/2891` | `cam_rd_dip` 接进 `tcp_tx_frame`、merge/split、常量、UDP 接线 | 3-4 组 |
| 2 | `rtl/tcp_tx_frame.v` | OVL `:400-401,817-819,874-876,1205-1208,1324,1354-1357,1396-1397,1440`；默认 `:2008-2012,2022-2024,2284,2411,2481` | +`cam_rd_dip`、`f_local_ip/ctrl_local_ip`（+96 FF 纸面）、源 IP 替换（OVL 4 处 / 默认体 3 处）、`o_port`（端口源 §2.6） | +2（+内部） |
| 3 | `rtl/udp_rx.v` | `:181` `ip_match`；`:210-213` meta | +`meta_dst_ip`（纯线束） | +1 |
| 4 | `rtl/udp_split.v` | `:209-213` meta；`:215` cfg | +`meta_dst_ip` 透传、`cfg_dst_ip` 二值集（共享） | +2 |
| 5 | `rtl/udp_tx_cfg.v` | `:66-77` peer 表 | 每 peer +`my_ip`/port | +2 |
| 6 | `rtl/tx_arb.v` | `:9-25` | +1 位（74）×2（**共享**） | +2 |
| 7 | `rtl/slow_tx_adp.v` | `:23-40` | 源 IP 提取 → port（纸面 +40 FF/+10 LUT） | +1 |
| 8 | `rtl/app_ctrl.v` | `:28-35` | 可选 +1 位 | +1 |
| 9 | `rtl/udp_tx_frame.v` | `:36-38` | 可选（若 port 由 `udp_tx_cfg` 冻结输出则不改） | 0-1 |
| 10 | `rtl/tcb.v`（**可选**） | `:36-75` 端口、`:94-105` 写、`:122-128` 读 | 1 位/槽（+16 FF）、`upd_sel` 选择、读口 | +2 |
| 11 | 新 `rtl/rx_merge2.v` | — | 76 位帧级 2:1 | 共享 |
| 12 | 新 `rtl/tx_split2.v` | — | 74→2×73 | 共享 |

### 5.3 计数对比

| 计数项 | CAM+1 | A-1 |
|---|---|---|
| 身份相关既有 RTL 文件 | **14** | **9**（+1 可选 `tcb`） |
| 接口点（组） | **≈20** | **≈11** |
| 受影响模块（间接） | 15 | 9-10 |
| 新增不变式 | 5 | 4（其中 1 条与 VLAN 提取前提相关） |
| 回归语料语义变化 | **CAM 4→5 元组** | 无 CAM 语义变化 |
| 新增 FF（纸面） | CAM 16 + 5 级标签 ~5-10 + 其余由 split/arb 共享 ⇒ **≈30-60 FF**（不含共享） | `f_local_ip` 96 + 槽数组 16（或 TCB 16）+ 提取器 40 ⇒ **≈100-150 FF**（不含共享） |
| 新增 LUT（纸面） | CAM 比较 16×1 输入 + 标签 ⇒ **≈30-80 LUT** | 比较/常量 mux + 提取器 ⇒ **≈50-120 LUT** |

⚠️ 所有面积/FF 都是**纸面结构估计（±50%）**；两方案的绝对量级都很小，**真正的差异在耦合/回归面，不在资源**。

---

## 6. 风险与可测性

### 6.1 “发错口”线上不可见（两方案共同的头号风险）

- 帧从另一个 SFP 出去，线上**没有任何字段**标记“本应从哪出”；对端若两个口在**同一网络命名空间/同一子网**，Linux 弱主机模型可能**照收**（`rp_filter` 默认宽松时），于是“错口”表现为**完全正常**。
- 唯一有牙的观测：
  1. **对端两口各自的计数**（SFC9120 每口 `port_rx_packets/bytes`，`ethtool -S`）——⚠️ 项目已登记 `port_rx_*` 与内核计数**同源、非独立硬件计数** ⇒ 它与板侧 MAC 计数构成**跨系统**独立口径，但**不是**两个独立硬件计数器；
  2. **板侧每口 TX 计数**（第二 `mac_tx_10g.stat_frames`，`_proj_10g/p7b_mac/rtl/mac_tx_10g.v:45-52`）进快照——直接见证“哪个 MAC 发了帧”；
  3. **构造性负对照**：把端口位/比较/源 IP 强制成错值 ⇒ 两口径计数必须翻转。没有这条，判据是空判据。
- 建议的板级构型：对端 p0/p1 放**不同 netns**（或不同子网 + 显式 `/32` 路由），否则错口会被“弱主机”吃掉。

### 6.2 方案特有的可测性弱点

| 方案 | 弱点 | 需要的新门/负对照 |
|---|---|---|
| CAM+1 | ① 标签穿过 `vlan_strip` 的 1 深寄存器/S_TAIL 可能错位；② ADD 端口源若来自 SYN 关联表，有 SYN 重传/多 SYN/DEL 竞态；③ CAM 键从 4→5 元组，旧 TB 语义失效 | ① 标签-帧对齐单元门（含 VLAN/尾字臂）；② 关联表门（重传/并发/清槽）；③ CAM 5 元组回归 |
| A-1 | ① `CAM.dip`、HLS 帧源 IP、UDP peer `my_ip` 三个来源必须一致；② 慢路径源 IP 提取依赖“HLS TX 不加 VLAN”；③ `tcp_tx_frame` 双体（OVL/默认）都要改，板上生效的 OVL 体覆盖最弱 | ① 强制一个来源错值的负对照；② `insert_vlan=1` 构造（若将来启用）⇒ 判据必须红；③ 双体各跑一次源 IP/校验和逐字节门 |

### 6.3 门覆盖（现读）

- **常驻矩阵 19 门**（`sim/p4gates/run_matrix_p4dfix.bat:184-241`）里：`p5_wrapper` **只编 `-d APP_MODE`**（`:200-211` 注释逐字：不编 `PCIE_OBS/P7B_10G/UDP_TX_OVL`，且 `TCP_TX_OVL` 关闭时 r6 的 `ack_seen` 门也不在；实际 defines 在 `sim/p5sim/run_tb_p5_wrapper.bat:44-55`）。它**确实编译** `tcp_cam/tcb/tcp_rx/tcp_tx_frame/tx_arb/udp_*/vlan_strip/rx_classify`（同一 `xvlog` 行），但**只覆盖 APP_MODE + 默认 tcp_tx_frame 体（1G 路径）** ⇒ **板上 10G + OVL 体零覆盖**；矩阵另无这些模块的独立单元门。
- **`_proj_10g/p7b_chain/sim/run_tb_p7b_chain.bat:39`** 编 `P7B_10G + PCIE_OBS + DP_156MHZ + APP_MODE`，但**不编 `TCP_TX_OVL` / `UDP_TX_OVL`**（现读 define 列表）⇒ 它覆盖的是 **tcp_tx_frame 默认体**，不是板上生效的 OVL 体。
- 唯一编 `TCP_TX_OVL` 的门 = `sim/p7b_stagec_tx/run_tx_ovl_gate.bat`（及历史副本）；项目记录称其**跑不通**（CRLF vs `\n` 锚点，既存，`udp_hls_10g/CLAUDE.md`「未收口」段）——本轮未跑，**不重复断言**。
- ⇒ **两方案都必须**：① 把 `p7b_chain` 升为常驻第 20 门；② 让该门编 `TCP_TX_OVL`（或修复 `run_tx_ovl_gate.bat`）；③ 新增“端口位/源 IP 与帧同帧”的单元门 + 错口负对照。**否则 A-1 的源 IP 改动与 CAM+1 的标签对齐都落在“无门”区。**

### 6.4 时序余量

- 0x2A `WNS +0.039` = **0.61%**；全局宿主是 DP setup（`u_tcp_tx/u_fifo_b/rptr → u_app/stg`，`_proj_10g/notes/p9_build_0x2A_20261017/README_FOR_TL.md:50-51`）。
- CAM+1 的新逻辑主要在 RX（CAM/流），A-1 的新逻辑主要在 `u_tcp_tx` 的帧启动/校验和锥（接近 0x1C 当年最差的 `ctrl_tcpcsum` 族，后来被 R-1 重定时移出）；两者都**不能纸面预测**。
- 纪律：一次构建收口 + 预登记 backstop（P1 §6.3 的 B1/B2/B3 是给 ch0 观测字用的；身份方案应各自另立 backstop：先砍慢路径提取/端口边带，再砍日志字）。

### 6.5 空判据清单

| 判据 | 为什么空 | 建议 |
|---|---|---|
| “对端 p0 carrier up” | ch0 TX 恒发 `/I/` 就能让对端块锁（P0 已证） | 不作为“端口身份正确”的证据 |
| “链路无错/无 CRC” | 错口帧在正确链路上也是好帧 | 必须用**每口**计数器 |
| “peer 收到数据” | 同 netns 下错口会被弱主机接受 | 对端分 netns/子网 |
| “W76/W39 状态” | 只反映 PCS 状态，不反映出口 | 另加每口 TX 计数 |
| “单连接吞吐正常” | 错口可能仍可通 | 与“该连接的数据必须只出现在其口”配对 |

---

## 7. 推荐与前提

### 7.1 推荐：**A-1**（在用户“每口独立 IP”裁定下）

**理由（证据性）**：

1. **身份通路已存在**：`w2 → CAM.dip`（`slow_cfg_adp.v:122,148`）、`CAM.rd_dip`（`tcp_cam.v:36`）、`cam_rd_dip` 已连线（`wrapper_p4.v:1904,2088`）——A-1 只差“接到 TX + 一个端口派生”。
2. **不动 RX 流宽/CAM 键**：规避 CAM+1 的 5 模块标签 + 4→5 元组回归面。
3. **单口天然退化**：一个 IP ⇒ 端口常量 0；宏关时可回到逐字原样。
4. **A-1 的“额外成本”（源 IP/校验和）在独立 IP 世界是共同的**，不构成相对劣势；CAM+1 的“HLS 零改动”优势只在同 IP 世界成立，与用户裁定冲突。

**实施建议（把耦合压到最小）**：

- **端口位来源**：**wrapper 16 槽 1 位数组，在 `slow_cfg_adp` 的 S_CAM 拍由 `w2` 比 IP 常量写入**（不碰 TCB 的 `sel=7` 守卫；`tcb.v` 零改动）。备选 = 每帧比较 `cam_rd_dip`（+2 级、但少一份状态）。
- **源 IP**：`tcp_tx_frame` 增 `cam_rd_dip`，per-bank + ctrl 锁存 `local_ip`；`ip_csum_calc` 加 `src_ip` 入参；数据帧 `csum_init_val` 用 `cam_rd_dip`（那一拍只能组合读）；控制帧用已寄存的 `ctrl_local_ip`；`h_local_ip = port?IP1:IP0` 由端口位 mux（与出口同源，**一致性由构造保证**）。
- **慢路径**：`slow_tx_adp` 在字节 FSM 里锁存内容字节 26..29 → 端口；写死“HLS TX 不加 VLAN”不变式。
- **UDP**：`udp_rx` 引出 `meta_dst_ip` → peer 表存 `my_ip`；`udp_split.cfg_dst_ip` 改二值集。
- **TX 承载**：端口位走 74 位两级 arb，split 在 `u_txcdc` 前消费；**或**把 split 前移到每个生产者（复制 arb，73 位不变）——纸面两可选，前者改动少、后者不碰共享流宽。
- **观测**：第二 `mac_tx_10g.stat_frames`（+可选 `stat_tx_words`）进快照；对端两口分 netns；构造错口负对照。

### 7.2 前提（不满足则推荐失效）

1. 用户“每口独立 IP”裁定不变（plan §0.5-2b）。**若改回同 IP 双口 → A-1 不成立，必须 CAM+1。**
2. 授权 HLS 双 IP 改动 + 重综合（否则第二个 IP 的 SYN/ARP 根本进不了慢栈，A-1 和 CAM+1 都无法工作；CAM+1 的“HLS 零改动”只在同 IP 世界成立）。
3. 接受“慢路径源 IP 提取”这一新不变式（HLS TX 无 VLAN；当前 `insert_vlan` 从未置 1，【已证·源码】）。
4. 同 MAC 双口可接受（直连构型）；若未来接交换机/同 L2，需再裁 per-port MAC（两方案同额外交付）。
5. 时序按“一次构建收口 + backstop”执行（0.61% 余量）。
6. 对端路由/ARP 前置：p0/p1 同子网时必须显式 `/32` 路由 + `-I p0`（否则 Linux 按路由表选口，第二个 IP 的流量根本到不了板上；P1 审查中-13 同款）。

### 7.3 何时应选 CAM+1

- 用户改为**同 IP 双口**或未来 **N 口同 IP**（此时 `dip` 不能区分）；
- 或要求“端口身份与 IP 解耦”（例如 IP 可运行时重配、NAT、端口迁移）；
- 或要求 app/事件字显式看到“物理口”而不经过 IP（但 A-1 也可从 `w2` 派生事件位）。
- 选 CAM+1 时**必须先补 §3.2 的 ADD 写入源设计**（物理口绑定需 SYN 关联表；IP 派生则与 A-1 同源、失去其“显式”优势）。

---

## 8. 未测/纸面/未判定声明

1. **本件未改任何 RTL/脚本**；未跑 xsim/Vivado；未构建；未上板。所有“改动量/FF/LUT/级数”= **纸面结构估计（±50%）**，不是实现读数。
2. **WNS 预测不可给**：0x2A 的 `+0.039` 是唯一可信输入；任何“预计 WNS”都不成立。
3. **CAM+1 的 ADD 端口源 = 【未判定】**（plan/P1 未指定；三种候选各有代价，见 §3.2）。
4. **A-1 的 HLS 双 IP 改动 = 【未实施】/【未测】**；本件只给行号与语义，不保证 HLS 改通。
5. **慢路径源 IP 提取的 VLAN 前提 = 【已证·源码】（当前 `insert_vlan` 无生产者）**；未来启用 VLAN 的影响 = 【推断】。
6. **“发错口”的板级可观测性 = 【未测】**；每口计数/分 netns 的构型未跑。
7. **对端两口的 IP/路由/命名空间配置 = 【未定】**（产品配置，需用户定）。
8. **两方案的真实时序/资源增量 = 【未测】**；本件所有计数为“接口/文件”级，不是布局后数据。
9. **`rx_merge2`/`tx_split2` 是计划新增**（`ls rtl` 无 merge/split2）——本件比较的是“将要新增的机制”，不是既有实现。
10. **“未观测到 ≠ 不存在”**：本件对 CAM+1 的 ADD 通路缺口是**源码级缺席**（没有生产者），不是“跑过没看到”。

---

## 附录 A —— 关键引用（2026-10-18 现读）

| 主题 | 文件:行号 |
|---|---|
| CAM 键/读回 | `rtl/tcp_cam.v:9-33,36,49-55,58-69,71-75` |
| `w2=local_ip → cam_cfg_dip` | `rtl/slow_cfg_adp.v:4-16,122,148` |
| RX CAM 查询（dst IP） | `rtl/tcp_rx.v:133-138,213,443-446,680-681` |
| `cam_rd_dip` 已连/无消费者 | `board/wrapper_p4.v:1904,2088`（`grep` 仅两处） |
| `tcp_tx_frame` 源 IP 用途 | `rtl/tcp_tx_frame.v:392-405,400-401,817-819,874-876,1440,2008-2012,2022-2024,2481` |
| `cfg_src_ip` 常量 | `board/wrapper_p4.v:2330-2331` |
| per-bank/ctrl CAM 锁存 | `rtl/tcp_tx_frame.v:1205-1208,1324,1354-1357,2284,2411` |
| `tx_arb` 73 位/两级 | `rtl/tx_arb.v:9-25,29-34,42-52`；`board/wrapper_p4.v:2814,2865` |
| `u_txcdc(73)` | `board/wrapper_p4.v:2891-2901` |
| RX 76 位 bundle / 77 警告 | `board/wrapper_p4.v:921-943` |
| `rx_classify` FW=76 | `rtl/rx_classify.v:26-66,70,76-94` |
| `vlan_strip` 接口/重定时 | `rtl/vlan_strip.v:1-45,68-80` |
| UDP meta（无 dst_ip） | `rtl/udp_split.v:209-213`；`rtl/udp_rx.v:181,210-213` |
| UDP 单值过滤/常量 my_ip | `board/wrapper_p4.v:2470,2762` |
| `udp_tx_frame` 已有 `cfg_src_ip` | `rtl/udp_tx_frame.v:36-38` |
| 事件字 102 位 | `rtl/app_ctrl.v:28-35` |
| TCB 字段/upd_sel=7 保留 | `rtl/tcb.v:36-75,94-105,122-128` |
| HLS 单 IP | `hls/src/eth_types.h:119-123`；`layer_ip.cpp:76-83`；`layer_tcp.cpp:156,177,277,292`；`layer_arp.cpp:149,194,201`；`layer_icmp.cpp:142-143`；`layer_igmp.cpp:121-122`；`layer_udp.cpp:168-169` |
| HLS TX 可插 VLAN | `hls/src/eth_types.h:211-217`；`layer_mac.cpp:218`（唯一读取；无生产者） |
| 门覆盖 | `sim/p4gates/run_matrix_p4dfix.bat:184-241`；`sim/p5sim/run_tb_p5_wrapper.bat:44-55`；`_proj_10g/p7b_chain/sim/run_tb_p7b_chain.bat:39`；`sim/p7b_stagec_tx/run_tx_ovl_gate.bat` |
| 0x2A 基线 | `board/wrapper_p4.v:3394,4479`；`_proj_10g/notes/p9_build_0x2A_20261017/README_FOR_TL.md:39,47,50-51` |
| 设计/审查输入 | `_proj_10g/notes/p9_dual_sfp_p1_design_20261017/README_FOR_TL.md` §2.2/§4.4/§2.4；`p9_dual_sfp_plan_20261017/DESIGN.md` §0.5/§2-S2；`p9_review_dual_sfp_p1_design_20261018/FINDINGS.md` 高-3/高-4 |

*本件 = 只读架构分析。不含 PASS/FAIL 裁定；所有“更短/更低/更小”均为基于现读源码的证据性比较，最终裁定与实施授权在用户。*
