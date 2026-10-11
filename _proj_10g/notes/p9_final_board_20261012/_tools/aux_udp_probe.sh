#!/bin/bash
# aux_udp_probe.sh -- 辅助探针 (T1/T2 之外的登记项): 本轮全程**未观测到** UDP 泛洪背景
#   (NIC port_rx_bytes 2 s 窗逐字不动; 全程增量 ~5.6 MB/5.5 min ≈17 KB/s, 与 809k fps 差 4 个量级)
#   ⇒ 探针: 从对端发一个**小 UDP 包**给板 (8081) 看板是否开始泛洪 (判"peer 表是否为空")
#   ① 停流态 (0x08=0x2) 下发探针 —— 若 learn 成功但 carrier=0 ⇒ NIC 应仍不动
#   ② 恢复 carrier (0x08=0) ⇒ 若 peer 表已填 ⇒ 泛洪应起 (NIC 计数跳 809k fps 量级)
#   ③ 立刻收尾: 0x08=0x2 + 复核 NIC 冻结
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p9_final_board_20261012
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY D:/repo/XCKU5PMini/udp_hls_10g/tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
D=/tmp/p9_final
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW"; exit 3; }
exec > >(tee "$OUT/runs/AUX_UDP_PROBE_$(date +%Y%m%d_%H%M%S).txt") 2>&1

echo "=== AUX_BEGIN $(date +%s.%N)"
$SSH "cd $D && cp /tmp/p9_board_0x23/p7b_udp_src ./ && md5sum p7b_udp_src /tmp/p9_board_0x23/p7b_udp_src"
echo "--- 探针前基线 (NIC 2 s 窗 + CARRIER) ---"
$SSH "ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'; sleep 2; echo '-- 2s later --'; ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'; echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier"

echo "--- ① 发小 UDP 探针 (8081; 64 B × 少量; 停流态下) ---"
$SSH --sudo "cd $D && timeout -k 5 20 ./p7b_udp_src --host 192.168.100.2 --port 8081 --bytes 4096 --mbps 1 --batch 1 --paylen 64 --off 0 --seconds 3 2>&1 | grep -E 'UDP_SUM|PIN_CPU|FATAL|SRC' | head -6"
sleep 2
echo "--- ② 恢复 carrier (0x08=0) 后看泛洪是否起 (3 s 窗) ---"
$SSH --sudo "$T/reg_rw /dev/xdma0_user 0x08 w 0x0 2>&1 | tail -1"
sleep 3
$SSH "ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'; sleep 3; echo '-- 3s later --'; ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'; echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier"

echo "--- ③ 收尾: 0x08=0x2 (受控停流) + 冻结复核 ---"
$SSH --sudo "$T/reg_rw /dev/xdma0_user 0x08 w 0x2 2>&1 | tail -1"
sleep 4
$SSH "ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'; sleep 2; echo '-- 2s later --'; ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets'; echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier"
echo "--- 板上寄存器复核 ---"
$SSH --sudo "T=$T; echo -n 'SCRATCH_0x08='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1; echo -n 'MIR_CTRL_0x144='; \$T/reg_rw /dev/xdma0_user 0x144 w 2>&1 | tail -1; echo -n 'BID_0x04='; \$T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1"
echo "=== AUX_END $(date +%s.%N)"
