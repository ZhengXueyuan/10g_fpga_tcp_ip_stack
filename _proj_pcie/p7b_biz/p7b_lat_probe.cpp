// p7b_lat_probe.cpp -- small E1 latency probe for the P11 board.
//   Modes:
//     tcp : nonblocking connect() handshake RTT, immediate RST close
//     udp : send payload --bytes, wait for echo, measure RTT
//   Output: one LAT_SUMMARY line + optional CSV (seq,us,status).
//   No affinity dependency; run under `ip netns exec nsb` for port B probes.
#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>
#include <algorithm>
#include <cerrno>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <string>
#include <vector>

static double now_us() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1e6 + ts.tv_nsec / 1e3;
}

static void sleep_until(double t_us) {
    double d = t_us - now_us();
    if (d <= 0) return;
    struct timespec ts;
    ts.tv_sec = (time_t)(d / 1e6);
    ts.tv_nsec = (long)((d - ts.tv_sec * 1e6) * 1e3);
    nanosleep(&ts, nullptr);
}

static int parse_int(const char *s, int def) {
    char *e = nullptr;
    long v = strtol(s, &e, 0);
    return (e && *e == 0) ? (int)v : def;
}

static void usage() {
    fprintf(stderr,
            "usage: p7b_lat_probe --mode tcp|udp --host IP --port P --count N "
            "[--interval-ms 5] [--timeout-ms 100] [--bytes 64] [--csv FILE]\n");
}

int main(int argc, char **argv) {
    std::string mode, host, csv;
    int port = 8080, count = 1000, interval_ms = 5, timeout_ms = 100, bytes = 64;
    bool check = true;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--mode" && i + 1 < argc) mode = argv[++i];
        else if (a == "--host" && i + 1 < argc) host = argv[++i];
        else if (a == "--port" && i + 1 < argc) port = parse_int(argv[++i], port);
        else if (a == "--count" && i + 1 < argc) count = parse_int(argv[++i], count);
        else if (a == "--interval-ms" && i + 1 < argc) interval_ms = parse_int(argv[++i], interval_ms);
        else if (a == "--timeout-ms" && i + 1 < argc) timeout_ms = parse_int(argv[++i], timeout_ms);
        else if (a == "--bytes" && i + 1 < argc) bytes = parse_int(argv[++i], bytes);
        else if (a == "--no-check") check = false;
        else if (a == "--csv" && i + 1 < argc) csv = argv[++i];
        else { usage(); return 2; }
    }
    if ((mode != "tcp" && mode != "udp") || host.empty() || count <= 0 || port <= 0 ||
        port > 65535 || interval_ms < 0 || timeout_ms <= 0 || bytes <= 0 || bytes > 1472) {
        usage(); return 2;
    }

    struct sockaddr_in dst{};
    dst.sin_family = AF_INET;
    dst.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, host.c_str(), &dst.sin_addr) != 1) {
        fprintf(stderr, "bad host %s\n", host.c_str()); return 2;
    }
    const int timeout = timeout_ms;
    std::vector<long long> samples;
    std::vector<int> status;
    samples.reserve(count); status.reserve(count);
    int ok = 0, loss = 0, bad = 0;

    for (int i = 0; i < count; i++) {
        double t0 = now_us();
        bool good = false;
        int st = 0;
        if (mode == "tcp") {
            int fd = socket(AF_INET, SOCK_STREAM, 0);
            if (fd < 0) { st = -1; }
            else {
                int fl = fcntl(fd, F_GETFL, 0);
                fcntl(fd, F_SETFL, fl | O_NONBLOCK);
                int rc = connect(fd, (struct sockaddr *)&dst, sizeof(dst));
                if (rc == 0) {
                    good = true;
                } else if (errno == EINPROGRESS) {
                    struct pollfd pfd{fd, POLLOUT, 0};
                    int pr = poll(&pfd, 1, timeout);
                    if (pr > 0) {
                        int err = 0; socklen_t el = sizeof(err);
                        if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &el) == 0 && err == 0)
                            good = true;
                        else st = err ? err : -1;
                    } else st = (pr == 0) ? -2 : -3;
                } else st = errno;
                struct linger lg{1, 0};
                setsockopt(fd, SOL_SOCKET, SO_LINGER, &lg, sizeof(lg));
                close(fd);
            }
        } else {
            int fd = socket(AF_INET, SOCK_DGRAM, 0);
            if (fd < 0) { st = -1; }
            else {
                if (connect(fd, (struct sockaddr *)&dst, sizeof(dst)) != 0) st = errno;
                else {
                    std::vector<unsigned char> tx(bytes);
                    for (int k = 0; k < bytes; k++) tx[k] = (unsigned char)(0x5a ^ (i * 7 + k));
                    ssize_t n = send(fd, tx.data(), tx.size(), 0);
                    if (n != (ssize_t)tx.size()) st = (n < 0) ? errno : -4;
                    else {
                        struct pollfd pfd{fd, POLLIN, 0};
                        int pr = poll(&pfd, 1, timeout);
                        if (pr > 0) {
                            std::vector<unsigned char> rx(bytes + 16);
                            ssize_t r = recv(fd, rx.data(), rx.size(), 0);
                            if (r == (ssize_t)tx.size() && (!check || memcmp(rx.data(), tx.data(), tx.size()) == 0))
                                good = true;
                            else st = (r < 0) ? errno : -5;
                        } else st = (pr == 0) ? -2 : -3;
                    }
                }
                close(fd);
            }
        }
        double dt = now_us() - t0;
        long long us = (long long)llround(dt);
        status.push_back(good ? 0 : (st ? st : -9));
        samples.push_back(us);
        if (good) ok++; else if (st == -2 || st == -3) loss++; else bad++;
        sleep_until(t0 + interval_ms * 1000.0);
    }

    std::vector<long long> v;
    v.reserve(samples.size());
    for (size_t i = 0; i < samples.size(); i++) if (status[i] == 0) v.push_back(samples[i]);
    std::sort(v.begin(), v.end());
    auto pct = [&](double p) -> long long {
        if (v.empty()) return -1;
        size_t idx = (size_t)ceil(p * (double)v.size()) - 1;
        if (idx >= v.size()) idx = v.size() - 1;
        return v[idx];
    };
    long long mn = v.empty() ? -1 : v.front();
    long long mx = v.empty() ? -1 : v.back();
    double mean = 0; for (auto x : v) mean += (double)x; if (!v.empty()) mean /= (double)v.size();
    printf("LAT_SUMMARY mode=%s host=%s port=%d count=%d ok=%d loss=%d bad=%d check=%d "
           "min_us=%lld p50_us=%lld p90_us=%lld p99_us=%lld max_us=%lld mean_us=%.1f\n",
           mode.c_str(), host.c_str(), port, count, ok, loss, bad, check ? 1 : 0, mn, pct(0.50), pct(0.90),
           pct(0.99), mx, mean);
    if (!csv.empty()) {
        FILE *f = fopen(csv.c_str(), "w");
        if (f) {
            fprintf(f, "seq,us,status\n");
            for (size_t i = 0; i < samples.size(); i++) fprintf(f, "%zu,%lld,%d\n", i, samples[i], status[i]);
            fclose(f);
        }
    }
    return (ok == count) ? 0 : 1;
}
