// ===========================================================================
// p7b_tcp_churn.cpp -- C1「静默释放槽位偷取环」构型的对端工具 (P-3 复资格轮, 2026-10-17)
//
// ⚠️ 这是**新件**：不改任何现役工具（`p7b_tcp_sink.cpp` 一字未动 —— 另一条工作线正在用
//    现役 sink 跑板级实验）。部署名 `p7b_tcp_churn` 与现役 8 个产物**不重名**。
//
// 规格出处 = `_proj_10g/notes/p9_p3win_redesign_20261017/README_FOR_TL.md` §2.2（施工规格）+
//   §2.4（读数设计）。构型一句话：对端 **connect 洪流（~100/s）+ 所有 fd 持有不关 + 持续读干**
//   ⇒ 板侧 `T_SYN_RCVD` 超时（~80 ms，`hls/src/layer_tcp.cpp:532-535` = **静默释放、不发 CFG_DEL**）
//   让新 SYN 偷回同一槽位（ADD 覆盖 TCB 而 app 组装无缝续接）⇒ 同槽 ev_up ~11-12.5/s、
//   每事件带真实命中概率（P-3 危险拍）。
//
// 本工具的产物（= 规格 §2.4 的对端半边）:
//   A) **重启扫描（床内、零额外分析）**：每连接首 ~4 KB 内是否出现 32 字节 `pattern[0..31]`
//      （= 板侧 `tx_lfsr` 被复位 ⇒ 流重启 ⇒ 非命中）；不出现 ⇒ **命中候选**（覆盖写）
//   B) 候选连接的**首 64 KB 前缀落盘**（`--dump-prefix-dir`），供离线逐字节复算 K0/breaks
//
// ---------------------------------------------------------------------------
// 输出纪律（本工程惯例：缺见证按"未测"读；"我传了参数" ≠ "参数生效了"）:
//   * `CHURN_OPTS connect_interval_ms=… rcvbuf=… seconds=… safe_close=… restart_scan=1`
//     （字段与顺序 = 规格 §2.2-6 逐字）
//   * `CHURN_ULIMIT` / `CHURN_RCVBUF`（req vs 内核回读 eff）/ `CHURN_NEEDLE`（**扫描针自身的
//     指纹** —— 仪器自己先要被核）/ `CHURN_TARGET` / `CHURN_LIMITS`
//   * 每连接一行：**前四个字段固定为** `CHURN conn=<k> bytes=… restart@off=… idle_ms=…`
//     （规格 §2.2-5），其余字段**一律追加在行尾**
//   * 周期行 `CHURN_T …`（行尾 `CPU_FREQ_KHZ=`，口径同 R2 = **干活线程自采样**）
//   * 汇总 `CHURN_SUM …` + 收尾 `CHURN_DONE`
//
// ⛔ 本件**不下 PASS/FAIL 裁定**，只给读数（裁定权在判据所有者）。
//
// ---------------------------------------------------------------------------
// `restart@off` 的取值语义（**本件定义，写进 README**）:
//   * `k >= 1`  ⇒ 在该连接收到字节流的**偏移 k** 处出现整针 ⇒ **重启**（确定形态）⇒ 非命中
//   * `0`       ⇒ 整针就在偏移 0（= 本连接首字节恰是流起点）：**语义两义** ——
//                 "本连接就是新会话的起点"与"恰在 0 处被重启"在字节上不可分
//                 （设计件 §1.4(P-3) 的 u_swc0 教训：位置 0 时覆盖与干净复位逐字节相同）
//                 ⇒ 单独计数（`verdict_off0`），**不并入 k>0**
//   * `-1`      ⇒ 首窗口（≤ `--scan-bytes`，默认 4096）内**无匹配** ⇒ **命中候选**（落盘）
//   * `na`      ⇒ 该连接收到的字节 **< 32**（连针都装不下）⇒ **判不了**，不是候选、不落盘
//                 ⛔ 0 字节连接必须记 `na` —— 否则 1.2 万条"没收到任何数据"的连接会把
//                 候选集合污染成噪声（"没数据"与"没重启"是两件事）
//
// `idle_ms` 语义：收尾时刻 − 该连接**最后一次收到字节**的时刻；从未收到字节 ⇒ 取建立时刻；
//   从未建立 ⇒ 取发起时刻 ⇒ **未收数据的连接 idle_ms ≈ 全长**（可当"这条连接一直空着"的签）。
//
// ---------------------------------------------------------------------------
// 边界（硬需求逐条）:
//  1) 主循环 = `poll()` 多 fd + connect 定时器（`--connect-interval-ms`，默认 10）
//  2) **非阻塞 connect**：⛔ **故意不用** `p7b_io.h` 的 `p7b_io_connect_nb` —— 它会 poll 到
//     握手完成（最长 secs 秒）⇒ 把 10 ms 定时器**串行化**（洪流就不是洪流了）。本件用它
//     **同一套 socket 建立序列**（socket → inet_pton → `p7b_io_set_nonblock` → [--local-port
//     bind] → `SO_RCVBUF` **落点 = connect 之前**（sinkfix 口径）→ `connect()` 立即返回），
//     完成与否在 poll 环里收（POLLOUT/POLLERR → `getsockopt(SO_ERROR)`）
//  3) **永不主动 close**；`--safe-close`（默认关）= 仅当某个**更新**的连接**已收到数据**后
//     才关最旧 fd（依据 = 槽的 4-tuple 记录已被覆盖 ⇒ 旧连接的 FIN/RST 不再匹配 —— §2.2-3）。
//     两种模式都要能跑（默认关 = C1 主臂；开 = fd 数控制臂）
//  4) 读干（recv 到 EAGAIN）+ 每 fd 留存首 `--prefix-kb`（默认 64）KB + 首 `--scan-bytes`
//     （默认 4096）字节内扫 32 字节针
//  5) 报告行 + 候选落盘（见上）；6) 见证行（见上）
//  7) 非法值（interval ≤ 0 / rcvbuf 越界 / seconds ≤ 0 / …）⇒ stderr 说明 + **RC=2**
//  8) 启动时 `RLIMIT_NOFILE < 16384` ⇒ **警告行**（120 s×100/s ≈ 12,000 fd 的无安全关模式需要）
//
// 复用机制头（先现读接口，逐条对齐）: `p7b_io.h`（`p7b_io_set_nonblock` / `p7b_io_now_s` /
//   `p7b_io_die` / `p7b_io_retryable` / `P7bIoReporter`）· `p7b_affinity.h`（启动即绑核硬门 +
//   见证 + atexit 按线程硬门 —— 照现役工具口径：`argc = p7b_pin_cpu(argc, argv);`）·
//   `p7b_pattern.h`（SEED / `p7b_xs_next` / `P7bPat` 递推 —— 针由同一机制生成，不手抄常量）
//
// ⚠️ 已知边界（如实登记，不许读成"已收口"）:
//   * **进程退出 ⇒ 内核关闭全部 fd** ⇒ 已建立连接各发 1 个 FIN（本构型下 ~1.2 万条）
//     ⇒ 会给板侧灌一串控制帧（可能触发 DEL/ev_down）。要"先把板侧数点收完再让它退" ⇒
//     用 `--hold-s N`：打印完逐连接行与 `CHURN_SUM` 后**继续读干** N 秒**再退出**，
//     期间不新建连接（给 `p7b_snap` 收数留窗）。
//     ⚠️ `CHURN_SUM` 的 `rate_per_s` 分母 = **连接窗口**（`conn_window_s`），**不含** hold 段 ——
//     否则 10% 的 hold 会把 100/s 读成 90/s（3 s + hold 3 s 实测读到 49.9/s，已修）。
//   * 收尾时仍在 CONNECTING 的 fd **不判死**（SYN 重传由内核按 tcp_syn_retries 走完；
//     板"没有空槽就不应答 SYN"正是本构型要的，过早判死会掩盖它）⇒ 只统计、不 close。
//   * `--local-port` 的语义**只在单条连接**下成立（固定本地端口 + 持有不关 ⇒ 第 2 条起
//     bind 必 EADDRINUSE、响亮计 FAIL_CONNECT 并打一次 `CHURN_WARN`）—— C3 的
//     "close→reopen 同端口"臂不属于本工具的 hold 模式（C3 用现役 sink 的顺序模式）。
//   * `--dump-prefix-dir` 目录**必须先存在**（本件不 mkdir；打不开 ⇒ RC=2，响亮）；
//     dump 写失败 ⇒ 计数 + stderr + **RC=1**（候选前缀丢了 = 读数丢了，不许静默）。
//
// 编译（部署口径 = `_proj_10g/notes/p7b_affinity/BUILD.md` §2；与其它工具**逐字同一条命令**）:
//   g++ -O3 -pthread -o p7b_tcp_churn p7b_tcp_churn.cpp
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
static const size_t CHURN_NEEDLE_LEN = 32;          // 针长（规格 §2.2-4）
static const long long CHURN_ULIMIT_NEED = 16384;   // 硬需求 8 的门槛

enum { ST_CONNECTING = 0, ST_ESTAB = 1, ST_CLOSED = 2 };
enum { CL_NONE = 0, CL_SAFE = 1, CL_EOF = 2, CL_RESET = 3, CL_ERR = 4, CL_CONNFAIL = 5 };

// ===========================================================================
// 扫描器（本件的核心仪器 —— 必须能被独立单测：`--selftest-scan`）
//   语义：在 `buf[0..n)` 内搜 `needle[0..nlen)`，返回**首个匹配的起始偏移**；无匹配 ⇒ -1。
//   ⚠️ 整针必须**完整落在窗内**（`i + nlen <= n`）—— 半针不算匹配（窗边界上的那一格
//      正是"4 KB 窗"判据的牙：`--scan-bytes 4096` 时偏移 4065 的针是**出窗**的）
// ===========================================================================
static long long churn_scan_restart(const uint8_t *buf, size_t n,
                                    const uint8_t *needle, size_t nlen) {
    if (n < nlen) return -1;
    for (size_t i = 0; i + nlen <= n; i++) {
        if (buf[i] != needle[0]) continue;
        if (memcmp(buf + i, needle, nlen) == 0) return (long long)i;
    }
    return -1;
}

// FNV-1a 32（针的指纹；跨轮比对"针没被换掉"）
static uint32_t churn_fnv1a32(const uint8_t *p, size_t n) {
    uint32_t h = 2166136261u;
    for (size_t i = 0; i < n; i++) { h ^= (uint32_t)p[i]; h *= 16777619u; }
    return h;
}

static void churn_hex(const uint8_t *p, size_t n, char *out) {
    for (size_t i = 0; i < n; i++) sprintf(out + 3 * i, "%02X ", p[i]);
    out[3 * n] = '\0';
}

// ===========================================================================
// 扫描单测（`--selftest-scan`）
//   合成数据三种（硬需求）+ 边界。每例打**原始读数**（不是只打 PASS/FAIL —— 全局 #30
//   "注入过 ≠ 测到了"：必须同时钉住期望值）。
// ===========================================================================
static int churn_scan_selftest(void) {
    int checks = 0, fails = 0;
    uint8_t needle[CHURN_NEEDLE_LEN];
    {
        P7bPat p(0);                       // 与板侧 app 同一条机制（不手抄常量）
        p.fill(needle, CHURN_NEEDLE_LEN);
    }
    char hex[3 * CHURN_NEEDLE_LEN + 1], hex16[3 * 16 + 1];
    churn_hex(needle, CHURN_NEEDLE_LEN, hex);
    churn_hex(needle, 16, hex16);
    uint32_t nh = churn_fnv1a32(needle, CHURN_NEEDLE_LEN);
    printf("SCAN needle len=%zu fnv1a32=0x%08X\n", CHURN_NEEDLE_LEN, nh);
    printf("SCAN needle[0..31]  = %s\n", hex);
    printf("SCAN needle[0..15]  = %s\n", hex16);
    // ⛔ 独立核对（不是自证）：前 16 字节必须等于 p7b_pattern.h 文档里那条**从 RTL 语义
    //    手算**的向量 —— 针本身错了，后面全部单测都是空判据。
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

    // ① 针在偏移 0
    memset(buf, 0xA5, sizeof(buf));
    memcpy(buf, needle, CHURN_NEEDLE_LEN);
    SCAN_CASE("match_at_0", 0, churn_scan_restart(buf, sizeof(buf), needle, CHURN_NEEDLE_LEN));

    // ② 针在偏移 k>0（前面铺**流中段**数据 = 真图案的非 0 偏移，最接近实战）
    { P7bPat g(5000); g.fill(buf, 1234); }
    memcpy(buf + 1234, needle, CHURN_NEEDLE_LEN);
    memset(buf + 1234 + CHURN_NEEDLE_LEN, 0x5A, sizeof(buf) - 1234 - CHURN_NEEDLE_LEN);
    SCAN_CASE("match_at_1234", 1234, churn_scan_restart(buf, sizeof(buf), needle, CHURN_NEEDLE_LEN));

    // ③ 无匹配（整段流中段图案 —— 这就是"命中候选"的输入形态）
    { P7bPat g(7777); g.fill(buf, 4096); }
    SCAN_CASE("no_match", -1, churn_scan_restart(buf, 4096, needle, CHURN_NEEDLE_LEN));

    // ④ 窗边界：针起点 4064（= 4096-32，**整针恰好在窗内**）⇒ 命中
    { P7bPat g(1234); g.fill(buf, 4096); }
    memcpy(buf + 4064, needle, CHURN_NEEDLE_LEN);
    SCAN_CASE("window_edge_in_4064", 4064, churn_scan_restart(buf, 4096, needle, CHURN_NEEDLE_LEN));

    // ⑤ 窗边界：针起点 4065（尾字节出窗）⇒ 在 4096 窗内**不命中**；给足整段则命中 4065
    //    （两条一起才证明"不命中"是**窗**的功劳，不是扫描器瞎了）
    { P7bPat g(4321); g.fill(buf, 4096); }
    memcpy(buf + 4065, needle, CHURN_NEEDLE_LEN);
    SCAN_CASE("window_edge_out_4065", -1, churn_scan_restart(buf, 4096, needle, CHURN_NEEDLE_LEN));
    SCAN_CASE("window_edge_out_full", 4065, churn_scan_restart(buf, 4097, needle, CHURN_NEEDLE_LEN));

    // ⑥ 半针（前 31 字节对、第 32 字节错）⇒ 不命中
    memset(buf, 0x11, sizeof(buf));
    memcpy(buf + 100, needle, CHURN_NEEDLE_LEN);
    buf[100 + CHURN_NEEDLE_LEN - 1] ^= 0x01;
    SCAN_CASE("partial_31_of_32", -1, churn_scan_restart(buf, sizeof(buf), needle, CHURN_NEEDLE_LEN));

    // ⑦ 负对照：翻中间 1 个字节 ⇒ 不命中（"扫到就想报"的扫描器会在这里露馅）
    memset(buf, 0x11, sizeof(buf));
    memcpy(buf + 100, needle, CHURN_NEEDLE_LEN);
    buf[100 + 17] ^= 0x80;
    SCAN_CASE("flip_1bit_no_match", -1, churn_scan_restart(buf, sizeof(buf), needle, CHURN_NEEDLE_LEN));

    // ⑧ 窗比针短 ⇒ 不命中（"字节 < 32 ⇒ na"那条口径的底层行为）
    memset(buf, 0xA5, sizeof(buf));
    memcpy(buf, needle, CHURN_NEEDLE_LEN);
    SCAN_CASE("short_window_31", -1, churn_scan_restart(buf, 31, needle, CHURN_NEEDLE_LEN));

    // ⑨ "首个匹配偏移"：两处都有针 ⇒ 必须报**先出现**的那个
    memset(buf, 0x33, sizeof(buf));
    memcpy(buf, needle, CHURN_NEEDLE_LEN);
    memcpy(buf + 500, needle, CHURN_NEEDLE_LEN);
    SCAN_CASE("first_of_two_matches", 0, churn_scan_restart(buf, sizeof(buf), needle, CHURN_NEEDLE_LEN));

    printf("SCAN_SELFTEST %s checks=%d fails=%d\n", fails ? "FAIL" : "PASS", checks, fails);
    #undef SCAN_CASE
    return fails ? 1 : 0;
}

// ===========================================================================
// 连接记录
// ===========================================================================
struct ChurnConn {
    int fd;
    int state;                 // ST_*
    long long idx;             // 创建序号 (= 报告里的 conn=k；也是 --safe-close 的"新旧"序)
    int why;                   // errno (0 = 无)
    long long bytes;           // 收到的总字节
    long long reads;           // recv 调用次数
    double t_start, t_estab, t_last_rx;
    uint8_t *prefix;           // 首 prefix_cap 字节（**首字节到达时才 malloc** ——
    size_t prefix_len;         //   1.2 万条连接 x 64 KB = 768 MB，懒分配把没数据的那些省掉）
    size_t prefix_cap;
    long long restart_off;     // 收尾时算：>=0 命中偏移 / -1 无匹配 / -2 = na
    long long scan_n;          // 实际扫了多少字节
    int closed_by;             // CL_*
    int state_at_close;        // close 那一刻的状态（safe-close 报告用）
    ChurnConn()
        : fd(-1), state(ST_CONNECTING), idx(0), why(0), bytes(0), reads(0),
          t_start(0), t_estab(0), t_last_rx(0), prefix(NULL), prefix_len(0), prefix_cap(0),
          restart_off(-2), scan_n(0), closed_by(CL_NONE), state_at_close(ST_CONNECTING) {}
};

static const char *churn_state_str(const ChurnConn &c) {
    if (c.state == ST_CONNECTING) return "connecting";
    if (c.state == ST_ESTAB)      return "estab";
    switch (c.closed_by) {                       // ST_CLOSED: 细分
        case CL_SAFE:     return "closed_safe";
        case CL_EOF:      return "eof";
        case CL_RESET:    return "reset";
        case CL_ERR:      return "err";
        case CL_CONNFAIL: return "connfail";
        default:          return "closed";
    }
}

// ===========================================================================
// 非阻塞 connect 起手：**同一套 socket 建立序列**（逐条对齐现役 sink 的
// `sink_connect_rcvbuf`，p7b_tcp_sink.cpp:242-272；唯一差别 = connect **不等待**）
//   返回 fd（>=0）= 已在连接中（可能已 ESTAB）；-1 = 直接失败（*why 有值）。
//   ⭐ SO_RCVBUF 落点 = **connect 之前**（sinkfix 口径：SYN 就按目标窗通告）
// ===========================================================================
static int churn_connect_start(const struct sockaddr_in *dst, int rcvbuf, int local_port,
                               int *why, int *rcvbuf_eff) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) { *why = errno; return -1; }
    p7b_io_set_nonblock(fd);                 // ⚠️ 全程序唯一一处 fcntl 就在这个函数里（p7b_io.h）
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
    // 落点 = connect 之前（默认口径）；回读内核生效值（"我传了参数" ≠ "参数生效了"）
    setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &rcvbuf, sizeof(rcvbuf));
    if (rcvbuf_eff) {
        int v = 0; socklen_t vl = sizeof(v);
        *rcvbuf_eff = (getsockopt(fd, SOL_SOCKET, SO_RCVBUF, &v, &vl) == 0) ? v : -1;
    }
    int r = connect(fd, (const struct sockaddr *)dst, sizeof(*dst));
    if (r == 0) return fd;                   // 立即完成（回环上罕见但可能）
    if (errno == EINPROGRESS) return fd;     // 常规：完成在 poll 环里收
    *why = errno; close(fd); return -1;
}

// ===========================================================================
// 读干一件连接：recv 到 EAGAIN；前缀只留首 prefix_cap 字节（之后照读照丢 = "读干"）
//   ⚠️ 只有主线程调它（单线程设计）⇒ 无并发语义问题
// ===========================================================================
static void churn_drain(ChurnConn &c, uint8_t *scratch, size_t scratch_sz, size_t prefix_cap,
                        long long *newest_data_idx) {
    for (;;) {
        ssize_t n = recv(c.fd, scratch, scratch_sz, 0);
        if (n > 0) {
            c.reads++;
            c.bytes += (long long)n;
            c.t_last_rx = p7b_io_now_s();
            if (c.idx > *newest_data_idx) *newest_data_idx = c.idx;   // --safe-close 的依据
            if (c.prefix_len < prefix_cap) {
                if (!c.prefix) {
                    c.prefix = (uint8_t *)malloc(prefix_cap);
                    if (!c.prefix) p7b_io_die("malloc(prefix)");   // exit(2) (全族惯例)
                    c.prefix_cap = prefix_cap;
                }
                size_t room = c.prefix_cap - c.prefix_len;
                size_t take = ((size_t)n < room) ? (size_t)n : room;
                memcpy(c.prefix + c.prefix_len, scratch, take);
                c.prefix_len += take;
            }
            continue;                                          // 读干（不是只读一次）
        }
        if (n == 0) {                                          // 对端 FIN
            c.why = 0; c.closed_by = CL_EOF; c.state_at_close = c.state;
            close(c.fd); c.state = ST_CLOSED;
            return;
        }
        if (p7b_io_retryable(errno)) return;                   // EAGAIN = 读干到底
        c.why = errno;
        c.closed_by = (errno == ECONNRESET) ? CL_RESET : CL_ERR;
        c.state_at_close = c.state;
        close(c.fd); c.state = ST_CLOSED;
        return;
    }
}

static void churn_usage(void) {
    printf(
        "p7b_tcp_churn -- C1「静默释放槽位偷取环」对端工具（connect 洪流 + 持有不关 + 读干 + 重启扫描）\n"
        "  --host H                  默认 192.168.100.2\n"
        "  --port P                  默认 8080\n"
        "  --connect-interval-ms N   connect 节奏（默认 10 ⇒ ~100/s；必须 >= 1）\n"
        "  --seconds S               连接窗口秒数（默认 120；必须 >= 1）\n"
        "  --rcvbuf B                SO_RCVBUF（默认 1048576；合法 1024..2^30；落点 = connect **之前**）\n"
        "  --safe-close              仅当**更新的连接已收到数据**后才关最旧 fd（默认关 = 永不主动 close）\n"
        "  --local-port N            connect 之前 bind 本地端口（0 = 不 bind；hold 模式下固定端口第 2 条起必失败）\n"
        "  --prefix-kb N             每连接留存前缀 KB（默认 64；合法 1..1024）\n"
        "  --scan-bytes N            重启扫描窗（默认 4096；合法 32..prefix 字节数）\n"
        "  --dump-prefix-dir DIR     候选（restart@off=-1）首前缀落盘目录（默认无 ⇒ 不落盘，响亮提示）\n"
        "  --dump-max N              落盘上限（默认 2048；超限响亮计数）\n"
        "  --max-conns N             连接总数上限（默认 16000；`CHURN_CAP` 行响亮提示）\n"
        "  --hold-s N                逐连接行 + CHURN_SUM 打完后**继续读干** N 秒再退（给板侧收数留窗；\n"
        "                            也是「避免退出 FIN 洪泛」的唯一手段 —— 默认 0 = 立即退，内核会把\n"
        "                            全部 fd 关掉并对已建立连接各发 1 个 FIN）\n"
        "  --no-pin / --core N       绑核开关（p7b_affinity.h；默认自动选核，绑不上 = exit(2)）\n"
        "  --selftest                只跑图案自检向量（p7b_pattern.h 的 RTL 对齐向量）\n"
        "  --selftest-scan           只跑**重启扫描器**单测（合成数据：针在 0 / 在 k / 无匹配 + 窗边界）\n"
        "  输出：CHURN_OPTS/CHURN_ULIMIT/CHURN_RCVBUF/CHURN_NEEDLE/CHURN_TARGET/CHURN_LIMITS 见证行 →\n"
        "        CHURN_T 周期行 → 每连接 `CHURN conn=k bytes=… restart@off=… idle_ms=…`（+行尾追加）→\n"
        "        CHURN_DUMP 行 → CHURN_SUM → CHURN_DONE\n"
        "  ⛔ 本件不下 PASS/FAIL 裁定；退出码：0 = 跑完且有连接建立且无 dump 失败；1 = 上述任一不成立；2 = 用法/环境错\n");
    printf("  restart@off: k>=1 = 偏移 k 处重启 / 0 = 偏移 0（语义两义，单独计数）/ -1 = 首窗内无匹配\n"
           "               （**命中候选**，落盘）/ na = 收到字节 < 32（判不了，不是候选）\n");
}

// ===========================================================================
int main(int argc, char **argv) {
    // 单线程设计（一个 poll 环）⇒ 不需要第二颗核；命令行 --pin-pair 仍可覆盖（p7b_pin_cpu 剥离）
    p7baff_g_want_pair = 0;
    argc = p7b_pin_cpu(argc, argv);          // ⭐ 启动即绑核（硬门 exit(2) + 见证行 + atexit 硬门）

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
    bool selftest = false, selftest_scan = false;

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
        else if (k == "--selftest") selftest = true;
        else if (k == "--selftest-scan") selftest_scan = true;
        else if (k == "--help") { churn_usage(); return 0; }
        else { fprintf(stderr, "unknown arg %s (--help)\n", k.c_str()); return 2; }
    }
    if (selftest) return p7b_pattern_selftest("p7b_tcp_churn");
    if (selftest_scan) return churn_scan_selftest();

    // ---- 边界响亮（硬需求 7：非法值 = stderr 说明 + RC=2，绝不静默截断） ----
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
    if (scan_bytes < (long)CHURN_NEEDLE_LEN || scan_bytes > prefix_kb * 1024) {
        fprintf(stderr, "--scan-bytes 越界: %ld (合法 %zu..%ld = prefix 字节数)\n",
                scan_bytes, CHURN_NEEDLE_LEN, prefix_kb * 1024); return 2;
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

    const size_t prefix_cap = (size_t)prefix_kb * 1024;

    // ---- 硬需求 8: RLIMIT_NOFILE 检查（不够 = **警告行**，不阻断） ----
    {
        struct rlimit rl;
        long long soft = -1, hard = -1;
        int ok = 0;
        if (getrlimit(RLIMIT_NOFILE, &rl) == 0) {
            soft = (long long)rl.rlim_cur;
            hard = (long long)rl.rlim_max;
            ok = (soft >= CHURN_ULIMIT_NEED);
        }
        printf("CHURN_ULIMIT soft=%lld hard=%lld need=%lld ok=%d\n",
               soft, hard, CHURN_ULIMIT_NEED, ok);
        if (!ok) {
            fprintf(stderr,
                    "CHURN_WARN RLIMIT_NOFILE soft=%lld < %lld —— 120 s x 100/s 约需 12,000 fd；"
                    "无安全关模式会撞 EMFILE（跑前先 `ulimit -n 16384`）\n",
                    soft, CHURN_ULIMIT_NEED);
            fflush(stderr);
        }
        fflush(stdout);
    }

    // ---- 见证行（生效值；"我传了参数" ≠ "参数生效了"） ----
    printf("CHURN_OPTS connect_interval_ms=%d rcvbuf=%d seconds=%d safe_close=%d restart_scan=1\n",
           interval_ms, rcvbuf, seconds, safe_close ? 1 : 0);
    printf("CHURN_TARGET host=%s port=%d local_port=%d max_conns=%ld\n",
           host, port, local_port, max_conns);
    printf("CHURN_LIMITS prefix_kb=%ld scan_bytes=%ld dump_dir=%s dump_max=%ld hold_s=%d\n",
           prefix_kb, scan_bytes, dump_dir ? dump_dir : "none", dump_max, hold_s);
    fflush(stdout);

    // ---- 针（由 p7b_pattern.h 机制生成；指纹随见证行输出 = 仪器自己先被核） ----
    uint8_t needle[CHURN_NEEDLE_LEN];
    { P7bPat np(0); np.fill(needle, CHURN_NEEDLE_LEN); }
    {
        char h16[3 * 16 + 1];
        churn_hex(needle, 16, h16);
        printf("CHURN_NEEDLE len=%zu fnv1a32=0x%08X first16=%s\n",
               CHURN_NEEDLE_LEN, churn_fnv1a32(needle, CHURN_NEEDLE_LEN), h16);
        fflush(stdout);
    }

    std::vector<ChurnConn> conns;
    conns.reserve((size_t)max_conns + 8);        // 预留到底 ⇒ 循环里**永不重分配**（引用稳定）
    std::vector<struct pollfd> pfds;
    std::vector<uint8_t> scratch(1u << 20);      // 1 MiB recv 暂存（前缀之外的字节就地丢）

    double t0 = p7b_io_now_s();
    double t_conn_end = t0 + (double)seconds;    // 连接窗口
    double t_run_end  = t_conn_end + (double)hold_s;
    double next_connect_at = t0;
    double prev_conn_at = t0, gap_max_ms = 0.0;
    long long n_connfail = 0, n_safe_closed = 0, n_eof = 0, n_reset = 0, n_err = 0;
    long long newest_data_idx = -1;              // 已收到数据的最新连接序号（--safe-close 依据）
    size_t oldest_cursor = 0;
    bool cap_hit = false, warned_emfile = false, warned_eaddrinuse = false, warned_other = false;
    bool rcvbuf_eff_reported = false;
    long long bytes_prev = 0;
    P7bIoReporter rep; rep.start(t0);

    for (;;) {
        double now = p7b_io_now_s();
        if (now >= t_run_end) break;

        // ---- 1) connect 定时器（只在连接窗口内；catch-up 不改节奏 ⇒ 用绝对时刻表） ----
        if (now < t_conn_end) {
            while (now >= next_connect_at) {
                if ((long long)conns.size() >= max_conns) {
                    if (!cap_hit) {
                        cap_hit = true;
                        printf("CHURN_CAP max_conns=%ld reached at t=%.3f s ⇒ 停止新建连接\n",
                               max_conns, now - t0);
                        fflush(stdout);
                    }
                    next_connect_at = t_conn_end;    // 关掉定时器（不再空转）
                    break;
                }
                int why = 0, eff = -1;
                int fd = churn_connect_start(&dst, rcvbuf, local_port, &why, &eff);
                if (fd >= 0) {
                    if (!rcvbuf_eff_reported) {      // 内核回读（1 次即可，见证"参数生效"）
                        rcvbuf_eff_reported = true;
                        printf("CHURN_RCVBUF req=%d eff_after_set=%d (内核通常 x2；clamp=rmem_max)\n",
                               rcvbuf, eff);
                        fflush(stdout);
                    }
                    ChurnConn c;
                    c.fd = fd;
                    c.idx = (long long)conns.size();
                    c.t_start = now;
                    conns.push_back(c);              // 真正 ESTAB 的判定与时刻在 poll 环里记
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

        // ---- 2) 组 poll 集合（连接态等可写完成；已建立等可读 —— **从不等可写**，本件从不 send）
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
            tmo_ms = 100;                     // 只收不连阶段（--hold-s）：100 ms 一轮
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

        // ---- 3) 处理事件（pfds 按 conns 顺序生成、只跳过 CLOSED ⇒ 双游标一一对应） ----
        if (pr > 0) {
            size_t pi = 0;
            for (size_t i = 0; i < conns.size() && pi < pfds.size(); i++) {
                if (conns[i].state == ST_CLOSED) continue;
                short re = pfds[pi++].revents;
                if (re == 0) continue;
                ChurnConn &c = conns[i];
                if (re & POLLNVAL) {                       // fd 失效（不该发生）⇒ 响亮
                    fprintf(stderr, "CHURN_ERR POLLNVAL conn=%lld fd=%d\n", c.idx, c.fd);
                    c.why = 0; c.closed_by = CL_ERR; c.state_at_close = c.state;
                    close(c.fd); c.state = ST_CLOSED; n_err++;
                    continue;
                }
                if (c.state == ST_CONNECTING) {
                    int err = 0; socklen_t el = sizeof(err);
                    if (getsockopt(c.fd, SOL_SOCKET, SO_ERROR, &err, &el) < 0) err = errno;
                    if (err == 0) {                        // 握手完成
                        c.state = ST_ESTAB;
                        c.t_estab = p7b_io_now_s();
                        churn_drain(c, &scratch[0], scratch.size(), prefix_cap, &newest_data_idx);
                    } else {                               // 失败（RST/拒绝/…）⇒ 死 fd，close
                        c.why = err; c.closed_by = CL_CONNFAIL; c.state_at_close = ST_CONNECTING;
                        n_connfail++;
                        close(c.fd); c.state = ST_CLOSED;
                    }
                } else if (c.state == ST_ESTAB) {
                    if (re & (POLLIN | POLLERR | POLLHUP)) {
                        churn_drain(c, &scratch[0], scratch.size(), prefix_cap, &newest_data_idx);
                        if (c.state == ST_CLOSED) {
                            if (c.closed_by == CL_EOF) n_eof++;
                            else if (c.closed_by == CL_RESET) n_reset++;
                            else if (c.closed_by == CL_ERR) n_err++;
                        }
                    }
                }
            }
        }

        // ---- 4) --safe-close: 仅当**更新的连接已收到数据** ⇒ 关最旧 fd（fd 数控制；默认关） ----
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

        // ---- 5) 周期行 + 工作线程频率自采样（R2 口径） ----
        now = p7b_io_now_s();
        if (rep.due(now)) {
            long long ce = 0, cc = 0, cb = 0;
            for (size_t i = 0; i < conns.size(); i++) {
                if (conns[i].state == ST_ESTAB) ce++;
                else if (conns[i].state == ST_CONNECTING) cc++;
                cb += conns[i].bytes;
            }
            printf("CHURN_T t=%.1f conns=%zu estab=%lld connecting=%lld connfail=%lld eof=%lld "
                   "reset=%lld err=%lld closed_safe=%lld bytes=%lld rx_MBps=%.3f CPU_FREQ_KHZ=%s\n",
                   rep.since(now), conns.size(), ce, cc, n_connfail, n_eof, n_reset, n_err,
                   n_safe_closed, cb, (cb - bytes_prev) / 1e6, p7baff_work_freq_khz().c_str());
            fflush(stdout);
            bytes_prev = cb;
            rep.mark(now);
        }
        p7baff_work_freq_tick();
    }

    // =======================================================================
    // 收尾：逐连接判定 + 报告 + 候选落盘
    // =======================================================================
    double t_fin = p7b_io_now_s();
    long long v_off0 = 0, v_offk = 0, v_nomatch = 0, v_cand_full = 0, v_cand_short = 0;
    long long v_short = 0, v_nodata = 0;
    long long n_dumps = 0, n_dump_skip = 0, n_dump_fail = 0;
    bool dump_none_warned = false;

    for (size_t i = 0; i < conns.size(); i++) {
        ChurnConn &c = conns[i];
        size_t win = c.prefix_len;
        if (win > (size_t)scan_bytes) win = (size_t)scan_bytes;
        c.scan_n = (long long)win;
        if (c.prefix_len == 0) {
            c.restart_off = -2;                    // na: 一个字节都没收到 ⇒ 判不了
            v_nodata++;
        } else if (c.prefix_len < CHURN_NEEDLE_LEN) {
            c.restart_off = -2;                    // na: 连针都装不下
            v_short++;
        } else {
            c.restart_off = churn_scan_restart(c.prefix, win, needle, CHURN_NEEDLE_LEN);
            if (c.restart_off == 0)      v_off0++;
            else if (c.restart_off > 0)  v_offk++;
            else {
                v_nomatch++;                       // -1 = 命中候选
                if (win == (size_t)scan_bytes) v_cand_full++;
                else                           v_cand_short++;
            }
        }
        char off_s[32];
        if (c.restart_off == -2) strcpy(off_s, "na");
        else                     sprintf(off_s, "%lld", c.restart_off);
        double last_act = (c.bytes > 0) ? c.t_last_rx : (c.t_estab > 0 ? c.t_estab : c.t_start);
        double idle_ms = (t_fin - last_act) * 1e3;
        printf("CHURN conn=%lld bytes=%lld restart@off=%s idle_ms=%.3f state=%s why=%d why_str=%s"
               " closed_by=%s reads=%lld scan_bytes=%lld prefix_bytes=%zu dur_ms=%.3f"
               " estab_ms=%.3f last_rx_ms=%.3f CPU_FREQ_KHZ=%s\n",
               c.idx, c.bytes, off_s, idle_ms, churn_state_str(c), c.why,
               c.why ? strerror(c.why) : "-",
               c.closed_by == CL_SAFE ? "safe_close" : (c.closed_by == CL_NONE ? "-" : churn_state_str(c)),
               c.reads, c.scan_n, c.prefix_len,
               (t_fin - c.t_start) * 1e3,
               (c.t_estab > 0 ? (c.t_estab - c.t_start) * 1e3 : -1.0),
               (c.bytes > 0 ? (t_fin - c.t_last_rx) * 1e3 : -1.0),
               p7baff_work_freq_khz().c_str());

        // ---- 候选落盘（restart@off == -1）----
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
    // ⚠️ 速率的分母**只能**是连接窗口：`--hold-s` 那一段（只读干、不新建连接）若混进分母，
    //    10% 的 hold 会把 100/s 读成 90/s（实测踩到：3 s + hold 3 s ⇒ 读到 49.9/s）
    //    ⇒ 两个窗口都打出来，`rate_per_s` 一律按 `conn_window_s` 算。
    double conn_window_s = ((t_fin < t_conn_end) ? t_fin : t_conn_end) - t0;
    printf("CHURN_SUM conns=%zu estab=%lld connecting=%lld connfail=%lld eof=%lld reset=%lld "
           "err=%lld closed_safe=%lld bytes=%lld window_s=%.3f conn_window_s=%.3f "
           "rate_per_s=%.3f estab_rate_per_s=%.3f "
           "gap_max_ms=%.3f verdict_off0=%lld verdict_offk=%lld candidates=%lld "
           "candidates_full=%lld candidates_short=%lld short_lt32=%lld nodata=%lld "
           "dumps=%lld dumps_skipped=%lld dump_fail=%lld cap_hit=%d safe_close=%d needle_len=%zu "
           "scan_bytes=%ld CPU_FREQ_KHZ=%s\n",
           conns.size(), n_estab_now, n_connecting_now, n_connfail, n_eof, n_reset, n_err,
           n_safe_closed, bytes_total, window_s, conn_window_s,
           conn_window_s > 0 ? (double)conns.size() / conn_window_s : 0.0,
           conn_window_s > 0 ? (double)(n_estab_now + n_safe_closed + n_eof + n_reset + n_err) / conn_window_s : 0.0,
           gap_max_ms, v_off0, v_offk, v_nomatch, v_cand_full, v_cand_short, v_short, v_nodata,
           n_dumps, n_dump_skip, n_dump_fail, cap_hit ? 1 : 0, safe_close ? 1 : 0,
           CHURN_NEEDLE_LEN, scan_bytes, p7baff_work_freq_khz().c_str());
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
