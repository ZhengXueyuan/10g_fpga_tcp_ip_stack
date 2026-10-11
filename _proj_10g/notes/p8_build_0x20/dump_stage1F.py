#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""只读: 打印 apply_readside_bid1c.py 阶段 ④ (EDITS_1F) 的全部 edit (供构造阶段 ⑤)。"""
import importlib.util, os, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "p7b_readside_bid1c_20261011", "apply_readside_bid1c.py")
spec = importlib.util.spec_from_file_location("rs", SCRIPT)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
for i, (rel, old, new, n) in enumerate(m.EDITS_1F):
    print("### [%02d] %s  n=%d" % (i, rel, n))
    print("--- OLD ---"); print(old)
    print("--- NEW ---"); print(new)
print("TOTAL E4 edits = %d; files = %d" % (len(m.EDITS_1F), len(set(e[0] for e in m.EDITS_1F))))
