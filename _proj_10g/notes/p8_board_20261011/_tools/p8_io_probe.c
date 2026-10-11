/* p8_io_probe.c -- P8 板上现核: 寄存器窗口 (user BAR) 与 C2H 环设备的**取数法**
 *   背景: p7b_mir_dump.cpp 原用 lseek+read 访问 /dev/xdma0_user ⇒ 板上实测
 *         `FATAL: read @0x000: Illegal seek` (ESPIPE) —— 因为 ctrl_fops 没有 llseek
 *         (驱动源码 `xdma/cdev_ctrl.c:262` 的表里无 .llseek), 而 `reg_rw` 一直用的是 **mmap**。
 *   本探针逐条测: (1) user mmap / (2) user pread / (3) user lseek(负对照) /
 *                (4) c2h lseek+read / (5) c2h pread。
 *   用法: timeout 20 ./p8_io_probe     (需要 root)
 *   编译: gcc -O2 -o p8_io_probe p8_io_probe.c
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

int main(void) {
    /* (1)(2)(3) user BAR: 1 MB */
    int fdu = open("/dev/xdma0_user", O_RDWR | O_SYNC);
    if (fdu < 0) { perror("open user"); return 2; }
    volatile uint32_t *m = mmap(NULL, 1u << 20, PROT_READ | PROT_WRITE, MAP_SHARED, fdu, 0);
    if (m == MAP_FAILED) { perror("mmap user"); return 2; }
    printf("USER_MMAP ok magic=%08x bid=%08x w70_138=%08x unimpl_14c=%08x\n",
           m[0x000 / 4], m[0x004 / 4], m[0x138 / 4], m[0x14C / 4]);

    uint32_t v = 0;
    errno = 0;
    ssize_t n = pread(fdu, &v, 4, 0);
    printf("USER_PREAD n=%zd v=%08x errno=%d(%s)\n", n, v, errno, strerror(errno));

    errno = 0;
    off_t o = lseek(fdu, 0, SEEK_SET);
    printf("USER_LSEEK ret=%ld errno=%d(%s)  (负对照: 预期 ESPIPE)\n", (long)o, errno, strerror(errno));

    /* (4)(5) c2h 环设备 */
    int fdc = open("/dev/xdma0_c2h_0", O_RDONLY);
    if (fdc < 0) { perror("open c2h"); return 2; }
    uint32_t rbuf[8];
    errno = 0;
    off_t o2 = lseek(fdc, 0, SEEK_SET);
    printf("C2H_LSEEK ret=%ld errno=%d(%s)\n", (long)o2, errno, strerror(errno));
    errno = 0;
    ssize_t r1 = read(fdc, rbuf, 32);
    printf("C2H_READ32 n=%zd errno=%d(%s) words=%08x %08x %08x %08x\n",
           r1, errno, strerror(errno), rbuf[0], rbuf[1], rbuf[2], rbuf[3]);

    errno = 0;
    ssize_t r2 = pread(fdc, rbuf, 32, 4096);
    printf("C2H_PREAD@4096 n=%zd errno=%d(%s) words=%08x %08x %08x %08x\n",
           r2, errno, strerror(errno), rbuf[0], rbuf[1], rbuf[2], rbuf[3]);
    printf("PROBE_DONE\n");
    return 0;
}
