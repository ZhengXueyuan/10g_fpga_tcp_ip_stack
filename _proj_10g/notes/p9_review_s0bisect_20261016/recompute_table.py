#!/usr/bin/env python
# -*- coding: utf-8 -*-
# recompute_table.py -- S-0 bisect 轮 逐跑判决独立复算（主源 = runs/remote/*_sink.txt），逐行对 TABLE.txt
# 用法(仓根): /c/Users/zhxue/anaconda3/python.exe _proj_10g/notes/p9_review_s0bisect_20261016/recompute_table.py
import re
RD = "_proj_10g/notes/p9_s0bisect_board_20261016"
tags = ["S0_1A","S0_1A_L","S0_1C_L","S0_1C_L2","S0_1C_B","S0_1D_L","S0_1D_L2","S0_1D_L3","S0_1F_L","S0_24_L"]
rows = {}
for line in open(f"{RD}/runs/TABLE.txt", encoding="utf-8", errors="replace"):
    p = line.split()
    if len(p) > 8 and re.match(r"^S0_", p[0]): rows[p[0]] = p
bad = 0
for t in tags:
    s = open(f"{RD}/runs/remote/{t}_sink.txt", encoding="utf-8", errors="replace").read()
    conns = stall = phase = clean = 0
    for m in re.finditer(r"^SINK_CONN (\d+) (\w+).*?bytes=(\d+) first_mismatch=(-?\d+) mism_bytes=(\d+)", s, re.M):
        ok, by, fm, mm = m.group(2), int(m.group(3)), int(m.group(4)), int(m.group(5))
        conns += 1
        if ok == "STALL": stall += 1
        if fm == 0 and mm > by * 250 // 256: phase += 1   # mk_table.py:26 实现口径
        if fm == -1 and mm == 0 and ok == "OK": clean += 1
    mm_ = re.search(r"SINK_SUM.*?agg_Mbps=([\d.]+)", s, re.S)
    agg = mm_.group(1) if mm_ else "-"
    r = rows[t]; claim = (r[3], r[4], r[5], r[6], r[7])
    got = (str(conns), str(stall), str(phase), str(clean), agg)
    match = "OK" if claim == got else "<<< MISMATCH"
    if match != "OK": bad += 1
    print(f"{t:10s} got {got} | TABLE {claim} {match}")
# 相位错算术逐条（文档口径 mism ~= bytes - bytes/256）
print("--- phase arithmetic (documented criterion) ---")
for t in tags:
    s = open(f"{RD}/runs/remote/{t}_sink.txt", encoding="utf-8", errors="replace").read()
    for m in re.finditer(r"^SINK_CONN (\d+) (\w+).*?bytes=(\d+) first_mismatch=(-?\d+) mism_bytes=(\d+)", s, re.M):
        by, fm, mm = int(m.group(3)), int(m.group(4)), int(m.group(5))
        if fm == 0:
            pred = by - by / 256.0
            if mm > by * 250 // 256:
                print(f"  {t} conn{m.group(1)}: bytes={by} mism={mm} |d|={abs(pred-mm):.2f}")
print("total mismatches:", bad)
