#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""阶段 ⑭ (0x28 -> 0x29, 拆刀) + ⑮ (0x29 -> 0x2A, p9 孤儿修复) 的 EDITS 生成器。

来源:
  A. BID 面 24 处 / 14 文件 —— 以 `EDITS_28` 的 new 侧为 ⑭ 的 old 侧, 逐条显式变换;
     ⑮ 的 old 侧 = ⑭ 的 new 侧。⚠️ `EDITS_28[41]` 的 new 侧与盘上现状**不一致** (0x28 审查轮
     E-1 修掉了 `if/elif` 重放行但没回写工具) ⇒ 该行（几何行）在 ⑮ 里改用**盘上现读**的 75 分支。
  B. 几何面 39 处 (仅 ⑮): 75 -> 76 字 / 未实现 0x15C -> 0x160 / 标签表补 W75 /
     MIR 地址整体下移 4 字节 (tb_p6e_pcie_wrapper.v 的 73 处 32'h 常量 + tb_biz_win.v 改派生)。
⛔ 本脚本只**打印** E14/E15 块文本 + 自检; 不写仓内文件。
"""
import importlib.util
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "..", "p7b_readside_bid1c_20261011",
                      "apply_readside_bid1c.py")
SCRIPT = os.path.normpath(SCRIPT)
spec = importlib.util.spec_from_file_location("arb", SCRIPT)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

NEW29 = "0x29 拆刀 (persist 关)"
NEW2A = "p9 孤儿修复"
B29 = "0x00000029"
B2A = "0x0000002A"


def rep(s, a, b, tag):
    assert a in s, "entry[%s] 锚点 0 命中: %r" % (tag, a[:90])
    return s.replace(a, b)


# ===========================================================================
# A-⑭. 0x28 -> 0x29 (BID-only; 几何 75/0x15C 不变)
# ===========================================================================
def r29_0(s):       # [0]/[1] j6 + tcpreg EXPECT_BID 裸行
    return rep(s,
        "EXPECT_BID=${EXPECT_BID:-0x00000028}   # 2026-10-15 P9 E12 观测计数器 (75 字; 原 0x00000027 = 换流门 R5 / 0x26 = RFC seq 修复 / 0x25 = F-3 修复)",
        "EXPECT_BID=${EXPECT_BID:-0x00000029}   # 2026-10-17 0x29 拆刀 (persist 关; 75 字; 原 0x00000028 = P9 E12 / 0x27 = 换流门 R5 / 0x26 = RFC seq 修复)", "0")


def r29_tier(s):    # [2]/[3] 档表: 顶部插新行 (旧行逐字保留于下)
    return ('  "75|0x00000029|61 62|0x29 拆刀 (2026-10-17) 75 字 / BID 0x29 '
            '(PERSIST_EN(1\'b1) -> (1\'b0) 单比特拆刀; LEGACY 两跑幽灵=有: '
            'LEG1 4 STALL+3 相位错 / LEG2 4 STALL+2 相位错; 几何/未实现地址 0x15C 不变)"\n' + s)


def r29_4(s):       # [4] p7b_snap EXPECT_BID
    return rep(s, "EXPECT_BID=${EXPECT_BID:-0x00000028}",
                  "EXPECT_BID=${EXPECT_BID:-0x00000029}", "4")


def r29_5(s):       # [5] p7b_snap 头部现役块
    s = rep(s, "**现役 = 75 字 / BID 0x28**", "**现役 = 75 字 / BID 0x29**", "5a")
    note = ("#   ⭐ 0x29 拆刀 (2026-10-17): 身份 0x28 → **0x29** (**字长/未实现地址不变** = 75 字 / 0x15C;\n"
            "#      `board/wrapper_p4.v` `.PERSIST_EN(1'b1) → (1'b0)` 单比特; 板级 LEGACY 两跑幽灵=有)。\n")
    return rep(s, "#   ⭐ P9 E12 观测计数器", note + "#   ⭐ P9 E12 观测计数器", "5b")


def r29_6(s):       # [6] p6e_snap_check EXPECT_BID
    return rep(s,
        "EXPECT_BID=${EXPECT_BID:-0x00000028}       # ⛔ 2026-10-15 P9 E12 观测计数器: 原默认 0x00000027 (换流门 R5) / 0x26 (RFC seq 修复) / 0x0A (Stage C)",
        "EXPECT_BID=${EXPECT_BID:-0x00000029}       # ⛔ 2026-10-17 0x29 拆刀: 原默认 0x00000028 (P9 E12) / 0x27 (换流门 R5) / 0x0A (Stage C)", "6")


def r29_7(s):       # [7] gate4_accept EXPECT_BID
    return rep(s,
        "EXPECT_BID=${EXPECT_BID:-0x00000028}      # P9 E12 观测计数器 = 0x28 (源码 board/wrapper_p4.v 的 BUILD_ID_V; 原 0x27 = 换流门 R5 / 0x26 = RFC seq 修复)",
        "EXPECT_BID=${EXPECT_BID:-0x00000029}      # 0x29 拆刀 = 0x29 (源码 board/wrapper_p4.v 的 BUILD_ID_V; 原 0x28 = P9 E12 / 0x27 = 换流门 R5)", "7")


def r29_8(s):       # [8] gate4_selftest 现役注释
    s = rep(s, "现役 = **0x28** (P9 E12 观测计数器 75 字", "现役 = **0x29** (0x29 拆刀 75 字", "8a")
    return rep(s, "FAKE_BID=0x00000027 (换流门 R5; SNAP_WORDS=71)",
                  "FAKE_BID=0x00000028 (P9 E12; SNAP_WORDS=75) / 0x00000027 (换流门 R5; 71)", "8b")


def r29_9(s):       # [9] FAKE_BID 活行
    return rep(s, "0X04) V=\\${FAKE_BID:-0x00000028};;",
                  "0X04) V=\\${FAKE_BID:-0x00000029};;", "9")


def r29_10(s):      # [10] negctrl 几何块: 新首行替换旧首行
    old = "# 几何: **75 字 (W0..W74)** —— P9 E12 观测计数器 (2026-10-15, BID=0x28 / 未实现 0x15C);"
    new = ("# 几何: **75 字 (W0..W74)** —— 0x29 拆刀 (2026-10-17, BID=0x29 / 未实现 0x15C);\n"
           '#       (原句: "75 字 (W0..W74) —— P9 E12 观测计数器 (2026-10-15, BID=0x28 / 未实现 0x15C)" = 历史代, 逐字保留于下)')
    return rep(s, old, new, "10")


def r29_11(s):      # [11] negctrl BID echo
    s = rep(s, 'echo "BID 0x00000028"', 'echo "BID 0x00000029"', "11a")
    return rep(s, "P9 E12 观测计数器: 原 0x27 = 换流门 R5",
                  "0x29 拆刀: 原 0x28 = P9 E12 / 0x27 = 换流门 R5", "11b")


def r29_12(s):      # [12] livefake 注释块: 顶部插新块, 旧块"现役代"降级
    s = rep(s, "兜底值同改 0x28 (现役代)", "兜底值同改 0x28 (当时的现役代)", "12a")
    return ("    #   ⛔ 2026-10-17 (P9 E12 -> 0x29 拆刀): 75 字槽 = **0x29** (字长没动 ⇒ 槽号仍 75);\n"
            "    #      兜底值同改 0x29 (当时的现役代)。⚠️ 本字典**按 NW 索引** ⇒ 读 0x28/0x29 归档位流时须配套回改。\n"
            + s)


def r29_13(s):      # [13] livefake bid 字典 (同 NW 换身份)
    s = rep(s, '75: "0x00000028"', '75: "0x00000029"', "13a")
    return rep(s, '.get(nw, "0x00000028")', '.get(nw, "0x00000029")', "13b")


def r29_14(s):      # [14] selftest_fix2 FAKE_BID 活行
    return rep(s,
        "0X04) V=\\${FAKE_BID:-0x00000028};;   # P9 E12 观测计数器 = 0x28 (⛔ 原 0x27 = 换流门 R5 / 0x26 = RFC seq 修复 / 0x0A = Stage C);",
        "0X04) V=\\${FAKE_BID:-0x00000029};;   # 0x29 拆刀 = 0x29 (⛔ 原 0x28 = P9 E12 / 0x27 = 换流门 R5 / 0x0A = Stage C);", "14")


def r29_15(s):      # [15] final_state EXPECT_BID
    return rep(s,
        "EXPECT_BID=${EXPECT_BID:-0x00000028}   # ⛔ 2026-10-15 P9 E12 观测计数器 (75 字); 原 0x27 = 换流门 R5",
        "EXPECT_BID=${EXPECT_BID:-0x00000029}   # ⛔ 2026-10-17 0x29 拆刀 (75 字); 原 0x28 = P9 E12", "15")


def r29_16(s):      # [16] gen_inputs docstring
    old = '         ⚠️ 几何 = **75 字 / BID 0x28** (P9 E12 观测计数器, 2026-10-15 同步轮从 71 字/BID 0x27 同步)'
    new = ('         ⚠️ 几何 = **75 字 / BID 0x29** (0x29 拆刀, 2026-10-17 同步轮从 75 字/BID 0x28 同步)\n'
           '            ⛔ 2026-10-17 0x29 同步: 上一行原写 "几何 = 75 字 / BID 0x28 (P9 E12 观测计数器)";')
    return rep(s, old, new, "16")


def r29_17(s):      # [17] 夹具自述
    return rep(s, "本夹具现 = **75 字 / BID 0x28**, accept 默认也已是 75 字 / BID 0x28",
                  "本夹具现 = **75 字 / BID 0x29**, accept 默认也已是 75 字 / BID 0x29", "17")


def r29_18(s):      # [18] 逐代链
    return rep(s, "→ **75 字/0x28 (P9 E12 观测计数器, 未实现地址 0x14C → 0x15C)**。",
                  "→ 75 字/0x28 (P9 E12 观测计数器) → **75 字/0x29 (0x29 拆刀, 未实现地址 0x15C 不变)**。", "18")


def r29_19(s):      # [19] BID_FIX
    return rep(s,
        "BID_FIX = 0x00000028       # 位流身份 (P9 E12 观测计数器) —— ⛔ 2026-10-15: 原值 0x00000027 (换流门 R5)",
        "BID_FIX = 0x00000029       # 位流身份 (0x29 拆刀) —— ⛔ 2026-10-17: 原值 0x00000028 (P9 E12)", "19")


def r29_20(s):      # [20] counters TB
    return rep(s,
        "u_dut.u_pcie_xdma.axil_read(32'h04, v); chk(\"0b BUILD_ID (P9 E12 观测计数器 75-word = 0x28; 原 71-word=0x27(换流门 R5) / 0x26(RFC seq 修复) / 63-word=9)\", v, 32'h00000028);",
        "u_dut.u_pcie_xdma.axil_read(32'h04, v); chk(\"0b BUILD_ID (0x29 拆刀 75-word = 0x29; 原 75-word=0x28(P9 E12) / 71-word=0x27(换流门 R5) / 63-word=9)\", v, 32'h00000029);", "20")


def r29_21(s):      # [21] wrapper TB
    return rep(s,
        "u_dut.u_pcie_xdma.axil_read(32'h04, v); chk(\"2  BUILD_ID (P9 E12 观测计数器构建 = 0x28)\", v, 32'h00000028);",
        "u_dut.u_pcie_xdma.axil_read(32'h04, v); chk(\"2  BUILD_ID (0x29 拆刀构建 = 0x29)\", v, 32'h00000029);", "21")


def r29_22(s):      # [22] step0 缺省档
    return rep(s, "(i)  缺省档 (NW=75 / 0x15C / BID 0x28) 对 D **响亮失败**",
                  "(i)  缺省档 (NW=75 / 0x15C / BID 0x29) 对 D **响亮失败**", "22")


def r29_23(s):      # [23] step0 默认档
    s = rep(s, 'echo "### C-a) 默认档 (NW=75 / 0x15C / BID 0x28)',
               'echo "### C-a) 默认档 (NW=75 / 0x15C / BID 0x29)', "23a")
    return rep(s, "BID 0x18 != 0x28", "BID 0x18 != 0x29", "23b")


R29 = {0: r29_0, 1: r29_0, 2: r29_tier, 3: r29_tier, 4: r29_4, 5: r29_5,
       6: r29_6, 7: r29_7, 8: r29_8, 9: r29_9, 10: r29_10, 11: r29_11,
       12: r29_12, 13: r29_13, 14: r29_14, 15: r29_15, 16: r29_16,
       17: r29_17, 18: r29_18, 19: r29_19, 20: r29_20, 21: r29_21,
       22: r29_22, 23: r29_23}

# ===========================================================================
# A-⑮. 0x29 -> 0x2A (BID + 几何 75->76 / 0x15C->0x160)
# ===========================================================================
def r2a_0(s):
    return rep(s,
        "EXPECT_BID=${EXPECT_BID:-0x00000029}   # 2026-10-17 0x29 拆刀 (persist 关; 75 字; 原 0x00000028 = P9 E12 / 0x27 = 换流门 R5 / 0x26 = RFC seq 修复)",
        "EXPECT_BID=${EXPECT_BID:-0x0000002A}   # 2026-10-17 p9 孤儿修复 (76 字; 原 0x00000029 = 0x29 拆刀 / 0x28 = P9 E12 / 0x27 = 换流门 R5)", "0")


def r2a_tier(s):
    return ('  "76|0x0000002A|61 62|p9 孤儿修复 (2026-10-17) 76 字 / BID 0x2A '
            '(孤儿会话/槽回收: app_ctrl 三因子失联判据 + 回收通知; slow_cfg_adp o_busy; '
            'W75 = app_ctrl.stat_orphan; **几何变**: 75 -> 76 字, 未实现地址 0x15C -> 0x160)"\n' + s)


def r2a_4(s):
    return rep(s, "EXPECT_BID=${EXPECT_BID:-0x00000029}",
                  "EXPECT_BID=${EXPECT_BID:-0x0000002A}", "4")


def r2a_5(s):
    s = rep(s, "**现役 = 75 字 / BID 0x29**", "**现役 = 76 字 / BID 0x2A**", "5a")
    note = ("#   ⭐ p9 孤儿修复 (2026-10-17): **字长 75 → 76** (W75 = `app_ctrl.stat_orphan` 孤儿回收计数)\n"
            "#      + 身份 0x29 → **0x2A**; 未实现地址 **0x15C → 0x160** (公式 `0x20+4*NW+16` 不变)。\n")
    return rep(s, "#   ⭐ 0x29 拆刀", note + "#   ⭐ 0x29 拆刀", "5b")


def r2a_6(s):
    return rep(s,
        "EXPECT_BID=${EXPECT_BID:-0x00000029}       # ⛔ 2026-10-17 0x29 拆刀: 原默认 0x00000028 (P9 E12) / 0x27 (换流门 R5) / 0x0A (Stage C)",
        "EXPECT_BID=${EXPECT_BID:-0x0000002A}       # ⛔ 2026-10-17 p9 孤儿修复: 原默认 0x00000029 (0x29 拆刀) / 0x28 (P9 E12) / 0x0A (Stage C)", "6")


def r2a_7(s):
    return rep(s,
        "EXPECT_BID=${EXPECT_BID:-0x00000029}      # 0x29 拆刀 = 0x29 (源码 board/wrapper_p4.v 的 BUILD_ID_V; 原 0x28 = P9 E12 / 0x27 = 换流门 R5)",
        "EXPECT_BID=${EXPECT_BID:-0x0000002A}      # p9 孤儿修复 = 0x2A (源码 board/wrapper_p4.v 的 BUILD_ID_V; 原 0x29 = 0x29 拆刀 / 0x28 = P9 E12)", "7")


def r2a_8(s):
    s = rep(s, "现役 = **0x29** (0x29 拆刀 75 字", "现役 = **0x2A** (p9 孤儿修复 76 字", "8a")
    return rep(s, "FAKE_BID=0x00000028 (P9 E12; SNAP_WORDS=75)",
                  "FAKE_BID=0x00000029 (0x29 拆刀; SNAP_WORDS=75) / 0x00000028 (P9 E12; 75)", "8b")


def r2a_9(s):
    return rep(s, "0X04) V=\\${FAKE_BID:-0x00000029};;",
                  "0X04) V=\\${FAKE_BID:-0x0000002A};;", "9")


def r2a_10(s):
    old = "# 几何: **75 字 (W0..W74)** —— 0x29 拆刀 (2026-10-17, BID=0x29 / 未实现 0x15C);"
    new = ("# 几何: **76 字 (W0..W75)** —— p9 孤儿修复 (2026-10-17, BID=0x2A / 未实现 0x160);\n"
           '#       (原句: "75 字 (W0..W74) —— 0x29 拆刀 (2026-10-17, BID=0x29 / 未实现 0x15C)" = 历史代, 逐字保留于下)')
    return rep(s, old, new, "10")


def r2a_11(s):
    s = rep(s, 'echo "BID 0x00000029"', 'echo "BID 0x0000002A"', "11a")
    return rep(s, "0x29 拆刀: 原 0x28 = P9 E12 / 0x27 = 换流门 R5",
                  "p9 孤儿修复: 原 0x29 = 0x29 拆刀 / 0x28 = P9 E12 / 0x27 = 换流门 R5", "11b")


def r2a_12(s):
    s = rep(s, "兜底值同改 0x29 (当时的现役代)", "兜底值同改 0x29 (当时的现役代; 0x29 拆刀)", "12a")
    return ("    #   ⛔ 2026-10-17 (0x29 拆刀 -> p9 孤儿修复): **几何变** —— 76 字槽 = **0x2A**\n"
            "    #      (75 字槽的身份停在 0x29); 兜底值同改 0x2A (现役代)。\n"
            "    #      ⚠️ 本字典**按 NW 索引** ⇒ 读 0x29/0x28 及更早归档位流时须配套回改。\n"
            + s)


def r2a_13(s):
    s = rep(s, 'bid = {75: "0x00000029"', 'bid = {76: "0x0000002A", 75: "0x00000029"', "13a")
    return rep(s, '.get(nw, "0x00000029")', '.get(nw, "0x0000002A")', "13b")


def r2a_14(s):
    return rep(s,
        "0X04) V=\\${FAKE_BID:-0x00000029};;   # 0x29 拆刀 = 0x29 (⛔ 原 0x28 = P9 E12 / 0x27 = 换流门 R5 / 0x0A = Stage C);",
        "0X04) V=\\${FAKE_BID:-0x0000002A};;   # p9 孤儿修复 = 0x2A (⛔ 原 0x29 = 0x29 拆刀 / 0x28 = P9 E12 / 0x0A = Stage C);", "14")


def r2a_15(s):
    return rep(s,
        "EXPECT_BID=${EXPECT_BID:-0x00000029}   # ⛔ 2026-10-17 0x29 拆刀 (75 字); 原 0x28 = P9 E12",
        "EXPECT_BID=${EXPECT_BID:-0x0000002A}   # ⛔ 2026-10-17 p9 孤儿修复 (76 字); 原 0x29 = 0x29 拆刀", "15")


def r2a_16(s):
    old = '         ⚠️ 几何 = **75 字 / BID 0x29** (0x29 拆刀, 2026-10-17 同步轮从 75 字/BID 0x28 同步)'
    new = ('         ⚠️ 几何 = **76 字 / BID 0x2A** (p9 孤儿修复, 2026-10-17 同步轮从 75 字/BID 0x29 同步)\n'
           '            ⛔ 2026-10-17 p9 孤儿修复 同步: 上一行原写 "几何 = 75 字 / BID 0x29 (0x29 拆刀)";')
    return rep(s, old, new, "16")


def r2a_17(s):
    return rep(s, "本夹具现 = **75 字 / BID 0x29**, accept 默认也已是 75 字 / BID 0x29",
                  "本夹具现 = **76 字 / BID 0x2A**, accept 默认也已是 76 字 / BID 0x2A", "17")


def r2a_18(s):
    return rep(s, "→ **75 字/0x29 (0x29 拆刀, 未实现地址 0x15C 不变)**。",
                  "→ 75 字/0x29 (0x29 拆刀) → **76 字/0x2A (p9 孤儿修复, 未实现地址 0x15C → 0x160)**。", "18")


def r2a_19(s):
    return rep(s,
        "BID_FIX = 0x00000029       # 位流身份 (0x29 拆刀) —— ⛔ 2026-10-17: 原值 0x00000028 (P9 E12)",
        "BID_FIX = 0x0000002A       # 位流身份 (p9 孤儿修复) —— ⛔ 2026-10-17: 原值 0x00000029 (0x29 拆刀)", "19")


def r2a_20(s):
    return rep(s,
        "u_dut.u_pcie_xdma.axil_read(32'h04, v); chk(\"0b BUILD_ID (0x29 拆刀 75-word = 0x29; 原 75-word=0x28(P9 E12) / 71-word=0x27(换流门 R5) / 63-word=9)\", v, 32'h00000029);",
        "u_dut.u_pcie_xdma.axil_read(32'h04, v); chk(\"0b BUILD_ID (p9 孤儿修复 76-word = 0x2A; 原 75-word=0x29(0x29 拆刀) / 0x28(P9 E12) / 63-word=9)\", v, 32'h0000002A);", "20")


def r2a_21(s):
    return rep(s,
        "u_dut.u_pcie_xdma.axil_read(32'h04, v); chk(\"2  BUILD_ID (0x29 拆刀构建 = 0x29)\", v, 32'h00000029);",
        "u_dut.u_pcie_xdma.axil_read(32'h04, v); chk(\"2  BUILD_ID (p9 孤儿修复构建 = 0x2A)\", v, 32'h0000002A);", "21")


def r2a_22(s):
    return rep(s, "(i)  缺省档 (NW=75 / 0x15C / BID 0x29) 对 D **响亮失败**",
                  "(i)  缺省档 (NW=76 / 0x160 / BID 0x2A) 对 D **响亮失败**", "22")


def r2a_23(s):
    s = rep(s, 'echo "### C-a) 默认档 (NW=75 / 0x15C / BID 0x29)',
               'echo "### C-a) 默认档 (NW=76 / 0x160 / BID 0x2A)', "23a")
    return rep(s, "BID 0x18 != 0x29", "BID 0x18 != 0x2A", "23b")


R2A = {0: r2a_0, 1: r2a_0, 2: r2a_tier, 3: r2a_tier, 4: r2a_4, 5: r2a_5,
       6: r2a_6, 7: r2a_7, 8: r2a_8, 9: r2a_9, 10: r2a_10, 11: r2a_11,
       12: r2a_12, 13: r2a_13, 14: r2a_14, 15: r2a_15, 16: r2a_16,
       17: r2a_17, 18: r2a_18, 19: r2a_19, 20: r2a_20, 21: r2a_21,
       22: r2a_22, 23: r2a_23}

# ===========================================================================
# B. 几何面 (仅 ⑮): 75 -> 76 / 0x15C -> 0x160 / 补 W75
# ===========================================================================
def g24(s):
    s = rep(s, "`NW=${NW:-75}` (P9 E12 观测计数器; 更早 M1 镜像窗=71",
                "`NW=${NW:-76}` (p9 孤儿修复; 更早 P9 E12=75 / M1 镜像窗=71", "24")
    return s


def g25(s):
    return rep(s, "\nNW=${NW:-75}\n", "\nNW=${NW:-76}\n", "25")


def g29(s):
    return rep(s, "# 75 ⇒ 0x15C (P9 E12 起; 71 ⇒ 0x14C (M1 期B);",
                  "# 76 ⇒ 0x160 (p9 孤儿修复起; 75 ⇒ 0x15C (P9 E12); 71 ⇒ 0x14C (M1 期B);", "29")


def g30(s):
    return rep(s, "[74]=app_stat_up_pend\n)",
                  "[74]=app_stat_up_pend\n"
                  "# ⭐ p9 孤儿修复 (2026-10-17): W75 —— 孤儿回收计数 (真值源 = wrapper 装配段\n"
                  "#    `p7bdp_dout[35*32 +: 32]` / 槽 35)\n"
                  "[75]=app_stat_orphan\n)", "30")


def g31(s):
    return rep(s, "#    ⭐ P9 E12: 现役 NW=75 / MIR 四字在中间 ⇒ **0x15C** = 0x20+4*75+16)。",
                  "#    ⭐ P9 E12: 现役 NW=75 / MIR 四字在中间 ⇒ **0x15C** = 0x20+4*75+16);\n"
                  "#    ⭐ p9 孤儿修复: (**现役 NW=76** / MIR 四字在中间 ⇒ **0x160** = 0x20+4*76+16)。", "31")


def g32(s):
    return rep(s, "SNAP_WORDS=${SNAP_WORDS:-75}", "SNAP_WORDS=${SNAP_WORDS:-76}", "32")


def g33(s):
    return rep(s, "# 75 ⇒ 0x15C (P9 E12 起; 71 ⇒ 0x14C (M1 期B);",
                  "# 76 ⇒ 0x160 (p9 孤儿修复起; 75 ⇒ 0x15C (P9 E12); 71 ⇒ 0x14C (M1 期B);", "33")


def g34(s):
    s = rep(s, "表长必须 == SNAP_WORDS (75),", "表长必须 == SNAP_WORDS (76),", "34a")
    return rep(s, "#       P9 E12 再补 W71..W74 —— 四个换流门观测计数器)。",
                  "#       P9 E12 再补 W71..W74 —— 四个换流门观测计数器; p9 孤儿修复 再补 W75)。", "34b")


def g35(s):
    return rep(s, ' "app_stat_up_pend   (app_pattern.stat_up_pend: A3 异槽登记数 (ev_other_act); P9 E12)" )',
                  ' "app_stat_up_pend   (app_pattern.stat_up_pend: A3 异槽登记数 (ev_other_act); P9 E12)"\n'
                  ' # ---- p9 孤儿修复 (2026-10-17) 新增 1 字 (75 → 76 字窗口; 孤儿回收计数) ----\n'
                  ' "app_stat_orphan    (app_ctrl.stat_orphan: 孤儿会话/槽回收计数; p9 孤儿修复)" )', "35")


def g36(s):
    return rep(s, "SNAP_WORDS=${SNAP_WORDS:-75}", "SNAP_WORDS=${SNAP_WORDS:-76}", "36")


def g37(s):
    return rep(s, "# 75 ⇒ 0x15C (P9 E12 起; 71 ⇒ 0x14C (M1 期B);",
                  "# 76 ⇒ 0x160 (p9 孤儿修复起; 75 ⇒ 0x15C (P9 E12); 71 ⇒ 0x14C (M1 期B);", "37")


def g38(s):
    s = rep(s, "⭐ P9 E12 起 75 字 = **0x15C**。",
                "⭐ P9 E12 起 75 字 = **0x15C**; ⭐ p9 孤儿修复起 76 字 = **0x160**。", "38a")
    return rep(s, "⚠️ 读旧位流 (≤71 字) 必须显式", "⚠️ 读旧位流 (≤75 字) 必须显式", "38b")


def g39(s):
    return rep(s, "SW=${SNAP_WORDS:-75}", "SW=${SNAP_WORDS:-76}", "39")


def g40(s):
    old = "#   SW ≥ 75 (2026-10-15 P9 E12 起) ⇒ 0x13C/0x140/0x144/0x148 也是**窗口内的真字**"
    new = ("#   SW ≥ 76 (2026-10-17 p9 孤儿修复起) ⇒ 0x14C 也是**窗口内的真字** (W75 = app_ctrl.stat_orphan),\n"
           "#     且未实现地址 = 0x160 ⇒ `FAKE_UNIMPL` 挪到 **0x160**;\n"
           + old)
    return rep(s, old, new, "40")


def g41(s):         # 特殊: 输入 = 盘上 75 分支 (不是 EDITS_28[41] 的 stale new)
    raise AssertionError("g41 由 build_edits() 用盘上分支单独构造")


def g42(s):
    return rep(s, "                0 0 0 0 0 0 0 0)   # W51..W74 (M1: W70 = app_rx_mirror.drop_bytes; E12: W71..W74 = 换流门四观测计数器)",
                  "                0 0 0 0 0 0 0 0 0)   # W51..W75 (M1: W70 = app_rx_mirror.drop_bytes; E12: W71..W74 = 换流门四观测计数器; p9 孤儿修复: W75 = app_ctrl.stat_orphan)", "42")


def g43(s):
    return rep(s, "for (( i = 0; i < 75; i++ ))", "for (( i = 0; i < 76; i++ ))", "43")


def g44(s):
    return rep(s, "shift1(){ awk -v NW=75 ", "shift1(){ awk -v NW=76 ", "44")


def g45(s):
    s = rep(s, "        + [0] * 24          # W51..W74 = P7B-BIZ/WU/C/D/E/F + M1 + P9 E12 新增字",
                "        + [0] * 25          # W51..W75 = P7B-BIZ/WU/C/D/E/F + M1 + P9 E12 + p9 孤儿修复 新增字", "45")
    return s


def g46(s):
    old = "# ⚠️ 假板子的**几何必须与现役 RTL 同代** (= **75 字 / 未实现 0x15C**; 2026-10-15 P9 E12 观测计数器;"
    new = ("# ⚠️ 假板子的**几何必须与现役 RTL 同代** (= **76 字 / 未实现 0x160**; 2026-10-17 p9 孤儿修复;\n"
           "#    原句 = 75 字 / 0x15C (P9 E12);")
    return rep(s, old, new, "46")


def g47(s):
    return rep(s,
        "  0X13C) V=0x00000000;;                                       # W71 app_pattern.stat_up_ev (75 字起; P9 E12)\n"
        "  0X140) V=0x00000000;;                                       # W72 app_pattern.stat_sw_req (P9 E12)\n"
        "  0X144) V=0x00000000;;                                       # W73 app_pattern.stat_sw_apply (P9 E12)\n"
        "  0X148) V=0x00000000;;                                       # W74 app_pattern.stat_up_pend (P9 E12)\n"
        "  0X15C) V=0xffffffff;;                                       # 未实现地址 (75 字; = 0x20+4*SW+16)",
        "  0X13C) V=0x00000000;;                                       # W71 app_pattern.stat_up_ev (75 字起; P9 E12)\n"
        "  0X140) V=0x00000000;;                                       # W72 app_pattern.stat_sw_req (P9 E12)\n"
        "  0X144) V=0x00000000;;                                       # W73 app_pattern.stat_sw_apply (P9 E12)\n"
        "  0X148) V=0x00000000;;                                       # W74 app_pattern.stat_up_pend (P9 E12)\n"
        "  0X14C) V=0x00000000;;                                       # W75 app_ctrl.stat_orphan (76 字起; p9 孤儿修复)\n"
        "  0X160) V=0xffffffff;;                                       # 未实现地址 (76 字; = 0x20+4*SW+16)", "47")


def g48(s):
    return rep(s, "UNIMPL=$(rd 0x15c)", "UNIMPL=$(rd 0x160)", "48")


def g49(s):
    old = "# ⚠️ UNIMPL 地址跟窗口宽度走: **75 字 (P9 E12, 2026-10-15 起) ⇒ 0x15C** (word 87; 快照末字后接"
    new = ("# ⚠️ UNIMPL 地址跟窗口宽度走: **76 字 (p9 孤儿修复, 2026-10-17 起) ⇒ 0x160** (word 88; 快照末字后接\n"
           "#     MIR 四字 ⇒ 公式 = 0x20+4*NW+16); 75 字 (P9 E12) = 0x15C (word 87);\n"
           "#     原句: " + old)
    return rep(s, old, new, "49")


def g50(s):
    return rep(s, 'echo "W71=$(rd 0x13c) W72=$(rd 0x140) W73=$(rd 0x144) W74=$(rd 0x148)  # P9 E12: 换流门四观测计数器 (up_ev / sw_req / sw_apply / up_pend)"',
                  'echo "W71=$(rd 0x13c) W72=$(rd 0x140) W73=$(rd 0x144) W74=$(rd 0x148)  # P9 E12: 换流门四观测计数器 (up_ev / sw_req / sw_apply / up_pend)"\n'
                  'echo "W75=$(rd 0x14c)  # p9 孤儿修复: app_ctrl.stat_orphan (孤儿会话/槽回收计数)"', "50")


def g51(s):
    return rep(s, "NW_FIX = 75                # 快照字数 (W0..W74; P9 E12 起 —— 原 71 (M1) / 70)",
                  "NW_FIX = 76                # 快照字数 (W0..W75; p9 孤儿修复起 —— 原 75 (P9 E12) / 71 (M1) / 70)", "51")


def g52(s):
    return rep(s, "W0..W74 / UNIMPL", "W0..W75 / UNIMPL", "52")


def g53(s):
    return rep(s, '"""**75 字 (W0..W74)**', '"""**76 字 (W0..W75)**', "53")


def g54(s):
    return rep(s, "= 0x14C (M1) / **0x15C** (P9 E12 起);",
                  "= 0x14C (M1) / 0x15C (P9 E12) / **0x160** (p9 孤儿修复起);", "54")


def g55(s):
    s = rep(s, "u_dut.u_pcie_xdma.axil_read(32'h15C, v);",
                "u_dut.u_pcie_xdma.axil_read(32'h160, v);", "55a")
    s = rep(s, 'chk("7b 0x15C reads 0 no wrap"', 'chk("7b 0x160 reads 0 no wrap"', "55b")
    return rep(s, "75-word bound (P9 E12: 0x15C = 0x20+4*75+16; 原 71 字/0x14C, 70 字/0x138, 63 字/0x11C; 2026-10-15 E12 订正)",
                  "76-word bound (p9 孤儿修复: 0x160 = 0x20+4*76+16; 原 75 字/0x15C, 71 字/0x14C, 63 字/0x11C; 2026-10-17 订正)", "55c")


def g56(s):
    s = rep(s, 'findstr /C:"SNAP_NW_P6E = 75"', 'findstr /C:"SNAP_NW_P6E = 76"', "56a")
    return rep(s, "is not the 75-word version", "is not the 76-word version", "56b")


def g57(s):
    s = rep(s, 'findstr /C:"SNAP_NW_P6E = 75"', 'findstr /C:"SNAP_NW_P6E = 76"', "57a")
    return rep(s, "wrapper is not 75-word", "wrapper is not 76-word", "57b")


def g59(s):
    return rep(s, "localparam integer NW = 75;  // = wrapper 的 SNAP_NW_P6E (P9 E12; 原 71 = M1 / 70 = 构建 F / 61/63/65/66/67)",
                  "localparam integer NW = 76;  // = wrapper 的 SNAP_NW_P6E (p9 孤儿修复; 原 75 = P9 E12 / 71 = M1 / 70 = 构建 F)", "59")


def g60(s):
    return rep(s, "    nnew_top = 9                              # ⭐ P9 E12: W74/W73/W72/W71 (槽 34/33/32/31)\n"
                  "                                              #   + W70/W69/W68/W67/W66 (槽 30/29/28/27/26)\n"
                  "                                              #   —— 上一代 (M1) 是 5 (W70..W66); E12 四个字全落\n"
                  "                                              #   在最上面 ⇒ 顶端段 +4 (本条**每代都要按该代接线核**)",
                  "    nnew_top = 10                             # ⭐ p9 孤儿修复: W75 (槽 35)\n"
                  "                                              #   + W74/W73/W72/W71 (槽 34/33/32/31)\n"
                  "                                              #   + W70/W69/W68/W67/W66 (槽 30/29/28/27/26)\n"
                  "                                              #   —— 上一代 (P9 E12) 是 9 (W74..W66); W75 落\n"
                  "                                              #   在最上面 ⇒ 顶端段 +1 (本条**每代都要按该代接线核**)", "60")


def g61(s):
    return rep(s, "ntx = 1                                   # 其后的 tx 束项数 (W65) —— 现在排第 10 项",
                  "ntx = 1                                   # 其后的 tx 束项数 (W65) —— 现在排第 11 项", "61")


def g62(s):
    return rep(s, "P9 E12)\"", "p9 孤儿修复)\"", "62")


G2A = {24: g24, 25: g25, 26: g24, 27: g25, 28: g25, 29: g29, 30: g30,
       31: g31, 32: g32, 33: g33, 34: g34, 35: g35, 36: g36, 37: g37,
       38: g38, 39: g39, 40: g40, 41: g41, 42: g42, 43: g43, 44: g44,
       45: g45, 46: g46, 47: g47, 48: g48, 49: g49, 50: g50, 51: g51,
       52: g52, 53: g53, 54: g54, 55: g55, 56: g56, 57: g57, 58: g56,
       59: g59, 60: g60, 61: g61, 62: g62}


def disk_text(rel):
    """盘上文本, 行尾归一为 \n (工具按文件自身的 nl 再转回去)。"""
    p = os.path.join(m.REPO, rel.replace("/", os.sep))
    b, nl = m.rd(p)
    return b.decode("utf-8").replace(nl.decode(), "\n")


def extra_2a():
    """⑮ 的两类**工具清单之外的**常量读者 (任务 C 点名):
      · sim/p6e_pcie/tb_p6e_pcie_wrapper.v 的 73 处 `32'h` MIR 地址常量 (0x28 实施轮改的
        是 75 字代; 本轮再 +1 字 ⇒ 整体下移 4 字节) —— 用**降序 token 替换**避免级联。
      · _proj_10g/notes/p7b_biz_win/tb_biz_win.v 的 BUILD_ID + MIR 地址 —— 改为**由 NW 派生**
        (该件自 M1 起就把 MIR 地址写死, 0x28 只抬了 NW ⇒ 本次一并纠为派生式)。"""
    T = "sim/p6e_pcie/tb_p6e_pcie_wrapper.v"
    rows = [
        # 降序: 新值 = 下一档旧值, 已跑过的档不会再被碰到
        (T, "32'h15C", "32'h160", 2),
        (T, "32'h158", "32'h15C", 16),
        (T, "32'h154", "32'h158", 23),
        (T, "32'h150", "32'h154", 9),
        (T, "32'h14C", "32'h150", 23),
        # 活代码里的判据名 (0x15C ⇒ 0x160)
        (T, 'chk("9  unimpl 0x15C => rresp=SLVERR"', 'chk("9  unimpl 0x160 => rresp=SLVERR"', 1),
        (T, 'chk("M1-5a 0x15C rresp = SLVERR"', 'chk("M1-5a 0x160 rresp = SLVERR"', 1),
        # 顶部注释: 追加 p9 孤儿修复 一代
        (T, "//      0x14C/0x150/0x154/0x158; 共 73 处) + **M1-4 的 71→75 全字数读** +",
            "//      0x14C/0x150/0x154/0x158; 共 73 处) + **M1-4 的 71→75 全字数读** +\n"
            "//      ⭐ 2026-10-17 p9 孤儿修复: 快照 75 → **76 字** ⇒ MIR 块整体再下移 4 B\n"
            "//      (0x14C/0x150/0x154/0x158 → **0x150/0x154/0x158/0x15C**; 未实现 0x15C → **0x160**;\n"
            "//      同一套 73 处 `32'h` 常量按降序 token 替换, 见 readside 轮记录)", 1),
        # ---- tb_biz_win.v ----
        ("_proj_10g/notes/p7b_biz_win/tb_biz_win.v",
         "    localparam integer NW = 76;  // = wrapper 的 SNAP_NW_P6E (p9 孤儿修复; 原 75 = P9 E12 / 71 = M1 / 70 = 构建 F)",
         "    localparam integer NW = 76;  // = wrapper 的 SNAP_NW_P6E (p9 孤儿修复; 原 75 = P9 E12 / 71 = M1 / 70 = 构建 F)\n"
         "    // ⭐ p9 孤儿修复 (2026-10-17): MIR 地址**由 NW 派生** (不再写死; 每代自动跟随)\n"
         "    localparam [31:0] MIR_STATUS_A = 32'h20 + NW*4;       // 0x150 @NW=76 (快照末字后第一格; +16 是 UNIMPL)\n"
         "    localparam [31:0] MIR_DATA_A   = MIR_STATUS_A + 4;    // 0x154\n"
         "    localparam [31:0] MIR_CTRL_A   = MIR_STATUS_A + 8;    // 0x158\n"
         "    localparam [31:0] MIR_DMA_A    = MIR_STATUS_A + 12;   // 0x15C\n"
         "    localparam [31:0] UNIMPL_A     = MIR_STATUS_A + 16;   // 0x160", 1),
        ("_proj_10g/notes/p7b_biz_win/tb_biz_win.v",
         ".BUILD_ID_V(32'h00000008)", ".BUILD_ID_V(32'h0000002A)", 1),
        ("_proj_10g/notes/p7b_biz_win/tb_biz_win.v",
         'chk("1b BUILD_ID", v, 32\'h00000008);', 'chk("1b BUILD_ID", v, 32\'h0000002A);', 1),
        ("_proj_10g/notes/p7b_biz_win/tb_biz_win.v",
         "axil_rd(32'h13C", "axil_rd(MIR_STATUS_A", 3),
        ("_proj_10g/notes/p7b_biz_win/tb_biz_win.v",
         "axil_rd(32'h144", "axil_rd(MIR_CTRL_A", 2),
        ("_proj_10g/notes/p7b_biz_win/tb_biz_win.v",
         "axil_wr(32'h144", "axil_wr(MIR_CTRL_A", 2),
        ("_proj_10g/notes/p7b_biz_win/tb_biz_win.v",
         "axil_rd(32'h14C", "axil_rd(UNIMPL_A", 1),
        ("_proj_10g/notes/p7b_biz_win/tb_biz_win.v",
         "axil_wr(32'h14C", "axil_wr(UNIMPL_A", 1),
        ("_proj_10g/notes/p7b_biz_win/tb_biz_win.v",
         "axil_rd(32'h148", "axil_rd(MIR_DMA_A", 1),
        # 遗留硬编码: 11c 空读 MIR_DATA 还写着 M1 时代的 0x140 (即 W72)
        ("_proj_10g/notes/p7b_biz_win/tb_biz_win.v",
         "axil_rd(32'h140, v, resp);", "axil_rd(MIR_DATA_A, v, resp);", 1),
        # 遗留 stale 期望: MIR_STATUS.ver 停在 3 (P9 已 4)
        ("_proj_10g/notes/p7b_biz_win/tb_biz_win.v",
         'chk("11a MIR_STATUS: level==0 / ver==3 / cap==0 / unf==0 / src_sel==0",\n'
         '            {v[31:23], v[22:19], v[18], v[16], v[15:0]}, {9\'d0, 4\'d3, 1\'b0, 1\'b0, 16\'d0});',
         'chk("11a MIR_STATUS: level==0 / ver==4 / cap==0 / unf==0 / src_sel==0",\n'
         '            {v[31:23], v[22:19], v[18], v[16], v[15:0]}, {9\'d0, 4\'d4, 1\'b0, 1\'b0, 16\'d0});', 1),
        ("_proj_10g/notes/p7b_biz_win/tb_biz_win.v",
         ".mir_dma_cnt(32'hD0C0_0148)", ".mir_dma_cnt(32'hD0C0_015C)", 1),
        ("_proj_10g/notes/p7b_biz_win/tb_biz_win.v",
         'chk("11j MIR_DMA_CNT @0x148 读回 tie-off 常数 (地址映射对)", v, 32\'hD0C0_0148);',
         'chk("11j MIR_DMA_CNT @0x15C 读回 tie-off 常数 (地址映射对)", v, 32\'hD0C0_015C);', 1),
        ("_proj_10g/notes/p7b_biz_win/tb_biz_win.v",
         'chk("11h 读 0x14C (未实现) 回 0"', 'chk("11h 读 0x160 (未实现) 回 0"', 1),
        ("_proj_10g/notes/p7b_biz_win/tb_biz_win.v",
         'chkresp("11h2 读 0x14C rresp = SLVERR"', 'chkresp("11h2 读 0x160 rresp = SLVERR"', 1),
        ("_proj_10g/notes/p7b_biz_win/tb_biz_win.v",
         'chkresp("11i 写 0x14C = SLVERR', 'chkresp("11i 写 0x160 = SLVERR', 1),
        ("_proj_10g/notes/p7b_biz_win/tb_biz_win.v",
         'chk("6a 未实现地址 (0x20+4*NW+16 = 0x14C @NW=71) 回 0"',
         'chk("6a 未实现地址 (0x20+4*NW+16 = 0x160 @NW=76) 回 0"', 1),
    ]
    return rows


def build_edits():
    rows29, rows2a = [], []
    for i, (rel, _o, new28, n) in enumerate(m.EDITS_28[:24]):
        new29 = R29[i](new28)
        new2a = R2A[i](new29)
        rows29.append((rel, new28, new29, n))
        rows2a.append((rel, new29, new2a, n))
    # 几何行 (24..62) 只在 ⑮
    for i, (rel, _o, new28, n) in enumerate(m.EDITS_28):
        if i < 24:
            continue
        if i == 41:
            # 盘上现读的 75 分支 (0x28 审查 E-1 修复后的真身; EDITS_28[41].new 是 stale)
            s = disk_text(rel)
            start = 'if [ "$SW" -ge 75 ]; then'
            end = 'elif [ "$SW" -ge 71 ]; then'
            a = s.index(start)
            b = s.index(end, a)
            seg75 = s[a:b]
            seg76 = seg75.replace('if [ "$SW" -ge 75 ]; then',
                                  'if [ "$SW" -ge 76 ]; then', 1)
            seg76 = seg76.replace(
                "  0X15C) V=${FAKE_UNIMPL:-0xffffffff};;   # 未实现地址 (75 字; = 0x20+4*SW+16)",
                "  0X14C) V=0;;     # W75 app_ctrl.stat_orphan (孤儿回收计数; p9 孤儿修复)\n"
                "  0X160) V=${FAKE_UNIMPL:-0xffffffff};;   # 未实现地址 (76 字; = 0x20+4*SW+16)", 1)
            assert seg76 != seg75, "seg76 未变换"
            seg75_elif = seg75.replace('if [ "$SW" -ge 75 ]; then',
                                       'elif [ "$SW" -ge 75 ]; then', 1)
            rows2a.append((rel, seg75, seg76 + seg75_elif, 1))
            continue
        new2a = G2A[i](new28)
        rows2a.append((rel, new28, new2a, n))
    rows2a += extra_2a()
    return rows29, rows2a


def selfcheck(rows, name):
    bad = 0
    for rel, old, new, n in rows:
        s = disk_text(rel)
        k = s.count(old)
        if k != n:
            bad += 1
            print("SELFCHECK FAIL %-4s %-56s hits=%d/%d  %s"
                  % (name, rel, k, n, old.split("\n")[0][:60]))
    print("SELFCHECK(%s): %d 条中 %d 条不匹配" % (name, len(rows), bad))
    return bad


def emit(rows, listname):
    print("%s = [" % listname)
    for rel, old, new, n in rows:
        print("    (%r,\n     %r,\n     %r, %d)," % (rel, old, new, n))
    print("]")


if __name__ == "__main__":
    rows29, rows2a = build_edits()
    bad1 = selfcheck(rows29, "0x29")
    # 0x2A 的 old 侧 = 0x29 的 new 侧 (链式视图, 不在盘上) ⇒ 用内存 overlay 自检
    ov = {rel: disk_text(rel) for rel, _o, _n, _c in rows29}
    for rel, old, new, n in rows29:
        cur = ov[rel]
        assert cur.count(old) == n, "chain29 %s hits=%d/%d" % (rel, cur.count(old), n)
        ov[rel] = cur.replace(old, new)
    bad2 = 0
    for rel, old, new, n in rows2a:
        cur = ov[rel] if rel in ov else disk_text(rel)
        k = cur.count(old)
        if k != n:
            bad2 += 1
            print("SELFCHECK FAIL 0x2A %-56s hits=%d/%d  %s" % (rel, k, n, old.split("\n")[0][:60]))
        else:
            ov[rel] = cur.replace(old, new)
    print("SELFCHECK(0x2A 链式视图): %d 条中 %d 条不匹配" % (len(rows2a), bad2))
    if "--emit" in sys.argv:
        emit(rows29, "EDITS_29")
        emit(rows2a, "EDITS_2A")
