# P11（双 SFP+）· P2-甲 实施轮 —— REPORT

> **TL 代落（2026-10-18 10:1x）**：本件 = P2-甲实施 agent 的完整报告原文（平台拒写 `.md`），由 TL 转录落盘；未改结论。TL 抽核见文末 §TL 抽核。
>
> 权威设计件 = `_proj_10g/notes/p11_p2a_design_20261018/DESIGN_v2r1.md`（920 行）。以下只记录实施内容与读数；门/脚本的 PASS 字样是它们自身的输出，不做额外裁定。

## 0. 一句话

A/B/C 三块按设计件实施完毕；可跑的仿真门全部跑过（HLS csim 三臂、xsim G2–G6、elab 12 组合、24 门常驻矩阵）。**未跑 Vivado 构建/综合/实现、未上板、未碰 QSPI**。门抓出并修掉两处实施缺陷（`slow_tx_adp.stat_side_ovf` 结构性恒 0、`wrapper_p4.u_demux_tcp` 接错生产者输入网 `txin_*`），另修掉 `tb_p7b_chain.v` 自身缺分号。

## 1. 改动文件清单

### 1.1 新增文件（`git status --porcelain` 的 `??`，限本轮件）

- `rtl/rx_merge2.v`
- `rtl/tx_demux2.v`
- `rtl/maccnt_sync.v`
- `sim/p4gates/p11merge_src.f`
- `sim/p4gates/p11srcip_src.f`
- `sim/p4gates/p11dual_src.f`
- `_proj_10g/p11_dual/sim/tb_rx_merge2.v` + `run_tb_rx_merge2.bat`（G2）
- `_proj_10g/p11_dual/sim/tb_tcp_tx_srcip.v` + `run_tb_tcp_tx_srcip.bat` + `mk_mut_srcip.py`（G5）
- `_proj_10g/p11_dual/sim/tb_tx_split.v` + `run_tb_tx_split.bat`（G3，独立门）
- `_proj_10g/p11_dual/sim/tb_slow_tx_port.v` + `run_tb_slow_tx_port.bat`（G4，独立门）
- `_proj_10g/p11_dual/sim/tb_p11_dual.v` + `run_tb_p11_dual.bat`（G6）

工作产物（未清理/未入库）：`_proj_10g/p11_dual/sim/work/`、`mut/`、各 `xsim*.log`、`*.wdb`、`xsim.dir.stale_20261018/`、`sim/p4gates/matrix_run_now*.log`、`elab_gate_out.txt` 等。**本轮已把关键门日志复制到 `gates/` 存档（原始 log 被 `.gitignore:62 *.log` 忽略）。**

### 1.2 修改文件（`git status --porcelain` 的 `M`，本轮相关）

HLS：`hls/src/eth_types.h`、`layer_ip.cpp`、`layer_arp.cpp`、`layer_icmp.cpp`、`layer_igmp.cpp`、`layer_tcp.cpp`、`layer_udp.cpp`、`udp_echo.cpp`、`hls/tb/udp_echo_tb.cpp`、`hls/run_hls.tcl`。

RTL/顶层/构建：`rtl/tcp_tx_frame.v`、`rtl/udp_rx.v`、`rtl/udp_split.v`、`rtl/udp_tx_cfg.v`、`rtl/slow_tx_adp.v`、`board/wrapper_p4.v`、`board/build_p7b_ku5p.tcl`（未执行）。

TB 接线：`tb/tb_integ_app_tx.v`、`tb_p4_chain.v`、`tb_p5_adv.v`、`tb_p5_app.v`、`tb_p5_multi.v`、`tb_tcp_chain.v`、`tb_tcp_echo.v`、`tb_tcp_tx.v`、`tb_tcp_tx_dbg.v`、`tb_tcp_tx_ovl.v`（`cam_rd_dip=32'h0`/`cam_rd_port=1'b0`）；`tb/tb_app_udp.v`、`tb_app_udp_rate.v`（`peer_my_ip=32'h0`）。

门/脚本：`sim/p4gates/run_matrix_p4dfix.bat`（21→24）、`sim/p4gates/paths.txt`（FINGERPRINT_GLOBS）、`_proj_10g/p7b_chain/sim/tb_p7b_chain.v`、`run_elab_4combo.bat`（12 组合 + STRICT 计数改 Python）、`elab_files.f`；读侧链式同步：`p7b_biz_win/check_window.py`、`tb_biz_win.v`、`run_tb_biz_win.bat`、`run_xvlog_wrapper.bat`，`_proj_pcie/p6e_snap_check.sh`、`p7b_biz/p7b_snap.sh`、`p7b_gate4_negctrl.sh`，`j6_r6fix.sh`、`tcpreg_j6.sh`，`sim/p6e_pcie/tb_p6e_pcie_wrapper.v`、`tb_p6e_pcie_counters.v`，`run_xvlog_wrapper63.bat`，`apply_readside_bid1c.py`（0x2C 阶段）；`sim/p4sim/matrix_p4dfix.log`。

## 2. Scope A（HLS）读数

工具链：MSVC `cl.exe`（vcvars64 + `/utf-8`）。

| 臂 | 定义 | 结果串 | 时刻 |
|---|---|---|---|
| DUAL=0 | `-DBOARD_IP_DUAL=0` | `P11_SUMMARY passed=46 failed=3` | 2026-10-18 07:16:29 |
| DUAL=1 | `-DBOARD_IP_DUAL=1` | `P11_SUMMARY passed=62 failed=3` | 2026-10-18 07:16:29 |
| DUAL=1 + ACTIVE/RTO 探针 | `+ -DACTIVE_CONNECT -DTCP_STATE_PROBE` | `P11_SUMMARY passed=68 failed=3` | 2026-10-18 07:16:58 |

单 IP 回复字节等价（两二进制逐字相同）：`P11SIG ARP len=72 crc=485D91B0` / `ICMP len=72 crc=80B098A3` / `UDP len=72 crc=7C5314F3` / `SYNACK len=72 crc=035027A9`。

3 条失败 = **本轮前基线失败**（三臂同一集合）：`TCP SYN -> SYN-ACK FAIL: got SYN-ACK`；`TCP echo multi-MSS FAIL: all 2000 echo bytes received`（`recv_total=0`）；`TCP echo 536B FAIL: got SYN-ACK`。疑似老测试目的端口与 `TCP_PORT_ECHO=8080` 不一致（未修，只登记）。**基线见证 = `gates/base_out.txt`（mtime 07:12:27，早于 d0/d1 的 07:16:29；同一 3 条失败、无 P11 用例）**。

P11 测试函数：`test_p11_ipb_arp_icmp_udp`/`test_p11_broadcast_src`/`test_p11_tcp_dual`/`test_p11_ip_a_signature`/`test_p11_rst_released_slot`。**TB 内 `TEST()` 现读 23 条；设计件提到的“19”与当前文件不一致**（如实登记）。

## 3. Scope B（RTL/wrapper/构建）

按设计落地（摘要）：`rx_merge2`（帧级互斥、工作保持 RR、`STRICT` 负控口、每帧末 1 拍重仲裁）；`tx_demux2`（帧首锁存口、帧原子、`stat_port_change`）；`maccnt_sync`（4 相 toggle/ack、无裸 2FF 多比特）；`tcp_tx_frame`（`cam_rd_dip/cam_rd_port/o_port`、`PER_CONN_SRC_IP`、N-6 控制帧校验和源 IP、lip/port 锁存）；`udp_rx/udp_split`（`DUAL_IP/IP_B/meta_dst_ip`）；`udp_tx_cfg`（`PER_CONN_SRC_IP/IP_B/peer_my_ip/o_port`、M-11）；`slow_tx_adp`（`PER_PORT/IP_B/SIDE_DEPTH=128`、源 IP/ARP SPA、`vlan_seen`、side FIFO）；读侧几何 `SNAP_NW_P6E=88`、`SNAP_P7BDP_NW=44`、MIR `0x180..0x18C`、`BUILD_ID_V=0x2C`、未实现 `0x190`。

计数器口径（纸面）：W83=ch1 TX 帧数；W84=ch0 TX 帧数；W85=classify fast+slow 总帧（33 位和截 32）；W86=`{sat16(ch0 RX ovf),sat16(ch0 TX ovf)}`；W87=`{sat16(ch0 MAC TX abort),sat16(ch0 MAC TX frames)}`；非 DUAL 构建 W83/W84/W86/W87=0、W85 仍真。

**门抓出的实施缺陷**：
1. `slow_tx_adp.stat_side_ovf` 结构性恒 0：`if (side_do_push) ... if (side_full) ++`，而 `side_do_push = commit_pulse && !side_full`；改为 `if (commit_pulse && side_full) ++`。
2. `wrapper_p4.u_demux_tcp` 接 `txin_*`（app→tcp_tx_frame 的 AXIS 输入）而非 `tx_*`（tcp_tx_frame 输出）；修复后 G6 B1/B3/W84 全过。
3. `tb_p7b_chain.v` 的 `chk(...)` 缺分号（矩阵首跑红）；已补。
4. `run_elab_4combo.bat` 的 STRICT 计数管道在本机挂起；改 Python（`count_0=1 count_1=0`）。

## 4. Scope C（门）读数

- **G8 csim**：见 §2。
- **G2**（矩阵行 `g2_rx_merge2`）：`RX_MERGE2 TB PASS`；臂 A 单口工作保持 / B 双口逐帧 RR / C 随机反压原子性 / D 复位 / E STRICT=1 负控（p1 持帧 + tready=0 ≥24 拍、p0 溢出）/ F STRICT 正臂。矩阵 `EXIT=0`。
- **G3**（独立门）：`TX_SPLIT TB PASS` → `TX_SPLIT_GATE_PASS`，`gates/xsim_split.log` mtime 2026-10-18 08:26:20。A 端口分离 / B 帧内 `s_port` 翻转仍整帧走锁存口（`stat_pc=2`，n0=4/n1=0）/ C 两级 arb TCP>UDP>HLS / D 交叉接线判据。未注册进矩阵（M-5 登记债）。
- **G4**（独立门）：`SLOW_TX_PORT TB PASS` → `SLOW_TX_PORT_GATE_PASS`，`gates/xsim_slowport.log` mtime 08:27:06。A IPv4 源 IP、B ARP SPA、C 未识别/短帧、D VLAN sticky（L-10）、E 错误偏移、F H-3 长阻塞（SIDE_DEPTH=128 不溢出、放行逐帧正确）、G SIDE_DEPTH=16 溢出负控（首次跑红抓出 §3-1）。未注册进矩阵。
- **G5**（矩阵行 `g5_tcp_srcip`）：`SRCIP_GATE_PASS`，三臂 `SRCIP ovl OK` / `SRCIP def OK` / `SRCIP mut EXPECTED-FAIL OK`（`gates/xsim_{ovl,def,mut}.log` mtime 08:24:55/08:24:59/08:25:03）。覆盖数据帧源 IP/端口位（IP_B/IP_A）、SYN-ACK 源 IP（N-6：上一帧 IP_A 锁存后控制帧仍用 IP_B）、重放帧源 IP、M-12 反压期 `o_port` 稳定；变异件必红。**判决用 TB 终止行，不用 xsim 退出码**（实测 xsim.bat 在 TB PASS 时也返回非 0）。
- **G6**（矩阵行 `g6_p11_dual`）：`P11_DUAL TB PASS`，`gates/xsim_p11dual.log` mtime 08:53:57。臂 A 真 HLS 握手（IP_A/ch1，完整 XGMII 帧 + TCP 校验和 + FCS + /T/）→ ch1 出 SYN-ACK（IP_A）、ch0 静默；臂 B force 直驱三 demux 输入（TCP→port1/ch0、UDP→port0/ch1、HLS→port1/ch0）逐口出现/另一口不出现、W83 +1/W84 +2；臂 C maccnt 目的域无混合值 + 裸 2FF 变异（逐位错开激励）出现混合值。
- **G7**：`[ELAB STRICT] count_0=1 count_1=0 (expect 1 / 0)`。
- **Elab 12 组合**：`ELAB_4COMBO_PASS`、`ELAB_COMBO_FAILS=0`（`gates/elab_gate_out.txt` mtime 08:52:54）。c1–c5、c8 OK；c6/c7/c9/c10/c11/c12 EXPECTED-FAIL OK，签名：`SFP2_MODE_A_AND_B_CONFLICT`、`SFP2_MODE_B_REQUIRES_P7B_10G`、`DUAL_SFP_A_REQUIRES_P7B_10G`、`DUAL_SFP_A_AND_SFP2_MODE_B_CONFLICT`、`DUAL_SFP_A_REQUIRES_DP_156MHZ`、`DUAL_SFP_A_REQUIRES_APP_MODE`。
- **24 门常驻矩阵（最终重跑）**：`gates run : 24 / 24`、`gates failed: 0`、`VERDICT: FROZEN -- all 340 hashed files byte-identical across the run`，`DIGEST_ALL(content)=3c8df3292164d8c08b6bfd9f819b42b722db0021650753692598b7dfd78f199d`、`GIT_HEAD=1c3cc7da`、`MATRIX DONE 2026/10/18 10:01:43`（工作目录 `work_20261018_092943`）。逐门独有串：chain=`P4 CHAIN OK`；burst200/trunc50/trunc100/halfdrop/txdrop50/gate4096/dupstorm/pcackoob/vlanburst=`BURST OK`；vlanchain=`P4 CHAIN OK`（`STRIPPED=2`）；stallgate=`PCSTALL OK`；unit_retx=`ALL 7 GROUPS PASS`；unit_fifo=`PASS_ALL frame_fifo unit: ...`；unit_vlan=`VLAN_STRIP TB PASS`；unit_uart=`UART-GATE-OK`（`ALL_OK`）；p5_wrapper=`P5 WRAPPER OK`；f3_resync=`F3-RESYNC-GATE: PASS`；swc=`P9-SWC-GATE: PASS`；p7b_chain=`VERDICT = PASS`；biz_win=`PASS_ALL tb_biz_win: 40 项判据全过 (窗口 88 字)`；g2=`RX_MERGE2 TB PASS`；g5=`SRCIP_GATE_PASS`；g6=`P11_DUAL TB PASS`。首跑曾因 `tb_p7b_chain.v` 缺分号 1 门红，修复后本次为全 24 门 `EXIT=0` 的干净绑定跑。
- **G9 读侧**：`check_window.py` top-5=`w87_snap..w83_snap`、`nnew_top=22`（上一轮 113 PASS/0 FAIL）；默认几何 `NW=88`、`EXPECT_BID=0x2C`、UNIMPL `0x190`（`p6e_snap_check.sh`/`p7b_snap.sh`/`p7b_gate4_negctrl.sh`/`j6_r6fix.sh`/`tcpreg_j6.sh`/两个 p6e TB）；`apply_readside_bid1c.py` 新增 `("0x0000002C", EDITS_2C, "P11 P2-甲 双口 + 双 IP (2026-10-18)", 88, 0x190)` 阶段。**排练 caveat**：磁盘哨兵已是 0x2C，`--rehearse` 会报 0 个待执行阶段并检查已部分更新的磁盘；真正演练需先把哨兵重置到 0x2B（本轮未做）。
- **G10**：`paths.txt` 的 FINGERPRINT_GLOBS 已含 `_proj_10g\p11_dual\sim\run_*.bat;...\tb_*.v;...\mk_mut_srcip.py;hls\src\*.cpp;hls\src\*.h;hls\run_hls.tcl`。

## 5. 未跑 / 未测（如实登记）

1. Vivado 构建/综合/实现/位流：未跑（纪律禁止）。
2. 上板/QSPI：未跑（纪律禁止）。
3. HLS csynth：未跑（按指令）；`run_hls.tcl` 只改了 `-cflags "-DBOARD_IP_DUAL=1"`，`hls/slowstack_prj/.../verilog` 仍是 **P11 前单 IP 网表**。
4. 双 IP HLS 网表的 xsim：需重综合 → 构建轮。
5. `tb_hls_dual_ip.v`（设计 §A 定向臂）：未写/未跑（设计允许本轮用现网表；IP_B 臂在当前单 IP 网表上无判别力）。
6. G3/G4 未进常驻矩阵（M-5 登记债；独立门可手动跑）。
7. 板级 W83..W87 / maccnt / 双口吞吐：未测。
8. `maccnt_sync` 的物理 CDC 时序：只有 xsim 功能证据，无综合/STA。
9. apply_readside 端到端演练：见 §4 caveat。
10. HLS csim 3 条基线失败：未修。
11. `tb_p11_dual` 臂 A 只用 IP_A；IP_B 的 HLS 握手需双 IP 网表。

## 6. 与设计的偏离 / 实施级选择

1. `tcp_state_probe` 钩子（`layer_tcp.cpp`，`TCP_STATE_PROBE` 守卫）：为在 csim 见证 RST 释放槽位的 `T_FREE`；默认不编译。
2. 第三支 csim 二进制（`ACTIVE_CONNECT + TCP_STATE_PROBE`）：设计要求“两个二进制”，本实现多跑一支仅用于状态见证，不改语义。
3. G5 判决不用 xsim 退出码（实测其在 TB PASS 时也非 0），改为 TB 终止行判决。
4. G5 bat 的 manifestcheck 兼容写法：xvlog 活行用无扩展名变量 + `%VEXT%` 拼装（manifestcheck 只认字面 `.v` token），不改门语义。
5. G6 TB 新增 `copy "%HLS%\*.dat"`：HLS ROM 初始化文件必须在 xsim 工作目录，否则 preamble/src-MAC ROM 读到垃圾（P4 chain bat 同款）。
6. `run_elab_4combo.bat` 的 STRICT 计数改 Python（原 `for /f ... | find /c` 在本机挂起），语义不变。
7. `udpapp_*` 非 APP_MODE 常量：为让 c12 报出具名硬门而非先炸 undeclared；同时收口既存的 `PCIE_OBS ∧ ¬APP_MODE` 编不过缺陷。
8. `slow_tx_adp.stat_side_ovf` 与 `u_demux_tcp` 的修复属实施缺陷修复（非设计偏离），但改变网表，构建轮必须按新树重综合。
9. 只加 HLS `-cflags`、不 csynth（按指令）。
10. HLS TB 的 `TEST()` 23 条 vs 设计件“19”（核到不符，如实说）。

## 7. 门/工具的已知边界

xsim 门只证明行为级；elab 只做 elaborate；G6 的 PCS 是 `p7b_pcs_stub`（行为级 XGMII pump），不证明真实 PCS/PMA；W83..W87 的板级读数未取。

## 8. 关键文件路径

- 门/测试台：`D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\p11_dual\sim\`
- 矩阵日志：`D:\repo\XCKU5PMini\udp_hls_10g\sim\p4sim\matrix_p4dfix.log`
- elab 门输出：`D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\p7b_chain\sim\elab_gate_out.txt`
- HLS csim 输出：`D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\p11_dual\sim\work\d0.txt`、`d1.txt`、`drst.txt`
- 权威设计件：`D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p11_p2a_design_20261018\DESIGN_v2r1.md`

---

## TL 抽核（2026-10-18 10:1x，逐条回源）

| # | 抽核项 | 结果 |
|---|---|---|
| 1 | 工作树 diffstat | ✓ 跟踪文件 `48 files changed, +1367/−200`；新增 `rtl/{rx_merge2,tx_demux2,maccnt_sync}.v` + 3 个 `.f` + `_proj_10g/p11_dual/sim/` 门件 |
| 2 | 矩阵 | ✓ `gates run 24/24`、`gates failed: 0`、`VERDICT: FROZEN`（340 文件）、`DIGEST_ALL=3c8df329…f199d`、`GIT_HEAD=1c3cc7da`、`MATRIX DONE 10:01:43` |
| 3 | Elab 12 组合 | ✓ `ELAB_COMBO_FAILS=0` / `ELAB_4COMBO_PASS`；6 个 EXPECTED-FAIL 签名全中；`[ELAB STRICT] count_0=1 count_1=0` |
| 4 | 构建常量 | ✓ `SNAP_NW_P6E=88`、`SNAP_P7BDP_NW=44`、`BUILD_ID_V=32'h0000002C`、tcl `verilog_define` 含 `DUAL_SFP_A=1`（9 宏） |
| 5 | N-6 | ✓ 默认体 `csum_sip = PER_CONN_SRC_IP ? cam_rd_dip : cfg_src_ip`（`rtl/tcp_tx_frame.v:834`、`:2072-2077`）；OVL 控制帧用 `ctrl_lip`（`:894`）；`cam_rd_dip` 为新端口（`:128`）；`o_port` 复位 0（`:949-951`/`:1672-1674`） |
| 6 | N-10 | ✓ `w83_dp..w87_dp` 三个 ifdef 分支均存在，非 DUAL/非双口支 W83/W84/W86/W87=0、W85 真（`wrapper_p4.v:4821-4844`） |
| 7 | N-4 | ✓ `board/build_p7b_ku5p.tcl:94` 导入三新件；`:311-322` `P7B_MODULE_RESOLVED` + `IS_BLACKBOX` 硬门；`p11dual_src.f:21` 含 `maccnt_sync.v` |
| 8 | N-5/G9 | ✓ 6 个读侧文件默认值已 88/0x2C（`p6e_snap_check.sh:60,72`、`p7b_snap.sh:87,89`、`p7b_gate4_negctrl.sh:156`、`j6_r6fix.sh:75-76`、`tcpreg_j6.sh:69-70`）；`apply_readside_bid1c.py` 有 0x2C 阶段（`:693-727`） |
| 9 | HLS | ✓ `BOARD_IP_DUAL` 默认 0（`eth_types.h:133-134`）；`tcp_conn_t.local_ip`、`tcp_find(port,ip,local_ip)`、`cfg_write w[2]=local_ip`、RST 循环 local_ip 匹配、ADD 传 `c.local_ip`（`layer_tcp.cpp:101/143-148/191/291/650/679`） |
| 10 | HLS csim | ✓ d0=46/3、d1=62/3、drst=68/3（07:16:29/07:16:58）；三臂 `P11SIG` 四行逐字相同；**基线见证 `gates/base_out.txt`（07:12:27，同 3 条失败、无 P11 用例）⇒ 3 条失败为既有**（TL 未独立重跑改前树，按"agent 自跑基线 + 时刻在前"采信） |
| 11 | 门 verdict | ✓ `RX_MERGE2 TB PASS`（矩阵）；`SRCIP_GATE_PASS`（08:24:55–08:25:03）；`TX_SPLIT TB PASS`（08:26:20）；`SLOW_TX_PORT TB PASS`（08:27:06）；`P11_DUAL TB PASS`（08:53:57） |
| 12 | 无工具并行 | ✓ `tasklist` 无 vivado/xsim/xelab/xvlog；未跑构建、未上板 |
| 13 | 新件结构 | ✓ `maccnt_sync` 为 4 相 toggle/ack（`req_tgl/ack_tgl/req_s1-s3/data_s1-s2`，无裸 2FF 多比特）；`slow_tx_adp.stat_side_ovf` 已改为 `commit_pulse && side_full`（G4 负控抓出的缺陷已修） |
| 14 | 链 TB 几何 | ✓ `tb_p7b_chain.v:1647-1661`：W83/W84/W86/W87≡0（非 DUAL）、W85 真、MIR `0x180`、`0x190 reads 0` |

**TL 附加发现（构建轮前置）**：
1. **synth 日志 `black box`/`8-3491` grep 硬门未落进 tcl**（现有 `IS_BLACKBOX` 属性检查；DESIGN_v2r1 §5.3 要求"日志 grep 才是硬门"）⇒ 构建轮补或明确以 `IS_BLACKBOX` 为准并在读数里写明。
2. `apply_readside_bid1c.py --rehearse` 因哨兵已被改到 0x2C 而**未真正演练 0x2C 阶段**（agent 已登记）⇒ 构建/板级前需重置哨兵演练一次或写明以"默认值 grep 自检门"替代。
3. HLS 网表仍是**单 IP**（csynth 未跑）⇒ **构建轮必须先跑 `run_hls.tcl`（`-DBOARD_IP_DUAL=1`）并归档旧网表**；G6 臂 A 的 IP_B 握手留构建轮。

**抽核结论**：14/14 与报告一致（HLS "3 条基线失败"采信于 `base_out.txt` 的早时刻见证；未独立重跑改前树）。未发现转录错误。可进入**实施红队审查轮**；之后才允许构建 0x2C。
