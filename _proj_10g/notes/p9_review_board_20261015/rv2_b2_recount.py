#!/usr/bin/env python3
# RV2: B2 独立复算 —— 不读被审件的 analyze_*.txt / inject 嗅探器结论,
#     直接从 runs_*/main_*.pcap + inject_*.txt 的 INJECT 行(只取时刻/seq/ack) 复算。
# 输出: 每条注入之后 [0-2ms]/[0-100ms]/[0-600ms] 板侧帧清单(含 ack 值), 预窗 ambient 计数,
#       以及全窗板侧 1 字节零窗探针计数。
import sys, os, re, glob
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rv2_pcap_lib import read_pcap, parse_eth_tcp, flagstr

BOARD = "192.168.100.2"
PEER  = "192.168.100.100"

def load_inject(path):
    """从 inject_*.txt 只取 INJECT 行: 时刻 + seq + len + ack。"""
    injs = []
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"INJECT kind=(\S+) seq=0x([0-9A-Fa-f]+) len=(\d+) ack=0x([0-9A-Fa-f]+).*t=([0-9.]+)", line)
        if m:
            injs.append(dict(kind=m.group(1), seq=int(m.group(2), 16),
                             plen=int(m.group(3)), ack=int(m.group(4), 16),
                             t=float(m.group(5))))
    return injs

def analyze(tagdir, pcapname, injectname):
    pk = os.path.join(tagdir, pcapname)
    ij = os.path.join(tagdir, injectname)
    if not (os.path.exists(pk) and os.path.exists(ij)):
        print("SKIP %s/%s" % (tagdir, pcapname)); return
    link, pkts = read_pcap(pk)
    injs = load_inject(ij)
    print("=== %s | %s: %d 帧, 窗[%.6f,%.6f] | %d 条 INJECT ===" % (
        os.path.basename(tagdir), pcapname, len(pkts), pkts[0][0], pkts[-1][0], len(injs)))
    parsed = []
    for t, fr, orig in pkts:
        p = parse_eth_tcp(fr)
        p["t"] = t
        parsed.append(p)
    # 每条注入
    for e in injs:
        t0 = e["t"]
        # 该注入帧本身 (peer->board, seq/len 匹配 且 ident 标记段)
        hits = [p for p in parsed if p and p["src"] == PEER and p["dst"] == BOARD
                and p["seq"] == e["seq"] and p["plen"] == e["plen"]
                and (t0 - 0.2) <= p["t"] <= (t0 + 0.2)]
        mark = ["0x%04X" % h["ident"] for h in hits]
        print("  INJECT %-30s t=%.6f seq=0x%08X len=%d ack=0x%08X | 注入帧在 pcap:%d 帧 ident=%s" %
              (e["kind"], t0, e["seq"], e["plen"], e["ack"], len(hits), ",".join(mark)))
        # 板侧帧分窗
        for wname, wt in (("0-2ms", 0.002), ("0-100ms", 0.1), ("0-600ms", 0.6)):
            fs = [p for p in parsed if p and p["src"] == BOARD and p["sport"] == 8080
                  and t0 < p["t"] <= t0 + wt]
            print("    [%s] board_frames=%d" % (wname, len(fs)))
            for p in fs[:6]:
                print("       t=%.6f(rel +%.3f ms) seq=%u ack=%u win=%d len=%d flags=%s" %
                      (p["t"], (p["t"] - t0) * 1000, p["seq"], p["ack"], p["win"], p["plen"], flagstr(p["flags"])))
        # 注入前 0.85s 预窗 ambient (板侧)
        pre = [p for p in parsed if p and p["src"] == BOARD and p["sport"] == 8080
               and t0 - 0.85 < p["t"] <= t0]
        print("    [pre 0.85s] board_frames=%d" % len(pre))
    # 全窗: 板侧 1 字节零窗探针 (seq=?, len=1)
    probes = [p for p in parsed if p and p["src"] == BOARD and p["sport"] == 8080 and p["plen"] == 1]
    print("  全窗板侧 len==1 帧: %d" % len(probes))
    for p in probes[:10]:
        print("     t=%.6f seq=%u ack=%u win=%d flags=%s" % (p["t"], p["seq"], p["ack"], p["win"], flagstr(p["flags"])))
    # 全窗: peer->board 帧里带 FIN/RST 的
    ctl = [p for p in parsed if p and p["src"] == PEER and (p["flags"] & 0x05)]
    print("  全窗 peer->board FIN/RST 帧: %d" % len(ctl))
    for p in ctl[:10]:
        print("     t=%.6f seq=%u flags=%s len=%d" % (p["t"], p["seq"], flagstr(p["flags"]), p["plen"]))
    print()

if __name__ == "__main__":
    base = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "p9_board_rfcseq_20261015")
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", default=None)
    a = ap.parse_args()
    if a.run:
        runs = [a.run]
    else:
        runs = ["N25", "N25b", "P26", "P26b", "P27", "P27R", "P27F"]
    for r in runs:
        d = os.path.join(base, "runs_" + r)
        # 找最后一个 attempt 的 pcap
        pcaps = sorted(glob.glob(os.path.join(d, "main_*.pcap")))
        injs = sorted(glob.glob(os.path.join(d, "inject_*.txt")))
        injs = [i for i in injs if not i.endswith(".key.txt")]
        for pk, ij in zip(pcaps, injs):
            analyze(d, os.path.basename(pk), os.path.basename(ij))
