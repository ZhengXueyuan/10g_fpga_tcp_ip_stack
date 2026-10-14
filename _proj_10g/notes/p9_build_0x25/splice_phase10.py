#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把阶段 ⑩ (EDITS_25) 拼进 `apply_readside_bid1c.py`:
  ① 顶层 `EDITS_25 = []` + `def E10(...)`;  ② `STAGES` 追加 0x25;  ③ ⑯ 段 (E10 块) 插到 ⑧ 段前;
  ④ 顶部 docstring 加 ⑩ 指针;  ⑤ ALLOW 追加 4 条 (B 面分类, 见 §ALLOW)。
⛔ 幂等: 已拼过的标记存在 ⇒ 直接退出 (不重复插入)。锚点必须**唯一命中**, 否则响亮失败。"""
import io
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
P = os.path.join(HERE, "..", "p7b_readside_bid1c_20261011", "apply_readside_bid1c.py")
BLOCK = io.open(os.path.join(HERE, "EDITS_25_BLOCK.txt"), encoding="utf-8").read()

s = io.open(P, encoding="utf-8", newline="").read()
if "EDITS_25" in s:
    print("ALREADY SPLICED (EDITS_25 已在文件里) ⇒ 不动")
    sys.exit(0)


def sub1(old, new, why):
    global s
    n = s.count(old)
    assert n == 1, "splice: 锚点命中 %d (期望 1): %s" % (n, why)
    s = s.replace(old, new)
    print("OK  %s" % why)


# ---- ① 顶层: 声明 + E10 构造函数 ----
sub1("""EDITS_24 = []          # 阶段 ⑨: 0x23 树 -> 0x24 树 (P9 URAM 板内缓冲 (修正收口); **BID-only**: 几何不变 71/0x14C)
""",
     """EDITS_24 = []          # 阶段 ⑨: 0x23 树 -> 0x24 树 (P9 URAM 板内缓冲 (修正收口); **BID-only**: 几何不变 71/0x14C)
EDITS_25 = []          # 阶段 ⑩: 0x24 树 -> 0x25 树 (F-3 修复; **BID-only**: 几何不变 71/0x14C)
""", "①a EDITS_25 声明")

sub1("""def E9(rel, old, new, n=1):
    EDITS_24.append((rel, old, new, n))
""",
     """def E9(rel, old, new, n=1):
    EDITS_24.append((rel, old, new, n))


def E10(rel, old, new, n=1):
    EDITS_25.append((rel, old, new, n))
""", "①b E10() 构造函数")

# ---- ② STAGES 追加 0x25 ----
sub1("""          ("0x00000024", EDITS_24, "P9 URAM 板内缓冲 (2026-10-13)", 71, 0x14C)]""",
     """          ("0x00000024", EDITS_24, "P9 URAM 板内缓冲 (2026-10-13)", 71, 0x14C),
          ("0x00000025", EDITS_25, "F-3 修复 (2026-10-15)", 71, 0x14C)]""",
     "② STAGES 追加 0x25")

# ---- ③ ⑯ 段 (E10 块) 插到 ⑧ 段前 ----
HDR = """# ===========================================================================
# ⑯ 阶段 ⑩ (0x24 → 0x25, **F-3 修复**; **BID-only**, 几何不变 = 71 字 / 0x14C)
#
#   内容 = **F-3 (MMCM 失锁重锁) 修复**: `rtl/vlan_strip.v` 新参数 `RESYNC_EN` + `resync` 门
#   + `stat_resync_words` 计数; `board/wrapper_p4.v` 的 `VLAN_STRIP_RESYNC` localparam
#   (**双域开 / 单域关** = 单域路径逐位退化)。
#   依据 = 设计件 `_proj_10g/notes/p9_fix_f3_design_20261014/DESIGN_v2.md` + 实施报告
#   `_proj_10g/notes/p9_impl_f3_20261015/REPORT.md` (G1 门已绿: `sim/f3_resync/`)。
#   BID 面 = stage ⑨ 的 BID 清单逐条 +1 代 = **本阶段 24 处 / 14 文件** (与 ⑨/⑧ 同名同形):
#     · 几何**一字不动** (71 字 / 未实现地址 0x14C; 快照不扩 —— A7/B3 未做);
#     · 生成方式 = ⑨ 的 new 侧逐条 +1 代 (生成器 `p9_build_0x25/gen_edits25.py`;
#       old 侧锚点自检 = 24/24 逐字命中盘上现状)。
# ===========================================================================
"""
sub1("""# ===========================================================================
# ⑧ 【读侧加固】三条结构性断言 (照搬 F 轮; 判据必须**走到退出码**)""",
     HDR + BLOCK + """
# ===========================================================================
# ⑧ 【读侧加固】三条结构性断言 (照搬 F 轮; 判据必须**走到退出码**)""",
     "③ ⑯ 段插入 (⑧ 前)")

# ---- ④ 顶部 docstring: 加 ⑩ 指针 ----
sub1("""     ⑧ `0x23`（**P9 D4 clr 口径修正** / **BID-only**, 几何同 ④⑤⑥⑦）/
     ⑨ `0x24`（**P9 URAM 板内缓冲 (修正收口)** / **BID-only**, 几何同 ④⑤⑥⑦⑧）——
     **权威阶段表 = 文件中部 `STAGES = [...]`**""",
     """     ⑧ `0x23`（**P9 D4 clr 口径修正** / **BID-only**, 几何同 ④⑤⑥⑦）/
     ⑨ `0x24`（**P9 URAM 板内缓冲 (修正收口)** / **BID-only**, 几何同 ④⑤⑥⑦⑧）/
     ⑩ `0x25`（**F-3 修复** / **BID-only**, 几何同 ④⑤⑥⑦⑧⑨）——
     **权威阶段表 = 文件中部 `STAGES = [...]`**""", "④ docstring ⑩ 指针")

# ---- ⑤ ALLOW 追加 (B 面分类; 预扫 + 逐件核, 见 REPORT) ----
sub1("""    (r"^_proj_10g/notes/p9_build_0x24/",""",
     """    (r"^_proj_10g/notes/p9_board_0x24_20261013/",
     "旧位流读法: P9 板级轮 0x24 现场 (2026-10-13; 烧/读的是 **0x24** 归档位流 ⇒ `burn_0x24.sh` 的 "
     "`WANT=e3b07957…f1db`(= 0x24 位流 sha)/`NW=71 EXPECT_BID=0x00000024`、`_tools/run_arm.sh` 的 "
     "`BID=${BID:-0x00000024}`、`_tools/final_state.sh` 的 `EXPECT_BID=0x00000024` 都是**那一代的真值**, "
     "由 WANT 钉死; 改它反而毁掉该轮取证 —— 登记为 2026-10-15 阶段 ⑩ (0x25) 的新命中)"),
    (r"^_proj_10g/notes/p9_uram_ab_20261014/",
     "旧位流读法: URAM 同会话 A/B 轮现场 (2026-10-14; 六烧 **0x23 ↔ 0x24** 交替 ⇒ `_tools/burn_arm.sh` 的 "
     "两臂 `WANT=066a3923…3126`(0x23)/`WANT=e3b07957…f1db`(0x24) + `EXPBID=0x00000023/0x00000024`、"
     "`_tools/run_win_hw.sh` 的 `EXPECT_BID=${EXPECT_BID:-0x00000023}`、`_tools/run_window.sh` 的 "
     "`BID` 传参、`_tools/final_state.sh` 的 `EXPECT_BID=0x00000024` 都是**那两代的真值**, 由 WANT sha 钉死)"),
    (r"^_proj_10g/notes/p9_xverify_kimi_board24_20261013/",
     "旧位流读法: kimi 组板级 0x24 复核轮现场 (2026-10-13; `kx_stats.py` 的 "
     "`EXPECTED_ARGS = \"--bid 0x00000024 …\"` 与 `ab_recheck/kx_ab_burn.py` 的 "
     "`chain_ok = … \"0x00000024\"`(= 首轮烧前板遗留身份) 都是**那一代的真值**, 由被复核的位流钉死)"),
    (r"^_proj_10g/notes/p9_build_0x25/",
     "现役: 本轮 (阶段 ⑩ = 0x25) 构建轮目录 (读数/归档/生成器; 含各代 BID 字符串与各代断言输出)"),
    (r"^_proj_10g/notes/p9_build_0x24/",""", "⑤ ALLOW 追加 4 条")

io.open(P, "w", encoding="utf-8", newline="").write(s)
print("SPLICE DONE; 新文件 %d 字节" % len(s.encode("utf-8")))
