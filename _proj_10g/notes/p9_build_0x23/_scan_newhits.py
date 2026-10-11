#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""预扫: 8 位旧值 0x00000022 在**非忽略文件集**里的命中, 按"EDITS 目标 / ALLOW 分类 / 未登记"分。"""
import importlib.util, os, re, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("arb", os.path.join(HERE, "..", "p7b_readside_bid1c_20261011", "apply_readside_bid1c.py"))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
rx = re.compile(r"(?:0[xX]|32'[hH])0{6}22\b")
tgts = set(rel for st in m.chain_for("0x00000022") for rel, _a, _w, _c in st[1])
rows = []
for rel in m._fileset():
    p = os.path.join(m.REPO, rel.replace("/", os.sep))
    try:
        b = open(p, "rb").read()
    except OSError:
        continue
    if b"\x00" in b[:4096] or len(b) > 4*1024*1024:
        continue
    t = m._strip_comment_lines(b.decode("utf-8", "replace"))
    if not rx.search(t):
        continue
    cls = "EDITS_22 目标" if rel in tgts else None
    if cls is None:
        for pat, c in m.ALLOW:
            if re.search(pat, rel):
                cls = "ALLOW: " + c[:40]
                break
    rows.append((rel, cls or "**未登记**"))
for rel, cls in sorted(rows):
    print("%-78s | %s" % (rel, cls))
print("命中 %d 文件 (%d 未登记)" % (len(rows), sum(1 for _, c in rows if c == "**未登记**")))
