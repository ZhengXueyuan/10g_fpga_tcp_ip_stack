# P11 / P1 实施轮 —— 独立红队审查 FINDINGS

> **TL 代落（2026-10-18 03:2x）**：本件 = 独立红队审查 agent 的完整 FINDINGS 原文（平台拒绝 agent 写 `.md`，由 TL 转录；未改结论）。审查期间只在审查目录写了辅助取证件（`fp_now.txt`、`_fpcheck.py`、`_fpdbg.py`、`_fpdbg2.py`），未修改任何被跟踪文件、未跑 xsim/Vivado、未碰板。

- 审查对象：HEAD **3d4ce8ad**（P11 P1 实施轮收口；工作树干净）。
- 施工权威：`_proj_10g/notes/p9_dual_sfp_p1_impl_20261018/DESIGN_v5.md`；实施报告：同目录 `REPORT.md`；门日志：同目录 `gates/`。
- 上游：`p9_dual_sfp_p1_design_20261017/README_FOR_TL.md`、`p9_review_dual_sfp_p1_design_20261018/FINDINGS.md`、用户裁定 U-1..U-7。
- 角色：独立只读复核；不下 PASS/FAIL 裁定；不实施、不跑 xsim/Vivado、不碰板。
- 状态词：【已证·源码】【已证·日志】【推断】【未判定】【未测】；纸面数字标"纸面"。

## 0. 一页结论

**分级计数：阻断 0 / 高 2 / 中 7 / 低 9。**

**最重要 3 条**

1. **高-1（读侧静态核对器红）**：`_proj_10g/notes/p7b_biz_win/check_window.py` 在本轮被编辑（read-side 17 文件之一），但现读运行 **TRUE_RC=1 / PASS=95 FAIL=9**，失败项恰是本轮新增的 ch0 段：判据 3（束宽等式漏 `+4`）、判据 5a（顶端 17 项未含 `ch0snap_dout[3:0]`）、判据 5c（W76..W82）。该 checker 在 `P7B_BIZ_WINDOW.md:126/166/197/242` 被列为现存静态装配核对，且**不在** 20 门矩阵内；报告/台账的"读侧 0 fail / 门全绿"不覆盖它。→ 读侧同步不完整，须修 checker 并在门里跑一次。
2. **高-2（SNAP_STATUS[7] 读侧未同步）**：DESIGN §4.3-7 要求"主机**必须**读 `SNAP_STATUS[7]` 再决定是否信 W79..W82"，§11.2 中-19 也承诺改 `p6b_accept.sh`/`p7b_snap.sh` 的 0x1C 解析并加构造性负控；实际 `p7b_snap.sh` 只取 0x1c 的 gen/done（`:208-214`），`p6e_snap_check.sh:205` 只注释 bit0/1/2，`p7b_gate4_accept.sh:283-288` 只取 gen/done，`p6b_accept.sh` 完全未动。⇒ P1 板级轮用现役取数器读 W79..W82 时，不会看到"本代 ch0 束陈旧"的告警，可把上一代/复位值当本代读数。G1/G4 的 bit7 断言是 xsim 侧，不是读侧工具。
3. **中-1（无行为门的 TCP_TX_OVL body）**：`gates/tx_ovl_gate_status.txt` 宣称"OVL body is exercised by the standing chain gate + matrix #20"，但 chain TB 的 TX 臂是 **force `txsrc_*`（u_tx_arb 输出线）**，TB 自己写明"不测 u_tx_arb 内部"（`tb_p7b_chain.v:1339-1341`）；全文未驱动 `tcp_tx_frame`。⇒ 替代门只做到 elaborate，不是行为覆盖；`run_tx_ovl_gate.bat` 仍未修。

**门读数汇总（独立核对）**：G1a 106/0【已证·日志】；G1 142/0（132 条具名 PASS + 10 次 `snap_take` 硬断言，未打印 PASS）【已证·日志】；G4 29/0（18 条具名 + 11 次 `snap_take`）【已证·日志】；G2 `PASS_ALL`（BID 0x2B / W76..W82=0 / 0x17C SLVERR）【已证·日志】；G5 4/4【已证·日志】；G3 20/20 / FROZEN【已证·日志 + 独立复算】；读侧 apply 65 处/17 文件、assert/rehearse 绿、负控 4/4 有牙【已证·日志】；`run_tx_ovl_gate` 未修【已证·日志】。

**独立复算的关键正结果**：G3 的 FROZEN 内容摘要 `DIGEST_ALL(content)=37851074ec8f26cbc8fac4152a7aa85ce98a691ca6537becd6c6e1d7a45123a7` 与**现树 HEAD 3d4ce8ad 的 296 文件集逐字节重算完全一致**；`DIGEST_COMPILE=ee5658e0…` 也可由当前 manifest 复现；`p7bchain_src.f` 49 文件与 gate bat 的字面表一致（`sim/p4sim/matrix_p4dfix.log` 的 manifestcheck 行）。⇒ 日志的 `GIT_HEAD=dbbbe1e7` 是提交前 HEAD，但 FROZEN 的"内容绑定"成立（运行时的 7 个 M 文件 = 本轮实现文件，提交后内容未变）。

## 1. 事实核表

### 1.1 DESIGN_v5 对上游 FINDINGS 的逐条处置

| 上游项 | DESIGN_v5 处置 | 实施/现读核对 | 判定 |
|---|---|---|---|
| 高-1（S2/P3 判据与单栈矛盾） | §8 改写 P3 判据 | 聚合 ≤9.4935 Gbps / 公平份额 / 丢帧背压可读 / WIN_POOL 后果 | 【已证·源码/文档】 |
| 高-2（rx_merge2 严格优先饿死） | §8 要求 round-robin / ≥2 帧或 per-port drop / 负对照 | 设计到位，P3 实施 | 【已证·文档】 |
| 高-3（port 位穿 tx_arb） | §9.2 #3/#4（74 位或 split 前移） | 设计到位，P2 实施 | 【已证·文档】 |
| 高-4（A-1 的 tcp_tx_frame 源 IP/校验/种子/双体） | §9.2 #1/#2 全列 | 设计到位，P2 实施 | 【已证·文档】 |
| 高-5（snap_busy 排除 ch0；状态清位；G1-f 双代） | §4.3 | 源码：`snap_busy` `wrapper_p4.v:4584` 不含 `ch0snap_busy`；`snap_req` 清 `snap_main_seen/ch0_armed/ch0_seen/ch0_to_hit/ch0_to_cnt` `:4563-4572`；G1-5a..5d / G4-6a..6d 片上全过 | 【已证·源码/日志】 |
| 高-6（FP 预算 223/448） | §7 重算 | 源码计数 DP ≈224、ch0 ≈168、pcie ≈448+；与设计表一致（纸面） | 【已证·源码】 |
| 高-7（plan 行号 0x28 树） | 设计改用现读/符号 | DESIGN 头声明；但 DESIGN 内多处锚点仍是 P1 前 0x2A 行号（见低-2） | 【部分】 |
| 中-1..中-9（tcl:286 / vcc 自由 / carrier_changes / LOS 上升沿 / rx0_free / stub 拆分 / 矩阵 manifest / 模式语义 / 四宏声明） | 均采纳 | 逐项源码/门日志命中；G5 四组合、chain manifest 49、`build_p7b_ku5p.tcl:286` 正确 | 【已证·源码/日志】 |
| 中-10..中-15、中-17、中-20 | 登记 P2/P3/文档/板级前置 | 设计 §9/§10.4/§11.2 登记 | 【已证·文档】 |
| 中-16（好帧含 `!terr`） | 采纳 | `wrapper_p4.v:986` `tcrs && !terr`；W81 = MAC `stat_crc_err` | 【已证·源码】 |
| 中-18（0x2A 已烧） | 采纳 | 设计头写 0x2A 板上现役（台账 §10-117） | 【已证·文档】 |
| 中-19（SNAP_STATUS[7] 读侧工具 + bit7 负控） | "采纳" | **未落实**：RTL bit 与 xsim 断言有；`p6b_accept.sh`/`p7b_snap.sh`/`p6e_snap_check.sh`/`p7b_gate4_accept.sh` 的 0x1C 解析均未加 bit7，无读侧 bit7 负控（见高-2） | **【已证·源码】未落实** |
| 低-1..低-10 | 均登记 | 设计 §11.3 逐条登记 | 【已证·文档】 |

**结论**：高 7 全部落实（高-7 部分，锚点漂移是文档层）；中 20 中 **中-19 未落实**，其余采纳/登记成立；低 10 登记成立。

### 1.2 REPORT 门读数 vs `gates/` 日志（逐条）

| 报告项 | 报告值 | 日志/独立核对 | 判定 |
|---|---|---|---|
| G1a 基线 | 106/0 PASS | `G1a_baseline.txt`：`106 checks, 0 fail / VERDICT = PASS`；SHA256：wrapper `214dac09…cafb71`、TB `68979b25…`、axi_regs `d2a71769…`、stub `66940874…` | 【已证·日志】 |
| G1 全链 | 142/0 PASS | 全文日志：`142 checks, 0 fail`；`PASS=132` 行 = 132 条具名 `[PASS]`；10 次 `snap_take` 检查不打印 PASS（`tb_p7b_chain.v:2209-2233` 每次 `checks++`） | 【已证·日志】 |
| G4 单元 | 29/0 PASS | `xsim_p1ch0.log`：18 条具名 `[PASS]` + `29 checks, 0 fail`；11 次 `snap_take` | 【已证·日志】 |
| G2 p6e | `PASS_ALL` | `xsim_p6e.log`：BID 0x2B、W76..W82 全 0、`0x17C` SLVERR、`PASS_ALL` | 【已证·日志】 |
| G5 四宏 | 4/4 | `G5_elab_4combo.txt`：c1..c4 OK / `ELAB_4COMBO_PASS` | 【已证·日志】 |
| G3 矩阵 | 20/20 / FROZEN / RC=0 | `G3_matrix_2B.txt` + `sim/p4sim/matrix_p4dfix.log`：20/20、gates failed 0、manifestcheck `49 files == p7bchain_src.f`、FROZEN 296 文件；`RC=0` 未在日志里显式打印（矩阵 `gates failed: 0`，退出码需外部见证） | 【已证·日志（RC 见备注）】 |
| 读侧 0x2B | apply 65 处/17 文件 0 fail；assert 0 fail；rehearse 剩余 0；负控 4/4 有牙 | `readside_assert_2B.txt`（EDIT_COVERAGE 17/17、搜索面 524 文件全登记、默认值一致）；`readside_rehearse_2B.txt`（阶段链末项 65 处、剩余 0）；`readside_negctl_{table,bid,tier,face}` 各 `NEGCTL_VERDICT 有牙` / `NEGCTL_EXIT=1` | 【已证·日志】 |
| `run_tx_ovl_gate` | 未修（8 锚点漂移）；替代门 = chain 编 `TCP_TX_OVL` | `tx_ovl_gate_status.txt` 命中；但"替代门"只证明 elaborate，不证明行为（见中-1） | 【已证·日志；覆盖口径需更正】 |
| 改动规模 | 29 文件 +1297/−288 | `git show --numstat 3d4ce8ad`：**57 文件 +10041/−289**；剔除 impl 轮 notes 目录后 **38 文件 +2371/−289** | **【已证·源码】不一致** |

### 1.3 独立复算（FROZEN / 基线哈希 / 检查数）

- **FROZEN 内容绑定**【已证·日志+复算】：按 `p4gate.py` 的记录重算 `SHA256(path)` 行的内容摘要 = `37851074…45123a7`，与 `G3_matrix_2B.txt` / `sim/p4sim/matrix_p4dfix.log` 的 "this log is bound to revision DIGEST_ALL(content)=…" 逐字相同；共 **296 文件**。现树 `git status` 对 hashed set 无 M 文件。⇒ 运行时的 7 个 M 文件（`run_tb_p7b_chain.bat`、`tb_p7b_chain.v`、`axi_regs.v`、`p7b_pcs_stub.v`、`wrapper_p4.v`、`paths.txt`、`run_matrix_p4dfix.bat`）就是本轮实现面，提交后内容未变；`GIT_HEAD=dbbbe1e7` 只是提交前 HEAD，**FROZEN 绑定本提交内容成立**。
- **G1a 基线哈希**【已证】：`G1a_baseline.txt` 的 wrapper 哈希 `214dac09…cafb71` 不是 git blob（`git show dbbbe1e7:board/wrapper_p4.v` = `41abd90f…`）——差异是 **CRLF 工作树字节 vs LF blob**（`core.autocrlf=true`）；`214dac09` 与 `vivado_prj/.../imports/board/wrapper_p4.v` 的 0x2A 副本逐字节相同。⇒ 基线确实是 0x2A 工作树，不是"未知版本"；TB/axi_regs/stub 的哈希与父提交 blob 逐字相同（这三件是 LF）。
- **检查数**：G1 `grep -c "[PASS]"` = 132，`snap_take;` 调用 = 10 ⇒ 142；G4 `[PASS]` = 18，`snap_take` = 11 ⇒ 29。两个数都自洽。
- **p7b_chain manifest**：`sim/p4gates/p7bchain_src.f` 49 条（含 `tb_p7b_chain.v`、MAC 三件、stub、wrapper、axi_regs）；矩阵 manifestcheck `49 files == manifest`；`paths.txt` 的 FINGERPRINT_GLOBS 已加入 `_proj_10g\p7b_chain\sim\run_*.bat` 与 `tb_*.v`。⇒ G3 第 20 门确实纳入本轮文件【已证·日志】。
- **`check_window.py` 独立运行**：`python _proj_10g/notes/p7b_biz_win/check_window.py` ⇒ **TRUE_RC=1，PASS=95 FAIL=9**；失败 = 判据 3、5a、5c(W76..W82)。详见高-1。

### 1.4 事实核不一致项（材料级 4 + 标注级 8）

**材料级（4）**

1. `REPORT.md` §0/§8、`DESIGN_v5` 提交信息/台账 §10-126/`P11_REVIEW_QUEUE.md` 的"**29 文件 +1297/−288**" vs 实际 **57 文件 +10041/−289**（或剔除 notes 后 38/+2371/−289）；TL 抽核 #1 的"✓"为假。
2. DESIGN/REPORT 声称中-19 "采纳" vs 读侧 `SNAP_STATUS[7]` 工具同步**未实施**（高-2）。
3. `tx_ovl_gate_status.txt` 的"OVL body is exercised by the standing chain gate" vs chain TB 只 force `txsrc_*`、从不驱动 `tcp_tx_frame`（中-1）。
4. REPORT/台账"读侧 0 fail / 门全绿" vs `check_window.py`（read-side 17 文件之一）**RC=1 / 9 FAIL**（高-1）。

**标注级（8）**

5. `REPORT.md` §3 的行号锚点漂移：ch0 域别名 `:310`（实际 `wrapper_p4.v:352-353`）、装配 `:4630`（实际 4601 起）、BID `:4797`（实际 4824）。
6. TL 抽核 #12 "p7b_chain 5 件" vs 本轮 p7b_chain 目录新增 **6 件**（`tb_p1_ch0_unit.v`、`run_tb_p1_ch0_unit.bat`、`run_elab_4combo.bat`、`elab_files.f`、`hls_p1ch0.f`、`hls_p7bchain.f`；另 `run_tb_p7b_chain.bat` 修改）。
7. `gates/G1_chain_2B.txt` 只摘录了 9 条 P1 具名 PASS（长标签被 `chk` 的 `[255:0]` 输入截断，9 条被滤掉）；全文日志在 **ignored** workdir（`sim/p4gates/work_20261018_014051/p7b_chain/xsim_p7bchain.log`），未入 `gates/`。
8. `P7B_BIZ_WINDOW.md` 的"逐代回溯"出现**两段连续重复**（新段 0x160 起 + 旧段 0x15C 起）；`final_state.sh:12-15` 也有同类重复注释。
9. `run_tb_biz_win.bat:24` / `run_xvlog_wrapper.bat:34` 的报错文字仍写 "not 76-word"（指纹已改成 83）；`u_pcie_regs` 的 `.SNAP_NW` 注释首行仍写 "76 = …"。
10. `G3_matrix_2B.txt` 的 NOTE 说 stored `DIGEST_ALL` 是 "pre-content-v1（含 size/mtime）"—— 现读 p4gate 的 `DIGEST_ALL` 也是 content-only，差异实为**排序键不同**（digest_a 按 "hash path" 排序，freeze 复算按 path 排序）；两者都对，但 NOTE 的解释误导。
11. `p7bchain_src.f` 头注释写 "gate (#22)" vs 矩阵注册为第 20 门（#22 似为轮次号，不是门号）。
12. `check_window.py` 判据 4 的 oracle 是 `git show HEAD:board/wrapper_p4.v` —— 提交后 HEAD 已是新树 ⇒ "旧字未移位"判据**空转**（本机输出 "HEAD 48 项, 新表 48 项 => 新增 0 项"）。读侧 apply 时 HEAD 还是 0x2A，故当时有意义；作为常驻 checker，应改冻结锚（上一代 wrapper 或记录项表）。

## 2. 分级发现

### 阻断（0）

未发现使 P1 的 RTL/构建在结构上不可实现的阻断项。`snap_dout_all` 的总字数独立解析 = **83**（`check_window.py` 判据 1 通过），G1/G4 的 W76..W82 唯一值读回、G2 的 0x17C/83 字、G5 四组合均成立。⇒ RTL 主体结构【已证·源码/日志】；下面的高/中项是验证层与读数口径问题，不是"RTL 错"。

### 高（2）

**高-1 `check_window.py` 静态装配核对器红（9 FAIL / RC=1），且不在任何门里**
- 文件:行号：`check_window.py:18`（docstring 束宽等式仍无 ch0）、`:195`（判据 3）、`:227/:240`（判据 5a）、`:258`（判据 5c slot_map）。
- 依据：现读运行（TRUE_RC=1）：
  - `[FAIL] 3 束宽等式 == NW (14+22+3+(39-4)+5 = 79)` —— 漏 `SNAP_CH0_NW=4`；设计 §4.2 明写 `14+22+3+(39-4)+5+4 = 83`。
  - `[FAIL] 5a 最上面 17 项` —— 实际顶端 4 项是 `ch0snap_dout[3..0]`，期望却全按 `p7bdp_dout[38..22]`。
  - `[FAIL] 5c 槽号映射 W76..W82` —— W76..W78 的实际 RHS 是 `ch0_pcs_status/ch0_pcs_evt/ch0_los_bundle`（不是 `biz_w76..78`），W79..W82 根本不在 p7bdp 束（`slot_map` 把它们映射成 39..42）。
- 影响：该 checker 正是"装配项数/顺序/槽号/旧字不移位"这一风险类的唯一机械守卫（`P7B_BIZ_WINDOW.md:126/166/197/242`），本轮未跑；`gates/readside_assert_2B.txt` 只检查文本默认值，不运行 checker。⇒ "读侧 0 fail / 门全绿"不能覆盖这一格。
- 建议：① 判据 3 加 `SNAP_CH0_NW`；② 5a 期望按 `[ch0[3..0], p7bdp[38..26]]` 生成；③ 5c 给 W76..W78 特判 `ch0_pcs_*`、给 W79..W82 用 ch0 束槽 0..3；④ 把 `check_window.py`（和 `tb_biz_win`）纳入一个常驻入口（矩阵第 21 门或 read-side 收口脚本），并附一次 `--mutate drop/swap/declpatho` 负控；⑤ 判据 4 的 oracle 改冻结锚（见低-4）。

**高-2 `SNAP_STATUS[7]` 的读侧工具同步未实施（DESIGN 中-19 只落实了 RTL 半边）**
- 文件:行号：`p7b_snap.sh:208-214`（只取 gen/done，无 status 打印/bit7）；`p6e_snap_check.sh:205`（INFO 行只注 bit0/1/2 + gen）；`p7b_gate4_accept.sh:283-288`（只取 gen/done）；`p6b_accept.sh:62,150-154`（只取 gen）；`P7B_BIZ_WINDOW.md` 全文无 `SNAP_STATUS[7]`/bit7。
- 依据：DESIGN §4.3-7 "主机必须读 `SNAP_STATUS[7]` 再决定是否信 W79..W82"；§11.2 中-19 "p6b_accept.sh/p7b_snap.sh 的 0x1C 解析列入读侧阶段 0x2B；自检加 bit 7 可置 1 的构造性负对照"。实际 read-side 阶段（65 处/17 文件）没有改这些 0x1C 解析；G1-5a/6a 与 G4-6a 只在 xsim 里构造 bit7=1，不是读侧工具。
- 影响：P1 板级 S-2/S-5 读 W79..W82 时，若 ch0 钟停/超时，工具不会提示"本代 ch0 束陈旧"，操作者会把上一代/复位值当本代读数。**这是 P1 观测面的核心安全语义**。
- 建议：① `p7b_snap.sh`/`p6e_snap_check.sh`/`p7b_gate4_accept.sh` 打印/解析 `SNAP_STATUS[7]`（名字建议 `ch0_snap_to/ch0_bundle_stale`），并在 W79..W82 读数旁给 `stale=1` 告警；② `p6b_accept.sh` 若仍在用，至少加注释/硬失败；③ 在 `p7b_gate4_selftest.sh` 的 fake board 里构造一次 `SNAP_STATUS[7]=1` 的负控（期望工具报 stale 且非零/告警）；④ `P7B_BIZ_WINDOW.md` 增 SNAP_STATUS 段，写明 bit7 语义与"先读 status 再信 W79..W82"。

### 中（7）

**中-1 `TCP_TX_OVL` 的"替代门"只做到 elaborate，不覆盖行为**
- 文件:行号：`tb_p7b_chain.v:1339-1341`（"注入源 = txsrc_* … 不测 u_tx_arb 内部"）；`gates/tx_ovl_gate_status.txt`；`sim/p7b_stagec_tx/mk_mut_tx.py --dry-run` 8 锚点漂移。
- 依据：chain 门编译 `TCP_TX_OVL`，但 TB 只 force `txsrc_tdata/tkeep/tvalid/tlast`（`u_tx_arb` 输出线）；全文无 `tcp_tx_frame`/`u_tx_arb` 驱动。⇒ OVL body 只被 elaborate，行为零覆盖；`run_tx_ovl_gate.bat` 的 8 个 Stage-C 变异锚点仍未修。
- 建议：① 把 `tx_ovl_gate_status.txt` 的措辞改成 "compile/elaboration only"；② 要么修 8 锚点，要么新增一条 `tcp_tx_frame` 级行为臂（或把 `sim/p7b_stagec_tx/quick_bw.bat` 的可用变异升为常驻门）；③ 在 OPEN_ITEMS 登记"board TCP TX body 无行为门"。

**中-2 G4 SOP-2 语义放宽：从 `SOP==TLAST` 改为"F4 窗口外无裸 SOP"，且 F4 内有 2 个真实裸 SOP**
- 文件:行号：`tb_p7b_chain.v:2186-2195`（新判据）、`:337/:345/:432`（`rx_bare_n/rx_f4_win`）、`:1307/:2147`（F4 窗口）、`:2192`。
- 依据：`gates/G1_chain_2B.txt` 的 DIAG：`SOP n=55 / TLAST n=53 / TERM n=2` ⇒ 2 个 SOP 无 TLAST；新判据把 F4 窗口内排除。TB 注释承认"MAC 的单个 `term_pend` 用一个 TERM 关闭多个已推 SOP（本轮 P1 timing 位移后观测到 2 个）"。RTL 的 `vlan_strip.v:130-131,221-225` 会在新 SOP 上重置/直通，故数据通路不会合并帧；但 `mac_rx_10g` 的"每 SOP 必被 TLAST 关闭"合同在 F4 下不成立，是既存行为。
- 影响：这是既有判据的**真实语义改变**（不是纯健壮化）；报告 §6 登记了"G4 SOP-2 口径"，但设计 §11/§13 未登记 MAC 的"单 `term_pend` 多裸 SOP"行为与 2 个观测实例。
- 建议：① 在 DESIGN §13/OPEN_ITEMS 登记该 MAC 行为 + 2 个实例 + `vlan_strip` 的重同步依据；② G4 另加一个窗口内"未闭合 SOP 计数"信息量（不作为 PASS/FAIL，只登记）；③ 若未来 F4 在板上可触发（下游长期 tready=0），评估 `term_pend` 单槽是否要扩。

**中-3 W77/W80/W81 的行为覆盖缺口（只测了 force/好帧）**
- 文件:行号：`wrapper_p4.v:3892-3997`（W76..W78 逻辑）；`tb_p7b_chain.v:1545-1560`（group 7 直接 force `pcs0_ferr_evt/bad_evt/erv_evt/vcc_cyc` 和 `ch0_stat_crc_err/drop`）；`tb_p1_ch0_unit.v:200-217`（只注入好帧）。
- 依据：① 没有任何臂把 ch0 的坏 FCS 帧送进 MAC 并检查 **W81 +1 / W79/W80 不增**；② 没有 `/E/`（terr）帧臂验证 W79/W80 的排除；③ 没有驱动 `u_pcs.ferr_0/badv_0/errv_0` 的臂验证 W77 的 ferr/bad/erv 更新/饱和，也没有验证 vcc 自由计数（group 7 直接 force 计数器，绕过了更新逻辑）。
- 建议：加 3 条 ch0 臂：坏 FCS ⇒ W81+1、W79/W80 平；`/E/` ⇒ W79/W80 平、W81 平；`ferr_0=1` 持续 N dp 拍 ⇒ W77[31:24] 增到饱和/停、`vcc` 在 Δ 窗内变化（并记录 mod 256 口径）。

**中-4 S-1/S-5 的"W77 ferr/bad/erv 不增"是饱和后的空判据（并含 S-4 的 +1 脆性）**
- 文件:行号：`DESIGN_v5 §3.2/§10.4 S-1/S-5/S-4`；`wrapper_p4.v:3945-3957`（8 位饱和，`!=8'hFF` 门）。
- 依据：ferr/bad/erv 是"同步后为高的 dp 拍数"，156.25 MHz 下 **1.6 µs 到 0xFF** 后不再增。若某标志上电即卡高（或真实错误风暴先打满），10 min 窗口的 `ΔW77 = 0` ⇒ S-1/S-5 的"不增"通过，而链路实际是坏的。S-1 只检查 W76[2]/[4]/[5]/[6]，不检查 W76[7]/[8]/[9]/[10]/[20:13]。另：S-4 期望 `W78[23:16] +1`；物理拔 J7 的 LOS 引脚可能抖动（S-3 的同族教训：`carrier_changes` 实测 +3），`+1` 可能假 FAIL；应改为"≥1 + 记录实际值"，并给 LOS 事件加最小间隔/去抖口径。
- 建议：S-1/S-5 改成"**绝对值为 0**（或 W76 对应 level 位为 0）"作为主判据，Δ 只作副证；S-4 改 `≥1` 并记录实际值。

**中-5 背压 backstop 的覆盖缺口：B1/B2/B3 都不删除 W76/W78 的 DP 域成本**
- 文件:行号：`DESIGN_v5 §10.3`；`wrapper_p4.v:3892-4000`（PCS 3FF 69 + events 32 + LOS 24 + sig 3 = ~128 DP FF）、`:4452-4454`（p7bdp 3 字 hold_b +96 DP FF）。
- 依据：B1 删 W77（≈32 DP + 64 pcie）；B2 删 W79..W82+ch0 MAC（ch0 域/大 LUT）；B3 删 W77/W79..W82，**仍留 W76+W78**（其 PCS 3FF 69 + LOS 24 + sig 3 + p7bdp hold_b 96 ≈192 DP FF）。若构建失败族正是这些 DP 3FF/hold_b，B1/B2/B3 都不解决，最后只能整轮回退。
- 建议：① 在 §10.3 明确"B3 之后仍失败 ⇒ abort-to-P0（整轮回退）"的分支；② 或加 B4 = "W76 只保留 block_lock/hi_ber 两位 + W78 保留 LOS 两位（去事件）"；③ 构建轮定向看 `u_snap_p7bdp/hold_b_reg[*]`、`pcs0_*_sr`、LOS 计数器的 DP top-10。

**中-6 `SFP2_MODE_A/B` 硬门与"构建实际宏组合"没有任何 elaboration 门**
- 文件:行号：`wrapper_p4.v:253-283`（硬门）；`run_elab_4combo.bat:COMMON`（只 `DEV_USP/APP_MODE/DP_156MHZ/P6B_SIM_CLKGEN/UDP_TX_OVL/TCP_TX_OVL`）；`build_p7b_ku5p.tcl:286`（构建将传 `SFP2_MODE_A=1`）。
- 依据：G5 的 4 组合只覆盖 `P7B_10G × PCIE_OBS`；没有任何门编译 `-d SFP2_MODE_A`（构建实际将用的组合），也没有负控证明 `A∧B` / `B∧¬P7B_10G` 真的 elaboration 硬失败。G4 只验证"无 B ⇒ 模式位 0"。
- 建议：G5 增 3 个 combo：`A`（必须 OK）、`A+B`（必须 FAIL）、`B`（无 P7B，必须 FAIL）；把 expected-fail 的退出码/签名写进 bat。

**中-7 事实核：`git diff --stat` 与报告/台账不一致（TL 抽核 #1 为假）**
- 文件:行号：`REPORT.md:11/54`、`DESIGN_v5` 提交信息（HEAD 3d4ce8ad）、`P7B_TL_LEDGER_20261010.md:1720`、`P11_REVIEW_QUEUE.md`。
- 依据：`git show --numstat 3d4ce8ad` = 57 文件 +10041/−289；剔除 `p9_dual_sfp_p1_impl_20261018/` 后 38 文件 +2371/−289；无论哪种口径都不是 29/+1297/−288。TL 抽核表 #1 "✓ 29 files, +1297/−288" 与事实不符。
- 建议：四份文档统一改成 `git show --stat 3d4ce8ad` 的实际值，并注明"含 impl notes/gates"与"实现面（剔除 notes）"两个口径；TL 抽核 #1 标记更正。

### 低（9）

**低-1 G1 归档摘录不完整 / 检查数口径未解释**：`gates/G1_chain_2B.txt` 只有 9 条 P1 具名 PASS（`[PASS] P1-…` 前缀未被截断的才有）；`P1-1c/3a/3b/4a/4b/5a..5d` 的标签 >32 字节，被 `chk` 的 `[255:0] name` 截断后以 `[PASS] c …` 形式落在全文日志里，摘录滤掉。报告"全部日志在 gates/"不成立；全文在 ignored workdir。建议：把全文的 P1 段（或全文）归档到 `gates/`，或把 `chk` 的 name 宽度加大/加短标签；报告注"142 = 132 named + 10 snap_take"。

**低-2 REPORT/DESIGN 行号漂移**：`REPORT.md §3` 的 `:310`（实际 352-353）、`:4630`（实际 4601）、`:4797`（实际 4824）；DESIGN 的 `:443/:633/:442/:601-608` 等是 P1 前 0x2A 行号。设计纪律是"符号引用"，建议报告也用符号（模块/instance/信号名）或标"现读于提交时"。

**低-3 文档重复/陈旧**：`P7B_BIZ_WINDOW.md` 的"逐代回溯"两段连续重复；`final_state.sh:12-15` 同类；`run_tb_biz_win.bat:24`/`run_xvlog_wrapper.bat:34` 报错仍写 "not 76-word"；`u_pcie_regs` 的 `.SNAP_NW` 注释首行仍写 "76 = …"。

**低-4 `check_window.py` 判据 4 的 oracle 是 `HEAD`，提交后空转**：`check_window.py:199-200` 用 `git show HEAD:board/wrapper_p4.v`；现在 HEAD 已是新树，输出"HEAD 48 项 = 新表 48 项 => 新增 0 项"，不能证明 0x2A→0x2B 的旧字未移位。建议改为冻结锚（上一代 wrapper 副本或记录项表）。

**低-5 新 `axi_regs.ch0_snap_to` 端口在独立 TB/小 top 未连**：`_proj_pcie/tb/tb_axi_regs.v:59`、`_proj_pcie/rtl/pcie_min_top.v:139`、`agent_docs/int_scratch/tb_int_axr36.v:67` 均未连接；它们不在当前 20 门/任何门里，Verilog 会默认 0（旧判据可能仍过），但违反"新端口所有例化都连"的纪律。建议逐个连 `1'b0` 或注明"本 TB 不覆盖 bit7"。

**低-6 历史 TB 的旧 stub force 名会失效**：`_proj_10g/notes/p7b_chain_cov/tb_head.v:1256-1257,1312` 仍 `force u_dut.u_pcs.blk_lock/hi_ber`（旧名），stub 拆分后若有人直接跑该历史 TB 会 elaboration/force 失败；它不是门，但属"历史件与新 RTL 脱节"。建议加注释/归档标记。

**低-7 W80 的 32 位回卷口径数字用错**：DESIGN §2.3 写 "32 位计数器 @156.25 MHz 27.487 s 回卷"——27.487 s 是每拍 +1 的计数器（W5/W24 类）；W79/W80/W81/W82 是帧/字节/事件计数：W80 在 10 Gbps 下 ≈3.44 s 回卷，1 Gbps 下 ≈34.4 s。S-5 的 10 min 低速率窗口会多次回卷。建议按每个计数器的增量率写回卷期；差值一律 mod 2³² + 记原始/k。

**低-8 本轮新增文件数/边界表述**：TL 抽核 #12 "p7b_chain 5 件"实为 6 个新文件；`REPORT.md §4` 的"全部日志在 gates/"同低-1。

**低-9 未登记项**：`P7B_OPEN_ITEMS.md` 未随本轮更新；建议把"check_window 红 / SNAP_STATUS[7] 读侧未同步 / tx_ovl 仅 elaborate / W77-W81 行为覆盖缺口 / backstop B3 缺口 / S-1 饱和空判据"登记为 P1 板级轮前置或 OPEN_ITEMS（用户既有"解不了就记到单独文件"的指示）。

## 3. 门质量评估

### 3.1 G1（142/0）新增 36 条判别力

- 有判别力的：P1-1a/1b（W76 真状态；若 tie 0 必红）、P1-2a/2b（W79/W80 计数）、P1-3a/3b（tready=0 下 W79 平/W82 升，强）、P1-4a/4b（LOS 只数上升沿，强）、P1-5a..5d（停钟双代 + 恢复，强）、P1-6a/6b（ch0 TX 常量 IDLE，强）、组 7 的 7 个字地址-值（防槽错位/回绕，强）、MIR_STATUS @0x16C（几何下移，强）、0x17C SLVERR（边界，强）。
- 判别力不足的：P1-2c/2d 只证明好帧下 W81/W82=0，不能证明 W81 的增/坏帧排除（中-3）；W77 事件只 force 计数器，不测更新逻辑（中-3）；ch0 tap 内容/字节序未验（只计数）。
- 负对照/变异：P1 新增臂没有 `P7B_MUT` 变异证明；G4 是同一批臂的复制，不是独立 oracle。⇒ "新增 36 条有牙"目前是逐条推理 + 少数内置反例，不是变异证明。

### 3.2 G4（29/0）

- 18 条具名：模式/真状态/W39 独立性/好帧计数/坏帧不计/tready=0/LOS/超时/恢复/TX 常量；覆盖面 = P1 的 happy path + 关键负例（4a、5a、6a）。
- 11 条 `snap_take` 硬超时：每次 `checks++`，不打印 PASS；是"窗口必须完成"的硬断言，不是 11 条独立功能判据。报告"29 判据"宜注为"18 named + 11 snapshot-completion"。
- 缺口同 G1：无坏 FCS/`/E/`/W77 更新臂；无模式 B/硬门臂。

### 3.3 G3（20/20 FROZEN）

- 第 20 门 = `p7b_chain`；manifest **49 文件**；`manifestcheck` 通过；`paths.txt` 指纹 glob 已含 `run_*.bat`/`tb_*.v`；全矩阵 20/20、gates failed 0。
- FROZEN 绑定：内容摘要 37851074… 与 HEAD 3d4ce8ad 的 296 文件逐字节重算一致【已证·复算】。日志的 `GIT_HEAD=dbbbe1e7` 是提交前 HEAD；运行时的 7 个 M 文件 = 本轮实现面。⇒ "FROZEN 绑定本提交内容"成立；汇报时应写"content-bound to 3d4ce8ad, log HEAD=parent"。
- 矩阵不含 `check_window.py`、`tb_biz_win`、`p7b_gate4_*` self-tests、`p6e` 双门；这些是常驻/手工门，本轮未全跑（高-1）。

### 3.4 读侧门（apply/assert/rehearse/负控）

- apply 阶段表 65 处/17 文件；assert 的 EDIT_COVERAGE 17/17、默认值（BID 0x2B / NW 83 / UNIMPL 0x17C）全一致；rehearse 剩余 0 阶段；负控 table（删 WLABEL 末项）、bid（改 EXPECT_BID）、tier（改档表首行）、face（未登记新文件）各 有牙（RC=1）【已证·日志】。
- 局限：① apply 的原始运行日志未归档（`readside_assert_2B.txt` 是"已在盘上 ⇒ 0 阶段/0 处 edit"的复核，65 处来自阶段表）；② 文本断言不运行 checker（高-1 的逃逸）；③ `p6b_accept.sh` 未同步（高-2）。

### 3.5 G5（4/4）与无门区清单

G5 覆盖 `P7B_10G × PCIE_OBS` 四组合，elaboration 零错【已证·日志】。**无门区**（本审查所见）：

1. `check_window.py` 静态装配核对（现红，且不在矩阵）。
2. `tb_biz_win` + `run_tb_biz_win.bat`（axi_regs 单元门，不在矩阵，本轮未跑）。
3. `SFP2_MODE_A` / `SFP2_MODE_B` 硬门与"构建实际 A=1 组合"（G5 只 P7B×PCIE）。
4. `TCP_TX_OVL` 的 `tcp_tx_frame` 行为（chain 门只 elaborate；tx_ovl 变异门未修）。
5. W77 事件计数器的更新/饱和与 vcc 自由计数（只 force 计数器）。
6. ch0 的坏 FCS（W81）、`/E/`（terr 排除）、W80 坏帧排除（无臂）。
7. ch0 tap 的内容/字节序（只计数；ch1 同模块有内容门，ch0 实例无内容门）。
8. 快照超时的精确时长（4095 拍）——只验证"在 12000 iteration 内完成"，不验证时长。
9. `SNAP_STATUS[7]` 的读侧显示/构造性负控（高-2）。
10. `p6e_snap_selftest_fix2.sh` / `p7b_gate4_selftest.sh` 的 self-test 本轮未跑（readside 只检查其表长/地址条数）。
11. 独立 `tb_axi_regs` / `pcie_min_top` 的新端口连接（低-5）。

## 4. 偏离 / 未测复核（REPORT §6）

| REPORT §6 项 | 复核 |
|---|---|
| W77.vcc 自由计数（不饱和） | 源码 `wrapper_p4.v:3957` `if (pcs0_vcc_sr[2]) pcs0_vcc_cyc <= +1`；与设计一致【已证·源码】。后续影响：只作活动指示，S-1/S-5 不应对它断言；W77 其余三通道的饱和空判据见中-4。 |
| G4 SOP-2 口径（F4 窗口外） | 源码在；语义改变属实；F4 内 2 个裸 SOP 有 DIAG 读数（SOP 55 / TLAST 53 / TERM 2）；`vlan_strip` 的 SOP 重同步支撑数据面安全【已证·源码/日志】；但该 MAC 行为未在设计/OPEN_ITEMS 登记（中-2）。 |
| chain TB 6 处健壮化 | ① `snap_take` 12000 + 硬超时（`tb_p7b_chain.v:2209-2233`）；② TX 捕获 16384→65536（`:485-495`）；③ group6 负沿 force（`:1342-1360`）；④ SOP 重置 `got_len`（`:412-418`）；⑤ G4 前 drain（`:2170-2176`）；⑥ G4 SOP-2 限定 F4 外（`:2186-2195`）。逐条在；④⑤不改变 DUT 判据语义，①③是 timing/robustness，⑥是唯一语义改变。 |
| p6e MIR 降序 token | `tb_p6e_pcie_wrapper.v` 的 MIR 地址现为 0x16C/0x170/0x174/0x178；W76..W82 读 0x150..0x168；0x17C SLVERR；地址映射与 83 字几何一致【已证·源码/日志】。注释仍有 "75 字/0x15C" 陈旧字（低-3）。 |
| `tb_biz_win` 加 `ch0_snap_to(1'b0)` | `tb_biz_win.v:72` 在；`NW=83`、`MIR_*` 由 NW 派生、`UNIMPL=0x17C`【已证·源码】。该门本轮未跑（无门区 #2）。 |
| 读侧 3 TB 手工同步 | p6e wrapper/counters、chain TB 已同步（p6e 日志 BID 0x2B / W76..W82=0；chain 全链过）；`tb_biz_win` 由 apply 脚本 E16 编辑（非手工）。【已证·源码/日志】 |
| 未测（构建/板级/HLS/乙/BER/停钟/最小集） | 与 DESIGN §13 一致；本轮新增应登记：check_window 红、bit7 读侧、tx_ovl 行为、W77-W81 覆盖、backstop B3 缺口、S-1 饱和（见 §2）。 |

**"p6e MIR 降序 token"风险复核**：替换后 `0x150..0x168` 是 W76..W82 真字（非 P7B 时为常量 0），MIR 四字在 0x16C..0x178；`0x17C` 是首个未实现地址。p6e 的 `M1-4` 循环读 83 字、`M1-5a` 读 0x17C、`P9-B-2c` 读 0x178，均与地图一致；未发现"把快照字当地址搬走"的错位【已证·日志】。

**ch0 tap 只读性复核**：`wrapper_p4.v` 的 ch0 新增只消费 `rx_mii_d_0/c_0`（`:999-1000`），ch0 TX 仍是 `p7b_ch0_idle_d/c`（`:639-646`）常量 IDLE；ch1 数据面未改；ch0 MAC 的 `stat_*` 只作为 W81/W82 的源；`ch0_rx_tready=1` 是真消费者。⇒ 只读【已证·源码】。未覆盖：ch0 tap 的内容/字节序（只有计数）。

## 5. 构建风险与 backstop 复核

- **FP/资源（纸面，源码计数）**：DP 域 ≈ 96（p7bdp hold_b 3 字）+ 69（PCS 3FF）+ 3（sig）+ 32（W77 事件）+ 24（LOS）= **224**；`rx_clk_out_0` 域 ≈ 128（ch0 4 字 hold_b）+ ~40（sink）≈168；pcie 域 ≈ 448（7 字 × dout_a + snap_words_r）+ ~20（超时/锁存）≈468；`mac_rx_10g` 第二实例 ≈ +1453 LUT / +911 FF（OOC 上界）。总量 ≈ +1.5k LUT / +1.8k FF / +0 BRAM（纸面）。
- **时序**：0x2A 全局 WNS `+0.039` = 0.61%（DP setup 宿主）；本刀 DP +224 FF、pcie +448 FF，预测不可给。构建轮重点看：① DP top-10 是否出现 `u_snap_p7bdp/hold_b_reg[*]`、`pcs0_*_sr`、LOS 计数；② pcie 快照阵列异步复位族是否重返全局宿主（0x28 先例）；③ `report_clock_interaction` 是否把 `rx_clk_out_0` 束当异步（`ku5p_p7b_cdc.xdc:18-39` 的 `gtrefclk0 -include_generated_clocks` 预期覆盖，【推断】）；④ `12-4739` 0 命中。
- **backstop**：B1（删 W77 ⇒ 82/0x178）、B2（删 W79..W82 + ch0 MAC ⇒ 79/0x16C）、B3（删 W77/W79..W82 ⇒ 78/0x168）算术正确、每档=新输入；但 B3 仍保留 W76+W78 的 ~192 DP FF（见中-5）。建议构建前在 §10.3 写明"B3 后仍失败 ⇒ abort-to-P0"，或加 B4（PCS 只留 blk/hi_ber + LOS 只留电平）。
- **构建前置**：`board/build_p7b_ku5p.tcl:286` 是唯一的 `set_property verilog_define`，追加 `SFP2_MODE_A=1` 的指令正确（`UDP_TX_OVL/TCP_TX_OVL` 在同一条，必须追加不覆盖）。构建脚本 `import_files ${script_dir}/wrapper_p4.v`（`:114`）用的是 `board/` 树，不是 `vivado_prj/.../imports/board/wrapper_p4.v`（该副本仍是 0x2A）⇒ 走 `run_build_p7b_ku5p.bat` 安全；GUI 重编 `vivado_prj` 仍会踩旧副本陷阱（已知）。
- **构建宏组合**：`SFP2_MODE_A=1` 这个实际构建组合未被任何门 elaborate（中-6）；构建前建议先跑一次 `-d SFP2_MODE_A` 的 elaboration（G5 增 combo），以免构建时才暴露未知宏路径。
- **构建风险登记**：DP 余量 0.61% + 224 DP FF 是本刀最大风险；若失败，先看 DP/hold_b 族；backstop 的 B1/B2 不覆盖该族（中-5）。

## 6. 一句总评（不写 PASS/FAIL）

**可进入构建 0x2B（本审查未见 RTL 主体/结构/几何阻断；G3 的 FROZEN 内容摘要与 HEAD 逐字节复算一致；ch0 tap 只读、快照超时、W76..W82 槽位与几何均有源码+日志支持）；但读侧两项高（`check_window.py` 9 FAIL/RC=1；`SNAP_STATUS[7]` 未进入任何读侧工具）须在 P1 板级轮前修复并补门；G4 SOP-2 的语义放宽、TCP_TX_OVL 替代门仅 elaborate、W77/W80/W81 行为覆盖缺口、S-1 饱和空判据、backstop B3 缺口应与用户/设计所有者协调/登记后再收口。**

---

## 回报四项

- **分级计数**：阻断 0 / 高 2 / 中 7 / 低 9。
- **最重要 3 条**：① `check_window.py` 读侧静态核对器 TRUE_RC=1 / 9 FAIL（判据 3/5a/5c 未随 ch0 段更新）；② `SNAP_STATUS[7]` 没有进入任何读侧工具（中-19 只落实 RTL 半边）；③ `TCP_TX_OVL` 的"替代门"只 elaborate、不驱动 `tcp_tx_frame`，`run_tx_ovl_gate.bat` 仍未修。
- **事实核不一致项数**：材料级 4 项（diff stat 29/+1297/−288 vs 实际 57/+10041/−289；中-19"采纳"未落实；tx_ovl "exercised"实为 compile-only；读侧"0 fail"不覆盖 check_window 红）+ 标注级 8 项（行号漂移、G1 摘录、重复注释、陈旧报错文字等）。
- **无门区清单**：① `check_window.py`；② `tb_biz_win`/`run_tb_biz_win.bat`；③ `SFP2_MODE_A/B` 硬门与构建 A=1 组合；④ `TCP_TX_OVL` 的 `tcp_tx_frame` 行为；⑤ W77 更新/饱和与 vcc；⑥ ch0 坏 FCS/`/E/`/W80 坏帧排除；⑦ ch0 tap 内容/字节序；⑧ 超时精确时长；⑨ `SNAP_STATUS[7]` 读侧显示/负控；⑩ `p6e_snap_selftest_fix2.sh`/`p7b_gate4_selftest.sh` self-test；⑪ 独立 `tb_axi_regs`/`pcie_min_top` 的新端口连接。

*本件 = 独立红队审查（只读）。不含 PASS/FAIL 裁定。「未观测到」≠「不存在」；纸面数字已标"纸面"。*
