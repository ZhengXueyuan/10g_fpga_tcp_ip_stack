#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""occ_win.py -- parse a tcpdump pcap and report per-connection TCP window values

usage: occ_win.py <pcap> [last_k]
filters: IPv4 TCP, src == 192.168.100.4, payload length > 0.
prints one line per (sport,dport): frames, last/min/max window of the last K data frames.
"""
import struct, sys, collections

def main():
    path = sys.argv[1]
    K = int(sys.argv[2]) if len(sys.argv) > 2 else 8
    data = open(path, "rb").read()
    if len(data) < 24:
        print("EMPTY"); return 2
    magic = data[:4]
    if magic == b"\xd4\xc3\xb2\xa1":
        endian = "<"
    elif magic == b"\xa1\xb2\xc3\xd4":
        endian = ">"
    else:
        print("BAD_MAGIC", magic.hex()); return 2
    linktype = struct.unpack(endian + "I", data[20:24])[0]
    off = 24
    per = collections.defaultdict(list)
    allc = {}
    n = 0
    while off + 16 <= len(data):
        ts, tu, incl, orig = struct.unpack(endian + "IIII", data[off:off+16])
        off += 16
        pkt = data[off:off+incl]; off += incl
        n += 1
        if len(pkt) < 34: continue
        if linktype == 1:          # Ethernet
            eth = 12
            etype = struct.unpack(">H", pkt[eth:eth+2])[0]
            ipoff = eth + 2
            while etype == 0x8100:
                etype = struct.unpack(">H", pkt[ipoff+2:ipoff+4])[0]
                ipoff += 4
        elif linktype == 113:      # Linux cooked v1
            etype = struct.unpack(">H", pkt[14:16])[0]
            ipoff = 16
        elif linktype == 276:      # Linux cooked v2 (SLL2)
            etype = struct.unpack(">H", pkt[0:2])[0]
            ipoff = 20
        else:
            continue
        if etype != 0x0800: continue
        ip = pkt[ipoff:]
        if len(ip) < 20: continue
        ihl = (ip[0] & 0xF) * 4
        if ip[9] != 6: continue
        tot = struct.unpack(">H", ip[2:4])[0]
        src = ".".join(str(b) for b in ip[12:16])
        dst = ".".join(str(b) for b in ip[16:20])
        if src != "192.168.100.4": continue
        tcp = ip[ihl:]
        if len(tcp) < 20: continue
        sport, dport = struct.unpack(">HH", tcp[:4])
        doff = (tcp[12] >> 4) * 4
        win = struct.unpack(">H", tcp[14:16])[0]
        plen = tot - ihl - doff
        allc[(sport, dport)] = allc.get((sport, dport), 0) + 1
        if plen <= 0: continue
        per[(sport, dport)].append((ts + tu/1e6, win, plen))
    print("PCAP %s linktype=%d packets=%d conns=%d" % (path, linktype, n, len(per)))
    for k in sorted(allc):
        if k not in per:
            print("CONN %d->%d all=%d data=0" % (k[0], k[1], allc[k])); continue
        v = per[k][-K:]
        wins = [x[1] for x in v]
        print("CONN %d->%d all=%d data=%d lastK=%d win_last=%d win_min=%d win_max=%d t_last=%.3f"
              % (k[0], k[1], allc.get(k,0), len(per[k]), len(v), wins[-1], min(wins), max(wins), v[-1][0]))
    return 0

if __name__ == "__main__":
    sys.exit(main())
