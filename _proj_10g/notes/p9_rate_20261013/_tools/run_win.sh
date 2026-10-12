#!/bin/bash
# run_win.sh -- P9 线速档补测: **单窗** = "源精确交付 K 字节 (有界) + 一次 --stream 抓取 + 前后快照"
#   口径来源 = p9_board_0x23/_tools/run_arm.sh (同结构), 三处不同:
#     ① 有界源 = K (源交付量 == 抓取量 == --k-bytes 默认口径; 式 B 才有独立 K)
#     ② 快照加 W46..W49 (rx_classify 拒写/停等/占用) 与 W0/W1/W5 (MAC 收帧/字节/自由钟)
#     ③ 记录外部墙钟 T0/TS/TE/TZ (源起/源止/工具止) 供窗口覆盖率核对
#   用法(对端, root): TAG=W00 K=134217728 MBPS=0 SECS=30 bash run_win.sh
#   ⚠️ 每次读数必须自证新鲜 (快照 gen +1; p7b_snap.sh 自带 GEN_FAIL 判据)
set -u
D=${D:-/tmp/p9_rate}; cd "$D" || { echo "FATAL: no $D"; exit 3; }
export NW=${NW:-71} EXPECT_BID=${EXPECT_BID:-0x00000023}
TAG=${TAG:-W00}
K=${K:-33554432}                 # 抓取字节 == 源交付 N (K%4==0, stream 还要求 K%8==0)
MBPS=${MBPS:-0}                  # 0=满速 (unpaced)
PAYLEN=${PAYLEN:-1472}
BATCH=${BATCH:-32}
SECS=${SECS:-30}                 # mir_dump 看门狗 (SIGALRM, 只在 read 阻塞时生效)
SRC_SECS=${SRC_SECS:-90}
SAMPLE_MS=${SAMPLE_MS:-1000}     # ⭐ 本测口径: 1000ms (采样=自造宿主空档 ⇒ 会自造丢字节; pilot 实测 20ms 档每采一次丢 ~243KB)
SETTLE=${SETTLE:-0.3}
DECL=${DECL:-}                   # 非空 ⇒ 追加到工具参数 (如 --no-strict-quiesce)
OUT=${OUT:-./mir_${TAG}.bin}     # ⭐ /dev/null = 只留 MIR_VERIFY 判据, 不落盘 (批量窗省 IO)
ARM_GAP=${ARM_GAP:-1}            # 工具起 -> 源起 的间隔 (run_arm.sh 配方 = 2s; 1s 见 probe 时序)
WORDS=${WORDS:-"0 1 5 10 11 13 70 46 47 48 49"}
snap(){ NW=$NW EXPECT_BID=$EXPECT_BID bash ./p7b_snap.sh snap "$1" $WORDS 2>&1; }
T0=$(date +%s.%N)
echo "=== WIN ${TAG} K=$K MBPS=$MBPS PAYLEN=$PAYLEN BATCH=$BATCH SECS=$SECS DECL='$DECL' T0=$T0"
echo "--- pre 快照 ---"
PRE=$(snap "${TAG}_pre"); echo "$PRE"
echo "$PRE" | grep -q "SNAP_END" || { echo "FATAL: pre 快照失败"; exit 3; }
W11HEX=$(echo "$PRE" | awk '/^W11 /{print $NF}' | head -1)
case "$W11HEX" in 0x*|0X*) ;; *) echo "FATAL: 取不到 W11 ('$W11HEX')"; exit 3;; esac
OFF=$(( W11HEX ))
echo "OFF_AUTO: W11=$W11HEX => OFF=$OFF"
echo "--- 起 mir_dump (--stream) ---"
timeout -k 5 $((SECS+120)) ./p7b_mir_dump --bid "$EXPECT_BID" --bytes "$K" --stream --src udp --pat-off "$OFF" \
        --buf-mb 128 --sample-ms "$SAMPLE_MS" --settle "$SETTLE" --seconds "$SECS" $DECL \
        --out "$OUT" > "mir_${TAG}.log" 2>&1 &
TPID=$!
sleep "$ARM_GAP"
TS=$(date +%s.%N)
echo "--- 起发端 (有界: --bytes $K, --mbps $MBPS) TS=$TS ---"
timeout -k 5 $((SRC_SECS+60)) ./p7b_udp_src --host 192.168.100.2 --port 8081 --bytes "$K" --mbps "$MBPS" \
        --batch "$BATCH" --paylen "$PAYLEN" --off "$OFF" --seconds "$SRC_SECS" > "src_${TAG}.log" 2>&1
SRC_RC=$?
TE=$(date +%s.%N)
echo "SRC_RC=$SRC_RC TE=$TE"
wait $TPID; TOOL_RC=$?
TZ=$(date +%s.%N)
echo "TOOL_RC=$TOOL_RC TZ=$TZ"
echo "--- mir_dump 日志 (逐字) ---"
cat "mir_${TAG}.log"
echo "--- 发端关键行 (PIN 见证 + UDP_SUM) ---"
grep -E "PIN_CPU=|UNPINNED|UDP_SUM|FATAL|SEND_ERR|UDP_POLL_TMO|skip_pkts" "src_${TAG}.log" | tail -8
echo "--- post 快照 ---"
snap "${TAG}_post" || echo SNAP_POST_FAIL
echo "--- 文件 ---"
ls -la "$OUT" 2>&1 || true
echo "=== END ${TAG} $(date +%s.%N)"
