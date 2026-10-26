#!/bin/bash
# run_e1a_board.sh -- one-shot E1a board round: deploy tools, burn 0x33, idle control,
#   10x10GB load, fetch raw. Run from repo root with PEER_PW set.
#   Usage: PEER_PW=... bash _proj_10g/notes/p11_e1a_design_20261027/run_e1a_board.sh
set -u
[ -n "${PEER_PW:-}" ] || { echo "FATAL: PEER_PW required"; exit 3; }
REPO=/d/repo/XCKU5PMini/udp_hls_10g
D=$REPO/_proj_10g/notes/p11_e1a_design_20261027
D_WIN=D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p11_e1a_design_20261027
REPO_WIN=D:/repo/XCKU5PMini/udp_hls_10g
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY D:/repo/XCKU5PMini/udp_hls_10g/tools/peer_ssh.py"
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
mkdir -p "$D/raw"

echo "=== 1) deploy p7b_snap.sh + e1a_latency.sh ==="
$SSH --put "$REPO_WIN/_proj_pcie/p7b_biz/p7b_snap.sh" /tmp/p7b_snap.sh || exit 1
$SSH --put "$D_WIN/e1a_latency.sh" /tmp/e1a_latency.sh || exit 1
$SSH --sudo --timeout 20 "bash -n /tmp/p7b_snap.sh && bash -n /tmp/e1a_latency.sh && echo DEPLOY_OK" || exit 1

echo "=== 2) burn 0x33 + identity ==="
PEER_PW="$PEER_PW" bash "$D/burn_0x33_board.sh" || { echo "BURN_ROUND_FAIL"; exit 1; }

echo "=== 3) E1a latency runs ==="
$SSH --sudo --timeout 1800 "bash /tmp/e1a_latency.sh E1A 10 10000000000" \
  | tee "$D/raw/E1A_CONSOLE.txt"
RC=${PIPESTATUS[0]}
echo "E1A_CONSOLE_RC=$RC"

echo "=== 4) fetch /tmp/E1A_* ==="
$SSH --sudo --timeout 60 "cd /tmp && tar czf /tmp/e1a_raw.tgz E1A_* 2>/dev/null; ls -l /tmp/e1a_raw.tgz" || true
$SSH --get /tmp/e1a_raw.tgz "$D_WIN/raw/e1a_raw.tgz" || { echo "FETCH_FAIL"; exit 1; }
mkdir -p "$D/raw/E1A"
tar -xzf "$D/raw/e1a_raw.tgz" -C "$D/raw/E1A" || { echo "EXTRACT_FAIL"; exit 1; }
ls "$D/raw/E1A" | head

echo "=== 5) metrics ==="
"$PY" "$D/e1a_metrics.py" "$D/raw/E1A" | tee "$D/raw/E1A/E1A_METRICS_STDOUT.txt"
echo "=== E1A_BOARD_DONE rc=$RC ==="
