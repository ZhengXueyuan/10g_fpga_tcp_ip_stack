#!/bin/bash
# e05_latency_baseline.sh -- E0.5 zero-build latency baseline on 0x32.
#   One 9G-class TCP downlink (port A, 24 GB), snapshots W5/W20/W43/W65..W69/W27/W28
#   idle (PRE) -> 3 s (MID1) -> +10 s (MID2) -> after sink (POST).
#   Metrics: dW66/dW65 (window wait share of tx idle), dW65/dW5 (idle duty),
#            dW67/dW66 (cap-side attribution), W27/W28 sticky occupancy maxima.
#   No build, no burn; board stays 0x32. Run via:
#     PEER_PW=... python tools/peer_ssh.py --sudo "bash /tmp/e05_latency_baseline.sh E05"
set -u
I1=enp1s0f1np1
S=/tmp/p2b_snap.sh
SINK=/tmp/p7b_biz/p7b_tcp_sink
TAG=${1:-E05}
W="0 5 20 43 65 66 67 68 69 27 28"
snap() { local t=$1; echo "TS_BEGIN $t $(date +%s.%N)"; bash $S snap "$t" $W; echo "TS_END $t $(date +%s.%N)"; }

echo "=== E05_BEGIN tag=$TAG $(date +%s.%N) $(date)"
echo "--- IRQ affinity: NIC IRQs -> CPU 4-7 ---"
for i in $(grep -E "$I1" /proc/interrupts | awk -F: '{print $1}'); do
    if [ -w /proc/irq/$i/smp_affinity_list ]; then
        echo 4-7 > /proc/irq/$i/smp_affinity_list
        echo "IRQ $i aff=$(cat /proc/irq/$i/smp_affinity_list)"
    fi
done
echo "--- coalescing off (port A) ---"
ip netns exec nsa ethtool -C $I1 adaptive-rx off rx-usecs 0 tx-usecs 0 2>&1 | head -8
echo "--- board identity ---"
bash $S id; echo ID_RC=$?
echo "--- PRE (idle) ---"
snap ${TAG}_PRE | tee /tmp/${TAG}_PRE.txt
echo "--- start sink: port A, 24 GB, lane8, --no-pin, taskset 0,1 ---"
ip netns exec nsa taskset -c 0,1 $SINK --host 192.168.100.2 --port 8080 \
    --rcvbuf 1048576 --conns 1 --maxbytes 24000000000 --check lane8 --no-pin \
    > /tmp/${TAG}_A_sink.txt 2>&1 & SK=$!
sleep 3
echo "--- MID1 (t=3 s under load) ---"
snap ${TAG}_MID1 | tee /tmp/${TAG}_MID1.txt
sleep 10
echo "--- MID2 (t=13 s under load) ---"
snap ${TAG}_MID2 | tee /tmp/${TAG}_MID2.txt
wait $SK; RC=$?
echo "SINK_RC=$RC"
sleep 1
echo "--- POST (after sink) ---"
snap ${TAG}_POST | tee /tmp/${TAG}_POST.txt
echo "[A sink]"
grep -E "PIN_|SINK_OPTS|SINK_LIMITS|SINK_CONN|SINK_SUM|SINK_DONE" /tmp/${TAG}_A_sink.txt
echo "--- NIC counters (settled) ---"
echo -n "P1_RX "; ip netns exec nsa ethtool -S $I1 | awk '/port_rx_bytes:|port_rx_packets:/{printf "%s=%s ",$1,$2} END{print ""}'
echo "=== E05_END tag=$TAG $(date +%s.%N) $(date)"
