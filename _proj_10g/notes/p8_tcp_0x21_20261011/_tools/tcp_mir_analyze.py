#!/usr/bin/env python3
"""tcp_mir_analyze.py -- P8 TCP 臂抓取样离线复算 (与板上工具**独立**的一条路径)

判据: captured[i] ^ 0xA5 == pattern[pat_off + i]  (逐字节; pattern = p7b_pattern.h 的
      xorshift64 / SEED 0x9E3779B97F4A7C15 / 先取后推进, 与 RTL app_pattern 同款)
定位: --pat-off N (已知起点, 如全流捕获) 或 --search (中流捕获: 用首 16 字节在图案流
      [0,total) 里 find; 同时报第二个命中位置以证唯一性)。
用法: python tcp_mir_analyze.py <mir.bin> --pat-off N | --search [--total N] [--selftest]
"""
import sys

M64 = (1 << 64) - 1
SEED = 0x9E3779B97F4A7C15

def xs_next(s):
    s ^= (s << 13) & M64
    s ^= s >> 7
    s ^= (s << 17) & M64
    return s & M64

def pattern_at(off, n):
    s = SEED
    for _ in range(off):
        s = xs_next(s)
    out = bytearray(n)
    for i in range(n):
        out[i] = (s >> 24) & 0xFF
        s = xs_next(s)
    return bytes(out)

def first_mismatch(a, b):
    """返回 (第一个不等处, 不等字节数); a==b 时 (-1, 0)。按块扫 + 块内二分。"""
    n = min(len(a), len(b))
    step = 4096
    pos = 0
    while pos < n:
        end = min(pos + step, n)
        if a[pos:end] != b[pos:end]:
            lo, hi = pos, end
            while lo < hi:
                mid = (lo + hi) // 2
                if a[lo:mid+1] == b[lo:mid+1]:
                    lo = mid + 1
                else:
                    hi = mid
            fm = lo
            mism = sum(1 for k in range(fm, n) if a[k] != b[k])
            return fm, mism
        pos = end
    if len(a) != len(b):
        return n, len(a) - n  # 长度不等: 尾部缺失
    return -1, 0

def main():
    args = sys.argv[1:]
    if not args or args[0] == "--selftest":
        v0 = pattern_at(0, 16).hex()
        v2 = pattern_at(1460, 8).hex()
        ok1 = (v0 == "7f0b02e536a14ed61ab049b856add63f")
        ok2 = (v2 == "0300422d9b47cac0")
        print("SELFTEST off0_15 ", v0, "OK" if ok1 else "MISMATCH")
        print("SELFTEST off1460", v2, "OK" if ok2 else "MISMATCH")
        return 0 if (ok1 and ok2) else 1
    path = args[0]
    pat_off = None; search = False; total = 1 << 21
    i = 1
    while i < len(args):
        if args[i] == "--pat-off": pat_off = int(args[i+1], 0); i += 2
        elif args[i] == "--search": search = True; i += 1
        elif args[i] == "--total": total = int(args[i+1], 0); i += 2
        else: i += 1
    got = open(path, "rb").read()
    print(f"# file={path} bytes={len(got)}")
    xor = bytes(b ^ 0xA5 for b in got)
    need = max(total, len(got) + (pat_off or 0))
    pat = pattern_at(0, need)
    if search:
        needle = xor[:16]
        d = pat.find(needle)
        d2 = pat.find(needle, d + 1) if d >= 0 else -2
        print(f"SEARCH needle16={needle.hex()} first_hit={d} second_hit={d2}")
        if d < 0:
            print("SEARCH_FAIL 首 16 字节在图案流 [0,%d) 里找不到" % need)
            return 1
        pat_off = d
    if pat_off is None:
        pat_off = 0
    seg = pat[pat_off: pat_off + len(got)]
    fm, mism = first_mismatch(xor, seg)
    print(f"CHECK pat_off={pat_off} pat_len={len(seg)} cap_len={len(got)} "
          f"compared={min(len(seg),len(got))} first_mismatch={fm} mism_bytes={mism}")
    return 0 if (fm < 0 and len(seg) == len(got)) else 1

if __name__ == "__main__":
    sys.exit(main())
