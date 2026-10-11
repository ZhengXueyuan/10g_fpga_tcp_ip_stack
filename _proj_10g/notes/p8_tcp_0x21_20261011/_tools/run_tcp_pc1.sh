#!/bin/bash
# run_tcp_pc1.sh -- W70 **正控** (位流 0x21): cap_en=1 / dma_en=0 / 主机不读
#   ⇒ 镜像 FIFO (256×8B = 2 KB) 必然填满 ⇒ 之后的字节全部计进 drop_bytes。
#   期望: ΔW70 ≈ K − (2 KB + acc 8 B + stg ≤16 B), ΔW53 == K, ΔW54 == 0,
#         MIR_STATUS.any_drop_sticky 翻 1。⇒ 证明"W70 会涨"(零读数不是坏计数器)。
#   ⚠️ 本配置**故意**制造丢弃; 跑完 cap_en 已回 0。
set -u
K=${K:-65536}
PACE=${PACE:-1500000}
TAG=${TAG:-PC1}
PORT=${PORT:-8080}
NW=${NW:-71}
BID=${BID:-0x00000021}
D=${D:-/tmp/p8_tcp_0x21}
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
cd "$D" || { echo "FATAL: no $D"; exit 3; }
export NW BID
snap(){ NW=$NW EXPECT_BID=$BID bash ./p7b_snap.sh snap "$1" 53 54 70 2>&1; }
reg(){ $T/reg_rw /dev/xdma0_user "$1" w "$2" 2>&1 | tail -1; }
rd(){  $T/reg_rw /dev/xdma0_user "$1" w 2>&1 | tail -1; }
echo "=== TCPPC1 ${TAG} K=$K $(date +%s.%N)"
PRE=$(snap ${TAG}_pre); echo "$PRE"
echo "$PRE" | grep -q SNAP_END || { echo "FATAL: pre 快照失败"; exit 3; }
echo "--- arm: MIR_CTRL=0x6 (clr + src_sel=1, cap_en=0, dma_en=0) ---"; reg 0x144 0x6
echo "--- arm: MIR_CTRL=0x5 (cap_en=1 + src_sel=1, **dma_en=0**) ---";     reg 0x144 0x5
echo -n 'MIR_STATUS_after_arm='; rd 0x13C
echo "--- 起 TCP 发端 (K=$K; 主机**不读** MIR_DATA) ---"
timeout -k 5 60 ./p7b_tcp_src --host 192.168.100.2 --port $PORT --bytes $K --pace-bps $PACE \
        --no-verify-down --seconds 30 > src_${TAG}.log 2>&1
echo "SRC_RC=$?"
sleep 1
echo -n 'MIR_STATUS_after='; rd 0x13C
echo -n 'MIR_DMA_CNT_0x148='; rd 0x148
snap ${TAG}_post || echo SNAP_POST_FAIL
echo "--- 回冻结: MIR_CTRL=0x0 (cap_en=0 / dma_en=0) ---"; reg 0x144 0x0
echo -n 'MIR_CTRL_0x144='; rd 0x144
grep -E "PIN_CPU|SRC_SUM|SRC_DRAINED|SRC_CONNECTED" src_${TAG}.log || echo SRC_KEYLINES_MISSING
echo "=== TCPPC1_END ${TAG} $(date +%s.%N)"
