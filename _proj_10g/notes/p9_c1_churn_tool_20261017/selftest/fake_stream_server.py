#!/usr/bin/env python3
"""fake_stream_server.py -- p7b_tcp_churn 回环自测的**轻量服务端**（⛔ 不碰板, 只跑 127.0.0.1）

用法: python3 fake_stream_server.py --port P --seconds S --mode sink|mid|from0 [--conns-max N]
  sink  : accept + 读干, **不发**任何数据        ⇒ 客户端应报 restart@off=na (0 字节)
  mid   : 每条连接发 8 KB **流中段**图案（偏移 = 1234 + 4096*accept序号）
          ⇒ 客户端应报 restart@off=-1（命中候选）并落盘
  from0 : 每条连接发 8 KB **从偏移 0 起**的图案 ⇒ 客户端应报 restart@off=0
自限: --seconds（默认 20）/ --conns-max（默认 500，符合派单"连接数 ≤500"）/ 单进程 poll / 不写文件。

xorshift64 语义 = 与 rtl/app_pattern.v 及 p7b_pattern.h **逐字同款**（本文件是**独立第三实现**，
用于离线复算 —— 启动时用 p7b_pattern.h 文档里的手算向量自检，向量不对就 exit 2）。
"""
import argparse
import selectors
import socket
import sys
import time

MASK = (1 << 64) - 1
SEED = 0x9E3779B97F4A7C15
DOC16 = "7F0B02E536A14ED61AB049B856ADD63F"   # p7b_pattern.h 文档向量: offset 0..15


def pattern_base(n):
    """从 SEED 起递推 n 字节（gen_byte = s[31:24]，先取后推进）"""
    out = bytearray(n)
    s = SEED
    for i in range(n):
        out[i] = (s >> 24) & 0xFF
        s ^= (s << 13) & MASK
        s ^= s >> 7
        s ^= (s << 17) & MASK
    return bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--seconds", type=float, default=20.0)
    ap.add_argument("--mode", choices=["sink", "mid", "from0"], default="sink")
    ap.add_argument("--conns-max", type=int, default=500)
    ap.add_argument("--conn-bytes", type=int, default=8192)
    a = ap.parse_args()

    max_off = 1234 + 4096 * max(0, a.conns_max - 1)
    base = pattern_base(max_off + a.conn_bytes + 8)
    if base[:16].hex().upper() != DOC16:          # 独立实现的**自身**判据（错了就别跑）
        print("SRV_FAIL pattern self-check: got=%s want=%s" % (base[:16].hex().upper(), DOC16),
              flush=True)
        return 2

    ls = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    ls.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    ls.bind(("127.0.0.1", a.port))
    ls.listen(256)
    ls.setblocking(False)
    sel = selectors.DefaultSelector()
    sel.register(ls, selectors.EVENT_READ, "listen")
    conns = {}                                    # sock -> [buf, sent]
    n_acc = 0
    t0 = time.time()
    print("SRV_READY port=%d mode=%s seconds=%.1f conns_max=%d conn_bytes=%d pid=%d"
          % (a.port, a.mode, a.seconds, a.conns_max, a.conn_bytes, __import__("os").getpid()),
          flush=True)
    while time.time() - t0 < a.seconds:
        for key, ev in sel.select(timeout=0.05):
            if key.data == "listen":
                try:
                    c, _ = ls.accept()
                except BlockingIOError:
                    continue
                if n_acc >= a.conns_max:
                    c.close()
                    continue
                c.setblocking(False)
                if a.mode == "sink":
                    buf = b""
                elif a.mode == "from0":
                    buf = base[0:a.conn_bytes]
                else:
                    off = 1234 + 4096 * n_acc
                    buf = base[off:off + a.conn_bytes]
                n_acc += 1
                if n_acc % 50 == 0:               # 周期见证（被 kill 也留有增量读数）
                    print("SRV_ACCEPTED n=%d t=%.2f" % (n_acc, time.time() - t0), flush=True)
                conns[c] = [buf, 0]
                sel.register(c, selectors.EVENT_READ | (selectors.EVENT_WRITE if buf else 0), "c")
            else:
                c = key.fileobj
                st = conns.get(c)
                if st is None:
                    continue
                if ev & selectors.EVENT_READ:
                    try:
                        d = c.recv(65536)
                        if not d:
                            try:
                                sel.unregister(c)
                            except Exception:
                                pass
                            c.close()
                            conns.pop(c, None)
                            continue
                    except BlockingIOError:
                        pass
                    except OSError:
                        try:
                            sel.unregister(c)
                        except Exception:
                            pass
                        c.close()
                        conns.pop(c, None)
                        continue
                if (ev & selectors.EVENT_WRITE) and st[1] < len(st[0]):
                    try:
                        n = c.send(st[0][st[1]:])
                        st[1] += n
                    except BlockingIOError:
                        pass
                    except OSError:
                        try:
                            sel.unregister(c)
                        except Exception:
                            pass
                        c.close()
                        conns.pop(c, None)
                        continue
                    if st[1] >= len(st[0]):
                        sel.modify(c, selectors.EVENT_READ, "c")   # 发完就只要可读
    print("SRV_DONE accepted=%d mode=%s wall=%.3f" % (n_acc, a.mode, time.time() - t0), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
