#!/bin/bash
# fetch_basin.sh -- read-only fetch of one arm's /tmp/basin_<TAG>_* artifacts from the peer.
#   Usage: bash fetch_basin.sh <TAG> [--head N]     (needs MSYS_NO_PATHCONV=1)
#   --head N = fetch only the first N MB of each .pcap* (via dd on the peer).
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
TAG=${1:?usage: fetch_basin.sh TAG [--head N]}
HEADMB=0
[ "${2:-}" = "--head" ] && HEADMB=${3:?--head needs N}
cd /d/repo/XCKU5PMini/udp_hls_10g
PY=/c/Users/zhxue/anaconda3/python.exe
R=_proj_10g/notes/p9_slowbasin_gc_20261017/raw
mkdir -p "$R"
echo "=== FETCH tag=$TAG head=${HEADMB}MB $(date +%H:%M:%S) ==="
$PY tools/peer_ssh.py "ls -la /tmp/basin_${TAG}_* 2>/dev/null" > "$R/PEER_LISTING_${TAG}.txt" 2>&1
grep -oE '/tmp/basin_'"${TAG}"'_[^ ]+' "$R/PEER_LISTING_${TAG}.txt" | sort -u | while read -r f; do
  b=$(basename "$f")
  case "$b" in
    *.pcap*)
      if [ "$HEADMB" -gt 0 ]; then
        $PY tools/peer_ssh.py --sudo "dd if=$f of=/tmp/basin_${TAG}_head.pcap bs=1M count=$HEADMB status=none; chmod 644 /tmp/basin_${TAG}_head.pcap" >/dev/null 2>&1
        $PY tools/peer_ssh.py --get "/tmp/basin_${TAG}_head.pcap" "$R/${b}.head${HEADMB}MB" 2>&1
      else
        $PY tools/peer_ssh.py --get "$f" "$R/$b" 2>&1
      fi ;;
    *) $PY tools/peer_ssh.py --get "$f" "$R/$b" 2>&1 ;;
  esac
done
echo "=== LOCAL ==="
ls -la "$R" | awk '{print $5, $9}' | grep -E "basin_${TAG}_|^$"
echo "=== ALL_FETCH_DONE $(date +%H:%M:%S) ==="
