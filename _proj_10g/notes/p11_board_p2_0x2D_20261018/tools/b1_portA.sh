#!/bin/bash
# b1_portA.sh -- P11 P2 B-1: single-port (p1 <-> IP_A / J8) TCP continuous flow on 0x2D
#   peer-side; run via: peer_ssh.py --sudo 'bash /tmp/p2b_b1.sh TAG'
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
S=/tmp/p2b_snap.sh
SINK=/tmp/p7b_biz/p7b_tcp_sink
TAG=${1:-B1}
NW=${NW:-85}; EXPECT_BID=${EXPECT_BID:-0x0000002D}; UNIMPL_ADDR=${UNIMPL_ADDR:-0x184}
OUT=/tmp/${TAG}
N1=enp1s0f1np1
N0=enp1s0f0np0
W=${WORDS:-"5 20 43 21 4 51 52 54 55 83 84 62"}
nic(){ ethtool -S $1 2>/dev/null | awk -v k="$2" '$1==k":"{print $2}'; }
echo "=== B1_BEGIN tag=$TAG $(date +%s.%N) $(date)"
echo "--- id gate ---"
NW=$NW EXPECT_BID=$EXPECT_BID UNIMPL_ADDR=$UNIMPL_ADDR bash $S id; echo ID_RC=$?
echo "--- NIC pre ---"
P1B0=$(nic $N1 port_rx_bytes); P1P0=$(nic $N1 port_rx_packets); P1BAD0=$(nic $N1 port_rx_bad)
P0B0=$(nic $N0 port_rx_bytes); P0P0=$(nic $N0 port_rx_packets)
echo "NIC_PRE p1_rx_bytes=$P1B0 p1_rx_packets=$P1P0 p1_rx_bad=$P1BAD0 p0_rx_bytes=$P0B0 p0_rx_packets=$P0P0"
echo "--- start sink $(date +%s.%N) ---"
$SINK --host 192.168.100.2 --port 8080 --rcvbuf 2920 --conns 1 --maxbytes 2000000000 --check lane8 > ${OUT}_sink.txt 2>&1 &
SP=$!
sleep 3
echo "--- snap A $(date +%s.%N) ---"
bash $S snap ${TAG}_A $W
sleep 8
echo "--- snap B $(date +%s.%N) ---"
bash $S snap ${TAG}_B $W
for i in $(seq 1 90); do kill -0 $SP 2>/dev/null || break; sleep 1; done
if kill -0 $SP 2>/dev/null; then echo "SINK_STILL_RUNNING => kill"; kill $SP; fi
wait $SP; RC=$?
echo "SINK_RC=$RC"
echo "--- snap C $(date +%s.%N) ---"
bash $S snap ${TAG}_C $W
echo "--- NIC post ---"
P1B1=$(nic $N1 port_rx_bytes); P1P1=$(nic $N1 port_rx_packets); P1BAD1=$(nic $N1 port_rx_bad)
P0B1=$(nic $N0 port_rx_bytes); P0P1=$(nic $N0 port_rx_packets)
echo "NIC_POST p1_rx_bytes=$P1B1 p1_rx_packets=$P1P1 p1_rx_bad=$P1BAD1 p0_rx_bytes=$P0B1 p0_rx_packets=$P0P1"
echo "NIC_DELTA p1_rx_bytes=$((P1B1-P1B0)) p1_rx_packets=$((P1P1-P1P0)) p1_rx_bad=$((P1BAD1-P1BAD0)) p0_rx_bytes=$((P0B1-P0B0)) p0_rx_packets=$((P0P1-P0P0))"
echo "--- sink output ---"
grep -E "PIN_|SINK_|mism|stall|fail|Mbps|bytes=|dur" ${OUT}_sink.txt | head -40
echo "=== B1_END tag=$TAG $(date +%s.%N)"
