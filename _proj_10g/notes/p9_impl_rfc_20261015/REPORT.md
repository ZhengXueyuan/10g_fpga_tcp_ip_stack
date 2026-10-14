# P7B-BUILDG-RFC-SEQ 施工轮报告（实施 agent `p9_impl_rfc_20261015`）

> 依据 = 设计件 **`_proj_10g/notes/p9_fix_rfcseq_design_20261014/P7B_BUILDG_RFC_SEQ_DESIGN_v3r2.md`**（853 行，权威）。
> 范围 = RTL + 双 oracle + 模型 + TB + 新门 `sim/p3sim_rfc/` + `.gitignore`。**只跑 xsim；未跑 Vivado（构建=下一棒）；未上板。**
> **本件不下 PASS/FAIL 裁定**（判据所有者 = 用户/TL）；「未观测到」≠「不存在」。所有读数 = 本次实测。
> 轮内证据/原件目录 = `_proj_10g/notes/p9_impl_rfc_20261015/`（baseline/ · genchk/ · logs/ · 本件）。

---

## 0 一句话结论

**新门 7 臂全绿；两门既有红/绿逐字复现；criterion-0（尾部段默认关守恒）字节级成立；**
**另发现 2 处「设计与现读不符」**（§6-A `wnd_l` 前提错、§6-B G 臂 CLI 臂 spec 自相矛盾），
均按「保守 + 不自行改设计」处置并 **登记待裁定**；其中 §6-B 的处置把设计**自己的判据 4（G ⇒ RC=0）实测跑绿**。

---

## 1 交付物①：逐文件 diff 摘要

`git diff --stat`（工作树 vs HEAD `d77ed02`）：

```
 .gitignore                  |  15 ++
 rtl/tcp_rx.v                |  11 +-
 tb/tb_tcp_rx.v              | 189 +++++
 tools/gen_stim_tcp_chain.py |   4 +-
 tools/gen_stim_tcp_rx.py    | 145 +++++--
 5 files changed, 355 insertions(+), 9 deletions(-)
```

**新增（未跟踪）**：`sim/p3sim_rfc/{run_rfcseq_gate.bat, frozen/tcp_rx_prefix.v, mut/mk_mut_rfc.py, logs/*4}`。
**未动**：`board/**` · `rtl/vlan_strip.v` · `rtl/app_pattern.v` · 几何/读侧脚本（本刀不搭计数器 ⇒ §6.3 的"零几何改动"整块兑现）。

### 1.1 `rtl/tcp_rx.v`（**唯一功能改点 = 1 行表达式**）

- **hunk 1** `@@ -320 +320,8 @@`：旧行 `wire seq_lt = (seq32 < ra_rcv_nxt); …` 整行替换为设计 §3.6① 的 **8 行块**。
  **非注释变更 = 恰好 1 行**：`wire        seq_lt   = seq_diff[31];           // = $signed(seq32 - ra_rcv_nxt) < 0`
  （替换文本从 v3r2 的 §3.6 代码块**逐字提取**，非手抄——见 `apply_rtl_edit.py`）。
- **hunk 2** `@@ -356 +363 @@`：**:356 = 纯注释订正**，逐字照抄 §3.6② 代码块
  `// 窗口内乱序 (相对差为正) 与重复/旧段 (RFC SEQ_LT: 相对差的高位为 1): 丢数据仍回 ACK`
  （⚠️ 按 §3.6 的代码块**整行替换** ⇒ 原行尾的 ` (快速重传/dup-ACK 依赖)` 随块消失；见 §6-D 登记）。
- **③ `:359-360` = 不改**（设计件自证"保留原文即可，本件 = 该核对"）：现读 `:367` 的 `(!seq_eq && !win_ok && !seq_lt)` **逐字未动** ✓；**④ `:342-345` = 不改** ✓。
- §1.3"改 1 行 = 两处同时修好"机械复核：`grep -n seq_lt` = **4 命中**（`:327` 唯一定义 / `:357` `w6a_ok` / `:367` 注释 / `:370` `ackresp`）；全仓 `rtl/` 除本文件 **0** ✓。
- 行数/行尾：929 → **936 行**；CRLF 929 → 936（**纯 CRLF、0 孤立 LF**）✓。
- **sha256**：`7517c949…` → **`a35cd9809d233ebd3bc08bee1df6faa3c1c68882578dfba4cfe20c1cbf6fbc02`**；git blob `c8c7113b…` → **`a73b0be6ca32165f61fcc32b9ca4405b68d4d625`**。

### 1.2 `tools/gen_stim_tcp_rx.py`（16 hunks；§5.5 全项）

非注释改动清单（按 hunk 序）：
1. `+27,7`：模块级 `SEQ_RFC = os.environ.get('SEQRFC_ARM','fixed') != 'legacy'`（§5.5 逐字）。
2. `+119,54`：`RF_PAD0/RF_GAP/RF_SNAP_LAG/RF_TAIL_IDLE/TAIL0` + `build_tail()`（5 帧，seq/ack/长度按 §5.4 写死）+ `check_tail_domains()`（两侧域**写死自检**：F5 d==0x80000000 边界、F1/F2 ≥2^31、F3/F4 0/0x20000；旧式 seq_lt 全 0 / 新式 [1,0,0,1,1]）。
3. `+379,31`：`generate()` 尾段（**env `SEQRFC_TAIL=1` 门控**；默认关 ⇒ 以上全部字节索引与生成物不变）——布局 [200B 空隙][cfg2 6B][60B] F5 [60B] F3 [60B] F4 [60B] F1 [60B] F2 [120B]；每帧末 +30 快照；**布局不变量逐条 assert**（任一条不成立 = 生成即硬失败）。
4. `+441,8`：写 `rf_legs.memh`（7 位置）+ `rf_cfg.memh`（6 重配值，`TAIL0` 同源）；`return` 增第 5 元 `rf`（两个调用点同步）。
5. `+487 / +521 / +559 / +583`：`model()` 解包 5 元；`w6a_ok_l` 状态初始化；**oracle 臂化**（§5.5 逐字）：
   `seq_lt = (((seq32 - t['rcv_nxt']) & 0xFFFFFFFF) >= 0x80000000) if SEQ_RFC else (seq32 < t['rcv_nxt'])`；
   `nonlocal` 补 `w6a_ok_l`。
6. `+659,5`：wc==5 加 `w6a_ok = base_ok and plen_w == 0 and ((seq_diff <= t['rcv_wnd']) or seq_lt)` + 锁存（镜像 RTL `:356-357`/`:717`）。
7. `+674,5`：w6 支**新增** `elif w6a_ok_l: st_n = 'PAD'; wcnt_n = 7`（设计 §5.5；**不锁存 `wnd_l`** = 设计逐字，附现读勘误注释 —— 见 §6-A）。
8. `+681`：提交 `w6a_ok_l`。`+717,15`：w6a 支注释块。`+890`：`rf` 重配镜像注入（与 TB 同字节点）。`+962,4`：主块打印 `RFSEQ rf_pos …`。
9. `+1134 / +1137,3`：主块解包 + 打印。

**模型保真度复核（§5.5 硬要求）**：默认路径（尾段关）实测 —— nostall/stall 的**模型输出与改动前逐字相同**（297 行 / 同 stats）
⇒ "w6a 建模对现有 nostall/stall 激励 = 空操作"成立；**hard 模式模型输出变了 1 帧**（96→97 行、pss 19→20），见 §3/§6-C。

### 1.3 `tools/gen_stim_tcp_chain.py`（1 hunk，§5.5 逐字）

`:355` `seq_lt = seq32 < tb['rcv_nxt']` → `seq_lt = ((seq32 - tb['rcv_nxt']) & 0xFFFFFFFF) >= 0x80000000`（**无臂**：该门只编活 RTL）+ 2 行注释。逐位等价实证见 §5。

### 1.4 `tb/tb_tcp_rx.v`（8 hunks，**全部落在 `ifdef SEQRF_TAIL` 或新增 localparam 块内**；+189 行）

1. `+24,17`：头注 + `SEQRF_ARM` localparam（`-d SEQRF_LEGACY` ⇒ 0）。
2. `+88,15`：`rf_pos[0:6]` / `rf_cfg[0:5]` / 9 组快照数组 / `mwcnt` / 8 个判据标志（全 `ifdef` 内）。
3. `+312,11`：cfg 链插 `rf_pos[0]` 重配支（`%6` 字段序 = `FIELDS` 顺序；`rf_pos[0]!=0` 守卫 ⇒ memh 读失败时不污染基础流、腿判据响亮变红）。
4. `+364,18`：尾段快照循环（6 点；值 = pass/dseq/dnm/ackc/mw/snd_una/rcv_nxt/W68dut/W68tb）。
5. `+398,4`：`mwcnt` 计数（m_axis 接受词，TB 侧独立计数）+ `+421,13` readmemh + banner。
6. `+512,108`：尾部段判据块（期望 = §5.4 写死常量；A 臂 `RFSEQ ALL PASS` / LEGACY 臂 `RFSEQ LEGACY OK` + 3 个 `XFAIL-REPRODUCED`；每帧 `RFSEQ Fx PASS` / `[FAIL] RFSEQ Fx` 行 + 守恒 + 终态 + W68 增量）。
7. `+635,3`：`mwcnt` 显式初始化（**未初始化 reg = x ⇒ 全部 mwd 判据永久 x** —— 首跑实测踩到、已修，见 §6-D）。
8. 既有代码路径**逐字节未动**（compile-out = 零行为差；由 criterion-0 与两门逐字复现双重背书）。

### 1.5 `.gitignore`（+15 行）

照 `sim/p3sim_sw` 同款白名单：门驱动 bat / `frozen/`（含 sha256 钉住的 `tcp_rx_prefix.v`）/ `mut/mk_mut_rfc.py` / `logs/*.txt` 放行；
**回归生成物（`mut_M*.v`）与全部运行工作目录（`runA_a/…`、resp memh）维持忽略**。实测 8 条 `git check-ignore --no-index` 逐条符合预期（5 放行 / 3 忽略）。

### 1.6 新门 `sim/p3sim_rfc/`

```
sim/p3sim_rfc/
├── run_rfcseq_gate.bat        # 自定位 + PATHGUARD（照 p3sim/p3sim_sw 头）+ :run 子程序（ASCII + CRLF，364 行）
├── frozen/tcp_rx_prefix.v     # G 臂源 = 修复前字节副本（sha256 == 7517c949…，实测复核）
├── mut/mk_mut_rfc.py          # M1..M4 生成器（锚定 + 计数 + CRLF 守恒；锚点不中 ⇒ 硬失败不落盘）
├── mut/mut_M1..M4.v           # 生成物（每次门运行重生成；不入库）
└── logs/{gate_stdout.txt, mutgen.txt, frozen_revision_sha256.txt, baseline_head_hard_evidence.txt}
```

---

## 2 交付物②：新门读数（run3；与设计 §5.3 臂表 / §5.4 期望表逐字对）

**门总读数**：`RFCSEQ-GATE: PASS`（`exit /b 0`；门输出 0 条 `[FAIL]`；原件 `logs/gate_run3.txt`，sha256 `d7832ad9…`，
归档副本 `sim/p3sim_rfc/logs/gate_stdout.txt`）。**跑前 `tasklist` 已核无 xsim/xelab/vivado；全程串行。**

### 2.1 逐臂（设计臂表 ↔ 实测）

| 臂 | DUT 源（sha256 守卫） | TB 定义 | 模型 env | 期望（设计） | **实测** |
|---|---|---|---|---|---|
| A | `rtl/tcp_rx.v` = a35cd980… ✓ | `-d SEQRF_TAIL` | fixed | 全腿绿 + 模型 OK | **RFSEQ ALL PASS（xs1/xs2/xs3 三模式）+ SNDWND ALL PASS + chk_ns RC=0** ✓ |
| A-off | 同上 ✓ | 无 | 默认 | resp 三份 == 冻结基线 | **三份 sha256 全中**（§5.1）+ chk_ns RC=0 ✓ |
| G | `frozen/tcp_rx_prefix.v` = 7517c949… ✓ | `-d SEQRF_TAIL -d SEQRF_LEGACY` | **legacy** | 红点 = {F5,F1,F2}；{F3,F4} 相同；模型 OK | **RFSEQ LEGACY OK + F5/F1/F2 XFAIL-REPRODUCED（三模式）+ chk_ns RC=0** ✓ |
| M1 | `mut_M1.v`（1d442c7c…，每次门内重生成 + 生成器结构断言） | `-d SEQRF_TAIL` | fixed | 与 A 逐条相同 | **RFSEQ ALL PASS×3 + resp 三份 `fc /b` 与 A 逐字节相同** ✓ |
| M2 | `mut_M2.v`（91e112b5…） | 同上 | fixed | 红点**恰好** {F2} | **红点恰好 {F2}**（F5/F3/F4/F1 全 PASS；聚合线不在）+ 模型 MISMATCH 且冻结签名逐字命中 ✓ |
| M3 | `mut_M3.v`（d8984caa…） | 同上 | fixed | 红点**恰好** {F5} | **红点恰好 {F5}** + 冻结签名命中 ✓ |
| M4 | `mut_M4.v`（5cbe90b9…） | 同上 | fixed | 红点 ⊇ {F1,F2,F5} | **红点 = {F1,F2,F5}**（= 设计 ⊇ 的最小实现）+ 冻结签名命中 ✓ |

### 2.2 A / G 两臂逐帧原始读数（xs1；xs2/xs3 逐字相同；增量 = 相邻快照差）

```
== A 臂 (RFSEQ ARM=FIXED) ==                     == G 臂 (RFSEQ ARM=LEGACY) ==
F5 passd=0 dseqd=1 dnmd=0 ackd=1 mwd=0           F5 passd=0 dseqd=0 dnmd=1 ackd=0 mwd=0
F3 passd=1 dseqd=0 dnmd=0 ackd=1 mwd=13          F3 passd=1 dseqd=0 dnmd=0 ackd=1 mwd=13   <- 两臂逐位相同 ✓
F4 passd=0 dseqd=0 dnmd=1 ackd=0 mwd=0           F4 passd=0 dseqd=0 dnmd=1 ackd=0 mwd=0   <- 两臂逐位相同 ✓
F1 passd=0 dseqd=1 dnmd=0 ackd=1 mwd=0           F1 passd=0 dseqd=0 dnmd=1 ackd=0 mwd=0
F2 passd=1 dseqd=0 dnmd=0 ackd=0 mwd=0           F2 passd=0 dseqd=0 dnmd=1 ackd=0 mwd=0
END snd_una=00000010 rcv_nxt=00000164            END snd_una=00000000 rcv_nxt=00000164
    snd_wnd=4000 w68d=1 (dut 1)                      snd_wnd=4000 w68d=0 (dut 0)
```

与设计 §5.4 对表：**逐项全中** —— A 的 `ACK={F5,F3,F1}`（3 个）+ `dseq=2` + `dnm=1（F4）` + `pass=2（F3,F2）`；
G 的 `ACK={F3}`（1 个）+ `dseq=0` + `dnm=4` + `pass=1`；**守恒两臂都 = 5 帧**（每帧 pass+dseq+dnm == 1 由 `rf_cons_ok` 机器断言）；
终态 `snd_una：A=0x10 / G=0x0`、`rcv_nxt 两臂=0x164`、`snd_wnd 两臂=0x4000`；**W68ADV 增量 A=1 / G=0 且 dut==tb**。
模型侧段汇总（chk_ns 逐字）：A `pss=26=24+2 / dnm=8=7+1 / seq=6=4+2 / ack=20=17+3`；G `pss=25=24+1 / dnm=11=7+4 / seq=4 / ack=18=17+1` —— 与 §5.4 的"段汇总（写死）"逐字一致。

### 2.3 M2/M3/M4 的模型检查：冻结首分歧签名（**回填**，逐条语义核过）

| 臂 | `check fixed nostall` 首分歧（逐字，已写进 bat 常量） | 语义定位（施工时核） |
|---|---|---|
| M2 | `nostall LINE 315: exp 'FEND 0' resp None` | **F2 的 fend_pad FEND 行缺失** = 设计预测红点 {F2} 本身 ✓ |
| M3 | `nostall LINE 297: exp 'ACK 0 00000100' resp 'META 0a000001 3039 0064 0 00000100'` | **F5 的 ACK 缺失**（边界帧被 M3 判"未来" ⇒ 静默）= 预测红点 {F5} ✓ |
| M4 | `nostall LINE 245: exp 'ACK 0 00000A73' resp 'META 0a000001 d431 0014 1 00000000'` | 基流 `dup` 帧的 ACK 丢失 = 流序上**第一个依赖 seq_lt=1 的既有帧**（M4 的 ⊇ 语义 ⇒ 允许早于尾段）✓ |

（三条均**在本轮首跑时发现并逐条核对语义位置后才冻结**；非"跑绿即钉"。）

### 2.4 门内其它判据（全部 PASS）

- 判据 4（**注释-实现一致性**，§5.3-6）：`seq_diff[31]` 与 `RFC 793 SEQ_LT` 在；**活动行**无 `seq32 < ra_rcv_nxt`（python 逐行核）✓。
- **哈希守卫**：A 源（A/AO/M* 共用基底）= a35cd980… ✓；G 源 = 7517c949… ✓（臂内跑前守卫 + 跑前顶层复核）。
- 每臂 `xvlog/xelab` 干净（**五键隐式网扫描**含 xelab 面；任一中 ⇒ 硬失败）✓；三模式 xsim 的 banner 守卫（无跑 ⇒ 硬失败）✓。
- **env 臂负对照**（§5.3-5 精神，镜像 p3sim_sw 判据 6）：G 臂 resp + `SEQRFC_TAIL=1` 但**去掉** `SEQRFC_ARM=legacy` ⇒ **MISMATCH**（RC≠0）✓。
- 末行纪律：`FAIL count>0 ⇒ exit /b 1`，无无条件 PASS ✓（run1/run2 的 FAIL 都正确落到了退出码 255/1）。

---

## 3 交付物③：`p3sim` 复跑（RC + hard 首分歧签名逐字对照，§5.6 预测）

| 项 | 冻结基线（改动前现取） | **复跑（改动后）** | 判定 |
|---|---|---|---|
| RC | 1 | **1** | 逐字不变 ✓ |
| `hard LINE 63` 首分歧 | `hard LINE 63: exp 'META 0A000001 D431 0014 1 00000000' resp 'FEND 1'` | **逐字相同** | ✓（§5.6 核心预测成立） |
| nostall / stall | `297 lines … OK`（同 stats） | **逐字相同**（297 行 / pss 24 / dnm 7 / seq 4 / ack 17 / bytes 1843 / OK） | ✓ |
| DUT 侧 resp | `resp_tcp_rx{.memh,_stall,_hard}` = 7c95315f… / 7c95315f… / 2d96e7cc… | **三份 sha256 逐字相同** | ✓ |
| 仿真时长 | `$finish … time : 53092 ns` | **53092 ns**（逐字） | ✓ |

**逐字差异清单（全量；用 diff 精算，非目测）**：
1. `VRFC 10-3645` 四条"端口未连接"告警的行号（TB 136/146/180/191 → 168/178/212/223）——**只随 TB 插行位移**，内容不变。
2. `$finish … Line 444` → `Line 630` ——**同上（行号位移）**。
3. **hard 模式的模型侧数值行 2 条**：`hard STATS: exp {… 'pss': 19, 'nonmatch': 6 …}` → `{… 'pss': 20, 'nonmatch': 5 …}`；
   `hard: 96 lines …` → `hard: 97 lines …`（DUT 侧 `resp ['21','4','1','1','5','14','295']` **未变**）。
   ⚠️ 这是**§5.6 "逐字不变"表述的唯一不成立点**（见 §6-C 登记）：成因 = 设计 **§5.5 明文规定"必须"补的 `w6a` 保真度建模**
   （hard 模式语料里有一帧被新支从 nonmatch 归到 pass）；而"首分歧签名"（LINE 63）**未位移** ⇒
   按 §5.5 的处置规则（"若 hard 首分歧签名因此位移 ⇒ 响亮处理"）与 §5.3-5 的口径（"**不许**把 hard STATS/STATM/TCBF 的**数值行**当签名"），
   **本项按"预期内的数值行漂移"处理并登记**，未静默重钉、未改任何判据语义。

---

## 4 交付物④：`p3sim_sw` 复跑（既有门零扰动）

**RC=0**（与基线同）；**两臂 A/B + MUT + DROP 四臂判据全部逐字复现**：
`[PASS] FIXED arm: SNDWND ALL PASS …` / `[PASS] LEGACY arm: legA XFAIL-REPRODUCED + LEGACY OK …` /
`[PASS] MUTANT arm: LEGB1 red with accept witness …` / `[PASS] DROP arm: LEGA red with passd=0 …` /
`[PASS] hard-mode: known pre-existing divergence signature unchanged, LINE 63` /
`[PASS] arm-mismatch negative control …` / `SNDWND-GATE: PASS`。

**与基线 stdout 的逐字差异 = 恰好 3 行**（diff 精算）：
1. `MUTGEN OK src=… tcp_rx.v sha256=7517c949…` → `sha256=a35cd980…`（**基底源已被本刀修过**，预期）；
2. `MUTGEN OUT … mut_acckadv.v sha256=d2dd2098… changed_lines=[526, 536]` → `ab4ac42b… changed_lines=[533, 543]`
   （守卫两行随 +7 位移；变异语义不变）；
3. 我附加的 `RC=0` 行。
其余全同；`runA_fixed` 的 resp 三份 sha256 与基线**逐字相同**（7c95315f… / 7c95315f… / 2d96e7cc…）。

---

## 5 交付物⑤：等价 / 零扰动证据

1. **criterion-0（默认关守恒，§5.3-0 的机器证明）**：A-off 臂（TB **不带** `-d SEQRF_TAIL`；生成器 env 关）的
   `resp_tcp_rx.memh` / `resp_tcp_rx_stall.memh` / `resp_tcp_rx_hard.memh` 三份 sha256
   **== 冻结基线**（`7c95315f2f0761ca02a4a8c1c6845d030a5487434936ff9b23e14e33c36a7f80` ×2 / `2d96e7cc…`）✓；
   且 A-off 的模型检查（默认臂）RC=0 ✓。基线值 = 改动前用 `sim/p3sim` + `sim/p3sim_sw` 两个独立入口各跑一次取回，**两入口读数逐字相同**（顺带实测了 resp 的确定性）。
2. **生成器默认输出字节级**：新增代码 env 关时零作用 —— `stim_data.memh` / `cfg_tcb.memh` / `hardwin.memh` / `sw_legs.memh`
   与改动前基线 **`cmp` 逐字节相同**；`stim_dv.memh` / `stim_er.memh` 未单独留基线副本，但其正确性由**上下两端的字节级恒等**共同锁定
   （三模式 resp 逐字节相同 + 两门 stdout 逐字相同 —— 任一字节变化都会破坏这两条）。
3. **oracle 修复的逐位等价**：
   - `gen_stim_tcp_rx.py` 的臂化 oracle：**默认（fixed）路径**在既有全部语料上与旧式绝对比较**逐位同输出**——
     实测 = 改后模型对 nostall/stall 的期望行**逐字等于改动前**（§3 的 diff 只含 hard 的两条数值行，且那两条的成因是 `w6a` 建模而非 oracle 臂）；
     臂本身**有牙**由 env 负对照证明（去掉 legacy env ⇒ 同一 resp 立刻 MISMATCH）✓。
   - `gen_stim_tcp_chain.py` 的无臂 oracle：**链门 stdout 与基线逐字相同**（全量 diff 只多我附加的 `RC=1` 一行）+
     `resp_tcp_chain.memh` = `9359cce9…` **逐字节相同** ⇒ 该 oracle 的改动在链语料上逐位等价 ✓✓。
4. **M1 的"逐位等价实证"（§5.3 臂表要求）**：M1 与 A 的 resp 三份 `fc /b` **逐字节相同**（最强形式的等价证明，
   连仿真到仿真的确定性一起锁住）✓。
5. **非回归旁证（门内）**：A 臂三模式的 `SNDWND ALL PASS` + `P4b7 DIRECTED PASS` 保持 ⇒ 尾段的加入没有碰掉腿相位 ✓；
   W68ADV 的 `dut==tb` 双边等式在全部臂成立 ✓。

---

## 6 交付物⑥：异常与偏离（**全部登记；两处需裁定**）

### 6-A【设计与现读不符 #1｜需裁定】设计 §5.5 的 `wnd_l` 前提与代码不符

- 设计原文（v3r2 §5.5，§0a-5 的订正）："⛔ `wnd_l` 一律'不锁存'—— 镜像 RTL 的**取上帧陈值**语义
  （RTL 里 `wnd_l` **只在** `:724`（**w6-tlast 支**）与 `:764`（`acc_l` 支）被写；w6a 入口 `:766-771` 不写 ⇒
  `fend_pad` 拍 `wnd_ws` 取**上一帧值**）"。
- **现读（三重证据）**：`:724` 并不在 tlast 支内 —— 它是 `default:`（wcnt==6）accept 支里、`if (s_axis_tlast)` **之前**的
  **无条件**锁存（① 现读缩进/上下文；② `git blame` = `122b0c07` 把该行插在 tlast 判断之外；③ **本仓既有件
  `_proj_10g/notes/P7B_SNDWND_GUARD_DESIGN.md:83-89` 对同一行的读法与我一致**，其表逐字写
  "`fend_pay`/`fend_pad`（真实 60B 纯 ACK/带载荷帧）→ `wnd_l`（**本帧** w6 已锁存）✅"）。
  ⇒ **RTL 里 w6a 帧的 `fend_pad` 实际取的是"本帧"的窗**（非上帧陈值）。
- 处置（**不自行改设计**）：按设计**字面指令**实现 —— 模型的 w6a 支**不锁存 `wnd_l`**（§1.2-7），
  并在代码注释里如实写明现读勘误 + "仅当 w6a 帧窗 ≠ 上一帧 wnd_l 时与 RTL 分叉"。
- **影响面**：本门全部臂/模式**不可观测**（尾段 F2 的窗 == F3 的窗 == 0x4000 且 F2 是末帧 ⇒ 两条语义代数等价）；
  **未跑**"改用锁存"的对照臂（无必要 —— 等价是代数性的，且改动本身待裁定）。
- 连带登记：设计 §5.4 的 **W-a**（"F2 自己的窗字段根本不落线"）**机理句不成立**（结论"F2 的窗写在本激励下不可判"仍成立，
  但正确理由是"两帧窗同值"而非"不落线"）；设计 **D8**（"RTL 既存 quirk = w6a 入口不锁存"）**前提不成立**（无此 quirk）；
  W-a 里"不能用把 F2 的 wnd 改成不同值来加强"这句**被现读反证**（若改不同值，RTL 侧它**会**落线）。
- **修法（若裁定"锁存"）**：模型 w6a 支加 1 行 `wnd_l_n = (w[0] >> 48) & 0xFFFF`（镜像 `:724`）+ 同步注释；重跑本门 ≈1.5 min。

### 6-B【设计与现读不符 #2｜需裁定】G 臂的 "check legacy" 与臂表定义列表自相矛盾

- 设计 §5.3-4 要求 "G ⇒ `check legacy nostall,stall` **RC=0**"，而 G 行的 TB 定义 = `-d SEQRF_TAIL -d SEQRF_LEGACY`
  （**不含** `SNDWND_LEGACY`）。
- **实测（不是推断）**：CLI 臂参数控制的是 **SNDWND guard**（既有 CLI 自述"模型必须与 DUT **同臂同参**"），
  与 seq 臂（env `SEQRFC_ARM`）是**两个独立开关**。G 臂 DUT = frozen 文件 + TB 默认 `SNDWND_ARM=1` ⇒ guard=1；
  而 `check legacy` 的模型 = guard=0 ⇒ **TCBF 必红**（实跑：`nostall TCBF: exp …'1234' resp …'2000'`）。
  ⇒ 设计字面组合**跑不出它自己的判据 4**。
- **处置（最小改动、保设计主件逐字）**：保留 G 行**定义列表逐字不动**、保留"模型臂 = `SEQRFC_ARM=legacy`"（env，逐字），
  CLI 臂取**文档缺省 `fixed`**（= 与 DUT 同参；§5.3-4 的"legacy"落在 env —— 与设计自己的"模型臂"列一致）。
  实测：G 臂 `check fixed`（env legacy）⇒ **RC=0 且 hard LINE-63 签名逐字不变** ✓；且 G 行的全部期望读数（红点/终态）**逐项命中**。
- 备选（**未采用、也未实测**）：给 G 行加 `-d SNDWND_LEGACY`（⇒ DUT guard=0，`check legacy` 成立）。
  不采用理由：会给 A/G 对照引入**第二个变量**（guard 腿相位整体翻转），与"一次只动一个变量"冲突；
  但它是完全可行的等价方案，**裁定权在用户/TL**（若选它：G 臂重跑 + 判据行改 1 处 ≈2 min）。
- bat 头注已把此裁定连同证据写进 `NOTE-G`（不静默）。

### 6-C【预测不成立的登记】§5.6 的 `p3sim` "逐字不变"有两行例外（成因 = 设计自己要求必补的 `w6a` 建模）

详见 §3 的差异清单第 3 条。要点：**RC / 首分歧签名 / DUT 三 resp / nostall+stall 全部逐字不变**；
hard 的**模型侧**数值行按设计 §5.3-5 的既定口径（数值行不是签名、必变）处理，**未改判据、未重钉**。

### 6-D【施工面如实登记（都已当场修复，不入判据）】

1. **TB `mwcnt` 未初始化**（首跑 mwd 全 `x` ⇒ 5 条腿假红 + 聚合假 FAIL）：已加显式初始化并留防坑注释；
   修后读数与 §5.4 逐项吻合。（"instrument 的默认值也是仪器的一部分"。）
2. 门 bat 两个自伤：文件存在性循环**漏写扩展名**（假"missing"约 35 条）、生成器 banner 串与 bat grep 串不一致
   （`RF tail cfg2=` vs `RFSEQ rf_pos`）：均已修；**run1/run2 的失败是这两条造成的，run3（修正件）才是最终证据**。
3. `:356` 注释按 §3.6 代码块**整行替换** ⇒ 行尾 ` (快速重传/dup-ACK 依赖)` 随块消失（v2/v3/v3r2 三版设计给的都是同一块，
   我按"照抄"执行，未自行加回）；如视为遗漏，回加 = 1 处注释编辑。

### 6-E【登记但未做/未观测（如实）】

- **未跑 Vivado**（构建/定向 STA/`0x26` BID bump = 下一棒，按派单）；**未上板**（§7.2 注入实验不在本轮范围）；
- 设计 §4 的 W71 计数器分支**未搭**（D3 建议 = 不搭，本轮按"不搭"执行 ⇒ 零几何改动）；
- §5.2 的"路 A（全新 TB）"与 §5.3 备选臂（如 DROPA 式尾部段注入负对照）**未做**（设计未列入判据）；
- "M1 与 A 的逐位等价"证据 = resp 三份字节相同（**全流**）；未另做"逐周期波形比对"（非设计要求）。

---

## 7 交付物⑦之外：文件清单与可复算入口

**改动/新增件 sha256（终版；`sim/p3sim_rfc/logs/frozen_revision_sha256.txt` 同源）**：

```
a35cd9809d233ebd3bc08bee1df6faa3c1c68882578dfba4cfe20c1cbf6fbc02  rtl/tcp_rx.v                (A 值)
7517c94951598c7e42d11ba7d8e62164acc762cbbd8718356e4f8bf3bc6d1489  sim/p3sim_rfc/frozen/tcp_rx_prefix.v (G 值)
99cf45a8e5978bc79b36df3c9dbf924b8c8dce6a7263eeef6503dd1f7d67add7  tb/tb_tcp_rx.v
a0551b3e84e505b3dddb7ba3d52ae4eb0be2b582302e41273deaf54ef14e1bee  tools/gen_stim_tcp_rx.py
26109ac5f5113df3924443e9f0b17ebfc92f5e4e121615197467fb8a268c698b  tools/gen_stim_tcp_chain.py
5d5f72a5563d8bdeb9107b52a44799f75c9a6f36d058dde08b555a120461aed6  sim/p3sim_rfc/run_rfcseq_gate.bat
f3a703e3ffe18432b8cf459e98688cd4d43d62fdbac593f74ec789e3c93cdfd5  sim/p3sim_rfc/mut/mk_mut_rfc.py
776a57effebe4cc2788c953716e0936e3b881c5bac4520955ee2746c146eaf5d  .gitignore
```
git blob：A 修订 = `a73b0be6ca32165f61fcc32b9ca4405b68d4d625`（旧 `c8c7113b…`）；G 修订 = `c8c7113b…`（= 旧 HEAD 文件逐字节）。

**复算入口**（均自定位，自仓根调用）：
```
cmd //c 'sim\p3sim_rfc\run_rfcseq_gate.bat'   # 新门 7 臂（终版 PASS；logs/gate_stdout.txt 为 run3 归档）
cmd //c 'sim\p3sim\run_tb_tcp_rx.bat'         # 既有红复现（RC=1 + LINE 63）
cmd //c 'sim\p3sim\run_tb_tcp_chain.bat'      # 链门（RC=1；stdout 应与基线逐字同）
cmd //c 'sim\p3sim_sw\run_sndwnd_gate.bat'    # 既有门零扰动（RC=0）
```

**轮内证据目录**：`_proj_10g/notes/p9_impl_rfc_20261015/`
（`baseline/` = 改动前冻结（p3sim/p3sim_sw/chain 三处 stdout + resp/memh 副本）；`genchk/` = 生成器/模型 A/B 与逐字节比对；
`logs/` = run1/run2/run3、post 三门复跑、mutgen、A/B 读数；`apply_rtl_edit.py` = 逐字提取式 RTL 编辑脚本（含全断言））。

**下一棒（构建轮）须带走的接口事实**：A 值 sha256 = `a35cd980…`（`board/wrapper_p4.v` 的 BID bump 与定向 STA 按设计 §7.1 执行；
本刀 RTL 改动 = 1 行表达式 + 注释，端口面/几何零改动）。

---

# 补记（TL 修正轮裁定，2026-10-15）—— 三处小修 + 重跑 + 设计 errata 清单

> 裁定引用（TL 逐字要点）：① **§6-A = "锁存"**（门模型必须镜像 DUT；依据 = 亲读 `rtl/tcp_rx.v` 的
> `wnd_l <= s_axis_tdata[63:48];` **无条件位于 `default:`（wcnt==6）支内、`if (s_axis_tlast)` 之前**）
> ⇒ 模型 w6a 支**加锁存**（1 行）+ 注释改现读勘误版（带 `:731` 证据）；**设计侧 errata 列给 TL**。
> ② **§6-B = 维持已实施形态**（G 行定义逐字不动；CLI 默认 `fixed` = 与 DUT 同参；seq 臂走 env `legacy`；
> 备选（加 `-d SNDWND_LEGACY`）**登记不采用**（双变量））。③ **§6-D-3 = 回加注释尾**。

## R1 执行清单与三处 diff（含看守哈希同步）

| # | 文件 | 改动 | sha256 变化 |
|---|---|---|---|
| 1 | `rtl/tcp_rx.v` | `:363` 注释**行尾回加** ` (快速重传/dup-ACK 依赖)`（裁定③；纯注释） | `a35cd980…` → **`793761589de8089325c9f2f94986a696e1b198b978bfef341f370d0975a2b9f1`**（blob `a73b0be6…` → `d42da2c8…`） |
| 2 | `tools/gen_stim_tcp_rx.py` | 模型 w6a 支**加锁存** `wnd_l_n = (w[0] >> 48) & 0xFFFF`（1 行，取本帧窗）+ 注释整块改写为现读勘误版（引 `:731`/`:732` + `git blame 122b0c07` + `P7B_SNDWND_GUARD_DESIGN.md:83-89` 旁证 + errata 指针） | `a0551b3e…` → **`cbad26a5da16ff3a6a751840c05a385d3496ce13837f09a86bcd47426634a3d0`** |
| 3 | `sim/p3sim_rfc/run_rfcseq_gate.bat` | **哈希守卫同步**：`A_SHA` → 新 rtl sha（裁定②的"同步门内哈希守卫"） | `5d5f72a5…` → **`37d76b6d097706df3b87502a2ab2ea7acce35823db28da4746df711630607aad`** |
| 4 | `sim/p3sim_rfc/logs/frozen_revision_sha256.txt` | 重新生成（rev2；含三处变更说明 + 新 A_SHA/blob） | — |

**未动**（逐字）：`frozen/tcp_rx_prefix.v`（G 值 `7517c949…` 不变）· `tb/tb_tcp_rx.v`（`99cf45a8…`）·
`tools/gen_stim_tcp_chain.py`（`26109ac5…`）· `mut/mk_mut_rfc.py`（`f3a703e3…`）· `.gitignore`（`776a57ef…`）。CRLF/行数核过（rtl 936 行纯 CRLF 不变）。
**⛔ 未跑 Vivado**（遵派单）。

## R2 重跑读数（run4；原件 `logs/gate_run4.txt` sha256 `7322808c…`，已归档为 `sim/p3sim_rfc/logs/gate_stdout.txt`）

**`RFCSEQ-GATE: PASS`（RC=0，0 条 `[FAIL]`）。**
**run3 ↔ run4 的 stdout 全量 diff = 恰好 9 行，且全部是哈希打印行**：
① A 源顶层守卫 + A/AO 臂内守卫（3 行，sha 换新）；② mutgen 基底源 sha（1 行）；③ 4 个 mutant 的生成 sha（4 行，**`changed_lines=[327]` / `[327,370] ins=1` 结构逐字不变**）。
⇒ **全部判据行与全部逐臂读数（SUMMARY / 7 臂 RC / A·G 逐帧增量 / 守恒 / 终态 / W68ADV / M1≡A / M2-M4 红点集 /
env 负对照 / hard LINE-63 签名）+ key-readings 段 = 与 run3 逐字节相同** ✓（裁定预期的"读数逐字节不变"成立）。

**resp 字节恒等**（修正轮不改激励、不改 DUT 行为）：
- **A-off 直接比对**：`resp_tcp_rx.memh`（+stall/hard）sha256 == 冻结常量 `7c95315f…`/`7c95315f…`/`2d96e7cc…` ✓（门内哈希守卫二次命中）；
- **A vs M1**：run4 内 `fc /b` 三份**全同**（同 sha `1ccf62ed…`）✓；
- **跨轮**：run3 的工作目录 resp 已被 run4 覆盖（同路径），跨轮字节恒等由三重夹逼锁定 ——（i）DUT 行为不变（纯注释）、
  （ii）激励不变（默认路径 4 份 memh `cmp` 逐字节 + 尾段 `rf_pos` 打印逐字）、（iii）TB 不变（sha）⇒ resp 输入面全同；
  且 resp 被模型检查**全行比对**钉住、模型输出不变（尾段模型 dump：A/G 的 stats/终态 TCBF 与修正前逐字相同）⇒ 输出面亦全同。
- **p3sim 补跑（裁定允许，已跑）**：`POST2_p3_tcp_rx_stdout.txt` 与修正前 `POST_p3_tcp_rx_stdout.txt` **全量 diff-RC=0（逐字相同）**：
  RC=1、`hard LINE 63` 签名逐字不变、hard 模型数值行（pss 20 / 97 lines）**未再变化**、resp 三份 sha 与冻结基线逐字相同
  ⇒ **修正轮对 p3sim 零扰动** ✓（也顺带证明本次 wnd_l 锁存的改动在该门同样不可观测）。

## R3 设计 errata 清单（交 TL；供 v3r4 文档轮 + kimi 复审）

- **E-1（v3r2 §5.5 低-1 行的前提｜错）**："RTL 里 `wnd_l` 只在 `:724`（**w6-tlast 支**）与 `:764`（`acc_l` 支）被写" —— 现读（本刀 +7 位移后 = `:731`/`:771`）：
  `:731` 的 `wnd_l <= s_axis_tdata[63:48];` **无条件**位于 `default:`（wcnt==6）accept 支内、`if (s_axis_tlast)`（`:732`）之前
  （`git blame` = `122b0c07` 即插在 tlast 判断之外；旁证 = `P7B_SNDWND_GUARD_DESIGN.md:83-89` 的 `fend_pad` 行）
  ⇒ 结论"w6a 入口不锁存 ⇒ `fend_pad` 取上帧陈值"**不成立**；正确语义 = w6a 帧的 `fend_pad` 取**本帧**窗（模型应**锁存**；已按裁定修正）。
- **E-2（v3r2 §5.4 W-a 的机理句｜错）**："RTL 的 w6a 入口（`:766-771`）不锁存 `wnd_l` ⇒ `fend_pad` 取到的是上一帧（F3）的陈值，F2 自己的窗字段**根本不落线**" —— 机理句不成立（F2 的窗**会**落线）。
  W-a 的**结论**（F2 的窗写在本激励不可判）仍成立，但正确理由 = **F2.wnd == F3.wnd == 0x4000（同值不可分辨）**；
  其 ⛔"不能把 F2 的 wnd 改成不同值来加强"**应删/反转**（改不同值即可获得判别力）。
- **E-3（v3r2 §9 D8｜前提错）**："低-1 的 RTL 既存 quirk（w6a 入口不锁存 `wnd_l` ⇒ `fend_pad` 写上一帧的窗）是否立项修" ——
  该 quirk **不存在**（RTL 对每帧在 `:731` 无条件锁存）⇒ D8 应整条撤销（无立项对象）。
- **E-4（v3r2 §5.3-4 的 "G ⇒ `check legacy nostall,stall` RC=0"｜措辞错）**：CLI 臂参数控制 **SNDWND guard**（与 seq 臂 env 是两个独立开关）；
  G 行定义（`-d SEQRF_TAIL -d SEQRF_LEGACY`，无 `SNDWND_LEGACY`）下 DUT guard=1 ⇒ 字面组合的模型 guard=0 **必 TCBF 红**
  （本轮实跑复现：`nostall TCBF: exp …'1234' resp …'2000'`）⇒ 正确形态（TL 已裁定、已实施）= seq 臂走 env `SEQRFC_ARM=legacy`、CLI 臂保持 `fixed`。
- **E-5（v3r2 §5.6 "逐字不变"的措辞｜过强）**：对 p3sim 门，精确边界 = **RC / 首分歧签名 / DUT 侧 resp / nostall+stall 读数**；
  **hard 模式的模型侧数值行会变**（成因 = §5.5 明文必须补的 w6a 建模）——口径应引 §5.3-5 的"数值行不是签名"。
- （沿革注）E-1..E-3 的前提在 **v2** 的 §5.5/§0a-5 就已存在（v3 的"订正"把 v2 的另一种写法换成了这一种错前提）；v3r4 建议在 §0b 变更清单点明。

## R4 补记后的终版哈希（rev2）

```
793761589de8089325c9f2f94986a696e1b198b978bfef341f370d0975a2b9f1  rtl/tcp_rx.v            (A 值 rev2; blob d42da2c8…)
7517c94951598c7e42d11ba7d8e62164acc762cbbd8718356e4f8bf3bc6d1489  sim/p3sim_rfc/frozen/tcp_rx_prefix.v (G 值, 未动)
99cf45a8e5978bc79b36df3c9dbf924b8c8dce6a7263eeef6503dd1f7d67add7  tb/tb_tcp_rx.v          (未动)
cbad26a5da16ff3a6a751840c05a385d3496ce13837f09a86bcd47426634a3d0  tools/gen_stim_tcp_rx.py (rev2: 模型锁存)
26109ac5f5113df3924443e9f0b17ebfc92f5e4e121615197467fb8a268c698b  tools/gen_stim_tcp_chain.py (未动)
37d76b6d097706df3b87502a2ab2ea7acce35823db28da4746df711630607aad  sim/p3sim_rfc/run_rfcseq_gate.bat (rev2: A_SHA 同步)
f3a703e3ffe18432b8cf459e98688cd4d43d62fdbac593f74ec789e3c93cdfd5  sim/p3sim_rfc/mut/mk_mut_rfc.py (未动)
776a57effebe4cc2788c953716e0936e3b881c5bac4520955ee2746c146eaf5d  .gitignore              (未动)
```
（同源件 = `sim/p3sim_rfc/logs/frozen_revision_sha256.txt`，已按 rev2 重生成。）
