#!/bin/bash
# run_tcp_bar.sh -- P8 TCP 臂 **user-BAR 路径** (与 0x1F 轮 TCP 臂**同一条读路径**; 0x21 位流)
#   目的 = 拆解: 0x1F 的 91.9% 丢失里"镜像写侧"与"读路径/突发"各占多少
#   用法(对端): K=262144 PACE=2500000 TAG=BAR1 bash run_tcp_bar.sh
set -u
K=${K:-262144}
PACE=${PACE:-2500000}
OFF=${OFF:-0}
TAG=${TAG:-BAR1}
SECS=${SECS:-40}
PORT=${PORT:-8080}
NW=${NW:-71}
BID=${BID:-0x00000021}
D=${D:-/tmp/p8_tcp_0x21}
cd "$D" || { echo "FATAL: no $D"; exit 3; }
export NW BID
snap(){ NW=$NW EXPECT_BID=$BID bash ./p7b_snap.sh snap "$1" 53 54 70 11 13 2>&1; }
echo "=== TCPBAR ${TAG} K=$K PACE=$PACE OFF=$OFF $(date +%s.%N)"
echo "--- 起测前快照 ---"; PRE=$(snap ${TAG}_pre); echo "$PRE"
echo "$PRE" | grep -q SNAP_END || { echo "FATAL: pre 快照失败"; exit 3; }
echo "--- 起 mir_dump (**user-BAR 路径**, 无 --dma; dma_en=0) ---"
timeout -k 5 $((SECS+90)) ./p7b_mir_dump --bid $BID --bytes $K --src tcp --pat-off $OFF \
        --seconds $SECS --out ./mir_${TAG}.bin > mir_${TAG}.log 2>&1 &
TPID=$!
sleep 2
echo "--- 起 TCP 发端 ---"
timeout -k 5 $((SECS+60)) ./p7b_tcp_src --host 192.168.100.2 --port $PORT --bytes $K \
        --pace-bps $PACE --no-verify-down --seconds $SECS > src_${TAG}.log 2>&1
echo "SRC_RC=$?"
for i in $(seq 1 $((SECS+60))); do
  grep -qE "MIR_DONE|FATAL|FAIL:" mir_${TAG}.log && break
  sleep 1
done
wait $TPID; echo "TOOL_RC=$?"
echo "--- mir_dump 日志 (逐字) ---"; cat mir_${TAG}.log
echo "--- 发端日志 (PIN_CPU + 关键行) ---"
grep -E "PIN_CPU|SRC_CONNECTED|SRC_DRAINED|SRC_DONE|SRC_SUM" src_${TAG}.log || echo SRC_KEYLINES_MISSING
echo "--- 快照 (after) ---"; snap ${TAG}_post || echo SNAP_POST_FAIL
echo "--- 文件 ---"; ls -la mir_${TAG}.bin 2>&1
echo "=== TCPBAR_END ${TAG} $(date +%s.%N)"
