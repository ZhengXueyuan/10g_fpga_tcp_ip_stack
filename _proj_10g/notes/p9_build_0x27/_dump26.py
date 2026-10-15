#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""只读: 打印 EDITS_26 的逐条 new 侧 (供 0x27 生成器设计). 不写仓内文件."""
import importlib.util, os, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "p7b_readside_bid1c_20261011", "apply_readside_bid1c.py")
spec = importlib.util.spec_from_file_location("arb", SCRIPT)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print("EDITS_26 len =", len(m.EDITS_26))
for i, (rel, old, new, n) in enumerate(m.EDITS_26):
    print("="*100)
    print("[%d] %s  (n=%d)" % (i, rel, n))
    print("--- OLD ---"); print(old)
    print("--- NEW ---"); print(new)
