#!/bin/bash
# 02_net.sh -- 对端网络前置 (每次重来; 配方 = P7B_WU_LOOP_RECON §4.4 + p7b_env_restore/02+03)
#   /32 + 路由(src) + nmcli managed no (防 NM 冲掉) + 中断合并按口径 (跑长流必须 off: #68)
#   见证: ip route get 必须走 enp1s0f1np1 (不走 WiFi) / carrier / coalesce 前后。
#   用法: PEER_PW=<pw> bash 02_net.sh
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
ROOTW=D:/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p9_bench_restore_20261013
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY $ROOTW/tools/peer_ssh.py"
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW"; exit 3; }
exec > >(tee "$OUT/02_net_$(date +%Y%m%d_%H%M%S).txt") 2>&1

echo "=== NET_BEGIN $(date +%s.%N) $(date)"
echo "--- 0) 改前实录 ---"
$SSH "ip -br addr show enp1s0f1np1; echo '--- route table ---'; ip route show | head -8; echo '--- coalesce BEFORE ---'; ethtool -C enp1s0f1np1 2>&1 | grep -E 'Adaptive RX|rx-usecs:|rx-usecs-irq'"

echo "--- 1) 配置 (sudo) ---"
$SSH --sudo "ip link set enp1s0f1np1 up; \
  ip addr add 192.168.100.100/32 dev enp1s0f1np1 2>&1; \
  ip route add 192.168.100.2/32 dev enp1s0f1np1 src 192.168.100.100 2>&1; \
  nmcli device set enp1s0f1np1 managed no 2>&1; \
  echo SUDO_CFG_DONE; \
  ethtool -C enp1s0f1np1 adaptive-rx off rx-usecs 0 2>&1; echo SET_COALESCE_RC=\$?"

echo "--- 2) 见证 (现取) ---"
$SSH "echo '--- ip -br addr ---'; ip -br addr show enp1s0f1np1; \
  echo '--- ip route get 192.168.100.2 (必须 dev enp1s0f1np1, 不许走 WiFi) ---'; ip route get 192.168.100.2; \
  echo '--- route table (192.168.100) ---'; ip route show | grep 192.168.100; \
  echo '--- carrier ---'; cat /sys/class/net/enp1s0f1np1/carrier; \
  echo '--- operstate ---'; cat /sys/class/net/enp1s0f1np1/operstate; \
  echo '--- nmcli state ---'; nmcli -g GENERAL.STATE device show enp1s0f1np1 2>/dev/null; \
  echo '--- coalesce AFTER ---'; ethtool -C enp1s0f1np1 2>&1 | grep -E 'Adaptive RX|rx-usecs:|rx-usecs-irq'; \
  echo '--- ethtool link ---'; ethtool enp1s0f1np1 2>/dev/null | grep -E 'Speed|Link detected'; \
  echo '--- irqbalance ---'; systemctl is-active irqbalance 2>&1"
echo "=== NET_END $(date +%s.%N)"
