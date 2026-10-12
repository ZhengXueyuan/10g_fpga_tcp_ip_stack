#!/bin/bash
# final_state_rt.sh -- 线速档补测收尾 (改自 p9_final/_tools/final_state.sh):
#   ① NIC 收速率 (2 s 窗, 确认泛洪在跑) ② 写 0x08=0x2 (受控停流) ③ MIR_CTRL=0
#   ④ 停流后 NIC (逐字冻结?) + carrier/link ⑤ 终态寄存器 ⑥ 快照 ⑦ 残留进程 ⑧ 只读核对 ⑨ dmesg
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
D=/dev/xdma0_user
echo "=== FINAL_STATE_BEGIN $(date +%s.%N)"
echo "--- ① 停流前 NIC 收速率 (2 s 窗) ---"
ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'
sleep 2; echo '-- 2s later --'
ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'
echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier
echo "--- ② 写 0x08 = 0x2 (受控停流) ---"
$T/reg_rw $D 0x08 w 0x2 2>&1 | tail -1
echo "--- ③ 写 MIR_CTRL(0x144) = 0 ---"
$T/reg_rw $D 0x144 w 0x0 2>&1 | tail -1
sleep 4
echo "--- ④ 停流后 NIC + carrier/link ---"
ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'
sleep 2; echo '-- 2s later --'
ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'
echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier
echo -n 'LINK='; ethtool enp1s0f1np1 | grep -o 'Link detected: .*'
echo "--- ⑤ 终态寄存器 ---"
echo -n 'MAGIC_0x00='; $T/reg_rw $D 0x00 w 2>&1 | tail -1
echo -n 'BID_0x04=';   $T/reg_rw $D 0x04 w 2>&1 | tail -1
echo -n 'SCRATCH_0x08='; $T/reg_rw $D 0x08 w 2>&1 | tail -1
echo -n 'MIR_STATUS_0x13C='; $T/reg_rw $D 0x13C w 2>&1 | tail -1
echo -n 'MIR_CTRL_0x144='; $T/reg_rw $D 0x144 w 2>&1 | tail -1
echo -n 'MIR_DMA_CNT_0x148='; $T/reg_rw $D 0x148 w 2>&1 | tail -1
echo -n 'UNIMPL_0x14C='; $T/reg_rw $D 0x14C w 2>&1 | tail -1
echo "--- ⑥ 快照 (触发式, 关键 8 字) ---"
cd /tmp/p9_rate && NW=71 EXPECT_BID=0x00000023 bash ./p7b_snap.sh snap final 53 54 70 11 13 5 43 20 2>&1 | tail -12
echo "--- ⑦ 残留进程 (对端) ---"
ps -eo pid,user,comm,args --no-headers | grep -E 'p7b_|mir_dump|udp_src|tcp_src|tcp_sink|tcpdump' | grep -v grep; echo PROC_SCAN_DONE
echo "--- ⑧ 只读核对 (/tmp/p7b_biz 与 /tmp/p9_board_0x23 皆未动) ---"
md5sum /tmp/p7b_biz/p7b_udp_src /tmp/p7b_biz/p7b_snap.sh /tmp/p7b_biz/p7b_pattern.h /tmp/p7b_biz/p7b_affinity.h /tmp/p9_board_0x23/p7b_mir_dump /tmp/p9_board_0x23/p7b_udp_src
echo "--- ⑨ dmesg 尾部 ---"
dmesg | wc -l; dmesg | tail -6
echo "--- ⑩ 网络面 ---"
nmcli -g GENERAL.STATE device show enp1s0f1np1
ethtool -c enp1s0f1np1 2>/dev/null | grep -E 'Adaptive RX|rx-usecs:' | head -3
ip -4 addr show enp1s0f1np1 | grep inet
echo "=== FINAL_STATE_END $(date +%s.%N)"
