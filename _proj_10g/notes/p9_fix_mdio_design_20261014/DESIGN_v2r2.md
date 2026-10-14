# p9_fix_mdio 设计件 **v2r2** —— `_proj_mdio` 工具链尾项 · 实施计划（implementation-ready）

> **状态：待 kimi 即审** ⛔ 未过即审不得作为后续派单依据。

- 件名：`p9_fix_mdio_design_20261014` · 版本：**v2r2**（2026-10-15）· 性质：**只调查 + 写计划**
  （本 agent 唯一写操作 = 本目录内文件；**零改 `_proj_mdio`/rtl/sim · 零跑 Xilinx 工具 · 零上板 · 零 git 写 · 零碰板**）
- **版本链（三件并存，后者修订前者，前件一律原样保留不动）**：
  `DESIGN.md` v1（386 行）→ `DESIGN_v2.md`（453 行；依据 = kimi 首轮对抗复核 `BUNDLE_MDIO.md`，8 条全受理）→ **`DESIGN_v2r2.md`（本件）**。
- **v2r2 修订依据**：① **kimi 对四修订件的复审**（新发现 15 条；**本件 = 中 1 + 低 2**；其对本方反纠的独立复算已确认 —— 含 v2 的 L1 真值 `program_tcpreg_ku5p.tcl:14`）；
  ② **实施轮 `notes/p9_fix_mdio_impl_20261015/`**（2026-10-15：E1-E6 已落盘 + 两组归档 + elab 门就位未跑 —— 本件据其实况同步文档状态）。
- **读者**：阶段二 agent（零上下文可照做）。范围 = ① VIO 探针位宽同步（**已落盘**）② 重建位流（**未做**）③ MDIO 地址 0/1 板测（**未做**）。
- ⛔ 本件不做 PASS/FAIL 裁定（裁定权在判据所有者）。路径约定：`_proj_mdio` 相对 `D:\repo\XCKU5PMini\`；`notes/...` 相对 `D:\repo\XCKU5PMini\udp_hls_10g\`。
- **行号纪律（v2r2 强化）**：一切行号 = **现读值**；本件对 `mdio_vio_top.v` 的引用一律给**锚点文本（权威）+ 改前/改后双行号**（§2.0 对照表）；复算命令随文给出。

---

## §0v2r2 相对 v2 的变更清单（读这一节即知 v2r2 动了什么）

**复核发现 3 条：全部受理**（其中 中-1 按"二选一"取了 (a)，理由随条给出）。另加 **1 条状态同步（D1，非复核查项）**与 **1 条附加观察（E-0，非复核查项）**。全部依据 = 本 agent 2026-10-15 独立现读（命令随条）。

| # | 复审发现 | v2r2 处置 | 依据（v2r2 现读复算） |
|---|---|---|---|
| **中-1** | **判据假红缝**：v2 §4.4 硬判据 2 的 `Width x4` 具名行（`FIRST_RESCAN_LNKSTA_WIDTH=`）**只在设备级首次 rescan 打印一次**（`burn_arm.sh:73`，位于升级分支**之前**）⇒ "首次 x1、升级恢复 x4"（恰 R7 场景）**必假红**；且与 R7"升级后仍须再过硬判据"自相矛盾 | **受理，选 (a)：改锚"终态 `LnkSta:` 行"（非具名）**。§4.4 判据表重写：判据 2 = **最终 `--- lspci ---` 块（`burn_arm.sh:78`，升级分支**之后**）的 `LnkSta:` 行**，`grep -qE 'LnkSta:.*Width x4'`；具名行降级为"是否走了升级分支"的**见证量**（记录不判）。⛔ 并注明：**假红方向安全（停手非带病离板），但"恒红"的判据不是真判据**（成功路径也红 ⇒ 要么卡死每轮、要么被当噪声绕过）⇒ **必须消缝、不能只加注**。R7 措辞同步修（§6） | 现读 `burn_arm.sh:71-78`：`:73` 打印具名行 → `:74-77` 升级分支 → **`:78` 才打印 `--- lspci ---` 与 `lspci -vvv … \| grep -E "LnkSta:\|Region 0\|Region 1"`**；历轮 burn 日志中终态行逐字 = `LnkSta:\tSpeed 5GT/s (downgraded), Width x4`（如 `…/p9_uram_ab_20261014/burn/BURN_0x24_S1_…txt`）。**选 (a) 的理由**：`:78` 那块在 if/fi **之后**，构造上就是"升级后的终态"，语义与 v2 本意"升级后重核"**逐字一致**，且机器可判（`grep -q`）；选 (b)（保留恒红判据+加注）则每轮都要人工副判两行，且判据在成功路径上恒红 —— 违反"判据必须在成功路径上可为真" |
| **低-A** | §3.1 字面 `sha256sum archive_20260928/* …` **对目录报错**（`archive_20260928/*` 含子目录 `impl_1/` ⇒ `sha256sum: …/impl_1: Is a directory`）| **受理**。§3.1 改为**可执行写法（显式文件表 / 子壳内 glob）**，并加两条实测坑：① 实施轮已按显式文件表执行（15/15 + 7/7 自核 OK）；② `sha256sum` 输出为 `hash *file`（**带 `*` 前缀**）⇒ 用 `grep " file"` 类核对会**结构性漏检**（实施轮亲身踩到）—— 核对应走 `sha256sum -c` 或写解析器 | 实施轮 REPORT §1.1 逐字："v2 字面命令 `sha256sum archive_20260928/* …` 会把目录 `impl_1` 当参数报错；本件改为目录内显式文件表生成"；同件 §5 末记 `hash *file` 漏检坑 |
| **低-B** | **行号被编辑漂移**（`mdio_vio_top.v` 编辑后全移位）⇒ 现读重取，或统一改用"锚点文本"引用 | **受理，两者都做**。新增 **§2.0**：**锚点文本 = 权威**；每个编辑点附 **改前/改后双行号对照表**（改后 = 2026-10-15 现读，覆盖 E1-E6 与 E7/E8 未做锚点）；§1 拆"改前基线 / 改后现读"两栏；§2 表头与各条加"改后现读"值 | 本 agent 逐条现读（`cat -n`）：改后 = E1 插入行 `:28-29`（锚 `:27` 未动）· E2 `:88` · E3 插入行 `:114-115`（`busy` 在 `:113`）· E4 `:144-147`（新端口行 `:145-146`）· E5 `:149` · E6 `:30`（未位移）· E7a `:31` · E7b `:128`；文件 155→**161 行** |
| **D1**（状态同步；**非**复核查项，本 agent 自查追加） | v2 写于实施轮**之前** ⇒ 其"未落盘/未归档/门未就位"的世界态已过时；且 §3.4 第 3 步（"只改 stub 即可"）**已被实施轮现读证据推翻** | **受理（三处）**：① §0/§1 加状态栏（E1-E6 **已落盘**、两组归档在盘、门**就位未跑**、构建/上板未做；两文件新 sha）；② **§3.4 按实施轮证据重写**（stub-only 不生效 —— xvlog **后定义覆盖前定义** `VRFC 10-3609`，被 elaboration 采用的原是冻结 20 位的 `vio_0_sim_netlist.v`；门已按"把已 patch 的 stub 排到最后"处置，期望覆盖见证 = `10-3609 … [vio_0.v:49]`；⚠️ 门**未实跑**，第一次跑必须先核该锚点）；③ §2 状态注（E1-E6 = 已落盘记录；E7/E8 = 未做） | 实施轮 `p9_fix_mdio_impl_20261015/REPORT.md` §1-§5 + `gate_elab_22/GATE_NOTES.md`（含 `task2/elab_wrapper/xvlog.log:9` 的 `10-3609` 逐字）|
| **E-0**（附加观察；**非**复核查项） | ——（复核未提；本 agent 现读 `burn_arm.sh:72` 时顺带发现） | **登记不修**：`:72` 的 `W=$(lspci -vvv … \| grep -o "Width x[0-9]*" \| head -1)` 取**首个** `Width xN`；按 lspci 标准输出顺序（`LnkCap:` 先于 `LnkSta:`）该值 = **能力位宽（恒 x4）**而非**链路状态位宽** ⇒ `:74` 的**升级触发条件可能结构性不触发**。⚠️ **未实跑验证**（本件禁工具；历轮 `[D-3]` 全程"设备级一次成功"⇒ 该分支从未被激励、**无正面证据**）。处置建议（写入 §4.4/R7）：阶段二若遇"设备级只到 x1 而脚本未升级" ⇒ **手动**执行根端口级 remove+rescan；⚠️ 本件的判据 2 锚 `LnkSta:` 行 ⇒ 不受本观察影响（但若触发条件真的死，则 R7 的手动路径是唯一兜底） | 现读 `:72`/`:74` 逐字；lspci 输出顺序 = 标准行为（推断，**未经本机实跑**） |

**明确登记：v2 被本件订正的句子**（供对照）：

- v2 §3.1 的 `sha256sum archive_20260928/* archive_20260928/impl_1/* > …` **字面命令**（低-A ⇒ 已换可执行写法）。
- v2 §3.4 第 3 步"**只改 stub 第 60 行为 `[21:0]`（否则 xelab 会报 10-3091）**"（D1 ⇒ 实施轮证据表明只改 stub **不生效**，已重写）。
- v2 §4.4 判据 2"`FIRST_RESCAN_LNKSTA_WIDTH=Width x4`（含根端口级升级之后的重核）"（中-1 ⇒ 该括注原地不成立，已换锚终态 `LnkSta:` 行）。
- v2 §2/§1 中一切指向 `mdio_vio_top.v` 的行号（低-B ⇒ 已全部给出双行号；**锚点文本不变**）。
- v2 §0/§1 的"未落盘 / 未归档 / 门未就位"世界态（D1 ⇒ 已加状态栏）。
- ⛔ 其余（板测臂设计、边界声明、登记项 R-a..R-d、纪律核对、风险表）**逐字保留**（不与本次发现冲突）。

---

## §0 一页结论（含与派单描述的逐条核对）

派单四条陈述，现核结果：**三条属实；一条属实但需两处补正；一条的"待查"性质被器件手册改写**。

| # | 派单描述 | 现核 | 差异（如实，不迁就） |
|---|---|---|---|
| 1 | `_proj_mdio` 的 RTL 两潜伏项已修（`p7b_tool_debt_20261010/`） | ✅ **属实** | `rtl/mdio_master.v` 现读 sha256 `89d5c89e295ce988b2013ecdb07f94d158001e0ef1e5585020f82e481f8d35db`（7,274 B）· `tb/tb_mdio_master.v` `8c8dc2c83c09cc9a80bfc9995c6e55233095369de5cc67612e65e4581bc10d7d`（21,858 B）—— 与 `notes/p7b_tool_debt_20261010/REPORT.md` §2.2 逐字一致；pristine 保全件在 `…/pristine/` |
| 2 | VIO 探针位宽同步（**两处**）未做 | ✅ 属实（**已于 2026-10-15 由实施轮落盘** —— 见 §1-F17），但**"两处"只是文件数、不是编辑点数** | 改前现读：`build_mdio.tcl:30` = `{20}` · `mdio_vio_top.v:86`（改后 :88）= `[19:0]` · `:143`（改后 :149）= 20 位拼接。**并且例化处根本没接两个新端口**（工具债轮 xelab 实测 `VRFC 10-3645 … [mdio_vio_top.v:123]`，改后实例起始 :127）⇒ **全枚举 = 6 个编辑点**（§2；台账/复核所称"5 编辑点"= 未含注释型 E1 的口径 E2..E6，两口径指同一集合）。⚠️ **两种半改的死法**：只改两处位宽不接拼接 ⇒ **编译合法但新两位恒 0（静默无效）**；只加拼接不接例化 ⇒ 两 wire 无驱动（悬空）。故 E1-E6 **必须同批**（**已同批落盘**） |
| 3 | 未重建位流 / 未上板 | ✅ **属实**（且实施轮后**仍未构建/未上板**） | `pj_mdio/` 全部产物 mtime = **2026-09-28 20:34-20:35**（修复前；已由实施轮整组归档）；旧位流 sha256 `46417affc544e6a51e2eff8cafa473afaad5384cd1b17e033d1a31800d692ad2`（15,431,263 B）；旧基线 `timing_summary.rpt`：**WNS +7.091 / WHS +0.020 / WPWS +4.427，三列失败端点全 0**；旧资源 = CLB LUT 687 / Reg 1,345 |
| 4 | MDIO 地址 0/1 同 ID 仍待板测 | 属实（未结项），但 ⭐ **器件手册给出预期解释，性质从"怪现象"变为"手册预期行为 + 需排除宿主侧伪影"** | RTL8211E datasheet（本机 `资料\PDF\RTL8211E-VB-CG.pdf`，Rev 1.6）**§7.7 "Hardware Configuration"，Table 13 "Configuration Register Definition" 的 PHYAD[2:0] 行**（`pdftotext -layout` 提取文本行 1066-1069）**逐字**："PHYAD sets the PHY address for the device. The RTL8211E-VB(VL)/RTL8211EG-VB support PHY addresses from 00001 to 00111. **PHY address 0 is a broadcast from the MAC; each PHY device should respond.**" ⇒ 地址 0 = **广播**（每个 PHY 都应答），地址 1 = 搭接地址（原理图注记 `PHY_ADDR[2:0]=001`，⚠️ 外部一手件、不在仓内，只能转述）⇒ **"0 与 1 同 ID" 正是手册预期**。实验目的随之改为"确认 + 排除宿主侧伪影"（§4.2），并**如实登记不可判边界与覆盖缺口**（§4.2 末 + §7 登记项） |

**下一棒一行话**：**跑门**（先核 10-3609 锚点，§3.4）→ **构建**（§3.2，`create_project -force` 会清 `pj_mdio/` —— 归档已在盘）→ **板测**（§4；**先烧 mdio 位流；收尾必须重烧 0x24 + 硬判据核身份 + 恢复受控停流**）→ 全程只走 **JTAG 易失**，**绝不写 QSPI**。

---

## §1 现状现读（**两栏**：F1-F16 = **改前基线**（编辑依据）· F17-F18 = **改后现读**（2026-10-15，实施轮落盘后））

> ⚠️ 低-B 落地：**F1-F16 的行号一律 = 改前值**（v1/v2 口径），照旧是"编辑依据"；**改后值见 §2.0 对照表**。引用任何 `mdio_vio_top.v` 行号时给双值。

| # | 位置 | 逐字（现读） | 含义 |
|---|---|---|---|
| F1 | `_proj_mdio/rtl/mdio_vio_top.v:86`（改后 **:88**） | `    wire [19:0] vio_probe_in;` | 探针输入 20 位 = 旧 5 字段（改后为 `[21:0]`） |
| F2 | `…:143`（改后 **:149**） | `    assign vio_probe_in = {mdio_i, eth_rstn, busy, done_sticky, rd_data};` | 改前位映射：`[15:0]` rd_data · `[16]` done_sticky · `[17]` busy · `[18]` eth_rstn · `[19]` mdio_i |
| F3 | `…:123-141`（改后 **:127-147**） | 例化 `mdio_master #(.DIV (25)) u_mdio_master ( … .mdio_i (mdio_i) );` | **改前未接** `.param_bad` / `.stat_start_lost`（改后已接，见 §2.0-E4） |
| F4 | `…:109-111`（改后 **:111-115**） | `wire [15:0] rd_data; / wire done_sticky; / wire busy;` | 改前无两新信号 wire 声明（改后 +2 行） |
| F5 | `_proj_mdio/rtl/mdio_master.v:54-55` | `output wire param_bad, // 1 = DIV out of range, clamped (static)` · `output reg stat_start_lost // sticky: a start arrived while busy (dropped)` | 两新信号 = 本轮要引出的 2 位的**全部**（无第三处） |
| F6 | `…mdio_master.v:75/159-163` | `assign param_bad = PARAM_BAD;` / `always @(posedge clk) begin`（`:159`）+ 三条件行（`:160-162`） | `param_bad` = **elaboration 常量**（DIV=25 ⇒ 0，板上恒 0）· `stat_start_lost` = 1 FF，**只在 busy 期来 start 才置位** |
| F7 | `_proj_mdio/build_mdio.tcl:30` | `    CONFIG.C_PROBE_IN0_WIDTH {20} \`（改后 = `{22}`，行号未位移） | VIO IP 位宽参数（与 F1 必须同批改） |
| F8 | `_proj_mdio/probe_phy.tcl:22-28` | 注释位图（`probe_in0[19] mdio_i` 收尾） | 宿主侧位图注释；`mdio_read`（`:123-137`）按**位位置**解码 `[19:16]` ⇒ 新位放 MSB 端则旧脚本**零回归** |
| F9 | `…probe_phy.tcl:53-61` | `set_property PROGRAM.FILE $bit $dev` + `program_hw_devices` | ⚠️ 该脚本**自带烧录**，但**无 1MHz 降频、无 DONE 检查**（对比 `notes/p7b_biz_tcpreg/program_tcpreg_ku5p.tcl:`**`14`** `set_property PARAM.FREQUENCY 1000000 …` —— ⚠️ v1 的 `:16` 与首轮复核给的 `:15` 均偏，**现读真值 = `:14`**，复算 = `grep -n "PARAM.FREQUENCY" program_tcpreg_ku5p.tcl`）⇒ 见 §5.2 |
| F10 | `_proj_mdio/pj_mdio/…/impl_1/mdio_vio_top.bit` + `.ltx` | 15,431,263 B / 14,414 B，均 **2026-09-28 20:34**（**已整组归档**，§3.1） | 旧位流与探针文件；.ltx 与 bit **同目录同名**（`probe_phy.tcl:40` 按 `[file rootname $bit].ltx` 定位） |
| F11 | 板侧现态（p9_uram_ab 轮 `FINAL_STATE_20261014_004453.txt`） | `0x00=0x50360001` · **`0x04=0x00000024`** · `0x08=0x00000002`（受控停流）· `0x14=0xdeadbeef` · `0x13C=0x00220000` · `0x144=0` · `0x148=0x0feb1416` · `0x14C=0xffffffff` | 板现跑 **0x24 + 受控停流**；恢复 = `reg_rw /dev/xdma0_user 0x08 w 0x0` |
| F12 | `notes/p9_build_0x24/wrapper_p4.bit` | sha256 `e3b07957aea0326a168b9db0238ef9dd933dc7a21884c92e50a7c3b0abadf1db`（15,431,261 B；三处副本同 sha） | 收尾重烧的**唯一真值**（§4.4） |
| F13 | 版本控制现状 | `D:\repo\XCKU5PMini` **不是 git 仓库**；`udp_hls_10g` 是仓库但**不含** `_proj_mdio` | ⇒ `_proj_mdio` 被改文件**没有任何版本控制兜底** ⇒ §3.1 的**改前归档是回退的唯一来源**（**已由实施轮完成**） |
| F14 | 器件手册（本轮新证） | `资料\PDF\RTL8211E-VB-CG.pdf` **§7.7，Table 13 的 PHYAD[2:0] 行**（提取文本行 1066-1069）逐字 | 地址 0 = 广播（每个 PHY 都应答）、地址 1..7 = 搭接地址；另有 `PHYAD[2:0]=000` 时"自动记住第一个非零地址"的注释（**本板不适用**）。复算 = `pdftotext -enc UTF-8 -layout 资料/PDF/RTL8211E-VB-CG.pdf - \| sed -n '1060,1075p'` |
| F15 | **VIO 输出网段无覆盖** | `mdio_vio_top.v:130`（**改后 :134**） = `        .phyad       (vio_phyad),`（同类还有 `.op/.start`、`:134-136` 等直连线） | 该网段（VIO core 输出 → 端口 → `sh[27:23]` 装载）**无 TB**（`tb_mdio_master.v` 只例化 `mdio_master`）**也无结构论证** ⇒ 进 §4.2 不可判边界与 §7 登记项 R-a |
| F16 | 历史板测原始 stdout 未在仓内 | `notes/` 未找到"{0,1} 同 ID"的逐字 stdout 存档；`0x001CC915` 的期望出处 = `tb_mdio_master.v:4` 头注释 + `REPORT.md:229`（二手登记） | 阶段二复测的 stdout = **第一份一手存档**（§7 登记项 R-c） |
| **F17** ⭐ | **实施轮落盘状态**（2026-10-15，**改后现读**） | E1-E6 **已落盘**：`rtl/mdio_vio_top.v` 4,829→**5,259 B**（155→**161 行**）· 新 sha256 = **`79c360f83aff1789eb1144ef1045a3a5fd1cebed27d2f3cb76484d056b6956e6`**；`build_mdio.tcl` 新 sha256 = **`b7ff3c45ea89399b789308e0ac31340e3c6de1e490813855a446ad623846aecd`**；旧 20 位逐位不动（位序现读 = `[21] stat_start_lost · [20] param_bad · [19:0] 原样`）；两文件纯 LF | **归档两组在盘**：`p9_fix_mdio_impl_20261015/{archive_20260928/（15 件，`sha256sum -c` 15/15 OK）, pre_edit/（7 件，7/7 OK）}`；**elab 门 `gate_elab_22/` 就位、未运行**；**构建未做 / 未上板**；所有权面 = `find _proj_mdio -newermt 2026-10-14` **仅这 2 文件** |
| **F18** | 引用纪律（低-B 的落地） | —— | 引用 `mdio_vio_top.v` 一律 **锚点文本 + 改前/改后双行号**（§2.0 表）；再次编辑同一文件后**行号必须重取**（本工程台账 §9-5-11 同款纪律） |

---

## §2 编辑清单（锚点文本 = **权威**；行号 = 改前/改后双值）

### §2.0 引用纪律与全映射表（v2r2 新增；低-B 落地）

**规则**：① **锚点文本（逐字）是唯一权威** —— 行号只是"现读便利值"；② 每次编辑后**行号全体重取**；③ 本表"改后"列 = **2026-10-15 现读**（实施轮落盘后）。

| 点 | 锚点文本（逐字；权威） | 改前行号 | 改后行号（现读） | 状态 |
|---|---|---|---|---|
| **E1** | `//   probe_in0  [19]    mdio_i   (live line level)`（在其**后**插 2 行） | :27 | 插入行 = **:28-29**（锚点行仍在 :27） | ✅ 已落盘 |
| **E2** | `    wire [19:0] vio_probe_in;` | :86 | **:88** | ✅ 已落盘 |
| **E3** | `    wire        busy;`（在其**后**插 2 行） | :111 | 插入行 = **:114-115**（`busy` 仍在 :113） | ✅ 已落盘 |
| **E4** | `        .mdio_i      (mdio_i)` + `    );`（两行对，替换为 4 行） | :140-141 | **:144-147**（新端口行 = :145-146；实例起始 :127） | ✅ 已落盘 |
| **E5** | `    assign vio_probe_in = {mdio_i, eth_rstn, busy, done_sticky, rd_data};` | :143 | **:149** | ✅ 已落盘 |
| **E6** | `    CONFIG.C_PROBE_IN0_WIDTH {20} \` | :30 | **:30**（未位移；现文 = `{22}`） | ✅ 已落盘 |
| **E7a** | `module mdio_vio_top (` | :29 | **:31** | ⛔ **未做**（可选臂） |
| **E7b** | `.DIV (25)                       // 100MHz / 25 -> 2MHz MDC` | :124 | **:128** | ⛔ **未做** |
| **E8a** | `set proj [file join $here pj_mdio]`（`build_mdio.tcl`） | :9 | :9 | ⛔ **未做** |
| **E8b** | `update_compile_order -fileset sources_1`（`build_mdio.tcl`） | :20 | :20 | ⛔ **未做** |

**计数口径（消歧义）**：**全枚举 = 6 处**（E1 注释 · E2 位宽 · E3 声明 · E4 例化 · E5 拼接 · E6 IP 参数）；
台账 §10-55 与 kimi 复核所称"**5 编辑点**"= 未含注释型 E1 的口径（E2..E6）—— **同一集合，不矛盾**。
⛔ **执行 guard（复核 L4，v2 原句保留）**：**一律以本件 §2 锚点为准，别照台账行号改**（台账把 E4 记为整段 `:123-141`，本件锚 = 末两行 `:140-141` ⇒ 改后 `:144-147`）。

**状态注（D1）**：E1-E6 **已由实施轮落盘**（§1-F17）；本节 = **记录 + 复核**用。**E7/E8 未做**（实施轮派单范围 = E1–E6）⇒ **A+ 变体臂尚不可做**（其锚点行号已按上表更新为 :31 / :128 / :9 / :20）。

### §2.1 必做编辑（**已全部落盘**；下列为逐点锚点与内容，可作复核清单）

**E1~E5 · `_proj_mdio/rtl/mdio_vio_top.v`**（改前 sha256 `e9c0c74cac71e98caed48030e66a70d574eb55f6539622a8a0553d7aabe6fab3`，4,829 B ⇒ 改后 sha `79c360f8…`，5,259 B）

- **E1（注释位图，插入型）**：锚 = `//   probe_in0  [19]    mdio_i   (live line level)`（改前 :27）
  其后插入两行（改后 **:28-29**）：
  ```
  //   probe_in0  [20]    param_bad        (DIV out of range -> clamped; static)
  //   probe_in0  [21]    stat_start_lost  (start arrived while busy; sticky)
  ```
- **E2（声明，替换型）**（改前 :86 → 改后 **:88**）：`wire [19:0] vio_probe_in;` → `wire [21:0] vio_probe_in;`
- **E3（新 wire 声明，插入型）**：锚 = `    wire        busy;`（改前 :111）；其后插入（改后 **:114-115**）：
  ```
      wire        param_bad;          // from mdio_master (2026-10-10 additions)
      wire        stat_start_lost;
  ```
- **E4（例化接线，替换型）**（改前 :140-141 → 改后 **:144-147**）：
  ```
          .mdio_i      (mdio_i)
      );
  ```
  →
  ```
          .mdio_i      (mdio_i),
          .param_bad   (param_bad),          // 2026-10-10 additions (were left unconnected)
          .stat_start_lost (stat_start_lost)
      );
  ```
- **E5（拼接，替换型）**（改前 :143 → 改后 **:149**）：
  `    assign vio_probe_in = {mdio_i, eth_rstn, busy, done_sticky, rd_data};`
  →
  `    assign vio_probe_in = {stat_start_lost, param_bad, mdio_i, eth_rstn, busy, done_sticky, rd_data};`
  ⭐ **位序是关键设计决定**：新位放 **MSB 端** ⇒ 新映射 = `[21] stat_start_lost · [20] param_bad · [19:0] 逐位不动`
  ⇒ 旧读数脚本（按位位置解码）**零回归**；REPORT §2.4-2 的 `{stat_start_lost, param_bad, …}` 正是此序。

**E6 · `_proj_mdio/build_mdio.tcl`**（改前 sha `72f7bb8b…a4bf` ⇒ 改后 sha `b7ff3c45…aecd`）

- **E6（替换型）** 第 30 行（行号未位移）：`    CONFIG.C_PROBE_IN0_WIDTH {20} \` → `    CONFIG.C_PROBE_IN0_WIDTH {22} \`
  （该行是 dict 续行，**行尾反斜杠必须保留**）⇒ 现读 = `{22} \` ✓

### §2.2 可选编辑（A+ 变体臂专用；见 §4.3。推荐做，理由 = 两个新位的**板上正控只此一路**）

⛔ **未做**（实施轮派单范围 = E1–E6）。锚点行号 **已按改后现读更新**（v2r2 低-B）：

- **E7（`mdio_vio_top.v` 加顶层参数，插入型+替换型）**
  - 锚 = `module mdio_vio_top (`（改后 **:31**）→
    ```
    module mdio_vio_top #(
        parameter integer DIV = 25          // production 25; A+ arm overrides via build generic
    ) (
    ```
  - 锚 = `.DIV (25)                       // 100MHz / 25 -> 2MHz MDC`（改后 **:128**）→ `.DIV (DIV)                      // 100MHz / DIV -> 2MHz MDC at DIV=25`
  - 注明：默认 25 ⇒ **生产构建 elaboration 不变**；参数只被变体构建的 generic 覆盖。
- **E8（新文件）** `_proj_mdio/build_mdio_divbad.tcl` = `build_mdio.tcl` 的副本，改 2 处：
  ① 锚 = `set proj [file join $here pj_mdio]`（:9）→ `… pj_mdio_divbad]`（**必须换项目目录**，否则 `create_project -force` 摧毁生产构建产物）；
  ② 锚 = `update_compile_order -fileset sources_1`（:20）**之后**插入：
  ```tcl
  set_property -name {STEPS.SYNTH_DESIGN.ARGS.GENERIC} -value {DIV=65537} -objects [get_runs synth_1]
  ```
  （`DIV=65537` ⇒ 钳到 65536 + `PARAM_BAD=1` ⇒ 板上可观测，见 §4.3）

### §2.3 替代路径（若不想动生产文件加参数）

E7 可换成"变体独立顶层"：复制 `mdio_vio_top.v` → `mdio_vio_top_divbad.v`（只改 `.DIV (25)` → `.DIV (65537)`），E8 的副本构建脚本把 `add_files` 的 top 换成该变体件 + `set_property top mdio_vio_top_divbad`。
**二选一即可；不要两条都做**（会产生两个可烧变体，登记混乱）。

### §2.4 `.ltx` / 探针命名一致性核对（构建后必做，零成本）

- 探针名 = **所连网的网名**（五坑之①）：本设计连到 `vio_probe_in` 网 ⇒ 名应为 `vio_probe_in`，**随构建自动更新**，无需手改。
- `.ltx` 由构建产出，落在 **bit 同目录同名**（`pj_mdio/…/impl_1/mdio_vio_top.ltx`）⇒ `probe_phy.tcl:40` 的 `[file rootname $bit].ltx` 能直接找到。
- 板侧核对 = `get_property WIDTH $P_STATUS` **== 22**（"探针位宽同步已生效"的**直接**判据，比读值可靠）。
- 宿主侧文档同步（推荐）：只在 v2 驱动脚本里维护新位图（§4.2），历史 `probe_phy.tcl` 原样留档。

---

## §3 重建位流计划

### 3.1 先归档（**已由实施轮完成**；本节 = 记录 + 复核命令。`create_project -force` 开工即清 `pj_mdio/`）

全局教训 #54 同族：**每次构建都会摧毁上一次构建的取证**。⚠️ `_proj_mdio` **不在任何 git 仓库内**（F13）⇒ 归档 = 唯一回退来源。

**已落盘**（`notes/p9_fix_mdio_impl_20261015/`）：`archive_20260928/`（**15 件**，`sha256sum -c` **15/15 OK**）= bit + ltx + debug_nets.ltx + **11 个 `*.rpt`** + `timing_summary.rpt`；`pre_edit/`（**7 件**，**7/7 OK**）= `mdio_vio_top.v` / `build_mdio.tcl` / `probe_phy.tcl` + 超集补件（`mdio_master.v`/`tb_mdio_master.v`/`list_probes.tcl`/`ku5p_mdio.xdc`）。
未归档（如实登记）：`impl_1/` 的 dcp/vdi/runme.log 等非 rpt 产物（= 可选全量项，实测 24 MB）。

**可执行写法（低-A 修正；不要用 v2 的字面命令）**：

```
# ⛔ 不要写 `sha256sum archive_20260928/* …` —— glob 含子目录 `impl_1/` ⇒ sha256sum 对目录报错
#    (`Is a directory`)。可执行形式 = 显式文件表（或子壳内 glob）：
( cd archive_20260928 && sha256sum timing_summary.rpt impl_1/* ) > archive_20260928/SHA256SUMS.txt
( cd pre_edit          && sha256sum *.v *.tcl *.xdc )            > pre_edit/SHA256SUMS.txt
sha256sum -c archive_20260928/SHA256SUMS.txt      # 自核（工作目录 = archive_20260928/）
sha256sum -c pre_edit/SHA256SUMS.txt              # 自核（工作目录 = pre_edit/）
```
⚠️ **实测坑（实施轮亲身踩到）**：`sha256sum` 输出为 **`hash *file`**（文件名前带 `*`）⇒ 用 `grep " file"` 类核对会**结构性漏检**（会误报 DIFFERS）；核对应走 `sha256sum -c` 或自写解析器。
旧真值（供对账）：bit sha256 `46417aff…92ad2`（15,431,263 B）· `.ltx` 14,414 B · `timing_summary.rpt` WNS `+7.091 / WHS +0.020 / WPWS +4.427`（三列失败端点 0）· 改前 `mdio_vio_top.v` = `e9c0c74c…fab3` · `build_mdio.tcl` = `72f7bb8b…a4bf` · `probe_phy.tcl` = `a16e50eb…5ec4`。

### 3.2 构建（配方 = 本工程既有入口，不新造；**未做**）

```
# 在 Windows（bat 纪律：写 bat 再调；MSYS_NO_PATHCONV=1 与 cmd //c 并用会互相抵消）
cd /d D:\repo\XCKU5PMini\_proj_mdio
vivado -mode batch -source build_mdio.tcl -nojournal -nolog
```
stdout 期望形态（`build_mdio.tcl:40-67`）：`=== SYNTH ===` → SYNTH 100% → `=== IMPL ===` → impl 100% →
`TIMING_WNS …` / `TIMING_WHS …` / `TIMING_TNS …` → `BITSTREAM <path>` + `BITSTREAM_BYTES …` → `=== BUILD DONE ===`。
判据形态（不做裁定）：三类失败端点 0；WNS 应与旧基线**同量级**（+7 ns 级——本轮只 +1 FF + 常量 + VIO 6 位）；
若 WNS 掉到 <1 ns 量级 ⇒ **停手上报**（不应发生，属异常）。
变体臂（E8）同理跑 `build_mdio_divbad.tcl`，产物落 `pj_mdio_divbad/`（**E7/E8 未做 ⇒ 本轮构建无变体臂**）。

### 3.3 产物记录（sha256 方式）

```
sha256sum -b _proj_mdio/pj_mdio/mdio_prj.runs/impl_1/mdio_vio_top.bit
ls -l     _proj_mdio/pj_mdio/mdio_prj.runs/impl_1/mdio_vio_top.bit _proj_mdio/pj_mdio/mdio_prj.runs/impl_1/mdio_vio_top.ltx
```
记 `BIT_SHA / BIT_BYTES / BIT_MTIME / LTX_BYTES / TIMING_WNS / TIMING_WHS / 失败端点数`，写进轮 `READINGS.txt`。
**变体臂位流单独登记**（与生产臂 sha 必须不同；相同 = 构建没生效，停手查）。烧录前把该 sha 抄进烧录日志（§4.1 判据链要用）。

### 3.4 可选预构建 elaboration 门（**已就位、未运行**；v2r2 按实施轮证据**订正第 3 步**）

门件在 `notes/p9_fix_mdio_impl_20261015/gate_elab_22/`（`run.bat` + `check_elab.bat` + patched `vio_0.v` + `negctrl/` + `GATE_NOTES.md`；骨架 = `p7b_tool_debt_20261010/task2/elab_wrapper/` 的**只取 5 个输入 .v 与两条命令行**，**不带** `xsim.dir/` 与旧日志 —— 坑 7）。

1. 跑法：`cd /d <gate_elab_22>` → `run.bat`（xvlog → xelab → `check_elab.bat`；退出码 = 裁定）。
2. ⛔ **v2 第 3 步已被推翻（D1）**：v2 说"把 `vio_0.v` stub 第 60 行改成 `[21:0]` 即可，否则 xelab 报 10-3091" —— **只改 stub 不生效**。证据（`task2/elab_wrapper/xvlog.log:9` 逐字）：
   `WARNING: [VRFC 10-3609] overwriting previous definition of module 'vio_0' […\vio_0_sim_netlist.v:18]`
   ⇒ xvlog **后定义覆盖前定义**；原编译表里**冻结 20 位**的 `vio_0_sim_netlist.v`（`:27`/`:35` = `input [19:0]probe_in0;`）排在 stub 之后 ⇒ 被 elaboration 采用的是**网表版**（旁证：xelab 编译表出现 `unisims_ver.LUT6`/`FDRE_default`/`GND` 等只在网表内部出现的原语）。
3. **门的处置（已就位）**：把**已 patch 成 22 位**的 stub 排到编译表**最后** ⇒ stub 成为生效定义；期望 stdout 出现**同一条 10-3609，但锚点变成 `vio_0.v:49`**（= "stub 已生效"的覆盖见证）。替代路 = 把 `vio_0_sim_netlist.v` 从编译表去掉（二选一，门选了前者：保文件集、留见证）。
   ⚠️ **两条路都未实跑**（实施轮禁工具）⇒ **第一次跑门必须先核 10-3609 锚点**；锚点仍指 `vio_0_sim_netlist.v` ⇒ **停手**（顺序被改回去了），别信那次通过。
4. 门判据（`check_elab.bat`，硬门 = 打印 + 退出码两条腿）：F1 `elab_rc.txt==0` · F2 `VRFC 10-3645` **0 命中** · F3 `VRFC 10-3091` **0 命中** · F4 RTL 文本（`[21:0]` 在 / 旧 `[19:0]` 不在 / 拼接序逐字 —— 补 elab 看不见的"E2↔E6 同步"与"E5 位序"）· F5 `vio_0.v` 22 位且 `build_mdio.tcl {22}`。
5. 负对照（`negctrl/`）：删掉一行 `.param_bad (param_bad),` ⇒ xelab 报 `10-3645 … [mdio_vio_top.v:127]` ⇒ F2 命中 ⇒ `GATE_FAIL` + `exit /b 1`（⚠️ 红在**警告行**上，`XELAB_RC` 仍 0 —— 这正是"只打印 XELAB_RC"的旧骨架当不了门的原因）。
6. **覆盖边界（如实登记）**：只证 elaboration（不证功能/综合/实现/位图语义）；测不到"端口连到一根**没驱动的 wire**"（该形态 elab 无警告）；**不覆盖 VIO 网段**（R-a）。

### 3.5 TB 回归（可选；说明为何非必须）

`mdio_master.v` / `tb_mdio_master.v` 本轮**一字不动**（E1-E8 只碰 top 与构建脚本）⇒ 2×2 矩阵结论（新 RTL×新 TB PASS 等）自动延续。
⚠️ **覆盖边界（复核 M1 的根）**：该 TB **只例化 `mdio_master`**，对 `mdio_vio_top`（`vio_phyad` 等 VIO 网段）**零覆盖** —— 这正是 §4.2 不可判边界的来源，阶段二报告必须登记（§7）。
要复跑时配方 = `notes/p7b_tool_debt_20261010/task2/setup_sims.py`（重建 4 个独立目录 + 2×2）或单跑
`xvlog → xelab work.tb_mdio_master -s tb_sim → xsim tb_sim -runall`（独立目录，避 `xsim.dir` 文件锁，坑 7）。
⚠️ 单跑时 **不要**用 `_proj_mdio/_sim`（历史目录有旧 `xsim.dir`）。

---

## §4 板测计划（次序 + 代价 + 判据 + 对照）

### 4.0 前提与现态（全部现核，零成本）

- 板 = **0x24 + 受控停流**（F11）；烧 mdio 位流会**顶掉 0x24** ⇒ PCIe 端点消失（预期副作用，不是故障）。
- **mdio 设计无 PCIe 依赖**（现读：端口仅 `sys_clk_p/n / eth_mdc / eth_mdio / eth_rstn`；XDC 注释逐字"only ever loaded over JTAG"）
  ⇒ **不需要**厂商设计在场、**不需要**重开板、**不需要**对端机改状态；**判活方式 = VIO over JTAG**（不是 `lspci`/`reg_rw`）。
- 前提检查（各 1 条命令）：对端可达（`tools/peer_ssh.py`）· `systemctl is-active hw_server`（应 `active`）· `get_hw_targets` 非空。
- 记录烧前现态（对端 `reg_rw /dev/xdma0_user 0x04 w` = `0x00000024`；`0x08 w` = `0x2`）作 PRE 见证。
- ⛔ 纪律：mdio 构建与烧录**不得并行**（构建期间不烧被构建设计；也不与任何 Vivado 大构建共机，见"自己造成的资源争抢会产生假红"）。

### 4.1 步骤 1：烧 mdio 位流（约 3-5 min）

**工具 = 主树 tcpreg launcher**（它带 1MHz + 五判据；`probe_phy.tcl` 的烧录段没有这两条，见 F9/§5）：

```bash
export MSYS_NO_PATHCONV=1
TCPREG_BIT='D:\repo\XCKU5PMini\_proj_mdio\pj_mdio\mdio_prj.runs\impl_1\mdio_vio_top.bit' \
  cmd /c "D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p7b_biz_tcpreg\run_program_tcpreg.bat"
```
（模板 = `notes/p9_uram_ab_20261014/_tools/burn_arm.sh:53`，其 §3 的五判据 grep 原样套用：
**End of startup status: HIGH** + **TCPREG_PROG_DONE** + **位流路径匹配** + **无 TCPREG-ABORT** + **stdout 新鲜度（mtime ≥ T0-5）**。）
烧后：`cp tcpreg_program_stdout.txt <轮目录>/BURN_mdio_<TS>.txt`（该 stdout 是跟踪文件、每次烧录必被覆盖 —— 已知机制[D-6]，**先拷再干别的**）。
预期副作用：PCIe 端点消失（`lspci` 留陈旧条目、配置空间 `ffffffff`）—— **不要去 remove/rescan**（mdio 阶段无 PCIe 可恢复；把恢复留给 §4.4）。

### 4.2 步骤 2：VIO 探测（地址 0/1 实验 + 新位读取；约 5-15 min）

**驱动脚本**：新建 `probe_mdio_v2.tcl`（轮目录；基础 = `probe_phy.tcl`，**去掉自带烧录段 `:53-61`** —— 烧录已在 §4.1 完成）：
- 保留：`connect_hw_server -url 192.168.0.38:3121` / `open_hw_target` / `refresh_hw_device` / `findprobe` / `vset` / `vget`（五坑配方原样，见其头注释）；
- 改：`mdio_read` 返回 7 元组 `{rd done busy rstn mdio_i ssl pbad}`（位 = `15:0 / 16 / 17 / 18 / 19 / 20 / 21`）；
- 新：每条事务落一行原始记录（**收尾归档**）：
  `TX phyad=%02d regad=%02d rd=%04X done=%d busy=%d rstn=%d mdio=%d ssl=%d pbad=%d`；
- 新：臂 A/B(/C)（下）；收尾 `disconnect_hw_server`。
- stdout 全程 tee 到文件（判据面 = 原始 stdout，不是摘要）⇒ **本份 stdout = "{0,1} 同 ID" 的第一份一手存档**（F16）。

**臂 J-A · 全扫（复核，含既有负对照）**：32 地址 × {reg2, reg3}。
期望：应答地址集合**恰 = {0, 1}**，两者均 `{PHYID1=0x001C, PHYID2=0xC915}`（= 0x001CC915；⚠️ 该期望值 = **二手登记**（`tb_mdio_master.v:4` 头注释 + `REPORT.md:229`），一手 stdout 未在仓内 —— 见 F16）；其余 **30 个地址两寄存器均 0xFFFF**；
每事务 `done=1 / ssl=0 / pbad=0`。负对照（历史做过，本次要求**在同一份 stdout 里复现**）：2–31 的 `0xFFFF`（总线拉高 ⇒"没答"与"答 0"可分）。

**臂 J-B · 交错新鲜性（"同 ID ≠ 幻觉"主臂，约 1 min）**：顺序 `(1,r2)→(7,r2)→(0,r2)→(7,r2)→(0,r2)→(1,r2)→(31,r2)`。
期望：`001C / FFFF / 001C / FFFF / 001C / 001C / FFFF`。
判据形态：若 `rd_data` 是"回显/陈旧值"，静默地址会读回 `001C` —— 实测必须 `FFFF`；且除末对 `(0,r2)→(1,r2)` 相邻外，
每个 `001C` 都与前一个 `001C` 隔着至少一个 `FFFF`（即"静默读夹在中间"）⇒ 每次 `001C` 都是新事务。
**结构排除（不依赖板；⚠️ 范围限定）**：`mdio_master.v:111`（接受 start 即 `rd_sh<=0`）· `:118`（`rd_data<=0`）·
`:127-128`（只有真跑完帧才把 `mdio_i` 采样移入 `rd_sh`）⇒ 一次被接受的 start 之后，`rd_data` 只能来自**本事务**采到的线上位；
要到 `0x001C` 必须 **PHY 真的驱动了 TA=0 + 16 位数据**（拉高线读出来的是 `FFFF`）。
⛔ **本条论证的覆盖范围只到 master 端口以内**（其内部路径 TB 有专测）；**不覆盖** VIO 输出网段（见下"不可判边界"）。
**手册引用（预期解释）**：§0 第 4 行的 datasheet 原文 ⇒ "0 与 1 同 ID" = 广播地址的**预期行为**。

**臂 J-C · 写穿越（可选、低优先；仅在需要"同一颗芯片"的物理证据时做，约 3 min）**：
设计：`v0=read(1,r4)` → `write(1,r4,M1)` → `v1=read(1,r4)` → `write(1,r4,M2)` → `v2=read(1,r4)` → `read(0,r4)` → `read(8,r4)` → `write(1,r4,v0)` 还原。
先决条件（**先自证再下结论**）：`v1 != v2`（写-读回可区分）；否则本臂**降级为"不可判"如实记录**（备选寄存器 = reg 9 / PAGSEL 0x1F）。
判据形态：`read(0,r4) == v2` 且 `read(8,r4) == 0xFFFF` 且还原后 `read(1,r4) == v0`。
⚠️ 风险与恢复：reg 4 = ANAR；手册（同 PDF 提取文本 §7.12 区）逐字"**The setting of Register 4 has no effect unless NWay is restarted or the link goes down**"
⇒ 链路在跑时普通写**不生效于链路**；若 1G 链路恰好在下/重协商中，写会改广播能力 —— 恢复 = 还原原值 +（必要时）`force_rst` 复位 PHY。
⛔ 本臂**不**能区分"广播应答"与"地址字段位级错误"（见下"不可判边界"），价值 = 证明**读值随外部写入变化**（排除"定值表/回显"）。

**不可判边界（如实登记，不许写大）**：
单 PHY + 无 MDIO 示波器 ⇒ "PHY 应答广播地址 0" 与 "帧内 PHYAD 字段被改成 1" 两种世界在**本板上行为完全等价**（任何读/写序列结果相同）
⇒ **不许写"已排除地址字段伪影"**。可用的**结构论证只覆盖 master 端口以内**（5 位 PHYAD 与全部字段走**同一条移位链**、无按地址分叉的逻辑；
TB 对地址解码有专测；2–31 静默 = 端到端地址选择性的直接见证）。
⛔ **它不覆盖**：`vio_phyad` 从 **VIO core 输出寄存器 → 网 → 端口 → `sh[27:23]` 装载**这一段（`mdio_vio_top.v:130`，**改后 :134**）
—— 该网段**既无 TB 也无结构论证**，且该网段 **bit0 被置 1**（任一点，含 VIO 输出 FF）产生的可观察模式与"广播应答"**逐位不可分**：
主机写 0/1 ⇒ 线上都出 `00001`；写 2–31 ⇒ 出 `3/3/5…31`，均不应答 ⇒ 恰为"{0,1} 答、2–31 静默"的观察。
⇒ 真实等价类 = "**地址 bit0 在 VIO-out→MDIO 线路上被置 1**"，比"帧内 PHYAD 字段被改成 1"更宽。
风险评级 = **极低**（一段直连线；bit[4:1] 类 stuck 模式已被观察排除），**不要求补实验**，但阶段二报告**必须登记"VIO 网段未覆盖"**（§7 登记项 R-a）。

**臂 J-D · 新位读取（约 1 min）**：每条记录的 `ssl`/`pbad` 两列 = 0（生产臂）。
⛔ **陷阱（必须写进报告）**：`param_bad` 是**常量 0**、`stat_start_lost` 在**宿主不可触发**（见 §4.3）⇒
"恒 0"与"未接线"读数上**不可区分** ⇒ 本臂**不能**声称"两个新信号已在板上验过"。

### 4.3 步骤 2b：A+ 变体臂（可选；**推荐** —— 两个新位的板上正控只此一路；约 +10 min。⚠️ 前置 = E7/E8，**未做**）

为什么必须靠变体：`stat_start_lost` 只在 busy 期来 start 才置位，而 **busy 窗 32 µs ≪ JTAG commit 间隔（~数十 ms）**
（`mdio_vio_top.v:88-91` 头注释即此数，**改后 :90-93**）⇒ 生产臂**宿主无法制造**该条件；`param_bad` 是 elaboration 常量 ⇒ 生产臂恒 0。
变体（E7/E8）：`DIV=65537` ⇒ 钳到 65536 ⇒ ①`param_bad=1` ②帧时长 = 128×65536×10 ns = **83.9 ms**（宿主可感）。

1. 跑 `build_mdio_divbad.tcl`（§3.2），得 `pj_mdio_divbad/…/mdio_vio_top.bit` + 自己的 `.ltx`（登记 sha）。
2. 按 §4.1 同法烧（TCPREG_BIT 指变体位流；五判据同）。
3. VIO（用变体 `.ltx`）：
   - **P1**：读 `pbad`（bit20）期望 = **1** ⇒ 与生产臂的 0 构成**跨构建对照**（钳死/接错的位不可能随构建翻转）；
   - **P2**：一次事务的完成延迟 ≈ 83.9 ms（可粗测：commit start 后轮询 done_sticky 的等待感，或读 `busy` 位概率）；
   - **P3**：`ssl` 触发尝试（重试 ≤5 次）：commit(`start=1`) → 立即 commit(`start=0`) → commit(`start=1`)
     （第二上升沿落在 83.9 ms busy 窗内 ⇒ `ssl`=1）；随后等 done、再 commit 一次**干净** start（被接受 ⇒ 清位）⇒ `ssl`=0。
     ⚠️ 若某次 commit 延迟 >83.9 ms（工具抖动），触发会错过 ⇒ **如实记"未触发"（≠ 缺陷）**，最多重试 5 次；
     变体臂的 MDC = 762.9 Hz（合法慢端，无下限），PHY 读仍应答（顺带复核 ID）。
4. 变体臂结束后**生产臂不需要重烧**（若先做变体后做生产，则顺序反过来；最终以 §4.4 收尾）。建议顺序：**生产臂先（含 J-A/B）、变体臂后**，减少一次烧录。

### 4.4 步骤 3：收尾 —— 重烧 0x24 + PCIe 恢复 + **硬判据核身份** + 恢复受控停流（约 5-8 min，**不可省**）

```
bash notes/p9_uram_ab_20261014/_tools/burn_arm.sh 0x24 <seq>     # 原脚本原地跑（审计过的单一路径）
```
**该脚本的硬门与软判（必须知道哪几段是硬的）**：
- **硬（`exit 1`）**：烧前 sha256 门（`:43`；须 = `e3b07957…f1db`）+ 烧录五判据（`:60-64`：HIGH / DONE / 路径 / 新鲜度 / 无 ABORT）。
- **软（只打印）**：第 4 段 PCIe 恢复 —— 设备级 `remove`+`rescan`，`:72` 读宽度、`:73` 打印具名行、`:74-77` 升级分支（**只升级、不判失败**；根端口号**动态推导** `:68-69` —— warn：`0000:00:1c.0`、`0000:02:00.0` 都是**历史观察值**，按现读 `RP_PORT=` 行登记）；`:78` 打印**终态** `--- lspci ---` 块。
- **软（只打印）**：第 5 段"身份门"（`:83-86`）—— 全为 `echo`/读数，**无 `exit 1`**（`ID_RC` 只打印不判）。⚠️ **这是本步必须自己收口的地方。**

**⛔ 阶段二轮内必须显式执行的三条硬判据**（对 burn 日志 `grep -q`，不中即停、不带病离板）。**判据 2 已按复审 中-1 改锚（不再用具名行）**：

| 硬判据 | 来源行（burn 日志） | 期望 | 判法 |
|---|---|---|---|
| `ID_RC=0` | `:85`（`… p7b_snap.sh id; echo ID_RC=$?`）的输出 | `ID_RC=0` | `grep -q '^ID_RC=0$'` |
| **终态链路宽度 = x4** | **`:78` 的最终 `--- lspci ---` 块（升级分支**之后**）里的 `LnkSta:` 行** | `LnkSta:	Speed 5GT/s (downgraded), Width x4`（形态） | `grep -qE 'LnkSta:.*Width x4'` |
| `BID_0x04=0x00000024` | `:84` 的输出 | `BID_0x04=Read 32-bit … : 0x00000024` | `grep -q 'BID_0x04=.*0x00000024'` |

**为什么不用具名行（中-1 的缝）**：`FIRST_RESCAN_LNKSTA_WIDTH=`（`:73`）**只在设备级首次 rescan 后打印一次、且位于升级分支（`:74-77`）之前**
⇒ "首次 x1 → 升级后 x4"（恰 R7 场景）会让该行显示 x1；把它当判据 = **必假红**，且与 R7"升级后仍须再过硬判据"自相矛盾。
⇒ 该行**降级为见证量**（记录：它非 x4 而终态 LnkSta 为 x4 ⇒ 升级分支被激励且成功），**不作判据**。判据 2 锚 `:78` 的终态块（if/fi **之后**）—— 构造上就是"升级后的重核"。
⚠️ **方向声明**：原缝的失效方向 = **假红**（**停手而非带病离板** ⇒ 方向安全）；但"恒红"的判据**在成功路径上也不可为真** ⇒ 它不是真判据（要么卡死每一轮、要么被当噪声绕过）⇒ **必须消缝**。
⚠️ **附加观察（E-0；未实跑验证）**：`W=$(… \| grep -o "Width x[0-9]*" \| head -1)`（`:72`）取**首个** `Width xN`；按 lspci 标准输出顺序（`LnkCap:` 先于 `LnkSta:`）该值 = **能力位宽（恒 x4）** ⇒ 升级触发条件可能**结构性不触发**。⇒ 若阶段二遇"设备级只到 x1 而脚本未升级"：**手动**执行根端口级 remove+rescan（=`RP=` 行给出的端口），再回到本表判据 2 复核。

**建议同核（增强，非最低要求）**：`MAGIC_0x00=0x50360001` · `UNIMPL_0x14C=0xffffffff` · `dmesg identify_bars: 2 BARs` · `/dev/xdma0_{user,control,c2h_0,h2c_0}` 四节点在。
做法 = 三行（+建议行）写进轮内脚本：`grep -q '<期望串>' <burn log> || { echo "COLLAPSE_IDGATE_FAIL"; exit 1; }`，原始日志随轮归档。
⚠️ 其 [D-6] 机制照旧：跑完把 `burn/BURN_0x24_S<seq>_*.txt` 拷进轮目录。
**最后一步（脚本没有、必须手动补）**：恢复**受控停流**（与测试前现态一致）：
`reg_rw /dev/xdma0_user 0x08 w 0x2` → 核 `CARRIER=0`（`cat /sys/class/net/enp1s0f1np1/carrier`）。
（备选 = 留在 `0x08=0`（发流态）；但那会改变工程现态，**默认按恢复受控停流走**，要改口径须先经 TL。）

### 4.5 时间预算汇总

| 步 | 内容 | 估计 |
|---|---|---|
| 0 | ~~归档~~（**已做**，§3.1）+ 烧前现态 | 1 min |
| 0b | 跑 elab 门（§3.4；**先核 10-3609 锚点**） | 1-2 min |
| 1 | 生产构建（§3.2，小设计） | 3-6 min |
| 2 | 烧 mdio 位流（§4.1） | 3-5 min |
| 3 | VIO：J-A + J-B + J-D（§4.2） | 5-15 min |
| 3b | （可选推荐）变体构建+烧+VIO（§4.3；**需先做 E7/E8**） | +10-15 min |
| 3c | （可选）J-C 写穿越 | +3 min |
| 4 | 收尾重烧 0x24 + PCIe 恢复 + **硬判据**（§4.4） | 5-8 min |
| — | **合计** | **约 18-40 min**（不含可选项 ≈18 min；含全部可选项 ≈45 min） |

---

## §5 纪律核对（全程符合性自查）

**5.1 绝不写 QSPI（硬纪律）—— 本计划全程符合**：
- 构建侧：`build_mdio.tcl` 只产 `.bit`（无 `.bin`、无 `write_cfgmem`）—— 现读确认。
- 烧录侧：`program_tcpreg_ku5p.tcl` 只做 `set_property PROGRAM.FILE` + `program_hw_devices`（JTAG 易失）—— 现读确认。
- ⚠️ XDC 里的 `BITSTREAM.CONFIG.SPI_BUSWIDTH / CONFIGRATE` 与 `CONFIG_MODE SPIx4`（`ku5p_mdio.xdc` 尾 3 行）
  **只写进位流头**（"stays QSPI-compatible if that is ever wanted"），**不构成对 Flash 的任何操作** ⇒ 保留原样，别删也别扩。
- 全计划唯一"写 Flash"的路径 = 不存在的路径；收尾恢复 0x24 也走同一 JTAG 易失路径。

**5.2 烧录工具链推荐（现读判断）**：
- **推荐 = 主树 tcpreg launcher**（`run_program_tcpreg.bat` + `program_tcpreg_ku5p.tcl`）：唯一被审计过、带 **1MHz 降频**（该语句在 `program_tcpreg_ku5p.tcl:`**`14`**，见 F9 订正）+ **DONE 检查点** 的路径；mdio 位流与 0x24 恢复都走它。
- **不推荐**用 `probe_phy.tcl` 的**自带烧录段**：它**无 1MHz、无 DONE 检查**（F9 现读）。⇒ v2 驱动脚本**去掉烧录段**（§4.2），只连 JTAG 读 VIO。
- `list_probes.tcl`（本目录）是历史排障件，含**绝对路径**的 PROBES.FILE —— 不用于本轮。

**5.3 版本控制与归档**：
- `_proj_mdio` **不在任何 git 仓库内**（F13）⇒ §3.1 的改前归档 + 旧产物归档是**唯一回退来源**（**已由实施轮完成并自核**）。
- 实施轮**零 git 写**（其 git 可见增量 = 新目录 `_proj_10g/notes/p9_fix_mdio_impl_20261015/`，未提交；另两处 modified = 平行会话的 F-3 实施轮，与本件无关）。
- 后续轮**不做 git 写**（提交由 TL 统一）；笔记树入库与否按仓库现规（log 已放行入库）。

---

## §6 风险与回退

| # | 风险 | 处置 |
|---|---|---|
| R1 | 烧 mdio 后 **PCIe 端点消失**（预期副作用） | 不当故障处理；留到 §4.4 统一恢复。⚠️ 期间 `reg_rw`/`identify_bars` 不可用，**判活只用 JTAG/VIO** |
| R2 | 烧 mdio 失败（无 `HIGH` / `TCPREG-ABORT`） | 五判据会先拦下（无 HIGH 即停）；重试一次；仍失败 ⇒ 查 hw_server / JTAG 线 / 对端可达；**任何情况下都不认为"板坏了"**（板子没被写过 Flash） |
| R3 | VIO 找不到 / 零探针 | 顺序查：① `.ltx` 是否与 bit 同目录同名（v2 脚本按 `rootname(bit).ltx`）；② `refresh_hw_device` 是否在 program 之后；③ 探针名是否 = 网名 `vio_probe_in`（五坑之②）；④ 五坑之③：`commit/refresh` 传 **hw_vio CORE** 不传探针 |
| R4 | 板上读到的位序不对（新位没在 [21:20]） | 先用 `get_property WIDTH` 核 22；再用**可翻转的旧位**（busy/eth_rstn/mdio_i）验证位置语义；最后才怀疑 E5 的拼接顺序（§2.0-E5） |
| R5 | A+ 臂 `ssl` 触发反复错过（commit 延迟 >83.9 ms） | 如实记"未触发"（≠ 缺陷）；最多 5 次重试；`pbad=1`（P1）不依赖触发时序，仍成立 |
| R6 | J-C 写后 reg4 读回不区分（或链路受影响） | 本臂是"可选/低优先"：读回不区分 ⇒ 记"不可判"（勿硬凑）；链路受影响 ⇒ 还原原值 + `force_rst` 复位 PHY（`vio_force_rst` 现成） |
| R7 | 收尾 0x24 恢复失败（终态 `LnkSta` 非 x4 / 无 `/dev/xdma0_*`） | ① 依 `burn_arm.sh` 的**升级分支**：设备级 remove+rescan 不够 ⇒ **根端口级**（根端口号**动态推导** `:68-69`，按现读 `RP_PORT=` 登记）remove+rescan；② ⚠️ **升级分支只升级不判失败、且其触发条件可能结构性不触发（E-0 附加观察）** ⇒ 若"设备级只到 x1"而脚本未升级 ⇒ **手动**执行根端口级操作；③ **收口一律回 §4.4 判据 2（终态 `LnkSta:` 行）** —— 该判据锚在升级**之后**、不受上述触发问题影响；仍不行 ⇒ 对端机重启（POST 时板已在跑 0x24 ⇒ 场景 A/B）。⚠️ 全程**不许**动板载 QSPI |
| R8 | 板在 mdio 态"不配合"（JTAG 掉线等） | 最后手段 = 板断电重启（恢复 QSPI 厂商设计 + JTAG 可用；⚠️ 厂商设计在场时按"场景 C"恢复 PCIe：连根端口一起 remove+rescan）⇒ 再烧 0x24 |
| R9 | 变体臂位流 sha == 生产臂 sha | 构建没生效 ⇒ 停手，检查 E8 两处改动（项目目录 + generic） |
| R10 | 行号漂移（**本件已按低-B 处置**） | 引用 `mdio_vio_top.v` 一律 **锚点文本 + 改前/改后双行号**（§2.0）；再次编辑后**全体重取**（台账 §9-5-11 同款纪律） |
| R11 | elab 门第一次跑，"编译顺序 ⇒ 生效定义"锚点不成立 | §3.4：**先核 10-3609 锚点 = `vio_0.v:49`**；不是 ⇒ 停手、别信那次通过 |

---

## §7 本件边界与"不许声称"

- 本件 = **设计件（计划）**；实施由 TL 派单；本件**零上板/零构建/零改文件**（唯一写 = 本目录）。
- ⛔ **不许**把本件当作任何功能"已验证"的声明；下列口径必须沿用到后续轮报告：
  ① **两个新信号（param_bad / stat_start_lost）的行为验证在 xsim（已完成），板级（生产臂）只能给"出现且恒 0"** —— 恒 0 与未接线不可区分；
  ② **"地址 0/1 同 ID"= 手册预期（广播地址）**；板上实验给的是"确认 + 新鲜性"，**不是**"排除了地址字段伪影"
     —— 真实等价类 = "地址 bit0 在 VIO-out→MDIO 线路上被置 1"（比"帧内"更宽；结构论证只到 master 端口以内，VIO 网段无覆盖）；
  ③ **生产位流未做过功能仿真**（`mdio_vio_top` 只有 elaboration 级见证；行为级 = mdio_master 单元 TB，而该 TB **不例化 top**）；
  ④ **elab 门尚未运行**（就位 ≠ 通过）；**构建/上板未做**；**E7/E8 未做**。
- ⛔ 引用旧读数一律带位流 sha 与"哪一代"；旧 mdio 位流（`46417aff…`）与新构建位流**只有 sha256/字节数不同可判**。

### §7.1 阶段二报告**必载登记项**（照抄进轮报告的"未观测/不可判"节）

| 登记项 | 内容 | 来源 |
|---|---|---|
| **R-a** | **VIO 网段未覆盖**：`vio_phyad`（VIO core 输出 → 端口 → `sh[27:23]` 装载，`mdio_vio_top.v:130`，改后 :134）**无 TB、无结构论证**；该网段 bit0-stuck 与"广播应答"逐位不可分（等价类见 §4.2 末）。风险极低、不要求补实验 | 首轮复核 M1 |
| **R-b** | **两个新信号 = "出现且恒 0"**（生产臂）：恒 0 与未接线不可区分；行为验证仅在 xsim。若未做 A+ 臂，**不许**声称"新信号已在板上验过" | 本件 §4.2 J-D |
| **R-c** | **历史板测无一手存档**："{0,1} 同 ID"的原始 stdout 未在 notes 找到逐字件；`0x001CC915` 期望以 `tb_mdio_master.v:4` + `REPORT.md:229` 二手登记为源；本轮的 v2 驱动 stdout = 第一份一手存档 | 首轮复核"未核部分" |
| **R-d** | **原理图搭接注记 = 外部一手件**：`PHY_ADDR[2:0]=001` 来自原理图注记（不在仓内），只能转述；"1 应答 / 2–31 静默"是板上侧证但非该注记的直接读数 | 首轮复核"未核部分" |
| **R-e**（v2r2 新增） | **elab 门的"生效定义"锚点未实跑验证**（§3.4；第一次跑先核 `10-3609` 锚点 = `vio_0.v:49`）；且门**不覆盖** VIO 网段与"没驱动的 wire"形态 | 实施轮 GATE_NOTES |

---

### 附A · 已读/现核的工具与原件索引（可逐条复跑）

| 用途 | 路径 | 现读关键值 |
|---|---|---|
| 缺陷报告（母件） | `notes/p7b_tool_debt_20261010/REPORT.md` §2 + §4-3 | 改动清单/判据/未做到三格 |
| **首轮对抗复核** | `notes/p9_xreview_kimi_fix4_20261014/BUNDLE_MDIO.md`（95 行，commit `b15e43d`）+ `INDEX.md` | neg_ctrl 双过 + 中 2 / 低 6 |
| **实施轮（v2r2 状态依据）** | `notes/p9_fix_mdio_impl_20261015/REPORT.md` + `gate_elab_22/GATE_NOTES.md` + `archive_20260928/`（15/15 OK）+ `pre_edit/`（7/7 OK） | E1-E6 已落盘；两新 sha；门就位未跑 |
| RTL diff（工具债轮） | `…/p7b_tool_debt_20261010/mdio_master.diff` | 完整逐行 |
| pristine 保全 | `…/p7b_tool_debt_20261010/pristine/{mdio_master.v.orig,tb_mdio_master.v.orig,SHA256_PRISTINE.txt}` | 旧 sha `6a0b4c58…` / `3c23ea04…` |
| 2×2 矩阵原件 | `…/p7b_tool_debt_20261010/task2/{_rm1..4_*.stdout.txt, rm*/}` | FAIL(4 errors)/PASS 逐字 |
| elaboration 门（骨架） | `…/p7b_tool_debt_20261010/task2/elab_wrapper/{run.bat,vio_0.v,...}` | `XELAB_RC=0` + 10-3645 在案（stdout 在 **`task2/` 根**；目录内对应物 = `xelab.log:8`；**`xvlog.log:9` = 10-3609 覆盖见证**）|
| 器件手册 | `资料\PDF\RTL8211E-VB-CG.pdf`（**§7.7 Table 13 的 PHYAD[2:0] 行** / §7.10.4 / reg4 Note） | "PHY address 0 is a broadcast" |
| 烧录 launcher | `notes/p7b_biz_tcpreg/{run_program_tcpreg.bat,program_tcpreg_ku5p.tcl}` | 1MHz 语句在 **`:14`** + 五判据模板 |
| 烧录+恢复 launcher | `notes/p9_uram_ab_20261014/_tools/burn_arm.sh` | 硬门 `:43`/`:60-64`；**软段 `:68-86`**（`:73` 具名行仅一次且在升级前 · `:74-77` 升级分支 · **`:78` 终态 lspci 块** · `:83-86` 身份段） |
| 0x24 位流真值 | `notes/p9_build_0x24/wrapper_p4.bit`（另两处副本同 sha） | `e3b07957…f1db` |
| 板现态 | `notes/p9_uram_ab_20261014/runs/FINAL_STATE_20261014_004453.txt` | `0x04=0x24` / `0x08=0x2` |
| 清单登记 | `notes/P7B_OPEN_ITEMS.md` **§0 条目 #18（文件行 69）** | 三格登记（核对一致） |
| 台账条目 | `notes/P7B_TL_LEDGER_20261010.md:1055`（§10-55 ④） | mdio 设计件概括（其"5 编辑点"口径见 §2.0） |

**本件（设计轮）写操作 = 本目录内文件**（`DESIGN.md` v1 · `DESIGN_v2.md` · 本 `DESIGN_v2r2.md` 三件并存，前件原样保留）。
零改 `_proj_mdio`/rtl/sim · 零跑 Xilinx 工具 · 零上板 · 零 git 写 · 零碰板。⛔ **本件不含 PASS/FAIL 裁定**（裁定权在判据所有者）；
一切"期望值"均为**物理预期/判据形态**，不是验收裁定。⛔ **本件状态 = 待 kimi 即审**。
