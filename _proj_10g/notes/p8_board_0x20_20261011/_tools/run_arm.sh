#!/bin/bash
# run_arm.sh -- P8 板级 A/B 单臂 (对端机上一把跑完; 以 root 启动, /dev/xdma* 是 root-only)
#   用法(对端): K=1048576 PAYLEN=1472 OFF=auto TAG=A1 bash run_arm.sh
#   OFF=auto ⇒ 起拍前先取快照拿 W11 (= 板上图案流位置), 把 OFF 定成它
#     (同时满足两条: ① 板上 W13 校验器对齐 ⇒ ΔW13 应 == 0; ② mir_dump --pat-off 与发端 --off 对齐)
#   顺序: 快照(pre, 触发式锁存) -> 起 mir_dump(--dma, 内部 clr+cap_en+dma_en, --pat-off $OFF)
#         -> sleep 2 -> 起 p7b_udp_src(--bytes K --mbps 定速 --paylen --off $OFF) -> 等收口 -> 快照(post)
#   ⚠️ 工具全部包 timeout (防 C2H 读挂死拖住会话); 挂 = 判据未达成, 保留现场。
set -u
K=${K:-1048576}
PAYLEN=${PAYLEN:-1472}
OFF=${OFF:-auto}
MBPS=${MBPS:-20}
BATCH=${BATCH:-1}
TAG=${TAG:-A1}
SECS=${SECS:-30}
SRC_SECS=${SRC_SECS:-30}
NW=${NW:-71}
BID=${BID:-0x00000020}
D=${D:-/tmp/p8_board_0x20}
cd "$D" || { echo "FATAL: no $D"; exit 3; }
export NW BID
snap(){ NW=$NW EXPECT_BID=$BID bash ./p7b_snap.sh snap "$1" 5 11 13 70 2>&1; }
echo "=== ARM ${TAG} K=$K PAYLEN=$PAYLEN OFF=$OFF MBPS=$MBPS BATCH=$BATCH SECS=$SECS $(date +%s.%N)"
echo "--- 起测前快照 (W11=udpapp_rx_bytes / W13=app_mismatch / W70=mir_drop_bytes) ---"
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
echo "--- 起发端 (p7b_udp_src, --bytes $K --mbps $MBPS --batch $BATCH --paylen $PAYLEN --off $OFF) ---"
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
echo "=== END ${TAG} $(date +%s.%N)"
