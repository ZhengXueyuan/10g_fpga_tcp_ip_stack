# P8 板级轮报告 —— M1「UDP 载荷镜像窗」首次上板（位流 0x1F）

> **边界声明**：只烧归档副本（JTAG 易失，未写 QSPI）；未改 `rtl/`·`tb/`·`sim/`·`board/`（只读）；
> 未动对端 `/tmp/p7b_biz/` 现役工具；未碰 `D:\repo\perfv`；git 只读（未提交）；口令只作命令前缀、未落盘。
> **本报告不下 PASS/FAIL 裁定**；"未观测到" 一律写成 "未观测到"，不写成 "不存在"。
> 对端上做过的状态改动**逐条可回退**，见 §12。

## 0. 一句话结论

镜像窗的两条路径（① user-BAR 读=弹出 / ② C2H DMA 环读）在板上**都通了电**：身份五判据全中、
起测协议（clr→cap_en）生效、**字节账逐位闭合**（`pc + ΔW70 == ΔW11/ΔW53`，四条独立臂各一次）。
但 **③ 逐字节 verify（`K` 字节 == `pattern^0xA5`）在本位流上结构性不可达**：
镜像采集侧有 **4 B/拍** 的持续采集上限（RTL 头注释自陈），而 app RX 口按 **8 B/拍** 连续吐字
⇒ 镜像**每隔一个 8 B 组丢一个（实测恒 50%，全部计入 W70）**。这一形态由三条独立签名互证（§9）。

---

## 1. 交付物与工具（md5 表）

### 1.1 本轮改的三个源（全部附 diff，可回退；原文件可用 `git show HEAD:<path>` 取回）

| 源 | 原 md5 | 新 md5 | 新 sha256 | diff | 改动 |
|---|---|---|---|---|---|
| `_proj_pcie/p7b_biz/p7b_mir_dump.cpp` | `2a4435e63e5fa2c33e1a654f34d776b6` | `4a8e91f7e7e5151e209b8e6acff589d7` | `50b56f1f03bbbdd49aae7133a42c79384e3cf5d61c8f082f05e6473e0d2c5a64` | `_tools/p7b_mir_dump_mmap.diff` | user BAR 取法 lseek→**mmap**；C2H 取法加 **16 B 对齐 + 最小读块** |
| `_proj_pcie/p7b_biz/p7b_udp_src.cpp` | `95fd2e8a85e205068ed8d67b8b6f60a1` | `f5ff317288b59b3e3c91988ca07446c9` | `1678ec59fdc95ab7e7887da37b51d3de759660e02e85a9fed0111682297b4a6c` | `_tools/p7b_udp_src_bytes.diff`（原件副本 `_tools/p7b_udp_src.orig.cpp`，md5 `95fd2e8a…`） | 加 `--bytes K`（`K%4==0` 硬门）+ **续发语义**（partial/EAGAIN 不重填 ⇒ 防图案流挖洞） |
| `_proj_pcie/p7b_biz/p7b_tcp_src.cpp` | `e73309a9f85a628c85ba4eef0e74a0d7` | `7a6191fc01818f64eb956da069ed0640` | `8e074665ac259e202f1f2276b81129f50e64245614f144b7b6bf6ef4ecded129` | `_tools/p7b_tcp_src_bytes.diff` | 加 `--bytes K`（同门）+ ppos 续发 + **达 K 后等发送队列排空**（`TIOCOUTQ`）再退 |

### 1.2 对端部署（**新目录 `/tmp/p8_board/`；`/tmp/p7b_biz/` 一字未动**）

```
部署件 md5 (g++ -O3 -pthread, Ubuntu g++ 13.3.0, 编译 stderr 全空):
25af63df72993195469761d167005533  p7b_mir_dump          (源码 4a8e91f7…)
e0d4da5834cb95d67afb0cc523d1f92f  p7b_udp_src           (源码 f5ff3172…)
79be2a09024206b7c678dc13a3b9051d  p7b_tcp_src           (源码 7a6191fc…)
f9e131f99c8fa29fdd98bcbc2fc15d8d  p8_udp_rx_check       (本轮自写: 本地自检收端)
7834a8de6b4b3dd7cc0442552dd97c10  p8_mocktest_fix       (本轮自写: mock 单测, 改版臂)
7350154452128111fbc89a730a02de14  p8_mocktest_orig      (同源, 原版臂 -DUSE_ORIG)
108f899b03d5e37b4f8894339e5a804b  p8_io_probe           (取数法活体探针)
4bf71286228cd14f95a59fdc4fa4ced3  p8_c2h_one            (C2H 单组合探针)
5ac1b147d8fbd18781365c9195aa588a  p8_c2h_bench          (C2H 延迟基准)
250cc936544eaddce98b0377b1b04315  p8_bar_bench          (user BAR 读延迟基准)
共享头 (与仓库逐字相同): p7b_pattern.h b2f2e962… / p7b_affinity.h b0322279… / p7b_snap.sh 5af4c619…
```

对端 `p8_io_probe` 原生编译 (gcc) 亦 0 告警。**读侧默认值**（仓库 + 部署件同代）：
`NW=71`（71 字窗口）/ `EXPECT_BID=0x0000001F` / `UNIMPL_ADDR=0x14C`。

### 1.3 `p7b_udp_src --bytes/续发` 的判别性 A/B（内核无关，mock `sendmmsg`）

同一节奏脚本 `{1,3,32,5,17,EAGAIN,2,32,32,7}`（覆盖 1 个/少发/满发/EAGAIN 四形态）：

```
MOCKTEST fix  wire_bytes=1048576 expect=1048576 first_mismatch=-1 mism=0 calls=77 partials=45 eagain=8 OK
MOCKTEST orig(cap) wire_bytes=2110848 first_mismatch=1472 mism=2101243 calls=109 partials=65 eagain=11 FAIL
```
⇒ 原版在**第一次少发**（1/32）处就在图案流里挖洞（偏移恰 1472 = 32×1472 − 1472，与推演逐位吻合）；
改版在 45 次少发 + 8 次 EAGAIN 下仍**逐字节连续**。`--bytes` 门与自检（`K%4≠0 ⇒ rc=2`）、
本地 UDP 端到端（`RXCHK bytes=1048576 rc=0 first_mismatch=-1`）、工具 `--selftest`（T1–T7 全 OK、`MIR_SELFTEST PASS`）
见 `runs/STEP_TOOLS_selftest.txt`。

---

## 2. 烧录与身份（原始读数）

- 烧前核 sha256：`e365c5ca4fd25335f6713b2a960b4de5af5b42e0bda238c20d41011ca7460133`（= 派单值；
  源 = `_proj_10g/notes/p7b_build_0x1F/wrapper_p4.bit`，15,431,261 B）；只烧副本 `burn/wrapper_p4_0x1F.bit`。
- 烧录五判据（`burn/BURN_0x1F_*.txt`）：`End of startup status: HIGH` + 非注释行 `TCPREG_PROG_DONE`
  + 位流路径匹配 + stdout 新鲜 + 无 `TCPREG-ABORT`。
- **首跑被"陈旧 stdout"抓住**（详见 §10-②）：`cmd //c` 在本机是**静默空跑**，判据（mtime+路径）当场红 ⇒ 改 `cmd /c` 后成功。
- 设备级 `remove`+`rescan` 后身份（烧后原始读数）：

```
ID_MAGIC 0x50360001   (want 0x50360001)
ID_BID   0x0000001f   (want 0x0000001F = 本构建的 BUILD_ID)
ID_MARKER 0xdeadbeef  (want 0xdeadbeef)
ID_UNIMPL 0xffffffff  (want 0xffffffff: 未实现地址必须走 SLVERR)     [地址 = 0x14C]
ID_OK
MAGIC_0x00=0x50360001  BID_0x04=0x0000001f  W70_0x138=0x00000000  UNIMPL_0x14C=0xffffffff
MIR_STATUS_0x13C=0x00180000   ->  ver=3 / cap=0 / any_drop=0 / unf=0 / level=0 / src_sel=0
MIR_CTRL_0x144=0x00000000     MIR_DMA_CNT_0x148=0x00000000   SCRATCH_0x08=0   CARRIER=1
Region 0: Memory at df200000 [size=1M]   Region 1: Memory at df300000 [size=64K]
LnkSta: Speed 5GT/s (downgraded), Width x4
```

**身份五判据逐条成立**：`0x04 = 0x1f` · 71 字几何（`0x14C` 由 `0x20+4×71+16` 推出 = 未实现地址，回 `0xffffffff`；
`0x138`=W70 回 `0x00000000` 且 ≠ `0xffffffff` ⇒ 是真字非别名）· `LnkSta x4` · `2 BARs` · `ID_MARKER`。
`MIR_STATUS.ver=3` 与期 B 的 "ver 2→3" 判断项在板上独立验证。

---

## 3. 零构建项：我们的位流下 `/dev/xdma*` 是否存在（设计件 §4-①）

**答案：存在。**（step0 时板上是 0x1E，烧 0x1F 后又核一次）

```
crw------- /dev/xdma0_c2h_0   235,36   (0x1F 下 12:26 重建)
crw------- /dev/xdma0_h2c_0   235,32
crw------- /dev/xdma0_user    235,0
crw------- /dev/xdma0_control 235,1
节点总数 = 21 (/dev/xdma0*)；dmesg:
  xdma:identify_bars: 2 BARs: config 1, user 0, bypass -1.
  xdma:probe_one: 0000:02:00.0 xdma0, ..., usr 16, ch 1,1.
```

⇒ **1×C2H + 1×H2C 引擎在我们的位流下被驱动正常枚举**（`ch 1,1`），C2H 入口（候选 A）的"存在性"前提成立。
未做：**没有跑任何 H2C 写**（本轮工具不需要；`aximm_h2c_discard` 的板上行为 = 未观测）。

---

## 4. 取数法现核（三条工具改动的由来；三条都是"板上才知道"）

| # | 现象（原始） | 根因（现核） | 落地 |
|---|---|---|---|
| ① | `MIR_ID` 之前先挂：`FATAL: read @0x000: Illegal seek` | `/dev/xdma0_user` 走 `ctrl_fops`（`xdma/cdev_ctrl.c:262` 表里**无 `.llseek`**）⇒ lseek 报 **ESPIPE**；`reg_rw` 一直用的是 **mmap** | `FdIo` 改 **mmap**（BAR0 1 MB，32 位单笔 volatile） |
| ② | C2H 读 offset=4/8：首次 `-1`，**再读挂住**；dmesg `xdma_xfer_submit: xfer ...,4, s 0x1 timed out` + `transfer_abort` | 从机合法性② 要求 `araddr[3:0]==0`（16 B 对齐），而**引擎收到 SLVERR 不是干净报错而是 ~8 s 驱动超时**（`check_transfer_align`：`buf_lsb == pos_lsb (mod addr_align)`） | `FdRingIo::read_at` = **起点下对齐到 4 字、长度补齐 4 字、多读字节丢弃**（环幂等只读 ⇒ 多读无害；调用侧保证不越窗） |
| ③ | 修②前：30 s 只搬 128 KB（`rate_Bps≈4.4 KB/s` / `61 B/s`） | C2H **每次读固定 ~0.1–1 ms 开销**（4 B 与 16 KB 同价；基准见下），读太小 ⇒ 带宽塌 | `run_dma` 加 **最小读块 1024 字（4 KB）**，多读部分只进 scratch 不进流 |

活体探针读数（`p8_io_probe` / `p8_c2h_one` / `p8_bar_bench`，0x1F）：

```
USER_MMAP ok magic=50360001 bid=0000001f w70_138=00000000 unimpl_14c=ffffffff
USER_PREAD n=4 v=50360001 errno=0(Success)      USER_LSEEK ret=-1 errno=29(Illegal seek)   <- 负对照
C2H_LSEEK ret=0    C2H_READ32 n=32   C2H_PREAD@4096 n=32                        <- 均成功、不挂
C2H 组合图谱: off=0/16/4096/16368 成功；off=4/8 失败(首次 -1, 第二次挂死, timeout 杀)
C2H 单读延迟: min=102.7us max=984.1us (4 B 与 16 KB 同价；空载)
user BAR 读延迟: mmap 1.16us/次 · pread 1.63us/次 (2000 次平均)   => 寄存器读不是瓶颈
```

⇒ 设计件 §V1.5-② 的"半可定项"就此**关闭并定稿**（结论：寄存器走 mmap；C2H 走 lseek+read **但必须 16 B 对齐**）。

---

## 5. ① C2H DMA 路径（`--dma --src udp`）

**配置**：`K=1 MiB`（`K%4==0`），`--src udp`，发端 `p7b_udp_src --bytes 1048576 --mbps 20 --batch 1 --paylen 1472`
（定速必备；`--batch 1` 也是必须 —— 见下）。臂序：`dma1`（batch 32，被守卫拦）→ `dma2`（batch 1，读法未修）
→ **`dma3`（定稿，下面全是它）**。

```
MIR_ID magic=50360001 (exp 50360001) bid=0000001f (exp 0000001f)
MIR_SRC src_sel=0 readback=0
MIR_STATUS ver=3 src_sel=0 cap=0 any_drop=1 unf=0 level=0
MIR_UNIMPL addr=14c val=ffffffff (exp ffffffff)
MIR_DMA_DONE bytes=524288 words=131072 secs=60.002 rate_Bps=8738 out=/tmp/p8_board/mir_dma3.bin
MIR_DMA_ACCT cnt0=0 cnt1=131072 lag_max=736 clobber=0 short_reads=0
             (want: clobber==0 & short==0 & cnt1-cnt0==words[mod 2^32])
MIR_VERIFY rc=1 first_mismatch=8 of 1048576 (pat_off_eff=0)
快照: W11 0x300000 -> 0x400000 (Δ=1 MiB = K) ; W70 0x100000 -> 0x180000 (Δ=512 KiB = K/2)
发端: UDP_SUM pkts=713 pay_bytes=1048576 dur_s=0.475 call_errors=0 poll_tmo=0
```

判据逐条（派单）：`MIR_UNIMPL` = 逐字成立；`clobber==0` 成立；`short==0` 成立；
`cnt1-cnt0 == words`（131072 == 131072）成立；**`MIR_VERIFY rc=0 first_mismatch=-1` 未达成**
（实测 `rc=1 first_mismatch=8`，结构性，见 §9）。附带读数：`lag_max=736` 字（< 环容量 4096）；
字节账 `pc 524288 + ΔW70 524288 = ΔW11 1048576` **逐位闭合**。

- `dma1`（batch=32）被**守卫拦下**：`FATAL: 计数器跳变 5800 字 > 环容量 4096` —— 一批 32×1472 B = 47 KB 的突发
  （≈11,750 字）远大于 16 KB 环 ⇒ 必然回绕。**这是守卫正确工作**（响亮，不静默读垃圾）。
- `dma2`（batch=1，读法未修）：`short_reads=1`、`bytes=736 words=85`；dmesg 抓到
  `xdma_xfer_submit … timed out` + `transfer_abort` ⇒ 这就是 §4-② 的现场。

---

## 6. ② user-BAR 窗口路径（去掉 `--dma`；阶段一机制的首次上板）

```
MIR_SRC src_sel=0 readback=0      MIR_STATUS ver=3 cap=0 any_drop=1 unf=0 level=0
MIR_DONE bytes=131072 words=32768 secs=30.000 rate_Bps=4369 drop_seen=1 unf_seen=0
MIR_ACCT dW11=262144 dW70=131072 pc_bytes=131072   (want: (pc + dW70) == dW11 [mod 2^32])
MIR_VERIFY rc=1 first_mismatch=8 of 262144
快照: W11 0x420000 -> 0x460000 (Δ=256 KiB = K) ; W70 0x190000 -> 0x1B0000 (Δ=128 KiB = K/2)
发端(K=262144, 20 Mbps): UDP_SUM pkts=179 pay_bytes=262144 dur_s=0.119 call_errors=0 poll_tmo=0
```

判据：字节账 `(pc + dW70) == dW11` ⇒ `131072 + 131072 = 262144` **逐位闭合**；
`unf_seen=0` 且 STATUS `unf=0`（"先读 level 再读恰好 level 个"协议有效）；
**逐字节 verify 未达成**（`rc=1 first_mismatch=8`，同因）。

**归因臂（同位素：位流不动、只把发端图案起点对齐板上 LFSR）**：

```
发端 UDP_SUM off_start=4849664 (= 起测前 W11 现值 0x4A0000，由 bash 十六进制算术代入)
快照: W11 0x4A0000 -> 0x4E0000 (Δ=K=262144) ;  W70 0x1D0000 -> 0x1F0000 (Δ=K/2)
      W13 0x0039C5CB -> 0x0039C5CB   =>  ΔW13 == 0
```

⇒ **板上 app 自己的 RX 校验器在这 256 KiB 上零失配** ⇒ "SFP+ → MAC → classify → split → app RX" 全链**内容逐字节正确**；
镜像仍只吐出 K/2、且 `pc + ΔW70 = ΔW11` 闭合 ⇒ **丢字 100% 在镜像采集侧，不在链路/栈**。

---

## 7. ③ TCP 臂（`--src tcp`，用户裁"TCP 同等重要"）

四跑（`tcp1/2/3` 有工具侧/发端侧缺陷，`tcp4` 定稿）：

```
MIR_SRC src_sel=1 readback=1                    <- 期 A 的 src_sel 门在板上成立
MIR_STATUS ver=3 src_sel=1 cap=0 any_drop=1 unf=0 level=0
MIR_DONE bytes=21212 words=5303 secs=60.002 rate_Bps=354 drop_seen=1 unf_seen=0
MIR_ACCT dW11=0 dW70=240932 pc_bytes=21212      <- dW11 = UDP 计数器 (本臂不适用, 见下)
MIR_VERIFY rc=1 first_mismatch=8 of 262144
发端: SRC_DRAINED tx_bytes=262144 ; SRC_SUM tx_bytes=262144 dur_s=0.250 tx_Mbps=8.380
快照: W53(app_rx_bytes) 0x2F0D0 -> 0x6F0D0 (Δ=262144=K) ; W54(app_mismatch) 0x0 -> 0x0 (Δ=0)
      W70 0x21B2DC -> 0x256000 (Δ=240932)
```

判据：`src_sel` 门成立（readback=1）；分层字节账（TCP 用 W53）`pc 21212 + ΔW70 240932 = ΔW53 262144` **闭合**；
内容 oracle（板上 TCP 校验器 W54，**每连接从偏移 0 起**）`ΔW54 == 0`（256 KiB）⇒ TCP 链内容正确；
**逐字节 verify 未达成**（`rc=1 first_mismatch=8`）。

**本臂丢失率 91.9%，不是 UDP 那种 50%**：TCP 的到达是"窗口级突发"⇒ 除结构 4 B/拍上限外还叠加
**FIFO(256 字) 满拒写**。抓取样内容分析：前 ~400 个 8 B 组仍严格落在图案偶数组（`pat_off=16i`），
之后 1326/2651 组可定位、其余落在"陈旧/撕裂"区（环回绕 + 越读）⇒ **本臂不是干净的内容演示**（UDP 臂才是）。
另两处**发端侧**坑（已修，见 §10-④⑤）：不做排空等待 ⇒ 对端 RST 丢未上线数据；`mq`+`fq_codel` 根 qdisc
**不认** `SO_MAX_PACING_RATE` ⇒ 必须先临时装 `fq` 根 qdisc（用完已删，§12）。

---

## 8. 负对照 / 独立见证（全部原始读数）

**(a) 静态寄存器协议探针**（`_tools/static_protocol_probe.sh`，cap_en=1 态）：

```
(e) 逐字读快照 0x20..0x138 全 71 字 => 其中 0xffffffff = 0 个; MIR_STATUS.level 0 -> 0   [快照不偷数据]
(d) 读未实现地址 0x14C = 0xffffffff ;                            level 0 -> 0           [地址负对照]
(b) level==0 时读一次 MIR_DATA => 0x5a5a5a5a(哨兵) ; unf 0 -> 1 ; level 0 -> 0           [空读=哨兵+sticky, 不弹]
MIR_CTRL(0x144) = 0x00000003 (bit0 cap_en=1 / bit1 clr toggle=1)
```

**(b) 内容全检（离线，与板上工具独立的一条路径）**：把抓到的字节流按 8 B 组切开，逐组在图案流里定位：

```
mir_dma3.bin (DMA 臂, 512 KiB): 65536/65536 组 == pattern^0xA5 的 2*file_off 处   (零损坏)
mir_bar1.bin (BAR 臂, 128 KiB): 16384/16384 组 == 同上                           (零损坏)
负对照: 不做 ^0xA5 直接比对 => 首组即不同 (False) => 变换确实在板内做 (设计件 S8(c))
```
⇒ 镜像吐出的每一个字节都是**正确的图案字节**，唯一的偏差是"每隔一个 8 B 组被丢弃"（且全部计数）。

**(c) 载荷长度矩阵**（`_tools/run_paylen_matrix.sh`，K=64 KiB、20 Mbps、`--batch 1`；MAC 计数 W0/W1 与 app 计数 W10/W11 差分）：

| paylen | ΔW0 (MAC 收帧) | ΔW10 (app 收帧) | ΔW11 (app 收字节) | ΔW70 (镜像丢字节) |
|---|---|---|---|---|
| 8 | 8194 | **0** | **0** | 0 |
| 9 | 7284 | **0** | **0** | 0 |
| 16 | 4097 | **0** | **0** | 0 |
| 64 | 1025 | 1024 | 65536 | 32768（= K/2） |
| 1472 | 46 | 45 | 65536 | 32768（= K/2） |

⇒ ① MAC 层全收到；② **payload ≤16 B 的帧到不了 app**（阈值在 16–64 之间，**未定位**；见 §11-3a）；
③ 只要到得了 app，镜像恒丢一半（与 paylen 无关 ⇒ 是**每拍**级现象，不是"每帧"级）。

**(d) 板上 oracle 与镜像的分离（§6 归因臂）**：`ΔW13 == 0`（app 校验器零失配）而 `ΔW70 = K/2`。

**(e) `--selftest`**：`MIR_SELFTEST PASS`（T1–T7；含环回绕 T5 / 坏字 T6 / 被回绕覆盖检测 T7）。

---

## 9. 主发现：镜像窗的 4 B/拍结构上限 ⇒ 逐字节 verify 结构性不可达

**形态（三条独立签名互证）**：

1. **计数**：四条臂（DMA/BAR × UDP，+ 长度矩阵）**丢字恒 = 采集量的一半**（1 MiB→512 KiB，256 KiB→128 KiB，
   64 KiB→32768 B），且全部计入 `W70`（`drop_seen=1`/`any_drop=1`）。
2. **内容**：抓取样逐 8 B 组定位 = **偶数组全收、奇数组全丢**（`pat_off = 2 × file_off`；dma3 65,536/65,536、
   bar1 16,384/16,384）⇒ 洞的位置是**确定性**的，不是随机噪声。
3. **首失配恒为 8**：`first_mismatch=8`（第 0..7 字节对、第 8 字节起错）——正是"第 1 个 8 B 组被丢"的签名。

**与 RTL 的对照（读码，未改）**：`rtl/app_rx_mirror.v` 头注释**自陈**：
"① 暂存忙 —— 源一拍最多 8B, 而 FIFO 写口 = 32 位 ⇒ **持续采集上限 = 4B/拍**（156.25MHz ⇒ 625MB/s）；
源平均速率 > 4B/拍时, 多出的拍被拒收"。逐拍推演：pending 只有一级 8 B 寄存器 + 累加器 4 B/拍
⇒ 源连续 8 B/拍时稳态序列 = 收、丢、收、丢…（**恰好 50%**），与本轮板级读数逐位吻合。
而 app RX 口（`app_udp_rx_*`/`app_rx_*`）在数据报/段内部就是 **8 B/拍连续**吐字（由计数+内容+读码三方推断；
直接波形见证（ILA）**未取**）。

**为什么"定速"救不了它**：定速只拉开**数据报之间**的间隔；**数据报内部**的吐字节奏仍是 8 B/拍。
设计件 §3.5 的"必须定速 ⇒ 判据要求 `drop_bytes == 0`"这个前提在板上**不成立**：
`drop_bytes` 在**定速**下也恒 > 0（结构性的那一半）。

**⇒ 直接后果**：派单 ①/② 的第三条判据（`MIR_VERIFY rc=0 first_mismatch=-1` = "逐字节 == pattern^0xA5"）
在本位流上**不可达**（任何 ≥2 拍的载荷都如此）。可达的是：身份 / 计数账 / 内容"按确定性洞位"核对
（本轮已做：§8(b)）。**这不是"未观测到差别"，是"测到了一个确定的、可复现的差别"**。

**回退面**：`MIR_CTRL[0]=cap_en=0`（复位默认，本轮收尾已写 0）⇒ 采集整段冻结、其余读口照常
⇒ **M1 位流"带电即回退态"**（设计件 §V1.6-(i) 在板上成立）。

---

## 10. 其它发现与坑（逐条，附原始读数）

① **发端 partial send 会挖洞**（UDP 与 TCP 同病）：见 §1.3 的 mock A/B。**已修**（续发语义）。
   板级上未观测到该路径被激励（`poll_tmo=0`、`call_errors=0`：定速下 socket 队列不积压）。

② **`cmd //c` 在 `MSYS_NO_PATHCONV=1` 下是静默空跑**（本机探针：`//c` 只打 banner、rc=0、**不执行**；
   `/c` 正常）。首跑烧录因此读到**上一 session 的陈旧 stdout**，被 mtime + 位流路径两条判据当场抓住
   ⇒ 改 `cmd /c` 后一次成功。

③ **`pkill -f <自己命令行里也有的串>` 会自杀**（两次：`pkill -f p8_udp_rx_check` 把跑它的 shell 也杀了）
   ⇒ 收尾清进程一律 `pkill -x <exe 名>`。

④ **TCP 发端"发完即退"会丢数据**：`send()` 只把数据放进发送队列；进程秒退首尾撞上对端下行泛洪
   ⇒ 内核回 RST ⇒ 板侧连接被拆、已排队未上线的 218 KB 整段作废（实测两跑只送达 ~44–88 KB ≈ 1–2 个窗口）。
   修法 = 达 K 后**等 `TIOCOUTQ == 0`** 再退（修后 `ΔW53 = K` 精确）。

⑤ **`SO_MAX_PACING_RATE` 在 `mq`+`fq_codel` 根 qdisc 下被忽略**（TCP 臂）：实测未定速（262 KB 在 28 ms 内
   尽数入队）。临时装 `fq` 根 qdisc 后定速生效（`dur_s=0.250` for 262144 B ⇒ 8.38 Mbps ≈ 1 MB/s）；用完已删（§12）。

⑥ **`p7b_snap.sh snap` 的字列表要"数字"**（`11 70`），给 `W11` 会静默读成 word 0（打出 MAGIC 值）——
   本轮踩过一次，读数已作废重取（不影响结论）。

⑦ **小载荷（≤16 B）到不了 app**：MAC 收下、app 侧零帧零字节（矩阵表）。机理未定位（见 §11-3a）。
   副作用：本想用"单拍载荷"绕开 4 B/拍上限的计划**不成立**。

⑧ `MIR_CTRL` 写 0 后读回 `0x2`（bit1 = clr toggle 的**电平**反映"已清过一次"；bit0 cap_en=0 才是语义位）
   —— 登记口径，供读侧别把它误读成"还有东西在跑"。

---

## 11. 未观测到 / 做不了 / 未收口（逐条）

1. **逐字节 verify（`K` 字节 == `pattern^0xA5`）**：未达成，且**结构性**（§9）。
   不许写成"未观测到差别"——差别被**测到了**：确定性隔组丢 50%。
2. **"定速 ⇒ `drop_bytes==0`"**：前提不成立（§9）。设计件 S8(a) 同位素臂（去掉定速）因此**未被单独跑**
   —— 结构性丢字已在定速下出现，该臂的判别力被吞掉（登记：**不是**"不需要它"）。
3. **未定位**：
   a. 小载荷阈值（16→0 帧、64→1024 帧；区间内未细扫）；
   b. TCP 臂 91.9% 丢失的逐机制分解（结构 50% + FIFO 满各占多少）；
   c. `lag_max=736` 字的那一段（DMA 臂）为何攒到 736 而非更小。
4. **未做的负对照**：S8(c) 变换负对照**用离线路径做了**（不 XOR ⇒ 首组即不同）；(a) 见第 2 条；
   (f) clear 负对照（不写 clr 连跑两轮）未做。
5. **板上从未激励**：H2C 写通道（`aximm_h2c_discard`）；`MIR_DMA_CNT` 的 clr 换代语义（`dma1` 只碰到守卫）；
   环回绕 clobber 检测（`clobber=0` 全程 —— **不是"检测器有问题"，是本轮读侧一直跟得上**）。
6. **未取波形见证**：app RX 口的每拍 tvalid/tready（ILA）——8 B/拍 是"计数+内容+读码"三方推断，
   没有直接的时间轴见证。
7. **TCP 臂不是干净的内容演示**（§7），只有 UDP 臂是。
8. 历史未收口项（`P ≈ 199.7` 拍/帧等）与本轮无关，未动。

---

## 12. 最终态与对端改动台账（全部可回退）

**板子（默认停在 0x1F）**：

```
BID_0x04=0x0000001f   MAGIC=0x50360001   SCRATCH_0x08=0x00000000   CARRIER=1
MIR_CTRL_0x144=0x00000002  => cap_en=0（回退态：采集冻结，读口照常）; clr toggle 电平=1
MIR_STATUS_0x13C=0x001a0000 => level=0 / unf=0 / any_drop=1 / cap=0 / ver=3 / src_sel=0
UNIMPL_0x14C=0xffffffff
W11=0x004E0000 (累计 5,111,808 B)  W70=0x00256000 (累计镜像丢字 2,449,408 B)
残留进程: 无 (sink/mir_dump/udp_src/tcp_src/rx_check/tcpdump 全空)
```

**对端上动过的状态（逐条 + 回退方式）**：

| # | 改动 | 状态 | 回退 |
|---|---|---|---|
| 1 | 新目录 `/tmp/p8_board/`（工具 + 日志 + 抓取样 + bench） | 保留 | `rm -rf /tmp/p8_board` |
| 2 | `02:00.0` 设备级 `remove`+`rescan`（烧录后恢复 PCIe，既定流程） | 生效中 | 再 remove+rescan |
| 3 | **临时** `sysctl net.core.wmem_max=16384` → 已回 4194304 | **已回退**（现 4194304） | 无 |
| 4 | **临时** `tc qdisc add dev lo root netem rate 100mbit` → 已 `del`（回 `noqueue`） | **已回退** | 无 |
| 5 | **临时** `tc qdisc add dev enp1s0f1np1 root fq` → 已 `del`（回 `mq`） | **已回退** | 无 |
| 6 | `/tmp/p8_board/mir_*.bin` + `*.log` + `p8_logs.tgz` | 保留 | 随目录 1 一起删 |
| 7 | `/tmp/p7b_biz/`（现役工具） | **一字未动**（step0 核过 md5） | — |

**未动的持久配置**：未改 sysctl 持久项、未改 NetworkManager / `nmcli`（`enp1s0f1np1` 仍是 unmanaged 原状）、
未动 coalesce（`Adaptive RX: off / rx-usecs: 0` 是既有状态）、未写 QSPI。

---

## 13. 文件清单（本目录）

```
REPORT.md（本件）· STEP0_selfcheck.txt · step0_selfcheck.sh · burn_0x1F.sh
burn/wrapper_p4_0x1F.bit（烧录副本, sha e365c5ca…0133）· burn/BURN_0x1F_*.txt + stdout 副本
runs/FINAL_STATE_0x1F.txt · runs/STEP_TOOLS_selftest.txt
runs/mir_{dma2,dma3,bar1,bar3,tcp4}.bin（抓取样）· runs/p8_logs.tgz + runs/peer_logs/（对端全部日志）
_tools/p7b_mir_dump_mmap.diff · _tools/p7b_udp_src_bytes.diff + p7b_udp_src.orig.cpp · _tools/p7b_tcp_src_bytes.diff
_tools/{run_dma.sh,run_bar.sh,run_tcp.sh,run_paylen_matrix.sh,static_protocol_probe.sh}
_tools/{p8_udp_rx_check.cpp,p8_mock_sendmmsg.h,p8_mocktest_udp_src.cpp,p8_mir_analyze.py,
         p8_io_probe.c,p8_c2h_one.c,p8_c2h_bench.c,p8_bar_bench.c}
```

*本件 = 读数与证据，不代行裁定；凡"打通"结论均带原始 `MIR_*` / 快照 / 计数行。*
