# F-3 实施 + 门 G1 报告（`p9_impl_f3_20261015`）

> agent 原件由平台拒写 .md ⇒ 全文回传、TL 代落盘（文末「TL 附加」= 抽核与裁定，非 agent 正文）。
> **结论口径**：本报告**不下 PASS/FAIL 裁定**（裁定权在用户/判据所有者）。下面给的是**读数与形态**。
> **运行环境纪律**：全程只跑 xsim/xvlog/xelab（模拟器），**未跑任何综合/实现/位流（vivado.bat 一次未启）**、未碰对端机、未动 `rtl/tcp_rx.v` / `rtl/app_pattern.v`（`git status` 可证）。每次跑门前均核 `tasklist` 无 xsim/xelab/vivado。

---

## ① 逐文件 diff 摘要

### `rtl/vlan_strip.v` — **11 hunks / +52 / −9 / 非注释 +20 / −9**
非注释新增行（按设计件 A 清单分组，与 v2 §2.2 old-new 文本逐字一致）：
- **A1**：`module vlan_strip #(` / `parameter RESYNC_EN = 1'b0` / `)(`
- **A2**：`reg resync;` / `wire fwd = (!RESYNC_EN) || resync || s_axis_tuser;`
- **A3**：`wire acc_f = acc && fwd;` / `wire rsw = RESYNC_EN && acc && !(acc_f && rst_n);` / `reg [31:0] stat_resync_words;`
- **A4（8 处 acc→acc_f）**：`load_pass` / `load_w1` / `load_shift` / S_W1 的 hold 装载 / `shifting && acc_f` / `S_PASS` / `S_W1` / `S_SHIFT` —— **`:105 s_axis_tready` 一字未动（Policy D）** ✓
- **A5**：`resync <= 1'b0;` / `stat_resync_words <= 32'd0;`
- **A6**：`if (acc_f && rst_n) resync <= 1'b1;` / `if (rsw) stat_resync_words <= stat_resync_words + 32'd1;`（插在 `case (state)` 之前）
- A8（文件头合同追加）= 纯注释。

**插入型编辑保住旧行**：9 处删除全部是**有意替换**（8 处 `acc`→`acc_f` + `module vlan_strip (` 一行）；其余全为插入。

### `board/wrapper_p4.v` — **4 hunks / +15 / −2 / 非注释 +4 / −2**
- B1（取"更省写法"）：双域支 `localparam VLAN_STRIP_RESYNC = 1'b1;` + 单域支 `= 1'b0;`（各带 2/1 行注释）
- B2：`vlan_strip #(.RESYNC_EN(VLAN_STRIP_RESYNC)) u_vlan_strip (`
- BID：`32'h00000024 → 32'h00000025`（注释块同步补 0x25 条目；0x24 历史块保留）
- ⛔ **禁碰区 `:1319-1322` 逐字未动**（4 行 `app_reg_*` 在 HEAD 与工作树各 1 命中、内容相同，机器核过）。

**新增**：`sim/f3_resync/{tb_f3_resync.v, run_tb_f3_resync.bat(ASCII+CRLF), mut/mk_mut_f3.py, G1_READINGS.txt}`。**未改任何其它文件。**

**一处"设计可选、我判不做"**：(A7) 端口出 + (B3) wrapper 接出 ⇒ **不做**。理由：v2 标 A7 为"可选"且两者合并后设计自己写明"接出但不进窗口 ⇒ 综合当死逻辑剪掉（零代价、零观测）"；G1/G2 都用层次名读计数器即可；B3 还会多改禁碰区所在文件。若复核要 A7，是一处小编辑。

---

## ② G1 跑动记录（`cmd //c 'sim\f3_resync\run_tb_f3_resync.bat'` ⇒ **GATE PASS, RC=0**，终态从零复跑）

原始逐臂日志 = `sim/f3_resync/{runF,runL,runM1,runM2,runC}/xs.log`；策展读数 = `sim/f3_resync/G1_READINGS.txt`。
编译源 sha256：F/L/CTRL = `rtl/vlan_strip.v 04a12ff2…`；M1 = `mut_m1.v 49fd69ce…`；M2 = `mut_m2.v 4fdc480a…`（`mutgen` 锚点计数断言：改动行 = **恰好 1 行**）。

| 臂 | CHK 行（逐字） |
|---|---|
| **F**（新 RTL，RESYNC_EN=1） | `F3R CHK J1=1 J2=1 J3eq=1 J3pos=1 J4=1 J5=1 J6=1 ALL=1` |
| **L**（新 RTL，RESYNC_EN=0） | `F3R CHK J1=0 J2=0 J3eq=1 J3pos=0 J4=1 J5=0 J6=1 ALL=0` |
| **M1**（`fwd=1'b1`） | `F3R CHK J1=0 J2=0 J3eq=0 J3pos=0 J4=1 J5=0 J6=1 ALL=0` |
| **M2**（`fwd=…||s_axis_tlast`） | `F3R CHK J1=0 J2=0 J3eq=0 J3pos=1 J4=1 J5=0 J6=1 ALL=0` |
| **CTRL**（RESYNC_EN=1 + 注入挪到帧间） | `F3R CHK J1=1 J2=1 J3eq=1 J3pos=0 J4=1 J5=1 J6=1 ALL=1` |

**F 臂（正臂）逐条绿**：注入见证 `dp_rst_dp RISE at 2884000 / FALL at 14922000, stall_edges=0(钟真停), rstwin_edges=6`；`DELIV[0] len=64 WHOLE 帧4 crs=1 tuser_direct=1`；`SHAPE ndel=8 whole=8 frag=0 stale_frag=0 trunc_with_crs=0 unrec=0 srco_nz=0`；`POP-ACCT pop_pre=25 pop_rst=2 pop_post=69 taken_all=89 taken_post=64 rsw=5 mirror=5`；`resync_final=1`。J1..J6 全 `=> PASS`。
⭐ J2 同时给出 C9/L1 的当场证据：`tuser_direct=1`（首字拍直采）而 **`tuser_legacy=0`**（旧记录器对同一真 SOP 字给 0 ⇒ 它量的是自己的簿记）。

**L 臂缺陷复现形态（逐字）**：
```
F3R DELIV[0] len=40 **片段** 源帧=3 偏移=24 crs=1 tuser_direct=0   <== 陈字(重启前就开始收的帧)
F3R SHAPE ndel=9 whole=8 frag=1 stale_frag=1 trunc_with_crs=1 unrec=0 srco_nz=1
F3R WITNESS dp_rst_dp RISE at 2884000 (t0) / FALL at 14922000 (t1) stall_edges=0 rstwin_edges=6
F3R POP-ACCT pop_pre=25 pop_rst=2 pop_post=69 taken_all=94 taken_post=69 rsw=0 mirror=0
F3R STALE-CONSERV dw_all=69 pushes_after=70 => stale_words=0
F3R XFAIL-REPRODUCED frag=1 trunc_with_crs=1 stale_frag=1
```
与 t9 `case_old` 历史读数**逐字同形**（len=40/源帧3/偏移24/crs=1、ndel=9/whole=8/frag=1、stale_words=0、silent_drop=0、dw_all=69/pushes=70）。⇒ **L 臂 = `XFAIL-REPRODUCED`** ✓

**突变臂红点集**：M1 = J1/J2/**J3eq**/J5 红且 `ALL=0`（行为 = 与 L 同形 ⇒ "谓词没承重"被抓住，且 `J3eq=0` 是"变异真生效"的独立见证）；M2 = J1/J2/J3eq/J5 红、`J3pos=1`、`DELIV[0] len=8 偏移=56`（**开在帧尾** ⇒ 恰交付帧 3 的 tlast 尾字）。

**CTRL 臂（J3 正对照）**：`ctrl-precond si=392 (IFG=[376,399]) rx_empty=1 stable4=1`；`J3 rsw=0 mirror=0 eq=1`；`pop_rst=0 pop_post=64 taken_post=64`；96 字**零丢失**、8 帧全整 ⇒ 计数**不是恒正**且"干净帧间隙注入 = 零影响"。

---

## ③ RESYNC_EN=0 等价证据

**结构（设计 I1/I2，我复核同意）**：`RESYNC_EN=0 ⇒ fwd ≡ 1 ⇒ acc_f ≡ acc` ⇒ 8 处替换在综合期常数折叠回原式；`resync` 唯一作用点被真短路（无扇出）、`rsw ≡ 0` ⇒ 计数器被优化掉。

**可运行证据（三条，均可复查）**：
1. **既有门 `sim/vlansim/run_tb_vlan_strip.bat`（默认参数 ⇒ 本刀默认路径）**：`VLAN_STRIP TB PASS (in=1595 words, out=1502 words, vlan frames=66, stripped=66)`，与**改动前同门日志**（`sim/vlansim/xsim_run_26328.backup.log`，09-29）**逐行相同**（含 `$finish called at time : 18364 ns`）——唯一差异 = 会话元数据（时间戳/PID/OS build/Available Virtual）。
2. **L 臂**（新 RTL 编译 + RESYNC_EN=0）与 t9 历史缺陷形态**逐字同形**（见 ②）⇒ 行为级"与改动前同"。
3. **`sim/p5wu_p1p2/run_xvlog_wrapper63.bat`**：**6/6 OK**（含 `d0_default`=单域支 ⇒ 覆盖新增的 `1'b0` 行；`d3`=板配置 ⇒ 覆盖参数绑定）。

---

## ④ G2 选路与理由 —— **走路 2**（明写：**G2 不判 F-3 本身**）

理由（两条，均现读实证）：
1. **路 1 超出本轮文件所有权**：加"DP 侧 `vs_tuser` 逐帧见证 + I-1/I-2 注入"必须改 `_proj_10g/p7b_chain/sim/tb_p7b_chain.v`（106 KB）或 `sim/p6e_pcie/tb_p6e_pcie_wrapper.v`，两者都不在派单文件清单里 ⇒ 代价 >1 小时且越权。
2. ⭐ **设计点名的 G2 仪器在 HEAD 就结构性死亡**：`_proj_10g/p7b_chain/sim/run_tb_p7b_chain.bat` 跑出
   `ERROR: [VRFC 10-2063] Module <xpm_memory_sdpram> not found while processing module instance <u_ram> [ …/rtl/mir_uram_fifo.v:190]` + `ERROR: [XSIM 43-3322]`
   ⇒ 该门自 URAM 轮（0x24）起缺 xpm 库注册（**同一轮的 p6e 门补了 `-work xpm` + `-L xpm`，这张门没补**）。成因与本刀无关（结构判定：我的 diff 不含 `mir_uram_fifo.v`）。

**G2 实际执行 = p6e 全链门（板等价宏集 `PCIE_OBS+DEV_USP+APP_MODE+DP_156MHZ+P6B_SIM_CLKGEN`，门真打开）双树 A/B**：

| 树 | 读数 |
|---|---|
| 真 HEAD RTL（临时 worktree 提供文件，跑完已删） | **144 PASS / 0 FAIL / `PASS_ALL`（RC=0）** |
| 打过本刀 | **143 PASS / 1 FAIL**，唯一 FAIL = `BUILD_ID = 00000025 (期望 00000024)` |

⇒ **"回归未受伤"成立（除 BID 身份断言外逐条不变）**；该 1 FAIL = 已登记的重基线项（`sim/p6e_pcie/tb_p6e_pcie_wrapper.v:215` 与 `tb_p6e_pcie_counters.v:206` 硬编码 `0x24`，**不在我的所有权内**，随构建轮 `apply_readside_bid1c.py --bid 0x25` 一并对齐）。
**G2 的 witness 两格 = "未观测到"**：(a) `u_dut.dp_rst_dp` 走完整段 = **未观测到**（无注入）；(b) `u_dut.u_vlan_strip.stat_resync_words > 0` = **未观测到**（无注入、无探针）。G2 只报"回归未受伤 + 冷启动零影响相容"（p6e 从复位冷启的 143 条判据全绿）。

**G3 = 只登记**：G1 需进 `sim/p4gates/run_matrix_p4dfix.bat` 的 gate 行（本轮未动矩阵，遵派单）。

---

## ⑤ 异常与偏离

1. ⛔ **设计内部不一致（未迁就、未自作主张——按锚点字面实施，口径如实停报）**：v2 §2.2-(A6) 的说明写"`rsw` 里的 `!(acc_f && rst_n)` 是**复位窗口内弹掉…的唯一来源**"，但 A6 的**锚点落点**（`case (state)` 之前）在 `else`（rst_n=1）支内 ⇒ **复位窗口内被弹出并静默丢弃的字根本不会进 `stat_resync_words`**。实测证据：F 臂 `pop_rst=2`（复位窗内弹掉 2 个字，静默丢失、未计），且把 J4 写成字面的 `pop_total == taken + rsw` 会**恒定差 pop_rst**。**处置**：J4 按设计自己的 I5 口径实施（I5 逐字把划分限定为"**rst_n=1 时** `acc ≡ acc_f + rsw`"）⇒ 判据 = `pop_post == taken_post + rsw`，五臂**逐跑精确闭合**（69=64+5 / 69=69+0 / 69=65+4 / 64=64+0）；`pop_rst` 单列打印（就是"窗口内浪费"的量化）。**未移动计数行**（那属于改设计）——请复核裁定是否要在 A6 说明里加限定，或把计数器移出 `else` 支。
2. **TB 注入竞态（已修，且是保真度改进）**：照 t9 的 `dp_rst_dp = 0;` 紧跟 `repeat(4)@(posedge dclk)` ⇒ 释放落在 dclk 沿上 ⇒ TB 相位计数与 DP 侧时序逻辑是**两个视图**（本仓坑 17 同族），症状 = `pop_post` 恰好多 1 ⇒ J3/J4 假红。修 = 沿后 `#0.1` 释放（硬件上该沿对两侧都是"仍在复位"，所以这是更保真）。修后 F 臂 J3eq/J4 全绿。
3. **`-testplusarg NAME=VALUE` 在本机全形态失败**：`Expected a switch but found F` —— 本仓既有文档 `sim/d2run/p4prv/run_tb_p4_burst.bat:66-68` 已记录 ⇒ 改用 `-d` 定义传臂身份。
4. **bat 两处 cmd 脆弱点（已修）**：① 块内 `echo … (… )` 的嵌套括号 + `findstr | findstr` 管道会被 cmd 静默弄坏（症状 = 无消息 RC=1）；已改为单字面量 grep `F3R CHK …`。② 漏 `cd /d "%HERE%"` ⇒ 汇总循环的相对臂目录找不到。
5. **CTRL 臂的构造比 v2 字面更强（已文档化）**：纯"挪到 IFG"不具确定性——释放窗内的弹出会吃掉 FIFO 队首（把下一帧头 4 字吃掉）⇒ Δrsw 会 >0。故 CTRL = **IFG + FIFO 空（4 拍稳定判据） + 失锁窗内冻结 FE**，实测 `pop_rst=0`、Δrsw=0。
6. **p7b chain 门 HEAD 即死**（见 ④-2）：本轮**登记不修**。副作用：该门的未入库旧日志 `xsim_p7bchain.log`（10-10）被我这跑覆盖（同名读数在 `_proj_10g/notes/p7b_regression/logs/p7b_chain.log` 等 **8 处归档副本**仍在）。
7. **被跟踪文件 `_proj_10g/p7b_chain/sim/files.f`** 会被那张门的历史性行为重新生成；已按 HEAD blob **逐字节还原**（sha256 相同、`git diff` 为空），残留的 ` M` 只是 CRLF 索引元数据。（TL 已 `git checkout --` 清除该残留。）
8. **G2 基线用的临时 worktree** `…\udp_hls_10g_f3head`（HEAD 5ffe8f9 + 拷贝 HLS 产物）**已删除**（`git worktree list` 只剩主树与既存 agent worktree）。重建配方：`git worktree add --detach <path> HEAD` + 拷 `hls/slowstack_prj/solution1/syn/verilog`（gitignore 产物）。
9. **A7/B3 未做**（见 ①）。
10. **A1 注释里的路径指 v1 `DESIGN.md`**：按"逐字照 v2 文本、不改设计"保留；v2 才是权威件 —— 供复核决定是否改指针。

---

## ⑥ 未观测到 / 未做（防误读）

- **G2 不判 F-3 本身**（无注入 ⇒ 无 witness；见 ④）。**"未观测到" ≠ "不存在"**。
- **TX 臂 J7 未跑**（v2 标"可选"）⇒ §1.5 的 TX 侧【推断】仍未被本门测过。
- **A7/B3 未做**；`stat_resync_words` 未进快照（按 v2 §4.3-③ 勿动 NW/地址常量）。
- **门 G1 的"门真打开"见证**：G1 各臂有（xelab 打 `vlan_strip(RESYNC_EN=1'b1)` + 臂 banner `resync_en=`）；**p6e 构建里只有结构见证**（宏 + 源码文本 + xelab 接受该参数绑定），无独立见证 —— 写"未观测到直接见证"。
- **板级 = "未观测到"**（v2 §5.2：板上无法受控触发失锁）；本轮**未构建、未烧板**。
- 时序/资源 = **零读数**（本刀未综合；v2 §4.1/§4.2 仍是预算）。

**给下一轮（构建轮）的接口清单**：① 构建 0x25（BID 已 bump；两处 p6e TB 的 `0x24` 硬编码与读侧 `EXPECT_BID` 需按 `apply_readside_bid1c.py --bid 0x25` 对齐）；② 常驻矩阵会因 `rtl/vlan_strip.v` 哈希变化打红 **FROZEN/修订指纹**（设计 §4.3-③ 已登记：重基线理由 = "参数 + 门 + 计数"，**不许**用"指纹变了/没变"冒充等价证据）；③ G1 进矩阵（G3）；④ 若要让生成物不入库，`sim/f3_resync/mut/mut_*.v` 可照 `sim/p3sim_sw` 的 `.gitignore` 风格加一行（生成器 + `G1_READINGS.txt` 建议入库）。

----------------------------------------------------------------

## TL 附加（2026-10-15 01:5x；抽核 + 裁定）

**抽核**：工作树恰 `M rtl/vlan_strip.v` + `M board/wrapper_p4.v`（+ `files.f` 的 CRLF 残留，已 `git checkout --` 清为 HEAD）；`board/wrapper_p4.v:4322` BID 现读 = `0x25` ✓；`sim/f3_resync/G1_READINGS.txt` F 臂 `J1..J4 => PASS` 逐字在档、`pop_pre=25 pop_rst=2 pop_post=69 … rsw=5` 与报告一致；diff stat（61/17 总变行）与报告吻合。
**裁定（自主期内由 TL 代行；留痕供 owner/复审）**：
1. **A6/J4 不一致（偏离 #1）**：**采纳 agent 的 I5 口径实施**（五臂精确闭合恰如读数）+ **不移动计数行**（不在战役中途改设计）；把"v2 §2.2-(A6) 说明需加 `rst_n=1` 限定 + `pop_rst` 单列口径"列入**设计文档订正项**（留待修订/复审轮统一）。
2. **A7/B3 不做**：认可（v2 标可选，且"接出即被剪"）。
3. **G2 走路 2**：认可（路 1 越权是真的）；**新登记**：`run_tb_p7b_chain.bat` 自 URAM 轮起缺 xpm 库注册（HEAD 即死 `VRFC 10-2063`）——登记不修，已列入构建轮交办。
4. **TX J7 / A7 / 板级 / 时序** = 未做/未测，照实。
5. 一处 GBK 花码（`G1_READINGS.txt` 的 `STALE-CONSERV` 行尾注释）按原件保留（控制台编码产物）。
**口径**：以上均为读数与形态；判据层裁定权在 owner。
