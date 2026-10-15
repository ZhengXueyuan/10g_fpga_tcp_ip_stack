#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""记录/比对 阶段 ⑬ 目标文件的 sha256 (argv[1] = before|after)。"""
import hashlib
import importlib.util
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "arb", os.path.join(HERE, "..", "p7b_readside_bid1c_20261011", "apply_readside_bid1c.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
todo = m.stages_to_do("0x00000028")
files = sorted(set(rel for b, e, _n, _w, _u in todo for rel, _a, _b, _c in e))
tag = sys.argv[1]
lines = []
for rel in files:
    p = os.path.join(m.REPO, rel.replace("/", os.sep))
    h = hashlib.sha256(open(p, "rb").read()).hexdigest()
    lines.append("%s  %s" % (h, rel))
out = os.path.join(HERE, "TARGET_SHA_%s_BID28.txt" % tag.upper())
open(out, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
print("wrote %s (%d files)" % (os.path.basename(out), len(files)))
