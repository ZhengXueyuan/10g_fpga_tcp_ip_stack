#!/bin/bash
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
D=/dev/xdma0_user
kill_sinks() { ps -eo pid,args | awk '/[p]7b_tcp_sink/ {print $1}' | xargs -r kill -TERM; }
kill_sinks; sleep 0.5
$T/reg_rw $D 0x08 w 0x0 >/dev/null; sleep 1
cd /tmp/p7b_biz
for i in 1 2 3 4 5; do rm -f /tmp/f$i.txt; done
for i in 1 2 3 4 5; do
  ( ip netns exec nsb ./p7b_tcp_sink --host 192.168.100.4 --port 8080 \
      --maxbytes 268435456 --seconds 8 > /tmp/f$i.txt 2>&1 & )
  sleep 0.5
done
sleep 3
$T/reg_rw $D 0x18 w 0x1 >/dev/null; sleep 0.05
printf 'W62='; $T/reg_rw $D 0x118 w 2>&1 | tail -1 | sed 's/.*: *//'
printf 'W61='; $T/reg_rw $D 0x114 w 2>&1 | tail -1 | sed 's/.*: *//'
printf 'W97='; $T/reg_rw $D 0x1A4 w 2>&1 | tail -1 | sed 's/.*: *//'
sleep 5
kill_sinks || true
sleep 1
for i in 1 2 3 4 5; do printf 'F%s: ' $i; grep -E "SINK_SUM" /tmp/f$i.txt 2>/dev/null | tail -1 | cut -c1-120; echo; done
echo END
