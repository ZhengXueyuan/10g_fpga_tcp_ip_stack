#!/bin/bash
# fetch_readings.sh -- 把对端 /tmp 下的本轮读数原件拉回轮目录 runs/
set -u
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
B=/d/repo/XCKU5PMini/udp_hls_10g
BW=D:/repo/XCKU5PMini/udp_hls_10g
P=/c/Users/zhxue/anaconda3/python.exe
SSH="$P $BW/tools/peer_ssh.py"
OUT=$BW/_proj_10g/notes/p9_board_0x27_k0_20261015/runs
mkdir -p "$B/_proj_10g/notes/p9_board_0x27_k0_20261015/runs"

GETS=(
 "/tmp/k0run_K0P_S2.log:run_K0P_S2.log"
 "/tmp/k0run_K0P_S3.log:run_K0P_S3.log"
 "/tmp/k0run_K0N_S2.log:run_K0N_S2.log"
 "/tmp/k0run_K0N_S3.log:run_K0N_S3.log"
 "/tmp/k0run_K0N_S2B.log:run_K0N_S2B.log"
 "/tmp/k0run_K0N_S2C.log:run_K0N_S2C.log"
 "/tmp/k0_K0P_S2_sink.txt:sink_K0P_S2.txt"
 "/tmp/k0_K0P_S3_sink.txt:sink_K0P_S3.txt"
 "/tmp/k0_K0N_S2_sink.txt:sink_K0N_S2.txt"
 "/tmp/k0_K0N_S3_sink.txt:sink_K0N_S3.txt"
 "/tmp/k0_K0N_S2B_sink.txt:sink_K0N_S2B.txt"
 "/tmp/k0_K0N_S2C_sink.txt:sink_K0N_S2C.txt"
 "/tmp/k0_K0P_S2_snap.log:snap_K0P_S2.log"
 "/tmp/k0_K0N_S2_snap.log:snap_K0N_S2.log"
 "/tmp/k0_K0P_S3_snap.log:snap_K0P_S3.log"
 "/tmp/k0_K0N_S3_snap.log:snap_K0N_S3.log"
 "/tmp/k0_K0P_S2_ctl.pcap:ctl_K0P_S2.pcap"
 "/tmp/k0_K0N_S2_ctl.pcap:ctl_K0N_S2.pcap"
 "/tmp/k0_K0P_S3_ctl.pcap:ctl_K0P_S3.pcap"
 "/tmp/k0_K0N_S3_ctl.pcap:ctl_K0N_S3.pcap"
 "/tmp/k0_K0P_S2_nstat_pre.txt:nstat_pre_K0P_S2.txt"
 "/tmp/k0_K0P_S2_nstat_post.txt:nstat_post_K0P_S2.txt"
 "/tmp/k0_K0N_S2_nstat_pre.txt:nstat_pre_K0N_S2.txt"
 "/tmp/k0_K0N_S2_nstat_post.txt:nstat_post_K0N_S2.txt"
 "/tmp/k0an_K0P_S2.log:an_K0P_S2.log"
 "/tmp/k0an_K0P_S3.log:an_K0P_S3.log"
 "/tmp/k0an_K0N_S2.log:an_K0N_S2.log"
 "/tmp/k0an_K0N_S3.log:an_K0N_S3.log"
 "/tmp/k0an_K0N_S2B.log:an_K0N_S2B.log"
 "/tmp/k0an_K0N_S2C.log:an_K0N_S2C.log"
)
for g in "${GETS[@]}"; do
  R="${g%%:*}"; L="${g##*:}"
  if $SSH --sudo --get "$R" "$OUT/$L" >/dev/null 2>&1; then echo "GET_OK  $L"; else echo "GET_FAIL $R"; fi
done
echo "--- runs/ 清单 ---"
ls -la "$B/_proj_10g/notes/p9_board_0x27_k0_20261015/runs/"
