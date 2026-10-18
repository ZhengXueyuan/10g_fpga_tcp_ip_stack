# P11 · P2-甲 设计 v2.1（施工权威）

- 日期：2026-10-18 · 角色 = **实施级设计（只读源码）**：未改任何 RTL/脚本/工具，未跑 xsim/Vivado，未碰板/对端/烧录，未写 git。
- **本文 = `DESIGN_v2.md`（755 行，历史件，原样保留）的最小增量修订版**。基底 = v2；修订 = **N-1..N-14**（FINDINGS_V2 的 14 条新发现：中 6 / 低 8）。v2 保留为历史，不覆盖。
- 写入面：仅本目录（`_proj_10g/notes/p11_p2a_design_20261018/`）。
- 依据：`p11_review_p2a_design_v2_20261018/FINDINGS_V2.md`（17 项 = 已闭 12 / 部分闭 5 / 未闭 0；新发现 N-1..N-14；结论 = **可实施附条件：先修 N-1/N-2/N-4/N-5/N-6/N-10**，低 8 条同轮收口）+ 本件逐条回源核对。
- TL 决策（已定，直接落地）：**B-1/D4 暂按选项 (a)** —— `WIN_Q_MAX` 不传参、保持复位默认 `0xC000`（零 RTL 改动）。
- 判据层口径：**本件不下 PASS/FAIL 裁定**（裁定权在用户/判据所有者）。「未观测到」≠「不存在」；「不支持」≠「证伪」。
- 状态词：**【已证·源码】【已证·构建】【已证·板级】【推断】【未判定】【未测】**。纸面数字一律标 **“纸面”**。
- 行号 = **2026-10-18 现读**（工作树 = P1 实施后的 0x2B 树，`BUILD_ID_V = 32'h0000002B`）。行号会漂移，施工时以**符号名**为准；本件每条都带符号名。
- 方案身份：**S2 单栈**（不采用双栈，用户 2026-10-18 已裁）；出口身份 = **A-1（IP 即身份）**；P2-甲 = 数据面接入 + 双板 IP（**不含**乙镜像）。

> **v2.1 修订摘要**：本件相对 v2 的改动**全部落在 N-1..N-14 的落点**，其余章节逐字保留 v2。新增 **§N 修订对照表**（N-1..N-14 × 落点章节 × 一行改法）。核心 6 条（N-1/N-2/N-4/N-5/N-6/N-10）给出可施工的逐条改法（文件/模块/符号/新文本）；低 8 条同轮收口。若实施轮发现本件与源码事实不符，以现读源码为准并回写本件。

---

## 0. 修订对照表（FINDINGS → v2 处置；v2.1 增量另见 §N）

### 0.1 逐条处置（v2 原文，受影响行加 v2.1 指针）

| FINDINGS 项 | v2 处置 | v2 位置 |
|---|---|---|
| **B-1**（`WIN_Q_MAX=0x6000` 与 P2-1 冲突、与 `app_ctrl` 传参纪律相抵、SYN-ACK `0xC000` 不一致） | **采纳 TL 选项 (a)**：`WIN_Q_MAX` **不传参**、保持复位默认 `0xC000`（零 RTL 改动）。P2-2 改写为“**每口各自能建连 / 身份正确**；不要求两口同时有数据流”；数据流按**逐口顺序**做，并在第二条前用对端 `ss -ti` 的 `snd_wnd > 0` 核池归还（W62 是 RX 占用，不是窗口池直接量）。**“双口同时数据流”登记为待用户裁**（选项 b = `WIN_Q_MAX=0x6000` + P2-1 判据改写 + `0xC000` 对照臂）。**HLS SYN-ACK `0xC000` 与配额一致性**登记为 **P3 前置项**（不伪造改动）。**【v2.1 修订注 N-1】`ss -ti snd_wnd>0` 已降级为无效见证（SYN-ACK 硬编码 0xC000 结构性污染）；见 §4.5 / §5.1 P2-2 / §5.4 B-2。** | §4.5 / §5.1 P2-1/P2-2 / §6.1 D4 |
| **H-1**（新输入端口在既有直接例化 TB 中悬空为 Z） | `cfg_dual` 取消运行端口，改**编译期 parameter `DUAL_IP` + `IP_B`**（`udp_rx`/`udp_split` 走参数，不新增输入口）；`udp_tx_cfg` 的 `peer_my_ip` 是唯一新输入，`PER_CONN_SRC_IP=0` 时参数门控不用；`cfg_sync` 用**后 mux 期望值**（见 M-11）。G1 显式列出 **9 个** active 直接例化点（FINDINGS 的 5 个 + 4 个反向核对新增），逐个接常量/参数；加 `VRFC 10-3645` + `peer_my_ip` 联合断言与运行时无 X 断言。**【v2.1 修订注 N-2】`IP_A_5`/`IP_B_5` 移出 `ifdef`、`DUAL_SFP_A_DEF` 两分支定义；见 §2.2/§2.4。** | §2.4 / §2.7 / §5.2 G1 |
| **H-2**（P2-3 缺静态邻居，可能红在 ARP） | P2-3 加**静态邻居前置**（nsA `ip neigh replace 192.168.100.4 lladdr 00:0a:35:01:fe:c0 nud permanent dev p1`；nsB 对称 `192.168.100.2`）；判据拆两段：① **身份**（p1 对 IP_B 的 ARP who-has 无应答）；② **出口**（p1 pcap 见 SYN + p0 pcap 见 SYN-ACK 且 dst MAC = p1 MAC + p1 收不到 SYN-ACK）。不做静态邻居时只能叫“**ARP 层隔离**”，不能冒充出口判据。 | §4.6 / §5.1 P2-3 / §5.4 B-3 |
| **H-3**（`slow_tx_adp` side FIFO 深度 16 论证错误） | **选“深度 ≥128”**（理由见 §2.5）：`frame_fifo 512 字 / 最小帧 8 字 = 64 帧`（v1 的 7 字/73 帧是算术滑；见 §0.2），128 = 2× 余量；且端口位只在字节 29/31 才知道，前 4 字已写入 ⇒ **“塞进 frame_fifo 未用位”结构上不可行**（W=73 已满）；“commit 门 almost_full 不 commit”会把溢出转成丢帧并引入第二套回滚耦合，不选。单元门断言 `side_fifo_level == committed` 且 `side_ovf==0`，并有 `SIDE_DEPTH=16` 溢出负控与错位负控（必须红）。 | §2.5 / §5.2 G4 |
| **H-4**（构建 tcl 显式导入清单漏新件） | 在 `P7B_ADD_DATAPATH`（或新 `P7B_ADD_DUAL`）加两行 `import_files`：`rtl/rx_merge2.v`、`rtl/tx_demux2.v`；构建后加**模块解析断言**（`P7B_MODULE_RESOLVED rx_merge2=<n> tx_demux2=<n>`，0 或黑盒 = 硬失败）；G6 manifest 同步。**反向核对**：`run_elab_4combo.bat` 的 `elab_files.f` 是 `dir /b /s rtl\*.v` **运行时生成**，新件自动覆盖；需静态同步的是 `sim/p4gates/p7bchain_src.f` 与 G6 的 xvlog 字面清单。**【v2.1 修订注 N-3/N-4】模块解析必须用 `IS_BLACKBOX`/`report_black_boxes`（cell-count 对黑盒也返回）；`maccnt_sync` 是第三个新件，必须同批导入/断言/清单；见 §3.4/§5.3。** | §5.3 / §5.2 G6/G7 |
| **H-5**（`tb_p7b_chain.v` 硬编码 0x2B 几何） | 把 `tb_p7b_chain.v` 加入 G9 几何更新清单；G1 改称“**编辑后回归**”；构建前置核 `grep -n "0x17C reads 0" tb_p7b_chain.v` 为空（旧未实现断言必须消失）。**反向核对（地址算术）**：追加字只落末端，**W79..W82 地址不变（仍 0x15C..0x168）**；新几何 = W83 0x16C / W84 0x170 / W85 0x174 / W86 0x178 / W87 0x17C / MIR 0x180..0x18C / UNIMPL 0x190。FINDINGS 与派单把 W79..W82 写成 0x16C..0x178 是错的（见 §0.2-2）。**【v2.1 修订注 N-5/N-10/N-14】G9 增补 4 个 `_proj_pcie` 读侧工具默认值与 `apply_readside` 0x2C 阶段；非 DUAL 的 W83/W84/W86/W87 tie-off 见 §2.7；W79 标签口径见 §5.2 G9。** | §5.2 G9/G1 / §5.3 |
| **H-6**（G6 若 `force txsrc_*` 则 A-1 TX 全链无行为门） | G6 分两臂：**真实生产者臂**（驱动 `txin_*`/`app2_*` 或三个 demux 输入 `tx_*`/`utx2_*`/`stx_*`，走 `tcp_tx_frame`/`udp_tx_frame`/`slow_tx_adp`）与 **HLS 真实握手臂**（M-13）；`force txsrc_*` 只保留为 MAC 接线臂。断言每口 W83/W84、每帧 `o_port` 与帧头源 IP 一致、跨口不串；`force` 臂单独记结果。 | §5.2 G6 |
| **H-7**（观测仅 3 字偏离“开发期全量”） | **显式报用户**（§6.1 D12 登记为偏离）。v2 加 **5 个便宜分口观测字**：W83/W84（每口 TX 帧）、W85（classify 总帧）、**W86 = `{ch0_rxcdc_ovf_dp[15:0], ch0_txcdc_ovf[15:0]}`（16 位饱和，RX 侧经事件镜像到 dp）**、**W87 = `{ch0_mac_tx_abort_dp[15:0], ch0_mac_tx_frames_dp[15:0]}`（16 位饱和，经事件镜像到 dp）**；几何 **NW 88**、MIR `0x180..0x18C`、UNIMPL `0x190`。**per-port merge 帧/丢帧不另加字**：入口已有 W79/W0、出口有 W85，merge 无内部丢帧路径，上游溢出由 W82/W4 与 W86/W38 覆盖（理由见 §3.4）。**【v2.1 修订注 N-12】W87[15:0] 在 10G 正常速率下 ~82 ms 饱和 ⇒ 只作“有活动”指示，不作精确帧数；见 §3.4。** | §3.4 / §3.5 / §6.1 D12 |
| **H-8**（P2-2 缺回卷与 pre-FIFO 修正） | P2-2 对账式改写：`ΔW83/ΔW84` 为 **32 位 @156.25 MHz ⇒ 27.487 s 回卷**；**差值一律 mod 2³²、记 raw + k**；窗 `<27 s` 或分窗。修正项：ch1 `Δpeer_p1 ≤ ΔW83` 且 `ΔW83 − Δpeer_p1 ≤ ΔW45(字) + ΔW21(帧)`；ch0 同理用 **W86 低 16 位 / W87 高 16 位**（饱和计数，饱和后只记“≥0xFFFF”）；`port_rx_*` 写“**跨系统口径**”（L-6）。ch0 abort 在 v2 已由 W87 可观测（v1 的“未观测到”由此关闭）。**【v2.1 修订注 N-7】上界假设“窗末已静默”必须显式化：取窗前静默 ≥N_QUIET，或加第三修正项 `INFLIGHT_MAX_FRAMES`；见 §5.1 P2-2。** | §5.1 P2-2 / §3.4 |
| **M-1**（HLS `cfg_write` 签名/调用点、`local_ip` 保留语义） | 采纳：`cfg_write` 增 `uint32_t local_ip` 参数（`w[2]=local_ip`）；签名 `:165-181`；调用点 `:609/637/663/677/699/721` 全改，**DEL 传 0、两个 ADD 传 `c.local_ip`**；`tcp_conn_t` 加 `local_ip`；`tcp_find(port, ip, local_ip)`；RST 循环 `:631-645` 加 `local_ip == ip_rx.dst_ip`；`local_ip` 与 `peer_ip/peer_port` **同寿**（RTO 释放槽保留，新连接覆盖）；G8 加 RST-to-released-slot 用例。 | §4.2 / §5.2 G8 |
| **M-2**（canonical HLS 默认构建也接受 IP_B） | 采纳并显式化：**一个 canonical netlist**（`-DBOARD_IP_DUAL=1`）被所有构建共用 ⇒ 默认单口构建的 HLS **也接受 IP_B**（`dst=IP_B` 的 ARP/ICMP/UDP/TCP 会应答）。对 `dst=IP0` 的回包与旧网表**功能等价**（G8 csim 逐字节）；对 `dst=IP1` 的额外接受是设计意图。若要位级不变只能走双输出目录（不选，登记为备选）。G8 加“dual 接受 IP_B / legacy 丢弃 IP_B”两二进制 csim。 | §4.4 / §5.1 P2-9 / §5.2 G8 |
| **M-3**（HLS 在矩阵指纹之外） | **反向核对**：`p4gate.py:498-535` **已经把 HLS 网表 `.v/.dat`（`paths.txt` 的 `HLS=` 路径）纳入指纹** ⇒ “22/22 FROZEN 不绑定 HLS 字节”不成立；真正缺的是 **HLS 源与 `run_hls.tcl`**。v2：`paths.txt` 的 `FINGERPRINT_GLOBS` 追加 `hls\src\*.cpp;hls\src\*.h;hls\run_hls.tcl`；构建/门日志各记 `HLS_NET_HASH`（网表目录 sha256）与 `HLS_SRC_HASH`。 | §5.2 G10 / §5.3 |
| **M-4**（`elab_files.f`/G7 签名/DUAL 正控） | `run_elab_4combo.bat` 的 `elab_files.f` 是运行时 `dir /b /s rtl\*.v` 生成（反向核对），无需手工加件；**G7 组合 7→12**（原 7 + 4 条 DUAL 负控 + 1 条 DUAL 正控），`findstr` 签名表扩到 6 个（两个 SFP2 + 四个 DUAL）；加 `DUAL+P7B+A+DP+APP=ok` 正控。**【v2.1 修订注 N-9】G7 另加 `.STRICT(1'b0)` 常量断言；见 §5.2 G7。** | §5.2 G7 |
| **M-5**（G2–G5 未进常驻矩阵） | 至少注册 **G2（rx_merge2）与 G5（tcp_tx_srcip）**，连同 G6（双口全链）⇒ 矩阵 **21→24**；G3/G4 登记为“独立门，未进矩阵”的债务。G10 计数写实际注册数 24。 | §5.2 G10 |
| **M-6**（P2-4 守恒律符号/逻辑错） | 改写：**干净窗等式** `ΔW85 == ΔW79 + ΔW0` 仅在 `ΔW81=0`（ch0 CRC 错）、`ΔW82=0`（ch0 丢）、`ΔW4=0`（ch1 丢）且无 TERM 时成立；否则 `ΔW85 − (ΔW79+ΔW0) = 坏帧 + TERM ≥ 0`，两项**不可分观测**，只记残差、不判。**W85 = `(cls_stat_fast + cls_stat_slow)[31:0]`**（33 位和显式截断，L-5）。P2-4 主判据 = 两口都前进 + 每口 drop 可读 + 公平，不用守恒律当 oracle。**【v2.1 修订注 N-14】W79 语义 = “merge 输入 FIFO 接受的好帧数”；FIFO 满丢帧由 W82 计；见 §5.1 P2-4/§5.2 G9。** | §5.1 P2-4 / §3.4 |
| **M-7 / M-8**（`WIN_Q_MAX` 传参与 SYN-ACK 不一致） | 并入 B-1：**不传参**（选项 a）；SYN-ACK `0xC000` 与配额一致性 = **P3 前置项**，P2 不伪造。 | §4.5 / §6.1 D4 |
| **M-9**（merge 空泡未写进 P2-1 预期差值） | P2-1 预登记 **≤0.5% 结构性差值**（大帧 193 拍 + 1 拍仲裁），**主口径 = 板内 W43/W20 + W51/W52**（不依赖主机墙钟），对端 NIC 作次口径；`W84 Δ=0` 必须与 W83/对端 NIC 配对，且 P2-2 提供“W84 能动的正控”以消除空判据。 | §5.1 P2-1 |
| **M-10**（G2 STRICT 负对照可能无牙） | 采纳：G2 的负控实例把 `DEPTH` 参数化到 **4**，并**持续注入 ≥2 个最大帧**到低优先口、同时把高优先口 `tready` 拉 0 ≥N 拍；断言低优先口 `tready` 持续 0 且 `ovf` 增长。正臂同时断言逐帧 RR 交替。**【v2.1 修订注 N-13】负控必须同时给高优先口一个**有效帧**且 `tready=0` ≥N 拍（否则工作保持的 STRICT 仍服务低优先口，负控无牙）；见 §5.2 G2。** | §5.2 G2 |
| **M-11**（`cfg_sync` 新项必须用后 mux 期望值） | 采纳：`PER_CONN_SRC_IP=1` 时 `cfg_sync` 比较 `o_src_ip == peer_my_ip_r` 且 `o_port == (peer_my_ip_r == IP_B)`；`=0` 时比较 `o_src_ip == cfg_my_ip` 且 `o_port == 1'b0`。无条件加 `peer_my_ip` 会让单口永久 deny。 | §2.4 |
| **M-12**（`o_port` 稳定性只在 demux 侧断言） | 采纳：G5/G6 在**生产者侧**断言 `tvalid && !tready` 期间 `o_port` 逐拍不变（`tcp_tx_frame`/`udp_tx_cfg`/`slow_tx_adp` 各一条）；`tx_demux2` 另做帧首锁存 + `stat_port_change`。 | §2.6 / §5.2 G5/G6 |
| **M-13**（G6 是否走 HLS 握手未说明） | 采纳：G6 两臂分开记 —— **臂 A 真实 HLS 握手**（ARP/ICMP/SYN-ACK 走 `slow_tx_adp`，用双 IP 重综合网表）与 **臂 B force 快臂**（只测接线）。 | §5.2 G6 |
| **L-1**（`cam_rd_port` 用 `rb_id`） | 采纳：直接写 `cam_port_arr[cam_rd_id]`（现读 `cam_rd_id = rb_id`，未来 mux 改动不分叉）。 | §2.2 |
| **L-2**（`dont_touch` 空闲 FF 只在 DUAL 删 assign） | 采纳：`tx_mii_d_0/c_0` 的 `dont_touch` **寄存器声明本身**包 `ifndef DUAL_SFP_A`，不只删 assign，避免 72 FF 空转。 | §3.1 / §3.3 |
| **L-3**（“网表逐位相同”措辞） | 采纳：`PER_CONN_SRC_IP=0` 改称“**行为等价**”（折叠后的 mux 可能改变网表）。 | §2.3 / §2.7 |
| **L-4**（端口位数组/`o_port` 复位值） | 采纳：`cam_port_arr` 复位 0；三处 `o_port` 复位 0（`tcp_tx_frame`/`udp_tx_cfg`/`slow_tx_adp`）。 | §2.2 / §2.3 / §2.4 / §2.5 |
| **L-5**（W85 33 位和） | 采纳：W85 显式 `[31:0]` 截断；差值 mod 2³² 记 raw+k。 | §3.4 / §5.1 P2-2 |
| **L-6**（`port_rx_*` 同源） | 采纳：写“**跨系统口径**”（板内 RTL 计数 vs 对端内核/NIC 计数），不是“两条独立硬件计数”。 | §5.1 P2-2 / §5.4 |
| **L-7**（P2-6 “W83 平”被周期帧打破） | 采纳：P2-6 用**短窗 + 背景率预取**（HELLO/ARP 由慢路径 W7 计），主判据 = 每口 pcap；`ΔW84 ≥ N_app`，`ΔW83 ≤ background_max + 容差`，登记残差。 | §5.1 P2-6 |
| **L-8**（netns 下 `nmcli` 不适用） | 采纳：`nmcli device set <if> managed no` 在**移入 netns 之前**于根 ns 执行；移入后用 `ip -n <ns> link/ethtool`，不再用 nmcli。**【v2.1 修订注 N-8】`ip -n <ns> exec ethtool` 非法 ⇒ 改 `ip netns exec <ns> ethtool -C ...`；见 §4.6。** | §4.6 |
| **L-9**（`arp_send_request` SPA=IP0） | 采纳并登记：`ACTIVE_CONNECT=0` 下无害；若将来打开主动连接，ARP who-has 会从 ch1 发出而无视目标口。 | §4.2 / §6.3 |
| **L-10**（HLS TX 不加 VLAN 的 TPID 自检） | 采纳：`slow_tx_adp` 提取器看到 `0x8100/0x88A8` 置 `vlan_seen` sticky 并强制 `o_port=0`；G4 负控注入 VLAN 帧必须被抓到。 | §2.5 / §5.2 G4 |
| **L-11**（IGMP 措辞） | 订正：分发在 `udp_echo.cpp:172-173` 是**活的**；不可达因 `layer_ip.cpp:76-81` 只放行 board IP/0xFFFFFFFF（组播 224.x 被拒）。改法仍是“死代码一致性改”。 | §4.2 |
| **L-12**（`rx_merge2.STRICT` hard-tie） | 采纳：wrapper 例化 `.STRICT(1'b0)` 硬接；G2 另例化 `STRICT=1` 只做负控；G7/elab 加 `STRICT` 常量断言（wrapper 文本与参数双查）。**【v2.1 修订注 N-9】该常量断言在 v2 G7 行漏落，v2.1 补进 §5.2 G7。** | §3.2 / §5.2 G2 |
| **事实核 5 处 ±1 行号** | 订正为：p7bdp 末条 assign `:4455`；`ring_start` `:1198` 起；`start_ack` `:1313-1345`；活帧首拍 `:1345-1362`；ch0 RX 复位 `:692-699`。 | §0.2 / 附录 A |
| **事实核 §1.3 章节归属** | 订正：`0x2C 留给 P3` 的语句在 `DESIGN_v5.md` **§0（`:22`）与 §5.3（`:245`）**，不在 §1.3。 | §0.2-6 |
| **事实核 IGMP 机制** | 见 L-11。 | §4.2 |
| **plan §0.5 注** | 已在 `p9_dual_sfp_plan_20261017/DESIGN.md` §0.5 末尾追加一行（2026-10-18 §10-122 用户改裁 A-1；§0.5-2b 的 CAM+1 位+学习表按历史读）。 | plan §0.5 |

### 0.2 反向核对（与 FINDINGS / 派单描述不符，如实登记）

1. **H-3 的最小帧字数**：HLS `layer_mac.cpp:282-287` 的 pad 是“**46 字节最小载荷**”（`tx_payload = max(req_bytes,46)`），加 14 字节以太头 = **60 B 内容**，再加 4 B FCS = 64 B。`slow_tx_adp` 剥 FCS 后内容 = **60 B = 7.5 字 ⇒ 8 字（末字 tkeep 4 位）**，`frame_fifo 512/8 = 64` 帧，不是 FINDINGS 写的 56 B/7 字/73 帧。结论不变（深度 16 仍远不足），v2 按 **64 帧**论证。
2. **H-5 的地址算术**：快照字地址 = `0x20 + 4×word_index`；新增字只加在**末端**，已有 W79..W82 **不移动**（仍 `0x15C/0x160/0x164/0x168`）。派单文字“W79..W82→0x16C..0x178”与“MIR_STATUS→0x178”互相矛盾（0x178 在 NW=86 下是 **MIR_STATUS** 本身，不是 W82；W82 仍在 0x168）。v2 采用 **NW=88** 几何（见 §3.5），MIR_STATUS = `0x180`，UNIMPL = `0x190`。
3. **H-1 的直接例化点数**：FINDINGS 列 5 个；现读 active `tb/` 下还有 `tb/tb_udp_split.v:60`（`udp_split`）、`tb/tb_udp_tx_guard.v:180`（`udp_tx_cfg`）、`tb/tb_udp_rx.v:55`（`udp_rx`）、`tb/tb_udp_echo.v:51`（`udp_rx`）。v2 按 **9 个**列，全部接常量/参数；`frozen/` 与 `notes/` 副本不碰。
4. **H-4 的 `elab_files.f`**：`run_elab_4combo.bat:21-24` 用 `dir /b /s %ROOT%\rtl\*.v` **运行时生成**，不是静态清单；新件自动被 elab 组合覆盖。需要静态同步的是 `sim/p4gates/p7bchain_src.f`、`_proj_10g/p7b_chain/sim/run_tb_p7b_chain.bat` 的 xvlog 字面清单与 G6 自己的 manifest。
5. **M-3 的 HLS 指纹**：`sim/p4gates/p4gate.py:498-535` 已把 `HLS` 路径下的 `*.v/*.dat` 计入 `compile_set/hls` 并参与 `digest_c`；所以矩阵指纹**已经绑定 HLS 网表字节**。缺的是 **HLS 源/脚本**（`hls/src/*.cpp|*.h`、`hls/run_hls.tcl`），v2 补进 `FINGERPRINT_GLOBS`。
6. **§1.3 归属**：`DESIGN_v5.md:22`（§0 表）与 `:245`（§5.3）有“乙位流（0x2C）留到 P3”；§1.3（`:61-65`）无 0x2C。v2 引用统一写 **§0 + §5.3**。
7. **【v2.1 新增 N-11】P1 的 0x2C 分配已作废**：`p9_dual_sfp_p1_impl_20261018/DESIGN_v5.md:22` 逐字“乙位流（0x2C）留到 P3”、`:245` 逐字“乙位流（0x2C）留到 P3”。本件把 **甲 = 0x2C**、**乙顺延 0x2D**（§0.3 #10 / §5.3）；读侧/BID 链**不得再把 0x2C 当乙**。P1 原文按“历史分配”读，不改写原文。
8. **【v2.1 新增 N-6 源码补核】CAM 字段语义与 v2 标注一致**：`rtl/tcp_cam.v:26-27` 逐字“rd_sip = 对端 IP (发送帧的 dst IP!), rd_dip = 本地 IP”；`slow_cfg_adp.v:148` 写 `cam_cfg_dip <= w2`，而 `w2` = HLS `local_ip`。⇒ v2 §2.3 的“`cam_rd_dip` = 该连接的本地 IP”标注**正确**；但 v2 逐用途表第 3 行“默认体控制帧 csum init 用 `lip_r`”与源码的时间关系不符（`csum_init` 含 `start_ack`，`lip_r` 同沿才锁存）⇒ 本件订正为**组合读 `cam_rd_dip`**（§2.3）。**未发现 v2 的 `cam_rd_sip`/`cam_rd_dip` 语义标注错误**。
9. **【v2.1 新增 N-1 源码补核】零窗探针有正见证**：`rtl/tcp_rx.v:364-370` 的 `ackresp` 含 `(seq_eq && !win_ok)` ⇒ 对“顺序段但窗不足”**会回纯 ACK**（`plen_w != 0` 为条件）。⇒ 第二条连接发 1 字节探针时，即使 `winq=0` 也能在 pcap 上看到板侧 fast-path 的纯 ACK（win=0），不必依赖“没有 ACK”这种缺席推断。`app_ctrl.v:281-283` 注释逐字“winq=0 ⇒ 通告窗 0 ⇒ 线上每帧 win=0 (TCB rcv_wnd=0000) —— 永久而非瞬态”。**这条把 N-1 的见证从“只能看 >0”升级为“0 与 >0 都可判”**。
10. **【v2.1 新增 N-2 源码补核】`DUAL_SFP_A_DEF` 确无定义**：现树 `grep -rn "DUAL_SFP_A_DEF\|IP_A_5\|IP_B_5" rtl board tb sim` **0 命中**（2026-10-18 现读）⇒ v2 `:219` 的无条件引用在非 DUAL 构建是未声明标识符，xvlog/synth 硬错。FINDINGS 的描述成立。

### 0.3 一页结论（v2；v2.1 增补见行内注）

| # | 结论 | 等级 |
|---|---|---|
| 1 | **基线 = 0x2B**：`WNS +0.048 / WHS +0.010 / 三类失败端点 0/0/0`，placed **80,024 LUT / 76,888 FF / 348 BRAM / 1 URAM**。0x2A 的 0.61% 按“历史代”读。 | 【已证·构建】 |
| 2 | **A-1 映射钉死**：**ch1 = J8 = IP_A = 192.168.100.2（端口位 0）**；**ch0 = J7 = IP_B = 192.168.100.4（端口位 1）**；`port = (CAM.dip == IP_B)`。单口只插 J8 时所有端口位恒 0 ⇒ 全走现役 ch1 链。 | 【已证·源码】+本件口径 |
| 3 | **端口位来源 = wrapper 16 槽 1 位数组**，与 CAM 写 mux 同拍同址同源；`slow_cfg_adp`/`tcb`/`tcp_cam` 零改动；读口 `cam_port_arr[cam_rd_id]`（L-1）。 | 【已证·源码】+【推断】 |
| 4 | **TX 选口 = 方案 ②**（demux 前移 + 每口复制 arb 树）：`tx_arb.v` 源码零改动；新增 `tx_demux2` + 每口两级 arb。方案 ① 被否（改 `tx_arb` 端口表与两个直接 TB）；方案 ③ 登记待裁。 | 【已证·源码】+【推断】 |
| 5 | **A-1 TX 三项用途**（IP 头源 IP、IP 校验和、TCP 伪头种子）在 `tcp_tx_frame` 的 OVL/默认两体 × 数据/控制/重放全部要改；用 `PER_CONN_SRC_IP`（默认 0）门控。`o_port` 帧内锁存、生产者侧稳定。**【v2.1 N-6】默认体控制帧的 csum init 必须用组合 `cam_rd_dip`，禁用 `lip_r`。** | 【已证·源码】+【推断】 |
| 6 | **RX 合并 = 新件 `rx_merge2`**：两路 `fifo_async(76×256)` → `dp_clk` 单域帧级工作保持 RR（`STRICT` 硬接 0）→ `vlan_strip`。每帧 1 拍仲裁气泡（大帧约 0.5%，最小帧约 11%）。merge 无内部丢帧。 | 【已证·源码】+【推断】 |
| 7 | **观测 = 5 个新字**（W83..W87，全部进既有 p7bdp 束，不新增 CDC 束）：W83/W84 每口 TX 帧、W85 classify 总帧、W86 ch0 RX/TX FIFO 溢出（16+16 饱和）、W87 ch0 MAC TX 帧/abort（16+16 饱和）。几何 **NW 88 / UNIMPL 0x190 / MIR 0x180..0x18C**。这是对“开发期全量”的**偏离**，显式报用户。**【v2.1 N-12】W87[15:0] 只作活动指示。** | 【已证·源码】+【推断】 |
| 8 | **B-1/D4 = 选项 (a)**：`WIN_Q_MAX` 不传参、复位默认 `0xC000`；P2-2 只要每口各自建连/身份正确，数据流逐口顺序；双口同时数据流待用户裁；HLS SYN-ACK `0xC000` 一致性 = P3 前置。**【v2.1 N-1】池归还见证改为 fast-path 纯 ACK 双探针 pcap（win 0/＞0 都可判）。** | 【已证·源码】+TL 决策 |
| 9 | **HLS 双 IP = 一个 canonical netlist**（`-DBOARD_IP_DUAL=1`）；`dst=IP0` 功能等价，`dst=IP1` 在默认构建也被接受（M-2 显式登记）。 | 【推断】 |
| 10 | **BID = 0x2C**（甲）；乙顺延 0x2D。构建宏 = 既有 8 宏 + `DUAL_SFP_A=1`。**【v2.1 N-11】P1 `DESIGN_v5.md` 的“乙 = 0x2C”按历史读、已作废。** | 【推断】+登记 |
| 11 | **最大三个风险**：① 0x2B 余量 0.75%，A-1 的 `cam_rd_dip` 进校验和锥 + 5 字快照（+480 FF 纸面）+ 第二 MAC/arb/FIFO；② `tcp_tx_frame` 源 IP/校验和在 6 条路径上任一漏改 ⇒ 对端静默丢弃；③ HLS 重综合的全局面 + canonical netlist 对 IP_B 的新接受语义。 | 【推断】 |

### §N v2.1 修订对照表（N-1..N-14）

> 本表 = 派单要求的 §N。**落点章节**列给出 v2.1 中的位置；**改法**列一句话。核心 6 条（N-1/N-2/N-4/N-5/N-6/N-10）的完整施工文本在对应章节，本表不替代。

| N | 级别 | 落点章节（v2.1） | 一句话改法 |
|---|---|---|---|
| **N-1** | 中 | §4.5 / §5.1 P2-2 / §5.4 B-2 | 池归还见证改为“**第二条连接上 1 字节探针 ×2 → pcap 抓 fast-path 纯 ACK，读 `tcp.win`**”：`win==0` ⇒ 未归还；`win>0` ⇒ 已归还；**帧源必须按 flags/seq/ack + 滚动 `ip.id` 判别**（HLS 的 IP ID 恒 0、SYN-ACK win 恒 0xC000，故“值恰好 0xC000”不构成证据）；“建连后立刻读 `ss -ti`”降级为无效见证；`ss -ti` 只在已抓到 fast-path ACK 后作二次核对；sim/G6/G8 用 `app_ctrl 0x97 pool`/`0x9A winq[0]` 作辅助。 |
| **N-2** | 中 | §2.2 / §2.4 / §2.7 | `IP_A_5`/`IP_B_5` **移出 `ifdef DUAL_SFP_A`、无条件 localparam**；新增 `DUAL_SFP_A_DEF` 的 `ifdef/else` 两支（`1'b1`/`1'b0`）；全部参数引用点（`udp_split`/`udp_tx_cfg`/`tcp_tx_frame`/`slow_tx_adp`）在两种宏态下逐点核对并列表。 |
| **N-3** | 低 | §5.3 | 模块解析硬门改为 **`get_property IS_BLACKBOX` / `report_black_boxes` + synth 日志 `black box`/`8-3491` 0 命中**；cell-count 只作辅助并在文本里明说。 |
| **N-4** | 中 | §3.4 / §5.3 / §8 | 新增 **`rtl/maccnt_sync.v`**（4 相 toggle/ack 事件镜像，禁止裸 2FF 多比特）；加入 `P7B_ADD_DATAPATH`（或 `P7B_ADD_DUAL`）、`P7B_MODULE_RESOLVED`、`p11dual_src.f`、`p7bchain_src.f`（若该门编 DUAL 支）、G10 manifest 与 §8 变更表；W87 用一个 64 位实例（frames+abort 同采样）。 |
| **N-5** | 中 | §5.2 G9 / §5.3 / §8 | G9 显式列出 **4 个读侧工具**（`p6e_snap_check.sh`、`p7b_snap.sh`、`p7b_gate4_negctrl.sh`、`apply_readside_bid1c.py` 新阶段 0x2C）的默认值/标签同步；0x2C = **NW 88 / UNIMPL 0x190 / W83..W87 标签**；加“缺省赋值行 grep”自检门（历史注释行列入例外清单）。 |
| **N-6** | 中 | §2.3 | 逐用途表第 3 行默认体改为**组合读 `cam_rd_dip`**（`PER_CONN_SRC_IP ? cam_rd_dip : cfg_src_ip`），**明确禁止 `lip_r`**；OVL 用新 `ctrl_lip`（`start_ack` 沿锁存，`start_ack+1` 装载校验和）；补 CAM 字段语义（`rd_sip` = 对端 IP / `rd_dip` = 本地 IP）。 |
| **N-7** | 低 | §5.1 P2-2 | `ΔW83 − Δpeer ≤ ΔW45 + ΔW21` 增加前件：**取窗前连接关闭/静默 ≥N_QUIET**（连续两次快照 `ΔW83=0`，间隔 ≥1 ms；建议再等 ≥2×txcdc 深度/MAC 帧长对应的 tx 拍）；不能静默时登记第三修正项 **`INFLIGHT_MAX_FRAMES = 33`**（256/8 + 1，保守纸面）。 |
| **N-8** | 低 | §4.6 | `ip -n <ns> exec ethtool ...` 非法 ⇒ **`ip netns exec <ns> ethtool -C ...`**；`ip -n <ns> addr/link/route/neigh` 合法，保留；`sysctl` 明确在 ns 内执行。 |
| **N-9** | 低 | §5.2 G7 | G7 增加静态断言：wrapper 文本 **`.STRICT(1'b0)` 命中且 `.STRICT(1'b1)` 0 命中**（`rx_merge2` 实例不得传 1）；失败 = G7 硬失败。 |
| **N-10** | 中 | §2.7 / §3.4 / §3.5 / §5.2 G9 | 非 DUAL 构建的 **W83/W84/W86/W87 = 0、W85 仍真**（`snap_dout_all` 顶部 5 项按 `ifdef` 给常量）；G9 对 `tb_p7b_chain` 加非 DUAL 断言（W83/W84/W86/W87 ≡ 0，W85 跟随 classify）。 |
| **N-11** | 低 | §0.2-7 / §0.3 #10 / §5.3 | 补一行：**P1 `DESIGN_v5.md` 的“乙 = 0x2C”作废；甲 = 0x2C、乙顺延 0x2D**；读侧/BID 链不得把 0x2C 当乙。 |
| **N-12** | 低 | §3.4 | W87[15:0] `sat16(stat_frames)` 在 10G 正常速率下 **~81.9 ms 饱和**（65535/800k fps）⇒ 明确“**仅作有活动指示、不作精确帧数/速率判据**”；精确 per-port TX 帧数用 W83/W84（32 位，27.487 s 回卷）。 |
| **N-13** | 低 | §5.2 G2 | G2 `STRICT=1` 负控必须**同时给高优先口一个有效帧且 `tready=0` ≥N 拍**，再向低优先口持续注入 ≥2 最大帧；断言低优先口 `tready` 持续 0 且 `ovf` 增长。 |
| **N-14** | 低 | §5.1 P2-4 / §5.2 G9 | W79 口径同步为“**merge 输入 FIFO 接受的好帧数**”（`ch0_rx_tready = ~ch0_fifo_full`）；`P7B_BIZ_WINDOW.md:77` 的 WLABEL 同步；P2-4 注明 **FIFO 满丢帧由 W82 计**。 |

### §N.1 v2.1-errata 指针表（2026-10-18 实施红队回灌；权威处置 = **附录 E**）

> 本表只做“正文 → 附录 E 条目”的导航；**不重写正文原文**（原文按当时口径读，errata 条目给现行口径）。

| 正文位置 | 受影响条目 | 一句话现行口径 |
|---|---|---|
| §2.7（`PER_PORT=0` ⇒ 提取逻辑不例化） | **D-6 / F-11** | 已按此实现：提取寄存器/更新块整体进 `generate if (PER_PORT)`；单口零寄存器 |
| §3.2 第 5 条（merge 接 `dp_rst_n`） | **F-19** | 现接板级 `reset_n`（与两路 FIFO rd 侧同源；防 MMCM 失锁时 merge 与 FIFO 指针不同代） |
| §3.2 / §6.3（无半帧看门狗） | **F-2** | `rx_merge2` 新增 `TO_CYCLES`（wrapper 传 4096）；**需用户追认**（附录 E §E-2） |
| §3.4（`maccnt_sync` 采样节流 = 每 256 拍） | **D-12 / F-18** | 已实现：源域 8 位自由计数 rollover ⇒ 每 256 源拍一个 `src_tick` |
| §3.4 / §5.1 P2-2（W86 “应恒 0” / `sat16(ovf)` 修正项） | **D-1 / D-2 / F-4** | W86 = **AXIS 反压拍数**（不是丢字）；P2-2 删掉该修正项，改用 W82/W4 MAC drop |
| §5.2 G1 行（`VRFC 10-3645` + `$isunknown`） | **D-5 / F-7** | 已实现：G5/G6 bat 定向断言 + `tb_app_udp.v` 运行期 `$isunknown(o_port/cfg_sync)` |
| §5.2 G2 行 | — | 已实现（含 N-13 负控）；另加 **F-2 看门狗臂**（p1 半帧 ⇒ stat_abort 增、p0 帧仍出） |
| §5.2 G3 行（“端口反转变异红”） | **D-9 / F-12** | 已实现**真变异**：第二份 `tx_demux2` 把 d0/d1 交叉接线，同一判据必红 |
| §5.2 G6 行（maccnt 活性 / 每帧 `o_port` 与源 IP 一致） | **D-3 / D-7 / F-3 / F-13** | maccnt 改斜坡追踪+冻结+强制常 0 变异；UDP 侧新增臂 D（`peer_my_ip` ⇒ `o_src_ip/o_port`） |
| §5.2 G7 行（c8 = DUAL+P7B+A+DP+APP） | **D-11 / F-9** | c8 = **真构建 9 宏组合（含 `SFP2_MODE_A`）**；另加 c13 = DUAL 无 `SFP2_MODE_A` 正控；G6 DEFS 同改 |
| §5.3（HLS 双哈希 / synth 日志 grep 才是硬门） | **D-8 / F-6** | 已落进 `board/build_p7b_ku5p.tcl`（`HLS_SRC_HASH`/`HLS_NET_HASH` + `P7B_BLACKBOX_LOG_HITS=0` 硬门） |
| §5.3 N-5 读侧清单（4 文件） | **D-4 / F-1 / F-5** | 清单补全到 **20 文件**（含 6 gate4/夹具 + 3 TB + 2 个 j6 几何档表）；0x2C 阶段改**显式增量** |
| §5.4 B-6（RX 合并公平） | **F-4** | 加“ch0 灌流时 W86[15:0] ≈ 反压拍数（不是丢字）”的负对照（附录 E §E-3） |
| 报告 §4 G5 归档（`gates/g5_run.log` 全红） | **D-13 / F-10** | 旧件已改名 `g5_run.SUPERSEDED_fail_0814.log`；原因与修法见 FIX_REPORT §F-10 |

---

## 1. 前提与边界

- 用户已裁：**S2 单栈**（放弃 2×10G 同时满速）；P3 判据 = **聚合 ≤ ~9.5 Gbps + 每口工作保持公平份额 + 丢帧/背压可读**（`p9_dual_sfp_p1_impl_20261018/DESIGN_v5.md` §8）。
- 甲 = 两端口都有**独立板 IP**；P2-甲 = 数据面接入 + 双板 IP，**不含乙镜像**（乙 = P3，位流顺延 0x2D）。**【v2.1 N-11】P1 文件里“乙 = 0x2C”是历史分配，已作废。**
- P1 的观测（W76..W82）**全部保留**；P2 新增 5 个字（§3.4）。
- 不改：`rtl/tcp_rx.v`、`rtl/vlan_strip.v`、`rtl/rx_classify.v`、`rtl/tcp_cam.v`、`rtl/tcb.v`、`rtl/tx_arb.v`、`rtl/udp_tx_frame.v`、`rtl/app_ctrl.v` 的功能主体（`app_ctrl` 零传参改动）。
- 不碰：PCS/GT、参考钟、QPLL 复位、XDC 时钟组、QSPI、`D:\repo\perfv`。
- 本件所有 LUT/FF/时序增量 = **纸面**（±30% 包络）；唯一硬锚 = `mac_tx_10g` OOC 上界 `1,602 LUT / 488 FF`（`_proj_10g/p7b_mac_synth/mac_only/mac_tx_ooc/`）。

---

## 2. A-1 实施级

### 2.1 端口身份来源与物理映射（钉死）

**现读事实**：
- `slow_cfg_adp` 在 S_CAM 拍把 HLS 记录 `w2 = local_ip` 写入 `cam_cfg_dip`：`rtl/slow_cfg_adp.v:137-163`（`:148` 逐字 `cam_cfg_dip <= w2;`）。
- `tcp_rx` 用**帧的目的 IP** 组 CAM 键：`rtl/tcp_rx.v:213`、`:443-446`。
- `tcp_cam` 已有 `dip_r[0:15]` 与 `rd_dip` 读回：`rtl/tcp_cam.v:36-40`、`:71-75`；**读口字段语义见 `tcp_cam.v:26-27`：`rd_sip` = 对端 IP（发送帧的 dst IP），`rd_dip` = 本地 IP（发送帧的 src IP）。**
- wrapper 的 `cam_rd_dip` 已连线：`board/wrapper_p4.v:2026`（声明）、`:2210`（接 CAM），**当前零消费者**。
- HLS 的 `w2` 现在是编译期常量 IP：`hls/src/layer_tcp.cpp:177`。

**映射（本件口径）**：

| 物理口 | PCS 通道 | 板 IP | 逻辑端口位 | 说明 |
|---|---|---|---|---|
| **J8 = SFP B** | **ch1 = X0Y5** | **IP_A = 192.168.100.2**（保持不变） | **0** | 现役单口；对端 p1 = `192.168.100.1` |
| **J7 = SFP A** | **ch0 = X0Y4** | **IP_B = 192.168.100.4**（建议） | **1** | 新口；对端 p0 = `192.168.100.101` |

> **单点决定**：不能反过来把 IP_A 绑 ch0；否则“只插 J8 的单口”在双口位流里会把帧发到 J7。本件按“IP_A=ch1=现役”设计。
>
> 命名歧义：`SFP2_MODE_A` 的 **A = 甲（模式）**，与 **SFP A = J7 = ch0** 不是一回事；正文一律写“甲/乙”与“ch0/ch1”。

### 2.2 wrapper 16 槽端口位数组

**改动点（`board/wrapper_p4.v`，现读行号）**：

**【v2.1 修订注 N-2】v2 把 `IP_A_5`/`IP_B_5` 放在 `` `ifdef DUAL_SFP_A `` 内，而 §2.4 的 `udp_split #(.DUAL_IP(DUAL_SFP_A_DEF), .IP_B(IP_B_5))` 与 `udp_tx_cfg #(...)` 是**无条件**引用 ⇒ 非 DUAL 构建引用未声明标识符，xvlog/synth 硬错（现树 `grep DUAL_SFP_A_DEF|IP_A_5|IP_B_5` = 0 命中）。修法 = **两个 IP localparam 移出 ifdef 无条件声明；`DUAL_SFP_A_DEF` 用 ifdef/else 两支各给一个 localparam**。**

- 在 `cam_cfg_*_mux` 声明旁（`:2183-2189` 之后）新增（**注意：`IP_A_5`/`IP_B_5` 在 ifdef 外**）：

```verilog
    // ---- P11 P2-甲: 板 IP 常量（两种宏态都必须可见；N-2） ----
    localparam [31:0] IP_A_5 = 32'hC0A86402;   // 192.168.100.2 = ch1/J8
    localparam [31:0] IP_B_5 = 32'hC0A86404;   // 192.168.100.4 = ch0/J7

`ifdef DUAL_SFP_A
    localparam DUAL_SFP_A_DEF = 1'b1;
    reg [15:0] cam_port_arr;
    always @(posedge dp_clk or negedge dp_rst_n) begin
        if (!dp_rst_n) cam_port_arr <= 16'd0;                    // L-4: 复位 0
        else if (cam_cfg_wr_mux)
            cam_port_arr[cam_cfg_addr_mux] <= (cam_cfg_dip_mux == IP_B_5);
    end
    wire cam_rd_port = cam_port_arr[cam_rd_id];                  // L-1: 用 cam_rd_id
`else
    localparam DUAL_SFP_A_DEF = 1'b0;
    wire cam_rd_port = 1'b0;
`endif
```

- 零改 `slow_cfg_adp` / `tcb` / `tcp_cam`。
- 读口：`cam_rd_port` 送 `tcp_tx_frame`（§2.3）；UDP app 端口位由 `udp_tx_cfg` 自己按 `peer_my_ip_r` 产生（§2.4）；慢路径由 `slow_tx_adp` 提取（§2.5）。
- 成本：**+16 FF + 1 位 16:1 读 mux**（纸面）。
- 不变式（门必须断言）：**同拍同址同源**；DEL/孤儿清后 `port_arr[s]==0`；`cam_rd_port` 与 `cam_rd_dip` 在同一 `cam_rd_id` 下一致；`cam_port_arr` 复位 0。
- **`IP_A_5` 的用途（N-2 收口）**：现树 `cfg_dst_ip`（`wrapper_p4.v:2592` 附近）与 `cfg_my_ip`（`:2884` 附近）是字面量 `32'hC0A86402`。实施轮**建议**把这两处改成 `IP_A_5`（同值、行为等价），让“板 IP 身份”只有一个常量源；若实施轮不动这两处，`IP_A_5` 仅作文档常量（综合会裁掉），**不得**被任何 `ifdef` 包住。

**为什么不用 TCB 1 位**：`tcb.v:94-105` 的 `upd_sel` 是 3 位且 `3'd7` 显式保留拒写（`:103`），要加字段必须动接口；且 TCB 与 CAM 会多一份冗余状态。wrapper 数组不动任何既有模块接口。
**为什么不用“每帧比 `cam_rd_dip`”**：省 16 FF，但把 32 位比较放在帧启动/CSUM init 锥上；数组把比较放在慢速配置写拍（每连接一次）。

### 2.3 `tcp_tx_frame` 的 per-connection 源 IP / 端口 / 校验和

**新增端口/参数（`rtl/tcp_tx_frame.v`，现读端口表 `:122-129` 一带）**：

| 端口/参数 | 方向/默认 | 用途 |
|---|---|---|
| `input [31:0] cam_rd_dip` | in | 该 bank/ctrl 连接的本地 IP（`tcp_cam.rd_dip`，wrapper 已连线；**字段语义 = RX 视角的 dip = 本地 IP，见 `tcp_cam.v:26-27`**） |
| `input cam_rd_port` | in | 该连接的端口位（§2.2 数组；1 = ch0） |
| `output reg o_port` | out | 本帧出口端口位（帧内稳定；送 TX demux）；**复位 0**（L-4） |
| `parameter PER_CONN_SRC_IP = 1'b0` | 默认 0 | **0 = 原行为**（全部用 `cfg_src_ip`、`o_port=0`）；wrapper 在 `DUAL_SFP_A` 构建传 **1** |

**逐用途改动表（OVL 体 = 板上生效体；默认体 = 非 OVL 构建/部分门）**：

| # | 用途 | 现读位置（OVL） | 现读位置（默认体） | 改法 |
|---|---|---|---|---|
| 1 | IP 校验和函数 | `ip_csum_calc` `:392-405`（`:400-401` 用 `cfg_src_ip`） | `:2000-2013`（`:2008-2009`） | 函数加 `input [31:0] sip`；两体各改一处定义 |
| 2 | 数据帧 csum init（TCP 伪头种子） | `csum_init_val` `:817-819`；`csum_init = start_data \|\| ring_start` `:820` | `:2022-2024`；`csum_init = start_ack \|\| start_data \|\| ring_start` `:2025` | `PER_CONN_SRC_IP ? cam_rd_dip : cfg_src_ip`。**这一拍 bank 尚未装载，必须组合读 `cam_rd_dip`** |
| 3 | 控制帧 csum init（TCP 伪头种子） | `csum_init_ctrl` `:874-876`（现读用 `cfg_src_ip` + `ctrl_dip`） | **同 #2（控制帧走 `csum_init_val`，且 `start_ack` 同拍）** | **【v2.1 N-6 订正】默认体：用组合读 `PER_CONN_SRC_IP ? cam_rd_dip : cfg_src_ip`。⛔ 禁止用 `lip_r`** —— `csum_init` 含 `start_ack`（`:2025`），而 `lip_r <= cam_rd_dip` 在 `:2411` 的**同一沿**才锁存 ⇒ `start_ack` 拍读到的是**上一连接/复位值** ⇒ SYN-ACK 的 TCP 伪头源 IP 静默错（对端丢弃）。OVL：新增 `ctrl_lip`，在 `start_ack` 沿锁存（`ctrl_dip <= cam_rd_sip` 同块），控制帧校验和在 `start_ack+1` 装载（R-1，`:1164-1166`）⇒ 该拍 `ctrl_lip` 已稳定。 |
| 4 | 控制帧 IP 校验和 | `ctrl_ipcsum_now = ip_csum_calc(..., ctrl_dip)` `:900-901` | `ip_csum_r <= ip_csum_calc(total_len_r, id_cap, dip_r)` `:2463` | 已寄存的 `ctrl_lip` / `lip_r` 作 `sip` 入参（这两处都在锁存之后 ≥1 拍，寄存值安全） |
| 5 | 数据帧 IP 校验和（fin 拍） | `f_ipcsum[rx_bank] <= ip_csum_calc(..., f_dip[rx_bank])` `:1396-1397` | 同 #4 | bank 的 `f_lip[rx_bank]` / `lip_r` |
| 6 | 头字源 IP | `3'd3: m_axis_tdata <= {h_ipcsum, cfg_src_ip, h_dip[31:16]};` `:1440` | `:2481` | `h_lip`（= `h_ctrl ? ctrl_lip : f_lip[tx_bank]`）/ `lip_r` |

**N-6 的默认体逐字改法（可直接照抄）**：
```verilog
    // 默认体（非 OVL）：伪头源 IP 必须与 csum_init 同拍可用 ⇒ 组合读 CAM
    wire [31:0] csum_sip = PER_CONN_SRC_IP ? cam_rd_dip : cfg_src_ip;
    wire [31:0] csum_init_val = {4'b0, csum_sip[31:16]} + {4'b0, csum_sip[15:0]} +
                                {4'b0, cam_rd_sip[31:16]} + {4'b0, cam_rd_sip[15:0]} +
                                32'h0006;
    wire        csum_init = start_ack || start_data || ring_start;   // 与 :2025 逐字一致
```
> `ip_csum_calc`（默认体 `:2000-2013`）另加 `input [31:0] sip`，`S_WAIT` 的 `:2463` 调用改为 `ip_csum_calc(total_len_r, id_cap, dip_r, lip_r)`；`S_HDR` 的 `:2481` 改成 `{ip_csum_r, lip_r, dip_r[31:16]}`。这三处都在帧首锁存之后 ≥1 拍，**不存在同沿问题**。
>
> **为什么不是 `csum_sip = PER_CONN_SRC_IP ? cam_rd_dip : cfg_src_ip` 一处就够**：默认体的 `csum_init_val` 同时服务 `start_ack` / `start_data` / `ring_start` 三种帧；三者在各自启动拍 `rb_id` 都已 mux 到对应连接（`dip_r <= cam_rd_sip` 的同一沿）⇒ 组合 `cam_rd_dip` 对该连接有效。**不得**为省一级而改用任何 `*_r` 寄存值。

**字段语义（N-6 附带核对）**：`cam_rd_sip` = **对端 IP**（发送帧的 dst IP），`cam_rd_dip` = **本地 IP**（发送帧的 src IP）。来源：`rtl/tcp_cam.v:26-27` 的读口注释 + `slow_cfg_adp.v:148`（`cam_cfg_dip <= w2`，`w2 = local_ip`）。v2 §2.3 的 `cam_rd_dip` 标注**与源码一致**，本条不订正语义，只补出处。

**锁存点（每个都要加；行号为现读，±1 已按 §0.2 订正）**：

| 锁存 | 现读位置 | 加什么 |
|---|---|---|
| OVL `ring_start` bank 装载 | `:1198-1210` | `f_lip[rx_bank] <= cam_rd_dip; f_port[rx_bank] <= cam_rd_port;` |
| OVL `start_ack` 控制槽装载 | `:1313-1345`（`ctrl_dip <= cam_rd_sip` `:1324`） | `ctrl_lip <= cam_rd_dip; ctrl_port <= cam_rd_port;` |
| OVL 活帧首拍 bank 装载 | `:1345-1362`（`recv_first` 支 `:1347-1361`） | 同 ring 装载 |
| 默认体 `start_ack \|\| start_data` | `:2392-2415`（`dip_r <= cam_rd_sip` `:2411`） | `lip_r <= cam_rd_dip; port_r <= cam_rd_port;`（**仅用于 #4/#6，不用于 #3**） |
| 默认体 `ring_start` | `:2272-2288`（`dip_r <= cam_rd_sip` `:2284`） | 同上（`lip_r/port_r`） |

**`o_port` 生成**：
```
wire [31:0] h_lip = h_ctrl ? ctrl_lip : f_lip[tx_bank];
always @(posedge clk or negedge rst_n)
  if (!rst_n) o_port <= 1'b0;                                  // L-4
  else if (PER_CONN_SRC_IP) o_port <= h_ctrl ? ctrl_port : f_port[tx_bank];
  else o_port <= 1'b0;
```
`o_port` 在帧首锁存后到帧末**不变**（M-12 的生产者侧断言）。

**时序论证**：
- `start_data` / `ring_start` 那一拍，`rb_id = start_id / retx_id_r`（`:663`/`:1832`），`cam_rd_id = rb_id`（`:666`/`:1834`）；`tcp_cam.rd_dip` 是组合读（`tcp_cam.v:71-75`）⇒ **同一拍 `cam_rd_dip` 就是该连接的本地 IP**。`csum_init_val` 与 `checksum16.init` 同拍 ⇒ 只能组合读。
- `start_ack` 那一拍同理：`cam_rd_id = rb_id` 已 mux 到 `start_id`（OVL `:1306-1308` 注释；默认体同一 assign）⇒ 组合 `cam_rd_dip` 有效。**这正是 N-6 的根因：不能用同沿才锁存的 `lip_r`。**
- `f_lip`/`ctrl_lip` 在同一沿装载；后面 `RX_FIN`/`S_WAIT`/`S_HDR` 读到的都是**已寄存值** ⇒ 与 init 拍取的是同一份（同源同拍）。
- 重放：`ring_start` 重新从 `cam_rd_dip` 装 bank；同一连接在会话期间 CAM 不变 ⇒ 重放源 IP 与首帧一致。
- 控制帧（OVL）：R-1 重定时后 `ctrl_ipcsum/tcpcsum` 在 **start_ack+1** 装载（`:1164-1166`；`:582` 段注释），`ctrl_lip` 在 start_ack 沿已稳定 ⇒ 时序余量不变（仍 ≥3/5 拍）。
- 校验和锥：`csum_init_val` 的加数个数**不变**（原来就是 `cfg_src_ip` 两半字 + `cam_rd_sip` 两半字；现在把前两半字换成一个同宽 mux）。`cam_rd_sip` 本来就是 CAM 16:1 组合读 ⇒ 加法树级数不变，只是 CAM 读 mux 的扇出 +32 位。【推断：+0 级】

**收益/代价**：+99 FF（OVL：`f_lip` 2×32 + `f_port` 2 + `ctrl_lip` 32 + `ctrl_port` 1；默认体 33；两体互斥 ⇒ max 99），纸面 +50-100 LUT。

**单口兼容**：
- `PER_CONN_SRC_IP=0` 时所有选择器都选 `cfg_src_ip` / `o_port=0`；Vivado 常量折叠 ⇒ **行为等价**（L-3；不说“网表逐位相同”）。
- wrapper 只在 `DUAL_SFP_A` 构建传 `PER_CONN_SRC_IP=1`。
- 实施轮必须把**活跃 TB** 的这两个新输入显式接常量（`32'h0` / `1'b0`）——`tcp_tx_frame` 的活跃直接例化点在 `tb/` 现读至少 19 个文件（`tb_p4_chain.v:779`、`tb_p5_app.v:473`、`tb_p5_adv.v:438`、`tb_p5_multi.v:579`、`tb_p7b_chain.v` 经 wrapper 等），凡进门的都要接；**冻结副本**（`sim/.../frozen/`、`notes/` 副本）一律不碰。

### 2.4 UDP app 的源 IP / 端口（`udp_rx` + `udp_split` + `udp_tx_cfg`）

**现读事实**：
- `udp_tx_cfg` 的 peer 表只有 `{peer_mac, peer_ip}`（`rtl/udp_tx_cfg.v:66-77`）；`cfg_my_ip` 是静态端口（`:75`，wrapper 接常量 `wrapper_p4.v:2884`）；`o_src_ip` 在空闲窗口刷新（`:165-173`）。
- `udp_rx.ip_match` 只比一个 `cfg_dst_ip`（`rtl/udp_rx.v:180-181`）；meta 只有 `src_mac/src_ip/src_port/len`（`:202-213`）。
- `udp_split` 透传 meta（`rtl/udp_split.v:745-749`），`cfg_dst_ip` 是输入（`:215`）并转给 `udp_rx`（`:443-446`）。
- `udp_tx_frame` **已有 `cfg_src_ip` 输入**（`rtl/udp_tx_frame.v:36-38`），本身不必改。

**改动（H-1 的参数化形态）**：

| 文件 | 现读位置 | 改动 |
|---|---|---|
| `rtl/udp_rx.v` | `:180-181`（`ip_match`）、`:202-213`（meta 输出） | 加 **`parameter DUAL_IP = 1'b0`**、**`parameter [31:0] IP_B = 32'hFFFFFFFF`**（**不新增输入端口**）；`ip_match = cfg_multi_en&&multicast \|\| dst==cfg_dst_ip \|\| (DUAL_IP && dst==IP_B)`；新增 `output reg [31:0] meta_dst_ip`，在 **w4 接受拍**锁存 `{w3_r[15:0], s_axis_tdata[63:48]}`（该值就是 `ip_match` 比较的 dst IP；w5 的 `meta_valid` 时稳定） |
| `rtl/udp_split.v` | `:209-213`（meta 输出）、`:215`（cfg）、`:443-447`（例化） | 加 `meta_dst_ip` 透传；加 `parameter DUAL_IP=0`、`parameter [31:0] IP_B=32'hFFFFFFFF` 并透传给 `udp_rx` |
| `rtl/udp_tx_cfg.v` | `:66-77`（peer 写口）、`:104-107`（peer 寄存器）、`:124-127`（`cfg_sync`）、`:142-180`（锁存） | 加 `input [31:0] peer_my_ip`、`output reg o_port`（复位 0）、`parameter PER_CONN_SRC_IP=0`、`parameter [31:0] IP_B=32'hFFFFFFFF`；表中存 `peer_my_ip_r`；空闲刷新 `o_src_ip <= PER_CONN_SRC_IP ? peer_my_ip_r : cfg_my_ip`、`o_port <= PER_CONN_SRC_IP ? (peer_my_ip_r == IP_B) : 1'b0`；`cfg_sync` 见 M-11 |
| `board/wrapper_p4.v` | `:2880-2884`（peer 写口 + `cfg_my_ip`）、`:2592`（`cfg_dst_ip`） | `peer_my_ip(udp_meta_dst_ip)`、`udp_split #(.DUAL_IP(DUAL_SFP_A_DEF), .IP_B(IP_B_5))`、`udp_tx_cfg #(.PER_CONN_SRC_IP(DUAL_SFP_A_DEF), .IP_B(IP_B_5))`；建议 `cfg_dst_ip(IP_A_5)`、`cfg_my_ip(IP_A_5)`（N-2，同值） |
| `rtl/udp_tx_frame.v` | `:36-38` | **零改动**（端口位由 `udp_tx_cfg` 输出，帧内冻结） |

**M-11：`cfg_sync` 的后 mux 期望值（逐字口径）**：
```
wire cfg_sync = (o_dst_mac == peer_mac_r) && (o_dst_ip == peer_ip_r) &&
                (o_dst_port == cfg_dst_port) && (o_src_mac == cfg_my_mac) &&
                (o_src_port == cfg_my_port) && (o_csum_en == cfg_csum_en) &&
                (PER_CONN_SRC_IP
                   ? ((o_src_ip == peer_my_ip_r) && (o_port == (peer_my_ip_r == IP_B)))
                   : ((o_src_ip == cfg_my_ip)    && (o_port == 1'b0)));
```
**为什么**：`PER_CONN_SRC_IP=0` 时如果无条件比 `peer_my_ip`，未接输入（Z）会让 `cfg_sync` 恒 X ⇒ `deny` X ⇒ 单口 TX 全灭。参数门控后，单口只比 `cfg_my_ip`/`o_port=0`，与今天逐位相同。

**N-2：两种宏态下的参数引用逐点核对（施工轮必须全过）**：

| 引用点（v2.1 文本） | `DUAL_SFP_A=1` | 无 `DUAL_SFP_A` | 展开是否合法 |
|---|---|---|---|
| `udp_split #(.DUAL_IP(DUAL_SFP_A_DEF), .IP_B(IP_B_5))` | 1 / `0xC0A86404` | 0 / `0xC0A86404` | ✅（IP_B 已移出 ifdef） |
| `udp_tx_cfg #(.PER_CONN_SRC_IP(DUAL_SFP_A_DEF), .IP_B(IP_B_5))` | 1 / `0xC0A86404` | 0 / `0xC0A86404` | ✅ |
| `tcp_tx_frame #(.PER_CONN_SRC_IP(DUAL_SFP_A_DEF))` | 1 | 0 | ✅ |
| `slow_tx_adp #(.PER_PORT(DUAL_SFP_A_DEF), .IP_B(IP_B_5))` | 1 / `0xC0A86404` | 0 / `0xC0A86404` | ✅ |
| `rx_merge2` 实例 | 存在 | **不例化**（`ifdef DUAL_SFP_A` 内） | ✅ |
| `cam_port_arr` / `cam_rd_port` | 数组生效 | `cam_rd_port=1'b0` | ✅ |
| `IP_A_5` / `IP_B_5` | 可见 | 可见（ifdef 外） | ✅ |
| `DUAL_SFP_A_DEF` | `1'b1` | `1'b0` | ✅ |

> 施工轮自检：在 **无 `DUAL_SFP_A`** 的 elab 组合（G7 c1..c7）里 grep 日志 `VRFC 10-2989|not declared|8-36` 必须 0 命中；在 DUAL 组合（c8）里同一组必须 0 命中。**只核“DUAL 能编过”不算 N-2 收口**。

**单 peer 表限制（既有语义，不是本设计引入）**：两口同时活跃时“最后学习者赢”；P2 的 UDP app 测试必须**逐口做**或接受翻转。登记。

**新增输入无 Z（H-1）**：
- `peer_my_ip` 是唯一新输入。G1 的 9 个 active 直接例化点全部接常量/参数：
  - `tb/tb_app_udp.v:219`（udp_split）、`:311`（udp_tx_cfg）
  - `tb/tb_udprx_chain.v:232`（udp_split）
  - `tb/tb_udprx_rate.v:327`（udp_split）
  - `tb/tb_app_udp_rate.v:162`（udp_tx_cfg）
  - `tb/tb_udp_split.v:60`（udp_split）
  - `tb/tb_udp_tx_guard.v:180`（udp_tx_cfg）
  - `tb/tb_udp_rx.v:55`（udp_rx）
  - `tb/tb_udp_echo.v:51`（udp_rx）
- `udp_rx`/`udp_split` 走参数后**没有新输入口**，只需 TB 不覆盖参数（默认 0/0xFFFFFFFF）。
- 断言：G1 在 xelab 日志上查 `VRFC 10-3645` 与 `peer_my_ip` **同一行**（`findstr "peer_my_ip" xelab.log | findstr "VRFC 10-3645"`）为空；G2/G5 运行时把 `peer_my_ip` 钉常量并断言 `o_port !== 1'bx`、`cfg_sync` 无 X（用 `$isunknown`）。

### 2.5 慢路径出口端口：`slow_tx_adp` 源 IP 提取 + side FIFO

**现读事实**：HLS TX 是 16 位字节流（`hls_tx_tdata[8]=TLAST`，`slow_tx_adp.v:17-19`），剥前导/4 字节 FCS 后整帧进 `frame_fifo`（`:80-88`），播放器输出 73 位字流（`:207-224`）。HLS 帧**无 VLAN**（`hls/src/eth_types.h:211-217` 的 `insert_vlan` 全仓无生产者；`hls/src/layer_mac.cpp:218` 是唯一读点）⇒ 源 IP 偏移固定。

**端口提取（`rtl/slow_tx_adp.v`）**：
- 参数：`parameter PER_PORT = 1'b0`、`parameter [31:0] IP_B = 32'hFFFFFFFF`、`parameter SIDE_DEPTH = 128`。
- 新输出：`output wire o_port`（`PER_PORT ? play_port : 1'b0`，复位 0）、`output reg [31:0] stat_side_ovf`（side FIFO 拒 push 次数，恒 0）、`output wire [7:0] side_level`（门观测）。
- 在字节 FSM 的 `T_DATA` 消费路径（`:136-197`）加内容字节索引 `bpos`（`T_PRE→T_DATA` 清 0，每消费一字节 +1，饱和 6 位，`in_last` 帧末清）与 40 位移位寄存器 `src_sr <= {src_sr[31:0], in_b}`。
- 在 `bpos==13` 锁 `etype_r <= {src_sr[7:0], in_b}`（以太类型 = 帧字节 12..13）。
- 在 `bpos==29 && etype_r==16'h0800` 锁 `src_ip_lat <= {src_sr[23:0], in_b}`、`ip_seen<=1`（IPv4 源 IP = 帧字节 26..29）。
- 在 `bpos==31 && etype_r==16'h0806` 锁 `src_ip_lat <= {src_sr[23:0], in_b}`、`ip_seen<=1`（ARP SPA = 帧字节 28..31）。
- `VLAN 自检（L-10）`：若 `bpos==13` 的 etype 为 `16'h8100`/`16'h88A8`，置 `vlan_seen` sticky；`vlan_seen` 时强制 `o_port=0`（安全口）。
- 每帧开始清 `ip_seen`/`vlan_seen`；提交拍 `commit_pulse` 把 `(ip_seen && !vlan_seen && src_ip_lat==IP_B)` 压入 **1 位 × SIDE_DEPTH 的按帧 side FIFO**；`start_play` 拍弹出到 `play_port`；`side_level == committed` 是硬不变式（**仅 `PER_PORT=1`**；单口时 side FIFO 不例化、`side_level=0`，`committed` 仍计数）。

**为什么选“深度 128”（H-3 三选一）**：
1. **深度 ≥128（选）**：`frame_fifo` 512 字；HLS 最小帧内容 = 60 B = **8 字**（见 §0.2-1）⇒ 最多 **64 帧**在飞；128 = 2× 余量。1 位 ×128 LUTRAM 便宜。
2. **commit 门 `almost_full` 不 commit（不选）**：会把“端口位溢出”转成“整帧丢弃 + `stat_purge`”，需要把 side FIFO 占用耦合进 `commit_pulse` 的第二套回滚条件；丢帧代价 + 状态耦合，比加深 FIFO 差。
3. **塞进 `frame_fifo` 未用位（不可行）**：`frame_fifo` W=73 已满（`{tlast,tkeep,tdata}`）；且端口位要等字节 29/31 才知道，**前 4 个字已经写进 FIFO**，无法给早写的字打标。除非重写已写槽，否则结构上做不到。

**断言与负控（G4）**：
- 正臂：`side_fifo_level == committed` 每个检查点成立；`side_ovf == 0`；长时阻塞用例（`m_axis_tready=0`，提交 60 个 8 字最小帧，占用 480 字 < 512）后放行，逐帧 `o_port` 与帧头源 IP 一致。
- 负控 1：`SIDE_DEPTH=16` 例化 ⇒ 同一激励 `side_ovf>0` 且 `side_level != committed`（必须红），证明断言有牙。
- 负控 2：故意把 push 条件与 `commit_pulse` 错开 1 拍 ⇒ 错位必须被 `side_level==committed` 抓到。
- 短帧/未识别 ethertype：`ip_seen=0` ⇒ `o_port=0`（默认走 ch1/现役口，安全）。

**纸面**：+40 FF / +10-30 LUT + side FIFO 128×1 LUTRAM。

### 2.6 TX 选口：方案 ②（demux 前移 + 复制 arb 树）

| 维度 | ① 全链 74 位（穿两级 arb） | ② split/demux 前移 + 复制 arb 树（**采用**） |
|---|---|---|
| `rtl/tx_arb.v` | 端口表 73→74（全部实例） | **源码零改动**（保持 73） |
| 直接例化 `tx_arb` 的 TB | `tb/tb_tx_arb.v:37`、`tb/tb_p4_chain.v:930` **必须改** | **零改动** |
| wrapper | 两级 arb 加 1 位 + 新 `tx_split2` | 3 个 demux + **每口一套两级 arb（共 4 个 `tx_arb`）** + 每口 FIFO/MAC |
| 跨口 HOL | 存在（单流分裂） | **结构性消除**（每口独立 arb/FIFO）；生产者按帧目标口等待，仍有源端 HOL（登记） |
| 面积（纸面） | +1 位 ×2 arb ≈ +10 LUT | +2 arb ≈ +150 LUT / +20 FF；3 demux ≈ +200 LUT |
| 单口回归 | 模块端口变 | `else` 支原样，新逻辑全在 `DUAL_SFP_A` 内 |

**`rtl/tx_demux2.v`（新件，纸面 ~50 行）**：
- 端口：`s_tdata/s_tkeep/s_tvalid/s_tready/s_tlast/s_port` → `d0_*/d1_*`。
- **帧首锁存**：`busy=0` 且 `s_tvalid && s_tready` 时锁 `port_r <= s_port`、`busy<=1`；帧内用 `port_r`（不是组合 `s_port`）。
- 输出：`port_sel = busy ? port_r : s_port`；`d0_tvalid = s_tvalid && !port_sel`、`d1_tvalid = s_tvalid && port_sel`；`s_tready = port_sel ? d1_tready : d0_tready`；数据/keep/last 广播。
- 帧末（`s_tvalid && s_tready && s_tlast`）`busy<=0`。
- `stat_port_change`：帧内 `s_port != port_r` 时 +1（应恒 0）；G3 用它抓“帧内换口”。
- `o_port` 生产者侧稳定性（M-12）：`tcp_tx_frame`/`udp_tx_cfg`/`slow_tx_adp` 在 `tvalid && !tready` 期间必须保持。

**方案 ③（登记待裁）**：单流 arb 之后、FIFO 之前放 4 字前瞻路由器，从帧头 IPv4 源 IP/ARP SPA 解析出口。优点：三个生产者零端口改动；缺点：新增“TX 帧不带 VLAN + 头偏移固定”不变式，且 4 字管线滞后（单缓冲每帧 +4 拍 ≈ 2% 帧周期）。**不推荐作为第一版**。

### 2.7 单口/双口兼容（开关、参数、回归）

| 项 | 单口（默认/无 `DUAL_SFP_A`） | 双口（`DUAL_SFP_A=1`） |
|---|---|---|
| `cam_port_arr` | `ifdef` 外不存在，`cam_rd_port=1'b0` | 写/读生效 |
| `tcp_tx_frame` | `PER_CONN_SRC_IP=0` ⇒ `cfg_src_ip`、`o_port=0` | 用 `cam_rd_dip`/`cam_rd_port` |
| `udp_rx`/`udp_split` | `DUAL_IP=0`、`IP_B=0xFFFFFFFF`（**实际传 `IP_B_5` 但 `DUAL_IP=0` 使其折叠**） ⇒ 只比 `cfg_dst_ip` | `DUAL_IP=1`、`IP_B=IP_B_5` |
| `udp_tx_cfg` | `PER_CONN_SRC_IP=0` ⇒ `cfg_my_ip`、`o_port=0` | 用 `peer_my_ip_r` |
| `slow_tx_adp` | `PER_PORT=0` ⇒ 提取逻辑/ side FIFO 不例化，`o_port=0` | 生效，side FIFO 128 |
| `tx_arb` 链 | 现役 `u_tx_udp_arb→u_tx_arb→u_txcdc→u_mac_tx` **原样** | 每口一套 |
| `rx_merge2` | 不例化；`rx_*` 仍由 `u_rxcdc` 直连 | 例化；两路 FIFO → merge |
| ch0 TX | 常量 IDLE（P1 不动） | 第二 `mac_tx_10g` |
| **W83/W84/W86/W87** | **= 32'd0（常量，N-10）** | 真源（§3.4） |
| **W85** | **真源（classify，两种构建都存在）** | 同左 |

**N-10：非 DUAL 的快照 tie-off（必须写进 `snap_dout_all`，不能靠“源不存在就悬空”）**：
```verilog
    // snap_dout_all 顶部 5 项（MSB 端；W87/W86/W85/W84/W83）
`ifdef DUAL_SFP_A
    , w87_dp, w86_dp, w85_dp, w84_dp, w83_dp
`else
    , 32'd0, 32'd0, w85_dp, 32'd0, 32'd0
`endif
```
- **取舍**：本件选“W83/W84/W86/W87 = 0”而不是“W83 = 现役单 arb 输出”。理由 = 单口构建的时序余量（0x2B `+0.048` / 0.75%）优先；非 DUAL 不是 P2 的验收对象，只是兼容/回归构建。若用户希望单口也保留 TX 活动指示，备选 = 把 W83 接现役 `u_tx_arb` 输出的 `tvalid && tready && tlast` 计数器（纸面 +32 FF + 1 个 32 位计数器锥），**必须在同一次构建里单独评估时序**；本件不选。
- `tb_p7b_chain`（非 DUAL）断言：**W83/W84/W86/W87 ≡ 0（复位后到运行结束）**；W85 跟随 `rx_classify`（有注入帧时 >0，且等于 TB 注入帧数）。见 §5.2 G9。

**硬门（elaboration 失败，照 `g_orph_zw_guard` 手法 `wrapper_p4.v:226-241`）**：
- `DUAL_SFP_A ∧ ¬P7B_10G` → `DUAL_SFP_A_REQUIRES_P7B_10G`；
- `DUAL_SFP_A ∧ SFP2_MODE_B` → `DUAL_SFP_A_AND_SFP2_MODE_B_CONFLICT`；
- `DUAL_SFP_A ∧ ¬DP_156MHZ` → `DUAL_SFP_A_REQUIRES_DP_156MHZ`；
- `DUAL_SFP_A ∧ ¬APP_MODE` → `DUAL_SFP_A_REQUIRES_APP_MODE`；
- `DUAL_SFP_A` 下 `rx_merge2.STRICT` **硬接 `1'b0`**（L-12；G7 常量断言见 §5.2）。

**回归**：默认构建 = 矩阵 24 门（G2/G5/G6 进矩阵后；G3/G4 独立门）；单口运行时回归 = 双口位流只插 J8 与 0x2B 同会话 A/B。

---

## 3. ch0 数据面接入

### 3.1 时钟 / 复位 / TX_DIS

| 项 | 现读锚点 | 设计 |
|---|---|---|
| ch0 RX 域 | `gmii_clk_0 = rx_clk_out_0`（`:352` 声明、`:753` assign；`:390` PCS 端口） | 不变 |
| ch0 TX 域 | `tx_fe_clk_0 = tx_mii_clk_0`（`:353`、`:754` assign） | 不变；P2 首次有消费者 |
| ch0 RX MAC 复位 | `rx_mac_rst_n_0 = rstn_rx_sr_0[2] & ~pcs_user_rx_reset_0`（`:692-699`，§0.2 订正） | 不变 |
| ch0 TX MAC 复位 | **不存在**（P1 无 ch0 TX） | **新增** `(* ASYNC_REG *) reg [2:0] rstn_tx_sr_0;`（`tx_fe_clk_0` 域）+ `tx_mac_rst_n_0 = rstn_tx_sr_0[2] & ~pcs_user_tx_reset_0`（照 ch1 `:683-688`） |
| ch0 TX 常量 IDLE | `p7b_ch0_idle_d/c`（`:639-646`，`dont_touch`） | `DUAL_SFP_A` 下：**寄存器声明本身**包 `ifndef DUAL_SFP_A`（L-2），并删除两根 assign；`u_mac_tx_ch0` 驱动 `tx_mii_d_0/c_0`。非 dual 保留原样（ch0 端口必须有真实负载，`:626-638` 的 driverless-net 历史教训） |
| TX_DIS | `sfp1_tx_dis = pcie_scratch[0]`（`:4814`）、`sfp2_tx_dis = pcie_scratch[1]`（`:4815`） | **零改动**；bit0 = J7/ch0，bit1 = J8/ch1（P1 S-3 已板级证 bit0→对端 p0 carrier） |
| `mac_tx_10g` 空闲输出 | `S_IDLE` 输出 `64'h0707…/c=0xFF`（`_proj_10g/p7b_mac/rtl/mac_tx_10g.v:317-330` 的 mux default） | 与 P1 常量 IDLE 相同 ⇒ 换 MAC 后链路空闲行为不变 |

### 3.2 ch0 RX：tap → FIFO → `rx_merge2`

**现读**：P1 的 ch0 段在 `wrapper_p4.v:949-1012`：`ch0_rx_tready = 1'b1`（`:973`）的“真消费者”sink + 好帧/字节累加（`:978-993`）+ `u_mac_rx_ch0`（`:995-1012`）。

**改动**：
1. **升级 sink 为真业务消费者**：
   - `ch0_rx_tready = ~ch0_fifo_full`（写侧 FE 本地，同 `u_rxcdc` 的做法）。
   - 新增 `fifo_async #(.WIDTH(76), .DEPTH(256), .FWFT(1), .AW(8)) u_rxcdc_ch0`：
     `wr_clk=gmii_clk_0, wr_rst_n=reset_n, wr_en=ch0_rx_tvalid, din={ch0_rx_tdata, ch0_rx_tkeep, ch0_rx_tuser, ch0_rx_tlast, ch0_rx_tcrs, ch0_rx_terr}`；
     `rd_clk=dp_clk, rd_rst_n=reset_n, rd_en=merge_p1_tready, dout={ch0_rx_dp...}, empty=ch0_rx_empty, ovf_cnt=ch0_rxcdc_ovf`。
   - **【v2.1 N-14】P1 的 W79 口径随之变化**：W79 仍是 tap 上 `tvalid && tready` 的好帧数，但 `tready` 现在是 `~full` ⇒ **W79 = “被 merge 输入 FIFO 接受的好帧数”**（不是“MAC 收到的好帧数”）。FIFO 满导致的丢帧由 MAC `stat_drop`（W82）计数；`u_rxcdc_ch0.ovf_cnt`（W86 高半）在 `tready` 门控下应恒 0（只作安全网）。W81/W82 不变（`:1008-1011` 已连）。**【v2.1-errata D-1/F-4】上句“应恒 0”不成立** —— `fifo_async.ovf_pulse = wr_en && full`，而 `wr_en` 是原始 `tvalid`：AXIS 生产者在 `full` 时保持 `tvalid` ⇒ 每拍“有字但满”都 +1，而字并未丢（下拍重试）。⇒ **W86 高/低半的语义 = “AXIS 反压拍数”，不是丢字数**；正常反压即增长 ⇒ 只作健康指示，P2-2 不再把它当字级修正项（见附录 E D-1/D-2）。
2. **新增 `rtl/rx_merge2.v`（76 位、无标签、`dp_clk` 单域）**：

```
module rx_merge2 #(parameter STRICT = 1'b0) (
  clk, rst_n,
  p0_* (76b AXIS + tvalid/tready)   // p0 = ch1 (现役)
  p1_* (76b AXIS + tvalid/tready)   // p1 = ch0 (新)
  m_*  (76b AXIS + tvalid/tready)
  output reg [31:0] stat_frames0, stat_frames1, stat_out, stat_bubble
);
```
   - **FSM**：`busy`（帧内锁）、`sel`（本帧口）、`rr`（上一次服务的口）。
   - 空闲拍仲裁：`STRICT=1` 时优先 p1；`STRICT=0` 时优先 `~rr` 口；若它无 `tvalid`，**工作保持**地选另一口；有 valid 则 `sel<=选中口; busy<=1`。
   - 忙拍：`m_tvalid = busy && p_sel_tvalid`；`p_sel_tready = m_tready`；非选中口 `tready=0`。
   - 帧末（`m_tvalid && m_tready && m_tlast`）：`busy<=0; rr<=sel` ⇒ **每帧末尾 1 拍重仲裁气泡**。
   - **帧级互斥**：只在 `!busy` 时选口、只在 TLAST 释放 ⇒ 一帧的字连续、不交织。
   - **公平性**：`rr` 只在该帧被服务后翻转 ⇒ 两口同时有帧时**逐帧交替**；单口有帧时满速。P3 若要按字节公平，可在同一 FSM 上加 deficit 计数器升级为 DRR（不改帧级互斥结构）。
   - **无内部丢帧路径**：selected 口 backpressure 直接回上游 FIFO；未选中口 `tready=0`，其 FIFO/MAC 承担溢出计数。
   - **`stat_frames0/1`**：帧末按 `sel` 计数（只给门；不进快照）。
3. **接入点**：`u_rxcdc`（ch1）与 `u_rxcdc_ch0` 的 dout 进 merge；merge 输出替换现 `rx_tdata/rx_tkeep/...`（`wrapper_p4.v:1054-1081` 的 DP_156MHZ 支）。**两处握手必须同步改**：① `u_rxcdc` 的 `rd_en` 由 `rx_tvalid && rx_tready`（`:1058`）改为 merge 的 `p0_tready`；② `assign rx_tvalid = ~rx_fifo_empty`（`:1067`）改为 merge 的 `m_tvalid`。非 dual 构建保留原式。`vlan_strip`（`:1097`）/`rx_classify`（`:1120`）**零改动**。
4. **FIFO 深度与丢帧**：每口 256 字 = **1.35 个最大帧（1518B=190 字）**。RR 的单口最大等待 = 1 个帧；等待期间另一口最多再来 1 帧 ⇒ 病态下第 2 帧可能溢出；**MAC 整帧丢 + W82/W4 计数**（`mac_rx_10g` 的 push 空间门 `stat_drop`，`_proj_10g/p7b_mac/rtl/mac_rx_10g.v:326-327,405-414`）。这满足 DESIGN_v5 §8 的“≥2 帧 **或** per-port drop 计数”的后者；两根口灌满时两口 drop 计数都应前进（公平份额 ≈ 各 50%）。备选：深度 512（2.7 帧）⇒ 每 FIFO 纸面 +~300 LUTRAM；若板上看到单口被无谓丢帧再加。
5. **复位**：两 FIFO 两侧都接 `reset_n`（与 `u_rxcdc` 同规则，`:1052` 注释）；merge 接 `dp_rst_n`。
6. **可观测性边界（A-1 的固有代价）**：RX 合并流**不携带端口标签**（身份 = 目的 IP），因此板内**无法回答“这一帧从哪个物理口进来”**；诊断只能靠对端每口 NIC 计数 / 物理拔插 / TX_DIS 单口隔离。登记，不当缺陷。

### 3.3 ch0 TX：第二 `mac_tx_10g` + 每口 arb/FIFO

- 新增 `u_mac_tx_ch0`（`_proj_10g/p7b_mac/rtl/mac_tx_10g.v`），`clk=tx_fe_clk_0`、`rst_n=tx_mac_rst_n_0`、输出 `tx_mii_d_0/c_0`；`stat_frames`/`stat_abort` 接 **W87**（§3.4）。
- 新增 `fifo_async #(.WIDTH(73), .DEPTH(256), .FWFT(1), .AW(8)) u_txcdc_ch0`：`wr_clk=dp_clk`（merge/arb 侧）、`rd_clk=tx_fe_clk_0`；`ovf_cnt=ch0_txcdc_ovf` → **W86 低 16 位**。
- 现役 `u_txcdc`（`:3013`）保留为 **port0（ch1）** 的 FIFO，`rd_clk=tx_fe_clk`（= tx_mii_clk_1）。
- 命名口径：方案 ② 下**不存在单点 `tx_split2`** —— “split”由 **3 个 `tx_demux2`（每个生产者一个）+ 每口一套 arb** 等价实现。若用户坚持“单点 split 模块”，那对应方案 ①（74 位穿 arb 后单点分流），不在本推荐内。
- **每口两级 arb**：port0 = 现役 `u_tx_udp_arb`（`:2936`）+ `u_tx_arb`（`:2987`）；port1 = 新增两个 `tx_arb` 实例。三个生产者（TCP `tx_*`、UDP `utx2_*`、HLS `stx_*`）各过一个 `tx_demux2`。
- **W28/W45 语义**：保持 ch1 口径（W28 = ch1 txcdc occ max；W45 = ch1 txcdc ovf）；ch0 的 txcdc ovf 进 W86 低 16 位。**不改 W45**（避免旧读数语义变化）。ch0 txcdc 占用峰值**不进快照**（登记）。
- `m_tx_*` / `txsrc_*` / `tx_fifo_*` 的线名在 dual 支拆成 `_p0/_p1` 两套；`u_mac_tx`（`:3039-3061`）保留为 ch1。
- W83/W84 计数点 = **每口 arb 输出**（`txsrc_p0/p1` 的 `tvalid && tready && tlast`），即“整帧交给该口 FIFO”。

### 3.4 观测面（P2 新增 5 字；H-7）

| 新字 | 内容 | 位域/域 | 源（现读锚点） |
|---|---|---|---|
| **W83** | TX port0（ch1）帧数 | 32 位自由回卷 / `dp_clk` | 每口 arb 输出 `m_axis_tlast && tvalid && tready` |
| **W84** | TX port1（ch0）帧数 | 同上 | 同 W83，port1 |
| **W85** | `rx_classify` **总帧数**（fast+slow） | `(cls_stat_fast + cls_stat_slow)[31:0]`；**33 位和显式截断**（L-5） | `wrapper_p4.v:898` 声明、`:1147-1148` 连接；`rx_classify.v:188-191` 计数 |
| **W86** | ch0 FIFO 溢出 | `[31:16] = sat16(u_maccnt_ch0rx.dst_val)`；`[15:0] = sat16(u_txcdc_ch0.ovf_cnt)` | 低半 = `u_txcdc_ch0.ovf_cnt`（`wr_clk=dp_clk`，本域）；高半 = `u_rxcdc_ch0.ovf_cnt`（`wr_clk=gmii_clk_0`）经 **`maccnt_sync` 事件镜像**到 dp（实例 `u_maccnt_ch0rx`，`W=32`） |
| **W87** | ch0 MAC TX | `[31:16] = sat16(u_maccnt_ch0tx.dst_val[63:32])`；`[15:0] = sat16(u_maccnt_ch0tx.dst_val[31:0])` | `u_mac_tx_ch0.stat_abort/stat_frames`（`tx_fe_clk_0`）经 **`maccnt_sync` 事件镜像**到 dp（实例 `u_maccnt_ch0tx`，`W=64`，**同一采样拍** ⇒ frames/abort 自洽） |

**W86 高半 / W87 的域问题（必须写清）**：`u_rxcdc_ch0.ovf_cnt` 在 `gmii_clk_0`（= `rx_clk_out_0`）域，`u_mac_tx_ch0.stat_*` 在 `tx_fe_clk_0` 域，而 p7bdp 束的 `clk_b = dp_clk`。**不能把这两个域的寄存器直接接进 p7bdp 束，也不能用裸 2FF 同步多比特计数器**（可能读到进位中间值）。合法做法：
- (i) 新开 `snap_cdc` 束（+96 FF/字 + 新束 FSM，风险大，v1 已拒绝）；
- (ii) **事件镜像（v2 采用）**：每个源计数器配一个 `maccnt_sync` 小模块 —— **源域锁存 32 位值 + toggle 请求；目的域两级同步 toggle 后取数并回 ack**（标准 4 相握手，不是裸 2FF 多比特同步）。目的域输出 `*_dp` 为 dp 域寄存器（满足 `snap_cdc.din_b` 前提）。采样节流 = 每 256 个 `dp_clk` 取一次；`stat_frames` 最高约 800k/s（事件间隔 ≈195 个 `dp_clk`）≫ 握手 ~10 拍 ⇒ 不丢事件；`stat_abort`/`ovf` 更稀。
- **口径**：W86 高半 / W87 = “最近一次成功握手采样值”，误差 ≤ 采样周期（256/156.25e6 ≈ 1.64 µs）+ 跨域延迟；P2-2 对账窗 ≥100 ms ⇒ 误差可忽略；**不用于 µs 级判据**。
- 如果实施轮认为 (ii) 的 CDC 风险大于收益，**backstop = 删 W87**（NW 87 / UNIMPL `0x18C`），ch0 abort 回到“未观测到”；W86 高半同理可退化为 0 并登记。本件不把 W87 当 P2-2 的唯一判据。

**N-4：`maccnt_sync` 的施工规格（新件，必须随本件导入）**：
- **文件/模块**：`rtl/maccnt_sync.v` / `module maccnt_sync #(parameter W = 32)`。
- **端口（建议）**：
  ```
  module maccnt_sync #(parameter W = 32) (
      input  wire         src_clk, src_rst_n,
      input  wire [W-1:0] src_val,        // 源域当前计数值（寄存器输出）
      input  wire         src_tick,       // 采样节流脉冲（源域；可恒 1，由上层门控）
      output reg  [W-1:0] dst_val,        // 目的域最近一次成功采样（寄存器）
      input  wire         dst_clk, dst_rst_n
  );
  ```
- **协议（4 相 toggle/ack）**：源域在 `src_tick` 且无未完成事务时 `src_lat <= src_val; req_tgl <= ~req_tgl;`；目的域 `req_s1/req_s2` 两级同步 `req_tgl`，`req_s2 != ack_tgl` 时把 `src_lat` 同步进目的域（`data_s1/data_s2` 两级，**只在 `req` 稳定后采样**），置 `ack_tgl <= req_s2`、`dst_val <= data_s2`；源域 `ack_s1/ack_s2` 两级同步后清 busy。**禁止**把多比特 `src_val` 直接两级同步；**禁止**在 `req` 变化沿采样数据。
- **实例**：
  1. `u_maccnt_ch0rx`：`W=32`，源 = `u_rxcdc_ch0.ovf_cnt`（`gmii_clk_0`），目的 = `dp_clk`；
  2. `u_maccnt_ch0tx`：`W=64`，源 = `{u_mac_tx_ch0.stat_abort, u_mac_tx_ch0.stat_frames}`（`tx_fe_clk_0`），目的 = `dp_clk` —— **一个实例同时采两半，保证 W87 的 frames/abort 同采样**；拆分时 `[63:32]=abort`、`[31:0]=frames`。
- **sat16 在 dp 域做**（`dst_val` 已是 dp 域寄存器）：`sat16(dst_val[31:16])` / `sat16(dst_val[15:0])`。
- **复位**：两侧各自 `*_rst_n`；目的域复位后 `dst_val=0`、`ack_tgl=req_tgl=0`。
- **门**：G6/单元门必须有一条“源域计数 +1 → 目的域在 ≤N 拍后 `dst_val+1`”的正向用例，以及“源域停在常值 → 目的域不重复增加”的负向用例；**裸 2FF 同步变异必须红**（把 `data_*` 改成单级或直接连到源寄存器）。

**N-12：W87[15:0] 的语义（必须钉死）**：`sat16(stat_frames)` 在 10G 正常速率下 **65535 / 800,000 fps ≈ 81.9 ms 饱和**（纸面算术；实际帧率随流量）。⇒ **W87[15:0] 只作“ch0 MAC TX 有活动”指示**：
- 不得用它作精确帧数、帧率或丢帧对账；
- 不得把“饱和到 0xFFFF”解读为故障；
- 精确 per-port TX 帧数用 **W83/W84**（32 位，27.487 s 回卷，差值 mod 2³² + raw/k）；
- P2-2 的 ch0 对账只用 W87[31:16] abort（饱和概率极低）与 W86 低半 txcdc ovf。

**sat16 定义（W86/W87）**：
```
function [15:0] sat16; input [31:0] v; begin sat16 = (v > 32'h0000FFFF) ? 16'hFFFF : v[15:0]; end endfunction
```
语义：**16 位饱和**；读数 = 精确值 when < 0xFFFF，否则只表示“≥0xFFFF”。差值口径：饱和后只记“≥0xFFFF”，**不参与精确对账**；健康窗（P2-2 正常）应恒 0 或很小（**W87[15:0] 例外：它是帧计数，正常就会饱和，见 N-12**）。

**装配**：
- `snap_dout_all`（`:4601`）顶部加 5 项（MSB 端）：W87/W86/W85/W84/W83；**非 DUAL 支按 §2.7 的常量表 tie-off（N-10）**；
- `SNAP_P7BDP_NW 39→44`（`:3543`）；`SNAP_NW_P6E 83→88`（`:3522`）；p7bdp 槽 39..43（`:4406-4455` 末尾加 5 行）；
- `.SNAP_NW(SNAP_NW_P6E)`（`:5305`）自动跟随；
- 预算复算：`{snap_idx,5'b0}` 最大 = (88−1)<<5 = 2784 < 4096 ⇒ `snap_base[11:0]` 不动；`snap_idx = r_word[6:0]-8` 最大 87 < 119。

**为什么不再加 per-port merge 帧/丢帧字（H-7 建议的偏离）**：
- 入口已有 **W79（ch0 好帧）/ W0（ch1 MAC 帧）**；出口有 **W85**；merge 本身**无内部丢帧路径**（selected 口 backpressure 回上游，未选中口 `tready=0`）。
- 上游溢出已有 **W82/W4（MAC drop）** 与 **W86/W38（FIFO ovf）**；再挂 per-port merge 计数只会重复输入侧信息。
- 公平性判断用 `ΔW79` 与 `ΔW0` 同时前进 + 两口 drop 计数；若 merge 饿死某口，其输入 FIFO 先满、MAC drop 先涨 ⇒ 可归因。

**成本**：5 字 × 96 FF ≈ **+480 FF**（`hold_b`/`dout_a`/`snap_words_r` 三份），全落既有 p7bdp 束 ⇒ 不新增 CDC 束、不改快照 FSM。0x28 的先例是“快照阵列异步复位族”当过全局 WNS 宿主 ⇒ 构建轮必须定向观察。

**backstop（几何，按序；每档 = 新输入，不许重跑到过）**：
1. 删 W86/W87 ⇒ NW 86 / MIR `0x178..0x184` / UNIMPL `0x188`（保留 W83..W85）；
2. 删 W85 ⇒ NW 85 / MIR `0x174..0x180` / UNIMPL `0x184`；
3. 删 W83/W84 ⇒ NW 83 / `0x17C`（BID-only 阶段）；
4. 若仍失败 ⇒ **abort-to-0x2B**（丢掉 P2 本轮全部、保留 P1）；不允许“`PER_CONN_SRC_IP=0` 但保留双口接线”的半残态。

### 3.5 快照几何（NW 88）

| 字 | 地址 | 说明 |
|---|---|---|
| W79..W82 | `0x15C/0x160/0x164/0x168` | **不变**（P1 已入库） |
| W83 | `0x16C` | TX port0 帧数 |
| W84 | `0x170` | TX port1 帧数 |
| W85 | `0x174` | classify 总帧 |
| W86 | `0x178` | ch0 FIFO ovf（16+16 饱和） |
| W87 | `0x17C` | ch0 MAC TX（16+16 饱和；**低半仅活动指示，N-12**） |
| MIR_STATUS/DATA×3 | `0x180/0x184/0x188/0x18C` | 四字 |
| UNIMPL | `0x190` | `0x20 + 4×88 + 16` |

- `SNAP_NW_P6E = 88`；`SNAP_P7BDP_NW = 44`（槽 39..43 = W83..W87）。
- 读侧译码 7 位 ⇒ 红线仍是**绝不能挑 ≥0x200**。
- **N-10（非 DUAL）**：上表 5 个字槽**都保留**，但 W83/W84/W86/W87 的来源为常量 0（§2.7）；W85 真。`tb_p7b_chain` 非 DUAL 断言见 §5.2 G9。
- **注意**：`tb_p7b_chain.v` 现读在 `0x16C` 断言 MIR_STATUS、在 `0x17C` 断言读 0；新几何下 `0x16C` 是 W83、`0x17C` 是 W87 ⇒ 必须按 §5.2 G9 改。

---

## 4. 双板 IP / HLS

### 4.1 常量与助手（`hls/src/eth_types.h`）

现读：`BOARD_IP_BYTE0..3`（`:119-123`）、`BOARD_MAC_BYTE0..5`（`:111-117`）。**没有**单一 `BOARD_IP` 宏（全仓 grep 确认；引用点都是 4 个 BYTE 宏）。

新增（保持单口默认）：

```c
#ifndef BOARD_IP_DUAL
#define BOARD_IP_DUAL 0
#endif
#ifndef BOARD_IP1_BYTE0
#define BOARD_IP1_BYTE0 192
#define BOARD_IP1_BYTE1 168
#define BOARD_IP1_BYTE2 100
#define BOARD_IP1_BYTE3 4        // 192.168.100.4 = ch0/J7
#endif
static inline uint32_t board_ip0_u32(void) { return (BOARD_IP_BYTE0<<24)|(BOARD_IP_BYTE1<<16)|(BOARD_IP_BYTE2<<8)|BOARD_IP_BYTE3; }
static inline uint32_t board_ip1_u32(void) { return (BOARD_IP1_BYTE0<<24)|(BOARD_IP1_BYTE1<<16)|(BOARD_IP1_BYTE2<<8)|BOARD_IP1_BYTE3; }
static inline bool board_ip_match(uint32_t dst) {
#if BOARD_IP_DUAL
    return dst == board_ip0_u32() || dst == board_ip1_u32();
#else
    return dst == board_ip0_u32();
#endif
}
static inline uint32_t board_src_ip(uint32_t dst) {
#if BOARD_IP_DUAL
    return (dst == board_ip1_u32()) ? board_ip1_u32() : board_ip0_u32();
#else
    (void)dst; return board_ip0_u32();
#endif
}
```

**广播语义（登记）**：IPv4 广播 `dst==0xFFFFFFFF` 没有“哪个口”的身份，双口下 `board_src_ip` 返回 IP0 ⇒ 只从 ch1/J8 出。ARP 不走这里（用 target_ip，天然有身份）；DHCP/广播 ping 在双口下退化为单身份。单口行为与今天完全一致。
**MAC**：沿用单一 `BOARD_MAC = 00:0A:35:01:FE:C0`（直连可接受）；per-port MAC 不在 P2（待裁）。

### 4.2 HLS 匹配/源 IP 逐点清单（现读行号）

| 文件 | 现读位置 | 现内容 | 改法 |
|---|---|---|---|
| `hls/src/layer_ip.cpp` | `:76-81` | `board_ip` 单值 + 广播判定 | `board_ip_match(ip_rx.dst_ip) \|\| (dst==0xFFFFFFFF)` |
| `hls/src/layer_arp.cpp` | `:149`（request SPA）、`:194-195`（reply 目标匹配）、`:201`（reply SPA） | `BOARD_IP_BYTE*` / `board_ip` | request 用 IP0；匹配 `board_ip_match(target_ip)`；**reply SPA = `board_src_ip(target_ip)`**（= target_ip） |
| `hls/src/layer_tcp.cpp` | `:10-12` `MAX_TCP_CONN=3`；`:142-149` `tcp_find`；`:165-181` `cfg_write`；`:177` w2；`:267-292` `tcp_send` | 全用 `BOARD_IP` 常量；`tcp_find(port, ip)` | `tcp_conn_t` +`uint32_t local_ip`；`tcp_find(port, peer_ip, local_ip)` 加 1 比较；`cfg_write` 加 `local_ip` 参数（w2=local_ip）；`tcp_send` 的 sip/IP 头用 `c.local_ip`；T_LISTEN 建连存 `board_src_ip(ip_rx.dst_ip)`；T_SYN_SENT 存 IP0；RST 处理器（`:631-645`）加 local_ip 匹配 |
| `hls/src/layer_udp.cpp` | `:140`（dst）、`:168-171`（源 IP 头） | `BOARD_IP_BYTE*` | `udp_tx_process` 加 `rx_dst_ip` 入参；echo 的源 = `board_src_ip(rx_dst_ip)`；HELLO 源 = IP0 |
| `hls/src/layer_icmp.cpp` | `:141-143` | `BOARD_IP_BYTE*` | `board_src_ip(ip_rx.dst_ip)` |
| `hls/src/layer_igmp.cpp` | `:121-122` | `BOARD_IP_BYTE*` | `board_src_ip(ip_rx.dst_ip)`（**L-11 措辞**：分发在 `udp_echo.cpp:172-173` 是活的；不可达因 `layer_ip.cpp:76-81` 只放行 board IP/0xFFFFFFFF，组播 224.x 被拒；仍按“死代码一致性改”处理） |
| `hls/src/udp_echo.cpp` | `:184-205`（UDP 解析）、`:227-229`（`udp_tx_process` 调用） | 只传 `rx_src_ip` | 加 `rx_dst_ip = ip_rx.dst_ip` 并传给 `udp_tx_process` |
| `hls/src/layer_dhcp.cpp` | 全文 | src=0.0.0.0 | **不改**；双口 = 静态 IP，DHCP 不在范围 |

**M-1 的 `cfg_write` 签名与调用点（逐字）**：
```c
static void cfg_write(hls::stream<ap_uint<32> > &cfg_stream, uint8_t cmd,
                      int8_t cid, uint32_t peer_ip, uint32_t local_ip,
                      uint16_t peer_port, uint64_t peer_mac, uint16_t peer_wnd,
                      uint8_t wscale, uint32_t rcv_nxt, uint32_t snd_nxt)
```
- `w[2]=local_ip;`（替换 `:177` 的 4 个 BYTE 宏）。
- DEL 调用点 `:609/637/699/721`：`cfg_write(cfg_stream,CFG_CMD_DEL,cid,0,0,0,0,0,0,0,0);`
- ADD 调用点 `:663`（T_SYN_SENT）与 `:677`（T_LISTEN）：`cfg_write(cfg_stream,CFG_CMD_ADD,cid,c.peer_ip,c.local_ip,c.peer_port,rx_smac,wnd,c.peer_wscale,c.peer_seq,c.seq[+1]);`
- `tcp_conn_t`（`:96-130`）加 `uint32_t local_ip;`；T_LISTEN 分支 `:670-681` 在 `cfg_write` 前 `c.local_ip=board_src_ip(ip_rx.dst_ip);`；T_SYN_SENT 建连路径（`:420-490` 的主动连接 setup）`c.local_ip=board_ip0_u32();`。
- `tcp_find` 调用点 `:581`：`tcp_find(sp, ip_rx.src_ip, ip_rx.dst_ip)`。
- **RST-to-released-slot 语义（M-1）**：RTO 超限释放槽时只置 `state=T_FREE`，**保留** `peer_ip/peer_port/local_ip`；新连接 setup 覆盖这三项。RST 循环 `:631-645` 的匹配改为 `peer_port==sp && peer_ip==ip_rx.src_ip && local_ip==ip_rx.dst_ip`。G8 加用例：在 IP_B 上建连 → 强制 RTO 释放 → 对端从 p0 发 RST（src .101 → dst IP_B）→ 断言 HLS 命中并 CFG_DEL（不是静默）。
- **L-9**：`arp_send_request` 的 SPA 仍是 IP0；`ACTIVE_CONNECT=0` 下无影响；若将来打开主动连接，ARP who-has 会从 ch1 出而无视目标口——登记。

### 4.3 `cfg_write.w2` 的下游链路（确认无 RTL 改动）

`HLS cfg_write w2 = local_ip` → `slow_cfg_adp` S_CAM 写 `cam_cfg_dip`（`rtl/slow_cfg_adp.v:148`）→ wrapper `cam_cfg_dip_mux`（`:2186`）→ `tcp_cam.dip_r`（`rtl/tcp_cam.v:37,51`）→ `rd_dip`（`:71-75`）→ wrapper `cam_rd_dip`（`:2210`）→ `tcp_tx_frame`（§2.3）。**`slow_cfg_adp` 零改动。**

### 4.4 1/2 口兼容与单口零回归（HLS）

- **一个 canonical HLS 输出（采用）**：`hls/run_hls.tcl` 的 `add_files` 加 `-cflags "-DBOARD_IP_DUAL=1"`，重新综合并**归档旧 `slowstack_prj/solution1/syn/verilog`**。之后 `board/build_p7b_ku5p.tcl:27` 的 `hls_dir` 与所有现有门都自动用新网表。
- **单口功能等价**：`BOARD_IP_DUAL=0` 与 `=1` 的 csim 对 `dst=IP0` 的 ARP/ICMP/UDP/TCP 回包**逐字节相同**；`=1` 额外接受 `dst=IP1`。**网表不逐位相同**（HLS 源变了）；这是“功能零回归”。
- **M-2 显式语义**：canonical 网表被所有构建共用 ⇒ **默认单口构建的 HLS 也接受 IP_B**。单口在位流级的行为变化 = “对 IP_B 的帧会应答”；对现有只使用 IP_A 的对端无影响。若要位级不变只能走**双输出目录**（`run_hls_dual.tcl` + `slowstack_prj_dual`；默认/其它构建指旧目录）。不选，登记为备选。
- **M-3 指纹**：HLS 网表 `.v/.dat` 已在 `p4gate.py` 的指纹内；v2 再把 `hls/src/*.cpp|*.h`、`hls/run_hls.tcl` 加进 `FINGERPRINT_GLOBS`，并让构建/门日志记 `HLS_SRC_HASH`/`HLS_NET_HASH`。
- **HLS 面积/时序 = 未测**：+`local_ip`（3×32 FF）+ 匹配比较 + `tcp_find` 比较；HLS 在 DP 域 156.25 MHz 下运行（`wrapper_p4.v:2710` `.ap_clk(dp_clk)`），而综合约束是 K7 8 ns（`hls/run_hls.tcl`）⇒ 构建轮定向看 `u_hls/*` 是否进 DP top-10。

### 4.5 `MAX_TCP_CONN=3` / 分池 / app 事件 / B-1 取舍

- **`MAX_TCP_CONN=3`**（`hls/src/layer_tcp.cpp:10-12`）= 全系统同时连接上限。P2 验收 = **每口 1 条**（2 ≤ 3）；**每口 2 条（4）结构性不够**（需扩 HLS 连接表，另开轮）。登记（§6.1）。
- **`WIN_POOL = 49152 B` 共享**（`rtl/app_ctrl.v:277` `WIN_POOL=16'hC000`；wrapper 未覆盖）。**B-1/D4 = 选项 (a)**（M-7/M-8 并入本条）：
  - `WIN_Q_MAX` **不做 wrapper 传参**（`rtl/app_ctrl.v:283-290` 逐字纪律：“不做成 wrapper 传参…漏一个就是门与板两个配置”）；保持参数默认 `16'hC000`（`:296`）⇒ `wq_cap_r` 复位 `0xC000`（`:530-533`）。**零 RTL 改动**。
  - 后果（既有 P5d 语义）：**先建连者先占池**，第一条连接可拿满 **49,152 B**（`WIN_POOL=0xC000`）；第二条 `g_grant = min(0xC000, pool-occ)` 可能 = 0 ⇒ 零窗。**P2-2 只要求每口各自建连/身份正确**，不要求两口同时有数据流；数据流测试**逐口顺序**做。
  - **【v2.1 N-1 修订：池归还见证】**v2 的“第二条建连后立刻用对端 `ss -ti` 读 `snd_wnd > 0`”**降级为无效见证**：HLS 的 SYN-ACK 窗口硬编码 `0xC000`（`hls/src/layer_tcp.cpp:281`），在 fast-path 发出第一条带窗 ACK 之前，`snd_wnd` 只反映 SYN-ACK 的 0xC000，**与池是否归还无关**。v2.1 改用 **fast-path 纯 ACK 双探针**：
    1. 第一条连接关闭并确认板侧 `CONN_DOWN`/DEL 后，**等 ≥ 1 个池归还扫描周期**（建议 ≥10 ms；归还逻辑 = `app_ctrl` ev_down/扫描，见 `app_ctrl.v:75/121-125`），再建第二条；
    2. 在第二条连接上由对端发 **1 字节数据探针 ×2**（两次探针间隔 ≥ a few ms；第二字节的 seq = 前一字节 + 1）；
    3. 板侧 fast path 对“顺序段但窗不足”会回纯 ACK（`rtl/tcp_rx.v:364-370` 的 `ackresp`：`seq_eq && !win_ok`）——**零窗时也有正见证**；对窗内数据则走正常 `ack_req`；
    4. 用 pcap 抓这两条纯 ACK，读 `tcp.win`：
       - **两帧 `win == 0`** ⇒ 池**未**归还（`winq=0` ⇒ TCB rcv_wnd=0；`app_ctrl.v:281-283` 逐字“winq=0 ⇒ 通告窗 0 ⇒ 线上每帧 win=0 —— 永久而非瞬态”）；
       - **两帧 `win > 0`（且两帧一致或按窗口更新解释）** ⇒ **已归还**；值应为 `min(0xC000, g_grant)`；
       - 两帧不一致 ⇒ 记“窗口中途变化”，按时间顺序解释；不据此判“已归还”。
    5. **帧源判别（必须，不能只看值）**：
       - **flags/seq/ack**：必须是 `ACK` only（非 SYN-ACK），且 `ack == probe_seq + 1`；这排除了 HLS 的 SYN-ACK（`seq=ISS`、`ack=客户端 ISN+1`、SYN 置位）与 HLS 握手纯 ACK（`layer_tcp.cpp:665`，`seq=ISS+1`、`ack=客户端 ISN+1`，只发生在 `T_SYN_RCVD`）。
       - **IP ID**：HLS `tcp_send` 逐字 `ip[4]=0; ip[5]=0`（`hls/src/layer_tcp.cpp:290`）⇒ **HLS 帧的 IP ID 恒 0**；fast-path `tcp_tx_frame` 用 16 位滚动 `id_cap <= id_r`（`rtl/tcp_tx_frame.v:2414` / `:1327`）⇒ 两条探针 ACK 的 `ip.id` 应为**不同值**（允许 16 位回卷；若两条都 = 0，记“帧源未判定”，换下一轮探针）。**值恰好 0xC000 不构成证据** —— HLS 的 SYN-ACK/握手 ACK 也是 0xC000（`layer_tcp.cpp:281`），必须按上述帧源判别排除。
       - 若 N ms（建议 100 ms）内**没有任何** fast-path 纯 ACK ⇒ 记“**零窗/无响应不可分（未判定）**”，不得判“已归还”，也不得判“PASS”。
    6. **`ss -ti` 只作二次核对**：仅在上一步已抓到 fast-path 纯 ACK 之后读，且要求 `ss -ti` 的 `snd_wnd` 与该 ACK 的 `tcp.win` **相等**；**“建连后立刻读 `snd_wnd`”不再作为见证**（它只反映 SYN-ACK 的 0xC000）。
    7. **sim/G6/G8 辅助**：`app_ctrl` 的 `0x97 = {15'b0,pool}`（自由池余额）与 `0x9A = {16'b0,winq[0]}`（`rtl/app_ctrl.v:57/59`）可直接读；**板上 `app_reg_addr/wr/wdata` 静态钉死（`wrapper_p4.v:1547-1549`）⇒ 板上不可用，只作门**。
  - **“双口同时数据流”= 待用户裁**（选项 b）：`WIN_Q_MAX=0x6000` + P2-1 判据改写（两臂现取 `ss -ti`；单口速率只要求 24.6 KB 窗口下的可解释值）+ 保留一个 `WIN_Q_MAX=0xC000` 的对照构建臂用于归因。**未获裁定前不实施**。
  - **HLS SYN-ACK `0xC000` 与配额一致性 = P3 前置项**：`hls/src/layer_tcp.cpp:281` 的 `tcp_build_hdr(...,0xC000,...)` 是硬编码。选项 (a) 下第一条连接配额 = `0xC000` ⇒ 一致；第二条连接配额 0 而 SYN-ACK 仍通告 48K ⇒ **window shrink**。P3 必须在“HLS 通告 `min(0xC000, wq_cap)` / 快路径接受初始窗 / 其他机制”中定案；P2 **不伪造**。
  - 板上没有可用 app 寄存器总线（`wrapper_p4.v:1547-1549` 静态钉死 `app_reg_addr=0/wr=0/wdata=0`）⇒ 运行时写 `0x0C` 分池不可用。
- **`app_ctrl` 事件字**（`rtl/app_ctrl.v:462` `EW=102`、`:468-469` `{kind, slot, peer_mac, peer_port, peer_ip}`）**无端口位**。P2 **不加**（app 总线在板上不可用，加了也没有消费者）；登记为 P3/后续可选项。
- **接收物理缓冲**：单 `tcp_echo` `frame_fifo`（16 BRAM）由两口共享；P2 验收按“单流/逐口”做，不要求两口同时满速。

### 4.6 甲模式对端配置（含 H-2 静态邻居）

板：IP_A `192.168.100.2/32`（ch1/J8）、IP_B `192.168.100.4/32`（ch0/J7）；板 MAC = `00:0A:35:01:FE:C0`。
对端（SFC9120 双口）：p1 = `enp1s0f1np1`（现役，`192.168.100.1/32`）；p0 = `enp1s0f0np0`（建议 `192.168.100.101/32`）。

**推荐：两个 netns（最强“错口不可见”）+ 静态邻居（P2-3 判据的必要条件）**：
```
# L-8: 先在根 ns 关闭 NM 管理，再移入 netns
nmcli device set enp1s0f1np1 managed no
nmcli device set enp1s0f0np0 managed no
ip netns add nsa; ip netns add nsb
ip link set enp1s0f1np1 netns nsa   # p1 <-> 板 J8 (IP_A)
ip link set enp1s0f0np0 netns nsb   # p0 <-> 板 J7 (IP_B)
ip -n nsa addr add 192.168.100.1/32 dev enp1s0f1np1; ip -n nsa link set enp1s0f1np1 up
ip -n nsb addr add 192.168.100.101/32 dev enp1s0f0np0; ip -n nsb link set enp1s0f0np0 up
ip -n nsa route add 192.168.100.2/32 dev enp1s0f1np1
ip -n nsb route add 192.168.100.4/32 dev enp1s0f0np0
# H-2: 静态邻居（p1 必须知道 IP_B 的 MAC 才能发 SYN；否则 SYN 根本发不出）
ip -n nsa neigh replace 192.168.100.4 lladdr 00:0a:35:01:fe:c0 nud permanent dev enp1s0f1np1
ip -n nsb neigh replace 192.168.100.2 lladdr 00:0a:35:01:fe:c0 nud permanent dev enp1s0f0np0
# 两 ns 各（注意：sysctl 必须在 netns 内执行，否则改的是根 ns）:
#   ip netns exec nsa sysctl -w net.ipv4.conf.enp1s0f1np1.rp_filter=0
#   ip netns exec nsa sysctl -w net.ipv4.conf.enp1s0f1np1.arp_ignore=1
#   ip netns exec nsa sysctl -w net.ipv4.conf.enp1s0f1np1.arp_announce=2
# 两 ns 各（N-8: `ip -n <ns> exec` 非法；exec 是 netns 对象的子命令）:
ip netns exec nsa ethtool -C enp1s0f1np1 adaptive-rx off rx-usecs 0   # 全局 #68
ip netns exec nsb ethtool -C enp1s0f0np0 adaptive-rx off rx-usecs 0
```
**N-8 说明**：`ip -n <ns> exec ...` 不是合法 iproute2 用法；`-n` 只适用于 `ip` 自己的对象（`addr/link/route/neigh`），`exec` 属于 `netns` 对象 ⇒ 写 `ip netns exec <ns> <cmd>`。同配方其余 `ip -n nsa/nsb addr|link|route|neigh` **合法，保留**。
**备选（单 netns）**：两口各 `/32` + 显式路由 + `arp_ignore=1/arp_announce=2/rp_filter=0` + 静态邻居。**弱主机模型会掩盖错口**（同一主机两个 IP 都属于本机）⇒ 只有 netns 或不同子网能给出“错口必须失败”的判别力。

**H-2 判据拆两段（P2-3）**：
1. **身份（ARP 层隔离）**：在 nsA 执行 `arping -c 1 -I enp1s0f1np1 192.168.100.4`（或 `ip neigh` 触发）。p1 pcap 见 who-has；**无应答**（板 HLS 的 ARP reply SPA=IP_B，`slow_tx_adp` 提取端口位 1 ⇒ 从 ch0/J7 发出 ⇒ p1 永远收不到）。反向 p0→IP_A 同理。
2. **出口（真负对照）**：静态邻居就位后，nsA 向 IP_B 发 SYN。p1 pcap 见 SYN；**p0 pcap 见 SYN-ACK 且 dst MAC = p1 MAC**（板的 `cam_rd_dmac` = p1 SYN 的源 MAC）；**p1 收不到 SYN-ACK**；连接 timeout。若 p1 收到 SYN-ACK ⇒ 出错误口（帧走了 ch1）；若 p0 什么也没看到 ⇒ 板没发（无判别力，登记）。反向 p0→IP_A 同理。
- **不做静态邻居时，P2-3 只能叫“ARP 层隔离”**，不能当出口判据。

---

## 5. 判据 / 门 / 构建 / 板级计划

### 5.1 P2 验收判据（草案，不下裁定）

| # | 判据 | 仪器/负对照 |
|---|---|---|
| P2-1 | **单口零回归（编辑后）**：双口位流只插 J8，TCP 连续流向 IP_A；**主口径 = 板内 `ΔW43/ΔW20` fps + `ΔW51/ΔW52`**，与 0x2B 同会话 A/B；预登记 **≤0.5% 结构性差值**（merge 1 拍仲裁）；`mism_bytes=0`/`stall=0`。**`W84 Δ=0` 必须与 `ΔW83>0` + 对端 p1 NIC 配对**，且 P2-2 提供“W84 能动”的正控（否则 `W84=0` 是空判据） | 板侧 W51/W52/W54/W55 + W83/W84；对端 p1 NIC；`PIN_CPU=` 见证 |
| P2-2 | **A-1 出口正确（H-8 + N-1 + N-7 修订）**：<br>**阶段 I 身份**：p1→IP_A、p0→IP_B **各自**建连（顺序），每条的 SYN-ACK 只在该口出现、源 IP = 该连接本地 IP；对端口无该帧。<br>**阶段 II 数据（逐口顺序）**：第一条关闭并确认板侧 DEL/CONN_DOWN 后，**等 ≥1 个池归还扫描周期（≥10 ms）**；第二条建连后，用**双 1 字节探针 + pcap 抓 fast-path 纯 ACK**判池归还（N-1 全流程见 §4.5）：两帧 `tcp.win==0` ⇒ 未归还；两帧 `>0` ⇒ 已归还；**帧源必须用 flags/seq/ack + 滚动 `ip.id` 判别**（HLS 的 IP ID 恒 0；值恰好 0xC000 不构成证据）；**无 fast-path ACK ⇒ “零窗/无响应不可分（未判定）”，不得判已归还**。`ss -ti` 只在已抓到 fast-path ACK 后作二次核对（`snd_wnd` 必须等于该 ACK 的 `tcp.win`）。**“建连后立刻读 `snd_wnd`” = 无效见证**。每口 `mism_bytes=0`。<br>**阶段 III 同时**：仅作登记（选项 a 下第二条可能零窗；不判失败）。<br>**对账（mod 2³² + raw+k；N-7）**：ch1 `Δpeer_p1 ≤ ΔW83` 且 `ΔW83 − Δpeer_p1 ≤ ΔW45(字) + ΔW21(帧) + INFLIGHT_MAX_FRAMES`；ch0 `Δpeer_p0 ≤ ΔW84` 且 `ΔW84 − Δpeer_p0 ≤ sat16(ch0_mac_tx_abort)(帧，W87[31:16]) + INFLIGHT_MAX_FRAMES`（**【v2.1-errata F-4/D-2】删掉 `sat16(ch0_txcdc_ovf)` 字级修正项** —— W86 低半是“AXIS 反压拍数”不是丢字数，且会饱和 ⇒ 原式是恒真的松上界；ch0 丢帧由 MAC `stat_drop`（W82）计）；窗 <27.487 s 或记回卷 k。**取窗前必须静默**：连接关闭/停流后，连续两次快照（间隔 ≥1 ms）`ΔW83=ΔW84=0`；若做不到，必须登记第三修正项 **`INFLIGHT_MAX_FRAMES = 33`**（纸面：txcdc 256 字 / 最小帧 8 字 + 1 帧在 MAC/线上；保守上界）。`port_rx_*` = **跨系统口径**（L-6） | 两条独立链（板 RTL 计数 vs 对端内核/NIC）；pcap 两口；`app_ctrl 0x97/0x9A`（仅 sim/G6/G8） |
| P2-3 | **构造性错口负对照（H-2 修订）**：静态邻居就位；判据拆 ① 身份（p1 对 IP_B 的 ARP who-has 无应答）与 ② 出口（p1 pcap 见 SYN + p0 pcap 见 SYN-ACK 且 dst MAC=p1 MAC + p1 收不到 SYN-ACK）；反向 p0→IP_A 对称。不做静态邻居 ⇒ 只写“ARP 层隔离” | netns + 静态邻居；两 ns pcap；板 W83/W84 |
| P2-4 | **RX 合并公平/守恒（M-6 + N-14 修订）**：两口同时灌 ≥ 聚合容量时，`ΔW79`（ch0 好帧，**语义 = 被 merge 输入 FIFO 接受的好帧数**，`tready = ~ch0_fifo_full`）与 `ΔW0`（ch1 MAC 帧）**都前进**；两侧 drop（W82/W4）可读；公平份额 ≈ 各 50%。**守恒只在干净窗判**：`ΔW81=ΔW82=ΔW4=0` 且无 TERM 时 `ΔW85 == ΔW79 + ΔW0`；否则残差 = 坏帧+TERM（不可分观测），只记不判。**FIFO 满造成的 ch0 丢帧进 W82（MAC `stat_drop`），不进 W79**；`ch0_rxcdc_ovf`（W86 高半）在 `tready=~full` 门控下应恒 0（安全网）。W85 为 `[31:0]` 截断和。单元门严格优先负对照必须红；板级 pcap（两口） | 单元门 STRICT 负控（G2）；板级 W79/W0/W82/W4/W85/W86 |
| P2-5 | **慢路径每口身份**：p0 对 IP_B 发 ARP/ICMP/UDP echo ⇒ 回包**只**在 p0 出现且源 IP=IP_B；p1 对 IP_A 同理。**加长时阻塞用例**（H-3）：`slow_tx_adp.m_axis_tready=0`，提交 60 个最小帧（480 字），断言 `side_level==committed`/`side_ovf==0`，放行后逐帧端口正确 | 对端两 ns pcap/NIC；G4 单元门 |
| P2-6 | **UDP app 每口（L-7 修订）**：从 IP_B 学 peer 后 app UDP TX 只从 ch0 出；从 IP_A 学后翻转。**主判据 = 每口 pcap**；板侧用 2 s 窗：`ΔW84 ≥ N_app`、`ΔW83 ≤ background_max + 容差`（HELLO/ARP 背景率预取，慢路径由 W7 计）；登记残差 | 板 W8/W9/W83/W84 + 两口 pcap |
| P2-7 | **单口隔离负对照**：`0x08` bit0=1（J7 TX_DIS）⇒ IP_B 连接停、IP_A 连接继续；bit1=1 反之 | P1 S-3 已证 bit0；bit1 需复跑 |
| P2-8 | **错误源 IP 可观测**：若某帧源 IP 错，对端 pcap 逐字节可见 + 该连接行为异常；单元门 `tb_tcp_tx_srcip` 的错 IP 变异必须红 | pcap + 单元门 |
| P2-9 | **HLS 单口等价（M-2 修订）**：`BOARD_IP_DUAL=0/1` 对 `dst=IP_A` 的 ARP/ICMP/UDP/TCP 回包逐字节相同；`=1` 另测 `dst=IP_B` 接受、`=0` 丢弃。csim 两二进制 + xsim 定向臂 | G8 |
| P2-10 | **构建门**：WNS>0 + 三类失败端点 0/0/0 + `12-4739` 0 + 隐式网 5 键 0 + DRC 0 Error + 模块解析断言（含黑盒检查）+ HLS 哈希归档 | 构建报告 |

### 5.2 门计划（现有 21 门 → 24 门）

现读：矩阵 **21 门**（`sim/p4gates/run_matrix_p4dfix.bat:184-261` 的 21 条 `call :gate`；`p7b_chain` = 第 20、`biz_win` = 第 21）。P2 注册 **G2/G5/G6** ⇒ **24**；G3/G4 为独立门（不在矩阵，登记债务）。

| 门 | 新/改 | 内容 |
|---|---|---|
| **G1 基线回归（改称“编辑后回归”）** | 现有 21 门 | 不是“零编辑”：`tb_p7b_chain.v` 几何编辑（G9）+ H-1 的 9 个 TB 接常量。预期 21 门全绿；指纹漂移逐条解释。加“新端口无 Z”断言（`VRFC 10-3645`+`peer_my_ip` 联合查 + 运行时 `$isunknown`）。**另加 N-2 自检**：无 `DUAL_SFP_A` 与有 `DUAL_SFP_A` 两种 elab 日志里 `VRFC 10-2989`/`not declared`/`8-36` 均 0 命中。 |
| **G2 `rx_merge2` 单元** | **新**（注册进矩阵） | `_proj_10g/p11_dual/sim/tb_rx_merge2.v`：单口工作保持 / 双口逐帧 RR 交替 / 帧原子性 / 随机反压 / 复位 / **STRICT=1 且 DEPTH=4 的负控**。**【v2.1 N-13 改写】负控必须同时满足：① 高优先口**持有一个有效帧**且 `tready=0` 持续 ≥N 拍（N 建议 ≥16）；② 低优先口**持续注入 ≥2 个最大帧**；③ 断言低优先口 `tready` 持续 0 且其 `ovf` 增长。只给低优先口注入而不给高优先口有效帧 ⇒ 工作保持的 `STRICT=1` 仍会服务低优先口，负控无牙。** 正臂断言 `stat_frames0/1` 逐帧交替。**另加 `.STRICT` 常量断言（或放 G7，见 N-9）**。 |
| **G3 `tx_demux2`+每口 arb 单元** | 新（独立门） | `tb_tx_split.v`：三口端口位分流 / 帧原子性 / 口内 TCP>UDP>HLS / **帧内 `s_port` 变化必须被 `stat_port_change` 抓到且不跨口分裂** / 端口反转变异红 |
| **G4 `slow_tx_adp` 端口提取单元** | 新（独立门） | `tb_slow_tx_port.v`：IPv4/ARP/短帧/无 VLAN；**错偏移变异必须红**；**H-3 长阻塞用例 + `SIDE_DEPTH=16` 溢出负控**（`side_ovf>0` 且 `side_level!=committed`）；**L-10 VLAN TPID 负控**（0x8100/0x88A8 ⇒ `vlan_seen` sticky、`o_port=0`） |
| **G5 `tcp_tx_frame` 源 IP/校验和单元** | **新**（注册进矩阵；两体各一臂） | `tb_tcp_tx_srcip.v`，编译 **OVL 与默认两体**：数据/控制/重放 × 两连接 A/B：IP 源、IP csum、TCP csum 逐字节；`o_port` 正确且 `tvalid && !tready` 期间逐拍不变（M-12）；**错 local IP 变异必须红**。**N-6 专项臂**：默认体在 `start_ack` 拍必须使用 `cam_rd_dip`（用一个“上一连接 local IP ≠ 当前连接 local IP”的序列触发；若实现误用 `lip_r`，SYN-ACK 的 TCP 伪头源 IP 错 ⇒ 该臂必须红）。 |
| **G6 双口全链 wrapper 门** | **新**（注册进矩阵） | `_proj_10g/p11_dual/sim/run_tb_p11_dual.bat`（真 wrapper + `DUAL_SFP_A` + `P7B_SIM_NOPCS` 双通道注入/捕获）。**H-6：必须从生产者入口驱动真实帧**。**臂 A = HLS 真实握手**（ARP/ICMP/SYN-ACK 走 `slow_tx_adp`，双 IP 重综合网表）；**臂 B = force 快臂**（驱动 `txin_*`/`app2_*` 或三个 demux 输入 `tx_*`/`utx2_*`/`stx_*`，**不 force `txsrc_*`**；`txsrc_*` force 只作 MAC 接线臂，单独记）。断言每口 W83/W84、每帧 `o_port` 与帧头源 IP 一致、跨口不串、端口反转变异红；两臂结果分开记（M-13）。**N-4：`maccnt_sync` 必须在 xvlog 清单里；加“源域计数 +1 → 目的域 `dst_val+1`”与“常值不重复增加”两用例；裸 2FF 变异必须红。** |
| **G7 elaboration 组合** | 改 `run_elab_4combo.bat`（7 → **12**） | 原 c1..c7 + c8 **DUAL+P7B+A+DP+APP = OK（正控）**、c9 DUAL 无 P7B = FAIL、c10 DUAL+`SFP2_MODE_B` = FAIL、c11 DUAL 无 DP = FAIL、c12 DUAL 无 APP = FAIL；`findstr` 签名表扩到 6 个（`SFP2_MODE_A_AND_B_CONFLICT`、`SFP2_MODE_B_REQUIRES_P7B_10G`、`DUAL_SFP_A_REQUIRES_P7B_10G`、`DUAL_SFP_A_AND_SFP2_MODE_B_CONFLICT`、`DUAL_SFP_A_REQUIRES_DP_156MHZ`、`DUAL_SFP_A_REQUIRES_APP_MODE`）。**`elab_files.f` 是运行时 `dir /b /s rtl\*.v` 生成**（§0.2-4），新件自动覆盖。注意：现 `COMMON` 是**无条件前缀**，c9/c11/c12 需要**减掉** P7B/DP/APP ⇒ 实施轮把 `:one` 改成逐组合**显式 `DEFS` 构造**（或加 `NOP7B/NODP/NOAPP` 开关），不要在 `COMMON` 上做字符串减法（cmd 变量运算易错）。**【v2.1 N-9 新增静态断言】**：`board/wrapper_p4.v` 中 **`.STRICT(1'b0)` 恰 1 处命中**（`u_rx_merge` 实例）、**`.STRICT(1'b1)` 0 命中**；任一不满足 ⇒ G7 硬失败。实现方式：`findstr /C:".STRICT(1'b0)" board\wrapper_p4.v` 计数 == 1，`findstr /C:".STRICT(1'b1)" ...` 计数 == 0（或等价 Python 检查）。若实施轮把该断言移进 G2，必须在 G2 行**点名**，不能在两处都缺失。 |
| **G8 HLS 双 IP** | 改 `hls/tb/udp_echo_tb.cpp` + 构建前 csim/xsim | csim **两二进制**（`-DBOARD_IP_DUAL=0/1`）：单口 `dst=IP_A` 逐字节等价 + 双 IP 匹配/回源 + `tcp_find` 同 peer 双 IP 分离 + **RST-to-released-slot（M-1）** + broadcast→IP0 + **dual 接受 IP_B / legacy 丢弃 IP_B（M-2）** + 既有 19 TEST 回归。xsim 定向臂 `_proj_10g/p11_dual/sim/tb_hls_dual_ip.v`（ARP/ICMP/UDP/TCP 到 IP_B）。**N-1 的 sim 辅助**：在 G6/G8 里读 `app_ctrl 0x97 pool` / `0x9A winq[0]`，断言“第一条关闭后 pool 回到 0xC000 / 第二条 ev_up 后 winq > 0”，作为板级 pcap 见证的**门级对照**（不替代板级）。 |
| **G9 几何/读侧** | 改 `sim/p6e_pcie/tb_p6e_pcie_wrapper.v`、`…_counters.v`、`_proj_10g/notes/p7b_biz_win/{check_window.py,tb_biz_win.v}`、`apply_readside_bid1c.py` 新阶段 0x2C；**新增 `tb_p7b_chain.v`**；**新增 `_proj_pcie` 读侧 4 工具** | 83→88 / `0x17C→0x190` / MIR `0x180..0x18C` / WLABEL 补 W83..W87。**`tb_p7b_chain.v` 逐条**：W79..W82 断言**不动**（0x15C..0x168）；新增 W83..W87 @0x16C..0x17C；MIR_STATUS 0x16C→**0x180**；UNIMPL 0x17C→**0x190**。构建前置核 `grep -n "0x17C reads 0" tb_p7b_chain.v` **为空**（旧断言必须消失）。**【v2.1 N-10】非 DUAL 运行：W83/W84/W86/W87 ≡ 0、W85 跟随 classify**（TB 里加显式断言；不得留空期望）。**【v2.1 N-5】读侧工具清单见下表；`apply_readside_bid1c.py` 增阶段 0x2C（NW=88 / UNIMPL=0x190 / W83..W87 标签）。【v2.1 N-14】`P7B_BIZ_WINDOW.md:77` 的 W79 标签同步为“merge 输入 FIFO 接受的好帧数”。** |
| **G10 矩阵** | 改 `run_matrix_p4dfix.bat` + `paths.txt` + 新 manifest | **24/24**、FROZEN、指纹漂移逐条解释；`paths.txt` 的 `FINGERPRINT_GLOBS` 加 `_proj_10g\p11_dual\sim\run_*.bat`、`tb_*.v`、`hls\src\*.cpp`、`hls\src\*.h`、`hls\run_hls.tcl`；新增 `sim/p4gates/p11dual_src.f`、`p11merge_src.f`、`p11srcip_src.f`；`MANIFEST_GLOB=sim\p4gates\*_src.f` 自动覆盖。**【v2.1 N-4】`p11dual_src.f` 必须含 `rtl/maccnt_sync.v`；`p11merge_src.f` 只在 G2 另编 W86/W87 单元时需要；`p7bchain_src.f` 若编 DUAL 支必须含 `maccnt_sync.v`。** |

**G9 读侧工具同步清单（N-5，必须逐项写进 G9 的施工单）**：

| # | 文件 | 现读默认/硬编码 | 0x2C 目标 | 备注 |
|---|---|---|---|---|
| 1 | `_proj_pcie/p6e_snap_check.sh` | `:60 EXPECT_BID=${EXPECT_BID:-0x0000002B}`；`:72 SNAP_WORDS=${SNAP_WORDS:-83}`；`:73` 由 `SNAP_WORDS` 派生 `UNIMPL_ADDR=0x17C` | `EXPECT_BID=0x0000002C`；`SNAP_WORDS=88`；派生 UNIMPL=**0x190** | 注释里的历史代（0x2A/0x29/0x28/0x0A）保留 |
| 2 | `_proj_pcie/p7b_biz/p7b_snap.sh` | `:85 NW=${NW:-83}`；`:87 EXPECT_BID=${EXPECT_BID:-0x0000002B}`；`:86` 派生 UNIMPL=0x17C | `NW=88`；`EXPECT_BID=0x0000002C`；UNIMPL=**0x190** | 头部“现役 = 83 字 / BID 0x2B”注释同步为 88/0x2C |
| 3 | `_proj_pcie/p7b_gate4_negctrl.sh` | `:156 awk -v NW=83` | `awk -v NW=88` | 该负控的“末字回绕”依赖 NW；改后重跑负对照 |
| 4 | `_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py` | `STAGES` 末项 = `("0x0000002B", EDITS_2B, "P11 P1 ch0 bring-up (2026-10-18)", 83, 0x17C)` | 追加 `("0x0000002C", EDITS_2C, "P11 P2-甲 双口 + 双 IP (2026-10-18)", 88, 0x190)`；`EDITS_2C` 覆盖下列文件的默认值/标签：`j6_r6fix.sh`、`tcpreg_j6.sh`、`p7b_snap.sh`、`p6e_snap_check.sh`、`p7b_gate4_negctrl.sh`、`check_window.py`（`nnew_top` 17→22，W83..W87 的 WLABEL） | 新阶段必须过 `assert_tables(88)` / `assert_defaults(0x2C)`；**0x2C 阶段不得改历史注释的逐字原文** |

**G9 自检门（N-5 配套）**：在缺省上下文（**赋值行**，不含历史注释）grep 旧值必须 0 命中：
```
grep -nE '^\s*(EXPECT_BID|SNAP_WORDS|NW|UNIMPL_ADDR)=\$\{[A-Z_]+:-0x0000002B\}' _proj_pcie/p6e_snap_check.sh _proj_pcie/p7b_biz/p7b_snap.sh
grep -nE '^\s*(EXPECT_BID|NW)=\$\{[A-Z_]+:-83\}' _proj_pcie/p7b_biz/p7b_snap.sh
grep -nE 'awk -v NW=83' _proj_pcie/p7b_gate4_negctrl.sh
```
例外清单（明确保留、不算命中）：所有以 `#` 开头的历史注释行、`p9_build_0x2B_*` 归档件、`p7b_build_*` 历史 README。**“注释里有 0x2B/83”不算失败；“默认赋值仍是 0x2B/83”才算失败。**

### 5.3 构建计划

- **BID = `0x2C`**（`wrapper_p4.v:4824` `BUILD_ID_V`）；乙顺延 **0x2D**。**【v2.1 N-11】P1 `DESIGN_v5.md` 的“乙 = 0x2C”作废，见 §0.2-7。**
- **宏**：`build_p7b_ku5p.tcl:286` 在现有 8 宏后**追加** `DUAL_SFP_A=1`（不覆盖；日志回读 `P7B_VERILOG_DEFINE` 核 9 项）。
- **HLS**：先跑 `run_hls.tcl`（`add_files -cflags "-DBOARD_IP_DUAL=1"`），归档旧 `slowstack_prj` 输出；记 `HLS_SRC_HASH`/`HLS_NET_HASH`；再构建。
- **新件导入（H-4 + N-4，硬前置）**：在 `P7B_ADD_DATAPATH`（或新 `P7B_ADD_DUAL`）加
  `${root_dir}/rtl/rx_merge2.v ${root_dir}/rtl/tx_demux2.v ${root_dir}/rtl/maccnt_sync.v`。
  构建后**模块解析断言（N-3 修订：黑盒硬门，cell-count 仅辅助）**：
  ```tcl
  open_run synth_1
  set c1 [get_cells -hier -quiet -filter {REF_NAME =~ rx_merge2}]
  set c2 [get_cells -hier -quiet -filter {REF_NAME =~ tx_demux2}]
  set c3 [get_cells -hier -quiet -filter {REF_NAME =~ maccnt_sync}]
  set n1 [llength $c1]; set n2 [llength $c2]; set n3 [llength $c3]
  puts "P7B_MODULE_RESOLVED rx_merge2=$n1 tx_demux2=$n2 maccnt_sync=$n3"
  if {$n1 < 1 || $n2 < 1 || $n3 < 1} { puts "P7B_MODULE_MISSING" ; exit 1 }
  # N-3: cell-count 对黑盒也返回实例 ⇒ 必须查 IS_BLACKBOX（辅助 cell 计数不是硬门）
  set bb 0
  foreach c [concat $c1 $c2 $c3] {
      if {[get_property IS_BLACKBOX $c]} { incr bb }
  }
  puts "P7B_BLACKBOX_COUNT $bb"
  if {$bb != 0} { puts "P7B_MODULE_BLACKBOX" ; exit 1 }
  ```
  并**必须**在 synth 日志查 `black box` / `8-3491`（未解析模块）为 0 —— **这条日志 grep 才是硬门**；若 `get_property IS_BLACKBOX` 在该 Vivado 版本不可用（属性名变更），用 `report_black_boxes`（若存在）或直接以日志 grep 为准，并在构建报告里写明所用判据。**不得**只凭 `n1/n2/n3 ≥ 1` 判“已解析”。
- **一次性收口**：WNS>0 / WHS>0 / 三类失败端点 0/0/0 / `12-4739` 0 / 隐式网 5 键 0 / DRC 0 Error / 位流 sha256 + BID 归档（#54 写进构建脚本）/ `HLS_*_HASH` 归档。
- **构建轮定向 STA 观察点**（`-from` 定向，不靠 top-200 清单——#66）：
  `u_tcp_tx/f_lip_reg*`、`u_tcp_tx/ctrl_lip_reg*`、`cam_rd_dip` 到 `u_tcp_tx/*csum*`、
  `u_rx_merge/*`、`u_tx_udp_arb/u_tx_arb`（每口）、`u_snap_p7bdp/hold_b_reg[1248..1407]`（新增 5 字 = 160 位）、
  `u_hls/*`（HLS 重综合后的新锥）、`maccnt_sync`（W87 的 CDC 采样）、`IP_B_5`/`DUAL_SFP_A_DEF` 的常量折叠（非 DUAL 构建不应留下 `cam_port_arr`）。
- **backstop（预登记顺序，见 §3.4）**：W86/W87 → W85 → W83/W84 → abort-to-0x2B；每档 = 新输入，不许重跑到过。
- **H-7 偏离报告**：见 §6.1 D12。

### 5.4 板级计划（草案；不写 PASS/FAIL）

**前置**：重烧 0x2C + 核 sha256；身份门 `0x04=0x2C` / **88 字** / `0x190=0xffffffff` / MIR `0x180..0x18C` 可读 / 2 BARs / `LnkSta x4` / `0x08=0`；两口 AOC 在位（J7↔p0、J8↔p1）；对端 netns + **静态邻居**（§4.6）配置现取见证（`ip -n … addr/route/neigh`、`ip netns exec … ethtool -C`、`ss -ti`）；两口 coalescing 关；`nmcli managed no`（根 ns，移入 netns 前）；记录 `PIN_CPU=`。

| # | 动作 | 期望读数（草案） | 独立仪器/负对照 |
|---|---|---|---|
| B-0 | 入口态 + 身份门 | BID/几何/UNIMPL/2 BARs/x4；`0x08=0`；p0/p1 carrier=1；静态邻居在位 | 对端 `ip -br neigh` |
| B-1 | 单口回归（只插 J8；J7 不插或 TX_DIS） | TCP 连续流 9 Gbps 级 / `mism=0` / `stall=0`；**W84≡0** 且 **W83>0**；与 0x2B 同会话 A/B 差值 ≤0.5% | 0x2B 同会话 A/B；对端 p1 NIC；#43/#59/#68 台架帽记录 |
| B-2 | 双口各一条 TCP（**顺序**） | 阶段 I：p1→IP_A、p0→IP_B 各自建连；SYN-ACK 只在该口、源 IP 正确。阶段 II：逐口数据；第一条关闭后等 ≥10 ms；第二条用**双 1 字节探针 + pcap fast-path 纯 ACK** 判池归还（`win==0` ⇒ 未归还；`win>0` ⇒ 已归还；**帧源按 flags/seq/ack + 滚动 `ip.id` 判别；值恰好 0xC000 不构成证据**；无 fast-path ACK ⇒ 未判定）；`ss -ti` 只在已抓到 fast-path ACK 后作二次核对（`snd_wnd` 必须等于该 ACK 的 `tcp.win`）。每口 `mism=0`。阶段 III：同时只登记（选项 a 下第二条可能零窗） | 两条独立链；pcap 两口；W62/W83/W84/W86/W87 对账（mod 2³² + raw+k + N-7 的静默前件/在飞项） |
| B-3 | **错口负对照（H-2）** | ① 身份：p1 对 IP_B 的 ARP who-has **无应答**；② 出口：p1 pcap 见 SYN + p0 pcap 见 SYN-ACK（dst MAC=p1 MAC）+ p1 收不到；反向对称 | netns + 静态邻居；两 ns pcap；板 W83/W84 |
| B-4 | 慢路径逐口 | p0 对 IP_B：ARP/ICMP/8080 UDP echo 回包只在 p0、源 IP=IP_B；p1 对 IP_A 同理 | 两 ns pcap + NIC |
| B-5 | UDP app 逐口 | 从 IP_B 学 peer ⇒ app TX 只出 ch0（W84 涨、W83 ≤ 背景+容差）；从 IP_A 学 ⇒ 翻转 | 板 W8/W9/W83/W84 + pcap |
| B-6 | RX 合并公平 | 两口同时灌（> 聚合）；`ΔW79`、`ΔW0` 都前进；W82/W4 可读；干净窗 `ΔW85 == ΔW79+ΔW0`，否则记残差；**W79 口径 = merge 输入 FIFO 接受的好帧，FIFO 满丢帧看 W82** | G2 STRICT 负控；pcap |
| B-7 | 单口 TX_DIS 隔离 | `0x08` bit0=1 ⇒ IP_B 停、IP_A 继续；bit1 反之；恢复 | P1 S-3 已证 bit0；bit1 复跑 |
| B-8 | 收尾 | 回烧 0x2B 或留 0x2C（按用户）；`0x08=0`；carrier=1；对端 ns/neigh 清理 | 身份门复算 |

---

## 6. 待裁与风险

### 6.1 待裁清单（按影响排序）

| # | 事项 | v2 建议/状态 | 影响 |
|---|---|---|---|
| D1 | **IP_B 地址值 / 对端 p0 地址 / netns vs 单 ns** | IP_B=`192.168.100.4`；p0=`192.168.100.101`；**netns + 静态邻居**（H-2） | 决定 P2-3 负对照有没有判别力 |
| D2 | **BID 分配** | 甲 `0x2C`、乙 `0x2D`（**P1 的 0x2C=乙 作废，N-11**） | 读侧/身份门 |
| D3 | **TX 选口方案** | **②**（demux 前移 + 复制 arb） | 改动面/回归面 |
| D4 | **`WIN_POOL` 分池** | **TL 已定：选项 (a)** —— `WIN_Q_MAX` 不传参、复位默认 `0xC000`、零 RTL。**“双口同时数据流”待用户裁**（选项 b = `WIN_Q_MAX=0x6000` + P2-1 判据改写 + `0xC000` 对照臂）；**HLS SYN-ACK `0xC000` 一致性 = P3 前置**；**P2-2 的池归还见证 = N-1 的 fast-path 纯 ACK 双探针** | 两连接 BDP；P2-2 判据 |
| D5 | **`rx_merge2` FIFO 深度** | 256（1.35 帧）+ per-port drop 计数；病态下第 2 帧可能溢出（承认）；**另：`slow_tx_adp` side FIFO = 128（H-3 新增 D 项）** | 板上无谓丢帧量 |
| D6 | **HLS 网表策略** | 单 canonical 输出（重新综合 + 归档旧）；M-2 的“默认构建接受 IP_B”显式登记 | 单口“位级不变”是否可接受 |
| D7 | **per-port MAC** | 单 MAC（直连可接受）；per-port MAC 留后续 | 接交换机/L2 时才需要 |
| D8 | **广播 IPv4 语义** | 映射回 IP0（= 今天行为） | 双口广播 ping/DHCP 只走 ch1 |
| D9 | **`app_ctrl` 事件端口位** | P2 不加，P3 可选 | app 可见性 |
| D10 | **板上错口变异位流（PORT_INV）** | **不做**；用 netns + 静态邻居 + 单元门变异。**触发条件**：若 P2-3 被现场判“无判别力”（p0 什么都看不到），再做 PORT_INV | 省一次 ~47 min 构建 |
| D11 | **方案③（post-arb 源 IP 解析选口）** | 不在第一版；若要“生产者零改动”再裁 | 可能显著缩小改动面 |
| D12 | **观测（H-7 偏离）** | v1 的 3 字 = 最小集，**偏离**用户“开发期全量”裁定。v2 加 **5 字（W83..W87）**；仍非全量：ch0 `stat_flush_done`/`stat_tx_short`、`slow_tx_adp.side_ovf/play_port`、`rx_merge2` 内部仲裁计数、ch0 txcdc 占用峰值、`udp_rx.meta_dst_ip` 未进快照。**显式报用户**；若要全量需追加字并接受时序风险。**【v2.1 N-12】W87[15:0] 只作活动指示，不能当精确帧数。** | 时序风险 vs 可观测性 |
| D13 | **`MAX_TCP_CONN=3` 与 P3 每口 ≥2 条** | P2 每口 1 条（2≤3）；每口 2 条（4>3）需扩 HLS 连接表，P3 前裁 | P3 连接容量 |

### 6.2 最关键的 3 个剩余风险

1. **时序（0x2B 余量 0.75%）**：A-1 的 `cam_rd_dip` 进 `csum_init_val`/头字 mux（加法树级数不变，但 CAM 读扇出 +32 位），加 `f_lip/ctrl_lip` 99 FF + 5 字快照（+480 FF 纸面）+ 第二 `mac_tx_10g`/arb/FIFO + HLS 重综合。0x2B 的全局宿主是既存 `u_tcp_tx/u_fifo_a → u_app/bcnt`（`p9_build_0x2B_20261018/README_FOR_TL.md:63-64`），新逻辑可能换宿主。**不可纸面预测**；一次构建收口 + 预登记 backstop + 定向 STA。**N-6 的组合 `cam_rd_dip` 进默认体 csum init 会在非 OVL 构建增加一个 32 位 mux——G5 两体都要跑，构建轮按体分别看锥。**
2. **A-1 的静默错误**：`tcp_tx_frame` 的源 IP 出现在 **IP 头 / IP 校验和 / TCP 伪头** 三处，覆盖**数据帧、控制帧、重放** × **OVL/默认双体**。任何一处漏改 = 对端静默丢弃/连接异常，**没有握手判据会红**。对策 = G5 逐字节（两体各跑；**含 N-6 的 start_ack 专项臂**）+ G6 全链 pcap 对账 + G7 变异负控 + G8 HLS 源 IP。
3. **HLS 重新综合的全局面 + canonical netlist 的新语义**：`slowstack_prj` 是所有 P7B/K7 构建与门的共同 HLS 输入；重综合后 ① 单口行为必须由 G8 证明等价；② 门的 HLS 与板的 HLS 必须是同一份；③ HLS 在 DP 156.25 MHz 下运行（综合约束 8 ns），新逻辑可能进 DP 关键路径；④ **默认单口构建也接受 IP_B**（M-2）。对策 = 归档旧网表 + HLS 源/网表双哈希 + G8 两二进制 + 构建轮 `u_hls/*` 定向 STA。

### 6.3 其他风险（登记）

- 每口 arb 使“TCP 全局绝对优先”变成“口内优先”；跨口不再互相抢占（设计接受，P3 判据按口写）。
- `rx_merge2` 每帧 1 拍仲裁气泡：大帧 ≈0.5%，最小帧（8 字）≈11% —— 只影响小帧吞吐，登记。
- UDP app 单 peer 表“最后学习者赢”，两口同时活跃会翻转。
- 慢路径源 IP 提取的不变式“HLS TX 不加 VLAN”若被将来打开 ⇒ 静默错口；v2 加 `vlan_seen` 自检（L-10）但仍登记。
- 端口位数组的“同拍同址同源”不变式若将来有人改 CAM 写路径（如加第二条配置源）会破；门断言必须覆盖。
- `0x08` 既是 SCRATCH 又是 TX_DIS 门（既存坑）。
- **B-1/D4 残余**：选项 (a) 下第二条连接零窗是既有 P5d 语义；P2-2 只判身份/顺序数据，不判双口同时吞吐。P3 若要双口同时数据，必须先解 SYN-ACK `0xC000`/配额一致性并重裁 D4。
- **H-7 残余**：5 字不是“开发期全量”；ch0 txcdc 占用峰值 / `slow_tx_adp.side_ovf` 板级不可见（只门内可见）。
- **W86 高半 / W87 的 CDC 口径**：`maccnt_sync` 是 4 相握手事件镜像（不是裸 2FF 多比特同步），采样值误差 ≤1.64 µs + 跨域延迟；不得用于 µs 级判据。**N-4：该模块本身是新增黑盒风险源，构建轮必须查 `IS_BLACKBOX` 与 synth 日志。**
- **N-12 残余**：W87[15:0] 饱和后只表示“≥0xFFFF”；任何把 W87 当精确帧计数的下游判据都必须改。

---

## 7. 未测 / 纸面 / 未判定（不许当已答）

1. **全部 LUT/FF/时序增量 = 纸面**（±30% 包络）；唯一硬锚 = `mac_tx_10g` OOC 上界 `1,602 LUT / 488 FF`。
2. **WNS 预测不可给**：0x2B 的 `+0.048` 是唯一可信输入。
3. **HLS 重新综合的面积/时序 = 未测**。
4. **`rx_merge2` 的板级公平性/丢帧率 = 未测**；FIFO 深度 256 的“1.35 帧”是纸面算术。
5. **对端 netns + 静态邻居配方 = 未跑**；跨口 SYN 负对照的判别力 = 未测（P2-3 的两段判据依赖它）。**N-8 的 `ip netns exec ethtool` 配方 = 未跑。**
6. **G5/G6 新门 = 未跑**；`tcp_tx_frame` 两体的行为覆盖在 G5 跑通前仍是风险。**N-6 的默认体 start_ack 专项臂 = 未跑。**
7. **方案③ = 未设计细节、未评估**；本件只登记。
8. **乙模式（0x2D）= 不在 P2**；镜像目的地在 P3 定。**N-11：P1 的 0x2C=乙 已作废。**
9. **`MAX_TCP_CONN=3` / 共享 `WIN_POOL` 的 BDP 后果 = 纸面**（单连接 RTT ≤39.3 µs；双连接各 24.6 KB ⇒ RTT ≤19.7 µs），实测 `ss -ti` 未取。
10. **`app_ctrl` 事件端口位 / per-port MAC / 交换机场景 = 未实施、未测**。
11. **H-1 的 9 个 TB 里只有一部分在常驻矩阵**；未进矩阵的（`tb_udp_split`/`tb_udp_tx_guard`/`tb_udp_rx`/`tb_udp_echo`）即使改了也不会被矩阵跑 ⇒ “已改”不等于“已覆盖”。
12. **H-3 的 side FIFO 深度/最小帧算术 = 纸面**（60 B 内容 = 8 字；64 帧）；板级未测。
13. **W86/W87 的 16 位饱和语义 = 纸面**；饱和后精确值不可得。
14. **W86 高半 / W87 的跨域事件镜像（`maccnt_sync`）= 纸面**；4 相握手在源事件率 < `clk/8` 时不丢事件，误差 ≤1.64 µs + 跨域延迟，未实测。**N-4：模块导入/黑盒判据未跑。**
15. **H-7 不是“开发期全量”**；未进快照的项见 D12。
16. **“未观测到 ≠ 不存在”**：P1 的 S-4/S-5（LOS/停钟）仍未测（`p9_board_p1_20261018/README_FOR_TL.md` §3-4/5），P2 设计不改变这一点。
17. **【v2.1 N-1】池归还见证 = 纸面判据**：双探针 + pcap fast-path ACK 的流程未在板上跑过；`win==0` 的“未归还”正见证（`tcp_rx.v:364-370` 的 `ackresp`）是源码事实，但**板上是否稳定出现两条 ACK、`ip.id` 滚动是否可辨 = 未测**。若实施轮发现零窗时板侧不发 ACK（例如 tcp_rx 的 `base_ok` 先失败），则本见证降级为“未判定”，不得改写为“已归还”。
18. **【v2.1 N-10】非 DUAL tie-off 的 0 值断言 = 纸面**；`tb_p7b_chain` 未改前，W83..W87 的期望仍按旧几何（0x17C = 未实现）跑。
19. **【v2.1 N-5】读侧 0x2C 阶段 = 未实施**；`apply_readside_bid1c.py` 的 `STAGES` 仍止于 0x2B，`p6e_snap_check.sh`/`p7b_snap.sh` 默认仍 0x2B/83。
20. **【v2.1 N-12】W87[15:0] 饱和时间 ~81.9 ms = 纸面算术**（65535/800k fps）；实际随流量变化。

---

## 8. 变更表（文件级）

| 文件 | 变更 | FINDINGS/N 来源 |
|---|---|---|
| `board/wrapper_p4.v` | 端口位数组（`ifdef DUAL_SFP_A`）；**`IP_A_5`/`IP_B_5` 无条件、`DUAL_SFP_A_DEF` 两分支（N-2）**；`tcp_tx_frame` 新端口/参数；`udp_split`/`udp_tx_cfg` 参数；`slow_tx_adp` 新端口；3 个 `tx_demux2` + 每口 arb/FIFO；ch0 RX FIFO/merge；ch0 TX MAC/FIFO/复位；`p7b_ch0_idle` 声明包 `ifndef`；W83..W87 装配 + **非 DUAL 常量 tie-off（N-10）**；NW 88 / UNIMPL 0x190 / BID 0x2C；DUAL 硬门；`rx_merge2.STRICT=0`；**`.STRICT(1'b0)` 静态断言对象（N-9）** | B-1,H-1..H-8,M-9,M-11,M-12,L-2,L-4,L-12,N-2,N-9,N-10 |
| `rtl/tcp_tx_frame.v` | `cam_rd_dip`/`cam_rd_port`/`o_port`/`PER_CONN_SRC_IP`；6 个用途点 × 2 体；5 个锁存点；`h_lip`；**默认体控制帧 csum init 用组合 `cam_rd_dip`、禁 `lip_r`（N-6）** | A-1 核心、H-1、M-12、L-3、N-6 |
| `rtl/udp_rx.v` | `DUAL_IP`/`IP_B` 参数；`meta_dst_ip` | H-1,M-11 |
| `rtl/udp_split.v` | `DUAL_IP`/`IP_B` 参数 + `meta_dst_ip` 透传 | H-1 |
| `rtl/udp_tx_cfg.v` | `peer_my_ip`/`o_port`/`PER_CONN_SRC_IP`/`IP_B`；`peer_my_ip_r`；`cfg_sync` 后 mux 值 | H-1,M-11,L-4 |
| `rtl/slow_tx_adp.v` | 源 IP 提取（bpos/src_sr/etype）；side FIFO 128；`o_port`/`stat_side_ovf`/`side_level`；VLAN 自检 | H-3,L-10,M-12 |
| `rtl/rx_merge2.v` | 新件（RR/STRICT/帧级互斥/计数） | H-7,M-10,L-12 |
| `rtl/tx_demux2.v` | 新件（帧首锁存/端口稳定/`stat_port_change`） | M-12 |
| **`rtl/maccnt_sync.v`** | **新件（4 相 toggle/ack 事件镜像；W86 高半/W87）——必须导入/解析/清单（N-4）** | **N-4** |
| `hls/src/eth_types.h` | `BOARD_IP_DUAL`/IP1/`board_ip0_u32`/`board_ip1_u32`/`board_ip_match`/`board_src_ip` | M-2,L-11 |
| `hls/src/layer_ip.cpp` | `board_ip_match` | M-2 |
| `hls/src/layer_arp.cpp` | reply 匹配/SPA；request SPA=IP0 | M-1,L-9 |
| `hls/src/layer_tcp.cpp` | `tcp_conn_t.local_ip`；`tcp_find`；`cfg_write` 签名/6 调用点；`tcp_send` sip/IP 头；RST local_ip；T_LISTEN/T_SYN_SENT local_ip | M-1 |
| `hls/src/layer_udp.cpp` | `udp_tx_process(rx_dst_ip)` | M-2 |
| `hls/src/layer_icmp.cpp` | `board_src_ip` | M-2 |
| `hls/src/layer_igmp.cpp` | `board_src_ip` + 措辞订正 | L-11 |
| `hls/src/udp_echo.cpp` | 传 `rx_dst_ip` | M-2 |
| `hls/tb/udp_echo_tb.cpp` | 新 TEST（IP_B/双 IP/tcp_find/RST/broadcast/legacy） | M-1,M-2 |
| `hls/run_hls.tcl` | `-cflags "-DBOARD_IP_DUAL=1"`；归档 | M-2,M-3 |
| `board/build_p7b_ku5p.tcl` | 导入 `rx_merge2.v`/`tx_demux2.v`/**`maccnt_sync.v`**；模块解析断言（**`IS_BLACKBOX` 硬门，N-3**）；`DUAL_SFP_A=1`；BID 0x2C；HLS 哈希 | H-4,M-3,N-3,N-4 |
| `sim/p4gates/run_matrix_p4dfix.bat` | 21→24 门（G2/G5/G6） | M-5 |
| `sim/p4gates/paths.txt` | `FINGERPRINT_GLOBS` 加 p11_dual/HLS 源 | M-3,M-5 |
| `sim/p4gates/*_src.f` | 新增 p11dual/p11merge/p11srcip manifest；**`p11dual_src.f` 含 `maccnt_sync.v`（N-4）** | H-4,M-5,N-4 |
| `_proj_10g/p7b_chain/sim/run_elab_4combo.bat` | 7→12 组合 + 6 签名 + DUAL 正控 + **`.STRICT` 静态断言（N-9）** | M-4,N-9 |
| `_proj_10g/p7b_chain/sim/run_tb_p7b_chain.bat` / `sim/p4gates/p7bchain_src.f` | 若 G6 复用此清单，加三新件（含 `maccnt_sync.v`）；几何断言改 0x2C；**非 DUAL W83..W87=0（N-10）** | H-4,H-5,N-4,N-10 |
| `sim/p6e_pcie/tb_p6e_pcie_wrapper.v` / `_counters.v` | NW 88 / UNIMPL 0x190 / MIR 0x180 / W83..W87 | H-5,H-7 |
| `_proj_10g/notes/p7b_biz_win/{check_window.py,tb_biz_win.v}` | 同上 + WLABEL（**W79 语义同步，N-14**；`nnew_top` 17→22） | H-5,H-7,N-14 |
| **`_proj_pcie/p6e_snap_check.sh`** | **默认 `EXPECT_BID=0x2C` / `SNAP_WORDS=88` / UNIMPL 0x190（N-5）** | **N-5** |
| **`_proj_pcie/p7b_biz/p7b_snap.sh`** | **默认 `NW=88` / `EXPECT_BID=0x2C` / UNIMPL 0x190（N-5）** | **N-5** |
| **`_proj_pcie/p7b_gate4_negctrl.sh`** | **`awk -v NW=88`（N-5）** | **N-5** |
| **`_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py`** | **追加 `STAGES` 阶段 `0x0000002C`（88 / 0x190）+ `EDITS_2C` + `DEFAULT_SPECS`（N-5）** | **N-5** |
| **`_proj_10g/notes/p7b_affinity/j6_r6fix.sh` / `_proj_10g/notes/p7b_biz_tcpreg/tcpreg_j6.sh`** | **`NW=88` / `EXPECT_BID=0x2C` / 几何表（N-5；这两个是 `apply_readside` 的 SENTINEL 链）** | **N-5** |
| `tb/tb_app_udp.v` / `tb_udprx_chain.v` / `tb_udprx_rate.v` / `tb_app_udp_rate.v` / `tb_udp_split.v` / `tb_udp_tx_guard.v` / `tb_udp_rx.v` / `tb_udp_echo.v` | 新输入 `peer_my_ip` 接常量/参数；`tcp_tx_frame` 新输入接常量 | H-1 |
| `_proj_10g/p11_dual/sim/*` | 新门 G2/G3/G4/G5/G6/G8b | 全 |
| `p9_dual_sfp_plan_20261017/DESIGN.md` §0.5 | 追加一行（A-1 改裁注） | 事实核/plan |
| **`_proj_10g/notes/p9_dual_sfp_p1_impl_20261018/DESIGN_v5.md`** | **不改原文；仅在 §0.2-7/§0.3 #10 登记“乙=0x2C 作废、甲=0x2C、乙=0x2D”（N-11）** | **N-11** |

---

## 附录 A —— 现读锚点速查（2026-10-18，0x2B 树）

**wrapper（`board/wrapper_p4.v`）**
`:294` `WIN_CAP_5` · `:346-353` FE 域别名 · `:639-646` ch0 常量 IDLE · `:683-688` ch1 TX 复位 · `:692-699` ch0 RX 复位 · `:911` `u_mac_rx`（ch1） · `:949-1012` ch0 tap/sink/`u_mac_rx_ch0` · `:1054` `u_rxcdc(76)` · `:1097` `vlan_strip` · `:1120` `rx_classify` · `:1295-1297` app_reg 线 · `:1461-1469` `app_ctrl` 参数 · `:1547-1549` app_reg 钉死 · `:2026` `cam_rd_dip` 声明 · `:2183-2189` CAM 写 mux · `:2191-2213` `tcp_cam` · `:2215` `tcb` · `:2290` `slow_cfg_adp` · `:2398` `tcp_tx_frame` · `:2452-2453` `cfg_src_mac/ip` 常量 · `:2558` `udp_split`（`:2592` `cfg_dst_ip`） · `:2710` `udp_echo` · `:2732` `slow_tx_adp` · `:2818` `app_udp_pattern` · `:2865` `udp_tx_cfg`（`:2884` `cfg_my_ip`） · `:2910` `udp_tx_frame` · `:2936` `u_tx_udp_arb` · `:2987` `u_tx_arb` · `:3013` `u_txcdc` · `:3039` `u_mac_tx` · `:3522` `SNAP_NW_P6E=83` · `:3543` `SNAP_P7BDP_NW=39` · `:3554` `SNAP_CH0_NW=4` · `:3555` `SNAP_TX_NW=5` · `:4406-4455` p7bdp 槽 assign（末条 `:4455`） · `:4483-4495` ch0 束 · `:4601-4649` `snap_dout_all` · `:4814-4818` SFP TX_DIS · `:4824` `BUILD_ID_V=0x2B` · `:5305` `.SNAP_NW`

**RTL**
`rtl/tcp_cam.v:26-27`（**rd_sip = 对端 IP / rd_dip = 本地 IP**）· `:36-40,71-75` · `rtl/tcb.v:94-105`（`3'd7` 保留） · `rtl/slow_cfg_adp.v:137-163`（`:148` w2） · `rtl/tx_arb.v:9-25`（73 位固定） · `rtl/tcp_tx_frame.v:122-129,392-405,817-820,874-876,900-901,1164-1166,1198-1210,1313-1345,1324,1327,1345-1362,1396-1397,1440,2000-2013,2022-2025,2272-2288,2392-2415,2411,2463,2481` · `rtl/udp_tx_cfg.v:66-77,104-107,124-127,142-180` · `rtl/udp_rx.v:180-181,202-213` · `rtl/udp_split.v:209-213,215,443-447,745-749` · `rtl/slow_tx_adp.v:17-25,40-44,80-88,136-197,199-224` · `rtl/rx_classify.v:26-66,70,76-94,188-191` · `rtl/app_ctrl.v:57,59,75,121-125,276-296,281-283,462,468-469,530-533,843,866,1020` · `rtl/tcp_rx.v:364-370`（**`ackresp`：`seq_eq && !win_ok` 回纯 ACK**） · `_proj_10g/p7b_mac/rtl/mac_tx_10g.v:317-330` · `_proj_10g/p7b_mac/rtl/mac_rx_10g.v:326-327,405-414`

**HLS**
`eth_types.h:111-123,211-217` · `layer_ip.cpp:76-81` · `layer_arp.cpp:149,194-195,201` · `layer_tcp.cpp:10-12,142-149,165-181,177,267-292,281,290,314,581,609,631-645,637,663,665,677,699,721` · `layer_udp.cpp:82-88,140,168-171` · `layer_icmp.cpp:141-143` · `layer_igmp.cpp:121-122` · `udp_echo.cpp:172-173,184-205,227-229` · `layer_mac.cpp:218,282-287` · `run_hls.tcl`（add_files/cflags）

**构建/门/读侧**
`build_p7b_ku5p.tcl:27`（`hls_dir`）、`:84-116`（import）、`:286`（verilog_define） · `board/p7b_pcs_stub.v:172-217`（双通道注入/捕获） · `sim/p4gates/run_matrix_p4dfix.bat:184-261`（21 条 `call :gate`） · `sim/p4gates/paths.txt`（`FINGERPRINT_GLOBS`） · `sim/p4gates/p4gate.py:498-535`（HLS 指纹） · `_proj_10g/p7b_chain/sim/run_elab_4combo.bat`（7 组合，`:44-50`） · `_proj_10g/p7b_chain/sim/run_tb_p7b_chain.bat:51-72`（字面清单） · `_proj_10g/p7b_chain/sim/tb_p7b_chain.v:1353-1354`（`txsrc_*` force）、`:1641-1649`（几何） · `_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py:689-704`（`STAGES` 到 0x2B） · `_proj_pcie/p6e_snap_check.sh:60,72-73` · `_proj_pcie/p7b_biz/p7b_snap.sh:85-87` · `_proj_pcie/p7b_gate4_negctrl.sh:156` · `_proj_10g/notes/p7b_biz_win/check_window.py`（`nnew_top`） · `_proj_10g/notes/P7B_BIZ_WINDOW.md:77`（W79 标签）

**基线读数**
`_proj_10g/notes/p9_build_0x2B_20261018/README_FOR_TL.md:39-55,63-92,98-106,159-170` · `_proj_10g/notes/p9_board_p1_20261018/README_FOR_TL.md:20-29,82-181` · `_proj_10g/notes/p9_dual_sfp_p1_impl_20261018/DESIGN_v5.md:22,245,287-300`

---

*本件 = P2-甲 实施级设计 v2.1（基于 DESIGN_v2.md 的最小增量修订；N-1..N-14 已逐条落点）。不含 PASS/FAIL 裁定；所有“达标/不达标”留待用户与后续实测。纸面数字已逐条标注；「未观测到」≠「不存在」。*

---

## 附录 E —— 实施红队回灌（2026-10-18 v2.1-errata）

**来源**：`_proj_10g/notes/p11_review_p2a_impl_20261018/FINDINGS.md`（F-1..F-20 + D-1..D-13）。**本附录 = 逐条的现行处置**；正文按 v2.1 原文读，凡与本附录冲突处**以本附录为准**（正文已在关键处加【v2.1-errata】指针，导航表见 §N.1）。状态词沿用本件约定；**本附录不下 PASS/FAIL 裁定**，也不声称时序/资源/板级已达标。

### E-1 设计不符项 D-1..D-13 的处置

| # | 处置 | 现行口径 / 实施位置 |
|---|---|---|
| **D-1** | **设计件错，已订正**（正文 §3.4 已加指针） | W86 高/低半 = **AXIS 反压拍数**（`fifo_async.ovf_pulse = wr_en && full`，生产者在 full 时保持 tvalid ⇒ 字不丢、下拍重试）。⚠️ **RTL 计数器名未改**（`*_ovf` 字面仍在），读法按本条目；正常反压即增长 ⇒ **不是**“应恒 0”，也**不携带丢字信息**。 |
| **D-2** | **判据改写（已落正文 §5.1 P2-2）** | 对账式 **删掉 `sat16(ch0_txcdc_ovf)` 字级修正项**；ch0 丢帧只认 **MAC `stat_drop`（W82）**。替代的两条硬约束：① **取窗前静默**（连续两次快照间隔 ≥1 ms 且 `ΔW83=ΔW84=0`）；② 做不到静默时登记 **`INFLIGHT_MAX_FRAMES = 33`**（纸面，保守）。W86 只作健康指示。 |
| **D-3** | **已实施** | G6 臂 C 改**斜坡追踪**：`dst_val` 必须在 ≤32 个目的域拍内追到精确中间值 (1..4)；`src_val` 冻结 ≥120 拍时 `dst_val` **逐拍不变**；另加 **`dst_val` 强制常 0 的变异臂**（同一活性判据必红）。裸 2FF 负控保留。 |
| **D-4** | **已实施（清单补全）** | N-5 读侧清单从 4 文件补到 **20 文件**：j6/tcpreg 的 **GEOM_TIERS 顶端 88 档** + 6 个 gate4/夹具（accept/selftest/livefake/negctrl/final_state/gen_inputs）+ 3 个 TB（`tb_p7b_chain`/`tb_p6e_pcie_{counters,wrapper}`）+ `p6e_snap_selftest_fix2.sh` + 两个 biz_win 脚本。0x2C 阶段 = **显式增量 43 处**（F-5）。 |
| **D-5** | **已实施** | G5 与 G6 bat 各加 `findstr "peer_my_ip" \| findstr "VRFC 10-3645"` 为空的定向断言；`tb/tb_app_udp.v` 加运行期 `$isunknown(u_cfg.o_port)` / `$isunknown(u_cfg.cfg_sync)`（首次命中即 `[FAIL]` 并计入 errs）。 |
| **D-6** | **已实施** | `rtl/slow_tx_adp.v`：提取寄存器（`bpos/src_sr/etype_r/src_ip_lat/ip_seen/vlan_seen`）与更新块整体进 `generate if (PER_PORT)`；`PER_PORT=0` 支 `ext_side_push=1'b0`，**零寄存器/零锥**。G4 重跑验证行为不变。 |
| **D-7** | **已实施（部分口径）** | TCP/慢路径每帧源 IP 一致性 = G5/G4 单元级；**UDP 侧** = G6 新臂 D（真 wrapper 的 `u_udp_tx_cfg`：学习帧 `peer_my_ip=IP_B` ⇒ `o_src_ip=IP_B`/`o_port=1`；改 IP_A ⇒ 反向）。⚠️ 臂 D 用**force 学习口**而不是“真 IPv4/UDP 帧走 `udp_tx_frame`”（后者要 HLS/慢路径参与，成本高且本缺陷形态是 mux 取值，force 足以判别）；该选择登记为实施级偏离。 |
| **D-8** | **已实施** | `board/build_p7b_ku5p.tcl`：`HLS_SRC_HASH`（`hls/src/*.cpp\|*.h` + `run_hls.tcl`）与 `HLS_NET_HASH`（`verilog/*.v` + `*.dat`）逐文件 sha256 + 合并 sha256，全部打印归档（PowerShell Get-FileHash；拿不到 = `P7B_VERDICT=HLS_HASH_FAIL` 硬失败）；synth 后 `synth_1/runme.log` 的 `black box\|8-3491` 必须 **0 命中**（`P7B_BLACKBOX_LOG_HITS=0`），否则 exit 1。`IS_BLACKBOX` 保留为辅助。 |
| **D-9** | **已实施（真变异）** | G3 臂 D = **第二份 `tx_demux2`** 把 `d0/d1` 输出交叉接到检查器：同一激励下正常件 `n0==4 && n1==0`，交叉件 `n1i==4 && n0i==0` ⇒ “端口反接”判据必红（不再是重复正例）。 |
| **D-10** | **已实施** | `_proj_10g/notes/P7B_BIZ_WINDOW.md:77` 的 W79 标签同步为“**merge 输入 FIFO 接受的好帧数**（`tready=~ch0_fifo_full`）；FIFO 满丢帧由 W82 计”。 |
| **D-11** | **已实施（消歧义）** | G7 的 c8 = **真构建 9 宏组合**（`APP_MODE DEV_USP PCIE_OBS DP_156MHZ P7B_10G UDP_TX_OVL TCP_TX_OVL SFP2_MODE_A DUAL_SFP_A`）；另加 **c13 = DUAL 无 `SFP2_MODE_A`** 正控；`run_tb_p11_dual.bat` 的 DEFS 同加 `-d SFP2_MODE_A` 并重跑 G6。 |
| **D-12** | **已实施** | `maccnt_sync` 两实例的 `src_tick` 改为源域 **8 位自由计数 rollover**（每 256 源拍一个单拍脉冲；rx 用 `gmii_clk_0`、tx 用 `tx_fe_clk_0`，各自同源复位）——设计 §3.4 “每 256 拍一次”落地。 |
| **D-13** | **已处理（归档洁净）** | 旧全红件改名 `gates/g5_run.SUPERSEDED_fail_0814.log`；G5 门改写为**四臂**（OVL / 默认体 / 全量 6 处变异 / **N-6 精确变异 `csum_sip=lip_r`**），本轮重跑取新的最终件。08:14 全红的原因（旧 bat 把变异件喂给了全部三臂 + 判决解析放行）写进 `p11_p2a_fix_20261018/FIX_REPORT.md` §F-10；⚠️ 旧 bat 未入库、无法逐字复原 ⇒ 原因为**按错误签名反推**，不是逐字证据。 |

### E-2 F-2 半帧看门狗（设计修订项；**需用户追认**）

- **实现**：`rtl/rx_merge2.v` 加 `parameter TO_CYCLES = 0`（0 = 关）。语义 = `busy && !sel_tvalid` 连续 ≥`TO_CYCLES` 拍 ⇒ 释放 `busy`、`stat_abort+1`、**不产生帧计数**。wrapper 实例传 **4096**（≈26 µs @156.25 MHz；> 一个最大帧 190 字 + 余量）。
- **为什么需要**：上游 `mac_rx_10g` 只在“新 `/S/` 碎片”或“FIFO 满”时产生 `TERM`；链路断开/停钟/PCS 中途复位时，已推入输入 FIFO 的半帧没有后续字、也没有 `TERM` ⇒ `busy` 永久为 1 ⇒ **另一口 RX 被连坐锁死**（只能复位恢复）。P2 相对 P1 的**新跨口耦合**。
- **复位域（F-19）**：`u_rx_merge` 的 `rst_n` 由 `dp_rst_n` 改为板级 **`reset_n`** —— 与两路输入 FIFO 的 `rd_rst_n` 同源。理由：MMCM 失锁重锁（F-3）时 merge 会清而 FIFO 指针不清 ⇒ 从半帧开始；改同源后二者同代复位。成本 = 0（纯连线改动），风险 = 无（merge 无 MMCM 依赖）。
- **残余（必须如实登记）**：超时释放后，该半帧已消费的拍不会再回卷；输入 FIFO 里剩余的字会在下一轮仲裁里被当作“无 tlast 的流”排出（不构成帧、不计帧）。下游 `vlan_strip` 在 DP 构建 `RESYNC_EN=1` 会等到下一个 SOP 才放行 ⇒ 另一口的首帧不受污染（**该论证依赖 `RESYNC_EN=1`**；单域/非 DP 构建不例化 merge，不适用）。
- **门**：G2 新臂 G —— p1 注入 4 拍**不发 tlast**、静默 ≥16 拍（门内用 `TO_CYCLES=16` 的第三实例）⇒ 断言 `stat_abort>0`、`stat_frames1==0`、**p0 的两帧仍出来**（`tl_w==2`）、`stat_frames0==2`。
- **⚠️ 需用户追认**：这是设计件 §3.2/§6.3 之外**新增的 RTL 行为**（虽默认关、常量折叠零代价），且 `stat_abort` 未进快照（板级不可见）⇒ 由用户裁定是否接受该修订；不追认时的回退 = `.TO_CYCLES(0)`（一行）+ 设计件登记“停钟楔死只能复位”。

### E-3 F-4 板级 B-6 负对照建议（W86 语义）

1. **W86 是拍数不是丢字**：ch0 单独灌流（正常反压）时，`ΔW86[15:0]` 应与该口的**反压拍数**同量级、随流量增长并**饱和到 0xFFFF**；它**不**应等于任何“丢字节数”。若板上把它当“必须为 0”的健康判据 ⇒ **假红**。
2. **丢帧走 W82**：构造一个“故意让 MAC 丢帧”的负对照（例如把 ch0 输入 FIFO 深度/消费暂停），断言 **`ΔW82 > 0`** 而 `ΔW79 = 0`（W79 只数被接受的好帧）。
3. **P2-2 对账**按 E-1/D-2 的改写执行：先静默（两次快照 `ΔW83=ΔW84=0`），否则带 `INFLIGHT_MAX_FRAMES=33`；**不得**再把 W86 加进上界。

### E-4 实施级偏离与未测（与本附录同批登记）

1. **UDP 一致性臂 D 用 force 学习口**（D-7）—— 不是真 IPv4/UDP 帧；判别对象是 `peer_my_ip → o_src_ip/o_port` 的 mux。
2. **W86/W87 的 16 位饱和/命名**未改（D-1）；读数口径按 E-1。
3. **HLS csynth / 双 IP 网表、Vivado 构建/综合/实现、板级 W83..W87**：**本轮仍未跑**（纪律禁止构建/上板）；所有时序/资源/板级结论仍为未测。
4. **`tb_p11_dual` 臂 A 仍只用 IP_A**（现役 HLS 网表是单 IP）⇒ IP_B 的 HLS 握手留构建轮（重综合后）。
5. **`INFLIGHT_MAX_FRAMES = 33` 是纸面保守值**（txcdc 256 字 / 最小帧 8 字 + 1 帧在 MAC/线上），未实测。

### E-5 F-21（W83..W87 绕过 `snap_cdc`）—— 修复实施登记（2026-10-18）

> ⚠️ **编号说明**：派单写作「附录 E 加 E-4 F-21」，但本文件 **E-4 已被「实施级偏离与未测」占用** ⇒
> 本条编号 **E-5**（核到不符如实登记，不覆盖既有编号）。本节 = **实施记录**，不是 PASS/FAIL 裁定。

**现象（0x2C 构建布后实测，非推断）**：`_proj_10g/notes/p11_build_0x2C_20261018/README_FOR_TL.md` §5 +
`gates/{SNAP_PROBE,FANOUT_PROBE}_0x2C.txt`：
- `u_snap_p7bdp/hold_b_reg` 布后 982 个寄存器、最大位号 1239 ⇒ **槽 39..43（W83..W87）各 0 个**；
- `tx_p0_frames_r_reg[0]/Q` 的全部负载 = 自身反馈 + `u_pcie_regs/snap_din[2422]` ⇒ **裸多比特 CDC**
  （多比特计数器两位可能在不同拍到达 ⇒ 读出"从未存在过的中间值"）；
- 源码定位：`board/wrapper_p4.v` 顶层 `w8x_snap = w8x_dp` 直驱 `snap_dout_all`，而 `p7bdp_din[39..43]` 是死逻辑。

**修法（已实施，未构建）**：
1. `board/wrapper_p4.v`：`snap_dout_all` 顶部 5 项改为 `p7bdp_dout[43*32 +: 32] … [39*32 +: 32]`；
   删除 `ifdef DUAL_SFP_A` / `else` 两支的 `w8x_snap` 直连块。
2. **N-10 语义不变**：非 DUAL 构建的 `w83_dp/w84_dp/w86_dp/w87_dp = 32'd0`、`w85_dp` 仍真
   ⇒ 仍经 `p7bdp_din[39..43] → u_snap_p7bdp → p7bdp_dout[43..39]` 进快照（只是多走一次 CDC）。
3. **两层结构门**：
   - 静态（源码面，已挂进 `run_tb_p7b_chain.bat`，24 门矩阵内）：
     `_proj_10g/p7b_chain/sim/check_snap_top5_wired.py` —— 断言顶部 5 项 = `p7bdp_dout[43..39]`、
     无 `w8x_snap` / 无 `assign w8x_snap = w8x_dp`、`p7bdp_din[39..43]` 五条线在位、N-10 tie-off 仍在。
   - 布后（构建轮执行）：`board/build_p7b_ku5p.tcl` 的 `P7B_SNAP_TOP5_CDC` 段 ——
     `u_snap_p7bdp/hold_b_reg[1248..1407]` 每槽至少 1 个寄存器；`tx_p0_frames_r_reg[0]/Q` 扇出含
     `u_snap_p7bdp/hold_b_reg`、不含 `u_pcie_regs/snap_din`；失败 = `P7B_SNAP_TOP5_CDC_MISSING` /
     `P7B_SNAP_TOP5_FANOUT_BAD` + exit 1。
4. **BID**：`BUILD_ID_V = 32'h0000002D`（甲重建；**0x2C 位流从未烧板**）；**乙顺延 0x2E**（本文件与
   `P7B_OPEN_ITEMS.md` §0-72 同步登记）。
5. **F-2 `TO_CYCLES`**：用户 2026-10-18 已批「下一构建用 `16'hFFFF`」⇒ wrapper 实例
   `.TO_CYCLES(16'hFFFF)`（65535 拍 ≈ 419 µs @156.25 MHz）；`rtl/rx_merge2.v` **模块默认仍 0**（关），
   其它例化/默认构建零行为变化；回退 = 改回 `.TO_CYCLES(4096)` 或 `.TO_CYCLES(0)`（一行）。
6. **读侧**：BID 0x2C → 0x2D 的**显式增量**（26 处 / 15 文件；几何不变 88 字 / `0x190`）；
   `apply_readside_bid1c.py --assert --bid 0x2D` = 0 fail；从 0x2C 树重放 = **20/20 逐字节相同**。

**未测（不许当已答）**：重建 0x2D 的综合/实现/时序、布后门的两条实际读数、板级 W83..W87 相干性；
以及"裸 CDC 是否真的读出过位混" —— **未观测到 ≠ 不存在**（0x2C 从未上板）。
