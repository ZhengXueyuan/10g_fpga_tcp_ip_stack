#!/bin/bash
# run_tcp.sh -- P8 板级轮 ③: TCP 源臂 (src_sel=1, tap = app_rx_* / eco2 路径)
#   用法(root): K=<bytes> PACE=<B/s> TAG=<name> bash run_tcp.sh
#   快照读 W53 (app_rx_bytes) / W54 (app_mismatch) / W70 (mir_drop_bytes)
set -u
K=${K:-262144}
PACE=${PACE:-2500000}        # bytes/s (SO_MAX_PACING_RATE)
TAG=${TAG:-tcp1}
SECS=${SECS:-40}
cd /tmp/p8_board
echo "=== ${TAG} K=$K PACE=$PACE $(date +%s.%N)"
echo "--- 起测前快照 (W53/W54/W70) ---"
bash p7b_snap.sh snap ${TAG}_pre 53 54 70 || echo SNAP_PRE_FAIL
echo "--- 起 mir_dump (--src tcp) ---"
timeout -k 5 $((SECS+60)) ./p7b_mir_dump --bid 0x1F --bytes $K --src tcp \
        --seconds $SECS --out /tmp/p8_board/mir_${TAG}.bin > mir_${TAG}.log 2>&1 &
TPID=$!
sleep 2
echo "--- 起 TCP 发端 ---"
timeout -k 5 90 ./p7b_tcp_src --host 192.168.100.2 --port 8080 --bytes $K --pace-bps $PACE \
        --no-verify-down --seconds $SECS > src_${TAG}.log 2>&1
echo "SRC_RC=$?"
for i in $(seq 1 60); do grep -qE "MIR_DONE|FATAL" mir_${TAG}.log && break; sleep 1; done
wait $TPID; echo "TOOL_RC=$?"
echo "--- mir_dump 日志 (逐字) ---"
cat mir_${TAG}.log
echo "--- 发端日志 (尾部) ---"
tail -4 src_${TAG}.log
echo "--- 快照 (after) ---"
bash p7b_snap.sh snap ${TAG}_post 53 54 70 || echo SNAP_POST_FAIL
echo "--- 文件 ---"
ls -la /tmp/p8_board/mir_${TAG}.bin 2>&1
echo "=== ${TAG} END $(date +%s.%N)"
