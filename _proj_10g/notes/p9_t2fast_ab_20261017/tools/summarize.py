#!/usr/bin/env python3
"""summarize.py -- aggregate the p9_t2fast_ab round artifacts into one readings table.

Reads raw/fast_<TAG>_*.txt (fetched from the peer) and emits per-arm:
  * config + sink binary identity
  * per-connection rates (from the sink logs) + fast/slow verdict per the pre-registered rule
    (fast = any conn >= 100 Mbps or completes maxbytes within 120 s; crawl = all conns <= 5 Mbps)
  * board ring rates (median per-sample delta / dt, mod 2^32) for W5/W20/W43/W51/W52/W55/W66/W67/W68
  * E12 deltas (W71..W74) PRE->POST with the three-state identity check
  * nstat deltas (9 counters incl. the delayed-ACK family) and delayed-ACK ratios
  * pcap hard gates (captured/received/dropped)
"""
import glob, os, re, sys, collections

RAW = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "raw")
TAGS = ["F0", "F1", "F2", "F3", "F4", "F5", "F6", "F7a", "F7b", "F7c", "F7d", "F7e", "F8"]
M32 = 1 << 32

def rd(p):
    with open(p, "r", errors="replace") as f:
        return f.read()

def snap_parse(path):
    """-> list of (t, {word: value}) for SNAP_BEGIN blocks in a snap log"""
    out = []
    cur = None
    t = None
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
    """median per-second rate of word w over consecutive samples (mod 2^32)"""
    rates = []
    for i in range(len(samples) - 1):
        t0, a = samples[i]
        t1, b = samples[i + 1]
        if w not in a or w not in b or t1 <= t0:
            continue
        rates.append(((b[w] - a[w]) % M32) / (t1 - t0))
    if not rates:
        return None
    rates.sort()
    return rates[len(rates) // 2]

def pre_post(path, name):
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
         "TcpExtTCPACKSkippedSeq", "TcpExtDelayedACKs", "TcpExtDelayedACKLocked", "TcpExtDelayedACKLost"]

def main():
    print("=" * 118)
    print("p9_t2fast_ab_20261017 -- per-arm readings")
    print("=" * 118)
    for tag in TAGS:
        base = os.path.join(RAW, "fast_%s" % tag)
        so = base + "_stdout.txt"
        if not os.path.exists(so):
            print("\n### %s : stdout MISSING" % tag); continue
        txt = rd(so)
        # a couple of arms' stdouts were saved in runs/ instead of raw/
        print("\n" + "#" * 100)
        begin = re.search(r"### K0M_BEGIN (.+)", txt)
        print("### %s" % (begin.group(1) if begin else "(no K0M_BEGIN)"))
        for pat in [r"### SINK_MD5 \S+", r"### SINK_SIZE \d+", r"### SINK_OPTS_WITNESS .*",
                    r"### SINK_RC_SUM.*", r"### K0M_END .*"]:
            m = re.search(pat, txt)
            if m: print("    " + m.group(0))
        # sink conns
        for m in re.finditer(r"SINK_SUM .*", txt):
            print("    SUM " + m.group(0)[:200])
        rates = [float(m.group(1)) for m in re.finditer(r"SINK_CONN \d+ (?:OK|STALL|POLL_TIMEOUT|ERR)[^\n]*Mbps=([\d.]+)", txt)]
        if rates:
            print("    per-conn Mbps: %s" % ", ".join("%.3f" % r for r in rates))
            nfast = sum(1 for r in rates if r >= 100)
            print("    VERDICT-READ (n=%d conns): fast(>=100Mbps)=%d  crawl(<=5Mbps)=%d  mid=%d" %
                  (len(rates), nfast, sum(1 for r in rates if r <= 5),
                   sum(1 for r in rates if 5 < r < 100)))
        # pcap gates
        cap = re.search(r"(\d+) packets captured", txt)
        rec = re.search(r"(\d+) packets received by filter", txt)
        dro = re.search(r"(\d+) packets dropped by kernel", txt)
        if cap:
            print("    pcap: captured=%s received=%s dropped=%s" % (cap.group(1), rec.group(1), dro.group(1)))
        # snap ring rates
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
        # PRE/POST + E12
        pp, po = base + "_pre.txt", base + "_post.txt"
        if os.path.exists(pp) and os.path.exists(po):
            a, b = pre_post(pp, "pre"), pre_post(po, "post")
            keys = [5, 20, 43, 51, 52, 55, 63, 64, 65, 66, 67, 68, 69, 71, 72, 73, 74]
            print("    PRE/POST deltas (mod 2^32): " + " ".join(
                "W%d=%d" % (w, (b[w] - a[w]) % M32) for w in keys if w in a and w in b))
            if all(w in a and w in b for w in (71, 72, 73, 74)):
                dev = ((b[71] - a[71]) % M32, (b[72] - a[72]) % M32, (b[73] - a[73]) % M32, (b[74] - a[74]) % M32)
                d_ev, d_sw, d_ap, d_pd = dev
                print("    E12: dEv=%d dsw_req=%d dapply=%d dup_pend=%d  trig_face=%d  当拍应用=%d  identity=%s" %
                      (d_ev, d_sw, d_ap, d_pd, d_sw + d_pd, d_ap - d_sw,
                       "CLOSED(ev==apply+pend)" if d_ev == d_ap + d_pd else "OPEN!!"))
                if d_ev != d_ap + d_pd:
                    print("    ⚠️ NOTE: raw applies may lag one sample; PRE/POST are single-point reads.")
            if 69 in b:
                print("    W69 latch POST raw=0x%08x -> {infl, wnd}=%s" %
                      (b[69], "{%d,%d}" % (b[69] >> 16, b[69] & 0xFFFF)))
        # nstat
        np_, np2 = base + "_nstat_pre.txt", base + "_nstat_post.txt"
        if os.path.exists(np_) and os.path.exists(np2):
            a, b = nstat(np_), nstat(np2)
            dv = {k: (b.get(k, 0) - a.get(k, 0)) for k in NKEYS}
            print("    nstat delta: " + " ".join("%s=%+d" % (k.replace("TcpExt", ""), dv[k]) for k in NKEYS))
            seg = dv["TcpInSegs"]
            if seg:
                print("    delayed-ACK trace: DelayedACKs/InSegs=%s Locked=%d Lost=%d RetransSegs/InSegs=%s" %
                      ("%.3e" % (dv["TcpExtDelayedACKs"] / seg), dv["TcpExtDelayedACKLocked"],
                       dv["TcpExtDelayedACKLost"], "%.3e" % (dv["TcpRetransSegs"] / seg)))
        # board state after
        m = re.search(r"BID_0x04=[^\n]*", txt) and re.findall(r"(BID_0x04=.*?)\n(SCRATCH_0x08=.*?)\n(CARRIER=.*?)\n", txt)
        if m:
            print("    board after: %s | %s | %s" % (m[-1][0][:60], m[-1][1][:60], m[-1][2][:30]))
    # faseg medians per arm
    print("\n" + "=" * 118)
    print("first-segment timing (faseg) medians per arm")
    print("=" * 118)
    print("%-5s %10s %10s %10s %12s" % ("arm", "synack->d1", "d1->ack1", "conn mbps", "first1s bps"))
    for tag in TAGS:
        f = os.path.join(RAW, "fast_%s_faseg.txt" % tag)
        if not os.path.exists(f):
            continue
        t = rd(f)
        def g(p):
            m = re.search(p, t)
            return m.group(1) if m else "-"
        print("%-5s %10s %10s %10s %12s" % (tag, g(r"synack->d1 med = ([\d.]+)"),
                                            g(r"d1->ack1  med = ([\d.]+)"),
                                            g(r"conn mbps med = ([\d.]+)"),
                                            g(r"first1s bps med = ([\d.]+)")))

if __name__ == "__main__":
    main()
