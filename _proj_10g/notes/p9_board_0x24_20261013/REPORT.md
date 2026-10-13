# P9 板级轮 `0x24`（URAM 板内缓冲）—— 烧录 + 身份 + 行为套件（§5a–§5d）+ URAM 收益主臂

> **边界声明**：只烧归档件（JTAG 易失，**未写 QSPI**）；**未改** `rtl/**`、`board/**`、`sim/**`、工具源码（`_proj_pcie/**` 一字未写；对端只在**新目录** `/tmp/p9_board_0x24/` 部署 + 补 `/tmp/p9_rate/p7b_snap.sh` 一件）；`/tmp/p7b_biz/` 全程只读（收尾 md5 四件逐字未变）。**本件不下 PASS/FAIL 裁定**；「未观测到」不写「不存在」；不写「时序已解决」。口令只作 env 前缀、**未落盘**（落盘前 grep 复核为空）。
> **轮序**：开工核 → 烧录/PCIe/身份 → 环境前置 → §5a 干净抓取（P2A/P2B）→ §5b URAM 收益主臂（单源 11 窗 S0–S10 / 4 源 10 窗 F0–F9）→ §5c 内容臂 CAPD24 → §5d D4 停流链（S3D4/S4D4/S5D4 + 停流探针）→ 收尾（受控停流）。全程单 agent 串行，板侧无并发。
> **工具指纹（对端现读；收尾 ⑧ 复核未变）**：`p7b_mir_dump 7cebded7e9270b6a2d81f5db29843f4d`（= 宿主读轮同一二进制）· `p7b_udp_src e0d4da5834cb95d67afb0cc523d1f92f` · `p7b_snap.sh 97c66382cf2a0c334f5e6466ce714ad2` · `run_win_hw.sh 7b40bcbb4adc2bf776d421656b65e7a9` · `analyze_readlog.py a451b98d1416e9c21be5ce03e9e61169`。
> ⚠️ **中途订正已并入**（协调者转达 kimi 审查 P1）：`--dual` 窗的 **READLOG 行级 `dw70/ddma` 有两段锁窗口竞态**（`p7b_mir_dump.cpp:1199-1210` ⇒ 行级 `dw70` 可 uint32 回绕、`Σdw70` 不保证 == `drop`）⇒ 本件**主读数一律用 `MIR_STREAM_ACCT` 快照差分口径**（独立、不受该竞态影响）；凡引用 READLOG 派生量处均标注「辅助口径（含 kimi B-1 竞态）」。
> **单位口径**：ΔW70 一律「字节 + **十进制 MB**」（与基线 5.46/8.93 MB 同口径）；`runs/STATS_*.txt` 内打印的是 MiB（换算见本件表格）。
> （落盘说明：REPORT.md 由 TL 代落盘 —— 平台拒写 .md 的已知间歇故障；正文逐字为板级 agent 回传。⚠️ TL 注：本件 §0.1 引用的位流 sha256 一律用**实算真值 `…e50a7c3…`**；散文中曾出现的 `…e50e7c3…` 为转抄笔误，已在相关件就地订正。）

---

## §0 开工核 + 烧录证据

### 0.1 ⛔⛔ sha256「转抄差异」登记（判据所有者裁定权保留）

| 出处 | sha256（第 50 位字符） | 性质 |
|---|---|---|
| **盘上实算**（`sha256sum` + Python `hashlib` 双工具） | `e3b07957aea0326a168b9db0238ef9dd933dc7a21884c92e50`**`a`**`7c3b0abadf1db` | **程序化** |
| `p9_build_0x24/SHA256SUMS.txt`（09:10:49 程序化重跑） | `…e50`**`a`**`7c3…` | **程序化** |
| `vivado_prj/p7b_ku5p_prj.runs/impl_1/wrapper_p4.bit`（Vivado 原始输出） | `…e50`**`a`**`7c3…` **逐字节同** | **程序化** |
| 派单期望值 = `p9_build_0x24/REPORT.md:107` = `PROGRESS.txt:23` = `P7B_LOOP_HANDOFF.md:374` = 台账 `:928` | `…e50`**`e`**`7c3…` | **散文（人工书写/转抄）** |
| 全仓搜索 `e` 变体 | 仅命中上述散文件（+本件 `burn_0x24.sh`/BURN 日志的登记行） | **无任何文件命中它** |

- **两者恰差 1 个字符（idx 50，`e`↔`a`）**。一字符之差**不可能**来自文件替换/损坏（多字符全变）；盘上件与 **impl_1 原始输出逐字节同 sha**（该件 mtime `2026-10-13 08:57:04.082`，`.bit` 头逐字 `Version=2025.2;SW_CRC=05997278 … 2026/10/13 … 08:57:01`）⇒ 盘上件 = 本次构建原产物。
- ⇒ **判定（推断；最终裁定权在判据所有者）**：散文侧 1 字转抄笔误。**烧录按实算真值 + impl_1 交叉核执行**（`burn_0x24.sh` 文件头 ⚠️ 块：`WANT=…e50a7c3…` + `IMPL1_ORIG_SHA` 双核）。
- ⭐ **行为级闭环**：烧后 `0x04 = 0x00000024`（§2）⇒ 该位流**确为 0x24 构建**。
- **记录**：位流副本 mtime `2026-10-13 09:00:18.830420700 +0800`（本次独有串对应物）· 15,431,261 B。

### 0.2 烧录（原始件 `burn/BURN_0x24_20261013_220442.txt` + `burn/BURN_stdout_copy_*.txt`）

**五判据逐字**：`End of startup status: HIGH` · 非注释行 `TCPREG_PROG_DONE` · 位流路径含 `wrapper_p4_0x24.bit` · stdout 新鲜（mtime ≥ T0）· 无 `TCPREG-ABORT` ⇒ **BURN_OK**。`TCPREG_BIT_MTIME = 1791900282`（= 本轮副本，非陈旧件）；`TCPREG_PROG device=xcku5p_0、freq=1MHz`；age=138 s。
**烧前见证**：`hw_server active` · `XDMA_NOT_LOADED` · 板端 = 厂商设计（`02:00.0 Serial controller … 9034`、桥窗 `size=1M` ⇒ **场景 C**）；`insmod xdma.ko` RC=0；厂商 control BAR 0x0 = `0x1fc00006`。

## §1 判据设计（承派单 + 既有轮口径；逐条注明出处）

| # | 判据 | 口径出处 | 判定式（跑前定） |
|---|---|---|---|
| B-1 | 烧录五判据 | `p9_bench_restore_20261013/03_burn_pcie_id.sh` | 见 §0.2 |
| I-1 | 身份五判据 | 派单 §3 + p7b_snap.sh | `0x00==0x50360001` · `0x04==0x00000024` · 71 字窗 NFF=0 · `0x14C==0xffffffff` · `0x14==0xdeadbeef`；`id`（`NW=71 EXPECT_BID=0x00000024`）RC=0 |
| I-2 | PCIe 场景 C | `P7B_PCIE_RESCAN_RECOVERY.md` §7 | 根端口 `0000:00:1c.0` remove+rescan ⇒ `2 BARs` + `LnkSta x4` |
| E-1 | 环境前置 | 重部署报告 §5(a) + 全局 #68 | `/32` + nmcli unmanaged + `adaptive-rx off rx-usecs 0`；`ip route get` 必须 dev enp1s0f1np1 |
| A-1 | 干净抓取 | 0x23 板级轮 §3（P2A/P2B 同构型） | `pc=taken=K` · 式A=式B=ΔW70=0 · `rc=0 fm=-1` · 离线逐字节 0 失配 + 车道恒等 |
| M-1 | **URAM 收益主臂** | 派单 §5b（hostread after 臂同构型 = K=1 GiB/chunk 4 MiB/`--dual 2`/unpaced/`--no-verify`/READLOG=1；**跨会话基线** 0x23：单源 5.46 MB / 4 源 8.93 MB，出处 `p9_hostread_20261013/REPORT.md` §4） | 每臂 **≥30 s 累计窗**（逐窗 span 累加，rate 轮口径）· 主读数 = **ACCT 差分 ΔW70** · 每窗式B 终态=0 |
| C-1 | 内容臂 | 派单 §5c（CAPD 同款 K=256 MiB verify-on） | 首洞位置/L；0x23 基线 = `4,196,408 / 42,952 B` |
| D-1 | D4 停流链 | 0x23 板级轮 §4（S3'/S4'/S5' + stop probe） | 式A=8/0/8；停流 `-s 8` ⇒ **8/8 RC=0 + 逐字节 MATCH**；读后 level=0 |
| F-1 | 收尾 | `final_state_rt.sh` 配方 | `0x08=0x2` + `MIR_CTRL` 功能位 0 + 无残留进程 + NIC 冻结 |

**口径声明**：主读数一律 **ACCT（快照差分）**；READLOG 派生量（entry/gap/idle/O）仅辅助（kimi B-1）。NIC 口径带 **~1 s latch 量子**（handoff §D-6）⇒ 本件只把 NIC 当量级见证；窗长按 rate 轮「累计采样窗」累加 ≥30 s。

## §2 身份与 PCIe（原始件 = §0.2 烧录日志）

| # | 判据 | 期望 | 实测（逐字） |
|---|---|---|---|
| 1 | PCIe 桥窗 | 厂商 1M → 我们 2M | before `size=1M` → after `size=2M`（根端口级 remove+rescan 一次成功） |
| 2 | BARs | 2 | `Region 0 [size=1M]` + `Region 1 [size=64K]`；dmesg `identify_bars: 2 BARs: config 1, user 0` |
| 3 | LnkSta | x4 | `Speed 5GT/s (downgraded), Width x4` |
| 4 | `0x00` MAGIC | `0x50360001` | `0x50360001` |
| 5 | **`0x04` BID** | **`0x00000024`** | **`0x00000024`**（`ID_OK / ID_RC=0`） |
| 6 | `0x14` MARKER | `0xdeadbeef` | `0xdeadbeef` |
| 7 | `0x14C` 未实现 | `0xffffffff` | `0xffffffff` |
| 8 | 71 字窗 | NFF=0 | `WINDOW_SCAN_NFF=0` |
| 9 | 烧后清零 | 全 0 | `0x08=0` · `MIR_STATUS=0x00200000`(ver=4/cap=0) · `MIR_CTRL=0` · `MIR_DMA_CNT=0` |
| 10 | 解除停流后链路 | carrier=1 | `NIC_CARRIER=1 / up / Speed: 10000Mb/s / Link detected: yes` |

**环境前置（`runs/ENV_PRE_*.txt`）**：`192.168.100.100/32` UP · `ip route get 192.168.100.2` ⇒ **dev enp1s0f1np1**（非 WiFi）· `CARRIER=1` · nmcli `10 (unmanaged)` · `Adaptive RX: off / rx-usecs: 0`。

## §3 行为套件逐臂读数（原始 stdout 摘录；全文见 `runs/`）

### 5a 干净抓取（P2A：K=1,048,576 paylen 1472；P2B：K=1,505,280 paylen 1470 —— 0x23 轮同构型）

**P2A 逐字（`runs/ARM_P2A_raw_*.txt`）**：`MIR_ID … bid=00000024 (exp 00000024)` · `MIR_STREAM_DONE pc=1048576 reads=1 partial=0 nonmul64=0 short=0 ended_early=0 read_error=0 secs=2.482` · `MIR_STREAM_ACCT pc=1048576 taken_bytes=1048576 dW70=0` · `式A -> 0 closed_a=1` · `式B -> 0 closed_b=1` · `QUIESCE level_end=0 quiesced=1 premise_level0=1` · `MIR_VERIFY rc=0 first_mismatch=-1` · W11 `0 → 0x100000`；`PIN_CPU=1`。
**P2B 逐字**：同形全绿（`reads=2 partial=0 short=0` · `pc=taken=1505280` · `dW70=0` · 式A=式B=0 · `rc=0 fm=-1`；`PIN_CPU=7`）。
⚠️ **0x23 轮 P2B 首跑曾红一次**（`ΔW70=3314` ⇒ read#2 10 s 超时；登记为概率性形态）——本轮 P2B **首跑即全绿（n=1，未复现该形态）**。

**离线逐字节复算（独立 LFSR；`runs/ANALYZE_P2{A,B}.txt`，两跑 rc=0）**：SELFTEST 两向量 OK；**恒等假设 `first_mismatch=-1 / mism=0`**（P2A 1,048,576 B / P2B 1,505,280 B）；6 个候选失配形态各 99.60–99.62% 失配（假设被**判别**）；**车道发现 = `[0..15]` 恒等，16/16 唯一且 100% 命中**。

### 5b URAM 收益主臂（单源 11 窗 S0–S10 · 4 源 10 窗 F0–F9；K=1 GiB/窗 · chunk 4 MiB · `--dual 2` · unpaced · `--no-verify`）

**构型见证**（逐窗，`runs/WIN_*.txt`）：`TOOL_ARGS: --bid 0x00000024 --bytes 1073741824 --stream --src udp --pat-off 0 --buf-mb 1024 --sample-ms 1000 --settle 0.3 --seconds 6 --readlog 1 --chunk 4194304 --dual 2 --no-verify`（FIXOFF=0 生效）；源 `PIN_CPU` 全程在位（`{1:×1, 4:×12, 7:×44}`——**核号逐跑现取、非常量**）；读侧亲和外部见证 `READER_CPUS_ALLOWED Cpus_allowed_list: 0-7`（未绑）。

**逐窗主读数（ACCT 差分；`runs/STATS_SINGLE.txt` / `runs/STATS_FOURSRC.txt`）**：

| 臂 | 窗数 | Σ ΔW70 | 逐窗（十进制 MB，原序） | 中位 | 均值 | 极差 | Σ w_read | Σ w_src |
|---|---|---|---|---|---|---|---|---|
| 单源 | 11 | 36.85 MB (36,845,912 B) | 2.74/5.71/1.70/9.81/1.17/8.38/0.84/2.51/2.41/0.58/1.01 | **2.41 MB** (2,414,504 B) | 3.35 MB | 0.58–9.81 | **39.5 s** | **32.6 s** |
| 4 源 | 10 | 62.27 MB (62,267,240 B) | 5.27/7.33/5.27/7.70/8.25/4.40/5.26/5.92/6.06/6.80 | **5.99 MB** (5,989,288 B) | 6.23 MB | 4.40–8.25 | **38.0 s** | **31.5 s** |

（w_read = 末条 READLOG `t` ≈ 收数跨度；w_src = `TE−TS` 源活跃跨度；**两臂双口径均 ≥30 s**。）
**每窗终态**：式B `res=0 closed_b=1` **21/21 窗全中**（终态排空 ⇒ 缓冲占用归 0）；式A 残差 10,352–3,988,588 B（宿主末段在飞，**按设计红**）。
**单窗逐字（S0 摘）**：`MIR_STREAM_DONE pc=1069547520 reads=255 … read_error=0` · `MIR_STREAM_ACCT pc=1069547520 taken_bytes=1071001688 dW70=2740136` · `式B -> 0 closed_b=1` · `QUIESCE level_end=0 quiesced=1 premise_level0=1`。
**辅助 READLOG（含 kimi B-1 竞态，`runs/READLOG_ANALYZE_AUX.txt`）**：S0 `entry 184.0 MB/s · read_us 中位 22,811.5 µs · gap 0.2 · mmio 5.7`；F0 `174.1 / 24,193.5 / 0.2 / 5.9`；CAPD24 `183.4 / 22,921.2 / 0.2 / 5.8`。
**背景条件见证**：收尾 ① 段 NIC `+2,455,472,778 B/2 s = 9.82 Gbps`、`+1,617,571 帧/2 s = 808,786 fps` ⇒ 全轮测量在**板 TX 侧 9.5 Gbps 泛洪**背景下取得（与 hostread 轮环境同档）。

### 5c 内容臂 CAPD24（K=256 MiB · chunk 4 MiB · `--dual 2` · **verify 开** · auto OFF=1,076,295,680）

**工具行（`runs/WIN_CAPD24_*.txt`）**：`pc=264241152 reads=63` · `ΔW70=769,704`（0.29%）· `式B=0` · **`MIR_VERIFY rc=1 first_mismatch=4,229,208`** · bin 留对端（264,241,152 B，md5 `d348cd49fccb3c408b28da78a6a98305`）。
**独立复算（`runs/ANALYZE_CAPD24*.txt`；跳跃版 LFSR，自检 + 与慢版 11 点对照见 `runs/PATTERN_JUMP_SELFTEST.txt`）**：
- **首洞 = 绝对 4,229,208，删除长度 L = 39,608 B（16B 窗口唯一候选 + 64 KiB 验证）**；洞前 [3,180,632, 4,229,208) 0 失配；**洞后 3.1 MB 位移 L 后 0 失配**；洞边界 16 B dump 逐字吻合（前=无位移、后=位移 L）。
- **多洞结构（新观测）**：洞起点**全部落在「4 MiB 读块 + 34,904」相位**——4 个独立点实测全中（4,229,208 / 16,812,120 / 67,143,768 / 201,361,496）；另一洞长实测 **2,368 B**（16,812,120 处）；80 MiB 区 64 KiB 探针**全净**（非每块有洞）。
- **累计位移曲线 S(P)**（各点唯一候选 + 64 KiB 验证）：16 MiB → 61,992 · 64 MiB → 171,944 · 128 MiB → 372,648 · 192 MiB → 604,840 · **251 MiB → 759,488**（≈ 全窗 ΔW70 769,704 − 10,216 = 末段未捕获部分）。

### 5d D4 停流链（S3D4/S4D4/S5D4 + 停流探针；`runs/ARM_D4_CHAIN_*.txt` + `runs/STOP_PROBE_S5D4_*.txt`）

| 跑 | 构造 | pc / taken | 式A | 式B | 读短尾 |
|---|---|---|---|---|---|
| S3D4 | K=1,048,576 / 源交付 1,048,584 | 1048576 / **1048584** | **8** | 0 | — |
| S4D4 | 抓=源=1,048,576（起测 clr） | 1048576 / 1048576 | **0** | 0 | — |
| S5D4 | 再留残拍 | 1048576 / **1048584** | **8** | 0 | ↓ |
| 停流探针 | `MIR_CTRL=0x8`（bit1=0 无 clr） | — | — | — | **`dma_from_device -s 8` ⇒ TAIL_RC=0 ELAPSED=0** |

- **TAIL 内容逐字节 MATCH**：`got 23 b9 0e 8c a6 5b d3 20 == EXPECT`（= 图案[OFF+K..+8) ^ 0xA5，独立复算 `runs/D4_EXPECT_HEX.txt`）⇒ **0x24 上复现「停流 8/8 RC=0」口径**（含 clr 丢弃残拍：S4D4 起测首部**无**残拍、式A=0）。
- 停流前后：`MIR_STATUS 0x00240000(cap=1,level=0) → 0x00200000(cap=0,level=0)`；`MIR_DMA_CNT` 不变；读后 level=0。读回 `MIR_CTRL=0x0000000a`（= 所写 0x8 + bit1 奇偶位读语义，**非**功能位——同 handoff §B 口径）。
- dmesg 无新增停流相关报错（仅既知族：一次 `transfer_abort` @2518.6 = 早前主臂收尾尾读产物 + 收尾 2× `sfc link down`）。

## §4 URAM 收益对比（跨会话基线；口径钉死）

| 臂 | 0x23 基线（无 URAM，hostread §4，**每臂 n=1 窗**） | 0x24 本件（URAM 32.8 KB，n=11 / n=10） | 观测 |
|---|---|---|---|
| 单源 ΔW70 | **5.46 MB**（A1；A1N2=5.46 亦同） | 中位 **2.41 MB** / 均值 3.35 MB（0.58–9.81） | 中位 **−56%** / 均值 −39% |
| 4 源 ΔW70 | **8.93 MB**（A4） | 中位 **5.99 MB** / 均值 6.23 MB（4.40–8.25） | 中位 **−33%** / 均值 −30% |
| 丢率（Σ/K） | 单源 0.51% / 4 源 0.83% | **单源 0.31%（11 GiB）/ 4 源 0.58%（10 GiB）** | — |
| 每读管线上限（内容臂） | 首洞相位 = 4 MiB + **2,104**（hostread 已知管线量算式 2048+24+32） | 首洞相位 = 4 MiB + **34,904** = 2,104 + **32,800**（URAM 载荷容量，4 点全中） | **洞起点被推迟恰 = 缓冲容量** |
| 首洞长度 | 42,952 B（CAPD） | **39,608 B**（CAPD24）；另一洞 2,368 B | 首洞 −7.8% |

- ⚠️ **跨会话口径（必须随数引用）**：0x23 基线测于 hostread 轮（不同会话；该轮每臂 n=1 无散布统计）；0x24 为本件多窗分布。**散布远大于两代中位差**（0x24 单源极差 0.58–9.81 MB）⇒ 可写「**中位/均值低于基线**」为观测，**单窗对单窗不可判**。
- ⭐ **O（缓冲占用）**：① **终态 = 0**：21/21 窗式B `res=0 closed_b=1` + `level_end=0/quiesced=1`（终态排空后归零，正面读数）。② **中途实测见证**：洞起相位 34,904 = 2,104 + 32,800 ⇒ 洞开始那一刻缓冲**恰装满**（O=32,800 = 设计登记上限 4,100 字；4 点全中）。③ ⛔ **派生尝试不可用（如实登记）**：以 READLOG `Σ(ddma×4+dw70) − dma×4` 推 O 序列，得中位 ≈ ΔW70 总额、离群至 533 MB（≫ 结构上界 32.8 KB）⇒ 该派生口径有缺陷（叠加 kimi B-1 竞态与基线/单位问题），**本件不用它下任何结论**；缓冲水位仍**无直接观测口**（`dbg_occ/dbg_oocc` 空接）。

## §5 未竟项（⛔ 不许当已答）

1. **sha256 转抄差异**：散文四件（REPORT/PROGRESS/HANDOFF/台账）里的 `e` 值**未改**（本件只登记 + 全文回传）——是否统一订正归**判据所有者/文档所有者**。（⚠️ TL 注：**已由 TL 就地订正**，见本件顶部落盘说明。）
2. **URAM 收益不可单窗归因**：跨会话 + 0x23 基线 n=1 ⇒ 「URAM 生效 ⇒ 丢字节降」只到**分布级观测**；同会话 A/B（0x24 内关缓冲）**结构上不可做**（无 bypass 控制）。
3. **O 的中途口径**：② 的「洞起相位」是**间接**见证；READLOG 派生 ③ **不可用**已登记；若要直接读数需加观测口（会改窗口几何，属另一轮）。
4. **多洞机理未定位**：洞相位 ≡ 4 MiB+34,904（4 点）与「80 MiB 区全净」并列已登记；**洞为何落在该相位、哪些块有洞、洞长分布**均未回答（0x23 侧成因也未定位，且 0x23 基线只有首洞口径）。
5. **kimi B-1（READLOG 行级竞态）** 修复与否 = 工具轮的事；本件全部 READLOG 派生量按「辅助」读。
6. **本件自伤登记（3 处，均已修）**：① `hole_finder` v1 的 L 搜索缺探针偏移 ⇒ 假「16 B 洞」（v1 输出改名 `*_V1_OFFSET-BUG.txt` 留档）；② v2 细化循环方向写反（向左）⇒ 假洞@片首（同轮修，见 `_tools/hole_finder.py` 内登记）；③ `win_stats.py` O 公式漏 ×4（修后仍不可用，见 §4-③）。
7. **未跑**：`--src tcp` · H2C · `--aio` · `--buf-huge` · 双工具同配置二次重跑散布臂 · `W57/W58` · 长时窗（本件最长 ~4.6 s/窗）· 0x23 位流回烧对照（跨会话已够，未做回烧）。
8. **0x23 侧多洞结构未回查**：本件对 0x23 的引用一律限「首洞位置/长度」两个既有记录值。

## §6 收尾（原始件 `runs/FINAL_STATE_*.txt`；板上留 `0x24` + 受控停流）

`BID=0x00000024` · `SCRATCH_0x08=0x00000002`（受控停流）· `MIR_CTRL` 读回 `0x00000002`（**功能位全 0**，bit1=奇偶位读语义）· `MIR_STATUS=0x00200000`（cap=0/level=0）· `MIR_DMA_CNT=0x00040002` · `UNIMPL_0x14C=0xffffffff` · 停流后 `CARRIER=0 / Link detected: no`、NIC 两读**逐字冻结**（`1075029181146 / 708187952`）· **无残留进程** · `/tmp/p7b_biz` 四件 md5 **逐字未变** · 恢复配方 = `reg_rw /dev/xdma0_user 0x08 w 0x0`。

## §7 原始件清单（`runs/` 42 件 + `_tools/` 9 件 + `burn/` 3 件；`SHA256SUMS.txt` 56 件自核）

- 烧录：`burn/BURN_0x24_20261013_220442.txt` · `burn/BURN_stdout_copy_20261013_220707.txt` · `burn/wrapper_p4_0x24.bit`
- 窗协议：`runs/WIN_{S0,S1_S5,S6_S10,F0,F1_F5,F6_F9,CAPD24}_*.txt` · `ARM_P2A_raw_*.txt` · `ARM_P2B_raw_*.txt` · `ARM_D4_CHAIN_*.txt` · `STOP_PROBE_S5D4_*.txt`
- 离线复算：`ANALYZE_P2{A,B}.txt` · `ANALYZE_CAPD24.txt` · `ANALYZE_CAPD24_HOLES_*_V2.txt`（+2 件 `*_V1_OFFSET-BUG.txt` 留档）· `ANALYZE_CAPD24_SHIFTSCAN.txt` · `PATTERN_JUMP_SELFTEST.txt` · `D4_EXPECT_HEX.txt` · `STATS_{SINGLE,FOURSRC}.txt` · `READLOG_ANALYZE_AUX.txt`
- 抓样：`runs/mir_P2A.bin` · `mir_P2B.bin` · `capd_{head,sliceA,tail,p16M…p80M1}.bin`（对端全量 bin = `/tmp/p9_board_0x24/mir_CAPD24.bin`，md5 `d348cd49fccb3c408b28da78a6a98305`）
- 环境/收尾：`runs/ENV_PRE_*.txt` · `runs/FINAL_STATE_*.txt` · `_tools/`（脚本 + 分析器；`byteorder_analyze.py` 承 0x23 轮原件 md5 `903fbf15…`）

*本件 = 板级轮读数与登记；判据层 PASS/FAIL 裁定权在判据所有者（用户）。「未观测到」不写「不存在」。*
