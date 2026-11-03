#!/bin/bash
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
B=/tmp/p7b_biz
ps -eo pid,args | awk '/[p]7b_tcp_sink_multi/ {print $1}' | xargs -r kill -9
$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1
rm -f /tmp/late2.pcap
ip netns exec nsb tcpdump -i any -nn -s 80 -w /tmp/late2.pcap 'tcp and (tcp[tcpflags] & tcp-syn != 0)' >/dev/null 2>&1 &
TPID=$!
sleep 1.5
ip netns exec nsb timeout 20 $B/p7b_tcp_sink_multi --host 192.168.100.4 --port 8080 --conns 8 --maxbytes 4294967296 --seconds 3 --check seq > /tmp/late2_run.txt 2>&1
sleep 14
kill -9 $TPID 2>/dev/null; wait $TPID 2>/dev/null
echo "=== CONNS ==="; grep -E 'MULTI_CONN|MULTI_SUM' /tmp/late2_run.txt
echo "=== SYN-ACK timeline ==="
tcpdump -tt -nn -r /tmp/late2.pcap 2>/dev/null | grep 'Flags \[S.\]' | sed 's/ length 0//'
echo "=== SYN packets (timeline, src ports) ==="
tcpdump -tt -nn -r /tmp/late2.pcap 2>/dev/null | grep 'Flags \[S\]' | awk '{print $1, $5}' | head -50
