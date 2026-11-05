#!/bin/bash
# f2_disc3.sh -- 大批量停顿猎手（零构建）：在 disc2 基础上加窗口门 W66/W67/W68。
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
B=/tmp/p7b_biz; P=/home/a/p11_bench; mkdir -p $P
MODE=${1:-d}; GAP=${2:-0}; TAG=${3:-run}
reg(){ $T/reg_rw /dev/xdma0_user "$1" w 2>/dev/null | tail -1 | sed 's/.*: *//'; }
snaprd(){ $T/reg_rw /dev/xdma0_user 0x18 w 1 >/dev/null 2>&1; sleep 0.05; \
  printf 'W51=%s W52=%s W6=%s W7=%s W55=%s W66=%s W67=%s W68=%s' \
    "$(reg 0xEC)" "$(reg 0xF0)" "$(reg 0x38)" "$(reg 0x3C)" "$(reg 0xFC)" \
    "$(reg 0x128)" "$(reg 0x12C)" "$(reg 0x130)"; }
$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1
echo "=== DISC3_BEGIN TAG=$TAG MODE=$MODE $(date +%T) BID=$(reg 0x04)"
echo "T0 $(snaprd)"
SAMPLES=$P/${TAG}_samples3.txt; : > "$SAMPLES"
STOP=/tmp/f2_disc3_stop.$TAG; rm -f "$STOP"
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
  round 16777216 c 0.5
  sleep "$GAP"
fi
round 268435456 d 0.3
touch "$STOP"; wait "$SPID" 2>/dev/null
for i in 0 1 2 3 4 5 6 7; do
  echo "P$i $(grep -E 'SINK_CONN' $P/${TAG}_d_$i.txt | tail -1)"
done
echo "=== DISC3_END TAG=$TAG $(date +%T)"
