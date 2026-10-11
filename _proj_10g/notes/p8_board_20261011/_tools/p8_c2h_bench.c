/* p8_c2h_bench.c -- P8: /dev/xdma0_c2h_0 单笔读延迟/错误形态基准 (空载即可跑)
 *   背景: p7b_mir_dump --dma 在板上只读到 85 字/12 s (rate 61 B/s) 且 1 次短读 ⇒ 需实测:
 *         每次 lseek+read 的耗时、随长度/偏移的变化、失败时的 errno。
 *   用法: timeout -k 5 60 ./p8_c2h_bench [reps]
 *   编译: gcc -O2 -o p8_c2h_bench p8_c2h_bench.c
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static double now_s(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

int main(int argc, char **argv) {
    int reps = (argc > 1) ? atoi(argv[1]) : 50;
    int fd = open("/dev/xdma0_c2h_0", O_RDONLY);
    if (fd < 0) { perror("open"); return 2; }
    static uint8_t buf[1 << 20];
    size_t sizes[] = {4, 64, 256, 1024, 4096, 16384};
    unsigned offs[] = {0, 4, 64, 4096};
    for (unsigned si = 0; si < sizeof(sizes) / sizeof(sizes[0]); si++) {
        for (unsigned oi = 0; oi < sizeof(offs) / sizeof(offs[0]); oi++) {
            size_t sz = sizes[si];
            if (offs[oi] + sz > 16384) continue;
            double t0 = now_s();
            int ok = 0, shortr = 0, err = 0, lsek = 0;
            double tmin = 1e9, tmax = 0;
            int last_errno = 0;
            for (int r = 0; r < reps; r++) {
                double a = now_s();
                if (lseek(fd, (off_t)offs[oi], SEEK_SET) < 0) { lsek++; last_errno = errno; break; }
                ssize_t n = read(fd, buf, sz);
                double b = now_s();
                if (b - a < tmin) tmin = b - a;
                if (b - a > tmax) tmax = b - a;
                if (n == (ssize_t)sz) ok++;
                else if (n < 0) { err++; last_errno = errno; }
                else shortr++;
            }
            double el = now_s() - t0;
            printf("C2H_BENCH sz=%5zu off=%5u ok=%3d short=%3d err=%3d lseek_err=%d "
                   "min=%.1fus max=%.1fus avg=%.1fus total=%.3fs last_errno=%d(%s)\n",
                   sz, offs[oi], ok, shortr, err, lsek,
                   (ok ? tmin * 1e6 : 0.0), tmax * 1e6,
                   (ok ? el / reps * 1e6 : 0.0), el, last_errno, strerror(last_errno));
            fflush(stdout);
        }
    }
    return 0;
}
