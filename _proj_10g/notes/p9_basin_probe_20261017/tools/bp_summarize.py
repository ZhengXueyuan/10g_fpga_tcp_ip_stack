#!/usr/bin/env python3
"""bp_summarize.py -- aggregate the p9_basin_probe_20261017 arm artifacts.

Adapted from p9_slowbasin_gc_20261017/tools/summarize_basin.py (same snap/nstat parsers),
retargeted to raw/bp_<TAG>_* + runs/<TAG>_stdout.txt.  Adds:
  * W63/W64/W65 duty vs W5 (the design's 'true value' request; ring basis, no PRE/POST wrap)
  * W20 = W52 + W55 identity check (design sec.1.2)
  * W57/W58 note (session too short for 3 Hz ring)
Usage: python bp_summarize.py TAG [TAG ...]
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
RAW = os.path.join(ROOT, "raw")
RUNS = os.path.join(ROOT, "runs")
TAGS = sys.argv[1:]
if not TAGS:
    TAGS = ["B0", "B1", "B2"]
M32 = 1 << 32

RING_WORDS = [5, 20, 43, 51, 52, 55, 63, 64, 65, 66, 67, 68, 69, 57, 58]
PRE_WORDS = [5, 20, 43, 51, 52, 55, 63, 64, 65, 66, 67, 68, 69, 71, 72, 73, 74]
NKEYS = ["TcpInSegs", "TcpOutSegs", "TcpRetransSegs", "TcpExtTCPOFOQueue", "TcpExtTCPFastRetrans",
         "TcpExtTCPACKSkippedSeq", "TcpExtDelayedACKs", "TcpExtDelayedACKLocked", "TcpExtDelayedACKLost",
         "TcpExtTCPPureAcks", "TcpExtTCPHPAcks"]


def rd(p):
    with open(p, "r", errors="replace") as f:
        return f.read()


def snap_parse(path):
    out, cur, t = [], None, None
    for line in rd(path).splitlines():
        if line.startswith("SNAP_T "):
            t = float(line.split()[1])
        elif line.startswith("SNAP_BEGIN"):
            cur = {}
        elif line.startswith("SNAP_END"):
            if cur is not None and t is not None:
                out.append((t, cur))
            cur = None
        elif cur is not None and line.startswith("W"):
            m = re.match(r"W(\d+)\s+0x[0-9A-Fa-f]+\s+\S+\s+(0x[0-9a-fA-F]+)", line)
            if m:
                cur[int(m.group(1))] = int(m.group(2), 16)
    return out


def ring_rates(samples):
    """median successive-sample rate per word (mod 2^32); also min/max/span."""
    rates = {}
    for w in RING_WORDS:
        vals = []
        for i in range(len(samples) - 1):
            t0, a = samples[i]
            t1, b = samples[i + 1]
            if w in a and w in b and t1 > t0:
                vals.append(((b[w] - a[w]) % M32) / (t1 - t0))
        if vals:
            vals.sort()
            rates[w] = dict(med=vals[len(vals) // 2], mn=vals[0], mx=vals[-1], n=len(vals))
    return rates


def pre_post(path):
    vals = {}
    for line in rd(path).splitlines():
        m = re.match(r"W(\d+)\s+\S+\s+\S+\s+(0x[0-9a-fA-F]+)", line)
        if m:
            vals[int(m.group(1))] = int(m.group(2), 16)
    return vals


def nstat(path):
    d = {}
    for line in rd(path).splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0].startswith("Tcp"):
            try:
                d[parts[0]] = int(parts[1])
            except ValueError:
                pass
    return d


def main():
    print("=" * 118)
    print("p9_basin_probe_20261017 -- per-arm readings (ring = KW basis, mod 2^32)")
    print("=" * 118)
    for tag in TAGS:
        base = os.path.join(RAW, "bp_%s" % tag)
        so = os.path.join(RUNS, "%s_stdout.txt" % tag)
        if not os.path.exists(so):
            print("\n### %s : stdout MISSING" % tag)
            continue
        txt = rd(so)
        print("\n" + "#" * 100)
        begin = re.search(r"### K0M_BEGIN (.+)", txt)
        print("### %s" % (begin.group(1) if begin else "(no K0M_BEGIN)"))
        for pat in [r"### SINK_MD5 \S+", r"### SINK_OPTS_WITNESS .*", r"### SINK_RC_SUM.*", r"### K0M_END .*"]:
            for m in re.finditer(pat, txt):
                print("    " + m.group(0))
        for m in re.finditer(r"SINK_SUM .*", txt):
            print("    SUM " + m.group(0)[:230])
        connrows = re.findall(r"SINK_CONN (\d+) (OK|STALL|POLL_TIMEOUT|ERR|FAIL_CONNECT)([^\n]*)", txt)
        rates = []
        for m in connrows:
            mm = re.search(r"Mbps=([\d.]+)", m[2])
            if mm:
                rates.append(float(mm.group(1)))
        if rates:
            print("    per-conn Mbps: %s" % ", ".join("%.3f" % r for r in rates))
            nfast = sum(1 for r in rates if r >= 100)
            ncr = sum(1 for r in rates if r <= 5)
            print("    VERDICT-READ (n=%d): fast(>=100Mbps)=%d crawl(<=5Mbps)=%d mid=%d" %
                  (len(rates), nfast, ncr, len(rates) - nfast - ncr))
        cap = re.search(r"(\d+) packets captured", txt)
        rec = re.search(r"(\d+) packets received by filter", txt)
        dro = re.search(r"(\d+) packets dropped by kernel", txt)
        if cap:
            print("    pcap: captured=%s received=%s dropped=%s" % (cap.group(1), rec.group(1), dro.group(1)))
        sp = base + "_snap.log"
        if os.path.exists(sp):
            samples = snap_parse(sp)
            rr = ring_rates(samples)
            span = (samples[-1][0] - samples[0][0]) if len(samples) > 1 else 0
            print("    snap ring: n=%d span=%.2fs" % (len(samples), span))
            if rr:
                print("      " + " ".join("W%d=%s" % (w, ("%.3f" % rr[w]["med"]) if w in rr else "-")
                                          for w in [5, 20, 43, 51, 52, 55, 66, 67, 68]))
                if all(w in rr for w in (20, 52, 55)) and rr[5]["med"]:
                    lhs, rhs = rr[20]["med"], rr[52]["med"] + rr[55]["med"]
                    print("      W20 = W52+W55 : %.3f vs %.3f (diff %.3f%%)" %
                          (lhs, rhs, 100.0 * (lhs - rhs) / lhs if lhs else 0))
                if all(w in rr for w in (63, 64, 65)) and 5 in rr and rr[5]["med"]:
                    print("      duties (ring): W63/W5=%.4f W64/W5=%.6f W65/W5=%.4f" %
                          (rr[63]["med"] / rr[5]["med"], rr[64]["med"] / rr[5]["med"], rr[65]["med"] / rr[5]["med"]))
                if 66 in rr and 67 in rr:
                    print("      W67/W66=%s (W66 rate %.1f/s)" %
                          (("%.4f" % (rr[67]["med"] / rr[66]["med"])) if rr[66]["med"] else "-", rr[66]["med"]))
                if 57 in rr or 58 in rr:
                    print("      W57=%s W58=%s (session-level; 3 Hz ring sees only long sessions)" %
                          (("%.3f" % rr[57]["med"]) if 57 in rr else "-",
                           ("%.4f" % rr[58]["med"]) if 58 in rr else "-"))
        pp, po = base + "_pre.txt", base + "_post.txt"
        if os.path.exists(pp) and os.path.exists(po):
            a, b = pre_post(pp), pre_post(po)
            print("    PRE/POST deltas (mod 2^32): " + " ".join(
                "W%d=%d" % (w, (b[w] - a[w]) % M32) for w in PRE_WORDS if w in a and w in b))
            if all(w in a and w in b for w in (71, 72, 73, 74)):
                d_ev = (b[71] - a[71]) % M32
                d_sw = (b[72] - a[72]) % M32
                d_ap = (b[73] - a[73]) % M32
                d_pd = (b[74] - a[74]) % M32
                print("    E12: dEv=%d dsw_req=%d dapply=%d dup_pend=%d trig_face=%d identity=%s" %
                      (d_ev, d_sw, d_ap, d_pd, d_sw + d_pd,
                       "CLOSED(ev==apply+pend)" if d_ev == d_ap + d_pd else "OPEN!!"))
            if 69 in b:
                print("    W69 latch POST raw=0x%08x -> {infl, wnd}=%s" %
                      (b[69], "{%d,%d}" % (b[69] >> 16, b[69] & 0xFFFF)))
        np_, np2 = base + "_nstat_pre.txt", base + "_nstat_post.txt"
        if os.path.exists(np_) and os.path.exists(np2):
            a, b = nstat(np_), nstat(np2)
            dv = {k: (b.get(k, 0) - a.get(k, 0)) for k in NKEYS}
            print("    nstat delta: " + " ".join("%s=%+d" % (k.replace("TcpExt", ""), dv[k]) for k in NKEYS))
            seg = dv["TcpInSegs"]
            if seg:
                print("    delayed-ACK trace: DelayedACKs/InSegs=%.3e Locked=%d Lost=%d RetransSegs/InSegs=%.3e" %
                      (dv["TcpExtDelayedACKs"] / seg, dv["TcpExtDelayedACKLocked"],
                       dv["TcpExtDelayedACKLost"], dv["TcpRetransSegs"] / seg))


if __name__ == "__main__":
    main()
