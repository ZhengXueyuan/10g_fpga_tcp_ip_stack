#!/bin/bash
# zw_bucket.sh -- run one rcvbuf bucket (N runs, sequential) + fetch artifacts.
#   Usage: bash zw_bucket.sh <BUCKET> <RUNS> <in|out> [PREFIX]
#     in  : basin ladder run  : 1 sink, conns 3, secs 60, maxbytes 50e6, RUN_TIMEOUT 90
#     out : outside-basin ctl : 1 sink, conns 3, secs 30, maxbytes 30e6, RUN_TIMEOUT 60
#   Tag = <PREFIX><BUCKET>r<i>   (PREFIX default: Z for in, C for out)
#   PEER_PW must be in the environment (forwarded, never written to disk).
set -u
BUCKET=${1:?}; RUNS=${2:?}; MODE=${3:?}; PFX=${4:-}
if [ -z "$PFX" ]; then [ "$MODE" = "in" ] && PFX=Z || PFX=C; fi
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
R=$ROOT/_proj_10g/notes/p9_basin_zero_win_20261017
if [ "$MODE" = "in" ]; then
  RT=90; SECS=60; MB=50000000; EXTRA=""
else
  RT=60; SECS=30; MB=30000000; EXTRA=""
fi
echo "=== BUCKET_BEGIN bucket=$BUCKET runs=$RUNS mode=$MODE pfx=$PFX $(date +%Y-%m-%dT%H:%M:%S) ==="
for i in $(seq 1 "$RUNS"); do
  TAG=${PFX}${BUCKET}r${i}
  echo "--- run $TAG $(date +%H:%M:%S) ---"
  RUN_TIMEOUT=$RT bash "$R/tools/zw_run_arm.sh" "$TAG" 1 0 "$BUCKET" 3 "$SECS" "$MB" > "$R/runs/${TAG}_DRIVER.txt" 2>&1
  RC=$?
  echo "RUN_RC[$TAG]=$RC"
  if [ "$RC" != "0" ]; then echo "BUCKET_ABORT run $TAG rc=$RC"; exit $RC; fi
  bash "$R/tools/zw_fetch.sh" "$TAG" > "$R/runs/${TAG}_FETCH.txt" 2>&1
  echo "FETCH_RC[$TAG]=$?"
done
echo "=== BUCKET_END bucket=$BUCKET $(date +%Y-%m-%dT%H:%M:%S) ==="
