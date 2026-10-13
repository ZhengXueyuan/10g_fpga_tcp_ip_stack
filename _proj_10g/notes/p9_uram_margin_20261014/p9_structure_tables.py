#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""p9_structure_tables.py -- 每窗洞结构表 + 量子移位检查 (任务1 的表; 任务3 的旁证)"""
import importlib.util
import glob
import os
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("hp", os.path.join(HERE, "p9_holeparse.py"))
hp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hp)

NEW = "D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_uram_ab_20261014/runs/WIN_*.txt"
OLD24 = ["D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_board_0x24_20261013/runs/WIN_S0_20261013_220859.txt",
         "D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_board_0x24_20261013/runs/WIN_S1_S5_20261013_220956.txt",
         "D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_board_0x24_20261013/runs/WIN_S6_S10_20261013_221125.txt",
         "D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_board_0x24_20261013/runs/WIN_F0_20261013_220930.txt",
         "D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_board_0x24_20261013/runs/WIN_F1_F5_20261013_221254.txt",
         "D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_board_0x24_20261013/runs/WIN_F6_F9_20261013_221427.txt"]
OLD23 = ["D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_hostread_20261013/runs/A1.txt",
         "D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_hostread_20261013/runs/A1N2.txt",
         "D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_hostread_20261013/runs/A4.txt"]

def load(pat_list):
    out = []
    files = []
    for p in pat_list:
        files += sorted(glob.glob(p))
    for f in files:
        txt = open(f, encoding="utf-8", errors="replace").read()
        for r in hp.parse_windows(txt, os.path.basename(f)):
            hp.analyze(r)
            out.append(r)
    return out

def med(v):
    s = sorted(v); n = len(s)
    return s[n//2] if n else 0

def main():
    wins_new = load([NEW])
    wins_o24 = load(OLD24)
    wins_o23 = load(OLD23)
    rep = []
    W = rep.append
    W("# 每窗洞结构表 (Def-A 主口径; 位置/间距以 pc 字节计; 1 区间 = 1 次 4 MiB 读完成)")
    W(f"{'窗':<6} {'观测ΔW70':>10} {'洞数':>4} {'洞深 min':>9} {'med':>9} {'max':>10} "
      f"{'零区间数':>6} {'有丢区间%':>8} {'间距(区间)中位':>8} {'首段洞':>10} {'最大洞':>10}")
    for w in wins_new + wins_o23 + wins_o24:
        ds = [b["depth"] for b in w["bursts"]]
        nint = len(w["deltas"])
        zero = sum(1 for d in w["deltas"] if d == 0)
        gaps = [ (w["bursts"][i]["pc_anchor"] - w["bursts"][i-1]["pc_anchor"]) // hp.CHUNK
                 for i in range(1, len(w["bursts"])) ]
        first = ds[0] if ds else 0
        tag = w["tag"]
        W(f"{tag:<6} {w['sum_my_delta']:>10,} {len(ds):>4} {min(ds) if ds else 0:>9,} "
          f"{med(ds):>9,} {max(ds) if ds else 0:>10,} {zero:>6} "
          f"{100*(nint-zero)/nint:>7.1f}% {med(gaps) if gaps else 0:>8} {first:>10,} {max(ds) if ds else 0:>10,}")

    # 量子移位检查: 逐区间深度 (Def-B) 在 [9000,13000] 与 [40000,48000] 的比例
    W("\n# 量子移位检查 (Def-B 逐区间深度落入两窗的比例)")
    W(f"{'窗':<6} {'洞数':>4} {'∈[9000,13000]':>13} {'∈[40000,48000]':>14} {'∈其他':>8}")
    for w in wins_new:
        ds = [b["depth"] for b in w["bursts_b"]]
        a = sum(1 for d in ds if 9000 <= d <= 13000)
        b_ = sum(1 for d in ds if 40000 <= d <= 48000)
        W(f"{w['tag']:<6} {len(ds):>4} {a:>13} {b_:>14} {len(ds)-a-b_:>8}")

    txt = "\n".join(rep)
    open(os.path.join(HERE, "structure.report.txt"), "w", encoding="utf-8").write(txt)
    print(txt[:2000])
    print("...")
    print(txt[-1600:])

if __name__ == "__main__":
    main()
