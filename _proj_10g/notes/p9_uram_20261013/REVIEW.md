# P9 追加轮（URAM 板内缓冲）—— 对抗审查报告（只读）

**审查对象**：`_proj_10g/notes/p9_uram_20261013/REPORT.md` + `rtl/mir_uram_fifo.v`(245) +
`board/wrapper_p4.v` 功能编辑 + `sim/p9_uram/`（TB 337 / bat 61 / mut_uram.py 81，7 臂）+
`sim/p6e_pcie/*.bat` 4 件补丁 + `diag_p9b3d/`
**审查时现读基线**：工作树 HEAD = `18c2717`（257c911 之后另有 Kimi 组两个 docs 提交 96a092c/18c2717 落在同一范围）；
`board/wrapper_p4.v` 工作树 sha256 = `598185021bcfa742d242b507d530fa49cf364280aceb1241fe860d5c7e23e6d7`（与 01:49 指纹逐字相同 ⇒
门读数与该内容绑定）；`rtl/mir_uram_fifo.v` sha256 = `22ca56949dae44ec33dd6e92c12430f6baeac6d671ae369a765cf60e043ace97`（与报告 §2 一致）。
**性质**：本件**不下 PASS/FAIL 裁定**、不写"时序已解决"；"未观测到"≠"不存在"。全部结论标注证据（文件:行 / 现读命令与输出）。

---

## §0 发现计数（按严重度）

| 级别 | 条数 | 编号 |
|---|---|---|
| 中 | 4 | F1（突变臂"没跑也判抓到"洞）· F2（`up_req` 无 `rst_n`，靠跨模块不变量闭合且未登记）· F3（clr 拍 dn 侧弹字无门 + 依赖下游关门）· F4（缺臂/缺场景 6 条，含一条**从未被触发过**的 RTL FATAL 守卫） |
| 低 | 5 | F5（判据名 >32 字符被截掉前缀）· F6（URAM 仅在构建后判 + `SIM_ASSERT_CHK(0)` 未登记）· F7（注释/报告数字小错 3 处）· F8（回归面：矩阵指纹不含新件、历史 bat 未打补丁、aliasgate 不含 PCIE_OBS）· F9（板级无缓冲水位见证 = 已登记但值得强调） |
| 信息 | 3 | I1（全部正面复核结论汇总：四条不变式逐状态推、XPM 用法、契约回归、并行面）· I2（P9-B-3d 修法意见）· I3（两个"看着不合理其实是设计点的红"的读数解释） |

**TL;DR（三条最重的）**：
1. **F1**：`run_tb_mir_uram_fifo.bat` 的突变臂判据 = "除 PASS_ALL 以外都算抓到" ⇒ xsim 崩溃/无任何判据行也会 exit 0 报 `MUTANT-CAUGHT-as-expected`（负对照方向的假绿）。
2. **F2**：`up_req = en && !clr && !ufull`（`rtl/mir_uram_fifo.v:143`）**不含 `rst_n`** ⇒ 复位窗内可"取走但永不记账"的静默丢字通道结构性存在；当前配置被"`en` 与缓冲同复位域（pcie_axi_aresetn）+ `mir_ctrl_r` 复位 0"这条**跨模块不变量**闭合，但该不变量未在任何注释登记。
3. **F3**：`clr` 拍 `dn_gnt = dn_req && (o_occ!=0)` 不门控（`o_occ` 到沿才清）⇒ "clr 拍不交付旧字"依赖下游 `axis_c2h_stream` 的 `clr_drop` 关门；单元门 TB 从不测该组合（do_clr 前总是先 `set_dn_req(0)`）。

---

## §1 现读方法与工具

- 非注释面过滤（wrapper）：`git diff d7ebafd..HEAD -- board/wrapper_p4.v`（316 行）→ python 逐行剥离 `//` 及字符串感知后取"代码部"差集。输出见 §I1-①。
- 突变件对照：`diff rtl/mir_uram_fifo.v sim/p9_uram/mut/mir_uram_fifo_mut_*.v` 逐个（每个恰 1 行）。
- XPM 行为模型：现读 `C:/AMDDesignTools/2025.2/Vivado/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv`（含 `xpm_memory_base`）的 SDP 读通路（§I1-③）。
- 对数复算：`xsim_real.log` / `arm_*.txt` / `p6e_fullchain.txt` / `diag_p9b3d/DIAG_stdout.txt`。
- 现读其余关键件：`rtl/axis_c2h_stream.v`、`rtl/app_rx_mirror.v`、`_proj_pcie/rtl/axi_regs.v`、`sim/p4sim/P4_MATRIX_FINGERPRINT_20261013_014907_*.txt`、`_proj_pcie/p7b_biz/p7b_mir_dump.cpp`。

---

## §2 发现清单（按严重度）

### F1（中）突变臂判据："没跑"与"抓到了"不可分 —— 负对照方向的假绿

**位置**：`sim/p9_uram/run_tb_mir_uram_fifo.bat:54-61`
```
:mut_arm
findstr /C:"FATAL mir_uram_fifo" xsim.log >NUL && (echo URAM-FIFO-FATAL & goto mut_caught)
if %RC%==0 (echo URAM-GATE-VERDICT: MUTANT-NOT-CAUGHT & ... & exit /b 1)
:mut_caught
echo URAM-GATE-VERDICT: MUTANT-CAUGHT-as-expected
```
**反例**：`RC` 的唯一来源是 `:45-46` 的 `findstr /C:"PASS_ALL" xsim.log` + `set RC=%ERRORLEVEL%`。若 xsim 崩在跑动中途（或 `xsim.log` 根本没生成成判据行——`:43` 的 `findstr /C:"URAM_FIFO_GATE"` 只**打印**、不参与判据），则 RC=1 ⇒ 不进 `if` ⇒ 落到 `:mut_caught` ⇒ **exit 0 报"按预期抓到"**。即：**任何基础设施失败都被记成"门有牙"**（本仓自己点名的"注入过≠测到了"/哑门家族）。TIMEOUT 有专门拦截（`:44`），但崩溃/空日志没有。
**建议**：mutant 分支把"抓到"收紧为硬证据——必须命中 `[FAIL]` 或 `FATAL mir_uram_fifo` 二者之一，且 `URAM_FIFO_GATE:` 行必须存在，否则按基础设施失败 `exit /b 1`。real 分支现状是严的（`:48-52`），不必动。

### F2（中）`up_req` 不含 `rst_n`：复位窗内"取走但永不交付"通道存在，靠跨模块不变量闭合且未登记

**位置**：`rtl/mir_uram_fifo.v:143`（`assign up_req = en && !clr && !ufull;`）、`:144`（`u_wr = up_gnt && !clr`）、`:197-203`（rst/clr 整块清零）。
**推演（反例构造）**：设 `rst_n=0`（缓冲复位）、`en=1`、镜像侧活着（`reset_n=1`，FIFO 非空）。则 `occ=0 ⇒ ufull=0 ⇒ up_req=1`（`rst_n` 不参与）⇒ 镜像按合同给 `dma_gnt`（`rtl/app_rx_mirror.v:412`：`dma_gnt_i = dma_req && !fifo_empty && !rd_en && !flush_r`，**gnt 蕴含 req**）⇒ `u_wr=1` ⇒ URAM 写口在 `addra=wp[11:0]=0`（`wp` 被复位钳在 0）落笔，而 `wp` 不增 ⇒ 该字**被取走、写进一个 `occ` 看不见的槽、此后永不会被读出**（`issue` 需 `occ!=0`）⇒ 违反不变式①；且此事**不触发任何守卫**（三条 FATAL 都不覆盖"复位期取数"）。
**为什么现在不可达（逐项现读）**：① `en = mir_ctrl[3]`（`board/wrapper_p4.v:3852`）来自 `axi_regs`，其 `rst_n` = **同一条 `pcie_axi_aresetn`**（`board/wrapper_p4.v:4706`）；② `mir_ctrl_r` 复位值 = `32'd0`（`_proj_pcie/rtl/axi_regs.v:252`）⇒ 缓冲复位期间 `en=0` ⇒ `up_req=0` ⇒ 无 gnt。
**残余风险**：该安全性是**跨模块、隐式**的（`en` 的复位域 + 复位值决定本模块不变式成立与否），任何一次"给 `up_req` 接一个异域使能 / 板上固化 `en=1` / 把 `mir_ctrl` 搬域"都会静默打开该通道。
**建议**：① 最小改：`assign up_req = rst_n && en && !clr && !ufull;`（复位期不取数，方向安全）；② 或至少在头注释登记"依赖 `en` 与 `pcie_axi_aresetn` 同域且复位 0"这条不变量；③ 单元门加一臂（`en=1` 期间拉低 `rst_n`，断言无取数）。

### F3（中）`clr` 拍 dn 侧弹字无人门：现役靠下游关门，单元门零覆盖

**位置**：`rtl/mir_uram_fifo.v:138`（`pop = dn_req && (o_occ != 3'd0)`）、`:146`（`dn_gnt = pop`）。
`clr` 拍清的是寄存器（`:201`），而 `pop` 是组合量、`o_occ` 到沿才变 ⇒ **clr 拍若 `dn_req=1`，`dn_gnt=1` 且 `dn_data=o_mem[op_r]`（上一窗口的字）**。
**现役系统为什么不出事（现读）**：`rtl/axis_c2h_stream.v:167`(`clr_drop=clr`)、`:202`(`dma_req = en && !clr_drop && (...)`）⇒ clr 拍下游**结构性不拉 req** ⇒ `dn_req=0`。另外镜像的 `clr_pulse_rd = clrt_sr_r[2]^clrt_sr_r[1]`（`rtl/app_rx_mirror.v:384/436`）= **恰 1 拍**脉冲，无"连续 clr 电平"问题。
**两条缺口**：① **门没有牙**：单元门 TB 的 `do_clr`（`tb_mir_uram_fifo.v:146-156`）在 G5/G5b 使用前都先 `set_dn_req(0)`（`:256`/`:269`）⇒ "clr 拍下游正在弹"这个组合**从未被激励**，"不交付旧字"这条没有任何判据覆盖（`G9d clr_take` 只看 up 侧）；② **未来消费者陷阱**：本模块自称"clr 拍全清 ⇒ 丢弃"，但该语义实际由**下游**的 `!clr_drop` 承担——换一个不在 clr 拍关门的消费者，旧窗口字会经 `dn_gnt` 漏进新窗口（正是板级 D4 抓到的形态族）。
**建议**：RTL 把 `dn_gnt` 收成 `pop && !clr`（一行，与 `up_req`/`u_wr` 的 `!clr` 同款）；并在 TB 加一条"clr 拍保持 dn_req=1 ⇒ 断言 `dn_gnt==0` 且期望队列按丢弃记账"的判据。若刻意不改 RTL，则必须在头注释把"依赖下游 clr 拍关门"写实，并让 TB 补一条该场景的判据。

### F4（中）缺臂 / 缺场景（对照 mut_uram.py 逐臂核过："在场 7 臂 = 每臂恰 1 行恰 1 处"✓；**缺 6 类**）

现读：`diff rtl/mir_uram_fifo.v sim/p9_uram/mut/mir_uram_fifo_mut_*.v` 每个仅 1 行（`mut_clr_off` :201 · `mut_clr_take`/`mut_full_off` :143 · `mut_dnreq` :146 · `mut_full_e1` :131 · `mut_issue_free` :141 · `mut_val1` :145），生成日志 `mut_mut_*_gen.txt` 各 `hits = 1 (want 1)`✓，且 bat **每次先重生成**（锚点失配会硬失败）⇒ 不存在"跑陈旧突变件"面。

缺的（建议按序补）：
1. **`en` 项**：无任何臂动 `up_req` 的 `en &&`（`mut_full_off` 去 `!ufull`、`mut_clr_take` 去 `!clr`、去 `en` 没有）。`G6` 是现成的判据，缺臂。
2. **复位**：无任何臂动 `rst_n` 分支、TB 全程只有开局一次复位（无"跑动中途拉低 `rst_n`"场景）。复位路径（整块清零）与 clr 同权重，却零覆盖。
3. **"无 req 也给 gnt"的上游违约守卫**：RTL 有 `FATAL mir_uram_fifo: upstream grant without req`（`:224-225`），但 **TB 的源模型结构性不会产生它**（`tb:108` `up_gnt = up_req && !src_hold_v`），且**没有任何一个突变臂走过这条路**（7 臂日志里该串 0 命中）⇒ 该守卫"从未被触发过"（本仓口径：注入过≠测到了；此处连注入都没有）。建议加 TB 模式（`src_hold_v` 之外的独立 force）证明守卫有牙。
4. **连续/背靠背 clr**：`do_clr` 只发单拍；**clr 拍 `dn_req=1`**（见 F3）；**clr 紧邻 `up_gnt`**（clr-1 拍成交、clr 拍清账）都未激励。
5. **`wp`/`rp` 位宽与 AW 绕回的单点臂**：G8 覆盖了绕回行为（>2×DEPTH），但没有"把 13 位加 1 写窄/写错"这类单点突变。
6. **`arr_v` 的 `!clr` 项**（`:145`）：纯防御项（现值下无害），无臂——可归入"不必要项"清单，不必强补。
另：`AW`/`OQ`/`LAT` 三参数的仿真自检（`:110`）本身没有负对照（例如"故意给 LAT=2 应硬失败"未测）——低优先。

### F5（低）判据名 >32 字符被截掉**前缀**：判据 ID 在日志里整体消失

**位置**：`tb_mir_uram_fifo.v:54/60/66` —— `input [255:0] name` = **32 字节**。
**机制（现读实证）**：Verilog 字符串字面量赋给 256 位向量时超长部分丢的是**高位（左侧）**；xsim `%0s` 打印该向量 ⇒ 名字只剩**末 32 字符**。逐条复算（python 对拍 `xsim_real.log`）：
```
'G1a taken >= 150 words (path alive)'(35) -> ' taken >= 150 words (path alive)'   ← 日志原样（注意双空格）
'G2a CAPACITY-PIN (whitebox): occ == DEPTH (4096)'(48) -> ' (whitebox): occ == DEPTH (4096)'
'G2f after full drain: popped - taken == p0 (nothing lost in elastic/inflight)'(77) -> 'othing lost in elastic/inflight)'
```
⇒ 报告说"判据名已改纯 ASCII"只解决了非 ASCII 逐字节损坏，**ASCII 长名仍被截**；而报告 §4 与 §2 的表格又是按 `G2a/G2c/G1a…` 这些**已被截掉的 ID** 引用的 ⇒ 对日志审计的人按值对不上 ID（`[FAIL]  (whitebox): occ == DEPTH (4096) = 4296` 这种行尤其容易读错成"无名判据"）。
**建议**：name 端口加宽到 `[511:0]`；或把判据 ID 放**名字末尾**（`… (G2a)`）。

### F6（低）URAM 推断只有"构建后人工核"一道判据；`SIM_ASSERT_CHK(0)` 未登记

① 报告 §6 的暴露形态只给"构建后核 `URAM288 = 1`"（人工看表）。本仓"静默回退 BRAM"是历史重灾区（`Synth 8-6793` 家族），而 XPM 的 `MEMORY_PRIMITIVE("ultra")` 是否被工具在极端情形下改写**没有任何本地/门级判据**。更早更硬的两条可选：把 `report_utilization` 的 URAM 计数写成构建脚本的**硬门**（=0 即失败），或先对该模块做一次 OOC synth（分钟级）核 `Synth 8-6793` + URAM 推断。容量自洽性我核过：`MEMORY_SIZE = 64*(1<<12) = 262144 bit = 256 Kb ≤ 288 Kb` ✓ 落单个 URAM288 合理。
② `.SIM_ASSERT_CHK(0)`（`:179`）关掉了 XPM 的仿真自带断言（默认 1）。报告/注释未见理由登记。若为规避噪声而关，建议在注释里写明"关了什么、为什么"（本仓纪律：口径登记）；否则改回 1。

### F7（低）注释/报告小错 3 处（其余数字我复算过，见 §I1）

① `rtl/mir_uram_fifo.v:119-120` 与 `:125` 两处**指针位宽注释互相矛盾且都与代码不符**：代码 `localparam OW = (OQ<=2)?1:((OQ<=4)?2:3)`（:120，正确：OQ=2→1 位、3..4→2 位、5..7→3 位），而 :125 注"2..4 ⇒ 1 位"、:119 注"2..4 ⇒ 2 位"——两处都错且自相矛盾。默认 `OQ=4`（wrapper 传参）下无功能影响。
② 报告 §5.3 写诊断副本"只差 1 行注入量 + **3 行注释**"；**现读 = 4 行注释 + 1 行代码**（`diff diag_p9b3d/tb_p6e_pcie_wrapper.v sim/p6e_pcie/tb_p6e_pcie_wrapper.v` = `722,726c722`，899 vs 895 行）。
③ 报告 §1.6/§2 的"clr 拍不取数（5 结构性）"只覆盖了 **up 侧**（`up_req` 含 `!clr` ✓ 成立），未覆盖 dn 侧（见 F3）——措辞容易让读者以为 clr 拍"一个字都不进不出"。

### F8（低）回归面三格（把报告 §5.1 的两处"未核/弱"现读核清）

① **P4 矩阵指纹结构性不含本件**（现读）：`sim/p4sim/P4_MATRIX_FINGERPRINT_20261013_014907_after.txt` 共 257 文件哈希，其中 `rtl/*.v` 仅 **27 个**（chain/manifest 集合），`grep mir_uram|app_rx_mirror|axis_c2h` = **0 命中** ⇒ 矩阵对 P9 三件（含新件）**零覆盖**（#52"清单没有"家族）。真支覆盖只能靠 p6e 门——它们 `dir /b /s "%ROOT%\rtl\*.v"`（`run_tb_p6e_pcie_counters.bat:20`）自动收新件 ✓（这也是 4 条 bat 需要 xpm 补丁的原因）。
② **未打 xpm 补丁的历史 bat**（`sim/p5wu_p1p2*` · `sim/p5wu_p1p2_regress/p6e_pcie_ab/*` · `sim/p7b_stageb_rx8_regress/extra/*` · `sim/p7b_stagec_tx_regress/extra*`）重跑时会**响亮失败**（`VRFC 10-2063 Module <xpm_memory_sdpram> not found`）——方向是好方向，报告已登记配方。
③ **`aliasgate` 现存配置 = `APP_MODE` 与 `(APP_MODE, DP_156MHZ)`，不含 `PCIE_OBS`**（现读输出 `config G_appmode_dp156 (macros=APP_MODE,DP_156MHZ)`）⇒ 它对本实例**零覆盖**；报告把它列进"既有门"清单时未标注这一点（建议在清单里给每门标"是否编到真支"）。

### F9（低）板级无缓冲水位见证（已登记，值得在板级协议里写实）

`dbg_occ/dbg_oocc` 在 wrapper 显式空接（`board/wrapper_p4.v:3861-3862`）。⇒ 板上无法区分"缓冲在吸收"与"缓冲从不进水"；且模块内**没有任何丢字节计数器**（合同要求）⇒ **缓冲内部静默丢字在板上没有直接见证**，只能靠端到端逐字节（`MIR_VERIFY`）与 `W70`/两条恒等式间接判。报告 §7-7 已登记仪器缺口；建议板级轮把"逐字节全查 + `ΔW70` + 式 A/式 B（终态）"三条**同时**列为收口判据（不要只跑计数对账）。

---

## §I1 正面复核（"没找到反例"的部分，逐条给证据）

**① 并行面（Kimi 注释改写是否夹带功能变化）—— 现读结论：wrapper 非注释净变恰 4 处，未夹带**
`git diff d7ebafd..HEAD -- board/wrapper_p4.v`（含 96a092c 的 28 处引用改写 + 257c911 本刀）经"剥注释+字符串感知"过滤后，**净新增代码** = `mir_uf_req/gnt/data` 三根声明 + `u_mir_buf` 例化 14 行；**净删除代码** = `u_mir` 例化的 `.dma_req/.dma_gnt/.dma_data(mir_dma_*)` 三行；`u_mir_axis` 例化只有注释行变化（code 部逐字相同）；`::1319-1322` 禁碰区（`app_reg_addr/wr/wdata` 三行 assign）零变化（`:1320-1322` 现读原样）。
同一过滤跑 `96a092c` 其余 32 个文件：**全部为注释/文档串内插入 `agent_docs/`**；唯一落在**运行期输出字符串**上的是 `_proj_pcie/p6b_accept.sh` 的 3 行 `echo "…"`（**文本措辞**，无逻辑分支依赖该串的现读证据未查证 —— 若有门 grep 这些串需另核，属低风险）。`18c2717` 仅新增 `docs/` 5 件 + README。

**② 四条不变式逐状态推 —— 未找到可违反的时序（除 F2/F3 两处"现役被闭合"的窗口）**
- ①写侧不丢：`ufull ⇒ up_req=0`；合同保证"无 req 不给 gnt"（`app_rx_mirror.v:412` 现读）。满态误写另有守卫（`:222`）。
- ②到达安全：`inv ≤ CAP` 归纳成立——`issue` 门用 `(inv − pop) < CAP`，逐拍 `inv' = inv + issue − pop ≤ CAP`（`pop=1 ⇒ o_occ≥1 ⇒ inv≥1`，无 4 位下溢反例；`inv=0,pop=1` 时 `inv−pop=4'hF` ⇒ 门关闭 = 安全方向）。到达拍 `v_sr[2]=1 ⇒ inflight≥1 ⇒ o_occ ≤ CAP−1 = 3 < OQ` ⇒ `o_mem[op_w]` 必落在**环上唯一的空槽**（`op_w−op_r ≡ o_occ (mod 4)` 由单驱动块保证）；`o_occ=4` 与 `arr_v=1` 结构性互斥；`o_occ=4` 时若同拍有 `pop`（写槽 = 读槽）也只是"同沿覆写已被组合读走的槽"，且该组合不可达。
- ③存储回收点：同拍 `u_wr ∧ issue` 需 `wp[11:0] == rp[11:0]` ⇒ `occ ≡ 0 (mod 4096)` ⇒ `occ ∈ {0,4096}`；`occ=0 ⇒ issue=0`、`occ=4096 ⇒ u_wr=0`（合同）⇒ **结构性不相撞** ✓（`read_first` 的前提确实成立）。
- ④在囊：`occ ≤ 4096`（就写门）+ `inv ≤ 4` ⇒ ≤ 4100 字。报告 §1.3 表里的"在飞 ≤2"指"未到达"，与 `inv`（含到达拍那 1 位）不矛盾 ✓。
- **clr/复位**：clr 拍 `up_req=0`（`:143` 含 `!clr`）、`u_wr=0`（`:144` 再门）、`issue=0`（`:141`）⇒ 上游不成交 ✓；在飞 ≤3 字靠清 `v_sr` 丢弃；**clr 后幻影读不漏**：XPM 读流水使 `doutb` 在 issue+3 出现（见 ③），clr+1..clr+3 期间 `v_sr[2]≡0` ⇒ 不采旧 doutb；新 issue 的数据与 `v_sr[2]` 逐拍对齐（我按 `v_sr <= {v_sr[1:0], issue}` 逐拍展开核过 `clr+4` 对齐）。复位同款整块清零 ⇒ 空态读出旧值永不弹给下游 ✓（`dn_gnt=pop` 需 `o_occ≠0`）。
- `en` 沿：`en` 只门 `up_req`；1→0 当拍若有 gnt 仍正常记账（`u_wr` 只看 `!clr`）⇒ 无丢；`aw`/`occ` 账不依赖 `en` ✓。
- AW 绕回：`wp/rp` 13 位、绕回 8192，`occ = wp−rp` 在 `occ≤4096` 下模运算精确 ✓。

**③ XPM 用法（现读 v2025.2 模型源码，结论 = 报告声明成立）**
`xpm_memory_base` 的 `MEM_PORTB_RD_PIPE` 路径（`xpm_memory.sv:3082/3157/3173`）：`enb_pipe[0] <= enb_o_pipe_ctrl`（= `enb`，`:1726`，`enb_i = enb` 直通 `:1732`）；`doutb_pipe[0] <= doutb_reg` 由 `enb_pipe[0]` 门 ⇒ 每笔读的语义延迟 = **恰 3 拍且与 enb 空档无关**（末级 `doutb_pipe[LAT-2]` 由 `regceb_i` 推，我们恒接 `1'b1`；`doutb_pipe[0]` 只在"该笔读的下一拍"更新）⇒ "issue 拍 → `doutb` 恰在 +3、空闲保持旧值、由 `v_sr[2]` 判有效"与模型**逐拍一致**；`WRITE_MODE_B=read_first` 只影响读写同址，而同址已被③结构性排除 ⇒ 该选择不承重 ✓。`regceb(1'b1)` 是"末级无条件推进"的前提——它若被改，整个 valid 链错位（建议注释点名）。

**④ 合同回归（逐条现读）**
aux 合同 ✓（gnt 蕴含 req，1 grant = 2 逻辑字 = 8 B，空态不弹——`app_rx_mirror.v:412/407`）；`MIR_DMA_CNT` 口径在成形器**本刀 0 改动**（`git diff d7ebafd..HEAD --stat -- rtl/axis_c2h_stream.v` 空）✓，语义位移（"从本缓冲取走"）已在 `mir_uram_fifo.v:236-240` 与报告 §1.7② 登记 ✓；**不新增丢字节计数器** ✓（模块内 `grep drop` 仅注释 2 处、无计数逻辑）；读侧语义：`rtl/app_rx_mirror.v` 在 257c911 **0 改动** ✓（范围 d7ebafd..HEAD 只有 96a092c 的一条注释改写 `P6B_SPEC→agent_docs/P6B_SPEC`，现读 diff 逐行核过）。
两条恒等式推导**复核成立**：式 A 两端均在计数点下游 ⇒ 不受缓冲影响 ✓；式 B：`K − taken(shaper) − ΔW70 = 镜像残余 + O`（`O` = 缓冲占用 ≤ 4099 字 ≈ 32.8 KB）⇒ **中途评估差额可达 O**，工具默认上界 `--resid-max-mirror 24`（`_proj_pcie/p7b_biz/p7b_mir_dump.cpp:96/591` 现读）**只对终态（O=0）成立** ✓；报告建议的三条口径（保持"停源→排空到 early-stop"协议 / 显式放宽并注明 / 加观测口）方向正确——补一条：**`en=0` 停排空时缓冲自身的 ≤32.8 KB 残留会保留到 `en` 回来才交付**（与镜像 FIFO 语义一致，但"en=0 ⇒ 在飞只剩 ≤32 B"的旧直觉不再成立，凡按旧直觉推残余的判据/工具都要重看）。

**⑤ 门读数与对数（抽检复算）**
- `xsim_real.log` = **43 条 `[PASS]`** ✓（与报告"43 判据/0 FAIL"逐条计数一致）；`URAM_FIFO_GATE: PASS_ALL` ✓。
- G2 白盒账**复算闭合**：锚点处 `occ=4096, inv=4, taken=4099`，而窗口起点 `p0=1` ⇒ 模块内容 = `occ+inv = 4100` = TB 未核销（`taken − popped + p0 = 4099 − 0 + 1 = 4100`）✓；G2-end `taken=4107 / popped=4108 / occ=0 / inv=0` ⇒ `popped − taken = 1 = p0` ✓；G2-acc `eq_w=eq_r=4308` ⇒ 未核销 0 = 模块内容 0 ✓。`G7 popped=300/300 拍` ✓ 稳态 1 字/拍。
- 突变臂读数**逐个可解释**：`mut_full_e1 ⇒ occ=4095`（恰 `UFULL−1`）✓；`mut_issue_free ⇒ G2a 读 occ=1` 是**设计点的红**而非伪影——自由发起让 `rp` 追平 `wp` ⇒ 永不到 4096 ⇒ `while` 循环跑满 `DEPTH+200` 才退出（日志 `require-drop after 4296 cyc` 与之吻合）✓；`mut_full_off / mut_issue_free` 各命中 `URAM write while FULL`(5) / `arrival into FULL elastic FIFO`(3444) ⇒ 两条守卫**有牙** ✓。
- `p6e_fullchain.txt`：**全门唯一红 = `P9-B-3d`**（`:109-110`），`delivered words = 720` 全数交付、`keep_bad=0` ✓；`diag_p9b3d/DIAG_stdout.txt` 尾部 `PASS_ALL  tb_p6e_pcie_wrapper: 全链门全过` ✓ 且 `ΔW70` 实测推进（`4d494e79 → 4d49fea1`）✓。
- 门证据与内容绑定：wrapper 现读 sha256 与 01:49 指纹逐字相同（见头注）⇒ 全部读数对当前内容有效 ✓。

---

## §I2 `P9-B-3d` 修法意见（只给意见，不改任何门）

**归因成立**（现读）：判据 `sim/p6e_pcie/tb_p6e_pcie_wrapper.v:733-735`；旧注入 700 拍 ×4 B = 2.8 KB < 新在囊 ≈ 34 KB（镜像 2 KB + URAM 32 KB + 成形器 32 B + 分级暂存）⇒ 全吸收 ⇒ `ΔW70=0` ⇒ 红。这不是计数路径坏了，是**激励的"够不够满"前提**变了。
**方向评价**：诊断的"容量感知注入"（700→20000 拍 = 80 KB ≈ 2.4× 容量）**方向对**，但建议再进一步：
1. **把注入量绑到一个具名常量并注明容量预算**（如 `P9B3_INJECT_BEATS = 2.4 × 弹性预算 / 4`），否则下一次容量变化（`AW=13` ⇒ 64 KB）会**再次静默失效**（同一个坑第二次踩）。
2. **判据升级为双边账**（更强、且抗容量变化）：`ΔW70 ≥ 注入 − 弹性上界`（下界腿）+ 恢复期交付量 == `注入 − ΔW70`（闭上界腿，`keep_bad`/前缀逐拍已是现成件）。`>0` 只证"路径活着"，**抓不到"多计/少计"类缺陷**——按本仓口径"判据要有判别力"，">0"是弱环。
3. 同步改掉判据旁的**陈旧推理注释**（"下游弹性只有几十字节"）；诊断副本已加 4 行说明，主 TB 的注释仍旧。
4. 不建议把判据改成"`ΔW70 == 期望值`"的精确等式（吸收量的精确建模会把台架耦进 RTL 内部容量；下界+闭账是更稳的中间态）。
**诊断可复现性** ✓：副本与原件 diff = 1 行注入量 + 4 行注释（F7② 订正报告口径），`run_diag.bat` 自定位、日志/门读数齐备，重跑可复现（`DIAG_stdout.txt` 全绿 + `W70` 推进）。

---

## §I3 两条"看着不合理、其实对"的读数（备忘，防下游误读）

1. `arm_mut_issue_free.txt` 的 `occ == 1 (期望 4096)` / `falls back to DEPTH-1..DEPTH-8 = 1`：自由发起下 `rp` 与 `wp` 同速 ⇒ 占用水位低 ⇒ 白盒锚必红 + 循环跑满超时拍数。**这是突变该红的形态**，不是 TB 竞争伪影。
2. `p6e_fullchain.txt` 的 `P9-B-3 W70: 4d494e79 -> 4d494e79`（原样不变）+ 同时 `delivered words = 720`：**"没丢"与"全交付"同时成立**才是这条红的本体（= 缓冲把 2.8 KB 全吸收了）；不是 W70 计数坏了（诊断臂同判据 + 80 KB 注入 ⇒ 推进 ✓）。任何把这条红读成"丢字节计数器坏了"的下游结论都是错的。

---

## §4 未做 / 残留（本审查自认的边界）

- **未跑任何仿真/构建**（只读审查，未重跑门、未综合）⇒ "XPM 行为模型 ↔ 综合后网表读延迟一致性" 与 "URAM 推断/时序" 一律**未测**（报告 §7-1/§7-2 同款，我未加深）。
- 未审计 `diag_p9b3d/files.f`（218 行）与其 xvlog/xelab 日志的**逐行**内容（只核了 TB diff 与 DIAG_stdout 结论）。
- 未核 `sim/p6e_pcie/run_tb_p6e_pcie{,_mut,_mut2}.bat` 的**其余**历史行为（只核了本刀 +4/−1 补丁内容 = xpm 两行 + 注释）。
- `p6b_accept.sh` 的 3 行 echo 字符串改写是否有任何门 grep 它们 —— **未核**（低风险，见 §I1-①）。
- 仓库根 `_tmp_*.py`（12 个未跟踪）与本轮无关，未动。
