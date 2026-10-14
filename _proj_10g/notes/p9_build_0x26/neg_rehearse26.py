#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""负彩排 (构建轮 0x25): **故意漏掉末条 edit** ⇒ 期望**恰 1 红** (= 被漏掉那处的断言)。
做法 = 内存 overlay (仓内文件一个字节不动): 只把 24 处里的**最后一条**从应用列表里去掉,
跑与 apply 后同一套 C 断言 (assert_defaults) —— 漏掉的那处默认值仍是旧代 ⇒ 必然 1 红。
⛔ 只读仓内文件; 不落盘任何仓内改动。RC: 0 = 恰好 1 红 (符合预期) / 1 = 不是恰 1 红。
"""
import importlib.util, os, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "arb", os.path.join(HERE, "..", "p7b_readside_bid1c_20261011", "apply_readside_bid1c.py"))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

TARGET = "0x00000026"
todo = m.stages_to_do(TARGET)
print("负彩排 target=%s; 阶段 = %s" % (TARGET, [(b, len(e)) for b, e, _n, _w, _u in todo]))
assert len(todo) == 1, "盘上读侧代应恰好差 1 阶段 (got %d)" % len(todo)
bk, edits, nm, _w, _u = todo[0]
dropped = edits[-1]
print("故意漏掉的 1 处 = (%s, %s, %r)" % (bk, dropped[0], dropped[1][:60]))

overlay = {}
applied, skipped, ok = m._apply_stage_on_overlay(overlay, bk, edits[:-1])
print("部分应用 (24 -> 23 处): applied=%d / skipped=%d / ok=%s" % (applied, skipped, ok))
nw, unimpl = m.stage_nw(TARGET), m.stage_unimpl(TARGET)
fails = m.assert_defaults(nw, TARGET, overlay, unimpl)
print("负彩排 FAIL 数 = %d" % len(fails))
for f in fails:
    print("  红: %s" % f)
expect = dropped[0]
ok1 = (len(fails) == 1 and fails[0].startswith(expect))
print("NEG_REHEARSE %s (期望恰 1 红且落 %s)" % ("OK" if ok1 else "FAIL", expect))
sys.exit(0 if ok1 else 1)
