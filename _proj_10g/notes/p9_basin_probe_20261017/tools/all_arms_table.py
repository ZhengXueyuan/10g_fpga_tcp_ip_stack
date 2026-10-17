#!/usr/bin/env python3
"""all_arms_table.py -- one-line-per-arm pcap-derived table (all probe arms).

Columns: conns w/ data, per-conn wire Mbps, unique Mbps median, held% unique (median),
held% G-anchor basis (median), burst% (median), first-seg list, peer win dominant (MSS),
peer win 0-fraction, >=8MSS fraction, board win dominant.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RUNS = os.path.join(HERE, "..", "runs")
MSS = 1460
ARMS = sys.argv[1:] or ["B0", "B1", "B2", "B3a", "B3b", "B3c", "B3d", "B3e", "B4", "B5", "B5P"]


def med(xs):
    xs = sorted(xs)
    n = len(xs)
    return None if not n else (xs[n // 2] if n % 2 else 0.5 * (xs[n // 2 - 1] + xs[n // 2]))


print("%-5s %6s %-34s %10s %9s %9s %8s %-14s %11s %8s %8s %10s" %
      ("arm", "conns", "wire Mbps (per conn)", "uniq med", "held%uni", "held%tx", "burst%", "first_seg",
       "peerwin", "zero%", ">=8MSS", "bwin"))
for arm in ARMS:
    p = os.path.join(RUNS, "%s_metrics.json" % arm)
    if not os.path.exists(p):
        print("%-5s MISSING" % arm)
        continue
    j = json.load(open(p))
    cs = [c for c in j["conns"] if not c.get("no_data")]
    if not cs:
        print("%-5s %6d (no data)" % (arm, len(j["conns"])))
        continue
    agg = {}
    for c in cs:
        for k, v in c.get("peer_win_hist", {}).items():
            agg[int(k)] = agg.get(int(k), 0) + v
    tot = sum(agg.values())
    dom = max(agg, key=agg.get) if agg else 0
    zero = agg.get(0, 0)
    ge8 = sum(v for k, v in agg.items() if k >= 8 * MSS)
    bw = {}
    for c in cs:
        for k, v in c.get("board_win_hist", {}).items():
            bw[int(k)] = bw.get(int(k), 0) + v
    bdom = max(bw, key=bw.get) if bw else 0
    print("%-5s %6d %-34s %10.2f %9.1f %9.1f %8.1f %-14s %6d(%3.1fM) %7.1f%% %7.1f%% %10d" %
          (arm, len(cs),
           ",".join("%.1f" % c["rate_mbps"] for c in cs[:8]),
           med([c["uniq_mbps"] for c in cs]),
           med([c["held_pct"] for c in cs]),
           med([c["held_pct_tx"] for c in cs]),
           med([c["burst_pct"] for c in cs]),
           ",".join(str(c["first_seg_count"]) for c in cs[:10]),
           dom, dom / MSS,
           100.0 * zero / tot if tot else 0,
           100.0 * ge8 / tot if tot else 0,
           bdom))
