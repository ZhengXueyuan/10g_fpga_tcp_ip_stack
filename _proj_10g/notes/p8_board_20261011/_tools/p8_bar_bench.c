/* p8_bar_bench.c -- P8: user BAR (寄存器窗口) 单次读延迟基准 (mmap vs pread)
 *   动因: bar1/bar2/bar3 的 mir_dump 读 131 KB 用了 30 s (rate_Bps≈4.4 KB/s) ⇒ 疑每次读 ~1 ms。
 *   用法: ./p8_bar_bench [n]      (需要 root)
 *   编译: gcc -O2 -o p8_bar_bench p8_bar_bench.c
 */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

static double now_s(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

int main(int argc, char **argv) {
    int n = (argc > 1) ? atoi(argv[1]) : 2000;
    int fd = open("/dev/xdma0_user", O_RDWR | O_SYNC);
    if (fd < 0) { perror("open"); return 2; }
    volatile uint32_t *m = mmap(0, 1u << 20, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (m == MAP_FAILED) { perror("mmap"); return 2; }
    uint32_t sink = 0;

    for (int pass = 0; pass < 2; pass++) {
        double t0 = now_s();
        for (int i = 0; i < n; i++) sink += (pass == 0) ? m[0x13C / 4] : m[0x00 / 4];
        double el = now_s() - t0;
        printf("BAR_MMAP pass=%d addr=%s n=%d total=%.4fs per_read=%.2fus (sink=%08x)\n",
               pass, pass == 0 ? "0x13C" : "0x000", n, el, el / n * 1e6, sink & 0xF);
        fflush(stdout);
    }
    double t0 = now_s();
    for (int i = 0; i < n; i++) { uint32_t v; if (pread(fd, &v, 4, 0x04) == 4) sink += v; }
    double el = now_s() - t0;
    printf("BAR_PREAD addr=0x004 n=%d total=%.4fs per_read=%.2fus\n", n, el, el / n * 1e6);
    return 0;
}
