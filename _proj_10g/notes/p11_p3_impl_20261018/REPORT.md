# P11 · P3 实施轮 REPORT — C4（甲·双栈 2×10G）

- 日期：2026-10-19（实施轮；设计件 = `_proj_10g/notes/p11_p3_dualstack_design_20261018/README_FOR_TL.md` v1.1，含 §13/§14）
- 仓库根 = `D:\repo\XCKU5PMini\udp_hls_10g`；HEAD = `90307cd1`（本轮**未写 git**，改动均由 TL 提交）
- 纪律：**只实施 + 门**。未跑 Vivado synth/impl、未建工程、未构建、未上板、未碰 QSPI/对端/`D:\repo\perfv`/license。
- 判据层口径：本件不下 PASS/FAIL 裁定；「未观测到」≠「不存在」。

---

## 0. 一句话

C4（甲·双栈：两套同模块快路径 + 单份双 IP HLS + 共享 96KB 信用池 + 共享 8 槽 retx + 慢路径 2:1 merge / 1:2 demux / cfg 1:2）**已实施**；新件单元门、8 连接 churn 门（四释放路径 + 负控）、C4 全链 elaboration、C4 wrapper 功能门（ch1 ARP/SYN 真实 HLS + 跨口隔离）与 HLS csim 三臂全部有读数。C1（单口/0x2A）与 C3（共享 10G/0x2D）既有门仍绿；32 门常驻矩阵见 §7（FROZEN 结果见 §7 末）。

---

## 1. 改动文件清单

### 1.1 新增（本轮）

RTL 新件（设计件 §2.4 列出的 5 件；**没有**任何 `_p3/_dual/_portN/_copy/_c4` 派生的模块文件）：
- `rtl/win_pool_mgr.v` —— 96KB 单共享信用池（8 槽 / 2 口 / port_cap / C18 原子 / 两个只读配额口 ×2）
- `rtl/retx_pool_shared.v` —— 8×`retx_ram #(.N(1))` + 只写属主 mux + `slot<8` 守卫 + owner mismatch/oor 计数
- `rtl/slow_merge2.v` —— 慢路径 2:1 帧级 RR merge（76 位 AXIS）
- `rtl/slow_demux2.v` —— 慢路径 1:2 帧级 demux（73 位 AXIS，帧首锁口）
- `rtl/slow_cfg_demux.v` —— HLS cfg 8 词记录 1:2 分流（ADD 按 w2 / DEL 按 slot_port / slot≥8 丢弃）

门（`_proj_10g/notes/p11_p3_impl_20261018/gates/`）：
- `sim/tb_win_pool_mgr.v` + `run_tb_win_pool_mgr.bat`（G-P3-1）
- `sim/mk_mut_wpm.py` + `run_negctl_wpm.bat`（G-P3-1 负控：c18/pcap/dup）
- `sim/tb_p3_churn.v` + `run_tb_p3_churn.bat`（G-P3-1b）
- `sim/mk_mut_churn.py` + `run_negctl_churn.bat`（G-P3-1b 负控：noevd/noto/nost/dup）
- `sim/tb_retx_pool_shared.v` + `run_tb_retx_pool_shared.bat`（G-P3-3）
- `sim/tb_slow_merge2.v` / `tb_slow_demux2.v` / `tb_slow_cfg_demux.v` + 各自的 `run_tb_*.bat`（G-P3-4）
- `sim/tb_p11_c4_wrap.v` + `run_tb_p11_c4_wrap.bat`（G-P3-6）
- `sim/run_elab_c4.bat`（G-P3-7 正控）
- `sim/run_cfg_gate_c4.bat` + `run_negctl_cfg_c4.bat`（G-P3-7 负控）
- `sim/p11c4_src.f`（文件集清单）+ `csim/run_csim_p3.bat`（G-P3-5）
- 矩阵清单：`sim/p4gates/p11wpm_src.f` / `p11retx_src.f` / `p11sm2_src.f` / `p11sd2_src.f` / `p11scd_src.f` / `p11churn_src.f` / `p11c4elab_src.f` / `p11c4w_src.f` / `p11cfggate_src.f` / `p11neg_src.f`

### 1.2 修改（本轮）

RTL：
- `rtl/app_ctrl.v`：`EXT_QUOTA`（默认 0）；两个只读配额口 + 事件口；统一释放 `o_quota_rel/o_quota_rel_slot`；**6 类写点旁路**（复位保持、ev_up、ev_down、to_fire、st_req_now、C15 关闭）；`pa_winq/pb_winq` 锁存；`ret_slot_q` 外部化。
- `rtl/retx_ram.v`：`N` 参数（16 默认 = 今天的 16×64KB；8 = 每口 8 槽退路；1 = 共享池每槽实例）；地址按 AW 截低位。
- `rtl/tcp_tx_frame.v`：`EXTERNAL_RETX`（默认 0）+ `RETX_N`（默认 16）+ `ext_retx_*` 端口；OVL/默认**两体都接**；`ring_d` 走外部/内部选择。
- `rtl/tcp_echo.v`：`D/AW` 参数（默认 8192/13）；`FQW`、`CQ_AW` 随深度（16384 ⇒ 7 位 / 128 深）；debug 指针宽度参数化。
- `hls/src/layer_tcp.cpp`：`tcp_adv_wnd_cur`（默认 0xC000）+ `tcp_adv_wnd_set`；`tcp_build_hdr(..., tcp_adv_wnd_cur, ...)`；4 处 DEL 传 `local_ip`；`cfg_write` 的 DEL 分支写 `w[2]=local_ip`。
- `hls/src/udp_echo.cpp`：新端口 `i_tcp_adv_wnd`（ap_none），每 pass 写入 `tcp_adv_wnd_set`。
- `hls/tb/udp_echo_tb.cpp`：兼容壳 adv_wnd 形参（默认 g_adv_wnd=0xC000）；新增 `test_p3_adv_wnd` / `test_p3_max8` / `test_p3_del_local_ip`（含 RST/ FIN 清理，保证 MAX=3 回归臂也过）。
- `hls/run_hls.tcl`：P3 网表 cflags 加 `-DMAX_TCP_CONN=8`（C1/C3 继续用归档网表）。
- `board/wrapper_p4.v`：
  - 四配置宏 `P11_CFG_C1..C4` + `P11_CFG_ENFORCE` + 11 个具名 elaboration 硬门（§2.1 矩阵）；
  - C4 合同常量：`P11_EXPECTED_CONNS=8`、`WIN_POOL_5=96KB`、`WQ_CAP_5=WIN_POOL/8`、`PORT_CAP_5=96KB`；
  - C4 分支：ch0/ch1 各自 `vlan_strip/rx_classify/tcp_rx/tcp_echo(128KB)/app_pattern/tcp_cam/tcb/tcp_tx_frame(EXTERNAL_RETX)/app_ctrl(EXT_QUOTA)`；**同模块二次例化**；
  - 共享件：`win_pool_mgr`、`retx_pool_shared`、`slow_merge2`、`slow_demux2`、`slow_cfg_demux` + 第二套 `slow_cfg_adp`；
  - 每口 UDP app 链（port1 全链：udp_split/app_udp_pattern/udp_tx_cfg/udp_tx_frame）；
  - TX 侧：C4 无 fast demux，每口生产者直连本口 arb（`u_tx_arb`/`u_tx_arb_p1` 的输入按宏分叉）；
  - `tcp_echo` 128KB（D=16384/AW=14）+ `app_rx_occ` 18→17 位饱和；`eco_dbg_occ` 宽度无关化；
  - W79（C4）= ch0 MAC 好帧（`ch0_stat_frames`），C3 保持历史口径（FIFO 接受帧）；
  - HLS `i_tcp_adv_wnd` 端口用构建开关 `P11_HLS_ADV_WND` 控制（归档旧网表无此端口）。
- `board/build_p7b_ku5p.tcl`：`verilog_define` 加 `P11_CFG_C3=1 P11_CFG_ENFORCE=1`（C4 构建改为 C4+P11_DUAL，见文件注释）。
- `sim/p4gates/run_matrix_p4dfix.bat`：24 → **32** 门（8 个新门入册）。
- `sim/p4gates/paths.txt`：FINGERPRINT_GLOBS 加 P3 gate 的 `run_*.bat` / `tb_*.v` / `*.py`。
- `_proj_10g/notes/p7b_biz_win/check_window.py`：W79（C4 语义）接受 `ch0_w79_frames` 或历史 `ch0_rx_frames` 两个源名（P3 语义变更的静态判据同步）。

---

## 2. 门读数（逐门）

### 2.1 G-P3-1 `win_pool_mgr`（矩阵 `p11_wpm`）
- 正控：`WIN_POOL_MGR TB PASS`（臂 A 基本授予/归还、B 8 槽 4+4 + C18 原子、C port_cap、D 同拍双口、E 重复 rel、F slot≥8）。
- 负控（`run_negctl_wpm.bat`）：3/3 变异件被拒（`WPM_NEGCTL_PASS`）：
  - `c18`（去掉旧配额先回池）→ 不变量红；
  - `pcap`（去掉 port_cap 夹紧）→ port_win≤port_cap 红；
  - `dup`（去掉 rel 时 winq==0 计数）→ 重复释放红。

### 2.2 G-P3-1b 8 连接 churn（矩阵 `p11_churn`）
- 真实 2×`app_ctrl(EXT_QUOTA=1)` + `win_pool_mgr` + 行为级 mini-TCB；逐拍不变量（Σwinq+pool / Σport_win==Σwinq / port_win≤port_cap，影子模型 + DUT 内部方程双核）。
- 覆盖：4+4 建连 → 池抽干；外部 DEL；关闭超时 `to_fire`；abort `st_req_now`；C18 同槽复用；孤儿回收 `orph_down_i`；每条非零配额恰好 1 次 `o_quota_rel`；`stat_rel_dup==0` / `stat_slot_oor==0` / `stat_grant_zero==0` / 池全额归还。
- 读数：`P3_CHURN TB PASS`。
- 负控（`run_negctl_churn.bat`）：4/4 被拒（`CHURN_NEGCTL_PASS`）：`noevd` / `noto` / `nost`（任一释放路径断开）与 `dup`（去掉 `winq!=0` 门 ⇒ 双还）。

### 2.3 G-P3-2 `app_ctrl EXT_QUOTA=0` 回归
- 既有门全绿（本轮重跑）：`P5 FC UNIT GATE PASS`（`sim/p5sim/run_tb_p5_fc.bat`）· `P5 FLOW OK`（`run_tb_p5_flow.bat`）· `P7B WU GATE PASS`（`sim/p5wu/run_tb_app_wu.bat`）。
- `EXT_QUOTA=1` 的只读配额/释放语义由 §2.2 churn 门覆盖。

### 2.4 G-P3-3 共享 retx（矩阵 `p11_retx_pool`）
- `RETX_POOL_SHARED TB PASS`：8 槽属主写/读回逐字、两口同拍不同槽、非属主访问被丢弃且数据不损坏（`stat_retx_owner_mismatch` +1）、slot≥8 丢弃（`stat_slot_oor` +1）、2 拍读延迟与 `retx_ram` 一致。

### 2.5 G-P3-4 慢 merge / slow demux / cfg demux（矩阵 3 门）
- `SLOW_MERGE2 TB PASS`：帧级 RR（初值 rr=0 ⇒ 首帧 p1）、帧内 id 连续（帧原子）、非选中口 tready=0、反压保持帧锁。
- `SLOW_DEMUX2 TB PASS`：按口分离、帧内 s_port 翻转仍整帧走锁存口（`stat_port_change`≥1）、tlast 随帧、无同拍双口 valid。
- `SLOW_CFG_DEMUX TB PASS`：ADD 按 w2 判口 + `slot_port` 更新；DEL 按 slot_port 路由；w2 不一致计数；slot≥8 整条丢弃；back-to-back DEL→ADD（DEL 旧口 / ADD 新口）；反压记录保持后完整播出。

### 2.6 G-P3-5 HLS csim
- 工具链 = MSVC（vcvars64，`/std:c++14`）。三臂（`csim/run_csim_p3.bat`）：
  - `MAX=8, DUAL=1`：`P11_SUMMARY passed=75 failed=3`（新用例全过；3 条失败 = **本轮前基线**，见下）
  - `MAX=3, DUAL=1`：`passed=72 failed=3`
  - `MAX=3, DUAL=0`：`passed=51 failed=3`
- 新用例：`P3 adv_wnd`（SYN-ACK 窗口 = 运行时 0x3000/0xC000 两臂）· `P3 MAX_TCP_CONN=8`（8 条不同四元组 SYN 全部 SYN-ACK + 8 条 ADD cfg 记录；第 9 条被拒）· `P3 DEL carries local_ip`（FIN/RST 的 DEL 记录 `w2 == IP_A/IP_B`）。
- 3 条基线失败 = `TCP SYN -> SYN-ACK`（旧用例目的端口 7，而 HLS 监听 8080）· `TCP echo multi-MSS`（recv_total=0）· `TCP echo 536B`；与 P2 轮 `gates/base_out.txt` 同一集合（**既有**，本轮未修）。

### 2.7 G-P3-6 C4 wrapper 全链（矩阵 `p11_c4_wrap`）
- `P11_C4_WRAP TB PASS`：
  - 臂 B：ch1 注入 ARP request（target IP_A）⇒ 回包只出现在 **ch1** TX（ARP opcode=2、SPA=IP_A）；**ch0 无该回包**（跨口隔离）。
  - 臂 D：ch1 注入 SYN（dst IP_A）⇒ **ch1** TX 出 SYN-ACK（proto=6、flags SYN|ACK、src IP=IP_A）。
  - 臂 A：ch0 注入 ARP target IP_B ⇒ **应答在 ch0**（ARP opcode=2、SPA=IP_B；ch1 无回包）。
    ⛔ **2026-10-19 订正（P3 修复轮 M-1）**：原文写"归档**单 IP** HLS 网表不应答（`reply idx=-1`）"**与归档日志相反** ——
    `logs/p11_c4_wrap_xsim_c4w.txt:39` 逐字 `reply idx=13`（P2 双 IP 网表本来就应答 IP_B）。旧门 arm A 只有
    `$display`、无 `chk`，所以该错误没被拦住。本轮已：① arm A 改为硬判据（idx>=0/opcode=2/SPA=IP_B）；
    ② 补 arm C（ch0 SYN/IP_B ⇒ SYN-ACK，源 IP=IP_B，ch1 无回包）；③ 门改用 **P3 归档网表 + `P11_HLS_ADV_WND`**
    （H-4，配对硬判）；④ 加 `Error:/Critical/Unisim` 硬门（`scan_xsim_errors.py --mode c4wrap`，唯一允许
    `u_slow_rx.u_ff` 的 RAMB36E2-11 bypass 碰撞）与 `P11_ACC_MARGIN_SELFCHK OK` 断言。读数见
    `p11_p3_fix_20261019/FIX_REPORT.md`。
- C1/C3 回归门仍绿（矩阵 `p5_wrapper` 与 `g6_p11_dual` 在本轮全矩阵里重跑，见 §7）。

### 2.8 G-P3-7 elaboration 组合（矩阵 `p11_c4_elab` + 负控驱动）
- 正控：`P11_C4_ELAB PASS`（C4 全宏集：P7B_10G/PCIE_OBS/DP_156MHZ/APP_MODE/P6B_SIM_CLKGEN/UDP_TX_OVL/TCP_TX_OVL/SFP2_MODE_A/DUAL_SFP_A/P11_DUAL/P11_CFG_C4/P11_CFG_ENFORCE；implicit/xvlog-ERROR 硬门 0）。
- 负控（`run_negctl_cfg_c4.bat`）：9/9 被拒（`CFG_NEGCTL_PASS`；⛔ **2026-10-19 P3 修复轮 M-10 追加 2 条 ⇒ 现 11/11**：`P11-noDual` / `P11-noSFP2A` 分别被 `P11_DUAL_REQUIRES_DUAL_SFP_A` / `P11_DUAL_REQUIRES_SFP2_MODE_A` 拒绝）：
  - 0-select → `P11_CFG_SELECT_ONE`
  - C1+DUAL → `P11_CFG_C1_CONFLICTS_SECOND_PORT`
  - C2 缺 MODE_B → `P11_CFG_C2_REQUIRES_MODE_B`
  - C2+DUAL → `P11_CFG_C2_CONFLICTS_DUAL_SFP_A`
  - C3 缺 DUAL → `P11_CFG_C3_REQUIRES_MODE_A_DUAL`
  - C4 缺 P11_DUAL → `P11_CFG_C4_REQUIRES_DUAL_SFP_A`
  - C4+MODE_B → 被**既有更宽门** `DUAL_SFP_A_AND_SFP2_MODE_B_CONFLICT` 预占（xvlog 硬失败；登记：`P11_CFG_C4_CONFLICTS_MODE_B` 模块存在但结构上被更早的门覆盖）
  - C3+C4 → `P11_CFG_SELECT_ONE`
  - P11_DUAL+MODE_B → `P11_DUAL_AND_SFP2_MODE_B_CONFLICT`

### 2.9 G-P3-8 矩阵/指纹
- 矩阵 24 → **32** 门（8 个新门入册，见 §7）；`paths.txt` 指纹 globs 已加 P3 gate 文件。
- 全矩阵结果：**32/32、0 failed、FROZEN**（382 文件逐字节相同；读数与两次跑的历史见 §7）。

---

## 3. 与设计件的偏差（如实）

1. **app_ctrl 配额读口：每口 2 个（不是 1 个）**。设计件 §4.3 给单读口 + ID mux；实装发现扫描拍（`fq_scan` 用 `scan_id`）与 ev_down/ev_up（另一槽）可同拍冲突，单口会把一个槽的配额当成另一个槽的扫描结果（redge 毒化）。拆成"扫描/init 口 + 事件口"；语义不变，只是读口加宽。
2. **win_pool_mgr 的 C18 语义 = 旧配额先回池、再算授予量**（`avail = pool + old - occ`）。设计件文字"`pool − g + old`"与"旧配额先归还再授新"在 `g` 是否看见 `old` 上有歧义；本实装取"先回池"（测试 B 的 C18 期望按此）。
3. **HLS `adv_wnd` 的机制 = 文件级寄存器**（顶层 `i_tcp_adv_wnd` 每 pass 写入 `tcp_adv_wnd_cur`），不是逐层形参。综合后函数全内联，语义等价；避免改 `tcp_send`/`tcp_rx_process` 的整条调用链。
4. **boot writer → 编译常量**：设计件允许"或直接接常量输入"。`wq_cap = WIN_POOL/EXPECTED_CONNS`、`port_cap = 96KB` 由 wrapper localparam 直接接 manager；没有 host 可见配额寄存器（P3 非目标）。
5. **`P11_CFG_SELECT_ONE` 的 0 选择在非 ENFORCE 模式 = legacy 推断配置**（C1/C3 回归与既有 TB/门不需要改宏）。板构建必须 `P11_CFG_ENFORCE=1`（`build_p7b_ku5p.tcl` 已按 C3 设置）；G-P3-7 的 0-select 负控在 ENFORCE 下跑。设计件 §2.1 字面"0 个 = 硬失败"在 ENFORCE 模式下逐字成立。
6. **`tcp_echo` 的 CQ/FQ 宽度随 D 参数化**（16384 字 ⇒ 7 位 / 128 深）。设计件只要求 D/AW；不加深会在 128KB 下出现 cq 溢出/fq 失配。
7. **C4 的慢 merge 位置 = 每口 `udp_split` 透传口之后**（不是 `rx_classify.slow` 直连）。因设计件同时要求每口独立 UDP app，`udp_split` 必须在 merge 之前；合流后的下游仍是单份 `slow_rx_adp`→HLS。
8. **C4 第二口 UDP app 全链已实现**（`u_udp_split2`/`u_app_udp2`/`u_udp_tx_cfg2`/`u_udp_tx2`），UDP app 参数 `DUAL_IP=0` + 本口 IP（设计 §3.5）。
9. **W79（C4）= ch0 MAC 好帧**（`ch0_stat_frames`，与 W0 同计数点）；C3 保持历史"FIFO 接受帧"口径。读侧标签需同步（本轮未改读侧脚本；构建/读侧轮处理）。
10. **`check_window.py` 的 W79 判据**由单一 `ch0_rx_frames` 改为接受两源名（C4 = `ch0_w79_frames` / C3 = `ch0_rx_frames`）；读侧标签仍待 C4 阶段同步。
11. **负控驱动未入册矩阵**：`run_negctl_{wpm,churn,cfg_c4}.bat` 为独立门（它们 `cd %~dp0` 编译，不满足矩阵私有 cwd 约定），与 P2 G3/G4 同款登记债；读数在 §2。
12. **`P11_CFG_C4_CONFLICTS_MODE_B` 被既有 `DUAL_SFP_A_AND_SFP2_MODE_B_CONFLICT` 预占**（更宽的同义门在 xvlog 先硬失败）；模块保留但结构上不可达。
13. **`tcp_tx_frame` 端口表新增 9 个 `ext_retx_*`**（默认配置无消费者，综合裁掉）；不属于"行为回归"承诺的 placed 网表逐位相同（源已改）。

### 3.1 防分叉 / 实例计数静态审计（`grep` 口径，非工具网表）

- `rtl/`/`hls/src/` 的产品模式宏命中 = **0**（`SFP2_MODE*`/`DUAL_SFP_A`/`P11_DUAL`/`P11_CFG_*`）。
- 新增 RTL 文件命名检查：`git ls-files rtl/` 命中 `(_p3|_dual|_port[12]|_copy|_c[1-4])` = 2，两者都是 **P9 既有件**（`aximm_c2h_win.v` / `axis_c2h_stream.v`，`c2h` 子串误命中），**不是 P3 派生**；P3 的 5 个新件 0 命中。
- wrapper 源文本实例计数（**跨所有 ifdef 分支**）：`tcp_rx`=2 / `tcp_echo`=2 / `tcb`=2 / `tcp_cam`=2 / `app_ctrl`=2 / `win_pool_mgr`=1 / `retx_pool_shared`=1 / `slow_merge2`=1 / `slow_demux2`=1 / `slow_cfg_demux`=1；`rx_merge2`=1 与 `tx_demux2`=3 均在 `ifdef DUAL_SFP_A` 的 **`ifndef P11_DUAL`** 支内 ⇒ **C4 elaboration 里不存在**（C3 支保留）。
- ⚠️ 这是**文本口径**，不是 xelab 网表实例计数；工具级实例门（`P11_INSTANCE_COUNT`）未实现（构建轮可用 `report_hierarchy` 补）。

---

## 4. 未测 / 未跑（如实）

1. **未跑 Vivado synth/impl/位流/时序/资源** —— 无 WNS/WHS/失败端点/BRAM/LUT/FF 读数；C4 时序风险仍按设计件 §8 的"一次构建 + backstop"处理。
2. **未跑 HLS csynth** —— P3 双 IP 网表（MAX=8 + `i_tcp_adv_wnd`）**不存在**；C4 wrapper 门用的是归档**单 IP** 网表 ⇒ 臂 A/C（IP_B 的 ARP/SYN 应答）**未测**，由构建轮 P3 网表补。
3. **C4 port1 功能路径只到"接线/elaboration"级**（ch0 ARP IP_B 无应答是单 IP 网表的预期）；ch0 的 TCP 数据面、8 连接 4+4/6+2/8+0 的板级分布、W83/W84/W0/W79/W4/W82 的运行时读数**未测**。
4. **共享池的板上行为**（零窗/合同违反/第 9 条被拒）**未测**（xsim churn 已覆盖语义）。
5. **C1/C3 的 P3 源回归重建**未做（C1/C3 用的是**既存宏组合**重跑既有门，不是新 BID 的重建位流）。
6. **慢 merge 的 TO_CYCLES 看门狗**在 C4 wrapper 里配了 4096，但双口半帧场景未在 TB 里构造。
7. **对端 2×9.5G 同时接收、多连接 app、板级 2×10G** 全部未测（属板级轮）。
8. **G-P3-2 的 `EXT_QUOTA=1` 覆盖率**：redge/wu/fc 复用逻辑在 churn TB 里只间接覆盖（有扫描/事件/超时/孤儿），未做逐字波形核对。

---

## 5. 关键实施细节（给构建/板级轮）

- **构建选择**：C4 = `P11_CFG_C4=1 P11_CFG_ENFORCE=1 P11_DUAL=1 SFP2_MODE_A=1 DUAL_SFP_A=1` + 0x2D 的 9 宏；C3 = `P11_CFG_C3=1 P11_CFG_ENFORCE=1` + 9 宏（已在 `build_p7b_ku5p.tcl`）；C1 = 无第二口宏（legacy 分支）。
- **HLS 网表**：C4 必须先用 P3 cflags 综合并定义 `P11_HLS_ADV_WND=1`（wrapper 才会接 `i_tcp_adv_wnd`）；C1/C3 继续归档网表（不定义该宏）。
- **合同常量**：默认 8×12KB；2×10G 演示构建改 `P11_EXPECTED_CONNS=2`（wq_cap=0xC000）。**一个 bitstream 一个合同**。
- **定向 STA**（设计件 §9.2）：`u_tcp_tx/u_fifo_b→u_tcb`（两套）、`u_app_ctrl/o_ev_up→orph`（两套）、`win_pool_mgr` 的 pool/winq 锥、retx owner mux、`u_hls/*`、慢 merge/demux、`slot_port` 写口。
- **W79 标签**：C4 读侧需改成 "port1/ch0 MAC RX 好帧"。

---

## 6. 关键文件路径

- 设计件：`_proj_10g/notes/p11_p3_dualstack_design_20261018/README_FOR_TL.md`
- 本报告：`_proj_10g/notes/p11_p3_impl_20261018/REPORT.md`
- 门：`_proj_10g/notes/p11_p3_impl_20261018/gates/`
- 矩阵：`sim/p4gates/run_matrix_p4dfix.bat`（32 门）/ 日志 `sim/p4sim/matrix_p4dfix.log`

---

## 7. 常驻矩阵（32 门）

**最终全矩阵（32 门，2026-10-19 01:27，私有 workdir `sim/p4gates/work_20261019_005516`）**：

- `gates run : 32 / 32` · `gates failed: 0`
- `VERDICT: FROZEN -- all 382 hashed files byte-identical across the run`
- `DIGEST_ALL(content) = e4367d759ed3739bd88161c91ad59c453db927eb544e2d7668e3915c7b282e6f`（382 文件）
- `DIGEST_COMPILE = 6cab8bb7d508be14acb114294fd5e2082f7390d8012fea92c9d4cec9a0406f38`（258 文件）
- `GIT_HEAD = 90307cd1`
- 日志：`sim/p4sim/matrix_p4dfix.log`；逐门 log 已按 `.txt` 归档到 `gates/logs/`。

历史（如实）：本报告轮内跑了两次全矩阵。**第一次 = 31/32**，唯一红 = `biz_win`：`check_window.py` 的 5c 判据仍钉历史 W79 源名 `ch0_rx_frames`，而 C4 引入了 `ch0_w79_frames`（P3 的 W79 语义变更，设计件 §7.1 已登记）。修正 = 判据接受两个源名（C4/C3），随后 `biz_win`/`p5_wrapper`/`g6_p11_dual` 单跑全绿；**第二次全矩阵 = 32/32 FROZEN**（上列读数）。
⛔ **2026-10-19 订正（P3 修复轮 M-11）**：原文"两次的 `DIGEST_ALL` 不同（第一次 `851d1343…`=修正前；第二次 `e4367d75…`=最终修订）"把**同一份最终修订的两个读数**误写成两次运行。事实 = `sim/p4sim/matrix_p4dfix.log` **存储**的 `DIGEST_ALL(content) = 851d1343…`（382 条记录对 HEAD 全一致：missing 0 / mismatch 0）；`e4367d75…` 是 `p4gate.py` 的 `compare` 子命令**按路径排序重算**得到的同一内容摘要（根路径正/反斜杠写法影响字符串，故与存储值不同）。⇒ 正确写法 = "存储 `851d1343`；compare 重算 `e4367d75`"，不是"两个修订"。`check_window.py` 的编辑只解释第一次→第二次**矩阵运行**的差异，与这两个摘要的关系无关。

逐门独有串（本轮）：`P11_C4_ELAB PASS` · `WIN_POOL_MGR TB PASS` · `RETX_POOL_SHARED TB PASS` · `SLOW_MERGE2 TB PASS` · `SLOW_DEMUX2 TB PASS` · `SLOW_CFG_DEMUX TB PASS` · `P3_CHURN TB PASS` · `P11_C4_WRAP TB PASS` · 既有 `P4 CHAIN OK` / `BURST OK` / `P5 WRAPPER OK` / `P7B WU GATE PASS` / `RX_MERGE2 TB PASS` / `SRCIP_GATE_PASS` / `P11_DUAL TB PASS` / `TB_BIZ_WIN_PASS` 等全绿。

