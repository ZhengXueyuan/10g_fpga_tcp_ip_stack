# p9_fix_mdio 设计件 —— `_proj_mdio` 工具链尾项 · 实施计划（implementation-ready）

- 件名：`p9_fix_mdio_design_20261014` · 日期：**2026-10-14** · 性质：**只调查 + 写计划**
  （本 agent 唯一写操作 = 新建本目录；**零改文件 / 零 Vivado / 零 xsim / 零上板 / 零 git 写 / 零碰板**）
- **读者**：阶段二实施 agent（**零上下文可照做**）。范围 = `_proj_mdio` 三件尾项：
  ① VIO 探针位宽同步（新信号板上可见）② 重建位流 ③ MDIO 地址 0/1 板测。
- ⛔ **本件不做 PASS/FAIL 裁定**（裁定权在判据所有者）。本件只给：编辑锚点 / 构建配方 / 板测次序与代价 / 判据形态 / 回退。
- 路径约定：`_proj_mdio` 相对 `D:\repo\XCKU5PMini\`；`notes/...` 相对 `D:\repo\XCKU5PMini\udp_hls_10g\`。
- 行号约定：本件所有行号 = **2026-10-14 现读值**（引用前现读，见台账纪律）。

---

## §0 一页结论（含与派单描述的逐条核对）

派单四条陈述，现核结果：**三条属实；一条属实但需两处补正；一条的"待查"性质被本轮新证据改写**。

| # | 派单描述 | 现核 | 差异（如实，不迁就） |
|---|---|---|---|
| 1 | `_proj_mdio` 的 RTL 两潜伏项已修（`p7b_tool_debt_20261010/`） | ✅ **属实** | `rtl/mdio_master.v` 现读 sha256 `89d5c89e295ce988b2013ecdb07f94d158001e0ef1e5585020f82e481f8d35db`（7,274 B）· `tb/tb_mdio_master.v` `8c8dc2c83c09cc9a80bfc9995c6e55233095369de5cc67612e65e4581bc10d7d`（21,858 B）—— 与 `notes/p7b_tool_debt_20261010/REPORT.md` §2.2 逐字一致；pristine 保全件在 `…/pristine/` |
| 2 | VIO 探针位宽同步（**两处**）未做 | ✅ 属实，但**"两处"只是文件数、不是编辑点数** | 现读：`build_mdio.tcl:30` = `{20}` · `mdio_vio_top.v:86` = `[19:0]` · `:143` = 20 位拼接。**并且例化处（`:123-141`）根本没有接两个新端口**（工具债轮 xelab 实测 `VRFC 10-3645 port 'param_bad' remains unconnected [mdio_vio_top.v:123]`）⇒ 实际需 **5 个编辑点**（§2）。⚠️ **两种半改的死法**：只改两处位宽不接拼接 ⇒ **编译合法但新两位恒 0（静默无效）**；只加拼接不接例化 ⇒ 两 wire 无驱动（悬空）。故 E1-E5 **必须同批** |
| 3 | 未重建位流 / 未上板 | ✅ **属实** | `pj_mdio/` 全部产物 mtime = **2026-09-28 20:34-20:35**（修复前）；旧位流 sha256 `46417affc544e6a51e2eff8cafa473afaad5384cd1b17e033d1a31800d692ad2`（15,431,263 B）；旧基线 `timing_summary.rpt`：**WNS +7.091 / WHS +0.020 / WPWS +4.427，三列失败端点全 0**；旧资源 = CLB LUT 687 / Reg 1,345 |
| 4 | MDIO 地址 0/1 同 ID 仍待板测 | 属实（未结项），但 ⭐ **本轮现读器件手册找到预期解释，性质从"怪现象"变为"手册预期行为 + 需排除宿主侧伪影"** | RTL8211E datasheet（本机 `资料\PDF\RTL8211E-VB-CG.pdf`，Rev 1.6）§7.7 Table 13 **逐字**："PHYAD sets the PHY address for the device. The RTL8211E-VB(VL)/RTL8211EG-VB support PHY addresses from 00001 to 00111. **PHY address 0 is a broadcast from the MAC; each PHY device should respond.**" ⇒ 地址 0 = **广播**（每个 PHY 都应答），地址 1 = 搭接地址（原理图注记 `PHY_ADDR[2:0]=001`）⇒ **"0 与 1 同 ID" 正是手册预期**。实验目的随之改为"确认 + 排除宿主侧伪影"（§4.2），并**如实登记一条不可判边界**（单 PHY + 无 MDIO 示波器时，"广播应答"与"帧内地址字段位级错误"行为等价，§4.2 末） |

**阶段二一行话**：按 §2 改 5 个编辑点（可选 +1 变体参数）→ 按 §3 **先归档后重建**（得新 bit + 新 .ltx + 新 sha256）→ 按 §4 板测
（**先烧 mdio 位流；收尾必须重烧 0x24 + 恢复受控停流**）→ 全程只走 **JTAG 易失**，**绝不写 QSPI**。

---

## §1 现状现读（事实表；行号 = 2026-10-14 现读）

| # | 位置 | 逐字（现读） | 含义 |
|---|---|---|---|
| F1 | `_proj_mdio/rtl/mdio_vio_top.v:86` | `    wire [19:0] vio_probe_in;` | 探针输入 20 位 = 旧 5 字段 |
| F2 | `…:143` | `    assign vio_probe_in = {mdio_i, eth_rstn, busy, done_sticky, rd_data};` | 位映射：`[15:0]` rd_data · `[16]` done_sticky · `[17]` busy · `[18]` eth_rstn · `[19]` mdio_i |
| F3 | `…:123-141` | 例化 `mdio_master #(.DIV (25)) u_mdio_master ( … .mdio_i (mdio_i) );` | **未接** `.param_bad` / `.stat_start_lost`（两新端口悬空） |
| F4 | `…:109-111` | `wire [15:0] rd_data; / wire done_sticky; / wire busy;` | 现无两新信号的 wire 声明 |
| F5 | `_proj_mdio/rtl/mdio_master.v:54-55` | `output wire param_bad, // 1 = DIV out of range, clamped (static)` · `output reg stat_start_lost // sticky: a start arrived while busy (dropped)` | 两新信号 = **本轮要引出的 2 位** 的**全部**（无第三处） |
| F6 | `…mdio_master.v:75/160-163` | `assign param_bad = PARAM_BAD;` / `if (!busy && start) … =0; else if (busy && start) … =1;` | `param_bad` = **elaboration 常量**（DIV=25 ⇒ 0，板上恒 0）· `stat_start_lost` = 1 FF，**只在 busy 期来 start 才置位** |
| F7 | `_proj_mdio/build_mdio.tcl:30` | `    CONFIG.C_PROBE_IN0_WIDTH {20} \` | VIO IP 位宽参数（与 F1 必须同批改） |
| F8 | `_proj_mdio/probe_phy.tcl:22-28` | 注释位图（`probe_in0[19] mdio_i` 收尾） | 宿主侧位图注释；`mdio_read`（`:123-137`）按 **位位置** 解码 `[19:16]` ⇒ 新位放 MSB 端则旧脚本**零回归** |
| F9 | `…probe_phy.tcl:53-61` | `set_property PROGRAM.FILE $bit $dev` + `program_hw_devices` | ⚠️ 该脚本**自带烧录**，但**无 1MHz 降频、无 DONE 检查**（对比 `notes/p7b_biz_tcpreg/program_tcpreg_ku5p.tcl:16` 有 `set_property PARAM.FREQUENCY 1000000`）⇒ 见 §5 工具链推荐 |
| F10 | `_proj_mdio/pj_mdio/…/impl_1/mdio_vio_top.bit` + `.ltx` | 15,431,263 B / 14,414 B，均 **2026-09-28 20:34** | 旧位流与探针文件在盘；.ltx 与 bit **同目录同名**（`probe_phy.tcl:40` 按 `[file rootname $bit].ltx` 定位） |
| F11 | 板侧现态（p9_uram_ab 轮 `FINAL_STATE_20261014_004453.txt`） | `0x00=0x50360001` · **`0x04=0x00000024`** · `0x08=0x00000002`（受控停流）· `0x14=0xdeadbeef` · `0x13C=0x00220000` · `0x144=0` · `0x148=0x0feb1416` · `0x14C=0xffffffff` | 板现跑 **0x24 + 受控停流**；恢复 = `reg_rw /dev/xdma0_user 0x08 w 0x0` |
| F12 | `notes/p9_build_0x24/wrapper_p4.bit` | sha256 `e3b07957aea0326a168b9db0238ef9dd933dc7a21884c92e50a7c3b0abadf1db`（15,431,261 B；三处副本同 sha） | 收尾重烧的**唯一真值**（§4.4） |
| F13 | 版本控制现状 | `D:\repo\XCKU5PMini` **不是 git 仓库**；`udp_hls_10g` 是仓库但**不含** `_proj_mdio` | ⇒ `_proj_mdio` 的 4 个被改文件**没有任何版本控制兜底** ⇒ §3.1 的**改前归档是回退的唯一来源**（必须做） |
| F14 | 器件手册（本轮新证） | `资料\PDF\RTL8211E-VB-CG.pdf` §7.7 Table 13 逐字 | 地址 0 = 广播、地址 1..7 = 搭接地址；另有 `PHYAD[2:0]=000` 时"自动记住第一个非零地址"的注释（**本板不适用**——本板搭接 = 001，已由"1 应答 / 2–31 静默"见证） |

---

## §2 编辑清单（精确到行；锚点 = 现读逐字，替换/插入型分别标注）

同一文件内的编辑**必须同批**（只改一半 = 悬空位或位宽不匹配）。全部为 `_proj_mdio/` 内文件（F13：无 git 兜底，先做 §3.1 归档）。

### 2.1 必做编辑（生产构建）

**E1~E5 · `_proj_mdio/rtl/mdio_vio_top.v`**（改前 sha256 `e9c0c74cac71e98caed48030e66a70d574eb55f6539622a8a0553d7aabe6fab3`，4,829 B）

- **E1（注释位图，插入型）** 锚点 = 第 27 行：
  `//   probe_in0  [19]    mdio_i   (live line level)`
  在其**后**插入两行：
  ```
  //   probe_in0  [20]    param_bad        (DIV out of range -> clamped; static)
  //   probe_in0  [21]    stat_start_lost  (start arrived while busy; sticky)
  ```

- **E2（声明，替换型）** 第 86 行：
  `    wire [19:0] vio_probe_in;`
  →
  `    wire [21:0] vio_probe_in;`

- **E3（新 wire 声明，插入型）** 锚点 = 第 111 行 `    wire        busy;`
  在其**后**插入：
  ```
      wire        param_bad;          // from mdio_master (2026-10-10 additions)
      wire        stat_start_lost;
  ```

- **E4（例化接线，替换型）** 第 140-141 行（该两行在文件内唯一）：
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
  （命名端口例化，顺序无关；放末尾与 RTL 端口表末尾追加一致）

- **E5（拼接，替换型）** 第 143 行：
  `    assign vio_probe_in = {mdio_i, eth_rstn, busy, done_sticky, rd_data};`
  →
  `    assign vio_probe_in = {stat_start_lost, param_bad, mdio_i, eth_rstn, busy, done_sticky, rd_data};`
  ⭐ **位序是本件的关键设计决定**：新位放 **MSB 端** ⇒ 新映射 = `[21] stat_start_lost · [20] param_bad · [19:0] 逐位不动`
  ⇒ 旧读数脚本（按位位置解码）**零回归**；REPORT §2.4-2 的 `{stat_start_lost, param_bad, …}` 正是此序。

**E6 · `_proj_mdio/build_mdio.tcl`**（改前 sha256 `72f7bb8b5e06c3a855708a3154e394168dbe3d537b1cba82a8b36d7838f8a4bf`，2,456 B）

- **E6（替换型）** 第 30 行：
  `    CONFIG.C_PROBE_IN0_WIDTH {20} \`
  →
  `    CONFIG.C_PROBE_IN0_WIDTH {22} \`
  （该行是 dict 续行，**行尾反斜杠必须保留**）

### 2.2 可选编辑（A+ 变体臂专用；见 §4.3。推荐做，理由 = 两个新位的**板上正控只此一路**）

- **E7（`mdio_vio_top.v` 加顶层参数，插入型+替换型）**
  - 第 29 行 `module mdio_vio_top (` → 
    ```
    module mdio_vio_top #(
        parameter integer DIV = 25          // production 25; A+ arm overrides via build generic
    ) (
    ```
  - 第 124 行 `.DIV (25)                       // 100MHz / 25 -> 2MHz MDC`
    → `.DIV (DIV)                      // 100MHz / DIV -> 2MHz MDC at DIV=25`
  - 注明：默认 25 ⇒ **生产构建 elaboration 不变**；参数只被变体构建的 generic 覆盖。
- **E8（新文件）** `_proj_mdio/build_mdio_divbad.tcl` = `build_mdio.tcl` 的副本，改 2 处：
  ① 第 9 行 `set proj [file join $here pj_mdio]` → `… pj_mdio_divbad]`（**必须换项目目录**，否则 `create_project -force` 摧毁生产构建产物）；
  ② 第 20 行 `update_compile_order -fileset sources_1` **之后**插入：
  ```tcl
  set_property -name {STEPS.SYNTH_DESIGN.ARGS.GENERIC} -value {DIV=65537} -objects [get_runs synth_1]
  ```
  （`DIV=65537` ⇒ 钳到 65536 + `PARAM_BAD=1` ⇒ 板上可观测，见 §4.3）

### 2.3 替代路径（若不想动生产文件加参数）

E7 可换成"变体独立顶层"：复制 `mdio_vio_top.v` → `mdio_vio_top_divbad.v`（只改 `.DIV (25)` → `.DIV (65537)`），E8 的副本构建脚本把 `add_files` 的 top 换成该变体件 + `set_property top mdio_vio_top_divbad`。
**二选一即可；不要两条都做**（会产生两个可烧变体，登记混乱）。

### 2.4 `.ltx` / 探针命名一致性核对（构建后必做，零成本）

- 探针名 = **所连网的网名**（五坑之①）：本设计连到 `vio_probe_in` 网 ⇒ 名应为 `vio_probe_in`，**随构建自动更新**，无需手改。
- `.ltx` 由构建产出，落在 **bit 同目录同名**（`pj_mdio/…/impl_1/mdio_vio_top.ltx`）⇒ `probe_phy.tcl:40` 的 `[file rootname $bit].ltx` 能直接找到。
- 板侧核对 = `get_property WIDTH $P_STATUS` **== 22**（这是"探针位宽同步已生效"的**直接**判据，比读值可靠）。
- 宿主侧文档同步（推荐）：把 `probe_phy.tcl:22-28` 的位图注释补上 `[21:20]` 两行**或**（推荐）只在 v2 脚本里维护新位图（§4.2 的 v2 驱动），历史脚本原样留档。

---

## §3 重建位流计划

### 3.1 先归档（**必须先做**；`create_project -force` 开工即清 `pj_mdio/`）

全局教训 #54 同族：**每次构建都会摧毁上一次构建的取证**。本轮会丢的：旧位流、旧 `.ltx`、旧 `timing_summary.rpt` 与 impl 报告。
⚠️ 加重：`_proj_mdio` **不在任何 git 仓库内**（F13）⇒ 归档 = 唯一回退来源。

落点建议：`notes/p9_fix_mdio_<阶段二轮名>/archive_20260928/`（与 `pre_edit/` 两组）：

```
# ① 旧构建产物（6-7 件）
cp _proj_mdio/pj_mdio/mdio_prj.runs/impl_1/mdio_vio_top.bit            archive_20260928/
cp _proj_mdio/pj_mdio/mdio_prj.runs/impl_1/mdio_vio_top.ltx            archive_20260928/
cp _proj_mdio/pj_mdio/mdio_prj.runs/impl_1/debug_nets.ltx              archive_20260928/
cp _proj_mdio/pj_mdio/timing_summary.rpt                               archive_20260928/
cp _proj_mdio/pj_mdio/mdio_prj.runs/impl_1/mdio_vio_top_timing_summary_routed.rpt archive_20260928/
cp _proj_mdio/pj_mdio/mdio_prj.runs/impl_1/mdio_vio_top_utilization_placed.rpt    archive_20260928/
cp _proj_mdio/pj_mdio/mdio_prj.runs/impl_1/mdio_vio_top_drc_routed.rpt            archive_20260928/
sha256sum archive_20260928/* > archive_20260928/SHA256SUMS.txt      # 自核 + 记录
# ② 改前源文件（E1-E8 涉及的全部；mdio_master.v/tb 已有 pristine 保全，可连带拷求全）
cp _proj_mdio/rtl/mdio_vio_top.v  _proj_mdio/build_mdio.tcl  _proj_mdio/probe_phy.tcl  pre_edit/
sha256sum pre_edit/* > pre_edit/SHA256SUMS.txt
```
旧真值（供对账）：bit sha256 `46417aff…92ad2`（15,431,263 B）· `.ltx` 14,414 B ·
`timing_summary.rpt` WNS `+7.091 / WHS +0.020 / WPWS +4.427`（三列失败端点 0）·
`mdio_vio_top.v` = `e9c0c74c…fab3` · `build_mdio.tcl` = `72f7bb8b…a4bf` · `probe_phy.tcl` = `a16e50eb…5ec4`。

### 3.2 构建（配方 = 本工程既有入口，不新造）

```
# 在 Windows（bat 纪律：写 bat 再调；MSYS_NO_PATHCONV=1 与 cmd //c 并用会互相抵消）
cd /d D:\repo\XCKU5PMini\_proj_mdio
vivado -mode batch -source build_mdio.tcl -nojournal -nolog
```
stdout 期望形态（`build_mdio.tcl:40-67`）：`=== SYNTH ===` → SYNTH 100% → `=== IMPL ===` → impl 100% →
`TIMING_WNS …` / `TIMING_WHS …` / `TIMING_TNS …` → `BITSTREAM <path>` + `BITSTREAM_BYTES …` → `=== BUILD DONE ===`。
判据形态（不做裁定）：三类失败端点 0；WNS 应与旧基线**同量级**（+7 ns 级——本轮只 +1 FF + 常量 + VIO 6 位）；
若 WNS 掉到 <1 ns 量级 ⇒ **停手上报**（不应发生，属异常）。
变体臂（E8）同理跑 `build_mdio_divbad.tcl`，产物落 `pj_mdio_divbad/`。

### 3.3 产物记录（sha256 方式）

```
sha256sum -b _proj_mdio/pj_mdio/mdio_prj.runs/impl_1/mdio_vio_top.bit
ls -l     _proj_mdio/pj_mdio/mdio_prj.runs/impl_1/mdio_vio_top.bit _proj_mdio/pj_mdio/mdio_prj.runs/impl_1/mdio_vio_top.ltx
```
记 `BIT_SHA / BIT_BYTES / BIT_MTIME / LTX_BYTES / TIMING_WNS / TIMING_WHS / 失败端点数 / 新 mdio_vio_top.v 与 build_mdio.tcl 的 sha256`，
写进阶段二轮的 `READINGS.txt`。**变体臂位流单独登记**（与生产臂 sha 必须不同；相同 = 构建没生效，停手查）。
烧录前把该 sha 抄进烧录日志（§4.1 的判据链要用）。

### 3.4 可选预构建 elaboration 门（约 1 分钟，零风险提前抓接线错）

复用 `notes/p7b_tool_debt_20261010/task2/elab_wrapper/`（`run.bat` = xvlog 两 RTL + 真 `vio_0` 仿真网表 + `dbg_hub` + `glbl` → `xelab -L unisims_ver work.mdio_vio_top work.glbl`）：
1. 复制整个目录 → 阶段二轮目录；
2. 把目录里的 `mdio_master.v`/`mdio_vio_top.v` 换成**编辑后**的版本；
3. ⚠️ **`vio_0.v` 的 stub 第 60 行 `input [19 : 0] probe_in0;` 必须改成 `[21 : 0]`**（否则 xelab 会报
   `VRFC 10-3091 actual bit length 22 differs from formal bit length 20` —— 正是该判据要抓的形态）；
4. 跑 `run.bat`：期望 `XELAB_RC=0` 且 **`VRFC 10-3645` 对 `param_bad`/`stat_start_lost` 的警告消失**
   （旧件该警告在案：`_elab_wrapper.stdout.txt` 第 8 行；警告消失 = 接线已生效的编译级见证）。
   本门只证 elaboration（不含功能），口径别写大。

### 3.5 TB 回归（可选；说明为何非必须）

`mdio_master.v` / `tb_mdio_master.v` 本轮**一字不动**（E1-E8 只碰 top 与构建脚本）⇒ 2×2 矩阵结论（新 RTL×新 TB PASS 等）自动延续。
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
烧后：`cp tcpreg_program_stdout.txt <阶段二轮目录>/BURN_mdio_<TS>.txt`（该 stdout 是跟踪文件、每次烧录必被覆盖 —— 已知机制[D-6]，**先拷再干别的**）。
预期副作用：PCIe 端点消失（`lspci` 留陈旧条目、配置空间 `ffffffff`）—— **不要去 remove/rescan**（mdio 阶段无 PCIe 可恢复；把恢复留给 §4.4）。

### 4.2 步骤 2：VIO 探测（地址 0/1 实验 + 新位读取；约 5-15 min）

**驱动脚本**：新建 `probe_mdio_v2.tcl`（阶段二轮目录；基础 = `probe_phy.tcl`，**去掉自带烧录段 `:53-61`** —— 烧录已在 §4.1 完成）：
- 保留：`connect_hw_server -url 192.168.0.38:3121` / `open_hw_target` / `refresh_hw_device` / `findprobe` / `vset` / `vget`（五坑配方原样，见其头注释）；
- 改：`mdio_read` 返回 7 元组 `{rd done busy rstn mdio_i ssl pbad}`（位 = `15:0 / 16 / 17 / 18 / 19 / 20 / 21`）；
- 新：每条事务落一行原始记录（**收尾归档**）：
  `TX phyad=%02d regad=%02d rd=%04X done=%d busy=%d rstn=%d mdio=%d ssl=%d pbad=%d`；
- 新：臂 A/B(/C)（下）；收尾 `disconnect_hw_server`。
- stdout 全程 tee 到文件（判据面 = 原始 stdout，不是摘要）。

**臂 J-A · 全扫（复核，含既有负对照）**：32 地址 × {reg2, reg3}。
期望：应答地址集合**恰 = {0, 1}**，两者均 `{PHYID1=0x001C, PHYID2=0xC915}`（= 0x001CC915）；其余 **30 个地址两寄存器均 0xFFFF**；
每事务 `done=1 / ssl=0 / pbad=0`。负对照（历史做过，本次要求**在同一份 stdout 里复现**）：2–31 的 `0xFFFF`（总线拉高 ⇒"没答"与"答 0"可分）。

**臂 J-B · 交错新鲜性（"同 ID ≠ 幻觉"主臂，约 1 min）**：顺序 `(1,r2)→(7,r2)→(0,r2)→(7,r2)→(0,r2)→(1,r2)→(31,r2)`。
期望：`001C / FFFF / 001C / FFFF / 001C / 001C / FFFF`。
判据形态：若 `rd_data` 是"回显/陈旧值"，静默地址会读回 `001C` —— 实测必须 `FFFF`；且除末对 `(0,r2)→(1,r2)` 相邻外，
每个 `001C` 都与前一个 `001C` 隔着至少一个 `FFFF`（即"静默读夹在中间"）⇒ 每次 `001C` 都是新事务。
**结构排除（不依赖板，写进报告）**：`mdio_master.v:111`（接受 start 即 `rd_sh<=0`）· `:118`（`rd_data<=0`）·
`:127-128`（只有真跑完帧才把 `mdio_i` 采样移入 `rd_sh`）⇒ 一次被接受的 start 之后，`rd_data` 只能来自**本事务**采到的线上位；
要到 `0x001C` 必须 **PHY 真的驱动了 TA=0 + 16 位数据**（拉高线读出来的是 `FFFF`）。
**手册引用（预期解释）**：§0 第 4 行的 datasheet 原文 ⇒ "0 与 1 同 ID" = 广播地址的**预期行为**。

**臂 J-C · 写穿越（可选、低优先；仅在需要"同一颗芯片"的物理证据时做，约 3 min）**：
设计：`v0=read(1,r4)` → `write(1,r4,M1)` → `v1=read(1,r4)` → `write(1,r4,M2)` → `v2=read(1,r4)` → `read(0,r4)` → `read(8,r4)` → `write(1,r4,v0)` 还原。
先决条件（**先自证再下结论**）：`v1 != v2`（写-读回可区分）；否则本臂**降级为"不可判"如实记录**（备选寄存器 = reg 9 / PAGSEL 0x1F）。
判据形态：`read(0,r4) == v2` 且 `read(8,r4) == 0xFFFF` 且还原后 `read(1,r4) == v0`。
⚠️ 风险与恢复：reg 4 = ANAR；手册（同 PDF 提取文本 §7.12 区）逐字"**The setting of Register 4 has no effect unless NWay is restarted or the link goes down**"
⇒ 链路在跑时普通写**不生效于链路**；若 1G 链路恰好在下/重协商中，写会改广播能力 —— 恢复 = 还原原值 +（必要时）`force_rst` 复位 PHY。
⛔ 本臂**不**能区分"广播应答"与"地址字段位级错误"（见下"不可判边界"），价值 = 证明**读值随外部写入变化**（排除"定值表/回显"）。

**不可判边界（如实登记，不许写大）**：单 PHY + 无 MDIO 示波器 ⇒ "PHY 应答广播地址 0" 与 "帧内 PHYAD 字段被改成 1"
两种世界在**本板上行为完全等价**（任何读/写序列结果相同）⇒ **不许写"已排除地址字段伪影"**。
该微伪影只能靠**结构性论证**排除：5 位 PHYAD 与全部字段走**同一条移位链**（无按地址分叉的逻辑）、TB 对地址解码有专测、
2–31 静默 = 端到端地址选择性的直接见证。这条并进 §4.2 报告。

**臂 J-D · 新位读取（约 1 min）**：每条记录的 `ssl`/`pbad` 两列 = 0（生产臂）。
⛔ **陷阱（必须写进报告）**：`param_bad` 是**常量 0**、`stat_start_lost` 在**宿主不可触发**（见 §4.3）⇒
"恒 0"与"未接线"读数上**不可区分** ⇒ 本臂**不能**声称"两个新信号已在板上验过"。

### 4.3 步骤 2b：A+ 变体臂（可选；**推荐** —— 两个新位的板上正控只此一路；约 +10 min）

为什么必须靠变体：`stat_start_lost` 只在 busy 期来 start 才置位，而 **busy 窗 32 µs ≪ JTAG commit 间隔（~数十 ms）**
（`mdio_vio_top.v:88-91` 头注释即此数）⇒ 生产臂**宿主无法制造**该条件；`param_bad` 是 elaboration 常量 ⇒ 生产臂恒 0。
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

### 4.4 步骤 3：收尾 —— 重烧 0x24 + PCIe 恢复 + 恢复受控停流（约 5 min，**不可省**）

```
bash notes/p9_uram_ab_20261014/_tools/burn_arm.sh 0x24 <seq>     # 原脚本原地跑（审计过的单一路径）
```
该脚本已含：**烧前 sha256 门**（须 = `e3b07957…f1db`）→ 1MHz 烧录五判据 → **PCIe 恢复：设备级 `remove`+`rescan`；`LnkSta` 非 `x4` 则自动升根端口级**（`0000:00:1c.0`）→ 身份门
（**`0x04==0x00000024`** + `0x00=0x50360001` / `0x14=0xdeadbeef` / `0x14C=0xffffffff` + `dmesg identify_bars: 2 BARs` + `LnkSta Width x4`）。
⚠️ 其设计假设的 [D-6] 机制：跑完把 `burn/BURN_0x24_S<seq>_*.txt` 拷进阶段二轮目录。
**最后一步（脚本没有、必须手动补）**：恢复**受控停流**（与测试前现态一致）：
`reg_rw /dev/xdma0_user 0x08 w 0x2` → 核 `CARRIER=0`（`cat /sys/class/net/enp1s0f1np1/carrier`）。
（备选 = 留在 `0x08=0`（发流态）；但那会改变工程现态，**默认按恢复受控停流走**，要改口径须先经 TL。）

### 4.5 时间预算汇总

| 步 | 内容 | 估计 |
|---|---|---|
| 0 | 归档（§3.1）+ 烧前现态 | 2 min |
| 1 | 生产构建（§3.2，小设计） | 3-6 min |
| 2 | 烧 mdio 位流（§4.1） | 3-5 min |
| 3 | VIO：J-A + J-B + J-D（§4.2） | 5-15 min |
| 3b | （可选推荐）变体构建+烧+VIO（§4.3） | +10-15 min |
| 3c | （可选）J-C 写穿越 | +3 min |
| 4 | 收尾重烧 0x24 + 恢复（§4.4） | 5-8 min |
| — | **合计** | **约 18-40 min**（不含可选项 ≈18 min；含全部可选项 ≈40 min） |

---

## §5 纪律核对（全程符合性自查）

**5.1 绝不写 QSPI（硬纪律）—— 本计划全程符合**：
- 构建侧：`build_mdio.tcl` 只产 `.bit`（无 `.bin`、无 `write_cfgmem`）—— 现读确认。
- 烧录侧：`program_tcpreg_ku5p.tcl` 只做 `set_property PROGRAM.FILE` + `program_hw_devices`（JTAG 易失）—— 现读确认。
- ⚠️ XDC 里的 `BITSTREAM.CONFIG.SPI_BUSWIDTH / CONFIGRATE` 与 `CONFIG_MODE SPIx4`（`ku5p_mdio.xdc` 尾 3 行）
  **只写进位流头**（"stays QSPI-compatible if that is ever wanted"），**不构成对 Flash 的任何操作** ⇒ 保留原样，别删也别扩。
- 全计划唯一"写 Flash"的路径 = 不存在的路径；收尾恢复 0x24 也走同一 JTAG 易失路径。

**5.2 烧录工具链推荐（现读判断）**：
- **推荐 = 主树 tcpreg launcher**（`run_program_tcpreg.bat` + `program_tcpreg_ku5p.tcl`）：唯一被审计过、带 **1MHz 降频** + **DONE 检查点** 的路径；mdio 位流与 0x24 恢复都走它。
- **不推荐**用 `probe_phy.tcl` 的**自带烧录段**：它**无 1MHz、无 DONE 检查**（F9 现读）。⇒ v2 驱动脚本**去掉烧录段**（§4.2），只连 JTAG 读 VIO。
- `list_probes.tcl`（本目录）是历史排障件，含**绝对路径**的 PROBES.FILE —— 不用于本轮（会被新构建路径绕过）。

**5.3 版本控制与归档**：
- `_proj_mdio` **不在任何 git 仓库内**（F13）⇒ §3.1 的改前归档 + 旧产物归档是**唯一回退来源**，缺一不可。
- 阶段二轮**不做 git 写**（提交由 TL 统一）；阶段二轮的 note/日志落在其自建目录，笔记树入库与否按仓库现规（log 已放行入库）。

---

## §6 风险与回退

| # | 风险 | 处置 |
|---|---|---|
| R1 | 烧 mdio 后 **PCIe 端点消失**（预期副作用） | 不当故障处理；留到 §4.4 统一恢复。⚠️ 期间 `reg_rw`/`identify_bars` 不可用，**判活只用 JTAG/VIO** |
| R2 | 烧 mdio 失败（无 `HIGH` / `TCPREG-ABORT`） | 五判据会先拦下（无 HIGH 即停）；重试一次；仍失败 ⇒ 查 hw_server / JTAG 线 / 对端可达；**任何情况下都不认为"板坏了"**（板子没被写过 Flash） |
| R3 | VIO 找不到 / 零探针 | 顺序查：① `.ltx` 是否与 bit 同目录同名（v2 脚本按 `rootname(bit).ltx`）；② `refresh_hw_device` 是否在 program 之后；③ 探针名是否 = 网名 `vio_probe_in`（五坑之②）；④ 五坑之③：`commit/refresh` 传 **hw_vio CORE** 不传探针 |
| R4 | 板上读到的位序不对（新位没在 [21:20]） | 先用 `get_property WIDTH` 核 22；再用**可翻转的旧位**（busy/eth_rstn/mdio_i）验证位置语义；最后才怀疑 E5 的拼接顺序（对照 §2.1-E5 的替换串） |
| R5 | A+ 臂 `ssl` 触发反复错过（commit 延迟 >83.9 ms） | 如实记"未触发"（≠ 缺陷）；最多 5 次重试；`pbad=1`（P1）不依赖触发时序，仍成立 |
| R6 | J-C 写后 reg4 读回不区分（或链路受影响） | 本臂是"可选/低优先"：读回不区分 ⇒ 记"不可判"（勿硬凑）；链路受影响 ⇒ 还原原值 + `force_rst` 复位 PHY（`vio_force_rst` 现成） |
| R7 | 收尾 0x24 恢复失败（`LnkSta` 非 x4 / 无 `/dev/xdma0_*`） | 依 `burn_arm.sh` 的升级分支：设备级 remove+rescan 不够 ⇒ **根端口级**（`0000:00:1c.0`）remove+rescan；仍不行 ⇒ 对端机重启（POST 时板已在跑 0x24 ⇒ 场景 A/B）。⚠️ 全程**不许**动板载 QSPI |
| R8 | 板在 mdio 态"不配合"（JTAG 掉线等） | 最后手段 = 板断电重启（恢复 QSPI 厂商设计 + JTAG 可用；⚠️ 厂商设计在场时按"场景 C"恢复 PCIe：连根端口一起 remove+rescan）⇒ 再烧 0x24 |
| R9 | 变体臂位流 sha == 生产臂 sha | 构建没生效 ⇒ 停手，检查 E8 两处改动（项目目录 + generic） |
| R10 | 阶段二轮写完发现 §1 行号漂移 | 一切引用**行号前先现读**（本件行号 = 2026-10-14 现读值；台账纪律） |

---

## §7 本件边界与"不许声称"

- 本件 = **设计件（计划）**；阶段二实施由 TL 派单；本件**零上板/零构建/零改文件**（唯一写 = 本目录）。
- ⛔ **不许**把本件当作任何功能"已验证"的声明；下列三条口径必须沿用到阶段二报告：
  ① **两个新信号（param_bad / stat_start_lost）的行为验证在 xsim（已完成），板级（生产臂）只能给"出现且恒 0"** —— 恒 0 与未接线不可区分；
  ② **"地址 0/1 同 ID"= 手册预期（广播地址）**；板上实验给的是"确认 + 新鲜性",**不是**"排除了地址字段伪影"（单 PHY 行为等价，§4.2 末）；
  ③ **生产位流未做过功能仿真**（`mdio_vio_top` 只有 elaboration 级见证；行为级 = mdio_master 单元 TB）。
- ⛔ 引用旧读数一律带位流 sha 与"哪一代"；旧 mdio 位流（`46417aff…`）与新构建位流**只有 sha256/字节数不同可判**（同板同器件的 .bit 尺寸可能相同，见仓库既有教训）。

---

### 附A · 已读/现核的工具与原件索引（可逐条复跑）

| 用途 | 路径 | 现读关键值 |
|---|---|---|
| 缺陷报告（母件） | `notes/p7b_tool_debt_20261010/REPORT.md` §2 + §4-3 | 改动清单/判据/未做到三格 |
| RTL diff | `…/p7b_tool_debt_20261010/mdio_master.diff` | 完整逐行 |
| pristine 保全 | `…/p7b_tool_debt_20261010/pristine/{mdio_master.v.orig,tb_mdio_master.v.orig,SHA256_PRISTINE.txt}` | 旧 sha `6a0b4c58…` / `3c23ea04…` |
| 2×2 矩阵原件 | `…/p7b_tool_debt_20261010/task2/{_rm1..4_*.stdout.txt, rm*/}` | FAIL(4 errors)/PASS 逐字 |
| elaboration 门 | `…/p7b_tool_debt_20261010/task2/elab_wrapper/{run.bat,vio_0.v,...}` | `XELAB_RC=0` + 10-3645 在案 |
| 器件手册 | `资料\PDF\RTL8211E-VB-CG.pdf`（§7.7 Table 13 / §7.10.4 / §7.13） | "PHY address 0 is a broadcast" |
| 烧录 launcher | `notes/p7b_biz_tcpreg/{run_program_tcpreg.bat,program_tcpreg_ku5p.tcl}` | 1MHz + 五判据模板 |
| 烧录+恢复 launcher | `notes/p9_uram_ab_20261014/_tools/burn_arm.sh` | sha 门 + 恢复 + 身份门 |
| 0x24 位流真值 | `notes/p9_build_0x24/wrapper_p4.bit`（另两处副本同 sha） | `e3b07957…f1db` |
| 板现态 | `notes/p9_uram_ab_20261014/runs/FINAL_STATE_20261014_004453.txt` | `0x04=0x24` / `0x08=0x2` |
| 清单登记 | `notes/P7B_OPEN_ITEMS.md` §0 第 18 行 | 三格登记（本轮核对一致） |

**本件（设计轮）写操作 = 1 个新目录**：`notes/p9_fix_mdio_design_20261014/`。
零改文件 / 零 Vivado / 零 xsim / 零上板 / 零 git 写 / 零碰板。⛔ **本件不含 PASS/FAIL 裁定**（裁定权在判据所有者）；
一切"期望值"均为**物理预期/判据形态**，不是验收裁定。
