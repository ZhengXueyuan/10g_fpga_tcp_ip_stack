#!/bin/bash
# =============================================================================
# equiv_ab.sh -- default-switch behavioral-equivalence witness: OLD vs NEW sink binary
#
#   Byte-for-byte equality of the default path is NOT obtainable (the source changed),
#   so the witness is BEHAVIORAL: same configuration, same params, DEFAULT switches only,
#   and the two binaries' SINK_SUM key columns (clean / mism / stall / bytes) must agree
#   up to run-to-run scatter.  Each arm is run TWICE (interleaved) so the run-to-run
#   scatter itself is visible.
#
#   Config: p7b_fake_board.py loopback (same pattern stream the existing gates use):
#     fake board: --bytes 1048576 --conns 2
#     sink      : --conns 2 --seconds 30 --rcvbuf 1048576   (NO new switches)
#
#   Usage:  bash equiv_ab.sh
#   Env: OLD NEW FB BYTES CONNS P0
# =============================================================================
set -u
OLD=${OLD:-/tmp/p7b_biz_prev/p7b_tcp_sink__6d9b14f2_pre_sinkdelta}
NEW=${NEW:-/tmp/p7b_biz/p7b_tcp_sink}
FB=${FB:-/tmp/p7b_biz/p7b_fake_board.py}
BYTES=${BYTES:-1048576}
CONNS=${CONNS:-2}
P0=${P0:-20300}

echo "### EQUIV_AB_BEGIN $(date +%s.%N)"
echo "### OLD $(basename $OLD) md5=$(md5sum $OLD | awk '{print $1}') size=$(stat -c %s $OLD)"
echo "### NEW $(basename $NEW) md5=$(md5sum $NEW | awk '{print $1}') size=$(stat -c %s $NEW)"

one(){   # one <name> <bin> <port>
  local name=$1 bin=$2 port=$3
  python3 "$FB" --listen 127.0.0.1:$port --bytes $BYTES --conns $CONNS > /tmp/equiv_${name}_fb.txt 2>&1 &
  local FPID=$!
  sleep 0.7
  timeout -k 5 120 "$bin" --host 127.0.0.1 --port $port --conns $CONNS --seconds 30 \
      --rcvbuf 1048576 > /tmp/equiv_${name}_sink.txt 2>&1
  local RC=$?
  wait $FPID 2>/dev/null
  echo "===== ARM $name rc=$RC ====="
  grep -E '^SINK_OPTS|^SINK_CONN|^SINK_SUM' /tmp/equiv_${name}_sink.txt
  echo "--- fake board (tail) ---"
  tail -4 /tmp/equiv_${name}_fb.txt
}

for r in 1 2; do
  one OLD_r$r "$OLD" $((P0+2*r-1))
  one NEW_r$r "$NEW" $((P0+2*r))
done

echo "### EQUIV_AB_END $(date +%s.%N)"
