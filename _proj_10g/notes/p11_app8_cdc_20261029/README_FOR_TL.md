# P11 APP8 CDC 轮（0x36/0x37）—— README_FOR_TL

日期：2026-10-29 01:45–05:xx（用户指令：「持续自主推进到早上 7 点，逐个修复问题，修好就上板验证」）

## 0. 一句话

**0x36（CDC/OCC=0）已构建通过并上板**：身份全中、CDC 健康字干净、8 连接数据面内容全过
（102 MB 逐字节 + 8×12KB 上行零失配）。**两个新缺陷**（app 统计字恒 0、RX 停顿钩子无效）已登记；
**OCC A/B 因停读钩子无效而【未执行】**；**0x37（CDC+OCC=1）构建在飞，路由严重拥塞（中间 WNS −1.03）**。

## 1. 第三轮独立审查（V4-01…V4-27）与 v5 处置

- 裁定：**v4 未闭合**（阻断 1 / 高 6 / 中 9 / 低 11）。
- 阻断 V4-01 = **§3 文字写反**（RTL 本已把 `dbg_inst_mismatch` 接进 W97[15:8]）。
- 处置：`DESIGN.md` 升 **v5**，新增 **§11** 逐条处置表（27/27 有落点）+ §11.1 实施回写 + §11.2 未闭合；
  `REVIEW.md` 加 §7 并就地订正 M9（`RX_IDLE`）等。
- 关键改字：变异 9 期望改"必须红"；M8 断言移到 core 侧并用显式 prev（不用 `$stable`）；
  0x36 配方补 `P11_CFG=c4`；W97[31:21] 改"活动性见证"（残留长度未测）；[15:8] 改 per-slot/delta；
  [4] 生成规则与"帧"定义写死；几何门三处列入清单；stat hold 白名单逐项。

## 2. 实施与门

- 新 RTL：`rtl/app_clk_gen.v`（第二 MMCM 156.25 MHz）、`rtl/app_multi8_cdc.v`（4×异步 FIFO +
  stats hold/toggle + W97）；`app_multi8.v` LED 宽度修正；`board/wrapper_p4.v` CDC 分支（含 V4-07
  P8 镜像 DP 侧修复）；`board/build_p7b_ku5p.tcl` env 门/导入/XDC/`top_hi=53`/模块门；
  `board/ku5p_p7b_app8_cdc.xdc`。
- 门：`tb_app_multi8_cdc` **PASS**（两种时钟比：6.23/6.4 与 6.4/6.4）；C4 全链 elaborate **PASS**；
  `check_cdc_wiring.py` 19 项 **PASS**；`check_build_0x36.py` 构建后机械门 **PASS**。

## 3. 构建

- **0x36 #1 作废**（`build_fail1_0x36/`）：CDC XDC 用源码级 `u_*/u_mmcm/CLKOUT0`，综合后 MMCM 在
  generate 块里 ⇒ 12-508/12-4739、两条 false_path 被丢弃。`sta/query_mmcm.tcl` 从 synth DCP 实测
  真名（`u_appclkgen/g_real.u_mmcm/CLKOUT0` / `u_clkgen/g_hw.u_mmcm/CLKOUT0`）后改正。
- **0x36 #2 PASS**（`build_ok_0x36/`）：**WNS +0.017 / WHS +0.010 / 0/0/0**；app 自域 +0.39；
  dp↔app = False Path（双向，8427/431 路径）；无 12-4739；LUTRAM +708、FF +1,081；
  位流 `d80bdb28…9adde9`（15,431,261 B）。
- **0x37（CDC+OCC=1）**：BID 0x37；综合后门过（`SLOTS_OK=15`、`P11_STA_WPM_REL_WNS=1.930`）；
  实现**拥塞级 5**（`Route 35-448`/`35-443`，路由 ~60 min）⇒ **最终 TIMING_FAIL**：
  **WNS −0.629 / WHS +0.010**；最差 `u_tcp_tx2/u_fifo_b/rptr_reg[6] → u_app2/stg_reg[9]/D`
  （DP 域、port1 app 暂存路径 = **OCC=1 的占用/tready 逻辑**，不是 CDC 的 dp↔app）；
  资源 +2,264 LUT / +888 FF（vs 0x36）。位流 `.TIMING_FAIL` **禁烧**；报告归档 `build_fail2_0x37/`。
  **本轮不做 L-5 重试**（gap 0.63 ns + 拥塞级 5 + 75 min 构建 + OCC A/B 已被 §0-81 阻断）；
  下一轮作为新输入（Spread 策略或 OCC 侧面积/布局改动）。

## 4. 板级（0x36）

- 烧录：JTAG 1 MHz，HIGH；QSPI 零写；上板前板在 QSPI 厂商态 ⇒ **根端口 remove+rescan**（场景 C）恢复 2 BAR。
- 身份：MAGIC/BID 0x36/MARKER/UNIMPL 0x1B8/98 字 NFF=0/MIR 0x1A8..0x1B4。
- **W97 = 0x20**：locked_app=1、无 drop/stale/超时/复位、per-slot mismatch=0。
- 数据面：
  - `p7b_tcp_sink` **100 连接 × ~1 MiB = 107,052,876 B，mismatch=0、stall=0**；
  - 8 连接 `seq`：8/8 status=0、mism=0、stall=0（`got>maxbytes` 是工具 64K 块过冲）；
  - 上行 8×12,288 B（unsent=0）⇒ **W97[15:8]=0**（app 域直连粘滞）= 上行零失配。
- **新缺陷 ①（观测面，未定位）**：W51–W54/W71–W74 恒 0 —— 流量中/后均如此，W97 干净、
  内容全过；网表事实已记（st_hold/st_shadow 时钟与 CE、计数器 CE=`pw_take`）；
  ⇒ 这些字**不得用作判据**直至修复（`P7B_OPEN_ITEMS §0-80`）。
- **新缺陷 ②（OCC A/B 阻断）**：`0x08 bit2` RX 停顿钩子无效 —— 置位后单连接 512 KB `unsent=0`、
  窗口恒 12288、W62（触发快照）=0 ⇒ OCC A/B 前件不可达 ⇒ **按 §6.6 记【未执行/空判据】**，
  不记 PASS/FAIL（`§0-81`）。

## 5. 未闭合（不许当已完成）

1. H4 真 wrapper 全链门未写（DESIGN §11.2）。
2. 几何文本门/读侧工具未同步 0x36（`check_snap_top5_wired.py` / `check_window.py` /
   `apply_readside_bid1c.py`）；矩阵 42/43/44 未注册。
3. app 统计字恒 0（未定位，需 ILA/新仪器）。
4. RX 停顿钩子无效（OCC A/B 阻断，未定位）。
5. 0x37 构建结果（拥塞/时序）待定；OCC A/B 未做。
6. 板现态 = 0x36（若 0x37 未烧）。

## 6. 原件索引

`DESIGN.md`（v5 §11）· `REVIEW.md`（§7）· `BOARD_0X36_REPORT.md` · `build_ok_0x36/` ·
`build_fail1_0x36/` · `bits/` · `burn/` · `raw/` · `tb/` · `compile/` · `sta/`（MMCM/统计网表查询）·
`check_build_0x36.py` · `check_cdc_wiring.py` · `decode_w97.py` · `occ_win.py` ·
`run_build_0x36.bat` / `run_build_0x37.bat` · `burn_0x36_board.sh` / `burn_0x37_board.sh` ·
`b0_env_setup_0x36.sh` · `b1_func_0x36.sh` / `b1_func_0x37.sh` · `b2_occ_ab.sh` / `occ_*.sh`
