#!/usr/bin/env python3
# analyze_readlog.py -- 解析 READLOG 逐 read 表 (2026-10-13 宿主读循环轮)
#   口径 (逐条):
#     区间 i = (记录 i-1 → 记录 i):  dt = t_i - t_{i-1}
#       offered_bytes = Δdma×4 + Δw70            (源对采集通道的交付 = 取走 + 丢)
#       entry_rate  = offered_bytes / dt          (本区间的"入口速率")
#       idle_us     = Δw70 / entry_rate           (**丢字节反解的空档**; 用同一区间自己的 entry)
#     三时长: gap_us(宿主账面) / mmio_us(仪器自身) / read_us(read 调用或 AIO 生命期)
#   汇总: 各量中位 + gap(C)=a+b·C 最小二乘拟合 (C = chunk MiB, 用 read_us/gap+mmio+read 两种口径)
#   用法: python analyze_readlog.py <win.txt> [<win.txt> ...]
import re, sys, statistics as st

def parse(path):
    txt = open(path, encoding="utf-8", errors="replace").read()
    recs = []
    for m in re.finditer(r"READLOG i=(\d+) t=([\d.]+) gap_us=([-\d.]+) mmio_us=([-\d.]+) "
                         r"read_us=([-\d.]+) got=(\d+) pc=(\d+) w70=(\d+) dw70=(\d+) dma=(\d+) ddma=(\d+)", txt):
        g = m.groups()
        recs.append(dict(i=int(g[0]), t=float(g[1]), gap=float(g[2]), mmio=float(g[3]),
                         read=float(g[4]), got=int(g[5]), pc=int(g[6]),
                         w70=int(g[7]), dw70=int(g[8]), dma=int(g[9]), ddma=int(g[10])))
    def find(pat):
        m = re.search(pat, txt)
        return m.groups() if m else None
    cfg = find(r"MIR_STREAM_CFG dev=(\S+) bytes=(\d+) chunk=(\d+)")
    cfg2 = find(r"MIR_STREAM_CFG2 readlog=(\d+) aio_depth=(\d+)")
    done = find(r"MIR_STREAM_DONE pc=(\d+) reads=(\d+) partial=(\d+) nonmul64=(\d+) short=(\d+) "
                r"ended_early=(\d+) read_error=(\d+) secs=([\d.]+) rate_Bps=(\d+)")
    acct = find(r"MIR_STREAM_ACCT pc=(\d+) taken_bytes=(\d+) dW70=(\d+)")
    ida = find(r"MIR_STREAM_IDA .*-> (-?\d+)\s+band=\[0,(\d+)\] closed_a=(\d)")
    idb = find(r"MIR_STREAM_IDB .*-> (-?\d+)\s+band=\[0,(\d+)\] closed_b=(\d)")
    buf = find(r"MIR_STREAM_BUF bytes=(\d+) mb=(\d+) prefault=1 aligned=4096 huge=(\d)")
    return dict(path=path, recs=recs, cfg=cfg, cfg2=cfg2, done=done, acct=acct, ida=ida, idb=idb, buf=buf)

def fit(xs, ys):
    n = len(xs)
    if n < 2: return (0.0, 0.0)
    mx, my = sum(xs)/n, sum(ys)/n
    sxx = sum((x-mx)**2 for x in xs)
    if sxx == 0: return (my, 0.0)
    b = sum((x-mx)*(y-my) for x, y in zip(xs, ys)) / sxx
    return (my - b*mx, b)   # (a, b)

def main():
    rows = []
    for p in sys.argv[1:]:
        w = parse(p)
        recs = w["recs"]
        if not recs:
            print(f"{p}: 无 READLOG 记录"); continue
        chunk = int(w["cfg"][2]) if w["cfg"] else 0
        K = int(w["cfg"][1]) if w["cfg"] else 0
        entries, idles, dts, reads, gaps, mmios, drops = [], [], [], [], [], [], []
        prev = None
        for r in recs:
            if prev is not None:
                dt = r["t"] - prev["t"]
                if dt <= 0: prev = r; continue
                offered = r["ddma"]*4 + r["dw70"]
                if offered <= 0: prev = r; continue
                entry = offered/dt                      # B/s
                entries.append(entry)
                idles.append(r["dw70"]/entry*1e6)       # µs
                dts.append(dt)
            if r["read"] < 1e6:                         # 排除最后的阻塞读 (看门狗尾巴)
                reads.append(r["read"]); gaps.append(r["gap"]); mmios.append(r["mmio"])
            drops.append(r["dw70"])
            prev = r
        med = lambda v: st.median(v) if v else float("nan")
        entry_med = med(entries)
        # read 口径的空档 = read_us 中位 - 本块纯数据时间
        data_us = (chunk/entry_med*1e6) if entry_med > 0 else float("nan")
        rows.append(dict(path=p, chunk=chunk, K=K, n=len(recs),
                         entry=entry_med, read=med(reads), gap=med(gaps), mmio=med(mmios),
                         idle=med(idles), data_us=data_us,
                         dsum=sum(drops), done=w["done"], idb=w["idb"], huge=(w["buf"][2] if w["buf"] else "?"),
                         aio=(w["cfg2"][1] if w["cfg2"] else "?")))
    hdr = ("win                     chunkMiB  n   entry_MBps read_us  gap_us mmio_us idle_us data_us  "
           "drop_MB  huge aio 式B")
    print(hdr)
    for r in rows:
        print("%-22s %7.2f %4d %9.1f %8.1f %7.2f %7.2f %7.1f %7.1f %8.2f %5s %3s %s" % (
            r["path"].split("/")[-1].replace(".txt", ""), r["chunk"]/1048576, r["n"],
            r["entry"]/1e6, r["read"], r["gap"], r["mmio"], r["idle"], r["data_us"],
            r["dsum"]/1e6, r["huge"], r["aio"],
            ("res=%s closed=%s" % (r["idb"][0], r["idb"][2])) if r["idb"] else "?"))
    # 拟合 (同一配置族: 同一 huge/aio 标记)
    for tag in sorted(set((r["huge"], r["aio"]) for r in rows)):
        sel = [r for r in rows if (r["huge"], r["aio"]) == tag]
        if len(sel) < 2: continue
        xs = [r["chunk"]/1048576 for r in sel]
        a1, b1 = fit(xs, [r["idle"] for r in sel])                 # idle(C) [µs]
        a2, b2 = fit(xs, [r["read"] - r["data_us"] for r in sel])  # (read-data)(C) [µs]
        print("fit huge=%s aio=%s: idle(C)= %.1f µs + %.1f µs/MiB   (read−data)(C)= %.1f + %.1f µs/MiB"
              % (tag[0], tag[1], a1, b1, a2, b2))

if __name__ == "__main__":
    main()
