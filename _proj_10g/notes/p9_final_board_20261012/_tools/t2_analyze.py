#!/usr/bin/env python3
# t2_analyze.py -- P9 收尾轮 T2 (AXIS --stream + TCP 源臂) 抓取样离线独立复算
#   判据: captured[i] ^ 0xA5 == pattern[0 + i]  (TCP 路 = 每连接从偏移 0 起)
#   自检: 复用 byteorder_analyze.py 的 pattern_at, 先用 p7b_pattern.h 的两个自检向量验它
# 用法: python t2_analyze.py   (cwd = 本轮目录)
import sys, hashlib, os
sys.path.insert(0, "_tools")
from byteorder_analyze import pattern_at, self_test

XORC = 0xA5
CASES = [("T2A", 1048576), ("T2B", 1048576), ("T2C", 262144)]

ok = self_test()
print(f"SELFTEST_PASS={ok}  (FALSE ⇒ 本脚本无资格判, 下面读数全部作废)")

def fm_mism(got, exp):
    n = min(len(got), len(exp))
    for i in range(n):
        if got[i] != exp[i]:
            mism = sum(1 for k in range(i, n) if got[k] != exp[k])
            return i, mism
    if len(got) != len(exp):
        return n, abs(len(got) - len(exp))
    return -1, 0

md5s = {}
for tag, K in CASES:
    p = f"runs/mir_{tag}.bin"
    if not os.path.exists(p):
        print(f"{tag}: MISSING {p}"); continue
    got = open(p, "rb").read()
    md5s[tag] = hashlib.md5(got).hexdigest()
    if len(got) != K:
        print(f"{tag}: SIZE_MISMATCH got={len(got)} want={K}")
    exp = bytes(b ^ XORC for b in pattern_at(0, len(got)))
    fm, mism = fm_mism(got, exp)
    print(f"{tag}: pc={len(got)} md5={md5s[tag]} first_mismatch={fm} mism_bytes={mism}"
          f"  head16={got[:16].hex()}  tail16={got[-16:].hex()}")

print(f"MD5_T2A_EQ_T2B={md5s.get('T2A') == md5s.get('T2B')}  (T2A={md5s.get('T2A')} T2B={md5s.get('T2B')})")

# T2C 残拍见证: 后 8 B (k-bytes=262152 的后 8 B) 未进抓取样 ⇒ 抓取应恰为图案前 262144 B
if os.path.exists("runs/mir_T2C.bin"):
    got = open("runs/mir_T2C.bin", "rb").read()
    nxt = bytes(b ^ XORC for b in pattern_at(262144, 8))
    print(f"T2C: 抓取样尾后 8 B (图案 [262144,262152)) = {nxt.hex()} (残拍见证: 这 8 B 只进 式A)")
