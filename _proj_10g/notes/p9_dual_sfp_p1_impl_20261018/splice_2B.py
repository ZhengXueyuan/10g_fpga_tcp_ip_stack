#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把阶段 0x2B (P11 / P1 ch0 bring-up) 落进链式读侧工具 apply_readside_bid1c.py。

默认 = 只写副本 (round/apply_readside_bid1c__spliced.py) + py_compile + exec 自检;
`--apply` = 真改仓内工具 (先备份到本目录)。
插入点:
  1. `EDITS_2A = []` 之后: `EDITS_2B = []`
  2. `def E15` 块之后: `def E16`
  3. `# 目标 BID ⇒ 阶段链` 之前: 生成器现算的 E16 调用
  4. STAGES 末尾: 0x2B 行 (83, 0x17C)
  5. ALLOW 顶部: 本轮目录 / P11 设计/审查轮目录
  6. DEFAULT_SPECS: 无新增 (现有正则按现读值/参数断言; WLABEL/NAME/W/V/FAKE_TAIL 表长由 NW 驱动)
"""
import importlib.util
import io
import os
import py_compile
import shutil
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, "gen_edits_2A_2B.py")
TOOL = os.path.normpath(os.path.join(HERE, "..", "p7b_readside_bid1c_20261011",
                                     "apply_readside_bid1c.py"))
OUT = os.path.join(HERE, "apply_readside_bid1c__spliced_2B.py")
BACKUP = os.path.join(HERE, "apply_readside_bid1c__pre_splice_2B.py")


def load_gen():
    spec = importlib.util.spec_from_file_location("g2a2b", GEN)
    g = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(g)
    return g


def fmt_calls(rows, fn):
    out = []
    for rel, old, new, n in rows:
        out.append("%s(%r,\n  %r,\n  %r, %d)" % (fn, rel, old, new, n))
    return "\n".join(out) + "\n"


def splice(text, g):
    rows = g.ROWS
    # 1) list declaration
    a = "EDITS_2A = []          # 阶段 ⑮: 0x29 树 -> 0x2A 树 (p9 孤儿修复; **BID + 几何**: 75->76 字 / 0x15C->0x160)\n"
    assert a in text
    text = text.replace(a, a +
        "EDITS_2B = []          # 阶段 ⑯: 0x2A 树 -> 0x2B 树 (P11 / P1 ch0 bring-up; **BID + 几何**: 76->83 字 / 0x160->0x17C)\n", 1)
    # 2) E16 definition
    a = ("def E15(rel, old, new, n=1):\n"
         "    EDITS_2A.append((rel, old, new, n))\n")
    assert a in text
    text = text.replace(a, a +
        "\n\ndef E16(rel, old, new, n=1):\n"
        "    EDITS_2B.append((rel, old, new, n))\n", 1)
    # 3) edit calls before STAGES
    marker = "# 目标 BID ⇒ 阶段链 (链上每阶段的 old 侧 = 上一阶段的 new 侧)。"
    assert marker in text
    block = ("\n# ===========================================================================\n"
             "# 阶段 ⑯ (0x2A -> 0x2B, P11 / P1 ch0 bring-up)\n"
             "#   生成器 = _proj_10g/notes/p9_dual_sfp_p1_impl_20261018/gen_edits_2A_2B.py\n"
             "#   几何: 83 字 / 未实现 0x17C / BID 0x2B; W76..W82; MIR 四址 +0x1C。\n"
             "#   ⚠️ p6e wrapper/counters 与 p7b_chain TB 已由实现 agent 手工同步 (见生成器 §15),\n"
             "#      本阶段不对它们发 EDITS; DEFAULT_SPECS 仍断言其终值。\n"
             "# ===========================================================================\n"
             + fmt_calls(rows, "E16") + "\n")
    text = text.replace(marker, block + marker, 1)
    # 4) STAGES row
    a = ('          ("0x0000002A", EDITS_2A, "p9 孤儿修复 (2026-10-17)", 76, 0x160)]')
    assert a in text
    text = text.replace(a,
        '          ("0x0000002A", EDITS_2A, "p9 孤儿修复 (2026-10-17)", 76, 0x160),\n'
        '          ("0x0000002B", EDITS_2B, "P11 P1 ch0 bring-up (2026-10-18)", 83, 0x17C)]', 1)
    # 5) ALLOW entries
    a = ('    (r"^_proj_10g/notes/p9_build_0x2A_20261017/readside/", "现役: 本轮读侧生成器/拼接器/自检输出"),\n')
    assert a in text
    text = text.replace(a, a +
        '    (r"^_proj_10g/notes/p9_dual_sfp_p1_impl_20261018/", "现役: P11/P1 实施轮 (设计/报告/门日志/读侧生成器)"),\n'
        '    (r"^_proj_10g/notes/p9_dual_sfp_p1_design_20261017/", "P11/P1 设计轮 (v4.1; 含旧代 BID/NW)"),\n'
        '    (r"^_proj_10g/notes/p9_dual_sfp_plan_20261017/", "P11 总计划轮 (含 0x2A/0x28 旧代)"),\n'
        '    (r"^_proj_10g/notes/p9_dual_sfp_p0_20261017/", "P11 P0 板级轮 (0x2A 位流身份)"),\n'
        '    (r"^_proj_10g/notes/p9_dual_sfp_exit_identity_compare_20261018/", "P11 出口身份分析轮"),\n'
        '    (r"^_proj_10g/notes/p9_dual_sfp_s1_cost_20261018/", "P11 双栈代价分析轮"),\n'
        '    (r"^_proj_10g/notes/p9_review_dual_sfp_p1_design_20261018/", "P11 P1 设计红队 FINDINGS (含旧代值)"),\n'
        '    (r"^_proj_10g/notes/p9_basin_zero_win_20261017/", "旧位流读法: 慢盆/零窗板级轮 (烧 0x2A 时代位流; 其 NW/BID 是那一代真值)"),\n'
        '    (r"^_proj_10g/notes/p9_board_0x2A_20261017/", "旧位流读法: 0x2A 板级轮 (烧 0x2A 位流; 其 NW/BID/UNIMPL 是那一代真值)"),\n', 1)
    return text


def main():
    g = load_gen()
    text = io.open(TOOL, "r", encoding="utf-8", newline="").read()
    new = splice(text, g)
    out = TOOL if "--apply" in sys.argv else OUT
    if "--apply" in sys.argv:
        if not os.path.exists(BACKUP):
            shutil.copy2(TOOL, BACKUP)
        print("BACKUP = %s" % BACKUP)
    io.open(out, "w", encoding="utf-8", newline="").write(new)
    print("WROTE %s (%d -> %d bytes)" % (out, len(text.encode("utf-8")), len(new.encode("utf-8"))))
    py_compile.compile(out, doraise=True)
    print("PY_COMPILE OK")
    ns = {"__name__": "spliced_readside_tool_2b", "__file__": TOOL}
    exec(compile(new, out, "exec"), ns)
    print("STAGES = %s" % [s[0] for s in ns["STAGES"]])
    print("len(EDITS_2B) = %d" % len(ns["EDITS_2B"]))
    if "--run" in sys.argv:
        i = sys.argv.index("--run")
        tool_args = sys.argv[i + 1:]
        sys.argv = [TOOL] + tool_args
        rc = ns["main"]()
        print("TOOL_RC=%d (args: %s)" % (rc, " ".join(tool_args)))
        return rc
    return 0


if __name__ == "__main__":
    sys.exit(main())
