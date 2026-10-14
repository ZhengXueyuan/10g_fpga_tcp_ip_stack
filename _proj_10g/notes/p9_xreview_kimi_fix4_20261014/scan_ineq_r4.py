#!/usr/bin/env python
# -*- coding: utf-8 -*-
# RFC v3r3 复审(R4) - 可行性注不等号独立穷举复算
# 判据: 目标向分歧exists <=> ∃a∈[0,2^32): (a>rcv ∧ (a-rcv) mod 2^32 >= 2^31)   [修正形第一析取]
#       recipe②合法 Δ exists <=> interval [2^31, 2^32-rcv) nonempty <=> rcv < 2^31 (严格)
M32 = 0xFFFFFFFF
H = 2**31

def A_old(a, b): return int(a < b)
def B_new(a, b): return ((a - b) & M32) >> 31

RCVS = [0, 1, 0x7FFFFFFE, 0x7FFFFFFF, H, H + 1, 0xFFFFFFFE, 0xFFFFFFFF]
print("%-12s %-22s %-22s %-10s %-10s" % ("rcv_nxt", "recipe②interval[2^31,2^32-rcv)", "intervalnonempty? (<=>rcv<2^31)", "fwd-seg?", "witness"))
for rcv in RCVS:
    lo, hi = H, 2**32 - rcv
    nonempty = lo < hi
    # 前向分歧exists性(解析): a>rcv => D=a-rcv ∈ [1, 2^32-1-rcv]; 需 D>=2^31
    fwd_exists = (2**32 - 1 - rcv) >= H
    seg = None
    if fwd_exists:
        a = rcv + H                    # 最小合法 D = 2^31 (recipe②下沿)
        if a > M32:                    # 越界则取最大 a
            a = M32
        if a > rcv and ((a - rcv) & M32) >= H and A_old(a, rcv) != B_new(a, rcv):
            seg = a
    # 穷举核(双通道): 全域扫 a ∈ {0,1,2,rcv-1,rcv+1,rcv+H-1,rcv+H,rcv+H+1,M32-1,M32} ∪ 边界集
    cands = {0, 1, 2, M32 - 1, M32, rcv, (rcv + 1) & M32, (rcv - 1) & M32,
             (rcv + H) & M32, (rcv + H - 1) & M32, (rcv + H + 1) & M32,
             (rcv - H) & M32, (rcv - H - 1) & M32, H, H - 1, H + 1}
    ex = [a for a in cands if A_old(a, rcv) != B_new(a, rcv)]
    fwd_seg = [a for a in ex if a > rcv and ((a - rcv) & M32) >= H]
    assert (len(fwd_seg) > 0) == fwd_exists, "analytic-vs-brutemismatch rcv=%#x" % rcv
    assert nonempty == (rcv < H), "interval判据mismatch rcv=%#x" % rcv
    print("%-12s [2^31,%#-20x) %-22s %-10s  seg=%s" %
          (hex(rcv), hi, nonempty, fwd_exists, hex(fwd_seg[0]) if fwd_seg else "-"))
print("\nconclusion: intervalnonempty <=> 严格 rcv<2^31 ✓; rcv=2^31 时前向分歧不exists ✓ (rcv=2^31 antipode: whole-domain-equiv/agree);")
print("      theirclaim的brute-points (2^31-1 exists / 2^31 不exists) recomputed-OK ✓")
# reverse-domain可达性附带核: rcv > 2^31 时可构造反向分歧 (a<b ∧ d_mod∈(0,2^31))
for rcv in (H + 1, 0xFFFFFFFF):
    a = 0
    d = (a - rcv) & M32
    print("reverse-domainsidecheck rcv=%#x a=0: d_mod=%#x <2^31:%s 分歧:%s" %
          (rcv, d, d < H, A_old(a, rcv) != B_new(a, rcv)))
