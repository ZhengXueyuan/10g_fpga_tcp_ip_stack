#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""P11 / P1 (0x2A -> 0x2B) 读侧 EDITS 生成器。

目标几何: 83 字 / 未实现地址 0x17C / BID 0x2B; 新增 W76..W82 (ch0 PCS 状态/
事件/LOS + ch0 RX 四计数); MIR 四址 0x150/0x154/0x158/0x15C -> 0x16C/0x170/0x174/0x178。
20 个读侧文件 (与 0x2A 阶段同一清单)。

⛔ 只打印 EDITS_2B + 自检; 不写仓内文件。
"""
import io
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))

ROWS = []


def R(rel, old, new, n=1):
    ROWS.append((rel, old, new, n))


def disk(rel):
    p = os.path.join(REPO, rel.replace("/", os.sep))
    b = io.open(p, "r", encoding="utf-8", errors="replace", newline="").read()
    return b.replace("\r\n", "\n")


# ===========================================================================
# 1) 台架脚本 (j6 / tcpreg): 几何 + 身份 + 档表
# ===========================================================================
for rel in ("_proj_10g/notes/p7b_affinity/j6_r6fix.sh",
            "_proj_10g/notes/p7b_biz_tcpreg/tcpreg_j6.sh"):
    R(rel, "#     ⑦ **几何门 (硬断言)**: ① `NW=${NW:-76}` (p9 孤儿修复; 更早 P9 E12=75",
      "#     ⑦ **几何门 (硬断言)**: ① `NW=${NW:-83}` (P11 P1 ch0 bring-up; 更早 p9 孤儿修复=76 / P9 E12=75")
    R(rel, "\nNW=${NW:-76}\n", "\nNW=${NW:-83}\n")
    R(rel, "EXPECT_BID=${EXPECT_BID:-0x0000002A}   # 2026-10-17 p9 孤儿修复 (76 字; 原 0x00000029 = 0x29 拆刀 / 0x28 = P9 E12 / 0x27 = 换流门 R5)",
      "EXPECT_BID=${EXPECT_BID:-0x0000002B}   # 2026-10-18 P11 P1 ch0 bring-up (83 字; 原 0x0000002A = p9 孤儿修复 / 0x29 = 0x29 拆刀 / 0x28 = P9 E12)")
    R(rel, '  "76|0x0000002A|61 62|p9 孤儿修复',
      '  "83|0x0000002B|61 62|P11 P1 ch0 bring-up (2026-10-18) 83 字 / BID 0x2B (ch0 J7 RX MAC + 76-bit tap + sink; W76 = ch0 PCS 状态 / W77 = ch0 PCS 事件 / W78 = LOS+模式 / W79..W82 = ch0 好帧/载荷字节/FCS 错/丢帧; **几何变**: 76 -> 83 字, 未实现地址 0x160 -> 0x17C)"\n'
      '  "76|0x0000002A|61 62|p9 孤儿修复')

# ===========================================================================
# 2) p7b_snap.sh: 身份 + 几何 + NAME 表
# ===========================================================================
P = "_proj_pcie/p7b_biz/p7b_snap.sh"
R(P, "(**现役 = 76 字 / BID 0x2A**", "(**现役 = 83 字 / BID 0x2B**")
R(P, "#   ⭐ p9 孤儿修复 (2026-10-17): **字长 75 → 76**",
  "#   ⭐ P11 P1 ch0 bring-up (2026-10-18): **字长 76 → 83** (W76..W82 = ch0 PCS/LOS/计数)\n"
  "#      + 身份 0x2A → **0x2B**; 未实现地址 **0x160 → 0x17C** (公式 `0x20+4*NW+16` 不变)。\n"
  "#   ⭐ p9 孤儿修复 (2026-10-17): **字长 75 → 76**")
R(P, "\nNW=${NW:-76}\n", "\nNW=${NW:-83}\n")
R(P, "# 76 ⇒ 0x160 (p9 孤儿修复起; 75 ⇒ 0x15C",
  "# 83 ⇒ 0x17C (P11 P1 起; 76 ⇒ 0x160 (p9 孤儿修复); 75 ⇒ 0x15C")
R(P, "EXPECT_BID=${EXPECT_BID:-0x0000002A}", "EXPECT_BID=${EXPECT_BID:-0x0000002B}")
R(P, "[75]=app_stat_orphan\n)",
  "[75]=app_stat_orphan\n"
  "# ⭐ P11 P1 (2026-10-18): W76..W82 —— ch0 (J7) 状态/事件/LOS + RX 四计数\n"
  "#    (真值源 = wrapper 的 p7bdp 槽 36..38 + ch0 束槽 0..3; b 域 = dp_clk / rx_clk_out_0)\n"
  "[76]=ch0_pcs_status     [77]=ch0_pcs_evt        [78]=ch0_los_mode\n"
  "[79]=ch0_rx_frames      [80]=ch0_rx_bytes       [81]=ch0_rx_crc_err\n"
  "[82]=ch0_rx_drop\n)")

# ===========================================================================
# 3) p6e_snap_check.sh: 身份 + 几何 + WLABEL 表
# ===========================================================================
P = "_proj_pcie/p6e_snap_check.sh"
R(P, "EXPECT_BID=${EXPECT_BID:-0x0000002A}       # ⛔ 2026-10-17 p9 孤儿修复: 原默认 0x00000029 (0x29 拆刀) / 0x28 (P9 E12) / 0x0A (Stage C)",
  "EXPECT_BID=${EXPECT_BID:-0x0000002B}       # ⛔ 2026-10-18 P11 P1 ch0 bring-up: 原默认 0x0000002A (p9 孤儿修复) / 0x29 (0x29 拆刀) / 0x28 (P9 E12) / 0x0A (Stage C)")
R(P, "SNAP_WORDS=${SNAP_WORDS:-76}", "SNAP_WORDS=${SNAP_WORDS:-83}")
R(P, "# 76 ⇒ 0x160 (p9 孤儿修复起; 75 ⇒ 0x15C",
  "# 83 ⇒ 0x17C (P11 P1 起; 76 ⇒ 0x160 (p9 孤儿修复); 75 ⇒ 0x15C")
R(P, ' "app_stat_orphan    (app_ctrl.stat_orphan: 孤儿会话/槽回收计数; p9 孤儿修复)" )',
  ' "app_stat_orphan    (app_ctrl.stat_orphan: 孤儿会话/槽回收计数; p9 孤儿修复)"\n'
  ' # ---- P11 P1 (2026-10-18) 新增 7 字 (76 → 83 字窗口; ch0 J7 bring-up) ----\n'
  ' "ch0_pcs_status     (ch0 PCS 状态束: 与 W39 同位域; bit2=block_lock / bit4=hi_ber)"\n'
  ' "ch0_pcs_evt        (ch0 PCS 事件束: ferr/bad/erv 饱和; vcc=自由计数 mod 256)"\n'
  ' "ch0_los_mode       (LOS 电平/上升沿计数 + SFP2_MODE_B 模式条 bit31)"\n'
  ' "ch0_rx_frames      (ch0 好帧数: tlast && tcrs && !terr)"\n'
  ' "ch0_rx_bytes       (ch0 好帧载荷字节: Σpopc(tkeep))"\n'
  ' "ch0_rx_crc_err     (ch0 MAC 口径 FCS 错帧数)"\n'
  ' "ch0_rx_drop        (ch0 MAC 口径整帧丢)" )')
R(P, "表长必须 == SNAP_WORDS (76),", "表长必须 == SNAP_WORDS (83),")
R(P, "#       P9 E12 再补 W71..W74 —— 四个换流门观测计数器; p9 孤儿修复 再补 W75)。",
  "#       P9 E12 再补 W71..W74 —— 四个换流门观测计数器; p9 孤儿修复 再补 W75;\n"
  "#       P11 P1 再补 W76..W82 —— ch0 J7 状态/事件/LOS + RX 四计数)。")

# ===========================================================================
# 4) p7b_gate4_accept.sh
# ===========================================================================
P = "_proj_pcie/p7b_gate4_accept.sh"
R(P, "EXPECT_BID=${EXPECT_BID:-0x0000002A}      # p9 孤儿修复 = 0x2A (源码 board/wrapper_p4.v 的 BUILD_ID_V; 原 0x29 = 0x29 拆刀 / 0x28 = P9 E12)",
  "EXPECT_BID=${EXPECT_BID:-0x0000002B}      # P11 P1 ch0 bring-up = 0x2B (源码 board/wrapper_p4.v 的 BUILD_ID_V; 原 0x2A = p9 孤儿修复 / 0x29 = 0x29 拆刀 / 0x28 = P9 E12)")
R(P, "SNAP_WORDS=${SNAP_WORDS:-76}", "SNAP_WORDS=${SNAP_WORDS:-83}")
R(P, "# 76 ⇒ 0x160 (p9 孤儿修复起; 75 ⇒ 0x15C",
  "# 83 ⇒ 0x17C (P11 P1 起; 76 ⇒ 0x160 (p9 孤儿修复); 75 ⇒ 0x15C")
R(P, "#    ⇒ 71 字 = **0x14C** (M1 期B); ⭐ P9 E12 起 75 字 = **0x15C**; ⭐ p9 孤儿修复起 76 字 = **0x160**。",
  "#    ⇒ 71 字 = **0x14C** (M1 期B); ⭐ P9 E12 起 75 字 = **0x15C**; ⭐ p9 孤儿修复起 76 字 = **0x160**;\n"
  "#    ⭐ P11 P1 起 83 字 = **0x17C**。")

# ===========================================================================
# 5) p7b_gate4_selftest.sh: 身份 + FAKE_TAIL 新档 (>=83)
# ===========================================================================
P = "_proj_pcie/p7b_gate4_selftest.sh"
R(P, "SW=${SNAP_WORDS:-76}", "SW=${SNAP_WORDS:-83}")
R(P, "现役 = **0x2A** (p9 孤儿修复 76 字", "现役 = **0x2B** (P11 P1 ch0 bring-up 83 字")
R(P, "0X04) V=\\${FAKE_BID:-0x0000002A};;", "0X04) V=\\${FAKE_BID:-0x0000002B};;")
R(P, "#   SW ≥ 76 (2026-10-17 p9 孤儿修复起)",
  "#   SW ≥ 83 (2026-10-18 P11 P1 ch0 bring-up 起) ⇒ 0x150..0x168 也是窗口内的真字\n"
  "#     (W76..W82 = ch0 状态/事件/LOS/四计数), 且未实现地址 = 0x17C;\n"
  "#   SW ≥ 76 (2026-10-17 p9 孤儿修复起)")
_s = disk(P)
_a = _s.index('if [ "$SW" -ge 76 ]; then')
_b = _s.index('elif [ "$SW" -ge 75 ]; then', _a)
_seg76 = _s[_a:_b]
_seg83 = _seg76.replace('if [ "$SW" -ge 76 ]; then', 'if [ "$SW" -ge 83 ]; then', 1)
_seg83 = _seg83.replace(
    "  0X160) V=${FAKE_UNIMPL:-0xffffffff};;   # 未实现地址 (76 字; = 0x20+4*SW+16)'",
    "  0X150) V=0;;     # W76 ch0_pcs_status (P11 P1)\n"
    "  0X154) V=0;;     # W77 ch0_pcs_evt\n"
    "  0X158) V=0;;     # W78 ch0_los_mode\n"
    "  0X15C) V=0;;     # W79 ch0_rx_frames\n"
    "  0X160) V=0;;     # W80 ch0_rx_bytes\n"
    "  0X164) V=0;;     # W81 ch0_rx_crc_err\n"
    "  0X168) V=0;;     # W82 ch0_rx_drop\n"
    "  0X17C) V=${FAKE_UNIMPL:-0xffffffff};;   # 未实现地址 (83 字; = 0x20+4*SW+16)'", 1)
assert _seg83 != _seg76, "selftest >=83 branch transform failed"
_seg76_elif = _seg76.replace('if [ "$SW" -ge 76 ]; then', 'elif [ "$SW" -ge 76 ]; then', 1)
R(P, _seg76, _seg83 + _seg76_elif)

# ===========================================================================
# 6) p7b_gate4_negctrl.sh
# ===========================================================================
P = "_proj_pcie/p7b_gate4_negctrl.sh"
R(P, "# 几何: **76 字 (W0..W75)** —— p9 孤儿修复 (2026-10-17, BID=0x2A / 未实现 0x160);",
  "# 几何: **83 字 (W0..W82)** —— P11 P1 ch0 bring-up (2026-10-18, BID=0x2B / 未实现 0x17C);\n"
  '#       (原句: "76 字 (W0..W75) —— p9 孤儿修复 (2026-10-17, BID=0x2A / 未实现 0x160)" = 历史代, 逐字保留于下)')
R(P, 'echo "BID 0x0000002A"', 'echo "BID 0x0000002B"')
R(P, "p9 孤儿修复: 原 0x29 = 0x29 拆刀", "P11 P1 ch0 bring-up: 原 0x2A = p9 孤儿修复 / 0x29 = 0x29 拆刀")
R(P, "                0 0 0 0 0 0 0 0 0)   # W51..W75",
  "                0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)   # W51..W82")
R(P, "    local i; for (( i = 0; i < 76; i++ ))", "    local i; for (( i = 0; i < 83; i++ ))")
R(P, "awk -v NW=76 ", "awk -v NW=83 ")

# ===========================================================================
# 7) p7b_gate4_livefake.sh
# ===========================================================================
P = "_proj_pcie/p7b_gate4_livefake.sh"
R(P, "        + [0] * 25          # W51..W75 = P7B-BIZ/WU/C/D/E/F + M1 + P9 E12 + p9 孤儿修复 新增字 (accept 只要求窗口齐全 + 无 0xffffffff)",
  "        + [0] * 32          # W51..W82 = P7B-BIZ/WU/C/D/E/F + M1 + P9 E12 + p9 孤儿修复 + P11 P1 新增字 (accept 只要求窗口齐全 + 无 0xffffffff)")
R(P, 'bid = {76: "0x0000002A"', 'bid = {83: "0x0000002B", 76: "0x0000002A"')
R(P, '.get(nw, "0x0000002A")', '.get(nw, "0x0000002B")')

# ===========================================================================
# 8) p6e_snap_selftest_fix2.sh
# ===========================================================================
P = "_proj_pcie/p6e_snap_selftest_fix2.sh"
R(P, "# ⚠️ 假板子的**几何必须与现役 RTL 同代** (= **76 字 / 未实现 0x160**; 2026-10-17 p9 孤儿修复;",
  "# ⚠️ 假板子的**几何必须与现役 RTL 同代** (= **83 字 / 未实现 0x17C**; 2026-10-18 P11 P1;\n"
  "#    原句 = 76 字 / 0x160 (p9 孤儿修复);")
R(P, "0X04) V=\\${FAKE_BID:-0x0000002A};;   # p9 孤儿修复 = 0x2A (⛔ 原 0x29 = 0x29 拆刀 / 0x28 = P9 E12 / 0x0A = Stage C);",
  "0X04) V=\\${FAKE_BID:-0x0000002B};;   # P11 P1 ch0 bring-up = 0x2B (⛔ 原 0x2A = p9 孤儿修复 / 0x29 = 0x29 拆刀 / 0x28 = P9 E12 / 0x0A = Stage C);")
R(P, "  0X14C) V=0x00000000;;",
  "  0X14C) V=0x00000000;;                                       # W75 app_ctrl.stat_orphan (76 字起; p9 孤儿修复)\n"
  "  0X150) V=0x00000000;;                                       # W76 ch0_pcs_status (83 字起; P11 P1)\n"
  "  0X154) V=0x00000000;;                                       # W77 ch0_pcs_evt\n"
  "  0X158) V=0x00000000;;                                       # W78 ch0_los_mode\n"
  "  0X15C) V=0x00000000;;                                       # W79 ch0_rx_frames\n"
  "  0X160) V=0x00000000;;                                       # W80 ch0_rx_bytes\n"
  "  0X164) V=0x00000000;;                                       # W81 ch0_rx_crc_err\n"
  "  0X168) V=0x00000000;;                                       # W82 ch0_rx_drop")
R(P, "  0X160) V=0xffffffff;;",
  "  0X17C) V=0xffffffff;;")

# ===========================================================================
# 9) final_state.sh
# ===========================================================================
P = "_proj_10g/notes/p7b_gate4_3/final_state.sh"
R(P, "UNIMPL=$(rd 0x160)", "UNIMPL=$(rd 0x17C)")
R(P, "# ⚠️ UNIMPL 地址跟窗口宽度走: **76 字 (p9 孤儿修复, 2026-10-17 起) ⇒ 0x160** (word 88; 快照末字后接",
  "# ⚠️ UNIMPL 地址跟窗口宽度走: **83 字 (P11 P1, 2026-10-18 起) ⇒ 0x17C** (word 95; 快照末字后接\n"
  "#     MIR 四字 ⇒ 公式 = 0x20+4*NW+16); 76 字 (p9 孤儿修复) = 0x160 (word 88);")
R(P, "EXPECT_BID=${EXPECT_BID:-0x0000002A}   # ⛔ 2026-10-17 p9 孤儿修复 (76 字); 原 0x29 = 0x29 拆刀",
  "EXPECT_BID=${EXPECT_BID:-0x0000002B}   # ⛔ 2026-10-18 P11 P1 ch0 bring-up (83 字); 原 0x2A = p9 孤儿修复")
R(P, 'echo "W75=$(rd 0x14c)  # p9 孤儿修复: app_ctrl.stat_orphan (孤儿会话/槽回收计数)"',
  'echo "W75=$(rd 0x14c)  # p9 孤儿修复: app_ctrl.stat_orphan (孤儿会话/槽回收计数)"\n'
  'echo "W76=$(rd 0x150) W77=$(rd 0x154) W78=$(rd 0x158)  # P11 P1: ch0 PCS 状态/事件/LOS+mode"\n'
  'echo "W79=$(rd 0x15c) W80=$(rd 0x160) W81=$(rd 0x164) W82=$(rd 0x168)  # P11 P1: ch0 RX 好帧/载荷字节/FCS 错/丢帧"')

# ===========================================================================
# 10) gen_inputs.py
# ===========================================================================
P = "_proj_10g/notes/p7b_gate4_criteria/gen_inputs.py"
R(P, "SNAP_BEGIN / TLATCH / GEN / MAGIC / BID / MARKER / W0..W75 / UNIMPL / SNAP_END",
  "SNAP_BEGIN / TLATCH / GEN / MAGIC / BID / MARKER / W0..W82 / UNIMPL / SNAP_END")
R(P, "0x14C (M1) / 0x15C (P9 E12) / **0x160** (p9 孤儿修复起);",
  "0x14C (M1) / 0x15C (P9 E12) / 0x160 (p9 孤儿修复) / **0x17C** (P11 P1 起);")
R(P, "→ **76 字/0x2A (p9 孤儿修复, 未实现地址 0x15C → 0x160)**。",
  "→ 76 字/0x2A (p9 孤儿修复) → **83 字/0x2B (P11 P1 ch0 bring-up, 未实现地址 0x160 → 0x17C)**。")
R(P, "几何 = **76 字 / BID 0x2A** (p9 孤儿修复, 2026-10-17 同步轮从 75 字/BID 0x29 同步)",
  "几何 = **83 字 / BID 0x2B** (P11 P1 ch0 bring-up, 2026-10-18 同步轮从 76 字/BID 0x2A 同步)")
R(P, "NW_FIX = 76                # 快照字数 (W0..W75; p9 孤儿修复起 —— 原 75 (P9 E12) / 71 (M1) / 70)",
  "NW_FIX = 83                # 快照字数 (W0..W82; P11 P1 起 —— 原 76 (p9 孤儿修复) / 75 (P9 E12) / 71 (M1) / 70)")
R(P, "BID_FIX = 0x0000002A       # 位流身份 (p9 孤儿修复) —— ⛔ 2026-10-17: 原值 0x00000029 (0x29 拆刀)",
  "BID_FIX = 0x0000002B       # 位流身份 (P11 P1 ch0 bring-up) —— ⛔ 2026-10-18: 原值 0x0000002A (p9 孤儿修复)")
R(P, '"""**76 字 (W0..W75)**', '"""**83 字 (W0..W82)**')
R(P, "本夹具现 = **76 字 / BID 0x2A**, accept 默认也已是 76 字 / BID 0x2A",
  "本夹具现 = **83 字 / BID 0x2B**, accept 默认也已是 83 字 / BID 0x2B")

# ===========================================================================
# 11) step0_selfcheck.sh
# ===========================================================================
P = "_proj_10g/notes/p7b_a3_negctl_20261010/step0_selfcheck.sh"
R(P, "(i)  缺省档 (NW=76 / 0x160 / BID 0x2A) 对 D **响亮失败**",
  "(i)  缺省档 (NW=83 / 0x17C / BID 0x2B) 对 D **响亮失败**")
R(P, 'echo "### C-a) 默认档 (NW=76 / 0x160 / BID 0x2A)',
  'echo "### C-a) 默认档 (NW=83 / 0x17C / BID 0x2B)')
R(P, "BID 0x18 != 0x2A", "BID 0x18 != 0x2B")

# ===========================================================================
# 12) 三个 wrapper 源指纹 bat
# ===========================================================================
for P in ("_proj_10g/notes/p7b_biz_win/run_xvlog_wrapper.bat",
          "_proj_10g/notes/p7b_biz_win/run_tb_biz_win.bat",
          "sim/p5wu_p1p2/run_xvlog_wrapper63.bat"):
    R(P, 'findstr /C:"SNAP_NW_P6E = 76"', 'findstr /C:"SNAP_NW_P6E = 83"')

# ===========================================================================
# 13) tb_biz_win.v
# ===========================================================================
P = "_proj_10g/notes/p7b_biz_win/tb_biz_win.v"
R(P, "localparam integer NW = 76;  // = wrapper 的 SNAP_NW_P6E (p9 孤儿修复; 原 75 = P9 E12 / 71 = M1 / 70 = 构建 F)",
  "localparam integer NW = 83;  // = wrapper 的 SNAP_NW_P6E (P11 P1; 原 76 = p9 孤儿修复 / 75 = P9 E12 / 71 = M1)")
R(P, ".BUILD_ID_V(32'h0000002A)", ".BUILD_ID_V(32'h0000002B)")
R(P, 'chk("1b BUILD_ID", v, 32\'h0000002A);', 'chk("1b BUILD_ID", v, 32\'h0000002B);')
R(P, ".ch0_snap_to", ".ch0_snap_to") if False else None

# ===========================================================================
# 14) check_window.py
# ===========================================================================
P = "_proj_10g/notes/p7b_biz_win/check_window.py"
R(P, "    nnew_top = 10                             # ⭐ p9 孤儿修复: W75 (槽 35)\n"
     "                                              #   + W74/W73/W72/W71 (槽 34/33/32/31)\n"
     "                                              #   + W70/W69/W68/W67/W66 (槽 30/29/28/27/26)\n"
     "                                              #   —— 上一代 (P9 E12) 是 9 (W74..W66); W75 落\n"
     "                                              #   在最上面 ⇒ 顶端段 +1 (本条**每代都要按该代接线核**)",
  "    nnew_top = 17                             # ⭐ P11 P1: W82..W76 (p7bdp 槽 38..36 + ch0 束槽 3..0)\n"
  "                                              #   + W75 (槽 35) + W74..W71 (槽 34..31)\n"
  "                                              #   + W70/W69/W68/W67/W66 (槽 30..26)\n"
  "                                              #   —— 上一代 (p9 孤儿修复) 是 10; P1 新增 7 字全落\n"
  "                                              #   在最上面 ⇒ 顶端段 +7 (本条**每代都要按该代接线核**)")
R(P, '"5a 最上面 %d 项 = %s (p7bdp 束槽 %s; p9 孤儿修复)"',
  '"5a 最上面 %d 项 = %s (p7bdp 束槽 %s; P11 P1)"')

# ===========================================================================
# 15) sim TBs: p6e wrapper/counters + p7b_chain
#   ⚠️ 这三件在本实施轮里已由实现 agent **手工同步** (见 REPORT §改动清单):
#      · sim/p6e_pcie/tb_p6e_pcie_wrapper.v: 73 处 MIR 地址 token 0x150/0x154/
#        0x158/0x15C -> 0x16C/0x170/0x174/0x178 (降序替换) + unimpl 0x160 -> 0x17C
#        + BID 0x2B + M1-4 全字数读 75 -> 83 + W76..W82 非 P7B 常 0 断言;
#      · sim/p6e_pcie/tb_p6e_pcie_counters.v: BID 0x2B;
#      · _proj_10g/p7b_chain/sim/tb_p7b_chain.v: 0x17C / 83-word / W76..W82 arms.
#   ⇒ 本阶段不再对它们发 EDITS (在已同步树上会产生"部分命中"的假 FAIL);
#      DEFAULT_SPECS 仍逐文件断言其终值 (漂了就红)。pristine 0x2A 树上应用本阶段时,
#      这三件由实现轮脚本/手工同批落盘 —— 记在 REPORT 的构建前置里。
# ===========================================================================


def selfcheck():
    bad = 0
    for rel, old, new, n in ROWS:
        s = disk(rel)
        k = s.count(old)
        if k != n:
            if k == 0 and new in s:
                continue      # already applied in this (mid-edit) tree
            bad += 1
            print("SELFCHECK FAIL %-58s hits=%d/%d  %s" % (rel, k, n, old.split("\n")[0][:70]))
    print("SELFCHECK(0x2B): %d rows, %d mismatched" % (len(ROWS), bad))
    return bad


def emit():
    print("EDITS_2B = [")
    for rel, old, new, n in ROWS:
        print("    (%r,\n     %r,\n     %r, %d)," % (rel, old, new, n))
    print("]")


if __name__ == "__main__":
    rc = selfcheck()
    if "--emit" in sys.argv:
        emit()
    sys.exit(1 if rc else 0)
