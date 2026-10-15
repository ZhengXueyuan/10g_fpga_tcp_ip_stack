#!/bin/bash
# burn_mdio.sh -- B3: burn the freshly built MDIO VIO bitstream over JTAG (volatile ONLY).
#   Usage: PEER_PW=<pw> bash burn_mdio.sh <WANT_SHA256> <WANT_SIZE_BYTES>
#   Recipes inherited from notes/p9_board_rfcseq_20261015/burn_arm.sh (B1/B2 audited path):
#   sha256 triple gate / tcpreg launcher (1MHz) / five criteria / [D-6] stdout copy.
#   NOTE: mdio design has NO PCIe -> no remove/rescan here (design v2r2 sec 4.1).
set -u
WANT=${1:?usage: burn_mdio.sh <sha256> <size>}
SZ_WANT=${2:?usage: burn_mdio.sh <sha256> <size>}
ROOT=/d/repo/XCKU5PMini/udp_hls_10g
ROOTW=D:/repo/XCKU5PMini/udp_hls_10g
OUT=$ROOT/_proj_10g/notes/p9_mdio_board_20261015
export MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8
PY=/c/Users/zhxue/anaconda3/python.exe
SSH="$PY $ROOTW/tools/peer_ssh.py"
T=/home/a/xdma_test/dma_ip_drivers-patched/XDMA/linux-kernel/tools
SRC_BIT=D:/repo/XCKU5PMini/_proj_mdio/pj_mdio/mdio_prj.runs/impl_1/mdio_vio_top.bit
SRC_LTX=D:/repo/XCKU5PMini/_proj_mdio/pj_mdio/mdio_prj.runs/impl_1/mdio_vio_top.ltx
[ -n "${PEER_PW:-}" ] || { echo "FATAL: PEER_PW required"; exit 3; }
mkdir -p "$OUT/burn" "$OUT/board/artifacts"
exec > >(tee "$OUT/burn/BURN_mdio_$(date +%Y%m%d_%H%M%S).txt") 2>&1

echo "=== BURN_MDIO_BEGIN $(date +%s.%N) $(date)"
echo "--- 1) bit/ltx sha256 + size gate ---"
stat -c 'SRC %n size=%s mtime=%y' "$SRC_BIT" "$SRC_LTX"
[ -f "$SRC_BIT" ] || { echo "BIT missing"; exit 1; }
[ -f "$SRC_LTX" ] || { echo "LTX missing"; exit 1; }
GOT=$(sha256sum "$SRC_BIT" | cut -d' ' -f1)
SZ=$(stat -c %s "$SRC_BIT")
echo "SHA_WANT=$WANT"; echo "SHA_GOT =$GOT"; echo "SZ_WANT=$SZ_WANT SZ_GOT=$SZ"
[ "$GOT" = "$WANT" ] || { echo "SHA_MISMATCH => refuse to burn"; exit 1; }
[ "$SZ" = "$SZ_WANT" ] || { echo "SIZE_MISMATCH => refuse to burn"; exit 1; }
cp -f "$SRC_BIT" "$OUT/board/artifacts/mdio_vio_top.bit"
cp -f "$SRC_LTX" "$OUT/board/artifacts/mdio_vio_top.ltx"
sha256sum "$OUT/board/artifacts/mdio_vio_top.bit" "$OUT/board/artifacts/mdio_vio_top.ltx"
echo "SHA_OK (report anchor + size)"
BIT_WIN="D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_mdio_board_20261015\board\artifacts\mdio_vio_top.bit"

echo "--- 2) PRE witness: board state BEFORE the mdio burn (expect 0x04=0x27, 0x08=0x0) ---"
$SSH --sudo "T=$T; echo -n 'PRE_0x04='; \$T/reg_rw /dev/xdma0_user 0x04 w 2>&1 | tail -1; echo -n 'PRE_0x08='; \$T/reg_rw /dev/xdma0_user 0x08 w 2>&1 | tail -1; echo -n 'PRE_CARRIER='; cat /sys/class/net/enp1s0f1np1/carrier" || echo "PRE_READ_FAILED (continuing)"

echo "--- 3) burn via tcpreg launcher (JTAG, 1MHz) $(date +%s) ---"
T0=$(date +%s)
TCPREG_BIT="$BIT_WIN" cmd /c "D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p7b_biz_tcpreg\run_program_tcpreg.bat" >/dev/null 2>&1
F=$ROOT/_proj_10g/notes/p7b_biz_tcpreg/tcpreg_program_stdout.txt
MT=$(stat -c %Y "$F")
echo "BURN_STDOUT=$F mtime=$MT T0=$T0 age=$((MT-T0))s"
cp "$F" "$OUT/burn/BURN_mdio_stdout_copy_$(date +%Y%m%d_%H%M%S).txt"
grep -E "TCPREG_BIT =|End of startup status|TCPREG_PROG_DONE|TCPREG-ABORT|TCPREG_PROG device" "$F"
grep -q "End of startup status: HIGH" "$F" || { echo "BURN_FAIL (no HIGH)"; exit 1; }
grep -v '^#' "$F" | grep -q "TCPREG_PROG_DONE" || { echo "BURN_FAIL (no DONE)"; exit 1; }
grep -q "mdio_vio_top.bit" "$F" || { echo "BURN_FAIL (bit path mismatch)"; exit 1; }
grep -v '^#' "$F" | grep -q "TCPREG-ABORT" && { echo "BURN_FAIL (TCPREG-ABORT)"; exit 1; }
[ "$MT" -ge "$((T0-5))" ] || { echo "BURN_FAIL (stale stdout)"; exit 1; }
echo "BURN_OK (HIGH+DONE+path+freshness+noABORT)"
echo "=== BURN_MDIO_END $(date +%s.%N)"
