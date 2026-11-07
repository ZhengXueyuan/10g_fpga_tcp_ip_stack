#!/bin/bash
# sim_stall_diag.sh -- 同时启动 8 连接（无错开）+ W71 采样，用于诊断 0x3E 之后仍出现的
#   "同时连接"停顿。板须为 0x3D 诊断位流（W71 = compact TX bundle）。
#   usage: bash /tmp/sim_stall_diag.sh <tag> [rounds] [maxbytes]
set -u
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
B=/tmp/p7b_biz; P=/home/a/p11_bench; mkdir -p "$P"
TAG=${1:-simd}; ROUNDS=${2:-3}; MB=${3:-16777216}
reg(){ $T/reg_rw /dev/xdma0_user "$1" w 2>/dev/null | tail -1 | sed 's/.*: *//'; }
snaprd(){ $T/reg_rw /dev/xdma0_user 0x18 w 1 >/dev/null 2>&1; sleep 0.05; \
  printf 'W51=%s W52=%s W20=%s W55=%s W66=%s W67=%s W68=%s W71=%s W72=%s' \
    "$(reg 0xEC)" "$(reg 0xF0)" "$(reg 0x70)" "$(reg 0xFC)" "$(reg 0x128)" \
    "$(reg 0x12C)" "$(reg 0x130)" "$(reg 0x13C)" "$(reg 0x140)"; }
$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1
echo "=== SIMDIAG_BEGIN TAG=$TAG ROUNDS=$ROUNDS MB=$MB $(date +%T) BID=$(reg 0x04)"
for r in $(seq 1 "$ROUNDS"); do
  SAMPLES=$P/${TAG}_r${r}_samples5.txt; : > "$SAMPLES"
  STOP=/tmp/simdiag_stop.$TAG.$r; rm -f "$STOP"
  ( while [ ! -f "$STOP" ]; do echo "S $(date +%T) $(snaprd)" >> "$SAMPLES"; sleep 0.4; done ) &
  SPID=$!
  pids=()
  for k in 0 1 2 3 4 5 6 7; do
    ip netns exec nsa timeout 40 "$B/p7b_tcp_sink" --host 192.168.100.2 --port 8080 --conns 1 \
        --maxbytes "$MB" --seconds 6 --poll-ms 2000 --stall-n 2 --check seq --no-pin \
        > $P/${TAG}_r${r}_$k.txt 2>&1 &
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p"; done
  touch "$STOP"; wait "$SPID" 2>/dev/null
  ok=0; st=0
  for k in 0 1 2 3 4 5 6 7; do
    L=$(grep -E 'SINK_CONN' $P/${TAG}_r${r}_$k.txt | tail -1)
    case "$L" in *' OK '*) ok=$((ok+1));; *STALL*) st=$((st+1));; esac
  done
  echo "R$r OK=$ok STALL=$st"
  if [ $st -gt 0 ]; then
    echo '--- SAMPLES (tail) ---'; tail -8 "$SAMPLES"
    echo '--- CONNS ---'
    for k in 0 1 2 3 4 5 6 7; do
      echo "P$k $(grep -E 'SINK_CONN' $P/${TAG}_r${r}_$k.txt | tail -1 | grep -oE '(OK|STALL)|bytes=[0-9]+|conn_ms=[0-9.]+|poll_tmo=[0-9]+' | tr '\n' ' ')"
    done
  fi
done
echo "=== SIMDIAG_END TAG=$TAG $(date +%T)"
