#!/usr/bin/env python3
# parse_pcap.py -- minimal pcap parser for b2a orphan arms (Ethernet/IPv4/TCP)
# Usage: parse_pcap.py FILE [--t0 EPOCH] [--t1 EPOCH] [--board 192.168.100.2] [--peer 192.168.100.100] [--port 8080]
import struct, sys, argparse, collections

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('file')
    ap.add_argument('--t0', type=float, default=None)
    ap.add_argument('--t1', type=float, default=None)
    ap.add_argument('--board', default='192.168.100.2')
    ap.add_argument('--peer', default='192.168.100.100')
    ap.add_argument('--port', type=int, default=8080)
    a = ap.parse_args()
    f = open(a.file, 'rb')
    gh = f.read(24)
    if len(gh) < 24: print("SHORT_HEADER"); return 2
    magic = gh[:4]
    if magic == b'\xd4\xc3\xb2\xa1': endian = '<'; nano = False
    elif magic == b'\xa1\xb2\xc3\xd4': endian = '>'; nano = False
    elif magic == b'\x4d\x3c\xb2\xa1': endian = '<'; nano = True
    elif magic == b'\xa1\xb2\x3c\x4d': endian = '>'; nano = True
    else: print("BAD_MAGIC %r" % magic); return 2
    board = a.board; peer = a.peer
    n = 0; kept = 0
    stats = collections.Counter()
    payload_hist = collections.Counter()
    b2p_t = []; b2p_len = []; p2b_t = []
    first = last = None
    while True:
        rh = f.read(16)
        if len(rh) < 16: break
        ts, tu, incl, orig = struct.unpack(endian + 'IIII', rh)
        data = f.read(incl)
        if len(data) < incl: break
        t = ts + tu / (1e9 if nano else 1e6)
        n += 1
        if a.t0 is not None and t < a.t0: continue
        if a.t1 is not None and t > a.t1: continue
        kept += 1
        if first is None: first = t
        last = t
        # Ethernet
        if len(data) < 14: continue
        et = struct.unpack('!H', data[12:14])[0]
        if et != 0x0800: stats['nonipv4'] += 1; continue
        ip = data[14:]
        if len(ip) < 20: continue
        ihl = (ip[0] & 0xf) * 4
        proto = ip[9]
        if proto != 6: stats['non-tcp'] += 1; continue
        tot = struct.unpack('!H', ip[2:4])[0]
        src = '.'.join(str(b) for b in ip[12:16])
        dst = '.'.join(str(b) for b in ip[16:20])
        tcp = ip[ihl:]
        if len(tcp) < 20: continue
        sp, dp = struct.unpack('!HH', tcp[:4])
        off = (tcp[12] >> 4) * 4
        flags = tcp[13]
        plen = tot - ihl - off
        if plen < 0: plen = 0
        is_board = (src == board and sp == a.port)
        is_peer = (dst == board and dp == a.port)
        if not (is_board or is_peer): stats['other'] += 1; continue
        d = 'B2P' if is_board else 'P2B'
        stats[d] += 1
        stats[d + '_bytes'] += plen
        if flags & 0x01: stats[d + '_FIN'] += 1
        if flags & 0x04: stats[d + '_RST'] += 1
        if flags & 0x02: stats[d + '_SYN'] += 1
        if flags & 0x10: stats[d + '_ACK'] += 1
        if plen == 0: stats[d + '_zero_payload'] += 1
        if d == 'B2P':
            payload_hist[plen] += 1; b2p_t.append(t); b2p_len.append(plen)
        else:
            p2b_t.append(t)
    print("FILE %s records=%d kept=%d first=%s last=%s span=%s" % (
        a.file, n, kept,
        '%.6f' % first if first else '-', '%.6f' % last if last else '-',
        '%.3f' % (last - first) if first else '-'))
    print("COUNTS " + " ".join("%s=%d" % (k, stats[k]) for k in sorted(stats)))
    print("B2P payload_hist " + " ".join("%dB:%d" % (k, payload_hist[k]) for k in sorted(payload_hist)))
    def iat(ts, name):
        if len(ts) < 2:
            print("%s n=%d (no IAT)" % (name, len(ts))); return
        ds = sorted(ts[i] - ts[i-1] for i in range(1, len(ts)))
        q = lambda p: ds[min(len(ds)-1, int(p*(len(ds)-1)))]
        print("%s n=%d iat_us p10=%.1f p50=%.1f p90=%.1f p99=%.1f max=%.1f" % (
            name, len(ts), q(.10)*1e6, q(.50)*1e6, q(.90)*1e6, q(.99)*1e6, ds[-1]*1e6))
        # 20 ms +/- 5 ms fraction and histogram coarse
        near = sum(1 for x in ds if 0.015 <= x <= 0.025)
        print("   frac_iat_in[15,25]ms=%.3f" % (near / len(ds)))
        h = collections.Counter()
        for x in ds:
            if x < 0.001: b='<1ms'
            elif x < 0.005: b='1-5ms'
            elif x < 0.015: b='5-15ms'
            elif x < 0.025: b='15-25ms'
            elif x < 0.050: b='25-50ms'
            elif x < 0.2: b='50-200ms'
            else: b='>=200ms'
            h[b] += 1
        print("   iat_hist " + " ".join("%s:%d" % (k, h[k]) for k in ['<1ms','1-5ms','5-15ms','15-25ms','25-50ms','50-200ms','>=200ms']))
    iat(b2p_t, 'B2P')
    iat(p2b_t, 'P2B')
    # per-10s B2P counts
    if b2p_t:
        t0 = b2p_t[0]; buckets = collections.Counter()
        for t in b2p_t: buckets[int((t - t0)//10)*10] += 1
        print("B2P 10s-buckets " + " ".join("%ds:%d" % (k, buckets[k]) for k in sorted(buckets)))
    return 0

if __name__ == '__main__':
    sys.exit(main())
