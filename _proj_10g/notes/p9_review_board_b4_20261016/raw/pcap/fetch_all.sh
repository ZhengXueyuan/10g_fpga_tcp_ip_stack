#!/bin/bash
# read-only fetch of B4 pcaps from peer (MUST have MSYS_NO_PATHCONV=1 to avoid MSYS path mangling)
export MSYS_NO_PATHCONV=1
cd /d/repo/XCKU5PMini/udp_hls_10g
PY=/c/Users/zhxue/anaconda3/python.exe
R=_proj_10g/notes/p9_review_board_b4_20261016/raw/pcap
for f in k0_B4H3_full.pcap0 k0_N4H3_full.pcap0 k0_N4H3_full.pcap1 k0_B4P_S3_full.pcap0 k0_B4P_S3_full.pcap1 k0_B4H2_full.pcap0 k0_B4P_S2_full.pcap0 k0_B4P_S2_full.pcap1 k0_B4P_S2_full.pcap2 k0_B4P_S2_full.pcap3 k0_B4P_S2_full.pcap4; do
  echo "=== $(date +%H:%M:%S) FETCH $f ==="
  $PY tools/peer_ssh.py --get /tmp/$f "$R/$f" 2>&1
  ls -la "$R/$f" 2>/dev/null | awk '{print $5, $9}'
done
echo "=== ALL_FETCH_DONE $(date +%H:%M:%S) ==="
