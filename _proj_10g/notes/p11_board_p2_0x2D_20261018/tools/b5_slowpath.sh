#!/bin/bash
# b5_slowpath.sh -- P11 P2 B-5: slow path per port (ARP / ICMP / UDP echo 8080) on 0x2D
set -u
I1=enp1s0f1np1; I0=enp1s0f0np0
S=/tmp/p2b_snap.sh
TAG=${1:-B5}
W="0 1 4 7 16 18 20 43 79 80 81 82 83 84"
echo "=== B5_BEGIN tag=$TAG $(date +%s.%N) $(date)"
bash $S id; echo ID_RC=$?
bash $S snap ${TAG}_PRE $W
run_side(){ # $1=ns $2=if $3=target  $4=label
  NS=$1; IF=$2; TGT=$3; LB=$4
  echo "--- SIDE $LB: $NS $IF -> $TGT ---"
  ip netns exec $NS ip neigh del $TGT dev $IF 2>/dev/null
  ip netns exec nsa tcpdump -i $I1 -nn -e -U -w /tmp/${TAG}_${LB}_arpA.pcap 'arp or icmp or udp port 8080' >/dev/null 2>&1 & TA=$!
  ip netns exec nsb tcpdump -i $I0 -nn -e -U -w /tmp/${TAG}_${LB}_arpB.pcap 'arp or icmp or udp port 8080' >/dev/null 2>&1 & TB=$!
  sleep 1
  echo "[ping -c 3 (ARP first)]"
  ip netns exec $NS ping -c 3 -W 1 -I $IF $TGT 2>&1 | tail -4
  ip netns exec $NS python3 /tmp/p2b_echo.py $TGT 8080 "HELLO-$LB" 2>&1 | sed "s/^/UDP_$LB: /"
  sleep 0.5
  kill $TA $TB 2>/dev/null; wait $TA $TB 2>/dev/null
  ip netns exec $NS ip neigh replace $TGT lladdr 00:0a:35:01:fe:c0 nud permanent dev $IF
  echo "[p1/p0 pcap — ARP replies]"
  echo "  p1:"; tcpdump -nn -e -r /tmp/${TAG}_${LB}_arpA.pcap 'arp' 2>/dev/null | head -6 | sed 's/^/    /'
  echo "  p0:"; tcpdump -nn -e -r /tmp/${TAG}_${LB}_arpB.pcap 'arp' 2>/dev/null | head -6 | sed 's/^/    /'
  echo "[p1/p0 pcap — ICMP/UDP src]"
  echo "  p1:"; tcpdump -nn -e -r /tmp/${TAG}_${LB}_arpA.pcap 'icmp or udp' 2>/dev/null | head -8 | sed 's/^/    /'
  echo "  p0:"; tcpdump -nn -e -r /tmp/${TAG}_${LB}_arpB.pcap 'icmp or udp' 2>/dev/null | head -8 | sed 's/^/    /'
}
run_side nsb $I0 192.168.100.4 B
bash $S snap ${TAG}_POST_B $W
run_side nsa $I1 192.168.100.2 A
bash $S snap ${TAG}_POST_A $W
echo "=== B5_END tag=$TAG $(date +%s.%N)"
