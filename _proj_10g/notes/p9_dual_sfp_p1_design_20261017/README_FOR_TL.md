# p9_dual_sfp_p1_design_20261017 / README_FOR_TL.md —— P1（ch0 bring-up + 观测面）实施级设计

- 日期：2026-10-17 · 角色 = **纯设计（只读 RTL/脚本）**：未改任何 RTL/脚本/工具，未构建，未跑 xsim/Vivado，未碰板/对端/烧录。
- 产物面：仅本目录。并发写面（`p9_basin_zero_win_*` / `_proj_pcie/p7b_biz/` / `p9_p3_tool_v3_*`）未触碰。
- 上位件：`_proj_10g/notes/p9_dual_sfp_plan_20261017/DESIGN.md`（485 行，§0.5 用户裁定）+ `_proj_10g/notes/p9_dual_sfp_p0_20261017/README_FOR_TL.md`（P0 实测）。
- 判据层口径：**本件不下 PASS/FAIL 裁定**（裁定权在用户/判据所有者）。「未观测到」≠「不存在」。
- 证据标记：**【已证·源码】/【已证·构建】/【已证·板级】/【推断】/【未判定】/【未定位】/【未测】**；所有推算数字标 **“纸面”**。

---

## 0. 一页结论（先读这个）

| # | 结论 | 等级 |
|---|---|---|
| 1 | **ch0 不是 PCS/GT 的死端口**：现役 `pcs64` 是 **2 通道核**（`NUM_OF_CORES=2` / `LANE1=X0Y4` / `LANE2=X0Y5`）；ch0 的 TX 由**常量 IDLE 寄存器**驱动（`wrapper_p4.v:601-608`），RX 数据输出**无消费者**（只有状态 XOR 折叠成 W39[30] 的 1 位签名，`:3665-3670` / `:3753`）。所谓“死”= **数据面单实例只挂在 ch1**，不是 PCS 能力缺失 | 【已证·源码】 |
| 2 | P0 已把“J7 模块 + 第二根 AOC + ch0 TX 通路 + 对端 p0 块锁”抬到**板级已证**，且 `0x08` bit0（`sfp1_tx_dis`）负对照有牙、单口隔离成立（关 ch0 不影响 p1） | 【已证·板级】P0 README |
| 3 | **P1 = 给 ch0 挂一个 `mac_rx_10g` + 把它的状态/计数接进快照；PCS/GT/参考钟/复位序列零改动；ch1 数据面零改动；不改任何流宽、不改 CAM/TCB** | 【推断】（本件设计） |
| 4 | 推荐观测面 = **+7 字（W76..W82）**：ch0 PCS 状态 / ch0 PCS 事件（BER 代理）/ LOS+模式 / ch0 RX 好帧 / 载荷字节 / FCS 错 / 丢帧。以**工作树 0x2A（76 字 / `0x160`）为基** ⇒ **83 字 / 未实现地址 `0x17C`**。成本 **纸面 ≈ +1.5k LUT / +1.8k FF / +0 BRAM / +0 URAM** | 【推断】 |
| 5 | ⛔ **P1 必须新增一个“快照汇合超时”机制**：ch0 计数器束的 `clk_b = rx_clk_out_0`（CDR 恢复钟）；若该钟停（拔线/LOS 负对照）而无超时，**整个 83 字窗口会永久不可读**（`snap_valid_all` 等不到该束）。设计 = 逐代 arming + 4096 拍超时 + `SNAP_STATUS[7]` 标“本代 ch0 束缺失/陈旧” | 【推断】（防御性设计；`rx_clk_out_0` 停钟行为 **【未判定】**） |
| 6 | **甲模式在“独立 IP”裁定下可以走“无标签”路线**：两个板 IP 使帧的 IP 头天然携带“哪个口” ⇒ RX 侧**不需要 77 位端口标签、CAM 不需要 +1 位**；出向只需按连接的**本地 IP**（CAM 的 `dip`）选口。这是对 plan §2-S2「CAM+1 位 + 流加宽」的**简化**，也是本件的主要设计增量 | 【推断】（依据 `slow_cfg_adp.v:7,148`：CAM 的 `dip` = HLS 上报的 `local_ip`） |
| 7 | **乙模式 = 无 IP、只把 ch0 RX 原始帧镜像出去**；P1 只交付“可复用的 76 位 RX tap + 计数”，镜像目的地留 P3。**ch0 TX 在 P1/P2乙 继续发常量 IDLE** | 【推断】 |
| 8 | 时序基线**必须按两代并列**：**工作树 = 0x2A**（76 字 / `0x160` / **WNS `+0.039` = 0.61%** / placed 78,248 LUT / 75,360 FF）；**板上现役 = 0x28**（75 字 / `0x15C` / **WNS `+0.065` = 1.02%** / 77,631 LUT / 75,086 FF）。P1 是一次构建收口，按最薄的 0.61% 预算 | 【已证·构建】`p9_build_0x2A_20261017/README_FOR_TL.md`；`p9_build_0x28/REPORT.md` |
| 9 | BID 建议：**P1-甲 = `0x2B`；P1-乙（同几何、仅模式常量）= `0x2C`**（0x29/0x2A 已占用；0x2C 可留到乙位流轮） | 【推断】 |
| 10 | ⛔ **最大的非 RTL 风险不是时序，而是门覆盖**：常驻矩阵 19 门里的 `p5_wrapper` **只编 `-d APP_MODE`**（不编 `P7B_10G/DP_156MHZ/PCIE_OBS`，见 `sim/p4gates/run_matrix_p4dfix.bat:206-211`）；`p6e` 全链门 **不编 `P7B_10G`**（`sim/p6e_pcie/run_tb_p6e_pcie.bat:24`）。**P1 的 ch0 逻辑只有 `_proj_10g/p7b_chain/` 门能看见**。建议把 `p7b_chain` 注册成矩阵第 20 门 | 【已证·源码】 |

---

## 0.1 先读订正：派单描述与本轮现读的三处不符（不迁就）

| # | 派单/plan 的描述 | 本轮现读 | 处理 |
|---|---|---|---|
| 1 | “0x28 现役几何（75 字 / `0x15C`）、WNS `+0.065` / 1.02%” | **工作树不是 0x28**：`BUILD_ID_V = 32'h0000002A`（`wrapper_p4.v:4479`）、`SNAP_NW_P6E = 76`（`:3394`）、未实现地址 `0x160`（`:3391` 注释）、`PERSIST_EN(1'b1)`（`:2276` 已还原）。0x2A 构建读数 = **WNS `+0.039` / WHS `+0.010` / 三类失败端点 `0/0/0`**、placed **78,248 LUT / 75,360 FF / 348 BRAM / 1 URAM / 6 GTYE4**。**板上现役仍是 0x28**（0x2A 的板级正结果已出、现役资格待用户裁） | 本件同时给两代几何表（§3.2）；推荐以 **0x2A 为构建基** |
| 2 | “ch0 当前为何是死端口（是否只例化了 1 core / ch0 TX/RX 未接 / CARRIER 只跟 ch1）” | **不是 1 core**：`build_p7b_ku5p.tcl:48-59` = `NUM_OF_CORES 2` / `LANE1 X0Y4` / `LANE2 X0Y5`；生成产物 `ip_0`/`ip_1` 逐核回读 X0Y4/X0Y5。**ch0 TX 已接**（常量 IDLE 寄存器，不是悬空）；**ch0 RX 数据未接**（无消费者）。**FPGA 内没有 “CARRIER” 信号** —— “carrier” 是**对端网卡的 PCS 视图**；板内“只有 ch1 是业务口”的原因是**数据面单实例只连了 `rx_mii_*_1`/`tx_mii_*_1`** | 按现读设计 |
| 3 | “`rtl/` 中的 MAC/PCS 封装” | **10G MAC 不在 `rtl/`**：在 `_proj_10g/p7b_mac/rtl/{mac_rx_10g.v,mac_tx_10g.v,crc32_64.v}`（`build_p7b_ku5p.tcl:111-112`）；`rtl/` 里的同名近亲是 **1G 版** `mac_rx_64.v`/`mac_tx_64.v`。PCS 封装 = `board/wrapper_p4.v` 里的 `pcs64 u_pcs`（`:430`）+ 仿真 socket `board/p7b_pcs_stub.v` | 引用时不拿错世代 |

另：plan §2-S2 的“CAM +1 位 + 流 76→77”在本件里被**降级为备选** —— 用户 §0.5 的“甲方案单独 IP”使“IP 头即端口身份”成立（§4.4）。这是**设计细化**，不是对 plan 的否定：同 IP 双口/未来 N 口仍需要端口位。

---

## 1. 现状核对（精确到文件:行号；全部 2026-10-17 现读）

### 1.1 ch0 死端口的具体原因（逐条）

| # | 事实 | 位置（现读） | 后果 |
|---|---|---|---|
| 1 | `pcs64 u_pcs` 是**一个实例、两通道成对端口**：`_0` = ch0（X0Y4 = J7），`_1` = ch1（X0Y5 = J8） | `board/wrapper_p4.v:430-563`；ch0 端口 `:437-481`，ch1 端口 `:483-527` | PCS/GT/共享逻辑对两口都已存在 |
| 2 | ch0 **TX 已驱动**：`(* dont_touch *) reg [63:0] p7b_ch0_idle_d` / `[7:0] p7b_ch0_idle_c`，`always @(posedge tx_mii_clk_0)` 恒 `64'h0707070707070707` / `8'hFF`（全 lane `/I/`） | `:601-608` | 链路合法、对端可块锁（P0 已证）；**不是悬空** |
| 3 | ch0 **RX 数据无消费者**：`rx_mii_d_0`/`rx_mii_c_0` 只在 `u_pcs` 端口连接处出现（`:452-453`），没有任何 MAC/逻辑读它们 | `:349-350` 声明；`:452-453` 连接 | 综合可安全修剪 ch0 RX 数据通路 |
| 4 | ch0 的**除时钟输出外的全部状态/控制输出**（`gt_refclk_out`/`rxrecclkout_0` 刻意排除，`:3671-3672`）XOR 折叠成 1 位 `pcs_ch0_sig`，进 **W39[30]** | `:3665-3670`（签名）；`:3753`（装配 W39） | ch0 状态**不可逐位读**；但该签名同时是“ch0 输出有真实负载”的结构保证（否则 `opt_design` 会死在 `MDRV-1`/`Opt 31-67`，`:3653-3663` 有两次实测记录） |
| 5 | 唯一 TX 出口 = `mac_tx_10g u_mac_tx`，只接 `tx_mii_d_1`/`tx_mii_c_1` | `:2917-2939`（`.xgmii_txd(tx_mii_d_1)` `:2926`，`.xgmii_txc(tx_mii_c_1)` `:2927`） | ch0 TX 没有业务帧源 |
| 6 | 唯一 RX 入口 = `mac_rx_10g u_mac_rx`，只接 `rx_mii_d_1`/`rx_mii_c_1` | `:854-890`（`.xgmii_rxd(rx_mii_d_1)` `:857`，`.xgmii_rxc(rx_mii_c_1)` `:858`） | ch0 RX 没有去向 |
| 7 | RX 跨域 FIFO `u_rxcdc` 只接 `u_mac_rx` 的输出 | `:932-943` | 单口假设 |
| 8 | `gmii_clk`/`tx_fe_clk` 两个域别名只指向 **ch1** 的 PCS 时钟 | `:699-704`（`gmii_clk = rx_clk_out_1`、`tx_fe_clk = tx_mii_clk_1`） | ch0 的两个时钟没有域别名/消费者 |
| 9 | ch0 的复位/时钟：`rx_core_clk_0 = rx_clk_out_0` 自环（`:633`）；`pcs_rx_reset_0`/`pcs_tx_reset_0` 钉 0（`:636-637`）；`qpllreset_in_0` 钉 0（`:530`） | 同上 | 两通道共用 QPLL0 / `MGTREFCLK0_225`（156.25 MHz）；**任何 GT 复位动作会同时扰动两口** |
| 10 | `sfp1_rx_los` / `sfp2_rx_los` 端口在、XDC 在，但 wrapper 里**无任何消费者** | 端口声明 `:199,:201`；`grep los` 只命中端口声明 | LOS 从未进过快照 |
| 11 | `sfp1_tx_dis = pcie_scratch[0]` / `sfp2_tx_dis = pcie_scratch[1]`（仅在 `P7B_10G ∧ PCIE_OBS`） | `:4467-4475` | ch0 发射门已可远程控制（P0 负对照用的就是 bit0） |

**一句话根因**：P7b 从第一天起就按“**全系统只有一根 AOC、接 J8**”做单实例数据面（`P7B_GATE2` 的历史事实），ch0 只保留“发 IDLE + 1 位签名”这两个最小合法负载。**P1 的“接入”100% 在数据面与观测面，PCS/GT 侧零改动。**

### 1.2 参考钟 / 复位 / 时钟域（P1 不许碰的部分）

| 项 | 现读事实 | 位置 |
|---|---|---|
| 参考钟 | 核心板 Y2 = **156.25 MHz** → `MGTREFCLK0_225`（V7/V6），两通道共用；`156.25 × 66 = 10.3125 GHz` | `board/ku5p_p7b_gt.xdc:27-32`；仓根 `CLAUDE.md` §1 |
| PLL | 两子核 `TX_PLL_TYPE = RX_PLL_TYPE = QPLL0`；`qpllreset_in_0` 是 common 级、恒 0 | `build_p7b_ku5p.tcl:48-59`；`wrapper_p4.v:530` |
| PCS 总复位 | `sys_reset_p7b = ~p7b_por_n`；POR 计数器 `P7B_POR_BITS = 20`（10.5 ms） | `:618-630` |
| ch0 RX 钟 | `rx_clk_out_0`（PCS 的 CDR 恢复钟）；`rx_core_clk_0` 自环回核 | `:633`；`p9_build_0x2A` 的 clock utilization 报告有 `rxoutclk_out[0]` |
| ch0 TX 钟 | `tx_mii_clk_0`（QPLL0 派生） | `:603`（常量 IDLE 寄存器用它） |
| CDC 约束 | `set_clock_groups -asynchronous` 三组：`sys_clk_100` 系 / `pcie_axi_aclk` 系 / `gtrefclk0` 系（`-include_generated_clocks`） | `board/ku5p_p7b_cdc.xdc:36-39` |
| SFP 控制脚实测映射 | `SFP1_TX_DIS=C11` / `SFP1_RX_LOS=B11` / `SFP2_TX_DIS=D9` / `SFP2_RX_LOS=C9`（厂商两份 XDC 都对调了） | `ku5p_p7b_gt.xdc:34-38` |
| 位流纪律 | 构建只走 `board/run_build_p7b_ku5p.bat`；`12-4739` 0 命中是硬门 | `P7B_LOOP_HANDOFF.md` §6-B-7 |

⚠️ **P1 不得新增 XDC 组**：新增的 `snap_cdc` 束 `clk_b = rx_clk_out_0` 应已被 `gtrefclk0` 的 `-include_generated_clocks` 覆盖（与现有 `u_snap_p7bfe` 的 `gmii_clk = rx_clk_out_1` 同型）——【推断】；构建轮必须用 `report_clock_interaction` + `12-4739` grep 复核。

### 1.3 数据面单实例假设（P1 不动、P2 才动；逐点清单）

| # | 位置（现读） | 单口假设 |
|---|---|---|
| 1 | `wrapper_p4.v:854-890` `mac_rx_10g u_mac_rx`（只挂 `rx_mii_*_1`） | RX 单入口 |
| 2 | `:932-943` `fifo_async(76×256) u_rxcdc` | RX 单跨界 |
| 3 | `rtl/vlan_strip.v`（单 AXIS 口；`RESYNC_EN` 参数） | 单流 |
| 4 | `rtl/rx_classify.v:26-66`（单 `s_axis_*`；`FW=76`；字 FIFO 深度 16） | 单入口、无端口维度 |
| 5 | `:2069` `tcp_cam u_cam`；`rtl/tcp_cam.v:9-33`（键 = `(sip,dip,sport,dport)`） | 4 元组身份 |
| 6 | `rtl/tcb.v`（16 槽） | 全局槽池 |
| 7 | `:2276` `tcp_tx_frame u_tcp_tx`（`cam_rd_*` 读回 dmac/sip/sport/dport；**未用 `rd_dip`**） | 出口恒 ch1 |
| 8 | `:2436` `udp_split` → `:2564` `slow_rx_adp` → HLS `udp_echo` → `:2610` `slow_tx_adp` | 慢路径无端口概念 |
| 9 | `:2743` `udp_tx_cfg`（单 peer 表 `peer_mac/peer_ip`，`rtl/udp_tx_cfg.v:66-77`） | 单 peer |
| 10 | `rtl/app_ctrl.v:28-33` 事件字 `{kind,slot,peer_mac,peer_port,peer_ip}` = 102 位，无端口位 | app 看不到来源口 |
| 11 | `:2865` `tx_arb u_tx_arb` → `:2891` `fifo_async(73×256) u_txcdc` → `:2917` `mac_tx_10g` | TX 单出口 |
| 12 | `:2814` `tx_arb u_tx_udp_arb`（UDP 压 HLS） | —— |

### 1.4 观测面现状（P1 要扩的基座）

- 快照 = **76 字**（`SNAP_NW_P6E`，`wrapper_p4.v:3394`），未实现地址 **`0x160`**（word 88；`0x20 + 4×76 + 16`）。
- 五束并行：`snap_seq` 的 FE(14)/DP(22) + P7b 的 `p7bfe`(3)/`p7bdp`(36)/`tx`(5)；装配 = `snap_dout_all`（`:4263-4304`，**逐项写出、新增一律落 MSB 端**）。
- **W39 = PCS 状态束**（`:3745-3761`）：`[30]` = `pcs_ch0_sig`（1 位签名），`[29:2]` = ch1 逐位状态；**ch0 无独立可观测位**。
- **W40 = PCS 事件束**（`:3761`）：4 个 8 位饱和计数器（ferr/bad/erv/vcc），**只服务 ch1**。
- LOS：两个端口**无消费者**（§1.1-#10）。
- 每字成本：**≈ +96 FF**（`snap_cdc.hold_b` 32 + `dout_a` 32 + `snap_words_r` 阵列 32 三份）。出处 = `P7B_LOOP_HANDOFF.md:430` + 仓根 `CLAUDE.md`。
- 现役快照完成门：`snap_valid_all = snap_valid & p7bfe_seen & p7bdp_seen & tx_seen`（`:4246`）；`snap_busy` = 四束 busy 的 OR（`:4248`）。

### 1.5 资源/时序基线（两代并列，⛔ 不归因、不比大小，#66）

| 项 | 0x28（板上现役） | **0x2A（工作树）** |
|---|---|---|
| BID / 字数 / 未实现 | `0x28` / 75 / `0x15C` | **`0x2A` / 76 / `0x160`** |
| WNS / WHS | `+0.065` / `+0.010`（1.02%） | **`+0.039` / `+0.010`（0.61%）** |
| 三类失败端点 | 0/0/0 | **0/0/0** |
| placed LUT / FF | 77,631 / 75,086 | **78,248 / 75,360** |
| BRAM / URAM / DSP / GTYE4 | 348 / 1 / 4 / 6 | **348 / 1 / 4 / 6** |
| 全局 WNS 宿主 | 快照阵列异步复位族（`user_reset_reg → snap_words_r_reg[*]/CLR`，recovery） | **DP 域 setup**：`u_tcp_tx/u_fifo_b/rptr_reg[3]/C → u_app/stg_reg[26]/D`（19 级，logic 1.855 / route 4.371） |
| 出处 | `p9_build_0x28/REPORT.md:93,100,121-129` | `p9_build_0x2A_20261017/README_FOR_TL.md` §② |

⚠️ **P1 的时序预算按 `+0.039`（0.61%）算**，不是 1.02%。两代宿主/检查类型不同（recovery vs setup），只并列。

---

## 2. ch0 与 ch1 并存方案

### 2.1 P1（两模式共同基础）——最小 diff

P1 只做四件事：

1. **给 ch0 挂一手 `mac_rx_10g`**（时钟 = `rx_clk_out_0`，复位 = `reset_n` 同步 + `~pcs_user_rx_reset_0`）。
2. **把 ch0 RX 输出变成一个固定的 76 位 tap**（`tdata/tkeep/tvalid/tready/tlast/tuser/tcrs/terr`），P1 用一个**真实 sink**消费它（计数好帧/载荷字节），**不接数据面**。
3. **把 ch0 状态/计数/LOS 接进快照**（§3）。
4. **ch0 TX 保持常量 IDLE**；**ch1 数据面、PCS/GT、XDC、时钟组一字不改**。

为什么 sink 必须是“真消费者”而不是 `assign tready = 1'b1` 后把输出悬空：若输出流无负载，综合可能把 MAC 内部 FIFO 的读侧修剪掉 ⇒ FIFO 填满 ⇒ 后续帧走 `stat_drop_full`，**帧计数会变成“丢帧计数”**。sink 的 `tvalid/tlast` 有真实负载即可保住读侧（§3.1 W79/W80 的源就是 sink）。

**P1 的“两模式共同基础”接口合同（先冻结，P2/P3 直接挂）**：

```
ch0_rx_tap = {tdata[63:0], tkeep[7:0], tuser, tlast, tcrs, terr}   // 76 bit, AXIS, rx_clk_out_0 域
             + tvalid / tready
合同 = 与 mac_rx_10g / mac_rx_64 的输出合同逐字相同（tdata[63:56]=帧首字节；SOP 满对齐；
       TLAST 的 tcrs=FCS 正确；TERM 六元组 = {0,0,tlast=1,tuser=0,tcrs=0,terr=1}）
       ⇒ P2 的 fifo_async(76→77 或 76) / rx_merge2 / 镜像器可直接接
```

### 2.2 甲模式（P2）——单栈双口 + 独立 IP

**推荐架构（“IP 头即端口身份”的无标签路线）**：

```
ch0: mac_rx_10g ─→ fifo_async(76×256) ─┐
                                        ├─→ rx_merge2（dp 单域、帧级互斥、无标签）─→ vlan_strip ─→ rx_classify ─→ …
ch1: mac_rx_10g ─→ fifo_async(76×256) ─┘                                        （宽度全部保持 76）
```

- **RX 合并**：`rx_merge2` = `rtl/tx_arb.v` 的同款帧级 2:1 结构（空闲选路、锁到 TLAST、帧间 1 拍重仲裁）。**两路各自跨域**（`rx_clk_out_0` 与 `rx_clk_out_1` 互不相关）⇒ 合并器只能在 `dp_clk` 单域，**禁止双时钟仲裁**。
- **为什么可以无标签**：两个板 IP 不同 ⇒ 帧的 `dip`（板本地 IP）天然区分连接；`slow_cfg_adp.v:7,148` 已经把 HLS 上报的 `w2 = local_ip` 写进 CAM 的 `dip`。所以 `tcp_cam` 的 4 元组键**已经**能区分两口连接，**不需要 +1 位 port 字段**。
- **出口选口**：
  - TCP fast path：`tcp_tx_frame` 读 CAM 时需要 `rd_dip`（本地 IP）—— 现读它只用了 `cam_rd_sip/sport/dport/dmac`（`wrapper_p4.v:2325-2329`），**没用 `cam_rd_dip`**。P2 的最小改法 = 给 `tcp_tx_frame` 增加 `cam_rd_dip` 输入 + 一个 `o_port` 输出（或直接在 wrapper 侧用 `cam_rd_id` 经 CAM 的 `rd_dip` 组合口判口），`port = (rd_dip == BOARD_IP_PORT1)`。
  - 慢路径（HLS）：HLS 的 TX 帧若按“被寻址的本地 IP”填源 IP，则源 IP 就是口身份；在 `slow_tx_adp` 出口用一个**固定字节偏移的源 IP 提取**（IPv4 源 IP = 帧字节 26..29）或让 HLS 直接给一个 port 边带。若 HLS 不改，则退化为 `dst_ip → port` 学习表（plan §2-S2 的原方案）。
  - UDP app：`udp_split` 的 meta 只带了 `src_ip/src_port/len`（`rtl/udp_split.v:209-213`），**没有 dst_ip**；P2 需要给 `udp_tx_cfg` 的 peer 表加“本地 IP/端口位”，或给 `udp_rx` 的 meta 增加 `dst_ip`。
- **TX 分流**：`tx_arb`（TCP 严格优先）之后、`u_txcdc` **之前**插入 `tx_split2`（帧级、按 per-frame `port` 位选路），每路各自 `fifo_async(73×256)` + `mac_tx_10g`。⚠️ plan 写的“`fifo_async(73→74)`”应订正为 **73 位、两条**：端口位在 split 处被消费，**不进 FIFO**；FIFO 读侧必须各自挂自己的 `tx_mii_clk_0/1` 域，所以 split 必须在 CDC 之前。
- **ch0 TX**：P2 用 `mac_tx_10g` 替代常量 IDLE（否则多驱动）。`rst_n = rstn_tx_sr_0[2] & ~pcs_user_tx_reset_0`，时钟 = `tx_mii_clk_0`。
- **ch0 BB 的 BDP/窗口**：`WIN_POOL = 49152 B` 是**全局**池（16 槽共享）；单路 10G 的 BDP 在 RTT > ~39 µs 时不够（plan §0.5 的硬约束）。P2/P3 必须现取 `ss -ti` 作见证；P1 不承诺速率。

**备选架构（同 IP 双口 / 未来 N 口）**：plan §2-S2 的“端口标签贯穿 + CAM +1 位”。本件**不推荐**在甲模式首选，因为用户已裁定“单独 IP”，无标签路线少改 4 个流宽/2 个接口。若将来要求两口同 IP，则回到该方案。

### 2.3 乙模式（P3）——无 IP、只转发 RX

- **RX**：ch0 `mac_rx_10g` → `fifo_async(76×256)` → dp → **原始帧镜像**（帧级 fanout，满则丢整帧 + 计数）。目的地候选见 §4.5。
- **TX**：ch0 继续常量 IDLE（或 P3 用 `mac_tx_10g` 发 IDLE）；**不建连、不回 ARP/ICMP/SYN-ACK**。
- **不碰**：`vlan_strip`/`rx_classify`/`tcp_rx`/`tcp_cam`/`tcb`/`app_ctrl`/HLS。慢路径对 ch0 完全不可见。
- **模式闸**：`SFP2_MODE_B_SEL` 在 ch0 tap 的出口处二选一（甲 = 进 `rx_merge2`；乙 = 进镜像器）。**同一份源码、两个宏、两个 bitfile**。

### 2.4 改动点清单（P1 必须做；P2/P3 只列接口）

> 行号 = 2026-10-17 现读的工作树（0x2A）。所有 P1 RTL 改动包在 `ifdef P7B_10G` 内；默认构建（无 `P7B_10G`）的端口表/数据面逐位不变。快照几何改动在 `ifdef PCIE_OBS` 内。

| # | 文件:行号（现读） | 改动 | 守卫 | 轮次 |
|---|---|---|---|---|
| 1 | `board/wrapper_p4.v:346-352` | 在 P7B 线网块加 `wire gmii_clk_0; wire tx_fe_clk_0;`（ch0 域别名） | `P7B_10G` | P1 |
| 2 | `wrapper_p4.v:699-704` | 加 `assign gmii_clk_0 = rx_clk_out_0; assign tx_fe_clk_0 = tx_mii_clk_0;` | `P7B_10G` | P1 |
| 3 | `wrapper_p4.v:639-650` | 加 ch0 复位同步器：`(* ASYNC_REG *) reg [2:0] rstn_rx_sr_0`（`rx_clk_out_0` 域）、`rst_n_ch0 = rstn_rx_sr_0[2] & ~pcs_user_rx_reset_0` | `P7B_10G` | P1 |
| 4 | `wrapper_p4.v:819-845`（ch1 tap 线网旁） | 加 ch0 tap 线网：`ch0_rx_tdata/tkeep/tvalid/tready/tlast/tuser/tcrs/terr` + `ch0_rx_frames/bytes`（sink 计数） | `P7B_10G` | P1 |
| 5 | `wrapper_p4.v:890` 之后（`u_mac_rx` 实例之后、`else` 之前） | 例化 `mac_rx_10g u_mac_rx_ch0`：`.clk(gmii_clk_0)`、`.rst_n(rst_n_ch0)`、`.xgmii_rxd(rx_mii_d_0)`、`.xgmii_rxc(rx_mii_c_0)`、输出接 ch0 tap、`stat_crc_err`/`stat_drop` 接观测线 | `P7B_10G` | P1 |
| 6 | 同处 | ch0 sink：`assign ch0_rx_tready = 1'b1;` + `always @(posedge gmii_clk_0)` 计好帧（`tvalid&&tready&&tlast&&tcrs`）与载荷字节（`Σpopc(tkeep)`，帧内累加、TLAST 且 `tcrs` 才提交） | `P7B_10G` | P1 |
| 7 | `wrapper_p4.v:3651-3761`（ch1 PCS 状态/事件段旁） | 加 ch0 版 3FF 同步 + 事件计数器：`pcs0_*_sr`、`pcs0_ferr_evt` 等；装配 `pcs0_status_bundle`（**与 W39 同位域**）与 `pcs0_evt_bundle`（**与 W40 同位域**） | `P7B_10G` | P1 |
| 8 | 同段 | LOS：`sfp1_rx_los`/`sfp2_rx_los` 各 3FF 同步进 `dp_clk` + 上电 priming（复位后前 3 拍只建基线、不计数）+ 8 位饱和沿计数；装配 `los_bundle`（含 `SFP2_MODE_B_SEL`） | `P7B_10G` | P1 |
| 9 | `wrapper_p4.v:3415` | `SNAP_P7BDP_NW 36 → 39`（加槽 36/37/38 = W76/W77/W78）；新增 `localparam SNAP_CH0_NW = 4` | `PCIE_OBS` | P1 |
| 10 | `wrapper_p4.v:3394` | `SNAP_NW_P6E 76 → 83`（+7 字）；注释里的未实现地址 `0x160 → 0x17C` | `PCIE_OBS` | P1 |
| 11 | `wrapper_p4.v:4163-4208` | `p7bdp_din[36/37/38]` 三条显式 assign（**不要并进 `gi<12` 的 generate**，理由同 `:4179-4184`） | `PCIE_OBS` | P1 |
| 12 | `wrapper_p4.v:4210-4227` | 新 `snap_cdc #(.W(32), .NW(4)) u_snap_ch0`：`.clk_b(rx_clk_out_0)`、`.din_b({ch0_mac_drop, ch0_mac_crc_err, ch0_rx_bytes, ch0_rx_frames})`；非 P7B 支 = 常量 0、无实例 | `PCIE_OBS` + `P7B_10G` | P1 |
| 13 | `wrapper_p4.v:4233-4248` | 快照完成门改造：`snap_valid_main` 锁存 + ch0 逐代 arming + 4096 拍超时 + 1 拍 `snap_valid_all` 脉冲 + `snap_busy` 含 pending（**§3.3 的完整设计**） | `PCIE_OBS` | P1 |
| 14 | `wrapper_p4.v:4263-4304` | `snap_dout_all` 顶部（MSB 端）加 7 项，**顺序 = W82,W81,W80,W79,W78,W77,W76**（= `ch0[3],ch0[2],ch0[1],ch0[0],p7bdp[38],p7bdp[37],p7bdp[36]`，再往下才是原来的 W75=`p7bdp[35]`）；**拼接项数必须恰 = 83** | `PCIE_OBS` | P1 |
| 15 | `wrapper_p4.v:4479` | `BUILD_ID_V = 0x2A → 0x2B`（甲）；乙 = `0x2C` | `PCIE_OBS` | P1 |
| 16 | `wrapper_p4.v:4960` | `.SNAP_NW(SNAP_NW_P6E)` 自动跟随（仅注释更新）；`.ch0_snap_to(ch0_snap_to)` 新端口 | `PCIE_OBS` | P1 |
| 17 | `_proj_pcie/rtl/axi_regs.v:192` 后 | 新输入 `ch0_snap_to`；`snap_status`（`:406`）的 `9'd0` → `8'd0, ch0_snap_to` ⇒ **`SNAP_STATUS[7]` = 本代 ch0 束缺失/陈旧** | —— | P1 |
| 18 | `board/p7b_pcs_stub.v:150-157,210-263` | **仿真专用**：① 把共享的 `rx_clk` 拆成 `rx_clk_0`/`rx_clk_1`（`rx_clk_out_0/1` 各接一个），使 P1 的超时臂能**只停 ch0**；② 把 ch0/ch1 共享的 status reg 拆成 `*_0`/`*_1` 两套（默认 ch0 也 link-up），使 W76/W39 可被独立 force | sim only | P1 |
| 19 | `_proj_10g/p7b_chain/sim/tb_p7b_chain.v:1440-1520` | 快照组：`0x160 → 0x17C`；加 W76/W77/W78 强制生产者检查；加 ch0 注入臂（`inj_d0/inj_c0` 第二队列）→ W79/W80 计数；加 LOS 翻转 → W78 沿计数；加超时臂（force ch0 rx 时钟停） | sim only | P1 |
| 20 | `sim/p6e_pcie/tb_p6e_pcie_wrapper.v:448,545-548` / `tb_p6e_pcie_counters.v` | 几何/未实现地址：`0x160 → 0x17C`；MIR 四址 `0x150/0x154/0x158/0x15C → 0x16C/0x170/0x174/0x178`；非 P7B 支断言 W76..W82 读 0 | sim only | P1 |
| 21 | `_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py:480-494` | 新增阶段 ⑯ `0x2B`（83 字 / `0x17C`；BID+几何+标签+MIR 常量）与 ⑰ `0x2C`（乙；BID-only） | tool | 构建轮 |
| 22 | `board/build_p7b_ku5p.tcl:145` | `verilog_define` 加 `SFP2_MODE_A=1`（甲）或 `SFP2_MODE_B=1`（乙）**二选一**；硬门 = 两者不能同时定义 | build | P1 |
| 23 | `board/ku5p_p7b_gt.xdc` / `ku5p_p7b_cdc.xdc` | **预期零改动**；构建轮 grep `12-4739` + 看 `report_clock_interaction` 确认新束的两域是异步 | build | P1 |

**P2/P3 的接口点（只登记，不实施）**：
- `rx_merge2` 插入点 = `u_rxcdc` 输出与 `vlan_strip` 输入之间（`wrapper_p4.v:944` / `:975`）；ch0 的 `fifo_async` 在 `u_rxcdc` 旁。
- `tx_split2` 插入点 = `u_tx_arb.m_axis` 与 `u_txcdc` 之间（`:2883-2891`）；ch0 的 TX FIFO + MAC 在 `u_mac_tx` 旁。
- 甲模式出口判口 = `tcp_cam.rd_dip`（`rtl/tcp_cam.v:36` 的 `rd_dip` 输出；`tcp_tx_frame` 现在没接，`:2325-2329`）。
- 慢路径 / UDP app 的本地 IP 改动点 = `wrapper_p4.v:2331`（`cfg_src_ip`）、`:2470`（`cfg_dst_ip`）、`:2762`（`cfg_my_ip`）；HLS 侧 = `hls/src/eth_types.h:123`（`BOARD_IP`）、`hls/src/layer_arp.cpp:149,194`、`hls/src/layer_tcp.cpp:68,156`。

### 2.5 资源/时序预估（**全部纸面**）

| 项 | LUT | FF | BRAM | URAM | 依据 |
|---|---|---|---|---|---|
| `mac_rx_10g`（第二实例） | **+1,453**（OOC 上界） | **+911** | 0 | 0 | `p7b_mac_synth/mac_only/mac_rx_ooc/.../utilization_synth.rpt` |
| ch0 时钟/复位别名 | +5 | +3 | 0 | 0 | 结构估计 |
| ch0 PCS 3FF + 事件计数器 | +20 | +107 | 0 | 0 | 17×3 + 8×3 + 4×8 |
| LOS 3FF + 饱和沿计数 + priming | +20 | +20 | 0 | 0 | 结构估计 |
| p7bdp +3 字（三份寄存器） | +10 | **+288** | 0 | 0 | 3×96 |
| ch0 计数束 NW=4（三份） | +20 | **+384 + ~20 FSM** | 0 | 0 | 4×96 + snap_cdc 开销 |
| 完成门超时/arming | +20 | +25 | 0 | 0 | 结构估计 |
| **合计** | **≈ +1.55k** | **≈ +1.76k** | **0** | **0** | 纸面，小项 ±50% |

- 相对 0x2A：LUT 78,248 → ~79.8k（36.8%）；FF 75,360 → ~77.1k（17.8%）。**BRAM/URAM/GT/BUFG 零增量**（ch0 的两个 BUFG_GT 已在跑）。
- 功耗：纸面增量 < 0.3 W（现 4.380 W，Confidence Medium）。
- **时序**：新增面 = ① ch0 新时钟域（MAC + sink + 计数束，独立于 DP）；② DP 域 +3 个 `hold_b` 字 + 2FF 状态/LOS（~110 FF）；③ pcie 域 +7 字阵列 + 超时 FSM。**纸面判断：新逻辑不直接落在 0x2A 的全局 WNS 宿主（DP 的 `u_tcp_tx/u_fifo_b → u_app/stg`）上，但 DP 域新增 FF 会参与布局** ⇒ 无法给出可信的 WNS 预测，按“一次构建收口 + 预登记 backstop”处理（§6.3）。

---

## 3. 观测面（P1 的核心交付）

### 3.1 字表（推荐 7 字；基 = 0x2A 的 76 字）

| 新字 | 内容 | 位域（写死，判读照此拆） | 束 / 域 | 源 |
|---|---|---|---|---|
| **W76** | ch0 PCS 状态束（**与 W39 同位域**） | `[31]0 [30]ch0_sig [29]gtpowergood0 [28]user_rx_reset0 [27]user_tx_reset0 [26:22]0 [21]rx_error_valid0 [20:13]rx_error0[7:0] [12]valid_ctrl_code0 [11]fifo_error0 [10]bad_code_valid0 [9]bad_code0 [8]framing_err_valid0 [7]framing_err0 [6]tx_local_fault0 [5]rx_local_fault0 [4]hi_ber0 [3]rx_status0 [2]block_lock0 [1:0]0` | p7bdp 槽 36 / dp | 3FF 同步后的 ch0 `stat_*_0` |
| **W77** | ch0 PCS 事件束（**与 W40 同位域**；BER 代理） | `[31:24]ferr_evt [23:16]bad_evt [15:8]erv_evt [7:0]vcc_cyc`（各 8 位饱和） | p7bdp 槽 37 / dp | dp 域事件计数器 |
| **W78** | LOS 电平 + 沿计数 + 模式条 | `[31]SFP2_MODE_B_SEL [30:24]0 [23:16]los1_evt[7:0]（饱和） [15:8]los2_evt[7:0]（饱和） [7:2]0 [1]los2_level [0]los1_level` | p7bdp 槽 38 / dp | `sfp1_rx_los`/`sfp2_rx_los` 3FF + priming 后计数；mode = 编译常量 |
| **W79** | ch0 RX **好帧数**（sink 交付；`tlast && tcrs`） | 32 位自由回卷 | ch0 束 槽 0 / `rx_clk_out_0` | ch0 sink |
| **W80** | ch0 RX **载荷字节**（`Σpopc(tkeep)`，仅好帧） | 32 位自由回卷 | ch0 束 槽 1 / `rx_clk_out_0` | ch0 sink |
| **W81** | ch0 RX **FCS 错帧数** | 32 位自由回卷 | ch0 束 槽 2 / `rx_clk_out_0` | `mac_rx_ch0.stat_crc_err` |
| **W82** | ch0 RX **丢帧数**（整帧丢，含空间/碎片/零长） | 32 位自由回卷 | ch0 束 槽 3 / `rx_clk_out_0` | `mac_rx_ch0.stat_drop` |

**口径（必须先钉死，别读混）**：
- W79/W80 是**sink 交付口径**：W80 只累加 `tcrs=1` 的好帧的 `Σpopc(tkeep)`；对好帧，`W80 + 4×W79 = 线上字节（含 FCS）`。对端 NIC 的 `port_tx_bytes` 是线字节（不含前导/IFG）⇒ **在 W81=0、无背景流量时，应满足 `W80 + 4×W79 = Δport_tx_bytes`**（±窗口边界）。`Δport_tx_packets` 对应 `ΔW79`。
- W81/W82 是**MAC 口径**：`stat_crc_err` 在帧被推入时按 `!res_ok` 计数；`stat_drop` 是整帧丢的总数。两者与 W79 不是同一计数点 ⇒ **不要拿 `W79 + W81 + W82` 当“收到帧总数”**（TERM 字/碎片会重复计）。
- 所有 32 位计数器在 156.25 MHz 下 **27.487 s 回卷** ⇒ 差值判据必须 **mod 2³²** 且记原始值（全局 #55）。
- `pcs_user_rx_reset_0`（W76[28]）有效时 ch0 MAC 计数器会清零 ⇒ **跨复位的差值无效**；读数必须同时看 W76[28]。
- W76[20:13] = `rx_error[7:0]` 是**逐 lane 指示位**（bit7=lane7）⇒ **不得当 8 位数值引用**（与 W39 的同族口径逐字相同）。
- ch0 停钟时 W76 的 PCS 状态可能停在最后一拍（PCS 状态输出可能在 ch0 时钟域）⇒ 此时**以 W78 的 LOS 电平/沿**（板级引脚、dp 同步、独立于 PCS）为准。
- W77 与 W40 **同口径**：数的是“同步后为高的 **dp 拍数**”（PCS 的 `_valid` 是 1 个 dclk 拍宽的脉冲，3FF 后可能被展宽/合并）⇒ **只用于“这条线有没有动过”，不得当精确事件数**。
- BER：官方 PCS **没有 BER 数值输出**。W76 的 `hi_ber`/`bad_code`/`framing_err`/`rx_error[7:0]` + W77 的事件饱和计数是**可用代理**；正式 BER 需 PRBS/长时统计（P7a 配方），**P1 不做**。【未测】

### 3.2 地址与几何（两代并列；扩窗必须构建）

**公式（现役 `axi_regs`）**：
- 快照字 = `0x20 + 4×W#`（W0 @ `0x20`）
- MIR 四字 = `SNAP_LAST_IDX+1..+4`（自动跟随 `SNAP_NW`）
- 未实现地址 = `0x20 + 4×SNAP_NW + 16`

**推荐（基 = 0x2A，76 字 → 83 字）**：

| 字 | 地址 | 备注 |
|---|---|---|
| W76 | `0x150` | ch0 PCS 状态 |
| W77 | `0x154` | ch0 PCS 事件 |
| W78 | `0x158` | LOS + mode |
| W79 | `0x15C` | **⚠️ 0x28/0x29 的“未实现地址”现在变成真字** |
| W80 | `0x160` | **⚠️ 0x2A 的“未实现地址”现在变成真字** |
| W81 | `0x164` | |
| W82 | `0x168` | 末字（`SNAP_LAST_IDX` = 90） |
| MIR_STATUS / DATA / CTRL / DMA_CNT | `0x16C / 0x170 / 0x174 / 0x178` | 由 `SNAP_LAST_IDX` 自动下移 |
| **未实现** | **`0x17C`** | `0x20+4×83+16` |

**备选（基 = 0x28，75 字 → 82 字）**：新字编号 = **W75..W81**，地址 `0x14C..0x164`；MIR `0x168/0x16C/0x170/0x174`；未实现 **`0x178`**。**不推荐**：会打断读侧链（0x2A 阶段要跳过）且丢掉已板级验证的孤儿修复。

**预算核对（两代都过）**：
- **项数对账（必须恰 = NW）**：`14+22`（snap_seq 的 FE/DP）`+ 3 + (39-4)`（p7bfe + p7bdp，槽 2..5 由 tx 束搬）`+ 5`（tx）`+ 4`（ch0 束）`= 83` ✓。少一项 = 高位悬空；多一项 = 被截断（`:3559` 的同一条纪律）。
- `snap_idx = r_word[6:0]-8` 7 位：max 82 < 128 ✓
- `snap_base` 12 位：max `(83-1)<<5 = 2624 < 4096` ✓
- `ar_word` 7 位：max word 95 < 128 ✓
- **红线**：绝不能挑 ≥ `0x200` 当未实现地址（7 位译码回绕）。

### 3.3 ⛔ 快照汇合超时（P1 必须新增的机制；否则 LOS 负对照会打瞎整个窗口）

**问题**：新增的 `u_snap_ch0` 束 `clk_b = rx_clk_out_0`（CDR 恢复钟）。**该钟在无光/拔线时是否停转 = 【未判定】**（GT `rxoutclksel=3'b101` 的选择语义、以及 CDR 无数据时的行为，本轮未核）。若它停：
- `snap_cdc` 的 b 域握手永远不回 ⇒ `ch0_valid` 永不置 ⇒ 若 `snap_valid_all` 仍等它，**整个 83 字窗口永久不可读**（包括 ch1 业务计数）。
- 这正好发生在 P1 的 LOS 负对照（拔线/关对端）——**最需要读数的时刻**。

**设计（pcie 域，~25 FF）**：

1. **逐代 arming**：`snap_req` 拍采样 `ch0_ready = ~ch0_busy`。
   - `ch0_armed = ch0_ready`；`ch0_seen = 0`；`ch0_to_cnt = 0`；`ch0_to_hit = 0`。
   - 若 `ch0_armed = 0`（上一代仍卡着）⇒ 本代**不等** ch0（视为陈旧），直接 `ch0_to_hit = 1`（或等价 `ch0_done = 1`）。
2. **等待 / 超时**：`ch0_armed && !ch0_seen && !ch0_to_hit` 时，`ch0_to_cnt` 每 `pcie_axi_aclk` +1；到 **4096**（≈16 µs @250 MHz，远大于正常 ~10 拍往返）置 `ch0_to_hit`。⭐ **`ch0_seen` 只在 `ch0_armed=1` 时接受 `ch0_valid`** —— 否则上一代超时后迟到的 `valid_a` 会被误记到本代（同一束没有代标签，这是 arming 位存在的第二个理由）。
3. **主束完成锁存**：`snap_valid_main = snap_valid & p7bfe_seen & p7bdp_seen & tx_seen`（现有四束）；`snap_main_seen` 锁存到本代结束（因为超时可能晚于主束的 1 拍 `snap_valid`）。
4. **本代完成**：`snap_done = snap_main_seen & (ch0_seen | ch0_to_hit)`；`snap_valid_all = snap_done & ~snap_done_q`（**1 拍脉冲**，`axi_regs` 的捕获语义要求）。
5. **本代状态**：`ch0_snap_to_r` 在 **`snap_valid_all` 那一拍**锁存 `(ch0_to_hit && !ch0_seen)`（与 `snap_words_r` 同拍 ⇒ 读到的标志与读到的字是同代；**逐代**，不是 sticky）；接 `axi_regs` 新输入 → **`SNAP_STATUS[7]`**。
6. **busy**：`snap_busy = snap_pending | 四束 busy`，`snap_pending` 在 `snap_req` 置位、在 `snap_valid_all` 清零（保证主机“trigger→poll done”协议不被超时路径破坏）。
7. **陈旧语义**：`ch0_snap_to = 1` 时，W79..W82 是**上一代/复位值**（不是本代）；W76..W78（dp 束）仍是本代。**主机必须读 `SNAP_STATUS[7]` 再决定是否信 W79..W82**。
8. **非 P7B 构建（p6e 门）**：ch0 束不存在 ⇒ `ch0_armed=0`、`ch0_done=1`、`ch0_snap_to=0`（**“不适用”不是“失败”**），W79..W82 恒 0；只有 P7B 构建才允许 `ch0_snap_to=1`。否则 p6e 门会每代误报“ch0 束缺失”。

**单元/门牙（§5.2）**：
- 正常臂：ch0 钟在 ⇒ `ch0_snap_to=0`，W79..W82 等于 force 值。
- 停钟臂：force ch0 rx 时钟停 ⇒ 主束仍可读、`ch0_snap_to=1`、W76..W78 正确。
- 负对照：把 `snap_valid_all` 改回“只等四束”（去掉 ch0）⇒ 停钟臂下 W79..W82 会**静默读到上一代**且 `SNAP_STATUS[7]=0` ⇒ 判据必须红（证明状态位有牙）。

⚠️ **同一个风险也存在于现有 `u_snap_p7bfe`**（`clk_b = gmii_clk = rx_clk_out_1`）：若 ch1 拔线/停钟，整个窗口也可能卡住。这是**既存潜伏项**，P1 不修（不在范围内），但必须登记；若 P1 的超时机制验证有效，可考虑在后续轮把它泛化到所有束。

### 3.4 成本与扩窗风险

- 7 字 × 96 FF ≈ **+672 FF**（三份），其中 **dp 域 +96 FF**（W76..W78 的 `hold_b`）、`rx_clk_out_0` 域 +128 FF（W79..W82 的 `hold_b`）、pcie 域 +320 FF（`dout_a` + `snap_words_r` 阵列）。
- **0x2A 的全局 WNS 宿主已换成 DP setup**（不再是 0x28 的快照阵列复位族）⇒ 扩窗的**主要风险从“复位族”转到“DP 域布局压力 + pcie 阵列”**；两代都只并列、不归因。
- 如果构建吃不动：按 §6.3 的 backstop 顺序砍字（先砍 W77 事件字，再砍 W79..W82 计数束，最后 P1-min）。
- 备选观测通道（不推荐 P1 用）= 把 ch0 计数走 **MIR/URAM 镜像通道**（P9 已有 `mir_uram_fifo` + `axis_c2h_stream`），代价是另开一档设计且主机要持续读；快照字仍是“低带宽、随机读”的最便宜口径。

### 3.5 读侧同步（构建轮必做；漏改 = 静默误读）

以 0x2A 轮的 110 处/20 文件为模板，新增阶段 ⑯ `0x2B`：
- `EXPECT_BID` 默认值 `0x2A → 0x2B`；`SNAP_WORDS/NW` 默认 `76 → 83`；`UNIMPL_ADDR` 默认 `0x160 → 0x17C`。
- `WLABEL/NAME[]/W 表/V 表/FAKE_TAIL` 补 W76..W82（末条 `0x17C`）。
- MIR 四址 `0x150/0x154/0x158/0x15C → 0x16C/0x170/0x174/0x178`（**p6e TB 的 73 个 `32'h` token 降序替换**，照 0x2A 轮的做法）。
- `tb_biz_win.v` 的 BUILD_ID 与 MIR 地址改由 NW 派生（0x2A 轮已改成派生，只需改 NW/BID）。
- `final_state.sh` / `tb_p7b_chain.v` / `check_window.py` 三处几何常量。
- 工具自检 A/B/C/D + negctl 四条全有牙（照 0x2A 轮）。

⚠️ **0x15C/0x160 的身份翻转**是 P1 最容易被旧脚本误读的一处：旧读侧把它们当“未实现地址”并断言 `0xffffffff`，新位流里它们是**真字 W79/W80** ⇒ 必须同批改，否则会得到“假 FAIL”或“假 PASS”。

---

## 4. 甲/乙模式开关（只定接口与分叉点）

### 4.1 单一开关（代码）

**推荐**：一个 `ifdef` 开关，**甲 = 未定义，乙 = 定义 `SFP2_MODE_B`**。

```verilog
`ifdef SFP2_MODE_B
    localparam SFP2_MODE_B_SEL = 1'b1;
`else
    localparam SFP2_MODE_B_SEL = 1'b0;   // 默认甲
`endif
```

**硬门（照 `g_orph_zw_guard` 的“缺模块 ⇒ elaboration 硬失败”手法，`wrapper_p4.v:226-241`）**：
- 若 **`SFP2_MODE_A` 与 `SFP2_MODE_B` 同时定义** ⇒ 例化一个不存在的模块。
- 若 **`SFP2_MODE_B` 定义但 `P7B_10G` 未定义** ⇒ 同样硬失败（乙模式只对 10G 前端有意义）。
- 构建脚本：**甲 = 不传模式宏**（默认甲；也可显式传 `SFP2_MODE_A=1` 作“我确实选了甲”的构建见证），**乙 = 传 `SFP2_MODE_B=1`**；两者同时传 = 硬失败。**单开关 = `SFP2_MODE_B` 的有无**。

**P1 的实现边界**：P1 只把开关与 **W78[31] 模式条**落地；**甲/乙的功能分叉在 P2/P3**（甲 = `rx_merge2`；乙 = 镜像）。P1 的甲/乙两位流在功能上相同、只有模式条/BID 不同 —— 因此 **P1 建议只构建甲（0x2B）**；乙位流（0x2C）留到 P3 有镜像通路时再建（省一轮 40 min 构建，且避免一个“无意义乙位流”）。见待裁 #10。

### 4.2 BID 分配建议

| BID | 内容 | 状态 |
|---|---|---|
| `0x29` | 0x29 拆刀（persist 关） | 已用（历史） |
| `0x2A` | 孤儿修复 | 已构建、板级正结果、**现役待裁** |
| **`0x2B`** | **P1-甲（ch0 bring-up + 观测）** | 建议 |
| **`0x2C`** | **P1/P3-乙（同几何，模式条=1；镜像通路）** | 建议保留 |
| `0x2D` | 若用户否决 0x2A、P1 需以 0x28 为基 | 备用（避免 0x2B 内容二义） |

⚠️ 纪律：每次构建 bump；全代位流同尺寸（15,431,261 B）⇒ **只有 sha256 + BID 能分版**。

### 4.3 分叉点（文件:行号级）

| 分叉 | 甲（A） | 乙（B） | 位置 |
|---|---|---|---|
| ch0 RX 去向 | `fifo_async(76×256)` → `rx_merge2` → `vlan_strip` | `fifo_async(76×256)` → 原始帧镜像器 | `wrapper_p4.v:944/975` 之间（P2/P3） |
| ch0 TX 源 | `tx_split2` 的 ch0 支 → `mac_tx_10g` | 常量 IDLE（P1/P2 共用） | `:2883-2891` / `:601-608` |
| 连接身份 | 4 元组（`dip` = 本地 IP，天然分口） | 不建连 | `rtl/tcp_cam.v:9-33`；`slow_cfg_adp.v:148` |
| 出口判口 | `rd_dip == BOARD_IP_PORT1`（CAM 已有 `rd_dip`，`tcp_cam.v:36`） | 不适用 | `tcp_tx_frame` 的 `cam_rd_*`（`:2325-2329`） |
| 慢路径 | HLS 认两个本地 IP（`BOARD_IP` + 第二 IP）；ARP/SYN 两口都答 | 不接慢路径 | `hls/src/eth_types.h:123`、`layer_arp.cpp:149,194`、`layer_tcp.cpp:68,156` |
| UDP app | peer 表加本地 IP/端口位（meta 需 `dst_ip`） | 不接 | `rtl/udp_split.v:209-213`、`rtl/udp_tx_cfg.v:66-77` |
| app 可见性 | 事件字 +1 位 port（102→103）或按 local_ip 暴露 | 不适用 | `rtl/app_ctrl.v:28-33` |
| 观测 | W79..W82（ch0 计数）+ W76..W78 共用 | 同左 + 镜像丢帧计数（P3 新增字） | §3 |

### 4.4 甲模式的三种“口身份/出口”实现（选项与推荐）

| 选项 | 做法 | 代价 | 风险 | 推荐 |
|---|---|---|---|---|
| **A-1（推荐）** | **IP 头即端口身份**：RX 合并无标签、流宽不变、CAM 不变；出口用 `cam_rd_dip`（TCP）/ 源 IP 提取（慢路径）/ peer 表本地 IP（UDP） | TCP：`tcp_tx_frame` +`cam_rd_dip` 输入 +1 `o_port`；慢路径：源 IP 提取小逻辑或 HLS 边带；UDP：meta +`dst_ip` 或 peer 表 +1 位 | 慢路径/UDP 的本地 IP 必须由 HLS/udp_rx 正确给出；HLS 必须认两个 IP | ⭐ |
| A-2 | plan §2-S2：流 76→77 + CAM +1 位 port + 出口分流 | 4 处流宽 + CAM 7 组端口 + TB 语料 | 回归面大（4 元组→5 元组） | 备选（同 IP 双口时才需要） |
| A-3 | HLS 直接给 port 边带（慢路径），fast path 仍用 `rd_dip` | HLS 接口改动 + 重综合 | 最显式、最少 RTL 猜测 | 可与 A-1 同批 |

**推荐 A-1**（+ 慢路径优先尝试“源 IP 提取”，失败再退回学习表）。理由：用户的“单独 IP”裁定已经把端口身份放进 IP 头；A-1 的改动面最小、不动既有流宽/CAM、不给回归语料制造 5 元组语义变更。

### 4.5 乙模式的转发目的地（待裁）

| 选项 | 做法 | 代价 | 风险/限制 | 推荐 |
|---|---|---|---|---|
| **B-1（推荐）** | ch0 RX 原始帧 → 板内缓冲（URAM/BRAM）→ C2H AXIS → 主机 | 复用 P9 的 `axis_c2h_stream`/`mir_uram_fifo` 思路；需要新的 raw-frame tap 与缓冲 | 10G 全速 = ~1.2 GB/s；主机必须能持续读；满则**丢整帧** + 计数 | ⭐ |
| B-2 | ch0 RX → ch1 TX（线上转发） | 需与 ch1 业务 TX 仲裁；占用业务口带宽 | 会把镜像流量混进 ch1 业务线；不推荐 | ✗ |
| B-3 | ch0 RX → 只计数/丢弃（P1 的 sink） | 零成本 | 不是“转发”，只是观测 | P1 临时 |

⚠️ 用户原话“乙只转发 RX / 因为只需要转发”**没有指定转发到哪**；这是 §0.5 的未定项（§4.6 / 待裁 #5）。

### 4.6 甲模式的 HLS 影响（必须如实标出）

- plan §0.5 已承认：“慢路径 IP 匹配需容纳两个板 IP（单值 → 值集合，或按口查表）—— 这是相对推荐路线（HLS 零改动）的一处偏离”。
- 本轮现读把成本钉得更死：
  - `hls/src/eth_types.h:123` 的 `BOARD_IP` 是**编译期常量**；`layer_arp.cpp:149,194` 用它填 ARP 的 sender IP / 判 target；`layer_tcp.cpp:68,156` 有 `ACTIVE_IP` 与本地 IP 注释。
  - 因此**甲模式不是“RTL 小改”**：要让 ch0 的 IP 能收 ARP、能完成 TCP 握手，HLS 必须**认两个本地 IP**并按其一来回包。这就是 **HLS 源码改动 + `run_hls.bat` 重综合**（+ 慢栈配置通道）。
  - RTL 侧三个硬编码点（`:2331`/`:2470`/`:2762`）也要同批改；CAM 的 `dip` 由 HLS 的 `w2 = local_ip` 自动正确（`slow_cfg_adp.v:7,148`），**不需要 CAM 存储改**。
- **如果用户不接受 HLS 改动**：只能退回“两口同 IP + 端口标签/CAM+1 位”（A-2），这与 §0.5 的“单独 IP”裁定冲突 ⇒ 需要用户重新裁定。**不要**用 RTL NAT/IP 改写 shim 硬绕（校验和/ARP/ICMP/TCP 全覆盖，风险远大于 HLS 改）。

---

## 5. P1 判据与实验（草案；裁定权在用户/判据所有者）

### 5.1 构建门（一次构建收口）

| # | 判据 | 期望读数 | 负对照/牙 |
|---|---|---|---|
| B-1 | `P7B_WNS` / `P7B_WHS` | **正值**；逐档并列、不比大小（#66） | 若 WNS < 0 或任一类失败端点 > 0 ⇒ 走 §6.3 backstop（不是“重跑到过为止”） |
| B-2 | 三类失败端点 | `0/0/0`；`Slack (VIOLATED)` = 0 | —— |
| B-3 | `12-4739` | 0 命中 | 命中 = 约束被静默丢弃 |
| B-4 | 隐式网五键 / DRC | `IMPLICIT-NET-FAIL` 0；DRC 0 Error / 0 Critical | —— |
| B-5 | 位流 | 存在、15,431,261 B、sha256 归档 | 只有 sha256+BID 能分版 |
| B-6 | 身份常量 | `BUILD_ID_V=0x2B`；`SNAP_NW_P6E=83`；`SNAP_P7BDP_NW=39`；`SNAP_CH0_NW=4` | 读源码/回读 |
| B-7 | 构建输入绑定 | `BUILD_INPUT_HASHES_BEFORE == AFTER` | 漂移 = 整轮作废 |
| B-8 | 时钟交互 | 新 ch0 束的两域在 `report_clock_interaction` 里是异步/不分析 | 若被当同步路径分析 ⇒ 可能是新跨域失败源 |

### 5.2 仿真/单元门（P1 的主战场）

**G1 — `_proj_10g/p7b_chain/sim/run_tb_p7b_chain.bat`（P7B 真 wrapper 配置）**

这是**唯一**编 `P7B_10G + PCIE_OBS + DP_156MHZ + APP_MODE + P7B_SIM_NOPCS` 的全链门（`run_tb_p7b_chain.bat:39`）。P1 必须扩：

| 臂 | 激励 | 期望读数 | 牙 |
|---|---|---|---|
| G1-a 基线 | 现有链级判据（plan 记 106；以门打印的 `checks` 为准，含快照组） | `VERDICT = PASS`、`fails=0` | 任何旧判据红 = 回归 |
| G1-b 新几何 | 读 `0x17C` 未实现；读 W76..W82 | `0x17C` 回 0 + SLVERR；W76..W82 地址-值映射正确 | 0x15C/0x160 不再是未实现（旧地址断言必红） |
| G1-c ch0 状态 | force **stub 的 ch0 生产者 reg**（拆完后为 `blk_lock_0=1`、`hi_ber_0=1`、`rerr_0=8'h5A`）；ch1 侧 force 成不同值 | W76[2]=1、W76[4]=1、W76[20:13]=0x5A；**W39 的对应位不被 ch0 污染** | stub 必须拆 ch0/ch1 status（改动 #18），否则 W76=W39，判据无判别力 |
| G1-d ch0 帧计数 | 用第二 XGMII 队列 force `inj_d0/inj_c0` 注入 N 帧已知长度（好 FCS） | `ΔW79 = N`、`ΔW80 = N×(wire_len−4)`、`ΔW81=0`、`ΔW82=0` | 负对照：把 sink 的 `tready` force 0 ⇒ W79 不涨、W82 涨（证明计数点在交付端） |
| G1-e LOS | `sfp1_rx_los` 0→1→0；`sfp2_rx_los` 保持 0 | W78[0] 随电平；W78[23:16] 每次沿 +1（饱和）；W78[31] = 模式条 | 复位 priming：复位后的第一段不计数（防“上电即 +1”假事件） |
| G1-f 快照超时 | force **stub 的 `rx_clk_0` 拉低**（只停 ch0；改动 #18 已把共享 `rx_clk` 拆开）→ trigger snapshot | 窗口仍可读（`snap_done` 在 4096 拍内到）；`SNAP_STATUS[7]=1`；W76..W78 正确；W79..W82 陈旧 | 负对照：去掉 ch0 的“不等”分支 ⇒ 该臂 TIMEOUT（证明超时机制有牙） |
| G1-g ch0 TX 不动 | 读 `txcap_d0/txcap_c0` | 恒 `0x0707…/0xFF`（常量 IDLE） | 任何变化 = 误改 |

**G2 — `sim/p6e_pcie/run_tb_p6e_pcie.bat` + `_counters`（非 P7B 配置）**

- 只覆盖几何/身份：BID `0x2B`、83 字、MIR `0x16C/0x170/0x174/0x178`、未实现 `0x17C`；W76..W82 读 0（非 P7B 支常量）。
- ⛔ **不许拿 G2 当 ch0 功能证据**（它不编 `P7B_10G`，`run_tb_p6e_pcie.bat:24` 的 define 列表可核）。

**G3 — 常驻矩阵 `sim/p4gates/run_matrix_p4dfix.bat`**

- 19/19 `EXIT=0`、`VERDICT: FROZEN`；指纹漂移必须逐条可解释（预期：`board/wrapper_p4.v`；若改 stub/TB 则再加它们）。
- ⛔ **`p5_wrapper` 只编 `-d APP_MODE`**（`run_matrix_p4dfix.bat:206-211`）⇒ 对 ch0 逻辑 **零覆盖**。
- ⭐ **建议**：把 `p7b_chain` 注册为矩阵第 20 门（新门必须进矩阵；这也是对“矩阵看不见 P7B wrapper”旧债的收口）。见待裁 #8。

**G4 — 新单元门（可选但建议）**

若把“快照汇合超时/arming”抽成小模块（如 `rtl/snap_join_to.v`），加 `sim/p9_dual_sfp/tb_snap_join_to.v`：
- 正常臂（所有 valid 到 → 1 拍 done）、
- 缺一束臂（超时 → done + 标志）、
- 上一代仍 busy 臂（arming=0，不受理旧 valid）、
- 变异（把超时删掉 / 把 done 做成电平）→ 必红。
抽模块的代价 = 构建脚本 `import_files` 加一行（漏加 = black box，先例 `mir_uram_fifo.v`，`build_p7b_ku5p.tcl:102-106`）；不想加文件就内联在 wrapper 里、用 G1-f 覆盖。

### 5.3 板级门（**必须等在飞板级轮收口后；不抢板**）

前置：重烧 + 核 sha256 + 身份门（`0x04=0x2B` / 83 字 / `0x17C`=`0xffffffff` / 2 BARs / `LnkSta x4`）；对端 p0 `managed no`、`ip link up`（P1 不需要 IP）；ch1 保持现役配方；`0x08` **bit1 保持 0**（别误关 ch1 发射）。

| # | 动作 | 主判据（期望读数） | 独立仪器 / 负对照 |
|---|---|---|---|
| S-1 | 静置 10 min（两口都连着，ch1 不跑业务） | 对端 p0 `carrier=1`、`carrier_changes` 不新增；板 W76[2]=1、W76[4]=0、W76[5]=0、W76[6]=0；W77 事件不增；W81=W82=0；W78[0]=0 | 对端 `ip -br link` / `ethtool -S`；板快照 |
| S-2 | 对端 p0 发 N 帧已知长度（`arping` 或静态 neigh + `ping -c N`；先测空窗背景） | `ΔW79 = N + 背景`；`ΔW80 = Σ(wire−4) + 背景`；`ΔW81=0`；`ΔW82=0`；`W80+4×W79 = Δport_tx_bytes`（±窗口边界；**先现核 NIC 的 `port_tx_bytes` 是否含前导/IFG**，口径不同则按同式加 20×N 修正） | 对端 NIC `port_tx_packets/bytes`（硬件计数）+ pcap（辅助）；**两条独立口径** |
| S-3 | TX_DIS 负对照：`0x08=0x1` → 4 s → `0x08=0x0` | 对端 p0 `carrier 1→0` 且 `carrier_changes +1`；p1 `carrier=1` 不变；恢复后 p0 `0→1` | P0 已证；本条是复算 |
| S-4 | LOS：拔 J7 AOC（或对端 p0 TX 关断，若可）→ 恢复 | `W78[0] 0→1`、`W78[23:16]+1`；对端 p0 `carrier 0`；`W76[2]` 期望 1→0，**但若 ch0 钟停且 PCS 状态停在最后值则可能不变 ⇒ 以 W78 为准**；**窗口仍可读**（`SNAP_STATUS[7]` 记录为 0 或 1，按实际）；恢复后回到 S-1 形态 | 物理拔插（需现场）；若用 `ip link set down` 先确认它真能关光（不然 LOS 不翻，判据无判别力） |
| S-5 | ch0 长收（例如 10 min 低速图案流） | `ΔW81=0`、`ΔW82=0`；W77 的 ferr/bad/erv 不增；`ΔW79 = 对端 port_tx_packets`（±0.2% 量级） | BER 代理（PCS 无 BER 数值） |
| S-6 | ch1 业务回归（同会话 A/B：P1 位流 vs 0x28/0x2A 基线） | ch1 的 UDP/TCP 业务读数同档、`mism_bytes=0`、丢弃计数不增；W0/W1/W20/W43 与基线同量级 | 同板同线；台架帽必须记录（#43/#59/#68） |
| S-7 | 双口并存静置/轻载 | 两口 `carrier=1`、W76[2]=1、ch1 业务不退化；无新 `W81/W82`；温度/功耗无明显跳变 | 闸 1 已证“两通道同时跑”；本条是**我们自己的 MAC** 构型 |

⚠️ **板级判据不许写成 PASS/FAIL**：上表是“期望读数/草案”，裁定权在用户。任何“未观测到”只能写“未观测到”，不能写“不存在”。

### 5.4 负对照/“牙”的汇总（P1 必须至少有一条会让判据红的构造）

1. **W76 vs W39 独立**：stub 拆 ch0/ch1 status；force 不同值 ⇒ 若 W76 跟着 W39 走，判据红。
2. **sink 计数点**：force `ch0_rx_tready=0` ⇒ W79 不涨、W82 涨；证明 W79 不是“MAC 内部推入”口径。
3. **超时机制**：停 ch0 rx 钟 ⇒ 窗口仍可读且 `SNAP_STATUS[7]=1`；去掉“不等 ch0”分支 ⇒ TIMEOUT。
4. **LOS 沿计数**：单一电平不动 ⇒ 计数不涨；翻转一次 ⇒ 恰好 +1。
5. **几何翻转**：读旧 `0x15C`/`0x160` 必须不再回 `0xffffffff`（它们现在是 W79/W80）⇒ 旧脚本断言会红，证明读侧同步是必要的。
6. **TX 常量**：`txcap_d0` 恒 IDLE；任何变化 = 误改。

### 5.5 门覆盖警告（别引用错门）

| 门 | 编的配置 | 对 P1 的覆盖 |
|---|---|---|
| `p7b_chain` | `P7B_10G + PCIE_OBS + DP_156MHZ + APP_MODE + P7B_SIM_NOPCS` | **唯一覆盖 ch0 逻辑** |
| `p6e_pcie`（双门） | `PCIE_OBS + APP_MODE + DP_156MHZ`，**无 `P7B_10G`** | 只覆盖几何/身份；W76..W82 = 常量 0 |
| `p4` 矩阵 `p5_wrapper` | **只 `APP_MODE`** | **零覆盖** ch0/P7B；只能证明“默认构建没坏” |
| `p4` 矩阵其余 18 门 | 数据面单元/链 | 与 P1 无直接关系（P1 不改数据面） |

---

## 6. 实施步骤与风险

### 6.1 实施步骤（建议）

| 步 | 动作 | 产出/门 | 备注 |
|---|---|---|---|
| 0 | 冻结基代与输入哈希；确认在飞板级轮已收口（或另开 worktree） | 基 commit + 3 文件 sha256 | **改 RTL 与在跑回归互斥（#57）**；P1 实现必须独占树或在 worktree |
| 1 | 实施 P1 RTL（§2.4 #1–#17） | 源码 diff | 全部 `ifdef P7B_10G`/`PCIE_OBS`；默认构建逐位不变 |
| 2 | 仿真专用改动（stub 拆 ch0/ch1 status；chain TB 扩臂；p6e 几何） | G1/G2 | 先跑 G1-a 基线，确认旧判据全绿，再加新臂 |
| 3 | 跑 G1/G2/G3；必要时加 G4 | 门日志 | 新臂必须有“牙”（§5.4） |
| 4 | 一次构建 + 12 键硬门 + 归档 | 位流/sha256/报告 | backstop 见 §6.3 |
| 5 | 读侧阶段 ⑯（+⑰ 若建乙） | `--apply --bid 0x2B` + A/B/C/D 自检 | 与工具 agent 协调 `_proj_pcie/p7b_biz/` 写面 |
| 6 | 板级（等在飞轮收口） | S-1..S-7 原始读数 | 不抢板；每次重烧 + 核 sha256 |
| 7 | 归档/回灌（#54） | 报告 + SHA256SUMS | 构建脚本内归档 |

### 6.2 风险与缓解

| # | 风险 | 等级 | 缓解 |
|---|---|---|---|
| R-1 | **时序**：0x2A 只有 0.61%；+7 字 + DP 域 2FF/计数器 | 高 | 先按 7 字一次构建；预登记 backstop（§6.3）；不承诺 WNS 数值 |
| R-2 | **快照打瞎**：ch0 CDR 钟停 ⇒ 窗口永久不可读 | **高** | §3.3 的逐代 arming + 4096 拍超时 + `SNAP_STATUS[7]`；G1-f 验证 |
| R-3 | **门覆盖盲**：矩阵/p6e 看不见 ch0 | 高 | 把 `p7b_chain` 进矩阵（#20）；报告里逐条标“哪门覆盖哪条” |
| R-4 | **读侧误读**：`0x15C/0x160` 从“未实现”变“真字” | 高 | 阶段 ⑯ 同批改；`check_window.py`/`final_state.sh`/TB 三处；旧脚本断言必红是**预期** |
| R-5 | **HLS 改动面**（甲模式） | 中高 | P1 不做；P2 前先裁 HLS 范围；备选 A-2/学习表 |
| R-6 | **sink 被优化**：输出流无负载 ⇒ 帧计数变丢帧 | 中 | sink 是真消费者；G1-d 的 `tready=0` 负对照 |
| R-7 | **stub 共享 status** ⇒ W76/W39 无判别力 | 中 | 拆 ch0/ch1 status（#18）；G1-c |
| R-8 | **`0x08` bit1 误写** | 中 | 板级只写 bit0；每次读数前确认 `0x08` 的 bit1=0 |
| R-9 | **BRAM/URAM** | 低 | P1 零增量；第二 MAC 0 BRAM（OOC 报告） |
| R-10 | **功耗/热** | 低 | 纸面 <0.3 W；S-7 实测 |
| R-11 | **与 0x2A 的关系**：0x2A 现役待裁 | 中 | 基代待裁 #1；若否决 ⇒ BID 用 0x2D，读侧链改基 |
| R-12 | **并发写面**：`_proj_pcie/p7b_biz/` 被工具 agent 占用 | 中 | 实施/构建轮先协调；本件不写 |

### 6.3 预登记 backstop（“一次构建收口”的失败路径；不是“重跑到过为止”）

**触发条件**：构建后 `WNS < 0` **或** 任一类失败端点 > 0 **或** `Slack (VIOLATED) > 0`。

**阶梯（按顺序，每次 = 一个新输入，不是重跑）**：
1. **B1**：删 **W77**（ch0 PCS 事件字）⇒ 6 新字 / NW 82 / `0x178`。保留 status/LOS/MAC 计数。
2. **B2**：删 **W79..W82**（ch0 计数束 + ch0 MAC 实例）⇒ 3 新字 / NW 79 / `0x16C`；只剩 ch0 status + 事件 + LOS。
3. **B3（P1-min）**：删 **W77/W79..W82**，只留 W76+W78 ⇒ 2 新字 / NW 78 / `0x168`；P1 退化为“ch0 link + PCS 状态 + LOS”，**不交帧计数**（需用户接受）。

⚠️ 每一档都要更新读侧阶段与 TB 几何；**不许**在同一输入上反复重跑。

### 6.4 待裁问题（逐条 + 与 §0.5 裁定的对照）

| # | 问题 | 选项 | 本件建议 | 与 §0.5 的关系 |
|---|---|---|---|---|
| 1 | **P1 基代** | (a) 0x2A（工作树，76 字，WNS +0.039/0.61%）；(b) 0x28（板上，75 字，WNS +0.065/1.02%） | **(a) 0x2A**（已含板级验证的孤儿修复、树即基、读侧链连续）。⚠️ **隐含后果**：以 0x2A 为基 ⇒ P1 位流会把孤儿修复（`app_ctrl.stat_orphan` / `slow_cfg_adp.o_busy` / `wrapper +148`）**一起带上板**，即使 0x2A 本身尚未被裁定为现役。若用户希望 P1 位流**不含**孤儿修复 ⇒ 必须选 (b) 并用 BID `0x2D` | §0.5 未涉及；0x2A 现役待裁 |
| 2 | **BID** | 0x2B（甲）/0x2C（乙）/0x2D（0x28 基备用） | 0x2B + 0x2C | 用户要求“两个 bitfile” |
| 3 | **观测字档位** | 7 字（推荐）/6 字（去 W77）/9 字（+2 守恒字） | **7 字**（status/events/LOS/4 MAC 计数） | §0.5 未涉及；plan §3.3 的 P1 两行 + P2 四字 |
| 4 | **快照超时机制 + `SNAP_STATUS[7]`** | 批准 / 不批准（不批准 ⇒ LOS 负对照可能打瞎窗口） | **批准** | 新增；plan 未列 |
| 5 | **乙模式的转发目的地** | PCIe C2H（B-1）/ ch1 线上（B-2）/ 只计数（B-3） | **B-1（PCIe C2H）** | §0.5 “乙只转发 RX”未指定目的地 |
| 6 | **甲模式的 HLS 两 IP 改动** | 授权 HLS 改 + 重综合 / 退回同 IP + 端口位（与 §0.5 冲突）/ RTL shim（不推荐） | **授权 HLS 改**（P2） | §0.5 “甲则单独 IP”直接要求 |
| 7 | **甲模式出口身份** | A-1 无标签（IP 头即身份）/ A-2 CAM+1 位 / A-3 HLS 边带 | **A-1**（+慢路径源 IP 提取） | §0.5 “单独 IP”使 A-1 成立 |
| 8 | **`p7b_chain` 进矩阵** | 是（第 20 门）/ 否（只单独跑） | **是**（收口“矩阵看不见 P7B wrapper”旧债） | §0.5 未涉及 |
| 9 | **LOS 负对照执行方式** | 物理拔 AOC / 对端 p0 `ip link down`（需先确认能关光） | **物理拔 AOC**（判别力确定）；若不可行再用对端关断并如实登记“未判定” | §0.5 未涉及 |
| 10 | **P1 是否建乙位流** | 只建甲（推荐）/ 甲+乙（P1 两位流，功能同、只差模式条/BID） | **只建甲**；乙留 P3 | §0.5 “两个 bitfile” —— 本件建议**功能分叉到位再建乙**，但需用户确认“先甲”是否允许暂缓乙位流 |
| 11 | **P1 是否加 ch0 TX MAC** | 不加（推荐，TX 常量 IDLE）/ 加（预铺 P2） | **不加**（+1.6k LUT/488 FF 无收益） | §0.5 未涉及 |
| 12 | **stub 拆 ch0/ch1 status（sim-only）** | 批准 / 不批准（不批准 ⇒ G1-c 无判别力） | **批准** | 仿真面，需用户/门所有者同意 |
| 13 | **0x08 bit1 纪律** | 固定 0 / 允许测试后恢复 | **固定 0**（P1 只写 bit0） | P0 已用 bit0 |
| 14 | **与在飞板级轮/工具 agent 的排期** | P1 实施/构建等其收口 / 另开 worktree 并行 | **另开 worktree 实施；板级等收口** | 并发约束 |

---

## 附录 A —— 证据索引（本件引用位置，全部 2026-10-17 现读）

**源码（board/rtl）**
- `board/wrapper_p4.v`：`:166-202` P7B 端口表 · `:299-345` 通道选择/时钟域说明 · `:346-352` P7B 线网声明 · `:430-563` `pcs64 u_pcs`（ch0 `:437-481` / ch1 `:483-527`）· `:601-608` ch0 常量 IDLE · `:618-650` PCS/MAC 复位 · `:699-704` 域别名 · `:819-919` ch1 RX MAC · `:932-943` `u_rxcdc(76)` · `:975` `vlan_strip` · `:998` `rx_classify` · `:2069` `tcp_cam` · `:2276` `tcp_tx_frame` · `:2325-2329` `cam_rd_*` · `:2436` `udp_split` · `:2470` `cfg_dst_ip` · `:2564/2610` 慢路径适配 · `:2743` `udp_tx_cfg` · `:2762` `cfg_my_ip` · `:2814/2865` 两级 `tx_arb` · `:2891` `u_txcdc(73)` · `:2917-2939` `mac_tx_10g` · `:3394` `SNAP_NW_P6E=76` · `:3415` `SNAP_P7BDP_NW=36` · `:3665-3670` `pcs_ch0_sig` · `:3674-3708` ch1 3FF · `:3710-3725` ch1 事件计数 · `:3745-3761` W39/W40 · `:4163-4208` `p7bdp_din` · `:4210-4227` 三束 `snap_cdc` · `:4233-4248` seen/busy/valid · `:4263-4304` `snap_dout_all` · `:4467-4475` SFP TX_DIS · `:4479` `BUILD_ID_V` · `:4960` `.SNAP_NW`
- `board/build_p7b_ku5p.tcl`：`:45-59` IP 配置（`NUM_OF_CORES=2`/`LANE1/2`）· `:111-112` MAC 导入 · `:145` `verilog_define` · `:266-286` 约束 · `:294-327` synth/impl/reports
- `board/ku5p_p7b_gt.xdc:22-51` · `board/ku5p_p7b_cdc.xdc:36-39` · `board/p7b_pcs_stub.v:41-263`（inj `:169-172`；status `:210-263`）
- `_proj_10g/p7b_mac/rtl/mac_rx_10g.v:72-`（端口/计数 `:340-470`）· `mac_tx_10g.v:35-68` · `rtl/tx_arb.v` 全文 · `rtl/rx_classify.v:26-66` · `rtl/vlan_strip.v` · `rtl/tcp_cam.v:9-33` · `rtl/app_ctrl.v:28-33` · `rtl/slow_cfg_adp.v:7,148` · `rtl/udp_tx_cfg.v:66-77` · `rtl/udp_split.v:209-213` · `rtl/snap_cdc.v:80-131` · `_proj_pcie/rtl/axi_regs.v:187-192,206-217,350-450`

**仿真/构建**
- `_proj_10g/p7b_chain/sim/run_tb_p7b_chain.bat:1-48`（配置/define）· `tb_p7b_chain.v:98-114`（LOS/实例）· `:1440-1522`（快照组/未实现 `0x160`）· `:1969-1975`（`snap_take`）
- `sim/p6e_pcie/run_tb_p6e_pcie.bat:15,24`（文件/define，无 `P7B_10G`）· `tb_p6e_pcie_wrapper.v:440-448,545-548`（未实现 `0x160`）
- `sim/p4gates/run_matrix_p4dfix.bat:180-241`（19 门；`p5_wrapper` 配置 `:206-211`）
- `_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py:480-494`（STAGES 到 0x2A）· `:301`（UNIMPL 公式）

**基线/历史**
- `_proj_10g/notes/p9_build_0x2A_20261017/README_FOR_TL.md` §①②⑤（WNS/资源/读侧）· `_proj_10g/notes/p9_build_0x28/REPORT.md:93,100,121-129`
- `_proj_10g/notes/p9_dual_sfp_plan_20261017/DESIGN.md`（§0.5 用户裁定 / §1–§7）· `_proj_10g/notes/p9_dual_sfp_p0_20261017/README_FOR_TL.md`
- `P7B_GATE1.md:25-31,86-91` · `P7B_GATE2.md:28-29,94-97` · `P7B_XXV_OFFICIAL.md` · `P7B_BRAM_REPORT.md:22-24` · `agent_docs/P7B_SPEC.md`
- 仓根 `CLAUDE.md`「本板实测修正 §1/§1b」· `~/.claude/fpga_net_dev.md` §六（#54/#55/#57/#62/#66/#68 等）

---

## 附录 B —— 与派单/上位件的差异（如实登记）

| # | 差异 | 依据 |
|---|---|---|
| B-1 | 工作树是 **0x2A（76 字 / `0x160` / WNS +0.039）**，不是派单写的 0x28（75 字 / `0x15C` / +0.065）；板上现役才是 0x28 | `wrapper_p4.v:3394,4479`；`p9_build_0x2A.../README_FOR_TL.md` |
| B-2 | ch0 不是“只例化了 1 core”：是 **2 通道核**；TX 已接常量 IDLE；RX 数据未接 | `build_p7b_ku5p.tcl:48-59`；`wrapper_p4.v:430-563,601-608` |
| B-3 | 10G MAC 在 `_proj_10g/p7b_mac/rtl/`，不在 `rtl/` | `build_p7b_ku5p.tcl:111-112` |
| B-4 | plan §2-S2 的“流 76→77 + CAM +1 位”在甲模式（用户裁定单独 IP）下**可降级为无标签路线** | `slow_cfg_adp.v:7,148`；§4.4 |
| B-5 | plan 的“`fifo_async(73→74)`”应订正为 **73 位 × 两条**（端口位在 split 处消费） | §2.2 |
| B-6 | plan §5 P1 把“ch0 自环/图案发生器”列为可选；本件建议**不加 ch0 TX MAC** | §6.4 #11 |
| B-7 | 甲的“单独 IP”会**强制 HLS 改两个本地 IP**（不是“HLS 零改动”）；plan §0.5 已提示，本件把成本钉到行 | `hls/src/eth_types.h:123` 等；§4.6 |
| B-8 | 常驻矩阵 `p5_wrapper` 只编 `APP_MODE`，对 P1 零覆盖；`p6e` 不编 `P7B_10G` | `run_matrix_p4dfix.bat:206-211`；`run_tb_p6e_pcie.bat:24` |

---

## 附录 C —— 未测/纸面/未判定声明

1. **全部资源数字（除 `mac_rx_10g` 的 OOC 值外）= 纸面**（结构估计，小项 ±50%）；`mac_rx_10g` 的 1,453 LUT / 911 FF 是 OOC 上界，不是 placed 增量。
2. **WNS 预测 = 不可给**。0x2A 的 +0.039 是唯一可信输入；新增逻辑的布局影响无法纸面预测。**不许把 +0.039 减一个估计值当“预期 WNS”。**
3. **`rx_clk_out_0` 在无光/拔线时是否停钟 = 【未判定】**。§3.3 的超时机制是防御性设计，不能反过来当“它一定会停”的证据。
4. **P1 的 ch0 RX 帧计数是否与对端 NIC 逐帧吻合 = 【未测】**；S-2 是判据草案，窗口边界/背景流量会带来非零偏差，必须记背景。
5. **BER 无直接读数**；W76/W77/W81 只是代理。正式 BER 需 PRBS/长时统计（P7a 配方），P1 不做。
6. **甲模式的 HLS 两 IP 改动 = 【未实施】/【未测】**；本件只给接口与成本，不给“HLS 能改通”的保证。
7. **乙模式的转发通路 = 【未实施】**；B-1 的缓冲容量/主机持续读能力未测（P9 的 C2H 读数可作量级参考，但 raw-frame tap 未做）。
8. **0x2A 的现役资格 = 【未判定】**（板级正结果已出，用户未裁）；本件的 7 字/83 字几何以 0x2A 为基，若改用 0x28 基则全部新字编号/地址按 §3.2 备选表平移。
9. **`snap_cdc` 新束的时钟组覆盖 = 【推断】**（应与 `u_snap_p7bfe` 同型）；构建轮必须用 `report_clock_interaction` + `12-4739` 复核。
10. **P1 的板级读数 = 【未测】**（设计件，未上板）；S-1..S-7 的“期望读数”不是判据裁定。

---

*本件 = P1 实施级设计（纯纸面 + 只读源码核对）。不含 PASS/FAIL 裁定；所有“达标/不达标”留待用户与后续实测。*

---

## TL 注（2026-10-17 18:45，代落）

- **用户已裁定 0x2A 转现役**（18:38，台账 §10-113）⇒ 待裁 #1 的"P1 基代"按 **0x2A** 执行（物理烧录排在慢盆夹逼轮收尾后；本设计以 0x2A 为基与此裁定一致）。
- 本件 §0.1 表中"现役资格待用户裁"一句，自本条起按"**已裁：0x2A 转现役（待烧录）**"读。
- 其余待裁问题（BID / 观测档位 / 快照超时机制与 `SNAP_STATUS[7]` / 乙模式转发目的地 / 甲 HLS 两 IP 改动授权 / 甲出口身份 / `p7b_chain` 入矩阵第 20 门 / LOS 负对照执行方式 / 乙位流暂缓 / ch0 TX MAC）未裁，保持待用户裁定。
- **TL 抽核（源码逐条现读）**：`wrapper_p4.v:601-608` ch0 TX 常量 IDLE、`rx_mii_d_0/rx_mii_c_0` 无消费者、`SNAP_NW_P6E=76`、`SNAP_P7BDP_NW=36`、`BUILD_ID_V=0x2A` 全部相符；`git status` 确认本 agent 未改 RTL/脚本（仅新增本目录）。
