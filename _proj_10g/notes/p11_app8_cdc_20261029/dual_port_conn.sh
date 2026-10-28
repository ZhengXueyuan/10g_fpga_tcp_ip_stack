#!/bin/bash
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
D=/dev/xdma0_user
kill_sinks() { ps -eo pid,args | awk '/[p]7b_tcp_sink/ {print $1}' | xargs -r kill -TERM; }
kill_sinks; sleep 0.5
$T/reg_rw $D 0x08 w 0x0 >/dev/null; sleep 1
cd /tmp/p7b_biz
for i in 1 2 3 4; do rm -f /tmp/p0_$i.txt /tmp/p1_$i.txt; done
# port0 (.4) via nsb
for i in 1 2 3 4; do
  ( ip netns exec nsb ./p7b_tcp_sink --host 192.168.100.4 --port 8080 --maxbytes 268435456 --seconds 9 > /tmp/p0_$i.txt 2>&1 & )
  sleep 0.3
done
# port1 (.2) via nsa
for i in 1 2 3 4; do
  ( ip netns exec nsa ./p7b_tcp_sink --host 192.168.100.2 --port 8080 --maxbytes 268435456 --seconds 9 > /tmp/p1_$i.txt 2>&1 & )
  sleep 0.3
done
sleep 4
$T/reg_rw $D 0x18 w 0x1 >/dev/null; sleep 0.05
printf 'W62='; $T/reg_rw $D 0x118 w 2>&1 | tail -1 | sed 's/.*: *//'
printf 'W97='; $T/reg_rw $D 0x1A4 w 2>&1 | tail -1 | sed 's/.*: *//'
sleep 5
kill_sinks || true
sleep 1
echo "--- port0 (.4/nsb) ---"
for i in 1 2 3 4; do printf 'P0_%s: ' $i; grep -E "SINK_SUM" /tmp/p0_$i.txt 2>/dev/null | tail -1 | cut -c1-110; echo; done
echo "--- port1 (.2/nsa) ---"
for i in 1 2 3 4; do printf 'P1_%s: ' $i; grep -E "SINK_SUM" /tmp/p1_$i.txt 2>/dev/null | tail -1 | cut -c1-110; echo; done
echo END
