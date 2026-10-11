#!/bin/bash
# burn_0x23.sh -- P9 板级 A/B 轮: 烧归档位流 0x23 (AXIS + clr/停流新口径; BID 0x23)
#   纪律: 只走 JTAG 易失烧录 (绝不写 QSPI); 只烧本目录副本 (burn/wrapper_p4_0x23.bit,
#         从 _proj_10g/notes/p9_build_0x23/wrapper_p4.bit 复制); 烧前 sha256 双核; 烧后核板侧 BID.
#   判据: sha256 == 派单值 + stdout 新鲜 (mtime) + 位流路径匹配 + "End of startup status: HIGH"
#         + 非注释行 TCPREG_PROG_DONE + 无 TCPREG-ABORT.
#   ⚠️ heredoc 吞 `$变量` 坑 ⇒ BIT_WIN 用**单引号字面路径**.
#   ⚠️ 跑 bat 正确式 = `MSYS_NO_PATHCONV=1 cmd /c '...'` (env + `cmd //c` 会互相抵消).
#   用法: PEER_PW=<pw> bash burn_0x23.sh
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p9_board_0x23_20261011
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY D:/repo/XCKU5PMini/udp_hls_10g/tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW (只用于 --sudo)"; exit 3; }

WANT=066a3923351b8f539a986b88d96f1093a686da57f95938e0c8837b13d30a3126
EXPBID=0x00000023
SRC=$ROOT/_proj_10g/notes/p9_build_0x23/wrapper_p4.bit
BS=wrapper_p4_0x23.bit
LOCAL_BIT=$OUT/burn/$BS
BIT_WIN='D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_board_0x23_20261011\burn\wrapper_p4_0x23.bit'

mkdir -p "$OUT/burn"
LOG=$OUT/burn/BURN_0x23_$(date +%Y%m%d_%H%M%S).txt
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

echo "=== 板上烧前身份 (现读 0x04; 期望 = 0x22)"
$SSH --sudo "$T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1"
echo "--- 烧前对照臂基线 (0x22 上的 ctrl identifier / alignments) ---"
$SSH --sudo "T=$T; for a in 0x0000 0x1000 0x004C 0x104C; do printf 'ctrl %s=' \$a; \$T/reg_rw /dev/xdma0_control \$a r 2>&1 | tail -1; done"

echo "=== BURN $(date +%s.%N)"
T0=$(date +%s)
TCPREG_BIT="$BIT_WIN" cmd /c "D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p7b_biz_tcpreg\run_program_tcpreg.bat" >/dev/null 2>&1
F=$ROOT/_proj_10g/notes/p7b_biz_tcpreg/tcpreg_program_stdout.txt
MT=$(stat -c %Y "$F")
echo "BURN_STDOUT=$F mtime=$MT T0=$T0"
cp "$F" "$OUT/burn/BURN_0x23_stdout_copy_$(date +%Y%m%d_%H%M%S).txt"
echo "--- burn stdout (关键行逐字) ---"
grep -E "TCPREG_BIT =|TCPREG_BIT_EXISTS|TCPREG_BIT_MTIME|End of startup status|TCPREG_PROG_DONE|TCPREG-ABORT|TCPREG_PROG device" "$F"
echo "--- end ---"
grep -q "End of startup status: HIGH" "$F" || { echo "BURN_FAIL (无 HIGH)"; exit 1; }
grep -v '^#' "$F" | grep -q "TCPREG_PROG_DONE" || { echo "BURN_FAIL (无 DONE)"; exit 1; }
grep -q "$BS" "$F" || { echo "BURN_FAIL (位流路径不匹配: 期望含 $BS)"; exit 1; }
grep -v '^#' "$F" | grep -q "TCPREG-ABORT" && { echo "BURN_FAIL (出现 TCPREG-ABORT)"; exit 1; }
[ "$MT" -ge "$((T0-5))" ] || { echo "BURN_FAIL (stdout 陈旧)"; exit 1; }
echo "BURN_OK (HIGH+DONE+bit路径+新鲜度+无ABORT 五判据)"

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
  echo \"--- lspci ---\"; lspci -s 02:00.0; lspci -vvv -s 02:00.0 2>/dev/null | grep -E \"LnkSta:|Region 0|Region 1\"
  echo \"--- dev ---\"; ls -la /dev/xdma0_user /dev/xdma0_c2h_0 /dev/xdma0_h2c_0 /dev/xdma0_control'"
echo "--- dmesg (identify_bars: 期望 2 BARs: config 1, user 0; 引擎名) ---"
$SSH --sudo "dmesg 2>/dev/null | grep -i xdma | grep -E 'identify_bars|probe_one|streaming|C2H0' | tail -6"

echo "=== ID (五判据) $(date +%s.%N)"
$SSH --sudo "T=$T; NW=71 EXPECT_BID=$EXPBID bash /tmp/p9_board_0x23/p7b_snap.sh id; echo ID_RC=\$?; \
  echo -n 'MAGIC_0x00='; \$T/reg_rw /dev/xdma0_user 0x00 w 2>&1 | tail -1; \
  echo -n 'BID_0x04=';   \$T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1; \
  echo -n 'UNIMPL_0x14C='; \$T/reg_rw /dev/xdma0_user 0x14C w 2>&1 | tail -1; \
  echo -n 'MARKER_0x0C='; \$T/reg_rw /dev/xdma0_user 0x0C w 2>&1 | tail -1; \
  echo -n 'MIR_STATUS_0x13C='; \$T/reg_rw /dev/xdma0_user 0x13C w 2>&1 | tail -1; \
  echo -n 'MIR_CTRL_0x144='; \$T/reg_rw /dev/xdma0_user 0x144 w 2>&1 | tail -1; \
  echo -n 'MIR_DMA_CNT_0x148='; \$T/reg_rw /dev/xdma0_user 0x148 w 2>&1 | tail -1; \
  echo -n 'SCRATCH_0x08='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1"
echo "--- 71 字窗口逐字扫 (0x20..0x138; 期望无 0xffffffff) ---"
$SSH --sudo "T=$T; NFF=0; for i in \$(seq 0 70); do A=\$(printf '0x%X' \$((0x20+4*i))); V=\$(\$T/reg_rw /dev/xdma0_user \$A w 2>/dev/null | tail -1 | sed 's/.*: *//'); if [ \"\$V\" = \"0xffffffff\" ]; then echo \"NFF word\$i \$A = \$V\"; NFF=\$((NFF+1)); fi; done; echo WINDOW_SCAN_NFF=\$NFF"
echo "--- 烧后清零核对 (重配置 ⇒ W11/W13/W70 应 0; MIR_CTRL=0; MIR_DMA_CNT=0) ---"
$SSH --sudo "cd /tmp/p9_board_0x23 && NW=71 EXPECT_BID=$EXPBID bash ./p7b_snap.sh snap post_burn 5 11 13 70 2>&1 | tail -8"
$SSH --sudo "T=$T; echo -n 'MIR_CTRL readback='; \$T/reg_rw /dev/xdma0_user 0x144 w 2>&1 | tail -1; echo -n 'MIR_DMA_CNT readback='; \$T/reg_rw /dev/xdma0_user 0x148 w 2>&1 | tail -1"
echo "=== BURN_PHASE_DONE $(date +%s.%N)"
