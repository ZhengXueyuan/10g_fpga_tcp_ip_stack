#!/bin/bash
# read_final_state.sh -- p9_mdio_aplus_board_20261016 final readings
#   (board state / NIC witness / deployment fingerprints / leftover processes).
#   Adapted from B4 env/read_final_state.sh; PW discipline: PEER_PW read once, unset,
#   per-command env prefix only.
#   Usage: PEER_PW=<pw> bash read_final_state.sh <TAG>
set -u
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
ROOTW=D:/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p9_mdio_aplus_board_20261016/board
TAG=${1:-FINAL}
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY $ROOTW/tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
PW=${PEER_PW:?PEER_PW required}
unset PEER_PW
exec > >(tee "$OUT/FINAL_STATE_$TAG.txt") 2>&1
echo "=== FINAL_STATE_BEGIN $TAG $(date +%s.%N) $(date)"
echo "--- board side (board = the card in the peer PCIe slot) ---"
PEER_PW="$PW" $SSH --sudo "T=$T; echo -n 'MAGIC_0x00='; \$T/reg_rw /dev/xdma0_user 0x00 w 2>&1 | tail -1; \
  echo -n 'BID_0x04=';   \$T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1; \
  echo -n 'MARKER_0x14='; \$T/reg_rw /dev/xdma0_user 0x14 w 2>&1 | tail -1; \
  echo -n 'UNIMPL_0x15C='; \$T/reg_rw /dev/xdma0_user 0x15C w 2>&1 | tail -1; \
  echo -n 'SCRATCH_0x08='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1; \
  NW=75 EXPECT_BID=0x00000028 bash /tmp/p7b_biz/p7b_snap.sh id; echo ID_RC=\$?"
echo "--- snapshot tail (E12 counters) ---"
PEER_PW="$PW" $SSH --sudo "NW=75 EXPECT_BID=0x00000028 bash /tmp/p7b_biz/p7b_snap.sh snap FINAL 71 72 73 74 51 20 5; echo SNAP_RC=\$?"
PEER_PW="$PW" $SSH --sudo "lspci -vvv -s 02:00.0 2>/dev/null | grep -E 'LnkSta:'; ls /dev/xdma0_user /dev/xdma0_c2h_0 /dev/xdma0_h2c_0 /dev/xdma0_control 2>&1"
echo "--- NIC witness ---"
PEER_PW="$PW" $SSH "ip route get 192.168.100.2 | head -1; echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier; echo; \
  ip -4 addr show enp1s0f1np1 | grep inet; nmcli device status | grep enp1s0f1np1; \
  ethtool enp1s0f1np1 | grep -E 'Speed|Link detected'; ethtool -c enp1s0f1np1 | grep -E 'Adaptive RX|rx-usecs:'"
echo "--- leftover processes (this round started none on the peer) ---"
PEER_PW="$PW" $SSH --sudo "pgrep -af '[p]7b_' || echo NO_P7B_PROCS; pgrep -af '[t]cpdump' || echo NO_TCPDUMP; pgrep -af '[k]0_' || echo NO_K0"
echo "--- deployment fingerprints (peer, current) ---"
PEER_PW="$PW" $SSH "cd /tmp/p7b_biz && md5sum p7b_snap.sh 2>&1; ls /tmp/p7b_biz | wc -l"
echo "=== FINAL_STATE_END $TAG $(date +%s.%N) ==="
