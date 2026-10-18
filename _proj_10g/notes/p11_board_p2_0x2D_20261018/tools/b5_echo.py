#!/usr/bin/env python3
# b5_echo.py -- UDP echo probe for HLS udp_echo (port 8080)
import socket, sys
host, port, msg = sys.argv[1], int(sys.argv[2]), sys.argv[3].encode()
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.settimeout(2.0)
s.sendto(msg, (host, port))
try:
    data, addr = s.recvfrom(4096)
    print("UDP_ECHO_OK from=%s:%d len=%d match=%s data=%r" % (addr[0], addr[1], len(data), data == msg, data[:64]))
except Exception as e:
    print("UDP_ECHO_FAIL %r" % (e,)); sys.exit(2)
