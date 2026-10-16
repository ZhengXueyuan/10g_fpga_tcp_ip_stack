// c1_align.cpp -- offline byte-exact recompute for the C1 round (读数 B).
//
//   Semantics = align_check2.py (K0 / breaks) BUT with the 4 MB head limit removed:
//   K0 is found by stepping the LFSR from SEED at M^8 rate (8 bytes/iteration,
//   Tw table = p7b_pattern.h's constexpr table math, reimplemented inline so the
//   file is self-contained).  GB-scale offsets cost seconds.
//
//   Per dump file (= first ~64 KB of the raw byte stream of one candidate
//   connection, produced by p7b_tcp_churn --dump-prefix-dir):
//     K0       = absolute stream offset (bytes since SEED) of dump[0], or
//                NOTFOUND if no alignment within the scan bound
//     breaks   = number of stream discontinuities found inside the dump
//                (each break is re-aligned: small-jump window first, then a
//                restart (needle) search)
//     verified_prefix = bytes from dump[0] that are byte-exact pattern bytes
//                       (with the segment structure accounted for)
//
//   --selftest: positive controls incl. GB-scale offsets + negative + restart
//   -- max_scan defaults to 16e9 bytes (stream total measured ~9.8 GB).
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

static const uint64_t P7B_SEED = 0x9E3779B97F4A7C15ull;

static inline constexpr uint64_t xs_next(uint64_t s) {
    s ^= s << 13;
    s ^= s >> 7;
    s ^= s << 17;
    return s;
}

// M^8 tables (identical math to peer p7b_pattern.h; Tw packs byte j at bits 8j..8j+7)
struct L8 { uint64_t Tj[8][256]; uint64_t Tw[8][256]; };
static inline constexpr L8 build_l8() {
    L8 t{};
    for (int p = 0; p < 8; p++)
        for (int v = 0; v < 256; v++) {
            uint64_t s = (uint64_t)v << (8 * p), w = 0;
            for (int j = 0; j < 8; j++) {
                w |= (uint64_t)(uint8_t)(s >> 24) << (8 * j);
                s = xs_next(s);
            }
            t.Tj[p][v] = s; t.Tw[p][v] = w;
        }
    return t;
}
static constexpr L8 L8T = build_l8();

static inline uint64_t load_le8(const uint8_t *p) {
    uint64_t u; memcpy(&u, p, 8); return u;
}
static inline uint64_t step8_out(uint64_t st) {
    return L8T.Tw[0][st & 0xFF] ^ L8T.Tw[1][(st >> 8) & 0xFF] ^ L8T.Tw[2][(st >> 16) & 0xFF] ^
           L8T.Tw[3][(st >> 24) & 0xFF] ^ L8T.Tw[4][(st >> 32) & 0xFF] ^ L8T.Tw[5][(st >> 40) & 0xFF] ^
           L8T.Tw[6][(st >> 48) & 0xFF] ^ L8T.Tw[7][(st >> 56) & 0xFF];
}
static inline uint64_t step8_next(uint64_t st) {
    return L8T.Tj[0][st & 0xFF] ^ L8T.Tj[1][(st >> 8) & 0xFF] ^ L8T.Tj[2][(st >> 16) & 0xFF] ^
           L8T.Tj[3][(st >> 24) & 0xFF] ^ L8T.Tj[4][(st >> 32) & 0xFF] ^ L8T.Tj[5][(st >> 40) & 0xFF] ^
           L8T.Tj[6][(st >> 48) & 0xFF] ^ L8T.Tj[7][(st >> 56) & 0xFF];
}

static const uint8_t NEEDLE[32] = {
    0x7F,0x0B,0x02,0xE5,0x36,0xA1,0x4E,0xD6,0x1A,0xB0,0x49,0xB8,0x56,0xAD,0xD6,0x3F,
    0xFC,0x7D,0x55,0x6B,0xC8,0x6D,0x9A,0x9C,0x82,0xED,0xC1,0xCD,0x69,0x69,0x98,0x6C };

// step the generator `n` bytes from state st (returns state after n outputs consumed)
static uint64_t skip(uint64_t st, uint64_t n) {
    uint64_t i = 0;
    for (; i + 8 <= n; i += 8) st = step8_next(st);
    for (; i < n; i++) st = xs_next(st);
    return st;
}
// expected byte at current state (take-then-advance semantics)
static inline uint8_t peekb(uint64_t st) { return (uint8_t)(st >> 24); }

// find a segment start matching buf[q..q+32) by scanning pattern offsets [lo, hi)
// (byte-granular; used for break re-alignment with small windows)
static long long realign_small(const uint8_t *buf, size_t n, size_t q, uint64_t lo, uint64_t hi) {
    if (q + 32 > n) return -1;
    uint64_t st = skip(P7B_SEED, lo);
    for (uint64_t o = lo; o < hi; o++) {
        if (peekb(st) == buf[q]) {
            uint64_t s2 = st; int ok = 1;
            for (int j = 0; j < 32; j++) {
                if ((uint8_t)(s2 >> 24) != buf[q + j]) { ok = 0; break; }
                s2 = xs_next(s2);
            }
            if (ok) return (long long)o;
        }
        st = xs_next(st);
    }
    return -1;
}

struct Res { long long K0; std::vector<long long> breaks; std::vector<size_t> needle_hits; size_t verified; const char *k0tag; };

static Res analyze(const uint8_t *d, size_t n, uint64_t max_scan) {
    Res r; r.K0 = -1; r.verified = 0; r.k0tag = "scan";
    if (n < 32) { r.k0tag = "short_lt32"; return r; }
    // needle hits anywhere in dump (independent witness)
    for (size_t i = 0; i + 32 <= n; i++)
        if (memcmp(d + i, NEEDLE, 32) == 0) r.needle_hits.push_back(i);
    // scan from SEED for the first byte alignment (byte-granular: 8 bytes/step +
    // SWAR first-byte filter, then exact byte walk).  8-aligned-only scanning was
    // the round-1 bug: K0 mod 8 is arbitrary.
    uint64_t st = P7B_SEED, off = 0;
    uint64_t st_at = P7B_SEED;
    const uint64_t ONES = 0x0101010101010101ull, HIGH = 0x8080808080808080ull;
    uint64_t spread = (uint64_t)d[0] * ONES;
    bool found = false;
    while (off < max_scan && !found) {
        uint64_t W = step8_out(st);
        uint64_t x = W ^ spread;
        if (((x - ONES) & ~x & HIGH) != 0) {          // some byte of W == d[0]
            for (int j = 0; j < 8 && !found; j++) {
                if (((W >> (8 * j)) & 0xFF) != (uint64_t)d[0]) continue;
                uint64_t s2 = st;
                for (int t = 0; t < j; t++) s2 = xs_next(s2);
                if ((uint8_t)(xs_next(s2) >> 24) != d[1]) continue;   // 2nd-byte filter
                uint64_t s3 = s2; int ok = 1;
                for (int t = 0; t < 32; t++) { if ((uint8_t)(s3 >> 24) != d[t]) { ok = 0; break; } s3 = xs_next(s3); }
                if (ok) { r.K0 = (long long)(off + (uint64_t)j); st_at = s2; found = true; }
            }
        }
        st = step8_next(st); off += 8;
    }
    if (!found) { r.k0tag = "not_found_in_scan"; return r; }
    // verify forward with break re-alignment
    uint64_t curK = (uint64_t)r.K0;
    uint64_t cur = st_at;
    size_t i = 0;
    size_t last_ok = 0;
    while (i < n) {
        if (peekb(cur) == d[i]) { cur = xs_next(cur); i++; last_ok = i; continue; }
        // mismatch at i
        r.breaks.push_back((long long)i);
        if (r.breaks.size() > 8) break;
        // (a) small-jump: try offsets near curK + i (window -8192 .. +262144)
        long long base = (long long)curK + (long long)i;
        long long lo = base - 8192; if (lo < 0) lo = 0;
        long long hit = realign_small(d, n, i, (uint64_t)lo, (uint64_t)(base + 262144));
        if (hit >= 0) { curK = (uint64_t)hit; cur = skip(P7B_SEED, curK); continue; }
        // (b) restart: earliest needle at or after i
        size_t r2 = SIZE_MAX;
        for (size_t j = i; j + 32 <= n; j++)
            if (memcmp(d + j, NEEDLE, 32) == 0) { r2 = j; break; }
        if (r2 != SIZE_MAX) { curK = 0; cur = P7B_SEED; i = r2; continue; }
        // cannot re-align: stop
        break;
    }
    r.verified = last_ok;
    return r;
}

static int selftest() {
    int fail = 0;
    const size_t N = 65536;
    uint8_t *buf = (uint8_t *)malloc(N);
    // T1: offset 0
    { uint64_t st = P7B_SEED; for (size_t i = 0; i < N; i++) { buf[i] = peekb(st); st = xs_next(st); }
      Res r = analyze(buf, N, (uint64_t)1 << 40);
      int ok = (r.K0 == 0) && r.breaks.empty() && r.verified == N;
      printf("T1 off0          K0=%lld breaks=%zu verified=%zu %s\n", r.K0, r.breaks.size(), r.verified, ok ? "PASS" : "FAIL"); fail += !ok; }
    // T2: offset 4096
    { uint64_t st = skip(P7B_SEED, 4096); for (size_t i = 0; i < N; i++) { buf[i] = peekb(st); st = xs_next(st); }
      Res r = analyze(buf, N, (uint64_t)1 << 40);
      int ok = (r.K0 == 4096) && r.breaks.empty() && r.verified == N;
      printf("T2 off4096       K0=%lld breaks=%zu verified=%zu %s\n", r.K0, r.breaks.size(), r.verified, ok ? "PASS" : "FAIL"); fail += !ok; }
    // T3: GB-scale offset 2,000,000,000 (exercises the "arbitrary offset" claim)
    { uint64_t OFF = 2000000000ull; uint64_t st = skip(P7B_SEED, OFF);
      for (size_t i = 0; i < N; i++) { buf[i] = peekb(st); st = xs_next(st); }
      Res r = analyze(buf, N, 16ull * 1000 * 1000 * 1000);
      int ok = (r.K0 == (long long)OFF) && r.breaks.empty() && r.verified == N;
      printf("T3 off2e9        K0=%lld breaks=%zu verified=%zu %s\n", r.K0, r.breaks.size(), r.verified, ok ? "PASS" : "FAIL"); fail += !ok; }
    // T4: restart in the middle (second half = pattern from 0)
    { uint64_t OFF = 5000000000ull; uint64_t st = skip(P7B_SEED, OFF);
      for (size_t i = 0; i < N / 2; i++) { buf[i] = peekb(st); st = xs_next(st); }
      st = P7B_SEED; for (size_t i = N / 2; i < N; i++) { buf[i] = peekb(st); st = xs_next(st); }
      Res r = analyze(buf, N, 16ull * 1000 * 1000 * 1000);
      int ok = (r.K0 == (long long)OFF) && r.breaks.size() == 1 && r.breaks[0] == (long long)(N / 2)
               && !r.needle_hits.empty() && r.needle_hits[0] == N / 2;
      printf("T4 restart@mid   K0=%lld breaks=%zu (b0=%lld) needle_hits[0]=%zu %s\n", r.K0, r.breaks.size(),
             r.breaks.empty() ? -1 : r.breaks[0], r.needle_hits.empty() ? (size_t)-1 : r.needle_hits[0], ok ? "PASS" : "FAIL"); fail += !ok; }
    // T5: forward gap jump (+4000) at 30000
    { uint64_t OFF = 777777777ull; size_t G = 30000; size_t J = 4000;
      uint64_t st = skip(P7B_SEED, OFF);
      for (size_t i = 0; i < G; i++) { buf[i] = peekb(st); st = xs_next(st); }
      st = skip(P7B_SEED, OFF + G + J);
      for (size_t i = G; i < N; i++) { buf[i] = peekb(st); st = xs_next(st); }
      Res r = analyze(buf, N, 16ull * 1000 * 1000 * 1000);
      int ok = (r.K0 == (long long)OFF) && r.breaks.size() == 1 && r.breaks[0] == (long long)G;
      printf("T5 gap+4000@%zu  K0=%lld breaks=%zu (b0=%lld) %s\n", G, r.K0, r.breaks.size(),
             r.breaks.empty() ? -1 : r.breaks[0], ok ? "PASS" : "FAIL"); fail += !ok; }
    // T6: negative (pseudo-random non-pattern bytes, small bound)
    { uint64_t s = 0x123456789ABCDEFull; for (size_t i = 0; i < N; i++) { s ^= s << 13; s ^= s >> 7; s ^= s << 17; buf[i] = (uint8_t)s; }
      buf[0] ^= 0x5A; buf[1] ^= 0x5A; buf[2] ^= 0x5A; buf[3] ^= 0x5A;
      Res r = analyze(buf, N, 1000000ull);
      int ok = (r.K0 == -1) && !strcmp(r.k0tag, "not_found_in_scan");
      printf("T6 no_match      K0=%lld tag=%s %s\n", r.K0, r.k0tag, ok ? "PASS" : "FAIL"); fail += !ok; }
    printf("SELFTEST %s\n", fail ? "FAIL" : "PASS");
    free(buf);
    return fail ? 1 : 0;
}

int main(int argc, char **argv) {
    if (argc >= 2 && !strcmp(argv[1], "--selftest")) return selftest();
    uint64_t max_scan = 16ull * 1000 * 1000 * 1000;
    uint64_t from = 0;
    int ai = 1;
    for (;;) {
        if (argc >= ai + 2 && !strcmp(argv[ai], "--max-scan")) { max_scan = strtoull(argv[ai + 1], nullptr, 10); ai += 2; continue; }
        if (argc >= ai + 2 && !strcmp(argv[ai], "--from")) { from = strtoull(argv[ai + 1], nullptr, 10); ai += 2; continue; }
        break;
    }
    for (; ai < argc; ai++) {
        FILE *f = fopen(argv[ai], "rb");
        if (!f) { printf("FILE %s OPEN_FAIL\n", argv[ai]); continue; }
        static std::vector<uint8_t> d;
        d.resize(1 << 22);
        size_t n = fread(d.data(), 1, d.size(), f);
        fclose(f);
        if (from > n) { printf("FILE %s FROM_OOB n=%zu\n", argv[ai], n); continue; }
        const uint8_t *p = d.data() + from;
        size_t m = n - from;
        Res r = analyze(p, m, max_scan);
        printf("DUMP %s from=%llu n=%zu K0=%lld k0tag=%s breaks=%zu verified_prefix=%zu\n",
               argv[ai], (unsigned long long)from, m, r.K0, r.k0tag, r.breaks.size(), r.verified);
        if (!r.breaks.empty()) {
            printf("  break_offsets:");
            for (size_t i = 0; i < r.breaks.size(); i++) printf(" %lld", r.breaks[i]);
            printf("\n");
        }
        if (!r.needle_hits.empty()) {
            printf("  needle_hits(%zu):", r.needle_hits.size());
            for (size_t i = 0; i < r.needle_hits.size() && i < 12; i++) printf(" %zu", r.needle_hits[i]);
            printf("\n");
        }
        printf("  first16:");
        for (size_t i = 0; i < 16 && i < m; i++) printf(" %02X", p[i]);
        printf("\n");
        fflush(stdout);
    }
    return 0;
}
