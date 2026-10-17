// ===========================================================================
// p7b_tcp_churn_v3.cpp -- C1/P-3 对端工具 **v3 = 全流滚动针扫描**（2026-10-17）
//
// 这是**新件**：`p7b_tcp_churn.cpp`（v2，C1 候选工具）**一个字节未改**。
// 部署名 `p7b_tcp_churn_v3` 与现役 8 个产物 + v2 不重名。
//
// 规格出处 = `_proj_10g/notes/p9_p3_boost_design_20261017/README_FOR_TL.md` §4.1-A
//   （Q2 判据：**"候选连接全流无针" + "前持有者全流扫描的最后一个重启位置"**）。
//   v2 只扫每连接**首 `--scan-bytes`（默认 4 KB）**；v3 把同一根 32 B 针扫到**整条流**上
//   （跨 recv chunk 保留 31 B 重叠）—— 这是 Q2 的承重件：`hits==0` ⇒ **该连接全流无重启**，
//   而不是"首 4 KB 无重启"。
//
// ---------------------------------------------------------------------------
// 本件相对 v2 的**行为增量**（逐条；其余连接/建连/poll/落盘/报告语义逐字保留）:
//
//  A) **全流滚动针扫描**（`--scan-all 1`，默认开；`--scan-all 0` 关闭）
//     * 每连接收到的**每一个字节**都过滚动扫描；32 B 针由 `P7bPat(0).fill()` 生成
//       （**不手抄常量**；`pattern[0]=0x7F` = SEED[31:24]，⛔ **不是 0x9E** —— 见 v2 ERRATA）。
//     * 跨 chunk：保留**最后 31 B** 作为下一块的重叠；每个出现**只计一次**
//       （判据：整针只在"尾字节落入本 chunk"时记账；完全落在旧数据里的出现已在上一块记过）。
//     * 记账：`hits`（总次数）、`first_needle`、`last_needle`、前 `--needle-max` 条的偏移列表
//       （`CHURN_NEEDLES` 行）、`needle_trunc`（列表溢出）。
//     * **内存上界 = O(31 B + needle_max×8 B) / 连接** —— 流本身**不缓存**（有界缓冲，
//       不是队列）；不清空、不回放、不重排。
//     * 复杂度 = 期望 O(n)（`memchr(needle[0])` 过滤 + 候选处 32 B `memcmp`）；
//       最坏 O(32n)（全流每个字节都是 `0x7F` 的病态输入）。**不依赖**图案相位已知。
//
//  B) **M⁸ lane-parallel 相位连续性扫描**（`--verify-stream 1`，默认**关**；`--check seq|lane8`）
//     * 这是"任意偏移的**字节流断点**"那一半仪器：把连接流当成**某一条**连续图案流
//       （相位未知）来跟踪；相位一旦断开（重启/跳变/字节损坏）⇒ 记 `vbreaks` + 首次/末次
//       断点偏移，然后**重新同步**（resync）后继续。
//     * **默认关**的理由 = 与 C1b2 臂（v2）保持**读速可比**（设计件 §5-U7 的 `--scan-all`
//       读速影响仍未测；再加一层全流校验会污染"事件率"读数）。要用 M⁸ 臂时显式开。
//     * 加速路径 = `p7b_pattern.h` 的 `P7bPat::check_lane8`（M⁸ 表，8 字节/步）；
//       **逐字节对照臂 = `check_seq`**（`--check seq`，默认 = 历史已上板验过的路径）。
//       两条路径的**逐位等价**由 `--selftest-equiv`（头文件自带，表重建 + 8 MiB+5 长序列 +
//       6 点注入 + 跨块状态 + 分派开关）**实测自证**；本件另加 `--selftest-verify` 证明
//       多 chunk + resync 路径上两模式读数逐位相同。
//     * **stream resync 的数学**（本件新增，自检覆盖）：
//         连续 8 个输出字节的映射在 GF(2) 上**秩只有 63（不可逆）**；**9 个字节秩 64**
//         （实测，`--selftest-verify` 会重算）。因此从 9 B 反解 64 位状态（选定的 64 个
//         输出位 + 8 个校验位），再用**下 8 B**（M⁸ 一步）验证 ⇒ 17 B 窗口把误同步率压到
//         ~2⁻⁷²。⛔ 不是"看着像就认"：9 B 的 8 个冗余位 + 8 B 的 64 位校验都必须命中。
//     * 非图案数据（找不到合法相位）⇒ 逐字节 resync 搜索有**硬预算**
//       `--verify-degrade-bytes`（默认 1 MiB）⇒ 超限置 `vdegraded=1` 并**停止该连接**的
//       校验（针扫描继续）—— 保证最坏情况有界，不会把 CPU 拖死。
//
//  C) **输出行 = 下游接口（只追加，不改名/不改序）**
//     * `CHURN_OPTS` **逐字未动**（77 判据里的 `T1_opts_line` 是整行 grep 断言）。
//     * 每连接行前 13 个字段（`conn= bytes= restart@off= idle_ms= state= why= why_str=
//       closed_by= reads= scan_bytes= prefix_bytes= dur_ms= estab_ms= last_rx_ms= CPU_FREQ_KHZ=`）
//       **逐字保留**；新字段**一律追加在 `CPU_FREQ_KHZ=` 之后**。
//     * `CHURN_SUM` 既有键**逐字保留**；新键追加在行尾。
//     * `CHURN_T` 既有键保留；行尾追加 `scan_hits=` / `vbreaks=`。
//     * 新增独立行：`CHURN_SCAN_OPTS` / `CHURN_NEEDLES` / `CHURN_VBREAKS`（不挤进既有行）。
//     * 退出码**三条件语义逐字保留**：0 = 跑完 ∧ 有连接 ∧ 无 dump 失败；1 = 上述任一不成立；
//       2 = 用法/环境错。⛔ `needle_trunc` / `vdegraded` **不改变 RC**（它们是**声明过的
//       读数边界**，不是跑失败；要判"数据够不够"由下游看见证字段）。
//
// ---------------------------------------------------------------------------
// 已知坑（必须规避/文档明示）:
//   * `--maxbytes 0`（**本工具没有这个参数**；`p7b_tcp_sink` 的坑）= "不是无限，是立即
//     退出 RC=1"。v3 不要照搬；未知参数一律 RC=2（响亮）。
//   * `--seconds` **只停"新建连接"**，不终止已在跑的连接（它们继续读干到 `--hold-s` 结束/
//     进程退出；退出时内核会对每条已建立连接发 1 个 FIN —— 真臂请用 `--hold-s` 给板侧
//     收数留窗）。
//   * `cmd /c` vs `cmd //c`（**条件式陷阱**）：Git Bash 下未加 `MSYS_NO_PATHCONV=1` 时
//     `cmd /c` 的 `/c` 会被改写成 `C:/` ⇒ **bat 静默不执行**，而你读到的 stdout 可能是
//     **上一 session 的陈旧件**。判据 = **mtime = 本次时刻 + 本次独有字符串**。
//     ⚠️ `MSYS_NO_PATHCONV=1` 与 `cmd //c` 并用会**互相抵消**（静默不执行）。
//   * 部署/重编必须保持源文件名 `p7b_tcp_churn_v3.cpp`（`.symtab` 的 `STT_FILE` 进产物
//     ⇒ 改名换 md5；BUILD.md §3b）。
//
// 编译（部署口径 = `_proj_10g/notes/p7b_affinity/BUILD.md` §2，与其它工具逐字同一条）:
//   g++ -O3 -pthread -o p7b_tcp_churn_v3 p7b_tcp_churn_v3.cpp
//
// ⛔ 本件不下 PASS/FAIL 裁定；自检里的 "PASS/FAIL" 只是**工具自身**的判据行。
// ===========================================================================
#include "p7b_pattern.h"
#include "p7b_affinity.h"
#include "p7b_io.h"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <poll.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

// ===========================================================================
// 常量
// ===========================================================================
static const size_t V3_NEEDLE_LEN = 32;          // 与 v2 同长（ERRATA: pattern[0]=0x7F）
static const size_t V3_NCARRY     = V3_NEEDLE_LEN - 1;   // 31 B 跨 chunk 重叠
static const size_t V3_VCARRY     = 16;          // 校验器跨 chunk 保留（resync 需 17 B）
static const size_t V3_RSYNC_NEED = 17;          // 9 B 反解 + 8 B M⁸ 验证
static const long long V3_ULIMIT_NEED = 16384;

enum { ST_CONNECTING = 0, ST_ESTAB = 1, ST_CLOSED = 2 };
enum { CL_NONE = 0, CL_SAFE = 1, CL_EOF = 2, CL_RESET = 3, CL_ERR = 4, CL_CONNFAIL = 5 };

// ===========================================================================
// 基础工具
// ===========================================================================
static uint32_t v3_fnv1a32(const uint8_t *p, size_t n) {
    uint32_t h = 2166136261u;
    for (size_t i = 0; i < n; i++) { h ^= (uint32_t)p[i]; h *= 16777619u; }
    return h;
}

static void v3_hex(const uint8_t *p, size_t n, char *out) {
    for (size_t i = 0; i < n; i++) sprintf(out + 3 * i, "%02X ", p[i]);
    out[3 * n] = '\0';
}

// 朴素全流扫描（**只用于自检的独立参照实现**；生产路径不用）
static long long v3_scan_naive(const uint8_t *buf, size_t n,
                               const uint8_t *needle, size_t nlen) {
    if (n < nlen) return -1;
    for (size_t i = 0; i + nlen <= n; i++) {
        if (buf[i] != needle[0]) continue;
        if (memcmp(buf + i, needle, nlen) == 0) return (long long)i;
    }
    return -1;
}

// v2 的**首窗**扫描器（语义逐字保留；77 判据里的 11 条单测跑的就是它）
static long long v3_scan_first(const uint8_t *buf, size_t n,
                               const uint8_t *needle, size_t nlen) {
    if (n < nlen) return -1;
    for (size_t i = 0; i + nlen <= n; i++) {
        if (buf[i] != needle[0]) continue;
        if (memcmp(buf + i, needle, nlen) == 0) return (long long)i;
    }
    return -1;
}

// ===========================================================================
// 全流滚动针扫描器
//   * 每连接状态 = 31 B 重叠 + 计数 + **有界**偏移列表（懒分配）
//   * 记账判据（防重复/防漏）:
//       - 边界块（carry + 本 chunk 的前 31 B）：只记"起点在 carry 里"（g < base）且
//         整针已完整的出现；起点在 chunk 里的由正文扫描负责（31 B 的临时窗装不下
//         32 B 的正文针 ⇒ 结构性无重复）。
//       - 正文档：记所有 i+32 <= n 的出现。
//       - 一个出现只会在它**最后一个字节到达**的那次 feed 里被记一次。
// ===========================================================================
struct V3NeedleScan {
    uint8_t carry[V3_NCARRY];
    size_t  carry_len;
    long long hits;          // 总出现次数（不受列表容量限制）
    long long first;         // 首次偏移（-1 = 无）
    long long last;          // 末次偏移（-1 = 无）
    long long *offs;         // 前 stored 条偏移（懒分配）
    long long cap;           // = needle_max
    long long stored;
    int trunc;               // 1 = 出现次数 > cap（偏移列表不完整）
    V3NeedleScan()
        : carry_len(0), hits(0), first(-1), last(-1), offs(NULL), cap(0), stored(0),
          trunc(0) { memset(carry, 0, sizeof(carry)); }
};

static void v3_needle_record(V3NeedleScan &s, long long g) {
    s.hits++;
    if (s.first < 0) s.first = g;
    s.last = g;
    if (s.stored < s.cap) {
        if (!s.offs) {
            // 懒分配：0 字节流连接不花这 512 B（与 prefix 的懒分配同纪律）
            s.offs = (long long *)malloc((size_t)s.cap * sizeof(long long));
            if (!s.offs) p7b_io_die("malloc(needle_offs)");
        }
        s.offs[s.stored++] = g;
    } else {
        s.trunc = 1;
    }
}

static void v3_needle_free(V3NeedleScan &s) {
    free(s.offs);
    s.offs = NULL;
    s.cap = s.stored = 0;
}

// 一次 feed：p[0..n) 的全局起点 = base
static void v3_needle_feed(V3NeedleScan &s, const uint8_t *p, size_t n,
                           long long base, const uint8_t *needle) {
    if (n == 0) return;

    // ---- 1) 边界块：carry（≤31 B）+ 本 chunk 前 ≤31 B ----
    if (s.carry_len > 0) {
        uint8_t tmp[V3_NCARRY + V3_NCARRY];
        size_t take = (n < V3_NCARRY) ? n : V3_NCARRY;
        memcpy(tmp, s.carry, s.carry_len);
        memcpy(tmp + s.carry_len, p, take);
        size_t tl = s.carry_len + take;
        if (tl >= V3_NEEDLE_LEN) {
            size_t lim = tl - V3_NEEDLE_LEN;
            for (size_t j = 0; j <= lim; j++) {
                if (tmp[j] != needle[0]) continue;
                if (memcmp(tmp + j, needle, V3_NEEDLE_LEN) != 0) continue;
                long long g = base - (long long)s.carry_len + (long long)j;
                if (g < base) v3_needle_record(s, g);   // 起点在 carry 里
            }
        }
    }

    // ---- 2) 正文档：所有整针落在本 chunk 内的出现 ----
    if (n >= V3_NEEDLE_LEN) {
        size_t limit = n - V3_NEEDLE_LEN;               // 最大起始下标（含）
        size_t i = 0;
        while (i <= limit) {
            const uint8_t *q = (const uint8_t *)memchr(p + i, needle[0], limit - i + 1);
            if (!q) break;
            size_t j = (size_t)(q - p);
            // 第二字节预过滤（q[1] 安全：j <= n-32 ⇒ j+1 < n）
            if (q[1] == needle[1] && memcmp(q, needle, V3_NEEDLE_LEN) == 0)
                v3_needle_record(s, base + (long long)j);
            i = j + 1;
        }
    }

    // ---- 3) 更新 carry = 流的最后 ≤31 B ----
    if (n >= V3_NCARRY) {
        memcpy(s.carry, p + n - V3_NCARRY, V3_NCARRY);
        s.carry_len = V3_NCARRY;
    } else {
        size_t keep = V3_NCARRY - n;
        if (keep > s.carry_len) keep = s.carry_len;
        memmove(s.carry, s.carry + s.carry_len - keep, keep);
        memcpy(s.carry + keep, p, n);
        s.carry_len = keep + n;
    }
}

// ===========================================================================
// 校验器（相位连续性）：M⁸ lane-parallel 路径 + seq 对照臂
// ===========================================================================

// 9 字节输出 → 64 位状态的反解表（运行时建一次；`--selftest-verify` 重新验证）
struct V3Inv { uint64_t B[64]; int ok; };
static V3Inv g_v3inv = {{0}, 0};

// 从状态 s 起算的 9 个输出字节（gen_byte = s[31:24]，先取后推进）
static void v3_out9(uint64_t s, uint8_t o[9]) {
    for (int k = 0; k < 9; k++) {
        o[k] = (uint8_t)(s >> 24);
        s = p7b_xs_next(s);
    }
}

// 选定的 64 个输出位：row 0..61 + row 63 + row 64（row 62 = 冗余校验位之一）
static uint64_t v3_sel_bits(const uint8_t *p) {
    uint64_t w = p7b_load_le8(p);
    return (w & 0x3FFFFFFFFFFFFFFFull)          // rows 0..61
         | (((w >> 63) & 1ull) << 62)           // row 63
         | (((uint64_t)(p[8] & 1u)) << 63);     // row 64
}

static uint64_t v3_decode_state(uint64_t sel) {
    uint64_t s = 0;
    while (sel) {
        int i = __builtin_ctzll(sel);
        s ^= g_v3inv.B[i];
        sel &= sel - 1;
    }
    return s;
}

// 从 9 B 反解 + 用 9 B 自身校验（8 个冗余位）；成功回带"9 步后的状态"
static int v3_state_from9(const uint8_t *p, uint64_t *s9_out) {
    uint64_t s = v3_decode_state(v3_sel_bits(p));
    uint8_t o[9];
    uint64_t t = s;
    for (int k = 0; k < 9; k++) { o[k] = (uint8_t)(t >> 24); t = p7b_xs_next(t); }
    if (memcmp(o, p, 9) != 0) return -1;        // 冗余位不成立 ⇒ 不是合法相位
    *s9_out = t;
    return 0;
}

static inline uint64_t v3_m8_out(uint64_t s) {
    return P7B_L8.Tw[0][(s      ) & 0xFF] ^ P7B_L8.Tw[1][(s >>  8) & 0xFF] ^
           P7B_L8.Tw[2][(s >> 16) & 0xFF] ^ P7B_L8.Tw[3][(s >> 24) & 0xFF] ^
           P7B_L8.Tw[4][(s >> 32) & 0xFF] ^ P7B_L8.Tw[5][(s >> 40) & 0xFF] ^
           P7B_L8.Tw[6][(s >> 48) & 0xFF] ^ P7B_L8.Tw[7][(s >> 56) & 0xFF];
}

static inline uint64_t v3_m8_next(uint64_t s) {
    return P7B_L8.Tj[0][(s      ) & 0xFF] ^ P7B_L8.Tj[1][(s >>  8) & 0xFF] ^
           P7B_L8.Tj[2][(s >> 16) & 0xFF] ^ P7B_L8.Tj[3][(s >> 24) & 0xFF] ^
           P7B_L8.Tj[4][(s >> 32) & 0xFF] ^ P7B_L8.Tj[5][(s >> 40) & 0xFF] ^
           P7B_L8.Tj[6][(s >> 48) & 0xFF] ^ P7B_L8.Tj[7][(s >> 56) & 0xFF];
}

// 17 B 窗口 resync：9 B 反解 + 下 8 B 的 M⁸ 一步验证
static int v3_resync_at(const uint8_t *p, size_t avail, uint64_t *state_out) {
    if (avail < V3_RSYNC_NEED) return -1;
    uint64_t s9 = 0;
    if (v3_state_from9(p, &s9) != 0) return -1;
    if (v3_m8_out(s9) != p7b_load_le8(p + 9)) return -1;
    *state_out = v3_m8_next(s9);
    return 0;
}

// 建 64×64 GF(2) 逆表（只做一次；失败 = `--verify-stream 1` 的用法/环境错）
static int v3_inv_init(void) {
    if (g_v3inv.ok) return 0;

    // rowmask[r] = { j : 状态=1<<j 时第 r 个输出位为 1 }，r = 0..71（9 B）
    uint64_t rowmask[72];
    memset(rowmask, 0, sizeof(rowmask));
    for (int j = 0; j < 64; j++) {
        uint8_t o[9];
        v3_out9(1ull << j, o);
        for (int r = 0; r < 72; r++)
            if ((o[r >> 3] >> (r & 7)) & 1u) rowmask[r] |= (1ull << j);
    }
    static const int sel[64] = {
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
        16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
        32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47,
        48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 63, 64
    };
    uint64_t L[64], R[64];
    for (int i = 0; i < 64; i++) { L[i] = rowmask[sel[i]]; R[i] = 1ull << i; }
    for (int col = 0; col < 64; col++) {
        int pvt = -1;
        for (int i = col; i < 64; i++) if ((L[i] >> col) & 1ull) { pvt = i; break; }
        if (pvt < 0) { g_v3inv.ok = 0; return -1; }
        if (pvt != col) { uint64_t t = L[col]; L[col] = L[pvt]; L[pvt] = t;
                          t = R[col]; R[col] = R[pvt]; R[pvt] = t; }
        for (int i = 0; i < 64; i++) {
            if (i == col) continue;
            if ((L[i] >> col) & 1ull) { L[i] ^= L[col]; R[i] ^= R[col]; }
        }
    }
    for (int i = 0; i < 64; i++) if (L[i] != (1ull << i)) { g_v3inv.ok = 0; return -1; }
    // ⚠️ Gauss-Jordan 后 `R[i]` 是逆矩阵的**行 i**；decode 需要的是**列 i**
    //    (`B[i]` = 输出位 i 对 64 位状态的贡献)。直接 `B[i]=R[i]` 会把矩阵转置 ⇒
    //    基向量 0/64（本轮自检实测踩到）。这里显式转置。
    for (int i = 0; i < 64; i++) {
        uint64_t col = 0;
        for (int r = 0; r < 64; r++)
            if ((R[r] >> i) & 1ull) col |= (1ull << r);
        g_v3inv.B[i] = col;
    }

    // 基向量 + 1000 个确定性随机状态的自检（表错了后面全部无意义）
    for (int j = 0; j < 64; j++) {
        uint8_t o[9];
        v3_out9(1ull << j, o);
        if (v3_decode_state(v3_sel_bits(o)) != (1ull << j)) { g_v3inv.ok = 0; return -1; }
    }
    uint64_t rng = 0x0123456789ABCDEFull;
    for (int t = 0; t < 1000; t++) {
        rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17;
        uint8_t o[9];
        v3_out9(rng, o);
        if (v3_decode_state(v3_sel_bits(o)) != rng) { g_v3inv.ok = 0; return -1; }
    }
    g_v3inv.ok = 1;
    return 0;
}

struct V3Verify {
    uint8_t  carry[V3_VCARRY];
    size_t   carry_len;
    int      synced;
    uint64_t state;            // synced 时 = 下一个未消费字节的期望状态
    long long breaks, first_break, last_break;
    long long *boffs;          // 前 bstored 条断点偏移（懒分配）
    long long bcap, bstored;
    int      btrunc;
    long long processed;       // 已"消费/检查"的连接内字节数（degraded 时冻结）
    long long unresynced;      // 自上次同步以来未同步的字节数（预算用）
    int      degraded;         // 1 = 该连接的校验已放弃（针扫描不受影响）
    V3Verify()
        : carry_len(0), synced(0), state(0), breaks(0), first_break(-1), last_break(-1),
          boffs(NULL), bcap(0), bstored(0), btrunc(0), processed(0), unresynced(0),
          degraded(0) { memset(carry, 0, sizeof(carry)); }
};

static void v3_verify_break(V3Verify &v, long long g) {
    v.breaks++;
    if (v.first_break < 0) v.first_break = g;
    v.last_break = g;
    if (v.bstored < v.bcap) {
        if (!v.boffs) {
            v.boffs = (long long *)malloc((size_t)v.bcap * sizeof(long long));
            if (!v.boffs) p7b_io_die("malloc(break_offs)");
        }
        v.boffs[v.bstored++] = g;
    } else {
        v.btrunc = 1;
    }
}

static void v3_verify_free(V3Verify &v) {
    free(v.boffs);
    v.boffs = NULL;
    v.bcap = v.bstored = 0;
}

// 在 p[0..n) 里找 resync 点；最多试 max_pos 个起点（预算硬界）。返回起点或 -1。
static long long v3_find_resync_limited(const uint8_t *p, size_t n, size_t max_pos,
                                        uint64_t *state_out) {
    if (n < V3_RSYNC_NEED) return -1;
    size_t lim = n - V3_RSYNC_NEED;                 // 最大起点（含）
    if (max_pos > 0 && lim > max_pos - 1) lim = max_pos - 1;
    for (size_t i = 0; i <= lim; i++) {
        uint64_t s = 0;
        if (v3_resync_at(p + i, n - i, &s) == 0) { *state_out = s; return (long long)i; }
    }
    return -1;
}

// 一次 feed：p[0..n)，全局起点 base
static void v3_verify_feed(V3Verify &v, const uint8_t *p, size_t n, long long base,
                           long long degrade_bytes) {
    if (v.degraded || n == 0) return;
    size_t pos = 0;
    size_t consumed = 0;                             // 本 chunk 已"处理完"的字节数
    int degraded_here = 0;

    while (pos < n) {
        if (!v.synced) {
            // ---- A) 边界块：carry + 本 chunk 前 ≤16 B（只找起点在 carry 里的窗口） ----
            if (v.carry_len > 0) {
                uint8_t tmp[V3_VCARRY + V3_VCARRY];
                size_t take = (n - pos < V3_VCARRY) ? (n - pos) : V3_VCARRY;
                memcpy(tmp, v.carry, v.carry_len);
                memcpy(tmp + v.carry_len, p + pos, take);
                size_t tl = v.carry_len + take;
                long long found = -1;
                uint64_t s17 = 0;
                if (tl >= V3_RSYNC_NEED) {
                    size_t lim = tl - V3_RSYNC_NEED;
                    for (size_t j = 0; j <= lim; j++) {
                        long long g = base + (long long)pos - (long long)v.carry_len +
                                      (long long)j;
                        if (g >= base + (long long)pos) break;   // 正文负责
                        if (v3_resync_at(tmp + j, tl - j, &s17) == 0) { found = g; break; }
                    }
                }
                if (found >= 0) {
                    long long endg = found + (long long)V3_RSYNC_NEED;
                    long long next = endg - base;            // chunk 内下标
                    if (next < 0) next = 0;
                    if (next > (long long)pos) consumed = (size_t)next;
                    v.synced = 1;
                    v.state = s17;
                    v.unresynced = 0;
                    v.carry_len = 0;
                    pos = (size_t)next;                      // 可能 == n（窗口吃到下一块）
                    continue;
                }
            }

            // ---- B) 正文档 resync 搜索（预算 = degrade_bytes − 已用） ----
            long long budget_left = degrade_bytes - v.unresynced;
            if (budget_left <= 0) {
                v.degraded = 1;
                degraded_here = 1;
                break;
            }
            size_t avail = n - pos;
            size_t max_pos = (size_t)budget_left;
            uint64_t s17 = 0;
            long long r = v3_find_resync_limited(p + pos, avail, max_pos, &s17);
            if (r >= 0) {
                size_t next = pos + (size_t)r + V3_RSYNC_NEED;
                if (next > consumed) consumed = next;
                v.synced = 1;
                v.state = s17;
                v.unresynced = 0;
                v.carry_len = 0;
                pos = next;
                continue;
            }
            // 没找到：本段全部算"未同步"，并保留最后 ≤16 B 给下一块
            long long examined = (long long)avail;
            if (examined > budget_left) examined = budget_left;
            v.unresynced += examined;
            if (consumed < pos + (size_t)examined) consumed = pos + (size_t)examined;
            if (v.unresynced >= degrade_bytes) {
                v.degraded = 1;
                degraded_here = 1;
                break;
            }
            // 扫完了本 chunk（预算没超）⇒ 保留**carry+chunk 的最后 ≤16 B**。
            // ⚠️ 小 chunk（n<16）必须与旧 carry 合并：直接覆盖会让逐字节 feed 永远
            //    攒不满 17 B 的 resync 窗口（本件 Python 镜像实测踩到：chunk=1 时
            //    synced 永远为 0）。pos>0（断点之后）时旧 carry 已清，不合并。
            {
                size_t take = (n < V3_VCARRY) ? n : V3_VCARRY;
                size_t keep_old = (pos > 0 || take >= V3_VCARRY) ? 0 : v.carry_len;
                if (keep_old > V3_VCARRY - take) keep_old = V3_VCARRY - take;
                if (keep_old)
                    memmove(v.carry, v.carry + v.carry_len - keep_old, keep_old);
                memcpy(v.carry + keep_old, p + n - take, take);
                v.carry_len = keep_old + take;
            }
            consumed = n;
            pos = n;
            break;
        }

        // ---- C) 已同步：跑 check（seq 或 lane8；分派在头文件里） ----
        P7bPat vp;
        vp.s = v.state;
        uint64_t mism = 0;
        long long f = vp.check(p + pos, n - pos, &mism);
        v.state = vp.s;
        if (f < 0) {
            consumed = n;
            pos = n;
            break;
        }
        // 相位断点：记首次失配（可能晚于真实断点 ≤ 几字节；见 README）
        long long gbreak = base + (long long)pos + f;
        v3_verify_break(v, gbreak);
        v.synced = 0;
        v.state = 0;
        v.carry_len = 0;                     // 断点之前的 carry 已无意义
        pos = pos + (size_t)f;               // 从失配字节起尝试 resync
        if (pos > consumed) consumed = pos;
        continue;
    }

    if (!degraded_here) {
        if (consumed < n) consumed = n;      // 正常走完：整块都已消费/检查
        v.processed = base + (long long)consumed;
    } else {
        v.processed = base + (long long)consumed;
    }
}

// ===========================================================================
// 自检 1/4: 图案机制（与 RTL 对齐的手算向量）
// ===========================================================================
static int v3_selftest_pattern(void) {
    return p7b_pattern_selftest("p7b_tcp_churn_v3");
}

// ===========================================================================
// 自检 2/4: 扫描器
//   ① v2 的 11 条首窗单测**逐条保留**（同名前缀 SCAN case=）
//   ② 全流滚动扫描 vs 朴素全流扫描（随机 chunk 切分 + 随机针注入）**逐位相同**
//   ③ 截断（needle_max）与边界（0/31/32 字节）读数
// ===========================================================================
static int v3_selftest_scan(void) {
    int checks = 0, fails = 0;
    uint8_t needle[V3_NEEDLE_LEN];
    { P7bPat p(0); p.fill(needle, V3_NEEDLE_LEN); }

    char hex[3 * V3_NEEDLE_LEN + 1], hex16[3 * 16 + 1];
    v3_hex(needle, V3_NEEDLE_LEN, hex);
    v3_hex(needle, 16, hex16);
    uint32_t nh = v3_fnv1a32(needle, V3_NEEDLE_LEN);
    printf("SCAN needle len=%zu fnv1a32=0x%08X\n", V3_NEEDLE_LEN, nh);
    printf("SCAN needle[0..31]  = %s\n", hex);
    printf("SCAN needle[0..15]  = %s\n", hex16);
    {
        checks++;
        const char *WANT16 = "7F 0B 02 E5 36 A1 4E D6 1A B0 49 B8 56 AD D6 3F ";
        int ok = (strcmp(hex16, WANT16) == 0);
        if (!ok) fails++;
        printf("SCAN case=needle_vs_doc_vector got=%s want=%s %s\n", hex16, WANT16,
               ok ? "PASS" : "FAIL");
    }

    uint8_t buf[8192];
    #define SCAN_CASE(NAME, EXPECT, EXPR) do { \
        long long got_ = (EXPR); checks++; \
        int ok_ = (got_ == (long long)(EXPECT)); if (!ok_) fails++; \
        printf("SCAN case=%-22s got=%-8lld want=%-8lld %s\n", NAME, got_, \
               (long long)(EXPECT), ok_ ? "PASS" : "FAIL"); } while (0)

    // ---- v2 的 11 条（逐字同构；同名前缀） ----
    memset(buf, 0xA5, sizeof(buf));
    memcpy(buf, needle, V3_NEEDLE_LEN);
    SCAN_CASE("match_at_0", 0, v3_scan_first(buf, sizeof(buf), needle, V3_NEEDLE_LEN));

    { P7bPat g(5000); g.fill(buf, 1234); }
    memcpy(buf + 1234, needle, V3_NEEDLE_LEN);
    memset(buf + 1234 + V3_NEEDLE_LEN, 0x5A, sizeof(buf) - 1234 - V3_NEEDLE_LEN);
    SCAN_CASE("match_at_1234", 1234, v3_scan_first(buf, sizeof(buf), needle, V3_NEEDLE_LEN));

    { P7bPat g(7777); g.fill(buf, 4096); }
    SCAN_CASE("no_match", -1, v3_scan_first(buf, 4096, needle, V3_NEEDLE_LEN));

    { P7bPat g(1234); g.fill(buf, 4096); }
    memcpy(buf + 4064, needle, V3_NEEDLE_LEN);
    SCAN_CASE("window_edge_in_4064", 4064,
              v3_scan_first(buf, 4096, needle, V3_NEEDLE_LEN));

    { P7bPat g(4321); g.fill(buf, 4096); }
    memcpy(buf + 4065, needle, V3_NEEDLE_LEN);
    SCAN_CASE("window_edge_out_4065", -1, v3_scan_first(buf, 4096, needle, V3_NEEDLE_LEN));
    SCAN_CASE("window_edge_out_full", 4065, v3_scan_first(buf, 4097, needle, V3_NEEDLE_LEN));

    memset(buf, 0x11, sizeof(buf));
    memcpy(buf + 100, needle, V3_NEEDLE_LEN);
    buf[100 + V3_NEEDLE_LEN - 1] ^= 0x01;
    SCAN_CASE("partial_31_of_32", -1, v3_scan_first(buf, sizeof(buf), needle, V3_NEEDLE_LEN));

    memset(buf, 0x11, sizeof(buf));
    memcpy(buf + 100, needle, V3_NEEDLE_LEN);
    buf[100 + 17] ^= 0x80;
    SCAN_CASE("flip_1bit_no_match", -1, v3_scan_first(buf, sizeof(buf), needle, V3_NEEDLE_LEN));

    memset(buf, 0xA5, sizeof(buf));
    memcpy(buf, needle, V3_NEEDLE_LEN);
    SCAN_CASE("short_window_31", -1, v3_scan_first(buf, 31, needle, V3_NEEDLE_LEN));

    memset(buf, 0x33, sizeof(buf));
    memcpy(buf, needle, V3_NEEDLE_LEN);
    memcpy(buf + 500, needle, V3_NEEDLE_LEN);
    SCAN_CASE("first_of_two_matches", 0, v3_scan_first(buf, sizeof(buf), needle, V3_NEEDLE_LEN));

    // ---- 全流滚动扫描：固定小例 ----
    {
        // 流 = 32 B 针 + 100 B 中段 + 32 B 针 => hits=2, first=0, last=132
        uint8_t s[200];
        memset(s, 0x5A, sizeof(s));
        memcpy(s, needle, 32);
        memcpy(s + 132, needle, 32);
        V3NeedleScan ns;
        ns.cap = 8;
        // 逐字节 feed（最严的跨块切分）
        for (size_t i = 0; i < sizeof(s); i++) v3_needle_feed(ns, s + i, 1, (long long)i, needle);
        int ok = (ns.hits == 2 && ns.first == 0 && ns.last == 132 && ns.stored == 2 &&
                  ns.offs[0] == 0 && ns.offs[1] == 132 && ns.trunc == 0);
        checks++; if (!ok) fails++;
        printf("SCANV3 case=bytewise_two_hits hits=%lld first=%lld last=%lld stored=%lld "
               "trunc=%d %s\n", ns.hits, ns.first, ns.last, ns.stored, ns.trunc,
               ok ? "PASS" : "FAIL");
        v3_needle_free(ns);
    }
    {
        // 针恰好跨 chunk 边界：chunk1 给 16 B、chunk2 给 16 B => 只在 chunk2 记一次
        uint8_t s[64];
        memset(s, 0x77, sizeof(s));
        memcpy(s + 10, needle, 32);
        V3NeedleScan ns;
        ns.cap = 8;
        v3_needle_feed(ns, s, 26, 0, needle);          // 针的前 16 B
        v3_needle_feed(ns, s + 26, 38, 26, needle);    // 后 16 B
        int ok = (ns.hits == 1 && ns.first == 10 && ns.stored == 1 && ns.offs[0] == 10);
        checks++; if (!ok) fails++;
        printf("SCANV3 case=split_16_16 hits=%lld first=%lld stored=%lld %s\n",
               ns.hits, ns.first, ns.stored, ok ? "PASS" : "FAIL");
        v3_needle_free(ns);
    }
    {
        // 截断：5 次出现，cap=3 => hits=5 / stored=3 / trunc=1
        uint8_t s[512];
        memset(s, 0x22, sizeof(s));
        for (int k = 0; k < 5; k++) memcpy(s + 20 + 90 * k, needle, 32);
        V3NeedleScan ns;
        ns.cap = 3;
        v3_needle_feed(ns, s, sizeof(s), 0, needle);
        int ok = (ns.hits == 5 && ns.stored == 3 && ns.trunc == 1 && ns.first == 20 &&
                  ns.last == 20 + 90 * 4);
        checks++; if (!ok) fails++;
        printf("SCANV3 case=trunc_cap3 hits=%lld stored=%lld trunc=%d first=%lld last=%lld %s\n",
               ns.hits, ns.stored, ns.trunc, ns.first, ns.last, ok ? "PASS" : "FAIL");
        v3_needle_free(ns);
    }
    {
        // 0 / 31 字节流 => 0 次（短流不是"无重启"，读数侧用 scan_state 区分）
        V3NeedleScan a, b;
        a.cap = 4; b.cap = 4;
        uint8_t s[31];
        memset(s, 0x7F, sizeof(s));
        v3_needle_feed(a, s, 0, 0, needle);
        v3_needle_feed(b, s, 31, 0, needle);
        int ok = (a.hits == 0 && b.hits == 0);
        checks++; if (!ok) fails++;
        printf("SCANV3 case=short_streams hits0=%lld hits31=%lld %s\n",
               a.hits, b.hits, ok ? "PASS" : "FAIL");
        v3_needle_free(a); v3_needle_free(b);
    }

    // ---- 随机等价：滚动扫描 vs 朴素全流（20 个确定性种子；随机 chunk 切分） ----
    {
        const size_t N = 1u << 20;              // 1 MiB
        uint8_t *s = (uint8_t *)malloc(N);
        if (!s) { printf("SCANV3 malloc fail\n"); return 1; }
        uint64_t rng = 0xC0FFEE123456789ULL;
        int eq_ok = 0, eq_n = 0;
        for (int seed = 0; seed < 20; seed++) {
            // 背景 = 若干段随机偏移的图案（中间用 0x00 断开，避免长段边界造成歧义）
            size_t o = 0;
            memset(s, 0, N);
            while (o < N) {
                rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17;
                size_t seg = 4096 + (size_t)(rng % 8192);
                if (seg > N - o) seg = N - o;
                P7bPat g(rng % 100000);
                g.fill(s + o, seg);
                o += seg;
            }
            // 注入 ≤40 处整针（分散；可能覆盖背景）
            int inj = 0;
            for (int k = 0; k < 40; k++) {
                rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17;
                size_t off = (size_t)(rng % (N - 64));
                if (off + 32 <= N) { memcpy(s + off, needle, 32); inj++; }
            }
            // 朴素参照
            std::vector<long long> want;
            for (size_t i = 0; i + 32 <= N; i++)
                if (s[i] == needle[0] && memcmp(s + i, needle, 32) == 0)
                    want.push_back((long long)i);
            // 滚动扫描（随机 chunk）
            V3NeedleScan ns;
            ns.cap = (long long)want.size() + 8;
            size_t pos = 0;
            int chunks = 0;
            while (pos < N) {
                rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17;
                size_t c = 1 + (size_t)(rng % 8192);
                if (c > N - pos) c = N - pos;
                v3_needle_feed(ns, s + pos, c, (long long)pos, needle);
                pos += c; chunks++;
            }
            int ok = (ns.hits == (long long)want.size());
            if (ok)
                for (size_t i = 0; i < want.size() && i < (size_t)ns.cap; i++)
                    if (ns.offs[i] != want[i]) { ok = 0; break; }
            if (ok && !want.empty() &&
                (ns.first != want.front() || ns.last != want.back())) ok = 0;
            eq_n++;
            if (ok) eq_ok++;
            else
                printf("SCANV3 seed=%d MISMATCH got_hits=%lld want=%zu first=%lld/%lld "
                       "last=%lld/%lld\n", seed, ns.hits, want.size(), ns.first,
                       want.empty() ? -1 : want.front(), ns.last,
                       want.empty() ? -1 : want.back());
            if (seed == 0)
                printf("SCANV3 seed=0 n=%zu chunks=%d inj=%d hits=%lld first=%lld last=%lld\n",
                       N, chunks, inj, ns.hits, ns.first, ns.last);
            v3_needle_free(ns);
        }
        checks++;
        if (eq_ok != eq_n) fails++;
        printf("SCANV3 random_equiv ok=%d/%d want=%d/%d %s\n", eq_ok, eq_n, eq_n, eq_n,
               (eq_ok == eq_n) ? "PASS" : "FAIL");
        free(s);
    }

    printf("SCAN_SELFTEST %s checks=%d fails=%d\n", fails ? "FAIL" : "PASS", checks, fails);
    #undef SCAN_CASE
    return fails ? 1 : 0;
}

// ===========================================================================
// 自检 3/4: M⁸ lane-parallel 与逐字节路径的逐位等价（头文件自带）
// ===========================================================================
static int v3_selftest_equiv(void) {
    return p7b_pattern_equiv_selftest("p7b_tcp_churn_v3");
}

// ===========================================================================
// 自检 4/4: 校验器（相位连续性）
//   ① 9 B 反解表：基向量 64/64 + 1000 随机状态
//   ② 干净长流（4 MiB+5）：随机 chunk + seq/lane8 两模式 => 0 断点、读数逐位相同
//   ③ 注入：单 bit 翻转 / 重启到偏移 0 / 相位跳到偏移 5000 => 断点偏移 = 注入点
//   ④ 非图案数据：degrade 预算生效、两模式读数一致
// ===========================================================================
static int v3_selftest_verify(void) {
    int checks = 0, fails = 0;
    if (v3_inv_init() != 0) {
        printf("VERIFY inv_init FAIL (9-byte map not invertible)\n");
        return 1;
    }
    checks++;
    printf("VERIFY inv_init rows=64 basis=64 rand=1000 OK (B[0]=0x%016llX)\n",
           (unsigned long long)g_v3inv.B[0]);

    const size_t N = (4u << 20) + 5;
    uint8_t *base = (uint8_t *)malloc(N);
    if (!base) { printf("VERIFY malloc fail\n"); return 1; }
    { P7bPat g(0); g.fill(base, N); }

    // 把整个流喂给校验器（指定 chunk 大小），返回读数
    struct VOut { long long breaks, first, last, processed; int degraded; uint64_t state; };
    auto feed_all = [&](const uint8_t *buf, size_t n, size_t chunk, int mode,
                        long long degrade_bytes) -> VOut {
        p7b_check_mode_set(mode);
        V3Verify v;
        v.bcap = 64;
        size_t pos = 0;
        while (pos < n) {
            size_t c = chunk;
            if (c > n - pos) c = n - pos;
            v3_verify_feed(v, buf + pos, c, (long long)pos, degrade_bytes);
            pos += c;
        }
        VOut o;
        o.breaks = v.breaks; o.first = v.first_break; o.last = v.last_break;
        o.processed = v.processed; o.degraded = v.degraded; o.state = v.state;
        v3_verify_free(v);
        return o;
    };
    auto same = [](const VOut &a, const VOut &b) {
        return a.breaks == b.breaks && a.first == b.first && a.last == b.last &&
               a.processed == b.processed && a.degraded == b.degraded && a.state == b.state;
    };

    // ---- ② 干净流 + 随机/极端 chunk ----
    {
        const size_t chunks[] = { 1, 7, 8, 9, 16, 17, 31, 32, 33, 4093, 65536, 1048576 };
        int ok_n = 0;
        for (size_t k = 0; k < sizeof(chunks) / sizeof(chunks[0]); k++) {
            size_t c = chunks[k];
            if (c == 1 && N > 65536) c = 1;                 // 逐字节只跑一小段? 这里仍跑全长
            // chunk=1 对 4 MiB 太慢（每次调用带 P7bPat 构造）；对该档用前 64 KiB + 尾 5 B 检查
            size_t nn = (chunks[k] == 1) ? (65536 + 5) : N;
            VOut a = feed_all(base, nn, c, P7B_CHECK_SEQ, 1 << 20);
            VOut b = feed_all(base, nn, c, P7B_CHECK_LANE8, 1 << 20);
            int ok = same(a, b) && a.breaks == 0 && a.first == -1 && a.last == -1 &&
                     a.degraded == 0 && a.processed == (long long)nn;
            checks++;
            if (ok) ok_n++;
            else fails++;
            if (k == 0 || !ok)
                printf("VERIFY clean chunk=%-8zu n=%-9zu seq=(%lld,%lld,%lld,%lld,%d) "
                       "lane8=(%lld,%lld,%lld,%lld,%d) state_eq=%d %s\n",
                       chunks[k], nn, a.breaks, a.first, a.last, a.processed, a.degraded,
                       b.breaks, b.first, b.last, b.processed, b.degraded,
                       (int)(a.state == b.state), ok ? "PASS" : "FAIL");
        }
        checks++;
        printf("VERIFY clean_all ok=%d/%zu %s\n", ok_n,
               sizeof(chunks) / sizeof(chunks[0]),
               (ok_n == (int)(sizeof(chunks) / sizeof(chunks[0]))) ? "PASS" : "FAIL");
        if (ok_n != (int)(sizeof(chunks) / sizeof(chunks[0]))) fails++;
    }

    // ---- ③ 注入三种断点 ----
    {
        struct Inj { size_t off; int kind; const char *what; };
        const Inj injs[] = {
            { 12345,  0, "single_bit_flip" },
            { 100000, 1, "restart_to_offset0" },
            { 200000, 2, "phase_jump_to_5000" },
        };
        for (size_t k = 0; k < sizeof(injs) / sizeof(injs[0]); k++) {
            uint8_t *b = (uint8_t *)malloc(N);
            memcpy(b, base, N);
            if (injs[k].kind == 0) {
                b[injs[k].off] ^= 0x01;
            } else {
                uint64_t off = (injs[k].kind == 1) ? 0 : 5000;
                P7bPat g(off);
                g.fill(b + injs[k].off, N - injs[k].off);
            }
            VOut a = feed_all(b, N, 4093, P7B_CHECK_SEQ, 1 << 20);
            VOut c = feed_all(b, N, 4093, P7B_CHECK_LANE8, 1 << 20);
            int ok = same(a, c) && a.breaks >= 1 && a.first == (long long)injs[k].off;
            checks++;
            if (!ok) fails++;
            printf("VERIFY inj %-20s off=%-7zu seq=(%lld,%lld,%lld) lane8=(%lld,%lld,%lld) "
                   "%s\n", injs[k].what, injs[k].off, a.breaks, a.first, a.last,
                   c.breaks, c.first, c.last, ok ? "PASS" : "FAIL");
            free(b);
        }
    }

    // ---- ④ 非图案数据 + degrade 预算 ----
    {
        const size_t M = (1u << 20) + 7;
        uint8_t *g = (uint8_t *)malloc(M);
        memset(g, 0xA5, M);
        const long long budget = 65536;
        VOut a = feed_all(g, M, 4093, P7B_CHECK_SEQ, budget);
        VOut b = feed_all(g, M, 4093, P7B_CHECK_LANE8, budget);
        int ok = same(a, b) && a.degraded == 1 &&
                 a.processed >= budget && a.processed <= budget + 4093;
        checks++;
        if (!ok) fails++;
        printf("VERIFY garbage budget=%lld seq=(deg=%d,proc=%lld,breaks=%lld) "
               "lane8=(deg=%d,proc=%lld,breaks=%lld) %s\n",
               budget, a.degraded, a.processed, a.breaks, b.degraded, b.processed, b.breaks,
               ok ? "PASS" : "FAIL");
        free(g);
    }

    free(base);
    p7b_check_mode_set(P7B_CHECK_SEQ);      // 自检不留副作用
    printf("VERIFY_SELFTEST %s checks=%d fails=%d\n", fails ? "FAIL" : "PASS", checks, fails);
    return fails ? 1 : 0;
}

// ===========================================================================
// 连接记录
// ===========================================================================
struct ChurnConn {
    int fd;
    int state;
    long long idx;
    int why;
    long long bytes;
    long long reads;
    double t_start, t_estab, t_last_rx;
    uint8_t *prefix;
    size_t prefix_len;
    size_t prefix_cap;
    long long restart_off;
    long long scan_n;
    int closed_by;
    int state_at_close;
    V3NeedleScan ns;
    V3Verify vs;
    ChurnConn()
        : fd(-1), state(ST_CONNECTING), idx(0), why(0), bytes(0), reads(0),
          t_start(0), t_estab(0), t_last_rx(0), prefix(NULL), prefix_len(0), prefix_cap(0),
          restart_off(-2), scan_n(0), closed_by(CL_NONE), state_at_close(ST_CONNECTING) {}
};

static const char *churn_state_str(const ChurnConn &c) {
    if (c.state == ST_CONNECTING) return "connecting";
    if (c.state == ST_ESTAB)      return "estab";
    switch (c.closed_by) {
        case CL_SAFE:     return "closed_safe";
        case CL_EOF:      return "eof";
        case CL_RESET:    return "reset";
        case CL_ERR:      return "err";
        case CL_CONNFAIL: return "connfail";
        default:          return "closed";
    }
}

// ===========================================================================
// 非阻塞 connect 起手（逐字沿用 v2 / sink 的建立序列）
// ===========================================================================
static int churn_connect_start(const struct sockaddr_in *dst, int rcvbuf, int local_port,
                               int *why, int *rcvbuf_eff) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) { *why = errno; return -1; }
    p7b_io_set_nonblock(fd);
    if (local_port > 0) {
        int one = 1;
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &one, sizeof(one));
        struct sockaddr_in la{};
        la.sin_family = AF_INET;
        la.sin_addr.s_addr = htonl(INADDR_ANY);
        la.sin_port = htons((uint16_t)local_port);
        if (bind(fd, (struct sockaddr *)&la, sizeof(la)) < 0) { *why = errno; close(fd); return -1; }
    }
    setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &rcvbuf, sizeof(rcvbuf));
    if (rcvbuf_eff) {
        int v = 0; socklen_t vl = sizeof(v);
        *rcvbuf_eff = (getsockopt(fd, SOL_SOCKET, SO_RCVBUF, &v, &vl) == 0) ? v : -1;
    }
    int r = connect(fd, (const struct sockaddr *)dst, sizeof(*dst));
    if (r == 0) return fd;
    if (errno == EINPROGRESS) return fd;
    *why = errno; close(fd); return -1;
}

// ===========================================================================
// 读干：recv 到 EAGAIN；前缀只留首 prefix_cap 字节；**全流扫描在此处逐 chunk 进行**
// ===========================================================================
static void churn_drain(ChurnConn &c, uint8_t *scratch, size_t scratch_sz, size_t prefix_cap,
                        const uint8_t *needle, bool scan_all, bool verify_stream,
                        long long degrade_bytes, long long *newest_data_idx) {
    for (;;) {
        ssize_t n = recv(c.fd, scratch, scratch_sz, 0);
        if (n > 0) {
            long long base = c.bytes;              // 本 chunk 的流内起点
            c.reads++;
            c.bytes += (long long)n;
            c.t_last_rx = p7b_io_now_s();
            if (c.idx > *newest_data_idx) *newest_data_idx = c.idx;
            if (scan_all)
                v3_needle_feed(c.ns, scratch, (size_t)n, base, needle);
            if (verify_stream)
                v3_verify_feed(c.vs, scratch, (size_t)n, base, degrade_bytes);
            if (c.prefix_len < prefix_cap) {
                if (!c.prefix) {
                    c.prefix = (uint8_t *)malloc(prefix_cap);
                    if (!c.prefix) p7b_io_die("malloc(prefix)");
                    c.prefix_cap = prefix_cap;
                }
                size_t room = c.prefix_cap - c.prefix_len;
                size_t take = ((size_t)n < room) ? (size_t)n : room;
                memcpy(c.prefix + c.prefix_len, scratch, take);
                c.prefix_len += take;
            }
            continue;
        }
        if (n == 0) {
            c.why = 0; c.closed_by = CL_EOF; c.state_at_close = c.state;
            close(c.fd); c.state = ST_CLOSED;
            return;
        }
        if (p7b_io_retryable(errno)) return;
        c.why = errno;
        c.closed_by = (errno == ECONNRESET) ? CL_RESET : CL_ERR;
        c.state_at_close = c.state;
        close(c.fd); c.state = ST_CLOSED;
        return;
    }
}

static void churn_usage(void) {
    printf(
        "p7b_tcp_churn_v3 -- C1/P-3 对端工具 v3（connect 洪流 + 持有不关 + 读干 + **全流滚动针**）\n"
        "  --host H                  默认 192.168.100.2\n"
        "  --port P                  默认 8080\n"
        "  --connect-interval-ms N   connect 节奏（默认 10 ⇒ ~100/s；必须 >= 1）\n"
        "  --seconds S               连接窗口秒数（默认 120；必须 >= 1；⚠️ 只停新建，不终止已建连接）\n"
        "  --rcvbuf B                SO_RCVBUF（默认 1048576；合法 1024..2^30；落点 = connect **之前**）\n"
        "  --safe-close              仅当**更新的连接已收到数据**后才关最旧 fd（默认关 = 永不主动 close）\n"
        "  --local-port N            connect 之前 bind 本地端口（0 = 不 bind；hold 模式下固定端口第 2 条起必失败）\n"
        "  --prefix-kb N             每连接留存前缀 KB（默认 64；合法 1..1024）\n"
        "  --scan-bytes N            首窗扫描（v2 语义；默认 4096；合法 32..prefix 字节数）\n"
        "  --dump-prefix-dir DIR     候选（restart@off=-1）首前缀落盘目录（默认无 ⇒ 不落盘，响亮提示）\n"
        "  --dump-max N              落盘上限（默认 2048；超限响亮计数）\n"
        "  --max-conns N             连接总数上限（默认 16000；`CHURN_CAP` 行响亮提示）\n"
        "  --hold-s N                逐连接行 + CHURN_SUM 打完后**继续读干** N 秒再退（给板侧收数留窗）\n"
        "\n"
        "  ---- v3 新增（全流滚动针 / 相位连续性）----\n"
        "  --scan-all 0|1            **全流滚动针扫描**（默认 1）：扫每一个收到字节，不是首 4 KB\n"
        "  --needle-max N            每连接保存的针偏移条数（默认 64；合法 0..4096；0 = 只计数）\n"
        "  --verify-stream 0|1       相位连续性校验（默认 0；开启后每 chunk 多一层全流检查）\n"
        "  --verify-degrade-bytes N  resync 预算（默认 1048576；合法 1024..2^30；超限置 vdegraded=1）\n"
        "  --break-max N             每连接保存的断点偏移条数（默认 16；合法 0..4096）\n"
        "  --check seq|lane8         校验器引擎（默认 seq = 历史已上板验过的逐字节路径；\n"
        "                            lane8 = M⁸ 表 8 字节/步；两条路径的逐位等价由 --selftest-equiv 自证）\n"
        "  --no-pin / --core N       绑核开关（p7b_affinity.h；默认自动选核，绑不上 = exit(2)）\n"
        "  --selftest                图案自检向量（p7b_pattern.h 的 RTL 对齐向量）\n"
        "  --selftest-scan           扫描器单测（v2 的 11 条 + 滚动等价/截断/边界）\n"
        "  --selftest-equiv          M⁸ lane8 vs 逐字节的逐位等价（表重建/长序列/注入/跨块）\n"
        "  --selftest-verify         校验器自检（反解表/干净流/三种注入/降级预算；seq vs lane8）\n"
        "  --selftest-all            以上四项全跑（CPU-only；不发任何网络包）\n"
        "\n"
        "  输出：CHURN_OPTS（逐字未动）/ CHURN_SCAN_OPTS（v3 新）/ CHURN_ULIMIT / CHURN_RCVBUF /\n"
        "        CHURN_NEEDLE / CHURN_TARGET / CHURN_LIMITS → CHURN_T 周期行 → 每连接\n"
        "        `CHURN conn=k bytes=… restart@off=… idle_ms=…`（既有字段不动，新字段追加在\n"
        "        CPU_FREQ_KHZ= 之后：full_scan= first_needle= hits= last_needle= scanned=\n"
        "        scan_state= needle_trunc= verify= vbreaks= vfirst_break= vlast_break=\n"
        "        vdegraded= vscanned= vmode=）→ CHURN_NEEDLES（有针时）→ CHURN_VBREAKS（有断点时）\n"
        "        → CHURN_DUMP 行 → CHURN_SUM（既有键不动，新键追加）→ CHURN_DONE\n"
        "  ⛔ 退出码：0 = 跑完 ∧ 有连接 ∧ 无 dump 失败；1 = 任一不成立；2 = 用法/环境错\n"
        "  ⛔ 本工具**没有** --maxbytes；`--seconds` 不终止已建连接；退出时内核会对每条已建立\n"
        "     连接发 1 个 FIN（真臂用 --hold-s 留窗）\n");
    printf("  restart@off（v2 语义，首 --scan-bytes 窗）: k>=1 = 偏移 k 处重启 / 0 = 偏移 0\n"
           "      （语义两义，单独计数）/ -1 = 首窗内无匹配（**旧口径候选**）/ na = 收到字节 < 32\n"
           "  全流口径（v3）: hits==0 ∧ scan_state=full ⇒ **该连接全流无重启**；\n"
           "      first_needle/last_needle = 全流首次/末次重启偏移；scan_state=none|short ⇒ 判不了\n"
           "      （短流不是\"无重启\"）；needle_trunc=1 ⇒ 偏移列表不完整（hits 计数仍完整）\n");
}

// ===========================================================================
int main(int argc, char **argv) {
    p7baff_g_want_pair = 0;
    argc = p7b_pin_cpu(argc, argv);

    const char *host = "192.168.100.2";
    int  port = 8080;
    int  interval_ms = 10;
    int  seconds = 120;
    int  rcvbuf = 1048576;
    bool safe_close = false;
    int  local_port = 0;
    const char *dump_dir = NULL;
    long dump_max = 2048;
    long prefix_kb = 64;
    long scan_bytes = 4096;
    long max_conns = 16000;
    int  hold_s = 0;

    // v3 新增
    int  scan_all = 1;
    long needle_max = 64;
    int  verify_stream = 0;
    long verify_degrade_bytes = 1048576;
    long break_max = 16;
    int  check_mode = P7B_CHECK_SEQ;

    bool selftest = false, selftest_scan = false, selftest_equiv = false;
    bool selftest_verify = false, selftest_all = false;

    for (int i = 1; i < argc; i++) {
        std::string k = argv[i];
        auto nx = [&]() -> const char * {
            if (++i >= argc) { fprintf(stderr, "missing %s\n", k.c_str()); exit(2); }
            return argv[i];
        };
        if (k == "--host") host = nx();
        else if (k == "--port") port = atoi(nx());
        else if (k == "--connect-interval-ms") interval_ms = atoi(nx());
        else if (k == "--seconds") seconds = atoi(nx());
        else if (k == "--rcvbuf") rcvbuf = atoi(nx());
        else if (k == "--safe-close") safe_close = true;
        else if (k == "--local-port") local_port = atoi(nx());
        else if (k == "--prefix-kb") prefix_kb = atol(nx());
        else if (k == "--scan-bytes") scan_bytes = atol(nx());
        else if (k == "--dump-prefix-dir") dump_dir = nx();
        else if (k == "--dump-max") dump_max = atol(nx());
        else if (k == "--max-conns") max_conns = atol(nx());
        else if (k == "--hold-s") hold_s = atoi(nx());
        else if (k == "--scan-all") { scan_all = atoi(nx()); }
        else if (k == "--needle-max") needle_max = atol(nx());
        else if (k == "--verify-stream") verify_stream = atoi(nx());
        else if (k == "--verify-degrade-bytes") verify_degrade_bytes = atol(nx());
        else if (k == "--break-max") break_max = atol(nx());
        else if (k == "--check") {
            if (p7b_check_mode_parse(nx()) != 0) {
                fprintf(stderr, "--check 必须是 seq 或 lane8\n");
                return 2;
            }
            check_mode = p7b_check_mode_get();
        }
        else if (k == "--selftest") selftest = true;
        else if (k == "--selftest-scan") selftest_scan = true;
        else if (k == "--selftest-equiv") selftest_equiv = true;
        else if (k == "--selftest-verify") selftest_verify = true;
        else if (k == "--selftest-all") selftest_all = true;
        else if (k == "--help") { churn_usage(); return 0; }
        else { fprintf(stderr, "unknown arg %s (--help)\n", k.c_str()); return 2; }
    }

    // ---- 自检（CPU-only；在任何 socket/参数校验之前返回） ----
    if (selftest_all) {
        int f = 0;
        f |= v3_selftest_pattern();
        f |= v3_selftest_scan();
        f |= v3_selftest_equiv();
        f |= v3_selftest_verify();
        printf("SELFTEST_ALL %s\n", f ? "FAIL" : "PASS");
        return f ? 1 : 0;
    }
    if (selftest) return v3_selftest_pattern();
    if (selftest_scan) return v3_selftest_scan();
    if (selftest_equiv) return v3_selftest_equiv();
    if (selftest_verify) return v3_selftest_verify();

    p7b_check_mode_set(check_mode);

    // ---- 边界响亮（非法值 = stderr + RC=2） ----
    if (interval_ms <= 0) {
        fprintf(stderr, "--connect-interval-ms 必须 >= 1 (got %d)\n", interval_ms); return 2;
    }
    if (seconds <= 0) {
        fprintf(stderr, "--seconds 必须 >= 1 (got %d)\n", seconds); return 2;
    }
    if (rcvbuf < 1024 || rcvbuf > (1 << 30)) {
        fprintf(stderr, "--rcvbuf 越界: %d (合法 1024..1073741824)\n", rcvbuf); return 2;
    }
    if (port < 1 || port > 65535) {
        fprintf(stderr, "--port 越界: %d (合法 1..65535)\n", port); return 2;
    }
    if (local_port < 0 || local_port > 65535) {
        fprintf(stderr, "--local-port 越界: %d (合法 0..65535；0 = 不 bind)\n", local_port); return 2;
    }
    if (prefix_kb < 1 || prefix_kb > 1024) {
        fprintf(stderr, "--prefix-kb 越界: %ld (合法 1..1024)\n", prefix_kb); return 2;
    }
    if (scan_bytes < (long)V3_NEEDLE_LEN || scan_bytes > prefix_kb * 1024) {
        fprintf(stderr, "--scan-bytes 越界: %ld (合法 %zu..%ld = prefix 字节数)\n",
                scan_bytes, V3_NEEDLE_LEN, prefix_kb * 1024); return 2;
    }
    if (dump_max < 0) {
        fprintf(stderr, "--dump-max 不能为负: %ld\n", dump_max); return 2;
    }
    if (max_conns < 1 || max_conns > 100000) {
        fprintf(stderr, "--max-conns 越界: %ld (合法 1..100000)\n", max_conns); return 2;
    }
    if (hold_s < 0 || hold_s > 3600) {
        fprintf(stderr, "--hold-s 越界: %d (合法 0..3600)\n", hold_s); return 2;
    }
    if (scan_all != 0 && scan_all != 1) {
        fprintf(stderr, "--scan-all 必须是 0 或 1 (got %d)\n", scan_all); return 2;
    }
    if (needle_max < 0 || needle_max > 4096) {
        fprintf(stderr, "--needle-max 越界: %ld (合法 0..4096)\n", needle_max); return 2;
    }
    if (verify_stream != 0 && verify_stream != 1) {
        fprintf(stderr, "--verify-stream 必须是 0 或 1 (got %d)\n", verify_stream); return 2;
    }
    if (verify_degrade_bytes < 1024 || verify_degrade_bytes > (1L << 30)) {
        fprintf(stderr, "--verify-degrade-bytes 越界: %ld (合法 1024..1073741824)\n",
                verify_degrade_bytes); return 2;
    }
    if (break_max < 0 || break_max > 4096) {
        fprintf(stderr, "--break-max 越界: %ld (合法 0..4096)\n", break_max); return 2;
    }
    struct sockaddr_in dst{};
    dst.sin_family = AF_INET;
    dst.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, host, &dst.sin_addr) != 1) {
        fprintf(stderr, "--host 不是合法 IPv4: '%s'\n", host); return 2;
    }
    if (dump_dir) {
        struct stat st;
        if (stat(dump_dir, &st) != 0 || !S_ISDIR(st.st_mode)) {
            fprintf(stderr, "--dump-prefix-dir 不存在或不是目录: '%s' (先 mkdir -p)\n", dump_dir);
            return 2;
        }
        if (access(dump_dir, W_OK) != 0) {
            fprintf(stderr, "--dump-prefix-dir 不可写: '%s' (%s)\n", dump_dir, strerror(errno));
            return 2;
        }
    }
    if (verify_stream) {
        if (v3_inv_init() != 0) {
            fprintf(stderr, "--verify-stream 1 但 9 字节反解表不可逆（工具缺陷）\n");
            return 2;
        }
    }

    const size_t prefix_cap = (size_t)prefix_kb * 1024;

    // ---- RLIMIT_NOFILE ----
    {
        struct rlimit rl;
        long long soft = -1, hard = -1;
        int ok = 0;
        if (getrlimit(RLIMIT_NOFILE, &rl) == 0) {
            soft = (long long)rl.rlim_cur;
            hard = (long long)rl.rlim_max;
            ok = (soft >= V3_ULIMIT_NEED);
        }
        printf("CHURN_ULIMIT soft=%lld hard=%lld need=%lld ok=%d\n",
               soft, hard, V3_ULIMIT_NEED, ok);
        if (!ok) {
            fprintf(stderr,
                    "CHURN_WARN RLIMIT_NOFILE soft=%lld < %lld —— 120 s x 100/s 约需 12,000 fd；"
                    "无安全关模式会撞 EMFILE（跑前先 `ulimit -n 16384`）\n",
                    soft, V3_ULIMIT_NEED);
            fflush(stderr);
        }
        fflush(stdout);
    }

    // ---- 见证行（CHURN_OPTS 逐字未动；v3 新开关单列一行） ----
    printf("CHURN_OPTS connect_interval_ms=%d rcvbuf=%d seconds=%d safe_close=%d restart_scan=1\n",
           interval_ms, rcvbuf, seconds, safe_close ? 1 : 0);
    printf("CHURN_SCAN_OPTS version=3 scan_all=%d needle_max=%ld verify_stream=%d "
           "verify_degrade_bytes=%ld break_max=%ld check=%s needle_len=%zu\n",
           scan_all, needle_max, verify_stream, verify_degrade_bytes, break_max,
           p7b_check_mode_name(), V3_NEEDLE_LEN);
    printf("CHURN_TARGET host=%s port=%d local_port=%d max_conns=%ld\n",
           host, port, local_port, max_conns);
    printf("CHURN_LIMITS prefix_kb=%ld scan_bytes=%ld dump_dir=%s dump_max=%ld hold_s=%d\n",
           prefix_kb, scan_bytes, dump_dir ? dump_dir : "none", dump_max, hold_s);
    fflush(stdout);

    // ---- 针 ----
    uint8_t needle[V3_NEEDLE_LEN];
    { P7bPat np(0); np.fill(needle, V3_NEEDLE_LEN); }
    {
        char h16[3 * 16 + 1];
        v3_hex(needle, 16, h16);
        printf("CHURN_NEEDLE len=%zu fnv1a32=0x%08X first16=%s\n",
               V3_NEEDLE_LEN, v3_fnv1a32(needle, V3_NEEDLE_LEN), h16);
        fflush(stdout);
    }

    std::vector<ChurnConn> conns;
    conns.reserve((size_t)max_conns + 8);
    std::vector<struct pollfd> pfds;
    std::vector<uint8_t> scratch(1u << 20);

    double t0 = p7b_io_now_s();
    double t_conn_end = t0 + (double)seconds;
    double t_run_end  = t_conn_end + (double)hold_s;
    double next_connect_at = t0;
    double prev_conn_at = t0, gap_max_ms = 0.0;
    long long n_connfail = 0, n_safe_closed = 0, n_eof = 0, n_reset = 0, n_err = 0;
    long long newest_data_idx = -1;
    size_t oldest_cursor = 0;
    bool cap_hit = false, warned_emfile = false, warned_eaddrinuse = false, warned_other = false;
    bool rcvbuf_eff_reported = false;
    long long bytes_prev = 0;
    P7bIoReporter rep; rep.start(t0);

    for (;;) {
        double now = p7b_io_now_s();
        if (now >= t_run_end) break;

        if (now < t_conn_end) {
            while (now >= next_connect_at) {
                if ((long long)conns.size() >= max_conns) {
                    if (!cap_hit) {
                        cap_hit = true;
                        printf("CHURN_CAP max_conns=%ld reached at t=%.3f s ⇒ 停止新建连接\n",
                               max_conns, now - t0);
                        fflush(stdout);
                    }
                    next_connect_at = t_conn_end;
                    break;
                }
                int why = 0, eff = -1;
                int fd = churn_connect_start(&dst, rcvbuf, local_port, &why, &eff);
                if (fd >= 0) {
                    if (!rcvbuf_eff_reported) {
                        rcvbuf_eff_reported = true;
                        printf("CHURN_RCVBUF req=%d eff_after_set=%d (内核通常 x2；clamp=rmem_max)\n",
                               rcvbuf, eff);
                        fflush(stdout);
                    }
                    ChurnConn c;
                    c.fd = fd;
                    c.idx = (long long)conns.size();
                    c.t_start = now;
                    c.ns.cap = needle_max;
                    c.vs.bcap = break_max;
                    conns.push_back(c);
                } else {
                    n_connfail++;
                    if (why == EMFILE || why == ENFILE) {
                        if (!warned_emfile) {
                            warned_emfile = true;
                            fprintf(stderr, "CHURN_WARN EMFILE/ENFILE (%s) —— fd 上限到了；"
                                            "`ulimit -n` 提高后再跑\n", strerror(why));
                            fflush(stderr);
                        }
                    } else if (why == EADDRINUSE && local_port > 0) {
                        if (!warned_eaddrinuse) {
                            warned_eaddrinuse = true;
                            fprintf(stderr, "CHURN_WARN EADDRINUSE (local_port=%d) —— hold 模式下"
                                            "固定本地端口第 2 条起必失败（C3 的 close→reopen 语义"
                                            "不是本工具 hold 模式）\n", local_port);
                            fflush(stderr);
                        }
                    } else if (!warned_other) {
                        warned_other = true;
                        fprintf(stderr, "CHURN_WARN 首次 connect 失败 why=%d (%s)\n",
                                why, strerror(why));
                        fflush(stderr);
                    }
                }
                double g = (now - prev_conn_at) * 1e3;
                if (g > gap_max_ms) gap_max_ms = g;
                prev_conn_at = now;
                next_connect_at += (double)interval_ms / 1000.0;
                now = p7b_io_now_s();
            }
        }

        pfds.clear();
        for (size_t i = 0; i < conns.size(); i++) {
            ChurnConn &c = conns[i];
            if (c.state == ST_CLOSED) continue;
            struct pollfd p;
            p.fd = c.fd;
            p.events = (c.state == ST_CONNECTING) ? POLLOUT : POLLIN;
            p.revents = 0;
            pfds.push_back(p);
        }
        int tmo_ms;
        if (now >= t_conn_end) {
            tmo_ms = 100;
        } else {
            double d = (next_connect_at - now) * 1000.0;
            if (d < 0) d = 0;
            if (d > 1000) d = 1000;
            tmo_ms = (int)(d + 0.5);
        }
        int pr = poll(pfds.empty() ? NULL : &pfds[0], (nfds_t)pfds.size(), tmo_ms);
        if (pr < 0 && errno != EINTR) {
            fprintf(stderr, "CHURN_ERR poll: %s\n", strerror(errno));
            break;
        }

        if (pr > 0) {
            size_t pi = 0;
            for (size_t i = 0; i < conns.size() && pi < pfds.size(); i++) {
                if (conns[i].state == ST_CLOSED) continue;
                short re = pfds[pi++].revents;
                if (re == 0) continue;
                ChurnConn &c = conns[i];
                if (re & POLLNVAL) {
                    fprintf(stderr, "CHURN_ERR POLLNVAL conn=%lld fd=%d\n", c.idx, c.fd);
                    c.why = 0; c.closed_by = CL_ERR; c.state_at_close = c.state;
                    close(c.fd); c.state = ST_CLOSED; n_err++;
                    continue;
                }
                if (c.state == ST_CONNECTING) {
                    int err = 0; socklen_t el = sizeof(err);
                    if (getsockopt(c.fd, SOL_SOCKET, SO_ERROR, &err, &el) < 0) err = errno;
                    if (err == 0) {
                        c.state = ST_ESTAB;
                        c.t_estab = p7b_io_now_s();
                        churn_drain(c, &scratch[0], scratch.size(), prefix_cap, needle,
                                    scan_all != 0, verify_stream != 0,
                                    verify_degrade_bytes, &newest_data_idx);
                    } else {
                        c.why = err; c.closed_by = CL_CONNFAIL; c.state_at_close = ST_CONNECTING;
                        n_connfail++;
                        close(c.fd); c.state = ST_CLOSED;
                    }
                } else if (c.state == ST_ESTAB) {
                    if (re & (POLLIN | POLLERR | POLLHUP)) {
                        churn_drain(c, &scratch[0], scratch.size(), prefix_cap, needle,
                                    scan_all != 0, verify_stream != 0,
                                    verify_degrade_bytes, &newest_data_idx);
                        if (c.state == ST_CLOSED) {
                            if (c.closed_by == CL_EOF) n_eof++;
                            else if (c.closed_by == CL_RESET) n_reset++;
                            else if (c.closed_by == CL_ERR) n_err++;
                        }
                    }
                }
            }
        }

        if (safe_close) {
            while (oldest_cursor < conns.size() && conns[oldest_cursor].state == ST_CLOSED)
                oldest_cursor++;
            if (oldest_cursor < conns.size() &&
                newest_data_idx > (long long)oldest_cursor) {
                ChurnConn &o = conns[oldest_cursor];
                o.why = 0; o.closed_by = CL_SAFE; o.state_at_close = o.state;
                close(o.fd);
                o.state = ST_CLOSED;
                n_safe_closed++;
                oldest_cursor++;
            }
        }

        now = p7b_io_now_s();
        if (rep.due(now)) {
            long long ce = 0, cc = 0, cb = 0, sh = 0, vb = 0;
            for (size_t i = 0; i < conns.size(); i++) {
                if (conns[i].state == ST_ESTAB) ce++;
                else if (conns[i].state == ST_CONNECTING) cc++;
                cb += conns[i].bytes;
                sh += conns[i].ns.hits;
                vb += conns[i].vs.breaks;
            }
            printf("CHURN_T t=%.1f conns=%zu estab=%lld connecting=%lld connfail=%lld eof=%lld "
                   "reset=%lld err=%lld closed_safe=%lld bytes=%lld rx_MBps=%.3f CPU_FREQ_KHZ=%s "
                   "scan_hits=%lld vbreaks=%lld\n",
                   rep.since(now), conns.size(), ce, cc, n_connfail, n_eof, n_reset, n_err,
                   n_safe_closed, cb, (cb - bytes_prev) / 1e6, p7baff_work_freq_khz().c_str(),
                   sh, vb);
            fflush(stdout);
            bytes_prev = cb;
            rep.mark(now);
        }
        p7baff_work_freq_tick();
    }

    // =======================================================================
    // 收尾：逐连接判定 + 报告 + 候选落盘（v2 语义 + v3 追加字段）
    // =======================================================================
    double t_fin = p7b_io_now_s();
    long long v_off0 = 0, v_offk = 0, v_nomatch = 0, v_cand_full = 0, v_cand_short = 0;
    long long v_short = 0, v_nodata = 0;
    long long n_dumps = 0, n_dump_skip = 0, n_dump_fail = 0;
    bool dump_none_warned = false;

    long long scan_bytes_total = 0, needle_conns = 0, needle_hits_total = 0;
    long long needle_trunc_conns = 0, vbreak_conns = 0, vbreaks_total = 0;
    long long vdegraded_conns = 0;

    for (size_t i = 0; i < conns.size(); i++) {
        ChurnConn &c = conns[i];
        size_t win = c.prefix_len;
        if (win > (size_t)scan_bytes) win = (size_t)scan_bytes;
        c.scan_n = (long long)win;
        if (c.prefix_len == 0) {
            c.restart_off = -2;
            v_nodata++;
        } else if (c.prefix_len < V3_NEEDLE_LEN) {
            c.restart_off = -2;
            v_short++;
        } else {
            c.restart_off = v3_scan_first(c.prefix, win, needle, V3_NEEDLE_LEN);
            if (c.restart_off == 0)      v_off0++;
            else if (c.restart_off > 0)  v_offk++;
            else {
                v_nomatch++;
                if (win == (size_t)scan_bytes) v_cand_full++;
                else                           v_cand_short++;
            }
        }
        char off_s[32];
        if (c.restart_off == -2) strcpy(off_s, "na");
        else                     sprintf(off_s, "%lld", c.restart_off);
        double last_act = (c.bytes > 0) ? c.t_last_rx : (c.t_estab > 0 ? c.t_estab : c.t_start);
        double idle_ms = (t_fin - last_act) * 1e3;

        // ---- v3 全流字段 ----
        const char *scan_state;
        if (!scan_all)                 scan_state = "off";
        else if (c.bytes == 0)         scan_state = "none";
        else if (c.bytes < (long long)V3_NEEDLE_LEN) scan_state = "short";
        else                           scan_state = "full";
        long long first_needle = c.ns.hits ? c.ns.first : -1;
        long long last_needle  = c.ns.hits ? c.ns.last  : -1;
        long long scanned      = scan_all ? c.bytes : 0;
        long long vfirst = c.vs.breaks ? c.vs.first_break : -1;
        long long vlast  = c.vs.breaks ? c.vs.last_break  : -1;
        long long vscanned = verify_stream ? c.vs.processed : 0;

        printf("CHURN conn=%lld bytes=%lld restart@off=%s idle_ms=%.3f state=%s why=%d why_str=%s"
               " closed_by=%s reads=%lld scan_bytes=%lld prefix_bytes=%zu dur_ms=%.3f"
               " estab_ms=%.3f last_rx_ms=%.3f CPU_FREQ_KHZ=%s"
               " full_scan=%d first_needle=%lld hits=%lld last_needle=%lld scanned=%lld"
               " scan_state=%s needle_trunc=%d verify=%d vbreaks=%lld vfirst_break=%lld"
               " vlast_break=%lld vdegraded=%d vscanned=%lld vmode=%s\n",
               c.idx, c.bytes, off_s, idle_ms, churn_state_str(c), c.why,
               c.why ? strerror(c.why) : "-",
               c.closed_by == CL_SAFE ? "safe_close" : (c.closed_by == CL_NONE ? "-" : churn_state_str(c)),
               c.reads, c.scan_n, c.prefix_len,
               (t_fin - c.t_start) * 1e3,
               (c.t_estab > 0 ? (c.t_estab - c.t_start) * 1e3 : -1.0),
               (c.bytes > 0 ? (t_fin - c.t_last_rx) * 1e3 : -1.0),
               p7baff_work_freq_khz().c_str(),
               scan_all, first_needle, c.ns.hits, last_needle, scanned,
               scan_state, c.ns.trunc, verify_stream, c.vs.breaks, vfirst, vlast,
               c.vs.degraded, vscanned, p7b_check_mode_name());

        // ---- 出现偏移列表（只在该连接有针时打一行；不影响 `grep '^CHURN conn='`） ----
        if (scan_all && c.ns.hits > 0) {
            printf("CHURN_NEEDLES conn=%lld n=%lld shown=%lld trunc=%d offs=",
                   c.idx, c.ns.hits, c.ns.stored, c.ns.trunc);
            if (c.ns.stored == 0) printf("-");
            for (long long k = 0; k < c.ns.stored; k++)
                printf("%s%lld", k ? "," : "", c.ns.offs[k]);
            printf("\n");
        }
        if (verify_stream && c.vs.breaks > 0) {
            printf("CHURN_VBREAKS conn=%lld n=%lld shown=%lld trunc=%d offs=",
                   c.idx, c.vs.breaks, c.vs.bstored, c.vs.btrunc);
            if (c.vs.bstored == 0) printf("-");
            for (long long k = 0; k < c.vs.bstored; k++)
                printf("%s%lld", k ? "," : "", c.vs.boffs[k]);
            printf("\n");
        }

        // ---- 汇总计数 ----
        if (scan_all) {
            scan_bytes_total += c.bytes;
            if (c.ns.hits > 0) needle_conns++;
            needle_hits_total += c.ns.hits;
            if (c.ns.trunc) needle_trunc_conns++;
        }
        if (verify_stream) {
            if (c.vs.breaks > 0) vbreak_conns++;
            vbreaks_total += c.vs.breaks;
            if (c.vs.degraded) vdegraded_conns++;
        }

        // ---- 候选落盘（restart@off == -1；v2 语义逐字保留） ----
        if (dump_dir && c.restart_off == -1) {
            if (n_dumps >= dump_max) {
                n_dump_skip++;
            } else {
                char path[1200];
                snprintf(path, sizeof(path), "%s/churn_conn%06lld.bin", dump_dir, c.idx);
                FILE *f = fopen(path, "wb");
                if (!f) {
                    n_dump_fail++;
                    fprintf(stderr, "CHURN_DUMP_FAIL conn=%lld path=%s: %s\n",
                            c.idx, path, strerror(errno));
                } else {
                    size_t w = fwrite(c.prefix, 1, c.prefix_len, f);
                    int bad = (fclose(f) != 0) || (w != c.prefix_len);
                    if (bad) {
                        n_dump_fail++;
                        fprintf(stderr, "CHURN_DUMP_FAIL conn=%lld path=%s written=%zu/%zu\n",
                                c.idx, path, w, c.prefix_len);
                    } else {
                        n_dumps++;
                        printf("CHURN_DUMP conn=%lld file=%s bytes=%zu scan_bytes=%lld\n",
                               c.idx, path, c.prefix_len, c.scan_n);
                    }
                }
            }
        }
        free(c.prefix);
        c.prefix = NULL;
        v3_needle_free(c.ns);
        v3_verify_free(c.vs);
    }
    if (dump_dir && n_dump_skip > 0 && !dump_none_warned) {
        dump_none_warned = true;
        printf("CHURN_DUMP_LIMIT dumps=%lld skipped=%lld dump_max=%ld (提高 --dump-max 可全落)\n",
               n_dumps, n_dump_skip, dump_max);
    }
    if (!dump_dir && v_nomatch > 0) {
        printf("CHURN_DUMP none (--dump-prefix-dir 未给 ⇒ %lld 条候选前缀**未落盘**)\n", v_nomatch);
    }
    fflush(stdout);

    long long n_estab_now = 0, n_connecting_now = 0, bytes_total = 0;
    for (size_t i = 0; i < conns.size(); i++) {
        if (conns[i].state == ST_ESTAB) n_estab_now++;
        else if (conns[i].state == ST_CONNECTING) n_connecting_now++;
        bytes_total += conns[i].bytes;
    }
    double window_s = t_fin - t0;
    double conn_window_s = ((t_fin < t_conn_end) ? t_fin : t_conn_end) - t0;

    // ⚠️ CHURN_SUM 既有键与顺序**逐字未动**；v3 新键一律追加在 `CPU_FREQ_KHZ=` 之后。
    printf("CHURN_SUM conns=%zu estab=%lld connecting=%lld connfail=%lld eof=%lld reset=%lld "
           "err=%lld closed_safe=%lld bytes=%lld window_s=%.3f conn_window_s=%.3f "
           "rate_per_s=%.3f estab_rate_per_s=%.3f "
           "gap_max_ms=%.3f verdict_off0=%lld verdict_offk=%lld candidates=%lld "
           "candidates_full=%lld candidates_short=%lld short_lt32=%lld nodata=%lld "
           "dumps=%lld dumps_skipped=%lld dump_fail=%lld cap_hit=%d safe_close=%d needle_len=%zu "
           "scan_bytes=%ld CPU_FREQ_KHZ=%s"
           " full_scan=%d scan_bytes_total=%lld needle_conns=%lld needle_hits=%lld "
           "needle_trunc_conns=%lld verify=%d vbreak_conns=%lld vbreaks=%lld "
           "vdegraded_conns=%lld vmode=%s\n",
           conns.size(), n_estab_now, n_connecting_now, n_connfail, n_eof, n_reset, n_err,
           n_safe_closed, bytes_total, window_s, conn_window_s,
           conn_window_s > 0 ? (double)conns.size() / conn_window_s : 0.0,
           conn_window_s > 0 ? (double)(n_estab_now + n_safe_closed + n_eof + n_reset + n_err) / conn_window_s : 0.0,
           gap_max_ms, v_off0, v_offk, v_nomatch, v_cand_full, v_cand_short, v_short, v_nodata,
           n_dumps, n_dump_skip, n_dump_fail, cap_hit ? 1 : 0, safe_close ? 1 : 0,
           V3_NEEDLE_LEN, scan_bytes, p7baff_work_freq_khz().c_str(),
           scan_all, scan_bytes_total, needle_conns, needle_hits_total,
           needle_trunc_conns, verify_stream, vbreak_conns, vbreaks_total,
           vdegraded_conns, p7b_check_mode_name());
    printf("CHURN_DONE\n");
    fflush(stdout);

    int rc = 0;
    if (conns.empty()) {
        fprintf(stderr, "CHURN_FAIL 一条连接都没建 (conns=0) ⇒ RC=1\n");
        rc = 1;
    } else if (n_estab_now + n_safe_closed + n_eof + n_reset + n_err == 0) {
        fprintf(stderr, "CHURN_FAIL 没有任何连接完成握手 (estab=0, connfail=%lld) ⇒ RC=1\n",
                n_connfail);
        rc = 1;
    }
    if (n_dump_fail > 0) {
        fprintf(stderr, "CHURN_FAIL dump_fail=%lld（候选前缀丢了 ⇒ 读数丢了）⇒ RC=1\n", n_dump_fail);
        rc = 1;
    }
    return rc;
}
