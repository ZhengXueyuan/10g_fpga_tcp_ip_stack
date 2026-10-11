#!/bin/bash
# run_tcp_arm.sh -- P8 TCP 臂单跑 (位流 0x21 / STG; 对端机上一把跑完; 以 root 启动)
#   ⭐ 与 0x1F 轮 run_tcp.sh 的结构同款, 四处有意不同 (逐条登记):
#     ① 镜像侧加 --pat-off 0 (TCP 路 = 每连接偏移 0 起的连续图案流; 见 REPORT §1)
#     ② 发端换 P8 冻结件 (带 --bytes K 精确停 + TIOCOUTQ 排空等待)
#     ③ 采样 ss -tinp (MSS/速率/rtt/pacing 的**运行中**见证)
#     ④ 快照字扩到 W53/W54 (TCP app 侧账) + W11/W13 (UDP 侧对照) + W5/W43/W20 (背景)
#   用法(对端): K=262144 PACE=1500000 TAG=T1 bash run_tcp_arm.sh
set -u
K=${K:-262144}
PACE=${PACE:-1500000}
OFF=${OFF:-0}
TAG=${TAG:-T1}
SECS=${SECS:-40}
PORT=${PORT:-8080}
NW=${NW:-71}
BID=${BID:-0x00000021}
D=${D:-/tmp/p8_tcp_0x21}
cd "$D" || { echo "FATAL: no $D"; exit 3; }
export NW BID
snap(){ NW=$NW EXPECT_BID=$BID bash ./p7b_snap.sh snap "$1" 53 54 70 11 13 5 43 20 2>&1; }
echo "=== TCPARM ${TAG} K=$K PACE=$PACE OFF=$OFF PORT=$PORT SECS=$SECS $(date +%s.%N)"
echo "--- 起测前快照 (W53 app_rx_bytes / W54 app_mismatch / W70 mir_drop / W11 W13 UDP / W5 W43 W20 背景) ---"
PRE=$(snap ${TAG}_pre); echo "$PRE"
echo "$PRE" | grep -q "SNAP_END" || { echo "FATAL: pre 快照失败, 停在起测前"; exit 3; }
echo "--- 起 mir_dump (--dma --src tcp --pat-off $OFF) ---"
timeout -k 5 $((SECS+90)) ./p7b_mir_dump --bid $BID --bytes $K --dma --src tcp --pat-off $OFF \
        --seconds $SECS --out ./mir_${TAG}.bin > mir_${TAG}.log 2>&1 &
TPID=$!
sleep 2
echo "--- 起 TCP 发端 (p7b_tcp_src --port $PORT --bytes $K --pace-bps $PACE --no-verify-down) ---"
timeout -k 5 $((SECS+60)) ./p7b_tcp_src --host 192.168.100.2 --port $PORT --bytes $K \
        --pace-bps $PACE --no-verify-down --seconds $SECS > src_${TAG}.log 2>&1 &
SPID=$!
( for i in 1 2 3 4 5; do echo "--- SS_SAMPLE_$i $(date +%s.%N)"; ss -tinp "sport = :$PORT or dport = :$PORT" 2>&1 | head -8; sleep 0.25; done ) > ss_${TAG}.log 2>&1 &
SSPID=$!
wait $SPID; SRC_RC=$?; echo "SRC_RC=$SRC_RC"
wait $SSPID
for i in $(seq 1 $((SECS+60))); do
  grep -qE "MIR_DMA_DONE|FATAL|FAIL:" mir_${TAG}.log && break
  sleep 1
done
wait $TPID; echo "TOOL_RC=$?"
echo "--- mir_dump 日志 (逐字) ---"; cat mir_${TAG}.log
echo "--- ss 采样 (逐字) ---"; cat ss_${TAG}.log
echo "--- 发端日志 (PIN_CPU 见证 + 关键行) ---"
grep -E "PIN_CPU|UNPINNED|SRC_CONNECTED|SRC_DRAIN|SRC_DONE|SRC_EOF|SRC_SEND_ERR|SRC_POLL_ERR|SRC_SUM" src_${TAG}.log || echo "SRC_LOG_KEYLINES_MISSING"
echo "--- 快照 (after) ---"
snap ${TAG}_post || echo SNAP_POST_FAIL
echo "--- 文件 ---"; ls -la mir_${TAG}.bin ss_${TAG}.log src_${TAG}.log 2>&1
echo "=== TCPARM_END ${TAG} $(date +%s.%N)"
