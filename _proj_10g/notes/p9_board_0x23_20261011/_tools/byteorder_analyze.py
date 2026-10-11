#!/usr/bin/env python3
# byteorder_analyze.py -- P9 字节序判决: 抓取流 vs 图案流(独立 LFSR 复算) 的逐字节对账
#   三条判据 (相互独立):
#     ① SELF-TEST: LFSR 复算必须命中 p7b_pattern.h 的两个自检向量 (否则本脚本无资格判)
#     ② 恒等假设 (本工具/实现假设: tdata[7:0] = 宿主 byte 0): mism_bytes 应为 0
#     ③ 三个候选失配形态 (a) 16B 整拍反序 (b) 拍内 8B 半交换 (c) 拍内 4B 字序
#        —— 各自给出 mism_bytes (若恒等为 0, 它们应大量失配 ⇒ 假设被判别而不是被默认)
#     ⭐ 另加 "车道发现" (lane discovery): 不做任何先验假设, 直接对每个内存车道位置 m
#        求它与图案拍内位置 q 的**唯一一致映射** (跨多拍 100% 命中) ⇒ 直接读出置换本身。
#   用法: python byteorder_analyze.py <mir.bin> --pat-off N [--dump-at A] [--scan-bytes N]
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
    return out

def self_test():
    v = pattern_at(0, 16)
    want = bytes([0x7F,0x0B,0x02,0xE5,0x36,0xA1,0x4E,0xD6,0x1A,0xB0,0x49,0xB8,0x56,0xAD,0xD6,0x3F])
    v2 = pattern_at(1460, 8)
    want2 = bytes([0x03,0x00,0x42,0x2D,0x9B,0x47,0xCA,0xC0])
    ok1 = (v == want); ok2 = (v2 == want2)
    print(f"SELFTEST off0_15    {v.hex()} {'OK' if ok1 else 'MISMATCH'}")
    print(f"SELFTEST off1460_67 {v2.hex()} {'OK' if ok2 else 'MISMATCH'}")
    return ok1 and ok2

# ---- 候选失配形态 (作用在"抓取流"上, 使其回到应有顺序) ----
def perm_identity(n):   return list(range(n))
def perm_rev16(n):      return [ (i//16)*16 + 15 - (i%16) for i in range(n) ]           # (a) 16B 整拍反序
def perm_swap8(n):      return [ (i//16)*16 + ((i%16)+8)%16 for i in range(n) ]          # (b) 拍内 8B 半交换
def perm_swap4w8(n):    return [ (i//8)*8 + ((i%8)+4)%8 for i in range(n) ]              # (c) 8B 组内 4B 字序
def perm_rev4(n):       return [ (i//4)*4 + 3 - (i%4) for i in range(n) ]                # (c') 4B 字内反序
def perm_rev8(n):       return [ (i//8)*8 + 7 - (i%8) for i in range(n) ]                # 8B 组内整反序
def perm_rot4(n):       return [ (i//16)*16 + ((i%16)+4)%16 for i in range(n) ]          # 拍内 4B 旋转

def count_mismatch(got, pat, perm):
    mism = 0; fm = -1
    for i, gi in enumerate(perm):
        if got[gi] != pat[i]:
            if fm < 0: fm = i
            mism += 1
    return fm, mism

def main():
    args = sys.argv[1:]
    if not args:
        print("usage: byteorder_analyze.py <mir.bin> --pat-off N [--dump-at A]"); return 2
    path = args[0]
    pat_off = 0; dump_at = 0; scan = None
    i = 1
    while i < len(args):
        if args[i] == "--pat-off": pat_off = int(args[i+1], 0); i += 2
        elif args[i] == "--dump-at": dump_at = int(args[i+1], 0); i += 2
        elif args[i] == "--scan-bytes": scan = int(args[i+1], 0); i += 2
        else: i += 1

    print("=== ① LFSR 自检 (p7b_pattern.h 的两条向量) ===")
    if not self_test():
        print("FATAL: LFSR 复算与文档向量不符 ⇒ 本脚本无资格对账"); return 3

    got = open(path, "rb").read()
    N = len(got) if scan is None else min(scan, len(got))
    print(f"=== ② 对账 ===\nfile={path} bytes={len(got)} 对账长度={N} pat_off={pat_off} xor=0xA5")
    pat = pattern_at(pat_off, N)
    # 期望流 = 图案 ^ 0xA5
    exp = bytes(b ^ 0xA5 for b in pat)

    print("--- 恒等假设 (tdata[7:0] = 宿主 byte 0) ---")
    fm, mism = count_mismatch(got[:N], exp, perm_identity(N))
    print(f"IDENTITY        first_mismatch={fm} mism_bytes={mism} of {N} ({'全等' if mism==0 else 'x'})")

    print("--- 三个候选失配形态 (同一份数据, 换重排假设) ---")
    for name, fn in [("(a) rev16  ", perm_rev16), ("(b) swap8  ", perm_swap8),
                     ("(c) 4B字序 ", perm_swap4w8), ("(c') 4B反序", perm_rev4),
                     ("    8B反序 ", perm_rev8), ("    拍内rot4", perm_rot4)]:
        fm2, m2 = count_mismatch(got[:N], exp, fn(N))
        print(f"HYP {name} first_mismatch={fm2} mism_bytes={m2} of {N} ({m2*100.0/N:.2f}%)")

    print("--- ⭐ 车道发现 (无先验: 每个内存车道 m 找唯一全中的图案通道 q) ---")
    BEATS_TOTAL = N // 16
    START = 0
    if BEATS_TOTAL > 64:
        START = min(1024, (BEATS_TOTAL // 2))       # 从流中段取 (避开可能的头残拍)
    W = min(512, BEATS_TOTAL - START)
    if W < 8:
        print(f"LANE_DISCOVERY 跳过 (拍数不足: {BEATS_TOTAL})")
    else:
        counts = [[0]*16 for _ in range(16)]        # counts[m][q]
        for b in range(START, START + W):
            for m in range(16):
                c = got[16*b+m] ^ 0xA5
                for q in range(16):
                    if c == pat[16*b+q]: counts[m][q] += 1
        mapping = []; amb = []
        for m in range(16):
            best = max(counts[m]); qs = [q for q in range(16) if counts[m][q] == best]
            mapping.append(qs[0] if len(qs) == 1 else None)
            if len(qs) != 1 or best != W: amb.append((m, qs, best))
        print(f"LANE_DISCOVERY beats={W} (起拍 {START}) 每车道唯一一致映射 m->q: {mapping}")
        print(f"LANE_DISCOVERY 歧义/不满分车道: {amb if amb else '无 (16/16 唯一且 100% 命中)'}")
        voc = {(0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15):"恒等",
               tuple(range(15,-1,-1)):"(a) 16B整拍反序"}
        mm = tuple(mapping) if None not in mapping else None
        tag = voc.get(mm, "见映射")
        print(f"LANE_DISCOVERY 形态标签: {tag}")

    print(f"--- 十六进制 dump (偏移 {dump_at}; 抓取 / 期望(图案^A5) / 逐字节异或) ---")
    d0 = dump_at; d1 = min(dump_at + 32, N)
    print(f"GOT  [{d0}] " + " ".join(f"{got[k]:02x}" for k in range(d0, d1)))
    bo = pat_off + d0
    print(f"EXP  [{d0}] " + " ".join(f"{exp[k]:02x}" for k in range(d0, d1)))
    print(f"XOR  [{d0}] " + " ".join(f"{got[k]^exp[k]:02x}" for k in range(d0, d1)))

    print("--- 全流逐字节统计 ---")
    nz = sum(1 for k in range(N) if got[k] != exp[k])
    print(f"ALL_BYTES mism={nz} / {N}   ({'逐字节全等' if nz==0 else 'x'})")
    return 0

if __name__ == "__main__":
    sys.exit(main())
