#!/bin/bash
# f2_warm.sh -- 换烧后 warm-up 刻画：顺序单连接 (默认 .2 16MB)，可选先打 .4 预热。
#   usage: f2_warm.sh <tag> <n> [prewarm4]
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
B=/tmp/p7b_biz; P=/home/a/p11_bench; mkdir -p $P
TAG=${1:-w}; N=${2:-6}; PRE=${3:-}
reg(){ $T/reg_rw /dev/xdma0_user "$1" w 2>/dev/null | tail -1 | sed 's/.*: *//'; }
sr(){ $T/reg_rw /dev/xdma0_user 0x18 w 1 >/dev/null 2>&1; sleep 0.05; \
  printf 'W51=%s W52=%s W6=%s W7=%s W55=%s' "$(reg 0xEC)" "$(reg 0xF0)" "$(reg 0x38)" "$(reg 0x3C)" "$(reg 0xFC)"; }
$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1
echo "=== WARM_BEGIN TAG=$TAG N=$N PRE=$PRE $(date +%T) BID=$(reg 0x04)"
echo "T0 $(sr)"
if [ "$PRE" = "prewarm4" ]; then
  echo "--- prewarm .4 single 16MB $(date +%T)"
  ip netns exec nsb timeout 30 $B/p7b_tcp_sink --host 192.168.100.4 --port 8080 --conns 1 \
    --maxbytes 16777216 --seconds 15 --poll-ms 3000 --stall-n 3 --check lane8 --no-pin > $P/${TAG}_pre4.txt 2>&1
  echo "PRE4 $(grep -E 'SINK_CONN' $P/${TAG}_pre4.txt | tail -1)"
fi
for k in $(seq 1 $N); do
  ip netns exec nsa timeout 30 $B/p7b_tcp_sink --host 192.168.100.2 --port 8080 --conns 1 \
    --maxbytes 16777216 --seconds 15 --poll-ms 3000 --stall-n 3 --check lane8 --no-pin > $P/${TAG}_$k.txt 2>&1
  L=$(grep -E 'SINK_CONN' $P/${TAG}_$k.txt | tail -1)
  case "$L" in *' OK '*) R=OK;; *STALL*) R=STALL;; *) R=OTHER;; esac
  BYTES=$(echo "$L" | sed -n 's/.*bytes=\([0-9]*\).*/\1/p')
  echo "S$k $R bytes=${BYTES:-?} $(sr)"
  sleep 0.3
done
echo "=== WARM_END TAG=$TAG $(date +%T)"
