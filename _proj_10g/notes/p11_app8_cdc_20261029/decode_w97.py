#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""decode_w97.py -- P11 APP8 CDC 的 W97 位域解码（本地；只读输入）

用法: python decode_w97.py 0xXXXXXXXX [0xYYYYYYYY ...]
W97 = cdc_status（NW=98；地址 0x20+4*97 = 0x1A4）。
"""
import sys

def dec(v):
    print("W97 = 0x%08X" % v)
    print("  [1:0]   reserved            = %d" % (v & 3))
    print("  [2]     ev drop             = %d" % ((v >> 2) & 1))
    print("  [3]     close drop          = %d" % ((v >> 3) & 1))
    print("  [4]     stats stale (current)=%d" % ((v >> 4) & 1))
    print("  [5]     locked_app          = %d" % ((v >> 5) & 1))
    print("  [6]     app_rst_seen (armed)= %d" % ((v >> 6) & 1))
    print("  [7]     stats timeout sticky= %d" % ((v >> 7) & 1))
    mm = (v >> 8) & 0xFF
    print("  [15:8]  per-slot mismatch   = 0x%02X %s" % (mm, "".join(("1" if (mm >> i) & 1 else "0") for i in range(7, -1, -1))))
    print("  [19:16] close_pend_max      = %d" % ((v >> 16) & 0xF))
    print("  [20]    dp_rst_seen (armed) = %d" % ((v >> 20) & 1))
    print("  [31:21] rx FIFO occ (live)  = %d" % ((v >> 21) & 0x7FF))
    ok = ((v >> 5) & 1) == 1 and ((v >> 2) & 1) == 0 and ((v >> 3) & 1) == 0 \
         and ((v >> 4) & 1) == 0 and ((v >> 6) & 1) == 0 and ((v >> 7) & 1) == 0 \
         and ((v >> 20) & 1) == 0 and mm == 0
    print("  => %s (V5 §7.1: fault bits 2/3/7=0, reset-seen 6/20=0, stale 4=0, lock 5=1, mismatch 0x00)" % ("CLEAN" if ok else "NOT-CLEAN"))

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("usage: decode_w97.py 0xXXXXXXXX [...]"); sys.exit(2)
    for a in sys.argv[1:]:
        dec(int(a, 0))
        print()
