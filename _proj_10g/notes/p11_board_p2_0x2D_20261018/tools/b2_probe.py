#!/usr/bin/env python3
# b2_probe.py -- P11 P2 B-2 minimal TCP client (connect / short data / two 1-byte probes)
import socket, sys, time
host, port, mode = sys.argv[1], int(sys.argv[2]), sys.argv[3]
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.settimeout(6.0)
t0 = time.time()
try:
    s.connect((host, port))
except Exception as e:
    print("CONNECT_FAIL %r" % (e,)); sys.exit(2)
print("CONNECT_OK local=%s:%d remote=%s:%d ms=%.1f" %
      (s.getsockname()[0], s.getsockname()[1], host, port, (time.time() - t0) * 1000))
if mode == "conn1":
    s.sendall(b"HELLO1")
    time.sleep(0.3)
    s.shutdown(socket.SHUT_WR)   # FIN
    print("SHUT_WR_FIN")
    time.sleep(0.5)
    s.close()
    print("CLOSED")
elif mode == "hold":
    time.sleep(2.5)
    s.close()
    print("HOLD_CLOSED")
elif mode == "probe":
    time.sleep(0.3)
    s.sendall(b"A")
    print("PROBE1_SENT t=%.3f" % time.time())
    time.sleep(0.4)
    s.sendall(b"B")
    print("PROBE2_SENT t=%.3f" % time.time())
    time.sleep(2.5)              # keep open for ss witness / tcpdump
    s.close()
    print("CLOSED")
else:
    print("BAD_MODE"); sys.exit(3)
