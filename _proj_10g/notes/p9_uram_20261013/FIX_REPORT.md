# P9 追加轮（URAM 板内缓冲）—— 复核修订 + 门重跑（FIX_REPORT）

**日期**：2026-10-13 · **工作树**：`D:\repo\XCKU5PMini\udp_hls_10g`
**轮次性质**：把 `REVIEW.md`（对抗复核；4 中 5 低 3 信息）的发现修掉 + 重跑门。
**全程 xsim-only**：未综合/未布线/未上板/未烧录；无 Vivado 并行。⛔ 本件**不下 PASS/FAIL 裁定**、
不写"时序已解决"；判据的验收权威仍在复核者/用户。未测处写"未测"，未观测处写"未观测到"。
**派单口径（TL）**：修 F2 / F3 / F1 / F5 / F4（至少 `dn_req-on-clr` + 连续两拍 clr）/ `P9-B-3d` / F7；
门重跑 = `sim/p9_uram`（real + 全部突变臂 + 新臂）· `sim/p6e_pcie`（`_counters` + 全链门）·
`sim/p9_axis_stream`（real）· `sim/p7b_mir`（real）；**先改完再跑**，跑动期间源码不改。

**改动件与绑定哈希（跑前 = 跑后逐字相同；原件 `gate_stdout_fix/input_hashes_{before,after}.txt`）**：

| 文件 | 行数 | sha256（跑前=跑后） | 性质 |
|---|---|---|---|
| `rtl/mir_uram_fifo.v` | 275 | `52db7c0f4c864880…`（全文见 hashes 件） | F2/F3 功能修复（2 行）+ F7① 注释 + 登记注释 |
| `sim/p9_uram/tb_mir_uram_fifo.v` | 445 | `397008b81968024b…` | F5 改名（全部 ≤32）+ 3 组新场景（+16 判据）+ 2 个新监视器 + rogue ifdef |
| `sim/p9_uram/mut_uram.py` | 119 | `6f1a924f901c96f7…` | 锚点改写到新行 + 5 条新臂 |
| `sim/p9_uram/run_tb_mir_uram_fifo.bat` | 108 | `f681b8b1bd48fa8e…` | F1 加固 + F5 守卫 + rogue 两臂分派 |
| `sim/p9_uram/namecheck.py` | 43 | `55d30ae0…`（新文件） | F5 守卫实现（见 §3 注） |
| `sim/p6e_pcie/tb_p6e_pcie_wrapper.v` | 950 | `322e06cc857c7a5f…` | `P9-B-3d` 双边账 + 具名常量 + 陈旧注释订正 |
| `board/wrapper_p4.v` | 4860 | `bcb24891db833541…` | **仅注释 +6/−0**（F2 不变量登记，例化处；⛔ `:1319-1322` 禁碰区零变化） |
| `_proj_10g/notes/p9_uram_20261013/REPORT.md` | — | `c240cc5f…` | F7②/F7③ 就地订正（+ 指向本件的订正块） |

**观测到的并行会话活动（与本轮无关，如实登记）**：`_proj_pcie/p7b_biz/p7b_mir_dump.cpp`
mtime `2026-10-13 07:43:15`（另一会话在改 PC 侧 dump 工具）。**它不在任何本轮门的编译闭包内**
（p6e 的 `files.f` = `rtl/*.v` + hls verilog + `board/{wrapper_p4,util_gmii…,uart_dbg}.v` +
`_proj_pcie/rtl/axi_regs.v` + stub + TB），对本轮读数**无影响**。BID 未动（构建轮的事）。

## §0 一页结论（修订计数 + 门结果）

| 项 | 复核级别 | 处置 | 证据（本件 § 节） |
|---|---|---|---|
| **F2**（`up_req` 无 `rst_n`） | 中 | ✅ ① `rst_n` 并入写门（1 行）② 跨模块不变量**两处登记注释** ③ 新 TB 场景 `GR` + 新臂 `mut_rstn_off`（**该臂被 GR1/G9g 抓红**，有牙实证） | §1-F2 |
| **F3**（clr 拍 dn 侧无门） | 中 | ✅ 语义裁定 = **clr 拍 dn 侧不交付**（`pop` 并入 `!clr`，1 行）+ 对照论证 + 新 TB 场景 `GC`（`dn_req` 保持 1 横穿 clr）+ 监视器 `clr_pop` + 新臂 `mut_dnclr`（**被抓红**） | §1-F3 |
| **F1**（突变臂"没跑也判抓到"） | 中 | ✅ 判据收紧为三段硬证据 + INFRA-FAIL 路径；**自测三条腿**：崩溃形态下 改前版 `EXIT=0 MUTANT-CAUGHT`（洞复现）vs 改后版 `EXIT=1 INFRA-FAIL`；假 `PASS_ALL` 形态下 `EXIT=1 MUTANT-NOT-CAUGHT` | §1-F1 + §4 |
| **F5**（判据名 >32 截断） | 低 | ✅ 全部判据名缩短到 ≤32（脚本审计 59/59、纯 ASCII）+ bat 新增 NAME-CHECK 守卫（`namecheck.py`；故意截断会被红） | §1-F5 |
| **F4**（缺臂/缺场景 6 类） | 中 | ✅ 补 5/6：`dn_req-on-clr`(GC)· 连续两拍 clr(GB)· `mut_en_off`· `mut_rstn_off`· `mut_wp_nmc`· 守卫有牙对(`guard_rogue` + `mut_guard_off`)；⛔ 未补 1 类（`arr_v` 的 `!clr` —— 复核自判"不必强补"）+ 2 个低优选留（见 §7） | §1-F4 |
| **`P9-B-3d`**（判据前提） | 复核 §I2 | ✅ **改了**（逐字记录见 §1-P9-B-3d：注入量绑具名常量 + 双边账 + 排空等待 + 陈旧注释订正）；`run_tb_p6e_pcie.bat` **全绿**（含 `P9-B-3d`/新增 `P9-B-3h`） | §1-P9-B-3d + §2 |
| **F7**（注释/行号小错 3 处） | 低 | ✅ ① rtl 指针位宽注释两处改正 ② REPORT §5.3"3 行注释"→"1 行代码 + 4 行注释" ③ REPORT §1.6 补"只覆盖 up 侧"限定 | §1-F7 |

**门读数汇总（全部 EXIT=0；原始 stdout = `gate_stdout_fix/`）**：

| 门 | 读数（末行） | 退出码 |
|---|---|---|
| `sim/p9_uram` real | `URAM_FIFO_GATE: PASS_ALL` + `NAME-CHECK: verdict_lines=59 with_visible_id=59` + `URAM-GATE-VERDICT: PASS-as-expected` | 0 |
| `sim/p9_uram` 12 突变臂 | 每臂 `MUTANT-CAUGHT-as-expected`（各自命中其目标判据，见 §2 表） | 0 ×12 |
| `sim/p9_uram` guard_rogue | `URAM-GUARD-VERDICT: GUARD-FIRED-as-expected`（守卫串 3 次命中） | 0 |
| `sim/p9_uram` mut_guard_off | `URAM-GUARD-VERDICT: GUARD-BLIND-CAUGHT-as-expected` | 0 |
| `sim/p6e_pcie` 全链门 | `PASS_ALL  tb_p6e_pcie_wrapper: 全链门全过` | 0 |
| `sim/p6e_pcie` `_counters` | `PASS_ALL  tb_p6e_pcie_counters: … 增量逻辑全过` | 0 |
| `sim/p9_axis_stream` real | `AXIS_C2H_STREAM_GATE: PASS_ALL` + `AXIS-GATE-VERDICT: PASS-as-expected` | 0 |
| `sim/p7b_mir` real | `APP_RX_MIRROR_GATE: PASS_ALL` + `MIRROR-GATE-VERDICT: PASS-as-expected` | 0 |

## §1 逐条修订（复核编号 → 修法 → 证据）

### F2（中）`up_req` 不含 `rst_n` —— 复位窗"取走但永不交付"通道

**修法（两件都做，派单要求）**：
1. **RTL 最小行**（`rtl/mir_uram_fifo.v:169`）：
   `assign      up_req   = rst_n && en && !clr && !ufull;`
   （旧式 = `en && !clr && !ufull`；复位窗 `occ` 被清零 ⇒ `!ufull` 为真 ⇒ 旧式会拉 req 并
   **收下**上游的字，而 `wp` 被复位钳住 ⇒ 该字"被取走却永不可读出"。并入后**结构性关闭**。）
2. **不变量登记注释（两处）**：`rtl/mir_uram_fifo.v` 写门处（含"改 `en` 来源/复位域/复位值或改
   wrapper 接线必须重推本段"）+ `board/wrapper_p4.v` `u_mir_buf` 例化处（约 `:3848`，**纯注释**）。
   登记内容 = `en`(= `mir_ctrl[3]`) 与 `rst_n`(= `pcie_axi_aresetn`) 同复位域 + `mir_ctrl_r` 复位 0
   （来源 `_proj_pcie/rtl/axi_regs.v`）—— 复核点名"改任何一处就静默打开"。
3. **新 TB 场景 `GR`（复位中途）**：源就绪 + `en=1` 期间拉低 `rst_n` 10 拍 ⇒ GR0（非空性前置：
   悬空 40 字）/ **GR1（复位期 `up_req||up_gnt` 违规计数 == 0）**/ GR2（释放后零错）/ GR3（流照常）。
   另加全窗监视器 `rst_take` → `G9g`。
4. **新突变臂 `mut_rstn_off`**（把 `rst_n &&` 从写门删掉，重开该洞）⇒ **必须被抓红**。

**证据（real 臂，`gate_stdout_fix/unit_real_xsim.log`）**：
```
  --- GR: reset mid-stream (rst_n low while en=1) ---
  [PASS] GR0 outstanding words pre-reset = 40 (带 [1,1000000])
  [PASS] GR1 no take/req in rst (10cyc) = 0
  [PASS] GR2 post-reset zero error = 0
  [PASS] GR3 post-reset stream alive = 201 (带 [50,1000000])
```
**有牙证据（`gate_stdout_fix/mut_rstn_off.txt` + `xsim_mut_rstn_off.log`）**：
```
  [FAIL] GR1 no take/req in rst (10cyc) = 10 (期望 0)
  [FAIL] G9g rst_take total == 0 = 10 (期望 0)
URAM_FIFO_GATE: FAIL (2 checks failed)
→ URAM-GATE-VERDICT: MUTANT-CAUGHT-as-expected   (EXIT=0)
```
（即：**旧式的洞被新场景直接量到 10 拍取数** —— 不是靠论证。）

### F3（中）clr 拍 `dn_gnt` 不门控 —— 先定语义，再修 + 补 TB

**语义裁定（设计块，一句话）**：**clr 拍对 dn 侧 = 不交付**（`dn_gnt` 强制 0；下游若在 clr 拍仍
保持 `dn_req`，该请求只被**忽略一拍** —— FWFT 合同只要求"`dn_gnt` 那拍 `dn_data` 有效"，
削发行、不引入数据冒险，**方向安全**；下拍无数据自然继续 0）。

**与下游合同的对照论证（为什么这样定）**：
1. **现役下游结构性不开门也安全**：`axis_c2h_stream` 的 `dma_req = en && !clr_drop && (…)`
   （`rtl/axis_c2h_stream.v:202`，`clr_drop=clr` `:167`）⇒ 现役系统 clr 拍 `dn_req=0` ⇒
   `pop=0` ⇒ **本修法对现役行为零影响**（两种写法在现役下逐位等价）。
2. **但"clr 拍不弹旧字"当时由下游承担** ⇒ 本模块自己的 clr 语义（"clr 拍全清 ⇒ 丢弃"）**不自足**：
   换一个不在 clr 拍关门的消费者，旧窗口头字会经 `dn_gnt` 漏进新窗口 —— 正是板级 D4 抓到的形态族。
   本修法把它升级为**本模块自足**。
3. 修法 = `rtl/mir_uram_fifo.v:155`：`wire pop = dn_req && (o_occ != 3'd0) && !clr;`
   （与 `up_req`/`u_wr`/`arr_v`/`issue` 的 `!clr` 同款；clr 拍 `o_occ` 到沿才清 ⇒ 不门就会带旧头字）。
   `dn_gnt = pop`、`dn_data = o_mem[op_r]` 两行不变。头注释 clr 段与 REPORT §1.6 同步补登记。

**TB 覆盖（两臂都要）**：新场景 `GC`（攒出 47 字悬空 → **`dn_req` 保持 1 横穿 clr 拍**）+ 监视器
`clr_pop`（`clr_m && dn_gnt` 计数 → `GC1` 与 `G9f`）+ 新臂 `mut_dnclr`（把 `!clr` 从 `pop` 删掉）。

**证据（real）**：
```
  --- GC: dn_req held high across clr (F3) ---
  [PASS] GC0 outstanding words pre-clr = 47 (带 [1,1000000])
  [PASS] GC1 clr_pop monitor == 0 = 0
  [PASS] GC2 clr: no stale leak = 0
  [PASS] GC3 clr: stream alive after = 203 (带 [50,1000000])
  … G9f clr_pop total == 0 = 0
```
**有牙证据（`mut_dnclr`）**：
```
  [FAIL] GC1 clr_pop monitor == 0 = 1 (期望 0)
  [FAIL] G9f clr_pop total == 0 = 3 (期望 0)
→ MUTANT-CAUGHT-as-expected   (EXIT=0)
```
（旧式在 clr 拍**真的弹了 3 个字** —— 复核点名的"零覆盖"组合现已被激励且有判据。）

### F1（中）突变臂判据"除 PASS_ALL 外都算抓到" ⇒ 崩溃=假绿

**修法（`run_tb_mir_uram_fifo.bat` `:mut_arm`）**："抓到"收紧为**三段硬证据**：
(a) 日志必须含判决行 `URAM_FIFO_GATE`（否则 = **INFRA-FAIL** `exit /b 1`）；
(b) **不得**含 `PASS_ALL`（否则 = `MUTANT-NOT-CAUGHT` 红）；
(c) 必须含 `[FAIL]` 行**或** RTL 守卫串（`FATAL mir_uram_fifo …`）；三者全不满足 = INFRA-FAIL。
（TIMEOUT 拦截原样保留在更前面。）

**自测（有牙，两跑；原件 `gate_stdout_fix/f1_selftest_{before,after}_fake.txt`）**：
用一个**崩溃形态日志**（`> xsim.log echo ERROR: [XSIM 43-3322] Fatal run-time error …`，
无判决行/无 `[FAIL]`/无守卫串）替换 xsim 调用行（其余流程原样），arm = `mut_val1`：
```
改前版 (旧逻辑): MUTANT-CAUGHT-as-expected        EXIT=0   ← 洞复现（"没跑也判抓到"）
改后版 (新逻辑): URAM-GATE-INFRA-FAIL: no URAM_FIFO_GATE verdict line   EXIT=1   ← 有牙
```
**第三条腿（mutant 竟"通过"必须红）**：同法把假日志换成 `URAM_FIFO_GATE: PASS_ALL`（即"突变没被
抓到"形态），arm = `mut_val1`（原件 `gate_stdout_fix/f1_selftest_passmut_fake.txt`）：
```
URAM-GATE-VERDICT: MUTANT-NOT-CAUGHT   EXIT=1   ← 有牙（"没抓到"不会被判成抓到）
```
（自测 bat 快照保留在同目录：`_selftest_f1_before{,_fake}.bat`、`_selftest_f1_after_fake.bat`、`_selftest_f1_passmut_fake.bat`。
注：`after_fake` 快照取自 F1 逻辑定稿、**臂分派修复前**的版本 —— 两版之间 `:mut_arm` 逻辑段**逐字相同**（已用脚本对拍：`mut_arm section identical: True`），差异只在臂分派段，与本次测试的 mut 路径无关。）

### F5（低）判据名 >32 字符被截掉前缀 ⇒ 判据 ID 在日志里整体消失

**修法**：① `tb_mir_uram_fifo.v` 里**全部判据名缩短到 ≤32 字符**（脚本审计：59/59 条、
纯 ASCII、最长恰 32；保留 ID 前缀在行首）；② bat 里新增 **NAME-CHECK 守卫**（real 臂）：
`%PY% namecheck.py xsim.log` —— 每条 `[PASS]`/`[FAIL]` 行都必须含 `"] G"`（ID 可见），
不等则 `URAM-GATE-NAME-CHECK-FAIL` 红（exit 2 → red）。
**证据**：real 臂 `NAME-CHECK: verdict_lines=59 with_visible_id=59`；日志里原被截的四条已可见，例如
`[PASS] G2a CAPACITY-PIN: occ == 4096 = 4096`、`[PASS] G1a taken >= 150 words = 199`。

### F4（中）缺臂/缺场景 —— 补 5/6

| 复核缺项 | 补法 | 抓红证据（臂） |
|---|---|---|
| ① `en` 项无臂 | 新臂 `mut_en_off`（写门去 `en`） | `G6a up_req stays 0 while en=0 = 30` |
| ② 复位路径零覆盖 | 新场景 `GR` + 新臂 `mut_rstn_off`（见 F2） | `GR1 = 10` / `G9g = 10` |
| ③ 守卫"无 req 给 gnt"从未被触发 | **新场景（ifdef）+ 一对臂**：`guard_rogue`（真 RTL + `-d URAM_TB_ROGUE`，TB 违约驱动 `up_gnt=1` 而 `up_req=0`，期望守卫串**出现**）守 与 `mut_guard_off`（删守卫 `$display`，同场景期望串**不出现**）| `GUARD-FIRED-as-expected` / `GUARD-BLIND-CAUGHT-as-expected` |
| ④ 连续/背靠背 clr + clr 拍 `dn_req=1` | 新场景 `GB`（clr 高两拍背靠背）+ `GC`（见 F3） | real 全绿；`mut_clr_take ⇒ GB1=2`、`mut_dnclr ⇒ GC1 红` |
| ⑤ `wp/rp` 位宽单点 | 新臂 `mut_wp_nmc`（wp 增量丢绕回位） | `G2a occ == 4096 = 200` + 14 条红 |
| ⑥ `arr_v` 的 `!clr`（纯防御项） | **不补**（复核自判"不必强补"，已登记） | — |

**守卫有牙臂的原始读数（`guard_rogue`）**：
```
FATAL mir_uram_fifo: upstream grant without req (violates aux contract, t=206550000)
FATAL mir_uram_fifo: upstream grant without req (violates aux contract, t=206554000)
FATAL mir_uram_fifo: upstream grant without req (violates aux contract, t=206558000)
URAM-GUARD-VERDICT: GUARD-FIRED-as-expected   (EXIT=0)
```
⇒ **三条 RTL 守卫现在全部有牙实证**：① `arr_full` ← `mut_issue_free`（3460 次）；② `wr_full` ←
`mut_full_off`（5 次）；③ 上游违契 ← `guard_rogue`（3 次）+ 对照 `mut_guard_off`。

### `P9-B-3d`（复核 §I2 修法意见）—— **改了什么、为什么（逐字记录）**

**为什么改**：旧判据 = "下游停收 + 灌 **700** 拍（2.8 KB）⇒ 期望 `ΔW70 > 0`"。URAM 板内缓冲把下游
弹性从 ≈2 KB 抬到 ≈34 KB 后 **2.8 KB 不再够填满** ⇒ `ΔW70=0` 而红。归因成立（**不是**计数路径
坏了 —— 诊断副本 80 KB 注入下 `ΔW70` 推进且整门 PASS_ALL）；这**不是**判据坏了，是**激励的
"够不够满"前提变了**。按复核 §I2 三条意见改（判据的验收权威仍在复核者/用户）：

1. **注入量/弹性预算绑具名常量**（防 `AW=13` 之类再静默失效、同一个坑第二次踩）：
   `P9B3_INJECT_BEATS = 20000`（= 80000 B ≈ 2.3× 弹性上界）、`P9B3_ELASTIC_MAX_BYTES = 35840`
   （**结构性上界**，预算逐项写进注释：镜像 FIFO 2048 + 打包 stg/acc ≤24 + URAM 32768 +
   缓冲弹性堆 32 + 在飞 ≤24 + 成形器暂存 32 + 粒度裕量）、`P9B3_RESID_ACCEPT = 1`、
   `P9B3_DRAIN_CYCLES = 20000`。
2. **判据升级为双边账**（取代 `> 0`；">0 只证路径活着，抓不到多计/少计"）：
   - **下界腿**（`P9-B-3d`）：`ΔW70 ≥ 注入字节 − 弹性上界`；
   - **上界腿**（新 `P9-B-3h`）：**恢复期交付量 == 注入字数 − ΔW70/4**（容差 ±1 字 = 镜像打包
     残余；"注入 − 丢弃 = 交付"闭账 ⇒ 多计/少计/丢账全被夹住）。
   - 配套：`MIR_DMA_CNT` 基线改**显式读**（`mi_cnt_a`）；恢复期等待从 600 拍扩到
     `P9B3_DRAIN_CYCLES`（旧等待**够不着新容量**，实测需 ~4400 拍）。
3. **同步订正判据旁陈旧推理注释**（"下游弹性只有几十字节"已随 URAM 缓冲作废；`P9-B-3b` 的
   "计数只推进到暂存满"改写为"成形器暂存 32 B = 4 grant；缓冲自己吸走的 32 KB 不计入本计数"）。

**逐字读数（`gate_stdout_fix/p6e_fullchain.txt`）**：
```
  [INFO] P9-B-3 W70: 4d494e79 -> 4d49fea1 (注入 20000 拍 = 80000 B, 下游停收)
  [INFO] P9-B-3 dW70 = 45096 B (弹性上界预算 = 35840 B, 实测吸收 = 34904 B)
  [PASS] P9-B-3d lower leg: dW70 >= inject - elastic_max (= 44160)
  [INFO] P9-B-3 delivered words = 8746 ; beats = 2181 ; keep_bad = 0
  [INFO] P9-B-3 close: injected=20000 w, dW70/4=11274 w, expected_delivered=8726 w, delivered=8726 w
  [PASS] P9-B-3h upper leg: delivered == inject - dW70/4 (±1)
PASS_ALL  tb_p6e_pcie_wrapper: 全链门全过    (EXIT=0)
```
⭐ **实测吸收 = 34904 B 与结构性账逐字吻合**（2048 FIFO + 32768 URAM + 32 弹性堆 + 32 成形器
暂存 + 24 在飞 = 34904）⇒ 弹性上界预算 35840 有 ~0.9 KB 裕量、且**上界腿无需动容差即精确闭合**
（delivered == expected 恰等）。全链门其余判据**零变化**（唯一的红被修掉、其余逐字仍在）。
**诊断件未动**（`diag_p9b3d/` 作为历史证据保留）；**`run_tb_p6e_pcie_mut{,2}.bat` 未重跑**（见 §7）。

### F7（低）注释/报告小错 3 处

1. **rtl 指针位宽注释互相矛盾且都错**（复核 F7①）：`rtl/mir_uram_fifo.v` 两处改为与代码一致
   （`OQ=2 ⇒ 1 位, 3..4 ⇒ 2 位, 5..7 ⇒ 3 位`；代码判据 `OQ<=2 ? 1 : (OQ<=4 ? 2 : 3)` 未动），
   并就地注明"旧句一对写 2..4⇒1、另一对写 2..4⇒2"的订正来源。默认 `OQ=4` 下无功能影响。
2. **REPORT §5.3 "只差那一行 + 3 行注释"** ⇒ 订正为 **"1 行代码（注入量 700→20000）+ 4 行注释，
   `diff` 现读 `722,726c722`、899 vs 895 行"**（复核 F7②）。
3. **REPORT §1.6 "clr 拍不取数"措辞** ⇒ 就地加限定："**只覆盖 up 侧**；dn 侧同轮已补门
   `pop &&= !clr` ⇒ clr 拍 `dn_gnt` 强制 0"（复核 F7③）。REPORT 头部另加指向本件的订正块。

## §2 突变/守卫臂逐条读数（12 突变臂 + 2 守卫臂，全部 EXIT=0）

| 臂 | 打的性质 | 抓红它的判据（首两条） | RTL 守卫串命中 |
|---|---|---|---|
| `mut_full_off` | 满也取数 | `G2a occ == 4296`、`G2b = 4299` | `URAM write while FULL` ×5 |
| `mut_full_e1` | 容量少 1 | `G2a occ == 4095`（仅 1 条） | — |
| `mut_issue_free` | 到达覆盖弹性堆 | `G2a occ == 1`、`G2b = 4299` | `arrival into FULL elastic FIFO` ×3460 |
| `mut_val1` | 到达早一拍 | `G1b seq_err = 195`、`G2g = 4303` | — |
| `mut_clr_off` | clr 不丢弃 | `G2g = 4107`、`G3e = 4107` | — |
| `mut_clr_take` | clr 拍取数 | `G5c clr_take = 3`、`GB1 = 2` | — |
| `mut_dnreq` | 幻影弹 | `G1b seq_err = 198`、`G1c over_err = 2` | — |
| **`mut_rstn_off`（新）** | 复位期取数（重开 F2 洞） | **`GR1 = 10`**、`G9g = 10` | — |
| **`mut_en_off`（新）** | 停排空还取数 | `G6a = 30`（仅 1 条） | — |
| **`mut_dnclr`（新）** | clr 拍弹旧头字（重开 F3 洞） | **`GC1 = 1`**、`G9f = 3` | — |
| **`mut_wp_nmc`（新）** | wp 绕回位写窄 | `G2a occ == 200`、`G2b = 4299` | — |
| **`mut_guard_off`（新）** | 删守卫③ `$display` | （rogue 模式）守卫串**不出现** ⇒ 对照臂成立 | 0（预期） |
| **`guard_rogue`（新, ROGUE 模式）** | TB 违约驱动 | —（期望串出现） | 上游违契串 ×3 |
| `real`（ROGUE 模式外） | — | — | 0 |

**real 臂其余新场景读数**：
```
  [PASS] GB1 2clr: no clr_take = 0 / GB2 no clr_pop = 0 / GB3 zero err = 0 / GB4 alive = 203 / GB5 closed = 0
  [PASS] G9a..G9g 全 0; G9e FINAL: eq_w == eq_r closed = 24702
  URAM_FIFO_GATE: PASS_ALL   (59 判据 / 0 FAIL, 206.518 µs 处 $finish)
```
（原有 43 条判据语义未改；本轮 +16 条 = GR4 + GC4 + GB6 + G9f/G9g；总 59。）

## §3 顺带发现（工具面，已就地处理）

- ⛔ **`for /f %%n in ('cmd1 ^| cmd2')` 管道惯用法在本机挂死**：F5 守卫原写成
  `findstr … | find /c /v ""` 放在 `for /f` 里 ⇒ **find.exe 悬在控制台等输入**、门挂住（实测：
  420 s 未返回、进程表里 `find.exe` 常驻）。已改为独立脚本 `namecheck.py`（bat 里
  `%PY% namecheck.py xsim.log || …`），并在 bat 注释与本文件记录。**本仓其它 bat 是否有同款
  惯用法 = 未普查**（见 §7）。
- ⛔ **`set X=v & set Y=w` 的尾随空格陷阱**：臂分派最初用括号块 `( set EXPECT=ROGUE & … )` ⇒
  `EXPECT` 值带尾随空格 ⇒ `if "%EXPECT%"=="ROGUE"` 恒假、静默走了 real 分支（症状 = rogue 臂
  报 `URAM-FIFO-FATAL` 而非 guard verdict）。已改为 `goto` + 独立 `set` 行（不荐再写带 `&` 的
  `set` 块）。两坑都属"静默换了路径"，故登记。

## §4 门重跑的绑定条件（读数可追溯）

- **跑动期间源码零改动**：`rtl/mir_uram_fifo.v` / `tb_mir_uram_fifo.v` / `mut_uram.py` /
  `run_tb_mir_uram_fifo.bat` / `namecheck.py` 的 sha256 **跑前=跑后逐字相同**
  （`gate_stdout_fix/input_hashes_{before,after}.txt`；跑窗 = 2026-10-13 07:40–07:44）。
- 本次独有串（防"读了上次的陈旧件"）：`GUARD-FIRED-as-expected` /
  `P9-B-3d lower leg` / `P9-B-3h upper leg` / `NAME-CHECK: verdict_lines=59` 均为本修订轮
  首次出现的串；`gate_stdout_fix/` 里各件 mtime 全落在本跑窗内。
- `p6e_fullchain` 二进制绑定：改动后的 `sim/p6e_pcie/tb_p6e_pcie_wrapper.v`
  sha256 `322e06cc857c7a5f…` 即本次运行所编译的版本（mtime 07:41:13 < 跑动结束 07:43:24）。

## §5 本轮改动清单（文件 → 位置）

1. `rtl/mir_uram_fifo.v`：`:155`（`pop &&= !clr`，F3）· `:169`（`rst_n &&` 并入写门，F2）·
   头注释不变式①/clr 段/写门处登记/守卫段/指针位宽注释（F2/F3/F7① 注释）。
2. `board/wrapper_p4.v`：`u_mir_buf` 例化处（约 `:3848`）**仅注释 +6 行**（F2 不变量登记）；
   ⛔ `:1319-1322` 零变化（`git diff` 单 hunk）。
3. `sim/p9_uram/tb_mir_uram_fifo.v`：判据名全缩短（F5）· 监视器 `clr_pop`/`rst_take` ·
   场景 `GR`/`GC`/`GB` · `URAM_TB_ROGUE` ifdef（rogue 源模型 + 收尾 rogue 窗口）。
4. `sim/p9_uram/mut_uram.py`：`UP_REQ_LINE` 常量重写锚点 + 5 臂新增（`mut_rstn_off`/`mut_en_off`/
   `mut_dnclr`/`mut_wp_nmc`/`mut_guard_off`）。
5. `sim/p9_uram/run_tb_mir_uram_fifo.bat`：F1 三段硬证据 + INFRA-FAIL · F5 NAME-CHECK ·
   臂分派 `goto` 重构（guard_rogue/mut_guard_off 走 `-d URAM_TB_ROGUE`）。
6. `sim/p9_uram/namecheck.py`：新文件（F5 守卫）。
7. `sim/p6e_pcie/tb_p6e_pcie_wrapper.v`：`P9B3_*` 具名常量 · `P9-B-3d` 双边账 · `P9-B-3h` 闭账 ·
   排空等待 600→20000 拍 · `mi_cnt_a` 显式基线 · 陈旧注释订正。
8. `_proj_10g/notes/p9_uram_20261013/REPORT.md`：F7②/F7③ 就地订正 + 头部订正块。
9. 证据：`_proj_10g/notes/p9_uram_20261013/gate_stdout_fix/`（36 件：各臂 stdout + 各臂
   `xsim.log` + F1 自测两跑 + 哈希前后 + 四个既有门 stdout）。

## §6 已知边界（本件自认）

- 只跑 xsim；**综合/URAM 推断/时序一律未测**（构建轮的事；F6① 的两条更硬判据归构建轮）。
- `P9-B-3h` 的 ±1 字容差来自"4 B/拍注入 ⇒ 打包残余 ≤1 个 32 位字"这一**结构性论证**（本轮
  real 跑实测恰等、未动容差）；若未来改注入粒度（非 4 B 整字）该容差需重推。
- 上界腿的"排空完成"靠固定 20000 拍等待（≈4× 实测需求），**不是**结构判据；若排空未完成，
  红会显形（不会静默通过），但"红 ⇒ 排空未完 vs 真丢账"的区分需要看 `[INFO]` 三行读数。
- 走廊外：另一会话在改 `_proj_pcie/p7b_biz/p7b_mir_dump.cpp`（不在任何门闭包内，已登记）。

## §7 未竟项（⛔ 不许当已答）

1. **F6② `SIM_ASSERT_CHK(0)` 的口径登记未做**（不属本轮派单修正项）；F6① 的更硬 URAM 推断判据
   （构建脚本硬门 / OOC synth 核 `Synth 8-6793` + URAM 计数）= **构建轮**。
2. **F4 余项未补**：`clr` 紧邻 `up_gnt`（clr-1 拍成交 / clr 拍清账）场景 · TB 侧 `en` 沿
   （1→0 当拍有 gnt）场景 · `LAT` 参数自检的负对照（"故意 `LAT=2` 应硬失败"；复核自评"低优先"）。
   （`arr_v` 的 `!clr` 按复核意见**不补**，已登记。）
3. **p6e TB 其余判据名仍走 `[255:0]` name 端口**（>32 截断 + 非 ASCII 逐字节损坏 —— 全链日志里
   大片乱码即此）—— 本轮只保证**改动的 `P9-B-3` 块**判据可读（新判据用纯 `$display` 不经 name 口）；
   全 p6e TB 判据名清理**未做**（范围外）。
4. **`run_tb_p6e_pcie_mut{,2}.bat` 未重跑**（不在派单门清单内）⇒ "TB 改动是否影响这两门"**未核**。
5. **F8 三格未动**（复核低优先，登记）：常驻 P4 矩阵指纹不含 P9 三件 · 未打 xpm 补丁的历史 bat
   重跑会响（配方在 REPORT §5.4）· `aliasgate` 不含 `PCIE_OBS`。
6. **F9（板级无缓冲水位见证）**留给板级轮（`dbg_occ/dbg_oocc` 仍空接；"逐字节全查 + `ΔW70` +
   式 A/式 B 三条同时判"的建议转给板级协议）。
7. **`for /f ('… ^| …')` 挂死惯用法未普查**（§3）：本仓其它 bat 若有同款写法，重跑时可能同样挂住；
   本轮的处置只覆盖 `sim/p9_uram/run_tb_mir_uram_fifo.bat` 一处。
8. 三个自测/快照 bat（`_selftest_f1_*`）保留作证据；若要收进 `.gitignore`/删除，属仓库整理轮的事。

*本件 = 修订 + 门重跑读数；判据层面的裁定（尤其 `P9-B-3d/h` 改法的验收）归复核者/用户。*
