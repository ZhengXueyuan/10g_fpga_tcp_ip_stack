# A 捆（URAM 板内缓冲）—— 独立验证报告（Claude 组 · 验证 A 捆）

**日期**：2026-10-13 · **工作树**：`D:\repo\XCKU5PMini\udp_hls_10g`（HEAD = `3e8f5cb`；被审件 = `ed69d33` 的 A 捆）
**被验证件**：`_proj_10g/notes/p9_xreview_kimi_20261013/BUNDLE_A_URAM.md`（kimi，2026-10-13 22:00）+ 其负对照
`negctl_occ_model.py` / `negctl_occ_model.out`
**对照基线（现读）**：`rtl/mir_uram_fifo.v`(275) · `sim/p9_uram/{tb_mir_uram_fifo.v, mut_uram.py, run_tb_mir_uram_fifo.bat}` ·
`_proj_10g/notes/p9_uram_20261013/{REPORT,REVIEW,FIX_REPORT}.md` · `_proj_pcie/p7b_biz/p7b_mir_dump.cpp`(2364) ·
`rtl/axis_c2h_stream.v` · `rtl/app_rx_mirror.v` · `board/wrapper_p4.v` 接线现读 · `_proj_10g/notes/p9_build_0x24/`（0x24 轮归档）
**方法**：**只读 + 独立复现**。⛔ 未跑 Vivado/xsim/任何门；⛔ 未复跑 kimi 的脚本当验证；⛔ 未改任何既有文件。
逐条用自己的手段：现读 RTL/TB/文档 + 自写逐拍模型（`ax_occ_reach_model.py`：**缩比几何状态空间穷举 BFS** +
现役几何逐拍模型 + 1M 拍反证扫描 + 8 种子对账）+ 逐状态手工推演 + 文件系统/git 时间线取证。
**本件性质**：只列验证结论与证据；**不下 PASS/FAIL 裁定**；"未观测到"≠"不存在"。

---

## §0 一页结论（逐条）

| 编号 | kimi 级别 | 我的结论 | 一句话证据 | 修复归口 |
|---|---|---|---|---|
| **A-K1** 占用上界 4099 vs 真值 4100 | P1 | **属实** | 我方 BFS 穷举（缩比几何）max = DEPTH+CAP 恰上界；AW=12 模型 max=4100@cyc4100；1M 拍反证扫描未破；四处写 4099 / 两处写 4100 / TB 门 [4096,4100] 逐条现读 | 文档/RTL 注释级（P2） |
| **A-K2** 式 B 中途上界 32824 vs 默认 24 | P1 | **属实**（附 2 点精化） | 现读工具 :66-70/:96/:157 + 身份式守恒推导（`K−taken−ΔW70 = 镜像残余 + O`）+ 工具 :2279-2287 判红路径；"工具一行未改" git 现核 | 工具+协议级（P1/P2） |
| **A-K3** 计数点口径权威注释陈旧 | P2 | **属实**（陈旧面比 kimi 列的更大） | `axis_c2h_stream.v:92-95/:7` + 工具 `:61-63` 现读；wrapper `:3892-3894` 接线现读；另有 `:6/:122` 与工具 `:496/:498/:593` 同款 | 注释级（P2） |
| **A-K4** p6e 两个突变门未重跑 | P2 | **⛔ 不属实（被 0x24 轮证据推翻）** | TB 07:53:17 被改后，两门 07:54/07:56/08:25 **重跑**且归档 `MUTANT-CAUGHT-as-expected`；绑定哈希 `INPUT_HASHES_*_GATES.txt:101` 记同 TB；提交 `09e34a6` 明文记录 | 撤案 + 一行回写（P3） |
| **A-K5** 缺突变臂（≥2 类） | P2 | **属实** | `mut_uram.py` 12 臂全表逐臂核：无任何臂动 64 位数据通路 / clr 分支内部行；缺臂后果我方独立推演成立（"有牙"= 未证预期） | 门内补臂（P2） |
| **A-K6** G4/G8 固定种子单序列 | P2 | **属实** | TB `:96-97` 写死种子、无 `$random`/无种子参数；我方自写 8 种子 + 1M 拍扫描 0 错（同向复现"未兑现"判断） | 低优先登记（P3） |
| **A-K7** `SIM_ASSERT_CHK(0)` 登记 | P2 | **部分属实** | 登记缺口属实（RTL `:205` 无注释；REVIEW F6② / FIX §7-1 现读）；**但其"关掉（默认 1）"不属实——XPM v2025.2 现读默认 = 0，该显式值 = 照抄默认、什么都没关** | 注释级（P3） |
| **I1** 三处 `!clr` 冗余防御 | 信息 | **属实** | 三处逐处推演独立复现（clr 分支优先 / v_sr 清零使隐形读不采集 / 上游 gnt 蕴含 req）；另附同族观察 `pop` 无 `rst_n`（kimi 未列） | 头注释注明（P3） |
| **C 捆** 0x24 构建面"无发现" | — | **三项可核且复算吻合；覆盖面有 1 缝 + 1 未列面** | 逐项自复算（tcl / mut_bwire 锚 / BID）；缝 = "门读数"格在两捆里无人正确覆盖（K4 即其产物） | 描述性结论（见 §9） |

**计数**：属实 **6**（K1/K2/K3/K5/K6/I1）· 部分属实 **1**（K7）· 不属实 **1**（K4）。
**与 kimi 相左**：**K4（整体不实）**、**K7 的"默认 1/关掉"子句（不实）**；另有两处数字/引用级精化（K1 的 4099 陈旧面为 4 处非 3 处；K2 的真·中途上界还须加镜像 FIFO 项）。

---

## §1 A-K1（P1）占用上界 "4099 字" 错误 —— **属实**

### kimi 的发现（引原文）
真实上界 = **4100 字 / 32800 B**（`occ=4096 ∧ inv=4` 可同时取到）；`rtl/mir_uram_fifo.v:267`、`REPORT.md:102`、`:120`
写 4099；`REPORT.md:89` 写 "4096 + inv(≤4)"（=4100）；TB G2b `:217` 允许 `[4096, 4100]`（门比文档宽 1）。

### 我的独立方法
1. **守恒恒等式（自推）**：把"取走未弹走"定义为寄存器账 `O = occ + inv`（`inv = o_occ + inflight`）。
   逐拍递推：`occ' = occ + u_wr − issue`、`inv' = inv − pop + issue`（由 `inflight' = inflight − arr_v + issue`、
   `o_occ' = o_occ + arr_v − pop` 相加得）⇒ `O' = O + u_wr − pop` ⇒ `O ≡ 取走事件数 − 弹出事件数`（窗口起算）。
2. **两分量上界（自推）**：`occ ≤ DEPTH`（写门 `!ufull` 只在 `occ<2^AW` 放行）；`inv ≤ CAP`（归纳：`issue ⟹ inv−pop < CAP`
   ⇒ `inv' = inv−pop+issue ≤ CAP`；`pop=1 ⟹ o_occ≥1 ⟹ inv≥1` 无下溢反例）⇒ **O ≤ DEPTH + CAP = 4100**。
3. **穷举可达性（BFS，缩比几何 AW=4/OQ=4，转移方程与现役逐条同构）**：对**全部输入序列**枚举可达状态
   —— 上界是"证"出来的，不是"跑"出来的。同时检查 `occ=DEPTH ∧ inv=CAP` 的**联合可达性**。
4. **现役几何逐拍模型 + 反证扫描**：对抗序列（`dn_req≡0` 长停、源常就绪）找上界；五类波形 × 5 seed × 4 万拍
   （共 100 万拍）试图击破 `O ≤ 4100`。
5. **门读数佐证**：读 kimi 未引的门日志本体（`REPORT.md:129` 的 `[DBG] G2` 行）与 `REVIEW.md:141` 的复算。

### 原始证据
现读三处 + 两处（行号逐条核过）：
```
rtl/mir_uram_fifo.v:267   …上界 4099 字 (= 32.8 KB)…
REPORT.md:102             …缓冲占用（≤4099 字 = 32.8 KB）…
REPORT.md:120             …O ≤ 4099 字 = 32.8 KB ⇒ --resid-max-mirror 默认 24 只对终态成立…
REPORT.md:89              …在囊 = 4096 + inv(≤4)…                      ← 文档内部自相矛盾（= 4100）
tb_mir_uram_fifo.v:217    chk_range("G2b taken in [DEPTH, DEPTH+OQ]", …) ← [4096, 4100]
```
（⭐ 我另核出**第 4 处 4099**：`REVIEW.md:137` "O = 缓冲占用 ≤ 4099 字 ≈ 32.8 KB" —— kimi 未列，同一漂移面。
同时 `REVIEW.md:127` 写 "≤ 4100 字"、`REVIEW.md:141` 复算 "模块内容 = occ+inv = 4100" ⇒ 4099/4100 在同一审查件内也互斥。）

我的模型输出（原件 = 本目录 `ax_occ_reach_model.out`，命令 `PYTHONIOENCODING=utf-8 python ax_occ_reach_model.py`）：
```
A. 穷举可达性 BFS (缩比几何 AW=4 => DEPTH=16, OQ=CAP=4) -- 对全部输入序列枚举
  可达状态数 = 5504 ; 穷举可达 max(occ+inv) = 20 ; DEPTH+CAP = 20
  [PASS] BFS: 穷举可达 max(occ+inv) == DEPTH+CAP == 20 (实测 20)
  [PASS] BFS: 全部可达状态/输入满足 inv<=CAP 且 occ<=DEPTH (违例 0 条)
  可达状态中 'occ==16 且 inv==4' 个数 = 128          ← 联合取满"构造性可达"（不是空判据）
B1. 现役几何 AW=12 对抗序列 (en=1, clr=0, dn_req=0, 源常就绪, 6000 拍)
  max(occ+inv) = 4100 @cyc4100 ; 分解 (occ,o_occ,inflight) = (4096, 4, 0)
B2. 反证扫描: 五类波形 x 5 seed (每类 20 万拍) 试图击破 occ+inv <= 4100
  rand  : 4100 / burst : 4100 / gate : 4100 / clrinj : 996 / rstinj : 3000   ← 连"非特意对抗"波形也取到 4100
```
**门读数佐证（现读原件）**：`REPORT.md:129` 的 G2 白盒行 = `occ=4096 inv=4 taken=4099` ——
即**运行中的设计已实际进入 (occ=4096 ∧ inv=4) 状态**；`taken=4099` 是 TB 窗口计数（窗口起点 `p0=1`，
`REVIEW.md:141` 已复算 `taken − popped + p0 = 4099 − 0 + 1 = 4100`），不是模块内容 —— 数字自洽。
kimi 的 `4100` 与"4099 是低估（乐观方向）"均与我方独立结论一致。

### 结论
**属实**。真实上界 = **4100 字 = 32800 B**（且非奇异形态：普通突发/随机波形即达）。三处（实为四处）"4099"是
**低估 1 字（8 B）**；TB G2b 的 `[4096,4100]` 与真实上界一致 ⇒ **门没错、文档错**。未造成现判据漏洞——
`P9B3_ELASTIC_MAX_BYTES = 35840` 的逐项预算（FIX_REPORT 现读：2048+32768+32+32+24 = 34904）用的是 **4096**（×8），
不含这 1 字。

### 建议修复（范围/优先级）
- **P2（纯文档/注释）**：四处统一改 **4100 字 = 32800 B**：`rtl/mir_uram_fifo.v:267`、`REPORT.md:102`、`:120`、
  `REVIEW.md:137`；并把 `REPORT.md:89` 与 `:102/:120` 合成一句口径（"在囊 = occ(≤4096) + inv(≤CAP) ≤ 4100 字"）。
  ⛔ 不动 RTL 逻辑、不动 TB 判据（门允许域本就正确）。
- ⚠️ 顺手项（同族、见 §10）：`REPORT.md:89` 的 `up_req = en && !clr && occ<4096` 是**F2 修复前的旧公式**（缺 `rst_n`）。

---

## §2 A-K2（P1）式 B 中途上界 = 32824 B vs 工具默认 24 —— **属实（附 2 点精化）**

### kimi 的发现（引原文）
缓冲引入后式 B 中途真上界 = `镜像残余(≤24 B) + O(≤32800 B) = 32824 B`，工具 `--resid-max-mirror` 默认 24
差 ~1367× ⇒ 中途/停排空评估必假红；REPORT §3 已登记但**工具一行未改**。

### 我的独立方法
1. **守恒推导（自推，从两处 RTL 账目合出）**：镜像字节账（`app_rx_mirror.v:38` 现读
   `offered == 8×(写入字数) + drop_bytes + (acc_cnt_r + stg_cnt)`）+ 计数点现读（`MIR_DMA_CNT` 在成形器 aux 口计
   `dma_gnt`，而该口现由 `u_mir_buf.dn_*` 驱动——wrapper `:3892-3894`）⇒
   **`K − taken − ΔW70 = (acc_cnt_r + stg_cnt) + FIFO残留×8 + (occ+inv)×8`**，
   即 `= 镜像残余 + 缓冲占用 O`。`level==0` 只清掉 FIFO 项，**不清 O**（O 的可见口 `dbg_occ/dbg_oocc` 现为空接）。
2. **工具行为现读**：默认值/帮助/注释/判红路径逐处读（见下）。
3. **数字复算**：`32824/24 = 1367.67` ⇒ kimi"~1367×"的算术核过。
4. **"工具一行未改"的现核**：`git log -- _proj_pcie/p7b_biz/p7b_mir_dump.cpp`（最近 4 提交 = 宿主读轮/P9 工具轮，
   无任何 URAM 缓冲相关更新）+ 现读全文无"缓冲/URAM/O"限定注记。

### 原始证据
```
_proj_pcie/p7b_biz/p7b_mir_dump.cpp:66-70  式 A/式 B 定义："…式 B … == 镜像残余 ∈ [0, --resid-max-mirror]（默认 24 B
                                          = rtl/app_rx_mirror.v 头注释 acc_cnt_r + stg_cnt）"
                                  :96      帮助文本 "[--resid-max-mirror 24] [--resid-max-shaper 32]"（无"仅终态有效"限定）
                                  :157     RESID_MAX_MIRROR_DEF = 24
                                  :61-63   taken_bytes = ΔMIR_DMA_CNT×4 = "从镜像取走"的字节数（陈旧，见 K3）
                                  :496/:498/:593  身份式描述同款（"K = 取走 + drop + 镜像残余"）—— 无 +O 项
                                  :753-754 r.closed_b = idB_eval(r.k, r.taken, r.drop, …)
                                  :2279-2287  if (!sr.closed_b) { FAIL …; fail=1; }     ← 判红路径
                                  :2288-2298  premise(level==0) 失败也 rc=1（strict），--no-strict-quiesce 才放行
```
镜像残余口径现读：`app_rx_mirror.v:37-38`（`acc_cnt_r + stg_cnt` ≤ 24 B）；`app_rx_mirror.v:359`
（`fifo_async #(.WIDTH(64), .DEPTH(256))` = 2 KB —— 非静默时残余的另一项）。
登记现读：`REPORT.md:119-120`（"中途差额可到 O ≤ 4099 字 = 32.8 KB ⇒ 默认 24 只对终态成立"+三条建议）；
`REVIEW.md:137`（补"`en=0` 停排空时缓冲残留保留到 `en` 回来"）。

### 结论
**属实**。式 B 在**任何** `O > 24 B` 的评估点必判红（`closed_b=false, rc=1`），而
**premise（`level==0`）不排除 `O > 0`**（它只管镜像 FIFO/stash）——"停流静置 + 宿主停止读 + 镜像已排空"就是
一个"premise 已获见证但 式 B 仍假红"的形态（错误信息还会指向"镜像残余越界/K 口径不对"，误导归因）。
两点精化（不改结论方向）：
- ① kimi 的 **32824 对应"镜像已静默（`level==0`）但缓冲未排空"态**；真·中途（镜像也存水）时镜像残余还要加
  FIFO ≤ 2048 B ⇒ 严格上界 **≤ 32800 + 2048 + 24 = 34872 B**（算术，非实测）。
- ② 现行协议（"停源 → 排空到 early-stop"）在**排空完成**时 `O=0` ⇒ 式 B 逐字成立——REPORT §3 建议①已覆盖；
  假红面 = 非整齐收尾（watchdog 截断 / 宿主提前停读 / `en=0` 停排空态评估）。

### 建议修复（范围/优先级）
- **P1（工具轮，最高优先；零 RTL 改动）**：① 默认按容量具名常量重算（`4096×8 + OQ×8 + 24` 一档）**或**
  ② 至少把 `:96` 帮助 + `:66-70` 注释 + `:61-63` 口径写明"默认 24 仅在'停源 + 排空到 early-stop'的终态有效"，
  中途/停排空评估必须显式放宽（并打出所用上界）。③ 更强（可选、另轮）：缓冲占用观测口（会改快照几何 71 字/0x14C，
  ⛔ 不在本刀）。
- **P2（协议）**：板级收尾协议保持"停源 → 排空到 early-stop"，并在读数模板里并列打印 `MIR_STREAM_QUIESCE`
  与两条式（REVIEW F9 已同向建议）。

---

## §3 A-K3（P2）计数点口径权威注释陈旧 —— **属实（陈旧面更大）**

### kimi 的发现（引原文）
`rtl/axis_c2h_stream.v:92-95`（"计数点 = 上游 aux 口 —— 数**从镜像 aux 口取走**的 32 位字数"）与 `:7`
（"`dma_req`（本模块→镜像…）"）**在 P9 后失效**（`dma_gnt` 现来自 `u_mir_buf.dn_gnt`）；工具同口径在
`p7b_mir_dump.cpp:61-62`。语义位移只在 `mir_uram_fifo.v:266-270` 与 `REPORT.md:102` 登记 ⇒ 权威源注释未更新。

### 我的独立方法
现读三处被点名的注释原文 + wrapper 接线（`:3818-3834` u_mir.aux ↔ `mir_uf_*`；`:3855-3866` u_mir_buf 例化；
`:3892-3894` u_mir_axis.dma_* ← `mir_dma_*` = u_mir_buf.dn_*）；再 `grep` 同一文件找同款漂移面。

### 原始证据
```
rtl/axis_c2h_stream.v:7    //        `dma_req`(本模块→镜像, 电平) / `dma_gnt`(镜像→本模块, 同拍握手)
rtl/axis_c2h_stream.v:93   //   **计数点 = 上游 aux 口** —— 数**从镜像 aux 口取走 (`dma_gnt`) 的 32 位字数**
p7b_mir_dump.cpp:61-63     //        taken_bytes    = Δ`MIR_DMA_CNT` × 4 = **从镜像取走**的字节数 …
board/wrapper_p4.v:3892    .dma_req        (mir_dma_req),   // → u_mir_buf (无容量不拉 ⇒ 缓冲满 ⇒ W70 记账)
board/wrapper_p4.v:3893    .dma_gnt        (mir_dma_gnt),   // ← u_mir_buf (1 拍 = 8 B = 2 个逻辑字)
board/wrapper_p4.v:3894    .dma_data       (mir_dma_data),  // ← 64 位 = {后出, 先出} (缓冲 FWFT 头字)
```
同款漂移（我另核出，kimi 未列）：`axis_c2h_stream.v:6`（"⛔ **上游合同一字不改** —— 吃 `app_rx_mirror` 的 aux 读口"）、
`:122`（模块内端口注释"上游: app_rx_mirror 的 aux 读口"）；工具 `:496/:498/:593`（身份式描述）。已登记面现读：
`mir_uram_fifo.v:266-270`（"成形器数的是'从本缓冲取走的字数'"）与 `REPORT.md:102` ✓。

### 结论
**属实**（P9 后成形器的 `dma_gnt` 来自 `u_mir_buf`，"从镜像 aux 口取走"这句已失效；权威源注释未同步）。
陈旧面比 kimi 列的大：**至少 6 处**（2 处 kimi 已点 + `:6` + `:122` + 工具 `:496/:498/:593` 族）。

### 建议修复（范围/优先级）
- **P2（注释级，零逻辑改动）**：上述各点统一改"从**上游 aux 口**取走（P9 板内缓冲轮之前 = 镜像；
  之后 = `u_mir_buf`）"，并指向 `mir_uram_fifo.v` 口径登记段；工具的 `:496/:498/:593` 顺手补 "+ O（缓冲占用）"。
- 与 K2 的工具轮同批做（同一文件、同一根因）。

---

## §4 A-K4（P2）"p6e 两个突变门未随 TB 功能改动重跑" —— **⛔ 不属实（被 0x24 轮证据推翻）**

### kimi 的发现（引原文）
"p6e 两个突变门未随 TB 功能改动重跑（编辑后 TB 的'仍被抓红'无证据）"；依据 = `FIX_REPORT.md:313`（§7-4）
自登"未重跑 ⇒ 'TB 改动是否影响这两门'未核"；并现读 `run_tb_p6e_pcie_mut.bat:12-15`（突变对象 = wrapper 本体
+ 同一被改 TB 进编译闭包）。

### 我的独立方法
**时间线取证**（文件 mtime + git blob/hash + 归档件 + 提交 message 四方交叉）：
1. FIX 轮跑窗与**当时**的 TB 版本（对 `git show f46a221:… | sha256sum` 复算，验证 FIX_REPORT 引的哈希）；
2. TB 的**最后一次编辑时刻**与**内容**（mtime + `git diff f46a221..HEAD` 非注释行 + 现文件 sha）；
3. 两个突变门**最后一次编译/运行时刻**（编译日志/xsim 日志 mtime；门每次都重编、编译的是文件系统现值）；
4. 0x24 轮归档里的**stdout 判决行**与**跑前/跑后输入哈希**；
5. 同一 TB 上**真实臂**的读数（突变臂的红必须能与真实臂对照）。

### 原始证据
**(a) FIX 轮（f46a221）编译的是旧 TB — 复算**：
```
$ git show f46a221:sim/p6e_pcie/tb_p6e_pcie_wrapper.v | sha256sum
322e06cc857c7a5ff5fa8ee36a5745a69c841a95dadfe7a69444e10d9411c1d9   ← 与 FIX_REPORT §4 引的 322e06cc… 逐字相符
```
**(b) TB 在 FIX_REPORT 落盘（07:46）之后又被改 — 07:53:17**：
```
$ ls --time-style=full-iso sim/p6e_pcie/tb_p6e_pcie_wrapper.v sim/p6e_pcie/tb_p6e_pcie_counters.v
… 2026-10-13 07:53:17.359623900 … tb_p6e_pcie_counters.v
… 2026-10-13 07:53:17.359623900 … tb_p6e_pcie_wrapper.v      ← 两 TB 同 mtime（同一次批量编辑 = 0x24 BID 同步）
$ git diff f46a221..HEAD -- sim/p6e_pcie/tb_p6e_pcie_wrapper.v | grep -E "^[+-]" | grep -vE "^\+\+\+|---" | wc -l
2        ← 非注释行恰 2 = 两条 BID 期望 0x23→0x24（commit 09e34a6 明文）
$ git show HEAD:sim/p6e_pcie/tb_p6e_pcie_wrapper.v | sha256sum
19fbf93695b2d7761b2621881e09c0911cf378842d3d37c13bd3799e070b70df   ← = 现行文件 sha（git status 干净）
```
**(c) 两个突变门在 TB 改动之后全部重跑（0x24 轮）**：
```
sim/p6e_pcie/dir_mut/xvlog_mut.log   2026-10-13 08:24:43  （编译）
sim/p6e_pcie/dir_mut/xsim_mut.log    2026-10-13 08:25:22   FAIL 54 项
sim/p6e_pcie/dir_mut2/xsim_mut2.log  2026-10-13 07:56:29   FAIL 11 项
sim/p6e_pcie/xsim_p6e.log            2026-10-13 08:26:04   PASS_ALL（真实臂，同一 TB）
_proj_10g/notes/p9_build_0x24/gate_mut.txt        07:54:58  → 末行 P6E-MUT-VERDICT: MUTANT-CAUGHT-as-expected
_proj_10g/notes/p9_build_0x24/gate_mut_rerun.txt  08:25:22  → 末行 P6E-MUT-VERDICT: MUTANT-CAUGHT-as-expected
_proj_10g/notes/p9_build_0x24/gate_mut2.txt       07:56:29  → 末行 P6E-MUT2-VERDICT: MUTANT-CAUGHT-as-expected
_proj_10g/notes/p9_build_0x24/gate_p6e_fullchain.txt 08:26:04 → PASS_ALL（含 P9-B-3d 下界腿 / P9-B-3h 上界腿）
```
**(d) 输入哈希绑定（跑前=跑后，含 TB）**：
```
_proj_10g/notes/p9_build_0x24/INPUT_HASHES_BEFORE_GATES.txt:101   19fbf936…  sim/p6e_pcie/tb_p6e_pcie_wrapper.v
_proj_10g/notes/p9_build_0x24/INPUT_HASHES_AFTER_GATES.txt:101    19fbf936…  sim/p6e_pcie/tb_p6e_pcie_wrapper.v
（同件还绑 rtl/mir_uram_fifo.v = 52db7c0f… / 两件 TB / 两个门 bat）
```
**(e) 提交 `09e34a6` message 逐字**："- 门：p6e 四门全绿（mut/mut2 MUTANT-CAUGHT · 全链 PASS_ALL 含 B-3d/B-3h）；
矩阵 17/17 FROZEN（DIGEST 前后逐位同）"；`p9_build_0x24/REPORT.md:24-33` 有逐门时刻表（含 mut2 的
"锚点修复前首跑 GENFAIL / 修后重跑 11 项 FAIL = 内容判据"的两次记录、与 08:24:40 的"外来改写后重绑"重跑）。

### 结论
**不属实**。两门**已**随 TB 功能改动重跑（而且跑的是**比 FIX 轮更新**的、含 0x24 BID 同步的 TB），有可复算的
判决行 + 输入哈希绑定 + 真实臂对照（同 TB PASS_ALL ⇒ 突变臂的红可归因于突变）；kimi 引的 FIX_REPORT §7-4
文本"未重跑"在**该件写成时（07:46）为真**，但 **8 分钟后**的 0x24 轮已把此格关闭（并写进提交 message——
kimi 自己引用过的 `09e34a6`）。K4 的成因 = 只读了 FIX_REPORT 的自登记，未看 `sim/p6e_pcie/dir_mut*`
与 `p9_build_0x24/` 的实测件。
残留（仍成立、但属另一件事）：FIX_REPORT §7-4 文本未回写（陈旧自登记）；`sim/p9_uram` **单元门**本身未在 0x24 轮
重跑（0x24 REPORT §7-4 自登，读数归修正轮）——这条与"两个 p6e 突变门"无关。

### 建议修复（范围/优先级）
- **P3（文档）**：① **撤回 K4** 并在 FIX_REPORT §7-4 补一行"已于 0x24 轮闭合：`p9_build_0x24/gate_mut{,_rerun}.txt`
  / `gate_mut2.txt`（MUTANT-CAUGHT）+ 绑定哈希 `INPUT_HASHES_*_GATES.txt:101`"；② 派单侧登记"审查引用 '未核/未跑'
  类自登记时必须现核其后继轮的归档"（与本仓 #52/#91 同族）。

---

## §5 A-K5（P2）缺突变臂（至少 2 类） —— **属实**

### kimi 的发现（引原文）
12 臂全部集中在写门/读门/计数器/clr 总开关/守卫；**64 位数据面与 clr 分支内部零覆盖**。给出 3 条该有而没有的：
① clr 分支"部分清"臂（如删 `v_sr <= 3'd0;` 或 `o_occ <= 3'd0;` 一行）；② 弹性堆 FWFT 读出臂
（`dn_data = o_mem[op_r]` / 4:1 mux / `o_mem[op_w]` 写）；③（次要）`o_occ` 更新项臂、XPM 接线臂（`.enb(issue)→.enb(up_req)`）。

### 我的独立方法
现读 `mut_uram.py` 的 `MUTS` 全表（12 臂）+ 逐臂核其改动行（对照 RTL 现读行号），统计"哪些结构没有任何臂"；
对被点名的缺失类做**独立后果推演**（用 §1 的模型 + 逐拍账），判断"现有判据是否有牙"。

### 原始证据
```
mut_uram.py MUTS（现读全表）：
  mut_full_off(up_req 去 !ufull) · mut_full_e1(UFULL−1) · mut_issue_free(issue 去 CAP 门) ·
  mut_val1(arr_v 取 v_sr[1]) · mut_clr_off(整条 clr 分支封死 :227) · mut_clr_take(up_req 去 !clr) ·
  mut_dnreq(dn_gnt=dn_req) · mut_rstn_off(up_req 去 rst_n) · mut_en_off(up_req 去 en) ·
  mut_dnclr(pop 去 !clr) · mut_wp_nmc(wp 绕回位写窄) · mut_guard_off(删守卫③ $display)
⇒ 逐臂对照 RTL：全部落在 up_req/UFULL/issue/dn_gnt/pop/wp/guard 七类控制点上；
  **0 条**动 o_mem 数据通路（:173 dn_data=o_mem[op_r]、:234 o_mem[op_w] 写入、:214 .enb(issue)）·
  **0 条**动 clr 分支内部单行（:228 的 v_sr<=0 / :229 的 o_occ<=0）—— kimi 的两条"该有而没有"成立。
```
**后果推演（我方独立）**：删 `v_sr <= 3'd0;`（clr 部分清）⇒ clr 后旧流水 valid 链持续对齐 ⇒ 旧 `ram_dout`
在 clr+1..+3 被 `arr_v` 采入弹性堆（`o_occ` 从 0 起涨）⇒ 下游弹到旧字时：TB 期望队列已 resync（`eq_r=eq_w`）
⇒ 先弹先红 = **over_err（幻影弹）**，有旧字时再 **seq_err（逐字对账）** ⇒ G1c/G5b-b/G5b-c/GC2/GB3/G9e 家族
**预期**有牙（此为推演/预期，**未跑该臂**——与 kimi 同口径："有牙但无臂证明"）。
② 数据面臂（`o_mem[op_r]→o_mem[op_w]`）：`o_occ∈1..3` 时读错槽（`o_occ==4` 时 op_w≡op_r 同槽，不暴露）
⇒ G1b seq_err 预期红（未跑）。

### 结论
**属实**（缺臂事实逐臂核对无误；两条缺失类的后果推演我方独立成立；"现有判据有牙"是**合理预期、未证**）。
作为**覆盖缺口**（P2），不是现役缺陷。

### 建议修复（范围/优先级）
- **P2（门内工作，零 RTL 风险）**：补 2-3 臂：`mut_clrv`（clr 分支删 `v_sr<=0` 一行）、`mut_omem`（读索引
  `op_r→op_w`）、可选 `mut_oocc`（o_occ 更新丢 `+arr_v`）。每条须先验"其目标判据确实红"（否则暴露判据空转）。

---

## §6 A-K6（P2）G4/G8 固定种子单序列 —— **属实**

### kimi 的发现（引原文）
`tb_mir_uram_fifo.v:96-97` 种子写死（`lfsr_src=16'h1ACE` / `lfsr_dst=16'h2BDF`）；每次 real 跑 = 同一相位图；
头注释自称"双侧独立 LFSR ⇒ 相位不成简单比例"，但"单个种子的'独立'不构成相位覆盖论证"。低优先。

### 我的独立方法
现读 TB 激励源（种子/占空生成式/有无 `$random`/有无种子参数）；用自己的模型跑**自选种子与占空比**
（8 种子、2 万拍/跑、含 clr 注入），看"该风险是否兑现"（模型级复现，非 RTL 门级）。

### 原始证据
```
tb_mir_uram_fifo.v:95   // 两个独立 LFSR (确定性伪随机; 多项式/种子都不同 ⇒ 相位不成简单比例)
tb_mir_uram_fifo.v:96   reg [15:0] lfsr_src = 16'h1ACE;
tb_mir_uram_fifo.v:97   reg [15:0] lfsr_dst = 16'h2BDF;     ← 写死；全文无 $random / 无种子参数
```
我的模型（`ax_occ_reach_model.out` §B3，种子/占空均为自选、与 TB 与 kimi 均不同）：
```
seed=11 src=0.68 dn=0.34: pops=6831  seq_err=0 over_err=0 clr_pop=0 rst_take=0
seed=22 … pops=8530 / seed=33 … 10302 / seed=44 … 10795 / seed=55 … 4982 / seed=66 … 6822 /
seed=77 … 7844 / seed=88 … 10459   —— 逐字对账全部 0 错（含 max(occ+inv)=4100 的那一跑）
[PASS] 8 种子逐字对账: 丢/重/错序/clr 拍弹字/复位期取数 全 0
```

### 结论
**属实**（结构性事实：相位覆盖 = 单一固定序列；头注释的"独立性"论证对覆盖面无支撑）。
"风险现役未兑现"的判断我以自写模型/自选种子同向复现（**模型级**；不等于 RTL 门级已扫过相位）。

### 建议修复（范围/优先级）
- **P3（低优先）**：登记口径"相位覆盖 = 单序列（种子 A/B）"即可；若要做，TB 加种子参数 + 少量种子扫描
  （或 G4/G8 尾接一段换种子的复跑），属门增强、非阻断。

---

## §7 A-K7（P2）`SIM_ASSERT_CHK(0)` 口径登记 —— **部分属实（"默认 1"子句不实）**

### kimi 的发现（引原文）
`rtl/mir_uram_fifo.v:205` 显式 `.SIM_ASSERT_CHK (0)`；REVIEW F6② 点名 → `FIX_REPORT.md:305`（§7-1）自登未做；
"**关掉的是 XPM 行为模型的自带仿真断言（默认 1）**，无注释说明关了什么/为什么"。

### 我的独立方法
现读 RTL 行与两处登记；**到工具源头核"默认值"**：读本机 v2025.2 的 XPM 源
（`C:/AMDDesignTools/2025.2/Vivado/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv`）中 `xpm_memory_sdpram` 的参数声明与
断言门控条件。

### 原始证据
```
rtl/mir_uram_fifo.v:205      .SIM_ASSERT_CHK     (0),
REVIEW.md:97（F6②）          ".SIM_ASSERT_CHK(0)（:179）关掉了 XPM 的仿真自带断言（默认 1）…"
FIX_REPORT.md:305（§7-1）    "F6② SIM_ASSERT_CHK(0) 的口径登记未做（不属本轮派单修正项）"   ← 登记确未做（属实）
$ grep -n "SIM_ASSERT_CHK" C:/AMDDesignTools/2025.2/Vivado/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv
77:  parameter integer SIM_ASSERT_CHK = 0,          ← xpm_memory_base
8997: module xpm_memory_sdpram # (                   ← 我们例化的就是它
（其参数表内）parameter integer SIM_ASSERT_CHK = 0,  ← **默认 = 0**；全文件 16 处声明全 "= 0"
5431/6567/8184:  if(SIM_ASSERT_CHK == 1) begin : …chk_…   ← 断言/检查块只在 =1 时生成
```

### 结论
**部分属实**：① "口径登记未做、RTL 处无注释"——**属实**；② "关掉的是 XPM 自带仿真断言（默认 1）"——**不属实**：
**v2025.2 的 `xpm_memory_sdpram.SIM_ASSERT_CHK` 默认值 = 0**（工具源头现读），显式写 `(0)` = **照抄默认值**，
**没有关闭任何默认开启的东西**。该"默认 1"的措辞源出 REVIEW F6②，kimi 沿用了它；连带 REVIEW 的
"否则改回 1"建议也应改口径（改 1 = **有意启用**额外仿真检查，不是"恢复默认"）。

### 建议修复（范围/优先级）
- **P3**：在 XPM 例化注释加一行"`SIM_ASSERT_CHK=0`（= XPM 默认值；不启用 XPM 断言/检查块；启用 = 写 1）"。
  不属缺陷族，纯口径登记。

---

## §8 I1（信息）`issue`/`u_wr`/`arr_v` 三处 `!clr` 为冗余防御 —— **属实**

### kimi 的发现（引原文）
三处 `!clr` 在现役结构下为冗余防御项（推演证明，非缺陷）；建议头注释注明，免得下一轮审查再当功能项重推。

### 我的独立方法
逐处找全部消费者 + 逐拍推演"若删掉该 `!clr` 会发生什么"（用 §1 的模型逐拍展开流水/valid 对齐）：

### 原始证据与推演
```
rtl/mir_uram_fifo.v:155  wire pop   = dn_req && (o_occ != 3'd0) && !clr;
rtl/mir_uram_fifo.v:158  wire issue = (occ != {(AW+1){1'b0}}) && ((inv - {3'd0, pop}) < CAP) && !clr;
rtl/mir_uram_fifo.v:170  wire u_wr  = up_gnt && !clr;
rtl/mir_uram_fifo.v:171  wire arr_v = v_sr[2] && !clr;
```
- **arr_v**：消费者 = 正常分支（:234 `if (arr_v)` 与 :236 `o_occ +/-`）与守卫（:250，另有 `!clr` 门）——两者都在
  `if (clr)` 分支之外/之内被吞 ⇒ 删 `!clr` 无行为变化 ✓。
- **issue**：删 `!clr` 时 clr 拍多发一次 URAM 读（`.enb` 组合）——其数据到 `doutb@clr+3` 时 `v_sr[2]=0`
  （clr 分支整块清 `v_sr`；后续合法 issue 的 valid 位与流水**逐拍重新对齐**：`i@c+1 → v_sr[2]@c+4 ↔ doutb@c+4`
  ——我逐拍展开核过）⇒ 永不被采集；`rp` 被 clr 分支归零 ⇒ 指针无偏 ✓。
- **u_wr**：clr 拍 `up_req=0`（其自身含 `!clr`）且镜像合同 = **gnt 蕴含 req**（`app_rx_mirror.v:412` 现读）
  ⇒ `up_gnt=0` ⇒ 无写；该 `!clr` 是"防上游违契"的纵深（守卫③ 另有牙）✓。

### 结论
**属实**（信息级：三处冗余防御成立；建议头注释注明"现役结构下冗余、防接线/合同变更"）。
**附加（kimi 未列、我另发现）**：`pop`（:155）**不含 `rst_n`** —— 复位拍若 `dn_req=1 ∧ o_occ≠0`，`dn_gnt` 可脉冲
（`o_occ` 到沿才清）。现役**同复位域**（`u_mir_buf` 与 `u_mir_axis` 同一 `pcie_axi_aresetn`；下游寄存器在沿上清零）
⇒ 无功能后果；但该组合**无 TB 场景、无臂**（GR 场景 `dn_req=0`）。按 I1 同款登记即可（P3，非缺陷）。

### 建议修复（范围/优先级）
- **P3**：头注释一句（三处冗余 + `pop` 的复位期边界），归文档轮。

---

## §9 C 捆"无发现"的覆盖面核查（描述性结论）

### 三项的独立复算（全部吻合）
1. **`board/build_p7b_ku5p.tcl` +1 行导入**：现读 `:101 ${root_dir}/rtl/mir_uram_fifo.v` + `:102` 注释；
   `grep -n mir_uram_fifo` = 2 命中（1 导入 + 1 注释）⇒ **无重复导入** ✓；`git show 09e34a6` 功能 diff = +1 行（+注释块）。
2. **`mut_bwire.py` 锚点重对**：`mut_bwire.py:34` 的 `OLD` 串与现行 `board/wrapper_p4.v:3894` **逐字一致**
   （我方 `grep -cF` = 1，非 kimi 复跑）；`:3912/:3931` 两条 `64'd0` 常量（别的分支）不匹配锚形 ⇒ 现行文件上
   `anchor_hits==1` 自检（`:47-49`，`hits!=1 ⇒ return 2`）成立 ✓。
3. **wrapper BID 非注释行恰 1**：`git show 09e34a6 -- board/wrapper_p4.v` 功能性改动 = 1 行
   （`.BUILD_ID_V 32'h23 → 32'h24`）+ 注释行；无夹带 ✓。⚠️ **行号引用有误**：kimi 写"（:3866 区域）"，
   现读与 `09e34a6` 处**均为 `:4316`**（事实成立、行号需订正）。

### 覆盖面结论（不是 PASS/FAIL 裁定）
- 三项各自**可核、且我逐条复算吻合** ⇒ **"三项覆盖面扫描通过"**。
- 但整捆对 `09e34a6` 的覆盖**有 1 处结构性缝**：C 明确排除"矩阵 17/17 FROZEN 与门读数（属 A 捆门质量面/独立复跑件）"，
  而 A 捆对该格的唯一覆盖 = **K4**，K4 结论不实（§4）⇒ **0x24 轮的四门重跑（mut/mut2/全链/counters）在两捆里
  都没有被正确覆盖**（证据其实齐备，在 `p9_build_0x24/` 归档里）。
- 另有 **1 处未列面**：提交 `09e34a6` 的第 4 个声明面（"B-3 读侧 BID 同步 0x23→0x24：24 处/14 文件"）不在 C 的
  三项内，A/B 两捆也未含（其自证件在 `p9_build_0x24/` 的 DRYRUN/REHEARSE/APPLY/ASSERT/NEGCTL 系列，
  本次验证未对其逐件复核——超出 A 捆派单面，如实登记）。

---

## §10 未覆盖面与残余不确定（本验证自认）

1. **未跑**：Vivado/xsim/任何门（只读 + 自写模型）；未复跑 kimi 的 `negctl_occ_model.py`（我方模型独立实现，
   结论同向）；未逐行核 `sim/p9_uram/gate_stdout_fix/` 全部原始日志（只抽检 FIX_REPORT 引用到的行）。
2. **模型边界**：`ax_occ_reach_model.py` 是**模型**（自 RTL 现读推导），不是 RTL 本身；XPM 只按
   "LAT=3、空闲保持" 复刻。BFS 穷举在**缩比几何**（AW=4）完成——对现役 AW=12 是"同构转移方程 + 分量上界"
   两级论证（非 4096 深度上的穷举）。
3. **我附加的未列观察（kimi 未覆盖、供修复轮一并处理）**：
   - ① `REPORT.md:89` 的 `up_req = en && !clr && occ<4096` 是 **F2 修复前的旧公式**（RTL 现版含 `rst_n`）——
     第 5 处陈旧文本（同 K1 的文档面）。
   - ② `pop` 无 `rst_n`（见 §8 附加）。
   - ③ 工具 `:496/:498/:593` 的身份式描述同款陈旧（见 §3）。
4. **"未观测到 ≠ 不存在"**：K5 的"有牙"、"clr 部分清臂的实际红形"、K2 的 34872 严格上界（算术非实测）均属
   推演/预期；本件不把它们读成已证。
5. **时间边界**：K4 的推翻链依赖 0x24 轮归档（07:54–08:26）与提交 `09e34a6`（09:11:03）。截至本验证
   （2026-10-13 22:2x）：两 TB mtime 仍 = 07:53:17、`git status` 干净（未见后续编辑）⇒ 该链有效。

---

## §11 我的模型与原始输出（可复跑）

```
_proj_10g/notes/p9_xverify_claude_20261013/
├── ax_occ_reach_model.py   自写（BFS 穷举可达性 + AW=12 逐拍模型 + 5 波形×5 seed×4 万拍反证扫描 + 8 种子逐字对账）
└── ax_occ_reach_model.out  完整跑通存档（RESULT: ALL-PASS, fails=0）
复跑: cd <repo> && PYTHONIOENCODING=utf-8 python _proj_10g/notes/p9_xverify_claude_20261013/ax_occ_reach_model.py
```
关键读数：BFS（AW=4）= 5504 可达状态 / max(occ+inv) == 20 == DEPTH+CAP / `occ==DEPTH ∧ inv==CAP` 可达（128 态）/
0 违例；AW=12 对抗 = **4100 @cyc4100**（4096,4,0）；反证扫描 100 万拍最大 = 4100（rand/burst/gate 三型均触到）；
8 种子逐字对账 0 错。

*本件 = 逐条独立验证 + 原始证据 + 修复建议；不下 PASS/FAIL 裁定；裁定权在 TL/owner。*
