#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""阶段 ⑪ (0x25 → 0x26, P9 **RFC seq 修复**) 的 EDITS_26 生成器。

做法 (照抄 p9_build_0x25/gen_edits25.py): 导入现役 `apply_readside_bidc1.py`, 取 `EDITS_25` 的
**new 侧** (= 盘上现状) 当 ⑪ 的 old 侧; new 侧 = old 侧经**逐条显式变换** (值 0x25→0x26 + 代名
+ 逐代历史链追加)。
⛔ 不做任何通配替换到仓内文件: 本脚本只**打印** E11(...) 块文本 (写 EDITS_26_BLOCK.txt)。
⚠️ 与 0x25 轮的差异: 本轮**逐条显式** (不用 base() 通配) —— 因为 25 树的注释里含大量
   0x1F..0x24 历史链字面, 通配会污染历史。
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

NAME_NEW = "RFC seq 修复"
DATE_NEW = "2026-10-15"


def rep(s, a, b, tag):
    """all-occurrences replace + 必须真的变过的断言 (负对照: 锚点没中 = 硬失败)。"""
    assert s.count(a) >= 1, "entry[%s] 锚点 0 命中: %r" % (tag, a[:60])
    return s.replace(a, b)


# ---- 逐条变换表 (index -> fn; index 与 EDITS_25 序一致, 见 _EDITS25_DUMP.txt) ----

def f0(s):  # [0][1] EXPECT_BID 裸行: 历史链移一格 (保留 3 项)
    return rep(s,
        "EXPECT_BID=${EXPECT_BID:-0x00000025}   # 2026-10-15 F-3 修复 (71 字; 原 0x00000024 = P9 URAM 板内缓冲 / 0x23 = P9 D4 clr 口径修正 / 0x22 = P9 XDMA MM→AXIS)",
        "EXPECT_BID=${EXPECT_BID:-0x00000026}   # 2026-10-15 RFC seq 修复 (71 字; 原 0x00000025 = F-3 修复 / 0x24 = P9 URAM 板内缓冲 / 0x23 = P9 D4 clr 口径修正)",
        "0")


def f2(s):  # [2][3] 档表: 顶部插新行, 旧行逐字保留于下
    return ('  "71|0x00000026|61 62|RFC seq 修复 (2026-10-15) 71 字 / BID 0x26 '
            '(RFC seq 修复: `rtl/tcp_rx.v` 的 `seq_lt = seq_diff[31]` 真差口径 (RFC 793 SEQ_LT); '
            '几何/未实现地址 0x14C 不变)"\n' + s)


def f4(s):  # p7b_snap.sh EXPECT_BID 裸行
    return rep(s, "EXPECT_BID=${EXPECT_BID:-0x00000025}",
                  "EXPECT_BID=${EXPECT_BID:-0x00000026}", "4")


def f5(s):  # p7b_snap.sh 头部"现役"块: 顶部插新块, 旧块逐字保留于下
    s = rep(s, "**现役 = 71 字 / BID 0x25**", "**现役 = 71 字 / BID 0x26**", "5a")
    return rep(s,
        "#   ⭐ F-3 修复 (2026-10-15): 身份 0x24 → **0x25** (**字长/未实现地址不变** = 71 字 / 0x14C;\n"
        "#      `rtl/vlan_strip.v` 的 RESYNC_EN 重同步门 + `board/wrapper_p4.v` 的 `VLAN_STRIP_RESYNC`)。\n",
        "#   ⭐ RFC seq 修复 (2026-10-15): 身份 0x25 → **0x26** (**字长/未实现地址不变** = 71 字 / 0x14C;\n"
        "#      `rtl/tcp_rx.v` 的 `seq_lt = seq_diff[31]` 真差口径 (RFC 793 SEQ_LT), 唯一功能改点 1 行)。\n"
        "#   ⭐ F-3 修复 (2026-10-15): 身份 0x24 → **0x25** (**字长/未实现地址不变** = 71 字 / 0x14C;\n"
        "#      `rtl/vlan_strip.v` 的 RESYNC_EN 重同步门 + `board/wrapper_p4.v` 的 `VLAN_STRIP_RESYNC`)。\n",
        "5b")


def f6(s):  # p6e_snap_check.sh: 历史链移一格
    return rep(s,
        "EXPECT_BID=${EXPECT_BID:-0x00000025}       # ⛔ 2026-10-15 F-3 修复: 原默认 0x00000024 (P9 URAM 板内缓冲) / 0x23 (P9 D4 clr 口径修正) / 0x0A (Stage C)",
        "EXPECT_BID=${EXPECT_BID:-0x00000026}       # ⛔ 2026-10-15 RFC seq 修复: 原默认 0x00000025 (F-3 修复) / 0x24 (P9 URAM 板内缓冲) / 0x0A (Stage C)",
        "6")


def f7(s):  # gate4_accept: 历史链移一格
    return rep(s,
        "EXPECT_BID=${EXPECT_BID:-0x00000025}      # F-3 修复 = 0x25 (源码 board/wrapper_p4.v 的 BUILD_ID_V; 原 0x24 = P9 URAM 板内缓冲 / 0x23 = P9 D4 clr 口径修正)",
        "EXPECT_BID=${EXPECT_BID:-0x00000026}      # RFC seq 修复 = 0x26 (源码 board/wrapper_p4.v 的 BUILD_ID_V; 原 0x25 = F-3 修复 / 0x24 = P9 URAM 板内缓冲)",
        "7")


def f8(s):  # gate4_selftest: 现役注释行 + FAKE_BID 旧口径行 (两处都在同一 hunk)
    s = rep(s,
        "  #    而\"正例必须 0 FAIL\"是本脚本的断言⑤)。现役 = **0x25** (F-3 修复 71 字 —— ⛔ 2026-10-15 同步轮: 原 0x24 = P9 URAM 板内缓冲 /\n"
        "  #    0x23 = P9 D4 clr 口径修正 / 0x22 = P9 XDMA MM→AXIS / 原句 = 现役 17 (构建 C 65 字) / 10 (P7b Stage C)); 跑旧口径时\n"
        "  #    FAKE_BID=0x00000024 (P9 URAM 板内缓冲; SNAP_WORDS=71) / 0x00000023 (P9 D4 clr 口径修正; 71) / 0x00000017 / 0x00000008。\n",
        "  #    而\"正例必须 0 FAIL\"是本脚本的断言⑤)。现役 = **0x26** (RFC seq 修复 71 字 —— ⛔ 2026-10-15 同步轮: 原 0x25 = F-3 修复 /\n"
        "  #    0x24 = P9 URAM 板内缓冲 / 0x23 = P9 D4 clr 口径修正 / 原句 = 现役 17 (构建 C 65 字) / 10 (P7b Stage C)); 跑旧口径时\n"
        "  #    FAKE_BID=0x00000025 (F-3 修复; SNAP_WORDS=71) / 0x00000024 (P9 URAM 板内缓冲; 71) / 0x00000017 / 0x00000008。\n",
        "8")
    return s


def f9(s):  # FAKE_BID 活行
    return rep(s, "  0X04) V=\\${FAKE_BID:-0x00000025};;",
                  "  0X04) V=\\${FAKE_BID:-0x00000026};;", "9")


def f10(s):  # negctrl 几何块首行: 换新 + 旧行降级为"原句"
    return rep(s,
        "# 几何: **71 字 (W0..W70)** —— F-3 修复 (2026-10-15, BID=0x25 / 未实现 0x14C);\n",
        "# 几何: **71 字 (W0..W70)** —— RFC seq 修复 (2026-10-15, BID=0x26 / 未实现 0x14C);\n"
        "#       (原句: \"71 字 (W0..W70) —— F-3 修复 (2026-10-15, BID=0x25 / 未实现 0x14C)\" = 历史代, 逐字保留于下)\n",
        "10")


def f11(s):  # negctrl BID echo: 历史链移一格
    s = rep(s, "echo \"BID 0x00000025\"", "echo \"BID 0x00000026\"", "11a")
    return rep(s,
        "F-3 修复: 原 0x24 = P9 URAM 板内缓冲 / 0x23 = P9 D4 clr 口径修正 / 0x22 = P9 XDMA MM→AXIS",
        "RFC seq 修复: 原 0x25 = F-3 修复 / 0x24 = P9 URAM 板内缓冲 / 0x23 = P9 D4 clr 口径修正",
        "11b")


def f12(s):  # livefake 注释块: 顶部插新块, 旧块 (现役代) → (当时的现役代)
    return ("    #   ⛔ 2026-10-15 (F-3 修复 → RFC seq 修复): 71 字槽的身份 0x25 → **0x26** (字长没动 ⇒ 槽号仍 71);\n"
            "    #      兜底值同改 0x26 (现役代)。⚠️ 本字典**按 NW 索引** ⇒ 读 0x1F/0x20/0x21/0x22/0x23/0x24/0x25 归档位流时须配套回改。\n"
            + rep(s, "兜底值同改 0x25 (现役代)", "兜底值同改 0x25 (当时的现役代)", "12"))


def f13(s):  # livefake bid 字典活行
    return rep(s,
        '    bid = {71: "0x00000025", 70: "0x0000001E", 67: "0x00000019", 66: "0x00000018", 65: "0x00000017", 63: "0x0000000A", 61: "0x00000008", 51: "0x00000007"}.get(nw, "0x00000025")',
        '    bid = {71: "0x00000026", 70: "0x0000001E", 67: "0x00000019", 66: "0x00000018", 65: "0x00000017", 63: "0x0000000A", 61: "0x00000008", 51: "0x00000007"}.get(nw, "0x00000026")',
        "13")


def f14(s):  # p6e_snap_selftest_fix2: 历史链移一格
    return rep(s,
        "  0X04) V=\\${FAKE_BID:-0x00000025};;   # F-3 修复 = 0x25 (⛔ 原 0x24 = P9 URAM 板内缓冲 / 0x23 = P9 D4 clr 口径修正 / 0x0A = Stage C);",
        "  0X04) V=\\${FAKE_BID:-0x00000026};;   # RFC seq 修复 = 0x26 (⛔ 原 0x25 = F-3 修复 / 0x24 = P9 URAM 板内缓冲 / 0x0A = Stage C);",
        "14")


def f15(s):  # final_state.sh: 历史链移一格
    return rep(s,
        "EXPECT_BID=${EXPECT_BID:-0x00000025}   # ⛔ 2026-10-15 F-3 修复 (71 字); 原 0x24 = P9 URAM 板内缓冲",
        "EXPECT_BID=${EXPECT_BID:-0x00000026}   # ⛔ 2026-10-15 RFC seq 修复 (71 字); 原 0x25 = F-3 修复",
        "15")


def f16(s):  # gen_inputs.py docstring: 顶部插新行 + 旧行降级
    return rep(s,
        "         ⚠️ 几何 = **71 字 / BID 0x25** (F-3 修复, 2026-10-15 同步轮从 71 字/BID 0x24 同步)\n"
        "            ⛔ 2026-10-15 F-3 同步: 上一行原写 \"几何 = 71 字 / BID 0x24 (P9 URAM 板内缓冲)\";\n",
        "         ⚠️ 几何 = **71 字 / BID 0x26** (RFC seq 修复, 2026-10-15 同步轮从 71 字/BID 0x25 同步)\n"
        "            ⛔ 2026-10-15 RFC-seq 同步: 上一行原写 \"几何 = 71 字 / BID 0x25 (F-3 修复)\";\n"
        "            ⛔ 2026-10-15 F-3 同步: 那一行的上一行原写 \"几何 = 71 字 / BID 0x24 (P9 URAM 板内缓冲)\";\n",
        "16")


def f17(s):  # 夹具自述行
    # ⚠️ 0x25 轮只改了加粗那一处 (第二处 "accept 默认也已是 …" 未被带粗体 ⇒ 上轮遗留半代)。
    #    本轮两处一起拉正 (第二处是指 accept 脚本的默认值 = 本阶段同步后就是 0x26)。
    return rep(s,
        "本夹具现 = **71 字 / BID 0x25**, accept 默认也已是 71 字 / BID 0x24",
        "本夹具现 = **71 字 / BID 0x26**, accept 默认也已是 71 字 / BID 0x26",
        "17")


def f18(s):  # 逐代链: 末尾追加新格 + 旧格去粗
    return rep(s,
        "→ **71 字/0x25 (F-3 修复, 未实现地址 0x14C 不变)**。",
        "→ 71 字/0x25 (F-3 修复) → **71 字/0x26 (RFC seq 修复, 未实现地址 0x14C 不变)**。",
        "18")


def f19(s):  # BID_FIX: 历史值移一格
    return rep(s,
        "BID_FIX = 0x00000025       # 位流身份 (F-3 修复) —— ⛔ 2026-10-15: 原值 0x00000024 (P9 URAM 板内缓冲)",
        "BID_FIX = 0x00000026       # 位流身份 (RFC seq 修复) —— ⛔ 2026-10-15: 原值 0x00000025 (F-3 修复)",
        "19")


def f20(s):  # counters TB: 历史链移一格
    return rep(s,
        "u_dut.u_pcie_xdma.axil_read(32'h04, v); chk(\"0b BUILD_ID (F-3 修复 71-word = 0x25; 原 71-word=0x24(P9 URAM 板内缓冲) / 0x23(P9 D4 clr 口径修正) / 63-word=9)\", v, 32'h00000025);",
        "u_dut.u_pcie_xdma.axil_read(32'h04, v); chk(\"0b BUILD_ID (RFC seq 修复 71-word = 0x26; 原 71-word=0x25(F-3 修复) / 0x24(P9 URAM 板内缓冲) / 63-word=9)\", v, 32'h00000026);",
        "20")


def f21(s):  # wrapper TB
    return rep(s,
        "u_dut.u_pcie_xdma.axil_read(32'h04, v); chk(\"2  BUILD_ID (F-3 修复 构建 = 0x25)\", v, 32'h00000025);",
        "u_dut.u_pcie_xdma.axil_read(32'h04, v); chk(\"2  BUILD_ID (RFC seq 修复 构建 = 0x26)\", v, 32'h00000026);",
        "21")


def f22(s):  # step0_selfcheck 第 1 处: (i) 缺省档行
    return rep(s,
        "#     (i)  缺省档 (NW=71 / 0x14C / BID 0x25) 对 D **响亮失败** (且失败点只在 BID = 档位错, 不是板错);",
        "#     (i)  缺省档 (NW=71 / 0x14C / BID 0x26) 对 D **响亮失败** (且失败点只在 BID = 档位错, 不是板错);",
        "22")


def f23(s):  # step0_selfcheck 第 2 处: C-a 默认档行
    return rep(s,
        "echo \"### C-a) 默认档 (NW=71 / 0x14C / BID 0x25) —— 对 D 位流: 期望 ID_FAIL 且失败点=身份不符 (BID 0x18 != 0x25)\"",
        "echo \"### C-a) 默认档 (NW=71 / 0x14C / BID 0x26) —— 对 D 位流: 期望 ID_FAIL 且失败点=身份不符 (BID 0x18 != 0x26)\"",
        "23")


OVERRIDES = {
    0: f0, 1: f0,
    2: f2, 3: f2,
    4: f4,
    5: f5,
    6: f6,
    7: f7,
    8: f8,
    9: f9,
    10: f10,
    11: f11,
    12: f12,
    13: f13,
    14: f14,
    15: f15,
    16: f16,
    17: f17,
    18: f18,
    19: f19,
    20: f20,
    21: f21,
    22: f22, 23: f23,
}

rows = []
for i, (rel, old, new, n) in enumerate(m.EDITS_25):
    f = OVERRIDES.get(i)
    assert f is not None, "entry %d 无变换 (逐条显式; 不许漏)" % i
    rows.append((rel, new, f(new), n))

# ---- 自检 1: old 侧 (= EDITS_25 的 new 侧) 必须逐字在盘上 (否则 ⑪ 的锚点会 FAIL) ----
bad = 0
for rel, o, nw, n in rows:
    p = os.path.join(m.REPO, rel.replace("/", os.sep))
    b, nl = m.rd(p)
    cnt = b.decode("utf-8").count(o.replace("\n", nl.decode()))
    if cnt != n:
        bad += 1
        print("SELFCHECK FAIL old-side on-disk hits=%d/%d  %s" % (cnt, n, rel))
print("SELFCHECK old-side: %d 条中 %d 条不匹配 (0 = 全锚得上)" % (len(rows), bad))

# ---- 自检 2: new 侧必须与 old 侧不同; 残留旧值打印出来人工核对 ----
warns = 0
for i, (rel, o, nw, n) in enumerate(rows):
    assert o != nw, "entry %d new == old" % i
    if "0x00000025" in nw or "32'h00000025" in nw:
        warns += 1
        print("WARN entry %d 仍含 8 位旧值 0x00000025 (须为'逐字保留的历史'): %s" % (i, rel))
    if "0x25" in nw.replace("0x00000025", ""):
        warns += 1
        print("WARN entry %d 仍含短旧值 0x25: %s" % (i, rel))
print("SELFCHECK new-side: %d 条 WARN (历史保留 = 预期; 逐条人工核)" % warns)


def vlit(s):
    """Python 单引号字面量 (含 \\n 转义), 与脚本既有风格一致。"""
    out = s.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n")
    return "'" + out + "'"


lines = []
for rel, o, nw, n in rows:
    lines.append("E11(%s," % vlit(rel))
    lines.append("  %s," % vlit(o))
    lines.append("  %s, %d)" % (vlit(nw), n))
block = "\n".join(lines) + "\n"
with open(os.path.join(HERE, "EDITS_26_BLOCK.txt"), "w", encoding="utf-8", newline="\n") as f:
    f.write(block)
print("WROTE EDITS_26_BLOCK.txt: %d 行 / %d 条 / %d 文件"
      % (len(lines), len(rows), len(set(r[0] for r in rows))))
