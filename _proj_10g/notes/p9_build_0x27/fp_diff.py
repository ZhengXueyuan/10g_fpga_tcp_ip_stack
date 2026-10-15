#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""指纹 diff (只读): 两个 P4_MATRIX_FINGERPRINT 文件的内容对比 ⇒ 列出
"内容变了 / 新增 / 消失" 的文件 (判 0x26 轮的漂移集合)。
用法: fp_diff.py <base_fingerprint> <new_fingerprint>
"""
import io, sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def read_hashes(path):
    d = {}
    for line in io.open(path, "r", encoding="ascii", errors="replace"):
        if not line.startswith("SHA256 "):
            continue
        p = line.split()
        if len(p) >= 4:
            d[p[2]] = p[1]
    return d


a, b = read_hashes(sys.argv[1]), read_hashes(sys.argv[2])
changed = sorted(k for k in set(a) & set(b) if a[k] != b[k])
added = sorted(set(b) - set(a))
gone = sorted(set(a) - set(b))
print("BASE %s: %d files" % (sys.argv[1], len(a)))
print("NEW  %s: %d files" % (sys.argv[2], len(b)))
print("CONTENT-CHANGED (%d):" % len(changed))
for k in changed:
    print("  C %s" % k)
print("ADDED (%d):" % len(added))
for k in added:
    print("  + %s" % k)
print("GONE (%d):" % len(gone))
for k in gone:
    print("  - %s" % k)
