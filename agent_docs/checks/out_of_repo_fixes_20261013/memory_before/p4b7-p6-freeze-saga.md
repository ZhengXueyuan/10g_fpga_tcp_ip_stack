---
name: p4b7-p6-freeze-saga
description: P4b-7 P6 板级冻结五层根因剥除的完整经过与重启恢复点
metadata: 
  node_type: memory
  type: project
  originSessionId: a43dc219-6b2c-4721-bd7a-260ae74f7393
  modified: 2026-09-12T06:50:02.603Z
---

# P4b-7 P6 板级冻结破案（五层根因，最后一层修复在途）

项目 udp_hls_10g（纯 RTL TCP fast path，ECO 板 Kintex-7）。P4b-7 快速重传
里程碑 P1-P5 全绿（提交 542689d 本地，推送未遂），P6 板级重建遇 WNS 不收敛
+ 速率测试冻结，逐层剥除：

1. **16 位门控 64K 跨界误关**（P6 时序优化自引入）：`hi_eq && 低16差<帽` 在
   在飞跨越任何 64K 边界时误关死 → 修：tcb win 口回归 32 位回绕安全比较
   （寄存器化保住时序）。sim 的快速 ACK 模型掩盖了级联（strad=3878 拍佐证）。
2. **tcp_rx drain 重启丢推进**（P4b-5/6 遗留）：新 fend 整体重启 drain 并重锁
   pend_* → 背靠背纯 ACK 小帧下推进永久丢失 → 修：pend 粘性置位/gnt 落写才清。
3. **frame_fifo 全 LUTRAM 时序炸**（WNS -2.9）：73 位宽超 BRAM36 上限 → 修：
   主存 RAMB36E1 原语直例化（WRITE_FIRST SDP，DOA_REG=0，地址位段 RAMB36
   [14:6]/RAMB18 [13:5]，ENARDEN 恒 1，glbl+unisims_ver 进 bat）。
4. **svc/rb_id 长链**（WNS -1.4）：rto_pend→prio_lo→rb_id→TCB→wnd 比较→
   accept→retx 写口 19 级 → 修：svc_id_r/rto_pend_any/ack_pend_r 寄存器化 +
   scan 改自由 tick（RTO_LIM 重标定 48828/125）。
5. **tlast 丢失**（未破）：UART 快照实锤（TX S_RECV 收满 256 词未 tlast、
   PF=1、echo 滞留 921 词）。侧存 RAMB18E1 嫌疑已排除（混合结构=侧存退回
   LUTRAM 寄存器读，sim 全绿但板测仍冻结）。**下一轮探针**：echo 的
   fdout[72]（fifo dout tlast 位）+ tx 的 s_axis_tlast 直入 UART 快照，
   定位 tlast 死在 echo 出口 / axis_pipe / tx 入口哪一段；备选：pipe 边沿
   行为与 echo FWFT 弹出对齐。

## 诊断方法论沉淀（本轮最有价值的部分）

- **UART 快照 > LED 探针**：4 LED 读数反复歧义/矛盾（双色 LED、丝印映射、
  人眼读动态信号），UART 9600-8N1 全精度十六进制快照一次到位。板有 CH340
  （A17 引脚、COM8），PowerShell System.IO.Ports 读取，冻结后每 5s 重复行。
- **逐层剥除节奏**：修一层→板测→读快照→下一层，每层根因都被"sim 全绿"
  掩盖（宽松 ACK 模型、无时序、无真实帧模式），板上快照是唯一裁决。
- **时序优化引入语义回归的双重教训**：16 位化论证漏 64K 边界；修时序的
  换原语动作引入 tlast 板-模差异。任何"优化"都要做语义回归测试 + 板级验证。

## 恢复点

PORT_NOTES.md 末尾有会话存档点（含重启后待办 1-4）。关键配方：UART 读取
PowerShell 命令、run_build_p4.bat/run_program_p4.bat、p4b7_synscan.py
抓包解析、GATEPROBE 门控失配探测器（tb_p4_chain.v 内）。提交规范：-c
user.name/email、显式 refspec、ls-remote 验证；GitHub 当时网络不可达需重试。

## 第二轮会话 (2026-09-11/12) 追加

- 冻结层层剥除到第十三层: ①tlast 未丢 (TW/TF/TI 对账) ②pay FIFO 真满
  (指针裁决) ③TX 在 S_IDLE/S_RECV 间循环 (回卷触发轨迹) ④FIFO 侧存
  tlast 位图: 帧尾在 rptr+5 处存在 ⑤RX emit 轨迹: 触发帧 = 7 头词+1 载荷
  词就 fend — **62 字节真实帧 + 总长字段 1500 + FCS 有效** ⑥三站计数
  (mac/classify/tcp_rx) 零丢词 + wcnt 正常 — 帧真短, 线缆上就是个怪帧。
- **WL 线长探针已构建未读** (PHY rx_ctl 高电平计数, 异常触发锁存):
  WL=66 → PC 发的怪帧; WL=1518 → RGMII 桥吞中段。
- **PC 侧链路修复配方** (板断电重启后): 静态 IP 丢失 → netsh 重配 +
  ping -S 强制源 + 静态 ARP (netsh interface ip add neighbors
  "以太网 2" 192.168.100.2 00-0a-35-01-fe-c0) + 测试脚本 s.bind 补丁。
- **新阻塞: HLS 慢路径从启动即死** (wire-counter 构建起; 重烧不愈;
  diag15 及之前的构建正常)。重启后第一步: 回退 wire-counter 二分定位
  wrapper 哪处杀了 HLS。

## 第三轮会话 (2026-09-12 上午) 追加

- **HLS 死亡确诊非伪影**: 重烧两次 (10:31/10:35) PROGRAM_OK; LED boot 自检
  3 闪可见 → FPGA 活着、gmii_clk 正常; PktMon 20s 板上 MAC 零帧 (连 ~5s
  一次的 UDP HELLO 都没有) → HLS 主循环从未运行; UART 静默 (latched=0)。
  已排: PC 残留连接 (netstat 无)、静态 IP/ARP 完好、慢路径适配器 diff 仅
  tie-off、HLS 实例接线未变、看门狗老代码、HLS 导出 8-30 未变、时序全绿。
- **diag18 二分构建**: ①wire counter 回退 (phy1_rxc 域删除 — diag15→17
  唯一新时钟域; WL 改 gmii_clk 域 e_rxdv 高拍计数, 判别力不变) ②UART
  boot 行 (uart_run = latched || boot_h==6, ~1.2s 后每 5s 一行, 不再依赖
  回卷) ③行尾慢路径字段 SC/SD/SF/SP/SV/HR (slow_rx/slow_tx 计数 + 看门狗
  starv + hls_rst_n 实时) ④xvlog 声明顺序修正 + uart_dbg 新字段避开既有
  sv_l/v_sv 名 (改名 srv_l/v_srv)。
- **判读表**: HELLO 恢复 = wire counter 域是杀手; 否则 SV 周期归零 = 看门狗
  循环复位 HLS, HR=0 恒 = HLS 卡复位, SC/SF=0+SV=0+HR=1 = HLS 内部死。
- **板测工具**: tools/board_diag18_test.py (COM8 读 N 秒 + pktmon comp 102
  并行抓包 + 板 MAC 计数); COM8 已验证可开 (旧位流下静默正常)。
- **教训**: PHY 链路 Up 不证明 FPGA 工作 (PHY 独立自协商); pktmon txt 是
  UTF-16LE (iconv 转码才能 grep); etl2txt 覆盖旧 PktMon.txt。

## 第四轮 (2026-09-12 下午): 双谜题全破 + 里程碑收官 (提交 122b0c0 已推送)

- **冻结根因破案**: tcp_rx 截断支静默吞尾 (pop8w<pay_r 时无 fend 无
  emit_l=1) → echo 帧永不判尾 → 后续帧合并无尽帧 → TX 卡死。修复:
  截断帧按真实字节闭合/推进 (adv_cnt), w6 截断 fend_w6t, stat_drop_trunc
  (UART TRU 字段)。审查 agent 另抓 tcp_echo judged 拍 has_data 同拍冲突
  (P1-7) 等 6 项已修。
- **怪帧源**: WL=72 字节实锤 PC 侧 (offload 全关仍偶发, drop_seq 恒 13
  确定性; Killer E5000B NIC/栈嫌疑, 未定案)。修复后无害 (自愈)。
- **板级 100MB 全通**: 126.9/127.0 Mbps 完整收齐, 零冻结, 563 自愈事件。
  全矩阵 19 用例绿 (唯一红门 TXDROP=200 = checker 判据过窄, conn1 独立
  自愈为正确行为, 按连接语义修正)。
- **RXTR 触发器坑**: plen_l=0 纯 ACK 误触发 (pcount=0 < 0-4) → WL 锁存
  污染; 已修 (plen_l!=0 排除)。**读旧 WL 值时先判 RXTR 触发帧类型**。
- **新工具**: Wireshark 4.6.8 + tshark (接口 8=以太网 2); capture_rate_test.ps1
  (怪帧过滤 ip.len==1500&&frame.len<100 + 重传统计); 板 MAC 在 txt 大写。
- **TXDROP 是位置参数 %8 不是环境变量** (TRUNC/TRUNCM 才是环境变量);
  `200 0 0 400` 门控应力已弱化 (PCACK inj_wnd=0x4000 覆盖 snd_wnd),
  要门控应力用 %4=10。
- **遗留**: w6 截断支无 TB 用例 (60B 填充不可激励侧构造); 怪帧 PC 侧根因;
  wrapper_tcp.v P3 目标端口过时; 113 条 RAMB36E1 Memory Collision 报错
  属 FWFT 写穿既有现象; 诊断脚手架保留为长期接口。

## 第五轮 (2026-09-12 傍晚): 怪帧证伪 + 冻结第三机制修复 (提交 96092c5 已推送)

- **怪帧证伪**: 冻结轮 PktMon 抓包零怪帧 (PC 发送全规范) — 旧"62B 怪帧"
  解读 = RXT 环误读 + RXTR 触发器纯 ACK 误触发混读。真触发源 = **强杀
  npcap 抓包进程 → Killer E5000B 网卡驱动重启** (pktmon 组件 ID 102→239
  实证; 复现率 ~75%): 驱动重启 RX 盲区丢 echo 帧 → PC dup-ACK/重传风暴
  (**drop_seq 恒 13** 确定性签名) → HLS 被看门狗复位 (DHCP DISCOVER×3 中
  段出现实证) → PC RST。
- **冻结第三机制**: 驱动重启 TX DMA 中断 → 线缆无 tlast 半帧 → mac_rx 中止
  → RX SOP 防御救己不救 echo → echo 半帧不判尾 → 合并巨帧 → TX 卡死。
  修复: S_PAY 见 SOP 拍合成 ferr 尾拍 (fend_trunc) 闭合 echo 半帧 (回卷),
  新帧 w0 牺牲 (PC 重传补回), pend_rcv/dup/ack_adv 屏蔽陈旧 acc_l。
- **TB 四门矩阵** (无注入/TRUNC/HALFDROP/chain + TXDROP/门控): 10/10 绿,
  HALFD TXSTUCK 241113→0, 无注入 resp md5 逐位不变。板级强杀复现法
  5/5 全过 (124-157 Mbps, 42 重复段+91 异常段全消化)。
- **教训**: ①注入类 TB 改动必须跑全门矩阵 (实现 agent 的 gen_stim if/elif
  重构把截断帧 add() 挂掉 → TRUNC 回归裸奔一轮才被 TL 抓到) ②抓包进程
  用优雅停止 (tshark -a duration), 强杀会重启网卡驱动毒化链路 ③板级
  "恒 13" 类确定性常数 = 对端栈特定行为签名, 优先怀疑对端而非噪声。
- **pktmon 组件 ID 会变** (驱动重挂后 102→239), 抓包前先 comp list。
