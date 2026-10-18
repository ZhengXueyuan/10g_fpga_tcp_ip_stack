#!/bin/bash
# b4b_rxflood.sh -- P11 P2 B-4 RX merge: quiet check, then simultaneous UDP flood both ports
set -u
I1=enp1s0f1np1; I0=enp1s0f0np0
S=/tmp/p2b_snap.sh
UDP=/tmp/p7b_biz/p7b_udp_src
TAG=${1:-B4B}
W="0 1 4 20 43 79 80 81 82 83 84"
nic(){ ip netns exec $1 ethtool -S $2 2>/dev/null | awk -v k="$3" '$1==k":"{print $2}'; }
echo "=== B4B_BEGIN tag=$TAG $(date +%s.%N) $(date)"
bash $S id; echo ID_RC=$?
echo "--- quiet window (two snapshots, >=1ms apart) ---"
bash $S snap ${TAG}_Q1 83 84 20
bash $S snap ${TAG}_Q2 83 84 20
echo "NIC_PRE_P1 rxpk=$(nic nsa $I1 port_rx_packets) rxby=$(nic nsa $I1 port_rx_bytes) NIC_PRE_P0 rxpk=$(nic nsb $I0 port_rx_packets) rxby=$(nic nsb $I0 port_rx_bytes)"
bash $S snap ${TAG}_PRE $W
ip netns exec nsa $UDP --host 192.168.100.2 --port 8081 --seconds 7 --mbps 0 > /tmp/${TAG}_p1_udp.txt 2>&1 & UA=$!
ip netns exec nsb $UDP --host 192.168.100.4 --port 8081 --seconds 7 --mbps 0 > /tmp/${TAG}_p0_udp.txt 2>&1 & UB=$!
sleep 2
bash $S snap ${TAG}_MID1 $W
sleep 4
bash $S snap ${TAG}_MID2 $W
wait $UA; echo UDP_A_RC=$?
wait $UB; echo UDP_B_RC=$?
sleep 2
echo "NIC_POST_P1 rxpk=$(nic nsa $I1 port_rx_packets) rxby=$(nic nsa $I1 port_rx_bytes) NIC_POST_P0 rxpk=$(nic nsb $I0 port_rx_packets) rxby=$(nic nsb $I0 port_rx_bytes)"
bash $S snap ${TAG}_POST $W
echo "[p1 udp]"; grep -E "UDP_SUM|PIN_CPU=" /tmp/${TAG}_p1_udp.txt
echo "[p0 udp]"; grep -E "UDP_SUM|PIN_CPU=" /tmp/${TAG}_p0_udp.txt
echo "=== B4B_END tag=$TAG $(date +%s.%N)"
