# mdio 设计件对抗复核（kimi-tl 组）

- 审查对象：`_proj_10g/notes/p9_fix_mdio_design_20261014/DESIGN.md`（386 行，目录内唯一文件）
- 复核时间：2026-10-14 · 复核方：kimi-tl（对抗审查，找茬方）· ⛔ 本复核不下 PASS/FAIL 裁定
- 纪律遵守：全程只读；唯一写操作 = 本文件。所有命令可复算（Git Bash，`/d/repo/XCKU5PMini/udp_hls_10g`）

## 结论摘要

设计件的机制主张经现读核实**几乎全部逐字属实**：5 编辑点枚举真实、锚点精确（行号/sha256 全中）；"只改两处位宽=新位恒 0 静默无效"的论证成立；PHYAD 引文与盘上 PDF 提取文本**逐字一致**（台账"TL 亲核 PDF 属实"经本复核独立证实）。板测计划收尾覆盖完整（重烧 0x24 + PCIe 恢复 + 恢复受控停流），烧录路径全部可达且 sha 已验。发现的问题集中在**引用精度级偏差**（3 处行号/措辞）与**两处中等严重度的论证覆盖缺口**（不可判边界的结构论证没盖住 VIO 输出网段；burn_arm.sh 身份段是观察式而非硬门控）。无高严重度发现；与台账 §10-55 及既有报告无实质矛盾。

## neg_ctrl 结果

### neg_ctrl-1：5 编辑点枚举核实 —— **成立（逐条真实）**

独立 grep/read 结果（关键词 mdio/MDIO/phyad/PHYAD；探针代码确认全部位于 `/d/repo/XCKU5PMini/_proj_mdio/`，**不在 git 仓内但在盘上**）：

| 编辑点 | 设计件声称（DESIGN.md） | 现读实况 | 判定 |
|---|---|---|---|
| E1 注释锚 | `mdio_vio_top.v:27` = `//   probe_in0  [19]    mdio_i   (live line level)` 后插 2 行 | 该文件第 27 行逐字一致 | ✅ |
| E2 位宽 | `:86` = `    wire [19:0] vio_probe_in;` → `[21:0]` | 第 86 行逐字一致 | ✅ |
| E3 声明锚 | `:111` = `    wire        busy;` 后插 2 行声明 | 第 111 行逐字一致；且 F4 所称"现无两新信号 wire 声明"（`:109-111` 仅 rd_data/done_sticky/busy）属实 | ✅ |
| E4 例化接线 | `:140-141` 两行对（`.mdio_i      (mdio_i)` + `    );`），"文件内唯一" | grep 证实 `.mdio_i      (mdio_i)` 全文件唯一出现（第 140 行），`);` 在第 141 行；例化 `:123-141` 确未接 `.param_bad`/`.stat_start_lost` | ✅ |
| E5 拼接 | `:143` = `assign vio_probe_in = {mdio_i, eth_rstn, busy, done_sticky, rd_data};` | 第 143 行逐字一致 | ✅ |
| E6 VIO IP 位宽 | `build_mdio.tcl:30` = `    CONFIG.C_PROBE_IN0_WIDTH {20} \`（行尾反斜杠须保留） | 第 30 行逐字一致（含续行反斜杠）；dict 语法上下文 `:28-37` 属实 | ✅ |
| E7/E8 锚（可选臂） | `:29` `module mdio_vio_top (`；`:124` `.DIV (25)`；`build_mdio.tcl:9` `set proj [file join $here pj_mdio]`；`:20` `update_compile_order` | 四处全部逐字一致 | ✅ |

旁证（设计件引用、本复核独立复算）：
- 改前 sha256 全中：`mdio_vio_top.v=e9c0c74c…fab3`（4,829 B）·`build_mdio.tcl=72f7bb8b…a4bf`（2,456 B）·`probe_phy.tcl=a16e50eb…5ec4`（6,504 B）——`sha256sum` 实测一致（DESIGN.md:56,99,166）。
- 悬空端口见证：`task2/elab_wrapper/xelab.log:8` 逐字 = `WARNING: [VRFC 10-3645] port 'param_bad' remains unconnected for this instance […/elab_wrapper/mdio_vio_top.v:123]`（DESIGN.md:20 转引一致）；`_elab_wrapper.stdout.txt` 在 `task2/` 根（非 elab_wrapper/ 内），其第 8 行同为该警告、第 1 行 `XELAB_RC=0`（DESIGN.md:198-199 引"第 8 行"属实，目录略含糊——见低-5）。
- mdio_master.v 新端口在 `:54-55`，`param_bad` 为 elaboration 常量（`:75` `assign param_bad = PARAM_BAD;` + `:70-73` localparam），`stat_start_lost` 语义与 `:159-163` always 块逐字一致（DESIGN.md:37-38,160-163 引用"160-163"，条件行实为 161-162，差异可忽略）。

**"只改两处位宽=新位恒 0 静默无效"独立判定：成立。** 若仅改 E2+E6 而不改 E5：`assign vio_probe_in = {20-bit 拼接}` 的 RHS 是无符号表达式，赋给 `wire [21:0]` 时**零扩展到 22 位** ⇒ `[21:20]` 恒 2'b00，且位宽扩展在 Vivado 编译中无告警 ⇒ "编译合法但新两位恒 0（静默无效）"逐字成立。反向半改（加 E3/E5 不接 E4）⇒ 两 wire 无驱动悬空，亦不能工作。⇒ E1-E6 同批的必要性论证成立。

### neg_ctrl-2：PHYAD 引文核实 —— **逐字属实**

- 手册在盘：`/d/repo/XCKU5PMini/资料/PDF/RTL8211E-VB-CG.pdf`（1,904,495 B）。`pdftotext -layout` 提取成功。
- 章节号核实：目录第 171 行 = `7.7. HARDWARE CONFIGURATION ……16`；Table 13 "Configuration Register Definition" 位于该节（提取文本行 1063）⇒ 设计件"§7.7 Table 13"**准确**。
- **逐字引文**（提取文本行 1066-1069，换行处为 PDF 排版折行）：
  > "PHYAD sets the PHY address for the device. The RTL8211E-VB(VL)/RTL8211EG-VB support PHY addresses from 00001 to 00111. PHY address 0 is a broadcast from the MAC; each PHY device should respond."

  与设计件 §0 第 4 行（DESIGN.md:22）引文**逐字一致**（含 "00001 to 00111" 与 "each PHY device should respond"）。
- 附注核实：提取文本行 1071-1072 = "Note: PHYAD[2:0]=000 can support all PHY addresses. It can automatically remember the first non-zero PHY address." ⇒ 设计件 F14（DESIGN.md:46）"自动记住第一个非零地址"注释的转述属实。
- J-C 的 reg4 引文（DESIGN.md:263）：提取文本行 2124 逐字 = "Note 1: The setting of Register 4 has no effect unless NWay is restarted or the link goes down." ⇒ 属实（设计件引的是 Note 正文句，逐字一致）。
- 判定：**一手引文可核且逐字命中**；台账 §10-55（P7B_TL_LEDGER_20261010.md:1055）"TL 亲核 PDF 属实"的转述经本复核**独立证实**。"地址 0/1 同 ID = 手册预期"的解读与引文方向一致（PHYAD 搭接只支持 00001-00111 ⇒ 线上地址 0 = 广播 ⇒ 搭接 001 的 PHY 对 0/1 都应答自身 ID）。
- 未核部分（如实登记）：本板"搭接 = 001"来自原理图注记（外部一手件），不在仓内，本复核**未观测**，只能依赖设计件转述；"已由 1 应答/2-31 静默见证"的原始板测 stdout 未在 notes 内找到逐字存档（PHYID 0x001CC915 的期望出处 = TB 头注释 `tb_mdio_master.v:4` + REPORT.md:229，属二手登记）。

## 发现清单

### 中

**M1 · 不可判边界的"结构论证"覆盖范围被写大，"帧内"措辞收窄了等价类**（DESIGN.md:267-270 §4.2 末；:362 §7-②）
证据：设计件称微伪影"只能靠结构性论证排除：5 位 PHYAD 与全部字段走同一条移位链（`mdio_master.v:108-110,141-142` 现读证实）、TB 对地址解码有专测、2-31 静默"。但该论证链**只覆盖 master 端口之后**：`vio_phyad` 从 VIO core 输出到 master 端口的网段（`mdio_vio_top.v:130` 一例化连线）既无 TB（§3.5 自承 `mdio_vio_top` 无功能仿真）、也无结构论证。而该网段的 stuck-at 故障产生的可观察模式与广播假设**逐位不可分**（例：`vio_phyad[0]` stuck-1 ⇒ 主机写 0/1 线上都出 00001，写 2-31 出 3/3/5…31，均不应答 ⇒ 恰为"{0,1} 答、2-31 静默"）。即真实等价类 = "地址 bit0 在 VIO-out→MDIO 线上任一点（含帧外）被置 1"，比"帧内 PHYAD 字段被改成 1"更宽。
建议：阶段二报告沿用"不许写'已排除地址字段伪影'"的口径（设计件此禁条本身如实），但把"VIO 输出网段无测试/结构覆盖"一并登记进不可判边界，别让"结构论证排除"的表述盖过这一截。实际风险极低（一段直连线 + 原观测已排除 bit[4:1] 类 stuck 模式），不要求补实验。

**M2 · 收尾"身份门"是观察式而非硬门控**（DESIGN.md:298-299 称 burn_arm.sh 含"身份门"；实测 `p9_uram_ab_20261014/_tools/burn_arm.sh:85` 只 `echo ID_RC=$?`，无 exit 1；LnkSta 非 x4 仅触发升级分支不判失败）
证据：脚本内硬门仅 6 处（sha 门 :43、五判据 :60-64，均 `exit 1`）；第 5 段身份读数（MAGIC/BID/MARKER/UNIMPL/MIR_*）与 dmesg/Lspci 全部只打印。dmesg `identify_bars` 也只 `tail -3` 打印（:82）。
影响：收尾恢复（§4.4，本轮声称"不可省"）若身份不符，脚本不会红，靠人读输出兜底。
建议：阶段二收尾轮在 burn_arm.sh 之外显式核 `ID_RC=0`、`FIRST_RESCAN_LNKSTA_WIDTH=Width x4`、`BID_0x04=0x00000024` 三行再离板；或在该轮补一条 grep 判据。不阻断。

### 低

**L1 · F9 行号 off-by-one**（DESIGN.md:41 引 `program_tcpreg_ku5p.tcl:16` 有 `set_property PARAM.FREQUENCY 1000000`；现读该语句在 **:15**）。该文件其余转述（1MHz、DONE 检查 `catch {program_hw_devices}`+`TCPREG_PROG_DONE`、无 ABORT 结构）全部属实。

**L2 · 附A"OPEN_ITEMS §0 第 18 行"引用不精确**（DESIGN.md:382）。mdio 三格登记实为 §0 **条目 #18**（表格行，文件行 69，P7B_OPEN_ITEMS.md:69）；文件行 18 是重放路径订正条目。按设计件自身"行号=现读值"纪律（DESIGN.md:9），应写"§0 条目 #18"。内容本身核对一致（"两处同步未执行"确在条 #18）。

**L3 · §3.1 归档清单未覆盖 impl_1 全部取证件**（DESIGN.md:152-158）。`pj_mdio/mdio_prj.runs/impl_1/` 现还有 bus_skew_routed.rpt、methodology_drc_routed.rpt、io_placed.rpt、control_sets_placed.rpt、drc_opted.rpt、mdio_vio_top.vdi、runme 日志与 opt/placed/physopt .dcp 等未列入；设计件首句自称"本轮会丢的：…与 impl 报告"。缓解：回滚关键 7 件（bit/.ltx/debug_nets/timing×2/utilization/drc）**存在性全部已验**（本复核逐件 stat OK），且 WNS/WHS/WPWS/sha/字节数已写进设计件"旧真值"块（DESIGN.md:164-166）；设计本身 3-6 min 可重建。建议：阶段二归档时顺手 `cp impl_1/*_routed.rpt` 通配，成本为零。

**L4 · 台账 §10-55 的 5 编辑点口径与设计件 §2 略不齐**（P7B_TL_LEDGER_20261010.md:1055 记 `:86`/`:109-111`/`:123-141`（未接线）/`:143` + `build_mdio.tcl:30`；设计件为 E1 注释 :27 / E2 :86 / E3 :111 / E4 :140-141 / E5 :143 / E6 :30）。差异：台账未列注释型 E1，且把例化记为整段 `:123-141`（设计件锚为末两行 :140-141）。无实质矛盾（E4 两种记法都指向同一编辑），但阶段二应**以设计件 §2 锚点为准**执行，别照台账行号改。

**L5 · `_elab_wrapper.stdout.txt` 路径含糊**（DESIGN.md:198-199 在 elab_wrapper 语境下引用该文件）。实况：文件在 `task2/` 根（`task2/_elab_wrapper.stdout.txt`），elab_wrapper/ 内对应物是 `xelab.log`（第 8 行同为 10-3645 警告）。内容引用（第 8 行警告、`XELAB_RC=0`）均属实，仅路径语境含糊。

**L6 · §4.4 括号注 "（0000:00:1c.0）" 为历史观察值而非脚本值**（DESIGN.md:298；R7 同 :350）。burn_arm.sh:68-69 是**动态**求根端口（`RP=$(basename $(dirname $(readlink -f …/0000:02:00.0)))`），并未硬编码 00:1c.0。若对端 PCIe 拓扑变化，文档值 stale（脚本仍正确）。建议在阶段二轮按现读值登记。

## 与台账/既有报告的矛盾点

1. **台账 §10-55（P7B_TL_LEDGER_20261010.md:1050-1058）**：本设计件是该节"四真缺陷·阶段一"之④。台账行 1055 对本件的 TL 层概括（5 编辑点、恒 0 静默无效论证、PHYAD 引文"TL 亲核 PDF 属实"、收尾必须重烧 0x24+恢复受控停流、`_proj_mdio` 无 git ⇒ 改前归档、elab 门 stub 需 20→22）**经本复核逐条独立证实**（其中 L4 枚举口径差异见上）。行 1056"TL 抽核……全中"对本件相关部分（mdio sha/行号）与现读一致。**无实质矛盾。**
2. **P7B_OPEN_ITEMS.md 条 #18 / B7 / REPORT.md §2.4-2**：既有件均写"两处同步（未执行）"；设计件将其改写为"两处只是文件数、实为 5 编辑点"——这是**对既有登记的细化而非推翻**，且 REPORT.md:214 的位序 `{stat_start_lost, param_bad, …}` 与设计件 E5 的 MSB 端新增**一致**（DESIGN.md:97 的对照引用属实）。B7（OPEN_ITEMS.md:424）"地址 0/1 复测不用重建位流"与设计件重建计划**不矛盾**（复测本身可用旧位流；重建的目的之一是让两个新信号可见）。
3. **板现态**：台账 §10-55 末行"板 = 0x24 + 受控停流（本轮未动）"与设计件 F11 一致；本复核核 `FINAL_STATE_20261014_004453.txt`（0x00=0x50360001 / 0x04=0x24 / 0x08=0x2 / 0x14=0xdeadbeef / 0x13C=0x00220000 / 0x144=0 / 0x148=0x0feb1416 / 0x14C=0xffffffff）**逐值吻合**。0x24 位流 `wrapper_p4.bit` sha256 `e3b07957…f1db`（15,431,261 B）现读一致；烧录链（run_program_tcpreg.bat → program_tcpreg_ku5p.tcl，1MHz + DONE catch）与 burn_arm.sh（sha 门 :43 + 五判据 :60-64 + 动态根端口升级 :67-80）全部在盘可达。
4. 除上列 L1/L2/L4/L6 引用精度级偏差外，**未发现设计件与台账/既有报告的实质矛盾**；未发现设计件内部自相矛盾（§0 事实表 ↔ §1 F1-F14 ↔ §2 编辑清单 ↔ §4 板测臂 ↔ §7 边界声明交叉核对一致）。

## 门计划判别力 / 负对照 / 空判据 / 同源 oracle 专项

- **判别力（逐臂核）**：§3.4 elaboration 门双向可红（E4 漏接 ⇒ 10-3645 不消失；stub 未同步 ⇒ 10-3091 位长错），且自限口径"只证 elaboration"如实。J-A 负对照（2-31 必为 0xFFFF、须同一份 stdout 复现）双向可红：PHY 不应答 ⇒ 全 FFFF 红；回显/定值伪影 ⇒ 2-31 读出 0x001C 红。J-B 新鲜性交错（相邻 001C 必须夹 FFFF，末对除外已如实注明）针对陈旧读数类伪影。J-D 自承"恒 0 与未接线不可区分"，**不空称验过**。WIDTH==22 直判据先于位序语义核对（R4 递进排查）合理。变体臂 P1 的跨构建 0/1 翻转对照（钳死/接错位不可能随构建翻转）是全套计划里最强的一枚对照。
- **空判据**：未发现。J-C 自设先决条件 `v1 != v2` 且自带"降级为不可判"出口（DESIGN.md:261），非空判据。
- **同源 oracle**：J-A/J-B 的期望值 0x001CC915 出自 TB 头注释登记的历史板测观测（tb_mdio_master.v:4，与 RTL8211E OUI 一致），判据输出取自**板上实读**，非同一数据源；无同源自证循环。
- **数学复核**：DIV=25 ⇒ 帧 64×2×25=3,200 clk=32 µs；DIV=65537 钳 65536 ⇒ 8,388,608 clk=83.886 ms、MDC=762.9 Hz（DESIGN.md:280,290 数字全部吻合）；P3 触发窗口论证（busy 83.9 ms vs commit 数十 ms）与 RTL 头注释（mdio_vio_top.v:88-91）一致。
- **结构排除引用核**：mdio_master.v:111（接受 start `rd_sh<=0`）、:118（`rd_data<=0`）、:127-128（`is_read && bit_idx>=47` 才采样 `mdio_i` 入 `rd_sh`）、:138（仅 bit_idx==63 更新 `rd_data`）现读全部与设计件 §4.2 转述一致；"rd_data 只能来自本事务"论证成立（见 M1 对覆盖范围的限定）。

## 覆盖面声明

**已核（逐字现读/实算）**：DESIGN.md 全文 386 行；`_proj_mdio/rtl/mdio_vio_top.v` 155 行（全读）、`rtl/mdio_master.v` 165 行（全读）、`build_mdio.tcl` 67 行（全读）、`probe_phy.tcl` 173 行（全读）；5 个 sha256 + 全部字节数 + mtime；旧位流/.ltx/debug_nets/timing/utilization/drc 存在性与 WNS 7.091/WHS 0.020/WPWS 4.427/失败端点 0/LUT 687/Reg 1,345；RTL8211E-VB-CG.pdf 全文提取（PHYAD 引文、PHYAD[2:0]=000 注释、reg4 Note 1、§7.7 章节号）；台账 §10-55 全文 + P7B_OPEN_ITEMS 条 #18/B7 + REPORT.md §2.2/§2.4/§4-3 + §10-55 行 1055；burn_arm.sh 全文关键段 + program_tcpreg_ku5p.tcl + run_program_tcpreg.bat + FINAL_STATE_20261014_004453.txt + elab_wrapper（run.bat/vio_0.v:60/xelab.log:8/_elab_wrapper.stdout.txt）+ pristine SHA256；git 归属（XCKU5PMini 非仓库、udp_hls_10g 仓库 `git ls-files | grep -ci mdio` = 16 且不含 _proj_mdio，`_proj_mdio` 在 worktree 外）。

**未观测/未核（如实登记）**：① 板卡实物、JTAG、hw_server、对端机——本轮零上板（只读纪律）；② 原理图"PHY_ADDR[2:0]=001"搭接注记——外部一手件，不在仓内，仅设计件转述；③ 历史板测 stdout（"{0,1} 同 ID"的原始记录）未在 notes 找到逐字存档，0x001CC915 期望以 TB/REPORT 二手登记为源；④ `tb_mdio_master.v` 全文未读（仅 sha256/字节数 + REPORT 摘要转述，与台账值一致）；⑤ xsim/Vivado 未实跑（设计件 §3.4/§3.5 均自标可选，不影响本复核结论）；⑥ PHYID2=0xC915 与具体芯片型号的绑定未对 PDF 寄存器表逐格核（属常识级 OUI 匹配，非本件判据链一环）。

**"未观测到"≠"不存在"**：上列 ①-⑥ 的任何一项若被一方声称"已验证"，本复核不提供背书。
