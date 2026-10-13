#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""诊断: w70 列 (原始采样) vs dw70 列 (工具打印的区间增量) 逐步对比。
目的: 决定洞检测用哪一列。"""
import re
import sys
import glob

RL = re.compile(r"READLOG i=(\d+) t=([\d.]+) \S+ \S+ \S+ got=(\d+) pc=(\d+) w70=(\d+) dw70=(\d+)")

def load(f):
    rows = []
    for m in RL.finditer(open(f, encoding="utf-8", errors="replace").read()):
        g = m.groups()
        rows.append((int(g[0]), float(g[1]), int(g[2]), int(g[3]), int(g[4]), int(g[5])))
    return rows

for f in sys.argv[1:]:
    rows = sorted(load(f), key=lambda r: r[1])
    print(f"== {f.split('/')[-1]}  n={len(rows)}")
    # 累积对比
    cum_printed = 0
    mism = 0
    maxdiff = 0
    # 逐步: my_delta[j] vs printed[j]
    detail = []
    for j in range(1, len(rows)):
        my = rows[j][4] - rows[j - 1][4]
        pr = rows[j][5]
        if my != pr:
            mism += 1
            detail.append((rows[j][0], rows[j][1], rows[j - 1][4], rows[j][4], my, pr))
    print(f"   逐行不一致数 = {mism} / {len(rows)-1}")
    for d in detail[:12]:
        print(f"     i={d[0]:>3} t={d[1]:.4f} w70_prev={d[2]:>9} w70={d[3]:>9} myΔ={d[4]:>8} printed={d[5]:>8}")
    if len(detail) > 12:
        print(f"     ... (共 {len(detail)} 行, 只列前 12)")
    # 检查 printed 是否可能 = 上一行的 myΔ (移位)
    shifted_ok = sum(1 for j in range(2, len(rows))
                     if rows[j][5] == rows[j - 1][4] - rows[j - 2][4] and rows[j][4] - rows[j - 1][4] != rows[j][5])
    print(f"   printed[j] == myΔ[j-1] 的移位命中数 = {shifted_ok}")
    # 首行与尾差
    print(f"   首行 w70={rows[0][4]}  末行 w70={rows[-1][4]}  Σprinted={sum(r[5] for r in rows)}")
