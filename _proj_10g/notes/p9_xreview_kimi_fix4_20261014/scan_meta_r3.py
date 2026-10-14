#!/usr/bin/env python
# -*- coding: utf-8 -*-
# RFC v3r2 复审(R3) — 元值集可复现构造核验 + 全网格复算 + assert 牙测
# 构造代码逐字复制自 v3r2 §3.2(提交 d77ed02 版)
import random

M32 = 0xFFFFFFFF
LO = -2**31

def A_old(a, b): return int(a < b)
def B_new(a, b): return ((a - b) & M32) >> 31
def d_mod(a, b): return (a - b) & M32
def truth_div(a, b): return A_old(a, b) != B_new(a, b)
def form_R1(a, b):   # 我方 R1 双侧式(第一析取缺 a>b)
    d = d_mod(a, b)
    return (2**31 <= d < 2**32) or (a < b and 0 < d < 2**31)
def form_V3(a, b):   # v3 修正形
    d = d_mod(a, b)
    return (a > b and 2**31 <= d < 2**32) or (a < b and 0 < d < 2**31)

# ===== 1. 对方构造(逐字) =====
def build(ddset=(-1, 0, 1), extra=True):
    M = 1 << 32
    vals = set()
    for k in range(33):                # k = 0..32
        for dd in ddset:               # 含 2^k 本身(v3r2 声称旧描述漏的就是它)
            v = (1 << k) + dd
            if 0 <= v < M:
                vals.add(v)
    if extra:
        vals |= {0, 1, 2, 0x7FFFFFFF, 0x80000000, 0x80000001,
                 0xFFFFFFFE, 0xFFFFFFFF, 0x40000000, 0xC0000000}
    return vals

vals = build()
print("[1] 对方构造(dd=-1,0,1 + extras): len=%d (声称 96)  min=%d max=%#x" %
      (len(vals), min(vals), max(vals)))
assert len(vals) == 96, "len!=96"
pairs = [(a, b) for a in sorted(vals) for b in sorted(vals)]
print("    pairs=%d (声称 9216)" % len(pairs))
assert len(pairs) == 9216

# ===== 2. 全网格复算 =====
fR1 = sum(1 for a, b in pairs if form_R1(a, b) != truth_div(a, b))
fV3 = sum(1 for a, b in pairs if form_V3(a, b) != truth_div(a, b))
fLem = sum(1 for a, b in pairs
           if ((A_old(a, b) == B_new(a, b)) != (LO <= a - b <= 2**31 - 1)))
print("[2] 96x96 网格: R1式 falsifier=%d (对方称 4291)  v3修正形=%d  等价引理=%d"
      % (fR1, fV3, fLem))

# ===== 3. assert 牙测 =====
def teeth(name, fn):
    try:
        v = fn()
        assert v == 96, "%s: len=%d (期望 96) -> 断言未触发, 牙测 FAIL" % (name, v)
        print("[3] %s: len=%d -> 断言已触发(红) 牙测 PASS" % (name, v))
        return True
    except AssertionError as e:
        print("[3] %s: 断言触发(红) -> 牙测 PASS (%s)" % (name, str(e)[:60]))
        return True

# 3a. 抽掉 dd=0 (= 我方 R2 的字面构造) -> len 应为 68, assert 必须红
v2 = build(ddset=(-1, 1))
print("[3a] dd=±1 only (= R2 字面): len=%d (R2 实测 68; assert 现在必须红)" % len(v2))
try:
    assert len(v2) == 96
    print("     -> 断言未触发: FAIL(牙掉了)")
except AssertionError:
    print("     -> AssertionError 已触发: 牙 PASS")
# 3b. 抽掉 0xC0000000 -> len=95, assert 必须红
v3 = build(extra=False) | {0, 1, 2, 0x7FFFFFFF, 0x80000000, 0x80000001,
                           0xFFFFFFFE, 0xFFFFFFFF, 0x40000000}  # 漏 0xC0000000
print("[3b] 漏 0xC0000000: len=%d" % len(v3))
try:
    assert len(v3) == 96
    print("     -> 断言未触发: FAIL")
except AssertionError:
    print("     -> AssertionError 已触发: 牙 PASS")

# ===== 4. 等价引理在 dd=±1-only 68 集上(回应"v3r2 声称两种复算结论不变") =====
p68 = [(a, b) for a in sorted(v2) for b in sorted(v2)]
f68 = sum(1 for a, b in p68 if form_R1(a, b) != truth_div(a, b))
fV68 = sum(1 for a, b in p68 if form_V3(a, b) != truth_div(a, b))
print("[4] 68x68(R2 字面集): R1式=%d (R2 实测 2093)  v3修正形=%d" % (f68, fV68))

# ===== 5. R1 式在 96 网格的 falsifier 细胞解剖(应为 a<b & hi 一胞) =====
cells = {}
for a, b in pairs:
    if form_R1(a, b) != truth_div(a, b):
        key = "a>b" if a > b else ("a<b" if a < b else "eq")
        d = d_mod(a, b)
        key += "&hi" if d >= 2**31 else "&lo"
        cells[key] = cells.get(key, 0) + 1
print("[5] R1式 falsifier 细胞:", cells)
