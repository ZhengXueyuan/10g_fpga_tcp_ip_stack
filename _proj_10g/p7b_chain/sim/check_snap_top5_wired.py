#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_snap_top5_wired.py — P11 F-21 静态结构门 (源码面; 0x2D backstop-2 = TOPN 2).

背景 (0x2C 构建布后实测, 见 `_proj_10g/notes/p11_build_0x2C_20261018/
README_FOR_TL.md` §5):
  `board/wrapper_p4.v` 里 `snap_dout_all` 顶部 5 项 (W87..W83) 曾直接接
  `w8x_snap = w8x_dp` (= dp 域寄存器输出) ⇒ 多比特裸 CDC; 同时
  `p7bdp_din[39..43]` 成死逻辑 (布后 `u_snap_p7bdp/hold_b_reg` 槽 39..43
  = 0 个寄存器)。修法 = 顶部项只读 `p7bdp_dout[...]` ⇒ 必须经过
  `snap_cdc` 的 hold_b 相干锁存。

⭐ 0x2D backstop-2 (2026-10-18): W85/W86/W87 已从快照删除 ⇒ 顶端只剩
  **TOPN = 2** 项 (W84/W83 = p7bdp 槽 40/39)。本门随之把期望从 43..39 收窄到
  40..39; 旧的 5 项 (88 字) 形态会因第 3 项不是 ch0 束而**红** (负控仍有牙)。

本脚本断言 (全部为**源码结构**, 不依赖综合/布局):
  1. `snap_dout_all` 顶部 TOPN=2 项 = `p7bdp_dout[40..39]` (顺序 40,39);
  2. 源码 (去注释后) 无 `w8x_snap` 线, 也无 `assign w8x_snap = w8x_dp` 直连;
  3. 输入侧仍完整: `p7bdp_din[39..40] = w83_dp/w84_dp` (2 条);
  4. N-10 语义仍在: 两处非 DUAL 分支的 `w83_dp/w84_dp` 常量 tie-off
     (各 2 处 = 32'd0) —— 只做存在性断言, 不解释 ifdef 组合。

用法:
  python check_snap_top5_wired.py [--root <repo-root>]
退出码: 0 = PASS / 1 = FAIL (打印 SNAP_TOP5_STATIC_PASS|FAIL)。
本脚本只读, 不写任何文件。挂载点 = `run_tb_p7b_chain.bat` 首步 (24 门矩阵内)。
"""
import argparse
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

TOPN = 14                    # P11 E1a-1: W96..W83 (p7bdp 槽 52..39)
ITEMS_WANT = ["p7bdp_dout[%d*32 +: 32]" % s for s in range(52, 38, -1)]


def _norm(s):
    return re.sub(r"\s+", " ", s.strip())


def strip_line_comments(text):
    """去掉 `//` 行内注释。本文件没有跨行块注释; 字符串里的 // 不会出现在
    这些结构行上 (只处理 wrapper_p4.v 的代码行)。"""
    out = []
    for line in text.split("\n"):
        i = line.find("//")
        out.append(line[:i] if i >= 0 else line)
    return "\n".join(out)


def extract_snap_items(code):
    """从 `snap_dout_all = {` 起取到配平的 `};`, 返回顶层逗号分隔的项。"""
    m = re.search(r"snap_dout_all\s*=\s*\{", code)
    if not m:
        raise SystemExit("FAIL 找不到 snap_dout_all 初始化")
    i = code.index("{", m.start())
    depth = 0
    for j in range(i, len(code)):
        if code[j] == "{":
            depth += 1
        elif code[j] == "}":
            depth -= 1
            if depth == 0:
                body = code[i + 1:j]
                break
    else:
        raise SystemExit("FAIL snap_dout_all 大括号不配平")
    # 顶层逗号切分 (项里没有花括号; part-select 的方括号不参与切分)
    items, cur, depth_b, depth_p = [], [], 0, 0
    for ch in body:
        if ch == "{":
            depth_b += 1
        elif ch == "}":
            depth_b -= 1
        elif ch == "[":
            depth_p += 1
        elif ch == "]":
            depth_p -= 1
        if ch == "," and depth_b == 0 and depth_p == 0:
            items.append(_norm("".join(cur)))
            cur = []
        else:
            cur.append(ch)
    tail = _norm("".join(cur))
    if tail:
        items.append(tail)
    return [x for x in items if x]


def main():
    ap = argparse.ArgumentParser()
    here = os.path.dirname(os.path.abspath(__file__))
    ap.add_argument("--root", default=os.path.abspath(os.path.join(here, "..", "..", "..")))
    a = ap.parse_args()
    path = os.path.join(a.root, "board", "wrapper_p4.v")
    if not os.path.isfile(path):
        print("FAIL 找不到 %s" % path)
        print("SNAP_TOP5_STATIC_FAIL")
        return 1
    text = open(path, "r", encoding="utf-8", errors="replace").read()
    raw = text
    code = strip_line_comments(text)
    fails = []

    # 1) 顶部 TOPN 项
    try:
        items = extract_snap_items(code)
    except SystemExit as e:
        print("FAIL %s" % e)
        print("SNAP_TOP5_STATIC_FAIL")
        return 1
    got = items[:TOPN]
    ok1 = got == ITEMS_WANT
    print("%s [1] snap_dout_all 顶部 %d 项 = %s" % ("[ok]" if ok1 else "[FAIL]", TOPN, got))
    if not ok1:
        print("      期望 = %s" % ITEMS_WANT)
        fails.append("top%d" % TOPN)

    # 2) 无 w8x_snap / 无直连
    sn = re.findall(r"\bw8[3-7]_snap\b", code)
    asg = re.findall(r"assign\s+w8[3-7]_snap\s*=\s*w8[3-7]_dp\b", code)
    ok2 = (len(sn) == 0 and len(asg) == 0)
    print("%s [2] 无 w8x_snap (code hits=%d) / 无 assign w8x_snap=w8x_dp (hits=%d)"
          % ("[ok]" if ok2 else "[FAIL]", len(sn), len(asg)))
    if not ok2:
        fails.append("direct-wire")

    # 3) p7bdp_din[39..40] = w83_dp/w84_dp
    miss = []
    for slot in (39, 40):
        pat = r"assign\s+p7bdp_din\[%d\*32\s*\+:\s*32\]\s*=\s*w%d_dp\s*;" % (slot, slot + 44)
        if not re.search(pat, code):
            miss.append(slot)
    ok3 = not miss
    print("%s [3] p7bdp_din[39..40] = w83_dp/w84_dp (缺 %s)"
          % ("[ok]" if ok3 else "[FAIL]", miss if miss else "无"))
    if not ok3:
        fails.append("din-wiring")

    # 3b) P11 E1a-1: p7bdp_din[41..52] = e1a_hist[0..9]/sum/max
    miss_e = []
    for k in range(85, 95):
        slot = 41 + (k - 85)
        pat = r"assign\s+p7bdp_din\[%d\*32\s*\+:\s*32\]\s*=\s*e1a_hist\[%d\*32\s*\+:\s*32\]\s*;" % (slot, k - 85)
        if not re.search(pat, code):
            miss_e.append(k)
    for k, slot, src in ((95, 51, "e1a_sum_total"), (96, 52, "e1a_max_total")):
        pat = r"assign\s+p7bdp_din\[%d\*32\s*\+:\s*32\]\s*=\s*%s\s*;" % (slot, src)
        if not re.search(pat, code):
            miss_e.append(k)
    ok3b = not miss_e
    print("%s [3b] p7bdp_din[41..52] = e1a_hist/sum/max (缺 %s)"
          % ("[ok]" if ok3b else "[FAIL]", miss_e if miss_e else "无"))
    if not ok3b:
        fails.append("e1a-din-wiring")

    # 4) N-10 tie-off 存在性 (非 DUAL 两支: w83/w84 = 0; W85..W87 已删, 不再检查)
    zero_hits = {k: len(re.findall(r"wire\s*\[31:0\]\s+w%d_dp\s*=\s*32'd0\s*;" % k, code))
                 for k in (83, 84)}
    # 两处非 DUAL 分支 (DUAL+非 APP_MODE 的内层 else + 非 DUAL 的外层 else) ⇒ 常量 0 各 2 次。
    ok4 = all(v == 2 for v in zero_hits.values())
    print("%s [4] N-10 tie-off: zero_hits=%s (期望 83/84 各 2)"
          % ("[ok]" if ok4 else "[FAIL]", zero_hits))
    if not ok4:
        fails.append("n10-tieoff")

    if fails:
        print("SNAP_TOP5_STATIC_FAIL (%s)" % ",".join(fails))
        return 1
    print("SNAP_TOP5_STATIC_PASS (source=%s)" % path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
