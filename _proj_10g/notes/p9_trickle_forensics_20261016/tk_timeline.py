#!/usr/bin/env python3
"""tk_timeline.py <pcap> <t0_abs> [ctl_pcap...]  -- arm-level connection lifecycle table.
Columns: dport, synack_t, first_data_t, last_data_t, ndata, fin_t (earliest FIN/RST from ctl), 
all times relative to t0_abs (run start).
"""
import sys, collections
sys.path.insert(0, '.')
from tk_dump import iter_packets, parse

def main():
    pcap = sys.argv[1]; t0 = float(sys.argv[2]); ctls = sys.argv[3:]
    conns = {}
    for t, d in iter_packets(pcap):
        r = parse(d)
        if r is None: continue
        src, sport, dp, seq, ack, flags, win, pl = r
        if sport != 8080 or src != "192.168.100.2": continue
        c = conns.setdefault(dp, {"synack": None, "first": None, "last": None, "n": 0})
        if flags & 0x02 and not (flags & 0x10):
            if c["synack"] is None: c["synack"] = t
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
    print("dport synack first_data last_data ndata fin_1st fin_n")
    for dp in sorted(conns):
        c = conns[dp]
        f = fins.get(dp, [])
        ft = f"{f[0][0]-t0:.3f}(fl=0x{f[0][1]:02x},win={f[0][2]})" if f else "-"
        print("%6d %8s %10s %10s %6d %s %4d" % (
            dp,
            f"{c['synack']-t0:.3f}" if c['synack'] else "-",
            f"{c['first']-t0:.3f}" if c['first'] else "-",
            f"{c['last']-t0:.3f}" if c['last'] else "-",
            c["n"], ft, len(f)))
    # also: connections seen only in ctl (no data)
    for dp in sorted(fins):
        if dp not in conns:
            f = fins[dp]
            print("%6d %8s %10s %10s %6d %s %4d" % (dp, "-", "-", "-", 0,
                  f"{f[0][0]-t0:.3f}(fl=0x{f[0][1]:02x},win={f[0][2]})", len(f)))

if __name__ == "__main__":
    main()
