#!/bin/bash
# env_pre.sh -- 0x24 板级轮网络前置 (配方 = p9_bench_redeploy_20261013/REPORT.md §5(a) + handoff §6-新块2 A.3)
#   /32 + nmcli unmanaged (防 NetworkManager 静默冲掉) + ethtool 中断合并关 (全局 #68)
#   全部现取见证 (ip route get 必须 dev enp1s0f1np1, 不许走 WiFi)
set -u
echo "=== ENV_PRE $(date +%s.%N)"
ip link set enp1s0f1np1 up
ip addr replace 192.168.100.100/32 dev enp1s0f1np1
ip route replace 192.168.100.2/32 dev enp1s0f1np1 src 192.168.100.100
nmcli device set enp1s0f1np1 managed no
ethtool -C enp1s0f1np1 adaptive-rx off rx-usecs 0
echo "--- 见证 (现取) ---"
ip -br addr show enp1s0f1np1
ip route get 192.168.100.2
echo -n "CARRIER="; cat /sys/class/net/enp1s0f1np1/carrier
nmcli -g GENERAL.STATE device show enp1s0f1np1
ethtool -c enp1s0f1np1 | grep -E 'Adaptive RX|rx-usecs'
echo "=== ENV_PRE_END $(date +%s.%N)"
