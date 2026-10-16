#!/usr/bin/env python3
"""snap_series.py -- parse a p7b_snap.sh ring log into per-word series + deltas.

Usage:
  python snap_series.py <snap.log> [--t0 EPOCH] [--words 5 20 43 51 52 55 63 64 66 67 68 69 71 72 73 74]
                        [--csv out.csv] [--rate W] [--interval-lo A --interval-hi B]

Reads only; writes nothing unless --csv given.

Log grammar (from p7b_snap.sh):
  SNAP_T <epoch>
  SNAP_BEGIN <TAG> gen=<n>
  W<n> <addr> <name> <hex>
  SNAP_END <TAG> nff=<n>
  GEN_FAIL ... / SNAP_ABORT   (concurrent-writer guard; such samples are dropped)
"""
import re, sys, argparse


def parse(path):
    """-> list of (t, gen, {w: int}); drops aborted samples."""
    samples = []
    t = None
    gen = None
    cur = {}
    aborted = False
    n_abort = 0
    for line in open(path, errors="replace"):
        line = line.strip()
        m = re.match(r"SNAP_T\s+([\d.]+)", line)
        if m:
            t = float(m.group(1)); gen = None; cur = {}; aborted = False
            continue
        m = re.match(r"SNAP_BEGIN\s+\S+\s+gen=(\d+)", line)
        if m:
            gen = int(m.group(1)); continue
        m = re.match(r"W(\d+)\s+\S+\s+\S+\s+(0x[0-9a-fA-F]+)", line)
        if m:
            cur[int(m.group(1))] = int(m.group(2), 16); continue
        if line.startswith("GEN_FAIL") or line.startswith("SNAP_ABORT"):
            aborted = True; n_abort += 1; continue
        m = re.match(r"SNAP_END\s+\S+\s+nff=(\d+)", line)
        if m:
            if not aborted and t is not None and cur:
                samples.append((t, gen, dict(cur)))
            cur = {}
            continue
    return samples, n_abort


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--t0", type=float, default=None)
    ap.add_argument("--words", type=int, nargs="*", default=None)
    ap.add_argument("--csv", default=None)
    ap.add_argument("--rate", type=int, default=None, help="word -> per-second rate summary")
    ap.add_argument("--interval-lo", type=float, default=None)
    ap.add_argument("--interval-hi", type=float, default=None)
    a = ap.parse_args()

    samples, n_abort = parse(a.log)
    if not samples:
        print("NO_SAMPLES (aborted=%d)" % n_abort); return
    t0 = a.t0 if a.t0 is not None else samples[0][0]
    allw = sorted({w for (_, _, d) in samples for w in d})
    words = a.words if a.words else allw
    print("samples=%d aborted=%d span=%.3fs words=%s"
          % (len(samples), n_abort, samples[-1][0] - samples[0][0], ",".join(map(str, words))))

    print("\n=== per-word first/last/delta (whole window) ===")
    print("%-5s %12s %12s %14s %12s" % ("word", "first", "last", "delta", "rate/s"))
    span = samples[-1][0] - samples[0][0]
    for w in words:
        vals = [(t, d[w]) for (t, g, d) in samples if w in d]
        if len(vals) < 2:
            continue
        f, l = vals[0][1], vals[-1][1]
        d = (l - f) & 0xFFFFFFFF
        print("%-5d %12d %12d %14d %12.2f" % (w, f, l, d, d / span if span > 0 else 0))

    # interval summary (between two sample indices, expressed as +t from t0)
    lo = a.interval_lo if a.interval_lo is not None else -1e18
    hi = a.interval_hi if a.interval_hi is not None else 1e18
    sel = [(t, d) for (t, g, d) in samples if lo <= (t - t0) <= hi]
    if lo > -1e18 or hi < 1e18:
        print("\n=== interval [%.2f,%.2f] s from t0: samples=%d ===" % (lo, hi, len(sel)))
        if len(sel) >= 2:
            dt = sel[-1][0] - sel[0][0]
            for w in words:
                v = [(t, d[w]) for (t, d) in sel if w in d]
                if len(v) < 2:
                    continue
                d = (v[-1][1] - v[0][1]) & 0xFFFFFFFF
                print("  W%-4d delta=%-14d rate/s=%.3f  (dt=%.3f)" % (w, d, d / dt if dt > 0 else 0, dt))

    if a.csv:
        with open(a.csv, "w") as fh:
            fh.write("t_rel," + ",".join("W%d" % w for w in words) + "\n")
            for (t, g, d) in samples:
                fh.write("%.6f," % (t - t0) + ",".join(str(d.get(w, "")) for w in words) + "\n")
        print("\nCSV_WRITTEN %s" % a.csv)

    if a.rate is not None:
        w = a.rate
        v = [(t - t0, d[w]) for (t, g, d) in samples if w in d]
        print("\n=== W%d per-interval rates (>=0.05s gaps only) ===" % w)
        for i in range(1, len(v)):
            dt = v[i][0] - v[i - 1][0]
            if dt < 0.05:
                continue
            d = (v[i][1] - v[i - 1][1]) & 0xFFFFFFFF
            print("  t=%9.2f dt=%6.3f dW%-4d=%-12d rate=%10.2f /s" % (v[i][0], dt, w, d, d / dt))


if __name__ == "__main__":
    main()
