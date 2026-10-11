# P8 板级 A/B 轮报告 —— 位流 `0x21`（STG 相位鲁棒暂存）两臂 A/B（唯一变量 = UDP 载荷长度）

> **边界声明**：只烧归档副本（JTAG 易失，**未写 QSPI**）；**未改** `rtl/` · `tb/` · `board/wrapper_p4.v`（0x21 位流的冻结源，全程只读）；
> **未改任何工具源码**（对端工具 = 冻结件，md5 逐字核对；p7b_snap.sh 用的是**构建轮已同步到 0x21 的仓库现树件**，只用不改）；
> 未动 `/tmp/p7b_biz/`（现役，部署前后两次复读 md5 逐字相同）与 `/tmp/p8_board/`、`/tmp/p8_board_0x20/`（只读核对，未改）；
> 未碰 `D:\repo\perfv`；git 只读（未提交）；口令只作 `--sudo` 前缀、未落盘。
> **本报告不下 PASS/FAIL 裁定**；"未观测到"一律写成"未观测到"，不写成"不存在"；不写"时序已解决"。

## 0. 一句话结论（观测，非裁定）

**两臂都以"零丢失 + 逐字节干净 + 账目逐位闭合"收口，且是【板级实测】**：
- **臂 B（`--paylen 1470`，逐帧相位 6；⭐ 正臂）**：`MIR_VERIFY rc=0 / first_mismatch=-1 of 1,505,280`、**`ΔW70 == 0`**、抓取 **1,505,280 B == K**（两跑 B1/B2 同形）；离线独立复算 `mism_bytes=0`（全 K 逐字节）。
  与 0x20 同位对照：0x20 时同样两跑 = `rc=1 / first_mismatch=1478 / ΔW70=750,882 B (49.883%) / 抓取 754,392 B / 离线 mism_bytes≈750k`。
- **臂 A（`--paylen 1472`，相位 0；回归臂）**：`rc=0 / first_mismatch=-1`、`ΔW70 == 0`、抓取 1,048,576 B == K（A1/A2 同形）——与 0x20 位流下的臂 A 逐项同形（**无回归**）。
- **字节账（新口径：残余 = `acc_cnt_r + stg_cnt` ∈ [0,24] B）**：五跑（含 1 次附带跑）全部 `pc + ΔW70 + 残余 == ΔW11` 且 **残余 = 0**（K ≡ 0 mod 8 且无丢时的期望值）⇒ **逐位闭合**。
- 板侧自己的内容校验器 **`ΔW13 ≡ 0`（四跑全）**；抓取流与"图案 LFSR 独立复算 ^0xA5"**逐字节全等（五件）**。

## 1. 与派单描述不符/需细化的点（如实报，未迁就）

1. **"工具侧不建恒等式"需限定到路径**：`p7b_mir_dump.cpp` 的**逐字现读**（`:587`）确实有一条 `MIR_ACCT dW11=… dW70=… pc_bytes=… (want: (pc+dW70)==dW11)` —— 但它只在 **user-BAR（非 `--dma`）路径**打印；本轮两臂都走 `--dma`（C2H 环路径），该行**不出现**（`:556-568` 段只打 `MIR_DMA_DONE/ACCT/NOTE/VERIFY`）⇒ **对本次构型，派单这句成立**；恒等式确由离线复算补（§5）。
2. **`--paylen 1470` 的相位口径**：1470 = 183×8 + 6 ⇒ 帧尾为 6 B 部分拍（相位 6）——与派单"相位 6"一致；**相位本身是合同语义**，本轮判别式只用 `ΔW70` 与抓取字节数（§5），不把流的相位当缺陷。
3. **派单的负对照（0x20 的 750,882 B）未在本轮重测**（派单明示不需要）——本报告引用它时一律标注来源 = `p8_board_0x20_20261011/REPORT.md` §3/§4，并**与它做同位对打**（§5 表）。
4. **附带跑 run0（如实登记）**：首跑（臂 A 参数）在**本机 stdout 转发**时因 `PYTHONIOENCODING` 未设而撞 GBK `UnicodeEncodeError` ⇒ **stdout 流中断**；远端其实已完整跑完，`mir/log/src` 三件已成并已归档（`runs/mir_A1_run0.bin` + 对端 `mir_A1_run0.{bin,log}`、`src_A1_run0.log`）。它的**工具/发端日志是原始件**、`ΔW11`（0→1,048,576）与 `ΔW70`（=0，由相邻快照读出）可从邻跑快照复算 ⇒ 已纳入离线复算与字节账（§4/§5），但**不计入"每臂两跑"的编制**（它没有一次成文的原始 stdout）。
5. **`MIR_CTRL` 读回含"clr toggle 状态位"**：收尾写 `0x0` 后读回 `0x00000002`。RTL 现读（`_proj_pcie/rtl/axi_regs.v:269`）= `if (wdata_r[1]) mir_ctrl_r[1] <= ~mir_ctrl_r[1];` ⇒ **bit1 是翻转位**，本次会话共 5 次武装（5 次 clr 写）⇒ 回读 = 1。**语义上 `cap_en=0 / dma_en=0`（= 冻结）确实达成**；这不是"写 0 没生效"。
6. **直读 `0xCC/0x70` 是陈旧锁存值**（复现既有登记）：收尾时直读两次 2 s 差分**逐字不动**，而**触发式**读（`p7b_snap.sh pair`）显示 `W43`/`W20` 照跑 ⇒ 快照字一律走触发式取数器。

## 2. 烧录与身份（原始读数）

**位流**：`_proj_10g/notes/p8_build_0x21/wrapper_p4.bit`，sha256 **`fbb6fca81076a28b80fcc7a794de698c4253cc36961b7b682887818e1514892c`**（15,431,261 B）——与派单值**逐字相同**；只烧本目录副本 `burn/wrapper_p4_0x21.bit`（烧前双核 sha256 逐字相同）。

**烧录判据（5 条，原始件 `burn/BURN_0x21_*.txt` + `BURN_0x21_stdout_copy_*`）**：`End of startup status: HIGH` · 非注释行 `TCPREG_PROG_DONE` · 位流路径匹配（stdout 含 `wrapper_p4_0x21.bit`）· stdout 新鲜（mtime `1791717614 ≥ T0=1791717481`）· 无 `TCPREG-ABORT`。烧前板侧 `0x04 = 0x00000020`（= 上轮的 0x20，与派单一致）。

**设备级 `remove`+`rescan` 后身份五判据（逐条）**：

| # | 判据 | 期望 | 实测（原始行） |
|---|---|---|---|
| 1 | `0x04` = 本构建 BID | `0x00000021` | `ID_BID 0x00000021 (want 0x00000021)`；直读 `BID_0x04=…: 0x00000021` |
| 2 | 71 字窗口（0x20..0x138） | 全可读、无别名 | `WINDOW_SCAN_NFF=0`（71 字逐字扫，无 `0xffffffff`） |
| 3 | 未实现地址 `0x14C` | `0xffffffff` | `ID_UNIMPL 0xffffffff (want 0xffffffff)`；直读同值 |
| 4 | `LnkSta` | x4 | `LnkSta: Speed 5GT/s (downgraded), Width x4` |
| 5 | 2 BARs | Region 0 (1M) + Region 1 (64K) | `Region 0: …[size=1M]` / `Region 1: …[size=64K]`；dmesg `xdma:identify_bars: 2 BARs: config 1, user 0, bypass -1` |

另：`ID_MAGIC 0x50360001` · `ID_MARKER 0xdeadbeef` · `ID_OK`（`ID_RC=0`）。
**烧后清零核对**：`W11 = W13 = W70 = 0` ✓ · `MIR_CTRL = 0`（cap_en=0）✓ · `MIR_DMA_CNT = 0` ✓ · `SCRATCH_0x08 = 0`（⇒ 板上 TX 使能、carrier=1）✓ · `MIR_STATUS = 0x00180000`（ver=3 / cap=0 / any_drop=0 / unf=0 / level=0）✓。

**对端部署（本轮新目录；现役与历史目录均一字未动）**：`/tmp/p8_board_0x21/` ← `p7b_mir_dump` md5 `25af63df72993195469761d167005533` · `p7b_udp_src` md5 `e0d4da5834cb95d67afb0cc523d1f92f`（= 上一轮 0x20 用的同一件 ⇒ **逐跑可直接对打**）· `p7b_snap.sh` md5 `15eb5384d188a31eeaa40529aff28858`（= **仓库现树 0x21 同步件**）· `p7b_pattern.h` `b2f2e962…` · `p7b_affinity.h` `b0322279…` · `run_arm.sh` `b09ba1d4…`（本轮 `_tools/` 件）。仓库侧源码 md5 现核：`p7b_mir_dump.cpp` `4a8e91f7…` / `p7b_udp_src.cpp` `f5ff3172…`（与 /tmp/p8_board 的部署件同源）。
⚠️ **部署坑（登记）**：`peer_ssh.py --put` 的**本地**参数必须 Windows 式（`D:/…`）且须 `MSYS_NO_PATHCONV=1`；否则远端路径被 MSYS 改写 ⇒ 远端报 `FileNotFoundError`。

## 3. 两臂协议与原始读数

**协议（两臂逐字相同，唯一变量 = `--paylen`）**：起测前取**触发式**快照拿 `W11` ⇒ **`OFF := W11`**（`OFF=auto`）⇒ 先起 `p7b_mir_dump --bid 0x21 --bytes K --dma --src udp --pat-off $OFF --seconds 40`（内部走 clr+cap_en+dma_en 起测协议）⇒ `sleep 2` ⇒ 起 `p7b_udp_src --host 192.168.100.2 --port 8081 --bytes K --mbps 20 --batch 1 --paylen P --off $OFF` ⇒ 等收口 ⇒ 快照(after)。
⚠️ **直读快照字会读到陈旧锁存值**（本轮复现）⇒ 一切快照字一律走 `p7b_snap.sh`（触发新锁存、自证 gen+1）。

| 跑 | paylen | K | 帧数（src 自报） | OFF | 发端读数（原始） | `PIN_CPU` |
|---|---|---|---|---|---|---|
| A0(run0) | 1472 | 1,048,576 | 713（末帧 512 B） | 0 | `pkts=713 pay_bytes=1048576 dur_s=0.475 pps=1502 pay_Mbps=17.673 wire_Mbps=18.178 off_start=0 off_end=1048576 call_errors=0 poll_tmo=0` | **5** |
| A1 | 1472 | 1,048,576 | 713 | 1,048,576 | `pkts=713 pay_bytes=1048576 dur_s=0.475 pps=1500 pay_Mbps=17.651 wire_Mbps=18.155 off_start=1048576 off_end=2097152 call_errors=0 poll_tmo=0` | **5** |
| A2 | 1472 | 1,048,576 | 713 | 2,097,152 | `pkts=713 pay_bytes=1048576 dur_s=0.473 pps=1507 pay_Mbps=17.734 wire_Mbps=18.240 off_start=2097152 off_end=3145728 call_errors=0 poll_tmo=0` | **5** |
| B1 | 1470 | 1,505,280 | 1024（全部整帧） | 3,145,728 | `pkts=1024 pay_bytes=1505280 dur_s=0.682 pps=1501 pay_Mbps=17.650 wire_Mbps=18.154 off_start=3145728 off_end=4651008 call_errors=0 poll_tmo=0` | **5** |
| B2 | 1470 | 1,505,280 | 1024 | 4,651,008 | `pkts=1024 pay_bytes=1505280 dur_s=0.682 pps=1501 pay_Mbps=17.651 wire_Mbps=18.155 off_start=4651008 off_end=6156288 call_errors=0 poll_tmo=0` | **5** |

（`PIN_CPU=` 见证行五跑全在位，`PIN_RULE=avoid-nic` / `PIN_ALLOWED_MASK=20`（= 1<<5），与本轮早前记录同取核 5；发端 pace 参数 = `--mbps 20`（两臂同值，非本轮判据，照录）。）

**工具原始读数（逐字，`runs/ARM_{A1,A2,B1,B2}_raw.txt` + run0 的 `mir_A1_run0.log`/`src_A1_run0.log`）**：

| 跑 | `MIR_VERIFY` | `MIR_DMA_DONE` | `MIR_DMA_ACCT` | `ΔW11` | **`ΔW70`** | `ΔW13` |
|---|---|---|---|---|---|---|
| A0(run0) | `rc=0 first_mismatch=-1 of 1048576 (pat_off_eff=0)` | `bytes=1048576 words=262144 secs=2.476` | `cnt0=0 cnt1=262144 lag_max=608 clobber=0 short_reads=0` | 1,048,576 (=K) | **0** | 0 |
| A1 | `rc=0 first_mismatch=-1 of 1048576 (pat_off_eff=1048576)` | `bytes=1048576 words=262144 secs=2.479` | `cnt0=0 cnt1=262144 lag_max=1522 clobber=0 short_reads=0` | 1,048,576 (=K) | **0** | 0 |
| A2 | `rc=0 first_mismatch=-1 of 1048576 (pat_off_eff=2097152)` | `bytes=1048576 words=262144 secs=2.479` | `cnt0=0 cnt1=262144 lag_max=1104 clobber=0 short_reads=0` | 1,048,576 (=K) | **0** | 0 |
| B1 | `rc=0 first_mismatch=-1 of 1505280 (pat_off_eff=3145728)` | `bytes=1505280 words=376320 secs=2.690` | `cnt0=0 cnt1=376320 lag_max=736 clobber=0 short_reads=0` | 1,505,280 (=K) | **0** | 0 |
| B2 | `rc=0 first_mismatch=-1 of 1505280 (pat_off_eff=4651008)` | `bytes=1505280 words=376320 secs=2.694` | `cnt0=0 cnt1=376320 lag_max=368 clobber=0 short_reads=0` | 1,505,280 (=K) | **0** | 0 |

- 每跑的 `TOOL_RC=0` / `SRC_RC=0`；每跑工具日志头两行 = `MIR_ID … bid=00000021 (exp 00000021)` + `MIR_UNIMPL addr=14c val=ffffffff`（**逐跑自带身份门与边界门**）。
- `MIR_STATUS`（每跑起测前打印）= `ver=3 src_sel=0 cap=0 any_drop=0 unf=0 level=0`（**五跑全**；`any_drop` 是逐会话 sticky ⇒ 它同时是"上一会话零丢"的独立佐证）。
- ⚠️ `rate_Bps ≈ 423k–560k` **不是带宽读数**（工具的 `MIR_RATE_NOTE` 自述；它是"收口用了几秒"的换算），本报告不把它当速率用。

## 4. 离线逐字节复算（与板上工具**独立**的一条路径）

工具与抓取样全部取回本机（`runs/mir_*.bin`，五件；sftp `--get`，解码长度与工具字节数逐位吻合、对端/本机 md5 逐件相同）。用**逐字副本**的 `_tools/p8_ab_analyze.py`（未改一行）+ `_tools/mir_packer_model.py`，先以 `p7b_pattern.h` 文档里的**自检向量**验证 LFSR 独立复算（`off0..15 = 7f0b02e5…d63f`、`off1460..1467 = 0300422d9b47cac0` **两向量全中**），再逐字节比对 `captured[i]^0xA5 == pattern[pat_off+i]`：

| 跑 | `first_mismatch` | `mism_bytes` | 比对面 |
|---|---|---|---|
| A0(run0) | **−1** | **0** | 1,048,576 / 1,048,576 |
| A1 | **−1** | **0** | 1,048,576 / 1,048,576 |
| A2 | **−1** | **0** | 1,048,576 / 1,048,576 |
| B1 | **−1** | **0** | **1,505,280 / 1,505,280** |
| B2 | **−1** | **0** | **1,505,280 / 1,505,280** |

⇒ **抓取流 = 图案流的逐字节连续段（含 B 臂全 K）**；`first_mismatch` 由两条独立路径给出同值（板侧工具 / 离线复算）。
（说明：0x21 下 `K ≡ 0 mod 8` 且零丢 ⇒ 逐拍模型的写出索引 ≡ 恒等 ⇒ "模型假设"比对退化为与"无丢假设"同一个谓词，故本轮不另立模型检查；模型侧证据在构建轮的 xsim 门 G15–G20。）

## 5. 【观测】vs【期望】vs【对打表】

**期望（派单 + 构建轮 §7-2 的口径）**：0x21 的 STG 修复**就是为消掉** 0x20 在相位 ≠0 时的恒丢失 ⇒ 臂 B 期望 `ΔW70 == 0` + 内容逐字节干净 + 账目闭合；臂 A 期望与 0x20 一致（回归臂）。

| 量 | 0x20（上轮，同位两跑） | **0x21（本轮）** | 结论分类 |
|---|---|---|---|
| 臂 B `ΔW70` | 750,882 / 750,882 B（K 的 49.883%） | **0 / 0** | **观测 = 期望**（消掉） |
| 臂 B 抓取字节 `pc` | 754,392 / 754,392 | **1,505,280 / 1,505,280（= K）** | 观测 = 期望 |
| 臂 B `MIR_VERIFY` | `rc=1 first_mismatch=1478`（工具+离线同值） | **`rc=0 first_mismatch=-1`** | 观测 = 期望 |
| 臂 B 离线 `mism_bytes`（无丢假设） | 750,003 / 749,934 | **0 / 0** | 观测 = 期望 |
| 臂 B 残余（账差额） | 6 B（= 0x20 累加器语义） | **0 B**（新口径 `acc_cnt+stg_cnt`） | 观测 = 期望 |
| 臂 A `ΔW70` / `pc` / `first_mismatch` | 0 / 1,048,576 / −1 | **0 / 1,048,576 / −1** | 观测 = 期望（**无回归**） |
| 四跑 `ΔW13`（板侧校验器） | 0 | **0** | 观测 = 期望 |

**字节账（逐位；离线复算件 = `runs/ACCOUNT_0x21.txt`，工具 `--dma` 路径不打印该式 ⇒ 逐跑自算）**：
- 身份式（0x21 口径）= `pc + ΔW70 + 残余 == ΔW11`，**残余 ≡ `acc_cnt_r + stg_cnt` ∈ [0,24] B**（`p8_mir_stg_20261011/DESIGN.md` §3-11；`K ≡ 0 mod 8` 且无丢 ⇒ 期望残余 = 0）。
- 读数反解：`残余 = K − 8×(64 位 FIFO 字数)`（工具 `words` 是 32 位字数 ⇒ ÷2 即 64 位字数；工具把 FIFO 全排空 ⇒ `8×字数 == pc`，两式同值）。
- **五跑全部**：`ΔW11 == K`、`ΔW70 == 0`、`pc == K`、**残余 == 0**、`cnt1−cnt0 == words (mod 2³²)` ⇒ `pc + ΔW70 + 残余 == ΔW11` **逐位闭合**（`ALL CLOSED`）。
- ⚠️ 本轮 `K`（≤1.5 MB）远未触到 `W70`/`W11` 的 32 位回卷（终值 `W11 = 0x5DF000`）；更大 K 下须按 mod 2³² 读（全局 #55）。

**归属（三条独立读数同指）**：`ΔW13 ≡ 0`（板侧内容校验器，五跑）⇒ 载荷在链路/协议栈上逐字节正确；`pc` 与 `ΔW70` 互补且均 = 期望端值 ⇒ **本轮无任何丢失可归因**；采集侧 `clobber=0 / short_reads=0`（读侧全程跟得上）。
⚠️ **本轮对 0x21 的板级归因 = "0x20 vs 0x21 两个位流整体 A/B"**：位流面唯一已知差异 = `app_rx_mirror` 的 STG 改造 + `BUILD_ID_V`（构建轮 §2/§6 逐条）⇒ 但**未做板级"拆刀臂"**（如 STG 突变位流）⇒ 不写"已单独归因给 STG 那一行 RTL"（见 §7-1）。

## 6. 背景条件（照实登记；四跑全程相同）

- **板上 UDP 泛洪在跑**（烧后 `0x08=0`；臂 A0/A1 的报文让板学到 peer 后即开始）：实测对端 NIC `port_rx_bytes` 2 s 窗差分 **+2,821,013,250 B / +1,858,375 帧**（按几何帧率折算窗长 ≈ 2.296 s ⇒ **≈809k fps / ≈9.8 Gbps**）；`tcpdump -nn -e` 抽 4 帧：`00:0a:35:01:fe:c0 > 00:0f:53:2c:68:01 192.168.100.2.8081 > 192.168.100.100.8081: UDP, length 1472`（= 板的 UDP app 图案泛洪）；板侧触发式读 `ΔW43 ≈ 156.25 MHz × Δt`、`ΔW20 = 1,373,199 帧 / 2.015 s ≈ 682k fps`（同一泛洪的板内见证）。
  ⚠️ 直读 `0xCC/0x70` 得到**陈旧锁存值**（会误读成"泛洪没跑"）——走 `p7b_snap.sh` 后照常推进（复现既有登记）。
- **对端网络面**（每次测量前现取）：`inet 192.168.100.100/32` + `nmcli GENERAL.STATE: 10 (unmanaged)` + `ip route get 192.168.100.2 dev enp1s0f1np1` + `Speed: 10000Mb/s / Link detected: yes`（烧后链路回起）。
- **中断合并 = 本来就是关的**：`Adaptive RX: off / rx-usecs: 0 / rx-usecs-irq: 0`（**未动任何设置**）。
- **残留进程**：两臂前后各扫一次，全程**无** `p7b_*`/`mir_dump`/`udp_src`/`tcpdump`。

## 7. 未定项 / 未观测到（不许当已答）

1. **归因粒度**：本轮的"0x21 消掉相位 6 丢失"是**两个位流整体**的 A/B（0x20 ↔ 0x21），**没有**板级突变/拆刀臂（例如"STG 容量回退到 8 B"的位流）⇒ 板级只能写"0x21 相对 0x20 的这条差异被消掉"，**不写"已单独归因给某一行 RTL"**（拆刀证据目前在 xsim 门 G15–G20 + 7 突变臂，属另一条链）。
2. **只测了两个相位**：板上只跑了相位 0（1472）与相位 6（1470）；相位 1..5 / 7 的**板级**行为**未观测到**（xsim 侧 G17 扫过 1..7，但那不是板级）。
3. **`stg_cnt` 内部状态不可见**：快照窗口里**没有** `stg_cnt`/`acc_cnt_r` 的读数（残余只能从字节账反解，本工况恰为 0）；"正常态 `stg_cnt ≤ 15`"仍是**设计/仿真**结论，板级未直接观测。
4. **run0 的原始 stdout 非一次成文**（§1-4）：它的三件日志是原始件、账目可由邻跑快照复算，但**没有**那一跑自己的 pre/post 快照原始行。
5. **`--paylen 1470` 的逐帧相位 = 合同语义**（不当缺陷）；本轮判别式 = `ΔW70` + 抓取字节数，**不是**流的相位对齐。
6. **工具口径的两处已知偏差未改**（本轮按派单"只报告现象"）：`--bytes` 硬门仍是 `K%4`（不是 RTL 契约的 `K%8`；`K≡4 mod 8` 会被接受、然后在板上表现为**安静的短读**）；读侧/工具的 8 字节对齐未做。本轮两个 K 都是 8 的倍数，未被这两条影响。
7. **H2C 写通道从未激励** · **`clobber` 检测器全程未触发**（五跑 `clobber=0` —— 这是"读侧一直跟得上"的读数，**不是**"检测器有问题"）。
8. **0x20 轮登记的两项未观测仍在**：① "帧内 8 B/拍密集"这条源模型的**直接时间轴见证**仍是未取（ILA/逐拍波形）；② `cap_on` 并入写门的板级可达性未观测到（本轮同样未观测到该序列被激励）。
9. **`rate_Bps` 不是带宽读数**（§3 末）；本轮**不宣称**任何 C2H 带宽数字。
10. **位流面身份门 = 板侧 `0x04` 已实证**（这条 0x21 轮补齐了构建轮 §7-1 的"未做"）；但**时序面**本轮不产生任何裁定（构建读数 `WNS +0.044 / 0/0/0` 原样引用，不写"已解决"）。

## 8. 收尾与对端改动台账（全部可回退）

**板子（最终态）**：`0x08 = 0x00000002`（**受控停流**；实测对端 `CARRIER=0` / `Link detected: no`、停流后 NIC `port_rx_bytes/packets` 两次读**逐字不动**）· `MAGIC=0x50360001` · `BID_0x04=0x00000021` · `UNIMPL_0x14C=0xffffffff` · `MIR_STATUS=0x00180000`（ver=3 / **any_drop=0** / level=0）· **`MIR_CTRL=0x00000002`**（额外写了一次 `0x0` 把采集口置回冻结默认态 ⇒ `cap_en=0`/`dma_en=0`；bit1 = clr toggle 状态，§1-5）· `MIR_DMA_CNT=0x0005BE00=376,320`（B2 的残留读数，冻结）· `W11=0x005DF000=6,156,288`（**五跑 K 之和逐位闭合**：3×1,048,576 + 2×1,505,280）· `W13=0` · `W70=0`。**恢复配方（派单指定）= `reg_rw /dev/xdma0_user 0x08 w 0x0`**。残留进程：无。

| # | 对端改动 | 状态 | 回退 |
|---|---|---|---|
| 1 | 新目录 `/tmp/p8_board_0x21/`（冻结工具 5 件 + `run_arm.sh` + 抓取样/日志 + `mir_A1_run0.*` 归档） | 保留 | `rm -rf /tmp/p8_board_0x21` |
| 2 | `02:00.0` 设备级 `remove`+`rescan`（烧后恢复 PCIe，既定流程） | 生效中 | 再 remove+rescan |
| 3 | `/tmp/p7b_biz/`（现役工具） | **一字未动**（部署前后复读 md5 逐字相同） | — |
| 4 | `/tmp/p8_board/`、`/tmp/p8_board_0x20/`（上两轮部署件） | **一字未动**（只读核对 md5） | — |
| 5 | 未改任何 sysctl / qdisc / coalesce / NetworkManager / nmcli | — | — |
| 6 | 未写板载 QSPI | — | — |

## 9. 文件清单（本目录）

```
PROGRESS.txt · SHA256SUMS.txt
step0_selfcheck.sh + STEP0_selfcheck.txt          (只读自检: 位流 sha / 对端 / 三目录工具 md5 / 网络面 / 现态 / 进程)
deploy_0x21.sh + DEPLOY_0x21_*.txt                (对端部署 + 部署前后 md5 双核; 含 --put 路径坑的订正注释)
burn_0x21.sh + burn/BURN_0x21_*.txt + burn/BURN_0x21_stdout_copy_* + burn/wrapper_p4_0x21.bit (sha fbb6fca8…)
final_state.sh + runs/FINAL_STATE_0x21.txt        (受控停流 + MIR_CTRL=0 + 最终态 + 进程扫描 + 未动复读)
runs/ARM_{A1,A2,B1,B2}_raw.txt                     (四跑原始 stdout，逐字; 含 pre/post 快照 + PIN_CPU 见证 + UDP_SUM)
runs/mir_{A1,A2,B1,B2}.bin + runs/mir_A1_run0.bin  (抓取样; 对端/本机 md5 逐件相同)
runs/ANALYZE_{A1,A2,B1,B2,A1_run0}.txt             (离线逐字节复算: LFSR 独立复算 + ^0xA5)
runs/ACCOUNT_0x21.txt                              (字节账: pc + ΔW70 + 残余 == ΔW11, 五跑全闭合)
runs/BACKGROUND_after_arms.txt                     (泛洪见证: NIC 差分/tcpdump/触发式 W43/W20)
_tools/run_arm.sh（对端跑法; md5 b09ba1d4…）· _tools/p8_ab_analyze.py（逐字副本, 未改）
_tools/mir_packer_model.py（逐字副本; 分析脚本的依赖）
```

*本件 = 读数与证据，不代行裁定；凡"观测 = 期望"均带原始 `MIR_*` / 快照 / 发端行。*
