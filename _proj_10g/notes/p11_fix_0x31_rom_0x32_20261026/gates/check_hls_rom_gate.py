#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_hls_rom_gate.py -- pattern-level control for P7B_HLS_ROM_LOG_GATE.

The gate itself lives in board/build_p7b_ku5p.tcl (Tcl, post-synth).
This script proves the SAME regex has teeth on the archived 0x31 log and
does not fire on the 0x32 log:

  0x31: 3x Synth 8-4445 + 3x rom0 no-driver  -> hits > 0  (negative control)
  0x32: 0                                      -> hits == 0 (positive control)

It is NOT a substitute for the build-time gate; it is the archived-log bridge.
Exit 0 only when both controls hold.
"""
import os
import re
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", ".."))
RX = re.compile(r"8-4445|could not open \$readmem|rom0.*does not have driver", re.I)


def hits(path):
    if not os.path.exists(path):
        print("MISSING %s" % path)
        return -1, []
    out = []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for ln, line in enumerate(f, 1):
            # The build stdout echoes the Tcl source (lines starting with '#');
            # they are not synthesis output.  The real gate reads synth_1/runme.log.
            if line.lstrip().startswith("#"):
                continue
            if RX.search(line):
                out.append((ln, line.rstrip()))
    return len(out), out


def read_ok(path):
    if not os.path.exists(path):
        return -1
    n = 0
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.lstrip().startswith("#"):
                continue
            if re.search(r"8-3876.*read successfully", line, re.I):
                n += 1
    return n


def main():
    bad = os.path.join(REPO, "_proj_10g", "notes", "p11_fix_0x30_0x31_20261025",
                       "build0x31_clean", "p7b_ku5p_stdout.txt")
    good = os.path.join(REPO, "_proj_10g", "notes", "p11_fix_0x31_rom_0x32_20261026",
                        "build0x32", "P7B_STDOUT.txt")
    n_bad, h_bad = hits(bad)
    n_good, h_good = hits(good)
    r_bad = read_ok(bad)
    r_good = read_ok(good)
    print("0x31 hits = %d (expect > 0); 8-3876 reads = %d (expect 0)" % (n_bad, r_bad))
    for ln, line in h_bad[:10]:
        print("  HIT %d: %s" % (ln, line[:180]))
    print("0x32 hits = %d (expect 0); 8-3876 reads = %d (expect 3)" % (n_good, r_good))
    for ln, line in h_good[:10]:
        print("  HIT %d: %s" % (ln, line[:180]))
    ok = (n_bad > 0) and (n_good == 0) and (r_bad == 0) and (r_good == 3)
    print("HLS_ROM_GATE_CONTROL = %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
