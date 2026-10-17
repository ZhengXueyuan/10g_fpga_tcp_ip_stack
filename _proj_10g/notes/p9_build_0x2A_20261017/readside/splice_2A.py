#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把阶段 ⑭ (0x29) / ⑮ (0x2A) 落进链式读侧工具 `apply_readside_bid1c.py`。

默认 = **只写副本** (round/readside/apply_readside_bid1c__spliced.py) 并编译自检;
`--apply` = 真改仓内工具 (先备份到本目录)。
插入点:
  1. `EDITS_28 = []` 之后: `EDITS_29 = []` / `EDITS_2A = []`
  2. `def E13` 块之后: `def E14` / `def E15`
  3. `# 目标 BID ⇒ 阶段链` 之前: 86 条 E14/E15 调用 (生成器现算)
  4. `STAGES` 的 0x28 行之后: 0x29 / 0x2A 两行 (几何 75/0x15C → 76/0x160)
  5. `ALLOW` 顶部: 新轮目录 / 0x29 拆刀轮 / 孤儿修复实施轮 / 设计轮
  6. `DEFAULT_SPECS`: tb_biz_win 的 BUILD_ID 断言 (本刀把它从 0x08 纠正到 0x2A)
"""
import importlib.util
import io
import os
import py_compile
import shutil
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, "gen_edits_29_2A.py")
TOOL = os.path.normpath(os.path.join(HERE, "..", "..", "p7b_readside_bid1c_20261011",
                                     "apply_readside_bid1c.py"))
OUT = os.path.join(HERE, "apply_readside_bid1c__spliced.py")
BACKUP = os.path.join(HERE, "apply_readside_bid1c__pre_splice_29_2A.py")


def load_gen():
    spec = importlib.util.spec_from_file_location("g292a", GEN)
    g = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(g)
    return g


def fmt_calls(rows, fn):
    out = []
    for rel, old, new, n in rows:
        out.append("%s(%r,\n  %r,\n  %r, %d)" % (fn, rel, old, new, n))
    return "\n".join(out) + "\n"


def splice(text, g):
    rows29, rows2a = g.build_edits()
    # 1) list declarations
    a = "EDITS_28 = []          # 阶段 ⑬: 0x27 树 -> 0x28 树 (P9 E12 观测计数器; **BID + 几何**: 71->75 字 / 0x14C->0x15C)\n"
    assert a in text
    text = text.replace(a, a +
        "EDITS_29 = []          # 阶段 ⑭: 0x28 树 -> 0x29 树 (0x29 拆刀; **BID-only**: 几何不变 75 字 / 0x15C)\n"
        "EDITS_2A = []          # 阶段 ⑮: 0x29 树 -> 0x2A 树 (p9 孤儿修复; **BID + 几何**: 75->76 字 / 0x15C->0x160)\n", 1)
    # 2) E14/E15 definitions
    a = ("def E13(rel, old, new, n=1):\n"
         "    EDITS_28.append((rel, old, new, n))\n")
    assert a in text
    text = text.replace(a, a +
        "\n\ndef E14(rel, old, new, n=1):\n"
        "    EDITS_29.append((rel, old, new, n))\n"
        "\n\ndef E15(rel, old, new, n=1):\n"
        "    EDITS_2A.append((rel, old, new, n))\n", 1)
    # 3) edit calls before STAGES
    marker = "# 目标 BID ⇒ 阶段链 (链上每阶段的 old 侧 = 上一阶段的 new 侧)。"
    assert marker in text
    block = ("\n# ===========================================================================\n"
             "# 阶段 ⑭ (0x28 -> 0x29, 0x29 拆刀) 与 ⑮ (0x29 -> 0x2A, p9 孤儿修复)\n"
             "#   生成器 = _proj_10g/notes/p9_build_0x2A_20261017/readside/gen_edits_29_2A.py\n"
             "#   ⚠️ ⑮ 的几何行 41 用**盘上现读**的 75 分支 (EDITS_28[41] 的 new 侧是 0x28 审查轮\n"
             "#      E-1 修复前的 stale 文本); ⑮ 另含 p6e TB 的 73 处 MIR 地址 token 与\n"
             "#      tb_biz_win.v 的 BUILD_ID/MIR 派生式改造。\n"
             "# ===========================================================================\n"
             + fmt_calls(rows29, "E14") + "\n" + fmt_calls(rows2a, "E15") + "\n")
    text = text.replace(marker, block + marker, 1)
    # 4) STAGES rows
    a = ('          ("0x00000028", EDITS_28, "P9 E12 观测计数器 (2026-10-15)", 75, 0x15C)]')
    assert a in text
    text = text.replace(a,
        '          ("0x00000028", EDITS_28, "P9 E12 观测计数器 (2026-10-15)", 75, 0x15C),\n'
        '          ("0x00000029", EDITS_29, "0x29 拆刀 (persist 关; 2026-10-17)", 75, 0x15C),\n'
        '          ("0x0000002A", EDITS_2A, "p9 孤儿修复 (2026-10-17)", 76, 0x160)]', 1)
    # 5) ALLOW entries
    a = ('    (r"^board/wrapper_p4\\.v$", "权威源: SNAP_NW_P6E / BUILD_ID_V (只读; 由 ⑧ 现读)"),\n')
    assert a in text
    text = text.replace(a, a +
        '    (r"^_proj_10g/notes/p9_build_0x2A_20261017/", "现役: 本轮 (阶段 ⑮ = 0x2A) 构建轮目录 (读数/归档/生成器)"),\n'
        '    (r"^_proj_10g/notes/p9_orphan_impl_20261017/", "现役: 孤儿修复实施轮目录 (0x2A 内容取证; 含各代 BID 字符串)"),\n'
        '    (r"^_proj_10g/notes/p9_orphan_fix_design_20261017/", "现役: 孤儿修复设计轮目录 (v4.1; 含 0x2A 字样)"),\n'
        '    (r"^_proj_10g/notes/p9_dissect_0x29_20261017/", "旧位流读法: 0x29 拆刀轮 (2026-10-17; 烧 0x29 位流 + LEGACY 两跑; BID 0x29 = 那一代真值)"),\n'
        '    (r"^_proj_10g/notes/p9_build_0x2A_20261017/readside/", "现役: 本轮读侧生成器/拼接器/自检输出"),\n'
        '    (r"^_proj_10g/notes/p9_(board_0x28_k0_20261016|review_build0x28_20261016|mdio_aplus_board_20261016|c1_board_20261017|t2fast_ab_20261017|slowbasin_gc_20261017|basin_probe_20261017|sink_delta_20261017|p3win_trickle_board_20261017)/",\n'
        '     "旧位流读法: 2026-10-16/17 板级/实验轮现场 (烧的是 0x24/0x27/0x28 各代归档位流; "\n'
        '     "其 BID/NW/UNIMPL 是**那一代的真值**, 由各轮 WANT sha256 钉死; 改它反而毁掉该轮取证)"),\n', 1)
    # 6) DEFAULT_SPECS: tb_biz_win BUILD_ID (本刀顺带纠正 0x08 -> 0x2A)
    a = ('    ("_proj_10g/notes/p7b_biz_win/tb_biz_win.v", r"localparam integer NW = (\\d+)", "NW"),\n')
    assert a in text
    text = text.replace(a, a +
        '    #   ⚠️ 2026-10-17 p9 孤儿修复: 本件的 BUILD_ID_V/检查此前自 M1 起停在 0x08 (0x28 轮只抬了 NW)\n'
        '    #      ⇒ 本轮一并纠正并**纳入断言** (再漂就红)。\n'
        '    ("_proj_10g/notes/p7b_biz_win/tb_biz_win.v", r\'chk\\("1b BUILD_ID", v, 32\\\'h([0-9A-Fa-f]+)\\)\', "BID"),\n', 1)
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
    # 自检: STAGES / 列表 / 调用数
    ns = {"__name__": "spliced_readside_tool", "__file__": TOOL}
    exec(compile(new, out, "exec"), ns)
    print("STAGES = %s" % [s[0] for s in ns["STAGES"]])
    print("len(EDITS_29) = %d / len(EDITS_2A) = %d" % (len(ns["EDITS_29"]), len(ns["EDITS_2A"])))
    # 在**进程内**按真 REPO 跑工具 (不落盘真工具; 只有 --apply 才改它)
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
