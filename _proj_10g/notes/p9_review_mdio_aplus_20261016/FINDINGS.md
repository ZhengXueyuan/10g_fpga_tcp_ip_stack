# p9_mdio_aplus_board_20261016 —— 对抗审查（红队，只读）FINDINGS

> **agent 原件由平台拒写 .md ⇒ 全文回传、TL 代落盘**（本件正文 = agent 原文；文末 = TL 裁定折叠/补档块）。
> 审查对象 = 提交 `e5fc9f7`（mdio A+ 变体位流构建 + 板测轮）。姿态 = 找错 + 从原始件独立复算；**不下 PASS/FAIL 裁定**。
> 全程未跑 xsim/xelab/vivado、未碰板/对端机、未改任何其它文件（含 `_proj_mdio` 活树，只读）。
> 结论总貌：**核心读数全部独立复算一致**（§② 清单）；**未证伪任何主结论**；发现 1 条中低（证据链幽灵引用 + §10 复算命令无牙，但结论本身经独立路径复核成立）、5 条低、4 条微。

## ① 已证伪

**无。** 本批逐条攻击（双构建 sha、R9、位级惰性、E8 修正及根因、板级三臂/三烧、位映射、纪律面、报告-原件一致性）无一被证伪；核心数字逐条复算一致（§②）。

---

## §A FINDINGS（按 severity 降序；file:line + 复算值/命令）

### A-1（中低）E8 根因链有"幽灵引用"：transcripts 不存在 + §10 复算命令结构性无牙

- **原件**：`APPLY_LOG.txt:52-53` 写 "*it appears in the dump … transcripts in `build_divbad/query_*.stdout.txt`*"；`REPORT.txt:179`（§10 首条复算命令）写 `grep -n "MORE OPTIONS" build_divbad/query_all_props.tcl`。
- **复算**：
  - `find <轮目录> -iname "*query*"` 只有两个 **.tcl 脚本**（`query_all_props.tcl` / `query_generic_prop.tcl`），**零个 transcript**；`find D:/repo/XCKU5PMini/_proj_mdio -iname "*query*"` 也 0 命中 ⇒ 声称的 `query_*.stdout.txt` **全盘不存在**。
  - 逐字复跑 §10 命令：`grep -n "MORE OPTIONS" build_divbad/query_all_props.tcl` ⇒ **rc=1 / 0 命中**（该 tcl 是通用 `report_property -all` dump 脚本，本身不含该字符串）。
- **口径**：这是**可复算性/审计缺口**（"根因（查询所得）"的唯一原始见证缺档），**不是结论错误** —— 根因结论经我独立复核成立，见 §②-10 的三条独立证据（安装脚本 grep / gen_run.xml / runme.log+vds）。
- **修法建议（供 TL）**：把真实 dump（或 `synth_1/runme.log:28` 的逐字行）补档为 transcript；§10 命令改指 dump 或 runme.log。

### A-2（低）REPORT.txt §5.3 标题的时序与本轮证据自相矛盾

- **原件**：`REPORT.txt:91` 写"原始位级诊断（**run2 后补跑**；位映射由测量钉死）"。
- **复算（三份原始 stdout 会话时间）**：run1 = `PROBE_APLUS_STDOUT_run1_loopbug.txt:6` **02:27:09–17**；diag = `PROBE_APLUS_DIAG_STDOUT.txt:6` **02:29:14–22**；run2 = `PROBE_APLUS_STDOUT.txt:6` **02:30:23–31** ⇒ 时序 = run1 → **diag → run2**，diag 实际在 run2 **之前**。同件 `REPORT.txt:117`（"run2 已修（并按 diag 钉死后打印 raw 原文）"）**是对的**，与 §5.3 标题互斥。影响：无（内容逐字相符），仅次序标签错。

### A-3（低）"Vivado 报 ERROR 时 bat 退出码仍 0" 无归档见证

- **原件**：`APPLY_LOG.txt:60-64`（commit message 复述）。
- **复算**：轮目录内 `grep -rn "errorlevel|exit code|RC="` 仅命中 APPLY_LOG 这处自述本身 ⇒ **无任何 RC 捕获件**。只读约束下不可复跑 ⇒ 记 **未证（无法判定）**。
- 影响：零 —— 该断言不承重；同轮明写的"看 stdout"规则我按其复核三份 stdout：prod/run2 = 0×`^ERROR` + 2×`=== BUILD DONE ===`；run1 = 1×ERROR + 0×DONE ⇒ 规则在件上有牙。

### A-4（低）BIT_MTIME 列两套口径未注明

- **原件**：`BUILD_READINGS.txt:10/:39` 与 REPORT §4 表：BIT_MTIME = 02:14:34（prod）/ 02:20:30（variant）。
- **复算**：这两个值 = **impl_1 源件**建完时刻（两 sha 与归档副件逐位相同）；而**归档副件 mtime** = 拷贝时刻 02:14:58 / 02:21:37（与 `burn/BURN_*.txt:3` 的 "SRC mtime" 一致）。两套数都在盘上、可复算；表头未注"源件 vs 副件"口径 ⇒ 拿 mtime 做新鲜度判据的下游会撞车。

### A-5（低）文件计数三种口径并存且"入库"口径错

- **实测**：盘上 **73 件**（`find -type f | wc -l`）= **61 git-tracked** + 12 ignored-on-disk（.bit×4/.ltx×4/wrapper_p4_0x28.bit/dfx_runtime×2）。
- **报告/TL 块写"72 件"**（`REPORT.md:84` + commit message；疑 = 不含 TL 落盘 REPORT.md 的旧计数，72 = 73−1）；**commit message 又写"72 件入库"** —— 与 git 实况（61）不符。影响：无，仅口径错位。

### A-6（低-中）run2 P2/P3 的"哪一个边沿被丢"在原始件里不可钉死（报告已部分登记）

- **复算**：P2 的 58 ms 判 stale **正确**（`BUSY_SEEN=0` 且 58 ms < 83.886 ms ⇒ 不可能是本帧 done；`PROBE_APLUS_STDOUT.txt:180/:188`）。P3"2nd rise 落在 busy 窗内"是**推断**：由 P3 `wait_idle`（i=0, busy=0, raw=1d001c，~031180–195）与 P2 的 start=1 commit（c2=031118，用时 21 ms）的位置关系反推——若 P2 的 rise 已成帧，wait_idle 应读到 busy=1。最自然读法 = P2 的 rise 未成帧 / P3 的 c2 rise 成帧 / c4 rise 被丢；但 commit→fabric 生效延迟抖动（本轮自测 14–58 ms）使精确归因不可重建。**报告已在 §8.6 登记**（"丢瞬间 busy 必为 1 无逐拍见证"）。
- **独立补强件（轮内已有、REPORT 未点名）**：diag 的 **D 段在同一 readout 里同时得到 busy=1 与 b21=1**（`PROBE_APLUS_DIAG_STDOUT.txt:169` @962505），是"忙窗丢 start"最干净的见证；D 段另有第二个 ~84 ms 帧长再现（:180 @962560 已 done，帧 [~962470, ~962554]）。
- **附登记（下轮脚本建议）**：diag 结束态遗留 fabric `start=1`（E 段 e2=start=1 后无 0 写）⇒ run2 进入时 start=1 / done_sticky=1；run2-P2 的 c1 实为**下降沿**。脚本收尾建议显式归零。

### A-7（微）"run2-P2 里 ≥58 ms"的延迟下界偏大

`REPORT.txt:116`。严格下界应从 c2 commit 返回起算：read@c1+58 时 c2 已完成 37 ms 而仍未生效 ⇒ **≥37 ms**（"≥58"是相对 c1 的口径）。量级结论（数十 ms 抖动）不破。

### A-8（微）BOARD_READINGS 的 run1-P2 引用行未就地标注标签错序

`BOARD_READINGS.txt:72-73` 照抄 run1 原始行 `… ssl=1 pbad=0`（run1 的 sdec 错序：第 6 元素 = >>20；该行真实 bit20=1/bit21=0 = pbad=1/ssl=0）。错序警告在同文件 `:85` 与 `REPORT.txt:117`，但引用点本身无注 ⇒ 单读 :72-73 会误读为"run1 也丢了 start"。建议补注。

### A-9（微）"一行最小修正"与 diff 行数的口径

`build_mdio_divbad.tcl.shipped → .fixed` 的 diff 实为 **24c24,29 = 6 增 1 删**（1 行功能 + 5 行解释注释）。"一行最小修正"（D-1）指功能行，可读；但若按"diff 行数"核会差 5 行。另：D-2 只覆 E8-vs-`build_mdio.tcl` 的 3 处，未覆 shipped-vs-fixed 这对 diff。

### A-10（微，正面口径）帧长读数的更优形式

`REPORT.txt:113` 引 `busy_to_done = 72/76/72 ms`。**更强的口径 = `tdone − t1`（commit 完成→done 观测）= 84/86/82 ms**（P2B 原始行直接相减），更贴构造值 83.886 ms。报告口径自洽（busy 首见 ≈ 帧首+12 ms），不作错论，仅建议引用升级。

---

## ② 复算一致清单（全部我独立跑出）

**构建面**
1. 双 sha256 = `0549c1af…5b27ba`（prod）/ `1d7bfdb7…f145452`（variant），均 15,431,263 B ⇒ **R9 ✓**；impl_1 源件 sha 与归档副件逐位相同。
2. LTX 两构建同一：`46f53c81b305fdf1f4260fd18f6c4c7c011c2f6d3ef2cc967c1972a3bb4f75fc` / 14,756 B，**逐字节相同**。
3. timing：prod `+7.328 / +0.029 / 0-0-0`；variant `+7.391 / +0.029 / 0-0-0`；两件 `Slack (VIOLATED)` = 0；尾句 "All user specified timing constraints are met." ✓。
4. **位级惰性（加强版）**：`cmp -l prod B3归档` = 6 字节，偏移 **113/118/119/122/124/125**（= `.bit` ASCII 头日期时间数字 `2026/10/15 13:15:19`→`2026/10/16 02:14:31`）逐字命中；`SW_CRC=907d005a` 同；头 200 B 后体 md5 = `96dee90a8368f423c5fac789d2831d0a` 同。⭐ 另加更强一条：prod vs B3 的 `timing_summary.rpt`/`drc_routed.rpt` **逐字节全同（仅 line 4 Date 行差）**，utilization/route/bus 报告亦然 ⇒ "同输入确定性"再证实。
5. variant vs prod：`cmp -l = 14546` ✓；variant 头 `SW_CRC=1c167609` ✓；两构建 `utilization_placed.rpt` 逐字节同（仅 Date）。
6. 文件 sha：`mdio_vio_top.v.b3 = 79c360f8…` / `build_mdio.tcl.b3 = b7ff3c45…`（live `build_mdio.tcl` 同=未被动）/ live `rtl/mdio_vio_top.v = 4416710a…`（= stage2_apply + SHA256SUMS）/ `.shipped = bcb497df…` / `.fixed = 1d5a5c9a…`（= live `build_mdio_divbad.tcl`）。E7 diff vs B3 = **恰 2 处**（:31 模块头 / `:128 .DIV(25)` → `:130 .DIV(DIV)`），锚点 :32/:130 ✓。
7. E8 报错逐字（`BUILD_STDOUT_run1_FAILED.txt` 末三行）= 失败行回显 + `ERROR: [Common 17-54] … 'STEPS.SYNTH_DESIGN.ARGS.GENERIC'.`；run1 构建未启动；`BUILD_STDOUT.txt`（02:15）与 run1_FAILED **逐字节相同**（md5 `fe98d9ed…`）。
8. shipped→fixed = 仅 line 24 一处功能行（A-9）。
9. declared 构建规则有牙：prod/run2 = 0×ERROR + 2×DONE；run1 = 1×ERROR + 0×DONE。
10. **E8 根因三方独立复核（结论成立）**：① Vivado 2025.2 安装脚本 `rg "ARGS\.MORE OPTIONS"` 命中 3 文件 / `rg "ARGS\.GENERIC"` **0 命中**；② `pj_mdio_divbad/…/synth_1/gen_run.xml:56` = `<Option Id="MoreOptsStr">[-generic DIV=65537]`，prod 的 gen_run.xml **无 MoreOptsStr**；③ `synth_1/runme.log:16` 命令行 + **:28/:36 `Parameter DIV bound to: 65537 - type: integer`**（vds:37/:45 同）；prod runme.log 无 `-generic`。 ⇒ "generic 真的生效"成立。
11. 构建会话串行：prod 02:10:19–…、run1 02:15:07–13、run2 02:16:19–02:20:46 ✓。

**RTL 语义面（活树只读）**
12. `mdio_vio_top.v:151` 打包 `{stat_start_lost, param_bad, mdio_i, eth_rstn, busy, done_sticky, rd_data}` ⇒ **[20]=param_bad / [21]=stat_start_lost / [19:16]=mdio/rstn/busy/done**，与报告逐字一致；probe_in0 = 22 位（tcl + 板侧 `STATUS_WIDTH=22`）。
13. `mdio_master.v:70-75` clamp/`PARAM_BAD` + `:84` tick ⇒ DIV=65537 → 65536 + param_bad=1；帧 = 83.886 ms；生产 32 µs；MDC = 762.939 Hz。`stat_start_lost` 语义 = `:159-163`，与 P3/DIAG 行为逐条对应。

**板级面（原始 stdout 逐字）**
14. prod 臂：71 条 `^TX`（64 J-A + 7 J-B），**71/71 done=1、71/71 ssl=0 pbad=0**；`ARM_J_A_ANSWERED 0,1`、0/1=001CC915、2–31 全 FFFF、NO_RESPONSE 空；J-B 序列与 tcl `jb_seq`(:195) 逐字核对 ✓；`PROD_PBAD_READ … ssl=0 pbad=0` ✓。J-B 即新鲜性主臂，全中 ⇒ 无 stale 读。
15. variant 臂：P1 `pbad=1 raw=1d001c`；P3 原始序列 **`1d001c → 3d001c → 1e0000 → 1d001c`** 逐字（逐位反解全自洽）；`ATTEMPTS 1`；commit 跨 65 ms（19/20/26）✓。
16. DIAG 8 行逐字一致；时间戳自洽（C 段 commit 23 ms / busy 962269 / done 962337 ⇒ 105 ms ≈ 23+83.9 ✓；D 段 ~84 ms 帧长再现；E 段接受清位 ✓）。B 段写错探针的登记属实（`u_vio_n_2 width=1` 掩码后=0，b18 未激励）。
17. P2B 逐字：`34/32/31` · `72/76/72` · `106/108/103` · 准备循环 `89/85/88`；**`tdone−t1` = 84/86/82 ms**（A-10）。
18. 三烧五判据（脚本有牙）：`burn_bit.sh:31-34` sha 门 refuse；:59-63 HIGH/DONE/path/freshness/noABORT；三份 BURN 日志全 `BURN_OK`（age=132s）；stdout 副本指各自 bit ✓。
19. 收尾：0x28 sha 三方一致；`FIRST_RESCAN_LNKSTA_LINE … Width x4` ⇒ 设备级一次成功（E-0 触发条件已按 LnkSta 行取值）；Region 0 1M / Region 1 64K；四 /dev 节点；`identify_bars: 2 BARs`；身份门 5 值 + ID_RC=0（NW=75/EXPECT_BID=0x28）；**75 字窗扫 NFF=0**；0x15C 未实现=0xffffffff（与 0x28 几何权威 `p9_build_0x28/APPLY_BID28_OUTPUT.txt:1` "NW=75 / 未实现地址=0x15C" 逐字一致）；C1–C4 全 PRESENT ✓。
20. FINAL/PRE：BID 0x28 / 0x08=0 / CARRIER=1 / unmanaged / adaptive-rx off / rx-usecs 0 / 10000Mb/s / NO_P7B_PROCS / NO_TCPDUMP / NO_K0 / `p7b_snap.sh md5 a257af82…`（与 0x28 轮 B4FINAL 件逐字同 ⇒"自 B4 起未动"可溯）；PRE 与 B4 收尾态逐字相符 ✓。
21. **位映射反混淆（攻击面 #4）三方闭合**：RTL 打包 + sim 变异件（zero 有牙 / swap 在变体上会读 `ssl_t0=1`）+ 板级跨构建对照（prod b20=0 vs variant b20=1，"钳死/接错的位不可能随构建翻转"）⇒ "bit20=1 恒值"≠"接线/映射错"；替代信号候选被排除（bit20 全状态恒 1 只有静态 `param_bad` 满足）。
22. 纪律面：PW grep = 0（仅 env 前缀形，read-once + unset）；无 `write_cfgmem|program_cfgmem|bootgen`（QSPI 零写间接证据 = 全轮只走 `program_hw_devices`）；无 xsim/xelab/xvlog；board 四 .bat = ASCII+CRLF（`cat -A` 全 `^M$`）；`tcpreg_program_stdout.txt` = 烧录固有 tracking 件（git 历史 B1–B4 同款；本轮 diff 12 行恰为烧录输出替换）；`_proj_mdio` 与 `D:\repo\XCKU5PMini` 均非 git 仓 ✓。
23. 归档自核：`archive_impl1/SHA256SUMS.txt` 12/12 OK；轮级 **70/70 OK、0 真 FAIL**（唯一 "FAILED" 命中是文件名 `BUILD_STDOUT_run1_FAILED.txt: OK`）；未入清单的恰 3 件 = `REPORT.md`/`SHA256SUMS.txt` 自身/`archive_impl1/SHA256SUMS.txt`（惯例）。
24. 报告-原件一致性：REPORT.md 与 REPORT.txt 关键数逐条对上；D-2/D-3/D-4 与源件核对成立（`APPLY_STEPS.txt:26`"exactly two" vs 实测 3 处；:42"(S4.1)" vs 臂定义实在 `DESIGN_v2r2.md:275/285-317` §4.2；:59"0x27/P8"）✓。

---

## ③ 无法判定

1. **"Vivado ERROR ⇒ bat 退出码仍 0"** —— 无归档 RC 见证，只读约束下不可复跑（A-3）。
2. **"本机无残留 vivado/xsim"** —— 仅报告自述（`REPORT.txt:132`），事后不可判。
3. **diag 结束态 fabric `start=1`** —— 原始件可读、板上不可复核。
4. **生产臂两个新位的"物理在位"** —— 变体侧已证；生产臂恒 0 与"常量折叠/未接线"不可区分（R-b，报告已自认）；映射本身已反混淆（②-21）。
5. **P2"上一事务"的具体归属**（diag 末帧 vs run1 末帧）—— 原始件可作最自然推断、不可钉死（A-6 同族）。

---

**补充说明（交付面）**：轮目录 `_proj_10g/notes/p9_review_mdio_aplus_20261016/` 已建（空）—— 平台拒写 `.md`，请 TL 以本全文代落盘为 FINDINGS.md。全部复现命令均为本机只读命令（sha256sum/cmp/md5sum/grep/stat/find/rg/diff），值均自算。

---

## TL 裁定折叠 / 补档块（2026-10-16 03:5x，TL 亲核亲补）

- **A-1 亲证成立**（TL 独立复跑 `find … -iname "*query*"` ⇒ 只两个 `.tcl`、零 stdout）⇒ **就地补档已执行**：`p9_mdio_aplus_board_20261016/build_divbad/E8_ROOTCAUSE_EVIDENCE.txt`（活树逐字副本 = `runme.log:16/:28/:36` + `gen_run.xml:56 MoreOptsStr` + 生产 `MoreOptsStr` 命中数 = 0；安装树路径①采信审查复算）——**根因审计缺口闭合**；⚠️ 补档件生成于 `SHA256SUMS.txt` 之后 ⇒ 不在其 70 件清单内（惯例同 `REPORT.md`）。
- **折叠处置（全部采纳）**：A-1 已补档（§10 复算命令今后指向该件）· A-2..A-10 逐条入 `p9_mdio_aplus_board_20261016/REPORT.md` 的 **TL ERRATA 块 E-1..E-10**（含 A-6 的"DIAG D 段:169 是忙窗丢 start 最干净见证"补提 + 脚本清尾建议；A-10 帧长引用升级 `tdone−t1 = 84/86/82 ms`）。
- **裁定**：**主结论零证伪** —— E8 一行修正经**多条独立路径**（安装脚本 grep / `gen_run.xml MoreOptsStr` / `runme.log Parameter DIV bound to: 65537` / 行为面 P1=1 + 帧长）复核成立；"生产位级惰性"获**更强形式**（timing/drc 报告逐字节全同仅 Date 行差）；位映射三方闭合；纪律面全清。**mdio A+ 轮收口。**
