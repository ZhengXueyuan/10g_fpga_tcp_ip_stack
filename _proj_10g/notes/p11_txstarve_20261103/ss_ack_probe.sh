#!/bin/bash
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
B=/tmp/p7b_biz
pkill -x tcpdump 2>/dev/null; sleep 1
bash /tmp/env_setup_robust.sh >/tmp/ssack_env.log 2>&1
grep -E 'MOVE_.*RC=|packet loss|NSB_CARRIER' /tmp/ssack_env.log | tail -3
$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1
ps -eo pid,args | awk '/[p]7b_tcp_sink_multi/ {print $1}' | xargs -r kill -9
ip netns exec nsb timeout 30 "$B/p7b_tcp_sink_multi" --host 192.168.100.4 --port 8080 \
  --conns 8 --maxbytes 4294967296 --seconds 15 --send-conns 8 --send-bytes 4096 --check seq > /tmp/ssack_run.txt 2>&1 &
FP=$!
sleep 4
echo "=== SS after uplink 4096 x8 ==="
ip netns exec nsb ss -tin 2>/dev/null | grep -A1 "192.168.100.4:8080" | head -50
wait $FP
echo "=== RESULTS ==="
grep -E 'MULTI_CONN|MULTI_SUM' /tmp/ssack_run.txt
