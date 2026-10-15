# 构建轮 `0x27` 报告（换流门 R5 修复：BID bump + 读侧同步 + p6e 双门复跑 + 矩阵 18→19 门 + 构建 + 归档 + 定向 STA）

> **agent 原件由平台拒写 .md ⇒ 全文回传、TL 代落盘**（本件正文 = agent 原文；文末「TL 附加」= TL 独立抽核记录）。
> **口径**：本报告**不下 PASS/FAIL 裁定**（裁定权在用户/判据所有者）；给的是读数与形态。「未观测到」≠「不存在」。
> 轮次目录 = `D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_build_0x27\`（**91 件** + `SHA256SUMS.txt`）· HEAD = `dd9c9f0`（全程未提交，改动留工作树）
> **纪律**：⛔ 未烧板 / 未写 QSPI / 未碰对端机；xsim 与 Vivado 全程按序（无并行）；收尾复核 **0 个残留 `xsim.exe`/`xelab.exe`/`vivado.exe`**。
> ⛔ **被验源一字未动**：`rtl/app_pattern.v` = **`be0b5f9c642dcd97bec2c3ffb3beec73d57df22e9e39d3be75a5f46c16d8aa6c`**（R5 冻结修订，收尾现读复核）· `git status --short rtl/` = **空**（`rtl/` 全目录零改动）。
> 被验源两处改点（现读核，RTL 文本层）：`rtl/app_pattern.v:516` `close_send` 追加 `!(SWC_OK && frm_wait)`（裁决 B）· `:1012` 守卫 `!(SWC_OK && (closing || !active))`（裁决 A，替换式）。

---

## ① BID bump + 读侧同步 `--bid 0x27`（阶段 ⑫；24 处 / 14 文件；几何**一字未动**）

### ①-1 唯一被验源改动 = `board/wrapper_p4.v` 的 BID（**+15/−2，单 hunk**）

`git diff --numstat -- board/wrapper_p4.v` = **15 / 2**；`git diff -U0 | grep -c "^@@"` = **1**（`:4326` 起）：

- 活行 **`:4329`**：`32'h00000026` → **`32'h00000027`**（行尾注释 `RFC seq 修复 = 0x26` → `换流门 R5 = 0x27`）；
- 注释块顶部插新块（本轮 = 换流门 R5：裁决 A/B 两处 + 设计件指针 `p9_fix_upok_design_20261014/DESIGN_v2r4.md` + 收尾报告 `p9_impl_upok_20261015/fix_r5/REPORT_FIX_R5.md` + **几何不变 71 字 / 0x14C** + 读侧 `EXPECT_BID` **0x26 → 0x27**（阶段 ⑫ = 24 处 / 14 文件）），旧 RFC 块降级为「⭐ 上一轮」**逐字保留**。
- ⛔ **禁碰区核**：app 寄存器总线静止块（`assign app_reg_addr = 8'h00;` / `app_reg_wr = 1'b0;` / `app_reg_wdata = 32'd0;`）**一字未动** —— 全文件 diff 只有上面那一个 hunk 即证。⚠️ 派单写 `:1319-1322`；该块现读位置随历史轮位移（R5 实施轮在 `:1214` 加了 7 行 ⇒ 整块下移），**内容**核过 = 同一块。
- 行尾纪律：编辑后 `CRLF 4948 / loneCR 0`（未污染）。

### ①-2 读侧同步（先例 = `p9_build_0x26`；⚠️ 工具实际路径 = `_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py`——派单写的 `_proj_10g/tools/…` 不存在，与 0x25/0x26 两轮同款笔误，按先例纠正）

- **生成器 `gen_edits27.py`**：取 `EDITS_26` 的 new 侧（= 盘上现状）当 ⑫ old 侧，**逐条显式**变换（0x26→0x27 值 + 代名「RFC seq 修复」→「换流门 R5」+ 逐代历史链追加）；⛔ 不用 `base()` 通配（26 树注释含大量 `0x1F..0x26` 历史链字面）。
  自检 = **old 侧 24/24 逐字命中盘上现状**；new 侧 **7 条 WARN**（8 位旧值残留）逐条人工核 = **全部是"逐字保留的历史"**（另做 `_review_resid.py` 全表复查：12 条 new 侧提到 `0x26` 的段落全为历史/勘定文本）。
- **`splice_phase12.py`**：**6 锚点唯一命中**（①a `EDITS_27 = []` / ①b `def E12(...)` / ② `STAGES` 追加 `("0x00000027", EDITS_27, "换流门 R5 修复 (2026-10-15)", 71, 0x14C)` / ③ ⑱ 段（E12 块）插到 ⑧ 段前 / ④ 顶部 docstring ⑫ 指针 / ⑤ ALLOW 追加 1 条）⇒ 工具本体 **+103/−2**。

**逐文件 hunk 清单**（`git diff --numstat`；原件 `READ_SIDE_DIFF_NUMSTAT.txt`）

| # | 文件（仓根相对） | +/− | hunk 内容 |
|---|---|---|---|
| 1 | `_proj_10g/notes/p7b_affinity/j6_r6fix.sh` | +2/−1 | `EXPECT_BID` 默认 0x26→0x27 + GEOM_TIERS 顶部插 `71\|0x00000027\|…` 行 |
| 2 | `_proj_10g/notes/p7b_biz_tcpreg/tcpreg_j6.sh` | +2/−1 | 同上 |
| 3 | `_proj_pcie/p7b_biz/p7b_snap.sh` | +5/−2 | `EXPECT_BID` 裸行 + 头部「现役」块顶部插换流门 R5 块 |
| 4 | `_proj_pcie/p6e_snap_check.sh` | +1/−1 | `EXPECT_BID` 默认 + 历史链移一格 |
| 5 | `_proj_pcie/p7b_gate4_accept.sh` | +1/−1 | 同上 |
| 6 | `_proj_pcie/p7b_gate4_selftest.sh` | +4/−4 | 现役注释行 + `FAKE_BID` 活行 + 旧口径行 |
| 7 | `_proj_pcie/p7b_gate4_negctrl.sh` | +3/−2 | 几何注释块顶部插新行（旧行降级为"原句"）+ `echo "BID 0x…27"` 活行 |
| 8 | `_proj_pcie/p7b_gate4_livefake.sh` | +4/−2 | 注释块顶部插新块 + `bid = {71: "0x…27", …}` 活行 |
| 9 | `_proj_pcie/p6e_snap_selftest_fix2.sh` | +1/−1 | `FAKE_BID` 活行 |
| 10 | `_proj_10g/notes/p7b_gate4_3/final_state.sh` | +1/−1 | `EXPECT_BID` |
| 11 | `_proj_10g/notes/p7b_gate4_criteria/gen_inputs.py` | +6/−5 | docstring 几何行 + 夹具自述 + 逐代链 + `BID_FIX` |
| 12 | `_proj_10g/notes/p7b_a3_negctl_20261010/step0_selfcheck.sh` | +2/−2 | 缺省档/默认档两行 |
| 13 | `sim/p6e_pcie/tb_p6e_pcie_wrapper.v` | +1/−1 | **:215** 活行 `chk("2  BUILD_ID (换流门 R5 构建 = 0x27)", v, 32'h00000027);` |
| 14 | `sim/p6e_pcie/tb_p6e_pcie_counters.v` | +1/−1 | **:206** 活行 `chk("0b BUILD_ID (换流门 R5 71-word = 0x27; 原 71-word=0x26(RFC seq 修复) / 0x25(F-3 修复) / 63-word=9)" …)` |
| 15 | `_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py`（工具本体） | +103/−2 | 阶段 ⑫ 全部（声明 / E12 / STAGES / ⑱ 段 24 条 E12 / ⑫ 指针 / ALLOW 1 条） |

**全阶段读数**（原件 = 本目录同名 txt）

| 阶段 | 读数 |
|---|---|
| 预扫（`_scan_newhits27.py`） | 目标 0x27 搜索面 4 族 **388 行 / 192 文件**；**未登记 0 件**（新 ALLOW 一条即覆盖本轮目录 + 生成器/读数件） |
| dry-run | **24/24 `hits=1/1`**；A 表长 5/5 绿（NW=71）；B 4 族 388 命中文件 **未登记 0**；C 24 红 = 待改处；D 覆盖 14/14 |
| rehearse | **全绿 0 fail**（`REHEARSE OK … 0 fail`） |
| negctl ×4（apply 前） | `table` 1 红（表长 70≠71）· `bid` 24 红（含目标）· `tier` 24 红（含目标）· `face` 3 红（合成未登记件被抓）—— **四条全有牙（RC=1）** |
| neg_rehearse（apply 前） | **恰 1 红** = 末条（`step0_selfcheck.sh[BID]`） |
| apply | RC=0 / **0 fail**（`APPLY_READSIDE_BID OK (target 0x00000027, 1 阶段 / 24 处 edit, 0 fail)`）；**14/14 件 SHA256 全变**（`TARGET_SHA_BEFORE_BID27.txt` ↔ `POSTAPPLY_SHA_BID27.txt` 逐条比，0 件未变） |
| assert（after） | RC=0；A 5/5 · B 4 族 **388 命中 0 未登记** · C 全绿 · D 14/14；收尾再跑一次 `ASSERT_BID27_FINAL.txt` = RC=0 |
| face | **380 行 / 192 文件**（未登记 0） |
| post negctl ×4 + 反演重建 | 四条仍有牙（1/1/1/3 红，含目标）；反演重建（new→old，内存态）**恰 1 红**且落 `step0_selfcheck.sh[BID]` |

**几何不变量（派单点名核）**：NW 保持 **71**、未实现地址保持 **0x14C** —— A 表长断言 5/5 绿 + 权威源两侧现读一致。⚠️ 派单写"wrapper `:3266` 现读"；**现读 = `:3273`**（`localparam SNAP_NW_P6E = 71;`，见 ⑥-1）。三个读侧默认哨兵现读 **0x00000027**（`j6_r6fix.sh:76` / `tcpreg_j6.sh:70` / `p7b_snap.sh:74`）。

---

## ② p6e 双门读数（修前 / 修后对）

**修前 = wrapper 已 bump 到 0x27、TB 仍期望 0x26**（= 同步前的同一棵树；TB 同步步骤的"咬合力"见证）；**修后 = TB 同步 0x27**。两次运行间**只差 TB 的两个期望值**（TB 同步由 ①-2 的读侧 apply 同批落盘 —— 与 0x26 轮同一时序：BID bump → 修前跑 → 读侧 apply → 修后跑）。

| 门 | 修前 | 修后 |
|---|---|---|
| **全链门** `run_tb_p6e_pcie.bat` | **143 `[PASS]` / 1 `[FAIL]`**（唯一 FAIL = BID 判据：`= 00000027 (期望 00000026)`）**RC=1** | **144 `[PASS]` / 0 `[FAIL]` / `PASS_ALL`** **RC=0** |
| **counters 门** `run_tb_p6e_pcie_counters.bat` | **25 `[PASS]` / 1 `[FAIL]`**（唯一 FAIL = BID 判据：`= 39 (期望 38)`）**RC=1** | **26 `[PASS]` / 0 `[FAIL]` / `PASS_ALL`** **RC=0** |

**H 段读数两臂逐字相同**（派单点名"若有任何变化 ⇒ 停下报我" ⇒ **无变化**）：`H 读数(灌满后): W26=69 W27=256` · `H 读数(排空后): W30=257 W31=2056 W0=0`。
原始证据：`P6E_{WRAPPER,COUNTERS}_{BEFORE,AFTER}_console.txt` + `_evidence_xsim_p6e_{wrapper,cnt}_{BEFORE,AFTER}.log`。

---

## ③ 常驻矩阵（**18 → 19 门**：新增 `swc` 换流门，照 F-3→G1 先例入册）

### ③-1 门注册（4 处改动，全部在边界内）

1. **新 manifest `sim/p4gates/swcg_src.f`**（6 文件 = `rtl/app_pattern.v` + `head_app_pattern.v` + `tb_p9_swc.v` + `mut/{m6_v1_eq,m6b_closing_drop,m7_guard_swpend}.v`）；
2. **`sim/p9_swc_gate/run_tb_p9_swc.bat`**：照 f3_resync 的注册法 —— ① 改调 `p4env.bat` 取 `REPO_ROOT`（旧 `%~dp0..\..` 自推会让 `manifestcheck` 读不到任何 `%VAR%` 文件 ⇒ "bat carries 0 files"，p5_wrapper/f3_resync 同款坑）+ `p4gate.py selfcheck` 触点；② `P4_WORKDIR` 支持（矩阵里 run 目录落私有 cwd，独立跑仍落门目录）；③ `checkpaths` 声明 manifest；④ **编译步拆分**：五个互斥 DUT 变体各以**恰一条字面 xvlog 行**出现（`USERLIVE`/`USEHEAD`/三条 mutant 行），TB 一次 —— 语义/判据/8 运行定义**一字未改**（改的只是编译行的**写法**与根路径来源）；
3. **`sim/p4gates/run_matrix_p4dfix.bat`**：`call :gate swc … swcg_src.f - -` + 注册注释块（门总数**派生** ⇒ 自动 19）；
4. **`sim/p4gates/paths.txt`**：`FINGERPRINT_GLOBS` 追加 `sim\p9_swc_gate\run_*.bat;sim\p9_swc_gate\mk_mut_swc.py`。

**注册前置自核**（runner 口径，绝对 `--root`）：`manifestcheck` = **6 files == manifest** ✓ · `checkpaths` = 8 paths inside ✓ · `selfcheck` = 0 outside ✓。**先单独跑一次门**（`SWC_GATE_STANDALONE_AFTER_REG.txt`）：8 运行全 RC=0 · `P9-SWC-GATE: PASS` · 编译见证 8 条 RSRC 全对（F/F10/OFF→live RTL；H/H10→head；M6/M6B/M7→三 mutant）。⚠️ 单独跑**未**改 `mut/*.v` 一个字节（gate 运行后 `git status` 里 mut 三件未出现 ⇒ 生成确定性再证）。

### ③-2 19 门 run1（08:34:28–09:00:56）

- **19/19 门 `EXIT=0` · `gates failed: 0`** · **`VERDICT: FROZEN`**（**272 件** before=after **逐位**；`DIGEST_COMPILE=e5376d3e3ace8acd87517b968ad07ef6f4572aa27940f4213be822fb597226bb` / `FILES_COMPILE=221` / `DIGEST_ALL=3240a9639f32276046d39ecd6e6cf077871e563c66d6c7e6c67769178cb634fd` / `FILES_ALL=272` / `HEAD=dd9c9f0`）。
- swc 门在矩阵里：`checkpaths 8 paths` / `manifestcheck 6 files` / `scanlog 1 files, 11 path tokens, 0 outside` / **`EXIT=0`** / console 尾 = `P9-SWC-GATE: PASS`（`SWC_GATE_MATRIX_console.log` 已归档）。
- 归档副本：`P4_MATRIX_FINGERPRINT_20261015_083428_{before,after}.txt` + `matrix_stdout_run1.txt` + `MATRIX_TAIL_run1.txt`。
- **漂移集合核验（vs 0x26 轮基线 `sim/p4sim/P4_MATRIX_FINGERPRINT_20261015_040121_after.txt`；原件 `FP_DRIFT_vs_0x26.txt`）**：
  **CONTENT-CHANGED 恰 4 = `{board/wrapper_p4.v, rtl/app_pattern.v, sim/p4gates/paths.txt, sim/p4gates/run_matrix_p4dfix.bat}`** · **ADDED 恰 8** · **GONE 0**（264 → 272）。
  - 前两件 = 本刀面（BID bump + R5 冻结修订 `rtl/app_pattern.v`）；后两件 = **矩阵注册面**（gate 19 + globs）—— 派单允许项（"矩阵 runner 自身/新门件在指纹 globs 内则一并解释"）。
  - **ADDED 逐条归类**（派单点名）：`sim/p4gates/swcg_src.f`（globs `sim\p4gates\*.f`）· `sim/p9_swc_gate/run_tb_p9_swc.bat`（globs `sim\p9_swc_gate\run_*.bat`）· `sim/p9_swc_gate/mk_mut_swc.py`（globs 同名）· `sim/p9_swc_gate/{head_app_pattern.v, tb_p9_swc.v}` + `sim/p9_swc_gate/mut/{m6_v1_eq, m6b_closing_drop, m7_guard_swpend}.v`（**编译集**（= `swcg_src.f` 声明，而 `swcg_src.f` 自身在 globs 内））⇒ **8/8 全部可解释、逐条落"globs 内 / 编译集内"两类**；**超出该集合的漂移/红 = 0**。
  - ⚠️ **登记一处覆盖缺口**：`sim/p9_swc_gate/runF_dbg_witness.bat`（见证 bat，跟踪件）**不在**任何 globs 内（`run_*.bat` 不匹配 `runF_*`）⇒ 未进指纹。**未修**（此刻改 globs 会作废本轮矩阵的修订绑定）；性质 = 调试辅助件、非门判据载体。**下一轮若要收口 = 加一条 glob 后重跑矩阵**。
- **重基线记录（理由 = 参数 + 门 + 行为；⛔ 不以"指纹变了"充当等价证据）**：① 参数面 = `wrapper_p4.v` BID 0x26→0x27（几何/端口零改动）+ `rtl/app_pattern.v` R5 两处（TB/门层证据见 ② 与 `fix_r5/REPORT_FIX_R5.md`）；② 门面 = 新 `swc` 门（8 运行，自带"实测红集 == 期望红集"内判据）；③ 行为面 = 本轮 p6e 双门 144/0 + 26/0 + 19 门编译本树的 RTL。
- **gate 相位输入完整性**：`INPUT_HASHES_BEFORE_GATES == AFTER_GATES`（**227 件，0 变**）⇒ 26 min 内无其它写入。

---

## ④ 构建 `0x27`（唯一入口 `board/run_build_p7b_ku5p.bat`，一次收口）

**调用式** = `MSYS_NO_PATHCONV=1 cmd /c 'board\run_build_p7b_ku5p.bat'`（**单斜杠式**；⛔ 未与 `//c` 并用）。**本次独有串** = `ARCHIVE_DONE 20261015_090724 files=19`（BAT_RC=0）。

**时间线**：

| 时刻 | 事件 |
|---|---|
| 09:07:24 | 归档块先跑（#54）：`p7b_build_archive/20261015_090724/`，19 件；**内含上一代位流** `wrapper_p4.bit` sha256 = **`34e553ee…4202` = 0x26 位流**（provenance 已核 ✓） |
| 09:17:32 | synth `Exiting Vivado`（`P7B_ROUND #1 MISMATCH_N = 5` → `#2 = 0`；`P7B_CONVERGED_AT_ROUND = 2`，与 0x26 逐字同） |
| 09:36:36 | 位流落盘（`write_bitstream completed successfully` + `Bitgen Completed Successfully`）/ impl `Exiting Vivado` |
| 09:37:35 | 报告落盘（`p7b_ku5p_timing.rpt` 时间戳）/ bat console 收尾（`BITSTREAM-OK`） |

**收口读数（逐项）**：

| 项 | 读数 |
|---|---|
| **BAT_RC / BUILD_EXIT** | **0 / 0**（console 末 = `BITSTREAM-OK`） |
| **一次收口（计数式）** | `^P7B_ROUND #1 ` 恰 **1** · `BUILD_EXIT` 恰 1 · `^P7B DONE$` 恰 **1**（⚠️ 裸 grep "P7B_ROUND"/"P7B DONE" = 2，第二处 = tcl 源码回显）· `Exiting Vivado` 恰 **3** 条（均在 `board/p7b_ku5p_stdout.txt` 口径上） |
| **P7B_WNS / P7B_WHS** | **+0.069 / +0.010**（`IS_LOCKED_POSTGEN = 0`；`P7B_CONVERGED_AT_ROUND = 2`） |
| **三类失败端点** | **0 / 0 / 0**（setup `0/258,633` · hold `0/258,633` · pulse-width `0/84,241`；`Slack (VIOLATED)` **0 条**；`All user specified timing constraints are met.` 在档） |
| **位流** | sha256 = **`5c17b14f0656cf6680b7d16f7f1659faa4ca9225cf0cb0461765be7a91943385`** · **15,431,261 B**（= 九档同尺寸）· **`SW_CRC=20c4e8b8`**（`.bit` 头逐字读）· routed dcp 63,323,489 B |
| **硬门（12 键）** | `12-4739` / 隐式网五键 / DRC 六键 —— **全 0 命中**（bat 一行都没打；逐键 `grep -c` = 0 复核过；console 0 条 `*-FAIL`） |
| **DRC（routed）** | **0 Error / 0 Critical**；Warning 五族（DPIP-2 4 · DPOP-3 2 · DPOP-4 4 · DPOR-2 18 · REQP-1858 41 = 69 checks）与 0x26 **逐数相同** |
| **Route status** | `# of nets with routing errors = 0`；fully routed 137,858 |
| **日志面** | impl runme 末步 `181 Infos, 12 Warnings, 2 Critical Warnings, 0 Errors`；DRC `finished with 0 Errors`；CRITICAL WARNING = **既存** `Constraints 18-1056` + `Vivado 12-1790` |
| **XDMA 断言组** | `RC_BASE=0` · `RC_INTF=0`（`<AXI_Stream>`）· `RB_MISMATCH_N=0`（13/13）· `GEN_BAD_N=0`（6/6）· `CFGDIFF_ST_N=1` · `CFGDIFF_MM_N=2` · **`VERDICT = OK`**（与 0x26 逐字同）；`p7b_ku5p_xdma_cfg_post_gen.txt` 与 0x26 件 **sha256 逐字相同**（⚠️ 该件本身是**未跟踪**产物） |
| **资源（只并列，不归因）** | placed **78,112 LUT / 74,553 FF** / 348 BRAM / 1 URAM / 4 DSP / 10 IOB / 6 GTYE4；synth **62,790 LUT / 53,114 FF** / 312 BRAM（0x26: placed 78,262/74,570/348/1；synth 62,761/53,107/312 ⇒ **−150 LUT / −17 FF（placed）· +29 LUT / +7 FF（synth）**） |
| **构建期间绑定** | `BUILD_INPUT_HASHES{,_AFTER}.txt`（**287 件**源集）**0 变**（窗口 09:07:24–09:37；`BUILD_INPUT_HASHES_DIFF.txt` = 空，`diff` rc=0） |

**归档清单（`_proj_10g/notes/p9_build_0x27/`，#54）**：`wrapper_p4.bit` · `wrapper_p4_routed.dcp` · `board_rpt/`（**14 件**，与 0x25/0x26 同名集）· `p7b_ku5p_stdout.txt` · 全部读数/原件 txt · `SHA256SUMS.txt`（**91 件**）。
⚠️ 按仓规 `.gitignore`：`*.bit`（`:69`）与 `*.dcp`（`:355`）**均不入库**（`git check-ignore -v` 双证）——归档留盘。另：`p7b_build_archive/20261015_090724/SHA256SUMS.txt` 是白名单件（`.gitignore:810 !…/SHA256SUMS.txt`）⇒ 随轮提交入库（**路径信息供 TL**）。

---

## ⑤ 定向 STA（`q_0x27.tcl`，**两代并列**：0x26 归档 dcp × 0x27 新 dcp）

> 沿用 0x26 轮 `q_0x26.tcl` 先例（调用式 = `run_q_x{26,27}.bat`：`-nojournal -nolog` 在 `-source` 之前；⛔ 行内 `#` 注释陷阱已避；两 bat 复核 `bareCR=0 / nonascii=0 / CRLF=7`）。⛔ **无拆刀 ⇒ 差异含"本刀 + P&R 重排"两项、分不开 ⇒ 只登记不归因**（#66）。

### ⑤-1 全局 / DP 域（原件 `q_stdout_x26.txt` / `q_stdout_x27.txt`）

| 项 | **0x26（前代）** | **0x27（本件）** |
|---|---|---|
| 全局 setup WNS | +0.019 @ `u_tcp_tx/u_fifo_a/wptr_reg[6]_replica/C → u_app/pw_data_reg[41]/D`（lvl 19） | **+0.069** @ `u_tcp_tx/u_ackq/wptr_reg[1]/C → u_tcb/snd_nxt_r_reg[8][25]/CE`（lvl 14） |
| DP 域 WNS（`g_hw.clk_out0`） | +0.019（= 全局，同一对象） | **+0.069**（= 全局，**仍是同一对象**） |
| DP top-10 起点直方图 | **10/10 = `u_tcp_tx/u_fifo_a/wptr_reg[6]_replica/C`** | **10/10 = `u_tcp_tx/u_ackq/wptr_reg[1]/C`** |
| DP top-10 宿 | 3 条 = `u_app/*`（`pw_data_reg[41]` / `stg_reg[45]` / `stg_reg[51]`）+ `u_tcb/*` | **0 条 `u_app/*`**：9 条 `u_tcb/*`（snd_nxt_r / rcv_nxt_r / snd_wnd_r）+ 1 条 `u_tcp_tx/u_retx/*` |
| **⭐ 核心判据：DP 前 10 有本刀新锥?** | —— | ⛔ **没有**：`dp_top10.rpt` grep **`u_app/` = 0**（0x26 = 72）；且 **`dp_top50.rpt` 的 `u_app/` 也是 0**（0x26 = 316）⇒ **比设计件 §3 的"可判死"预期更强**（不进前 10，也不进前 50）；x27 top50 里 20 处 `u_app_udp` 命中 = **老族** `u_app_udp/u_txf → u_udp_tx/ip_csum_r`（与 `u_app` = `app_pattern` 实例不同） |

### ⑤-2 ⭐ 本刀面：`u_app`（app_pattern 实例）族 —— 两代并列

| 族 | **0x26** | **0x27** |
|---|---|---|
| `u_app/*`（2323 → 2358 cell） from_worst | 1.502（sp=`u_app/FSM_sequential_rxs_reg/C`，ep=`u_tcp_echo/u_fifo/…`） | **1.676**（同 sp，ep=`u_mir/stg_data_reg[0]/D`） |
| `u_app/*` to_worst | **0.019**（sp=`u_tcp_tx/u_fifo_a/wptr_reg[6]_replica`，ep=`u_app/pw_data_reg[41]/D`）⭐ 它就是前代 **全局 WNS** | **0.146**（sp=`u_app_ctrl/c_snd_una_reg[8][1]/C`，ep=`u_app/tx_lfsr_reg[21]/CE`）⇒ **本件里 `u_app` 的 to_worst 不再是 WNS**（离 WNS 0.069 有 2.1× 距离） |
| `closing_reg`（裁决 A 输入） | from 2.695 / to 1.070 | from **2.541** / to **1.913** |
| `frm_wait_reg`（裁决 A/B 输入） | from 3.528 / to 0.504 | from **4.263** / to **0.987** |
| `active_reg`（裁决 A 新项） | from 3.379 / to 1.250 | from **3.832** / to **1.925** |
| `sw_pend_reg` | **NOCELL**（cell 名未存活） | 1 cell：from 4.066 / to 1.925 |

### ⑤-3 ⭐ 定向网查询（`#90`：驱动 + 负载两侧都打出来；原件 = `q_stdout_x*.txt` 的 `N` 段）

| 网族 | **0x26** | **0x27** |
|---|---|---|
| **`close_send`**（裁决 B 的落点） | **0 网** | **0 网** |
| **`frm_wait`** | **2 网 / 14 pins**（含 `frm_wait_reg/D`、`frm_wait_i_1/O`） | **6 网 / 47 pins**（`frm_wait_i_1..4_n_53` + `frm_wait_reg_0`；负载含 `act_tmr[*]`、`stat_tx_frames`） |
| **`closing`** | **4 网 / 24 pins**（根网 `u_app/closing` 存活） | **5 网 / 28 pins**（根网存活；负载含 `frm_wait_i_4/I2`） |
| `tx_ok` / `sw_apply` / `op_beat` | 0 / 0 / 0 | 0 / 0 / 0 |

⚠️ **`close_send` 两代都查不到网名 ⇒ 这条定向查询结构性缺席**（表达式被合并进驱动锥、名字未存活）⇒ 按 #92 口径**只能写"未观测到"，不能把 0 命中读成"没影响"**；裁决 B 的有效证据 = RTL 文本层（`:516` 现读）+ TB 门层（`fix_r5` 的 W2 牙 + 96/96 dump 退化重申），**不是**这条 STA 查询。
（`frm_wait` 2→6 网 / 14→47 pins 的负载增长与"新增消费者"方向一致；`closing` 4→5 网含 `frm_wait_i_4/I2` —— **形态登记，不归因**。）

### ⑤-4 参考族并列（跨代只登记）

| 族 | **0x26** from/to | **0x27** from/to |
|---|---|---|
| `ref_tcp_tx`（16331 → 16296） | 0.019 / 0.171 | 0.069 / 0.092 |
| `ref_fifo_a`（749 → 739） | 0.019 / 0.519 | 0.260 / 0.341 |
| `ref_tcp_rx`（4490 → 4485） | 0.319 / 0.319 | 0.237 / 0.444 |
| `ref_tcbcsum` | 4.668 / 0.445 | 4.385 / 0.313 |
| `ref_app_udp`（2723 = 2723） | 0.211 / 0.225 | **0.110** / **0.983** |
| `ref_udp_tx`（2613 = 2613） | 0.225 / 0.211 | 0.598 / 0.110 |
| `ref_tcb`（5402 = 5402） | 0.614 / 0.023 | 0.696 / **0.069**（= 本件 WNS 宿） |
| `ref_fifo_b`（1659 → 1647） | 0.211 / 0.516 | 0.147 / 0.518 |
| `ref_mac_rx`（2573 = 2573） | 0.780 / 0.243 | 1.096 / 0.572 |

**E 段（cell 清单）**：`closing_reg` / `frm_wait_reg` / `active_reg` 两代各 1 cell（FDCE）；`sw_pend_reg` x26 = 0 / x27 = 1（同 ⑤-2 的 NOCELL→1）。
⚠️ **WNS 代际并列 = 0.019 → 0.069**：两代 WNS **宿主不是同一对象**（`u_fifo_a/wptr_reg[6]_replica` ↔ `u_tcp_tx/u_ackq/wptr_reg[1]`）⇒ **只并列、不比"好坏"、不归因**（#66）。

---

## ⑥ 偏离 / 异常（逐条如实）

1. ⚠️ **派单行号 `:3266` 已位移**：`SNAP_NW_P6E = 71` 现读 = **`:3273`**。来源 = **R5 实施轮**（`3a21614`）在 `:1214` 附近的 `TX_SWCLOSE` 启用点 **+7 行**（0x26 轮读 `:3266` 在它之前）。**内容**核过 = 同一块（`// 总字数 W0..W70 (未实现地址 = 0x14C = word 83)` 逐字）。
2. ⚠️ **`manifestcheck` 首跑 "bat carries 0" 是调用方式问题（已自证，不是门缺陷）**：我用 `--root .`（相对）试跑 ⇒ `p4env_var_map` 里 `REPO_ROOT="."` ⇒ `%RTL%` 解析成相对路径被扫描器跳过。按 runner 口径（**绝对** `--root`）复跑 = `6 files == manifest` ✓。**未改任何文件**（同一次核对中 `checkpaths`/`selfcheck` 均 OK）。
3. ⚠️ **`findstr | find /c` 陷阱自伤 1 处（已清）**：计数时误用 `findstr … | find /c …` ⇒ Git Bash 下 MSYS `find.exe` 把 `/c` 当路径**递归 C: 盘**（后台任务超时，已 kill）。改用 `python` 计数（工程已有同款坑登记）。
4. ⚠️ **新门覆盖缺口（登记不修）**：`sim/p9_swc_gate/runF_dbg_witness.bat` 不匹配 `run_*.bat` glob ⇒ **未进指纹**（见 ③-2）。修它需改 globs + **重跑矩阵**，本轮不做。
5. ⚠️ **归档/产物类 git 变更（预期内）**：构建重写 `board/p7b_ku5p_{timing,util,drc,clkinteract}.rpt` + `board/p7b_ku5p_stdout.txt`（5 件 tracked；`board/p7b_ku5p_xdma_cfg_post_gen.txt` 是**未跟踪**产物、内容与 0x26 件 sha 相同）；矩阵重写 `sim/p4sim/matrix_p4dfix.log`。工作树 tracked 修改 = **25 件** = 14 读侧件 + 工具本体 + `wrapper_p4.v` + 2 矩阵件 + swc 门 bat + 5 板产物 + 1 矩阵日志。
6. ⚠️ **资源差分只登记不归因**：placed **−150 LUT / −17 FF**（synth +29 LUT / +7 FF）—— 无拆刀 A/B（#66）。
7. ⚠️ **WNS 代际并列**：见 ⑤-4 末（不同对象）。
8. ⚠️ **P7B_WPWS 读数口径提醒**：stdout 的 `P7B_WPPS` 列表最小 = 0.010，而 routed 报告表 pulse-width 段显示 `0.000`（failing 0）—— 两口径并列，不在此裁定（历史各轮同形态）。
9. ⚠️ **本机有 2 个长驻 `python.exe`**（早于本轮 session；疑为其它会话 watcher）—— 全程三处完整性面（矩阵 26 min 冻结 272 件 / 构建 35 min 源集 287 件 0 变 / gate 相位 227 件 0 变）**都证明它们没有写本仓**。如实登记，不处置。
10. ⚠️ **未烧板**：本轮到"位流 + 归档 + 定向 STA"为止；**未写 QSPI / 未碰对端机**。烧录属后续板级轮。
11. ⚠️ **未提交 git**（按本轮纪律，提交归 TL）；改动全部留工作树。

---

### 附：本目录原件索引（`SHA256SUMS.txt` = 91 件）

- 读侧：`PRESCAN_0x27.txt` · `_dump26.py`/`_EDITS26_DUMP.txt` · `_review_resid.py`/`_RESID_REVIEW_27.txt` · `_scan_newhits27.py` · `gen_edits27.py`/`GEN_EDITS27_OUTPUT.txt` · `EDITS_27_BLOCK.txt` · `splice_phase12.py`/`SPLICE_PHASE12_OUTPUT.txt` · `_tool_backup_pre_splice12.py` · `DRYRUN_BID27_OUTPUT.txt` · `REHEARSE_BID27_OUTPUT.txt` · `NEGCTL_{table,bid,tier,face}_0x27{,_postapply}.txt` · `NEG_REHEARSE_BID27{,_POSTAPPLY}.txt` · `neg_rehearse27{,_post}.py` · `APPLY_BID27_OUTPUT.txt` · `ASSERT_BID27_{AFTER,FINAL}.txt` · `FACE_BID27_AFTER.txt` · `TARGET_SHA_BEFORE_BID27.txt` · `POSTAPPLY_SHA_BID27.txt` · `READ_SIDE_DIFF_NUMSTAT.txt`
- p6e 双门：`P6E_{WRAPPER,COUNTERS}_{BEFORE,AFTER}_console.txt` · `_evidence_xsim_p6e_{wrapper,cnt}_{BEFORE,AFTER}.log`
- 矩阵：`matrix_stdout_run1.txt` · `MATRIX_TAIL_run1.txt` · `P4_MATRIX_FINGERPRINT_20261015_083428_{before,after}.txt` · `FP_DRIFT_vs_0x26.txt` · `INPUT_HASHES_{BEFORE,AFTER}_GATES.txt` + `..._GATES_DIFF.txt` · `SWC_GATE_STANDALONE_AFTER_REG.txt` · `SWC_GATE_MATRIX_console.log` · `SWC_GATE_MATRIX_runF_xs.log` · `mk_input_hashes.py`
- 构建：`BUILD_CONSOLE_BID27.txt` · `p7b_ku5p_stdout.txt` · `BIT_SHA256_BID27.txt` · `board_rpt/`（14 件）· `wrapper_p4.bit`（15,431,261 B / `5c17b14f…3385`）· `wrapper_p4_routed.dcp` · `BUILD_INPUT_HASHES{,_AFTER}.txt` + `..._DIFF.txt`
- 定向 STA：`q_0x27.tcl` · `run_q_x{26,27}.bat` · `q_console_x{26,27}.txt` · `q_stdout_x{26,27}.txt` · `query_out_x{26,27}/`（global_top5 / dp_top10 / dp_top50）· `DP_TOP50_COMPARE.txt`
- 目录工具：`_mksums.py`、`fp_diff.py`

---

**一句话状态**：BID 0x27 已落盘（wrapper 单 hunk +15/−2；禁碰区一字未动）+ 读侧 **24/24** 同步（四负控有牙 / 反演重建恰 1 红 / 几何不变量 71 · 0x14C 双核 · 三哨兵 0x27）；p6e 双门 **144/0** 与 **26/0** 全 PASS_ALL（修前两门各恰 1 红 = BID；H 段读数逐字不变）；矩阵 **18→19 门**（新 `swc` 换流门注册：manifest + bat 重构 + runner 行 + globs；注册前置 6/6 · checkpaths/selfcheck 全过 · 单独跑 PASS），**19/19 EXIT=0 / FROZEN**（272 件），漂移恰 `{wrapper_p4.v, app_pattern.v, paths.txt, run_matrix_p4dfix.bat}` + ADDED 8（逐条落 globs/编译集）；构建一次收口 **WNS +0.069 / WHS +0.010 / 三类失败端点 0/0/0**，位流 `5c17b14f0656cf6680b7d16f7f1659faa4ca9225cf0cb0461765be7a91943385`（15,431,261 B，`SW_CRC=20c4e8b8`），12 键硬门 0 命中 / DRC 0E0C / route 0 错 / XDMA VERDICT=OK / 构建窗口 287 件 0 变；归档 91 件（bit/dcp 按 .gitignore 留盘；`p7b_build_archive/20261015_090724/SHA256SUMS.txt` 白名单入库）。定向 STA（两代并列）：⭐ **本刀新锥不在 DP 前 10（也不在前 50）—— `u_app/` 命中 72/316 → 0/0**，比设计件"可判死"预期更强；WNS 宿主换族（`u_fifo_a/wptr_reg[6]_replica` → `u_tcp_tx/u_ackq/wptr_reg[1]`，不同对象 ⇒ 只并列）；`close_send` 网名**两代都未存活**（结构性缺席 ⇒ 该条定向查询只能写"未观测到"）。**板子未烧。**

---

## 给 TL 的关键交接信息（报告之外）

- **REPORT.md 需 TL 代落盘**（平台拒写 .md）；上表即全文。
- **归档路径**：`_proj_10g/notes/p7b_build_archive/20261015_090724/SHA256SUMS.txt`（白名单件，随轮入库；同目录 `wrapper_p4.bit` = **0x26 位流** `34e553ee…` provenance 已核）。
- **轮目录 92 件 / 92 MB**（`.bit` + `.dcp` 均被 `.gitignore` 忽略：`:69` / `:355`）。
- **工作树 tracked 修改恰 25 件**（清单见 ⑥-5）；新增未跟踪 = `sim/p4gates/swcg_src.f` + 轮目录 + `p7b_build_archive/20261015_090724/`。
- **板子现态未动**（未烧、未碰对端机、未写 QSPI）；xsim/Vivado/py 进程 0 残留（长驻 python.exe 2 个除外，已登记）。

----------------------------------------------------------------

## TL 附加（2026-10-15 09:5x；独立抽核记录）

- **位流核**：`sha256sum _proj_10g/notes/p9_build_0x27/wrapper_p4.bit` = `5c17b14f0656cf6680b7d16f7f1659faa4ca9225cf0cb0461765be7a91943385` ✓（与报告逐字）。
- **被验源核**：`rtl/app_pattern.v` = `be0b5f9c…d8aa6c` ✓（R5 冻结值，未动）；`board/wrapper_p4.v` = `305123dc…`（BID 编辑后新 sha）。
- **BID 亲读核**：`board/wrapper_p4.v:4329` = `32'h00000027` ✓（TL 亲读；注释块新块在顶、RFC 块降级逐字保留）。
- **门读数核**：`P6E_WRAPPER_AFTER_console.txt` 末 = `PASS_ALL` ✓；`P6E_COUNTERS_AFTER_console.txt` 末 = `PASS_ALL` ✓；**修前咬合见证** = wrapper `[FAIL] … = 00000027 (期望 00000026)` / counters `[FAIL] … = 39 (期望 38)`（各恰 1 红）✓。
- **矩阵核**：`MATRIX_TAIL_run1.txt` = `gates run 19/19` / `gates failed: 0` / `VERDICT: FROZEN`（272 件）✓；`FP_DRIFT_vs_0x26.txt` = CONTENT-CHANGED (4) + ADDED (8) + GONE (0) ✓（逐条与报告一致）。
- **工作树核**：tracked 修改恰 **25 件** ✓；新未跟踪 = `sim/p4gates/swcg_src.f` + 轮目录 + `p7b_build_archive/20261015_090724/` ✓。
- ⛔ **裁定口径**：本件不下 PASS/FAIL；"未观测到"≠"不存在"。⚠️ `close_send` 网名缺席 = 该条 STA 查询**结构性缺席**（#92），裁决 B 的证据面 = RTL 文本 + TB 门层（**已按此口径写入**）。
- **裁定**：接受入库（25 件 + 轮目录 91 件 + `swcg_src.f` + `p7b_build_archive/20261015_090724/SHA256SUMS.txt`）。**0x27 冻结 = `5c17b14f…3385`**；下一棒 = **板级轮**（板态 = 厂商设计 ⇒ 全恢复 + 0x27 上板 + 换流门 K0 + RFC 注入 A/B）。
