#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成本目录 SHA256SUMS.txt (递归; 跳过 __pycache__ 与自身)。"""
import hashlib
import io
import os

ROOT = os.path.dirname(os.path.abspath(__file__))
os.chdir(ROOT)
files = []
for dirpath, dirs, fns in os.walk("."):
    dirs[:] = [d for d in dirs if d != "__pycache__"]
    for f in fns:
        rel = os.path.relpath(os.path.join(dirpath, f), ".").replace(os.sep, "/")
        if rel == "SHA256SUMS.txt":
            continue
        files.append(rel)
files.sort()
with io.open("SHA256SUMS.txt", "w", encoding="ascii", newline="\n") as out:
    for rel in files:
        h = hashlib.sha256(open(rel, "rb").read()).hexdigest()
        out.write("%s *%s\n" % (h, rel))
print("files", len(files))
