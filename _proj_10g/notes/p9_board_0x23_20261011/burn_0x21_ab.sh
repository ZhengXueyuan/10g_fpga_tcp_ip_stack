#!/bin/bash
# burn_0x21_ab.sh -- P9 0x23 轮的 **MM 对照臂 (P4)**: 烧归档位流 0x21 (MM 环 + STG; BID 0x21)
#   纪律同 burn_0x23.sh: 只走 JTAG 易失; 只烧本目录副本 (从 p8_board_0x21_20261011/burn/ 复制);
#   烧前 sha256 双核 (派单值 fbb6fca8…892c); 烧后核板侧 BID (= 0x00000021).
#   用法: PEER_PW=<pw> bash burn_0x21_ab.sh
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p9_board_0x23_20261011
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY D:/repo/XCKU5PMini/udp_hls_10g/tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW"; exit 3; }

WANT=fbb6fca81076a28b80fcc7a794de698c4253cc36961b7b682887818e1514892c
EXPBID=0x00000021
SRC=$ROOT/_proj_10g/notes/p8_board_0x21_20261011/burn/wrapper_p4_0x21.bit
BS=wrapper_p4_0x21_ab.bit
LOCAL_BIT=$OUT/burn/$BS
BIT_WIN='D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_board_0x23_20261011\burn\wrapper_p4_0x21_ab.bit'

mkdir -p "$OUT/burn"
LOG=$OUT/burn/BURN_0x21_AB_$(date +%Y%m%d_%H%M%S).txt
exec > >(tee "$LOG") 2>&1

echo "=== COPY $(date +%s.%N)"
cp "$SRC" "$LOCAL_BIT"
echo "--- 源 (0x21 轮归档) ---"; sha256sum "$SRC"
echo "--- 副本 (烧录件) ---";   sha256sum "$LOCAL_BIT"
GOT=$(sha256sum "$LOCAL_BIT" | cut -d' ' -f1)
echo "SHA_WANT want=$WANT"
[ "$GOT" = "$WANT" ] || { echo "SHA_MISMATCH ⇒ 拒绝烧"; exit 1; }
echo "SHA_OK copy==archive ($GOT)"

echo "=== 板上烧前身份 (现读 0x04; 期望 = 0x23)"
$SSH --sudo "$T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1"

echo "=== BURN $(date +%s.%N)"
T0=$(date +%s)
TCPREG_BIT="$BIT_WIN" cmd /c "D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p7b_biz_tcpreg\run_program_tcpreg.bat" >/dev/null 2>&1
F=$ROOT/_proj_10g/notes/p7b_biz_tcpreg/tcpreg_program_stdout.txt
MT=$(stat -c %Y "$F")
echo "BURN_STDOUT=$F mtime=$MT T0=$T0"
cp "$F" "$OUT/burn/BURN_0x21_AB_stdout_copy_$(date +%Y%m%d_%H%M%S).txt"
grep -E "TCPREG_BIT =|End of startup status|TCPREG_PROG_DONE|TCPREG-ABORT" "$F"
grep -q "End of startup status: HIGH" "$F" || { echo "BURN_FAIL (无 HIGH)"; exit 1; }
grep -v '^#' "$F" | grep -q "TCPREG_PROG_DONE" || { echo "BURN_FAIL (无 DONE)"; exit 1; }
grep -q "$BS" "$F" || { echo "BURN_FAIL (位流路径不匹配)"; exit 1; }
grep -v '^#' "$F" | grep -q "TCPREG-ABORT" && { echo "BURN_FAIL (出现 TCPREG-ABORT)"; exit 1; }
[ "$MT" -ge "$((T0-5))" ] || { echo "BURN_FAIL (stdout 陈旧)"; exit 1; }
echo "BURN_OK (0x21 对照臂)"

echo "=== RESCAN $(date +%s.%N)"
$SSH --sudo "sh -c '
  RP=\$(basename \$(dirname \$(readlink -f /sys/bus/pci/devices/0000:02:00.0)))
  echo ROOTPORT=\$RP
  echo 1 > /sys/bus/pci/devices/0000:02:00.0/remove; sleep 1; echo 1 > /sys/bus/pci/rescan; sleep 4
  W=\$(lspci -vvv -s 02:00.0 2>/dev/null | grep -o \"Width x[0-9]*\" | head -1)
  echo FIRST_RESCAN_LNKSTA_WIDTH=\$W
  if [ \"\$W\" != \"Width x4\" ]; then
    echo \"设备级 x4 未拿到 ⇒ 升级到根端口级 remove+rescan\"
    echo 1 > /sys/bus/pci/devices/\$RP/remove; sleep 1; echo 1 > /sys/bus/pci/rescan; sleep 5
  fi
  lspci -vvv -s 02:00.0 2>/dev/null | grep -E \"LnkSta:|Region 0|Region 1\"'"
echo "--- 身份 (0x21 对照臂: BID 应 = 0x00000021) ---"
$SSH --sudo "T=$T; NW=71 EXPECT_BID=$EXPBID bash /tmp/p9_board_0x23/p7b_snap.sh id; echo ID_RC=\$?; \
  echo -n 'BID_0x04=';   \$T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1; \
  echo -n 'MIR_STATUS_0x13C='; \$T/reg_rw /dev/xdma0_user 0x13C w 2>&1 | tail -1; \
  echo -n 'SCRATCH_0x08='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1"
echo "=== BURN_0x21_AB_DONE $(date +%s.%N)"
