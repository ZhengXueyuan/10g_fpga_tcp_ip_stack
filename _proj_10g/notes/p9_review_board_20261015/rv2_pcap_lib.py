#!/usr/bin/env python3
# RV2 独立复算用:pcap 解析库(自写,不依赖被审件的 rfcseq_pcap_analyze.py / analyze_*.txt)
# 只读原始 .pcap;Ethernet + IPv4 + TCP 解析;不做任何过滤假设(上游过滤由调用方给)。
import struct, sys

def read_pcap(path):
    with open(path, "rb") as f:
        data = f.read()
    magic = data[:4]
    if magic == b"\xd4\xc3\xb2\xa1":
        endian = "<"
    elif magic == b"\xa1\xb2\xc3\xd4":
        endian = ">"
    else:
        raise SystemExit("bad magic %r" % magic)
    (vmaj, vmin, tz, sig, snap, link) = struct.unpack(endian + "HHiIII", data[4:24])
    off = 24
    pkts = []
    while off + 16 <= len(data):
        ts_sec, ts_usec, incl, orig = struct.unpack(endian + "IIII", data[off:off+16])
        off += 16
        frame = data[off:off+incl]
        off += incl
        pkts.append((ts_sec + ts_usec / 1e6, frame, orig))
    return link, pkts

def parse_eth_tcp(frame, vlan=False):
    """返回 dict 或 None。支持一层 VLAN(0x8100)。"""
    if len(frame) < 14:
        return None
    ethertype = struct.unpack(">H", frame[12:14])[0]
    l3 = 14
    if ethertype == 0x8100:
        ethertype = struct.unpack(">H", frame[16:18])[0]
        l3 = 18
    if ethertype != 0x0800:
        return None
    ip = frame[l3:]
    if len(ip) < 20:
        return None
    ihl = (ip[0] & 0xF) * 4
    proto = ip[9]
    tot = struct.unpack(">H", ip[2:4])[0]
    ident = struct.unpack(">H", ip[4:6])[0]
    src = socket_ntoa(ip[12:16]); dst = socket_ntoa(ip[16:20])
    if proto != 6 or len(ip) < ihl + 20:
        return None
    tcp = ip[ihl:]
    sport, dport, seq, ack, off_flags = struct.unpack(">HHIIH", tcp[:14])
    flags = off_flags & 0x1FF
    doff = (off_flags >> 12) & 0xF
    win = struct.unpack(">H", tcp[14:16])[0]
    plen = tot - ihl - doff * 4
    return dict(src=src, dst=dst, sport=sport, dport=dport, seq=seq, ack=ack,
                flags=flags, win=win, plen=plen, ident=ident)

def socket_ntoa(b):
    return "%d.%d.%d.%d" % (b[0], b[1], b[2], b[3])

def flagstr(f):
    s = ""
    for bit, ch in ((0x02, "S"), (0x10, "A"), (0x01, "F"), (0x04, "R"), (0x08, "P")):
        if f & bit:
            s += ch
    return s or "-"

if __name__ == "__main__":
    link, pkts = read_pcap(sys.argv[1])
    print("link=%d pkts=%d t=[%.6f,%.6f]" % (link, len(pkts), pkts[0][0], pkts[-1][0]))
    for t, fr, orig in pkts[:5]:
        p = parse_eth_tcp(fr)
        print("%.6f" % t, p if p else ("non-tcp len=%d" % len(fr)))
