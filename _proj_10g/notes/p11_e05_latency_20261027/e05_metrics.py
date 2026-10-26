#!/usr/bin/env python3
# e05_metrics.py -- compute E0.5 window/queue metrics from the four raw console captures.
#   Inputs: raw/E05{,B,C,D}_CONSOLE.txt (SNAP_BEGIN ... Wn lines + SINK_SUM).
#   Time base: W43 (tx-domain cycle counter; NOT tx words -- P7b A7 #77) mod 2^32 at 156.25 MHz.
#   W5 (FE clock) is reported as a cross-check; wall clock is NOT used.
#   Output: stdout table; also archived as raw/E05_METRICS.txt.
import re, sys
from pathlib import Path
M = 1 << 32
FCLK = 156.25e6

def parse(path):
    txt = path.read_text(encoding='utf-8', errors='replace')
    blocks, cur = {}, None
    for line in txt.splitlines():
        m = re.match(r'SNAP_BEGIN (\S+) gen=', line)
        if m:
            cur = m.group(1); blocks[cur] = {}; continue
        m = re.match(r'W(\d+)\s+0x[0-9A-Fa-f]+\s+\S+\s+(0x[0-9A-Fa-f]+)', line)
        if m and cur:
            blocks[cur][int(m.group(1))] = int(m.group(2), 16)
    s = re.search(r'SINK_SUM .*?bytes=(\d+).*?wall_s=([\d.]+).*?agg_Mbps=([\d.]+)', txt)
    sink = (int(s.group(1)), float(s.group(3)), float(s.group(2))) if s else None
    return blocks, sink

def main(root):
    rows = []
    for tag in ('E05', 'E05B', 'E05C', 'E05D'):
        blocks, sink = parse(root / f'{tag}_CONSOLE.txt')
        k1 = next(k for k in blocks if 'MID1' in k)
        k2 = next(k for k in blocks if 'MID2' in k)
        a, c = blocks[k1], blocks[k2]
        d = {k: (c[k] - a[k]) % M for k in (5, 20, 43, 65, 66, 67, 68, 27, 28)}
        dt = d[43] / FCLK
        idle_ms = 1000.0 * d[65] / FCLK
        win_ms = 1000.0 * d[66] / FCLK
        peerwin_ms = 1000.0 * (d[66] - d[67]) / FCLK
        rows.append(dict(
            tag=tag, sink_Mbps=sink[1], sink_s=sink[2], bytes=sink[0],
            dt=dt, fps=d[20] / dt, wp=d[43] / d[20], ack=d[68] / d[20],
            idle_pct=100.0 * d[65] / d[43], win_pct=100.0 * d[66] / d[43],
            win_idle_pct=100.0 * d[66] / d[65],
            cap_win_pct=100.0 * d[67] / d[66],
            peerwin_pct=100.0 * (d[66] - d[67]) / d[43], w5_w43=d[5] / d[43],
            idle_ms=idle_ms, win_ms=win_ms, peerwin_ms=peerwin_ms,
            dW27=d[27], dW28=d[28], raw=d))
    out = []
    out.append('E0.5 (0x32, zero-build) - 9G-class single-port TCP downlink, MID1->MID2 windows')
    out.append('time base = dW43 / 156.25 MHz (tx-domain cycle counter), deltas mod 2^32; W5 cross-check = dW5/dW43')
    out.append('')
    out.append('tag   sinkG   fps_board  W43/W20  ACK/frm  idle%   win/idle%  cap/win%  win/clk%  peerwin/clk%  idle_ms  win_ms  peerwin_ms  dW27 dW28')
    for r in rows:
        out.append(f"{r['tag']:5} {r['sink_Mbps']/1000:7.4f} {r['fps']:10.1f} {r['wp']:8.3f} {r['ack']:8.4f} "
                   f"{r['idle_pct']:7.3f} {r['win_idle_pct']:10.2f} {r['cap_win_pct']:9.2f} "
                   f"{r['win_pct']:8.3f} {r['peerwin_pct']:13.3f} "
                   f"{r['idle_ms']:8.2f} {r['win_ms']:7.2f} {r['peerwin_ms']:11.2f} {r['dW27']:5d} {r['dW28']:4d}")
    out.append('')
    out.append('raw deltas (MID1->MID2):')
    for r in rows:
        d = r['raw']
        out.append(f"  {r['tag']:5} dW5={d[5]:,} dW20={d[20]:,} dW43={d[43]:,} dW65={d[65]:,} "
                   f"dW66={d[66]:,} dW67={d[67]:,} dW68={d[68]:,} sink_bytes={r['bytes']:,} sink_s={r['sink_s']:.3f} "
                   f"dW5/dW43={r['w5_w43']:.9f}")
    out.append('')
    out.append('structural bound: WIN_CAP = 61,440 B => 42.08 frames of 1460 B; drain time at observed sink rate:')
    for r in rows:
        out.append(f"  {r['tag']:5} {61440*8/(r['sink_Mbps']*1e6)*1e6:.2f} us")
    out.append('')
    out.append('state label (descriptive): fast if idle% < 0.5 else slow')
    for r in rows:
        out.append(f"  {r['tag']:5} {'fast' if r['idle_pct'] < 0.5 else 'slow'}")

    # ---- supplementary long runs: 60 GB single connections, five 10 s windows each ----
    for ltag in ('E05L', 'E05M'):
        lb, lsink = parse(root / f'{ltag}_CONSOLE.txt')
        lkeys = [k for k in (f'{ltag}_L1', f'{ltag}_L2', f'{ltag}_L3', f'{ltag}_L4', f'{ltag}_L5') if k in lb]
        out.append('')
        out.append(f'long run {ltag} (60 GB single connection; consecutive ~10 s windows, board time base)')
        out.append('window   dW43          dW20       idle%   win/idle%  cap/win%  win/clk%  fps_board  cyc/frm  ACK/frm  dW27 dW28')
        for a, b in zip(lkeys, lkeys[1:]):
            A, B = lb[a], lb[b]
            d = {k: (B[k] - A[k]) % M for k in (5, 20, 43, 65, 66, 67, 68, 27, 28)}
            dt = d[43] / FCLK
            out.append(f"{a[-2:]}->{b[-2:]}  {d[43]:>12,}  {d[20]:>9,}  {100*d[65]/d[43]:6.3f}  {100*d[66]/d[65]:9.2f}  "
                       f"{100*d[67]/d[66]:8.2f}  {100*d[66]/d[43]:8.3f}  {d[20]/dt:9.1f}  {d[43]/d[20]:7.3f}  "
                       f"{d[68]/d[20]:7.4f}  {d[27]:4d} {d[28]:4d}")
        if lsink:
            out.append(f"{ltag} sink: {lsink[0]:,} B / {lsink[2]:.3f} s = {lsink[1]:.3f} Mbps; mism=0 path per SINK_SUM")
    text = '\n'.join(out) + '\n'
    print(text)
    (root / 'E05_METRICS.txt').write_text(text, encoding='utf-8')

if __name__ == '__main__':
    main(Path(sys.argv[1] if len(sys.argv) > 1 else 'raw'))
