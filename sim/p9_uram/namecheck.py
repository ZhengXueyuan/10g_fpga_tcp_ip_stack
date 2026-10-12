#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""namecheck.py -- F5 guard for the p9_uram unit gate (2026-10-13 review round).

Every `[PASS]` / `[FAIL]` line in the xsim log must carry a **visible criterion ID**
(= the line must contain "] G...").  Rationale: the TB passes names through an
`input [255:0] name` port (32 bytes); xsim keeps the LAST 32 characters and drops the
rest => a name longer than 32 chars loses its ID prefix and the log line starts with
"] " + tail-of-name (auditors can no longer match value <-> ID).

exit codes:  0 = all verdict lines carry an ID
             2 = at least one verdict line lost its ID (truncation)
             1 = log missing / no verdict lines (infrastructure)

(Why python and not a `findstr | find /c` pipe: the cmd `for /f ('... ^| ...')` pipe
idiom hung in an observed run -- find.exe sat waiting on the console.  A tiny script
file avoids the cmd quoting/pipe minefield entirely.)
"""
from __future__ import print_function
import io, sys

def main():
    p = sys.argv[1] if len(sys.argv) > 1 else "xsim.log"
    try:
        lines = io.open(p, encoding="utf-8", errors="replace").read().splitlines()
    except IOError:
        print("NAME-CHECK: log not found: %s" % p)
        return 1
    pf  = [l for l in lines if ("[PASS]" in l) or ("[FAIL]" in l)]
    gid = [l for l in pf if "] G" in l]
    print("NAME-CHECK: verdict_lines=%d with_visible_id=%d" % (len(pf), len(gid)))
    if len(pf) == 0:
        print("NAME-CHECK: no verdict lines at all")
        return 1
    if len(pf) != len(gid):
        for l in pf:
            if "] G" not in l:
                print("NAME-CHECK MISSING-ID: %s" % l)
        return 2
    return 0

if __name__ == "__main__":
    sys.exit(main())
