#!/usr/bin/env python3
"""shapes.py -- compact per-connection shape table for p9_slowbasin_gc arms.

Per connection (from the 100 ms B2P buckets of the arm's ctl pcap):
  * t_syn (ms rel arm), first-0.4s rate (Mbps), collapse bucket (first 100 ms bucket
    after bucket 4 with < 10% of early median), x20 rate after collapse (median of
    100 ms buckets 5..30), whole-life rate (from unique-byte coverage), dup ratio.
Usage: python shapes.py <pcap> <label>
"""
import sys, os, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pcap_util_src import read_pcap, parse_pkt

BOARD = "192.168.100.2"

def main():
    path, label = sys.argv[1], sys.argv[2]
    pk = []
    for (ts, lt, r) in read_pcap([path]):
        p = parse_pkt(ts, lt, r)
        if p and (p["sport"] == 8080 or p["dport"] == 8080):
            p["dir"] = "B2P" if p["src"] == BOARD else "P2B"
            pk.append(p)
    pk.sort(key=lambda x: x["ts"])
    t0 = pk[0]["ts"]
    conns = collections.defaultdict(list)
    for p in pk:
        cp = p["sport"] if p["dir"] == "P2B" else p["dport"]
        conns[cp].append(p)
    print("=== SHAPES %s (pkts=%d span=%.1f s) ===" % (label, len(pk), pk[-1]["ts"] - t0))
    print("%-8s %9s %9s %8s %10s %10s %8s %7s %9s" %
          ("cliport", "t_syn_ms", "rate0.4s", "collapse", "crawl_rate", "uniqB", "dup", "life_s", "wireMbps"))
    for cp, ps in sorted(conns.items(), key=lambda kv: kv[1][0]["ts"]):
        ps.sort(key=lambda x: x["ts"])
        syn = next((p for p in ps if p["dir"] == "P2B" and (p["flags"] & 0x02) and not (p["flags"] & 0x10)), None)
        b2p = [p for p in ps if p["dir"] == "B2P" and p["pay"] > 0]
        if not b2p or syn is None:
            print("%-8s %9.1f %9s %8s %10s %10s %8s %7s %9s" % (cp, (syn["ts"] - t0) * 1e3 if syn else -1, "-", "-", "-", 0, "-", "-", "-"))
            continue
        d1 = b2p[0]
        b100 = [0] * 30
        for p in b2p:
            i = int((p["ts"] - d1["ts"]) / 0.1)
            if 0 <= i < 30:
                b100[i] += p["pay"]
        early = sorted(x for x in b100[:4] if x > 0)
        emed = early[len(early)//2] if early else 0
        c = None
        for i in range(4, 30):
            if emed and b100[i] < emed * 0.1:
                c = i; break
        r04 = sum(b100[:4]) * 8 / 0.4 / 1e6
        post = sorted(b100[i] for i in range(5, 30) if b100[i] > 0) if c is not None else []
        crawl = sum(post) * 8 / (0.1 * len(post)) / 1e6 if post else 0
        # unique coverage
        ini = d1["seq"]
        seen = set(); tot = 0
        for p in b2p:
            s0 = (p["seq"] - ini) & 0xFFFFFFFF
            for off in range(0, p["pay"], 1460):
                k = s0 + off
                if k not in seen:
                    seen.add(k)
            tot += p["pay"]
        uniq = len(seen) * 1460
        life = (b2p[-1]["ts"] - d1["ts"])
        print("%-8s %9.1f %9.2f %8s %10.2f %10d %8s %7.2f %9.2f" %
              (cp, (syn["ts"] - t0) * 1e3, r04,
               ("t=%.1f" % (c * 0.1)) if c is not None else "none",
               crawl, uniq, ("%.3f" % (1 - uniq / tot)) if tot else "-", life,
               tot * 8 / 1e6 / life if life > 0 else 0))

if __name__ == "__main__":
    main()
