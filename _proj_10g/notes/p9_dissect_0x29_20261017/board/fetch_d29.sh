#!/bin/bash
# fetch_d29.sh -- 0x29 拆刀轮: 取回某臂的 /tmp/d29_<TAG>_* 产物 (母本 = slowbasin fetch_basin.sh 同族)
#   Usage: bash fetch_d29.sh <TAG> [--head N]   (需 MSYS_NO_PATHCONV=1; 大 pcap 用 --head N 只取前 N MB)
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
TAG=${1:?usage: fetch_d29.sh TAG [--head N]}
HEADMB=0
[ "${2:-}" = "--head" ] && HEADMB=${3:?--head needs N}
cd /d/repo/XCKU5PMini/udp_hls_10g
PY=/c/Users/zhxue/anaconda3/python.exe
R=_proj_10g/notes/p9_dissect_0x29_20261017/runs/remote
mkdir -p "$R"
echo "=== FETCH tag=$TAG head=${HEADMB}MB $(date +%H:%M:%S) ==="
$PY tools/peer_ssh.py "ls -la /tmp/d29_${TAG}_* 2>/dev/null" > "$R/PEER_LISTING_${TAG}.txt" 2>&1
grep -oE '/tmp/d29_'"${TAG}"'_[^ ]+' "$R/PEER_LISTING_${TAG}.txt" | sort -u | while read -r f; do
  b=$(basename "$f")
  case "$b" in
    *.pcap*)
      if [ "$HEADMB" -gt 0 ]; then
        $PY tools/peer_ssh.py --sudo "dd if=$f of=/tmp/d29_${TAG}_head.pcap bs=1M count=$HEADMB status=none; chmod 644 /tmp/d29_${TAG}_head.pcap" >/dev/null 2>&1
        $PY tools/peer_ssh.py --get "/tmp/d29_${TAG}_head.pcap" "$R/${b}.head${HEADMB}MB" 2>&1
      else
        $PY tools/peer_ssh.py --get "$f" "$R/$b" 2>&1
      fi ;;
    *) $PY tools/peer_ssh.py --get "$f" "$R/$b" 2>&1 ;;
  esac
done
echo "=== LOCAL ==="
ls -la "$R" | awk '{print $5, $9}' | grep -E "d29_${TAG}_|^$"
echo "=== ALL_FETCH_DONE $(date +%H:%M:%S) ==="
