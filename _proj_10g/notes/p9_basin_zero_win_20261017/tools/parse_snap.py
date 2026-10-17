#!/usr/bin/env python3
# parse_snap.py -- parse b2a snapshot ring logs (b2a_snap.sh snap output)
# Usage: parse_snap.py LOG [--ref EPOCH] [--words 5,20,55,75] [--step N]
import re, sys, argparse

LINE_W = re.compile(r'^W(\d+)\s+0x[0-9A-Fa-f]+\s+\S+\s+(0x[0-9a-fA-F]+)\s*$')
LINE_T = re.compile(r'^SNAP_T\s+([0-9.]+)')
LINE_BEGIN = re.compile(r'^SNAP_BEGIN\s+(\S+)\s+gen=(\d+)')
LINE_END = re.compile(r'^SNAP_END\s+(\S+)\s+nff=(\d+)')

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('log')
    ap.add_argument('--ref', type=float, default=None)
    ap.add_argument('--words', default=None)
    ap.add_argument('--step', type=int, default=1, help='print every Nth point')
    a = ap.parse_args()
    words = None
    if a.words:
        words = [int(x) for x in a.words.split(',')]
    pts = []
    cur = None
    for ln in open(a.log, errors='replace'):
        m = LINE_T.match(ln)
        if m:
            cur = {'t': float(m.group(1)), 'w': {}, 'gen': None, 'nff': None, 'tag': None}
            pts.append(cur)
            continue
        m = LINE_BEGIN.search(ln)
        if m and cur is not None:
            cur['tag'] = m.group(1); cur['gen'] = int(m.group(2)); continue
        m = LINE_END.search(ln)
        if m and cur is not None:
            cur['nff'] = int(m.group(2)); continue
        m = LINE_W.match(ln.strip())
        if m and cur is not None:
            cur['w'][int(m.group(1))] = int(m.group(2), 16)
    pts = [p for p in pts if p['w']]
    if not pts:
        print("NO_POINTS"); return 2
    ref = a.ref if a.ref is not None else pts[0]['t']
    if words is None:
        words = sorted(set().union(*[set(p['w']) for p in pts]))
    print("POINTS=%d REF=%.6f T_FIRST=%.6f T_LAST=%.6f SPAN=%.3f" %
          (len(pts), ref, pts[0]['t'], pts[-1]['t'], pts[-1]['t'] - pts[0]['t']))
    print("nff_nonzero_points=%d" % sum(1 for p in pts if p['nff'] not in (0, None)))
    # header
    print("idx\tt_rel\tgen\t" + "\t".join("W%d" % w for w in words))
    for i, p in enumerate(pts):
        if i % a.step and i != len(pts) - 1:
            continue
        vals = []
        for w in words:
            v = p['w'].get(w)
            vals.append('-' if v is None else ('0x%08x' % (v & 0xffffffff)))
        print("%d\t%.3f\t%s\t%s" % (i, p['t'] - ref, p['gen'], "\t".join(vals)))
    # W55 / W75 event analysis
    def series(w):
        return [(p['t'] - ref, p['w'][w] & 0xffffffff) for p in pts if w in p['w']]
    for w in (55, 75):
        s = series(w)
        if len(s) < 2:
            continue
        d = []
        for j in range(1, len(s)):
            dv = (s[j][1] - s[j-1][1]) & 0xffffffff
            dt = s[j][0] - s[j-1][0]
            d.append((s[j][0], dv, dt))
        # per-second rates over 10 s buckets
        print("-- W%d: first=0x%08x last=0x%08x total_delta=%d" % (w, s[0][1], s[-1][1], (s[-1][1]-s[0][1]) & 0xffffffff))
        ev = [(t, dv) for (t, dv, dt) in d if dv]
        if ev:
            print("   increments (t_rel,delta): " + ", ".join("%.2f:+%d" % e for e in ev[:80]) + (" ..." if len(ev) > 80 else ""))
        # 10s bucket sums
        buckets = {}
        for (t, dv, dt) in d:
            b = int(t // 10) * 10
            buckets[b] = buckets.get(b, 0) + dv
        print("   10s-bucket sums: " + " ".join("%ds:%d" % (k, buckets[k]) for k in sorted(buckets)))
    return 0

if __name__ == '__main__':
    sys.exit(main())
