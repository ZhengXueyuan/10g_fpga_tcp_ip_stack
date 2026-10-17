#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""读侧同步的 sha256 快照 (before/after)。目标 = ⑮ 的 edit 目标文件 + 工具 + 窗口文档。"""
import hashlib
import importlib.util
import io
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
P = os.path.join(HERE, "apply_readside_bid1c__spliced.py")
spec = importlib.util.spec_from_file_location("sp", P)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.REPO = os.path.normpath(os.path.join(HERE, "..", "..", "..", ".."))

files = set(rel for rel, _a, _b, _c in m.EDITS_2A)
files.add("_proj_10g/notes/p7b_readside_bid1c_20261011/apply_readside_bid1c.py")
files.add("_proj_10g/notes/P7B_BIZ_WINDOW.md")
for rel in sorted(files):
    p = os.path.join(m.REPO, rel.replace("/", os.sep))
    h = hashlib.sha256(open(p, "rb").read()).hexdigest()
    print("%s  %s" % (h, rel))
print("# FILES=%d" % len(files))
