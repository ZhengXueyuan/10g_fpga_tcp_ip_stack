# P9 板级首测 —— 位流 `0x22`（XDMA 用户接口 = AXI4-Stream）· REPORT

> **边界声明**：只烧归档副本（JTAG 易失，**未写 QSPI**）；**未改** `rtl/**` · `tb/**` · `board/**` · 工具源码
> （`_proj_pcie/**` 一字未写；对端只在新目录 `/tmp/p9_board_0x22/` 部署并**现编**工具）；
> `/tmp/p7b_biz/` 与 `/tmp/p8_board*` `/tmp/p9_*` 全程**只读**（逐文件 md5 前后双核，四件逐字相同）；
> git 只读（未提交）；口令只作 `--sudo` 前缀、**未落盘**。
> **本件不下 PASS/FAIL 裁定**；「未观测到」一律写成「未观测到」，不写「不存在」；不写「时序已解决」。

## 0. 一句话结论（观测，非裁定）

1. **AXIS 首次上板可用**：换烧后驱动把引擎认成 **ST**（`dmesg: 0-C2H0-ST`）、`identifier` bit15 翻 1、
   `0x148` 是真字（`MIR_DMA_CNT`，口径 = 从镜像取走的 32 位字数）⇒ **`--stream`（平铺 `read()`）端到端跑通**。
2. ⭐⭐ **字节序判决 = 假设成立（恒等），(a)/(b)/(c) 三形态全部被排除**：`captured[i] ^ 0xA5 == pattern[off+i]`
   **逐字节 0 失配（4 跑 / 共 4,651,016 B）**；无先验的**车道发现**独立给出 `m→q = [0..15]` 恒等映射
   （16/16 车道唯一且 100% 命中）；三条候选形态各自 **99.60–99.62% 失配**。
3. **干净抓取**：S1/S2/S5 三跑 `式A == 0 ∈ [0,32]` · `式B == 0 ∈ [0,24]` · `ΔW70 == 0` ·
   `level_end=0 / premise_level0=1` · `pc == taken == K` · `reads` 无 partial/nonmul64/short/ended_early。
4. ⚠️ **D4 现场形态已抓到（S4，且是有意构造的）**：前一轮在打包器槽里留的**半拍（1 grant = 8 B）**
   在**起测瞬间（`clr` / `cap_en=0→1`）以短拍（`tlast=1`）冒出** ⇒ 该 EOP 把第 1 个 C2H 描述符**提前关掉**
   ⇒ 宿主侧：头 8 B 是上一轮的尾巴、该页剩余 **4,088 B 是零洞**、读**截短**（1,044,488）、
   尾 8,176 B 未交付（后续 `read()` 10 s 超时、RC=1）；`式A = 4,080` **正确地判红**。**内容本身无损**
   （体 1,040,392 B 对齐后 **0 失配**）。**恢复**：显式排空后下一跑（S5）**逐项回到全绿**。

---

## 1. 与派单描述的核对（如实报）

1. **派单值逐条核对**：位流 sha256 **`c2e48a69…635a`** ✓（15,431,261 B）· 工具 sha256 **`f5e8d486…`** ✓
   （= `p7b_mir_dump.cpp`；对端现编产物 md5 **`5ea97067cd90f93c8c47d1f272b04667`** = 工具报告 §0 记录值**逐字相同**）。
2. **"板上前态 = 0x21（受控停流）"** ✓ 实测：烧前 `0x04=0x00000021` / `0x08=0x2` / `CARRIER=0` /
   `MIR_STATUS=0x00180000`(ver=3)。
3. ⚠️ **`dmesg` 里的引擎名不会在 probe 时打印** —— 它只出现在驱动**调试转储**路径
   （`engine_reg_dump`/`engine_status_dump`，由**传输超时**触发；`libxdma.c:3784` 一带）。
   ⇒ 本轮**主动诱导了一次 C2H 超时**（`dma_from_device -s 4096`、无数据流，10 s 后超时）来取这个名字。
   代价 = 一次 `transfer_abort + engine_stop`；**恢复证据 = 紧随其后的 5 跑全部正常**（S1–S5）。
4. **MM 对照臂 = 烧前现读（同会话、同板、同驱动）**：`identifier`/`alignments` 在 `0x21` 位流上读过一次；
   **未做**「烧回 0x21 再读一次」的往返臂（派单标"可选"）。dmesg 的 `0-C2H0-MM` 那一行取自**更早一个会话**
   （同一 boot、同一驱动）⇒ 详见 §2 的口径标注。
5. **未碰 `--no-strict-quiesce` / `--allow-ver-mismatch` / `--k-bytes`（除 S3 故意的）**：所有跑的
   `ver`/`path`/`UNIMPL` 门都是**放行态**（`ver=4 / path=stream / 0x14C=0xffffffff`）。
6. **工具侧观测到一次"读长度非 64 倍数"**：S4 的第二次 `read()` 请求 4,088 B（不是 64 的倍数）——
   它**因无数据而超时**，因此**不能**回答 `CONF §7-⑥`（宿主侧非 64 倍数读的形态）⇒ 登记为未测。

---

## 2. 烧录 + 身份五判据（原始件 `burn/BURN_0x22_*.txt`）

**位流**：`burn/wrapper_p4_0x22.bit`（从 `_proj_10g/notes/p9_build_0x22/wrapper_p4.bit` 复制；烧前双核 sha256 逐字相同）。

**烧录五判据（stdout 逐字）**：`TCPREG_BIT_EXISTS = 1` · `TCPREG_BIT_MTIME = 1791732219` ·
`TCPREG_PROG device=xcku5p_0 freq=1MHz` · **`End of startup status: HIGH`** · 非注释行 `TCPREG_PROG_DONE` ·
位流路径含 `wrapper_p4_0x22.bit` · 无 `TCPREG-ABORT` · stdout 新鲜（mtime ≥ T0）。**烧前** `0x04 = 0x00000021` ✓。

**设备级 `remove`+`rescan` 后身份五判据（逐条）**：

| # | 判据 | 期望 | 实测（原始行） |
|---|---|---|---|
| 1 | `0x04` = 本构建 BID | `0x00000022` | `ID_BID 0x00000022 (want 0x00000022)`；直读 `BID_0x04=…: 0x00000022` |
| 2 | 71 字窗口（`0x20..0x138`） | 全可读、无别名 | `WINDOW_SCAN_NFF=0`（71 字逐字扫，无 `0xffffffff`） |
| 3 | 未实现地址 `0x14C` | `0xffffffff` | `ID_UNIMPL 0xffffffff (want 0xffffffff)`；直读同值 |
| 4 | `LnkSta` | x4 | `LnkSta: Speed 5GT/s (downgraded), Width x4` |
| 5 | 2 BARs | Region 0 (1M) + Region 1 (64K) | `Region 0: …[size=1M]` / `Region 1: …[size=64K]`；dmesg `identify_bars: 2 BARs: config 1, user 0, bypass -1` |

另：`ID_MAGIC 0x50360001` ✓ · `ID_MARKER 0xdeadbeef` ✓ · **`ID_RC=0`** · `/dev/xdma0_{user,control,c2h_0,h2c_0}` 全在位。
**烧后清零核对**：`W11 = W13 = W70 = 0` ✓ · `MIR_CTRL = 0` ✓ · `MIR_DMA_CNT = 0` ✓ · `0x08 = 0`（TX 使能）✓ ·
`MIR_STATUS_0x13C = 0x00200000` = **`ver=4`**（0x21 是 `0x00180000` = ver=3 ⇒ 代际标记与构建一致）。

---

## 3. ⭐ ST 身份三条（CONF §⑦ 点名的三条；逐条原始命令 + 输出）

**① 驱动把引擎认成 ST（dmesg 引擎标识）**

```bash
# 诱导一次 C2H 超时（无数据流 ⇒ 10 s 后驱动走 timeout 调试转储路径）
sudo tools/dma_from_device -d /dev/xdma0_c2h_0 -s 4096 -f /tmp/p9_board_0x22/tmo.bin   # RC=251, ELAPSED=10
sudo dmesg | grep -E "xdma_xfer_submit|engine_reg_dump|engine_status_dump"
```
```
[179373.230769] xdma:xdma_xfer_submit: xfer 0x…,4096, s 0x1 timed out, ep 0x1000.
[179373.230784] xdma:engine_reg_dump: 0-C2H0-ST: ioread32(…) = 0x1fc18006 (id).
…
[179373.230828] xdma:engine_status_dump: SG engine 0-C2H0-ST status: 0x00000001: BUSY
```
**对照（MM 臂，更早一个会话、同 boot/同驱动）**：`[140094.614579] xdma:engine_reg_dump: 0-C2H0-MM: …`
⇒ **`MM → ST` 成立**。附带一条：转储里 `control` 寄存器 **MM `0x00f83e1e` → ST `0x00f83e1f`**（bit0 差）。

**② 引擎 `identifier` 寄存器 bit15**（`reg_rw /dev/xdma0_control <addr> r`）

| 寄存器 | MM 臂（烧前，0x21 位流上现读） | **ST 臂（0x22，现读）** | Δ |
|---|---|---|---|
| H2C ch0 `0x0000` | `0x1fc00006`（bit15=0） | **`0x1fc08006`**（bit15=1） | `+0x00008000` |
| C2H ch0 `0x1000` | `0x1fc10006`（bit15=0） | **`0x1fc18006`**（bit15=1） | `+0x00008000` |

**③ `alignments` 寄存器**（`0x004C` / `0x104C`）

| 寄存器 | MM 臂 | ST 臂 |
|---|---|---|
| H2C ch0 `0x004C` | `0x00010140` | **`0x00010140`（逐字未变）** |
| C2H ch0 `0x104C` | `0x00010140` | **`0x00010140`（逐字未变）** |

（解码 `0x00010140` = `align_bytes[23:16]=0x01` / `granularity[15:8]=0x01` / `address_bits[7:0]=0x40(64)` ⇒
**两模式都是 1/1/64** ⇒ 驱动侧对齐约束面不变；`CONF §7-①` 的「ST 是否放松对齐」这一格 = **未变（1 B）**。）

---

## 4. ⭐⭐ 字节序判决（本轮主任务）

**判据**：`captured[i] ^ 0xA5 == pattern[off + i]`（图案流 = `p7b_pattern.h` 的 xorshift64 语义，
**独立 Python 复算**，先过两条文档自检向量 `7f0b02e5…d63f` / `0300422d9b47cac0` 才判）。

| 跑 | 源配置 | 对账长度 | **恒等假设** | (a) 16B 整拍反序 | (b) 拍内 8B 半交换 | (c) 拍内 4B 字序 | 车道发现 |
|---|---|---|---|---|---|---|---|
| S1 | paylen 1472（相位 0）· K=1 MiB | 1,048,576 | **0 失配（`fm=-1`）** | 99.61% | 99.62% | 99.62% | **[0..15] 恒等**（16/16 唯一 · 100%） |
| S2 | paylen 1470（相位 6）· K=1,505,280 | 1,505,280 | **0 失配（`fm=-1`）** | 99.60% | 99.61% | 99.61% | **[0..15] 恒等** |
| S3 | paylen 1472 · `--k-bytes` 档 | 1,048,576 | **0 失配（`fm=-1`）** | — | — | — | **[0..15] 恒等** |
| S5 | paylen 1472（恢复跑） | 1,048,576 | **0 失配（`fm=-1`）** | 99.61% | 99.61% | 99.61% | **[0..15] 恒等** |

**判决：假设成立（恒等）——既不是 (a) 也不是 (b) 也不是 (c)，也不是 (c′) 4B 反序 / 8B 反序 / 拍内 rot4。**
即 **XDMA 把 `tdata` 按小端落进宿主内存**（`tdata[7:0]` = 内存 byte 0 = 流的第一个字节），
与 `rtl/axis_c2h_stream.v` 头注释的冻结口径逐字一致；**"宿主侧落点"这条【未定项】现已被板级逐字节坐实**。

**原始证据（S1，`runs/ANALYZE_S1.txt` 全文）**：
```
SELFTEST off0_15    7f0b02e536a14ed61ab049b856add63f OK
SELFTEST off1460_67 0300422d9b47cac0 OK
IDENTITY        first_mismatch=-1 mism_bytes=0 of 1048576 (全等)
HYP (a) rev16   first_mismatch=0 mism_bytes=1044532 …(99.61%)
HYP (b) swap8   first_mismatch=0 mism_bytes=1044580 …(99.62%)
HYP (c) 4B字序  first_mismatch=0 mism_bytes=1044562 …(99.62%)
LANE_DISCOVERY beats=512 (起拍 1024) 每车道唯一一致映射 m->q: [0,1,2,…,15]
LANE_DISCOVERY 歧义/不满分车道: 无 (16/16 唯一且 100% 命中)
GOT  [0] da ae a7 40 93 04 eb 73 …   (32 B)
EXP  [0] da ae a7 40 93 04 eb 73 …   (逐字节相同)
XOR  [0] 00 00 00 00 00 00 00 00 …   (全 0 ⇒ 逐字节见证)
ALL_BYTES mism=0 / 1048576   (逐字节全等)
```
> ⚠️ 三形态的"失配数"不可读成"接近全错 = 数据坏了"：它们是对**同一份正确数据**换重排假设后的
> **判别力读数**（~99.6% ⇒ 假设被强判别）。恒等档 = 0 才是"数据对"。

---

## 5. 干净抓取（三跑读数，原始 stdout = `runs/ARM_S{1,2,5}_raw.txt`）

| 量 | **S1** | **S2** | **S5** |
|---|---|---|---|
| `--stream` 参数 | `--bytes 1048576 --src udp --pat-off 0` | `--bytes 1505280 --pat-off 1048576` | `--bytes 1048576 --pat-off 4651016` |
| `pc`（抓取字节） | 1,048,576 | 1,505,280 | 1,048,576 |
| `taken_bytes`（= ΔMIR_DMA_CNT×4） | 1,048,576 | 1,505,280 | 1,048,576 |
| words0 → words1 | 0 → 262,144 | 0 → 376,320 | 0 → 262,144 |
| **ΔW70** | **0** | **0** | **0**（w70a=w70b=8，S4 的旧值） |
| **式 A**：`taken − pc` | **0**（∈[0,32]） | **0** | **0** |
| **式 B**：`K − taken − ΔW70` | **0**（∈[0,24]） | **0** | **0** |
| `level_end` / `premise_level0` / `waited_ms` | 0 / 1 / 0.0 | 0 / 1 / 0.0 | 0 / 1 / 0.0 |
| `reads / partial / nonmul64 / short / ended_early` | 1 / 0 / 0 / 0 / 0 | 2 / 0 / 0 / 0 / 0 | 1 / 0 / 0 / 0 / 0 |
| **`MIR_VERIFY`** | **rc=0 `fm=-1`** | **rc=0 `fm=-1`** | **rc=0 `fm=-1`** |
| 发端 `UDP_SUM` | 713 帧 / 1,048,576 B / `call_errors=0 poll_tmo=0` | 1024 帧 / 1,505,280 B / 0 / 0 | 713 帧 / 1,048,576 B / 0 / 0 |
| `PIN_CPU` 见证 | `PIN_CPU=5`（`PIN_RULE=avoid-nic`） | 同 | 同 |
| 板侧 `W13`（UDP app 校验器） | 0 → 0 | 0 → 0 | 0 → 0 |

**逐字节（离线独立路径）**：S1/S3/S5 各 1,048,576 B、S2 1,505,280 B **全部 `mism_bytes=0`**（§4 表）。
**`W11`（收字节账）终值 = `0x56F808` = 5,699,592 = Σ各跑 K**（1,048,576+1,505,280+1,048,584+1,048,576+1,048,576）
**逐位相合**；`W13 ≡ 0`（五会话全程）。
⚠️ `rate_Bps`（≈43 万）**不是带宽读数**（工具自打 `MIR_STREAM_NOTE`；本轮**不宣称**任何 C2H 带宽数字）。

---

## 6. ⚠️ 起测/停流边界 —— D4 现场形态（**S4，有意构造；原始件 `runs/D4_BOUNDARY.txt`**）

**构造**：S3 用 `--k-bytes 1,048,584` 让**源交付量 ≡ 8 (mod 16)** ⇒ 打包器槽里**留下一个 grant（8 B）**
（= 式 A 的 `taken−pc = 8`，本轮第一次读到非 0 残余）；S4 起测时该残拍被 `clr`（`stop=1`）**以短拍送出**。

**S4 原始读数**：`pc=1,044,488` · `taken=1,048,568` · `ΔW70=8` · **`reads=1 partial=1 nonmul64=1 short=1`**
· 第二次 `read()`（n=4,088）**`Connection timed out`（10 s）⇒ `read_error=1` / `TOOL_RC=1`** ·
`式A = 4,080 ∉ [0,32]`（**工具正确判红**）· `式B = 0` ✓ · `level_end=0`。

**抓取样逐字节解剖（离线，见 `runs/D4_BOUNDARY.txt`）**：

| 段 | 长度 | 内容 |
|---|---|---|
| `[0, 8)` | 8 B | **= S3 的残拍**（`0175175fa4e3dc44` = 图案 `[3602432, 3602440)` ^0xA5）**逐字节 MATCH** |
| `[8, 4096)` | 4,088 B | **全零**（第 1 个描述符页的剩余 ⇒ 从未被 DMA 写过） |
| `[4096, 1,044,488)` | 1,040,392 B | **= 图案 `[3602440, 4642832)` ^0xA5，`mism_bytes=0`（内容无损、只是布局位移）** |

**字节账**：`8 + 4,088 + 1,040,392 = 1,044,488 == pc` ✓；源流可用 = `K−8(丢)` = 1,048,568 ⇒ **尾截 8,176 B**；
其中 **最后 8 B 被显式 stop 探针捞回**（`MIR_CTRL=0x8` ⇒ `dma_from_device -s 16` ⇒ 驱动打
`read underflow 0x8/0x10`，落盘 8 B = `83630182d4f3e822` = **图案偏移 4,651,008 唯一命中** = S4 源流最后 8 B）。

**形态归属（按派单口径）**：**"`clr`/`cap_en=0→1` 起测瞬间出现短拍" = D4 域**（打包器在 `stop` 下把半拍
按一拍送出，`tlast=1`；此处 1 grant ⇒ 1 短拍）。**下游后果链是本轮新观测、需要归属裁定**：
该短拍的 **EOP 提前关掉第 1 个描述符** ⇒ 宿主侧「头残拍 + 零洞 + 截短 + 后续 read 超时」。
⛔ **不以"新缺陷"相称**（派单已明示 D4 未修；本条只是把它的**下游形态与量级**测出来了）。
⛔ **也不是"每跑都会发生"**：**只有当上一会话在打包器里留了半拍时才可能**（`taken ≡ 8 mod 16`）。
**恢复证据**：显式排空后 S5 **逐项全绿**（`pc=taken=K`、式 A=B=0、`fm=-1`、`level=0`）。

---

## 7. 未定 / 未观测（不许当已答）

1. **S4 的 8,176 B 尾截"丢在哪一层"不可观测**：外部只有形状（`taken−pc=4,080` + 打包器残 8 B + drain 捞回 8 B）；
   引擎内部/描述符回写路径的具体行为**无仪器**。⇒ 只写"形状与量级"，不写机制。
2. **`ΔW70 = 8`（只出现在 S4）的位置不可观测**（`W70` 只计数不给位置）；候选（解冻沿 1 拍 / 满态 /
   宿主停读）**未分离**。S1/S2/S3/S5 的 `ΔW70 ≡ 0`。
3. **`read #2` 超时的性质**：无数据 + "永不 tlast" ⇒ 等到驱动 `c2h_timeout`（10 s）—— **与文档语义自洽**，
   但它在 S4 里与"截短"叠加，**未做拆分实验**（例如带 `-e`/eop_flush 的同跑）。
4. **`CONF §7-⑥`（宿主侧非 64 倍数读长度）**：S4 的那次 4,088 B 读**因无数据超时** ⇒ **不能回答**该问题；
   本轮全部**满块**读长度都是 64 的倍数（`--chunk 1 MiB`）。
5. **`MIR_STREAM_WRAP`（跨 2³² 回卷）本轮未触发**（最大 `words1=376,320`）；`dword_max_step=262,144`
   是**采样稀疏**的产物（两次读之间），不是回卷。
6. **没有做**：烧回 `0x21` 的往返对照臂（MM 臂寄存器 = 烧前现读，dmesg 名 = 更早会话的读数）·
   `--src tcp` 的 ST 路径 · H2C（`m_axis_h2c_tready` 恒 1 = 吞噬）· 更大 K / 高码率（本轮全在 20 Mbps）·
   `--no-strict-quiesce` 场景 · 256 位宽度 · 引擎在"永不 tlast"下**长期**运行的进一步证据
   （CONF §7-④ 的 `-e` 负对照）——**本轮单跑 ≤2.7 s，未长时间累积**。
7. **采样自造空档的影响未测**（默认 50 ms 一点；本轮每跑只 2–3 点）—— 与工具 §8-5 同款未测项。
8. **`p7b_udp_src` 二进制指纹差异（登记）**：对端现编件 md5 **`e0d4da5834cb95d67afb0cc523d1f92f`**
   = 与 0x20/0x21 两轮部署件**逐字相同**（跨轮可比性反而最好）；而 `BUILD.md §3` 表里
   `p7b_udp_src` 写 **`a3faafd3…`**（= 现役 `/tmp/p7b_biz/` 里那件）。**同一源 + 同一命令行得到两个 md5，
   未追**（不影响本轮：发端在 5 跑里全部 `off_start/off_end` 与 `fm=-1` 自洽）。
9. **`/tmp/p7b_biz` 的 `ls -la | md5sum` 前后不同**（`49ad1077…` → `8980988a…`）：**四个文件 md5 逐字未变**
   （见 §8），差异来自**父目录 `/tmp` 的 mtime/size**（`ls -la` 会打印 `..` 项）⇒ 非改动。

---

## 8. 收尾与对端改动台账（全部可回退）

**板子（最终态，`runs/FINAL_STATE_0x22.txt`）**：`0x08 = 0x00000002`（**受控停流**；实测 `CARRIER=0` /
`Link detected: no`、停流后 NIC `port_rx_bytes/packets` 两次读**逐字不动**）· `MAGIC=0x50360001` ·
`BID_0x04=0x00000022` · `UNIMPL_0x14C=0xffffffff` · `MIR_STATUS=0x00200000`（ver=4 / cap=0 / any_drop=0 / level=0）·
**`MIR_CTRL=0x00000002`**（额外写了一次 `0x0` 把采集口置回冻结默认态 ⇒ `cap_en=0`/`dma_en=0`；
**bit1 = `clr` toggle 状态位**，与 0x21 轮 `§1-5` 同款，非"写 0 没生效"）· `MIR_DMA_CNT=0x00040000=262,144`（S5 残留，冻结）·
`W11=0x0056F808=5,699,592`（**Σ五会话 K 逐位**）· `W13=0` · `W70=8`（S4 的累计值）。**恢复配方**（与历轮相同）=
`reg_rw /dev/xdma0_user 0x08 w 0x0`。

| # | 对端改动 | 状态 | 回退 |
|---|---|---|---|
| 1 | 新目录 `/tmp/p9_board_0x22/`（部署 6 件 + 现编 2 件 + 抓样/日志 + `tmo.bin`/`drain.bin`） | 保留 | `rm -rf /tmp/p9_board_0x22` |
| 2 | `02:00.0` 设备级 `remove`+`rescan`（烧后恢复 PCIe，既定流程） | 生效中 | 再 remove+rescan |
| 3 | `/tmp/p7b_biz/`（现役） | **一字未动**（`p7b_udp_src a3faafd3…` / `p7b_snap.sh ba2faf79…` / `p7b_pattern.h b2f2e962…` / `p7b_affinity.h b0322279…`，前后双核逐字相同） | — |
| 4 | `/tmp/p8_board_0x21/`（上轮部署件） | **一字未动**（md5 核对同值） | — |
| 5 | 未改任何 sysctl / qdisc / coalesce / nmcli（`qdisc mq` 原样；`Adaptive RX: off` / `rx-usecs: 0` 本来就是关的） | — | — |
| 6 | 未写板载 QSPI | — | — |
| 7 | 残留进程扫描 | **无** | — |

---

## 9. 文件清单（本目录）

```
PROGRESS.txt · SHA256SUMS.txt · REPORT.md
step0_selfcheck.sh + STEP0_selfcheck.txt        (开工只读自检: 双 sha / 对端 / 现态 / MM 臂寄存器基线)
deploy_0x22.sh + DEPLOY_0x22_*.txt              (新目录部署 + put + 现编 + selftest + md5 双核)
burn_0x22.sh + burn/BURN_0x22_*.txt + burn/BURN_0x22_stdout_copy_* + burn/wrapper_p4_0x22.bit (sha c2e48a69…)
final_state.sh + runs/FINAL_STATE_0x22.txt      (受控停流 + MIR_CTRL=0 + 台账 + 进程扫描 + 未动复读)
runs/ARM_S{1,2,3,4,5}_raw.txt                   (五跑原始 stdout，逐字; 含 pre/post 快照 + PIN_CPU 见证)
runs/mir_S{1,2,3,4,5}.bin · runs/src_S*.log · runs/mir_S*.log
runs/ANALYZE_S{1,2,3,4,5}.txt                   (离线独立复算: LFSR 自检 + 恒等/三形态/车道发现 + 16 进制 dump)
runs/D4_BOUNDARY.txt                            (D4 边界链: 头残拍/零洞/体对齐/drain 捞出字节, 逐项复算)
runs/drain_S4leftover.bin                       (stop 探针捞回的 8 B = S4 源流末 8 B)
_tools/run_arm.sh · _tools/byteorder_analyze.py · _tools/d4_boundary.py   (本轮对端/本机脚本)
```

*本件 = 读数与证据，不代行裁定；凡"观测 = 期望"处均带原始 `MIR_*` / 快照 / 发端行；凡未测处均写"未测"。*
