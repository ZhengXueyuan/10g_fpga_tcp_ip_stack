#!/usr/bin/env python3
"""tk_timeline2.py <full.pcap> <t0_abs> [ctl.pcap] -- arm-level connection lifecycle.
Fixes the SYN-ACK detection ((flags & 0x12)==0x12).  t0_abs = run K0M_BEGIN wall time.
Outputs per connection: SYN-ACK t, first/last data t, n data segs, first FIN t (from ctl) + win,
and (if a FIN exists) the time of the last board packet before it.
"""
import sys, collections
sys.path.insert(0, '.')
from tk_dump import iter_packets, parse

def main():
    pcap, t0 = sys.argv[1], float(sys.argv[2])
    ctls = sys.argv[3:]
    conns = {}
    for t, d in iter_packets(pcap):
        r = parse(d)
        if r is None: continue
        src, sport, dp, seq, ack, flags, win, pl = r
        if sport != 8080 or src != "192.168.100.2": continue
        c = conns.setdefault(dp, {"synack": None, "first": None, "last": None, "n": 0, "any": None})
        c["any"] = t
        if (flags & 0x12) == 0x12 and c["synack"] is None: c["synack"] = t
        if pl:
            if c["first"] is None: c["first"] = t
            c["last"] = t; c["n"] += 1
    fins = collections.defaultdict(list)
    for cp in ctls:
        for t, d in iter_packets(cp):
            r = parse(d)
            if r is None: continue
            src, sport, dp, seq, ack, flags, win, pl = r
            if dp == 8080 and (flags & 0x01 or flags & 0x04):
                fins[sport].append((t, flags, win, ack))
    ISN = 0x12345678
    print("dport   SYN-ACK  data_start data_end  ndata  last_pkt_b4_FIN  FIN1(t,win,ackoff)   FINn")
    for dp in sorted(conns, key=lambda d: (conns[d]['synack'] or 1e18, d)):
        c = conns[dp]; f = fins.get(dp, [])
        sa = f"{c['synack']-t0:8.3f}" if c['synack'] else "       -"
        fs = f"{c['first']-t0:8.3f}" if c['first'] else "       -"
        ls = f"{c['last']-t0:8.3f}" if c['last'] else "       -"
        if f:
            ft = f[0][0]
            ftx = f"{ft-t0:8.3f}(win={f[0][2]:5d},ackoff={((f[0][3]-ISN-1)&0xffffffff)})"
            gap = f"{ft-c['any']:7.3f}"
        else:
            ftx = "        -"; gap = "      -"
        print(f"{dp:6d} {sa} {fs} {ls} {c['n']:6d} {gap:>16} {ftx:>40} {len(f):4d}")
    for dp in sorted(fins):
        if dp not in conns:
            f = fins[dp]
            print(f"{dp:6d} (no SYN-ACK, no data)  FIN1={f[0][0]-t0:.3f}(win={f[0][2]},ackoff={((f[0][3]-ISN-1)&0xffffffff)}) n={len(f)}")

if __name__ == "__main__":
    main()
