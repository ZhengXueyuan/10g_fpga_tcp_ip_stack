#!/bin/bash
# e1a_latency.sh -- P11 E1a-1 board run: A-port TCP downlink + W85..W96 hist snapshots.
#   DRAFT (design round; not yet used on board). Requires:
#     /tmp/p7b_snap.sh   (geometry overridden below: NW=97 / UNIMPL=0x1B4 / BID=0x33)
#     /tmp/p7b_biz/p7b_tcp_sink
#   Run as root on the peer (tools/peer_ssh.py --sudo).
#   Usage: bash /tmp/e1a_latency.sh E1A [RUNS] [BYTES]
#          RUNS default 10, BYTES default 10000000000 (10 GB)
set -u
TAG=${1:-E1A}
RUNS=${2:-10}
BYTES=${3:-10000000000}
S=/tmp/p7b_snap.sh
SINK=/tmp/p7b_biz/p7b_tcp_sink
I=enp1s0f1np1
W="0 5 14 20 43 52 65 66 67 68 69 83 85 86 87 88 89 90 91 92 93 94 95 96"
export NW=97
export UNIMPL_ADDR=0x1B4
export EXPECT_BID=0x00000033

snap() { local t=$1; echo "TS_BEGIN $t $(date +%s.%N)"; \
         bash "$S" snap "$t" $W; echo "TS_END $t $(date +%s.%N)"; }

echo "=== E1A_BEGIN tag=$TAG runs=$RUNS bytes=$BYTES $(date +%s.%N) $(date)"
# IRQ affinity: keep the board's NIC IRQs off the sink cores (E0.5/E1 recipe).
for i in $(grep -E "$I" /proc/interrupts | awk -F: '{print $1}'); do
    [ -w /proc/irq/$i/smp_affinity_list ] && echo 4-7 > /proc/irq/$i/smp_affinity_list
done
ip netns exec nsa ethtool -C "$I" adaptive-rx off rx-usecs 0 tx-usecs 0 >/dev/null 2>&1
bash "$S" id | tee /tmp/${TAG}_ID.txt

echo "--- idle negative control (2 s, no traffic) ---"
snap ${TAG}_IDLE0 | tee /tmp/${TAG}_IDLE0.txt
sleep 2
snap ${TAG}_IDLE1 | tee /tmp/${TAG}_IDLE1.txt

for r in $(seq 1 "$RUNS"); do
    RT=${TAG}_R${r}
    echo "--- run $r/$RUNS: ${BYTES} B downlink on port A ---"
    snap ${RT}_PRE | tee /tmp/${RT}_PRE.txt
    ip netns exec nsa taskset -c 0,1 "$SINK" --host 192.168.100.2 --port 8080 \
        --rcvbuf 1048576 --conns 1 --maxbytes "$BYTES" --check lane8 --no-pin \
        > /tmp/${RT}_A_sink.txt 2>&1 &
    SK=$!
    sleep 3
    snap ${RT}_MID1 | tee /tmp/${RT}_MID1.txt
    wait $SK; echo "SINK_RC=$?" | tee -a /tmp/${RT}_A_sink.txt
    sleep 1
    snap ${RT}_POST | tee /tmp/${RT}_POST.txt
    grep -E "SINK_CONN|SINK_SUM" /tmp/${RT}_A_sink.txt | tee -a /tmp/${RT}_SUMMARY.txt
done

snap ${TAG}_FINAL | tee /tmp/${TAG}_FINAL.txt
echo "=== E1A_END tag=$TAG $(date +%s.%N) $(date)"
