# P11（双 SFP+）· P1 实施 —— REPORT

> **TL 代落（2026-10-18 02:2x）**：本件 = P1 实施 agent 的完整报告原文（平台拒写 `.md`），由 TL 转录落盘；未改结论。TL 抽核见文末 §TL 抽核。
>
> **v1.1 修订注（2026-10-18 P1FIX 轮 / FINDINGS 低-1/低-2/低-8）**：§3 的行号锚点改为**符号引用**
> （原 `:310/:4630/:4797` 是提交时笔误级漂移，实际见 DESIGN_v5 头注）；§4 增“142 = 132 named +
> 10 snap_take”口径；§8 的 p7b_chain 新增文件数订正为 **6 件**；G1 全文日志已归档到 fix 轮
> `gates/`（原只在 ignored workdir）。**结论与门读数不变**。

- 日期 2026-10-18；轮目录 `p9_dual_sfp_p1_impl_20261018`（p9_* 历史命名空间）。
- 施工权威 = 同目录 `DESIGN_v5.md`（P11 标注、FINDINGS 逐条处置、U-1..U-7 回灌）。
- 不下 PASS/FAIL 裁定；纸面/未测如实标。

## 0. 结论表

阶段 1 设计 v5 已落盘；阶段 2 门债：chain 门加 `TCP_TX_OVL`+xpm，未改 RTL 基线 **106/0 PASS**；`run_tx_ovl_gate` 未修（8 锚点漂移），替代门 = chain 门；阶段 3 RTL 完成，目标 **0x2B**（83 字/`0x17C`）；**G1 142/0 PASS**；**G4 29/0 PASS**；**G2 PASS_ALL**；**G5 4/4**；**G3 矩阵 20/20 EXIT=0 FROZEN**；读侧 **0x2B 65 处/17 文件 0 fail**，负控 **4/4 有牙**；改动 **57 文件 +10041/−289**（含 impl notes/gates；实现面剔除 notes = 38 文件 +2371/−289）；未跑构建/板级。

## 1. 阶段 1（设计 v5）

`DESIGN_v5.md`：`snap_busy` 排除 `ch0_busy`；`snap_req` 清全部状态；G1-f 双代；DP ~223–230 / pcie ~468 FF；W77.vcc 自由计数 mod 256；LOS 只数上升沿 + priming；好帧 `tlast && tcrs && !terr`；模式 A = 默认/显式，B = `SFP2_MODE_B`；P2 A-1 清单 §9；P3 判据改写（聚合 ≤~9.5 Gbps + 每口公平 + 丢帧/背压可读）；观测最小集 W76+W78+W79+W80。

## 2. 阶段 2（门债）

- chain 门：+`TCP_TX_OVL`、+xpm（修既有 elaboration 失败）、`P4_WORKDIR`/p4env、字面文件表。
- 基线（未改 RTL）：**106/0 PASS**，01:21:16 +0800，`gates/G1a_baseline.txt`。
- `run_tx_ovl_gate.bat`：`mk_mut_tx.py --dry-run` = `DRYRUN FAIL 8 (0 bytes written)`；8 个 Stage-C 锚点漂移（c1/c2×3/c7/c8/f1×2/k1×2/k2）；生成器 all-or-nothing；**替代覆盖 = chain 门编 `TCP_TX_OVL`，级别 = compile/elaboration only（不是行为覆盖；chain TB 只 force `txsrc_*`，不驱动 `tcp_tx_frame` —— v1.1 / FINDINGS 中-1）**。`gates/tx_ovl_gate_status.txt` 已就地订正措辞。
- `p7bchain_src.f`（49 文件）+ `run_matrix_p4dfix.bat` 第 20 门 + `paths.txt` 指纹；`-only p7b_chain` EXIT=0；全矩阵 20/20。

## 3. 阶段 3（P1 改动）

`wrapper_p4.v`（**v1.1：符号引用；行号 = 提交时现读，不保证后续树**）：`SFP2_MODE` 硬门（`g_sfp2_mode_conflict` / `g_sfp2_mode_b_requires_p7b` generate）、ch0 域别名（`rx_core_clk_0` / `tx_fe_clk_0` 的 assign 块）、ch0 复位（`rstn_rx_sr_0`）、ch0 MAC+tap+sink（`u_mac_rx_ch0` / `ch0_rx_*` / `ch0_acc_bytes`）、ch0 PCS/事件/LOS（`pcs0_*_sr` / `pcs0_*_evt` / `los1_*` / `los2_*`）、几何（`SNAP_NW_P6E` / `SNAP_P7BDP_NW` / `SNAP_CH0_NW`）、p7bdp 槽 36..38（`assign p7bdp_din[36..38*32 +: 32] = ch0_pcs_status/ch0_pcs_evt/ch0_los_bundle`）、`u_snap_ch0`、超时/busy（`ch0_to_cnt` / `ch0_snap_to` / `snap_busy`）、装配（`snap_dout_all`）、BID（`BUILD_ID_V`）、axi_regs `ch0_snap_to`。⚠️ 原行号 `:310/:4630/:4797` 已订正（实际提交时现读 = `:352-353` / `:4601` / `:4824`；DESIGN_v5 头注同）。
`axi_regs.v`：`ch0_snap_to` 输入/逐代锁存/`SNAP_STATUS[7]`（bit6 及以下不变）。
`p7b_pcs_stub.v`：`rx_clk` 拆 0/1、status 拆 `*_0/*_1`、fault 每拍驱动 0（force/release 坑）。
`tb_p7b_chain.v`：几何 83/`0x17C`、W76..W82 force、ch0 注入/LOS/超时双代/TX 常量、`snap_take` 硬断言、既有 force/W39 同步；6 处健壮化（`snap_take` 12000 硬超时、TX 捕获 65536、group6 负沿 force、SOP 重置 `got_len`、G4 前 drain、G4 SOP-2 限定 F4 窗口外）。
新 `tb_p1_ch0_unit.v` + `run_tb_p1_ch0_unit.bat`（29 判据）；`run_elab_4combo.bat`。
读侧：`apply_readside_bid1c.py` 阶段 0x2B（65 处/17 文件）+ STAGES + ALLOW；p6e wrapper/counters、chain TB 手工同步；`P7B_BIZ_WINDOW.md` 更新 83 字/W76..W82/`0x17C`。

## 4. 门读数

G1-a **106/0 PASS**；G1 **142/0 PASS**（**v1.1 口径：142 = 132 条具名 `[PASS]` + 10 次 `snap_take` 硬断言** —— `snap_take` 每次 `checks++` 但不打印 PASS；长标签被 `chk` 的 `[255:0] name` 截断后以 `[PASS] c …` 形式落在全文日志里）；G4 **29/0 PASS**（18 条具名 + 11 次 `snap_take`）；G2 **PASS_ALL**（W76..W82 读 0 全 PASS）；G5 **ELAB_4COMBO_PASS 4/4**；G3 **20/20 EXIT=0/FROZEN/RC=0**（01:42:37–02:11:30）；读侧 apply **65/17/0 fail**、assert 0 fail、rehearse 0 阶段 0 fail、negctl table/bid/tier/face **4/4 有牙（RC=1）**；tx_ovl 未修（**覆盖口径 = compile/elaboration only**，见 §2 与 fix 轮订正）。`gates/` 内为摘录；**G1 全文日志已由 P1FIX 轮从 ignored workdir 归档**（fix 轮 `gates/G1_chain_2B_full.txt`）。均带 `P1IMPL-*`/`P1FIX-*` 独有串与时刻。

## 5. FINDINGS/裁定对照

高-1/2 改形（P3 判据）；高-3/4 采纳入 P2 清单；高-5/6/7 采纳并实施；中-1..9/16/18/19 采纳；中-10..15/17/20 登记（P2/P3/文档/板级前置）；低-1..10 登记；U-1..U-7 落 `DESIGN_v5 §0`。

## 6. 偏离/未测

W77.vcc 自由计数；G4 SOP-2 口径（F4 窗口外）；chain TB 6 处健壮化；读侧 3 TB 手工同步；p6e MIR 降序 token；`tb_biz_win` 加 `ch0_snap_to(1'b0)`。
未测：构建/板级/HLS 双 IP/乙镜像/BER/停钟行为；观测最小集待裁；`run_tx_ovl_gate` 未修；REPORT.md 平台拒写（本内容由 TL 代落盘）。

## 7. 构建前置与 backstop

`tcl:286` 追加 `SFP2_MODE_A=1`；走 `run_build_p7b_ku5p.bat`；一次收口；读数 WNS/WHS/三类端点、`12-4739`、隐式网、DRC、clock interaction、sha256、资源。
**backstop（每次 = 新输入）**：B1 删 W77（82/`0x178`）→ B2 删 W79..W82 + ch0 MAC（79/`0x16C`）→ B3 P1-min 仅 W76+W78（78/`0x168`，需用户接受）。
板级草案 = `DESIGN_v5 §10.4`（`0x04=0x2B` / 83 字 / `0x17C=0xffffffff` / 2 BARs / x4；S-1..S-7，含负对照；`0x08` bit1=0）。

## 8. 文件清单

见 `DESIGN_v5 §12` 与本报告 §3；`git show --stat 3d4ce8ad` = **57 files, +10041/−289**（实现面口径：剔除 impl notes/gates = 38 files, +2371/−289）。
**v1.1（FINDINGS 低-8）**：本轮 `_proj_10g/p7b_chain/` 目录新增 **6 件**（不是 5 件）=
`tb_p1_ch0_unit.v` · `run_tb_p1_ch0_unit.bat` · `run_elab_4combo.bat` · `elab_files.f` ·
`hls_p1ch0.f` · `hls_p7bchain.f`（另 `run_tb_p7b_chain.bat` 为**修改**，不计新增）。

---

## TL 抽核（2026-10-18 02:2x，逐条回源）

| # | 抽核项 | 结果 |
|---|---|---|
| 1 | diffstat | ✓ 提交后 `git show --stat 3d4ce8ad` = 57 files +10041/−289；提交前 `git diff --stat`（未加新文件）= 29/+1297/−288 —— 两个口径不同，已按实际订正（审查 中-7） |
| 2 | wrapper 锚点 | ✓ `SFP2_MODE` 硬门 `:255-280`；`SNAP_NW_P6E=83` `:3522`；`SNAP_CH0_NW=4` `:3554`；`snap_busy` 注释"不得 OR ch0snap_busy" `:4478`；`ch0_los_bundle` 模式位 `:3998` |
| 3 | axi_regs | ✓ `ch0_snap_to` 输入 `:196`、逐代锁存 `:339`、`SNAP_STATUS[7]` 注释 `:193` |
| 4 | G1a 基线 | ✓ `tb_p7b_chain done: 106 checks, 0 fail; VERDICT = PASS` |
| 5 | G1 全链 | ✓ `142 checks, 0 fail; VERDICT = PASS` |
| 6 | G4 单元 | ✓ `29 checks, 0 fail; UNIT VERDICT = PASS` |
| 7 | G3 矩阵 | ✓ `VERDICT: FROZEN`（296 hashed files / 240 compile files 逐字节相同；HEAD `dbbbe1e7`） |
| 8 | G5 四宏 | ✓ `ELAB_4COMBO_FAILS=0 / ELAB_4COMBO_PASS`（c4 = P7B=0 PCIE=0 OK） |
| 9 | G2 p6e | ✓ `PASS_ALL`（W81/W82 读 0 PASS） |
| 10 | 读侧负控 | ✓ table/bid/tier/face 各 `NEGCTL_VERDICT 有牙` + `NEGCTL_EXIT=1` |
| 11 | 无 Vivado 运行 | ✓ `tasklist` 无 vivado |
| 12 | 未跟踪边界 | ✓ 本轮新增仅 impl 轮目录 + p7b_chain 5 件；`__pycache__`/历史 scratch 不入库 |

**抽核结论**：12/12 与报告一致；未发现转录错误。构建前置与 backstop 按报告执行（构建轮另派）。
