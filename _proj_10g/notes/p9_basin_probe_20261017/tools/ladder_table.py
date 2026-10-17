#!/usr/bin/env python3
"""ladder_table.py -- build the B3 rcvbuf-ladder table from the per-tier JSON + stdout.

For each tier: rcvbuf (from K0M_BEGIN), measured peer advertised window (dominant value
in MSS units, max value, >=8MSS fraction), unique-basis rate, held%, burst%, first_seg,
and dW55/dt from the PRE/POST explicit snapshots (mod 2^32, arm duration from K0M lines).

Usage: python ladder_table.py B3a B3b B3c B3d B3e
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
RUNS = os.path.join(ROOT, "runs")
M32 = 1 << 32
MSS = 1460


def median(xs):
    xs = sorted(xs)
    n = len(xs)
    return None if not n else (xs[n // 2] if n % 2 else 0.5 * (xs[n // 2 - 1] + xs[n // 2]))


def pre_post_vals(path):
    d = {}
    for line in open(path, "r", errors="replace"):
        m = re.match(r"W(\d+)\s+\S+\s+\S+\s+(0x[0-9a-fA-F]+)", line)
        if m:
            d[int(m.group(1))] = int(m.group(2), 16)
    return d


def main():
    print("%-6s %7s %10s %11s %9s %10s %10s %8s %9s %9s %10s" %
          ("arm", "rcvbuf", "dur_s", "peerwin", "maxwin", ">=8MSS%", "uniqMbps", "held%", "burst%", "firstseg", "W55/s"))
    for tag in sys.argv[1:]:
        so = os.path.join(RUNS, "%s_stdout.txt" % tag)
        js = os.path.join(RUNS, "%s_metrics.json" % tag)
        txt = open(so, "r", errors="replace").read()
        mb = re.search(r"### K0M_BEGIN tag=\S+ nsinks=\S+ stagger=\S+ rcvbuf=(\d+)", txt)
        rcvbuf = int(mb.group(1)) if mb else -1
        t0 = re.search(r"### K0M_BEGIN .*? (\d{10}\.\d+)", txt)
        t1 = re.search(r"### K0M_END tag=\S+ (\d{10}\.\d+)", txt)
        dur = (float(t1.group(1)) - float(t0.group(1))) if (t0 and t1) else None
        pre = os.path.join(ROOT, "raw", "bp_%s_pre.txt" % tag)
        post = os.path.join(ROOT, "raw", "bp_%s_post.txt" % tag)
        j = json.load(open(js))
        # W55 rate denominator = the pcap span (data window), not the arm wall time:
        # short fast arms would otherwise be diluted by setup/teardown.
        dur_w55 = j.get("span") or dur
        w55_rate = None
        if dur_w55 and os.path.exists(pre) and os.path.exists(post):
            a, b = pre_post_vals(pre), pre_post_vals(post)
            if 55 in a and 55 in b:
                w55_rate = ((b[55] - a[55]) % M32) / dur_w55
        conns = [c for c in j["conns"] if not c.get("no_data")]
        # peer win: aggregate over conns
        agg = {}
        for c in conns:
            for k, v in c.get("peer_win_hist", {}).items():
                agg[int(k)] = agg.get(int(k), 0) + v
        tot = sum(agg.values())
        dom = max(agg, key=agg.get) if agg else 0
        mx = max(agg) if agg else 0
        ge8 = sum(v for k, v in agg.items() if k >= 8 * MSS)
        print("%-6s %7d %10s %6d(%4.1fM) %6d(%4.1fM) %8.1f%% %10s %8.1f %9.1f %9s %10s" %
              (tag, rcvbuf, ("%.1f" % dur) if dur else "-",
               dom, dom / MSS, mx, mx / MSS, 100.0 * ge8 / tot if tot else 0,
               ("%.2f" % median([c["uniq_mbps"] for c in conns])) if conns else "-",
               median([c["held_pct"] for c in conns]) if conns else 0,
               median([c["burst_pct"] for c in conns]) if conns else 0,
               ",".join(str(c["first_seg_count"]) for c in conns),
               ("%.0f" % w55_rate) if w55_rate is not None else "-"))


if __name__ == "__main__":
    main()
