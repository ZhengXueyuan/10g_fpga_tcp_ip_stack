#!/usr/bin/env python3
"""Red-team independent K0 verifier v2 (lane-decomposition pattern generator).

Pattern (from rtl/app_pattern.v): state s u64, seed 0x9E3779B97F4A7C15;
step s^=s<<13; s^=s>>7; s^=s<<17; output byte=(s>>24)&0xFF before the step.

Generator: split the N-byte pattern into L contiguous lanes; lane l starts at
s = A_chunk^l(SEED) with A_chunk = f^chunk; all lanes then advance IN LOCKSTEP
(vectorized uint64 numpy).  The lane-start chain is computed sequentially in
python (L steps, cheap).  Self-checked against a straight sequential generator
on the first 1 MiB.

Check per TCP connection (pcap, board->peer dport-split):
  * per-segment absolute comparison: payload == patt[o:o+len], o=(seq-base)&0xFFFFFFFF
  * byte-level coverage: holes / duplicate bytes / duplicate payload conflicts
  * first mismatch position (absolute), if any
This verifies the claim "K0==0 ∧ breaks==0 ∧ verified_prefix==n" by directly
checking the strongest form: the whole stream == pattern from absolute offset 0.
Usage: k0_verify2.py <arm-tag> <pcap files...>
"""
import struct, sys, time
import numpy as np

M64 = (1 << 64) - 1
SEED = 0x9E3779B97F4A7C15
BOARD_IP = "192.168.100.2"
SPORT = 8080


def step_bits(x):
    x ^= (x << 13) & M64
    x ^= x >> 7
    x ^= (x << 17) & M64
    return x & M64


def seq_generator(n):
    s = SEED
    out = bytearray(n)
    for i in range(n):
        out[i] = (s >> 24) & 0xFF
        s = step_bits(s)
    return bytes(out)


def build_F():
    F = np.zeros((64, 64), dtype=np.uint8)
    for j in range(64):
        f = step_bits(1 << j)
        for i in range(64):
            if (f >> i) & 1:
                F[i, j] = 1
    return F


def matmul_gf2(A, B):
    return (A.astype(np.uint32) @ B.astype(np.uint32) % 2).astype(np.uint8)


def matpow_gf2(A, k):
    R = np.eye(64, dtype=np.uint8)
    while k:
        if k & 1:
            R = matmul_gf2(R, A)
        A = matmul_gf2(A, A)
        k >>= 1
    return R


def cols_as_ints(M):
    """For matrix M (64x64 GF2): col[j] as int = M applied to e_j."""
    cols = []
    for j in range(64):
        v = 0
        for i in range(64):
            if M[i, j]:
                v |= (1 << i)
        cols.append(v)
    return cols


def apply_mixed(cols, v):
    out = 0
    while v:
        b = v & -v
        out ^= cols[b.bit_length() - 1]
        v ^= b
    return out


def generate_pattern(N, L=1 << 18):
    """Return numpy uint8 array of the pattern's first N bytes (global order)."""
    chunk = max(1, (N + L - 1) // L)
    F = build_F()
    A = matpow_gf2(F, chunk)
    cols = cols_as_ints(A)
    t0 = time.time()
    # lane starts: z_l = A^l (SEED)
    zs = np.empty(L, dtype=np.uint64)
    z = SEED
    for l in range(L):
        zs[l] = z
        z = apply_mixed(cols, z)
    print(f"# lane starts done L={L} chunk={chunk} ({time.time()-t0:.1f}s)")
    patt = np.empty((L, chunk), dtype=np.uint8)
    batch = zs
    t0 = time.time()
    for t in range(chunk):
        patt[:, t] = (batch >> np.uint64(24)).astype(np.uint8)
        batch = batch ^ (batch << np.uint64(13))
        batch = batch ^ (batch >> np.uint64(7))
        batch = batch ^ (batch << np.uint64(17))
    print(f"# pattern generated ({time.time()-t0:.1f}s) total={L*chunk}")
    flat = patt.reshape(-1)[:N]
    return flat


def iter_packets(path):
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
    if len(eth) < 34 or eth[12] != 0x08 or eth[13] != 0x00:
        return None
    ip = eth[14:]
    if (ip[0] >> 4) != 4 or ip[9] != 6:
        return None
    ihl = (ip[0] & 0xF) * 4
    tot = struct.unpack(">H", ip[2:4])[0]
    src = ".".join(str(x) for x in ip[12:16])
    tcp = ip[ihl:]
    if len(tcp) < 20:
        return None
    sport, dport = struct.unpack(">HH", tcp[0:4])
    seq = struct.unpack(">I", tcp[4:8])[0]
    flags = tcp[13]
    doff = (tcp[12] >> 4) * 4
    payload = bytes(tcp[doff:tot - ihl]) if tot >= ihl + doff else b""
    return (src, sport, dport, seq, flags, payload)


def main():
    arm = sys.argv[1]
    files = sys.argv[2:]
    conns, order, flags_seen = {}, [], {}
    total_pkts = 0
    t0 = time.time()
    for p in files:
        for data in iter_packets(p):
            r = parse_tcp(data)
            if r is None:
                continue
            total_pkts += 1
            src, sport, dport, seq, flags, pl = r
            if src != BOARD_IP or sport != SPORT:
                continue
            if dport not in conns:
                conns[dport] = []
                order.append(dport)
                flags_seen[dport] = {}
            flags_seen[dport][flags] = flags_seen[dport].get(flags, 0) + 1
            if pl:
                conns[dport].append((seq, pl))
    print(f"# arm={arm} files={len(files)} total_pkts={total_pkts} conns={len(conns)} "
          f"({time.time()-t0:.1f}s)")

    # per-connection geometry
    geo = {}
    Nmax = 0
    for d in order:
        segs = conns[d]
        if not segs:
            continue
        seqs = [s for s, _ in segs]
        base = min(seqs)
        spans = [((s - base) & 0xFFFFFFFF, len(pl), pl) for s, pl in segs]
        n = max(o + L for o, L, _ in spans)
        Nmax = max(Nmax, n)
        geo[d] = (segs, base, spans, n)

    # sanity: sequential reference for first 1 MiB
    ref = seq_generator(1 << 20)
    patt = generate_pattern(Nmax)
    assert bytes(patt[:1 << 20]) == ref, "lane generator != sequential generator!"
    print(f"# generator self-check vs sequential first 1MiB: OK; Nmax={Nmax}")

    for d in order:
        if d not in geo:
            print(f"== CONN dport={d} == NO_PAYLOAD flags={flags_seen[d]}")
            continue
        segs, base, spans, n = geo[d]
        buf = np.zeros(n, dtype=np.uint8)
        filled = np.zeros(n, dtype=bool)
        holes = dup_bytes = dup_conflict = 0
        first_conf = None
        mism_seg = 0
        first_mism = None
        for o, L, pl in sorted(spans, key=lambda x: x[0]):
            seg = np.frombuffer(pl, dtype=np.uint8)
            ref_slice = patt[o:o + L]
            neq = np.nonzero(seg != ref_slice)[0]
            if len(neq):
                mism_seg += 1
                if first_mism is None:
                    k = int(neq[0])
                    first_mism = (o + k, int(seg[k]), int(ref_slice[k]))
            ov = filled[o:o + L] & (buf[o:o + L] != seg)
            if ov.any():
                dup_conflict += int(ov.sum())
                if first_conf is None:
                    first_conf = o + int(np.argmax(ov))
            new = ~filled[o:o + L]
            dup_bytes += int((~new & (buf[o:o + L] == seg)).sum())
            buf[o:o + L] = np.where(new, seg, buf[o:o + L])
            filled[o:o + L] = True
        holes = int((~filled).sum())
        # whole-buffer direct compare as an extra belt-and-braces check
        if holes == 0:
            dbad = np.nonzero(buf != patt[:n])[0]
            buf_first = int(dbad[0]) if len(dbad) else -1
        else:
            buf_first = None
        verdict = (mism_seg == 0 and holes == 0 and dup_conflict == 0 and buf_first in (-1, None) and buf_first != None and buf_first == -1)
        print(f"== CONN dport={d} segs={len(segs)} base={base} n={n} "
              f"holes={holes} dup_bytes={dup_bytes} dup_conflict={dup_conflict} "
              f"seg_mismatches={mism_seg} buf_first_mismatch={buf_first} "
              f"first_mism=(pos,got,want)={first_mism} first_conflict_pos={first_conf} "
              f"VERDICT={'K0=0&breaks=0&prefix=n' if verdict else 'CHECK'} flags={flags_seen[d]}")


if __name__ == "__main__":
    main()
