#!/bin/bash
# burn_round_b2a.sh -- JTAG burn for p9_board_0x2A_20261017
#   Usage: PEER_PW=<pw> bash burn_round_b2a.sh <0x28|0x2A>
#   Skeleton = p9_c1_board_20261017/burn/burn_round_c1.sh (verbatim gates):
#     sha256 double-anchor BEFORE burn; after burn HIGH + DONE + bit path + freshness + no ABORT;
#     PCIe device-level remove+rescan (escalate to root port 00:1c.0); identity gate; NFF scan;
#     release controlled stop (0x08 <- 0).
#   0x2A ANCHOR NOTE: only ONE independent build artifact exists
#     (_proj_10g/notes/p9_build_0x2A_20261017/build/wrapper_p4.bit).
#     The second "anchor" is a byte copy made by this script into the round burn/ dir and
#     re-hashed afterwards -- it is NOT an independent source; registered as such.
#   never writes QSPI (JTAG volatile only).
set -u
GEN=${1:?usage: burn_round_b2a.sh <0x28|0x2A>}
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
ROOTW=D:/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p9_board_0x2A_20261017
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY $ROOTW/tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
KO=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/xdma/xdma.ko
S=/tmp/b2a_snap.sh
[ -n "${PEER_PW:-}" ] || { echo "FATAL: PEER_PW required"; exit 3; }
mkdir -p "$OUT/burn"

case "$GEN" in
  0x28)
    WANT=79c9cf434eb66723b97f654cbece9ea061632e2297c0a8ab0ea0dc198c43bec8
    A1=$ROOT/_proj_10g/notes/p9_build_0x28/wrapper_p4.bit
    A2=$ROOT/_proj_10g/notes/p9_mdio_aplus_board_20261016/burn/wrapper_p4_0x28.bit
    DST=$OUT/burn/wrapper_p4_0x28.bit
    NW=75; BID=0x00000028; UNIMPL=0x15C; ANCHOR_NOTE="double (independent)" ;;
  0x2A)
    WANT=aa44a0eda1604623eac951afc26b9f27d4798fc414a5eb9c7137ee47f9a2a3b6
    A1=$ROOT/_proj_10g/notes/p9_build_0x2A_20261017/build/wrapper_p4.bit
    A2=$OUT/burn/wrapper_p4_0x2A.bit
    DST=$OUT/burn/wrapper_p4_0x2A.bit
    NW=76; BID=0x0000002A; UNIMPL=0x160; ANCHOR_NOTE="single independent + local copy" ;;
  *) echo "GEN must be 0x28 or 0x2A"; exit 3 ;;
esac

exec > >(tee "$OUT/burn/BURN_${GEN}_$(date +%Y%m%d_%H%M%S).txt") 2>&1
echo "=== BURN_BEGIN gen=$GEN $(date +%s.%N) $(date) anchor=$ANCHOR_NOTE"

echo "--- 1) sha256 anchor check (must equal expected) ---"
sha256sum "$A1" ${A2:+"$A2"}
G1=$(sha256sum "$A1" | cut -d' ' -f1)
echo "WANT=$WANT"
[ "$G1" = "$WANT" ] || { echo "SHA_MISMATCH anchor1 => REFUSE TO BURN"; exit 1; }
if [ "$GEN" = "0x2A" ]; then
  cp -f "$A1" "$DST"
  G2=$(sha256sum "$DST" | cut -d' ' -f1)
  [ "$G2" = "$WANT" ] || { echo "SHA_MISMATCH local copy => REFUSE TO BURN"; exit 1; }
  echo "SHA_OK (build artifact + local byte copy == expected; copy is NOT independent)"
else
  G2=$(sha256sum "$A2" | cut -d' ' -f1)
  [ "$G2" = "$WANT" ] || { echo "SHA_MISMATCH anchor2 => REFUSE TO BURN"; exit 1; }
  echo "SHA_OK (anchor1 == anchor2 == expected)"
  cp -f "$A1" "$DST"
  sha256sum "$DST"
fi
stat -c 'LOCAL_BIT %n size=%s mtime=%y' "$DST"
BIT_WIN="D:\\repo\\XCKU5PMini\\udp_hls_10g\\_proj_10g\\notes\\p9_board_0x2A_20261017\\burn\\$(basename $DST)"

echo "--- 2) pre-burn state + hw_server + xdma insmod ---"
$SSH --sudo "systemctl is-active hw_server; lsmod | grep -w xdma || echo XDMA_NOT_LOADED"
$SSH --sudo "if ! lsmod | grep -qw xdma; then insmod $KO; echo INSMOD_RC=\$?; fi; sleep 2; lsmod | grep -w xdma | head -1"

echo "--- 3) burn (JTAG via 192.168.0.38:3121) $(date +%s) ---"
T0=$(date +%s)
TCPREG_BIT="$BIT_WIN" cmd /c "D:\\repo\\XCKU5PMini\\udp_hls_10g\\_proj_10g\\notes\\p7b_biz_tcpreg\\run_program_tcpreg.bat" >/dev/null 2>&1
F=$ROOT/_proj_10g/notes/p7b_biz_tcpreg/tcpreg_program_stdout.txt
MT=$(stat -c %Y "$F")
echo "BURN_STDOUT=$F mtime=$MT T0=$T0 age=$((MT-T0))s"
cp "$F" "$OUT/burn/BURN_stdout_copy_$(date +%Y%m%d_%H%M%S).txt"
grep -E "TCPREG_BIT =|TCPREG_BIT_EXISTS|End of startup status|TCPREG_PROG_DONE|TCPREG-ABORT|TCPREG_PROG device" "$F"
grep -q "End of startup status: HIGH" "$F" || { echo "BURN_FAIL (no HIGH)"; exit 1; }
grep -v '^#' "$F" | grep -q "TCPREG_PROG_DONE" || { echo "BURN_FAIL (no DONE)"; exit 1; }
grep -q "$(basename $DST)" "$F" || { echo "BURN_FAIL (bit path mismatch)"; exit 1; }
grep -v '^#' "$F" | grep -q "TCPREG-ABORT" && { echo "BURN_FAIL (ABORT present)"; exit 1; }
[ "$MT" -ge "$((T0-5))" ] || { echo "BURN_FAIL (stale stdout)"; exit 1; }
echo "BURN_OK (HIGH + DONE + path + freshness + no-ABORT)"

echo "--- 4) PCIe recovery: device-level remove+rescan (escalate to root port on failure) $(date +%s) ---"
$SSH --sudo "echo 1 > /sys/bus/pci/devices/0000:02:00.0/remove 2>/dev/null; sleep 2; echo 1 > /sys/bus/pci/rescan; sleep 5; lspci -vvv -s 02:00.0 2>/dev/null | grep -E 'LnkSta:' | head -2; dmesg | grep -i xdma | grep -E 'identify_bars|probe err' | tail -3; ls /dev/xdma0_user /dev/xdma0_control 2>&1"
$SSH --sudo "test -e /dev/xdma0_user || { echo 'DEVICE_LEVEL_FAILED => escalate to root port'; echo 1 > /sys/bus/pci/devices/0000:00:1c.0/remove; sleep 2; echo 1 > /sys/bus/pci/rescan; sleep 8; lspci -vvv -s 02:00.0 2>/dev/null | grep -E 'LnkSta:|Memory behind'; dmesg | grep -i xdma | grep -E 'identify_bars|probe err' | tail -3; ls /dev/xdma0_user 2>&1; }"

echo "--- 5) identity gate (GEN=$GEN: NW=$NW BID=$BID UNIMPL=$UNIMPL) ---"
$SSH --sudo "T=$T; echo -n 'MAGIC_0x00='; \$T/reg_rw /dev/xdma0_user 0x00 w 2>&1 | tail -1; echo -n 'BID_0x04='; \$T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1; echo -n 'UNIMPL_$UNIMPL='; \$T/reg_rw /dev/xdma0_user $UNIMPL w 2>&1 | tail -1; echo -n 'SCRATCH_0x08='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1; if [ '$GEN' = '0x2A' ]; then echo -n 'MIR_DMA_CNT_0x15C='; \$T/reg_rw /dev/xdma0_user 0x15C w 2>&1 | tail -1; fi"
$SSH --sudo "NW=$NW EXPECT_BID=$BID UNIMPL_ADDR=$UNIMPL bash $S id; echo ID_RC=\$?"

echo "--- 6) window scan: NFF must be 0 over NW words ---"
$SSH --sudo "T=$T; NFF=0; for i in \$(seq 0 $((NW-1))); do A=\$(printf '0x%X' \$((0x20+4*i))); V=\$(\$T/reg_rw /dev/xdma0_user \$A w 2>/dev/null | tail -1 | sed 's/.*: *//'); if [ \"\$V\" = \"0xffffffff\" ]; then echo \"NFF word\$i \$A = \$V\"; NFF=\$((NFF+1)); fi; done; echo WINDOW_SCAN_NFF=\$NFF"

echo "--- 7) release controlled stop (0x08 <- 0) ---"
$SSH --sudo "T=$T; \$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1; echo -n 'SCRATCH_0x08(after)='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1; echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier"
echo "=== BURN_END gen=$GEN $(date +%s.%N) ==="
