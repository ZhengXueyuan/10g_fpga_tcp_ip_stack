# P11（双 SFP+）· P2-甲 实施修复轮 —— FIX_REPORT

- 日期：2026-10-18（本会话）
- 权威清单：`_proj_10g/notes/p11_review_p2a_impl_20261018/FINDINGS.md`（F-1..F-20 + D-1..D-13）
- 施工依据：`_proj_10g/notes/p11_p2a_design_20261018/DESIGN_v2r1.md`（本轮追加 §N.1 errata 指针表 + **附录 E**）
- 纪律：**未跑 Vivado 构建/综合/实现；未上板；未碰 QSPI；未提交 git**。xsim/HLS-csim 门全部在本轮跑过并归档（`gates/`）。
- 本报告**不下 PASS/FAIL 裁定**；门/脚本的 PASS 字样是它们自身的输出。纸面数字标“纸面”。「未观测到」≠「不存在」。

## 0. 一句话

FINDINGS 的 20 条 F + 13 条 D **全部处置**（19 修 / 1 条设计修订项 F-2 实现并**待用户追认**；D-13 的旧 bat 原文不可复原，按错误签名反推登记）。读侧 0x2C 链补全到 **20 文件**并改成**可重放的显式增量**（从 0x2B 树重放 = 现磁盘 **20/20 逐字节相同**）。门全部重跑：G2/G3/G4/G5/G6/G7(`tb_app_udp`)/elab 13 组合通过；**24 门常驻矩阵 24/24 EXIT=0 · gates failed 0 · FROZEN（340 文件，含 `board/wrapper_p4.v` + 两个新 RTL）**。HLS 基线由**改前树 worktree@1c3cc7da** 三臂 csim 复现，与 `base_out.txt` **逐字节相同** ⇒ 3 条失败确属既有。

## 1. 改动清单

### 1.1 RTL（3 文件）

| 文件 | 改动 | 来源 |
|---|---|---|
| `rtl/rx_merge2.v` | 新增 `parameter TO_CYCLES=0` + `output stat_abort`；`busy && !sel_tvalid` 连续 ≥TO_CYCLES ⇒ 释放 busy、`stat_abort+1`、不计帧；默认 0 = 常量折叠 | F-2 |
| `rtl/slow_tx_adp.v` | 源 IP/ARP SPA/VLAN 提取寄存器与更新块**整体进 `generate if (PER_PORT)`**；`PER_PORT=0` 支 `ext_side_push=1'b0`（零寄存器） | F-11 |
| `board/wrapper_p4.v` | ① `u_rx_merge` 传 `.TO_CYCLES(4096)`、接 `stat_abort()`；② 复位由 `dp_rst_n` 改板级 **`reset_n`**（与两路 FIFO rd 侧同源）；③ `rx_p0_tvalid` 声明移出 `ifdef DUAL_SFP_A`；④ `tx_p0_frames/tx_p1_frames` 声明移到**所有 ifdef 之外**；⑤ `maccnt_sync` 两实例 `src_tick` 改源域 **8 位 rollover**（每 256 拍） | F-2/F-8/F-18/F-19 |

### 1.2 门 / 测试台（7 文件）

- `_proj_10g/p11_dual/sim/tb_rx_merge2.v`：新增**臂 G**（TO_CYCLES=16 的第三实例；p1 4 拍无 tlast ⇒ `stat_abort>0`、半帧不计、p0 两帧仍出）。
- `_proj_10g/p11_dual/sim/tb_p11_dual.v`：臂 C 改 **斜坡追踪**（精确值 1..4 / 冻结 120 拍不变 / `dst` 强制常 0 变异必红），保留裸 2FF 负控；新增**臂 D**（真 wrapper 的 `u_udp_tx_cfg`：`peer_my_ip=IP_B ⇒ o_src_ip=IP_B/o_port=1`，IP_A 反向）。
- `_proj_10g/p11_dual/sim/tb_tx_split.v`：臂 D 改为**第二份 `tx_demux2` 交叉接线**的真变异（同一判据必红）。
- `tb/tb_app_udp.v`：加运行期 X/Z 断言（`is_xz1(u_cfg.o_port/cfg_sync)`；Verilog-2001 下 `$isunknown` 不可用 ⇒ 用 `(v!==0)&&(v!==1)`）。
- `_proj_10g/p11_dual/sim/mk_mut_srcip.py`：新增 `--n6` 模式（默认体 `csum_sip=lip_r`，**两处锚都替换**并打印 hits=2）。
- `_proj_10g/p11_dual/sim/run_tb_p11_dual.bat`：DEFS 加 `-d SFP2_MODE_A`；加 `peer_my_ip`+`VRFC 10-3645` 定向断言；加 `Error:/Critical/Unisim` 硬门（唯一允许 = 文档化的 `RAMB36E2-11 @ u_slow_rx.u_ff`）。
- `_proj_10g/p11_dual/sim/run_tb_tcp_tx_srcip.bat`：四臂（OVL / 默认体 / 全量变异 / **N-6 精确变异**）；变异臂选择改 `USEMUT`（`mut`+`mutn6`）；加 `peer_my_ip` 定向断言。
- `_proj_10g/p7b_chain/sim/run_elab_4combo.bat`：c8 改**真 9 宏组合（含 SFP2_MODE_A）**、新增 **c13**（DUAL 无 SFP2_MODE_A 正控）；加 `.STRICT` 静态断言与 **F-8 DECLCHECK**；**每组合私有 cwd/library + 私有 glbl**（否则 xvlog 在 c2 挂起，见 §6.4）。
- 新增 `_proj_10g/p7b_chain/sim/check_decl_outside_ifdef.py`（F-8 结构性自检）。

### 1.3 读侧 / 构建脚本

- 读侧 20 文件：`j6_r6fix.sh`/`tcpreg_j6.sh` 的 **GEOM_TIERS 顶端加 `88|0x0000002C`**（保留 83 档）；`p7b_gate4_accept.sh`（0x2C / 88 / UNIMPL 0x190 / B_CH0 阈值 88）；`p7b_gate4_selftest.sh`（SW=88、FAKE_BID=0x2C、新增 88 档 FAKE_TAIL 至 0x190）；`p7b_gate4_livefake.sh`（bid 字典 88 + 兜底 0x2C、W 表 37）；`p7b_gate4_negctrl.sh`（BID 0x2C、`i<88`、几何自述）；`p7b_gate4_3/final_state.sh`（0x2C / rd 0x190）；`p7b_gate4_criteria/gen_inputs.py`（NW_FIX=88 / BID_FIX=0x2C / 几何自述）；`p6e_snap_selftest_fix2.sh`；`tb_p7b_chain.v`（标签改回 `7b 0x190`）；`tb_p6e_pcie_{counters,wrapper}.v`；两个 biz_win 脚本；`apply_readside_bid1c.py`（**显式 EDITS_2C 43 处 / 20 文件** + `LF_AFTER_2C` 6 文件 + 两条 ALLOW 登记）。
- `board/build_p7b_ku5p.tcl`：`HLS_SRC_HASH`/`HLS_NET_HASH`（逐文件 + 合并 sha256，PowerShell Get-FileHash）、synth 日志 `black box|8-3491` **0 命中硬门**、`P7B_VERDICT = OK` 终判、位流缺失 = `BITSTREAM_MISSING`。
- `board/run_build_p7b_ku5p.bat`：rc 捕获 + `TRIP` 双判据（`P7B_VERDICT=OK` 必须出现；`SYNTH_FAIL`/`HLS_HASH_FAIL`/`BLACKBOX_LOG_HIT`/`BITSTREAM_MISSING`/`MODULE_MISSING_OR_BLACKBOX` 任一出现或 rc≠0 ⇒ BUILD-GATE-FAIL）。

### 1.4 文档

- `DESIGN_v2r1.md`：§N.1 v2.1-errata 指针表（13 行）+ **附录 E**（D-1..D-13 处置、F-2 看门狗修订、F-4 B-6 负对照建议、实施偏离/未测）；正文 §3.2/§3.4/§5.1 P2-2 加【v2.1-errata】。
- `_proj_10g/notes/P7B_BIZ_WINDOW.md:77`：W79 标签改为“merge 输入 FIFO 接受的好帧数；FIFO 满丢帧由 W82 计”。
- `p11_p2a_impl_20261018/gates/g5_run.log` → `g5_run.SUPERSEDED_fail_0814.log`。

## 2. 逐条 F 处置

| # | 处置 | 证据 / 位置 |
|---|---|---|
| **F-1** | **已修** | j6/tcpreg 顶端 88 档 + 6 个 gate4/夹具 + gen_inputs + final_state 全同步；`apply_readside_bid1c.py --bid 0x2C --assert` → `APPLY_READSIDE_BID OK (…0 fail)`（`gates/f1_assert_2c.log`，11:37:40）；`bash -n`/`py_compile` 全 OK |
| **F-2** | **已修（设计修订，需追认）** | `rx_merge2.TO_CYCLES=4096`（wrapper）+ G2 臂 G 三条断言全 `[ ok ]`（`gates/g2_xsim_run.log`，10:39:58）；附录 E §E-2 登记“需用户追认”，回退 = `.TO_CYCLES(0)` 一行 |
| **F-3** | **已修** | G6 臂 C：`C-live` 精确 1..4 / 冻结 120 拍 / `C-mut`（dst 常 0）必红，均 `[ ok ]`（`gates/g6_xsim_p11dual.log`，11:06:31；矩阵 g6 亦 PASS，11:45–11:50） |
| **F-4** | **已修（判据口径）** | P2-2 删 `sat16(ch0_txcdc_ovf)` 字级修正项、改 W82/W4 MAC drop + 静默前件 + `INFLIGHT_MAX_FRAMES=33`；W86 口径改“AXIS 反压拍数”（设计正文 §3.4/§5.1 + 附录 E §E-1/D-1/D-2/§E-3） |
| **F-5** | **已修** | 0x2C 阶段改为**显式增量 43 处/20 文件**（无 `_to_2c`）；worktree@1c3cc7da 重放：`APPLY_READSIDE_BID OK (1 阶段/43 处/0 fail)` + **20/20 文件 SHA256 与现磁盘相同**（`gates/f5_rehearse_2c_apply.log`、`gates/f5_byte_compare.txt`，10:37）；主树 `--rehearse` 0 fail + 4 个 `--negctl` 均有牙（`gates/f5_*`） |
| **F-6** | **已修（脚本，未执行构建）** | `build_p7b_ku5p.tcl`：`HLS_SRC_HASH`/`HLS_NET_HASH`、`P7B_BLACKBOX_LOG_HITS=0` 硬门（静态关键行 = `gates/f6_f20_static_lines.txt`）；tcl `info complete`=1；哈希 proc 用 MSYS tclsh 实测可运行 |
| **F-7** | **已修** | G5/G6 bat 各加 `peer_my_ip`+`VRFC 10-3645` 同行为空的定向断言；`tb_app_udp.v` 加 X/Z 运行期断言；`run_tb_app_udp.bat pos` → `P5E UDP APP GATE: OK`（`gates/f7_tb_app_udp_pos.log`，11:19:12） |
| **F-8** | **已修** | 3 个名字声明移到所有 ifdef 之外；`check_decl_outside_ifdef.py` → 三行 `DECLCHECK OK … ifdef stack []`；G7 日志内嵌该检查（`gates/g7_elab_run.log`） |
| **F-9** | **已修** | G7 c8 = 9 宏真构建组合 OK、c13 = DUAL 无 `SFP2_MODE_A` OK；G6 DEFS 加 `-d SFP2_MODE_A` 后 PASS；`ELAB_4COMBO_PASS`（11:18:30） |
| **F-10** | **已处理** | 旧件改名 `g5_run.SUPERSEDED_fail_0814.log`；本轮 G5 重跑得新 `gates/g5_run.log`（`SRCIP_GATE_PASS`，10:43:29）；原因见 §6.1 |
| **F-11** | **已修** | `slow_tx_adp` 提取块进 `generate if (PER_PORT)`；G4 `SLOW_TX_PORT TB PASS`（含长阻塞/SIDE_DEPTH=16 负控，10:40:15） |
| **F-12** | **已修** | G3 新臂 D：正常件 `n0==4&&n1==0`、交叉件 `n1i==4&&n0i==0` 均 ok（`gates/g3_xsim_split.log`，10:40:05） |
| **F-13** | **已修** | G6 臂 D：IP_B ⇒ `o_src_ip=IP_B/o_port=1`；IP_A ⇒ 反向，均 ok（`gates/g6_xsim_p11dual.log`）；⚠️ 用 force 学习口，非真 IPv4/UDP 帧（附录 E D-7） |
| **F-14** | **已处理（良性，已登记）** | 判定 = **既有慢路径 `frame_fifo` 的 bypass 同址碰撞**：`rtl/frame_fifo.v:46-50` 头注释给出“WRITE_FIRST 碰撞 ⇒ DOA X 一拍、存储存活、被 bypass_r 掩掉、永不漏出”；unisim 模型用**上一拍地址**判碰撞（`RAMB36E2.v:3290` 用 `*_last`）而打印**当前地址**（`:2662`）⇒ 日志里的 0040/0000 是碰撞后一拍的值，真实对是 bypass 同址对。G6 因此加“Error:/Critical/Unisim 硬门 + 唯一允许实例”并打印 `XSIM_BENIGN_RAMB36E2_11 observed at u_slow_rx.u_ff`；`unit_fifo` 矩阵门 PASS（bypass 覆盖） |
| **F-15** | **已修** | `mk_mut_srcip.py --n6`（两处锚，hits=2）+ G5 臂 4：`SRCIP TB FAIL errs=4`（恰 4 条 TCP 校验和失败）⇒ `SRCIP mutn6 EXPECTED-FAIL OK`（`gates/g5_run.log` 10:43:29；矩阵 g5 同结果） |
| **F-16** | **已修** | `P7B_BIZ_WINDOW.md:77` W79 口径同步 |
| **F-17** | **已修** | worktree@1c3cc7da 三臂 csim（BOARD_IP_DUAL=0/1/1+ACTIVE+RTO 探针）：**三个输出都与 `base_out.txt` 逐字节相同（diff 空）**；源/二进制 sha256 与失败集合归档 = `gates/f17_hls_baseline.txt` ⇒ 3 条失败**既有**（可复核） |
| **F-18** | **已修** | wrapper 两实例 `src_tick` = 8 位 rollover（每 256 源拍）；G6 臂 C 的 maccnt 活性仍绿（G6 PASS） |
| **F-19** | **已修** | `u_rx_merge.rst_n = reset_n`（与 FIFO rd 侧同源）；理由与残余见附录 E §E-2 |
| **F-20** | **已修（脚本）** | 构建 bat 双判据（`P7B_VERDICT=OK` 文本 + rc + 失败文本零命中）；关键行 = `gates/f6_f20_static_lines.txt` |

### D-1..D-13

全部按附录 E 处置（设计件已就地加指针）。要点：D-1/D-2 = W86 语义 + P2-2 改写；D-3 = G6 活性门；D-4 = 读侧清单 20 文件；D-5 = 无 Z 断言；D-6 = PER_PORT generate；D-7 = UDP 一致性臂；D-8 = HLS 哈希 + synth 日志硬门；D-9 = G3 真变异；D-10 = W79 标签；D-11 = G7 c8 消歧义（+c13）；D-12 = 256 拍节流；D-13 = 归档洁净 + 原因登记。

## 3. 门读数（独有串 + 时戳；原件在 `gates/`）

| 门 | 独有串 | 时刻 | 文件 |
|---|---|---|---|
| G2 `rx_merge2` | `RX_MERGE2 TB PASS`（含 G 臂三条 `[ ok ]`） | 10:39:58 | `g2_xsim_run.log` |
| G3 `tx_split` | `TX_SPLIT TB PASS` / `TX_SPLIT_GATE_PASS`（D-mut 两条 ok） | 10:40:05 | `g3_xsim_split.log` |
| G4 `slow_tx_port` | `SLOW_TX_PORT TB PASS` / `SLOW_TX_PORT_GATE_PASS` | 10:40:15 | `g4_xsim_slowport.log` |
| G5 `tcp_tx_srcip` | `SRCIP ovl OK` / `def OK` / `mut EXPECTED-FAIL OK` / `mutn6 EXPECTED-FAIL OK` / `SRCIP_GATE_PASS` | 10:43:29 | `g5_run.log` |
| G6 `p11_dual` | `P11_DUAL TB PASS` + `XSIM_BENIGN_RAMB36E2_11 observed at u_slow_rx.u_ff -- documented bypass collision` | 11:05:54（独立）/ 矩阵内 ~11:45–11:50 | `g6_run.log`、`g6_{xvlog,xelab,xsim}_p11dual.log` |
| G7 elab | 13 组合全 OK/EXPECTED-FAIL，`[ELAB STRICT] count_0=1 count_1=0`，`DECLCHECK_EXIT=0`，`ELAB_COMBO_FAILS=0`，`ELAB_4COMBO_PASS`；6 条硬门签名 `VRFC 10-2063 Module <…> not found` 全部命中 | 11:18:30 | `g7_elab_run.log` |
| G8(`tb_app_udp`) | `P5E UDP APP GATE: OK (rx_frames=10 … pat_bad=0)` | 11:19:12 | `f7_tb_app_udp_pos.log` |
| 读侧 | `APPLY_READSIDE_BID OK` / `REHEARSE OK` / 4 个 `NEGCTL_VERDICT 有牙` | 10:37 | `f1_assert_2c.log`、`f5_*.log` |
| 矩阵 | 见 §4 | 11:19:17→11:50:30 | `matrix_p4dfix.log` |

## 4. 重跑矩阵结果（24 门常驻）

- `gates run : 24 / 24`；`gates failed: 0`；所有行 `GATE <name> EXIT=0`。
- `VERDICT: FROZEN -- all 340 hashed files byte-identical across the run`（**指纹含 `board/wrapper_p4.v` / `rtl/rx_merge2.v` / `rtl/slow_tx_adp.v` + 全部本轮门文件：`_proj_10g/p11_dual/sim/run_*.bat` / `tb_*.v` / `mk_mut_srcip.py` / `_proj_10g/p7b_chain/sim/run_elab_4combo.bat` / `tb_p7b_chain.v` / biz_win 三件**）⇒ 本轮改动树与矩阵绑定。
- `DIGEST_ALL(content)=ab0505338ac8cecb6d554e40e3fe8ea756c485b243d59dceb382253e986d53af`；`GIT_HEAD=3a157801`；`MATRIX DONE 2026/10/18 11:50:30.11`。
- 归档：`gates/matrix_p4dfix.log`（权威，含每门 cwd/env/verdict）+ `gates/matrix_run.log`（stdout 摘要）。
- ⚠️ 覆盖边界：矩阵指纹 globs **不含** `tb/tb_app_udp.v`、`_proj_10g/p11_dual/sim/tb_tx_split.v`、`mk_mut_srcip.py` 之外的 fix 脚本与构建脚本；构建脚本本**轮未执行**（F-6/F-20 只有静态证据）。

## 5. 未测 / 残余 / 需追认

1. **Vivado 构建/综合/实现、位流、时序、资源、黑盒、HLS 双 IP 网表：全部未跑**（纪律禁止）⇒ F-6/F-20 的硬门只有静态证据；`hls/slowstack_prj` 仍是 P11 前单 IP 网表。
2. **上板 / W83..W87 / F-2 看门狗 / F-14 板级 / P2-1..P2-10：未测**。
3. **F-2 需用户追认**：新增 `TO_CYCLES`/`stat_abort` 行为（默认关、折叠零代价）+ merge 复位改 `reset_n`；不追认回退 = `.TO_CYCLES(0)` 一行。残余：超时后该半帧残拍会作“无 tlast 流”排出，下游 `vlan_strip` 依赖 `RESYNC_EN=1`（DP 构建成立）。
4. **W86 的 RTL 名仍是 `*_ovf`**（语义已按“反压拍数”登记，未改名）；W87[15:0] 仍只作活动指示。
5. **UDP 一致性臂 D 用 force 学习口**（不是真 IPv4/UDP 帧）——判别对象是 mux 取值。
6. **F-10 的 08:14 根因**：旧 bat 未入库、不可逐字复原（见 §6.1 的证据链与反推）。
7. **`apply_readside_bid1c.py` 的 6 个文件行尾由 CRLF→LF**（现磁盘本已是 LF；重放时由 `LF_AFTER_2C` 显式落盘才做到逐字节一致）——登记为“重放语义的一部分”，不是内容变化。
8. **矩阵指纹不含 `tb/tb_app_udp.v`**（该门不在常驻矩阵）；它本轮单独跑过 pos。
9. **HLS 三臂 csim 在改前树上产物与 `base_out.txt` 逐字节相同** ⇒ 3 条失败既有；但**未修**（仍登记）。

## 6. 关键发现（本轮新登记）

### 6.1 G5 `08:14` 全红 → `08:24` 绿（F-10 / D-13）

- 可复核事实：(a) `g5_run.log`（08:14）三臂输出均为 21/21/23 条**同一族全连接级失败**（`IP src`/两校验和/`o_port`/`replay` 全红）——该形态只可能来自“三臂都编了变异件”或“期望/判据整体错位”；(b) 同一日志的判决行 `UNEXPECTED-PASS` 与它自己打印的 `SRCIP TB FAIL` **自相矛盾** ⇒ 当时的判决读的**不是**它打印的那个日志（或 EXPECT 参数错位）；(c) `run_tb_tcp_tx_srcip.bat` 的 mtime = **08:23**，早于 08:24:55 的绿跑 ⇒ 绿跑用的是重写后的 bat。
- **结论**：08:14 的全红是**门/夹具自身缺陷**（不是 RTL 坏），但旧 bat 文本未入库、**无法逐字复原** ⇒ 本格为“按错误签名反推”，不是逐字证据。
- 本轮把该门改成四臂 + `USEMUT` 选择 + 判决取 TB 终止行 + 负臂错误类型必须匹配（`SRCIP_GATE_PASS`）。

### 6.2 N-6 变异器的两个假阴性陷阱（F-15 实施中实测）

1. `csum_sip` 锚在 `tcp_tx_frame.v` 出现**两次**（OVL 体 + 默认体）；`replace(...,1)` 只改 OVL ⇒ 默认体臂编译原文件 ⇒ 假 `UNEXPECTED-PASS`。修 = `--n6` 替换全部锚并打印 `hits=2`。
2. `:run` 子程序原来只对 `TAG=="mut"` 走 `%RTLF%`；新 tag `mutn6` 落到 else ⇒ 编原文件 ⇒ 假绿。修 = `USEMUT` 显式选择。

### 6.3 工具坑：`find /c /v ""` 在本机挂起

F-14 的计数原用 `type f | find /c /v ""`；实测 `find.exe` 进入 stdin 等待（PID 常驻、CPU 不涨）。改用“负向过滤 + `%%~zA` 文件大小”判非空。

### 6.4 工具坑：G7 共享库让 xvlog 在 c2 挂起

`run_elab_4combo.bat` 原把 13 个组合编进**同一个** `xil_defaultlib`；实测 c2 的 xvlog 0-byte 日志、CPU 掉到 0（挂起），单文件新目录重跑正常。修 = **每组合私有 cwd/library + 私有 glbl**（此前 per-combo dir 没做，导致 `Cannot find xil_defaultlib.glbl`；两处一起修后 13/13 通过、总耗时 ~2 min）。

### 6.5 bat 里 UTF-8 非 ASCII 会制造“幽灵命令”

REM 行里的中文/emoji（如 `⚠️`）在 cmd 的 OEM 代码页下被拆成片段执行（`'…' 不是内部或外部命令`）。修 = 本轮触碰的 4 个 bat **全 ASCII**（`run_tb_p11_dual.bat` / `run_tb_tcp_tx_srcip.bat` / `run_elab_4combo.bat` / `run_build_p7b_ku5p.bat`）。

### 6.6 `.\exe` 依赖

本机设置了 `NoDefaultCurrentDirectoryInExePath`-等价行为：bat 里裸 `csim_d0.exe` 报 9009；必须 `.\csim_d0.exe`（F-17 的跑数脚本已按此）。

## 7. 证据文件索引（`_proj_10g/notes/p11_p2a_fix_20261018/gates/`）

`f1_assert_2c.log` · `f5_rehearse_2c_apply.log` · `f5_byte_compare.txt` · `f5_rehearse_main.log` · `f5_negctl.log` · `f6_f20_static_lines.txt` · `f7_tb_app_udp_pos.log` · `f17_hls_baseline.txt` · `g2_xsim_run.log` · `g3_xsim_split.log` · `g4_xsim_slowport.log` · `g5_run.log` · `g6_run.log` · `g6_xvlog_p11dual.log` · `g6_xelab_p11dual.log` · `g6_xsim_p11dual.log` · `g7_elab_run.log` · `matrix_p4dfix.log` · `matrix_run.log`。

> 原始 log 被 `.gitignore` 的 `*.log` 忽略 ⇒ 已显式复制进 `gates/`。

---

## 8. v1.1 订正（kimi 回灌，2026-10-18 review-fix 轮）

> 本节**不改写上文原文**（原文按当时口径读）；凡下文与上文冲突处，以本节为准。
> 本轮的改动落点、门读数与矩阵结果 = `_proj_10g/notes/p11_reviewfix_20261018/FIX_REPORT.md`。

1. **§4 指纹覆盖声明方向写反（订正）** —— 原文「矩阵指纹 globs **不含** `tb/tb_app_udp.v`、`_proj_10g/p11_dual/sim/tb_tx_split.v`、`mk_mut_srcip.py` 之外的 fix 脚本」把 `tb_tx_split.v` 说到了"不含"一侧，实际相反。
   现核（`sim/p4sim/P4_MATRIX_FINGERPRINT_20261018_111917_before.txt`）：`_proj_10g/p11_dual/sim/tb_tx_split.v` **在指纹内**（修改清单 + SHA256 各 1 行，共 2 命中）；`mk_mut_srcip.py` 与 `run_tb_*.bat` 也在内（`p11_dual\sim\tb_*.v` / `run_*.bat` globs）。
   **不在**指纹内的只有：`tb/tb_app_udp.v`（顶层 `tb\` 不在任何 glob）、`_proj_10g/p11_dual/sim/scan_xsim_errors.py`（本轮新增，`.py` 仅 `mk_mut_srcip.py` 单列）、`board/build_p7b_ku5p.tcl` 与 `board/run_build_p7b_ku5p.bat`。
2. **§2/§3 两处时刻矛盾（订正）** ——
   ① F-1 行写 `gates/f1_assert_2c.log`，`11:37:40`；文件 mtime = **10:37:40**（§3 的 `10:37` 正确，§2 是小时笔误）。
   ② §3 G6 行把两个文件并成一行时只给了一个时刻：`11:05:54` 是 `g6_run.log`（独立跑包装日志）mtime，`11:06:31` 是 `g6_xsim_p11dual.log`（xsim 本体）mtime —— 两者都对、指向不同文件，不是同一事件的矛盾；引用时须带文件名。
3. **`gates/f6_f20_static_lines.txt` 引文陈旧（已重取）** —— 旧文件引自 ASCII 清理前的 `run_build_p7b_ku5p.bat`（模块缺失检查无 `/B`、行号 63–81）；已按**当前树**重新生成（2026-10-18），行号现为 tcl 36–470 / bat 63–87，并补入 F-21 的 `P7B_SNAP_TOP5_*` 硬门与 `/B` 锚定的模块检查（现 bat:77）。
4. **`gates/g5_run.log` 的 4 处"幽灵命令"（披露）** —— 该归档件含 4 处 `'…' 不是内部或外部命令` + `系统找不到文件`（每处 2 行）。原因 = **中间版 bat 的 REM 行含中文/emoji，在 cmd 的 OEM(GBK) 代码页下被拆包执行**（§6.5 同族）。
   时间序：这些行属于 08:24 绿跑后、写死前的中间版 bat；D-13 归档时保留了原始输出。**它不影响判决**：每臂的 `SRCIP ovl/def/mut/mutn6 OK` 与最终 `SRCIP_GATE_PASS` 都在幽灵行之后正常打印，门判决读 TB 终止行。
   本轮重跑（ASCII 化后的 bat）同一门：`g5_run.log` 中该族**0 命中**（`grep -c '不是内部或外部命令'` = 0），见 `p11_reviewfix_20261018/gates/g5_console.log`。归档件保留不清理（作为 bat 编码坑的实证）。
5. **F-17 "逐字节相同"降级** —— 原句应为「**归一化后 diff 为空**」：`gates/f17_hls_baseline.txt` 自己的小节标题就是 `## diff vs base_out (normalized)`。worktree（`D:/repo/XCKU5PMini/_p11_wt_2c`）**已删除**、`base_out.txt` 与三臂产物不在现树 ⇒ **无法复验逐字节相同**；可复核的只剩该文件里的源/二进制 sha256 与失败行集合。**结论方向不变**（3 条失败在改前树即存在），但证据强度按"归一化后相同（不可复验）"读。
6. **`$isunknown` 术语（订正）** —— 实现里是本地函数 **`is_xz1`**（`(v!==0)&&(v!==1)`；Verilog-2001 下 `$isunknown` 不可用）。已在 `DESIGN_v2r1.md` §N.1、§3.x 断言行、§5.2 G1 行、附录 E D-5 就地加注；本报告 §1.2 原本就写的是 `is_xz1`，无需改。
7. **G7/G8 门编号（统一）** —— 以设计件 §5.2 为准：**G7 = elaboration 13 组合**、**G8 = HLS 双 IP（csim 两二进制 + `tb_hls_dual_ip`）**。
   原文两处把 `tb_app_udp`（P5E 门）叫成 `G7(tb_app_udp)`/`G8(tb_app_udp)` —— 订正为 **"P5E `tb_app_udp` 门（非 G8）"**；**G8 本轮未跑**（纪律禁止 HLS 重构/构建，只有 F-17 的三臂 csim 基线复现）。
8. **F-7 X/Z 运行期断言补负控（已补，证据在案）** —— 在 `tb/tb_app_udp.v` 加 `-testplusarg XZNEG`：复位后 200 拍 `force u_cfg.o_port = 1'bz` 保持 10 拍。`run_tb_app_udp.bat xzneg` → `[FAIL] P11 H-1: X/Z on u_cfg.o_port or u_cfg.cfg_sync` 精确触发、末行 `P5E UDP APP GATE: FAIL errs=10`、包装器打印 `XZNEG_NEGCTL_OK`、RC=0（期望红）。
   正臂同轮复跑：`P5E UDP APP GATE: OK (rx_frames=10 rx_bytes=13305 tx_frames=25 drop_len=1 drop_ovf=5 split=15 pat_bad=0)`。
   原件 = `p11_reviewfix_20261018/gates/{app_udp_xzneg_console.log,xsim_ua_xzneg.log,app_udp_pos_console.log}`。
9. **F-2 阈值终裁（2026-10-18）** —— 用户裁定 **`TO_CYCLES = 4096`**（0xFFFF 方案已否：4096 已是最大帧 21.5×，0xFFFF 只把停钟黑窗放大 16×）。⚠️ 本报告 §1.1/§5-3 写的"下一构建 0x2D 传 `16'hFFFF`"按本条读；**当前树 `board/wrapper_p4.v` 仍是 `16'hFFFF`（review-fix 轮未改），该一行由 TL 收口后统一改为 `4096` 再构建**。设计件 §E-2/E-5 与 `P7B_OPEN_ITEMS.md` §0-68 已同步。
