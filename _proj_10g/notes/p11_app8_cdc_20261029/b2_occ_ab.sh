#!/bin/bash
# b2_occ_ab.sh -- P11 OCC board arm (DESIGN_OCC_V6 6.6 adapted to 0x36/0x37 + CDC).
#   Usage: PEER_PW=<pw> bash b2_occ_ab.sh 0x36
#   Preconditions: board burned with that tag; netns up; /tmp/p7b_biz/p7b_tcp_sink_multi compiled.
#   Witness: W62 (0x118 app_ctrl.rx_occ_bytes) + per-connection TCP window from board->PC data frames.
set -u
TAG=${1:-0x36}
OUT=/d/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p11_app8_cdc_20261029
REPO_WIN=D:/repo/XCKU5PMini/udp_hls_10g
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY $REPO_WIN/tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
D=/dev/xdma0_user
[ -n "${PEER_PW:-}" ] || { echo "FATAL: PEER_PW required"; exit 3; }
mkdir -p "$OUT/raw"
exec > >(tee "$OUT/raw/B2_OCC_${TAG}_$(date +%Y%m%d_%H%M%S).txt") 2>&1
echo "=== B2_OCC_BEGIN tag=$TAG $(date +%s.%N) $(date)"

echo "--- 0) deploy parser ---"
$SSH --put "$REPO_WIN/_proj_10g/notes/p11_app8_cdc_20261029/occ_win.py" /tmp/occ_win.py || echo PUT_SKIP_USE_EXISTING
$SSH "python3 -c 'import py_compile;py_compile.compile(\"/tmp/occ_win.py\",doraise=True);print(\"PY_OK\")'" || exit 1

echo "--- 1) clear stall + settle ---"
$SSH --sudo "T=$T; D=$D; \$T/reg_rw \$D 0x08 w 0x0 >/dev/null 2>&1; sleep 2; printf 'W62_pre='; \$T/reg_rw \$D 0x118 w 2>&1 | tail -1 | sed 's/.*: *//'; printf 'W97_pre='; \$T/reg_rw \$D 0x1A4 w 2>&1 | tail -1 | sed 's/.*: *//'"
$SSH --sudo "pkill -f p7b_tcp_sink_multi 2>/dev/null; sleep 0.5; echo CLEAN"

echo "--- 2) RX stall FIRST (0x08=0x4) ---"
$SSH --sudo "T=$T; D=$D; \$T/reg_rw \$D 0x08 w 0x4 >/dev/null 2>&1; sleep 0.2; printf 'SCRATCH_stall='; \$T/reg_rw \$D 0x08 w 2>&1 | tail -1 | sed 's/.*: *//'"

echo "--- 3) start 8-conn sink (conn0 sends 16,384 B) and wait W62 >= 12288 ---"
$SSH --sudo "cd /tmp/p7b_biz && nohup ip netns exec nsb ./p7b_tcp_sink_multi --host 192.168.100.4 --port 8080 --conns 8 --maxbytes 4294967296 --seconds 40 --check seq --send-conns 1 --send-bytes 16384 > /tmp/occ_sink_${TAG}.txt 2>&1 & echo SINK_STARTED"
sleep 1
$SSH --sudo "T=$T; D=$D; for i in \$(seq 1 100); do V=\$(\$T/reg_rw \$D 0x118 w 2>/dev/null | tail -1 | sed 's/.*: *//'); if [ \$((V)) -ge 12288 ]; then echo \"W62_REACHED i=\$i W62=\$V\"; break; fi; sleep 0.05; done; printf 'W62_at_stall='; \$T/reg_rw \$D 0x118 w 2>&1 | tail -1 | sed 's/.*: *//'; printf 'W97_at_stall='; \$T/reg_rw \$D 0x1A4 w 2>&1 | tail -1 | sed 's/.*: *//'"

echo "--- 4) capture board->PC windows for 2 s ---"
$SSH --sudo "timeout 2 ip netns exec nsb tcpdump -i any -nn -s 96 -w /tmp/occ_${TAG}.pcap 'tcp and src host 192.168.100.4' 2>/dev/null; ls -l /tmp/occ_${TAG}.pcap"
$SSH --sudo "T=$T; D=$D; printf 'W62_after_cap='; \$T/reg_rw \$D 0x118 w 2>&1 | tail -1 | sed 's/.*: *//'; printf 'W97_after_cap='; \$T/reg_rw \$D 0x1A4 w 2>&1 | tail -1 | sed 's/.*: *//'"

echo "--- 5) clear stall + stop sink ---"
$SSH --sudo "T=$T; D=$D; \$T/reg_rw \$D 0x08 w 0x0 >/dev/null 2>&1; pkill -f p7b_tcp_sink_multi 2>/dev/null; sleep 1; printf 'W62_post='; \$T/reg_rw \$D 0x118 w 2>&1 | tail -1 | sed 's/.*: *//'; printf 'SCRATCH='; \$T/reg_rw \$D 0x08 w 2>&1 | tail -1 | sed 's/.*: *//'"
tail -6 /tmp/occ_sink_${TAG}.txt 2>/dev/null || $SSH --sudo "tail -6 /tmp/occ_sink_${TAG}.txt"

echo "--- 6) window parse ---"
$SSH --sudo "python3 /tmp/occ_win.py /tmp/occ_${TAG}.pcap 8"
echo "=== B2_OCC_END tag=$TAG $(date +%s.%N) $(date)"
