#!/bin/bash
# burn_0x1F.sh -- P8 板级轮: 烧归档位流 0x1F (M1 载荷镜像窗 / BID 0x1F)
#   纪律: 只走 JTAG 易失烧录 (绝不写 QSPI); 只烧本目录副本 (burn/wrapper_p4_0x1F.bit,
#         由 p7b_build_0x1F/wrapper_p4.bit 复制); 烧前 sha256 双核; 烧后核板侧 BID。
#   判据: sha256 与派单相同 + stdout 新鲜 + "End of startup status: HIGH" + 位流路径匹配
#         + 非注释行 TCPREG_PROG_DONE + 无 TCPREG-ABORT。
#   用法: PEER_PW=<pw> bash burn_0x1F.sh      (口令只作 --sudo 前缀, 不落盘)
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p8_board_20261011
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
ROOTW=D:/repo/XCKU5PMini/udp_hls_10g
SSH="$PY $ROOTW/tools/peer_ssh.py"
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW (只用于 --sudo)"; exit 3; }

WANT=e365c5ca4fd25335f6713b2a960b4de5af5b42e0bda238c20d41011ca7460133
EXPBID=0x0000001F
SRC=$ROOT/_proj_10g/notes/p7b_build_0x1F/wrapper_p4.bit
BS=wrapper_p4_0x1F.bit
LOCAL_BIT=$OUT/burn/$BS
BIT_WIN="D:\\repo\\XCKU5PMini\\udp_hls_10g\\_proj_10g\\notes\\p8_board_20261011\\burn\\$BS"

mkdir -p "$OUT/burn"
LOG=$OUT/burn/BURN_0x1F_$(date +%Y%m%d_%H%M%S).txt
exec > >(tee "$LOG") 2>&1

echo "=== COPY $(date +%s.%N)"
cp "$SRC" "$LOCAL_BIT"
echo "--- 源 (归档) ---";      sha256sum "$SRC"
echo "--- 副本 (烧录件) ---";  sha256sum "$LOCAL_BIT"
GOT=$(sha256sum "$LOCAL_BIT" | cut -d' ' -f1)
echo "SHA_WANT want=$WANT"
[ "$GOT" = "$WANT" ] || { echo "SHA_MISMATCH ⇒ 拒绝烧"; exit 1; }
echo "SHA_OK copy==archive ($GOT)"
stat -c 'LOCAL_BIT %n size=%s mtime=%y' "$LOCAL_BIT"

echo "=== 板上烧前身份 (现读 0x04)"
$SSH --sudo "/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1"

echo "=== BURN $(date +%s.%N)"
T0=$(date +%s)
# ⚠️ 本机实证 (2026-10-11/探针): 设了 MSYS_NO_PATHCONV=1 时 `cmd //c` = **静默空跑** (rc=0,
#    只打 banner 不执行) ⇒ 必须写 `cmd /c` (与 sndwnd 模板一致)。首跑就是被这条坑到:
#    陈旧 stdout 被读 (mtime + 位流路径双判据把它抓住)。
TCPREG_BIT="$BIT_WIN" cmd /c "D:\\repo\\XCKU5PMini\\udp_hls_10g\\_proj_10g\\notes\\p7b_biz_tcpreg\\run_program_tcpreg.bat" >/dev/null 2>&1
F=$ROOT/_proj_10g/notes/p7b_biz_tcpreg/tcpreg_program_stdout.txt
MT=$(stat -c %Y "$F")
echo "BURN_STDOUT=$F mtime=$MT T0=$T0"
cp "$F" "$OUT/burn/BURN_0x1F_stdout_copy_$(date +%Y%m%d_%H%M%S).txt"
echo "--- burn stdout (关键行逐字) ---"
grep -E "TCPREG_BIT =|TCPREG_BIT_EXISTS|TCPREG_BIT_MTIME|End of startup status|TCPREG_PROG_DONE|TCPREG-ABORT|TCPREG_PROG device" "$F"
echo "--- end ---"
grep -q "End of startup status: HIGH" "$F" || { echo "BURN_FAIL (无 HIGH)"; exit 1; }
grep -v '^#' "$F" | grep -q "TCPREG_PROG_DONE" || { echo "BURN_FAIL (无 DONE)"; exit 1; }
grep -q "$BS" "$F" || { echo "BURN_FAIL (位流路径不匹配: 期望含 $BS)"; exit 1; }
grep -v '^#' "$F" | grep -q "TCPREG-ABORT" && { echo "BURN_FAIL (出现 TCPREG-ABORT)"; exit 1; }
echo "--- 非注释行里的 DONE/ABORT 判定 ---"
grep -v '^#' "$F" | grep -E "TCPREG_PROG_DONE|TCPREG-ABORT" | tail -3
[ "$MT" -ge "$((T0-5))" ] || { echo "BURN_FAIL (stdout 陈旧)"; exit 1; }
echo "BURN_OK (HIGH+DONE+bit路径+新鲜度+无ABORT 五判据)"

echo "=== RESCAN $(date +%s.%N)"
$SSH --sudo "sh -c 'echo 1 > /sys/bus/pci/devices/0000:02:00.0/remove; sleep 1; echo 1 > /sys/bus/pci/rescan'; sleep 3; echo '--- lspci ---'; lspci -s 02:00.0; lspci -vvv -s 02:00.0 2>/dev/null | grep -E 'LnkSta:|Region 0|Region 1'; echo '--- dev ---'; ls -la /dev/xdma0_user /dev/xdma0_c2h_0 /dev/xdma0_h2c_0"

echo "=== ID $(date +%s.%N)"
$SSH --sudo "EXPECT_BID=$EXPBID NW=71 bash /tmp/p8_board/p7b_snap.sh id; echo ID_RC=\$?; \
  T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools; \
  echo -n 'MAGIC_0x00='; \$T/reg_rw /dev/xdma0_user 0x00 w 2>&1 | tail -1; \
  echo -n 'BID_0x04=';   \$T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1; \
  echo -n 'W70_0x138=';  \$T/reg_rw /dev/xdma0_user 0x138 w 2>&1 | tail -1; \
  echo -n 'UNIMPL_0x14C='; \$T/reg_rw /dev/xdma0_user 0x14C w 2>&1 | tail -1; \
  echo -n 'MIR_STATUS_0x13C='; \$T/reg_rw /dev/xdma0_user 0x13C w 2>&1 | tail -1; \
  echo -n 'MIR_CTRL_0x144='; \$T/reg_rw /dev/xdma0_user 0x144 w 2>&1 | tail -1; \
  echo -n 'MIR_DMA_CNT_0x148='; \$T/reg_rw /dev/xdma0_user 0x148 w 2>&1 | tail -1; \
  echo -n 'SCRATCH_0x08='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1; \
  echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier"
echo "=== BURN_PHASE_DONE $(date +%s.%N)"
