#!/usr/bin/env python3
"""tk_dump.py -- dumb, auditable pcap extractor for one TCP connection.

Usage:  tk_dump.py <pcap...> --dport N [--out CSV]
Writes CSV: t_rel,t_abs,dir,seq,ack,flags,win,len
  dir = B2P (src=192.168.100.2 sport=8080) or P2B (dst=...:8080)
  t_abs = unix seconds (float), t_rel = t_abs - first packet of the conn
Standard libpcap (LE), Ethernet/IPv4/TCP.  No tcpdump/toolchain needed.
"""
import struct, sys

BOARD = "192.168.100.2"
SPORT = 8080


def iter_packets(path):
    with open(path, "rb") as f:
        gh = f.read(24)
        if len(gh) < 24:
            return
        magic = struct.unpack("<I", gh[:4])[0]
        assert magic == 0xA1B2C3D4, f"unexpected magic {magic:#x} in {path}"
        while True:
            hdr = f.read(16)
            if len(hdr) < 16:
                break
            ts, tu, caplen, origlen = struct.unpack("<IIII", hdr)
            data = f.read(caplen)
            if len(data) < caplen:
                break
            yield ts + tu / 1e6, data


def parse(eth):
    if len(eth) < 34 or eth[12] != 0x08 or eth[13] != 0x00:
        return None
    ip = eth[14:]
    if (ip[0] >> 4) != 4 or ip[9] != 6:
        return None
    ihl = (ip[0] & 0xF) * 4
    tot = struct.unpack(">H", ip[2:4])[0]
    src = "%d.%d.%d.%d" % (ip[12], ip[13], ip[14], ip[15])
    tcp = ip[ihl:]
    if len(tcp) < 20:
        return None
    sport, dport = struct.unpack(">HH", tcp[0:4])
    seq, ack = struct.unpack(">II", tcp[4:12])
    doff = (tcp[12] >> 4) * 4
    flags = tcp[13]
    win = struct.unpack(">H", tcp[14:16])[0]
    plen = tot - ihl - doff
    payload = bytes(tcp[doff:doff + plen]) if plen > 0 else b""
    return (src, sport, dport, seq, ack, flags, win, payload)


def main():
    args = sys.argv[1:]
    dport = None
    out = None
    files = []
    i = 0
    while i < len(args):
        if args[i] == "--dport":
            dport = int(args[i + 1]); i += 2
        elif args[i] == "--out":
            out = args[i + 1]; i += 2
        else:
            files.append(args[i]); i += 1
    assert dport is not None
    rows = []
    for p in files:
        for t, data in iter_packets(p):
            r = parse(data)
            if r is None:
                continue
            src, sport, dp, seq, ack, flags, win, pl = r
            if sport == SPORT and src == BOARD and dp == dport:
                rows.append((t, "B2P", seq, ack, flags, win, pl))
            elif dp == SPORT and sport == dport:
                rows.append((t, "P2B", seq, ack, flags, win, pl))
    rows.sort(key=lambda r: r[0])
    if not rows:
        print("NO PACKETS")
        return
    t0 = rows[0][0]
    fh = open(out, "w") if out else sys.stdout
    fh.write("t_rel,t_abs,dir,seq,ack,flags,win,len\n")
    for t, d, seq, ack, flags, win, pl in rows:
        fh.write("%.6f,%.6f,%s,%u,%u,0x%02x,%u,%d\n" % (t - t0, t, d, seq, ack, flags, win, len(pl)))
    if out:
        fh.close()
        print("wrote %s rows=%d t0=%.6f" % (out, len(rows), t0))


if __name__ == "__main__":
    main()
