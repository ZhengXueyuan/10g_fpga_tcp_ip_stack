#!/bin/bash
# b4a_tx2port.sh -- P11 P2 B-4 Part A: simultaneous two-port TCP downlink (W83/W84 both advance)
set -u
I1=enp1s0f1np1; I0=enp1s0f0np0
S=/tmp/p2b_snap.sh
SINK=/tmp/p7b_biz/p7b_tcp_sink
TAG=${1:-B4A}
W="0 1 4 20 21 43 51 52 54 55 79 80 81 82 83 84 62"
echo "=== B4A_BEGIN tag=$TAG $(date +%s.%N) $(date)"
bash $S id; echo ID_RC=$?
echo "--- quiet check: two snapshots 1ms+ apart ---"
bash $S snap ${TAG}_Q1 83 84 20
bash $S snap ${TAG}_Q2 83 84 20
bash $S snap ${TAG}_PRE $W
ip netns exec nsa $SINK --host 192.168.100.2 --port 8080 --rcvbuf 2920 --conns 1 --maxbytes 1000000000 --check lane8 > /tmp/${TAG}_A1_sink.txt 2>&1 & SA=$!
ip netns exec nsb $SINK --host 192.168.100.4 --port 8080 --rcvbuf 2920 --conns 1 --maxbytes 1000000000 --check lane8 > /tmp/${TAG}_A0_sink.txt 2>&1 & SB=$!
sleep 2
bash $S snap ${TAG}_MID1 $W
sleep 5
bash $S snap ${TAG}_MID2 $W
for i in $(seq 1 60); do kill -0 $SA 2>/dev/null || break; sleep 1; done
kill $SA 2>/dev/null; wait $SA 2>/dev/null
for i in $(seq 1 60); do kill -0 $SB 2>/dev/null || break; sleep 1; done
kill $SB 2>/dev/null; wait $SB 2>/dev/null
sleep 1
bash $S snap ${TAG}_POST $W
echo "[p1 sink]"; grep -E "SINK_SUM|SINK_CONN" /tmp/${TAG}_A1_sink.txt
echo "[p0 sink]"; grep -E "SINK_SUM|SINK_CONN" /tmp/${TAG}_A0_sink.txt
echo "--- NIC counters (settled) ---"
echo -n "P1_RX "; ip netns exec nsa ethtool -S $I1 | awk '/port_rx_bytes:|port_rx_packets:/{printf "%s=%s ",$1,$2} END{print ""}'
echo -n "P0_RX "; ip netns exec nsb ethtool -S $I0 | awk '/port_rx_bytes:|port_rx_packets:/{printf "%s=%s ",$1,$2} END{print ""}'
echo "=== B4A_END tag=$TAG $(date +%s.%N)"
