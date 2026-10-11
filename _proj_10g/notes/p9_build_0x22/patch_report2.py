# -*- coding: utf-8 -*-
"""REPORT.md 数值订正: 比值 19.0x -> 20x; DP top10 同源条数 6 -> 5。幂等。"""
import io
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
p = r"D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_build_0x22\REPORT.md"
s = io.open(p, encoding="utf-8", newline="").read()

pairs = [
    ("⇒ 与 DP WNS 差值 0.474 ns / 比值 **≈19.0×**。", "⇒ 与 DP WNS 差值 0.474 ns / 比值 **≈20.0×**。"),
    ("（0.025–0.098，DP top10 里 6 条同源）", "（0.025–0.098，DP top10 里 **5 条**同源：`#1/#3/#4/#5/#6`）"),
]
for old, new in pairs:
    n = s.count(old)
    if n == 1:
        s = s.replace(old, new)
    print("hits=%d  %s" % (n, old[:40]))

io.open(p, "w", encoding="utf-8", newline="").write(s)
print("done; lines =", s.count("\n") + 1)
