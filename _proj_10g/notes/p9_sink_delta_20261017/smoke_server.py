#!/usr/bin/env python3
"""smoke_server.py -- loopback smoke server for the sink-delta switches (BOARD-FREE).

Purpose: give the three new p7b_tcp_sink switches a board-free smoking test
(127.0.0.1 only, no board, no NIC reconfiguration):
  --abort-rst          -> this server tells RST from FIN by the recv() outcome
                          (b'' = FIN, ConnectionResetError = RST)
  --local-port N       -> this server prints the peer source port of every connection
                          (same local port across connections = reuse entry works)
  --reconnect-delay-ms -> this server timestamps accept/close per connection; the gap
                          between close(i) and accept(i+1) is the measured delay

Semantics (same pattern stream as p7b_fake_board.py, which the existing gates use):
  * accept N connections sequentially; per connection immediately send BYTES bytes of the
    xorshift64 pattern (SEED, take-then-advance, offset 0), then DO NOT close first:
    stay in recv() and let the PEER's close decide the close kind.
  * close_kind values: fin | rst | timeout | data:<n> | err:<e>

Output (machine readable, one line each; stdout, flushed):
  SMOKE_LISTEN host=... port=... bytes=... conns=...
  SMOKE_CONN i=0 peer_port=34567 t_accept=... t_close=... gap_since_prev_s=... close_kind=fin sent=65536
  SMOKE_DONE conns=N

Usage:  python3 smoke_server.py --listen 127.0.0.1:20201 --conns 2 --bytes 65536
"""
import argparse
import socket
import sys
import time

SEED = 0x9E3779B97F4A7C15
M64 = (1 << 64) - 1


def xs_next(s):
    s ^= (s << 13) & M64
    s ^= s >> 7
    s ^= (s << 17) & M64
    return s & M64


def gen(n):
    s = SEED
    out = bytearray(n)
    for i in range(n):
        out[i] = (s >> 24) & 0xFF
        s = xs_next(s)
    return bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--listen", default="127.0.0.1:20200")
    ap.add_argument("--conns", type=int, default=2)
    ap.add_argument("--bytes", type=int, default=65536)
    ap.add_argument("--close-wait", type=float, default=10.0)
    ap.add_argument("--accept-timeout", type=float, default=60.0)
    a = ap.parse_args()
    host, port = a.listen.rsplit(":", 1)
    port = int(port)
    blk = gen(a.bytes)
    ls = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    ls.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    ls.bind((host, port))
    ls.listen(4)
    print("SMOKE_LISTEN host=%s port=%d bytes=%d conns=%d" % (host, port, a.bytes, a.conns), flush=True)
    prev_close = None
    done = 0
    for i in range(a.conns):
        ls.settimeout(a.accept_timeout)
        try:
            conn, peer = ls.accept()
        except socket.timeout:
            print("SMOKE_ACCEPT_TIMEOUT i=%d" % i, flush=True)
            break
        t_accept = time.monotonic()
        gap = "" if prev_close is None else "%.6f" % (t_accept - prev_close)
        try:
            conn.sendall(blk)
            sent = len(blk)
        except OSError as e:
            print("SMOKE_SEND_ERR i=%d %s" % (i, e), flush=True)
            sent = -1
        kind = "?"
        try:
            conn.settimeout(a.close_wait)
            d = conn.recv(65536)
            kind = "fin" if d == b"" else ("data:%d" % len(d))
        except ConnectionResetError:
            kind = "rst"
        except socket.timeout:
            kind = "timeout"
        except OSError as e:
            kind = "err:%s" % e
        t_close = time.monotonic()
        try:
            conn.close()
        except OSError:
            pass
        prev_close = t_close
        done += 1
        print("SMOKE_CONN i=%d peer_port=%d t_accept=%.6f t_close=%.6f gap_since_prev_s=%s close_kind=%s sent=%d"
              % (i, peer[1], t_accept, t_close, gap, kind, sent), flush=True)
    ls.close()
    print("SMOKE_DONE conns=%d" % done, flush=True)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
