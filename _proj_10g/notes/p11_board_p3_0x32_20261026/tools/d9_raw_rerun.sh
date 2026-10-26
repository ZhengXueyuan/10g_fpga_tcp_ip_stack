#!/bin/bash
# d9_raw_rerun.sh -- re-run the P11 0x32 dual-port 10GB TCP downlink arm with
#   **sink logs tee'd to files** (the first D9 run's D9_A/D9_B were 0 B).
# Environment: b0_env_setup.sh has already moved the two NICs into nsa/nsb.
# Run as root: PEER_PW=... python tools/peer_ssh.py --sudo "bash /tmp/d9_raw_rerun.sh D9R"
set -u
I1=enp1s0f1np1
I0=enp1s0f0np0
S=/tmp/p2b_snap.sh
SINK=/tmp/p7b_biz/p7b_tcp_sink
TAG=${1:-D9R}
W="0 1 4 20 21 43 51 52 53 54 55 62 79 80 81 82 83 84"
echo "=== D9R_BEGIN tag=$TAG $(date +%s.%N) $(date)"
echo "--- IRQ affinity: NIC IRQs -> CPU 4-7 (siblings) ---"
for i in $(grep -E "$I1|$I0" /proc/interrupts | awk -F: '{print $1}'); do
    if [ -w /proc/irq/$i/smp_affinity_list ]; then
        echo 4-7 > /proc/irq/$i/smp_affinity_list
        echo "IRQ $i aff=$(cat /proc/irq/$i/smp_affinity_list)"
    fi
done
echo "--- coalescing (both ports) ---"
ip netns exec nsa ethtool -C $I1 adaptive-rx off rx-usecs 0 tx-usecs 0 2>&1 | head -8
ip netns exec nsb ethtool -C $I0 adaptive-rx off rx-usecs 0 tx-usecs 0 2>&1 | head -8
echo "--- board identity / stop state ---"
bash $S id; echo ID_RC=$?
bash $S snap ${TAG}_PRE $W
echo "--- start two sinks (A: taskset 0,1; B: taskset 2,3; --no-pin; 10GB each) ---"
ip netns exec nsa taskset -c 0,1 $SINK --host 192.168.100.2 --port 8080 \
    --rcvbuf 1048576 --conns 1 --maxbytes 10000000000 --check lane8 --no-pin \
    > /tmp/${TAG}_A_sink.txt 2>&1 & SA=$!
ip netns exec nsb taskset -c 2,3 $SINK --host 192.168.100.4 --port 8080 \
    --rcvbuf 1048576 --conns 1 --maxbytes 10000000000 --check lane8 --no-pin \
    > /tmp/${TAG}_B_sink.txt 2>&1 & SB=$!
sleep 2
bash $S snap ${TAG}_MID $W
wait $SA; RA=$?
wait $SB; RB=$?
echo "SINK_A_RC=$RA SINK_B_RC=$RB"
sleep 1
bash $S snap ${TAG}_POST $W
echo "[A p1 sink]"; grep -E "PIN_|SINK_OPTS|SINK_LIMITS|SINK_CONN|SINK_SUM|SINK_DONE" /tmp/${TAG}_A_sink.txt
echo "[B p0 sink]"; grep -E "PIN_|SINK_OPTS|SINK_LIMITS|SINK_CONN|SINK_SUM|SINK_DONE" /tmp/${TAG}_B_sink.txt
echo "--- NIC counters (settled) ---"
echo -n "P1_RX "; ip netns exec nsa ethtool -S $I1 | awk '/port_rx_bytes:|port_rx_packets:/{printf "%s=%s ",$1,$2} END{print ""}'
echo -n "P0_RX "; ip netns exec nsb ethtool -S $I0 | awk '/port_rx_bytes:|port_rx_packets:/{printf "%s=%s ",$1,$2} END{print ""}'
echo "=== D9R_END tag=$TAG $(date +%s.%N) $(date)"
