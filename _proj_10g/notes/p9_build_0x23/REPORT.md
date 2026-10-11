# P9 构建轮 0x23 —— AXIS + D4 clr 口径修正（BID `0x23`）构建报告

**轮次** = 2026-10-12 00:11 → 01:40（本机）· **工作目录** = `D:\repo\XCKU5PMini\udp_hls_10g`
**开工 HEAD** = `5f03051`（台账 §10-25）· **收工 HEAD** = `5f03051`（**本轮不提交**；改动留在工作树 ⇒ 见 §D 绑定口径）
**派单** = A 读侧 BID-only 同步 `0x22 → 0x23`（阶段⑧）· B `board/wrapper_p4.v` 的 `BUILD_ID_V → 0x23`
· C 完整构建（唯一入口 `board/run_build_p7b_ku5p.bat`）· D 矩阵 17/17 + 两件指纹 + `GIT_HEAD` 前后核 · E 归档 · F 报告。
**本刀内容（0x22 → 0x23）** = `rtl/axis_c2h_stream.v` 的 **D4 停流/`clr` 口径修正**
（`clr` ⇒ **丢弃残拍不发拍** + clr 拍不拉 `dma_req`；非 clr 停流 = 排空 + 静置 `QUIET_N=32` 拍后**只发一拍短尾**；
`mv_last` 只对非满拍置位 ⇒ 整拍恒 `tlast=0`）。依据 = 板级 `0x22` 实测（旧口径 clr 冒 8 B 短拍
⇒ **EOP 早关描述符** ⇒ 宿主首块零填充 + 尾截断 + read 超时；件 `p9_board_0x22_20261011/runs/D4_BOUNDARY.txt`）。

**读数口径声明（先读这条）**
- 本报告**不下 PASS/FAIL 裁定**、**不写"时序已解决"**、**不把"未观测到"写成"不存在"**。
- 所有"是/否"句只描述**本轮实测到的读数**；判据层裁定权在判据所有者。
- **板上现役仍是 `0x22`**（本轮 ⛔ 不烧板、⛔ 不写 QSPI、⛔ 不碰对端机）；0x23 位流**尚未上板**。
- 本刀的门读数（单元门 / p6e 全链门）**出处 = 修正轮 `FIX_REPORT{,2}.md`，本轮未重跑** ⇒
  **17/17 矩阵对本刀 RTL 是空证据**（该件不在 6 manifest 内；见 §D-3）。

---

## §A 读侧 BID-only 同步 `0x22 → 0x23`（阶段⑧ = `EDITS_23`）

**做法（照抄上一轮，机械生成 + 全阶段读数）**
- 生成器 = `gen_edits23.py`：从现役脚本的 `EDITS_22` **new 侧**（= 盘上现状）逐条 +1 代
  （值 `0x22→0x23` + 代名 `P9 XDMA MM→AXIS → P9 D4 clr 口径修正` + 逐代历史链追加），
  **old 侧逐字自检 = 24/24 命中盘上现状**（0 条不匹配）。
- 拼接器 = `splice_phase8.py`：6 处锚点**唯一命中**（`EDITS_23` 声明 / `E8()` / `STAGES` / ⑭ 段插入 / docstring / ALLOW）。
- 阶段⑧ = **24 处 / 14 文件**（与 ⑥/⑦ 同名同形）· **几何一字不动**（仍 **71 字 / 未实现地址 `0x14C`**）。

| 阶段 | 阶段读数 | 结果 |
|---|---|---|
| dry-run | 24/24 `hits=1/1`；A 表长 5/5 OK；B 搜索面 **4 族 / 298 命中文件 / 未登记 0**（旧值族含 `0x22`：63 命中）；C 24 红 = **待改处**；D 覆盖 14/14 | `DRYRUN_BID23_OUTPUT.txt` |
| rehearse（内存 overlay，仓内不动） | 阶段 applied=24 / skipped=0；A/B/C/D **全绿 0 fail** | `REHEARSE_BID23_OUTPUT.txt` |
| negctl ×4（tempfile 破坏件） | `table` 1 红 · `bid` 24 红（**含目标断言**）· `tier` 24 红（**含目标**）· `face` 3 红 —— **四条全有牙 RC=1** | `NEGCTL_{table,bid,tier,face}_0x23.txt` |
| neg_rehearse（故意漏末条） | **恰 1 红** = 漏掉的那处（`step0_selfcheck.sh[BID]`），RC=0 | `NEG_REHEARSE_BID23.txt` |
| apply | RC=0 / 0 fail；**14/14 件 SHA256 全变**（前 → 后逐件落档） | `APPLY_BID23_OUTPUT.txt` / `TARGET_SHA_BEFORE_BID23.txt` / `POSTAPPLY_SHA_BID23.txt` |
| assert（复核） | RC=0；A 5/5 · B 4 族 290 命中 / **未登记 0** · C 全绿 · D 14/14 | `ASSERT_BID23_AFTER.txt` |
| face | **290 行 / 145 文件**，**未登记 0 行** | `FACE_BID23_AFTER.txt` |
| post-apply negctl ×4 + neg_rehearse | 四条仍**有牙**（1 / 1 / 1 / 3 红，含目标断言）；负彩排走**反演重建**路径仍**恰 1 红** | `NEGCTL_*_0x23_postapply.txt` / `NEG_REHEARSE_BID23_POSTAPPLY.txt` |

**哨兵/权威源复核**：读侧代哨兵 `j6_r6fix.sh` 的 `EXPECT_BID` 默认值 = `0x00000023`；
权威源 `board/wrapper_p4.v` 现读 = `SNAP_NW_P6E = 71` / `BUILD_ID_V = 0x00000023` ⇒ **两侧一致**（§B 改完后复跑 `--assert` RC=0）。

---

## §B `board/wrapper_p4.v`：`BUILD_ID_V` → `0x23`（2 hunk / +41 −3）

| # | 位置（现读行号） | 改动 |
|---|---|---|
| 1 | `:2144` | 版本戳注释：`本版 **0x22** 沿用` → `本版 **0x23** 沿用`（persist 现役构建配置块的自述） |
| 2 | `:4273` + 注释块 | `.BUILD_ID_V (32'h00000022)` → `32'h00000023`；`本轮构建 (2026-10-11): **0x21 → 0x22**` 块被新块取代，旧块降级为 `---- (以下为历史, 逐字保留) ---- / ⭐ 上一版 (2026-10-11): **0x21 → 0x22**。`（逐字保留，未删） |

**机检（防"顺手改了别的"）**
- `git diff board/wrapper_p4.v` = **2 hunk**；**非注释（无 `//`）改动行恰 1 行** = `.BUILD_ID_V (...)` 那一行。
- `tie-off` / `:1320-1321` / AXIS 端口表 / M1 块：`git diff` 命中 **0**。
- 改后文件 **4817 行**，sha256 = `68b36ffa4c1540db89a9df2785f95ff4e83258c71ded7a93f0c2bd967d820b5a`
  （与 §D 指纹里的 `board/wrapper_p4.v` 行**逐字相同**）。
- `board/build_p7b_ku5p.tcl` diff vs HEAD = **0**（构建脚本一字未动）。

**B 面（搜索面）未登记命中 = 逐条核内容（派单要求）**
- 断言可见面（`.sh/.bat/.py/.v/.vh/.tcl/.ps1/.cmd`）新命中 **5 件**，逐条核过、**0 条需改**：
  ① `_proj_10g/notes/p9_board_0x22_20261011/{_tools/run_arm.sh, final_state.sh, burn_0x22.sh}`
  = **烧 `0x22` 位流的板级现场件**（`WANT=c2e48a69…635a` / `EXPBID=0x00000022` / `NW=71` 由位流 sha256 钉死
  —— 改它反而毁掉那一轮取证）⇒ 登记为"旧位流读法"；
  ② `_proj_10g/notes/p9_build_0x23/{gen_edits23.py, _scan_newhits.py}` = 本轮生成器/预扫件 ⇒ 登记为"现役"。
- 非断言面（`.txt/.log/.md/.ORIG`，搜索面结构性地不扫）另 **8 件**也逐条核过（**同名不同物**）：
  `p7b_longsend_board/runs/LSLONG_run1.txt` 与 `p7b_retxfix/run_RXX.log` 的 `0x00000022` = **快照寄存器值**
  （`W55 stat_retx` / `W6 srx_stat_commit`，不是身份）；`p7b_tail/tb_uart_dbg.v.ORIG` = UART diag TB 的
  **计数器初值**（`cwi/sd = 32'h00000022`，与已登记的 `tb/tb_uart_dbg.v` 同族"侥幸命中"）；其余为本轮目录/报告件。
- ⇒ 新增 **2 条 ALLOW**（`p9_board_0x22_20261011/` = 旧位流读法 / `p9_build_0x23/` = 现役），
  splice 时同批写入；dry-run 与 assert 的 B 面均 **未登记 0**。

---

## §C 完整构建（`board/run_build_p7b_ku5p.bat`，一次收口）

**调用式** = `MSYS_NO_PATHCONV=1 cmd /c 'board\run_build_p7b_ku5p.bat'`（单斜杠式；⛔ 未用 GUI / 未用别的 tcl）。
**本次独有串（判"真的跑了"）** = `ARCHIVE_DONE 20261012_001552 files=19`；产物 mtime 全部落在本轮
（`p7b_ku5p_stdout.txt` 00:16:02 起、routed 报告 00:47 前后）—— 与上一轮归档 `20261011_215445` 无歧义区分。

| 项 | 读数 |
|---|---|
| **BAT_RC / BUILD_EXIT** | **0 / 0**；末尾 `BITSTREAM-OK` |
| **一次收口（计数式）** | `P7B_ROUND #1` 恰 **1** 次 · `BUILD_EXIT` 恰 **1** 次 · `P7B DONE` 恰 **1** 次 · `Exiting Vivado` 恰 **3** 条（synth `00:28:19` / impl `00:49:15` / 父 `00:50:30`） |
| **P7B_WNS / P7B_WHS** | **+0.098 / +0.010**（`P7B_CONVERGED_AT_ROUND = 2`；`IS_LOCKED_POSTGEN = 0`） |
| **三类失败端点** | **0 / 0 / 0**（setup 0/257,882 · hold 0/257,882 · pulse-width 0/83,896）；报告面 `Slack (VIOLATED)` **0 条** |
| **位流** | sha256 = `066a3923351b8f539a986b88d96f1093a686da57f95938e0c8837b13d30a3126` · **15,431,261 B**（与历史各档**逐字节同长** ⇒ 只有 sha256/BID 能分版） |
| **构建前归档（#54）** | `p7b_build_archive/20261012_001552/`（19 件 + SHA256SUMS）—— 归档的是**上一代（0x22）** impl 产物；`wrapper_p4.bit` sha256 实测 = `c2e48a69…635a` = **0x22 位流**（provenance 已核） |
| **硬门（12 键）** | `DROPPED-CONSTRAINT-FAIL` / `IMPLICIT-NET-FAIL`（5 键）/ `DRC-KEY-FAIL`（6 键）**全 0 命中** |
| **DRC（routed）** | **0 Error / 0 Critical**；Warning 五族（DPIP-2 4 · DPOP-3 2 · DPOP-4 4 · DPOR-2 18 · REQP-1858 41）与 0x22 **逐数相同** |
| **Route status** | 195,527 logical nets / **137,366 全布通** / **routing errors = 0** |

**XDMA 配置断言组（全过；静默回滚防线）**

| 判据 | 读数 |
|---|---|
| `P7B_XDMA_RC_BASE` | **0**；MSG = `<>`（无消息命中 ⇒ 无 `19-3461`/`19-3438`） |
| `P7B_XDMA_RC_INTF` | **0**；MSG = `<AXI_Stream>` |
| `P7B_XDMA_RB_MISMATCH_N` | **0**（13 项回读 13/13） |
| `P7B_XDMA_GEN_BAD_N` | **0**（生成产物 6 参数 6/6） |
| `P7B_XDMA_CFGDIFF_ST_N` | **1** = `{CONFIG.Component_Name}`（= 预期：组件实例名） |
| `P7B_XDMA_CFGDIFF_MM_N` | **2** = `{CONFIG.Component_Name CONFIG.xdma_axi_intf_mm}`（= 预期：MM 参照 + AXI_Stream 本项） |
| `P7B_XDMA_VERDICT` | **OK** |

**资源（board 口径 / placed 报告）与 0x22 并列**

| 资源 | **0x23** | 0x22 | Δ |
|---|---|---|---|
| CLB LUTs | **77,878** | 78,006 | **−128** |
| CLB Registers | **74,209** | 74,200 | **+9** |
| Block RAM Tile | **348**（RAMB36E2 317 + RAMB18E2 62） | 348（同分解） | 0 |
| URAM | **0** | 0 | 0 |
| DSP48E2 | 4 | 4 | 0 |
| Bonded IOB / GTYE4 | 10 / 6 | 10 / 6 | 0 |

**时序定位（后布线定向查询 `q_0x23.tcl`；基座 = `q_0x22.tcl` 逐条同形，仅加本刀新族）**

| 面 | **0x23** | 0x22（对照） |
|---|---|---|
| **全局 WNS** | **+0.098** —— 宿主 = `u_snap_dp/valid_a_reg/C → u_snap_seq/dout_reg[268]/CE`（**lvl=2**；top5 五条同值同族） | +0.025 = DP 域 |
| **DP 域 WNS（`g_hw.clk_out0`）** | **+0.311** `u_tcp_tx/recv_first_reg/C → u_tcb/snd_nxt_r_reg[9][28]/CE`（lvl=17；DP top10 全在 `u_tcp_tx → u_tcb` 旧族，**u_mir/fifo 族 0 条进前 10**） | +0.025（= 全局最差） |
| **`u_mir_axis` 定向锥** | **FROM +0.687**（`u_mir_axis/b_v_reg/C → axist_c2h slv axi_wto_cnt_100_reg[31]/D`）· **TO +0.645**（`u_pcie_regs/s_axil_arready_reg/C → u_mir_axis/s1_data_reg[25]/CE`） | **+0.914 / +0.648** |
| `u_mir_axis` cell 数 | **389** | 365（**+24** = D4 新逻辑） |
| 本刀新状态族 | `qcnt_reg*` **6 cells**（from +1.682 / to +0.886）· `clr_drop` **NOCELL**（网名归并产物，无独立 cell）· `dma_words_reg*` 35 cells（to +0.765 = 异步复位 CLR 面） | 不存在 |
| `m1_all` / `m1_app_core` | +0.687 / +0.532（2164→**2189** cells） | +0.499 / +0.524（2164） |
| `m1_dp_from` / `m1_dp_to` | +1.031 / +1.031 | +1.239 / +0.524 |
| `u_mir_ring` / `u_mir_c2h` / `u_mir_h2c` / `axis_c2h*` | **NOCELL ×4**（MM 从机确已移走 / 无同名网） | 同（NOCELL） |
| 未受伤复核（persist / 0x1C / 0x1E / P8-STG 族） | `ps_stage` to +0.318 · `dup_l_reg` to +0.860 · `ack_adv` to +0.843 · `ring_hi` to +1.133 · `stg_data` to +1.590 · `acc_cnt_r` to +1.211（**均非 DP 前 10**） | 见 `p9_build_0x22/q_stdout.txt` |

⛔ **口径（#66）**：**全局 WNS 宿主本轮换位**（0x22 的全局最差 = **DP 域**路径；0x23 的全局最差 = **pcie 域** `u_snap_dp→u_snap_seq` 2 级路径
—— 判域依据两条：① 它**不在** DP 组前 10（DP 组 #1 = `+0.311` > `+0.098`）② 全局 `P7B_WNS = 0.098`
与 **pcie 域 intra 表 `0.098` 逐字对上**）
⇒ 两个 `+0.098`/`+0.025` **不是同一对象**，**不比大小**。DP 域自身 `+0.025 → +0.311`、pcie 域 `+0.240 → +0.098`
（同域内可比的那一对已如实并列；**无拆刀 A/B ⇒ 不归因**给本刀 —— 本刀 RTL 只动 `axis_c2h_stream.v`（pcie 域），
而 P&R 重排本身就能搬动两域读数）。

---

## §D 回归矩阵 17/17 + 两件指纹 + `GIT_HEAD` 前后核

**调用式** = `MSYS_NO_PATHCONV=1 cmd /c 'sim\p4gates\run_matrix_p4dfix.bat'`（单斜杠式）。
**与 Vivado 严格串行（#47）**：矩阵 `01:01:49 → 01:26:58`，构建（00:16→00:50）与定向查询（00:56→00:59）**均已在它之前收口**。

| 判据 | 读数 |
|---|---|
| `gates run` / `gates failed` | **17 / 17** · **0** |
| `VERDICT`（冻结核） | **FROZEN** —— 257 件哈希在跑动前后**逐字节相同**（`this log is bound to revision DIGEST_ALL(content)=e1730a4c…f15f6`） |
| `DIGEST_COMPILE`（212 件） | `614538a7531b0b037cd05225a0ae06e0e283988c3b08335f96306274c09cc990`（before = after） |
| `DIGEST_ALL`（257 件） | `106a28c6002218e17924c5418a61d7817cc525bdb8f33febcf62245507522cb5`（before = after） |
| **`GIT_HEAD`** | **before = after = `5f03051`**（= 开工 HEAD；本轮**未提交** ⇒ 收工也不变） |
| 单门读数（静默门复核） | `unit_retx` / `unit_fifo` / `unit_vlan` / `unit_uart` / `p5_wrapper` 全 `EXIT=0`（矩阵日志尾已逐门保留；`unit_*` 无条件 exit 0 ⇒ 其**日志尾**已一并归档） |
| 两件指纹 | `P4_MATRIX_FINGERPRINT_20261012_010149_{before,after}.txt`（均在本目录）+ `matrix_p4dfix.log` |

**逐件绑定核对（`check_fp_binding.py`；判据 = 指纹集内每件 vs 盘上现读 vs `git diff --quiet HEAD`）**

- ① **指纹 == 盘上现读：257 / 257**（不一致 0 ⇒ 指纹没有飘）。
- ② 257 件**全部**在 HEAD 里可查（tracked）；**256 件逐字 == HEAD**，**仅 1 件 ≠ HEAD = `board/wrapper_p4.v`**
  —— 即 **§B 那一刀（2 hunk / 未提交）**，与指纹工具自报的 `MODIFIED vs HEAD (tracked, inside the hashed set): 1`
  **两面一致**。⇒ **"指纹绑 HEAD + 本刀 B 项"**，无第三个改动面（`rtl/` 38 件、`tb/`、`board/build_p7b_ku5p.tcl` 的
  `git diff HEAD` 命中全 **0**）。
- ⛔ **本核对的第一版方法学错误（如实登记）**：初版用 `git show HEAD:<p>` 的**原始字节**与盘上原始字节比哈希，
  报出 **40 件"≠HEAD"**（含 6 件 RTL + 33 个 bat）—— **全属假阳性**：本仓 `core.autocrlf=true`
  （`git ls-files --eol` 实测 `i/lf w/crlf`）⇒ 盘上是 CRLF、git 对象里是 LF。**判据必须走 `git diff --quiet HEAD`**（规范化比较）。
  **教训（本工程新增坑候选）**：*"文件 == HEAD"的判据不能用裸字节哈希，除非先核 `core.autocrlf`/`.gitattributes`*。

**覆盖声明（本刀 RTL 与本矩阵的关系 —— 不许当"已回归"读）**

- 本刀**唯一行为改动** = `rtl/axis_c2h_stream.v`（D4 clr/停流口径）。
- **6 个 manifest 对它命中 0**（`chain_src / retx_src / fifo_src / vlan_src / uart_src / p5wrapper_src` 全部不含该件）；
  `wrapper_p4.v` 只在 `p5wrapper_src.f` 里，而该门**只传 `-d APP_MODE`**，而 `u_mir_axis` 例化被
  **`APP_MODE ∧ DP_156MHZ` 双包**（`board/wrapper_p4.v:3769/3843`）⇒ **该实例根本没被编进去**。
- ⇒ **17/17 对本刀的行为面 = 空证据**（它证明的是"默认构建 + APP_MODE 面没被碰坏"，不是"0x23 的 clr 逻辑对"）。
- **本刀该有的门 = 修正轮已跑**（出处 `p9_axis_impl_20261011/FIX_REPORT{,2}.md`，**本轮未重跑**）：
  单元门 **real PASS_ALL（100 PASS / 0 FAIL）+ 12 突变臂全捕获**（红灯面两两不相等；⭐ `mut_clrdrop`
  = "clr 改回发残拍" = 板级那条缺陷形态，被 G7g/G7x 抓住）；p6e 真 wrapper 全链 **real PASS_ALL（143 PASS / 0 FAIL）**
  + 旧口径 RTL 排练 **8 FAIL 全落新判据**（其余 135 PASS）。
- ⛔ 推论（写清楚，别让下游误读）：**0x23 的行为正确性证据目前仍是"修正轮的 xsim 门"这一条**；
  **板上未测**（本轮不烧板）⇒ 板级收口要等下一轮的板级轮。

---

## §E 归档（`_proj_10g/notes/p9_build_0x23/`，**本轮内落盘**，#54）

| 组 | 件 |
|---|---|
| 位流 / 网表 | `wrapper_p4.bit`（15,431,261 B，sha256 `066a3923…3126`）· `wrapper_p4_routed.dcp`（62,708,492 B） |
| 板级/构建报告 | `board_rpt/`（14 件 = `wrapper_p4_{timing_summary_routed,utilization_placed,utilization_synth,clock_utilization_routed,control_sets_placed,drc_routed,power_routed,route_status}.rpt` + `p7b_ku5p_{timing,util,drc,clkinteract}.rpt` + `p7b_ku5p_xdma_cfg_post_gen.txt` + `runme_impl_1.log`）· `build_console.txt`（含 `ARCHIVE_DONE 20261012_001552` 本次独有串与 `BAT_RC`） |
| 定向查询 | `q_0x23.tcl` · `run_q.bat` · `q_stdout.txt`（`QUERY_EXIT=0`，Exiting Vivado `00:59:07`）· `q_bat_console.txt` · `query_out/`（`global_top5.rpt` / `dp_top10.rpt` / `dp_top50.rpt`） |
| 矩阵件 | `matrix_stdout_raw.txt`（GBK 原样）+ `matrix_stdout_utf8.txt` · `matrix_p4dfix.log` · `P4_MATRIX_FINGERPRINT_20261012_010149_{before,after}.txt` · `FP_BINDING_CHECK.txt` · `_gitdiff_head_names.txt` |
| 读侧件（A） | `gen_edits23.py` · `EDITS_23_BLOCK.txt` · `splice_phase8.py` · `DRYRUN_/REHEARSE_/APPLY_/ASSERT_/FACE_BID23*.txt` · `NEGCTL_*0x23*.txt`（4+4）· `NEG_REHEARSE_BID23*.txt` · `TARGET_SHA_BEFORE_BID23.txt` / `POSTAPPLY_SHA_BID23.txt` |
| 工具/预扫 | `_scan_newhits.py`（B 面预扫）· `check_fp_binding.py`（D 绑定核对）· `_mk_run_q.py` · `mk_sha256sums.py` |
| 自核 | `SHA256SUMS.txt`（本目录全件；含位流与 routed dcp）· `PROGRESS.txt`（逐步时间线） |

另：构建前的自动归档 `_proj_10g/notes/p7b_build_archive/20261012_001552/`（19 件 + 其 SHA256SUMS；
**内容是上一代 0x22 的 impl 产物**，位流 sha 已核 `c2e48a69…635a`）。

---

## §F 未定项 / 未测项（⛔ 不许当"已答"接手）

1. **0x23 位流未上板**（本轮不烧板、不写 QSPI）⇒ 身份五判据 / ST 三条 / 干净抓取 / **D4 后果链复测**
   （`clr` 后应无短拍 / 停流只一短尾）**全部未测**。板上现役仍是 `0x22`（受控停流）。
2. **矩阵对本刀 RTL 空证据**（§D-3）：`axis_c2h_stream.v` 不在任何 manifest；本刀行为面证据
   = 修正轮 xsim 门（单元 100/0 + 12 突变臂；p6e 143/0 + 旧口径排练 8 红），**本轮未重跑**。
   是否把 `axis_c2h_stream.v`（或 p6e 全链门）**接进常驻矩阵**= 待决（同 P8 轮的覆盖声明问题）。
3. **时序归因未做**：DP `+0.025→+0.311`、pcie `+0.240→+0.098`、全局 WNS 宿主**换域**（DP → pcie 域）
   —— **无拆刀 A/B，一律不归因**（#66：WNS 是"不同对象"）。本轮唯一能写的 = 读数本身
   （`+0.098 / +0.010 / 三类失败端点 0/0/0`）。**不许写"时序已解决"**。
4. **`u_mir_axis` 定向锥读数 = 单点事实、非"改善了"的证明**：FROM `+0.914 → +0.687`、TO `+0.648 → +0.645`
   同时 cell 数 `365 → 389`；**两代 P&R 不同 ⇒ 只能并列，不能当趋势或收益**。
5. **`clr_drop` 在网表里 NOCELL** —— 它被综合/归并掉了（= 本工程"网名 ≠ RTL 信号"族，见全局 #90）。
   ⇒ "clr 语义改对了"这件事**在网表面无法用该名字自证**，只能回 xsim 门 / 板级行为面。
6. **B 面 8 件非断言扩展名命中**（`.txt/.log/.md/.ORIG`）**结构性不被搜索面覆盖** —— 本轮是人工逐条核的
   （结论：全是"同名不同物/寄存器值"）；这条*人工*覆盖面不随脚本走 ⇒ **下一轮若新增同类文件，仍要靠人核**。
7. **`P7B_WPWS` 34 组值已落 `build_console.txt`**，本轮未逐组与 0x22 对比（无判据要求）；若要跨代比，
   先过 #66（逐组宿主可能不同）。
8. **两处既存工具事实（登记，非本刀引入）**：`localparam NW` 类断言在 `p7b_biz_win` 之外仍走"名字表长度"而非现读；
   `q_0x23.tcl` 的 `E` 段只列前 30 cell/族（`u_mir_axis` 389 ⇒ 清单被截断）—— 与 0x22 的查询面**同形**，
   **跨代并列成立**，但**不能拿它当"全 cell 清单"**。
9. **本轮未跑**：`ss -ti` / 板级任何项 / `run_tb_p6e_pcie_wrapper.bat` 重跑 / 矩阵以外的门。
