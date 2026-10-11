#!/bin/bash
# t2_remote_step.sh -- T2 单跑 (对端机, root): AXIS 读出口 (--stream) + TCP 源臂 (--src tcp)
#   用法: K=1048576 PACE=2500000 TAG=T2A [KBYTES=] [SRC_BYTES=] [SRC_SECS=40] bash t2_remote_step.sh
#   与 MM 轮 (p8_tcp_0x21 run_tcp_arm.sh) 的结构同款, 四处有意不同 (逐条登记):
#     ① 读出口 = --stream (AXIS 平铺 C2H) —— MM 轮是 --dma (16 KB 环)
#     ② 镜像侧 --pat-off 0 (TCP 路 = 每连接从偏移 0 起; 与 MM 轮同)
#     ③ K % 8 == 0 硬门 (stream 合同) —— MM 轮是 K % 4
#     ④ 快照字 = W53/W54/W70/W11/W13/W5/W43/W20 (与 p9 轮 ARM 同)
set -u
K=${K:-1048576}
PACE=${PACE:-2500000}
TAG=${TAG:-T2A}
PORT=${PORT:-8080}
SECS=${SECS:-40}
SRC_SECS=${SRC_SECS:-40}
KBYTES=${KBYTES:-}
SRC_BYTES=${SRC_BYTES:-$K}
MB=128
NW=${NW:-71}
BID=${BID:-0x00000023}
D=${D:-/tmp/p9_final}
cd "$D" || { echo "FATAL: no $D"; exit 3; }
export NW EXPECT_BID=$BID
UQ="${TAG}_$(date +%s)"
snap(){ NW=$NW EXPECT_BID=$BID bash ./p7b_snap.sh snap "$1" 53 54 70 11 13 5 43 20 2>&1; }
echo "=== T2STEP ${TAG} K=$K KBYTES=${KBYTES:-<none>} SRC_BYTES=$SRC_BYTES PACE=$PACE PORT=$PORT UQ=${UQ} begin=$(date +%s.%N)"
echo "--- 起测前快照 ---"
snap "${TAG}_pre"
echo "--- 起测前 MIR 寄存器 ---"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
reg(){ $T/reg_rw /dev/xdma0_user "$1" w 2>&1 | tail -1 | sed 's/.*: *//'; }
echo "PRE MIR_STATUS=$(reg 0x13C) MIR_CTRL=$(reg 0x144) MIR_DMA_CNT=$(reg 0x148) SCRATCH_0x08=$(reg 0x08) BID=$(reg 0x04)"
echo "--- 起 mir_dump (--stream --src tcp --pat-off 0) UQ=${UQ} ---"
KOPT=""
[ -n "$KBYTES" ] && KOPT="--k-bytes $KBYTES"
timeout -k 5 $((SECS+90)) ./p7b_mir_dump --bid $BID --bytes $K --stream --src tcp --pat-off 0 \
        --buf-mb $MB $KOPT --seconds $SECS --out ./mir_${TAG}.bin > mir_${TAG}.log 2>&1 &
TPID=$!
sleep 2
echo "--- 起 TCP 发端 (p7b_tcp_src --port $PORT --bytes $SRC_BYTES --pace-bps $PACE --no-verify-down) UQ=${UQ} ---"
timeout -k 5 $((SRC_SECS+60)) ./p7b_tcp_src --host 192.168.100.2 --port $PORT --bytes $SRC_BYTES \
        --pace-bps $PACE --no-verify-down --seconds $SRC_SECS > src_${TAG}.log 2>&1 &
SPID=$!
( for i in 1 2 3 4 5; do echo "--- SS_SAMPLE_$i $(date +%s.%N)"; ss -tinp "sport = :$PORT or dport = :$PORT" 2>&1 | head -8; sleep 0.25; done ) > ss_${TAG}.log 2>&1 &
SSPID=$!
wait $SPID; SRC_RC=$?; echo "SRC_RC=$SRC_RC"
wait $SSPID
for i in $(seq 1 $((SECS+60))); do
  grep -qE "MIR_STREAM_DONE|FATAL|FAIL:" mir_${TAG}.log && break
  sleep 1
done
wait $TPID; echo "TOOL_RC=$? UQ=${UQ}"
echo "--- mir_dump 日志 (逐字) ---"; cat mir_${TAG}.log
echo "--- ss 采样 (逐字) ---"; cat ss_${TAG}.log
echo "--- 发端日志 (PIN_CPU 见证 + 关键行) ---"
grep -E "PIN_CPU|UNPINNED|SRC_CONNECTED|SRC_DRAINED|SRC_DONE|SRC_EOF|SRC_SEND_ERR|SRC_POLL_ERR|SRC_SUM" src_${TAG}.log || echo "SRC_LOG_KEYLINES_MISSING"
echo "--- 起测后 MIR 寄存器 ---"
echo "POST MIR_STATUS=$(reg 0x13C) MIR_CTRL=$(reg 0x144) MIR_DMA_CNT=$(reg 0x148) SCRATCH_0x08=$(reg 0x08) BID=$(reg 0x04)"
echo "--- 起测后快照 ---"
snap "${TAG}_post"
echo "--- 文件 ---"; ls -la mir_${TAG}.bin src_${TAG}.log ss_${TAG}.log 2>&1
echo "=== T2STEP_END ${TAG} UQ=${UQ} end=$(date +%s.%N)"
