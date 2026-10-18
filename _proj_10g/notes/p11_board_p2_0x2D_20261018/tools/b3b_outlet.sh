#!/bin/bash
# b3b_outlet.sh -- P11 P2 B-3 part 2 (outlet) with explicit wrong-direction routes
set -u
I1=enp1s0f1np1; I0=enp1s0f0np0
TAG=${1:-B3B}
S=/tmp/p2b_snap.sh
echo "=== B3B_BEGIN tag=$TAG $(date +%s.%N) $(date)"
ip netns exec nsa ip route replace 192.168.100.4/32 dev $I1
ip netns exec nsb ip route replace 192.168.100.2/32 dev $I0
ip netns exec nsa ip neigh replace 192.168.100.4 lladdr 00:0a:35:01:fe:c0 nud permanent dev $I1
ip netns exec nsb ip neigh replace 192.168.100.2 lladdr 00:0a:35:01:fe:c0 nud permanent dev $I0
echo "[routes]"; ip netns exec nsa ip route show; ip netns exec nsb ip route show
echo "--- 2A: p1 SYN -> IP_B (.4) ---"
ip netns exec nsa tcpdump -i $I1 -nn -e -U -w /tmp/${TAG}_a_p1.pcap 'tcp port 8080' >/dev/null 2>&1 & T1=$!
ip netns exec nsb tcpdump -i $I0 -nn -e -U -w /tmp/${TAG}_a_p0.pcap 'tcp port 8080' >/dev/null 2>&1 & T0=$!
sleep 1
ip netns exec nsa timeout 8 python3 /tmp/p2b_probe.py 192.168.100.4 8080 conn1 2>&1 | sed 's/^/P1_TO_IPB: /'
sleep 0.5
kill $T1 $T0 2>/dev/null; wait $T1 $T0 2>/dev/null
echo "[p1 pcap]"; tcpdump -nn -e -r /tmp/${TAG}_a_p1.pcap 2>/dev/null | head -8
echo "[p0 pcap]"; tcpdump -nn -e -r /tmp/${TAG}_a_p0.pcap 2>/dev/null | head -8
echo "--- 2B: p0 SYN -> IP_A (.2) ---"
ip netns exec nsa tcpdump -i $I1 -nn -e -U -w /tmp/${TAG}_b_p1.pcap 'tcp port 8080' >/dev/null 2>&1 & T1=$!
ip netns exec nsb tcpdump -i $I0 -nn -e -U -w /tmp/${TAG}_b_p0.pcap 'tcp port 8080' >/dev/null 2>&1 & T0=$!
sleep 1
ip netns exec nsb timeout 8 python3 /tmp/p2b_probe.py 192.168.100.2 8080 conn1 2>&1 | sed 's/^/P0_TO_IPA: /'
sleep 0.5
kill $T1 $T0 2>/dev/null; wait $T1 $T0 2>/dev/null
echo "[p0 pcap]"; tcpdump -nn -e -r /tmp/${TAG}_b_p0.pcap 2>/dev/null | head -8
echo "[p1 pcap]"; tcpdump -nn -e -r /tmp/${TAG}_b_p1.pcap 2>/dev/null | head -8
# remove the wrong-direction routes (keep normal topology)
ip netns exec nsa ip route del 192.168.100.4/32 dev $I1 2>/dev/null
ip netns exec nsb ip route del 192.168.100.2/32 dev $I0 2>/dev/null
echo "--- board snapshot ---"
bash $S snap ${TAG}_POST 0 1 4 20 43 51 52 54 55 83 84 62
echo "=== B3B_END tag=$TAG $(date +%s.%N)"
