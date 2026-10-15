#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把阶段 ⑫ (EDITS_27) 拼进 `apply_readside_bid1c.py`:
  ① 顶层 `EDITS_27 = []` + `def E12(...)`;  ② `STAGES` 追加 0x27;  ③ ⑱ 段 (E12 块) 插到 ⑧ 段前;
  ④ 顶部 docstring 加 ⑫ 指针;  ⑤ ALLOW 追加 1 条 (B 面分类, 见 §ALLOW)。
⛔ 幂等: 已拼过的标记存在 ⇒ 直接退出 (不重复插入)。锚点必须**唯一命中**, 否则响亮失败。
（照抄 p9_build_0x26/splice_phase11.py; 逐条锚点已按现读复核。）
"""
import io
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
P = os.path.join(HERE, "..", "p7b_readside_bid1c_20261011", "apply_readside_bid1c.py")
BLOCK = io.open(os.path.join(HERE, "EDITS_27_BLOCK.txt"), encoding="utf-8").read()

s = io.open(P, encoding="utf-8", newline="").read()
if "EDITS_27" in s:
    print("ALREADY SPLICED (EDITS_27 已在文件里) ⇒ 不动")
    sys.exit(0)


def sub1(old, new, why):
    global s
    n = s.count(old)
    assert n == 1, "splice: 锚点命中 %d (期望 1): %s" % (n, why)
    s = s.replace(old, new)
    print("OK  %s" % why)


# ---- ① 顶层: 声明 + E12 构造函数 ----
sub1("""EDITS_26 = []          # 阶段 ⑪: 0x25 树 -> 0x26 树 (RFC seq 修复; **BID-only**: 几何不变 71/0x14C)
""",
     """EDITS_26 = []          # 阶段 ⑪: 0x25 树 -> 0x26 树 (RFC seq 修复; **BID-only**: 几何不变 71/0x14C)
EDITS_27 = []          # 阶段 ⑫: 0x26 树 -> 0x27 树 (换流门 R5 修复; **BID-only**: 几何不变 71/0x14C)
""", "①a EDITS_27 声明")

sub1("""def E11(rel, old, new, n=1):
    EDITS_26.append((rel, old, new, n))
""",
     """def E11(rel, old, new, n=1):
    EDITS_26.append((rel, old, new, n))


def E12(rel, old, new, n=1):
    EDITS_27.append((rel, old, new, n))
""", "①b E12() 构造函数")

# ---- ② STAGES 追加 0x27 ----
sub1("""          ("0x00000026", EDITS_26, "RFC seq 修复 (2026-10-15)", 71, 0x14C)]""",
     """          ("0x00000026", EDITS_26, "RFC seq 修复 (2026-10-15)", 71, 0x14C),
          ("0x00000027", EDITS_27, "换流门 R5 修复 (2026-10-15)", 71, 0x14C)]""",
     "② STAGES 追加 0x27")

# ---- ③ ⑱ 段 (E12 块) 插到 ⑧ 段前 ----
HDR = """# ===========================================================================
# ⑱ 阶段 ⑫ (0x26 → 0x27, **换流门 R5 修复**; **BID-only**, 几何不变 = 71 字 / 0x14C)
#
#   内容 = **换流门 (close-out-then-switch) R5 收尾修复**: `rtl/app_pattern.v` 两处 ——
#     · **裁决 A** (`:1012`, 替换式): E13 守卫 `!(SWC_OK && (closing || sw_apply))` →
#       `!(SWC_OK && (closing || !active))` (`sw_apply ⇒ !active` 支配关系 ⇒ 覆盖
#       post-close 闲置翼 `frm_wait ∧ !active`; 吸收原 `sw_apply` 项)。
#     · **裁决 B** (`:516`): `close_send` 追加 `&& !(SWC_OK && frm_wait)` (frm_wait 冻结态
#       收尾字不再被 S_IDLE 接受门当帧启动收下 ⇒ 消 54 B 空数据帧)。
#   端口面 / 几何**零改动**。
#   依据 = 设计件 `_proj_10g/notes/p9_fix_upok_design_20261014/DESIGN_v2r4.md` (两裁决勘定)
#   + 收尾报告 `_proj_10g/notes/p9_impl_upok_20261015/fix_r5/REPORT_FIX_R5.md`
#   (门 `sim/p9_swc_gate/` 11 臂 8 运行全 RC=0; 支配见证 55 臂次 0 违例;
#   96/96 dump 逐字节退化重申)。
#   BID 面 = stage ⑪ 的 BID 清单逐条 +1 代 = **本阶段 24 处 / 14 文件** (与 ⑪/⑩ 同名同形):
#     · 几何**一字不动** (71 字 / 未实现地址 0x14C; 快照不扩);
#     · 生成方式 = ⑪ 的 new 侧逐条 +1 代 (生成器 `p9_build_0x27/gen_edits27.py`;
#       old 侧锚点自检 = 24/24 逐字命中盘上现状)。
# ===========================================================================
"""
ANCHOR8 = """# ===========================================================================
# ⑧ 【读侧加固】三条结构性断言 (照搬 F 轮; 判据必须**走到退出码**)"""
sub1(ANCHOR8, HDR + BLOCK + "\n" + ANCHOR8, "③ ⑱ 段插入 (⑧ 前)")

# ---- ④ 顶部 docstring: 加 ⑫ 指针 ----
sub1("""     ⑪ `0x26`（**RFC seq 修复** / **BID-only**, 几何同 ④⑤⑥⑦⑧⑨⑩）——
     **权威阶段表 = 文件中部 `STAGES = [...]`**""",
     """     ⑪ `0x26`（**RFC seq 修复** / **BID-only**, 几何同 ④⑤⑥⑦⑧⑨⑩）/
     ⑫ `0x27`（**换流门 R5 修复** / **BID-only**, 几何同 ④⑤⑥⑦⑧⑨⑩⑪）——
     **权威阶段表 = 文件中部 `STAGES = [...]`**""", "④ docstring ⑫ 指针")

# ---- ⑤ ALLOW 追加 (B 面分类; 预扫 + 逐件核, 见 PRESCAN_0x27.txt) ----
sub1("""    (r"^_proj_10g/notes/p9_build_0x26/",""",
     """    (r"^_proj_10g/notes/p9_build_0x27/",
     "现役: 本轮 (阶段 ⑫ = 0x27) 构建轮目录 (读数/归档/生成器; 含各代 BID 字符串与各代断言输出)"),
    (r"^_proj_10g/notes/p9_build_0x26/",""", "⑤ ALLOW 追加 1 条")

io.open(P, "w", encoding="utf-8", newline="").write(s)
print("SPLICE DONE; 新文件 %d 字节" % len(s.encode("utf-8")))
