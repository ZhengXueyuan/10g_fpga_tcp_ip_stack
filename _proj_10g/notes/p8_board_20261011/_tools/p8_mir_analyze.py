#!/usr/bin/env python3
# p8_mir_analyze.py -- 分析镜像窗抓到的字节流与图案流的关系 (揭示"隔组丢"图案)
#   用法: python p8_mir_analyze.py <mir.bin> [--xorc 0xA5] [--group 8] [--search 262144]
#   输出: 每个 group 的字节在图案流里的**首候选偏移** (或 -1 = 找不到) + 差值序列
import sys

SEED = 0x9E3779B97F4A7C15
M64 = (1 << 64) - 1


def xs_next(s):
    s ^= (s << 13) & M64
    s ^= s >> 7
    s ^= (s << 17) & M64
    return s & M64


def pattern_stream(n):
    s = SEED
    out = bytearray(n)
    for i in range(n):
        out[i] = (s >> 24) & 0xFF
        s = xs_next(s)
    return bytes(out)


def main():
    bin_path = sys.argv[1]
    xorc = 0xA5
    group = 8
    search = 262144
    args = sys.argv[2:]
    for i, a in enumerate(args):
        if a == "--xorc":
            xorc = int(args[i + 1], 0)
        elif a == "--group":
            group = int(args[i + 1], 0)
        elif a == "--search":
            search = int(args[i + 1], 0)

    got = bytearray(open(bin_path, "rb").read())
    for i in range(len(got)):
        got[i] ^= xorc                      # 板内做的是 ^0xA5 ⇒ 这里还原
    pat = pattern_stream(search)
    ngroups = len(got) // group
    print(f"# file={bin_path} bytes={len(got)} group={group} ngroups={ngroups} search={search}")
    offs = []
    for g in range(ngroups):
        chunk = bytes(got[g * group:(g + 1) * group])
        pos = pat[: search + group].find(chunk)      # 允许跨尾
        offs.append(pos)
        print(f"G{g:4d} file_off={g*group:8d} pat_off={pos if pos >= 0 else -1:8d}")
    print("# 差值序列 (相邻 group 的 pat_off 差):")
    d = [offs[i + 1] - offs[i] for i in range(len(offs) - 1) if offs[i] >= 0 and offs[i + 1] >= 0]
    print("# diffs:", d[:64], ("..." if len(d) > 64 else ""))


if __name__ == "__main__":
    main()
