#!/bin/bash
# stop_probe.sh -- P9 0x23 停流探针 (P3-②): 写 MIR_CTRL=0x8 (= cap_en 0 / dma_en 1; bit1=0 ⇒ **不触发 clr**)
#   ⇒ 新口径: 排空 + 静置 QUIET_N=32 拍后**只发一拍短尾**把打包器里的半拍交付.
#   然后用 dma_from_device -s 8 读**恰好 8 B** (期望 = 源流最后 8 B = 图案[OFF+K, OFF+K+8) ^ 0xA5).
#   ⚠️ 与上轮 (0x22) 的对照口径: 上轮 -s 16 ⇒ 驱动打 "read underflow 0x8/0x10" (dma_utils.c:79);
#      本轮 -s 8 ⇒ 期望 8/8, **无 underflow 行** (同一条 syscall 路径, 只是请求量取准).
#   ⚠️ 读**只有一次机会** (拍被取走即消失) ⇒ 先起读、再等 rc; 失败时保留现场不重试.
#   用法(对端): TAG=S5 EXPECT_HEX=<16 hex> bash stop_probe.sh
#     EXPECT_HEX 可选: 期望的 8 B (图案[OFF+K..OFF+K+8) ^ 0xA5) 十六进制; 给了就现场比对.
set -u
TAG=${TAG:-STOP}
EXPECT_HEX=${EXPECT_HEX:-}
T=${P7B_TOOLS:-/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools}
D=${D:-/tmp/p9_board_0x23}
cd "$D" || { echo "FATAL: no $D"; exit 3; }
echo "=== STOP_PROBE ${TAG} $(date +%s.%N)"
echo "--- 停流前: MIR_STATUS / MIR_CTRL / MIR_DMA_CNT (逐字) ---"
$T/reg_rw /dev/xdma0_user 0x13C w 2>&1 | tail -1
$T/reg_rw /dev/xdma0_user 0x144 w 2>&1 | tail -1
$T/reg_rw /dev/xdma0_user 0x148 w 2>&1 | tail -1
echo "--- 写 MIR_CTRL = 0x8 (停流; bit1=0 ⇒ 无 clr 脉冲) ---"
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
