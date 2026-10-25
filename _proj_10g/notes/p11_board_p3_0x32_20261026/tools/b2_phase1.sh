#!/bin/bash
# b2_phase1.sh -- P11 P2 B-2 Phase I identity + Phase II pool-return probe (0x2D)
#   p1(nsa 192.168.100.1) -> IP_A 192.168.100.2 (J8/ch1)
#   p0(nsb 192.168.100.101) -> IP_B 192.168.100.4 (J7/ch0)
set -u
I1=enp1s0f1np1; I0=enp1s0f0np0
S=/tmp/p2b_snap.sh
TAG=${1:-B2P1}
P1PC=/tmp/${TAG}_p1.pcap; P0PC=/tmp/${TAG}_p0.pcap
P1PC2=/tmp/${TAG}_p1_conn2.pcap; P0PC2=/tmp/${TAG}_p0_conn2.pcap
echo "=== B2_PHASE1_BEGIN tag=$TAG $(date +%s.%N) $(date)"
bash $S id; echo ID_RC=$?
echo "--- conn1: nsa p1 -> IP_A (.2), short data + FIN ---"
ip netns exec nsa tcpdump -i $I1 -nn -U -w $P1PC 'tcp port 8080 or arp' >/tmp/${TAG}_td1a.log 2>&1 &
TD1=$!
ip netns exec nsb tcpdump -i $I0 -nn -U -w $P0PC 'tcp port 8080 or arp' >/tmp/${TAG}_td1b.log 2>&1 &
TD2=$!
sleep 1
ip netns exec nsa python3 /tmp/p2b_probe.py 192.168.100.2 8080 conn1 2>&1 | sed 's/^/CONN1: /'
sleep 1
kill $TD1 $TD2 2>/dev/null; wait $TD1 $TD2 2>/dev/null
echo "--- wait 0.3 s then conn2: nsb p0 -> IP_B (.4), two 1-byte probes ---"
sleep 0.3
: > /tmp/${TAG}_ss.txt
ip netns exec nsa tcpdump -i $I1 -nn -U -w $P1PC2 'tcp port 8080 or arp' >/tmp/${TAG}_td2a.log 2>&1 &
TD1=$!
ip netns exec nsb tcpdump -i $I0 -nn -U -w $P0PC2 'tcp port 8080 or arp' >/tmp/${TAG}_td2b.log 2>&1 &
TD2=$!
sleep 1
ip netns exec nsb python3 /tmp/p2b_probe.py 192.168.100.4 8080 probe > /tmp/${TAG}_probe.txt 2>&1 &
PP=$!
sleep 1.2
ip netns exec nsb ss -tin state established '( dport = :8080 )' > /tmp/${TAG}_ss.txt 2>&1
cat /tmp/${TAG}_probe.txt
wait $PP
sleep 0.5
kill $TD1 $TD2 2>/dev/null; wait $TD1 $TD2 2>/dev/null
echo "--- ss witness (conn2 open) ---"
cat /tmp/${TAG}_ss.txt
echo "--- pcap conn1: SYN/SYN-ACK per port ---"
echo "[p1 conn1]"; tcpdump -nn -r $P1PC 'tcp' 2>/dev/null | head -12
echo "[p0 conn1]"; tcpdump -nn -r $P0PC 'tcp' 2>/dev/null | head -12
echo "--- pcap conn2: SYN/SYN-ACK + pure ACKs per port ---"
echo "[p1 conn2]"; tcpdump -nn -r $P1PC2 'tcp' 2>/dev/null | head -12
echo "[p0 conn2 SYN/ACK/PURE-ACK]"; tcpdump -nn -vv -r $P0PC2 'tcp' 2>/dev/null | grep -E "Flags \[(S|S\.|\.|A|PA)" | head -30
echo "--- board snapshot ---"
bash $S snap ${TAG}_POST 5 20 43 51 52 54 55 0 1 83 84 62
echo "=== B2_PHASE1_END tag=$TAG $(date +%s.%N)"
