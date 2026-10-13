# p9_toolfix_validate_20261013 — 修复版工具切换 + R1 实窗验证（B-1 修复后的第一条真实 dual 窗）

> **轮次**：2026-10-13 23:21–23:25（+0800）。**工作树** `D:\repo\XCKU5PMini\udp_hls_10g`（未改任何仓内既有文件；本目录 6 件为新增）。
> **边界声明**：**未烧位流、未写 QSPI**；未改 `rtl/**`、`board/**`、`sim/**`、工具源码（两处工具源码均逐字节未动）；板上只做**派单规定的两处写**（`0x08` 解停流 / 复停流）+ `MIR_CTRL=0`。
> 口令 `PEER_PW` 只作命令 env 前缀、**未落盘**（本件全文无口令）。**不下 PASS/FAIL 裁定**；「未观测到」≠「不存在」；判据层裁定权在判据所有者。
> **本次独有串**：`WIN_R1_20261013_232311` · `_selftest_toolfix_20261013_232223` · 板上写时刻 ≈23:22:49（解停流）/ ≈23:23:56（复停流，+0800）。
> ⚠️ 本件由 agent 全文回传、**TL 代落盘**（平台拒写 .md 的已知间歇故障族）。文末「TL 附加」块 = TL 独立抽核记录，非 agent 正文。

## §0 开工核 + 切换记录

### 0.1 开工核（全部现取；23:21–23:22）

| 项 | 读数 | 判据式 |
|---|---|---|
| 对端可达（**TCP 判据，不用 ping 退出码**） | `TCP OPEN 192.168.0.38:22` · `TCP OPEN 192.168.0.38:3121` | 本机 socket.connect |
| 登录 | `a-MS-7850` · `Tue Oct 13 11:21:18 PM CST 2026` · `up 1:46`（boot = 21:34:23，`uptime -s` 现取） | — |
| `hw_server` | `systemctl is-active` = **active**；`ss -lntp` = `LISTEN 0 16 0.0.0.0:3121` | active + 3121 监听 |
| `/tmp/p7b_biz_fix/`（修复版新目录） | `p7b_mir_dump.cpp` = **`464006d9d7dcc5f365f36880ba8f8fc5`**（= 派单期望源 md5）；`p7b_mir_dump` = **`48dcbcb26a4db45f576fc9664638a089`**（108,696 B，= FIX 轮记录） | 逐字命中 |
| 现役 `/tmp/p7b_biz/p7b_mir_dump` | **`7cebded7e9270b6a2d81f5db29843f4d`**（FIX 轮未覆盖，逐字不变） | = 派单期望 |
| 其它现役件 | `p7b_udp_src e0d4da58…` · `p7b_snap.sh 97c66382…` · `/tmp/run_win_hw.sh 7b40bcbb…` · `/tmp/analyze_readlog.py a451b98d…` · `/tmp/p9_rate/p7b_snap.sh 97c66382…` | 与重部署/0x24 轮记录一致 |
| 板侧身份（`reg_rw /dev/xdma0_user`，sudo 只读） | `0x00=0x50360001` · **`0x04=0x00000024`** · `0x08=0x00000002` · `0x14=0xdeadbeef` · `0x13C=0x00200000` · `0x144=0x00000002` · `0x148=0x00040002` · `0x14C=0xffffffff` | 派单 §1：`0x04==0x00000024` ⇒ 命中；`0x08=0x2` = 受控停流态 |
| 板侧网络/进程 | `CARRIER=0 / Link detected: no`；`enp1s0f1np1 DOWN 192.168.100.100/32`；nmcli `10 (unmanaged)`；残留进程扫描 = 空 | 与"0x24 + 受控停流"逐条相符 |

⇒ 开工核与派单前提**逐条相符**（板现态 = `0x24` + 受控停流；修复版在 `/tmp/p7b_biz_fix/`；现役未被覆盖）。

### 0.2 切换现役（23:22:23；对端 user `a`，无需 root）

**操作序列**（`/tmp/p7b_biz/` 内）：`cp -p p7b_mir_dump → p7b_mir_dump.bak_7cebded7`（先备份）→ `cp -p p7b_mir_dump.cpp → p7b_mir_dump.cpp.bak_b4833c55`（**附带项**，见下）→ `cp /tmp/p7b_biz_fix/p7b_mir_dump → p7b_mir_dump`（覆盖为现役）→ `cp /tmp/p7b_biz_fix/p7b_mir_dump.cpp → p7b_mir_dump.cpp`。

| 件 | 切换前 md5 | 切换后 md5 | mtime（full-iso） |
|---|---|---|---|
| `p7b_mir_dump`（现役） | `7cebded7…` | **`48dcbcb26a4db45f576fc9664638a089`** | **`2026-10-13 23:22:23.072966868 +0800`**（本次独有） |
| `p7b_mir_dump.bak_7cebded7` | — | `7cebded7e9270b6a2d81f5db29843f4d` | `2026-10-13 21:43:28.817810576 +0800`（= 原 mtime，`-p` 保留） |
| `p7b_mir_dump.cpp` | `b4833c55…` | **`464006d9d7dcc5f365f36880ba8f8fc5`** | `2026-10-13 23:22:23.073901374 +0800` |
| `p7b_mir_dump.cpp.bak_b4833c55` | — | `b4833c55642120f093fa2ee9e2544aa8` | `2026-10-13 21:42:36.537822352 +0800`（保留） |

⚠️ **附带项登记（超出派单字面，理由 = 源码 ↔ 二进制绑定链）**：派单只要求切二进制；本轮**同批把修复版源码（`464006d9…`）也放进现役目录**、旧源码备份为 `…bak_b4833c55` —— 否则现役目录会呈"二进制 = 修复版 / 源码 = 修复前"的不一致（本仓最忌的静默陷阱）。两处备份都在位，一键回退：`cp p7b_mir_dump.cpp.bak_b4833c55 p7b_mir_dump.cpp`。

**`--selftest`（切换后的现役件，23:22:23–23:22:33）**：`SELFTEST_RC=0`；日志 `/tmp/p7b_biz/_selftest_toolfix_20261013_232223.log`（5,051 B）md5 **`a961402f6b18a69b221121d8839315e3`** —— **与 FIX 轮归档件（`p9_xverify_claude_20261013/_tools/selftest_fix.txt`）逐字节相同**；该字节序列的既有统计 = **52×` OK` / 0×`FAIL` / 末行 `MIR_SELFTEST PASS`**（计数在与对端日志同 md5 的归档件上复算：`grep -o ' OK' | wc -l` = 52、`grep -c FAIL` = 0）。⇒ 期望"52 OK / 0 FAIL"命中，且比"命中"更强：切换后的现役件在 selftest 面**逐字节等于** FIX 轮验证过的那个二进制。

### 0.3 环境前置 + 解停流（23:22:49，sudo）

- `ip link set up` · `ip addr replace 192.168.100.100/32` · `ip route replace 192.168.100.2/32 dev enp1s0f1np1 src 192.168.100.100` · `nmcli device set enp1s0f1np1 managed no` · `ethtool -C enp1s0f1np1 adaptive-rx off rx-usecs 0`。
- 见证：`ip route get 192.168.100.2` ⇒ **`dev enp1s0f1np1`**（非 WiFi）；`nmcli` = `10 (unmanaged)`；`Adaptive RX: off / rx-usecs: 0`（窗口 stdout 内二次见证同款）。
- **解停流**：`reg_rw /dev/xdma0_user 0x08 w 0x0` ⇒ `CARRIER=1 / Link detected: yes / Speed: 10000Mb/s`（3 s 后现取）；`0x08` 读回 `0x00000000`。

## §1 判据（先写后跑；落盘 23:21:53，窗口启动 23:23:11 —— 本目录 `CRITERIA_R1.md` md5 `00f176c6c7fc5a4409100a1127c93234`、分析器 `_tools/r1_readlog_analyze.py` md5 `04cdcb4d9d45274072b98c1f208f6c58`，均**先于**窗口运行）

**窗口构型（与 0x24 板级轮主臂 S0 同构型）**：K=1 GiB · chunk 4 MiB · `--dual 2` · unpaced（源 `--mbps 0`）· `--readlog 1` · `--no-verify` · `--src udp` · SECS=6 · SAMPLE_MS=1000 · BUFMB=1024 · FIXOFF=0（off=0）· NW=71 · EXPECT_BID=0x00000024 · TOOL=`/tmp/p7b_biz/p7b_mir_dump`（切换后现役件）。
**主读数** = `MIR_STREAM_ACCT` 的 **ΔW70**（快照差分口径，不依赖 READLOG ⇒ 对 B-1 类竞态免疫）。

| 判据 | 判定式（跑前定） |
|---|---|
| **R1-a** 行级 uint32 回绕 | 全部 READLOG 行 `dw70 < 2^31`（回绕失效形态 = `2^32−δ`，必 ≥2^31）；附 max/min dw70 形态 |
| **R1-b** 按 `t` 排序链闭合率 | `t` 升序（= 锁内 commit 序）后：首行对 ACCT 基线 `(w70[0]−w70a) mod 2^32 == dw70[0]`、相邻 `(w70[k]−w70[k−1]) mod 2^32 == dw70[k]`（dma/ddma 同款）；**期望 100%**；尾部对账 `err = ΔW70 − Σdw70 − ((w70b−w70_last) mod 2^32) == 0`、`err2`（dma 侧）同 |
| **R1-c** 与主臂并列（单窗，仅形态） | 与 0x24 S0 的 ΔW70=2,740,136 B 及 11 窗分布（0.58–9.81 MB / 中位 2.41 MB）并列登记，不作裁定 |

**运行前标定（分析器有判别力的物证）**：同一分析器跑 0x24 S0 旧工具原文（`runs/CALIB_S0_analyze.txt`）：打印序相邻链 **124/254 不闭合**、按 `t` 排序 **255/255 闭合**、`err=err2=0` ⇒ "链"这一维**不是恒真**；本窗打印序对照数 = 175/254。

## §2 R1 窗三判据读数（原始 stdout 摘录；全文 = `runs/WIN_R1_20261013_232311.txt`，41,845 B，md5 `2bf19f58c5aa6ed80e6fdca4cc56b15e`；对端原件 `/tmp/p9_toolfix/WIN_R1_20261013_232311.txt` 同 md5）

### 2.1 运行见证（逐字摘）

```
TOOL_MD5=48dcbcb26a4db45f576fc9664638a089            ← 现役 = 切换后的修复版（运行期现取）
Adaptive RX: off  TX: n/a rx-usecs:0 …  CARRIER_PRE=1
TOOL_ARGS: --bid 0x00000024 --bytes 1073741824 --stream --src udp --pat-off 0 --buf-mb 1024
           --sample-ms 1000 --settle 0.3 --seconds 6 --readlog 1 --chunk 4194304 --dual 2 --no-verify
MIR_ID magic=50360001 (exp 50360001) bid=00000024 (exp 00000024)
MIR_STREAM_DONE pc=1069547520 reads=255 partial=0 nonmul64=0 short=1 ended_early=1 read_error=0 secs=13.901
MIR_STREAM_ACCT pc=1069547520 taken_bytes=1072154264 dW70=1587560 w70a=99882856 w70b=101470416
                words0=0 words1=268038566 dwords=268038566 K=1073741824
MIR_STREAM_QUIESCE level_end=0 quiesced=1 premise_level0=1 waited_ms=0.0 settle_s=0.30 strict=1
MIR_STREAM_IDA 式A taken−pc=2606744 band=[0,32] closed_a=0     ← 宿主末段在飞，按设计
MIR_STREAM_IDB 式B K−taken−dW70=0 band=[0,24] closed_b=1
MIR_STREAM_WRAP words0=0 words1=268038566 wrap_seen=0 dword_max_step=91227144
MIR_STREAM_GAP first=0 last=2606744 nondecreasing=1 host_miss_pct=0.2431
发端[p1]: PIN_CPU=7 … UDP_SUM pkts=729445 pay_bytes=1073741824 dur_s=2.958 pps=246601
           pay_Mbps=2903.976 call_errors=0 poll_tmo=0 skip_pkts=0
读侧: READER_CPUS_ALLOWED=Cpus_allowed_list:0-7 READER_CPU_START=3 READER_PID=21382
      READER_STAT(末行) utime=9 stime=32 threads=2
```

### 2.2 三判据读数（`runs/ANALYZE_R1.txt` 逐字；255 行 READLOG 全量解析）

| # | 判据 | 期望 | **实测（逐字）** |
|---|---|---|---|
| **R1-a** | 行级 dw70 无 uint32 回绕 | 0 候选 | `dw70 min=0 max=417896`；`wrap_candidates(dw70≥2^31) = 0` |
| **R1-b①** | t 排序链闭合率 100% | 100% | w70 链 **255/255 = 100.0000%** · dma 链 **255/255 = 100.0000%**；`非递增 t 对 = 0`（排序即提交序） |
| **R1-b②** | 尾部对账 err=0 | 0 | `Σdw70=1587560 = ACCT dW70`；`tail=0`；**`err = 0`**；dma 侧 `Σddma=267393622`、`tail_d=644944`；**`err2 = 0`** |
| **R1-c** | 并列（仅形态） | — | 本窗 **ΔW70 = 1,587,560 B（1.59 MB）**；同构型对照：0x24 S0 = 2,740,136 B；0x24 单源 11 窗 = 0.58–9.81 MB / 中位 2.41 MB。**单窗，无同会话 A/B，不作裁定** |

**三路独立一致（本窗内自洽性）**：
1. 快照端点差：`0x060c50d0 − 0x05f41768 = 101,470,416 − 99,882,856 = 1,587,560`（窗口 stdout 内 pre/post 快照 W70 原值，`SNAP_END … nff=0`）= ACCT `dW70` = `Σdw70` ⇒ **快照口径 / ACCT 口径 / READLOG 求和口径三分一致**；
2. ACCT `w70a/w70b` 与 pre/post 快照 W70 逐位同（`99882856` / `101470416`）；
3. 终态 `MIR_DMA_CNT = 0x0ff9f1a6 = 268,038,566` = ACCT `words1` = `dwords`。

**标定对照（同分析器）**：本窗打印序相邻链 **175/254**；旧工具 S0 打印序 124/254 —— 打印序部分不闭合是**已知的行序语义**（线程拼接非时间序，R3 口径）；两窗在打印序上都"不闭合"，而在 t 序上都 100%。

### 2.3 收尾（与 2.4 同批）

- 写 `0x08=0x2`（受控停流）→ 写 `MIR_CTRL(0x144)=0`（功能位归零）⇒ `CARRIER=0 / Link detected: no`；NIC 两读**逐字冻结**（`1160935948562 / 764780033`）。
- 终态寄存器：`0x00=0x50360001` · **`0x04=0x00000024`** · `0x08=0x00000002` · `0x14=0xdeadbeef` · `0x13C=0x00220000` · `0x144=0x00000000` · `0x148=0x0ff9f1a6` · `0x14C=0xffffffff`。
- 残留进程扫描 = 空；`/tmp/p7b_biz` 四件 md5 复核（= 切换后状态逐字相同）：`48dcbcb2…`（现役）/ `7cebded7…`（bak）/ `464006d9…`（cpp）/ `b4833c55…`（cpp bak）；`/tmp/p7b_biz_fix` 两件也逐字未变。
- dmesg（boot = `21:34:23`，`uptime -s` 现取，映射已核）：新增 `xdma:transfer_abort` @6542.4 s ⇒ **≈23:23:25.4**（= 本窗工具早停收尾的 fd 释放产物，`0-C2H0-ST` BUSY 快照同族，与 0x24 轮同类）；`sfc … link down` ×2 @6573.1/6573.2 ⇒ **≈23:23:56**（= 受控停流写的预期形态）。
- ⚠️ `0x13C` 终值 `0x00220000`：`MIR_STATUS = {[23]src_sel,[22:19]ver,[18]cap,[17]any_drop_sticky,[16]unf,[15:0]level}` ⇒ `ver=4 / any_drop_sticky=1 / level=0`。`any_drop` 是 sticky、clr 才清（`rtl/app_rx_mirror.v:141/347`）⇒ 与本窗 `ΔW70>0`（设计内丢字节）相符；与 0x24 轮终态 `0x00200000`（any_drop=0）的差异**登记**（成因未核到 RTL 级）。
- **板上现态 = `0x24` + 受控停流**（恢复 = `reg_rw /dev/xdma0_user 0x08 w 0x0`）。

### 2.4 本目录产物（mtime + md5）

| 件 | mtime（+0800） | md5 |
|---|---|---|
| `CRITERIA_R1.md` | 2026-10-13 23:21:53.271844500 | `00f176c6c7fc5a4409100a1127c93234` |
| `_tools/r1_readlog_analyze.py` | 2026-10-13 23:22:02.426275300 | `04cdcb4d9d45274072b98c1f208f6c58` |
| `runs/WIN_R1_20261013_232311.txt`（窗口全文，含 255 行 READLOG） | 2026-10-13 23:23:29.693680800 | `2bf19f58c5aa6ed80e6fdca4cc56b15e` |
| `runs/ANALYZE_R1.txt` | 2026-10-13 23:23:37.232919200 | `fb66162de05252d981a262599fe65c54` |
| `runs/CALIB_S0_analyze.txt`（标定） | 2026-10-13 23:22:05.223816400 | `29c95049b56a0546c58b29f921476468` |
| `runs/selftest_toolfix_20261013_232223.log` | 2026-10-13 23:24:23.029168700 | `a961402f6b18a69b221121d8839315e3` |

## §3 未竟（⛔ 不许当已答）

1. **单窗 n=1**：无同会话 A/B；本窗**未观测到**回绕行/链断裂，但 B 捆验证 §2.2 已证"触发需两线程 `[snap, commit]` 窗嵌套"是**概率性**事件 —— "未观测到"**不等于**"该工具已不可能回绕"（R1 的**结构性**论证在代码/静态锁序面；行为面证据 = 本窗 + selftest T15（mock 链）+ 静态锁序核对）。
2. **R1-a 无正例**：本窗与 S0 标定窗都没有回绕正例 ⇒ 该判据判别力靠"形态学 + 标定窗对照（打印序 124/254 证明链维非恒真）"支撑；要正例需回修复前工具重跑（会动现役，未做）。
3. **R2（回写单调性守卫）/ R4（`Σdw70 ≥ 2^32` 响亮标记）仍未实现**（FIX 轮登记；本轮未动工具语义）。
4. **未跑的构型**：repeat 窗（散布）/ 高丢率压力窗 / `--dual-stagger-ms` 特化 / `--aio`（selftest 结构性无 dual+aio 组合 —— FIX 轮 P3-4）/ `--src tcp` / bar/dma 路径；`dword_max_step=91,227,144` 只覆盖当前码率的回卷余量。
5. **`MIR_STATUS` 终值 bit17=1 与 0x24 终态 bit17=0 的差异**：登记（成因未核到 RTL 级；两者功能位均全 0、level=0）。
6. **附带项未决**：现役目录 `p7b_mir_dump.cpp` 已被本轮换成修复版（备份 `…bak_b4833c55` 在位）—— 若判据所有者要求"只动二进制"，一行 `cp` 即复旧（§0.2）。
7. **对端原件留档**：`/tmp/p9_toolfix/`（`WIN_R1_20261013_232311.txt` + `mir_R1.log` + `src_R1_p1.log` + `rstat_R1.log`，root 起、readable）；本目录 `runs/` 为归档副本。
8. 背景条件（形态见证）：窗口期间板 TX 泛洪持续（NIC `port_rx_bytes` pre→post Δ=18,781,596,430 B / ≈14.4 s；⚠️ 该口径在 ~1M fps 有已知 ~18% 计数虚高、机理未定位 —— 只作"泛洪在场"见证，不作速率）。
9. **报告落盘**：本 REPORT.md 由 agent 全文回传、TL 代落盘（平台拒写 .md）。

----------------------------------------------------------------

## TL 附加（2026-10-13 23:4x；非 agent 正文 —— 独立抽核记录）

- **本地 6 件 md5 + 字节数**逐字全中 §2.4 表（`CRITERIA_R1.md`/分析器/窗口全文 41,845 B/ANALYZE/CALIB/selftest 5,051 B）。
- **内容层复核**（直读归档件）：`TOOL_MD5=48dcbcb2…` · `dW70=1587560` · `closed_b=1`（`closed_a=0` = 宿主末段在飞，设计内）· ANALYZE 内 `wrap_candidates=0` / 双链 `255/255` / `err=err2=0` / 打印序 `175/254`（CALIB `124/254`）· selftest `52 OK / 0 FAIL / MIR_SELFTEST PASS`。
- **对端独立抽核**（TL 亲测，ssh 直读）：现役 `/tmp/p7b_biz/p7b_mir_dump` = `48dcbcb2…` ✓ · 备份 `7cebded7…` ✓ · `p7b_mir_dump.cpp` = `464006d9…` ✓ / bak `b4833c55…` ✓ · `/tmp/p7b_biz_fix/p7b_mir_dump` = `48dcbcb2…` ✓ · 对端原件 `WIN_R1_20261013_232311.txt` = `2bf19f58…` ✓（= 归档副本）。
- **板侧独立抽核**（TL 亲测，`reg_rw` 直读）：`0x04=0x00000024` ✓ · `0x08=0x00000002`（受控停流）✓ · `0x13C=0x00220000` ✓ · `carrier=0` ✓ ⇒ **板上现态 = `0x24` + 受控停流**，与 §2.3 逐条相符。
- 未复核项（如实登记）：§2.1 中"发端/读侧"细节行（进程内自报）、§2.3 dmesg 时刻换算、`0x13C` bit17 差异成因 —— 均按 agent 原文保留。
