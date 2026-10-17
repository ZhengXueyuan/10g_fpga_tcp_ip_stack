#!/bin/bash
# p1b_s6.sh -- S-6: ch1 (p1) TCP fast-arm regression.
#   usage: p1b_s6.sh [DUR_SECS]        (default 30)
#   Recipe = p9_board_0x2A C-fast: single sink, --rcvbuf 2920 --conns 1 --check lane8.
#   Rate = ss bytes_received per second (independent of the sink's own accounting).
set -u
DUR=${1:-30}
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
S=/tmp/p1b_snap.sh
BIN=/tmp/p7b_biz/p7b_tcp_sink
BOARD=192.168.100.2
IF1=enp1s0f1np1
KW='0 1 20 36 43 51 52 53 54 55 63 64 65 71 72 73 74 75'
port_of(){ ss -tinH state established '( dport = :8080 )' 2>/dev/null | grep -oE '192\.168\.100\.100:[0-9]+' | head -1 | cut -d: -f2; }
bytes_of(){ ss -tinH state established '( dport = :8080 )' 2>/dev/null | awk -v p=":$1" '
  index($0,"192.168.100.100" p){insock=1; next}
  insock && /bytes_received:/{for(i=1;i<=NF;i++) if($i ~ /^bytes_received:/){split($i,a,":"); s+=a[2]}; insock=0}
  END{print s+0}'; }
echo "=== P1BOARD-S6 $(date +%s.%N) $(date) DUR=$DUR ==="
pgrep -a -x p7b_tcp_sink && { echo "PRECHECK_FAIL leftover sink"; exit 3; }
echo -n 'p1 carrier='; cat /sys/class/net/$IF1/carrier
echo "--- NIC p1 counters PRE ---"
ethtool -S $IF1 | grep -E 'port_(rx|tx)_(bytes|packets)'
echo "--- SNAP PRE ---"
bash $S snap S6_PRE $KW
T0=$(date +%s.%N)
$BIN --host $BOARD --port 8080 --rcvbuf 2920 --conns 1 --seconds $((DUR+60)) --maxbytes 2000000000 --check lane8 > /tmp/p1b_S6_sink.txt 2>&1 &
PID=$!
PORT=""
for i in $(seq 1 100); do PORT=$(port_of); [ -n "$PORT" ] && break; sleep 0.2; done
echo "SINK_PID=$PID PORT=$PORT T0=$T0"
B0=""; TB0=""
for i in $(seq 1 $DUR); do
  B=$(bytes_of "$PORT"); TB=$(date +%s.%N)
  [ -z "$B0" ] && { B0=$B; TB0=$TB; }
  echo "SS_T $TB port=$PORT bytes=$B"
  sleep 1
done
TB1=$(date +%s.%N); B1=$(bytes_of "$PORT")
echo "SS_SPAN t0=$TB0 t1=$TB1 b0=$B0 b1=$B1"
awk -v a=$B0 -v b=$B1 -v t0=$TB0 -v t1=$TB1 'BEGIN{dt=t1-t0; printf "RATE_Mbps %.1f (bytes=%d dt=%.3f)\n",(b-a)*8/dt/1e6,(b-a),dt}'
kill -TERM $PID 2>/dev/null; sleep 1; kill -9 $PID 2>/dev/null
echo "--- sink output ---"
grep -E '^SINK_' /tmp/p1b_S6_sink.txt | tail -8
echo "--- NIC p1 counters POST ---"
ethtool -S $IF1 | grep -E 'port_(rx|tx)_(bytes|packets)'
echo "--- SNAP POST ---"
bash $S snap S6_POST $KW
echo "=== P1BOARD-S6-END $(date +%s.%N) ==="
