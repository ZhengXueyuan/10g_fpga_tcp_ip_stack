#!/usr/bin/env python3
# snap_traj.py -- parse a /tmp/c1_<TAG>_snap.log ring into a per-point trajectory and
# print first/last values + deltas for the KW words (wrap-aware via monotone segments).
import sys, re

def parse(path):
    pts = []
    cur = None
    for line in open(path, errors="replace"):
        line = line.rstrip("\n")
        if line.startswith("SNAP_T "):
            cur = {"t": float(line.split()[1]), "w": {}}
        elif line.startswith("SNAP_BEGIN"):
            if cur is not None: cur["gen"] = line.split("gen=")[-1]
        elif line.startswith("SNAP_END"):
            if cur is not None:
                cur["end"] = line
                pts.append(cur); cur = None
        elif line.startswith(("W", "SNAP_ABORT")):
            m = re.match(r"W(\d+)\s+\S+\s+\S+\s+(0x[0-9a-fA-F]+)", line)
            if m and cur is not None:
                cur["w"][int(m.group(1))] = int(m.group(2), 16)
    return pts

def main():
    path = sys.argv[1]
    words = [int(x) for x in sys.argv[2:]] or [5, 20, 43, 51, 52, 55, 63, 64]
    pts = parse(path)
    print(f"POINTS {len(pts)}")
    if not pts: return
    print(f"T0 {pts[0]['t']:.3f} T1 {pts[-1]['t']:.3f} span {pts[-1]['t']-pts[0]['t']:.3f}s")
    for w in words:
        vals = [(p["t"], p["w"].get(w)) for p in pts if w in p["w"]]
        vals = [(t, v) for t, v in vals if v is not None]
        if not vals:
            print(f"W{w}: no data"); continue
        first, last = vals[0][1], vals[-1][1]
        # wrap count = number of times consecutive samples decreased by >2^31
        wraps = sum(1 for i in range(1, len(vals)) if vals[i][1] < vals[i-1][1] - (1 << 31))
        raw_delta = last - first
        total = raw_delta + wraps * (1 << 32)
        print(f"W{w}: first=0x{first:08x}({first}) last=0x{last:08x}({last}) wraps={wraps} delta_wrapaware={total}")
    # per-second increments of the four E12 counters + a timebase
    print("--- per-second E12 deltas (wrap-aware within the minute) ---")
    tb = 5 if any(5 in p["w"] for p in pts) else 43
    pts2 = [(p["t"], p["w"]) for p in pts if tb in p["w"] and all(w in p["w"] for w in (71,72,73,74))]
    if not pts2:
        print("(no points with 71..74)"); return
    def d(a, b, w):
        raw = b.get(w, 0) - a.get(w, 0)
        return raw + (1 << 32) if raw < -(1 << 31) else raw
    t0 = pts2[0][0]
    buckets = {}
    for t, w in pts2:
        k = int(t - t0)
        buckets.setdefault(k, []).append((t, w))
    prev = None
    for k in sorted(buckets):
        t, w = buckets[k][-1]
        if prev is not None:
            print(f"t={t-t0:6.2f}s dW71={d(prev,w,71):5d} dW72={d(prev,w,72):5d} dW73={d(prev,w,73):5d} dW74={d(prev,w,74):5d} dW52={d(prev,w,52):9d} dW5={d(prev,w,5):11d}")
        prev = w
    print("--- first/last raw of 71..74 ---")
    print({w: (pts2[0][1][w], pts2[-1][1][w]) for w in (71,72,73,74)})

if __name__ == "__main__":
    main()
