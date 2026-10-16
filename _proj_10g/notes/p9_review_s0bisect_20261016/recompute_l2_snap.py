#!/usr/bin/env python
# -*- coding: utf-8 -*-
# recompute_l2_snap.py -- S-0 bisect 轮 F-1 复算：从 S0_1D_L2 原始件独立重算四个"板侧 300 s"读数
# 用法(仓根): /c/Users/zhxue/anaconda3/python.exe _proj_10g/notes/p9_review_s0bisect_20261016/recompute_l2_snap.py
# 判法: 逐样本对穷举（任何 (a,b) 样本）找声称值; 另算两套端点口径（环首→环尾 / 显式PRE→POST）
import re, os, sys
RD = "_proj_10g/notes/p9_s0bisect_board_20261016/runs/remote"
snap = os.path.join(RD, "S0_1D_L2_snap.log")
txt = open(snap, encoding="utf-8", errors="replace").read()
blocks = re.findall(r"SNAP_T ([\d.]+)\n(?:(?!SNAP_T).)*?SNAP_BEGIN \S+ gen=(\d+)\n((?:W\d+.*\n)+)SNAP_END", txt)
samples = []
for t, gen, body in blocks:
    d = {"t": float(t), "gen": int(gen)}
    for line in body.splitlines():
        m = re.match(r"(W\d+)\s+\S+\s+(\w+)\s+0x([0-9a-fA-F]+)", line)
        if m: d[m.group(1)] = int(m.group(3), 16)
    samples.append(d)
print("n samples:", len(samples), "first gen:", samples[0]["gen"], "last gen:", samples[-1]["gen"])
a, b = samples[0], samples[-1]
print("span(s): %.3f" % (b["t"] - a["t"]))
claims = {"W51": 107099940, "W20": 88914, "W55": 14951}
for w, c in claims.items():
    matches = []
    vals = [(i, s["gen"], s.get(w)) for i, s in enumerate(samples) if w in s]
    for i in range(len(vals)):
        for j in range(i + 1, len(vals)):
            if vals[j][2] - vals[i][2] == c:
                matches.append((vals[i], vals[j]))
    print(f"{w}: claim {c} | ring first->last delta = {b.get(w,0)-a.get(w,0)} | exact-pair matches = {len(matches)}")
    for m in matches[:5]: print("    ", m)
dw57 = b["W57"] - a["W57"]
print(f"W57: claim ~1.71e9 | ring first->last delta = {dw57} (max possible in-window) | ratio claim/delta = {1710000000/dw57:.1f}x")
# explicit PRE/POST from stdout (KW2 subset)
sto = open("_proj_10g/notes/p9_s0bisect_board_20261016/runs/S0_1D_L2_stdout.txt", encoding="utf-8", errors="replace").read()
pre = re.search(r"SNAP_BEGIN S0_1D_L2_PRE.*?W51\s+\S+\s+\S+\s+0x([0-9a-fA-F]+)", sto, re.S)
post = re.search(r"SNAP_BEGIN S0_1D_L2_POST.*?W51\s+\S+\s+\S+\s+0x([0-9a-fA-F]+)", sto, re.S)
pre20 = re.search(r"SNAP_BEGIN S0_1D_L2_PRE.*?W20\s+\S+\s+\S+\s+0x([0-9a-fA-F]+)", sto, re.S)
post20 = re.search(r"SNAP_BEGIN S0_1D_L2_POST.*?W20\s+\S+\s+\S+\s+0x([0-9a-fA-F]+)", sto, re.S)
print("explicit PRE->POST: dW51 =", int(post.group(1), 16) - int(pre.group(1), 16),
      " dW20 =", int(post20.group(1), 16) - int(pre20.group(1), 16))
print("claimed-value raw occurrences: 0x15B52(W20@gen1535) ->",
      [s["gen"] for s in samples if s.get("W20") == 0x15B52],
      "; 0x65E6894F(W43@gen796) ->", [s["gen"] for s in samples if s.get("W43") == 0x65E6894F],
      "=", 0x65E6894F)
