#!/bin/bash
# fetch_arm.sh -- read-only fetch of one arm's /tmp/k0_<TAG>_* artifacts from the peer.
#   Usage: bash fetch_arm.sh <TAG>          (needs MSYS_NO_PATHCONV=1; PEER_PW not needed for sftp)
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
TAG=${1:?usage: fetch_arm.sh TAG}
cd /d/repo/XCKU5PMini/udp_hls_10g
PY=/c/Users/zhxue/anaconda3/python.exe
R=_proj_10g/notes/p9_p3win_trickle_board_20261017/raw/$TAG
mkdir -p "$R"
echo "=== FETCH tag=$TAG $(date +%H:%M:%S) ==="
$PY tools/peer_ssh.py "ls -la /tmp/k0_${TAG}_* 2>/dev/null" > "$R/PEER_LISTING.txt" 2>&1
grep -oE '/tmp/k0_'"${TAG}"'_[^ ]+' "$R/PEER_LISTING.txt" | sort -u | while read -r f; do
  b=$(basename "$f")
  $PY tools/peer_ssh.py --get "$f" "$R/$b" 2>&1
done
echo "=== LOCAL === "
ls -la "$R" | awk '{print $5, $9}'
echo "=== ALL_FETCH_DONE $(date +%H:%M:%S) ==="
