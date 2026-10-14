# gate_elab_22 —— 22 位 VIO 探针的 elaboration 门（**已就位，尚未运行**）

- 落盘 2026-10-15 · 轮 = `p9_fix_mdio_impl_20261015`（实施轮）· **本轮未跑任何 Xilinx 工具**（派单硬约束 ⇒ 本门一次都没跑过）。
- 骨架来源 = `udp_hls_10g/_proj_10g/notes/p7b_tool_debt_20261010/task2/elab_wrapper/`。
  只取 5 个输入 `.v` 与 run.bat 的两条命令行；**未**连 `xsim.dir/`、`*.log` 一起拷（避陈旧产物与 `xsim.dir` 文件锁 —— 本工程坑 7）。
- 设计依据 = `notes/p9_fix_mdio_design_20261014/DESIGN_v2.md` §3.4。
- **门证什么**：只证 **elaboration**（连线完整性 + 位宽一致）。**不证**功能仿真、不证综合/实现、不证探针位宽与位图语义。
  （行为级只有 `tb_mdio_master.v`，而它**不例化 top** —— 见 DESIGN_v2 §3.5 的覆盖边界。）

## 输入（冻结 = 同目录 `SHA256SUMS.txt`）

| 文件 | 内容 | 与生产的关系 |
|---|---|---|
| `mdio_master.v` | 现役（P7B 工具债轮修复版） | 与 `_proj_mdio/rtl/mdio_master.v` 逐字节同 |
| `mdio_vio_top.v` | **编辑后**（E1–E5 已落） | 与 `_proj_mdio/rtl/mdio_vio_top.v` 逐字节同 |
| `build_mdio.tcl` | **编辑后**（E6 已落） | 与 `_proj_mdio/build_mdio.tcl` 逐字节同（只作 F5 文本判据的样件）|
| `vio_0.v` | stub，**第 60 行已 20→22**（`input [21 : 0] probe_in0;`） | 生产构建由 `create_ip` 重新生成同宽度 stub；门里这份是**门本地 mock** |
| `vio_0_sim_netlist.v` | 冻结 IP 网表（**20 位**，原样未改） | **不进生产**；留在编译表里只为产生"覆盖见证"（见下） |
| `dbg_hub_sim_netlist.v` | 原样 | 同上（在本门中不被例化） |

## ⚠️ 与 DESIGN_v2 §3.4 的**一处实质偏离**（如实登记，别迁就）

v2 §3.4 第 3 步说：把 `vio_0.v` stub 第 60 行改成 `[21:0]`，否则 xelab 会报 10-3091。
**现读证据表明：只改 stub 不生效。** 骨架上一次的实跑日志（`task2/elab_wrapper/xvlog.log:9`，同一份也在
`task2/_elab_wrapper.stdout.txt` 所属那批里）逐字：

    WARNING: [VRFC 10-3609] overwriting previous definition of module 'vio_0'
    [...\elab_wrapper\vio_0_sim_netlist.v:18]

⇒ xvlog 的**后一次定义覆盖前一次**；`vio_0_sim_netlist.v`（原编译表里排在 `vio_0.v` **之后**）才是被
elaboration 采用的那份，而它是**冻结的 20 位** IP 网表（`vio_0_sim_netlist.v:27` / `:35` = `input [19:0]probe_in0;`）。
旁证（同一份实跑日志的 xelab 侧）："Compiling module" 表里出现 `unisims_ver.LUT6` / `FDRE_default` / `GND` ——
这些原语只在网表内部出现，两个 RTL 里一个都没有 ⇒ 被 elaboration 的**确实是网表版**，不是 stub。
⇒ **只改 stub 时，22 位设计照旧会报 `VRFC 10-3091`（22 vs 20）** —— v2 预期的"改了就没有"不成立。

**本门的处置（不修网表、不动文件集，只改编译顺序）**：把已 patch 成 22 位的 `vio_0.v` 排到编译表**最后**
⇒ stub 成为生效定义。期望 stdout 出现**同一条 10-3609，但锚点变成 `vio_0.v:49`**（stub 的 module 声明行）
—— 这条警告本身就是"stub 已生效"的见证。**若锚点仍是 `vio_0_sim_netlist.v`，说明顺序被改回去了 ⇒ 停手看 F3。**

（另一条同样成立的路 = 把 `vio_0_sim_netlist.v` 从编译表里去掉。本门选"保文件集、换顺序"，
好处是留下覆盖见证。⚠️ 两条路都**没实跑过** —— 见"状态与残余"。）

## 判据（= `check_elab.bat`，硬门：打印 + 退出码两条腿都有）

| # | 判据 | 期望 |
|---|---|---|
| F1 | `elab_rc.txt` | `0` |
| F2 | `xelab.log` 里的 `VRFC 10-3645`（端口未连） | **0 命中** |
| F3 | `xelab.log` 里的 `VRFC 10-3091`（位宽不符） | **0 命中** |
| F4 | RTL 文本：`wire [21:0] vio_probe_in;` 在 · 旧 `wire [19:0] vio_probe_in;` 不在 · 拼接序 = `{stat_start_lost, param_bad, mdio_i, eth_rstn, busy, done_sticky, rd_data}` | 全中 |
| F5 | `vio_0.v` 有 `input [21 : 0] probe_in0;` 且 `build_mdio.tcl` 有 `CONFIG.C_PROBE_IN0_WIDTH {22}` | 全中 |

F4/F5 是**文本级**判据，补 elab **看不见**的两件事：
① **RTL 与构建脚本的位宽同步（E2↔E6）** —— 只改一处**任何仿真都发现不了**（elab 用的是门里的 stub，
它不知道 tcl 里的 IP 参数）；② **新两位的位序决定（E5）** —— 位序写反在纯 elab 里完全静默，
只在板上读数的位置上出错。

## 负对照（`negctrl/`，故意漏一处接线 ⇒ 门必须红）

- 变异件 = `negctrl/mdio_vio_top.v`（= 编辑后文件**只删一行**：`.param_bad   (param_bad),`）。
- 复现：`copy /Y negctrl\mdio_vio_top.v mdio_vio_top.v` → 跑 `run.bat`。
- **怎么红**：`xelab.log` 出现
  `WARNING: [VRFC 10-3645] port 'param_bad' remains unconnected for this instance [ ...\mdio_vio_top.v:127]`
  （实例起始行 = `:127`；与工具债轮抓到的是**同一签名**）⇒ F2 命中 ⇒ `check_elab.bat` 打
  `GATE_FAIL: F2_PORT_UNCONNECTED_10-3645` 且 `exit /b 1`。
  ⚠️ 红在**警告行**上，`XELAB_RC` 仍会是 0 —— 这正是"只打印 XELAB_RC"的旧骨架当不了门的原因。
- 恢复：从本目录 `SHA256SUMS.txt` 自核后回拷 `mdio_vio_top.v`。
- **覆盖边界（如实登记）**：本门测不到"端口连到了一根**没驱动的 wire**"（那种形态 elab 无警告、
  仿真里恒 0）—— 该形态分别由 DESIGN_v2 §2 的"两种半改的死法"与 §4.2 的 `ssl/pbad` 板上读数面覆盖。
  门也不覆盖 VIO 网段（`vio_phyad` 那条连线）—— 见 DESIGN_v2 §4.2 末与 §7 登记项 R-a。

## 怎么跑（下一棒；本轮不跑）

    cd /d <本目录>
    run.bat      :: xvlog -> xelab -> check_elab.bat；退出码 = 门的裁定

跑完把 `xvlog.stdout.txt` / `xelab.log` / `elab_rc.txt` 与整段 stdout 归档进轮目录。
零上板、零 QSPI、零构建；本门只写本目录（xsim 工作目录）。
⚠️ 纪律：**别与正在跑的大仿真/构建共机**（"自己造成的资源争抢会产生假红"），也别在构建期间动被构建的工程。

## 状态与已知残余

- **本门尚未运行**（本轮禁 Xilinx 工具）。因此"编译顺序 ⇒ 生效定义"这一结论 = **现读证据 + 推理**，
  第一次实跑必须**先核** stdout 里 10-3609 的锚点是否为 `vio_0.v:49`；不是 ⇒ 停手，别信那次通过。
- **未实施**：E7/E8（A+ 变体臂的 `DIV=65537` 构建；DESIGN_v2 §2.2）—— 不在本轮派单范围。
- 门的输出只到 `-s top_elab` 快照；**不跑 `xsim`**（本轮禁 Xilinx 工具；下一棒若按 §3.5 复跑 TB 请用独立目录）。
