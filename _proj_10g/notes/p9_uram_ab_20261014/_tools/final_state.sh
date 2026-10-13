#!/bin/bash
# final_state.sh -- 0x24 板级轮收尾 (改自 p9_rate_20261013/_tools/final_state_rt.sh; 换 0x24 几何/身份/目录):
#   ① NIC 收速率 (2 s 窗) ② 写 0x08=0x2 (受控停流) ③ MIR_CTRL=0 (功能位归零, 含 clr 翻转位处理)
#   ④ 停流后 NIC (逐字冻结?) + carrier/link ⑤ 终态寄存器 ⑥ 快照 ⑦ 残留进程 ⑧ 只读核对 (p7b_biz) ⑨ dmesg
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
D=/dev/xdma0_user
DD=/tmp/p9_uram_ab
echo "=== FINAL_STATE_BEGIN $(date +%s.%N)"
echo "--- ① 停流前 NIC 收速率 (2 s 窗) ---"
ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'
sleep 2; echo '-- 2s later --'
ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'
echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier
echo "--- ② 写 0x08 = 0x2 (受控停流) ---"
$T/reg_rw $D 0x08 w 0x2 2>&1 | tail -1
echo "--- ③ 写 MIR_CTRL(0x144) = 0 (功能位全 0; bit1 写 0 = 无 clr 翻转) ---"
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
echo -n 'MARKER_0x14='; $T/reg_rw $D 0x14 w 2>&1 | tail -1
echo -n 'MIR_STATUS_0x13C='; $T/reg_rw $D 0x13C w 2>&1 | tail -1
echo -n 'MIR_CTRL_0x144='; $T/reg_rw $D 0x144 w 2>&1 | tail -1
echo -n 'MIR_DMA_CNT_0x148='; $T/reg_rw $D 0x148 w 2>&1 | tail -1
echo -n 'UNIMPL_0x14C='; $T/reg_rw $D 0x14C w 2>&1 | tail -1
echo "--- ⑥ 快照 (触发式, 关键字) ---"
cd "$DD" && NW=71 EXPECT_BID=0x00000024 bash ./p7b_snap.sh snap final 0 1 5 11 13 43 70 53 54 2>&1 | tail -14
echo "--- ⑦ 残留进程 (对端) ---"
ps -eo pid,user,comm,args --no-headers | grep -E 'p7b_|mir_dump|udp_src|tcp_src|tcp_sink|tcpdump' | grep -v grep; echo PROC_SCAN_DONE
echo "--- ⑧ 只读核对 (/tmp/p7b_biz 未被动过) ---"
md5sum /tmp/p7b_biz/p7b_mir_dump /tmp/p7b_biz/p7b_mir_dump.cpp /tmp/p7b_biz/p7b_udp_src /tmp/p7b_biz/p7b_snap.sh
echo "--- ⑨ dmesg 尾部 ---"
dmesg | wc -l; dmesg | tail -6
echo "--- ⑩ 网络面 ---"
nmcli -g GENERAL.STATE device show enp1s0f1np1
ethtool -c enp1s0f1np1 2>/dev/null | grep -E 'Adaptive RX|rx-usecs:' | head -3
ip -4 addr show enp1s0f1np1 | grep inet
echo "=== FINAL_STATE_END $(date +%s.%N)"
