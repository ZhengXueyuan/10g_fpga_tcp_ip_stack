#!/usr/bin/env python3
"""probe_metrics.py -- p9_basin_probe_20261017 pcap derived metrics.

Implements the metric definitions pinned in the design doc
(p9_basin_probe_design_20261017/README_FOR_TL.md sec.4.3):

  * crawl      : per-conn median unique rate <= 5 Mbps AND same-window dW55/dt >= 20/s
  * held%      : data segments whose covering ACK appears only AFTER a replay of the
                 same seq (dedup by unique seq; first transmission is the unit)
  * burst%     : adjacent data-segment pairs with gap < 2 us / all adjacent pairs
  * first segs : # data segments sent before the first ACK that covers the FIRST segment
  * peer window: histogram of the win field on P2B ACKs (bytes; MSS = 1460)
  * board win  : histogram of the win field on B2P data segments
  * freeze     : last data time vs next connection SYN; last ACK win; last seq retx count

Parses the 'ctl' pcap flavour (full 'tcp port 8080', snaplen 128).  Handles multi-file
rings (pcap0..pcapN) and both endiannesses.  No external deps.

Usage:
  python probe_metrics.py <pcap...> --label TAG [--json OUT.json] [--port 8080]
"""
import argparse
import bisect
import collections
import json
import os
import struct
import sys

M32 = 1 << 32
MSS = 1460


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


def covers(ack, end_seq):
    return ((ack - end_seq) & 0xFFFFFFFF) < 0x80000000


def pct(x, n):
    return (100.0 * x / n) if n else 0.0


def median(xs):
    xs = sorted(xs)
    n = len(xs)
    if not n:
        return None
    return xs[n // 2] if n % 2 else 0.5 * (xs[n // 2 - 1] + xs[n // 2])


def hist_line(counter, top=8):
    tot = sum(counter.values())
    items = sorted(counter.items(), key=lambda kv: -kv[1])[:top]
    return " ".join("%d:%d(%.1f%%)" % (k, v, pct(v, tot)) for k, v in items)


def analyze_conn(cp, ps):
    ps.sort(key=lambda x: x["ts"])
    syns = [p for p in ps if p["dir"] == "P2B" and (p["flags"] & 0x02) and not (p["flags"] & 0x10)]
    syn = syns[0] if syns else None
    synack = next((p for p in ps if p["dir"] == "B2P" and (p["flags"] & 0x12) == 0x12), None)
    data = [p for p in ps if p["dir"] == "B2P" and p["pay"] > 0]
    acks = [p for p in ps if p["dir"] == "P2B" and (p["flags"] & 0x10) and p["pay"] == 0]
    r = dict(cliport=cp, n_pkts=len(ps), has_syn=syn is not None,
             t_syn=(syn["ts"] if syn else None),
             syn_win=(syn["win"] if syn else None),
             synack_win=(synack["win"] if synack else None),
             n_data=len(data), n_ack=len(acks))
    if not data:
        r["no_data"] = True
        return r
    # ---- per-connection rates -------------------------------------------------
    pay_bytes = sum(p["pay"] for p in data)
    d1 = data[0]
    life = data[-1]["ts"] - d1["ts"]
    # unique-byte coverage (dedupe by 1460-aligned seq slots, as in G-round shapes.py)
    ini = d1["seq"]
    seen = set()
    for p in data:
        s0 = (p["seq"] - ini) & 0xFFFFFFFF
        for off in range(0, p["pay"], MSS):
            seen.add(s0 + off)
    uniq = len(seen) * MSS
    r.update(pay_bytes=pay_bytes, uniq_bytes=uniq, life_s=life,
             dup_ratio=(1.0 - uniq / pay_bytes) if pay_bytes else None,
             rate_mbps=(pay_bytes * 8 / 1e6 / life) if life > 0 else 0.0,
             uniq_mbps=(uniq * 8 / 1e6 / life) if life > 0 else 0.0,
             first1s_mbps=_first_window_mbps(data, d1["ts"], 1.0))
    # ---- burst% : adjacent transmissions, gap < 2us ---------------------------
    gaps = [(b["ts"] - a["ts"]) for a, b in zip(data, data[1:])]
    n_lt2 = sum(1 for g in gaps if g < 2e-6)
    r.update(n_gaps=len(gaps), n_gap_lt2us=n_lt2, burst_pct=pct(n_lt2, len(gaps)),
             gap_med_us=(median(gaps) * 1e6 if gaps else None),
             gap_p10_us=(sorted(gaps)[int(len(gaps) * 0.1)] * 1e6 if gaps else None),
             gap_p90_us=(sorted(gaps)[int(len(gaps) * 0.9)] * 1e6 if gaps else None))
    # ---- O(log n) coverage lookup -------------------------------------------
    # seq/ack are unwrapped relative to the first data seq (per-connection payload
    # is far below 2^31), then a non-decreasing prefix-max of ACK values + bisect
    # gives the FIRST covering ACK in time.  (Replaces the old O(n^2) scan.)
    def rel(x):
        return (x - ini) & 0xFFFFFFFF

    ack_ts = [a["ts"] for a in acks]
    ack_rel = [rel(a["ack"]) for a in acks]
    prefix_max = []
    pm = -1
    for v in ack_rel:
        pm = v if v > pm else pm
        prefix_max.append(pm)

    def first_cover(t, end_rel):
        i0 = bisect.bisect_left(ack_ts, t)
        if i0 >= len(ack_ts):
            return None
        j = bisect.bisect_left(prefix_max, end_rel, i0)
        if j >= len(ack_ts):
            return None
        return acks[j]

    # ---- first-segment count --------------------------------------------------
    # first ACK (P2B) that covers the end of the FIRST data segment
    end0 = rel(d1["seq"] + d1["pay"])
    first_cov = first_cover(d1["ts"], end0)
    if first_cov is not None:
        n_first = sum(1 for p in data if p["ts"] < first_cov["ts"])
        r["first_seg_count"] = n_first
        r["first_seg_note"] = "counted_before_first_covering_ack"
        r["t_first_cov_d1_ms"] = (first_cov["ts"] - d1["ts"]) * 1e3
    else:
        r["first_seg_count"] = len(data)
        r["first_seg_note"] = "never_covered__all_segments"
        r["t_first_cov_d1_ms"] = None
    # ---- held% : covering ACK only after a same-seq replay --------------------
    # Build first-tx and replay times per unique seq; then first covering ACK time.
    first_tx = {}
    replay_ts = {}
    for p in data:
        s = p["seq"]
        if s not in first_tx:
            first_tx[s] = p
        else:
            # replay: keep the EARLIEST replay time per seq
            if s not in replay_ts:
                replay_ts[s] = p["ts"]
    n_held = n_cov = n_never = 0
    held_delays = []
    replay_cov_delays = []
    for s, p in first_tx.items():
        cov = first_cover(p["ts"], rel(s + p["pay"]))
        if cov is None:
            n_never += 1
            continue
        n_cov += 1
        if s in replay_ts and cov["ts"] > replay_ts[s]:
            n_held += 1
            held_delays.append((cov["ts"] - p["ts"]) * 1e3)
            replay_cov_delays.append((cov["ts"] - replay_ts[s]) * 1e3)
    r.update(n_uniq_seq=len(first_tx), n_covered=n_cov, n_never_covered=n_never,
             n_held=n_held, held_pct=pct(n_held, n_cov) if n_cov else 0.0,
             # anchor-compatible basis (design doc G4b anchor = 37.4%):
             # held_unique / all data TRANSMISSIONS (numerically == dup ratio here)
             held_pct_tx=pct(n_held, len(data)),
             held_pct_all=pct(n_held, len(first_tx)),
             held_delay_med_ms=(median(held_delays) if held_delays else None),
             replay_cover_med_ms=(median(replay_cov_delays) if replay_cov_delays else None))
    # ---- window histograms ----------------------------------------------------
    peer_win = collections.Counter(p["win"] for p in acks)
    board_win = collections.Counter(p["win"] for p in data)
    r["peer_win_hist"] = dict(peer_win)
    r["board_win_hist"] = dict(board_win)
    r["peer_win_mss_hist"] = {k: v for k, v in peer_win.items()}
    r["peer_win_ge8mss_accepted"] = sum(v for k, v in peer_win.items() if k >= 8 * MSS)
    r["peer_win_ge8mss_pct"] = pct(r["peer_win_ge8mss_accepted"], sum(peer_win.values()))
    # ---- freeze witnesses -----------------------------------------------------
    last_d = data[-1]
    last_seq = last_d["seq"]
    n_retx_last = sum(1 for p in data if p["seq"] == last_seq) - 1
    acks_before_last = [p for p in acks if p["ts"] <= last_d["ts"]]
    r.update(last_data_t=last_d["ts"], last_seq=last_seq, last_seq_retx=n_retx_last,
             last_ack_win=(acks_before_last[-1]["win"] if acks_before_last else None),
             last_ack_t=(acks_before_last[-1]["ts"] if acks_before_last else None))
    return r


def _first_window_mbps(data, t0, dur):
    w = [p for p in data if p["ts"] - t0 <= dur]
    if not w:
        return 0.0
    span = max(w[-1]["ts"] - t0, 1e-9)
    return sum(p["pay"] for p in w) * 8 / 1e6 / span


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pcaps", nargs="+")
    ap.add_argument("--label", default="")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--board", default="192.168.100.2")
    ap.add_argument("--peer", default="192.168.100.100")
    ap.add_argument("--json", default=None)
    ap.add_argument("--quiet", action="store_true")
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
        return
    pkts.sort(key=lambda x: x["ts"])
    t0 = pkts[0]["ts"]
    tend = pkts[-1]["ts"]

    conns = collections.defaultdict(list)
    for p in pkts:
        cp = p["sport"] if p["dir"] == "P2B" else p["dport"]
        conns[cp].append(p)

    results = [analyze_conn(cp, ps) for cp, ps in sorted(conns.items(),
                                                         key=lambda kv: kv[1][0]["ts"])]

    # next-SYN gap for freeze: the next SYN (any connection) AFTER this conn's last data
    syn_times = sorted(r["t_syn"] for r in results if r.get("t_syn"))
    for r in results:
        if r.get("no_data") or not syn_times or not r.get("last_data_t"):
            r["has_next_syn"] = False
            continue
        nxt = [t for t in syn_times if t > r["last_data_t"]]
        if nxt:
            r["next_syn_gap_ms"] = (nxt[0] - r["last_data_t"]) * 1e3
            r["next_syn_t"] = nxt[0]
            r["has_next_syn"] = True
        else:
            r["has_next_syn"] = False

    hdr = ("%-7s %6s %9s %8s %9s %8s %8s %8s %8s %9s %9s %7s %6s" %
           ("cliport", "pkts", "t_syn_ms", "data", "payMB", "dur_s", "Mbps", "uniqMb",
            "burst%", "held%", "first_seg", "peerw", "bwin"))
    print("=== PROBE_METRICS label=%s pkts=%d span=%.3f s ===" % (a.label or os.path.basename(a.pcaps[0]), len(pkts), tend - t0))
    if not a.quiet:
        print(hdr)
    for r in results:
        if r.get("no_data"):
            print("%-7s %6d %9s %8s %9s %8s %8s %8s %8s %9s %9s %7s %6s  (no data)" %
                  (r["cliport"], r["n_pkts"],
                   ("%.1f" % ((r["t_syn"] - t0) * 1e3)) if r.get("t_syn") else "-",
                   "-", "-", "-", "-", "-", "-", "-", "-",
                   r.get("synack_win", "-"), "-"))
            continue
        pw = ""
        if r.get("peer_win_hist"):
            pw = "/".join(str(k) for k in sorted(r["peer_win_hist"], key=lambda k: -r["peer_win_hist"][k])[:2])
        bw = ""
        if r.get("board_win_hist"):
            bw = "/".join(str(k) for k in sorted(r["board_win_hist"], key=lambda k: -r["board_win_hist"][k])[:2])
        if not a.quiet:
            print("%-7s %6d %9.1f %8d %9.2f %8.3f %8.2f %8.2f %8.1f %9.1f %9d %7s %6s" %
                  (r["cliport"], r["n_pkts"], (r["t_syn"] - t0) * 1e3 if r["t_syn"] else -1,
                   r["n_data"], r["pay_bytes"] / 1e6, r["life_s"], r["rate_mbps"], r["uniq_mbps"],
                   r["burst_pct"], r["held_pct"], r["first_seg_count"], pw or "-", bw or "-"))

    print()
    print("--- per-conn detail ---")
    for r in results:
        if r.get("no_data"):
            print("CONN %s: no data (synack_win=%s)" % (r["cliport"], r.get("synack_win")))
            continue
        print("CONN %s: data=%d uniq_seq=%d pay=%dB uniq=%dB dur=%.3fs rate=%.2fMbps uniq=%.2fMbps dup=%.3f" %
              (r["cliport"], r["n_data"], r["n_uniq_seq"], r["pay_bytes"], r["uniq_bytes"],
               r["life_s"], r["rate_mbps"], r["uniq_mbps"], r["dup_ratio"] or 0.0))
        print("   burst: pairs=%d <2us=%d (%.1f%%) gap_med=%.1fus p10=%.1f p90=%.1f" %
              (r["n_gaps"], r["n_gap_lt2us"], r["burst_pct"],
               r["gap_med_us"] or 0, r["gap_p10_us"] or 0, r["gap_p90_us"] or 0))
        print("   held: covered=%d never=%d held=%d held%%(of covered)=%.1f held%%(of all)=%.1f "
              "held%%(G-anchor basis: /transmissions)=%.1f delay(first_tx->cover)=%.2fms replay->cover=%.2fms" %
              (r["n_covered"], r["n_never_covered"], r["n_held"], r["held_pct"], r["held_pct_all"],
               r["held_pct_tx"], r["held_delay_med_ms"] or 0, r["replay_cover_med_ms"] or 0))
        print("   first_seg_count=%d (%s) t_first_cov_d1=%s ms" %
              (r["first_seg_count"], r["first_seg_note"],
               ("%.3f" % r["t_first_cov_d1_ms"]) if r["t_first_cov_d1_ms"] is not None else "-"))
        print("   peer_win hist(bytes): %s  [>=8MSS: %d (%.1f%%)]  syn_win=%s synack_win=%s" %
              (hist_line(collections.Counter(r["peer_win_hist"])),
               r["peer_win_ge8mss_accepted"], r["peer_win_ge8mss_pct"],
               r.get("syn_win"), r.get("synack_win")))
        print("   board_win hist(bytes): %s" % hist_line(collections.Counter(r["board_win_hist"])))
        print("   last: seq=%d retx_of_last=%d last_data_t=%.3f last_ack_win=%s next_syn_gap=%s ms" %
              (r["last_seq"], r["last_seq_retx"], r["last_data_t"] - t0,
               r["last_ack_win"],
               ("%.2f" % r["next_syn_gap_ms"]) if r.get("has_next_syn") else "none"))

    # aggregate
    with_data = [r for r in results if not r.get("no_data")]
    if with_data:
        tot = sum(r["pay_bytes"] for r in with_data)
        print()
        print("--- aggregate ---")
        print("conns=%d (with data=%d) totalB2P=%dB span=%.3fs agg=%.3f Mbps" %
              (len(results), len(with_data), tot, tend - t0, tot * 8 / 1e6 / max(tend - t0, 1e-9)))
        print("rates: " + " ".join("%s=%.2f" % (r["cliport"], r["rate_mbps"]) for r in with_data))
        n_fast = sum(1 for r in with_data if r["uniq_mbps"] >= 100)
        n_crawl = sum(1 for r in with_data if r["uniq_mbps"] <= 5)
        print("VERDICT-READ (conns with data=%d): fast(uniq>=100Mbps)=%d crawl(uniq<=5Mbps)=%d mid=%d" %
              (len(with_data), n_fast, n_crawl, len(with_data) - n_fast - n_crawl))
        print("held%%: " + " ".join("%s=%.1f" % (r["cliport"], r["held_pct"]) for r in with_data))
        print("burst%%: " + " ".join("%s=%.1f" % (r["cliport"], r["burst_pct"]) for r in with_data))
        print("first_seg: " + " ".join("%s=%d" % (r["cliport"], r["first_seg_count"]) for r in with_data))
        # aggregate peer win hist
        agg = collections.Counter()
        for r in with_data:
            agg.update(r["peer_win_hist"])
        print("peer_win_total_hist(bytes): %s" % hist_line(agg, top=12))

    if a.json:
        ser = []
        for r in results:
            rr = dict(r)
            ser.append(rr)
        with open(a.json, "w") as f:
            json.dump(dict(label=a.label, span=tend - t0, conns=ser), f, indent=1)
        print("JSON_WRITTEN %s" % a.json)


if __name__ == "__main__":
    main()
