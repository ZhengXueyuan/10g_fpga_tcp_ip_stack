#!/usr/bin/env python3
"""ss_parse.py -- parse the per-second `ss -tinH state established (dport = :8080)` log.

Format produced by bp_arm.sh:
    SS_T <epoch>
    <recvq> <sendq> <local> <peer>
    \t cubic rto:201 rtt:0.068/0.034 ... bytes_received:41129660 ... snd_wnd:49152

Emits, per socket (peer addr:port):
  * first/last sample, bytes_received delta, per-second rate (Mbps)
  * cwnd / rtt / snd_wnd / rcv_space ranges (the T1-missing trajectory cell)
  * an explicit "no samples" line when the socket lived <1 s (fast arms)

Usage: python ss_parse.py <ss.log> [<ss.log>...]
"""
import collections
import re
import sys

FIELD_RE = re.compile(r"(\w[\w-]*):([^\s]+)")


def parse(path):
    samples = []
    t = None
    cur = None
    for line in open(path, "r", errors="replace"):
        line = line.rstrip("\n")
        if line.startswith("SS_T "):
            if cur is not None:
                samples.append((t, cur))
                cur = None
            t = float(line.split()[1])
            continue
        if not line.strip():
            continue
        if not line.startswith("\t") and not line.startswith(" "):
            # socket header line: recvq sendq local peer
            parts = line.split()
            if len(parts) >= 4 and ":" in parts[2] and ":" in parts[3]:
                if cur is not None:
                    samples.append((t, cur))
                cur = dict(local=parts[2], peer=parts[3], fields={})
            continue
        if cur is not None:
            for k, v in FIELD_RE.findall(line):
                cur["fields"][k] = v
    if cur is not None:
        samples.append((t, cur))
    return samples


def fnum(fields, key):
    v = fields.get(key)
    if v is None:
        return None
    try:
        if "/" in v:
            v = v.split("/")[0]
        return float(v)
    except ValueError:
        return None


def main():
    for path in sys.argv[1:]:
        samples = parse(path)
        print("=== SS %s: %d socket samples ===" % (path, len(samples)))
        bysock = collections.OrderedDict()
        for t, s in samples:
            if t is None:
                continue
            bysock.setdefault(s["peer"], []).append((t, s))
        for peer, rows in bysock.items():
            rows.sort()
            br = [fnum(s["fields"], "bytes_received") for _, s in rows]
            br = [x for x in br if x is not None]
            t0, t1 = rows[0][0], rows[-1][0]
            if not br:
                print("  %s : no bytes_received field (n=%d)" % (peer, len(rows)))
                continue
            dt = t1 - t0
            # use max-min for the byte delta (monotone per socket)
            dbytes = max(br) - min(br)
            print("  %s : n=%d span=%.1fs bytes_received %.0f -> %.0f (delta=%d, %.3f Mbps)" %
                  (peer, len(rows), dt, min(br), max(br), dbytes,
                   dbytes * 8 / 1e6 / dt if dt > 0 else 0))
            for key in ("cwnd", "rtt", "snd_wnd", "rcv_space", "minrtt"):
                vals = [fnum(s["fields"], key) for _, s in rows]
                vals = [x for x in vals if x is not None]
                if vals:
                    print("      %-9s min=%-10g max=%-10g med=%g" %
                          (key, min(vals), max(vals), sorted(vals)[len(vals) // 2]))
            # per-second deltas (first 6 and last 3) for the crawl-rate witness
            deltas = []
            for (ta, sa), (tb, sb) in zip(rows, rows[1:]):
                a = fnum(sa["fields"], "bytes_received")
                b = fnum(sb["fields"], "bytes_received")
                if a is not None and b is not None and tb > ta:
                    deltas.append((tb - t0, (b - a) * 8 / 1e6 / (tb - ta)))
            if deltas:
                show = deltas[:6] + ([("...", None)] if len(deltas) > 9 else []) + deltas[-3:]
                print("      per-sec Mbps: " + " ".join(
                    ("%.2f" % v) if v is not None else "..." for _, v in show))


if __name__ == "__main__":
    main()
