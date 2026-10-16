#!/usr/bin/env python3
"""decay_profile.py -- 100 ms B2P payload profile for one connection of a pcap.

Usage: python3 decay_profile.py <pcap> <cliport|auto> [nsecs]
  cliport 'auto' = the connection with the most B2P payload.
Prints the first nsecs (default 5 s) in 100 ms buckets (Mbps + cumulative),
plus the B2P/P2B packet counts in the first 0.5 s and the collapse timestamp
(first 100 ms bucket that is < 10% of the connection's running median).
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from faseg import read_pcap, parse_pkt

def main():
    pcap = sys.argv[1]
    want = sys.argv[2]
    nsecs = float(sys.argv[3]) if len(sys.argv) > 3 else 5.0
    pkts = []
    for (ts, lt, r) in read_pcap([pcap]):
        p = parse_pkt(ts, lt, r)
        if p and (p["sport"] == 8080 or p["dport"] == 8080):
            p["dir"] = "B2P" if p["src"] == "192.168.100.2" else "P2B"
            pkts.append(p)
    conns = {}
    for p in pkts:
        cp = p["sport"] if p["dir"] == "P2B" else p["dport"]
        conns.setdefault(cp, []).append(p)
    if want == "auto":
        cp = max(conns, key=lambda k: sum(x["pay"] for x in conns[k] if x["dir"] == "B2P"))
    else:
        cp = int(want)
    ps = sorted(conns[cp], key=lambda x: x["ts"])
    t0 = ps[0]["ts"]
    print("conn %d: pkts=%d span=%.3f s" % (cp, len(ps), ps[-1]["ts"] - t0))
    b2p05 = sum(1 for p in ps if p["dir"] == "B2P" and p["ts"] - t0 < 0.5)
    p2b05 = sum(1 for p in ps if p["dir"] == "P2B" and p["ts"] - t0 < 0.5)
    print("first 0.5 s: B2P pkts=%d  P2B pkts=%d" % (b2p05, p2b05))
    buckets = {}
    for p in ps:
        if p["dir"] != "B2P" or p["pay"] <= 0:
            continue
        b = int((p["ts"] - t0) * 10)
        buckets[b] = buckets.get(b, 0) + p["pay"]
    nb = int(nsecs * 10)
    tot = 0
    allb = sum(buckets.values())
    for b in range(nb):
        v = buckets.get(b, 0)
        tot += v
        if v or b < 10:
            print("t=%5.1f-%5.1f s %11d B %9.2f Mbps (cum %d)" % (b / 10, (b + 1) / 10, v, v * 8 / 0.1 / 1e6, tot))
    tail = [buckets.get(b, 0) for b in range(10, 50)]
    run = sorted(x for x in [buckets.get(b, 0) for b in range(0, 4)] if x > 0)
    if run:
        fast = run[len(run) // 2]
        for b in range(4, 60):
            v = buckets.get(b, 0)
            if v < fast * 0.1:
                print("COLLAPSE at t=%.1f s (bucket %d: %d B vs early median %d B)" % (b / 10, b, v, fast))
                break
        else:
            print("NO_COLLAPSE within 6 s (early median %d B/100ms)" % fast)

if __name__ == "__main__":
    main()
