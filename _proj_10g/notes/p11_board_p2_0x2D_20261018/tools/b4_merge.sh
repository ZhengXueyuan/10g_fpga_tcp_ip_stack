#!/bin/bash
# b4_merge.sh -- P11 P2 B-4: (a) simultaneous two-port TCP downlink; (b) simultaneous two-port UDP flood
set -u
I1=enp1s0f1np1; I0=enp1s0f0np0
S=/tmp/p2b_snap.sh
SINK=/tmp/p7b_biz/p7b_tcp_sink
UDP=/tmp/p7b_biz/p7b_udp_src
TAG=${1:-B4}
W="0 1 4 20 21 43 51 52 54 55 79 80 81 82 83 84 62"
echo "=== B4_BEGIN tag=$TAG $(date +%s.%N) $(date)"
bash $S id; echo ID_RC=$?
echo "=== PART A: simultaneous two-port TCP downlink (board TX both ports) ==="
ip netns exec nsa $SINK --host 192.168.100.2 --port 8080 --rcvbuf 2920 --conns 1 --maxbytes 1000000000 --check lane8 > /tmp/${TAG}_A1_sink.txt 2>&1 & SA=$!
ip netns exec nsb $SINK --host 192.168.100.4 --port 8080 --rcvbuf 2920 --conns 1 --maxbytes 1000000000 --check lane8 > /tmp/${TAG}_A0_sink.txt 2>&1 & SB=$!
sleep 2
bash $S snap ${TAG}_A_MID1 $W
sleep 5
bash $S snap ${TAG}_A_MID2 $W
for i in $(seq 1 60); do kill -0 $SA 2>/dev/null || break; sleep 1; done
kill $SA 2>/dev/null; wait $SA 2>/dev/null
for i in $(seq 1 60); do kill -0 $SB 2>/dev/null || break; sleep 1; done
kill $SB 2>/dev/null; wait $SB 2>/dev/null
bash $S snap ${TAG}_A_POST $W
echo "[A p1 sink]"; grep -E "SINK_SUM|SINK_CONN" /tmp/${TAG}_A1_sink.txt
echo "[A p0 sink]"; grep -E "SINK_SUM|SINK_CONN" /tmp/${TAG}_A0_sink.txt
sleep 1
echo "=== PART B: simultaneous two-port UDP flood (RX merge) ==="
bash $S snap ${TAG}_B_PRE $W
ip netns exec nsa $UDP --host 192.168.100.2 --port 8081 --seconds 10 --mbps 0 > /tmp/${TAG}_B1_udp.txt 2>&1 & UA=$!
ip netns exec nsb $UDP --host 192.168.100.4 --port 8081 --seconds 10 --mbps 0 > /tmp/${TAG}_B0_udp.txt 2>&1 & UB=$!
sleep 2
bash $S snap ${TAG}_B_MID1 $W
sleep 5
bash $S snap ${TAG}_B_MID2 $W
wait $UA; echo "UDP_A_RC=$?"
wait $UB; echo "UDP_B_RC=$?"
bash $S snap ${TAG}_B_POST $W
echo "[B p1 udp]"; grep -E "UDP_SUM|PIN_CPU|PIN_DEGRADED" /tmp/${TAG}_B1_udp.txt
echo "[B p0 udp]"; grep -E "UDP_SUM|PIN_CPU|PIN_DEGRADED" /tmp/${TAG}_B0_udp.txt
echo "=== B4_END tag=$TAG $(date +%s.%N)"
