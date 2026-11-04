#!/bin/bash
# verify_0x3B_p0_b.sh -- 8 条并发、每条 16MB（可跑完），逐连接计数 + 传输中 W51/W52 多点采样
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
B=/tmp/p7b_biz
reg(){ $T/reg_rw /dev/xdma0_user "$1" w 2>/dev/null | tail -1 | sed 's/.*: *//'; }
snap(){ $T/reg_rw /dev/xdma0_user 0x18 w 1 >/dev/null 2>&1; sleep 0.5; }
rd(){ echo "W51=$(reg 0xEC) W52=$(reg 0xF0) W53=$(reg 0xF4) W97=$(reg 0x1A4)"; }
$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1
echo "BID=$(reg 0x04)"
snap; echo "T0 $(rd)"
echo "=== START 8 staggered sinks (0.5s), 16MB each, timeout 60 ==="
for i in 0 1 2 3 4 5 6 7; do
  ip netns exec nsa timeout 60 "$B/p7b_tcp_sink" --host 192.168.100.2 --port 8080 --conns 1 \
      --maxbytes 16777216 --seconds 8 --check seq > /tmp/v3bp0b_$i.txt 2>&1 &
  sleep 0.5
done
# 传输窗口内多点采样 (8 次 x 0.5s = 4s)
for k in 1 2 3 4 5 6 7 8; do snap; echo "T_$k $(rd)"; done
wait
snap; echo "T_end $(rd)"
for i in 0 1 2 3 4 5 6 7; do
  echo "P$i $(grep -E 'SINK_SUM' /tmp/v3bp0b_$i.txt | tail -1)"
done
