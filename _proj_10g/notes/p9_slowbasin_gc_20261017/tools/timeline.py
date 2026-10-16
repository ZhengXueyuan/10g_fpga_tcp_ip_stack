#!/usr/bin/env python3
"""timeline.py -- per-connection per-second / per-100ms B2P timeline profiler for the
'ctl' pcaps of p9_slowbasin_gc_20261017 (full 'tcp port 8080', snaplen 128, so IP
header lengths are intact => payload countable from tot_len).

For every connection (peer-side cliport):
  * handshake times: SYN / SYN-ACK / first data / first ack (rel to arm t0, and rel to conn SYN)
  * total B2P payload, duration, overall rate
  * 100 ms buckets for the first 3 s (crash-point resolution; "快→崩" shape)
  * 1 s buckets over the whole life (crawl shape; printed while nonzero, then every 10th)
  * collapse point: first 100 ms bucket (after the first 0.4 s) < 10% of early median
  * B2P inter-arrival gaps > 50 ms: count / max / median / first few start times
    and a '20 ms cluster clock' check (gaps in [10,30) ms vs rest) during the crawl phase
  * FIN/RST census per direction with times

Usage: python timeline.py <pcap> [<pcap>...] [--label TAG]
Parser = pcap_util_src.py (verbatim copy of p9_t2fast_ab_20261017/tools/faseg.py; md5 f574e17113c0c97dd6f57060b1c40ce3).
"""
import sys, os, argparse, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pcap_util_src import read_pcap, parse_pkt, fstr

BOARD = "192.168.100.2"
PEER = "192.168.100.100"
PORT = 8080


def load(paths):
    pkts = []
    for (ts, lt, r) in read_pcap(paths):
        p = parse_pkt(ts, lt, r)
        if p and (p["sport"] == PORT or p["dport"] == PORT):
            if p["src"] == BOARD:
                p["dir"] = "B2P"
            elif p["src"] == PEER:
                p["dir"] = "P2B"
            else:
                continue
            pkts.append(p)
    pkts.sort(key=lambda x: x["ts"])
    return pkts


def buckets(ps, t0, width, n):
    b = [0] * n
    for p in ps:
        i = int((p["ts"] - t0) / width)
        if 0 <= i < n:
            b[i] += p["pay"]
    return b


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pcaps", nargs="+")
    ap.add_argument("--label", default="")
    a = ap.parse_args()
    pkts = load(a.pcaps)
    if not pkts:
        print("NO_PKTS"); return
    t0 = pkts[0]["ts"]
    tend = pkts[-1]["ts"]
    print("=== timeline label=%s pkts=%d span=%.3f s ===" % (a.label, len(pkts), tend - t0))

    conns = collections.defaultdict(list)
    for p in pkts:
        cp = p["sport"] if p["dir"] == "P2B" else p["dport"]
        conns[cp].append(p)

    print("\n--- handshake table (ms rel t0) ---")
    print("%-7s %6s %10s %10s %10s %10s %10s %12s %9s" %
          ("cliport", "pkts", "t_syn", "t_synack", "sa->d1", "d1->ack1", "dur_s", "payB2P", "mbps"))
    summary = []
    for cp, ps in sorted(conns.items(), key=lambda kv: kv[1][0]["ts"]):
        ps.sort(key=lambda x: x["ts"])
        syn = next((p for p in ps if p["dir"] == "P2B" and (p["flags"] & 0x02) and not (p["flags"] & 0x10)), None)
        synack = next((p for p in ps if p["dir"] == "B2P" and (p["flags"] & 0x12) == 0x12), None)
        d1 = next((p for p in ps if p["dir"] == "B2P" and p["pay"] > 0), None)
        b2p = [p for p in ps if p["dir"] == "B2P" and p["pay"] > 0]
        pay = sum(p["pay"] for p in b2p)
        if d1 is None:
            print("%-7d %6d %10.3f %10.3f %10s %10s %10s %12d %9s" %
                  (cp, len(ps), (syn["ts"] - t0) * 1e3 if syn else -1,
                   (synack["ts"] - t0) * 1e3 if synack else -1, "-", "-", "-", 0, "-"))
            summary.append((cp, 0, 0.0, 0.0))
            continue
        dur = ps[-1]["ts"] - d1["ts"]
        mbps = pay * 8 / 1e6 / dur if dur > 0 else 0
        first_ack = None
        end_seq = d1["seq"] + d1["pay"]
        for p in ps:
            if p["dir"] == "P2B" and (p["flags"] & 0x10) and p["ts"] >= d1["ts"] and p["pay"] == 0:
                if ((p["ack"] - end_seq) & 0xFFFFFFFF) < 0x80000000:
                    first_ack = p; break
        print("%-7d %6d %10.3f %10.3f %10.3f %10.3f %10.3f %12d %9.3f" %
              (cp, len(ps), (syn["ts"] - t0) * 1e3 if syn else -1,
               (synack["ts"] - t0) * 1e3 if synack else -1,
               (d1["ts"] - synack["ts"]) * 1e3 if synack else -1,
               (first_ack["ts"] - d1["ts"]) * 1e3 if first_ack else -1,
               dur, pay, mbps))
        summary.append((cp, pay, dur, mbps))

    # per-connection detail
    for cp, ps in sorted(conns.items(), key=lambda kv: kv[1][0]["ts"]):
        ps.sort(key=lambda x: x["ts"])
        b2p = [p for p in ps if p["dir"] == "B2P" and p["pay"] > 0]
        if not b2p:
            continue
        d1 = b2p[0]
        print("\n=== CONN %d detail (t0'=% .3f s rel arm) ===" % (cp, d1["ts"] - t0))
        # 100 ms first 3 s
        b100 = buckets(b2p, d1["ts"], 0.1, 30)
        early = sorted(x for x in b100[:6] if x > 0)
        emed = early[len(early)//2] if early else 0
        line = []
        for i, v in enumerate(b100):
            line.append("%d:%d" % (i, v))
        print("  b100ms[0,3s] (B): " + " ".join(line))
        coll = None
        for i in range(4, 30):
            if emed and b100[i] < emed * 0.1:
                coll = i; break
        if coll is not None:
            print("  COLLAPSE_100ms at t=%.1f s (bucket %d = %d B vs early median %d B)"
                  % (coll * 0.1, coll, b100[coll], emed))
        span = ps[-1]["ts"] - d1["ts"]
        n1 = int(span) + 1
        b1 = buckets(b2p, d1["ts"], 1.0, n1)
        row = []
        for i, v in enumerate(b1):
            if i < 20 or v > 0:
                row.append("%d:%d" % (i, v))
        print("  b1s (B, first20 + all nonzero): " + " ".join(row[:80]) + (" ..." if len(row) > 80 else ""))
        # gaps
        gaps = []
        for a_, b_ in zip(b2p, b2p[1:]):
            g = b_["ts"] - a_["ts"]
            if g > 0.05:
                gaps.append((a_["ts"] - d1["ts"], g))
        if gaps:
            gs = sorted(g for _, g in gaps)
            gmed = gs[len(gs)//2]
            cluster = sum(1 for _, g in gaps if 0.010 <= g < 0.030)
            print("  gaps>50ms: n=%d max=%.3f s med=%.3f s  (in[10,30)ms: %d)  first8: %s"
                  % (len(gaps), gs[-1], gmed, cluster,
                     " ".join("t%.2f+%.3f" % (t, g) for t, g in gaps[:8])))
        else:
            print("  gaps>50ms: n=0 (continuous)")
        # crawl-phase packet inter-arrival (all B2P pkts, last 80% of life)
        tail = [p for p in b2p if (p["ts"] - d1["ts"]) > 2.0]
        if len(tail) > 10:
            dg = [t2["ts"] - t1["ts"] for t1, t2 in zip(tail, tail[1:])]
            ds = sorted(dg)
            print("  crawl-phase B2P pkt gaps (n=%d after t>2s): med=%.4f s p90=%.4f" %
                  (len(dg), ds[len(ds)//2] if ds else 0, ds[int(len(ds)*0.9)] if ds else 0))

    # FIN/RST census
    print("\n--- FIN/RST census (rel t0) ---")
    cnt = collections.Counter()
    for p in pkts:
        fl = p["flags"]
        if fl & 0x01:
            cnt["%s:F" % p["dir"]] += 1
        if fl & 0x04:
            cnt["%s:R" % p["dir"]] += 1
    print("  " + (", ".join("%s=%d" % kv for kv in sorted(cnt.items())) or "none"))
    for p in pkts:
        if p["flags"] & 0x05:
            print("  t=% 8.3f %s %s:%d->%s:%d %s seq=%u ack=%u" %
                  (p["ts"] - t0, p["dir"], p["src"], p["sport"], p["dst"], p["dport"],
                   fstr(p["flags"]), p["seq"], p["ack"]))

    print("\n--- summary ---")
    tot = sum(s[1] for s in summary)
    print("  conns=%d totalB2P=%d bytes (%.3f MB) span=%.3f s agg=%.3f Mbps"
          % (len(summary), tot, tot / 1e6, tend - t0, tot * 8 / 1e6 / (tend - t0)))


if __name__ == "__main__":
    main()
