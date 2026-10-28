#!/bin/bash
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
D=/dev/xdma0_user
kill_sinks() { ps -eo pid,args | awk '/[p]7b_tcp_sink_multi/ {print $1}' | xargs -r kill -9; }
snap() { $T/reg_rw $D 0x18 w 0x1 >/dev/null; sleep 0.05; }
rd() { printf '%s=' "$1"; $T/reg_rw $D $2 w 2>&1 | tail -1 | sed 's/.*: *//'; }
kill_sinks; sleep 0.5
$T/reg_rw $D 0x08 w 0x0 >/dev/null; sleep 1
snap; rd W8_pre 0x40; rd W9_pre 0x44; rd W62_pre 0x118
$T/reg_rw $D 0x08 w 0x4 >/dev/null; echo STALL_ON
cd /tmp/p7b_biz
rm -f /tmp/occ_w9.txt
( ip netns exec nsb ./p7b_tcp_sink_multi --host 192.168.100.4 --port 8080 --conns 1 \
    --maxbytes 1048576 --seconds 6 --check seq --send-conns 1 --send-bytes 16384 \
    > /tmp/occ_w9.txt 2>&1 & )
sleep 2
snap; rd W8_post 0x40; rd W9_post 0x44; rd W62_post 0x118; rd W97_post 0x1A4
sleep 1
snap; rd W62_post2 0x118
$T/reg_rw $D 0x08 w 0x0 >/dev/null
sleep 0.5
snap; rd W62_after_clear 0x118
kill_sinks || true
sleep 0.5; echo SINK_OUT:; cat /tmp/occ_w9.txt
echo END
