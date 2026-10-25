# P11 P3 · 0x2F 时序失败修复 + 0x30/0x31 构建报告

- 日期：2026-10-25（修复/0x30）→ 2026-10-26（0x31 clean 构建）
- 仓库根：`D:\repo\XCKU5PMini\udp_hls_10g`
- 开工 HEAD：`e4f4919d`（41 门矩阵重跑后的负控/变异件取证）
- 唯一构建入口：`P11_CFG=c4 P11_CFG_ENFORCE=1 P11_HLS_VARIANT=p3_dual_max8 cmd //c 'board\run_build_p7b_ku5p.bat'`
- 纪律：未烧板、未碰 QSPI、未写 `D:\repo\perfv`、未改 license；xsim 与 Vivado 未并行；构建期间未改源文件。
- 状态词：【已证·源码】【已证·仿真】【已证·构建】【已证·STA 定向】【推断】【未判定】【未测】
- ⛔ 本报告不写"时序已解决"之类措辞；0x31 的通过读数以构建门与 timing report 为准。

## 1. 结论（先读）

1. **0x2F 的 -6.456 ns 根因已修复**：`win_pool_mgr` 原先把 **rel0 → ev_up0 → ev_up1 → rel1**
   四个事件 + 8 槽 `winq` 数组下状态全部塞进一个组合块。定向 STA 首条路径 =
   `u_app_ctrl/c_rcv_nxt_reg[9][4]/C → u_win_pool/port_win1_reg[0]/D`，13.137 ns / 42 级；
   另测 **ev_up 自身路径仍有余量**（ev_up0 +0.323 / ev_up1 +0.201）。
   ⇒ 修法 = **事件 FIFO + 串行三拍事件机** + **grant-done 握手**（详见 §3）。
   synth 后定向 STA：`u_app_ctrl/c_rcv_nxt* → u_win_pool/evq_reg[5][0]/D` **+2.344 ns / 14 级**；
   ev_up0 **+2.902** / ev_up1 **+3.148**。**routed 后同族** = **+0.960 ns / 14 级**
   （`sta_0x31_tcb.txt`；synth 值只作预检，签核用 routed）。
2. **0x30 构建（manager 修好、未加策略）**：`WNS = -0.418 / TNS = -556.221 /
   setup 失败端点 3126 / 372,939`；hold/PW 0。失败族 = **既存** `u_tcp_tx/u_fifo_* → u_tcb/*`
   （0x2F 时该族定向 STA 为 **-3.772 / -3.788 / -3.797**（A/B/C）与 **-2.175**（D）——
   0x2F 的 top-10 全是 manager 链，把这一族盖住了）。0x30 位流被时序硬门**改名隔离**，
   未记录 sha，随后被下一次构建 `create_project -force` 清除。**禁烧。**
3. **RTL 侧"把 TCB 写口打一拍"的两次尝试均被 `txdrop50` 判死**（详见 §5）：
   - data/ctrl 延迟 + rew 旁路 ⇒ `MISMATCH 4380 B`（3 帧）；
   - 全部 tx 更新统一打一拍 ⇒ `MISMATCH 7300 B`（5 帧）。
   ⇒ **任何 TCB 写延迟都会破坏重传序列**；两版均已**回退**（`tcp_tx_frame.v` 回到 HEAD）。
4. **0x31 构建（`Performance_Explore` 策略）通过构建门**：
   **WNS +0.031 / WHS +0.010 / setup·hold·PW 失败端点 0/0/0**；
   `All user specified timing constraints are met.`；DRC 0 Error/Critical（85 条 Warning）。
   位流（clean 构建）sha256 **`420ddad5e7c018abefa9b3e1dea3942ab1d8ff0a6a24b8733f34fdb9fa8176b6`**，
   15,431,261 B，BID **0x31**。首版 0x31 构建（同一输入/策略）sha
   `4dce8d99570535ea039a0283a8d856a35f076318e670a277e9f078f1c498df1a` 与 clean 版
   **`cmp -l` 仅差 7 字节（全在 `.bit` 头时间戳区）** ⇒ **可编程镜像位级相同**。
5. **41 门矩阵 41/41 EXIT=0**（含 `txdrop50`、`p5_wrapper`、`p7b_chain`、`swc`、全部 P11 门与负控）。
6. **新增构建时序硬门 + 修掉两个门缺陷**（§4/§6）：
   - `P7B_TIMING_GATE = PASS` 要求 `WNS>0 ∧ setup/hold/PW 失败端点=0`，不满足则把位流
     改名 `*.TIMING_FAIL` 并 `P7B_VERDICT = TIMING_FAIL`。
   - 硬门的失败端点数解析改为 **Design Timing Summary 表**（旧版抓第一段 `Setup :`，
     0x30 实测第一段是子组 0、全局 3126 ⇒ 会假绿）。
   - DRC 文本门 `Opt 31-155` 会命中 `[Opt 31-1555] control_set_opt supports Versal devices only`
     ⇒ 六个 token 加 `]` 锚定，消除 0x31 的 DRC-KEY-FAIL 假阳性。

## 2. 0x2F 失败读数（基线）

| 项 | 读数 |
|---|---|
| WNS / TNS | **-6.456 / -55,816.719 ns** |
| setup 失败端点 | **25,697 / 371,939** |
| WHS / hold 失败 | +0.010 / 0 |
| WPWS / PW 失败 | 0.000 / 0 |
| 最差路径 | `u_app_ctrl/c_rcv_nxt_reg[9][4]/C → u_win_pool/port_win1_reg[0]/D`，13.137 ns（logic 4.788 / route 8.349），42 级（CARRY8=14, LUT6=16, MUXF7=3） |
| 位流 | `088948df…3a1f0`（15,431,261 B，**禁烧**，已归档） |

定向 STA（0x2F routed dcp，只读）另证：
- `u_slow_cfg/ev_up_reg/C → u_win_pool/*/D`：**+0.323 ns**（19 级）
- `u_slow_cfg2/ev_up_reg/C → u_win_pool/*/D`：**+0.201 ns**（9 级）
- `u_app_ctrl2/c_rcv_nxt* → u_win_pool/winq*`：**-0.579 ns**（10 级）
- 最差 40 条入 `u_win_pool/*/D` 全部来自 `u_app_ctrl/c_rcv_nxt*`（rel 路径）。

⇒ 结论：**要切的是 app_ctrl 扫描态 → rel → manager 算术这条组合链，不是整个池。**

## 3. 修法（RTL）

### 3.1 `rtl/win_pool_mgr.v`：事件 FIFO + 串行三拍事件机

- 事件编码：`bit0 = 1 ⇒ ev_up`，`bit1 = 口`；`00/01/10/11 = rel0/ev_up0/rel1/ev_up1`。
  （⚠️ 不能按 0/1/2/3 直排 rel0/evup0/evup1/rel1：`bit0/bit1` 语义会翻转；
  首版实现踩过，单测臂 B 立刻红。）
- **32 深 × 6 位事件 FIFO**，每拍最多 4 条 push（固定顺序 **rel0 → ev_up0 → ev_up1 → rel1**，
  与原组合块顺序逐位一致）；同口同槽 rel+ev_up 同拍仍由 C18 吸收（不单独入队）。
  ⚠️ **等价性边界（kimi L-6）**：`occ0/occ1` 在事件机的 `S_LOAD` 采样（比原组合块晚 1–2 拍）。
  occ 在 1–2 拍内变化时，授予量与旧式可能不同（≤几十 B；池/端口守恒不变量不受影响）。
  TB 的影子模型无 occ 项 ⇒ **occ≠0 的授予量路径零覆盖**；现有 churn/单元 TB 只用 occ=0。
  本轮不改（产品 8×12KB 合同留有 32KB 物理余量），下一轮补 occ 项的定向 TB。
- 事件机每条事件三拍：
  - `S_LOAD`：读 `pool/port_win/winq[slot]/grant_port[slot]/occ[port]` 并锁存；
  - `S_CALC`：`pool_after = pool + q`、`sat_sub` 扣旧配额、`avail/room`；
  - `S_COMMIT`：`g = min(wq_cap, avail, room)`，提交 `pool/winq/port_win/grant_port`，打 stat。
- **grant-done**：ev_up 提交沿的下一拍 `o_ev_up_doneN` 高，该拍 `winq[slot]` 已是新配额；
  `o_ev_up_done_slotN` 供 app_ctrl 校验队列头。
- FIFO 溢出：`stat_ev_ovf` 计数且整拍 push 不落地（保序）；服务率 1 条/3 拍，HLS 事件率远低于此。
- 槽号 ≥8：事件照常入/出 FIFO，只计 `stat_slot_oor`，不改状态；ev_up 仍产生 done
  （app_ctrl 读到 0 配额，与旧式一致）。
- 所有原有 stat/语义（C18 跨口、stale rel、dup rel、下溢、8+0/6+2 等）保留；
  旧 `win_pool_mgr` 的 6 个变异件（c18/pcap/dup/c18owner/stale/m5single）已按新结构迁移，
  负控仍全部被拒（§7）。

### 3.2 `rtl/app_ctrl.v`：init 等待队列（EXT_QUOTA=1 等 done）

- 旧实装 = `init_pend/init_slot` 单寄存器 + "ev_up 下一拍立即 init"。
  manager 事件机后授予在 ev_up 后 ~3 拍才落地 ⇒ 立即 init 会读到旧配额（通常 0）⇒ 零窗死锁。
- 新增 **4 深 init 队列**（`init_q/init_wr/init_rd/init_cnt`）：
  - `ev_up` 入队 `ev_slot`；`init_pop = init_valid && (EXT_QUOTA ? done && slot_match : 1)`；
  - `EXT_QUOTA=0`（C1/C3）时立即 pop ⇒ **逐拍退化为旧行为**（`init_pend/init_slot` 兼容
    wire 保留给旧 TB 的层次引用）；
  - `init_done_mismatch`/`stat_init_ovf` 计数（结构性应恒 0）。
- `rc_id`/`o_winq_rd_id` 用 `init_valid ? init_head : scan_id`；
  `scan_tick`/`to_fire`/`st_req_now` 用 `!init_valid`，与旧 `!init_pend` 语义一致。
- `o_ev_up` 仍在 ev_up 拍发出（不延迟），避免改变 app 事件次序；init/redge 在 done 拍落地。

### 3.3 `board/wrapper_p4.v`

- C4 下 `u_win_pool` 的 `o_ev_up_done0/1`、`o_ev_up_done_slot0/1` 接到
  `u_app_ctrl`/`u_app_ctrl2` 的新输入；非 C4 分支用常数 0（`EXT_QUOTA=0` 屏蔽）。
- `BUILD_ID_V = 0x31`。

### 3.4 语义边界（新登记；未在板级观测到）

- **配额释放窗口**：`app_ctrl.o_quota_rel` 仍以 `winq_q_evd != 0` 为门。若**同一槽**在 ev_up 后
  ~3 拍内就收到 ev_down/超时/abort，此时 manager 尚未提交授予，rel 不会生成，配额留死连接。
  对 HLS 事件源**结构性不可达**（ADD→DEL 至少隔一个握手 RTT，远大于 3 拍 = 19 ns；
  timeout/abort 只针对已建立的连接）。**未做 `up_pend` 位图守卫**；若未来 app 可立即 abort，
  下一轮应加（ev_up 置位、done 清零、rel 门并上 `up_pend`）。
- FIFO 溢出/init 队列溢出/done 错配均有计数，结构性不应发生；TB 断言 0。

## 4. 0x30 构建与两个门缺陷

### 4.1 构建读数

| 项 | 0x30 |
|---|---|
| WNS / TNS | **-0.418 / -556.221 ns** |
| setup 失败端点 | **3126 / 372,939** |
| hold / PW 失败 | 0 / 0 |
| 最差路径 | `u_tcp_tx/u_fifo_a/rptr_reg[0]/C → u_tcb/rcv_wnd_r_reg[3][14]/CE`，6.701 ns（logic 1.957 / route 4.744），16 级 |
| 位流 | 被时序硬门改名 `wrapper_p4.bit.TIMING_FAIL`；**未记录 sha**；下一次构建已清除 |

### 4.2 时序硬门（新增，0x30 起生效）

`board/build_p7b_ku5p.tcl` 在 `report_timing_summary` 后：
- 从 **Design Timing Summary 表**读全局 `WNS / TNS / setup 失败端点 / WHS / hold / WPWS / PW`；
- 要求 **WNS>0 且 setup/hold/PW 失败端点全 0**；
- 不满足：位流改名 `*.TIMING_FAIL`、打印 `P7B_BIT_QUARANTINED`、`P7B_VERDICT = TIMING_FAIL`、exit 1；
- bat 把 `TIMING_FAIL` 加入 tripwire；`P7B-VERDICT = OK` 缺失时也会 `BUILD-GATE-FAIL`。

⚠️ **首版硬门解析有缺陷**：抓了报告里**第一段** `Setup :`（某个子 clock group，0 失败），
而全局失败在 Design Timing Summary 表（0x30 实测 3126）。虽然该次仍因 `WNS=-0.418` 判失败，
但端点数会假绿。**已改为解析表格行**（本报告 §1.6；用 0x30 报告复核输出
`-0.418 / -556.221 / 3126 / 372939 / 0.010 / 0 / 0`）。

### 4.3 DRC 文本门假阳性（0x31 首版）

`Performance_Explore` 的 opt 日志出现
`INFO: [Opt 31-1555] control_set_opt supports Versal devices only`；
bat 的裸 token `Opt 31-155` 前缀命中它 ⇒ `DRC-KEY-FAIL`，尽管 **DRC 报告 0 Error/0 Critical**。
修法：`NSTD-1`/`UCIO-1`/`AVAL-326`/`Opt 31-155`/`Opt 31-67`/`Route 35-7` 六个 token
加 `]` 锚定（真实告警形如 `[Opt 31-155]`；`[Opt 31-1555]` 不含 `155]`）。
clean 构建已用此门通过。

## 5. TCB 族：0x2F → 0x30 → RTL 尝试（否定结果，必须登记）

### 5.1 定向 STA（从归档 routed dcp 只读查询；**工具原件** = `sta_0x2F_tcb.txt` / `sta_0x31_tcb.txt`）

> ⚠️ **证据留存订正（kimi M-1/M-2）**：0x2F 的 A–F 六族与 0x31 的 A–F 六族现由
> `board/p11_sta_tcb_probe.tcl` 在 routed DCP 上重跑并落盘（脚本可复跑、带阈值退出码）。
> 0x30 的原始 timing report **未归档**（被时序门改名后又被下一次构建清除）；表中 0x30
> 只有 A 的 -0.418 是当时读到的，其余格 **无原件 ⇒ 记"—"**。归档块已修（见 §10）。

| 族 | 0x2F slack（级） | 0x30 slack | 0x31 slack（级） |
|---|---|---|---|
| A `u_tcp_tx/u_fifo_a/rptr → u_tcb/rcv_wnd_r/CE` | **-3.772**（20） | **-0.418**（16） | **+0.219**（18） |
| B `u_tcp_tx/u_fifo_b/wptr → u_tcb/snd_nxt_r/CE` | **-3.788**（21） | — | **+0.295**（19） |
| C `u_tcp_tx/u_fifo_b/rptr → u_tcb/snd_una_r/CE` | **-3.797**（21） | — | **+0.134**（19） |
| D `u_tcp_tx/u_ackq/rptr → u_tcb/rcv_wnd_r/CE` | **-2.175**（16） | — | **+0.295**（15） |
| E `u_tcp_tx/u_fifo_b/wptr → u_tcb/snd_wnd_r/CE` | **-3.857**（21） | — | **+0.101**（19） |
| F `u_tcp_tx/u_fifo_b/rptr → u_tcb/snd_wnd_r/CE` | **-3.782**（21） | — | **+0.031**（19） |

⇒ 0x2F 该族**最差 = E −3.857**；0x31 最差 = **F +0.031**（= 全局 WNS 宿主，逐字对上）。
⇒ 0x2F 的 25,697 失败端点里 **包含了这一既存族**（top-10 被 manager 盖住）；
manager 修好后它**显形为 -0.418**。这不是 manager 修复引入的回归，是 **C4 双快路径的同域**问题
（设计件 §12 已预登记：0x2D 余量 0.66%，双栈同域 +~30k LUT，这两族各出现第二份）。

### 5.2 两次 RTL 尝试（均失败，已回退）

1. **data/ctrl 延迟 1 拍 + rew 旁路**（skid + 1 项 pending）：
   `txdrop50` ⇒ `MISMATCH 期望末字节 305707533 != 305711913`（差 **4380 B = 3×1460**），
   `burst sent=200 conn0 echoes=206 conn1 echoes=1 RETX=1`，`BURST FAIL`。
   —— data 写被延后而 rew 直通 ⇒ **同一 sel=1 的 snd_nxt 写序反转**（pending data 覆盖 rewind）。
2. **全部 tx 更新（data/ctrl/rew）统一打 1 拍**：`txdrop50` ⇒ `MISMATCH 305704613 !=
   305711913`（差 **7300 B = 5×1460**），`echoes=201`，`BURST FAIL`。
   —— 即使顺序保持一致，**TCB 写相位晚 1 拍**本身就会让 retx 判据读到旧 `snd_nxt` ⇒ 丢帧。

⇒ **结论（已证·仿真）**：`tcp_tx_frame` 的 TCB 更新写口**不能延后**；要切这条组合链必须
在不改变写拍的前提下做结构等价化简（未找到），或改 floorplan/策略。两版 RTL 均已
`git checkout -- rtl/tcp_tx_frame.v` 回退；最终树里该文件 = HEAD。

## 6. 0x31 构建（策略 = `Performance_Explore`）

### 6.1 读数（clean 构建）

| 项 | 0x31 |
|---|---|
| 策略 | `Performance_Explore`（place `Explore` / phys_opt `Explore` / route `Explore`） |
| WNS / TNS | **+0.031 / 0.000 ns** |
| setup 失败端点 | **0 / 372,921** |
| WHS / hold 失败 | **+0.010 / 0** |
| WPWS / PW 失败 | 0.000 / 0 |
| 时序判 | `All user specified timing constraints are met.`；`Slack (VIOLATED)` **0 行** |
| WNS 宿主 | `u_tcp_tx/u_fifo_b/rptr_reg[0]/C → u_tcb/snd_wnd_r_reg[6][5]/CE`，6.131 ns（logic 1.636 / route 4.495），19 级 |
| WHS 宿主 | `u_mac_rx_ch0/push_keep_reg[0]/C → u_mac_rx_ch0/u_fifo/mem_*`，+0.010（rxoutclk 域） |
| 位流 | `420ddad5e7c018abefa9b3e1dea3942ab1d8ff0a6a24b8733f34fdb9fa8176b6`，15,431,261 B |
| DRC | 85 条 Warning / **0 Error / 0 Critical** |
| 门 | `P7B_TIMING_GATE = PASS`、`P7B_VERDICT = OK`、`BITSTREAM-OK`、bat exit 0 |

### 6.2 资源（placed）

| 资源 | 0x31 | 0x2F（对照） |
|---|---|---|
| CLB LUT | **122,058 (56.26%)** | 122,366 (56.40%) |
| CLB FF | **98,472 (22.69%)** | 98,160 (22.62%) |
| BRAM Tile | **109 (22.71%)** | 109 |
| URAM | **17 (26.56%)** | 17 |
| DSP | 4 | 4 |

- 与 0x2F 的 placed 资源几乎相同（manager 重写省下的 LUT 被 `phys_opt` 的复制/实现映射吃掉）；
  **设计纸面的 BRAM 267/395、URAM=1 不成立**，资源账按本表订正。
- synth 资源（未 placed）为 LUT **106,947** / FF 76,766 / BRAM 73 / URAM 17；**不能当 placed 账**
  （首版报告写 106,926，差 21；以盘上 `wrapper_p4_utilization_synth.rpt` 的 106,947 为准）。

### 6.3 可复现性

- 同输入、同策略的两次 0x31 构建（首版 `4dce8d99…`、clean `420ddad5…`）：
  `cmp -l` **仅 7 字节不同**（偏移 111–123，全在 `.bit` 头 ASCII 时间戳区），
  文件大小相同 15,431,261 B，WNS/WHS/端点读数逐字相同 ⇒ **可编程镜像位级相同**。
- 结论：`Performance_Explore` 在本轮同输入下**可复现**；sha 差异来自头时间戳，引用时应同时给
  `SW_CRC`/`cmp -l` 口径（工程既有 #63 纪律）。

## 7. 门与回归

- **41 门矩阵：41/41 EXIT=0**（`sim/p4gates/run_matrix_p4dfix.bat`，日志
  `gates/matrix_final.log`）。包含：
  - `chain / burst200 / trunc50 / trunc100 / halfdrop / txdrop50 / gate4096 / dupstorm /
    pcackoob / vlanchain / vlanburst / stallgate`
  - `unit_retx / unit_fifo / unit_vlan / unit_uart / p5_wrapper / f3_resync / swc / p7b_chain /
    biz_win / g2_rx_merge2 / g5_tcp_srcip / g6_p11_dual`
  - P11：`p11_c4_elab / p11_wpm / p11_retx_pool / p11_slow_merge2 / p11_slow_demux2 /
    p11_slow_cfg_demux / p11_churn / p11_c4_wrap / p11_negctl_wpm / p11_negctl_churn /
    p11_negctl_cfg / p11_negctl_slow / p11_negctl_p3fix / p11_static / p11_accmargin /
    p11_buildcfg / p11_ext0`
- P11 负控：`c18 / pcap / dup / c18owner / stale / m5single` 全部被拒（`p11_negctl_wpm` +
  `p11_negctl_churn`）；`p11_negctl_p3fix` / `p11_negctl_cfg` / `p11_negctl_slow` 全绿。
- EXT_QUOTA=0 回归：`p11_ext0`（`tb_p5_fc` / `tb_p5_flow` / `tb_app_wu`）全绿
  ⇒ app_ctrl 的 init 队列在非 C4 配置下**逐拍退化**，未见回归。
- 0x30 的时序硬门拦截了 -0.418 位流；0x31 clean 构建 `BITSTREAM-OK`。

## 8. 未收口 / 边界（不许当已答）

1. **板级未做**：本轮未烧板、未碰 QSPI；板仍为 0x2D/厂商态（视上次开机状态），
   0x31 位流在 `bits/wrapper_p4_0x31.bit`（及 archive `20261025_221252` 的 preclean 版）。
   下一轮需重烧、身份门（BID `0x31`）、read-side 同步、2×10G/8 连接 app。
2. **TCB 族余量 +0.031（0.48%）**：与 0x2D 的 +0.042（0.66%）同量级；**策略敏感**。
   manager 修的确定性收益 = 族从 -3.77 → -0.418；最后 0.418 由策略补上。
   后续任何 RTL 改动必须**先跑定向 STA**（`u_tcp_tx/u_fifo_* → u_tcb/*`）再构建。
3. **`up_pend` 边界**（§3.4）：未做；对 HLS 事件源结构性不可达，未观测到；未来 app 可立即
   abort 时需补。**kimi M-5 同族**：init 队列若因 FIFO 溢出丢一条 ev_up，其 done 永不来
   ⇒ init 队头永久阻塞（后续 init 静默丢弃，无看门狗）。可达性低（事件率余量 ≥6 拍），
   但**下一轮 RTL 必须加 init timeout/看门狗**（超时 pop + 计数），与 `up_pend` 同轮。
4. **0x30 位流无 sha**：被硬门改名后又被下一次 `create_project -force` 清除；只有
   timing/门读数（§4）。**禁烧**（已不存在）。
5. **资源账**：BRAM 109 / URAM 17 / LUT 122,058 / FF 98,472；设计纸面 267/1 不成立。
6. **读侧/合同/遗留**：read-side 仍默认 0x2D（需 `--bid 0x31` 阶段）；8×12KB 合同（0x32?）
   需要多连接 app；M-7/M-13、L-2..L-13、`stat_ev_ovf`/`stat_init_*` 未进快照；
   0x31 的 BID 快照几何/未实现地址按读侧工具现读。
7. **策略复核**：`Performance_Explore` 的 +0.031 是**本轮构建门读数**，不是"时序已解决"；
   若后续构建输入变化，需重跑并保留 `Slack (VIOLATED)` 0 行的证据。

## 9. kimi 审查回灌（2026-10-26；`%TEMP%/bridge/xr10/REVIEW_0X2F_0X31.md`）

**总评：无高档；中 5 / 低 10；主等价性论证成立；主要短板 = 证据留存纪律。** 处置如下：

| # | 发现 | 本轮处置 |
|---|---|---|
| M-1 | 0x30 细读数无物证 | 归档块改为**无位流也归档 reports**（`ARCHIVE_REPORTS_ONLY`；下一次被门拦截的构建不会再丢 report）。0x30 原始 report 已被 `create_project -force` 清除、**不可恢复**；§4 的 3126/TNS 标注为"当时读到的自述"，新工具原件见 `sta_0x2F_tcb.txt`（0x2F）/`sta_0x31_tcb.txt`（0x31）。 |
| M-2 | TCB 5 条 + 0x2F dcp 查询无工具输出 | 新增 `board/p11_sta_tcb_probe.tcl`（A–F 六族 + manager 3 条，带阈值退出码）；在 0x2F 归档 routed DCP 与 0x31 clean routed DCP 上重跑，输出入库 `sta_0x2F_tcb.txt` / `sta_0x31_tcb.txt`。0x2F 实测 A–F = −3.772/−3.788/−3.797/−2.175/−3.857/−3.782，**min = E −3.857**；0x31 = +0.219/+0.295/+0.134/+0.295/+0.101/**+0.031**。 |
| M-3 | TCB 族定向 STA 未编码进 tcl、无 exit | `build_p7b_ku5p.tcl` 增 **post-route `P11_STA_TCB_GATE`**：A–F 六族，任一族 `< P11_STA_MIN_NS`（默认 0.0）或 pin 缺失 ⇒ `STA_FAMILY_FAIL` + 位流改名隔离。0x31 clean DCP 上实测 `P11_STA_TCB_MIN = +0.031` ⇒ PASS（下一构建起门生效）。 |
| M-4 | §3.4 "TB 断言 0"不实 | `tb_p3_churn` 接出 `stat_init_ovf/stat_init_mismatch` 并断言 0（`p11_churn` 重跑 PASS）；wrapper 侧仍只到 wire/未进快照（**无新观测字**，登记为下一构建可选项）。 |
| M-5 | init 队头阻塞无兜底 | **下一轮 RTL**（与 `up_pend` 同轮）：init 队列 timeout/看门狗（超时 pop + 计数）；当前 0x31 位流**不含**，报告 §8 已登记。 |

低项处置：
- §1.6 "四个 token" → **六个**（已改）；synth LUT 106,926 → **106,947**（已改，盘上 rpt 为准）。
- `board/p7b_ku5p_*.rpt` 的 HEAD 旧版：本轮把 **0x31 clean 报告**显式入库（`board/` 与 `build0x31_clean/` 逐字节同）；"board/ = 最近构建"从此成立。
- 台账 §10-160/队列行补提交 hash；`p11_ext0` 三臂原始日志在 `p11_p3_fix_20261019/gates/logs/h5_*`（矩阵日志只留汇总）。
- `occ` 采样漂移边界（§3.1 已加）；时序门 WNS 改用 Design Timing Summary 表值（§4.2 已改）；tcl 注释嵌数字/TB 五缺口 = **登记不逼修**。

## 10. 证据地图

| 件 | 路径 |
|---|---|
| 0x2F 原始报告 | `../p11_build_0x2F_20261019/`（README/BUILD_STDOUT/timing/util/drc/BIT_SHA256） |
| 0x30 构建日志 | `build0x30/p11_build_0x30_full.log` |
| 0x31 clean 报告 | `build0x31_clean/p7b_ku5p_{timing,util,drc,clkinteract}.rpt` + `p7b_ku5p_stdout.txt` |
| 0x31 clean 构建日志 | `build0x31_clean/p11_build_0x31_clean.log` |
| 0x31 位流 + SHA + cmp | `bits/wrapper_p4_0x31.bit`（clean）· `bits/wrapper_p4_0x31_preclean.bit` · `bits/SHA256.txt` |
| 41 门矩阵 | `gates/matrix_final.log` |
| TCB 族定向 STA（0x2F） | `sta_0x2F_tcb.txt`（probe 在归档 routed DCP 上重跑） |
| TCB 族定向 STA（0x31） | `sta_0x31_tcb.txt`（probe 在 clean routed DCP 上重跑；`TCB_MIN=+0.031` PASS） |
| 定向 STA 工具 | `board/p11_sta_tcb_probe.tcl`（A–F + manager 3 条，阈值 `P11_STA_MIN_NS`） |
| 本报告 | `README_FOR_TL.md` |
| 台账 | `../P7B_TL_LEDGER_20261010.md` §10（本轮） |
| 审查队列 | `../P11_REVIEW_QUEUE.md`（本轮行） |
