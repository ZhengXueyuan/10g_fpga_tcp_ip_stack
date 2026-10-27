#!/bin/bash
# ab_arm_occ.sh -- P11 APP8 OCC A/B board arm (DRAFT; not executed 2026-10-28)
#   ⛔ 0x34/0x35 均未过时序门 ⇒ 无位流，本脚本未执行。
#   Protocol = DESIGN_OCC_V6 §6.6: stall RX (0x08 bit2), conn0 sends 16KB, capture downlink windows.
#   Usage: PEER_PW=... python tools/peer_ssh.py --sudo "bash /tmp/ab_arm_occ.sh <tag> <bid> [secs]" (after --put)
# P11 APP8 0x34/0x35 board arm: RX stall + conn0 16KB send + continuous downlink capture.
# Runs as root (invoked via peer_ssh --sudo). Output dir /tmp/ab_<tag>.
set -u
TAG=${1:?tag}
BID=${2:?expect_bid}
SECS=${3:-12}
T=/tmp/ab_$TAG
TOOLS=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
mkdir -p "$T"
export NW=97
export EXPECT_BID=$BID
echo "ARM_BEGIN tag=$TAG bid=$BID secs=$SECS $(date +%s.%N)"
echo "=== id before ===" > "$T/id_before.txt"
bash /tmp/p7b_snap.sh id >> "$T/id_before.txt" 2>&1

# 1) RX stall (bit2=1, bits0/1=0 keeps TX enabled)
$TOOLS/reg_rw /dev/xdma0_user 0x08 w 0x4 > "$T/stall_on.txt" 2>&1
sleep 0.2

# 2) capture board->peer downlink; start tool (conn0 sends 16KB after all connects)
NSB=enp1s0f0np0
ip netns exec nsb timeout $((SECS+6)) tcpdump -i $NSB -w "$T/dl.pcap" 'tcp and src host 192.168.100.4' > "$T/tcpdump.log" 2>&1 &
TCPD=$!
sleep 0.6
ip netns exec nsb timeout $((SECS+3)) /tmp/p7b_biz/p7b_tcp_sink_multi \
  --host 192.168.100.4 --port 8080 --conns 8 --maxbytes 8000000000 --seconds "$SECS" \
  --rcvbuf 1048576 --send-conns 1 --send-bytes 16384 --send-pattern xorshift \
  > "$T/sink.txt" 2>&1 &
SINK=$!

# 3) mid-run snapshot (W62 should be >= 12288 while RX is stalled)
sleep 4
bash /tmp/p7b_snap.sh snap > "$T/snap_mid.txt" 2>&1
echo "SNAP_MID_DONE $(date +%s.%N)"

wait $SINK; echo "SINK_RC=$?" > "$T/rc.txt"
wait $TCPD; echo "TCPD_RC=$?" >> "$T/rc.txt"

# 4) release stall, drain, final snapshot
$TOOLS/reg_rw /dev/xdma0_user 0x08 w 0x0 > "$T/stall_off.txt" 2>&1
sleep 0.5
bash /tmp/p7b_snap.sh snap > "$T/snap_after.txt" 2>&1
bash /tmp/p7b_snap.sh id > "$T/id_after.txt" 2>&1
echo "ARM_END tag=$TAG $(date +%s.%N)"
ls -l "$T"
