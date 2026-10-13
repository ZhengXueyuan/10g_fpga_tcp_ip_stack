#!/usr/bin/env python3
# pattern_jump.py -- 0x24 轮: xorshift64 图案的 O(1) 跳跃生成 (OFF 可达 1e9, 纯逐 step 不可行)
#   方法: xorshift64 是 GF(2) 上的线性映射 => 用 64 个基向量的像表示该映射,
#         跳跃 off 步 = 平方-乘 (compose) 求 f^off 的像表, 再对 SEED 应用.
#   自检: 必须命中 p7b_pattern.h 的两条向量 (否则无资格对账).
#   与 byteorder_analyze.pattern_at 的同值性: 小 off 逐字对照 (main 里 assert).
M64 = (1 << 64) - 1
SEED = 0x9E3779B97F4A7C15


def _step(s):
    s ^= (s << 13) & M64
    s ^= s >> 7
    s ^= (s << 17) & M64
    return s & M64


def _step_images():
    return [_step(1 << j) for j in range(64)]


def _apply(imgs, s):
    r = 0
    while s:
        b = s & -s
        r ^= imgs[b.bit_length() - 1]
        s ^= b
    return r & M64


def _compose(A, B):          # 返回 B∘A 的像表 (先 A 后 B)
    return [_apply(B, a) for a in A]


def jump(off):
    """返回 SEED 前进 off 步之后的状态."""
    res = [1 << j for j in range(64)]        # identity
    cur = _step_images()
    k = off
    while k:
        if k & 1:
            res = _compose(res, cur)
        cur = _compose(cur, cur)
        k >>= 1
    return _apply(res, SEED)


def pattern_at(off, n):
    s = jump(off) if off else SEED
    out = bytearray(n)
    for i in range(n):
        out[i] = (s >> 24) & 0xFF
        s = _step(s)
    return bytes(out)


def self_test():
    v = pattern_at(0, 16)
    want = bytes([0x7F, 0x0B, 0x02, 0xE5, 0x36, 0xA1, 0x4E, 0xD6,
                  0x1A, 0xB0, 0x49, 0xB8, 0x56, 0xAD, 0xD6, 0x3F])
    v2 = pattern_at(1460, 8)
    want2 = bytes([0x03, 0x00, 0x42, 0x2D, 0x9B, 0x47, 0xCA, 0xC0])
    ok1 = (v == want)
    ok2 = (v2 == want2)
    print(f"SELFTEST off0_15    {v.hex()} {'OK' if ok1 else 'MISMATCH'}")
    print(f"SELFTEST off1460_67 {v2.hex()} {'OK' if ok2 else 'MISMATCH'}")
    return ok1 and ok2


if __name__ == "__main__":
    import sys
    if not self_test():
        print("FATAL: 自检不过"); sys.exit(3)
    # 与逐 step 版对照 (小 off)
    def slow(off, n):
        s = SEED
        for _ in range(off):
            s = _step(s)
        out = bytearray(n)
        for i in range(n):
            out[i] = (s >> 24) & 0xFF
            s = _step(s)
        return bytes(out)
    for off in (0, 1, 2, 7, 63, 64, 65, 1000, 1460, 65536, 1000003):
        a = pattern_at(off, 32)
        b = slow(off, 32)
        assert a == b, f"MISMATCH at off={off}"
    print("JUMP_VS_SLOW OK (offs 0,1,2,7,63,64,65,1000,1460,65536,1000003)")
    import time
    t0 = time.time()
    x = pattern_at(1076295680, 4096)
    print(f"JUMP_BIG off=1076295680 n=4096 ok, {time.time()-t0:.2f}s head={x[:8].hex()}")
