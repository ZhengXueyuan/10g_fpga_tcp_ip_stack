#!/bin/bash
# =============================================================================
# smoke_delta.sh -- board-free smoke test for the three new p7b_tcp_sink switches
#
#   Runs on the PEER box; loopback (127.0.0.1) ONLY -- never touches the board,
#   the NIC setup, tcpdump, or any /dev/xdma* device.  Needs no root.
#   Server = smoke_server.py (same dir / /tmp/p7b_biz; pattern stream identical to
#   p7b_fake_board.py which the existing gates already use).
#
#   Cases (raw readings only; the pass/fail reading belongs to the caller):
#     S1_default        default switches   -> expect close_kind=fin  x2 (default == old behavior)
#     S2_abort_rst      --abort-rst        -> expect close_kind=rst  x2
#     S3_localport_rst  --abort-rst --local-port 40000  -> expect peer_port=40000 x2, rc=0
#     S3b_localport_fin --local-port 40010 (default FIN close) -> registration case:
#                       does the same local port re-bind when the previous close was FIN?
#     S4_delay800       --abort-rst --reconnect-delay-ms 800 (3 conns)
#                       -> expect gap_since_prev_s >= ~0.8 on connections 1,2
#     S4b_delay0        --abort-rst (3 conns, NO delay)  -> negative control for S4 (small gaps)
#   S4 vs S4b differ by EXACTLY ONE variable (the delay switch).
#
#   Usage:  bash smoke_delta.sh [BIN] [SRV] [BYTES] [P0]
# =============================================================================
set -u
BIN=${1:-/tmp/p7b_biz/p7b_tcp_sink}
SRV=${2:-/tmp/p7b_biz/smoke_server.py}
BYTES=${3:-65536}
P0=${4:-20200}

echo "### SMOKE_DELTA_BEGIN $(date +%s.%N)"
echo "### SINK_MD5 $(md5sum $BIN | awk '{print $1}')  SINK_SIZE $(stat -c %s $BIN)"
echo "### SRV_MD5 $(md5sum $SRV | awk '{print $1}')"
echo "### HOST $(hostname) python3=$(python3 --version 2>&1)"

case_run(){   # case_run <name> <server_port> <conns> [sink extra args...]
  local name=$1 port=$2 conns=$3; shift 3
  echo "===== CASE $name server_port=$port sink_conns=$conns extra='$*' $(date +%s.%N) ====="
  python3 "$SRV" --listen 127.0.0.1:$port --conns $conns --bytes $BYTES > /tmp/smoke_${name}_srv.txt 2>&1 &
  local SPID=$!
  sleep 0.4
  timeout -k 5 60 "$BIN" --host 127.0.0.1 --port $port --conns $conns --seconds 30 \
      --maxbytes $BYTES "$@" > /tmp/smoke_${name}_sink.txt 2>&1
  local RC=$?
  wait $SPID 2>/dev/null
  echo "SINK_RC=$RC"
  echo "--- sink key lines ---"
  grep -E '^SINK_CHECK|^SINK_LIMITS|^SINK_OPTS|^SINK_CONN|^SINK_SUM' /tmp/smoke_${name}_sink.txt
  echo "--- server output ---"
  cat /tmp/smoke_${name}_srv.txt
  echo "===== CASE_END $name ====="
}

case_run S1_default       $((P0+1)) 2
case_run S2_abort_rst     $((P0+2)) 2 --abort-rst
case_run S3_localport_rst $((P0+3)) 2 --abort-rst --local-port 40000
case_run S3b_localport_fin $((P0+4)) 2 --local-port 40010
case_run S4_delay800      $((P0+5)) 3 --abort-rst --reconnect-delay-ms 800
case_run S4b_delay0       $((P0+6)) 3 --abort-rst

echo "### SMOKE_DELTA_END $(date +%s.%N)"
