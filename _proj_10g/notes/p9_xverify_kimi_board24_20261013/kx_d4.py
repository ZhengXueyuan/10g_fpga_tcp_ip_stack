#!/usr/bin/env python
# -*- coding: utf-8 -*-
# kx_d4.py — 独立复算 D4 停流链（S3D4/S4D4/S5D4 + 停流探针；自写比较器；不 import 对方 _tools）
import re, os

# ---- 自写 LFSR（与 kx_holes 同一实现；自包含留档）----
SEED = 0x9E3779B97F4A7C15
MASK = (1 << 64) - 1
def xs_next(s):
    s ^= (s << 13) & MASK
    s ^= s >> 7
    s ^= (s << 17) & MASK
    return s
def _mat_gen(): return [xs_next(1 << i) for i in range(64)]
def _mat_apply(cols, x):
    r = 0; i = 0
    while x:
        if x & 1: r ^= cols[i]
        x >>= 1; i += 1
    return r
def _mat_compose(A, B): return [_mat_apply(A, b) for b in B]
def _jump(off):
    M = _mat_gen(); s = SEED; n = off
    while n:
        if n & 1: s = _mat_apply(M, s)
        n >>= 1
        if n: M = _mat_compose(M, M)
    return s
def mir(off, n):
    s = _jump(off)
    out = bytearray(n)
    for i in range(n):
        out[i] = ((s >> 24) & 0xFF) ^ 0xA5
        s = xs_next(s)
    return bytes(out)

BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "p9_board_0x24_20261013")
RUNS = os.path.join(BASE, "runs")

text = open(os.path.join(RUNS, "ARM_D4_CHAIN_20261013_222058.txt"), encoding="utf-8", errors="replace").read()
heads = list(re.finditer(r"(?m)^=== ARM (\S+) K=(\d+) .*?OFF=(\S+) .*?$", text))
print("D4 链窗口:", [h.group(1) for h in heads])

EXP = {  # 报告 §5d 表
    "S3D4": dict(src_bytes=1048584, pc=1048576, taken=1048584, A=8,  B=0),
    "S4D4": dict(src_bytes=1048576, pc=1048576, taken=1048576, A=0,  B=0),
    "S5D4": dict(src_bytes=1048584, pc=1048576, taken=1048584, A=8,  B=0),
}
allok = True
for i, h in enumerate(heads):
    tag = h.group(1)
    body = text[h.end(): heads[i+1].start() if i+1 < len(heads) else len(text)]
    off = int(h.group(3)) if h.group(3).isdigit() else None
    m = re.search(r"OFF_AUTO: W11=0x([0-9a-f]+) => OFF=(\d+)", body)
    off_auto = int(m.group(2)) if m else None
    m = re.search(r"--- 起发端 \(p7b_udp_src, --bytes (\d+)", body); src_bytes = int(m.group(1)) if m else None
    m = re.search(r"MIR_STREAM_ACCT pc=(\d+) taken_bytes=(\d+) dW70=(\d+)", body)
    pc, taken, dw70 = (int(m.group(j)) for j in (1, 2, 3))
    m = re.search(r"式A\(成形器\).*?-> (\d+)\s+band=\[0,32\] closed_a=(\d+)", body); A, ca = (int(m.group(j)) for j in (1, 2))
    m = re.search(r"式B\(镜像/K\).*?-> (\d+)\s+band=\[0,24\] closed_b=(\d+)", body); B, cb = (int(m.group(j)) for j in (1, 2))
    m = re.search(r"MIR_VERIFY rc=(\d+) first_mismatch=(-?\d+)", body); vrc, vfm = (int(m.group(j)) for j in (1, 2))
    m = re.search(r"MIR_STREAM_CFG dev=\S+ bytes=(\d+) chunk=\d+ .*?k_bytes=(\d+)", body)
    k_bytes = int(m.group(2)) if m else 0
    m = re.search(r"MIR_STREAM_DONE pc=(\d+) reads=(\d+) partial=(\d+) nonmul64=(\d+) short=(\d+) ended_early=(\d+) read_error=(\d+)", body)
    done = (int(m.group(j)) for j in range(1, 8))
    K = k_bytes if k_bytes else 1048576
    if off is None:
        off = off_auto  # 头部 OFF=auto ⇒ 以 OFF_AUTO 行为准
    # 独立复算 式A/式B
    A_re = taken - pc
    B_re = K - taken - dw70
    e = EXP[tag]
    ok = (pc == e["pc"] and taken == e["taken"] and A == e["A"] and B == e["B"]
          and A_re == A and B_re == B and ca == 1 and cb == 1 and dw70 == 0
          and vrc == 0 and vfm == -1 and src_bytes == e["src_bytes"] and off == off_auto)
    allok &= ok
    print(f"{tag}: OFF={off} src_bytes={src_bytes} K={K} pc={pc} taken={taken} dW70={dw70} "
          f"式A={A}(复算{A_re},closed_a={ca}) 式B={B}(复算{B_re},closed_b={cb}) VERIFY rc={vrc} fm={vfm} "
          f"DONE pc/reads/partial/nonmul64/short/early/err={list(done)} => {'MATCH' if ok else 'MISMATCH'}")

# 停流探针
sp = open(os.path.join(RUNS, "STOP_PROBE_S5D4_20261013_222131.txt"), encoding="utf-8", errors="replace").read()
tail = bytes.fromhex(re.search(r"^ ([0-9a-f]{2}(?: [0-9a-f]{2}){7})$", sp, re.M).group(1).replace(" ", ""))
exp_hex_file = re.search(r"TAIL_EXPECT exp=([0-9a-f]+) got=([0-9a-f]+)", sp).group(1)
OFF_S5 = 1346828296  # ARM_D4_CHAIN S5D4 OFF_AUTO
K = 1048576
exp_mine = mir(OFF_S5 + K, 8).hex()
ctrl_pre = re.search(r"address 0x144[^\n]*: (0x[0-9a-f]+)", sp).group(1)
stat_pre = re.search(r"address 0x13c[^\n]*: (0x[0-9a-f]+)", sp).group(1)
writev = re.search(r"Write 32-bits value (0x[0-9a-f]+) to 0x144", sp).group(1)
stat_post = re.findall(r"address 0x13c[^\n]*: (0x[0-9a-f]+)", sp)[1]
ctrl_post = re.findall(r"address 0x144[^\n]*: (0x[0-9a-f]+)", sp)[1]
cnt_pre = re.search(r"address 0x148[^\n]*: (0x[0-9a-f]+)", sp).group(1)
cnt_post = re.findall(r"address 0x148[^\n]*: (0x[0-9a-f]+)", sp)
tail_rc = re.search(r"TAIL_RC=(\d+) ELAPSED=(\d+)", sp)
print()
print(f"停流探针: MIR_STATUS {stat_pre} -> {stat_post}; MIR_CTRL {ctrl_pre} --写{writev}--> {ctrl_post}; MIR_DMA_CNT {cnt_pre} -> {cnt_post}")
print(f"  TAIL_RC={tail_rc.group(1)} ELAPSED={tail_rc.group(2)}; tail={tail.hex()}")
print(f"  EXPECT 文件={exp_hex_file}; 本复算 mir(OFF+K,8)^A5 = {exp_mine}")
print(f"  逐字节 MATCH: {tail.hex() == exp_hex_file == exp_mine}")
print()
print("D4 链整体:", "ALL MATCH" if allok and tail.hex() == exp_mine else "MISMATCH FOUND")
