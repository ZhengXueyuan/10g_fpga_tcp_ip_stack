#!/bin/bash
# verify_0x38.sh -- P11 8-conn tx_arb STARVE_GUARD board gate (run on peer as root).
#   Preconditions: nsb owns enp1s0f0np0, carrier=1, ping to 192.168.100.4 OK.
#   Fresh-burn discipline: <=3 warm-up small runs; flood judged only if the last warm-up is 8/8.
#   Flood pass: 0 status=4, every conn bytes>1MB, and SYN-ACK unique dst ports >=8 (flood1).
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
B=/tmp/p7b_biz
H=192.168.100.4
I=enp1s0f0np0
reg(){ $T/reg_rw /dev/xdma0_user "$1" w 2>/dev/null | tail -1 | sed 's/.*: *//'; }
snap(){ $T/reg_rw /dev/xdma0_user 0x18 w 1 >/dev/null 2>&1; sleep 0.5; }
run8(){ # $1 label $2 maxbytes $3 seconds
  ip netns exec nsb timeout 90 "$B/p7b_tcp_sink_multi" --host $H --port 8080 \
      --conns 8 --maxbytes "$2" --seconds "$3" --check seq > "/tmp/v38_$1.txt" 2>&1
  echo "RUN_$1 $(grep MULTI_SUM /tmp/v38_$1.txt)"
  echo "  $1: status0=$(grep -c 'MULTI_CONN .* status=0' /tmp/v38_$1.txt) status2=$(grep -c 'MULTI_CONN .* status=2' /tmp/v38_$1.txt) status4=$(grep -c 'MULTI_CONN .* status=4' /tmp/v38_$1.txt) zeros=$(grep -c 'MULTI_CONN .* got=0 ' /tmp/v38_$1.txt)"
  awk '/MULTI_CONN/ {for(i=1;i<=NF;i++){if($i ~ /^status=/)s=substr($i,8); if($i ~ /^got=/)g=substr($i,5); if($i ~ /^id=/)id=substr($i,4)}; printf "    conn%s status=%s got=%s\n", id, s, g}' "/tmp/v38_$1.txt"
}
echo "=== PRECOND ==="
ip -n nsb -br link | grep -q "$I" || { echo PRECOND_FAIL_NO_IFACE; exit 2; }
echo -n "CARRIER="; ip netns exec nsb cat /sys/class/net/$I/carrier || { echo PRECOND_FAIL_CARRIER; exit 2; }
ip netns exec nsb ping -c 2 -W 1 -I $I $H >/tmp/v38_ping.txt 2>&1; grep -q ' 0% packet loss' /tmp/v38_ping.txt || { echo PRECOND_FAIL_PING; tail -3 /tmp/v38_ping.txt; exit 2; }
$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1
echo "=== W97 idle x4 (0x38: [1:0] = {ack_sync[1], st_req}; should vary) ==="
for k in 1 2 3 4; do snap; echo "  SNAP$k W97=$(reg 0x1A4) STATUS=$(reg 0x1C)"; done
echo "=== warm-up (<=3; require last = 8/8) ==="
WOK=0
for k in 1 2 3; do run8 warm$k 12288 8; Z=$(grep -c 'MULTI_CONN .* got=0 ' /tmp/v38_warm$k.txt); [ "$Z" = "0" ] && WOK=1; done
[ "$WOK" = "1" ] || { echo WARMUP_FAIL_NO_8OF8; exit 3; }
echo "=== flood1 (4GiB/12s, SYN capture) ==="
rm -f /tmp/v38_flood1.pcap
ip netns exec nsb timeout 25 tcpdump -i any -nn -s 80 -w /tmp/v38_flood1.pcap 'tcp and (tcp[tcpflags] & tcp-syn != 0)' >/tmp/v38_tcpdump1.log 2>&1 &
TP=$!
sleep 1.5
run8 flood1 4294967296 12
sleep 1; kill $TP 2>/dev/null; sleep 0.5
echo "  SYN_OUT=$(tcpdump -nn -r /tmp/v38_flood1.pcap 2>/dev/null | grep -c 'Out IP 192.168.100.101.*Flags \[S\]')"
echo "  SYNACK_IN=$(tcpdump -nn -r /tmp/v38_flood1.pcap 2>/dev/null | grep -c 'In  IP 192.168.100.4.*Flags \[S.\]')"
echo "  SYNACK_UNIQ_DST=$(tcpdump -nn -r /tmp/v38_flood1.pcap 2>/dev/null | awk '$3=="In"{print $7}' | sed 's/:$//' | sort -u | wc -l)"
echo "=== flood2 (no capture) ==="
run8 flood2 4294967296 12
echo "=== post-flood small ==="
run8 post1 12288 8
echo "=== single-conn rate (0x36 ref 4647 Mbps) ==="
ip netns exec nsb timeout 30 "$B/p7b_tcp_sink_multi" --host $H --port 8080 \
    --conns 1 --maxbytes 4294967296 --seconds 12 --check seq > /tmp/v38_rate.txt 2>&1
grep -E 'MULTI_CONN|MULTI_SUM' /tmp/v38_rate.txt
echo "=== END ==="
