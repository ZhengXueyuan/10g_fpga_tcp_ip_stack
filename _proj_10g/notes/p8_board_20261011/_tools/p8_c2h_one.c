/* p8_c2h_one.c -- P8: 单组合 C2H 读探针 (每次调用只测一个 off/sz, 便于外层 timeout 隔离)
 *   用法: ./p8_c2h_one <off_bytes> <sz_bytes> <reps>
 *   输出: C2H_ONE off=.. sz=.. reps=.. ok=.. short=.. err=.. min_us=.. max_us=.. w0=.. w1=..
 *   编译: gcc -O2 -o p8_c2h_one p8_c2h_one.c
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
    if (argc < 4) { fprintf(stderr, "usage: %s off sz reps\n", argv[0]); return 2; }
    unsigned off = (unsigned)strtoul(argv[1], 0, 0);
    size_t sz = (size_t)strtoul(argv[2], 0, 0);
    int reps = atoi(argv[3]);
    int fd = open("/dev/xdma0_c2h_0", O_RDONLY);
    if (fd < 0) { perror("open"); return 2; }
    static uint8_t buf[1 << 16] __attribute__((aligned(64)));
    int ok = 0, shortr = 0, err = 0; int last_errno = 0;
    double tmin = 1e9, tmax = 0;
    for (int r = 0; r < reps; r++) {
        double a = now_s();
        if (lseek(fd, (off_t)off, SEEK_SET) < 0) { perror("lseek"); return 2; }
        ssize_t n = read(fd, buf, sz);
        double b = now_s();
        if (b - a < tmin) tmin = b - a;
        if (b - a > tmax) tmax = b - a;
        if (n == (ssize_t)sz) ok++;
        else if (n < 0) { err++; last_errno = errno; }
        else shortr++;
        if (r == 0) printf("C2H_ONE off=%u sz=%zu first_n=%zd w0=%08x w1=%08x\n",
                           off, sz, n, ((uint32_t *)buf)[0], ((uint32_t *)buf)[1]);
        fflush(stdout);
    }
    printf("C2H_ONE off=%u sz=%zu reps=%d ok=%d short=%d err=%d min_us=%.1f max_us=%.1f "
           "last_errno=%d(%s)\n", off, sz, reps, ok, shortr, err,
           (ok ? tmin * 1e6 : 0.0), tmax * 1e6, last_errno, strerror(last_errno));
    return (ok == reps) ? 0 : 1;
}
