#!/bin/bash
# run_arm.sh -- P9 板级 A/B 轮 (0x23) 单臂: 对端上一把跑完 (以 root 启动, /dev/xdma* 是 root-only)
#   本轮 = 位流 0x23 (**XDMA 用户接口 = AXI4-Stream** + clr/停流新口径; 工具走 --stream).
#   结构自 p9_board_0x22/_tools/run_arm.sh 继承, 三处不同:
#     ① 路径 / BID 换成本轮 (D=/tmp/p9_board_0x23, BID=0x00000023, NW=71)
#     ② 判据行仍 = MIR_STREAM_*
#     ③ 快照字 = W5/W11/W13/W70 (与上轮同)
#   OFF=auto ⇒ 起拍前先取快照拿 W11 (= 板上 UDP app 收字节账 = 图案流位置), 把 OFF 定成它
#   ⚠️ 工具全部包 timeout (防 C2H 读挂死拖住会话); 挂 = 判据未达成, 保留现场.
#   用法(对端): K=1048576 PAYLEN=1472 OFF=auto TAG=S1 bash run_arm.sh
#               K=1048576 PAYLEN=1472 TAG=S3 KBYTES=1048584 SRC_BYTES=1048584 bash run_arm.sh
set -u
K=${K:-1048576}
PAYLEN=${PAYLEN:-1472}
OFF=${OFF:-auto}
MBPS=${MBPS:-20}
BATCH=${BATCH:-1}
TAG=${TAG:-S1}
SECS=${SECS:-30}
SRC_SECS=${SRC_SECS:-30}
KBYTES=${KBYTES:-}          # 非空 ⇒ 工具加 --k-bytes K (源交付量 ≠ 抓取量时**必须**)
SRC_BYTES=${SRC_BYTES:-$K}  # 发端实发字节数 (默认 = K)
NW=${NW:-71}
BID=${BID:-0x00000023}
D=${D:-/tmp/p9_board_0x23}
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
echo "--- 起 mir_dump (--stream, --pat-off $OFF) ---"
KOPT=""
[ -n "$KBYTES" ] && KOPT="--k-bytes $KBYTES"
timeout -k 5 $((SECS+90)) ./p7b_mir_dump --bid $BID --bytes $K --stream --src udp --pat-off $OFF \
        --buf-mb 128 $KOPT --seconds $SECS --out ./mir_${TAG}.bin > mir_${TAG}.log 2>&1 &
TPID=$!
sleep 2
echo "--- 起发端 (p7b_udp_src, --bytes $SRC_BYTES --mbps $MBPS --batch $BATCH --paylen $PAYLEN --off $OFF) ---"
timeout -k 5 $((SECS+60)) ./p7b_udp_src --host 192.168.100.2 --port 8081 --bytes $SRC_BYTES --mbps $MBPS \
        --batch $BATCH --paylen $PAYLEN --off $OFF --seconds $SRC_SECS > src_${TAG}.log 2>&1
echo "SRC_RC=$?"
for i in $(seq 1 $((SECS+60))); do
  grep -qE "MIR_STREAM_DONE|FATAL|FAIL:" mir_${TAG}.log && break
  sleep 1
done
wait $TPID; echo "TOOL_RC=$?"
echo "--- mir_dump 日志 (逐字) ---"
cat mir_${TAG}.log
echo "--- 发端日志 (PIN_CPU 见证行 + UDP_SUM) ---"
grep -E "PIN_CPU|UNPINNED|UDP_SUM|FATAL" src_${TAG}.log || echo SRC_LOG_KEYLINES_MISSING
echo "--- 快照 (after) ---"
snap ${TAG}_post || echo SNAP_POST_FAIL
echo "--- 文件 ---"
ls -la mir_${TAG}.bin 2>&1
echo "=== END ${TAG} $(date +%s.%N)"
