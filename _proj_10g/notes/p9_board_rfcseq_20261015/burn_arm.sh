#!/bin/bash
# burn_arm.sh -- B2 轮位流烧录（JTAG 易失; 绝不写 QSPI）—— 0x25 / 0x26 / 0x27 通用
#   配方 = B1 burn/burn_0x27.sh 逐条沿用（场景C 根端口 remove+rescan / 烧录五判据 / 身份门 / 71 字扫描）
#   ⚠️ 与 B1 的差异（已登记）: 第二锚不再是 impl_1（已被 0x27 覆盖）⇒ 改用
#      **(a) 报告硬编码 WANT + (b) 轮目录 SHA256SUMS.txt 记录值 + (c) 文件尺寸** 三重核对。
#   用法: PEER_PW=<pw> bash burn_arm.sh <BID>   # BID ∈ {0x25,0x26,0x27}
set -u
BID=${1:?usage: burn_arm.sh <0x25|0x26|0x27>}
# ⚠️ p7b_snap.sh 的身份门比较**不补零** (norm 只做小写归一) ⇒ 传 `0x25` 会对 `0x00000025` **假红**
#    (Stage C 大小写缺陷的同族; 板子是对的, 是门错) ⇒ 一律传 8 位补零形式。
BID8=$(printf '0x%08X' "$BID")
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
ROOTW=D:/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p9_board_rfcseq_20261015
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY $ROOTW/tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
KO=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/xdma/xdma.ko
[ -n "${PEER_PW:-}" ] || { echo "FATAL: 需要 PEER_PW"; exit 3; }
case "$BID" in
  0x25) WANT=faefa444e0d02ef9969d069d773614d65ace9583f51fd58c553463299db54c85
        SRC=$ROOT/_proj_10g/notes/p9_build_0x25/wrapper_p4.bit
        SUMS=$ROOT/_proj_10g/notes/p9_build_0x25/SHA256SUMS.txt
        COPY=wrapper_p4_0x25.bit ;;
  0x26) WANT=34e553eee8907b8a108303b43eb438199bea04285bbf213aa25585b6e9d94202
        SRC=$ROOT/_proj_10g/notes/p9_build_0x26/wrapper_p4.bit
        SUMS=$ROOT/_proj_10g/notes/p9_build_0x26/SHA256SUMS.txt
        COPY=wrapper_p4_0x26.bit ;;
  0x27) WANT=5c17b14f0656cf6680b7d16f7f1659faa4ca9225cf0cb0461765be7a91943385
        SRC=$ROOT/_proj_10g/notes/p9_build_0x27/wrapper_p4.bit
        SUMS=$ROOT/_proj_10g/notes/p9_build_0x27/SHA256SUMS.txt
        COPY=wrapper_p4_0x27.bit ;;
  *) echo "FATAL: 未知 BID $BID"; exit 3 ;;
esac
mkdir -p "$OUT/burn"
exec > >(tee "$OUT/burn/BURN_${BID}_$(date +%Y%m%d_%H%M%S).txt") 2>&1

echo "=== BURN_BEGIN bid=$BID $(date +%s.%N) $(date)"
echo "--- 1) 位流 sha256 三重核 (报告 WANT + SHA256SUMS.txt + 尺寸) ---"
stat -c 'SRC %n size=%s mtime=%y' "$SRC"
[ -f "$SRC" ] || { echo "SRC 不存在"; exit 1; }
GOT=$(sha256sum "$SRC" | cut -d' ' -f1)
echo "SHA_WANT=$WANT"; echo "SHA_GOT =$GOT"
[ "$GOT" = "$WANT" ] || { echo "SHA_MISMATCH (报告锚) => 拒绝烧"; exit 1; }
grep -q "$WANT" "$SUMS" || { echo "SHA_MISMATCH (SHA256SUMS.txt 记录) => 拒绝烧"; exit 1; }
SZ=$(stat -c %s "$SRC"); [ "$SZ" = "15431261" ] || { echo "SIZE_MISMATCH $SZ => 拒绝烧"; exit 1; }
echo "SHA_OK (报告锚 + SHA256SUMS + 15,431,261 B 三重通过)"
cp -f "$SRC" "$OUT/burn/$COPY"
sha256sum "$OUT/burn/$COPY"
BIT_WIN="D:\\repo\\XCKU5PMini\\udp_hls_10g\\_proj_10g\\notes\\p9_board_rfcseq_20261015\\burn\\$COPY"

echo "--- 2) 烧前现态 + hw_server + xdma 驱动 ---"
$SSH --sudo "systemctl is-active hw_server; echo '--- lspci before ---'; lspci -vvv -s 02:00.0 2>/dev/null | grep -E 'LnkSta:'; echo '--- lsmod ---'; lsmod | grep -w xdma || echo XDMA_NOT_LOADED"
$SSH --sudo "if ! lsmod | grep -qw xdma; then insmod $KO; echo INSMOD_RC=\$?; fi; sleep 3; lsmod | grep -w xdma; ls /dev/xdma0_control /dev/xdma0_user 2>&1"

echo "--- 3) 烧录 (JTAG via 192.168.0.38:3121, 1MHz) $(date +%s) ---"
T0=$(date +%s)
TCPREG_BIT="$BIT_WIN" cmd /c "D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p7b_biz_tcpreg\run_program_tcpreg.bat" >/dev/null 2>&1
F=$ROOT/_proj_10g/notes/p7b_biz_tcpreg/tcpreg_program_stdout.txt
MT=$(stat -c %Y "$F")
echo "BURN_STDOUT=$F mtime=$MT T0=$T0 age=$((MT-T0))s"
cp "$F" "$OUT/burn/BURN_stdout_copy_$(date +%Y%m%d_%H%M%S).txt"
grep -E "TCPREG_BIT =|End of startup status|TCPREG_PROG_DONE|TCPREG-ABORT|TCPREG_PROG device" "$F"
grep -q "End of startup status: HIGH" "$F" || { echo "BURN_FAIL (无 HIGH)"; exit 1; }
grep -v '^#' "$F" | grep -q "TCPREG_PROG_DONE" || { echo "BURN_FAIL (无 DONE)"; exit 1; }
grep -q "$COPY" "$F" || { echo "BURN_FAIL (位流路径不匹配)"; exit 1; }
grep -v '^#' "$F" | grep -q "TCPREG-ABORT" && { echo "BURN_FAIL (TCPREG-ABORT)"; exit 1; }
[ "$MT" -ge "$((T0-5))" ] || { echo "BURN_FAIL (stdout 陈旧)"; exit 1; }
echo "BURN_OK (HIGH+DONE+路径+新鲜度+无ABORT)"

echo "--- 4) PCIe 恢复 (先设备级; 失败再根端口级) $(date +%s) ---"
$SSH --sudo "echo 1 > /sys/bus/pci/devices/0000:02:00.0/remove 2>/dev/null; sleep 2; echo 1 > /sys/bus/pci/rescan; sleep 6; ls /dev/xdma0_user >/dev/null 2>&1 && echo DEVICE_LEVEL_OK || { echo DEVICE_LEVEL_FAIL_FALLBACK_ROOTPORT; lspci -vvv -s 00:1c.0 2>/dev/null | grep -E 'Memory behind bridge'; echo 1 > /sys/bus/pci/devices/0000:00:1c.0/remove; sleep 2; echo 1 > /sys/bus/pci/rescan; sleep 6; lspci -vvv -s 00:1c.0 2>/dev/null | grep -E 'Memory behind bridge'; }; echo '--- lspci 02:00.0 ---'; lspci -s 02:00.0; lspci -vvv -s 02:00.0 2>/dev/null | grep -E 'LnkSta:'; ls -la /dev/xdma0_user /dev/xdma0_c2h_0 /dev/xdma0_h2c_0 /dev/xdma0_control 2>&1; dmesg | grep -i xdma | grep -E 'identify_bars|probe_one' | tail -3"

echo "--- 5) 身份门 (BID $BID) ---"
$SSH --sudo "T=$T; echo -n 'MAGIC_0x00='; \$T/reg_rw /dev/xdma0_user 0x00 w 2>&1 | tail -1; echo -n 'BID_0x04='; \$T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1; echo -n 'MARKER_0x14='; \$T/reg_rw /dev/xdma0_user 0x14 w 2>&1 | tail -1; echo -n 'UNIMPL_0x14C='; \$T/reg_rw /dev/xdma0_user 0x14C w 2>&1 | tail -1; echo -n 'SCRATCH_0x08='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1"
$SSH --sudo "NW=71 EXPECT_BID=$BID8 bash /tmp/p7b_biz/p7b_snap.sh id; echo ID_RC=\$?"
$SSH --sudo "T=$T; NFF=0; for i in \$(seq 0 70); do A=\$(printf '0x%X' \$((0x20+4*i))); V=\$(\$T/reg_rw /dev/xdma0_user \$A w 2>/dev/null | tail -1 | sed 's/.*: *//'); if [ \"\$V\" = \"0xffffffff\" ]; then echo \"NFF word\$i \$A = \$V\"; NFF=\$((NFF+1)); fi; done; echo WINDOW_SCAN_NFF=\$NFF"
echo "--- 6) 解除受控停流 (0x08=0) ---"
$SSH --sudo "T=$T; \$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1; echo -n 'SCRATCH_0x08='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1"
echo "=== BURN_END bid=$BID $(date +%s.%N)"
