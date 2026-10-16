#!/bin/bash
# nic_setup.sh -- B4 轮: 对端 NIC 前置 (四行配方 + 见证打印)
#   配方 = B1 轮 §2.3 (逐字): up / 100.100-32 / route 单点 / nmcli managed no / 中断合并 off
#   ⚠️ 每次重启重做; 每次测量前仍要**现取** `ip route get 192.168.100.2` 当见证
set -u
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
ROOTW=D:/repo/XCKU5PMini/udp_hls_10g
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY $ROOTW/tools/peer_ssh.py"
IF=enp1s0f1np1

echo "=== NIC_SETUP_BEGIN $(date +%s.%N) $(date) ==="
$SSH --sudo "ip link set $IF up; ip addr add 192.168.100.100/32 dev $IF 2>&1 | grep -v 'RTNETLINK answers: File exists' || true; \
  ip route add 192.168.100.2/32 dev $IF 2>&1 | grep -v 'RTNETLINK answers: File exists' || true; \
  nmcli device set $IF managed no 2>&1; \
  ethtool -C $IF adaptive-rx off rx-usecs 0 2>&1; echo SETUP_DONE"
echo "--- 见证 (现取) ---"
$SSH "ip route get 192.168.100.2 | head -1; echo -n 'CARRIER='; cat /sys/class/net/$IF/carrier; echo; \
  ip -4 addr show $IF | grep inet; nmcli device status | grep $IF; \
  ethtool $IF | grep -E 'Speed|Link detected'; ethtool -c $IF | grep -E 'Adaptive RX|rx-usecs:'; \
  systemctl is-active irqbalance"
echo "=== NIC_SETUP_END $(date +%s.%N) ==="
