#!/usr/bin/env python3
"""zw_table.py -- build the per-run and per-bucket tables for p9_basin_zero_win_20261017.

Inputs (already produced by zw_metrics.py / probe_metrics.py / the arm's snapshot ring):
  runs/<TAG>_zw.json      (zero-window metrics; per-connection)
  runs/<TAG>_metrics.json (probe_metrics; per-connection rates/held/burst)
  raw/zw_<TAG>_snap.log   (snapshot ring; optional)

Outputs (stdout):
  * per-run table: conns, per-conn uniq Mbps + zw%, medians, held/burst, classification,
    ring rates (W55/s, W20/s, W51/s), duties W63/W5, W64/W5, W66/W5, W67/W5, W68/W20
  * per-bucket table: medians over runs (run-level agg zw, per-conn medians), counts
  * a machine-readable JSON dump with --json

Ring deltas are summed per adjacent snapshot pair as (b-a) mod 2^32 => wrap-safe.
W5 is the 156.25 MHz tick (0x... wraps every ~27.5 s).
"""
import argparse
import glob
import json
import os
import re
import statistics as st

M32 = 1 << 32
LINE_T = re.compile(r'^SNAP_T\s+([0-9.]+)')
LINE_W = re.compile(r'^W(\d+)\s+0x[0-9A-Fa-f]+\s+\S+\s+(0x[0-9a-fA-F]+)\s*$')


def parse_ring(path):
    pts = []
    cur = None
    if not os.path.exists(path):
        return pts
    for ln in open(path, errors='replace'):
        m = LINE_T.match(ln)
        if m:
            cur = {'t': float(m.group(1)), 'w': {}}
            pts.append(cur)
            continue
        m = LINE_W.match(ln.strip())
        if m and cur is not None:
            cur['w'][int(m.group(1))] = int(m.group(2), 16)
    return [p for p in pts if p['w']]


def ring_stats(path):
    pts = parse_ring(path)
    if len(pts) < 3:
        return None
    ws = [5, 20, 51, 52, 55, 63, 64, 65, 66, 67, 68]
    sums = {w: 0 for w in ws}
    for a, b in zip(pts, pts[1:]):
        for w in ws:
            if w in a['w'] and w in b['w']:
                sums[w] = (sums[w] + ((b['w'][w] - a['w'][w]) & 0xFFFFFFFF)) & 0xFFFFFFFF
    span = pts[-1]['t'] - pts[0]['t']
    if span <= 0:
        return None
    out = {'span_s': span, 'points': len(pts), 't_first': pts[0]['t'], 't_last': pts[-1]['t']}
    for w in (20, 51, 52, 55, 68):
        out['W%d_per_s' % w] = sums[w] / span
    w5 = sums[5]
    for w in (63, 64, 66, 67):
        out['W%d_over_W5' % w] = (sums[w] / w5) if w5 else None
    out['_sums'] = sums
    return out


def load(tag, root, mode):
    r = {'tag': tag, 'mode': mode}
    zp = os.path.join(root, 'runs', tag + '_zw.json')
    mp = os.path.join(root, 'runs', tag + '_metrics.json')
    if not os.path.exists(zp) or not os.path.exists(mp):
        r['missing'] = True
        return r
    zw = json.load(open(zp))
    pm = json.load(open(mp))
    zc = {c['cliport']: c for c in zw['conns']}
    conns = []
    for c in pm['conns']:
        if c.get('no_data'):
            continue
        z = zc.get(c['cliport'], {})
        conns.append(dict(port=c['cliport'],
                          uniq_mbps=c.get('uniq_mbps'),
                          wire_mbps=c.get('rate_mbps'),
                          zw_pct=z.get('zw_pct'),
                          zw_pct_pure=z.get('zw_pct_pure'),
                          n_acks=z.get('n_acks'),
                          n_win0=z.get('n_win0'),
                          held_pct=c.get('held_pct'),
                          held_ms=c.get('held_delay_med_ms'),
                          burst_pct=c.get('burst_pct'),
                          gap_med_us=c.get('gap_med_us'),
                          dup=c.get('dup_ratio')))
    r['conns'] = conns
    r['agg_zw_pct'] = zw.get('zw_pct')
    r['median_conn_zw_pct'] = zw.get('median_conn_zw_pct')
    rates = [c['uniq_mbps'] for c in conns if c['uniq_mbps'] is not None]
    zws = [c['zw_pct'] for c in conns if c['zw_pct'] is not None]
    held = [c['held_pct'] for c in conns if c['held_pct'] is not None]
    heldms = [c['held_ms'] for c in conns if c['held_ms'] is not None]
    burst = [c['burst_pct'] for c in conns if c['burst_pct'] is not None]
    r['n_conns'] = len(conns)
    r['median_rate_uniq'] = st.median(rates) if rates else None
    r['min_rate_uniq'] = min(rates) if rates else None
    r['max_rate_uniq'] = max(rates) if rates else None
    r['median_conn_zw_calc'] = st.median(zws) if zws else None
    r['median_held_pct'] = st.median(held) if held else None
    r['median_held_ms'] = st.median(heldms) if heldms else None
    r['median_burst_pct'] = st.median(burst) if burst else None
    r['n_crawl'] = sum(1 for x in rates if x <= 5)
    r['n_mid'] = sum(1 for x in rates if 5 < x < 100)
    r['n_fast'] = sum(1 for x in rates if x >= 100)
    r['ring'] = ring_stats(os.path.join(root, 'raw', 'zw_%s_snap.log' % tag))
    return r


def fmt(x, n=2, dash='-'):
    if x is None:
        return dash
    return ('%.*f' % (n, x))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default='.')
    ap.add_argument('--tags', default=None, help='comma list; default = all runs/*_zw.json')
    ap.add_argument('--json', default=None)
    a = ap.parse_args()
    root = a.root
    if a.tags:
        tags = [t.strip() for t in a.tags.split(',') if t.strip()]
    else:
        tags = sorted(os.path.basename(p)[:-8] for p in glob.glob(os.path.join(root, 'runs', '*_zw.json')))
    rows = []
    for tag in tags:
        mode = 'other'
        if tag.startswith('Z'):
            mode = 'basin'
        elif tag.startswith('C'):
            mode = 'outside'
        elif tag.startswith('A'):
            mode = 'precheck'
        elif tag.startswith('E'):
            mode = 'entry'
        rows.append(load(tag, root, mode))

    hdr = ('%-10s %-7s %4s %-42s %8s %8s %7s %7s %8s %10s %8s %8s' %
           ('TAG', 'MODE', 'n', 'per-conn uniqMbps/zw%', 'medRate', 'medZW', 'aggZW',
            'held%', 'burst%', 'W55/s', 'W63/W5', 'W66/W5'))
    print(hdr)
    for r in rows:
        if r.get('missing'):
            print('%-10s %-7s  MISSING JSON' % (r['tag'], r['mode']))
            continue
        pc = ' '.join('%s:%.2f/%.2f' % (c['port'], c['uniq_mbps'] or 0, c['zw_pct'] or 0) for c in r['conns'])
        ring = r.get('ring') or {}
        print('%-10s %-7s %4d %-42s %8s %8s %7s %7s %8s %10s %8s %8s' % (
            r['tag'], r['mode'], r['n_conns'], pc,
            fmt(r['median_rate_uniq']), fmt(r['median_conn_zw_calc']), fmt(r['agg_zw_pct']),
            fmt(r['median_held_pct'], 1), fmt(r['median_burst_pct'], 1),
            fmt(ring.get('W55_per_s')),
            fmt(ring.get('W63_over_W5'), 4), fmt(ring.get('W66_over_W5'), 4)))
    # per-bucket
    print()
    print('--- per-bucket (basin Z / outside C) ---')
    print('%-8s %-7s %4s %12s %10s %10s %10s %10s %10s' %
          ('BUCKET', 'MODE', 'nrun', 'medRate_med', 'medZW_med', 'aggZW_med', 'held%_med', 'W55/s_med', 'nC/nM/nF'))
    buckets = {}
    for r in rows:
        if r.get('missing') or r['mode'] not in ('basin', 'outside'):
            continue
        b = re.sub(r'^[ZC]', '', r['tag'])
        b = re.sub(r'r\d+$', '', b)
        buckets.setdefault((r['mode'], b), []).append(r)
    def medkey(rs, k):
        vals = [r[k] for r in rs if r.get(k) is not None]
        return st.median(vals) if vals else None
    for (mode, b) in sorted(buckets, key=lambda x: (x[0], int(x[1]))):
        rs = buckets[(mode, b)]
        rates = medkey(rs, 'median_rate_uniq')
        zwm = medkey(rs, 'median_conn_zw_calc')
        zwa = medkey(rs, 'agg_zw_pct')
        held = medkey(rs, 'median_held_pct')
        # ring is a dict -> handled below
        w55s = [r['ring']['W55_per_s'] for r in rs if r.get('ring')]
        w55med = st.median(w55s) if w55s else None
        nc = sum(r['n_crawl'] for r in rs); nm = sum(r['n_mid'] for r in rs); nf = sum(r['n_fast'] for r in rs)
        print('%-8s %-7s %4d %12s %10s %10s %10s %10s %10s' %
              (b, mode, len(rs), fmt(rates), fmt(zwm), fmt(zwa), fmt(held, 1), fmt(w55med), '%d/%d/%d' % (nc, nm, nf)))
    if a.json:
        out = []
        for r in rows:
            rr = dict(r)
            if rr.get('ring'):
                rr['ring'] = {k: v for k, v in rr['ring'].items() if k != '_sums'}
            out.append(rr)
        json.dump(out, open(a.json, 'w'), indent=1)
        print('\nJSON_WRITTEN %s' % a.json)


if __name__ == '__main__':
    main()
