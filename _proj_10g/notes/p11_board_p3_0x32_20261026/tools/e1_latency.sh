#!/bin/bash
# e1_latency.sh -- E1 zero-build load-tail latency probe (P11 0x32).
#   Load: 60 GB TCP downlink on port A (nsa -> 192.168.100.2), THREADED sink.
#   Probes: from port B (nsb -> 192.168.100.4): ping, TCP SYN, UDP echo 64/996/1472.
#   Snapshots: PRE / MID1 (t=3s) / MID2 (after probes) / POST.
#   Usage: bash /tmp/e1_latency.sh E1BASE baseline
#          bash /tmp/e1_latency.sh E1L1   load
set -u
TAG=${1:-E1BASE}
MODE=${2:-baseline}
S=/tmp/p2b_snap.sh
SINK=/tmp/p7b_biz/p7b_tcp_sink
PROBE=/tmp/p7b_biz/p7b_lat_probe
I1=enp1s0f1np1
I0=enp1s0f0np0
W="0 5 20 43 65 66 67 68 69 27 28"
snap() { local t=$1; echo "TS_BEGIN $t $(date +%s.%N)"; bash $S snap "$t" $W; echo "TS_END $t $(date +%s.%N)"; }

echo "=== E1_BEGIN tag=$TAG mode=$MODE $(date +%s.%N) $(date)"
for i in $(grep -E "$I1|$I0" /proc/interrupts | awk -F: '{print $1}'); do
    [ -w /proc/irq/$i/smp_affinity_list ] && echo 4-7 > /proc/irq/$i/smp_affinity_list
done
ip netns exec nsa ethtool -C $I1 adaptive-rx off rx-usecs 0 tx-usecs 0 >/dev/null 2>&1
ip netns exec nsb ethtool -C $I0 adaptive-rx off rx-usecs 0 tx-usecs 0 >/dev/null 2>&1
bash $S id | tail -1
snap ${TAG}_PRE | tee /tmp/${TAG}_PRE.txt

SK=""
if [ "$MODE" = "load" ]; then
    echo "--- start load: A port 60 GB ---"
    ip netns exec nsa taskset -c 0,1 $SINK --host 192.168.100.2 --port 8080 \
        --rcvbuf 1048576 --conns 1 --maxbytes 60000000000 --check lane8 --no-pin \
        > /tmp/${TAG}_A_sink.txt 2>&1 & SK=$!
fi
sleep 3
snap ${TAG}_MID1 | tee /tmp/${TAG}_MID1.txt
echo "CPU2_FREQ_KHZ=$(cat /sys/devices/system/cpu/cpu2/cpufreq/scaling_cur_freq 2>/dev/null || echo n/a)"

echo "--- ping (2000 @ 5 ms) ---"
ip netns exec nsb taskset -c 2 ping -n -i 0.005 -c 2000 -W 0.05 192.168.100.4 \
    > /tmp/${TAG}_ping.txt 2>&1
echo "PING_RC=$?"
if [ "${SKIP_TCP:-0}" != "1" ]; then
echo "--- tcp syn (2000 @ 5 ms) ---"
ip netns exec nsb taskset -c 2 $PROBE --mode tcp --host 192.168.100.4 --port 8080 \
    --count 2000 --interval-ms 5 --timeout-ms 200 --csv /tmp/${TAG}_tcp.csv \
    > /tmp/${TAG}_tcp.txt 2>&1
echo "TCP_RC=$?"
fi
echo "--- udp echo 64 B (2000 @ 5 ms) ---"
ip netns exec nsb taskset -c 2 $PROBE --mode udp --host 192.168.100.4 --port 8080 \
    --count 2000 --interval-ms 5 --timeout-ms 200 --bytes 64 --csv /tmp/${TAG}_udp64.csv \
    > /tmp/${TAG}_udp64.txt 2>&1
echo "UDP64_RC=$?"
echo "--- udp echo 996 B (1000 @ 10 ms, exact) ---"
ip netns exec nsb taskset -c 2 $PROBE --mode udp --host 192.168.100.4 --port 8080 \
    --count 1000 --interval-ms 10 --timeout-ms 500 --bytes 996 --csv /tmp/${TAG}_udp996.csv \
    > /tmp/${TAG}_udp996.txt 2>&1
echo "UDP996_RC=$?"
echo "--- udp echo 1472 B (500 @ 10 ms, no-check; >996 is zero-filled) ---"
ip netns exec nsb taskset -c 2 $PROBE --mode udp --host 192.168.100.4 --port 8080 \
    --count 500 --interval-ms 10 --timeout-ms 500 --bytes 1472 --no-check --csv /tmp/${TAG}_udp1472.csv \
    > /tmp/${TAG}_udp1472.txt 2>&1
echo "UDP1472_RC=$?"

snap ${TAG}_MID2 | tee /tmp/${TAG}_MID2.txt
if [ -n "$SK" ]; then
    wait $SK; echo "SINK_RC=$?"
    sleep 1
    snap ${TAG}_POST | tee /tmp/${TAG}_POST.txt
    grep -E "SINK_CONN|SINK_SUM" /tmp/${TAG}_A_sink.txt
else
    snap ${TAG}_POST | tee /tmp/${TAG}_POST.txt
fi
echo "[ping summary]"; tail -2 /tmp/${TAG}_ping.txt
echo "[tcp]"; cat /tmp/${TAG}_tcp.txt
echo "[udp64]"; cat /tmp/${TAG}_udp64.txt
echo "[udp996]"; cat /tmp/${TAG}_udp996.txt
echo "[udp1472]"; cat /tmp/${TAG}_udp1472.txt
echo "=== E1_END tag=$TAG $(date +%s.%N) $(date)"
