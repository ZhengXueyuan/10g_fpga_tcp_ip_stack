#!/bin/bash
# b1_func_0x37.sh -- P11 APP8 CDC+OCC (0x37) board functional round.
#   Assumes: 0x36 burned (burn_0x36_board.sh) and netns recipe available.
#   Checks: identity -> 8-conn downlink 12KB -> 8-conn uplink 12KB -> stats/W97 -> 9th conn.
#   QSPI NEVER written; this script only reads registers and drives TCP from the peer.
set -u
OUT=/d/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p11_app8_cdc_20261029
REPO_WIN=D:/repo/XCKU5PMini/udp_hls_10g
OUT_WIN=D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p11_app8_cdc_20261029
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY $REPO_WIN/tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
S=/tmp/p7b_snap.sh
[ -n "${PEER_PW:-}" ] || { echo "FATAL: PEER_PW required"; exit 3; }
mkdir -p "$OUT/raw"
exec > >(tee "$OUT/raw/B1_FUNC_0x37_$(date +%Y%m%d_%H%M%S).txt") 2>&1
echo "=== B1_FUNC_BEGIN $(date +%s.%N) $(date)"

echo "--- 0) deploy source + snap + env script; compile ---"
$SSH "mkdir -p /tmp/p7b_biz" || exit 1
for f in p7b_tcp_sink_multi.cpp p7b_io.h p7b_pattern.h p7b_affinity.h; do
  $SSH --put "$REPO_WIN/_proj_pcie/p7b_biz/$f" "/tmp/p7b_biz/$f" || { echo "PUT_FAIL $f"; exit 1; }
done
$SSH --put "$REPO_WIN/_proj_pcie/p7b_biz/p7b_snap.sh" /tmp/p7b_snap.sh || exit 1
$SSH --put "$OUT_WIN/b0_env_setup_0x36.sh" /tmp/b0_env_setup_0x36.sh || exit 1
$SSH --sudo "cd /tmp/p7b_biz && g++ -O3 -pthread -o p7b_tcp_sink_multi p7b_tcp_sink_multi.cpp && ls -l p7b_tcp_sink_multi" || { echo "COMPILE_FAIL"; exit 1; }
$SSH --sudo "bash -n /tmp/p7b_snap.sh && bash -n /tmp/b0_env_setup_0x36.sh && echo DEPLOY_OK" || exit 1

echo "--- 1) netns/env setup (nsb 192.168.100.101/32 -> board .4) ---"
$SSH --sudo "bash /tmp/b0_env_setup_0x36.sh" || { echo "ENV_FAIL"; exit 1; }

echo "--- 2) identity + baseline regs ---"
$SSH --sudo "T=$T; for A in 0x00 0x04 0x14 0x1B8 0x1A4 0xEC 0xF0 0xF4 0xF8 0x118 0x08; do printf 'REG_%s=' \$A; \$T/reg_rw /dev/xdma0_user \$A w 2>&1 | tail -1 | sed 's/.*: *//'; done"
$SSH --sudo "NW=98 EXPECT_BID=0x00000037 UNIMPL_ADDR=0x1B8 bash $S id; echo ID_RC=\$?"

echo "--- 3) 8-conn downlink: each connection gets 12,288 B (lane8 check) ---"
$SSH --sudo "cd /tmp/p7b_biz && ip netns exec nsb ./p7b_tcp_sink_multi --host 192.168.100.4 --port 8080 --conns 8 --maxbytes 12288 --seconds 30 --check lane8"; echo "DL_RC=$?"

echo "--- 3b) stats after downlink (wait >= 3 s for 1024-clk shadow refresh) ---"
sleep 3
$SSH --sudo "T=$T; for A in 0xEC 0xF0 0xF4 0xF8 0x118 0x1A4; do printf 'REG_%s=' \$A; \$T/reg_rw /dev/xdma0_user \$A w 2>&1 | tail -1 | sed 's/.*: *//'; done"

echo "--- 4) 8-conn uplink: each sends 12,288 B while receiving (seq check) ---"
$SSH --sudo "cd /tmp/p7b_biz && ip netns exec nsb ./p7b_tcp_sink_multi --host 192.168.100.4 --port 8080 --conns 8 --maxbytes 16777216 --seconds 15 --check seq --send-conns 8 --send-bytes 12288"; echo "UL_RC=$?"
sleep 3

echo "--- 5) stats after uplink ---"
$SSH --sudo "T=$T; for A in 0xEC 0xF0 0xF4 0xF8 0x118 0x1A4 0x1A8 0x1AC 0x1B0 0x1B4; do printf 'REG_%s=' \$A; \$T/reg_rw /dev/xdma0_user \$A w 2>&1 | tail -1 | sed 's/.*: *//'; done"

echo "--- 6) 9th connection attempt (must not get an app slot) ---"
$SSH --sudo "ip netns exec nsb python3 -c \"
import socket
s=socket.socket(); s.settimeout(2.0)
try:
    s.connect(('192.168.100.4',8080)); print('NINTH_CONNECT=OK')
except Exception as e:
    print('NINTH_CONNECT=FAIL', type(e).__name__, e)
try: s.close()
except Exception: pass
\""

echo "--- 7) final identity + W97 ---"
$SSH --sudo "T=$T; for A in 0x04 0x1A4; do printf 'REG_%s=' \$A; \$T/reg_rw /dev/xdma0_user \$A w 2>&1 | tail -1 | sed 's/.*: *//'; done"
$SSH --sudo "echo -n 'CARRIER_P0='; ip netns exec nsb cat /sys/class/net/enp1s0f0np0/carrier; echo -n 'SCRATCH_0x08='; $T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1 | sed 's/.*: *//'"
echo "=== B1_FUNC_END $(date +%s.%N) $(date)"
