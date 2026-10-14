#!/usr/bin/env python
"""F-3 (G1) 变异件生成器: fwd 谓词被改坏的两个变体。

设计件 = _proj_10g/notes/p9_fix_f3_design_20261014/DESIGN_v2.md §3.2-G1:
  M1 = `fwd = 1'b1`                      ("tuser 谓词没承重" ⇒ 门形同虚设 ⇒ 必须红)
  M2 = `fwd = (!RESYNC_EN) || resync || s_axis_tlast`  ("开在帧尾而非帧首" ⇒ 必须红)

锚点纪律 (本仓 #72/#75 类坑): 锚点必须**计数断言** —— 现读行内容不符/出现次数 != 1
时硬失败, 不许静默产出"没变异的变异件"。用法:
    python mk_mut_f3.py <repo_root> [--out <dir>]

风格照 sim/p3sim_sw/mut/mk_mut_acckadv.py: 以**二进制**读写保住行尾 (rtl/vlan_strip.v
是 LF, 但纪律不变), 并断言"diff 面 = 恰好 1 行"。
"""
import hashlib
import os
import sys

ANCHOR = "    wire        fwd   = (!RESYNC_EN) || resync || s_axis_tuser;"
MUT1 = "    wire        fwd   = 1'b1;"
MUT2 = "    wire        fwd   = (!RESYNC_EN) || resync || s_axis_tlast;"


def make(src, anchor, mutant, tag, outdir):
    n = src.count(anchor)
    assert n == 1, ('anchor count != 1 (stale anchor? fwd line changed?): %d [%s]' % (n, tag))
    mut = src.replace(anchor, mutant)
    assert mut.count(mutant) == 1 and mut.count(anchor) == 0
    sl, ml = src.splitlines(), mut.splitlines()
    assert len(sl) == len(ml), 'line count changed [%s]' % tag
    diffs = [i + 1 for i in range(len(sl)) if sl[i] != ml[i]]
    assert len(diffs) == 1, ('expected exactly 1 changed line, got %r [%s]' % (diffs, tag))
    out = os.path.join(outdir, 'mut_%s.v' % tag)
    mraw = mut.encode('utf-8')
    with open(out, 'wb') as fh:
        fh.write(mraw)
    print('MUTGEN %s changed_lines=%r out=%s sha256=%s' %
          (tag, diffs, out, hashlib.sha256(mraw).hexdigest()[:16]))
    print('MUTGEN %s SUBST %s' % (tag, anchor))
    print('MUTGEN %s SUBST %s' % (tag, mutant))


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.dirname(os.path.dirname(
            os.path.dirname(os.path.abspath(__file__))))), '')
    outdir = None
    if len(sys.argv) > 3 and sys.argv[2] == '--out':
        outdir = sys.argv[3]
    srcpath = os.path.join(root, 'rtl', 'vlan_strip.v')
    outdir = outdir or os.path.dirname(os.path.abspath(__file__))
    raw = open(srcpath, 'rb').read()
    src = raw.decode('utf-8')
    print('MUTGEN SRC %s sha256=%s' % (srcpath, hashlib.sha256(raw).hexdigest()[:16]))
    make(src, ANCHOR, MUT1, 'm1', outdir)
    make(src, ANCHOR, MUT2, 'm2', outdir)


if __name__ == '__main__':
    main()
