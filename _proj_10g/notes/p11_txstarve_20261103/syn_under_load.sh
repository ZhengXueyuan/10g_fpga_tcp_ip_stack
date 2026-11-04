#!/bin/bash
# syn_under_load.sh -- 判别：数据流占线时新建连接的建立时延（conn_ms）
set -u
B=/tmp/p7b_biz; P=/home/a/p11_bench
mk(){ ip netns exec nsa timeout 20 "$B/p7b_tcp_sink" --host 192.168.100.2 --port 8080 --conns 1 \
      --maxbytes "$1" --seconds 20 --poll-ms 3000 --stall-n 3 --check lane8 --no-pin 2>&1; }
echo "=== ARM A: 2 long streams then probe at t=1s ==="
mk 2147483648 > $P/ld_a0.txt & mk 2147483648 > $P/ld_a1.txt &
sleep 1
mk 16777216 > $P/ld_probe.txt
wait
echo "A_stream0 $(grep -E 'SINK_CONN' $P/ld_a0.txt | tail -1 | cut -c1-120)"
echo "A_stream1 $(grep -E 'SINK_CONN' $P/ld_a1.txt | tail -1 | cut -c1-120)"
echo "A_probe   $(grep -E 'SINK_CONN' $P/ld_probe.txt | tail -1 | cut -c1-120)"
echo "=== ARM B: idle control (3 probes staggered 1s) ==="
for i in 1 2 3; do mk 16777216 > $P/ld_b$i.txt; echo "B$i $(grep -E 'SINK_CONN' $P/ld_b$i.txt | tail -1 | cut -c1-120)"; sleep 1; done
