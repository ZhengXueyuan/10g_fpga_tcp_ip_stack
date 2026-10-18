#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""gen_edits_backstop2.py -- 从 **0x88/0x2D 基线副本** 与 **现磁盘 (85/0x184)** 的
逐行 diff 生成 `apply_readside_bid1c.py` 的 0x2D 阶段**显式增量** (EDITS_2D.extend)。

纪律:
  * old 侧 = 0x88/0x2D 基线（= 现有 EDITS_2D 应用后的中间态）；
  * new 侧 = 现磁盘；
  * 每笔 edit 在**内存重放**里必须恰好命中 1 次；重放结果必须与现磁盘**逐字节相同**
    （按 LF 归一；行尾样式已在 apply 引擎里由文件自身 nl 处理）。
  * 不改历史注释（diff 只会把我们本轮真正改过的行作为 old 侧）。

输出: `BACKSTOP2_EDITS.frag` (可直接粘贴/拼接进 apply_readside_bid1c.py 的 Python 字面量块)
"""
import difflib
import io
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BASE = os.path.join(HERE, "baseline_0x88_0x2D")

FILES = [
    "_proj_pcie/p6e_snap_check.sh",
    "_proj_pcie/p7b_biz/p7b_snap.sh",
    "_proj_pcie/p7b_gate4_negctrl.sh",
    "_proj_pcie/p7b_gate4_accept.sh",
    "_proj_pcie/p7b_gate4_selftest.sh",
    "_proj_pcie/p7b_gate4_livefake.sh",
    "_proj_pcie/p6e_snap_selftest_fix2.sh",
    "_proj_10g/notes/p7b_gate4_3/final_state.sh",
    "_proj_10g/notes/p7b_gate4_criteria/gen_inputs.py",
    "_proj_10g/notes/p7b_affinity/j6_r6fix.sh",
    "_proj_10g/notes/p7b_biz_tcpreg/tcpreg_j6.sh",
    "_proj_10g/notes/p7b_biz_win/check_window.py",
    "_proj_10g/notes/p7b_biz_win/tb_biz_win.v",
    "_proj_10g/notes/p7b_biz_win/run_tb_biz_win.bat",
    "_proj_10g/notes/p7b_biz_win/run_xvlog_wrapper.bat",
    "sim/p5wu_p1p2/run_xvlog_wrapper63.bat",
    "_proj_10g/p7b_chain/sim/tb_p7b_chain.v",
    "_proj_10g/p7b_chain/sim/check_snap_top5_wired.py",
    "sim/p6e_pcie/tb_p6e_pcie_wrapper.v",
]


def norm(s):
    return s.replace("\r\n", "\n")


def load(p):
    return norm(io.open(p, encoding="utf-8", newline="").read())


def hunks(base_lines, cur_lines):
    """逐 opcode 生成 (old, new)，**两侧各带 1 行上下文**（纯插入也可被 str.replace 表达）。
    上下文按 opcode 的**真实下标**取（不能用 find —— 重复行会锚错位置，实测踩到）。"""
    sm = difflib.SequenceMatcher(None, base_lines, cur_lines, autojunk=False)
    out = []
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            continue
        s, e = i1, i2
        cs, ce = j1, j2
        # 上下文各扩 1 行
        if s > 0:
            s -= 1
            cs -= 1
        if e < len(base_lines):
            e += 1
            ce += 1
        out.append((base_lines[s:e], cur_lines[cs:ce], (s, e, cs, ce)))
    return out


def simulate(edits, base_text):
    cur = base_text
    applied = []
    for rel_order, old, new in edits:
        k = cur.count(old)
        if k != 1:
            raise SystemExit("simulate: old hit %d != 1 in %s: %r" % (k, rel_order, old[:80]))
        cur = cur.replace(old, new, 1)
        applied.append((rel_order, old, new))
    return cur


def py_literal(s):
    # raw 三引号: 代码里含 `\n` / `\s` / `\w`（Verilog/py 正则）时不得被 Python 转义吃掉
    if "'''" in s or s.endswith("\\"):
        return repr(s)
    return "r'''" + s + "'''"


def main():
    all_edits = []
    frag = []
    for rel in FILES:
        bp = os.path.join(BASE, rel.replace("/", os.sep))
        cp = os.path.join(REPO, rel.replace("/", os.sep))
        b = load(bp)
        c = load(cp)
        if b == c:
            print("SKIP (no diff): %s" % rel)
            continue
        bl, cl = b.split("\n"), c.split("\n")
        hs = hunks(bl, cl)
        # 逐文件内的 edits: 用重放态模拟；上下文不足唯一时按**真实下标**继续扩
        local = []
        for old_chunk, new_chunk, (s, e, cs, ce) in hs:
            old, new = "\n".join(old_chunk), "\n".join(new_chunk)
            state = b
            for _r, o2, n2 in local:
                state = state.replace(o2, n2, 1)
            guard = 0
            while state.count(old) != 1:
                guard += 1
                if guard > 40:
                    raise SystemExit("cannot uniquify hunk in %s: %r" % (rel, old[:100]))
                if s > 0:
                    s -= 1
                    cs -= 1
                elif e < len(bl):
                    e += 1
                    ce += 1
                else:
                    raise SystemExit("cannot expand: %s" % rel)
                old, new = "\n".join(bl[s:e]), "\n".join(cl[cs:ce])
            local.append((rel, old, new))
        # 文件内模拟
        final = simulate(local, b)
        if final != c:
            # 打印首个差异帮助定位
            fl = final.split("\n")
            cl2 = c.split("\n")
            for i, (x, y) in enumerate(zip(fl, cl2)):
                if x != y:
                    print("MISMATCH %s line %d:\n  got : %r\n  want: %r" % (rel, i + 1, x, y))
                    break
            raise SystemExit("replay != disk for %s" % rel)
        print("OK %-64s edits=%d" % (rel, len(local)))
        all_edits += local
        for _r, old, new in local:
            frag.append("    (%r,\n     %s,\n     %s, 1)," % (rel, py_literal(old), py_literal(new)))

    frag_text = "\n".join(frag)
    with io.open(os.path.join(HERE, "BACKSTOP2_EDITS.frag"), "w", encoding="utf-8", newline="\n") as f:
        f.write(frag_text)
    print("TOTAL edits=%d -> BACKSTOP2_EDITS.frag" % len(all_edits))
    return 0


if __name__ == "__main__":
    sys.exit(main())
