#!/bin/bash
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
D=/dev/xdma0_user
kill_sinks() { ps -eo pid,args | awk '/[p]7b_tcp_sink_multi/ {print $1}' | xargs -r kill -TERM; }
kill_sinks; sleep 0.5
$T/reg_rw $D 0x08 w 0x0 >/dev/null; sleep 1
cd /tmp/p7b_biz
rm -f /tmp/mtx2.txt /tmp/mtx_a.pcap /tmp/mtx_b.pcap
( ip netns exec nsb ./p7b_tcp_sink_multi --host 192.168.100.4 --port 8080 --conns 8 \
    --maxbytes 4294967296 --seconds 20 --check seq > /tmp/mtx2.txt 2>&1 & )
sleep 2
ip netns exec nsb timeout 2 tcpdump -i any -nn -s 96 -w /tmp/mtx_a.pcap 'tcp and src host 192.168.100.4' 2>/dev/null
echo "--- capture A ---"; python3 /tmp/occ_win.py /tmp/mtx_a.pcap 3
sleep 3
ip netns exec nsb timeout 2 tcpdump -i any -nn -s 96 -w /tmp/mtx_b.pcap 'tcp and src host 192.168.100.4' 2>/dev/null
echo "--- capture B ---"; python3 /tmp/occ_win.py /tmp/mtx_b.pcap 3
kill_sinks || true
sleep 1
echo "--- sink output ---"; grep -E "MULTI_CONN|MULTI_SUM" /tmp/mtx2.txt | sed 's/ want=.*wall=/ wall=/' | head -10
echo END
