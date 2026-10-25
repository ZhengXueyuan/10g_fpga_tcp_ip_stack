#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_build_dat_pattern.py — static check for the 0x31 HLS .dat bug.

Fails if any board/*.tcl still contains the old `imports/verilog/udp_echo.v`
fallback (the `file dirname ""` => "." bug), or if the robust pattern is
missing.  This is a source-level gate; it does NOT run Vivado.
"""
import glob
import os
import re
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", ".."))
old_rx = re.compile(r"set\s+src_dir\s+\[file\s+dirname\s+\[lindex\s+\[glob\s+-nocomplain\s+\$\{root_dir\}/vivado_prj/\$\{project_name\}\.srcs/sources_1/imports/verilog/udp_echo\.v\]")
robust = "HLS_IMPORT_DIR_HITS"
files = sorted(glob.glob(os.path.join(REPO, "board", "*.tcl")))
bad, good = [], []
for p in files:
    s = open(p, "r", encoding="utf-8", errors="replace").read()
    hits = [i + 1 for i, line in enumerate(s.splitlines())
            if old_rx.search(line) and not line.lstrip().startswith("#")]
    if hits:
        bad.append((os.path.basename(p), hits))
    if robust in s:
        good.append(os.path.basename(p))
print("BOARD_TCL_FILES = %d" % len(files))
print("OLD_PATTERN_HITS = %s" % (bad if bad else "none"))
print("ROBUST_FILES = %d %s" % (len(good), good))
ok = (not bad) and len(good) >= 12
print("BUILD_DAT_PATTERN_GATE = %s" % ("PASS" if ok else "FAIL"))
sys.exit(0 if ok else 1)
