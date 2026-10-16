# 0x29 拆刀轮（单比特拆刀：`PERSIST_EN` vs P-1）—— 构建 + 板级 LEGACY 两判

> **执行 agent 原件**（轮目录 `_proj_10g/notes/p9_dissect_0x29_20261017/`）。
> **口径**：本报告**不下 PASS/FAIL 裁定**；给的是读数与**读数层判定**（"有/无幽灵"，用词照 bisect 轮先例）。
> **【已证】/【推断】/【未判定】/【未定位】/【未测】** 五档纪律全程遵守。
> HEAD = `e2850f1b`（本轮**未做任何 git 写**；改动留工作树）

## 0. 一行结论

**0x29（= 0x28 内容 + `.PERSIST_EN(1'b1)→(1'b0)` + BID 0x28→0x29）在 LEGACY 构型下两跑两中幽灵签名**（LEG1: 4 STALL+3 相位错 / LEG2: 4 STALL+2 相位错）
⇒ **读数层判定：0x29 幽灵 = 有** ⇒ **对消灭者问题的含义：`PERSIST_EN=1` 单独就是消灭者（P-1 无关）** ——
P-1 修复**在 0x29 里在位**（0x28 内容原样保留）而幽灵仍在 ⇒ 幽灵的有/无**跟 `PERSIST_EN` 走**，不跟 P-1 走。
**L2【推断】"消灭者 = persist 刀（捆绑 PERSIST_EN + P-1 + BID）"拆开结果为：消灭者 = `PERSIST_EN` 这一位（P-1 已排除）。**

## 1. A 段：改动（恰两处）+ 构建读数

### 1.1 两行 diff（`board/wrapper_p4.v`；`git diff --numstat` = 2/2，hunk 数 = 2）

```
@@ -2185 +2185 @@
-    tcp_tx_frame #(.RING_CAP(WIN_CAP_5), .PERSIST_EN(1'b1)) u_tcp_tx (
+    tcp_tx_frame #(.RING_CAP(WIN_CAP_5), .PERSIST_EN(1'b0)) u_tcp_tx (

@@ -4377 +4377 @@
-        .BUILD_ID_V (32'h00000028),     // ...（前置闸读这一项认位流; E12 观测计数器 = 0x28）
+        .BUILD_ID_V (32'h00000029),     // ...（前置闸读这一项认位流; PERSIST_EN 拆刀（persist＝关；0x28 内容）= 0x29）
```

sha256：before `3b39c85f509c09b0ce5ffb31014034f34d976f36bd1a2954b504c6e323dd68a2`（= 0x28 轮落盘值，逐字）
→ after **`dc40acb62c9cac6f7110b68ab3241ab48ad0e3cca91cce8f50bb9fcb947b748f`**；CRLF 5025 / loneLF 0 前后一致。
（原件：`diff/DIFF_0x29_README.txt` · `diff/diff_0x29_U0.txt` · `diff/sha_after.txt`）

⚠️ **登记（非偏离，供 TL 知）**：`:2170-2184` 上下文注释块现写"persist **开**"与"回退点 = 这一处改回 `1'b0`"——
本刀把例化翻回 `1'b0` 后该注释块与活行**语义相反**；因"恰两处"约束未动它。**建议下一轮（无论回退/再拆）同批更新该注释块。**

### 1.2 构建（唯一入口 `board/run_build_p7b_ku5p.bat`；调用式 = `MSYS_NO_PATHCONV=1 cmd /c`，单斜杠）

| 项 | 读数 |
|---|---|
| BAT_RC / BUILD_EXIT | **0 / 0**（console 末 = `BITSTREAM-OK`；`P7B DONE`；`P7B_CONVERGED_AT_ROUND = 2`；`P7B_IS_LOCKED_POSTGEN = 0`）|
| **WNS / WHS** | **+0.060 / +0.010**（0x28 = +0.065 / +0.010；⛔ 宿主/检查类型可能不同 ⇒ 只并列、不归因、不比大小）|
| **三类失败端点** | **0 / 0 / 0**（design timing summary 逐字：WNS +0.060 / TNS failing **0** / total 259,495 · WHS +0.010 / **0** / 259,495 · WPWS 0.000 / TPWS failing **0** / 84,157；`Slack (VIOLATED)` = **0** 条；`All user specified timing constraints are met.` 在档）|
| **位流** | sha256 **`9c9675436b5084a483b50d846d52a2b27ca56992ba90fe1761b3d4d6cd595e7e`** · **15,431,261 B**（= 全代同尺寸；⚠️ 只有 sha/BID 能分版）|
| 时间线 | 03:48:31 归档块（#54）→ 03:50:23 synth 等待 → 04:17:06 Exiting Vivado（**28.5 min**）|
| DRC / route | DRC `Checks found: 69`（0 Error / 0 Critical）· `nets with routing errors = 0` |
| XDMA 断言组 | `RC_BASE=0` / `RC_INTF=0 (<AXI_Stream>)` / `RB_MISMATCH_N=0` / `GEN_BAD_N=0` / **`VERDICT = OK`**（与 0x28 逐字同）|
| 资源（placed，只并列）| **75,986 LUT / 74,469 FF** / 348 BRAM / 1 URAM / 4 DSP / 6 GTYE4（0x28 = 77,631 / 75,086 / 348 / 1 ⇒ **−1,645 LUT / −617 FF**）——⚠️ **单比特刀动网表符合 #64 预期；只登记，不归因** |
| **构建输入绑定** | vs 0x28 轮 `BUILD_INPUT_HASHES.txt`（287 件 build 源集）：**变化恰 1 件 = `board/wrapper_p4.v`（`3b39c85f…` → `dc40acb6…`）** ⇒ 构建消费的源 == 预期两行改动，无其它源漂移 |
| 归档 | pre-build 归档 `p7b_build_archive/20261017_034831/`（19 件 + SHA256SUMS；内含 **0x28 位流 `79c9cf43…`**，provenance 已核 = 构建清空 `impl_1/` 之前）· 轮目录 `build/`（位流 + routed dcp + `board_rpt/` 15 件 + 读数）|

读数原件 = `build/READINGS_BID29.txt` · `build/BUILD_CONSOLE_0x29.txt` · `build/BIT_SHA256_BID29.txt`。
⚠️ `SW_CRC` 提取失败（脚本 regex 未命中 `.bit` 头 'e' 记录段；**未复核**，不影响任何判据）。

### 1.3 常驻矩阵（`sim/p4gates/run_matrix_p4dfix.bat` 全矩阵）

**结果见 §5**。矩阵在本轮板级段之后**串行**跑（沿用 0x28 轮"xsim 与 Vivado 严格串行"纪律）。
**BID 同步需求核**：0x28-BID 字面值**只出现在 `sim/p6e_pcie/tb_p6e_pcie_{wrapper,counters}.v`**（两处 `32'h00000028`）；
**19 门矩阵编译集内 0 处 BID 断言**（逐 manifest 核：`chain_src.f`/`retx_src.f`/`fifo_src.f`/`vlan_src.f`/`uart_src.f`/`p5wrapper_src.f`/`f3resync_src.f`/`swcg_src.f`；`sim/p4sim`,`p5sim`,`retxsim*`,`vlansim`,`tbgate`,`p9_swc_gate` 全目录 grep `BUILD_ID|0x0000002` = 0 命中；`f3_resync` 只编 `rtl/vlan_strip.v` 族、不编 wrapper）
⇒ **矩阵无需 BID 同步**。

### 1.4 读侧（**显式覆盖**路径；census 已做，链式同步**未做**）

- census（`--face`，工具 `p7b_readside_bid1c_20261011/apply_readside_bid1c.py`）= **464 行 / 238 文件**；
  其中 **"EDITS 目标（现役/已同步）" = 17 文件**（identity-BID 家族 = **14 文件 / 24 处**，与 0x28 轮 §②-1 "BID 面 24 处 / 14 文件" 逐数一致）；原件 = `env/READSIDE_FACE_0x28.txt`。
- **本轮选择 = "显式覆盖"**（任务 A-4 明列的允许选项）。理由：① 板级臂与烧录身份门的 `EXPECT_BID` **无默认值（缺了就响亮失败）** ⇒ 精度不依赖默认值；② 19 门矩阵 0 处 BID 断言 ⇒ 无门面依赖；③ 链式同步（历史链重写 + 档表 + 负控四族）是 ~30–45 min 手工件，与本窗口矩阵/板级直接冲突。
- **登记（留给下一轮）**：链上新增阶段 ⑭ `0x29` 需要 = `EDITS_29`（BID 面 24 处，old 侧 = 当前盘上 0x28 新侧）+ `STAGES` 行 + `E14()` 注册 + `gen_edits29.py`（照 `p9_build_0x28/gen_edits28.py` 做法）。
  ⚠️ 工具是**链式**的：下一轮要落 `0x2A` 时必须先把 `0x29` 阶段落盘（`--apply` 只落最后一阶段且要求前置阶段在位）。
- ⚠️ **现役盘上默认值仍是 0x28** ⇒ 任何**用默认值**读 0x29 板子的脚本会报身份门失败 —— **这不是缺陷**，是"读侧未同步"的预期形态。

## 2. B 段：板级 LEGACY 两判（烧 0x29 → 判 → 收尾烧回 0x28）

### 2.1 方法基线（逐字同 bisect 轮）

- 臂脚本 = `board/arm_d29.sh`（母本 = `p9_s0bisect_board_20261016/_tools/arm_s0.sh`；四处明示差异见其头注）。
- **sink 同锚**：bisect 轮用 `p7b_tcp_sink` md5 **`6d9b14f24725fa326ffe5b169f77e30f`**；现役部署件 = `f62299291fcb9e02afe109c4ea1f90ab`（sinkdelta 新件：三个 opt-in 开关 + SINK_OPTS 见证、默认行为等价已证）= **不同件**
  ⇒ 按任务指引**取归档同锚件**：`/tmp/p7b_biz_prev/p7b_tcp_sink__6d9b14f2_pre_sinkdelta`（**md5 逐字 = 6d9b14f2…**，已核）→ `/tmp/d29_p7b_tcp_sink_6d9b14f2`。**待用 sink 与 bisect 轮逐位同件。**
- 构型逐字 = S-0 LEGACY：`rcvbuf 2920 conns 6 secs 60 maxbytes 200000000 --check lane8` + **`--rcvbuf-after-connect`**；`SNAP_MD5 a257af8299904789c6a6dd9ed5ca030f`（与 bisect 轮逐字同）。
- 判据（逐字同 bisect `mk_table.py`）：**相位错** = `first_mismatch==0 且 mism ≈ bytes−bytes/256`；**STALL** = `poll_tmo=3`；clean = `-1/0/OK`。
- **双面记录**（防慢盆混淆）：慢盆签名 = 低速率 + `mism=0` + **无 STALL**（内容洁净）；幽灵签名 = **STALL 和/或相位错**。两臂读数**均无慢盆形态**。

### 2.2 烧录与身份门（`burn/burn_gen29.sh`；JTAG 易失，**QSPI 零写**）

烧 0x29（T0=04:17:50；burn stdout 新鲜度 132 s；五判据 BURN_OK = HIGH+DONE+路径+新鲜度+无ABORT）；
PCIe 场景 C 恢复成功（桥窗 2M、`LnkSta 5GT/s x4`、2 BARs、4 `/dev` 在位；dmesg `identify_bars: 2 BARs: config 1, user 0`）。
身份门（`p7b_snap.sh id`，`EXPECT_BID=0x00000029 NW=75 UNIMPL_ADDR=0x15C`）：**ID_OK / ID_RC=0**
（`ID_MAGIC 0x50360001` · `ID_BID 0x00000029` · `ID_MARKER 0xdeadbeef` · `ID_UNIMPL 0xffffffff`）；
`WINDOW_SCAN_NFF = 0`；`SCRATCH 0x08 = 0`；`CARRIER = 1`。
⚠️ 首次身份门曾以非补齐写法传 `EXPECT_BID=0x29` ⇒ 打 `ID_FAIL`（身份门是**字面量/位数敏感比较**；实测 BID 值本身正确）⇒ 已用补齐写法复跑得 `ID_OK`。登记为**调用式口径坑**，非缺陷。

### 2.3 臂读数（两跑，同一次烧录内；**未重烧中间**）

| TAG | 构型 | conns | STALL | 相位错 | clean | agg Mbps | wall s | SRC_RC | capture(ctl/full dropped) |
|---|---|---|---|---|---|---|---|---|---|
| **LEG1** | LEGACY 2920×6×60×2e8 | 4 | **4** | **3** | 0 | **0.015** | 60.746 | n/a（stdout 丢，见 §4-②）| ctl=0 full=0（arming 读数丢；两 `.err` 在档且 0 dropped）|
| **LEG2** | 同上（无重烧复跑）| 6 | **4** | **2** | 2 | **49.430** | 64.755 | 1 | ctl=0 full=0 armed=2 stopped=2 |

逐连接（sink 逐字；相位错算术核对 `bytes−bytes/256`）：
- **LEG1**：conn0 STALL(-1/0)；conn1 STALL **4380** `mism=4367`（pred 4363，Δ −4）；conn2 STALL **51100** `mism=50899`（pred 50901，Δ +2）；conn3 STALL **35040** `mism=34903`（pred 34904，Δ +1）⇒ **3 条相位错**、`mismatch_bytes = 90,169`。
- **LEG2**：conn0 STALL **29200** `mism=29090`（pred 29086，Δ −4）；conn1 STALL **59860** `mism=59619`（pred 59627，Δ +8）；conn2 **OK 200,001,020 B 洁净**（746.2 Mbps）；conn3 STALL(-1/0)；conn4 **OK 200,001,020 B 洁净**（814.0 Mbps）；conn5 STALL(-1/0) ⇒ **2 条相位错**、`mismatch_bytes = 88,709`。
- **pcap ctl**（轻量普查，FIN/RST 全窗）：LEG1 = **24 FIN / 0 RST**；LEG2 = **24 FIN / 2 RST**；**方向全是 对端(192.168.100.100)→板**（= sink 中止/关闭的清理；板侧在 ctl 窗内 **0 FIN / 0 RST**）；FIN 呈重传形态（对端反复重发 FIN）。
- **NIC 硬件计数**：LEG1 期间 `port_rx_bad`/`rx_eth_crc_err` **14820 → 14823（+3）**；LEG2 期间 **+0**。⚠️ 与 bisect 轮 §⑦-3 的"单跑 +14,820 错帧"**同族但量级完全不同；不归因**，只登记。
- 全窗守卫：两跑 tcpdump `0 packets dropped`（ctl/full）；sink 结束无残留进程。

### 2.4 对照锚（并列；出处 = `p9_s0bisect_board_20261016/runs/TABLE.txt`）

| 代 | LEGACY 幽灵 | 读数（逐字）|
|---|---|---|
| 0x1A | **有** | 5 连接 / **4 STALL + 3 相位错** / 0 clean / **25.532 Mbps** / wall 62.697 |
| 0x1C | **有** | 跑1：4 / **4 STALL + 3 相位错** / **0.012 Mbps**；跑2：6 / **2 STALL + 3 相位错** / 166.0 Mbps |
| 0x1D | 无（n=2 有效）| 6/6 洁净 / 716.4 · 768.9 Mbps（另 1 跑涓流 hang 作废）|
| 0x1F | 无 | 6/6 洁净 / 782.4 Mbps |
| 0x24 | 无 | 6/6 洁净 / 738.6 Mbps |
| **0x29（本刀）** | **有（n=2）** | **LEG1 4 STALL+3 相位错 / 0.015 Mbps · LEG2 4 STALL+2 相位错 / 49.430 Mbps** |

⇒ 与 0x1C 跑1（4+3 / 0.012）**形态逐项同款**；落在 0x1A/0x1C 的读数带内。

## 3. 读数层判定 + 对消灭者问题的含义

1. **0x29 幽灵 = 有**（读数层，n=2 同烧录两跑，签名 = STALL + 相位错、与慢盆可辨）。
2. ⇒ **消灭者 = `PERSIST_EN=1` 单独**（**P-1 无关**）：0x29 保留 0x28 全部内容（**含 P-1 修复 `6b7d00e`**）只翻这一位 ⇒ 幽灵回来；
   而 `PERSIST_EN=1` 的 0x1D/0x1F/0x24/0x28 **均无幽灵**。**bisect L2 的"捆绑两项"【推断】由此拆开（单变量，n=2）。**
3. **方法论边角（如实登记，不扩权）**：
   - 0x28→0x29 差异含**第三项** = BID 常量；本工程一贯把 BID 当无功能义（历轮同做，含 bisect 链本身）⇒ 归因的**充分性**建立在"BID 无功能义"这个**假设**上（与全仓先例一致；本轮**未做**"只翻 BID"的对照臂）。
   - 本刀只证"**幽灵的有/无 ⇒ 跟 PERSIST_EN 走**"；**未证** persist 内部的哪一部分在抑制它（探询段 / 退避阶梯 / `ps_rd` 清位…）—— persist 内部机制与相位错机制（L3）均保持【推断】。
   - 幽灵的**触发前提**仍是 `--rcvbuf-after-connect`（LEGACY）；本轮**未跑** before_connect 对照臂（bisect 已证该口径对幽灵无判别力）⇒ 该前提维持 bisect 结论。

## 4. 偏离 / 未决（逐条）

1. **sink 版本偏离现役**：按任务指引取归档**同锚件** `6d9b14f2`（= bisect 轮值），**未用**现役 `f6229929`（sinkdelta）。同一 sink 对 0x1A/0x1C（有）与 0x1D/0x1F/0x24（无）都做过判定 ⇒ 判别力在同锚件内自洽。
2. **LEG1 stdout 丢失**：首跑 stdout 重定向文件被臂脚本 `rm -f /tmp/d29_LEG1_*` 通配删除（**命名冲突陷阱**：stdout 自身匹配清理通配；已修 = LEG2 用聚合外名字 `/tmp/d29_STDOUT_LEG2.txt`）。
   影响面：LEG1 的 `D29_BEGIN/END`、身份闸、TCPDUMP_ARMED/STOPPED、`### SINK_RC` 行丢失；**判据载体全在**（`runs/remote/d29_LEG1_*` 11 件 + sink + 两 `.err` 0 dropped + `nicpre/post` + `nstat_*` + `snap.log` 150 KB）。
3. **矩阵相位**：板级段之后串行跑 ⇒ 结果 = §5。
4. **读侧链式同步未做**（§1.4）—— 显式覆盖路径，census 已归档；下一轮需补 `EDITS_29` 阶段。
5. **NIC CRC 错帧 +3**（LEG1 期间）**未定位**（LEG2 无；不归因板或线）。
6. **未测**：before_connect 对照臂（本轮未跑）· `--seconds 300` 档 · 幽灵的 RTL 级直接见证（无）· 0x29 的其它构型（P-3 / 涓流 / 慢盆免疫面）· `SW_CRC` 复核 · 定向 STA（单比特刀不归因，未做）。
7. **慢盆**：两跑**均无**慢盆形态；本轮为"烧后立刻跑"（天然清盆起点）。
8. **板子现态** = **0x28**（BID `0x28`）+ `0x08 = 0` + `carrier = 1`（收尾已烧回；见 `FINAL_STATE.txt`）；QSPI 零写入；本机/对端均无残留进程。

## 5. 常驻矩阵（终读数）

**`MATRIX_RC = 0` · `gates run: 19 / 19` · `gates failed: 0` · `VERDICT: FROZEN`**（04:26:52 → 04:53:37，26.7 min）。

- 冻结判据：272 件 before/after **逐位相同**；`DIGEST_ALL = 94e3042f1e87d9137172c7568bb1b635d9cb67e912d655b2aeef7aed4a665768` 两边逐字；`DIGEST_COMPILE = 942ff7ef…` / `FILES=221` / `HEAD = e2850f1b`。
- `P9-SWC-GATE: PASS`（swc 门在矩阵内）。
- ⚠️ 指纹 before/after 文件有 **1 字节差** —— 定位 = `sim/f3_resync/mut/mut_m1.v` 的 **mtime 元数据字段**（content-v1 口径：mtime 不入指纹；该 mutant 由门自己重生成，**内容 SHA 未变**）⇒ 冻结成立。
- **指纹漂移 vs 0x28 轮基线**（`P4_MATRIX_FINGERPRINT_20261015_234333_after.txt`；原件 `gates/FP_DRIFT_vs_0x28.txt`）：**CONTENT-CHANGED 恰 1 = `board/wrapper_p4.v`（`3b39c85f…` → `dc40acb6…`）· ADDED 0 · GONE 0（272 → 272）** ⇒ 矩阵的 hash 宇宙**看得见本刀、且只见本刀**。
- 门失败 0 ⇒ 本刀（含 `PERSIST_EN` 翻面）**未触怒任何既存门**（19 门编译集 0 处 BID 断言，与 §1.3 的事先核算一致）。
- 原件：`gates/matrix_stdout_run1.txt` · `gates/matrix_p4dfix.log` · `gates/MATRIX_VERDICT.txt` · 两份指纹文件（已拷入轮目录）。
