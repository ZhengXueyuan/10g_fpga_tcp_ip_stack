#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把阶段 ⑬ (EDITS_28) 拼进 `apply_readside_bid1c.py`:
  ① 顶层 `EDITS_28 = []` + `def E13(...)`;  ② `STAGES` 追加 0x28 (nw=75 / unimpl=0x15C);
  ③ ⑲ 段 (E13 块) 插到 ⑧ 段前;  ④ 顶部 docstring 加 ⑬ 指针;
  ⑤ ALLOW 追加 (本轮轮目录 + E12 实施轮目录) + 订正 check_window 的 ALLOW 措辞。
⛔ 幂等: 已拼过的标记存在 ⇒ 直接退出 (不重复插入)。锚点必须**唯一命中**, 否则响亮失败。
（照抄 p9_build_0x27/splice_phase12.py; 逐条锚点已按现读复核。）
"""
import io
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
P = os.path.join(HERE, "..", "p7b_readside_bid1c_20261011", "apply_readside_bid1c.py")
BLOCK = io.open(os.path.join(HERE, "EDITS_28_BLOCK.txt"), encoding="utf-8").read()

s = io.open(P, encoding="utf-8", newline="").read()
if "EDITS_28" in s:
    print("ALREADY SPLICED (EDITS_28 已在文件里) ⇒ 不动")
    sys.exit(0)


def sub1(old, new, why):
    global s
    n = s.count(old)
    assert n == 1, "splice: 锚点命中 %d (期望 1): %s" % (n, why)
    s = s.replace(old, new)
    print("OK  %s" % why)


# ---- ① 顶层: 声明 + E13 构造函数 ----
sub1("""EDITS_27 = []          # 阶段 ⑫: 0x26 树 -> 0x27 树 (换流门 R5 修复; **BID-only**: 几何不变 71/0x14C)
""",
     """EDITS_27 = []          # 阶段 ⑫: 0x26 树 -> 0x27 树 (换流门 R5 修复; **BID-only**: 几何不变 71/0x14C)
EDITS_28 = []          # 阶段 ⑬: 0x27 树 -> 0x28 树 (P9 E12 观测计数器; **BID + 几何**: 71->75 字 / 0x14C->0x15C)
""", "①a EDITS_28 声明")

sub1("""def E12(rel, old, new, n=1):
    EDITS_27.append((rel, old, new, n))
""",
     """def E12(rel, old, new, n=1):
    EDITS_27.append((rel, old, new, n))


def E13(rel, old, new, n=1):
    EDITS_28.append((rel, old, new, n))
""", "①b E13() 构造函数")

# ---- ② STAGES 追加 0x28 ----
sub1("""          ("0x00000027", EDITS_27, "换流门 R5 修复 (2026-10-15)", 71, 0x14C)]""",
     """          ("0x00000027", EDITS_27, "换流门 R5 修复 (2026-10-15)", 71, 0x14C),
          ("0x00000028", EDITS_28, "P9 E12 观测计数器 (2026-10-15)", 75, 0x15C)]""",
     "② STAGES 追加 0x28")

# ---- ③ ⑲ 段 (E13 块) 插到 ⑧ 段前 ----
HDR = """# ===========================================================================
# ⑲ 阶段 ⑬ (0x27 → 0x28, **P9 E12 观测计数器**; **BID + 几何**)
#
#   内容 = **换流门四只观测计数器** (`rtl/app_pattern.v` `stat_up_ev` / `stat_sw_req` /
#   `stat_sw_apply` / `stat_up_pend`) 接进快照 **W71..W74** (装配 **MSB 端 +4 项**;
#   `SNAP_P7BDP_NW` 31 → 35)。**纯观测** (4×32 FF + 常量门), 用途 = "触发条件本身"研究的
#   关键仪器 + K0 判据"负对照未现形"的破题件。
#   依据 = `_proj_10g/notes/p9_impl_e12_20261015/REPORT.md` (SWC 门 8 运行全 RC=0 /
#   p6e 全链 148/0 / counters 26/0 / 本代窗口静态核对 PASS=96 / 96/96 dump 逐字节退化重申)。
#   ⛔ **几何变** (M1 以来首例): 快照 **71 → 75 字** / 未实现地址 **0x14C → 0x15C**
#      (公式 `0x20+4*NW+16` 不变 —— 快照末字后仍是 MIR 四字) ⇒ 本阶段 = **BID + 几何**:
#      · **BID 面 24 处 / 14 文件** = 阶段 ⑫ 的清单逐条 +1 代 (生成器
#        `p9_build_0x28/gen_edits28.py` 的 f0..f23; old 侧自检 24/24 逐字命中盘上现状);
#      · **几何面 39 处 / 12 文件** = NW 默认值 (75) + 未实现地址 (0x15C) + 标签表 (W71..W74):
#        `j6_r6fix.sh`/`tcpreg_j6.sh` (NW= / 几何门注) · `p7b_snap.sh` (NW= / UNIMPL 注 /
#        `NAME[] += [71..74]`) · `p6e_snap_check.sh` (SNAP_WORDS= / UNIMPL 注 /
#        `WLABEL += W71..W74`) · `p7b_gate4_accept.sh` (SNAP_WORDS= / UNIMPL) ·
#        `p7b_gate4_selftest.sh` (SW= / 注 / **新 FAKE_TAIL 分支** `-ge 75`) ·
#        `p7b_gate4_negctrl.sh` (`V=` +8 项 / 循环界 75 / `awk -v NW=75`) ·
#        `p7b_gate4_livefake.sh` (`[0]*20 → [0]*24`) · `p6e_snap_selftest_fix2.sh` (假板地址表) ·
#        `final_state.sh` (UNIMPL 读址 0x15c / W71..W74 读数行) · `gen_inputs.py` (NW_FIX / 快照行) ·
#        `_proj_10g/p7b_chain/sim/tb_p7b_chain.v` (0x15C 界) ·
#        三个指纹 bat (`SNAP_NW_P6E = 75`) · `tb_biz_win.v` (NW=75) ·
#        `check_window.py` (nnew_top 5→9)。
# ===========================================================================
"""
ANCHOR8 = """# ===========================================================================
# ⑧ 【读侧加固】三条结构性断言 (照搬 F 轮; 判据必须**走到退出码**)"""
sub1(ANCHOR8, HDR + BLOCK + "\n" + ANCHOR8, "③ ⑲ 段插入 (⑧ 前)")

# ---- ④ 顶部 docstring: 加 ⑬ 指针 ----
sub1("""     ⑫ `0x27`（**换流门 R5 修复** / **BID-only**, 几何同 ④⑤⑥⑦⑧⑨⑩⑪）——
     **权威阶段表 = 文件中部 `STAGES = [...]`**""",
     """     ⑫ `0x27`（**换流门 R5 修复** / **BID-only**, 几何同 ④⑤⑥⑦⑧⑨⑩⑪）/
     ⑬ `0x28`（**P9 E12 观测计数器** / **BID + 几何**: 71→75 字 / 0x14C→0x15C）——
     **权威阶段表 = 文件中部 `STAGES = [...]`**""", "④ docstring ⑬ 指针")

# ---- ⑤ ALLOW 追加 (B 面分类; 预扫 + 逐件核, 见 PRESCAN_0x28.txt) ----
sub1("""    (r"^_proj_10g/notes/p9_build_0x27/",""",
     """    (r"^_proj_10g/notes/p9_build_0x28/",
     "现役: 本轮 (阶段 ⑬ = 0x28) 构建轮目录 (读数/归档/生成器; 含各代 BID 字符串与各代断言输出)"),
    (r"^_proj_10g/notes/p9_impl_e12_20261015/",
     "现役: E12 实施轮目录 (4 只观测计数器的落地取证; 含 `check_window_e12.py` = 本代副本 "
     "(nnew_top=9) 与各代断言输出 —— 与 0x28 同步后的原件同值, 属该轮取证, 只登记不动)"),
    (r"^_proj_10g/notes/p9_build_0x27/",""", "⑤ ALLOW 追加 2 条")

# ---- ⑤b 订正 check_window 的 ALLOW 措辞 (几何本轮**动**了) ----
sub1('''     "现役: 窗口几何守卫 (几何本轮不动; 其 nnew_top 由 ⑧-C 派生式断言)"),''',
     '''     "现役: 窗口几何守卫 (⚠️ P9 E12 起几何**动**了: 71→75 ⇒ 本件已成 EDITS 目标; "
     "其 nnew_top 由 ⑧-C 派生式断言)"),''', "⑤b check_window ALLOW 措辞订正")

io.open(P, "w", encoding="utf-8", newline="").write(s)
print("SPLICE DONE; 新文件 %d 字节" % len(s.encode("utf-8")))
