#!/bin/bash
# burn_bit.sh <SRC_BIT_WIN_OR_UNIX> <WANT_SHA256> <TAG> -- burn one bitstream over JTAG (volatile ONLY).
#   Round p9_mdio_aplus_board_20261016. Recipes inherited from B3 burn_mdio.sh / B4 burn_0x28.sh:
#   sha gate -> copy bit+ltx into $ROUND/burn/<TAG>.{bit,ltx} -> PRE witness -> tcpreg launcher
#   (1MHz) -> five criteria -> [D-6] stdout copy. No PCIe steps here (mdio has no PCIe; the
#   0x28 restore lives in restore_0x28.sh).
#   PW discipline: PEER_PW is read once, unset, and used only as a per-command env prefix.
#   Usage: PEER_PW=<pw> bash burn_bit.sh <src.bit> <sha256> <tag>
set -u
SRC=${1:?usage: burn_bit.sh <src.bit> <sha256> <tag>}
WANT=${2:?usage: burn_bit.sh <src.bit> <sha256> <tag>}
TAG=${3:?usage: burn_bit.sh <src.bit> <sha256> <tag>}
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
LOG=$OUT/burn/BURN_${TAG}_$(date +%Y%m%d_%H%M%S).txt
exec > >(tee "$LOG") 2>&1

echo "=== BURN_BEGIN tag=$TAG $(date +%s.%N) $(date)"
echo "--- 1) sha256 + size gate on the source bit + its ltx ---"
SRC_LTX="$(dirname "$SRC")/$(basename "$(basename "$SRC" .bit)").ltx"
stat -c 'SRC %n size=%s mtime=%y' "$SRC" 2>&1
[ -f "$SRC" ] || { echo "SRC bit missing => refuse"; exit 1; }
GOT=$(sha256sum "$SRC" | cut -d' ' -f1)
echo "SHA_WANT=$WANT"
echo "SHA_GOT =$GOT"
[ "$GOT" = "$WANT" ] || { echo "SHA_MISMATCH => refuse to burn"; exit 1; }
cp -f "$SRC" "$OUT/burn/${TAG}.bit"
if [ -f "$SRC_LTX" ]; then
  cp -f "$SRC_LTX" "$OUT/burn/${TAG}.ltx"
  echo "LTX copied: $SRC_LTX -> $OUT/burn/${TAG}.ltx  ($(stat -c %s "$OUT/burn/${TAG}.ltx") B)"
else
  echo "LTX_MISSING: $SRC_LTX (VIO probes will not enumerate)"
fi
sha256sum "$OUT/burn/${TAG}.bit" "$OUT/burn/${TAG}.ltx" 2>&1
stat -c 'COPY %n size=%s mtime=%y' "$OUT/burn/${TAG}.bit"
echo "SHA_OK (source == expected; copy made)"
BIT_WIN="D:\\repo\\XCKU5PMini\\udp_hls_10g\\_proj_10g\\notes\\p9_mdio_aplus_board_20261016\\burn\\${TAG}.bit"

echo "--- 2) PRE witness (board state BEFORE this burn; mdio state -> reads fail, that is expected) ---"
PEER_PW="$PW" $SSH --sudo "T=$T; echo -n 'PRE_0x04='; \$T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1; echo -n 'PRE_0x08='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1; echo -n 'PRE_CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier 2>&1" || echo "PRE_READ_FAILED (continuing)"

echo "--- 3) burn via tcpreg launcher (JTAG 192.168.0.38:3121, 1MHz) $(date +%s) ---"
T0=$(date +%s)
TCPREG_BIT="$BIT_WIN" cmd /c "D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p7b_biz_tcpreg\run_program_tcpreg.bat" >/dev/null 2>&1
F=$ROOT/_proj_10g/notes/p7b_biz_tcpreg/tcpreg_program_stdout.txt
MT=$(stat -c %Y "$F")
echo "BURN_STDOUT=$F mtime=$MT T0=$T0 age=$((MT-T0))s"
cp "$F" "$OUT/burn/BURN_${TAG}_stdout_copy_$(date +%Y%m%d_%H%M%S).txt"
echo "--- burn stdout key lines (verbatim) ---"
grep -E "TCPREG_BIT =|TCPREG_BIT_EXISTS|TCPREG_BIT_MTIME|End of startup status|TCPREG_PROG_DONE|TCPREG-ABORT|TCPREG_PROG device" "$F"
grep -q "End of startup status: HIGH" "$F" || { echo "BURN_FAIL (no HIGH) => stop"; exit 1; }
grep -v '^#' "$F" | grep -q "TCPREG_PROG_DONE" || { echo "BURN_FAIL (no DONE) => stop"; exit 1; }
grep -q "${TAG}.bit" "$F" || { echo "BURN_FAIL (bit path mismatch) => stop"; exit 1; }
grep -v '^#' "$F" | grep -q "TCPREG-ABORT" && { echo "BURN_FAIL (TCPREG-ABORT) => stop"; exit 1; }
[ "$MT" -ge "$((T0-5))" ] || { echo "BURN_FAIL (stale stdout: this run did not execute) => stop"; exit 1; }
echo "BURN_OK (HIGH+DONE+path+freshness+noABORT five criteria)"
echo "=== BURN_END tag=$TAG $(date +%s.%N)"
