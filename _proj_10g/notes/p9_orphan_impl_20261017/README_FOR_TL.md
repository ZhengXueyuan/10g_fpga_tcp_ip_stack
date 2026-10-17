# p9_orphan_impl_20261017 —— 孤儿会话修复**实施**轮（RTL + 单元/全链门；无构建）

> 依据件：`_proj_10g/notes/p9_orphan_fix_design_20261017/README_FOR_TL.md`（v4，841 行；**附录 B = 实现权威**）。
> 本件 = 实施轮交付：三文件 RTL 改动 + 新单元门 + 新全链门 + 矩阵读数 + 偏离/发现。
> **未做构建**（不跑 Vivado synthesis/impl/bitgen）；**未上板**；**未改读侧脚本**（设计件 §5 的读侧同步归构建轮）。
> 标签口径：【已证（`文件:行`/读数）】·【推断】·【未判定】。

---

## 0. 一句话结果

| 项 | 结果 |
|---|---|
| 三文件 RTL 改动 | ✅ 完成（`rtl/app_ctrl.v` +295/−?、`rtl/slow_cfg_adp.v` +8、`board/wrapper_p4.v` +148/−?） |
| 单元门 U1–U12（含 U10'/U12b/U9B） | ✅ **18/18 臂全 PASS**（**全套重跑**：`runs/unit_suite.txt` = `SUITE_DONE fails=0`，exit 0；逐臂 stdout `runs/unit_*.txt`） |
| 单元变异 M1–M14 | ✅ **14/14 全红**（含设计件 M1–M13 + 新加 M14 交接拆拍牙；同一 suite 跑） |
| 全链 C2a / C3 / C4 | ✅ PASS |
| 全链 C2b（OVL 构建，真纯 ACK 帧注入） | ✅ PASS（4 个真 `ack_obs` 脉冲；活零窗不点火 / 死零窗点火） |
| 全链 C1 | ⚠️ **1 条子判据 FAIL —— 设计与 RTL 交互发现，见 §5-F1**：`closing` 成立、新 ADD 恢复成立；但"孤儿回收后 `active=0`"在当前帧器接受门下**结构性不可达**（窗满孤儿特例） |
| 矩阵（19 门） | ✅ **19/19 EXIT=0，gates failed 0，VERDICT FROZEN**（§6） |
| 语法/隐式门 | ✅ xvlog/xelab 语法面 0 error（含 **非 APP_MODE 的 wrapper 单独 xvlog**）；全链构建的 5 键隐式门 0 命中 |

---

## 1. 改动面（严格三文件 + 新 TB/门脚本）

### 1.1 `rtl/app_ctrl.v`（大改）

**参数（6 个，默认值按设计件 §3.3）**
```
ORPHAN_EN=1'b0 · ORPHAN_LIM=8'd144 · ORPHAN_TICK_BITS=18
ORPHAN_ZW_EN=1'b0 · ORPHAN_ZW_LIM=8'd105 · ORPHAN_ZW_TICK_BITS=20
```

**端口（7 个输入 + 3 个输出）**
- 输入：`retx_active`、`retx_id[3:0]`、`una_adv`、`una_adv_id[3:0]`、`ack_obs`、`ack_obs_id[3:0]`、`scfg_busy`
  （⚠️ 派单文字写"6 输入"，设计件 §5/§3.2 列的是 **7 个**；按设计件实施 7 个。）
- 输出：`orphan_cam_clr`、`orphan_cam_slot[3:0]`、`stat_orphan[31:0]`

**实现要点（逐条对附录 B）**
- `orph_cnt[0:15]` / `orph_zw_cnt[0:15]` 8 位饱和；`orph_saw[15:0]`。
- 模式 A：`scan_gate/inflight/cap_eff/win_closed/work/accrueA/orph_tick` 逐字按附录 B §2；
  `fireA` 含 `!orph_busy`；`work` 的 retx 覆盖保留（`M3` 牙）。
- 模式 B：`orph_zw_tick/accrueB/fireB` 与**计数/清零块全部包在 `if (ORPHAN_ZW_EN)` 内**
  （`ORPHAN_ZW_EN=0` 时寄存器不写、综合折叠；不计数/不清零/不点火）。
- 清零优先级：`una_adv` 逐拍清零（附录 B §3.1）+ 扫描块内 `if (clr) 0; else if (tick) +1;`
  （§3.2）；**事件同槽清零块物理放在计数块之后**（`ev_up || ev_down_i` ⇒ 赢），覆盖 §3.2 正文
  "ev_up/ev_down 同槽 ⇒ 清"。
- FSM：`fire → fc gnt(state_done) → CAM 清 → cam_clr_done 同沿交接 wait_cam→notify_pend →
  deliver_gate 投递 down_r（同沿清 notify_pend）→ 1 拍 down_r`；`orph_busy` 五项含 `orph_down_r`；
  `orph_abort_comb` 组合（ev_up/ev_down_i 同槽 + fin_sent/rst_sent[orph_slot]）。
- `ev_down_i = ev_down | (ORPHAN_EN && orph_down_r)`，`ev_slot_i` 同门；**全部 use-point**：
  事件块（归还/winq/wu/fc/st/to/fin 清理 + `o_ev_down/o_ev_slot`）、`ev_blk`、`ev1_v/ev1_slot`、
  `hit_b/hit_c`、`to_push`（+`!orph_down_i`）、`ret_slot_q/pool_ret_x`。`ev_push`/`stat_ev_drop`/`ev_ovf` 保持原始。
- `fc_upd_wr` 组合门 **放在 ORPHAN_EN 内**：`fc_v && (!ORPHAN_EN || 同槽 ev_up/ev_down 不置位)`。
- **实现补强（F2 的"请求撤销"闭合）**：同一作用域内把 `fc_load` 也挡住同槽事件拍
  （`fc_load_blk`）。**理由（必须看）**：只挡 `fc_upd_wr` 时，事件拍仍会按旧 `st_pend`
  **装载** `fc_v`，下一拍（事件已回落）该 state=0 写照样落地 ⇒ 新会话静默死。
  这一条是设计件 F2 文字"事件块清 st_pend/fc_v，请求撤销"的**必要条件**（发现，见 §5-F2）。
- `stat_orphan` 只在 `orph_down_r` 拍 +1。

### 1.2 `rtl/slow_cfg_adp.v`
仅新增 `output wire o_busy = (state != S_RECV) || !f_empty || (wcnt != 3'd0);`（F16）。

### 1.3 `board/wrapper_p4.v`
- **参数表**（新增）：`ORPHAN_EN_5=1`、`ORPHAN_LIM_5=144`、`ORPHAN_TICK_BITS_5=18`、
  `ORPHAN_ZW_EN_5`（`` `ifdef TCP_TX_OVL `` ⇒ 1，否则 0）、`ORPHAN_ZW_LIM_5=105`、`ORPHAN_ZW_TICK_BITS_5=20`。
- **N2 结构防呆**：`generate if (ORPHAN_EN_5 && ORPHAN_ZW_EN_5 && !ACK_OBS_AVAILABLE)`
  实例化不存在的模块 ⇒ **elaboration 硬失败**（xelab/Vivado 都拒绝；不是警告）。
  `ACK_OBS_AVAILABLE` 由 `` `ifdef TCP_TX_OVL `` 定义。
- **前置声明**（坑 #24）：`rx_upd_wr/gnt/id/sel`、`rx_ack_obs/id`、`tx_retx_active`、`tx_retx_id_o`、
  `scfg_busy`、`orphan_cam_clr/slot`、`una_adv` 全部移到 `u_app_ctrl`（~1279）之前；**删除**原
  `:1761/:1782-1784/:1829-1830/:2132` 的重复声明。
  `assign una_adv = rx_upd_gnt && (rx_upd_sel == 3'd2);`
- u_app_ctrl：6 参数 + 7 输入 + 3 输出全部接线。
- `u_slow_cfg`：`.o_busy(scfg_busy)`。
- **CAM 写 mux（scfg 优先）**：`cam_cfg_*_mux`；orphan 清 = 该槽五字段全 0。
  非 APP 构建：`orphan_cam_clr/slot` 显式 tie 0（否则 mux 读 Z）。
- 快照：`SNAP_P7BDP_NW 35→36`、`SNAP_NW_P6E 75→76`；W75 = `app_stat_orphan` @ `0x14C`
  （p7bdp 槽 35）；`snap_dout_all` 顶部插入 W75；**MIR 由 `axi_regs.SNAP_LAST_IDX` 自动推**
  ⇒ MIR `0x150..0x15C`、UNIMPL `0x160`（未写死任何 MIR 地址）。
- **`.PERSIST_EN(1'b0) → 1'b1` 还原**（HEAD 0x29 拆刀态）。
- **`BUILD_ID_V 0x29 → 0x2A`**。

### 1.4 新 TB / 门脚本（均在 `sim/p9_orphan/`，TB 在 `tb/`）
- `tb/tb_app_orphan.v`（单元门；18 场景 + 冻结锚并行实例）
- `tb/tb_p5_orphan_wrapper.v`（全链门；C1/C2a/C3/C4/C2b；真 ACK 帧注入）
- `sim/p9_orphan/gen_mutants.py`（13 个变异体；锚点命中数硬断言）
- `sim/p9_orphan/run_orphan_unit.bat` / `run_orphan_suite.bat`
- `sim/p9_orphan/build_p5_orphan_wrapper.bat` / `run_p5_orphan_scen.bat`
- `tb/tb_p5_wrapper.v`：**基线臂显式传 `ORPHAN_EN_5=0/ORPHAN_ZW_EN_5=0`**（N12，不重基线）。

### 1.5 diff 统计（git 现读）
```
 board/wrapper_p4.v | 148 ++++++++++++++++++++++-----
 rtl/app_ctrl.v     | 295 +++++++++++++++++++++++++++++++++++++++++++++++++-----
 rtl/slow_cfg_adp.v |   8 ++
 tb/tb_p5_wrapper.v |   7 +-
 4 files changed, 407 insertions(+), 51 deletions(-)
```

---

## 2. 单元门（`tb/tb_app_orphan.v`）—— 全过

**整套复跑**：`runs/unit_suite.txt`（`SUITE_DONE fails=0`，exit 0；console =
`runs/unit_suite_console.txt`）。**TB 配置（v4 钉死）**：`ORPHAN_LIM=2`、`ORPHAN_TICK_BITS=1`、
`ORPHAN_ZW_LIM=2`、`ORPHAN_ZW_TICK_BITS=1`；活动臂 `ORPHAN_EN=1`；U11/U12/U12b 另
`ORPHAN_ZW_EN=1`；U10/U10' 用 0。U10' 冻结锚 = **HEAD `55d9012b` 的 `rtl/app_ctrl.v`**
（sha256 `cc7af9a8…8881`，存 `frozen/`；TB 副本仅改模块名 `app_ctrl_frozen`）。

| 臂 | 期望 | 读数 |
|---|---|---|
| U1 健康推进 | stat=0 | **PASS**（stat=0） |
| U2 孤儿模式A | 1 state 写 + 1 CAM 清 + 1 o_ev_down + stat=1 | **PASS** |
| U3 零窗负对照 | 0 点火 | **PASS** |
| U4 慢盆 a/b/c | 0 点火 | **PASS** |
| U5 回卷重放（U5a 持续 retx + U5b 携带） | 点火 | **PASS** |
| U5b 活动 retx 支 | 点火 | **PASS** |
| U6 ADD 竞态 pre/post | 中止、无通知 | **PASS** |
| U6b 双槽 + 交接拍 | 两槽都完成（stat=2） | **PASS** |
| U6c state→CAM 窗口 | state_done 前无清；busy 期间无清 | **PASS** |
| U7 通知顺序 | 严格在 state_done/CAM 清之后，1 拍 | **PASS** |
| U8 DEL 竞态 | 中止、仅真 ev_down 1 个通知 | **PASS** |
| U9 饱和 | 计数饱和 0xFF、只点火一次 | **PASS**（自然饱和 260 ticks） |
| U10 EN=0 冒烟 | 全 0 | **PASS** |
| U11 模式B 点火 | stat=1 | **PASS** |
| U12 模式B 负对照 | 0 点火 | **PASS** |
| U12b 模式B 单次丢失 | 0 点火 | **PASS** |
| U10' 零回归 | 同激励全输出逐位相同 | **PASS**（4207 拍对比，0 mismatch：`o_ev_up/o_ev_down/o_ev_slot/stat_ev_up/stat_ev_down/pool/winq/app_tx_ready`） |
| U9B to_push 碰撞（M9 牙） | 不同拍 | **PASS** |

**变异（`gen_mutants.py`；M1 = `ORPHAN_LIM=0` 泛型，不需补丁）**

| 变异 | 期望红在哪 | 实读 |
|---|---|---|
| M1 LIM=0 | U1 | **FAIL（红）** |
| M2 删 snd_wnd!=0 | U3 | **红** |
| M3 删 work 的 retx 覆盖 | U5a | **红** |
| M4' 第三因子强制 1 | U4c | **红** |
| M5 删 abort_comb | U6 post | **红** |
| M6 删 CAM 清 | U2 | **红** |
| M7 通知早于 state gnt | U7 | **红** |
| M8 删 o_ev_down（ev_down_i 只留真 ev_down） | U2 | **红** |
| M9 删 !orph_down_i 门 | U9B | **红** |
| M10 删 ack_obs 清零 | U12（ZW=1） | **红** |
| M11 CAM issue 删 state_done | U6c | **红** |
| M12 删 !orph_busy | U6b | **红** |
| M13 orph_down 改组合 | U2 | **红** |
| **M14（新加）交接拆两拍** | U6b handoff | **红** |

**TB 级实现说明（非判据改动）**
- xsim 禁止对非网 reg 的位选做 force ⇒ `orph_cnt[1]/orph_saw[1]/to_pend[1]/wcnt`
  用**层次阻塞赋值**；`scan_tick`（1 位网）/`scan_id`（整寄存器）用 force。
- U6b 交接拍臂：正确实现的 FSM ~8 拍就完成（< 相邻扫描拍间隔 16），自然扫描**永远采不到**
  1 拍 gap；该臂在交接拍**强制一拍 scan_tick + scan_id=1** 来打 M14（mutation 才有牙）。
- M12 的双槽臂需要在第一槽点火后**保持 `scfg_busy`** 才能让两槽 FSM 重叠（否则第一槽已完成）。

---

## 3. 全链门（`tb/tb_p5_orphan_wrapper.v`）

构建：`build_p5_orphan_wrapper.bat <OVL>`（APP_MODE；OVL=1 另加 `-d TCP_TX_OVL`）。
`runs/build_p5orphan_ovl0.txt` = `GATE_BUILD_OK OVL=0`；`…ovl1.txt` = `GATE_BUILD_OK OVL=1`。
**两构建的 5 键隐式门 0 命中**（`Synth 8-11241`/`undeclared symbol`/`VRFC 10-3091 actual bit length 1…`/`VRFC 10-2989`/`implicitly declared`）。

| 臂 | 配置 | 读数 |
|---|---|---|
| **基线** `tb_p5_wrapper`（原门） | `ORPHAN_EN_5=0/ZW_EN_5=0` | ✅ `P5 WRAPPER OK`（3 帧 / 4380 B 逐字节） |
| **C1** | 孤儿臂 A（1/0，LIM=2/TICK=1） | ⚠️ **1 条子判据 FAIL**（`runs/p5orphan_s1.txt` + 全日志 `runs/xsim_C1_full.log`）：`o_ev_down` 成立、`app.closing=1`、**新 ADD 后 app 恢复 `active=1`/`closing=0`/`stat_tx_frames` 继续增长（重新发帧）**；但"孤儿回收后 `active=0`"**未达成** —— 见 §5-F1（`C1 app state: active=1 closing=1 pw_valid=1 op_sent=1 seg_sent=0 m_tready=0`） |
| **C2a** | 孤儿臂 A | ✅ PASS：健康推进/零窗/慢盆三模式 `stat_orphan=0`、`n_cam_clr=0` |
| **C3** | 孤儿臂 A | ✅ PASS：① 正常路径 `orphan_cam_clr && scfg_cam_wr` 0 次；② 强制同拍碰撞时 CAM 写入 scfg 值（`sip_r[5]=DEADBEEF`、dmac 逐字）；③ `orphan_cam_clr` 只在 `orph_state_done` 之后 |
| **C4** | 孤儿臂 A | ✅ PASS：`scfg_busy` 保持 32 拍期间 0 CAM 清、释放后恰有清；`wcnt!=0` ⇒ `scfg_busy=1` |
| **C2b** | 孤儿臂 B（1/1，`TCP_TX_OVL`） | ✅ PASS（`runs/p5orphan_s5_ovl.txt` + 全日志 `runs/xsim_C2b_full.log`）：**真纯 ACK 帧注入**（RGMII `e_rxd/e_rxdv`，非 force ack_obs）⇒ 诊断行 `mac_frames=4 mac_crc=0 pass=4 drop_seq/nm/ipc=0 **ackobs=4**`；活零窗（周期 ACK）`stat_orphan=0`；死零窗（停止注入）⇒ **点火 stat=1 + CAM 清** |

---

## 4. 语法 / 隐式门

- `xvlog` 三文件语法：0 error（`work_syntax/xvlog_syntax.log`；xelab `app_ctrl` 单独 elaborate 0 error）。
- **非 APP_MODE wrapper 单独 xvlog**：0 error（`work_syntax/xvlog_nonapp.log`）—— 覆盖
  orphan tie-off / CAM mux / 参数表的默认分支文本面（默认构建的 elaborate 仍归构建轮）。
- wrapper 全链两构建：`build_p5_orphan_wrapper.bat` 的 5 键隐式门 0 命中（见上）。
- 新 `.bat` 全部 **ASCII + CRLF**（项目纪律；两处中文 REM 已改英文）。

---

## 5. 偏离 / 发现（必须读）

### F1【设计 vs RTL 冲突 —— C1 的 "active=0" 不可达】【已证（仿真状态 dump + RTL 阅读）】
- **现象**：C1 在"窗满 + snd_una 冻结"的孤儿回收后，`app_pattern.closing=1` 恒久，
  `active=1` 不落 0（12000 拍后仍如此）。dump：
  `active=1 closing=1 pw_valid=1 op_sent=1 seg_sent=0 m_tready=0`。
- **机理**：app 在收尾时走 `close_send`（0 载荷 + tlast 收尾字），它要求 `m_tready`；
  `m_tready` ← `tcp_tx_frame.s_axis_tready`，其 S_IDLE 子句含 **`wnd_open`**
  （`rtl/tcp_tx_frame.v:674`/`:1880`；`wnd_open = state==ESTAB && inflight < min(snd_wnd,WIN_CAP)`）。
  孤儿回收已把 TCB **state=0** ⇒ `wnd_open=0` ⇒ 收尾字永远进不去 ⇒ `closing` 永久保持。
  这不是本 TB 的时序偶然：**模式 A 的目标态就是窗满**，此时 app 通常正压在帧边界上
  （opener 在 pipe 里、帧未启动）⇒ 回收后必现。
- **影响**：核心回收（state=0 + CAM 清 + pool 归还 + `o_ev_down`）**不受影响**；
  app 只是卡在 `closing`，**下一个 ADD 的 `ev_up` 会经 `ev_restart` 清掉它**
  （C1 后半段已实测：新 ADD 后 app `active=1` 且 `closing=0`）。
- **设计件偏差**：设计件 §3.5 动作 #5 写"app 收尾（现有 closing→W3 收尾→active=0）"，
  在"窗满孤儿"这一格**不成立**。**本 agent 未擅自改 RTL/TB 判据来迁就**；C1 如实保留 FAIL。
- **建议（TL 定）**：① 接受"下一次 ADD 自愈"并改设计文字；或 ② 修 `tcp_tx_frame` 的
  S_IDLE 接受门（0 载荷 tlast 收尾字不要求 `wnd_open`，例如给 `close_send` 开一个旁路）——
  后者改第四文件 + 需构建/板级，**超出本轮改动面**。

### F2【F2 组合门的"请求撤销"需要第二条门】【已证（RTL 时序推演 + U6 post 实测）】
- 设计件 F2 只写 `fc_upd_wr` 门。实测/推演：事件拍 `fc_load` 仍按旧 `st_pend` 装载
  `fc_v`，下一拍事件回落 ⇒ 该 state=0 写**照样落地** ⇒ 新会话静默死。
- 已在**同一 `ORPHAN_EN` 作用域**内补 `fc_load_blk`（同槽 ev_up/ev_down 拍禁止装载）。
  U6 post（state_done 后 ev_up、busy 卡住 CAM 清）实测：补强前该写会落，补强后
  `n_wr=0`、`n_cam=0`。**这是设计件文字的闭合，不是语义改写**；请 TL 在 v5 设计件里补一句。

### F3【U6b "相邻扫描拍"天然不重叠；M12 需要 busy 保持】
FSM 在 fc 立即 gnt 下 ~8 拍完成；slot0/slot1 扫描相隔 16 拍 ⇒ 天然不重叠。U6b 双槽臂
用 `scfg_busy` 保持第一槽 FSM 活跃，第二槽才可能在 FSM 活跃期达限。**判据未改**，只是
激励构型；请写进 v5 的 U6b 注（否则复算者照"相邻扫描拍"做会得到空判据）。

### F4【交接拍牙需要强制 scan_tick】
v4 说"把交接拆两拍 ⇒ 交接拍 busy=0 ⇒ 第二槽改写"。1 拍 gap 与 16 拍扫描节拍**不对齐**
（正确实现的 FSM 相位固定），自然扫描采不到 gap。U6b handoff 臂在 gap 拍强制
`scan_tick=1 + scan_id=1`（TB 设备），M14 才红。**这不是判据放宽**：强制扫描仍是真实
的 scan_gate 路径（`fire` 的全部条件照旧）。

### F5【派单文字的三处小不符（已按设计件实施）】
1. 派单写"6 输入"，设计件列 **7 个**（`retx_active/retx_id/una_adv/una_adv_id/ack_obs/ack_obs_id/scfg_busy`）。
2. 派单写"清零块物理放在计数块之后"；**附录 B §3.1 的 una_adv 清零在计数块之前**（用
   §3.2 的 `if (clr) 0; else if (tick) +1` 保证 clr 赢）。本实施按**附录 B（权威）**，
   另在计数块后加"事件同槽清零"块（§3.2 正文要求）。
3. 派单写"wrapper 的 `BUILD_ID_V` bump 0x2A" —— 已做；但 **HEAD 的 `.PERSIST_EN` 还原**
   是构建前置（0x29 拆刀），已同批还原（`.PERSIST_EN(1'b1)`）。

### F7【残留：投递门与事件处理的 1 拍窗口（设计件未覆盖）】【推断（时序推演），未构造臂】
- `deliver_gate` 在 A 拍检查 `!ev_up` 并装载 `orph_down_r`；事件块在 **A+1 拍**消费
  `ev_down_i`（=`orph_down_r`）。若 `ev_up` 恰落在 **A+1**（deliver_gate 无法预知），
  事件块的 `if (ev_up || ev_down_i)` 走 **ev_up 支**，孤儿 DOWN 的
  pool/winq 归还与 `o_ev_down` **丢失**（`stat_orphan` 仍 +1，state=0/CAM 清已落地）。
- **影响界**：核心回收不受影响；丢失的配额会在该槽下一次 ADD 的 C18 记账里归还
  （`app_ctrl.v:987-991`，设计件 §9-6a 同款）；app 会少收一次 CONN_DOWN（下一次
  ev_up 仍能换流）。概率 = 事件拍与投递拍相邻（稀疏事件 × 1 拍窗）。
- **未修**（不擅自改设计）；建议 v5 在 `deliver_gate` 的下一拍再加一级
  `orph_down_pend` 或在事件块给 orphan 单独优先级（注意 ev_up 也不能丢——需同拍双处理）。
- 本轮的 U7/U9B 只覆盖了"投递拍 vs to_push"，**未覆盖本窗口**。

### F6【TB 设备登记】
- 单元门：xsim 禁止非网 reg 位选 force ⇒ 层次阻塞赋值。
- 全链 C1/C2a：TCB 用 negedge 层次重写钉住（tcp_rx 会按 ACK 写 `snd_wnd`）。
- 全链 C1 新 ADD：`scfg_ev_up/scfg_ev_slot` 用 force 注入（等价于 slow_cfg_adp 的 ADD 收尾脉冲；
  未驱动整条 HLS cfg 记录）。
- 全链 C1/C2a 的 `una_adv`：force `rx_upd_gnt/sel/id`（等价 tcp_rx 的授权拍）。
- 全链 C2b 的 ACK：真帧注入（8B 前导 + 54B 帧 + FCS），FCS 自算；`ipcsum` 真校验。

---

## 6. 矩阵（`sim/p4gates/run_matrix_p4dfix.bat`，19 门）—— ✅ 19/19 EXIT=0

原件：`runs/matrix_p4dfix.log`（`sim/p4sim/matrix_p4dfix.log` 的副本）+
`runs/P4_MATRIX_FINGERPRINT_20261017_123200_{before,after}.txt` + `runs/matrix_full.txt`。

- **gates run 19 / 19 · gates failed 0 · exit 0**；逐门 `EXIT=0`（chain … swc）。
- **冻结判据**：`VERDICT: FROZEN -- all 272 hashed files byte-identical across the run`；
  before/after `DIGEST_COMPILE = 23e5fefe…d6bb`（221 文件）/ `DIGEST_ALL = 6d6ac35a…22d3`（272 文件）逐字相同。
- **漂移清单（逐条可解释 = 全是本刀，4 件）**：指纹头 `MODIFIED vs HEAD …4`：
  `board/wrapper_p4.v`（+148/−?）· `rtl/app_ctrl.v`（+295/−?）· `rtl/slow_cfg_adp.v`（+8）·
  `tb/tb_p5_wrapper.v`（+7/−?，基线臂显式 0/0）。**无第五件**。
- `p5_wrapper`（#19）在矩阵内 `EXIT=0` = **基线臂（ORPHAN_EN_5=0/ZW_EN_5=0）保旧基线**。
- ⚠️ **覆盖边界（必须读）**：`chain_src.f` **不含** `wrapper_p4.v`/`app_ctrl.v`（现读 0 命中），
  所以前 18 门的绿**不是**本刀的回归证据；本刀在矩阵里的真实覆盖 = **`p5_wrapper` 第 19 门**
  （F12 的"p5wrapper_src.f 已含被改文件"成立）。**真盲区 = 板宏配置**（`P7B_10G`/`TCP_TX_OVL`/`DP_156MHZ`）；
  `TCP_TX_OVL` 由本轮 C2b 全链臂覆盖，其余由构建轮 + 板级覆盖。
- **新门入册意见（TL 定）**：**暂不入册**。理由：单元门依赖 `frozen/` 锚（在 notes 轮目录）
  与 `gen_mutants.py`（13 个文本锚点，随 RTL 漂移会硬失败）；矩阵是 19 门的稳定面，
  建议先以"轮级门"存在，等锚点固化成 `tb/frozen/` + 独立 manifest 后再按 `swc` 先例入册。

---

## 7. 未做 / 未判定

- **未构建**（按派单）：0x2A 位流、资源/时序、`W75` 的 +96 FF 成本、`SNAP_NW=76` 的
  `axi_regs` 综合 —— 全部留给构建轮。
- **未上板**：C1 的 `active=0` 板级形态、Mode B 的 180.39 s 阈值、persist 相位 —— 板级臂
  （B1/B3/B5/B5b/B5c/B6/B7）未跑。
- **读侧未同步**：`_proj_pcie/p6e_snap_check.sh` 的 `WLABEL`、`apply_readside.py`、
  `P7B_BIZ_WINDOW.md`、`check_window.py`、`tb_biz_win.v`/`tb_p6e_pcie_wrapper.v` 的
  NW/UNIMPL/EXPECT_BID —— 归构建轮（设计件 §5 列了，但**不在本轮改动面**）。
- **`(g′)②` 的 `ack_obs` 语义**：本轮 C2b 用真 ACK 帧验证了"真路径置位"；**未测**
  persist 60 s 档的真实 ACK 间隔（板级）。
- **`ORPHAN_EN=0` 的 wrapper 默认**：非 APP 构建 tie 0 已验证（矩阵 chain 门编译 wrapper
  无 APP_MODE）；`ORPHAN_EN_5=0` 与 `ORPHAN_EN=1` 的逐位零回归只在单元 U10' 证过，
  **wrapper 级逐位对比臂未做**（设计件 F13 的 U10' 是单元级；wrapper 级本刀只用 p5wrapper
  基线门 + 新臂行为证据）。

---

## 8. 复算入口

```bash
# 单元门全套 (U1..U12 + M1..M14)
cmd //c 'sim\p9_orphan\run_orphan_suite.bat'

# 单臂
cmd //c 'sim\p9_orphan\run_orphan_unit.bat rtl\app_ctrl.v 2 1 0 2 U2 PASS'

# 全链 (先构建, 再逐场景)
cmd //c 'sim\p9_orphan\build_p5_orphan_wrapper.bat 0'
cmd //c 'sim\p9_orphan\run_p5_orphan_scen.bat 0 2 PASS'
cmd //c 'sim\p9_orphan\build_p5_orphan_wrapper.bat 1'
cmd //c 'sim\p9_orphan\run_p5_orphan_scen.bat 1 5 PASS'
```
