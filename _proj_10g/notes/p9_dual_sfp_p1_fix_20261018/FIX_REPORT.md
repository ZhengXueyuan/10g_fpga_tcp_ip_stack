# P11 / P1 修复轮（P1FIX）—— FIX_REPORT

- 日期：2026-10-18 · 角色 = 修复 agent（唯一写者：TL 只写台账/队列）。
- 依据：`_proj_10g/notes/p9_review_p1_impl_20261018/FINDINGS.md`（阻断 0 / 高 2 / 中 7 / 低 9）。
- 施工权威：`_proj_10g/notes/p9_dual_sfp_p1_impl_20261018/DESIGN_v5.md`（本轮加 **v5.1 修订注 + §15 变更表**）；实施报告 = 同目录 `REPORT.md`（本轮 v1.1 注）。
- 范围：**验证层与文档缺口**。⛔ **RTL 功能零改动** —— `board/wrapper_p4.v` 只改了一条注释（`.SNAP_NW` 的 `76 → 83` 说明）；`_proj_pcie/rtl/axi_regs.v`、`board/p7b_pcs_stub.v` 未动。
- 纪律：不跑 Vivado（`tasklist | grep vivado` 无进程）；xsim 门已跑；不碰板/对端/烧录；不改 `D:\repo\perfv`；不写密码；**未做任何 git 写操作**（无 add/commit/push/checkout）。
- 状态词 =【已证·源码】/【已证·日志】/【推断】/【未判定】/【未测】；「未观测到」≠「不存在」；纸面标“纸面”。本件**不下 PASS/FAIL 裁定**。

## 0. 摘要

**修复项计数：高 2/2 · 中 7/7 · 低 9/9**（低-4 已并入高-1 的判据 4 修复；低-9 以 OPEN_ITEMS 新增 §0-58…§0-67 形式落地）。

| 门 | 读数（本轮） | 日志 |
|---|---|---|
| `check_window.py` 正跑 | **PASS=108 / FAIL=0 / INFO=1 / RC=0** | `gates/check_window_pos.txt` |
| `check_window.py` 负控 drop/swap/declpatho | **各 RC=1**（7 / 6 / 8 条 FAIL） | `gates/check_window_neg_*.txt` |
| `tb_biz_win`（axi_regs 逐字读回，NW=83） | **PASS_ALL / 40 项 / TB_BIZ_WIN_PASS** | `gates/tb_biz_win.txt` |
| 新矩阵门 `biz_win`（pre-check，`-only`） | **EXIT=0**（21 门声明生效） | `gates/G3_matrix_only_bizwin.txt` |
| G1 全链（`run_tb_p7b_chain.bat`，含新 4 条 ch0 臂） | **161 checks / 0 fail / VERDICT = PASS**（143 具名 + 18 `snap_take`） | `gates/G1_chain_2B_fix_full.txt` |
| G4 单元门（`run_tb_p1_ch0_unit.bat`） | **29 checks / 0 fail / UNIT VERDICT = PASS** | `gates/G4_unit_2B_fix_full.txt` |
| G5 elaboration（4 宏 + 3 SFP2 mode） | **7/7：c1–c5 OK；c6/c7 EXPECTED-FAIL（签名命中）；ELAB_4COMBO_PASS** | `gates/G5_elab_7combo_fix.txt` |
| 读侧 assert / rehearse | **OK / 0 fail；REHEARSE OK（剩余 0 阶段）** | `gates/readside_assert_2B_fix.txt` · `gates/readside_rehearse_2B_fix.txt` |
| 读侧负控 table/bid/tier/face | **4/4 有牙，各 `NEGCTL_EXIT=1`** | `gates/readside_negctl_*_2B_fix.txt` |
| 读侧 bit7 负控（假板子 `FAKE_STALE=1`） | **OK=19 / BAD=0**（`[FAIL] 5.-1` + stale 告警 + 非零退出） | `gates/G6_gate4_selftest_bit7.txt` |
| `p6e_snap_selftest_fix2.sh`（假板子 freq 伪影自证） | **OK=19 / BAD=0 / RC=0** | `gates/G7_p6e_selftest_fix2.txt` |
| 矩阵 21 门 | **Run 2 = 21/21 EXIT=0 · gates failed 0 · FROZEN（308 文件）· RC=0**；Run 1 = 20/21（`unit_vlan` 瞬态，见 §3-8） | `gates/G3_matrix_21_fix_run2_full.txt` · `gates/G3_matrix_21_fix.txt` |
| G1 全文归档（旧轮 ignored workdir） | 归档 + sha256（142 = 132 named + 10 `snap_take` 已复核） | `gates/G1_chain_2B_full_archived.txt` |

## 1. 逐条修复对照

### 1.1 高（2/2）

| FINDINGS | 改了什么 | 文件（符号/行号 = 现读） | 门读数 |
|---|---|---|---|
| **高-1** `check_window.py` 红（TRUE_RC=1 / PASS=95 / FAIL=9）且不在任何门 | ① 判据 3 束宽等式加 `SNAP_CH0_NW`（`14+22+3+(39-4)+5+4=83`）；② 判据 5a 顶端 4 项 = `ch0snap_dout[3..0]`、其下 `p7bdp[38..26]`；③ 判据 5c 拆三形态：W51..W75 走 `biz_wN`、W76..W78 走 `ch0_pcs_status/evt/los_bundle`、W79..W82 走 ch0 束槽 0..3（装配项下标 = `82-word`，拼接下标 = `3-slot`）；④ 判据 4 oracle 改**冻结锚** `FROZEN_2A_ITEMS`（0x2A 41 项，来源 `git show 3d4ce8ad^:board/wrapper_p4.v`，不再依赖 HEAD ⇒ 提交后不再空转）；⑤ 注册为**矩阵第 21 门** `biz_win`（含 `tb_biz_win` + 一次 drop/swap/declpatho 负控） | `_proj_10g/notes/p7b_biz_win/check_window.py`（判据 3/4/5a/5c + 冻结锚）；`_proj_10g/notes/p7b_biz_win/run_gate_biz_win_check.bat`（新）；`sim/p4gates/run_matrix_p4dfix.bat`（`call :gate biz_win`）；`sim/p4gates/bizwinsrc.f`（新）；`sim/p4gates/paths.txt`（指纹 globs 加 `p7b_biz_win`） | 正跑 PASS=108/FAIL=0/RC=0；三负控各 RC=1；矩阵 `-only biz_win` EXIT=0 |
| **高-2** `SNAP_STATUS[7]` 读侧未同步 | 四个读侧脚本的 0x1C 解析加 bit7（`ch0_snap_to/ch0_bundle_stale`）+ W79..W82 旁 `stale=1` 告警；`p7b_snap.sh` 打 ch0 字且 stale ⇒ 退出码 3；`p6e_snap_check.sh` 新判据 `5.-1`；`p7b_gate4_accept.sh` 快照文本带 `STATUS` 行 + 判据 `B_CH0`（P1 几何才判）；`p6b_accept.sh` 打印 bit7 解码 + 告警；`p7b_gate4_selftest.sh` 新增 `FAKE_STALE=1` 构造性负控；`P7B_BIZ_WINDOW.md` 增 §1b | `_proj_pcie/p7b_biz/p7b_snap.sh` · `_proj_pcie/p6e_snap_check.sh` · `_proj_pcie/p7b_gate4_accept.sh` · `_proj_pcie/p6b_accept.sh` · `_proj_pcie/p7b_gate4_selftest.sh` · `_proj_10g/notes/P7B_BIZ_WINDOW.md` | 假板子 self-test OK=19/BAD=0（含 stale 分支：`[FAIL] 5.-1` + `SNAP_STATUS[7]=1` 告警 + `W79 stale=1` + 非零退出）；读侧 assert/rehearse/4 负控全绿 |

### 1.2 中（7/7）

| FINDINGS | 改了什么 | 文件 | 门读数/备注 |
|---|---|---|---|
| **中-1** tx_ovl 只做到 elaborate | `tx_ovl_gate_status.txt` 措辞改 **compile/elaboration ONLY**（并写明 chain TB 只 force `txsrc_*`）；`P7B_OPEN_ITEMS.md` 新增 §0-60 “board TCP TX body 无行为门” | `gates/tx_ovl_gate_status.txt` · `P7B_OPEN_ITEMS.md` | 文档面；G1 只作 elaboration 见证（不声称行为覆盖） |
| **中-2** MAC 单 `term_pend` 多裸 SOP | DESIGN §13-11 登记 MAC 行为 + G1 DIAG 的 2 实例（SOP 55 / TLAST 53 / TERM 2）+ `vlan_strip` 重同步依据；G4 增 `[G INFO] unclosed SOP inside F4 windows`（信息量，不作 PASS/FAIL） | `DESIGN_v5.md` §13-11 · `tb_p7b_chain.v`（G4 DIAG 段） | G1 输出 `[G INFO] unclosed SOP inside F4 windows = 2 (rx_open_n=2 - rx_bare_n=0)`；不参与 161 checks |
| **中-3** W77/W80/W81 行为覆盖缺口 | G1 新增 4 条臂：P1-2e/f/f2（坏 FCS ⇒ W81+1、W79/W80/W82 平）· P1-2g/g2/g3（`/E/` ⇒ W79/W80/W81/W82 平；TB `fcs_incl_er=1` 把 `/E/` 字节纳入 FCS ⇒ `tcrs=1`，只测 `!terr`）· P1-2h（`ferr_0` 40 dp 拍 ⇒ ΔW77[31:24]=41；`bad_code` 20 拍 ⇒ ΔW77[23:16]=21；`rx_error_valid` 20 拍 ⇒ ΔW77[15:8]=20；ferr 320 拍饱和到 0xFF 不回卷；vcc mod 256 变化=52）· 另：**`badv` 的 RTL 真值是 `bad_code`（level），不是 `bad_code_valid`** —— 见 §5 | `_proj_10g/p7b_chain/sim/tb_p7b_chain.v`（P1-2e/f/g/h） | G1 **161/0 PASS**（原 142 → +19 = 11 具名 + 8 `snap_take`） |
| **中-4** S-1/S-5 饱和空判据 + S-4 脆性 | DESIGN §10.4：S-1/S-5 主判据改 **`W77[31:8]` 绝对值为 0**（Δ 只作副证）；S-4 改 **`W78[23:16]` ≥1 + 记录实际值**；LOS 事件加最小间隔/去抖口径（>3 dp 拍 = 3FF 可分辨率） | `DESIGN_v5.md` §10.4 | 文档面（板级轮执行） |
| **中-5** backstop B3 缺口 | DESIGN §10.3 加 **B4**（W76 只留 blk_lock/hi_ber、W78 只留 LOS 电平；NW 不变只减位）· **B3 后仍失败 ⇒ abort-to-P0（整轮回退）** · 构建轮 DP 定向观察点（`u_snap_p7bdp/hold_b_reg[*]` / `pcs0_*_sr` / LOS 计数） | `DESIGN_v5.md` §10.3 | 文档面；OPEN_ITEMS §0-62 |
| **中-6** SFP2_MODE 无 elaboration 门 | `run_elab_4combo.bat` 4 → **7 combos**：c5 = `-d SFP2_MODE_A`（**构建实际组合**）必须 OK；c6 = A+B 必须 FAIL（签名 `SFP2_MODE_A_AND_B_CONFLICT`）；c7 = B 且无 P7B 必须 FAIL（签名 `SFP2_MODE_B_REQUIRES_P7B_10G`）；expected-fail 同时判“非零退出 + 签名命中” | `_proj_10g/p7b_chain/sim/run_elab_4combo.bat` | **G5 7/7 PASS**（c6/c7 xelab 报文逐字命中，见 §2.5）；附：xvlog 的 define 语法是 `-d NAME`，`-d NAME=VALUE` 会把 `1` 当文件（实测） |
| **中-7** diffstat 不一致 | DESIGN 头/§15、REPORT §0/§8 统一为 **57 files +10041/−289（含 notes/gates）/ 38 +2371/−289（实现面）**；REPORT TL 抽核 #1 已就地保留“提交前 29/+1297/−288 = 另一口径”的说明 | `DESIGN_v5.md` · `REPORT.md` | 文档面；⚠️ **台账 §10-126 / `P11_REVIEW_QUEUE.md` 归 TL 写，本轮未改**（见 §4） |

### 1.3 低（9/9）

| FINDINGS | 改了什么 | 文件 |
|---|---|---|
| **低-1** G1 摘录不完整/口径 | 旧轮全文日志（ignored workdir `sim/p4gates/work_20261018_014051/p7b_chain/xsim_p7bchain.log`）归档为 `gates/G1_chain_2B_full_archived.txt`（sha256 `38fda53f1829027ed109578c07fed3875d4e9a70c680363ca742ae86c7ac7c90`）；REPORT 注 “142 = 132 named + 10 snap_take”（已复核：`grep -c "[PASS]"` = 132，`142-132=10`） | fix 轮 `gates/` · `REPORT.md` §4 |
| **低-2** 行号漂移 | REPORT §3 改**符号引用**并标“提交时现读”；DESIGN 头注声明“行号 = 提交时参考，优先符号名”，并给出实际 `:352-353 / :4601 / :4824` 对照 | `REPORT.md` §3 · `DESIGN_v5.md` 头 |
| **低-3** 重复/陈旧措辞 | `P7B_BIZ_WINDOW.md` “逐代回溯”两段去重；`final_state.sh` 12–15 行重复注释合并；`run_tb_biz_win.bat`/`run_xvlog_wrapper.bat` 的 `not 76-word` → `not 83-word`；`wrapper_p4.v` 的 `.SNAP_NW` 注释 `76 = …` → `83 = …` | 四文件 |
| **低-4** 判据 4 oracle = HEAD | 并入高-1：改冻结锚 `FROZEN_2A_ITEMS`（41 项） | `check_window.py` |
| **低-5** 新端口未连 | `tb_axi_regs.v` / `pcie_min_top.v` / `agent_docs/int_scratch/tb_int_axr36.v` 的 `ch0_snap_to` 显式连 `1'b0` + 注释“本门不覆盖 bit7” | 三文件 |
| **低-6** 历史 TB 旧 stub force 名 | `p7b_chain_cov/tb_head.v` 头部加“历史副本、`blk_lock/hi_ber` 旧名已失效、现役门 = `tb_p7b_chain.v`” | `tb_head.v` |
| **低-7** W80 回卷口径 | DESIGN §2.3 改为按计数器增量率：W80 @10G ≈3.44 s / @1G ≈34.4 s；W79 ≈5305 s（满几何）；W81/W82 按事件率；差值一律 mod 2³² + 记原始/k | `DESIGN_v5.md` §2.3 |
| **低-8** 文件数表述 | REPORT §8 订正 p7b_chain 本轮新增 **6 件**（列出 6 个文件名；`run_tb_p7b_chain.bat` = 修改） | `REPORT.md` §8 |
| **低-9** OPEN_ITEMS 未更新 | 新增 §0-58…§0-67（10 条：check_window / SNAP_STATUS[7] / tx_ovl / W77-W81 覆盖 / backstop B3-B4 / S-1 饱和 / 超时精确时长 / ch0 tap 内容 / self-test 未跑 / MAC 单 term_pend 多裸 SOP）+ 顶注 | `P7B_OPEN_ITEMS.md` |

## 2. 门读数（时间戳 + 本轮独有串 `P1FIX-20261018`）

> 所有读数的**独有串** = `P1FIX-20261018`（本文件 §0–§6 与 `gates/INDEX.txt`）；每条日志的文件 mtime = 本轮时刻（见 INDEX 的 `mtime` 列）。
> ⚠️ 记录约定：读数只作“状态”，不写 PASS/FAIL 裁定（门自身打印的 `VERDICT` 原样引用）。

### 2.1 check_window.py（正跑 + 三负控）

- 正跑：`PASS=108 FAIL=0 INFO=1` · `CHECK_WINDOW_PASS` · **RC=0**。
- `--mutate drop`：RC=1（`总字数 ≠ NW` / `最右项不是 snap_dout` / 冻结锚尾项不符）。
- `--mutate swap`：RC=1（`5a 顶端段` + `5c W81/W82 ch0 束装配`）。
- `--mutate declpatho`：RC=1（`1a 每项字数可解析` / `1 总字数` / `4 冻结锚` / `5b` / `7 declared-before-use`）。
- 新判据 4 的锚内容自证：`git show 3d4ce8ad^:board/wrapper_p4.v` 提取 41 项（2026-10-18 02:4x 现读；提取件已删，锚已冻结进源码）。

### 2.2 tb_biz_win（读侧单元门）

- `PASS_ALL tb_biz_win: 40 项判据全过 (窗口 83 字)` / `TB_BIZ_WIN_PASS` / RC=0。
- 由新矩阵门 `biz_win` 同时驱动；`-only biz_win` 的矩阵 pre-check = **EXIT=0**（21 门声明）。

### 2.3 G1 全链（改 TB 后重跑）

- `==== tb_p7b_chain done: 161 checks, 0 fail ====` · `VERDICT = PASS`。
- 新臂读数（xsim 全文）：`d_ferr=41` / `d_bad=21` / `d_errv=20` / ferr 饱和 `0xFF` / `vcc delta=52 (mod 256)`。
- `[G INFO] unclosed SOP inside F4 windows = 2`（信息量，不计 checks）。
- 归档全文：`gates/G1_chain_2B_fix_full.txt`（770 行；`grep -c "[PASS]"`=143、`[FAIL]`=0）。

### 2.4 G4 单元门

- `==== tb_p1_ch0_unit done: 29 checks, 0 fail ====` · `UNIT VERDICT = PASS`；RC=0。

### 2.5 G5 elaboration（7 combos）

- `[ELAB c1..c4] OK`；`[ELAB c5] P7B=1 PCIE=1 EXTRA=[-d SFP2_MODE_A] OK`。
- `[ELAB c6] EXPECTED-FAIL OK at xelab` + `ERROR: [VRFC 10-2063] Module <SFP2_MODE_A_AND_B_CONFLICT> not found … [wrapper_p4.v:276]`。
- `[ELAB c7] EXPECTED-FAIL OK at xelab` + `ERROR: [VRFC 10-2063] Module <SFP2_MODE_B_REQUIRES_P7B_10G> not found … [wrapper_p4.v:280]`。
- `ELAB_COMBO_FAILS=0 (7 combos: 4 macro + 3 SFP2 mode)` · `ELAB_4COMBO_PASS` · RC=0。
- ⚠️ 实测工具坑：xvlog 的 define 语法 = `-d NAME`；`-d NAME=VALUE` 把 `1` 当文件（`Can not find file: 1`）。已写入 bat 注释。

### 2.6 读侧（assert / rehearse / 负控 / bit7 构造性负控）

- `APPLY_READSIDE_BID OK (target 0x0000002B, 0 阶段 / 0 处 edit, 0 fail)`。
- `REHEARSE OK —— 全绿 … 剩余 0 阶段`。
- table / bid / tier / face：各 `NEGCTL_VERDICT 有牙` + `NEGCTL_EXIT=1`。
- `p7b_gate4_selftest.sh`：**OK=19 BAD=0**；正例含 `[PASS] 6.1` / `[PASS] 5.-1` / `FAIL=0`；负控含 `[FAIL] 6.1` 与 stale 三连（`[FAIL] 5.-1` / `SNAP_STATUS[7]=1` / `W79 stale=1`）且退出码非 0。

### 2.7 矩阵 21 门

**Run 1（2026-10-18 02:59:44–03:28:55）**：21/21 门全部运行；**20 × `EXIT=0` + 1 × `EXIT=1`**。
- 唯一非零 = **`unit_vlan`**：TB 日志逐字 `VLAN_STRIP TB PASS (in=1595 words, out=1502 words, vlan frames=66, stripped=66)`，
  但 `xsim.bat` 返回非零（`xsim_run.log` 记 `run: elapsed = 00:02:44`，异常长 ⇒ 判**工具瞬时故障**候选，不是判据红）。
  **同门经矩阵入口单跑复跑 = `EXIT=0`**（`gates/G3_matrix_only_unitvlan_rerun.txt`）。
- 修订面绑定：`VERDICT: FROZEN -- all 308 hashed files byte-identical across the run`；
  **content digest = `3f3ba871763654814d3f25c810afdb15f500882a9a4e1161d20e6fde3b2e4869`**
  （stored `DIGEST_ALL` = `4af1b9cd…` / `DIGEST_COMPILE` = `c24d6517…`，按日志 NOTE 为 pre-content-v1 口径）。
  `HEAD=4ff38912`（运行期间无源码漂移；本 agent 未在矩阵运行期间改任何指纹内文件）。
- 矩阵 RC = **1**（由 `unit_vlan` 单项拉红；见 §3 残余）。
- ⚠️ 汇总口径：**不许写“矩阵 21/21 全绿”** —— 本轮读数是 **20/21 EXIT=0 + FROZEN**；`unit_vlan` 的失败形态（TB PASS / bat 非零）已登记，单跑复跑 EXIT=0。

**Run 2（补跑，2026-10-18 03:29:59–03:59:20）**：**21/21 门 `EXIT=0`** · `gates failed: 0` · **矩阵 RC = 0**。
- 修订面绑定：`VERDICT: FROZEN -- all 308 hashed files byte-identical across the run`；
  **content digest = `3f3ba871763654814d3f25c810afdb15f500882a9a4e1161d20e6fde3b2e4869`**（与 Run 1 逐字相同 ⇒ 两次运行源码面相同）。
  `DIGEST_ALL`（stored，pre-content-v1 口径）= `4af1b9cd9948dca8c2edca6b90575922afab1e4d064bba5f81a44530daa46acd`；
  `DIGEST_COMPILE` = `c24d6517dab5889c624a93cb8d96639be11b256125d880593ddca5128d429219`；
  `FILES_COMPILE=241` / `FILES_ALL=308` / `HEAD=4ff38912`。
- 全文归档：`gates/G3_matrix_21_fix_run2_full.txt`；stdout = `gates/G3_matrix_21_fix_run2.txt`。
- 结论口径：**矩阵现役读数 = Run 2（21/21 EXIT=0 · FROZEN · RC=0）**；Run 1 的 `unit_vlan` 非零按 §3-8 登记为瞬时故障
  （两次运行 content digest 逐字相同 ⇒ 不是源码差异）。引用矩阵读数时**必须同时登记 Run 1 的 `unit_vlan` 瞬态**（不许只引 Run 2 的 21/21）。

## 3. 残余 / 未测（不许当已答）

1. **`badv` 与 RTL 不符**：FINDINGS 中-3 写 `badv_0` 驱动 W77 的 bad 字段；实测 RTL（`board/wrapper_p4.v` 的 `pcs0_bad_evt` 行）吃的是 **`pcs0_bad_sr[2]` = `stat_rx_bad_code_0`（`bcode_0`，LEVEL）**；`bad_code_valid`（`bcode_v_0`）只进 W76[10]。TB 臂已改为强制 `bcode_0`（`d_bad=21` 通过），`bcode_v_0` 的强制版本作废并留注释。
2. 3 条 ch0 新臂**无 `P7B_MUT` 变异证明**（有牙性目前是“臂内负例 + 期望值由 TB 自算”，不是变异证明）。
3. ch0 tap 的**内容/字节序**仍只计数未验（OPEN_ITEMS §0-64）。
4. 快照超时**精确时长（4095 拍）未测**（只验 12000 周期内完成；§0-65）。
5. `p6e_snap_selftest_fix2.sh` 已补跑（OK=19/BAD=0）；`p7b_snap.sh` 的 stale 分支只做 `bash -n` 语法验证（其行为由同族 `p6e_snap_check.sh` 的假板子负控覆盖，**不等价**）。
6. 构建/板级/HLS/乙/BER 全部**未测**（本轮不碰）。
7. `check_window.py` 的冻结锚 `FROZEN_2A_ITEMS` 是**文本锚**；换代（0x2B 板级验收后）必须整表替换并注明出处 commit。
8. **`unit_vlan` 矩阵瞬时故障（未定位）**：Run 1 中该门 `EXIT=1` 而 TB 日志逐字 PASS，`xsim_run.log` 的 `elapsed=00:02:44`（正常 ~1 s 级）；同门经矩阵入口单跑复跑 `EXIT=0`。**机理未定位**（候选 = xsim 退出码/资源瞬时；不归因给本刀）。⇒ 引用“矩阵全绿”前必须带这一条。

## 4. 构建前置与 backstop 变化

**构建前置（新增/收紧）**：

1. 宏组合：`board/build_p7b_ku5p.tcl` 的 `verilog_define` 追加 `SFP2_MODE_A=1`（甲）。**G5 c5 现已 elaborate 该组合**（此前无门）。
2. 常驻矩阵 = **21 门**（19 + `p7b_chain` + `biz_win`）；`biz_win` 带 3 个 checker 负控。
3. 板级取数纪律：**先读 `SNAP_STATUS`**；`SNAP_STATUS[7]=1` ⇒ W79..W82 不可信（W76..W78 仍是本代）。
4. 构建轮 DP 定向 STA 观察点 = DESIGN §10.3 清单（`u_snap_p7bdp/hold_b_reg[*]` / `pcs0_*_sr` / LOS 计数 / 各事件计数器）。
5. G1 的检查数从 142 变为 **161**；引用旧“142/0”时按历史读。

**backstop 顺序（更新）**：B1（删 W77 ⇒ 82/`0x178`）→ B2（删 W79..W82 + ch0 MAC ⇒ 79/`0x16C`）→ B3（P1-min 仅 W76+W78 ⇒ 78/`0x168`）→ **B4（可选：W76 只留 blk_lock/hi_ber、W78 只留 LOS 电平；NW 仍 78、只减位）** → **仍失败 ⇒ abort-to-P0（整轮回退，不叠加局部删减）**。每档 = 新输入。

**未改**：RTL 功能、构建脚本本体（`build_p7b_ku5p.tcl` 的宏追加指令仍是构建轮动作）、台账/审查队列（TL 面）。

## 5. 文件清单（本轮修改）

**新增**：`_proj_10g/notes/p7b_biz_win/run_gate_biz_win_check.bat` · `sim/p4gates/bizwinsrc.f` · 本目录（`FIX_REPORT.md` + `gates/`）。

**修改（实现/工具面）**：`_proj_10g/notes/p7b_biz_win/check_window.py` · `run_tb_biz_win.bat` · `run_xvlog_wrapper.bat` · `_proj_10g/p7b_chain/sim/tb_p7b_chain.v` · `run_elab_4combo.bat` · `sim/p4gates/run_matrix_p4dfix.bat` · `sim/p4gates/paths.txt` · `_proj_pcie/p7b_biz/p7b_snap.sh` · `_proj_pcie/p6e_snap_check.sh` · `_proj_pcie/p7b_gate4_accept.sh` · `_proj_pcie/p6b_accept.sh` · `_proj_pcie/p7b_gate4_selftest.sh` · `_proj_pcie/tb/tb_axi_regs.v` · `_proj_pcie/rtl/pcie_min_top.v` · `agent_docs/int_scratch/tb_int_axr36.v` · `_proj_10g/notes/p7b_chain_cov/tb_head.v` · `_proj_10g/notes/p7b_gate4_3/final_state.sh` · `board/wrapper_p4.v`（**仅注释**）。

**修改（文档面）**：`_proj_10g/notes/P7B_BIZ_WINDOW.md` · `_proj_10g/notes/P7B_OPEN_ITEMS.md` · `_proj_10g/notes/p9_dual_sfp_p1_impl_20261018/DESIGN_v5.md`（v5.1）· 同目录 `REPORT.md`（v1.1）· 同目录 `gates/tx_ovl_gate_status.txt`。

**副产品（工具重跑再生，非手改）**：`_proj_10g/notes/p7b_biz_win/{xelab_biz.log,xsim_biz.log}` · `_proj_10g/notes/p7b_gate4_tools/selftest/*`（self-test 产物）· `sim/p4sim/matrix_p4dfix.log`。

**语法/边界验证**：全部改动的 .bat = **CRLF + ASCII**（矩阵 bat 内含既存 `⚠️`，非本轮引入）；5 个 .sh `bash -n` 通过；`check_window.py` `py_compile` 通过；新门 `manifestcheck`（绝对 root）= 2 files == manifest。

## 6. 纪律声明

- 未跑 Vivado（`tasklist | grep vivado` = 无）；只跑 xsim/bash/python 门。
- 未碰板/对端/烧录；未改 `D:\repo\perfv`；无密码落盘；**无 git 写操作**。
- 本轮所有读数带 `P1FIX-20261018` 独有串；日志 `mtime` 见 `gates/INDEX.txt`。
- 与 FINDINGS 描述不符之处已如实登记（§3-1 的 `badv`）；未迁就描述改期望。

---
*本件 = 修复轮报告（状态词，不含 PASS/FAIL 裁定）。矩阵读数见 §2.7。*
