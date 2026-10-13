#!/usr/bin/env python
# -*- coding: utf-8 -*-
# kx_ab_sums.py — ③ SHA256SUMS / MD5SUMS 全量自核（自写解析器；处理非标准尺寸后缀格式）
import os, re, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.join(HERE, "..", "..", "p9_uram_ab_20261014")
REPO = os.path.join(HERE, "..", "..", "..", "..")  # 仓根（sha 件用仓根相对路径）

def check_sums(path, algo):
    ok = bad = miss = 0
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.rstrip("\n")
        if not line.strip():
            continue
        if algo == "sha256":
            m = re.match(r"^([0-9a-f]{64})  (\S+?)(?:\s+\((\d+) B\))?$", line)
        else:
            m = re.match(r"^([0-9a-f]{32}) \*(\S+)$", line)
        if not m:
            print(f"  [PARSE-FAIL] {line[:80]}"); bad += 1; continue
        want, rel = m.group(1), m.group(2)
        size = m.group(3) if algo == "sha256" else None
        for cand in (os.path.join(REPO, rel), os.path.join(BASE, rel), os.path.join(BASE, os.path.basename(rel))):
            if os.path.exists(cand):
                p = cand; break
        else:
            print(f"  [MISSING] {rel}"); miss += 1; continue
        if size and os.path.getsize(p) != int(size):
            print(f"  [SIZE] {rel}: 盘上 {os.path.getsize(p)} != 标注 {size}"); bad += 1; continue
        h = hashlib.new(algo, open(p, "rb").read()).hexdigest()
        if h == want: ok += 1
        else: print(f"  [MISMATCH] {rel}"); bad += 1
    return ok, bad, miss

for fname, algo in (("SHA256SUMS.txt", "sha256"), ("MD5SUMS.txt", "md5")):
    p = os.path.join(BASE, fname)
    n = sum(1 for ln in open(p, encoding="utf-8", errors="replace") if ln.strip())
    ok, bad, miss = check_sums(p, algo)
    print(f"{fname}: 行数={n} OK={ok} BAD={bad} MISSING={miss}")
print("\n③ 附带：12/12 TOOL_MD5=48dcbcb2… 已在 kx_ab_stats.out 中逐窗核过（本件不重复）")
