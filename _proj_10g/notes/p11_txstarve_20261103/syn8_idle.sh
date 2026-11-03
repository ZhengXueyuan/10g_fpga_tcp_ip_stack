#!/bin/bash
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
B=/tmp/p7b_biz
ps -eo pid,args | awk '/[p]7b_tcp_sink_multi/ {print $1}' | xargs -r kill -9
$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1
rm -f /tmp/syn8_idle.pcap /tmp/syn8_idle_run.txt
ip netns exec nsb timeout 20 tcpdump -i any -nn -s 80 -w /tmp/syn8_idle.pcap 'tcp and (tcp[tcpflags] & tcp-syn != 0)' > /tmp/tcpdump_syn8_idle.log 2>&1 &
TP=$!
sleep 1.5
ip netns exec nsb timeout 30 $B/p7b_tcp_sink_multi --host 192.168.100.4 --port 8080 --conns 8 --maxbytes 12288 --seconds 8 --check seq > /tmp/syn8_idle_run.txt 2>&1
sleep 1
kill $TP 2>/dev/null
sleep 0.5
echo "=== CONNS ==="
grep -E 'MULTI_SUM' /tmp/syn8_idle_run.txt
grep -c 'MULTI_CONN .* status=0' /tmp/syn8_idle_run.txt | sed 's/^/status0=/'
echo "=== COUNTS ==="
echo SYN_OUT=$(tcpdump -nn -r /tmp/syn8_idle.pcap 2>/dev/null | grep -c 'Out IP 192.168.100.101.*Flags \[S\]')
echo SYNACK_IN=$(tcpdump -nn -r /tmp/syn8_idle.pcap 2>/dev/null | grep -c 'In  IP 192.168.100.4.*Flags \[S.\]')
echo UNIQ_OUT=$(tcpdump -nn -r /tmp/syn8_idle.pcap 2>/dev/null | grep 'Out IP' | awk '{print $5}' | sort -u | wc -l)
echo UNIQ_SYNACK=$(tcpdump -nn -r /tmp/syn8_idle.pcap 2>/dev/null | grep 'In  IP' | awk '{print $3}' | sort -u | wc -l)
