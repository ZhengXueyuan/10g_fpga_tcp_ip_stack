#!/bin/bash
# p1b_s2.sh -- S-2: inject N known Ethernet frames on p0 (board ch0) and read ch0 counters.
#   usage: p1b_s2.sh [N] [PAYLEN]     (default 2000 / 114 => content 128 B, wire 132 B)
#   root required (AF_PACKET + /dev/xdma0_user).  Never touches QSPI.
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
S=/tmp/p1b_snap.sh
IF=enp1s0f0np0
N=${1:-2000}
PAY=${2:-114}
echo "=== P1BOARD-S2 $(date +%s.%N) $(date) N=$N PAY=$PAY content=$((14+PAY)) wire=$((18+PAY)) ==="
echo "--- NIC counters PRE ---"
ethtool -S $IF | grep -E 'port_tx_(bytes|packets|unicast|multicast|broadcast)'
echo "--- SNAP PRE ---"
bash $S snap S2_PRE 76 77 78 79 80 81 82
echo "--- tcpdump arm ---"
rm -f /tmp/p1b_S2.pcap /tmp/p1b_S2_tcpdump.log
timeout -s INT 20 tcpdump -i $IF -q -c $((N+200)) -w /tmp/p1b_S2.pcap 'ether proto 0x88b5' > /tmp/p1b_S2_tcpdump.log 2>&1 &
TP=$!
for i in $(seq 1 100); do grep -q 'listening on' /tmp/p1b_S2_tcpdump.log && break; sleep 0.1; done
sleep 1
echo "--- send ---"
python3 /tmp/p1b_rawsend.py $IF $N $PAY
sleep 2
kill -INT $TP 2>/dev/null; sleep 1; kill -9 $TP 2>/dev/null
echo "--- tcpdump log ---"; cat /tmp/p1b_S2_tcpdump.log
echo -n 'PCAP_FRAMES='; tcpdump -r /tmp/p1b_S2.pcap 2>/dev/null | wc -l
echo "--- NIC counters POST ---"
ethtool -S $IF | grep -E 'port_tx_(bytes|packets|unicast|multicast|broadcast)'
echo "--- SNAP POST ---"
bash $S snap S2_POST 76 77 78 79 80 81 82
echo "=== P1BOARD-S2-END $(date +%s.%N) ==="
