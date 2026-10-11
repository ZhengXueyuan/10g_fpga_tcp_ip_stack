# P9 PC 工具侧实施报告 —— `p7b_mir_dump --stream`（PCIe 用户接口 MM→AXIS）

**轮次**：2026-10-11 夜 · P9（AXIS 改造）· **PC 工具侧**（不动 `rtl/**` `board/**` `sim/**`；不上板、不烧录）
**唯一被改的源文件**：`_proj_pcie/p7b_biz/p7b_mir_dump.cpp`（`git diff --numstat` = **+787 / −8**，1373 行）
**规格口径**：`_proj_10g/notes/p8_axis_conf_20261011/CONF.md`（§1 基线 / §3 权威端口表 / §4 硬约束 / §5-C 驱动侧）
+ `p8_axis_recon_20261011/RECON.md` §3.3/§4 + `P7B_TL_LEDGER_20261010.md` §10-23（用户四条裁定）
+ `rtl/app_rx_mirror.v` 头注释（残余口径 = `acc_cnt_r + stg_cnt`, 0..24 B）
+ ⭐ **TL 2026-10-11 夜裁定（本方订正依据，见 §11）：计数点 = 上游 `dma_gnt` 字数 · 残差上界 24 B 仍成立 ·
  要求把静默窗升级为"带见证的断言"**

**本件不下 PASS/FAIL 裁定**；「未观测到」一律写「未观测到」，不写「不存在」。

---

## §0 交付物与指纹（全部可回核）

| 件 | 位置 | 指纹 |
|---|---|---|
| 工具源码 | `_proj_pcie/p7b_biz/p7b_mir_dump.cpp` | md5 `514c02a8cc623893e1632349718ff17d` · sha256 `3df42fcc27e901dc9cbe42ab3766e1c8e170c6c95af13cccb2db5353e7786873`（1373 行） |
| 证据全文（编译 + selftest + 三条负控 + 一条正控；§11 后已重跑） | `p9_axis_tool_20261011/EVIDENCE_stdout.txt` | sha256 `a78d73e812012266d65b693762fb419c77b588047d9bd250ce9370341ff89700`（129 行；本地/对端逐字节相同） |
| 对端产物（scratch，**非部署件**） | `/tmp/p9_axis_tool/p7b_mir_dump`（唯一） | md5 `b505a34664c082b22e20554556ccbdc3`（部署面 `/tmp/p7b_biz/` **零写入**） |
| 输入头 | `p7b_pattern.h`（未改） | md5 `b2f2e9627bac53bf3b4ab2b565afe872`（= `BUILD.md` §3 表逐字相同 ⇒ 工具与板同源） |

编译：对端 `192.168.0.38`，`g++ (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0`，
**`g++ -O3 -pthread -Wall -o p7b_mir_dump p7b_mir_dump.cpp`**（BUILD.md §2 口径 + `-Wall` 只作零告警见证 ⇒ **0 行告警**）。
`--selftest` = **T1–T14 全 OK · `MIR_SELFTEST PASS` · RC=0**。

---

## §1 改动清单

**新增（全部在新段内，前缀 `MIR_STREAM_*` / `Stream*`）**：

| 段 | 行区间（**2026-10-11 夜 §11 后现读**） | 内容 |
|---|---|---|
| 头注释 P9 块 | `:46-85` | 新路径语义 / 三件记账 / 闭合式 / **计数点已裁（上游）** / 残缺口径 + **`level==0` 前提** / 与 `--dma` 的分工 |
| `VER_MM/VER_ST` 常量 | `:146` | `MIR_STATUS.ver` 两代 |
| 平铺流抽象 | `:439-549` | `StreamIo` / `FdStreamIo`（含 `SIGALRM` 看门狗）/ `MemStreamIo`（mock 板：交付量、丢字节、残余、回卷、偏置） |
| 闭合式纯函数 | `:544-549` | `closure_eval(pc, drop, delivered, resid_max, *resid)` |
| **静默窗判定（纯函数）** | `:564-566` | ⭐ `quiesce_verdict(quiesced, strict)` —— 前提未见证 ⇒ 调用侧必须判红（§11-3 的牙） |
| `run_stream` | `:569-676` | 采集主循环 + 稀疏采样 + 跨回卷累计 + **带见证的静默窗**（`:620-637`）+ 端点/派生量 |
| 参数/身份纯函数 | `:684-707` | `stream_args_check`（7 类违规各自有名）/ `path_ver_ok`（路径↔ver） |
| 大缓冲 | `:710-717` | `buf_alloc`（`posix_memalign` 4096 对齐 + 预触页；失败返回 null） |
| `main` | `:718-1373` | 新参数解析（含 `--no-strict-quiesce`）/ 参数门（**开设备之前**）/ 互斥门 / ver 门 / `--stream` 主路径 / 三件记账 + `MIR_STREAM_QUIESCE(level_end/premise_level0/waited_ms)` + 闭合式打印 / 退出码（`:1300-1308` 静默窗前提高低两臂） |
| `--selftest` | `:874-1135` | **T8–T14**（见 §5；`:1006` 起 = T10d 静默窗前提高/低两臂） |
| 全局小改 | `main` 首行 | `setvbuf(stdout, _IOLBF)` —— 账本日志 stdout/stderr 交错时不再把 `FAIL` 冲到最前（2026-10-11 实测） |

**逐字保留（旧路一个字没动）**：`FdIo`（mmap 取寄存器）/ `run_dump`（user-BAR 弹出路径）/ `RingIo`·`FdRingIo`·`run_dma`（MM 环路径，**含** `计数器跳变 > 环容量` 的 `exit(2)` FATAL 与 `lag_max/clobber/short_reads`）/ `snap_read` / `verify` / 旧的全部打印行名（`MIR_ID` `MIR_STATUS` `MIR_SRC` `MIR_UNIMPL` `MIR_DONE` `MIR_ACCT` `MIR_RATE_NOTE` `MIR_DMA_*` `MIR_VERIFY`）与退出码语义。

> 注：`git diff` 的 **8 行删除**逐条 = 头注释 6 行（加 `[3]dma_en` / 重述 0x148 / 退出码加"不闭合"）+ `4u<<19 → ver<<19`（mock 加 `ver` 字段）+ `--seconds` 解析加 `secs_given` + usage 首行。**无功能行被删**。

---

## §2 三项设计决策与理由

### 2.1 取数：平铺 `read()`（不 lseek / 不做 16 B 对齐假设）

- `lseek` 不用（ST C2H 下 `f_pos` 写进描述符后立刻被回写缓冲地址覆盖 —— `CONF.md` §5-C 逐字）；
  16 B 对齐假设**整体移除**（那是我们自己的 MM 从机造的；PG195 Table 11：AXI4-Stream 地址限制 = None）。
- **read 长度策略（照顾"描述符长度须 64 B 倍数"）**：`--chunk N`（默认 **1 MiB**）**必须 %64==0**（否则 `exit(2)`）；
  只有"剩余不足一块"的**最后一笔**可能非 64 倍数，且逐跑打出见证 `MIR_STREAM_READS/DONE ... nonmul64=<0|1>`。
  **理由**：(a) 那条约束的原文是 **descriptor length**（`CONF.md` §4.3-②），而驱动按**页**切 SG（§5-C）——用户侧
  read 长度并不直接等于描述符长度，且 `CONF.md` §7-⑥ 明确写了"宿主侧表现**未测**"；(b) 把 K 强行取成 64 倍数会
  **静默改变"抓 K 字节"这个语义**（多抓或少抓）—— 宁愿**少而可见**地偏离一次并留见证；
  (c) 所有满块读合规 ⇒ 偏离面 = 至多 1 笔 <64 B。
- 每块之间做一次寄存器采样（见 §2.3），采样是**自造空档**（默认 `--sample-ms 50`），已在输出里显式登记。
- 完成语义 = 收满 `count`（驱动默认，不给 `O_TRUNC`）；**不做**任何"阻塞读 → 非阻塞"改造（`p7b_io.h` 里那套
  socket 机制不搬进来；`--seconds`>0 时才用 `SIGALRM` 打断阻塞 read 作看门狗，默认 **0=不武装**）。

### 2.2 PC 侧大缓冲：`--buf-mb`（默认 **128**），**预分配一次**

- `posix_memalign(4096)` 页对齐 + **预触页**（`memset`）：① 页对齐贴驱动 `get_user_pages` 的按页切 SG；
  ② 把首次触碰的缺页全部挪到起测**之前** —— 否则缺页落在流中间就是一次宿主空档，而空档**直接变板侧丢字节**
  （自造假缺陷）。全程**零重分配**（大缓冲是 `main` 里的一块，`run_stream` 直接往里写，`--stream` 路径**不再**
  经 `g_last_buf` 拷贝 ⇒ 也省掉一次 128 MB 级 memcpy）。
- `--bytes > --buf-mb` ⇒ 起测前 `exit(2)`（响亮）；分配失败 ⇒ `FATAL: 预分配 … 失败` + `exit(2)`，**不降级**。
- 见证行：`MIR_STREAM_BUF bytes=134217728 mb=128 prefault=1 aligned=4096`。

### 2.3 记账：三件分开 + 闭合式（逐项原始值）

```
MIR_STREAM_ACCT pc=<抓取字节> dW70=<板侧丢字节> w70a= w70b= words0= words1= dwords= delivered_bytes=<交付字节>
MIR_STREAM_CLOSURE pc + dW70 + resid == delivered_bytes -> resid_implied=<推导值> band=[0,resid_max] closed=<0|1>
```

- **交付字节 = Δ`MIR_DMA_CNT` × 4**（P9 口径：已交付 AXIS 口的 32 位字数）；`MIR_DMA_CNT` 是 32 位
  ⇒ **跨回卷用"逐段 mod 2³² 差分再累加"**（全局 #55；1.7 GB/s 下 ~10 s 就翻一次 0，单点原始值**不可**直接相减），
  并留 `dword_max_step` 作回卷余量见证；`ΔW70` 同样按段累计。
- **残余不可读** ⇒ 工具把它**蕴含**出来：`resid_implied = delivered − pc − ΔW70`，落在 `[0, --resid-max]`
  （默认 **24** = `app_rx_mirror` 头注释的 `acc_cnt_r + stg_cnt`）⇒ `closed=1`；否则 `closed=0` + stderr `FAIL` + **rc=1**。
- ⭐ **静默窗 = 带见证的断言**（§11-3）：终样本前有界等 `MIR_STATUS.level == 0`（默认 `--settle 1.0` s；
  每轮先写 `SNAP_CTRL` 做**触发式快照读**，再读 level）。**等到/超时都打实际值** ——
  `MIR_STREAM_QUIESCE level_end=… quiesced=… premise_level0=… waited_ms=… settle_s=… strict=…`；
  **超时 = 前提未见证 ⇒ 账本按"不可判"读 ⇒ 响亮 rc=1**（除非显式 `--no-strict-quiesce`，放行时另打
  `MIR_STREAM_QUIESCE_OVERRIDE` 见证）——理由：`level==0` 是"残余上界 = 镜像 `acc+stg` ≤24 B"这条的**前提**
  （打包器残留由 FPGA 侧停流 flush 清掉、FIFO 尾部由这一刻清掉），前提不成立时闭合式的读数不承载判据力。
- **宿主跟不上的比例**：采一段稀疏序列（`MIR_STREAM_SAMPLE`，默认每 50 ms 一点，最多 40 点 + 末 2 点）
  并汇总 `MIR_STREAM_GAP … nondecreasing=<0|1> host_miss_bytes= host_miss_pct=`（= `(delivered−pc)/delivered`）。
  **不是静默判据**：`closed=0` 直接 `FAIL` + rc=1。

---

## §3 身份门与 `ver` 策略（选择 + 理由）

- `--bid` **无默认**的规则不变（`FATAL` + rc=2）。
- `MIR_STATUS.ver`：**{3,4} 都收**（收不下 ⇒ rc=2），**打印实际值** `MIR_VER ver=… path=… expect=…`；
  然后**再按路径判配对**：`--stream` 要求 ver=4、`--dma` 要求 ver=3、默认(user-BAR)路径**两代都放行**；
  不配对 ⇒ `FATAL` + rc=2，**除非**显式 `--allow-ver-mismatch`（放行时打 `MIR_VER_GATE override=1` 见证）。
  **理由**：两代 `0x148` 的语义不同（ver3 = 环已写字数 / ver4 = 已交付 AXIS 口字数），走错读出口会
  **静默读错东西**（`--dma` 在 ST 位流上会 lseek 出一段流并按"环"记账）——本工程一贯用**拒绝而非警告**
  （`run_matrix_p4dfix.bat` 的同一条纪律）。用户建议的"都收 + 打实际值"**已包含**在内，我只加了一层配对门 +
  一个显式逃生口；0x21（ver=3）旧位流照样能做对照（`--dma`/默认路径）。
- 边界身份门 `MIR_UNIMPL(0x14C) == 0xffffffff` 在 **`--stream` 与 `--dma` 都保留**（几何不扩 ⇒ 两代通用）。

---

## §4 新异常判据（ST 路径；与 MM 的旧判据**不混用**）

| # | 判据 | 触发时 |
|---|---|---|
| ① | **闭合式**：`0 ≤ delivered − pc − ΔW70 ≤ resid_max` | 越带 ⇒ `closed=0` + `FAIL:` 行 + **rc=1**（这是"新判据有牙"的主件） |
| ② | ⭐ **静默窗前提高（`level==0` 见证）**：`quiesce_verdict(quiesced, strict)` | 未见证 ⇒ `FAIL:` 行 + **rc=1**（除非 `--no-strict-quiesce`；放行仍打见证，不静默） |
| ③ | **交付-抓取差序列**：逐点 `dacc×4 − pc` 与 `nondecreasing` / `host_miss_pct` | 只打印与汇总（**不静默吞**；其终值与 ① 联动） |
| ④ | `MIR_DMA_CNT` 未接自证：armed 且读回 `0xffffffff` ⇒ `FATAL` | rc=2（**未上板核**，见 §8-3） |
| ⑤ | 采样/回卷余量：`MIR_STREAM_WRAP`（`words0/words1/wrap_seen/dword_max_step`） | 打印（回卷余量见证） |

**明确不搬进 ST 路径**：`计数器跳变 > 环容量 4096 ⇒ exit(2)` —— 它在 ST 下失去载体（无环，"落后"表现为
丢字节而不是回绕）。它**原样留在 `run_dma`（`--dma` 路径）**。

---

## §5 `--selftest` 读数（T1–T14；T8 起 = 本轮新增）

`EVIDENCE_stdout.txt` §[4] 全文；摘要（全部 `OK`，末行 `MIR_SELFTEST PASS`，`SELFTEST_RC=0`）：

| 用例 | 覆盖 | 牙（负例都必须红） |
|---|---|---|
| T8 ×6 | **闭合式算例**（纯函数打表） | `resid=band+1` / `resid<0` / `delivered-only` 三条**必须** `closed=0` |
| T9 | **`--stream` 端到端（mock 板·干净档）**：`pc=65536` `closed=1` `resid=4` `deliv=65540` 逐字节 rc=0；`partial=7`（碎片读被计数）`nonmul64=0` | 任一不等 ⇒ 红 |
| T10 | **端到端 + 真有丢字节（洞在第 1000 B）**：`rc=1 fm=1000`（内容必红）**同时** `closed=1`/`resid=4`/`drop=8` ⇒ 证明"交付量 vs 抓取量"**分账** | 账不闭 ⇒ 红 |
| **T10b** | ⭐ **构造必然不闭合的输入**（交付计数凭空 +64 字 = 256 B） ⇒ **`closed=0` / `resid=260`** | **必须红**（本轮"新判据要有牙"的正面证据） |
| T10c | **跑中回卷**（起点 `0xFFFFF000`）：`words0=4294963200 → words1=12289`（确实翻过 0）而 `dwords=16385`、`deliv=65540`、`closed=1` | 跨回卷累计错 ⇒ 红 |
| **T10d** ⭐ | **静默窗前提高/低两臂**（§11-3）：mock level=1024 ⇒ `quiesced=0/premise=0`、`waited_ms=50.7`（确实等满窗）且 `verdict(strict)=1`（⇒ 调用侧必判红）/ `verdict(lax)=0` / 见证到 ⇒ `0` | 前提未见证却不报红 ⇒ 红 |
| T11 ×6 | **ver 两态 × 三路径门矩阵**（`stream+ver3` / `dma+ver4` 必须拒；`bar` 两代都放行） | 方向反 ⇒ 红 |
| T12 ×7 | **`--stream` 参数校验**：`buf=0`/`chunk=0`/`chunk=100`/`want=0`/`want%8=4`/`want>buf` 各自**指名**拒（返回码 1..6 逐条比对） | 只要有一条"没拒" ⇒ 红 |
| T13 | **大缓冲**：128 MB 分配 + 预触页 + 可写 + **失败路径 `buf_alloc(0)==nullptr`** | 分配静默降级 ⇒ 红 |
| T14 ×4（`#ifndef _WIN32`） | **子进程退出码**：四类违规必须 **RC=2** 且输出含对应关键字（`--chunk`/`--bytes`/`--buf-mb`/`互斥`） | 只报错不返非零 ⇒ 红 |

**无板的正/负控（`EVIDENCE_stdout.txt` §[5]–[7]，走**真 main 路径**，设备 = 纯文件）**：

- §[5] **负对照 A**：假设备（静态交付计数 = 0）+ `--stream` ⇒ `resid_implied=-65536`、`closed=0`、
  `FAIL: 闭合式不成立…`、**RC=1** ⇒ 主路径的账本判据在 main 层也**有牙**。
- §[5b] ⭐ **负对照 C（新，§11-3 的牙）**：同一假设备但 `level=7`（静默窗不达）⇒
  `MIR_STREAM_QUIESCE level_end=7 quiesced=0 premise_level0=0 waited_ms=101.4` +
  `FAIL: 静默窗未达 level==0 …前提未获见证` + **RC=1**。
- §[5c] ⭐ **同上 + `--no-strict-quiesce`**：出 `MIR_STREAM_QUIESCE_OVERRIDE strict=0 level_end=7`
  见证（**不静默**）；剩下的 `FAIL` 只剩闭合式（本假设备结构上闭不了，见 §8-4）。
- §[6] **负对照 B**：`--dma` 在 ver=4 设备上 RC=2 / `--stream` 在 ver=3 设备上 RC=2（两向都拦）。
- §[7] **正控**：默认(user-BAR) 路径在 ver=4 设备上**放行**（`MIR_VER … path=bar expect=0`），身份四行全中，
  随后按预期 `level=0` 超时（无板）⇒ rc=1。

---

## §6 与旧 `--dma` / user-BAR 路径的**兼容性声明**

| 项 | 留（逐字） | 换（新） |
|---|---|---|
| `--dma` 取数（lseek+16 B 对齐+最小读块） | ✅ 原样 | — |
| `--dma` 记账（`cnt0/cnt1/lag_max/clobber/short_reads`、`cnt1−cnt0==words`） | ✅ 原样 | — |
| `--dma` 的 `FATAL: 计数器跳变 …` | ✅ 原样 | — |
| `--dma` 的 `MIR_DMA_CNT==0xffffffff` 未接门 | ✅ 原样 | — |
| user-BAR 弹出路径（读=弹出 / level 协议 / `MIR_ACCT dW11/dW70`） | ✅ 原样（**注**：它没有 `--bar` 开关，就是"不给 `--dma`/`--stream` 时的默认路径`） | — |
| 全局 `--bytes % 4 == 0` 前置条件 | ✅ 原样（所有路径） | — |
| ver 门 | — | ⭐ **新**：`--dma` 只在 ver=3 放行（ver=4 ⇒ rc=2）；默认路径两代都放行 |
| `--bytes % 8 == 0` | — | ⭐ **仅 `--stream`** 新增（P8-STG 起镜像按 64 位字打包；顺带关掉台账 §10-22-4 ③「K≡4(mod 8) 安静短读」那一格） |
| `--stream` 与 `--dma` 互斥 | — | ⭐ **新**：同时给 ⇒ rc=2 |
| stdout 行缓冲 | — | ⭐ **新**：`setvbuf(_IOLBF)`（只改刷新时机，不改任何行内容） |

输出行名：新路径全部 `MIR_STREAM_*`；旧行名/格式**未改一个字**（老台架解析器不会因本轮改动而失配）。

---

## §7 与任务描述**不符**之处（如实列；3 条实义 + 2 条口径）

1. ⭐ **闭合式的计数点假设 → ✅ 已裁（详见 §11-1）**：原描述与本工具的假设（计数点在**丢字节点同侧/上游**）
   已由 TL 明确定为**设计口径** —— `MIR_DMA_CNT` 数**从镜像取走（`dma_gnt`）的 32 位字数**，
   **不是** `tvalid&&tready` 下游字数（FPGA 侧"内部不丢、无空间不取"⇒ 两口径本该相等，但**上游才是设计口径**）
   ⇒ `pc + ΔW70 + 残余 == 交付字节` **就是设计口径下的恒等式**，不需要换式。本工具的实现**无需改动**；
   本条从"不符/未定"**关闭**。（RECON §3.3-② 的 `tvalid&&tready ×4` 措辞按"与上游口径本该相等"读。）
2. **`--bar` 不是开关**：任务里"保留既有 `--dma`（MM 路径）与 `--bar` 不动" —— 本工具**没有 `--bar` 参数**；
   user-BAR 弹出路径 = 不给 `--dma`/`--stream` 时的**默认路径**。已按"默认路径逐字不动"处理。
3. **那条 FATAL 的位置**：`计数器跳变 > 环 4096` **只存在于 `--dma`**（`run_dma` 内）；user-BAR 路径从来
   没有过这条判据（它没有字计数器）。所以"限定在 MM 路径（`--dma`/`--bar` 保留原判据）"的落地 = **原样不动
   + 不搬进 ST**（已如此）。
4. **口径**：PG195 的 64 B 约束是**描述符长度**约束，不是宿主 `read()` 长度约束；`CONF.md` §7-⑥ 明确
   "宿主侧表现**未测**、驱动按页切 SG"。本轮按"满块全合规 + 至多一笔尾读例外 + 见证"处理（§2.1）。
5. **口径**：任务写"`MIR_STATUS.ver` 接受 4"——本工具的实现是 **{3,4} 都收 + 实际值必打 + 路径↔ver 配对门
   （带显式逃生口）`；理由见 §3。

---

## §8 未定项（⛔ 不许当已答）

1. ~~0x148 的计数点~~ ⇒ ✅ **已裁（§11-1）：上游 `dma_gnt` 字数** ⇒ 闭合式即设计口径下的恒等式，
   本项**关闭**（改动面 = 无；只在头注释与报告里把"假设"升为"已裁"）。
2. ⭐ **AXIS 侧新件（`axis_c2h_stream.v`）的尾拍残留口径未读**（该文件尚未落盘）⇒ `--resid-max` 默认取
   镜像侧口径 **24**（TL §11-2 确认：**正常停流序列下 24 仍成立** —— 打包器残留由 FPGA 侧"停流 flush 一拍短拍"
   清掉；**若某停流序列 flush 覆盖不到，FPGA 侧会回一句**，届时再用 `--resid-max` 放宽或按新件头注释回改）。
   **跨过 24 的"未闭合"在板级首跑里出现时，先查这一条再看别处。**
3. `MIR_DMA_CNT` 是否被 `clr` 归零、以及 ST 下它读回 `0xffffffff` 的判"未接"分支：**未上板核**（设计意图 =
   归零；Δ 口径对初值不敏感，但"未接自证"只有设计依据）。
4. **main 层的正例（真闭合）未做**：静态假设备做不到"跑中计数推进"（文件不可动态更新）；正例只到 **mock
   端到端（T9/T10/T10c，与真路径同一段 `run_stream` 代码）**。真板正例 = 板级轮。
5. **采样开销对"丢字节"的影响幅度未测**（采样本身 = 自造空档；默认 50 ms 一点）。板级轮若要分离它，
   建议同跑两臂 `--sample-ms 0` 与 `--sample-ms 200`（本件**未跑**）。
6. `--stream` 下驱动**部分读/短读**在真 XDMA 上的形态**未测**（mock 里 `partial` 已被计数，T9；真板未知）——
   工具对 partial 只计数 + 打印，不当错误；对 `read()==0` / `<0` 才判 red。
7. `--seconds` 看门狗默认 **0（不武装）**：无人值守跑长流时阻塞 `read()` 可能久等 ⇒ 板级轮建议显式给值
   （`MIR_STREAM_WATCHDOG` 行会见证武装与否）。
8. 工具**未接** `p7b_affinity.h` ⇒ 任何 `rate_Bps` **不得当板子能力引用**（沿用旧纪律，新路径同样打
   `MIR_STREAM_NOTE`）。
9. **未跑**：与 0x21 位流的同会话 A/B（需要板）；对 `--stream` 的 `--src udp|tcp` 门在 ST 位流上的行为
   （寄存器语义未变 ⇒ 预期照旧，**未测**）。

---

## §9 复跑命令（照抄；⚠️ 两条环境坑见 §10-3）

```bash
# 1) 部署 (Git Bash) —— ⚠️ 必须 MSYS_NO_PATHCONV=1, 否则远程路径被 MSYS 改写 ⇒ FileNotFoundError
P=/c/Users/zhxue/anaconda3/python.exe
MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 $P tools/peer_ssh.py "mkdir -p /tmp/p9_axis_tool"
MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 $P tools/peer_ssh.py --put \
  "D:/repo/XCKU5PMini/udp_hls_10g/_proj_pcie/p7b_biz/p7b_mir_dump.cpp" /tmp/p9_axis_tool/p7b_mir_dump.cpp
MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 $P tools/peer_ssh.py --put \
  "D:/repo/XCKU5PMini/udp_hls_10g/_proj_pcie/p7b_biz/p7b_pattern.h" /tmp/p9_axis_tool/p7b_pattern.h
# 2) 编译 + 自检 (对端; ⛔ 不碰 /tmp/p7b_biz/)
MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 $P tools/peer_ssh.py \
  "cd /tmp/p9_axis_tool && g++ -O3 -pthread -Wall -o p7b_mir_dump p7b_mir_dump.cpp && ./p7b_mir_dump --selftest"
# 3) 板级 (换上新 ST 位流后; 例: 抓 64 MiB)
./p7b_mir_dump --bid 0x22 --bytes 67108864 --stream --src udp --out /tmp/mir.bin
#   判据看四行: MIR_STREAM_ACCT / MIR_STREAM_CLOSURE(closed) / MIR_STREAM_QUIESCE(premise_level0) /
#               MIR_VERIFY(rc) + MIR_STREAM_GAP
#   非静默场景 (源不停, level 到不了 0) 才加 --no-strict-quiesce; 加了它就等于声明"账本按不可判读"
```

---

## §10 出处 / 证据 / 两条工具链发现

- **证据全文**：`EVIDENCE_stdout.txt`（sha256 见 §0；含 [1] 编译环境 · [2] 指纹 · [3] 重编零告警 ·
  [4] selftest 全量 · [5] 负对照 A · [6] 负对照 B · [7] 正控）。
- **规格出处**：`p8_axis_conf_20261011/CONF.md` §1/§3/§4/§5-C（EDA 确认轮，`5abd9e1`）·
  `p8_axis_recon_20261011/RECON.md` §3.3/§4 · `P7B_TL_LEDGER_20261010.md` §10-23（用户四条裁定：BID 0x22 +
  ver 3→4 同批 / 128 MB = PC 侧缓冲 / 首版板内不加缓冲 / tlast 方案 A）· `rtl/app_rx_mirror.v:36-38`
  （残余口径）+ `:108-126`（dma 口合同）· `_proj_pcie/rtl/axi_regs.v:56-88`（MIR 四字）·
  `_proj_10g/notes/p7b_affinity/BUILD.md` §2/§6（编译口径 + 部署）。
- **两条工具链发现（本轮实测踩到，建议登记）**：
  ① **`tools/peer_ssh.py --put` 的远程路径会被 MSYS 改写**：从 Git Bash 直接给 `/tmp/...` ⇒
     `FileNotFoundError`（远程收到的是 `C:/.../Temp/p9_axis_tool/...` 之类）⇒ **必须 `MSYS_NO_PATHCONV=1`**
     （BUILD.md §6 的原文只警示了**本地**参数，未提**远程**参数 —— #72 同族）。
  ② `peer_ssh.py` 把远端输出 `sys.stdout.write(out)` 时按**本地 GBK** 编码 ⇒ 输出含 `⇒`/中文时
     本地抛 `UnicodeEncodeError`（**远端其实已跑完**）⇒ 加 `PYTHONIOENCODING=utf-8`（工程坑 16① 同族）。

## §11 订正块（2026-10-11 夜 · TL 四点裁定 + 本次改动/重跑）

**TL 裁定（逐字要点）**：① **计数点 = 上游**：`MIR_DMA_CNT` 数**从镜像取走（`dma_gnt`）的 32 位字数**，
**不是** `tvalid&&tready` 下游字数（FPGA 侧"内部不丢、无空间不取" ⇒ 两口径本该相等，但**上游才是设计口径**）。
② **残差上界**：正常停流序列下 = 镜像 `acc+stg`（≤24 B）—— 打包器残留由 FPGA 侧"停流 flush 一拍短拍"清掉，
镜像 FIFO 尾部由本工具的 `level==0` 等待清掉 ⇒ **`--resid-max` 默认 24 仍成立**；FPGA 侧若发现某停流序列
flush 覆盖不到会**回一句**，届时再放宽。③ 请在 `--stream` 路径**补一条见证**：终样本前断言/打印
**`level == 0`**（触发式快照读 `MIR_STATUS.level`）；已有等价有界等待（`--settle`）⇒ **升级成带见证的断言**
（等到/超时都要打实际 `level` 值，不许静默）。④ 其余按已交付的原样。

**本次改动（源码只有 `p7b_mir_dump.cpp`；相对 §11 前版本 **+64 / −0**（1373−1309 行）；**累计 +787 / −8**）**：

| # | 改动 | 落点（现读行号） |
|---|---|---|
| 1 | 头注释：计数点**已裁（上游）** + `level==0` 前提段（把"假设/两种口径"整段换掉） | `:46-85` |
| 2 | `StreamOpts.strict_quiesce` + `StreamRes.premise_level0/wait_ms` + **`quiesce_verdict()`** | `:551-566`, `:533-535` |
| 3 | `run_stream` 静默窗：**每轮触发式快照读 level**、记 `waited_ms`、`quiesced=(level==0)`、`premise_level0=quiesced` | `:620-637` |
| 4 | `main`：`--no-strict-quiesce` 解析 + usage + `MIR_STREAM_QUIESCE`（含 `premise_level0/waited_ms/strict`）+ `MIR_STREAM_CLOSURE`（加 `premise_level0`）+ 新 `MIR_STREAM_WRAP` 行 + **前提未见证 ⇒ `FAIL` + rc=1**（放行则打 `MIR_STREAM_QUIESCE_OVERRIDE`） | `:730/759/772`, `:1234-1310` |
| 5 | selftest **T10d**（前提两臂：未见证 ⇒ strict 判红 / lax 放行 / 见证到不判红）+ T9 断言加 `premise_level0` | `:1006-1032`, `:918` |

**重跑与读数**（`EVIDENCE_stdout.txt` 已整份重生成，sha256 见 §0）：
对端 `g++ -O3 -pthread -Wall` **零告警**（`REBUILD_RC=0`）· **`--selftest` T1–T14 全 OK / `MIR_SELFTEST PASS` / `SELFTEST_RC=0`**
（T10d 一行：`level_end=1024 quiesced=0 premise=0 waited_ms=50.7 verdict(strict)=1 verdict(lax)=0 OK`）·
新增两条主路径负控：**level=7 ⇒ `FAIL: 静默窗未达 level==0 …` + `RC=1`**；同跑加 `--no-strict-quiesce`
⇒ 出 `MIR_STREAM_QUIESCE_OVERRIDE` 见证（**不静默**）、剩余 `FAIL` 只剩闭合式。§[6]/§[7] 两条旧控**未变**（复跑一致）。

**未定（§11 后仍然成立）**：`axis_c2h_stream.v` 未落盘 ⇒ 其尾拍残留口径**未读**（默认带 24 = TL ② 的口径）·
`clr` 是否归零 `MIR_DMA_CNT` **未上板核** · main 层**正例（真闭合）未做**（静态假设备结构上做不出"跑中计数推进"；
正例只到 mock 端到端 T9/T10/T10c，与真路径同一段代码）· 采样开销对丢字节的影响**未测** ·
真 XDMA 的 partial/短读形态**未测** · 与 0x21 同会话 A/B **未跑**。

*本件 = 工具侧实施与读数；不代行裁定。凡未测处均写"未测"，凡未观测处均写"未观测到"。*
