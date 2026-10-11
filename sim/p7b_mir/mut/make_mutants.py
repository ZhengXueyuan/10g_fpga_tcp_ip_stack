#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
make_mutants.py -- M1 载荷镜像单元门的"该红时红"突变件生成器 (P8 阶段三 2026-10-11 重写版)

做什么: 从现役 `rtl/app_rx_mirror.v` 生成三个**单点**突变件到本目录:
  mut_gate  : 写门去掉空间门 `!fifo_full`  (`wr_en = have && !fifo_full && cap_on` -> `have && cap_on`)
              ⇒ 满态被拒写的字**静默消失** (FIFO 的 ovf 计数器本模块不接, drop_bytes 不动)
              ⇒ 只该由 **字节账恒等式 (G11c / G8d)** 翻红。
  mut_order : 两字节搬运分支 b0/b1 交换 (`{48'd0, b1, b0}` -> `{48'd0, b0, b1}`)
              ⇒ 只该由**手算锚** (G3c/G4c/G5c...) 翻红。
  mut_cap4  : **重新引入 4 B/拍结构上限** (`kk` 上限钉到 4)
              ⇒ 对 8 B/拍持续源又变成"收、丢、收、丢" ⇒ 只该由 **G13 (8B/拍持续源 ⇒ drop==0)** 翻红
              (这正证明本刀的**新主判据**有自己的牙; G13 之前的判据结构性抓不到它)。

纪律 (全局 #90-#94 精神; 同 `sim/p6e_pcie/mut_*.py`):
  · 每个突变**恰好 1 处命中**才算成功 (0 处 = 锚点陈旧; >1 处 = 改错地方) —— 打印 *_HITS 供 bat 判;
  · 只做一次字符串替换, 不做任何别的编辑; 输出件是**产物** (每次都重生成);
  · 不修改仓库里的任何源文件 (只读 rtl/, 只写本目录)。

用法: python make_mutants.py [--repo <repo>]      (退出码 0 = 三件全生成且各 1 处命中)
"""
from __future__ import print_function
import io, os, sys, argparse

MUTS = [
    ("app_rx_mirror_mut_gate.v", "mut_gate",
     "    wire       wr_en     = have && !fifo_full && cap_on;          // 冻结写门 (组合 + 本拍 full + cap_on)",
     "    wire       wr_en     = have && cap_on;                         // MUTANT mut_gate: 空间门被去掉"),
    ("app_rx_mirror_mut_order.v", "mut_order",
     "            4'd2:    mv = {48'd0, b1, b0};",
     "            4'd2:    mv = {48'd0, b0, b1};   // MUTANT mut_order: b0/b1 swapped"),
    ("app_rx_mirror_mut_cap4.v", "mut_cap4",
     "    wire [3:0] kk        = (n_cur < room) ? n_cur : room;         // 本拍搬 kk 个字节 (0..8)",
     "    wire [3:0] kk        = (n_cur < room) ? ((n_cur > 4'd4) ? 4'd4 : n_cur) : ((room > 4'd4) ? 4'd4 : room);  // MUTANT mut_cap4: 4B/拍上限"),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.path.dirname(os.path.dirname(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))
    a = ap.parse_args()
    src = os.path.join(a.repo, "rtl", "app_rx_mirror.v")
    with io.open(src, "r", encoding="utf-8", newline="") as f:
        text = f.read()
    rc = 0
    for fname, tag, old, new in MUTS:
        hits = text.count(old)
        print("MUT_%s_HITS = %d" % (tag.upper(), hits))
        if hits != 1:
            print("MUT_%s_GENFAIL (需要恰好 1 处命中)" % tag.upper())
            rc = 1
            continue
        out = text.replace(old, new)
        dst = os.path.join(os.path.dirname(os.path.abspath(__file__)), fname)
        with io.open(dst, "w", encoding="utf-8", newline="") as f:
            f.write(out)
        print("MUT_%s_OK -> %s" % (tag.upper(), fname))
    if rc == 0:
        print("MUT_ALL_OK")
    return rc


if __name__ == "__main__":
    sys.exit(main())
