// p7b_mir_dump.cpp -- M1「载荷镜像窗」的主机侧读工具 (user BAR / AXI4-Lite 寄存器窗口)
//
// 被测对象 = 板上 `rtl/app_rx_mirror.v` + `_proj_pcie/rtl/axi_regs.v` 的 MIR 读口:
//   板内: (tap) -> ^0xA5 -> 打包 32 位字 -> fifo_async(dp -> pcie) -> MIR_DATA (读=弹出)
//   主机: 本工具按 `MIR_STATUS.level` 读恰好 level 个 `MIR_DATA` 字, 小端拼字节流落盘。
//
// 协议 (设计件 v2 §V1.1/§V1.3; 地址全部见 `axi_regs.v` 头注释 §M1):
//   0x00 MAGIC (0x50360001) · 0x04 BUILD_ID (必须 == --bid) · 0x18 触发快照 (写 1)
//   0x1C SNAP_STATUS (bit1 done) · 0x13C MIR_STATUS · 0x140 MIR_DATA (读=弹出) · 0x144 MIR_CTRL
//   0x148 MIR_DMA_CNT · **未实现地址 = 0x14C** (MIR 四字之后第一格)
//   MIR_STATUS = {[31:24]=0, [23]src_sel, [22:19]ver, [18]capture_on, [17]any_drop_sticky,
//                 [16]unf_sticky, [15:0]level}
//   MIR_CTRL   = [0]cap_en [1]clr toggle [2]src_sel [3]dma_en;
//                起测顺序 = ① 写 clr=1 (+dma_en) → ② 写 cap_en=1 (+dma_en) → ③ 发包
//                (⭐ 期 A: `--src` 只改 [2], 不动 [0]/[1] 的协议)
//
// ⛔ 四条纪律 (全是本工程踩过的坑):
//   ① **只许 32 位单笔访问** (mmap 侧必须 `volatile uint32_t`): 宽读被拆成多笔 ⇒ 多弹。
//   ② 空读 `MIR_DATA` 会: 返回哨兵 `0x5A5A5A5A` + 置 `unf_sticky` + **不弹** ⇒ 本工具
//      **永不空读** (先读 level, 再读恰好 level 个字)。
//   ③ 读速率**不是**速率判据: 本通道上界 ~4–10 MB/s 量级 (设计件 §2.1, 未实测),
//      且本工具**未接** `p7b_affinity.h` ⇒ 打出的 `MIR_RATE_Bps` 只作形态参考,
//      **不得当板子能力引用** (若后续要用它做速率判据, 必须先补绑核见证, 全局 #62)。
//   ④ `--bytes K` 前置条件 **K % 4 == 0** (v2 §V1.2; 累加器不在 tlast flush ⇒ 尾部
//      <4B 结构性不可观测) ⇒ 不满足时立刻 exit(2) 响亮失败, 不"尽量读"。
//      ⭐ P9-ST 追加: `--stream` 路径的前置条件**更严** = **K % 8 == 0** (P8-STG 起镜像按
//      64 位字打包, 见 `rtl/app_rx_mirror.v:34` "发端总字节数 K 的前置条件 = K % 8 == 0")。
//
// ⭐⭐ 期 B (2026-10-11): `--dma` = C2H DMA 环读路径 (取代 user-BAR 逐字搬运)
//   · 通道 = XDMA 的 C2H 引擎 (`/dev/xdma0_c2h_0`) → 我们自写的 AXI-MM 读从机
//     (`rtl/aximm_c2h_win.v`) → 板内 16 KB 环 (`rtl/mir_dma_ring.v`)。
//   · **取法 = `lseek(fd, 卡内字节偏移, SEEK_SET)` + `read(fd, buf, len)`** —— ⭐⭐ 2026-10-11
//     **板上现核已定稿** (p8_io_probe / p8_c2h_one, 0x1F): c2h 的 `sgdma_fops` 有 llseek;
//     **偏移必须 16 B 对齐** (off=4/8 ⇒ 首次 -1 再读挂死, dmesg `xdma_xfer_submit timed out`),
//     且**每次读固定 ~1 ms 开销** ⇒ 取法 = 16 B 对齐取 + 最小读块 (见 FdRingIo / run_dma);
//     **user BAR 的 `ctrl_fops` 没有 llseek ⇒ lseek 报 ESPIPE**, 故寄存器取法改用 **mmap**
//     (见 FdIo; 与 `reg_rw` 同款)。设计件 §V1.5-② 的"半可定"项就此关闭。
//   · 环 = **幂等只读** (读不移动任何指针) ⇒ 与 BAR 窗口的"读=弹出"语义**不同**:
//     读同一地址两次得同一数据, 多读者/重读/进程重启都安全 (S3 的三类残余在这条路上不存在)。
//   · 新鲜度协议: 环会被写者**回绕覆盖** ⇒ 本工具在**每次环读之后**重读字计数器
//     (`MIR_DMA_CNT`, 0x148), 若 `(cnt_after - span_start) >= RING_WORDS` 则把这一段
//     记成 `clobber` 事件 (**检测, 非静默**; 定速演示下应为 0)。
//   · ⚠️ `MIR_DMA_CNT` 只在**接了 C2H 环的构建**里是"环已写字数" (未接 = 读回 `0xffffffff`)
//     ⇒ 本工具在身份步**响亮退出**。
//
// ⭐⭐⭐ P9 (2026-10-11): `--stream` = **PCIe 用户接口 MM→AXIS 之后的新路径** (与 `--dma`/`--bar`
//   **并存**, 旧两路逐字保留 ⇒ 0x21 旧位流仍可跑对照)。
//   语义变化 (权威口径 = `_proj_10g/notes/p8_axis_conf_20261011/CONF.md` §①③④ + §5-C;
//   规格背景 = `p8_axis_recon_20261011/RECON.md` §3.3/§4):
//     · **`lseek` 无意义** (ST C2H 下 `f_pos` 写进描述符后立刻被回写缓冲地址覆盖)
//       ⇒ 取数 = **平铺 `read(fd, buf, n)`** 连续流, **不做任何地址/16 B 对齐假设**;
//     · **16 B 对齐约束消失** (那是我们的 MM 从机造的; PG195 Table 11: AXI4-Stream 地址限制 = None);
//     · **PG195 硬约束: C2H 描述符长度须为 64 B 的整数倍** ⇒ 本工具的 read 长度策略**照顾**它
//       (见下 `--chunk`; 只有"最后一段不足 chunk"的那一笔可能非 64 倍数, 且逐跑打出见证);
//     · 完成条件默认 = 收满 `count` (不给 `O_TRUNC`); 单次 read 无 64 KB 硬顶 (链式)。
//   ⭐ 板内首版**不加缓冲** (用户裁定 "先不加, 测完以后加") ⇒ 宿主两次 `read()` 之间的空档
//      直接表现为**板侧丢字节** (记在快照 `W70` = `app_rx_mirror.drop_bytes`)。
//      ⇒ 本路径的记账必须把 **交付量 (板侧)** 与 **抓取量 (宿主)** 分开, 逐项打原始值。
//   ⭐⭐⭐ 记账 = **两条独立恒等式** (D1 修复, TL 审查 2026-10-11 夜; 旧式已废, 见下"⛔ 旧式"):
//        pc            = 抓取字节数 (宿主实际 read 到的字节)
//        taken_bytes    = Δ`MIR_DMA_CNT` × 4 = **从镜像取走**的字节数
//                        (已裁口径: `MIR_DMA_CNT` 数**从镜像取走 (`dma_gnt`) 的 32 位字数**;
//                         P8/期 B 的老口径 = "环已写字数" —— 两者**不是同一个量**)
//        ΔW70          = 板侧丢字节 (快照 W70 首末差; 32 位, 见"跨回卷")
//        K             = **源交付给采集通道**的字节数 (`--bytes`, 可用 `--k-bytes` 覆盖)
//        **式 A (成形器侧)**:  taken_bytes − pc == 成形器/在飞残余   ∈ [0, --resid-max-shaper]
//                               (默认 32 B; 审查给定上界)
//        **式 B (镜像/K 侧)**: K − taken_bytes − ΔW70 == 镜像残余   ∈ [0, --resid-max-mirror]
//                               (默认 24 B = `rtl/app_rx_mirror.v` 头注释 `acc_cnt_r + stg_cnt`;
//                                旧名 `--resid-max` = 本式的别名)
//        ⚠️ **只有式 B 含 K 与 ΔW70**; 两条**各自判定、各自命名打印** (`MIR_STREAM_IDA/IDB`),
//           FAIL 时指名是哪一条并打出实际值。
//        ⛔ **旧式 `pc + ΔW70 + 残余 == taken_bytes` 已废** —— 它把两个计数点混在一起
//           (`dma_gnt` 计数点**在丢字节之后**, 丢掉的字节根本不进 taken_bytes) ⇒ **有丢字节的跑必假红**
//           (审查实测 −688)。本工具不再打印该式 (回归留证 = selftest T10)。
//        ⭐ **两条式的共同前提 = `level == 0`** (FIFO 尾部已排空; 打包器残留由 FPGA 侧"停流 flush 一拍
//           短拍"清掉, FIFO 尾部由本工具的**有界等待 + 见证**清掉)。⇒ 终样本前等 `MIR_STATUS.level == 0`
//           (触发式快照读), **等到/超时都打实际值** (`MIR_STREAM_QUIESCE ... premise_level0=`);
//           超时 = 前提未见证 ⇒ 账本**不可判** ⇒ 响亮 (rc=1), 除非显式 `--no-strict-quiesce` (放行也打见证)。
//        ⭐ **"不足量"不再单独判红**: 丢字节场景下 pc < want **是预期形态** (丢掉的字节没了) ⇒
//           早停 (`ended_early`) 只打印; 解释不足量**是式 B 的活** (ΔW70 或镜像残余)。没解释 = 式 B 红。
//   ⚠️ 原"计数器跳变 > 环 4096"那条 FATAL **在 ST 下失去载体** (无环, 且"落后"表现为丢字节
//      不是回绕) ⇒ 它**只留在 `--dma` 路径** (run_dma 内), **不搬进本路径**。
//      ST 路径的替代异常判据 = ① 闭合式 (上) ② **交付-抓取差的时间序列** (能否被宿主跟上:
//      差随采样单调增 ⇒ 宿主跟不上的比例要打出来, 不静默)。见 `--sample-ms` / `MIR_STREAM_SAMPLE`。
//   ⚠️ **两条读出口不许混用** (`rtl/app_rx_mirror.v:117-122`): `--stream`(DMA/AXIS 排空) 与
//      `--bar`(`MIR_DATA` 读=弹出) 抢同一条队列 ⇒ 同一次运行里只用一条。
//
// 用法:
//   sudo ./p7b_mir_dump --bid 0x1F --bytes 1048576 [--dev /dev/xdma0_user] [--out /tmp/mir.bin]
//                       [--seconds 30] [--xor 0xA5] [--pat-off 0] [--no-verify] [--no-arm]
//                       [--src udp|tcp]        # 期 A: 源选择 (读回 MIR_STATUS[23] 作身份门)
//   sudo ./p7b_mir_dump --bid 0x1F --bytes 1048576 --dma [--dma-dev /dev/xdma0_c2h_0]
//                       [--src udp|tcp] [--out /tmp/mir.bin] [--seconds 30]
//   sudo ./p7b_mir_dump --bid 0x22 --bytes 67108864 --stream [--stream-dev /dev/xdma0_c2h_0]
//                       [--buf-mb 128] [--chunk 1048576] [--resid-max-mirror 24] [--resid-max-shaper 32]
//                       [--k-bytes N] [--sample-ms 50] [--allow-ver-mismatch] [--src udp|tcp]
//                       [--out /tmp/mir.bin]      # 旧名 --resid-max = 式 B 上界的别名
//   ./p7b_mir_dump --selftest [--bytes 65536]      # 无板自检 (内存 mock; 含负对照)
// 退出码: 0 = 全好 / 1 = 内容失配、式 A/式 B 不成立或真读错 / 2 = 用法或身份失败 (响亮)。
// 编译 (部署口径 = _proj_10g/notes/p7b_affinity/BUILD.md §2):
//   g++ -O3 -pthread -o p7b_mir_dump p7b_mir_dump.cpp
// ⚠️ mingw-w64 (本机自检编译用): 让 <unistd.h> 声明 pread/pwrite —— 只影响 Windows 侧,
//    Linux 部署口径 (g++ -O3 -pthread) 逐字不受影响。
#ifdef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif
#include "p7b_pattern.h"

#include <fcntl.h>
#include <sys/mman.h>      // ⭐ 2026-10-11: user BAR 走 mmap (现核: ctrl_fops 无 llseek)
#include <time.h>
#include <unistd.h>

#ifndef _WIN32
#include <signal.h>        // ⭐ P9: --seconds 看门狗 (SIGALRM 打断阻塞 read)
#include <sys/wait.h>      // ⭐ P9: T14 子进程退出码自检
#endif

#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

static double now_s() {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

// 寄存器地址 (与 axi_regs.v 的 localparam 对应: SNAP_NW=71 ⇒ 字号 79/80/81)
static const uint32_t A_MAGIC = 0x00, A_BID = 0x04, A_SNAP_CTRL = 0x18, A_SNAP_ST = 0x1C;
static const uint32_t A_W11 = 0x4C;            // W11 = app_udp_pattern.stat_rx_bytes (UDP 收口字节账)
static const uint32_t A_W70 = 0x138;           // W70 = app_rx_mirror.drop_bytes (71 字窗口末字)
static const uint32_t A_MIR_STATUS = 0x13C, A_MIR_DATA = 0x140, A_MIR_CTRL = 0x144;
static const uint32_t A_MIR_DMA_CNT = 0x148;    // ⭐ 期 B: 环字计数器 (未接该环的构建 ⇒ 0xffffffff)
static const uint32_t A_UNIMPL = 0x14C;         // ⭐ 期 B: 未实现地址 (MIR 四字之后第一格) ⇒ 0xffffffff
static const uint32_t MIR_SENT = 0x5A5A5A5Au;
static const uint32_t MAGIC = 0x50360001u;
// ⭐ 期 B: 环几何 —— 必须与 `rtl/mir_dma_ring.v` 的 `ROW_AW` 参数同代 (16 KB = 4096 字 × 4 行/拍)
static const uint32_t RING_WORDS = 4096u;
static const uint32_t RING_BYTES = RING_WORDS * 4u;

// ⭐⭐ P9: `MIR_STATUS.ver` 的代际 (位语义变了就 bump; 见 `axi_regs.v:56-63`)
//   ver=3 = 期 B (MM 引擎 + 环; MIR_DMA_CNT = **环已写字数**)
//   ver=4 = P9-ST (AXIS 引擎;  MIR_DMA_CNT = **已交付 AXIS 口的 32 位字数**)
//   ⇒ 两代的 0x148 语义不同 ⇒ **路径必须与 ver 配对** (见 path_ver_ok; 越轨 = 响亮拒)
static const uint32_t VER_MM = 3, VER_ST = 4;
// 残余带宽 (⭐ D1 修复后是**两条各自的**上界; 旧单条 `--resid-max` 保留为式 B 的别名)
static const uint32_t RESID_MAX_MIRROR_DEF = 24;   // 式 B: 镜像 acc_cnt_r+stg_cnt (P8-STG 口径)
static const uint32_t RESID_MAX_SHAPER_DEF = 32;   // 式 A: 成形器在飞 (TL 审查建议上界)

// ---------------------------------------------------------------------------
// 寄存器 IO 抽象: 真设备 (pread/pwrite) | 内存 mock (--selftest)
// ---------------------------------------------------------------------------
struct RegIo {
    virtual ~RegIo() {}
    virtual uint32_t rd(uint32_t a) = 0;
    virtual void wr(uint32_t a, uint32_t v) = 0;
};

struct FdIo : RegIo {
    int fd = -1;
    // ⭐⭐ 2026-10-11 板上现核 (p8_io_probe, 0x1F 位流): **user BAR 的 ctrl_fops 没有 llseek**
    //   (`xdma/cdev_ctrl.c:262` 表里无 .llseek) ⇒ lseek+read 实测 `ESPIPE (Illegal seek)`;
    //   而 **mmap 与 pread 都可用** (实测 magic/bid/0x14C 三值全中)。`reg_rw` 一直用 mmap
    //   ⇒ 本工具同款 (BAR0 = 1 MB; 32 位单笔 volatile 访问 —— 宽读会被拆成多笔 ⇒ MIR_DATA 多弹)。
    //   ⛔ 原注释"与对端现役 reg_rw 逐字同构"**与现核不符** (reg_rw 用 mmap, 不是 lseek)。
    static const uint32_t MAP_BYTES = 1u << 20;
    volatile uint32_t *map = nullptr;
    explicit FdIo(const char *path) {
        fd = open(path, O_RDWR | O_SYNC);
        if (fd < 0) { fprintf(stderr, "FATAL: open(%s): %s\n", path, strerror(errno)); exit(2); }
        void *m = mmap(nullptr, MAP_BYTES, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        if (m == MAP_FAILED) { fprintf(stderr, "FATAL: mmap(%s): %s\n", path, strerror(errno)); exit(2); }
        map = (volatile uint32_t *)m;
    }
    uint32_t rd(uint32_t a) override { return map[a >> 2]; }   // 32 位单笔
    void wr(uint32_t a, uint32_t v) override { map[a >> 2] = v; }
};

// 内存 mock: **只实现本工具用到的寄存器与语义** (够跑 --selftest 的正/负对照)。
struct MemIo : RegIo {
    uint8_t  stream[1 << 20];      // 载荷字节流 (测试预算内)
    uint32_t nbytes = 0, wpos = 0; // wpos = 已服务的字节数 (读=弹出)
    uint32_t cap = 0, tgl = 0, unf = 0, anyd = 0;
    uint32_t srcsel = 0;           // ⭐ 期 A: MIR_CTRL[2] (读回进 MIR_STATUS[23])
    uint32_t dma_cnt = 0;          // ⭐ 期 B: 环字计数器 (mock 直接给)
    uint32_t dma_auto = 0;         // ⭐ 期 B: >0 = 每被读一次就前进这么多字 (模拟并发写者)
    uint32_t bid = 0x1F;
    uint32_t ver = 4;              // ⭐ P9: MIR_STATUS[22:19] (默认 4 = ST 代; 老用例语义不变)
    uint32_t w70 = 0;              // ⭐ P9: 快照 W70 (drop_bytes) 的 mock 读回值
    uint32_t rd(uint32_t a) override {
        if (a == A_MAGIC) return MAGIC;
        if (a == A_BID) return bid;
        if (a == A_SNAP_ST) return 0x2;                     // done=1 (快照即刻完成)
        if (a == A_W70) return w70;                         // ⭐ P9
        if (a == A_MIR_STATUS) {
            uint32_t lv = (nbytes - wpos) / 4;
            if (lv > 0xFFFF) lv = 0xFFFF;
            return (srcsel << 23) | (ver << 19) | (cap << 18) | (anyd << 17) | (unf << 16) | lv;
        }
        if (a == A_MIR_DATA) {
            if (wpos + 4 <= nbytes) {
                uint32_t w = (uint32_t)stream[wpos] | ((uint32_t)stream[wpos+1] << 8) |
                             ((uint32_t)stream[wpos+2] << 16) | ((uint32_t)stream[wpos+3] << 24);
                wpos += 4;
                return w;
            }
            unf = 1;                                        // 空读: 哨兵 + sticky, 不弹
            return MIR_SENT;
        }
        if (a == A_MIR_DMA_CNT) {                           // ⭐ 期 B
            if (dma_auto) dma_cnt += dma_auto;              //   (mock 的并发写者: 读一次前进 N 字)
            return dma_cnt;
        }
        return 0;
    }
    void wr(uint32_t a, uint32_t v) override {
        if (a == A_MIR_CTRL) {
            if (v & 1u) cap = 1;                                // 照板上语义: 只管 bit0/bit1
            srcsel = (v >> 2) & 1u;                             // 期 A: bit2 电平 (写就落)
            if (v & 2u) { tgl ^= 1u; wpos = 0; }                // clr: 冲刷 (mock = 指针回 0)
        }
    }
};

// ---------------------------------------------------------------------------
// dump 主循环 (设备与 mock 共用; 这正是 selftest 的意义 —— 跑同一段代码)
// ---------------------------------------------------------------------------
struct DumpRes { uint64_t bytes = 0, words = 0; int unf_seen = 0, drop_seen = 0; double secs = 0; };

// src_sel: -1 = 不动该位 (默认, 阶段一行为); 0/1 = 写进 MIR_CTRL[2] (起测协议的每一笔都带上)
static DumpRes run_dump(RegIo &io, uint64_t want, double tmo_s, bool arm, int src_sel) {
    DumpRes r;
    std::vector<uint8_t> buf; buf.reserve((size_t)want);
    double t0 = now_s();
    uint32_t sb = (src_sel > 0) ? 4u : 0u;      // src_sel 位 (电平, 每一笔都带上)
    if (arm) {
        io.wr(A_MIR_CTRL, 0x2u | sb);       // ① clr (清 FIFO/累加器/sticky; 不改 src_sel)
        io.wr(A_MIR_CTRL, 0x1u | sb);       // ② cap_en = 1 (+ 保持 src_sel)
    }
    uint32_t s = io.rd(A_MIR_STATUS);
    r.unf_seen = (s >> 16) & 1; r.drop_seen = (s >> 17) & 1;
    int idle = 0;
    while (r.bytes < want) {
        s = io.rd(A_MIR_STATUS);
        if ((s >> 16) & 1) r.unf_seen = 1;
        if ((s >> 17) & 1) r.drop_seen = 1;
        uint32_t lv = s & 0xFFFFu;
        uint64_t need_w = (want - r.bytes) / 4;
        uint64_t c = lv < need_w ? lv : need_w;
        if (c == 0) {
            if (++idle % 2000 == 0) {
                if (now_s() - t0 > tmo_s) break;
                { struct timespec ts = {0, 50000}; nanosleep(&ts, nullptr); }
            }
            continue;
        }
        for (uint64_t i = 0; i < c; i++) {
            uint32_t w = io.rd(A_MIR_DATA);                 // 读=弹出
            buf.push_back((uint8_t)(w & 0xFF)); buf.push_back((uint8_t)((w >> 8) & 0xFF));
            buf.push_back((uint8_t)((w >> 16) & 0xFF)); buf.push_back((uint8_t)((w >> 24) & 0xFF));
        }
        r.words += c;
    }
    r.bytes = buf.size();
    r.secs = now_s() - t0;
    // 落盘由调用者做 —— 这里把 buf 塞回 io 侧的临时文件? 不: 直接在 main 里复用本函数的返回。
    // (为保持一个函数, 我们把数据写进全局临时缓冲)
    extern std::vector<uint8_t> g_last_buf;
    g_last_buf.swap(buf);
    return r;
}
std::vector<uint8_t> g_last_buf;

// ---------------------------------------------------------------------------
// ⭐⭐ 期 B: C2H DMA 环读路径 (幂等只读; 新鲜度靠字计数器 + 事后回绕检测)
// ---------------------------------------------------------------------------
// 环的物理布局 (必须与 `rtl/mir_dma_ring.v` 同代): 逻辑字 L 落在物理字 (L mod RING_WORDS);
// 卡内字节偏移 = 物理字号 * 4。卡内窗口 = [0, RING_BYTES)。
struct RingIo {
    virtual ~RingIo() {}
    // 从**物理**字号起读 nwords 个字 (调用侧保证不跨环尾) ⇒ 0 = 成功
    virtual int read_at(uint32_t phys_word, uint32_t nwords, uint8_t *dst) = 0;
};

struct FdRingIo : RingIo {
    int fd = -1;
    std::vector<uint8_t> tmp;      // 16 B 对齐取数的中转缓冲
    explicit FdRingIo(const char *path) {
        fd = open(path, O_RDONLY);
        if (fd < 0) { fprintf(stderr, "FATAL: open(%s): %s\n", path, strerror(errno)); exit(2); }
    }
    // ⭐⭐ 2026-10-11 板上现核 (p8_io_probe + p8_c2h_one, 0x1F 位流):
    //   · lseek 可用 (`sgdma_fops.llseek`, `xdma/cdev_sgdma.c:159/949`, f_pos 直接当地址);
    //   · **卡内偏移必须 16 B 对齐**: off=0/16/4096/16368 ⇒ ok; **off=4/8 ⇒ 首次 -1, 再读挂住**
    //     (dmesg `xdma_xfer_submit ... timed out` + `transfer_abort`) —— 因为从机合法性②
    //     要求 `araddr[3:0]==0`, 而引擎收到 SLVERR **不是干净报错** ⇒ 驱动 ~8 s 超时。
    //     (`check_transfer_align`: 宿主缓冲须 16 B 对齐且 `buf_lsb == pos_lsb (mod addr_align)`。)
    //   ⇒ 取法 = **起点向下对齐到 4 字 (16 B)、长度向上补齐到 4 字, 多读的字节丢弃**
    //     (环是幂等只读 ⇒ 多读无害)。调用侧保证 `phys+nwords <= RING_WORDS` ⇒
    //     `roundup4(...) <= RING_WORDS` ⇒ 永不越窗 (越窗 = 合法性① SLVERR = 同样挂)。
    //   · 每次读**固定 ~1 ms 开销** (4 B 与 16 KB 同价) ⇒ 调用侧必须按大块读 (见 run_dma)。
    int read_at(uint32_t phys_word, uint32_t nwords, uint8_t *dst) override {
        uint32_t astart = phys_word & ~3u;                    // 4 字 = 16 B
        uint32_t head   = phys_word - astart;                 // 0..3 字
        uint32_t total  = (head + nwords + 3u) & ~3u;          // 补齐到 4 字
        size_t   want   = (size_t)total * 4;
        if (tmp.size() < want) tmp.resize(want);
        if (lseek(fd, (off_t)astart * 4, SEEK_SET) < 0) return -1;
        if (read(fd, tmp.data(), want) != (ssize_t)want) return -1;
        memcpy(dst, tmp.data() + (size_t)head * 4, (size_t)nwords * 4);
        return 0;
    }
};

struct DmaRes {
    uint64_t words = 0, bytes = 0;
    uint32_t cnt0 = 0, cnt1 = 0;
    uint32_t lag_max = 0;      // 观测到的最大滞后 (字): max(cnt - cur)
    uint32_t clobber = 0;      // 环读窗口"可能被回绕覆盖"的次数 (检测, 非静默)
    int short_reads = 0;       // 短读 (驱动/链路错) —— 一律响亮
    double secs = 0;
};

// mock 环 (--selftest 用): 一片内存 = 物理环; 可注入"某个物理字坏 1 bit"当负对照
struct MemRingIo : RingIo {
    uint8_t  mem[RING_BYTES];
    uint32_t corrupt_phys = 0xFFFFFFFFu;
    int read_at(uint32_t phys_word, uint32_t nwords, uint8_t *dst) override {
        memcpy(dst, mem + (size_t)phys_word * 4, (size_t)nwords * 4);
        if (corrupt_phys != 0xFFFFFFFFu && corrupt_phys >= phys_word &&
            corrupt_phys < phys_word + nwords) {
            dst[(size_t)(corrupt_phys - phys_word) * 4 + 2] ^= 0x01;
        }
        return 0;
    }
};

// 把连续的图案流按 4 B/字填进环 (逻辑字 L → 物理字 L mod RING_WORDS) —— 与板上同布局
static void ring_fill(MemRingIo &r, uint32_t fill_words, uint8_t xorc, uint64_t pat_off) {
    P7bPat p(pat_off);
    for (uint32_t L = 0; L < fill_words; L++) {
        for (int b = 0; b < 4; b++) {
            r.mem[(size_t)((uint32_t)(L % RING_WORDS)) * 4 + b] = (uint8_t)(p.next() ^ xorc);
        }
    }
}

// 读 nwords 个逻辑字 (从 start 起; 允许跨环尾 ⇒ 分两段)
static int ring_read(RingIo &rio, uint32_t start, uint32_t nwords, uint8_t *dst, int *short_reads) {
    uint32_t done = 0;
    while (done < nwords) {
        uint32_t phys  = (uint32_t)((start + done) % RING_WORDS);
        uint32_t chunk = RING_WORDS - phys;
        if (chunk > nwords - done) chunk = nwords - done;
        if (rio.read_at(phys, chunk, dst + (size_t)done * 4) != 0) { (*short_reads)++; return -1; }
        done += chunk;
    }
    return 0;
}

// DMA 采集: 与 run_dump 同构的"want 字节"语义, 但读的是环 (幂等) + 计数器差分
static DmaRes run_dma(RegIo &io, RingIo &rio, uint64_t want, double tmo_s, bool arm, int src_sel) {
    DmaRes r;
    std::vector<uint8_t> buf; buf.reserve((size_t)want);
    uint32_t sb = (src_sel > 0) ? 4u : 0u;
    if (arm) {
        io.wr(A_MIR_CTRL, 0x2u | 0x8u | sb);   // ① clr + dma_en(bit3) [+ src_sel]
        io.wr(A_MIR_CTRL, 0x1u | 0x8u | sb);   // ② cap_en + dma_en(bit3) [+ src_sel]
    }
    double t0 = now_s();
    uint32_t c0 = io.rd(A_MIR_DMA_CNT);
    if (c0 == 0xFFFFFFFFu) { fprintf(stderr, "FATAL: MIR_DMA_CNT 读回 0xffffffff (本构建未接 C2H 环)\n"); exit(2); }
    r.cnt0 = c0;
    uint32_t cur = c0;
    int idle = 0;
    while (buf.size() < want) {
        uint32_t c1 = io.rd(A_MIR_DMA_CNT);
        uint32_t av = (uint32_t)(c1 - cur);
        // 结构守卫: 一次能拿到的量不可能超过环容量 ⇒ 超过 = clr 换代 / 计数器跳变 / 落后超一环
        // (落后超一环 = 这一段数据已被覆盖 ⇒ 读回的是垃圾; 响亮退出, 不静默读垃圾)
        // ⛔ P9: 这条**只属于 MM 环路径** (ST/--stream 下无环 ⇒ 该判据失去载体, 不搬过去)。
        if (av > RING_WORDS) {
            fprintf(stderr, "FATAL: 计数器跳变 %u 字 > 环容量 %u (clr 换代? 或已落后 > 1 环 = 该段数据已被覆盖)\n",
                    av, RING_WORDS);
            exit(2);
        }
        if (av > r.lag_max) r.lag_max = av;
        if (av == 0) {
            if (++idle % 2000 == 0) {
                if (now_s() - t0 > tmo_s) break;
                { struct timespec ts = {0, 50000}; nanosleep(&ts, nullptr); }
            }
            continue;
        }
        uint64_t need_w = (want - buf.size()) / 4;
        uint32_t n = ((uint64_t)av < need_w) ? av : (uint32_t)need_w;
        // ⭐ 2026-10-11 现核: 每次 C2H 读固定 ~1 ms 开销 (与长度无关) ⇒ 读太碎 = 带宽塌成
        //   B/s 级 (dma2 实测 61 B/s)。最小读块 = 1024 字 (4 KB) ⇒ 容量 ≈ 4 MB/s。
        //   ⚠️ 多读的字节**不进 buf** (只进 scratch): 未写字的陈旧值不许进流 (会被 verify 抓)。
        uint32_t nread = n;
        if (nread < 1024u) {
            uint32_t cap = ((uint64_t)need_w < 1024u) ? (uint32_t)need_w : 1024u;
            if (nread < cap) nread = cap;
        }
        static std::vector<uint8_t> scratch;
        if (scratch.size() < (size_t)nread * 4) scratch.resize((size_t)nread * 4);
        if (ring_read(rio, cur, nread, scratch.data(), &r.short_reads) != 0) break;
        size_t off = buf.size();
        buf.resize(off + (size_t)n * 4);
        memcpy(&buf[off], scratch.data(), (size_t)n * 4);
        // 新鲜度门: 这一段的起点是否已被写者回绕越过 (读期间/读之前都可能)
        uint32_t c2 = io.rd(A_MIR_DMA_CNT);
        if ((uint32_t)(c2 - cur) >= RING_WORDS) r.clobber++;
        cur += n;
        r.words += n;
    }
    r.bytes = buf.size();
    r.cnt1 = io.rd(A_MIR_DMA_CNT);
    r.secs = now_s() - t0;
    g_last_buf.swap(buf);
    return r;
}

// ---------------------------------------------------------------------------
// ⭐⭐⭐ P9: `--stream` = MM→AXIS 之后的平铺 C2H 流路径
// ---------------------------------------------------------------------------
// 取数合同 (与 `--dma` 的 lseek+read **完全不同**):
//   · 平铺 `read(fd, buf, n)`; **不 lseek**、**不做任何地址/16 B 对齐假设**
//     (ST C2H 下 `f_pos` 不再当地址: `libxdma.c:2948-2957` 用回写缓冲地址覆盖它);
//   · read 长度策略 (照顾 PG195 "C2H 描述符长度须为 64 B 的整数倍"):
//       - `--chunk N` (默认 1 MiB) **必须是 64 的倍数** ⇒ 所有"满块读"合规;
//       - 只有"剩余不足一块"的**最后一笔**可能是非 64 倍数 (K % 64 != 0 时), 逐跑打出见证
//         (`MIR_STREAM_READS nonmul64=`); 理由: (a) 驱动按**页**切 SG (`CONF.md` §5-C),
//         用户侧的 read 长度不直接等于描述符长度; (b) 把 K 强制成 64 的倍数会让"抓 K 字节"
//         这个语义变形 (多抓或少抓) —— 宁愿**少而可见**地偏离一次, 也不静默改语义。
//   · 完成条件 = 收满 `count` (驱动默认; 不给 `O_TRUNC`/`EOP`);
//   · 单次 read 无 64 KB 硬顶 (链式 transfer), 但仍然按 `--chunk` 分块:
//     好处 = ① 大缓冲里线性落笔 ② 每块之间能采一次寄存器 (序列) ③ 块大小可控。
struct StreamIo {
    virtual ~StreamIo() {}
    // 平铺读: 返回本次拿到的字节数 (>=0); <0 = 错 (errno 由实现打印); EINTR 由实现重试
    virtual long long rd(uint8_t *dst, size_t n) = 0;
};

// 看门狗 (只有 --seconds > 0 时武装): SIGALRM 打断阻塞 read ⇒ 不永久挂死。
#ifndef _WIN32
static volatile sig_atomic_t g_alarm_fired = 0;
static void on_alarm(int) { g_alarm_fired = 1; }
#endif
static bool wd_fired() {
#ifndef _WIN32
    return g_alarm_fired != 0;
#else
    return false;
#endif
}

// 快照读 (定义在下方; run_stream 先用 ⇒ 前置声明)
static void snap_read(RegIo &io, uint32_t &w11, uint32_t &w70);

struct FdStreamIo : StreamIo {
    int fd = -1;
    explicit FdStreamIo(const char *path) {
        fd = open(path, O_RDONLY);
        if (fd < 0) { fprintf(stderr, "FATAL: open(%s): %s\n", path, strerror(errno)); exit(2); }
    }
    long long rd(uint8_t *dst, size_t n) override {
        for (;;) {
            ssize_t r = read(fd, dst, n);
            if (r < 0 && errno == EINTR) {
#ifndef _WIN32
                if (!g_alarm_fired) continue;                   // 别的信号 ⇒ 重试
#endif
                errno = EINTR;
                return -1;
            }
            return (long long)r;
        }
    }
};

// mock 流 (--selftest 用): 一块内存 = "宿主可见"的字节流 (已含丢字节造成的洞);
// ⭐⭐⭐ D1 修复: mock **按 FPGA 的两个计数点的真实定义**生成 (旧版把"源交付量 = 可见 + 丢 + 残余"
//   硬编码进 `dma_cnt` ⇒ 那正是把 D1 藏起来的结构 —— 审查点名):
//     · 源交付量 K (= src_k)
//     · 镜像内: K = **取走** + drop(进 W70) + **镜像残余** (acc_cnt_r+stg_cnt, ≤24 B)
//     · 成形器侧: **取走** = 宿主可见 + **成形器残余** (在飞, ≤32 B)
//   ⇒ `MIR_DMA_CNT` 数**取走** (丢字节**已排除**); 可见流长度 = K − drop − 镜像残余 − 成形器残余。
struct MemStreamIo : StreamIo {
    MemIo   *reg = nullptr;
    const uint8_t *data = nullptr;  // 宿主可见流 (已挖掉丢字节的洞, 尾部已去掉两种残余)
    uint64_t len = 0, pos = 0;      // len 应与 (src_k − drop − mirror_resid − shaper_resid) 一致
    uint64_t src_k = 0;             // 源交付量 K
    uint32_t drop_total = 0;        // 镜像丢字节 (进 mock 的 W70)
    uint32_t mirror_resid = 0;      // 镜像残余 acc+stg (式 B 的右侧)
    uint32_t shaper_resid = 0;      // 成形器/在飞残余 (式 A 的右侧)
    uint64_t hole_at = 0;           // 可见流上"丢字节发生"的位置 (W70 从这一刻起记)
    uint32_t dma_bias_words = 0;    // 负对照: 把取走计数打偏这么多**字** (破坏式 A 与式 B)
    uint32_t dma_base = 0;          // 计数器起点 (做"跑中回卷"用例: base 贴近 2^32)
    size_t   max_per_read = 0;      // 0 = 一次给完; >0 = 单次最多给这么多字节 (模拟碎片读)
    uint64_t taken_total() const {  // 本跑总共会被取走的字节数
        return (src_k >= (uint64_t)drop_total + mirror_resid)
                   ? (src_k - drop_total - mirror_resid) : 0ull;
    }
    // 取走计数 (逐拍推进; 起测时刻 = 0 ⇒ 工具读到的 Δ 才是"本跑取走")
    uint32_t dma_cnt_now() const {
        uint64_t t = pos + shaper_resid;                        // 成形器比宿主读到的位置领先 shaper_resid
        if (t > taken_total()) t = taken_total();
        uint32_t w = (uint32_t)(t / 4);
        if (pos >= len) w += dma_bias_words;                    // 负对照**只打偏终值** (否则 Δ 会把它抵消)
        return (uint32_t)(dma_base + w);                        // mod 2^32 (跑中回卷)
    }
    uint32_t w70_now() const { return (pos >= hole_at) ? drop_total : 0u; }
    void arm() {                    // 起测时刻的初值 (tool 在 arm 后读 words0/w70a): 取走 = 0
        if (reg) {
            reg->w70 = w70_now();
            reg->dma_cnt = (uint32_t)(dma_base + 0);
        }
    }
    long long rd(uint8_t *dst, size_t n) override {
        uint64_t av = len - pos;
        if (!av) return 0;
        if (n > av) n = (size_t)av;
        if (max_per_read && n > max_per_read) n = max_per_read;
        memcpy(dst, data + pos, n);
        pos += n;
        if (reg) { reg->dma_cnt = dma_cnt_now(); reg->w70 = w70_now(); }
        return (long long)n;
    }
};

struct StreamSample { double t; uint64_t pc; uint32_t words; uint32_t w70; uint64_t dacc; };
struct StreamRes {
    uint64_t bytes = 0;                 // pc = 抓取字节数
    uint64_t reads = 0, partial = 0, nonmul64 = 0;
    uint32_t words0 = 0, words1 = 0;    // MIR_DMA_CNT 原始端点值
    uint32_t w70a = 0, w70b = 0;        // 快照 W70 原始端点值
    uint64_t dwords = 0, drop = 0;      // **跨回卷累计** (逐段 mod 2^32 差分再相加)
    uint64_t taken = 0;                 // = dwords * 4 (**从镜像取走**的字节数, ⛔ 不是"源交付量")
    uint64_t k = 0;                     // 式 B 用的源交付量 K (= --bytes 或 --k-bytes)
    long long resid_shaper = 0;         // 式 A 蕴含残余 = taken − pc
    bool closed_a = false;              // 式 A 是否成立 (0 <= resid_shaper <= resid_max_shaper)
    long long resid_mirror = 0;         // 式 B 蕴含残余 = K − taken − ΔW70
    bool closed_b = false;              // 式 B 是否成立 (0 <= resid_mirror <= resid_max_mirror)
    uint32_t dword_max_step = 0;        // 单次采样间隔内交付字数的最大增量 (回卷余量见证)
    uint32_t level_end = 0;
    bool quiesced = false;              // 终样本前 level==0 达成 (源已停时这才可能)
    bool premise_level0 = false;        // = quiesced: "残余上界 24 B" 的见证前提 (TL 裁定 3)
    double wait_ms = 0;                 // 静默窗实际等待时长 (见证)
    bool armed = false;
    int short_reads = 0;                // rd() 返回 0 或负 (早停/看门狗/真错) —— 分流见 ended_early
    bool ended_early = false;           // 流比 want 早结束 (丢字节场景下**是预期形态**: 由两式解释, 不单独判红)
    bool read_error = false;            // 真读错 (非早停/非看门狗) —— 响亮
    bool timed_out = false;
    double secs = 0;
    std::vector<StreamSample> series;
};

// ⭐⭐⭐ D1 修复 (TL 审查 2026-10-11 夜): **两条独立恒等式, 两条各自判定**。
//   旧式 `pc + ΔW70 + 残余 == ΔMIR_DMA_CNT×4` **把两个计数点混在一起** ——
//   `MIR_DMA_CNT` 数的是**从镜像取走 (`dma_gnt`) 的字**, 取走时**丢字节早已被排除**
//   ⇒ ΔW70 不能再出现在那条式子里 (有丢字节的跑必假红; 审查实测 −688)。
//   口径 (逐字自 TL):  K = 源交付给采集通道的字节数 (本工具 = `--bytes` / `--k-bytes`)
//      · 镜像内:  K = 取走字节 + ΔW70 + 镜像残余(acc_cnt_r+stg_cnt, 0..24 B)   ← 式 B
//      · 成形器/在飞: 取走字节 = pc + 成形器残余(≤32 B)                        ← 式 A
//   两条都是"蕴含残余 ∈ [0, 上界]"式; 哪条不成立**指名报哪条**, 并打实际值。
static bool resid_in_band(long long v, uint32_t maxv) { return v >= 0 && v <= (long long)maxv; }

// 式 A (成形器侧): resid_shaper = taken − pc
static bool idA_eval(uint64_t pc, uint64_t taken, uint32_t rmax, long long *resid_out) {
    long long v = (long long)taken - (long long)pc;
    if (resid_out) *resid_out = v;
    return resid_in_band(v, rmax);
}
// 式 B (镜像/K 侧): resid_mirror = K − taken − ΔW70   (⚠️ 只有这一条含 K 与 ΔW70)
static bool idB_eval(uint64_t k, uint64_t taken, uint64_t drop, uint32_t rmax, long long *resid_out) {
    long long v = (long long)k - (long long)taken - (long long)drop;
    if (resid_out) *resid_out = v;
    return resid_in_band(v, rmax);
}

struct StreamOpts {
    uint64_t want = 0;
    uint64_t chunk = 1u << 20;
    uint32_t resid_max_shaper = RESID_MAX_SHAPER_DEF;   // 式 A 上界 (默认 32 B: 成形器在飞)
    uint32_t resid_max_mirror = RESID_MAX_MIRROR_DEF;   // 式 B 上界 (默认 24 B: 镜像 acc+stg)
    uint64_t k_bytes = 0;                               // 式 B 的 K; 0 = 取 want (--bytes)
    double   settle_s = 1.0;
    double   sample_ms = 50.0;
    bool     arm = true;
    int      src_sel = -1;
    bool     strict_quiesce = true;     // ⭐ 前提未见证 (level!=0) ⇒ 调用侧必须判 FAIL (可用 --no-strict-quiesce 显式放行)
};

// 静默窗判定 (**前提未见证 ⇒ 必须响亮的牙**; 纯函数, 自检直接打表):
//   返回 1 = 调用侧应判 FAIL (前提未见证且未被显式放行); 0 = 不因此项判红。
static int quiesce_verdict(bool quiesced, bool strict) {
    return (!quiesced && strict) ? 1 : 0;
}

// 平铺流采集 (设备与 mock 共用同一段代码 —— 这就是 selftest 的意义)
static StreamRes run_stream(RegIo &io, StreamIo &sio, uint8_t *dst, size_t cap, const StreamOpts &o) {
    StreamRes r;
    uint32_t sb = (o.src_sel > 0) ? 4u : 0u;
    double t0 = now_s();
    if (o.arm) {
        io.wr(A_MIR_CTRL, 0x2u | 0x8u | sb);   // ① clr + dma_en(bit3) [+ src_sel]
        io.wr(A_MIR_CTRL, 0x1u | 0x8u | sb);   // ② cap_en + dma_en [+ src_sel]
    }
    r.armed = o.arm;
    // 端点基线 (arm 之后立刻取; clr 应已把交付计数/丢字节的**增量**基线定住)
    uint32_t last_words = io.rd(A_MIR_DMA_CNT);
    uint32_t w11a, last_w70;
    snap_read(io, w11a, last_w70);
    r.words0 = last_words; r.w70a = last_w70;
    double last_s = -1e9;
    // 采样: 只在**两次 read 块之间**做 (寄存器是 AXI-Lite, 与数据面不吃同一条流);
    //   ⚠️ 采样本身在流上=自造一个空档 ⇒ 采样周期别设得太密 (默认 50 ms)。
    auto sample = [&](bool force) {
        double t = now_s() - t0;
        if (!force && (t - last_s) * 1000.0 < o.sample_ms) return;
        uint32_t w11, w70;
        snap_read(io, w11, w70);
        uint32_t wd = io.rd(A_MIR_DMA_CNT);
        uint32_t step = (uint32_t)(wd - last_words);
        if (step > r.dword_max_step) r.dword_max_step = step;
        r.dwords += step;                                   // 跨回卷: 逐段 mod 2^32 差分再相加
        r.drop   += (uint32_t)(w70 - last_w70);
        last_words = wd; last_w70 = w70;
        if (r.series.size() < 20000) r.series.push_back(StreamSample{t, r.bytes, wd, w70, r.dwords});
        last_s = t;
    };
    sample(true);                                            // 起点样本 (pc=0)
    while (r.bytes < o.want) {
        uint64_t remain = o.want - r.bytes;
        size_t n = (remain < o.chunk) ? (size_t)remain : (size_t)o.chunk;
        if (!n) break;
        if (n % 64u != 0) r.nonmul64++;
        long long got = sio.rd(dst + r.bytes, n);
        if (got < 0) {
            r.short_reads++;
            if (wd_fired()) {                               // 看门狗截断 = 操作者自己限的界 ⇒ 早停形态
                r.timed_out = true; r.ended_early = true;
                printf("MIR_STREAM_END saw=read/看门狗截断 pc=%llu want=%llu (由两式解释不足量)\n",
                       (unsigned long long)r.bytes, (unsigned long long)o.want);
            } else {                                        // 真读错 —— 响亮
                r.read_error = true;
                fprintf(stderr, "FAIL: stream read 出错 (n=%zu): %s\n", n, strerror(errno));
            }
            break;
        }
        if (got == 0) {                                     // 流比 want 早结束 (丢字节场景下是**预期形态**)
            r.short_reads++; r.ended_early = true;
            printf("MIR_STREAM_END saw=read==0 pc=%llu want=%llu (由两式解释不足量)\n",
                   (unsigned long long)r.bytes, (unsigned long long)o.want);
            break;
        }
        r.reads++;
        if ((uint64_t)got < (uint64_t)n) r.partial++;
        r.bytes += (uint64_t)got;
        sample(false);
    }
    // 静默窗 (有界) + **见证**: 等 `MIR_STATUS.level == 0` —— 只有"源已停 + 全部交付被取走"时
    //   才可能成立。它是"残余上界 = 镜像 acc+stg (≤24 B)"这条的**前提** (TL 2026-10-11 裁定 3:
    //   打包器残留由 FPGA 侧停流 flush 清掉, FIFO 尾部由这一刻清掉) ⇒ **不许静默**:
    //   等到/超时都打实际 level 值, 超时由调用侧按 `quiesce_verdict` 判红 (除非显式放行)。
    //   ⭐ "触发式快照读 MIR_STATUS.level": 每轮先写 SNAP_CTRL 触发一次快照, 再读 level。
    double tb = now_s();
    for (;;) {
        io.wr(A_SNAP_CTRL, 0x1u);                       // 触发式快照 (与 W11/W70 同一机制)
        (void)io.rd(A_SNAP_ST);
        uint32_t s = io.rd(A_MIR_STATUS);
        r.level_end = s & 0xFFFFu;
        if (r.level_end == 0) { r.quiesced = true; break; }
        if (o.settle_s <= 0 || now_s() - tb > o.settle_s) break;
        { struct timespec ts = {0, 2000000}; nanosleep(&ts, nullptr); }   // 2 ms
    }
    r.wait_ms = (now_s() - tb) * 1000.0;
    r.premise_level0 = r.quiesced;
    sample(true);                                            // 终样本
    r.words1 = last_words; r.w70b = last_w70;
    // ⭐⭐⭐ D1 修复: 两条独立恒等式 (各自蕴含各自的残余)
    r.taken = r.dwords * 4u;                                // 从镜像取走的字节 (= ΔMIR_DMA_CNT×4)
    r.k = o.k_bytes ? o.k_bytes : o.want;                   // 源交付量 K 的口径 (见 --k-bytes)
    r.closed_a = idA_eval(r.bytes, r.taken, o.resid_max_shaper, &r.resid_shaper);
    r.closed_b = idB_eval(r.k, r.taken, r.drop, o.resid_max_mirror, &r.resid_mirror);
    r.secs = now_s() - t0;
    return r;
}

// 读一次快照并取两个字 (W11 = 板侧 UDP 收口字节账; W70 = 镜像拒收字节数)
static void snap_read(RegIo &io, uint32_t &w11, uint32_t &w70) {
    io.wr(A_SNAP_CTRL, 0x1u);
    for (int i = 0; i < 1000; i++) if ((io.rd(A_SNAP_ST) >> 1) & 1u) break;
    w11 = io.rd(A_W11); w70 = io.rd(A_W70);
}

static int verify(const std::vector<uint8_t> &got, uint64_t want, uint8_t xorc, uint64_t pat_off,
                  long long *first_mis) {
    P7bPat pat(pat_off);
    *first_mis = -1;
    for (uint64_t i = 0; i < got.size(); i++) {
        uint8_t e = (uint8_t)(pat.next() ^ xorc);
        if (got[i] != e) { *first_mis = (long long)i; return 1; }
    }
    if (got.size() < want) return 2;                    // 字节不足 (超时/停流)
    return 0;
}

// ⭐ P9: 指针版 verify (--stream 抓在大缓冲里, 不做一次 128 MB 拷贝)
static int verify_buf(const uint8_t *got, uint64_t n, uint64_t want, uint8_t xorc, uint64_t pat_off,
                      long long *first_mis) {
    P7bPat pat(pat_off);
    *first_mis = -1;
    for (uint64_t i = 0; i < n; i++) {
        uint8_t e = (uint8_t)(pat.next() ^ xorc);
        if (got[i] != e) { *first_mis = (long long)i; return 1; }
    }
    if (n < want) return 2;                             // 字节不足 (超时/停流)
    return 0;
}

// ---------------------------------------------------------------------------
// ⭐ P9: 参数/身份门的**纯函数** (main 与 --selftest 共跑同一段 ⇒ 自检有真牙)
// ---------------------------------------------------------------------------
enum StreamArgErr {
    SA_OK = 0, SA_BUF0, SA_CHUNK0, SA_CHUNK64, SA_WANT0, SA_WANT8, SA_WANT_BUF
};
// --stream 的参数校验 (返回 SA_OK 或首个违规项; *msg 给 stderr 用)
static int stream_args_check(uint64_t want, uint64_t buf_bytes, uint64_t chunk,
                             char *msg, size_t msgn) {
    if (buf_bytes == 0) { snprintf(msg, msgn, "--buf-mb 为 0 (PC 缓冲不能为空)"); return SA_BUF0; }
    if (chunk == 0)     { snprintf(msg, msgn, "--chunk 为 0"); return SA_CHUNK0; }
    if (chunk % 64u)    { snprintf(msg, msgn, "--chunk %llu 不是 64 的倍数 (PG195 描述符长度约束的口径)",
                                   (unsigned long long)chunk); return SA_CHUNK64; }
    if (want == 0)      { snprintf(msg, msgn, "--bytes 为 0"); return SA_WANT0; }
    if (want % 8u)      { snprintf(msg, msgn, "--bytes %llu 不是 8 的倍数 (镜像按 64 位字打包: "
                                   "K %% 8 == 0 是 P8-STG 起的合同)", (unsigned long long)want); return SA_WANT8; }
    if (want > buf_bytes) { snprintf(msg, msgn, "--bytes %llu > PC 缓冲 %llu B (--buf-mb 要够大)",
                                     (unsigned long long)want, (unsigned long long)buf_bytes); return SA_WANT_BUF; }
    return SA_OK;
}

// 路径 ↔ ver 配对门: 0 = bar (两代都真), 1 = dma (要求 MM/ver=3), 2 = stream (要求 ST/ver=4)
static bool path_ver_ok(int path, uint32_t ver) {
    if (path == 2) return ver == VER_ST;
    if (path == 1) return ver == VER_MM;
    return true;
}

// PC 侧大缓冲: **预分配一次** (页对齐 + 预触页)。理由:
//   · 页对齐 = 驱动 `get_user_pages` 按页切 SG 的天然对齐 (少一类"对齐未知");
//   · 预触页 (memset) = 把首次触碰的缺页全部挪到起测**之前** —— 否则缺页发生流中间
//     就是一次宿主空档, 而空档直接变板侧丢字节 (自造的假缺陷);
//   · 失败 (bytes==0 或分配失败) ⇒ 返回 nullptr, 调用侧**响亮退出** (不静默降级)。
static uint8_t *buf_alloc(size_t bytes, bool prefault) {
    if (bytes == 0) return nullptr;
    void *p = nullptr;
    if (posix_memalign(&p, 4096, bytes) != 0 || !p) return nullptr;
    if (prefault) memset(p, 0, bytes);
    return (uint8_t *)p;
}

int main(int argc, char **argv) {
    // ⭐ P9: stdout 行缓冲 —— 本工具的日志是"账本" (stdout 记账 + stderr 的 FAIL 交错),
    //   重定向到文件时默认块缓冲会把 FAIL 行冲到前面 (2026-10-11 实测) ⇒ 逐行刷。
    setvbuf(stdout, nullptr, _IOLBF, 0);
    const char *dev = "/dev/xdma0_user", *out = "/tmp/mir.bin", *dma_dev = "/dev/xdma0_c2h_0";
    uint64_t want = 0, pat_off = 0; double secs = 30.0;
    uint32_t bid = 0; bool have_bid = false, selftest = false, noverify = false, noarm = false;
    bool use_dma = false;
    int  src_sel = -1;                    // ⭐ 期 A: -1 = 不显式给 (默认不动该位)
    uint8_t xorc = 0xA5;
    // ⭐ P9 (--stream) 的新参数
    bool use_stream = false, allow_ver_mismatch = false, secs_given = false;
    bool strict_quiesce = true;            // ⭐ 前提未见证 (level!=0) ⇒ 判红; --no-strict-quiesce 显式放行
    bool resid_max_alias_used = false;     // ⭐ 旧 `--resid-max` 是否被用过 (打印里标明生效值)
    uint32_t buf_mb = 128;                 // PC 侧大缓冲默认 128 MB 量级 (用户裁定)
    uint64_t chunk = 1u << 20;             // 1 MiB (64 的倍数)
    // ⭐ D1 修复: 两条式各有自己的上界; 旧 `--resid-max` 保留为**式 B 的别名**
    uint32_t resid_max_mirror = RESID_MAX_MIRROR_DEF;   // 式 B (K 侧; 旧 `--resid-max` 指它)
    uint32_t resid_max_shaper = RESID_MAX_SHAPER_DEF;   // 式 A (成形器侧)
    uint64_t k_bytes = 0;                  // 式 B 的 K; 0 = 取 --bytes
    double settle_s = 1.0, sample_ms = 50.0;
    const char *stream_dev = nullptr;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        auto nxt = [&](void) -> const char * { return (i + 1 < argc) ? argv[++i] : nullptr; };
        if (a == "--dev") { const char *p = nxt(); if (p) dev = p; }
        else if (a == "--out") { const char *p = nxt(); if (p) out = p; }
        else if (a == "--bytes") { const char *p = nxt(); if (p) want = strtoull(p, nullptr, 0); }
        else if (a == "--bid") { const char *p = nxt(); if (p) { bid = (uint32_t)strtoul(p, nullptr, 0); have_bid = true; } }
        else if (a == "--seconds") { const char *p = nxt(); if (p) { secs = atof(p); secs_given = true; } }
        else if (a == "--xor") { const char *p = nxt(); if (p) xorc = (uint8_t)strtoul(p, nullptr, 0); }
        else if (a == "--pat-off") { const char *p = nxt(); if (p) pat_off = strtoull(p, nullptr, 0); }
        else if (a == "--selftest") selftest = true;
        else if (a == "--no-verify") noverify = true;
        else if (a == "--no-arm") noarm = true;
        else if (a == "--dma") use_dma = true;                                  // ⭐ 期 B
        else if (a == "--dma-dev") { const char *p = nxt(); if (p) dma_dev = p; } // ⭐ 期 B
        else if (a == "--stream") use_stream = true;                            // ⭐⭐ P9
        else if (a == "--stream-dev") { const char *p = nxt(); if (p) stream_dev = p; } // ⭐⭐ P9
        else if (a == "--buf-mb") { const char *p = nxt(); if (p) buf_mb = (uint32_t)strtoul(p, nullptr, 0); }
        else if (a == "--chunk") { const char *p = nxt(); if (p) chunk = strtoull(p, nullptr, 0); }
        else if (a == "--resid-max") { const char *p = nxt(); if (p) {   // 旧名 = 式 B 的别名
                        resid_max_mirror = (uint32_t)strtoul(p, nullptr, 0); resid_max_alias_used = true; } }
        else if (a == "--resid-max-mirror") { const char *p = nxt(); if (p) resid_max_mirror = (uint32_t)strtoul(p, nullptr, 0); }
        else if (a == "--resid-max-shaper") { const char *p = nxt(); if (p) resid_max_shaper = (uint32_t)strtoul(p, nullptr, 0); }
        else if (a == "--k-bytes") { const char *p = nxt(); if (p) k_bytes = strtoull(p, nullptr, 0); }
        else if (a == "--settle") { const char *p = nxt(); if (p) settle_s = atof(p); }
        else if (a == "--sample-ms") { const char *p = nxt(); if (p) sample_ms = atof(p); }
        else if (a == "--allow-ver-mismatch") allow_ver_mismatch = true;        // ⭐⭐ P9
        else if (a == "--no-strict-quiesce") strict_quiesce = false;            // ⭐ P9 (TL 裁定 3)
        else if (a == "--src") {                                                // ⭐ 期 A
            const char *p = nxt();
            if (!p) { fprintf(stderr, "FATAL: --src 需要 udp|tcp\n"); return 2; }
            if (!strcmp(p, "udp")) src_sel = 0;
            else if (!strcmp(p, "tcp")) src_sel = 1;
            else { fprintf(stderr, "FATAL: --src 只认 udp|tcp (给了 %s)\n", p); return 2; }
        }
        else { fprintf(stderr, "usage: %s --bid <hex> --bytes <K> [--dev D] [--out F] [--seconds T]\n"
                               "       %*s --xor <hex> [--pat-off N] [--no-verify] [--no-arm]\n"
                               "       %*s [--src udp|tcp] | --dma [--dma-dev /dev/xdma0_c2h_0]\n"
                               "       %*s | --stream [--stream-dev /dev/xdma0_c2h_0] [--buf-mb 128]\n"
                               "       %*s   [--chunk 1048576] [--resid-max-mirror 24] [--resid-max-shaper 32]\n"
                               "       %*s   [--k-bytes N] [--settle 1.0] [--sample-ms 50]\n"
                               "       %*s   [--allow-ver-mismatch] [--no-strict-quiesce]  (旧名 --resid-max = 式B 别名)\n"
                               "       %s --selftest [--bytes K]\n", argv[0], (int)strlen(argv[0]), "",
                               (int)strlen(argv[0]), "", (int)strlen(argv[0]), "",
                               (int)strlen(argv[0]), "", (int)strlen(argv[0]), "",
                               (int)strlen(argv[0]), "", argv[0]);
               return 2; }
    }
    if (use_stream && use_dma) { fprintf(stderr, "FATAL: --stream 与 --dma 互斥 (同一次跑只走一条读出口)\n"); return 2; }
    if (want == 0) want = selftest ? 65536 : 0;
    if (want == 0) { fprintf(stderr, "FATAL: --bytes 必填 (或 --selftest 用默认 65536)\n"); return 2; }
    // ⛔ 冻结前置条件: K % 4 == 0 (v2 §V1.2)
    if (want % 4 != 0) { fprintf(stderr, "FATAL: --bytes %llu 不是 4 的倍数 (K%%4==0 是 v2 §V1.2 前置条件)\n",
                                (unsigned long long)want); return 2; }
    // ⭐⭐ P9: --stream 的参数门 (在**打开设备之前** ⇒ 纯参数错误不需要板子就能响亮失败)
    if (use_stream && !selftest) {
        char msg[256] = {0};
        int rc = stream_args_check(want, (uint64_t)buf_mb << 20, chunk, msg, sizeof(msg));
        if (rc != SA_OK) { fprintf(stderr, "FATAL: --stream 参数不合规: %s\n", msg); return 2; }
    }

    // ---------------- --selftest: 内存 mock, 跑**同一段** dump/verify 代码 ----------------
    if (selftest) {
        int bad = 0;
        static MemIo m1, m2;
        m1.bid = 0x1F; m2.bid = 0x1F;
        m1.nbytes = (uint32_t)want;
        P7bPat p0(pat_off); for (uint32_t i = 0; i < m1.nbytes; i++) m1.stream[i] = (uint8_t)(p0.next() ^ xorc);
        memcpy(m2.stream, m1.stream, m1.nbytes); m2.nbytes = m1.nbytes;
        // T1 正例: 全链 (level 协议 -> pop -> 小端拼流 -> 逐字节 verify) 必须 PASS
        DumpRes r1 = run_dump(m1, want, 5.0, true, -1);
        long long fm = -1;
        int rc1 = verify(g_last_buf, want, xorc, pat_off, &fm);
        printf("MIR_SELFTEST T1 bytes=%llu words=%llu rc=%d first_mis=%lld %s\n",
               (unsigned long long)r1.bytes, (unsigned long long)r1.words, rc1, fm,
               (rc1 == 0 && r1.bytes == want) ? "OK" : "FAIL");
        if (!(rc1 == 0 && r1.bytes == want)) bad = 1;
        // T2 负对照: 打坏 mock 流里的**第 57 字节** ⇒ verify 必须红, 且首个失配恰为 57
        m2.stream[57] ^= 0x01;
        DumpRes r2 = run_dump(m2, want, 5.0, false, -1);
        fm = -1;
        int rc2 = verify(g_last_buf, want, xorc, pat_off, &fm);
        printf("MIR_SELFTEST T2 (corrupt byte 57) rc=%d first_mis=%lld bytes=%llu %s\n",
               rc2, fm, (unsigned long long)r2.bytes,
               (rc2 == 1 && fm == 57) ? "OK" : "FAIL");
        if (!(rc2 == 1 && fm == 57)) bad = 1;
        // T3 前置条件有牙: K%4!=0 必须被拒 (本测试用子进程语义无法直接验 main, 用解析复核)
        printf("MIR_SELFTEST T3 K%%4 check: want=%llu want%%4=%llu %s\n",
               (unsigned long long)want, (unsigned long long)(want % 4), (want % 4 == 0) ? "OK(本例合法)" : "FAIL");
        if (want % 4 != 0) bad = 1;
        // T4 哨兵/underflow: 排空后再读一次 ⇒ MIR_SENT + unf_sticky=1
        uint32_t s = m1.rd(A_MIR_STATUS);
        uint32_t lv = s & 0xFFFF; for (uint32_t i = 0; i < lv; i++) (void)m1.rd(A_MIR_DATA);
        uint32_t w = m1.rd(A_MIR_DATA);
        uint32_t s2 = m1.rd(A_MIR_STATUS);
        printf("MIR_SELFTEST T4 sentinel=%08x (exp %08x) unf=%u %s\n", w, MIR_SENT, (s2 >> 16) & 1u,
               (w == MIR_SENT && ((s2 >> 16) & 1u)) ? "OK" : "FAIL");
        if (!(w == MIR_SENT && ((s2 >> 16) & 1u))) bad = 1;
        // T4b 期 A: src_sel 的写-读回 (mock 语义, 与板上 MIR_CTRL[2]/MIR_STATUS[23] 同构)
        m1.wr(A_MIR_CTRL, 0x4u);                       // src_sel=1
        uint32_t s3 = m1.rd(A_MIR_STATUS);
        m1.wr(A_MIR_CTRL, 0x0u);                       // src_sel=0
        uint32_t s4 = m1.rd(A_MIR_STATUS);
        printf("MIR_SELFTEST T4b src_sel rb: set=%u clr=%u %s\n", (s3 >> 23) & 1u, (s4 >> 23) & 1u,
               (((s3 >> 23) & 1u) == 1u && ((s4 >> 23) & 1u) == 0u) ? "OK" : "FAIL");
        if (!(((s3 >> 23) & 1u) == 1u && ((s4 >> 23) & 1u) == 0u)) bad = 1;
        // ---- 期 B: 环读路径 (同一段 run_dma 代码; 含回绕/坏字/被回绕覆盖 三条腿) ----
        {
            const uint32_t N = 1024u, STEP = 64u;               // 写者每"被读一次"前进 64 字 (≈演示节奏)
            const uint32_t C0 = RING_WORDS - 512u + STEP;       // 首读返回的计数器 ⇒ 读起点贴环尾 (跨环尾)
            static MemIo m5; static MemRingIo r5;
            m5.bid = 0x1F; m5.dma_cnt = RING_WORDS - 512u; m5.dma_auto = STEP;
            ring_fill(r5, C0 + N + 64u, xorc, pat_off);
            DmaRes d5 = run_dma(m5, r5, (uint64_t)N * 4, 5.0, false, -1);
            fm = -1;
            int rc5 = verify(g_last_buf, (uint64_t)N * 4, xorc, pat_off + (uint64_t)4 * d5.cnt0, &fm);
            printf("MIR_SELFTEST T5 (ring wrap, cnt0=%u) words=%llu bytes=%llu rc=%d fm=%lld "
                   "clob=%u short=%d lag=%u %s\n",
                   d5.cnt0, (unsigned long long)d5.words, (unsigned long long)d5.bytes, rc5, fm,
                   d5.clobber, d5.short_reads, d5.lag_max,
                   (rc5 == 0 && d5.bytes == (uint64_t)N * 4 && d5.clobber == 0 && d5.short_reads == 0
                    && d5.words == N && d5.cnt0 == C0) ? "OK" : "FAIL");
            if (!(rc5 == 0 && d5.bytes == (uint64_t)N * 4 && d5.clobber == 0 && d5.short_reads == 0
                  && d5.words == N && d5.cnt0 == C0)) bad = 1;
            // T6 负对照: 环里**第一个被读到的物理字**坏 1 bit ⇒ verify 必须红 (fm==2)
            static MemIo m6; static MemRingIo r6;
            m6.bid = 0x1F; m6.dma_cnt = RING_WORDS - 512u; m6.dma_auto = STEP;
            ring_fill(r6, C0 + N + 64u, xorc, pat_off);
            r6.corrupt_phys = C0 % RING_WORDS;
            DmaRes d6 = run_dma(m6, r6, (uint64_t)N * 4, 5.0, false, -1);
            fm = -1;
            int rc6 = verify(g_last_buf, (uint64_t)N * 4, xorc, pat_off + (uint64_t)4 * d6.cnt0, &fm);
            printf("MIR_SELFTEST T6 (corrupt first ring word) rc=%d fm=%lld %s\n", rc6, fm,
                   (rc6 == 1 && fm == 2) ? "OK" : "FAIL");
            if (!(rc6 == 1 && fm == 2)) bad = 1;
            // T7 负对照: 写者在环读期间前进 > 1 环 ⇒ clobber 检测必须响
            static MemIo m7; static MemRingIo r7;
            m7.bid = 0x1F; m7.dma_auto = RING_WORDS / 2u + 64u;
            ring_fill(r7, 2048u + 128u, xorc, pat_off);          // 内容不判 (只判检测器)
            DmaRes d7 = run_dma(m7, r7, 4096, 5.0, false, -1);
            printf("MIR_SELFTEST T7 (writer wraps during read) clob=%u %s\n", d7.clobber,
                   (d7.clobber > 0) ? "OK" : "FAIL");
            if (!(d7.clobber > 0)) bad = 1;
        }
        // ================= ⭐⭐⭐ P9: --stream 路径的自检 (T8 起) =================
        // T8 ⭐ D1 修复后 = **两条独立恒等式**各自的算法例 (纯函数打表; 含带内边界与必红两类)
        {
            struct { uint64_t pc, taken; uint32_t rmax; bool want; long long wres; const char *tag; } A[] = {
                {0,     0,    32, true,   0,    "A zero"},
                {1024,  1032, 32, true,   8,    "A resid=8"},
                {1024,  1056, 32, true,  32,    "A resid==band(edge)"},
                {1024,  1057, 32, false, 33,    "A band+1(必须红)"},
                {1024,  1000, 32, false, -24,   "A negative(必须红)"},
                {0,     4096, 32, false, 4096,  "A taken-only(必须红)"},
            };
            struct { uint64_t k, taken, drop; uint32_t rmax; bool want; long long wres; const char *tag; } B[] = {
                {0,    0,    0,   24, true,   0,   "B zero"},
                {1000, 980,  16,  24, true,   4,   "B resid=4"},
                {1000, 976,  0,   24, true,  24,   "B resid==band(edge)"},
                {1000, 975,  0,   24, false, 25,   "B band+1(必须红)"},
                {1000, 1200, 0,   24, false, -200, "B taken>K(必须红)"},
                {0,    0,    696, 24, false, -696, "B K=0,drop=696(审查例形,必须红)"},
            };
            int nb = 0; std::string det;
            for (auto &c : A) {
                long long ri = -12345; bool ok = idA_eval(c.pc, c.taken, c.rmax, &ri);
                bool pass = (ok == c.want) && (ri == c.wres);
                if (!pass) { nb++; det += std::string(" [") + c.tag + ":]"; }
                printf("MIR_SELFTEST T8 式A %-26s taken-pc=%lld -> closed_a=%d resid=%lld (期望 %d/%lld) %s\n",
                       c.tag, (long long)c.taken - (long long)c.pc, (int)ok, ri, (int)c.want, c.wres,
                       pass ? "OK" : "FAIL");
            }
            for (auto &c : B) {
                long long ri = -12345; bool ok = idB_eval(c.k, c.taken, c.drop, c.rmax, &ri);
                bool pass = (ok == c.want) && (ri == c.wres);
                if (!pass) { nb++; det += std::string(" [") + c.tag + ":]"; }
                printf("MIR_SELFTEST T8 式B %-26s K-taken-drop=%lld -> closed_b=%d resid=%lld (期望 %d/%lld) %s\n",
                       c.tag, (long long)c.k - (long long)c.taken - (long long)c.drop, (int)ok, ri,
                       (int)c.want, c.wres, pass ? "OK" : "FAIL");
            }
            if (nb) { printf("MIR_SELFTEST T8 %d 条 FAIL:%s\n", nb, det.c_str()); bad = 1; }
        }
        // 造"宿主可见流": 图案在 hole_at 处**挖掉 hole_len 个字节** (板上丢字节的真实形态: 字节没了)
        auto mk_visible = [&](std::vector<uint8_t> &v, uint64_t n, uint64_t hole_at, uint32_t hole_len) {
            v.resize((size_t)n);
            P7bPat p(pat_off); uint64_t o = 0, i = 0;
            while (i < n) {
                uint8_t b = (uint8_t)(p.next() ^ xorc);
                if (hole_len && o >= hole_at && o < hole_at + hole_len) { o++; continue; }
                v[(size_t)i++] = b; o++;
            }
        };
        // T9 --stream 端到端 (mock 板: 干净档, **无丢字节**) —— 两式都要闭
        //   mock 板模型 (D1 修复后的两计数点): K = 取走 + drop + 镜像残余;  取走 = 可见 + 成形器残余
        {
            const uint64_t K = 65536; const uint32_t D = 0, MR = 4, SR = 8;
            const uint64_t TAKEN = K - D - MR, VIS = TAKEN - SR;      // 65532 / 65524
            static MemIo m8; static MemStreamIo st8; static std::vector<uint8_t> vis8;
            m8.bid = 0x22; m8.ver = VER_ST;
            mk_visible(vis8, VIS, 0, 0);
            st8.reg = &m8; st8.data = vis8.data(); st8.len = VIS;
            st8.src_k = K; st8.drop_total = D; st8.mirror_resid = MR; st8.shaper_resid = SR;
            st8.max_per_read = 8192;                    // 强制碎片读 (每次最多 8 KB)
            st8.arm();
            StreamOpts o; o.want = VIS; o.chunk = 65536; o.k_bytes = K;   // ⭐ K 显式声明 (want=VIS<K)
            o.resid_max_mirror = resid_max_mirror; o.resid_max_shaper = resid_max_shaper;
            o.settle_s = 0.0; o.sample_ms = 0.0;        // 每块都采样 (自检里不介意开销)
            std::vector<uint8_t> dst8((size_t)VIS + 64);
            StreamRes sr8 = run_stream(m8, st8, dst8.data(), dst8.size(), o);
            fm = -1;
            int rc8 = verify_buf(dst8.data(), sr8.bytes, VIS, xorc, pat_off, &fm);
            bool pass8 = (sr8.bytes == VIS) && (rc8 == 0) && (fm == -1) &&
                         (sr8.taken == TAKEN) && (sr8.drop == 0) && (sr8.w70b == 0) &&
                         (sr8.closed_a == true) && (sr8.resid_shaper == (long long)SR) &&
                         (sr8.closed_b == true) && (sr8.resid_mirror == (long long)MR) &&
                         (sr8.partial > 0) && (sr8.series.size() >= 2) && (sr8.nonmul64 >= 1) &&
                         // ↑ 可见长度 = K−drop−MR−SR = 65524 ≡ 52 (mod 64) ⇒ 尾读必然非 64 倍数 (**见证**)
                         (!sr8.ended_early) && (sr8.premise_level0 == true) && (sr8.quiesced == true);
            printf("MIR_SELFTEST T9 stream clean: pc=%llu taken=%llu drop=%llu 式A=[%lld/%u closed=%d] "
                   "式B=[%lld/%u closed=%d] rc=%d fm=%lld partial=%llu nonmul64=%llu premise=%d series=%zu %s\n",
                   (unsigned long long)sr8.bytes, (unsigned long long)sr8.taken,
                   (unsigned long long)sr8.drop, sr8.resid_shaper, resid_max_shaper, (int)sr8.closed_a,
                   sr8.resid_mirror, resid_max_mirror, (int)sr8.closed_b, rc8, fm,
                   (unsigned long long)sr8.partial, (unsigned long long)sr8.nonmul64,
                   (int)sr8.premise_level0, sr8.series.size(), pass8 ? "OK" : "FAIL");
            if (!pass8) bad = 1;
        }
        // T10 ⭐⭐ **D1 回归** (TL 审查点名): **有丢字节但两式都成立 ⇒ 必须全绿**
        //   数值取审查例形 (取走 64836 / 抓取 64828 / ΔW70 696 / 镜像残余 4):
        //     式 A: taken − pc = 8 ∈[0,32] ✓ ;  式 B: K − taken − ΔW70 = 4 ∈[0,24] ✓
        //     ⛔ 旧式 (pc + ΔW70 + 残余 == taken) 在这里 = 64828+696−64836 = **688** ⇒ 必假红 (打印留证)
        //   同时: want=K ⇒ pc<want ⇒ **ended_early 形态** (丢字节跑的真实形态) 由两式解释
        {
            const uint64_t K = 65536, G = 1000; const uint32_t D = 696, MR = 4, SR = 8;
            const uint64_t TAKEN = K - D - MR, VIS = TAKEN - SR;      // 64836 / 64828
            static MemIo m9; static MemStreamIo st9; static std::vector<uint8_t> vis9;
            m9.bid = 0x22; m9.ver = VER_ST;
            mk_visible(vis9, VIS, G, D);
            st9.reg = &m9; st9.data = vis9.data(); st9.len = VIS; st9.hole_at = G;
            st9.src_k = K; st9.drop_total = D; st9.mirror_resid = MR; st9.shaper_resid = SR;
            st9.max_per_read = 0; st9.arm();
            StreamOpts o; o.want = K; o.chunk = 65536;                 // want = 源总量 ⇒ 会早停
            o.resid_max_mirror = resid_max_mirror; o.resid_max_shaper = resid_max_shaper;
            o.settle_s = 0.0; o.sample_ms = 0.0;
            std::vector<uint8_t> dst9((size_t)VIS + 64);
            StreamRes sr9 = run_stream(m9, st9, dst9.data(), dst9.size(), o);
            fm = -1;
            int rc9 = verify_buf(dst9.data(), sr9.bytes, VIS, xorc, pat_off, &fm);
            long long old_eq = (long long)sr9.bytes + (long long)sr9.drop - (long long)sr9.taken;
            bool pass9 = (sr9.bytes == VIS) && (rc9 == 1) && (fm == (long long)G) &&
                         (sr9.taken == TAKEN) && (sr9.drop == D) && (sr9.w70b == D) &&
                         (sr9.closed_a == true) && (sr9.resid_shaper == (long long)SR) &&
                         (sr9.closed_b == true) && (sr9.resid_mirror == (long long)MR) &&
                         (sr9.ended_early == true) && (old_eq == 688);
            printf("MIR_SELFTEST T10 (D1 reg) pc=%llu taken=%llu drop=%llu 式A=%lld(closed=%d) 式B=%lld(closed=%d) "
                   "ended_early=%d fm=%lld(期望 %llu) 旧式=pc+drop-taken=%lld(应∉[0,24]) %s\n",
                   (unsigned long long)sr9.bytes, (unsigned long long)sr9.taken,
                   (unsigned long long)sr9.drop, sr9.resid_shaper, (int)sr9.closed_a,
                   sr9.resid_mirror, (int)sr9.closed_b, (int)sr9.ended_early, fm,
                   (unsigned long long)G, old_eq, pass9 ? "OK" : "FAIL");
            if (!pass9) bad = 1;
        }
        // T10b ⭐ 负对照: **取走计数被凭空打偏 64 字 (256 B)** ⇒ **两条式都必须红** (各自指名)
        {
            const uint64_t K = 65536;
            const uint32_t D = 0, MR = 4, SR = 8, BIASW = 64;
            const uint64_t TAKEN = K - D - MR, VIS = TAKEN - SR;
            static MemIo ma; static MemStreamIo sta; static std::vector<uint8_t> visa;
            ma.bid = 0x22; ma.ver = VER_ST;
            mk_visible(visa, VIS, 0, 0);
            sta.reg = &ma; sta.data = visa.data(); sta.len = VIS;
            sta.src_k = K; sta.drop_total = D; sta.mirror_resid = MR; sta.shaper_resid = SR;
            sta.dma_bias_words = BIASW; sta.arm();
            StreamOpts o; o.want = VIS; o.chunk = 65536; o.k_bytes = K;   // ⭐ K 显式声明
            o.resid_max_mirror = resid_max_mirror; o.resid_max_shaper = resid_max_shaper;
            o.settle_s = 0.0; o.sample_ms = 0.0;
            std::vector<uint8_t> dsta((size_t)VIS + 64);
            StreamRes sra = run_stream(ma, sta, dsta.data(), dsta.size(), o);
            long long exp_a = (long long)SR + (long long)BIASW * 4;      // 式 A 蕴含 = 8 + 256 = 264 (> 32)
            long long exp_b = (long long)MR - (long long)BIASW * 4;      // 式 B 蕴含 = 4 − 256 = −252 (< 0)
            bool passa = (sra.closed_a == false) && (sra.resid_shaper == exp_a) &&
                         (sra.closed_b == false) && (sra.resid_mirror == exp_b);
            printf("MIR_SELFTEST T10b stream BOTH-red (bias=+%u 字): 式A resid=%lld(期望 %lld, closed=%d) "
                   "式B resid=%lld(期望 %lld, closed=%d) %s\n",
                   BIASW, sra.resid_shaper, exp_a, (int)sra.closed_a,
                   sra.resid_mirror, exp_b, (int)sra.closed_b, passa ? "OK" : "FAIL");
            if (!passa) bad = 1;
        }
        // T10c ⭐ 跑中**回卷** (全局 #55): 取走计数起点贴近 2^32 ⇒ 跑中翻过 0 ⇒
        //   跨回卷累计必须仍给出正确的 Δ (真板 1.7 GB/s 下 ~10 s 就翻一次)
        {
            const uint64_t K = 65536; const uint32_t D = 0, MR = 4, SR = 8;
            const uint64_t TAKEN = K - D - MR, VIS = TAKEN - SR;
            static MemIo mb; static MemStreamIo stb; static std::vector<uint8_t> visb;
            mb.bid = 0x22; mb.ver = VER_ST;
            mk_visible(visb, VIS, 0, 0);
            stb.reg = &mb; stb.data = visb.data(); stb.len = VIS;
            stb.src_k = K; stb.drop_total = D; stb.mirror_resid = MR; stb.shaper_resid = SR;
            stb.dma_base = 0xFFFFF000u;                 // 距回卷 4096 字 (< 本跑的 TAKEN/4 = 16383 字)
            stb.arm();
            StreamOpts o; o.want = VIS; o.chunk = 8192; o.k_bytes = K;    // ⭐ K 显式声明
            o.resid_max_mirror = resid_max_mirror; o.resid_max_shaper = resid_max_shaper;
            o.settle_s = 0.0; o.sample_ms = 0.0;
            std::vector<uint8_t> dstb((size_t)VIS + 64);
            StreamRes srb = run_stream(mb, stb, dstb.data(), dstb.size(), o);
            bool passb = (srb.bytes == VIS) && (srb.dwords == TAKEN / 4) && (srb.taken == TAKEN) &&
                         (srb.closed_a == true) && (srb.closed_b == true) &&
                         (srb.words1 < srb.words0);   // 确实翻过 0
            printf("MIR_SELFTEST T10c stream wrap: words0=%u words1=%u(wrapped=%d) dwords=%llu taken=%llu "
                   "式A=%lld/%d 式B=%lld/%d %s\n",
                   srb.words0, srb.words1, (int)(srb.words1 < srb.words0),
                   (unsigned long long)srb.dwords, (unsigned long long)srb.taken,
                   srb.resid_shaper, (int)srb.closed_a, srb.resid_mirror, (int)srb.closed_b,
                   passb ? "OK" : "FAIL");
            if (!passb) bad = 1;
        }
        // T10d ⭐ 静默窗前提 (TL 2026-10-11 裁定 3): level != 0 ⇒ 前提未见证 ⇒
        //   ① run_stream 必须如实报 quiesced=0/premise=0 且**实际等满** settle 窗;
        //   ② `quiesce_verdict` 在 strict 下必须返回 1 (= 调用侧判红) ⇒ 这就是新前提的牙。
        {
            const uint64_t K = 16384; const uint32_t D = 0, MR = 4, SR = 8;
            const uint64_t TAKEN = K - D - MR, VIS = TAKEN - SR;
            static MemIo mc; static MemStreamIo stc; static std::vector<uint8_t> visc;
            mc.bid = 0x22; mc.ver = VER_ST;
            mc.nbytes = 4096;                          // ⇒ mock 的 level = (4096-0)/4 = 1024 ≠ 0
            mk_visible(visc, VIS, 0, 0);
            stc.reg = &mc; stc.data = visc.data(); stc.len = VIS;
            stc.src_k = K; stc.drop_total = D; stc.mirror_resid = MR; stc.shaper_resid = SR; stc.arm();
            StreamOpts o; o.want = VIS; o.chunk = 4096; o.k_bytes = K;    // ⭐ K 显式声明
            o.resid_max_mirror = resid_max_mirror; o.resid_max_shaper = resid_max_shaper;
            o.settle_s = 0.05; o.sample_ms = 0.0;      // 有界静默窗 = 50 ms
            std::vector<uint8_t> dstc((size_t)VIS + 64);
            StreamRes src = run_stream(mc, stc, dstc.data(), dstc.size(), o);
            bool passc = (src.bytes == VIS) && (!src.quiesced) && (!src.premise_level0) &&
                         (src.level_end == 1024u) && (src.wait_ms >= 40.0) &&
                         (quiesce_verdict(src.quiesced, true) == 1) &&     // strict ⇒ 判红
                         (quiesce_verdict(src.quiesced, false) == 0) &&    // 显式放行 ⇒ 不判红
                         (quiesce_verdict(true, true) == 0);               // 见证到 ⇒ 不判红
            printf("MIR_SELFTEST T10d quiesce premise: level_end=%u quiesced=%d premise=%d waited_ms=%.1f "
                   "verdict(strict)=%d verdict(lax)=%d %s\n",
                   src.level_end, (int)src.quiesced, (int)src.premise_level0, src.wait_ms,
                   quiesce_verdict(src.quiesced, true), quiesce_verdict(src.quiesced, false),
                   passc ? "OK" : "FAIL");
            if (!passc) bad = 1;
        }
        // T10e ⭐ **成形器残余越界 ⇒ 式 A 必须红、而式 B 仍绿** (两条各自独立的牙)
        {
            const uint64_t K = 65536; const uint32_t D = 0, MR = 4, SR = 40;   // SR=40 > R_A(32)
            const uint64_t TAKEN = K - D - MR, VIS = TAKEN - SR;
            static MemIo md; static MemStreamIo std_; static std::vector<uint8_t> visd;
            md.bid = 0x22; md.ver = VER_ST;
            mk_visible(visd, VIS, 0, 0);
            std_.reg = &md; std_.data = visd.data(); std_.len = VIS;
            std_.src_k = K; std_.drop_total = D; std_.mirror_resid = MR; std_.shaper_resid = SR;
            std_.arm();
            StreamOpts o; o.want = VIS; o.chunk = 65536; o.k_bytes = K;   // ⭐ K 显式声明
            o.resid_max_mirror = resid_max_mirror; o.resid_max_shaper = resid_max_shaper;
            o.settle_s = 0.0; o.sample_ms = 0.0;
            std::vector<uint8_t> dstd((size_t)VIS + 64);
            StreamRes srd = run_stream(md, std_, dstd.data(), dstd.size(), o);
            bool passd = (srd.bytes == VIS) && (srd.taken == TAKEN) &&
                         (srd.closed_a == false) && (srd.resid_shaper == (long long)SR) &&
                         (srd.closed_b == true) && (srd.resid_mirror == (long long)MR);
            printf("MIR_SELFTEST T10e shaper overflow: 式A resid=%lld(期望 %u > %u ⇒ closed=%d) "
                   "式B resid=%lld(closed=%d) %s\n",
                   srd.resid_shaper, SR, resid_max_shaper, (int)srd.closed_a,
                   srd.resid_mirror, (int)srd.closed_b, passd ? "OK" : "FAIL");
            if (!passd) bad = 1;
        }
        // T11 ver 两态 × 三路径的门矩阵 (6 格; 越轨必须被拒)
        {
            struct { int path; uint32_t ver; bool want; const char *tag; } V[] = {
                {2, VER_ST, true,  "stream+ver4"},
                {2, VER_MM, false, "stream+ver3(必须拒)"},
                {1, VER_MM, true,  "dma+ver3"},
                {1, VER_ST, false, "dma+ver4(必须拒)"},
                {0, VER_MM, true,  "bar+ver3"},
                {0, VER_ST, true,  "bar+ver4"},
            };
            int nb = 0;
            for (auto &v : V) {
                bool ok = path_ver_ok(v.path, v.ver);
                bool pass = (ok == v.want);
                if (!pass) nb++;
                printf("MIR_SELFTEST T11 ver-gate %-18s path=%d ver=%u -> %d (期望 %d) %s\n",
                       v.tag, v.path, v.ver, (int)ok, (int)v.want, pass ? "OK" : "FAIL");
            }
            if (nb) bad = 1;
        }
        // T12 --stream 参数校验 (每条违规都必须被**指名**拒掉 = 有牙)
        {
            struct { uint64_t want, buf, chunk; int want_rc; const char *tag; } A[] = {
                {8192,       (uint64_t)128 << 20, 1u << 20, SA_OK,      "defaults"},
                {8192,       0,                   1u << 20, SA_BUF0,    "buf=0"},
                {8192,       (uint64_t)128 << 20, 0,        SA_CHUNK0,  "chunk=0"},
                {8192,       (uint64_t)128 << 20, 100,      SA_CHUNK64, "chunk=100 (非 64 倍数)"},
                {0,          (uint64_t)128 << 20, 1u << 20, SA_WANT0,  "want=0"},
                {65540,      (uint64_t)128 << 20, 1u << 20, SA_WANT8,  "want%8=4"},
                {(uint64_t)256 << 20, (uint64_t)128 << 20, 1u << 20, SA_WANT_BUF, "want>buf"},
            };
            int nb = 0;
            for (auto &a : A) {
                char msg[256] = {0};
                int rc = stream_args_check(a.want, a.buf, a.chunk, msg, sizeof(msg));
                bool pass = (rc == a.want_rc) && (rc == SA_OK || msg[0] != 0);
                if (!pass) nb++;
                printf("MIR_SELFTEST T12 sargs %-24s -> rc=%d (期望 %d) %s %s\n", a.tag, rc, a.want_rc,
                       pass ? "OK" : "FAIL", (rc == SA_OK) ? "" : msg);
            }
            if (nb) bad = 1;
        }
        // T13 PC 大缓冲 (与 main 同一段 buf_alloc): 预分配 + 预触页 + 失败路径
        {
            const size_t B = (size_t)buf_mb << 20;
            uint8_t *p = buf_alloc(B, true);
            bool ok1 = (p != nullptr);
            bool ok2 = true;
            if (p) {                                       // 预触页见证: 首/中/尾都已是 0
                p[0] = 7; p[B / 2] = 7; p[B - 1] = 7;
                memset(p, 0, B);                           // (还原 —— 检验可写且无 SIGBUS)
                ok2 = (p[0] == 0 && p[B / 2] == 0 && p[B - 1] == 0);
                free(p);
            }
            uint8_t *q = buf_alloc(0, true);
            bool ok3 = (q == nullptr);                     // 失败路径必须**返回空** (调用侧响亮退出)
            printf("MIR_SELFTEST T13 bigbuf mb=%u alloc=%d writable=%d zero-fail-path=%d %s\n",
                   buf_mb, (int)ok1, (int)ok2, (int)ok3, (ok1 && ok2 && ok3) ? "OK" : "FAIL");
            if (!(ok1 && ok2 && ok3)) bad = 1;
        }
#ifndef _WIN32
        // T14 (子进程) --stream 参数门的**退出码**有牙: 违规必须在打开设备之前 RC=2 且打 FATAL
        //   只用"参数错误"的用例 (不碰板子); argv[0] 不可执行时按 SKIP 记 (不伪造通过)
        {
            const char *a0 = argv[0];
            bool usable = (a0 && *a0) && (access(a0, X_OK) == 0);
            if (!usable) {
                printf("MIR_SELFTEST T14 subprocess RC gate: SKIP (argv[0]=%s 不可执行)\n", a0 ? a0 : "(null)");
            } else {
                struct { const char *args; int want_rc; const char *needle; const char *tag; } S[] = {
                    {"--stream --chunk 100 --bid 0x22 --bytes 8192",    2, "--chunk",  "chunk non-64"},
                    {"--stream --bytes 65540 --bid 0x22",               2, "--bytes",  "want%8!=0"},
                    {"--stream --bytes 8192 --buf-mb 0 --bid 0x22",     2, "--buf-mb", "buf-mb 0"},
                    {"--stream --dma --bid 0x22 --bytes 8192",          2, "互斥",     "stream+dma"},
                };
                int nb = 0;
                for (auto &t : S) {
                    char cmd[512];
                    snprintf(cmd, sizeof(cmd), "%s %s 2>&1 </dev/null", a0, t.args);
                    FILE *fp = popen(cmd, "r");
                    int got_rc = -1; std::string outp;
                    if (fp) {
                        char line[512];
                        while (fgets(line, sizeof(line), fp)) outp += line;
                        int st = pclose(fp);
                        got_rc = (st == -1) ? -1 : (WIFEXITED(st) ? WEXITSTATUS(st) : -1);
                    }
                    bool pass = (got_rc == t.want_rc) && (outp.find(t.needle) != std::string::npos);
                    if (!pass) nb++;
                    printf("MIR_SELFTEST T14 subproc %-16s rc=%d (期望 %d) 含'%s'=%d %s\n",
                           t.tag, got_rc, t.want_rc, t.needle,
                           (int)(outp.find(t.needle) != std::string::npos), pass ? "OK" : "FAIL");
                }
                if (nb) bad = 1;
            }
        }
#endif
        printf("MIR_SELFTEST %s\n", bad ? "FAIL" : "PASS");
        return bad ? 1 : 0;
    }

    // ---------------- 真设备 ----------------
    if (!have_bid) { fprintf(stderr, "FATAL: --bid 必填 (身份门: 防'位流换代后读了个寂寞')\n"); return 2; }
    FdIo io(dev);
    uint32_t magic = io.rd(A_MAGIC), id = io.rd(A_BID);
    printf("MIR_ID magic=%08x (exp %08x) bid=%08x (exp %08x)\n", magic, MAGIC, id, bid);
    if (magic != MAGIC) { fprintf(stderr, "FATAL: MAGIC 不符 (端点没起 / 场景 A-C, 见 P7B_PCIE_RESCAN_RECOVERY.md)\n"); return 2; }
    if (id != bid) { fprintf(stderr, "FATAL: BUILD_ID %08x != --bid %08x (位流换代? 读侧几何不同代?)\n", id, bid); return 2; }

    // ---- ⭐ 期 A: --src 的写-读回门 (在起测协议之前落位; 不符 = 响亮退出) ----
    if (src_sel >= 0) {
        io.wr(A_MIR_CTRL, (uint32_t)(src_sel ? 4u : 0u));     // 只改 bit2 (cap_en=0)
        uint32_t sv = io.rd(A_MIR_STATUS);
        printf("MIR_SRC src_sel=%d readback=%u\n", src_sel, (sv >> 23) & 1u);
        if (((sv >> 23) & 1u) != (uint32_t)src_sel) {
            fprintf(stderr, "FATAL: src_sel 读回不符 (写 %d 读回 %u) —— 位流不带期 A 的 src_sel?\n",
                    src_sel, (sv >> 23) & 1u);
            return 2;
        }
    }

    uint32_t s0 = io.rd(A_MIR_STATUS);
    printf("MIR_STATUS ver=%u src_sel=%u cap=%u any_drop=%u unf=%u level=%u\n",
           (s0 >> 19) & 0xF, (s0 >> 23) & 1u, (s0 >> 18) & 1, (s0 >> 17) & 1, (s0 >> 16) & 1, s0 & 0xFFFF);
    // ---- ⭐⭐ P9: ver 身份门 (接受 {3,4}; 再按路径判配对; 越轨 = 响亮, 除非显式 override) ----
    {
        uint32_t ver = (s0 >> 19) & 0xF;
        const char *pname = use_stream ? "stream" : (use_dma ? "dma" : "bar");
        uint32_t vexp = use_stream ? VER_ST : (use_dma ? VER_MM : 0u);
        printf("MIR_VER ver=%u path=%s expect=%u unimpl=0x14C\n", ver, pname, vexp);
        if (ver != VER_MM && ver != VER_ST) {
            fprintf(stderr, "FATAL: MIR_STATUS.ver=%u 不在 {3,4} (老/未知代位流? 读侧几何不同代?)\n", ver);
            return 2;
        }
        if (!path_ver_ok(use_stream ? 2 : (use_dma ? 1 : 0), ver)) {
            if (!allow_ver_mismatch) {
                fprintf(stderr, "FATAL: 路径 %s 与位流 ver=%u 不配对 (ver3 = MM 环, ver4 = AXIS 流)"
                                " —— 走错读出口会静默读错东西; 确要跑请显式 --allow-ver-mismatch\n", pname, ver);
                return 2;
            }
            printf("MIR_VER_GATE override=1 path=%s ver=%u (显式放行)\n", pname, ver);
        }
    }
    uint32_t w11a, w70a, w11b, w70b;
    snap_read(io, w11a, w70a);

    // ---- ⭐⭐⭐ P9: --stream (平铺 C2H 流) ----
    if (use_stream) {
        // 边界身份门: 未实现地址 (0x14C) 必须回 0xffffffff (证 0x148 是真字、不是别名; 几何不扩)
        uint32_t un = io.rd(A_UNIMPL);
        printf("MIR_UNIMPL addr=%03x val=%08x (exp ffffffff)\n", A_UNIMPL, un);
        if (un != 0xFFFFFFFFu) {
            fprintf(stderr, "FATAL: 未实现地址 0x%03x 回 %08x != 0xffffffff —— 读侧几何不同代?\n", A_UNIMPL, un);
            return 2;
        }
        // PC 侧大缓冲: 预分配一次 (声明在循环外; 全程**不重分配**)
        const size_t buf_bytes = (size_t)buf_mb << 20;
        uint8_t *buf = buf_alloc(buf_bytes, true);
        if (!buf) {
            fprintf(stderr, "FATAL: 预分配 %zu B PC 缓冲失败 (--buf-mb %u) —— 不降级、不静默\n",
                    buf_bytes, buf_mb);
            return 2;
        }
        printf("MIR_STREAM_BUF bytes=%zu mb=%u prefault=1 aligned=4096\n", buf_bytes, buf_mb);
        printf("MIR_STREAM_CFG dev=%s bytes=%llu chunk=%llu resid_max_shaper=%u resid_max_mirror=%u "
               "k_bytes=%llu settle=%.2f sample_ms=%.1f arm=%d src=%d\n",
               stream_dev ? stream_dev : dma_dev, (unsigned long long)want, (unsigned long long)chunk,
               resid_max_shaper, resid_max_mirror, (unsigned long long)k_bytes, settle_s, sample_ms,
               (int)!noarm, src_sel);
        printf("MIR_STREAM_ALIGN want_mod_64=%llu chunk_mod_64=%llu (PG195: 描述符长度须 64 B 倍数)\n",
               (unsigned long long)(want % 64u), (unsigned long long)(chunk % 64u));
        // 看门狗 (只有显式 --seconds 才武装; 默认 0 = 不武装 → 阻塞 read 可能久等)
        double wd_s = secs_given ? secs : 0.0;
        printf("MIR_STREAM_WATCHDOG secs=%.1f (0=off; SIGALRM 打断阻塞 read)\n", wd_s);
#ifndef _WIN32
        if (wd_s > 0) {
            struct sigaction sa; memset(&sa, 0, sizeof(sa));
            sa.sa_handler = on_alarm;                 // 不置 SA_RESTART ⇒ 阻塞 read 被 EINTR 打断
            sigaction(SIGALRM, &sa, nullptr);
            alarm((unsigned)(wd_s + 0.999));
        }
#endif
        FdStreamIo sio(stream_dev ? stream_dev : dma_dev);
        StreamOpts so;
        so.want = want; so.chunk = chunk;
        so.resid_max_mirror = resid_max_mirror; so.resid_max_shaper = resid_max_shaper;
        so.k_bytes = k_bytes;
        so.settle_s = settle_s; so.sample_ms = sample_ms;
        so.arm = !noarm; so.src_sel = src_sel; so.strict_quiesce = strict_quiesce;
        StreamRes sr = run_stream(io, sio, buf, buf_bytes, so);
#ifndef _WIN32
        if (wd_s > 0) alarm(0);
#endif
        // ---- 原始值全打 (U1) ----
        printf("MIR_STREAM_DONE pc=%llu reads=%llu partial=%llu nonmul64=%llu short=%d ended_early=%d "
               "read_error=%d secs=%.3f rate_Bps=%.0f\n",
               (unsigned long long)sr.bytes, (unsigned long long)sr.reads,
               (unsigned long long)sr.partial, (unsigned long long)sr.nonmul64, sr.short_reads,
               (int)sr.ended_early, (int)sr.read_error, sr.secs,
               sr.secs > 0 ? (double)sr.bytes / sr.secs : 0.0);
        printf("MIR_STREAM_ACCT pc=%llu taken_bytes=%llu dW70=%llu w70a=%u w70b=%u words0=%u words1=%u "
               "dwords=%llu K=%llu\n",
               (unsigned long long)sr.bytes, (unsigned long long)sr.taken,
               (unsigned long long)sr.drop, sr.w70a, sr.w70b, sr.words0, sr.words1,
               (unsigned long long)sr.dwords, (unsigned long long)sr.k);
        printf("MIR_STREAM_QUIESCE level_end=%u quiesced=%d premise_level0=%d waited_ms=%.1f settle_s=%.2f "
               "strict=%d (前提: FIFO 尾部已排空; 打包器残留由 FPGA 侧停流 flush 清)\n",
               sr.level_end, (int)sr.quiesced, (int)sr.premise_level0, sr.wait_ms, settle_s,
               (int)strict_quiesce);
        // ⭐⭐⭐ D1 修复: **两条独立恒等式, 各自命名打印** (旧式 pc+dW70+残余==taken 已废)
        printf("MIR_STREAM_IDA 式A(成形器) taken_bytes - pc == shaper_resid -> %lld  band=[0,%u] closed_a=%d\n",
               sr.resid_shaper, resid_max_shaper, (int)sr.closed_a);
        printf("MIR_STREAM_IDB 式B(镜像/K) K - taken_bytes - dW70 == mirror_resid -> %lld  band=[0,%u] closed_b=%d "
               "(K 来源=%s; --resid-max 旧名%s)\n",
               sr.resid_mirror, resid_max_mirror, (int)sr.closed_b,
               k_bytes ? "--k-bytes" : "--bytes", resid_max_alias_used ? "已用(生效值 = 式B 上界)" : "未用");
        printf("MIR_STREAM_WRAP words0=%u words1=%u wrap_seen=%d dword_max_step=%u (回卷余量: 单步 <2^32)\n",
               sr.words0, sr.words1, (int)(sr.words1 < sr.words0), sr.dword_max_step);
        // 序列 (取走-抓取差随时间; 单调增 ⇒ 宿主跟不上)
        {
            uint64_t gap0 = 0, gapN = 0, gapmax = 0; int nondec = 1; uint64_t prevg = 0;
            for (size_t i = 0; i < sr.series.size(); i++) {
                const StreamSample &sp = sr.series[i];
                // "取走-抓取"差用**跨回卷累计**值算 (单点原始 words 会在回卷后塌, 只作展示)
                long long gs = (long long)(sp.dacc * 4u) - (long long)sp.pc;
                uint64_t g = (gs > 0) ? (uint64_t)gs : 0ull;
                if (i == 0) gap0 = g;
                if (i + 1 == sr.series.size()) gapN = g;
                if (g > gapmax) gapmax = g;
                if (i > 0 && g < prevg) nondec = 0;
                prevg = g;
                if (i < 40 || i + 2 >= sr.series.size()) {
                    printf("MIR_STREAM_SAMPLE i=%zu t=%.3f pc=%llu drop=%u words=%u dword_acc=%llu\n",
                           i, sp.t, (unsigned long long)sp.pc, sp.w70, sp.words,
                           (unsigned long long)sp.dacc);
                } else if (i == 40) {
                    printf("MIR_STREAM_SAMPLE ... (共 %zu 点, 只逐点打到第 40 点)\n", sr.series.size());
                }
            }
            {
                uint64_t miss = sr.taken > sr.bytes ? sr.taken - sr.bytes : 0;
                double pct = sr.taken ? (double)miss * 100.0 / (double)sr.taken : 0.0;
                printf("MIR_STREAM_GAP first=%llu last=%llu max=%llu nondecreasing=%d host_miss_bytes=%llu "
                       "host_miss_pct=%.4f (= (taken-pc)/taken; 宿主跟不上的比例)\n",
                       (unsigned long long)gap0, (unsigned long long)gapN, (unsigned long long)gapmax,
                       nondec, (unsigned long long)miss, pct);
            }
        }
        printf("MIR_STREAM_NOTE 采样本身在流上=自造空档 (%zu 点); 首版板内不加缓冲 ⇒ 宿主空档直接变丢字节\n",
               sr.series.size());
        // 落盘
        if (sr.bytes) {
            FILE *f = fopen(out, "wb");
            if (!f) { fprintf(stderr, "FATAL: fopen(%s): %s\n", out, strerror(errno)); return 2; }
            fwrite(buf, 1, (size_t)sr.bytes, f); fclose(f);
        }
        long long fm2 = -1; int rc = 0;
        // ⭐ D1 修复: 内容判据 = **纯内容** (对 pc 个字节逐字节); "不足量"由式 B 解释, 不再单独判红
        if (!noverify) rc = verify_buf(buf, sr.bytes, sr.bytes, xorc, pat_off, &fm2);
        if (!noverify) printf("MIR_VERIFY rc=%d first_mismatch=%lld of pc=%llu (want=%llu; 不足量看式B)\n",
                              rc, fm2, (unsigned long long)sr.bytes, (unsigned long long)want);
        int fail = 0;
        if (sr.read_error) { fprintf(stderr, "FAIL: stream 真读错 (非早停/非看门狗) —— 见上一条\n"); fail = 1; }
        if (rc == 1) { fprintf(stderr, "FAIL: content mismatch at %lld\n", fm2); fail = 1; }
        if (!sr.closed_a) {
            fprintf(stderr, "FAIL: 式 A (成形器) 不成立: taken_bytes(%llu) - pc(%llu) = %lld ∉ [0,%u] "
                            "(成形器/在飞残余越界)\n",
                    (unsigned long long)sr.taken, (unsigned long long)sr.bytes, sr.resid_shaper,
                    resid_max_shaper);
            fail = 1;
        }
        if (!sr.closed_b) {
            fprintf(stderr, "FAIL: 式 B (镜像/K 侧) 不成立: K(%llu) - taken_bytes(%llu) - dW70(%llu) = %lld "
                            "∉ [0,%u] (镜像残余越界 / K 口径不对 —— 若抓的是源流前缀请用 --k-bytes 声明源交付量)\n",
                    (unsigned long long)sr.k, (unsigned long long)sr.taken,
                    (unsigned long long)sr.drop, sr.resid_mirror, resid_max_mirror);
            fail = 1;
        }
        // ⭐ 前提断言 (TL 2026-10-11 裁定 3): level==0 是"两条残余上界"的见证前提 ⇒ 未见证
        //   一律响亮 (rc=1); 非静默场景要用, 就显式 --no-strict-quiesce (放行也打见证, 不静默)
        if (quiesce_verdict(sr.quiesced, strict_quiesce)) {
            fprintf(stderr, "FAIL: 静默窗未达 level==0 (level_end=%u, 实等 %.1f ms / settle=%.2f s): "
                            "\"残余上界\"的前提未获见证 ⇒ 本跑账本按\"不可判\"读 "
                            "(非静默场景请显式 --no-strict-quiesce)\n",
                    sr.level_end, sr.wait_ms, settle_s);
            fail = 1;
        } else if (!sr.quiesced) {
            printf("MIR_STREAM_QUIESCE_OVERRIDE strict=0 level_end=%u (显式放行: 前提未见证, 账本按\"不可判\"读)\n",
                   sr.level_end);
        }
        free(buf);
        return fail ? 1 : 0;
    }

    if (use_dma) {
        // ⭐⭐ 期 B: C2H 环读路径 —— 身份门 = MIR_DMA_CNT 可读 (未接该环的构建回 0xffffffff)
        //   ⭐ 2026-10-11 接线轮: 再加一条**边界身份门** —— 未实现地址 (0x14C) 必须回 0xffffffff
        //     (经真 XDMA 的 SLVERR⇒0xffffffff 行为; 见 sim/p6e_pcie/xdma_0_sim_stub.v 头注)。
        //     它同时证明"MIR_DMA_CNT 的那个 0x148 是真字而不是别名" (两格一起判 ⇒ 边界不平移)。
        uint32_t un = io.rd(A_UNIMPL);
        printf("MIR_UNIMPL addr=%03x val=%08x (exp ffffffff)\n", A_UNIMPL, un);
        if (un != 0xFFFFFFFFu) {
            fprintf(stderr, "FATAL: 未实现地址 0x%03x 回 %08x != 0xffffffff —— 读侧几何不同代?\n",
                    A_UNIMPL, un);
            return 2;
        }
        FdRingIo rio(dma_dev);
        DmaRes dr = run_dma(io, rio, want, secs, !noarm, src_sel);
        snap_read(io, w11b, w70b);
        std::vector<uint8_t> got = g_last_buf;
        if (!got.empty()) {
            FILE *f = fopen(out, "wb");
            if (!f) { fprintf(stderr, "FATAL: fopen(%s): %s\n", out, strerror(errno)); return 2; }
            fwrite(got.data(), 1, got.size(), f); fclose(f);
        }
        long long fm = -1; int rc = 0;
        uint64_t poff = pat_off + (uint64_t)4 * dr.cnt0;    // 环是第 cnt0 字开始被本工具读走的
        if (!noverify) rc = verify(got, want, xorc, poff, &fm);
        printf("MIR_DMA_DONE bytes=%llu words=%llu secs=%.3f rate_Bps=%.0f out=%s\n",
               (unsigned long long)dr.bytes, (unsigned long long)dr.words, dr.secs,
               dr.secs > 0 ? (double)dr.bytes / dr.secs : 0.0, out);
        printf("MIR_DMA_ACCT cnt0=%u cnt1=%u lag_max=%u clobber=%u short_reads=%d (want: clobber==0 & short==0 & cnt1-cnt0==words[mod 2^32])\n",
               dr.cnt0, dr.cnt1, dr.lag_max, dr.clobber, dr.short_reads);
        printf("MIR_DMA_NOTE ring=16KB idempotent-read; access=lseek+read on %s (pread 未现核, 见文件头)\n", dma_dev);
        if (!noverify) printf("MIR_VERIFY rc=%d first_mismatch=%lld of %llu (pat_off_eff=%llu)\n",
                              rc, fm, (unsigned long long)want, (unsigned long long)poff);
        if (dr.short_reads != 0) { fprintf(stderr, "FAIL: %d 次短读 (驱动/链路错)\n", dr.short_reads); return 1; }
        if (rc == 1) { fprintf(stderr, "FAIL: content mismatch at %lld\n", fm); return 1; }
        if (rc == 2) { fprintf(stderr, "FAIL: short (got %llu of %llu bytes)\n",
                              (unsigned long long)got.size(), (unsigned long long)want); return 1; }
        return 0;
    }
    DumpRes r = run_dump(io, want, secs, !noarm, src_sel);
    snap_read(io, w11b, w70b);

    std::vector<uint8_t> got = g_last_buf;
    if (!got.empty()) {
        FILE *f = fopen(out, "wb");
        if (!f) { fprintf(stderr, "FATAL: fopen(%s): %s\n", out, strerror(errno)); return 2; }
        fwrite(got.data(), 1, got.size(), f); fclose(f);
    }
    long long fm = -1; int rc = 0;
    if (!noverify) rc = verify(got, want, xorc, pat_off, &fm);
    printf("MIR_DONE bytes=%llu words=%llu secs=%.3f rate_Bps=%.0f out=%s drop_seen=%d unf_seen=%d\n",
           (unsigned long long)r.bytes, (unsigned long long)r.words, r.secs,
           r.secs > 0 ? (double)r.bytes / r.secs : 0.0, out, r.drop_seen, r.unf_seen);
    printf("MIR_RATE_NOTE not-a-rate-benchmark (user-BAR window; ~4-10MB/s class; no PIN_CPU witness)\n");
    printf("MIR_ACCT dW11=%u dW70=%u pc_bytes=%llu (want: (pc + dW70) == dW11  [mod 2^32])\n",
           w11b - w11a, w70b - w70a, (unsigned long long)r.bytes);
    if (!noverify) printf("MIR_VERIFY rc=%d first_mismatch=%lld of %llu\n", rc, fm, (unsigned long long)want);
    if (rc == 1) { fprintf(stderr, "FAIL: content mismatch at %lld\n", fm); return 1; }
    if (rc == 2) { fprintf(stderr, "FAIL: short (got %llu of %llu bytes)\n",
                          (unsigned long long)got.size(), (unsigned long long)want); return 1; }
    return 0;
}
