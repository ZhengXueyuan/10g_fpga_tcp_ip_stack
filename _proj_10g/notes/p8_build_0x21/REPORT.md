# P8 构建轮（BID `0x21` = P8-STG 镜像采集侧 16 B 字节粒度弹性暂存）—— REPORT

**边界声明**：未烧板 / 未连 JTAG / 未 ssh 对端 / 未写 QSPI / 未改 `rtl/`（一律只读）/ 未走 GUI `vivado_prj`
旧 wrapper / 仓内无 `prj_*` scratch。构建只走 `board/run_build_p7b_ku5p.bat`。git **只读（未提交）**。
**本轮不下 PASS/FAIL 裁定、不写"时序已解决"、不把"未观测到"写成"不存在"。**

| 项 | 值 |
|---|---|
| 位流 | sha256 **`fbb6fca81076a28b80fcc7a794de698c4253cc36961b7b682887818e1514892c`** / **15,431,261 B** |
| 位流身份 | `BUILD_ID_V = 32'h00000021`（源码面 `:4332`）；⚠️ **位流面回读（板上 `0x04`）本轮未做 —— 需烧录**（见 §7-1） |
| 构建 | `P7B_WNS = 0.044` / `P7B_WHS = 0.010`；**三类失败端点 `0 / 0 / 0`**（setup 0/261,899 · hold 0/261,899 · pulse-width 0/84,934）；`BUILD_EXIT=0` / `BAT_RC=0`；**一次收口**（单次调用未重跑：`P7B_ROUND #1` 恰 1 次 / `BUILD_EXIT` 恰 1 行 / `P7B DONE` 恰 1 次；stdout 里 3 条 `Exiting Vivado` = 同一次运行的子进程：synth 18:03:59 / impl 18:26:24 / 父 18:27:34）；`CONVERGED_AT_ROUND=2` / `IS_LOCKED_POSTGEN=0` |
| 矩阵 | **17/17 门 EXIT=0，`gates failed: 0`，`VERDICT: FROZEN`，`MATRIX_RC=0`** |
| 几何 | **不变**：71 字（`SNAP_NW_P6E = 71`）/ 未实现地址 `0x14C`（与 0x20 逐字相同） |
| DP 域 | `g_hw.clk_out0` setup WNS **`+0.044` = 全局最差**；最差路径 `u_tcp_tx/u_fifo_b/rptr_reg[0]/C → u_tcb/rcv_nxt_r_reg[0][22]/CE`（lvl=15；logic 1.410 ns / route 4.652 ns = 76.7% 布线）；DP 组内 setup `0/144,493` 失败端点 |
| M1 族 | **DP 组内**最紧 slack **`+0.391`**（`u_mir/acc_cnt_r_reg[0]/C → u_mir/u_fifo/mem_reg_0_63_28_34/RAMD/I`，lvl 7）⇒ 与 DP WNS 差值 **0.347 ns（比值 8.9×）**；**全钟面**最紧 `+0.171`（lvl=0 的异步复位 CLR 路 `…/user_reset_reg/C → u_mir_h2c/aw_got_reg/CLR`，**非 DP setup** ⇒ 与 DP WNS 不同对象，只登记不比大小） |
| STG 新锥（本刀主角） | `stg_cnt` from **+0.665**（lvl 7 → `u_mir/u_fifo/mem_reg_0_63_28_34/RAMD/I`）/ to +1.537（lvl 13）· `stg_data` from +2.866 / to +0.888（lvl 13）· `acc_cnt_r` from **+0.391**（= M1 面最紧）/ to +1.782 · `acc_r` from +3.683 / to +1.303 · **`stg_ret` / `beat_pl` / `nbmask` = NOCELL**（纯组合锥，无寄存器单元 ⇒ 只能按 from/to 定向查询覆盖）；⭐ **`u_mir` 在 DP top10 / DP top50 / global top5 = 0 命中** |
| 资源（placed） | LUT **78,699** / FF **74,795** / BRAM tile **352**（R36 321 + R18 62）/ URAM **0** / DSP 4 / BUFGCE 4 / GTYE4 6；对照 0x20 后布线（LUT 78,156 / FF 74,723 / BRAM 352）⇒ **跨网表差值 LUT +543 / FF +72 / BRAM ±0，无拆刀臂 ⇒ 不归因** |
| DRC | 69 checks，**全 Warning（0 Error / 0 Critical）**（DPIP-2 4 / DPOP-3 2 / DPOP-4 4 / DPOR-2 18 / REQP-1858 41）；`route_design completed successfully` / `write_bitstream completed successfully` |

---

## §0 与派单描述的对齐检查（如实报）

1. **读侧脚本开工时末代 = `0x20`** ⇒ `--bid 0x21` 会直接 `SystemExit("不支持的 --bid")`。派单已预告
   "0x21 大概还要再扩一代" ⇒ 本轮先扩**阶段 ⑥**（`EDITS_21`；**BID-only**，几何 = 71 字 / `0x14C`；
   **24 处 / 14 文件**），再照脚本既定阶段顺序跑全阶段。**与派单一致。**
2. **`sim/p4sim/run_matrix_p4dfix.bat` 不存在**（只有 shim `run_matrix_p4dfix.sh`，它 exec 真 runner
   `sim/p4gates/run_matrix_p4dfix.bat`）—— 与派单一致，本轮用 shim。
3. **构建调用式**：本轮实测可用的就是派单给的 **`MSYS_NO_PATHCONV=1 cmd /c '…'`（单斜杠）**；
   `MSYS_NO_PATHCONV=1` + `cmd //c` 并用会互相抵消（派单已警告）⇒ 未踩。新鲜性判据（#72）=
   **`ARCHIVE_DONE 20261011_175317`（本次独有串）+ `board/p7b_ku5p_stdout.txt` mtime 16:07 → 18:27 +
   控制台含 `BUILD_EXIT=0` / `BITSTREAM-OK`**；wrapper mtime 17:53:06 → 构建 17:53:15（晚 9 s）。
4. **HEAD 在轮内被推到 `70d5ba4`**（开工 = `889cd28`）。该提交 = TL 的**只读审查轮**，只含 2 个文档件
   （`_proj_10g/notes/P7B_TL_LEDGER_20261010.md` + `_proj_10g/notes/p8_mir_stg_20261011/REVIEW.md`；
   `git show --stat` 逐字），**不涉 RTL / 顶层 / 构建 / 读侧** ⇒ 对本轮读数零影响；
   矩阵 `GIT_HEAD` BEFORE = AFTER = `70d5ba4`。
5. `board/wrapper_p4.v:4332` 现读确为 BUILD_ID 行（与派单行号一致）；⚠️ 与 0x1D 轮记的别名块
   `:2788-2792` 无关（那是另一处，本轮未碰）。
6. `rtl/app_rx_mirror.v` 工作树 sha256 = `d0310dd4…aa373`（与 `p8_mir_stg_20261011/IMPL_REPORT.md` §1 一致；
   本轮**零改动，只读**）。
7. ⚠️ 派单说的"24 处/14 文件"模式成立；**唯一文字差异** = `sim/p6e_pcie/tb_p6e_pcie_wrapper.v` 断言串里
   "8 B/拍" → "16 B 弹性暂存"（该 TB 不在 17 门矩阵内 ⇒ 常量已同步、运行验证未做，见 §7-7）。

---

## §1 A 读侧 BID-only 同步 `0x20 → 0x21`

### A0 阶段 ⑥（本轮新增，写进 `_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py`）

- `EDITS_21` + `E6()` + `STAGES` 追加 `("0x00000021", EDITS_21, "P8-STG 16 B 弹性暂存 (2026-10-11)", 71, 0x14C)`
  （**BID-only**：几何与 0x20 逐字相同）；顶部 docstring 加 ⑥ 指针。`git diff --stat` = **+140 / −2 行**（该脚本）。
- **覆盖的 14 文件（24 处，逐条）**：`_proj_10g/notes/p7b_affinity/j6_r6fix.sh`(2) ·
  `_proj_10g/notes/p7b_biz_tcpreg/tcpreg_j6.sh`(2) · `_proj_pcie/p7b_biz/p7b_snap.sh`(2) ·
  `_proj_pcie/p6e_snap_check.sh`(1) · `_proj_pcie/p7b_gate4_accept.sh`(1) · `_proj_pcie/p7b_gate4_selftest.sh`(2) ·
  `_proj_pcie/p7b_gate4_negctrl.sh`(2) · `_proj_pcie/p7b_gate4_livefake.sh`(2) · `_proj_pcie/p6e_snap_selftest_fix2.sh`(1) ·
  `_proj_10g/notes/p7b_gate4_3/final_state.sh`(1) · `_proj_10g/notes/p7b_gate4_criteria/gen_inputs.py`(4) ·
  `sim/p6e_pcie/tb_p6e_pcie_counters.v`(1) · `sim/p6e_pcie/tb_p6e_pcie_wrapper.v`(1) ·
  `_proj_10g/notes/p7b_a3_negctl_20261010/step0_selfcheck.sh`(2)。
- 另加 **2 条 ALLOW**（分类动作，见 A1-B）；**未改**任何 ALLOW 外的件。

### A1 逐阶段读数（原始件全在本目录）

| 阶段 | 命令 | RC | 读数 |
|---|---|---|---|
| dry-run（扩 ALLOW 前） | `--bid 0x21` | 1（**预期**：C 红 = 待改处） | 24 处 **hits=1/1 全 OK**；A 表长 5/5 OK；**B 报 3 条未登记命中**（见下）；C = 24 条红（= 待改清单）；D `EDIT_COVERAGE 14/14` |
| B 面分类 | — | — | 3 条未登记**全在 `_proj_10g/notes/p8_board_0x20_20261011/`**（`burn_0x20.sh` / `_tools/run_arm.sh` / `final_state.sh`）。**核过内容**：`WANT=998ff90f…`（= **0x20 位流 sha256**）/ `EXPBID=0x00000020` / `BID=${BID:-0x00000020}` / `EXPECT_BID=0x00000020` ⇒ 都是**烧 0x20 归档位流**那一代的真值 ⇒ 归 **"旧位流读法/位流绑定（只登记不改）"**，加 1 条 ALLOW（**未改那三个文件**）；另加 1 条给构建轮目录 `p8_build_0x2[01]`（读数/归档·非读侧） |
| dry-run（扩 ALLOW 后） | `--bid 0x21` | 1（**预期**） | 24/24 OK · A 5/5 · **B 4 族 263 命中文件全登记（未登记 0）** · C 24 红 · D 14/14 |
| rehearse | `--rehearse` | **0** | 阶段 ⑥ `applied=24 / skipped=0`；A/B/C/D 全绿；`REHEARSE OK —— 清单完整且自洽 … 0 fail` |
| negctl（有牙） | `--negctl={table,bid,tier,face}` | **1/1/1/1** | 4 条全"有牙"：table = 删 WLABEL 末项 ⇒ 恰 1 红；bid = EXPECT_BID 改 0x09 ⇒ 24 红**含目标** `j6_r6fix.sh[BID]`；tier = 档表首行改错代 ⇒ 24 红**含** `tcpreg_j6.sh[TIER_TOP]`；face = 造未登记新文件带上一代值 ⇒ 3 红 |
| neg_rehearse | `neg_rehearse.py 0x21` | **0** | 故意漏末阶段最后一处 ⇒ **FAIL 恰 1 条**（`step0_selfcheck.sh[BID]`） |
| apply | `--bid 0x21 --apply` | **0** | `APPLY_READSIDE_BID OK (target 0x00000021, 1 阶段 / 24 处 edit, 0 fail)`；**14/14 件 SHA 全变** |
| assert（落盘后） | `--bid 0x21 --assert` | **0** | `0 阶段 / 0 处 edit, 0 fail`；搜索面 OK |
| face（落盘后） | `--bid 0x21 --face` | 0 | 256 行 |
| negctl postapply | 同上 ×4 | **1/1/1/1** | 各只剩注入那条红：table 1 / bid 1（含目标）/ tier 1（含目标）/ face 3 ⇒ 落盘后断言面无其它红 |
| neg_rehearse postapply | `neg_rehearse.py 0x21` | **0** | 反演重建 apply 前态后同结论：**恰 1 条红** |

**交叉核对（"上一代同步未被破坏"）**：14 件 apply 前 SHA 逐条对 0x20 轮 `POSTAPPLY_SHA_BID20.txt` ——
**14/14 逐字相同** ⇒ 读侧 `0x20` 那一代在 HEAD 上**完好**（轮内无并发读侧改动）。

---

## §2 B `BUILD_ID_V` 0x20 → 0x21（`board/wrapper_p4.v`）

| 项 | 改前 | 改后 |
|---|---|---|
| `.BUILD_ID_V`（行 `:4332`） | `32'h00000020` | **`32'h00000021`** |
| 该行注释块 | 顶部 = `//   ⭐ 本轮构建 (2026-10-11): **0x1F → 0x20**。` | **新增 0x21 段（33 行）**：P8-STG 16 B 字节粒度弹性暂存（成因 = 0x20 位流板级 A/B `9ad13da` 的"相位≠0 恒丢 49.883%"；门/synth 检查点指针；几何不变 71 字 / `0x14C`；回退点 = 回滚 `889cd28`；口径位移 = 残余项 `acc_cnt_r + stg_cnt`）+ 历史链；0x20 段整段降级进新的 `---- (以下为历史, 逐字保留) ----`（逐字未动，仅标签 `本轮构建` → `上一版`） |
| `:2144` persist 注释头 | `本版 **0x20** 沿用` | **`本版 **0x21** 沿用`**（先读后判：该句 = 版本戳性质） |

**核验**：`git diff --stat board/wrapper_p4.v` = **只有 2 个 hunk**（`:2144` 一行 + `:4332` BID 块）、
**36 insertions / 3 deletions**；**未动** M1 块与 `:1319-1322` app 总线 tie-off（现读逐字确认：
`app_reg_addr = 8'h00` / `app_reg_wr = 1'b0` / `app_reg_wdata = 32'd0`）。改后工作树 sha256 =
**`bd8f608cc4fce9283f5e14018a1cdf8101667aa2d63ae36d8be2e767254fd7d0`**（304,144 B / 4790 行）。

---

## §3 C 完整构建

- **入口**：`MSYS_NO_PATHCONV=1 cmd /c 'D:\repo\XCKU5PMini\udp_hls_10g\board\run_build_p7b_ku5p.bat'`（§0-3）。
- **读数**（`board/p7b_ku5p_stdout.txt` + `board/p7b_ku5p_timing.rpt`）：
  `P7B_WNS = 0.044` / `P7B_WHS = 0.010` / 三类失败端点 **0/0/0** / `P7B_BIT_EXISTS = 1` /
  **`All user specified timing constraints are met.`** / 三条硬门（`12-4739` / 隐式网 5 键 / DRC 6 键）**扫描 0 命中**。
  `P7B_WPWS` 打印的是**逐组 slack 列表**（34 个数，最小 0.010），**不是**单一 WPWS —— 逐字留档在 `build_console.txt`。
  ⭐ **`Slack (VIOLATED)` 在 timing rpt 中 0 条**。
- **一次收口**：`P7B_ROUND #1` 恰 1 次 / `BUILD_EXIT=0` 恰 1 行 / `P7B DONE` 恰 1 次 ⇒ **未重跑**。
- **资源（placed）对照**：

  | 项 | 0x20（后布线） | **0x21（后布线）** | Δ |
  |---|---|---|---|
  | CLB LUTs | 78,156 | **78,699** | **+543** |
  | CLB Registers | 74,723 | **74,795** | **+72** |
  | Block RAM tile | 352 | **352** | 0 |
  | URAM | 0 | **0** | 0 |
  | DSP | 4 | 4 | 0 |

  ⚠️ **跨网表差值、无拆刀臂 ⇒ 不归因**（#63/#64 族）。⚠️ STG 轮的 **synth 检查点**曾报 **+432 LUT / +67 FF**
  （pre-place）—— 与后布线 **不同流程**，**不可互相推算**（此处只并列登记）。
- **DP 域最差路径**：`u_tcp_tx/u_fifo_b/rptr_reg[0]/C → u_tcb/rcv_nxt_r_reg[0][22]/CE`（lvl=15）= **全局最差**；
  同族次格 `…[0][28]` 同为 `0.044`。**DP 组内**：setup 0/144,493 · hold 0/144,493 · pulse-width 0/51,277。
  ⛔ 与 0x20 的 DP 最差（`u_tcp_tx/u_fifo_a/rptr_reg[3]/C → …rcv_nxt_r_reg[5][9]/CE`，`+0.154`）**不是同一对象**
  （同族不同成员 + 绝对值不同流程比不得大小）⇒ 只并列登记（#66）。
- **M1 面（定向查询 `q_0x21.tcl` / `query_out/`，`QUERY_EXIT=0`）**：M1 cell **2319** 个（0x20 轮为 1905 ⇒ +414，只登记不比）；
  **DP 组内最紧 `+0.391`** ⇒ 隔离 = 差值 `0.347 ns` / 比值 `8.9×`（⛔ 0x20 的 `+0.515 / 3.34×` **不可比**：
  两侧都动了 —— DP WNS `0.154 → 0.044` 与新锥换最差位同时发生，**无拆刀臂 ⇒ 不归因**）；
  `m1_app_core to_worst = +0.377`；`m1_ring to +0.268`；`m1_c2h from +0.556` / `to +0.426`；`m1_h2c to +0.171`（异步复位族）；
  **`u_mir` 在 global top5 / DP top10 / DP top50 = 全 0 命中**。
- ⚠️ **命名陷阱（本轮实测，登记）**：DP top10 里 **8 条**宿 = **`u_app/stg_reg[*]`**（slack `0.071`）——
  那是 **`app_pattern` 自己的 staging 寄存器**，与本刀的 STG（`u_mir/stg_data_reg` / `stg_cnt_reg`）**同名不同物**
  （全局 #90 族）⇒ **不许当成本刀新锥**。判据 = 逐条查宿主层次（`u_mir` 命中 0，`u_app/stg_reg` 命中 32 行含源/宿重复）。
- **STG 新锥定向读数（后布线，本刀主角）**：`stg_cnt` from **+0.665** / to **+1.537** · `stg_data` from +2.866 / to +0.888 ·
  `acc_cnt_r` from **+0.391**（= M1 面最紧）/ `acc_r` from +3.683 / to +1.303 ·
  **`stg_ret` / `beat_pl` / `nbmask` = NOCELL**（组合锥 ⇒ 无 cell 可查，只能由 from/to 与宿面覆盖）。
  ⚠️ 与 STG 实施轮 synth 面（三条族 "+3.498 / +5.194 / +4.662"，M1 面最紧 +2.147）**不同流程 ⇒ 不比大小**；
  方向一致的只有一条：**新锥都没进 DP 最差面**（synth: 前 20 = 0 个 `u_mir`；后布线: top10/top50 = 0）。
- **其它族挤动复核（只登记，不做归因）**：`ps_stage to +0.083`（persist 族内最紧）· `pend_wnd to +0.721` ·
  `ack_adv to +0.999` · `dup_l_reg to +1.019` · `ring_hi from +1.644` · `whi_r from +2.579` · `ctrl_pld from +1.372`。
- **`BUILD_ID_V` 回读**：源码面 `0x21` ✅；**位流面 = 未做**（见 §7-1）。

---

## §4 D 常驻矩阵 17/17（不是 filter 子集）

- **入口**：`bash sim/p4sim/run_matrix_p4dfix.sh`（自定位 `[P4GUARD OK] root=… manifests=6`）；
  **`MATRIX_RC = 0`**；日志 = `sim/p4sim/matrix_p4dfix.log`（副本 `matrix_p4dfix.log` / `matrix_stdout{,_utf8}.txt` / `_gbk_original`）。
- **逐门清单（17/17 全 `EXIT=0`）**：chain · burst200 · trunc50 · trunc100 · halfdrop · txdrop50 · gate4096 ·
  dupstorm · pcackoob · vlanchain · vlanburst · stallgate · unit_retx · unit_fifo · unit_vlan · unit_uart · p5_wrapper。
  `gates run : 17 / 17` / `gates failed: 0` / `VERDICT: FROZEN -- all 257 hashed files byte-identical across the run`。
- **跑动期间零漂移**：`DIGEST_COMPILE`(212) / `DIGEST_ALL`(257) BEFORE = AFTER 逐位相同；`GIT_HEAD` BEFORE = AFTER = `70d5ba4`。
- **静默门复核**：`unit_retx` = **`ALL 7 GROUPS PASS`**；`unit_fifo` = **`PASS_ALL  frame_fifo unit: writes A=568139 B=595715 C=616302 pops A=567224 B=591216 C=611802 cycles=750700`**（C=616302 与既存基线**逐字相同**）；`p5_wrapper` 尾 = `P5 WRAPPER OK (wrapper APP_MODE app-TX 通路端到端逐字节正确)`。
- ⭐ **指纹绑定核对（派单点名）**：指纹件 `sim/p4sim/P4_MATRIX_FINGERPRINT_20261011_183626_{before,after}.txt`
  （已归档本目录）里 `board/wrapper_p4.v` 行 = **`bd8f608c…`（304,144 B）** ⇒ **= 工作树现读，逐字相同**
  ⇒ **矩阵 FROZEN 绑定【工作树】成立**。⚠️ 但 `git show HEAD:board/wrapper_p4.v`（按工作树 CRLF 口径复算）=
  **`8d9374c5…` ≠ 工作树** ⇒ **绑定的是工作树修订，不是 HEAD**（B 项未提交）。
  指纹件自己那行也写着 `M M board/wrapper_p4.v`（tracked 但相对 HEAD 已改）。
  ⇒ **这不是新缺陷，是口径**（与 0x20 轮同形）；要与"提交版本"绑，必须先把本轮改动提交、或提交后重跑矩阵。
- ⛔ **覆盖声明（空证据面，照实报）**：6 个 manifest 逐个现核 —— `app_rx_mirror` / `aximm_c2h_win` / `mir_dma_ring` /
  `aximm_h2c_discard` / `axi_regs` 命中数 **全 0** ⇒ **17 门里没有一门编译本刀改的 RTL**
  （`rtl/app_rx_mirror.v`）；唯一编译 `board/wrapper_p4.v` 的门 = `p5_wrapper`，而它的 manifest 头自述
  `-d APP_MODE ONLY. No DP_156MHZ / PCIE_OBS / P7B_10G …` = **单域遗留分支** ⇒ **本刀在该门里根本没被 elaborate**。
  ⇒ **17/17 绿对本刀是空证据**；本刀的门证据在 `sim/p7b_mir/`（单元门 real `PASS_ALL` + G15–G20 + 7 突变臂）
  与 `sim/p6e_pcie/`（p6e 全链 116 条 PASS 行 / 0 FAIL），另有独立对抗审查（`p8_mir_stg_20261011/REVIEW.md`）。
- **矩阵件归档**：before/after 指纹 + `matrix_p4dfix.log` + `matrix_stdout{,_gbk_original,_utf8}.txt`（全在本目录）。

---

## §5 E 归档（本目录，全部在本轮之内落盘 —— #54）

`wrapper_p4.bit`（15,431,261 B）· `wrapper_p4_routed.dcp` · `board_rpt/`（timing/util/drc/clk-util/control-sets/
power/route-status/runme_impl_1.log + `board/` 四份 rpt + synth util）· 定向查询 `q_0x21.tcl` + `run_q.bat` +
`query_out/`（`dp_top10.rpt` / `dp_top50.rpt` / `global_top5.rpt` / `QUERY_EXIT.txt`）+ `q_stdout.txt` ·
矩阵件（before/after 指纹 + `matrix_p4dfix.log` + `matrix_stdout*`）· 读侧件（dry-run/rehearse/apply/assert/face/
negctl×4/negctl_post×4/neg_rehearse×2 + `TARGET_SHA_BEFORE_BID21.txt` / `POSTAPPLY_SHA_BID21.txt`）·
`build_console.txt` · `PROGRESS.txt` · **`SHA256SUMS.txt`**（49 件 / 50 行）。
另：构建脚本自带归档 `_proj_10g/notes/p7b_build_archive/20261011_175317/`（**19 件 = 上一版 0x20 的 impl 产物**；
其 `wrapper_p4.bit` sha256 = `998ff90f…` 已核 = 0x20 位流 ⇒ 归档的是**上一版**，符合脚本设计）。

---

## §6 口径声明（哪些变了 / 哪些逐字不变）

**变了**：① 14 个读侧文件（BID 0x20 → 0x21 + 注释代际）；② `board/wrapper_p4.v`（B 项：1 值 + 2 段注释）；
③ `apply_readside_bid1c.py`（+阶段⑥/+2 ALLOW/+文档，**+140/−2 行**）；④ 构建产物 `board/p7b_ku5p_{stdout.txt,timing,util,drc,clkinteract}.rpt`
与 `sim/p4sim/matrix_p4dfix.log`（跑动即重写，上一轮同形）；⑤ 新文件全在 `_proj_10g/notes/p8_build_0x21/` 与
`_proj_10g/notes/p7b_build_archive/20261011_175317/`。

**逐字不变**：几何（71 字 / `0x14C` / 各读侧表 71 项 / 假板子 11 条地址）· M1 块与 `:1319-1322` tie-off ·
`rtl/`（本轮**一个字节未写**）· 两个 TB 的 UNIMPL/几何期望 · 所有"历史/逐字保留"注释行 ·
`unit_fifo` 的 C=616302 读数 · 矩阵 `DIGEST_COMPILE`/`DIGEST_ALL`。

**不许当已答**：本报告**不下时序裁定**（`+0.044 / 0/0/0` 是读数，不是"解决"；跨网表差值不归因）；
`WNS +0.044` = 周期 6.400 的 **0.69%** ⇒ **余量极薄，后续任何改动都先落这条族**。

---

## §7 未定项（没跑 / 没覆盖 / 只能写"未观测到"）

1. **位流面身份回读未做**：板上 `0x04` 门（真正的回读）**需烧录**，本轮不烧 ⇒ 只能写"源码面 = `0x21`；
   板面 = 未测"。
2. **板级完全未验**：`0x21` 位流**没有任何板级读数**。下轮配方（审查件给出，登记备查）：正臂 = 0x21 +
   `paylen 1470`（期望 `ΔW70 == 0`）；负对照 = 0x20 已测（750,882 B，同时是"源确实稠密"的见证）；
   **字节账须换新残余口径 `acc_cnt + stg_cnt`（0..24 B）**（旧口径 ≤16 B 只对暂存那一半成立）。
3. **矩阵不覆盖本刀 RTL**（§4 覆盖声明）⇒ 17/17 绿**不能**当作本刀的回归证据。
4. **矩阵指纹 ≠ HEAD**（本轮改动未提交）⇒ FROZEN 绑工作树；提交后若要"绑定提交版本"需重核/重跑（§4）。
5. **时序余量**：`WNS +0.044`（0.69%）且 **DP 域 = 全局最差** ⇒ 加逻辑先看 `u_tcp_tx/u_fifo_b/rptr_reg[0] →
   u_tcb/rcv_nxt_r_reg[0][*]` 与 `u_tcp_tx/u_ackq/wptr_reg[1] → u_app/stg_reg[*]`（0.071）两条族。
6. **资源/时序跨网表差（+543 LUT / +72 FF / DP WNS 0.154 → 0.044）无拆刀臂 ⇒ 不归因**；
   synth(+432/+67) 与后布线(+543/+72) 是两个流程，不可互推。
7. **`run_tb_p6e_pcie_counters`（TB 期望已 = `0x21`）本轮未跑**：它不在 17 门内 ⇒ 只能写"常量已同步、未运行验证"。
8. **审查件 `p8_mir_stg_20261011/REVIEW.md` 的两条待办（⑥-1 `cap_en` 解冻沿 1 拍丢未登记 / ⑥-3 残余口径
   ≤23/24 B）与 DESIGN §4.1 回写** —— TL 指令 = **等 0x21 构建做完再动**（构建期改 RTL 会毁证据绑定）
   ⇒ **本轮严格未碰 `rtl/`**；这些仍是**未收口**项。
9. **M1 cell 计数 +414 的构成**（只登记不比）、**`u_app/stg_reg` 同名陷阱在别处的复核**、**位流 0x21 与
   0x20 的 A/B 拆刀**，均属下一轮范围。
