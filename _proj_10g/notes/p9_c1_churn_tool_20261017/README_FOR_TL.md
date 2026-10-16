# p9_c1_churn_tool_20261017 —— C1「静默释放槽位偷取环」对端工具 `p7b_tcp_churn` 实施 + 自测【v2 = 最终】

> 件名 `_proj_10g/notes/p9_c1_churn_tool_20261017/README_FOR_TL.md` · 日期 **2026-10-17** · 状态 = **工具已实施 + 已部署 + 已过三级自检；⛔ 未上板、未烧录、未跑任何板级臂（本轮边界）**
> 规格出处 = `_proj_10g/notes/p9_p3win_redesign_20261017/README_FOR_TL.md` §2.2 / §2.4（TL 抽核块已把本件派单）
> ⛔ 本件**不下 PASS/FAIL 裁定**；下面所有 "PASS/FAIL" 字样都只是**自检脚本自己打的行**（判据所有者 = 用户/TL）
> ⚠️ 未用词："时序已解决"类措辞一律不出现在本件。

---

## 0 三行结论

1. **新件已交付**：`_proj_pcie/p7b_biz/p7b_tcp_churn.cpp`（**44998 B**，仓内主树）⇒ 对端产物 `p7b_tcp_churn`
   **140,576 B / md5 `ac2c89bf074f7dde979404776bfe35b5`**；源码 md5 **`388cd5d4f4cb488adf8d83313757dfef`**。
   **现役件一个字节未动**（`p7b_tcp_sink.cpp` 前读=后读 `dd3adfbe…`；4 个头 + 现役 sink 二进制锚 `f6229929…` 不变，见 `env/DEPLOY_REGISTRY.txt`）。
2. **三级自检全过**：`--selftest`（图案 RTL 向量）· `--selftest-scan`（**扫描器单测 11 条**）·
   回环门 `loopback_check.sh` **PASS=62/FAIL=0** + `hold_cap_check.sh` **PASS=15/FAIL=0**（合计 **77 判据**，含 17 条非法值 RC=2、离线独立复核、`--hold-s`/`--max-conns` 两条补径）。
3. **运行读数**（本机回环，非板级）：interval 10 ms ⇒ **99.995 连接/s**、400 连 0 失败、`gap_max=10.59 ms`；
   interval 50 ms ⇒ **19.999/s**、`gap_max=50.60 ms`；`--safe-close` ⇒ 活动 fd **4**（400 连里 399 被安全关掉）；
   候选判定三形态（`-1`/`0`/`na`）**逐一正确**；落盘 400 件经**独立第三实现**复核（0 件含针 + 正控/注入反例有牙）。
   ⭐ **v2 修正**：速率分母改按**连接窗口**（`--hold-s` 段不再混进分母）—— v1 在"3 s + hold 3 s"下把 100/s 读成 **49.9/s**，v2 = **100.000/s**（定点牙已入 `hold_cap_check.sh`）。

---

## 1 实施摘要（逐条对齐 §2.2 硬需求）

| §2.2 | 落点（实现） |
|---|---|
| 1 主循环 = `poll()` 多 fd + connect 定时器（`--connect-interval-ms` 默认 10） | 单线程 poll 环；**绝对时刻表**（`next_connect_at += interval`，catch-up 不改节奏）；`gap_max_ms` 落 `CHURN_SUM`（节奏可判） |
| 2 非阻塞 `connect()`（沿用 sink 建立序列 + `SO_RCVBUF` 落点） | `churn_connect_start()` = sink `sink_connect_rcvbuf` 的**逐条同款序列**（socket → `inet_pton` → `p7b_io_set_nonblock` → [`--local-port` bind] → **SO_RCVBUF 在 connect 之前** → `connect()` 立即返回）；完成在 poll 环里收（POLLOUT/POLLERR → `getsockopt(SO_ERROR)`）。⛔ **故意不用** `p7b_io_connect_nb`（它会 poll 到握手完成 ⇒ 把 10 ms 定时器串行化）；`CHURN_RCVBUF` 行给 **req 与内核回读 eff** 两个值（"传了参数"≠"生效"） |
| 3 永不主动 close；`--safe-close`（默认关） | 默认 = 零 close（除死 fd：connect 失败/EOF/RST）。`--safe-close` 规则 = **存在更新的连接已收到数据**（`newest_data_idx > oldest_open_idx`）⇒ 关最旧活动 fd；`closed_safe` 计数 + 每行 `closed_by=safe_close` + close 时刻状态 |
| 4 读干 + 首 64 KB + 首 4 KB 扫 32 B 针 | `churn_drain()` recv 到 EAGAIN；前缀**首字节到达时才 malloc**（1.2 万连 × 64 KB 若预分配 = 768 MB）；针由 `P7bPat(0).fill()` 生成（**不手抄常量**），指纹落 `CHURN_NEEDLE` 行 |
| 5 报告行 + 候选落盘 | 每连接一行，**前四字段固定** `CHURN conn=<k> bytes=… restart@off=… idle_ms=…`，其余追加行尾；`restart@off=-1` ⇒ 落 `--dump-prefix-dir/churn_conn%06lld.bin` + `CHURN_DUMP` 行；超 `--dump-max` 响亮计数 |
| 6 见证行 `CHURN_OPTS` | 字段与顺序 = 规格逐字：`connect_interval_ms=… rcvbuf=… seconds=… safe_close=… restart_scan=1`（回环门有**整行 grep 断言**）；另加 `CHURN_TARGET/CHURN_LIMITS/CHURN_ULIMIT/CHURN_RCVBUF/CHURN_NEEDLE` |
| 7 边界响亮 | 17 条非法值逐一验（interval ≤0 / rcvbuf 越界 / seconds ≤0 / port / local-port / prefix-kb / scan-bytes / dump-max / max-conns / hold-s / host / dump 目录 / 未知参数 / 缺值）⇒ **RC=2 + stderr 非空**（回环门 17/17） |
| 8 `ulimit -n < 16384` 警告 | `CHURN_ULIMIT soft=… hard=… need=16384 ok=…` 见证行 + **stderr 警告行**（对端现读 soft=**1024** ⇒ 每次启动都会响 —— 这是**真臂的前置条件**，见 §4-d） |
| 9 复用机制头 | `p7b_io.h`（set_nonblock/now_s/die/retryable/Reporter）· `p7b_affinity.h`（`argc = p7b_pin_cpu(argc, argv)` 启动即绑核硬门 + 见证 + atexit 硬门；`p7baff_work_freq_tick/khz` 周期行）· `p7b_pattern.h`（SEED/递推） |

**核心仪器（`restart@off`）的取值语义**（本件定义，写进 `--help` 与文件头）：
`k≥1` = 偏移 k 处重启（确定形态，非命中）· `0` = 针在偏移 0（**语义两义**：本连接恰是流起点 / 恰在 0 处重启 —— 字节上不可分，设计件 §1.4(P-3) 的 u_swc0 教训）**单独计数** ·
`-1` = 首窗（≤`--scan-bytes`，默认 4096）无匹配 ⇒ **命中候选**（落盘）· `na` = 收到字节 < 32（**判不了，不是候选、不落盘**）。

---

## 2 自测读数（全部本机/对端回环；⛔ 未碰板）

### 2.1 编译（`env/peer_build_v2.log` = 最终；`env/peer_build.log` = v1）

| 项 | 读数 |
|---|---|
| 口径 | `cd /tmp/p7b_biz && g++ -O3 -pthread -o p7b_tcp_churn p7b_tcp_churn.cpp`（BUILD.md §2） |
| 结果 | **BUILD_RC=0**；g++ 13.3.0；140,576 B；md5 `ac2c89bf074f7dde979404776bfe35b5` |
| `-Wall` 旁路检查 | RC=0；**唯一告警** = `p7b_affinity.h:851 p7baff_pin_self_thread defined but not used`（共享头自带的，单线程工具必现；与现役发送族同款，**非本件引入**） |

### 2.2 单测（`selftest/selftest_stdout_v2.txt` = 最终；两级都 RC=0）

* `--selftest`（图案机制与 RTL 对齐）= **OK**：off0..15 `7F 0B 02 E5 …` / off1460..7 `03 00 42 2D …` / state@100 `0xAB5917A81F0FB2AE`（三条都是 `p7b_pattern.h` 里**从 RTL 语义手算**的向量）。
* `--selftest-scan`（**扫描器独立单测 11 条，fails=0**）：

| 用例 | 期望 | 实测 |
|---|---|---|
| 针 vs 文档向量（**仪器自己先被核**） | 前 16 B | `7F 0B 02 E5 36 A1 4E D6 1A B0 49 B8 56 AD D6 3F` ✓ |
| 针在偏移 0 | 0 | **0** |
| 针在偏移 1234（前面铺**流中段**图案） | 1234 | **1234** |
| 无匹配（整段流中段图案） | -1 | **-1** |
| 窗边界：针起点 4064（=4096-32） | 4064 | **4064** |
| 窗边界：针起点 4065（尾字节出窗，窗=4096） | -1 | **-1** |
| 同上但给足整段（n=4097） | 4065 | **4065**（证明"不命中"是**窗**的功劳） |
| 半针（前 31 B 对 + 第 32 B 错） | -1 | **-1** |
| 翻中间 1 bit（负对照） | -1 | **-1** |
| 窗 31 B（比针短） | -1 | **-1** |
| 两处都有针 ⇒ 报**先出现**的 | 0 | **0** |

针全文 = `7F 0B 02 E5 36 A1 4E D6 1A B0 49 B8 56 AD D6 3F FC 7D 55 6B C8 6D 9A 9C 82 ED C1 CD 69 69 98 6C`（`fnv1a32=0xF372FA09`）。

### 2.3 回环门（`selftest/loopback_v2.txt` = 最终；**PASS=62 / FAIL=0**）

台架 = `fake_stream_server.py`（127.0.0.1；**≤500 连接 / 每跑 ≤15 s**；自遵守"不回数据/发流中段/发从 0 起"三模式）。

| 场景 | 关键读数 | 判定的东西 |
|---|---|---|
| **T1** mid / interval 10 ms / 4 s | `conns=400 rate_per_s=99.995 gap_max_ms=10.591 connfail=0 bytes=3276800 candidates=400 dumps=400 dump_fail=0`；fd 采样 1.5 s→**154** / 收尾→**379**（≈400 连+3 std）；服务器独立计数 `accepted=400` | 建立率 ≈100/s ✓ · fd 计数随连接增长且与 conns 一致（**无 fd 泄漏**）✓ · `bytes` 增长（逐连接恰 8192 B = 服务器发的量）✓ · 候选判定 `-1` ✓ |
| **T1b** 离线独立复核 | `files=400 with_needle=0 bytes_total=3276800` + **正控**（合成针在 0 ⇒ 报 0）+ **注入反例**（把针插到某文件偏移 100 ⇒ 报 100） | 落盘内容由**第三实现**复核：候选内确实无针，且该检查器**有牙** |
| **T2** mid / interval 50 ms / 10 s | `conns=200 rate_per_s=19.999 gap_max_ms=50.598` | 定时器刻度**可判**（50 ms 档不是 10 ms 档的假读数） |
| **T3** from0 / interval 20 ms / 4 s | `verdict_off0=200`（= conns）· `candidates=0` · `dumps=0`；样例行 `restart@off=0` | 重启形态 `0` 单独判定、**不落盘** ✓ |
| **T4** mid + `--safe-close` / 10 ms / 4 s | `conns=400 closed_safe=399`；活动 fd 采样（1.75 s / 收尾）= **4 / 4** | 旧 fd 数被控住（≤ 常数上界 + 余量）✓ · `safe_close=1` 见证 ✓ |
| **T5** sink（不回数据）/ 10 ms / 3 s | `nodata=300`（= conns）· `restart@off` 取值集合 = `{na}` · `candidates=0` · `bytes=0` | **0 字节连接记 `na`、不污染候选集合** ✓ |
| **T6** 边界响亮 | 17/17 非法值 `rc=2` + stderr 非空（每条原始 stderr 首行落档） | §2.2-7 ✓ |
| **T7** | `--help` RC=0 · `--selftest` RC=0 · `--selftest-scan` RC=0 | — |

### 2.4 补径门（`selftest/v2_gates.txt` 内的 hold_cap 段 = 最终；**PASS=15 / FAIL=0**）

* **E1 `--hold-s 3`（v2 定点牙）**：`wall_s=6.03`（= 3 + 3 + 收尾）· 活动 fd 在 t≈4.5 s（**窗口已结束**）仍 = **303** · `CHURN_T` 打到 t=4.0 · `conns=300`（**没有**多建）· `rate_per_s=100.000` / `conn_window_s=3.000` / `window_s=6.011`
  ⇒ 连接窗口结束后进程仍活着、fd 仍开着、仍在读干（退 FIN 洪泛的缓解手段**可用且可判**）；
  ⭐ **v1 在同一条下读到 `rate_per_s=49.904`** —— 那是分母含 hold 段造成的**读数缺陷**（不是板级/工具行为错），v2 已修并在此钉住。
* **E2 `--max-conns 50`**：`CHURN_CAP max_conns=50 reached at t=0.500 s` 行 + `conns=50` + `cap_hit=1` + 50 条逐连接行 + RC=0 ⇒ 上限路径有声有形。

### 2.5 版本与"判据自己先失效"的如实披露

| 版本 | 差别 | 证据 |
|---|---|---|
| v1（`4344e3ff…`） | 初版 | `loopback_run1.txt`（**PASS=58/FAIL=4**：4 条全是台架脚本 bug —— 浮点读数走 bash 整数 `-ge`；`bytes=` grep 未锚前导空格而命中 `scan_bytes=`/`prefix_bytes=`）· `loopback_run2.txt`（PASS=62/FAIL=0）· `hold_cap_run1.txt` |
| **v2（`ac2c89bf…`）= 最终** | **只改 SUM 的速率分母**（`conn_window_s`）+ 文件头一行说明 | `loopback_v2.txt`（62/62）· `v2_gates.txt`（hold_cap 15/15）· `selftest_stdout_v2.txt` |

⚠️ run1/run2 的两版都是 **v1 二进制**（`4344e3ff…`）；两次跑的 FAIL 差**只来自脚本修**，工具二进制两跑逐字节相同（已核）。

---

## 3 部署配方增量（供 C1 臂脚本照抄）

```bash
P=/c/Users/zhxue/anaconda3/python.exe
B=D:/repo/XCKU5PMini/udp_hls_10g
# 1) 上载源码（必须保持文件名 p7b_tcp_churn.cpp —— 源文件名进 .symtab ⇒ 改名换 md5，BUILD.md §3b）
$P tools/peer_ssh.py --put "$B/_proj_pcie/p7b_biz/p7b_tcp_churn.cpp" /tmp/p7b_biz/p7b_tcp_churn.cpp
# 2) 编译（BUILD.md §2 唯一口径）
$P tools/peer_ssh.py "cd /tmp/p7b_biz && g++ -O3 -pthread -o p7b_tcp_churn p7b_tcp_churn.cpp"
# 3) 对 md5：源 388cd5d4f4cb488adf8d83313757dfef / 产物 ac2c89bf074f7dde979404776bfe35b5 (140576 B)
# 4) 复跑自检（不碰板）：--selftest / --selftest-scan
#    bash /tmp/c1_churn_selftest/loopback_check.sh     (62 判据)
#    bash /tmp/c1_churn_selftest/hold_cap_check.sh     (15 判据)
```

**使用示例（真臂命令行；`--hold-s` 见 §4-c）**：

```bash
# ⚠️ 先抬 fd 上限（对端现读 soft=1024；120 s×100/s ≈ 12,000 fd）
ulimit -n 16384
mkdir -p /tmp/c1_dump_0x28
/tmp/p7b_biz/p7b_tcp_churn --host 192.168.100.2 --port 8080 \
    --connect-interval-ms 10 --rcvbuf 1048576 --seconds 120 \
    --max-conns 16000 --dump-prefix-dir /tmp/c1_dump_0x28 --hold-s 5 \
    > /tmp/c1_0x28.out 2> /tmp/c1_0x28.err
# 收数：CHURN_SUM 行 = 板侧读数的对端锚；grep '^CHURN conn=' | awk 统计 restart@off 分布
```

---

## 4 偏离 / 未决（逐条；⛔ 不许读成"已收口"）

| # | 项 | 说明 |
|---|---|---|
| **a** | **规格 §2.2-4 的 `pattern[0]=0x9E` 是错的** | 现读 RTL 语义（`gen_byte = tx_lfsr[31:24]` + `p7b_pattern.h` 的手算向量 + 本件 `--selftest` 实跑）⇒ **`pattern[0]=0x7F`**。`0x9E` = `SEED` 的**最高字节**（`tx_lfsr[63:56]`）—— 那句话把 `SEED>>56` 当成了 `tx_lfsr[31:24]`。本件按**RTL 语义**取针（规格同一句里的 `gen_byte=tx_lfsr[31:24]` 才是对的），针全文见 §2.2。**下游若按其字面 `0x9E` 起手搜，会 100% 搜不到。** |
| **b** | `restart@off=na` = 本件新增的**第三取值** | 规格只定义了 `k`/`-1`。0 字节（或 <32 B）连接若记 `-1`，1.2 万条"没收到数据"的连接会把候选集合污染成噪声 ⇒ 记 `na` 且不落盘；`CHURN_SUM` 里 `nodata=`/`short_lt32=`/`candidates=` 三分。**口径变更需 TL 确认**（已在 `--help` 与文件头写明） |
| **c** | **进程退出 ⇒ 内核关全部 fd ⇒ 已建立连接各发 1 个 FIN**（真臂 ~1.2 万条） | 会给板侧灌控制帧（可能触发 DEL/ev_down，污染下一臂的起始态）⇒ 提供了 `--hold-s N`（打印完逐连接行与 `CHURN_SUM` 后**继续读干** N 秒**再退**）给 `p7b_snap` 收数留窗；E1 已实测该路径可用且不留假读数。⛔ **臂脚本应把 `--hold-s` 用起来**；本件**无法**让退出不发 FIN（SIGKILL 也一样） |
| **d** | **对端 `ulimit -n` soft = 1024**（现读） | 无安全关模式 120 s 需 ≈12,000 fd ⇒ **真臂跑之前必须先 `ulimit -n 16384`**（工具会打 `CHURN_ULIMIT ok=0` + stderr 警告，但**不会**自动抬）；不抬 ⇒ 撞 `EMFILE`（工具打一次 `CHURN_WARN EMFILE` 并继续记账，跑出来的读数**不可用于"事件率"判据**） |
| **e** | C3 的"close→reopen 同端口"**不是**本工具 hold 模式 | 本件提供 `--local-port`（bind-before-connect 原语，沿用 sink 语义）；但**持有不关** ⇒ 第 2 条起 bind 必 EADDRINUSE（记 FAIL_CONNECT + 打一次 `CHURN_WARN`）。C3 臂应按设计件用**现役 sink 的顺序模式** |
| **f** | 收尾时仍在 CONNECTING 的 fd **不判死** | SYN 重传由内核走完（"板没有空槽就不应答 SYN"正是本构型要的）⇒ 只统计不 close；`connecting=` 落 `CHURN_SUM`（真臂若出现大量 connecting ⇒ 直接读数即可判"板没接"） |
| **g** | **未跑**现役"五项自检"（`p7b_selftest.sh` 等） | 理由 = 派单硬约束"不覆盖任何现役件"，而那 5 套脚本会**编译/运行现役工具**（有覆盖共享部署的风险）；改以 **① 现役件 md5 前读=后读**（§0-1 + `env/DEPLOY_REGISTRY.txt`）+ **② 本件自带两级自检** + **③ 独立 77 判据回环门** 替代。⛔ 若 TL 要那 5 套，请单独排期（不与其他板级轮并行） |
| **h** | **未做**（本轮边界） | 不跑板、不烧录、不做板级臂脚本、不动任何 RTL/TB/快照几何。板级 C1 两代臂（0x28/0x24 × 120 s，KW 表见设计件 §2.2）**待 TL 排期** |
| **i** | 回环读数的**可外推范围** | 回环测的是**工具自身**（建连率/定时器/fd/扫描/落盘/边界），**不是** C1 构型在板上的行为；"99.995 连/秒"是**回环**读数，板级速率必须重取 |
| **j** | 落盘上限 | `--dump-max` 默认 **2048**（≈128 MB）；超限打 `CHURN_DUMP_LIMIT` 行并计数（`dumps_skipped`）。真臂候选数未知 ⇒ **跑前按 TL 判断抬 `--dump-max`**（候选 = `restart@off=-1` 的条数） |
| **k** | v1→v2 的改动**只动读数口径**，不动行为 | 除 `conn_window_s` 外 v2 与 v1 逐行同源；v1 的全部 v1-读数（run1/run2/hold_cap_run1）**仍可对账**，但**引用速率一律用 v2** |

---

## 5 证据地图

| 件 | 内容 |
|---|---|
| `_proj_pcie/p7b_biz/p7b_tcp_churn.cpp` | **源码**（入库主树；`_proj_pcie/p7b_biz/` 与现役头同目录，扁平部署） |
| `selftest/selftest_stdout_v2.txt` | **最终** `--selftest` + `--selftest-scan` 原文（11 条扫描单测逐条读数）；`selftest_stdout.txt` = v1 |
| `selftest/loopback_v2.txt` | **最终回环门全文：PASS=62/FAIL=0**（含 `CHURN_SUM`、样例行、离线复核原文） |
| `selftest/hold_cap_run1.txt` · `selftest/v2_gates.txt` | 补径门：`--hold-s`/`--max-conns`（前者 = v1，后者内含 v2 的 15/15） |
| `selftest/loopback_run1.txt` · `loopback_run2.txt` | v1 两跑（run1 = 台架脚本 4 条假 FAIL 的实例，run2 = 修脚本后的 62/62） |
| `selftest/loopback_check.sh` · `hold_cap_check.sh` · `fake_stream_server.py` · `offline_dump_check.py` | 回环门四件（部署在 `/tmp/c1_churn_selftest/`，md5 见 registry） |
| `env/peer_build_v2.log` · `env/peer_build.log` | 对端编译原文（v2 / v1；各含 `-Wall` 旁路检查） |
| `env/deploy_md5.txt` | 现役件后读 md5 + 新件 md5（原样 stdout） |
| `env/DEPLOY_REGISTRY.txt` | 部署登记表（新件 v2/v1 / 台架 / 现役件未触碰见证 / 对端环境） |

—— 完（本件 = 工具实施件；板级 C1 臂的排期与裁定权在 TL/用户）
