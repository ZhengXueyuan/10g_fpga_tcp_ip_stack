#!/bin/bash
# verify_0x3B_p0_c.sh -- 干净态 8x16MB 并发 (无绑核, lane8), 传输中 ss -tin 判别
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
B=/tmp/p7b_biz; P=/home/a/p11_bench
mkdir -p $P
reg(){ $T/reg_rw /dev/xdma0_user "$1" w 2>/dev/null | tail -1 | sed 's/.*: *//'; }
snap(){ $T/reg_rw /dev/xdma0_user 0x18 w 1 >/dev/null 2>&1; sleep 0.5; }
rd(){ echo "W51=$(reg 0xEC) W52=$(reg 0xF0) W53=$(reg 0xF4) W97=$(reg 0x1A4)"; }
$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1
echo "BID=$(reg 0x04)"; snap; echo "T0 $(rd)"
echo "=== START 8 x 16MB to .2 (no-pin, lane8) $(date +%T) ==="
for i in 0 1 2 3 4 5 6 7; do
  ip netns exec nsa timeout 90 "$B/p7b_tcp_sink" --host 192.168.100.2 --port 8080 --conns 1 \
      --maxbytes 16777216 --seconds 20 --poll-ms 3000 --stall-n 3 --check lane8 --no-pin \
      > $P/c_$i.txt 2>&1 &
  sleep 0.5
done
sleep 1; snap; echo "T_1 $(rd) $(date +%T)"
ip netns exec nsa ss -tin state established '( dport = :8080 )' > $P/ss_1.txt 2>&1
sleep 2; snap; echo "T_2 $(rd) $(date +%T)"
ip netns exec nsa ss -tin state established '( dport = :8080 )' > $P/ss_2.txt 2>&1
sleep 4; snap; echo "T_3 $(rd) $(date +%T)"
ip netns exec nsa ss -tin state established '( dport = :8080 )' > $P/ss_3.txt 2>&1
wait
snap; echo "T_end $(rd) $(date +%T)"
for i in 0 1 2 3 4 5 6 7; do
  echo "P$i $(grep -E 'SINK_CONN' $P/c_$i.txt | tail -1)"
done
echo "=== ss_1 ==="; cat $P/ss_1.txt
echo "=== ss_2 ==="; cat $P/ss_2.txt
echo "=== ss_3 ==="; cat $P/ss_3.txt
