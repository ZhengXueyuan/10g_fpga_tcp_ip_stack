#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""预扫 (构建轮 0x25): 目标 0x25 的搜索面 (旧值族 = 0x1A/0x1C..0x24 + 三个命名族) 在
**非忽略文件集**里的命中, 按"EDITS 目标 / ALLOW 分类 / 未登记"分。
⚠️ 只读: 不改仓内任何文件; 只打印。
"""
import importlib.util, os, re, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "arb", os.path.join(HERE, "..", "p7b_readside_bid1c_20261011", "apply_readside_bid1c.py"))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
# 0x24 尚未进 HISTORY_BIDS (splice 前) ⇒ 补上, 让 families_for 造出目标 0x25 的完整旧值族
m.HISTORY_BIDS = list(m.HISTORY_BIDS) + ["0x00000024"]
fams = m.families_for("0x00000025")
tgts = set(rel for st in m.chain_for("0x00000024") for rel, _a, _w, _c in st[1])
ext = (".sh", ".bat", ".py", ".v", ".vh", ".tcl", ".ps1", ".cmd")
rows = []
for fam, rx in fams:
    for rel in m._fileset():
        if not rel.endswith(ext):
            continue
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
        cls = "EDITS 目标" if rel in tgts else None
        if cls is None:
            for pat, c in m.ALLOW:
                if re.search(pat, rel):
                    cls = "ALLOW: " + c[:44]
                    break
        rows.append((fam, rel, cls or "**未登记**"))
seen = set()
for fam, rel, cls in sorted(rows):
    if (rel, cls) in seen:
        continue
    seen.add((rel, cls))
    print("%-30s | %-74s | %s" % (fam, rel, cls))
unreg = sorted(set(r[1] for r in rows if r[2] == "**未登记**"))
print("命中 %d 行 (%d 文件) · **未登记 %d 文件**" % (len(rows), len(set(r[1] for r in rows)), len(unreg)))
for r in unreg:
    print("UNREG %s" % r)
