# p9_mdio_aplus_board_20261016 —— mdio A+ 变体位流构建 + 板级实测轮报告

> **本件 = agent 全文（平台侧已另落盘 `REPORT.txt`，sha256 `46dbfa31b408b765d14da968db13361b0bb90bf8c98b73bf2a8d7ee3fdc74a17`）+ 文末 TL 抽核块**（TL 代落盘 `REPORT.md`；`REPORT.txt` 保持逐字不动以维持 `SHA256SUMS.txt` 有效）。
> 状态一行话：E7/E8 已应用（E8 有一处**必要的一行修正**，见 §3）；两构建收口（**R9 ✓**）；板级三次烧录五判据全过；**J-A/J-B/J-D 全中**；**A+ 臂 P1=1 / P2=数十 ms / P3 第 1 次尝试即触发 + 净启动清位**（原始位级记录在案）；收尾已回 **0x28 + `0x08=0` + 身份门全中**。⛔ 只给读数与形态，PASS/FAIL 裁定权在判据所有者；全程 JTAG 易失，QSPI 一字未写。

## §1 环境与前置（全部现取）

- 对端在线、`hw_server`=active；板现态（烧 mdio 前）= **`0x04=0x28` / `0x08=0` / `0x15C=0xffffffff` / LnkSta x4 / CARRIER=1**（= B4 收尾态，逐字相符）。
- `p7b_snap.sh` md5 **`a257af8299904789c6a6dd9ed5ca030f`** == B4 FINAL_STATE 值（自 B4 起未动）。
- `_proj_mdio` 已核**不在任何 git 仓库内**；密码只作命令前缀、**未落盘**（轮内文本件 + tracking file grep = 0）。

## §2 Step 0 —— 归档（先做）

`_proj_mdio/pj_mdio/…/impl_1/` 的 **bit + 11 份 `*.rpt` = 12 件** → `archive_impl1/`，`SHA256SUMS.txt` 自核 **12/12 OK**。旧 bit sha256 = **`4c74c219…e7132a`**（B3 构建，15,431,263 B）。另存 `pre_edit_b3/`（改前 `mdio_vio_top.v`=`79c360f8…`、`build_mdio.tcl`=`b7ff3c45…`）。

## §3 Step 1/2 —— E7/E8

**E7**：拷后 sha = **`4416710a230ff582af999f3b4348812c007638b8497fcbec3ee52b462e9864df`** == `stage2_apply/SHA256SUMS.txt` ✓；锚点 `parameter integer DIV = 25`(:32) / `.DIV (DIV)`(:130) ✓；与 B3 件 diff = 恰 2 处。

**E8**：原样拷入 sha = `bcb497df…849b25`（== SHA256SUMS ✓），但**原样文件在本机 2025.2 下直接报错、构建无法启动**：
`ERROR: [Common 17-54] The object 'run' does not have a property 'STEPS.SYNTH_DESIGN.ARGS.GENERIC'.`
- 根因（查询所得）：`report_property -all [get_runs synth_1]` **无任何 `*GENERIC*` 属性**；承载附加 synth_design 参数的官方属性 = **`STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS`**（字符串，默认空）。
- **最小一行修正**（修正后 sha = `1d5a5c9aec6294be69d1175af0b0a6d7586a5ff04f6c51c29f3fec24e96ad676`）：
  `ARGS.GENERIC {DIV=65537}` → **`ARGS.MORE OPTIONS {-generic DIV=65537}`**
- 生效证据（逐字，`pj_mdio_divbad/…/synth_1/runme.log`）：`Command: synth_design -top mdio_vio_top -part xcku5p-ffvb676-1-e -generic DIV=65537`。两版都归档（`.shipped`/`.fixed`）。

## §4 Step 3 —— 两构建读数（串行，不并跑；R9）

| | 生产（DIV=25 默认） | 变体（修正后 run2） |
|---|---|---|
| BIT_SHA | **`0549c1af4e5eb98849c4741f58899bd2c18651f4d4cd783bd187155b4a5b27ba`** | **`1d7bfdb7c77488ecbda0fb3cb853dfb7ed214163ff63ab4cd5eb0b65df145452`** |
| BIT_BYTES / MTIME | 15,431,263 / 02:14:34 | 15,431,263 / 02:20:30 |
| LTX_SHA / BYTES | `46f53c81…` / 14,756 | `46f53c81…`（同生产）/ 14,756 |
| WNS / WHS / 失败端点 | **+7.328 / +0.029 / 0/0/0** | **+7.391 / +0.029 / 0/0/0**（`Slack (VIOLATED)` grep=0） |
| R9 | —— | **变体 sha ≠ 生产 sha ✓** |

- 生产构建 vs B3 归档件位级对照：`cmp -l` = **6 字节，全在 `.bit` ASCII 头**（日期时间数字），`SW_CRC` 同 `907d005a`、**头 200 B 后体 md5 逐字相同** ⇒ **E7-默认-DIV 在生产路径上位级惰性**。
- ⚠️ 工具面发现：**Vivado 报 ERROR 时 bat 退出码仍 0**（run1 失败与 prod 成功都退 0）⇒ 构建判据只能看 stdout，不能看退出码。run1（原样 E8）构建未启动、无位流。

## §5 Step 4 —— 板级

三次烧录全走审计过的 tcpreg launcher（**1MHz + 五判据**：HIGH/DONE/路径/新鲜度/无 ABORT）——**全过**；烧前 sha256 门逐次命中。

**① 生产位流 → J-A/J-B/J-D**（臂定义出处 = DESIGN_v2r2 **§4.2**；APPLY_STEPS 写的 "S4.1" 实指 §4.2）：
- `STATUS_WIDTH=22` ✓ · WRITE_CHECK ✓；**J-A**：`ARM_J_A_ANSWERED 0,1`、0/1 均 `001CC915`、**2–31 全静默 `FFFF`**、`NO_RESPONSE` 空（71 条 TX 记录全 `done=1`）；**J-B**：`ARM_J_B_RD 001C FFFF 001C FFFF 001C 001C FFFF`（逐字命中）；**J-D**：71 条记录全 `ssl=0 pbad=0`（两位都 0，与标签约定无关）+ `PROD_PBAD_READ … ssl=0 pbad=0` ⇒ **生产臂端 P1=0**。
- ⛔ 口径：恒 0 与"未接线"不可区分（R-b）⇒ 不声称"新两位已在生产臂验过"。

**② 变体位流 `1d7bfdb7…` → A+ P1/P2/P3**（变体 .ltx，`STATUS_WIDTH=22`）：
- **P1**：`APLUS_P1_IDLE rd=001C done=1 busy=0 rstn=1 mdio=1 ssl=0 pbad=1 raw=1d001c` ⇒ **pbad(bit20)=1**，与生产 0 构成跨构建对照 ✓
- **P3（原始记录）**：**第 1 次尝试即触发（重试记录 = 0 次重试）**：
  `APLUS_P3_PRE k=1 … raw=1d001c` → 三次 commit 跨 65 ms（19/20/26 ms）→ `APLUS_P3_AFTER k=1 … ssl=1 raw=3d001c`（=恰 +bit21）→ `APLUS_P3_TRIGGERED k=1 / ATTEMPTS 1` → 净启动：`APLUS_P3_CLEAN_READ … ssl=0 busy=1 raw=1e0000`（bit21 清 + done 清 + busy 起）→ `SSL_CLEARED ssl_bit21=0` ✓ → `P3_FINAL raw=1d001c`（帧完、`rd=001C` 新值）。
- **P2**：run2 的 done 轮询**被上一事务的 done_sticky 抢跑**（JTAG→fabric 更新延迟抖动）⇒ **该 58 ms 不作帧时长**，如实登记；run1 的 P2（elapsed 127 ms、busy_seen=1）与 diag C（busy 在 commit 后 14 ms 读为 1、done at +105 ms）作旁证。
- **原始位级诊断（位映射由测量钉死）**：逐字行 = `A_IDLE raw=1d001c b21=0 b20=1 b19=1 b18=1 b17=0 b16=1 rd=001C` · `C_AFTER_START b17=1 b16=0`（帧中）· `D_AFTER_TRIGGER b21=1 …b17=1 b16=0`（丢）· `E_CLEAN_START b21=0 …b17=1 b16=0`（被接受即清）⇒ **[20]=param_bad（全状态恒 1；帧时长证明 DIV=65536）、[21]=stat_start_lost、[19:16]=mdio/rstn/busy/done**。与 sim 臂互证：sim 的 **swap 变异件**在变体上会读 `ssl_t0=1`；**板上 idle 读 b21=0 ⇒ 打包 = BASE（正确序）**。
- **P2b（busy-first 惯用法，3 轮）**：`commit_to_busy = 34/32/31 ms`；`busy_to_done = 72/76/72 ms`；`commit_to_done = 106/108/103 ms`（准备循环 start→done = 89/85/88 ms）⇒ **帧时长"数十 ms"级，三样本一致于构造值 83.886 ms，与生产 32 µs 结构性不同**。MDC=762.9 Hz 为构造值（无示波器，未直测）。
- ⚠️ run1（本脚本第一版）**死在自己的 P3 循环**（我的 Tcl 拙误：for 缺 `{incr k}` 的 arity 错；且沿用了 B3 脚本的历史错序标签把 bit20 印成 "ssl"）⇒ run1 原始 stdout 保档、run2 已修并打印 raw 原文。

**③ 收尾恢复：0x28 + PCIe + 身份门 + `0x08=0`**：
- sha 门 `79c9cf434eb66723b97f654cbece9ea061632e2297c0a8ab0ea0dc198c43bec8` == 任务书锚 ✓（impl_1 交叉核对同 sha）；五判据 **BURN_OK**。
- **PCIe 设备级一次成功**（`RP_PORT=0000:00:1c.0`；首读行 `LnkSta: … Width x4` ⇒ 未升根端口级；本脚本按 **E-0 修正**取 `LnkSta` 行而非"首个 Width"死触发）；`Region 0` 1M / `Region 1` 64K；四个 `/dev/xdma0_*` 全现；`dmesg identify_bars: 2 BARs`。
- **身份门**：`MAGIC 0x50360001 / BID 0x00000028 / MARKER 0xdeadbeef / UNIMPL 0x15C=0xffffffff / SCRATCH 0x08=0`、`ID_RC=0`、`WINDOW_SCAN_NFF=0`（75 字）；硬判据 `C1_ID_RC / C2_LNKSTA_X4 / C3_BID_0x28 / C4_0x08_ZERO` 全 PRESENT。

## §6 收尾态（不关机）

板 = **0x28 + `0x08=0` + CARRIER=1**；NIC `192.168.100.100/32` / unmanaged / adaptive-rx off / 10000Mb/s；残留：`NO_P7B_PROCS / NO_TCPDUMP / NO_K0`；`p7b_snap.sh` md5 未变；本机无残留 vivado/xsim（另有一枚 `ssh.exe a@192.168.0.38` **非本轮所起**，未处置）；**未关机**。

## §7 偏离清单（逐条）

D-1 **E8 原样文件在 2025.2 不可用** ⇒ 一行最小修正（`MORE OPTIONS = {-generic DIV=65537}`；两版+diff+属性 dump+runme.log 全归档）· D-2 E8 实为 3 处 diff（第 3 处=注释头）· D-3 收尾目标 = **0x28+`0x08=0`**（APPLY_STEPS 原写 0x27；任务书预授权）· D-4 "S4.1" 实指 §4.2（已按 §4.2 执行）· D-5 run1 两处我自己的错（for arity / 标签错序）已修 · D-6 bat 自写（ASCII+CRLF 已核）· D-7 mdio 段 PCIe 消失为预期副作用、统一在 §5.5 恢复。

## §8 未观测 / 不可判

1. **bit18（eth_rstn）未被翻转激励**（诊断写错探针：本构建 `force_rst` 是独立 1-bit 探针 `vio_force_rst`；b18 恒 1 与 POR 后状态相符但未做动态验证；force_rst 通路未测）。2. **MDC 762.9 Hz 未直测**（构造值+帧时长间接吻合）。3. **P2 的"精确 83.9 ms"未达**（JTAG 读数节奏 ~20–70 ms 限分辨率）。4. **VIO 网段无覆盖**（R-a；不声称"排除地址字段伪影"）。5. **生产臂两个新信号="出现且恒 0"**（R-b）。6. **P3 的"丢瞬间 busy 必为 1"无逐拍见证**。7. **param_bad 未被优化掉无网表级点名**（只有行为读数）。8. **sim 臂与板级不是同一份证据**（sim 侧读数见 `p9_simfill_20261015/READINGS_A_mdio_aplus.txt`：帧 8388608 拍 / mdc1 65536 / mdct 131072 / pbad 1↔0 / ssl 0→1→0 + 两个变异件负对照）——本件 = "硅上见过"，分开读。9. **E8 修正未过审查**（一行；有 runme.log 与位级差异佐证）。

## §9 证据地图

`APPLY_LOG.txt` · `archive_impl1/`(12 件+自核) · `pre_edit_b3/` · `build_prod/`(stdout+bit/ltx+rpt+bat) · `build_divbad/`(run1 失败/run2 成功 stdout、两版 tcl、属性查询 tcl、bit/ltx/rpt) · `BUILD_READINGS.txt` · `board/PROBE_PROD_STDOUT.txt` · `board/PROBE_APLUS_STDOUT.txt`(+run1 保档) · `board/PROBE_APLUS_DIAG_STDOUT.txt` · `board/PROBE_APLUS_P2B_STDOUT.txt` · `board/PRE_WITNESS.txt` · `board/FINAL_STATE_APP_FINAL.txt` · `burn/`(三烧 BURN 日志+stdout 副本+脚本+0x28 副本) · `BOARD_READINGS.txt` · `SHA256SUMS.txt`。

**写入面**：仅新建轮目录（+ `_proj_mdio` 配方明示两处编辑，`build_mdio.tcl` 未动）；`tcpreg_program_stdout.txt` 为烧录固有 tracking 件（B1–B4 同款）；**零 git 写**、零 QSPI、零 xsim、license 未动。

---

## TL 抽核附加块（2026-10-16 02:5x，TL 亲核）

- 轮目录 **72 件**（含 `REPORT.txt` sha `46dbfa31…` 与 `SHA256SUMS.txt` 70 件自核 OK）✓；**PW 泄漏 grep = 0** ✓。
- **E8 修正亲读**：`build_divbad/build_mdio_divbad.tcl.fixed:29` = `set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-generic DIV=65537} -objects [get_runs synth_1]` ✓；**活件 `_proj_mdio/pj_mdio_divbad/mdio_prj.runs/synth_1/runme.log` 亲读** = `Command: synth_design -top mdio_vio_top -part xcku5p-ffvb676-1-e -generic DIV=65537` ✓（修正后 generic 真实生效）；轮目录 `build_divbad/BUILD_STDOUT_run2.txt:21/:67` 逐字含同两行 ✓（证据已归档）。
- **双构建读数亲读**（`BUILD_READINGS.txt`）：生产 `+7.328 / +0.029 / 0/0/0` ✓ · 变体 `+7.391 / +0.029 / 0/0/0` ✓；R9（两 sha 不同）✓。
- **板级位级读数亲读**（`board/PROBE_APLUS_STDOUT.txt`）：`APLUS_P1_IDLE … pbad=1 raw=1d001c` ✓ · `APLUS_P3_AFTER k=1 … ssl=1 raw=3d001c` + `APLUS_P3_TRIGGERED k=1` ✓。
- **收尾态亲读**（`board/FINAL_STATE_APP_FINAL.txt`）：`ID_BID 0x00000028` ✓ / `ID_UNIMPL 0xffffffff` ✓ / `SCRATCH_0x08 = 0x00000000` ✓ / `ID_RC=0` ✓。
- **TL 裁定**：读数与 agent 报告一致；**D-1（E8 一行修正）**为本轮唯一配方外改动 —— 证据链（属性查询 tcl + 修正前后两版 tcl + runme.log 生效命令行 + 行为面 P1=1/帧时长）完整，**采纳并登记**；其"未过审查"状态按自审模式转 **mdio 轮自审（已派）**。板 = **`0x28` + `0x08=0` + carrier=1**（与 B4 收尾态相同）✓。
