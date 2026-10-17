#!/usr/bin/env python3
"""zw_eval.py -- evaluate the PRE-REGISTERED criteria of p9_basin_zero_win_20261017
on runs/ALL_RUNS.json (produced by zw_table.py).

Criteria text = README_FOR_TL.md sec.1.3 (locked before data collection).
This script only applies them; it does not add or alter criteria.

Bucket statistic:
  * run value  = median over that run's valid connections (per-conn uniq rate / zw_pct)
  * bucket value = median over the bucket's runs
  * robustness check with the alternative: median over all connections pooled
"""
import json
import statistics as st
import sys

SEQ = ['2920', '6000', '7000', '8000', '8760', '10000', '12000']


def main(path='runs/ALL_RUNS.json'):
    rows = [r for r in json.load(open(path)) if not r.get('missing') and r['mode'] in ('basin', 'outside')]
    basin = {b: [] for b in SEQ}
    outside = {}
    for r in rows:
        b = r['tag'][1:]
        b = b[:b.index('r')]
        if r['mode'] == 'basin':
            basin.setdefault(b, []).append(r)
        else:
            outside.setdefault(b, []).append(r)

    def med(xs):
        xs = [x for x in xs if x is not None]
        return st.median(xs) if xs else None

    def bucket(b, keyrun='median'):
        rs = basin.get(b, [])
        if keyrun == 'median':
            return med([med([c['uniq_mbps'] for c in r['conns']]) for r in rs]) if rs else None, \
                   med([med([c['zw_pct'] for c in r['conns']]) for r in rs]) if rs else None
        else:
            rates = [c['uniq_mbps'] for r in rs for c in r['conns']]
            zws = [c['zw_pct'] for r in rs for c in r['conns']]
            return (st.median(rates) if rates else None), (st.median(zws) if zws else None)

    print('=== bucket values (basin) ===')
    print('%-8s %6s %12s %10s %12s %12s' % ('bucket', 'nrun', 'medRate_med', 'medZW_med', 'poolRate', 'poolZW'))
    vals = {}
    for b in SEQ:
        r1, z1 = bucket(b, 'median')
        r2, z2 = bucket(b, 'pool')
        vals[b] = (r1, z1)
        print('%-8s %6d %12.3f %10.3f %12.3f %12.3f' % (b, len(basin.get(b, [])), r1, z1, r2, z2))

    print('\n=== criterion (a): first rate step vs first zero-window step ===')
    rate_step = None
    zw_step = None
    for i in range(len(SEQ) - 1):
        b0, b1 = SEQ[i], SEQ[i + 1]
        r0, z0 = vals[b0]
        r1, z1 = vals[b1]
        cond_r = (r0 is not None and r1 is not None and r0 > 0 and r1 / r0 >= 10
                  and r0 <= 10 and r1 >= 100)
        cond_z = (z0 is not None and z1 is not None and z0 >= 5.0 and z1 <= 1.0)
        print('pair %s->%s : rate %.3f->%.3f (x%.1f) condR=%s | zw %.2f->%.2f condZW=%s' %
              (b0, b1, r0, r1, (r1 / r0 if r0 else 0), cond_r, z0, z1, cond_z))
        if cond_r and rate_step is None:
            rate_step = (b0, b1)
        if cond_z and zw_step is None:
            zw_step = (b0, b1)
    a_ok = (rate_step is not None and zw_step is not None and rate_step == zw_step)
    print('RATE_STEP=%s ZW_STEP=%s  (a)=%s' % (rate_step, zw_step, 'SUPPORTED' if a_ok else 'NOT_OBSERVED'))

    print('\n=== criterion (b): within-bucket, highest zw run must have lowest rate ===')
    ok_b = []
    for b in SEQ:
        rs = [r for r in basin.get(b, []) if r['conns']]
        if len(rs) < 3:
            continue
        zr = [med([c['zw_pct'] for c in r['conns']]) for r in rs]
        rr = [med([c['uniq_mbps'] for c in r['conns']]) for r in rs]
        if (max(zr) - min(zr)) < 0.5:
            print('%s: excluded (zw range %.3f pp < 0.5)' % (b, max(zr) - min(zr)))
            continue
        hi = zr.index(max(zr))
        lo = rr.index(min(rr))
        ok = (hi == lo)
        ok_b.append(ok)
        print('%s: zw=%s rate=%s -> highest-zw run=%d lowest-rate run=%d => %s' %
              (b, ['%.2f' % x for x in zr], ['%.2f' % x for x in rr], hi + 1, lo + 1, 'OK' if ok else 'NO'))
    b_ok = (sum(ok_b) * 3 >= 2 * len(ok_b)) if ok_b else False
    print('QUALIFYING=%d OK=%d (b)=%s (low power, n=3/run)' % (len(ok_b), sum(ok_b), 'SUPPORTED' if b_ok else 'NOT_OBSERVED'))

    print('\n=== criterion (c): outside-basin zw <=1%% at 2920/7000/8000 and in-basin >=5%% somewhere ===')
    c_rows = []
    for b in ('2920', '7000', '8000'):
        rs = outside.get(b, [])
        oz = med([med([c['zw_pct'] for c in r['conns']]) for r in rs]) if rs else None
        orate = med([med([c['uniq_mbps'] for c in r['conns']]) for r in rs]) if rs else None
        c_rows.append((b, len(rs), oz, orate))
        print('outside %s: nrun=%d medZW=%.3f medRate=%.2f' % (b, len(rs), oz, orate))
    c_out = all(x[2] is not None and x[2] <= 1.0 for x in c_rows) and all(x[1] >= 2 for x in c_rows)
    c_in = any(vals[b][1] is not None and vals[b][1] >= 5.0 for b in ('2920', '7000', '8000'))
    c_ok = c_out and c_in
    print('outside_all_le1=%s in_basin_any_ge5=%s  (c)=%s' % (c_out, c_in, 'SUPPORTED' if c_ok else 'NOT_OBSERVED'))

    print('\n=== overall (pre-registered rule) ===')
    if a_ok and c_ok:
        print('VERDICT = SUPPORTED (zero-window ratio is the watershed for the observed step)')
    elif a_ok and not c_ok:
        print('VERDICT = SAME-ORDER-BUT-NOT-ATTRIBUTED')
    elif (not a_ok) and c_ok:
        print('VERDICT = BASIN-FEATURE-NOT-WATERSHED')
    else:
        print('VERDICT = NOT-OBSERVED')
    return 0


if __name__ == '__main__':
    sys.exit(main(*sys.argv[1:]))
