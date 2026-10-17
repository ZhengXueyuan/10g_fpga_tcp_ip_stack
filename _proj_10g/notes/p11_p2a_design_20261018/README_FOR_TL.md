# P11 / P2-甲 实施级设计 —— ch0 数据面接入 + A-1 出口身份 + rx_merge2 + 双板 IP + HLS 双 IP

- 日期：2026-10-18 · 角色 = **实施级设计（只读）**：未改任何 RTL/脚本/工具，未跑 xsim/Vivado，未碰板/对端/烧录，未写 git。
- 写入面：仅本目录（`_proj_10g/notes/p11_p2a_design_20261018/`）。
- 判据层口径：**本件不下 PASS/FAIL 裁定**（裁定权在用户/判据所有者）。「未观测到」≠「不存在」；「不支持」≠「证伪」。
- 状态词：**【已证·源码】【已证·构建】【已证·板级】【推断】【未判定】【未测】**。纸面数字一律标 **“纸面”**。
- 行号 = **2026-10-18 现读**（工作树 = P1 实施后的 0x2B 树）。行号会漂移，施工时以**符号名**为准；本件每条都带符号名。
- 方案身份：**S2 单栈**（不采用双栈，用户 2026-10-18 已裁）；出口身份 = **A-1（IP 即身份）**；P2-甲 = 数据面接入 + 双板 IP（**不含**乙镜像）。

---

## 0. 一页结论（先读这个）

| # | 结论 | 等级 |
|---|---|---|
| 1 | **基线更正**：派单写的“0.61% 基线”是 **0x2A**（WNS `+0.039`）。**现树 = P1 的 0x2B**：`WNS +0.048 / WHS +0.010 / 三类失败端点 0/0/0`，placed **80,024 LUT / 76,888 FF / 348 BRAM / 1 URAM**（原件 `p9_build_0x2B_20261018/README_FOR_TL.md:39-55,98-106`）。本设计一律以 **0x2B** 为基线；0.61% 按“历史代”读。 | 【已证·构建】 |
| 2 | **A-1 的核心映射必须钉死**：**ch1 = J8 = 现役口 = IP_A（192.168.100.2，保持不变）**；**ch0 = J7 = 新口 = IP_B（新 IP，建议 192.168.100.4）**。逻辑“端口位”定义为 **`1 = ch0/J7`**，即 `port = (CAM.dip == IP_B)`。这样**单口（只插 J8）时所有端口位恒 0 ⇒ 全部走现役 ch1 链**，不会因为双口位流把单口流量送到没插线的 J7。 | 【已证·源码】+本件裁定建议 |
| 3 | **端口位来源 = wrapper 16 槽 1 位数组**，与 `cam_cfg_wr_mux / cam_cfg_addr_mux / cam_cfg_dip_mux` **同拍并行写**（现读 `wrapper_p4.v:2183-2189`）；**`slow_cfg_adp` / `tcb` / `tcp_cam` 源码零改动**。读口按 `rb_id` 组合读。 | 【已证·源码】 |
| 4 | **TX 1 位选口方案 = ②“split/demux 前移 + 复制 arb 树”**（推荐）：`rtl/tx_arb.v` **源码零改动**（保持 73 位），既有单元/链级 TB（`tb/tb_tx_arb.v`、`tb/tb_p4_chain.v`）**零改动**；新增 `tx_demux2` + 每口一套两级 arb。代价 = +2 个 `tx_arb` 实例（纸面 ≈ +150 LUT/+20 FF）+ 3 个 demux（纸面 ≈ +200 LUT）。方案①（全链 74 位）会改 `tx_arb` 端口表并连带改上述两 TB，**单口回归面更大**，不推荐。另一条本轮新发现的候选（③“post-arb 源 IP 解析选口”）见 §2.7。 | 【已证·源码】+【推断】 |
| 5 | **A-1 的 TX 侧三项用途**（数据帧 IP 头源 IP、IP 校验和、TCP 伪头种子）在 `tcp_tx_frame.v` 的 **OVL 体 + 默认体**里都要改，且**重放（ring）必须用 bank 锁存的 local IP**；控制帧用 `ctrl_local_ip`。全部改动用 **`PER_CONN_SRC_IP` 参数（默认 0 = 原行为）** 门控 ⇒ 单口构建与所有旧 TB **功能逐位不变**。 | 【已证·源码】 |
| 6 | **RX 合并 = 新件 `rx_merge2`**：两路各一条 `fifo_async(76×256)`（ch0 新增、ch1 现役）→ `dp_clk` 单域 **帧级工作保持 round-robin**（非严格优先）→ `vlan_strip`。256 字 = 1.35 个最大帧，满足“每口最多等一帧”的 RR 上界；**per-port 丢帧计数用既有 MAC `stat_drop`（ch0=W82 / ch1=W4）**，满足 P3 判据里“≥2 帧 **或** per-port drop 计数”的后者。 | 【已证·源码】+【推断】 |
| 7 | **观测只加 3 个字**（全部落既有 p7bdp 束，**不新增 CDC 束**）：W83 = TX split→ch1 帧数、W84 = TX split→ch0 帧数、W85 = `rx_classify` 总帧数（fast+slow）。几何 **NW 83→86 / 未实现地址 `0x17C→0x188` / MIR 四字 `0x178..0x184`**。 | 【已证·源码】+【推断】 |
| 8 | **BID 建议：P2-甲 = `0x2C`；乙顺延 `0x2D`**（P1 = 0x2B，已构建）。构建宏 = 既有 8 宏 + **`DUAL_SFP_A=1`** 追加（`build_p7b_ku5p.tcl:286`，不覆盖）。 | 【推断】+登记 |
| 9 | **HLS 双 IP = 一个 canonical netlist**（`slowstack_prj` 重新综合，`-DBOARD_IP_DUAL=1`），单口功能等价靠 csim/xsim 门证；若要求“单口 HLS 网表逐位不变”，必须走**双输出目录**路线（§4.6，代价 = 多一份 HLS 产物与选择逻辑）。 | 【推断】 |
| 10 | **最大三个风险**：① 0x2B 的 WNS 只有 0.75%，A-1 的 `cam_rd_dip` 进校验和锥 + 快照 +288 FF 可能压穿；② `tcp_tx_frame` 的源 IP/校验和在**双体 × 数据/控制/重放 6 条路径**上任一漏改 ⇒ 对端**静默丢弃**、无握手判据会红；③ HLS 重新综合会改变**所有**引用 `slowstack_prj` 的构建/门的 HLS 网表（单口等价必须显式证明）。 | 【推断】 |

---

## 0.1 与派单/既有描述的核对（含不符，不迁就）

| # | 派单/既有描述 | 现读 | 判定 |
|---|---|---|---|
| 1 | “资源/时序（0.61% 基线）” | 0.61% = **0x2A**（`+0.039/6.400`）；现树 0x2B = **`+0.048/6.400` = 0.75%** | ⚠️ **基线代不同**，本设计用 0x2B |
| 2 | “P1 已完成（0x2B：ch0 RX tap/观测）” | `wrapper_p4.v:4824` `BUILD_ID_V = 32'h0000002B`；`:3522` `SNAP_NW_P6E=83`；`:995` `u_mac_rx_ch0` | ✅ 相符（树 = 0x2B；**板在 P1 轮收尾已回烧 0x2A**，见 `p9_board_p1_20261018/README_FOR_TL.md` §4） |
| 3 | 出口身份比较件说 CAM 写 mux 在 `wrapper_p4.v:2061-2067` | 现读 **`:2183-2189`**（`cam_cfg_wr_mux`/`addr`/`sip`/`dip`/`sport`/`dport`/`dmac`） | ⚠️ 行号漂移（P1 轮 +122 行量级），以现读为准 |
| 4 | 比较件说 `cam_rd_dip` 已连线但无消费者（`:1904,2088`） | 现读：声明 `:2026`、接 `tcp_cam.rd_dip` `:2210`；**仍无消费者** | ✅ 结论成立（行号现读） |
| 5 | 派单说“TX 1 位穿两级 `tx_arb`：①74 位 vs ②split 前移” | `tx_arb` 是**固定端口** 73 位（`rtl/tx_arb.v:9-25`，无参数）；存在**直接例化它的 TB**：`tb/tb_tx_arb.v:37`、`tb/tb_p4_chain.v:930` ⇒ ①必须改这两处 | ⚠️ ①的回归面比派单描述更大；本件推荐 ② |
| 6 | 派单说 `tcp_tx_frame` 有 `cfg_src_ip` 的 3 组用途 | 现读确认：`ip_csum_calc`（OVL `:392-405`/默认 `:2000-2011`）、数据 `csum_init_val`（`:817-819`/`:2022-2024`）、控制 `csum_init_ctrl`（`:874-876`）+ 头字（`:1440`/`:2481`）；`cfg_src_ip` 是**端口**（`:129`），wrapper 接常量（`:2453`） | ✅ 相符（“3 组”= 函数/init/头字，实际 4 个代码点 × 2 体） |
| 7 | 派单说 `MAX_TCP_CONN=3`（每口 1 条够、2 条不够） | `hls/src/layer_tcp.cpp:10-12` `#define MAX_TCP_CONN 3` | ✅ 相符 |
| 8 | P1 设计件 §1.3 曾写“乙位流（0x2C）留到 P3” | 本件把 **0x2C 分配给 P2-甲**，乙顺延 **0x2D** | ⚠️ BID 重排（登记） |
| 9 | 派单说“RX 字 76 位（历史 77 是算术错）” | `wrapper_p4.v:1044-1047` 逐字警告；`u_rxcdc` `:1054` 是 **WIDTH(76)** | ✅ 相符（A-1 不改 RX 宽度） |

---

## 1. 前提与边界

- 用户已裁：**S2 单栈**（放弃 2×10G 同时满速）；P3 判据 = **聚合 ≤ ~9.5 Gbps + 每口工作保持公平份额 + 丢帧/背压可读**（`p9_dual_sfp_p1_impl_20261018/DESIGN_v5.md` §8）。
- 甲 = 两端口都有**独立板 IP**；P2-甲 = 数据面接入 + 双板 IP，**不含乙镜像**（乙 = P3，位流顺延 0x2D）。
- P1 的观测（W76..W82）**全部保留**；P2 只新增 3 个字（§3.5）。
- 不改：`rtl/tcp_rx.v`、`rtl/vlan_strip.v`、`rtl/rx_classify.v`、`rtl/tcp_cam.v`、`rtl/tcb.v`、`rtl/tx_arb.v`、`rtl/udp_tx_frame.v`、`rtl/app_ctrl.v` 的功能主体（`app_ctrl` 只由 wrapper 传参）。
- 不碰：PCS/GT、参考钟、QPLL 复位、XDC 时钟组、QSPI、`D:\repo\perfv`。

---

## 2. A-1 实施级（含 P1 已留清单）

### 2.1 端口身份来源与物理映射（必须钉死）

**现读事实**：
- `slow_cfg_adp` 在 S_CAM 拍把 HLS 记录 `w2 = local_ip` 写入 `cam_cfg_dip`：`rtl/slow_cfg_adp.v:137-163`（`:148` 逐字 `cam_cfg_dip <= w2;`）。
- `tcp_rx` 用**帧的目的 IP** 组 CAM 键：`rtl/tcp_rx.v:213`、`:443-446`。
- `tcp_cam` 已有 `dip_r[0:15]` 与 `rd_dip` 读回：`rtl/tcp_cam.v:36-40`、`:71-75`。
- wrapper 的 `cam_rd_dip` 已连线：`board/wrapper_p4.v:2026`（声明）、`:2210`（接 CAM），**当前零消费者**。
- HLS 的 `w2` 现在是编译期常量 IP：`hls/src/layer_tcp.cpp:177`。

**裁定建议（本件口径）**：

| 物理口 | PCS 通道 | 板 IP | 逻辑端口位 | 说明 |
|---|---|---|---|---|
| **J8 = SFP B** | **ch1 = X0Y5** | **IP_A = 192.168.100.2**（**保持不变**） | **0** | 现役单口口；单口配置、对端 p1（192.168.100.1）全部不动 |
| **J7 = SFP A** | **ch0 = X0Y4** | **IP_B = 192.168.100.4**（建议） | **1** | 新口；对端 p0（建议 192.168.100.101） |

> ⚠️ 这条映射是本设计**最重要的单点决定**：若反过来把 IP_A 绑到 ch0，则“只插 J8 的单口”在双口位流里会把帧发到 J7 ⇒ 立刻可见的假故障。本件按“IP_A=ch1=现役”设计。
>
> 命名歧义提醒：`SFP2_MODE_A` 里的 **A = 甲（模式）**，与 **SFP A = J7 = ch0** 不是一回事；本件在正文中一律写“甲/乙”与“ch0/ch1”。

### 2.2 wrapper 16 槽端口位数组（推荐方案）

**改动点（`board/wrapper_p4.v`，现读行号）**：

- 在 `cam_cfg_*_mux` 声明旁（`:2183-2189` 之后）新增：

```verilog
    // ---- P11 P2-甲: 16-slot port array (A-1). 1 = ch0/J7 (IP_B), 0 = ch1/J8 (IP_A).
    //   Written on the SAME cycle / SAME address / SAME source as the CAM write mux
    //   (scfg S_CAM 或 orphan 清): 与 tcp_cam 的写法逐位同源 ⇒ 不变式
    //     port_arr[s] == (CAM.dip[s] == IP_B) 在每次写后成立 (DEL/孤儿清写 dip=0 ⇒ port=0).
    localparam [31:0] IP_A_5 = 32'hC0A86402;   // 192.168.100.2 = ch1/J8 (现役)
    localparam [31:0] IP_B_5 = 32'hC0A86404;   // 192.168.100.4 = ch0/J7 (新)
    reg [15:0] cam_port_arr;
    always @(posedge dp_clk or negedge dp_rst_n) begin
        if (!dp_rst_n) cam_port_arr <= 16'd0;
        else if (cam_cfg_wr_mux) cam_port_arr[cam_cfg_addr_mux] <= (cam_cfg_dip_mux == IP_B_5);
    end
    wire cam_rd_port = cam_port_arr[rb_id];   // 与 cam_rd_dip 同拍同源 (cam_rd_id = rb_id)
```

- 零改 `slow_cfg_adp` / `tcb` / `tcp_cam`。
- 读口：`cam_rd_port` 送入 `tcp_tx_frame`（§2.3）；UDP app 的端口位由 `udp_tx_cfg` 自己按 `peer_my_ip` 产生（§2.4）；慢路径由 `slow_tx_adp` 提取（§2.5）。
- 成本：**+16 FF + 1 位 16:1 读 mux**（纸面）。
- 不变式（门必须断言）：**同拍同址同源**；DEL/孤儿清后 `port_arr[s]==0`；`cam_rd_port` 与 `cam_rd_dip` 在同一 `rb_id` 下一致。

**为什么不用 TCB 1 位**：`tcb.v:94-105` 的 `upd_sel` 是 3 位且 **`3'd7` 显式保留拒写**（`:103`），要加字段必须动接口（占 sel=7 / 独立口 / 扩 wscale 位宽），且 TCB 与 CAM 会多一份冗余状态。wrapper 数组不动任何既有模块接口，是零耦合方案。
**为什么不用“每帧比 `cam_rd_dip`”**：省 16 FF，但把 32 位比较放在帧启动/CSUM init 锥上（纸面 +2 级 LUT），在 0.75% 余量下不划算；数组方案把比较放在**慢速配置写**拍（每连接一次）。

### 2.3 `tcp_tx_frame` 的 per-connection 源 IP / 端口 / 校验和

**目标**：同一 `tcp_tx_frame` 实例按 `conn_id`（= `rb_id`）发送时，帧头源 IP、IP 校验和、TCP 伪头种子都必须用**该连接的本地 IP**（`CAM.dip` / 端口数组），而不是全局常量 `cfg_src_ip`。

**新增端口/参数（`rtl/tcp_tx_frame.v`，现读端口表 `:122-129` 一带）**：

| 端口/参数 | 方向/默认 | 用途 |
|---|---|---|
| `input [31:0] cam_rd_dip` | in | 该 bank/ctrl 连接的本地 IP（`tcp_cam.rd_dip`，wrapper 已连线） |
| `input cam_rd_port` | in | 该连接的端口位（§2.2 数组；1 = ch0） |
| `output o_port` | out | 本帧出口端口位（帧内稳定；送 TX demux） |
| `parameter PER_CONN_SRC_IP = 1'b0` | 默认 0 | **0 = 原行为**（全部用 `cfg_src_ip`、`o_port=0`）；wrapper 在双口构建传 **1** |

**逐用途改动表（OVL 体 = 板上生效体；默认体 = 非 OVL 构建/部分门）**：

| # | 用途 | 现读位置（OVL） | 现读位置（默认体） | 改法 |
|---|---|---|---|---|
| 1 | IP 校验和函数 | `ip_csum_calc` `:392-405`（`:400-401` 用 `cfg_src_ip`） | `:2000-2011`（`:2008-2009`） | 函数加 `input [31:0] sip`；两体各改一处定义 |
| 2 | 数据帧 csum init（TCP 伪头种子） | `csum_init_val` `:817-819`；`csum_init = start_data \|\| ring_start` `:820` | `:2022-2024`；`csum_init` `:2025` | `PER_CONN ? cam_rd_dip : cfg_src_ip`。⚠️ 这一拍 bank 尚未装载（见下“锁存拍”），**必须组合读 `cam_rd_dip`** |
| 3 | 控制帧 csum init（TCP 伪头种子） | `csum_init_ctrl` `:874-876` | 同段（控制帧走 `csum_init_val`） | 用已寄存的 `ctrl_lip`（OVL）/ `lip_r`（默认） |
| 4 | 控制帧 IP 校验和 | `ctrl_ipcsum_now = ip_csum_calc(..., ctrl_dip)` `:900-901` | `ip_csum_r <= ip_csum_calc(total_len_r, id_cap, dip_r)` `:2463` | 已寄存的 `ctrl_lip` / `lip_r` 作 `sip` 入参 |
| 5 | 数据帧 IP 校验和（fin 拍） | `f_ipcsum[rx_bank] <= ip_csum_calc(..., f_dip[rx_bank])` `:1396-1397` | 同 #4 | bank 的 `f_lip[rx_bank]` / `lip_r` |
| 6 | 头字源 IP | `3'd3: m_axis_tdata <= {h_ipcsum, cfg_src_ip, h_dip[31:16]};` `:1440` | `:2481` | `h_lip`（= `h_ctrl ? ctrl_lip : f_lip[tx_bank]`）/ `lip_r` |

**锁存点（每个都要加）**：

| 锁存 | 现读位置 | 加什么 |
|---|---|---|
| OVL `ring_start` bank 装载 | `:1199-1208` | `f_lip[rx_bank] <= cam_rd_dip; f_port[rx_bank] <= cam_rd_port;` |
| OVL `start_ack` 控制槽装载 | `:1314-1344`（`ctrl_dip <= cam_rd_sip` `:1324`） | `ctrl_lip <= cam_rd_dip; ctrl_port <= cam_rd_port;` |
| OVL 活帧首拍 bank 装载 | `:1346-1361`（`recv_first` 支 `:1347-1361`） | 同 ring 装载 |
| 默认体 `start_ack \|\| start_data` | `:2392-2415`（`dip_r <= cam_rd_sip` `:2411`） | `lip_r <= cam_rd_dip; port_r <= cam_rd_port;` |
| 默认体 `ring_start` | `:2272-2288`（`dip_r <= cam_rd_sip` `:2284`） | 同上 |

**时序论证（为什么不变/为什么安全）**：
- `start_data` / `ring_start` 那一拍，`rb_id = start_id / retx_id_r`（`:663`/`:1832` 的 mux），`cam_rd_id = rb_id`（`:666`/`:1834`）；`tcp_cam.rd_dip` 是组合读（`tcp_cam.v:71-75`）⇒ **同一拍 `cam_rd_dip` 就是该连接的本地 IP**。`csum_init_val` 与 `checksum16.init` 同拍 ⇒ 只能组合读。
- `f_lip`/`ctrl_lip` 在同一沿装载；后面 `RX_FIN`/`S_WAIT`/`S_HDR` 读到的都是**已寄存值** ⇒ 与 init 拍取的是同一份（同源同拍）。
- 重放：`ring_start` 重新从 `cam_rd_dip` 装 bank；同一连接在会话期间 CAM 不变 ⇒ 重放源 IP 与首帧一致。
- 控制帧：R-1 重定时后 `ctrl_ipcsum/tcpcsum` 在 **start_ack+1** 装载（`:582` 段注释），`ctrl_lip` 在 start_ack 沿已稳定 ⇒ 时序余量不变（仍 ≥3/5 拍）。
- **校验和锥**：`csum_init_val` 的加数个数**不变**（原来就是 `cfg_src_ip` 两半字 + `cam_rd_sip` 两半字；现在把前两半字换成 `cam_rd_dip` 两半字）。`cam_rd_sip` 本来就是 CAM 16:1 组合读 ⇒ 加法树级数不变，只是 CAM 读 mux 的扇出 +32 位。【推断：+0 级】

**收益/代价**：+99 FF（OVL：`f_lip` 2×32 + `f_port` 2 + `ctrl_lip` 32 + `ctrl_port` 1；默认体 33），纸面 +50-100 LUT。

**单口兼容（关键）**：
- `PER_CONN_SRC_IP=0` 时所有选择器都选 `cfg_src_ip` / `o_port=0`；Vivado 常量折叠 ⇒ **单口网表行为与 0x2B 逐位相同**（源文本新增的是被折叠的 mux）。旧 TB 即使不接 `cam_rd_dip`/`cam_rd_port`（未接输入为 Z，但未被选中）也不会改变输出。
- wrapper 只在 `DUAL_SFP_A` 构建传 `PER_CONN_SRC_IP=1`。
- 仍建议实施轮把活跃 TB 的这两个新输入显式接常量（`32'h0` / `1'b0`），消除 xelab 的 “port remains unconnected” 噪声；**冻结副本**（`sim/.../frozen/`）一律不碰。

### 2.4 UDP app 的源 IP / 端口（`udp_tx_cfg` + `udp_rx` + `udp_split`）

**现读事实**：
- `udp_tx_cfg` 的 peer 表只有 `{peer_mac, peer_ip}`（`rtl/udp_tx_cfg.v:66-77`）；`cfg_my_ip` 是**静态端口**（`:75`，wrapper 接常量 `wrapper_p4.v:2884`）；`o_src_ip` 在空闲窗口刷新（`:165-173`）。
- `udp_rx.ip_match` 只比一个 `cfg_dst_ip`（`rtl/udp_rx.v:180-181`）；meta 只有 `src_mac/src_ip/src_port/len`（`:210-213`）。
- `udp_split` 透传 meta（`rtl/udp_split.v:745-749`），`cfg_dst_ip` 是输入（`:215`）并转给 `udp_rx`（`:443-446`）。
- `udp_tx_frame` **已有 `cfg_src_ip` 输入**（`rtl/udp_tx_frame.v:36-38`），本身不必改。

**改动**：

| 文件 | 现读位置 | 改动 |
|---|---|---|
| `rtl/udp_rx.v` | `:180-181`（`ip_match`）、`:202-213`（meta 输出） | 加 `input [31:0] cfg_dst_ip1`、`input cfg_dual`；`ip_match = cfg_multi_en&&multicast \|\| dst==cfg_dst_ip \|\| (cfg_dual && dst==cfg_dst_ip1)`；新增 `meta_dst_ip` 输出（在 w4 匹配拍锁存 `{w3_r[15:0], s_axis_tdata[63:48]}`） |
| `rtl/udp_split.v` | `:209-213`（meta 输出）、`:215`（cfg）、`:745-749`（assign） | 加 `meta_dst_ip` 透传、`cfg_dst_ip1`/`cfg_dual` 透传 |
| `rtl/udp_tx_cfg.v` | `:66-77`（peer 写口）、`:124-127`（`cfg_sync`）、`:142-180`（锁存） | 加 `input [31:0] peer_my_ip`、`output o_port`、`parameter PER_CONN_SRC_IP=0`、`parameter [31:0] IP_B=32'hFFFFFFFF`（默认永不匹配 ⇒ 单口 `o_port=0`）；表中存 `peer_my_ip_r`；`o_src_ip <= PER_CONN ? peer_my_ip_r : cfg_my_ip`；`o_port <= (peer_my_ip_r == IP_B)`（同空闲刷新块，+1 FF）；`cfg_sync` 加对应项 |
| `board/wrapper_p4.v` | `:2880-2884`（peer 写口 + `cfg_my_ip`）、`:2592`（`cfg_dst_ip`） | `peer_my_ip(udp_meta_dst_ip)`、`cfg_dst_ip1(IP_B_5)`、`cfg_dual(DUAL_SFP_A_DEF)`、`PER_CONN_SRC_IP` 传参 |
| `rtl/udp_tx_frame.v` | `:36-38` | **零改动**（端口位由 `udp_tx_cfg` 输出，帧内冻结） |

**单 peer 表限制（既有语义，不是本设计引入）**：两口同时活跃时“最后学习者赢”；P2 的 UDP app 测试必须**逐口做**或接受翻转。登记。

### 2.5 慢路径（HLS）出口端口：`slow_tx_adp` 源 IP 提取

**现读事实**：HLS TX 是 16 位字节流（`hls_tx_tdata[8]=TLAST`，`slow_tx_adp.v:17-19`），剥前导/4 字节 FCS 后整帧进 `frame_fifo`（`:80-88`），播放器输出 73 位字流（`:207-224`）。HLS 帧**无 VLAN**（`hls/src/eth_types.h:211-217` 的 `insert_vlan` 全仓无生产者；`hls/src/layer_mac.cpp:218` 是唯一读点）⇒ 源 IP 偏移固定。

**改动（`rtl/slow_tx_adp.v`）**：
- 在字节 FSM 的 `T_DATA` 消费路径（`:136-198`）加一个内容字节索引 `bpos`（`T_PRE→T_DATA` 清 0，每消费一字节 +1，`in_last` 帧末清）与 40 位移位寄存器 `src_sr <= {src_sr[31:0], in_b}`。
- 在 `bpos==13` 锁 `etype <= {etype_sr[7:0], in_b}`（字节 12..13）。
- 在 `bpos==29 && etype==0x0800` 锁 `src_ip_lat <= {src_sr[23:0], in_b}`（IPv4 源 IP = 帧字节 26..29）。
- 在 `bpos==31 && etype==0x0806` 锁 `src_ip_lat <= {src_sr[23:0], in_b}`（ARP SPA = 帧字节 28..31）。
- 每帧开始清 `ip_seen`；提交拍（`commit_pulse`）把 `(ip_seen && src_ip_lat==IP_B)` 压入一个 **1 位 × 16 的按帧 side FIFO**（深度 16 ≥ `frame_fifo` 512 字能容纳的最大帧数；另加 `side_ovf` 自检计数 —— 非 0 = 端口映射失效）；`start_play` 拍弹出到 `play_port`；输出 `o_port = PER_PORT ? play_port : 1'b0`（`parameter PER_PORT=0`、`parameter [31:0] IP_B=32'hFFFFFFFF`；默认永不匹配 ⇒ 单口 `o_port=0`）。
  - 为什么不在 `frame_fifo` 里加 1 位：字节 FSM 是**边收边写**，端口要等字节 29/31 才知道，前 4 个字已经写进 FIFO ⇒ 无法给早写的字打标；side FIFO 在**整帧提交后**才 push（与 `committed`/`start_play` 同一对事件），对齐天然正确。
- 为什么用 side FIFO 而不是把 `frame_fifo` 加宽 1 位：加宽会改变 512×73 的 FIFO 形状（单口构建也变），side FIFO 只在 `DUAL_SFP_A` 下存在，**单口源码/网表不变**。
- 短帧/未识别 ethertype：`ip_seen=0` ⇒ `o_port=0`（默认走 ch1/现役口，安全）。
- 端口位在播放期间稳定（由 side FIFO 对齐 `commit_pulse`/`start_play`，与 `committed` 同一对事件）。
- 纸面：+40 FF / +10-30 LUT；不变式写死 **“HLS TX 不加 VLAN”**（将来启用 VLAN 必须同步改偏移，否则静默选错口）。

### 2.6 TX 选口：方案选择（① vs ②），推荐 **②**

| 维度 | ① 全链 74 位（穿两级 arb） | ② split/demux 前移 + 复制 arb 树（**推荐**） |
|---|---|---|
| `rtl/tx_arb.v` | 端口表 73→74（全部实例） | **源码零改动**（保持 73） |
| 直接例化 `tx_arb` 的 TB | `tb/tb_tx_arb.v:37`、`tb/tb_p4_chain.v:930` **必须改** | **零改动** |
| wrapper | 两级 arb 加 1 位 + 新 `tx_split2` | 3 个 demux + **每口一套两级 arb（共 4 个 `tx_arb`）** + 每口 FIFO/MAC |
| 跨口 HOL | 存在：单流分裂，前一口 FIFO 满会阻塞后一口帧（本设计下**边界有界**：每口 MAC 排水 10G ≥ 单栈聚合 ≤9.5G，且 FIFO 256 字；仍登记） | **结构性消除**：每口独立 arb/FIFO |
| 面积（纸面） | +1 位 ×2 arb ≈ +10 LUT | +2 arb ≈ +150 LUT / +20 FF；3 demux ≈ +200 LUT |
| 单口回归 | 网表层面多 1 根常量 0 输入（功能同，但模块端口变） | **单口路径逐字保留**（`else` 支原样），新逻辑全在 `DUAL_SFP_A` 内 |
| 风险 | 改动面更大、跨口 HOL | 每口优先级变成“口内 TCP>UDP>HLS”（全局 TCP 绝对优先不再跨口，语义可接受） |

**②的逐文件改动面**：
- 新件 `rtl/tx_demux2.v`（纸面 ~40 行）：`s_tdata/tkeep/tlast/tvalid/tready + s_port` → 两路，`d0_tvalid = tvalid && !s_port`、`d1_tvalid = tvalid && s_port`，`s_tready = s_port ? d1_tready : d0_tready`；数据/keep/last 广播。**不变式：帧内 `s_port` 稳定**（三个生产者各自保证）。
- `board/wrapper_p4.v`：`u_tx_udp_arb`/`u_tx_arb` 两个现有实例保留为 **port0（ch1）** 支；新增 **port1（ch0）** 的两个 `tx_arb` 实例 + 3 个 demux；两个 `fifo_async(73×256)`（`u_txcdc_p0/p1`）+ 两个 `mac_tx_10g`。默认（非 `DUAL_SFP_A`）支 = 现有 `u_tx_udp_arb→u_tx_arb→u_txcdc→u_mac_tx` **原样**。
- `rtl/tcp_tx_frame.v`：`o_port`（§2.3）。
- `rtl/udp_tx_cfg.v`：`o_port`（§2.4）。
- `rtl/slow_tx_adp.v`：`o_port`（§2.5）。
- `rtl/tx_arb.v`：**不改**。

**方案③（本轮新发现，登记待裁）**：单流 arb 之后、FIFO 之前放一个 **4 字前瞻路由器**，从帧头的 IPv4 源 IP/ARP SPA 解析出口（“出口 = 帧头源 IP 对应的口”）。优点：**三个生产者零端口改动**、`tx_arb` 零改动、单口回归最小；缺点：新增“TX 帧不带 VLAN + 头偏移固定”的解析不变式，且需要 4 字管线滞后（若只做单缓冲会每帧 +4 拍 = 纸面 ~2% 帧周期；需要 word-lag/双缓冲才无气泡）。本件**不推荐作为第一版**，但若用户想把生产者改动降到零，它是候选。

### 2.7 单口/双口兼容（开关、参数、回归）

| 项 | 单口（默认/无 `DUAL_SFP_A`） | 双口（`DUAL_SFP_A=1`） |
|---|---|---|
| `cam_port_arr` | 存在但输出未被使用（`PER_CONN_SRC_IP=0` ⇒ 折叠） | 写/读生效 |
| `tcp_tx_frame` | `PER_CONN_SRC_IP=0` ⇒ 全用 `cfg_src_ip`、`o_port=0` | 用 `cam_rd_dip`/`cam_rd_port` |
| `udp_tx_cfg` | `PER_CONN_SRC_IP=0` ⇒ `cfg_my_ip`、`o_port=0` | 用 `peer_my_ip` |
| `slow_tx_adp` | 提取逻辑/ side FIFO 不例化，`o_port=0` | 生效 |
| `tx_arb` 链 | 现役 `u_tx_udp_arb→u_tx_arb→u_txcdc→u_mac_tx` **原样** | 每口一套 |
| `rx_merge2` | 不例化；`rx_*` 仍由 `u_rxcdc` 直连 | 例化；两路 FIFO → merge |
| ch0 TX | 常量 IDLE（P1 不动） | 第二 `mac_tx_10g` |

**硬门（elaboration 失败，照 `g_orph_zw_guard` 手法 `wrapper_p4.v:226-241`）**：
- `DUAL_SFP_A ∧ ¬P7B_10G`；
- `DUAL_SFP_A ∧ SFP2_MODE_B`（甲/乙是两个位流）；
- `DUAL_SFP_A ∧ ¬DP_156MHZ`（双口必须有独立 dp 域；单域构建 `dp_clk=gmii_clk`，见 `:816`，ch0 的恢复钟会被错误别名）；
- `DUAL_SFP_A ∧ ¬APP_MODE`（双口 TX 路径按 APP_MODE 的三生产者集合设计；若将来要非 APP 双口，另开）。

**回归**：默认构建 = 矩阵 22 门全跑（新增的 dual 门只在 `DUAL_SFP_A` 下编，不污染默认）；单口运行时回归 = 双口位流只插 J8 与 0x2B 同会话 A/B。

---

## 3. ch0 数据面接入

### 3.1 时钟 / 复位 / TX_DIS

| 项 | 现读锚点 | 设计 |
|---|---|---|
| ch0 RX 域 | `gmii_clk_0 = rx_clk_out_0`（`:352` 声明、`:753` assign；`:390` PCS 端口） | 不变 |
| ch0 TX 域 | `tx_fe_clk_0 = tx_mii_clk_0`（`:353`、`:754` assign） | 不变；P2 首次有消费者 |
| ch0 RX MAC 复位 | `rx_mac_rst_n_0 = rstn_rx_sr_0[2] & ~pcs_user_rx_reset_0`（`:693-700`） | 不变 |
| ch0 TX MAC 复位 | **不存在**（P1 无 ch0 TX） | **新增** `(* ASYNC_REG *) reg [2:0] rstn_tx_sr_0;`（`tx_fe_clk_0` 域）+ `tx_mac_rst_n_0 = rstn_tx_sr_0[2] & ~pcs_user_tx_reset_0`（照 ch1 `:683-688`） |
| ch0 TX 常量 IDLE | `p7b_ch0_idle_d/c`（`:639-646`，`dont_touch`） | `DUAL_SFP_A` 下删除这两根 assign，改由 `u_mac_tx_ch0` 驱动 `tx_mii_d_0/c_0`；非 dual 构建保留原样（**ch0 端口必须有真实负载**，`:626-638` 的 driverless-net 历史教训） |
| TX_DIS | `sfp1_tx_dis = pcie_scratch[0]`（`:4814`）、`sfp2_tx_dis = pcie_scratch[1]`（`:4815`） | **零改动**；bit0 = J7/ch0，bit1 = J8/ch1（P1 S-3 已板级证 bit0→对端 p0 carrier） |
| mac_tx_10g 空闲输出 | `S_IDLE` 输出 `64'h0707…/c=0xFF`（`_proj_10g/p7b_mac/rtl/mac_tx_10g.v:317-330` 的 mux default） | 与 P1 常量 IDLE 相同 ⇒ 换 MAC 后链路空闲行为不变 |

### 3.2 ch0 RX：tap → FIFO → `rx_merge2`

**现读**：P1 的 ch0 段在 `wrapper_p4.v:949-1012`：`ch0_rx_tready = 1'b1`（`:973`）的“真消费者”sink + 好帧/字节累加（`:978-993`）+ `u_mac_rx_ch0`（`:995-1012`）。

**改动**：

1. **升级 sink 为真业务消费者**：
   - `ch0_rx_tready = ~ch0_fifo_full`（写侧 FE 本地，同 u_rxcdc 的做法）。
   - 新增 `fifo_async #(.WIDTH(76), .DEPTH(256), .FWFT(1), .AW(8)) u_rxcdc_ch0`：
     `wr_clk=gmii_clk_0, wr_rst_n=reset_n, wr_en=ch0_rx_tvalid, din={ch0_rx_tdata, ch0_rx_tkeep, ch0_rx_tuser, ch0_rx_tlast, ch0_rx_tcrs, ch0_rx_terr}`；
     `rd_clk=dp_clk, rd_rst_n=reset_n, rd_en=merge_p1_tready, dout={ch0_rx_dp...}, empty=ch0_rx_empty, ovf_cnt=ch0_rxcdc_ovf`。
   - **P1 的 W79/W80 计数保持原口径**（在 tap 上按 `tvalid && tready` 数；tready 现在是 `~full`）⇒ W79 变成“被 merge 输入接收的好帧数”；FIFO 满导致的丢帧由 MAC `stat_drop`（W82）计数。W81/W82 不变（`:1008-1011` 已连）。
2. **新增 `rtl/rx_merge2.v`（76 位、无标签、`dp_clk` 单域）**：

```
module rx_merge2 (
  clk, rst_n,
  p0_* (76b AXIS + tvalid/tready)   // p0 = ch1 (现役)
  p1_* (76b AXIS + tvalid/tready)   // p1 = ch0 (新)
  m_*  (76b AXIS + tvalid/tready)
  // 可选观测（本设计不默认进快照）: stat_frames0/1/out
);
```
   - **FSM**：`busy`（帧内锁）、`sel`（本帧口）、`rr`（上一次服务的口）。
   - 空闲拍仲裁：优先 `~rr` 口；若它无 `tvalid`，**工作保持**地选另一口；有 valid 则 `sel<=选中口; busy<=1`。
   - 忙拍：`m_tvalid/busy = busy && p_sel_tvalid`；`p_sel_tready = m_tready`；非选中口 `tready=0`。
   - 帧末（`m_tvalid && m_tready && m_tlast`）：`busy<=0; rr<=sel` ⇒ **每帧末尾 1 拍重仲裁气泡**（与 `tx_arb` 同构）。
   - **帧级互斥**：只在 `!busy` 时选口、只在 TLAST 释放 ⇒ 一帧的字连续、不交织。
   - **公平性**：`rr` 只在该帧被服务后翻转 ⇒ 两口同时有帧时**逐帧交替**；单口有帧时满速（工作保持）。P2 先用 **RR**（判据只要求“每口公平份额”）；若 P3 要求**按字节**公平，可在同一 FSM 上加每口 deficit 计数器升级为 **DRR**（不改帧级互斥结构）。
   - **参数**：`parameter STRICT = 1'b0`（0=RR；1=严格优先 p1，**仅用于单元门的负对照**，板上不置 1）。
3. **接入点**：`u_rxcdc`（ch1）与 `u_rxcdc_ch0` 的 dout 进 merge；merge 输出替换现 `rx_tdata/rx_tkeep/...`（`wrapper_p4.v:1054-1081` 的 DP_156MHZ 支）。**两处握手必须同步改**（否则 FIFO 读口被双采/不弹）：① `u_rxcdc` 的 `rd_en` 由 `rx_tvalid && rx_tready`（`:1058`）改为 merge 的 `p0_tready`；② `assign rx_tvalid = ~rx_fifo_empty`（`:1067`）改为 merge 的 `m_tvalid`（FWFT 的 `dout` 仍是 merge 内部选中口的头字）。非 dual 构建保留原式。`vlan_strip`（`:1097`）/`rx_classify`（`:1120`）**零改动**（A-1 不需要 77 位，见 §0.1 #9）。
4. **FIFO 深度与丢帧**：每口 256 字 = **1.35 个最大帧（1518B=190 字）**。RR 的单口最大等待 = 1 个帧；等待期间另一口最多再来 1 帧 ⇒ 病态下第 2 帧可能溢出；**MAC 整帧丢 + W82/W4 计数**（`mac_rx_10g` 的 push 空间门 `stat_drop`，见 `_proj_10g/p7b_mac/rtl/mac_rx_10g.v:326-327,405-414`）。这满足 DESIGN_v5 §8 的“≥2 帧 **或** per-port drop 计数”的**后者**；两根口灌满时**两口 drop 计数都应前进**（公平份额 ≈ 各 50%）。
   - **备选（backstop）**：深度 512（2.7 帧）⇒ 每 FIFO 纸面 +~300 LUTRAM；若板上看到单口被无谓丢帧再加。
5. **守恒律（板级）**：`ΔW85（classify 总帧）≈ ΔW79（ch0 好帧）+ ΔW0（ch1 MAC 帧）− 坏帧/丢帧`。⚠️ 这是**设计不变式级**的核对（不是独立物理量）；真正的独立仪器是**对端两口各自的 NIC 计数**（见 §5.4）。
6. **复位**：两 FIFO 两侧都接 `reset_n`（与 `u_rxcdc` 同规则，`:1052` 注释）；merge 接 `dp_rst_n`。
7. **可观测性边界（A-1 的固有代价）**：RX 合并流**不携带端口标签**（身份 = 目的 IP），因此板内**无法回答“这一帧从哪个物理口进来”**；诊断只能靠对端每口 NIC 计数 / 物理拔插 / TX_DIS 单口隔离。登记，不当缺陷。

### 3.3 ch0 TX：第二 `mac_tx_10g` + 每口 arb/FIFO

- 新增 `u_mac_tx_ch0`（`_proj_10g/p7b_mac/rtl/mac_tx_10g.v`），`clk=tx_fe_clk_0`、`rst_n=tx_mac_rst_n_0`、输出 `tx_mii_d_0/c_0`；计数输出按需接（见 §3.5）。
- 新增 `fifo_async #(.WIDTH(73), .DEPTH(256), .FWFT(1), .AW(8)) u_txcdc_ch0`：`wr_clk=dp_clk`（merge/arb 侧）、`rd_clk=tx_fe_clk_0`。
- 现役 `u_txcdc`（`:3013`）保留为 **port0（ch1）** 的 FIFO，`rd_clk=tx_fe_clk`（= tx_mii_clk_1）。
- ⚠️ **命名口径**：方案②下**不存在单点 `tx_split2`** —— “split”由 **3 个 `tx_demux2`（每个生产者一个）+ 每口一套 arb** 等价实现。若用户坚持“单点 split 模块”（即派单字面的 `tx_split2`），那对应方案①（74 位穿 arb 后单点分流），不在本推荐内（§2.6）。
- **每口两级 arb**：port0 = 现役 `u_tx_udp_arb`（`:2936`）+ `u_tx_arb`（`:2987`）；port1 = 新增两个 `tx_arb` 实例。三个生产者（TCP `tx_*`、UDP `utx2_*`、HLS `stx_*`）各过一个 `tx_demux2`（§2.6）。
- **W28/W45 的语义泛化**（都在 dp 写域，合法）：双口下 `W28 = max(occ_max0, occ_max1)`、`W45 = ovf0 + ovf1`；单口 = 原值。W26/W27（RX FIFO）**保持 ch1 口径**（它们在 ch1 的 FE 域；ch0 FIFO 在 ch0 RX 域，跨域求和不可做）⇒ ch0 的背压用 W82/W79 看，文档写清。
- `m_tx_*` / `txsrc_*` / `tx_fifo_*` 的线名在 dual 支拆成 `_p0/_p1` 两套；`u_mac_tx`（`:3039-3061`）保留为 ch1。

### 3.4 与 P1 观测共存

- W76（ch0 PCS 状态）/W77（事件）/W78（LOS+模式）**不变**（`:4606-4608` 装配）。
- W79/W80/W81/W82 **不变**（ch0 束 `:4602-4605`），口径微调见 §3.2-1。
- ch0 TX 的 MAC 计数器**默认不进快照**（要新开一个 `tx_mii_clk_0` 的 `snap_cdc` 束 = +96 FF/字 + 第 7 束 FSM 改动，风险大）；A-1 的板侧出口证据用 **TX split 计数（dp 域，§3.5）**，实际到达用**对端 NIC p0**。若后续需要“MAC 真发了多少”，再按 backstop 加束。

### 3.5 观测面（P2 新增 3 字）

| 新字 | 内容 | 位域/域 | 源（现读锚点） |
|---|---|---|---|
| **W83** | TX port0（ch1）帧数 | 32 位自由回卷 / `dp_clk` | **每口 arb 输出**上 `m_axis_tlast && tvalid && tready` 的计数（= 整帧交给 port0 FIFO） |
| **W84** | TX port1（ch0）帧数 | 同上 | 同 W83，port1 |
| **W85** | `rx_classify` **总帧数**（fast+slow） | 同上 | `cls_stat_fast + cls_stat_slow`（`wrapper_p4.v:898` 声明、`:1147-1148` 连接；`rx_classify.v:188-191` 计数）。两个源都是 dp 域寄存器 ⇒ 组合和在 `clk_b=dp_clk` 沿之外不变，满足 `snap_cdc.din_b` 前提 |

- 地址（NW=86）：W83 `0x16C` / W84 `0x170` / W85 `0x174`；MIR 四字 `0x178/0x17C/0x180/0x184`；**未实现地址 `0x188`**（= `0x20+4×86+16`）。
- 装配：`snap_dout_all`（`:4601`）顶部加 3 项；`SNAP_P7BDP_NW 39→42`（`:3543`）；`SNAP_NW_P6E 83→86`（`:3522`）；p7bdp 槽 39/40/41（`:4406-4454` 的显式 assign 末尾加 3 行）；`.SNAP_NW(SNAP_NW_P6E)`（`:5305`）自动跟随。
- 预算复算：`{snap_idx,5'b0}` 最大 = (86−1)<<5 = 2720 < 4096 ⇒ `snap_base[11:0]` 不动；`snap_idx = r_word[6:0]-8` 最大 85 < 119 ✓。
- **成本**：3 字 × 96 FF ≈ **+288 FF**（`hold_b`/`dout_a`/`snap_words_r` 三份），全落既有 p7bdp 束 ⇒ **不新增 CDC 束、不改快照 FSM**。这是本设计刻意压小的时序风险；但 0x28 的先例是“快照阵列异步复位族”当过全局 WNS 宿主 ⇒ 构建轮必须定向观察（§5.3）。
- **backstop（几何）**：B1 删 W85 ⇒ NW 85 / `0x184`；B2 再删 W83/W84 ⇒ NW 83 / `0x17C`（**BID 仍 0x2C**，读侧该阶段变 BID-only）；不删 P1 的 7 字。

---

## 4. 双板 IP / HLS

### 4.1 常量与助手（`hls/src/eth_types.h`）

现读：`BOARD_IP_BYTE0..3`（`:119-123`）、`BOARD_MAC_BYTE0..5`（`:111-117`）。**没有**单一 `BOARD_IP` 宏（全仓 grep 确认；引用点都是 4 个 BYTE 宏）。

建议新增（保持单口默认）：

```c
#ifndef BOARD_IP_DUAL
#define BOARD_IP_DUAL 0          // 0 = 单口（默认；单口构建行为不变）
#endif
#ifndef BOARD_IP1_BYTE0
#define BOARD_IP1_BYTE0 192
#define BOARD_IP1_BYTE1 168
#define BOARD_IP1_BYTE2 100
#define BOARD_IP1_BYTE3 4        // 192.168.100.4 = ch0/J7
#endif
static inline uint32_t board_ip0_u32() { return (BOARD_IP_BYTE0<<24)|...; }
static inline uint32_t board_ip1_u32() { return (BOARD_IP1_BYTE0<<24)|...; }
// 目的 IP 匹配：双口 = 两个 IP；单口 = 仅 IP0（编译期折叠 ⇒ 与今天同）
static inline bool board_ip_match(uint32_t dst) { ... }
// 回包源 IP：双口 = 命中的 IP；**广播 0xFFFFFFFF 映射回 IP0**（保持今天的单口行为）
static inline uint32_t board_src_ip(uint32_t dst) { ... }
```

> **广播语义（登记为限制）**：IPv4 广播（`dst==0xFFFFFFFF`）没有“哪个口”的身份，双口下回包源 IP = IP0 ⇒ 只从 ch1/J8 出。ARP 不走这里（ARB 用 target_ip，天然有身份）；DHCP/广播 ping 在双口下退化为单身份。单口行为与今天**完全一致**。
>
> **MAC**：沿用单一 `BOARD_MAC = 00:0A:35:01:FE:C0`（直连构型可接受）；per-port MAC 需同时改 HLS 源 MAC 选择与快路径 `cfg_src_mac`，**不在 P2**（待裁）。

### 4.2 HLS 匹配/源 IP 逐点清单（现读行号）

| 文件 | 现读位置 | 现内容 | 改法 |
|---|---|---|---|
| `hls/src/layer_ip.cpp` | `:76-80` | `board_ip` 单值 + 广播判定 | `board_ip_match(ip_rx.dst_ip) \|\| (dst==0xFFFFFFFF)` |
| `hls/src/layer_arp.cpp` | `:149`（request SPA）、`:194-195`（reply 目标匹配）、`:201`（reply SPA） | `BOARD_IP_BYTE*` / `board_ip` | request 用 IP0；匹配 `board_ip_match(target_ip)`；**reply SPA = `board_src_ip(target_ip)`**（= target_ip） |
| `hls/src/layer_tcp.cpp` | `:10-12` `MAX_TCP_CONN=3`；`:142-149` `tcp_find`；`:177` cfg `w2`；`:277,292` `tcp_send` 的 sip/头 | 全用 `BOARD_IP` 常量；`tcp_find(port, ip)` | `tcp_conn_t` +`uint32_t local_ip`；`tcp_find(port, peer_ip, local_ip)` 加 1 比较；`w2 = local_ip`；`tcp_send` 的 `sip = c.local_ip`；T_LISTEN 建连存 `board_src_ip(ip_rx.dst_ip)`；T_SYN_SENT 存 IP0；RST 处理器（`:631-641`）加 local_ip 匹配 |
| `hls/src/layer_udp.cpp` | `:140`（dst）、`:168-171`（源 IP 头） | `BOARD_IP_BYTE*` | `udp_tx_process` 加 `rx_dst_ip` 入参；echo 的源 = `board_src_ip(rx_dst_ip)`；HELLO 源 = IP0 |
| `hls/src/layer_icmp.cpp` | `:141-143` | `BOARD_IP_BYTE*` | `board_src_ip(ip_rx.dst_ip)` |
| `hls/src/layer_igmp.cpp` | `:121-122` | `BOARD_IP_BYTE*` | 同 ICMP（今天 IGMP 在 `layer_ip` 里到不了，**死代码一致性改**） |
| `hls/src/udp_echo.cpp` | `:185-206`（UDP 解析）、`:228-229`（`udp_tx_process` 调用） | 只传 `rx_src_ip` | 加 `rx_dst_ip = ip_rx.dst_ip` 并传给 `udp_tx_process` |
| `hls/src/layer_dhcp.cpp` | 全文 | src=0.0.0.0 | **不改**；双口 = 静态 IP，DHCP 不在范围 |

### 4.3 `cfg_write.w2` 的下游链路（确认无 RTL 改动）

`HLS cfg_write w2 = local_ip` → `slow_cfg_adp` S_CAM 写 `cam_cfg_dip`（`rtl/slow_cfg_adp.v:148`）→ wrapper `cam_cfg_dip_mux`（`:2186`）→ `tcp_cam.dip_r`（`rtl/tcp_cam.v:37,51`）→ `rd_dip`（`:71-75`）→ wrapper `cam_rd_dip`（`:2210`）→ `tcp_tx_frame`（§2.3）。**`slow_cfg_adp` 零改动。**

### 4.4 1/2 口兼容与单口零回归（HLS）

- **一个 canonical HLS 输出**（推荐）：在 `hls/run_hls.tcl` 的 `add_files` 加 `-cflags "-DBOARD_IP_DUAL=1"`，重新综合并**归档旧 `slowstack_prj/solution1/syn/verilog`**。之后 `board/build_p7b_ku5p.tcl:27` 的 `hls_dir` 与所有现有门都自动用新网表。
  - **单口功能等价**的证明义务：`BOARD_IP_DUAL=0` 与 `=1` 的 csim 对 `dst=IP0` 的 ARP/ICMP/UDP/TCP 回包**逐字节相同**；`=1` 额外接受 `dst=IP1`。
  - ⚠️ **网表不逐位相同**：HLS 源变了 ⇒ 重新综合的 RTL 变了；这是“功能零回归”，不是“位级零回归”。构建轮必须把**旧 HLS 目录归档**（#54：`create_project -force` 会清 impl；HLS 目录也要单独归档），并记录新 HLS 的 `csynth` 报告。
- **备选：双输出目录**（若用户要求“单口 HLS 网表逐位不变”）：新增 `hls/run_hls_dual.tcl`（`-DBOARD_IP_DUAL=1`，`open_project slowstack_prj_dual`），P2 构建的 `hls_dir` 指向 dual；默认/其它构建仍指旧目录。代价 = 两份 HLS 产物、门与板可能编不同 HLS（**必须让双口门/构建显式选 dual、单口门选旧**，否则“门与板两个配置”）。本件推荐单输出。
- **HLS 面积/时序 = 未测**：+`local_ip`（3×32 FF）+ 匹配比较 + `tcp_find` 比较；HLS 在 DP 域 156.25 MHz 下运行（`wrapper_p4.v:2710` `.ap_clk(dp_clk)`），而综合约束是 K7 8 ns（`hls/run_hls.tcl`）⇒ 构建轮要定向看 `u_hls/*` 是否进 DP top-10。

### 4.5 `MAX_TCP_CONN=3` / 分池 / app 事件

- **`MAX_TCP_CONN=3`**（`hls/src/layer_tcp.cpp:10-12`）= 全系统同时连接上限。P2 验收 = **每口 1 条**（2 ≤ 3）；**每口 2 条（4）结构性不够**（除非扩 HLS 连接表，另开轮）。登记。
- **`WIN_POOL = 49152 B` 共享**（`rtl/app_ctrl.v:276`；wrapper 未覆盖）。两块连接的后果：
  - 默认 `wq_cap_r` 复位 = `WIN_Q_MAX = 0xC000`（`rtl/app_ctrl.v:296,1020`）⇒ **先建连者先占池**，第二条可能拿到 ~0 ⇒ RX 窗饥饿。
  - **本设计建议（零 RTL 改动）**：wrapper 在 `DUAL_SFP_A` 下给 `app_ctrl` 传 `.WIN_Q_MAX(WIN_POOL/2 = 0x6000)`（`:1461-1469` 的参数块加一项；`WIN_POOL` 本身保持默认 0xC000）。单口构建不传 ⇒ 复位值不变（零回归）。双口下两条连接各 ≤24,576 B ⇒ BDP 支持 RTT ≤ **19.7 µs**（纸面；实测 `minrtt 6–8 / srtt 16–27 µs` ⇒ 上沿越墙）⇒ P3 记录 `ss -ti`、**不承诺 2×10G**。
  - 板上没有可用 app 寄存器总线（`wrapper_p4.v:1547-1549` 静态钉死 `app_reg_addr=0/wr=0/wdata=0`）⇒ 运行时写 `0x0C` 分池不可用；只能靠参数复位值。
- **`app_ctrl` 事件字**（`rtl/app_ctrl.v:462` `EW=102`、`:468-469` `{kind, slot, peer_mac, peer_port, peer_ip}`）**无端口位**。P2 **不加**（app 总线在板上不可用，加了也没有消费者）；登记为 P3/后续可选项（改点：`app_ctrl.v:462/468-469` + `slow_cfg_adp` 的 `ev_*` 加 1 位 + wrapper 事件 FIFO 宽度）。
- **接收物理缓冲**：单 `tcp_echo` `frame_fifo`（16 BRAM）由两口共享；P2 验收按“单流/逐口”做，不要求两口同时满速。

### 4.6 甲模式对端配置（板级前置，待用户确认）

板：IP_A `192.168.100.2/32`（ch1/J8）、IP_B `192.168.100.4/32`（ch0/J7）。
对端（SFC9120 双口）：p1 = `enp1s0f1np1`（现役，`192.168.100.1/32`）；p0 = `enp1s0f0np0`（建议 `192.168.100.101/32`）。

**推荐：两个 netns**（最强“错口不可见”）：
```
ip netns add nsa; ip netns add nsb
ip link set enp1s0f1np1 netns nsa   # p1 <-> 板 J8 (IP_A)
ip link set enp1s0f0np0 netns nsb   # p0 <-> 板 J7 (IP_B)
ip -n nsa addr add 192.168.100.1/32 dev enp1s0f1np1; ip -n nsa link set enp1s0f1np1 up
ip -n nsb addr add 192.168.100.101/32 dev enp1s0f0np0; ip -n nsb link set enp1s0f0np0 up
ip -n nsa route add 192.168.100.2/32 dev enp1s0f1np1
ip -n nsb route add 192.168.100.4/32 dev enp1s0f0np0
# 两 ns 各: sysctl -w net.ipv4.conf.<if>.rp_filter=0; arp_ignore=1; arp_announce=2
# 两 ns 各: ethtool -C <if> adaptive-rx off rx-usecs 0   (全局 #68)
```
**备选（单 netns）**：两口各 `/32` + 显式路由 + `arp_ignore=1/arp_announce=2/rp_filter=0`。**弱主机模型会掩盖错口**（同一主机两个 IP 都属于本机）⇒ 只有 netns 或**不同子网**能给出“错口必须失败”的判别力（`p9_dual_sfp_exit_identity_compare_20261018/README.md` §6.1 同款）。

⚠️ 现有 P1 单口配方是 p1（J8）+ `.1/32`；上面的 netns 方案会**移动 p1 进 nsA**，与现役脚本不同 ⇒ 板级轮要重写工具入口（`p7b_tcp_sink` 用 `ip netns exec`）。登记为环境成本。

---

## 5. 判据 / 门 / 构建 / 板级计划

### 5.1 P2 验收判据（草案，不下裁定）

| # | 判据 | 仪器/负对照 |
|---|---|---|
| P2-1 | **单口零回归**：双口位流只插 J8，TCP 连续流向 IP_A，速率/`mism_bytes=0`/`stall` 与 0x2B 同会话 A/B 同档；**W84（ch0 TX split）Δ=0** | 板侧 W51/W52/W54/W55 + W83/W84；对端 p1 NIC |
| P2-2 | **A-1 出口正确**：p1→IP_A、p0→IP_B 两条连接各自通；每条连接的帧只在该口出现（板侧 W83/W84 与对端 p0/p1 NIC `port_rx_*` 双向对账） | 两条独立口径（板 + 对端 NIC） |
| P2-3 | **构造性错口负对照**：先两口各做一次 ARP 预热（板学习到 .1@p1 / .101@p0 的 MAC）；再在 nsA 临时加 `192.168.100.4/32 dev p1` 路由并 `p1→IP_B`（以及反向 `p0→IP_A`）——SYN 会被板按“IP 身份”接受，但 SYN-ACK 从 IP 的物理口发出（ch0 发往 p1 的 MAC）⇒ 对端 p0 的 NIC 因**目的 MAC 不是自己**而丢弃 ⇒ 连接 **必失败**；若两者都通 ⇒ **隔离无判别力**（不是 PASS） | netns + ARP 预热；板侧 W83/W84；两 ns pcap |
| P2-4 | **RX 合并公平/守恒**：两口同时灌 ≥ 聚合容量时，`ΔW79`（ch0 好帧）与 `ΔW0`（ch1 MAC 帧）**都前进**；两侧 drop（W82/W4）可读；`ΔW85 ≈ ΔW79+ΔW0−坏帧/丢帧` | 单元门严格优先负对照必须红；板级 pcap（两口） |
| P2-5 | **慢路径每口身份**：p0 对 IP_B 发 ARP/ICMP/UDP echo ⇒ 回包**只**在 p0 出现且源 IP=IP_B；p1 对 IP_A 同理 | 对端两 ns 的 pcap/NIC；`slow_tx_adp.o_port` 单元门 |
| P2-6 | **UDP app 每口**：从 IP_B 学 peer 后 app UDP TX 只从 ch0 出（W84 涨、W83 平）；从 IP_A 学后翻转（最后学习者赢） | 板侧 W8/W9 + W83/W84 |
| P2-7 | **单口隔离负对照**：`0x08` bit0=1（J7 TX_DIS）⇒ IP_B 连接停、IP_A 连接继续；bit1=1 反之 | P1 S-3 已证 bit0；bit1 需复算 |
| P2-8 | **错误源 IP 可观测**：若某帧源 IP 错，对端 pcap 逐字节可见 + 该连接行为异常；单元门 `tb_tcp_tx_srcip` 的错 IP 变异必须红 | pcap + 单元门 |
| P2-9 | **HLS 单口等价**：`BOARD_IP_DUAL=0/1` 对 `dst=IP_A` 的 ARP/ICMP/UDP/TCP 回包逐字节相同 | csim + xsim |
| P2-10 | **构建门**：WNS>0 + 三类失败端点 0/0/0 + `12-4739` 0 + 隐式网 5 键 0 + DRC 0 Error | 构建报告 |

### 5.2 门计划（现有 21 门 → 22 门）

现读：矩阵 **21 门**（`sim/p4gates/run_matrix_p4dfix.bat` 的 21 条 `call :gate`；`p7b_chain` = 第 20、`biz_win` = 第 21。⚠️ 该文件内联注释把 `p7b_chain` 写成 `#22`——那是**注释编号**，与实际 `call :gate` 条数/顺序差 1；本件按**实际条数**计）。P2 增 **1 门** ⇒ **22**。

| 门 | 新/改 | 内容 |
|---|---|---|
| G1 基线回归 | 现有 21 门 | **零回归**；新增端口在新源里默认常量 ⇒ 预期全绿（指纹会变，逐条解释） |
| G2 `rx_merge2` 单元 | **新** `_proj_10g/p11_dual/sim/tb_rx_merge2.v` | 单口工作保持 / 双口逐帧交替 / 帧原子性 / 随机反压 / 复位 / **STRICT=1 负对照必须红** |
| G3 `tx_demux2`+每口 arb 单元 | **新** `tb_tx_split` | 三口端口位分流 / 帧原子性 / 口内 TCP>UDP>HLS / **port 帧内变化必须被断言抓到** |
| G4 `slow_tx_adp` 端口提取单元 | **新** `tb_slow_tx_port` | IPv4/ARP/短帧/无 VLAN 不变式；**错偏移变异必须红** |
| G5 `tcp_tx_frame` 源 IP/校验和单元 | **新** `tb_tcp_tx_srcip`（编译 **OVL 与默认两体**各一臂） | 数据/控制/重放 × 两连接 A/B：IP 源、IP csum、TCP csum 逐字节；`o_port` 正确；**错 local IP 变异必须红** |
| G6 双口全链 wrapper 门 | **新** `_proj_10g/p11_dual/sim/run_tb_p11_dual.bat`（真 wrapper + `DUAL_SFP_A` + `P7B_SIM_NOPCS` 双通道注入/捕获） | 两连接从两口建连、RX 合并路由、TX 出口、每口计数、跨口不串；**端口反转变异必须红** |
| G7 elaboration 组合 | 改 `p7b_chain/sim/run_elab_4combo.bat`（7 → 11 组合） | 新增：DUAL(无 P7B) FAIL / DUAL+B FAIL / DUAL(无 DP) FAIL / DUAL(无 APP) FAIL，按**模块名签名**判失败 |
| G8 HLS 双 IP | 改 `hls/tb/udp_echo_tb.cpp` + 构建后 xsim 臂 | 单口逐字节等价 + 双 IP 匹配/回源 + `tcp_find` 同 peer 双 IP 分离 |
| G9 几何/读侧 | 改 `sim/p6e_pcie/tb_p6e_pcie_wrapper.v`、`…_counters.v`、`_proj_10g/notes/p7b_biz_win/{check_window.py,tb_biz_win.v}`、`apply_readside_bid1c.py` 新阶段 0x2C（83→86 / 0x17C→0x188 / MIR 迁移 / WLABEL 补 W83..W85） | BID/几何/未实现地址/逐字读回 |
| G10 矩阵 | 改 `run_matrix_p4dfix.bat` + `paths.txt` + 新 manifest | 22/22、FROZEN、指纹漂移逐条解释 |

### 5.3 构建计划

- **BID = `0x2C`**（`wrapper_p4.v:4824` `BUILD_ID_V`）；乙顺延 **0x2D**。
- **宏**：`build_p7b_ku5p.tcl:286` 在现有 8 宏后**追加** `DUAL_SFP_A=1`（不覆盖；日志回读 `P7B_VERILOG_DEFINE` 核 9 项）。
- **HLS**：先跑 `run_hls.tcl`（含 `-DBOARD_IP_DUAL=1`），归档旧 `slowstack_prj` 输出；再构建。
- **一次收口**：WNS>0 / WHS>0 / 三类失败端点 0/0/0 / `12-4739` 0 / 隐式网 5 键 0 / DRC 0 Error / 位流 sha256 + BID 归档（#54 写进构建脚本）。
- **构建轮定向 STA 观察点**（`-from` 定向，不靠 top-200 清单——#66）：
  `u_tcp_tx/f_lip_reg*`、`u_tcp_tx/ctrl_lip_reg*`、`cam_rd_dip` 到 `u_tcp_tx/*csum*`、
  `u_rx_merge/*`、`u_tx_udp_arb/u_tx_arb`（每口）、`u_snap_p7bdp/hold_b_reg[1248..1343]`（新增 3 字）、
  `u_hls/*`（HLS 重综合后的新锥）。
- **backstop（预登记，按序；每档 = 新输入，不许重跑到过）**：
  1. 删 W85 ⇒ NW 85 / `0x184`；
  2. 删 W83/W84 ⇒ NW 83 / `0x17C`（BID-only 阶段）；
  3. 删 ch0 TX 的第二级（只留每口 demux+单级 arb？不可行）——改为**把 `PER_CONN_SRC_IP=0` 并放弃 A-1** 是**不合格回退**；正确做法 = **abort-to-0x2B**（丢掉 P2 本轮全部，保留 P1），不在坏输入上叠加局部删减。
  4. 若 HLS 新网表吃时序：回退 HLS 到归档网表并**只做 RX 接入 + 单 IP TX**（P2 拆半，登记为不合格的中间态，需用户裁）。

### 5.4 板级计划（草案；不写 PASS/FAIL）

**前置**：重烧 0x2C + 核 sha256；身份门 `0x04=0x2C` / 86 字 / `0x188=0xffffffff` / MIR 四字可读 / 2 BARs / `LnkSta x4` / `0x08=0`；两口 AOC 在位（J7↔p0、J8↔p1）；对端 netns 配置现取见证（`ip -n … addr/route`、`ethtool -C`、`ss -ti`）；两口 coalescing 关；`nmcli managed no`（两 ns 各一）。

| # | 动作 | 期望读数（草案） | 独立仪器/负对照 |
|---|---|---|---|
| B-0 | 入口态 + 身份门 | BID/几何/UNIMPL/2 BARs/x4；`0x08=0`；p0/p1 carrier=1 | 对端 `ip -br link` |
| B-1 | 单口回归（只插 J8；J7 不插或 TX_DIS） | TCP 连续流 9 Gbps 级 / `mism=0` / `stall=0`；**W84≡0**、W83 涨 | 0x2B 同会话 A/B；对端 p1 NIC；#43/#59/#68 台架帽记录 |
| B-2 | 双口各一条 TCP | p1→IP_A、p0→IP_B 同时通；每口板侧 W83/W84 与对端 `port_rx_*` 对账（±0.2% 量级）；`mism=0`/逐连接 | 两条独立链；pcap 两口 |
| B-3 | **错口负对照** | 先 ARP 预热两口；nsA 加临时 `/32` 路由后 `p1→IP_B`、nsB 加临时路由后 `p0→IP_A` —— 两者 **必失败**（timeout；SYN-ACK 从 IP 的物理口发往对端另一口的 MAC ⇒ 对端 NIC 丢弃）；若通 ⇒ 隔离无效（登记“无判别力”） | netns；两 ns pcap；板 W83/W84 |
| B-4 | 慢路径逐口 | p0 对 IP_B：ARP/ICMP/8080 UDP echo 回包只在 p0、源 IP=IP_B；p1 对 IP_A 同理 | 两 ns pcap + NIC |
| B-5 | UDP app 逐口 | 从 IP_B 学 peer ⇒ app TX 只出 ch0（W84 涨/W83 平）；从 IP_A 学 ⇒ 翻转 | 板 W8/W9/W83/W84 |
| B-6 | RX 合并公平 | 两口同时灌（> 聚合）；`ΔW79`、`ΔW0` 都前进；W82/W4 可读；W85 对账 | 单元门 STRICT 负对照；pcap |
| B-7 | 单口 TX_DIS 隔离 | `0x08` bit0=1 ⇒ IP_B 停、IP_A 继续；bit1 反之；恢复 | P1 S-3 已证 bit0 |
| B-8 | 收尾 | 回烧 0x2B 或留 0x2C（按用户）；`0x08=0`；carrier=1；对端 ns 清理 | 身份门复算 |

---

## 6. 待裁与风险

### 6.1 待裁清单（按影响排序）

| # | 事项 | 本件建议 | 影响 |
|---|---|---|---|
| D1 | **IP_B 地址值 / 对端 p0 地址 / netns vs 单 ns** | IP_B=`192.168.100.4`；p0=`192.168.100.101`；**netns** | 决定 P2-3 负对照有没有判别力 |
| D2 | **BID 分配** | 甲 `0x2C`、乙 `0x2D` | 读侧/身份门 |
| D3 | **TX 选口方案** | **②**（demux 前移 + 复制 arb） | 改动面/回归面 |
| D4 | **`WIN_POOL` 分池** | 双口构建 `.WIN_Q_MAX=0x6000`（参数复位值） | 两连接 BDP（RTT ≤19.7 µs） |
| D5 | **`rx_merge2` FIFO 深度** | 256（1.35 帧）+ per-port drop 计数 | 板上无谓丢帧量 |
| D6 | **HLS 网表策略** | 单 canonical 输出（重新综合 + 归档旧） | 单口“位级不变”是否可接受 |
| D7 | **per-port MAC** | 单 MAC（直连可接受）；per-port MAC 留后续 | 接交换机/L2 时才需要 |
| D8 | **广播 IPv4 语义** | 映射回 IP0（= 今天行为） | 双口广播 ping/DHCP 只走 ch1 |
| D9 | **`app_ctrl` 事件端口位** | P2 不加，P3 可选 | app 可见性 |
| D10 | **板上错口变异位流**（PORT_INV） | **不做**；用 netns 跨口 SYN + 单元门变异 | 省一次 ~47 min 构建 |
| D11 | **方案③（post-arb 源 IP 解析选口）** | 不在第一版；若要“生产者零改动”再裁 | 可能显著缩小改动面 |
| D12 | **观测 3 字的核心集** | W83/W84/W85；backstop 见 §5.3 | 时序风险 |

### 6.2 最关键的 3 个风险

1. **时序（0.75% 基线）**：A-1 的 `cam_rd_dip` 进入 `csum_init_val`/头字 mux（加法树级数不变，但 CAM 读扇出 +32 位），加上 `f_lip/ctrl_lip` 99 FF 与快照 +288 FF。0x2B 的全局宿主是既存 `u_tcp_tx/u_fifo_a → u_app/bcnt`（`p9_build_0x2B_20261018/README_FOR_TL.md:63-64`），新逻辑可能换宿主。**不可纸面预测**；一次构建收口 + 预登记 backstop；定向 STA 必查 `f_lip/ctrl_lip/cam_rd_dip`→csum 与 `u_snap_p7bdp/hold_b_reg` 新字。
2. **A-1 的静默错误**：`tcp_tx_frame` 的源 IP 出现在 **IP 头 / IP 校验和 / TCP 伪头** 三处，且要覆盖**数据帧、控制帧、重放** × **OVL/默认双体**。任何一处漏改都表现为“对端静默丢弃/连接行为异常”，**没有握手判据会红**（工程已多次吃过“校验和错 ⇒ 无判据红”的亏）。对策 = G5 单元门逐字节校验（两体各跑）+ G6 全链 pcap 对账 + G7 变异负对照。
3. **HLS 重新综合的全局面**：`slowstack_prj` 是**所有** P7B/K7 构建与门的共同 HLS 输入（`build_p7b_ku5p.tcl:27`、各 build tcl、`p7b_chain` 门）。重新综合后：① 单口行为必须由 G8 证明等价；② 门的 HLS 与板的 HLS 必须是同一份（否则“门与板两个配置”，坑 11）；③ HLS 在 DP 156.25 MHz 下运行（综合约束 8 ns），新逻辑可能进 DP 关键路径。对策 = 归档旧网表 + 单口 csim/xsim 逐字节 + 构建轮 `u_hls/*` 定向 STA。

### 6.3 其他风险（登记）

- 每口 arb 使“TCP 全局绝对优先”变成“口内优先”；跨口不再互相抢占（设计接受，但 P3 的“公平份额”判据要按口写）。
- `rx_merge2` 每帧 1 拍重仲裁气泡：大帧 ≈0.5%，最小帧（8 字）≈11% —— 只影响小帧吞吐，登记。
- UDP app 单 peer 表“最后学习者赢”，两口同时活跃会翻转。
- 慢路径源 IP 提取的不变式“HLS TX 不加 VLAN”若被将来打开 ⇒ 静默错口；必须写进门断言。
- 端口位数组的“同拍同址同源”不变式若将来有人改 CAM 写路径（如加第二条配置源）会破；门断言必须覆盖。
- `0x08` 既是 SCRATCH 又是 TX_DIS 门（既存坑）。

---

## 7. 未测 / 纸面 / 未判定（不许当已答）

1. **全部 LUT/FF/时序增量 = 纸面**（±30% 包络）；唯一的硬锚是 `mac_tx_10g` OOC 上界 `1,602 LUT / 488 FF`（`_proj_10g/p7b_mac_synth/mac_only/mac_tx_ooc/`）。
2. **WNS 预测不可给**：0x2B 的 `+0.048` 是唯一可信输入；任何“预计 WNS”都不成立。
3. **HLS 重新综合的面积/时序 = 未测**。
4. **`rx_merge2` 的板级公平性/丢帧率 = 未测**；FIFO 深度 256 的“1.35 帧”是纸面算术（190 字/最大帧）。
5. **对端 netns 配方 = 未跑**；跨口 SYN 负对照的判别力 = 未测。
6. **`tcp_tx_frame` 两体的行为覆盖**：OVL 体在板上生效，但现有 `p7b_chain` 门**只编 OVL、无行为臂**（P1 已登记“board TCP TX body 无行为门”）；G5 是新增门，未跑前该风险仍在。
7. **方案③（post-arb 解析）** = 未设计细节、未评估；本件只登记。
8. **乙模式（0x2D）= 不在 P2**；镜像目的地在 P3 定。
9. **`MAX_TCP_CONN=3` / 共享 `WIN_POOL` 的 BDP 后果** = 纸面（RTT 19.7 µs），实测 `ss -ti` 未取。
10. **`app_ctrl` 事件端口位 / per-port MAC / 交换机场景** = 未实施、未测。
11. **本件未改一行代码、未构建、未跑门、未碰板**；所有“推荐/顺序”是设计建议，裁定权在用户。
12. **“未观测到 ≠ 不存在”**：P1 的 S-4/S-5（LOS/停钟）仍未测（`p9_board_p1_20261018/README_FOR_TL.md` §3-4/5），P2 设计不改变这一点。

---

## 附录 A —— 现读锚点速查（2026-10-18，0x2B 树）

**wrapper（`board/wrapper_p4.v`）**
`:294` `WIN_CAP_5` · `:346-353` FE 域别名 · `:639-646` ch0 常量 IDLE · `:677-700` MAC 复位（`:687-688` ch1 / `:693-700` ch0 RX） · `:911` `u_mac_rx`（ch1） · `:949-1012` ch0 tap/sink/`u_mac_rx_ch0` · `:1054` `u_rxcdc(76)` · `:1097` `vlan_strip` · `:1120` `rx_classify` · `:1295-1297` app_reg 线 · `:1461-1469` `app_ctrl` 参数 · `:1547-1549` app_reg 钉死 · `:2026` `cam_rd_dip` 声明 · `:2183-2189` CAM 写 mux · `:2191-2213` `tcp_cam` · `:2215` `tcb` · `:2290` `slow_cfg_adp` · `:2398` `tcp_tx_frame` · `:2452-2453` `cfg_src_mac/ip` 常量 · `:2558` `udp_split`（`:2592` `cfg_dst_ip`） · `:2710` `udp_echo` · `:2732` `slow_tx_adp` · `:2818` `app_udp_pattern` · `:2865` `udp_tx_cfg`（`:2884` `cfg_my_ip`） · `:2910` `udp_tx_frame` · `:2936` `u_tx_udp_arb` · `:2987` `u_tx_arb` · `:3013` `u_txcdc` · `:3039` `u_mac_tx` · `:3522` `SNAP_NW_P6E=83` · `:3543` `SNAP_P7BDP_NW=39` · `:3554` `SNAP_CH0_NW=4` · `:3555` `SNAP_TX_NW=5` · `:4406-4454` p7bdp 槽 assign · `:4483-4495` ch0 束 · `:4601-4649` `snap_dout_all` · `:4814-4818` SFP TX_DIS · `:4824` `BUILD_ID_V=0x2B` · `:5305` `.SNAP_NW`

**RTL**
`rtl/tcp_cam.v:36-40,71-75` · `rtl/tcb.v:94-105`（`3'd7` 保留） · `rtl/slow_cfg_adp.v:137-163`（`:148` w2） · `rtl/tx_arb.v:9-25`（73 位固定） · `rtl/tcp_tx_frame.v:122-129,392-405,817-820,874-876,900-901,1199-1208,1314-1344,1346-1361,1396-1397,1440,2000-2011,2022-2025,2272-2288,2392-2415,2463,2481` · `rtl/udp_tx_cfg.v:66-77,124-127,142-180` · `rtl/udp_rx.v:180-181,202-213` · `rtl/udp_split.v:209-213,215,443-446,745-749` · `rtl/slow_tx_adp.v:17-25,40-44,80-88,136-198,207-224` · `rtl/rx_classify.v:26-66,70,76-94,188-191` · `rtl/app_ctrl.v:276,296,462,468-469,1020` · `_proj_10g/p7b_mac/rtl/mac_tx_10g.v:39-68,317-330` · `_proj_10g/p7b_mac/rtl/mac_rx_10g.v:326-327,405-414`

**HLS**
`eth_types.h:111-123,211-217` · `layer_ip.cpp:76-80` · `layer_arp.cpp:149,194-195,201` · `layer_tcp.cpp:10-12,142-149,177,277,292,581,631-641,663-679` · `layer_udp.cpp:140,168-171` · `layer_icmp.cpp:141-143` · `layer_igmp.cpp:121-122` · `udp_echo.cpp:185-206,228-229` · `run_hls.tcl`（add_files/cflags） · `layer_mac.cpp:218`（`insert_vlan` 唯一读点）

**构建/门**
`build_p7b_ku5p.tcl:27`（`hls_dir`）、`:286`（`verilog_define`） · `board/p7b_pcs_stub.v:172-217`（双通道注入/捕获） · `sim/p4gates/run_matrix_p4dfix.bat` 21 条 `call :gate` · `_proj_10g/p7b_chain/sim/run_elab_4combo.bat`（7 组合） · `_proj_10g/p7b_chain/sim/run_tb_p7b_chain.bat`（板宏集，不含 SFP2/DUAL） · `_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py`（阶段链到 0x2B）

**基线读数**
`_proj_10g/notes/p9_build_0x2B_20261018/README_FOR_TL.md:39-55,63-92,98-106,159-170` · `_proj_10g/notes/p9_board_p1_20261018/README_FOR_TL.md:20-29,82-181`

---

*本件 = P2-甲 实施级设计（只读）。不含 PASS/FAIL 裁定；所有“达标/不达标”留待用户与后续实测。纸面数字已逐条标注；「未观测到」≠「不存在」。*
