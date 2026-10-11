// p8_mocktest_udp_src.cpp -- P8: "续发路径"确定性单元测试 (同一脚本跑改版/原版两臂)
//   编译 (对端 /tmp/p8_board):
//     g++ -O2 -o p8_mocktest_fix  p8_mocktest_udp_src.cpp
//     g++ -O2 -DUSE_ORIG -o p8_mocktest_orig p8_mocktest_udp_src.cpp
//   判据:
//     fix  臂: MOCKTEST fix  ... first_mismatch=-1 ... OK     (无洞; 且 wire_bytes == K)
//     orig 臂: MOCKTEST orig ... first_mismatch>=0  ... FAIL   (洞 = 原版行为; 这就是被修的那条)
//   ⚠️ 全部在内存里跑 (无 socket / 无板卡 / 不落盘); mock 见 p8_mock_sendmmsg.h。
#include "p8_mock_sendmmsg.h"

#define sendmmsg   mock_sendmmsg
#define socket     mock_socket
#define setsockopt mock_setsockopt
#define fcntl      mock_fcntl
#define poll       mock_poll
#define main       src_entry_main
#ifdef USE_ORIG
#include "p7b_udp_src_orig.cpp"
#else
#include "p7b_udp_src.cpp"
#endif
#undef main
#undef sendmmsg
#undef socket
#undef setsockopt
#undef fcntl
#undef poll

#include "p7b_pattern.h"

#include <cstdio>
#include <cstdlib>

static const size_t K = 1048576;             // 发端总量 (4 的倍数; 712 整帧 + 1 个 512 B 部分帧)

static int verify_wire(const char *tag, size_t expect) {
    P7bPat pat(0);
    uint64_t nmis = 0;
    long long fm = pat.check(g_wire.data(), g_wire.size(), &nmis);
    int ok = (fm < 0) && (expect == 0 || g_wire.size() == expect);
    printf("MOCKTEST %s wire_bytes=%zu expect=%zu first_mismatch=%lld mism=%llu "
           "calls=%d partials=%d eagain=%d %s\n",
           tag, g_wire.size(), expect, fm, (unsigned long long)nmis,
           g_calls, g_partials, g_eagains, ok ? "OK" : "FAIL");
    return ok ? 0 : 1;
}
void mock_finish_and_exit() { exit(verify_wire("orig(cap)", 0)); }

int main() {
#ifdef USE_ORIG
    g_wire_cap = 2u << 20;                   // 原版不吃 --bytes ⇒ 攒到 2 MB 就收尾判
    char *av[] = {(char *)"p8mock_orig", (char *)"--no-pin", (char *)"--seconds", (char *)"30", nullptr};
    int rc = src_entry_main(4, av);
    (void)rc;                                // 正常不会走到这里 (mock 会先 exit)
    return verify_wire("orig", 0);
#else
    char *av[] = {(char *)"p8mock_fix", (char *)"--no-pin", (char *)"--bytes", (char *)"1048576",
                  (char *)"--seconds", (char *)"30", nullptr};
    int rc = src_entry_main(6, av);
    printf("MOCKTEST fix src_entry_main rc=%d\n", rc);
    return verify_wire("fix", K);
#endif
}
