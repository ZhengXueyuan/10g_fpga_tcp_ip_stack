# P11 · 0x2D backstop-2 几何/读侧同步轮 —— 交付报告

- 日期：2026-10-18；仓库根 `D:\repo\XCKU5PMini\udp_hls_10g`；开工/收工 HEAD = **`0f4c87a6`**（未做任何 git 写操作）
- 输入（上游）：`_proj_10g/notes/p11_build_0x2D_20261018/retry/README_FOR_TL.md`（0x2D backstop-2 构建轮）+ 台账 §10-148
- 最终几何（**推导值、未板级验证**）：**NW 85（W0..W84）/ `SNAP_P7BDP_NW` 41（仅槽 39/40 = W83/W84）/
  MIR `0x174..0x180` / UNIMPL `0x184`**；W85/W86/W87 已删；`maccnt_sync` 剪除
- 位流（构建轮产物，本 agent 未构建/未烧）：`ecef15f2339435edb70727e6a979b363375be2a0f8bd875d352f63a293b0e76f`
  / 15,431,261 B / `SW_CRC=e7658864` / BID **0x2D**；WNS +0.042 / WHS +0.009 / 三类失败端点 0/0/0
- 纪律：**未跑 Vivado 构建/综合/实现、未烧板、未改 `board/wrapper_p4.v` 与 `board/build_p7b_ku5p.tcl`（0 行 diff）、
  未写 git、未碰 `D:\repo\perfv`**；xsim 与 Vivado 全程无并行；跑门期间零 RTL 写入（本轮所有编辑均为读侧/TB/门/文档面）。
  **本报告与全部读数均不下 PASS/FAIL 裁定**（裁定权在用户/判据所有者）。

---

## 1. 逐项处置

### 1.1 任务 1 —— 设计附录 E 回灌（`DESIGN_v2r1.md`）

| 项 | 处置 | 位置 |
|---|---|---|
| E-6 几何/字表 | ✅ 已追加 **E-6.1**：NW 85 / P7BDP 41 / W83/W84 保留 / W85..W87 删除 / MIR `0x174..0x180` / UNIMPL `0x184`；全部标注"推导、未板验"；`maccnt_sync` 剪除（`=0`，非黑盒） | `_proj_10g/notes/p11_p2a_design_20261018/DESIGN_v2r1.md` 附录 E（E-5 之后） |
| P2-2 判据改写 | ✅ **E-6.2**：① 删除 W85 守恒（`ΔW85 == ΔW79+ΔW0` 及残差式作废）；② ch0 abort 退回 **"未观测到"**（W87 无）；③ ch0 对账 = **W84 + W82（MAC drop）+ 静默窗（两次快照 ≥1 ms 且 `ΔW83=ΔW84=0`）+ `INFLIGHT_MAX_FRAMES=33`**；④ ch1 = **W83 + W21（`tx_stat_abort`）+ 静默窗 + INFLIGHT**；⑤ W86/W85 不可读，不得再进健康指示/上界项 | 同上 §E-6.2 |
| backstop 阶梯 | ✅ **E-6.3** 表：首跑 **−0.013 / 37** → backstop-1（删 W86/W87）**−0.089 / 726（更差）** → backstop-2（再删 W85）**+0.042 / 0/0/0**；位流 sha/SW_CRC/BID；**#94 不归因**（删字与转正无拆刀，只登记、不归因） | 同上 §E-6.3 |

### 1.2 任务 2 —— 读侧默认值/几何（全部 85 / 0x2D / 0x184）

| 文件 | 改动（`0x88/0x2D` → `85/0x184`） |
|---|---|
| `_proj_pcie/p6e_snap_check.sh` | `SNAP_WORDS=85`；UNIMPL 注释 88⇒0x190 → 85⇒0x184；`WLABEL` 删 W85/W86/W87 三行（表长 88→85）；表长注释同步 |
| `_proj_pcie/p7b_biz/p7b_snap.sh` | `NW=85`；头部"现役 = 85 字"；UNIMPL 注释；`NAME[]` 删 `[85]/[86]/[87]` |
| `_proj_pcie/p7b_gate4_negctrl.sh` | 几何头注 85；`V` 数组 88→85 项（W51..W84）；`for i<85`；`shift1 awk -v NW=85` |
| `_proj_pcie/p7b_gate4_accept.sh` | `SNAP_WORDS=85`；UNIMPL 注释；B_CH0 阈值 88→85（保持"低代跳过"的保守语义，见 §4-②） |
| `_proj_pcie/p7b_gate4_selftest.sh` | `SW=85`；新增 `elif [ "$SW" -ge 85 ]` 假字表分支（W61..W84 + `0X184` 未实现）；旧 88/83 分支逐字保留 |
| `_proj_pcie/p7b_gate4_livefake.sh` | `bid` 字典首键 **85 → 0x2D**（88 档保留为历史）；`W` 表 `[0]*37 → [0]*34` |
| `_proj_pcie/p6e_snap_selftest_fix2.sh` | 假板子未实现地址 **`0X17C → 0X184`**（0X17C 现为 MIR_CTRL 真字，由默认 0 覆盖） |
| `_proj_10g/notes/p7b_gate4_3/final_state.sh` | `rd 0x190 → rd 0x184`；注释/EXPECT_BID 注释同步 |
| `_proj_10g/notes/p7b_gate4_criteria/gen_inputs.py` | `NW_FIX=85`；docstring `W0..W84`；逐代链末格 = `85 字/0x2D`（0x184）；`snap_words` docstring |
| `_proj_10g/notes/p7b_affinity/j6_r6fix.sh` | `NW=85`；`GEOM_TIERS` **顶端新增 `"85|0x0000002D|..."`**（旧 `88|0x2D` 档逐字保留） |
| `_proj_10g/notes/p7b_biz_tcpreg/tcpreg_j6.sh` | 同上 |
| `_proj_10g/notes/p7b_biz_win/check_window.py` | `nnew_top 22 → 19`（= 2 + ch0 4 + p7bdp 13）；`np11_top 5 → 2`；5a 标签 `W84..W83`；5c 只断言 W83/W84；docstring 判据 5 同步 |
| `_proj_10g/notes/p7b_biz_win/tb_biz_win.v` | `NW=85`；MIR 常量注释 `0x174/0x178/0x17C/0x180`、UNIMPL `0x184`；末字/未实现/MIR 边界标签同步（地址由 `NW` 派生） |
| `_proj_10g/notes/p7b_biz_win/run_tb_biz_win.bat` | 指纹 `SNAP_NW_P6E = 85`（注释 88/83/76/75/71 历史） |
| `_proj_10g/notes/p7b_biz_win/run_xvlog_wrapper.bat` | 指纹 `SNAP_NW_P6E = 85` |
| `sim/p5wu_p1p2/run_xvlog_wrapper63.bat` | 指纹 `SNAP_NW_P6E = 85`（沿用既有"跟现役 wrapper"约定） |

`apply_readside_bid1c.py`：
- **0x2D 阶段改为最终几何**：`STAGES` 元数据 `("0x0000002D", EDITS_2D, "... backstop-2 ...", 85, 0x184)`；
  `EDITS_2D.extend([...])` 追加 **71 笔显式增量**（**旧侧 = 0x88/0x2D 状态**，历史注释逐字保留）；
  生成器 = `gen_edits_backstop2.py`（逐行 diff 基线副本 ↔ 现磁盘；文件内内存重放 == 现磁盘）。
- `--assert --bid 0x2D` = **0 fail**（`APPLY_READSIDE_BID OK`；EDIT_COVERAGE 21/21）。
- 负对照 `--negctl=table|bid|tier` = **三者均有牙**（RC=1，目标断言在 FAIL 名单里）。

### 1.3 任务 3 —— 链 TB / 静态门

| 文件 | 改动 |
|---|---|
| `_proj_10g/p7b_chain/sim/tb_p7b_chain.v` | 几何块改为 85：**W83 @0x16C / W84 @0x170** 非 DUAL tie-off = 0；**MIR_STATUS @0x174**；**`0x184 reads 0` + SLVERR**；删除 W85/W86/W87 的读断言与地址；旧 `0x190` 活断言已清（仅新断言文案里保留"原 88 字/0x190"说明） |
| `_proj_10g/p7b_chain/sim/check_snap_top5_wired.py` | `TOPN = 2`；顶部期望 `p7bdp_dout[40..39]`；din 期望 `p7bdp_din[39..40] = w83_dp/w84_dp`；tie-off 只查 83/84 各 2 处；无 `w8x_snap` 断言保留 |
| `_proj_10g/p7b_chain/sim/run_tb_p7b_chain.bat` | 首步注释同步 TOPN=2（门本体未改） |
| `p7bchain_src.f` / `paths.txt` / 12 个 `*_src.f` | **无需改**：未增删编译单元/文件；矩阵 `manifests=12` 且各门 `manifestcheck` 全过（见 §3） |

静态门负控（`--root` 指向临时副本，不改仓内）：
- **旧 88 形态**（顶部恢复 5 项 43..39）⇒ `SNAP_TOP5_STATIC_FAIL (top2)`，RC=1
- **0x2C 直连形态**（顶部插 `w83_snap` + `wire w83_snap = w83_dp`）⇒ `SNAP_TOP5_STATIC_FAIL (top2,direct-wire)`，RC=1
- 正例 ⇒ `SNAP_TOP5_STATIC_PASS`，RC=0

### 1.4 任务 4 —— 文档口径

- `_proj_10g/notes/P7B_BIZ_WINDOW.md`：顶部 2026-10-18 块改写为 **"W85..W87 在 0x2D backstop-2 删除（不可读）；W83/W84 保留"**；
  W83/W84 行标"保留"、W85/W86/W87 行**划删除线 + 不可读**；F-21 静态门 → TOPN=2/槽 40..39；
  未实现地址 → `0x184`；逐代回溯链补 `0x184/0x188`。
- `_proj_10g/notes/P7B_OPEN_ITEMS.md`：新增 **§0-74**（汇总表行 + 顶注）：
  0x2D 观测缩水 + P2-2 判据改写 + **需用户知悉**；并订正 §0-66 的 fix2 fake board 几何为 85/0x184。

---

## 2. 读侧重放 / 断言证据（逐字节）

- **基线快照**：`gates/BASELINE_0x88_0x2D_SHA256.txt` —— 19 个文件，全部为**开工前磁盘状态**（0x88/0x2D）；
  ⚠️ `run_xvlog_wrapper.bat` 的基线按**磁盘 CRLF** 重建（`git cat-file` 的库内 blob 是 LF，不等于开工磁盘态；如实登记）。
- **重放**：`replay_check.py` 从 `apply_readside_bid1c.py` 导入 `EDITS_2D` 的尾部 71 笔（并断言 == 生成的 frag），
  按 apply 引擎同款行尾规则应用到基线副本，再与**现磁盘**逐文件比对：
  **`REPLAY BYTE-IDENTICAL (19 文件; 0 差异)`**（`gates/REPLAY_0x88_0x2D_TO_85.txt`，20:55:32）。
- **默认值断言**：`gates/APPLY_READSIDE_ASSERT_0x2D.txt`（20:55:38）：
  `APPLY_READSIDE_BID OK (target 0x0000002D, 0 阶段 / 0 处 edit, 0 fail)`；
  `EDIT_COVERAGE (本阶段 EDITS 文件 21 / 有对应断言 21)`。
- **负控**：`gates/APPLY_READSIDE_NEGCTL_{table,bid,tier}.txt`（20:52）—— 三条 `NEGCTL_VERDICT 有牙`，RC 全 1。
- **最终读侧哈希**：`gates/FINAL_READSIDE_SHA256.txt`（20 文件，含 `apply_readside_bid1c.py`）。
- **diff 原件**：`gates/READSIDE_DIFF_0x88_to_85.txt`（19 文件、基线→现磁盘统一 diff）。

---

## 3. 门读数（独有串 + 时刻；日志均在 `gates/`）

| 门 | 时刻 | 独有串 / 读数 | 结果 |
|---|---|---|---|
| 静态门（正/负控） | 20:33 | `SNAP_TOP5_STATIC_PASS`（RC=0）· `SNAP_TOP5_STATIC_FAIL (top2)`（RC=1）· `SNAP_TOP5_STATIC_FAIL (top2,direct-wire)`（RC=1） | 正例通过、两条负控有牙 |
| **biz_win** | 20:37 | `PASS=110 FAIL=0 INFO=1` · `CHECK_WINDOW_PASS` · 3 个 `--mutate` 负控全 RC=1 · `PASS_ALL  tb_biz_win: 40 项判据全过 (窗口 85 字)` · `TB_BIZ_WIN_PASS` · `BIZ_WIN_CHECK_PASS` | RC=0 |
| **p7b_chain** | 20:38 | `SNAP_TOP5_STATIC_PASS` · `0` 条 `[FAIL]` · `VERDICT = PASS` · `P11 MIR_STATUS @0x174` PASS · `7b 0x184 reads 0 no wrap` PASS · W83/W84 非 DUAL tie-off PASS | RC=0 |
| **G2/G5/G6（单独）** | 20:40 | `gates run 3 / 24` · `gates failed 0` · `VERDICT: FROZEN`（346 文件）· 三条 `GATE ... EXIT=0` | RC=0 |
| gate4 selftest | 20:42 | `OK=19 BAD=0` · `正例读过未实现地址 0X184` · `section5 序列长度 85` · `W84  0x170` | RC=0 |
| p6e snap selftest fix2 | 20:47 | `OK=19 BAD=0`（初跑 BAD=2：假板子未实现地址仍 0X17C ⇒ 已同步到 0X184 后复跑） | RC=0 |
| gate4 negctrl | 20:48 | `负对照汇总: OK=15 BAD=0` | RC=0 |
| **24 门全矩阵** | **20:40:26 → 21:11:04** | `gates run 24 / 24` · `gates failed: 0` · `VERDICT: FROZEN -- all 346 hashed files byte-identical across the run` · `BEFORE/AFTER` 同 digest（compile `50916dad…`；ALL `7e4e66f7…`）· **content DIGEST_ALL `95a2608b430ba34d6b8af6fd8d0512fcf1f8bd6fa255e2eef150df6646ac7f84`** · `GIT_HEAD = 0f4c87a6` | RC=0 |
| 矩阵内 f3_resync | 同上 | `F3-RESYNC-GATE: PASS` · `J1=1 J2=1 J3eq=1 J3pos=0 J4=1 J5=1 J6=1 ALL=1` | 无瞬态，未做 standalone 记录 |
| 矩阵内 biz_win / chain | 同上 | `PASS_ALL  tb_biz_win: 40 项判据全过 (窗口 85 字)` · `VERDICT = PASS`（chain） | 全绿 |

矩阵输入绑定：`manifests=12`、每门 `P4GUARD OK / manifestcheck` 通过；`FILES_ALL=346` 与上轮同集合。
（本轮的读侧 20 文件与构建轮 `retry/` 不在 `FINGERPRINT_GLOBS`，与 OPEN_ITEMS §0-50 登记一致。）
⭐ **收工复核**：按 `sim/p4sim/P4_MATRIX_FINGERPRINT_20261018_204026_after.txt` 逐条重算
**346/346 个文件 sha256 全部相同（0 差异）** ⇒ 当前工作树与矩阵 AFTER 指纹**逐字节一致**
（唯一例外是矩阵后新写的本报告目录 `p11_sync_0x2D_20261018/`，它不在指纹宇宙内）。

---

## 4. 未同步 / 未测项（如实登记）

1. **板级全部未做**（本 agent 未烧板）：BID `0x2D`、85 字窗口、`0x184=0xffffffff`、MIR `0x174..0x180`、
   W83/W84 相干性、P2-2 新对账式 —— **均为未测**；几何/地址是 `SNAP_LAST_IDX` 推导值。
2. **`sim/p6e_pcie/tb_p6e_pcie_wrapper.v` 的 MIR 测试地址仍是 83 字代**（`0x16C/0x170/0x174/0x178`），
   而该文件自己的注释写的是 88 字代 `0x180..0x18C` —— **这是 0x2C/0x2D 首轮就存在的既存不一致**；
   本轮只同步了它的 **UNIMPL 断言（0x190 → 0x184，两处）** 以让 `--assert` 自洽，**未改 MIR 测试地址**。
   该 TB 不在 24 门矩阵内，本轮未运行；引用其 MIR 判据前必须先按现几何重标（否则会读 W83/W84/MIR 错位）。
3. **`p7b_gate4_accept.sh` 的 B_CH0 阈值 = 85**（保持"低于现役几何即跳过"的保守形态；83 字 P11 P1 虽有 ch0 束
   也会被跳过 —— 这是 88 字时代就有的保守策略，本轮未改变其性质）。
4. **`check_snap_top5_wired.py` 文件名仍含 `top5`**（门标记 `SNAP_TOP5_STATIC_*` 也未改名）—— 为保挂载点/下游引用稳定，
   内部已参数化为 `TOPN=2`；**不是漏改**。
5. **门运行改写了被 git 跟踪的产物**（非源码/非 RTL）：`_proj_10g/p7b_chain/sim/hls_p7bchain.f`（gate 重新生成）、
   `_proj_10g/notes/p7b_biz_win/xsim_biz.log`（gate 输出）、`sim/p4sim/matrix_p4dfix.log`（矩阵日志）、
   `_proj_10g/notes/p7b_gate4_tools/{selftest,fix2,negctrl}/*`（两个 self-test 与 negctrl 的假板/日志/夹具输出，门本体）。
   本轮**未提交、未还原**（按要求不写 git）。`rtl/` 与 `board/` 的 tracked diff = **0**（已核）。
6. **未跑**：`gen_inputs.py`（会写夹具目录；仅做语法/断言覆盖）、`p7b_gate4_livefake.sh` 单独运行、
   `sim/p6e_pcie/tb_p6e_pcie_*` 两个 TB（不在矩阵）、任何 Vivado 构建/综合/实现、任何板级动作。
7. **口径**：本报告不下 PASS/FAIL 裁定；"门全绿"只指这些门的退出码/独有串，不等于产品/时序/板级达标。
   backstop 删字与 WNS 转正之间的因果 **未做拆刀 ⇒ 不归因（全局 #94）**。

---

## 5. 器材地图（本目录）

| 路径 | 内容 |
|---|---|
| `SYNC_REPORT.md` | 本报告 |
| `gates/` | 全部门日志/读数、基线哈希、重放与断言证据、负控 wrapper 副本（`negctl_old88/`、`negctl_direct/`） |
| `baseline_0x88_0x2D/` | 19 个读侧文件的**开工前**磁盘快照（0x88/0x2D；补丁左值） |
| `gen_edits_backstop2.py` | 71 笔显式增量的生成器（基线↔现磁盘 diff + 文件内重放断言） |
| `BACKSTOP2_EDITS.frag` | 生成的 Python 字面量块（已 `EDITS_2D.extend(...)` 进 `apply_readside_bid1c.py`） |
| `replay_check.py` | 从 `EDITS_2D` 尾部重放到基线副本、与现磁盘逐字节比对 |
