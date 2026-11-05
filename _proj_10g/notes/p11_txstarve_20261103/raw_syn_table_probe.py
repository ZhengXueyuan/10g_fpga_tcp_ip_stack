#!/usr/bin/env python3
# raw_syn_table_probe.py -- 在 nsa 内用原始以太网帧制造半开 TCP 连接，验证 HLS 连接表容量与泄漏
import socket, struct, time, random, sys
IFACE = 'enp1s0f1np1'
SMAC = bytes.fromhex('020000000001')           # 伪造源 MAC，避免内核收到 SYN-ACK 后发 RST
DMAC = bytes.fromhex('000a3501fec0')           # KU5P 板 MAC
SIP = socket.inet_aton('192.168.100.1'); DIP = socket.inet_aton('192.168.100.2')
def csum(b):
    if len(b) % 2: b += b'\0'
    s = sum(struct.unpack('!%dH' % (len(b)//2), b))
    while s >> 16: s = (s & 0xffff) + (s >> 16)
    return (~s) & 0xffff
def frame(sport, dport, seq, flags):
    tcp = struct.pack('!HHIIBBHHH', sport, dport, seq, 0, 5<<4, flags, 65535, 0, 0)
    pseudo = SIP + DIP + struct.pack('!BBH', 0, 6, len(tcp))
    c = csum(pseudo + tcp); tcp = tcp[:16] + struct.pack('!H', c) + tcp[18:]
    ip = struct.pack('!BBHHHBBH4s4s', 0x45, 0, 20+len(tcp), random.randint(0,65535), 0, 64, 6, 0, SIP, DIP)
    ip = ip[:10] + struct.pack('!H', csum(ip)) + ip[12:]
    return DMAC + SMAC + struct.pack('!H', 0x0800) + ip + tcp
tx = socket.socket(socket.AF_PACKET, socket.SOCK_RAW); tx.bind((IFACE, 0))
rx = socket.socket(socket.AF_PACKET, socket.SOCK_RAW); rx.bind((IFACE, 0)); rx.setblocking(False)
def drain_synack(sports):
    n = 0
    while True:
        try: f = rx.recv(2048)
        except BlockingIOError: break
        if len(f) < 54 or f[0:6] != DMAC or f[12:14] != b'\x08\x00': continue
        if f[23] != 6: continue
        ihl = (f[14] & 0xf) * 4; t = f[14+ihl:]
        if len(t) < 20: continue
        sp, dp = struct.unpack('!HH', t[0:4]); fl = t[13]
        if sp == 8080 and dp in sports and (fl & 0x12) == 0x12: n += 1
    return n
def normal_connect(timeout=2.0):
    s = socket.socket(); s.settimeout(timeout)
    try: s.connect(('192.168.100.2', 8080)); return 'OK'
    except Exception as e: return type(e).__name__
    finally: s.close()
def main():
    N = int(sys.argv[1]) if len(sys.argv) > 1 else 8
    base = 40000
    print('BASE_CONNECT', normal_connect())
    seqs = {}
    for i in range(N):
        sport = base + i; seq = random.randint(1, 0xffffff); seqs[sport] = seq
        tx.send(frame(sport, 8080, seq, 0x02))
        time.sleep(0.1)
    time.sleep(0.5)
    print('RAW_SYN_SENT', N)
    print('SYNACK_SEEN', drain_synack(set(seqs)))
    print('CONNECT_AFTER_FILL', normal_connect())
    # 对第一条半开连接发 RST，释放一个槽
    sport = base; seq = seqs[sport]
    tx.send(frame(sport, 8080, seq + 1, 0x04)); time.sleep(0.3)
    print('RST_SENT', sport)
    print('CONNECT_AFTER_RST', normal_connect())
    time.sleep(0.2); print('SYNACK_AFTER_RST', drain_synack(set(seqs)))

if __name__ == "__main__":
    main()
