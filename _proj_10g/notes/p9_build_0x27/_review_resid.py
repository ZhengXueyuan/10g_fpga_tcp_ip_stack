#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""只读: 把 EDITS_27_BLOCK.txt 的 new 侧逐条列出**仍提到 0x26 的行**, 供人工核
(每条都必须是"逐字保留的历史")。"""
import io
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
t = io.open("EDITS_27_BLOCK.txt", encoding="utf-8").read()
# 每 4 行 = 一条: E12(...) / old / new, n) / (空)
lines = t.split("\n")
i = 0
idx = -1
while i < len(lines):
    if lines[i].startswith("E12("):
        idx += 1
        old = lines[i + 1]
        new = lines[i + 2]
        for ln in old.split("\\n"):
            pass
        hits = [seg for seg in new.split("\\n") if "0x26" in seg]
        if hits:
            print("[%d] %s" % (idx, lines[i][:80]))
            for h in hits:
                print("      | %s" % h[:160])
        i += 4
    else:
        i += 1
print("done entries=%d" % (idx + 1))
