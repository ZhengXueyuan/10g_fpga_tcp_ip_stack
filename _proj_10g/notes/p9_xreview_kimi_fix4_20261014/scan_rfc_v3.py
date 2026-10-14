#!/usr/bin/env python
# -*- coding: utf-8 -*-
# RFC v3 复审 — 反纠反核扫描器（第二轮）
# 任务: (1) 复算 R1 双侧式 falsifier; (2) 验证 v3 修正形 0 falsifier;
#       (3) 验证 v3 两条注入配方的落格; (4) 验证修正形 ⟺ 真差式逐位等价.
# 纯组合代数, 与 xsim/Vivado 无关.
import random

M32 = 0xFFFFFFFF
LO, HI = -2**31, 2**31 - 1          # 等价域(真差普通整数)

def A_old(a, b):                    # 旧式绝对比较
    return int(a < b)

def B_new(a, b):                    # 新式 seq_diff[31]
    return ((a - b) & M32) >> 31

def d_mod(a, b):
    return (a - b) & M32

def truth_div(a, b):                # ground truth: 两实现是否分歧
    return A_old(a, b) != B_new(a, b)

def D_int(a, b):                    # 真差(普通整数)
    return a - b

# ---------- R1 双侧式(逐字自 _proj_10g/notes/p9_xreview_kimi_fix4_20261014/BUNDLE_RFC.md 高-1) ----------
def form_R1(a, b):
    d = d_mod(a, b)
    return (2**31 <= d < 2**32) or (a < b and 0 < d < 2**31)

# ---------- v3 修正形(逐字自 v3 §0a-10 / §3.2) ----------
def form_V3(a, b):
    d = d_mod(a, b)
    return (a > b and 2**31 <= d < 2**32) or (a < b and 0 < d < 2**31)

def form_true(a, b):                # v3 主口径(真差)
    D = D_int(a, b)
    return (D >= 2**31) or (D < LO)

def scan(pairs, form, name):
    n = f = 0
    first = None
    for a, b in pairs:
        n += 1
        if form(a, b) != truth_div(a, b):
            f += 1
            if first is None:
                first = (hex(a), hex(b), hex(d_mod(a, b)))
    print("%-46s pairs=%-8d falsifier=%-8d %s" % (name, n, f, ("first=" + str(first)) if first else ""))
    return f

# ---------- 元值集(v2 §3.2 原集, 去重) ----------
meta = {0, 1}
for k in range(0, 33):
    for v in (2**k - 1, 2**k + 1):
        if 0 <= v <= M32:
            meta.add(v)
for v in (0x7FFFFFFF, 0x80000000, 0x80000001, 0xFFFFFFFE, 0xFFFFFFFF,
          0x40000000, 0xC0000000):
    meta.add(v)
meta = sorted(meta)
print("meta set size =", len(meta), "(v2 文档称 96)")

grid = [(a, b) for a in meta for b in meta]
print("grid pairs =", len(grid), "(v3 称 9216; 台账 §10-57 称 9206)")
scan(grid, form_R1, "R1 双侧式 @ 元值网格")
scan(grid, form_V3, "v3 修正形 @ 元值网格")

# R1 falsifier 的细胞解剖: 全是 a<b ∧ d_mod∈[2^31,2^32) ?
cells = {"a>b&hi": 0, "a<b&hi": 0, "a<b&lo": 0, "eq": 0, "a>b&lo": 0}
for a, b in grid:
    d = d_mod(a, b)
    if a > b and d >= 2**31: cells["a>b&hi"] += 1
    elif a < b and d >= 2**31: cells["a<b&hi"] += 1
    elif a < b and 0 < d < 2**31: cells["a<b&lo"] += 1
    elif a == b: cells["eq"] += 1
    else: cells["a>b&lo"] += 1
print("grid cells:", cells)

random.seed(20261015)
uni = [(random.getrandbits(32), random.getrandbits(32)) for _ in range(200000)]
scan(uni, form_R1, "R1 双侧式 @ 均匀随机 200k")
scan(uni, form_V3, "v3 修正形 @ 均匀随机 200k")
scan(uni, form_true, "v3 真差式 @ 均匀随机 200k")

metasamp = [(random.choice(meta), random.choice(meta)) for _ in range(200000)]
scan(metasamp, form_R1, "R1 双侧式 @ 元值抽样 200k (复现对方口径用)")

uni2 = [(random.getrandbits(32), random.getrandbits(32)) for _ in range(2000000)]
scan(uni2, form_V3, "v3 修正形 @ 均匀随机 2M")
scan(uni2, form_true, "v3 真差式 @ 均匀随机 2M")

# 边界积集 + 边界×随机
BND = [0, 1, 2, 3, 0x7FFFFFFE, 0x7FFFFFFF, 0x80000000, 0x80000001,
       0x80000002, 0xFFFFFFFE, 0xFFFFFFFF]
scan([(a, b) for a in BND for b in BND], form_V3, "v3 修正形 @ 边界积集 11x11")
bxu = [(random.choice(BND), random.getrandbits(32)) for _ in range(200000)] + \
      [(random.getrandbits(32), random.choice(BND)) for _ in range(200000)]
scan(bxu, form_V3, "v3 修正形 @ 边界×随机 400k")

# 修正形 ⟺ 真差式 逐位等价(全部样本)
allp = grid + uni + uni2 + bxu + [(a, b) for a in BND for b in BND]
mism = sum(1 for a, b in allp if form_V3(a, b) != form_true(a, b))
print("修正形 vs 真差式 不一致对(全部 %d 对): %d" % (len(allp), mism))

# ---------- 注入配方复算(v3 §7.2) ----------
print("\n--- 配方① (减式): seq=(rcv-Δ) mod 2^32 ---")
for rcv in (0x100, 0x80000000, 0xFFFFFF00):
    for Delta in (1, 0x1000, 2**31 - 1, 2**31):
        guard = rcv < Delta
        seq = (rcv - Delta) & M32
        d = d_mod(seq, rcv)
        print("rcv=%#010x Δ=%#010x guard(rcv<Δ)=%s seq=%#010x D=%+d d_mod=%#010x old=%d new=%d -> %s" %
              (rcv, Delta, guard, seq, D_int(seq, rcv), d,
               A_old(seq, rcv), B_new(seq, rcv),
               "DIVERGE" if truth_div(seq, rcv) else "same"))
print("\n--- 配方② (加式): seq=rcv+Δ ---")
for rcv in (0x100, 0xFFFFFF00):
    for Delta in (2**31, 2**31 + 0x1000, 2**32 - rcv - 1, 2**32 - rcv, 2**32 - 1):
        in_range = (2**31 <= Delta < 2**32 - rcv)
        seq = (rcv + Delta) & M32
        d = d_mod(seq, rcv)
        print("rcv=%#010x Δ=%#010x in[2^31,2^32-rcv)=%s seq=%#010x D=%+d d_mod=%#010x old=%d new=%d -> %s" %
              (rcv, Delta, in_range, seq, D_int(seq, rcv), d,
               A_old(seq, rcv), B_new(seq, rcv),
               "DIVERGE" if truth_div(seq, rcv) else "same"))
