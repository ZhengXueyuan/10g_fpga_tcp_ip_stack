#!/bin/bash
# restore_0x28.sh -- p9_mdio_aplus_board_20261016 final step: burn 0x28 back + PCIe recovery
#   + identity gate + restore 0x08=0 (ledger-active board state = B4 finish state).
#   Recipes: B4 burn_0x28.sh (scenario-C aware) + B3/burn_arm.sh (device- then root-port-level)
#   with the E-0 fix: the escalation trigger reads the LnkSta LINE (not "first Width x[0-9]*",
#   which is the LnkCap width and never triggers).
#   PW discipline: PEER_PW read once, unset, per-command env prefix only.
#   Usage: PEER_PW=<pw> bash restore_0x28.sh
set -u
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
ROOTW=D:/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p9_mdio_aplus_board_20261016
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY $ROOTW/tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
PW=${PEER_PW:?PEER_PW required}
unset PEER_PW
mkdir -p "$OUT/burn"
LOG=$OUT/burn/BURN_0x28_RESTORE_$(date +%Y%m%d_%H%M%S).txt
exec > >(tee "$LOG") 2>&1

echo "=== RESTORE_BEGIN $(date +%s.%N) $(date)"
WANT=79c9cf434eb66723b97f654cbece9ea061632e2297c0a8ab0ea0dc198c43bec8
SRC=$ROOT/_proj_10g/notes/p9_build_0x28/wrapper_p4.bit
IMPL=$ROOT/vivado_prj/p7b_ku5p_prj.runs/impl_1/wrapper_p4.bit

echo "--- 1) sha256 gate (archive + impl_1 cross-check) ---"
sha256sum "$SRC"
GOT=$(sha256sum "$SRC" | cut -d' ' -f1)
echo "SHA_WANT=$WANT"
[ "$GOT" = "$WANT" ] || { echo "SHA_MISMATCH (archive) => refuse"; exit 1; }
if [ -f "$IMPL" ]; then
  IMPH=$(sha256sum "$IMPL" | cut -d' ' -f1)
  echo "IMPL1_ORIG_SHA=$IMPH"
  [ "$IMPH" = "$WANT" ] || { echo "SHA_MISMATCH (impl_1 != archive) => refuse"; exit 1; }
else
  echo "IMPL1_ORIG_MISSING (cross-check skipped, archive is the only copy here)"
fi
echo "SHA_OK"
cp -f "$SRC" "$OUT/burn/wrapper_p4_0x28.bit"
sha256sum "$OUT/burn/wrapper_p4_0x28.bit"
stat -c 'LOCAL_BIT %n size=%s mtime=%y' "$OUT/burn/wrapper_p4_0x28.bit"
BIT_WIN='D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_mdio_aplus_board_20261016\burn\wrapper_p4_0x28.bit'

echo "--- 2) PRE witness (mdio state: PCIe reads will fail, expected) ---"
PEER_PW="$PW" $SSH --sudo "systemctl is-active hw_server; T=$T; echo -n 'PRE_0x04='; \$T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1" || echo "PRE_READ_FAILED (continuing)"

echo "--- 3) burn via tcpreg launcher (JTAG 1MHz) $(date +%s) ---"
T0=$(date +%s)
TCPREG_BIT="$BIT_WIN" cmd /c "D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p7b_biz_tcpreg\run_program_tcpreg.bat" >/dev/null 2>&1
F=$ROOT/_proj_10g/notes/p7b_biz_tcpreg/tcpreg_program_stdout.txt
MT=$(stat -c %Y "$F")
echo "BURN_STDOUT=$F mtime=$MT T0=$T0 age=$((MT-T0))s"
cp "$F" "$OUT/burn/BURN_0x28_stdout_copy_$(date +%Y%m%d_%H%M%S).txt"
grep -E "TCPREG_BIT =|TCPREG_BIT_EXISTS|TCPREG_BIT_MTIME|End of startup status|TCPREG_PROG_DONE|TCPREG-ABORT|TCPREG_PROG device" "$F"
grep -q "End of startup status: HIGH" "$F" || { echo "BURN_FAIL (no HIGH) => stop"; exit 1; }
grep -v '^#' "$F" | grep -q "TCPREG_PROG_DONE" || { echo "BURN_FAIL (no DONE) => stop"; exit 1; }
grep -q "wrapper_p4_0x28.bit" "$F" || { echo "BURN_FAIL (bit path mismatch) => stop"; exit 1; }
grep -v '^#' "$F" | grep -q "TCPREG-ABORT" && { echo "BURN_FAIL (TCPREG-ABORT) => stop"; exit 1; }
[ "$MT" -ge "$((T0-5))" ] || { echo "BURN_FAIL (stale stdout) => stop"; exit 1; }
echo "BURN_OK (five criteria)"

echo "--- 4) PCIe recovery: device-level remove+rescan, escalate on the LnkSta LINE $(date +%s) ---"
PEER_PW="$PW" $SSH --sudo "sh -c '
  RP=\$(basename \$(dirname \$(readlink -f /sys/bus/pci/devices/0000:02:00.0 2>/dev/null))) 2>/dev/null
  case \"\$RP\" in 00*|02*) ;; *) RP=00:1c.0 ;; esac
  echo RP_PORT=\$RP
  echo 1 > /sys/bus/pci/devices/0000:02:00.0/remove 2>/dev/null; sleep 1; echo 1 > /sys/bus/pci/rescan; sleep 4
  W=\$(lspci -vvv -s 02:00.0 2>/dev/null | grep -m1 \"LnkSta:\")
  echo FIRST_RESCAN_LNKSTA_LINE=\"\$W\"
  case \"\$W\" in
    *\"Width x4\"*) echo \"device-level rescan got x4\" ;;
    *) echo \"escalating to root-port-level remove+rescan (\$RP)\"
       echo 1 > /sys/bus/pci/devices/\$RP/remove; sleep 1; echo 1 > /sys/bus/pci/rescan; sleep 5 ;;
  esac
  echo \"--- lspci ---\"; lspci -s 02:00.0; lspci -vvv -s 02:00.0 2>/dev/null | grep -E \"LnkSta:|Region 0|Region 1\"
  echo \"--- dev ---\"; ls -la /dev/xdma0_user /dev/xdma0_c2h_0 /dev/xdma0_h2c_0 /dev/xdma0_control 2>&1'"
echo "--- dmesg (identify_bars expect 2 BARs: config 1, user 0) ---"
PEER_PW="$PW" $SSH --sudo "dmesg 2>/dev/null | grep -i xdma | grep -E 'identify_bars' | tail -3"

echo "--- 5) identity gate $(date +%s) ---"
PEER_PW="$PW" $SSH --sudo "T=$T; echo -n 'MAGIC_0x00='; \$T/reg_rw /dev/xdma0_user 0x00 w 2>&1 | tail -1; echo -n 'BID_0x04='; \$T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1; echo -n 'MARKER_0x14='; \$T/reg_rw /dev/xdma0_user 0x14 w 2>&1 | tail -1; echo -n 'UNIMPL_0x15C='; \$T/reg_rw /dev/xdma0_user 0x15C w 2>&1 | tail -1; echo -n 'SCRATCH_0x08='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1"
PEER_PW="$PW" $SSH --sudo "NW=75 EXPECT_BID=0x00000028 bash /tmp/p7b_biz/p7b_snap.sh id; echo ID_RC=\$?"
echo "--- 6) 75-word window scan (expect NFF=0) ---"
PEER_PW="$PW" $SSH --sudo "T=$T; NFF=0; for i in \$(seq 0 74); do A=\$(printf '0x%X' \$((0x20+4*i))); V=\$(\$T/reg_rw /dev/xdma0_user \$A w 2>/dev/null | tail -1 | sed 's/.*: *//'); if [ \"\$V\" = \"0xffffffff\" ]; then echo \"NFF word\$i \$A = \$V\"; NFF=\$((NFF+1)); fi; done; echo WINDOW_SCAN_NFF=\$NFF"

echo "--- 7) restore 0x08=0 (ledger-active state) + carrier witness $(date +%s) ---"
PEER_PW="$PW" $SSH --sudo "T=$T; echo -n 'SCRATCH_0x08(before)='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1; \$T/reg_rw /dev/xdma0_user 0x08 w 0x0 >/dev/null 2>&1; echo -n 'SCRATCH_0x08(after) ='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1"
PEER_PW="$PW" $SSH --sudo "sleep 3; echo -n 'CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier; echo; ethtool enp1s0f1np1 2>/dev/null | grep -E 'Speed|Link detected'"

echo "--- 8) hard criteria (grep -q on THIS log's transcript is done by the caller too) ---"
grep -q '^ID_RC=0$' "$LOG" && echo "C1_ID_RC=PASS_LINE_PRESENT" || echo "C1_ID_RC=ABSENT"
grep -qE 'LnkSta:.*Width x4' "$LOG" && echo "C2_LNKSTA_X4=PRESENT" || echo "C2_LNKSTA_X4=ABSENT"
grep -q 'BID_0x04=.*0x00000028' "$LOG" && echo "C3_BID_0x28=PRESENT" || echo "C3_BID_0x28=ABSENT"
grep -q 'SCRATCH_0x08(after) =.*0x00000000' "$LOG" && echo "C4_0x08_ZERO=PRESENT" || echo "C4_0x08_ZERO=ABSENT"
echo "=== RESTORE_END $(date +%s.%N)"
