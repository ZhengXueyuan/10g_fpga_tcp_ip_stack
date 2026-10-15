#!/usr/bin/env python3
# RV2: B2 SYNC_CHECK 独立复算 —— 用 syn_*.pcap 的 ISN + inject_*.txt 的 rcv_nxt + src_*.txt 的自报 tx
# 目的: 判 "MISMATCH 是嗅探器丢帧" 还是 "对端真的发得比板收得多"。
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rv2_pcap_lib import read_pcap, parse_eth_tcp

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "p9_board_rfcseq_20261015")
RUNS = ["P27", "P27R", "N25", "P26", "P26b", "N25b", "P27F"]

def syn_isn(path):
    link, pk = read_pcap(path)
    for t, fr, orig in pk:
        p = parse_eth_tcp(fr)
        if p and (p["flags"] & 0x02):
            return p["seq"]
    return None

for r in RUNS:
    d = os.path.join(BASE, "runs_" + r)
    print("== %s ==" % r)
    for fn in sorted(os.listdir(d)):
        if not fn.startswith("inject_") or fn.endswith(".key.txt"):
            continue
        att = int(re.search(r"inject_(\d+)", fn).group(1))
        txt = open(os.path.join(d, fn), encoding="utf-8", errors="replace").read()
        m = re.search(r"DISCOVER lport=\d+ rcv_nxt=(\d+)\(0x[0-9A-Fa-f]+\) peer_snd_nxt=(\d*)", txt)
        if not m:
            continue
        rcvs = re.findall(r"SELFCHECK \S+\s+.*?rcv=0x([0-9A-Fa-f]+)", txt)
        sync = re.search(r"SYNC_CHECK peer_snd-rcv_nxt=(-?\d+) (\w+)", txt)
        isn = syn_isn(os.path.join(d, "syn_%d.pcap" % att))
        srcf = os.path.join(d, "src_%d.txt" % att)
        tx_mb = None
        if os.path.exists(srcf):
            txs = re.findall(r"SRC_T [0-9.]+ tx_MB=([0-9.]+)", open(srcf, encoding="utf-8", errors="replace").read())
            if txs:
                tx_mb = [float(x) for x in txs]
        # 注入用 rcv (SELFCHECK)
        rcv_inj = int(rcvs[0], 16) if rcvs else None
        print("  att=%d ISN=%s (0x%08X) | SELFCHECK rcv=0x%08X | SYNC=%s %s | src tx_MB=%s" % (
            att, isn, isn or 0, rcv_inj or 0,
            sync.group(1) if sync else "-", sync.group(2) if sync else "-", tx_mb))
        if isn is not None and rcv_inj is not None:
            off = (rcv_inj - isn - 1) & 0xFFFFFFFF
            print("     板已接受量 (rcv_nxt - ISN - 1) = %d B = %.3f MiB" % (off, off / 1048576))
            if tx_mb:
                print("     src 末次自报 tx = %.3f MiB = %d B ; 差 (板接受 - src自报) = %+d B" % (
                    tx_mb[-1], int(tx_mb[-1] * 1048576), off - int(tx_mb[-1] * 1048576)))
