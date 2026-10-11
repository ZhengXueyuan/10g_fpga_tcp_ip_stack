#!/bin/bash
# run_bar.sh -- P8 板级轮: ② user-BAR 窗口路径 (读=弹出; 不带 --dma)
#   用法(root): K=<bytes> MBPS=<n> PAYLEN=<n> TAG=<name> bash run_bar.sh
#   顺序: 快照(before) -> 起 mir_dump(BAR 路径, 内部 clr+cap_en) -> 等 2 s -> 发端 -> 等工具收口
set -u
K=${K:-262144}
OFF=${OFF:-0}          # 发端图案起点偏移 (= 板上 app LFSR 位置 = 累计 W11)
PATOFF=${PATOFF:-0}    # 工具 verify 的图案基准偏移
MBPS=${MBPS:-20}
BATCH=${BATCH:-1}
PAYLEN=${PAYLEN:-1472}
TAG=${TAG:-bar1}
SECS=${SECS:-30}
cd /tmp/p8_board
echo "=== ${TAG} K=$K MBPS=$MBPS BATCH=$BATCH PAYLEN=$PAYLEN $(date +%s.%N)"
echo "--- 起测前快照 (W11/W13/W70) ---"
bash p7b_snap.sh snap ${TAG}_pre 11 13 70 || echo SNAP_PRE_FAIL
echo "--- 起 mir_dump (BAR 路径) ---"
timeout -k 5 $((SECS+60)) ./p7b_mir_dump --bid 0x1F --bytes $K --src udp \
        --pat-off $PATOFF --seconds $SECS --out /tmp/p8_board/mir_${TAG}.bin > mir_${TAG}.log 2>&1 &
TPID=$!
sleep 2
echo "--- 起发端 ---"
timeout -k 5 90 ./p7b_udp_src --host 192.168.100.2 --port 8081 --bytes $K --mbps $MBPS \
        --batch $BATCH --paylen $PAYLEN --off $OFF --seconds $SECS > src_${TAG}.log 2>&1
echo "SRC_RC=$?"
for i in $(seq 1 60); do grep -qE "MIR_DONE|FATAL" mir_${TAG}.log && break; sleep 1; done
wait $TPID; echo "TOOL_RC=$?"
echo "--- mir_dump 日志 (逐字) ---"
cat mir_${TAG}.log
echo "--- 发端日志 (尾部) ---"
tail -3 src_${TAG}.log
echo "--- 快照 (after) ---"
bash p7b_snap.sh snap ${TAG}_post 11 13 70 || echo SNAP_POST_FAIL
echo "--- 文件 ---"
ls -la /tmp/p8_board/mir_${TAG}.bin
echo "=== ${TAG} END $(date +%s.%N)"
