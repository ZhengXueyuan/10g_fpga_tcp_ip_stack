#!/bin/bash
# ss_probe.sh -- zero-build: inspect all 8 TCP connections from the peer while 2/8 stream.
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
B=/tmp/p7b_biz
pkill -x tcpdump 2>/dev/null; sleep 1
bash /tmp/env_setup_robust.sh >/tmp/ssp_env.log 2>&1
grep -E 'MOVE_.*RC=|packet loss|NSB_CARRIER' /tmp/ssp_env.log | tail -3
$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1
for i in 0 1 2 3 4 5 6 7; do
  ip netns exec nsb timeout 25 "$B/p7b_tcp_sink" --host 192.168.100.4 --port 8080 --conns 1 \
      --maxbytes 4294967296 --seconds 20 --check seq > /tmp/ssp_$i.txt 2>&1 &
  sleep 0.5
done
sleep 3
echo "=== SS during test ==="
ip netns exec nsb ss -tin state established '( dport = :8080 )' 2>/dev/null | grep -E "192.168.100.4:8080|bytes_received|snd_wnd|rcv_space|retrans|rcv_ssthresh" | head -60
wait
echo "=== RESULTS ==="
for i in 0 1 2 3 4 5 6 7; do echo "P$i $(grep -E 'SINK_SUM' /tmp/ssp_$i.txt | tail -1)"; done
