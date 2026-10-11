#!/bin/bash
# aux_udp_probe2.sh -- 辅助探针 2 (顺序修正版): 先查 ARP/邻居 + 先恢复 carrier, 再发 UDP 探针
#   目的: 分清上一探针的"无泛洪"是 (a) 包根本没出宿主 (ARP/邻居) 还是 (b) 板侧没学/没发
#   判据量: ① ip neigh (192.168.100.2 是否 REACHABLE) ② 板侧 W11 (udpapp_rx_bytes) Δ ≠ 0 证"板收到了"
#           ③ NIC port_rx_bytes Δ (泛洪是否起) ④ 收尾回 0x08=0x2
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p9_final_board_20261012
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY D:/repo/XCKU5PMini/udp_hls_10g/tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
D=/tmp/p9_final
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW"; exit 3; }
exec > >(tee "$OUT/runs/AUX_UDP_PROBE2_$(date +%Y%m%d_%H%M%S).txt") 2>&1
snap(){ $SSH --sudo "cd $D && NW=71 EXPECT_BID=0x00000023 bash ./p7b_snap.sh snap $1 $2 $3 2>&1 | tail -5"; }

echo "=== AUX2_BEGIN $(date +%s.%N)"
echo "--- ① 邻居表 / 路由 / NIC ---"
$SSH "ip neigh show 192.168.100.2; ip neigh show dev enp1s0f1np1; ip route get 192.168.100.2; echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier"
echo "--- ② 先恢复 carrier (0x08=0) ---"
$SSH --sudo "$T/reg_rw /dev/xdma0_user 0x08 w 0x0 2>&1 | tail -1"
sleep 3
$SSH "echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier; echo -n 'LINK='; ethtool enp1s0f1np1 | grep -o 'Link detected: .*'"
echo "--- ③ 起测前 W11/W13 (板侧 UDP app 账) ---"
snap pre 11 13 52
echo "--- ④ 发 UDP 探针 (8081; 4096 B) ---"
$SSH --sudo "cd $D && timeout -k 5 20 ./p7b_udp_src --host 192.168.100.2 --port 8081 --bytes 4096 --mbps 1 --batch 1 --paylen 64 --off 0 --seconds 3 2>&1 | grep -E 'UDP_SUM|FATAL' | head -3"
echo "--- ⑤ 探针后 W11/W13 + 邻居表 ---"
sleep 1
snap post 11 13 52
$SSH "ip neigh show 192.168.100.2"
echo "--- ⑥ NIC 3 s 窗 (泛洪是否起) ---"
$SSH "ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'; sleep 3; echo '-- 3s later --'; ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'"
echo "--- ⑦ 收尾: 0x08=0x2 + 冻结复核 + 寄存器 ---"
$SSH --sudo "$T/reg_rw /dev/xdma0_user 0x08 w 0x2 2>&1 | tail -1"
sleep 3
$SSH "echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier; ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes'; sleep 2; echo '-- 2s later --'; ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes'"
$SSH --sudo "T=$T; echo -n 'SCRATCH_0x08='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1; echo -n 'MIR_CTRL_0x144='; \$T/reg_rw /dev/xdma0_user 0x144 w 2>&1 | tail -1; echo -n 'BID_0x04='; \$T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1"
echo "=== AUX2_END $(date +%s.%N)"
