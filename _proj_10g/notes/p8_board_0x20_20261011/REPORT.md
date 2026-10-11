> ⚠️ **落盘说明（TL 代落盘）**：本 `REPORT.md` 由**板级 A/B agent 全文撰写**，因平台拒写 `.md`（subagent 禁写 report 类文件）⇒ **由 TL 逐字代落盘**，内容未改（已与 agent 回传件逐段核对；落盘动作本身不改任何读数）。
> 原始件全部在**同目录**：`runs/ARM_{A1,A2,B1,B2}_raw.txt` · `runs/mir_*.bin` · `runs/ANALYZE_*.txt` · `runs/FINAL_STATE_0x20.txt` · `burn/` · `_tools/` · `STEP0_selfcheck.txt` · `PROGRESS.txt` · `SHA256SUMS.txt`（38 行）。

# P8 板级 A/B 轮报告 —— 位流 `0x20`（镜像采集侧 8 B/拍修复）两臂 A/B（唯一变量 = UDP 载荷长度）

> **边界声明**：只烧归档副本（JTAG 易失，**未写 QSPI**）；**未改** `rtl/` · `tb/` · `board/wrapper_p4.v`（0x20 位流的冻结源，全程只读）；**未改任何工具源码**（对端用的是上一轮的冻结二进制，md5 逐字核对）；未动 `/tmp/p8_board/`（上一轮部署件，只读核对）；未碰 `D:\repo\perfv`；git 只读（未提交）；口令只作 `--sudo` 前缀、未落盘。
> **本报告不下 PASS/FAIL 裁定**；"未观测到" 一律写成 "未观测到"，不写成 "不存在"；不写"时序已解决"。对端上做过的状态改动逐条可回退，见 §8。

## 0. 一句话结论

**两臂都按各自模型逐字节成立，且是【板级实测】而非推断**：
- **臂 A（`--paylen 1472`，相位 0）**：`MIR_VERIFY rc=0 / first_mismatch=-1`、**`ΔW70 == 0`**、字节账**逐位闭合**（两跑 A1/A2 逐字相同）⇒ **0x20 的 8 B/拍修复在板上成立**（本轮的主演示）。
- **臂 B（`--paylen 1470`，逐帧相位 6）**：`rc=1 / first_mismatch=1478`、**`ΔW70 = 750,882 B = K 的 49.883%`**、抓取 754,392 B —— **三个数与"相位 ≠ 0 ⇒ 帧内密集源每 2 拍吃 1 拍"的逐拍模型逐位相同，且抓取流与模型输出逐字节全等（754,392/754,392，两跑 B1/B2 各一次）** ⇒ **审查件 C2 的模型在板上被证实**（不是"演示失败"，是"模型判决"）。
- **两臂的载荷内容都正确**（板侧自己的校验器 `ΔW13 ≡ 0`，四跑全部）⇒ 臂 B 的丢失**全部发生在镜像采集侧**，**不是**链路/协议栈问题。

## 1. 与派单描述不符的点（如实报，未迁就）

1. **`mismatch_bytes` 不在 `p7b_mir_dump` 的输出里**（派单把它列为本轮判据之一）。工具源码现读（`_proj_pcie/p7b_biz/p7b_mir_dump.cpp:564/589`）只打 `MIR_VERIFY rc=… first_mismatch=… of … (pat_off_eff=…)` —— **没有逐字节失配计数**。⇒ 本轮**失配字节数 = 离线复算**得到（`runs/ANALYZE_{A1,A2,B1,B2}.txt`，与板上工具是两条独立路径）：臂 A = 0 / 臂 B（对"无丢"假设）= 750,003（B1）/ 749,934（B2）。
2. **对端网卡中断合并本来就已是关的**（派单要求"若为 `Adaptive RX on, rx-usecs 60` 则先关掉"）：现场 `Adaptive RX: off / rx-usecs: 0` ⇒ **不需要动**（原始读数见 §6）。**未改任何 coalesce 设置**。
3. **`/tmp/p7b_biz/` 非空、本机与对端均未断电重启**（uptime 1 天 19 小时）⇒ 派单里"重建台架"的分支未触发。本轮**没有**在 `/tmp/p7b_biz/` 里做任何事（只读 md5 核对），另建 `/tmp/p8_board_0x20/` 作本轮部署位。
4. **派单说臂 B "`first_mismatch` 落在第一个被丢的拍（≈ 第一个帧边界之后）"**：实测落在 **1478** = **第 2 帧的第 8..15 字节（第 2 个 8 B 拍）**，不是"第 1 个帧边界"（1470）本身 —— 因为第 1 帧按模型是**相位 0、整帧干净**（实测与模型一致）。这是**细化，不是矛盾**。
5. **`MIR_DMA_DONE ... rate_Bps` 在臂 B 里不是带宽读数**（工具等到 `--seconds` 超时才收口：`secs=40.000 rate_Bps=18860`）—— 它分母是超时窗，不是"板能吐多快"。臂 A 的 `rate_Bps≈423k` 同样是"收口用了 2.48 s"的换算，也**不是**带宽测量。本报告不把它当速率用。

## 2. 烧录与身份（原始读数）

**位流**：`_proj_10g/notes/p8_build_0x20/wrapper_p4.bit` sha256 **`998ff90f31907750f31024d2aa62828a8e08c3cd097b03fc9eb15a82b037d244`**（15,431,261 B）—— 与派单值逐字相同；只烧本目录副本 `burn/wrapper_p4_0x20.bit`（烧前双核 sha256 逐字相同）。

**烧录判据（5 条，原始件 `burn/BURN_0x20_20261011_165045.txt` + `burn_run_console2.txt`）**：`End of startup status: HIGH` · 非注释行 `TCPREG_PROG_DONE` · 位流路径匹配（stdout 含 `wrapper_p4_0x20.bit`）· stdout 新鲜（mtime `1791708830 ≥ T0=1791708697`）· 无 `TCPREG-ABORT`。烧前板侧 `0x04 = 0x0000001f`（= 上轮位流）。
⚠️ **首跑失败并已被判据抓住**：脚本里 `BIT_WIN` 变量被 heredoc 吞成 `...burn$BS`（字面量）⇒ `TCPREG_BIT_EXISTS = 0` + 无 HIGH ⇒ **BURN_FAIL**（板子未被碰）。改成单引号字面路径后一次成功。

**设备级 `remove`+`rescan` 后身份五判据（逐条）**：

| # | 判据 | 期望 | 实测（原始行） |
|---|---|---|---|
| 1 | `0x04` = 本构建 BID | `0x00000020` | `BID_0x04=…: 0x00000020`（`p7b_snap.sh id` 打 `ID_BID 0x00000020 (want 0x00000020)`） |
| 2 | 71 字窗口 | 0x20..0x138 均可读、无别名 | `WINDOW_SCAN_NFF=0`（71 字逐字扫，无 `0xffffffff`） |
| 3 | 未实现地址 `0x14C` | `0xffffffff` | `UNIMPL_0x14C=…: 0xffffffff` |
| 4 | `LnkSta` | x4 | `LnkSta: Speed 5GT/s (downgraded), Width x4` |
| 5 | 2 BARs | Region 0 (1M) + Region 1 (64K) | `Region 0: …[size=1M]` / `Region 1: …[size=64K]`；dmesg `xdma:identify_bars: 2 BARs: config 1, user 0, bypass -1` |

另：`ID_MAGIC 0x50360001` · `ID_MARKER 0xdeadbeef` · `ID_OK`（`ID_RC=0`）；`/dev/xdma0_{user,c2h_0,h2c_0}` 在 16:53 重建；`dmesg: xdma:probe_one: … usr 16, ch 1,1`。
**烧后清零**：`W11 = W13 = W70 = 0`、`MIR_CTRL = 0`（cap_en=0 冻结）、`MIR_DMA_CNT = 0`、`SCRATCH_0x08 = 0`（⇒ 板上 `carrier = 1`）、`MIR_STATUS = 0x00180000`（ver=3 / cap=0 / any_drop=0 / unf=0 / level=0 / src_sel=0）。

**对端部署（新目录，只读的现役目录一字未动）**：`/tmp/p8_board_0x20/` ← `p7b_mir_dump` md5 `25af63df72993195469761d167005533` · `p7b_udp_src` md5 `e0d4da5834cb95d67afb0cc523d1f92f` · `p7b_snap.sh` md5 `5af4c61911a8cc2cb4821456f5c43845` · `p7b_pattern.h` `b2f2e962…` · `p7b_affinity.h` `b0322279…` —— 与上一轮记录的部署件 md5 **逐字相同**（= 冻结工具）。仓库侧源码 md5 亦逐字相同（`p7b_mir_dump.cpp` `4a8e91f7…` / `p7b_udp_src.cpp` `f5ff3172…`）。

## 3. 两臂协议与原始读数

**协议（两臂逐字相同，唯一变量 = `--paylen`）**：起测前取**触发式**快照拿 `W11`（= 板上图案流位置）⇒ **`OFF := W11`**（`OFF=auto`）⇒ 先起 `p7b_mir_dump --bid 0x20 --bytes K --dma --src udp --pat-off $OFF`（内部写 clr+cap_en+dma_en 起测）⇒ `sleep 2` ⇒ 起 `p7b_udp_src --bytes K --mbps 20 --batch 1 --paylen P --off $OFF` ⇒ 等收口 ⇒ 快照(after)。⚠️ **`OFF` 对齐同时满足两条**：板侧校验器 W13 对齐（⇒ `ΔW13` 应为 0）与镜像 `--pat-off` 对齐（⇒ verify 语义成立）。**直读快照字会读到陈旧锁存值**（本轮实测），一切快照字一律走 `p7b_snap.sh`（触发新锁存）。

| 跑 | paylen | K | 帧数 | OFF | 发端读数（原始） | `PIN_CPU` |
|---|---|---|---|---|---|---|
| A1 | 1472 | 1,048,576 | 713（末帧 512 B） | 0 | `pkts=713 pay_bytes=1048576 dur_s=0.477 pps=1495 pay_Mbps=17.591 wire_Mbps=18.094 off_start=0 off_end=1048576 call_errors=0 poll_tmo=0` | **5** |
| B1 | 1470 | 1,505,280 | 1024（全部整帧） | 1,048,576 | `pkts=1024 pay_bytes=1505280 dur_s=0.679 pps=1508 pay_Mbps=17.738 wire_Mbps=18.245 off_start=1048576 off_end=2553856 call_errors=0 poll_tmo=0` | **5** |
| A2 | 1472 | 1,048,576 | 713（末帧 512 B） | 2,553,856 | `pkts=713 pay_bytes=1048576 dur_s=0.475 pps=1502 pay_Mbps=17.676 wire_Mbps=18.181 off_start=2553856 off_end=3602432 call_errors=0 poll_tmo=0` | **5** |
| B2 | 1470 | 1,505,280 | 1024 | 3,602,432 | `pkts=1024 pay_bytes=1505280 dur_s=0.682 pps=1501 pay_Mbps=17.652 wire_Mbps=18.157 off_start=3602432 off_end=5107712 call_errors=0 poll_tmo=0` | **5** |

（`PIN_CPU=5` 行全文含 `PIN_ALLOWED_MASK=20`（= `1<<5`）、`PIN_RULE=avoid-nic`；四跑全部在位 ⇒ 见证有效。发端 pace 参数 = `--mbps 20`（两臂同值）；工具自报 `pay_Mbps ≈ 17.6–17.7`，非本轮判据，照录。）

**工具原始读数（逐字，`runs/ARM_{A1,A2,B1,B2}_raw.txt`）**：

| 跑 | `MIR_VERIFY` | `MIR_DMA_DONE` | `MIR_DMA_ACCT` | `ΔW11` | `ΔW70` | `ΔW13` |
|---|---|---|---|---|---|---|
| A1 | `rc=0 first_mismatch=-1 of 1048576 (pat_off_eff=0)` | `bytes=1048576 words=262144 secs=2.479` | `cnt0=0 cnt1=262144 lag_max=368 clobber=0 short_reads=0` | 1,048,576 (= K) | **0** | 0 |
| B1 | `rc=1 first_mismatch=1478 of 1505280 (pat_off_eff=1048576)`（stderr `FAIL: content mismatch at 1478`） | `bytes=754392 words=188598 secs=40.000` | `cnt0=0 cnt1=188598 lag_max=232 clobber=0 short_reads=0` | 1,505,280 (= K) | **750,882** | 0 |
| A2 | `rc=0 first_mismatch=-1 of 1048576 (pat_off_eff=2553856)` | `bytes=1048576 words=262144 secs=2.481` | `cnt0=0 cnt1=262144 lag_max=368 clobber=0 short_reads=0` | 1,048,576 (= K) | **0** | 0 |
| B2 | `rc=1 first_mismatch=1478 of 1505280 (pat_off_eff=3602432)` | `bytes=754392 words=188598 secs=40.000` | `cnt0=0 cnt1=188598 lag_max=248 clobber=0 short_reads=0` | 1,505,280 (= K) | **750,882** | 0 |

**字节账（逐位）**：
- 臂 A：`pc(1,048,576) + ΔW70(0) == ΔW11(1,048,576)` **恰好闭合**；`cnt1−cnt0` 字数 ×4 = 1,048,576 = 工具读出的字节数 ✓。
- 臂 B：`pc(754,392) + ΔW70(750,882) = 1,505,274 = ΔW11 − 6` —— **差的恰是 6 B 累加器残余**（= RTL 头注释写明的**已知语义**：`K%8` 粒度下尾部 1–7 B 停在累加器、无读出通路；本次残余 6 B 不是"尾部"而是"缺 6 B 才能凑满一个字"——与模型 `acc_end=6` 逐位相同）。`cnt1−cnt0`×4 = 754,392 = 工具读出的字节数 ✓。
- `MIR_STATUS.level=0`（两跑起测前）· `clobber=0` / `short_reads=0`（四跑全部）· `cnt0=0`（clr 后环计数清零，与 `pat_off_eff = pat_off + 4·cnt0` 逐位一致）。

## 4. 离线逐字节复算（与板上工具**独立**的一条路径）

工具与抓取样全部取回本机（1,048,576 B / 754,392 B，四件；base64 传输，解码长度逐位吻合），用本轮自写的 `_tools/p8_ab_analyze.py` 做两条逐字节比对（图案流用 LFSR 独立复算，并以 p7b_pattern.h 文档里的**自检向量**先验证：`off0..15 = 7f0b02e536a14ed61ab049b856add63f`、`off1460..1467 = 0300422d9b47cac0` **两向量全中**）：

| 跑 | ① 无丢假设：`captured[i]^0xA5 == pattern[pat_off+i]` | ② 模型假设：`captured[i]^0xA5 == pattern[pat_off+idx_i]`（idx = 逐拍模型的写出索引） |
|---|---|---|
| A1 | `first_mismatch=-1  mism_bytes=0` / 1,048,576 | `mism_bytes=0` / 1,048,576（**逐字节全等**） |
| A2 | `first_mismatch=-1  mism_bytes=0` / 1,048,576 | `mism_bytes=0` / 1,048,576（**逐字节全等**） |
| B1 | `first_mismatch=1478  mism_bytes=750,003` / 754,392 | **`mism_bytes=0` / 754,392（逐字节全等）** |
| B2 | `first_mismatch=1478  mism_bytes=749,934` / 754,392 | **`mism_bytes=0` / 754,392（逐字节全等）** |

⇒ **臂 B 抓取流 = 模型的输出流，逐字节、含每一处洞的位置**（`(A1→B1) 的 mism_bytes` 差异来自不同 `pat_off` 下的巧合命中数，与结论无关）。**臂 B 的 `first_mismatch=1478` 同时被两条独立路径给出**（板上工具 = 1478；离线 = 1478）。

## 5. 【板级观测】 vs 【模型预测】 vs 【差在哪】

**模型**（= `_tools/mir_packer_model.py`，逐拍复算 `rtl/app_rx_mirror.v:150-250` 的写侧；**与审查件 `p8_mir8b_impl_20261011/REVIEW.md` C2 的模型是同一件事**——本 agent 从 RTL 独立重写）：

- `kk = min(n_cur, 8−acc_cnt)`；本拍搬空（`drain_all`）才接新拍，否则**拒收整拍**（按 popcount 计丢字）；
- 源模型 = **帧内 8 B/拍背靠背**、帧间空闲（定速只拉开数据报之间的间隔；"帧内密集"由上一轮 0x1F 的"恒丢 50%"反推 —— 稀疏源在旧 4 B/拍版本下**不会**丢）。

| 量 | 臂 A 模型 | 臂 A 实测（A1/A2） | 臂 B 模型 | 臂 B 实测（B1/B2） |
|---|---|---|---|---|
| `drop_bytes` | 0 | **0 / 0** | 750,882（49.883%） | **750,882 / 750,882** |
| 抓取字节数 | 1,048,576 | **1,048,576 / 1,048,576** | 754,392 | **754,392 / 754,392** |
| `first_mismatch` | −1 | **−1 / −1** | 1478 | **1478 / 1478** |
| 累加器残余 | 0 | 0（账恰好闭合） | 6 | **6**（`K−(pc+ΔW70)`） |
| 逐字节内容 | 连续图案流 | **逐字节全等** | 模型输出流 | **逐字节全等** |

⇒ **模型与观测"差在哪" = 差 0**（四跑、两个量纲：计数 + 逐字节内容）。**这是"模型级已证 + 板级已测"**，不再是审查件里的"模型级已证 + 板级未测"。

**臂 B 形态（板级可直接读出的）**：第 1 帧（相位 0）整帧干净；从**第 2 帧**起**每 2 拍吃 1 拍**（第 2 帧第 2 个 8 B 拍起被拒收）⇒ 全流丢失率 = `1023×734 / 1,505,280 = 49.883%`。**丢失逐拍位置确定性**（两跑逐字节相同），**不是噪声**。

**归属（三条独立读数同指）**：`ΔW13 ≡ 0`（板侧内容校验器，四跑）⇒ 载荷在链路/协议栈上**逐字节正确**；`ΔW70` 与抓取量互补闭合 ⇒ **丢失 100% 在镜像采集侧**；采集侧唯一丢字节来源（0x20 起）= **拒收类**（§5 模型）。

## 6. 背景条件（照实登记；两臂全程相同）

- **板上泛洪在跑**（继承自上轮末态 `0x08=0` ⇒ `carrier=1`）：四臂全程 `carrier=1`；停流前实测对端 NIC `port_rx_bytes` 2 s 差分 = **+2,455,471,324 B（⇒ ~9.82 Gbps = 1.2277 GB/s）**、`port_rx_packets` **+1,617,571（⇒ ~808,786 pps）**；`tcpdump -nn -e` 抽 6 帧：`00:0a:35:01:fe:c0 > 00:0f:53:2c:68:01 192.168.100.2.8081 > 192.168.100.100.8081: UDP, length 1472`（= 板的 UDP app 图案泛洪）。
  ⚠️ 直读 `0xCC/0x70` 得到**陈旧锁存值**（会误读成"泛洪没跑"）——走 `p7b_snap.sh` 后 `W20/W43` 照常推进。
- **对端网络面**（每次测量前现取）：`inet 192.168.100.100/32` + `nmcli GENERAL.STATE: 10 (unmanaged)` + `ip route get 192.168.100.2 dev enp1s0f1np1` + `neigh 192.168.100.2 lladdr 00:0a:35:01:fe:c0` + `Speed: 10000Mb/s / Link detected: yes`。
- **中断合并 = 本来就是关的**：`Adaptive RX: off / rx-usecs: 0 / rx-usecs-irq: 0`（**未动任何设置**）。
- **残留进程**：四臂前后各扫一次，`PROC_SCAN_DONE` 前**无**任何 `p7b_*`/`mir_dump`/`udp_src`/`tcpdump`。

## 7. 未定项 / 未观测到（不许当已答）

1. **"帧内 8 B/拍密集"这条源模型的直接时间轴见证仍是未取**（ILA/逐拍波形）。它的**可观测后果**已被逐字节全等证实（两处独立量纲），但"逐拍密度本身"仍是**推断**（旁证 = 上轮 0x1F 的恒 50%）。
2. **`cap_on` 并入写门的板级可达性**（0x20 的第二个修复）：本轮**未观测到**该序列被激励（`ΔW70` 全部可由拒收类解释、无重复字签名）—— "未观测到" ≠ "不存在"，与该序列的可达性未证。
3. **小载荷（≤16 B）到不了 app 的阈值**（上轮 §11-3a 登记项）：本轮未扫，原样未定位。
4. **工具口径的两处已知偏差未改**（本轮按派单"只报告现象"）：`--bytes` 硬门仍是 `K%4`（不是 RTL 契约的 `K%8`；`K≡4 mod 8` 会被工具接受、然后在板上表现为**安静的短读**）；读侧/工具的 8 字节对齐未做。本轮两个 K 都是 8 的倍数，未被这两条影响。
5. **H2C 写通道从未激励** · **`clobber` 检测器全程未触发**（四跑 `clobber=0` —— 这是"读侧一直跟得上"的读数，**不是**"检测器有问题"）。
6. **`ΔW70` 的 32 位回卷**：本轮 K 级（≤1.5 MB）远未触到（W70 终值 0x16EA44 = 1,501,764）；更大 K 下须按 mod 2³² 读（全局 #55）。
7. **`MIR_DMA_DONE.rate_Bps` 不是带宽读数**（§1-5）；本轮**不宣称**任何 C2H 带宽数字。
8. **臂 B 的丢失"应该怎么修"** = 审查件 C2 的两条出路（板级 A/B 已做完它要的那一步；真修 = 字节粒度弹性暂存）—— **本轮不做**，属设计件范畴。

## 8. 收尾与对端改动台账（全部可回退）

**板子（最终态）**：`0x08 = 0x00000002`（**受控停流**；实测对端 `CARRIER=0` / `Link detected: no`，停流后 NIC `port_rx_bytes/packets` 两次读**逐字不动**）· `MAGIC=0x50360001` · `BID_0x04=0x00000020` · `UNIMPL_0x14C=0xffffffff` · `MIR_STATUS=0x001e0000`（any_drop=1，臂 B 所致）· **`MIR_CTRL=0x00000000`**（额外写了一次：把采集口置回"冻结"默认态，与上一轮收尾口径一致；⚠️ 该写使 `cap_en=0`/`dma_en=0`，要重新采集须重走 clr→cap_en 协议）· `MIR_DMA_CNT=0x0002E0B6=188,598`（B2 的残留读数，冻结）· `W11=0x004DF000=5,107,712`（四跑 K 之和逐位闭合）· `W13=0` · `W70=0x0016EA44=1,501,764`。**恢复配方（派单指定）= `reg_rw /dev/xdma0_user 0x08 w 0x0`**。残留进程：无。

| # | 对端改动 | 状态 | 回退 |
|---|---|---|---|
| 1 | 新目录 `/tmp/p8_board_0x20/`（冻结工具 5 件 + `run_arm.sh` + 抓取样/日志） | 保留 | `rm -rf /tmp/p8_board_0x20` |
| 2 | `02:00.0` 设备级 `remove`+`rescan`（烧后恢复 PCIe，既定流程） | 生效中 | 再 remove+rescan |
| 3 | `/tmp/p7b_biz/`（现役工具） | **一字未动** | — |
| 4 | `/tmp/p8_board/`（上轮部署件） | **一字未动**（只读核对 md5） | — |
| 5 | 未改任何 sysctl / qdisc / coalesce / NetworkManager / nmcli | — | — |
| 6 | 未写板载 QSPI | — | — |

## 9. 文件清单（本目录）

```
PROGRESS.txt · SHA256SUMS.txt（38 行）
step0_selfcheck.sh + STEP0_selfcheck.txt        （只读自检：位流 sha / 对端 / 工具 md5 / 网络面 / 现态 / 进程）
burn_0x20.sh + burn_run_console2.txt            （烧录；burn_run_console.txt = 首跑失败件，保留为坑证）
burn/wrapper_p4_0x20.bit（sha 998ff90f…d244）· burn/BURN_0x20_*.txt（含失败那次）· burn/BURN_0x20_stdout_copy_*
final_state.sh + runs/FINAL_STATE_0x20.txt      （受控停流 + 最终态 + 进程扫描）
runs/ARM_{A1,A2,B1,B2}_raw.txt                  （四跑原始 stdout，逐字）
runs/mir_{A1,A2,B1,B2}.bin（+ .b64 传输件）      （抓取样；解码长度与工具字节数逐位相同）
runs/ANALYZE_{A1,A2,B1,B2}.txt                  （离线逐字节复算：无丢假设 + 模型假设）
_tools/run_arm.sh（对端跑法；md5 37e5c2e6…）· _tools/mir_packer_model.py · _tools/model_arms.py + MODEL_ARMS.txt
_tools/p8_ab_analyze.py（含 p7b_pattern.h 文档自检向量复核）
```

*本件 = 读数与证据，不代行裁定；凡"成立"结论均带原始 `MIR_*` / 快照 / 发端行。*
