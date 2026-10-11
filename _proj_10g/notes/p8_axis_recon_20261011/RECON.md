# P8 → AXIS 侦察报告（只读轮 · 2026-10-11）

**任务**：核"把 PCIe 侧（XDMA）从现役 **AXI-MM** 改成 **AXI4-Stream**"的真相、最小改动面、代价与风险、回退与待裁定项。

**边界声明**：本件 = **只读侦察**。**未跑 Vivado**（未开工程 / 未 synth / 未 regen IP / 未读 `get_property`）· 未烧板 · 未 ssh 对端 · 未改任何文件（唯一新增 = 本件）· git 只读。凡"读"到的都来自**磁盘上的文本**（`.xci` / 生成的 stub / `build_p7b_ku5p.tcl` / `wrapper_p4.v` / RTL 头注释 / 报告），带 `文件:行号` 或原文摘录。

**不下 PASS/FAIL 裁定**；"未观测到"一律不写成"不存在"；不确定的一律标【需要验证】并给验证命令。

**三分类**：【事实】（有出处）·【推断】（从事实推，未证）·【需要验证】（给命令）。

---

## §0 一句话结论（五条）

1. **【事实】现役 IP 里根本没有 AXI4-Stream 端口** —— `.xci` 现读 `DMA_ST = 0` / `DMA_MM = 1`（AXI-MM 模式），生成的端口表里只有 `m_axi_*` + `m_axil_*`（无 `s_axis_c2h_*` / `m_axis_h2c_*`）。⇒ **改成 AXIS 必须重生成 IP**（改 `CONFIG.xdma_axi_intf_mm`）；**"IP 里有 AXIS 通道、改造成本骤降"不成立**。
2. **【事实】但代价可控**：本工程的 IP 是**每次构建用 tcl 现场 `create_ip` 出来的**（非 BD、非手改 `.xci`）⇒ "重生成" = **构建脚本加 1 行 + 换 wrapper 的一段端口表 + 换一路搬运 RTL**，不是手工 IP 手术。BAR / 时钟 / 驱动**预计不动**。
3. **【事实】AXIS 恰好命中现役两个痛点**：现役 C2H-MM 路 = `lseek+read` 逐笔寻址（**16 B 对齐硬约束** + **每笔 ~1 ms 固定开销**）⇒ 工具实测只有 ~4 MB/s，且 **K > 16 KB 结构性读不到**（2026-10-11 TCP 臂 T1/T2/T3 三跑响亮 `FATAL: 计数器跳变 4892/4716/5110 字 > 环容量 4096`）；AXIS 路**无寻址、无对齐、无环回绕**，`s_axis_c2h_tready` 提供真背压。
4. **【事实】`axi_regs`（user BAR / AXI4-Lite）不受影响** —— `M_AXI_LITE` 使能只依赖 `XDMA_AXILITE_MASTER`（与接口模式无关，`component.xml` 依赖式现读）。⇒ **快照 71 字窗口 / 控制寄存器 / BID 身份门 / `reg_rw` / mmap 全线照旧**。
5. **【推断】时序面风险低但要重建**：现役 `pcie_axi_aclk` = 250 MHz、WNS **+0.261** / 0 失败端点；全局最差域 = DP（`+0.044` = 余量 0.69%）**不被本改动触碰**。⚠️ 但 IP 重生成 + 换搬运段**会换网表** ⇒ "新网表的时序"只能由**构建后的报告**回答（本件**不写"时序已解决"**）。

---

## §1 现役 XDMA 是怎么进工程的

### 1.1 【事实】不是 BD，是**每次构建现场 `create_ip` + 直接例化**

| 项 | 事实 | 出处 |
|---|---|---|
| 创建方式 | `create_ip -name xdma -vendor xilinx.com -library ip -module_name xdma_0` + `set_property -dict [list CONFIG.* ...]` + `generate_target all` | `board/build_p7b_ku5p.tcl:116-133`（块起始 `sec "P7B_ADD_XDMA"`） |
| 全仓只有两个 IP | 本文件只 `create_ip` 两个：`xxv_ethernet`（`:45`）与 `xdma`（`:117`） | `board/build_p7b_ku5p.tcl` · 另一处登记 `_proj_10g/notes/P7B_GATE4_TOOLING.md:204` |
| 例化点 | `xdma_0 u_pcie_xdma (...)` —— **直接例化在 `wrapper_p4.v`**（不是 BD wrapper） | `board/wrapper_p4.v:4241-4300` |
| 工程目录 | `create_project -force p7b_ku5p_prj`（**每次构建清空重建** ⇒ 旧 `impl_1/` 全丢，全局经验 #54） | `board/build_p7b_ku5p.tcl`（`create_project -force`）· `board/run_build_p7b_ku5p.bat` 的 pre-build archive 块（开工前把上一轮产物抄进 `_proj_10g/notes/p7b_build_archive/<stamp>/`） |
| `.xci` 的性质 | **构建产物**，不是源：`vivado_prj/p7b_ku5p_prj.srcs/sources_1/ip/xdma_0/xdma_0.xci` | 现读磁盘（本轮构建 17:52 量级时间戳） |
| config 从哪读 | **tcl 的 `CONFIG.*` 是唯一源**；`.xci` 里的 `MODELPARAM_VALUE.*` 是它的展开（例：tcl `CONFIG.axi_data_width {128_bit}` ⇒ `.xci` `AXI_DATA_WIDTH = 128`；tcl **未设**接口模式 ⇒ `.xci` 取默认 `xdma_axi_intf_mm = AXI_Memory_Mapped` ⇒ `XDMA_AXI_INTF_MM = 1` / `DMA_MM = 1` / `DMA_ST = 0`） | `board/build_p7b_ku5p.tcl:119-132` vs `vivado_prj/p7b_ku5p_prj.srcs/sources_1/ip/xdma_0/xdma_0.xci`（现读） |
| OOC 综合 | 每次构建跑 `xdma_0_synth_1`（与 `pcs64_synth_1` 同批 launch）⇒ 换 IP 配置 = 这一档重跑 | `board/p7b_ku5p_stdout.txt:291`（`[Sun Oct 11 17:55:06 2026] Launched xdma_0_synth_1, pcs64_synth_1...`）· `vivado_prj/p7b_ku5p_prj.runs/xdma_0_synth_1/` |
| 仿真替身 | 工程 TB 目录里有一个**同名模块的替身** `sim/p6e_pcie/xdma_0_sim_stub.v`（319 行；端口名/位宽与真 IP **逐字一致**，并实现 AXI4-Lite 主机 + `m_axi_read/m_axi_write` 层次任务） | `sim/p6e_pcie/xdma_0_sim_stub.v:1-35` · `sim/p6e_pcie/files.f:215` |

### 1.2 【事实】改造的唯一合法入口 = `board/build_p7b_ku5p.tcl` 的 XDMA 块

```tcl
116: sec "P7B_ADD_XDMA"
117: create_ip -name xdma -vendor xilinx.com -library ip -module_name xdma_0
118: set xip [get_ips xdma_0]
119: set_property -dict [list \
120:     CONFIG.pcie_blk_locn              {X0Y0} \
121:     CONFIG.pf0_device_id              {9034} \
122:     CONFIG.pf0_subsystem_id           {0007} \
123:     CONFIG.ref_clk_freq               {100_MHz} \
124:     CONFIG.mode_selection             {Basic} \
125:     CONFIG.axi_data_width             {128_bit} \
126:     CONFIG.num_queues                 {1} \
127:     CONFIG.axilite_master_en          {true} \
128:     CONFIG.axilite_master_scale       {Megabytes} \
129:     CONFIG.axilite_master_size        {1} \
130:     CONFIG.pl_link_cap_max_link_speed {8.0_GT/s} \
131:     CONFIG.pl_link_cap_max_link_width {X4} \
132: ] $xip
133: generate_target all $xip
```

⚠️ 两条既有纪律（改造时必须继续遵守）：
- ⛔ **不许 GUI 重编 `vivado_prj`**：树里 `vivado_prj/p7b_ku5p_prj.srcs/sources_1/imports/board/wrapper_p4.v` 是**旧版**（BID `0xA` / 0 处 `ack_seen`）⇒ **构建一律只走 `board/run_build_p7b_ku5p.bat`**（`udp_hls_10g/CLAUDE.md` 顶部与 `MEMORY.md` 均点名）。
- ⛔ 构建期间**不得从被构建的工程烧位流**（板级测量前置闸）。

---

## §2 现役 XDMA 的配置真相（逐项摘录）

### 2.1 【事实】`.xci` 的 `MODELPARAM_VALUE.*`（现读，可回核）

来源：`vivado_prj/p7b_ku5p_prj.srcs/sources_1/ip/xdma_0/xdma_0.xci`（本轮构建产物）。

| 类 | 参数 | 值 | 含义 / 后果 |
|---|---|---|---|
| **DMA 接口模式** | `DMA_MM` / `DMA_ST` / `XDMA_AXI_INTF_MM` | **1 / 0 / 1** | **AXI 内存映射**。**AXI4-Stream DMA 通道 = 不存在** |
| 通道数 | `C_C2H_NUM_CHNL` / `C_H2C_NUM_CHNL` | **1 / 1** | 1 个 C2H + 1 个 H2C 引擎（Basic 模式） |
| 通道使能 | `EN_WCHNL_0` / `EN_RCHNL_0` | **TRUE / TRUE** | C2H（卡→宿主；IP 内叫 "W" 通道）+ H2C（宿主→卡；IP 内叫 "R" 通道）都开 |
| 数据宽度 | `AXI_DATA_WIDTH` | **128**（bit） | MM 路 = `m_axi_wdata/rdata[127:0]`；**AXIS 路也用它 = 流位宽**（见 §3.1） |
| 地址宽度 | `AXI_ADDR_WIDTH` | **64** | `m_axi_araddr/awaddr[63:0]` |
| ID 宽度 | `C_M_AXI_ID_WIDTH` | **4** | 但 IP **把 `arid[3:0]`/`awid[3:0]` 核内硬接 0**（明文网表现读） |
| 未完成事务 | `C_M_AXI_NUM_READ` / `NUM_WRITE` / `NUM_READQ` | **8 / 8 / 2** | 引擎的读/写未完成深度 |
| User BAR（AXI-Lite） | `XDMA_AXILITE_MASTER` / `AXILITE_MASTER_APERTURE_SIZE` | **TRUE / 0x0D** | = BAR0（1 MB）→ 我们的 `axi_regs`。**与接口模式无关** |
| PF0 BAR | `PF0_BAR0_APERTURE_SIZE/CONTROL` = `0x0A`/`0x4`；BAR1..5 = `0x05`/`0x0`；`PCIEBAR_NUM=6`；`C_INCLUDE_BAROFFSET_REG=1` | — | 板级实测 = **2 BARs（Region0 1 MB / Region1 64 KB）** |
| 配置 BAR | `XDMA_CONTROL` / `XDMA_APERTURE_SIZE` | `0x4` / `0x09` | XDMA 自己的配置寄存器 BAR（`/dev/xdma0_control`；`reg_rw ... 0x0 w` = `0x1fc00006`） |
| 时钟 | `REF_CLK_FREQ=0`（= 100 MHz）· `CORE_CLK_FREQ=1` · **`USER_CLK_FREQ=2`** | — | **`pcie_axi_aclk` = 250 MHz**（板上时序报告逐字 `{0.000 2.000} 4.000 250.000`） |
| 链路 | `PL_LINK_CAP_MAX_LINK_SPEED=4`（8.0 GT/s）· `PL_LINK_CAP_MAX_LINK_WIDTH=4` | X4 | ⚠️ **能力**是 Gen3 x4；**实际槽位是 PCIe 2.0 x4**（`LnkSta 5.0GT/s x4`） |
| 描述符旁路 | `XDMA_DSC_BYPASS=FALSE` · `DSC_BYPASS_RD/WR=0` · `AXISTEN_IF_ENABLE_MSG_ROUTE=0x00000` · `XDMA_AXIST_BYPASS=FALSE` | — | **不做** AXIS 描述符旁路（本改造也不需要） |
| 队列 / 多 PF | `MULTQ_EN=0` · `PF1_ENABLED=0` · `MSIX_ENABLED=FALSE` · `MSI_ENABLED=TRUE` | — | 单 PF / MSI |
| 器件 / 位置 | `ULTRASCALE_PLUS=TRUE` · `PCIE_BLK_LOCN=0`（X0Y0）· `SELECT_QUAD=GTY_Quad_227` | — | 与 XDC 一致 |

### 2.2 【事实】生成的端口表 = "改动面基线"

来源：`vivado_prj/p7b_ku5p_prj.gen/sources_1/ip/xdma_0/xdma_0_stub.v`（本轮 17:58 生成，`write_verilog -mode synth_stub`）—— **"现役 IP 有什么端口"的权威现读**：

```
module xdma_0(sys_clk, sys_clk_gt, sys_rst_n, user_lnk_up,
  pci_exp_txp[3:0], pci_exp_txn[3:0], pci_exp_rxp[3:0], pci_exp_rxn[3:0],
  axi_aclk, axi_aresetn, usr_irq_req[0:0], usr_irq_ack[0:0], msi_enable, msi_vector_width[2:0],
  m_axi_*      ← 128 位数据 / 64 位地址 / ID 4 位（AW/W/B + AR/R，共 ~60 根）
  m_axil_*     ← 32 位 AXI4-Lite（user BAR → axi_regs）
  cfg_mgmt_*   ← 配置管理（不实现：输入 tie 0 / 输出悬空）
  )
```

- **【事实】没有 `s_axis_c2h_*` / `m_axis_h2c_*`**（逐字端口表核过）。

### 2.3 【事实】AXIS 模式在**器件 / IP 库层面是现成的**（"重生成"实际很轻的根据）

来源（**只读 IP 库文本**，未跑 Vivado）：`C:/AMDDesignTools/2025.2/data/ip/xilinx/xdma_v4_2/component.xml` + `xgui/xdma_v4_2.tcl`：

1. **GUI 参数** `xdma_axi_intf_mm` ∈ {`AXI_Memory_Mapped`, `AXI_Stream`}（`component.xml` 的 choice list 现读）—— **二选一**（DMA 功能模式下不并存）。
2. **MODELPARAM 生成式**（`xdma_v4_2.tcl:12973-12981` 现读）：`AXI_Memory_Mapped → XDMA_AXI_INTF_MM = 1`；`AXI_Stream → XDMA_AXI_INTF_MM = 0`。
3. **端口使能依赖**（`component.xml` 现读，逐条）：
   - `M_AXI` ⇔ `XDMA_AXI_INTF_MM = 1`；
   - `S_AXIS_C2H_0` ⇔ `XDMA_AXI_INTF_MM = 0` **且** `EN_WCHNL_0 = TRUE`；
   - `M_AXIS_H2C_0` ⇔ `XDMA_AXI_INTF_MM = 0` **且** `EN_RCHNL_0 = TRUE`；
   - `M_AXI_LITE` ⇔ `XDMA_AXILITE_MASTER = TRUE`（**与接口模式无关**）。
   ⇒ 现役配置两个通道使能都 TRUE ⇒ 切 AXIS 后 **0 号 C2H 与 0 号 H2C 的流口都会出现**。（IP 核支持 4 通道：`S_AXIS_C2H_0..3` / `M_AXIS_H2C_0..3` 都在 `component.xml` 里 —— 与既有登记 S12「核里有 4 通道 AXIS、顶层没有」一致；**Basic 模式只用 0 号**。）
4. **AXIS 流位宽 = `AXI_DATA_WIDTH`**（`component.xml` 端口宽度依赖式现读）：
   - `s_axis_c2h_tdata_0[AXI_DATA_WIDTH-1:0]` ⇒ 现役配置下 = **128 位**；
   - `tkeep[AXI_DATA_WIDTH/8-1:0]` = **16 位**；`tuser[AXI_DATA_WIDTH/8-1:0]` = **16 位**；`tlast`/`tvalid` 1 位；`tready`（**IP 输出**）。
5. **时钟不变**：`USER_CLK_FREQ` 是 `axisten_freq`（"AXI Clock Frequency"）+ `axi_data_width` 的**纯函数**（`xdma_v4_2.tcl:13146-13180` 现读）⇒ 保持 250 MHz / 128 位 ⇒ `USER_CLK_FREQ` 仍 = 2 ⇒ **`pcie_axi_aclk` 仍 250 MHz，零新增时钟域**。
6. **合法频率组合**（`xdma_v4_2.tcl:8765-8850` 现读）：8.0 GT/s × X4 下 `128_bit → 250 MHz`（唯一）；`256_bit → 125 MHz`。⇒ 想换宽度会**连带换 `axi_aclk` 频率**（256 位 ⇒ 125 MHz ⇒ 整个 pcie 域降频）——**别顺手选**。

---

## §3 改成 AXIS 的最小改动面

### 3.1 FPGA 侧

#### (a) IP 配置：**加 1 行**（其余逐字不动）

```tcl
CONFIG.xdma_axi_intf_mm {AXI_Stream}
```

- **【推断】** 其余 12 项（`pcie_blk_locn` / `pf0_device_id` / `ref_clk_freq` / `mode_selection` / `axi_data_width` / `num_queues` / `axilite_master_*` / `pl_link_cap_*`）**无需改**：BAR 与时钟相关参数与接口模式正交（§2.3-3/5）。
- ⚠️ **【需要验证】"设一个 CONFIG 会静默重置它的从属参数"这条坑**：本构建脚本对 `pcs64` 已经用"**不动点迭代 + 全量回读比对**"防它（`board/build_p7b_ku5p.tcl:47-71`）；**XDMA 那一块没有回读**（`:119-132` 设完就走）⇒ **建议同批照抄那个不动点循环**，否则可能静默丢参数。

#### (b) 端口变化（对照表；宽度按现役 `AXI_DATA_WIDTH=128`）

| 方向 | 现役（MM） | 改后（AXIS） |
|---|---|---|
| 消失 | `m_axi_aw* / w* / b* / ar* / r*`（~60 根） | — |
| 新增 | — | `s_axis_c2h_tdata_0[127:0]` · `tkeep_0[15:0]` · `tlast_0` · `tvalid_0`（**IP 输入**）· `tuser_0[15:0]` · `tready_0`（**IP 输出**） |
| 新增 | — | `m_axis_h2c_tdata_0[127:0]` · `tkeep_0[15:0]` · `tlast_0` · `tvalid_0`（**IP 输出**）· `tuser_0[15:0]` · `tready_0`（**IP 输入**） |
| **不变** | `sys_clk` / `sys_clk_gt` / `sys_rst_n` / `pci_exp_*` / `user_lnk_up` / `axi_aclk` / `axi_aresetn` / `usr_irq_*` / `msi_*` / **`m_axil_*`**（→ `axi_regs`）/ `cfg_mgmt_*` | 同左 |

#### (c) `board/wrapper_p4.v`：**改 3 处**

| # | 位置（现役行号） | 现役内容 | 改法 |
|---|---|---|---|
| 1 | `:4241-4300` XDMA 例化 | 60 根 `m_axi_*` 接 `mir_axi_*` 网线 | 整段换成 12 根 AXIS 信号（+ 新的流搬运模块接线） |
| 2 | `:3848-3900` P2 三件（`u_mir_ring` / `u_mir_c2h` / `u_mir_h2c`）+ `:3745-3800` 的 `mir_axi_*` 网线声明 | 环 + 两个 AXI-MM 从机 | 换成 **1 个新模块**（见 (d)）；`mir_axi_*` 网线整段删除 |
| 3 | `:3901-3950` 两条 **tie-off 分支**（`¬DP_156MHZ` / `¬(APP_MODE∧DP_156MHZ)`） | 把从机响应线钉常量（`arready=0` / `bvalid=0` …） | 换成 AXIS 常量表：`s_axis_c2h_tvalid=0` / `tlast=0` / `tkeep=0` / `tuser=0` / `tdata=0` + `m_axis_h2c_tready=1`（丢弃）+ `mir_dma_cnt` 常量 |

⚠️ 本工程有一条**成文纪律**："按宏叉开写两份端口表的做法本工程已点名禁止 — 坑 8 的同族"（`board/wrapper_p4.v:3737` 逐字）⇒ **不许**在同一 wrapper 里"MM 一套端口表 / AXIS 另一套"并存。回退靠**位流 + git**（§6），不靠宏。

#### (d) 新搬运模块（建议名 `rtl/axis_c2h_stream.v`）—— 现役三件的替代

- **上游合同不变**（这是关键：**镜像侧一个字都不用改**）：吃 `app_rx_mirror` 的 aux 口 `dma_req/dma_gnt/dma_data[63:0]`（**2 个逻辑字 / 拍**，`[31:0]` 先出；主机弹出优先；空态不弹）。出处：`rtl/app_rx_mirror.v:108-126`（合同注释 + 端口声明，现读）+ `board/wrapper_p4.v:3804-3836` 接线。
- **下游新合同**：把 2 次 aux 弹出（= 16 B）拼成 **1 个 128 位 AXIS 拍**：
  - `tdata` = {第 2 个 64b, 第 1 个 64b}（先出的字在**低**位 —— 字节序必须与 `mir_dma_ring` 的"逻辑字 L → 物理字"口径**同代**：环的 `src_data[63:0]` = {后出, 先出}，`rtl/mir_dma_ring.v:57-58` + `:88-95`）；
  - `tvalid` = "本拍凑满 16 B（或已决定提前发）且 dma_en";
  - `tkeep` = 恒 `16'hFFFF`（见 §4.3）；`tlast` = 见 §4.3；`tuser` = 建议恒 0（见 §4.3）；
  - 停等 = `!tready` ⇒ 不弹 aux、保持数据（标准 AXIS 保持合同）。
- **速率核算（【推断】）**：源上界 = **8 B/拍 @ 156.25 MHz = 1.25 GB/s**（tap 侧）；拼装口 = **8 B/拍 @ 250 MHz = 2 GB/s**（每 2 拍发 1 个 128 位拍）⇒ **拼装口 > 源**，不构成新瓶颈（与现役环的 2 字/拍同量级）。
- **控制/计数**：`dma_en`（= `MIR_CTRL[3]`）继续当总开关；`clr` 仍走 `app_rx_mirror.clr_pulse_rd`（环的用法见 `rtl/mir_dma_ring.v:29-31` 的"clr_pulse 归零"冻结语义 + `board/wrapper_p4.v:3848-3859` 接线）⇒ **新模块要接这根线做计数归零**。
- **观测**：`MIR_DMA_CNT(0x148)` 的语义在 AXIS 下 = 见 §3.3；若沿用"已写字数"口径，则新模块只需一个 32 位计数器（**不改快照几何**）。
- **H2C 侧**：建议一个小 sink（`m_axis_h2c_tready = 1'b1` 恒 = "永远接收并丢弃"），与 P2 的 `aximm_h2c_discard` **同一哲学**（结构性消除"等一个永不来的应答"）。⛔ 但它**静默丢弃**（若将来有人真发 H2C 数据，工具会当成功）⇒ 见 §7 待裁定 ②。

#### (e) `axi_regs`（user BAR）：**不受影响**（【事实】）

- 端口表 `.m_axil_*(pcie_*)` 一行不改（`board/wrapper_p4.v:4284-4292`）；
- MIR 四字（`0x13C/0x140/0x144/0x148`）、快照 71 字（`SNAP_NW_P6E = 71`，`board/wrapper_p4.v:3256`）、未实现地址 `0x14C` **几何可不动**（【推断】：只要新模块不新增快照字）；
- `MIR_CTRL` 三位语义（`[0] cap_en / [1] clr toggle / [2] src_sel`）+ `[3] dma_en` **逐字保留**（`_proj_pcie/rtl/axi_regs.v:56-88`）；
- ⚠️ `MIR_STATUS.ver` = 现在 **3**（`_proj_pcie/rtl/axi_regs.v:307-312`）⇒ **改造 = 位语义变了 ⇒ 按既定规则应 bump**（见 §7 待裁定 ⑥）。

### 3.2 驱动侧

#### (a) 【事实】现役驱动与部署面

| 项 | 事实 | 出处 |
|---|---|---|
| 驱动 | **out-of-tree `Xilinx XDMA Reference Driver xdma v2025.2.0`**（不是 in-tree DMAEngine 版） | `_pcie/README.md:12` · `PORT_NOTES.md:3852` |
| 加载 | `insmod /home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/xdma/xdma.ko`（**patched** 版；`modprobe` 会取到 in-tree 那个、不产生 `/dev/xdma*` 节点） | `_pcie/README.md:63-64` · `PORT_NOTES.md:3880-3882` |
| 节点 | 我们的设计下 **21 个 `/dev/xdma*` 节点**，含 `c2h_0` 与 `h2c_0`（零构建项已板级现核） | `_proj_10g/notes/P7B_TL_LEDGER_20261010.md:648` |
| 工具 | `/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools/`：`reg_rw` / `dma_to_device` / `dma_from_device` | `_pcie/README.md` §三 |

#### (b) 【事实】两种模式下 `c2h_0` / `h2c_0` 的语义差（现役 MM 侧已板级现核）

- **MM（现役）**：`/dev/xdma0_c2h_0` 的 **`lseek(卡内字节偏移)` + `read()`** = "从卡内 **AXI 地址空间** 的该地址起读 N 字节"。**板上现核**：`off=0/16/4096/16368 ⇒ ok`；**`off=4/8 ⇒ 首次 -1、再读挂死**（`dmesg: xdma_xfer_submit ... timed out`）—— 根因 = 我们的从机要求 `araddr[3:0]==0`，而 **SLVERR 对引擎不是干净报错**（~8 s 驱动超时）。**每笔固定 ~1 ms 开销**（4 B 与 16 KB 同价）。出处 = `_proj_pcie/p7b_biz/p7b_mir_dump.cpp:196-224`（现读的头注释与 `FdRingIo`）。
- **AXIS（目标）**：`read()` 不再需要地址 —— 引擎把 `s_axis_c2h` 上的**字节流**搬进宿主缓冲；`tlast` 界定"包"。**边界条件**（外部资料，非本机现核）：C2H 流**描述符按页切**、**`tlast` 会提前关闭当前描述符**、C2H 流描述符长度**须为 64 B 的整数倍**、`tkeep` 只在 `tlast` 那一拍可以不满且必须**挤到 LSB**（**这正是 §4.3 要给建议的依据**）。
- **【需要验证·必做】驱动源码侧对"ST 模式"的处理**（本机**全盘无 `dma_ip_drivers` 副本** —— 这是既登记事实，`P7B_PCIE_DATAPATH_DESIGN.md:728` 现读）。验证命令（只读）：
  ```bash
  ssh a@192.168.0.38 "grep -rn 'xdma_xfer_submit\|check_transfer_align\|addr_align\|stream' \
      /home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/{libxdma.c,libxdma.h,cdev_sgdma.c,xdma_mod.h} | head -60"
  ```
  要回答三条：① ST 模式下 `f_pos` 是否仍被当地址（⇒ 16 B 对齐约束是否消失）；② 宿主缓冲的对齐要求（`check_transfer_align` 现核只对 MM 验证过）；③ ST 模式下 `read()` 的完成条件（填满 / `tlast` / 超时）与超时值。
- **【推断】** **驱动不需要换**：同一份驱动同时支持 MM 与 ST（ST 是 IP 侧配置，驱动只搬描述符）。⚠️ 但这条**必须**由上面那条命令证实 —— 若驱动里有按 IP 模式分叉的路径而 2025.2 版对 ST 有额外要求，工具与流程要跟着改。
- **【推断】** **PCIe 枚举/父桥窗不变**：BAR 数与尺寸不变（2 BARs：1 MB + 64 KB）⇒ 既有的"场景 C 要连根端口一起 `remove`+`rescan`"流程不变（`MEMORY.md` / `_pcie/README.md` §二）。

### 3.3 工具侧（`_proj_pcie/p7b_biz/p7b_mir_dump.cpp`）

现役 `--dma` 路径（`p7b_mir_dump.cpp:187-355` 现读）有三件 AXIS 下**要么改、要么废**的东西：

| # | 现役 | AXIS 下 | 建议 |
|---|---|---|---|
| ① 取数 | `FdRingIo::read_at()` = `lseek(物理字×4)` + `read()`，**16 B 对齐 + 补到 4 字**，多读丢弃 | 无地址、无对齐：**平铺 `read(fd, buf, n)`** 连续流 | 新路径（可叫 `--stream`，与 `--dma` 并存 ⇒ 两臂可直接对比） |
| ② 计数器 | `MIR_DMA_CNT(0x148)` = **环已写 32 位字数**（`rtl/mir_dma_ring.v:26-28` 冻结语义） | 无环 ⇒ 语义须重新定义 | **建议**：口径改为"**已交付给 AXIS 口的 32 位字数**"（= 累计 `tvalid&&tready` 拍 × 4 字），名字与地址不变 ⇒ 工具与读侧表改动最小 |
| ③ FATAL | `av > RING_WORDS` ⇒ `exit(2)`（`p7b_mir_dump.cpp:318-322`）= "一次能拿到的量不可能超过环容量" | **无环** ⇒ 这条**结构性失去意义**（AXIS 下"落后"表现为**丢字节**，不是回绕） | **必须替换**，不许留着当装饰。建议换成：**`ΔW70 > 0` ⇒ 响亮报"板侧丢字节"** + `ΔMIR_DMA_CNT`（板侧交付字数）与宿主实收字节的**对账**（差 = 丢弃量的独立见证） |

- 身份门（`MAGIC` / `BID` / 未实现地址 `0x14C`）**逐字保留**（`p7b_mir_dump.cpp:99-107`）—— user BAR 不受影响。
- ⚠️ 现役工具**单线程**；AXIS 下宿主"读之间有空档"会**直接翻译成板侧丢字节**（缓冲只有 2 KB，见 §4.1 的核算）⇒ **工具可能需要改成多笔并发/大块读**（这是改造成败的关键之一，见 §5 风险 R4）。

---

## §4 流控与丢字节语义

### 4.1 【事实】现役缓冲/容量链（AXIS 下不变的部分）

| 段 | 容量 | 出处 | 折合时间（@1.25 GB/s 源） |
|---|---|---|---|
| 镜像暂存 | 16 B（`stg_data[127:0]` + `stg_cnt[4:0]`） | `rtl/app_rx_mirror.v:11-30` | 可忽略 |
| 跨域 FIFO | **64 位 × 256 = 2 KB** | `rtl/app_rx_mirror.v:347`（`fifo_async #(.WIDTH(64), .DEPTH(256), .FWFT(1), .AW(8))`） | **~1.6 µs** |
| （现役）环 | 16 KB（4 bank × 1024 × 32b） | `rtl/mir_dma_ring.v:62-63` | ~13 µs |
| （现役）读侧 | 每笔 `lseek+read` **~1 ms 固定开销** ⇒ 工具 4 MB/s 级 | `p7b_mir_dump.cpp:196-224` · `p8_tcp_0x21_20261011/REPORT.md` §0-3 | — |

⇒ **【推断】AXIS 的因果链**：读侧变成连续流后，"宿主来不及收"**不再表现为环回绕**，而是 `tready` 拉低 → FIFO 填满 → **`drop_bytes`(W70) 上涨**。**这是好事**：丢字节从"要靠事后回绕检测"变成"**板内计数器直接记**"。

### 4.2 【事实】唯一的背压点 = `s_axis_c2h_tready`

- 【事实】结构面：`tready` 是 IP **输出**、我们只能**消费**它（`component.xml` 端口方向现读）⇒ 对板内而言它是**唯一**的下游流控输入。
- 【需要验证】它**由什么决定**：外部资料口径 = "C2H 流由**描述符可用性**门控 —— 宿主每笔 `read()` 提交描述符，描述符耗尽 ⇒ `tready` 低"（PG195/PG344 + AMD 论坛，**本机不可回核**）⇒ 见 §8-②/④ 的命令与实验。
- 板内可用的"容忍空档"只有 **2 KB ≈ 1.6 µs**（§4.1）⇒ **【推断·关键】宿主两次 `read()` 之间的空档只要 > ~1.6 µs 就开始丢**，除非：
  - (i) 宿主**多线程/大块**连续提交（把空档压到 µs 级），或
  - (ii) 板内把缓冲**做大**（可用余量：BRAM 现用 352/480 ⇒ 空 128 tile ≈ 576 KB；**URAM 0/64 ⇒ 全空 2.25 MB**，`p8_build_0x21/REPORT.md` 资源行现读）。
- **建议（供设计件选型）**：AXIS 首版可**先用现役 2 KB 链原样**（改动最小、语义最干净：丢多少 W70 就记多少），把"加多大缓冲"作为**实测后的第二步**（先拿到"空档到底多长"的读数）。

### 4.3 `tlast` / `tkeep` / `tuser` 的置法（**建议 + 依据**）

| 信号 | 建议 | 依据 |
|---|---|---|
| `tkeep` | **恒 `16'hFFFF`**（只在"末拍"允许不满；本用途无末拍） | PG195/PG344 口径：非末拍的 `tkeep` 必须全 1；`tlast` 拍允许不满但须**挤到 LSB**。我们的源是**纯字节流**、每次发满 16 B ⇒ 恒全 1（外部资料现查，见 §8 出处） |
| `tlast` | **两个方案（见下），推荐 A** | `tlast` 的作用 = "关闭当前描述符/界定包"。C2H 流按**页**切描述符 ⇒ `tlast` 落在**非**页边界会让描述符**提前收尾**（多发一次 writeback），读侧就可能拿到**短读** |
| `tuser` | **恒 0** | XDMA 的 C2H `tuser` 用于**描述符旁路**（`XDMA_DSC_BYPASS=FALSE` / `DSC_BYPASS_RD=0` 现役配置下不启用）。⚠️ **【需要验证】**（见 §8-③） |
| `tvalid` | = "有完整 16 B 且 `dma_en=1`" | `MIR_CTRL[3]` 是既有的总闸（`_proj_pcie/rtl/axi_regs.v:73-76`） |
| 复位/停流语义 | 建议：`dma_en` 由 1→0 时**在最后一个整拍上发一次 `tlast`**（"flush 一拍"） | 否则被挂住的描述符**永远填不满** ⇒ 宿主的 `read()` 只能靠驱动超时退出（"停止后一次读挂住"是**可预期的形态**，登记在案） |

**方案 A（推荐）：`tlast` 恒 0 + 停流时 flush 一拍。** 全流 = **一个无限长包** ⇒ 宿主的 `read(N)` 填满 N 字节即返回、字节与字节**连续无缝**（不用处理短读）。风险：**引擎/驱动是否接受"永不 `tlast`"**（外部资料里"描述符被填满即关闭"是常规行为，但**本机无法证实**）⇒ 见 §8-②。
**方案 B（保守）：`tlast` 打在 4 KB 边界（每 256 拍一次）。** 与"描述符 = 页"完全对齐，最贴近驱动预期。代价：宿主 `read()` **必须按 4 KB 的整数倍**取，否则每次都短读（工具逻辑复杂一档）。

---

## §5 代价与风险

### 5.1 【事实】代价

| 项 | 量 | 出处 |
|---|---|---|
| 构建时长 | 0x21 全构建 **17:53 → 18:27 ≈ 34 min**（含 `xdma_0_synth_1` OOC）；IP 换配置 ⇒ 这一档重跑（量级不变） | `board/p7b_ku5p_stdout.txt:291` · `_proj_10g/notes/p8_build_0x21/REPORT.md` |
| 面积 | 减：环（4 bank×1024×32b ⇒ 数个 RAMB）+ 两个 AXI-MM 从机；增：一个拼装/流控模块 ⇒ **净额预计小幅减少**（【推断】，须看构建报告） | `rtl/mir_dma_ring.v:78-96` |
| 时序 | 新逻辑在 `pcie_axi_aclk`（现役 WNS **+0.261** / 0 失败端点）；**DP 域（+0.044 = 全局最差）不触碰** | `board/p7b_ku5p_timing.rpt:218`（pcie 组）· `p8_build_0x21/REPORT.md`（DP 行） |
| 许可 | **无缺口**（XDMA 无需 license key；0x21 构建日志 `License Check failed` 命中 0；本机 license 文件里无 xdma 条目也不需要） | `_proj_10g/notes/p8_build_0x21/` 构建控制台（grep 现核）· `P7B_PCIE_DATAPATH_DESIGN.md` §V1.5-⑪ |

### 5.2 风险清单（按"会不会咬人"排）

- **R1（中）IP 重生成可能**静默**改别的参数** —— 本工程对 `pcs64` 有不动点回读、对 XDMA **没有**。**缓解**：同批给 XDMA 块加"设后全量回读 + 打 `P7B_XDMA_*` 行"，并在验收里核 **BAR 数/尺寸（`lspci -vv` 的 Region0/1）+ `LnkSta x4` + `2 BARs`**。出处：`board/build_p7b_ku5p.tcl:47-71`（可照抄的范式）。
- **R2（中）仿真替身必须同步** —— `sim/p6e_pcie/xdma_0_sim_stub.v` 端口表**逐字对着真 IP**；换 AXIS 后它**必须**改（否则 P6e 全链门**响亮编不过**，这是好事；坏的是**忘了改而另写一套**）。同批要改：`sim/p6e_pcie/files.f:3-17,214-215`（模块清单）+ 该 TB 里 **M1-11 的 `dMIR_DMA_CNT == 600` 一族判据**（它锚在"环 = 2 字/拍"的口径上，`tb_p6e_pcie_wrapper.v:116,550,579`）。
- **R3（中）矩阵覆盖 = 空证据**（**已登记的在飞项**）：`sim/p4gates/run_matrix_p4dfix.bat` 的 17 门**不含** `app_rx_mirror/mir_dma_ring/axi_regs`；`p5_wrapper`（唯一编 `wrapper_p4.v` 的门）走 **`APP_MODE` 单域分支**（`sim/p4gates/p5wrapper_src.f` 头注释逐字）。⇒ **"矩阵 17/17 绿"对本改造同样是空证据**，必须要**新的单元门 + wrapper 全链门**（后者 = `sim/p6e_pcie/run_tb_p6e_pcie.bat` 那一档）。出处：`p8_build_0x21/REPORT.md` §7-④ · `P7B_OPEN_ITEMS.md` §0-37-④。
- **R4（高·设计性）宿主侧"读之间空档"直接变丢字节** —— 见 §4.2。**缓解**：(i) 工具多笔并发/大块读；(ii) 板内加深缓冲（URAM 全空 2.25 MB）；(iii) 接受丢、但由 **W70 + 交付字数**给出**可判读数**。⛔ 不许把"没读到"当"没发生"。
- **R5（低）`read()` 对齐约束** —— MM 下现核"16 B 对齐"是由**我们的从机**（`araddr[3:0]==0`）制造的；AXIS 下地址不参与 ⇒ **【推断】该约束消失**，但**宿主缓冲对齐要求**是驱动侧的、**未核**（§3.2-b 命令）。
- **R6（低）读侧链式同步** —— 任何一次构建换 BID/几何都要跑 `_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py` 的**新阶段**（脚本现到 `EDITS_21`，`apply_readside_bid1c.py:82-87`）；**几何不变则 = BID-only（24 处 / 14 文件，有先例）**；**加新快照字则几何也变**（五处同改，`rtl/aximm_*`/`axi_regs.v` 头注释 §M1 现读）。
- **R7（低）`vivado_prj` 旧源陷阱** —— 与本次无关但会咬人：**只走 `board/run_build_p7b_ku5p.bat`**。
- **R8（低）已知工具侧历史形态** —— 0x21 轮 10 跑里 **4 跑**出现 `FATAL: 计数器跳变 > 环容量`（"fq initial_quantum"假设已被证伪，根因未定位，`P7B_OPEN_ITEMS.md` §0-38）。AXIS 下这条 FATAL 本来就要换掉 ⇒ **该未定位项随之失去载体**（登记：不是"解决了"，是"换路了"）。

---

## §6 回退方案

| 层 | 回退物 | 位置 / 命令 |
|---|---|---|
| **位流（首选）** | 0x21 位流 **sha256 `fbb6fca81076a28b80fcc7a794de698c4253cc36961b7b682887818e1514892c`** / 15,431,261 B | `_proj_10g/notes/p8_board_0x21_20261011/burn/wrapper_p4_0x21.bit`（另有两份副本：同目录 `_proj_10g/notes/p8_build_0x21/wrapper_p4.bit`） |
| 烧录脚本 | `_proj_10g/notes/p8_board_0x21_20261011/burn_0x21.sh`（该轮跑法/身份门/对端部署件齐全） | 同目录 `deploy_0x21.sh` / `final_state.sh` / `runs/` |
| 构建归档 | `_proj_10g/notes/p7b_build_archive/20261011_175317/`（含 `wrapper_p4.bit` + 全部报告 + `SHA256SUMS.txt`，由构建脚本**开工前自动归档**，全局经验 #54） | 现读目录列表 |
| **RTL/工具** | 环 + 两个 AXI-MM 从机 + `--dma` 路径**都留在树里**（本次建议**不删文件**，只从构建 `import_files` 清单摘掉不用者） | `rtl/mir_dma_ring.v` · `rtl/aximm_c2h_win.v` · `rtl/aximm_h2c_discard.v` · `_proj_pcie/p7b_biz/p7b_mir_dump.cpp` |
| 驱动 | **无需回退**（同一份驱动两种模式都用；【推断】+【需要验证】§3.2-b） | — |
| 板级现态 | 板子 = **0x21 + 受控停流**（`0x08 = 0x2` ⇒ `carrier = 0`；`MIR_CTRL = 0`）⇒ 恢复 = `reg_rw /dev/xdma0_user 0x08 w 0x0` 或重烧 | `_proj_10g/notes/p8_board_0x21_20261011/REPORT.md` §2 |

⚠️ 注意：**回退只到"位流层"**（烧回 0x21 = 原行为），因为**不许**在同一个 wrapper 里做双端口表（§3.1-c 纪律）。源码回退 = `git revert`（本件未做任何 git 写操作）。

---

## §7 待裁定清单（每条带我的推荐 + 依据）

| # | 待裁定 | 我的推荐 | 依据 |
|---|---|---|---|
| ① | **AXIS 数据宽度**：64 / 128 / 256 | **保持 128**（不动 `CONFIG.axi_data_width`） | 128 位 = 现役值 ⇒ **`axi_aclk` 仍 250 MHz**（换 256 位会连带降到 125 MHz，`xdma_v4_2.tcl:8840-8845` 现读）；拼装只需 2 拍攒 1 拍（§3.1-d），速率 2 GB/s 仍 > 源 1.25 GB/s |
| ② | **H2C 侧怎么办**：恒 `tready=1`（丢弃）/ 恒 0（不接）/ 真实现 | **恒 `tready=1`（丢弃 sink）**，与 P2 的 `aximm_h2c_discard` 同哲学 | P2 的既定理由逐字："结构性消除'等一个永不来的应答'"（`rtl/aximm_h2c_discard.v:4-10`）；恒 0 会让任何 H2C 事务**挂死到驱动超时**。⚠️ 代价 = 静默丢弃（若要可观测，得加计数器 ⇒ 动几何） |
| ③ | **`tlast` 策略** | **方案 A（恒 0）+ 停流 flush 一拍** | 全流 = 一个无限包 ⇒ 宿主 `read(N)` 语义最干净；方案 B（4 KB 边界）会把"工具必须按 4 KB 取"写进契约。⛔ 两个方案都**必须先做 §8-② 的驱动核对** |
| ④ | **是否保留 MM 路作对照臂** | **构建层不并存**（wrapper 只一份端口表）；**对照靠位流**（0x21 归档件） | 本工程成文纪律禁止按宏叉开两份端口表（`board/wrapper_p4.v:3737` 逐字"按宏叉开写两份端口表的做法本工程已点名禁止 — 坑 8 的同族"）；位流级 A/B = 本工程既有手法（Stage C 的负对照臂就是这么做的） |
| ⑤ | **`MIR_DMA_CNT(0x148)` 新口径** | 改为"**已交付 AXIS 口的 32 位字数**"（地址/单位/名字不变） | 只换语义不换地址 ⇒ 读侧表与工具改动最小；环的旧口径原文见 `rtl/mir_dma_ring.v:26-28`（"已写进环的字数"，该文件保留但不再实例化） |
| ⑥ | **BID / `MIR_STATUS.ver` 是否同批 bump** | **同批**：`BUILD_ID_V` 0x21→0x22 + `ver` 3→4 | 项目纪律：位语义变就 bump（`_proj_pcie/rtl/axi_regs.v:307-309` 逐字"依'位语义变了就 bump'的既定规则"）；BID 每次构建必 bump（`P7B_HANDOFF` §4-#55） |
| ⑦ | **快照几何是否扩**（加"AXIS 交付字数/丢弃计数"等新字） | **首版不扩**（71 字沿用）⇒ 读侧同步 = **BID-only**（24 处/14 文件，有 0x1C/0x1D/0x1E/0x21 四个先例） | 少一个变量 = 少一类失败；`MIR_DMA_CNT` 已能承担"交付量"见证。若后面确需新字，五处同改（`board/wrapper_p4.v:3256` + `axi_regs.v` §M1 + 读侧脚本 + 工具 + 验收脚本） |
| ⑧ | **是否同批加深板内缓冲**（URAM 2.25 MB 全空） | **首版不动**（2 KB 原样），先拿"宿主空档/丢字节"读数再决定 | 先测量后设计（全局经验 #81 的同族精神）；加深缓冲会同时改变丢字节形态与资源读数，**两个变量一次动 = 归因不可判** |
| ⑨ | **工具改造范围**：改 `--dma` 还是新增 `--stream` | **新增 `--stream`**（`--dma` 保留） | 两臂可直接对比（同一位流下 MM 路已不再存在，但代码留着零成本）；也保留"回退到 0x21 位流仍能用旧路径"的能力 |
| ⑩ | **是否同批补 XDMA 参数回读**（R1） | **同批**（`pcs64` 范式照抄） | 静默重置是**已知坑**（`build_p7b_ku5p.tcl:47-71` 的注释逐字"设 CONFIG.CORE 会**静默重置**它的从属参数（闸 1 侦察期实测）"） |

---

## §8 【需要验证】清单（逐条给命令 / 最小 EDA）

| # | 要证的事 | 怎么证 |
|---|---|---|
| ① | **切 `xdma_axi_intf_mm = AXI_Stream` 后的**真实**参数展开与端口表**（含 BAR 参数是否被动） | **需要一轮 EDA 才能定**。最小命令（`create_ip` + `generate_target`，**不必 synth**，约 1–2 min）：
```tcl
create_project -force scratch_axis -part xcku5p-ffvb676-1-e
create_ip -name xdma -vendor xilinx.com -library ip -module_name xdma_0
set xip [get_ips xdma_0]
set_property -dict [list CONFIG.pcie_blk_locn {X0Y0} CONFIG.pf0_device_id {9034} \
  CONFIG.pf0_subsystem_id {0007} CONFIG.ref_clk_freq {100_MHz} CONFIG.mode_selection {Basic} \
  CONFIG.axi_data_width {128_bit} CONFIG.num_queues {1} CONFIG.axilite_master_en {true} \
  CONFIG.axilite_master_scale {Megabytes} CONFIG.axilite_master_size {1} \
  CONFIG.pl_link_cap_max_link_speed {8.0_GT/s} CONFIG.pl_link_cap_max_link_width {X4} \
  CONFIG.xdma_axi_intf_mm {AXI_Stream}] $xip
generate_target all $xip
# 判据: 回读 DMA_MM/DMA_ST/AXI_DATA_WIDTH/USER_CLK_FREQ/PF0_BAR*_APERTURE_SIZE 逐项;
#       端口表 = ..._prj.gen/sources_1/ip/xdma_0/xdma_0_stub.v 的 module 行
```
（做完即删 scratch 工程；**这一步不碰本树任何构建件**） |
| ② | **驱动在 ST 模式下的 `read()` 语义**（`f_pos` 是否仍当地址 / 缓冲对齐 / 完成条件 / 超时） | §3.2-b 的 `grep` 命令（对端只读）；必要时补一次"板上最小 ST 位流 + 4 KB 读"实验 |
| ③ | **`tuser` 在非描述符旁路 ST 模式下是否需要非 0** | 先按 PG195/PG344 口径（tuser 用于旁路）**tie 0**；若板上首测出现"引擎不接受/短读"，再查 PG195 的 `s_axis_c2h_tuser` 字段定义（本机无 PG195 副本 ⇒ 需外部资料或 AMD 论坛） |
| ④ | **"永不 `tlast`"是否被引擎/驱动接受** | 需要一轮 EDA（构建）+ 板级最小实验：发 1 MB 无 `tlast` 数据，看 `read()` 是否返回 1 MB（**判据 = 宿主实收 == 板侧交付字数**） |
| ⑤ | **宿主空档 vs 丢字节的实测曲线**（定缓冲大小） | 板级：固定源速率、扫 `read()` 块大小/线程数，同跑取 `ΔW70`（**判据必须带 `ΔMIR_DMA_CNT` 与宿主字节数的三方对账**） |
| ⑥ | **板上 BAR 布局是否随模式变化** | 烧后 `lspci -vv -s 02:00.0`（核 Region0/Region1 尺寸与 `2 BARs`）+ `LnkSta x4`；与 0x21 的表逐字比 |

---

## §9 本件引用的证据清单（可逐条回核）

**本树（`D:\repo\XCKU5PMini\udp_hls_10g\`）**
- `board/build_p7b_ku5p.tcl`（XDMA 块 `:116-133`；`pcs64` 不动点范式 `:47-71`；文件清单 `:95-101`）
- `board/wrapper_p4.v`（XDMA 例化 `:4241-4300`；P2 三件 `:3848-3900`；tie-off 两条分支 `:3901-3950`；快照几何 `:3256`；`mir_axi_*` 网线声明区 `:3745-3800`）
- `board/run_build_p7b_ku5p.bat`（pre-build archive；硬门）
- `board/p7b_ku5p_stdout.txt`（`:291` OOC launch）· `board/p7b_ku5p_timing.rpt`（`:218` pcie 组 WNS +0.261）· `board/p7b_ku5p_clkinteract.rpt`
- `rtl/app_rx_mirror.v`（aux 口合同 `:108-126`；FIFO `:347`；暂存 `:11-30`）
- `rtl/mir_dma_ring.v`（冻结语义块 `:23-34`；`src_data` 口径 `:57-58` + `:88-95`）
- `rtl/aximm_c2h_win.v`（从机合同 + IP 明文事实节 `:1-50`）· `rtl/aximm_h2c_discard.v`（`:1-40`）
- `_proj_pcie/rtl/axi_regs.v`（MIR 寄存器表 `:46-90`；`ver` `:307-312`）
- `_proj_pcie/p7b_biz/p7b_mir_dump.cpp`（头注释 `:1-60`；`--dma` 路径 `:187-355`；FATAL `:318-322`；身份门 `:99-107`）
- `_pcie/README.md`（驱动 `:12`；`insmod` `:63-64`；PCIe 存亡纪律 §二）
- `PORT_NOTES.md:3852,3880-3882`（驱动身份/判活口径）
- `sim/p6e_pcie/{xdma_0_sim_stub.v,files.f}` · `sim/p4gates/{run_matrix_p4dfix.bat,p5wrapper_src.f}` · `sim/p7b_mirdma/` · `sim/p7b_h2cdisc/` · `sim/p7b_mir/`
- `_proj_10g/notes/P7B_PCIE_DATAPATH_DESIGN.md`（§1.7-① `:15`；`:58`；S12 `:761`；§V1.5 `:719-729`）
- `_proj_10g/notes/P7B_OPEN_ITEMS.md`（§0-37/38 表行）
- `_proj_10g/notes/p8_build_0x21/REPORT.md`（几何/资源/DP 行）· `_proj_10g/notes/p8_board_0x21_20261011/REPORT.md`（板上现态/回退件）· `_proj_10g/notes/p8_tcp_0x21_20261011/REPORT.md`（16 KB 上界 / 81.6% / FATAL 三跑）
- `_proj_10g/notes/P7B_TL_LEDGER_20261010.md`（§10-14…§10-20 阶段链；`:648` 21 节点）
- `_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py`（`STAGES` `:82-87`）

**Vivado 安装（只读 IP 库文本，未跑 Vivado）**
- `C:/AMDDesignTools/2025.2/data/ip/xilinx/xdma_v4_2/component.xml`（`xdma_axi_intf_mm` choice；端口使能依赖式；AXIS 端口宽度依赖式）
- `.../xdma_v4_2/xgui/xdma_v4_2.tcl`（`:12973` XDMA_AXI_INTF_MM；`:8765-8850` 频率合法组合；`:13146-13180` USER_CLK_FREQ）

**外部资料（仅背景，本机不可回核 ⇒ 全部标【需要验证】）**
- PG195（XDMA v4.1）/ PG344（Versal DMA）：C2H 流 `tlast`/`tkeep` 规则、描述符 64 B 整数倍、writeback 语义
- GitHub `Xilinx/dma_ip_drivers` issue #353（stream 模式 `read()` 与 `tlast` 的实测形态）· AMD 论坛"AXI4-Stream C2H tready 由描述符门控"

---

*本件 = 侦察读数与证据，不代行裁定；凡"观测 = 期望"处均带原文出处；凡未证处均标【需要验证】。*
