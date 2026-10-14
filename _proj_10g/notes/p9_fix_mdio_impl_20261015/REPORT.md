# p9_fix_mdio_impl_20261015 —— 实施报告：mdio 改前归档 + 6 编辑点 + 门脚本就位

> **agent 原件由平台拒写 .md ⇒ 全文回传、TL 代落盘**（本件正文 = agent 原文；文末「TL 附加」= TL 独立抽核记录）。
> 轮 = 实施轮（agent `p9_impl_mdio_edit_20261015`），依据 = `_proj_10g/notes/p9_fix_mdio_design_20261014/DESIGN_v2.md`（其 §1/§2/§3.1 锚点与哈希面，本轮独立现读逐条命中，见 §5）。
> 落点命名：v2 §3.1 模板 `notes/p9_fix_mdio_<阶段二轮名>/` ⇒ **`D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_fix_mdio_impl_20261015\`**（与设计轮同前缀成对）。
> ⛔ 本件不下 PASS/FAIL 裁定；一切"期望值"= 判据形态。
> **状态一行话**：6 编辑点已落（旧 20 位逐位不动）· 改前归档两组 + 三份 `SHA256SUMS` 全部自核通过 · elab 门 + 硬判据检查器 + 负对照已就位（**未跑**）· ⚠️ **一处实质偏离**（v2 §3.4 的"只改 stub"不生效 —— 见 §4-A，门已按证据修正）。

---

## §1 归档（v2 §3.1；改前 = 唯一回退来源，`_proj_mdio` 不在任何 git 仓内）

### 1.1 `archive_20260928/` —— 旧构建产物（15 件，`sha256sum -c` **15/15 OK**）

| 件 | 字节 | sha256 / 读数 |
|---|---|---|
| `impl_1/mdio_vio_top.bit` | 15,431,263 | `46417affc544e6a51e2eff8cafa473afaad5384cd1b17e033d1a31800d692ad2` —— **与 v2 §3.1 预期 `46417aff…92ad2` 逐字相同** |
| `impl_1/mdio_vio_top.ltx` | 14,414 | （全表在 SHA256SUMS.txt） |
| `impl_1/debug_nets.ltx` | 14,414 | 同上 |
| `impl_1/*.rpt` × 11 | — | bus_skew_routed · clock_utilization_routed · control_sets_placed · drc_opted · drc_routed · io_placed · methodology_drc_routed · power_routed · route_status · timing_summary_routed · utilization_placed（**与 v2 §3.1 列的 11 件逐项一致**） |
| `timing_summary.rpt` | 79,930 | 读回 **WNS 7.091 / WHS 0.020 / WPWS 4.427，三列失败端点全 0** —— 与 v2 旧真值逐字相同 |
| `SHA256SUMS.txt` | — | 本组自核清单 |

**未归档（如实登记）**：`pj_mdio/` 的 dcp/vdi/runme.log 等非 rpt 产物（= v2 §3.1 的**可选**全量项，实测 24 MB）；`_proj_mdio/_sim/`（构建不摧毁它，非回退必需）。
**格式微差**：v2 字面命令 `sha256sum archive_20260928/* …` 会把目录 `impl_1` 当参数报错；本件改为**目录内显式文件表**生成（路径相对本组自洽）。⚠️ `sha256sum` 输出带 `*`（`hash *file`），按 `grep " file"` 核对会**结构性漏检** —— 本件核对时亲身踩到（见 §5 末）。

### 1.2 `pre_edit/` —— 改前源文件（7 件，`sha256sum -c` **7/7 OK**）

v2 核心三条 = `mdio_vio_top.v`/`build_mdio.tcl`/`probe_phy.tcl`；按 v2 授权（"mdio_master.v/tb 已有 pristine 保全，**可连带拷求全**"）扩到 `_proj_mdio` **全部小文件表面**（超集、无删除）：

| 件 | 字节 | sha256（首8+末4） |
|---|---|---|
| `mdio_vio_top.v` | 4,829 | `e9c0c74c…fab3`（**与 v2 §2.1 改前 sha 逐字相同**） |
| `build_mdio.tcl` | 2,456 | `72f7bb8b…a4bf`（同上） |
| `probe_phy.tcl` | 6,504 | `a16e50eb…5ec4`（与 v2 §3.1 逐字相同） |
| `mdio_master.v` | 7,274 | `89d5c89e…35db`（= 工具债轮修复版，与 REPORT §2.2 一致） |
| `tb_mdio_master.v` | 21,858 | `8c8dc2c8…0d7d`（同上） |
| `list_probes.tcl` / `ku5p_mdio.xdc` | 1,253 / 1,951 | 见 SHA256SUMS.txt |

---

## §2 6 编辑点（逐点 diff，实录 `git diff --no-index`；行号 = **编辑后**现读）

**E1（注释位图，插入型）→ 现 `:28-29`**（锚点原 `:27`）
```diff
 //   probe_in0  [19]    mdio_i   (live line level)
+//   probe_in0  [20]    param_bad        (DIV out of range -> clamped; static)
+//   probe_in0  [21]    stat_start_lost  (start arrived while busy; sticky)
```

**E2（声明，替换型）→ 现 `:88`**（锚点原 `:86`）
```diff
-    wire [19:0] vio_probe_in;
+    wire [21:0] vio_probe_in;
```

**E3（新 wire，插入型）→ 现 `:114-115`**（锚点原 `:111` 之后）
```diff
     wire        busy;
+    wire        param_bad;          // from mdio_master (2026-10-10 additions)
+    wire        stat_start_lost;
```

**E4（例化接线，替换型）→ 现 `:144-147`**（锚点原 `:140-141`；实例起始行现 `:127`）
```diff
-        .mdio_i      (mdio_i)
+        .mdio_i      (mdio_i),
+        .param_bad   (param_bad),          // 2026-10-10 additions (were left unconnected)
+        .stat_start_lost (stat_start_lost)
     );
```

**E5（拼接，替换型）→ 现 `:149`**（锚点原 `:143`）
```diff
-    assign vio_probe_in = {mdio_i, eth_rstn, busy, done_sticky, rd_data};
+    assign vio_probe_in = {stat_start_lost, param_bad, mdio_i, eth_rstn, busy, done_sticky, rd_data};
```

**E6（`build_mdio.tcl:30`，替换型；行号不变，续行反斜杠已保留 ✓）**
```diff
-    CONFIG.C_PROBE_IN0_WIDTH {20} \
+    CONFIG.C_PROBE_IN0_WIDTH {22} \
```

**非注释行核对**：语义行变化 = E2/E3/E4/E5 四条（E1 纯注释、E6 在 tcl），全部为"扩展式替换"（被删 3 行的内容均以原样字符出现在替换行内）⇒ **旧 20 位逐位不动**；位序现读验证 = `[21] stat_start_lost · [20] param_bad · [19:0] 原样` ✓。文件量：`mdio_vio_top.v` 4,829→**5,259 B**（+430），155→**161 行**（+6）；两文件仍**纯 LF**（CR=0）。**新 sha256**：`rtl/mdio_vio_top.v` = `79c360f83aff1789eb1144ef1045a3a5fd1cebed27d2f3cb76484d056b6956e6` · `build_mdio.tcl` = `b7ff3c45ea89399b789308e0ac31340e3c6de1e490813855a446ad623846aecd`。
**所有权边界**：`find _proj_mdio -newermt 2026-10-14` = **仅这 2 个文件**；其余 5 个归档源文件与 `dfx_runtime.txt`/`pj_mdio/*` 经 `cmp` 逐字节 **SAME**。

---

## §3 门脚本就位（`gate_elab_22/`，**未运行**）

| 件 | 内容 |
|---|---|
| `run.bat` | 骨架 = `p7b_tool_debt_20261010/task2/elab_wrapper/run.bat` 的两条命令行；**一处刻意偏离**：已 patch 22 位的 `vio_0.v` 排到编译表**最后**（理由见 §4-A）；末尾接硬判据并把其退出码传播。ASCII+CRLF（逐行核过）。 |
| `check_elab.bat` | **硬门**：F1 `elab_rc.txt==0` · F2 无 `VRFC 10-3645` · F3 无 `VRFC 10-3091` · F4 RTL 文本（`[21:0]` 在/旧 `[19:0]` 不在/拼接序逐字）· F5 `vio_0.v`=22 位 且 `build_mdio.tcl {22}`。**打印它所判的每一行**（`findstr /N`）+ `GATE_PASS`/`GATE_FAIL:<原因>` + 退出码 0/1。 |
| `vio_0.v` | stub，第 60 行 20→22（现 `input [21 : 0] probe_in0;`）—— 门本地 mock |
| `GATE_NOTES.md` | 覆盖范围（只证 elaboration）· §4-A 偏离的完整论证 · 判据表 · 负对照 · 运行法 · 状态残余 |
| `SHA256SUMS.txt` | 11 件输入/脚本自核（11/11 OK） |

**负对照（`negctrl/`）**：`negctrl/mdio_vio_top.v` = 编辑后文件**只删一行**（`.param_bad   (param_bad),`，diff 实测恰 1 行）；复现 = `copy /Y negctrl\mdio_vio_top.v mdio_vio_top.v` 后跑 `run.bat`。
**怎么红**：`xelab.log` 出现 `WARNING: [VRFC 10-3645] port 'param_bad' remains unconnected … [mdio_vio_top.v:127]`（与工具债轮抓到的**同一签名**）⇒ F2 命中 ⇒ `GATE_FAIL: F2_PORT_UNCONNECTED_10-3645` + `exit /b 1`。⚠️ 红在**警告行**上，`XELAB_RC` 仍为 0 —— 这正是"只打印 XELAB_RC"的旧骨架当不了门的原因。**覆盖边界（如实登记）**：门测不到"端口连到没驱动的 wire"（elab 无警告）；不覆盖 VIO 网段（v2 §4.2 R-a）。

---

## §4 异常与偏离

### A. ⚠️ v2 §3.4 的"只改 `vio_0.v` stub"**不生效**（证据 + 门已修正）

- v2 §3.4 第 3 步说：改 stub 第 60 行为 `[21:0]`，"否则 xelab 会报 `VRFC 10-3091`"。
- **现读证据**（骨架实跑日志 `task2/elab_wrapper/xvlog.log:9`，逐字）：`WARNING: [VRFC 10-3609] overwriting previous definition of module 'vio_0' […\vio_0_sim_netlist.v:18]` ⇒ xvlog **后定义覆盖前定义**；原编译表里 `vio_0_sim_netlist.v`（**冻结 20 位**：`:27`/`:35` = `input [19:0]probe_in0;`）排在 stub **之后** ⇒ 被 elaboration 采用的那份**不是 stub**。
- **旁证**（同日志 xelab 侧）：`Compiling module` 表里出现 `unisims_ver.LUT6`/`FDRE_default`/`GND` —— 这些原语只在网表内部出现，两个 RTL 里一个都没有 ⇒ 被 elaboration 的确实是网表版。
- ⇒ **只按 v2 改 stub，22 位设计照旧会报 10-3091**（v2 预期的"改了就没有"不成立）。**处置**：门里把已 patch 的 stub 排到编译表**最后**（不改网表、不动文件集）；期望覆盖见证变为 `10-3609 … [vio_0.v:49]`。⚠️ 此结论**未实跑验证**（本轮禁工具）⇒ **下一棒第一次跑门必须先核该锚点**，不是 ⇒ 停手（已写入 GATE_NOTES）。
- 口径：本条**不动摇** v2 其余部分、**不追溯**工具债轮既有结论（那一轮全程 20 位，10-3609 与 10-3645 捕获均有效）。

### B. 归档面比 v2 的 `pre_edit/` 三条更宽（**超集**，v2 已授权）—— 理由：归档=唯一回退来源，宁超勿缺。
### C. 门目录**未整目录拷贝**（v2 §3.4 说"复制整个目录"）—— 只取 5 个输入 .v；**不带**骨架的 `xsim.dir/` 与旧日志（避陈旧产物污染与文件锁假红，本工程坑 7）。
### D. **E7/E8（A+ 变体臂）未做** —— 派单范围 = 6 编辑点（E1–E6）；E7/E8 是 v2 §2.2 可选件 ⇒ **变体臂尚不可做**（已登记 GATE_NOTES 残余）。

---

## §5 复核对账（v2 现读值 vs 本轮现读）

F1 `:86 [19:0]` ✓ · F2 `:143` ✓ · F3 `:123-141`（末两行 `:140-141`）✓ · F4 `:109-111` ✓ · F5 `mdio_master.v:54-55` 端口名逐字 ✓ · F6 `:75` + `:159-163`（条件行 160-162 逐字）✓ · F7 `tcl:30 {20}` ✓ · **F9 1MHz 语句 = `program_tcpreg_ku5p.tcl:14`**（v2 的订正正确，v1 的 `:16` 与复核的 `:15` 均偏）✓ · F10 旧 bit/ltx 字节数与 mtime ✓ · §3.1 旧真值（bit sha、`+7.091/+0.020/+4.427`）✓ · 三件改前 sha ✓ · F13 无 git 兜底 ✓ ⇒ **唯一实质偏差在 §3.4**。
（本轮自身踩到的坑已登记：`sha256sum` 输出 `hash *file`，`grep " file"` 类核对会结构性漏检 —— 我据此一度误报 5 文件 "DIFFERS"，`cmp` 复核对全部 SAME。）

---

## §6 不许声称 / 下一步

⛔ 不许声称：① "新两位已验/已接线"（只经文本级核对；门未跑、未构建、未上板；生产臂上它们仍是"出现且恒 0"，v2 §7-R-b）；② "门已通过"（未运行；10-3609 锚点必须先核）；③ "已构建/可烧"（板上现态仍 = 0x24 + 受控停流；旧 mdio 位流只是历史件，回退源 = `archive_20260928/impl_1/`）；④ "E7/E8 已做"（没做）。
**下一步（下一棒）**：跑门（先核覆盖见证锚点）→ 构建（`build_mdio.tcl`；#54：`create_project -force` 会清 `pj_mdio/`，归档已在盘）→ 板测（v2 §4）→ 收尾重烧 0x24 + 三条硬判据 + 恢复受控停流。

---

**两条环境备注（不是本轮的改动）**：① `git status` 显示 `board/wrapper_p4.v`(+17/−2) 与 `rtl/vlan_strip.v`(+61/−11) 处于 modified（mtime 00:42，内容与 mdio 无关 = 另一会话在飞的工作 = **F-3 实施轮**）；本轮的 git 可见增量**只有**新目录 `_proj_10g/notes/p9_fix_mdio_impl_20261015/`（未提交，按 v2 §5.3 零 git 写）。② 落盘清单：36 件 / 18 MB（含 15 MB 位流归档），结构 = `archive_20260928/`(15+SUMS) · `pre_edit/`(7+SUMS) · `gate_elab_22/`(6 输入 + run.bat/check_elab.bat/GATE_NOTES.md + SUMS + negctrl/2)。

----------------------------------------------------------------

## TL 附加（2026-10-15 01:0x；独立抽核记录）

- **在盘核**：轮目录 36 件、三子目录齐全；`archive_20260928/SHA256SUMS.txt` 与 `pre_edit/SHA256SUMS.txt` 经**自写解析器**（处理 `hash *file` 格式）复核 = **15/15 OK + 7/7 OK**（agent 报的同一结论，独立复现）。
- **编辑落点核**（`_proj_mdio` 现读）：`rtl/mdio_vio_top.v` = `[21:0]`（`:88`）· 两 wire（`:114-115`）· 例化接线（`:145-146`）· 拼接序 `{stat_start_lost, param_bad, mdio_i, …}`（`:149`）· 注释位图（`:28-29`）；`build_mdio.tcl:30 = {22}`；**两文件现读 sha 与报告逐字吻合**（`79c360f8…` / `b7ff3c45…`）。
- **所有权核**：`find _proj_mdio -newermt 2026-10-14` = **仅 2 文件** ✓。
- **§4-A 偏离**：证据链（`xvlog.log:9` 的 `10-3609` + xelab 编译表内的网表侧原语）**方向可信**；其"未实跑验证"的自我限定**如实** ⇒ 已按"下一棒跑门先核锚点"排入 mdio 构建轮。
- 未复核项（如实登记）：负对照的"怎么红"逐字（未跑）；`violation` 类细节按原件保留。
