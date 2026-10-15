#!/usr/bin/env python3
# rfcseq_pcap_analyze.py -- B2 主抓包分析 (工作站侧; 纯 stdlib 解析经典 pcap + Ethernet/IPv4/TCP)
#   判据面 (设计件 §7.2): 每次注入帧之后, 【板→对端】方向是否出现帧 (及其 seq/ack/flags/plen)。
#   注入帧定位 = **以 inject 日志的 INJECT 行 (seq, len) 为准** (优先), 辅以 IP-ID 标记 0xA5C0..:
#     ⚠️ 标记**单独不够**: 内核自选 IP-ID 会偶发落进标记段 (实测 P27: 77 帧"假标记"),
#     故匹配口径 = `INJECT kind seq len` 三元组 + 方向/端口 + (标记作为第三号见证)。
#   用法: python3 rfcseq_pcap_analyze.py <inject_log.txt> <main.pcap>
#   只给读数与形态; PASS/FAIL 裁定权在用户/判据所有者。
import struct, sys, os, re

BOARD = "192.168.100.2"
MYIP = "192.168.100.100"
ID_BASE = 0xA5C0

def ipstr(b):
    return ".".join(str(x) for x in b)

def flagstr(f):
    s = ""
    for bit, ch in ((0x02, "S"), (0x10, "A"), (0x01, "F"), (0x04, "R"), (0x08, "P"), (0x20, "U")):
        if f & bit:
            s += ch
    return s or "-"

def read_pcap(path):
    with open(path, "rb") as f:
        gh = f.read(24)
        if len(gh) < 24:
            return []
        magic = gh[:4]
        if magic in (b"\xd4\xc3\xb2\xa1", b"\x4d\x3c\xb2\xa1"):
            endian = "<"
        elif magic in (b"\xa1\xb2\xc3\xd4", b"\xa1\xb2\x3c\x4d"):
            endian = ">"
        else:
            sys.stderr.write("BAD_PCAP_MAGIC %r\n" % magic)
            return []
        linktype = struct.unpack(endian + "I", gh[20:24])[0]
        if linktype != 1:
            sys.stderr.write("WARN linktype=%d (非 Ethernet)\n" % linktype)
        out = []
        while True:
            ph = f.read(16)
            if len(ph) < 16:
                break
            ts_s, ts_us, incl, orig = struct.unpack(endian + "IIII", ph)
            pkt = f.read(incl)
            out.append((ts_s + ts_us / 1e6, pkt, orig))
        return out

def parse_eth_ip_tcp(pkt):
    if len(pkt) < 14 + 20 + 20:
        return None
    if pkt[12:14] != b"\x08\x00":
        return None
    ip = pkt[14:]
    ihl = (ip[0] & 0xF) * 4
    if ip[9] != 6 or len(ip) < ihl + 20:
        return None
    src = ipstr(ip[12:16]); dst = ipstr(ip[16:20])
    ident = struct.unpack(">H", ip[4:6])[0]
    tot = struct.unpack(">H", ip[2:4])[0]
    tcp = ip[ihl:]
    sport, dport, seq, ack, off_flags = struct.unpack(">HHIIH", tcp[:14])
    flags = off_flags & 0x1FF
    doff = (off_flags >> 12) & 0xF
    win = struct.unpack(">H", tcp[14:16])[0]
    plen = tot - ihl - doff * 4
    return dict(src=src, dst=dst, sport=sport, dport=dport, seq=seq, ack=ack,
                flags=flags, win=win, plen=plen, ident=ident)

def load_inject_log(path):
    """从 inject_*.txt 提 INJECT 行 ⇒ [(kind, seq, len, t)]"""
    out = []
    for ln in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"INJECT kind=(\S+) seq=0x([0-9A-Fa-f]+) len=(\d+) ack=0x([0-9A-Fa-f]+) win=(\d+) ident=0x([0-9A-Fa-f]+) t=([0-9.]+)", ln.strip())
        if m:
            out.append(dict(kind=m.group(1), seq=int(m.group(2), 16), plen=int(m.group(3)),
                            ack=int(m.group(4), 16), ident=int(m.group(6), 16), t=float(m.group(7))))
    return out

def analyze(ilog, pcap):
    inj = load_inject_log(ilog)
    pkts = read_pcap(pcap)
    print("== pcap %s: %d 包 | inject 日志 %s: %d 条 INJECT ==" % (
        os.path.basename(pcap), len(pkts), os.path.basename(ilog), len(inj)))
    board = []; peer = []; ctl = []
    for t, raw, orig in pkts:
        p = parse_eth_ip_tcp(raw)
        if p is None:
            continue
        if p["src"] == BOARD:
            board.append((t, p))
        elif p["dst"] == BOARD:
            peer.append((t, p))
        if p["flags"] & (0x01 | 0x04):
            ctl.append((t, p))
    print("   board->peer=%d  peer->board=%d  FIN/RST=%d  pcap 窗=[%.3f, %.3f] (%.2f s)" % (
        len(board), len(peer), len(ctl), pkts[0][0] if pkts else 0, pkts[-1][0] if pkts else 0,
        (pkts[-1][0] - pkts[0][0]) if pkts else 0))
    for t, p in ctl:
        print("   CTRL t=%.6f flags=%s seq=%u ack=%u len=%d" % (t, flagstr(p["flags"]), p["seq"], p["ack"], p["plen"]))
    for e in inj:
        # 注入帧定位: 同 seq + 同 len + 方向(p2b) + dport 8080 (标记为第三号见证)
        cand = [(t, p) for t, p in peer if p["seq"] == e["seq"] and p["plen"] == e["plen"] and p["dport"] == 8080]
        print("-- 注入 kind=%s seq=%u len=%d (ident 标记 0x%04X) 在 pcap 中命中 %d 帧" % (
            e["kind"], e["seq"], e["plen"], e["ident"], len(cand)))
        if not cand:
            print("   !! 注入帧不在 pcap 中 (抓包尾部截断? 见 tcpdump 自报)")
            continue
        for t0, pi in cand:
            print("   注入帧 t=%.6f ident=0x%04X ack=%u flags=%s%s" % (
                t0, pi["ident"], pi["ack"], flagstr(pi["flags"]),
                " <标记符合>" if ID_BASE <= pi["ident"] < ID_BASE + 0x40 else " <标记不符!>"))
            for lo, hi, label in ((-0.8, -0.001, "ambient"), (0.0, 0.002, "0-2ms"), (0.0, 0.1, "0-100ms"), (0.0, 0.6, "0-600ms")):
                sel = [(t, p) for t, p in board if lo <= (t - t0) < hi]
                print("   [%s] board_frames=%d" % (label, len(sel)))
                for t, p in sel[:20]:
                    print("      t=%.6f(rel %+.3f ms) seq=%u ack=%u win=%d len=%d flags=%s" % (
                        t, (t - t0) * 1000.0, p["seq"], p["ack"], p["win"], p["plen"], flagstr(p["flags"])))
            sel_p = [(t, p) for t, p in peer if p is not pi and 0.0 <= (t - t0) < 0.1]
            print("   [peer frames after 0-100ms] n=%d %s" % (
                len(sel_p), "; ".join("t=%+.3fms flags=%s len=%d" % ((t - t0) * 1000, flagstr(p["flags"]), p["plen"]) for t, p in sel_p[:8])))
    print("-- 全窗板侧帧目录 (共 %d; 上限 200) --" % len(board))
    for t, p in board[:200]:
        print("   t=%.6f seq=%u ack=%u win=%d len=%d flags=%s" % (t, p["seq"], p["ack"], p["win"], p["plen"], flagstr(p["flags"])))

if __name__ == "__main__":
    analyze(sys.argv[1], sys.argv[2])
