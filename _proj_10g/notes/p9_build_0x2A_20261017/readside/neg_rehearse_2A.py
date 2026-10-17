#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""⑮ 的**反演彩排** (负对照): 故意漏一条 edit, 必须**恰 1 红**且落在该文件。

两种模式 (自动判):
  · **pre**  (盘上读侧代 < 0x2A): 在内存 overlay 上按链应用**除**目标 edit 外的全部;
  · **post** (盘上读侧代 = 0x2A): 先把盘上 0x2A **反演重建**成 0x28 (new→old, 内存),
    再正向应用**除**目标 edit 外的全部 ⇒ 模拟"漏了一条 edit"的落盘态。
⛔ 仓内文件一个字节都不动。"""
import importlib.util
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
P = os.path.join(HERE, "apply_readside_bid1c__spliced.py")
spec = importlib.util.spec_from_file_location("sp", P)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.REPO = os.path.normpath(os.path.join(HERE, "..", "..", "..", ".."))

DROP_REL = "_proj_10g/notes/p7b_gate4_3/final_state.sh"
DROP_SUB = "UNIMPL=$(rd 0x15c)"
TARGET = "0x0000002A"
NW = 76
UNIMPL = 0x160

chain = m.chain_for(TARGET)
gen = m.tree_gen()
print("盘上读侧代 = %s ⇒ 模式 = %s" % (gen, "post (反演重建)" if gen == TARGET else "pre"))

ov = {}
if gen == TARGET:
    # ---- 反演重建: 从 0x2A 盘上态回到 0x28 态 (new → old) ----
    for bk, edits, nm, _w, _u in reversed(chain[-2:]):   # 只回退 ⑭/⑮ (0x28 的 new 侧有 E-1 stale)
        for rel, old, new, n in reversed(edits):
            cur = ov.get(rel)
            if cur is None:
                p = os.path.join(m.REPO, rel.replace("/", os.sep))
                b, nl = m.rd(p)
                cur = b.decode("utf-8").replace(nl.decode(), "\n")
            k = cur.count(new)
            assert k == n, "invert %s %s: new hits=%d/%d" % (bk, rel, k, n)
            ov[rel] = cur.replace(new, old)
    print("反演重建 OK (回到 %s 态)" % (chain[-2][0] if len(chain) > 1 else "?"))
    start_stages = chain[-2:]
else:
    start_stages = [st for st in chain if int(st[0], 16) > int(gen, 16)]

# ---- 正向应用 (漏掉目标 edit) ----
dropped = 0
for bk, edits, nm, _w, _u in start_stages:
    keep = []
    for e in edits:
        if e[0] == DROP_REL and DROP_SUB in e[1]:
            dropped += 1
            print("DROP edit: %s  %r" % (e[0], e[1][:70]))
            continue
        keep.append(e)
    ok = m._apply_stage_on_overlay(ov, bk, keep)
    print("stage %s applied=%s (%d edit)" % (bk, ok, len(keep)))
    assert ok
print("dropped=%d (期望 1)" % dropped)
fails = []
fails += m.assert_tables(NW, ov, UNIMPL)
fails += m.assert_defaults(NW, TARGET, ov, UNIMPL)
print("FAILS = %s" % fails)
key = "%s[UNIMPL]" % DROP_REL
ok = (len(fails) == 1 and key in fails)
print("NEG_REHEARSE %s (恰 1 红且落 %s)" % ("OK" if ok else "FAIL", key))
sys.exit(0 if ok else 1)
