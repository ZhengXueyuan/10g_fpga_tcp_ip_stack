#!/bin/bash
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
B=/tmp/p7b_biz
ps -eo pid,args | awk '/[p]7b_tcp_sink_multi/ {print $1}' | xargs -r kill -9
$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1
rm -f /tmp/syn8.pcap /tmp/syn8_run.txt /tmp/tcpdump_syn8.log
ip netns exec nsb timeout 20 tcpdump -i any -nn -s 80 -w /tmp/syn8.pcap 'tcp and (tcp[tcpflags] & tcp-syn != 0)' > /tmp/tcpdump_syn8.log 2>&1 &
TP=$!
sleep 1.5
ip netns exec nsb timeout 30 $B/p7b_tcp_sink_multi --host 192.168.100.4 --port 8080 --conns 8 --maxbytes 4294967296 --seconds 10 --check seq > /tmp/syn8_run.txt 2>&1
sleep 1
kill $TP 2>/dev/null
sleep 0.5
echo "=== CONNS ==="
grep -E 'MULTI_CONN|MULTI_SUM' /tmp/syn8_run.txt
echo "=== PCAP (SYN/SYN-ACK only) ==="
tcpdump -nn -r /tmp/syn8.pcap 2>/dev/null | head -80
echo "=== COUNTS ==="
tcpdump -nn -r /tmp/syn8.pcap 2>/dev/null | awk '{print $3, $5, $6}' | sort | uniq -c | sort -rn | head -30
