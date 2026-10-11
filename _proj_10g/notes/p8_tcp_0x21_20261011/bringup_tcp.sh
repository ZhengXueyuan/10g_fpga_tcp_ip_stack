#!/bin/bash
# bringup_tcp.sh -- 恢复 carrier=1 + 网络面现取 + 背景泛洪见证 + 临时 fq 根 qdisc (定速前置)
#   可回退: fq 用 `tc qdisc del dev enp1s0f1np1 root` 撤销; 0x08 恢复受控停流见 final 脚本。
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p8_tcp_0x21_20261011
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY D:/repo/XCKU5PMini/udp_hls_10g/tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW"; exit 3; }
exec > >(tee "$OUT/runs/BRINGUP_TCP_$(date +%Y%m%d_%H%M%S).txt") 2>&1
echo "### BRINGUP_BEGIN $(date +%Y-%m-%dT%H:%M:%S%z)"
echo "--- A) 恢复 carrier (= 写 0x08 = 0; 板侧 TX_DIS 门释放) ---"
$SSH --sudo "T=$T; \$T/reg_rw /dev/xdma0_user 0x08 w 0x0 2>&1 | tail -1; echo -n 'R_0x08='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1"
sleep 5
echo "--- B) 链路/网络面现取 ---"
$SSH "echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier; ip -4 addr show enp1s0f1np1 | grep -E 'inet |state'; ethtool enp1s0f1np1 | grep -E 'Speed|Link detected'; echo ---; ip route get 192.168.100.2 | head -2; echo ---; ip neigh show 192.168.100.2"
echo "--- C) 背景泛洪见证 (NIC port_rx 2 s 差分; 板侧 W43/W20 两次读) ---"
$SSH "ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets|rx_packets|rx_bytes'; sleep 2; echo '--- 2s later ---'; ethtool -S enp1s0f1np1 | grep -E 'port_rx_bytes|port_rx_packets|rx_packets|rx_bytes'"
$SSH --sudo "T=$T; echo -n 'W43a=';\$T/reg_rw /dev/xdma0_user 0xCC w 2>&1 | tail -1; echo -n 'W20a=';\$T/reg_rw /dev/xdma0_user 0x70 w 2>&1 | tail -1; sleep 2; echo -n 'W43b=';\$T/reg_rw /dev/xdma0_user 0xCC w 2>&1 | tail -1; echo -n 'W20b=';\$T/reg_rw /dev/xdma0_user 0x70 w 2>&1 | tail -1"
echo "--- D) 临时 fq 根 qdisc (SO_MAX_PACING_RATE 生效前置; mq+fq_codel 下被忽略) ---"
$SSH --sudo "tc qdisc replace dev enp1s0f1np1 root fq && echo FQ_OK; tc qdisc show dev enp1s0f1np1 | head -3"
echo "### BRINGUP_END $(date +%Y-%m-%dT%H:%M:%S%z)"
