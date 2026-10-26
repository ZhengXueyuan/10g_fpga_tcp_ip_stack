#!/bin/bash
# e05_longrun.sh -- supplementary E0.5 long run: one 60 GB TCP downlink on port A,
#   5 snapshots at t=5/15/25/35/45 s, to test whether the fast/slow state is stable
#   within a single connection. Zero-build. Run via:
#     PEER_PW=... python tools/peer_ssh.py --sudo --timeout 180 "bash /tmp/e05_longrun.sh E05L"
set -u
I1=enp1s0f1np1
S=/tmp/p2b_snap.sh
SINK=/tmp/p7b_biz/p7b_tcp_sink
TAG=${1:-E05L}
W="0 5 20 43 65 66 67 68 69 27 28"
snap() { local t=$1; echo "TS_BEGIN $t $(date +%s.%N)"; bash $S snap "$t" $W; echo "TS_END $t $(date +%s.%N)"; }

echo "=== E05L_BEGIN tag=$TAG $(date +%s.%N) $(date)"
for i in $(grep -E "$I1" /proc/interrupts | awk -F: '{print $1}'); do
    if [ -w /proc/irq/$i/smp_affinity_list ]; then echo 4-7 > /proc/irq/$i/smp_affinity_list; fi
done
ip netns exec nsa ethtool -C $I1 adaptive-rx off rx-usecs 0 tx-usecs 0 >/dev/null 2>&1
bash $S id | tail -1
snap ${TAG}_PRE | tee /tmp/${TAG}_PRE.txt
ip netns exec nsa taskset -c 0,1 $SINK --host 192.168.100.2 --port 8080 \
    --rcvbuf 1048576 --conns 1 --maxbytes 60000000000 --check lane8 --no-pin \
    > /tmp/${TAG}_A_sink.txt 2>&1 & SK=$!
sleep 5;  snap ${TAG}_L1 | tee /tmp/${TAG}_L1.txt
sleep 10; snap ${TAG}_L2 | tee /tmp/${TAG}_L2.txt
sleep 10; snap ${TAG}_L3 | tee /tmp/${TAG}_L3.txt
sleep 10; snap ${TAG}_L4 | tee /tmp/${TAG}_L4.txt
sleep 10; snap ${TAG}_L5 | tee /tmp/${TAG}_L5.txt
wait $SK; RC=$?
echo "SINK_RC=$RC"
sleep 1
snap ${TAG}_POST | tee /tmp/${TAG}_POST.txt
echo "[A sink]"
grep -E "PIN_|SINK_OPTS|SINK_LIMITS|SINK_CONN|SINK_SUM|SINK_DONE" /tmp/${TAG}_A_sink.txt
echo "=== E05L_END tag=$TAG $(date +%s.%N) $(date)"
