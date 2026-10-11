#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
make_mutants.py -- M1 载荷镜像单元门的"该红时红"突变件生成器
                   (P8-STG 16 B 弹性暂存版, 2026-10-11 重写)

做什么: 从现役 `rtl/app_rx_mirror.v` 生成七个**单点**突变件到本目录:
  mut_gate    : 写门去掉空间门 `!fifo_full`  (`wr_en = have && !fifo_full && cap_on` -> `have && cap_on`)
                ⇒ 满态被拒写的字**静默消失** (FIFO 的 ovf 计数器本模块不接, drop_bytes 不动)
                ⇒ **至少**由 字节账恒等式 (G11c / G8d) 翻红。            [锚点存活]
  mut_order   : 两字节搬运分支 b0/b1 交换 (`{48'd0, b1, b0}` -> `{48'd0, b0, b1}`)
                ⇒ **至少**由 手算锚 (G3c/G4c/G5c...) 翻红。               [锚点存活]
  mut_cap4    : **重新引入 4 B/拍结构上限** (`kk` 上限钉到 4)            [锚点移到新 `kk` 行]
                ⇒ 对 8 B/拍持续源又变成"收、丢、收、丢" ⇒ **至少**由 G13 翻红
                (这正证明本刀的**新主判据**有自己的牙; G13 之前的判据结构性抓不到它)。
  mut_admit14 : ⭐ 新。`admit` 容量界 16 -> **14** (`<= 5'd16` -> `<= 5'd14`)
                ⇒ **只**由最坏轨迹类用例翻红 (G18 phase=7 / G17 ph=7 / G16 1477 含相位 7 帧)
                —— 这正证明为什么必须做 G18 (设计件 §6.2)。
  mut_apos0   : ⭐ 新。`keep=0` 档的尾部追加位置错位 (`{xbeat, 64'd0}` -> 8 字节旋转)
                ⇒ 相位 0 稠密流每拍都走这一档 ⇒ **至少**由 G13/G15 的逐字 golden 翻红。
  mut_dropcnt : ⭐ 新。丢字节计数被旁路 (`else if (drop_now)` -> `else if (1'b0 && drop_now)`)
                ⇒ 满态/恢复沿**静默丢** ⇒ **至少**由 G19 的字节账 + any_drop 翻红。
  mut_keep1   : (可选臂) 保留计数 +1 (`keep = stg_cnt - kk` -> `+ 5'd1`)
                ⇒ 暂存记账全错 ⇒ **至少**由 字节账恒等式 + G20 结构化断言翻红。

纪律 (全局 #90-#94 精神; 同 `sim/p6e_pcie/mut_*.py`):
  · 每个突变**恰好 1 处命中**才算成功 (0 处 = 锚点陈旧; >1 处 = 改错地方) —— 打印 *_HITS 供 bat 判;
  · 只做一次字符串替换, 不做任何别的编辑; 输出件是**产物** (每次都重生成);
  · 不修改仓库里的任何源文件 (只读 rtl/, 只写本目录)。
  · ⚠️ 措辞纪律 (审查 ⑤-3): 期望红灯面一律写"**至少**由 X 翻红", **不写**"只该由 X 翻红"
    (实测有多臂命中多处)。

用法: python make_mutants.py [--repo <repo>]      (退出码 0 = 全部生成且各 1 处命中)
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
     "    wire [3:0] kk        = (sc4 < room) ? sc4 : room;",
     "    wire [3:0] kk        = (((sc4 < room) ? sc4 : room) > 4'd4) ? 4'd4 : ((sc4 < room) ? sc4 : room);  // MUTANT mut_cap4: 4B/拍上限"),
    ("app_rx_mirror_mut_admit14.v", "mut_admit14",
     "    wire       admit     = src_beat && (keep + {1'b0, n_b} <= 5'd16);",
     "    wire       admit     = src_beat && (keep + {1'b0, n_b} <= 5'd14);  // MUTANT mut_admit14: CAP 16->14"),
    ("app_rx_mirror_mut_apos0.v", "mut_apos0",
     "            5'd0:  beat_pl = {xbeat, 64'd0};",
     "            5'd0:  beat_pl = {xbeat[55:0], xbeat[63:56], 64'd0};   // MUTANT mut_apos0: keep=0 档尾部错位"),
    ("app_rx_mirror_mut_dropcnt.v", "mut_dropcnt",
     "        end else if (drop_now) begin",
     "        end else if (1'b0 && drop_now) begin                          // MUTANT mut_dropcnt: 丢字节不计数"),
    ("app_rx_mirror_mut_keep1.v", "mut_keep1",
     "    wire [4:0] keep      = stg_cnt - {1'b0, kk};",
     "    wire [4:0] keep      = stg_cnt - {1'b0, kk} + 5'd1;   // MUTANT mut_keep1: 保留计数 +1"),
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
