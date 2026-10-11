# P8 · XDMA 4.2 切 AXI4-Stream 的 **EDA 确认**（scratch 轮 · 2026-10-11）

**任务**：在**不动仓库任何源文件**的前提下，用一轮 Vivado **scratch** 实验，把"XDMA 4.2 切成 AXI4-Stream 后
**真实的** `CONFIG.*` 与**端口表**"钉死；并核驱动侧事实。产出 = 实现轮可直接照抄的**权威端口表 + 配置增量清单**。

**边界声明**：本件**未改任何仓库源文件**（唯一新增 = 本件 + 本目录）；scratch 工程建在
`_proj_10g/notes/p8_axis_conf_20261011/work/`，**只 `create_ip` + `set_property` + `generate_target all`**
（**未 synth / 未 impl / 未烧板**），跑完即删工程目录（保留全部产物与日志，可由脚本 1:1 复跑）。
对端（192.168.0.38）**只读**，零写入。**不下 PASS/FAIL 裁定**；不写"时序已解决"。

**三分类**：【事实】（有出处，带文件:行号 或原文）·【推断】（从事实推、未证）·【需要验证】（给命令）。

**权威口径**：EDA 侧一切读数来自**引擎自己生成的产物**（`xdma_st.veo` / `synth/xdma_st.sv` / 生成的 `.xci`），
不是我对文档的转述；PG195 口径来自**本机文档**（见 §8 出处）。

---

## §0 一句话结论（八条）

1. **【事实】配置增量 = 恰好 1 行**：`CONFIG.xdma_axi_intf_mm {AXI_Stream}`。全量 **1001 项 `CONFIG.*`**
   逐项对照，MM 臂与 ST 臂**只差 2 处**（`Component_Name` 与这一行）；**BAR / AXI-Lite / 链路 / 时钟参数一字未变**。
2. **【事实】端口表：75 → 50 根**。消失 **35 根 `m_axi_*`**（不是侦察件写的"~60 根"）；新增 **10 根 AXIS**；
   保留 **40 根**（含 `m_axil_*` **19** 根 + `cfg_mgmt_*` 7 根 + PCIe/时钟/中断 **14** 根）。
3. **【事实】128 位 + 250 MHz 在 ST 下合法且已生成**：`AXI_DATA_WIDTH=128` / `USER_CLK_FREQ=2` /
   `axisten_freq=250` ⇒ 与现役 MM 完全相同（**保持 128 位 = 不引入新时钟域**，用户既定决策成立）。
   ⚠️ **但 `set_property` 有顺序陷阱**（见 §2.3）——写错顺序会**报错回滚**，且**回滚后仍能生成位流**。
4. **【事实】AXIS 侧没有 `tuser` 端口**。本配置（`parity_settings=None`，无 Propagate Parity）下不生成 tuser
   ⇒ 侦察件 §3.1-b 表里的 `tuser_0[15:0]` **不存在**（PG195 Table 15/16 也把它标为"only in Propagate Parity mode"）。
5. **【事实】`axi_aclk` 约束逐字不变**：生成的 OOC XDC 两臂都只有
   `create_clock -period 4 [get_ports axi_aclk]`（= 250 MHz）。
6. **【事实】驱动不用换**：MM/ST 判定 = 驱动在 probe 时读**引擎 identifier 寄存器 bit15**（运行期，非编译期）；
   当前板上那颗被驱动命名为 **`0-C2H0-MM`**（dmesg 原文）。已加载驱动 = **out-of-tree v2025.2.0**（srcversion 判死）。
7. **【事实】"16 B 对齐"是**我们的从机**造的**：PG195 Table 11（p.27）给 AXI4-Stream 的地址限制 = **None**；
   驱动的对齐检查只看 `addr_align`（= 引擎 alignments 寄存器的运行期读数）+ `buf_lsb` vs `pos_lsb`；
   **ST C2H 下 `f_pos` 写进描述符后立刻被回写结果缓冲地址覆盖** ⇒ 不再当地址用。
8. **【事实】单次 `read()` 无 64 KB 级硬顶**：用户缓冲按页切成 sw_desc，每 **2048** 个描述符构成 1 个 transfer，
   `while (nents)` + `tfer[2]` 链式续跑（源码原文）；ST C2H 的内部回写缓冲 = 2048 × 32 B = **64 KB**。

---

## §1 基线与可复跑命令

### 1.1 【事实】现役 XDMA 的全部 `CONFIG.*`（逐字抄自 `board/build_p7b_ku5p.tcl:119-132`）

```tcl
CONFIG.pcie_blk_locn              {X0Y0}
CONFIG.pf0_device_id              {9034}
CONFIG.pf0_subsystem_id           {0007}
CONFIG.ref_clk_freq               {100_MHz}
CONFIG.mode_selection             {Basic}
CONFIG.axi_data_width             {128_bit}
CONFIG.num_queues                 {1}
CONFIG.axilite_master_en          {true}
CONFIG.axilite_master_scale       {Megabytes}
CONFIG.axilite_master_size        {1}
CONFIG.pl_link_cap_max_link_speed {8.0_GT/s}
CONFIG.pl_link_cap_max_link_width {X4}
```
（**12 项**，与磁盘上 `.xci` 的 `value_src=user` 条目数**逐条相等** ⇒ tcl 确是唯一源。见 §8 `cfg_mm_defaults.txt`。）

### 1.2 【事实】可复跑命令（本轮原样跑的）

```bat
:: work\run_mk_axis_ip.bat   /   work\run_mk_axis_ip2.bat   (= 实验 1 / 实验 2)
call "C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat" -mode batch -source "...\work\mk_axis_ip.tcl" -nojournal -nolog
```
- 实验 1（`mk_axis_ip.tcl`）：同工程两臂 `xdma_mm`（基线 12 项）/ `xdma_st`（12 项 + intf 覆写），
  **不动点回读循环**（照抄 `build_p7b_ku5p.tcl:60-72` 的 pcs64 范式）→ `generate_target all` → 全量 `CONFIG.*` 落盘 + 端口表。
- 实验 2（`mk_axis_ip2.tcl`）：**四臂 A/B/C/D** 定位"顺序敏感性"与"静默回滚"（§2.3）。
- 全程 stdout：`work/vivado_stdout.txt`（实验 1）/ `work/vivado_stdout2.txt`（实验 2）。
- ⚠️ `.bat` 必须 **ASCII + CRLF**（本轮第一次用 `printf` 生成把 `\r`/`\n` 当转义、bat 被写坏 ⇒ 报"系统找不到指定的路径"；
  改用 Write + `sed -i 's/$/\r/'` 后正常）。

### 1.3 【事实】实验产物（判据所引的原文）

| 文件 | 内容 |
|---|---|
| `work/evidence/xdma_st.veo` · `xdma_mm.veo` | Vivado 生成的**例化模板**（端口名 + 方向 + 位宽） |
| `work/evidence/xdma_st.sv` · `xdma_mm.sv` | **OOC 综合顶层 wrapper**（端口声明 + `CORE_GENERATION_INFO` 全参数展开） |
| `work/evidence/xdma_st.xci` · `xdma_mm.xci` | 生成态的 IP 配置（`component_parameters` + `model_parameters` 两节） |
| `work/evidence/xdma_st_ooc.xdc` | 时钟约束（§4.1） |
| `work/evidence/xdma_b.sv` · `xdma_d.sv` · `xdma_d.veo` | 实验 2 的 B / D 臂（D = 踩坑臂） |
| `work/cfg_*.txt` · `work/cfg2_*.txt` | 14 份**全量 `CONFIG.*` 转储**（各 1001 项） |
| `work/peer_driver_evidence.txt` | 驱动侧逐条命令 + stdout 原文 |
| 本地 PG195 v4.1 原件 = `C:\Users\zhxue\Documents\XilinxDocs\IP\4.1_English\pg195-pcie-dma.pdf`（本件按**页码**引用；⛔ 全文提取件**不入库**=版权，见 `.gitignore`） |
| `work/SHA256SUMS.txt` | 上述全部件的 sha256 |

---

## §2 配置增量清单（**我设的 vs 实际生效的**，逐条）

### 2.1 【事实】逐条对照（实验 1 · ST 臂）

| # | 我设的 | 实际生效（`get_property` 回读） | 一致？ | 生成产物里的展开 |
|---|---|---|---|---|
| 1 | `CONFIG.xdma_axi_intf_mm {AXI_Stream}` | `AXI_Stream` | ✅ | `XDMA_AXI_INTF_MM=0` / `DMA_MM=0` / `DMA_ST=1` |
| 2 | `pcie_blk_locn {X0Y0}` | `X0Y0` | ✅ | `PCIE_BLK_LOCN=0` |
| 3 | `pf0_device_id {9034}` | `9034` | ✅ | `PF0_DEVICE_ID=0x9034` |
| 4 | `pf0_subsystem_id {0007}` | `0007` | ✅ | `PF0_SUBSYSTEM_ID=0x0007` |
| 5 | `ref_clk_freq {100_MHz}` | `100_MHz` | ✅ | `REF_CLK_FREQ=0` |
| 6 | `mode_selection {Basic}` | `Basic` | ✅ | `FUNC_MODE=1` / `PF1_ENABLED=0` |
| 7 | **`axi_data_width {128_bit}`** | **`128_bit`** | ✅（⚠️ 见 §2.3） | **`AXI_DATA_WIDTH=128`** |
| 8 | `num_queues {1}` | `1` | ✅ | `MULTQ_EN=0` |
| 9 | `axilite_master_en {true}` | `true` | ✅ | **`XDMA_AXILITE_MASTER=TRUE`** |
| 10 | `axilite_master_scale {Megabytes}` | `Megabytes` | ✅ | `AXILITE_MASTER_APERTURE_SIZE=0x0D` |
| 11 | `axilite_master_size {1}` | `1` | ✅ | 同上（1 MB 孔径） |
| 12 | `pl_link_cap_max_link_speed {8.0_GT/s}` | `8.0_GT/s` | ✅ | `PL_LINK_CAP_MAX_LINK_SPEED=4` |
| 13 | `pl_link_cap_max_link_width {X4}` | `X4` | ✅ | `PL_LINK_CAP_MAX_LINK_WIDTH=4` |
| — | （未设，走默认） | `axisten_freq = 250` | — | **`USER_CLK_FREQ=2`**（= 250 MHz） |

**全量对照（决定性）**：`diff cfg_mm_post_gen.txt cfg_st_post_gen.txt` ⇒ **只有 2 行不同**
（`Component_Name` 与 `xdma_axi_intf_mm`）；**1001 行 `CONFIG.*` 其余逐字相同**（`sha256` 亦见 §8）——
**包括** `pf0_bar0_scale/size`、`pf0_bar1_*`、`axilite_*`、`dsc_bypass_*`、`parity_settings`、`plltype`。

### 2.2 【事实】BAR / AXI-Lite 相关项（用户最关心的"会不会被改掉"）

| 参数（生成后回读） | MM 臂 | ST 臂 |
|---|---|---|
| `PF0_BAR0_APERTURE_SIZE` / `CONTROL` | `0x0A` / `0x4` | 同左 |
| `PF0_BAR1_APERTURE_SIZE` / `CONTROL` | `0x05` / `0x0` | 同左 |
| `PCIEBAR_NUM` / `C_INCLUDE_BAROFFSET_REG` | `6` / `1` | 同左 |
| `XDMA_APERTURE_SIZE` / `CONTROL`（配置 BAR） | `0x09` / `0x4` | 同左 |
| `AXILITE_MASTER_APERTURE_SIZE` / `CONTROL` | `0x0D` / `0x4` | 同左 |
| `XDMA_AXILITE_MASTER` | `TRUE` | **`TRUE`**（`M_AXI_LITE` 与接口模式无关，侦察件 §0-4 成立） |
| `DSC_BYPASS_RD/WR`、`XDMA_DSC_BYPASS` | `0/0`、`FALSE` | 同左（⇒ 无用 tuser 的场景） |

### 2.3 ⚠️【事实】**顺序陷阱 + 静默回滚**（实验 2 四臂 · 本件最重要的一条）

实验 1 的 ST 臂出现了**看似矛盾**的一幕：日志里报
```
ERROR: [IP_Flow 19-3461] Value '128_bit' is out of the range for parameter
       'AXI Data width(axi_data_width)' for IP 'xdma_st'. Valid values are - 64_bit
INFO:  [IP_Flow 19-3438] Customization errors found on 'xdma_st'. Restoring to previous valid configuration.
```
**而同一臂的回读比对 MISMATCH_N = 0、生成的核 AXI_DATA_WIDTH=128**。实验 2 四臂把它钉死：

| 臂 | 写法 | 报错？ | 最终生效（`get_property`） | 生成产物 |
|---|---|---|---|---|
| **A** | 一次 `-dict` 设 13 项，且 **link speed/width 排在 `axi_data_width` 之前** | **无** | 128_bit / 250 / AXI_Stream / 8.0GT/s / X4 | `AXI_DATA_WIDTH=128 USER_CLK_FREQ=2` |
| **B** | **先设 12 项基线**（含 link），**再单独设 intf 一行** | **无** | 同上 | 同上（**= 与 A 逐字相同的参数集**） |
| **C** | 先设 intf，再设 12 项基线（`axi_data_width` 在 link 参数**之前**） | **无**（本轮） | 同上 | 同上 |
| **D** | 一次 `-dict`，link 参数在前，但把 `axi_data_width` 改成 **`64_bit`** | **有** | ⛔ **`64_bit` / 2.5 GT/s / X1 / CPLL / `AXILITE_MASTER=FALSE`** | **`generate_target` 仍 RC=0**，生成 `AXI_DATA_WIDTH=64 USER_CLK_FREQ=0` 的核 |

**机制（【推断】，有两条硬证据支撑）**：
- 参数合法性是**边设边算**的：`update_PARAM_VALUE.axi_data_width` 的合法集只依赖
  **link speed / link width / 器件 / 速度等级**（`xdma_v4_2.tcl:9549-9600` 现读：8.0 GT/s × X4 ⇒ `128_bit,256_bit`；
  默认态 2.5 GT/s × X1 ⇒ **只有 `64_bit`**）。**D 臂的报错原文 `Valid values are - 128_bit, 256_bit` 反证
  "link 参数已先落地"** ⇒ `-dict` **按列表顺序逐条应用**。
- 回滚 = 回到"**上一个合法状态**"，该状态**能继续 `generate_target` 且不报错**（D 臂 RC=0）。
  D 臂的终态（64_bit / 2.5GT/s / X1 / `AXILITE_MASTER=FALSE`）**在板上完全不可用**，且**回读比对也会通过**
  （因为比对的是"我设的值 vs 读回的值"，回滚把两者一起改了）。

**实验 1 那一幕的复现条件（照抄给复核者）**：实验 1 的 ST 臂用的是 `foreach {k v} $DESIRED { catch {set_property …} }`
（**逐条设 + 逐条吞异常**），且 `axi_data_width` 排在两个 link 参数**之前** ⇒ 宽度那一条在 link 参数还没落地时被拒
（此时合法集 = 默认态的 `{64_bit}`，与报错原文逐字一致），随后 link 参数落地。**终态仍读出 `128_bit` 且生成物 `AXI_DATA_WIDTH=128`**
（【推断】= 合法集变化时把越界值重置为该档默认值，而 8.0 GT/s × X4 的默认宽度恰是 `128_bit`；**未做实验证此机制**）。
⛔ 但**这条路径依赖"默认值恰好 = 我想要的"** —— 若目标值是 `256_bit`（该档另一个合法值），同一路径会**静默落回 128**。**不要用这条路径。**

**给实现轮的硬结论**：
1. 写法**用 B 臂**（12 项照抄 + 之后**单独一行** `set_property CONFIG.xdma_axi_intf_mm {AXI_Stream}`）或 **A 臂**
   （一次 `-dict` 且 **link speed/width 必须排在 `axi_data_width` 之前**）。两者产物**参数集逐字相同**。
2. ⛔ **回读比对不足以发现回滚** —— 必须**同时**把构建日志当判据：
   `IP_Flow 19-3461` / `IP_Flow 19-3438` / `Common 17-39` **出现即硬失败**。
3. ⛔ **不许把 `axi_data_width` 设成 `64_bit`**（在 8.0 GT/s × X4 下非法；想要 64 位必须同时改 link 参数 ⇒ 另一套枚举）。
4. 侦察件 §8-① 给的 scratch 片段**原样跑会踩到这条**（它把 `axi_data_width` 写在 link 参数之前）——
   本轮实验 1 的 ST 臂即复现该现象。

---

## §3 权威端口表（生成产物逐字抄出）

**来源**：`work/evidence/xdma_st.sv` 的 `module xdma_st (...)` 端口清单 + 声明（`input/output` 与位宽）。
**计数**：`module` 端口名 50 个，声明 50 条，**无一条漏声明**（脚本逐条核过）。

### 3.1 【事实】ST 臂全部 50 根端口

**A. 新增（AXIS 侧，10 根）** —— 位宽按 `AXI_DATA_WIDTH=128`：

| 端口 | 方向 | 位宽 | 说明 |
|---|---|---|---|
| `s_axis_c2h_tdata_0` | **input** | `[127:0]` | C2H（板→宿主）数据 |
| `s_axis_c2h_tkeep_0` | **input** | `[15:0]` | = `AXI_DATA_WIDTH/8` |
| `s_axis_c2h_tlast_0` | **input** | 1 | 包尾 |
| `s_axis_c2h_tvalid_0` | **input** | 1 | |
| `s_axis_c2h_tready_0` | **output** | 1 | **IP 输出**（唯一的板内流控输入） |
| `m_axis_h2c_tdata_0` | **output** | `[127:0]` | H2C（宿主→板）数据 |
| `m_axis_h2c_tkeep_0` | **output** | `[15:0]` | |
| `m_axis_h2c_tlast_0` | **output** | 1 | |
| `m_axis_h2c_tvalid_0` | **output** | 1 | |
| `m_axis_h2c_tready_0` | **input** | 1 | 由我们驱动（恒 1 = 吞噬） |

⛔ **没有 `tuser`**（0 根）。PG195 Table 15/16（p.30/31）逐字：`m_axis_h2c_tuser_x` / C2H 侧同款
"Parity bits. This port is enabled only in **Propagate Parity mode**"；本配置 `parity_settings = None` ⇒ 不生成。

**B. 保留（40 根，逐根照抄）**：

| 类 | 端口（方向 / 位宽） |
|---|---|
| 时钟复位 | `sys_clk`(i) · `sys_clk_gt`(i) · `sys_rst_n`(i) · `axi_aclk`(**o**) · `axi_aresetn`(**o**) |
| 链路 | `user_lnk_up`(o) · `pci_exp_txp/txn`(**o**[3:0]) · `pci_exp_rxp/rxn`(i[3:0]) |
| 中断 | `usr_irq_req`(i[0:0]) · `usr_irq_ack`(o[0:0]) · `msi_enable`(o) · `msi_vector_width`(o[2:0]) |
| AXI-Lite 主（→ `axi_regs`） | `m_axil_awaddr`(o[31:0]) · `awprot`(o[2:0]) · `awvalid`(o) · `awready`(i) · `wdata`(o[31:0]) · `wstrb`(o[3:0]) · `wvalid`(o) · `wready`(i) · `bvalid`(i) · `bresp`(i[1:0]) · `bready`(o) · `araddr`(o[31:0]) · `arprot`(o[2:0]) · `arvalid`(o) · `arready`(i) · `rdata`(i[31:0]) · `rresp`(i[1:0]) · `rvalid`(i) · `rready`(o) |
| 配置管理（未实现） | `cfg_mgmt_addr`(i[18:0]) · `write`(i) · `write_data`(i[31:0]) · `byte_enable`(i[3:0]) · `read`(i) · `read_data`(o[31:0]) · `read_write_done`(o) |

**C. 消失（35 根，全部 `m_axi_*`）**：
`awid`(o[3:0]) · `awaddr`(o[63:0]) · `awlen`(o[7:0]) · `awsize`(o[2:0]) · `awburst`(o[1:0]) · `awprot`(o[2:0]) ·
`awvalid`(o) · `awlock`(o) · `awcache`(o[3:0]) · `awready`(i) · `wdata`(o[127:0]) · `wstrb`(o[15:0]) · `wlast`(o) ·
`wvalid`(o) · `wready`(i) · `bid`(i[3:0]) · `bresp`(i[1:0]) · `bvalid`(i) · `bready`(o) · `arid`(o[3:0]) ·
`araddr`(o[63:0]) · `arlen`(o[7:0]) · `arsize`(o[2:0]) · `arburst`(o[1:0]) · `arprot`(o[2:0]) · `arvalid`(o) ·
`arlock`(o) · `arcache`(o[3:0]) · `arready`(i) · `rid`(i[3:0]) · `rdata`(i[127:0]) · `rresp`(i[1:0]) · `rlast`(i) ·
`rvalid`(i) · `rready`(o)。
⇒ ⛔ **侦察件 §3.1-b 的"~60 根"是错的**（实为 **35 根**；MM 臂总共才 75 根）。

### 3.2 【事实】两臂端口计数

| 臂 | 端口总数 | `m_axi_*` | AXIS | `m_axil_*` | `cfg_mgmt_*` | 其它 |
|---|---|---|---|---|---|---|
| MM（现役） | **75** | 35 | 0 | **19** | 7 | **14** |
| ST（目标） | **50** | 0 | **10** | **19** | 7 | **14** |

（脚本按前缀逐根统计，非人工数；"其它 14" = 时钟复位 5 + 链路 5 + 中断 4，逐根见 §3.1-B。）

### 3.3 【事实】`cfg_mgmt_*` / `m_axil_*` **都保留**（不是"消失"）

侦察件 §3.1-b 表把 `cfg_mgmt_*` 与 `m_axil_*` 列在"不变"列 —— **正确**（本件逐根复算确认）。

---

## §4 硬约束：频率 / 缓冲 / tlast / tkeep

### 4.1 【事实】时钟：**不被本次改动触碰**

- 生成的 **OOC XDC 两臂逐字相同**（`work/evidence/xdma_st_ooc.xdc`，MM 臂同款）：
  ```tcl
  create_clock  -period 10 [get_ports sys_clk]
  create_clock  -period 10 [get_ports sys_clk_gt]
  create_clock -period 4 [get_ports axi_aclk]      # = 250 MHz
  ```
- 生成产物：`USER_CLK_FREQ=2`（= 250 MHz）、`axisten_freq=250`、`CORE_CLK_FREQ=1`、`PLL_TYPE=2`。
- **规则出处**（`xdma_v4_2.tcl` 现读）：`axisten_freq` 合法集只依赖 link speed/width/width/器件
  （`:8765-8870`）—— **8.0 GT/s × X4**：`128_bit ⇒ {250 MHz}`（唯一）、`256_bit ⇒ {125 MHz}`；
  `USER_CLK_FREQ`（`:13146-13180`）是 `axisten_freq + axi_data_width` 的纯函数（250 MHz & 非 512 位 ⇒ 2）。
  ⇒ **与接口模式（MM/ST）无关** ⇒ **"保持 128 位 ⇒ 保持 250 MHz、零新增时钟域"成立**。
- PG195 v4.1 p.85 逐字："AXI Clock Frequency: Select 62.5 MHz, 125 MHz or 250 MHz depending on the lane width/speed."
  p.84："AXI Data Width: Select 64, 128, 256-bit, or 512-bit (only for UltraScale+)."
  ⇒ 文档层面 128 位 ST 合法；Table 11（p.27）把 AXI4-Stream 的 datapath width 记为 "64, 128, 256, 512"。

### 4.2 【事实】"缓冲/深度"面：**没有 `*_BUF_*` 用户参数**；真正的缓冲在别处

- 全量 1001 项 `CONFIG.*` 里**不存在**名字含 `buf/depth/fifo` 的用户参数（逐项 grep 过）。
  与"缓冲"沾边的只有：`dsc_bypass_*`（描述符旁路，本配置 0）、`axist_bypass_*`（旁路 BAR，`false`）、
  `tl_credits_cd/ch = 15`（PCIe TL 信用，与数据面缓冲无关）、`C_M_AXI_NUM_READ/WRITE/READQ = 8/8/2`
  （**MM 侧**引擎未完成事务深度；ST 下这几项**仍在**但语义不再是"板上数据缓冲"）。
- 【事实·EDA】ST 核内部数据通路是 **512 位**（生成的接口头 `dma_pcie_c2h_crdt_if.svh` 里
  `tdata[511:0]`/`tkeep[64]`/`tusr[127:0]`），**外部用户口** = 按 `AXI_DATA_WIDTH`（本配置 128）。
- 【事实·驱动】真正的"缓冲"是**描述符环 + 驱动侧回写数组**：`desc_max = 2048`（credit 关时）/ `1023`（credit 开时）；
  `cyclic_result` 回写缓冲 = `desc_max × sizeof(struct xdma_result=32 B)` = **64 KB**（§5）。
- ⇒ 侦察件 §4.2 的"板内可用容忍空档只有 2 KB"指的是**我们自己的** `app_rx_mirror` FIFO，与 IP 无关；
  **IP 侧背压的语义**见 4.3-④。

### 4.3 【事实】`tlast` / `tkeep` / `tuser` / 描述符 的硬约束（PG195 v4.1，本机文档）

PG195 v4.1 原文（本地 PDF：`C:\Users\zhxue\Documents\XilinxDocs\IP\4.1_English\pg195-pcie-dma.pdf`，按页码引）：

| # | 约束 | 原文（摘） | 页 |
|---|---|---|---|
| ① | **C2H `tkeep` 非末拍必须全 1** | "The tkeep bits must be all 1s except for the last data transfer of a packet. On the last transfer of a packet, when tlast is asserted, you can specify a tkeep that is not all 1s… The asserted tkeep bits need to be **packed to the lsb**… **If tlast is asserted and tkeep has all zero's, this is not a valid combination**" | p.27 |
| ② | **C2H 描述符长度必须是 64 B 的整数倍** | "The length of a C2H Stream descriptor (the size of the destination buffer) **must always be a multiple of 64 bytes**." | p.27 |
| ③ | **一个包可跨多个描述符；描述符被填满 或 因 EOP 关闭都要回写** | "Packets can span multiple descriptors. The C2H channel accepts data when it is enabled, and **has valid descriptors**. As data is received, it fills descriptors in order. When a descriptor is **filled completely** or closed due to an **end of packet** on the interface, the C2H channel writes back…(WB Magic `16'h52b4`, Status[0] = EOP)" | p.26–27 |
| ④ | **`tready` 的因果（文末口径）** | "The C2H channel accepts data when it is enabled, and **has valid descriptors**" + credit 模式寄存器（`c2h_dsc_credit_enable`，写信用才继续取描述符） | p.26 / p.73 |
| ⑤ | **流内必须连续** | "For valid data cycles on the C2H AXI4-Stream interface, **all data associated with a given packet must be contiguous**." | p.26 |
| ⑥ | **H2C 侧（引擎打 tlast）** | "A descriptor with an **EOP bit** asserts tlast on the AXI4-Stream user interface on the last beat of data"；`m_axis_h2c_tkeep_x` = "specifies how many bytes are valid **when tlast is asserted**" | p.26 / p.30 |
| ⑦ | **地址对齐** | Table 11：`AXI4-Stream` ⇒ Address Restriction = **None**（对 64/128/256/512 位）；只有 `AXI4 MM fixed address` 才有 `addr[3:0]==0` 类要求 | p.27 |
| ⑧ | **`tuser` 只在 Parity 模式** | Table 15/16：`*_tuser_x` "Parity bits. This port is enabled only in Propagate Parity mode." | p.30/31 |
| ⑨ | **引擎 identifier 的 Stream 位** | Table 41/60：bit15 = "Stream"（1 = AXI4-Stream Interface，0 = AXI Memory Mapped） | p.44 / p.52 |

⚠️ **版本告警**：本机文档 = **PG195 v4.1**；实验用 IP = **xdma 4.2**（VLNV 逐字 `xilinx.com:ip:xdma:4.2`，Revision 2）。
上面 ①②③⑥⑨ 在 4.2 里**未被本轮证伪**（生成产物与 4.1 一致的端口名/位宽即是旁证），但**页码引用只能按 v4.1 记账**。

### 4.4 【事实】`tlast` 与"宿主 read 完成"的关系（**两侧不是同一件事**）

- 引擎侧：描述符可**被填满而关闭**（不需要 tlast）③ ⇒ **"永不 tlast"在引擎语义上= 一个无限长包**（不是非法）。
- 驱动侧（`libxdma.c`）：**默认**（工具不传 `-e`）读完成 = "**指定字节数收到**"；开了 `eop_flush`
  （工具 `-e` ⇒ `open(O_TRUNC)`）才是"**收到 EOP 或收满**"（§5-C）。
- ⇒ 侦察件 §4.3 的方案 A（tlast 恒 0 + 停流 flush 一拍）**在引擎侧合规、在驱动默认路径上也成立**；
  ⛔ 但"**引擎内部真的不因长期无 tlast 而停摆**"**没有 EDA 可证**，属【需要验证】（§7-④）。

---

## §5 驱动侧三条结论（对端 192.168.0.38，只读；逐条命令与原文见 `work/peer_driver_evidence.txt`）

### A. 【事实】版本与来源：**out-of-tree `dma_ip_drivers-patched`, XDMA v2025.2.0**；已加载 = 它，不是 in-tree

- `RELEASE` 最新条目 = `v2025.2.0`；源码树 = `/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/xdma/`。
- **决定性判据**：`/sys/module/xdma/srcversion` = `E2C680AF6D8BF5E3A2F6ACB` **逐字等于**
  `.../xdma/xdma.ko` 的 `modinfo -F srcversion`。
- ⚠️ 陷阱：`modinfo xdma` 显示的是 `/lib/modules/7.0.0-38-generic/kernel/drivers/dma/xilinx/xdma.ko.zst`（**in-tree 件**）
  ⇒ **按名 modinfo 会给出假线索**；判"到底是哪一个"必须用 srcversion（或 `/dev/xdma0_*` 节点是否存在）。
- 板级旁证：`dmesg` 有 `xdma:probe_one: 0000:02:00.0 xdma0 … usr 16, ch 1,1` + `identify_bars: 2 BARs: config 1, user 0, bypass -1`
  + `map_single_bar: BAR0 … length=1048576 / BAR1 … length=65536`（与板级身份门逐字一致）。

### B. 【事实】ST 支持 = **运行期判定，驱动无需更换**

- 唯一判定点（`libxdma.c:2856-2860`）：
  ```c
  val = read_register(&engine->regs->identifier);
  if (val & 0x8000U) engine->streaming = 1;
  snprintf(engine->name, …, "%d-%s%d-%s", xdev->idx, (dir==DMA_TO_DEVICE)?"H2C":"C2H",
           channel, engine->streaming ? "ST" : "MM");
  ```
- 引擎寄存器基址（`libxdma.c:4345-4352` 注释 + `libxdma.h:190/191/217/219`）：
  **H2C ch0 @0x0000（id 期望 `0x1fc0`）/ C2H ch0 @0x1000（id 期望 `0x1fc1`）**，通道间距 `0x100`；
  `identifier` 结构偏移 `0x00`，`alignments` 偏移 **`0x4C`**。
- 板级旁证：`dmesg` 现打 **`0-C2H0-MM`** ⇒ 当前（MM 位流）被驱动判为 MM；换 ST 位流后应打 **`0-C2H0-ST`**（§7-②）。
- 影响面（逐条）：`engine->desc_max` 2048 ↔ 1023（仅 credit 开启时）；C2H ST 额外分配 `cyclic_result` 回写数组
  （`libxdma.c:2817-2825`）；`char_sgdma_open` 才允许一个读者（`device_open`，`-EBUSY` 第二个）；
  C2H ST 下 `transfer_build` 覆写描述符 `src_addr` = 回写缓冲（`libxdma.c:2948-2957`）。
  ⇒ **驱动侧没有任何"按 IP 接口模式分叉的编译期开关"** ⇒ 侦察件的【推断】升级为【事实】。

### C. 【事实】ST 下 `read()` 语义（f_pos / 对齐 / 完成条件 / 上限）

| 问 | 答（源码逐字） |
|---|---|
| **`f_pos` 还当地址吗？** | **不**。ST C2H 下 `ep_addr = f_pos` 被写进描述符后被 `cyclic_result` 回写地址**覆盖**（`libxdma.c:2948-2957`）⇒ 它只在 `check_transfer_align` 里当 `pos_lsb` 用。**不需要 `lseek`**（`lseek` 只改 `f_pos`）。⚠️ 补一条：H2C ST 侧驱动仍把 `ep_addr` 写进 `dst_addr`，但 **PG195 p.26 明文"the destination address in the descriptor is unused"** ⇒ 同样不参与寻址。 |
| **还要 16 B 对齐吗？** | 取决于**运行期**的 `engine->addr_align`（= 引擎 `alignments` 寄存器 @0x4C 的 `(w>>16)&0xff`；`w==0` ⇒ 默认 `addr_align=1`、`len_granularity=1`）。默认（`non_incr_addr=0`，无 ioctl 时的唯一状态）：检查 = **`buf_lsb == pos_lsb` (mod addr_align)**。⇒ 若 ST 引擎报 `alignments=0` 或 1 ⇒ **对齐约束消失**；若报 16 且 `f_pos` 非 0 对齐 ⇒ 老约束**以新形式**回来。**PG195 Table 11 说 AXI4-Stream 无地址限制** ⇒ 倾向消失，但**寄存器值是硬件读数，属【需要验证】**（§7-①）。 |
| **宿主缓冲还有什么要求？** | `char_sgdma_map_user_buf_to_sgl`：`get_user_pages_fast` + 逐页 `PAGE_SIZE` 映 SG，构建时**拒绝重复页**（`duplicate pages`）；用户缓冲长度**不必** 64 B 倍数（64 B 倍数那条是**FPGA 侧描述符**的约束，由驱动程序保证——sg 段按页切）。 |
| **完成条件 / 超时** | 默认 = **收满 `count` 字节**；`eop_flush`（工具 `-e` / `open(O_TRUNC)`）= **收到 EOP 或收满**。超时 = `c2h_timeout`（module param，毫秒 ×1000；`libxdma.c:418`）。 |
| **单次 `read()` 上限** | **无 64 KB 级硬顶**：`while (nents) { transfer_init(...); nents -= xfer->desc_num; }` + `struct xdma_request_cb { struct xdma_transfer tfer[2]; /* Use two transfers … */ }`；单 transfer ≤ `engine->desc_max`（2048）个描述符，每描述符 ≤ `min(page, desc_blen_max=2²⁸−1)`。 |
| **内部缓冲** | ST C2H 的 `cyclic_result` 数组 = `desc_max × sizeof(struct xdma_result)` = **2048 × 32 B = 64 KB**（回写 WB Magic `0x52b4` 那套）。 |
| **credit 模式** | `enable_st_c2h_credit` **默认 0**（`libxdma.c:46`，与 RELEASE 的 v2020.2.0 条目一致）；开启才写 `credit_mode_enable_w1s`，并把 `desc_max` 降到 1023。 |
| **工具** | `tools/`: `reg_rw` / `dma_from_device`（`-e/--eop_flush`）/ `dma_to_device` / `performance` / `test_chrdev` —— 均已在位。 |

---

## §6 **与侦察件（`p8_axis_recon_20261011/RECON.md`）不符的地方**（逐条，如实列）

| # | 侦察件原文 | 本轮实测 | 严重度 |
|---|---|---|---|
| 1 | §3.1-b 端口表：新增含 **`tuser_0[15:0]`**（两处，C2H 与 H2C） | **不存在**。本配置无 Parity ⇒ 无 tuser 端口（PG195 Table 15/16 支持） | 中（会让实现轮接一根不存在的线 ⇒ 编译期就红，可发现） |
| 2 | §3.1-b：消失 `m_axi_*` **（~60 根）** | **35 根** | 低（端口表本身没错，只是计数虚高） |
| 3 | §3.2-b / §8-② 的驱动 grep 命令：`…/linux-kernel/{libxdma.c,libxdma.h,cdev_sgdma.c,xdma_mod.h}` | **路径少一层** ⇒ 原样跑 = `No such file or directory`（全臂）。正确路径 = `…/linux-kernel/**xdma/**` | 中（照抄会得到"文件不存在"的空判据） |
| 4 | §2.3-6：「8.0 GT/s × X4 下 `128_bit → 250 MHz`（**唯一**）」 | 讲的是**频率**；**宽度**合法集 = `{128_bit, 256_bit}`（128→250MHz / 256→125MHz）。64_bit 在此档**非法** | 低（结论方向对；但"唯一"若被读成"宽度唯一"会误导） |
| 5 | §4.2：`s_axis_c2h_tready` 由什么决定 = "**外部资料口径**，本机不可回核" | **本机 PG195 p.26 有正面文字**："The C2H channel accepts data when it is enabled, and **has valid descriptors**"；credit 机制另有 `c2h_dsc_credit_enable` 寄存器（p.73） | 低（【推断】可升【事实】） |
| 6 | §4.3 `tuser` 建议"恒 0"（标【需要验证】） | **moot**：端口不存在（同 #1） | 低 |
| 7 | §8-① 给的 scratch Tcl **片段** | **原样跑会报 `IP_Flow 19-3461` 并触发"Restoring to previous valid configuration"**（`axi_data_width` 写在 link 参数之前）⇒ 必须按 §2.3 的顺序/两步写 | **高**（这条不改，实现轮的构建会在**静默回滚**后继续跑） |
| 8 | §1.2「其余 12 项**无需改**」 | ✅ 成立，**但顺序敏感**（见 #7） | — |
| 9 | §2.1 的 `.xci` 现读（`DMA_MM=1 / DMA_ST=0 / XDMA_AXI_INTF_MM=1`）、§0-1「IP 里没有 AXIS 端口」 | ✅ 逐条复核成立（`cfg_mm_post_gen.txt` / `xdma_mm.xci`） | — |
| 10 | §3.2（b）「驱动不需要换」=【推断】 | **升【事实】**（§5-B） | — |
| 11 | §0-4「`axi_regs`（user BAR）不受影响」 | ✅ 成立：`m_axil_*` 20 根逐字保留 + `XDMA_AXILITE_MASTER=TRUE` 两臂相同 | — |
| 12 | §5.1「面积：净额预计小幅减少」 | **未测**（本轮不 synth）⇒ 保持【推断】 | 低 |
| 13 | §2.3-5「`USER_CLK_FREQ` 是 `axisten_freq` + `axi_data_width` 的纯函数」 | ✅ 逐字成立（`xdma_v4_2.tcl:13146`）；补一条：**`axisten_freq` 的合法集也与接口模式无关** | — |

---

## §7 **未定 / 需要板级验证**（逐条给命令）

> 全部命令都在**换上新 ST 位流之后**跑。⚠️ **本轮未动板**：板子"现态 = 0x21 位流 + 受控停流"这句
> **引自侦察件**（`RECON.md` §6），**不是本轮的读数**（本轮对板零操作）。

**① ST 引擎的 `identifier` bit15 与 `alignments` 寄存器**（决定 §5-C 的对齐结论）
```bash
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
$T/reg_rw /dev/xdma0_control 0x0000 r    # H2C ch0 identifier
$T/reg_rw /dev/xdma0_control 0x1000 r    # C2H ch0 identifier
$T/reg_rw /dev/xdma0_control 0x004C r    # H2C ch0 alignments
$T/reg_rw /dev/xdma0_control 0x104C r    # C2H ch0 alignments
```
**期望**：两个 identifier 的 **bit15 = 1**（MM 现态 = `0x1FC00006`@0x0 ⇒ ST 后应成 `0x1FC0_8006` 形态）；
`alignments` 三位域 = `align_bytes[23:16] / granularity[15:8] / address_bits[7:0]`（【未定】值；`0` ⇒ 驱动退化为 1/1/64）。
**对照臂**：同一命令在 0x21（MM）位流上跑一遍 ⇒ MM 的 identifier bit15 应为 0。

**② 驱动是否把引擎认成 ST**
```bash
sudo dmesg | grep -i "xdma" | grep -E "C2H0|H2C0"
```
**期望**：出现 **`0-C2H0-ST`**（现役 = `0-C2H0-MM`，已实测）。

**③ 板级 BAR 布局/链路是否仍与 0x21 一致**
```bash
sudo lspci -vv -s 02:00.0 | grep -E "LnkSta|Region|BAR"
```
**期望**：`LnkSta: … 5.0GT/s, Width x4` + **2 个 Region**（1 MB + 64 KB）。⚠️ 换位流后可能要走"设备级 `remove`+`rescan`"（厂商设计 POST 时枚举 1 BAR 才需要"连根端口一起"）。

**④ "永不 tlast"是否被引擎接受**（侦察件 §8-④）
最小实验：ST 位流 + `s_axis_c2h_tlast` 常 0 + 连续发 N MB，宿主
`dma_from_device -d /dev/xdma0_c2h_0 -f out.bin -s <N> -c 1`（**不带 `-e`**），
**判据 = 宿主实收字节 == 板侧交付字数 ×4，且 `read()` 正常返回（非超时）**；
负对照 = 带 `-e` 的同一实验（应**卡到 `c2h_timeout`**，因为永不 EOP）。

**⑤ `tready` 的真实门控（描述符可用性/credit）**
- 无连接/不发描述符时读 `reg_rw /dev/xdma0_control 0x1040 r`（C2H ch0 status）看 `IDLE/BUSY`；
- 或做"慢宿主"实验（宿主故意延时提交下一笔 read），同跑取板侧 `drop_bytes` ——
  **判据必须三方对账**（板侧交付字数 vs 宿主实收字节 vs 丢弃计数）。

**⑥ 64 B 倍数约束的**宿主侧**表现**（PG195 ② 是"描述符长度"约束）
`read(fd, buf, N)` 取 `N % 64 != 0`，看是否短读/报错。—— **驱动按页切 SG，理论上不受影响**，但**未测**。

**⑦ 面积/时序**（本轮**未 synth**）：ST 臂的资源与时序只能由**实现轮的构建报告**回答。⛔ 本件不写"时序已解决"。

---

## §8 出处与证据清单（可逐条回核）

**本轮新增（全部在 `_proj_10g/notes/p8_axis_conf_20261011/`）**
- `work/mk_axis_ip.tcl` / `work/mk_axis_ip2.tcl`（可复跑实验脚本）+ 同名 `.bat`（ASCII+CRLF）
- `work/vivado_stdout.txt`（实验 1 全 stdout，含那条 `IP_Flow 19-3461`）+ `work/vivado_stdout2.txt`（实验 2 四臂）
- `work/cfg_*.txt`（14 份全量 `CONFIG.*`）· `work/cfg2_*.txt`
- `work/evidence/`：`xdma_st.veo` `xdma_st.sv` `xdma_st_ooc.xdc` `xdma_mm.veo` `xdma_mm.sv` `xdma_mm.xci`
  `xdma_st.xci` `xdma_b.sv` `xdma_d.sv` `xdma_d.veo` `gen_tree_listing.txt`（872 条生成文件名）
  （PG195 全文提取件**不入库**；见本地 PDF 路径）
- `work/peer_driver_evidence.txt`（驱动侧逐条命令 + 原文）· `work/SHA256SUMS.txt`（34 件 sha256）

**仓库内（只读引用）**
- `board/build_p7b_ku5p.tcl:116-133`（现役 XDMA 块）· `:47-71`（pcs64 不动点范式）
- `vivado_prj/p7b_ku5p_prj.srcs/sources_1/ip/xdma_0/xdma_0.xci`（现役 MM 的磁盘读数；本轮用 `cfg_mm_*.txt` 做同构对照）
- `_proj_10g/notes/p8_axis_recon_20261011/RECON.md`（被核对象）

**Vivado 安装（只读）**
- `C:/AMDDesignTools/2025.2/data/ip/xilinx/xdma_v4_2/component.xml`（`xdma_axi_intf_mm` 选择表）
- `.../xgui/xdma_v4_2.tcl`（`:9549-9600` 宽度合法集；`:8765-8870` 频率合法集；`:13146-13180` `USER_CLK_FREQ`）

**本机文档（用户提供，2026-10-11）**
- `C:/Users/zhxue/Documents/XilinxDocs/IP/4.1_English/pg195-pcie-dma.pdf`（2,533,836 B；pdftotext -enc UTF-8 -layout 提取，
  全文提取件按版权**不入库**）。⚠️ **DocNav 本身不落盘文档**：`C:/AMDDesignTools/DocNav/resources/*.xml`
  只是 docs.amd.com 的**在线目录**（`hub-settings.xml`/`xdocs.xml` 里全是 https 链接）⇒ **本轮 PG195 全部引页码均出自上面那份本地 PDF**。

---

*本件 = EDA 读数与证据，不代行裁定；凡"观测 = 期望"处均带产物原文；凡未证处均标【需要验证】并给命令。*
