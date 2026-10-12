# 模块划分

> **本文档给谁看**：想知道"这个系统由哪些部分组成、每部分干什么、干得怎么样"的人。
> 每个模块按固定五格写：**是什么 / 功能 / 接口 / 关键指标 / 已知缺陷**。
> 没核实到的项一律写"暂无实测数据"，绝不编造；每条关键事实后标出处。
> 名词解释见 [glossary.md](glossary.md)；时间线见 [progress.md](progress.md)。

**系统一句话**：一块 XCKU5P FPGA 开发板，对内实现完整的硬件 TCP/IP 协议栈数据面，
两个前端——1G 电口（RGMII）与 10G 光口（XGMII，经官方物理层 IP）——共用同一套 64 位数据面；
板子经 PCIe 插槽与 PC 相连，PC 通过寄存器窗口观测板内状态、读取镜像数据（源：根 README.md 标题块；
`_proj_10g/notes/P7B_DATAPATH_CONTRACT.md` §0）。

---

## 1. 顶层与板级基础设施

- **是什么**：`board/wrapper_p4.v` 是顶层模块，把所有模块装配起来；同一源码用宏区分构建配置
  （`APP_MODE` = 应用接口模式、`PCIE_OBS` = 观测面、`DP_156MHZ` = 数据面 156.25 MHz、`P7B_10G` = 10G 前端）。
- **功能**：时钟生成（100 MHz 输入 → MMCM）、复位、两个前端的选择与切换、PCIe 观测面装配、构建编号（BID）登记。
- **接口**：SFP+ 光口 ×2、RGMII 电口、PCIe x4、100 MHz 晶振。
- **关键指标**：现役快照窗口 71 字（W0..W70），未实现地址 `0x14C`；位流固定 15,431,261 B，版本只能靠
  sha256 与 BID 区分（源：`_proj_10g/notes/P7B_BIZ_WINDOW.md`；台账 §10-17/§10-18）。
- **已知缺陷**：`TX_CONTINUOUS=1` 连续模式下换流门只在帧间隙成立 ⇒ 多连接长跑对端会看到图案的另一段
  （"相位错"新形态，已登记不修）（源：`_proj_10g/notes/P7B_OPEN_ITEMS.md` §0 第 32 行）。

## 2. 10G 物理层（PCS/PMA）与自写 64 位 XGMII MAC

- **是什么**：官方 AMD `xxv_ethernet` IP（配置为 `Ethernet PCS/PMA 64-bit`，输出 64 位 XGMII 并行总线）+
  我们自己写的 64 位 MAC（`mac_rx_10g` / `mac_tx_10g` / `crc32_64`，位于 `_proj_10g/p7b_mac/rtl/`）。
- **功能**：把光口进来的串行 10.3125 Gbit/s 码流转成每拍 8 字节的帧流（接收方向），以及反向组帧发出去；
  完成前导/SFD 处理、FCS 校验/生成、pad 补齐。
- **接口**：对上是 XGMII（万兆以太网 64 位并行总线标准）；对下游数据面输出与 1G 版完全相同的
  64 位 AXIS 帧流合同（AXI-Stream：一拍拍传数据、带 valid/ready 握手的行业标准流接口），
  即 `tdata[63:0]+tkeep[7:0]+tvalid/tready/tlast/tuser/terr/tcrs`，因此下游零改动
  （源：`_proj_10g/notes/P7B_DATAPATH_CONTRACT.md` §0；`agent_docs/P7B_SPEC.md` §0）。
- **关键指标**：1 字/拍真流水；L=1514 帧 193 拍/帧 = 99.6% 效率（源：`_proj_10g/notes/P7B_MAC_DESIGN.md` §0）；
  单元测试 391 条判据 0 失败（lane4 修复后口径，源：根 README.md「10G 门」节）；
  与 PCS 合并 WNS +0.401 / 三类失败端点全 0（合并当时口径，源：根 README.md「已完成」表）。
- **已知缺陷**：历史上修过两个真缺陷——① 需补 pad 的短帧 FCS 只覆盖数据不含 pad（已修，判据 337/0）；② `/S/` 落
  lane4 的帧 SOP 字非满对齐（已修并板级复证 20/20 + 2999 帧逐字节）（源：根 README.md「新 MAC 修掉的一个真缺陷」节与
  「已完成」表）。厂商 example 的 FCS 缺陷未修（不要照抄那个例程）（源：根 README.md「分层裁决」节）。

## 3. 1G 前端（RGMII MAC）

- **是什么**：`rtl/mac_rx_64.v` / `rtl/mac_tx_64.v`，1G 电口的字节串行 GMII 模块。
- **功能**：GMII 字节流 ⇄ 64 位左对齐字流，FCS 校验/剥离（CRC 残留常量 `0xDEBB20E3`）、统计计数。
- **接口**：GMII（125 MHz）；对下游数据面同样是 64 位 AXIS 帧流（源：`_proj_10g/notes/P7B_DATAPATH_CONTRACT.md` §A.1）。
- **关键指标**：1G 数据面已在 156.25 MHz 域完成板级正式验收 35/35 判据、956.0 Mbps（P6b）
  （源：`agent_docs/P6B_SUMMARY.md`）。
- **已知缺陷**：F-3（MMCM 失锁/重锁 ⇒ 数据面侧在帧中重启 ⇒ 丢/重一帧，三种接线实测都无解，潜伏未修）；
  F-1 的板级缺口（`ovf_pulse/ovf_cnt` 未接进快照）（源：根 README.md「进行中 / 未完成」节）。

## 4. 接收分类与流分发（RX classify / split / strip）

- **是什么**：`rtl/rx_classify.v`（把进来的帧分类成 TCP 快路径 / UDP 应用 / 慢路径）、`rtl/udp_split.v`（UDP 帧整帧缓冲与分流）、
  `rtl/vlan_strip.v`（802.1Q 标签剥离）。
- **功能**：逐帧路由 + 坏帧整帧丢弃（永不把半帧交给下游）；VLAN 单标签剥离后下游零改动。
- **接口**：64 位 AXIS 帧流进、按路由结果分流到 TCP 快路径 / UDP app / HLS 慢路径适配器。
- **关键指标**：v2 改造后最小帧帧周期 14→8 拍，10G 最小帧从 57.1% 提到 100% 通道能力；
  保真验证 v1/v2 逐拍逐位 6224 beat × 7 场景 0 失配（源：`_proj_10g/notes/P7B_RXCLASSIFY_DESIGN.md` §0）。
- **已知缺陷**：暂无新登记（历史上的吞吐天花板已由 v2 修复）。

## 5. TCP 快路径（数据面核心）

- **是什么**：纯 RTL、每级 II=1（每时钟周期处理一个字）的处理链：
  `tcp_rx`（接收段解析）→ `tcp_cam`（四元组匹配，16 连接）→ `tcb`（每连接传输控制块）→
  `tcp_echo`（回显管道，`frame_fifo` 8192 字）→ `tcp_tx_frame`（组帧发送）。
- **功能**：TCP 数据段的接收、校验、窗口管理、确认处理；回显式转发；发送侧组帧与重传调度。
- **接口**：64 位 AXIS 帧流；HLS 慢路径负责握手（SYN/FIN/RST），快路径只跑数据段。
- **关键指标**：实测流水里 BRAM 贡献 0 拍（必经 BRAM 只有 5 块小件 ≈ 20 tile）；
  快路径本身（非 app 演示）上行能力 2026-10-06 已实测到 8.4 Gbps（源：`_proj_10g/notes/P7B_BRAM_REPORT.md` §2；
  根 README.md「P7b-BIZ Stage 2」行）。
- **已知缺陷**：
  - 窗口"通告"通路曾有的结构性弱点（板从不主动通告窗口重开 ⇒ TCP 上行被压到 4.7 Mbps）——
    **已修复并经板级两臂 A/B 坐实**（行为层已证实 / 判据层待复跑，不许写成 PASS）
    （源：`_proj_10g/notes/P7B_WU_MILESTONE.md` §1）。
  - 发送侧零窗口探询（persist）机制曾缺失（微窗 stall 的根因）——**已实现 + 构建 0x1D + 板级 A/B 正结果**
    （源：`_proj_10g/notes/P7B_OPEN_ITEMS.md` §0 第 29 行）。
  - 窗口写入守卫（`snd_wnd` 无守卫 ⇒ 陈旧/乱序 ACK 的窗口字段会覆盖当前窗口）——**已实现 + 构建 0x1E +
    板级双证**（源：`_proj_10g/notes/P7B_OPEN_ITEMS.md` §0 第 30 行）。
  - 重放越界缺陷（重放路径可能把"上一圈"字节发出）——**已修复（0x1C）；板级触发条件结构性缺席，
    按"未观测到"收口**；残留 R1–R5 登记不修（源：`_proj_10g/notes/P7B_OPEN_ITEMS.md` §0 第 28 行）。

## 6. 重传子系统

- **是什么**：`rtl/retx_ram.v`（每连接 64 KB 重传环，16 连接共 256 tile BRAM）+ `tcp_tx_frame` 里的
  3×dup-ACK 快速重传（整段回卷重放）+ RTO 兜底扫描器。
- **功能**：丢包自愈——收到 3 个重复 ACK 就回卷重放 `[snd_una, snd_nxt]`；RTO 超时兜底。
- **接口**：TX 路径旁写（首发时与载荷同拍旁写），重传会话时读。
- **关键指标**：读延迟 2 拍流水；`W55` 已定案（一次回卷 = 重放整段，平均 4.6–5.0 段；
  触发源 = dup-ACK，RTO 被直接读数排除）（源：根 README.md「P7b-BIZ Stage 2」行）。
- **已知缺陷**：`retx_ram` 是全设计唯一够格迁 URAM 的块（348→92 tile，代价 29–32/64 URAM + 读流水 2→3 级），
  综合器自己试过并拒绝过简单改法；**非阻断项**（既不是时序也不是延迟瓶颈）
  （源：`_proj_10g/notes/P7B_BRAM_REPORT.md` §0/§3）。

## 7. 慢路径协议栈（HLS 综合的协议处理 IP）

- **是什么**：`hls/src/` 下用 C++ 编写、经 Vitis HLS 综合成 RTL 的协议栈：ARP / ICMP / IGMP / DHCP /
  UDP echo(8080) / TCP 握手（被动打开 + 主动 connect）/ UDP HELLO 周期发行文；入口适配 `rtl/slow_rx_adp.v`、
  出口 `rtl/slow_tx_adp.v`、配置下发 `rtl/slow_cfg_adp.v`（源：根 README.md「慢路径」节；`hls/src/` 目录）。
- **功能**：一切不进快路径的包（ARP 应答、ping、组播、握手、DHCP）都在这里处理；
  看门狗（饥饿超时复位脉冲）防 HLS 死锁。
- **接口**：64 位字 ⇄ 9 位字节、1 字节/拍（封顶 ≈1.25 Gbps，是慢路径既有上限）；配置通道（wscale/窗口）→ CAM/TCB。
- **关键指标**：协议功能全景（P4c 收官）= ARP 应答 / ICMP echo / IGMP / UDP 收+回显+主动发送 / DHCP / TCP 握手 +
  数据 echo（源：根 README.md「协议功能全景」节）。
- **已知缺陷**：慢路径曾被怀疑"会被永续数据源饿死"——**已被板级实测证伪**（泛洪持续 300 s 时 ping 5/5 通、
  建连成功）；慢路径 aging 里程碑因此取消（源：根 README.md「P7b-LONGSEND」段第③条）。

## 8. UDP 应用发送链

- **是什么**：`rtl/udp_tx_cfg.v`（learn-on-RX 对端表）→ `rtl/udp_tx_frame.v`（组帧 + 长度守卫 ≤1500）→
  两级仲裁（TCP 快路径 > UDP app > HLS）；演示 app `rtl/app_udp_pattern.v`。
- **功能**：板上应用主动发 UDP 帧；默认不激活（配置全哨兵 ⇒ 零新增帧）。
- **接口**：64 位 AXIS；控制面经 `app_ctrl` 寄存器。
- **关键指标**：2026-09-30 线速达标的关键改造之一——组帧乒乓重叠（`UDP_TX_OVL` 宏）把组帧器从 378 拍/帧压到 191 拍/帧
  （源：根 README.md「P7b-线速（RATE）」行）。
- **已知缺陷**：TX 字 FIFO 写门一拍错位（每帧静默丢 8 B）——**已修复并经 Stage 2 的 `J0` 板级坐实**
  （源：根 README.md「P7b-BIZ」行）。

## 9. 应用接口层（APP_MODE）

- **是什么**：`rtl/app_ctrl.v`（寄存器面：连接事件、close/abort、状态计数）、`rtl/app_pattern.v`（TCP 演示 app，
  含 RX 8 路并行与 TX_CONTINUOUS 连续模式）、`rtl/app_status_uart.v`（UART 状态行）。
- **功能**：应用经 AXIS 流收发 TCP 载荷（一帧 = 一个 TCP 段 ≤1460 B）、经寄存器面拿连接事件与控制；
  应用接收流控闭环（每连接信用配额 + 单调右沿 + `wu` ACK 主动重开 + 接受裕度）。
- **接口**：AXIS 流 + 寄存器面（`app_reg_*`，**当前板级静态钉死**，注释"将来接 AXI-Lite 桥"）。
- **关键指标**：演示 app 结构天花板 = 1.111 Gbps（RX 校验器实测撞墙 99.977–99.987%）——
  这是**演示 app** 的天花板，不是快路径的（快路径实测 8.4 Gbps）（源：`_proj_10g/notes/P7B_WU_MILESTONE.md` §1.4）。
- **已知缺陷**：连续模式相位错（见 §1）；app 口 8 字节/拍持续吐字时镜像采集曾恒丢 50%（见 §11，已修）。

## 10. PCIe 观测面（P6e / XDMA）

- **是什么**：AMD XDMA IP + `_proj_pcie/rtl/axi_regs.v`（user BAR 寄存器窗口）+ `rtl/snap_cdc.v` / `rtl/snap_seq.v`
  （跨域快照序列器）。**本板无 UART，这是唯一的板上观测手段**（源：根 README.md「板级诊断接口」节）。
- **功能**：PC 经 PCIe 读写 71 个 32 位快照字（计数器、窗口、状态）+ 控制寄存器（TX_DIS 门、镜像控制等）。
- **接口**：PCIe x4；user BAR（`reg_rw /dev/xdma0_user`）。
- **关键指标**：快照窗口从 36 字逐步扩到 71 字（W70 = 镜像丢弃字节）；扩字成本 ≈96 FF/字（三份同步）
  （源：`agent_docs/P6E_OBS.md`；`_proj_10g/notes/P7B_BIZ_WINDOW.md`；根 README.md「板级诊断接口」节订正块）。
- **已知缺陷**：读数自证要求"每次测量前必重烧 + 核 sha256 ↔ 板侧 BID"；`0x08` 既是 SCRATCH 又是 TX_DIS 门
  （受控停流恢复配方 = 写 `0x08 = 0`）（源：根 README.md「进行中」节）。

## 11. P8/P9 镜像与 DMA 数据通路（SFP+ → 协议栈 → PCIe → PC）

- **是什么**：`rtl/app_rx_mirror.v`（"载荷镜像窗"小功能：旁路采集应用载荷 → 异或 0xA5 → 打包）、
  `rtl/mir_dma_ring.v`（16 KB 环）、`rtl/aximm_c2h_win.v`（只读 AXI-MM 从机）、`rtl/aximm_h2c_discard.v`
  （"永远应答并丢弃"写从机）、`rtl/axis_c2h_stream.v`（AXIS 流出口）；PC 侧工具 `_proj_pcie/p7b_biz/p7b_mir_dump.cpp`。
- **功能**：把板上应用收到的载荷镜像一份，经 PCIe 送到 PC 落盘并逐字节对账——
  用户要求的"逻辑简单但功能齐备、打通所有环节的小功能"。两条路径：user BAR 窗口（阶段一，约 4–10 MB/s 量级估算）与
  DMA 直读（估算 ≈1.7 GB/s，均未线速实测）（源：`_proj_10g/notes/P7B_PCIE_DATAPATH_DESIGN.md`，台账 §10-5）。
- **接口**：`app_rx_*` / `app_udp_rx_*` 旁路口（`MIR_CTRL[2] src_sel` 选 UDP/TCP）；C2H AXIS（P9 后）或 MM（P8）。
- **关键指标**：板级已验——UDP/TCP 两源 × 相位 0/≠0 逐字节零失配；字节序假设板级判决成立；
  H2C 首次激励三档无 hang（源：台账 §10-26）。
- **已知缺陷**：线速档未测（本轮只到 2.5 MB/s）；板上缓冲未加（用户裁定届时用 URAM）；
  历史"91.9% 丢失"已归因到读侧/突发容量（台架面），非板缺陷（源：台账 §10-26-3/§10-22-3）。

## 12. 跨域与公共件

- `rtl/fifo_async.v`（手写异步 FIFO——先进先出队列，灰码指针 + 两级同步）、`rtl/fifo_sync.v`、`rtl/clk_gen_p6b.v`（MMCM 156.25 MHz）、
  `rtl/checksum16.v` / `rtl/crc32_8b.v`。
- 已知缺陷：F-3（见 §3）；`fifo_async` 的 F-1 修复已落（`ovf_pulse/ovf_cnt`），板级缺口是未接进快照。

## 13. 测试与验证体系

- **是什么**：约 17 个常驻仿真检查（本项目称"测试门"：一跑给出通过/失败判决的自检脚本，
  入口 `sim/p4gates/run_matrix_p4dfix.bat`）+ 各模块单元测试 + 变异测试（故意改坏代码验证检查能抓到）+
  板级工具链（`tools/`、`_proj_pcie/p7b_biz/`）。
- **关键指标**：常驻矩阵 17/17 通过 + 冻结校验（最近三代位流 0x1C/0x1D/0x1E 均 17/17）；
  10G MAC 单元测试 391 判据 0 失败；真 wrapper 全链门 106 判据 0 失败；
  全仓回归 136 门 = 112 通过 + 既存/偶发若干（源：根 README.md「怎么跑」「10G 门」节；
  台账 §10-5-2）。
- **已知缺陷**：矩阵 manifest 覆盖面有结构性盲区（某些改动不在任何清单里 ⇒ "矩阵全绿"不等于"被验过"，
  全仓唯一一条"编它 + 开宏 + 真驱动"的 RX8 门曾未登记，已登记为第 17 门但仍有宏面残留）；
  8 条形同虚设的检查（脚本自身不置失败码）已单列、其中 1 条掩盖了一个既存编译失败；
  `p5c_rev_elab` 那类"假通过"已修 3 条（源：根 README.md「进行中」节；`_proj_10g/notes/P7B_REGRESSION.md` §5；
  `_proj_10g/notes/P7B_STAGEA_MILESTONE.md` §1.3 教训 1）。

---

## 附：未单独成章的部分

- **厂商参考设计 / 官方 example**：仅作对照与取证，不作为实现基础（P7B 非目标 N10）。
- **`_proj_mdio`**：MDIO 主机（PHY 管理接口），两潜伏项 RTL 已修、未重建位流（低优）
  （源：`_proj_10g/notes/P7B_OPEN_ITEMS.md` §0 第 18 行）。
- **性能测量台架**（对端机上的 sink/source 工具）：属工具而非 RTL 模块；其缺陷曾造成镜像侧"丢失"
  假象（`SO_RCVBUF` 设置时机），已修（源：台账 §7-1；`_proj_10g/notes/P7B_OPEN_ITEMS.md` §0 第 31 行）。
