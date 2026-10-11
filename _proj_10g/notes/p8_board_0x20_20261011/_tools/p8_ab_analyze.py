#!/usr/bin/env python3
"""p8_ab_analyze.py -- A/B 两臂抓取样离线复算 (与板上工具独立的一条路径)。

两条比对 (逐字节):
  ① NO_DROP 假设: captured[i]^0xA5 == pattern[pat_off + i]  ⇒ first_mismatch / mism_bytes
  ② 模型假设:     captured[i]^0xA5 == pattern[pat_off + idx_i] (idx = 逐拍模型的写出索引)
用法: python p8_ab_analyze.py <mir.bin> --pat-off N [--model PAYLEN NFRAMES [TAIL]]
      [--selftest]
"""
import importlib.util, sys

spec = importlib.util.spec_from_file_location("m", "mir_packer_model.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

M64 = (1 << 64) - 1
SEED = 0x9E3779B97F4A7C15

def xs_next(s):
    s ^= (s << 13) & M64
    s ^= s >> 7
    s ^= (s << 17) & M64
    return s & M64

def pattern_at(off, n):
    """图案流 [off, off+n) 的字节 (先取后推进: byte = s[31:24] 后推进)。"""
    s = SEED
    for _ in range(off):
        s = xs_next(s)
    out = bytearray(n)
    for i in range(n):
        out[i] = (s >> 24) & 0xFF
        s = xs_next(s)
    return out

def main():
    if "--selftest" in sys.argv:
        v = pattern_at(0, 16)
        want = bytes([0x7F,0x0B,0x02,0xE5,0x36,0xA1,0x4E,0xD6,0x1A,0xB0,0x49,0xB8,0x56,0xAD,0xD6,0x3F])
        v2 = pattern_at(1460, 8)
        want2 = bytes([0x03,0x00,0x42,0x2D,0x9B,0x47,0xCA,0xC0])
        print("SELFTEST off0_15", v.hex(), "OK" if v == want else "MISMATCH")
        print("SELFTEST off1460", v2.hex(), "OK" if v2 == want2 else "MISMATCH")
        return 0
    bin_path = sys.argv[1]
    pat_off = 0; model = None
    a = sys.argv[2:]
    i = 0
    while i < len(a):
        if a[i] == "--pat-off": pat_off = int(a[i+1], 0); i += 2
        elif a[i] == "--model-k":
            K = int(a[i+1], 0); pl = int(a[i+2])
            frames = m.frames_for(K, pl)
            model = m.run_frames(frames)
            print(f"# model: K={K} paylen={pl} frames={len(frames)} (末帧={frames[-1]})")
            i += 3
        else: i += 1
    got = bytearray(open(bin_path, "rb").read())
    N = len(got)
    print(f"# file={bin_path} bytes={N} pat_off={pat_off}")
    plen = N
    if model is not None and model["out_idx"]:
        plen = max(plen, max(model["out_idx"]) + 1)
    pat = pattern_at(pat_off, plen)
    # ① NO_DROP 比对
    fm = -1; mism = 0
    for k in range(N):
        if (got[k] ^ 0xA5) != pat[k]:
            if fm < 0: fm = k
            mism += 1
    print(f"NO_DROP_CHECK first_mismatch={fm} mism_bytes={mism} of {N}")
    # ② 模型比对
    if model is not None:
        idx = model["out_idx"]
        L = min(len(idx), N)
        fm2 = -1; mism2 = 0
        for k in range(L):
            if (got[k] ^ 0xA5) != pat[idx[k]]:
                if fm2 < 0: fm2 = k
                mism2 += 1
        print(f"MODEL_CHECK  len_model={len(idx)} len_file={N} 比对长度={L} "
              f"first_mismatch={fm2} mism_bytes={mism2}")
        print(f"MODEL_PRED   drop={model['drop']} out_bytes={model['out_bytes']} "
              f"acc_end={model['acc_end']} first_mismatch={model['first_mismatch']}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
