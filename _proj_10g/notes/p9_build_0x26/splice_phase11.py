#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把阶段 ⑪ (EDITS_26) 拼进 `apply_readside_bid1c.py`:
  ① 顶层 `EDITS_26 = []` + `def E11(...)`;  ② `STAGES` 追加 0x26;  ③ ⑰ 段 (E11 块) 插到 ⑧ 段前;
  ④ 顶部 docstring 加 ⑪ 指针;  ⑤ ALLOW 追加 1 条 (B 面分类, 见 §ALLOW)。
⛔ 幂等: 已拼过的标记存在 ⇒ 直接退出 (不重复插入)。锚点必须**唯一命中**, 否则响亮失败。
（照抄 p9_build_0x25/splice_phase10.py; 逐条锚点已按现读复核。）
"""
import io
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
P = os.path.join(HERE, "..", "p7b_readside_bid1c_20261011", "apply_readside_bid1c.py")
BLOCK = io.open(os.path.join(HERE, "EDITS_26_BLOCK.txt"), encoding="utf-8").read()

s = io.open(P, encoding="utf-8", newline="").read()
if "EDITS_26" in s:
    print("ALREADY SPLICED (EDITS_26 已在文件里) ⇒ 不动")
    sys.exit(0)


def sub1(old, new, why):
    global s
    n = s.count(old)
    assert n == 1, "splice: 锚点命中 %d (期望 1): %s" % (n, why)
    s = s.replace(old, new)
    print("OK  %s" % why)


# ---- ① 顶层: 声明 + E11 构造函数 ----
sub1("""EDITS_25 = []          # 阶段 ⑩: 0x24 树 -> 0x25 树 (F-3 修复; **BID-only**: 几何不变 71/0x14C)
""",
     """EDITS_25 = []          # 阶段 ⑩: 0x24 树 -> 0x25 树 (F-3 修复; **BID-only**: 几何不变 71/0x14C)
EDITS_26 = []          # 阶段 ⑪: 0x25 树 -> 0x26 树 (RFC seq 修复; **BID-only**: 几何不变 71/0x14C)
""", "①a EDITS_26 声明")

sub1("""def E10(rel, old, new, n=1):
    EDITS_25.append((rel, old, new, n))
""",
     """def E10(rel, old, new, n=1):
    EDITS_25.append((rel, old, new, n))


def E11(rel, old, new, n=1):
    EDITS_26.append((rel, old, new, n))
""", "①b E11() 构造函数")

# ---- ② STAGES 追加 0x26 ----
sub1("""          ("0x00000025", EDITS_25, "F-3 修复 (2026-10-15)", 71, 0x14C)]""",
     """          ("0x00000025", EDITS_25, "F-3 修复 (2026-10-15)", 71, 0x14C),
          ("0x00000026", EDITS_26, "RFC seq 修复 (2026-10-15)", 71, 0x14C)]""",
     "② STAGES 追加 0x26")

# ---- ③ ⑰ 段 (E11 块) 插到 ⑧ 段前 ----
HDR = """# ===========================================================================
# ⑰ 阶段 ⑪ (0x25 → 0x26, **RFC seq 修复**; **BID-only**, 几何不变 = 71 字 / 0x14C)
#
#   内容 = **RFC seq 比较修复**: `rtl/tcp_rx.v` 的 `wire seq_lt = (seq32 < ra_rcv_nxt)` →
#   `wire seq_lt = seq_diff[31]` (**真差口径**, RFC 793 SEQ_LT; 唯一功能改点 = 1 行表达式 +
#   注释)。端口面 / 几何**零改动**。
#   依据 = 设计件 `_proj_10g/notes/p9_fix_rfcseq_design_20261014/P7B_BUILDG_RFC_SEQ_DESIGN_v3r2.md`
#   (构建/STA = §7.1; v3r3 只动 §7.2 的不等号) + 实施报告
#   `_proj_10g/notes/p9_impl_rfc_20261015/REPORT.md` (新门 `sim/p3sim_rfc/` 7 臂全绿;
#   rev2 修正轮 = 模型锁存/注释尾回加/守卫同步, 重跑逐字节不变)。
#   BID 面 = stage ⑩ 的 BID 清单逐条 +1 代 = **本阶段 24 处 / 14 文件** (与 ⑩/⑨ 同名同形):
#     · 几何**一字不动** (71 字 / 未实现地址 0x14C; 快照不扩);
#     · 生成方式 = ⑩ 的 new 侧逐条 +1 代 (生成器 `p9_build_0x26/gen_edits26.py`;
#       old 侧锚点自检 = 24/24 逐字命中盘上现状)。
# ===========================================================================
"""
ANCHOR8 = """# ===========================================================================
# ⑧ 【读侧加固】三条结构性断言 (照搬 F 轮; 判据必须**走到退出码**)"""
sub1(ANCHOR8, HDR + BLOCK + "\n" + ANCHOR8, "③ ⑰ 段插入 (⑧ 前)")

# ---- ④ 顶部 docstring: 加 ⑪ 指针 ----
sub1("""     ⑩ `0x25`（**F-3 修复** / **BID-only**, 几何同 ④⑤⑥⑦⑧⑨）——
     **权威阶段表 = 文件中部 `STAGES = [...]`**""",
     """     ⑩ `0x25`（**F-3 修复** / **BID-only**, 几何同 ④⑤⑥⑦⑧⑨）/
     ⑪ `0x26`（**RFC seq 修复** / **BID-only**, 几何同 ④⑤⑥⑦⑧⑨⑩）——
     **权威阶段表 = 文件中部 `STAGES = [...]`**""", "④ docstring ⑪ 指针")

# ---- ⑤ ALLOW 追加 (B 面分类; 预扫 + 逐件核, 见 PRESCAN_0x26.txt) ----
sub1("""    (r"^_proj_10g/notes/p9_build_0x25/",""",
     """    (r"^_proj_10g/notes/p9_build_0x26/",
     "现役: 本轮 (阶段 ⑪ = 0x26) 构建轮目录 (读数/归档/生成器; 含各代 BID 字符串与各代断言输出)"),
    (r"^_proj_10g/notes/p9_build_0x25/",""", "⑤ ALLOW 追加 1 条")

io.open(P, "w", encoding="utf-8", newline="").write(s)
print("SPLICE DONE; 新文件 %d 字节" % len(s.encode("utf-8")))
