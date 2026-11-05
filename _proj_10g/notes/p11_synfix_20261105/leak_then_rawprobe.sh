#!/bin/bash
# leak_then_rawprobe.sh -- 对称 F2 判据：.4 口 8x4GiB 泄漏轮 -> 板空闲后原始 SYN 探针（数 W7 = 空闲槽）。
#   期望：0x3B ~2；0x3C 8。
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
B=/tmp/p7b_biz; P=/home/a/p11_bench; mkdir -p $P
reg(){ $T/reg_rw /dev/xdma0_user "$1" w 2>/dev/null | tail -1 | sed 's/.*: *//'; }
bash /tmp/env_setup_robust.sh >/tmp/lt_env.log 2>&1
grep -E 'MOVE_.*RC=|NSB_CARRIER' /tmp/lt_env.log | tail -3
$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1
echo "BID=$(reg 0x04)"
echo "=== .4 leak round (8 x 4GiB) ==="
for i in 0 1 2 3 4 5 6 7; do
  ip netns exec nsb timeout 20 "$B/p7b_tcp_sink" --host 192.168.100.4 --port 8080 --conns 1 \
      --maxbytes 4294967296 --seconds 8 --poll-ms 5000 --stall-n 3 --check lane8 --no-pin \
      > $P/lt_$i.txt 2>&1 &
  sleep 0.5
done
wait
for i in 0 1 2 3 4 5 6 7; do
  printf 'LT%s %s\n' "$i" "$(grep -oE 'bytes=[0-9]+|fail_conns=[0-9]+' $P/lt_$i.txt | head -2 | tr '\n' ' ')"
done
sleep 2
echo "=== raw SYN occupancy probe ==="
bash /tmp/raw_probe_table.sh 8 42000
