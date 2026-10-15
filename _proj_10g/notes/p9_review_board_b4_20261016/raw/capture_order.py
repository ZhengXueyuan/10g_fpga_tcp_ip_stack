#!/usr/bin/env python3
"""Capture-order forensics for one dport: timestamps, seq regressions, gaps."""
import struct, sys
import numpy as np

BOARD_IP = "192.168.100.2"

def iter_packets(path):
    with open(path, "rb") as f:
        gh = f.read(24)
        magic = struct.unpack("<I", gh[:4])[0]
        endian = "<" if magic in (0xA1B2C3D4, 0xA1B23C4D) else ">"
        while True:
            hdr = f.read(16)
            if len(hdr) < 16:
                break
            ts, tu, caplen, origlen = struct.unpack(endian + "IIII", hdr)
            data = f.read(caplen)
            if len(data) < caplen:
                break
            yield ts + tu / 1e6, data

def parse_tcp(eth):
    if len(eth) < 34 or eth[12] != 0x08 or eth[13] != 0x00:
        return None
    ip = eth[14:]
    if (ip[0] >> 4) != 4 or ip[9] != 6:
        return None
    ihl = (ip[0] & 0xF) * 4
    tot = struct.unpack(">H", ip[2:4])[0]
    src = ".".join(str(x) for x in ip[12:16])
    tcp = ip[ihl:]
    sport, dport = struct.unpack(">HH", tcp[0:4])
    seq = struct.unpack(">I", tcp[4:8])[0]
    ack = struct.unpack(">I", tcp[8:12])[0]
    flags = tcp[13]
    wnd = struct.unpack(">H", tcp[14:16])[0]
    doff = (tcp[12] >> 4) * 4
    payload = bytes(tcp[doff:tot - ihl]) if tot >= ihl + doff else b""
    return (src, sport, dport, seq, ack, flags, wnd, payload)

def main():
    dports = [int(x) for x in sys.argv[1].split(",")]
    files = sys.argv[2:]
    recs = {d: [] for d in dports}
    t0 = None
    for p in files:
        for ts, data in iter_packets(p):
            r = parse_tcp(data)
            if r is None:
                continue
            src, sport, dport, seq, ack, flags, wnd, pl = r
            if src != BOARD_IP or sport != 8080 or dport not in recs:
                continue
            recs[dport].append((ts, seq, ack, flags, wnd, len(pl), pl))
    for d, lst in recs.items():
        if not lst:
            print(f"== dport {d}: no packets")
            continue
        lst.sort(key=lambda x: x[0])
        tstart = lst[0][0]
        print(f"===== dport {d}: {len(lst)} board->peer packets, span {lst[-1][0]-tstart:.1f}s =====")
        # find seq regressions in capture order among payload segments
        prev_end = None
        regress = []
        gaps = []
        for ts, seq, ack, flags, wnd, plen, pl in lst:
            if plen == 0:
                continue
            if prev_end is not None:
                if seq != prev_end:
                    delta = (seq - prev_end)
                    if delta & 0x80000000:
                        delta -= 0x100000000
                    regress.append((ts - tstart, seq, prev_end, delta, plen))
            prev_end = (seq + plen) & 0xFFFFFFFF
        print(f"  payload segs={sum(1 for x in lst if x[5])}; seq-discontinuities (in capture order) = {len(regress)}")
        for x in regress[:20]:
            print(f"    t={x[0]:.3f} seq={x[1]:#x} prev_end={x[2]:#x} delta={x[3]} len={x[4]}")
        if len(regress) > 20:
            print(f"    ... ({len(regress)} total)")
        # non-payload packets
        np_ = [(x[0]-tstart, x[3], x[5]) for x in lst if x[5] == 0]
        print(f"  non-payload packets = {len(np_)}: {[(round(a,3), hex(b)) for a,b,c in np_[:12]]}")
        # payload timeline summary: first/last
        first = [x for x in lst if x[5]]
        print(f"  first payload: t={first[0][0]-tstart:.3f} seq={first[0][1]:#x} len={first[0][5]}")
        print(f"  last  payload: t={first[-1][0]-tstart:.3f} seq={first[-1][1]:#x} len={first[-1][5]}")
        # histogram of inter-segment gaps > 0.5s
        big = []
        for i in range(1, len(first)):
            dt = first[i][0] - first[i-1][0]
            if dt > 0.5:
                big.append((first[i-1][0]-tstart, dt, first[i][1]))
        print(f"  gaps >0.5s between consecutive payload segs: {len(big)}")
        for x in big[:15]:
            print(f"    at t={x[0]:.2f} gap={x[1]:.2f}s next_seq={x[2]:#x}")

main()
