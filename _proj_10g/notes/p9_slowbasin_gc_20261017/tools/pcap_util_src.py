#!/usr/bin/env python3
"""faseg.py -- first-segment timing analyzer for p9_t2fast_ab_20261017.

For each sink connection (cli port) in the 'ctl' pcap (full 'tcp port 8080', snaplen 128):
  a) SYN-ACK -> first B2P data segment delay (ms)
  b) first B2P data segment -> first P2B ACK that advances ack past that segment (ms)
  c) first-1s B2P payload rate (basin-entry witness: "slow from the first second")
  d) whole-connection payload rate + payload bytes
  e) window advertised in the SYN-ACK and in the first data-ACK (rcvbuf witness)
Parser copied from tkbi.py (p9_p3win_trickle round; self-contained, no deps).

Usage: python3 faseg.py <pcap...> [--board 192.168.100.2] [--peer 192.168.100.100] [--port 8080]
"""
import struct, sys, argparse, collections

def read_pcap(paths):
    pkts = []
    for p in paths:
        with open(p, "rb") as fh:
            data = fh.read()
        if len(data) < 24:
            continue
        magic = data[:4]
        if magic == b"\xd4\xc3\xb2\xa1":
            endian, nano = "<", False
        elif magic == b"\xa1\xb2\xc3\xd4":
            endian, nano = ">", False
        elif magic == b"\x4d\x3c\xb2\xa1":
            endian, nano = "<", True
        elif magic == b"\xa1\xb2\x3c\x4d":
            endian, nano = ">", True
        else:
            sys.stderr.write("BAD_MAGIC %s %r\n" % (p, magic)); continue
        (_, _, _, _, _, linktype) = struct.unpack(endian + "HHIIII", data[4:24])
        off = 24
        n = 0
        while off + 16 <= len(data):
            ts_s, ts_f, incl, orig = struct.unpack(endian + "IIII", data[off:off+16])
            off += 16
            if off + incl > len(data):
                sys.stderr.write("TRUNCATED %s at off %d (incl=%d)\n" % (p, off, incl)); break
            ts = ts_s + (ts_f / 1e9 if nano else ts_f / 1e6)
            pkts.append((ts, linktype, data[off:off+incl]))
            off += incl
            n += 1
        sys.stderr.write("read %s: %d pkts linktype=%d\n" % (p, n, linktype))
    pkts.sort(key=lambda x: x[0])
    return pkts

def parse_pkt(ts, linktype, raw):
    if linktype == 1:
        if len(raw) < 14: return None
        eth_type = struct.unpack("!H", raw[12:14])[0]
        pay = raw[14:]
        if eth_type == 0x8100:
            if len(pay) < 4: return None
            eth_type = struct.unpack("!H", pay[2:4])[0]; pay = pay[4:]
        if eth_type != 0x0800: return None
    elif linktype == 113:
        if len(raw) < 16: return None
        eth_type = struct.unpack("!H", raw[14:16])[0]
        pay = raw[16:]
        if eth_type != 0x0800: return None
    else:
        return None
    if len(pay) < 20: return None
    ihl = (pay[0] & 0xF) * 4
    if pay[9] != 6: return None
    total_len = struct.unpack("!H", pay[2:4])[0]
    src = ".".join(str(b) for b in pay[12:16])
    dst = ".".join(str(b) for b in pay[16:20])
    t = pay[ihl:]
    if len(t) < 20: return None
    sport, dport, seq, ack, off_flags, win = struct.unpack("!HHIIHH", t[0:16])
    doff = (off_flags >> 12) * 4
    flags = off_flags & 0x1FF
    pay_len = total_len - ihl - doff
    if pay_len < 0: pay_len = 0
    return dict(ts=ts, src=src, dst=dst, sport=sport, dport=dport, seq=seq, ack=ack,
                flags=flags, win=win, pay=pay_len)

FL = [(0x01, "F"), (0x02, "S"), (0x04, "R"), (0x08, "P"), (0x10, "A")]
def fstr(f):
    return "".join(n for b, n in FL if f & b) or "-"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pcaps", nargs="+")
    ap.add_argument("--board", default="192.168.100.2")
    ap.add_argument("--peer", default="192.168.100.100")
    ap.add_argument("--port", type=int, default=8080)
    a = ap.parse_args()

    raw = read_pcap(a.pcaps)
    pkts = []
    for (ts, lt, r) in raw:
        p = parse_pkt(ts, lt, r)
        if p and (p["sport"] == a.port or p["dport"] == a.port):
            if p["src"] == a.board:
                p["dir"] = "B2P"
            elif p["src"] == a.peer:
                p["dir"] = "P2B"
            else:
                continue
            pkts.append(p)
    if not pkts:
        print("NO_PKTS"); return
    t0 = pkts[0]["ts"]
    print("pkts=%d span=%.3fs t0=%.6f" % (len(pkts), pkts[-1]["ts"] - t0, t0))

    # group by connection: cli side = peer, cli port = sport of P2B / dport of B2P
    conns = collections.defaultdict(list)
    for p in pkts:
        cp = p["sport"] if p["dir"] == "P2B" else p["dport"]
        conns[cp].append(p)

    print("\n=== per-connection first-segment timing (times rel t0, ms) ===")
    print("%-7s %5s %9s %9s %11s %11s %8s %8s %9s %9s %9s %6s" %
          ("cliport", "pkts", "t_syn", "t_synack", "synack->d1", "d1->ack1",
           "payB2P", "mbps", "first1s_B", "first1s_bps", "fack_win", "sa_win"))
    rows = []
    for cp, ps in sorted(conns.items(), key=lambda kv: kv[1][0]["ts"]):
        ps.sort(key=lambda x: x["ts"])
        syn = next((p for p in ps if p["dir"] == "P2B" and (p["flags"] & 0x02) and not (p["flags"] & 0x10)), None)
        synack = next((p for p in ps if p["dir"] == "B2P" and (p["flags"] & 0x12) == 0x12), None)
        d1 = next((p for p in ps if p["dir"] == "B2P" and p["pay"] > 0), None)
        first_ack = None
        first_ack_win = None
        if d1 is not None:
            end_seq = d1["seq"] + d1["pay"]
            for p in ps:
                if p["dir"] == "P2B" and (p["flags"] & 0x10) and p["ts"] >= d1["ts"] and p["pay"] == 0:
                    # ack must advance past the first data segment (mod 2^32 arithmetic)
                    if ((p["ack"] - end_seq) & 0xFFFFFFFF) < 0x80000000:
                        first_ack = p; first_ack_win = p["win"]; break
        if d1 is None:
            print("%-7d %5d %9.3f %9s %11s %11s %8s %8s %9s %9s %9s %6s  (no data)" %
                  (cp, len(ps),
                   (syn["ts"] - t0) * 1e3 if syn else -1,
                   "%.3f" % ((synack["ts"] - t0) * 1e3) if synack else "-",
                   "-", "-", 0, 0, 0, 0, "-",
                   synack["win"] if synack else "-"))
            continue
        # per-connection payload stats
        b2p = [p for p in ps if p["dir"] == "B2P" and p["pay"] > 0]
        pay = sum(p["pay"] for p in b2p)
        dur = ps[-1]["ts"] - d1["ts"]
        mbps = (pay * 8 / 1e6 / dur) if dur > 0 else 0
        d1t = d1["ts"]
        w1 = [p for p in b2p if p["ts"] - d1t <= 1.0]
        pay1 = sum(p["pay"] for p in w1)
        span1 = min(1.0, max((w1[-1]["ts"] - d1t) if w1 else 0, 1e-9))
        bps1 = pay1 * 8 / span1 if w1 else 0
        print("%-7d %5d %9.3f %9.3f %11.3f %11.3f %8d %8.2f %9d %9.0f %9s %6s" %
              (cp, len(ps),
               (syn["ts"] - t0) * 1e3 if syn else -1,
               (synack["ts"] - t0) * 1e3 if synack else -1,
               (d1["ts"] - synack["ts"]) * 1e3 if synack else -1,
               (first_ack["ts"] - d1["ts"]) * 1e3 if first_ack else -1,
               pay, mbps, pay1, bps1,
               first_ack_win if first_ack_win is not None else "-",
               synack["win"] if synack else "-"))
        rows.append(dict(cp=cp, synack_d1_ms=(d1["ts"] - synack["ts"]) * 1e3 if synack else None,
                         d1_ack1_ms=(first_ack["ts"] - d1["ts"]) * 1e3 if first_ack else None,
                         mbps=mbps, bps1=bps1))
    if rows:
        def med(xs):
            xs = sorted(x for x in xs if x is not None)
            return xs[len(xs)//2] if xs else float("nan")
        print("\n=== medians over %d conns ===" % len(rows))
        print("synack->d1 med = %.3f ms" % med([r["synack_d1_ms"] for r in rows]))
        print("d1->ack1  med = %.3f ms" % med([r["d1_ack1_ms"] for r in rows]))
        print("conn mbps med = %.2f ; first1s bps med = %.0f" %
              (med([r["mbps"] for r in rows]), med([r["bps1"] for r in rows])))

if __name__ == "__main__":
    main()
