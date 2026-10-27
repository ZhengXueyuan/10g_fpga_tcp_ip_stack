#!/bin/bash
# run_app8_board.sh -- P11 APP8 (0x34) 板级轮：部署工具 -> 编译 -> 烧 0x34 -> 8 并发跑
#   Usage: PEER_PW=... bash run_app8_board.sh
#   前提：bits/wrapper_p4_0x34.bit + bits/SHA256.txt 已由 finalize_build 生成。
#   ⛔ 2026-10-28 状态：0x34 四次构建全部 TIMING_GATE FAIL ⇒ bits/ 未生成，本脚本**未执行**。
#   ⭐ 端口映射已按 2026-10-28 现核修正：8-app 组在 port0/J7 = 板 IP 192.168.100.4，
#      从对端 **nsb(enp1s0f0np0, 192.168.100.101/32)** 发；port1/J8 = 192.168.100.2/nsa
#      只有单 app（q1_app），绝不能用于 8 连接测试。OCC A/B 的主见证协议见
#      DESIGN_OCC_V6 §6.6（tcpdump 连续下行帧的 tcp.window），不是本脚本的连通性跑法。
set -u
[ -n "${PEER_PW:-}" ] || { echo "FATAL: PEER_PW required"; exit 3; }
REPO=/d/repo/XCKU5PMini/udp_hls_10g
D=$REPO/_proj_10g/notes/p11_app8_contract_20261027
D_WIN=D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p11_app8_contract_20261027
REPO_WIN=D:/repo/XCKU5PMini/udp_hls_10g
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY D:/repo/XCKU5PMini/udp_hls_10g/tools/peer_ssh.py"
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
mkdir -p "$D/raw" "$D/compile_peer"

echo "=== 1) deploy tools ==="
$SSH --put "$REPO_WIN/_proj_pcie/p7b_biz/p7b_snap.sh" /tmp/p7b_snap.sh || exit 1
$SSH --put "$REPO_WIN/_proj_pcie/p7b_biz/p7b_io.h" /tmp/p7b_biz/p7b_io.h || exit 1
$SSH --put "$REPO_WIN/_proj_pcie/p7b_biz/p7b_pattern.h" /tmp/p7b_biz/p7b_pattern.h || exit 1
$SSH --put "$REPO_WIN/_proj_pcie/p7b_biz/p7b_tcp_sink_multi.cpp" /tmp/p7b_biz/p7b_tcp_sink_multi.cpp || exit 1
$SSH --sudo --timeout 30 "cd /tmp/p7b_biz && g++ -O2 -pthread -std=c++17 -o p7b_tcp_sink_multi p7b_tcp_sink_multi.cpp 2>&1 | tee /tmp/p7b_biz/compile_multi.log; echo GCC_RC=\${PIPESTATUS[0]}; ls -l p7b_tcp_sink_multi" || exit 1
$SSH --get /tmp/p7b_biz/compile_multi.log "$D_WIN/compile_peer/compile_multi.log" || true

echo "=== 2) burn 0x34 + identity ==="
PEER_PW="$PEER_PW" bash "$D/burn_0x34_board.sh" || { echo BURN_ROUND_FAIL; exit 1; }

W="0 5 14 20 43 51 52 53 54 65 66 67 68 69 83"
snap() { local t=$1; $SSH --sudo --timeout 60 "NW=97 UNIMPL_ADDR=0x1B4 EXPECT_BID=0x00000034 bash /tmp/p7b_snap.sh snap $t $W"; }

echo "=== 3) idle negative control (2s) ==="
snap APP8_IDLE0 | tee "$D/raw/APP8_IDLE0.txt"
sleep 2
snap APP8_IDLE1 | tee "$D/raw/APP8_IDLE1.txt"

echo "=== 4) 8-way concurrent downlink (port A) ==="
snap APP8_R8_PRE | tee "$D/raw/APP8_R8_PRE.txt"
$SSH --sudo --timeout 300 "ip netns exec nsb taskset -c 0-7 /tmp/p7b_biz/p7b_tcp_sink_multi --host 192.168.100.4 --port 8080 --conns 8 --maxbytes 268435456 --seconds 60 --rcvbuf 1048576 --check lane8" | tee "$D/raw/APP8_R8_CONSOLE.txt"
RC8=${PIPESTATUS[0]}
echo "APP8_R8_RC=$RC8"
sleep 1
snap APP8_R8_POST | tee "$D/raw/APP8_R8_POST.txt"

echo "=== 5) single-conn baseline ==="
snap APP8_R1_PRE | tee "$D/raw/APP8_R1_PRE.txt"
$SSH --sudo --timeout 300 "ip netns exec nsb taskset -c 0-7 /tmp/p7b_biz/p7b_tcp_sink_multi --host 192.168.100.4 --port 8080 --conns 1 --maxbytes 268435456 --seconds 60 --rcvbuf 1048576 --check lane8" | tee "$D/raw/APP8_R1_CONSOLE.txt"
RC1=${PIPESTATUS[0]}
echo "APP8_R1_RC=$RC1"
sleep 1
snap APP8_R1_POST | tee "$D/raw/APP8_R1_POST.txt"

echo "=== 6) 9th-connection rejection (8 held open, 6s) ==="
snap APP8_R9_PRE | tee "$D/raw/APP8_R9_PRE.txt"
$SSH --sudo --timeout 120 "ip netns exec nsb taskset -c 0-7 /tmp/p7b_biz/p7b_tcp_sink_multi --host 192.168.100.4 --port 8080 --conns 9 --maxbytes 1000000000 --seconds 6 --rcvbuf 1048576 --check lane8" | tee "$D/raw/APP8_R9_CONSOLE.txt"
RC9=${PIPESTATUS[0]}
echo "APP8_R9_RC=$RC9 (expect 1: 8 stall-at-deadline + 1 connect fail)"
sleep 1
snap APP8_R9_POST | tee "$D/raw/APP8_R9_POST.txt"

echo "=== 7) fetch raw + manifests ==="
$SSH --sudo --timeout 60 "cd /tmp && tar czf /tmp/app8_raw.tgz p7b_biz/compile_multi.log 2>/dev/null; ls -l /tmp/app8_raw.tgz" || true
$SSH --get /tmp/app8_raw.tgz "$D_WIN/raw/app8_raw.tgz" || true
( cd "$D/raw" && sha256sum $(ls | grep -v SHA256SUMS) > SHA256SUMS.txt )
echo "=== APP8_BOARD_DONE rc8=$RC8 rc1=$RC1 rc9=$RC9 ==="
