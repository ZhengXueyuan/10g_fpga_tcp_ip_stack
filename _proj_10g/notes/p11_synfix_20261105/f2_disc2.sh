#!/bin/bash
# f2_disc2.sh -- §0-92/停顿时现场采样加强版（零构建）：多读 W15/W20/W23/W55/W57/W58。
#   usage: f2_disc2.sh d <tag>            # 只跑 d 轮 8x256MB
#          f2_disc2.sh cd <gap_s> <tag>   # c 轮 8x16MB -> 等 gap -> d 轮
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
B=/tmp/p7b_biz; P=/home/a/p11_bench; mkdir -p $P
MODE=${1:-d}; GAP=${2:-0}; TAG=${3:-run}
reg(){ $T/reg_rw /dev/xdma0_user "$1" w 2>/dev/null | tail -1 | sed 's/.*: *//'; }
snaprd(){ $T/reg_rw /dev/xdma0_user 0x18 w 1 >/dev/null 2>&1; sleep 0.05; \
  printf 'W51=%s W52=%s W6=%s W7=%s W15=%s W20=%s W23=%s W55=%s W57=%s W58=%s' \
    "$(reg 0xEC)" "$(reg 0xF0)" "$(reg 0x38)" "$(reg 0x3C)" "$(reg 0x5C)" \
    "$(reg 0x70)" "$(reg 0x7C)" "$(reg 0xFC)" "$(reg 0x104)" "$(reg 0x108)"; }
$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1
echo "=== DISC2_BEGIN TAG=$TAG MODE=$MODE GAP=$GAP $(date +%T) BID=$(reg 0x04)"
echo "T0 $(snaprd)"
SAMPLES=$P/${TAG}_samples2.txt; : > "$SAMPLES"
STOP=/tmp/f2_disc2_stop.$TAG; rm -f "$STOP"
( while [ ! -f "$STOP" ]; do echo "S $(date +%T) $(snaprd)" >> "$SAMPLES"; sleep 0.4; done ) &
SPID=$!
round(){ # $1 maxbytes  $2 prefix  $3 stagger_s
  local MB=$1 PFX=$2 ST=$3
  local pids=()
  for i in 0 1 2 3 4 5 6 7; do
    ip netns exec nsa timeout 90 "$B/p7b_tcp_sink" --host 192.168.100.2 --port 8080 --conns 1 \
        --maxbytes "$MB" --seconds 20 --poll-ms 3000 --stall-n 3 --check lane8 --no-pin \
        > $P/${TAG}_${PFX}_$i.txt 2>&1 &
    pids+=($!)
    sleep "$ST"
  done
  local p
  for p in "${pids[@]}"; do wait "$p"; done
}
if [ "$MODE" = "cd" ]; then
  echo "--- c round 8x16MB start $(date +%T)"
  round 16777216 c 0.5
  echo "--- c round done $(date +%T) $(snaprd)"
  sleep "$GAP"
fi
echo "--- d round 8x256MB start $(date +%T) $(snaprd)"
round 268435456 d 0.3
echo "--- d round done $(date +%T) $(snaprd)"
touch "$STOP"; wait "$SPID" 2>/dev/null
for i in 0 1 2 3 4 5 6 7; do
  echo "P$i $(grep -E 'SINK_CONN' $P/${TAG}_d_$i.txt | tail -1)"
done
echo "=== DISC2_END TAG=$TAG $(date +%T)"
