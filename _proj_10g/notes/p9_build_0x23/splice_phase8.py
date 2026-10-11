#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把阶段 ⑧ (EDITS_23) 拼进 `apply_readside_bid1c.py`:
  ① 顶层 `EDITS_23 = []` + `def E8(...)`;  ② `STAGES` 追加 0x23;  ③ ⑭ 段 (E8 块) 插到 ⑧ 段前;
 ④ 顶部 docstring 加 ⑧ 指针;  ⑤ ALLOW 追加 2 条 (B 面分类)。
⛔ 幂等: 已拼过的标记存在 ⇒ 直接退出 (不重复插入)。锚点必须**唯一命中**, 否则响亮失败。"""
import io
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
P = os.path.join(HERE, "..", "p7b_readside_bid1c_20261011", "apply_readside_bid1c.py")
BLOCK = io.open(os.path.join(HERE, "EDITS_23_BLOCK.txt"), encoding="utf-8").read()

s = io.open(P, encoding="utf-8", newline="").read()
if "EDITS_23" in s:
    print("ALREADY SPLICED (EDITS_23 已在文件里) ⇒ 不动")
    sys.exit(0)


def sub1(old, new, why):
    global s
    n = s.count(old)
    assert n == 1, "splice: 锚点命中 %d (期望 1): %s" % (n, why)
    s = s.replace(old, new)
    print("OK  %s" % why)


# ---- ① 顶层: 声明 + E8 构造函数 ----
sub1("""EDITS_22 = []          # 阶段 ⑦: 0x21 树 -> 0x22 树 (P9 XDMA MM→AXIS; **BID-only**: 几何不变 71/0x14C)
""",
     """EDITS_22 = []          # 阶段 ⑦: 0x21 树 -> 0x22 树 (P9 XDMA MM→AXIS; **BID-only**: 几何不变 71/0x14C)
EDITS_23 = []          # 阶段 ⑧: 0x22 树 -> 0x23 树 (P9 D4 clr 口径修正; **BID-only**: 几何不变 71/0x14C)
""", "①a EDITS_23 声明")

sub1("""def E7(rel, old, new, n=1):
    EDITS_22.append((rel, old, new, n))
""",
     """def E7(rel, old, new, n=1):
    EDITS_22.append((rel, old, new, n))


def E8(rel, old, new, n=1):
    EDITS_23.append((rel, old, new, n))
""", "①b E8() 构造函数")

# ---- ② STAGES 追加 0x23 ----
sub1("""          ("0x00000022", EDITS_22, "P9 XDMA MM→AXIS (2026-10-11)", 71, 0x14C)]""",
     """          ("0x00000022", EDITS_22, "P9 XDMA MM→AXIS (2026-10-11)", 71, 0x14C),
          ("0x00000023", EDITS_23, "P9 D4 clr 口径修正 (2026-10-12)", 71, 0x14C)]""",
     "② STAGES 追加 0x23")

# ---- ③ ⑭ 段 (E8 块) 插到 ⑧ 段前 ----
HDR = """# ===========================================================================
# ⑭ 阶段 ⑧ (0x22 → 0x23, **P9 D4 clr 口径修正**; **BID-only**, 几何不变 = 71 字 / 0x14C)
#
#   内容 = `rtl/axis_c2h_stream.v` 的 **clr/停流口径修正 (D4 修正轮)** —— clr 改为
#   **丢弃残拍不发拍** (`stop=(!cap_en)||(!en)`, 不含 clr; `wire clr_drop` 三处用);
#   非 clr 停流 = 排空 + 静置 QUIET_N(32) 拍后**只发一拍短尾**; `mv_last` 只对非满拍置位。
#   依据 = 板级 `0x22` 实测 (旧口径 clr 冒 8 B 短拍 ⇒ EOP 早关描述符 ⇒ 宿主首块零填充 +
#   尾截断 + read 超时; 件 `_proj_10g/notes/p9_board_0x22_20261011/runs/D4_BOUNDARY.txt`)。
#   实施 + 门读数 = `_proj_10g/notes/p9_axis_impl_20261011/FIX_REPORT{,2}.md`
#   (real PASS_ALL 100/0 + 12 突变臂全捕获 / p6e 全链 143/0 + 旧口径排练 8 红)。
#   BID 面 = stage ⑦ 的 BID 清单逐条 +1 代 = **本阶段 24 处 / 14 文件** (与 ⑦/⑥ 同名同形):
#     · 几何**一字不动** (71 字 / 未实现地址 0x14C; 快照不扩);
#     · 生成方式 = ⑦ 的 new 侧逐条 +1 代 (生成器 `p9_build_0x23/gen_edits23.py`;
#       old 侧锚点自检 = 24/24 逐字命中盘上现状)。
# ===========================================================================
"""
sub1("""# ===========================================================================
# ⑧ 【读侧加固】三条结构性断言 (照搬 F 轮; 判据必须**走到退出码**)""",
     HDR + BLOCK + """
# ===========================================================================
# ⑧ 【读侧加固】三条结构性断言 (照搬 F 轮; 判据必须**走到退出码**)""",
     "③ ⑭ 段插入 (⑧ 前)")

# ---- ④ 顶部 docstring: 加 ⑧ 指针 ----
sub1("""     **BID-only**, 几何同 ④⑤）/ ⑦ `0x22`（**P9 XDMA MM→AXIS** / **BID-only**, 几何同 ④⑤⑥）——
     **权威阶段表 = 文件中部 `STAGES = [...]`**""",
     """     **BID-only**, 几何同 ④⑤）/ ⑦ `0x22`（**P9 XDMA MM→AXIS** / **BID-only**, 几何同 ④⑤⑥）/
     ⑧ `0x23`（**P9 D4 clr 口径修正** / **BID-only**, 几何同 ④⑤⑥⑦）——
     **权威阶段表 = 文件中部 `STAGES = [...]`**""", "④ docstring ⑧ 指针")

# ---- ⑤ ALLOW 追加 (B 面分类; 核过内容, 见 REPORT) ----
sub1("""    (r"^_proj_10g/notes/p9_build_0x22/",""",
     """    (r"^_proj_10g/notes/p9_board_0x22_20261011/",
     "旧位流读法: P9 板级首测 0x22 现场 (烧的是 **0x22** 归档位流 ⇒ `burn_0x22.sh` 的 "
     "`WANT=c2e48a69…635a`(0x22 位流 sha256)/`EXPBID=0x00000022`/`NW=71` 与 `_tools/run_arm.sh` 的 "
     "`BID=${BID:-0x00000022}`、`final_state.sh` 的 `EXPECT_BID=0x00000022` 都是**那一代的真值**, "
     "由 `WANT` sha256 钉死; 改它反而毁掉该轮取证 —— 登记为 2026-10-12 阶段 ⑧ (0x23) 的新命中)"),
    (r"^_proj_10g/notes/p9_build_0x23/",
     "现役: 本轮 (阶段 ⑧ = 0x23) 构建轮目录 (读数/归档/生成器; 含各代 BID 字符串与各代断言输出)"),
    (r"^_proj_10g/notes/p9_build_0x22/",""", "⑤ ALLOW 追加 2 条")

io.open(P, "w", encoding="utf-8", newline="").write(s)
print("SPLICE DONE; 新文件 %d 字节" % len(s.encode("utf-8")))
