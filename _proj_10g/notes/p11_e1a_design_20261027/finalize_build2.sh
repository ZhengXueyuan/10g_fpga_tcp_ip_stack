#!/bin/bash
# finalize_build2.sh -- copy 0x33 build2 reports/bit + SHA, print readings.
set -u
D=/d/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p11_e1a_design_20261027
IMPL=/d/repo/XCKU5PMini/udp_hls_10g/vivado_prj/p7b_ku5p_prj.runs/impl_1
mkdir -p "$D/bits" "$D/build2"
cp -f /d/repo/XCKU5PMini/udp_hls_10g/board/p7b_ku5p_stdout.txt "$D/build2/" 2>/dev/null || true
cp -f /d/repo/XCKU5PMini/udp_hls_10g/board/p7b_ku5p_timing.rpt  "$D/build2/" 2>/dev/null || true
cp -f /d/repo/XCKU5PMini/udp_hls_10g/board/p7b_ku5p_util.rpt    "$D/build2/" 2>/dev/null || true
cp -f /d/repo/XCKU5PMini/udp_hls_10g/board/p7b_ku5p_drc.rpt     "$D/build2/" 2>/dev/null || true
cp -f "$IMPL/wrapper_p4_timing_summary_routed.rpt" "$D/build2/" 2>/dev/null || true
cp -f "$IMPL/wrapper_p4_utilization_placed.rpt"    "$D/build2/" 2>/dev/null || true
if [ -f "$IMPL/wrapper_p4.bit" ]; then
    cp -f "$IMPL/wrapper_p4.bit" "$D/bits/wrapper_p4_0x33.bit"
    ( cd "$D/bits" && sha256sum wrapper_p4_0x33.bit > SHA256.txt )
    ls -l "$D/bits/wrapper_p4_0x33.bit"
    cat "$D/bits/SHA256.txt"
else
    echo "NO_BIT wrapper_p4.bit missing"
fi
echo "--- readings ---"
grep -E "^P11_IMPL_STRATEGY|^P7B_WNS|^P7B_WHS|^P7B_WPWS|^P7B_TIMING_GATE|^P7B_VERDICT|^P7B_BIT|^P11_STA_TCB_(A|B|C|D|E|F|A2|B2|C2|D2|E2|F2|G2|MIN) =|^P7B_SNAP_TOP5_SLOTS_OK|^P7B_SNAP_TOP5_E1A_ON" \
    /d/repo/XCKU5PMini/udp_hls_10g/board/p7b_ku5p_stdout.txt | tail -40
