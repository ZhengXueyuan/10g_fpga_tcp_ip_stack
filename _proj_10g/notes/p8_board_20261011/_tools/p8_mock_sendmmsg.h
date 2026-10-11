// p8_mock_sendmmsg.h -- P8 板级轮: 把 p7b_udp_src 的发送系统调用替换成 mock,
//   以便**确定性**激励"续发路径" (sendmmsg 少发 / EAGAIN 未发)。
//   WHY: 在 loopback 上试过三种手段 (慢消费者 / netem limit=1000 / netem limit=100000 + wmem_max=16K)
//        都**产生不了发端反压** (loopback 把 skb 立刻 orphan ⇒ wmem 不累积; qdisc 满时静默尾丢弃)
//        ⇒ EAGAIN 路径在真机上不可激励 ⇒ 只能在内核之外用 mock 证。
//   用法: 在测试文件里 define 宏重定向后 #include 被测 .cpp (见 p8_mocktest_udp_src.cpp)。
//   语义: 每次调用按 g_script 循环返回"N 个 datagram 已发" (-1 = EAGAIN 未发);
//         mock 把"真正发出去"的字节按顺序追加进 g_wire ⇒ 与 P7bPat(0) 逐字节比对
//         ⇒ **洞** = first_mismatch >= 0。
#pragma once
#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <time.h>
#include <unistd.h>

#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

static std::vector<uint8_t> g_wire;      // "已上线"的字节流 (按 datagram 顺序)
static size_t g_wire_cap   = 0;          // >0 ⇒ 达到即收尾退出 (原版臂用; 它不吃 --bytes)
static int    g_calls      = 0;
static int    g_partials   = 0;          // 少发 (0 < r < vlen) 次数
static int    g_eagains    = 0;          // EAGAIN 次数
// 节奏脚本: 覆盖 1 个/少发/满发/EAGAIN 四种形态 (循环取用)
static int    g_script[]   = {1, 3, 32, 5, 17, -1, 2, 32, 32, 7};
static const int g_script_n = 10;

extern void mock_finish_and_exit();      // 定义在测试文件里 (需要 P7bPat 才能判)

static ssize_t mock_sendmmsg(int fd, struct mmsghdr *msgvec, unsigned int vlen, int flags) {
    (void)fd; (void)flags;
    int k = g_script[g_calls % g_script_n];
    g_calls++;
    if (k < 0) { g_eagains++; errno = EAGAIN; return -1; }      // ⇒ 工具走 EAGAIN 分支
    if ((unsigned)k > vlen) k = (int)vlen;
    for (int i = 0; i < k; i++) {                               // 记录真正发出去的字节
        const uint8_t *p = (const uint8_t *)msgvec[i].msg_hdr.msg_iov[0].iov_base;
        size_t n = (size_t)msgvec[i].msg_hdr.msg_iov[0].iov_len;
        g_wire.insert(g_wire.end(), p, p + n);
    }
    if ((unsigned)k < vlen) g_partials++;
    if (g_wire_cap && g_wire.size() >= g_wire_cap) mock_finish_and_exit();
    return k;
}
static int mock_socket(int, int, int) { return 7; }                         // 假 fd
static int mock_setsockopt(int, int, int, const void *, socklen_t) { return 0; }
static int mock_fcntl(int, int, ...) { return O_RDWR | O_NONBLOCK; }        // set_nonblock 的检查要过
static int mock_poll(struct pollfd *, nfds_t, int) { return 1; }            // 永远"可写" (不真等)
