#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""阶段 ⑦ (0x21 → 0x22, P9 XDMA MM→AXIS) 的 EDITS_22 生成器。

做法: 导入现役 `apply_readside_bid1c.py`, 取 `EDITS_21` 的 **new 侧** (= 盘上现状) 当 ⑦ 的 old 侧;
new 侧 = old 侧经**逐条显式变换** (值 0x21→0x22 + 代名 + 逐代历史链追加)。
⛔ 不做任何通配替换到仓内文件: 本脚本只**打印** E7(...) 块文本。
"""
import importlib.util
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "p7b_readside_bid1c_20261011", "apply_readside_bid1c.py")
spec = importlib.util.spec_from_file_location("arb", SCRIPT)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

NAME_NEW = "P9 XDMA MM→AXIS"
NAME_OLD = "P8-STG 16 B 弹性暂存"


def base(s):
    """通用变换 (大多数条 = 值 + 代名)。"""
    return (s.replace("0x00000021", "0x00000022")
             .replace("32'h00000021", "32'h00000022")
             .replace(NAME_OLD, NAME_NEW)
             .replace("0x21", "0x22"))


def _hist_shift_expect_bid(s):
    return (s.replace("0x00000021", "0x00000022")
             .replace("P8-STG 16 B 弹性暂存 (71 字; 原 0x00000020 = P8 镜像 8 B/拍 / 0x1F = M1 镜像窗 / 0x1E = snd_wnd 守卫)",
                      "P9 XDMA MM→AXIS (71 字; 原 0x00000021 = P8-STG 16 B 弹性暂存 / 0x20 = P8 镜像 8 B/拍 / 0x1F = M1 镜像窗)"))


def _tier_insert(s):
    return ('  "71|0x00000022|61 62|P9 XDMA MM→AXIS (2026-10-11) 71 字 / BID 0x22 '
            '(XDMA 用户接口 MM→AXIS: 新件 `axis_c2h_stream` + 端口表 75→50; 几何/未实现地址 0x14C 不变)"\n' + s)


OVERRIDES = {
    # [0]/[1] EXPECT_BID 裸行: 历史链移一格 (保留 3 项)
    0: _hist_shift_expect_bid,
    1: _hist_shift_expect_bid,
    # [2]/[3] 档表: 顶部插新行, 旧行逐字保留于下
    2: _tier_insert,
    3: _tier_insert,
    # [5] p7b_snap.sh 头部"现役"块: 顶部插新块, 旧块逐字保留于下
    5: lambda s: (s.replace("**现役 = 71 字 / BID 0x21**", "**现役 = 71 字 / BID 0x22**")
                   .replace("#   ⭐ P8-STG 16 B 弹性暂存 (2026-10-11): 身份 0x20 → **0x21** (**字长/未实现地址不变** = 71 字 / 0x14C;\n"
                            "#      采集侧 `app_rx_mirror` 8 B 单槽 → 16 B 字节粒度弹性暂存, 任意相位可续接)。\n",
                            "#   ⭐ P9 XDMA MM→AXIS (2026-10-11): 身份 0x21 → **0x22** (**字长/未实现地址不变** = 71 字 / 0x14C;\n"
                            "#      XDMA 用户接口 MM→AXIS: 新件 `axis_c2h_stream` + 端口表 75→50)。\n"
                            "#   ⭐ P8-STG 16 B 弹性暂存 (2026-10-11): 身份 0x20 → **0x21** (**字长/未实现地址不变** = 71 字 / 0x14C;\n"
                            "#      采集侧 `app_rx_mirror` 8 B 单槽 → 16 B 字节粒度弹性暂存, 任意相位可续接)。\n")),
    # [6] p6e_snap_check.sh: 历史链移一格
    6: lambda s: (s.replace("0x00000021", "0x00000022")
                   .replace("P8-STG 16 B 弹性暂存: 原默认 0x00000020 (P8 镜像 8 B/拍) / 0x1F (M1 镜像窗) / 0x0A (Stage C)",
                            "P9 XDMA MM→AXIS: 原默认 0x00000021 (P8-STG 16 B 弹性暂存) / 0x20 (P8 镜像 8 B/拍) / 0x0A (Stage C)")),
    # [7] gate4_accept: 历史链移一格
    7: lambda s: (s.replace("0x00000021", "0x00000022")
                   .replace("P8-STG 16 B 弹性暂存 = 0x21 (源码 board/wrapper_p4.v 的 BUILD_ID_V; 原 0x20 = P8 镜像 8 B/拍 / 0x1F = M1 镜像窗)",
                            "P9 XDMA MM→AXIS = 0x22 (源码 board/wrapper_p4.v 的 BUILD_ID_V; 原 0x21 = P8-STG 16 B 弹性暂存 / 0x20 = P8 镜像 8 B/拍)")),
    # [8] gate4_selftest: 历史链移一格 + FAKE_BID 旧口径行移一格
    8: lambda s: (s.replace("现役 = **0x21** (P8-STG 16 B 弹性暂存 71 字 —— ⛔ 2026-10-11 同步轮: 原 0x20 = P8 镜像 8 B/拍 /\n  #    0x1F = M1 镜像窗 / 0x1E = snd_wnd 守卫 / 原句",
                            "现役 = **0x22** (P9 XDMA MM→AXIS 71 字 —— ⛔ 2026-10-11 同步轮: 原 0x21 = P8-STG 16 B 弹性暂存 /\n  #    0x20 = P8 镜像 8 B/拍 / 0x1F = M1 镜像窗 / 原句")
                   .replace("    FAKE_BID=0x00000020 (P8 镜像 8 B/拍; SNAP_WORDS=71) / 0x0000001F (M1 镜像窗; 71) / 0x00000017 / 0x00000008。",
                            "    FAKE_BID=0x00000021 (P8-STG 16 B 弹性暂存; SNAP_WORDS=71) / 0x00000020 (P8 镜像 8 B/拍; 71) / 0x00000017 / 0x00000008。")),
    # [9] FAKE_BID 活行
    9: lambda s: s.replace("0x00000021", "0x00000022"),
    # [10] negctrl 几何块: 顶部插新行, 旧行降级为"原句"
    10: lambda s: (s.replace("# 几何: **71 字 (W0..W70)** —— P8-STG 16 B 弹性暂存 (2026-10-11, BID=0x21 / 未实现 0x14C);\n"
                             "#       (原句: \"71 字 (W0..W70) —— P8 镜像 8 B/拍 (2026-10-11, BID=0x20 / 未实现 0x14C)\" = 历史代, 逐字保留于下)\n",
                             "# 几何: **71 字 (W0..W70)** —— P9 XDMA MM→AXIS (2026-10-11, BID=0x22 / 未实现 0x14C);\n"
                             "#       (原句: \"71 字 (W0..W70) —— P8-STG 16 B 弹性暂存 (2026-10-11, BID=0x21 / 未实现 0x14C)\" = 历史代, 逐字保留于下)\n"
                             "#       (原句: \"71 字 (W0..W70) —— P8 镜像 8 B/拍 (2026-10-11, BID=0x20 / 未实现 0x14C)\" = 历史代, 逐字保留于下)\n")),
    # [11] negctrl BID echo: 历史链移一格
    11: lambda s: (s.replace("echo \"BID 0x00000021\"", "echo \"BID 0x00000022\"")
                    .replace("P8-STG 16 B 弹性暂存: 原 0x20 = P8 镜像 8 B/拍 / 0x1F = M1 镜像窗 / 0x1E = snd_wnd 守卫",
                             "P9 XDMA MM→AXIS: 原 0x21 = P8-STG 16 B 弹性暂存 / 0x20 = P8 镜像 8 B/拍 / 0x1F = M1 镜像窗")),
    # [12] livefake 注释块: 顶部插新块, 旧块 (现役代) → (当时的现役代)
    12: lambda s: ("    #   ⛔ 2026-10-11 (P8-STG 16 B 弹性暂存 → P9 XDMA MM→AXIS): 71 字槽的身份 0x21 → **0x22** (字长没动 ⇒ 槽号仍 71);\n"
                   "    #      兜底值同改 0x22 (现役代)。⚠️ 本字典**按 NW 索引** ⇒ 读 0x1F/0x20/0x21 归档位流时须配套回改。\n"
                   + s.replace("兜底值同改 0x21 (现役代)", "兜底值同改 0x21 (当时的现役代)")),
    # [13] livefake bid 字典活行
    13: lambda s: s.replace("0x00000021", "0x00000022"),
    # [14] p6e_snap_selftest_fix2: 历史链移一格
    14: lambda s: (s.replace("0x00000021", "0x00000022")
                    .replace("P8-STG 16 B 弹性暂存 = 0x21 (⛔ 原 0x20 = P8 镜像 8 B/拍 / 0x1F = M1 镜像窗 / 0x0A = Stage C)",
                             "P9 XDMA MM→AXIS = 0x22 (⛔ 原 0x21 = P8-STG 16 B 弹性暂存 / 0x20 = P8 镜像 8 B/拍 / 0x0A = Stage C)")),
    # [15] final_state.sh: 历史链移一格
    15: lambda s: (s.replace("0x00000021", "0x00000022")
                    .replace("P8-STG 16 B 弹性暂存 (71 字); 原 0x20 = P8 镜像 8 B/拍",
                             "P9 XDMA MM→AXIS (71 字); 原 0x21 = P8-STG 16 B 弹性暂存")),
    # [16] gen_inputs.py docstring: 顶部插新行 + 旧行降级
    16: lambda s: (s.replace("⚠️ 几何 = **71 字 / BID 0x21** (P8-STG 16 B 弹性暂存, 2026-10-11 同步轮从 71 字/BID 0x20 同步)\n"
                             "            ⛔ 2026-10-11 P8-STG 同步: 上一行原写 \"几何 = 71 字 / BID 0x20 (P8 镜像 8 B/拍)\";\n",
                             "⚠️ 几何 = **71 字 / BID 0x22** (P9 XDMA MM→AXIS, 2026-10-11 同步轮从 71 字/BID 0x21 同步)\n"
                             "            ⛔ 2026-10-11 P9-AXIS 同步: 上一行原写 \"几何 = 71 字 / BID 0x21 (P8-STG 16 B 弹性暂存)\";\n"
                             "            ⛔ 2026-10-11 P8-STG 同步: 那一行的上一行原写 \"几何 = 71 字 / BID 0x20 (P8 镜像 8 B/拍)\";\n")),
    # [17] 夹具自述行
    17: lambda s: s.replace("**71 字 / BID 0x21**", "**71 字 / BID 0x22**").replace("BID 0x21\n", "BID 0x22\n"),
    # [18] 逐代链: 末尾追加新格 + 旧格去粗
    18: lambda s: s.replace("→ **71 字/0x21 (P8-STG 16 B 弹性暂存, 未实现地址 0x14C 不变)**。",
                            "→ 71 字/0x21 (P8-STG 16 B 弹性暂存) → **71 字/0x22 (P9 XDMA MM→AXIS, 未实现地址 0x14C 不变)**。"),
    # [19] BID_FIX: 历史值移一格
    19: lambda s: (s.replace("BID_FIX = 0x00000021", "BID_FIX = 0x00000022")
                    .replace("位流身份 (P8-STG 16 B 弹性暂存) —— ⛔ 2026-10-11: 原值 0x00000020 (P8 镜像 8 B/拍)",
                             "位流身份 (P9 XDMA MM→AXIS) —— ⛔ 2026-10-11: 原值 0x00000021 (P8-STG 16 B 弹性暂存)")),
    # [20] counters TB: 历史链移一格
    20: lambda s: (s.replace("32'h00000021", "32'h00000022")
                    .replace("P8-STG 16 B 弹性暂存 71-word = 0x21; 原 71-word=0x20(P8 镜像 8 B/拍) / 0x1F(M1 镜像窗) / 63-word=9",
                             "P9 XDMA MM→AXIS 71-word = 0x22; 原 71-word=0x21(P8-STG 16 B 弹性暂存) / 0x20(P8 镜像 8 B/拍) / 63-word=9")),
    # [21] wrapper TB
    21: lambda s: (s.replace("32'h00000021", "32'h00000022")
                    .replace("BUILD_ID (P8-STG 16 B 弹性暂存构建 = 0x21)", "BUILD_ID (P9 XDMA MM→AXIS 构建 = 0x22)")),
    # [22]/[23] step0_selfcheck: 值 + 代名 (描述"缺省档"/"默认档")
    22: lambda s: s.replace("BID 0x21", "BID 0x22"),
    23: lambda s: (s.replace("BID 0x21", "BID 0x22").replace("(BID 0x18 != 0x21)", "(BID 0x18 != 0x22)")),
}

rows = []
for i, (rel, old, new, n) in enumerate(m.EDITS_21):
    f = OVERRIDES.get(i, base)
    rows.append((rel, new, f(new), n))

# ---- 自检 1: old 侧必须逐字在盘上 (否则 ⑦ 的锚点会 FAIL) ----
ov = {}
bad = 0
for rel, o, nw, n in rows:
    p = os.path.join(m.REPO, rel.replace("/", os.sep))
    b, nl = m.rd(p)
    cnt = b.decode("utf-8").count(o.replace("\n", nl.decode()))
    if cnt != n:
        bad += 1
        print("SELFCHECK FAIL old-side on-disk hits=%d/%d  %s" % (cnt, n, rel))
print("SELFCHECK old-side: %d 条中 %d 条不匹配 (0 = 全锚得上)" % (len(rows), bad))

# ---- 自检 2: new 侧必须与 old 侧不同, 且仍含旧值残留检查 ----
for i, (rel, o, nw, n) in enumerate(rows):
    assert o != nw, "entry %d new == old" % i
    if "0x00000021" in nw or "32'h00000021" in nw:
        print("WARN entry %d 仍含 0x00000021 (逐字保留的历史??): %s" % (i, rel))

# ---- 输出 E7(...) 块 ----
def vlit(s):
    """Python 单引号字面量 (含 \n 转义), 与脚本既有风格一致。"""
    out = s.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n")
    return "'" + out + "'"

lines = []
for rel, o, nw, n in rows:
    lines.append("E7(%s," % vlit(rel))
    lines.append("  %s," % vlit(o))
    lines.append("  %s, %d)" % (vlit(nw), n))
block = "\n".join(lines) + "\n"
with open(os.path.join(HERE, "EDITS_22_BLOCK.txt"), "w", encoding="utf-8", newline="\n") as f:
    f.write(block)
print("WROTE EDITS_22_BLOCK.txt: %d 行 / %d 条 / %d 文件"
      % (len(lines), len(rows), len(set(r[0] for r in rows))))
