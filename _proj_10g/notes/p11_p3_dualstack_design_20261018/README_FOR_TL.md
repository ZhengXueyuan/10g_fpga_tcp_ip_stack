# P11 · P3「甲·双栈」设计 v1 —— 共享 8 连接缓存 + 2×10G

- 日期：2026-10-18 · 角色 = **纯设计轮**：未改任何 RTL/HLS/脚本/工具，未跑 xsim/Vivado，未构建，未碰板/对端/烧录，未写 git。
- 仓库根 = `D:\repo\XCKU5PMini\udp_hls_10g`；HEAD = `87a04937`。工作树现读 = **0x2D 构建**（`BUILD_ID_V = 32'h0000002D`；快照 **NW 85**（W0..W84）/ 未实现地址 **`0x184`**；W85..W87 已按 backstop-2 删除；构建读数 **WNS `+0.042` / WHS `+0.009` / 三类失败端点 `0/0/0`**；placed **82,013 LUT / 77,361 FF / 346 BRAM / 1 URAM / 4 DSP / 6 GTYE4**；位流 `ecef15f2…e76f`）。
- 判据层口径：**本件不下 PASS/FAIL 裁定**（裁定权在用户/判据所有者）。「未观测到」≠「不存在」；「不支持」≠「证伪」。
- 状态词：**【已证·源码】【已证·构建】【已证·板级】【推断】【未判定】【未测】【纸面】**。所有面积/时序增量一律标 **纸面**（±20–30% 包络），锚 = S1 成本件 / 0x2D 构建 / 源码。
- 写入面：仅本目录。不改 `P7B_TL_LEDGER_20261010.md`（工作树里它本就有一处未提交改动，**不是本件产生的**）。

---

## 0. 一页结论（先读这个）

| # | 结论 | 等级 |
|---|---|---|
| 1 | **目标 = 甲·双栈（P3）**：两个 SFP+ 同时各 ~10G 线上载荷（聚合 ~19G），**8 条 TCP 连接共用一份缓存/配额**，连接可任意分布（6+2 / 8+0 / 4+4），**不是 4+4 固定分组**。⚠️ **方向口径**：主判据 = **板→对端**（P7b 单口 9.1–9.3G 已证）；**板 RX 每口 10G 未证**（P7b Stage B 的 4.1G 是台架帽、A7 B3 的 6.16G 是板通告窗帽；`tcp_rx` 190 cyc/seg ≈9.6G 是最近结构上限〔RTL 读值〕）⇒ §9.3/§10.2 单列。 | 用户约束（2026-10-18）+【已证·板级】 |
| 2 | **这是对「早先不双栈」的反转**：P2 范围决定 = S2 单栈（`p11_p2a_design_20261018/DESIGN_v2r1.md` §1 逐字「用户已裁：S2 单栈（放弃 2×10G 同时满速）」）；本件按新用户指令改为双栈。P2/0x2D 保留为 **回归配置**，不删。 | 登记 |
| 3 | **C4（P3）架构推荐 = B/C2S**：**两套同模块快路径二次例化** + **单份双 IP HLS** + **新模块 `win_pool_mgr`（单共享 96KB 配额池）** + **每口独立 app_ctrl 只读配额** + **慢路径 2:1 merge / 1:2 demux**。A′（两份 HLS）作为风险对冲。**C1/C2/C3 的架构不变**（见 §2.1）。 | 【推断】+纸面 |
| 4 | **8 连接缓存的语义分解**：①连接控制（TCB/CAM，每口 16 物理槽，系统准入 8）；②RX 窗口信用 + 物理 RX 缓冲；③TX 重传环（每连接 64KB）。②的**信用池 = 单共享 96KB**（新模块）；③**首选单共享 8 槽阵列（128 tile）**，退路 = 每口 8 槽（两套 256 tile，净 0）。 | 【已证·源码】+纸面 |
| 5 | **BDP 算术（必须区分口径）**：聚合 20G × 27µs = **67.5KB** ⇒ 单个 **共享 48KB 池不够**（48,000 B 口径 19.2µs / 49,152 B 口径 19.7µs）；**共享 96KB 覆盖到 38.4µs（96,000 B）/ 39.3µs（0x18000 = 98,304 B）**；**每口 48KB（两条池，共 96KB）在 10G/口下覆盖到 39.3µs**——所以「48KB 不够」只对「单个 48KB 池供两口」成立，**每口 48KB 的 BDP 是够的**；但它是固定 48/48 分区，**不满足用户的共享语义**（6+2/8+0 的跨口借用）。 | 纸面算术 |
| 6 | **配额不可建连后借还**：TCP 窗口不可撤销 ⇒ 配额必须建连前写入；**单共享池 = 单一分配器 + 预配额**，不是动态借还。`app_ctrl` 现有的 C15 **增量补授在共享模式下关闭**（与用户要求同向，不是缺陷）。 | 【已证·源码】+用户约束 |
| 7 | **每连接配额 = 场景常量**：8 连接协议 ⇒ 96KB/8 = **12KB/条**（2.5G/条 @20µs 的 BDP = 6.25KB，余量 1.92×〔12,000 B〕/1.97×〔0x3000 = 12,288 B〕）；2 连接 2×10G ⇒ **48KB/条**（10G @27µs BDP = 33.75KB，余量 1.42×〔48,000 B〕/1.46×〔0xC000 = 49,152 B〕）。配额由 **板级 boot writer** 写 `wq_cap`，HLS 的 SYN-ACK 窗口用**同一常量**（`TCP_ADV_WND`），否则出现「通告 48KB、实配额 12KB」的窗口收缩。 | 【已证·源码】+纸面 |
| 8 | **8+0 分布需要每口物理 RX 缓冲 ≥ 96KB**：0x2D 的 `tcp_echo` `frame_fifo` = **8192 字 = 64KB**；8×12KB = 96KB 放在一口 ⇒ 必须把每口 echo 缓冲升到 **16384 字 = 128KB**（`D=16384/AW=14`，32 BRAM/口，两套 +48 tile vs 0x2D 的 16 tile/口）。这是本件发现的**硬约束**，派单未提；**若不加，8+0 在 12KB/条下不成立**。 | 【已证·源码】+纸面 |
| 9 | **防分叉（新增强制章，§2）**：**四配置 = 互斥构建配置**（C1 单口 / C2 镜像 / C3 共享栈 / C4 双栈）；P3 只管 **C4**；每个构建恰选一个 C；`C2 ∧ DUAL_SFP_A`、`C2 ∧ P11_DUAL`、`P11_DUAL ∧ SFP2_MODE_B` 等 = **elaboration 硬失败**；第二套快路径 = **同模块二次例化**（禁复制/派生模块文件）；共享模块改动**默认关 + C3(0x2D) 行为回归**；共享池 = **新模块**；模式宏只在 `board/`；每配置独立 BID。 | 设计纪律 |
| 10 | **单仓四配置**：`rtl/`+`hls/` = 模式无关 stack；`board/` 按 **`cfg_single`(C1)/`cfg_mirror`(C2)/`cfg_shared`(C3)/`cfg_dual`(C4)** 分薄顶层 + 共享 `board/common` 前端；**禁止四份顶层复制**。**拆仓结论：自然切口 = 2 仓（stack / board-product），不是 3 仓**；当前接口未稳定（P3 还要改 `app_ctrl`/`retx_ram`/`tcp_tx_frame`/HLS/共享池），**现在不满足拆仓触发条件**。 | 设计纪律 |
| 11 | **资源（纸面，基线 C3=0x2D 82,013 LUT / 77,361 FF / 346 BRAM）**：B/C2S（共享 retx + 128KB echo）≈ **+27–30k LUT / +16–19k FF**（C4 vs C3；MAC/CDC/arb 已在 C3，**不计入**）；BRAM ≈ **267**（共享 retx）/ **395**（每口 retx）；URAM 1；DSP 4。A′（两份 HLS）+37 BRAM / +≈20k LUT（相对 B/C2S）。**全部可行**（LUT ≤ ~52%，BRAM ≤ 83%）。 | 纸面 |
| 12 | **时序无法给可信预测**：0x2D 余量 **0.66%**（`+0.042/6.4`），当前 DP 最差族 = `u_tcp_tx/u_fifo_b → u_tcb` 与 `u_app_ctrl/o_ev_up → orph_cnt/pw_*`；双栈在同一 `dp_clk` 域再放 ~30k LUT，这两族各出现第二份；**只能一次构建收口 + 预登记 backstop**。不写「WNS 会降 X ns」。 | 【已证·构建】+推断 |
| 13 | **观测推荐：首版不加新字**（NW 保持 85 / UNIMPL `0x184`）。0x2D 的 backstop 史证明「加一个快照字可以把 WNS 从 +0.042 打到负」；W83/W84（每口 TX 帧）+ W0/W79（每口 RX 帧）+ W4/W82（每口 MAC drop）已够 2×10G 的功能判据；池占用在 xsim 用 `app_ctrl`/`win_pool_mgr` 寄存器读，板上用吞吐/零窗行为判。可选 W85 = 每口已授配额和（另开构建，预登记 backstop）。 | 【已证·构建】+推断 |
| 14 | **最大三个风险**：① 时序（0.66% + 同域 +30k LUT + 共享 retx/配额 mux）；② 共享池迫使 `app_ctrl` 加 `EXT_QUOTA` 模式（红队可能判为语义分叉 ⇒ 退 M3 每口 48KB，**如实标注偏离**）；③ 对端 2×9.5G 同时接收 + 演示 app 单会话（P2 B-4A 已证双口同时 TCP 数据**结构性不可做**）——P3 必须同时交 **双 app 实例/多连接 app**，否则板级只能证明「连接准入」，不能证明 2×10G TCP 数据。 | 【推断】+【已证·板级】 |

---

## 0.1 与派单/既有陈述的核对（**核到不符就如实说，不迁就**）

| # | 派单/既有描述 | 本轮现读 | 判定 |
|---|---|---|---|
| 1 | 0x2D 现状：NW 85，W85..W87 已删，HLS 双 IP 已实现 | `board/wrapper_p4.v` `SNAP_NW_P6E=85` / `SNAP_P7BDP_NW=41` / `BUILD_ID_V=32'h0000002D`；E-6.1 与 P2 板级 README §1.2 逐字 | ✅ 相符 |
| 2 | 0x2D 构建 WNS +0.042 / 0/0/0 | `p11_build_0x2D_20261018/retry/README_FOR_TL.md` §5 逐字（WHS +0.009） | ✅ 相符（WHS 是 +0.009，不是 +0.010） |
| 3 | 0x2D placed 资源 | 同上：**82,013 LUT / 77,361 FF / 346 BRAM / 1 URAM / 4 DSP / 6 GTYE4**。四配置锚：**C1 = 0x2A**（78,248/75,360/348，WNS +0.039/+0.010/0/0/0）、**C3 = 0x2D**（上述）；S1 件的 0x2A/0x2B（80,024/76,888/348）按各自锚读，**不作为 C4 的增量基线** | ⚠️ **C4 基线 = C3 0x2D**；C1 单独列；S1 绝对值按历史读 |
| 4 | S1：B/C2 = +32–34k LUT / +19–20k FF / +19 BRAM / 367 tile | S1 的「第二套快路径」表**包含第二套 `slow_rx_adp`/`slow_tx_adp`（861/352/1、884/384/1）**；但 B/C2 是**单份 HLS**，慢路径 RX/TX 适配器只需**一套**（前面加 slow merge / 后面加 slow demux），**第二套 `slow_cfg_adp` 才需要**（每口一套 CAM/TCB）。⇒ S1 的 B/C2 增量**高估 ~1.7k LUT / ~0.7k FF / 2 BRAM**；修正后 **≈ +30–32k LUT / +18–19k FF / +365 tile（每口 retx）**。 | ⛔ **需限定**，本件按修正值 |
| 5 | 派单：「甲·单栈（P2/0x2D）……8 连接共用一个池」 | 现树 0x2D 的 HLS **`MAX_TCP_CONN=3`**（`hls/src/layer_tcp.cpp:10-12`），快路径 TCB/CAM 是 16 物理槽，但 HLS 只建最多 3 条；0x2D 板级 B-2c 实测「每口 1 条同时建连」= 2 条。**「8 连接」是 P3 甲·双栈的准入，不是 0x2D 的现状**。 | ⛔ **不符，如实列** |
| 6 | 派单：`MAX_TCP_CONN=3` 是硬限 | 现读 `layer_tcp.cpp:10-12` `#define MAX_TCP_CONN 3`；`tcp_find`（`:143-151`）/ `tcp_conn[3]` / `tcp_retrans_buf[3][576]` / `tcp_send_bufs[3][576]` 全按 3。P3 改 8 是**HLS 源码改动 + 重综合**，不是宏开关。 | ✅ 相符（P3 要改） |
| 7 | 派单：`rx_merge2`/`tx_demux2` 在双栈下退役 | **快速路径的 merge/demux 退役**（每口自己的 MAC→classify→tcp_rx）；但**单份 HLS 仍需要**：① **慢路径 2:1 merge**（两口的 `rx_classify` slow 输出 → 一个 `slow_rx_adp`→HLS）；② **HLS TX 1:2 demux**（`slow_tx_adp` 的源 IP 提取 → 两口 arb）；③ **cfg 1:2 demux**（HLS 的 8 词记录按 `local_ip`/slot 路由到两套 `slow_cfg_adp`）。⇒ **不是「全部退役」**，是「快路径退役、慢路径保留三个窄件」。 | ⛔ **需限定，如实列** |
| 8 | 派单：8 连接共用一个池；96KB/128KB 跨口分配器 | BDP 算术见 §4.2：**「48KB ⇒ 19.2µs」是单个 48KB 池供聚合 20G 的口径；每口 48KB 在 10G/口下是 39.3µs**。两点都真，但**不能混用**。本件按「单共享 96KB + 每口 128KB 物理缓冲」推荐。 | 口径订正 |
| 9 | 派单：每连接配额 12KB/条 @96KB，2.5G/条 @20µs BDP 6.25KB 余量 | 算术正确：12,288 / 6,250 = **1.97×**（按 20µs）；按实测 srtt 16–27µs，BDP 5.0–8.44KB ⇒ 余量 **1.46–2.46×**。 | ✅ 相符 |
| 10 | 派单：每口 TCB/CAM 16 槽（物理），系统准入 8 条 | `rtl/tcb.v` N=16、`rtl/tcp_cam.v` N=16；HLS 改 8 后，w0.slot = 0..7；每口只有 0..7 被写，8..15 未用。**需加 slot<8 守卫**（否则 retx 8 槽会别名）。 | ✅ 相符 + 新增守卫 |
| 11 | P2 板级 B-4A：两端口同时 TCP 下行**结构性不可做** | 原因 = **演示 app 的 TCP TX 是单会话**（Stage C 已登记）；不是栈的限制。P3 的 2×10G TCP 数据必须配**双 app 实例/多连接 app**，否则板级只能做连接准入 + 单口数据。 | ✅ 相符（必须纳入 P3 范围） |
| 12 | P2 板级 B-2：池归还见证 `win=49152` / HLS `ip.id=0` | 逐字相符（`p11_board_p2_0x2D_20261018/README_FOR_TL.md` §3.3）。P3 的共享池在板上**没有** app 寄存器总线（`wrapper_p4.v:1547-1549` 静态钉死）⇒ 配额必须 **boot writer/编译常量** 写入，不能靠 host。 | ✅ 相符 + 新发现 |
| 13 | 0x2D 观测面 = W83/W84 每口 TX 帧 | `p7bdp_din[39*32 +: 32] = w83_dp` / `[40*32 +: 32] = w84_dp`（wrapper `:4842-4843`）；W0/W79/W4/W82 是每口 RX 帧/drop（`SNAP_CH0_NW=4`，W79..W82）。 | ✅ 相符 |
| 14 | 0x2D 的 `W79` 语义 | P2 E-6.2/N-14：**W79 = 被 merge 输入 FIFO 接受的好帧数**；P3 双栈没有 merge ⇒ W79 应重定义为 **port1（ch0）MAC RX 好帧数**，与 W0（port0）对称。读侧标签必须同步。 | ⚠️ **语义变更，登记** |
| 15 | 派单：HLS 可改，改后必须同时支持 1/2 口 | 本件方案：P3 HLS = `MAX_TCP_CONN=8` + `BOARD_IP_DUAL=1` + **运行时 `adv_wnd` 输入**；1 口/2 口都用它；C3（0x2D）回归配置继续用**归档的 P2 HLS 网表**（逐位不变 artifact）；C1（0x2A）锚用**归档的 0x2A 单 IP 网表**。 | 设计选择 |
| 16 | **此前把 C1（只连一个端口）折叠进 C3、少列一个配置** | 用户 2026-10-18 订正为 **四配置**。本件按四配置重写 §2：C1 锚 = **0x2A**（P11 之前最近单口板级位流；台账 §10-110/§10-113：placed **78,248 LUT / 75,360 FF / 348 BRAM / 1 URAM / 4 DSP / 6 GT**，WNS **+0.039 / +0.010 / 0/0/0**，BID **0x2A**，位流 `aa44a0ed…a3b6`）；C3 锚 = **0x2D**。 | ⛔ **已订正** |
| 17 | **现核：C2 的 ch0 TX MAC 不是新模块** | 现树 0x2D/P2 已有 `mac_tx_10g u_mac_tx_ch0`（`board/wrapper_p4.v:3395`，`ifdef DUAL_SFP_A` 内）；P1（0x2B）只有 ch0 RX MAC。⇒ **C2 只需在 `cfg_mirror` 中例化/接线该模块，非新写模块**，资源估计不变（1,602 LUT / 488 FF）。旧的"P1 只有 RX MAC、需补 TX MAC"措辞已订正（§2.1 C2 行 / §8.3 表注 2）。 | ✅ **现核；已订正** |

---

## 1. 目标 / 约束 / 非目标

### 1.1 目标（用户逐字约束）

1. **两个 SFP+ 接口共用 8 个 TCP 连接的缓存资源**，不是平均分成两组每组 4 个。
2. **同时实现 10G×2 线速**（两端口各 10G，聚合 ~20G）。
3. **HLS 可改**，但改后必须**同时支持 1 个或 2 个端口**。
4. 新增（协调者转达，2026-10-18；用户订正为四配置）：**C1/C2/C3/C4 是互斥构建配置**，区别很大；**防代码分叉**；**单仓四配置**，不拆三仓。

### 1.2 约束（不可违背）

- **TCP 窗口不可撤销**：已通告的窗口不能收回 ⇒ 每连接配额必须在**建连前**写入；共享池只能是「单一分配器 + 预配额」，**不能建连后动态借还**。
- **2×10G 需要两条独立的 10G TX 线与两个 RX 入口**（S1 §1 已证：单 `u_txcdc`/`u_mac_tx`/单 RX 入口的聚合上限 ~9.5Gbps）。
- **每连接重传环 64KB × 8 连接 = 512KB**；每连接 `WIN_CAP=16'hF000`（61,440 B）与 ring 结构界 `(61,440−1)+1,500 = 62,939 < 65,536` 不动（`rtl/retx_ram.v` 头注释、`rtl/tcb.v:144-147`；S1 §3.5）。
- **每口物理 RX 缓冲必须 ≥ 该口所有连接配额之和**（`tcp_echo` 的 `frame_fifo`）；0x2D 是 64KB/口；8×12KB 放一口需要 96KB ⇒ **128KB/口**（2 的幂，`frame_fifo` 的 `D/512` 与 AW 逻辑要求）。
- 0x2D 的时序余量 **0.66%**、DP 最差族已登记；**一次构建收口 + 预登记 backstop**，不许「重跑到过」。
- 不改 PCS/GT/参考钟/QPLL 复位/XDC 时钟组/QSPI/`D:\repo\perfv`。

### 1.3 非目标（本件不做）

- **不做乙·镜像转发**（`SFP2_MODE_B` = C2）的 RTL/位流；**P3 只管 C4（甲·双栈）**。C2 是单独配置/单独 BID，**不得经过 TCP 路径**。C1/C3 是既有/边界配置，保留为锚/回归，不在 P3 改动其行为。
- **不做 16 连接/口**、不做 URAM 迁移（`retx_ram` 29–32 URAM/套、板上已有 1 个 M1 URAM ⇒ 59–65/64 贴满；S1 §3.5）。
- **不做动态窗口借还/C15 增量补授**（共享模式下关闭；用户明确禁止建连后借还）。
- **不做 per-port MAC**（同 MAC 直连；接交换机/同 L2 需另裁）。
- **不做 host/PCIe CSR 配额写通路**（板上 app 总线静态钉死；用 boot writer / 编译常量）。
- **不做单栈 128 位宽化**（S1 §8.5 已否：全链 64 位，宽化 = 重写整条流水，不比双栈便宜）。
- **不做共享 TCB/CAM 多读口**（S1 B/C2 已验证「双快路径」是更低风险；见 §3.6）。
- 本件**不实施、不构建、不上板**。

---

## 2. 代码结构与模式矩阵（防分叉）【新增强制章】

### 2.1 四配置清单（互斥构建配置，不是运行期开关）

**两条正交轴**：**端口数（1/2）× 第二口角色（无 / 镜像转发口 / 共享栈入口 / 独立栈入口）**。两者组合里只有四个有效格，C1–C4 一一对应，**不用 2×4 全组合枚举**（其余组合结构性无意义）：

| 端口数 \ 第二口角色 | 无 | 镜像转发口 | 共享栈入口 | 独立栈入口 |
|---|---|---|---|---|
| **1** | **C1** `cfg_single`（单口基线，锚 0x2A） | —（无第二口） | —（无第二口） | —（无第二口） |
| **2** | —（第二口无角色≠有端口） | **C2** `cfg_mirror`（乙·镜像） | **C3** `cfg_shared`（甲·单栈，锚 0x2D） | **C4** `cfg_dual`（甲·双栈 = P3） |

| 配置 | 端口数 / 第二口角色 | TCP 快路径 | 第二口数据面 | HLS | 缓存/池 | 聚合上限 | BID / 锚 |
|---|---|---|---|---|---|---|---|
| **C1 只连一个端口**（单口基线） | 1 / 无 | **1 套**（`tcp_rx`/`tcp_tx_frame`/`tcb`/`tcp_cam`/`app_ctrl`/`tcp_echo`/`app`），无 merge/demux | **无**（无第二口 MAC/数据面） | 单份单 IP（归档 0x2A 网表） | 单 `app_ctrl` 池 48KB | ~10G（单口一条 TX 线） | **0x2A**（已上板；P11 前最近单口位流） |
| **C2 一个端口转发**（乙·镜像） | 2 / 镜像转发口 | **1 套业务栈**（业务口） | **第二口无 IP / 无 TCB / 无连接状态**；仅 **业务口 RX tap → FIFO → 第二口 TX MAC** 旁路；**不转发 TX**；**与 PCIe 无关** | 单份单 IP（业务口） | 业务栈自己的池 | 业务口 ~10G；镜像口随 tap 速率 | 单独 BID（**0x2E 或 0x30**，乙轮定）；**纸面**（P1（0x2B）只有 ch0 RX MAC；**P2/0x2D 已在树中落地 `mac_tx_10g u_mac_tx_ch0`（`board/wrapper_p4.v:3395`，`ifdef DUAL_SFP_A` 内），非新写模块**；C2 只需在 `cfg_mirror` 例化/接线，资源估计不变 1,602 LUT / 488 FF） |
| **C3 两个端口共享 10G**（甲·单栈 = P2-甲） | 2 / 共享栈入口 | **1 套** + **`rx_merge2`/`tx_demux2`**（两口都是 L2 入口，合流进同一栈） | 第二口 RX 进 merge、TX 由 demux 分流；全业务口（双 IP） | 单份双 IP（归档 P2 网表） | 单 `app_ctrl` 池 **48KB**；0x2D 历史 HLS `MAX_TCP_CONN=3`，P3 源配 P3 HLS 可 `MAX=8`（8 连接共池，6KB/条） | 聚合 **~10G**（一条 TX 线） | **0x2D**（已上板） |
| **C4 两个端口 10G×2**（甲·双栈 = P3） | 2 / 独立栈入口 | **2 套同模块实例**（每口独立 `tcp_rx`/`tcp_tx_frame`/`tcb`/`tcp_cam`/`app_ctrl`/`tcp_echo`/`app`），**无 fast merge/demux** | 两口各自 IP/TCB/CAM/retx，各自 MAC/arb/FIFO | 单份双 IP（P3 网表：`MAX_TCP_CONN=8` + `adv_wnd` 输入） | **新模块 `win_pool_mgr` 单共享 96KB** + 两套 app_ctrl 只读配额；**共享 8 槽 retx（首选）** | **2×~9.5G 线上载荷** | **0x2F**（纸面；乙顺延） |

> **C1/C3 的「8 连接共用一个池」口径**：C3 的逻辑能力 = P3 源 + P3 HLS `MAX=8` + `wq_cap=48KB/8=6KB` + boot writer；**0x2D 历史位流是 HLS `MAX=3` + 默认 `wq_cap=0xC000`（第一条拿满 48KB）**。C3 回归配置**不改**其历史行为；8 连接共池只在 P3 源的单栈配置里成立。C1 是单口基线（0x2A），不涉及 8 连接共享合同。

**硬门矩阵（一构建恰选一个 C；elaboration 失败，照 `board/wrapper_p4.v:226-241` 的 `g_orph_zw_guard` 手法）**：

| 门名（常量错误模块） | 条件 | 说明 |
|---|---|---|
| **`P11_CFG_SELECT_ONE`** | `P11_CFG_C1 + C2 + C3 + C4` 的定义数 ≠ 1 | **恰选一个 C**；0 个或 >1 个 = 硬失败 |
| **`P11_CFG_C1_CONFLICTS_SECOND_PORT`** | `P11_CFG_C1 ∧ (SFP2_MODE_A ∨ SFP2_MODE_B ∨ DUAL_SFP_A ∨ P11_DUAL)` | C1 无第二口数据面 |
| **`P11_CFG_C2_REQUIRES_MODE_B`** | `P11_CFG_C2 ∧ ¬SFP2_MODE_B` | C2 = 乙构建开关 |
| **`P11_CFG_C2_CONFLICTS_DUAL_SFP_A`** | `P11_CFG_C2 ∧ DUAL_SFP_A` | C2 不走双口共享栈前端 |
| **`P11_CFG_C2_CONFLICTS_P11_DUAL`** | `P11_CFG_C2 ∧ P11_DUAL` | C2 不与双栈共存 |
| **`P11_CFG_C3_REQUIRES_MODE_A_DUAL`** | `P11_CFG_C3 ∧ (¬SFP2_MODE_A ∨ ¬DUAL_SFP_A)` | C3 = P2-甲 双口单栈 |
| **`P11_CFG_C3_CONFLICTS_MODE_B`** | `P11_CFG_C3 ∧ SFP2_MODE_B` | 甲/乙互斥 |
| **`P11_CFG_C3_CONFLICTS_P11_DUAL`** | `P11_CFG_C3 ∧ P11_DUAL` | C3 无第二套栈 |
| **`P11_CFG_C4_REQUIRES_DUAL_SFP_A`** | `P11_CFG_C4 ∧ (¬DUAL_SFP_A ∨ ¬SFP2_MODE_A ∨ ¬P11_DUAL)` | **C4 要求 `DUAL_SFP_A=1`** + 甲 + 双栈 |
| **`P11_CFG_C4_CONFLICTS_MODE_B`** | `P11_CFG_C4 ∧ SFP2_MODE_B` | 甲/乙互斥 |
| **`P11_DUAL_AND_SFP2_MODE_B_CONFLICT`** | `P11_DUAL ∧ SFP2_MODE_B` | 现有手法同形（保留） |
| **`SFP2_MODE_A_AND_B_CONFLICT`** / **`DUAL_SFP_A_AND_SFP2_MODE_B_CONFLICT`** | 现有 | 现有手法（保留） |

- **一构建恰选一个 C**：`P11_CFG_SELECT_ONE` 是总门；C2/C3/C4 两两互斥由各自 sub-macro 门 + 选择器共同保证（C2 与 DUAL/P11 冲突、C3 与 P11/B 冲突、C4 与 B 冲突）。
- **C4 要求 `DUAL_SFP_A=1`**：`P11_CFG_C4_REQUIRES_DUAL_SFP_A`；另 `P11_DUAL_REQUIRES_DUAL_SFP_A` 保留。
- **C2 与 `DUAL_SFP_A`/`P11_DUAL` 冲突**：`P11_CFG_C2_CONFLICTS_DUAL_SFP_A` / `..._P11_DUAL`。
- 模式宏只在 `board/` 组合层；`rtl/`/`hls/src/` 不得出现 `P11_CFG_C*`/`SFP2_MODE_*`/`DUAL_SFP_A`/`P11_DUAL` 的产品模式 ifdef。

> **P3 范围声明**：本设计**只管 C4（甲·双栈）**。C1/C2/C3 是同一 stack 的既有/边界配置：C1 锚 = 0x2A，C3 锚 = 0x2D，C2 是乙（deferred，不在 P3 范围、**不得经过 TCP 路径**、第二口不例化 `tcp_rx`/`tcb`/`tcp_cam`/`tcp_tx_frame`/`app_ctrl`）。乙的具体方向（业务口 RX tap、第二口 TX MAC 出）沿用 P1/P2 `SFP2_MODE_B` 设计件，本件不复述、不发明。

### 2.2 单仓四配置的核心/配置边界

**目标结构（单仓，不拆仓）**：

```
rtl/  + hls/                      ← 模式无关 IP stack（无任何产品模式 ifdef；只用默认关参数）
board/
├── common/                       ← 共享前端（禁止四份复制）
│   ├── front_end.v                 PCS/GT 端口、SFP 控制脚、参考钟/MMCM、时钟/复位
│   ├── pcie_obs.v                  XDMA / user BAR / 快照框架 / 读侧几何
│   └── pins.xdc / clk.xdc          共享约束
├── cfg_single/top_single.v       ← C1 只连一个端口（0x2A 锚）：1 stack + 归档 0x2A 单 IP HLS；无第二口数据面
├── cfg_mirror/top_mirror.v       ← C2 一个端口转发（乙）：1 业务 stack + 业务口 RX tap→FIFO→第二口 TX MAC；第二口无 IP/TCB
├── cfg_shared/top_shared.v       ← C3 两个端口共享 10G（0x2D 锚）：1 stack + rx_merge2/tx_demux2 + 归档 P2 HLS
├── cfg_dual/top_dual.v           ← C4 两个端口 10G×2（P3）：2 stack 实例 + win_pool_mgr + slow merge/demux + P3 HLS
└── build/                        ← tcl：配置选择（P11_CFG_C1..C4 恰一个）、宏集、BID、HLS 网表路径、硬门清单
```

- **公共前端**（PCS/GT、时钟/复位、PCIe 观测、快照框架、XDMA、共享 XDC）抽到 `board/common/`，**四个配置例化同一模块**，禁止四份顶层复制。
- **模式宏只允许出现在 `board/` 组合层**（`cfg_*` 顶层 + `board/build/*.tcl`）。`rtl/`/`hls/src/` 内**不得**出现 `P11_CFG_C*`、`SFP2_MODE_A/B`、`DUAL_SFP_A`、`P11_DUAL` 等产品模式 ifdef。
  - **现读审计**：`grep -rn "SFP2_MODE\|DUAL_SFP_A\|P11_DUAL" rtl/ hls/src/` = **0 命中**（2026-10-18 现读）✅。现有 `rtl/` 里的 `DP_156MHZ`（时钟域常量）与 `P7B_10G`（数据面特性宏）**不是产品模式**，按「stack 构建参数/特性宏」读；P3 不重构它们（登记为技术债，见 §2.3-9）。
- **P3 实施增量路径**（如实）：当前 `board/wrapper_p4.v` 是一个 5,000+ 行、多 `ifdef` 的单体。P3 第一版**可以**在该单体里加 `P11_CFG_C4`/`P11_DUAL` 分支（最低风险、一次构建收口）；**`board/common` + `cfg_*` 的物理拆分是独立的结构轮**（P3.5/P4），不与 P3 功能改动混批。无论是否拆分，**防分叉纪律（§2.3）现在就必须执行**。

### 2.3 防分叉纪律（逐条 + 可检查判据）

1. **第二套快路径 = 同模块二次例化，禁止复制/派生模块文件**。
   - 判据：`git ls-files rtl/ | grep -Ei '(_p3|_dual|_port[12]|_copy|_c[1-4])'` = **0**；C4 构建的 `xvlog` 文件表与 C3 `cfg_shared`（以及 C1 `cfg_single`）的**同名模块文件集合差集 = 仅新模块**（`win_pool_mgr.v` + 慢 merge/demux（若新建）+ `retx_pool_shared.v`（若选共享 retx））。
   - **实例计数门（逐配置，按 C4 表为最严）**：
     - C1 `cfg_single`：`tcp_rx`/`tcp_tx_frame`/`tcb`/`tcp_cam`/`app_ctrl`/`app_pattern` = **1**；`mac_rx_10g`/`mac_tx_10g` = **1**；`win_pool_mgr` = 0；`rx_merge2` = 0。
     - C2 `cfg_mirror`：业务栈 `tcp_rx`/`tcp_tx_frame`/`tcb`/`tcp_cam`/`app_ctrl`/`app_pattern` = **1**；`mac_rx_10g` = **2**（业务口 + 第二口 tap）；`mac_tx_10g` = **2**（业务口 + 第二口镜像 TX）；`win_pool_mgr` = 0；`rx_merge2` = 0；**第二口 `tcp_rx`/`tcb`/`tcp_cam`/`tcp_tx_frame`/`app_ctrl` = 0**。
     - C3 `cfg_shared`：`tcp_rx`/`tcp_tx_frame`/`tcb`/`tcp_cam`/`app_ctrl`/`app_pattern` = **1**；`mac_rx_10g`/`mac_tx_10g` = **2**；`win_pool_mgr` = 0；`rx_merge2` = **1**。
     - C4 `cfg_dual`：`tcp_rx`/`tcp_tx_frame`/`tcb`/`tcp_cam`/`app_ctrl`/`app_pattern` = **2**；`mac_rx_10g`/`mac_tx_10g` = **2**；`win_pool_mgr` = **1**；`rx_merge2` = 0。
     - **任何配置出现第三份同模块副本 = 硬失败**（`P11_INSTANCE_COUNT` 门）。
2. **共享模块改动必须默认关 + 逐位退化/行为回归**。
   - `app_ctrl`：新参数 **`EXT_QUOTA = 1'b0`**（默认 0 = 今天的内部池/`winq`/C14/C15 **行为逐字等价**；源已改 ⇒ placed 网表不承诺逐位）；`EXT_QUOTA=1` 才接 `win_pool_mgr`。
   - `tcp_tx_frame`：新参数 **`EXTERNAL_RETX = 1'b0`**（默认 0 = 内部 `retx_ram`，两体 OVL/默认都保留）；`RETX_N = 16` 默认。
   - `retx_ram`：新参数 **`N = 16`**（默认 16 = 今天的 16 连接地址/阵列；N=8/1 只改 `w_conn` 位宽与阵列深度，ring 语义不变）。
   - `tcp_echo`：新参数 **`D = 8192, AW = 13`** 默认（默认 64KB；C4 配置传 16384/14）。
   - HLS：`MAX_TCP_CONN` 是**构建 cflag**（默认 3；P3 网表 8）；**C3 `cfg_shared` 继续用归档的 P2 双 IP HLS 网表**（逐位不变 artifact）；**C1 `cfg_single` 用归档的 0x2A 单 IP HLS 网表**；C2 用业务口单 IP 网表；C4 用 P3 双 IP 网表（`adv_wnd` 输入）。
   - 判据：C3 `cfg_shared` 重构建 = 0x2D 的**行为回归**（P2 板级 B-1/B-2/B-4B/B-5/B-7 + 0x2D 构建门）；C1 `cfg_single` 重构建 = 0x2A 的**行为回归**（P9 板级 0x2A 读数 + 0x2A 构建门）；`EXT_QUOTA=0`/`EXTERNAL_RETX=0`/`N=16`/`D=8192` 的参数分支被综合常量折叠；**不承诺 placed 网表逐位相同**（RTL 编辑 + 放置位移），只承诺**功能等价 + WNS>0 + 三类端点 0/0/0**。
   - ⚠️ **`TX_CONTINUOUS=0` 先例的正确引用**：那是 `app_pattern` 的**纯参数默认**，用 24 文件 `fc /b` 证明**源文件逐字节不变**（`p7b_longsend/CONT_GATE_stdout.txt`）。P3 的 `app_ctrl`/`tcp_tx_frame`/`retx_ram` 是**RTL 编辑**（新增参数/端口/分支），**不能照搬 'fc /b 逐字节'**；判据降为「默认参数行为回归 + C1/C3 构建读数」。**不许写成逐位退化**（除非该文件确实未改源）。
3. **共享池 = 新模块，不改 `tcb`/`retx_ram` 语义；不选 C4 时不例化**。
   - 新件 `rtl/win_pool_mgr.v`：单 `pool`（96KB，17 位）、`winq[0:7]`（16 位）、`port_win[0:1]`（17 位）、`wq_cap`/`port_cap`；只做 **ev_up 授予 / ev_down 归还**；**无 C15 动态补授**（用户要求预配额）。
   - 判据：C1/C2/C3（`cfg_single`/`cfg_mirror`/`cfg_shared`）的 synth 日志 `win_pool_mgr` **0 实例**（不是黑盒、不是漏导入）；C4 `cfg_dual` = 1。`tcb.v`/`retx_ram.v` 的**功能主体零改动**（`retx_ram` 只加 N 参数）。
4. **模式选择只在 `board/` 组合层；每配置独立 BID；不得出现第三份模块副本**。
   - 判据：`rtl/`/`hls/src/` 的产品模式宏命中 = 0；`P11_CFG_SELECT_ONE` 门（恰一个 C）；每个 `cfg_*` 的 `BUILD_ID_V` 唯一（C1 **0x2A** / C2 **0x2E 或 0x30** / C3 **0x2D** / C4 **0x2F**）；构建日志打印 `P11_CONFIG=<single|mirror|shared|dual> BID=<...>`；实例计数门（第 1 条）。
5. **单仓四配置，不拆仓（当前）**。见 §2.6。

### 2.4 模块 → stack/config → C4 角色 → 选 C1/C3 时是否逐位不变

| 模块（路径） | 归属 | C4（P3）角色 | 选 C1 `cfg_single` / C3 `cfg_shared` 时 |
|---|---|---|---|
| `rtl/tcp_rx.v` | **stack** | 第 2 次例化（C4 共 2 实例） | **源未改** ⇒ 同参下逻辑同源（C1/C3 各 1 实例） |
| `rtl/tcp_tx_frame.v` | **stack** | 第 2 次例化；`EXTERNAL_RETX=0` 默认、`PER_CONN_SRC_IP=0` 默认、`RETX_N=16` 默认 | **默认行为等价**；源已改（参数/端口/两体分支）⇒ **不承诺逐位** |
| `rtl/tcb.v` | **stack** | 第 2 次例化；N=16 | **源未改** ⇒ 逻辑同源（C3 的 16 槽 / C1 的 16 槽） |
| `rtl/tcp_cam.v` | **stack** | 第 2 次例化；N=16 | **源未改** |
| `rtl/retx_ram.v` | **stack** | `N` 参数（默认 16）；C4 = 每口 `N=8` ×2 或共享 `N=1`×8（新模块） | `N=16` 默认 ⇒ **ring 语义/地址不变**（C3 的 16 连接 / C1 的 16 连接）；阵列尺寸参数化是结构改动 |
| `rtl/app_ctrl.v` | **stack** | 第 2 次例化；`EXT_QUOTA=0` 默认 | **默认行为等价**（内部池/winq/C15 全保留）；C1/C3 各 1 实例；源已改 ⇒ 不承诺逐位 |
| `rtl/win_pool_mgr.v` | **stack（新）** | `cfg_dual` 1 实例 | **C1/C2/C3 不例化** ⇒ 无影响 |
| `rtl/retx_pool_shared.v` | **stack（新，可选）** | `cfg_dual` 1 实例（8×`retx_ram #(.N(1))` + owner mux） | **不例化** ⇒ 无影响 |
| `rtl/slow_merge2.v` / `slow_demux2.v` | **stack（新，或复用 `rx_merge2`/`tx_demux2`）** | `cfg_dual` 各 1 | **不例化** ⇒ 无影响 |
| `rtl/rx_merge2.v` / `rtl/tx_demux2.v` | **stack helper** | **C4 不例化**（快路径退役） | **C3 `cfg_shared` 仍例化**（各 1）；C1/C2 不例化 ⇒ 源未改、C3 行为不变 |
| `rtl/app_pattern.v` / `app_udp_pattern.v` | **stack** | 每口 1 实例（C4 共 2 套） | 源未改；C1/C2/C3 各 1 套 |
| `rtl/udp_split.v` / `udp_rx.v` / `udp_tx_cfg.v` / `udp_tx_frame.v` | **stack** | 每口一套（C4 共 2 套） | C1/C2/C3 各 1 套 |
| `rtl/vlan_strip.v` / `rx_classify.v` / `fifo_async.v` | **stack** | 每口一套（C4 共 2 套） | C1 各 1；C2 业务口各 1（第二口 tap 不走 classify）；C3 各 1（merge 之后） |
| `mac_rx_10g.v` / `mac_tx_10g.v` | **stack** | 每口一套（C4 共 2/2） | C1 = 1/1；C2 = 2/2（业务口 + 第二口 tap/镜像）；C3 = 2/2 |
| `rtl/app_ctrl.v` 的 `EXT_QUOTA` 参数 | **stack** | `cfg_dual` = 1 | C1/C2/C3 = 0 |
| `hls/src/*` | **stack** | P3 网表：`MAX_TCP_CONN=8` + `BOARD_IP_DUAL=1` + `adv_wnd` 输入 | C1 = 归档 0x2A **单 IP** 网表；C3 = 归档 P2 **双 IP** 网表；C2 = 业务口单 IP 网表 |
| `board/wrapper_p4.v` 或 `board/cfg_*` | **config** | `cfg_dual`/C4 分支 + `P11_CFG_C4`/`P11_DUAL` | C1 `cfg_single`=0x2A 路径；C3 `cfg_shared`=0x2D 路径 |
| PCS64 / XDMA / 快照框架 / XDC | **config/common** | 共享，不复制 | 四个配置共享 |

> 「逐位不变」列的口径：**源未改 + 同参** ⇒ 逻辑同源（最终 placed 网表仍可能因父层/布局位移）；**默认参数但源已改** ⇒ 只承诺行为等价 + C1(0x2A)/C3(0x2D) 构建回归；**归档 HLS 网表** ⇒ artifact 逐位不变。**没有任何一格允许「派生/复制模块文件」。**

### 2.5 既有配置（C1/C3）保留还是退役

| 配置 | 角色 | 保留成本 | 退役代价 |
|---|---|---|---|
| **C1 `cfg_single`（0x2A，单口）** | 单口产品/单口基线锚 | 每次改快路径多跑 1 档（单口 build/门）；板级单口回归 1 次 | 失去 P11 前最近单口板级锚；P3 之后单口只能靠 C4 只插 J8 / C3 只插 J8 覆盖（**不是同一个位流/配置**） |
| **C3 `cfg_shared`（0x2D，双口共享栈）** | P2-甲 产品/共享栈回归锚；`rx_merge2`/`tx_demux2` 的常驻覆盖 | 每次改快路径多跑 1 档（shared build/门）；板级双口共享回归 1 次 | `rx_merge2`/`tx_demux2` 失去常驻门覆盖（只剩历史）；**0x2D 的 P2 板级读数不能复现**；共享栈的单口 J8 回归只剩 C4/C1 |
| **C2 `cfg_mirror`（乙）** | 独立产品（deferred） | 只有改镜像路径时才跑；不进 P3 常驻矩阵（乙轮定） | 不影响 C1/C3/C4 |

**推荐**：P3 轮**保留 C1 + C3** 作为回归配置（每次改快路径跑 **C1+C3+C4 三档**；C2 仅在乙轮/动镜像时跑）；P3 板级收口后由用户裁定 C3 是否退役。若退役 C3，`rx_merge2`/`tx_demux2` 与「双口共享栈」路径只剩历史件；**C1（单口）保留**作为单口产品/锚。**不建议立即退役任何一档**（会失去 P3 共享模块改动的默认关回归锚）。

### 2.6 拆仓评估：**2 仓（stack / board-product），不是 3 仓**

- **为什么不是 3 仓（或按配置拆更多仓）**：**C1–C4 是同一套 stack 的四个配置，不是四个 stack**。拆成「两个上层配置 + IP stack 本身」三仓会把 `cfg_single`/`cfg_mirror`/`cfg_shared`/`cfg_dual` 变成多个仓库、各自复制/派生前端与接口，**直接违反防分叉**；四个配置只是同一 stack 的四个组合层。**自然切口 = 2 仓**：`ip_stack`（rtl + hls + 单元门/矩阵）与 `board_product`（board/common + cfg_single/cfg_mirror/cfg_shared/cfg_dual + 构建/烧录/板级工具）。
- **当前接口是否稳定到可拆仓？不**。P3 还要改/新增、因而**不能现在冻结**的接口点：
  1. `app_ctrl` 的 `EXT_QUOTA` 参数与配额输入/`winq` 只读口；
  2. `retx_ram` 的 `N` 参数与 `tcp_tx_frame` 的 `EXTERNAL_RETX`/`RETX_N` 端口；
  3. `tcp_echo` 的 `D/AW`（128KB 缓冲）；
  4. HLS top 的 `MAX_TCP_CONN=8`、`adv_wnd` 输入、`cfg_write` DEL 的 `local_ip`；
  5. 慢路径 merge/demux 与 cfg demux 的接口；
  6. **四配置选择（`P11_CFG_C1..C4` + `P11_CFG_SELECT_ONE` 硬门）**、`P11_DUAL`/`SFP2_MODE_B`/BID 与 HLS 网表选择；
  7. 观测几何/读侧阶段（0x2F）。
- **拆仓触发条件（现在不满足）**：≥2 个独立产品/团队；接口版本化（有 semver/兼容矩阵）；stack 有独立测试套件（可脱离 board 跑）；CI 可按 pinned commit 构建。当前是单产品、单团队、单仓，接口仍在 P3 改动中 ⇒ **不拆**。
- **结论句（写进本件）**：**拆仓的自然切口是 2 仓（stack / board-product），不是 3 仓；触发条件 = ≥2 独立产品/团队、接口版本化、stack 有独立测试套件、CI 可按 pinned commit 构建。现在不满足。**

---

## 3. C4（甲·双栈 = P3）架构选择：B/C2（共享池）vs A′（完全双栈含双 HLS）

### 3.1 选项表

| 选项 | 快路径 | 慢路径 HLS | 共享池 | 共享 retx | HLS 双 IP | 资源（纸面 vs 0x2D 346 BRAM） | 风险 |
|---|---|---|---|---|---|---|---|
| **B/C2S（推荐）** | 2 套（同模块二次例化） | **1 份**（双 IP） | **96KB 单池（新 `win_pool_mgr`）** | **8 槽共享（新 `retx_pool_shared`，128 tile）** | 1 处改 | LUT +27–30k；FF +16–19k（C4 vs C3；MAC/CDC/arb 不计入）；BRAM ≈267；URAM 1；DSP 4 | 时序 + 共享池/retx 抽取的语义 |
| **B/C2P（低风险退路）** | 2 套 | 1 份 | 96KB 单池 | **每口 8 槽（两套 256 tile，净 0 vs 0x2D 的 256）** | 1 处改 | LUT/FF 同 B/C2S；BRAM ≈395 | 物理重传缓存 8+8（8 空闲时浪费 128 tile），但**逻辑准入仍是 8 共享** |
| **A′** | 2 套 | **2 份**（各 1 口，各自双 IP/单 IP 常量） | 96KB 单池（仍需共享，或每口 48KB） | 同 B/C2S/P | 无跨口 HLS | LUT ≈+20k（第二份 HLS 19.8k + 参数化 0.2–0.5k）；BRAM ≈304（共享 retx + 128KB echo）/432（每口 retx）；DSP 8 | 面积可行；**HLS 两份 = 同一模块两次综合/两个网表**，不是代码分叉；跨口慢路径零耦合；资源最高 |
| **M3（共享池退路/偏离）** | 2 套 | 1 份 | **每口 48KB（两条池）** | 共享 8 槽或每口 8 槽 | 1 处改 | 同 B/C2 | **违反「单共享池」语义**：6+2/8+0 无法跨口借用；8+0 时一口只有 48KB（6KB/条，2.5G/20µs BDP 6.25KB 略短） |

### 3.2 B/C2S 结构（推荐，= C4）

```
                    ┌──────────────── 共享前端（board/common）────────────────┐
   J8/ch1 PCS ──────┤ rx_clk_out_1 / tx_mii_clk_1                            │
   J7/ch0 PCS ──────┤ rx_clk_out_0 / tx_mii_clk_0                            │
                    └──────────────────────────────────────────────────────────┘
   port0（ch1，IP_A）:  mac_rx_10g → fifo_async(76) → vlan_strip → rx_classify ─┬→ tcp_rx ─→ tcp_echo ─→ app_pattern
                                                                                 ├→ udp_split → app_udp_pattern
                                                                                 └→ slow 输出 ─┐
   port1（ch0，IP_B）:  mac_rx_10g → fifo_async(76) → vlan_strip → rx_classify ─┬→ tcp_rx ─→ tcp_echo ─→ app_pattern
                                                                                 ├→ udp_split → app_udp_pattern
                                                                                 └→ slow 输出 ─┤
                                                                                                ▼
                                                              slow_merge2（2:1 帧级） → slow_rx_adp → HLS（单份双 IP）
                                                                                                │
   HLS TX ← slow_tx_adp（源 IP 提取 o_port） ←──────────────────────────────────────────────────┘
        │
        └→ slow_demux2（1:2，按 o_port） ─┬→ port0 的 arb 树（UDP>HLS，TCP>UDP/HLS）
                                          └→ port1 的 arb 树（同上）
   port0: tcp_tx_frame（EXTERNAL_RETX=1）→ arb×2 → txcdc(73) → mac_tx_10g → J8
   port1: tcp_tx_frame（EXTERNAL_RETX=1）→ arb×2 → txcdc(73) → mac_tx_10g → J7
                │                                    │
                └────────── 共享 retx 8 槽（owner mux）┘
   app_ctrl ×2（每口 1，EXT_QUOTA=1） ← 只读 winq[slot] ← win_pool_mgr（单 pool 96KB / per-port cap 96KB）
   HLS cfg 8 词 → slow_cfg_demux（1:2，按 w2/slot） → slow_cfg_adp ×2（各自 CAM/TCB/事件）
```

**与 P2/0x2D 的复用与退役**：

| P2 件 | 双栈下的去向 |
|---|---|
| `rx_merge2`（快速路径 2:1） | **C4 退役**（每口自己的 MAC→classify→tcp_rx）。模块保留在 `rtl/` 供 **C3 `cfg_shared`**；C1/C2/C4 不例化。 |
| `tx_demux2`（3 生产者 1:2） | **C4 退役**（TCP/UDP 生产者天然每口一套）。模块保留供 **C3 `cfg_shared`**。**HLS-only 的 1:2 仍需要**（新的 `slow_demux2` 或复用 `tx_demux2` 的单生产者配置）。 |
| `slow_tx_adp` 源 IP 提取 / `o_port` | **保留并复用**（单份 HLS 的出口身份）。 |
| `cam_port_arr` / `cam_rd_port` / `tcp_tx_frame.o_port` / `PER_CONN_SRC_IP` | **C4 不用于 TCP**：每口 `tcp_tx_frame` 接**本口常量 `cfg_src_ip`**（IP_A/IP_B），`PER_CONN_SRC_IP=0`、`o_port=0`。P2 的每连接源 IP 代码保留供 **C3 `cfg_shared`**；C4 不需要它。 |
| A-1（IP 即身份） | **保留**：端口 = `(local_ip == IP_B)`；HLS `board_ip_match/board_src_ip` 复用；cfg demux 与 slow TX demux 都用 IP 判口。 |
| HLS 双 IP | **复用**（P2 已实现 `BOARD_IP_DUAL`；P3 网表沿用 + `MAX_TCP_CONN=8` + `adv_wnd`）。 |
| `SFP2_MODE_A` / `DUAL_SFP_A` 前端 | **复用**（第二口 MAC/FIFO/arb/PCS 端口都在 P2 已落）。 |

### 3.3 A′ 结构

- 两份 HLS（每口一份），各自接本口的 slow 适配器（`slow_rx_adp`/`slow_tx_adp`/`slow_cfg_adp` 各一套），**无 slow merge/demux、无 cfg demux**；每份 HLS 的本地 IP 是常量/参数，不做双 IP 成员判定。
- 两套快路径与 B/C2 相同；共享池/共享 retx 可选（若共享池仍用 `win_pool_mgr`，则 A′ 也要共享；若每口 48KB，则退化为 M3 语义）。
- 代价：+≈20k LUT / +≈18k FF / +37 BRAM / +4 DSP（S1 锚：第二份 `udp_echo` 19,811/17,894/37/4；HLS 参数化 +0.2–0.5k LUT）。
- 优点：端口间慢路径**零耦合**，一份 HLS 的 bug 不影响另一口；无 cfg/TX 跨口 demux；无 `local_ip` 分流的语义风险。
- 缺点：资源最高；两份 HLS 的**单口零回归**仍是「功能等价」不是逐位；两份 HLS 的维护（同一源码两次综合，不是代码分叉）。

### 3.4 资源/时序/风险对比（摘要）

| 维度 | B/C2S | B/C2P | A′ |
|---|---|---|---|
| LUT（vs C3 0x2D 82,013） | +27–30k ⇒ ~109–112k（50–52%） | 同 | +≈20k（相对 B/C2S）⇒ ~129–132k（59.5–60.8%） |
| FF（vs 77,361） | +16–19k ⇒ ~93–96k（21.4–22.1%） | 同 | +≈18k ⇒ ~111–114k（25.6–26.3%） |
| BRAM（vs 346） | **≈267（56%）** | ≈395（82%） | ≈304（63%）/432（90%） |
| URAM | 1 | 1 | 1 |
| DSP | 4 | 4 | 8 |
| 时序 | 同域 +30k LUT + retx/pool mux；风险最高 | 略低（无 retx 抽取 mux，但有第二套 256 tile） | 同域 +50k LUT；风险更高，但无跨口慢 mux |
| 慢路径语义风险 | 中（单 HLS + merge/demux + 双 IP） | 中 | **低**（每口独立 HLS） |
| 共享池语义 | **满足**（单池） | 满足 | 取决于池实现（共享池则满足） |

### 3.5 A-1 / HLS 双 IP / 端口映射复用（钉死）

- 映射沿用 P2：**ch1 = J8 = IP_A = 192.168.100.2（port 0）；ch0 = J7 = IP_B = 192.168.100.4（port 1）**；端口位 = `(local_ip == IP_B)`。
- `slow_cfg_adp` 的 `w2 = local_ip` 写 `cam_cfg_dip`（`rtl/slow_cfg_adp.v:148`）；`tcp_rx` 用帧的 dst IP 组 CAM 键（`rtl/tcp_rx.v:213,443-446`）；`tcp_cam.rd_dip` 语义 = 本地 IP（`tcp_cam.v:26-27`）。
- **双栈不依赖 `tcp_tx_frame` 的每连接源 IP**：每口的 `cfg_src_ip` 常量（IP_A/IP_B）就够；这比 P2 的 `cam_rd_dip` csum 方案更简单、无同沿风险。P2 的 `PER_CONN_SRC_IP`/`cam_rd_dip` 代码保留给 **C3 `cfg_shared`**。
- HLS 双 IP 复用 P2：`board_ip0_u32/board_ip1_u32/board_ip_match/board_src_ip`（`hls/src/eth_types.h:119-180`）；ARP/ICMP/UDP/TCP 的源 IP 取自请求的 dst IP。
- **每口 UDP app 的过滤**：P2 的 `udp_split`/`udp_rx` 用 `DUAL_IP=1` 接受两个 IP（单共享 UDP app）。双栈下每口有自己的 `app_udp_pattern`，应设 **`DUAL_IP=0` + `cfg_dst_ip = 本口 IP`**，保持错口负对照（B-3）的判别力；HLS 共享层仍 `BOARD_IP_DUAL=1`。

### 3.6 不选的结构（登记）

- **单栈加宽到 128 位跑 20G**：全链 64 位（MAC/CDC/classify/tcp_rx/tcp_tx/retx），宽化 = 重写整条流水；两个 MAC 仍要分开。S1 §8.5 已否。
- **共享 TCB/CAM 多读口（单套状态 + 双数据面）**：省 ~5k LUT/FF，但 `tcb` 要加 4 个读口 + 8 级写仲裁，`tcp_cam` 要加 2 查询/2 读口；`tcp_echo` 仍要两份（两个写口）。回归面大，收益小，不选。
- **单 retx + 单写口**：两口 10G 同时写 ⇒ 需第二写口 ⇒ bank 翻倍 = 512 tile（>480，S1 §8.5）。**共享 8 槽 + per-slot owner mux** 是唯一可行的单共享存储形态（每槽只有一个属主口，天然无同槽双写）。

---

## 4. 共享 8 连接缓存（核心）

### 4.1 「缓存」三层分解（先钉术语，避免把信用当存储）

| 层 | 内容 | 0x2D 现状 | P3 设计 | 是否"共享" |
|---|---|---|---|---|
| **L1 连接控制** | `tcb`（16×~136 FF）+ `tcp_cam`（16×~120 FF）+ 事件/槽状态 | 每栈 16 槽；HLS `MAX_TCP_CONN=3` | **每口各 16 物理槽（同模块二次例化）**，**系统准入 8 条（HLS MAX=8 + slot<8 守卫）** | **逻辑共享 8 个全局 slot**；物理 16/口（只 0..7 用） |
| **L2 RX 窗口信用 + 物理缓冲** | `app_ctrl` 的 `winq[16]`/`pool`（信用）+ `tcp_echo` 的 `frame_fifo`（物理） | 单栈 `WIN_POOL=49,152 B`；echo 64KB | **新 `win_pool_mgr` 单 pool 96KB** + `winq[8]` + `port_win[2]` + `port_cap`；**每口 echo 128KB** | **信用：单共享 96KB**；物理：每口 128KB（写口原因，见 §4.5） |
| **L3 TX 重传环** | `retx_ram` 8×64KB | 16×64KB = 256 tile | **共享 8 槽 = 128 tile（首选）** 或每口 8 槽 = 256 tile（退路） | 首选**物理单共享**；退路逻辑共享、物理 8+8 |

> **「共用 8 个 TCP 连接的缓存资源」在本设计中 = L1 全局 8 准入 + L2 单共享 96KB 信用池 + L3 单共享 8 槽重传阵列（首选）。** 不是「两个口各 4 条」。

### 4.2 单共享池 vs 每口 48KB：BDP 算术（口径必须分开）

| 拓扑 | 承载速率 | 池 | RTT 上限 | 实测 srtt 16–27µs |
|---|---|---|---|---|
| **单个 48KB 池供两口（P2 C3 式）** | 聚合 20G | 48KB | **19.2µs（48,000 B）/ 19.7µs（0xC000）** | **27µs 不够**（缺口 1.4×） |
| **单个 96KB 池供两口（P3 推荐）** | 聚合 20G | 96KB | **38.4µs（96,000 B）/ 39.3µs（0x18000）** | 覆盖（27µs 处余量 **1.42× / 1.46×**） |
| **单个 128KB 池供两口（可选）** | 聚合 20G | 128KB | **51.2µs（128,000 B）/ 52.4µs（0x20000）** | 覆盖（27µs 处余量 **1.90× / 1.94×**） |
| **每口 48KB（两条池，共 96KB）** | 10G/口 | 48KB/口 | **38.4µs（48,000 B）/ 39.3µs（0xC000）** | 覆盖（27µs 处余量 **1.42× / 1.46×**） |
| **每口 24.6KB（P2 C3 共享）** | 10G/口 | 24.6KB/口 | **19.2µs / 19.7µs** | 27µs 不够 |

**结论（与派单口径的差异，如实说）**：

- 派单的「48KB ⇒ 19.2µs；96KB ⇒ 38.4µs；实测 srtt 16–27µs ⇒ 单 48KB 不够、96KB 覆盖」**只对"单个 48KB 池供两口"成立**。
- **每口 48KB（两条独立池，总 96KB）在 BDP 上是够 2×10G 的**（每口 39.3µs @10G）。所以「共享 96KB」不是 2×10G 的 BDP 必需，而是**用户语义必需**：①不能固定 48/48 分区；②6+2/8+0 要能跨口借用；③一份分配器/一份记账。
- **每连接配额**：
  - 8 连接合同：96KB/8 = **12,288 B（0x3000）/条**；2.5G/条 @20µs BDP = 6,250 B ⇒ **余量 1.97×**；@27µs BDP = 8,437 B ⇒ 余量 1.46×。
  - 2 连接 2×10G：96KB/2 = **48KB（0xC000）/条**；10G @27µs BDP = 33,750 B ⇒ **余量 1.42×**；@16µs BDP = 20,000 B ⇒ 余量 2.4×。
  - **配额是场景常量，不是"8 条就固定 12KB"**：8 条合同用 12KB；2 条合同用 48KB。app/boot writer 必须在建连前选好。
- **128KB 池（可选）**：8×16KB；2×64KB；BDP 51.2µs（128,000 B）/ 52.4µs（0x20000）。若用户要更大余量可选；本件推荐 96KB（12KB/条）作为基准，128KB 作为 headroom 选项。**注意：128KB 池的 `pool` 超过 17 位（131,071）一位 ⇒ 池/比较要扩到 18 位**（`winq` 仍是 16 位；每连接 16KB 放得下）；且 **128KB 池 + 每口 128KB echo 时，8×16KB=128KB 刚好占满一口的物理缓冲（无安全余量）** ⇒ 若选 128KB 池，建议每口 echo 256KB（D=32768，64 tile/口）或把 8 条合同收紧到 14KB。**本件推荐 96KB 池（0x18000，17 位）+ 128KB/口 echo（32KB 物理余量）**。

### 4.3 窗口不可撤销 ⇒ 预配额；寄存器/接口

**硬规则**：TCP 窗口一旦通告不可撤销（降窗会把在飞段拒掉 ⇒ 静默丢帧/死锁；`rtl/app_ctrl.v:19-21`、`hls/src/layer_tcp.cpp` 的 P4b-6 注释）。⇒ 每连接配额**只能在建连前写入**；「共用」只能 = **单一分配器 + 预配额**，**不能建连后动态借还**。

**接口（推荐：共享配额管理器 + 两套数据面只读配额 = 协调者建议的最小侵入替代）**：

```
module win_pool_mgr #(
  parameter [16:0] WIN_POOL = 17'h18000,   // 96KB
  parameter [16:0] PORT_CAP = 17'h18000    // 每口上限 96KB
)(
  input clk, rst_n,
  // 授予：ADD 收尾（slow_cfg_adp ev_up，同拍给 app_ctrl 与 manager）
  input        ev_up0, input [3:0] ev_up_slot0,
  input        ev_up1, input [3:0] ev_up_slot1,
  // 统一释放：app_ctrl 的 o_quota_rel / o_quota_rel_slot（每条非零配额恰好一次）
  input        rel0,   input [3:0] rel_slot0,
  input        rel1,   input [3:0] rel_slot1,
  input [16:0] occ0, occ1,                 // 每口 tcp_echo 占用字节（17 位饱和）
  input [15:0] wq_cap,                     // 每连接配额（boot writer 写；8→12KB / 2→48KB）
  input [16:0] port_cap,                   // 每口上限（boot writer 写；96KB）
  // 只读配额（每个 app_ctrl 一个读口）
  input  [3:0] winq_rd_id0, output [15:0] winq_rd0,
  input  [3:0] winq_rd_id1, output [15:0] winq_rd1,
  // 观测/状态
  output [16:0] dbg_pool, output [16:0] dbg_port_win0, dbg_port_win1,
  output [31:0] stat_grant_zero, stat_slot_reuse, stat_rel_dup
);
```

- **属主（EXT_QUOTA=1）**：**`win_pool_mgr` 是 `pool`/`winq`/`port_win` 的唯一属主**；`app_ctrl` 不再写这三者（见下面的 6 类写点旁路表）。`EXT_QUOTA=0`（默认）时 manager 不例化，app_ctrl 的内部池逐字保留。
- **授予（ev_up）**：`g = min(wq_cap, max(pool−occ[p],0), max(port_cap−port_win[p],0))`；`winq[slot] <= g`；`pool <= pool − g + old_winq[slot]`；`port_win[p] <= port_win[p] − old_winq[slot] + g`。**C18（ev_up 落在已占槽）在 manager 内原子完成**：旧配额先回池、再授新；app_ctrl **不再同时归还**（EXT=1 时它的 C18 写点旁路）。
- **归还（rel）**：`pool <= pool + winq[slot]`；`port_win[p] −= winq[slot]`；`winq[slot] <= 0`。同一槽后续的零额 rel 幂等（加 0），并由 app_ctrl 的 `winq_rd[slot]!=0` 门抑制；manager 的 `stat_rel_dup` 计"rel 时 winq==0"（应恒 0）。
- **同拍事件**：两口 ev_up/rel 同拍时，池算术按 `port0 → port1` 固定顺序组合计算（慢事件块；事件稀疏）；gate 逐拍断言 `Σwinq + pool == WIN_POOL`、`Σport_win == Σwinq`、`port_win[p] ≤ port_cap`。
- **无 C15**：不做运行期增量补授；配额固定到连接结束。**这与用户「不能建连后动态借还」同向**；是对现有 `app_ctrl` C15 的一个**模式差异**（不是缺陷）。

**`EXT_QUOTA=1` 时 app_ctrl 的 6 类配额写点逐条旁路**（现读 `rtl/app_ctrl.v`；行号会漂移，以信号名为准）：

| # | 现写点 | 现行为 | EXT_QUOTA=1 处置 |
|---|---|---|---|
| 1 | 复位 `pool<=WIN_POOL; winq<=0`（`:1019/:1043` 一带） | app_ctrl 内部 | **旁路**；manager 自己复位 `pool/winq/port_win`；app_ctrl 的 `redge/wu_mark` 仍复位 |
| 2 | `ev_up` 授予 `winq[ev_slot]<=g_grant; pool<=pool_upd`（`:1119-1120`，含 C18 旧配额归还） | app_ctrl 内部 | **旁路**；manager 在 ev_up 原子授予（`pool−g+old`）；app_ctrl 只保留事件转发/init/`redge`/`wu_mark` |
| 3 | `ev_down` 归还 `pool<=pool_ret_x; winq[ev_slot_i]<=0`（`:1162-1165`） | app_ctrl 内部 | **旁路**；app_ctrl 发 `o_quota_rel`（`ev_down_i`）→ manager 归还 |
| 4 | 超时/孤儿归还 `pool<=pool_ret_x; winq[scan_id]<=0`（`:1278-1279`，F1） | app_ctrl 内部 | **旁路**；超时 `to_fire` 发 rel；**孤儿已并入 `ev_down_i`**（`orph_down_r` → `ev_down_i`）⇒ 走 #3，不另发 |
| 5 | abort/state=0 归还 `pool<=pool_ret_x; winq[scan_id]<=0`（`:1303-1304`） | app_ctrl 内部 | **旁路**；`st_req_now` 发 rel → manager 归还 |
| 6 | C15 增量补授 `winq[pb_sid]+=inc_grant; pool<=pool-inc_grant`（`:1348-1352`） | app_ctrl 内部 | **关闭**（EXT=1 无 C15；与用户预配额同向） |

**统一释放事件（新增 app_ctrl 输出，`EXT_QUOTA=0` 时恒 0）**：

```
output wire       o_quota_rel;        // 1 拍脉冲；每条槽的**非零配额**恰好一次
output wire [3:0] o_quota_rel_slot;
```

- 生成：`o_quota_rel = (ev_down_i | to_fire | st_req_now) && (winq_rd[slot] != 0)`；`slot = ev_down_i ? ev_slot_i : scan_id`。**`winq_rd` 是 manager 的只读配额**（app_ctrl 已有该读口）⇒ 后续零额释放被抑制，非零释放只发一次。
- **读口 ID mux**：`winq_rd_id = ev_down_i ? ev_slot_i : (init_pend ? init_slot : scan_id)`（与 `rc_id` 同源，多一个 `ev_down_i` 覆盖）⇒ `o_quota_rel` 的 gate 在 DEL 拍读到**该槽**的配额；`to_fire`/`st_req_now` 的槽 = `scan_id`，天然同口。EXT=0 时 `winq_rd` 不存在（内部数组）。
- 为什么不能用外部 `slow_cfg_adp.ev_down` 直接接 manager：它只覆盖 #3 的外部 DEL，**看不到 #4（超时/孤儿）与 #5（abort/state=0）** ⇒ 配额泄漏；若再接内部信号又会与 #3 双重归还。统一事件把 #3/#4/#5 收在一处，manager 只认 `rel`。

**释放路径 → 事件源 → 恰好一次**：

| 释放路径 | 事件源（app_ctrl 内） | 发 `rel` 的条件 | 恰好一次保证 |
|---|---|---|---|
| 外部 DEL（`slow_cfg_adp` ev_down） | `ev_down` | `ev_down_i && winq_rd[slot]!=0` | 每条 DEL 至多一次；重复 DEL 时 winq=0 ⇒ 不发 |
| 孤儿回收通知（`orph_down_r`） | `ev_down_i` 的 OR | 同上 | orphan FSM 只发一次 `orph_down_r`；与 DEL 同拍只 OR 一次 |
| 关闭超时（`to_fire`） | `to_fire` | `to_fire && winq_rd[scan_id]!=0` | `to_fired` 只置一次；后续 DEL 时 winq=0 ⇒ 不发 |
| abort/state=0（`st_req_now`） | `st_req_now` | `st_req_now && winq_rd[scan_id]!=0` | `st_done` 只置一次；后续 DEL 不发 |
| ev_up 同槽旧配额（C18） | — | **不发**；manager 内 `pool−g+old` 原子 | manager 单点 |
| C15 增量补授 | — | **关闭**（EXT=1） | — |
| 复位 | — | manager 自己 | — |

- **app_ctrl 的 `EXT_QUOTA=1` 读路径**：`fq_scan = fq_calc(winq_rd[scan_id], rx_occ_bytes)`；`redge`/`wu`/`fc`/事件/超时/孤儿逻辑**全部复用**（它们只读 `winq_rd`，不写配额）；`stat_pool_exhaust`/`dbg_pool`/`stat_slot_reuse` 来自 manager。
- **时序**：ev_up 与 manager 的授予**同拍**（g 组合、`winq` 在沿上寄存器化）⇒ app_ctrl 的 init（ev_up+1）读到新 `winq`；rel 与 manager 的归还在**同拍**（app_ctrl 的 rel 是组合脉冲，manager 在沿上更新）⇒ app_ctrl 后续读看到 0。**不用额外握手**。
- **`tcb` 零改动**；**`retx_ram` 零语义改动**。
- **boot writer（板级必需，新发现）**：0x2D 的 `app_reg_addr/wr/wdata` 在板上**静态钉死**（`wrapper_p4.v:1547-1549`）⇒ host 写不了 `0x0C`。P3 的 `wq_cap`/`port_cap` 必须由 `board/cfg_dual` 里的**小 boot FSM**在复位后写一次（或直接接常量输入）；`EXPECTED_CONNS` 是**构建常量**（2/8），`wq_cap = WIN_POOL / EXPECTED_CONNS`，`port_cap = 96KB`。没有这个 boot writer，上电默认 `0xC000` 会让**第一条连接拿满 48KB**、8 条合同的后 7 条零窗。
- **HLS 的 SYN-ACK 窗口必须与配额一致（P2 遗留的 P3 前置项）**：`tcp_send` 当前硬编码 `0xC000`（`hls/src/layer_tcp.cpp:295`）。P3 改为**运行时输入 `adv_wnd`**（或 P3 网表 cflag），值 = `wq_cap`（2 连接 48KB / 8 连接 12KB）。
  - **为什么必须一致**：SYN-ACK 先于 fast path 的 cfg ADD/首次 ACK；若通告 48KB 而实配额 12KB ⇒ 对端按 48KB 发，fast path 的 `winq=12KB` ⇒ **窗口收缩/丢段**。
  - **超额准入（第 3 条连接 vs EXPECTED_CONNS=2）**：第 3 条 SYN-ACK 仍通告 48KB，但 manager 授予 0 ⇒ 零窗；这是**准入合同被违反**的预期行为（现有 P5d 零窗语义），不是数据损坏；测试必须按合同做。可选的更干净做法 = fast path 对零授予发 RST（新行为，登记为 open decision，不进第一版）。

### 4.4 8 连接准入：HLS MAX=8、分布、TCB/CAM、tcp_find/CAM 键

- **HLS `MAX_TCP_CONN=8`**：`tcp_conn[8]`、`tcp_retrans_buf[8][576]`、`tcp_send_bufs[8][576]`、`tcp_find` 8 项 UNROLL。`w0.slot` 是 8 位（`(cmd<<8)|slot`；`slow_cfg_adp` 取 `w0[3:0]`，0..7 够）。
- **系统准入 = 8**：HLS 是唯一建连源（SYN 走慢路径）；HLS 的 8 个槽 = 全系统 8 条。fast path 的 CAM/TCB 16 物理槽只写 0..7。
- **任意分布**：连接的口由对端连哪个 IP 决定（连 IP_A → port0；IP_B → port1）；HLS 按全局 free slot 分配，不按口。6+2 / 8+0 / 4+4 都只是 `w2=local_ip` 的不同；cfg demux 按 `w2` 路由，`slot_port[8]` 记录每个全局 slot 的口。
- **CAM 键**：`(sip=peer_ip, dip=local_ip, sport=peer_port, dport=8080)`；local_ip 区分口。`tcp_find(port, ip, local_ip)`（P2 已改）同样带 local_ip ⇒ 同 peer 4 元组在两口是两条独立连接。
- **slot<8 守卫（新增，必须）**：HLS 若因 bug 发 `slot>=8`，`tcp_cam`/`tcb` 的 4 位地址会写到 8..15；共享 retx 的 8 槽会**别名到 0..7**（数据损坏）。⇒ `cfg demux` 对 `slot[3]==1` 的记录**丢弃 + `stat_slot_oor++`**；gate 注入 slot=8 的 ADD，断言计数 +1、CAM/TCB 0..15 全不变、retx 不变（负控必红）。
- **每口 TCB/CAM 16 槽**：保留 N=16（零改动；用户约束「物理 16」）。上电 8..15 全 0；`tcp_rx` 的 CAM 查询不会命中；`app_ctrl` 的 16 槽扫描对 8..15 读 0/非 ESTAB，无副作用（超时/孤儿判据不触发）。可选优化 = N=8（省 ~3k FF/2k LUT），但会改接口/阵列宽度，**第一版不做**。

### 4.5 每口物理 RX 缓冲：64KB → 128KB（8+0 的硬约束）

- 0x2D：`tcp_echo` 的 `frame_fifo #(.W(73), .D(8192), .AW(13))`（`rtl/tcp_echo.v:93`）= **8192 字 × 8 B = 64KB**；16 BRAM/口。
- **信用池 96KB 要求物理缓冲 ≥ 该口的 Σwinq**：若 8 条全在 port0（8+0），Σwinq = 96KB > 64KB ⇒ 物理溢出。**必须二选一**：
  - **A（推荐）**：每口 `D=16384, AW=14` = **128KB**（32 BRAM/口）。`frame_fifo` 的 `NB=D/512`、指针 `[AW:0]`、`full` 逻辑要求 **D 是 2 的幂** ⇒ 96KB（12288 字）不可行，**只能 128KB**。总 BRAM 267（共享 retx）/395（每口 retx），均 ≤480。
  - **B（退路）**：保持 64KB/口，`port_cap = 60KB`；6+2 在 12KB/条下需要 72KB > 60KB ⇒ **不成立**；8+0 更不成立。⇒ **只能支持 ≤5 条/口 @12KB**。与用户「任意分布」冲突。
- **宽度/指针改动**：`dbg_fifo_wptr/rptr` 14→15 位；`app_rx_occ = {(wptr−rptr),3'b0}` 从 17 位变 18 位 ⇒ 在 `win_pool_mgr`/`app_ctrl` 的 `rx_occ_bytes` 入口**饱和到 17 位**（128KB = 131,072 恰好超出 17 位 1 字节；饱和到 131,071 的 1 字节低估无实质影响）；`uart_dbg`/trace 的 FIFO 指针字段 +1 位。**`app_ctrl` 的 `fq_calc`/`redge` 位宽不变**。
- **每口 echo 的归属**：每口一个 `tcp_echo`（同模块二次例化），app 每口一个实例；`tcp_echo` 的 `m_axis_tid` 仍带全局 slot，app 按 slot 分发。8 条在一口时，单 FIFO 的 HOL 阻塞是**app 层**问题（app 必须持续排空）；信用池/物理容量足够。

### 4.6 共享池跨口仲裁的代价 vs 最小侵入替代（如实标注）

- **方案 M1（单个 `app_ctrl` 双口扫描）**：把两套 TCB/事件/占用/retx 反馈都接进一个 app_ctrl，池/配额是内部数组。**代价**：app_ctrl 的扫描/事件/孤儿/WU 全要双口化；它是本工程打补丁最多的模块（WU P1/P2、orphan v4、C15、C17……）⇒ **回归风险最高**。不推荐。
- **方案 M2（推荐，= 本设计）**：**新 `win_pool_mgr`（单池/单记账）+ 两套原样 `app_ctrl`（`EXT_QUOTA=1` 只读配额 + `o_quota_rel` 统一释放）**。配额分配从 app_ctrl 移到 manager；`redge`/`wu`/`fc`/事件/超时/孤儿逻辑**留在原地**、每口一份、同模块二次例化。代价 = app_ctrl 加一个默认关参数 + 只读 `winq` 口 + **统一释放事件**（#3/#4/#5 收口；#2/#6 旁路/关闭，见 §4.3 的 6 类写点与释放路径表）；风险集中在「配额与 redge/wu 的时序」、「同拍双事件」和「**每条非零配额恰好一次释放**」。**这是协调者建议的「共享 window 管理器 + 两套数据面只读配额」。**
- **方案 M3（退路，偏离用户语义）**：两套 `app_ctrl` 各 48KB 内部池（零改动、二次例化）。**偏离**：不是单共享池；6+2/8+0 不能跨口借用；8+0 时一口 48KB（6KB/条）略短于 2.5G/20µs 的 6.25KB。**如实标注**，只在 M2 被红队否决时用。
- **是否迫使 `tcb` 语义分叉？不**：`tcb` 零改动。**是否迫使 `app_ctrl` 分叉？** 加 `EXT_QUOTA` 默认关模式；redge/wu/fc 共享；配额来源切换；C15 关闭；**新增 `o_quota_rel` 统一释放**。这是**受控模式**，不是模块文件分叉；**但这不是零代价**：6 类写点必须逐条旁路（§4.3 表），释放事件必须恰好一次（§4.3 路径表 + §9.1 `G-P3-1b` churn 门）。**本件的判断**：在统一释放事件 + 6 类写点旁路 + `G-P3-1b` 门成立的前提下，**M2 可拆**（不是"语义无法拆"）；但若红队不接受 `o_quota_rel` 这一新增输出（认为释放路径不可穷举/把 app_ctrl 绑死），M2 的代价超过收益 ⇒ **M3**。本件把它列为**开放决策 #1（M2 vs M3），不强行选 M2**。

### 4.7 共享 8 槽重传环（首选）vs 每口 8 槽（退路）

| 项 | 共享 8 槽（首选） | 每口 8 槽（退路） |
|---|---|---|
| 物理 | 新 `retx_pool_shared.v`：8 × `retx_ram #(.N(1))` + **per-slot owner mux**（owner = `slot_port[slot]`） | 每口 `tcp_tx_frame` 内 `retx_ram #(.N(8))`（`EXTERNAL_RETX=0`） |
| BRAM | **128 tile** | **256 tile（净 0 vs 0x2D 的 256）** |
| 总 BRAM | ≈267（+128KB echo） | ≈395 |
| 写口/读口 | 每槽只有一个属主口 ⇒ 每槽 1 写 + 1 读，**无同槽争用**；两口访问不同槽天然并行 | 每口一套，天然隔离 |
| 风险 | 要从 `tcp_tx_frame` **两体**（OVL `:991` / 默认 `:2036`）抽出 `retx_ram` 端口（`EXTERNAL_RETX=1`），并加 owner mux/抽取断言；retx 地址写路径是已知关键族 | 机械二次例化，风险最低 |
| 语义 | **物理单共享 8 槽**，最贴合用户「共用缓存」 | 逻辑共享 8 准入、物理 8+8（8 空闲时浪费 128 tile） |
| 选择 | 若红队接受 retx 抽取/owner mux 的时序风险 | 若首版要最低风险 |

**owner mux 的安全性**：连接的口在 `slot_port[slot]` 建连时写入；同一 slot 在连接存活期只属于一个口（A-1 的 local_ip 决定，不会迁移）。两口同时访问**不同槽** ⇒ 各槽独立；**同槽** ⇒ 结构性不可能（非属主口的 CAM/TCB 不会有该 slot 的 ESTAB）。加 `stat_retx_owner_mismatch`（非属主访问计数，应恒 0）与 `slot<8` 守卫。

**`retx_ram` N 参数的地址宽度**：N=8 时 ring 地址 = `{conn[2:0], w[12:1]}` = **15 位**（每 conn 每 bank 4096 字），**必须同步缩到 15 位；留 4 位 conn 会越界**（S1 §5.1-#1）。N=1（共享 8 槽的每槽实例）时 conn 位宽 0，地址只留 `w[12:1]`。N=16 默认的地址/阵列与今天逐字相同。

---

## 5. HLS 改造

### 5.1 `MAX_TCP_CONN=8`

- `layer_tcp.cpp:10-12` 3→8；`tcp_conn[8]`、`tcp_retrans_buf[8][576]`、`tcp_send_bufs[8][576]`、`tcp_find`/若干 `for` 的 UNROLL 8。
- **面积**：HLS 锚（0x2A 代）= 19,811 LUT / 17,894 FF / 37 BRAM / 4 DSP（`MAX=3`）。8 槽增加：
  - 存储：`tcp_conn` ~8×100 B、`tcp_retrans_buf`/`send_bufs` 各 8×576 = 4,608 B ⇒ 合计 ~10KB；**纸面 +2–4 BRAM**。
  - 逻辑：`tcp_find` 8 比较、状态机 8 份展开、`tcp_maintenance` 扫描 8 ⇒ **纸面 +2–4k LUT / +2–4k FF**。
  - **未测**：HLS 重综合后的实际面积/时序；**必须重跑 `hls/run_hls.tcl` 并归档 `HLS_SRC_HASH`/`HLS_NET_HASH`**。
- **`tcp_stat_no_slot`**：8 槽下仍保留（HLS 槽耗尽计数）。
- **1/2 口兼容**：`MAX=8` 对 1 口/2 口都成立；1 口只是只建 1 条。

### 5.2 `cfg_write` DEL 的 `local_ip` + cfg 1:2 demux

- 现状：`cfg_write(cfg_stream, CFG_CMD_DEL, cid, 0, 0, ...)`（当前 `layer_tcp.cpp:624/653/717/739` 一带；行号会漂移，按符号）。DEL 的 `w2=0` ⇒ **cfg demux 不能按 w2 路由 DEL**。
- 改法（两保险）：
  1. **HLS 侧**：所有 DEL 调用改传 `c.local_ip`（4 处）；ADD 已传 `c.local_ip`（P2 已改）。
  2. **RTL demux**：ADD 按 `w2` 判口并更新 `slot_port[slot]`；DEL 按 **`slot_port[slot]`** 路由（不依赖 w2）；若 DEL 的 w2 非 0 且与 `slot_port` 不一致，计 `stat_cfg_port_mismatch`（应恒 0）。
- **`slow_cfg_demux.v`（新）**：输入 HLS 的 8×32 词流；FSM 计数 0..7，w0 锁 `cmd/slot`，ADD 在 w2 到齐后判口；**8 词整记录先入 1 记录缓冲（8×32 FF）**，再按目标口的 `slow_cfg_adp` 的 `tready` 播放；目标 FIFO 满 ⇒ 反压 HLS（与今天 `slow_cfg_adp` 的 `!f_full` 语义同）。输出 `slot_port[7:0]` 给 `win_pool_mgr`/共享 retx/观测。
- **back-to-back DEL→ADD**（P5d-D6 的 bare SYN 路径）：DEL 先到，按旧 `slot_port` 路由；ADD 后到，更新 `slot_port` 到新口。demux 的顺序保证不丢。

### 5.3 SYN-ACK 通告窗 `TCP_ADV_WND`（P2 遗留的 P3 前置项）

- 现状：`tcp_build_hdr(..., 0xC000, has_opts)`（`layer_tcp.cpp:295`）硬编码。
- P3：新增**运行时输入 `i_tcp_adv_wnd[15:0]`**（HLS top → `tcp_send` → `tcp_build_hdr`），`board/cfg_dual`（C4）接常量 `TCP_ADV_WND = WIN_POOL / EXPECTED_CONNS`（2→48KB，8→12KB）；`board/cfg_shared`（C3）接 0xC000（0x2D 行为）；C1 用归档 0x2A 网表（固定 0xC000）。
- **为什么运行时输入而不是 cflag**：一次综合的 canonical 网表可被 1 口/2 口/不同合同复用；避免两份 HLS 网表（A′ 除外）。HLS top 端口 +16 位，wrapper/TB 各接一处。
- **窗口不收缩的保证**：SYN-ACK 通告 = `TCP_ADV_WND` = `wq_cap` = manager 的授予上限 ⇒ 对端不会按大于配额的值发。若 `EXPECTED_CONNS` 合同被违反（更多连接），第 N+1 条零窗（现有 P5d 语义）；可选 RST 拒绝（open decision）。
- **C3 `cfg_shared`（0x2D）**：继续用归档的 P2 HLS 网表（`MAX=3`，`0xC000`），不重综合 ⇒ 0x2D 的 HLS artifact 逐位不变。**C1 `cfg_single`（0x2A）**：继续用归档的 0x2A 单 IP HLS 网表（`MAX=3`，`0xC000`），artifact 逐位不变。

### 5.4 ARP/ICMP/UDP 双 IP（P2 已实现，复用）

| 文件 | P2 现状 | P3 |
|---|---|---|
| `hls/src/eth_types.h` | `board_ip0_u32/board_ip1_u32/board_ip_match/board_src_ip` | **复用** |
| `layer_ip.cpp` | `board_ip_match(dst) \|\| broadcast` | 复用 |
| `layer_arp.cpp` | request SPA=IP0；reply SPA=`board_src_ip(target)` | 复用 |
| `layer_tcp.cpp` | `local_ip` 字段/`tcp_find(port,ip,local_ip)`/`cfg_write` w2/`tcp_send` sip | 复用 + `MAX=8` + DEL local_ip + adv_wnd |
| `layer_udp.cpp`/`layer_icmp.cpp`/`layer_igmp.cpp`/`udp_echo.cpp` | `rx_dst_ip` → `board_src_ip` | 复用 |
| 每口 UDP app | P2 单 UDP app 用 `DUAL_IP=1` 接受两 IP | **双栈每口 `DUAL_IP=0` + 本口 IP**（保持错口负对照）；HLS 共享层仍双 IP |

**广播语义**：`dst==0xFFFFFFFF` 无口身份 ⇒ `board_src_ip` 返回 IP0（只从 ch1/J8 出）；ARP 不走这里（target_ip 天然有身份）。登记。

### 5.5 1/2 口兼容 + 各配置的 HLS 网表

| 配置 | HLS 网表 | `MAX_TCP_CONN` | `adv_wnd` | 行为 |
|---|---|---|---|---|
| **C1 `cfg_single`（0x2A 锚）** | **归档 0x2A 单 IP 网表** | 3 | 0xC000 | 逐位 artifact 不变 |
| C1 `cfg_single`（P3 源前向） | P3 网表 | 8 | 0xC000（或 0x3000 合同） | 1 口，接受 IP_B（P2 M-2 显式） |
| **C2 `cfg_mirror`（乙）** | 业务口单 IP 网表 | 3（或 8，乙轮定） | 0xC000 | 第二口无 TCP |
| **C3 `cfg_shared`（0x2D 锚）** | **归档 P2 双 IP 网表** | 3 | 0xC000 | 逐位 artifact 不变 |
| **C4 `cfg_dual`（P3）** | P3 双 IP 网表 | 8 | `WIN_POOL/EXPECTED_CONNS` | 2 口，8 连接共享 |

- HLS 源**无产品模式 ifdef**；`MAX_TCP_CONN`/`BOARD_IP_DUAL` 是**构建 cflag**，`adv_wnd` 是运行时输入；配置选择在 `board/`。

### 5.6 逐文件/逐点清单 + 面积估计

| # | 文件 | 改动 | 规模 |
|---|---|---|---|
| 1 | `hls/src/layer_tcp.cpp` | `MAX_TCP_CONN 3→8`；4 处 DEL 传 `c.local_ip`；`tcp_send`/`tcp_build_hdr` 接 `adv_wnd`；`tcp_find` 8 项 | 中 |
| 2 | `hls/src/udp_echo.cpp` | top 新输入 `i_tcp_adv_wnd`，透传 `tcp_rx_process`/`tcp_send` | 小 |
| 3 | `hls/src/eth_types.h` | 无（P2 双 IP 已就位） | 0 |
| 4 | `hls/src/layer_arp.cpp`/`layer_ip.cpp`/`layer_icmp.cpp`/`layer_igmp.cpp`/`layer_udp.cpp` | 无（P2 已双 IP） | 0 |
| 5 | `hls/run_hls.tcl` | P3 变体 `MAX_TCP_CONN=8`/`BOARD_IP_DUAL=1`；归档旧网表 | 小 |
| 6 | `hls/tb/udp_echo_tb.cpp` | 8 连接 × 2 local IP；DEL local_ip；adv_wnd；1/2 口 | 中 |
- **面积（纸面）**：HLS 19,811/17,894/37/4（MAX=3）→ **+2–4k LUT / +2–4k FF / +2–4 BRAM / +0 DSP**（MAX=8 + 8×576×2 存储 + adv_wnd 端口）。**未测**；重综合后以实际为准。

---

## 6. 快路径复制与共享

### 6.1 C4 相对 C3 的第二套增量（同模块二次例化，不复制文件；**不含 C3 已有件**）

> **表头口径（必读）**：`mac_rx_10g` / `mac_tx_10g` / `fifo_async rxcdc+txcdc` / `tx_arb` **在 0x2D/C3 已存在（每口一只/一套）** ⇒ **不计入 C4 的第二套增量**（否则读者按行相加 ≈35k，与小计不符）。小计只计**第二套栈 + 新件 + `EXT_QUOTA` Δ**；**retx 两行二选一**（小计按 `retx_ram` 805 计；共享变体 +0.4–1.0k）。

| 模块 | LUT | FF | BRAM | 级别/依据 |
|---|---|---|---|---|
| `mac_rx_10g` | 1,453 | 911 | 0 | **C3 已有（每口一只）—— 不计入** |
| `mac_tx_10g` | 1,602 | 488 | 0 | **C3 已有（每口一只）—— 不计入**（C2 的 ch0 TX MAC 也是此模块，非新写） |
| `fifo_async` rxcdc + txcdc（76/73×256） | 600–800 | 150–250 | 0 | **C3 已有（每口一套）—— 不计入** |
| `vlan_strip` | 45 | 117 | 0 | C3 是 merge 后一套；C4 每口一套 ⇒ **计入第二套** |
| `rx_classify` | 496 | 534 | 0 | 同上；**计入第二套** |
| `tcp_rx` | 4,323 | 782 | 0 | 锚·P6a |
| `tcp_echo`（**128KB**） | 3,503 | 257 | **32** | 锚·P6a（16 tile 为 64KB；D=16384 ⇒ 32；**第二口**） |
| `tcp_cam` | 1,081 | 2,304 | 0 | 锚·P6a |
| `tcb` | 1,856 | 2,209 | 0 | 锚·P6a |
| `tcp_tx_frame`（不含 retx；含 `TCP_TX_OVL` 第二体） | 4,188+579 = 4,767 | 2,511+91 = 2,602 | 0 | 锚·P6a + 增量 |
| `retx_ram`（每口 8×64KB，**退路**） | 805 | 499 | **128** | 锚·P6a（N=8 半深度纸面） |
| `retx_pool_shared`（8 槽，**首选**） | 1,200–1,800 | 700–1,100 | **128** | 纸面（8×N=1 ring + owner mux；LUT/FF 与两套引擎相当） |
| `app_ctrl`（第 2 套，`EXT_QUOTA=1` + `o_quota_rel`） | 3,503+Δ | 3,319+Δ | 0 | 锚·P6a；Δ = `EXT_QUOTA` 模式（只读配额 + 统一释放）纸面 +200–500/+150–400 |
| `app_pattern`（P7b 版） | 900–1,300 | 550–800 | 0 | 纸面（锚 667/553 + 增量） |
| `app_udp_pattern`（8 路/OVL） | 1,200–1,800 | 650–900 | 0 | 纸面 |
| `udp_split` | 865 | 650 | **1** | 锚·P6a |
| `udp_rx` / `udp_tx_cfg` / `udp_tx_frame` | 263 / 99 / 887+579 | 413 / 163 / 369+91 | 0 | 锚·P6a + 增量 |
| `slow_cfg_adp`（第 2 套） | 411 | 485 | 0 | 锚·P6a |
| `slow_rx_adp` / `slow_tx_adp` | **共享 1 套**（不复制） | — | — | **S1 的 B/C2 表把这两件算进第二套，高估 ~1.7k LUT/0.7k FF/2 BRAM**（见 §0.1-4） |
| `tx_arb` ×2（第二套两级） | 100–200 | 50–100 | 0 | **C3 已有（每口一套）—— 不计入** |
| `win_pool_mgr`（新） | 400–800 | 200–500 | 0 | 纸面 |
| `slow_merge2` / `slow_demux2` / `cfg_demux`（新） | 500–1,000 | 100–300 | 0 | 纸面 |
| **第二套 + 共享新增小计（纸面）** | **≈27–30k LUT** | **≈16–19k FF** | **§6.4** | 修正 S1：−MAC 3.1k/−1.4k、−slow 1.7k/−0.7k、−CDC/arb ~0.9k/~0.3k；+新件/merge ~1–2k |

> **注**：`app_ctrl` 第 2 套是二次例化；`win_pool_mgr` 是共享件（不是 app_ctrl 的第 3 份）。**总 LUT 增量 = 第二套 + 新模块 + `EXT_QUOTA` Δ −（S1 慢适配器高估 + MAC/CDC/arb 已在 C3）≈ 27–30k**；FF ≈ 16–19k。**MAC 两行不在小计内**。

### 6.2 共享 retx vs 每口 retx 的资源（见 §4.7）

- 共享 8 槽：128 tile；`retx_ram` 加 `N` 参数（默认 16），新 `retx_pool_shared` 例化 8×`N=1`。
- 每口 8 槽：两套各 128 tile = 256 tile（净 0 vs 0x2D 的 256）；`tcp_tx_frame` 的 `retx_ram #(.N(8))` 内部例化（`RETX_N=8`）。
- **`tcb` 零改动；`retx_ram` 的 ring 语义零改动**（N 只改连接地址/阵列深度）。

### 6.3 慢路径 merge/demux（单份 HLS 的代价）

- **`slow_merge2`**：两口 `rx_classify` 的 slow 输出（76 位 AXIS）→ 2:1 帧级工作保持 RR → `slow_rx_adp` → HLS。可复用 `rtl/rx_merge2.v`（`STRICT=0`，FIFO 深度可按慢速流量缩小，如 64–256 字；两输入各一个 FIFO 承接上游 `slow_fifo` 反压）。**这是 P3 新增的跨口慢路径耦合**（P2 的 fast merge 退役，但 slow merge 保留）。
- **`slow_demux2`**：HLS TX（73 位，`slow_tx_adp` 已输出 `o_port`）→ 1:2；单生产者、帧内 `o_port` 稳定（side FIFO 128），可用简单 valid 门 + `port` 帧首锁存；或复用 `tx_demux2` 的单生产者配置。`slow_tx_adp` 的源 IP 提取**零改动**。
- **`cfg_demux`**：见 §5.2。
- **成本（纸面）**：+500–1,000 LUT / +100–300 FF / +0 BRAM（FIFO 用 LUTRAM；若用 BRAM 深 FIFO 另计）。S1 的跨口 slow merge/demux 纸面 +0.5–1.0k LUT 与此一致。

### 6.4 BRAM/URAM 账（基线 0x2D **346**，不是 S1 的 348）

| 项 | 0x2D | B/C2S（共享 retx + 128KB echo） | B/C2P（每口 retx + 128KB echo） | A′（共享 retx + 128KB echo） |
|---|---|---|---|---|
| `retx_ram` | 256 | **128**（共享 8 槽） | **256**（8+8） | 128 |
| HLS `udp_echo` | 37 | 37 | 37 | **74**（两份） |
| XDMA | 36 | 36 | 36 | 36 |
| `tcp_echo` ×2 | 16（1 口） | **64**（2×32，128KB/口） | 64 | 64 |
| 慢路径 frame_fifo | 3 | 3（共享 `slow_rx_adp`/`slow_tx_adp` 各 1；第二套 `udp_split` +1） | 3 | 6（两套慢适配器） |
| 其他/余量 | −2（346 与 348 的组成差，**未逐项拆分**） | 同差 | 同差 | 同差 |
| **总计（纸面）** | **346** | **≈267（55.6%）** | **≈395（82.3%）** | **≈304（63.3%）** |
| URAM | 1 | 1 | 1 | 1 |
| DSP | 4 | 4 | 4 | 8 |

- **若保持 64KB echo**（每口 16 tile）：B/C2S ≈235、B/C2P ≈363；但 8+0/12KB 不成立（§4.5）。
- **若选 128KB 池**：池本身不占 BRAM；每口 echo 仍 128KB；8×16KB=128KB 无余量（§4.2）。
- ⚠️ **A′ 的 304/432 未单列第二套 `slow_rx_adp`/`slow_tx_adp` 的 2 个 frame_fifo（+2 tile）**：A′ 有两套慢适配器，B/C2 共享一套；+2 落在表的"其他/余量 −2"与纸面包络内，**不逐 tile 归因**。
- **URAM 不迁移**：`retx_ram` 共享 8 槽仍是 128 tile；无需 29–32 URAM/套；板上 1 个 M1 URAM 不动。
- **组成注**：0x2D placed 346 vs P7B 报告的 348 差 2 tile（XDMA 36/38 口径、frame_fifo 计数），**本件按 346 为锚、差值标"未逐项拆分"**；不据此归因。

---

## 7. 观测面

### 7.1 0x2D 现状（基线）

- **W83/W84** = 每口 TX 帧数（per-port arb 输出 `tvalid && tready && tlast`；32 位自由回卷 **27.487 s @156.25MHz**；差值 mod 2³² + raw/k）。现读 wrapper `:4842-4843`。
- **W0/W79** = 每口 RX 好帧（W0=ch1，W79=ch0）。**两者计数点不同（必须逐字对齐）**：W0 = **ch1 MAC 好帧**（`mac_rx_10g.stat_frames` 口径；MAC 端整帧接受）；W79 现 = `ch0_rx_frames` = `ch0_rx_tvalid && ch0_rx_tready && tlast && tcrs && !terr`，`DUAL_SFP_A` 下 `ch0_rx_tready = ~ch0_fifo_full` ⇒ **计数点在 ch0 FIFO 写接受端（MAC→merge 输入 FIFO 的握手）**，FIFO 满时该帧不计、MAC 丢弃由 W82（`stat_drop`）计。**C4 若把 W79 改成 "ch0 MAC RX 好帧"，必须把计数点上移到 ch0 `mac_rx_10g.stat_frames`（与 W0 同点）**；否则 C3 的 W79 读数与 C4 的 W79 不可直接比，读侧标签/对账式必须同步。
- **W4/W82** = 每口 MAC RX drop（ch1/ch0）。
- **W85..W87 已删**（0x2D backstop-2）：W85（classify 总帧）、W86（ch0 FIFO ovf）、W87（ch0 MAC TX `{abort,frames}`）**不可读**。
- **W43/W20** = ch1（port0）tx 域拍钟/帧；**第二口 ch0 的 tx 域计数器不在快照**（若需，另加字/另开 CDC 镜像；本件首版不加）。
- **W51/W52/W54/W55** = 第一套 app/TX 的计数；**第二套 app 的计数不在快照**（板级第二口内容用对端 NIC/pcap）。

### 7.2 推荐：首版 **NW 85 不加新字**；可选 W85 = 每口已授配额和

- **理由**：0x2D 的 backstop 史 = 加一个快照字可把 WNS 从 +0.042 打到负（backstop-1 `−0.089/726`；删字才回到 `+0.042/0`；#94 不归因，但**风险已实证**）。P3 本身已 +30k LUT 同域；**第一版不冒观测字的风险**。
- **2×10G 的功能判据不需要新字**：
  - 每口 TX：W83/W84（帧）+ 对端每口 NIC `port_rx_bytes/packets`（独立链）。
  - 每口 RX：W0/W79（帧）+ W4/W82（drop）。
  - 共享池行为：xsim 读 `win_pool_mgr` 的 `dbg_pool`/`dbg_port_win*` 与 app_ctrl `0x97/0x9A`；板上用**吞吐/零窗/连接准入**行为判（第 3 条连接被拒/零窗 = 合同被遵守的反证）。
- **可选（第二版/另开构建，预登记 backstop）**：**W85 = `{port_win1_sat16, port_win0_sat16}`**（每口已授配额和，16 位饱和；32 位一字）。语义：2×10G 2 连接 = `0xC000/0xC000`；8 连接 8+0 = `≥0xFFFF`/0（饱和可见分布）。**不是**历史 W85（classify 总帧）；读侧标签必须新写。
  - 若加：NW 86 / `0x174` = W85 / MIR `0x178..0x184` / UNIMPL `0x188`；读侧 `apply_readside` 新阶段 0x2F（20 文件）。
  - **backstop 第一档 = 删 W85**（回到 NW 85 / `0x184`）。
- **最小开发期集**：W83/W84 + W0/W79 + W4/W82（+ 可选 W85）。
- **测试后拆分**：保留 W83/W84/W0/W79/W4/W82（长期产品判据）；W85 若加，测试后由用户裁定保留/删除（倾向删，回到 NW 85）。

### 7.3 读侧

- 首版 NW 85 ⇒ 几何与 0x2D 相同（UNIMPL `0x184`）；只需 **新 BID 阶段 0x2F** + **W79 标签改成"port1/ch0 MAC RX 好帧"** + W0/W4/W82 的标签复核。
- 若加 W85 ⇒ 几何 86 / `0x188`，全部 20 文件 + `check_window` + TB 几何同步；`apply_readside_bid1c.py` 新阶段必须过 `assert_tables`/`assert_defaults`。
- `P7B_BIZ_WINDOW.md` 的 W79 标签同步（N-14 遗留）。

---

## 8. 时序 / 资源 / 时钟 / 复位 / CDC

### 8.1 基线

| 项 | 值 | 出处 |
|---|---|---|
| 0x2D WNS / WHS | **+0.042 / +0.009 ns**（周期 6.400 ⇒ 余量 **0.66%**） | `p11_build_0x2D_20261018/retry/README_FOR_TL.md` §5 |
| 三类失败端点 | 0 / 0 / 0 | 同上 |
| placed | 82,013 LUT / 77,361 FF / 346 BRAM / 1 URAM / 4 DSP / 6 GTYE4 | 同上 |
| 全局最差族（首跑 37 端点） | `u_tcp_tx/u_fifo_b/* → u_tcb/*`（35）+ `u_app_ctrl/o_ev_up → orph_cnt/pw_*`（2） | 同上 §3 |
| 0x2D 最终 WNS 宿主 | 逐档不同（#66）；**不并列比大小** | 同上 |

### 8.2 双栈的时序风险（定性，不给数值）

1. **同一 `dp_clk` 域再放 ~30k LUT**：0x2D 最差族 `u_fifo_b → u_tcb` 与 `o_ev_up → orph` **各出现第二份**；它们已经是 0x2D 的失败族（首跑 37 端点）⇒ 双栈是同族加深。
2. **共享 retx 抽取/owner mux**：retx 写地址路径是历史关键族（`u_tcp_tx FSM state → 256 写地址`，`rtl/retx_ram.v` 头注释）；在 2:1 mux 前加一级组合 ⇒ +1 LUT 级可能。选每口 retx（B/C2P）可消除这一项。
3. **`app_ctrl` 的 `EXT_QUOTA` 只读 `winq` 口**：`winq[scan_id]` 从内部阵列变成 manager 的读 mux；`fq_scan → redge_n` 是 app_ctrl 的已知长链（P0 曾 22 CARRY4/37 级/WNS −3.089；现为流水化）⇒ 只读 mux 可能加一级。**`EXT_QUOTA=0` 的 0x2D 路径不受影响**。
4. **慢 merge/demux**：在 `slow_rx_adp`/HLS 附近，慢速，非 DP 关键路径；但 `slow_merge2` 的 FIFO 反压可能进 `rx_classify` 的 slow 输出门（低扇出）。
5. **观测字**：首版不加 ⇒ 不加快照阵列异步复位族（0x28 的先例）。若加 W85，+96 FF/字×三份；按 0x2D 的 backstop 风险，**第一档删**。
6. **HLS 重综合**：`u_hls/*` 的 MAX=8 展开可能进 DP top-10；构建轮必须定向 STA `-from u_hls/*`（不靠 top-200，见 #66）。

### 8.3 四配置资源/时序表（基线一律相对 C3=0x2D 现读）

| 项 | **C1 `cfg_single`**（0x2A） | **C2 `cfg_mirror`**（乙） | **C3 `cfg_shared`**（0x2D） | **C4 `cfg_dual`**（P3） |
|---|---|---|---|---|
| 身份 | 只连一个端口 | 一个端口转发（第二口无 IP/TCB） | 两个端口共享 10G | 两个端口 10G×2 |
| BID | **0x2A** | 0x2E 或 0x30（乙轮定） | **0x2D** | **0x2F** |
| LUT | **78,248（已上板读数）** | 82,013 + δ_C2（纸面；δ ≈ −1.5–2.5k ⇒ ≈79.5–80.5k） | **82,013（已上板读数）** | 109–112k（纸面） |
| FF | **75,360（已上板）** | 77,361 + δ（纸面；≈ −0.3–0.6k ⇒ ≈76.8–77.1k） | **77,361（已上板）** | 93–96k（纸面） |
| BRAM | **348（已上板）** | 346 + δ（≈0；纸面） | **346（已上板）** | **267**（共享 retx + 128KB echo）/ **395**（每口 retx）〔纸面〕 |
| URAM | 1 | 1 | 1 | 1 |
| DSP | 4 | 4 | 4 | 4（B/C2）/ 8（A′） |
| GTYE4 | 6 | 6 | 6 | 6 |
| WNS / WHS | **+0.039 / +0.010（已上板）** | 纸面/未构建 | **+0.042 / +0.009（已上板）** | **无预测**；闸 WNS>0 |
| 三类失败端点 | **0/0/0（已上板）** | — | **0/0/0（已上板）** | 闸 0/0/0 |
| 板级状态 | **已上板（0x2A，P9 板级轮）** | **未构建** | **已上板（0x2D，P2 板级轮）** | **未构建** |
| **Δ vs C3** | **−3,765 LUT / −2,001 FF / +2 BRAM**（**读数差**，不同输入，非拆刀归因） | δ_C2（纸面；见下注） | **0（基线）** | **+27–30k LUT / +16–19k FF / BRAM 267 或 395**（纸面；**MAC/CDC/arb 已在 C3，不计入**） |
| 依据 | `p9_build_0x2A` README（位流 `aa44a0ed…a3b6`）/ P9 板级 | 纸面（P1（0x2B）只有 ch0 RX MAC；**P2/0x2D 已有 `u_mac_tx_ch0`**，C2 只例化/接线，非新写） | `p11_build_0x2D` retry README（位流 `ecef15f2…e76f`）/ P2 板级 | 本件 §6/§8 纸面 + S1 锚 |

**表注（必须读）**：

1. **C1/C3 是「已上板位流的构建读数」**（板上不能测资源/WNS；"已上板"只指该位流曾烧录并做过板级读数）：C1 = 0x2A（单口；placed 78,248/75,360/348/1/4/6；WNS +0.039/+0.010/0/0/0；BID 0x2A；位流 `aa44a0ed…a3b6`；P9 板级）；C3 = 0x2D（双口共享栈；placed 82,013/77,361/346/1/4/6；WNS +0.042/+0.009/0/0/0；BID 0x2D；位流 `ecef15f2…e76f`；P2 板级）。**C1 的 Δ vs C3 是两个不同输入的构建读数差，不是受控 A/B、不归因**（#94）；它对应 P11 P1/P2 的增量（ch0 MAC/merge/demux/双 IP/观测）。
2. **C2 是纸面**：P1（0x2B）只有 ch0 **RX** MAC；**P2/0x2D 已在树中落地 ch0 TX MAC 例化**（`mac_tx_10g u_mac_tx_ch0`，`board/wrapper_p4.v:3395`，`ifdef DUAL_SFP_A` 内）⇒ **C2 只需在 `cfg_mirror` 中例化/接线该模块（非新写模块），资源估计不变（1,602 LUT / 488 FF）**；另加业务口 RX tap FIFO + 镜像路由（纸面 +1.0–1.5k LUT/+0.3–0.5k FF）。**相对 C3**：删 `rx_merge2`/`tx_demux2`/第二口 arb 树/P2 端口身份提取（纸面 ≈ −2.5–4k LUT/−0.6–1.0k FF），加 tap FIFO + mirror 路由（≈ +1.0–1.5k LUT/+0.3–0.5k FF）⇒ **净 δ_C2 ≈ −1.5–2.5k LUT / −0.3–0.6k FF**（纸面，±30%）。**相对 C1**：需例化 ch0 RX MAC（1,453/911，P1 已有模块）+ ch0 TX MAC（1,602/488，**P2/0x2D 已有模块、非新写**）+ tap/mirror（≈0.4–0.9k LUT）⇒ **≈ +3.5–4k LUT / +1.5–1.9k FF**（纸面）。C2 的 BID/板级未定（乙轮）。
3. **C4 是 P3 纸面增量**：B/C2S（共享 retx + 128KB echo）为主，B/C2P（每口 retx，BRAM 395）/ A′（两份 HLS，BRAM 304/432，DSP 8）见 §3.1/§6.4。**C4 的 WNS 不给预测**；一次构建收口 + 预登记 backstop。
4. **C4 的 HLS 面积**：+2–4k LUT/+2–4k FF/+2–4 BRAM（纸面，MAX=8+adv_wnd；A′ 另加第二份 19.8k/17.9k/37/4）。
5. **基线口径**：本表所有 Δ 一律相对 **C3=0x2D 现读**（82,013/77,361/346）；**不再使用 S1 的 0x2A/0x2B 旧基线**。

**C1/C3 回归构建预期读数（这是闸，不是预测）**：

- **C3 `cfg_shared`（0x2D）重构建**：必须 **WNS > 0、WHS > 0、三类失败端点 0/0/0、DRC 0 Error、`12-4739` 0、隐式网 5 键 0、black box 0**；0x2D 历史锚 = `+0.042/+0.009/0/0/0`，**不承诺重构建 WNS 等于 +0.042**（RTL 编辑 + 放置位移；#63/#64），只承诺 >0 + 0/0/0；行为回归 = P2 板级 B-1/B-2/B-4B/B-5/B-7 + 0x2D 构建门。
- **C1 `cfg_single`（0x2A）重构建**：同上时序门；0x2A 历史锚 = `+0.039/+0.010/0/0/0`；行为回归 = P9 板级 0x2A（孤儿正/负臂 + 回归四臂）+ 0x2A 构建门。
- **若任一回归构建 WNS<0 或 0/0/0 不成立** ⇒ P3 的默认关改动**没有做到零回归** ⇒ 修默认关路径（不是重跑到过），并登记。
- ⚠️ **P2 B-1 的 1G 是台架口径**：P2 B-1 的 sink 用 `--rcvbuf 2920`（小窗；P7b 慢盆笔记的同一口径），**不是 app 的速率上限**；P7b 长流 S3/A 在 **1MB rcvbuf + slow-bowl 免疫**下测到 **9.1–9.3 Gbps**（`p7b_longflow_board/ACCEPT.md`、`p7b_longsend_board/ACCEPT.md`）。C4 的 2×10G 板级必须用后者的 sink 配置；单口回归可用 B-1 的 1G 口径与 C3 对齐。

### 8.4 时钟 / 复位 / CDC

- **PCS 不新增**：现役 `pcs64` 是 2 通道核（`NUM_OF_CORES=2`，ch1=X0Y5=J8、ch0=X0Y4=J7）；双栈只是给 ch0 的 RX/TX 时钟接上第二套消费者（P1/P2 已接）。**没有第二份 PCS/GT**。
- **时钟域**：数据面 = 单 `dp_clk` 156.25MHz（`DP_156MHZ`）；port0 RX = `rx_clk_out_1`→`fifo_async`→dp；port1 RX = `rx_clk_out_0`→`fifo_async`→dp；port0 TX = dp→`txcdc`→`tx_mii_clk_1`；port1 TX = dp→`txcdc_ch0`→`tx_mii_clk_0`。**两套 CDC 都在 P2 已存在**（P2 的 `u_rxcdc_ch0`/`u_txcdc_ch0`）；双栈只是多一套 dp 侧消费者。
- **复位**：ch0 RX MAC 复位 `rstn_rx_sr_0[2] & ~pcs_user_rx_reset_0`（P2 §3.1）；ch0 TX MAC 复位 P2 新增 `rstn_tx_sr_0`。双栈的两套 stack 共用 `dp_rst_n`（与 P2/P6b 同规则）；`win_pool_mgr`/共享 retx 同 `dp_clk/dp_rst_n`。
- **CDC 检查**：构建轮必须 `report_clock_interaction` + `12-4739` 0；P2 的 clock interaction = `g_hw.clk_out0 → g_hw.clk_out0` Timed/Clean，跨钟全 `Ignored / Asynchronous Groups`（36 行）；双栈不新增时钟名，但负载/扇出变，必须复核。
- **共享池/共享 retx 无 CDC**：都在 `dp_clk`；两口的事件/配额/retx 访问都是同域。**没有跨口 CDC**。
- **快照**：W83/W84 在 dp 域；W0/W79/W4/W82 在 ch0/ch1 RX 域（P1/P2 的 ch0 束/现役束）；首版不加字 ⇒ 快照 CDC 束不变。

### 8.5 口径

- **不写"时序已解决"**；不写"WNS 会降 X ns"。0x2D 的 `+0.042` 是唯一可信输入；双栈的时序只能一次构建收口 + backstop。
- **backstop 顺序（预登记，每档 = 新输入）**：① 删可选观测字（首版没有；若第二版加了 W85 则第一档删）；② **共享 retx → 每口 retx**（B/C2S → B/C2P；新输入）；③ **`EXT_QUOTA=1` → M3 每口 48KB**（偏离用户语义；只在 app_ctrl 模式失败时）；④ **A′ 的每口 HLS 保持不变；B/C2 的慢 merge/demux 加 1–2 拍寄存器切片**；⑤ 若仍负 ⇒ **回到 0x2D（P2 单栈）**，P3 设计登记为"当前余量下不可实现"，另开结构轮（不许重跑到过）。

---

## 9. 门 / 构建 / 板级计划

### 9.1 门清单（新增 + 负控）

| 门 | 内容 | 负控（必须红） |
|---|---|---|
| **G-P3-1 `win_pool_mgr` 单元** | 授予/归还/同拍双事件/8+0/6+2/4+4/port_cap/slot_reuse/`Σwinq+pool==WIN_POOL`/`Σport_win==Σwinq`/`port_win≤port_cap`/`stat_rel_dup==0` | ① 双 ev_up 同拍池记账错 ⇒ 红；② `port_cap` 越界 ⇒ 红；③ 配额 0 仍授予 ⇒ 红；④ 动态借还（不应存在）⇒ 红；⑤ rel 时 `winq==0` ⇒ `stat_rel_dup` 非 0 ⇒ 红 |
| **G-P3-1b 8 连接 churn / 释放恰好一次** | 真实 `app_ctrl(EXT_QUOTA=1)` + `win_pool_mgr` 两套；两口 4+4/6+2/8+0；注入 connect/close/timeout（`to_fire`）/orphan（`orph_down_r`）/abort+state=0（`st_req_now`）/slot reuse（C18）；**逐拍**断言 `Σwinq+pool==WIN_POOL`、`Σport_win==Σwinq`、`port_win≤port_cap`、`winq[slot]≥0`、每条槽的**非零** `o_quota_rel` 恰好 1 次、`stat_rel_dup==0` | ① 断开 `to_fire` 的 rel（超时漏还）⇒ 不变量必红；② 断开 `st_req_now` 的 rel（abort 漏还）⇒ 红；③ 断开 `ev_down_i` 的 rel（DEL/孤儿漏还）⇒ 红；④ 绕过 `winq_rd[slot]!=0` 门强制双 rel ⇒ 双还 ⇒ 红；⑤ C18 ev_up 与 rel 同槽双还 ⇒ 红；⑥ 任一释放路径漏 ⇒ 红 |
| **G-P3-2 `app_ctrl EXT_QUOTA` 单元** | `EXT_QUOTA=0` 跑既有 `tb_app_fc`/`tb_p5_flow`/`tb_app_wu` 全绿；`EXT_QUOTA=1` 只读配额 + redge/wu/fc/孤儿不变；配额变化时的 init/redge/wu_mark | ① `EXT_QUOTA=1` 仍用内部池 ⇒ 红；② 只读 `winq` 读到旧值 ⇒ `redge` 错 ⇒ 红；③ 默认 0 的既有判据任一红 |
| **G-P3-3 共享 retx 单元** | 8 槽两引擎、同拍不同槽读写、owner mux、重放内容逐字节、读延迟 2 拍/写 1 拍、slot<8 | ① 非属主访问 ⇒ `stat_retx_owner_mismatch` +1 且数据不损坏；② slot=8 ⇒ 丢弃+计数；③ 跨槽数据串 ⇒ 红 |
| **G-P3-4 慢 merge/demux + cfg demux 单元** | 两 slow 流 RR/帧原子；ADD 按 w2、DEL 按 slot_port；back-to-back DEL→ADD；slot 跨口复用；HLS TX 源 IP→口（ARP/ICMP/SYN-ACK/UDP）；未知口→0 | ① w2 反向 ⇒ 错口（必红）；② DEL 按 w2=0 路由 ⇒ 错误口（必红）；③ 帧内 `o_port` 变化 ⇒ 红；④ slot=8 ⇒ 丢弃 |
| **G-P3-5 HLS csim** | `MAX=8`、双 IP、8 连接 × local_ip、DEL local_ip、adv_wnd、1/2 口、既有 19 TEST | ① `dst=IP_B` 在单 IP 网表被丢（M-2 对照）；② adv_wnd 与 cfg w2 不一致 ⇒ 红；③ 同 peer 双 local_ip 串槽 ⇒ 红 |
| **G-P3-6 双栈全链 wrapper 门** | `P7B_SIM_NOPCS` 两通道注入/捕获；8 连接分布 4+4/6+2/8+0；每口源 IP/帧不串；W83/W84/W0/W79/W4/W82；TX_DIS 单口隔离；**C1 `cfg_single` / C3 `cfg_shared` 门仍绿**（C2 乙轮另跑） | ① 跨口帧（源 IP 错）⇒ 红；② 端口位反转 ⇒ 红；③ 三口同时（8+8 超准入）⇒ 零窗/拒绝符合合同；④ C1/C3 门任一红 |
| **G-P3-7 elaboration 组合** | 现有 c1..c12 + `P11_DUAL` 正控 + `P11_DUAL` 缺 `DUAL_SFP_A`/`P7B`/`DP`/`APP`/`SFP2_MODE_A` 的负控 + `P11_DUAL ∧ SFP2_MODE_B` 冲突 | 任一负控未报对应常量错误 ⇒ 红；`rtl/` 产品模式宏命中 ≠0 ⇒ 红 |
| **G-P3-8 矩阵/指纹** | 新门入册；`paths.txt` 指纹加 `hls/src/*.cpp|*.h`、`hls/run_hls.tcl`、`_proj_10g/p11_p3*/sim/run_*`；`HLS_SRC_HASH`/`NET_HASH`；FROZEN | 指纹漂移未逐条解释 ⇒ 红；HLS 源/网表哈希缺失 ⇒ 红 |

- **2×10G 模型**：全链门用**功能级**两通道（每口 10G 帧率模型/背压，不做 10G 全时长仿真）；速率判据在板级。8 连接 × 2 口的功能吞吐在门里用缩短帧数/有限字节，门断言 = 每口帧/字节计数前进 + 内容逐字节 + 无跨口。
- **常驻矩阵**：现有 21 门（P2 设计 §5.2 说 21→24；以现读 `run_matrix_p4dfix.bat` 为准）+ G-P3-1..6 注册 + G-P3-7/8；矩阵数按实际注册写，不照抄旧数。

### 9.2 构建计划

- **BID/配置**：**C1 = 0x2A（锚，归档）· C3 = 0x2D（锚，归档）· C2 = 0x2E 或 0x30（乙轮定）· C4 = 0x2F**。C1/C3 的 **P3 源回归重建**（默认参数）是**新输入**，建议分配**新 BID**（如 0x30/0x31，构建轮定）并在读侧加阶段；**不得用锚 BID 冒充重建件**（身份/读侧会混）。构建日志回读 `P11_CONFIG=<single|mirror|shared|dual>` + `BUILD_ID_V`。
- **宏（四配置恰选一个，`P11_CFG_SELECT_ONE`）**：
  - **C1**：`P11_CFG_C1=1`；无 `SFP2_MODE_A/B`/`DUAL_SFP_A`/`P11_DUAL`；无第二口数据面。
  - **C2**：`P11_CFG_C2=1` + **`SFP2_MODE_B=1`**；无 `SFP2_MODE_A`/`DUAL_SFP_A`/`P11_DUAL`；补第二口 TX MAC + 业务口 RX tap FIFO + 镜像路由。
  - **C3**：`P11_CFG_C3=1` + `SFP2_MODE_A=1` + `DUAL_SFP_A=1`；无 `P11_DUAL`/`SFP2_MODE_B`。
  - **C4**：`P11_CFG_C4=1` + `SFP2_MODE_A=1` + **`DUAL_SFP_A=1`** + **`P11_DUAL=1`**；无 `SFP2_MODE_B`。
  - 加上 0x2D 的 9 宏（`APP_MODE/DEV_USP/PCIE_OBS/DP_156MHZ/P7B_10G/UDP_TX_OVL/TCP_TX_OVL/SFP2_MODE_A/DUAL_SFP_A`）的公共部分；C1/C2 的甲/乙相关宏按上表裁剪。硬门矩阵见 §2.1。
- **HLS**：**C1 用归档 0x2A 单 IP 网表**；**C2 用业务口单 IP 网表**；**C3 用归档 P2 双 IP 网表**；**C4 用 P3 双 IP 网表（`MAX=8`/`adv_wnd` 输入）**；记录 `HLS_SRC_HASH`/`HLS_NET_HASH`。
- **新件导入（仅 C4）**：`rtl/win_pool_mgr.v`、`rtl/slow_merge2.v`、`rtl/slow_demux2.v`（或复用 `rx_merge2`/`tx_demux2` 的单生产者配置）、`rtl/retx_pool_shared.v`（若共享 retx）、`rtl/cfg_demux.v`；构建后 `P7B_MODULE_RESOLVED` 计数 + **black box/8-3491 日志 0**（不只 cell-count）。
- **一次收口**：WNS>0 / WHS>0 / 三类失败端点 0/0/0 / `12-4739` 0 / 隐式网 5 键 0 / DRC 0 Error / 位流 sha256+BID 归档（#54 写进构建脚本）/ HLS 哈希归档。
- **定向 STA 观察**：`u_tcp_tx/u_fifo_b → u_tcb`（两套）、`u_app_ctrl/o_ev_up → orph`（两套）、`win_pool_mgr` 的 `pool/winq` 锥、`retx` owner mux、`u_hls/*`、慢 merge/demux、`slot_port` 写口。**不靠 top-200 清单**（#66）。
- **backstop**：§8.5 顺序；每档新输入；归档每档 READINGS/INPUT_DIFF。

### 9.3 板级计划（2×10G + 8 连接分布）

**前置**：烧 0x2F + sha256 核；身份门 **BID 0x2F / NW 85（或 86 若加 W85）/ `0x184`（或 `0x188`）/ 2 BARs / LnkSta x4 / `0x08=0` / carrier p0=1 p1=1**；对端 netns/静态邻居/coalescing off（P2 §4.6 配方）；`PIN_CPU=` 见证；**两机开机**。

| # | 动作 | 判据/仪器 | 备注 |
|---|---|---|---|
| B-P3-0 | 入口 + 身份 + `cfg_dual` boot | BID/几何/UNIMPL/2 BARs/x4；`0x08=0`；p0/p1 carrier 1/1 | 对端 `ip -br`/`ethtool` |
| B-P3-1 | **单口回归**（只 J8/IP_A） | **B-1 口径（`--rcvbuf 2920`）1G 级** 与 0x2D 同会话对照（≤0.5% 预登记；若同臂散布 >14% 则【未判定】）；**高码率口径（1MB rcvbuf + slow-bowl 免疫）9G 级** / `mism=0` / `stall=0`；W84≡0、W83>0 | W51/W52/W54/W55；p1 NIC；**无 merge 1 拍气泡**（P3 结构上比 0x2D 少 merge） |
| B-P3-2 | **双口 2×10G（2 连接，EXPECTED_CONNS=2/配额 48KB）** | 两口同时：p1→IP_A 与 p0→IP_B 各一条；**主判据 = 板→对端每口 9G 级**（W83/W84 + 每口对端 NIC；sink 用 **1MB rcvbuf + slow-bowl 免疫**）；板 RX 方向（对端→板）另臂单独测（每口 48KB 窗 + 对端源；P7b B3 口径），**双向 2×10G 作扩展、不混入主判据**；`mism=0`（逐口，若 CPU 允许） | 对端 4 核/两口 coalescing off；**单核 ≤4.72G 史** ⇒ 必须两进程/两核；**同时收 2×9.5 未测**；⚠️ 小窗口径（2920）会把它压到 1G，不是板子能力 |
| B-P3-3 | **8 连接分布**（6+2 / 8+0 / 4+4，配额 12KB） | 8 条全部建连（HLS MAX=8）；每口 W83/W84 与 W0/W79 分布符合；`Σ` 连接 = 8；数据面小流量/逐连接内容（需多连接 app/工具，见 §9.4）；第 9 条被拒/零窗（准入合同） | 若多连接 app 未交，只做**建连 + 准入**，数据面登记【未测】 |
| B-P3-4 | **共享池行为** | 2 连接各 48KB 下无零窗/无收缩；8 连接 12KB 下无零窗；第 3 条（EXPECTED_CONNS=2）零窗/RST = 合同 | 板上无 app 总线 ⇒ 用行为+NIC，不用 `0x97/0x9A`（仅 sim） |
| B-P3-5 | **错口/隔离负控** | TX_DIS bit0 停 J7/ch0、p1 不动；bit1 停 J8/ch1、p0 不动（P2 B-7 已证，复跑）；p1 对 IP_B 的 ARP 无应答（P2 B-3 复跑） | 对端两 ns pcap |
| B-P3-6 | **单口隔离 + 共享 retx 归属** | 只跑 port0 时 port1 的 retx 无写；`stat_retx_owner_mismatch=0`（sim/若可读）；错口负控 | 板侧若无该计数器 ⇒ sim 判 |
| B-P3-7 | **peer 能力 caveat** | 若对端同时收不到 2×9.5：**不判板失败**；分开写「板侧每口 egress（W83/W84+NIC）已证」与「用户态同时收 2×9.5 未测」；内容逐口顺序做 | 全局 #43/#59/#68：先查台架帽 |

### 9.4 app / 台架（P3 必须同时交付的测试载具）

- **2×10G 演示**：**两个 `app_pattern` 实例**（每口一个），各自 `TX_CONTINUOUS=1`、各自 `tcp_echo`/`tcp_tx_frame`/`app_ctrl`（M2 下每口一个 app_ctrl ⇒ **事件天然按口分开，不需要 `o_ev_port` 过滤**；M1 才需要）；对端两个 sink 进程（各绑核/各口 coalescing off）。**这是 P3 的实现范围**，否则 B-P3-2 做不了（P2 B-4A 的单会话限制）。
- **8 连接数据面**：现有 `app_pattern` 是**单会话**（P2 B-4A 已证）。8 连接的数据面测试需要**多连接 app/工具**（读 `tcp_echo` 的 `tid`，按连接分发/校验；或每连接独立 pattern checker）。**登记为 P3 实现项**；若未交，B-P3-3 只做建连/准入，数据面写【未测】，**不许用"建连成功"冒充"8 连接数据面"**。
- **多连接 xsim 门**：G-P3-6 的 8 连接模型覆盖每口帧路由/内容；app 的多连接行为在 G-P3-5/板级补。

---

## 10. 风险 / 开放决策 / backstop

### 10.1 开放决策（需要用户/红队裁定）

| # | 决策 | 选项 | 本件倾向 |
|---|---|---|---|
| 1 | **共享池实现** | **M2（`win_pool_mgr` + 两套 app_ctrl `EXT_QUOTA=1` + `o_quota_rel` 统一释放）** / M1（单 app_ctrl 双口）/ **M3（每口 48KB，偏离语义）** | **M2（附条件：§4.3 的 6 类写点旁路 + 释放恰好一次 + §9.1 `G-P3-1b` churn 门全过）**；若红队判语义不可拆/释放不能证明恰好一次 ⇒ **M3**，不强行 M2 |
| 2 | **retx 共享 vs 每口** | **共享 8 槽（128 tile，物理单共享）** / 每口 8 槽（256 tile，净 0，低风险） | **共享 8 槽首选**；若 retx 抽取/owner mux 时序不过 ⇒ 每口（B/C2P），登记物理 8+8 |
| 3 | **池大小 / 每口物理缓冲** | 96KB + 128KB echo（推荐）/ 128KB + 128KB（无余量）/ 64KB + 60KB cap（8+0 不成立） | **96KB + 128KB** |
| 4 | **合同常量** | `EXPECTED_CONNS=2`（2×10G 演示，48KB）/ 8（8 连接，12KB） | 两个构建常量；2×10G 演示用 2；8 连接测试用 8 |
| 5 | **超额准入** | 零窗（现有 P5d 语义）/ fast path 对零授予发 RST（新行为） | 第一版零窗 + 合同文档；RST 登记 |
| 6 | **A′ vs B/C2** | B/C2（资源低、单 HLS）/ A′（无跨口慢耦合、+20k LUT） | B/C2；A′ 是风险对冲 |
| 7 | **C1/C3 保留** | C1/C3 保留到 P3 收口 / C3 后退役（C1 长期单口锚）/ C3 立即退役 | **C1+C3 保留到 P3 收口**；C3 后由用户裁；C1 长期保留（§2.5） |
| 8 | **BID** | C1=0x2A；C2=0x2E/0x30；C3=0x2D；C4=0x2F；C1/C3 的 P3 源回归重建另分配新 BID | 按左；每配置/每次重建独立 BID |

### 10.2 风险清单（按影响）

1. **时序（最高）**：0x2D 0.66% + 同域 +30k LUT + 两套最差族 + retx/pool mux；无预测；一次构建 + backstop。
2. **共享池语义（app_ctrl `EXT_QUOTA`）**：redge/wu/fc 与配额来源的时序；同拍双事件；默认 0 回归。若红队判分叉 ⇒ M3 偏离。
3. **HLS MAX=8/adv_wnd**：面积/时序未测；HLS 网表重综合；SYN-ACK 窗口与配额一致性；超额准入。
4. **共享 retx 抽取**：`tcp_tx_frame` 两体 + owner mux + retx 关键族；退路每口。
5. **8+0 物理缓冲**：128KB echo 的 `D/AW` 改动 + `app_rx_occ` 饱和 + debug 指针宽度；若不加 ⇒ 8+0 不成立。
6. **app/台架**：双 app 实例 + 多连接 app；对端 2×9.5 同时收未测；单核 ≤4.72G 史。
7. **观测**：首版不加字；若加 W85 的 backstop。
8. **BRAM**：共享 retx 267 / 每口 395 / A′ 304–432；均 ≤480；URAM 1。
9. **防分叉**：第二套必须同模块；`rtl/` 无模式 ifdef；**C1 `cfg_single` 0x2A + C3 `cfg_shared` 0x2D 行为回归**；模板/gate 的实例计数；`P11_CFG_SELECT_ONE` 四配置恰选一。
10. **乙模式**：不在 P3；`P11_DUAL ∧ SFP2_MODE_B` 硬失败；乙的 RX tap→TX MAC 任何 TCP 例化都是错误（gate 断言 `cfg_mirror` 的 `tcp_rx`/`tcb`/`tcp_cam` 实例数 = 业务口数量，第二口 0）。
11. **板 RX 每口 10G 未证（独立于 TX）**：P7b Stage B 的 RX 8-way R1 上游 **4.1G** 是**台架帽**（对端单核 socket）；A7 B3 的 **6.16G** 是**板通告窗帽**；P3 的 48KB 窗（14.5G@27µs）不再是帽 ⇒ 剩下的候选 = `tcp_rx` 190 cyc/seg ≈ **9.6G**（P7b RTL 读值，未板级直测 10G）+ `tcp_echo`/app RX 8-way + 对端源 CPU。**2×10G RX 是独立目标，未测**；不许用 TX 的 9.1G 外推。

### 10.3 backstop（预登记；每档 = 新输入）

1. 删可选观测字（若第二版加了 W85）⇒ NW 85。
2. 共享 retx → 每口 retx（B/C2S → B/C2P）；BRAM 267→395。
3. `EXT_QUOTA=1` → M3 每口 48KB（偏离共享池；只在 app_ctrl 模式失败时；8+0 语义降级）。
4. 慢 merge/demux 加 1–2 拍寄存器切片（切断新组合长链；慢路径延迟可接受）。
5. **abort-to-0x2D**（P2 单栈）⇒ 丢掉 P3 双栈；保留 P3 设计件与 0x2D 回归；另开结构轮。**不许"重跑到过"**。

---

## 11. 不实施（本件边界）

- 本件**只设计**：未改任何 RTL/HLS/脚本/工具；未跑 xsim/Vivado；未构建；未碰板/对端/烧录；未写 git。
- 所有面积/时序增量 = **纸面**（锚 = S1 表 / 0x2D 构建 / 源码）；推断标【推断】；未测标【未测】；未判定标【未判定】。
- 本件**不下 PASS/FAIL 裁定**；「未观测到」≠「不存在」；「不支持」≠「证伪」。
- 本件**不假设拆仓**；单仓四配置的边界见 §2.2；拆仓结论见 §2.6。

---

## 附录 A —— 证据索引（2026-10-18 现读）

**基线/构建**
- `_proj_10g/notes/p11_build_0x2D_20261018/retry/README_FOR_TL.md` §3/§5（0x2D WNS +0.042 / WHS +0.009 / 0/0/0；placed 82,013/77,361/346/1/4/6；首跑 37 端点族；backstop-1 −0.089/726）。
- `_proj_10g/notes/p11_p2a_design_20261018/DESIGN_v2r1.md` §E-6（0x2D 几何 NW 85 / UNIMPL 0x184；P2-2 判据改写）。
- `_proj_10g/notes/p9_dual_sfp_s1_cost_20261018/README.md`（S1：B/C2 367 / A′ 404 / 0x2A 78,248/75,360/348 / 分层锚 / BDP）。
- `_proj_10g/notes/p11_board_p2_0x2D_20261018/README_FOR_TL.md`（P2 板级：B-1 单口 1027–1041 Mbps / B-2 池归还 / B-4A 双口 TCP 结构性不可做 / B-4B UDP 49.3/50.7 / B-5 慢路径 / B-7 TX_DIS / 终态 0x2D）。
- `_proj_10g/notes/p9_dual_sfp_exit_identity_compare_20261018/README.md`（A-1 / CAM+1 对比；A-1 推荐）。

**源码**
- `board/wrapper_p4.v`：`SNAP_NW_P6E=85` / `SNAP_P7BDP_NW=41` / `BUILD_ID_V=32'h2D`；W83/W84 `:4842-4843`；`u_app_ctrl` `:1582`；`u_tcp_rx` `:2160`；`u_cam` `:2337`；`u_tcb` `:2361`；`u_tcp_echo` `:2263`；`u_app` `:1511`；`app_reg_addr/wr/wdata` 静态 `:1547-1549`；`DUAL_SFP_A` 守卫 `:286-320`；构建 9 宏 `board/build_p7b_ku5p.tcl:330`。
- `rtl/app_ctrl.v`：`WIN_POOL=16'hC000` `:276`；`WIN_Q_MAX` `:296`；`rx_occ_bytes` 17 位 `:370`；`fq_calc` `:693-699`；`pool/g_grant/pool_reuse/inc_grant` `:860-900`；C15 `:884-900`；事件 FIFO 102 位 `:462`；`EXT_QUOTA` 新参数（本件设计）。
- `rtl/tcb.v`：N=16、`WIN_CAP` 默认 0xBFFE、wrapper 传 `WIN_CAP_5`；`upd_sel=7` 保留 `:103`；win 门控 `:144-166`。
- `rtl/tcp_cam.v`：N=16、4 元组、`rd_dip` 语义 `:26-27`、`dip_r`/`rd_dip` `:36-75`。
- `rtl/retx_ram.v`：ring 界注释 `:5-11`；16 conn×64KB 两 bank `mem_e/mem_o`；写/读流水 1/2 拍；N 参数（本件设计）。
- `rtl/tcp_tx_frame.v`：OVL `u_retx` `:991`；默认体 `u_retx` `:2036`；`EXTERNAL_RETX`/`RETX_N` 新参数（本件设计）。
- `rtl/tcp_echo.v`：`frame_fifo #(.W(73),.D(8192),.AW(13))` `:93`；`dbg_fifo_wptr/rptr` 14 位 `:50-51`。
- `rtl/frame_fifo.v`：`NB=D/512`、`AW` 指针/满逻辑；D 必须是 2 的幂。
- `rtl/slow_cfg_adp.v`：`w0=(wscale<<16)|(cmd<<8)|slot` `:5`；`slot=w0[3:0]` `:80`；`cmd` `:79`；S_CAM `cam_cfg_dip<=w2` `:148`；DEL 清 CAM `:154-158`；`ev_up/ev_down` `:49-54`。
- `rtl/slow_tx_adp.v`：HLS TX 16 位字节流 / FCS 剥离 / `frame_fifo` / `o_port`（P2）。
- `rtl/app_pattern.v`：单会话 `act_id`；`ev_up/ev_down/ev_slot` 端口 `:55-57`；`P7B_10G` 8 路 `:118` 等。
- `hls/src/layer_tcp.cpp`：`MAX_TCP_CONN 3` `:10-12`；`tcp_conn_t.local_ip` `:96-127`；`tcp_find` `:143-151`；`cfg_write` `:179-201`；DEL 调用 `:624/653/717/739`（行号会漂移）；`tcp_send` sip `:291`；`tcp_build_hdr(...,0xC000,...)` `:295`。
- `hls/src/eth_types.h`：`BOARD_IP_DUAL`/`board_ip0_u32/board_ip1_u32/board_ip_match/board_src_ip` `:111-180`。
- `hls/src/layer_arp.cpp:149,194,201`；`layer_ip.cpp:76`；`layer_icmp.cpp:142`；`layer_igmp.cpp:121`；`layer_udp.cpp:168`；`udp_echo.cpp`（P2 双 IP 点）。

**上游件**
- `_proj_10g/notes/p9_dual_sfp_plan_20261017/DESIGN.md` §0.5（用户裁定：甲/乙、先甲、乙只转发 RX、不同 bitfile；「不用独立连接池」）。
- `_proj_10g/notes/P7B_BRAM_REPORT.md`（348 组成 / URAM 29–32 / X2 列 / S_RING 代价）。
- `_proj_10g/notes/P7B_SINGLE_FLOW_10G_DESIGN.md:258-266`（`TCP_TX_OVL` +579 LUT/+91 FF；`tcp_tx_frame` 第二体 308 FF）。
- `_proj_10g/notes/p7b_longflow_board/ACCEPT.md`（单口 9.108/9.314 Gbps；coalescing；快照变慢）。
- `_proj_10g/notes/P7B_U7_AND_PEER.md:246-278`（SFC9120 双口/p0/p1）。
- `_proj_10g/notes/P7B_OPEN_ITEMS.md:196`（`WIN_POOL=49152` ⇒ RTT ≈39.3µs；srtt 16–27µs）。

---

## 12. 四配置订正 + TL 抽核订正记录（2026-10-18）与核心结论未变确认

- **订正 A（用户四配置）**：此前把 **C1（只连一个端口）折叠进 C3、少列一个配置**；现 §2 按**四配置**重写（C1/C2/C3/C4），目录树四配置、硬门矩阵四配置恰选一、资源/时序表四列（基线一律相对 C3=0x2D 现读）。C1 锚 = **0x2A**（P11 前最近单口板级位流，台账 §10-110/§10-113），C3 锚 = **0x2D**。
- **订正 B（TL 抽核 #1）**：C2 的 ch0 TX MAC **不是新模块**——现树 0x2D/P2 已有 `mac_tx_10g u_mac_tx_ch0`（`board/wrapper_p4.v:3395`，`ifdef DUAL_SFP_A` 内）；P1（0x2B）只有 ch0 RX MAC。C2 只需在 `cfg_mirror` 例化/接线，资源估计不变（1,602 LUT / 488 FF）。§0.1 #17、§2.1 C2 行、§8.3 表注 2 已改。
- **订正 C（TL 抽核 #2）**：§6.1 表把 `mac_rx_10g`/`mac_tx_10g`/`fifo_async`/`tx_arb` 标为 **C3 已有（每口一只/一套）——不计入 C4 第二套增量**；小计从 ≈30–33k/17–20k 修正为 **≈27–30k LUT / ≈16–19k FF**（C4 vs C3；MAC/CDC/arb 已排除）；§0 #11 / §3.1 / §3.4 / §8.3 同步。
- **订正 D（TL 抽核 #3，核心接口缺口）**：`win_pool_mgr` 的归还输入改为 **app_ctrl 的统一释放 `o_quota_rel`/`o_quota_rel_slot`**（不是只接外部 `slow_cfg_adp.ev_down`）。`EXT_QUOTA=1` 时 manager 是 `pool/winq/port_win` 的**唯一属主**；app_ctrl 的 **6 类配额写点逐条旁路**（§4.3 表）；释放路径（外部 DEL / 孤儿 / 超时 / abort/state=0）**每条非零配额恰好一次**（§4.3 路径表）；C18 旧配额归还在 manager 内原子；C15 关闭。新增 **`G-P3-1b` 8 连接 churn 门**（逐拍不变量 + 断路径负控），§4.6/§9.1/§10.1 #1 同步；**M2 vs M3 仍是开放决策，不强行 M2**。
- **核心结论未变（逐条确认）**：
  1. **C4 架构 = B/C2S 不变**：两套同模块快路径二次例化 + 单份双 IP HLS + 新模块 `win_pool_mgr` 单共享 96KB + 两套 app_ctrl 只读配额 + 慢路径 2:1 merge / 1:2 demux（§3）。
  2. **8 连接共享缓存的语义分层、96KB 池、12KB/48KB 场景配额、预配额不可借还、C15 关闭不变**（§4）；M2 的接口按订正 D 具体化（统一释放），**语义仍是单一分配器 + 预配额**。
  3. **`MAX_TCP_CONN=8`、cfg/TX 按 local_ip 分流、SYN-ACK `adv_wnd`、1/2 口兼容不变**（§5）。
  4. **共享 8 槽 retx（128 tile）首选、每口 8 槽（256 tile）退路、B/C2P/A′ 结构不变**（§4.7/§6）；数值按 C4 vs C3 口径修正（订正 C）。
  5. **观测首版 NW 85 不加新字不变**（§7）；W0/W79 的计数点差异已补（W0 = ch1 MAC；W79 = ch0 FIFO 写接受，`tready=~full`）。
  6. **时序风险/一次构建/backstop 不变**（§8/§10）；C4 纸面增量按 C4 vs C3 口径修正为 **+27–30k LUT / +16–19k FF**（MAC/CDC/arb 已在 C3，不计入），资源表四列。
  7. **门/板级/backstop 的 C4 内容不变**（§9/§10）；新增 C1/C2/C3 的配置门/回归锚 + `G-P3-1b` churn 门。
  8. **单仓四配置、2 仓拆仓结论、防分叉纪律不变**（§2.2/§2.6），只是配置数 3→4。
- **本件仍只设计**：不实施、不构建、不上板、未改源/未写 git。

---

*本件 = 纯设计（纸面 + 源码/构建锚）。不含 PASS/FAIL 裁定；所有"达标/不达标"留待用户与后续实测。「未观测到」≠「不存在」；「不支持」≠「证伪」；纸面数字已逐条标"纸面"。*

---

## 13. TL 抽核（2026-10-18，TL 亲核）

**已核锚点（源码/构建现读）**
- `hls/src/layer_tcp.cpp:10-11` `MAX_TCP_CONN 3`；`:295` SYN-ACK `0xC000`。
- `rtl/tcp_echo.v:93` `frame_fifo #(.W(73),.D(8192),.AW(13))`；dbg 指针 14 位。
- `rtl/app_ctrl.v:276/296/370` `WIN_POOL=16'hC000`、`WIN_Q_MAX=16'hC000`、`rx_occ_bytes 17 位`；`fq_calc(q,oc)=q−oc`，`winq` 是**配额**（非剩余信用）⇒ `EXT_QUOTA` 只读配额语义与现实现同构。
- `rtl/retx_ram.v` `w_conn[3:0]`、`mem_*[0:65535]`、地址 `{conn[3:0],w[12:1]}` ⇒ N=8 必须缩 15 位。
- C1 0x2A：78,248 / 75,360 / 348 / 1 URAM / 4 DSP / 6 GT，WNS +0.039/+0.010/0/0/0，位流 `aa44a0ed…a3b6`。
- C3 0x2D：82,013 / 77,361 / 346 / 1 / 4 / 6，WNS +0.042/+0.009/0/0/0，位流 `ecef15f2…e76f`。
- P2 B-1 确为 `--rcvbuf 2920`（`b1_portA.sh:23` 等）。
- W79 现源 = `ch0_rx_frames`（`tvalid && tready && tlast && tcrs && !terr`；DUAL 下 `tready=~ch0_fifo_full`）。
- `u_mac_tx_ch0` 已在 `board/wrapper_p4.v:3395`（`ifdef DUAL_SFP_A` 内）。

**TL 退回并已修订的三条**
1. C2 ch0 TX MAC 措辞（§0.1-17 / §2.1 / §8.3）：P2/0x2D 已落地该例化，非新写模块。
2. §6.1 MAC/CDC/arb 行不计入小计；C4 vs C3 = **+27–30k LUT / +16–19k FF**（§0 #11 / §3.1 / §3.4 / §8.3 同步）。
3. 配额释放路径：`win_pool_mgr` 单点属主；`o_quota_rel` 统一释放（`ev_down_i | to_fire | st_req_now`，`winq_rd[slot]!=0` 抑制重复）；C18 由 manager 原子完成；C15 关闭；G-P3-1b churn 门。

**TL 追加口径（提交前提醒，未改设计正文）**
- **一个 bitstream 只能承载一个配额合同**：2×10G 用 2×48KB，8 连接用 8×12KB；boot writer/编译常量不是运行期切换。若要在同一位流里切两种合同，必须新增 host 可见配额寄存器（P3 非目标，需另立）。
- `EXT_QUOTA=1` 的 M2 是**有条件**的（释放路径穷举 + G-P3-1b 全过）；红队若不接受，退 M3（每口 48KB，明确偏离用户共享语义）。
- 观测首版 NW 85 不加新字，与用户"开发期全量"偏好有偏离；这是时序风险下的显式取舍，留用户/红队裁。
- 2×10G 主判据只写板→对端；板 RX 每口 10G 未证，不许用 TX 外推。
