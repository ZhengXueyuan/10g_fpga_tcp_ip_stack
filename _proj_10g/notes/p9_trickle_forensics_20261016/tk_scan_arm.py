#!/usr/bin/env python3
"""tk_scan_arm.py <pcap> -- per-connection census of a B4 full pcap (B2P only).
Prints one line per dport: segs, span, seg/s, unique offs, dup segs, max gap, burst period mode.
"""
import sys, collections, statistics
sys.path.insert(0, '.')
from tk_dump import iter_packets, parse

def main():
    pcap = sys.argv[1]
    conns = {}
    for t, d in iter_packets(pcap):
        r = parse(d)
        if r is None: continue
        src, sport, dp, seq, ack, flags, win, pl = r
        if sport != 8080 or src != "192.168.100.2": continue
        if not pl: continue
        conns.setdefault(dp, []).append((t, seq, len(pl), flags))
    rows = []
    for dp, segs in conns.items():
        segs.sort()
        base = min(s for _, s, _, _ in segs)
        t0, t1 = segs[0][0], segs[-1][0]
        span = t1 - t0
        offs = collections.Counter(((s - base) & 0xFFFFFFFF) for _, s, _, _ in segs)
        dups = sum(c - 1 for c in offs.values() if c > 1)
        maxoff = max(offs)
        gaps = [segs[i+1][0]-segs[i][0] for i in range(len(segs)-1)]
        mg = max(gaps) if gaps else 0
        # burst period mode
        bursts = []; cur = [segs[0]]
        for i in range(1, len(segs)):
            if segs[i][0]-segs[i-1][0] > 0.002: bursts.append(cur); cur = []
            cur.append(segs[i])
        bursts.append(cur)
        bt = [b[0][0] for b in bursts]
        ip = [bt[i+1]-bt[i] for i in range(len(bt)-1) if bt[i+1]-bt[i] > 0.001]
        pm = statistics.median(ip) if ip else 0
        rows.append((dp, len(segs), span, len(segs)/span if span else 0, len(offs),
                     dups, 100.0*dups/len(segs), mg, len(bursts), pm, len(segs)/max(len(bursts),1)))
    rows.sort()
    print(f"# {pcap}: conns={len(rows)}")
    print("dport segs span_s seg/s uniq_offs dup_segs dup% max_gap_s bursts med_burst_period segs/burst")
    for r in rows:
        print("%6d %6d %8.3f %8.1f %8d %7d %5.1f %8.3f %6d %8.4f %6.2f" % r)

if __name__ == "__main__":
    main()
