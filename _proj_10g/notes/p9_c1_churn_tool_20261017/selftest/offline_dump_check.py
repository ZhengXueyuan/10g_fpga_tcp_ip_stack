#!/usr/bin/env python3
"""offline_dump_check.py -- 对 p7b_tcp_churn 落盘的候选前缀做**独立实现**复核

用法: python3 offline_dump_check.py <dump_dir> [--expect-files N] [--note TAG]
判据（逐条打原始读数; 末行 OFFLINE_CHECK PASS|FAIL）:
  1) 文件数 == --expect-files（若给）
  2) 每个文件内**不含** 32 字节针（针由**本文件自己的** xorshift 重算 ⇒ 与工具是两套代码）
  3) **正对照（本检查器自己的牙）**：拿第一个文件，把针插到偏移 100 ⇒ 必须报 off=100
     （证明"不含针"不是"扫描器瞎了"）
  4) 反例：对一个合成文件（针在 0）⇒ 必须报 off=0
⛔ 独立第三实现；不 import 任何工程头/工具。
"""
import argparse
import os
import sys

MASK = (1 << 64) - 1
SEED = 0x9E3779B97F4A7C15
DOC16 = "7F0B02E536A14ED61AB049B856ADD63F"
N = 32


def xs(s):
    s ^= (s << 13) & MASK
    s ^= s >> 7
    s ^= (s << 17) & MASK
    return s


def needle32():
    s, out = SEED, bytearray(N)
    for i in range(N):
        out[i] = (s >> 24) & 0xFF
        s = xs(s)
    return bytes(out)


def scan(buf, nd):
    for i in range(0, len(buf) - N + 1):
        if buf[i] == nd[0] and buf[i:i + N] == nd:
            return i
    return -1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--expect-files", type=int, default=-1)
    ap.add_argument("--note", default="")
    a = ap.parse_args()

    nd = needle32()
    if nd[:16].hex().upper() != DOC16:
        print("OFFLINE_CHECK FAIL needle self-check got=%s" % nd[:16].hex().upper())
        return 1
    print("OFFLINE_CHECK needle[0..15]=%s (独立重算, 与 p7b_pattern.h 文档向量同)"
          % " ".join("%02X" % b for b in nd[:16]))

    files = sorted(f for f in os.listdir(a.dir) if f.startswith("churn_conn") and f.endswith(".bin"))
    nf = len(files)
    fails = 0
    print("OFFLINE_CHECK dir=%s files=%d %s" % (a.dir, nf, a.note))
    if a.expect_files >= 0:
        ok = (nf == a.expect_files)
        if not ok:
            fails += 1
        print("OFFLINE_CHECK file_count got=%d want=%d %s" % (nf, a.expect_files, "PASS" if ok else "FAIL"))

    # ① 正对照: 合成文件, 针在偏移 0 ⇒ 必须报 0
    ok0 = (scan(nd + b"\x00" * 64, nd) == 0)
    if not ok0:
        fails += 1
    print("OFFLINE_CHECK posctrl_synth_off0 got=%d want=0 %s" % (scan(nd + b"\x00" * 64, nd), "PASS" if ok0 else "FAIL"))

    n_hit = 0
    total_bytes = 0
    first = None
    for f in files:
        with open(os.path.join(a.dir, f), "rb") as fh:
            d = fh.read()
        total_bytes += len(d)
        if first is None:
            first = d
        hit = scan(d, nd)
        if hit >= 0:
            n_hit += 1
            print("OFFLINE_CHECK FILE_HAS_NEEDLE %s off=%d bytes=%d" % (f, hit, len(d)))
    okn = (n_hit == 0)
    if not okn:
        fails += 1
    print("OFFLINE_CHECK no_needle_in_dumps files=%d with_needle=%d bytes_total=%d %s"
          % (nf, n_hit, total_bytes, "PASS" if okn else "FAIL"))

    # ② 注入反例: 拿第一个文件, 针插到偏移 100 ⇒ 必须报 100
    if first is not None and len(first) > 200:
        inj = bytearray(first)
        inj[100:100 + N] = nd
        got = scan(bytes(inj), nd)
        ok = (got == 100)
        if not ok:
            fails += 1
        print("OFFLINE_CHECK inj_first_file_off100 got=%d want=100 %s" % (got, "PASS" if ok else "FAIL"))

    print("OFFLINE_CHECK %s fails=%d" % ("FAIL" if fails else "PASS", fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
