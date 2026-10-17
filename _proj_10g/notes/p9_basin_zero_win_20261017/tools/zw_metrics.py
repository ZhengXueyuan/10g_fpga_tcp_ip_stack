#!/usr/bin/env python3
"""zw_metrics.py -- p9_basin_zero_win_20261017 peer-advertised zero-window ACK metrics.

Definitions (pre-registered in the round README sec.1):
  * ACK population      : packets PEER -> BOARD (src = 192.168.100.100, sport/dport = 8080)
                          with TCP ACK flag set and ZERO TCP payload (pay == 0).
                          (Same base as p9_basin_probe_20261017/tools/probe_metrics.py
                          peer_win_hist => cross-round comparable.)
  * zero-window ACK     : one of those ACKs with the advertised window field win == 0.
  * zw_pct (PRIMARY)    : 100 * #(win==0) / #(ACKs)          [aggregate over the run]
  * zw_pct_pure (SEC.)  : same, but only pure ACKs (flags == 0x10; excludes FIN/RST+ACK).
  * per-conn zw_pct     : same ratio per connection (cliport = peer ephemeral port).
  * run_median_conn_zw  : median of per-connection zw_pct over conns with >= MIN_ACKS acks.

The window field is the PEER's advertised receive window (the peer is the data receiver
in this experiment).  Board-side window is reported separately (B2P data packets).

Also emits a per-ACK CSV (ts_rel,cliport,win,flags,seq,ack) for recomputation.  For very
large ACK counts the CSV is sampled every K-th ACK (+ first/last 1000) and says so in a
header comment -- the exact counts/ratio always come from the full parse, never the CSV.

Usage:
  python zw_metrics.py <pcap...> --label TAG [--json OUT.json] [--acks-csv OUT.csv]
                       [--port 8080] [--board 192.168.100.2] [--peer 192.168.100.100]
                       [--csv-cap 200000]
"""
import argparse
import collections
import json
import os
import struct
import sys

MSS = 1460
MIN_ACKS_PER_CONN = 20


def read_pcap(paths):
    pkts = []
    for p in paths:
        with open(p, "rb") as fh:
            data = fh.read()
        if len(data) < 24:
            sys.stderr.write("SHORT %s\n" % p)
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
            sys.stderr.write("BAD_MAGIC %s %r\n" % (p, magic))
            continue
        linktype = struct.unpack(endian + "HHIIII", data[4:24])[5]
        off = 24
        n = 0
        while off + 16 <= len(data):
            ts_s, ts_f, incl, _orig = struct.unpack(endian + "IIII", data[off:off + 16])
            off += 16
            if off + incl > len(data):
                break
            ts = ts_s + (ts_f / 1e9 if nano else ts_f / 1e6)
            pkts.append((ts, linktype, data[off:off + incl]))
            off += incl
            n += 1
        sys.stderr.write("read %s: %d pkts linktype=%d\n" % (p, n, linktype))
    pkts.sort(key=lambda x: x[0])
    return pkts


def parse_pkt(ts, linktype, raw):
    if linktype == 1:
        if len(raw) < 14:
            return None
        eth_type = struct.unpack("!H", raw[12:14])[0]
        pay = raw[14:]
        if eth_type == 0x8100:
            if len(pay) < 4:
                return None
            eth_type = struct.unpack("!H", pay[2:4])[0]
            pay = pay[4:]
        if eth_type != 0x0800:
            return None
    elif linktype == 113:
        if len(raw) < 16:
            return None
        eth_type = struct.unpack("!H", raw[14:16])[0]
        pay = raw[16:]
        if eth_type != 0x0800:
            return None
    else:
        return None
    if len(pay) < 20:
        return None
    ihl = (pay[0] & 0xF) * 4
    if pay[9] != 6:
        return None
    total_len = struct.unpack("!H", pay[2:4])[0]
    src = ".".join(str(b) for b in pay[12:16])
    dst = ".".join(str(b) for b in pay[16:20])
    t = pay[ihl:]
    if len(t) < 20:
        return None
    sport, dport, seq, ack, off_flags, win = struct.unpack("!HHIIHH", t[0:16])
    doff = (off_flags >> 12) * 4
    flags = off_flags & 0x1FF
    pay_len = total_len - ihl - doff
    if pay_len < 0:
        pay_len = 0
    return dict(ts=ts, src=src, dst=dst, sport=sport, dport=dport, seq=seq, ack=ack,
                flags=flags, win=win, pay=pay_len)


def pct(x, n):
    return (100.0 * x / n) if n else 0.0


def median(xs):
    xs = sorted(xs)
    n = len(xs)
    if not n:
        return None
    return xs[n // 2] if n % 2 else 0.5 * (xs[n // 2 - 1] + xs[n // 2])


def hist_line(counter, top=10):
    tot = sum(counter.values())
    items = sorted(counter.items(), key=lambda kv: -kv[1])[:top]
    return " ".join("%d:%d(%.1f%%)" % (k, v, pct(v, tot)) for k, v in items)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pcaps", nargs="+")
    ap.add_argument("--label", default="")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--board", default="192.168.100.2")
    ap.add_argument("--peer", default="192.168.100.100")
    ap.add_argument("--json", default=None)
    ap.add_argument("--acks-csv", default=None)
    ap.add_argument("--csv-cap", type=int, default=200000,
                    help="max ACKs written per connection; beyond this, sample")
    a = ap.parse_args()

    raw = read_pcap(a.pcaps)
    pkts = []
    for (ts, lt, r) in raw:
        p = parse_pkt(ts, lt, r)
        if not p:
            continue
        if p["sport"] == a.port or p["dport"] == a.port:
            if p["src"] == a.board:
                p["dir"] = "B2P"
            elif p["src"] == a.peer:
                p["dir"] = "P2B"
            else:
                continue
            pkts.append(p)
    if not pkts:
        print("NO_PKTS")
        return 1
    pkts.sort(key=lambda x: x["ts"])
    t0 = pkts[0]["ts"]
    tend = pkts[-1]["ts"]

    conns = collections.defaultdict(list)
    for p in pkts:
        cp = p["sport"] if p["dir"] == "P2B" else p["dport"]
        conns[cp].append(p)

    results = []
    csv_rows = []
    for cp in sorted(conns, key=lambda k: conns[k][0]["ts"]):
        ps = sorted(conns[cp], key=lambda x: x["ts"])
        acks = [p for p in ps if p["dir"] == "P2B" and (p["flags"] & 0x10) and p["pay"] == 0]
        pure = [p for p in acks if p["flags"] == 0x10]
        data = [p for p in ps if p["dir"] == "B2P" and p["pay"] > 0]
        syn = next((p for p in ps if p["dir"] == "P2B" and (p["flags"] & 0x02) and not (p["flags"] & 0x10)), None)
        synack = next((p for p in ps if p["dir"] == "B2P" and (p["flags"] & 0x12) == 0x12), None)
        n_acks = len(acks)
        n_win0 = sum(1 for p in acks if p["win"] == 0)
        n_pure = len(pure)
        n_pure_win0 = sum(1 for p in pure if p["win"] == 0)
        n_finack = sum(1 for p in acks if p["flags"] & 0x01)
        win_hist = collections.Counter(p["win"] for p in acks)
        pure_hist = collections.Counter(p["win"] for p in pure)
        board_win = collections.Counter(p["win"] for p in data)
        # zero<->nonzero transition counts (mechanism colour, not a criterion)
        zw_trans = 0
        prev = None
        for p in acks:
            z = (p["win"] == 0)
            if prev is not None and z != prev:
                zw_trans += 1
            prev = z
        r = dict(cliport=cp,
                 n_pkts=len(ps), n_data=len(data), n_acks=n_acks,
                 n_win0=n_win0, zw_pct=pct(n_win0, n_acks),
                 n_pure=n_pure, n_pure_win0=n_pure_win0, zw_pct_pure=pct(n_pure_win0, n_pure),
                 n_finack=n_finack, win_transitions=zw_trans,
                 syn_win=(syn["win"] if syn else None),
                 synack_win=(synack["win"] if synack else None),
                 peer_win_hist=dict(win_hist),
                 peer_win_pure_hist=dict(pure_hist),
                 board_win_hist=dict(board_win),
                 t_first_ack=(acks[0]["ts"] - t0) if acks else None,
                 t_last_ack=(acks[-1]["ts"] - t0) if acks else None)
        if data:
            d1 = data[0]
            pay_bytes = sum(p["pay"] for p in data)
            life = data[-1]["ts"] - d1["ts"]
            r.update(pay_bytes=pay_bytes, life_s=life,
                     rate_mbps=(pay_bytes * 8 / 1e6 / life) if life > 0 else 0.0)
        else:
            r.update(pay_bytes=0, life_s=0.0, rate_mbps=0.0)
        results.append(r)
        # per-ACK CSV rows (full or sampled)
        take = acks
        sampled = False
        if len(acks) > a.csv_cap:
            step = (len(acks) + a.csv_cap - 1) // a.csv_cap
            take = acks[:1000] + acks[1000:-1000:step] + acks[-1000:]
            sampled = True
        for p in take:
            csv_rows.append((p["ts"] - t0, cp, p["win"], p["flags"], p["seq"], p["ack"], int(sampled)))

    valid = [r for r in results if r["n_acks"] >= MIN_ACKS_PER_CONN]
    tot_acks = sum(r["n_acks"] for r in valid)
    tot_win0 = sum(r["n_win0"] for r in valid)
    agg = dict(label=a.label, span_s=tend - t0,
               n_conns=len(results), n_conns_valid=len(valid),
               total_acks=tot_acks, total_win0=tot_win0,
               zw_pct=pct(tot_win0, tot_acks),
               conn_zw_pct=[r["zw_pct"] for r in valid],
               median_conn_zw_pct=median([r["zw_pct"] for r in valid]),
               conns=results)

    print("=== ZW_METRICS label=%s pkts=%d span=%.3f s conns=%d (valid=%d) ===" %
          (a.label or os.path.basename(a.pcaps[0]), len(pkts), tend - t0, len(results), len(valid)))
    print("cliport  acks   win0   zw%%   pure  pwin0  pzw%%  finack  trans  data   payMB  dur_s  Mbps   win_hist")
    for r in results:
        print("%-7s %6d %6d %6.2f %6d %6d %6.2f %6d %6d %6d %8.2f %6.3f %8.2f  %s" %
              (r["cliport"], r["n_acks"], r["n_win0"], r["zw_pct"],
               r["n_pure"], r["n_pure_win0"], r["zw_pct_pure"], r["n_finack"],
               r["win_transitions"], r["n_data"], r["pay_bytes"] / 1e6, r["life_s"],
               r["rate_mbps"], hist_line(collections.Counter(r["peer_win_hist"]))))
    print("--- aggregate ---")
    print("ZW_AGG label=%s acks=%d win0=%d zw_pct=%.3f median_conn_zw_pct=%s valid_conns=%d" %
          (a.label, tot_acks, tot_win0, agg["zw_pct"],
           ("%.3f" % agg["median_conn_zw_pct"]) if agg["median_conn_zw_pct"] is not None else "-",
           len(valid)))
    print("ZW_CONN_LIST " + " ".join("%s:%.2f(%d/%d)" %
          (r["cliport"], r["zw_pct"], r["n_win0"], r["n_acks"]) for r in valid))
    agg_hist = collections.Counter()
    for r in valid:
        agg_hist.update(r["peer_win_hist"])
    print("PEER_WIN_TOTAL_HIST(bytes): %s" % hist_line(agg_hist, top=12))

    if a.json:
        with open(a.json, "w") as f:
            json.dump(agg, f, indent=1)
        print("JSON_WRITTEN %s" % a.json)
    if a.acks_csv:
        with open(a.acks_csv, "w") as f:
            f.write("# ts_rel,cliport,win,flags,seq,ack,csv_sampled_flag\n")
            for row in csv_rows:
                f.write("%.9f,%d,%d,0x%02x,%u,%u,%d\n" % row)
        print("ACKS_CSV_WRITTEN %s rows=%d (sampled rows carry flag=1)" % (a.acks_csv, len(csv_rows)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
