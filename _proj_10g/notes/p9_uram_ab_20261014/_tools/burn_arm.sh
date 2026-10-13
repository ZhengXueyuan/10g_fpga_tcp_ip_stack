#!/bin/bash
# burn_arm.sh <0x23|0x24> <seq> -- P9 URAM A/B 轮单次烧录 (只烧归档件, JTAG 易失, 绝不写 QSPI)
#   配方依据: p9_board_0x24_20261013/burn_0x24.sh + p9_board_0x23_20261011/burn_0x23.sh
#   判据: sha256 == 归档真值 + 五判据 (HIGH/DONE/路径/新鲜度/无ABORT) + 烧后 0x04==臂 BID + 2 BARs + LnkSta x4
#   ⚠️ 跑 bat 正确式 = `MSYS_NO_PATHCONV=1 ... cmd /c ...` (env + `cmd //c` 会互相抵消)
#   用法: PEER_PW=<pw> bash burn_arm.sh 0x23 1
set -u
ARM=${1:?arm 0x23|0x24}
SEQ=${2:?seq}
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
ROOTW=D:/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p9_uram_ab_20261014
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY $ROOTW/tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW (只用于 --sudo)"; exit 3; }

case "$ARM" in
  0x23) WANT=066a3923351b8f539a986b88d96f1093a686da57f95938e0c8837b13d30a3126
        EXPBID=0x00000023
        SRC=$ROOT/_proj_10g/notes/p9_build_0x23/wrapper_p4.bit ;;
  0x24) WANT=e3b07957aea0326a168b9db0238ef9dd933dc7a21884c92e50a7c3b0abadf1db
        EXPBID=0x00000024
        SRC=$ROOT/_proj_10g/notes/p9_build_0x24/wrapper_p4.bit ;;
  *) echo "FATAL: 未知 arm $ARM"; exit 3 ;;
esac
BS=wrapper_p4_${ARM}.bit
LOCAL_BIT=$OUT/burn/$BS
BIT_WIN="D:\\repo\\XCKU5PMini\\udp_hls_10g\\_proj_10g\\notes\\p9_uram_ab_20261014\\burn\\$BS"
TS=$(date +%Y%m%d_%H%M%S)
mkdir -p "$OUT/burn"
LOG=$OUT/burn/BURN_${ARM}_S${SEQ}_${TS}.txt
exec > >(tee "$LOG") 2>&1

echo "=== BURN_BEGIN arm=$ARM seq=$SEQ $(date +%s.%N) $(date)"
echo "--- 1) 烧前 sha256 核 (归档件 + 本轮副本) ---"
sha256sum "$SRC"
cp "$SRC" "$LOCAL_BIT"
sha256sum "$LOCAL_BIT"
GOT=$(sha256sum "$LOCAL_BIT" | cut -d' ' -f1)
echo "SHA_WANT=$WANT"
[ "$GOT" = "$WANT" ] || { echo "SHA_MISMATCH => 拒绝烧"; exit 1; }
echo "SHA_OK (副本 == 归档 == 期望真值)"
stat -c 'LOCAL_BIT %n size=%s mtime=%y' "$LOCAL_BIT"
echo "BIT_HEADER_120B: $(head -c 120 "$LOCAL_BIT" | tr -c '[:print:]' '.')"

echo "--- 2) 烧前板侧现态 (0x04 见证) $(date +%s) ---"
$SSH --sudo "T=$T; echo -n 'PREBURN_BID_0x04='; \$T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1; echo -n 'PREBURN_SCRATCH_0x08='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1; systemctl is-active hw_server"

echo "--- 3) 烧录 (JTAG via 192.168.0.38:3121, 1MHz) $(date +%s) ---"
T0=$(date +%s)
TCPREG_BIT="$BIT_WIN" cmd /c "D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p7b_biz_tcpreg\run_program_tcpreg.bat" >/dev/null 2>&1
F=$ROOT/_proj_10g/notes/p7b_biz_tcpreg/tcpreg_program_stdout.txt
MT=$(stat -c %Y "$F")
echo "BURN_STDOUT=$F mtime=$MT T0=$T0 age=$((MT-T0))s"
cp "$F" "$OUT/burn/BURN_${ARM}_S${SEQ}_stdout_copy_${TS}.txt"
echo "--- burn stdout 关键行 (逐字; 含 # 注释原文, 判别只看非注释行) ---"
grep -E "TCPREG_BIT =|TCPREG_BIT_EXISTS|TCPREG_BIT_MTIME|End of startup status|TCPREG_PROG_DONE|TCPREG-ABORT|TCPREG_PROG device" "$F"
grep -q "End of startup status: HIGH" "$F" || { echo "BURN_FAIL (无 HIGH) => 停止"; exit 1; }
grep -v '^#' "$F" | grep -q "TCPREG_PROG_DONE" || { echo "BURN_FAIL (无 DONE) => 停止"; exit 1; }
grep -q "$BS" "$F" || { echo "BURN_FAIL (位流路径不匹配) => 停止"; exit 1; }
grep -v '^#' "$F" | grep -q "TCPREG-ABORT" && { echo "BURN_FAIL (出现 TCPREG-ABORT) => 停止"; exit 1; }
[ "$MT" -ge "$((T0-5))" ] || { echo "BURN_FAIL (stdout 陈旧: 本次没跑) => 停止"; exit 1; }
echo "BURN_OK (HIGH+DONE+路径+新鲜度+无ABORT 五判据)"

echo "--- 4) PCIe 恢复 (设备级 remove+rescan; 不够则升根端口) $(date +%s) ---"
$SSH --sudo "sh -c '
  RP=\$(basename \$(dirname \$(readlink -f /sys/bus/pci/devices/0000:02:00.0 2>/dev/null))) 2>/dev/null
  echo RP_PORT=\$RP
  echo 1 > /sys/bus/pci/devices/0000:02:00.0/remove 2>/dev/null; sleep 1; echo 1 > /sys/bus/pci/rescan; sleep 4
  W=\$(lspci -vvv -s 02:00.0 2>/dev/null | grep -o \"Width x[0-9]*\" | head -1)
  echo FIRST_RESCAN_LNKSTA_WIDTH=\$W
  if [ \"\$W\" != \"Width x4\" ]; then
    echo \"设备级 x4 未拿到 => 升级到根端口级 remove+rescan\"
    echo 1 > /sys/bus/pci/devices/\$RP/remove; sleep 1; echo 1 > /sys/bus/pci/rescan; sleep 5
  fi
  echo \"--- lspci ---\"; lspci -s 02:00.0; lspci -vvv -s 02:00.0 2>/dev/null | grep -E \"LnkSta:|Region 0|Region 1\"
  echo \"--- dev ---\"; ls -la /dev/xdma0_user /dev/xdma0_c2h_0 /dev/xdma0_h2c_0 /dev/xdma0_control 2>&1'"
echo "--- dmesg (identify_bars: 期望 2 BARs: config 1, user 0) ---"
$SSH --sudo "dmesg 2>/dev/null | grep -i xdma | grep -E 'identify_bars' | tail -3"

echo "--- 5) 身份门 (0x04==$EXPBID + 五判据+窗口扫描) $(date +%s) ---"
$SSH --sudo "T=$T; echo -n 'MAGIC_0x00='; \$T/reg_rw /dev/xdma0_user 0x00 w 2>&1 | tail -1; echo -n 'BID_0x04='; \$T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1; echo -n 'MARKER_0x14='; \$T/reg_rw /dev/xdma0_user 0x14 w 2>&1 | tail -1; echo -n 'UNIMPL_0x14C='; \$T/reg_rw /dev/xdma0_user 0x14C w 2>&1 | tail -1; echo -n 'SCRATCH_0x08='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1; echo -n 'MIR_STATUS_0x13C='; \$T/reg_rw /dev/xdma0_user 0x13C w 2>&1 | tail -1; echo -n 'MIR_CTRL_0x144='; \$T/reg_rw /dev/xdma0_user 0x144 w 2>&1 | tail -1; echo -n 'MIR_DMA_CNT_0x148='; \$T/reg_rw /dev/xdma0_user 0x148 w 2>&1 | tail -1"
$SSH --sudo "NW=71 EXPECT_BID=$EXPBID bash /tmp/p9_rate/p7b_snap.sh id; echo ID_RC=\$?"
$SSH --sudo "T=$T; NFF=0; for i in \$(seq 0 70); do A=\$(printf '0x%X' \$((0x20+4*i))); V=\$(\$T/reg_rw /dev/xdma0_user \$A w 2>/dev/null | tail -1 | sed 's/.*: *//'); if [ \"\$V\" = \"0xffffffff\" ]; then echo \"NFF word\$i \$A = \$V\"; NFF=\$((NFF+1)); fi; done; echo WINDOW_SCAN_NFF=\$NFF"

echo "--- 6) 链路 (新配置后 0x08/停流/载波; 需要才写 0x08=0) $(date +%s) ---"
sleep 6
$SSH --sudo "T=$T; echo -n 'SCRATCH_0x08='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1; echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier; ethtool enp1s0f1np1 2>/dev/null | grep -E 'Speed|Link detected'"
echo "=== BURN_END arm=$ARM seq=$SEQ $(date +%s.%N)"
