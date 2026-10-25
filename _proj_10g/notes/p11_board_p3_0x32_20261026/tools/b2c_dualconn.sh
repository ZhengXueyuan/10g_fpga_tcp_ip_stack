#!/bin/bash
# b2c_dualconn.sh -- P11 P2: simultaneous 1 TCP connection per port (MAX_TCP_CONN=3)
set -u
S=/tmp/p2b_snap.sh
TAG=${1:-B2C}
echo "=== B2C_BEGIN tag=$TAG $(date +%s.%N) $(date)"
bash $S id; echo ID_RC=$?
bash $S snap ${TAG}_PRE 0 1 4 20 43 83 84
ip netns exec nsa python3 /tmp/p2b_probe.py 192.168.100.2 8080 hold > /tmp/${TAG}_A.txt 2>&1 & PA=$!
ip netns exec nsb python3 /tmp/p2b_probe.py 192.168.100.4 8080 hold > /tmp/${TAG}_B.txt 2>&1 & PB=$!
sleep 1.5
echo "--- ss nsa ---"; ip netns exec nsa ss -tn state established '( dport = :8080 )'
echo "--- ss nsb ---"; ip netns exec nsb ss -tn state established '( dport = :8080 )'
wait $PA; wait $PB
echo "[A]"; cat /tmp/${TAG}_A.txt
echo "[B]"; cat /tmp/${TAG}_B.txt
sleep 0.5
bash $S snap ${TAG}_POST 0 1 4 20 43 83 84
echo "=== B2C_END tag=$TAG $(date +%s.%N)"
