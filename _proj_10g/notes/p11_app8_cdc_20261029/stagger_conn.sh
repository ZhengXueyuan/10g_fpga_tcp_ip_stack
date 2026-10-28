#!/bin/bash
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
D=/dev/xdma0_user
kill_sinks() { ps -eo pid,args | awk '/[p]7b_tcp_sink/ {print $1}' | xargs -r kill -TERM; }
kill_sinks; sleep 0.5
$T/reg_rw $D 0x08 w 0x0 >/dev/null; sleep 1
cd /tmp/p7b_biz
for i in $(seq 1 8); do rm -f /tmp/st$i.txt; done
for i in $(seq 1 8); do
  ( ip netns exec nsb ./p7b_tcp_sink --host 192.168.100.4 --port 8080 \
      --maxbytes 268435456 --seconds 10 > /tmp/st$i.txt 2>&1 & )
  sleep 0.6
done
sleep 4
echo "--- per-sink first lines ---"
for i in $(seq 1 8); do printf 'S%s: ' $i; head -1 /tmp/st$i.txt 2>/dev/null | cut -c1-120; echo; done
sleep 7
kill_sinks || true
sleep 1
echo "--- totals ---"
for i in $(seq 1 8); do printf 'S%s: ' $i; grep -E "SINK_SUM|SINK_CONN" /tmp/st$i.txt 2>/dev/null | tail -1 | cut -c1-160; echo; done
echo END
