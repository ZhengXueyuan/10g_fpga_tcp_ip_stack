#!/bin/bash
# verify_0x3B_p0_d.sh -- .2 口 8 条真正并发 (各 256MB), 3 次采样 ready/estab, 量聚合
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
B=/tmp/p7b_biz; P=/home/a/p11_bench
reg(){ $T/reg_rw /dev/xdma0_user "$1" w 2>/dev/null | tail -1 | sed 's/.*: *//'; }
snap(){ $T/reg_rw /dev/xdma0_user 0x18 w 1 >/dev/null 2>&1; sleep 0.5; }
rd(){ echo "W51=$(reg 0xEC) W52=$(reg 0xF0) W53=$(reg 0xF4) W97=$(reg 0x1A4)"; }
$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1
echo "BID=$(reg 0x04)"; snap; echo "T0 $(rd)"
for i in 0 1 2 3 4 5 6 7; do
  ip netns exec nsa timeout 90 "$B/p7b_tcp_sink" --host 192.168.100.2 --port 8080 --conns 1 \
      --maxbytes 268435456 --seconds 20 --poll-ms 3000 --stall-n 3 --check lane8 --no-pin \
      > $P/d_$i.txt 2>&1 &
  sleep 0.3
done
sleep 0.5; snap; echo "T_1 $(rd)"
sleep 0.5; snap; echo "T_2 $(rd)"
sleep 0.5; snap; echo "T_3 $(rd)"
wait
snap; echo "T_end $(rd)"
for i in 0 1 2 3 4 5 6 7; do
  echo "P$i $(grep -E 'SINK_CONN' $P/d_$i.txt | tail -1)"
done
