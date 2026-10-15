#!/usr/bin/env python3
# align_check2.py -- 相位校正后的内容核查 (有界版; 断点搜索有界 => 不会挂)
#   1) 拼流 (按 seq)  2) 用首 32 字节找对齐偏移 K0 (扫 0..2^22)  3) 逐 64KB 块核 stream[i] == pat[K0+i]
#   4) 首个不符处: 打印位置 + 有界重对齐搜索 (j in [bp,bp+256], d in ±65536), 最多 3 个断点
# 用法: python3 align_check2_fixed.py <pcap...> <sport>
#
# ==== 相对原版的唯一改动（依据 = DESIGN_v2.md §5.3-②，M-6 采信版） ====
#   原文逐字："真缺口 = 断点后的重对齐（:119-127: c = K0 + j ± d, d ∈ [0, 65536]，且只在
#   bp..bp+257 窗口内找）⇒ 结构性到不了'绝对相位 0'（S0A 的 UNALIGNED_REST 即此）
#   ⇒ 修法 = 重对齐改绝对锚（或 d 扩到含 −(K0+j) 的绝对扫描）+ 把搜索窗口从 257 B 放宽"
#   ★ 改动 1 = 断点后重对齐新增【绝对锚分支】：在图案绝对偏移 [0, 2^22] 内直扫 32 字节窗
#     （与首扫 head=gen_pattern(0,1<<22) 同界；= DESIGN.md(v1) §5.3 的"绝对偏移 0..2^22 扫描"）。
#   ★ 改动 2 = 重对齐搜索窗口 257 → 65536（与 d 同量级；设计件未给数值，取值登记在轮报告）。
#   ★ 改动 3 = 重对齐命中后的【基址更新】`K0 = newK` → `K0 = newK - j2`。
#     【本件实测发现（设计件未写）】原版在 j2>0 时结构性无法恢复验证：`align_ok(i,.,K)` 的口径是
#     "K = 流位置 0 处的相位"（首扫 K0=head.find(w0) 即此义），而重对齐命中 (j2, newK=c) 后置
#     `K0 = c` 后，下一轮比较的是 PAT[c + i] vs buf[i]，在 i=j2 处必失配 ⇒ 同拍再断、三连后停
#     （实测 case E：原版与"只加绝对锚"的中间版都停在 verified_prefix=1440 / breaks=3，且重复打印
#     同一个 newK）。正确基址 = c − j2 ⇒ 改动 3 才让"重对齐"在**可观测意义上**成立（能继续验证到流尾）。
#     ⇒ 三处改动 = 一个整体（绝对锚 + 窗口 + 基址）；若只认前两处，后两处的能力差异见轮报告"偏差"节。
#   ★ 改动 4 = 【图案生成长度】`K0 + n` → `ABS_HEAD + n + 2*REALIGN_WIN + 32`。
#     【本件实测发现（设计件未写）】改动 3 把基址挪到新相位后，图案必须覆盖"新相位 + 流长"；
#     原版按初相位生成 ⇒ 当重对齐落点的相位-at-0 > 初相位时（前向相位跳变 / 绝对锚落点），
#     流尾会撞上 PAT 越界 ⇒ **假断点**（实测 case E：BREAK @92873 = PAT 耗尽点、newK=None）。
#     新长度覆盖：abs 分支 c ≤ 2^22 ⇒ 基址 ≤ 2^22；rel 分支 c ≤ K0+j+65536 ≤ K0+W+65536
#     ⇒ 基址 + n ≤ ABS_HEAD + n + 2*REALIGN_WIN（K0 ≤ 2^22-32 恒成立，见首扫界）。
#   ★ 旧式相对候选（K0+j±d, d∈[0,65536]）原样保留为【兜底】：仅当绝对锚扫不到才走。
#   ⚠️ 首扫 K0 = head.find(w0) 未动（M-6 现核：它本来就是绝对的）；头上限 4 MB 未动（§5.3-③ 登记不修）。
#   ⚠️ 输出仅 newK 行追加一个诊断字段（abs/rel）；既有字段一个未改。
import struct, sys

SEED = 0x9E3779B97F4A7C15
M64 = (1 << 64) - 1
CH = 65536
ABS_HEAD = (1 << 22) + 32   # 绝对锚扫描面 = 图案绝对偏移 [0, 2^22]（§5.3-② / 与首扫同界）
REALIGN_WIN = 65536          # 断点后重对齐窗口（原版 = 257；本件按 §5.3-② 放宽）


def read_pcap(path):
    with open(path, "rb") as f:
        gh = f.read(24)
        if len(gh) < 24:
            return
        magic = struct.unpack("<I", gh[:4])[0]
        endian = "<" if magic in (0xA1B2C3D4, 0xA1B23C4D) else ">"
        while True:
            hdr = f.read(16)
            if len(hdr) < 16:
                break
            ts, tu, caplen, origlen = struct.unpack(endian + "IIII", hdr)
            data = f.read(caplen)
            if len(data) < caplen:
                break
            yield data


def parse_tcp(eth):
    if len(eth) < 34:
        return None
    ip = eth[14:]
    if (ip[0] >> 4) != 4 or ip[9] != 6:
        return None
    ihl = (ip[0] & 0xF) * 4
    tot = struct.unpack(">H", ip[2:4])[0]
    tcp = ip[ihl:]
    sport, dport = struct.unpack(">HH", tcp[0:4])
    seq = struct.unpack(">I", tcp[4:8])[0]
    doff = (tcp[12] >> 4) * 4
    payload = bytes(tcp[doff:tot - ihl]) if tot >= ihl + doff else b""
    return (sport, dport, seq, payload)


def gen_pattern(start, n):
    """生成图案 [start, start+n) 的 bytes (逐字节, 与 app_pattern.v / p7b_pattern.h 同序)"""
    s = SEED
    for _ in range(start):
        s ^= (s << 13) & M64
        s ^= s >> 7
        s ^= (s << 17) & M64
        s &= M64
    out = bytearray(n)
    for i in range(n):
        out[i] = (s >> 24) & 0xFF
        s ^= (s << 13) & M64
        s ^= s >> 7
        s ^= (s << 17) & M64
        s &= M64
    return bytes(out)


def main():
    files = sys.argv[1:-1]
    sport = int(sys.argv[-1])
    segs = []
    for p in files:
        for data in read_pcap(p):
            r = parse_tcp(data)
            if r is None:
                continue
            s, d, seq, pl = r
            if s != sport or not pl:
                continue
            segs.append((seq, pl))
    if not segs:
        print("NO_SEGS", flush=True)
        return
    segs.sort(key=lambda x: x[0])
    base = segs[0][0]
    n = max((s - base) & 0xFFFFFFFF for s, _ in segs) + len(segs[-1][1])
    buf = bytearray(n)
    for s, pl in segs:
        o = (s - base) & 0xFFFFFFFF
        buf[o:o + len(pl)] = pl
    print("ALIGN2 segs=%d n=%d" % (len(segs), n), flush=True)
    w0 = bytes(buf[0:32])
    # K0 候选 = 用首 32 字节扫 (先生成 4 MB 图案即可覆盖常见偏移)
    head = gen_pattern(0, 1 << 22)
    K0 = head.find(w0)
    print("K0=%s" % K0, flush=True)
    if K0 < 0:
        return
    # 一次性生成 [0, K0+n) 图案 (单遍), 之后全是切片比较
    PAT = gen_pattern(0, ABS_HEAD + n + 2 * REALIGN_WIN + 32)   # 改动 4: 覆盖'重对齐后基址 + 流长'
    print("PAT_GEN done len=%d" % len(PAT), flush=True)

    def align_ok(i, ln, K):
        return PAT[K + i:K + i + ln] == bytes(buf[i:i + ln])

    i = 0
    breaks = []
    while i < n:
        ln = min(CH, n - i)
        if align_ok(i, ln, K0):
            i += ln
            if (i // CH) % 500 == 0:
                print("  ... verified %d/%d" % (i, n), flush=True)
            continue
        bp = i
        while bp < n - 8 and align_ok(bp, 8, K0):
            bp += 1
        print("BREAK @%d (verified %d bytes before)" % (bp, bp), flush=True)
        breaks.append(bp)
        newK = None
        j2 = None
        how = None
        for j in range(bp, min(n - 32, bp + REALIGN_WIN)):
            w = bytes(buf[j:j + 32])
            # (1) 绝对锚分支（新增）: 图案绝对偏移 [0, 2^22] 直扫 —— 能落到绝对相位（含 0）
            c = PAT.find(w, 0, min(len(PAT), ABS_HEAD))
            if c >= 0:
                newK = c
                how = "abs"
            else:
                # (2) 原相对候选（兜底, 未改）: K0+j±d, d ∈ [0, 65536]
                for d in range(0, 65537):
                    for c in (K0 + j + d, K0 + j - d):
                        if 0 <= c <= len(PAT) - 32 and PAT[c:c + 32] == w:
                            newK = c
                            how = "rel"
                            break
                    if newK is not None:
                        break
            if newK is not None:
                j2 = j
                break
        print("  newK=%s new_pos=%s how=%s" % (newK, j2, how), flush=True)
        if newK is None or len(breaks) >= 3:
            break
        K0 = newK - j2   # 改动 3: 基址 = 流位置 0 处的新相位 (原版 = newK 本身 ⇒ j2>0 时结构性停摆)
        i = j2
    print("ALIGN2_DONE verified_prefix=%d n=%d breaks=%d" % (i, n, len(breaks)), flush=True)


if __name__ == "__main__":
    main()
