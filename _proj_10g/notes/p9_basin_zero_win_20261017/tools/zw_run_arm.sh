#!/bin/bash
# zw_run_arm.sh -- LOCAL runner for one p9_basin_zero_win arm (drives zw_arm.sh on the peer).
#
#   Usage: bash zw_run_arm.sh <TAG> <NSINKS> <STAGGER> <RCVBUF> <CONNS> <SECS> <MAXBYTES>
#   Env (exported to the remote shell): SINK_EXTRA RUN_TIMEOUT KW KW2 NW EXPECT_BID RING_C RING_W
#   PEER_PW is used only as a command prefix, never written to disk.
set -u
TAG=${1:?}; NSINKS=${2:?}; STAGGER=${3:?}; RCVBUF=${4:?}; CONNS=${5:?}; SECS=${6:?}; MAXBYTES=${7:?}
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
cd /d/repo/XCKU5PMini/udp_hls_10g
PY=/c/Users/zhxue/anaconda3/python.exe
R=_proj_10g/notes/p9_basin_zero_win_20261017/runs
mkdir -p "$R"
RT=${RUN_TIMEOUT:-240}
ENVP=""
for v in SINK_EXTRA RUN_TIMEOUT KW KW2 NW EXPECT_BID RING_C RING_W; do
  if [ -n "${!v:-}" ]; then
    ENVP="$ENVP $(printf '%s=%q' "$v" "${!v}")"
  fi
done
CMD="cd /tmp/p7b_biz && env $ENVP bash zw_arm.sh $TAG $NSINKS $STAGGER $RCVBUF $CONNS $SECS $MAXBYTES"
echo "=== LOCAL_RUN tag=$TAG $(date +%Y-%m-%dT%H:%M:%S) timeout=$((RT+180)) ==="
echo "REMOTE_CMD: $CMD"
PEER_PW=${PEER_PW:?PEER_PW env required} $PY tools/peer_ssh.py --timeout $((RT+180)) --sudo "$CMD" 2>&1 | tee "$R/${TAG}_stdout.txt"
RC=${PIPESTATUS[0]}
echo "=== LOCAL_RUN_DONE tag=$TAG rc=$RC $(date +%H:%M:%S) ==="
exit $RC
