// aio_probe.c -- 经典 AIO 在 /dev/xdma0_c2h_0 上的**最小行为探针** (2026-10-13 宿主读循环轮)
//   目的 (三个问题, 每个都打印后再答):
//     Q1 io_setup / io_submit 在本驱动上**能不能收单** (返回 1)?
//     Q2 数据流起来后, iocb 的完成语义 = ki_complete -res=字节数?
//     Q3 ⭐⭐ **带着未完成的 iocb 退出** —— 进程会不会挂在内核侧 (exit_aio 等请求完成)?
//        判法: 外部 timeout 包裹 + 打印 "PROBE_EXIT_BEGIN" 后 exit(0); 若脚本报 124 = 挂死。
//   用法 (对端 root): ./aio_probe <dev> <file-of-bytes-to-read:hmm> <- 见下方 argv>
//     ./aio_probe submit  <dev> <bytes> <depth>   # 只提交不收割 (Q1) —— 收尾 io_getevents 有界等
//     ./aio_probe read    <dev> <bytes> <depth>   # 提交 + 收割 (Q2; 需要数据在流)
//   注: 只读探针; 不改任何寄存器 (镜像由调用方 arm)。
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#include <sys/syscall.h>
#include <linux/aio_abi.h>

static long io_setup_w(unsigned nr, aio_context_t *ctx) { return syscall(__NR_io_setup, nr, ctx); }
static long io_submit_w(aio_context_t ctx, long n, struct iocb **p) { return syscall(__NR_io_submit, ctx, n, p); }
static long io_getevents_w(aio_context_t ctx, long min_nr, long nr, struct io_event *ev, struct timespec *ts) {
    return syscall(__NR_io_getevents, ctx, min_nr, nr, ev, ts);
}
static long io_destroy_w(aio_context_t ctx) { return syscall(__NR_io_destroy, ctx); }
static long io_cancel_w(aio_context_t ctx, struct iocb *iocb, struct io_event *ev) {
    return syscall(__NR_io_cancel, ctx, iocb, ev);
}
static double now_s(void) { struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts); return ts.tv_sec + ts.tv_nsec * 1e-9; }

int main(int argc, char **argv) {
    if (argc < 4) { fprintf(stderr, "usage: %s submit|read <dev> <bytes> [depth]\n", argv[0]); return 2; }
    const char *mode = argv[1], *dev = argv[2];
    size_t bytes = (size_t)strtoull(argv[3], NULL, 0);
    int depth = (argc > 4) ? atoi(argv[4]) : 1;
    size_t chunk = bytes / (size_t)(depth > 0 ? depth : 1);
    chunk &= ~(size_t)4095;                       // 4 KB 对齐
    if (chunk == 0) { fprintf(stderr, "chunk=0\n"); return 2; }
    void *buf = NULL;
    if (posix_memalign(&buf, 4096, bytes)) { fprintf(stderr, "alloc fail\n"); return 2; }
    memset(buf, 0, bytes);
    int fd = open(dev, O_RDONLY);
    if (fd < 0) { fprintf(stderr, "PROBE open(%s): %s\n", dev, strerror(errno)); return 2; }
    printf("PROBE_OPEN fd=%d ok\n", fd);
    aio_context_t ctx = 0;
    long rc = io_setup_w(1024, &ctx);
    printf("PROBE_IO_SETUP rc=%ld ctx=%llu\n", rc, (unsigned long long)ctx);
    if (rc < 0) return 2;
    struct iocb *cbs = calloc((size_t)depth, sizeof(struct iocb));
    struct iocb **list = calloc((size_t)depth, sizeof(struct iocb *));
    double t0 = now_s();
    long submitted = 0;
    for (int i = 0; i < depth; i++) {
        struct iocb *c = &cbs[i];
        memset(c, 0, sizeof(*c));
        c->aio_data = (unsigned long long)i;
        c->aio_lio_opcode = IOCB_CMD_PREAD;
        c->aio_fildes = (unsigned)fd;
        c->aio_buf = (unsigned long long)(unsigned char *)buf + (unsigned long long)i * chunk;
        c->aio_nbytes = (unsigned)chunk;
        c->aio_offset = 0;
        list[i] = c;
    }
    long sn = io_submit_w(ctx, depth, list);
    printf("PROBE_IO_SUBMIT want=%d got=%ld errno=%d(%s) dt=%.3fms\n",
           depth, sn, errno, strerror(errno), (now_s() - t0) * 1e3);
    if (sn > 0) submitted = sn;
    if (strcmp(mode, "read") == 0) {
        struct io_event evs[64];
        double td = now_s();
        while (submitted > 0) {
            struct timespec ts = {0, 200000000};
            long n = io_getevents_w(ctx, 1, 64, evs, &ts);
            if (n <= 0) {
                if (now_s() - td > 5.0) { printf("PROBE_READ_TMO submitted=%ld (5 s 无完成)\n", submitted); break; }
                continue;
            }
            for (long k = 0; k < n; k++) {
                printf("PROBE_EVENT idx=%llu res=%lld t=%.3fs\n",
                       (unsigned long long)evs[k].data, (long long)evs[k].res, now_s() - t0);
                submitted--;
            }
        }
    } else if (strcmp(mode, "cancel") == 0) {
        // Q4: io_cancel 对"在飞"请求有没有牙? io_destroy 之后退出干不干净?
        struct io_event ev;
        memset(&ev, 0, sizeof(ev));
        long crc = io_cancel_w(ctx, &cbs[depth - 1], &ev);
        printf("PROBE_IO_CANCEL rc=%ld errno=%d(%s) ev.res=%lld\n",
               crc, errno, strerror(errno), (long long)ev.res);
        struct io_event evs[64];
        struct timespec ts = {0, 1000000000};
        long n = io_getevents_w(ctx, 0, 64, evs, &ts);
        printf("PROBE_AFTER_CANCEL events=%ld\n", n);
        for (long k = 0; k < n; k++)
            printf("PROBE_EVENT idx=%llu res=%lld res2=%lld\n",
                   (unsigned long long)evs[k].data, (long long)evs[k].res, (long long)evs[k].res2);
        long drc = io_destroy_w(ctx);
        printf("PROBE_IO_DESTROY rc=%ld errno=%d(%s)\n", drc, errno, strerror(errno));
    } else {
        // submit 模式: **故意不等完成** —— 检验"带在飞 iocb 退出"的行为 (Q3)
        printf("PROBE_LEAVE_PENDING submitted=%ld (故意不收割)\n", submitted);
    }
    printf("PROBE_EXIT_BEGIN pending=%ld\n", submitted);
    fflush(stdout);
    exit(0);
}
