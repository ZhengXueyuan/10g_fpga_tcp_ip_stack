#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""负彩排 (构建轮 0x27) — **post-apply / 反演重建**版: 盘上已 apply (0 待做阶段) 时,
用 overlay 把**最后一条 edit 反演回去** (new→old, 只在内存) ⇒ 期望**恰 1 红**。
⛔ 仓内文件不动。RC: 0 = 恰 1 红 / 1 = 不符。
"""
import importlib.util, os, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "arb", os.path.join(HERE, "..", "p7b_readside_bid1c_20261011", "apply_readside_bid1c.py"))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

TARGET = "0x00000027"
stage = m.stage_of(TARGET)
rel, old, new, n = stage[1][-1]
print("反演重建 (post-apply): 把末条 edit 反演回旧值 ⇒ 期望恰 1 红")
print("目标件 = %s" % rel)
p = os.path.join(m.REPO, rel.replace("/", os.sep))
b, nl = m.rd(p)
cur = b.decode("utf-8")
new2 = new.replace("\n", nl.decode())
old2 = old.replace("\n", nl.decode())
k = cur.count(new2)
assert k == n, "盘上应有 %d 处 new 侧 (got %d) —— apply 未落盘?" % (n, k)
rev, nsub = cur.replace(new2, old2), k
assert nsub == n
overlay = {rel: rev}
nw, unimpl = m.stage_nw(TARGET), m.stage_unimpl(TARGET)
fails = m.assert_defaults(nw, TARGET, overlay, unimpl)
print("负彩排 FAIL 数 = %d" % len(fails))
for f in fails:
    print("  红: %s" % f)
ok = (len(fails) == 1 and fails[0].startswith(rel))
print("NEG_REHEARSE(post) %s (期望恰 1 红且落 %s)" % ("OK" if ok else "FAIL", rel))
sys.exit(0 if ok else 1)
