# P11 / P2-甲 设计 v2 —— 闭项抽查 FINDINGS_V2

> **TL 代落（2026-10-18 08:5x）**：本件 = 独立闭项抽查 agent 的完整 FINDINGS_V2 原文（平台禁止子 agent 写报告类 `.md`，由 TL 转录；未改结论）。TL 抽核见文末 §TL 抽核。

- 日期：2026-10-18 · 角色：独立闭项抽查审查 agent（只读）。未改任何 RTL/脚本/工具，未跑 xsim/Vivado，未碰板/对端/烧录，未写 git。
- 对象：`_proj_10g/notes/p11_p2a_design_20261018/DESIGN_v2.md`（755 行，施工权威）· `p11_review_p2a_design_20261018/FINDINGS.md`（v1 审查：阻断 1 / 高 8 / 中 13 / 低 12 + TL 抽核 8/8）· v1 历史 `README_FOR_TL.md`。
- 基线：0x2B 树（`BUILD_ID_V = 32'h0000002B` / `SNAP_NW_P6E = 83` / 未实现 `0x17C`）。行号 = 2026-10-18 现读；行号漂移以符号名为准。
- 纪律：**不下 PASS/FAIL 裁定**；状态词 = 已闭 / 部分闭 / 未闭；「未观测到」≠「不存在」；纸面数字标"纸面"。

---

## ① 逐项闭项表

### 1.1 阻断 / 高（FINDINGS B-1 + H-1..H-8，共 9 项）

| 项 | v2 落点 | 状态 | 依据 / 残余 |
|---|---|---|---|
| **B-1(a)** | §4.5 / §5.1 P2-1/P2-2 / §6.1 D4 | **部分闭** | TL 选项 (a) 已落地：`WIN_Q_MAX` 不传参、复位默认 `0xC000`（`rtl/app_ctrl.v:283-296,530-533` 现读；wrapper `:1461-1469` 未覆盖）⇒ 单口单连接窗口 = 0x2B；P2-2 已改"每口各自建连/身份正确 + 逐口顺序"；"双口同时数据流"登记待用户裁；SYN-ACK `0xC000` 一致性登记 P3 前置（`hls/src/layer_tcp.cpp:281` 逐字 0xC000）。**残余 = 新发现 N-1**：P2-2 的"池归还见证"`ss -ti snd_wnd > 0` 被硬编码 SYN-ACK 0xC000 污染。W62 口径正确：`rx_occ_bytes` 只是 `pool_occ/fq_calc` 的输入（`app_ctrl.v:869,897`），不是自由池 `pool`。无 P2-1（单口零回归）与逐口顺序的结构矛盾。 |
| **H-1** | §2.4 / §2.7 / §5.2 G1 | **部分闭** | `cfg_dual` 已取消运行端口，`udp_rx`/`udp_split` 改编译期 `DUAL_IP`/`IP_B` 参数（§2.4；`udp_rx.v:180-181` 现读单值比较）；`udp_tx_cfg.peer_my_ip` 是唯一新输入且 `cfg_sync` 参数门控（M-11）；9 个 active 直接例化点现读逐点命中：`tb_app_udp.v:219/:311`、`tb_udprx_chain.v:232`、`tb_udprx_rate.v:327`、`tb_app_udp_rate.v:162`、`tb_udp_split.v:60`、`tb_udp_tx_guard.v:180`、`tb_udp_rx.v:55`、`tb_udp_echo.v:51`（8 文件 / 9 点）；无 Z 断言（`VRFC 10-3645` + `peer_my_ip` 联合 + `$isunknown`）在 G1。**残余 = 新发现 N-2**：`IP_B_5` 只在 `` `ifdef DUAL_SFP_A `` 内声明，却被非 DUAL 参数化引用。 |
| **H-2** | §4.6 / §5.1 P2-3 / §5.4 B-3 | **已闭** | nsA/nsB 两侧 `ip neigh replace 192.168.100.4/2 lladdr 00:0a:35:01:fe:c0 nud permanent`；判据拆 ① 身份（p1 对 IP_B ARP who-has 无应答）② 出口（p1 pcap SYN + p0 pcap SYN-ACK 且 dst MAC=p1 MAC + p1 收不到），并写明"不做静态邻居只能叫 ARP 层隔离"。源码链（`layer_tcp.cpp:314-315`、`layer_arp.cpp:194-201`）与 FINDINGS 一致。 |
| **H-3** | §2.5 / §5.2 G4 | **已闭** | 深度 ≥128（选 128）；8 字/64 帧论证成立（见 §③-1）；unit 门断言 `side_fifo_level==committed` / `side_ovf==0` + `SIDE_DEPTH=16` 溢出负控 + 错位负控（§2.5 / G4）。`frame_fifo` W=73/D=512、`slow_tx_adp.v:80-88` 现读。 |
| **H-4** | §5.3 / §5.2 G6/G7 | **部分闭** | `rtl/rx_merge2.v` / `rtl/tx_demux2.v` 两行 import 已写（`P7B_ADD_DATAPATH` 或新 `P7B_ADD_DUAL`）；`P7B_MODULE_RESOLVED` 断言 + synth 日志 `black box`/`8-3491` 为 0；静态同步三件（`p7bchain_src.f` / `run_tb_p7b_chain.bat` / G6 manifest）已写；`elab_files.f` 运行时生成已反向核对（§0.2-4，机制成立）。**残余 = N-3（cell-count 断言看不见黑盒）+ N-4（`maccnt_sync` 漏导入/漏解析断言）**。 |
| **H-5** | §5.2 G9/G1 / §5.3 | **已闭** | `tb_p7b_chain.v` 进 G9；G1 改"编辑后回归"；构建前置 `grep -n "0x17C reads 0" tb_p7b_chain.v` 为空；地址算术正确（见 §③-2）。现读 TB 在 `:1647` 有 `7b 0x17C reads 0 no wrap`，`:1645` 有 MIR_STATUS@0x16C ⇒ 必须编辑。**注：G9 读侧文件清单不全 = 新发现 N-5**。 |
| **H-6** | §5.2 G6 | **已闭** | G6 两臂：臂 A 真实 HLS 握手（ARP/ICMP/SYN-ACK 走 `slow_tx_adp`，双 IP 重综合网表）；臂 B force 快臂（驱动 `txin_*`/`app2_*` 或三个 demux 输入，**不 force `txsrc_*`**）；`txsrc_*` force 只作 MAC 接线臂单独记；断言每口 W83/W84、每帧 `o_port` 与帧头源 IP 一致、跨口不串、端口反转变异红。现读 `tb_p7b_chain.v:1353-1355` 的 force 自述与 FINDINGS 一致。 |
| **H-7** | §3.4 / §3.5 / §6.1 D12 | **已闭** | NW 88 表/地址/MIR/UNIMPL/`SNAP_P7BDP_NW=44` 正确（见 §③-2）；W86/W87 的 `maccnt_sync` 4 相握手（源域锁存 + toggle/ack，非裸 2FF 多比特）+ 256 dp_clk 节流 + 误差 ≤1.64 µs；偏离"开发期全量"在 D12 显式登记（仍缺 ch0 `stat_flush_done/stat_tx_short`、`side_ovf/play_port`、merge 内部计数、ch0 txcdc 占用峰值、`meta_dst_ip`）。**残余 = N-4（maccnt_sync 构建清单）+ N-12（W87 低半饱和语义）**。 |
| **H-8** | §5.1 P2-2 / §3.4 | **已闭** | 差值 mod 2³² + raw+k；窗 <27.487 s 或分窗；ch1 `ΔW83 − Δpeer_p1 ≤ ΔW45(字) + ΔW21(帧)`；ch0 `ΔW84 − Δpeer_p0 ≤ sat16(ch0_txcdc_ovf，W86[15:0]) + sat16(ch0_mac_tx_abort，W87[31:16])`；`port_rx_*` = 跨系统口径（L-6）；ch0 abort 由 W87 可观测（v1"未观测到"关闭，附 backstop 删 W87）。**残余 = N-7（等式假设窗末已静默）**。 |

**小计（阻断/高）：已闭 6 / 部分闭 3 / 未闭 0。**

### 1.2 中 / 低抽核（任务点名的 8 项）

| 项 | v2 落点 | 状态 | 依据 |
|---|---|---|---|
| **M-1** | §4.2 / §5.2 G8 | **已闭** | `cfg_write` 增 `uint32_t local_ip`（签名 §4.2；现读 `layer_tcp.cpp:165-181`）；`w[2]=local_ip`（现读 `:177` 为 BYTE 宏）；DEL 调用点 `:609/637/699/721` 传 0、ADD `:663/:677` 传 `c.local_ip`（现读调用点逐字命中）；`tcp_conn_t` 加 `local_ip`；`tcp_find(port,ip,local_ip)`（现读 `:142-149`，调用 `:581`）；RST 循环 `:631-645` 加 `local_ip==ip_rx.dst_ip`；RTO 释放只置 `T_FREE`、保留 peer_ip/port/local_ip（现读 `:540-550` 只写 state）；G8 加 RST-to-released-slot。 |
| **M-2** | §4.4 / §5.1 P2-9 / §5.2 G8 | **已闭** | 一个 canonical netlist（`-DBOARD_IP_DUAL=1`）；显式登记"默认单口构建也接受 IP_B"；`dst=IP0` 功能等价（G8 csim 两二进制）；位级不变备选（双输出目录）登记不选；`run_hls.tcl` 现读只 csynth、无 cflags（改动点正确）。 |
| **M-6** | §5.1 P2-4 / §3.4 | **已闭** | 干净窗 `ΔW85 == ΔW79 + ΔW0` 只在 `ΔW81=ΔW82=ΔW4=0` 且无 TERM 时判；否则只记残差；W85 = `(cls_stat_fast + cls_stat_slow)[31:0]` 显式截断；P2-4 主判据 = 两口前进 + drop 可读 + 公平，不用守恒律当 oracle。现读 `rx_classify.v:188-191` 计 fast/slow 帧、不判 tcrs；`mac_rx_10g.v:394-414` 计数语义一致。 |
| **M-11** | §2.4 | **已闭** | `cfg_sync` 参数门控逐字：`PER_CONN_SRC_IP ? (o_src_ip==peer_my_ip_r && o_port==(peer_my_ip_r==IP_B)) : (o_src_ip==cfg_my_ip && o_port==1'b0)`；现读 `udp_tx_cfg.v:124-127` 为 7 项比较（无误加 `peer_my_ip`）。 |
| **M-12** | §2.6 / §5.2 G5/G6 | **已闭** | 生产者侧 `tvalid && !tready` 期间 `o_port` 逐拍不变：`tcp_tx_frame`（帧首锁存）、`udp_tx_cfg`（idle 刷新 + frame_busy 冻结）、`slow_tx_adp`（start_play 弹出）各一条；`tx_demux2` 另做帧首锁存 + `stat_port_change`。 |
| **L-5** | §3.4 / §5.1 P2-2 | **已闭** | W85 显式 `[31:0]` 截断；差值 mod 2³² 记 raw+k。现读 `stat_fast/stat_slow` 各 32 位（`rx_classify.v:56-57`）。 |
| **L-8** | §4.6 | **部分闭** | `nmcli device set ... managed no` 已在移入 netns 之前于根 ns 执行（§4.6:538-539）；之后改用 `ip -n <ns> ...`。**残余 = N-8**：同一配方 `:551` 的 `ip -n <ns> exec ethtool ...` 不是合法 iproute2 用法（应为 `ip netns exec <ns> ethtool ...`）。 |
| **L-12** | §2.7 / §5.2 G2 | **部分闭** | `rx_merge2.STRICT` 在 wrapper 硬接 `1'b0`（§2.7）；G2 另例化 `STRICT=1` 做负控。**残余 = N-9**：§0.1 L-12 承诺"G7/elab 加 `STRICT` 常量断言（wrapper 文本与参数双查）"，但 §5.2 G7 行没有这条。 |

**小计（点名中/低 8 项）：已闭 6 / 部分闭 2 / 未闭 0。**

### 1.3 其余 M/L（快速复核）

| 项 | 状态 | 依据 |
|---|---|---|
| M-3 | 已闭 | `p4gate.py:498-505` 把 `HLS=` 目录的 `*.v/*.dat` 计入 `compile_set/hls`，`:535` 参与 `digest_c`；FROZEN 用 `DIGEST_ALL`（含 `FINGERPRINT_GLOBS` 的 extra）⇒ 追加 HLS 源 glob 可绑定；构建/门记 `HLS_*_HASH`。 |
| M-4 | 已闭 | `elab_files.f` 现读由 `run_elab_4combo.bat:27-28` 的 `dir /b /s rtl\*.v` 运行时生成；G7 7→12 组合 + 6 个 `findstr` 签名 + DUAL 正控；`COMMON` 无条件前缀的减法风险已在 §5.2 G7 写明。 |
| M-5 | 已闭 | G2/G5/G6 注册 ⇒ 矩阵 21→24；G3/G4 登记独立门债务；G10 计数写 24。现读矩阵确有 21 条 `call :gate` 行（`:184-199` 16 条 + `:211/:224/:241/:250/:261` 5 条）。 |
| M-7 / M-8 | 已闭 | 并入 B-1；不传参 + SYN-ACK 一致性 P3 前置。 |
| M-9 | 已闭 | P2-1 预登记 ≤0.5% 结构性差值；主口径 = 板内 `ΔW43/ΔW20` + `W51/W52`；`W84 Δ=0` 与 `ΔW83>0` + 对端 NIC 配对；P2-2 提供 W84 正控。 |
| M-10 | 已闭（附 N-13） | G2 负控 `DEPTH=4` + 持续注入 ≥2 最大帧 + 高优先口 `tready=0`；正臂断言逐帧 RR。**N-13**：需同时给高优先口一个有效帧，否则 work-conserving 的 `STRICT=1` 仍服务低优先口。 |
| M-13 | 已闭 | G6 两臂分开记（HLS 真实握手 / force 快臂）。 |
| L-1 | 已闭 | `cam_rd_port = cam_port_arr[cam_rd_id]`（§2.2），不用 `rb_id`。 |
| L-2 | 已闭 | `p7b_ch0_idle_d/c` 的 `dont_touch` **寄存器声明本身**包 `ifndef DUAL_SFP_A`（§3.1/§3.3）。 |
| L-3 | 已闭 | `PER_CONN_SRC_IP=0` 改称"行为等价"（§2.3/§2.7）。 |
| L-4 | 已闭 | `cam_port_arr` 复位 0；`tcp_tx_frame`/`udp_tx_cfg`/`slow_tx_adp` 三处 `o_port` 复位 0。 |
| L-6 | 已闭 | `port_rx_*` 写"跨系统口径"，不是两条独立硬件计数。 |
| L-7 | 已闭 | P2-6 短窗 + 背景率预取（W7）+ 每口 pcap 主判据。 |
| L-9 | 已闭 | `arp_send_request` SPA=IP0 登记；ACTIVE_CONNECT=0 下无害。 |
| L-10 | 已闭 | `slow_tx_adp` TPID 自检 sticky `vlan_seen` 强制 `o_port=0`；G4 负控。 |
| L-11 | 已闭 | IGMP 分发在 `udp_echo.cpp:172-173` 是活的；不可达因 `layer_ip.cpp:76-81`；措辞已订正。 |

---

## ② 新发现（分级）

### 中（6 条）

**N-1（中）P2-2 的"池归还见证"`ss -ti snd_wnd > 0` 结构性看不见 fast-path 配额。**
- 位置：`DESIGN_v2 §4.5`（`:523`）、`§5.1 P2-2`（`:569`）、`§5.4 B-2`（`:628`）。
- 依据：HLS SYN-ACK 的窗口是**硬编码 `0xC000`**（`hls/src/layer_tcp.cpp:281` 现读），而第二条连接的 fast-path 配额可能是 0（`app_ctrl.v:869` `g_grant=min(wq_cap_r, pool-occ)`）。在 fast path 发出第一条带窗口的 ACK 之前，对端 `ss -ti` 的 `snd_wnd` 只能来自 SYN-ACK = 0xC000 ⇒ **即使池未归还，见证仍 >0**。这正是 B-1 已登记的"SYN-ACK 0xC000 与配额一致性 = P3 前置"的直接后果。
- 影响：P2-2 阶段 II 的"先核 `snd_wnd>0` 再判数据"防线是**空判据**（结构上不会红）；第二条连接零窗时会在数据阶段以别的原因失败。
- 建议：把见证改为"**发生一次 fast-path 数据/ACK 交换之后**再读 `ss -ti`"，或先在第二条连接上发 1 字节数据探针并核其 ACK 的窗口；或在 G6/sim 侧用 `app_ctrl` `0x97 pool` / `0x9A winq` 读自由池（板上 app 总线不可用，只作门）。若坚持现法，应把该见证降级为"辅助"，不得作为"否则只做身份判定"的开关。

**N-2（中）`IP_B_5`/`DUAL_SFP_A_DEF` 的作用域/定义缺口 ⇒ 非 DUAL 构建编译失败。**
- 位置：`DESIGN_v2 §2.2` 代码块（`:125-137`）把 `localparam IP_A_5/IP_B_5` 放在 `` `ifdef DUAL_SFP_A `` 内；`§2.4`（`:219`）在 `udp_split #(.DUAL_IP(DUAL_SFP_A_DEF), .IP_B(IP_B_5))` 与 `udp_tx_cfg #(... .IP_B(IP_B_5))` 中**无条件**引用。
- 依据：非 DUAL 构建走 `else` 支，只有 `wire cam_rd_port = 1'b0;`；`IP_B_5` 是未声明标识符 ⇒ xvlog/synth 硬错。`DUAL_SFP_A_DEF` 在现树/本设计中也没有定义（现树只有 `SFP2_MODE_A_DEF`/`SFP2_MODE_B_DEF` 的模式）。
- 影响：G1/elab 的非 DUAL 组合、默认构建全部编译不过；"单口构建原样"要求被破坏。
- 建议：把 `IP_A_5`/`IP_B_5`/`DUAL_SFP_A_DEF` 定义移到 `ifdef` 外（值固定），或在非 DUAL 支传 `32'hFFFFFFFF`/`1'b0`。

**N-4（中）新模块 `maccnt_sync` 未进构建导入 / 模块解析断言 / 静态清单（H-4 同类缺陷复发）。**
- 位置：`DESIGN_v2 §3.4`（`:392`）、`§5.3` 导入段、`§5.3` STA 观察点（`:616`）、`§8` 变更表。
- 依据：`§5.3` 只把 `rtl/rx_merge2.v`、`rtl/tx_demux2.v` 加进 `P7B_ADD_DATAPATH`；`P7B_MODULE_RESOLVED` 只查这两个；`§5.2 G10` 的三个新 manifest 也只按 G2/G5/G6 命名。W86 高半/W87 依赖 `maccnt_sync`（§3.4），若它是新文件而不导入 ⇒ Vivado 黑盒（H-4 的既有先例），或 G6/G7 的 xvlog 清单缺件。
- 影响：W86/W87 观测面失效或门编译失败；这正是 FINDINGS H-4 要消灭的"黑盒静默失效"类。
- 建议：新增 `rtl/maccnt_sync.v` 并加入 `P7B_ADD_DATAPATH`（或 `P7B_ADD_DUAL`）、`P7B_MODULE_RESOLVED`、`p11dual_src.f`/`p11merge_src.f`（若 G6 用）以及 `p7bchain_src.f`（若该门编译 DUAL 支）；或明确把它写进已导入的某个文件并在设计中写明。

**N-5（中）G9 的"读侧"文件清单不全：`_proj_pcie` 的板侧取数器仍硬编码 83/0x2B/0x17C。**
- 位置：`DESIGN_v2 §5.2 G9`（`:593`）、`§8`。
- 依据：现读 `_proj_pcie/p6e_snap_check.sh:60,72` 默认 `EXPECT_BID=0x2B` / `SNAP_WORDS=83` / UNIMPL 派生 0x17C；`_proj_pcie/p7b_biz/p7b_snap.sh:85,87` 默认 `NW=83` / `EXPECT_BID=0x2B`；`_proj_pcie/p7b_gate4_negctrl.sh:156` 的 `awk -v NW=83` 硬编码。G9 只点名 `sim/p6e_pcie/tb_p6e_pcie_wrapper.v`、`tb_p6e_pcie_counters.v`、`p7b_biz_win/*`、`apply_readside_bid1c.py`。
- 影响：B-0 身份门/板级取数若用旧默认，会对 0x2C/88 字位流报 BID 不匹配，并把 `0x190` 当越界、把 `0x17C`（新 W87）当"未实现"读 ⇒ 假红/错读。`apply_readside_bid1c.py` 的新阶段是正确机制，但设计未把目标文件/默认值/断言写进 G9。
- 建议：在 G9 明确列出上述 4 个 shell 工具的默认值/标签同步（或声明 apply 新阶段覆盖它们），并加一条"grep 0x0000002B/83/0x17C 缺省已无"的自检门。

**N-6（中）默认体（非 OVL）控制帧 csum init 用已寄存 `lip_r` 会在 start_ack 同拍取到旧连接本地 IP。**
- 位置：`DESIGN_v2 §2.3` 逐用途表第 3 行（`:165`）+ 锁存表（`:177`）。
- 依据：默认体 `csum_init = start_ack || start_data || ring_start`（`rtl/tcp_tx_frame.v:2025` 现读），`csum_init_val` 在 `:2022-2024`，`dip_r <= cam_rd_sip` 在 `:2411` 同一 `always` 的同一沿；设计在 `:2392-2415` 同沿新增 `lip_r <= cam_rd_dip`。因此 start_ack 拍 `csum_init_val` 若用 `lip_r`，读到的是**上一连接/复位值** ⇒ SYN-ACK 的 TCP 伪头源 IP 错（静默，对端丢弃）。OVL 体不受影响（`ctrl_ipcsum/ctrl_tcpcsum` 在 `start_ack+1` 装载，`ctrl_lip` 已稳定）。
- 影响：非 OVL 构建 / G5 默认体臂的 SYN-ACK 校验和错；A-1 的"静默错误"风险清单第 2 条正是这一类。
- 建议：第 3 行默认体改为"同 #2（组合读 `cam_rd_dip`）"，或把默认体的控制帧 init 推到 `start_ack+1`；不要用 `lip_r`。

**N-10（中）W83/W84/W86/W87 在非 DUAL 构建的 tie-off 未写。**
- 位置：`DESIGN_v2 §2.7` 单口/双口表（`:298-307`）、`§3.4` 装配（`:402-406`）、`§3.5`（`:434`）。
- 依据：`SNAP_NW_P6E=88` 与 `snap_dout_all` 顶部 5 项是无条件 localparam/装配；W83/W84 来自"每口 arb 输出"、W86/W87 来自 ch0 FIFO/MAC，这些源在非 DUAL 支不存在。现读矩阵的 `p7b_chain` 门编译宏**不含 `DUAL_SFP_A`** ⇒ 非 DUAL wrapper 会看到 88 字装配但缺 4 个源。
- 影响：G1/默认矩阵编译失败，或被迫在实施时临时补线（与"单口原样"纪律冲突）；`tb_p7b_chain` 的 W83..W87 断言也没有明确期望（应为 0）。
- 建议：在 §2.7 增加非 DUAL 常量表（W83/W84/W86/W87 = 0；W85 仍真；或 W83 = 现役单 arb 输出，若希望保留活动指示），并在 G9 写明 `tb_p7b_chain` 对 0 的断言。

### 低（8 条）

**N-3（低）`P7B_MODULE_RESOLVED` 的 cell-count 看不见黑盒。**
- `§5.3` 的 `get_cells -hier -filter {REF_NAME =~ rx_merge2}` 对"未解析模块"也会返回一个黑盒实例 cell（REF_NAME 保留）⇒ `n1≥1` 不证明解析。真正有牙的是同一段的 synth 日志 `black box`/`8-3491` 检查。建议改用 `get_property IS_BLACKBOX` / `report_black_boxes`，或明确说明 cell-count 只是辅助、日志 grep 才是硬门。

**N-7（低）P2-2 的 `ΔW83 − Δpeer ≤ ΔW45 + ΔW21` 假设窗末已静默。**
- 若快照窗结束时仍有帧在 `txcdc`/MAC FIFO 中未上线，`ΔW83` 比 `Δpeer` 多出的部分不由 W45/W21 解释 ⇒ 等式上界失效。建议 P2-2 明确"取窗前连接关闭/静默 ≥N 拍"，或把在飞帧上界作为第三修正项登记。

**N-8（低）netns 下 `ip -n <ns> exec ethtool` 不是合法命令。**
- `§4.6:551`；应为 `ip netns exec <ns> ethtool -C <if> ...`（`ip -n <ns>` 只适用于 `ip` 自己的对象，`exec` 是 `netns` 对象的子命令）。其余 `ip -n <ns> addr/link/route/neigh` 是合法的。

**N-9（低）L-12 承诺的 `STRICT` 常量断言未落进 G7。**
- `§0.1 L-12` 写"G7/elab 加 `STRICT` 常量断言（wrapper 文本与参数双查）"，但 `§5.2 G7` 行只有 DUAL 组合/签名，无 `STRICT`。建议在 G7 增加"wrapper 文本 `.STRICT(1'b0)` 存在且 `rx_merge2` 实例未传 1"的检查，或把它移到 G2。

**N-11（低）P1 的"乙=0x2C"未被显式标为历史。**
- `p9_dual_sfp_p1_impl_20261018/DESIGN_v5.md:22,245` 逐字"乙位流（0x2C）留到 P3"；v2 把 0x2C 分给甲、乙顺延 0x2D（§0.3 #10 / D2）。`§0.2-6` 只订正了**章节归属**，没有写"P1 的 0x2C 分配已被本件取代"。建议补一行，避免读侧/BID 链把 0x2C 当乙。

**N-12（低）W87 低半 `stat_frames` 16 位饱和在正常速率下 ~82 ms 即到 0xFFFF。**
- `§3.4` 的 `sat16` 语义段写"健康窗（P2-2 正常）应恒 0 或很小"——这对外溢/abort 半成立，但对 `stat_frames` 低半不成立（ch0 10G 约 800k 帧/s ⇒ 65535 帧 ≈82 ms）。建议明确 W87[15:0] 只是"有活动"指示，不作为帧数精确值；或把低半改成一个慢变量。

**N-13（低）G2 `STRICT=1` 负控必须同时给高优先口一个有效帧。**
- `§3.2` 明确 `STRICT=1` 仍是工作保持（高优先口无 `tvalid` 时选另一口）；`§5.2 G2` / `§0.1 M-10` 的"高优先口 `tready` 拉 0"只保证反压，不保证有帧 ⇒ 若只向低优先口注入，merge 会服务低优先口，负控无牙。建议写成"高优先口持有一个有效帧且 `tready=0` ≥N 拍"。

**N-14（低）W79 的语义变化（tap 好帧 → merge 输入 FIFO 接受帧）未同步到窗口权威表/读侧标签。**
- `§3.2-1` 已写 `ch0_rx_tready = ~ch0_fifo_full` ⇒ W79 变成"被 merge 输入 FIFO 接收的好帧数"，FIFO 满丢帧由 W82 计；但 `P7B_BIZ_WINDOW.md:77` 仍写"ch0 好帧数"，G9 只补 W83..W87 的 WLABEL。P2-4 的守恒等式在干净窗（W82=0）仍成立，但读数口径应更新，避免下游把 W79 当 MAC 收帧 oracle。

---

## ③ 反向核对复核（任务 5 条）

| # | 反向核对项 | 结果 | 证据 |
|---|---|---|---|
| 1 | **H-3 的 8 字/64 帧** | **成立** | `hls/src/layer_mac.cpp:282-287`：`tx_payload = max(req_bytes, 46)`，pad 到 46 B 载荷；14 B 以太头 ⇒ 60 B 内容；`slow_tx_adp.v:17-19,136-197` 剥 8 B 前导 + 4 B FCS ⇒ 60 B = 7.5 字 ⇒ **8 字**（末字 tkeep=4 位）；`frame_fifo #(.W(73),.D(512))`（`slow_tx_adp.v:80-88`）⇒ 512/8 = **64 帧**。FINDINGS 的 56 B/7 字/73 帧是**算术滑**，v2 订正正确。 |
| 2 | **H-5 的地址算术** | **成立** | 快照地址 = `0x20 + 4×W`（现读 `P7B_BIZ_WINDOW.md` §1 / wrapper 注释）。W79..W82 = 0x15C/0x160/0x164/0x168 **不动**；W83 0x16C / W84 0x170 / W85 0x174 / W86 0x178 / W87 0x17C；MIR_STATUS/DATA/CTRL/DMA_CNT = 0x180/0x184/0x188/0x18C；UNIMPL = `0x20+4×88+16` = **0x190**。backstop：NW86 ⇒ MIR 0x178..0x184 / UNIMPL 0x188；NW85 ⇒ 0x174..0x180 / 0x184；NW83 ⇒ MIR 0x16C..0x178 / UNIMPL 0x17C —— 均自洽。派单"W79..W82→0x16C..0x178"与"MIR_STATUS→0x178"互相矛盾，v2 的订正正确。 |
| 3 | **H-1 的 9 个 TB** | **成立** | active `tb/` 现读：`tb_app_udp.v:219`（udp_split）/`:311`（udp_tx_cfg）、`tb_udprx_chain.v:232`、`tb_udprx_rate.v:327`、`tb_app_udp_rate.v:162`、`tb_udp_split.v:60`、`tb_udp_tx_guard.v:180`、`tb_udp_rx.v:55`、`tb_udp_echo.v:51` = **9 个例化点 / 8 个文件**，与 v2 清单逐点相同；`frozen/`、`notes/` 副本未列入。 |
| 4 | **H-4 的 `elab_files.f` 运行时生成** | **成立（行号小漂移）** | `_proj_10g/p7b_chain/sim/run_elab_4combo.bat:27` 逐字 `dir /b /s "%ROOT%\rtl\*.v" > elab_files.f`，`:28` 追加 HLS；新 `rtl/*.v` 自动覆盖。v2 写 `:21-24`，实际 `:27-28`（差 3–6 行，不影响机制）。"静态同步三件"现读存在：`sim/p4gates/p7bchain_src.f`（含 HLS 清单自述）、`run_tb_p7b_chain.bat:51-72` 字面清单、G6 manifest 待建。 |
| 5 | **M-3 的 `p4gate.py:498-535` HLS 网表指纹** | **成立** | `p4gate.py:498-505`：`hls_dir = root/k["HLS"]`，`for ext in ("*.v","*.dat")` 收入 `hls`；`:535` `if p in compile_set or p in hls: lines_c.append(ln)` ⇒ 参与 `DIGEST_COMPILE`；FROZEN 判决用 `DIGEST_ALL`（`:695-696`），而 `extra`（`FINGERPRINT_GLOBS`）在 `allset`/`lines_a` 内 ⇒ 追加 `hls/src/*.cpp|*.h`、`hls/run_hls.tcl` 后确实绑定 HLS 源。FINDINGS 的"HLS 网表在指纹外"不成立；v2 的"真正缺 HLS 源/脚本"正确。 |

**附加行号漂移（不改变结论）**：`tb_p7b_chain.v` 几何断言实际 `:1645-1649`（v2 写 `:1641-1649`）；`tb_p7b_chain.v:1647` 的 `0x17C reads 0` 与 v2 的 G9 前置 grep 一致。

---

## ④ 一句总评（证据性结论，不含 PASS/FAIL 裁定）

**P2-甲 v2 对 FINDINGS 的 B-1/H-1..H-8 做到了"无未闭项"：9 项中 6 项已闭、3 项部分闭；点名的 8 项中/低抽核 6 项已闭、2 项部分闭。** 结构选择（A-1、方案②、`rx_merge2`、side FIFO 128、NW 88、地址算术）与源码锚点整体经得起现读回源，反向核对 5 条全部成立（含两处既有 FINDINGS 的算术/事实订正）。但 v2 在**参数化作用域（N-2）**、**默认体控制帧校验和（N-6）**、**新模块导入/解析（N-4）**、**非 DUAL tie-off（N-10）**、**池归还见证（N-1）**、**读侧默认值（N-5）**六处仍会在实施轮直接撞上；其中 N-2/N-6/N-10 是"按现文施工会编不过或静默错"的级别。**可进入实施（附条件）：先修 N-1/N-2/N-4/N-5/N-6/N-10 六条，其余 8 条（N-3/N-7/N-8/N-9/N-11/N-12/N-13/N-14）为低优先，可在同一修订轮或实施轮随手收口；不建议按现文直接开工。**

---

## 回报

- **闭项计数**：FINDINGS 阻断/高 9 项 = **已闭 6 / 部分闭 3 / 未闭 0**；任务点名中/低 8 项 = **已闭 6 / 部分闭 2 / 未闭 0**；合计 17 项 = **已闭 12 / 部分闭 5 / 未闭 0**。
- **未闭项**：无。
- **部分闭项**：B-1（N-1）、H-1（N-2）、H-4（N-3/N-4）、L-8（N-8）、L-12（N-9）。
- **新发现**：14 条（中 6：N-1/N-2/N-4/N-5/N-6/N-10；低 8：N-3/N-7/N-8/N-9/N-11/N-12/N-13/N-14）。
- **反向核对**：5/5 成立（H-3 8 字/64 帧、H-5 地址算术、H-1 9 TB、H-4 elab 运行时、M-3 p4gate HLS 指纹）；两处行号小漂移（`run_elab_4combo.bat:27-28`、`tb_p7b_chain.v:1645-1649`）不影响机制。
- **可实施性**：**可进入实施（附条件）—— 先修 N-1/N-2/N-4/N-5/N-6/N-10；不建议按现文直接开工。**

---

## TL 抽核（2026-10-18 08:5x，逐条回源）

| # | 抽核项 | 结果 |
|---|---|---|
| 1 | N-2：`DESIGN_v2:126-127` 的 `IP_A_5/IP_B_5` 在 `ifdef DUAL_SFP_A` 内；`:219` 无条件引用 | ✓ 成立（非 DUAL 构建会引用未声明标识符） |
| 2 | N-6：默认体 `csum_init_val`（`rtl/tcp_tx_frame.v:2022-2024`）与 `dip_r` 同沿锁存（`:2411`） | ✓ 成立（start_ack 拍用 `lip_r` 会取旧值；应组合读 `cam_rd_dip`） |
| 3 | N-10：v2 §2.7 无非 DUAL 的 W83/W84/W86/W87 常量表；`SNAP_NW=88` 无条件 | ✓ 成立（非 DUAL wrapper 缺 4 个源） |
| 4 | N-1：v2 `:523/:569` 仍以 `ss -ti snd_wnd>0` 作池归还见证；HLS `layer_tcp.cpp:281` 硬编码 0xC000 | ✓ 成立（空判据） |
| 5 | N-4：`maccnt_sync` 在 §3.4 引入；§5.3 import 清单只列 rx_merge2/tx_demux2 | ✓ 成立（漏导入风险） |
| 6 | N-5：`p6e_snap_check.sh` / `p7b_snap.sh` / `p7b_gate4_negctrl.sh` 仍硬编码 0x2B/83/0x17C | ✓ 成立（G9 未列） |
| 7 | N-8：`ip -n <ns> exec ethtool` 非法 | ✓ 成立（应为 `ip netns exec`） |
| 8 | N-12：W87 低半 `sat16(stat_frames)` ~82 ms 饱和 | ✓ 成立（只能当活动指示） |

**抽核结论**：8/8 与报告一致。**下一步 = v2.1 修订（修 N-1/N-2/N-4/N-5/N-6/N-10 + 低 8 条）→ TL 亲核 → 实施。**
