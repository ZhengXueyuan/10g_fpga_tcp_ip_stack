#!/usr/bin/env python3
# split_conn_pcap.py -- 把多连接 pcap 按 (sport,dport) 拆成"每连接一个 pcap"（**数据搬运 plumbing**）
#   为什么需要它: 判据工具 align_check2_fixed.py 的 CLI 只收 `sport`（= 8080 ⇒ 一次含全部连接）;
#   设计件 §5.2-S4 要求"**每连接** K0/breaks/prefix"。⇒ 先用本件按 dport 拆出单连接 pcap，
#   再用设计件的工具逐连接跑（测量逻辑 100% 留在 align_check2_fixed.py 里，本件只做过滤+落盘）。
#   ⚠️ 拆出的 pcap 里**保留原帧字节**（只按 dport 过滤）⇒ 可被任何标准工具复跑。
#   ⚠️ 本件只写 payload 非空 + sport 命中的段（= 板上行的数据段）; 纯 ACK/握手段不进单连接文件
#      （align_check2 本来也只用有载荷的段）。
#   用法: python3 split_conn_pcap.py <out_dir> <tag> <pcap...>    (env SPORT=8080 可覆盖)
import os
import struct
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

SPORT = int(os.environ.get("SPORT", "8080"))


def read_pcap(path):
    with open(path, "rb") as f:
        gh = f.read(24)
        if len(gh) < 24:
            return
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
            yield (ts, tu, data, origlen)


def parse_tcp(eth):
    if len(eth) < 34:
        return None
    ip = eth[14:]
    if (ip[0] >> 4) != 4 or ip[9] != 6:
        return None
    ihl = (ip[0] & 0xF) * 4
    tot = struct.unpack(">H", ip[2:4])[0]
    tcp = ip[ihl:]
    if len(tcp) < 20:
        return None
    sport, dport = struct.unpack(">HH", tcp[0:4])
    seq = struct.unpack(">I", tcp[4:8])[0]
    doff = (tcp[12] >> 4) * 4
    payload = bytes(tcp[doff:tot - ihl]) if tot >= ihl + doff else b""
    return (sport, dport, seq, payload)


def main():
    out_dir, tag = sys.argv[1], sys.argv[2]
    files = sys.argv[3:]
    os.makedirs(out_dir, exist_ok=True)
    per = {}   # (sport,dport) -> list of (ts,tu,data,origlen); 同时记 segs/bytes
    for p in files:
        for ts, tu, data, origlen in read_pcap(p):
            r = parse_tcp(data)
            if r is None:
                continue
            sport, dport, seq, pl = r
            if sport != SPORT or not pl:
                continue
            per.setdefault((sport, dport), []).append((ts, tu, data, origlen))
    print("SPLIT tag=%s files=%d conns=%d sport=%d" % (tag, len(files), len(per), SPORT))
    for (sport, dport), lst in sorted(per.items(), key=lambda kv: kv[0][1]):
        nb = sum(len(parse_tcp(d)[3]) for _, _, d, _ in lst)
        path = os.path.join(out_dir, "%s_%d_%d.pcap" % (tag, sport, dport))
        with open(path, "wb") as f:
            f.write(struct.pack("<IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))
            for ts, tu, data, origlen in lst:
                f.write(struct.pack("<IIII", ts, tu, len(data), origlen) + data)
        print("  CONN dport=%-5d segs=%-8d bytes=%-12d file=%s" % (dport, len(lst), nb, os.path.basename(path)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
