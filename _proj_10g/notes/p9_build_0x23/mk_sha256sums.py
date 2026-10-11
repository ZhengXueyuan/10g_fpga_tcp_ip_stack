#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成本目录 SHA256SUMS.txt (递归; 排除自身与 __pycache__; 按相对路径排序)。"""
import hashlib
import os

D = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(D, "SHA256SUMS.txt")
rows = []
for root, dirs, files in os.walk(D):
    dirs[:] = [x for x in dirs if x != "__pycache__"]
    for f in files:
        p = os.path.join(root, f)
        rel = os.path.relpath(p, D).replace(os.sep, "/")
        if rel == "SHA256SUMS.txt":
            continue
        h = hashlib.sha256(open(p, "rb").read()).hexdigest()
        rows.append("%s *%s" % (h, rel))
rows.sort(key=lambda s: s.split(" *", 1)[1])
with open(OUT, "w", newline="\n") as fh:
    fh.write("\n".join(rows) + "\n")
print("SHA256SUMS.txt: %d 件" % len(rows))
