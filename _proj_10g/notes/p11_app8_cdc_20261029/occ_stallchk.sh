#!/bin/bash
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
D=/dev/xdma0_user
kill_sinks() { ps -eo pid,args | awk '/[p]7b_tcp_sink_multi/ {print $1}' | xargs -r kill -9; }
kill_sinks; sleep 0.5
$T/reg_rw $D 0x08 w 0x0 >/dev/null; sleep 1
$T/reg_rw $D 0x08 w 0x4 >/dev/null; echo STALL_ON
cd /tmp/p7b_biz
rm -f /tmp/occ_sc.txt /tmp/occ_sc.pcap
( ip netns exec nsb ./p7b_tcp_sink_multi --host 192.168.100.4 --port 8080 --conns 1 \
    --maxbytes 2097152 --seconds 6 --check seq --send-conns 1 --send-bytes 524288 \
    > /tmp/occ_sc.txt 2>&1 & )
sleep 2
rm -f /tmp/occ_sc.pcap
ip netns exec nsb timeout 2 tcpdump -i any -nn -s 96 -w /tmp/occ_sc.pcap 'tcp and src host 192.168.100.4' 2>/dev/null
python3 /tmp/occ_win.py /tmp/occ_sc.pcap 5
$T/reg_rw $D 0x18 w 0x1 >/dev/null; sleep 0.05
printf 'W62='; $T/reg_rw $D 0x118 w 2>&1 | tail -1 | sed 's/.*: *//'
printf 'W97='; $T/reg_rw $D 0x1A4 w 2>&1 | tail -1 | sed 's/.*: *//'
sleep 4
$T/reg_rw $D 0x08 w 0x0 >/dev/null
kill_sinks || true
sleep 0.5
echo SINK_OUT:; cat /tmp/occ_sc.txt
echo END
