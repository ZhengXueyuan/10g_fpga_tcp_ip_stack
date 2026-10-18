# P3/C4 0x2F 构建计划（草稿，2026-10-19）

> 前置：实施红队审查收口 + 修复提交；HLS P3 网表已就绪（见 `HLS_CSYNTH_READINGS.txt`）。

## 1. 合同选择
- **0x2F = `EXPECTED_CONNS=2`（2×48KB）**：先做 2×10G 主判据（每口一条连接、现有两个 `app_pattern` 实例可驱动）。
- **0x30（后续）= `EXPECTED_CONNS=8`（8×12KB）**：8 连接共享池；数据面需多连接 app（当前未交），先做准入/零窗。
- 一个 bitstream 一个合同（设计 §14.3-④）。`P11_EXPECTED_CONNS` 当前是 wrapper 硬编码 8 ⇒ 构建轮加 `P11_EXPECTED_CONNS_2` 构建宏（默认 8 不变）。

## 2. 构建输入
- HLS：P3 网表（MAX=8 + `i_tcp_adv_wnd`）；`HLS_SRC_HASH`/`HLS_NET_HASH` 归档。
- 宏：`APP_MODE=1 DEV_USP=1 PCIE_OBS=1 DP_156MHZ=1 P7B_10G=1 UDP_TX_OVL=1 TCP_TX_OVL=1 SFP2_MODE_A=1 DUAL_SFP_A=1 P11_CFG_C4=1 P11_CFG_ENFORCE=1 P11_DUAL=1 P11_HLS_ADV_WND=1 P11_EXPECTED_CONNS_2=1`。
- BID：`BUILD_ID_V = 0x2F`；构建日志回读 `P11_CONFIG=dual`。
- 读侧：`apply_readside_bid1c.py` 加阶段 ⑲ 0x2F（BID-only；NW 85 / UNIMPL 0x184；W79 标签 = C4/ch0 MAC 好帧）；`check_window.py` 已接受两源名。
- 矩阵：32 门；构建前跑；构建期间零仓库写入；xsim 与 Vivado 不并行。

## 3. 门/读数
- WNS>0 / WHS>0 / 三类失败端点 0/0/0；`12-4739` 0；隐式网 5 键 0；black box 0；DRC 0 Error。
- 定向 STA：`u_tcp_tx/u_fifo_b→u_tcb`（两套）、`u_app_ctrl/o_ev_up→orph`（两套）、`win_pool_mgr` pool/winq、retx owner mux、`u_hls/*`、slow merge/demux、`slot_port`。
- 资源：placed LUT/FF/BRAM/URAM/DSP；对照 HLS csynth Δ（+4.3k LUT / +6.1k FF / +6 BRAM18K）。
- backstop（预登记，每档新输入）：① 共享 retx→每口 retx；② `EXT_QUOTA=1`→M3 每口 48KB；③ 慢 merge/demux 加切片；④ 回 0x2D。不许重跑到过。

## 4. 时间
- 到 07:00 收工；构建若在 05:30 后仍未启动，则不启动，留下一步命令与输入清单。
