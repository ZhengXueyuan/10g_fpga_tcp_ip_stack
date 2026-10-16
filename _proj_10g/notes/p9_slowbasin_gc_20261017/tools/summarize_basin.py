#!/usr/bin/env python3
"""summarize_basin.py -- aggregate the p9_slowbasin_gc round artifacts into one readings table.

Adapted from p9_t2fast_ab_20261017/tools/summarize.py (same snap/nstat/pre-post parsers),
retargeted to raw/basin_<TAG>_* (+ runs/<TAG>_stdout.txt) and extended with the
delayed-ACK family incl. TCPPureAcks/TCPHPAcks.
"""
import glob, os, re, sys, collections

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "..", "raw")
RUNS = os.path.join(HERE, "..", "runs")
TAGS = sys.argv[1:] or ["G0", "G1", "G2", "G3", "G4F", "G4", "G1b", "G1c"]
M32 = 1 << 32

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

def ring_rate(samples, w):
    rates = []
    for i in range(len(samples) - 1):
        t0, a = samples[i]; t1, b = samples[i + 1]
        if w not in a or w not in b or t1 <= t0:
            continue
        rates.append(((b[w] - a[w]) % M32) / (t1 - t0))
    if not rates:
        return None
    rates.sort()
    return rates[len(rates) // 2]

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

NKEYS = ["TcpInSegs", "TcpOutSegs", "TcpRetransSegs", "TcpExtTCPOFOQueue", "TcpExtTCPFastRetrans",
         "TcpExtTCPACKSkippedSeq", "TcpExtDelayedACKs", "TcpExtDelayedACKLocked", "TcpExtDelayedACKLost",
         "TcpExtTCPPureAcks", "TcpExtTCPHPAcks"]

def main():
    print("=" * 118)
    print("p9_slowbasin_gc_20261017 -- per-arm readings")
    print("=" * 118)
    for tag in TAGS:
        base = os.path.join(RAW, "basin_%s" % tag)
        so = os.path.join(RUNS, "%s_stdout.txt" % tag)
        if not os.path.exists(so):
            so2 = base + "_stdout.txt"
            if os.path.exists(so2):
                so = so2
            else:
                print("\n### %s : stdout MISSING" % tag); continue
        txt = rd(so)
        print("\n" + "#" * 100)
        begin = re.search(r"### K0M_BEGIN (.+)", txt)
        print("### %s" % (begin.group(1) if begin else "(no K0M_BEGIN)"))
        for pat in [r"### SINK_MD5 \S+", r"### SINK_SIZE \d+", r"### SINK_OPTS_WITNESS .*",
                    r"### SINK_RC_SUM.*", r"### K0M_END .*"]:
            m = re.search(pat, txt)
            if m: print("    " + m.group(0))
        for m in re.finditer(r"SINK_SUM .*", txt):
            print("    SUM " + m.group(0)[:210])
        connrows = re.findall(r"SINK_CONN (\d+) (OK|STALL|POLL_TIMEOUT|ERR|FAIL_CONNECT)[^\n]*?(?:Mbps=([\d.]+))?[^\n]*", txt)
        rates = [float(m[2]) for m in connrows if m[2]]
        if rates:
            print("    per-conn Mbps: %s" % ", ".join("%.3f" % r for r in rates))
            nfast = sum(1 for r in rates if r >= 100)
            ncr = sum(1 for r in rates if r <= 5)
            print("    VERDICT-READ (n=%d conns): fast(>=100Mbps)=%d  crawl(<=5Mbps)=%d  mid=%d" %
                  (len(rates), nfast, ncr, len(rates) - nfast - ncr))
        cap = re.search(r"(\d+) packets captured", txt)
        rec = re.search(r"(\d+) packets received by filter", txt)
        dro = re.search(r"(\d+) packets dropped by kernel", txt)
        if cap:
            print("    pcap: captured=%s received=%s dropped=%s" % (cap.group(1), rec.group(1), dro.group(1)))
        sp = base + "_snap.log"
        if os.path.exists(sp):
            samples = snap_parse(sp)
            rr = {}
            for w in [5, 20, 43, 51, 52, 55, 66, 67, 68]:
                v = ring_rate(samples, w)
                if v is not None:
                    rr[w] = v
            span = (samples[-1][0] - samples[0][0]) if len(samples) > 1 else 0
            print("    snap ring: n=%d span=%.2fs  " % (len(samples), span) +
                  " ".join("W%d=%s" % (w, ("%.3f" % rr[w]) if w in rr else "-") for w in [5, 20, 43, 51, 52, 55, 66, 67, 68]))
            if 66 in rr and 5 in rr:
                print("    W67/W66 = %s ; (W66-W67)/W5 = %s" %
                      (("%.6f" % (rr[67] / rr[66])) if 66 in rr and rr[66] else "-",
                       ("%.6f" % ((rr[66] - rr.get(67, 0)) / rr[5])) if 5 in rr and rr[5] else "-"))
        pp, po = base + "_pre.txt", base + "_post.txt"
        if os.path.exists(pp) and os.path.exists(po):
            a, b = pre_post(pp), pre_post(po)
            keys = [5, 20, 43, 51, 52, 55, 63, 64, 65, 66, 67, 68, 69, 71, 72, 73, 74]
            print("    PRE/POST deltas (mod 2^32): " + " ".join(
                "W%d=%d" % (w, (b[w] - a[w]) % M32) for w in keys if w in a and w in b))
            if all(w in a and w in b for w in (71, 72, 73, 74)):
                d_ev = (b[71] - a[71]) % M32; d_sw = (b[72] - a[72]) % M32
                d_ap = (b[73] - a[73]) % M32; d_pd = (b[74] - a[74]) % M32
                print("    E12: dEv=%d dsw_req=%d dapply=%d dup_pend=%d  trig_face=%d  identity=%s" %
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
                print("    delayed-ACK trace: DelayedACKs/InSegs=%s Locked=%d Lost=%d RetransSegs/InSegs=%s PureAcks=%d HPAcks=%d" %
                      ("%.3e" % (dv["TcpExtDelayedACKs"] / seg), dv["TcpExtDelayedACKLocked"],
                       dv["TcpExtDelayedACKLost"], "%.3e" % (dv["TcpRetransSegs"] / seg),
                       dv["TcpExtTCPPureAcks"], dv["TcpExtTCPHPAcks"]))
        m = re.findall(r"(BID_0x04=.*?)\n(SCRATCH_0x08=.*?)\n(CARRIER=.*?)\n", txt)
        if m:
            print("    board after: %s | %s | %s" % (m[-1][0][:60], m[-1][1][:60], m[-1][2][:30]))

if __name__ == "__main__":
    main()
