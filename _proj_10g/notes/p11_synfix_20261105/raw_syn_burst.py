#!/usr/bin/env python3
# raw_syn_burst.py -- 只发 N 个原始 SYN（不重传/不完成握手），用于测量 HLS 空闲槽数。
#   依赖 raw_syn_table_probe.py 的帧构造（同目录，import 有 __main__ 守卫）。
#   RST 抑制由外层 shell 的 iptables 完成；SYN-ACK 计数以板内 W7 为准（本脚本尽力抓包）。
import importlib.util, socket, sys, time
spec = importlib.util.spec_from_file_location('m', '/tmp/raw_syn_table_probe.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
N = int(sys.argv[1]) if len(sys.argv) > 1 else 8
base = int(sys.argv[2]) if len(sys.argv) > 2 else 41000
tx = socket.socket(socket.AF_PACKET, socket.SOCK_RAW); tx.bind((m.IFACE, 0))
rx = socket.socket(socket.AF_PACKET, socket.SOCK_RAW); rx.bind((m.IFACE, 0)); rx.setblocking(False)
sports = set()
for i in range(N):
    sp = base + i; sports.add(sp)
    tx.send(m.frame(sp, 8080, 0x200000 + i, 0x02))
    time.sleep(0.15)
time.sleep(0.4)
print('RAW_BURST_SENT', N)
print('SYNACK_SEEN', m.drain_synack(sports))
