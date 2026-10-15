#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""负彩排 (构建轮 0x28): **故意漏掉 1 处活行 edit** ⇒ 期望**恰 1 红** (= 那处的断言)。
选中的那条 = `final_state.sh` 的 UNIMPL 活行 (`rd 0x14c` -> `rd 0x15c`) —— 与历轮"漏一处活行"
同构 (0x27 轮漏的是末条).
做法 = 内存 overlay (仓内文件一个字节不动): 把该条从应用列表里去掉, 跑与 apply 后同一套
C 断言 (assert_defaults) —— 漏掉的那处默认值仍是旧代 ⇒ 必然 1 红。
⛔ 只读仓内文件; 不落盘任何仓内改动。RC: 0 = 恰好 1 红 (符合预期) / 1 = 不是恰 1 红。
"""
import importlib.util
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "arb", os.path.join(HERE, "..", "p7b_readside_bid1c_20261011", "apply_readside_bid1c.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

TARGET = "0x00000028"
todo = m.stages_to_do(TARGET)
print("负彩排 target=%s; 阶段 = %s" % (TARGET, [(b, len(e)) for b, e, _n, _w, _u in todo]))
assert len(todo) == 1, "盘上读侧代应恰好差 1 阶段 (got %d)" % len(todo)
bk, edits, nm, _w, _u = todo[0]

# 选中要漏的那条: final_state.sh 的 UNIMPL 活行 (`rd 0x14c`)
idx = [i for i, (rel, old, _new, _n) in enumerate(edits)
       if rel.endswith("p7b_gate4_3/final_state.sh") and "rd 0x14c" in old]
assert len(idx) == 1, "选中条目数 = %d (期望 1)" % len(idx)
dropped = edits[idx[0]]
print("故意漏掉的 1 处 = (%s, %r, %r)" % (dropped[0], dropped[1][:60], dropped[2][:60]))
rest = [e for i, e in enumerate(edits) if i != idx[0]]
print("漏掉后应用 %d 处 (原 %d)" % (len(rest), len(edits)))

overlay = {}
applied, skipped, ok = m._apply_stage_on_overlay(overlay, bk, rest)
print("部分应用: applied=%d / skipped=%d / ok=%s" % (applied, skipped, ok))
nw, unimpl = m.stage_nw(TARGET), m.stage_unimpl(TARGET)
fails = m.assert_defaults(nw, TARGET, overlay, unimpl)
print("负彩排 FAIL 数 = %d" % len(fails))
for f in fails:
    print("  红: %s" % f)
expect = dropped[0]
ok1 = (len(fails) == 1 and fails[0].startswith(expect))
print("NEG_REHEARSE %s (期望恰 1 红且落 %s)" % ("OK" if ok1 else "FAIL", expect))
sys.exit(0 if ok1 else 1)
