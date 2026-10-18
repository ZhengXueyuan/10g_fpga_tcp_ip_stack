# P11（双 SFP+）· kimi 审查回灌 review-fix 轮 —— FIX_REPORT

- 日期：2026-10-18（本会话）
- 仓库根：`D:\repo\XCKU5PMini\udp_hls_10g`；**HEAD at matrix start = `98fa8e1c`**（矩阵结束时 HEAD 变为 `da70b2ac` —— 外部提交 README，非本轮改动；内容指纹 FROZEN，见 §3）
- 输入：kimi 合并审查 = 台账 §10-141/§10-142/§10-143；上一轮报告 = `_proj_10g/notes/p11_p2a_fix_20261018/FIX_REPORT.md`
- 纪律：**未跑 Vivado 构建/综合/实现；未烧板；未碰 QSPI；未改 `D:\repo\perfv`；未做任何 git 写操作**。xsim 门全部在本轮重跑并归档（`gates/`）。**`board/wrapper_p4.v` 的 `.TO_CYCLES` 值一行未改**（TB 见 §1-1）。
- 本报告**不下 PASS/FAIL 裁定**；门/脚本的 PASS 字样是它们自身的输出。纸面数字标"纸面"。「未观测到」≠「不存在」。

## 0. 一句话

kimi 的 6 组待修项 + 低 8 文档项**全部处置**：F-4 两侧对称删除、F-2 附录 E 残句改正、K-1 接常量、中 1（G4 RAMB 碰撞）**逐例判定为良性**并统一 G2/G3/G4/G6 的模拟器错误硬门（含 3 条负控）、低 8 逐条订正/补负控、0x2C 收集器改为只扫 synth 日志（重跑 `black box = 0 / 8-3491 = 0`）。**24 门矩阵一次跑完 = 24/24 EXIT=0 · gates failed 0 · FROZEN（341 文件）**。

---

## 1. 逐项处置

### 1-1 F-4 对称性（ch1 `ΔW45(字)` 与 ch0 `sat16(ovf)` 同语义 ⇒ 同删）

- **改动**：`_proj_10g/notes/p11_p2a_design_20261018/DESIGN_v2r1.md` §5.1 **P2-2**：
  - ch1 对账式由 `… ≤ ΔW45(字) + ΔW21(帧) + INFLIGHT_MAX_FRAMES` 改为 **`… ≤ ΔW21(帧) + INFLIGHT_MAX_FRAMES`**；
  - 就地加 **【v2.1-errata F-4】**：`u_txcdc.ovf_cnt` 与 W86 同语义 = **AXIS 反压拍数**（`fifo_async.ovf_pulse = wr_en && full`，生产者保持 tvalid ⇒ 字下拍重试、不丢），不是丢字数、且会饱和 ⇒ 原式是恒真的松上界；ch1 丢帧由 MAC `stat_abort`（W21）计。
  - 同页 **P2-4** 的"`ch0_rxcdc_ovf`（W86 高半）…应恒 0（安全网）"残句加 **【v2.1-errata F-4/D-1】** 指针（W86 = 反压拍数，只作健康指示，不作丢帧判据）。
  - 顺带在 H-8 / N-7 两条"历史发现"行上加同一条 errata 指针（不重写原文）；§N.1 表相应行改为"**两侧字级修正项同删**（ch0 用 W82 MAC drop / ch1 用 W21 MAC abort）"。
- **证据**：`DESIGN_v2r1.md:718`（P2-2，现行式）、`:720`（P2-4 指针）、`:31`/`:102`（H-8/N-7 指针）、`:121`（§N.1）。
- **OPEN_ITEMS**：`§0-69` 标 **"用户已确认（2026-10-18）"**；`§0-68` 按用户裁定写 **最终值 4096（0xFFFF 已否）**，理由 = 4096 已是最大帧 21.5×、0xFFFF 只放大停钟黑窗 16×；并注明 **wrapper 那一行由 TL 收口后统一改，本轮未改**。
- ⛔ **未改** `board/wrapper_p4.v:1188` 的 `.TO_CYCLES(16'hFFFF)`（核到现读仍是 `16'hFFFF`；TL 将改为 `4096`）。

### 1-2 F-2 附录 E 残句（`DESIGN_v2r1:972`）

- **改动**：原句"单域/非 DP 构建不例化 merge，不适用"与源码不符，已改为：
  "**merge 例化只受 `DUAL_SFP_A` 门控** —— `DUAL_SFP_A ∧ ¬DP_156MHZ` 被 `DUAL_SFP_A_REQUIRES_DP_156MHZ` 硬门拒绝（`board/wrapper_p4.v:310`，模块名故意不存在 ⇒ xelab 失败）、不在构建矩阵 ⇒ `RESYNC_EN=1` 前提在本构建集合内成立"。
- **源码核对**：`rx_merge2 u_rx_merge` 例化在 `board/wrapper_p4.v:1188` 的 `ifdef DUAL_SFP_A` 块内；`:310` 的硬门实例在 `ifdef DUAL_SFP_A` + `ifndef DP_156MHZ` 内。
- **门级证据**：G7 本轮 c11 = **EXPECTED-FAIL**，签名 `VRFC 10-2063 Module <DUAL_SFP_A_REQUIRES_DP_156MHZ> not found … [board/wrapper_p4.v:310]`（`gates/g7_elab_run.log`）。

### 1-3 K-1（`tb/tb_udp_tx_guard.v` 漏接 `peer_my_ip`）

- **改动**：`tb/tb_udp_tx_guard.v:183` 的 `udp_tx_cfg u_cfg` 补 `.peer_my_ip(32'h0)`（`PER_CONN_SRC_IP=0` 默认下不参与 mux，语义不变）。
- **同族核对**：其余 active 例化点均已接常量（`tb/tb_app_udp.v:316`、`tb/tb_app_udp_rate.v:165`）⇒ K-1 点确为唯一缺口。
- **门读数**：`P5E-T2 GUARD GATE: OK (frames=6 drop_len=2 deny=2 neg_fifo_occ=256 neg_sready=0)`，RC=0（14:48:48 起跑；`gates/tb_udp_tx_guard_console.log` + `tb_udp_tx_guard_{xvlog,xelab,xsim}.log`）。

### 1-4 中 1：G4 的 RAMB 碰撞逐例判定 + 统一硬门

**核到与派单描述不符（如实说）**：派单写"G4 的 **10 条** `RAMB36E1 Memory Collision`"；归档 `g4_xsim_slowport.log` 实际是 **9 条** —— `tb_slow_tx_port.u_dut.u_wf` **8 条** + `u_small.u_wf` **1 条**。G4 的 9 条 + G6 的 1 条（`RAMB36E2-11`，`u_slow_rx.u_ff`）= 10。以下按实际 9 条逐例判定。

**代码级依据（`rtl/frame_fifo.v`，不是"同模块"三个字）**：
1. `bypass = wr_ok && (rptr_n[AW-1:0] == wptr[AW-1:0])` —— 这是 frame_fifo 中**唯一**让 RAM 写地址与读捕获地址同址的条件（空推入 / 深度 1 pop+push）。读捕获地址是 `r_ad = rptr_n`，写地址是 `w_ad = wptr`。
2. 同址拍 = 主存 WRITE_FIRST 碰撞：写**成功**、DOA 该拍未知（unisim `RAMB36E1.v:3286-3287` 的 `wr_mode_a != 2'b01` 分支原文 "The write will be successful however the read value on port A is unknown until the next CLKA cycle"）。
3. 该未知 DOA **被 `bypass_r`/`din_r` 掩掉**：`bypass_r(N+1)=bypass(N)=1` ⇒ 下拍 `dout = din_r`（全 W 位，含 tkeep/tlast），DOA 永不漏出；非 bypass 拍写址 ≠ 读址（构造上无碰撞）。
4. unisim 模型判碰撞用的是 `addra_reg`（上一拍 A 地址）vs 当前 `ADDRB`（`RAMB36E1.v:4464` 的 `task_col_wr_ram_a(..., ADDRB, addra_reg)`），在"读地址连续两拍不变"的 bypass 稳态下与实际同址拍对齐；打印的地址 = 当前写地址。

**逐例实证（本轮新增 TB 旁路监视器，`-testplusarg BYPDBG`）**：
- 在 `tb_slow_tx_port.v` 对两个 `frame_fifo` 实例的 `bypass` 计数并逐事件打印 `$time/wptr/rptr`；每例 `wptr == rptr`（同址），且**每例碰撞消息时刻与该实例的 bypass 事件一一对应**（差 ≤0.4 ns = TB timescale 1 ns 量化）：

| # | 实例 | bypass 事件 t（TB） | 碰撞消息 t（ns） | 同址（wptr==rptr） |
|---|---|---|---|---|
| 1 | u_dut.u_wf | 182000 ps | 182.400 | 0 |
| 2 | u_dut.u_wf | 726000 | 726.400 | 8 |
| 3 | u_dut.u_wf | 1270000 | 1270.400 | 16 |
| 4 | u_dut.u_wf | 1814000 | 1814.400 | 24 |
| 5 | u_dut.u_wf | 2358000 | 2358.400 | 32 |
| 6 | u_dut.u_wf | 2902000 | 2902.400 | 40 |
| 7 | u_dut.u_wf | 3446000 | 3446.400 | 48 |
| 8 | u_dut.u_wf | 3990000 | 3990.400 | 56 |
| 9 | u_small.u_wf | 36413000 | 36412.800 | 0 |

- **计数 1:1**：`BYPASS_COUNT u_dut.u_wf=8 u_small.u_wf=1` = 碰撞 8 + 1。
- **行为面**：G4 TB 全部断言 PASS（含 F 臂 60 帧逐帧 `o_port`、G 臂侧 FIFO 溢出负控）；矩阵 `unit_fifo` 门（`sim/retxsim2/run_tb_frame_fifo.bat`）同轮 `PASS_ALL frame_fifo unit: writes A=568139 B=595715 C=616302 pops A=567224 B=591216 C=611802 cycles=750700`（该 TB 的 (a)/(b) 阶段就是空写 bypass 与深度 1 bypass 链，逐字节 pops 判据）。
- **判定**：G4 的 9 条 = **frame_fifo SDP bypass 同址碰撞，良性**；依据 = 唯一同址条件 + 写成功 + DOA 被 bypass 掩掉 + 逐例时刻/地址/计数 1:1 + 行为判据全过。**不是真缺陷 ⇒ 不改 RTL、不改 TB 激励。**

**统一硬门（G2/G3/G4/G6）**：
- 新增 `_proj_10g/p11_dual/sim/scan_xsim_errors.py`：扫 `Error:` / `Critical`（大小写不敏感）/ `Memory Collision` / `Address Overlap` / `Unisim`；白名单按 gate 显式给实例与语义分支（G4 只允许上述两个 `u_wf` 的 RAMB36E1 "read A vs write B same address"；G6 只允许 `u_slow_rx.u_ff` 的 `RAMB36E2-11` 且必须带 `A simultaneous WRITE … READ` 续行）；其它任何命中 = RC=1。
- 四个 bat 已接入：G2/G3 = `--mode none`；G4 = `--mode slowport`；G6 = `--mode p11dual`（替换 G6 原有 bespoke 检查）。
- **负控（扫描器有牙）**：合成 `Error:` 行（mode none）、非白名单实例的 E1 碰撞（mode slowport）、非白名单实例的 E2 碰撞（mode p11dual）⇒ 三个 RC 全 = 1（`gates/scan_selftest_run.log`）。
- **门读数（本轮重跑）**：G2 `XSIM_ERROR_SCAN … mode=none allowed=0 violations=0` / G3 同 / G4 `mode=slowport allowed=9 violations=0` / G6 `mode=p11dual allowed=1 violations=0` —— 四门全 RC=0，TB PASS 行不变。

### 1-5 低 8（文档/门）—— 逐条

① **§4 指纹方向写反（已订正）**：以 `sim/p4sim/P4_MATRIX_FINGERPRINT_20261018_111917_before.txt` 现核 —— `_proj_10g/p11_dual/sim/tb_tx_split.v` **在指纹内**（修改清单 + SHA256 各 1 行），`mk_mut_srcip.py`、`run_tb_*.bat` 也在内；**不在**指纹内的只有 `tb/tb_app_udp.v`（顶层 `tb\` 不在 globs）、本轮新增的 `scan_xsim_errors.py`、`board/build_p7b_ku5p.tcl` 与 `board/run_build_p7b_ku5p.bat`。订正文本 = `p11_p2a_fix_20261018/FIX_REPORT.md` §8-1（v1.1 订正段，不改原文）。
② **§2/§3 两处时刻矛盾（已订正）**：F-1 的 `11:37:40` 是小时笔误，`f1_assert_2c.log` mtime = **10:37:40**（§3 的 10:37 正确）；G6 行把 `g6_run.log`（mtime 11:05:54）与 `g6_xsim_p11dual.log`（mtime 11:06:31）并成一行只给一个时刻 —— 两者都对、指向不同文件。订正 = 同 §8-2。
③ **`f6_f20_static_lines.txt` 陈旧引文（已从当前文件重取）**：旧件引自 ASCII 清理前的 bat（模块检查无 `/B`、行号 63–81）；已按**当前树**重新生成（tcl 36–470 / bat 63–87，含 `/B` 模块检查与 F-21 的 `P7B_SNAP_TOP5_*` 硬门）。改动落点 = 该文件本身（新增"REGENERATED 2026-10-18"头注）。
④ **`g5_run.log` 的 4 处"幽灵命令"（已披露）**：原因 = 中间版 bat 的 REM 行中文/emoji 在 cmd OEM(GBK) 代码页被拆包执行（§6.5 同族）；时间序与"不影响判决"的理由 = FIX_REPORT §8-4。本轮 ASCII 化后重跑同一门：该族 **0 命中**（`grep -c '不是内部或外部命令' g5_run.log` = 0）；归档旧件保留作实证。
⑤ **F-17 "逐字节相同"降级**：降为"**归一化后 diff 为空**"（`f17_hls_baseline.txt` 自己的小节名就是 `diff vs base_out (normalized)`）；worktree `D:/repo/XCKU5PMini/_p11_wt_2c` **已删除** ⇒ **无法复验逐字节相同**，只剩源/二进制 sha256 与失败行集合可复核。结论方向（3 条失败既有）不变。落点 = §8-5。
⑥ **`$isunknown` 术语（已订正）**：实现为本地函数 **`is_xz1`**（`(v!==0)&&(v!==1)`，Verilog-2001 下 `$isunknown` 不可用）。已改/加注：`DESIGN_v2r1.md` §N.1 表、§3.x 断言行、§5.2 G1 行、附录 E D-5。`FINDINGS.md` 是历史审查件、其"建议修法"里的 `$isunknown` 按原文保留（实现按 `is_xz1`）。
⑦ **G7/G8 门编号（已统一）**：以设计件 §5.2 为准 = **G7 = elaboration 13 组合、G8 = HLS 双 IP**。上一轮报告把 P5E `tb_app_udp` 门叫成 `G7(tb_app_udp)`/`G8(tb_app_udp)`，已在 §8-7 订正为"P5E `tb_app_udp` 门（非 G8）"；**G8 本轮未跑**（纪律禁止 HLS 重构/构建）。
  - **附带发现（必须登记）**：`_proj_10g/p7b_chain/sim/elab_gate_out.txt` 是一份 **08:52 的陈旧件**（内容为 12 组合、c8 不含 `SFP2_MODE_A`），**当前 bat 不再写这个文件**；权威输出 = stdout/矩阵日志（本轮 13 组合、c8 含 `SFP2_MODE_A`、c13 = DUAL 无 `SFP2_MODE_A`）。引用 G7 时**不得**引用 `elab_gate_out.txt`。
⑧ **F-7 X/Z 运行期断言负控（已补，有牙）**：`tb/tb_app_udp.v` 新增 `-testplusarg XZNEG`：复位后 200 拍 `force u_cfg.o_port = 1'bz` 保持 10 拍。
  - 负控跑：`[NEGCTL] F-7: forcing u_cfg.o_port = 1'bz` → `[FAIL] P11 H-1: X/Z on u_cfg.o_port or u_cfg.cfg_sync` → 末行 `P5E UDP APP GATE: FAIL errs=10`；`run_tb_app_udp.bat xzneg` 打印 `XZNEG_NEGCTL_OK -- runtime X/Z assertion fired and gate went RED`，**RC=0（期望红）**。
  - 正臂同轮复跑：`P5E UDP APP GATE: OK (rx_frames=10 rx_bytes=13305 tx_frames=25 drop_len=1 drop_ovf=5 split=15 pat_bad=0)`。
  - 证据 = `gates/app_udp_{pos,xzneg}_console.log` + `app_udp_{pos,xzneg}_xsim.log`。

### 1-6 0x2C 收集器（`black box` / `8-3491` 假阳性）

- **改动**：`_proj_10g/notes/p11_build_0x2C_20261018/build/_collect_build_0x2C.py` 的 "hard gate hits" 段改为**只扫 `synth_1/runme.log`**（存在时）；该文件不存在时回退为"扫 board stdout 但排除以 `#` 开头的行（source echo excluded）"，并在输出里写明数据源。
- **重跑（0x2C 归档 stdout）**：数据源 = `synth_1/runme.log`；输出 **`black box = 0` / `8-3491 = 0`**（其余 6 键也全 0）。原 `black box=1 / 8-3491=1` 确系 `board/p7b_ku5p_stdout.txt:3683` 的 Tcl 源码回显行。
- 证据 = `gates/collect_0x2C_rerun_console.txt` + `gates/READINGS_BID2C_after_collector_fix.txt`；0x2C 位流 sha256 重算 = `e92f588b…d6be`（15,431,261 B，`SW_CRC=ccd5f297`）与归档一致。

---

## 2. 回归门读数（独有串 + 起跑时刻；原件在 `gates/`）

| 门 | 独有串 | xsim 起跑 | 结果 |
|---|---|---|---|
| G2 `rx_merge2` | `XSIM_ERROR_SCAN … mode=none allowed=0 violations=0` + `RX_MERGE2 TB PASS` | 14:48:56 | RC=0 |
| G3 `tx_split` | `XSIM_ERROR_SCAN … mode=none allowed=0 violations=0` + `TX_SPLIT TB PASS` / `TX_SPLIT_GATE_PASS` | 14:49:02 | RC=0 |
| G4 `slow_tx_port`（含 BYPDBG 臂） | `XSIM_ERROR_SCAN … mode=slowport allowed=9 violations=0` + `XSIM_BENIGN_E1_RAMB36E1 count=9` + `BYPASS_COUNT u_dut.u_wf=8 u_small.u_wf=1` + `SLOW_TX_PORT TB PASS` | 14:53:45（bypdbg 14:53:37） | RC=0 |
| G5 `tcp_tx_srcip` | `SRCIP ovl OK` / `def OK` / `mut EXPECTED-FAIL OK` / `mutn6 EXPECTED-FAIL OK` / `SRCIP_GATE_PASS` | —（bat 14:50:38） | RC=0 |
| G6 `p11_dual` | `XSIM_ERROR_SCAN … mode=p11dual allowed=1 violations=0` + `XSIM_BENIGN_E2_RAMB36E2 count=1 at u_slow_rx.u_ff` + `P11_DUAL TB PASS` | 14:49:33 | RC=0 |
| G7 elab | 13 组合（c1–c8/c13 OK；c6/c7/c9–c12 EXPECTED-FAIL 且签名命中）+ `ELAB STRICT count_0=1 count_1=0` + `DECLCHECK_EXIT=0` + `ELAB_COMBO_FAILS=0` + `ELAB_4COMBO_PASS` | 14:52:30 | RC=0 |
| K-1 `tb_udp_tx_guard` | `P5E-T2 GUARD GATE: OK (frames=6 drop_len=2 deny=2 neg_fifo_occ=256 neg_sready=0)` | 14:48:46 | RC=0 |
| P5E `tb_app_udp` pos | `P5E UDP APP GATE: OK (rx_frames=10 … pat_bad=0)` | 14:48:25 | RC=0 |
| P5E `tb_app_udp` **xzneg 负控** | `[FAIL] P11 H-1: X/Z …` + `P5E UDP APP GATE: FAIL errs=10` + `XZNEG_NEGCTL_OK` | 14:48:35 | RC=0（期望红） |
| 读侧 `--assert` 0x2D | `APPLY_READSIDE_BID OK (target 0x0000002D, 0 阶段 / 0 处 edit, 0 fail)` + `EDIT_COVERAGE 15/15` | 14:52:41 | RC=0 |
| 扫描器负控 ×3 | `SCAN_NEGCTL_BAD_OK` / `SCAN_NEGCTL_WRONGINST_OK` / `SCAN_NEGCTL_E2WRONG_OK`（均 rc=1） | 14:53:19 | 有牙 |
| 0x2C 收集器重跑 | `black box = 0` / `8-3491 = 0`（source = `synth_1/runme.log`） | 14:47:41 | RC=0 |

## 3. 24 门常驻矩阵（一次跑完，不凑 24/24）

- 起止：**2026/10/18 14:54:08 → 15:24:15**；`gates run : 24 / 24`；**`gates failed: 0`**；矩阵日志逐门 `EXIT=0`（24/24）。
- `VERDICT: FROZEN -- all 341 hashed files byte-identical across the run`；内容口径 `DIGEST_ALL(content)=84c9a337b23892e97443a3a9b7fcd6530e52bce02f1fd9396c599a0ed5609780`。
- 指纹修改清单（tracked）恰 5 件 = `run_tb_p11_dual.bat` / `run_tb_rx_merge2.bat` / `run_tb_slow_tx_port.bat` / `run_tb_tx_split.bat` / `tb_slow_tx_port.v`（BEFORE/AFTER 的 `DIGEST_*` 相同）。
- G2/G6 的新硬门在矩阵内确有读数：`XSIM_ERROR_SCAN … mode=none`（G2）、`… mode=p11dual allowed=1`（G6）；`unit_fifo` = `PASS_ALL frame_fifo unit …`。
- ⚠️ **HEAD 在矩阵期间由 `98fa8e1c` 变为 `da70b2ac`**（外部提交 README；非本轮改动）。内容指纹 FROZEN ⇒ 门结果仍绑定同一内容；但"HEAD 号"引用须按 BEFORE/AFTER 两个值写。
- 归档：`gates/matrix_p4dfix.log`（权威，24 门逐条）+ `gates/matrix_run.log`（stdout 摘要）+ `gates/fingerprint_{before,after}.txt`。

## 4. 未测 / 残余（不许当已收口）

1. **0x2D 构建/综合/实现/时序/资源/布后门正读数**：本轮未跑（纪律禁止）；`TO_CYCLES` 的 wrapper 值仍 = `16'hFFFF`，**TL 将在收口后改为 `4096` 再构建**。
2. **板级 W83..W87 相干性、`TO_CYCLES` 触发、F-14 板级**：未测。
3. **`scan_xsim_errors.py` 不在矩阵指纹 globs 内**（`_proj_10g/p11_dual/sim` 只哈希 `run_*.bat` / `tb_*.v` / `mk_mut_srcip.py`）⇒ 本轮的"矩阵绑定内容"不含这个新扫描器；建议下一轮把它加入 `paths.txt` 的 `FINGERPRINT_GLOBS`。
4. **以下文件不在矩阵指纹内**（globs 只覆盖 `sim\p4sim` / `sim\p5sim` / 若干指定 sim 目录与 `_proj_10g\p11_dual\sim` 的 `run_*.bat`、`tb_*.v`、`mk_mut_srcip.py`）：`tb/tb_app_udp.v`、`sim/p5e_udp/run_tb_app_udp.bat`、`tb/tb_udp_tx_guard.v`、`sim/p5e_t2/run_tb_udp_tx_guard.bat`、`_proj_10g/p11_dual/sim/scan_xsim_errors.py` ⇒ 它们的本轮改动由本报告的独立门读数绑定（G2/G3/G4/G6/G5 与 K-1/P5E 各门），**不在 FROZEN 的内容证明范围内**。矩阵内的 P11 门只有 G2/G5/G6 三条。
5. **`elab_gate_out.txt` 是陈旧件**（08:52 / 12 组合），当前 bat 不写它；引用 G7 必须用 stdout/矩阵日志。
6. G4 的 9 条 RAMB 碰撞判定是"良性"（逐例证据见 §1-4），**不是"没有观测到"**；但本判定只覆盖当前 G4 的两个 `frame_fifo` 实例。
7. 扫描器的白名单是"按实例 + 语义分支"的；若未来 G4/G6 新增 `frame_fifo` 实例并产生同类碰撞，门会**红**（需重新逐例判定）——这是有意行为。

## 5. 证据索引（`_proj_10g/notes/p11_reviewfix_20261018/gates/`）

`g2_{console,xvlog,xelab,xsim_run}.log` · `g3_{console,xvlog,xelab,xsim_split}.log` · `g4_{console,bypdbg_console,xvlog,xelab,xsim_slowport,xsim_bypdbg}.log` · `g5_{console,run_reviewfix}.log` · `g6_{console,xvlog,xelab,xsim_p11dual}.log` · `g7_{console,elab_run}.log` · `tb_udp_tx_guard_{console,xvlog,xelab,xsim}.log` · `app_udp_{pos,xzneg}_console.log` + `app_udp_{pos,xzneg}_xsim.log` · `readside_assert_0x2D.log` · `collect_0x2C_rerun_console.txt` + `READINGS_BID2C_after_collector_fix.txt` · `scan_selftest_*.log` · `matrix_p4dfix.log` / `matrix_run.log` / `fingerprint_{before,after}.txt`。

> 若本报告未能落盘（平台拒写），全文以最终回复原文为准；上面列出的门日志均已归档在磁盘。
