#!/bin/bash
# b6_udpapp.sh -- P11 P2 B-6: UDP app per-port learn/flip (0x2D)
#   learn from IP_B (p0) -> expect app TX only ch0 (W84 up, W83 flat);
#   then learn from IP_A (p1) -> expect flip (W83 up, W84 flat).
set -u
I1=enp1s0f1np1; I0=enp1s0f0np0
S=/tmp/p2b_snap.sh
UDP=/tmp/p7b_biz/p7b_udp_src
TAG=${1:-B6}
W="0 1 4 8 9 10 11 13 20 43 79 80 81 82 83 84 62"
echo "=== B6_BEGIN tag=$TAG $(date +%s.%N) $(date)"
bash $S id; echo ID_RC=$?
bash $S snap ${TAG}_PRE $W
learn(){ # $1=ns $2=target $3=label
  NS=$1; TGT=$2; LB=$3
  ip netns exec nsa tcpdump -i $I1 -nn -U -w /tmp/${TAG}_${LB}_p1.pcap 'udp port 8081' >/dev/null 2>&1 & TA=$!
  ip netns exec nsb tcpdump -i $I0 -nn -U -w /tmp/${TAG}_${LB}_p0.pcap 'udp port 8081' >/dev/null 2>&1 & TB=$!
  sleep 1
  ip netns exec $NS $UDP --host $TGT --port 8081 --seconds 0.2 --mbps 50 > /tmp/${TAG}_${LB}_udp.txt 2>&1
  echo "LEARN_${LB}_RC=$?"
  sleep 2.5
  kill $TA $TB 2>/dev/null; wait $TA $TB 2>/dev/null
  N1=$(tcpdump -nn -r /tmp/${TAG}_${LB}_p1.pcap 2>/dev/null | wc -l)
  N0=$(tcpdump -nn -r /tmp/${TAG}_${LB}_p0.pcap 2>/dev/null | wc -l)
  echo "PCAP_${LB} p1_frames=$N1 p0_frames=$N0"
  echo "  p1_sample:"; tcpdump -nn -r /tmp/${TAG}_${LB}_p1.pcap 2>/dev/null | head -2 | sed 's/^/    /'
  echo "  p0_sample:"; tcpdump -nn -r /tmp/${TAG}_${LB}_p0.pcap 2>/dev/null | head -2 | sed 's/^/    /'
  grep -E "UDP_SUM" /tmp/${TAG}_${LB}_udp.txt
}
echo "--- LEARN from IP_B (p0) ---"
learn nsb 192.168.100.4 B
bash $S snap ${TAG}_POST_B $W
echo "--- LEARN from IP_A (p1) ---"
learn nsa 192.168.100.2 A
bash $S snap ${TAG}_POST_A $W
echo "--- stop app TX: TX_DIS bit0 (J7/ch0) then bit1 (J8/ch1) ---"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
$T/reg_rw /dev/xdma0_user 0x08 w 0x1 >/dev/null 2>&1; sleep 0.3
bash $S snap ${TAG}_DIS0 83 84
$T/reg_rw /dev/xdma0_user 0x08 w 0x2 >/dev/null 2>&1; sleep 0.3
bash $S snap ${TAG}_DIS1 83 84
$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1; sleep 0.3
bash $S snap ${TAG}_DISRESTORE 83 84
echo "=== B6_END tag=$TAG $(date +%s.%N)"
