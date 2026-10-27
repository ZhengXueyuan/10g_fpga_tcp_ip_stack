// ===========================================================================
// p7b_tcp_sink_multi.cpp -- P11 APP8 板级载具：**并发** N 条 TCP 下行接收 + 逐连接图案
//
// 为什么需要它：现役 p7b_tcp_sink 是**逐连接串行**（connect → drain → close → 下一条，
// p7b_tcp_sink.cpp:414-460）⇒ 不能测 8 条连接共享 96KB 池/12KB 配额的行为。本工具
// 一次建 N 条连接（每连接一个线程），各自 poll/recv/校验，全部并发。
//
// 判据（与 DESIGN v6 §5/§6 对齐）：
//   · 每条连接从**自己的流偏移 0** 起校图案（与板侧 app_pattern 每实例 ev_up 复位一致）；
//   · `mism=0` / `first=-1` / `got==maxbytes`（或对端 FIN 截断则 status=EOF_SHORT）；
//   · 退出码 0 = 全部连接满足；1 = 任一失败；2 = 用法/环境错。
//
// ⭐ v6 新增（REVIEW_V5 M8/F9）：
//   · `--send-conns N --send-bytes B`：前 N 条连接各发 B 字节 xorshift 图案（从偏移 0），
//     与接收同线程（poll POLLIN|POLLOUT）；用于 conn0 灌流/8 连接上行臂。
//   · **SO_RCVBUF 在 connect 之前** 设置（p7b_io_connect_to_rcvbuf）—— 否则 SYN 首窗
//     仍是默认 64K，板→PC 的窗口判据不成立。
//   · 见证 `sent=`（内核已接受）与 `unsent=`（SIOCOUTQNSD，尚未上线）；**线上发送
//     字节 = sent − unsent**。conn0 臂里 16KB 可能只上 12KB（板窗关），这是设计预期。
//
// 见证：`MULTI_LIMITS ... check=<seq|lane8>`；`PIN_RULE=none UNPINNED=1`（不自动绑核；
//   需要绑核时由外层 taskset 指定，并把命令行记进 raw）。速率读数在无 PIN_CPU 见证时
//   **只作形态描述，不作速率判据**（全局 #62 口径）。
//
// ⚠️ 不复用/不修改 p7b_tcp_sink.cpp（它是对照臂）。本文件独立。
// ===========================================================================
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <sys/socket.h>
#include <unistd.h>
#if defined(__linux__)
#include <sys/ioctl.h>
#include <linux/sockios.h>
#endif

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "p7b_io.h"
#include "p7b_pattern.h"

enum {
    ST_OK = 0,
    ST_EOF_SHORT = 1,
    ST_STALL = 2,
    ST_ERR = 3,
    ST_CONNECT_FAIL = 4
};

struct ConnRes {
    int id;
    int status;
    int err;
    long long got;
    long long mism;
    long long first;
    double wall_s;
    double mbps;
    long long sent;      // v6: 内核已接受的上行字节
    long long unsent;    // v6: SIOCOUTQNSD (尚未上线的字节)
    int lport;           // v6: 本端端口 (4-tuple 对账用; 0 = 未知)
};

struct ConnArg {
    int id;
    std::string host;
    int port;
    long long maxbytes;
    int rcvbuf;
    int poll_ms;
    int stall_n;
    double deadline;     // CLOCK_MONOTONIC 绝对时刻
    int check_mode;
    long long send_bytes; // v6: 本连接上行字节 (0 = 不发)
    int send_on;
    ConnRes *res;
};

static void *conn_main(void *p) {
    ConnArg *a = (ConnArg *)p;
    ConnRes *r = a->res;
    r->id = a->id; r->status = ST_OK; r->err = 0;
    r->got = 0; r->mism = 0; r->first = -1; r->wall_s = 0; r->mbps = 0;
    r->sent = 0; r->unsent = 0; r->lport = 0;

    int why = 0;
    // v6: rcvbuf **在 connect 之前** (SYN 窗口)
    int fd = p7b_io_connect_to_rcvbuf(a->host.c_str(), a->port, 5, a->rcvbuf, &why);
    if (fd < 0) {
        r->status = ST_CONNECT_FAIL; r->err = why;
        return nullptr;
    }
    struct sockaddr_in la{};
    socklen_t ll = sizeof(la);
    if (getsockname(fd, (struct sockaddr *)&la, &ll) == 0) r->lport = (int)ntohs(la.sin_port);

    double t0 = p7b_io_now_s();
    P7bPat pat(0);                 // 下行: 每连接偏移 0
    P7bPat tx(0);                  // 上行: 每连接偏移 0 (与 app_pattern rx_lfsr 复位一致)
    std::vector<uint8_t> buf(64 * 1024);
    std::vector<uint8_t> sbuf(64 * 1024);
    int tmo = 0;
    long long sent = 0, sp = 0, chunk = 0;
    const bool sending = (a->send_on && a->send_bytes > 0);

    for (;;) {
        if (p7b_io_now_s() >= a->deadline) { r->status = ST_STALL; break; }
        const bool want_in = (r->got < a->maxbytes);
        const bool want_out = sending && (sent < a->send_bytes);
        if (!want_in) break;      // 接收目标完成即收; 发送残余由 sent/unsent 见证
        if (!want_in && !want_out) break;

        struct pollfd pf;
        pf.fd = fd;
        pf.events = (short)((want_in ? POLLIN : 0) | (want_out ? POLLOUT : 0));
        pf.revents = 0;
        int pr;
        do { pr = poll(&pf, 1, a->poll_ms); } while (pr < 0 && errno == EINTR);
        if (pr == 0) {
            if (++tmo >= a->stall_n) { r->status = ST_STALL; break; }
            continue;
        }
        if (pr < 0) { r->status = ST_ERR; r->err = errno; break; }
        tmo = 0;

        if (want_out && (pf.revents & (POLLOUT | POLLERR | POLLHUP))) {
            if (sp == 0) {
                long long remain = a->send_bytes - sent;
                chunk = (remain < (long long)sbuf.size()) ? remain : (long long)sbuf.size();
                tx.fill(sbuf.data(), (size_t)chunk);
                sp = chunk;
            }
            ssize_t n = send(fd, sbuf.data() + (chunk - sp), (size_t)sp, MSG_NOSIGNAL);
            if (n > 0) {
                sp -= (long long)n; sent += (long long)n;
            } else if (n < 0) {
                if (!p7b_io_retryable(errno)) { r->status = ST_ERR; r->err = errno; break; }
            } else {
                r->status = ST_ERR; r->err = EPIPE; break;
            }
        }

        if (want_in && (pf.revents & (POLLIN | POLLERR | POLLHUP))) {
            ssize_t n = recv(fd, buf.data(), buf.size(), 0);
            if (n == 0) { r->status = ST_EOF_SHORT; break; }
            if (n < 0) {
                if (p7b_io_retryable(errno)) continue;
                r->status = ST_ERR; r->err = errno; break;
            }
            uint64_t mis = 0;
            long long f = (a->check_mode == P7B_CHECK_LANE8)
                              ? pat.check_lane8(buf.data(), (size_t)n, &mis)
                              : pat.check_seq(buf.data(), (size_t)n, &mis);
            if (f >= 0 && r->first < 0) r->first = r->got + f;
            r->mism += (long long)mis;
            r->got += (long long)n;
        }
    }
#if defined(__linux__) && defined(SIOCOUTQNSD)
    {
        int q = 0;
        if (ioctl(fd, SIOCOUTQNSD, &q) == 0) r->unsent = (long long)q;
    }
#endif
    r->sent = sent;
    close(fd);
    r->wall_s = p7b_io_now_s() - t0;
    if (r->wall_s > 0) r->mbps = (double)r->got * 8.0 / r->wall_s / 1e6;
    return nullptr;
}

static void usage(const char *prog) {
    fprintf(stderr,
        "usage: %s --host H [--port P] [--conns N] [--maxbytes B] [--seconds S]\n"
        "          [--rcvbuf B] [--poll-ms MS] [--stall-n K] [--check seq|lane8]\n"
        "          [--send-conns N] [--send-bytes B] [--send-pattern xorshift]\n"
        "  default: port=8080 conns=8 maxbytes=16777216 seconds=60 rcvbuf=1048576\n"
        "           poll-ms=5000 stall-n=3 check=seq send-conns=0 send-bytes=0\n"
        "  exit: 0 all conns ok && mism==0 ; 1 any failure ; 2 usage/env\n",
        prog);
}

int main(int argc, char **argv) {
    signal(SIGPIPE, SIG_IGN);
    std::string host;
    int port = 8080, conns = 8, poll_ms = 5000, stall_n = 3;
    long long maxbytes = 16LL * 1024 * 1024;
    int secs = 60, rcvbuf = 1 << 20;
    const char *check = "seq";
    const char *send_pattern = "xorshift";
    int send_conns = 0;
    long long send_bytes = 0;

    for (int i = 1; i < argc; i++) {
        std::string k = argv[i];
        auto nx = [&]() -> const char * {
            if (i + 1 >= argc) { usage(argv[0]); exit(2); }
            return argv[++i];
        };
        if (k == "--host") host = nx();
        else if (k == "--port") port = atoi(nx());
        else if (k == "--conns") conns = atoi(nx());
        else if (k == "--maxbytes") maxbytes = atoll(nx());
        else if (k == "--seconds") secs = atoi(nx());
        else if (k == "--rcvbuf") rcvbuf = atoi(nx());
        else if (k == "--poll-ms") poll_ms = atoi(nx());
        else if (k == "--stall-n") stall_n = atoi(nx());
        else if (k == "--check") check = nx();
        else if (k == "--send-conns") send_conns = atoi(nx());
        else if (k == "--send-bytes") send_bytes = atoll(nx());
        else if (k == "--send-pattern") send_pattern = nx();
        else if (k == "--help" || k == "-h") { usage(argv[0]); return 0; }
        else { fprintf(stderr, "unknown arg: %s\n", k.c_str()); usage(argv[0]); return 2; }
    }
    if (host.empty()) { usage(argv[0]); return 2; }
    if (conns <= 0 || conns > 64 || maxbytes <= 0 || poll_ms <= 0 || stall_n <= 0) {
        fprintf(stderr, "bad numeric argument\n"); return 2;
    }
    if (send_conns < 0 || send_conns > conns || send_bytes < 0) {
        fprintf(stderr, "bad --send-conns/--send-bytes\n"); return 2;
    }
    if (send_conns > 0 && send_bytes == 0) {
        fprintf(stderr, "--send-conns>0 requires --send-bytes>0\n"); return 2;
    }
    if (strcmp(send_pattern, "xorshift") != 0) {
        fprintf(stderr, "bad --send-pattern '%s' (only xorshift)\n", send_pattern); return 2;
    }
    if (p7b_check_mode_parse(check) != 0) {
        fprintf(stderr, "bad --check '%s' (seq|lane8)\n", check); return 2;
    }
    printf("MULTI_BEGIN conns=%d host=%s port=%d maxbytes=%lld seconds=%d\n",
           conns, host.c_str(), port, maxbytes, secs);
    printf("MULTI_LIMITS conns=%d maxbytes=%lld rcvbuf=%d poll_ms=%d stall_n=%d check=%s "
           "send_conns=%d send_bytes=%lld send_pattern=%s\n",
           conns, maxbytes, rcvbuf, poll_ms, stall_n, p7b_check_mode_name(),
           send_conns, send_bytes, send_pattern);
    cpu_set_t set;
    if (sched_getaffinity(0, sizeof(set), &set) == 0) {
        unsigned long long mask = 0;
        for (int c = 0; c < CPU_SETSIZE && c < 64; c++)
            if (CPU_ISSET(c, &set)) mask |= (1ULL << c);
        printf("PIN_RULE=none UNPINNED=1 ALLOWED_MASK=0x%llx\n", mask);
    } else {
        printf("PIN_RULE=none UNPINNED=1 ALLOWED_MASK=? \n");
    }

    double deadline = p7b_io_now_s() + (double)secs;
    std::vector<ConnRes> res((size_t)conns);
    std::vector<ConnArg> args((size_t)conns);
    std::vector<pthread_t> th((size_t)conns);
    for (int i = 0; i < conns; i++) {
        int on = (i < send_conns) ? 1 : 0;
        args[i] = ConnArg{i, host, port, maxbytes, rcvbuf, poll_ms, stall_n,
                          deadline, p7b_check_mode_get(), send_bytes, on, &res[i]};
    }
    double t_start = p7b_io_now_s();
    for (int i = 0; i < conns; i++) {
        if (pthread_create(&th[i], nullptr, conn_main, &args[i]) != 0)
            p7b_io_die("pthread_create");
    }
    for (int i = 0; i < conns; i++) pthread_join(th[i], nullptr);
    double wall = p7b_io_now_s() - t_start;

    long long tot_bytes = 0, tot_mism = 0, tot_sent = 0, tot_unsent = 0;
    int ok = 0, shortc = 0, stall = 0, err = 0;
    for (int i = 0; i < conns; i++) {
        ConnRes &r = res[i];
        tot_bytes += r.got; tot_mism += r.mism;
        tot_sent += r.sent; tot_unsent += r.unsent;
        if (r.status == ST_OK && r.got == maxbytes && r.mism == 0) ok++;
        else if (r.status == ST_EOF_SHORT) shortc++;
        else if (r.status == ST_STALL) stall++;
        else err++;
        printf("MULTI_CONN id=%d status=%d err=%d got=%lld want=%lld mism=%lld first=%lld "
               "wall=%.3f Mbps=%.1f lport=%d sent=%lld unsent=%lld\n",
               r.id, r.status, r.err, r.got, maxbytes, r.mism, r.first, r.wall_s, r.mbps,
               r.lport, r.sent, r.unsent);
        fflush(stdout);
    }
    double agg = (wall > 0) ? (double)tot_bytes * 8.0 / wall / 1e6 : 0.0;
    printf("MULTI_SUM conns=%d ok=%d eof_short=%d stall=%d err=%d bytes=%lld mism=%lld "
           "wall=%.3f agg_Mbps=%.1f check=%s sent=%lld unsent=%lld\n",
           conns, ok, shortc, stall, err, tot_bytes, tot_mism, wall, agg,
           p7b_check_mode_name(), tot_sent, tot_unsent);
    return (ok == conns && tot_mism == 0) ? 0 : 1;
}
