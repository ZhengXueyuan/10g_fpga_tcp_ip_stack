# BUNDLE A（URAM 板内缓冲）—— Kimi 组跨组对抗审查报告

**审查人**：Kimi 组（跨组对抗审查员，对 Claude 组交付物做只读找茬）
**日期**：2026-10-13 22:00 +0800
**审查对象 commit**：`7200c919ca1aadd82dc29dd0f3724a51ddecda7d`（HEAD；本捆功能件 = `257c911` 实施 + `f46a221` 复核修订轮；其上另有构建收口 `09e34a6`（0x24，URAM288=1）与台账件，见 K6/覆盖面）
**方法**：只读静态审查 + 构造性验证（自写逐拍 Python 模型，见 §5）。⛔ 未跑 Vivado/xsim，未改任何既有文件。
**审查基线件**：`_proj_10g/notes/p9_uram_20261013/{REPORT,REVIEW,FIX_REPORT}.md`、`rtl/mir_uram_fifo.v`（275 行逐行）、`board/wrapper_p4.v` 接线（现读 3777-3901 + `git show 257c911` diff + `f46a221..HEAD` 净差核对）、`sim/p9_uram/`（TB 445 行、bat 108 行、mut_uram.py、namecheck.py、12 突变件逐个 diff、gate_stdout_fix 抽检）、`_proj_pcie/p7b_mir_dump.cpp`（式 A/式 B 实现）、`rtl/axis_c2h_stream.v` / `rtl/app_rx_mirror.v` / `_proj_pcie/rtl/axi_regs.v`（合同/复位域现读）、XPM 行为模型源（`xpm_memory.sv` 读管道独立复核）。
**本件性质**：只列发现与证据，**不下 PASS/FAIL 裁定**；"未观测到"≠"不存在"。

---

## §0 发现计数（按严重度）

| 级别 | 条数 | 编号 |
|---|---|---|
| P0 | 0 | —（未发现会导致数据错或合同破的反例；见 §4 覆盖面） |
| P1 | 2 | K1（缓冲占用上界 4099↔4100 差 1 字且文档自相矛盾，构造性坐实）· K2（式 B 中途真上界 32824 B vs 工具默认 24 B，假红面仍在） |
| P2 | 5 | K3（计数点口径权威注释陈旧两处）· K4（p6e 两个突变门未随 TB 改动重跑）· K5（缺突变臂 ≥2 类）· K6（G4/G8 随机相位为固定种子单序列）· K7（`SIM_ASSERT_CHK(0)` 口径登记两轮未做） |
| 信息 | 1 | I1（`issue`/`u_wr`/`arr_v` 三处 `!clr` 现役结构下为冗余防御项——推演证明，非缺陷） |

---

## §1 发现清单（按严重度排序）

### K1（P1）缓冲占用上界 "4099 字" 错误且文档自相矛盾；真实上界 = 4100 字（32800 B）

**位置**：`REPORT.md:102`（"≤4099 字 = 32.8 KB"）、`REPORT.md:120`（"O ≤ 4099 字"）、`rtl/mir_uram_fifo.v:267`（"上界 4099 字"）vs **`REPORT.md:89`（"在囊 = 4096 + inv(≤4)" = 4100）**、TB 判据 `tb_mir_uram_fifo.v:217`（`G2b taken in [DEPTH, DEPTH+OQ]` = 允许 4100）。

**反例构造（输入序列）**：`rst_n=1, en=1, clr=0, dn_req≡0`（下游长停），源常就绪。推演：`inv` 在开局 ~8 拍内顶到 CAP=4 并保持（`issue` 门 `(inv−0)<4` 关闭）；此后 `occ` 每拍 +1（写 1 发 0），第 4100 拍 `occ` 首次触 4096（ufull）——**该拍 `occ=4096 ∧ inv=4` 同时成立**，在囊 = 4100 字。4099 的潜台词（"occ 与 inv 不能同时取满"）不成立：`inv=4` 不阻塞写门，`occ=4095→4096` 的写入只要求 `!ufull` 于**写入当拍**成立。

**构造性证据**：负对照模型 S1 实测 `O_max = 4100 (occ,o_occ,inflight)=(4096,4,0) @cyc4100`（§5 输出原文）。且 TB 自家 G2b 区间 [4096,4100] 与文档 4099 互相矛盾——门允许的值域比文档上界大 1。

**影响**：所有引用 4099 的"上界"叙事（式 B 中途上界、`P9B3_ELASTIC_MAX_BYTES` 预算注释的容量依据）基础数字差 1 字（8 B）。方向：均为**低估**占用（乐观方向），未造成现判据漏洞（预算 35840 B 仍有 ≥3.4 KB 裕量）。

**建议修法**：三处 4099 统一改 4100 字 = 32800 B；顺手把 `REPORT.md:89` 与 `:102/:120` 的口径合成一句"在囊 = occ(≤4096) + inv(≤CAP) ≤ 4100 字"。

### K2（P1）式 B 中途真上界 = 镜像残余 + O_max ≈ 32824 B，工具默认 `--resid-max-mirror 24` 差 ~1367 倍，且工具注释仍写"残余 = 镜像残余"

**位置**：`_proj_pcie/p7b_mir_dump.cpp:66-69`（"式 B … == 镜像残余 ∈ [0, --resid-max-mirror]（默认 24 B）"）、`:157`（`RESID_MAX_MIRROR_DEF = 24`）；缓冲引入后的真实中途差额 = `镜像残余(≤24 B) + O`，`O ≤ 4100 字 = 32800 B`（K1）。

**证据**：构造性复算（§5 S5）：`式 B 真中途上界 = 24 + 32800 = 32824 B`，默认 24 为其 1/1368。REPORT §3 已登记"默认 24 只对终态成立"+三条建议，**但工具一行未改**（"工具轮的事"），工具帮助文本（`:96`）与注释（`:61-68`）亦未加"仅终态排空后有效"限定。`en=0` 停排空时缓冲 ≤32.8 KB 残留保留到 `en` 回来（REVIEW §I1-④ 已登记）——凡按旧直觉在中途/停排空态评估式 B 的跑法必假红。

**建议修法**（工具轮）：① 工具内把式 B 上界绑到容量具名常量（`4096*8 + OQ*8 + mirror_fifo 2048 + 24`），或帮助文本写明"默认 24 仅在停源+排空到 early-stop 的终态有效"；② 顺手把 `:61` taken_bytes 注释"从镜像取走"改为"从上游 aux 口取走（P9 后 = URAM 缓冲）"（与 K3 同根）。

### K3（P2）计数点口径的权威注释陈旧两处（P9 后 dma_gnt 来自缓冲，注释仍写"从镜像取走"）

**位置**：
- `rtl/axis_c2h_stream.v:92-95`（头注释"⭐ `dma_words`/`MIR_DMA_CNT` 的口径 … **计数点 = 上游 aux 口** —— 数**从镜像 aux 口取走** (`dma_gnt`) 的 32 位字数"；`:7` "`dma_req`（本模块→镜像…)"）——P9 后该模块的 `dma_gnt` 来自 `u_mir_buf.dn_gnt`，数的是"**从缓冲取走**"。
- `_proj_pcie/p7b_biz/p7b_mir_dump.cpp:61-62`（同口径，见 K2 引用）。

**证据**：`wrapper_p4.v:3892-3894`（`u_mir_axis.dma_gnt ← mir_dma_gnt = u_mir_buf.dn_gnt`）现读；语义位移仅在 `mir_uram_fifo.v:266-270` 脚注与 `REPORT.md:102` 登记，**权威源注释（成形器头注释 = dma_words 合同的定义处）未更新**。

**影响**：后续维护者/审查者按成形器头注释推"从镜像取走 ⇒ 式 B 差额 = 镜像残余"会推出错误结论；合同文本与实现漂移属本仓自点名的"口径不登记"族。

**建议修法**：两处注释改为"从上游 aux 口取走（P9 板内缓冲轮之前 = 镜像，之后 = `u_mir_buf`）"，并指向 `mir_uram_fifo.v` 口径登记段。

### K4（P2）p6e 两个突变门未随 TB 功能改动重跑（编辑后 TB 的"仍被抓红"无证据）

**位置**：`sim/p6e_pcie/tb_p6e_pcie_wrapper.v` 本轮被功能修改（`:125-133` `P9B3_*` 具名常量、`:723-765` `P9-B-3d` 双边账/`:741` 基线显式读/排空等待 600→20000），`FIX_REPORT.md:313`（§7-4）自登 `run_tb_p6e_pcie_mut{,2}.bat` **未重跑**。现读 `run_tb_p6e_pcie_mut.bat:12-15`：其突变对象 = **wrapper 本体**（`mut_srcinv.py` 生成 `wrapper_p4_mut_srcinv.v`）+ 同一被改 TB 进编译闭包 ⇒ "TB 改动后突变臂照样抓红"这一性质本轮无读数。

**建议修法**：补跑两臂（各一条命令）；或至少在 FIX_REPORT §7-4 保留并升级为"门覆盖缺口"而非"未核"。

### K5（P2）缺突变臂（至少 2 类该有而没有）

现 12 臂逐一对照（§3 表）：全部集中在**写门/读门/计数器/clr 总开关/守卫**，64 位数据面与 clr 分支**内部**零覆盖。该有而没有的：

1. **clr 分支"部分清"臂**：`mut_clr_off` 只测整个 clr 分支封死（`:227-229`），无臂测"clr 漏清单个寄存器"——例如把 clr 分支里 `v_sr <= 3'd0;` 或 `o_occ <= 3'd0;` 删一行。后果：旧窗口 valid/占用泄漏进新窗口（clr 后第 1..3 拍 `v_sr[2]=1` ⇒ 旧字落弹性堆 ⇒ 幻影弹/seq_err），现有判据（G5d/GB3/G9e）**有牙但无臂证明**。
2. **弹性堆 FWFT 读出臂**：`dn_data = o_mem[op_r]`（`rtl/mir_uram_fifo.v:173`）+ 4:1 读出 mux + `o_mem[op_w]` 写入索引（`:234`）是数据通路唯一无臂单点；`mut_val1` 只动 valid 时序不动词/槽。建议臂：`o_mem[op_r]`→`o_mem[op_w]`（G1b seq_err 应红）。
3. （次要，登记即可）`o_occ` 更新项臂（`:236` 丢 `+arr_v` 或 `-pop`，G7a 应红）；XPM 接线臂（`.enb(issue)`→`.enb(up_req)`，G1b 应红）。

### K6（P2）G4/G8"随机"相位为固定种子单序列，无种子扫描

**位置**：`tb_mir_uram_fifo.v:96-97`（`lfsr_src=16'h1ACE` / `lfsr_dst=16'h2BDF` 写死）。每次 real 跑 = 同一相位图；TB 头注释自称"双侧独立 LFSR ⇒ 相位不成简单比例"，但**单个种子的"独立"不构成相位覆盖论证**。我的负对照模型用 8 个种子扫描（§5 S3）全部 0 错——说明该风险现役未兑现，但门的相位覆盖在结构上只有 1 个样本。低优先。

### K7（P2）`SIM_ASSERT_CHK(0)` 口径登记两轮未做

**位置**：`rtl/mir_uram_fifo.v:205`（`.SIM_ASSERT_CHK (0)`）。REVIEW F6② 点名 → `FIX_REPORT.md:305`（§7-1）自登"未做（不属本轮派单）"。关掉的是 XPM 行为模型的自带仿真断言（默认 1），无注释说明关了什么/为什么——按本仓"口径登记"纪律应在 XPM 例化注释处写一行。低优先。

### I1（信息）`issue`/`u_wr`/`arr_v` 三处 `!clr` 在现役结构下为冗余防御项（推演证明，非缺陷）

clr 拍 `issue=1`（若 `!clr` 被删）的唯一实效 = 对 URAM 的一次无效读：`v_sr` 被 clr 分支整块清零（`:228`，优先级吞移位）⇒ 该读数据永不被 `arr_v` 采；`rp` 被 clr 分支复位置零优先 ⇒ 指针无偏。`u_wr`/`arr_v` 的 `!clr` 同构（上游镜像 `flush_r`/写门结构性不会在 clr 拍给 gnt）。即 F4⑥（`arr_v` 的 `!clr` 不补臂）的同理可推广到这三处——防御纵深合理，但建议头注释注明"现役结构下冗余、防接线变更"，免得下一轮审查再把它们当功能项重推。`mut_dnclr`/`mut_clr_take` 的"洞"其实都经由下游/上游结构性关门闭合，臂的价值在"防回归"而非"现役可达"。

---

## §2 四条不变式逐状态对抗推演（任务书条款 1）

对 `rtl/mir_uram_fifo.v:147-238` 自画状态关系（`wp/rp` 13 位环、`v_sr` 3 位valid链、`o_mem/op_w/op_r` 4 槽环、`o_occ` 0..4），逐场景找反例：

| 场景 | 推演结论 | 反例 |
|---|---|---|
| clr × 在飞事务 | clr 拍 `up_req/pop/issue` 全 0（`!clr`）；`v_sr` 同拍清零 ⇒ clr+1..+3 拍旧 `ram_dout` 无效；`issue` 需 `occ!=0`，clr 后 occ=0 ⇒ 新窗口无读发起 | 未找到 |
| 连续 clr（背靠背 2 拍） | 两拍皆走 clr 整块清零分支，第二拍无任何状态可清之外的变化；释放后同单拍 clr | 未找到（GB 场景 + 模型 S3 中 clr 每 997 拍注入亦 0 错） |
| en 沿序列 | en 只门 `up_req`；1→0 当拍无 gnt（组合同拍）；0→1 恢复；`en=0` 期间缓冲内容/账目不动，读侧语义保持 | 未找到 |
| 复位中途释放 | `rst_n` 异步 assert、同步生效；释放时全部寄存器已清零；XPM 本体不复位但 `v_sr=0` ⇒ 旧值永不弹；F2 修复后复位期 `up_req=0` 结构性成立（不依赖跨模块不变量） | 未找到（GR 场景 + 模型 S3 中途复位 8 种子 0 错） |
| 地址绕回（AW wrap） | `wp/rp` 13 位、8192 绕回；`occ=wp−rp ≤ 4096 < 8192` ⇒ 模减精确；写读同址 ⟺ `occ∈{0,4096}`，空无 issue、满无写 ⇒ 结构性不相撞 | 未找到（G8 24000 拍 + 模型 8×6000 拍跨多次绕回） |
| 满-空互斥 | `occ` 单值不可既 0 又 4096；ufull⇒`up_req=0`（合同保证无 gnt，守卫②兜底）；空⇒`issue=0`；弹性堆侧 `inv≤CAP` 归纳成立（`inv′=inv+issue−pop≤CAP`，`inv−pop` 4 位下溢方向为关断=安全） | 未找到 |
| 到达拍弹性堆满 | 到达 ⇒ `v_sr[2]=1` ⇒ `inflight≥1` ⇒ `o_occ=inv−inflight≤3<OQ`；`o_occ=4∧arr_v` 组合不可达（守卫①兜底） | 未找到 |
| clr 在飞时 level 怎么报 | clr 拍 `occ` 组合值仍在，但 `up_req=0` ⇒ 上游不再取数；沿后 `occ=0`；`dbg_*` 为纯线束 | 口径自洽（K1 不涉及） |

**结论**：现役配置下四条不变式未发现可违反时序；唯一两处历史破洞（F2 复位窗、F3 clr 拍 dn 侧）已由 `f46a221` 结构性关闭且有臂实证。clr 语义 up+dn 两侧完备（F3 修法 `pop &&= !clr` + 镜像 `flush_r` 双门关 up 侧，模型 S4 复算 clr 拍 `dn_gnt≡0`）。

---

## §3 门质量核查（任务书条款 4）

**12 突变臂逐臂核对**（`diff rtl/mir_uram_fifo.v sim/p9_uram/mut/*.v` 每个恰 2 行 diff = 恰 1 处替换；生成日志 `hits=1 (want 1)`；锚点与现 RTL 逐字一致）：

| 臂 | 改动行 | 打到的设计点 | 是否有牙（判据） |
|---|---|---|---|
| mut_full_off | up_req 去 `!ufull` | 满覆盖未读字 | G2a/G2b + 守卫② |
| mut_full_e1 | UFULL−1 | 容量锚 | G2a（仅 1 条，白盒钉容量） |
| mut_issue_free | issue 去 CAP 门 | 到达覆盖弹性堆 | G2a/G2b + 守卫①×3460 |
| mut_val1 | arr_v 取 v_sr[1] | 读流水对拍 | G1b seq_err |
| mut_clr_off | clr 分支封死 | 窗口丢弃 | G2g/G3e + 逐字对账 |
| mut_clr_take | up_req 去 `!clr` | clr 拍取数 | G5c/GB1 |
| mut_dnreq | dn_gnt=dn_req | 幻影弹 | G1b/G1c/G3b |
| mut_rstn_off | up_req 去 `rst_n` | 复位期取数 | GR1/G9g（=10，直接量到） |
| mut_en_off | up_req 去 `en` | 停排空取数 | G6a |
| mut_dnclr | pop 去 `!clr` | clr 拍弹旧头字 | GC1/G9f（=3，直接量到） |
| mut_wp_nmc | wp 增量丢绕回位 | AW 绕回计数 | G2a=200/G8 |
| mut_guard_off | 删守卫③ `$display` | 守卫盲化对照 | guard_rogue 配对 |

**空判据扫描**：59 条判据逐条过——G5a/GC0/GB0/GR0 的 `lo=1` 是刺激前置（悬空字存在性），非恒真；G2b/G2d2/G3d/G3f/G4a/G7a/G8a 为区间型真实约束；G2f/G8d/G9e 为终态账闭合（身份式，非恒真——`mut_issue_free` 下确实不闭合）。未发现结构性恒真判据。
**同源 oracle 扫描**：期望队列 `eq_mem` 写入的是源模型独立生成的 `src_word`（`tb:116`），与被测内部数据通路无任何共享逻辑；不是同源 oracle。✓
**打点评审**：12 臂全部打到声称的设计点，无打到无关行者；缺臂见 K5。

---

## §4 本捆未发现问题的方面（覆盖面声明）

- **本捆未发现 X 类问题（P0 = 数据错/合同破的反例）**：覆盖面 = rtl/mir_uram_fifo.v 全部 275 行逐行 + §2 八场景状态推演 + 8 种子逐拍模型 4.8 万拍对账 0 错。合同四件套逐字核：aux 合同（wrapper 3777-3834 现读 + `app_rx_mirror.v:412` gnt 蕴含 req）、`MIR_DMA_CNT` 口径（计数器留成形器、位移已登记）、**不新增丢字节计数器**（`grep -ni drop rtl/mir_uram_fifo.v` 仅 2 处注释、无计数逻辑，唯二观测口 `dbg_*` 空接）、读侧语义（`en=0` 不取数 + `axi_regs` 复位域/`mir_ctrl_r` 复位 0 现读 `_proj_pcie/rtl/axi_regs.v:224-252` + `wrapper_p4.v:4759` 同一条 `pcie_axi_aresetn` 核实）。
- **本捆未发现 X 类问题（XPM 用法三类）**：覆盖面 = `xpm_memory.sv` 读管道源码独立复核（`enb_pipe[0]<=enb`、末级 `regceb` 门控、`doutb=doutb_pipe[LAT-2]`）+ 模型 S2/S3 对拍。`READ_LATENCY_B=3` 与 `v_sr` 3 级逐拍对齐（发起拍 T ⇒ doutb 拍 T+3 ⇒ `arr_v` 同拍）；`read_first` 同址前提成立（`occ∈{0,4096}` 互斥，§2）；`MEMORY_PRIMITIVE("ultra")` 落 URAM288 的保证链 = XPM 参数合同 + 容量自洽（`MEMORY_SIZE=262144 bit ≤ 288 Kb`，4096×64 恰单条）——**且已由审查轮之后的构建 0x24（提交 `09e34a6`）实证**：`URAM288=1`、网表点名 `u_mir_buf`、`BRAM 不增`。设计件"未综合未测"声明在其成文日期下成立，此项现已被后续构建闭合。
- **本捆未发现 X 类问题（门基础设施）**：覆盖面 = bat 全文 108 行 + F1 自测三腿证据件 + namecheck.py。F1 三段硬证据（判决行存在 ∧ 无 PASS_ALL ∧ [FAIL]∨守卫串，否则 INFRA-FAIL）+ 崩溃形态/假 PASS 形态双自测；判据名 ≤32 纯 ASCII（namecheck 59/59）；臂分派 goto 化规避 set 尾随空格坑；xpm 库本地编译 + `for /f` 管道坑改为独立 py——均已实现且有跑过的证据。
- **本捆未发现 X 类问题（F2/F3 修法本身）**：覆盖面 = `rtl/mir_uram_fifo.v:155,169` 两行功能 diff + 双处登记注释（RTL 写门处 + `wrapper_p4.v:3848-3853` 例化处）逐字核。`rst_n` 并入写门后复位期取数通道结构性关闭且不再依赖"`en` 同域复位 0"跨模块不变量（该不变量仍登记为双保险）；F3 `pop &&= !clr` 对现役行为零影响（下游 `clr_drop` 本已关门）、对未来消费者自足。
- **本捆未发现 X 类问题（wrapper 接线 4 处的功能正确性）**：覆盖面 = `git show 257c911` 功能 diff + 现读 3777-3901。`u_mir` 三 aux 线改指 `u_mir_buf.up_*`、`u_mir_buf.dn_*` 接 `u_mir_axis` 原三线（线名照旧 ⇒ 成形器例化一字未改）、`en`/`clr`/`clk`/`rst_n` 四线接法与两侧模块复位域/时钟域一致；`f46a221..HEAD` 净差仅 BUILD_ID 0x23→0x24（`:4317`）⇒ 本捆读数绑定关系未被后续提交打破。

**没看什么（诚实声明）**：`diag_p9b3d/` 的 files.f/xvlog 逐行未核（只核了结论与 TB diff，同 REVIEW 边界）；`sim/p6e_pcie/run_tb_p6e_pcie_mut{,2}.bat` 历史行为未核（K4）；`xpm_memory.sv` 的 URAM DRC（40-3/40-8）分支未逐行展开（信 XPM 参数合同 + 后续 0x24 构建实证）；p6e TB 其余 ~900 行未逐行读（只读了 P9B3 块与计数器块）；未重跑任何门（只读审查，复用了 `gate_stdout_fix/` 证据 + 自写模型）。

---

## §5 负对照构造验证（任务书 neg_ctrl）

**脚本**：`_proj_10g/notes/p9_xreview_kimi_20261013/negctl_occ_model.py`（新建，只读运行；忠实复刻 `rtl/mir_uram_fifo.v:147-238` 的寄存器语义 + XPM"LAT=3、空闲保持旧值"行为模型；独立参照 FIFO 逐字对账）。
**输出**：`_proj_10g/notes/p9_xreview_kimi_20261013/negctl_occ_model.out`（完整跑通存档）。核心输出：

```
== S1: 最大占用 (dn_req=0, 源常就绪, en=1, 无 clr) ==
  [PASS] O_max(occ+inv) == 4100 字, 实测 = 4100 (occ,o_occ,inflight)=(4096, 4, 0) @cyc4100
  [PASS] occ 分量取到 4096 (ufull 同拍 inv=4)
== S2: 稳态吞吐 (源常就绪, dn_req=1) ==
  [PASS] 300 拍弹 300 字 (1 字/拍), 实测 = 300
== S3: 多种子随机相位扫描 + 逐字对账 (超出 TB 的固定种子覆盖) ==
  [PASS] seed=0..7: 逐字对账 seq_err=0 over_err=0  (丢/重/错序全 0)
  [PASS] seed=0..7: clr 拍弹字 clr_pop=0 / 复位期取数 rst_take=0
  [PASS] 全部种子 inv<=CAP(4), 实测 max=4 / occ<=4096, 实测 max=775
== S4: clr 拍 dn_req 保持 1 (F3 语义复算) ==
  [PASS] clr 拍 dn_gnt 强制 0, 实测 = 0
== S5: 式 B 中途上界复算 ==
  [INFO] O_max = 4100 字 = 32800 B
  [INFO] 式 B 真中途上界 = 镜像残余(<=24 B) + O_max = 32824 B ; 默认 24 差 1367 倍
RESULT: ALL-PASS (fails=0)
```

**结论**：K1（4099→4100、occ 与 inv 可同时取满）与 K2（中途上界 32824 B）构造性成立；附带独立复证了 1 字/拍吞吐、四不变式在 8 组随机相位 + clr + 中途复位下 0 违例、F2/F3 语义。

（方法注：模型初版 S3 曾现 1465 seq_err/种子，定位为**建模 bug**——读管道被建成每拍无条件移位、空闲不保持，与 RTL 注释"空闲 doutb 保持旧值"不符；修正为 3 级保持式延迟线后全过。此过程即负对照的本意：先证明模型能抓住"读延迟错位"类缺陷，再用它给设计算账。）

---

*本件 = 发现清单 + 构造验证 + 覆盖面声明；裁定权归 TL/owner。*
