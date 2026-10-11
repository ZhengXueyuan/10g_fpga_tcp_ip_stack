#!/bin/bash
# run_tcp_mid.sh -- P8 TCP 臂 **中流捕获** (位流 0x21): 先起发端, 等启动突发过去, 再 arm 镜像
#   目的 = ① 试"稳态流"能否被 C2H 环读路径整段吃掉 (启动突发之外的突发形态);
#          ② 拿到一段中流连续字节流 (离线按图案流搜索定位 = 内容判据的替代路径)
#   ⚠️ 本配置下工具的 --pat-off 不可对齐 (arm 时刻的流位置未知) ⇒ 必须 --no-verify;
#      内容判据 = 离线定位 (runs/ 里的分析件)。
#   用法(对端): KSRC=1048576 KTOOL=262144 DELAY=0.35 TAG=M1 bash run_tcp_mid.sh
set -u
KSRC=${KSRC:-1048576}
KTOOL=${KTOOL:-262144}
PACE=${PACE:-1500000}
DELAY=${DELAY:-0.35}
TAG=${TAG:-M1}
SECS=${SECS:-40}
PORT=${PORT:-8080}
NW=${NW:-71}
BID=${BID:-0x00000021}
D=${D:-/tmp/p8_tcp_0x21}
cd "$D" || { echo "FATAL: no $D"; exit 3; }
export NW BID
snap(){ NW=$NW EXPECT_BID=$BID bash ./p7b_snap.sh snap "$1" 53 54 70 5 43 20 2>&1; }
echo "=== TCPMID ${TAG} KSRC=$KSRC KTOOL=$KTOOL PACE=$PACE DELAY=$DELAY $(date +%s.%N)"
echo "--- 起测前快照 (W53/W54/W70/W5/W43/W20) ---"
PRE=$(snap ${TAG}_pre); echo "$PRE"
echo "$PRE" | grep -q "SNAP_END" || { echo "FATAL: pre 快照失败"; exit 3; }
echo "--- 先起 TCP 发端 (连续流, 后台) ---"
timeout -k 5 $((SECS+60)) ./p7b_tcp_src --host 192.168.100.2 --port $PORT --bytes $KSRC \
        --pace-bps $PACE --no-verify-down --seconds $SECS > src_${TAG}.log 2>&1 &
SPID=$!
sleep "$DELAY"
echo "--- (DELAY 过后) 起 mir_dump: --bytes $KTOOL --dma --src tcp --no-verify (arm 即 clr) ---"
timeout -k 5 $((SECS+90)) ./p7b_mir_dump --bid $BID --bytes $KTOOL --dma --src tcp --pat-off 0 \
        --no-verify --seconds $SECS --out ./mir_${TAG}.bin > mir_${TAG}.log 2>&1 &
TPID=$!
( for i in 1 2 3 4; do echo "--- SS_SAMPLE_$i $(date +%s.%N)"; ss -tinp "sport = :$PORT or dport = :$PORT" 2>&1 | head -8; sleep 0.2; done ) > ss_${TAG}.log 2>&1 &
SSPID=$!
wait $TPID; echo "TOOL_RC=$?"
wait $SSPID; wait $SPID; echo "SRC_RC=$?"
echo "--- mir_dump 日志 (逐字) ---"; cat mir_${TAG}.log
echo "--- ss 采样 (逐字) ---"; cat ss_${TAG}.log
echo "--- 发端日志 (PIN_CPU + 关键行) ---"
grep -E "PIN_CPU|UNPINNED|SRC_CONNECTED|SRC_DRAIN|SRC_DONE|SRC_SEND_ERR|SRC_POLL_ERR|SRC_SUM" src_${TAG}.log || echo SRC_KEYLINES_MISSING
echo "--- 快照 (after) ---"; snap ${TAG}_post || echo SNAP_POST_FAIL
echo "--- 文件 ---"; ls -la mir_${TAG}.bin ss_${TAG}.log src_${TAG}.log 2>&1
echo "=== TCPMID_END ${TAG} $(date +%s.%N)"
