#!/usr/bin/env python3
# p1b_rawsend.py -- send N deterministic Ethernet frames on a named interface (AF_PACKET).
#   usage: p1b_rawsend.py IFACE N PAYLEN [ETHERTYPE] [SRCMAC]
#   frame = dst ff:ff:ff:ff:ff:ff / src (default 02:00:00:00:00:01) / ethertype (default 0x88B5) /
#           payload = byte i & 0xff (i = frame-internal index)
#   content length = 14 + PAYLEN (>60 to stay above the 64B short-frame threshold)
#   The NIC hardware appends the FCS; the board's ch0 mac_rx_10g strips it => per good frame
#   W80 (ch0_rx_bytes) grows by the CONTENT length, W79 by 1 (if FCS is good).
#   Prints SENT_* lines for the peer-side witness.
import socket, struct, sys, time

def main():
    if len(sys.argv) < 4:
        print("usage: p1b_rawsend.py IFACE N PAYLEN [ETHERTYPE] [SRCMAC]"); return 2
    iface = sys.argv[1]
    n = int(sys.argv[2])
    paylen = int(sys.argv[3])
    etype = int(sys.argv[4], 0) if len(sys.argv) > 4 else 0x88B5
    srcmac = sys.argv[5] if len(sys.argv) > 5 else "02:00:00:00:00:01"
    src = bytes(int(x, 16) for x in srcmac.split(":"))
    dst = b"\xff" * 6
    pay = bytes(i & 0xFF for i in range(paylen))
    frame = dst + src + struct.pack("!H", etype) + pay
    s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.htons(0x0003))
    s.bind((iface, 0))
    t0 = time.time()
    sent = 0
    err = 0
    for _ in range(n):
        try:
            sent += s.send(frame)
        except OSError as e:
            err += 1
            if err <= 5:
                print("SEND_ERR %s" % e)
    dt = time.time() - t0
    print("SENT_OK iface=%s n=%d sent=%d err=%d content_len=%d wire_len=%d ethertype=0x%04x dt=%.6f"
          % (iface, n, sent, err, len(frame), len(frame) + 4, etype, dt))
    return 0

if __name__ == "__main__":
    sys.exit(main())
