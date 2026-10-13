#!/usr/bin/env python3
# bx_median_adj.py -- Claude 组独立验证
#   V-C: READLOG_SUM med 口径 (工具 v[n/2] 上中位 vs statistics.median) —— 真实窗复算
#   V-E: dual 打印序相邻行的 "Δw70 属 [上一条→本条]" 口径检验（数值化）
import re, sys, statistics
RUNS = r"D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_hostread_20261013/runs"
ROW = re.compile(r"READLOG i=(\d+) t=([\d.]+) gap_us=([-\d.]+) mmio_us=([-\d.]+) "
                 r"read_us=([-\d.]+) got=(\d+) pc=(\d+) w70=(\d+) dw70=(\d+) dma=(\d+) ddma=(\d+)")
SUM = re.compile(r"READLOG_SUM .*?read_us\[min=([\d.]+) med=([\d.]+) max=([\d.]+) sum_ms=([\d.]+)\]")
ARGS = re.compile(r"TOOL_ARGS: (.*)")

def load(path):
    txt = open(path, encoding="utf-8", errors="replace").read()
    rows = [dict(i=int(m[0]), t=float(m[1]), gap=float(m[2]), mmio=float(m[3]), read=float(m[4]),
                 got=int(m[5]), pc=int(m[6]), w70=int(m[7]), dw70=int(m[8]), dma=int(m[9]), ddma=int(m[10]))
            for m in (m.groups() for m in ROW.finditer(txt))]
    m = SUM.search(txt)
    printed = float(m.group(2)) if m else None
    m = ARGS.search(txt)
    args = m.group(1) if m else ""
    return rows, printed, args

print("=" * 96)
print("V-C: READLOG_SUM 'read_us med' 口径复算（真实窗）")
print("=" * 96)
print(f"{'win':12s} {'n':>5s} {'n%2':>4s} {'tool_printed':>13s} {'v[n/2]上中位':>13s} "
      f"{'v[(n-1)/2]下中位':>16s} {'statistics.median':>18s}")
for name in ("LAD_1048576", "S1M", "D1M", "AI4", "A1", "N32b"):
    rows, printed, args = load(f"{RUNS}/{name}.txt")
    v = sorted(r["read"] for r in rows)
    n = len(v)
    up = v[n // 2]; lo = v[(n - 1) // 2]; st = statistics.median(v)
    print(f"{name:12s} {n:5d} {n%2:4d} {printed:13.1f} {up:13.1f} {lo:16.1f} {st:18.1f}  "
          f"{'== 工具行 ✓' if printed == up else '≠ 工具行 ✗'}")

print()
print("=" * 96)
print("V-E: '打印序相邻行' 的 Δw70 口径检验: 逐行核 dw70 == (w70 - 上一打印行.w70) mod 2^32 ?")
print("=" * 96)
M32 = 1 << 32
for name in ("A1", "A1N2", "D1M", "D4M", "LAD_1048576", "S1M"):
    rows, printed, args = load(f"{RUNS}/{name}.txt")
    mode = "dual" if "--dual 2" in args else "sync"
    ok = bad = 0; examples = []
    for k in range(1, len(rows)):
        pred = (rows[k]["w70"] - rows[k - 1]["w70"]) % M32
        if pred == rows[k]["dw70"]:
            ok += 1
        else:
            bad += 1
            if len(examples) < 3:
                examples.append((k, rows[k - 1]["pc"], rows[k]["pc"], rows[k]["dw70"], pred))
    print(f"{name:12s} [{mode}] 相邻行口径成立 {ok}/{ok+bad}；反例(行号, 上行pc, 本行pc, 实际dw70, 按打印邻差应为):")
    for e in examples:
        print("      ", e)
