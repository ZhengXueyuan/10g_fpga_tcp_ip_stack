#!/bin/bash
# b3_wrongport.sh -- P11 P2 B-3 wrong-port negative control (H-2), two parts:
#   (1) identity: p1 ARP who-has IP_B => no reply on p1; capture p0 for any reply (expected on ch0)
#   (2) outlet:   p1 SYN -> IP_B with static neigh => p1 sees SYN, p0 sees SYN-ACK (dst MAC=p1),
#                 p1 must NOT see SYN-ACK; reverse p0 -> IP_A symmetric.
set -u
I1=enp1s0f1np1; I0=enp1s0f0np0
TAG=${1:-B3}
S=/tmp/p2b_snap.sh
echo "=== B3_BEGIN tag=$TAG $(date +%s.%N) $(date)"
bash $S id; echo ID_RC=$?
MAC1=$(ip netns exec nsa cat /sys/class/net/$I1/address)
MAC0=$(ip netns exec nsb cat /sys/class/net/$I0/address)
echo "MAC_P1=$MAC1 MAC_P0=$MAC0"
echo "--- PART 1: ARP identity (p1 who-has IP_B) ---"
# remove static neigh so ping must ARP
ip netns exec nsa ip neigh del 192.168.100.4 dev $I1 2>/dev/null
ip netns exec nsa tcpdump -i $I1 -nn -e -U -w /tmp/${TAG}_arp_p1.pcap 'arp' >/dev/null 2>&1 &
T1=$!
ip netns exec nsb tcpdump -i $I0 -nn -e -U -w /tmp/${TAG}_arp_p0.pcap 'arp' >/dev/null 2>&1 &
T0=$!
sleep 1
ip netns exec nsa ping -c 1 -W 1 -I $I1 192.168.100.4 2>&1 | sed 's/^/PING_P1: /'
sleep 0.5
kill $T1 $T0 2>/dev/null; wait $T1 $T0 2>/dev/null
echo "[p1 ARP pcap]"; tcpdump -nn -e -r /tmp/${TAG}_arp_p1.pcap 2>/dev/null | head -10
echo "[p0 ARP pcap]"; tcpdump -nn -e -r /tmp/${TAG}_arp_p0.pcap 2>/dev/null | head -10
ip netns exec nsa ip neigh show 192.168.100.4
# restore static neigh for part 2
ip netns exec nsa ip neigh replace 192.168.100.4 lladdr 00:0a:35:01:fe:c0 nud permanent dev $I1
echo "--- PART 2A: p1 SYN -> IP_B (wrong port) ---"
ip netns exec nsa tcpdump -i $I1 -nn -e -U -w /tmp/${TAG}_syn_p1.pcap 'tcp port 8080' >/dev/null 2>&1 &
T1=$!
ip netns exec nsb tcpdump -i $I0 -nn -e -U -w /tmp/${TAG}_syn_p0.pcap 'tcp port 8080' >/dev/null 2>&1 &
T0=$!
sleep 1
ip netns exec nsa timeout 6 python3 /tmp/p2b_probe.py 192.168.100.4 8080 conn1 2>&1 | sed 's/^/P1_TO_IPB: /'
sleep 0.5
kill $T1 $T0 2>/dev/null; wait $T1 $T0 2>/dev/null
echo "[p1 pcap]"; tcpdump -nn -e -r /tmp/${TAG}_syn_p1.pcap 2>/dev/null | head -8
echo "[p0 pcap]"; tcpdump -nn -e -r /tmp/${TAG}_syn_p0.pcap 2>/dev/null | head -8
echo "--- PART 2B: p0 SYN -> IP_A (wrong port) ---"
ip netns exec nsa tcpdump -i $I1 -nn -e -U -w /tmp/${TAG}_syn2_p1.pcap 'tcp port 8080' >/dev/null 2>&1 &
T1=$!
ip netns exec nsb tcpdump -i $I0 -nn -e -U -w /tmp/${TAG}_syn2_p0.pcap 'tcp port 8080' >/dev/null 2>&1 &
T0=$!
sleep 1
ip netns exec nsb timeout 6 python3 /tmp/p2b_probe.py 192.168.100.2 8080 conn1 2>&1 | sed 's/^/P0_TO_IPA: /'
sleep 0.5
kill $T1 $T0 2>/dev/null; wait $T1 $T0 2>/dev/null
echo "[p0 pcap]"; tcpdump -nn -e -r /tmp/${TAG}_syn2_p0.pcap 2>/dev/null | head -8
echo "[p1 pcap]"; tcpdump -nn -e -r /tmp/${TAG}_syn2_p1.pcap 2>/dev/null | head -8
echo "--- board snapshot after ---"
bash $S snap ${TAG}_POST 0 1 4 20 43 51 52 54 55 83 84 62
echo "=== B3_END tag=$TAG $(date +%s.%N)"
