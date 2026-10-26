#!/bin/bash
# burn_0x33_board.sh -- P11 E1a-1 (0x33) JTAG volatile burn + identity gate.
#   QSPI is NEVER written. 1 MHz. Requires bits/wrapper_p4_0x33.bit + bits/SHA256.txt.
#   Usage: PEER_PW=<pw> bash burn_0x33_board.sh
set -u
OUT=/d/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p11_e1a_design_20261027
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY D:/repo/XCKU5PMini/udp_hls_10g/tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
KO=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/xdma/xdma.ko
S=/tmp/p7b_snap.sh
[ -n "${PEER_PW:-}" ] || { echo "FATAL: PEER_PW required"; exit 3; }
mkdir -p "$OUT/burn" "$OUT/raw"

BIT=$OUT/bits/wrapper_p4_0x33.bit
SHAF=$OUT/bits/SHA256.txt
[ -f "$BIT" ] || { echo "FATAL: missing $BIT"; exit 3; }
[ -f "$SHAF" ] || { echo "FATAL: missing $SHAF"; exit 3; }
WANT=$(grep -Eo '[0-9a-f]{64}' "$SHAF" | head -1)
[ -n "$WANT" ] || { echo "FATAL: no sha in $SHAF"; exit 3; }
NW=97; BID=0x00000033; UNIMPL=0x1B4
DST=$OUT/burn/wrapper_p4_0x33.bit

exec > >(tee "$OUT/burn/BURN_0x33_$(date +%Y%m%d_%H%M%S).txt") 2>&1
echo "=== BURN_BEGIN gen=0x33 $(date +%s.%N) $(date)"

echo "--- 1) sha256 anchor ---"
G1=$(sha256sum "$BIT" | cut -d' ' -f1)
echo "WANT=$WANT GOT=$G1"
[ "$G1" = "$WANT" ] || { echo "SHA_MISMATCH anchor => REFUSE"; exit 1; }
cp -f "$BIT" "$DST"
G2=$(sha256sum "$DST" | cut -d' ' -f1)
[ "$G2" = "$WANT" ] || { echo "SHA_MISMATCH copy => REFUSE"; exit 1; }
echo "SHA_OK (copy is not an independent anchor)"
BIT_WIN="D:\\repo\\XCKU5PMini\\udp_hls_10g\\_proj_10g\\notes\\p11_e1a_design_20261027\\burn\\$(basename $DST)"

echo "--- 2) pre-burn peer state ---"
$SSH --sudo "systemctl is-active hw_server; lspci -vv -s 02:00.0 2>/dev/null | grep -E 'LnkSta:|Region [0-9]+:'; ls /dev/xdma* 2>&1 | head; lsmod | grep -w xdma || echo XDMA_NOT_LOADED"
RP=$($SSH --sudo "readlink -f /sys/bus/pci/devices/0000:02:00.0 2>/dev/null | xargs -r dirname | xargs -r basename")
echo "PARENT_ROOT_PORT=${RP:-UNKNOWN}"
$SSH --sudo "if ! lsmod | grep -qw xdma; then insmod $KO; echo INSMOD_RC=\$?; fi; sleep 2; lsmod | grep -w xdma | head -1"

echo "--- 3) burn via JTAG 192.168.0.38:3121 @1MHz $(date +%s) ---"
T0=$(date +%s)
( unset MSYS_NO_PATHCONV; TCPREG_BIT="$BIT_WIN" cmd //c "D:\\repo\\XCKU5PMini\\udp_hls_10g\\_proj_10g\\notes\\p7b_biz_tcpreg\\run_program_tcpreg.bat" ) >/dev/null 2>&1
F=/d/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p7b_biz_tcpreg/tcpreg_program_stdout.txt
MT=$(stat -c %Y "$F")
echo "BURN_STDOUT=$F mtime=$MT T0=$T0 age=$((MT-T0))s"
cp "$F" "$OUT/burn/BURN_stdout_copy_$(date +%Y%m%d_%H%M%S).txt"
grep -E "TCPREG_BIT =|TCPREG_BIT_EXISTS|TCPREG_BIT_MTIME|End of startup status|TCPREG_PROG_DONE|TCPREG-ABORT|TCPREG_PROG device" "$F"
grep -q "End of startup status: HIGH" "$F" || { echo "BURN_FAIL (no HIGH)"; exit 1; }
grep -v '^#' "$F" | grep -q "TCPREG_PROG_DONE" || { echo "BURN_FAIL (no DONE)"; exit 1; }
grep -q "$(basename $DST)" "$F" || { echo "BURN_FAIL (path mismatch)"; exit 1; }
grep -v '^#' "$F" | grep -q "TCPREG-ABORT" && { echo "BURN_FAIL (ABORT)"; exit 1; }
[ "$MT" -ge "$((T0-5))" ] || { echo "BURN_FAIL (stale stdout)"; exit 1; }
echo "BURN_OK (HIGH + DONE + path + freshness + no-ABORT)"

echo "--- 4) PCIe recovery ---"
$SSH --sudo "echo 1 > /sys/bus/pci/devices/0000:02:00.0/remove 2>/dev/null; sleep 2; echo 1 > /sys/bus/pci/rescan; sleep 5; lspci -vv -s 02:00.0 2>/dev/null | grep -E 'LnkSta:|Region [0-9]+:'; ls /dev/xdma0_user 2>&1"
$SSH --sudo "test -e /dev/xdma0_user || { echo 'DEVICE_LEVEL_FAILED => escalate to root port'; RP='$RP'; test -n \"\$RP\" || exit 2; echo 1 > /sys/bus/pci/devices/\$RP/remove; sleep 2; echo 1 > /sys/bus/pci/rescan; sleep 10; lspci -vv -s 02:00.0 2>/dev/null | grep -E 'LnkSta:|Region [0-9]+:'; dmesg | grep -i xdma | grep -E 'identify_bars|probe err|BAR' | tail -6; ls /dev/xdma0_user 2>&1; }"
$SSH --sudo "test -e /dev/xdma0_user && { echo -n 'BAR_COUNT='; lspci -vv -s 02:00.0 2>/dev/null | grep -cE '^[[:space:]]*Region [0-9]+: (Memory|I/O)'; dmesg | grep -i xdma | grep -E 'identify_bars' | tail -2; } || echo PCIE_FAIL"

echo "--- 5) identity (0x33: NW=$NW BID=$BID UNIMPL=$UNIMPL) ---"
$SSH --sudo "T=$T; for A in 0x00 0x04 0x14 $UNIMPL 0x08; do echo -n \"REG_\$A=\"; \$T/reg_rw /dev/xdma0_user \$A w 2>&1 | tail -1 | sed 's/.*: *//'; done"
$SSH --sudo "T=$T; for A in 0x1A4 0x1A8 0x1AC 0x1B0; do echo -n \"MIR_\$A=\"; \$T/reg_rw /dev/xdma0_user \$A w 2>&1 | tail -1 | sed 's/.*: *//'; done"
$SSH --sudo "NW=$NW EXPECT_BID=$BID UNIMPL_ADDR=$UNIMPL bash $S id; echo ID_RC=\$?"

echo "--- 6) window scan: NFF must be 0 over NW words ---"
$SSH --sudo "T=$T; NFF=0; for i in \$(seq 0 $((NW-1))); do A=\$(printf '0x%X' \$((0x20+4*i))); V=\$(\$T/reg_rw /dev/xdma0_user \$A w 2>/dev/null | tail -1 | sed 's/.*: *//'); if [ \"\$V\" = \"0xffffffff\" ]; then echo \"NFF word\$i \$A = \$V\"; NFF=\$((NFF+1)); fi; done; echo WINDOW_SCAN_NFF=\$NFF"

echo "--- 6b) link/BAR/carrier ---"
sleep 2
$SSH --sudo "lspci -vv -s 02:00.0 2>/dev/null | grep -E 'LnkSta:' | head -2; echo -n 'BAR_COUNT='; lspci -vv -s 02:00.0 2>/dev/null | grep -cE '^[[:space:]]*Region [0-9]+: (Memory|I/O)'; echo -n 'SYSFS_RESOURCE_NONZERO='; awk '\$1!=\"0x0000000000000000\" && NF>0 {n++} END{print n+0}' /sys/bus/pci/devices/0000:02:00.0/resource"
$SSH --sudo "echo -n 'CARRIER_P1='; ip netns exec nsa cat /sys/class/net/enp1s0f1np1/carrier; echo -n 'CARRIER_P0='; ip netns exec nsb cat /sys/class/net/enp1s0f0np0/carrier"

echo "--- 7) release controlled stop (0x08 <- 0) ---"
$SSH --sudo "T=$T; \$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1; echo -n 'SCRATCH_0x08(after)='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1 | sed 's/.*: *//'; echo -n 'CARRIER_P1='; ip netns exec nsa cat /sys/class/net/enp1s0f1np1/carrier; echo -n 'CARRIER_P0='; ip netns exec nsb cat /sys/class/net/enp1s0f0np0/carrier"
echo "=== BURN_END gen=0x33 $(date +%s.%N) ==="
