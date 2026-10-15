# p9_simfill_20261015 —— sim 补测轮报告（A = mdio A+ 变体臂 E7/E8 · B = F-3 N-2）

> **agent 原件由平台拒写 .md ⇒ 全文回传、TL 代落盘**（本件正文 = agent 原文；文末「TL 附加」= TL 独立抽核记录）。

| 项 | 值 |
|---|---|
| 轮名 | `p9_simfill_20261015`（派单来源：台账 §10-74 的"sim 补测[mdio A+ + F-3 N-2]"四轮之一） |
| 日期 | 2026-10-15 夜（全部读数取自 23:05–23:29 本机） |
| 性质 | **纯仿真/文本**：零构建、零上板、零 Vivado、零碰对端机、零 git 写、零台账写 |
| 状态一行话 | **A：A+ 变体臂已按 §2.2/§4.3 做成 xsim 臂并全绿（基臂 2 DUT 10 判据 PASS；两个负对照按设计各自红在预定格）**；**B：N-2 的 I5′ 默认关臂已实测（2×2 = 4 臂同会话全按设计：OFF×SOP-less 逐字复现 pre-F-3 基线 + PASS_ALL；ON×SOP-less 逐字复现历史红形）**；两部分的"位流构建 + 板测"（A 必需、B 不需要）已明确登记为**后续轮** |
| 交付 | 本目录：本报告 + `READINGS_A_mdio_aplus.txt` + `READINGS_B_f3_n2.txt` + `A_mdio_aplus/{src,logs,gate_stdout.txt}` + `B_f3_n2/{src,logs,gate_stdout.txt}` + `stage2_apply/`（A 的后续轮产物）+ `SHA256SUMS.txt` |

**一手依据（全部只读引用，未改动）**：
`_proj_10g/notes/p9_fix_mdio_design_20261014/DESIGN_v2r4.md`（= v2r2 + v2r3 + v2r4 按序读；§2.2 E7/E8、§4.3 A+ 臂、§4.2-J-D）·
`p9_fix_mdio_impl_20261015/REPORT.md`（§4-D：E7/E8 未做 ⇒ 变体臂"尚不可做"）· `p9_mdio_board_20261015/REPORT.md`（§7-1 板级缺口）·
`p9_fix_f3_design_20261014/DESIGN_v2r4.md`（§2 N-2/N-3；v2r2 §1-3b 的 I5′ 原文；v2r3 §1-4 的证伪配方）·
`p9_p6e_h1fix_20261015/`（H1 收口读数与 2 份 SALVAGED preF3 基线日志）。
**设计件目录全程只读**；`_proj_mdio/**` 全程未改（只读拷贝；`find _proj_mdio -newermt 2026-10-15 23:00` 零命中——写者不是我）。

---

## §A mdio A+ 变体臂（E7/E8）—— 已完成：设计 + 仿真 + 门

### A-1 改动清单（新目录 = `sim/mdio_aplus/`；**本目录外零写**）

| 件 | 作用 | 关键 sha256 |
|---|---|---|
| `mdio_vio_top.v` | `_proj_mdio/rtl/mdio_vio_top.v`（E1–E6 后，`79c360f8…`）的**工作副本 + E7**：`module mdio_vio_top #(parameter integer DIV = 25) (...)`、`.DIV (DIV)`。默认 25 ⇒ 生产 elaboration 不变（设计件要求） | `4416710a230ff582af999f3b4348812c007638b8497fcbec3ee52b462e9864df` |
| `mdio_master.v` | `_proj_mdio/rtl/mdio_master.v` 的**逐字节冻结副本**（两新位 RTL 在此，未动） | `89d5c89e295ce988b2013ecdb07f94d158001e0ef1e5585020f82e481f8d35db` |
| `vio_0_sim_stub.v` | **仿真用** vio_0 桩：22 位 `probe_in0`（与 E2/E6 同步）+ `probe_out*` 为可被 TB 层次写入的 reg（= 模拟"宿主写 VIO 输出"） | 见 SHA256SUMS |
| `tb_mdio_aplus.v` | 顶层功能 TB：**同一 elaboration 内两个 DUT**——`u_prod`（E7 默认，无覆盖）与 `u_var`（`#(.DIV(65537))`）；两新位都在 **cable-end 位置** `u_*/u_vio/probe_in0[21:20]` 读（= 经过真拼接的顶层接线测试，`tb_mdio_master.v` 结构上做不到） | 见 SHA256SUMS |
| `mut/mk_mut_aplus.py` + `mut/mut_zero.v` + `mut/mut_swap.v` | 负对照（有牙）生成器：锚点**恰好一次**替换，否则硬停。`mut_zero` = 两位接 `1'b0`（**正是设计件 §4.2-J-D 点名的"出现且恒 0 与未接线不可区分"形态**）；`mut_swap` = 两位互换 | zero `5184c719…` / swap `d0b2ce49…` |
| `run_mdio_aplus_gate.bat` | 硬门：自定位 + 根 tripwire + xsim 串行纪律 + 逐臂编译/仿真 + **逐字 grep 判据** + 退出码 0/1/97；基臂还核 DUT sha256 | 见 SHA256SUMS |
| `mk_e7_top.py` / `mk_stage2_artifacts.py` | E7 生成器 / E8 与后续轮产物生成器（后者写 `stage2_apply/`） | 见 SHA256SUMS |

### A-2 臂与全读数表（`gate_stdout.txt` + `logs/xs_base.log`）

设计件 §4.3 的 A+ 臂是**板臂**（变体位流 + 烧录 + VIO 读），本轮禁开 Vivado ⇒ **臂原样搬到 xsim**：同样两个 DUT 配置、同样三个问题（P1 `param_bad` / P2 事务时长 / P3 `stat_start_lost`），只是把"JTAG commit"换成"精确到拍的 VIO 输出写"。

| 字段（读点） | PROD（DIV=25，**取默认值**） | VAR（`#(.DIV(65537))`） | 说明 |
|---|---|---|---|
| `pbad_t0` bit20 | 0 期望 / **0 实测** | **1 期望 / 1 实测** | **P1 等价物**；VAR 侧 = `param_bad` 的**最小正控见证**（无任何激励，一次读） |
| `ssl_t0` bit21 | 0 / 0 | 0 / 0 | **负对照：不激励时应 = 0**（两臂都在此列） |
| `ssl_mid` bit21 | 0 / 0 | 0 / 0 | 首帧忙期内、丢 start 之前 = 0 |
| `ssl_drop` bit21 | 1 / **1** | 1 / **1** | **P3 等价物**：忙期来一个 start 上升沿 ⇒ 粘滞置 1（**最小正控见证**） |
| `sticky_end` bit16 | 1 / 1 | 1 / 1 | 帧尾 `done_sticky` 检出（顺带证明读点确实在跑） |
| `ssl_clean` bit21 | 0 / 0 | 0 / 0 | 干净 start 被接受 ⇒ 清位（设计件 §4.3-P3 的收尾判据） |
| `sticky_clr` bit16 | 0 / 0 | 0 / 0 | 同上（`done_sticky` 同拍清） |
| `frame_cyc` | 3200 / **3200** | 8388608 / **8388608** | **P2 等价物**：=`128 × DIV_SAFE`；PROD 3200 拍 = 32 µs、VAR 8388608 拍 = **83.886 ms**（把设计件"≈83.9 ms"逐位坐实） |
| `mdc1_cyc` | 25 / **25** | 65536 / **65536** | 接受→首个 MDC 上升沿 = `DIV_SAFE`（**钉死"钳到慢端"**：若发生旧的静默截断 `DIV[15:0]`，此处会读 1） |
| `mdct_cyc` | 50 / **50** | 131072 / **131072** | MDC 上升沿间期 = `2 × DIV_SAFE` |
| 臂判定 | `APL VERDICT PROD=PASS` | `APL VERDICT VAR=PASS` | `APL VERDICT ALL=PASS`；门 `MDIO-APLUS-GATE: PASS`（RC=0） |

**跨配置对照（设计件 P1 的本意）已成**：同一次 elaboration、同一份 RTL、只差 `DIV` 一个参数 ⇒ bit20 从 0 翻到 1、帧长拉长 2621.44×。**"板上正控只此一路"的那两格，在仿真层第一次被直接观测到。**

### A-3 负对照（有牙；两条都按设计红在预定格）

| 变体 | 改法（锚点×1） | 期望 | 实测 |
|---|---|---|---|
| `mut_zero`（= §4.2-J-D 点名的形态） | 拼接 `{stat_start_lost, param_bad, mdio_i, …}` → `{1'b0, 1'b0, mdio_i, …}` | `ALL=FAIL`，洞恰在 `{PROD ssl_drop, VAR pbad_t0}`（＋连带的 `VAR ssl_drop`） | `ALL=FAIL`；PROD mism=1 / VAR mism=2；三条 MISMATCH 逐字如上；PROD summary 只翻 `ssl_drop=0`（其余字段与基臂逐字同） |
| `mut_swap`（打包顺序回归） | → `{param_bad, stat_start_lost, mdio_i, …}` | `ALL=FAIL`，含特征洞 `VAR ssl_t0`（exp=0 got=1） | `ALL=FAIL`；PROD mism=1 / VAR mism=4；含 `VAR ssl_t0/MID/CLEAN` 三条 exp=0 got=1 |

⇒ 门的两条承重判据（bit20=param_bad、bit21=stat_start_lost 的**位序**）都有牙；`mut_zero` 恰好证明"把两位钳 0"会被本臂抓住 —— 这正是板级生产臂读数为"出现且恒 0"时**唯一能把"真 0"与"未接线"分开**的那一格。

### A-4 与设计件的关系（逐条）

- §2.2 **E7**：已按原文实施（改后锚点 `:31`/`:128` 对应处 = 我的副本 `module … #(` 与 `.DIV (DIV)`）；默认 25 保持 ⇒ 生产构建不受影响（**未构建，故"生产 elaboration 不变"只有文本证据，登记为后续轮的构建判据之一**）。
- §2.2 **E8**：`build_mdio_divbad.tcl` 已生成（见 `stage2_apply/`）：相对 `build_mdio.tcl` 的差异 = **恰好 3 处**（头注释 + `pj_mdio`→`pj_mdio_divbad` + `update_compile_order` 后插入 synth generic `DIV=65537`）——即设计件要求的 2 处改动 + 1 处注明。**未运行**（需 Vivado）。
- §2.3 备选路径（变体独立顶层）**未采用**（设计件明确"二选一即可，不要两条都做"）；我做的是 E7 参数化路线，但仿真里用**实例级参数覆盖** `#(.DIV(65537))` 代替 E8 的综合 generic `-generic_top` —— 两者对同一参数的语义等价，**`-generic_top` 路径本身未实测**（登记）。
- §4.3 P1/P2/P3 的两格已在仿真层拿到读数（上表）；**板上那三格仍未做**（见 A-5）。
- §4.2-J-D / §7-R-b 的"恒 0 与未接线不可区分"：本臂给出了**仿真层的分离见证**（基臂 0/1 二值 + mut_zero 必红）；**板级生产臂的"出现且恒 0"仍是未闭合项**（板上仍无正控——只有变体位流能给）。

### A-5 后续轮（**明确登记的回报范围**；本轮故意不做）

1. **变体位流构建**：按 `stage2_apply/APPLY_STEPS.txt` ——（0）先归档现 `pj_mdio`（#54）→（1）把 `stage2_apply/mdio_vio_top.v` 覆盖 `_proj_mdio/rtl/mdio_vio_top.v`（sha 4416710a…）→（2）拷入 `build_mdio_divbad.tcl` →（3）两次构建（生产 + 变体）→（4）登记两 sha（**R9：变体位流 sha 必须与生产臂不同**）。
2. **板测 A+ 臂**：烧变体位流后跑 §4.3 的 P1（bit20=1）/ P2（事务 ≈83.9 ms、MDC 762.9 Hz）/ P3（忙期 start ⇒ bit21=1，干净 start ⇒ 0；重试 ≤5，如实记"未触发"）。⚠️ 本报告不能替代它：**仿真观测 ≠ 硅上观测**。
3. 生产位流的 `param_bad=0` / `ssl` 恒 0 仍需与变体臂构成跨构建对照才有意义。

### A-6 A 的"未做 / 未观测"（"未观测到" ≠ "不存在"）

- **未做**：变体位流构建与烧录 · 板上 P1/P2/P3 · 真 `vio_0` IP 核与 JTAG commit 延迟（仿真用桩）· `.ltx` 探针名/宽度核对（属于构建轮）· `-generic_top` 路径 · E8 脚本的语法级运行（无 Vivado）。
- **未观测**：PHY 行为（本臂 MDIO 线只有 pullup，读数据未判；无 PHY 模型）· 330 ms `phy_rstn` 计数器（不门控 mdio_master，未等待）· 真实宿主 commit 间隔（数十 ms）与 32 µs 忙窗的对比（设计件的动机论证，仿真里未复现该约束）。
- **本轮范围外（如实声明）**：未碰任何 `rtl/**`、`board/**`、`_proj_mdio/**`、门 `gate_elab_22/`（B3 已封口，只读引用）。

---

## §B F-3 N-2（I5′ 默认关臂）—— 已完成：实测（零构建）

### B-1 改动清单（新目录 = `sim/f3_resync/n2_arm/`；**`sim/p6e_pcie/**` 一字未动**）

| 件 | 作用 | 关键 sha256 |
|---|---|---|
| `mk_wr_n2.py` | 由**当前树** `board/wrapper_p4.v` 生成两份副本：`wr_off/wrapper_p4_resync0.v`（锚点恰好一次：`:720` `VLAN_STRIP_RESYNC = 1'b1;` → `1'b0; // N-2 arm FROZEN-OFF …`）· `wr_on/wrapper_p4.v`（逐字节副本，用作同会话 ON 对照） | off 副本 `3d53d7c9…`；on 副本 = 树件 `bbf6e3cb…` |
| `frozen/tb_p6e_pcie_counters.FROZEN.v` · `frozen/xdma_0_sim_stub.FROZEN.v` | 计数器门的 TB/桩**冻结副本**（运行内与 `sim/p6e_pcie/` 现读逐字节比对：`FROZEN-TB-MATCH` / `FROZEN-STUB-MATCH`）——防"另一个 agent 正在写 p6e_pcie"污染本臂取证 | `ab54d5e0…` / `65fc292d…` |
| `mk_tb_nosop.py` | 由 FROZEN TB 生成 **NOSOP 变体 TB**（锚点恰好两处：H 段开场 `tuser` force `1'b1→1'b0`；H0 见证条件同步改）——**= 5 份历史 backup 所用的"旧激励"形态** | `fda3ea56…` |
| `run_n2_arm.bat` | 硬门：自定位 + 根 tripwire + xsim 串行纪律 + **臂身份前置核**（OFF 副本必须有 FROZEN-OFF 标记且 `1'b1` 零命中；NOSOP TB 必须有标记）+ 逐臂**文件表重定向**（原门 `:20` 的等价行）+ 逐臂编译/仿真 + 逐字判据 + 退出码 0/1/97 | 见 SHA256SUMS |

**与设计件 N-3 的偏差（如实登记）**：设计件说"若做 N-2，须同改 `run_tb_p6e_pcie_counters.bat:20`"——但该文件在 `sim/p6e_pcie/`（本轮禁区，且另一 agent 正在写）。⇒ 我把**同一段命令序列在自己的目录里重建**，只把那一行（wrapper）指向副本；**原门保持不动**。语义完全一致（friction (a) 的要求被满足：编的确实是副本，不是原 wrapper），但**下游若按 N-3 字面找 diff 会找不到**——这就是本条存在的原因。

### B-2 四臂读数表（`gate_stdout.txt`；2×2 = `VLAN_STRIP_RESYNC` × 激励形态）

| 臂 | wrapper | TB（激励） | 期望 | 实测 |
|---|---|---|---|---|
| `off` | `3d53d7c9…`（RESYNC=**0**） | FROZEN（H1 后：开场带 SOP） | `PASS_ALL` + `W26=69 W27=256` + `W30=257 W31=2056` | **全中**（`[PASS] arm off`，RC=0） |
| `on` | `bbf6e3cb…`（树件，RESYNC=1） | FROZEN | 同读数（同会话对照；H1 修复后 ON 臂亦回基线） | **全中**（RC=0） |
| `off_nosop` | `3d53d7c9…`（RESYNC=**0**） | NOSOP（**历史 SOP-less**） | 同读数 | **全中 + `PASS_ALL`**（RC=0）—— **★ I5′ 的判别臂** |
| `on_nosop` | `bbf6e3cb…`（RESYNC=1） | NOSOP | 必须红（激励变量的正控） | `W26=3 W27=5` / `W30=320 W31=2560` + `FAIL tb_p6e_pcie_counters: 1 项失败`（RC=0） |

**基线/红形的逐字对照（不是同一会话，是归档件）**：
- pre-F-3 基线（2 份 `SALVAGED_preF3_cnt_*.log` + 3 份更早 backup，逐字相同）= `W26=69 W27=256 W30=257 W31=2056` + `PASS_ALL` ⇒ **`off` 与 `off_nosop` 逐字复现**（门判据即这四个数与 `PASS_ALL`）。
- 修前失败形（`xsim_p6e_cnt_PREFIX_011001.log`）= `W26=3 W27=5 W30=320 W31=2560` + FAIL ⇒ **`on_nosop` 逐字复现**。

### B-3 单变量证据（同会话、同树）

- 四臂均在 **HEAD `730c99e153bf4593a307c015a98e4f2cae964ecb`** 上跑（运行内 `git rev-parse HEAD` 见证；四份 `git_head_*.txt` 逐字相同）。
- `files.f` 逐臂 **218 件**；**`off` vs `on` 的指纹 diff = 恰好 1 个文件**（wrapper 副本那两行）⇒ 两臂可归因于那一个 `localparam`。
- wrapper 副本 vs 树件 diff = **恰好 1 行**（`:720`）。
- FROZEN vs NOSOP TB diff = **恰好 2 行**（H 段 tuser force + H0 见证条件）；流/计数/判据一字未动。

### B-4 与结构证明的一致 / 差异（逐条）

**一致**：
1. I5′ 的结论（`RESYNC_EN=0 ⇒ fwd≡1 ⇒ 行为与 F-3 前逐字相同 ⇒ 门的历史读数原样复现`）在**读数层**成立：`off_nosop` 与 `off` 都给出 `69/256/257/2056` + `PASS_ALL`，且与归档 pre-F-3 读数逐字相同 ⇒ **I5′ 未被证伪**、I1 在该门成立（行为层）。
2. 设计件的"便宜证伪路径"（喂副本 ⇒ 重跑 ⇒ 期望逐字回到历史读数；**身份格按现树、不参与判据**）已按其字面执行；`on_nosop` 同时证明"这套装置确实能把缺陷打出来"（否则 `off_nosop` 的绿是空判据）。
3. 与 v2r3 §1-4 的期望形态一致：功能读数 = `69/256/257/2056`；`H1` 等判据在 ON×SOP-less 下红、在 OFF 两臂全绿。

**差异 / 边界（不许写大）**：
1. **测量层级**：本臂量的是**门的读数 + 26 条判据的裁决**（`PASS_ALL`），**不是逐拍位级流比对**——"逐位等价"本身仍是结构证明（I1，经复核）；没有本轮的独立位级见证（未做，登记）。
2. **对照物是归档读数、不是重跑 pre-F-3 RTL**：`verbatim` 是相对 5 份归档日志的**读数**；本轮 wrapper（`bbf6e3cb`，含 E12 等后续改动）**晚于**当年那批。故严格口径 = "**在现行 wrapper + 现行 TB 下，两臂返回与归档一致的四个功能读数**"，而不是"F-3 前后同一份网表逐位相同"。
3. **`chk()` 名截断（仪器自身的坑，实测）**：`tb_p6e_pcie_counters.v` 的 `chk` 用 `input [255:0] name` + `%0s` ⇒ 长中文检查名被**截到末 32 字节并弄坏 UTF-8**，日志里 `[FAIL] H1 W27 == DEPTH` 这种 ASCII 前缀**根本不在**（我第一版判据就据此假红了一次，已改锚到实测读数 `W26=3 W27=5`）。⇒ 任何按 `chk` 名做 grep 的判据都不可靠（本报告把它登记为仪器文档缺口）。

### B-5 B 的"未做 / 未观测"

- **未做**：逐拍位级差分（pre-F-3 RTL vs `RESYNC_EN=0`）· 全链门（`run_tb_p6e_pcie.bat`）的对应臂 · 板级任何东西（N-2 本就零构建）· 原门 `sim/p6e_pcie/run_tb_p6e_pcie_counters.bat` 的任何改动。
- **未观测**：`chk` 截断现象对其它已有门日志的影响面（只登记本门）· 218 件编译集里其它 agent 文件的语义变化（指纹只证"没变"，不证"对不对"）。

---

## §C 异常与偏离（含环境坑）

1. **⚠️ GNU `find` 陷阱（本轮实测，代价 = 一次约 10 min 的假挂起）**：bat 里写 `find /c /v "" file` 时，**从 git-bash 调 `cmd //c` 的环境里 `find` 解析到 Git 的 GNU find** ⇒ 它把 `/c` `/v` 当路径**递归扫整盘**，写出 37 MB 且持续增长的日志（表现为"门 10 分钟不结束"）。已改为 Python 计数并**在 bat 里留了警示注释**。⇒ 与"`cmd /c` vs `cmd //c` 是条件式的"同族：**bat 里凡是与 GNU 工具同名的内建/命令都要先想一遍**。
2. **树在轮中移动（其他 agent）**：轮开始时（23:05）HEAD = `a8420f6` / wrapper = `305123dc…`；约 23:07–23:11 其他 agent 的 E12 实施轮落地（HEAD → `730c99e`，wrapper → `bbf6e3cb…`，±75 行）。⇒ 这正是 B 轮**用冻结副本 + 运行内指纹 + 运行内 HEAD 见证**的理由；**归档的 B 四臂全部在 `730c99e`/`bbf6e3cb` 上**；其后 HEAD 继续推进到 `55a4184`（与本轮读数无关，但**复现时必须重核 `FP-AGG` 与 wrapper sha**）。
3. **"跑门期间禁改源"的部分不可控**：我无法阻止别的工作流在我跑门时改树（grep 见证：`sim/p6e_pcie/` 在 23:13 有别人的 xvlog 产物）。缓解 = 自建目录 + 冻结副本 + 指纹；**若读者要复现，必须重核本轮 `FP-AGG`**。
4. **A 侧一处自伤**：`run_n2_arm.bat` 的第二次编辑曾留下一个多余引号（`""%PY%"`），表现为 python 计数行不执行而 `type` 显示**上一次运行留下的旧值**——正是"跑了却没跑"的老形态。已修（最终归档日志逐字干净）；登记以提醒"读到的行必须来自本次运行"。
5. **平台/工具**：本报告由 agent 写盘被平台拒（`.md` 报告类）⇒ **正文全文回传，由 TL 代落盘**到本目录 `REPORT.md`。

## §D 命名决策登记（派单要求）

| 新路径 | 理由 |
|---|---|
| `sim/mdio_aplus/` | A 的 sim 目录：`mdio` + `aplus`（A+ 臂），与既有 `sim/f3_resync/` 同级；脚本/TB/桩/变异体/门/生成器全在此 |
| `sim/f3_resync/n2_arm/` | B 放在**既有受派目录树内**（`sim/f3_resync/**` 是本轮所有权），`n2_arm` = N-2 臂；其下 `frozen/` `wr_off/` `wr_on/` `run_<arm>/` |
| `_proj_10g/notes/p9_simfill_20261015/` | 轮目录（派单指定名）；`stage2_apply/` = A 的后续轮(构建+板测) ready-to-apply 产物 |
| `_proj_mdio` 相关 | **零改动**；E7 的落地方式 = 由后续轮把 `stage2_apply/mdio_vio_top.v` 拷过去（生成器 `mk_e7_top.py` 已把同一文本产出到两处，sha 相同） |

## §E 未做 / 未观测（汇总，两部分合并）

- **必须由后续轮承担**：A 的**变体位流构建 + 板上 P1/P2/P3**（本报告只到"设计 + 仿真 + 门"）；生产臂的"出现且恒 0"与变体臂的跨构建对照。
- **本轮明确未做**：任何 Xilinx 构建（Vivado 全程未开）· 板/对端机接触 · git 提交 · 台账写 · 对 `rtl/**`、`board/**`、`sim/p9_swc_gate/**`、`sim/p4gates/**`、`sim/p6e_pcie/**`、设计件目录的任何写。
- **未观测（≠不存在）**：真 VIO/JTAG 行为 · PHY 行为 · 位级流等价的逐拍见证 · `-generic_top` 路径 · 板级任何读数 · 其它门是否也受 `chk` 名截断影响。

## §F 一句话状态

**A：E7/E8 已按设计件实施（E7 落到工作副本、E8 落到 `stage2_apply/`），A+ 臂在 xsim 上全绿且两个负对照都有牙 —— "位流构建 + 板测"是明确登记的后续轮；B：I5′ 的默认关臂已实测且 2×2 四臂同会话全按设计 —— OFF×SOP-less 逐字复现 pre-F-3 基线（`69/256/257/2056` + `PASS_ALL`），I5′ 未被证伪，且 ON×SOP-less 逐字复现历史红形证明该装置有判别力。**

---

**收尾核查（已做）**：0 残留 xsim/xelab/Vivado 进程 · `git status` 跟踪面零改动（无需 `git checkout --`）· 我的新增仅 3 个未跟踪目录（`sim/mdio_aplus/`、`sim/f3_resync/n2_arm/`、轮目录）· `_proj_mdio` 与 `sim/p6e_pcie` 在我运行窗口内零写入 · 所有 bat 均为 ASCII+CRLF。

**与派单描述的两处不符（如实报告）**：① B 的设计件 N-3 指的是 `sim/p6e_pcie/run_tb_p6e_pcie_counters.bat:20`（本轮禁区），并非 `sim/f3_resync/` 内文件——我在自有目录重建了等价 runner（见 §B-1 偏差条）；② A 的"变体位流"确为 E7/E8 的目的（设计件 §2.2 逐字"两个新位的板上正控只此一路"），本轮只做到设计+仿真+门，构建+板测已按派单要求登记为后续轮（`stage2_apply/APPLY_STEPS.txt`）。

----------------------------------------------------------------

## TL 附加（2026-10-15 24:3x；独立抽核记录）

- **抽核**：写面 = 恰 3 个新目录（本轮两项 + 轮目录；RV2 的目录未混入）✓ · 跟踪面零改动 ✓ · **A 门** `tail` = `MDIO-APLUS-GATE: PASS`（base/zero/swap 三跑全中）✓ · **B 门** `tail` = `N2-ARM-GATE: PASS`（四臂全中）✓ · 轮目录 48 件 / sim 新目录 1165 件。
- **口径**：本件不下 PASS/FAIL；A 的"板上正控"= 明确未闭合（后续轮：变体位流构建 + 板测）；B 的"读数层"边界（非位级逐拍、对照物为归档读数）**照录**。
- **裁定**：接受入库（3 目录全部）；**登记后续轮 = mdio A+ 位流构建 + 板测**（`stage2_apply/APPLY_STEPS.txt`），并入板级序列。台账落 §10-78。
- ⚠️ 环境坑两则登记：**bat 内 `find /c` 在 git-bash 调 `cmd //c` 下解析为 GNU find（递归扫盘假挂起）** —— 与既有"bat 同名内建"族合并；`chk()` 名截断（`[255:0]`+`%0s`）⇒ **凡按 chk 名 grep 的判据不可靠**（仪器文档缺口，登记）。
