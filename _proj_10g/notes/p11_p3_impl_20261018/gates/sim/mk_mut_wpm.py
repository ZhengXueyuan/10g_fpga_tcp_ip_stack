#!/usr/bin/env python3
"""G-P3-1 负控: 生成 win_pool_mgr 变异件 (每次只改一处).

mutants:
  c18  : 去掉 port0 ev_up 的旧配额回池 (C18 原子归还) -> 不变量必红
  pcap : 去掉 port_cap 夹紧 -> port_win <= port_cap 必红
  dup  : 去掉 rel 时 winq==0 的 stat_rel_dup 计数 -> 重复释放必红
"""
import pathlib, sys

root = pathlib.Path(__file__).resolve().parents[5]  # repo root
src = (root / "rtl" / "win_pool_mgr.v").read_text(encoding="utf-8")
outdir = pathlib.Path(__file__).resolve().parent / "mut"
outdir.mkdir(exist_ok=True)

def emit(name, old, new, count=1):
    if src.count(old) < count:
        raise SystemExit(f"[MUT FAIL] {name}: pattern not found ({src.count(old)})")
    dst = src.replace(old, new, count) if count else src.replace(old, new)
    p = outdir / f"win_pool_mgr_{name}.v"
    p.write_text(dst, encoding="utf-8", newline="\n")
    print(f"MUT {name} -> {p}")

emit("c18",
     "            pool_n = pool_n + {1'b0, old_q};\n            pw0_n  = pw0_n - {1'b0, old_q};\n",
     "")  # first occurrence = port0

emit("pcap",
     "            if (room  < g) g = room;\n            winq_n[ev_up_slot0[2:0]] = g[15:0];",
     "            winq_n[ev_up_slot0[2:0]] = g[15:0];")

emit("dup",
     "            if (rel0 && (rel_slot0 < 4'd8) && (winq[rel_slot0] == 16'd0))\n                stat_rel_dup <= stat_rel_dup + 32'd1;",
     "")
