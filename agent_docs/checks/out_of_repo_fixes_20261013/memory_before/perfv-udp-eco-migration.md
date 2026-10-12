---
name: perfv-udp-eco-migration
description: udp_hls 网络协议栈移植到 Kintex7 ECO 板 (1G 全通) → 10G 纯硬件 TCP/IP 重构阶段 (设计审查完成, 主推 RTL fast+HLS slow)
metadata: 
  node_type: memory
  type: project
  originSessionId: a43dc219-6b2c-4721-bd7a-260ae74f7393
---

# perfv udp_hls → Kintex7 ECO 板移植工程

**目标**: 把 D:\repo\perfv\udp_hls 的 HLS 网络协议栈 (udp_echo + uart_console 双 IP) 移植到 Kintex7 ECO 板。原工程不改, 副本在 D:\repo\ECO\udp_hls_eco (35MB) + D:\repo\ECO\gmii_probe_eco (89KB)。移植总纲: D:\repo\ECO\udp_hls_eco\MIGRATION_K7325T.md。

**Why**: 旧板 (Perf-V xc7a35t) 以太网物理通路已判损坏, 换 ECO 板继续网络调试。
**How to apply**: 施工进度更新本文档 + TaskList (#1-#15)。里程碑完成后逐项勾掉。上下文不够时先读本文件恢复状态。板级实验细节在 udp_hls_eco/PORT_NOTES.md (权威), 本文档只记结论。

## 新阶段 (2026-08-23): 10G 纯硬件 TCP/IP 重构 — 施工已启动 (1G 先行 / 10G-ready)

- **终局目标**: 10G 线速纯硬件 TCP/IP (低延时行情 UDP 组播 + 交易 TCP 4-16 长连接), 对上提供
  TCP/UDP 接口; IP 栈读速相对 PHY/MAC 零瓶颈。1G 工程冻结为回归基线。
- **设计审查产物**: `udp_hls_eco/design_review/` (01 现状分析 / 02 行业调研 / 03 候选架构 /
  04 施工计划; Git fbe37d7/da32ef5 已推)。核心数字: 现状排空 ~1B/30拍 (~33Mbps), 距 10G 差
  ~200×; 根因 = ap_ctrl_none 单 FSM 串行 body — 必废重写; 协议语义资产全可移植。
- **主推架构 B**: 纯 RTL 64bit 数据面流水 + 慢路径原样移植现有 HLS 层; 资源 ~30-45K LUT。
- **决策 (用户拍板): 1G 先行、10G-ready** — 数据面 64bit 字流 @125MHz, 10G 升级 = P6 后置
  (换晶振 SIT9120AI-2B3-33E156.25 + PG157 + 提时钟, 流水线不改)。
- **新工程 `D:\repo\ECO\udp_hls_10g`** (独立 git 仓库, 本地 commit a4c125e; 未建远端):
  rtl/ tb/ sim/ tools/ 全 Python 工具链 (anaconda)。
- **P0 完成 ✅**: mac_rx_64 (GMII 字节流→64bit 左对齐字流, FCS 校验剥离/4字节前瞻/弹性FIFO/
  帧原子丢弃) + crc32_8b + fifo_sync(FWFT), xsim 三模式 (无背压/抖动/硬停) 全 PASS
  (11 帧用例, 逐字节比对)。字流接口规范 = 10G-ready MAC 边界。
- **P0 关键教训 (已记 PORT_NOTES.md)**: ① CRC 使能必须与数据同拍 (组合) ② FCS 残留魔数 =
  **0xDEBB20E3** (zlib 值小端线上序; 0xC704DD7B 是大端魔数勿用) ③ TB 必须时钟化非阻塞驱动
  (阻塞+@posedge 竞争) ④ AXIS 输出 = 组合 valid+组合 rd+FWFT FIFO (寄存器 rd 被双采)
  ⑤ 移位量禁用宽不匹配字面量 (3'd8 截断为 0) ⑥ push_* 脉冲每拍默认清零。
- 下一步 P0 续: mac_tx_64 (字流→GMII, CRC 生成+padding) → 板上 RGMII 前端复用
  (wrapper_1g 的 MMCM 200M + util_gmii_to_rgmii) → 环回 bring-up。
- **P0 全部完成 ✅ (2026-08-23 晚)**: mac_tx_64 xsim 双模式 PASS (main 3 帧逐拍全等 /
  abort 欠载中止 runt+新帧); crc32_8b 加 crc_nxt; 组合 txd mux 保证 CRC 同拍。
  TX 新坑 (已记 udp_hls_10g/PORT_NOTES.md): TB 接受拍重赋同词双采 / **$readmemh 读十六进制**
  (GAP 10000 变 65536) / 模型 init 需状态快照 / 模型 TB 需非阻塞语义 / 欠载 gap 需远大于
  排空时间。板上 wrapper (board/) 由 agent 交付已核查: 前端逐字复用 + 环回 + LED;
  构建脚本无 IP 步骤。Git: fb05fff。**板上 Vivado 构建运行中 → 烧录环回 bring-up (P1b)**。
- **P1 完成 ✅ 板上环回 bring-up PASS (2026-08-23 深夜, Git ef3e20e)**: 构建 0 警告 0 错误;
  JTAG 1MHz 烧录 DONE=HIGH; **pktmon 实锤**: PC ARP Tx(42B) 1.9µs 后 Rx 收到同内容 60B 副本
  (= mac_tx_64 pad 28→46B 的行为, FCS 有效); UDP 广播同样成对。10G-ready 64bit 字流
  MAC RX/TX 在 1G RGMII 板上全链验证通过。**pktmon comp ID 变更为 102** (旧 117 失效,
  用错 ID 抓包全空 — 已记教训)。
- **P2 完成 ✅ UDP fast path 全链 xsim PASS (2026-08-24, Git 3e3f0bd/d3332d0/4468e7e)**:
  checksum16 (反码和) + udp_rx (头解析+匹配+载荷 cut-through 直出, fend/ferr 帧判定 sideband)
  + udp_tx_frame (帧级递交, IP/UDP 双校验和) + frame_fifo (回卷) + udp_echo (帧级 echo);
  RX 三模式 33 帧 / TX 双模式 20 帧 / echo 闭环 22 帧 全 PASS (Python 参考模型逐拍对拍)。
  GitHub 仓库已建 ZhengXueyuan/udp_hls_10g (public)。关键新坑已记 PORT_NOTES:
  位宽声明错→越界选择 X→if(X) 静默绕过校验; 拼接必须恰 64 位; TX/RX 尾字剩余 n-6/n-2
  不可混用 (负移位→keep=0 字→mac 死循环); RFC768 udp_len 计两次; 回卷快照 wptr 非 wptr_n;
  帧判定脉冲与 emit 一拍延迟的 pend 挂起; agent 输出 32K token 上限 (报告≤400词)。
  **P2 板上 PASS ✅ (2026-08-24, Git 42af350)**: UDP echo 双模式 (组播免 ARP 500 帧 +
  单播静态 ARP 100 帧) 全收对零丢零错。板测关键: cfg_multi_en 与单播并存 (只开组播会
  旁路丢单播); mem 数组带异步复位 → BRAM 推断失败 → LUTRAM 时序炸 (WNS -0.108), 拆
  独立 always 后 +0.223 但 BRAM 仍 0 (10G 前要解决); PC 双网卡组播走 metric 低接口。
  下一步 P3: TCP fast path 数据段 (TCB 寄存器 + ACK 生成)。
- **P3 完成 ✅ (2026-08-28, Git e7391c1 已推) — 板上 TCP echo PASS**:
  Windows 真栈三次握手 13.2ms (SYN 带 12B 选项 doff=8 也正确处理), 14 块
  1..1460B 逐字节回显全对, 平均 RTT 0.05ms。全链: mac->tcp_rx->tcp_echo->
  tcp_tx_frame->mac + tcp_synp 握手 (P4-lite) + tcp_cam/tcb + 仲裁 tx>rx>cfg。
  6 回归全绿 (cam_tcb/tcp_rx 三模式/tcp_tx/chain/echo + P2 三套)。
  板级: WNS +0.482, LUT 8.3K, BRAM 0 (frame_fifo 分布式 RAM, 10G 前要解决)。
  本轮教训 (PORT_NOTES): CAM 4 元组是 RX 视角, TX 目的 IP 必须用 sip 字段 —
  模型与 RTL 同错会互相印证 (xsim 全绿但语义错), 语义期望要独立于 RTL 推导;
  批量替换端口接线必须 grep 验证 (空格对齐变体漏掉 -> 悬空 0); pktmon etl
  多次 stop 合并, 重抓前必须删 etl。
  agent 工作流: 测试 agent 抓 2 bug + 审查 agent 抓 2 bug 已固化 (用户指令:
  每里程碑必开审查+测试 agent; 重构允许, 功能实现为唯一标准)。
  下一步 P4: 慢路径 HLS 移植 (ARP/ICMP/DHCP/重传/RTO/FIN, 替代 tcp_synp)。
  P5: app 接口。P6: 10G (晶振 + PG157 + BRAM 化)。细节: udp_hls_10g/PORT_NOTES.md。
- **P4a 完成 ✅ (2026-08-29, Git 69eab75 已推) — 板上一次 PASS**:
  慢路径 = udp_hls_eco 的 udp_echo HLS **原样** (158 综合文件零改动) 经
  rx_classify (ethertype/proto 分流) + slow_rx_adp/slow_tx_adp (64b字流↔HLS
  字节流, 整帧 commit/rollback, 补/剥前导, 4B 回持剥 FCS) + tx_arb (fast优先)
  挂进数据面; **MAC 统一 C0** (HLS 编译期值, fast 原 C1 作废)。板测:
  免静态 ARP (HLS 应答, 动态绑定) + ping 4/4 0ms + TCP 回归 14 块逐字节
  RTT 0.04ms + UDP echo 0.16ms; WNS +0.918, LUT 26.3K (12.9%)。
  全链 xsim 带真 HLS (tb_p4_chain 9RX→11TX 全语义) 把板级风险前置清零。
  关键设计: HLS MAC RX 不查 FCS (适配器按 tcrs/terr 拦截, 只补前导);
  HLS 自发行文保留 (~1s DHCP×3 自停, ~5s UDP HELLO = 白送冒烟)。
  审查轮 2 致命: FWFT 铁律#4 再犯 (i_rd/wf_rd 寄存器化双采) + 截断帧
  SOP 防御 (slow_rx_adp in_frame/resync_drop)。
  **下一步 P4b**: TCP 正式握手 (classify skid 加深到 6 字窥 w5 flags 分流
  SYN/FIN/RST 到慢路径; HLS 握手结果 (layer_tcp.cpp:370 旁路) 经 cfg 口写
  CAM/TCB — 只连建期写容忍被抢; 移除 tcp_synp; HLS SYN+ACK 未应答会 RTO
  重传永不放弃需配套)。P4c: 重传/RTO (fast 侧重传缓冲)。
  P6 补充: rx_classify 在 10G min-frame 洪泛下 8字+3拍 stall > 10.5 拍预算
  → mac 层计数丢帧, P6 复审 (skid 改真 FIFO 或加深 mac fifo)。
- **P4a 单元回归轮 (2026-08-30, Git c6808c6)**: 4 单元 TB 三模式全绿 +
  全回归 (P0-P4a) 绿。抓到 3 个板测没暴露的真 RTL bug: ① frame_fifo full
  公式在 rptr 低位==0 窗口永不触发 (绕回踩槽, P2 起存量); ② 两适配器播放器
  幻影开播 (committed 播完才减 vs 开播判断同拍读旧值 → 末帧后抢读未提交词);
  ③ tcp_tx 的 bat 没接 checker (假绿) 且 checker 还是 rd_sip 修复前语义。
  教训: 队列计数与开播条件必须同源同拍; bat 必须自带 checker 收尾。
- **P4a 吞吐+泛洪轮 (2026-08-30, Git 5b9a537+407ffdd)**: **TCP 持续吞吐
  1.5Mbps → ~110 Mbps 稳态** (零重传; 上限是 Windows 对端环路: pktmon 测
  ~40µs/段 vs xsim 证 FPGA ~9µs/段, 瞬时线速 ~890Mbps — 真天花板要硬件
  对端 P6 再证)。三个关键修复: ① 顺序数据段纯 ACK 抑制 (cfg_suppress_
  data_ack, echo 帧自带 ack; 抑制前 TX 比 RX 慢 16.6% → echo fifo 满 →
  丢段雪崩) ② 泛洪死锁: HLS 内部 512 词帧 fifo 灌满 mac_rx 写阻塞永久
  停读 → slow_rx 开播节流 (o_fifo occ≤256B 才开播) + abort 恰好-TLAST-满
  同拍竞争粘连修复 + HLS 看门狗 (16.8ms 饥饿复位, WDOG 参数化) ③ tcp_synp
  窗口 8K→12K (无效, 非窗口限制)。**看门狗能复位 HLS** — P4b 握手状态
  在 HLS 侧时注意。xsim 探针 (tb_p4_chain PROBE 模式层级探针) 是破案主力;
  pktmon 同时间戳重复帧是双点采集伪影要去重。
- **10G 晶振调查 ✅ (2026-08-24, Git 3ff1045)**: 官方说明 (数据手册/关于光通信晶振说明.txt)
  指定万兆换 SIT9120AI-2B3-33E156.25; 原理图 R3 第 6 页实锤: 位号 X5 = 125M 差分晶振
  (SiT9102, 顶面丝印 A10LP, 频率在第二行), 网络 SYS_CLK_125M_P/N → MGTREFCLK0_115
  (H5/H6); 板上位置 = clkdiffgtx/C246 旁 6 脚器件; 换晶振不动 C246/C247/R85。
  换 KU115 板对比: 资源 3.3-6.6× + UltraRAM 270Mb + GTH 16.3G, 但本协议栈 325T
  已够 (30-45K LUT 占 15-22%), 暂不换。

## 网络调试最终状态 (2026-08-18 上午 — ✅ ping 全链打通, loop 结束)

- **✅ ping 192.168.100.2 = 4/4 回复 0ms** (09:05 位流, wrapper_1g ip_enable=1)。
  pktmon 确认 FPGA 的 ARP 回复 / ICMP echo reply / demo 克隆 ARP 广播全部到达 PC。
  当前板上位流 = vivado_prj/udp_dual_phy1g2.runs/impl_1/wrapper_1g.bit (03:30 构建, MSS=460 + RX 576B 修复)。
- **TCP 状态 (2026-08-23 ✅ 2000B 已破案修复)**: UDP 8080 echo ✅, TCP 25B/1608B/**2000B** ✅ 全过
  (py_net_test 7/7)。**根因 = wrapper 的 rx_fifo 溢出** (2048深/1900门限): HLS DUT 排空慢
  (~1字节/20周期, ap_ctrl_none 串行栈), 4 段背靠背 (~2392B) 顶满 FIFO → 丢第4段中段字节+丢
  last → 融合下一帧 → 回显错位 (非确定偏移~1739)。板级 ILA 实锤 (rx_occ 撞1900 + stride-21
  子采样吻合)。**修复: rx_fifo 2048→4096, 阈值 1900→3900** (wrapper_1g.v)。DUT 逻辑本身无错
  (xsim 2000B 逐字节证明)。**关键教训: 一直在 DUT 找竞态, 但瓶颈在 wrapper Verilog FIFO;
  csim/DUT-only xsim 都绕过它, 只有板级 ILA 能在真实 PHY 时序下抓到。** 修复是治标 (≤6段),
  治本需提升 DUT 排空速率。详见 RX_FIFO_OVERFLOW_ANALYSIS.md。Git: d388289 已推 GitHub。
  顺带修的真 bug: ap_uint<9> 地址截断 TX_UDP_BASE=512→0 / uint8_t wi 索引溢出 256→0。
  xsim TB 坑: 漏接 DUT reset_n 软复位端口 → 子FSM phi-mux X 死锁 (csim过/RTL卡典型)。
  工具留存: tb_udp_echo.v (DUT-only xsim) + tb_wrapper_rx.v (FIFO+DUT) + gen_stim.py +
  parse_resp.py + py_net_test.py + wrapper_1g_ila.v (ILA) + ila_capture/analyze 脚本。
- **两个最终根因 (都被"自证闭环"掩盖)**:
  ① **FCS 字节序必须 LSB-first** — demo 帧线上 FCS = CA A3 F9 63 (= zlib 寄存器
  0x63F9A3CA 小端); 我们发的 MSB-first 63 F9 A3 CA 被网卡静默丢 → 所有 demo 克隆
  实验 0 帧的唯一原因。修复: reflected CRC-32 + fcs[7:0],[15:8],[23:16],[31:24],
  应用于 7 个 Verilog 生成器 + HLS layer_mac.cpp。
  ② **ICMP 校验和字段只清 1 字节** — layer_icmp.cpp `&= 0xFFFF00FF` 漏清低字节,
  请求校验和低字节 0xD4 污染求和 → 线上 4600 (应 46D4) → Windows 静默丢。
  改 `&= 0xFFFF0000`, TB 加校验和检查。
- **教训 (铁律)**: ① FCS/校验和的"标准"有实现歧义 — 以权威 demo 位流的线上字节为基准,
  做**全帧逐字节**比对 (之前只比前 24 字节恰好漏掉 FCS)。② 线上字节问题必须用
  `pktmon etl2txt --hex` + Python 独立参考实现校验, 不能用与设计同源的参考自证
  (两次漏检都是这个原因)。③ 撤销: 功率/结构/相位/工具链假设全部撤销, 归因于上述两 bug。
- **遗留 (下一轮)**: UDP 8080 echo 超时 (疑 UDP RX 校验和验证/回复构造同类 bug —
  用 pktmon --hex 独立校验); 之后 TCP 7 echo。已写入 PORT_NOTES/CLAUDE/README。
- 其余已修: MAC padding (runt) / DHCP IP头+缓冲越界 / DHCP 洪泛 / wrapper rx_last 极性。
  新综合数: udp_echo = 27 BRAM / 4 DSP / 15,655 FF / 36,200 LUT; uart_console = 268 FF /
  1,765 LUT Latency 0 Interval 1 ✓。
- 文档全量刷新; git 已推 GitHub (hls_gigabit_tcp, 上游历史 + ECO 迁移 + FCS 破案两个 commit)。

## 板卡硬件结论 (R3 原理图 + RTL8211E 数据手册, 2026-08-16 已确认)

- FPGA: **XC7K325T-2FFG676C** (FFG676, 非迁移文档假设的 ffg900!) → set_part = xc7k325tffg676-2
- 以太网 PHY1: **RTL8211E** (QFN48), 板上有 PHY1+PHY2 两路, 用 PHY1
- 接口: **RGMII 4bit DDR, IO 电压 1.8V** (bank 34), 快速参考: "1.8V IO, RX DELAY strap 使能"
- FPGA↔PHY1 引脚 (bank 34):
  - RX_CLK=W1, RXD0=AA5, RXD1=AC4, RXD2=V2, RXD3=AB2, RXCTL=AB6
  - TX_CLK=Y2, TXD0=AA4, TXD1=AA2, TXD2=AC2, TXD3=AA3, TXCTL=V4
  - MDC=W4, MDIO=AC1, nRST=V1
- UART: CH340E, TTL 3.3V, bank 15: **rs232_rx=B19, rs232_tx=C17** (注意 k707 demo 用的是 B17/A17, 那是旧版本)
- 时钟: CLK_50M 晶振 (50M/10PPM) → **C26** (bank 14; 原理图还出现 G25 同网标)。k701/k707 demo 用 G22 且板级可用 — C26 若无效可用 G22 兜底
- LED1-8 (bank 14, 82R 串阻): C24/C22/E22/D24/G24/F24/H26/H21 → 用 LED1-4 = C24/C22/G24/D24 做 led_d0..3
- JTAG: FT232 板载调试器 (Digilent SN 210251A08870), hw_server TCP:3121, 烧录脚本模式见 k701_led_stream/program_hw.tcl (PROGRAM.FILE 必设 + JTAG 1MHz)
- 串口: **COM8** = USB-SERIAL CH340 (PowerShell + System.IO.Ports 测试)
- 其他: SFP×2 (GTX), PCIe x4, DDR3, HDMI×2, QSPI flash MT25QL256

## 工程移植改动清单 (副本内)

1. run_hls.bat/tcl + uart_hls/run_hls.bat/tcl + run_vivado_wrapper.tcl: set_part → xc7k325tffg676-2 (原 xc7a35tftg256-1)
2. wrapper.v: GMII 顶层端口 → RGMII 适配 (IDDR/ODDR + BUFG), e_rxc=e_gtxc=RXC_buf; UART 同步器保留在 wrapper; e_reset=1'b1 (RTL8211E nRST 低有效, 1=释放); msg_stream 仍禁用 (CDC FIFO 未做)
3. XDC 全重写: RGMII bank34=LVCMOS18, UART bank15=LVCMOS33, clk/LED bank14=LVCMOS33; 补 create_clock (125M on RXC, 50M on gclk) — 旧工程没约束
4. eth_types.h: BOARD_IP 192.168.100.2 已避 WLAN 网段, MAC 00:0A:35:01:FE:C0 保留
5. 必修 bug: layer_icmp.cpp:162 dst_mac=0 → ping 必死 (MIGRATION §3 #3)

## 已知坑 (来自勘察 + MIGRATION)

- udp_echo 是 31 状态事件驱动 FSM (无界延迟), **不要求 II=1**; 只有 uart_console 必须 Latency 0/Interval 1
- 生成 RTL 备份: udp_hls_eco/vivado_prj/udp_dual.srcs/sources_1/imports/verilog/ (162 文件, HLS 失败时的兜底)
- csim 最近一次失败 (solution1 被清空) — 跑 HLS 前注意 tb 状态
- RGMII RX 时序: RXDLY strap 已使能 → FPGA 端 IDDR 直接用 RXC 采样即可; TX 侧看 TXDLY strap 状态 (待确认)
- 板级验证顺序: ?mac (UART console) → gmii_probe (rxc=125M + MDIO PHY ID) → ping → TCP echo

## 工具链速查 (本机已验证)

- PDF 提取: C:\AMDDesignTools\2025.2\tps\win64\python-3.13.0\python.exe + pymupdf (已 pip 安装); 或 /mingw64/bin/pdftotext -layout
- 渲染脚本: /tmp/render2.py (fit width 2200px); Vitis HLS: vitis-run.bat --mode hls --tcl
- 进度: TaskList #1-#9; 关联 [[xilinx-vivado-toolchain]] [[vitis-hls-2025-2]]

## 硬件规格最终版 (板级实测修正, 2026-08-16)

- PHY = **RTL8211E-VL**: 只支持 RGMII, 1.8V 电平。**TXDLY=1, RXDLY=1** (排阻焊死) →
  PHY 内部加 2ns 延迟, FPGA 侧纯 IDDR/ODDR 上升沿方案正确, 无需 IDELAY/ODELAY
- **PHYAD = 0x1** (PHY_AD[2:0]=001), MDIO 1K 上拉到 1.8V, AN[1:0]=11 全广告
- bank34=1.8V (LVCMOS18), bank14/15=3.3V
- **⚠ PHY1 引脚 = k719/k720 DEMO 引脚组 (gmii_probe 板级实测确认)**:
  rxc=AB2, rxd=AE2/AE1/AC1/AC2, rxctl=AF3, txc=AB1, txd=AB4/AA4/AA3/AA2, txctl=Y3
  R3 原理图的 PHY1 分配 (W1/AA5/AC4/V2/AB6/Y2/V4...) 在物理板上**不成立** (W1 实测 0 沿;
  AB2 实测 PHY 空闲钟 2.5M)。PHY2 引脚 = demo 组 (AA23/V26/V21/U24/U25/U26/V24/V22/W26/W25/W21/W23)。
- MDC/MDIO/nRST 物理引脚未知 (demo 不用 MDIO, 原理图不匹配物理板) — 主设计靠 strap 配置, 不需要。
- **CLK_50M=G22 确认** (MRCC), UART=B17(RX)/A17(TX) 确认, reset=D26=KEY1 按键 (低有效)
- LED1-8=A23/A24/D23/C24/C26/D24/D25/E25, 高电平点亮 (4.7K 串阻)
- **网线状态**: 两个 PHY 都无链接 (空闲 2.5M), ping 实验零帧到达 → 网线没插进板子的 RJ45!
  PC 有线网卡 (Killer E5000B) 1G 链路连着别的东西 (可能路由器)。**等用户回来插线 (PHY1 口)**。

## 网口最终结论 (2026-08-16 深夜, 最小探针 125MHz 实测定案)

- **接线的口 (丝印 ETH2) = R3 原理图的 PHY2 = C 组引脚**: rxc=**AA23** (实测 125MHz 时钟!),
  rxd=V26/V21/U24/U25, rxctl=U26, txc=V24, txd=V22/W26/W25/W21, txctl=W23,
  **bank 12 @ 3.3V (LVCMOS33)**; MDIO=AA25/Y25 (PHYAD 0 答, ID 001C/C915)
- 旧 probe 的 2.5M/0 读数全不可信 (250MHz 采样器对 125MHz 有 2:1 混叠问题);
  新最小探针 (top_mini.v, 单 BUFG 无 CDC) 在 AA23 上读到 125MHz (446 行/60s = 134ms/窗) — 定案
- **MMCM 不锁根因**: MMCME2_BASE 的 CLKFBIN 未连接 (反馈环开路) — 补 `.CLKFBIN(fb)` 后
  D2 (LOCKED LED) 亮。probe 的 MMCM 一直是闭环的所以能锁
- **用户关键发现**: ping 192.168.0.2 (demo IP) 会走 WLAN (192.168.0.43 网段) — demo 的
  "8/8 ping" 是 WLAN 设备的假象 (ARP 缓存 0a-91-3a-43-8c-72); ping 192.168.100.2 走有线 ✓ 真测试
- RX 配方 (vendor demo): 取反 BUFG + IDELAY(10) + SAME_EDGE_PIPELINED + IDELAYCTRL@200MHz;
  裸非取反采样在 1G 下必挂 (1/5 ping 是它的极限)
- 排查教训: ① 对照实验必须走对物理路径 (路由!) ② MMCM 必须闭环 ③ 探针的采样域设计
  要防混叠 ④ genvar/段删除的脚本编辑反复踩坑 — 每次构建前 grep 验证关键行

## 重大根因发现 (2026-08-16): UART TX 9.5 位元间距

原 TX FSM "停止位 mid-cell 驱动后立即结束" → 背靠背突发起始沿间距 9.5 位元 (标准 10)。
旧板适配器宽容; ECO 板 CH340 在停止位采样点撞上下一起始沿 → framing error 级联 →
回显干净 (RX 握手抖动有间隙) 但响应/报告突发全乱码。csim 全过 (C++ 模型对, 是物理时序问题)。
修复: 字节在停止位元结束才结束 (uart_console.cpp + gmii_probe top.v)。
⚠ 与用户全局 CLAUDE.md "TX 停止位驱动后立即结束" 经验冲突 — 该经验是旧板适配器特定的。

## 网络调试最新状态 (2026-08-18 凌晨 5点半 — 疑点锁定: 大设计功率/噪声)

- **HLS 协议栈已全部修复** (agent 完成): MAC padding / DHCP IP头+缓冲布局+FAILED 状态 /
  csim 14 测试全过 / 已重综合重烧录。IP 现在正常回 ARP (tx 随 ping 增长)。
- **runt 理论被推翻**: 64B padded FCS 有效帧同样 PC 不可见。
- **demo 克隆实验定案**: wrapper 内置 ipsend 同款帧发生器 (55x7 D5 + FFx6 + ARP + 真CRC,
  1Hz), 经 demo 原版 RGMII 发出 (tx 计数证实 +177/16s) → **pktmon 仍零**。
  帧内容/节奏/RGMII/引脚/时序/配置全部排除。
- **唯一剩余差异**: 34k LUT HLS IP @125MHz 的功耗/开关噪声 vs demo 微型设计。
- **功率门控实验 (构建中)**: 上电按住 IP 复位 (静止低功耗), 只跑 demo 克隆发生器 + RGMII。
  PC 收到帧=功率实锤 (修法: BUFGCE 时钟门控/降频/分区摆放); 仍零=PHY 状态层面或示波器实测。
- 全程细节: udp_hls_eco/PORT_NOTES.md。探针: ?net/?txd/?rxd/?raw。
- 教训追加: ① 网卡硬件丢弃 runt/错 MAC 时 pktmon 完全不可见 ② 前向引用隐式网 vs reg
  声明坑 (tx_draining 双重声明第二次被忽略) ③ 实验必须验证生成器真的在发 (计数)。


- **BUG1 (wrapper rx_last 极性反了 = dv 上升沿误当帧尾) 已修并板级验证**: ping 6 ARP → tx+6,
  IP 现在收到 ARP 请求会回复了 (此前 RX 协议栈全死)。
- **pktmon 仍零 FPGA 帧** — 与 runt 理论一致: 我们发出的帧全是 46B runt, PC 网卡硬件
  静默丢弃 (pktmon 不可见)。物理层/数字链全部健康, 唯一问题 = 帧 <64B。
- **HLS 修复 agent (af167be57af8aebec) 已派出**: layer_mac.cpp 加 padding +
  layer_dhcp.cpp 补 IP 头/修缓冲越界/修洪泛复位 → HLS 重综合 → Vivado 重建 → 烧录验证。
  完成后预期 ping 通 → UDP 8080 → TCP 7 (任务 #12)。
- 板级 DHCP 实际速率 ~1/3.3s (仿真里的 134ms 是缩短定时器所致)。
- 全部过程记录在 udp_hls_eco/PORT_NOTES.md (含 UART 探针 ?net/?txd/?rxd/?raw 用法)。

- **fresh-eyes agent 网表级对比 + 全链仿真定案**: RGMII TX 通路与 demo 逐字节一致
  (ODDR/BUFG/IOB 全同; 反相 LUT 两边都被优化成缓冲器 → gmii_clk≈RXC; TX 时序无违例)。
  帧 FCS 仿真全对。**物理层/电气层彻底排除** — 问题全是协议栈 bug。
- **BUG 清单**: ① wrapper 的 rx_last_in 极性反了 (写成了 dv 上升沿=帧首! 应是
  `!rx_dv_d1 && rx_dv_d2` 帧尾) → IP 的 MAC RX 永不 complete → ARP/ICMP/UDP 全不响应;
  ② MAC_TX 无 padding → ARP 帧 46B 是 runt → PC 网卡硬件静默丢弃 → pktmon 零包;
  ③ DHCP 帧无 IP 头 + 缓冲越界 (word331+308>512); ④ DHCP 放弃后不复位 → 每 ~134ms 洪泛。
- 修复: ① wrapper 已改 (push 用 rx_d2 门控 rx_dv_d2, last=rx_dv_d2&&!rx_dv_d1) 重建中;
  ②③④ 需改 layer_mac.cpp/layer_dhcp.cpp → HLS 重综合。
- 工具留存: UART 探针 ?net/?txd/?rxd/?raw; agent 留了 wrapper_tb.v 全链仿真 TB + sim_patch/。
- 教训: ① `wire x=expr` 对已声明网不可靠 → 用 assign ② 5'd32+ 截断坑 ③ LUT 反相 BUFG 时钟
  必须 create_generated_clock -invert (但注意反相会被综合优化掉, 是约束描述不是硬件)
  ④ 帧捕获必须冻结防撕裂 ⑤ 网卡硬件丢 runt/错 MAC 帧时 pktmon 完全不可见 — 不可只信 pktmon。

## 网络调试最新状态 (2026-08-17 深夜 — TX nibble 配对 bug 破案)

- **对照实验**: 烧 k720 demo 预构建 bit → PC 每秒收到 demo 的 ARP 广播 →
  **PHY1 线侧 TX 硬件完好**, 问题在自研设计。
- **根因**: demo 的 TXD ODDR D2 (`gmii_txd_low`) 是寄存器+阻塞赋值 = 读 txd_r 旧值 =
  **2 拍延迟字节的高半字节 → D1/D2 同字节** (标准 RGMII DDR)。误实现成 D2=1 拍字节
  → 字节错位混搭 → 目的 MAC 移位 → PC 网卡硬件过滤 → pktmon 零包。
  TXCTL D2 同样修。已改 wrapper_1g.v (D2=gmii_txd_r_d1[i+4]) 重建中。
- net_stats "?net" 实战有效 (rx=000D tx=14E0 L=1 暴露 TX 狂发 PC 零收)。
- 教训: agent 转述 demo 代码会丢阻塞/非阻塞语义 — 关键 recipe 必须亲自逐行读源码。
- 诊断信号: pktmon 零包 + tx 计数狂涨 = 帧字节级错位被网卡硬件过滤 (不是物理断链)。

## 网络调试最新状态 (2026-08-17 晚 — PHY1 k720 配方定案)

- **ETH1 (PHY1, AB2 组 bank34 LVCMOS18) 自动协商 1G 正常** (PC Killer E5000B 192.168.100.1 直连),
  UART console 全过。裸采样/MMCM 移相在 1G 都是死路 (1/15 极限 / 全周期 0 ping)。
- **k720 demo 配方 = 1G 正解** (Explore agent 提取): RX = RXC 经 LUT1 反相 → BUFG →
  IDDR SAME_EDGE_PIPELINED (字节 {Q2,Q1}, 寄存一级), 数据/CTL 各过 IDELAYE2 FIXED=10
  (200MHz IDELAYCTRL, MMCM 50M×20÷5, IODELAY_GROUP "idelay"); TX = 同反相时钟,
  TXD ODDR D1=D2=同一 2 拍延迟字节 (注意: demo 的 gmii_txd_low 是寄存器, 等于 txd_r_d1[7:4]!),
  TXC=ODDR(1,0); 无 MDIO 无 RGMII 约束。k721=ETH2 同配方 IDELAY=21。
- 重建: wrapper_1g.v (demo 配方 + net_stats.v "?net" 帧计数) → vivado_prj/udp_dual_phy1g2。
- 验证序: LED D2=RDY/D3=locked → ?net rx>0 → ping → UDP 8080 → TCP 7。

## 网络调试最新状态 (2026-08-17 上午 — 攻坚结论)

- **100M RGMII = 1 nibble/周期** (不是 1G 式字节/周期 DDR!) — 所有既有实现的字节拼装
  在 100M 下全错。RX 修复: 上升沿采样 + 2 周期 nibble 累加 (板级逐字节验证通过)。
  TX 修复: nibble/周期 + TXD 挂 MMCM 输出 (PHY 用内部时钟采样, 不用我们的 TXC!)
  + 相位 @+10-12 校准 + FCS 重算 — 环回数据逐字节正确。
- **ETH2 的 PHY (RTL8211E) 线侧数据 TX = 硬件故障**: 环回数据正确 + 链路 UP
  (100M/1G 都协商成功) + RX 方向完全正常, 但数据帧在所有配置下到不了线上。
- **下一步 = ETH1 (PHY1, bank 34, AB2 组引脚)**: PHY1 空闲钟 2.5M 一直在 (活着)。
  攻坚 agent 在准备 wrapper_v2 的 PHY1 变体 + MDIO 双 PHY 写探针; 用户回来把网线
  换到 ETH1 口即可测试。
- 完整攻坚日志: udp_hls_eco/PORT_NOTES.md 的"攻坚日志"节 (agent 写了 100+ 行)
- 交付物: wrapper_v2.v + vivado_prj/udp_dual_v2 (AA23 组); mini_proj_D2 (诊断探针);
  probe_aa23 (寄存器读探针); tools/crc32.ps1 + pktmon_capture.ps1

## 网络调试最新状态 (2026-08-17 凌晨 v4 — 垃圾帧破案, 校准进行中)

- **根因锁定**: pktmon 抓到 PC 收到 25 个垃圾帧 (EtherType 0x889E/0x88C7 = 0x0800 错位采样) —
  **PHY 采样 FPGA 的 TXD 时相位错位**, 转发到线上的是坏帧。环回自洽 (用自己时钟) 所以全通。
  RX 方向同理 (采样相位错) — 一个相位设置同时修 TX+RX。
- **解药已就位**: wrapper.v 和 mini 的 RXC→MMCME2_ADV (VCO=600, CLKFBIN 闭环, @+/- = 56 步
  ≈1.67ns, UART 9600 命令, 全周期 40ns 需 24 条命令)。XDC create_clock 周期 40.0。
- **校准协议 (UART 观察)**: 烧 mini_proj_C (帧发生器+相位调器, agent 构建中) → 每 ~7s 发 @+,
  看 UART 行 rxdv_hi/frm 从 0 变 >0 的相位 = 采样窗 → 记下步数 → 换算回 wrapper 的 CLKOUT0_PHASE
  (或用同样步数的 @+ 在烧录后自动执行) → 主设计 ping 验证 → UDP/TCP。
- 主设计位流: vivado_prj/udp_dual_min.runs/impl_1/wrapper.bit (相位可调, 已就绪)
- 若全周期扫完无窗口 → 查 PHY 的 TXDLY strap 假设, 或换网线 (用户换过一次, 仍怀疑)
- pktmon 可用 (管理员 OK): pktmon start --capture --comp 117; etl2txt -v 拿 MAC
- agent 团队: a258c5d2f8189e72b=MDIO probe, a99d588052272904f=mini probe, a534f375fb210cc2a=wrapper

## 网络调试最新状态 (2026-08-17 凌晨 v2 — 环回判决)

- **MAC 环回测试 (BMCR=0x6100) 通过**: mini TX 帧发生器每窗口发 1 帧 → PHY 环回 →
  rxdv_hi=63/frm=1 完整收回 — **引脚组 (AA23 组) + FPGA TX/RX 数据通路 + PHY 数据通路全部正确**
- 结论: 正常模式数据死的唯一变量 = PHY 的 RXC→RXD 相位 (物理板 RXDLY strap 未知,
  误差可达半周期 20ns@25MHz, IDELAY max 2.4ns 不够)
- 进行中: wrapper 加 RXC→MMCME2_ADV (VCO=600, ÷24=25MHz 输出, CLKFBIN 闭环) + 相位
  FSM + UART @+/- 命令 (56 步≈1.67ns/次) 在线扫相位; TX 保持环回验证过的接法
  (tx_clk=BUFG(phy1_rxc) 非取反 + TXC 转发)
- 烧录后校准流程: ping → @+×N 扫 → 帧出现的相位 → UDP/TCP 验证

## 网络调试最新状态 (2026-08-17 凌晨)

- **pktmon 抓包 (可用, 无 admin 问题)**: 60s 捕获 259 包, FPGA MAC 零出现 — PC 的 ARP 出去了,
  FPGA 从未回过帧。etl2txt 需 -v 拿 MAC; 文件是 UTF-16 编码 (grep 前先解码)
- **当前矛盾**: AA23 时钟稳定 25MHz (100M 强制后) + 链路 UP + MDIO 可用,
  但 PHY↔FPGA 数据双向死 (rxdv 恒 0, PC 零收包)
- 下一步: **MAC 环回测试** (BMCR=0x6100: bit14 环回 + 100M-FD) — PHY 把 TX 输入环到 RX 输出,
  配合 mini 的 TX 帧发生器, 一次测穿 FPGA TX 引脚 + PHY 数据通路 + FPGA RX 引脚
- 若环回也不通 → PHY 的 RGMII 数据通路被禁 (strap/mode 问题, 深挖 PHY 模式)

## 施工进度 (2026-08-16)

- [x] 任务#1 硬件规格 (strap agent 完成; PHY1 引脚经 gmii_probe 板级修正为 demo 组, 见上)
- [x] 任务#2 复制工程
- [x] 任务#3 HLS set_part 全部改完
- [x] 任务#4 wrapper.v (RGMII IDDR/ODDR) + XDC (demo PHY1 引脚组 + PHY2 变体)
- [x] 任务#5 HLS 综合: UART (Latency 0 ✓, ?ip=192.168.100.2 + TB 同步), NET (csim+csynth+export ✓)
  - 附带修复: TB ICMP dst_mac 检查偏移少 8 字节 preamble
- [x] 任务#6 Vivado bitstream ×2 (PHY1 + PHY2 变体)
- [x] 任务#7 烧录 + ?mac ✅ **UART console 板级 PASS** (9.5 位元修复后)
- [~] 任务#8 gmii_probe: 探针本身 ✅ (UART 报告干净); 引脚真相已定 (demo 组);
  链路验证 ⏸ 等用户插网线 (两个 PHY 都无链接, ping 零帧)
- [ ] 任务#9 ping/UDP/TCP 迭代 — 等网线; 指南在 udp_hls_eco/网络验证指南.md
