#!/usr/bin/env python3
# e1a_metrics.py -- summarize P11 E1a-1 snapshots (W85..W96) from e1a_latency.sh raw/.
#   Bins (cycles @156.25 MHz): 0:0-127, 1:128-159, 2:160-191, 3:192-223,
#   4:224-255, 5:256-383, 6:384-511, 7:512-1023, 8:1024-4095, 9:>=4096.
#   W95 = sum_total (delta is window sum), W96 = max_total (GLOBAL since reset; do not delta).
#   Requires snapshot files with lines: W<idx> <addr> <name> <hex>.
import re, sys, math
from pathlib import Path

BINS = [(0,127),(128,159),(160,191),(192,223),(224,255),
        (256,383),(384,511),(512,1023),(1024,4095),(4096,None)]

def parse_snap(path):
    vals = {}
    if not path.exists():
        return vals
    for line in path.read_text(encoding='utf-8', errors='replace').splitlines():
        m = re.match(r'^W(\d+)\s+\S+\s+\S+\s+(0x[0-9a-fA-F]+)\s*$', line)
        if m:
            vals[int(m.group(1))] = int(m.group(2), 16)
    return vals

def d32(a, b):
    return (b - a) & 0xFFFFFFFF

def sink_mbps(path):
    if not path.exists():
        return None
    t = path.read_text(encoding='utf-8', errors='replace')
    m = re.search(r'SINK_SUM.*?agg_Mbps=([\d.]+)', t)
    if m:
        return float(m.group(1))
    m = re.search(r'SINK_SUM.*?Mbps=([\d.]+)', t)
    return float(m.group(1)) if m else None

def quantile(hist, q):
    n = sum(hist)
    if n == 0:
        return None
    target = math.ceil(q * n)
    cum = 0
    for i, c in enumerate(hist):
        cum += c
        if cum >= target:
            lo, hi = BINS[i]
            return i, lo, hi
    return 9, BINS[9][0], None

def fmt_q(hist, q):
    r = quantile(hist, q)
    if r is None:
        return 'n/a'
    i, lo, hi = r
    if hi is None:
        return f'bin{i} >={lo}cyc(>={lo*0.0064:.1f}us)'
    return f'bin{i} {lo}-{hi}cyc({lo*0.0064:.2f}-{hi*0.0064:.2f}us)'

def main(root):
    root = Path(root)
    out = []
    out.append('E1a-1 (0x33 geometry): per-frame DP TX latency hist; W85..W96')
    out.append('edges(cyc): ' + ', '.join(
        f'{i}:{lo}-{hi if hi is not None else "inf"}' for i,(lo,hi) in enumerate(BINS)))
    out.append('W95=sum_total (window delta); W96=max_total (GLOBAL since reset, NOT a delta)')
    out.append('')
    # Idle negative control (2 s, no traffic): hist/sum/max must all be 0.
    i0 = parse_snap(root / 'E1A_IDLE0.txt')
    i1 = parse_snap(root / 'E1A_IDLE1.txt')
    if i0 and i1:
        dh = sum(d32(i0.get(85+k, 0), i1.get(85+k, 0)) for k in range(10))
        ds = d32(i0.get(95, 0), i1.get(95, 0))
        dmx = d32(i0.get(96, 0), i1.get(96, 0))
        d43 = d32(i0.get(43, 0), i1.get(43, 0))
        d65 = d32(i0.get(65, 0), i1.get(65, 0))
        ok = (dh == 0 and ds == 0 and dmx == 0)
        out.append(f"IDLE negative control: d_hist={dh} d_sum={ds} d_max={dmx} "
                   f"(W43 +{d43}, W65 +{d65}) => {'PASS' if ok else 'FAIL'}")
        out.append('')
    hdr = (f"{'run':10} {'state':8} {'sinkG':>7} {'frames':>10} {'dW14':>10} {'gap':>5} "
           f"{'dW52-h':>6} {'mean_us':>8} {'meanX_us':>8} {'p50':>21} {'p99':>21} "
           f"{'tail%':>7} {'max_cyc':>10}")
    out.append(hdr)
    tags = sorted([p.name.replace('_MID1.txt', '') for p in root.glob('*_MID1.txt')
                   if re.match(r'.*_R\d+_MID1\.txt$', p.name)],
                  key=lambda s: int(re.search(r'_R(\d+)$', s).group(1)))
    tot_h = 0
    tot_d14 = 0
    tot_d52 = 0
    for tag in tags:
        pre = parse_snap(root / f'{tag}_PRE.txt')
        mid = parse_snap(root / f'{tag}_MID1.txt')
        post = parse_snap(root / f'{tag}_POST.txt')
        if not pre or not mid or not post:
            out.append(f'{tag:10} MISSING snapshot')
            continue
        # whole run = PRE -> POST (10 GB runs are ~9 s; sum_total 32-bit safe < 27.5 s).
        # MID1 exists for a 3 s state witness; do not use it as the histogram window.
        def window(a, b):
            h = [d32(a.get(85+i, 0), b.get(85+i, 0)) for i in range(10)]
            s = d32(a.get(95, 0), b.get(95, 0))
            return h, s
        h, s = window(pre, post)
        n = sum(h)
        mx = post.get(96, 0)  # GLOBAL since reset (not a window quantity)
        dw14 = d32(pre.get(14, 0), post.get(14, 0))  # port0 tcp_tx_frame.stat_frames
        dw52 = d32(pre.get(52, 0), post.get(52, 0))  # app_tx_frames
        sink = sink_mbps(root / f'{tag}_A_sink.txt')
        if sink is None:
            state = 'idle'
        elif sink >= 9350:
            state = 'fast'
        elif sink >= 9260:
            state = 'degraded'
        else:
            state = 'slow'
        mean = (s / n) if n else 0.0
        # One frame per session (the first one, presented before the connection opens)
        # can carry the whole inter-session idle gap; W96 shows it. Subtract at most the
        # single global max once to get mean without that polluted frame.
        meanx = ((s - mx) / n) if n and s >= mx else mean
        tail = (sum(h[7:]) / n * 100.0) if n else 0.0
        out.append(f"{tag:10} {state:8} {(sink or 0)/1000:7.4f} {n:10d} {dw14:10d} "
                   f"{dw14-n:5d} {dw52-n:6d} {mean*0.0064:8.2f} {meanx*0.0064:8.2f} "
                   f"{fmt_q(h,.50):>21} {fmt_q(h,.99):>21} {tail:7.3f} {mx:10d}")
        out.append(f"  bins: {h}  sum={s}")
        tot_h += n; tot_d14 += dw14; tot_d52 += dw52
    if tags:
        out.append(f"TOTAL runs={len(tags)} hist={tot_h} dW14={tot_d14} (gap {tot_d14-tot_h}) "
                   f"dW52={tot_d52} (dW52-hist {tot_d52-tot_h})")
    out.append('')
    out.append('notes:')
    out.append('- state bands: fast >=9.35 Gbps; degraded 9.26-9.35; slow <=9.26 (E0.5 clusters).')
    out.append('- meanX_us = mean with ONE global-max frame subtracted (see W96 note); '
               'raw mean includes it.')
    out.append('- tail% = frames in bin7..bin9 (>=512 cyc = >=3.28 us).')
    out.append('- p50/p99 are bin intervals, not point estimates; W96 is GLOBAL max since reset, so it is')
    out.append('  an upper bound for every window. max is polluted by the first frame of each session')
    out.append('  (presented before the connection opens; it then waits the whole idle gap ~1.2 s).')
    out.append('- If frames==0 with a nonzero sink, the instrument is not wired/triggered => FAIL (instrument).')
    out.append('- Primary denominator: hist_total <= dW14 (port0 tcp_tx_frame.stat_frames);')
    out.append('  dW14-hist_total = control/ring/probe/too-long frames. Same-module check: hist == dW52.')
    text = '\n'.join(out) + '\n'
    print(text)
    (root / 'E1A_METRICS.txt').write_text(text, encoding='utf-8')

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'raw')
