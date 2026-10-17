#!/bin/bash
# zw_fetch.sh -- read-only fetch of one arm's /tmp/zw_<TAG>_* artifacts from the peer.
#   Usage: bash zw_fetch.sh <TAG>
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
TAG=${1:?usage: zw_fetch.sh TAG}
cd /d/repo/XCKU5PMini/udp_hls_10g
PY=/c/Users/zhxue/anaconda3/python.exe
R=_proj_10g/notes/p9_basin_zero_win_20261017/raw
mkdir -p "$R"
echo "=== FETCH tag=$TAG $(date +%H:%M:%S) ==="
$PY tools/peer_ssh.py "ls -la /tmp/zw_${TAG}_* 2>/dev/null" > "$R/PEER_LISTING_${TAG}.txt" 2>&1
grep -oE '/tmp/zw_'"${TAG}"'_[^ ]+' "$R/PEER_LISTING_${TAG}.txt" | sort -u | while read -r f; do
  b=$(basename "$f")
  $PY tools/peer_ssh.py --get "$f" "$R/$b" 2>&1
done
echo "=== LOCAL ==="
ls -la "$R" | awk '{print $5, $9}' | grep -E "zw_${TAG}_"
echo "=== FETCH_DONE $(date +%H:%M:%S) ==="
