#!/bin/bash
# b2b_data.sh -- P11 P2 B-2 Phase II data per port (sequential): p1->IP_A then p0->IP_B
set -u
I1=enp1s0f1np1; I0=enp1s0f0np0
S=/tmp/p2b_snap.sh
SINK=/tmp/p7b_biz/p7b_tcp_sink
TAG=${1:-B2D}
W="0 1 4 20 43 51 52 54 55 83 84 62 70"
nic(){ ip netns exec $1 ethtool -S $2 2>/dev/null | awk -v k="$3" '$1==k":"{print $2}'; }
echo "=== B2B_DATA_BEGIN tag=$TAG $(date +%s.%N) $(date)"
bash $S id; echo ID_RC=$?
echo "--- PORT A data: nsa p1 -> IP_A ---"
A1=$(nic nsa $I1 port_rx_bytes); A2=$(nic nsa $I1 port_rx_packets)
echo "NIC_A_PRE bytes=$A1 packets=$A2"
bash $S snap ${TAG}_A_PRE $W
ip netns exec nsa $SINK --host 192.168.100.2 --port 8080 --rcvbuf 2920 --conns 1 --maxbytes 200000000 --check lane8 > /tmp/${TAG}_A_sink.txt 2>&1
echo "SINK_A_RC=$?"
bash $S snap ${TAG}_A_POST $W
A1b=$(nic nsa $I1 port_rx_bytes); A2b=$(nic nsa $I1 port_rx_packets)
echo "NIC_A_DELTA bytes=$((A1b-A1)) packets=$((A2b-A2))"
grep -E "PIN_|SINK_SUM|SINK_CONN" /tmp/${TAG}_A_sink.txt
sleep 0.5
echo "--- PORT B data: nsb p0 -> IP_B ---"
B1=$(nic nsb $I0 port_rx_bytes); B2=$(nic nsb $I0 port_rx_packets)
echo "NIC_B_PRE bytes=$B1 packets=$B2"
bash $S snap ${TAG}_B_PRE $W
ip netns exec nsb $SINK --host 192.168.100.4 --port 8080 --rcvbuf 2920 --conns 1 --maxbytes 200000000 --check lane8 > /tmp/${TAG}_B_sink.txt 2>&1
echo "SINK_B_RC=$?"
bash $S snap ${TAG}_B_POST $W
B1b=$(nic nsb $I0 port_rx_bytes); B2b=$(nic nsb $I0 port_rx_packets)
echo "NIC_B_DELTA bytes=$((B1b-B1)) packets=$((B2b-B2))"
grep -E "PIN_|SINK_SUM|SINK_CONN" /tmp/${TAG}_B_sink.txt
echo "=== B2B_DATA_END tag=$TAG $(date +%s.%N)"
