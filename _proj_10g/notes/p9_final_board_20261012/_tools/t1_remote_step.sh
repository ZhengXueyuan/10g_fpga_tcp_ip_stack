#!/bin/bash
# t1_remote_step.sh -- T1 单档 (对端机, root): H2C 写一次 + 前后寄存器/触发式快照 + dmesg 差分
#   用法: bash t1_remote_step.sh <size> <tag>
#   新鲜度见证: 每行带 TAG_<size>_<epoch> 唯一串 (防"读了上一次的陈旧件")
set -u
S=${1:?size}
TAG=${2:?tag}
D=/tmp/p9_final
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
cd "$D" || { echo "FATAL: no $D"; exit 3; }
export NW=71 EXPECT_BID=0x00000023
UQ="${TAG}_${S}_$(date +%s)"
snap(){ bash ./p7b_snap.sh snap "$1" 53 54 70 11 13 5 43 20 2>&1; }
reg(){ $T/reg_rw /dev/xdma0_user "$1" w 2>&1 | tail -1 | sed 's/.*: *//'; }

echo "=== T1STEP ${TAG} size=$S UQ=${UQ} begin=$(date +%s.%N)"
echo "--- 写前触发式快照 ---"
snap "${TAG}_pre"
echo "--- 写前寄存器 ---"
echo "PRE MIR_STATUS=$(reg 0x13C) MIR_CTRL=$(reg 0x144) MIR_DMA_CNT=$(reg 0x148) SCRATCH_0x08=$(reg 0x08) BID=$(reg 0x04)"
DM0=$(dmesg 2>/dev/null | wc -l)
echo "DMESG_LINES_BEFORE=$DM0"
echo "--- dma_to_device (-d /dev/xdma0_h2c_0 -f h2c_${S}.bin -s $S -c 1; timeout 60) ---"
T0=$(date +%s.%N)
timeout -k 5 60 $T/dma_to_device -d /dev/xdma0_h2c_0 -f "$D/h2c_${S}.bin" -s "$S" -c 1 -v 2>&1
RC=$?
T1=$(date +%s.%N)
echo "DMA_TO_DEVICE_RC=$RC UQ=${UQ}"
awk -v a="$T0" -v b="$T1" 'BEGIN{printf "ELAPSED_SEC=%.6f\n", b-a}'
DM1=$(dmesg 2>/dev/null | wc -l)
echo "DMESG_LINES_AFTER=$DM1"
echo "--- dmesg 新增行 (逐字; 无则 NEWDMESG_COUNT=0) ---"
NEW=$(dmesg 2>/dev/null | tail -n +$((DM0+1)))
if [ -n "$NEW" ]; then echo "$NEW" | sed 's/^/NEWDMESG: /'; else echo "NEWDMESG_COUNT=0"; fi
echo "--- dmesg 尾部 12 行 (整段看上下文) ---"
dmesg 2>/dev/null | tail -12
echo "--- 写后寄存器 ---"
echo "POST MIR_STATUS=$(reg 0x13C) MIR_CTRL=$(reg 0x144) MIR_DMA_CNT=$(reg 0x148) SCRATCH_0x08=$(reg 0x08) BID=$(reg 0x04)"
echo "--- 写后触发式快照 ---"
snap "${TAG}_post"
echo "=== T1STEP_END ${TAG} UQ=${UQ} end=$(date +%s.%N)"
