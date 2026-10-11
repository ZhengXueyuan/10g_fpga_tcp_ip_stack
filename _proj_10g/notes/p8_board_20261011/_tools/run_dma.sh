#!/bin/bash
# run_dma.sh -- P8 板级轮: ① C2H DMA 环读路径 (对端机上一把跑完)
#   用法(root): K=<bytes> MBPS=<n> TAG=<name> bash run_dma.sh
#   顺序: 快照(before) -> 起 mir_dump(--dma, 内部 clr+cap_en+dma_en 起测协议)
#         -> 等 2 s -> 起 p7b_udp_src(--bytes K --mbps 定速) -> 等工具收口 -> 快照(after)
#   ⚠️ 工具/发端全部包 timeout (防 C2H 读挂死拖住会话; 挂 = 判据未达成, 保留现场)
set -u
K=${K:-1048576}
MBPS=${MBPS:-20}
BATCH=${BATCH:-1}      # ⚠️ 必须小: 发端一批 = batch 个 datagram 的突发; 环只有 16 KB(4096 字)
                       #    ⇒ batch=32 的 47 KB 突发必然吃爆环 (dma1 首跑实测 FATAL 5800 字)
TAG=${TAG:-dma1}
SECS=${SECS:-60}
PAYLEN=${PAYLEN:-1472}
cd /tmp/p8_board
echo "=== ${TAG} K=$K MBPS=$MBPS BATCH=$BATCH PAYLEN=$PAYLEN $(date +%s.%N)"
echo "--- 起测前快照 (W11=udpapp_rx_bytes / W70=mir_drop_bytes) ---"
bash /tmp/p8_board/p7b_snap.sh snap ${TAG}_pre 11 13 70 || echo SNAP_PRE_FAIL

echo "--- 起 mir_dump (--dma) ---"
timeout -k 5 $((SECS+60)) ./p7b_mir_dump --bid 0x1F --bytes $K --dma --src udp \
        --seconds $SECS --out /tmp/p8_board/mir_${TAG}.bin > mir_${TAG}.log 2>&1 &
TPID=$!
sleep 2
echo "--- 起发端 (p7b_udp_src, 定速) ---"
timeout -k 5 90 ./p7b_udp_src --host 192.168.100.2 --port 8081 --bytes $K --mbps $MBPS \
        --batch $BATCH --paylen $PAYLEN --seconds $SECS > src_${TAG}.log 2>&1
echo "SRC_RC=$?"
for i in $(seq 1 60); do
  grep -qE "MIR_DMA_DONE|FATAL|FAIL:" mir_${TAG}.log && break
  sleep 1
done
wait $TPID; echo "TOOL_RC=$?"
echo "--- mir_dump 日志 (逐字) ---"
cat mir_${TAG}.log
echo "--- 发端日志 (尾部) ---"
tail -4 src_${TAG}.log
echo "--- 快照 (after) ---"
bash /tmp/p8_board/p7b_snap.sh snap ${TAG}_post 11 13 70 || echo SNAP_POST_FAIL
echo "--- 文件 ---"
ls -la /tmp/p8_board/mir_${TAG}.bin
echo "=== ${TAG} END $(date +%s.%N)"
