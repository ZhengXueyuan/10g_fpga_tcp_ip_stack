#!/usr/bin/env python3
"""G-P3-3 负控: retx_pool_shared 变异件.

mutants:
  staleowner : 去掉属主门 (任何口都能读写任何槽) -> H-2 owner 翻转臂必红
               (旧口在 grant_port 翻转后仍能读回旧数据, 且 mismatch 不计数)
"""
import pathlib

root = pathlib.Path(__file__).resolve().parents[5]  # repo root
src = (root / "rtl" / "retx_pool_shared.v").read_text(encoding="utf-8")
outdir = pathlib.Path(__file__).resolve().parent / "mut"
outdir.mkdir(exist_ok=True)

def emit(name, old, new, count=1):
    if src.count(old) < count:
        raise SystemExit(f"[MUT FAIL] {name}: pattern not found ({src.count(old)})")
    dst = src.replace(old, new, count) if count else src.replace(old, new)
    p = outdir / f"retx_pool_shared_{name}.v"
    p.write_text(dst, encoding="utf-8", newline="\n")
    print(f"MUT {name} -> {p}")

# 单文件同时去掉写/读属主门 (同一模块只能有一个定义 => 必须合并成一个变异件)
dst = src
for old, new in [
    ("wire       wr0_ok = wr_en0 && (w_conn0 == gi[3:0]) && (grant_port[gi] == 1'b0);",
     "wire       wr0_ok = wr_en0 && (w_conn0 == gi[3:0]);"),
    ("wire       rd0_ok = rd_en0 && (r_conn0 == gi[3:0]) && (grant_port[gi] == 1'b0);",
     "wire       rd0_ok = rd_en0 && (r_conn0 == gi[3:0]);"),
]:
    if dst.count(old) != 1:
        raise SystemExit(f"[MUT FAIL] staleowner: pattern not found ({dst.count(old)})")
    dst = dst.replace(old, new)
p = outdir / "retx_pool_shared_staleowner.v"
p.write_text(dst, encoding="utf-8", newline="\n")
print(f"MUT staleowner -> {p}")
