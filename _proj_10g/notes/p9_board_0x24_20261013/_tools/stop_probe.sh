#!/bin/bash
# stop_probe.sh -- 0x24 停流探针 (对齐 0x23 轮 P3-③ 口径): 写 MIR_CTRL=0x8 (= cap_en 0; bit1=0 => 不触发 clr)
#   => D4 口径: 排空 + 静置后交付打包器里那**恰一拍**短尾 (0x23 实测 8/8 RC=0).
#   然后用 dma_from_device -s 8 读恰好 8 B (期望 = 源流最后 8 B = 图案[OFF+K, OFF+K+8) ^ 0xA5).
#   ⚠️ 读只有一次机会 (拍被取走即消失) => 先起读、再等 rc; 失败时保留现场不重试.
#   ⚠️ 0x24 新增 URAM 缓冲在镜像 aux 与成形器之间 => 残字可能驻留在缓冲里, 短尾形态**据实报**
#      (出现 underflow / 大于 8 B / 无尾 = 如实登记, 不裁定).
#   用法(对端): TAG=S5 EXPECT_HEX=<16 hex> bash stop_probe.sh
set -u
TAG=${TAG:-STOP}
EXPECT_HEX=${EXPECT_HEX:-}
T=${P7B_TOOLS:-/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools}
D=${D:-/tmp/p9_board_0x24}
cd "$D" || { echo "FATAL: no $D"; exit 3; }
echo "=== STOP_PROBE ${TAG} $(date +%s.%N)"
echo "--- 停流前: MIR_STATUS / MIR_CTRL / MIR_DMA_CNT (逐字) ---"
$T/reg_rw /dev/xdma0_user 0x13C w 2>&1 | tail -1
$T/reg_rw /dev/xdma0_user 0x144 w 2>&1 | tail -1
$T/reg_rw /dev/xdma0_user 0x148 w 2>&1 | tail -1
echo "--- 写 MIR_CTRL = 0x8 (停流; bit1=0 => 无 clr 脉冲) ---"
$T/reg_rw /dev/xdma0_user 0x144 w 0x8 2>&1 | tail -1
sleep 1
echo "--- 停流后即刻: MIR_STATUS / MIR_CTRL / MIR_DMA_CNT ---"
$T/reg_rw /dev/xdma0_user 0x13C w 2>&1 | tail -1
$T/reg_rw /dev/xdma0_user 0x144 w 2>&1 | tail -1
$T/reg_rw /dev/xdma0_user 0x148 w 2>&1 | tail -1
echo "--- 读短尾 (= 恰一拍 8 B): dma_from_device -s 8 (stdout+stderr 全留) ---"
T0=$(date +%s)
timeout -k 5 40 $T/dma_from_device -d /dev/xdma0_c2h_0 -s 8 -f ./tail_${TAG}.bin; RC=$?
T1=$(date +%s)
echo "TAIL_RC=$RC ELAPSED=$((T1-T0))"
echo "--- tail 文件 ---"
ls -la ./tail_${TAG}.bin 2>&1
od -An -tx1 ./tail_${TAG}.bin 2>&1
if [ -n "$EXPECT_HEX" ]; then
  GOT=$(od -An -tx1 ./tail_${TAG}.bin | tr -d ' \n')
  echo "TAIL_EXPECT exp=$EXPECT_HEX got=$GOT"
  [ "$GOT" = "$EXPECT_HEX" ] && echo "TAIL_MATCH yes" || echo "TAIL_MATCH no"
fi
echo "--- 读后: MIR_STATUS / MIR_DMA_CNT (level 应 0) ---"
$T/reg_rw /dev/xdma0_user 0x13C w 2>&1 | tail -1
$T/reg_rw /dev/xdma0_user 0x148 w 2>&1 | tail -1
echo "--- dmesg 尾部 (找 underflow / timeout / xdma 报错) ---"
dmesg 2>/dev/null | tail -12
echo "=== STOP_PROBE_END ${TAG} $(date +%s.%N)"
