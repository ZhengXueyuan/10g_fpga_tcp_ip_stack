#!/usr/bin/env python3
# e1_metrics.py -- summarize E1 latency runs (baseline/load) from raw/.
#   State is classified by sink rate (E0.5: fast 9.44, slow 9.07-9.26); the
#   45 s MID window exceeds the 27.49 s W43/W65 wrap period, so W65/W43 are
#   NOT used for state here (E0.5 10 s windows are the W65 reference).
import re, sys, math
from pathlib import Path

def pct(v, p):
    if not v: return -1
    v = sorted(v)
    i = int(math.ceil(p * len(v))) - 1
    return v[max(0, min(i, len(v)-1))]

def parse_ping(path):
    txt = path.read_text(encoding='utf-8', errors='replace')
    us = []
    for line in txt.splitlines():
        m = re.search(r'time=([\d.]+)\s*ms', line)
        if m: us.append(float(m.group(1)) * 1000.0)
    m = re.search(r'(\d+) packets transmitted, (\d+) received, ([\d.]+)% packet loss', txt)
    tx, rx, loss = (int(m.group(1)), int(m.group(2)), float(m.group(3))) if m else (0, 0, -1)
    return us, tx, rx, loss

def parse_probe(path):
    if not path.exists(): return None
    txt = path.read_text(encoding='utf-8', errors='replace')
    m = re.search(r'LAT_SUMMARY mode=(\S+).*?count=(\d+) ok=(\d+) loss=(\d+) bad=(\d+).*?'
                  r'min_us=(-?\d+) p50_us=(-?\d+) p90_us=(-?\d+) p99_us=(-?\d+) max_us=(-?\d+) mean_us=([\d.]+)', txt)
    if not m: return None
    keys = ['mode','count','ok','loss','bad','min','p50','p90','p99','max','mean']
    d = dict(zip(keys, m.groups()))
    for k in ('count','ok','loss','bad','min','p50','p90','p99','max'):
        d[k] = int(d[k])
    d['mean'] = float(d['mean'])
    return d

def sink_info(path):
    if not path.exists(): return None
    t = path.read_text(encoding='utf-8', errors='replace')
    m = re.search(r'SINK_SUM .*?bytes=(\d+).*?wall_s=([\d.]+).*?agg_Mbps=([\d.]+)', t)
    if not m: return None
    return dict(bytes=int(m.group(1)), wall=float(m.group(2)), mbps=float(m.group(3)))

def main(root):
    tags = ['E1BASE', 'E1BASE2', 'E1BASE3', 'E1BASE4', 'E1BASE5',
            'E1L1', 'E1L2', 'E1L3', 'E1L4', 'E1L5']
    rows = []
    for tag in tags:
        ping = root / f'{tag}_ping.txt'
        us, tx, rx, loss = parse_ping(ping) if ping.exists() else ([],0,0,-1)
        probes = {k: parse_probe(root / f'{tag}_{k}.txt') for k in ('tcp','udp64','udp996','udp1472')}
        rows.append(dict(tag=tag, ping=us, ping_loss=loss, probes=probes,
                         sink=sink_info(root / f'{tag}_A_sink.txt')))
    out = []
    out.append('E1 (0x32, zero-build) -- load-tail latency; probes on port B (192.168.100.4)')
    out.append('load = 60 GB TCP downlink on port A (nsa -> 192.168.100.2), THREADED sink')
    out.append('ping = ICMP echo 2000 @5 ms; tcp = connect() handshake 2000 @5 ms; udp = echo 64/996/1472')
    out.append('probe process pinned to CPU2; NIC IRQ 4-7; coalescing off; baseline/load both 3 s before probes')
    out.append('state = sink-rate based (fast >= 9.35 Gbps); 45 s MID window > 27.49 s W43 wrap => W65/W43 not used for state')
    out.append('')
    hdr = f"{'tag':7} {'mode':5} {'state':5} {'sinkG':>7} {'ping50':>7} {'ping99':>7} {'tcp50':>5} {'tcp99':>5} {'u64_50':>6} {'u64_99':>6} {'u996_50':>7} {'u996_99':>7} {'u1472_50':>8} {'u1472_99':>8}"
    out.append(hdr)
    for r in rows:
        s = r['sink']
        state = 'idle' if s is None else ('fast' if s['mbps'] >= 9350 else 'slow')
        def g(k, f):
            x = r['probes'].get(k); return x[f] if x else -1
        out.append(f"{r['tag']:7} {'load' if s else 'base':5} {state:5} "
                   f"{(s['mbps']/1000 if s else 0):7.4f} {pct(r['ping'],.50):7.1f} {pct(r['ping'],.99):7.1f} "
                   f"{g('tcp','p50'):5d} {g('tcp','p99'):5d} {g('udp64','p50'):6d} {g('udp64','p99'):6d} "
                   f"{g('udp996','p50'):7d} {g('udp996','p99'):7d} {g('udp1472','p50'):8d} {g('udp1472','p99'):8d}")
    out.append('')
    out.append('per-run probe detail (p50/p90/p99/max/mean us; loss/bad):')
    for r in rows:
        out.append(f"  {r['tag']:7} ping n={len(r['ping'])} p50={pct(r['ping'],.5):.1f} p99={pct(r['ping'],.99):.1f} loss={r['ping_loss']}%")
        for k in ('tcp','udp64','udp996','udp1472'):
            x = r['probes'].get(k)
            if x:
                out.append(f"    {k:7} n={x['count']} ok={x['ok']} loss={x['loss']} bad={x['bad']} "
                           f"p50={x['p50']} p90={x['p90']} p99={x['p99']} max={x['max']} mean={x['mean']:.1f}")
    out.append('')
    out.append('sink detail:')
    for r in rows:
        s = r['sink']
        if s:
            out.append(f"  {r['tag']:7} {s['bytes']:,} B / {s['wall']:.3f} s = {s['mbps']:.3f} Mbps")
    out.append('')
    out.append('notes:')
    out.append('- 1472 B UDP echo is run with --no-check: the HLS echo TX region is 1024 B total')
    out.append('  (TX_UDP_BASE=512, TX_UDP_SIZE=256 words, header 7 words) => max exact payload 996 B;')
    out.append('  >=997 B returns the requested length but bytes >=996 are zero-filled. 996 B is exact.')
    out.append('- TCP SYN to port 8080 is a data-app connection, not a control-plane listener; it may perturb the load.')
    out.append('- No fast-state load (>=9.35 Gbps) was captured in E1; load rows are slow-state (8.60-9.25 Gbps).')
    text = '\n'.join(out) + '\n'
    print(text)
    (root / 'E1_METRICS.txt').write_text(text, encoding='utf-8')

if __name__ == '__main__':
    main(Path(sys.argv[1] if len(sys.argv) > 1 else 'raw'))
