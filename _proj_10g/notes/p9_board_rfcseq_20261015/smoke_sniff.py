#!/usr/bin/env python3
# smoke_sniff.py -- 预飞冒烟: 验证 AF_PACKET 双向可见 + 4 元组/rcv_nxt 可发现 (3 s)
import socket, struct, sys, time, collections

IFACE = "enp1s0f1np1"
BOARD = "192.168.100.2"; MY = "192.168.100.100"; PORT = 8080
s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.ntohs(0x0003))
s.bind((IFACE, 0)); s.settimeout(0.2)
t_end = time.time() + 3.0
cnt = collections.Counter(); rcv = None; peersnd = None; lport = None; lastb = None
n = 0
while time.time() < t_end:
    try:
        pkt, addr = s.recvfrom(65536)
    except socket.timeout:
        continue
    n += 1
    if len(pkt) < 54 or pkt[12:14] != b"\x08\x00":
        continue
    ip = pkt[14:]
    if ip[9] != 6:
        continue
    ihl = (ip[0] & 0xF) * 4
    src = ".".join(str(x) for x in ip[12:16]); dst = ".".join(str(x) for x in ip[16:20])
    tcp = ip[ihl:]
    sport, dport, seq, ack, of = struct.unpack(">HHIIH", tcp[:14])
    flags = of & 0x1FF
    plen = struct.unpack(">H", ip[2:4])[0] - ihl - ((of >> 12) & 0xF) * 4
    pkttype = addr[2]   # 0 = HOST(in), 4 = OUTGOING
    if src == BOARD and sport == PORT:
        cnt["board_in"] += 1
        if flags & 0x10:
            rcv = ack if rcv is None else max(rcv, ack)
        lastb = (seq, ack, plen, flags)
    elif dst == BOARD and dport == PORT:
        cnt["peer_out"] += 1
        if lport is None:
            lport = sport
        if plen > 0 and (flags & 0x10):
            peersnd = (seq + plen) & 0xFFFFFFFF if peersnd is None else peersnd
            if peersnd is None or ((seq + plen - peersnd) & 0xFFFFFFFF) < 0x80000000:
                peersnd = (seq + plen) & 0xFFFFFFFF
    cnt["pkttype_%d" % pkttype] += 1
print("SMOKE pkts=%d %s" % (n, dict(cnt)))
print("SMOKE lport=%s rcv_nxt=%s peer_snd=%s last_board=%s" % (lport, rcv, peersnd, lastb))
print("SMOKE_END")
