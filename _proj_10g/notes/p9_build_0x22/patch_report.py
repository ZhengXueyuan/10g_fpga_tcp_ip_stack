# -*- coding: utf-8 -*-
"""REPORT.md 的两处就地订正 (笔误 + 端点数对照)。一次性脚本, 幂等。"""
import io
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
p = r"D:\repo\XCKU5PMini\udp_hls_10g\_proj_10g\notes\p9_build_0x22\REPORT.md"
s = io.open(p, encoding="utf-8", newline="").read()

bad = ("⑤ 新文件全在 `_proj_10g/notes/p9_build_0x22/` 与 `_proj_10g/notes/p7b_build_archive/20261015_215445/`"
       "（笔误，见下）——\n⚠️ **订正**：构建脚本归档目录 = `_proj_10g/notes/p7b_build_archive/20261011_215445/`。")
good = "⑤ 新文件全在 `_proj_10g/notes/p9_build_0x22/` 与 `_proj_10g/notes/p7b_build_archive/20261011_215445/`。"
n1 = s.count(bad)
if n1 == 1:
    s = s.replace(bad, good)
print("fix1 hits =", n1)

old2 = "- **读数**（`board/p7b_ku5p_stdout.txt` + `board/p7b_ku5p_timing.rpt`；全量副本 = `board_stdout.txt` / `board_rpt/`）："
add2 = ("- ⚠️ **端点总数对照（同口径，可比）**：setup/hold 端点 **261,899 → 257,862**（0x21 → 0x22，Δ **−4,037**）、\n"
        "  pulse-width 端点 **84,934 → 83,887**（Δ **−1,047**）—— 方向与\"MM 从机三件被 AXIS 成形器取代\"一致\n"
        "  （⛔ 仍属跨网表差、**无拆刀臂 ⇒ 不归因**）。\n"
        + old2)
n2 = s.count(old2)
if n2 == 1 and add2 not in s:
    s = s.replace(old2, add2)
print("fix2 hits =", n2)

old3 = "与上一轮同形；**单值 WPWS = 0.000 / TPWS 失败端点 0**（Design Timing Summary 行）。"
new3 = ("与上一轮同形；**Design Timing Summary 行：WPWS 0.000 / TPWS 0.000 / TPWS 失败端点 0**"
        "（⚠️ 0x21 归档 rpt 逐字同形 ⇒ 是同形态、非本轮异常）。")
n3 = s.count(old3)
if n3 == 1:
    s = s.replace(old3, new3)
print("fix3 hits =", n3)

io.open(p, "w", encoding="utf-8", newline="").write(s)
print("patched; lines =", s.count("\n") + 1)
