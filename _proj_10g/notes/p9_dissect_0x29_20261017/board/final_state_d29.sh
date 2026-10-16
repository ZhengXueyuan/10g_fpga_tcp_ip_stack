#!/bin/bash
# final_state_d29.sh -- 0x29 拆刀轮收尾态取证 (母本 = bisect 轮 FINAL_STATE 同族)
#   Usage: bash final_state_d29.sh <TAG> <NW> <EXPECT_BID> <UNIMPL>
set -u
TAG=${1:?usage: final_state_d29.sh TAG NW EXPECT_BID UNIMPL}; NW=${2:?}; BID=${3:?}; UNIMPL=${4:?}
cd /d/repo/XCKU5PMini/udp_hls_10g
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
IF=enp1s0f1np1
echo "=== FINAL_STATE ($TAG) $(date)"
$SSH --sudo "T=$T; echo -n 'BID_0x04='; \$T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1; echo -n 'SCRATCH_0x08='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1; echo -n 'MAGIC_0x00='; \$T/reg_rw /dev/xdma0_user 0x00 w 2>&1 | tail -1; echo -n \"UNIMPL_${UNIMPL}=\"; \$T/reg_rw /dev/xdma0_user ${UNIMPL} w 2>&1 | tail -1; echo -n 'CARRIER='; cat /sys/class/net/$IF/carrier; echo -n 'ROUTE_GET='; ip route get 192.168.100.2 | head -1; echo -n 'ADAPTIVE_RX='; ethtool -c $IF 2>/dev/null | grep -E 'Adaptive RX|rx-usecs:' | tr '\n' ' '; echo; nmcli device show $IF 2>/dev/null | grep -i managed; lspci -vvv -s 02:00.0 2>/dev/null | grep -E 'LnkSta:'"
echo "--- NIC_FINAL ---"
$SSH --sudo "ethtool -S $IF 2>/dev/null | grep -E '^ +(port_rx_good_bytes|port_rx_packets|port_rx_bad|rx_eth_crc_err|rx_nodesc_drops):'"
echo "--- board-side snapshot id ---"
$SSH --sudo "NW=$NW UNIMPL_ADDR=$UNIMPL EXPECT_BID=$BID bash /tmp/p7b_biz/p7b_snap.sh id; echo ID_RC=\$?"
echo "--- leftover procs ---"
$SSH "pgrep -a p7b_tcp_sink; pgrep -a tcpdump; echo '(空=无残留进程)'"
echo "=== FINAL_STATE_END $(date) ==="
