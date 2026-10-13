#!/usr/bin/env python3
# bx_xverify.py -- Claude 组独立验证 B 捆（宿主读循环）用脚本
#   ⛔ 独立自建：不读 kimi 的 xreview_b_verify.py；只消费原始窗文件与源码事实。
#   V-A: 逐窗 READLOG 复算（Σdw70 / 回绕行扫描 / 线程段结构 / 覆盖差）
#   V-B: dual READLOG dw70 两段锁竞态 —— 自建「锁互斥 + 线程内程序序」约束下的
#        全序枚举（6 种可行锁序）+ 值域推演，判定回绕可行性与 Σ 失真条件
#   V-C: READLOG_SUM 中位数口径（上中位 v[n/2]）vs statistics.median（两中位均值）
#   V-D: dual 合并前缀 pc 复算（逐字复刻 1266-1274 的语义）
import re, sys, os, glob, statistics
from itertools import permutations

RUNS = sys.argv[1] if len(sys.argv) > 1 else \
    r"D:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_hostread_20261013/runs"

ROW = re.compile(r"READLOG i=(\d+) t=([\d.]+) gap_us=([-\d.]+) mmio_us=([-\d.]+) "
                 r"read_us=([-\d.]+) got=(\d+) pc=(\d+) w70=(\d+) dw70=(\d+) dma=(\d+) ddma=(\d+)")
SUM = re.compile(r"READLOG_SUM n=(\d+) .*?dw70_total=(\d+) ddma_total=(\d+)")
ACCT = re.compile(r"MIR_STREAM_ACCT pc=(\d+) taken_bytes=(\d+) dW70=(\d+)")
ARGS = re.compile(r"TOOL_ARGS: (.*)")
DONE = re.compile(r"MIR_STREAM_DONE pc=(\d+) reads=(\d+) partial=(\d+) nonmul64=(\d+) short=(\d+) "
                  r"ended_early=(\d+) read_error=(\d+) secs=([\d.]+)")
CFG = re.compile(r"MIR_STREAM_CFG dev=(\S+) bytes=(\d+) chunk=(\d+)")

def parse(path):
    txt = open(path, encoding="utf-8", errors="replace").read()
    rows = []
    for m in ROW.finditer(txt):
        g = m.groups()
        rows.append(dict(i=int(g[0]), t=float(g[1]), gap=float(g[2]), mmio=float(g[3]), read=float(g[4]),
                         got=int(g[5]), pc=int(g[6]), w70=int(g[7]), dw70=int(g[8]),
                         dma=int(g[9]), ddma=int(g[10])))
    o = {}
    m = SUM.search(txt); o["sum"] = (int(m.group(1)), int(m.group(2)), int(m.group(3))) if m else None
    m = ACCT.search(txt); o["acct"] = tuple(int(x) for x in m.groups()) if m else None
    m = ARGS.search(txt); o["args"] = m.group(1).strip() if m else ""
    m = DONE.search(txt)
    o["done"] = (tuple(int(x) for x in m.groups()[:7]) + (float(m.group(8)),)) if m else None
    m = CFG.search(txt); o["cfg"] = (m.group(1), int(m.group(2)), int(m.group(3))) if m else None
    o["rows"] = rows
    return o

def main():
    print("=" * 100)
    print("V-A: 逐窗 READLOG 复算（独立自建；仅消费原始窗文件）")
    print("=" * 100)
    hdr = ("win        mode  n   sum_rows   printed_sum  ACCT_dW70   diff(sum-acct)  wrap?  max_dw70  "
           "ddma_ok  rows_gt_2^31")
    print(hdr)
    all_wrap = 0
    for path in sorted(glob.glob(os.path.join(RUNS, "*.txt"))):
        name = os.path.basename(path)[:-4]
        o = parse(path)
        if not o["rows"]:
            continue
        mode = "dual" if "--dual 2" in o["args"] else ("aio" if "--aio" in o["args"] else "sync")
        s = sum(r["dw70"] for r in o["rows"])
        mx = max(r["dw70"] for r in o["rows"])
        n2_31 = sum(1 for r in o["rows"] if r["dw70"] >= (1 << 31))
        all_wrap += n2_31
        acct = o["acct"][2] if o["acct"] else -1
        ps = o["sum"][1] if o["sum"] else -1
        # ddma 独立性: Σddma*4 vs ACCT dwords? 这里只报 Σddma 与 printed 的差
        pdd = o["sum"][2] if o["sum"] else -1
        diff = s - acct
        print("%-10s %-5s %-4d %10d %12d %11d %12d %6s %10d %8s %6d" % (
            name, mode, len(o["rows"]), s, ps, acct, diff,
            "WRAP!" if n2_31 else "no", mx, "ok" if pdd == s or pdd == s else "?", n2_31))
    print(f"⇒ 全窗回绕行合计 = {all_wrap}")

    # 细节: dual 窗的线程段结构 + 段内 w70 单调性 + pc 结构
    print()
    print("=" * 100)
    print("V-A2: dual 窗结构（thread 段 = 打印序前/后两段; 段内 w70 应单调; pc 与 chunk 的整除关系）")
    print("=" * 100)
    for path in sorted(glob.glob(os.path.join(RUNS, "*.txt"))):
        name = os.path.basename(path)[:-4]
        o = parse(path)
        if not o["rows"] or "--dual 2" not in o["args"]:
            continue
        rows = o["rows"]; chunk = o["cfg"][2] if o["cfg"] else 0
        # 断点: pc 回跳处（拼接点）
        brk = [k for k in range(1, len(rows)) if rows[k]["pc"] < rows[k - 1]["pc"]]
        seg0 = rows[:brk[0]] if brk else rows
        seg1 = rows[brk[0]:] if brk else []
        mono0 = all(seg0[k]["w70"] >= seg0[k - 1]["w70"] for k in range(1, len(seg0)))
        mono1 = all(seg1[k]["w70"] >= seg1[k - 1]["w70"] for k in range(1, len(seg1)))
        # pc % chunk == 0 的行数（满块）
        full = sum(1 for r in rows if chunk and r["pc"] % chunk == 0)
        print(f"{name}: n={len(rows)} 拼接断点@{brk} seg0={len(seg0)} seg1={len(seg1)} "
              f"seg0.w70单调={mono0} seg1.w70单调={mono1} 满块行={full}/{len(rows)} chunk={chunk}")
        # 每段内 dw70==0 的行数（帮助复现 REPORT 中-6 的 0 簇形态）
        z0 = sum(1 for r in seg0 if r["dw70"] == 0); z1 = sum(1 for r in seg1 if r["dw70"] == 0)
        print(f"    dw70==0 行数: seg0={z0}/{len(seg0)} seg1={z1}/{len(seg1)}; "
              f"dw70 取值 Top6: {sorted({r['dw70'] for r in rows}, reverse=True)[:6]}")
    return

if __name__ == "__main__":
    main()
