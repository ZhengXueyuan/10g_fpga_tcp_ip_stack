#!/bin/bash
# run_arm_mm.sh -- P9 0x23 轮的 MM 对照臂: 烧 0x21 后跑 **--dma** (MM 环路径) 同参数一条
#   结构 = p8_board_0x21_20261011/_tools/run_arm.sh 逐字 (只把 D 指到本轮目录; BID/PIN 同口径)
#   用法(对端): K=1048576 PAYLEN=1472 OFF=auto TAG=MM1 BID=0x00000021 bash run_arm_mm.sh
set -u
K=${K:-1048576}
PAYLEN=${PAYLEN:-1472}
OFF=${OFF:-auto}
MBPS=${MBPS:-20}
BATCH=${BATCH:-1}
TAG=${TAG:-MM1}
SECS=${SECS:-40}
SRC_SECS=${SRC_SECS:-30}
NW=${NW:-71}
BID=${BID:-0x00000021}
D=${D:-/tmp/p9_board_0x23}
cd "$D" || { echo "FATAL: no $D"; exit 3; }
export NW BID
snap(){ NW=$NW EXPECT_BID=$BID bash ./p7b_snap.sh snap "$1" 5 11 13 70 2>&1; }
echo "=== ARM_MM ${TAG} K=$K PAYLEN=$PAYLEN OFF=$OFF MBPS=$MBPS BATCH=$BATCH SECS=$SECS $(date +%s.%N)"
echo "--- 起测前快照 ---"
PRE=$(snap ${TAG}_pre); echo "$PRE"
echo "$PRE" | grep -q "SNAP_END" || { echo "FATAL: pre 快照失败, 停在起测前"; exit 3; }
if [ "$OFF" = "auto" ]; then
  W11HEX=$(echo "$PRE" | awk '/^W11 /{print $NF}' | head -1)
  case "$W11HEX" in 0x*|0X*) ;; *) echo "FATAL: 取不到 W11 ('$W11HEX')"; exit 3;; esac
  OFF=$(( W11HEX ))
  echo "OFF_AUTO: W11=$W11HEX ⇒ OFF=$OFF"
fi
echo "--- 起 mir_dump (--dma, --pat-off $OFF) ---"
timeout -k 5 $((SECS+90)) ./p7b_mir_dump --bid $BID --bytes $K --dma --src udp --pat-off $OFF \
        --seconds $SECS --out ./mir_${TAG}.bin > mir_${TAG}.log 2>&1 &
TPID=$!
sleep 2
echo "--- 起发端 ---"
timeout -k 5 $((SECS+60)) ./p7b_udp_src --host 192.168.100.2 --port 8081 --bytes $K --mbps $MBPS \
        --batch $BATCH --paylen $PAYLEN --off $OFF --seconds $SRC_SECS > src_${TAG}.log 2>&1
echo "SRC_RC=$?"
for i in $(seq 1 $((SECS+60))); do
  grep -qE "MIR_DMA_DONE|FATAL|FAIL:" mir_${TAG}.log && break
  sleep 1
done
wait $TPID; echo "TOOL_RC=$?"
echo "--- mir_dump 日志 (逐字) ---"
cat mir_${TAG}.log
echo "--- 发端日志 (PIN_CPU 见证行 + UDP_SUM) ---"
grep -E "PIN_CPU|UNPINNED|UDP_SUM|FATAL" src_${TAG}.log || echo "SRC_LOG_KEYLINES_MISSING"
echo "--- 快照 (after) ---"
snap ${TAG}_post || echo SNAP_POST_FAIL
echo "--- 文件 ---"
ls -la mir_${TAG}.bin 2>&1
echo "=== END_MM ${TAG} $(date +%s.%N)"
