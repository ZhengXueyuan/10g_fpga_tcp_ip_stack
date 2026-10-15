#!/usr/bin/env python3
# RV2: 决定性检验 —— 在同一 pcap 内, 板侧 ACK 的 ack 值是否超过对端到该时刻为止实际发出的最大字节 (seq+len)?
# 若超过 ⇒ 板 rcv_nxt 相对线上字节有正偏移 (over-ack) ⇒ "板已接受量 > src 自报 tx" 之谜的正解。
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rv2_pcap_lib import read_pcap, parse_eth_tcp

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "p9_board_rfcseq_20261015")

def run(tag, pcapname, lport):
    p = os.path.join(BASE, "runs_" + tag, pcapname)
    link, pk = read_pcap(p)
    # 只看非注入帧 (ident 标记段排除)
    evs = []
    for t, fr, o in pk:
        d = parse_eth_tcp(fr)
        if not d:
            continue
        if 0xA5C0 <= d["ident"] < 0xA600:
            continue
        if d["src"] == "192.168.100.100" and d["sport"] == lport and d["plen"] > 0:
            evs.append((t, "D", d["seq"], d["plen"]))
        elif d["src"] == "192.168.100.2" and d["sport"] == 8080 and d["dport"] == lport and (d["flags"] & 0x10):
            evs.append((t, "A", d["ack"], 0))
    evs.sort(key=lambda z: z[0])
    maxsent = None      # 对端已发最大字节 (seq+len), 按到达序取 max (帧序不乱)
    worst = None
    first_viol = []
    for t, k, v, l in evs:
        if k == "D":
            e = (v + l) & 0xFFFFFFFF
            if maxsent is None or ((e - maxsent) & 0xFFFFFFFF) < 0x80000000:
                maxsent = e
        else:
            if maxsent is not None:
                over = (v - maxsent) & 0xFFFFFFFF
                if over < 0x80000000 and over > 0:
                    first_viol.append((t, v, maxsent, over))
    print("== %s/%s: peer(lport=%d) 数据帧 + 板 ACK 交错共 %d 事件" % (tag, pcapname, lport, len(evs)))
    if not first_viol:
        print("   板 ACK 从未超过对端已发最大字节 (over-ack 违例 = 0)")
    else:
        print("   ⚠ 板 ACK 超过对端已发最大字节的违例 = %d 次; 前 5:" % len(first_viol))
        for t, v, m, o in first_viol[:5]:
            print("      t=%.6f ack=%u (0x%08X) vs 已发 max=%u (0x%08X) over=%d" % (t, v, v, m, m, o))

if __name__ == "__main__":
    run("N25", "main_2.pcap", 43594)
    run("N25b", "main_1.pcap", 43586)
    run("P26", "main_2.pcap", 0)   # lport 待填; 见 RUNS_SUMMARY
