#!/bin/bash
# fetch_readings.sh -- 把对端 /tmp 下的本轮读数原件拉回轮目录 runs/
set -u
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
B=/d/repo/XCKU5PMini/udp_hls_10g
BW=D:/repo/XCKU5PMini/udp_hls_10g
P=/c/Users/zhxue/anaconda3/python.exe
SSH="$P $BW/tools/peer_ssh.py"
OUT=$BW/_proj_10g/notes/p9_board_0x28_k0_20261016/runs
mkdir -p "$B/_proj_10g/notes/p9_board_0x28_k0_20261016/runs"

GETS=(
 "/tmp/k0run_B4P_S2.log:run_B4P_S2.log"
 "/tmp/k0run_B4P_S3.log:run_B4P_S3.log"
 "/tmp/k0_B4P_S2_sink.txt:sink_B4P_S2.txt"
 "/tmp/k0_B4P_S3_sink.txt:sink_B4P_S3.txt"
 "/tmp/k0_B4P_S2_snap.log:snap_B4P_S2.log"
 "/tmp/k0_B4P_S3_snap.log:snap_B4P_S3.log"
 "/tmp/k0_B4P_S2_pre.txt:pre_B4P_S2.txt"
 "/tmp/k0_B4P_S2_post.txt:post_B4P_S2.txt"
 "/tmp/k0_B4P_S3_pre.txt:pre_B4P_S3.txt"
 "/tmp/k0_B4P_S3_post.txt:post_B4P_S3.txt"
 "/tmp/k0_B4P_S2_ctl.pcap:ctl_B4P_S2.pcap"
 "/tmp/k0_B4P_S3_ctl.pcap:ctl_B4P_S3.pcap"
 "/tmp/k0_B4P_S2_nstat_pre.txt:nstat_pre_B4P_S2.txt"
 "/tmp/k0_B4P_S2_nstat_post.txt:nstat_post_B4P_S2.txt"
 "/tmp/k0_B4P_S3_nstat_pre.txt:nstat_pre_B4P_S3.txt"
 "/tmp/k0_B4P_S3_nstat_post.txt:nstat_post_B4P_S3.txt"
 "/tmp/k0an_B4P_S2.log:an_B4P_S2.log"
 "/tmp/k0an_B4P_S3.log:an_B4P_S3.log"
 "/tmp/k0an_B4H3.log:an_B4H3.log"
 "/tmp/k0run_N4H3.log:run_N4H3.log"
 "/tmp/k0_N4H3_sink1.txt:sink_N4H3_1.txt"
 "/tmp/k0_N4H3_sink2.txt:sink_N4H3_2.txt"
 "/tmp/k0_N4H3_snap.log:snap_N4H3.log"
 "/tmp/k0_N4H3_pre.txt:pre_N4H3.txt"
 "/tmp/k0_N4H3_post.txt:post_N4H3.txt"
 "/tmp/k0_N4H3_ctl.pcap:ctl_N4H3.pcap"
 "/tmp/k0_N4H3_nstat_pre.txt:nstat_pre_N4H3.txt"
 "/tmp/k0_N4H3_nstat_post.txt:nstat_post_N4H3.txt"
 "/tmp/k0an_N4H3.log:an_N4H3.log"
 "/tmp/k0run_H2P.log:run_B4H2_ref.log"
)
for g in "${GETS[@]}"; do
  R="${g%%:*}"; L="${g##*:}"
  if $SSH --sudo --get "$R" "$OUT/$L" >/dev/null 2>&1; then echo "GET_OK  $L"; else echo "GET_FAIL $R"; fi
done
echo "--- runs/ 清单 ---"
ls -la "$B/_proj_10g/notes/p9_board_0x28_k0_20261016/runs/"
