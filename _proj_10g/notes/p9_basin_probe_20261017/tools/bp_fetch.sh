#!/bin/bash
# bp_fetch.sh -- read-only fetch of one arm's /tmp/bp_<TAG>_* artifacts from the peer.
#   Usage: bash bp_fetch.sh <TAG>
#   Round: p9_basin_probe_20261017.  Needs MSYS_NO_PATHCONV=1 (set below).
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
TAG=${1:?usage: bp_fetch.sh TAG}
cd /d/repo/XCKU5PMini/udp_hls_10g
PY=/c/Users/zhxue/anaconda3/python.exe
R=_proj_10g/notes/p9_basin_probe_20261017/raw
mkdir -p "$R"
echo "=== FETCH tag=$TAG $(date +%H:%M:%S) ==="
$PY tools/peer_ssh.py "ls -la /tmp/bp_${TAG}_* 2>/dev/null" > "$R/PEER_LISTING_${TAG}.txt" 2>&1
grep -oE '/tmp/bp_'"${TAG}"'_[^ ]+' "$R/PEER_LISTING_${TAG}.txt" | sort -u | while read -r f; do
  b=$(basename "$f")
  $PY tools/peer_ssh.py --get "$f" "$R/$b" 2>&1
done
echo "=== LOCAL ==="
ls -la "$R" | awk '{print $5, $9}' | grep -E "bp_${TAG}_"
echo "=== FETCH_DONE $(date +%H:%M:%S) ==="
