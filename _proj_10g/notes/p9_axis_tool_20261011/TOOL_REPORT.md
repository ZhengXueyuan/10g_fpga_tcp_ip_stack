# P9 PC 工具侧实施报告 —— `p7b_mir_dump --stream`（PCIe 用户接口 MM→AXIS）

**轮次**：2026-10-11 夜 · P9（AXIS 改造）· **PC 工具侧**（不动 `rtl/**` `board/**` `sim/**`；不上板、不烧录）
**唯一被改的源文件**：`_proj_pcie/p7b_biz/p7b_mir_dump.cpp`（**本件版本** = 1514 行；`git diff --numstat` 相对
已被 TL 入库的前一轮工具 = **+331 / −190**；再往前的两轮增量见 §11/§12）
**规格口径**：`p8_axis_conf_20261011/CONF.md`（§1/§3/§4/§5-C）+ `p8_axis_recon_20261011/RECON.md` §3.3/§4
+ `P7B_TL_LEDGER_20261010.md` §10-23（用户四条裁定）+ `rtl/app_rx_mirror.v` 头注释
+ ⭐ **TL 2026-10-11 夜裁定（§11）**：计数点 = 从镜像取走（`dma_gnt`）的字 · 残差上界 24 B 仍成立 ·
  静默窗升级为带见证的断言
+ ⛔ **TL 审查 D1（§12，本件最高优先）**：原闭合式把两个计数点混在一式里 ⇒ **改两条独立恒等式**
  （式 A 成形器侧 / 式 B 镜像·K 侧）

**本件不下 PASS/FAIL 裁定**；「未观测到」一律写「未观测到」，不写「不存在」。

---

## §0 交付物与指纹（全部可回核）

| 件 | 位置 | 指纹 |
|---|---|---|
| 工具源码 | `_proj_pcie/p7b_biz/p7b_mir_dump.cpp` | md5 `ee8b829fdb6648f1072f11d65f9fb67b` · sha256 `f5e8d486ff3816b3fcb016762a86175058190eeb3af8b3620eeffee556ac8eb1`（1514 行） |
| 证据全文（编译 + selftest×2 + 五条假设备控；**§12 后整份重生成**） | `p9_axis_tool_20261011/EVIDENCE_stdout.txt` | sha256 `4ecedf9649e9bc531988793726ad3cf3933b5df244002264beb0f7066ad32081`（132 行；本地/对端逐字节相同） |
| 对端产物（scratch，**非部署件**） | `/tmp/p9_axis_tool/p7b_mir_dump`（唯一） | md5 `5ea97067cd90f93c8c47d1f272b04667`（部署面 `/tmp/p7b_biz/` **零写入**） |
| 输入头 | `p7b_pattern.h`（未改） | md5 `b2f2e9627bac53bf3b4ab2b565afe872`（= `BUILD.md` §3 表逐字相同 ⇒ 工具与板同源） |

编译：对端 `192.168.0.38`，`g++ (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0`，
**`g++ -O3 -pthread -Wall -o p7b_mir_dump p7b_mir_dump.cpp`**（BUILD.md §2 口径 + `-Wall` 只作零告警见证 ⇒ **0 行告警**）。
`--selftest` = **T1–T14 全 OK · `MIR_SELFTEST PASS` · RC=0**。

---

## §1 改动清单

**新增（全部在新段内，前缀 `MIR_STREAM_*` / `Stream*`）**：

| 段 | 行区间（**2026-10-11 夜 §12 后现读**） | 内容 |
|---|---|---|
| 头注释 P9 块 | `:46-86` | 新路径语义 / **两条独立恒等式** / 计数点已裁（从镜像取走）/ 两条上界 / `level==0` 前提 / 与 `--dma` 的分工 |
| `VER_MM/VER_ST` 与两条上界常量 | `:146` / `:152-153` | `MIR_STATUS.ver` 两代 · `RESID_MAX_MIRROR_DEF=24` / `RESID_MAX_SHAPER_DEF=32` |
| 平铺流抽象 | `:444-535` | `StreamIo` / `FdStreamIo`（含 `SIGALRM` 看门狗）/ `MemStreamIo`（**按 FPGA 两计数点建模**：取走 = 可见 + 成形器残余；K = 取走 + 丢 + 镜像残余） |
| **两条恒等式纯函数** | `:572-585` | `resid_in_band` · `idA_eval(pc, taken, R_A)` · `idB_eval(K, taken, drop, R_B)` |
| 静默窗判定（纯函数） | `:602-604` | `quiesce_verdict(quiesced, strict)` —— 前提未见证 ⇒ 调用侧必须判红（§11-3 的牙） |
| `run_stream` | `:607-725` | 采集主循环（**早停 = 打印不判红**，由式 B 解释不足量）+ 稀疏采样 + 跨回卷累计 + 带见证的静默窗 + 两条式判定 |
| 参数/身份纯函数 | `:735-758` | `stream_args_check`（7 类违规各自有名）/ `path_ver_ok`（路径↔ver） |
| 大缓冲 | `:761-768` | `buf_alloc`（`posix_memalign` 4096 对齐 + 预触页；失败返回 null） |
| `main` | `:769-1514` | 新参数解析（`--resid-max-mirror/-shaper` · `--k-bytes` · 旧名 `--resid-max` 别名 · `--no-strict-quiesce`）/ 参数门（**开设备之前**）/ ver 门 / `--stream` 主路径 / `MIR_STREAM_IDA`+`MIR_STREAM_IDB` 两条各自命名打印 / **FAIL 指名哪条式** / 退出码 |
| `--selftest` | `:935-1250` | **T8–T14**（见 §5；`:1075` 起 = T10c/T10d/T10e） |
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

### 2.3 记账：**两条独立恒等式**（逐项原始值 + 各自命名打印）

⛔ 旧式 `pc + ΔW70 + 残余 == ΔMIR_DMA_CNT×4` **已废**（它是 D1：把两个计数点混在一式里 ——
`dma_gnt` 计数点在**丢字节之后**，丢掉的字节根本不进"取走"）⇒ 改成：

```
MIR_STREAM_ACCT pc=<抓取字节> taken_bytes=<取走=ΔMIR_DMA_CNT×4> dW70=<板侧丢字节> w70a= w70b= words0= words1= dwords= K=<源交付量>
MIR_STREAM_IDA 式A(成形器) taken_bytes - pc == shaper_resid  -> <蕴含值>  band=[0,R_A] closed_a=<0|1>
MIR_STREAM_IDB 式B(镜像/K)  K - taken_bytes - dW70 == mirror_resid -> <蕴含值>  band=[0,R_B] closed_b=<0|1> (K 来源=…; --resid-max 旧名…)
```

- **式 A**：`taken_bytes − pc ∈ [0, --resid-max-shaper]`（默认 **32** = 成形器/在飞残余，审查给定上界）。
- **式 B**：`K − taken_bytes − ΔW70 ∈ [0, --resid-max-mirror]`（默认 **24** = 镜像 `acc_cnt_r + stg_cnt`；
  **只有这条含 K 与 ΔW70**）。旧名 `--resid-max` = **式 B 的别名**（打印里标明生效值）。
- **K 的口径** = `--bytes`（默认；= 本跑的**源交付量**），可用 **`--k-bytes N`** 显式覆盖
  （抓源流前缀 / K ≠ 抓取目标时**必须**声明，否则式 B 红并给出该提示）。
- `taken_bytes` 是 32 位计数器 ⇒ **跨回卷用"逐段 mod 2³² 差分再累加"**（全局 #55；真板 1.7 GB/s 下
  ~10 s 翻一次 0，单点原始值**不可**直接相减），并留 `MIR_STREAM_WRAP` 见证；`ΔW70` 同样按段累计。
- **两条残余都不可读** ⇒ 工具各自**蕴含**（`taken−pc` / `K−taken−ΔW70`）；越带 ⇒ **指名哪条式**的
  `FAIL:` 行 + **rc=1**。
- ⭐ **"不足量"不再单独判红**（D1 的连体修法）：丢字节场景下 `pc < want` **是预期形态**（丢掉的字节没了）
  ⇒ 早停只打 `MIR_STREAM_END saw=… pc=… want=…` + `ended_early=1` 见证；**解释不足量是式 B 的活**
  （ΔW70 或镜像残余）。内容判据同步收敛为**纯内容**（对 pc 个字节逐字节），不再拿"短读"当红。
  真读错（非早停/非看门狗）仍响亮判红。
- ⭐ **静默窗 = 带见证的断言**（§11-3）：终样本前有界等 `MIR_STATUS.level == 0`（默认 `--settle 1.0` s；
  每轮先写 `SNAP_CTRL` 做**触发式快照读**，再读 level）。**等到/超时都打实际值** ——
  `MIR_STREAM_QUIESCE level_end=… quiesced=… premise_level0=… waited_ms=… settle_s=… strict=…`；
  **超时 = 前提未见证 ⇒ 账本按"不可判"读 ⇒ 响亮 rc=1**（除非显式 `--no-strict-quiesce`，放行时另打
  `MIR_STREAM_QUIESCE_OVERRIDE` 见证）——理由：`level==0` 是"两条残余上界"的**前提**
  （打包器残留由 FPGA 侧停流 flush 清掉、FIFO 尾部由这一刻清掉）。
- **宿主跟不上的比例**：稀疏序列（`MIR_STREAM_SAMPLE`，默认每 50 ms 一点，最多 40 点 + 末 2 点）
  + 汇总 `MIR_STREAM_GAP … nondecreasing=<0|1> host_miss_bytes= host_miss_pct=`（= `(taken−pc)/taken`）。

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
| ① | **式 A（成形器侧）**：`0 ≤ taken_bytes − pc ≤ R_A(默认32)` | 越带 ⇒ `closed_a=0` + `FAIL: 式 A (成形器) 不成立: taken−pc=<v> ∉ [0,R_A]` + **rc=1** |
| ② | **式 B（镜像/K 侧）**：`0 ≤ K − taken_bytes − ΔW70 ≤ R_B(默认24)` | 越带 ⇒ `closed_b=0` + `FAIL: 式 B (镜像/K 侧) 不成立: K−taken−ΔW70=<v> ∉ [0,R_B]`（含"K 口径不对 ⇒ 用 `--k-bytes`"提示）+ **rc=1** |
| ③ | **静默窗前提高（`level==0` 见证）**：`quiesce_verdict(quiesced, strict)` | 未见证 ⇒ `FAIL:` 行 + **rc=1**（除非 `--no-strict-quiesce`；放行仍打见证，不静默） |
| ④ | **取走-抓取差序列**：逐点 `dacc×4 − pc` 与 `nondecreasing` / `host_miss_pct` | 只打印与汇总（**不静默吞**；其终值与 ① 联动） |
| ⑤ | `MIR_DMA_CNT` 未接自证：armed 且读回 `0xffffffff` ⇒ `FATAL` | rc=2（**未上板核**，见 §8-3） |
| ⑥ | **早停**（`read()==0` / 看门狗截断）：`ended_early=1` + `MIR_STREAM_END` 行 | **不单独判红**（由式 B 解释不足量）；真读错另判 |

**明确不搬进 ST 路径**：`计数器跳变 > 环容量 4096 ⇒ exit(2)` —— 它在 ST 下失去载体（无环，"落后"表现为
丢字节而不是回绕）。它**原样留在 `run_dma`（`--dma` 路径）**。

---

## §5 `--selftest` 读数（T1–T14；T8 起 = 本轮新增；**§12 后 T8/T9/T10/T10b/T10c/T10d 按 D1 重写 + 新 T10e**）

`EVIDENCE_stdout.txt` §[4] 全文；摘要（全部 `OK`，末行 `MIR_SELFTEST PASS`，`SELFTEST_RC=0`；§[4b] 两次跑逐字节相同）：

| 用例 | 覆盖 | 牙（负例都必须红） |
|---|---|---|
| T8 ×12 | **两条式各自的算例**（纯函数打表：式 A 6 例 / 式 B 6 例） | 两表各含 `band+1` / 负值 / `taken-only`、`taken>K`（含**审查例形** `K=0,drop=696`）等**必须** `closed=0` 的档 |
| T9 | **端到端·干净档**：`pc=65524 taken=65532 式A=8 式B=4` 双绿、内容 rc=0、`partial=7`、`nonmul64=8`（可见长度 ≡52(mod 64) ⇒ 尾读必非 64 倍数，作**见证**） | 任一不等 ⇒ 红 |
| **T10** ⭐⭐ | **D1 回归**（审查点名）：**有丢字节但两式都成立 ⇒ 必须全绿** —— `K=65536 / drop=696 / 镜像残余 4 / 成形器残余 8` ⇒ `pc=64828 / taken=64836 / 式A=8 ✅ / 式B=4 ✅ / ended_early=1 / 内容 fm=1000`；同打 **旧式 = pc+drop−taken = 688 ∉ [0,24]**（旧式必假红的留证） | 两式任一不绿 ⇒ 红 |
| **T10b** | **取走计数被打偏 +64 字 ⇒ 两条式都红**且各自点名：`式A resid=264(∉[0,32])` / `式B resid=−252(∉[0,24])` | 任一条没红 ⇒ 红 |
| T10c | **跑中回卷**（起点 `0xFFFFF000`）：`words0=4294963200 → words1=12287`（翻过 0）而 `dwords=16383 / taken=65532 / 两式双绿` | 跨回卷累计错 ⇒ 红 |
| **T10d** ⭐ | **静默窗前提高/低两臂**（§11-3）：mock level=1024 ⇒ `quiesced=0/premise=0`、`waited_ms≈51`（确实等满窗）且 `verdict(strict)=1`（⇒ 调用侧必判红）/ `verdict(lax)=0` / 见证到 ⇒ `0` | 前提未见证却不报红 ⇒ 红 |
| **T10e** ⭐ | **成形器残余越界 ⇒ 式 A 必红、式 B 仍绿**（`SR=40 > R_A=32`）：`式A resid=40 closed=0 / 式B resid=4 closed=1` | 两条式互相绑死（不是各自独立判）⇒ 红 |
| T11 ×6 | **ver 两态 × 三路径门矩阵**（`stream+ver3` / `dma+ver4` 必须拒；`bar` 两代都放行） | 方向反 ⇒ 红 |
| T12 ×7 | **`--stream` 参数校验**：`buf=0`/`chunk=0`/`chunk=100`/`want=0`/`want%8=4`/`want>buf` 各自**指名**拒（返回码 1..6 逐条比对） | 只要有一条"没拒" ⇒ 红 |
| T13 | **大缓冲**：128 MB 分配 + 预触页 + 可写 + **失败路径 `buf_alloc(0)==nullptr`** | 分配静默降级 ⇒ 红 |
| T14 ×4（`#ifndef _WIN32`） | **子进程退出码**：四类违规必须 **RC=2** 且输出含对应关键字（`--chunk`/`--bytes`/`--buf-mb`/`互斥`） | 只报错不返非零 ⇒ 红 |

**无板的正/负控（`EVIDENCE_stdout.txt` §[5]–[7]，走**真 main 路径**，设备 = 纯文件）**：

- §[5] **负对照 A**：假设备（静态取走计数 = 0）+ `--stream` ⇒ `式A = −65536 ∉ [0,32]`、`式B = +65536 ∉ [0,24]`、
  **两条各自指名报红** + **RC=1** ⇒ 主路径的账本判据在 main 层也**有牙**，且诊断不再混账。
- §[5b] ⭐ **负对照 C**（§11-3 的牙）：同一假设备但 `level=7`（静默窗不达）⇒
  `MIR_STREAM_QUIESCE level_end=7 quiesced=0 premise_level0=0 waited_ms=101.4` +
  `FAIL: 静默窗未达 level==0 …前提未获见证` + **RC=1**。
- §[5c] ⭐ **同上 + `--no-strict-quiesce`**：出 `MIR_STREAM_QUIESCE_OVERRIDE strict=0 level_end=7`
  见证（**不静默**）；剩下的 `FAIL` 只剩两条式（本假设备结构上闭不了，见 §8-4）。
- §[5d] ⭐ **旧名与 K 的接纳见证**（§12）：`--resid-max 40 --k-bytes 65536` ⇒
  `MIR_STREAM_CFG … resid_max_mirror=40 … k_bytes=65536`、
  `MIR_STREAM_IDB … band=[0,40] … (K 来源=--k-bytes; --resid-max 旧名已用(生效值 = 式B 上界))`。
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

1. ⭐⭐ **计数点口径 = 已裁，且由此抓到 D1 并修复（详见 §11-1 + §12）**：TL 裁定 `MIR_DMA_CNT` 数
   **从镜像取走（`dma_gnt`）的 32 位字数**（"内部不丢、无空间不取"，与 `tvalid&&tready` 下游口径本该相等）——
   ⛔ **本工具第一版据此写的"单一闭合式"把取走量与源交付量混为一谈**（`dma_gnt` 计数点在**丢字节之后**）
   ⇒ **有丢字节的跑必假红**（审查实测 −688）。**已改为两条独立恒等式**（式 A / 式 B，见 §2.3 与 §12）。
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
# 3) 板级 (换上新 ST 位流后; 例: 源交付 K=64 MiB, 全抓)
./p7b_mir_dump --bid 0x22 --bytes 67108864 --stream --src udp --out /tmp/mir.bin
#   判据看五行: MIR_STREAM_ACCT(原始值) / MIR_STREAM_IDA(closed_a) / MIR_STREAM_IDB(closed_b) /
#               MIR_STREAM_QUIESCE(premise_level0) / MIR_VERIFY(rc)  (+ MIR_STREAM_GAP = 宿主跟不上比例)
#   · 只抓源流**前缀** (want < 源总量) 时: 必须加 --k-bytes <源交付量>, 否则式 B 会(正确地)报红并提示本条
#   · 非静默场景 (源不停, level 到不了 0) 才加 --no-strict-quiesce; 加了它就等于声明"账本按不可判读"
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

## §12 订正块（2026-10-11 夜 · TL 只读审查 **D1** 修复；本件最高优先）

**缺陷（审查逐字要点）**：第一版的闭合式 `pc + ΔW70 + 残余 == ΔMIR_DMA_CNT×4` **与计数点不同义** ——
`MIR_DMA_CNT` 数的是**从镜像取走**的字（**已经排除了丢字节**）⇒ ΔW70 **不能再出现在左边**；
审查用 FPGA 侧单元门自己的数演示：取走 2184 / 抓取 2176 / ΔW70 696 ⇒ 旧式给 `2184−2176−696 = −688`
⇒ **任何有丢字节的跑都会硬 FAIL(rc=1) 并打出误导诊断**。并点名 mock 的硬编码
"源交付量 = 可见 + 丢 + 残余"（旧 `:494`）**正是隐藏 D1 的结构**。另：`--resid-max` 旧名保留为别名。

**修复（两条独立恒等式，各自判定/命名/报实际值）**：

| 式 | 恒等式 | 带 | 默认上界 | 失败时 |
|---|---|---|---|---|
| **式 A（成形器侧）** | `taken_bytes − pc == 成形器残余` | `[0, --resid-max-shaper]` | **32 B**（审查给） | `closed_a=0` + `FAIL: 式 A (成形器) 不成立: taken−pc=<v> ∉ [0,R_A]` |
| **式 B（镜像/K 侧）** | `K − taken_bytes − ΔW70 == 镜像残余` | `[0, --resid-max-mirror]` | **24 B**（镜像 `acc_cnt_r+stg_cnt`） | `closed_b=0` + `FAIL: 式 B (镜像/K 侧) 不成立: K−taken−ΔW70=<v> ∉ [0,R_B]`（含 `--k-bytes` 提示） |

⛔ **只有式 B 含 K 与 ΔW70**；`taken_bytes = ΔMIR_DMA_CNT×4`（从镜像取走）。
`--resid-max`（旧名）= **式 B 的别名**，打印里标明生效值；`K` 默认 = `--bytes`，可用
**`--k-bytes N`** 显式声明（抓前缀时**必须**）。**连体修法**：丢字节场景下 `pc < want` 是预期形态 ⇒
早停改为**打印不判红**（`MIR_STREAM_END` + `ended_early=1`），不足量**由式 B 解释**；内容判据收敛为纯内容
（对 pc 字节逐字节），真读错仍判红。

**mock/selftest 同步**（按 FPGA 两个计数点的真实定义重写 mock + 三条新/重写牙，见 §5）：
`取走流 = 可见 + 成形器残余`；`K = 取走 + 丢 + 镜像残余`。
⭐ **D1 回归（T10，必绿）**：`K=65536 / drop=696 / 镜像残余 4 / 成形器残余 8` ⇒
`pc=64828 / taken=64836 / 式A=8✅ / 式B=4✅ / ended_early=1 / fm=1000`，并留证 **旧式 = 688 ∉ [0,24]**。
⭐ **成形器越界（T10e）**：`SR=40>32` ⇒ `式A red / 式B green`（两条式**各自独立**）。⭐ **T10b**：取走计数打偏
⇒ **两条式同时红**。T9/T10c/T10d 按新模型重写（T9 的 `nonmul64>=1` = 可见长度 52 mod 64 的**见证**）。

**重跑读数**（`EVIDENCE_stdout.txt` 整份重生成，sha256 见 §0）：对端 `g++ -O3 -pthread -Wall` **零告警**
（`REBUILD_RC=0`）· **T1–T14 全 OK · `MIR_SELFTEST PASS` · `SELFTEST_RC=0`** · **两次跑逐字节相同**
（`TWO_RUNS_IDENTICAL`）· 五条假设备控全按预期（§[5] 两条式各自指名报红 / §[5b] 静默窗前提高 / §[5c] 显式放行
见证 / §[5d] 别名与 `--k-bytes` 接纳 / §[6]/[7] 门控与正控）。

**新登记（§12 后仍然成立的未定/未测）**：
① **早停语义在真 XDMA 上的形态未测**（`read()==0` 何时出现 / 是否伴随驱动超时）—— 本件只在 mock 上验过；
② 式 A 的 **32 B 上界是审查给的先验**，**未与 FPGA 侧 `axis_c2h_stream` 的实现在飞深度核对**（若该件
在飞 > 32 B，请回话改 `--resid-max-shaper`）；
③ `K` 的两个来源（`--bytes` 默认 / `--k-bytes`）在板级首跑里**未实测**；
④ main 层**正例（真闭合）仍未做**（静态假设备结构上做不出"跑中计数推进"；正例只到 mock 端到端）；
⑤ 采样开销 / 真 partial 形态 / 与 0x21 同会话 A/B **仍未测**（同 §8）。

*本件 = 工具侧实施与读数；不代行裁定。凡未测处均写"未测"，凡未观测处均写"未观测到"。*
