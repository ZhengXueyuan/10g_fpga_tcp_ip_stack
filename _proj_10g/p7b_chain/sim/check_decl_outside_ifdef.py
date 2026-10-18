#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""check_decl_outside_ifdef.py — F-8 结构性自检 (隐式网/截断的源头).

用法: check_decl_outside_ifdef.py <verilog-file> <name1> [name2 ...]

判据: 每个名字必须存在**一条 wire/reg 声明**, 且该声明**不在** `` `ifdef DUAL_SFP_A ``
      (含 else 分支: 在 `` `else `` 侧 = "非 DUAL" ⇒ 合法)。名字不存在 ⇒ FAIL;
      声明落在 DUAL 侧 ⇒ FAIL。

为什么需要它: Vivado 2025.2 的 xvlog 不再打印 `implicitly declared`; 非 DUAL 构建里
"32 位常量赋给 1 位隐式网"这一类截断**结构上不会在任何日志里出现** (只有 xelab 的
`actual bit length 1 differs` 能抓端口形式, 抓不到连续赋值形式)。本检查把
"声明是否在 ifdef 外"变成可判据的静态事实。
"""
import re
import sys


def main():
    if len(sys.argv) < 3:
        print("usage: check_decl_outside_ifdef.py <file> <name1> [name2 ...]")
        return 2
    path = sys.argv[1]
    names = sys.argv[2:]
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError as e:
        print("DECLCHECK FAIL cannot read %s: %s" % (path, e))
        return 1

    stack = []
    decl = {}
    for i, ln in enumerate(text.split("\n"), 1):
        s = ln.strip()
        if s.startswith("`ifdef"):
            parts = s.split()
            stack.append(parts[1] if len(parts) > 1 else "?")
            continue
        if s.startswith("`ifndef"):
            parts = s.split()
            stack.append("!" + (parts[1] if len(parts) > 1 else "?"))
            continue
        if s.startswith("`else"):
            if stack:
                top = stack[-1]
                stack[-1] = top[1:] if top.startswith("!") else "!" + top
            continue
        if s.startswith("`endif"):
            if stack:
                stack.pop()
            continue
        if not re.match(r"^\s*(wire|reg)\b", ln):
            continue
        for n in names:
            if n in decl:
                continue
            if re.search(r"\b" + re.escape(n) + r"\b", ln):
                decl[n] = (i, list(stack))

    bad = 0
    for n in names:
        if n not in decl:
            print("DECLCHECK FAIL %s: no wire/reg declaration found" % n)
            bad += 1
            continue
        i, st = decl[n]
        if "DUAL_SFP_A" in st:
            print("DECLCHECK FAIL %s: declaration at line %d is inside ifdef stack %s"
                  % (n, i, st))
            bad += 1
        else:
            print("DECLCHECK OK %s: declaration at line %d (ifdef stack %s)"
                  % (n, i, st))
    print("DECLCHECK_EXIT=%d" % bad)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
