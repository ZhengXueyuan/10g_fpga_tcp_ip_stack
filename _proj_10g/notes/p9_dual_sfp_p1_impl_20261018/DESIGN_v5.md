# P11（双 SFP+）· P1 实施 —— DESIGN_v5.md（ch0 bring-up + 观测面）**施工权威**

> 命名裁定（用户 2026-10-18）：本阶段（双 SFP+ 双光口）命名为 **P11**；内部子阶段仍称 P0/P1/P2/P3。
> 轮目录名 `p9_dual_sfp_p1_impl_20261018/` 保持不变（p9_* = 历史命名空间）。

- 日期：2026-10-18 · 角色 = **实施 agent**（本文件是施工依据；本轮不构建、不碰板/对端、不写 git）。
- 基线：工作树 **0x2A**（`board/wrapper_p4.v` 现读：`BUILD_ID_V = 32'h0000002A` @`:4479`；`SNAP_NW_P6E = 76` @`:3394`；未实现地址 `0x160`）。
  板上现役 = 0x2A（台账 §10-117；2026-10-17 19:17 已烧）。
- 目标：P1-甲位流 **0x2B**（**83 字 / 未实现 `0x17C`**）；乙位流（0x2C）留到 P3。
- 上位件：`p9_dual_sfp_p1_design_20261017/README_FOR_TL.md`（设计 v4.1）+ `p9_review_dual_sfp_p1_design_20261018/FINDINGS.md`（红队：阻断 0 / 高 7 / 中 20 / 低 10）。
- 口径：**不下 PASS/FAIL 裁定**；状态词 =【已证·源码】/【已证·构建】/【已证·板级】/【推断】/【未判定】/【未测】；纸面数字一律标“纸面”。「未观测到」≠「不存在」；「不支持」≠「证伪」。
- 行号 = **2026-10-18 现读**；引用一律“文件:行号 + 符号名”，不按任何历史件的行号施工（FINDINGS 高-7）。

---

## 0. 用户裁定回灌（2026-10-18，全部已落台账）

| # | 裁定 | 本设计落点 |
|---|---|---|
| U-1 | **双 SFP+：P1 = ch0（J7/SFP A）bring-up + 观测面** | §2/§3；P1 只接 ch0 RX，不接数据面 |
| U-2 | **不采用双栈 ⇒ 维持 S2 单栈**（放弃 2×10G 同时满速）；**P3 判据改写** | §8；聚合 ≤ ~9.5 Gbps + 每口公平份额 + 每口丢帧/背压计数可读 |
| U-3 | 出口身份 = **A-1（IP 即身份）**；**P1 不含出口选口** | §9 P2 清单（wrapper 16 槽端口位、`tcp_tx_frame` 源 IP/校验和、TX 1 位穿两级 `tx_arb` 等全部留 P2） |
| U-4 | 乙模式 = **只镜像第一个口的 RX、从第二个口发出；不转发 TX；与 PCIe 无关** | §1.3；P1 不做 ch0 TX MAC；镜像目的地留 P3 |
| U-5 | **HLS 两 IP 已授权**，P2 实施，须同时支持 **1 或 2 个端口**（单口零回归） | §9 P2 清单 §9.3 |
| U-6 | 观测：**开发期 W76..W82 共 7 字全部实现**；**功能测试完成后拆掉只留最小集** | §4；最小集建议见 §4.7（本轮不拆） |
| U-7 | 板上现役 = 0x2A（76 字 / UNIMPL `0x160` / BID 0x2A）；P1 目标 = **0x2B（83 字 / UNIMPL `0x17C`）** | §5/§10 |

---

## 1. P1 范围与边界

### 1.1 做（本文件施工面）

1. `board/wrapper_p4.v`：ch0 第二只 `mac_rx_10g` + 固定 76 位 RX tap + sink/计数束；ch0 PCS 状态/事件；LOS；模式位；快照 **W76..W82**；`SNAP_NW_P6E 76→83` / `SNAP_P7BDP_NW 36→39` / `SNAP_CH0_NW=4`；快照汇合超时 + `SNAP_STATUS[7]`；`SFP2_MODE_A/B` 开关与 elaboration 硬门；`BUILD_ID_V=0x2B`；四宏组合线网声明安全。
2. `_proj_pcie/rtl/axi_regs.v`：`SNAP_STATUS[7]`（`ch0_snap_to` 的逐代锁存）。
3. `board/p7b_pcs_stub.v`（**sim-only**）：ch0/ch1 的 `rx_clk` 与 status 拆分。
4. `_proj_10g/p7b_chain/sim/tb_p7b_chain.v`：新几何、W76..W82 生产者 force、ch0 注入臂、LOS 臂、超时臂、`snap_take` 硬断言、既有 force/W39 断言同步。
5. 新单元门（`_proj_10g/p7b_chain/sim/tb_p1_ch0_unit.v` + `run_tb_p1_ch0_unit.bat`）：ch0 tap/sink/计数、超时、LOS 沿、模式位、单口退化。
6. 门债：`run_tb_p7b_chain.bat` 加 `TCP_TX_OVL` + `-L xpm` + 矩阵隔离；`p7bchain_src.f`；矩阵第 20 门；`run_tx_ovl_gate.bat` 修复或替代门。
7. 读侧：`apply_readside_bid1c.py` 新增阶段 0x2B（83 字 / `0x17C`，WLABEL/NAME/W/V/FAKE_TAIL，MIR 四址迁移，20 文件）；`P7B_BIZ_WINDOW.md` 更新；自检 A/B/C/D + 负控（table/bid/tier/face）。

### 1.2 明确不做

- Vivado 综合/实现/bitstream（下轮）；HLS 改动（P2）；ch0 TX MAC（乙阶段）；A-1 出口选口（P2）；板级。
- 不改 ch1 数据面、PCS/GT、参考钟、复位序列、XDC 时钟组（预期零改动，构建轮复核）。
- 不改 `D:\repo\perfv`；不写密码；不做 git 提交。

### 1.3 乙模式口径（只登记，不实施）

- ch0 RX 原始帧 → 镜像出口（目的地 P3 定；B-1 PCIe C2H 为推荐）；**不转发 TX**；**与 PCIe 无关**（乙阶段另加 ch0 TX MAC 时也只在 P3）。
- P1 的 tap/sink 是两种模式共同基础；P1 的甲/乙位流功能相同、只有模式位/BID 不同 ⇒ **P1 只建甲**。

---

## 2. ch0 RX tap + sink（P1 核心新增）

### 2.1 时钟/复位

| 项 | 设计 | 现读锚点 |
|---|---|---|
| ch0 RX 域 | `gmii_clk_0 = rx_clk_out_0`（PCS CDR 恢复钟） | `wrapper_p4.v:443`（`rx_clk_out_0` 端口）、`:633`（`rx_core_clk_0` 自环） |
| ch0 TX 域 | `tx_fe_clk_0 = tx_mii_clk_0`（仅域别名；P1 无消费者） | `wrapper_p4.v:442`、`:601-608` |
| ch0 MAC 复位 | `(* ASYNC_REG *) reg [2:0] rstn_rx_sr_0`；`rst_n_ch0 = rstn_rx_sr_0[2] & ~pcs_user_rx_reset_0` | 仿 ch1 的 `:415-416,640-650` |
| 复位极性 | `pcs_user_rx_reset_0` 高有效（MAC 端口合同 `rst_n = ~user_rx_reset_N`） | `p7b_mac/rtl/mac_rx_10g.v:72`；`:451` |
| ch0 TX | **保持常量 IDLE**（`p7b_ch0_idle_d/c` 不动） | `wrapper_p4.v:601-608` |

> ch0 的 `rx_clk_out_0` 在无光/拔线时是否停钟 = **【未判定】**；历史观察 `P7B_GATE2.md:95` 记录 `rx0_free = 0`（原文读作“恢复时钟死”），但计数器为 0 也可由复位/无沿解释 ⇒ 本设计**按“可能停钟”设计超时**（§5），不把该观察当已判定。

### 2.2 tap 合同（先冻结，P2/P3 直接挂）

```
ch0_rx = {tdata[63:0], tkeep[7:0], tuser, tlast, tcrs, terr}   // 76 bit AXIS, rx_clk_out_0 域
         + tvalid / tready
合同 = 与 mac_rx_10g / mac_rx_64 输出逐字相同:
  tdata[63:56] = 帧首字节; SOP 满对齐(tkeep[7]=1); TLAST 的 tcrs = FCS 正确;
  TERM 六元组 = {0,0,tlast=1,tuser=0,tcrs=0,terr=1}
```

### 2.3 sink 与计数（W79..W82 的源）

- `assign ch0_rx_tready = 1'b1;` —— **sink 必须是真消费者**（计数/状态有真实负载；否则读侧可能被修剪 ⇒ FIFO 填满 ⇒ 帧计数退化为丢帧计数）。
- 好帧定义（FINDINGS 中-16）：**`tvalid && tready && tlast && tcrs && !terr`**。
  - `ch0_rx_frames`（W79）：好帧数，32 位自由回卷。
  - `ch0_rx_bytes`（W80）：**仅好帧**的 `Σpopc(tkeep)`；帧内用 `ch0_acc_bytes` 累加，TLAST 且好帧才提交；坏帧（`!tcrs` 或 `terr`）丢弃累加器。
  - `ch0_fcs_err`（W81）= `u_mac_rx_ch0.stat_crc_err`（MAC 口径：推入时按 `!res_ok` 计）。
  - `ch0_drop`（W82）= `u_mac_rx_ch0.stat_drop`（MAC 口径：整帧丢，含空间/碎片/零长）。
- **口径警告（必须写进读侧/报告）**：
  - W81/W82 与 W79 **不是同一计数点**；`W79 + W81 + W82` **不是**“收到帧总数”（TERM 字/碎片会重复计）。
  - 对好帧：`W80 + 4×W79 = 线上字节（含 FCS）`；对端 NIC 的 `port_tx_bytes` 口径（前导/IFG/pad）**板级前现核**（FINDINGS E-6）。
  - 32 位计数器 @156.25 MHz **27.487 s 回卷** ⇒ 差值判据必须 mod 2³² 且记原始值（全局 #55）。
  - `pcs_user_rx_reset_0`（W76[28]）有效时 ch0 MAC 计数器清零 ⇒ 跨复位差值无效。
- `mac_rx_10g` 其余输出（XGMII 层证据）**只接必要的**：P1 只消费 `stat_crc_err/stat_drop` 与本 tap；不新增第二套 W36..W38 式 XGMII 计数（P1-min 成本控制）。

---

## 3. ch0 PCS 状态/事件/LOS

### 3.1 PCS 状态同步（W76）

- ch0 的 `stat_*_0` 输出（当前接到 `pcs_ch0_u_*` 线，`:458-469`）**改为逐位 3FF 同步进 `dp_clk`**（与 ch1 的 `:3674-3708` 同款、同域）：
  - 单 bits：`blk_lock_0`、`rx_status_0`、`hi_ber_0`、`rx_localfault_0`、`tx_localfault_0`、`framing_err_0`、`framing_err_valid_0`、`bad_code_0`、`bad_code_valid_0`、`fifo_error_0`、`valid_ctrl_code_0`、`rx_error_valid_0`、`gtpowergood_0`、`user_rx_reset_0`、`user_tx_reset_0`（15×3 = 45 FF）。
  - `rx_error[7:0]`：每 bit 各一个 3FF（8×3 = 24 FF）；**逐 lane 语义，不得当 8 位数值引用**。
  - `ch0_sig`：`pcs_ch0_sig`（`:3665-3670` 的 XOR，**保留不动**以维持 W39[30] 与 ch0 输出的结构负载）；W76[30] 用它的 3FF 版 `pcs0_sig_sr[2]`。
- **W76 位域（写死）**：
  `[31]0 [30]ch0_sig [29]gtpowergood0 [28]user_rx_reset0 [27]user_tx_reset0 [26:22]0 [21]rx_error_valid0 [20:13]rx_error0[7:0] [12]valid_ctrl_code0 [11]fifo_error0 [10]bad_code_valid0 [9]bad_code0 [8]framing_err_valid0 [7]framing_err0 [6]tx_local_fault0 [5]rx_local_fault0 [4]hi_ber0 [3]rx_status0 [2]block_lock0 [1:0]0`
  （31 位有效 + 1 位保留；与 W39 同位域布局。）

### 3.2 PCS 事件（W77）

- `ferr/bad/erv`：8 位**饱和**计数器，语义与 ch1 W40 逐字相同 = “同步后为高的 dp 拍数”，**不是精确事件数**（`wrapper_p4.v:3710-3725` 的同一口径）。
- `vcc`：**选择 = 自由计数（mod 256），不饱和**。实现：`if (pcs0_vcc_sr[2]) pcs0_vcc_cyc <= pcs0_vcc_cyc + 8'd1;`（无 `!= 8'hFF` 门）。
  - 理由：`vcc` 在链路正常时几乎恒 1 ⇒ 饱和版 1.6 µs 就到 `0xFF`，S-1 的“静置 10 min 事件不增”会**永不成立**（FINDINGS 中-2/E-1）。自由计数至少保留“有控制码活动”的可变读数。
  - 口径：它是 **dp 拍数 mod 256**，只用于“动没动/活动指示”；跨窗口差值只对 `ΔW77[7:0]` 有意义，且窗口 > 1.6 µs 时无法还原绝对值。S-1 只对 `ferr/bad/erv` 断言不增。
- **W77 位域**：`[31:24]ferr_evt [23:16]bad_evt [15:8]erv_evt [7:0]vcc_cyc`（与 W40 同布局）。

### 3.3 LOS（W78）

- `sfp1_rx_los`（B11）/`sfp2_rx_los`（C9）是**异步板级引脚** ⇒ 各 3FF 同步进 `dp_clk`（`(* ASYNC_REG *)`）。
- **沿定义（统一，FINDINGS 中-4）：只数上升沿 = LOS 断言（0→1）**，8 位饱和。
- 上电 priming：复位后前 3 个 dp 拍只建基线、不计数（`los_prim_cnt != 3` 时只移位）；否则“上电即 +1”是假事件。
- **W78 位域**：`[31]SFP2_MODE_B_SEL [30:24]0 [23:16]los1_evt [15:8]los2_evt [7:2]0 [1]los2_level [0]los1_level`。
- 停钟时 PCS 状态可能停在最后一拍 ⇒ **以 W78 的 LOS 电平/沿为准**（板级引脚、dp 同步、独立于 PCS）。

---

## 4. 观测面（W76..W82，开发期全量）

### 4.1 字表

| 新字 | 内容 | 位域 | 束 / 域 | 源 |
|---|---|---|---|---|
| **W76** | ch0 PCS 状态 | §3.1 | p7bdp 槽 36 / dp | 3FF 后的 ch0 `stat_*_0` |
| **W77** | ch0 PCS 事件 | §3.2 | p7bdp 槽 37 / dp | dp 域事件计数器 |
| **W78** | LOS + 模式 | §3.3 | p7bdp 槽 38 / dp | LOS 3FF + priming + 计数；mode = 编译常量 |
| **W79** | ch0 RX 好帧数 | 32 位自由回卷 | ch0 束槽 0 / `rx_clk_out_0` | ch0 sink |
| **W80** | ch0 RX 载荷字节 | 32 位自由回卷 | ch0 束槽 1 / `rx_clk_out_0` | ch0 sink |
| **W81** | ch0 RX FCS 错帧数 | 32 位自由回卷 | ch0 束槽 2 / `rx_clk_out_0` | `mac_rx_ch0.stat_crc_err` |
| **W82** | ch0 RX 丢帧数 | 32 位自由回卷 | ch0 束槽 3 / `rx_clk_out_0` | `mac_rx_ch0.stat_drop` |

### 4.2 地址（基 = 0x2A ⇒ 83 字）

| 字 | 地址 | 备注 |
|---|---|---|
| W76 | `0x150` | ch0 PCS 状态 |
| W77 | `0x154` | ch0 PCS 事件 |
| W78 | `0x158` | LOS + mode |
| W79 | `0x15C` | ⚠️ 旧“未实现地址”变真字 |
| W80 | `0x160` | ⚠️ 0x2A 的“未实现地址”变真字 |
| W81 | `0x164` | |
| W82 | `0x168` | 末字（`SNAP_LAST_IDX` = 90） |
| MIR_STATUS/DATA/CTRL/DMA_CNT | `0x16C/0x170/0x174/0x178` | 由 `axi_regs.SNAP_LAST_IDX` 自动下移 |
| **未实现** | **`0x17C`** | `0x20+4×83+16`（0.5 字）；≤ 0x1FC，绝不 ≥ 0x200 |

- 预算：`{snap_idx,5'b0}` max = 82<<5 = 2624 < 4096（`snap_base [11:0]` 不动）；`r_word` max 95 < 128 ✓。
- **装配项数**：`14+22 + 3 + (39-4) + 5 + 4 = 83` ✓（p7bdp 槽 2..5 由 tx 束搬）。

### 4.3 快照汇合超时（P1 必需机制）

**问题**：`u_snap_ch0.clk_b = rx_clk_out_0`；该钟停 ⇒ `snap_cdc.busy_a` 永久高（`rtl/snap_cdc.v:78,117`；头注释 `:43-45`），若 `snap_valid_all` 仍等它，**整个 83 字窗口永久不可读**。

**设计（pcie 域）**：

1. **逐代 arming**：`snap_req` 拍采样 `ch0_ready = ~ch0_busy`（非 P7B：`ch0_ready=1`）。
   - `ch0_armed <= ch0_ready`；`ch0_seen <= 0`；`ch0_to_cnt <= 0`；`ch0_to_hit <= ~ch0_ready`（上一代仍卡着 ⇒ 本代视为陈旧）。
   - `snap_main_seen <= 0`（**必须在 `snap_req` 清零**，FINDINGS 高-5）。
2. **等待/超时**：`ch0_armed && !ch0_seen && !ch0_to_hit` 时，`ch0_to_cnt` 每 `pcie_axi_aclk` +1；到 **4095**（≈16.4 µs @250 MHz）置 `ch0_to_hit`。
   - **`ch0_seen` 只在 `ch0_armed=1` 时接受 `ch0_valid`**（防上一代迟到的 valid 被记到本代）。
3. **主束完成锁存**：`snap_main_now = snap_valid & p7bfe_seen & p7bdp_seen & tx_seen`；`snap_main_seen <= 1`（锁存到本代结束；超时可能晚于主束的 1 拍 valid）。
4. **本代完成**：`snap_done = snap_main_seen & (ch0_seen | ch0_to_hit | ~CH0_EXISTS)`；`snap_valid_all = snap_done & ~snap_done_r`（**1 拍脉冲**）。
5. **逐代状态**：`ch0_snap_to = CH0_EXISTS & ch0_to_hit & ~ch0_seen & snap_done`（组合；`axi_regs` 在 `snap_valid` 拍锁存）⇒ **`SNAP_STATUS[7]` = 本代 ch0 束缺失/陈旧**；非 P7B = 0（“不适用”，不是失败）。
6. **busy**：`snap_pending` 在 `snap_req` 置位、`snap_valid_all` 清零；`snap_busy = snap_pending | snap_seq_busy | p7bfe_busy | p7bdp_busy | txsnap_busy` —— **明确排除 `ch0_busy`**（FINDINGS 高-5；否则第一次超时后主机轮询永不落 busy）。
7. **陈旧语义**：`ch0_snap_to=1` 时 W79..W82 是上一代/复位值（不是本代）；W76..W78 仍是本代。主机**必须**读 `SNAP_STATUS[7]` 再决定是否信 W79..W82。
8. **非 P7B 构建（p6e 门）**：`CH0_EXISTS=0`、无实例、`ch0_snap_din=0`、`ch0_done_ok=1`、`ch0_snap_to=0` ⇒ W79..W82 恒 0，不误报超时。

**G1-f 双代断言（必须）**：停 ch0 rx 钟 → 连续两次 trigger 都返回；第一次 `SNAP_STATUS[7]=1`；第二次仍可读（`ch0_busy` 永久高 ⇒ 第二代 `ch0_armed=0` ⇒ `ch0_to_hit=1` 立即完成）。负对照：把“不等 ch0”分支去掉 ⇒ 该臂 TIMEOUT。

> ⚠️ 同一风险也存在于既有 `u_snap_p7bfe`（`clk_b = gmii_clk = rx_clk_out_1`）。P1 **不修**（不在范围），登记；若 P1 的超时机制验证有效，后续轮可泛化到所有束。

### 4.4 线网/宏组合安全（FINDINGS 中-9）

- 所有在 `PCIE_OBS` 装配段引用的 ch0 线网（`ch0_w76..w82`、`ch0_snap_din`、`ch0_valid/busy`、`ch0_snap_to`）**在 `PCIE_OBS` 段内无条件声明**；驱动分两支：
  - `ifdef P7B_10G`：真实值 / 真实实例；
  - `else`：常量（`ch0_snap_din=0`、`ch0_valid=0`、`ch0_busy=0`）。
- `PCIE_OBS ∧ ¬P7B_10G`、`¬PCIE_OBS ∧ P7B_10G`、`P7B_10G ∧ PCIE_OBS`、全关 四种组合必须 elaboration 零错（§10 门）。
- 坑 #24：新线网必须先声明后用；`snap_busy` 的拼接宽度、`snap_dout_all` 的项数/位宽逐项核对。

### 4.5 SNAP_STATUS[7]（axi_regs）

- 新输入 `ch0_snap_to`；`reg ch0_snap_to_r`；在 `snap_valid` 拍 `ch0_snap_to_r <= ch0_snap_to`。
- `snap_status = {snap_gen_r, 8'd0, ch0_snap_to_r, locked_axi, fe_state, snap_seen_r, snap_done_r, snap_busy}`（16+8+1+1+3+1+1+1 = 32）。
- bit 6 及以下**逐位不变**（既有脚本取位不受影响）。

### 4.6 读侧同步（构建轮，工具已在本轮落阶段 0x2B）

- `EXPECT_BID` 0x2A→0x2B；`SNAP_WORDS/NW` 76→83；`UNIMPL_ADDR` 0x160→0x17C。
- `WLABEL/NAME[]/W 表/V 表/FAKE_TAIL` 补 W76..W82；MIR 四址 `0x150/0x154/0x158/0x15C → 0x16C/0x170/0x174/0x178`。
- `sim/p6e_pcie/tb_p6e_pcie_wrapper.v` 的 73 处 `32'h` MIR 地址常量按**降序 token 替换**；`tb_biz_win.v` 的 NW/BID 更新（MIR 已由 NW 派生）。
- `0x15C/0x160` 的身份翻转 ⇒ 旧脚本的“未实现地址”断言**必红是预期**。

### 4.7 最小集建议（功能测试后；本轮不拆）

**建议保留 4 字**：W76（ch0 PCS 状态）+ W78（LOS+模式）+ W79（好帧）+ W80（载荷字节）。理由：
- W77 事件字是 BER 代理，功能测试后价值低于成本（40 FF + 1 字）；
- W81/W82 可由 MAC 侧 `stat_*` 的仿真面覆盖；板级若发生 FCS/丢帧，W79 停滞 + W76 状态可定位；
- 若板级链路调试仍需 FCS/丢帧，则保留 6 字（+W81/W82），删 W77。

---

## 5. 模式开关（SFP2_MODE_A / SFP2_MODE_B）

### 5.1 语义（统一，FINDINGS 中-8）

- **甲 = 默认**：**不传**或显式传 `SFP2_MODE_A=1` 均可；构建脚本默认**不传** A（也可以显式传 A 作“我确实选了甲”的构建见证）。
- **乙 = `SFP2_MODE_B=1`**。
- 单开关 = `SFP2_MODE_B` 的有无；`SFP2_MODE_A` 只作显式见证。

### 5.2 elaboration 硬门（照 `g_orph_zw_guard` 手法，`wrapper_p4.v:226-241`）

- `SFP2_MODE_A ∧ SFP2_MODE_B` ⇒ 例化不存在的模块 ⇒ elaboration 硬失败。
- `SFP2_MODE_B ∧ ¬P7B_10G` ⇒ 同样硬失败（乙模式只对 10G 前端有意义）。
- 其余组合（默认/A/无宏）正常。

### 5.3 P1 实现边界

- P1 只落开关 + **W78[31] 模式条**；甲/乙功能分叉在 P2/P3（甲 = `rx_merge2`；乙 = 镜像）。
- P1 甲/乙位流功能相同、只有模式条/BID 不同 ⇒ **P1 只建甲（0x2B）**；乙位流（0x2C）留到 P3。
- 构建脚本：`board/build_p7b_ku5p.tcl:286` 的 `verilog_define` **追加**（不覆盖）`SFP2_MODE_A=1`（甲）或 `SFP2_MODE_B=1`（乙），两者**同时传 = 硬失败**。⚠️ `:145` 是 `set_msg_config`，不是 `verilog_define`（FINDINGS 中-1）。

---

## 6. 构建几何与身份（0x2B）

- `SNAP_NW_P6E = 83`；`SNAP_P7BDP_NW = 39`；`SNAP_CH0_NW = 4`；`SNAP_P7BFE_NW = 3`；`SNAP_TX_NW = 5`。
- `BUILD_ID_V = 32'h0000002B`。
- 未实现地址 `0x17C`；MIR 四址 `0x16C/0x170/0x174/0x178`。
- 位流尺寸预期仍 15,431,261 B（全代同尺寸）⇒ **只有 sha256 + BID 能分版**。
- 源码面核对：`SNAP_NW_P6E = 83` / `SNAP_P7BDP_NW = 39` / `BUILD_ID_V (32'h0000002B)` / 装配项数 83。

---

## 7. 资源/时序预算（纸面；构建轮观察点）

| 项 | FF | 说明 |
|---|---|---|
| W76..W78 的 `hold_b`（p7bdp 3 字） | +96 | dp 域（3×32） |
| ch0 PCS 3FF | +69 | dp 域（15×3 + 8×3） |
| ch0_sig 3FF | +3 | dp 域 |
| W77 事件计数 | +32 | dp 域（4×8） |
| LOS 3FF + 计数 + priming | +22+2 | dp 域 |
| ch0 束 `hold_b`（NW=4） | +128 | `rx_clk_out_0` 域 |
| pcie 域 `dout_a` + `snap_words_r` | **+448** | 7×32×2 |
| 超时 FSM + 状态锁存 | ~+20 | pcie 域 |
| ch0 sink 累加/计数 | ~+40 | `rx_clk_out_0` 域 |
| **DP 域合计** | **≈ +223…230** | FINDINGS 高-6 的口径（不是 v4.1 的 ~110） |
| **pcie 域合计** | **≈ +468** | 448 + 超时/锁存 |

- `mac_rx_10g` 第二实例：**+1,453 LUT / +911 FF**（OOC 上界；`p7b_mac_synth/mac_only/`）。
- 总纸面增量 ≈ **+1.5k LUT / +1.8k FF / +0 BRAM / +0 URAM**。
- **时序预测 = 不可给**（0x2A WNS `+0.039` = 0.61%，全局宿主 = DP setup）。构建轮重点观察：
  1. DP 域 top-10 是否出现 `u_snap_p7bdp/hold_b_reg[*]`、`pcs0_*_sr`、LOS 计数器端点；
  2. pcie 域快照阵列异步复位族是否重新成为全局宿主（0x28 的先例）；
  3. `report_clock_interaction` 是否把 ch0 束当异步（预期：`gtrefclk0` 的 `-include_generated_clocks` 覆盖，【推断】）；
  4. `12-4739` 0 命中。
- **一次构建收口**；backstop 顺序见 §10.3。

---

## 8. P3 判据改写（回灌 U-2；P1 不实施）

**S2 单栈** = 一套快路径 + 一条 10G TX 线 + 一条 RX 合并输出 + 共享 `WIN_POOL = 49152 B`。因此：

1. **聚合 ≤ 线上载荷天花板** `1460/1538 × 10 = 9.4935 Gbps`（纸面；实测按单口 9.1–9.3 Gbps 量级）；**不写“每口向天花板逼近”**。
2. **每口公平份额**：`rx_merge2` 必须 round-robin（或 deficit round-robin），**不得照抄 `tx_arb` 的严格优先**；每口最多等一帧。
3. **每口丢帧/背压计数可读**：合并前 FIFO 深度 ≥ 2 个最大帧或加 per-port drop 计数；判据 = 两口各灌满时**两口计数都前进**；负对照 = 改回严格优先 ⇒ 低优先口计数停滞（必须红）。
4. **共享 `WIN_POOL` 的后果**：两条连接各 ~24.6 KB ⇒ 10G BDP 支持 RTT ≤ **19.7 µs**；单连接仍为 ~39.3 µs。实测 `minrtt 6–8 µs / srtt 16–27 µs` ⇒ 双连接上沿越墙。P3 必须现取 `ss -ti` 作见证量，**不得承诺 2×10G**。
5. S2 不是 2×10G，而是 **10G 聚合分担**；2×10G 需要独立数据面（双栈，已由用户否）。

---

## 9. P2 改动清单（A-1 出口身份；U-3 明确“P1 不含”）

> 本清单只登记，不实施。依据 `p9_dual_sfp_exit_identity_compare_20261018/README.md` + FINDINGS 高-3/高-4。

### 9.1 端口身份来源（RX/建连，零改动）

- `slow_cfg_adp` 的 `w2 = local_ip` 已写入 `cam_cfg_dip`（`rtl/slow_cfg_adp.v:122,148`）；`tcp_rx` 用帧的**目的 IP** 组 CAM 键（`rtl/tcp_rx.v:213,443-446`）；`tcp_cam` 已有 `rd_dip`（`rtl/tcp_cam.v:36`）；wrapper 的 `cam_rd_dip` 已连线（`board/wrapper_p4.v:1904,2088`）。
- 端口位：**wrapper 16 槽 1 位数组**，在同一 `cam_cfg_wr_mux` 拍写 `port_arr[cam_cfg_addr_mux] <= (cam_cfg_dip_mux == IP1)`（现读 `:2061-2067`）；**零改 `slow_cfg_adp`/`tcb`**（不碰 `tcb.v` 的 `upd_sel=7` 守卫）。读口按 `rb_id` 组合读。
- 备选：TCB 1 位（`rtl/tcb.v:36-75,94-105`；需 `upd_sel` 选择或独立 `port_wr` 口）或每帧比较 `cam_rd_dip`（+2 级 LUT）。

### 9.2 TX 侧（A-1 的**完整**改动面；FINDINGS 高-3/高-4）

| # | 文件 | 改动 |
|---|---|---|
| 1 | `rtl/tcp_tx_frame.v` | +`cam_rd_dip` 输入；per-bank + ctrl 的 `local_ip` 锁存（OVL 装载点 `:1205-1208,1324,1354-1357`；默认体 `:2284,2411`）；`ip_csum_calc` 加 `src_ip` 入参（`:392-405,400-401,2008-2012`）；数据帧 `csum_init_val`（`:817-819,2022-2024`）与控制帧 `csum_init_ctrl`（`:874-876`）；头字源 IP（`:1440,2481`）；**OVL/默认两体同改**；+`o_port` |
| 2 | `rtl/tcp_tx_frame.v` 重放 | `f_local_ip/o_port` 必须按 bank 锁存（重放与首帧一致） |
| 3 | `rtl/tx_arb.v` | 73 → **74 位**（+1 位 port）；两级实例（`wrapper_p4.v:2814` `u_tx_udp_arb`、`:2865` `u_tx_arb`）同改；或把 split 前移到各生产者（复制 arb，73 位不变） |
| 4 | 新 `tx_split2` | 插在 `u_tx_arb.m_axis` 与 `u_txcdc`（`:2891`）之间；每条 `fifo_async(73×256)` + `mac_tx_10g`；**ch0 `mac_tx_10g` 替代常量 IDLE**（P2/乙） |
| 5 | `rtl/udp_rx.v` | 引出 `meta_dst_ip`（纯线束；`ip_match` 已算，`:180-181`） |
| 6 | `rtl/udp_split.v` | `meta_dst_ip` 透传（meta `:209-213`） |
| 7 | `rtl/udp_tx_cfg.v` | peer 表 +`my_ip`/port（`:66-77,106-126`）；`cfg_my_ip` 从常量改为按 peer |
| 8 | `rtl/slow_tx_adp.v` | 源 IP 提取（帧字节 26..29）→ port（纸面 +40 FF/+10 LUT）；不变式 = **HLS TX 不加 VLAN**（`insert_vlan` 当前无生产者，`hls/src/eth_types.h:211-217`、`layer_mac.cpp:218`） |
| 9 | `rtl/app_ctrl.v` | 可选事件字 +1 位 port（102→103，`:28-35`） |
| 10 | `board/wrapper_p4.v` | `cam_rd_dip` 接进 `tcp_tx_frame`；UDP 过滤二值集（`:2470`）；`cfg_my_ip`（`:2762`）；split/arb 接线 |
| 11 | `hls/src/*` | 双本地 IP 成员判定 + 用命中 IP 作源：`eth_types.h:119-123`、`layer_ip.cpp:76`、`layer_arp.cpp:149,194,201`、`layer_icmp.cpp:142-143`、`layer_igmp.cpp:121-122`、`layer_udp.cpp:168-169`、`layer_tcp.cpp:177,277,292`；**必须重跑 HLS 综合**；单口时行为逐位不变（1 或 2 口兼容） |
| 12 | 观测 | 每口 TX 计数进快照（否则“发错口”不可观测）；对端 p0/p1 分 netns/子网 + 显式 `/32` 路由 |

### 9.3 其它 P2 前置

- `udp_split.cfg_dst_ip` 从单值改为二值集合（`wrapper_p4.v:2470`）。
- `cfg_src_mac` 是否 per-port（同 MAC 直连可行；接交换机/同 L2 需两 MAC）——待用户定。
- `MAX_TCP_CONN = 3`（HLS）为全系统上限（不影响 A-1）。

---

## 10. 构建前置与门计划

### 10.1 构建输入（下一轮）

1. `board/wrapper_p4.v`：本轮改动（§2–§6）。
2. `board/build_p7b_ku5p.tcl:286`：追加 `SFP2_MODE_A=1`（或 B）。
3. BID bump = 0x2B（本轮已改源码；构建轮再核）。
4. 构建前 `tasklist | grep vivado` 无进程；一次构建收口；记录构建输入哈希 before/after。
5. 构建后：WNS/WHS/三类失败端点、`12-4739`、隐式网五键、DRC、`report_clock_interaction`、位流 sha256、资源。

### 10.2 门（本轮已跑/将跑）

| 门 | 内容 | 覆盖 |
|---|---|---|
| G1-a 基线 | `run_tb_p7b_chain.bat`（+TCP_TX_OVL） | 既有链级判据 |
| G1-b 新几何 | 0x17C 未实现；W76..W82 地址-值 | 读侧译码 |
| G1-c ch0 状态 | force stub ch0 生产者（与 ch1 不同值） | W76 vs W39 独立性 |
| G1-d ch0 帧计数 | 第二 XGMII 队列注入 N 帧 | W79/W80；`tready=0` 负对照 |
| G1-e LOS | `sfp1_rx_los` 0→1→0 | W78 电平/沿/priming |
| G1-f 超时 | force ch0 rx 钟停；双代断言 | 窗口仍可读 + SNAP_STATUS[7] |
| G1-g ch0 TX | `txcap_d0/c0` | 恒常量 IDLE |
| G2 p6e | 非 P7B 几何/身份 | W76..W82 读 0 |
| G3 矩阵 | 20/20 | 默认构建回归 |
| G4 单元门 | ch0 tap/sink/超时/LOS/模式/单口 | P1 专项 |
| G5 四宏组合 | elaboration | 线网声明安全 |

### 10.3 backstop（构建失败时，按序；每一次 = 新输入）

1. **B1**：删 W77 ⇒ 6 新字 / NW 82 / `0x178`。
2. **B2**：删 W79..W82（ch0 计数束 + ch0 MAC 实例）⇒ 3 新字 / NW 79 / `0x16C`。
3. **B3（P1-min）**：删 W77/W79..W82，只留 W76+W78 ⇒ 2 新字 / NW 78 / `0x168`（P1 退化为“ch0 link + PCS 状态 + LOS”，不交帧计数，需用户接受）。
- 每档更新读侧阶段与 TB 几何；**不许在同一输入上反复重跑**。

### 10.4 板级判据草案（P1 上板轮；不写 PASS/FAIL）

前置：重烧 + 核 sha256 + 身份门（`0x04=0x2B` / 83 字 / `0x17C`=`0xffffffff` / 2 BARs / `LnkSta x4`）；对端 p0 `managed no` + `ip link up`；ch1 保持现役配方；`0x08` **bit1 保持 0**。

| # | 动作 | 期望读数（草案） | 独立仪器/负对照 |
|---|---|---|---|
| S-1 | 静置 10 min（两口连、ch1 不跑业务） | 对端 p0 `carrier=1`；板 W76[2]=1、W76[4]=0、W76[5]=0、W76[6]=0；W77 的 ferr/bad/erv 不增（vcc 自由计数不判）；W81=W82=0；W78[0]=0 | 对端 `ip -br link` / `ethtool -S`；板快照 |
| S-2 | 对端 p0 发 N 帧已知长度 | `ΔW79=N+背景`、`ΔW80=Σ(wire−4)+背景`、W81=W82=0；`W80+4×W79=Δport_tx_bytes`（先现核 NIC 口径） | NIC 硬件计数 + pcap |
| S-3 | TX_DIS 负对照：`0x08=0x1` → 4 s → `0x08=0x0` | 对端 p0 `carrier 1→0` 且 `carrier_changes` **单调增 ≥1（记录实际值；P0 实测同一动作 +3，不钉死 +1）**；p1 不变；恢复后 0→1 | P0 已证；本条复算 |
| S-4 | LOS：拔 J7 AOC → 恢复 | `W78[0] 0→1`、`W78[23:16]` **+1（只数上升沿）**；对端 p0 `carrier 0`；W76[2] 期望 1→0（若 ch0 钟停则可能不变 ⇒ 以 W78 为准）；**窗口仍可读**（`SNAP_STATUS[7]` 按实际记录） | 物理拔插；若用 `ip link set down` 先确认真能关光 |
| S-5 | ch0 长收（10 min 低速图案流） | `ΔW81=0`、`ΔW82=0`；W77 ferr/bad/erv 不增；`ΔW79=对端 port_tx_packets`（±0.2%） | BER 代理；PCS 无 BER 数值 |
| S-6 | ch1 业务回归（同会话 A/B：0x2B vs 0x2A） | ch1 UDP/TCP 读数同档、`mism_bytes=0`、丢弃计数不增；W0/W1/W20/W43 同量级 | 同板同线；记录台架帽（#43/#59/#68） |
| S-7 | 双口并存静置/轻载 | 两口 `carrier=1`、W76[2]=1、ch1 不退化；无新 W81/W82 | **温度/功耗 = 未测（无板上仪器）**（FINDINGS 中-14/E-4） |

---

## 11. FINDINGS 逐条处置

### 11.1 高（7）

| # | 处置 | 理由/落点 |
|---|---|---|
| 高-1 | **改形（判据）** | P3 判据改写为“聚合 ≤ ~9.5 Gbps + 每口公平份额 + 丢帧/背压可读”（§8）；P1 不实施 |
| 高-2 | **改形（P2/P3 设计约束）** | `rx_merge2` 必须 round-robin；FIFO ≥2 帧或 per-port drop；负对照“改回严格优先必红”（§8） |
| 高-3 | **采纳（P2 清单）** | 端口位穿两级 `tx_arb` 的承载方式写明（74 位或 split 前移）（§9.2 #3/#4） |
| 高-4 | **采纳（P2 清单）** | A-1 的 `tcp_tx_frame` 源 IP/IP 校验/TCP 种子/双体全部列入；明确“A-1 vs §0.5 CAM+1”需用户再裁（U-3 已裁 A-1） |
| 高-5 | **采纳** | `snap_busy` 排除 `ch0_busy`；`snap_main_seen/ch0_seen/ch0_to_hit/ch0_to_cnt` 在 `snap_req` 清零；G1-f 双代断言（§4.3） |
| 高-6 | **采纳** | FF 预算按 **DP ~223…230 / pcie ~468** 重算；构建轮 DP 观察点（§7） |
| 高-7 | **采纳** | 行号一律现读/符号引用；本文件不复制 plan 行号（§0 头） |

### 11.2 中（20）

| # | 处置 | 落点 |
|---|---|---|
| 中-1 | **采纳** | `build_p7b_ku5p.tcl:286` 追加宏，不覆盖（§5.3） |
| 中-2 | **采纳（选择：vcc 自由计数 mod 256）** | S-1 只对 ferr/bad/erv 断言；vcc 只作活动指示（§3.2） |
| 中-3 | **采纳** | `carrier_changes` 单调 ≥1 + 记录实际值（§10.4 S-3） |
| 中-4 | **采纳** | LOS 沿定义统一 = **只数上升沿**；G1-e 与 S-4 同口径（§3.3） |
| 中-5 | **采纳** | 引用 `P7B_GATE2.md:95 rx0_free=0` 两种解释；超时从“防御性”升为“有历史支持的必需项”（§2.1 注） |
| 中-6 | **采纳** | stub 拆 ch0/ch1 status 时同步既有 force/W39 断言（`tb_p7b_chain.v:1463-1465,1482-1483` 改 ch1 限定名）（§12 改动清单） |
| 中-7 | **采纳** | `p7b_chain` 入矩阵的 manifest/私有 workdir/字面文件表完整工作量（`p7bchain_src.f` + P4_WORKDIR + 本文件 §12） |
| 中-8 | **采纳** | 模式语义统一（§5.1） |
| 中-9 | **采纳** | 四宏组合线网声明安全（§4.4） |
| 中-10 | **登记（P2）** | plan §2-S2 的标签贯穿漏项列入 P2 清单（§9.2） |
| 中-11 | **登记（P2）** | HLS 零改动与“单独 IP”冲突 ⇒ HLS 双 IP 为 P2 硬前置（§9.2 #11） |
| 中-12 | **登记（P3）** | 乙模式 = S3d（RX raw-frame mirror），P3 新定义；目的地待裁（推荐 B-1） |
| 中-13 | **登记（板级前置）** | 对端双口同子网路由/ARP 配方（显式 `/32` + `-I` + `arp_ignore`）写入 §10.4 前置 |
| 中-14 | **采纳** | S-7 温度/功耗 = 未测（无 XADC/sysmon） |
| 中-15 | **登记（P3）** | “每口最多 8”是 app 约定，不是硬件性质；不做独立池 ⇒ 不保证 |
| 中-16 | **采纳** | 好帧 = `tlast && tcrs && !terr`；W81 只数 `!tcrs`；`terr` 帧不计好帧（§2.3） |
| 中-17 | **登记（P3）** | 镜像“满即丢整帧”需帧首空间准入 + 中途 abort 到 TLAST + 丢弃计数 |
| 中-18 | **采纳（文档）** | TL 注“0x2A 待烧录”已过时 ⇒ 按台账 §10-117 已烧（本文件头） |
| 中-19 | **采纳** | `SNAP_STATUS[7]` 读侧工具同步（`p6b_accept.sh`/`p7b_snap.sh` 的 0x1C 解析）列入读侧阶段 0x2B；自检加“bit 7 可置 1”的构造性负对照 |
| 中-20 | **登记（文档）** | plan §7 指针化；本轮不修 plan 目录（只读） |

### 11.3 低（10）

| # | 处置 |
|---|---|
| 低-1~低-8 | **登记（文档勘误）**：plan/历史件的行号/哈希/引用范围错误，不在本文件施工面重复；引用一律现读 |
| 低-9 | **登记**：P1 只建甲（0x2B）与用户“两个 bitfile”字面差 ⇒ 乙留 P3（U-6 观测全量已裁，位流暂缓未裁；本轮按“只建甲”执行并登记） |
| 低-10 | **登记**：P1 §6.4 实际 14 行待裁，不是 9 条 |

---

## 12. 改动文件清单（本轮实施）

| # | 文件 | 改动 |
|---|---|---|
| 1 | `board/wrapper_p4.v` | ch0 RX MAC/tap/sink；ch0 PCS 状态/事件；LOS；模式宏/硬门；W76..W82；`SNAP_NW_P6E 83` / `SNAP_P7BDP_NW 39` / `SNAP_CH0_NW 4`；超时 + `SNAP_STATUS[7]`；`BUILD_ID_V 0x2B`；四宏线网安全 |
| 2 | `_proj_pcie/rtl/axi_regs.v` | `ch0_snap_to` 输入 + 逐代锁存；`SNAP_STATUS[7]` |
| 3 | `board/p7b_pcs_stub.v` | sim-only：`rx_clk_0`/`rx_clk_1` 拆分；ch0/ch1 status 拆分（默认 ch0 也 link-up） |
| 4 | `_proj_10g/p7b_chain/sim/tb_p7b_chain.v` | 几何 83/`0x17C`；W76..W82 force；ch0 注入臂；LOS 臂；超时臂；force/W39 同步；`snap_take` 硬断言 |
| 5 | `_proj_10g/p7b_chain/sim/tb_p1_ch0_unit.v` + `run_tb_p1_ch0_unit.bat` | 新单元门（§10.2 G4） |
| 6 | `_proj_10g/p7b_chain/sim/run_tb_p7b_chain.bat` | +`TCP_TX_OVL`、+`-L xpm`、P4_WORKDIR/p4env |
| 7 | `sim/p4gates/p7bchain_src.f` + `run_matrix_p4dfix.bat` | 第 20 门注册 |
| 8 | `sim/p7b_stagec_tx/run_tx_ovl_gate.bat` | 修复 CRLF/锚点（或登记替代门） |
| 9 | `sim/p6e_pcie/tb_p6e_pcie_wrapper.v` / `tb_p6e_pcie_counters.v` | 几何/MIR/UNIMPL/BID 同步 |
| 10 | `_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py` + 20 文件 | 阶段 0x2B |
| 11 | `_proj_10g/notes/P7B_BIZ_WINDOW.md` | W76..W82 / 83 字 / UNIMPL `0x17C` |

---

## 13. 未测/纸面/未判定（不许当已答）

1. 资源/时序增量 = **纸面**（除 `mac_rx_10g` OOC 值）；WNS 预测不可给。
2. `rx_clk_out_0` 停钟行为 = **未判定**（历史 `rx0_free=0` 只作支持）；超时机制按“可能停钟”设计。
3. P1 板级读数 = **未测**；§10.4 是草案，不是裁定。
4. BER 无直接读数；W76/W77/W81 只是代理；正式 BER 需 PRBS/长时统计（P7a 配方）。
5. 甲模式 HLS 双 IP = **未实施/未测**（P2）。
6. 乙模式转发通路 = **未实施**（P3）。
7. `snap_cdc` 新束的时钟组覆盖 = **推断**；构建轮 `report_clock_interaction` + `12-4739` 复核。
8. 对端双口同子网路由/ARP 配置 = **未定**（板级前置）。
9. W77 的 `vcc` 自由计数 = 编译期选择，板级读法只作活动指示；不承诺可还原绝对值。
10. 观测最小集（§4.7）= **建议**，拆除动作待功能测试完成后由用户裁。

---

## 14. 实施结果回填（2026-10-18，本轮门读数；详表见 `gates/` 与回传报告）

| 门 | 读数 |
|---|---|
| G1-a 基线（未改 RTL，chain 门加 `TCP_TX_OVL`+xpm） | **106 checks / 0 fail / PASS**（01:21） |
| G1 全链（P1，142 checks） | **0 fail / VERDICT = PASS** |
| G4 单元门 `tb_p1_ch0_unit` | **29 checks / 0 fail / UNIT VERDICT = PASS** |
| G2 p6e（非 P7B 几何/身份） | `PASS_ALL`（83 字 / `0x17C` / BID 0x2B / W76..W82 读 0） |
| G5 四宏 elaboration | `ELAB_4COMBO_PASS`（4/4） |
| G3 矩阵（第 20 门 = p7b_chain） | **20/20 EXIT=0 / gates failed 0 / FROZEN（296 文件逐字节相同）/ RC=0**（01:42:37–02:11:30） |
| 读侧 0x2B | apply 65 处/17 文件 0 fail；assert 0 fail；rehearse 剩余 0 阶段全绿；负控 table/bid/tier/face 4/4 有牙 |
| `run_tx_ovl_gate.bat` | 未修（8 锚点漂移）；替代门 = chain 门编 `TCP_TX_OVL` |

- ⛔ 未跑构建/板级；`REPORT.md` 的平台落盘被拒（已知间歇问题），完整报告以 **agent 回传文本** 交 TL 代落盘。

---

*本文件 = P1 施工权威（纯设计 + 本轮实施记录）。不含 PASS/FAIL 裁定；所有“达标/不达标”留待用户与后续实测。*
