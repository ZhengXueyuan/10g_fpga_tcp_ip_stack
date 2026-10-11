// p8_udp_rx_check.cpp -- P8 板级轮本地自检: 收 UDP 到恰好 K 字节, 与 P7bPat(0) 逐字节核对
//   用途 = 在碰板子之前, 先验证 `p7b_udp_src --bytes K` 改动的两件事:
//     ① 精确停在 K; ② **无洞** (即"续发语义"生效, partial send 不再跳过图案字节)。
//   判据: RXCHK bytes=K rc=0 first_mismatch=-1  (mism=0); rc=2 = 未收满 (超时)。
//   用法: ./p8_udp_rx_check --port 18081 --bytes 1048576 [--seconds 20] [--slow-ms N]
//   ⭐ --slow-ms N: 每收 --slow-every (默认 64) 个包就 sleep N ms —— 模拟**慢消费者**,
//      逼发端 socket 队列填满 ⇒ EAGAIN ⇒ 激励 `p7b_udp_src` 的**续发路径** (防挖洞的改动)。
//      判据不变 (bytes==K, first_mismatch==-1); 发端侧应出现 poll_tmo>0。
//   编译: g++ -O3 -pthread -o p8_udp_rx_check p8_udp_rx_check.cpp   (同 BUILD.md §2 口径)
#include "p7b_pattern.h"

#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

int main(int argc, char **argv) {
    int port = 18081;
    long long want = 0;
    double secs = 20.0;
    int slow_ms = 0, slow_every = 64;
    for (int i = 1; i < argc; i++) {
        std::string k = argv[i];
        auto nx = [&]() -> const char * {
            if (++i >= argc) { fprintf(stderr, "missing %s\n", k.c_str()); exit(2); }
            return argv[i];
        };
        if (k == "--port") port = atoi(nx());
        else if (k == "--bytes") want = atoll(nx());
        else if (k == "--seconds") secs = atof(nx());
        else if (k == "--slow-ms") slow_ms = atoi(nx());
        else if (k == "--slow-every") slow_every = atoi(nx());
        else { fprintf(stderr, "usage: %s --bytes K [--port 18081] [--seconds 20] [--slow-ms N]\n", argv[0]); return 2; }
    }
    if (slow_every < 1) slow_every = 1;
    if (want <= 0) { fprintf(stderr, "FATAL: --bytes 必填\n"); return 2; }

    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) { perror("socket"); return 2; }
    int rcv = 16 << 20;
    setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &rcv, sizeof(rcv));
    struct timeval tv = {(time_t)1, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    struct sockaddr_in a{};
    a.sin_family = AF_INET; a.sin_port = htons((uint16_t)port); a.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(fd, (struct sockaddr *)&a, sizeof(a)) < 0) { perror("bind"); return 2; }
    printf("RXCHK_LISTEN port=%d want=%lld\n", port, want);
    fflush(stdout);

    std::vector<uint8_t> buf(1 << 20);
    std::vector<uint8_t> got;
    got.reserve((size_t)want + (1 << 20));
    struct timeval t0, tn;
    gettimeofday(&t0, nullptr);
    long long npkts = 0;
    while ((long long)got.size() < want) {
        ssize_t n = recv(fd, buf.data(), buf.size(), 0);
        if (n > 0) {
            got.insert(got.end(), buf.begin(), buf.begin() + n);
            if (slow_ms > 0 && (++npkts % slow_every) == 0) {
                struct timespec ts{(time_t)(slow_ms / 1000), (long)(slow_ms % 1000) * 1000000L};
                nanosleep(&ts, nullptr);
            }
            continue;
        }
        if (n < 0) {
            gettimeofday(&tn, nullptr);
            double el = (tn.tv_sec - t0.tv_sec) + (tn.tv_usec - t0.tv_usec) * 1e-6;
            if (el > secs) break;                    // 超时 (1 s 无包且总时长超限)
        }
    }
    gettimeofday(&tn, nullptr);
    double el = (tn.tv_sec - t0.tv_sec) + (tn.tv_usec - t0.tv_usec) * 1e-6;
    long long fm = -1;
    uint64_t nmis = 0;
    int rc = 0;
    if ((long long)got.size() < want) rc = 2;
    else {
        P7bPat pat(0);
        fm = pat.check(got.data(), got.size(), &nmis);
        if (fm >= 0) rc = 1;
    }
    printf("RXCHK bytes=%zu want=%lld secs=%.3f rc=%d first_mismatch=%lld mism=%llu\n",
           got.size(), want, el, rc, fm, (unsigned long long)nmis);
    return rc;
}
