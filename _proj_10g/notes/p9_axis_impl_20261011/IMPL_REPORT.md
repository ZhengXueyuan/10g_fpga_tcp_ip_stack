# P9 · XDMA `AXI4-MM → AXI4-Stream` 的 FPGA 侧实现轮 — IMPL_REPORT

**轮次**: 2026-10-11 晚 · 目录 `_proj_10g/notes/p9_axis_impl_20261011/`
**派单边界 (逐条遵守)**: ⛔ 不出位流 · ⛔ 不 bump BID · ⛔ 不做读侧同步 · ⛔ 不烧板。
构建 + 读侧 + 板级 = 构建轮。**本轮不下 PASS/FAIL 裁定**, 不写"时序已解决"。

**权威件**: `_proj_10g/notes/p8_axis_conf_20261011/CONF.md` (配置/端口表/顺序陷阱/驱动事实);
侦察件 `p8_axis_recon_20261011/RECON.md` 只作背景 (CONF 已订正它 13 处)。

---

## §0 一页结论

1. **IP 切换在真 EDA 流程里成立 (synth 检查点实测)**: B 臂写法 (12 项 `-dict` 照抄 + 单独一行
   `CONFIG.xdma_axi_intf_mm {AXI_Stream}`) ⇒ 两条 RC=0、**无任何 `19-3461/19-3438/17-39`**、
   13 项回读 **MISMATCH_N=0**、生成产物 6 个展开参数 (DMA_ST=1 / DMA_MM=0 / XDMA_AXI_INTF_MM=0 /
   AXI_DATA_WIDTH=128 / USER_CLK_FREQ=2 / XDMA_AXILITE_MASTER=TRUE) **BAD_N=0** ⇒ `XDMA_VERDICT = OK`。
2. **新件 = `rtl/axis_c2h_stream.v`** (替代期 B 的环 + 两个 AXI-MM 从机): 上游 aux 合同**一字不改**,
   下游 = 128 位 AXIS 拍。**丢字节口径 = 无容量不拉 `dma_req`** ⇒ 不新增任何丢字节计数器,
   丢字节仍全部记在 **`W70`**; 快照几何**不扩** (71 字 / 未实现地址 `0x14C`)。
3. **TL 口径 (2026-10-11) 已逐条落实** (与本轮首版方向相反的两处, 按裁定改写):
   ① `MIR_DMA_CNT` 计数点 = **上游 aux 口取走** (`dma_gnt`, 每 grant +2), 不是 `tvalid&&tready`;
   ② 停流 flush 触发式 = **`stop = (!cap_en) || (!en) || clr`** (电平/脉冲的"或"); `clr`
   **不丢弃**残拍 (作为短末拍送出) 且使计数归零。触发式已**逐字写进头注释** (TL 点名要求)。
4. **门**: 新件单元门 **PASS_ALL** + **7 突变臂全部被捕获** (红灯面互不相同; 每件与源 diff 恰 1 行);
   p6e **真 wrapper 全链门 PASS_ALL (0 FAIL)**; lint (¬DP 支) LINT-OK + xelab 建快照;
   既有 counters/镜像/环门全绿; `¬APP_MODE` 组合 = **HEAD 既存编不过** (两臂证据, 诊断副本证明本刀干净);
   `p5_wrapper` EXIT=0 (解析面)。见 §5。
5. **synth 检查点**: 新 IP **真编过** (OOC dcp 落盘) + 断言全中; 综合面 (pre-place) **LUT −616 /
   FF −1,201 / BRAM −4 / WNS +0.006 (→ −0.371)**; **新件不在 top200、定向锥 ≥ +1.53 ns**;
   ⛔ 同批无拆刀 ⇒ **不归因**。见 §6。
6. ⭐ **排练抓到构建脚本里一个真 bug** (`p7b_cfg_diff_keys` 重复计数 ⇒ 构建轮会假红早退): 已修 + 复跑全过。
7. **未定项**: 字节序的宿主侧落点 (XDMA 把 `tdata` 按小端写内存 —— 未 EDA 证); "永不 tlast"
   是否被引擎长期接受 (CONF 已登记为需板级验证); `clr` 中途的残拍边界 (≤16 B 会跟在 post-clr 窗口头部);
   停流 flush 覆盖不到"暂存全空"的情形 (发不出空拍 ⇒ 最后一个未满描述符等驱动超时)。
   **全部登记在 §8, 不许当已答。**

---

## §1 改动清单 (逐文件; 全部在本轮派单的可写面内)

| # | 文件 | 改动 | 说明 |
|---|---|---|---|
| 1 | `rtl/axis_c2h_stream.v` | **新增** (~200 行, 含头注释) | C2H AXIS 成形器 (B 项) |
| 2 | `board/wrapper_p4.v` | 四段: ① 35 根 `m_axi_*` 网线 → 10 根 AXIS 网线 (单点声明) ② 真支三件套 → `u_mir_axis` ③ 两个 ¬ 支 → AXIS 常量表 ④ XDMA 例化端口表 75→50 | C 项 |
| 3 | `board/build_p7b_ku5p.tcl` | ① XDMA 块: AXIS 配置 (B 臂) + 两层日志牙 + 13 项回读 + 生成产物 6 参数 + 与两份冻结参照转储**逐行 diff** ② 文件清单: −3 个 MM 件, +`axis_c2h_stream.v` | A 项 |
| 4 | `_proj_pcie/rtl/axi_regs.v` | `MIR_STATUS.ver` **3→4** + `MIR_DMA_CNT`/`dma_en` 注释同步 (**位域/地址表 0 改动**) | D 项 |
| 5 | `sim/p6e_pcie/xdma_0_sim_stub.v` | 端口表换 50 根 AXIS + C2H 消费者 (可控 `tready` / 逐拍记录 / keep·tlast 合同自检) + H2C 生产者 + 4 个层次任务 | E 项 (不同步则全链门编不过) |
| 6 | `sim/p6e_pcie/tb_p6e_pcie_wrapper.v` | M1-B (环/AR→R/写通道) 整段 → **P9-B** 8 组 AXIS 判据 | F 项 |
| 7 | `sim/p9_axis_stream/{tb_axis_c2h_stream.v, run_tb_axis_c2h_stream.bat, mut_axis.py}` | **新增** (单元门 + 7 突变臂) | F 项 |
| 8 | `rtl/app_rx_mirror.v` | **仅头注释**两条订正 (审查 ⑥-1 / ⑥-3) | G 项 |
| 9 | `_proj_10g/notes/p8_mir_stg_20261011/DESIGN.md` | §4.1 回写块 (两处"草图 vs 实现"分叉) | G 项 |
| 10 | `_proj_10g/notes/p9_axis_synth/*` | **新增** synth-only 检查点 (含与构建脚本逐字同款的 XDMA 断言块) | F 项 |
| 11 | `_proj_10g/notes/p9_axis_impl_20261011/*` | 本报告 + PROGRESS + 门日志 + 断言牙口排练脚本 | 交付 |

**保留在树、不再入位流** (派单要求: 不删文件): `rtl/mir_dma_ring.v` · `rtl/aximm_c2h_win.v` ·
`rtl/aximm_h2c_discard.v` (单元门 `sim/p7b_mirdma/` `sim/p7b_h2cdisc/` 仍在, 直接编模块本身)。
**回退路径** = 烧 0x21 旧位流 (`fbb6fca8…`) / `git revert`; ⛔ 不在同一 wrapper 里并存两套端口表。

---

## §2 IP 配置与断言 (A 项)

**写法 (CONF §2.3 的 B 臂 + A 臂排序保险)**: 12 项基线**一次 `-dict` 照抄原样** (顺序不动) +
**之后单独一行** `set_property CONFIG.xdma_axi_intf_mm {AXI_Stream}`。⛔ 不用"逐条设+吞异常"
(实验 1 实测那条路径会报 `19-3461`), ⛔ 宽度不写 `64_bit` (8.0GT/s×X4 下非法 ⇒ 静默回滚)。

**两层日志牙** (CONF §2.3 硬结论 ②: 回读比对**抓不到**回滚):
```
set_msg_config -id {IP_Flow 19-3461} -new_severity {ERROR}
set_msg_config -id {IP_Flow 19-3438} -new_severity {ERROR}
catch { set_msg_config -string {Restoring to previous valid configuration} -new_severity {ERROR} }
```
+ 两个 `catch` 收 RC + 对捕获消息做四模式文本扫描 (`19-3461` / `19-3438` / 那句原文 / `17-39`)。

**生成后回读断言** (照 `pcs64` 不动点范式, 三件):
- (i) 13 项 CONFIG 逐项 `get_property` 比对 (含 intf);
- (ii) 生成产物 `synth/xdma_0.sv` 的 `CORE_GENERATION_INFO` 6 个展开参数 (权威 = 引擎自己的产物);
- (iii) 与**冻结参照转储**逐行 diff: 对 MM 参照 (`cfg_mm_post_gen.txt`) 必须**只差 2 行**
  (`CONFIG.Component_Name` + `CONFIG.xdma_axi_intf_mm`), 对 ST 参照 (`cfg_st_post_gen.txt`) 只差 1 行。
  参照件缺失 = **硬失败** (判据不静默降级)。
⇒ 任一不满足 ⇒ `P7B_VERDICT = XDMA_ST_CFG_FAIL` + `exit 1` (早退 ⇒ 没有位流 ⇒ bat 侧 `NO-BITSTREAM` 红)。

**断言的"牙口"已提前排练** (`check_cfgdiff_teeth.tcl`, 从句点里**文本提取**同一段 procs, 无副本漂移):
T1 「两份参照之间 = 恰 2 行」/ T2 「模拟我们的 dump ⇒ vs ST 1 行 / vs MM 2 行」/
T3 **负对照**「篡改一个无关键 ⇒ 必须被检出」⇒ 见 §5。

---

## §3 新件合同 (`rtl/axis_c2h_stream.v`)

**上游 (aux 读口, 合同一字不改)**: `dma_req`(电平, 本模块→镜像) / `dma_gnt`(同拍握手) /
`dma_data[63:0]` = 2 个逻辑字, `[31:0]` = 先出的字; 空态不弹 / 主机弹出优先。

**打包**: 2 次 grant = 16 B = 1 个 128 位拍; `tdata = {第2次 grant, 第1次 grant}`
(**先出的字落低字节** ⇒ 与 `mir_dma_ring` 的行读口径同代, 工具侧字节流语义不变)。
`tkeep`: 非末拍恒 `16'hFFFF`; 短末拍 **`16'h00FF` (挤 LSB, 非全 0)** —— PG195 v4.1 **p.27** 逐字
("all 1s except for the last data transfer" / "packed to the lsb" / "tlast 且 tkeep 全 0 非法")。
`tlast` = **方案 A**: 正常恒 0 (全流 = 一个无限长包), 只在**停流残拍**那一拍置 1
(PG195 p.26–27: 描述符"填满 **或** 收到 EOP"都回写)。

**⭐ 停流触发式 (TL 2026-10-11 裁定 ②; 头注释逐字给出)**:
```
stop = (!cap_en) || (!en) || clr                      // 三者任一 = 停流 (电平/脉冲的"或")
mv_go(残拍成形)  = b_free && (mv_full || (stg_half && stop))
mv_last(末拍标记) = mv_full ? stop : 1'b1              // 半拍恒末拍; 整拍在停流拍上打 last
```
`clr` 语义 (裁定 ④): **不丢弃**残拍 (作为短末拍送出 ⇒ **packer 残留 = 0**), 且使计数归零。
**⭐ 计数点 (TL 裁定 ①)**: `MIR_DMA_CNT` = **从 aux 口取走的 32 位字数** (每 grant **+2**),
`clr` 归零。

**丢字节口径**: ⛔ 不新增任何丢字节计数器 —— **无容量时不拉 `dma_req`** (`dma_req = en && 有空槽`) ⇒
镜像 FIFO 自然涨满 ⇒ 丢字节**全部记在 `W70`** (`app_rx_mirror.drop_bytes`, dp 域寄存器输出)。
⇒ "宿主 read 之间的空档" 不被板内缓冲吸收 (首版**不加缓冲**): 空档 → `tready` 低 → 停拉 req →
FIFO 满 → `W70` 上涨 (可判读数, 不是静默)。

**实现要点**: 暂存 = 2 × 8 B 槽 + 1 个 16 B 寄存成形拍 (tvalid/data/keep/last **全寄存** ⇒
AXIS "tvalid 不依赖 tready、停顿期载荷稳定" 结构性成立); 持续率 **8 B/cycle @250 MHz**
(= 2 GB/s > 源上界 1.25 GB/s, 单元门 G8 实测 ≥1 拍/2 拍钟)。

---

## §4 顶层接线 (C 项): 端口表 75 → 50

- **消失 35 根 `m_axi_*`** (不是侦察件写的"~60 根"); **新增 10 根 AXIS**; 保留 40 根
  (`m_axil_*` 19 + `cfg_mgmt_*` 7 + 时钟/链路/中断 14) —— 全部照 CONF §3.1 (生成产物逐字)。
- **⛔ 没有 `tuser`** (本配置无 Parity ⇒ PG195 Table 15/16 只在 Propagate Parity 模式生成)。
- 三分支 (沿用原"单点声明、分支只驱动"纪律; 按宏叉开两份端口表**本工程已点名禁止**):
  · 真支 (`APP_MODE ∧ DP_156MHZ`) = `u_mir_axis` + `assign mir_h2c_tready = 1'b1`;
  · ¬DP_156MHZ / ¬APP_MODE = AXIS 常量表 (`tvalid=0` + 边带同钉 / `h2c_tready=1` / `dma_cnt=0`)。
- ⛔ 未动: `board/wrapper_p4.v:1319-1322` 的 app 寄存器总线 tie-off · M1 块其它部分 · `:2144` 一带。

---

## §5 门读数 (F 项)

### 5.1 新件单元门 `sim/p9_axis_stream/` — **PASS_ALL**

正臂判据 (G0..G10, 全部自检式无 Python): 复位态 / 正常打包手算锚 / 半拍不成形 /
**背压 (载荷恒定 + 暂存满 ⇒ `dma_req`=0 + 恢复后按序无丢)** / `en` 停流短末拍 /
**`cap_en` 停流短末拍** / 整拍停流 ⇒ `last=1` 且 keep=FFFF (数据不丢) / `en=0 ⇒ dma_req 恒 0` /
**`clr` ⇒ 残拍作为短末拍送出 + 计数归零** / 吞吐 ≥1 拍每 2 拍钟 / 计数口径 (取走计数) /
末拍稳定性 (跨 `cap_en` 撤销载荷不变)。

**7 条突变臂 (每件恰 1 行、恰 1 处命中 [`diff` 实核]; 全部被捕获, 红灯面互不相同)**:

| 臂 | 突变 | 被哪条判据抓 (红灯面) | FAIL 数 |
|---|---|---|---|
| `mut_last` | `mv_last` 恒 0 | G4e / G4c-e / G5h (`tlast == 1`) | 5 |
| `mut_keep` | 短末拍 keep `00FF → FF00` | *-keep == 00FF 一族 (G4d/G4c-c/G7f) | 4 |
| `mut_order` | 拍内字序反 (`{s1,s0} → {s0,s1}`) | 内容锚一族 (G1b/G3g/G3h) | 10 |
| `mut_req` | `dma_req` 去掉容量项 | G3b (grant 数) / **G3c (满态仍拉 req)** | 5 |
| `mut_cnt` | 取走计数 `+2 → +4` | G1e / G2d / G9a | 6 |
| `mut_clr` | `clr` 不清计数 | G7c / G9a | 2 |
| `mut_stop` | `stop` 去掉 `clr` 项 | **G7d (clr 不 flush 残拍)** / G7e / G7f | 8 |

> ⚠️ 门自己踩过的三类坑 (都写进 TB 注释, 供复核者): ① TB 队列模型 blocking 写 与 NBA 写
> 同一变量 ⇒ 同拍 NBA 覆盖 blocking (**连踩两版**: "清不掉队列"/"入队丢失"); ②
> `clr = 1; @(posedge clk); clr = 0;` 的 blocking 与当拍 posedge 竞争 ⇒ **clr 脉冲被吞**
> (工程坑 3/17 同族; 修 = negedge 驱动 + 非阻塞); ③ 判据前置: 停一手 (`en=0`) 让 DUT 内部
> 流水排空再取计数基线, 否则"取走未交付"的尾巴会让拍数不确定。

### 5.2 p6e 真 wrapper 全链门 `sim/p6e_pcie/` — **PASS_ALL (0 FAIL)**

新桩 (50 根 AXIS 端口) + 新 wrapper 端口表 + 新件一起过: P9-B 8 组 (单拍手算锚 / 多拍逐拍 /
**背压 ⇒ 不拉 req ⇒ `W70` 记账** (700 字灌入) / 停流 flush / `dma_en` 门 / **`clr` 单独触发
flush** / clr-flush 内容 + 计数归零 / **H2C 恒吞噬 50 拍 + 边带线非 Z**) + 既有判据 1–9 / M1 期 A
全部保持 PASS。`MIR_STATUS.ver == 4` 读回 ✓。

### 5.3 既有门 / 旁支编译面 (全绿; 逐条注明覆盖面)

| 门 | 宏组合 | 结果 | 覆盖面说明 |
|---|---|---|---|
| `sim/p6e_pcie/run_tb_p6e_pcie_counters.bat` | PCIE_OBS+APP_MODE+DP+DEV_USP | **PASS_ALL** (W16/W17 + W26..W31) | 用新桩 ✓ (未用任何 `m_axi` 信号) |
| `board/run_lint_p6e.bat` | PCIE_OBS+APP_MODE (**无 DP_156MHZ**) | **LINT-OK** (xvlog exit 0 + **xelab 建快照**) | 覆盖 **¬DP_156MHZ** 的 AXIS 常量表支; 0 隐式网 / 0 位宽失配 |
| 本目录 `run_compile_negappmode.bat` | PCIE_OBS (**无 APP_MODE**) | ⛔ **HEAD 即编不过** (见下) | 见"既存缺陷"条 |
| `run_tb_app_rx_mirror.bat real` | — | **PASS_ALL** | 镜像件 (逻辑未动, 只改头注释) 无回归 |
| `run_tb_mir_dma.bat real` | — | **PASS_ALL** (45 checks) | 环件保留在树且仍自洽 (不再入位流) |
| `run_matrix_p4dfix.bat -only p5_wrapper` | APP_MODE only | **EXIT=0** | 唯一编 `wrapper_p4.v` 的常驻门; 本刀改动全在 `ifdef PCIE_OBS` 内 ⇒ 它只做**解析面**检查 (弱证据, 如实登记) |

> ⚠️ **`PCIE_OBS ∧ ¬APP_MODE` = 既存缺陷 (本刀无关, 登记不修)**: 该组合 **HEAD 即编不过**
> (6 条 `VRFC 10-2989`: `udpapp_{tx,rx}_{frames,bytes}` / `rx_null` / `mismatch` 未声明 ——
> 快照装配段引用 APP_MODE 内部线)。**两臂证据**: HEAD 的 `board/wrapper_p4.v` (git `dd6fe3d`,
> 提到本目录 `head_negapp/wrapper_p4_head.v`) 用同一命令编 ⇒ **完全相同的 6 条错误签名**。
> ⇒ 该组合下**本刀的 ¬APP_MODE AXIS 常量表拿不到整体编译证据**; 补一个**诊断副本**
> (`head_negapp/wrapper_p4_negapp_patched.v` = 现役文件 + 只给那 6 根线加常量声明, **不进树**)
> ⇒ **xvlog RC=0 + xelab "Built simulation snapshot"** ⇒ 本刀的常量表在该支**结构上干净**
> (与 ¬DP 支逐字同形, 那一支过了 lint)。

### 5.4 构建脚本断言代码的"牙口排练" (`check_cfgdiff_teeth.tcl`)

**`P9CFGDIFF_TEETH = OK`** (T1/T2/T3 全过):
- T1 两份参照之间 = 恰 `{CONFIG.Component_Name, CONFIG.xdma_axi_intf_mm}` (CONF §2.1 复核);
- T2 排练 (模拟我方 dump) ⇒ vs ST 参照 **1 行** / vs MM 参照 **2 行** —— 与构建脚本断言逐字相同;
- T3 **负对照**: 篡改一个无关键 (`CONFIG.BASEADDR`) ⇒ **被检出** (差集含它) ⇒ 断言不是恒绿。
> ⚠️ **这次排练抓到构建脚本里的一个真 bug**: 差异键没有从参照表里删掉 ⇒ 被"左表残留"循环
> **再数一次** (2 行数成 4 行) ⇒ 构建轮里会**假红并早退**。已就地修 (`build_p7b_ku5p.tcl` 的
> `p7b_cfg_diff_keys`, 差异分支补 `catch { unset A($k) }`) 并复跑 T1/T2/T3 全过。
> ⭐ 这是"把断言写进脚本 + 提前排练"的直接收益 (否则要等 34 分钟的构建回报假红)。

---

## §6 synth 检查点 (`_proj_10g/notes/p9_axis_synth/`, **synth-only**)

**流程与构建脚本同文件表/同 define/同 XDC/同 XDMA 断言块** (⇒ 它也验证了"新 IP 能编过")。
**A/B 对照臂 = `_proj_10g/notes/p8_stg_synth/` 的 `p8stg` 臂** (上一版 0x21 树, **同一脚本同一流程**)。

### 6.1 XDMA 断言面 (决定性)

`RC_BASE = 0` · `RC_INTF = 0` · **无任何 `19-3461/19-3438/17-39`** · **RB_MISMATCH_N = 0 (13/13)** ·
**GEN_BAD_N = 0** (生成产物 6 个展开参数全中) ⇒ **`P9SYNTH_XDMA_VERDICT = OK`**。
**xdma_0 的 OOC 综合完成** (`xdma_0.dcp` 已生成) ⇒ 新 IP 配置**真编过** (不只是 generate)。

### 6.2 综合面读数 (pre-place; ⛔ 不与后布线读数比大小)

| 指标 | `p8stg` 臂 (0x21 树) | **`p9axis` 臂 (本刀)** | Δ |
|---|---|---|---|
| CLB LUTs | 84,594 | **83,978** | **−616** |
| CLB Registers | 79,147 | **77,946** | **−1,201** |
| Block RAM Tile | 354 | **350** | **−4** |
| URAM | 0 | 0 | 0 |
| **WNS (synth 估计)** | −0.377 | **−0.371** | **+0.006** |
| WHS (synth 估计) | −0.661 | −0.661 | 0 |
| 文件数 | 444 | 442 | −2 (三件出 / 新件入) |

- **全局最差路径 = DP 域 `g_hw.clk_out0`** (`u_tcp_tx/FSM_sequential_rx_state_reg[0]/C → u_app/stg_reg[0]/CE`,
  group WNS −0.371 / 325 failing at synth) —— **与上一臂是同一个源/宿对** ⇒ **不是新件**。
- **新件 `u_mir_axis` 在 top200 报告里 0 命中**; 定向查询: FROM 侧最好 **+1.531 ns** /
  TO 侧最好 **+2.120 ns** ⇒ 新逻辑**离临界路径很远**。`pcie_axi_aclk` 组 (新件所在域)
  synth 面 = async_default WNS 2.725 ⇒ 富余。
- **XDMA 的 IP 级 A/B** (两个 OOC 报告, 同工具/同 part/同 IP 版本): MM 臂 17,322 LUT / 20,484 FF / 38 BRAM
  ⇒ **AXIS 臂 16,887 LUT / 19,192 FF / 38 BRAM** (**−435 LUT / −1,292 FF / BRAM 同**)
  ⇒ 侦察件"面积净额小幅减少"的【推断】**在 IP 侧被实测坐实**。
- ⛔ **不许归因**: IP 换模式与 RTL 换件**同批**发生, **无拆刀臂** ⇒ "谁贡献了多少"**不可判**;
  以上只作"整刀代价/收益"登记。⛔ **synth 面 pre-place 与后布线不可比**; 真正的裁定 = 构建轮的
  布线报告。

---

## §7 口径声明 (哪些变了 / 哪些逐字不变)

**变了** (逐条) ⭐:
1. `MIR_DMA_CNT(0x148)` 口径: "环已写字数" → **"从 aux 口取走的 32 位字数"** (地址/单位/名字不变);
2. `MIR_STATUS.ver` 3 → **4** (位域/地址表 0 改动; 依"位语义变了就 bump");
3. `MIR_CTRL[3] dma_en` 语义补充: 1→0 = 停流 (残拍以末拍送出); 注释里的"消费者"从环改为成形器;
4. 快照几何**不扩** (仍 71 字 / 未实现地址 `0x14C`) ⇒ 读侧同步 = **BID-only** (留给构建轮 `0x21→0x22`);
5. `rtl/app_rx_mirror.v` **头注释**两条订正 (⑥-1 / ⑥-3) —— 逻辑未动;
6. 构建文件清单: MM 三件出清单 (文件仍在树) / 新件入清单;
7. **构建脚本的断言代码修了一个真 bug** (`p7b_cfg_diff_keys` 重复计数 ⇒ 会假红; 见 §5.4) ——
   这是构建脚本**唯一的**逻辑性改动 (其余是新增断言段);
8. `MIR_DMA_CNT` 的**驱动器**从 `mir_dma_ring.wr_words` 换成 `axis_c2h_stream.dma_words` (同址同名)。

**逐字不变** (逐条) ⛔:
- 上游 aux 合同 / 镜像模块逻辑 (只改注释) / `axi_regs` 的地址表与位域 / BAR 与 AXI-Lite 通路 /
  时钟域 (`pcie_axi_aclk` 250 MHz 不变) / 两个 MIR 主机读口 (level/empty/dout/pop) /
  `W70` 的唯一性 (新增 0 个丢字节计数器) / `board/wrapper_p4.v:1319-1322` 的 app 总线 tie-off。

---

## §8 未定项 (⛔ 不许当已答; 逐条给"怎么证")

1. **字节序的宿主侧落点**: `tdata[7:0]` = 宿主缓冲 byte0 是**假设** (PG195 不写字节序) ——
   板级首测逐字节对账即可判 (失配形态 = 整拍内 8 B 交换, 一眼可辨)。**本轮未证。**
2. **"永不 tlast" 是否被引擎长期接受**: CONF §4.4/§7-④ 已登记为需 EDA+板级; 本轮**未跑**。
3. **停流 flush 覆盖不到的情形** (如实报, 按 TL 要求给上界): 若停流时**暂存全空** (最后一拍已整拍
   送出), 本模块**发不出空拍** (PG195 p.27 "tlast 且 tkeep 全 0 非法") ⇒ 宿主最后那个未填满的描述符只能等驱动
   超时 (`c2h_timeout`)。**残余上界不因此变大** (全空 = 残余 0), 但"读不到末尾"这一形态存在。
4. **`clr` 发生在流中途的边界**: 残拍 (≤16 B, clr 之前的数据) 会作为短末拍送出、随后计数归零
   ⇒ 宿主 post-clr 窗口头部可能出现这一拍。**协议上 clr 只在起测前写** (此时打包器空 ⇒ 无此拍);
   工具侧若要容忍 mid-capture clr, 需把这 ≤16 B 当"clr 前缀"处理。**本轮只登记。**
5. **镜像侧 `clr` 会丢弃 FIFO 内容 (≤2 KB)**: 那部分字节**从未被本模块取走** ⇒ 不进 `MIR_DMA_CNT`,
   也不进 `W70` ⇒ 账目式 `pc + ΔW70 + 残余 == K` 的残余项在 **mid-capture clr** 场景下可能大到
   FIFO 容量 (≤2 KB)。⇒ 与 #4 同源: **工具侧要么不在流中途 clr, 要么把 clr 当窗口边界**。
6. **synth 面读数不完整** (见 §6): 待检查点跑完填; ⛔ 不写"时序已解决"。
7. **lint 面结构性看不见本刀**: 现役 lint 的宏集不含 `DP_156MHZ` ⇒ 只覆盖 ¬DP 支。「按宏叉开
   端口表」这条纪律的完整覆盖靠 p6e 全链门 (§5.2)。
8. **`PCIE_OBS ∧ ¬APP_MODE` 组合**: **既存缺陷** (HEAD 同签名, 见 §5.3) ⇒ 该组合下本刀的常量表
   只有**诊断副本**的编译证据 (打过 6 行常量的"越过补丁", **补丁不进树**)。⛔ 不许写成
   "该组合已修好" —— 它**仍未修** (沿用既有"登记不修"纪律)。
9. **H2C 侧 = 恒吞噬**: 若将来有人真发 H2C 数据, 工具会当成功 (静默丢弃) —— 与 P2 的
   `aximm_h2c_discard` 同一已登记代价; 本轮**未观测到**任何 H2C 数据 (复位后 tvalid 由 IP 驱动)。
10. **synth 面 A/B 无拆刀**: IP 换模式 + RTL 换件同批 ⇒ §6.2 的 Δ **不许归因**到单件;
    且全为 pre-place, 与后布线不可比。
11. **构建脚本的 XDMA 断言段本身未经"真构建"跑过**: 其 Tcl 逻辑已排练 (teeth OK), 但整段
    (含 dump/参照路径/早退) 只在检查点里以同款代码跑过 —— 构建轮第一次真跑时若路径有变
    (notes 被裁) ⇒ 参照缺失会**硬失败** (设计如此, 见 §5.4/§2), 届时按日志一行即可判。

---

## §9 交付件地图 (本目录)

```
IMPL_REPORT.md                 本报告
PROGRESS.txt                   逐项时间线 (含门自踩的三类坑)
check_cfgdiff_teeth.tcl        构建脚本断言的排练 + 牙口自检 (Vivado batch; 输出 P9CFGDIFF_*)
run_compile_negappmode.bat     ¬APP_MODE 组合编译/elaborate 检查 (被既存缺陷挡住, 见 §5.3)
head_negapp/                     HEAD 版 wrapper (证明既存缺陷) + 诊断补丁副本 (证明本刀干净)
logs/                          全部门日志 (单元门 8 份 / p6e 全链 / counters / lint / mirror / ring /
                               ¬APP_MODE 两臂 / synth stdout + 6 份 rpt)
rehearsal_mine.txt             排练用的"模拟我方 dump" (可复跑产物)
xdir_negapp/                    ¬APP_MODE 检查的工作目录 (含 logs)
```
门外件 (不在本目录): `sim/p9_axis_stream/` (单元门 TB + runner + mut_axis.py + mut/ + xdir_*) ·
`_proj_10g/notes/p9_axis_synth/` (synth 检查点 + 报告) · `board/`, `rtl/`, `_proj_pcie/rtl/`, `sim/p6e_pcie/` 的改动。
