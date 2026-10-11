// p7b_tcp_src.cpp -- TCP 上行验收 (对端 -> 板): 真实 Linux 栈灌流 + 同连接双向核对
//
// 被测对象: 板上 TCP fast path 的 RX 侧 (mac_rx_10g -> rx_classify -> tcp_rx ->
//           tcp_echo.frame_fifo -> app_pattern 校验器)。板侧计数器: W22(接受帧)/
//           W23(nonmatch)/W0/W1(MAC 收帧/字节)/W3(FCS 错)/W42... (见方案 §4.4)
//
// ⚠️ 两条**结构性**限制 (读源码得出, 方案 §2 有出处):
//   ① 板侧校验器 rtl/app_pattern.v 的 RX 是 **0.889 B/拍** (rtl/app_pattern.v:530-544 每字 1 拍
//      取值 + rw_n 拍逐字节比) => @156.25MHz 天花板 **1.111 Gbps**。实测若停在这个值附近,
//      是 **app 天花板**, 不是 TCP 栈/链路的能力 (RATE 轮教训 #36 的同族陷阱)。
//   ② 板侧 app 发完 1MB 会 AUTO_CLOSE 发 FIN。**半关闭后对端仍可继续发** (TCP 语义), 且
//      板侧 HLS 状态机只在**收到对端 FIN** 时才离开 T_ESTABLISHED
//      (hls/src/layer_tcp.cpp:710-723; 自己发 FIN 不走那条) => 上行测试可以持续跑。
//      但这一条**必须先用本工具的 SRC_EOF_AT 那行验证** (方案 §4.3 步骤 0)。
//
// 用法: p7b_tcp_src --host 192.168.100.2 --port 8080 --seconds 30 [--chunk 65536]
//                    [--pace-bps 0] [--no-verify-down] [--poll-ms 200]
// 输出行 SRC_* / SRC_SUM_* / SRC_DONE; 退出码 0 = 上行无 send 错且(若开核对)下行逐字节干净。
//
// ⭐ 2026-10-09 (R1/R2 用户要求落地): socket 一律 **非阻塞 + 电平触发 poll(LT)**。
//   * **connect 也是非阻塞的** (旧版是阻塞 connect, 之后才置 O_NONBLOCK);
//   * 全程序只有一处 fcntl (set_nonblock 里置 O_NONBLOCK), **从不切回阻塞**;
//   * poll 超时 = 空闲 (确定语义: 计数进 SRC_SUM `poll_tmo=`, 不静默吞); poll 真出错 ⇒ 打行 + 结束
//   * ⛔ **本工具不写盘**: 上行载荷由 p7b_pattern.h **按规则现场生成**后直接 send (无文件/无 --dump);
//     下行校验 = 重生图案**增量逐字节复算**, 同样不落盘。
// 编译 (部署口径 = _proj_10g/notes/p7b_affinity/BUILD.md §2; ⛔ 别再用旧头注释里的 -O3 写法):
//   g++ -O3 -pthread -o p7b_tcp_src p7b_tcp_src.cpp
#include "p7b_pattern.h"
#include "p7b_affinity.h"

#include <arpa/inet.h>
#include <fcntl.h>
#include <linux/sockios.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#include <cerrno>
#include <cstdlib>
#include <string>
#include <vector>

static double now_s() {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

// ------------------------- R1 (2026-10-09): socket 契约 -------------------------
// 全程序**只有这一处 fcntl** —— 只置 O_NONBLOCK, 从不切回阻塞
// (判据: `grep -n "F_SETFL" *.cpp` 只应命中本函数; 出现清 O_NONBLOCK 即违规)。
static void set_nonblock(int fd) {
    int fl = fcntl(fd, F_GETFL, 0);
    if (fl < 0 || fcntl(fd, F_SETFL, fl | O_NONBLOCK) < 0) { perror("fcntl(O_NONBLOCK)"); exit(2); }
    if (!(fcntl(fd, F_GETFL, 0) & O_NONBLOCK)) { fprintf(stderr, "FATAL: O_NONBLOCK 未生效\n"); exit(2); }
}

// 非阻塞 connect: EINPROGRESS -> poll(POLLOUT, 电平触发) -> SO_ERROR。
// 成功 0 / 失败 -1 且 *why = 原因码; 调用者必须把它打进日志 (不许静默)。
static int connect_nb(int fd, const struct sockaddr *sa, socklen_t sl, int timeout_ms, int *why) {
    int r = connect(fd, sa, sl);
    if (r < 0 && errno != EINPROGRESS) { *why = errno; return -1; }
    if (r < 0) {
        struct pollfd p{fd, POLLOUT, 0};
        int pr;
        do { pr = poll(&p, 1, timeout_ms); } while (pr < 0 && errno == EINTR);
        if (pr == 0) { *why = ETIMEDOUT; return -1; }
        if (pr < 0)  { *why = errno; return -1; }
    }
    int err = 0; socklen_t el = sizeof(err);
    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &el) < 0) { *why = errno; return -1; }
    if (err) { *why = err; return -1; }
    return 0;                                     // ⚠️ 返回后 fd **仍是 O_NONBLOCK**
}

int main(int argc, char **argv) {
    argc = p7b_pin_cpu(argc, argv);      // 启动即绑核 (p7b_affinity.h; 剥离本函数自己的选项)
    const char *host = "192.168.100.2";
    int port = 8080, secs = 30, chunk = 65536, poll_ms = 200;
    long long pace = 0;
    long long want_bytes = 0;     // ⭐ P8: --bytes K (0 = 不限; K%4==0 硬前置)
    bool selftest = false, verify_down = true;
    for (int i = 1; i < argc; i++) {
        std::string k = argv[i];
        auto nx = [&]() -> const char * { if (++i >= argc) { fprintf(stderr, "missing %s\n", k.c_str()); exit(2); } return argv[i]; };
        if (k == "--host") host = nx();
        else if (k == "--port") port = atoi(nx());
        else if (k == "--seconds") secs = atoi(nx());
        else if (k == "--chunk") chunk = atoi(nx());
        else if (k == "--pace-bps") pace = atoll(nx());
        else if (k == "--bytes") want_bytes = atoll(nx());          // ⭐ P8
        else if (k == "--poll-ms") poll_ms = atoi(nx());
        else if (k == "--no-verify-down") verify_down = false;
        else if (k == "--selftest") selftest = true;
        else if (k == "--help") {
            printf("p7b_tcp_src --host H --port P [--seconds S] [--chunk B] [--pace-bps BPS] [--poll-ms 200]\n"
                   "  上行: 从连接起点偏移 0 起连续图案流 (现场生成), 灌到板子 (板侧 rcvbuf/窗口自然限速)\n"
                   "  下行: 同一连接上核对板子的 1MB 图案流 (可用 --no-verify-down 关)\n"
                   "  ⛔ 不写盘: 上行按 p7b_pattern.h 规则生成后直接 send; 下行增量复算\n"
                   "  --selftest: 图案自检向量\n");
            return 0;
        } else { fprintf(stderr, "unknown arg %s\n", k.c_str()); return 2; }
    }
    if (selftest) return p7b_pattern_selftest("p7b_tcp_src");
    if (poll_ms < 1) poll_ms = 1;
    // ⭐ P8: K%4==0 硬前置 (镜像窗 v2 §V1.2; 不满足 ⇒ 响亮 exit(2))
    if (want_bytes < 0 || (want_bytes > 0 && want_bytes % 4 != 0)) {
        fprintf(stderr, "FATAL: --bytes %lld 非法 (K%%4==0 是 M1 前置条件)\n", want_bytes);
        return 2;
    }

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) { perror("socket"); return 2; }
    struct sockaddr_in a{};
    a.sin_family = AF_INET; a.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, host, &a.sin_addr) != 1) { fprintf(stderr, "bad host\n"); return 2; }
    set_nonblock(fd);                     // ⭐ socket() 之后**立刻**设, 且全程不切回
    int why = 0;
    if (connect_nb(fd, (struct sockaddr *)&a, sizeof(a), 5000, &why) < 0) {
        fprintf(stderr, "SRC_CONNECT_FAIL why=%d (%s) %s:%d\n", why, strerror(why), host, port);
        return 2;
    }
    printf("SRC_CONNECTED %s:%d\n", host, port);
    if (pace > 0) setsockopt(fd, SOL_SOCKET, SO_MAX_PACING_RATE, &pace, sizeof(pace));

    P7bPat tx(0);                 // 上行: 每连接偏移 0 起
    P7bPat rx(0);                 // 下行: 板侧每连接偏移 0 起
    std::vector<uint8_t> sbuf(chunk), rbuf(1 << 20);
    // ⭐ P8/M1 (2026-10-11): `--bytes K` 精确发满 K 字节即停 + **ppos-续发** (少发不重填,
    //   防 partial send 在图案流里挖洞; 设计件 §V1.2 的前置条件 K%4==0 同 UDP 源)。
    size_t cur_len = (size_t)chunk, tx_off = 0;      // 本段长度 / 本段已发出字节
    long long tx_bytes = 0, rx_bytes = 0, rx_mism_bytes = 0, rx_first_mis = -1;
    long long poll_tmo = 0, poll_err = 0;
    double t0 = now_s(), t_eof = 0;
    int eof_seen = 0, send_err = 0;
    double next_report = t0 + 1.0;
    double t_drain = -1;                  // ⭐ P8: 达到 K 后的"排空等待"起点

    while (now_s() - t0 < secs) {
        // ⭐ P8: 达到 K ⇒ **等发送队列排空再退**。否则进程秒退: 对端下行泛洪撞上正在关闭的
        //   套接字 ⇒ 内核回 RST ⇒ 板侧连接被拆, 已排队未上线的数据整段作废 (实测两跑都只
        //   送达 ~1 个窗口 ≈44–88 KB)。
        if (want_bytes > 0 && tx_bytes >= want_bytes) {
            int outq = -1;
            (void)ioctl(fd, TIOCOUTQ, &outq);
            if (outq == 0) { printf("SRC_DRAINED tx_bytes=%lld\n", tx_bytes); break; }
            if (t_drain < 0) t_drain = now_s();
            else if (now_s() - t_drain > 20.0) {
                printf("SRC_DRAIN_TIMEOUT outq=%d tx_bytes=%lld\n", outq, tx_bytes); break;
            }
        }
        struct pollfd p{fd, 0, 0};
        p.events = POLLIN;
        if (!send_err) p.events |= POLLOUT;
        int pr;
        do { pr = poll(&p, 1, poll_ms); } while (pr < 0 && errno == EINTR);   // ⭐ R1: 电平触发
        double t = now_s();
        if (pr < 0) { poll_err++; printf("SRC_POLL_ERR errno=%d (poll 失败, 本轮结束)\n", errno); break; }
        if (pr == 0) poll_tmo++;             // ⭐ poll 超时 = 空闲; 计数进 SRC_SUM (确定语义, 非静默)
        if (pr > 0 && (p.revents & POLLIN)) {
            ssize_t n = recv(fd, rbuf.data(), rbuf.size(), 0);
            if (n == 0) { if (!eof_seen) { eof_seen = 1; t_eof = t; printf("SRC_EOF_AT %.6f rx_bytes=%lld  (板侧 FIN)\n", t - t0, rx_bytes); } }
            else if (n > 0) {
                rx_bytes += n;
                if (verify_down) {
                    uint64_t nm = 0;
                    long long f = rx.check(rbuf.data(), (size_t)n, &nm);
                    if (f >= 0) { if (rx_first_mis < 0) rx_first_mis = rx_bytes - n + f; rx_mism_bytes += (long long)nm; }
                } else rx.s = p7b_xs_next(rx.s);   // 不核对时也推进, 保持状态一致
            } else if (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) {
                printf("SRC_RECV_ERR errno=%d\n", errno);
            }
        }
        if (pr > 0 && (p.revents & (POLLOUT | POLLERR | POLLHUP)) && !send_err
            && (want_bytes == 0 || tx_bytes < want_bytes)) {   // ⭐ P8: 达 K 后不再发 (走排空等待)
            if (tx_off == 0) {                       // ⭐ 只在"新一段"时定长+填充 (续发语义)
                size_t send_len = (size_t)chunk;
                if (want_bytes > 0) {
                    long long rem = want_bytes - tx_bytes;
                    if ((long long)send_len > rem) send_len = (size_t)rem;
                }
                cur_len = send_len;
                tx.fill(sbuf.data(), cur_len);
            }
            ssize_t n = send(fd, sbuf.data() + tx_off, cur_len - tx_off, MSG_NOSIGNAL);
            if (n > 0) { tx_bytes += n; tx_off += (size_t)n; if (tx_off >= cur_len) tx_off = 0; }
            else if (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) {
                send_err = errno; printf("SRC_SEND_ERR errno=%d tx_bytes=%lld\n", errno, tx_bytes);
            }
        }
        t = now_s();
        if (t >= next_report) {
            printf("SRC_T %.3f tx_MB=%.3f rx_MB=%.3f eof=%d CPU_FREQ_KHZ=%s\n",
                   t - t0, tx_bytes / 1048576.0, rx_bytes / 1048576.0, eof_seen,
                   p7baff_cpu_freq_khz().c_str());   // F9: 周期行尾频率轨迹 (追加, 旧字段一字不动)
            fflush(stdout);
            next_report = t + 1.0;
        }
    }
    double t1 = now_s();
    close(fd);
    printf("SRC_SUM tx_bytes=%lld rx_bytes=%lld dur_s=%.3f tx_Mbps=%.3f rx_Mbps=%.3f "
           "eof_seen=%d eof_at_s=%.3f send_err=%d rx_first_mismatch=%lld rx_mism_bytes=%lld "
           "poll_tmo=%lld poll_err=%lld\n",
           tx_bytes, rx_bytes, t1 - t0, tx_bytes * 8.0 / (t1 - t0) / 1e6, rx_bytes * 8.0 / (t1 - t0) / 1e6,
           eof_seen, t_eof - t0, send_err, rx_first_mis, rx_mism_bytes, poll_tmo, poll_err);
    printf("SRC_DONE\n");
    return (send_err == 0 && tx_bytes > 0 && (!verify_down || rx_first_mis < 0)) ? 0 : 1;
}
