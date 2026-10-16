#!/usr/bin/env python3
"""tkbi.py -- bidirectional pcap analyzer for the trickle experiment A (port 8080).

Reads a pcap ring (full.pcap0..7) or a single pcap; no external deps.
Usage:
  python tkbi.py <pcap...> [--board 192.168.100.2] [--peer 192.168.100.100] [--port 8080]
                 [--conns] [--stream DPORT] [--clusters DPORT] [--acks DPORT]
"""
import struct, sys, argparse, collections

def read_pcap(paths):
    """yield (ts, raw_eth_payload) for all packets in all files (sorted by ts)."""
    pkts = []
    for p in paths:
        with open(p, "rb") as fh:
            data = fh.read()
        if len(data) < 24:
            continue
        magic = data[:4]
        if magic == b"\xd4\xc3\xb2\xa1":
            endian, nano = "<", False
        elif magic == b"\xa1\xb2\xc3\xd4":
            endian, nano = ">", False
        elif magic == b"\x4d\x3c\xb2\xa1":
            endian, nano = "<", True
        elif magic == b"\xa1\xb2\x3c\x4d":
            endian, nano = ">", True
        else:
            sys.stderr.write("BAD_MAGIC %s %r\n" % (p, magic)); continue
        (_, _, _, _, _, linktype) = struct.unpack(endian + "HHIIII", data[4:24])
        off = 24
        n = 0
        while off + 16 <= len(data):
            ts_s, ts_f, incl, orig = struct.unpack(endian + "IIII", data[off:off+16])
            off += 16
            if off + incl > len(data):
                sys.stderr.write("TRUNCATED %s at off %d (incl=%d)\n" % (p, off, incl)); break
            ts = ts_s + (ts_f / 1e9 if nano else ts_f / 1e6)
            pkts.append((ts, linktype, data[off:off+incl]))
            off += incl
            n += 1
        sys.stderr.write("read %s: %d pkts linktype=%d\n" % (p, n, linktype))
    pkts.sort(key=lambda x: x[0])
    return pkts

def parse_pkt(ts, linktype, raw):
    """-> dict or None. Handles Ethernet (1) and Linux SLL (113)."""
    if linktype == 1:
        if len(raw) < 14: return None
        eth_type = struct.unpack("!H", raw[12:14])[0]
        pay = raw[14:]
        if eth_type == 0x8100:  # vlan
            if len(pay) < 4: return None
            eth_type = struct.unpack("!H", pay[2:4])[0]; pay = pay[4:]
        if eth_type != 0x0800: return None
    elif linktype == 113:  # SLL
        if len(raw) < 16: return None
        eth_type = struct.unpack("!H", raw[14:16])[0]
        pay = raw[16:]
        if eth_type != 0x0800: return None
    else:
        return None
    if len(pay) < 20: return None
    ihl = (pay[0] & 0xF) * 4
    if pay[9] != 6: return None  # TCP
    total_len = struct.unpack("!H", pay[2:4])[0]
    src = ".".join(str(b) for b in pay[12:16])
    dst = ".".join(str(b) for b in pay[16:20])
    t = pay[ihl:]
    if len(t) < 20: return None
    sport, dport, seq, ack, off_flags, win = struct.unpack("!HHIIHH", t[0:16])
    doff = (off_flags >> 12) * 4
    flags = off_flags & 0x1FF
    opts = t[20:doff] if doff > 20 else b""
    pay_len = total_len - ihl - doff
    if pay_len < 0: pay_len = 0
    tsval = None
    i = 0
    while i + 1 < len(opts):
        k = opts[i]
        if k == 0: break
        if k == 1: i += 1; continue
        if i + 1 >= len(opts): break
        ln = opts[i+1]
        if ln < 2: break
        if k == 8 and ln == 10:
            tsval = struct.unpack("!I", opts[i+2:i+6])[0]
        i += ln
    return dict(ts=ts, src=src, dst=dst, sport=sport, dport=dport, seq=seq, ack=ack,
                flags=flags, win=win, pay=pay_len, tsval=tsval)

FL = [(0x01, "F"), (0x02, "S"), (0x04, "R"), (0x08, "P"), (0x10, "A")]
def fstr(f):
    return "".join(n for b, n in FL if f & b) or "-"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pcaps", nargs="+")
    ap.add_argument("--board", default="192.168.100.2")
    ap.add_argument("--peer", default="192.168.100.100")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--conns", action="store_true")
    ap.add_argument("--stream", type=int, default=None, help="dport of connection to dump")
    ap.add_argument("--clusters", type=int, default=None)
    ap.add_argument("--acks", type=int, default=None, help="peer->board ACK analysis for dport")
    ap.add_argument("--limit", type=int, default=80)
    ap.add_argument("--from", dest="tfrom", type=float, default=None, help="stream window start (s rel t0)")
    ap.add_argument("--to", dest="tto", type=float, default=None, help="stream window end (s rel t0)")
    a = ap.parse_args()

    raw = read_pcap(a.pcaps)
    pkts = []
    for (ts, lt, r) in raw:
        p = parse_pkt(ts, lt, r)
        if p and (p["sport"] == a.port or p["dport"] == a.port):
            p["dir"] = "B2P" if p["src"] == a.board else ("P2B" if p["src"] == a.peer else "OTH")
            pkts.append(p)
    if not pkts:
        print("NO_PKTS"); return
    t0 = pkts[0]["ts"]
    print("pkts=%d span=%.3fs t0=%.6f" % (len(pkts), pkts[-1]["ts"] - t0, t0))
    nb2p = sum(1 for p in pkts if p["dir"] == "B2P")
    np2b = sum(1 for p in pkts if p["dir"] == "P2B")
    print("dir: B2P=%d P2B=%d OTH=%d" % (nb2p, np2b, len(pkts) - nb2p - np2b))
    # flag census by direction
    fc = collections.Counter((p["dir"], fstr(p["flags"])) for p in pkts)
    print("flag census:", dict(fc))

    if a.conns:
        conns = collections.defaultdict(lambda: dict(n=0, syn=0, synack=0, fin=0, rst=0, b2p=0, p2b=0,
                                                     first=None, last=None, data_b2p=0, data_p2b=0))
        for p in pkts:
            first = True
            marks = []
            if p["flags"] & 0x02: marks.append("syn")
            if p["flags"] & 0x01: marks.append("fin")
            if p["flags"] & 0x04: marks.append("rst")
            if p["dir"] == "B2P":
                if p["sport"] == a.port:
                    key = ("cli", p["dport"])
                    c = conns[key]; c["b2p"] += 1
                    if p["pay"]: c["data_b2p"] += p["pay"]
                    if p["flags"] & 0x02: c["synack"] += 1
                elif p["dport"] == a.port:
                    key = ("srv", p["sport"])
                    c = conns[key]; c["b2p"] += 1
                    if p["pay"]: c["data_b2p"] += p["pay"]
                    if p["flags"] & 0x02: c["synack"] += 1
                else:
                    continue
            else:
                if p["dport"] == a.port:
                    key = ("cli", p["sport"])
                elif p["sport"] == a.port:
                    key = ("srv", p["dport"])
                else:
                    continue
                c = conns[key]; c["p2b"] += 1
                if p["pay"]: c["data_p2b"] += p["pay"]
            c["n"] += 1
            for m in marks: c[m] += 1
            if c["first"] is None: c["first"] = p["ts"]
            c["last"] = p["ts"]
        print("\n=== connection census (key=(role,cli_port); times rel t0) ===")
        print("%-14s %8s %6s %8s %5s %5s %10s %10s %8s %8s" %
              ("key", "pkts", "syn/sa", "fin/rst", "b2p", "p2b", "dataB2P", "dataP2B", "first", "last"))
        for k, c in sorted(conns.items(), key=lambda kv: kv[1]["first"] or 0):
            print("%-14s %8d %2d/%-2d %4d/%-4d %5d %5d %10d %10d %8.3f %8.3f" %
                  ("%s:%d" % k, c["n"], c["syn"], c["synack"], c["fin"], c["rst"],
                   c["b2p"], c["p2b"], c["data_b2p"], c["data_p2b"],
                   (c["first"] or t0) - t0, (c["last"] or t0) - t0))

    def sel(dport):
        return [p for p in pkts if p["dport"] == dport or p["sport"] == dport]

    if a.stream is not None:
        ss = sel(a.stream)
        if a.tfrom is not None or a.tto is not None:
            lo = t0 + (a.tfrom if a.tfrom is not None else 0)
            hi = t0 + (a.tto if a.tto is not None else 1e18)
            ss = [p for p in ss if lo <= p["ts"] <= hi]
        print("\n=== stream dump port=%d n=%d (window [%s,%s]) ===" %
              (a.stream, len(ss), a.tfrom, a.tto))
        for p in ss[:a.limit]:
            print("t=%9.6f %s %s:%d>%s:%d %-4s seq=%u ack=%u win=%u pay=%d tsval=%s" %
                  (p["ts"] - t0, p["dir"], p["src"], p["sport"], p["dst"], p["dport"],
                   fstr(p["flags"]), p["seq"], p["ack"], p["win"], p["pay"], p["tsval"]))
        if len(ss) > a.limit:
            print("... (%d more)" % (len(ss) - a.limit))

    if a.clusters is not None:
        ss = [p for p in sel(a.clusters) if p["pay"] > 0]
        print("\n=== clusters port=%d data pkts=%d ===" % (a.clusters, len(ss)))
        if len(ss) > 1:
            gaps = [(ss[i]["ts"] - ss[i-1]["ts"]) for i in range(1, len(ss))]
            big = [(i, g) for i, g in enumerate(gaps) if g > 0.015]
            print("n_clusters=%d  first=%9.6f last=%9.6f span=%.3f" %
                  (len(big) + 1, ss[0]["ts"] - t0, ss[-1]["ts"] - t0, ss[-1]["ts"] - ss[0]["ts"]))
            periods = [(ss[big[i][0] + 1]["ts"] - ss[big[i-1][0] + 1]["ts"]) for i in range(1, len(big))]
            if periods:
                periods.sort()
                print("cluster period ms: min=%.3f med=%.3f max=%.3f" %
                      (periods[0] * 1e3, periods[len(periods)//2] * 1e3, periods[-1] * 1e3))
            # sizes
            bounds = [0] + [i for (i, g) in big] + [len(ss)]
            sizes = collections.Counter()
            for j in range(len(bounds) - 1):
                sizes[bounds[j+1] - bounds[j]] += 1
            print("cluster sizes:", dict(sorted(sizes.items())))
            # replay (dup seq) analysis
            seen = {}
            dup = 0; conflict = 0
            for p in ss:
                if p["seq"] in seen:
                    dup += 1
                    if seen[p["seq"]] != p["pay"]: conflict += 1
                else:
                    seen[p["seq"]] = p["pay"]
            print("dup_pkts=%d conflict=%d new_pkts=%d" % (dup, conflict, len(ss) - dup))

    if a.acks is not None:
        ss = sel(a.acks)
        b2p = [p for p in ss if p["dir"] == "B2P" and p["pay"] > 0]
        p2b = [p for p in ss if p["dir"] == "P2B"]
        print("\n=== ACK analysis port=%d (B2P data=%d, P2B=%d) ===" % (a.acks, len(b2p), len(p2b)))
        wc = collections.Counter(p["win"] for p in p2b)
        print("peer win histogram:", dict(sorted(wc.items())))
        fc2 = collections.Counter(fstr(p["flags"]) for p in p2b if p["pay"] == 0)
        print("peer flag census (nopay):", dict(fc2))
        # cluster alignment: for each board data pkt, find peer ACKs within +2ms
        import bisect
        pt = [p["ts"] for p in p2b]
        near = collections.Counter()
        gaps = []
        for p in b2p:
            i = bisect.bisect_left(pt, p["ts"])
            got = []
            while i < len(pt) and pt[i] - p["ts"] <= 0.002:
                got.append(pt[i] - p["ts"]); i += 1
            near[len(got)] += 1
        print("peer-ACKs within 2ms AFTER each B2P data pkt:", dict(sorted(near.items())))
        # cluster the board stream and count peer acks per cluster
        if len(b2p) > 1:
            big = [(i, b2p[i]["ts"] - b2p[i-1]["ts"]) for i in range(1, len(b2p)) if b2p[i]["ts"] - b2p[i-1]["ts"] > 0.015]
            bounds = [0] + [i for (i, g) in big] + [len(b2p)]
            per = collections.Counter()
            ack_delay = []
            pt_sort = sorted(pt)
            for j in range(len(bounds) - 1):
                lo = b2p[bounds[j]]["ts"]
                hi = b2p[bounds[j+1]]["ts"] if bounds[j+1] < len(b2p) else b2p[-1]["ts"] + 0.020
                cnt = bisect.bisect_left(pt_sort, hi) - bisect.bisect_left(pt_sort, lo)  # non-overlapping
                per[cnt] += 1
                # delay of the FIRST peer ACK at/after this cluster's last data pkt
                lastd = b2p[bounds[j+1] - 1]["ts"]
                k2 = bisect.bisect_left(pt_sort, lastd)
                if k2 < len(pt_sort):
                    ack_delay.append(pt_sort[k2] - lastd)
            print("n_clusters=%d peer-ACKs-per-cluster histogram (non-overlapping windows):" % (len(bounds) - 1))
            for k in sorted(per): print("   %2d acks: %d clusters" % (k, per[k]))
            if ack_delay:
                ack_delay.sort()
                print("ack delay from cluster end, ms: min=%.3f med=%.3f max=%.3f n=%d" %
                      (ack_delay[0]*1e3, ack_delay[len(ack_delay)//2]*1e3, ack_delay[-1]*1e3, len(ack_delay)))

if __name__ == "__main__":
    main()
