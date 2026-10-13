#!/usr/bin/env python3
# shift_scan.py -- 0x24 内容臂: 各探针切片求"至该点累计删除位移" S(P)
#   口径: got(P+i) == 图案(OFF + P + i + S(P)) ^ 0xA5; S 单调不减 => 跳变处即洞位置区间
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pattern_jump import pattern_at, self_test

OFF = 1076295680
SMAX = 1500000
PROBES = [
    (16777216, "runs/capd_p16777216.bin"),
    (67108864, "runs/capd_p67108864.bin"),
    (134217728, "runs/capd_p134217728.bin"),
    (201326592, "runs/capd_p201326592.bin"),
    (263192576, "runs/capd_tail.bin"),
]

if not self_test():
    print("FATAL selftest")
    sys.exit(3)
print(f"OFF={OFF} SMAX={SMAX}")
for P, f in PROBES:
    got = open(f, "rb").read()
    buf = bytes(b ^ 0xA5 for b in pattern_at(OFF + P, SMAX + len(got) + 32))
    win = got[:16]
    cands = [L for L in range(0, SMAX + 1) if buf[L:L + 16] == win]
    found = None
    for L in cands:
        if got[:65536] == buf[L:L + 65536]:
            found = L
            break
    print(f"P={P:>9} ({P/1048576:7.2f} MiB)  S={found}  (cands={cands[:5]}{'...' if len(cands) > 5 else ''})")
