#!/bin/bash
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
D=/dev/xdma0_user
kill_sinks() { ps -eo pid,args | awk '/[p]7b_tcp_sink_multi/ {print $1}' | xargs -r kill -9; }
kill_sinks; sleep 0.5
$T/reg_rw $D 0x08 w 0x0 >/dev/null; sleep 1
cd /tmp/p7b_biz
rm -f /tmp/mtx.txt /tmp/mtx.pcap
( ip netns exec nsb ./p7b_tcp_sink_multi --host 192.168.100.4 --port 8080 --conns 8 \
    --maxbytes 4294967296 --seconds 12 --check seq > /tmp/mtx.txt 2>&1 & )
sleep 2
ip netns exec nsb timeout 2 tcpdump -i any -nn -s 96 -w /tmp/mtx.pcap 'tcp and src host 192.168.100.4' 2>/dev/null
python3 /tmp/occ_win.py /tmp/mtx.pcap 5
kill_sinks || true
sleep 0.5
tail -4 /tmp/mtx.txt
echo END
