#!/usr/bin/env python
# -*- coding: utf-8 -*-
# kx_holes.py — 独立复算 0x24 内容臂 CAPD24 洞结构（自写 LFSR + 自写解析；不 import 对方 _tools）
# 口径: 镜流 = pattern(OFF + 绝对位置) ^ 0xA5 ; OFF = 1076295680 (WIN_CAPD24 OFF_AUTO)
# 假设形态: 洞 = 单次连续删除 L (洞起点之后整体位移 +L; 位移量沿流累积)
import os

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "p9_board_0x24_20261013")
RUNS = os.path.join(BASE, "runs")
OFF = 1076295680          # CAPD24 --pat-off
SEED = 0x9E3779B97F4A7C15
MASK = (1 << 64) - 1

def xs_next(s):
    s ^= (s << 13) & MASK
    s ^= s >> 7
    s ^= (s << 17) & MASK
    return s

# ---- GF(2) 矩阵快速跳跃（自写；列 = 基向量像）----
def mat_gen():
    return [xs_next(1 << i) for i in range(64)]

def mat_apply(cols, x):
    r = 0
    i = 0
    while x:
        if x & 1:
            r ^= cols[i]
        x >>= 1
        i += 1
    return r

def mat_compose(A, B):           # A∘B
    return [mat_apply(A, b) for b in B]

def jump(off):
    """返回从 SEED 前进 off 步后的状态"""
    M = mat_gen()
    s = SEED
    n = off
    while n:
        if n & 1:
            s = mat_apply(M, s)
        n >>= 1
        if n:
            M = mat_compose(M, M)
    return s

def pat_bytes(off, n):
    """pattern 字节 [off, off+n)（不 ^0xA5）"""
    s = jump(off)
    out = bytearray(n)
    for i in range(n):
        out[i] = (s >> 24) & 0xFF
        s = xs_next(s)
    return bytes(out)

def mir(off, n):
    return bytes(b ^ 0xA5 for b in pat_bytes(off, n))

def fm_and_count(got, exp):
    assert len(got) == len(exp)
    fm = -1; mism = 0
    for i in range(len(got)):
        if got[i] != exp[i]:
            if fm < 0: fm = i
            mism += 1
    return fm, mism

def load(name):
    return open(os.path.join(RUNS, name), "rb").read()

# ============== 0. 图案自检 ==============
v0 = pat_bytes(0, 16)
v1 = pat_bytes(1460, 8)
st100 = jump(100)
print("SELFTEST off0_15   ", v0.hex(), "expect 7f0b02e536a14ed61ab049b856add63f", "OK" if v0.hex() == "7f0b02e536a14ed61ab049b856add63f" else "FAIL")
print("SELFTEST off1460_67", v1.hex(), "expect 0300422d9b47cac0", "OK" if v1.hex() == "0300422d9b47cac0" else "FAIL")
print("SELFTEST state@100 = %016X expect AB5917A81F0FB2AE" % st100, "OK" if st100 == 0xAB5917A81F0FB2AE else "FAIL")

# ============== 1. head @0 64 KiB 无位移 ==============
head = load("capd_head.bin")
fm, c = fm_and_count(head, mir(OFF, len(head)))
print(f"[head @0 +{len(head)}] 无位移: fm={fm} mism={c}  (报告/ANALYZE: fm=-1 mism=0)")

# ============== 2. sliceA @3,180,632 4 MiB ==============
SL = 3180632
sl = load("capd_sliceA.bin")
assert len(sl) == 4194304
FM_CLAIM = 4229208
pos = FM_CLAIM - SL
exp_pre = mir(OFF + SL, pos)
fm, c = fm_and_count(sl[:pos], exp_pre)
print(f"[sliceA 洞前区 {SL}:{FM_CLAIM}) 无位移: fm={fm} mism={c}")

# L 搜索 (16B 窗口, 候选空间 0..262144)
buf = mir(OFF + FM_CLAIM, 262144 + (len(sl) - pos) + 32)
win = sl[pos:pos + 16]
cands = [L for L in range(0, 262144 + 1) if buf[L:L + 16] == win]
print(f"[sliceA L 搜索] 16B 窗口候选 = {cands} (ANALYZE: [39608] 共 1)")
L = cands[0]
n64 = min(len(sl) - pos, 65536)
ok64 = sl[pos:pos + n64] == buf[L:L + n64]
print(f"[sliceA L={L}] 首候选 64 KiB 全过: {ok64}")
rest = len(sl) - pos
fm2, c2 = fm_and_count(sl[pos:], buf[L:L + rest])
print(f"[sliceA 洞后区 {FM_CLAIM}:+{rest}) 位移 L={L}: fm={fm2}(切片内) mism={c2}")
# 边界 dump
print(f"GOT[{FM_CLAIM-16}:{FM_CLAIM}] = {sl[pos-16:pos].hex()}")
print(f"EXP[{FM_CLAIM-16}:{FM_CLAIM}] = {mir(OFF+FM_CLAIM-16,16).hex()}")
print(f"GOT[{FM_CLAIM}:{FM_CLAIM+16}] = {sl[pos:pos+16].hex()}")
print(f"EXP_noShift            = {mir(OFF+FM_CLAIM,16).hex()}")
print(f"EXP_shift{L}            = {buf[L:L+16].hex()}")

# ============== 3. 相位判定 ==============
print("\n[相位] 4 个洞起点 mod 4 MiB:")
for hp in (4229208, 16812120, 67143768, 201361496):
    print(f"  {hp} = {hp // 4194304}×4MiB + {hp % 4194304}  (相位断言 = 34904)")

# ============== 4. 各探针 (累积位移 S) ==============
# 方向（本复算实测确认）: 抓取位置 c 对应图案位置 OFF + c + S （洞=删除 ⇒ 内容左移 ⇒ +S 查图案）
def probe(name, P, S_claim, hole_at=None, hole_L=None):
    got = load(name)
    exp = mir(OFF + P + S_claim, len(got))
    fm, c = fm_and_count(got, exp)
    print(f"[{name} @{P} S={S_claim}] 全片对账(+S): fm={fm} mism={c} (len={len(got)})")
    if hole_at is not None:
        rel = hole_at - P
        expa = mir(OFF + P + S_claim, rel)
        fma, ca = fm_and_count(got[:rel], expa)
        print(f"    洞前 [0,{rel}): fm={fma} mism={ca}  (期望 -1/0)")
        if hole_L is not None:
            Spost = S_claim + hole_L
            rest = len(got) - (rel + hole_L)
            expb = mir(OFF + P + rel + hole_L + Spost, rest)
            fmb, cb = fm_and_count(got[rel + hole_L:], expb)
            print(f"    洞后 [{rel}+{hole_L}:end) 位移 S+{hole_L}={Spost}: fm={fmb} mism={cb}  (期望 -1/0)")

print()
probe("capd_p16777216.bin", 16777216, 61992, hole_at=16812120, hole_L=None)
probe("capd_p16Mw.bin",     16807216, 61992, hole_at=16812120, hole_L=2368)
probe("capd_p67108864.bin", 67108864, 171944, hole_at=67143768, hole_L=None)
probe("capd_p134217728.bin",134217728, 372648)
probe("capd_p201326592.bin",201326592, 604840, hole_at=201361496, hole_L=None)
probe("capd_p80M1.bin",     85983232, 228632)

# ============== 5. tail @263,192,576 ==============
tail = load("capd_tail.bin")
T = 263192576
S_tail = 759488
fm, c = fm_and_count(tail, mir(OFF + T + S_tail, len(tail)))
print(f"\n[tail @{T} S={S_tail}] 对账(+S): fm={fm} mism={c} (ANALYZE 尾区位移 759488 期望 -1/0)")
fm, c = fm_and_count(tail, mir(OFF + T + 39608, len(tail)))
print(f"[tail @{T} S=39608(错值对照)] 对账(+S): fm={fm} mism={c} (ANALYZE 用 L=39608: fm=0 mism=4193473)")

# ============== 6. 账: S(251MiB) vs ΔW70 ==============
print(f"\n[账] S(251MiB)=759488 vs ΔW70=769704: 差 = {769704 - 759488} (报告: 末段未捕获 10216)")
