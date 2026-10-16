#!/usr/bin/env python3
"""make_patch.py -- produce the peer-patched arm_trickleA.sh (T3 per-sink extras).

Round: p9_p3win_trickle_board_20261017 (2026-10-17).
Instruction: "如发现脚本缺陷，改对端副本 + 把改动回传（别改本地原件）".
So: the original under p9_sink_delta_20261017/ is READ ONLY here; the patched
artifact lives in this round dir and is what gets pushed to the peer.
"""
import difflib
import os

SRC = r"D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_sink_delta_20261017\arm_trickleA.sh"
DST = r"D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_p3win_trickle_board_20261017\tools\arm_trickleA_peer_patched.sh"
DIFF = r"D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_p3win_trickle_board_20261017\tools\arm_trickleA_peer_patch.diff"

s = open(SRC, "r", newline="").read()
orig = s
BS = chr(92)  # backslash

def rep(old, new, tag):
    global s
    n = s.count(old)
    if n != 1:
        raise SystemExit("PATCH_FAIL %s count=%d" % (tag, n))
    s = s.replace(old, new)
    print("PATched %s" % tag)

# 1) declare SINK_EXTRA2
rep("SINK_EXTRA=${SINK_EXTRA-'--poll-ms 1000 --stall-n 3'}" + chr(10),
    "SINK_EXTRA=${SINK_EXTRA-'--poll-ms 1000 --stall-n 3'}" + chr(10)
    + "# --- T3 patch (2026-10-17, board round p9_p3win_trickle): per-sink extras ---" + chr(10)
    + "#   SINK_EXTRA2 = extra args for sinks 2..N (default = SINK_EXTRA => previous behaviour" + chr(10)
    + "#   byte-identical when unset).  Needed because control arm T3 must RST the SECOND sink" + chr(10)
    + "#   within ~1 s of its connect while sink 1 keeps the B4H3 verbatim args." + chr(10)
    + "SINK_EXTRA2=${SINK_EXTRA2-$SINK_EXTRA}" + chr(10),
    "declare SINK_EXTRA2")

# 2) banner echo
rep("sink_extra='$SINK_EXTRA' $(date +%s.%N)\"" + chr(10),
    "sink_extra='$SINK_EXTRA' sink_extra2='$SINK_EXTRA2' $(date +%s.%N)\"" + chr(10),
    "banner echo")

# 3) per-sink extra in the launch loop
old3 = ("  timeout -k 5 $RUN_TIMEOUT /tmp/p7b_biz/p7b_tcp_sink --host $BOARD --port 8080 " + BS + chr(10)
        + "    --rcvbuf $RCVBUF --conns $CONNS --seconds $SECS --maxbytes $MAXBYTES --check lane8 $SINK_EXTRA " + BS + chr(10)
        + "    > /tmp/k0_${TAG}_sink${i}.txt 2>&1 &" + chr(10))
new3 = ("  ex=$SINK_EXTRA; [ \"$i\" -gt 1 ] && ex=$SINK_EXTRA2   # T3 patch: per-sink extras" + chr(10)
        + "  timeout -k 5 $RUN_TIMEOUT /tmp/p7b_biz/p7b_tcp_sink --host $BOARD --port 8080 " + BS + chr(10)
        + "    --rcvbuf $RCVBUF --conns $CONNS --seconds $SECS --maxbytes $MAXBYTES --check lane8 $ex " + BS + chr(10)
        + "    > /tmp/k0_${TAG}_sink${i}.txt 2>&1 &" + chr(10))
rep(old3, new3, "launch loop")

open(DST, "w", newline="").write(s)
d = "".join(difflib.unified_diff(orig.splitlines(True), s.splitlines(True),
                                 "arm_trickleA.sh (orig, p9_sink_delta_20261017)",
                                 "arm_trickleA.sh (peer-patched, this round)", n=2))
open(DIFF, "w", newline="").write(d)
print("WROTE %s (%d bytes)" % (DST, len(s)))
print(d)
