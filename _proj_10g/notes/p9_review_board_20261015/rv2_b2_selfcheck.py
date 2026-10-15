#!/usr/bin/env python3
# RV2: 独立复算 B2 的 SELFCHECK 配方 (D/d_mod/old/new/分歧) + 从 pcap 验证注入帧 IP/TCP 校验和
# 口径: old = 绝对比较 (seq < rcv, 无符号); new = d_mod>>31; 目标向 = old==0 且 new==1。
import os, re, sys, struct
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rv2_pcap_lib import read_pcap, parse_eth_tcp

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "p9_board_rfcseq_20261015")
RUNS = ["P27", "P27R", "N25", "P26", "P26b", "N25b", "P27F"]

def csum(data):
    if len(data) % 2:
        data += b"\x00"
    s = 0
    for i in range(0, len(data), 2):
        s += (data[i] << 8) + data[i+1]
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF

def main():
    for r in RUNS:
        d = os.path.join(BASE, "runs_" + r)
        for fn in sorted(os.listdir(d)):
            if not fn.startswith("inject_") or fn.endswith(".key.txt"):
                continue
            path = os.path.join(d, fn)
            txt = open(path, encoding="utf-8", errors="replace").read()
            sc = re.findall(r"^SELFCHECK (\S+)\s+seq=0x([0-9A-Fa-f]+) rcv=0x([0-9A-Fa-f]+) D=([+-]?\d+) d_mod=0x([0-9A-Fa-f]+) old=(\d) new=(\d)", txt, re.M)
            if not sc:
                continue
            print("== %s/%s ==" % (r, fn))
            for name, seq_s, rcv_s, D_s, dm_s, old_s, new_s in sc:
                seq = int(seq_s, 16); rcv = int(rcv_s, 16)
                D = seq - rcv                        # 真差 (普通整数)
                d_mod = D & 0xFFFFFFFF
                old = 1 if seq < rcv else 0
                new = d_mod >> 31
                div = (old == 0 and new == 1)
                in_equiv = (-(1 << 31)) <= D <= ((1 << 31) - 1)
                ok = (D == int(D_s) and d_mod == int(dm_s, 16) and old == int(old_s) and new == int(new_s))
                print("   %-30s seq=0x%08X rcv=0x%08X 重算 D=%+d d_mod=0x%08X old=%d new=%d 分歧=%s 等价域=%s | 与日志一致=%s" % (
                    name, seq, rcv, D, d_mod, old, new, div, in_equiv, ok))
            # 注入帧校验和核 (从 pcap 取帧)
            pcaps = sorted(f for f in os.listdir(d) if f.startswith("main_") and f.endswith(".pcap"))
            att = int(re.search(r"inject_(\d+)", fn).group(1))
            pk = os.path.join(d, "main_%d.pcap" % att)
            if not os.path.exists(pk):
                print("   (无 main_%d.pcap, 跳校验和核)" % att); continue
            link, pkts = read_pcap(pk)
            frames = {}
            for t, fr, orig in pkts:
                p = parse_eth_tcp(fr)
                if p and p["src"] == "192.168.100.100" and p["dst"] == "192.168.100.2":
                    frames[(p["seq"], p["plen"])] = fr
            injlines = re.findall(r"^INJECT kind=(\S+) seq=0x([0-9A-Fa-f]+) len=(\d+)", txt, re.M)
            for kind, seq_s, len_s in injlines:
                key = (int(seq_s, 16), int(len_s))
                fr = frames.get(key)
                if fr is None:
                    print("   [csum] %-30s 注入帧不在 pcap (跳)" % kind); continue
                # IP 头校验和
                ip = fr[14:]
                ipc = struct.unpack(">H", ip[10:12])[0]
                ipz = ip[:10] + b"\x00\x00" + ip[12:20]
                ip_calc = csum(ipz)
                # TCP 校验和 (载荷全文按注入器公式重建)
                plen = key[1]
                payload = bytes([0xAA + (i % 16) for i in range(plen)])
                ihl = (ip[0] & 0xF) * 4
                tcp = ip[ihl:ihl+20]
                pseudo = ip[12:16] + ip[16:20] + struct.pack(">BBH", 0, 6, 20 + plen)
                tc = struct.unpack(">H", tcp[16:18])[0]
                tcpz = tcp[:16] + b"\x00\x00" + tcp[18:]
                tcp_calc = csum(pseudo + tcpz + payload)
                print("   [csum] %-30s IP: 帧内=0x%04X 重算=0x%04X %s | TCP: 帧内=0x%04X 重算=0x%04X %s" % (
                    kind, ipc, ip_calc, "OK" if ipc == ip_calc else "MISMATCH",
                    tc, tcp_calc, "OK" if tc == tcp_calc else "MISMATCH"))
        print()

if __name__ == "__main__":
    main()
