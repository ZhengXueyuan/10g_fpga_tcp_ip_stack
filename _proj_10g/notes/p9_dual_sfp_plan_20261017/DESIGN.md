# p9_dual_sfp_plan_20261017 / DESIGN.md —— 「两个 SFP+ 模块全部接入」接入计划研究件

- 日期：2026-10-17 · 基线代 = `0x28`（`_proj_10g/notes/p9_build_0x28/`，板侧身份 = BID `0x28` / 快照 75 字 / 未实现地址 `0x15C`）
- 本件 = **纯研究/设计件**：未改 RTL、未构建、未 xsim、未烧板、未写 QSPI、未碰 git、**对端只做只读探查**
- 判据层口径：**本件不下 PASS/FAIL 裁定**（裁定权在用户/判据所有者）。「未观测到」≠「不存在」。
- 证据标记（与 `P7B_SPEC.md` §13 同义，全文使用，**严禁把任一条写成比它本身更高的等级**）：

| 标记 | 含义 |
|---|---|
| 【已证·板级】 | 有板级读数的原文（带文件/行号） |
| 【已证·构建】 | 有构建/综合/实现产物的原文（日志/报告/.xci 回读） |
| 【已证·源码】 | 仓库内可逐行核对的源码（本件全部行号 = 2026-10-17 现读） |
| 【推断】 | 逻辑推理，无直接证据 |
| 【未证】 | 不知道 / 没做。**不得当判据用** |

---

## 0. 一页结论（先读这个）

| # | 结论 | 等级 |
|---|---|---|
| 1 | ⭐ **"两个口"在 PCS/GT 层已经全在**：现役构建的官方核就是 **2 通道核**（`NUM_OF_CORES=2` / `LANE1=X0Y4` / `LANE2=X0Y5`），生成产物 `ip_0`/`ip_1` 逐核回读 = `X0Y4`/`X0Y5`，两通道各 10.3125 Gbps、QT/QPLL0。⇒ 本次「接入第二个 SFP+」的工作量 **100% 在数据面与观测面，PCS/GT 侧零改动** | 【已证·构建】`build_p7b_ku5p.tcl:45-59`；`vivado_prj/p7b_ku5p_prj.gen/sources_1/ip/pcs64/{ip_0/pcs64_gt.xci:16,ip_1/pcs64_gt_1.xci:16}` |
| 2 | ⭐ **双通道"同时工作"已被板级证明过**（闸 1）：2 通道官方 PCS + 板内光路 J7↔J8，判定方向 30,056,095 帧零错 / 9,999.94 Mbps，反向纯 IDLE 也 `block_lock=1` | 【已证·板级】`P7B_GATE1.md:27,563,592` |
| 3 | 现役设计里 **ch0（J7）只剩两只"死"端口**：TX = 常量 IDLE 寄存器（`dont_touch`），RX 输出**悬空**（其状态只折叠成快照 W39[30] 的**1 个签名位**）。⇒ 第二个口的"接入"= 给 ch0 配 MAC + 开观测面 | 【已证·源码】`wrapper_p4.v:566-573`（TX idle）、`:3555-3570`（ch0 签名）、`:3655-3656`（W39 位域） |
| 4 | ⛔ **最大结构性成本不是 LUT/FF/时序，而是 BRAM**：TCP 重传环 `retx_ram` **独占 256 / 348 tile**（16 连接 × 64 KB），全器件余量只有 **132 tile** ⇒ **"第二套完整 TCP 栈"（S1-full）在 BRAM 上不可能**（+256 > 132）。除非先做 URAM 迁移（29–32 URAM/套，两套 58–64/64 = 贴满） | 【已证·源码/构建】`rtl/retx_ram.v:123-124`（`reg [63:0] mem_e/mem_o [0:65535]`）；`P7B_BRAM_REPORT.md:22-24,119-124`；`p9_build_0x28/REPORT.md:100` |
| 5 | 推荐主路线 = **S2（单栈双口：端口进连接身份）**，分 **P1（ch0 单口 bring-up + 观测，低风险）→ P2（ch0 数据面接入）→ P3（双口业务共存）** 三段；每段一次构建收口 | 【推断】（本件的设计建议，非既成事实） |
| 6 | ⭐ **零构建先导步存在**：只插第二只光模块 + 第二根 AOC（J7 ↔ 对端 `enp1s0f0np0`），用**现役 `0x28` 位流**即可看对端 `p0 carrier` 起立（ch0 TX 恒发 /I/ ⇒ 对端 PCS 块锁）。负对照 = 写 `pcie_scratch[0]` 拉高 `sfp1_tx_dis` ⇒ carrier 必掉 | 【推断】（机理有闸 1/闸 2 同款先例，本条组合未跑） |
| 7 | ⛔ **物理件状态未核**：第二只光模块与第二根 AOC 是否在位/在手 —— 闸 2 实测"全系统只有一根 AOC"且 J7 `los=1` 恒亮，**"没插线还是没插模块"当时未区分（U7）**。本轮禁写对端 ⇒ 未再核。**这是本计划的第一号待裁定项** | 【已证·板级（历史）】`P7B_GATE2.md:28-29,94-97,396` |
| 8 | 对端**双口可用**（2026-10-17 只读实测）：SFC9120 双口 → `enp1s0f0np0` / `enp1s0f1np1`，两口当前 `DOWN / NO-CARRIER`、无 IP、无占用 ⇒ "双口对双口"实验**在硬件上可做**（缺的只是模块与线） | 【已证·只读实测】见 §1.3 |

---

## 1. 现状与接入目标（一页）

### 1.1 物理现状【已证·板级/图纸】

| 项 | 事实 | 出处（现读） |
|---|---|---|
| 两路 SFP | **2 路 SFP28 全在底板**；**都在 GTY quad 225** | 仓根 `CLAUDE.md`「本板实测修正 §1」 |
| SFP A = J7 | GTY **X0Y4** = ch0；TX `AA5/AA4`、RX `Y2/Y1` | 同上；`wrapper_p4.v:173-176` 端口注释 |
| SFP B = J8 | GTY **X0Y5** = ch1；TX `W5/W4`、RX `V2/V1` | 同上；`wrapper_p4.v:177-180` |
| 参考钟 | 核心板 **Y2 = 156.25 MHz** → `MGTREFCLK0_225` = ball `V7/V6`（**两通道共用**；156.25×66 = 10.3125 GHz） | `ku5p_p7b_gt.xdc:27-32`；`P7B_XXV_OFFICIAL.md:295-296` |
| SFP 控制脚（**实测映射，厂商两份 XDC 都错**） | `SFP1_TX_DIS=C11` · `SFP1_RX_LOS=B11` · `SFP2_TX_DIS=D9` · `SFP2_RX_LOS=C9`（TX_DIS 高有效 + 板上 10k 上拉 ⇒ **悬空 = 发射关闭 = 全黑**） | `ku5p_p7b_gt.xdc:34-38`；`P7B_GATE1.md:86-91` |
| **当前接线（唯一）** | **全系统只有一根 AOC：`J8` ↔ 网卡 `enp1s0f1np1`**；`J7` 全黑（`los=1`、`block_lock=0`、`rx_local_fault=1`、`rx0_free=0`） | `P7B_GATE2.md:28-29,94-97` |
| J7 的"黑"是什么 | **U7：没插线 vs 没插模块，两者都表现为 `los=1` 恒亮 ⇒ 当时未区分**（登记为"现场看"） | `P7B_GATE2.md:396` |
| 闸 1 先例（**两个口同时跑过**） | 2 通道官方 PCS + 官方 example 图案发生器/监视器（**未改一行**），板内光路 `J7↔J8`：判定方向 **6.6 s / 30,056,095 帧零错 / 9,999.94 Mbps**；**反向 = ch1 发常数 IDLE、ch0 收，`block_lock=1`、`/E/`=0**；两通道健康期 `block_lock` 均 1；`TX_DIS` 负对照两边都对 | `P7B_GATE1.md:25-31,350,563,592`；施工目录 `_proj_10g/xxv_loop/` |
| 结论 | **"两个模块 + 一根 AOC J7↔J8"这套物理构型历史确实存在过**（闸 1 就是靠它跑的）⇒ 两个光模块至少当时都在位；**闸 1 之后 AOC 被改接到 J8↔网卡** ⇒ 若要恢复双口，至少需要**第二根** AOC（或把现有 AOC 改成 J7↔对端 p0 而放弃 J8？——那等于放弃现役口，见 §7-1） | 【推断】（由闸 1/闸 2 两段事实合成） |

### 1.2 设计现状（前端 / 数据面 / 观测）

**(a) 前端（PCS/GT）—— 两通道硬件全在，ch0 数据未接**

- `pcs64 u_pcs` 一个实例，两通道成对端口：`_0` = ch0（`wrapper_p4.v:401-446`）、`_1` = ch1（`:447-492`）。
- ch0 **TX** = `(* dont_touch *) reg` 常量流 `64'h0707070707070707` / `c=8'hFF`（全 lane `/I/`），在 `tx_mii_clk_0` 域【已证·源码 `:566-573`】。⚠️ 这三行曾被误删过一次，删掉的后果是 `opt_design` 硬失败（Driverless net / Opt 31-67）—— **ch0 的端口"必须有真实负载"是本工程踩过的坑**（`:556-565` 注释）。
- ch0 **RX** = `rx_mii_d_0/rx_mii_c_0` **无消费者**（悬空；Vivado 可安全修剪 RX 数据通路）；ch0 的全部**状态/控制输出** XOR 折叠成 **1 位签名** `pcs_ch0_sig` 进 W39[30]（`:3555-3570`）。
- ch0 的时钟**已在跑**：`rx_clk_out_0`（BUFG_GT，1428 负载）与 `tx_mii_clk_0`（577 负载）在时钟报告里都在，且 `rx_core_clk_0 = rx_clk_out_0` 已自环（`wrapper_p4.v:598`）。
- **两通道共用 QPLL0**（quad 225 的 common；`qpllreset_in_0` 是 common 级输入，恒 0）—— 两侧子核 `.xci` 回读 `TX_PLL_TYPE = RX_PLL_TYPE = QPLL0`。【已证·构建】

**(b) 数据面 —— 全链单实例、单口假设**

RX：`mac_rx_10g u_mac_rx`（`_proj_10g/p7b_mac/rtl/mac_rx_10g.v`）→ `fifo_async(76×256) u_rxcdc` → `vlan_strip` → `rx_classify`（fast=TCP / slow=其余）→ `tcp_rx` →（`tcp_echo`/app）· `slow` → `udp_split` / `slow_rx_adp`（HLS）。
TX：`tcp_tx_frame` / `udp_tx_frame` / `slow_tx_adp` → `tx_arb`（UDP 压 HLS）→ `tx_arb`（TCP 严格优先）→ `fifo_async(73×256) u_txcdc` → `mac_tx_10g u_mac_tx` → `tx_mii_d_1`。

单口假设的**逐点清单**（现读抽查，§2 各选项按此出改点）：

| # | 位置（现读行号） | 单口假设 | 双口的后果 |
|---|---|---|---|
| 1 | `board/wrapper_p4.v:819` `mac_rx_10g u_mac_rx`（RX 只挂 `rx_mii_*_1`） | 一个 RX 入口 | ch0 的帧无处可去 |
| 2 | `wrapper_p4.v:897` `fifo_async(76)` `u_rxcdc` | 一条 RX 跨界 | ch0 需要自己的一条 |
| 3 | `rtl/rx_classify.v`（`s_axis_*` 单入口；`fw=76` 字 FIFO，`:70-71`） | 入口无端口维度 | 两路合并必须先解决"帧级互斥 + 端口标签" |
| 4 | `wrapper_p4.v:1981` `tcp_cam u_cam`（键 = `(sip,dip,sport,dport)`；`rtl/tcp_cam.v:9-33`，**无 port 字段**） | 连接身份不含端口 | 同 4 元组在两口的连接会互撞/无法区分出口 |
| 5 | `rtl/tcb.v`（16 槽，`:8-75`） | 槽位是全局资源 | 双口共享 16 槽（容量/分池语义需重新表述） |
| 6 | `wrapper_p4.v:2185` `tcp_tx_frame`（`rb_*` 读 CAM/T CB 得 dmac/sip/dip） | 出口恒 = ch1 | 出口必须按连接选 |
| 7 | `wrapper_p4.v:2473` `slow_rx_adp` → `:2497` HLS `udp_echo` → `:2519` `slow_tx_adp`（**单 AXIS 口，端口概念不存在**；HLS 参数 `MAX_TCP_CONN=3`） | 慢栈不知端口 | ARP/ICMP/SYN-ACK 的回程口必须另行判定 |
| 8 | `wrapper_p4.v:2652` `udp_tx_cfg`（**单 peer 表** `peer_mac/peer_ip`，learn-on-RX，`rtl/udp_tx_cfg.v:66-77`） | 单 peer | UDP app 的 peer 表需加端口（或"最后学会者"语义） |
| 9 | `rtl/app_ctrl.v:28-33` 事件字 `{kind,slot,peer_mac,peer_port,peer_ip}`（102 位）**无端口位**；寄存器映射 `:37-64` | app 看不到"这条连接从哪来" | app 的建连事件/每连接块都需要 +1 位（或另开一读口） |
| 10 | `wrapper_p4.v:2826` `mac_tx_10g u_mac_tx`（唯一 TX 出口） | 一个 TX 出口 | 需要按帧选口（分流/去复用） |
| 11 | `wrapper_p4.v:2800` `fifo_async(73) u_txcdc` | 一条 TX 跨界 | ch0 需要自己的一条 |
| 12 | `wrapper_p4.v:4367-4368` `sfp1_tx_dis = pcie_scratch[0]` | ——（**已有**） | ✔ 无需改（ch0 的发射门已可远程控制） |

**(c) 观测面（75 字快照）—— ch0 是"1 位签名"，LOS 完全没接**

- 快照 = `SNAP_NW_P6E = 75` 字（`wrapper_p4.v:3296`），未实现地址 `0x15C`（`p9_build_0x28/REPORT.md:93-103`）。
- **W39 = PCS 状态束**（`:3647-3663`）：`[30]` = `pcs_ch0_sig`（ch0 全部状态的 XOR），`[29:2]` = ch1 逐位状态，其余 0 ⇒ **ch0 无独立可观测位**。
- **`sfp1_rx_los` / `sfp2_rx_los` 两个输入端口在 wrapper 里没有任何消费者**（现读 `grep -n "los"` 只命中端口声明 `:181,:183`）⇒ **LOS 从未进过快照**【已证·源码】。
- 每个快照字 ≈ **+96 FF**（`snap_cdc.hold_b` 32 + `dout_a` 32 + `snap_words_r` 阵列 32 三份），出处 `P7B_LOOP_HANDOFF.md:430` + 仓根 `CLAUDE.md:18,207`；**扩窗第一观察对象 = 快照阵列异步复位族**（现役全局 WNS 宿主）。

**(d) 资源与时序基线（硬约束）【已证·构建】**

| 项 | 值 | 出处 |
|---|---|---|
| placed | **77,631 LUT / 75,086 FF / 348 BRAM / 1 URAM / 4 DSP / 6 GTYE4** | `p9_build_0x28/REPORT.md:100` |
| 器件总量 | 216,960 LUT / 433,920 FF / 480 BRAM / 64 URAM / 1,824 DSP / 16 GTYE4 | 同上（用量对器件） |
| 全局 WNS / WHS | **+0.065 / +0.010**（周期 6.400 ns ⇒ 余量 **1.02%**）；三类失败端点 0/0/0 | `p9_build_0x28/REPORT.md:93` |
| WNS 宿主 | **快照阵列的异步复位族**（`user_reset_reg → u_pcie_regs/snap_words_r_reg[{2224,2066,2277}]/CLR`，lvl 0，recovery）。DP 域 setup 另有 +0.068（不同对象，⛔ 只并列不比大小，#66） | `p9_build_0x28/REPORT.md:121-129` |
| 功耗（估算） | Total On-Chip **4.380 W**（dynamic 3.772 / static 0.608），Junction 32.6 °C，Confidence **Medium** | `p9_build_0x28/board_rpt/wrapper_p4_power_routed.rpt:33-41` |
| 单套 MAC 的增量锚（OOC 综合，**上界**） | `mac_rx_10g` = **1,453 LUT / 911 FF**；`mac_tx_10g` = **1,602 LUT / 488 FF**（各 0 BRAM/URAM/DSP） | `_proj_10g/p7b_mac_synth/mac_only/mac_{rx,tx}_ooc/.../mac_{rx,tx}_min_top_utilization_synth.rpt` |
| PCS/GT 的增量 | **0** —— 两通道已在核里（结论 1）；再实例化第二个核才会翻倍 | 同上 |

### 1.3 对端现状（2026-10-17 只读实测，本轮唯一一次跨机取证）

命令（全部只读；`tools/peer_ssh.py`，无 sudo、未提权、未改任何配置）：

```
$ lspci | grep -i -E 'sfc|ethernet'
01:00.0 Ethernet controller: Solarflare Communications SFC9120 10G Ethernet Controller (rev 01)
01:00.1 Ethernet controller: Solarflare Communications SFC9120 10G Ethernet Controller (rev 01)
03:00.0 … RTL8111/8168/8211/8411 …
06:00.0 … Wi-Fi 6 AX200 …
$ ip -br link
enp1s0f0np0      DOWN   00:0f:53:2c:68:00 <NO-CARRIER,BROADCAST,MULTICAST,UP>
enp1s0f1np1      DOWN   00:0f:53:2c:68:01 <NO-CARRIER,BROADCAST,MULTICAST,UP>
$ lspci -d 10ee:            →  02:00.0 Serial controller: Xilinx Corporation Device 9034   （板在位）
$ ls /dev/xdma*             →  /dev/xdma0_{c2h_0,control,events_*,…} 全在
$ sudo -n true              →  sudo: a password is required（⇒ /dev/xdma0_user 读不了，**板 BID 本轮未核**）
```

| 事实 | 读数 | 等级 |
|---|---|---|
| 对端 10G 卡 = **SFC9120 双口**；两口 = `enp1s0f0np0`（p0，MAC …:00）/ `enp1s0f1np1`（p1，MAC …:01） | 上表 | 【已证·只读实测】 |
| 两口当前 **DOWN / NO-CARRIER**、无 IPv4、无驱动占用（历史件 `P7B_U7_AND_PEER.md:244-283` 亦如此） | 上表 + `P7B_U7_AND_PEER.md:246-283` | 【已证】 |
| **p1 是唯一实测上过 10000Mbps 的口**；p0 `carrier_changes=0`（**从未 link 过**） | `P7B_U7_AND_PEER.md:246-278` | 【已证·历史板级】 |
| 对端光模块/线缆（`ethtool -m`）需要 root ⇒ **未核**；p0 口"有无模块"同样未核 | `P7B_U7_AND_PEER.md:285-294` | 【未证】 |
| 板在 PCIe 上、XDMA 设备齐全（`/tmp/p7b_biz/` 台架仍在，最近一次板级轮 2026-10-17 在飞） | 只读实测 + `P7B_TL_LEDGER_20261010.md` §10-92 | 【已证·只读实测】 |

⇒ **"双口对双口"实验的硬件条件**：对端两个口都在且干净；缺的是（a）板上第二只模块/第一只模块的确认、（b）**第二根 AOC**（现有唯一一根接在 J8↔p1）、（c）对端 p0 侧的光模块（未核）。

### 1.4 「接入」的三种口径（需用户裁定 ⇒ 映射到 §2）

| 口径 | 含义 | 对应选项 | 成本量级 |
|---|---|---|---|
| 甲：**第二个口能收能发、可当独立业务口** | 两条 10G 各跑业务（TCP/UDP） | S1 / S2 | 高（数据面改造） |
| 乙：**第二个口能收能发、只做测试/镜像** | 不接业务栈，或只做镜像出口 | S3 | 中 |
| 丙：**第二个口只做 bring-up + 观测** | 只证明物理/PCS/GT 与线缆可用 | S4（= P1 的交付面） | 低 |

---

## 2. 使用场景选项（S1–S4）

> 通用前置（四选项共用，不重复列）：`board/wrapper_p4.v` 全部改动包在 `P7B_10G` 内（默认构建逐位不变契约）；每次构建 bump `BUILD_ID_V`（`:4377`）+ 读侧链式同步（§3.3）+ 归档（#54）；禁止 GUI 重编 `vivado_prj`（§4-#7）。
> 资源估算的**方法**：MAC 用 OOC 综合值当上界；FIFO/仲裁器等自写件按行数/结构估（**【推断】等级**，量级 ±50%）；快照字按 **96 FF/字** 计。

### S1 —— 双口独立快路径（两条全功能业务口，各自一套栈）

- **目标**：两条连接可在两口上各自跑满 10G，互不影响（真·两套）。
- **改点清单（文件级）**：
  - 前端：`wrapper_p4.v` 新增第二组 `mac_rx_10g` / `mac_tx_10g` / `fifo_async`（rx/tx 各一）；
  - 数据面：**第二套** `vlan_strip` / `rx_classify` / `tcp_rx` / `tcb` / `tcp_cam` / `tcp_tx_frame` / `retx_ram` / `tcp_echo` / `tx_arb`；`udp_split`/`udp_rx`/`udp_tx_cfg`/`udp_tx_frame` 视需求同批；
  - 慢路径：**第二套 HLS `udp_echo`**（或双口共用一个慢栈 ⇒ 那就退化成 S2）——HLS 是综合产物，加一套 = 重新综合 + 面积翻倍；
  - app：两套 `app_pattern` / `app_udp_pattern` + 两套 `app_ctrl`（或一个 app 用 tid 空间分区）。
- **资源估算【推断】（关键数字是硬的）**：
  - ⛔ **BRAM：+256 tile（`retx_ram`）× 需要第二套 ⇒ 348+256 = 604 > 480 全器件** ⇒ **不可能**（`rtl/retx_ram.v:126`：`reg [63:0] mem_e/o [0:65535]` × 2 = 256 RAMB36；`P7B_BRAM_REPORT.md:22,38`）。
  - 绕法 A：`retx_ram` 迁 URAM —— 单套 **29–32/64 URAM**（`P7B_BRAM_REPORT.md:24,119`），两套 58–64/64（**贴满**），且要改读流水 2→3 级（`retx_ram` 地址网当前是 DP 组第 3 差，0.289 ns，`P7B_BRAM_REPORT.md:94`）。
  - 绕法 B：两套**共享**同一个 `retx_ram`（16 连接池对半）⇒ 那是 S2 的语义 + 两套前端。
  - LUT/FF：第二套数据面 ≈ +15–25k LUT / +10–15k FF（**粗估**，以 `tcp_tx_frame` 2,596 行 + `tcp_rx` 936 行 + HLS 37 BRAM 为锚）；现役余量 LUT 139k / FF 359k ⇒ **不紧**。
- **时序风险**：新逻辑多数落在**新时钟域**（ch0 的恢复钟 tx_mii_clk_0）与既有 DP 域；但两套数据面意味着 DP 域逻辑量近乎翻倍 ⇒ **布线压力与现役 1.02% 余量正交**（无直接预测）；**必须一次构建收口**（纪律）。
- **慢路径影响**：两套 HLS ⇒ 需要重跑 HLS 综合（`run_hls.bat`）与两套 cfg 通道；`app_ctrl` 的事件 FIFO/寄存器映射要复制。
- **验收判据草案（每口一套）**：单口 unpaced 下行（TCP 连续流 ≥ 9.0 Gbps 量级，参照 S3 长流刀的判据形式）+ 上行 + `mism_bytes=0` + `ΔW55`（重传）在饱和档 ≈0 + 两口**同时**跑时的互扰检查（§6.3）。
- **不可逆点**：无（不改既有连接语义；新构建可回退到 0x28 位流）。

### S2 —— 单栈双口（端口 ID 进流/TCB；一套快路径两入口）【**推荐主路线**】

- **目标**：两个物理口共用**一套** TCP/UDP 数据面与一套慢路径；"端口"成为**连接的属性**（新连接从哪进来，其回程就从哪出去）。
- **改点清单（文件级，最小核心集）**：
  1. **RX 合并**（新件，例如 `rtl/rx_merge2.v`，或复用 `tx_arb` 的帧级 2:1 结构）：两路各一条 `fifo_async`（宽度 76→**77**，多 1 位**端口标签**）→ 在 `dp_clk` 域做**帧级**互斥仲裁（`tx_arb` 同款 FSM：空闲时选一路、锁到 TLAST）→ 输出 77 位（含 port 位）单流。
  2. **标签贯穿**：`vlan_strip`（`rtl/vlan_strip.v`）与 `rx_classify`（`rtl/rx_classify.v`，字 FIFO `fw=76`→77、路由队列不变）各 +1 位直通位。
  3. **连接身份**：`rtl/tcp_cam.v` 的 `cfg_*`/`q_*`/`rd_*` 三组各 +1 位 `port`（76 行模块，改动 ~10 行）⇒ 同 4 元组在两口的连接**凭端口区分**；`rtl/tcb.v` 不必改（槽位是 id 的函数）。
  4. **出口分流**：`wrapper_p4.v` 在 `u_txcdc` 处把一个 TX 流按 **per-frame 端口位**分流成两路（各一条 `fifo_async(73→74)` + 各一个 `mac_tx_10g`）。端口位的来源：
     - TCP：由 `tcp_tx_frame` 从 CAM 读回的 `rd_port` 带出（`rd_*` 已是接口的一部分）；
     - UDP app：`udp_tx_cfg` 的 peer 表 +1 位；
     - **慢路径（HLS）**：HLS 无端口概念 ⇒ 用**学习绑定表**（新件，小表：`dst_ip → port`，RX 侧学习"此 IP 来自哪个口"）在 `slow_tx_adp` 出口处贴端口位；ARP/ICMP/SYN-ACK 的 dst 都是"来的那个人"⇒ 绑定必中。⚠️ 同 IP 两口（路由器/同机双口同 IP）时退化 = 最后学会者）。
  5. **app 可见性**（可选但建议同批）：`app_ctrl` 事件字 +1 位（`rtl/app_ctrl.v:33-38` 的 102 位字 → 103 位）或另开一读口把"每槽端口位"暴露给 app。
- **资源估算【推断】**：
  - 第二套 MAC：**+3,055 LUT / +1,399 FF**（= 1,453+1,602 / 911+488，OOC 上界）；
  - 2 × `fifo_async`（77×256 FWFT、74×256）：LUTRAM 型（`rtl/fifo_async.v:82-85`），0 BRAM，量级小；
  - `rx_merge2` + 出口分流 + 绑定表 + 标签贯穿：**+500–1,000 LUT / +200–500 FF**【粗估】；
  - 快照新增字（ch0 状态 1 字 + ch0 MAC 计数 3–4 字 + LOS 沿计数 1 字 + 端口维度计数 1–2 字 ≈ **6–8 字**）：**+576～768 FF**；
  - 合计 ≈ **+4–5k LUT / +2.5–3k FF / +0 BRAM / +0 URAM** ⇒ 对 0x28 基线是**小量级**（LUT 77.6k→82k ≈ 38%）。
- **时序风险**：
  - 新增面集中在 DP 域（合并器/分流器/标签贯穿）；**现役 DP 域 setup WNS 仅 +0.068（1.06%）** ⇒ 任何 DP 域新锥都要按"一次构建收口"对待；
  - 快照新增 6–8 字会**继续喂"快照阵列异步复位族"**（现役全局 WNS 宿主）⇒ 这是本选项的**头号时序观察对象**（不是新数据面逻辑）；
  - 两路 RX 恢复钟互不相关 ⇒ 合并器必须在 `dp_clk` 单域内做（每路各自 `fifo_async` 跨域后合并）——**不要**做双时钟仲裁器。
- **慢路径影响**：HLS 零改动（这是本选项相对 S1 的最大优势）；代价 = 引入"学习绑定表"这一新假设（需门 + 板级负对照）。
- **验收判据草案**：① 每口单口业务通话（同 S3 长流刀判据：`ΔW51 = TX_BYTES` / `mism_bytes=0` / `ΔW15/ΔW51 = 1.000000`）；② **跨口连接归属判据**：从 p0 建连的数据从 p0 回（对端 p0/p1 两侧 NIC 计数分摊必须对得上）；③ 同 4 元组在两口的构造性对撞（负对照：去掉 CAM 的端口位 ⇒ 必红）；④ 慢路径绑定：从 p0 发 ARP/ICMP ⇒ 回包必须从 p0 出（p1 上抓到 = FAIL）。
- **不可逆点**：**CAM/事件字/TB 期望的语义变更**（4 元组 → 5 元组）会让既有回归语料里"同 4 元组"的断言全部需要复核 —— 这不是物理不可逆，但是**回归面的一次大改**（本工程最贵的一类返工）。

### S3 —— 一口业务 + 一口镜像/测试

- **目标**：ch1 继续跑现役业务；ch0 当**板内测试口/镜像出口**。
- **三种子形态（成本递增）**：
  - **S3a 板内自环测试口**（推荐先做）：ch0 与 ch1 之间用一根 AOC 板内自环（闸 1 构型），ch0 跑"自产帧 → 自收校验"（复用 `_proj_10g/xxv_loop/` 的官方 gen/mon 或我们自己的 `mac_tx_10g`→`mac_rx_10g`）。**不碰业务数据面**，但占用 ch1 的光口 ⇒ 与业务互斥（不能同时接对端）。改点 = 新件一个 `p7b_ch0_selftest.v` + wrapper 分支；资源 ≈ +3.1k LUT（一对 MAC）。
  - **S3b ch0 纯 RX 嗅探/计数**：ch0 加 `mac_rx_10g` + 计数进快照（+1,453 LUT/+911 FF + 1–2 字）。对端 p0 发流、板只收不答（对端需要"只管发"的工具，`p7b_udp_src` 类已有）。**风险最低的"数据面接入"**。
  - **S3c ch0 镜像出口（TX mirror）**：把 ch1 的**出向帧**在 `u_txcdc` 前**扇出一份**（不改变原路时序：镜像支路 = 独立 `fifo_async` + `mac_tx_10g`，满则**丢整帧**），线上一份完整副本 ⇒ 对端 p0 可抓包（比 PCIe 镜像快得多、且是线上真值）。改点 = 新件 `tx_mirror2.v`（帧级 fanout，必须"丢帧不丢字"）+ wrapper 分支。资源 ≈ +1,602 LUT / +488 FF + FIFO + 快照计数 1–2 字。⚠️ 注意：镜像**不是**无损（满即丢），且 **RX 方向没有镜像**（要 RX 镜像就回到 S2 的入口合并）。
- **时序风险**：S3c 的 fanout 直接**坐在现役 TX 关键路径旁**（`u_txcdc` 上游）⇒ 本选项最贵的一处；S3a/S3b 风险低（独立实例、不进现役链）。
- **慢路径影响**：S3a/S3b 零影响；S3c 零影响（旁路）。
- **验收判据草案**：S3a = 闸 1 同款（帧数守恒 + 逐字节 + `/E/`=0 + 负对照拉 TX_DIS）；S3b = 对端 NIC `port_tx_*` 与板侧 ch0 计数对账（±0.2% 量级）+ 零丢帧；S3c = ch1 业务读数**不退化**（同会话 A/B：镜像开/关）+ p0 抓到逐字节等于 p1 发出的流 + 镜像溢出计数可读。
- **不可逆点**：无（都是旁路件）。

### S4 —— 最小接入（只 bring-up + 观测，不接数据面）

- **目标**：把"第二个口现在能不能收能发"变成**可读数字**，别的什么都不承诺。
- **改点清单**：`wrapper_p4.v` 的 ch0 段：① ch0 PCS 状态**逐位**镜像进快照（新字，与 W39 同款位域）；② `sfp{1,2}_rx_los` + 其变化沿计数进快照；③ 可选：ch0 `mac_rx_10g` + 10 个 stat 计数（+1,453 LUT/911 FF，3–4 字）做"真的收到帧了"的正证据；④ 可选：把 ch0 TX 的常量 IDLE 换成**官方 example 的图案发生器**（闸 1 配方，`_proj_10g/xxv_loop/rtl/pcs64_pkt_gen_mon_ds.v`）⇒ 对端/自环端可测量、可校验（+2,238～4,917 LUT 量级，可裁）。
- **资源估算**：**+~1.5–5k LUT / +~1–1.5k FF / +0 BRAM**（取决于③④是否打开）+ **4–6 快照字（+384–576 FF）**。
- **时序风险**：**最低**；唯一要盯的仍是快照阵列复位族。ch0 的 MAC/发生器在**新时钟域**，对现役 DP 域无直接压力。
- **慢路径影响**：零。
- **验收判据草案**：① 对端 p0 `carrier` 起立/拉 TX_DIS 后必掉（独立仪器）；② 板侧 ch0 `block_lock/status` 逐位可读；③ ch0 RX 计数随对端 p0 发包而涨（`Δframes = ΔNIC port_tx_packets` 量级）；④ 负对照：物理拔线 ⇒ LOS 计数沿 +1、block_lock 掉。
- **不可逆点**：无；**S4 = P1 的交付面**（§5）。

### 选项对照（一句话）

| 选项 | 一口/两口业务 | 数据面改动 | BRAM | 推荐度 |
|---|---|---|---|---|
| S1 | 两口各自全栈 | 巨大（两套） | ⛔ +256 tile **不可行**（除非 URAM 迁移且贴满） | 不推荐（除非用户明确要"完全独立"并接受 URAM 迁移轮） |
| S2 | 两口共栈 | 中（标签贯穿 + CAM + 分流 + 绑定表） | +0 | ⭐ 主路线 |
| S3 | 一口业务 + 一口辅助 | 小～中（旁路件） | +0 | ⭐ 先导/可选（S3a/S3b 便宜） |
| S4 | 无业务 | 极小 | +0 | ⭐ P1 必做（它是 S2/S3 的观测底座） |

---

## 3. 实现路径

### 3.1 PCS core "单→双通道" 三种做法评估（现读 `build_p7b_ku5p.tcl` + 核配置后）

| 做法 | 内容 | 评估 | 结论 |
|---|---|---|---|
| **① 同一 core 双通道**（`NUM_OF_CORES=2` + `LANE1_GT_LOC=X0Y4` + `LANE2_GT_LOC=X0Y5`） | 现役配置：`build_p7b_ku5p.tcl:48-59`；生成产物两子核 `ip_0`/`ip_1` 回读 `CHANNEL_ENABLE = X0Y4 / X0Y5`、各 `10.3125`、`TX/RX_REFCLK_SOURCE = X0Y4 clk0 / X0Y5 clk0` | **已经是现役做法**；板级已由闸 1（两通道同时跑）与所有后续构建证明；**不需要任何 PCS 改动** | ⭐ **采用（零工作）** |
| **② 第二个 core 实例**（再来一个 1 通道核） | 两个 `xxv_ethernet` IP 各 1 通道 | ⚠️ 两核都要 `INCLUDE_SHARED_LOGIC`、都要 QPLL——同 quad 的 common（QPLL0/参考钟缓冲）会**被两份共享逻辑重复声明**；核自带 XDC 的 `create_clock` 会二次声明（闸 1 已实测过"重新声明会替换成具名副本"这一类相互作用，`ku5p_p7b_gt.xdc:27-32`）；且**多花 ~2.2k LUT 的共享逻辑** | 不推荐（同 quad 双核是已知的高风险构型） |
| **③ 双 GT 手动例化**（自己拉 `GTYE4_CHANNEL` + 自写 PCS） | 绕开官方核 | ⛔ 直接违反 `P7B_SPEC.md:133-145`（§2.2）的**反向要求**：自己写加扰器/块同步/gearbox/`rxgearboxslip` = **安静失效**（链路照锁、每帧全错）——这是 P7a→P7b 路线变更的教训 | 禁止 |

**⇒ 路径结论**：PCS 侧**零改动**；当前 wrapper 已经按"两通道成对端口"接好了全部 GT/PCS/时钟/复位，"接入"只需给 ch0 挂数据与观测。

### 3.2 XGMII → 数据面的耦合方式（S2 主线）

**RX 侧（ch0 + ch1 → 单流）**：

```
mac_rx_10g(ch0) ─→ fifo_async(77×256, FWFT) ─┐
                                              ├─→ rx_merge2 (dp_clk 单域, 帧级互斥) ─→ 77bit 单流 ─→ vlan_strip(+1 pass) ─→ rx_classify(+1 pass) ─→ …
mac_rx_10g(ch1) ─→ fifo_async(77×256, FWFT) ─┘
```

要点（逐条）：
1. **每口各自跨域**（两路 RX 恢复钟互不相关）⇒ 合并器**只能**在 `dp_clk` 单域，禁止在合并器里做双时钟逻辑。
2. **帧级互斥**（同一时刻只允许一路推进到 TLAST）——`rtl/tx_arb.v` 就是同款结构的现成先例（53 行，"空闲时选并寄存、锁到 TLAST"），可直接改名复用/扩展为 2:1 带标签版本。
3. **标签宽度 = 1 位**（two ports）；若将来要 N 口，合并器与 CAM 的 port 字段按 ⌈log₂N⌉ 加宽。
4. **不能做的**：把两路 XGMII 直接异或/交织（字级交织会毁帧）；在 `mac_rx` 上游做合并（每口 PCS 时钟域各不相同）。

**TX 侧（单流 → 两口）**：

```
… → tx_arb → [u_txcdc 之前] tx_split2 (按帧端口位分流) ─┬─→ fifo_async(74×256) ─→ mac_tx_10g(ch0) → tx_mii_d_0
                                                        └─→ fifo_async(74×256) ─→ mac_tx_10g(ch1) → tx_mii_d_1
```

- **端口位来源三路**（同一根 1 位信号，按帧稳定）：TCP = CAM `rd_port`；UDP app = peer 表 +1 位；**慢路径 = 学习绑定表**（`dst_ip → port`，RX 侧边学边写，小表 4–16 项即够：ARP/ICMP/SYN-ACK 的 dst 必是刚来过的那个人）。
- **备选（更省状态、但要动 HLS）**：**每口一个板 IP**（port0 = `192.168.100.2`、port1 = `192.168.100.4`）⇒ 出口端口 = `f(src_ip)`（一个比较器），且 RX 侧 CAM 的 `dip` 天然区分两口连接（**CAM 都不用改**）；代价 = HLS 慢栈要认两个 IP（`hls/src/` 改动 + `run_hls.bat` 重新综合），且对端要能容忍两个目标 IP。**登记为备选**（§7-3）。
- **字宽连锁**：RX 字 76→77、TX 字 73→74；`rx_classify` 的 `FW=76`→77（`rtl/rx_classify.v:70-71`）、`u_rxcdc/u_txcdc` 的 `WIDTH` 参数同步；**所有"逐字拼接"处都要按 §3.3 的清单同步**（少一处 = 静默截断，工程坑 24 的同族）。

### 3.3 观测窗口扩展（新字 = 一次"五处同改 + 读侧链式同步"）

现役几何：**75 字**（`wrapper_p4.v:3296`）、未实现地址 `0x15C`、`snap_idx = r_word[6:0]-8`（7 位译码 ⇒ 上限 119 字；回绕红线 ≥0x200）。

**加字的标准动作（照 0x28 构建轮的实际流程）**：
1. `wrapper_p4.v`：`SNAP_NW_P6E` +1；对应束的 `*_src` 拼接 +1 项；装配段 `snap_dout_all` +1 项（**拼接项数必须恰 = SNAP_NW_P6E**，`:3461` 注释）；
2. `_proj_pcie/rtl/axi_regs.v` 的 `.SNAP_NW`（`wrapper_p4.v:4858`）；
3. TB 期望：`sim/p6e_pcie/tb_p6e_pcie_wrapper.v`（全链 148 PASS 基线）+ `tb_p6e_pcie_counters.v`；
4. 读侧脚本（**链式同步**）：`_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py --bid <新BID>`（0x28 轮 = **63 处 / 20 文件**，含 `check_window.py` / `tb_biz_win.v` / `j6_r6fix.sh` / `p7b_snap.sh` / `p6e_snap_check.sh` / 三个指纹 bat 等）；
5. 几何常量与"未实现地址"三处（`final_state.sh` / `tb_p7b_chain.v` / 读侧默认哨兵）。

**候选新字（本计划的建议集，优先级排序）**：

| 优先级 | 新字 | 内容 | 束/域 | 为什么 |
|---|---|---|---|---|
| P1 | +1 字 | **ch0 PCS 状态束**（与 W39 同款位域：block_lock/status/hi_ber/local_fault/framing_err/bad_code/error/fifo_error/tx_local_fault/gpwr/user_*_reset） | dp（每位 2FF，同 W39 手法） | ch0 从"1 位签名"升格为逐位可读 —— **S4/P1 的最小观测面** |
| P1 | +1 字 | `sfp1_rx_los` / `sfp2_rx_los` 电平 + **变化沿计数** | dp（输入异步 ⇒ 2FF） | LOS 目前**从未进过快照**（现读 `grep -n los` 只命中端口声明） |
| P2 | +2～4 字 | ch0 `mac_rx_10g` 的帧/字节/FCS 错/丢帧（抬用的是与 W0/W1/W3/W4 同名口径） | ch0 RX 恢复域（多比特计数器**不许** 2FF，需独立束） | S3b/S2 的 RX 正证据 + 速率对账 |
| P2 | +1～2 字 | ch0 `mac_tx_10g` 的帧/字节/abort | ch0 TX-MII 域 | S3c/S2 的 TX 正证据 |
| P3 | +1 字 | 端口维度计数：`rx_merge2` 的各口帧数 / 出口分流各口帧数（**合并器自检**：`Δin = Δout_port0 + Δout_port1`） | dp | **合并/分流器是新增的帧序风险点**，必须有守恒律 |

⚠️ **成本口径**：**每字 ≈ +96 FF**（三份）；**+7 字 ⇒ ≈ +700 FF**，且**全部落"快照阵列异步复位族"= 现役全局 WNS 宿主**（`p9_build_0x28/REPORT.md:121-129`）⇒ **"再往窗口加字会继续吃这条"是本计划第一位的构建风险**。若实测吃不动 ⇒ 备选是本轮已存在的 `app_rx_mirror`/URAM 路径（把诊断数据走 PCIe 镜像通道而非快照字），但那要另开一档设计（登记 §7-6）。

### 3.4 SFP 控制脚与 LOS 接线（两块 XDC 的现实）

| 信号 | 现状 | 双口下要做的 |
|---|---|---|
| `sfp1_tx_dis` / `sfp2_tx_dis` | 已接：`= pcie_scratch[0]/[1]`（`wrapper_p4.v:4367-4368`，非 PCIE_OBS 构建钉 0） | **零改动**（ch0 的发射门已可远程控制 —— 这正是零构建先导步的负对照手段） |
| `sfp1_rx_los` / `sfp2_rx_los` | 端口在、XDC 在（`ku5p_p7b_gt.xdc:37-38`，PULLUP），但**wrapper 里无消费者** | P1 接进快照（§3.3 第 2 行） |
| 引脚映射 | ⚠️ **厂商两份 XDC 都把每对脚对调**（实测：`SFP1_TX_DIS=C11 / SFP1_RX_LOS=B11 / SFP2_TX_DIS=D9 / SFP2_RX_LOS=C9`） | 任何新约束**必须抄 `ku5p_p7b_gt.xdc` 这份实测版**，绝不抄厂商件 |
| 位流纪律 | `12-4739`（约束被静默丢弃）是构建硬门之一 | 新增约束后**在 impl 日志 grep `12-4739`**（命中 = 约束没生效） |

### 3.5 XDC / 时钟（现状已覆盖，预计零新增约束；但需复核）

- 时钟组约束现状（`ku5p_p7b_cdc.xdc:36-39`）：三组 `set_clock_groups -asynchronous`（`sys_clk_100` 系 / `pcie_axi_aclk` 系 / `gtrefclk0` 系），PCS 的 `tx_mii_clk_N` 与 `rx_clk_out_N` 都是 `gtrefclk0` 的派生 ⇒ **两通道的四个 MAC 时钟已在同一组内，不需要新增组**【已证·源码 + 推断】。
- ⚠️ 该文件**必须由构建脚本标 `used_in_synthesis false`**（`build_p7b_ku5p.tcl:271`）；`12-4739` 硬门复核不可省。
- 时钟报告事实：ch0 的 `rxoutclk_out[0]_2`（1428 负载）/ `txoutclk_out[0]_2`（577 负载）**已在跑**（`p9_build_0x28/board_rpt/wrapper_p4_clock_utilization_routed.rpt`）⇒ 新增消费者只是加负载，不新开时钟。

---

## 4. 硬约束清单（不许漏；逐条带出处）

| # | 约束 | 出处 | 对本计划的含义 |
|---|---|---|---|
| 1 | **时序余量 = 1.02%**（全局 WNS `+0.065` / 周期 6.400）；**宿主 = 快照阵列异步复位族**（lvl 0，recovery） | `p9_build_0x28/REPORT.md:93,121-122` | 任何新逻辑 **一次构建收口**；加快照字是**头号风险**（+96 FF/字） |
| 2 | DP 域 setup WNS `+0.068`（不同对象，只并列） | `p9_build_0x28/REPORT.md:128-129` | S2 的合并/分流/标签贯穿都落 DP 域 ⇒ 按最薄处对待 |
| 3 | BRAM 348/480（72.5%）；`retx_ram` 独占 256；**余量 132** | `P7B_BRAM_REPORT.md:22-24`；`p9_build_0x28/REPORT.md:100` | ⛔ S1-full 不可行；S2/S3 不新增 BRAM |
| 4 | URAM 1/64（余 63）；URAM 迁移只有 `retx_ram` 够格（29–32/套，读流水 2→3 级，地址网已近临界 0.289） | `P7B_BRAM_REPORT.md:24,119-124,94` | 若用户要 S1 ⇒ 先做 URAM 迁移轮（**独立一轮**） |
| 5 | GT 通道 6/16（余 10）；两通道共用 quad 225 的 QPLL0 与 `MGTREFCLK0_225`（156.25 MHz）；`qpllreset_in_0` 是 common 级（恒 0） | `p9_build_0x28/REPORT.md:100`；`ku5p_p7b_gt.xdc:27-32`；`P7B_XXV_OFFICIAL.md:321`；子核 `.xci` 回读 | 双口**不需要新 GT/新参考钟**；⚠️ 任何碰 QPLL 复位的改动会**同时扰动两口** |
| 6 | SFP 控制脚**实测映射**（厂商 XDC 两处错）；TX_DIS 高有效 + 上拉 ⇒ 悬空 = 全黑 | `ku5p_p7b_gt.xdc:9-10,34-38` | 新约束只抄这份；排查"全黑"先查 TX_DIS 电平 |
| 7 | ⛔ **GUI 重编 `vivado_prj` 有"永久禁发"陷阱的历史**；构建**只走** `board/run_build_p7b_ku5p.bat` | 仓根 `CLAUDE.md`「P7b」节；`P7B_LOOP_HANDOFF.md` §6-B-7 | ⚠️ **本件现读订正**：`vivado_prj/p7b_ku5p_prj.srcs/sources_1/imports/board/wrapper_p4.v` 现在与 `board/wrapper_p4.v` **逐字节相同**（sha256 `3b39c85f…68a2`，均 0x28 代）⇒ 那句警告所指的**具体旧版陷阱当前不成立**，但纪律不变（GUI 编的是上一次 import 的快照） |
| 8 | 每次构建 **bump `BUILD_ID_V`**（现役 `0x28`，`:4377`）；位流全代同尺寸 ⇒ **只有 sha256/BID 能分版** | `p9_build_0x28/REPORT.md`；`P7B_LOOP_HANDOFF.md` §4 | 双口每一步构建都要 bump + 读身份门 |
| 9 | **读侧链式同步**（BID + 几何，63 处/20 文件量级）+ **未实现地址**三处 + TB 期望同批改 | `p9_build_0x28/REPORT.md` ② | 漏改 = 静默误读（不是编译错） |
| 10 | **归档纪律（#54）**：`create_project -force` 开工即清 impl_1 ⇒ 归档必须写进构建脚本 | 全局经验 #54；`p9_build_0x28/REPORT.md:103` | 双口轮的每一代都要归档（位流/dcp/报告/SHA256SUMS） |
| 11 | ⛔ **绝不写板载 QSPI**（厂商 XDMA+DDR4 设计在里） | 仓根 `CLAUDE.md` 纪律① | 只走 JTAG 易失烧录 |
| 12 | `sfp*_rx_los` 现无消费者；ch0 输出**必须有真实负载**（否则 `opt_design` 硬失败，已踩两次） | `wrapper_p4.v:556-565`；`grep -n los` 零消费者 | 新逻辑引用 ch0 状态时按"加负载"处理，别留悬空 |
| 13 | 板级测量前置：构建期间不得从被构建工程烧位流；每次测量前重烧 + 核 sha256；`0x08` 既是 SCRATCH 又是 TX_DIS 门 | `P7B_LOOP_HANDOFF.md` §6-B；`wrapper_p4.v:4355-4371` | 双口轮也要照办（且**双口轮要用 `0x08` bit0/bit1 分别当两口发射门**） |
| 14 | 对端运行配置每次重启都要重来（`/32` + `nmcli … managed no` + `ethtool -C … adaptive-rx off rx-usecs 0`） | `P7B_LOOP_HANDOFF.md` §6-B-3 | 双口轮还要给 **p0** 配第二套（`192.168.100.101/32` 之类）——**两个口都会被 NetworkManager 冲** |

---

## 5. 分阶段计划（P1 → P3）+ 每阶段验收判据

> **总原则**：① 每阶段**一次构建收口**；② 先零构建、再低风险、再高成本；③ 每阶段的观测面先于功能面（"先能看见，再谈改造"）；④ 与现有门/矩阵的接口逐条挂上（§5.X 末列）。
> ⚠️ **与在飞工作的关系**：截至 2026-10-17 03:3x，板级轮（P-3 窗口 + 涓流实验 A，三烧 `0x28→0x24→0x28`）**在飞**（`P7B_TL_LEDGER_20261010.md` §10-92）。本计划**不与该轮抢板**：P0/P1 的零构建步可并行（不需要板），需要烧板的步骤排在在飞轮收口之后。

### P0 —— 零构建先导（**不做任何 RTL/构建**）★ 建议第一步

| 步 | 动作 | 判据（草案） | 负对照 |
|---|---|---|---|
| P0-1 | 物理：确认**第二只光模块**与**第二根 AOC**；把 AOC 接成 `J7 ↔ 对端 enp1s0f0np0`（J8↔p1 保持不动） | 现场目检 + 对端 `ip -br link` 的 p0 `carrier` | —— |
| P0-2 | 烧/确认现役 `0x28` 位流（**板子当前可能被在飞轮换过代**；以 `0x04 == 0x28` 为准） | 身份门（MAGIC/BID/75 字/`0x15C`） | —— |
| P0-3 | 观察对端 p0 是否起 link（ch0 TX 恒发 `/I/` ⇒ 对端 PCS 应能 `block_lock`） | `enp1s0f0np0 carrier=1` + `carrier_changes` **新跳变**（不是陈旧值） | 写 `0x08` bit0=1（拉高 `sfp1_tx_dis`）⇒ p0 `carrier 1→0`**且** `carrier_changes` 再 +1；恢复 ⇒ 0→1 |
| P0-4 | 反向（ch0 RX）粗判：对端 p0 发流，看板侧 **W39[30] 签名位**是否变化 | 签名位在"有光/无光"两态间**出现可辨变化**（弱判据，只作方向性） | 拔线 ⇒ 签名位回到无光态 |

- **成本**：0 构建、0 RTL；**风险 = 物理接线**（拔插光模块/AOC）。
- **产出**：把"J7 的 GT/PCS/模块/线缆是否可用"从【未证】抬到【已证】。
- ⚠️ **限制**：P0-4 的签名位是 17 个信号的 XOR ⇒ **不可逐位归因**（这是它必须被 P1 取代的原因）。

### P1 —— ch0 单口 bring-up + 观测面（**低风险先导构建**；对应 S4）

- **RTL 面**（全部包在 `P7B_10G` 内）：
  1. `wrapper_p4.v`：ch0 PCS 状态逐位 2FF 进**新 dp 束字**（照 W39 手法，`:3580-3663` 的现成模板）；`sfp1_rx_los`/`sfp2_rx_los` + 沿计数进字；`BUILD_ID_V` bump（建议 `0x29` 起）。
  2. （可选同批）ch0 `mac_rx_10g` + 计数（+1,453 LUT/911 FF）+ 2–4 字。
  3. （可选同批）ch0 TX 换成官方 example 图案发生器（闸 1 配方）或我们的 `mac_tx_10g` 自发测试流。
- **观测面**：§3.3 的候选新字 P1 两行（+2 字 ⇒ +192 FF）。
- **验收判据（草案）**：
  - 构建：三类失败端点 0/0/0 + `12-4739` 0 命中 + 位流 sha256 归档；**逐档并列 WNS（不比大小，#66）**；
  - 仿真：`sim/p6e_pcie/run_tb_p6e_pcie.bat`（全链）+ `…_counters.bat` 扩到新字（基线 148/26 PASS 必须全绿）；`run_tb_p7b_chain.bat`（106 判据）零回归；
  - 板级：P0 的三条（carrier / TX_DIS 负对照 / LOS）**逐条复算**，加"ch0 计数随对端 p0 发包单调 + 零丢帧"。
  - **与现有门的接口**：常驻矩阵 19 门（`sim/p4gates/run_matrix_p4dfix.bat`）**零回归**（P1 不改数据面 ⇒ 预期 19/19 FROZEN，但**指纹会变**（wrapper 改了）⇒ 指纹漂移必须逐条可解释）。
- **不可逆点**：无。

### P2 —— ch0 数据面接入（二选一，视用户口径乙/甲）

| 分支 | 内容 | 验收判据草案 |
|---|---|---|
| **P2-a（S3c，镜像/测试口）** | ch0 = ch1 出向帧的镜像出口（fanout 在 `u_txcdc` 前，独立 FIFO + `mac_tx_10g`，满即丢整帧） | ① 同会话 A/B：镜像开/关时 ch1 业务读数不退化（判据 = 业务速率/`mism` 同档）；② 对端 p0 抓到逐字节等于 p1 出向流（对端 pcap 或 NIC 计数对账）；③ 镜像丢帧计数可读且 = 0（无背压时） |
| **P2-b（S3b/S2 前置，RX 接入）** | ch0 RX 接入 `rx_merge2`（77 位含标签）→ `rx_classify` →（先只统计，不路由到业务） | ① 守恒律 `Δmerge_in = Δport0 + Δport1`；② 对端 p0 发流 ⇒ 板侧 ch0 帧/字节计数与 NIC `port_tx_*` 对账（±0.2% 量级）；③ 逐字节校验（用 `p7b_udp_src` 图案流 + 板侧计数口径）④ 负对照：把标签位钉 0 ⇒ 两口数据混流/计数错（证明标签有效） |
| **共同要求** | 一次构建收口；快照新增字按 §3.3；新件必须有**单元门**（`sim/p7b_dualsfp/` 类新目录），且**新件进常驻矩阵**（避免 `P4 矩阵指纹对 app_pattern.v 两种盲` 的旧债重演） | 矩阵 20/20（新增 1 门） |

### P3 —— 双口业务共存（S2 全量）

- **RTL 面**：§2-S2 的 5 条改点（CAM +1 位 / 标签贯穿 / 收发分流 / 慢路径绑定表 / app 可见性）。
- **验收判据（草案）**：
  1. **单口基线**：每口各跑一次单口 unpaced 长流（判据形式照长流刀：`ΔW51 = TX_BYTES`、`mism_bytes=0`、`ΔW15/ΔW51 = 1.000000`、跨 2³² 回卷无异常）；
  2. **跨口归属**：p0 建连的数据必须从 p0 回、p1 从 p1（对端两侧 NIC 计数独立对账 ⇒ **两条独立的仪器**）；
  3. **慢路径绑定**：从 p0 发 ARP/ICMP/SYN ⇒ 回包只出现在 p0（负对照：把绑定表钉死成 port1 ⇒ 判据必红）；
  4. **同 4 元组对撞**（构造性负对照）：同 `(sip,dip,sport,dport)` 从两口各建一连接 ⇒ 无端口位时应失败/互串，加端口位后各自独立；
  5. **双口同时跑**：§6.3 的互扰检查（吞吐/帧率/丢弃/CRC/温度）；
  6. **业务速率**：目标值域 = 每口向"线上载荷天花板"逼近（TCP `1460/1538×10 = 9.493 Gbps`；UDP app `1472/1538×10 = 9.5709 Gbps`）；⚠️ **达标界待用户裁**（本件不下裁定）。
- **风险处置**：任一步吃穿 WNS ⇒ 按"一次构建收口"回到上一代位流（`0x28` 可回退）。

### 与现有门/矩阵的接口（汇总）

| 现有件 | 在本计划中的角色 | 需要做的事 |
|---|---|---|
| `sim/p4gates/run_matrix_p4dfix.bat`（19 门常驻矩阵） | 数据面回归主入口 | 新件（merge/split/绑定表/mirror）**必须进矩阵**（新增门 ⇒ 20+）；每轮核"指纹漂移逐条可解释" |
| `sim/p6e_pcie/run_tb_p6e_pcie.bat`（全链 148 PASS）+ `run_tb_p6e_pcie_counters.bat`（26 PASS） | wrapper/快照/PCIe 全链门 | 新快照字 + 新 BID ⇒ 两门期望值同批改（0x28 轮先例：修前两门各恰 1 红 = 咬合见证） |
| `_proj_10g/p7b_chain/`（链级 106 判据） | MAC/帧流合同回归 | 双口不改 MAC 合同 ⇒ 应零回归；但"合并器"引入新的帧序风险 ⇒ 建议在链级门加"标签守恒"族 |
| `_proj_10g/p7b_mac/sim/`（MAC 单元门 391 checks） | 第二套 MAC 实例直接复用 | 无需改（同一模块） |
| `board/run_build_p7b_ku5p.bat` + `build_p7b_ku5p.tcl` | 唯一构建入口 | 新增 RTL 件要**加入 `import_files` 清单**（漏加 = black box = 安静失效，先例：`mir_uram_fifo.v` 那行注释，`build_p7b_ku5p.tcl:102-106`） |
| 读侧同步工具 `apply_readside_bid1c.py` | BID/几何同步 | 每轮必跑；`--bid` 传新值 |

---

## 6. 板级测试计划

### 6.1 板内 J7↔J8 自环臂（**复用闸 1 配方**）

- 构型：AOC 接 `J7 ↔ J8`（板内），对端机不参与。
- 两种用法：
  - **A（官方例程）**：`_proj_10g/xxv_loop/` 工程原样重编（2 通道核 + `pcs64_pkt_gen_mon_ds.v` + `xgmii_rx_chk.v`），判据 = 闸 1 原判据（帧数守恒 + 逐字节 + `/E/`=0 + `completion_status`）。
  - **B（我们自己的 MAC）**：ch0/ch1 各挂 `mac_tx_10g`/`mac_rx_10g`，ch0 发 / ch1 收（或双向），判据 = 线上帧逐字节 + FCS 零错 + 帧数守恒。
- **注意**：A/B 都要求**两个光模块同时在位**；B 需要 P2 的代（ch0 有 MAC）。
- **价值**：这是**不需要对端机**的 10G 全链验收面（闸 1 已证有效）。

### 6.2 对端双口臂（视 §1.3 与 §7-1）

- 构型：`J7 ↔ enp1s0f0np0` + `J8 ↔ enp1s0f1np1`（需要两根 AOC + 两侧模块）。
- 对端配置（每次重来，双双配置）：p1 保持现役配方；p0 加 `192.168.100.101/32`（或按裁定）+ `nmcli … managed no`（两个口都要）+ `ethtool -C … adaptive-rx off rx-usecs 0`（p0 必做，否则"读数低"先撞中断合并，全局 #68）。
- 仪器（**两套独立**）：两口各自的 `ethtool -S`（`port_tx_bytes`/`port_rx_*`）+ 板侧快照计数 +（可选）双口 pcap。
- 判据草案：板侧 ch0 收帧/字节 == 对端 p0 `port_tx_packets/bytes`（±0.2%）；零 `rx_eth_crc_err`；`Δnodesc_drops` 关注（对端描述符耗尽曾造成 1.72% 接收限制）。
- ⚠️ 需要"能单流 >8 Gbps 的对端发送端"（现台架的限制历史见 `P7B_BOARD_STAGEB_ACCEPT`；长流刀已把 sink 提速到 11.15 Gbps 端到端）。

### 6.3 双口并存互扰检查（同 quad 两通道 / 共享 refclk / 热 / 功耗）

| 检查项 | 判据草案 | 现有依据 |
|---|---|---|
| GT/光路并存 | 两口**同时**双向跑固定时长：逐口 `/E/`=0、block_lock 恒 1、帧数守恒 | 闸 1 已证"两通道同时跑"（30M 帧零错） |
| 共享 QPLL/refclk | 不碰 `qpllreset_in_0`（恒 0）；任何 GT 复位动作要意识到**影响两口** | `P7B_XXV_OFFICIAL.md:321`；`wrapper_p4.v:495` |
| 板内互扰（吞吐） | 两口同时满速时，各口速率与单口时同档（同会话 A/B；⚠️ 判据必须记**台架帽是否在位**，全局 #43/#59/#68） | 长流刀/双向轮的判据形式 |
| 热/功耗 | 2 通道 GT + 1–2 套 MAC 的增量功耗（估算量级 <1 W vs 现 4.38 W）⇒ 关注实测结温/风扇；⚠️ 现报告 Confidence **Medium** | `wrapper_p4_power_routed.rpt` |
| 时钟资源 | ch0 时钟已在跑（1428/577 负载）⇒ 加负载不新开时钟；BUFG_GT 余量充足 | `wrapper_p4_clock_utilization_routed.rpt` |
| 板对板连接器（12 GHz 手册约束） | 两条 10.3125 GBd 同时过连接器 = 闸 1 已实测过的构型；⚠️ 手册的"12 GHz"是**单 lane SI** 结论，双 lane 只叠功耗/串扰风险，**未被专门测过** | 仓根 `CLAUDE.md`「10G 硬件约束」；`P7B_GATE1.md` |

### 6.4 板级轮的环境前置（每次）

- 板：重烧 + 核 sha256 + 身份门（`0x04` BID / 75 字 / `0x15C` `0xffffffff` / `LnkSta x4` / `identify_bars` **2 BARs**）。
- 对端：`ip route get` / `CARRIER` / `ethtool -c` 三件现取见证；`/32` 与 `managed no` 重配（**两口都要**）。
- 工具：`/tmp/p7b_biz/` 部署（配方 `p7b_affinity/BUILD.md`）；⚠️ 已知部署异常：`p7b_tcp_src_rate` 曾是 sink 的**同名副本**（`P7B_TL_LEDGER_20261010.md` §10-92）⇒ 双口轮用发送端前**先核 md5**。

---

## 7. 未定 / 风险 / 待用户裁定清单

| # | 项 | 现状 | 谁定 |
|---|---|---|---|
| 1 | ⭐ **物理件**：第二只光模块（板侧）、对端 p0 侧模块、**第二根 AOC** 是否在位/在手 | **未核**（本轮禁写对端；闸 2 只证"只有一根 AOC"+"J7 黑"） | **用户**（现场目检/采购） |
| 2 | ⭐ **口径**：甲乙丙三口径（§1.4）选哪个？ | 未定 | **用户** |
| 3 | **出口端口解析法**：S2 的「CAM +1 位 + 慢路径学习表」 vs 备选「每口一个板 IP（要动 HLS + 重新综合）」 | 未定（本件推荐前者：HLS 零改动） | **用户/设计裁定** |
| 4 | ⛔ **半双工复用**：现有物理只有 1 根 AOC（如第 1 号项未解决）⇒ 是否接受"J7 与 J8 二选一"（即 S3a 自环与业务口互斥） | 未定 | **用户** |
| 5 | **S1 是否要**：若坚持"两口完全独立全栈" ⇒ 前置 = **URAM 迁移轮**（`retx_ram` 29–32 URAM/套 × 2 = 58–64/64 贴满 + 读流水 2→3 级，地址网已 0.289 = DP 第 3 差） | 未定 | **用户** |
| 6 | **观测扩容的上界**：+7 字 ≈ +700 FF 全落"快照阵列复位族"（现役 WNS 宿主）⇒ 若吃不动，是否改走镜像/URAM 通道 | 未定（需一次构建实测） | **用户/构建轮实测后定** |
| 7 | **在飞工作不抢板**：板级轮（P-3 窗口 + 涓流 A）在飞（`P7B_TL_LEDGER_20261010.md` §10-92）；另 `p7b_tcp_src_rate` 部署异常未修 | 登记 | TL/用户排期 |
| 8 | **J7 的模块状态**（闸 2 的 U7） | 未核 | 现场 |
| 9 | **LOS 的用法**：接电平还是接沿计数（模块热插拔/掉线历史） | 设计建议 = 两者都接（1 字装得下） | 设计 |
| 10 | **口间隔离语义**：两口是否要"独立 16 连接池"（S2 共享 16 槽 ⇒ 每口最多 8；`WIN_POOL` 分池 = 建连前写 `0x0C` 的现成机制） | 未定 | **用户** |
| 11 | **对端同 IP 双播边界**：若对端两口同 IP（或中间是交换机）⇒ 学习绑定表退化为"最后学会者"（已在 §2-S2 登记为已知限制） | 登记 | —— |

---

## 8. 派单描述逐条核对（**含不符处**）

| # | 派单原话 | 现读结果 | 判定 |
|---|---|---|---|
| 1 | "现役设计只用了一个光口（前端 = 官方 PCS ch1 = X0Y5 = J8，对端只连 J8）" | 全部成立（`wrapper_p4.v:299-301,447-451`；`P7B_GATE2.md:28-29`） | ✅ 相符 |
| 2 | "SFP A=J7=ch0：TX `AA5/AA4`、RX `Y2/Y1`；SFP B=J8=ch1：TX `W5/W4`、RX `V2/V1`" | `wrapper_p4.v:173-180` 端口注释 + 仓根 `CLAUDE.md` 一致 | ✅ 相符 |
| 3 | "Y2 156.25 MHz 供 quad 225 REFCLK0（两通道共用）" | 相符（`ku5p_p7b_gt.xdc:27-32`；两子核 `TX_REFCLK_SOURCE = X0Y4 clk0 / X0Y5 clk0`） | ✅ 相符 |
| 4 | "SFP 控制脚实测映射 SFP1_TX_DIS=C11 / SFP1_RX_LOS=B11 / SFP2_TX_DIS=D9 / SFP2_RX_LOS=C9" | 相符（`ku5p_p7b_gt.xdc:35-38`） | ✅ 相符 |
| 5 | "闸 1：2 通道官方 PCS + 板内 J7↔J8 自环 6.6 s / 30,056,095 帧零错 / 9,999.94 Mbps" | 相符（`P7B_GATE1.md:27-31`；窗内数字逐字一致） | ✅ 相符 |
| 6 | "**`rtl/mac_rx_10g.v`/`mac_tx_10g.v`**" 在 `rtl/` | ⛔ **不符**：两个 10G MAC 在 **`_proj_10g/p7b_mac/rtl/`**（`build_p7b_ku5p.tcl:28,112`）；`rtl/` 里的同名近亲是 **1G 版** `mac_rx_64.v`/`mac_tx_64.v`。引用时别拿错世代 | ⛔ 订正 |
| 7 | "`board/build_p7b_ku5p.tcl`（core 配置 = 单通道还是双通道？现读确认）" | **双通道**（`NUM_OF_CORES=2` / `LANE1=X0Y4` / `LANE2=X0Y5`，`:48-59`），且生成产物 `ip_0`/`ip_1` 逐核回读 `X0Y4`/`X0Y5`、各 10.3125 Gbps/QPLL0 | ✅（并给出结论 1） |
| 8 | "0x28 placed = 77,631 LUT / 75,086 FF / 348 BRAM / 1 URAM / 4 DSP / 6 GTYE4" | 逐字相符（`p9_build_0x28/REPORT.md:100`） | ✅ 相符 |
| 9 | "全局 WNS +0.065 = 周期 1.02%，宿主 = 快照阵列异步复位族" | 逐字相符（`REPORT.md:93,121-122`） | ✅ 相符 |
| 10 | "URAM 余 63；GT 通道余 10（16-6）" | 相符（URAM 1/64、GTYE4 6/16） | ✅ 相符 |
| 11 | "对端 `enp1s0f1np1`（SFC9120 = 双口 10G 卡？现读）" | ✅ **确实是双口**（`01:00.0/01:00.1` → `enp1s0f0np0`/`enp1s0f1np1`），两口当前 DOWN/NO-CARRIER | ✅ 已核 |
| 12 | "历史件 `P7B_LOOP_HANDOFF.md`（接线：唯一连线 J8↔enp1s0f1np1）" | 相符（`P7B_GATE2.md:97`；HANDOFF §6-A） | ✅ 相符 |
| 13 | 派单未提、但**必须登记**的一处：**"GUI 重编 vivado_prj = 永久禁发"**（仓根 `CLAUDE.md` / `P7B_LOOP_HANDOFF.md` §6-B-7 仍在写） | ⛔ **该警告所指的具体状态已变**：`vivado_prj/p7b_ku5p_prj.srcs/sources_1/imports/board/wrapper_p4.v` 与 `board/wrapper_p4.v` 现**逐字节相同**（sha256 `3b39c85f509c09b0ce5ffb31014034f34d976f36bd1a2954b504c6e323dd68a2`，均 0x28 代、`ack_seen` 9 处），**不再是**"BID 0xA / 0 处 `ack_seen`"的旧版 | ⛔ 订正（纪律保留、陷阱描述过时） |
| 14 | 派单说"对端只读探查允许…若不可达则按已知事实登记" | 对端**可达**，已做只读探查（§1.3）；⚠️ `/dev/xdma0_user` 需 sudo（无免密）⇒ **板 BID 未核**，按文档登记 `0x28` | 如实登记 |

---

## 附录 A —— 证据索引（本件引用的关键位置，全部 2026-10-17 现读）

**源码**
- `board/wrapper_p4.v`：`:166-185` P7B 端口表 · `:299-310` 通道选择与核说明 · `:395` `pcs64 u_pcs` · `:401-446` ch0 端口 · `:447-492` ch1 端口 · `:556-573` ch0 常量 IDLE（dont_touch + 三行曾被误删的教训）· `:598` `rx_core_clk_0` 自环 · `:605-615` 两域 MAC 复位 · `:665-669` `gmii_clk`/`tx_fe_clk` 别名 · `:819-855` `mac_rx_10g u_mac_rx` · `:897` `u_rxcdc(76)` · `:940` `vlan_strip` · `:963` `rx_classify` · `:1345-1347` app 寄存器总线静止 · `:1981` `tcp_cam u_cam` · `:2185` `tcp_tx_frame` · `:2473/2497/2519` 慢路径三件 · `:2652` `udp_tx_cfg` · `:2723/2774` 两级 `tx_arb` · `:2800` `u_txcdc(73)` · `:2826` `mac_tx_10g` · `:3296` `SNAP_NW_P6E = 75` · `:3555-3570` ch0 签名 · `:3647-3663` W39/W40 位域 · `:4162-4200` `snap_dout_all` 装配 · `:4355-4371` SFP TX_DIS 门 · `:4377` `BUILD_ID_V` · `:4858` `axi_regs .SNAP_NW`
- `rtl/rx_classify.v:26-66,70-94`（单入口、`fw=76`）· `rtl/tcp_cam.v:9-33`（4 元组键）· `rtl/tcb.v:8-75` · `rtl/udp_tx_cfg.v:62-102`（单 peer）· `rtl/app_ctrl.v:28-33`（事件字）/`:37-64`（寄存器映射）· `rtl/retx_ram.v:119-135`（256 tile）· `rtl/tx_arb.v` 全文（53 行，帧级 2:1 先例）· `rtl/mac_rx_64.v`/`mac_tx_64.v`（1G 版）
- `_proj_10g/p7b_mac/rtl/mac_rx_10g.v:72-` 端口 · `mac_tx_10g.v:35-68` 端口

**约束/构建**
- `board/ku5p_p7b_gt.xdc:22-51` · `board/ku5p_p7b_cdc.xdc:36-39` · `board/build_p7b_ku5p.tcl:41-80`（IP 配置）、`:111-112`（MAC 导入）、`:266-286`（约束/宏）、`:294-327`（synth/impl/报告）

**构建产物（0x28）**
- `_proj_10g/notes/p9_build_0x28/REPORT.md:93,100,103,112-129,178-190` · `board_rpt/wrapper_p4_{utilization_placed,power_routed,clock_utilization_routed}.rpt`
- `vivado_prj/p7b_ku5p_prj.gen/sources_1/ip/pcs64/{ip_0/pcs64_gt.xci, ip_1/pcs64_gt_1.xci}`
- `_proj_10g/p7b_mac_synth/mac_only/mac_{rx,tx}_ooc/.../utilization_synth.rpt`

**笔记/历史**
- `_proj_10g/notes/P7B_GATE1.md:25-31,86-91,350,563,592,613` · `P7B_GATE2.md:28-29,94-97,396` · `P7B_XXV_OFFICIAL.md:248-296,300-358,574-624` · `agent_docs/P7B_SPEC.md:28-45,79-145,133-145,353-412,775-838` · `_proj_10g/notes/P7B_BRAM_REPORT.md:22-27,94,102-145` · `_proj_10g/notes/P7B_U7_AND_PEER.md:244-294` · `_proj_10g/notes/P7B_LOOP_HANDOFF.md:404-433` · `_proj_10g/notes/P7B_TL_LEDGER_20261010.md` §10-87…§10-92 · `_proj_10g/notes/P7B_CHAIN_COVERAGE.md:1-30` · `sim/p4gates/run_matrix_p4dfix.bat:184-241`（19 门）· `sim/p6e_pcie/run_tb_p6e_pcie{,_counters}.bat`
- 闸 1 施工目录（自环臂配方）：`_proj_10g/xxv_loop/{rtl,tcl,xdc,logs,artifacts}`

**本轮只读实测（对端）**：`tools/peer_ssh.py` 三条命令（`lspci | grep -i -E 'sfc|ethernet'` / `ip -br link` / `lspci -d 10ee:` + `ls /dev/xdma*` + `sudo -n true`），2026-10-17 执行，无 sudo、无写入。

---

*本件 = 设计研究件（纯纸面）。不含 PASS/FAIL 裁定；所有"达标/不达标"的判定留待用户与后续实测。*
