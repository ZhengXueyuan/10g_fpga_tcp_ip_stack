# P9 构建轮 0x24 —— URAM 板内缓冲（修正收口）构建报告

**轮次** = 2026-10-13 07:47 → 09:2x（本机）· **工作目录** = `D:\repo\XCKU5PMini\udp_hls_10g`
**开工 HEAD** = `f46a221`（URAM 修正轮收口）· **收工 HEAD** = `0b06a2e`（**并行会话的提交**，见 §F；本轮不提交，改动留工作树）
**派单** = A 构建前补门（`run_tb_p6e_pcie_mut{,2}.bat` + 常驻矩阵 + FROZEN 指纹）· B `board/wrapper_p4.v` BID `0x23→0x24` · C BID 断言同步（照 0x23 清单全仓）· D 完整构建（唯一入口 `board/run_build_p7b_ku5p.bat`）· E 硬门与读数 · F 报告。
**本刀内容（0x23 → 0x24）** = **URAM288 板内缓冲**（`rtl/mir_uram_fifo.v` = `u_mir_buf`，4096×64 = 32 KB 载荷 + 4 字弹性堆 + 3 级读流水；接在 `u_mir` aux 读口与 `u_mir_axis` 之间，两侧同钟无新 CDC）+ **F2/F3 修正**（`up_req` 并入 `rst_n`；clr 拍 `pop &&= !clr`）。依据与门读数 = `_proj_10g/notes/p9_uram_20261013/{REPORT,REVIEW,FIX_REPORT}.md`。

（落盘说明：REPORT.md 由 TL 代落盘 —— 平台拒写 .md 的已知间歇故障；正文逐字为构建 agent 回传。落盘后 `SHA256SUMS.txt` 已由 TL 重跑一次。）

**读数口径声明（先读这条）**
- 本报告**不下 PASS/FAIL 裁定**、**不写"时序已解决"**、**不把"未观测到"写成"不存在"**。
- 所有"是/否"句只描述**本轮实测到的读数**；判据层裁定权在判据所有者。
- **板上现役仍是 `0x23`**（本轮 ⛔ 不烧板、⛔ 不写 QSPI、⛔ 不碰对端机）；**`0x24` 位流已构建、未烧、未验**。
- 跨代读数（0x23 ↔ 0x24）**一律并列，不归因**（#66：全局 WNS 逐代"不是同一对象"；无拆刀 A/B）。

---

## §A 构建前补门（xsim；Vivado 前全部收口，#47）

**顺序纪律**：**先改完所有文件**（§B 三项）→ 再跑门（跑动期间我不改任何源码）；**xsim 与 Vivado 严格串行**（最后一项 xsim = 矩阵 08:22:34 收口；构建 08:26:30 启动）。

| 门 | 调用 | 读数 | 退出码 |
|---|---|---|---|
| `run_tb_p6e_pcie_mut.bat` | 07:54:15 | `MUT_SRCINV anchor_hits=1` → sim **54 项 FAIL** → **`P6E-MUT-VERDICT: MUTANT-CAUGHT-as-expected`** | **0** |
| `run_tb_p6e_pcie_mut2.bat`（首跑 07:55:17） | — | **`MUT_BWIRE FAIL: anchor must hit exactly 1 line (got 0)` → `MUT-BWIRE-GENFAIL`**（见下"既存缺陷"） | 1 |
| `run_tb_p6e_pcie_mut2.bat`（重跑 07:55:51） | 锚点修复后 | `MUT_BWIRE anchor_hits=1` → sim **11 项 FAIL**（**全部 = 内容对账判据**，逐条显示数据恒 0 vs 期望图案）→ **`P6E-MUT2-VERDICT: MUTANT-CAUGHT-as-expected`** | **0** |
| `run_tb_p6e_pcie_mut.bat`（重跑 08:24:40） | 见 §F 外来改写后重绑 | 同首跑：54 项 FAIL / `MUTANT-CAUGHT-as-expected` | **0** |
| `run_tb_p6e_pcie.bat`（全链） | 08:25:26 | **`PASS_ALL`**（含 `P9-B-3d lower leg` / `P9-B-3h upper leg` 双边账；P9-B-3 W70 4d494e79→4d49fea1） | **0** |
| `run_tb_p6e_pcie_counters.bat` | 08:26:06 | **`PASS_ALL`** | **0** |
| `run_matrix_p4dfix.bat`（常驻矩阵） | 07:57:10→08:22:34 | **17/17 · gates failed 0 · VERDICT: FROZEN**（见下） | **0** |

**⭐ 抓到一条既存缺陷（非本轮引入，修法=门工具锚点重对）**：`sim/p6e_pcie/mut_bwire.py` 的锚 = `u_mir` 的 `mir_dma_ring` 例化里 `.src_data (mir_dma_data),` —— 该例化**在 `173b18d`（P9 XDMA MM→AXIS 落地，2026-10-11）被整体删除**（环被 AXIS 成形器取代）⇒ 自那以后 `anchor_hits=0`、`mut2` 门**结构性空转**（症状 = `MUT-BWIRE-GENFAIL`；它会**响亮失败**、不会假绿，但门实际上一直在"生成器失败"处停住 ⇒ 该突变臂对 0x22/0x23 两代**没有任何执行**）。
**修**（最小、同语义）：锚改为 AXIS 架构下的同一根线 **`.dma_data (mir_dma_data)`**（来自 `u_mir_buf.dn_data`）→ `64'd0`，突变语义不变（grant 照常/计数照涨，**数据恒 0**）；docstring 补"锚点重对"说明。修后 mut2 门重跑 = **11 项 FAIL 全落内容判据、计数器判据全绿** = 正是该臂设计要打的点（`MIR-2e`/`M1-B-3d`/`P9-B-*` 内容对账有牙）。

**矩阵读数（原件 = 本目录 `matrix_p4dfix.log` + `P4_MATRIX_FINGERPRINT_20261013_075711_{before,after}.txt`）**
- `gates run 17 / 17` · `gates failed: 0`；单门 `GATE <名> EXIT=0` 全列于 stdout（`matrix_stdout_utf8.txt`）。
- `VERDICT: FROZEN -- all 257 hashed files byte-identical across the run`；`DIGEST_COMPILE = bc18cc8b…`（212 件）before=after；`DIGEST_ALL = 28fda2c4…`（257 件）before=after。
- ⚠️ `GIT_HEAD` **before=`30d2253` → after=`97c13e6`**：跑动期间**并行文档迁移会话落了 6 个提交**（§F）；**它们未触矩阵哈希集** —— 判据 = 两个 DIGEST 逐位相同（若被触，DIGEST 必变）。⇒ FROZEN 判决**成立**，但"HEAD 前后核"这一格**如实登记为"≠"**。
- 逐件绑定核对（照抄 0x23 的 `check_fp_binding.py`；原件 `FP_BINDING_CHECK.txt`）：**257/257 == 盘上现读**；257 全 tracked；**256 件逐字 == HEAD，唯一 ≠ HEAD = `board/wrapper_p4.v`**（= §B 的 BID 刀，未提交）⇒ 与"本刀唯一 RTL 面改动"一致；③ 未跟踪 = 0。
- **覆盖声明（承 0x23 轮）**：常驻矩阵对 `rtl/mir_uram_fifo.v`/`app_rx_mirror.v`/`axis_c2h_stream.v` **零覆盖**（`p5_wrapper` 只 `-d APP_MODE`；该实例被 `APP_MODE ∧ DP_156MHZ` 双包）⇒ **17/17 对本刀 = 空证据**；本刀该有的门 = `sim/p9_uram`（修正轮跑过，**本轮未重跑**：59 判据 + 12 突变臂 + 2 守卫，出处 `p9_uram_20261013/FIX_REPORT.md`）+ 上面 p6e 四门（**本轮跑了**）。

**跑动期间绑定**：`INPUT_HASHES_{BEFORE,AFTER}_GATES.txt`（117 件）比对 = **仅 4 件变化**：`sim/p6e_pcie/mut_bwire.py`（**我的**锚点修复）+ `rtl/mac_tx_64.v` / `board/build_p6a_ku5p.tcl` / `board/build_p5_diag.tcl`（**外来**，见 §F；**纯注释**）；余 113 件逐字相同。

---

## §B 文件改动面（3 项；⛔ 未碰 rtl/**、未碰 Kimi 组在途文档迁移件）

### B-1 `board/wrapper_p4.v`：`BUILD_ID_V` `0x23 → 0x24`（2 hunk / +50 −3）

| # | 位置（现读） | 改动 |
|---|---|---|
| 1 | `:2144` | 版本戳注释：`本版 **0x23** 沿用` → `本版 **0x24** 沿用` |
| 2 | `:4316` + 注释块 | `.BUILD_ID_V (32'h00000023)` → `32'h00000024`；新 `本轮构建 (2026-10-13): **0x23 → 0x24**` 块（内容/门/回退点/历史链，含"构建清单 +1 行导入"的 ⚠️ 注记），旧 0x23 块降级为 `---- (以下为历史, 逐字保留) ---- / ⭐ 上一版 (2026-10-12)`（逐字保留） |

**机检（防"顺手改了别的"）**：`git diff` = **2 hunk**；**非注释（无 `//`）改动行恰 1 行** = `.BUILD_ID_V (...)`；`tie-off` / `:1319-1322` 禁碰区 / AXIS 端口表 / M1 块 `git diff` 命中 **0**；文件 4860 → **4907 行**；sha256 `bcb24891db833541…` → **`c06690ce6fce414a2018d1b46c21d01ec9b903ca0513d6e1cb89bb4aa4c82743`**（= §A FP 指纹里 `≠HEAD` 的唯一一件）。
**并行面**：改动前/后各记 sha256（上）；改前核过 `git status board/ rtl/` = **零未提交改动**（无外来在途编辑）；改后 diff 面 = 仅本刀。

### B-2 `board/build_p7b_ku5p.tcl`：**+1 行导入 `rtl/mir_uram_fifo.v`**（+6 行注释）

**为什么必须改（本刀最重的既存缺口）**：本脚本的源清单是**显式 `import_files` 列表**（不是 glob）——URAM 实施轮（2026-10-13，**xsim-only**）新增了 `rtl/mir_uram_fifo.v` 且 wrapper 已例化 `u_mir_buf`，但**没人把它加进本清单**。**缺这一行 = `u_mir_buf` 在黑盒状态被综合**（Vivado 对"被例化但没导入"的模块不报硬错）⇒ **URAM288 不会推断、缓冲不存在**——本工程最贵的一类"安静失效"。
**加件先例** = `173b18d` 在**同一区域**加 `axis_c2h_stream.v`（同款写法）。**效果直接可见**：`P7B_NFILES = 442 →` **`443`**（+1，§C），synth **URAM 0 → 1**。
sha256 `6635e873293674bf…` → **`790424b9ab77c7492fb644055b12df46488ec44897c31aa275fa5959f9a76113`**。
⚠️ 这条**不在派单明文里**（派单只说 BID bump + 读侧同步）——按"必须修的既存问题"处置并**在此显式报告**（若 TL 判该改动越权，回退 = 删 2 行，位流随之作废）。

### B-3 读侧 BID 同步 `0x23 → 0x24`（阶段 ⑨ = `EDITS_24`；**24 处 / 14 文件**；几何**一字未动**）

做法照抄 0x23 轮：`gen_edits24.py`（从 `EDITS_23` 的 new 侧逐条 +1 代；**old 侧自检 24/24 逐字命中盘上现状**）→ `splice_phase9.py`（6 锚点**唯一命中**：`EDITS_24` 声明 / `E9()` / `STAGES` 追加 `("0x00000024", …, 71, 0x14C)` / ⑮ 段插入 / docstring ⑨ 指针 / ALLOW 追加 9 条）→ 全阶段读数：

| 阶段 | 读数 | 原件 |
|---|---|---|
| 预扫 | 目标 0x24 搜索面 4 族 / 337 行 / 164 文件 / **未登记 19 件** → 逐条核内容 → 分类（见下） | `PRESCAN_0x24.txt` |
| dry-run | **24/24 `hits=1/1`**；B 面 4 族 **340 命中文件**（apply 前计数）**未登记 0**；C 24 红 = 待改处；D 覆盖 14/14 | `DRYRUN_BID24_OUTPUT2.txt` |
| rehearse（内存 overlay） | applied=24 / **0 fail（全绿 ⇒ 清单完整且自洽）** | `REHEARSE_BID24_OUTPUT.txt` |
| negctl ×4（tempfile 破坏件） | `table` 1 红 · `bid` **24 红（含目标断言）** · `tier` **24 红（含目标）** · `face` 3 红 —— **四条全有牙** | `NEGCTL_{table,bid,tier,face}_0x24.txt` |
| neg_rehearse（故意漏末条） | **恰 1 红** = 漏掉那处（`step0_selfcheck.sh[BID]`） | `NEG_REHEARSE_BID24.txt` |
| apply | RC=0 / 0 fail；**14/14 件 SHA256 全变** | `APPLY_BID24_OUTPUT.txt` · `TARGET_SHA_BEFORE_BID24.txt` / `POSTAPPLY_SHA_BID24.txt` |
| assert（复核、矩阵后再跑一次） | RC=0；A 5/5 · B 4 族 **332 命中文件**（apply 后）**未登记 0** · C 全绿 · D 14/14 | `ASSERT_BID24_AFTER.txt` · `ASSERT_BID24_AFTER_MATRIX.txt` |
| face | **332 行 / 165 文件 · 未登记 0** | `FACE_BID24_AFTER.txt` |
| post-apply negctl ×4 + 反演重建 neg_rehearse | 四条仍有牙（1/1/1/3 红，含目标断言）；反演重建恰 **1 红** | `NEGCTL_*_0x24_postapply.txt` · `NEG_REHEARSE_BID24_POSTAPPLY.txt` |

（B 面文件计数 340 → 332：apply 后有 9 件已不含 8 位旧值字面值 `0x00000023`/`32'h00000023`（身份串被整串 +1 代），其中 8 件从命中面移出。）

**B 面 19 件未登记命中的处置（逐条核过）**：
- **烧 0x23 的现场件**（`p9_bench_restore_20261013/` · `p9_board_0x23_20261011/` · `p9_final_board_20261012/` · `p9_hostread_20261013/` · `p9_rate_20261013/`）= **旧位流读法**：`EXPECT_BID=0x00000023` / `WANT=066a3923…` 都是**那一代的真值**（位流 sha 钉死）⇒ 改它反而毁掉取证 ⇒ 登记不动（ALLOW 5 条）。
- `p9_uram_20261013/diag_p9b3d/tb_p6e_pcie_wrapper.v` = 修正轮的 **P9-B-3d 诊断副本**（内含当时的 `0x23` 期望）⇒ 一次性证据件，只登记不动（ALLOW 1 条）。
- `p9_build_0x24/`（本轮）+ `p9_uram_20261013/`（上一轮）⇒ 现役（ALLOW 2 条）。
- ⭐ `agent_docs/int_scratch/tb_int_axr36.v` = **Kimi 组文档迁移把仓根 `int_scratch/` 移走**导致旧 ALLOW 正则 `^int_scratch/` 失配；内容是 **36 字世代（2026-09-29）的 scratch TB**（`BUILD_ID_V(32'h00000006)` / `NW=36`，与现役身份无关）⇒ 加 ALLOW 1 条（只登记不动）。

**哨兵/权威源复核**：读侧代哨兵 `j6_r6fix.sh` 的 `EXPECT_BID` 默认值 = `0x00000024`；权威源 `board/wrapper_p4.v` 现读 = `SNAP_NW_P6E = 71` / `BUILD_ID_V = 0x00000024` ⇒ **两侧一致**。
**人工覆盖面（结构性不被搜索面扫的非断言扩展名）**：`.md/.txt/.log` 命中共 40+ 件（另见 `.claude/worktrees/**` 一体本，属 ignore 面）——逐类抽样核过：**全是"寄存器值/快照读数"**（例 `W28 txcdc_occ_max = 0x00000023`、`W0 rx_stat_frames = 0x00000023`）或烧录现场日志，**无一是身份断言** ⇒ 0 条需改（同 0x23 轮 §F-6 的口径）。

**两处 p6e TB 的 BID 期望**（派单点名）：`tb_p6e_pcie_counters.v` / `tb_p6e_pcie_wrapper.v` 均已 `32'h00000023 → 32'h00000024`（含判据名串），并被上面 p6e 四门实跑覆盖（其中全链门 08:25 = **PASS_ALL**，即新 BID 在真 wrapper 上被读到）。

---

## §C 完整构建读数（`board/run_build_p7b_ku5p.bat`，一次收口）

**调用式** = `MSYS_NO_PATHCONV=1 cmd /c 'board\run_build_p7b_ku5p.bat'`（单斜杠式；⛔ 未用 GUI / 未用别的 tcl / 未手工 `create_project`）。
**本次独有串（判"真的跑了"）** = `ARCHIVE_DONE 20261013_082630 files=19`；产物 mtime 全落本轮（synth `08:37:03` / impl `08:57:04` / 父 `08:58:12` 三条 `Exiting Vivado`）。

| 项 | 读数 |
|---|---|
| **BAT_RC / BUILD_EXIT** | **0 / 0**；末尾 `BITSTREAM-OK` |
| **一次收口（计数式）** | `P7B_ROUND #1` 恰 **1** 次（`#1 MISMATCH_N=5` → `#2 =0`）· `BUILD_EXIT` 恰 1 · `P7B DONE` 恰 1 · `Exiting Vivado` 恰 **3** 条 |
| **P7B_WNS / P7B_WHS** | **+0.066 / +0.010**（`P7B_CONVERGED_AT_ROUND = 2`；`IS_LOCKED_POSTGEN = 0`） |
| **三类失败端点** | **0 / 0 / 0**（setup 0/258,575 · hold 0/258,575 · pulse-width 0/84,196）；报告面 `Slack (VIOLATED)` **0 条**；报告原文 `All user specified timing constraints are met.` |
| **位流** | sha256 = **`e3b07957aea0326a168b9db0238ef9dd933dc7a21884c92e50a7c3b0abadf1db`** · **15,431,261 B**（与历史八档**逐字节同长** ⇒ 只有 sha256/BID 能分版）⚠️ **2026-10-13 TL 代落盘时第 50 位转录笔误（原写 `…e50e7c3…`）**；实算双工具 / `SHA256SUMS.txt` / Vivado `impl_1` 原件三方一致 = 本值（订正依据 = `p9_board_0x24_20261013/REPORT.md` §0.1） |
| **构建前归档（#54）** | `p7b_build_archive/20261013_082630/`（19 件 + SHA256SUMS）——归档的是**上一代（0x23）** impl 产物；`wrapper_p4.bit` sha256 实测 = `066a3923…3126` = **0x23 位流**（provenance 已核） |
| **硬门（12 键）** | `DROPPED-CONSTRAINT-FAIL` / `IMPLICIT-NET-FAIL`（5 键）/ `DRC-KEY-FAIL`（6 键）**全 0 命中** |
| **DRC（routed）** | **0 Error / 0 Critical**；Warning 五族（DPIP-2 4 · DPOP-3 2 · DPOP-4 4 · DPOR-2 18 · REQP-1858 41 = 69 checks）与 0x23 **逐数相同** |
| **Route status** | 196,049 logical nets / **137,858 全布通** / **routing errors = 0** |
| **日志面** | impl 汇总 `1128 Infos / 311 Warnings / 1 Critical Warning / 0 Errors`（0x23 = 1122/308/1/0；**Critical = 既存两条：约束 18-1056 + 评估 license 12-1790**） |

**XDMA 配置断言组（全过；与 0x23 逐条相同）**：`RC_BASE=0`（MSG `<>`）· `RC_INTF=0`（MSG `<AXI_Stream>`）· `RB_MISMATCH_N=0`（13/13）· `GEN_BAD_N=0`（6/6）· `CFGDIFF_ST_N=1 {CONFIG.Component_Name}` · `CFGDIFF_MM_N=2 {+CONFIG.xdma_axi_intf_mm}` · `VERDICT=OK`。

### C-1 ⭐ 三条 URAM 硬门（任务点名的逐条原文）

1. **`URAM288 = 1`（0 → 1）** ✅
   - synth：`URAM | 1 | … | 1.56`（0x23 = 0）+ 器件明细 **`URAM288 | 1 | BLOCKRAM`**。
   - routed（placed）：`URAM | 1 | … | 1.56`。
   - 网表点名（§D）：`U uram_cells=1`，原语 = **`u_mir_buf/u_ram/xpm_memory_base_inst/gen_wr_a.gen_word_narrow.mem_reg_uram_0`（REF_NAME = `URAM288`）**，父层次 = `u_mir_buf/u_ram` ⇒ 落在新件里。
2. **`Synth 8-6793`** —— ⚠️ **口径必须写清**：**全日志 56 条**（`grep -c` = 56），**逐条全指既存 `retx_ram`**（`mem_e_reg`/`mem_o_reg` 六族同分布）；**0x23 同为 56 条、逐族同分布**（原件 = 归档 `20261013_082630/p7b_ku5p_stdout.txt`）⇒ **本刀新增 = 0 条**；**新件/URAM 例化面 0 条**。
   ⇒ **"0 条 `Synth 8-6793`"这条硬门按字面读为 56 ≠ 0、按 URAM 报告 §6 的语义读（"不许新件被拒"）为 0** —— **两个读数都摆在上面，裁定权在判据所有者**。
3. **BRAM 不增** ✅ **synth 312 = 312；routed 348 = 348**（分解同：RAMB36E2 317 + RAMB18E2 62）⇒ XPM **没有**静默落回 BRAM。

### C-2 资源差分（vs 0x23；两代都列，不加解释）

| 资源 | 0x24 synth | 0x23 synth | Δ | 0x24 placed | 0x23 placed | Δ |
|---|---|---|---|---|---|---|
| CLB LUTs | 62,763 | 62,626 | **+137** | **78,068** | 77,878 | **+190** |
| CLB Registers | 53,113 | 52,761 | **+352** | **74,508** | 74,209 | **+299** |
| Block RAM Tile | 312 | 312 | 0 | **348** | 348 | **0** |
| URAM | **1** | 0 | **+1** | **1** | 0 | **+1** |
| DSP48E2 / Bonded IOB / GTYE4 | — | — | — | 4 / 10 / 6 | 4 / 10 / 6 | 0 |

### C-3 新件引入的 synth 告警（逐条；新 vs 0x23 = **+3 条警告、0 新错误**）

| 告警 | 位置 | 判读（本报告只描述，不裁定） |
|---|---|---|
| `Synth 8-7137` 寄存器 `o_mem_reg` Set/reset 同优先级 | `mir_uram_fifo.v` | 与**既存同族**（wrapper `trace_mem_reg`/`rx_trace_mem_reg`、`axis_pipe.m_data_r_reg` 等同款警告）——静态"仿真/综合可能不一致"提示 |
| `Synth 8-4767` RAM `o_mem_reg` 用**寄存器**实现 | `mir_uram_fifo.v:234` | **= 设计本意**：`o_mem` 是 4 字弹性寄存器堆（`reg [63:0] o_mem [0:OQ-1]`），本就该落寄存器；**URAM 本体（`u_ram`）另落 URAM288** ⇒ "落错 primitive"的警戒（BRAM 不增 / URAM=1）**两条都已核** |
| `Synth 8-6014` 未用时序件 `gen_rd_b.gen_doutb_pipe.gen_stages.gen_epipe[1].enb_pipe_reg[1]` 被删 | `xpm_memory.sv:3139`（XPM 内部） | 纯优化提示；同族 0x23 41 条 → 0x24 42 条（+1）；读延迟合同面**未见**其它变化（§D 的 URAM 读路径 `doutb_pipe_reg[1]` 在报告面上） |

**BlackBox 报告**：0x23 与 0x24 **逐字相同**（仅 `xdma_0` ×1 + `pcs64` ×1 = IP 容器）⇒ **`mir_uram_fifo` 不是黑盒**（= §B-2 那一行的直接效果）。

**构建期间绑定**：`BUILD_INPUT_HASHES{,_AFTER}.txt`（260 件：`rtl/*.v` + `board/*` + `_proj_pcie/rtl` + hls verilog + `p7b_mac/rtl`）**逐字相同** ⇒ 构建窗口（08:26:28–08:59:37）**零源码改动**（并行会话在此窗口未动构建面）。

---

## §D 定向时序查询（`q_0x24.tcl`，后布线；原件 `q_stdout.txt` + `query_out/`）

**调用式** = `run_q.bat`（`QUERY_EXIT=0`，09:04:43）。⚠️ **首跑自伤登记**：q_0x24.tcl 初版在 `fam` 参数后写**行内 `#` 注释** ⇒ Tcl 不以行内 `#` 为注释 ⇒ `wrong # args`，89 s 即退（`QUERY_EXIT=1`）；修法 = 注释独立成行后重跑（09:02:05→09:04:43）。

### D-1 全局 / DP 域（vs 0x23 并列）

| 面 | **0x24** | 0x23 |
|---|---|---|
| 全局 WNS | **+0.066** —— 宿主 = `u_tcp_tx/FSM_sequential_rx_state_reg[1]/C → u_tcb/rcv_nxt_r_reg[4][20]/CE`（**lvl=16**；top5 全同族：`rcv_nxt_r_reg[4][{20,3,4,6,15}]`） | +0.098（宿主 = **pcie 域** 2 级路径 `u_snap_dp/valid_a_reg/C → u_snap_seq/dout_reg[268]/CE`） |
| DP 域 WNS（`g_hw.clk_out0`） | **+0.066 = 与全局同一对象**（DP top10 全 = `u_tcp_tx FSM → u_tcb/rcv_nxt_r` 族，+0.066…+0.079）⇒ **DP 域本代再次是全局最差域** | +0.311（宿主 `u_tcp_tx/recv_first_reg/C → u_tcb/snd_nxt_r_reg[9][28]/CE`，lvl 17） |

⛔ **口径（#66）**：两代全局 WNS 的**宿主、域、逻辑级数全都不同** ⇒ **不比大小、不归因**（无拆刀 A/B）；本格只登记"本代全局最差 = DP 域 `u_tcp_tx FSM → u_tcb/rcv_nxt_r` 写使能锥"。

### D-2 ⭐ 新件 `u_mir_buf` 定向锥（任务清单四条逐条 + 全族）

| 族（`ncell`） | from_worst | to_worst |
|---|---|---|
| `mir_buf`（全族 495，ref=`mir_uram_fifo`） | **+0.573**（lvl 9）`u_mir_buf/wp_reg[4]/C → u_mir/u_fifo/empty_r_reg/D` | **+0.590**（lvl 1）`u_mir/clrt_sr_r_reg[1]/C → u_mir_buf/o_mem_reg[3][62]/CE` |
| ① `mb_wp`（13）`wp → occ → ufull → up_req` | +0.573（同上） | +1.049（`u_pcie_regs/s_axil_arready_reg/C → wp_reg[12]/CE`） |
| ① `mb_rp`（13） | +0.624（`rp_reg[5]/C → u_mir/u_fifo/empty_r_reg/D`） | +1.349 |
| ② `mb_vsr`（3）`valid 链 → inflight` | +1.493（`v_sr_reg[2]/C → o_mem_reg[3][62]/CE`） | +1.905 |
| ② `mb_oocc`（6）`o_occ → inv → issue` | +1.914 | +1.797 |
| ③ `mb_omem`（260）`弹性堆 → 4:1 mux → dn_data` | +1.682（`o_mem_reg[3][47]/C → u_mir_axis/s0_data_reg[47]/D`） | +0.590 |
| ③ `mb_opw`（3）/ `mb_opr`（4） | +1.567 / +0.972 | +2.227 / +1.683 |
| ④ `mb_ram`（80，含 XPM/URAM 例化面）`up_data → URAM 写口` | +1.996（URAM `CLK → doutb_pipe_reg[1][31]/D`） | **+0.710**（`u_pcie_regs/s_axil_arready_reg/C → …mem_reg_uram_0/BWE_B[1]`） |
| `M1 全体在 DP 组内`（`m1_dp_from` / `m1_dp_to`） | +1.686 | +1.105 |
| `M1 全体全钟面`（`m1_any_from/to` 最差） | +0.480（`u_mir/u_fifo/rbin_r_reg[3]/C → u_pcie_regs/s_axil_rdata_reg[13]/D`） | +0.473（`u_pcie_regs/s_axil_arready_reg/C → u_mir/u_fifo/empty_r_reg/D`） |

**读法（只并列）**：新件**自己的锥**（from +0.573 / to +0.590）离本代全局 WNS（+0.066）有 **~0.51 ns**；四条清单里**唯一贴近 pcie 侧中高档的是 ④ 的 to 面 +0.710 与 ② 的 +0.590**，两者仍 **8–10× 全局余量**；`u_mir_buf` 族 **0 条进 DP top10、0 条进全局 top5**。
**未受伤复核（承前代）**：`qcnt_reg` to +1.621 · `clr_drop` **NOCELL**（网名归并产物，同 0x23）· `dma_words` to +0.935 · `ps_stage` to +0.505 / from +0.550（**宿主 = 本代全局最差锥**：`ps_stage_rdy_reg/C → rcv_nxt_r_reg[4][20]/CE`）· `dup_l_reg` to +0.804 · `ack_adv` to +0.780 · `ring_hi` to +0.930 · `ctrl_probe` from **+0.238**（lvl 17，`ctrl_tcpcsum` 族 —— 未进全局 top5）。
**成形器面（对照 0x23）**：`axis_inst`（381 cells；0x23 = 389）from **+1.279**（0x23 +0.687）/ to **+0.821**（0x23 +0.645）—— ⛔ 两代 P&R 不同，**只并列、不当趋势/收益**。

---

## §E 归档（`_proj_10g/notes/p9_build_0x24/`，**本轮内落盘**，#54）

| 组 | 件 |
|---|---|
| 位流 / 网表 | `wrapper_p4.bit`（15,431,261 B，sha256 `e3b07957…f1db`）· `wrapper_p4_routed.dcp`（63,244,955 B） |
| 构建报告 | `board_rpt/`（14 件 = `wrapper_p4_{timing_summary_routed,utilization_placed,utilization_synth,clock_utilization_routed,control_sets_placed,drc_routed,power_routed,route_status}.rpt` + `p7b_ku5p_{timing,util,drc,clkinteract}.rpt` + `p7b_ku5p_xdma_cfg_post_gen.txt` + `runme_impl_1.log`）· `build_stdout_full.txt`（bat stdout）· `p7b_ku5p_stdout.txt`（vivado stdout 全量） |
| 定向查询 | `q_0x24.tcl` · `run_q.bat` · `q_stdout.txt` · `q_bat_console.txt` · `query_out/`（`global_top5.rpt` / `dp_top10.rpt` / `dp_top50.rpt`） |
| 门读数 | `gate_mut.txt` / `gate_mut_rerun.txt` / `gate_mut2.txt` / `gate_p6e_fullchain.txt` / `gate_p6e_counters.txt` · 矩阵件（`matrix_stdout_raw.txt` + `matrix_stdout_utf8.txt` + `matrix_p4dfix.log` + 两件指纹 + `FP_BINDING_CHECK.txt`） |
| 绑定哈希 | `INPUT_HASHES_{BEFORE,AFTER}_GATES.txt` · `BUILD_INPUT_HASHES{,_AFTER}.txt` |
| 读侧件（B-3） | `gen_edits24.py` · `EDITS_24_BLOCK.txt` · `splice_phase9.py` · `_scan_newhits.py`（+`PRESCAN_0x24.txt`） · `neg_rehearse24.py` / `neg_rehearse24_post.py` · `{DRYRUN_BID24_OUTPUT2,REHEARSE_BID24_OUTPUT,APPLY_BID24_OUTPUT,ASSERT_BID24_AFTER,ASSERT_BID24_AFTER_MATRIX,FACE_BID24_AFTER,NEG_REHEARSE_BID24,NEG_REHEARSE_BID24_POSTAPPLY}.txt` · `NEGCTL_{table,bid,tier,face}_0x24{,_postapply}.txt` · `TARGET_SHA_BEFORE_BID24.txt` / `POSTAPPLY_SHA_BID24.txt` |
| 工具 | `check_fp_binding.py` / `mk_sha256sums.py`（照抄 0x23 轮）· `_edits23_dump.txt`（生成器输入快照） |
| 自核 | `SHA256SUMS.txt`（本目录全件，71 件；⛔ 不含本 REPORT.md —— 落盘后需重跑 `mk_sha256sums.py`） · `PROGRESS.txt`（逐步时间线） |

另：构建前自动归档 `p7b_build_archive/20261013_082630/`（19 件 + SHA256SUMS；**内容是上一代 0x23 的 impl 产物**，位流 sha 已核 `066a3923…3126`）。

---

## §F 环境面观察（并行会话活动；**非本刀引入**，逐条登记）

1. **HEAD 移动**：开工 `f46a221` → 矩阵跑动期间 `30d2253 → 97c13e6` → 收工现读 **`0b06a2e`**。全部是**并行会话的提交**（文档迁移批次 3 / 台账 §10-33…§10-38 / `docs/HUMAN_LAYER.md` / 宿主读订正轮收口）。**未触任何本刀文件**（本刀 20 件改动全部留在工作树 `M`）。
2. **外来源码改写（3 件，纯注释）**：`07:55:11` 并行文档迁移把路径引用改写 ⇒ `rtl/mac_tx_64.v`（2 行注释 `audit_scratch/` → `agent_docs/audit_scratch/`）· `board/build_p6a_ku5p.tcl`（1 行注释）· `board/build_p5_diag.tcl`（1 行注释）。**判读：`git diff f46a221 97c13e6` 显示 4 行全在 `//` / `#` 内 ⇒ 零功能变化**。
   - **处置**（按派单规则："非你引入的**非注释**变化才停下报告"）：**不停**；登记 + **重绑**受影响的 xsim 门（`mut` 在改写前跑过 ⇒ 08:24:40 重跑，读数与首跑逐字相同：54 项 / MUTANT-CAUGHT）。
   - ⚠️ `board/build_p6a_ku5p.tcl` / `build_p5_diag.tcl` **不在本刀的构建路径**（本刀只走 `build_p7b_ku5p.tcl`）；`rtl/mac_tx_64.v` 在构建路径内，构建编译的是**改写后**版本（纯注释 ⇒ 无影响）。
3. **文档迁移的连带面**：仓根 `int_scratch/`、`review_scratch/` 等已被移入 `agent_docs/` ⇒ 读侧搜索面出现 1 件"路径失配"新命中（`agent_docs/int_scratch/tb_int_axr36.v`），已在 §B-3 加 ALLOW 登记（只登记不动）。**若迁移继续移动目录，后续轮的读侧 assert 会再报新命中** —— 属结构迁移的正常副作用。
4. **`docs/HUMAN_LAYER.md` 新规则**（owner 2026-10-13 裁定：人读层文档变更须通知 kimi 审查）：本轮已按用户当面指令 **通知 `kimi-tl`**（bridge `m_b310616c6d57`，含本刀文档面变更清单 + 预告 `REPORT.md` 落盘；⚠️ 该消息写于 HUMAN_LAYER 落盘前、未带 `ref` 字段 —— 收口后已补发带 `ref` 的短报文 `m_be19b423771f`）。**本刀对 Tier A/B（README/docs/INDEX/PORT_NOTES/OPEN_ITEMS/台账）零改动**；本报告 = Tier C。
5. **owner 关机令（台账 §10-38）**：本轮（构建 0x24）= 执行序①的"在飞余其一" ⇒ **本报告交回即解锁后续序**（② `P7B_LOOP_HANDOFF.md` §6 更新 / ③ 知会 kimi / ④ 对端清理+关机 / ⑤ 本机入库+推送+关机）。**执行权在 TL**；本轮 ⛔ 未替 TL 执行（未提交、未关机、未碰对端）。

---

## §G 未竟项 / 未定项（⛔ 不许当"已答"接手）

1. **`0x24` 位流未上板**（本轮不烧板、不写 QSPI）⇒ 身份五判据 / 干净抓取 / URAM 缓冲的**板级行为**（吸收 25.6 µs 窗口 / `MIR_DMA_CNT` 与缓冲占用的差账 / 两条工具恒等式）**全部未测**。板上仍 = `0x23`（且按 §10-38 §④ 要收成停流态）。
2. **`synth 8-6793` 硬门的字面口径 = 56 ≠ 0**（全部既存 `retx_ram`，与 0x23 逐族同分布）—— **判据口径裁定权在所有者**（本节只把"新件 0 条"与"全日志 56 条"两个读数并列）。
3. **时序归因未做**：全局 WNS `+0.098 → +0.066`、宿主从 pcie 域换回 DP 域、`u_mir_axis` 锥 +0.687→+1.279 / +0.645→+0.821、`u_mir_buf` 族的绝对量级 —— **无拆刀 A/B，一律不归因**（#66）；本轮唯一能写的 = 读数本身（`+0.066 / +0.010 / 三类失败端点 0/0/0`）。**不许写"时序已解决"**。
4. **`sim/p9_uram` 单元门本轮未重跑**（派单只点名 mut/mut2 + 矩阵）⇒ 该门的 59 判据/12 突变臂/2 守卫的读数**归修正轮**（出处 `p9_uram_20261013/FIX_REPORT.md`）。
5. **`mut_bwire.py` 锚点重对 = 本轮修** ⇒ 0x22/0x23 两代**从未真正执行**过 mut2 突变的窗口客观存在；本轮不能反推"那两代该门曾绿"（那两代门读数里 mut2 是否被引用 = 未核）。
6. **XPM 内部告警（8-6014 `gen_epipe` / 8-7137 `o_mem`）**：判读为良性（§C-3），但**未做**行为模型 ↔ 综合后网表的读延迟一致性门后仿真（同 URAM 报告 §7-1 的既有未竟项）。
7. **`dbg_occ/dbg_oocc` 仍空接**（缓冲水位无观测口）；接进快照会改窗口几何（71 字 / 0x14C）⇒ 属另一轮。
8. **`P7B_WPWS` 34 组值已落 `p7b_ku5p_stdout.txt`**（min 0.010 / max 998.845，0 失败端点），本轮未逐组与 0x23 对比（无判据要求；跨代比先过 #66）。
9. **并行面未定**：文档迁移仍在途（§F-3）⇒ 下一轮读侧 assert 可能再报新命中；TL 的 §10-38 执行序 ②–⑤ 未执行（交回后由 TL 定）。

*本件 = 构建轮读数与归档；判据层面的裁定（含 `8-6793` 口径、`0x24` 是否直烧）归判据所有者/owner。*
