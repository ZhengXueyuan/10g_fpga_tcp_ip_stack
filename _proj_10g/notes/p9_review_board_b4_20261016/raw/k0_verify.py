#!/usr/bin/env python3
"""Red-team independent K0 verifier for the B4 round (written from scratch).

Method (independent of align_check2_fixed.py):
  * Pattern definition taken from the RTL (rtl/app_pattern.v): state s (uint64),
    seed 0x9E3779B97F4A7C15; each step s ^= s<<13; s ^= s>>7; s ^= s<<17;
    output byte = (s >> 24) & 0xFF, emitted BEFORE the step.
  * The xorshift64 map f is LINEAR over GF(2)^64, so the 8-byte word w_k
    (stream bytes 8k..8k+7) = G(f^{8k}(SEED)) where G maps a state to the 8
    successive top bytes.  The map G is (very likely) invertible; then
    w_{k+1} = G(A(R(w_k))) with A = f^8 — a purely VECTORIZED consistency
    check over the whole stream, plus an absolute anchor w_0 == G(SEED).
  * This is stronger than the round tool: it checks EVERY byte of EVERY TCP
    segment (per-segment absolute offset), flags any byte mismatch, counts
    duplicate/overlapping segments and byte-level holes, and computes the
    connection's absolute stream length from seq numbers.
Usage: k0_verify.py <arm-tag> <pcap files...>
"""
import struct, sys, os
import numpy as np

M64 = (1 << 64) - 1
SEED = 0x9E3779B97F4A7C15

# ---------------- GF(2) linear map machinery ----------------
def step_bits(bits):
    """Apply f (xorshift) to a single state represented as a python int;
    bits = the state value; return f(bits)."""
    x = bits
    x ^= (x << 13) & M64
    x ^= x >> 7
    x ^= (x << 17) & M64
    return x & M64

def seq_generator(n, start_steps=0):
    """Straight sequential generator (for small n + cross-checks)."""
    s = SEED
    for _ in range(start_steps):
        s = step_bits(s)
    out = bytearray(n)
    for i in range(n):
        out[i] = (s >> 24) & 0xFF
        s = step_bits(s)
    return bytes(out)

def build_F():
    """64x64 bit matrix of f: F[i,j] = coeff of input bit j in output bit i."""
    F = np.zeros((64, 64), dtype=np.uint8)
    for j in range(64):
        e = 1 << j
        (f,) = (step_bits(e),)
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

def inv_gf2(A):
    """Gauss-Jordan inverse over GF(2); None if singular."""
    n = 64
    M = np.concatenate([A.copy(), np.eye(n, dtype=np.uint8)], axis=1)
    for col in range(n):
        piv = None
        for r in range(col, n):
            if M[r, col]:
                piv = r
                break
        if piv is None:
            return None
        if piv != col:
            M[[col, piv]] = M[[piv, col]]
        for r in range(n):
            if r != col and M[r, col]:
                M[r] ^= M[col]
    return M[:, n:]

def apply_matrix_batch(M, vbits):
    """M: (64,64) uint8 GF(2); vbits: (N,64) uint8 -> (N,64) uint8."""
    out = np.zeros((vbits.shape[0], 64), dtype=np.uint8)
    # chunk to keep memory sane
    CH = 1 << 20
    for st in range(0, vbits.shape[0], CH):
        blk = vbits[st:st + CH].astype(np.uint32)
        out[st:st + CH] = (blk @ M.astype(np.uint32).T % 2).astype(np.uint8)
    return out

def bytes_to_bits(buf):
    """buf: (N,) uint8 of stream bytes in groups of 8 -> (N/8, 64) bit array,
    bit (8j+b) = bit b of byte j."""
    nb = len(buf) // 8
    arr = np.frombuffer(buf[:nb * 8], dtype=np.uint8).reshape(nb, 8)
    bits = np.zeros((nb, 64), dtype=np.uint8)
    for j in range(8):
        for b in range(8):
            bits[:, 8 * j + b] = (arr[:, j] >> b) & 1
    return bits

def build_G(F):
    """G maps state -> 8 stream bytes (as 64 bits with the bytes_to_bits layout)."""
    G = np.zeros((64, 64), dtype=np.uint8)
    powers = [np.eye(64, dtype=np.uint8)]
    for _ in range(7):
        powers.append(matmul_gf2(powers[-1], F))
    for j in range(8):
        Fj = powers[j]  # columns: Fj[:, k] = f^j(e_k)
        for b in range(8):
            # output bit (8j+b) = bit (24+b) of f^j(s)
            G[8 * j + b, :] = Fj[24 + b, :]
    return G

def bits_to_bytes(bits):
    """Inverse of bytes_to_bits for compare (N,64)->(N,8) bytes."""
    arr = np.zeros((bits.shape[0], 8), dtype=np.uint8)
    for j in range(8):
        for b in range(8):
            arr[:, j] |= (bits[:, 8 * j + b] << b)
    return arr

# ---------------- pcap parsing ----------------
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
    if len(eth) < 34:
        return None
    if eth[12] != 0x08 or eth[13] != 0x00:
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
    BOARD_IP = "192.168.100.2"
    SPORT = 8080
    conns = {}   # dport -> list of (seq, payload)  (board->peer data segments)
    order = []   # dport first-seen order
    flags_seen = {}  # dport -> flag histogram
    total_pkts = 0
    for p in files:
        for data in iter_packets(p):
            r = parse_tcp(data)
            if r is None:
                continue
            src, sport, dport, seq, flags, pl = r
            total_pkts += 1
            if src != BOARD_IP or sport != SPORT:
                continue
            d = dport
            if d not in conns:
                conns[d] = []
                order.append(d)
                flags_seen[d] = {}
            flags_seen[d][flags] = flags_seen[d].get(flags, 0) + 1
            if pl:
                conns[d].append((seq, pl))
    print(f"# arm={arm} files={len(files)} total_pkts={total_pkts} conns={len(conns)}")

    F = build_F()
    A = matpow_gf2(F, 8)
    G = build_G(F)
    R = inv_gf2(G)
    print(f"# G invertible: {R is not None}")
    anchor_vec = np.zeros((1, 64), dtype=np.uint8)
    s = SEED
    for j in range(8):
        for b in range(8):
            anchor_vec[0, 8 * j + b] = ((s >> 24) >> b) & 1
        s = step_bits(s)
    # sanity: G*(SEED bits) == anchor_vec
    seed_bits = np.array([[(SEED >> k) & 1 for k in range(64)]], dtype=np.uint8)
    chk = apply_matrix_batch(G, seed_bits)
    assert (chk == anchor_vec).all(), "G/anchor construction self-check FAILED"
    # cross-check seq_generator head
    head = seq_generator(64)
    assert bytes(head) == bytes(bits_to_bytes(anchor_vec).reshape(-1)), "seq_generator vs G mismatch"
    print("# self-checks: G*(SEED)==anchor, seq_generator==G OK")

    base_seq = None
    results = []
    for d in order:
        segs = conns[d]
        if not segs:
            print(f"== CONN dport={d} == NO_PAYLOAD (flags={flags_seen[d]})")
            continue
        seqs = [s for s, _ in segs]
        base = min(seqs)
        spans = []
        for s, pl in segs:
            o = (s - base) & 0xFFFFFFFF
            spans.append((o, pl))
        n = max(o + len(pl) for o, pl in spans)
        # coverage
        cover = np.zeros(n + 1, dtype=np.int8)
        holes = []
        dup_bytes = 0
        dup_mismatch = 0
        mism_pos = []
        # build buffer with FIRST-writer-wins and record conflicts
        buf = np.zeros(n, dtype=np.uint8)
        filled = np.zeros(n, dtype=bool)
        for o, pl in sorted(spans, key=lambda x: x[0]):
            L = len(pl)
            seg = np.frombuffer(pl, dtype=np.uint8)
            ov = filled[o:o + L] & (buf[o:o + L] != seg)
            if ov.any():
                dup_mismatch += int(ov.sum())
                if not mism_pos:
                    first = o + int(np.argmax(ov))
                    mism_pos.append(first)
            new = ~filled[o:o + L]
            dup_bytes += int((~new & (buf[o:o + L] == seg)).sum())
            buf[o:o + L] = np.where(new, seg, buf[o:o + L])
            filled[o:o + L] = True
        hole_cnt = int((~filled).sum())
        # vectorized phase check on the merged buffer
        nb = n // 8
        rem = n - nb * 8
        v = bytes_to_bits(buf[:nb * 8])
        # anchor: word 0 == G(SEED)
        ok_anchor = bool((v[0] == anchor_vec[0]).all()) if nb >= 1 else None
        # chain: w_{k+1} == G(A(R(w_k)))
        chain_bad = -1
        if nb >= 2 and R is not None and ok_anchor:
            s_k = apply_matrix_batch(R, v[:-1])
            s_next = apply_matrix_batch(A, s_k)
            w_pred = apply_matrix_batch(G, s_next)
            diff = (w_pred != v[1:]).any(axis=1)
            bad = np.nonzero(diff)[0]
            if len(bad):
                chain_bad = int(bad[0]) + 1  # word index
        # direct first-32B comparison against a freshly generated prefix
        headref = seq_generator(64)
        head_ok32 = bytes(buf[:32]) == headref[:32]
        # first mismatch scan (sequential, only up to first bad word, cheap)
        fm = -1
        if ok_anchor and chain_bad < 0 and rem == 0 and hole_cnt == 0 and not mism_pos:
            fm = -1
        else:
            # locate first mismatch vs generated pattern (generate up to n, chunked)
            gen = seq_generator(min(n, 1 << 22))  # first 4MB suffices for phase-0 locate
            a = np.frombuffer(bytes(buf[:len(gen)]), dtype=np.uint8)
            b = np.frombuffer(gen, dtype=np.uint8)
            d2 = np.nonzero(a != b)[0]
            fm = int(d2[0]) if len(d2) else (-1 if len(gen) == n else -2)
        results.append((d, segs, n, base, hole_cnt, dup_bytes, dup_mismatch,
                        ok_anchor, chain_bad, head_ok32, fm, mism_pos))
        print(f"== CONN dport={d} segs={len(segs)} n={n} hole_bytes={hole_cnt} "
              f"dup_bytes={dup_bytes} dup_payload_conflicts={dup_mismatch} "
              f"anchor_w0_ok={ok_anchor} chain_bad_word={chain_bad} head32_ok={head_ok32} first_mismatch={fm}")
        if mism_pos:
            print(f"   conflict_positions(first)={mism_pos}")

if __name__ == "__main__":
    main()
