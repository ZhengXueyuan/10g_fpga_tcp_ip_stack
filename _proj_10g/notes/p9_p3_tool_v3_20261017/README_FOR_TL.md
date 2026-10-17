# p9_p3_tool_v3_20261017 —— P-3 工具 v3「全流滚动针扫描」实施 + 自检

> 件名 `_proj_10g/notes/p9_p3_tool_v3_20261017/README_FOR_TL.md` · 日期 **2026-10-17** ·
> 状态 = **工具源码已交付 + 对端编译通过 + CPU-only 自检通过；未上板、未烧录、未跑任何网络收发（本轮边界）**
> 规格出处 = `_proj_10g/notes/p9_p3_boost_design_20261017/README_FOR_TL.md` §4.1-A（Q2 = 全流滚动针）
> 前序件 = `_proj_10g/notes/p9_c1_churn_tool_20261017/README_FOR_TL.md`（v2，77 判据）
> ⛔ 本件**不下 PASS/FAIL 裁定**；状态词 = 【已证】/【未判定】/【未定位】/【未测】/【未观测到】。
> ⛔ 未用词："已排除 / 不存在 / 收口" 类措辞不出现在本件；工具自检行里的 "PASS/FAIL"
>    只是**工具自己的判据行**，不是工程裁定。

---

## §0 三行结论

1. **新件已交付**：`_proj_pcie/p7b_biz/p7b_tcp_churn_v3.cpp`（**78,239 B / md5 `44ccdb9a61008033542240dada7c20cd`**）。
   `p7b_tcp_churn.cpp`（v2）**一个字节未动**（源 md5 仍 = `388cd5d4f4cb488adf8d83313757dfef`）；
   `/tmp/p7b_biz/` 现役工具与头文件**未被覆盖**（编译在独立目录 `/tmp/p3_tool_v3_20261017/`）。
2. **编译【已证】**：对端 `g++ -O3 -pthread`（BUILD.md §2 口径）**RC=0**；`-Wall -fsyntax-only` **RC=0 且零告警**。
   产物 `p7b_tcp_churn_v3` = **203,304 B / md5 `5ffab696dd45ccc67ecf2e150b56bba4`**。
3. **自检【已证】（CPU-only，未发任何网络包）**：`--selftest-all` = `SELFTEST_ALL PASS`
   （图案 3 向量 OK / 扫描 16 条 0 fail + 随机等价 20/20 / M⁸ vs 逐字节等价 10 条 0 fail /
   校验器 18 条 0 fail）；**17/17 条 v2 非法值 RC=2** + **7/7 条 v3 新非法值 RC=2**；
   `--help` RC=0。**56/77 条 v2 判据（需要 socket 的回环/补径门）本轮【未测】**（派单禁止网络收发）。

---

## §1 设计

### 1.1 全流滚动针（Q2 的承重件）

**要回答的问题（设计件 §4.0）**：对每个收到过数据的连接，**整条流**里是否出现过
`pattern[0..31]`（= 板侧 `tx_lfsr` 被复位到 SEED ⇒ 图案流重启）。v2 只看首 4 KB；
v3 看**全部字节**，并给出**每一次出现的位置**。Q2 的两个分类都只需要这一件事：

* **候选 C**：`hits == 0 ∧ scan_state=full` ⇒ C 全流无重启。
* **前持有者 P**：`last_needle` = P 的最后一次重启偏移 `o` ⇒
  `P.bytes − o == K0` ⇒ J-退化；`K0 == P.bytes − o`（P 无针时取 `P.bytes`）⇒ J-命中相容。

**针**：32 B，由 `P7bPat(0).fill()` 生成（**不手抄常量**）。
**`pattern[0] = 0x7F`**（= `SEED[31:24]`；⛔ **不是 0x9E** —— 0x9E 是 `SEED[63:56]`，
v2 ERRATA 已三路证实）。针全文 = `7F 0B 02 E5 36 A1 4E D6 1A B0 49 B8 56 AD D6 3F
FC 7D 55 6B C8 6D 9A 9C 82 ED C1 CD 69 69 98 6C`（`fnv1a32=0xF372FA09`）。

**算法（流式，跨 recv chunk）**：
1. 每连接保留**最后 31 B** 作为下一块的 carry（`V3_NCARRY=31`）。
2. 每来一个 chunk `p[0..n)`（全局起点 `base = c.bytes`）：
   * **边界块** = `carry + p[0..min(n,31))`，只记"起点在 carry 里"（`g < base`）且整针已完整的出现；
   * **正文档** = `memchr(p, needle[0])` 过滤 + 候选处 32 B `memcmp`，记所有 `i+32 <= n` 的出现；
   * 更新 carry = 流的最后 `min(31, total)` 字节。
3. **不重复、不遗漏的判据**：一个出现只在它**最后一个字节到达**的那次 feed 里被记一次——
   * 整针完全落在旧数据里（`g+32 <= base`）：上一块已经扫过（上一块的正文扫描覆盖了所有
     `start <= 上一块末尾-32` 的位置）；
   * 整针跨边界：本块边界块记一次；
   * 整针完全在本块：本块正文记一次；边界块的 chunk 部分只有 31 B，**装不下** 32 B 的正文针
     ⇒ 结构性不会重复。
4. **流不缓存**：只有 31 B carry + 有界偏移列表；没有"把整条流存起来再扫"的队列。
   前缀 64 KB（`--prefix-kb`）是 v2 既有的**首窗/dump** 逻辑，不是全流扫描的缓冲。

**复杂度**：
* 期望 **O(n)**（`memchr` 是 SIMD 优化过的单字节过滤；图案流中 `0x7F` 出现率约 1/256）；
* 最坏 **O(32n)**（病态输入：每个字节都是 `0x7F`，每次候选都做 32 B `memcmp`）；
* 空间 **O(31 B + needle_max×8 B) / 连接**（默认 `needle_max=64` ⇒ 512 B；懒分配）。

**读数**（每连接行追加；`hits=0` 只在 `scan_state=full` 时才有"全流无重启"的语义）：
`full_scan=1 first_needle=<off|-1> hits=<n> last_needle=<off|-1> scanned=<bytes>
scan_state=<full|short|none|off> needle_trunc=<0|1>`；出现偏移列表在独立行
`CHURN_NEEDLES conn=<k> n=<hits> shown=<stored> trunc=<0|1> offs=o1,o2,...`。

**`scan_state` 的空判据防线**（本项目全局 #92）：
| 值 | 含义 | 能否说"无重启" |
|---|---|---|
| `full` | 收到 ≥32 B 且全部字节过扫描 | **可以**（`hits==0` ⇒ 全流无针） |
| `short` | 收到 1..31 B（连针都装不下） | **不可以**（判不了） |
| `none` | 0 B | **不可以** |
| `off` | `--scan-all 0` | **不可以**（字段里的 0 是占位） |

**唯一性边界（如实登记）**：32 B 针在一条**干净**图案流（非零相位）里不出现的**数学唯一性
未证明**。本件只证明两件事：① 两个独立扫描器（滚动 vs 朴素全流）在同一流上给出**同一列表**
（1 MiB × 20 随机种子，20/20）；② 本工程历史读数里从未观测到误报（v2 的单测与 C1 板级）。
"未观测到" ≠ "不存在"。

### 1.2 M⁸ lane-parallel：相位连续性校验（`--verify-stream`）

**先说清楚 M⁸ 用在哪、不在哪**：
* 32 B 针的**任意偏移搜索**不需要 M⁸ —— 它需要的是"相位未知"下的字节串匹配，
  本件用 `memchr + memcmp`（§1.1）。
* M⁸ 表（`p7b_pattern.h` 的 `Tj`/`Tw`，8 字节/步）真正加速的是**已知相位的连续流校验**：
  给定流在某个字节的状态，一次算出下 8 个期望字节 + 下 8 步状态（16 次表查询 + 15 次异或，
  无串行依赖）。本件用它做"**任意偏移的字节流断点**"那一半仪器。

**校验器语义**：把连接流当成**某一条**连续图案流（相位未知）来跟踪。
* 首次需要 17 B 做 resync：**9 B 反解 64 位状态**（见下）+ **8 B 的 M⁸ 一步验证**；
* 之后每个 chunk 用 `P7bPat::check` 校验；`--check lane8` = M⁸ 路径，`--check seq` = 逐字节
  对照臂（默认 seq = 历史已上板验过的路径）；
* 一旦失配 ⇒ 记一次 `vbreaks`（偏移 = **首次观测到的失配字节**），从该字节起重新 resync 后继续；
* 非图案数据找不到合法相位 ⇒ 逐字节 resync 搜索有**硬预算** `--verify-degrade-bytes`
  （默认 1 MiB）⇒ 超限置 `vdegraded=1` 并**停止该连接的校验**（针扫描不受影响）。

**resync 的数学（本件新增，自检覆盖）**：
* 连续 **8** 个输出字节的映射在 GF(2) 上**秩只有 63**（实测：`rows 0..63 rank=63`）⇒
  **不可逆**；**9** 个字节秩 64 ⇒ 可反解。
* 本件选 64 个输出位（row 0..61 + 63 + 64；row 62 留作冗余校验位），运行时建 64×64 GF(2)
  逆表；decode 取的是逆矩阵的**列**（⚠️ 直接取行会转置 ⇒ 基向量 0/64，本轮自检实测踩到并已修）。
* 9 B 的 8 个冗余位 + 下 8 B 的 64 位 M⁸ 验证 ⇒ 17 B 窗口的误同步率约 **2⁻⁷²**。

**读数**（每连接行追加；独立行 `CHURN_VBREAKS` 给前 `break_max` 条偏移）：
`verify=<0|1> vbreaks=<n> vfirst_break=<off|-1> vlast_break=<off|-1>
vdegraded=<0|1> vscanned=<bytes> vmode=<seq|lane8>`。

**语义边界（如实登记）**：
* `vfirst_break`/`vlast_break` 是**首次失配**，不是"真实相位切换点"的严格见证：
  若新相位的前几个字节恰好等于旧相位期望（概率很小），失配会晚几字节。**重启的精确位置
  由针扫描给出**（`first_needle`/`last_needle`），校验器管的是"任意偏移的断点"。
* `vscanned` = 校验器**检查/搜索过的字节数**，不是"全部已验证的字节数"；断点后的 resync 段
  只算"检查过"。
* `vdegraded=1` ⇒ 该连接**不能**用校验器下任何结论；针扫描仍独立有效。

**为什么默认关**：设计件 §5-U7 明确 `--scan-all` 对读速的影响**未测**；再叠一层全流校验会
改变 C1b2 构型的读速与事件率。v3 的默认 = **v2 + 全流针**（可比性优先）；M⁸ 臂用
`--verify-stream 1 --check lane8` 显式打开，`--check seq` 是同轮对照臂。

### 1.3 输出接口（只追加，不改名/不改序）

**逐字未动的行/字段**：
* `CHURN_OPTS connect_interval_ms=… rcvbuf=… seconds=… safe_close=… restart_scan=1`
  —— **整行逐字不变**（77 判据里的 `T1_opts_line` 是整行 grep 断言）。
* 每连接行前 13 个字段：`conn= bytes= restart@off= idle_ms= state= why= why_str= closed_by=
  reads= scan_bytes= prefix_bytes= dur_ms= estab_ms= last_rx_ms= CPU_FREQ_KHZ=`。
* `CHURN_SUM` 的全部既有键与顺序；`CHURN_T` 的既有键；`CHURN_ULIMIT/RCVBUF/NEEDLE/TARGET/LIMITS`；
  `CHURN_DUMP`；`CHURN_DONE`。
* 退出码三条件（0/1/2，见 §1.4）。

**新增/追加**：
| 行 | 内容 | 说明 |
|---|---|---|
| `CHURN_SCAN_OPTS`（新行） | `version=3 scan_all= needle_max= verify_stream= verify_degrade_bytes= break_max= check= needle_len=` | v3 开关的**生效值见证** |
| `CHURN conn=` 行尾 | `full_scan= first_needle= hits= last_needle= scanned= scan_state= needle_trunc= verify= vbreaks= vfirst_break= vlast_break= vdegraded= vscanned= vmode=` | 追加在 `CPU_FREQ_KHZ=` 之后 |
| `CHURN_NEEDLES`（新行，仅有针时） | `conn= n= shown= trunc= offs=`（逗号分隔；`shown=0` 时 `offs=-`） | 出现偏移列表 |
| `CHURN_VBREAKS`（新行，仅有断点时） | 同上 | 断点偏移列表 |
| `CHURN_T` 行尾 | `scan_hits= vbreaks=` | 累计轨迹 |
| `CHURN_SUM` 行尾 | `full_scan= scan_bytes_total= needle_conns= needle_hits= needle_trunc_conns= verify= vbreak_conns= vbreaks= vdegraded_conns= vmode=` | 汇总 |

⚠️ 派单里提到的 `s1_3_run.sh`（sed 抓 `off_end`）与 `recompute_s1_3.py`（正则抓
`UDP_SUM … off_start= off_end=`）解析的是 **`p7b_udp_src` 的 `UDP_SUM`**，本件**不改那个工具**；
本件对 v3 自己的行遵循**同一纪律**（`CHURN_OPTS` / `CHURN conn=` / `CHURN_SUM` 只追加）。
C1 臂脚本 `c1_arm.sh` 的解析面（`^CHURN conn=`、`restart@off=`、`^CHURN_SUM`）**逐条核对未破**。

**下游兼容性核对（对 v2 的 77 判据脚本逐条）**：
* `sfield()` = `grep -oE "(^| )$2=[^ ]+"` ⇒ 追加字段不影响既有键；
* `connfield()` 取 `restart@off` ⇒ 仍在；
* `grep -c '^CHURN conn='` ⇒ `CHURN_NEEDLES` 不以 `CHURN conn=` 开头，不误计；
* `T1_opts_line` 的整行断言 ⇒ `CHURN_OPTS` 未动；
* `T1_bytes_values_in_0_or_8192` 的 `(^| )bytes=[0-9]+` ⇒ 新字段没有 " bytes=" 形式
  （`scan_bytes=`/`prefix_bytes=` 前是 `_`，不是空格）。

**程序化比对（v2 vs v3 的 printf 格式串前缀；2026-10-17 现跑）**：
`CHURN_OPTS`（行尾）/ `CHURN_T` / `CHURN conn=` / `CHURN_SUM` 四条在 `CPU_FREQ_KHZ=%s`
（或行尾）之前**逐字相同**，四条均 `PREFIX_IDENTICAL=True` —— 既有字段**没有改名/改序**，
新字段只在 `CPU_FREQ_KHZ=` 之后追加。

### 1.4 内存上界 / 复杂度 / 退出码

| 项 | 上界 | 说明 |
|---|---|---|
| 每连接针扫描 | **31 B + needle_max×8 B** | 默认 512 B；懒分配（0 命中/0 数据不分配） |
| 每连接校验器 | **16 B + break_max×8 B** | 默认 128 B；懒分配 |
| 每连接前缀（v2 既有） | `prefix_kb×1024`（默认 64 KB） | **只在首字节到达时分配**；全流扫描**不增加**这块 |
| 全流扫描时间 | 期望 O(n)；最坏 O(32n) | 见 §1.1 |
| 校验器时间 | 正常 O(n/8×表查询)；断点处 O(resync 预算) | 非图案数据最坏 ≈ `verify_degrade_bytes` × ~60 ops/字节/连接 |
| 退出码 | **三条件逐字保留**：0 = 跑完 ∧ 有连接 ∧ 无 dump 失败；1 = 任一不成立；2 = 用法/环境错 | `needle_trunc` / `vdegraded` **不改变 RC**（声明过的读数边界，不是跑失败） |

⚠️ **`--max-conns` 默认 16,000；若全部连接都收到数据且都用默认 64 KB 前缀**，前缀总量
≈ **1.0 GB**（v2 既有口径）；v3 新增只有 `needle_max×8 B`/连接（默认 ≈8 MB 上界）。
长臂建议按 C1b2 实际（116 条有数据连接）估，或下调 `--prefix-kb`。

---

## §2 v2 的 77 判据对照表（62 回环 + 15 补径）

**状态图例**：`保留·已测` = v3 本轮实际执行且通过（工具自检行）；`保留·未测` = 代码路径逐字
保留但本轮**禁止网络收发**故未执行；`新增` = v3 新判据。

**变化项 = 0**：既有 77 条的**输入参数语义、输出字段名/顺序、退出码三条件**均零改动
（唯一插入是 `churn_drain` 里两个扫描调用，不改变 socket 行为；输出只在既有字段之后追加）。
**新增项 = §2.3**（全流滚动针 / M⁸ 等价 / 校验器 / 7 条新非法值）。

### 2.1 回环门 `loopback_check.sh`（62 条）

| 组 | 判据名（逐条） | v3 状态 | v3 落点/说明 |
|---|---|---|---|
| T1（20） | `T1_rc` | 保留·未测 | 退出码三条件逐字保留 |
| | `T1_conns` | 保留·未测 | `CHURN_SUM conns=` 未动 |
| | `T1_rate_per_s` | 保留·未测 | `conn_window_s` 分母（v2 修复）逐字保留 |
| | `T1_nodata` | 保留·未测 | `nodata=` 未动 |
| | `T1_candidates` | 保留·未测 | `restart@off=-1` 首窗口径未动 |
| | `T1_dumps` | 保留·未测 | dump 逻辑未动（仍只落候选） |
| | `T1_dumps_skipped` | 保留·未测 | `dump_max` 逻辑未动 |
| | `T1_dump_fail` | 保留·未测 | 写失败 RC=1 未动 |
| | `T1_bytes_8192x` | 保留·未测 | `bytes=` 求和未动 |
| | `T1_conn_lines` | 保留·未测 | `CHURN conn=` 行数未动（新行不冒名） |
| | `T1_bytes_values_in_0_or_8192` | 保留·未测 | 新字段无 " bytes=" 形式 |
| | `T1_opts_line` | 保留·未测 | `CHURN_OPTS` **整行逐字未动** |
| | `T1_ulimit_warn_ok0` | 保留·未测 | `CHURN_ULIMIT ok=` 未动 |
| | `T1_ulimit_warn_stderr` | 保留·未测 | 警告文案未动 |
| | `T1_pin_bound` | 保留·未测 | `p7b_pin_cpu` 调用未动 |
| | `T1_fd_at_1p5s` | 保留·未测 | socket/fd 行为未动 |
| | `T1_fd_final` | 保留·未测 | 同上 |
| | `T1_estab` | 保留·未测 | estab 计数未动 |
| | `T1_srv_accepted_last` | 保留·未测 | 建连序列未动 |
| | `T1b_offline_rc` | 保留·未测 | dump 文件内容/数量未动 |
| T2（4） | `T2_rc` `T2_conns` `T2_rate_per_s` `T2_gap_max_ms` | 保留·未测 | 绝对时刻表 + `gap_max` 未动 |
| T3（6） | `T3_rc` `T3_conns` `T3_verdict_off0` `T3_candidates` `T3_dumps` `T3_dump_files` | 保留·未测 | 首窗 `restart@off` 语义未动 |
| T4（5） | `T4_rc` `T4_conns` `T4_live_fd_bounded` `T4_closed_safe` `T4_safe_close_witness` | 保留·未测 | `--safe-close` 未动 |
| T5（6） | `T5_rc` `T5_conns` `T5_nodata` `T5_candidates` `T5_verdict_na` `T5_bytes` | 保留·未测 | `na` 三取值未动 |
| T6（17） | `bad_interval0` `bad_intervalneg` `bad_seconds0` `bad_rcvbuf_lo` `bad_rcvbuf_hi` `bad_prefixkb0` `bad_scan31` `bad_scan_toobig` `bad_port0` `bad_localport_hi` `bad_dumpmax_neg` `bad_maxconns0` `bad_hold_neg` `bad_host_bogus` `bad_dumpdir_miss` `bad_unknown_arg` `bad_missing_val` | **保留·已测 17/17** | 全部 `rc=2` + stderr 非空（§3.4 原始读数） |
| T7（2） | `T7_help_rc` `T7_help_has_off` | **保留·已测 2/2** | `HELP_RC=0`；`restart@off` 出现 3 次（1..9 范围内） |
| T8（2） | `T8_selftest_rc` `T8_selftest_scan_rc` | **保留·已测 2/2** | 两条单独跑均 RC=0（另加 equiv/verify 也 RC=0） |

**T1–T5 + T1b = 41 条**需要 127.0.0.1 真实 socket（listen/connect/send/recv）⇒ 本轮按派单
"不得启动任何网络收发" **未测**。代码路径是 v2 的逐字拷贝（唯一插入是 `churn_drain` 里
`v3_needle_feed`/`v3_verify_feed` 两个调用，位于 `c.bytes` 更新之后、前缀拷贝之前；
它们不改变 socket 的读写语义）。

### 2.2 补径门 `hold_cap_check.sh`（15 条）

| 组 | 判据名（逐条） | v3 状态 | 说明 |
|---|---|---|---|
| E1（10） | `E1_rc` `E1_wall_s` `E1_fd_pre` `E1_fd_in_hold` `E1_churn_t_during_hold` `E1_conns` `E1_cap_hit` `E1_rate_per_s` `E1_conn_window_s` `E1_window_s` | 保留·未测 | `--hold-s` 循环未动；`CHURN_T` 既有键未动 |
| E2（5） | `E2_rc` `E2_cap_line` `E2_conns` `E2_cap_hit` `E2_conn_lines` | 保留·未测 | `--max-conns` 撞顶逻辑未动 |

**合计**：62 + 15 = **77 条**；本轮**实际执行 21 条**（T6 17 + T7 2 + T8 2），
**未测 56 条**（T1–T5/T1b 41 + E1/E2 15）。

### 2.3 v3 新增判据（不计入 77）

| 组 | 判据 | 本轮读数 |
|---|---|---|
| 扫描单测 | v2 的 11 条同名同期望（`needle_vs_doc_vector` / `match_at_0` / `match_at_1234` / `no_match` / `window_edge_in_4064` / `window_edge_out_4065` / `window_edge_out_full` / `partial_31_of_32` / `flip_1bit_no_match` / `short_window_31` / `first_of_two_matches`） | 11/11 通过（§3.2） |
| 扫描单测 | `bytewise_two_hits`（逐字节 feed） | hits=2 first=0 last=132 stored=2 |
| 扫描单测 | `split_16_16`（针跨 chunk 边界） | hits=1 first=10 stored=1 |
| 扫描单测 | `trunc_cap3`（needle_max 截断） | hits=5 stored=3 trunc=1 |
| 扫描单测 | `short_streams`（0/31 B） | hits0=0 hits31=0 |
| 扫描等价 | 1 MiB × 20 随机种子 × 随机 chunk（1..8192）vs 朴素全流 | **20/20 逐位相同** |
| M⁸ 等价 | `--selftest-equiv`（表重建 4096 / 8 MiB+5 / 6 点注入 / 跨块 12 状态 / 分派） | **10/10** |
| 校验器 | `--selftest-verify`（反解表 / 12 种 chunk 干净流 / 3 种注入 / 非图案降级） | **18/18** |
| 边界 | 7 条 v3 新非法值（`--scan-all 2` / `--needle-max -1|4097` / `--verify-stream 2` / `--verify-degrade-bytes 100` / `--break-max -1` / `--check foo`） | **7/7 rc=2** |

---

## §3 编译与自检读数

### 3.1 编译【已证】

| 项 | 读数 |
|---|---|
| 口径 | `cd /tmp/p3_tool_v3_20261017 && g++ -O3 -pthread -o p7b_tcp_churn_v3 p7b_tcp_churn_v3.cpp`（BUILD.md §2） |
| 结果 | **BUILD_RC=0**；g++ (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0 |
| `-Wall` 旁路 | `g++ -O3 -pthread -Wall -fsyntax-only` ⇒ **RC=0，零告警**（原文 `env/wall_check.txt`） |
| 源 | **78,239 B / md5 `44ccdb9a61008033542240dada7c20cd`** |
| 产物 | **203,304 B / md5 `5ffab696dd45ccc67ecf2e150b56bba4`** |
| 头指纹 | `p7b_pattern.h b2f2e9627bac53bf3b4ab2b565afe872` · `p7b_affinity.h b03222792d20443138515ba2804b0d87` · `p7b_io.h 62b1257d69c40f24bfa9a799593073b7` |
| 现役件 | `p7b_tcp_churn.cpp` md5 **`388cd5d4f4cb488adf8d83313757dfef`（未变）**；对端现役二进制 `/tmp/p7b_biz/p7b_tcp_churn` md5 **`ac2c89bf074f7dde979404776bfe35b5`（= v2 README 锚，mtime 2026-10-17 03:01:29）**；编译在独立目录，`/tmp/p7b_biz/` 未覆盖 |

⚠️ **本轮的两次构建（如实登记）**：
* 第一版（pre-fix）产物 md5 `876f07e0ab2cfebfc1a78a1e348f0bf7`，`--selftest-all` 在 `VERIFY inv_init`
  **失败**（逆表转置 bug），随后 Python 镜像又抓到**小 chunk carry 覆盖** bug；
* 修复两处后重编 = 最终 `5ffab696…`，`SELFTEST_ALL PASS`。
两处都是**工具自身缺陷**，不是被测设计的问题；修复点已写进源码注释（`p7b_tcp_churn_v3.cpp`
的 `v3_inv_init` 转置段与 `v3_verify_feed` 的 carry 合并段）。

### 3.2 扫描自检【已证】（原文见 `selftest/selftest_all_fixed.txt`）

```
SCAN needle len=32 fnv1a32=0xF372FA09
SCAN needle[0..31]  = 7F 0B 02 E5 36 A1 4E D6 1A B0 49 B8 56 AD D6 3F FC 7D 55 6B C8 6D 9A 9C 82 ED C1 CD 69 69 98 6C
SCAN case=needle_vs_doc_vector ... PASS
SCAN case=match_at_0             got=0        want=0        PASS
SCAN case=match_at_1234          got=1234     want=1234     PASS
SCAN case=no_match               got=-1       want=-1       PASS
SCAN case=window_edge_in_4064    got=4064     want=4064     PASS
SCAN case=window_edge_out_4065   got=-1       want=-1       PASS
SCAN case=window_edge_out_full   got=4065     want=4065     PASS
SCAN case=partial_31_of_32       got=-1       want=-1       PASS
SCAN case=flip_1bit_no_match     got=-1       want=-1       PASS
SCAN case=short_window_31        got=-1       want=-1       PASS
SCAN case=first_of_two_matches   got=0        want=0        PASS
SCANV3 case=bytewise_two_hits hits=2 first=0 last=132 stored=2 trunc=0 PASS
SCANV3 case=split_16_16 hits=1 first=10 stored=1 PASS
SCANV3 case=trunc_cap3 hits=5 stored=3 trunc=1 first=20 last=380 PASS
SCANV3 case=short_streams hits0=0 hits31=0 PASS
SCANV3 seed=0 n=1048576 chunks=263 inj=40 hits=40 first=56252 last=1030735
SCANV3 random_equiv ok=20/20 want=20/20 PASS
SCAN_SELFTEST PASS checks=16 fails=0
```

### 3.3 M⁸ 逐位等价【已证】

```
EQUIV p7b_tcp_churn_v3: table_rebuild bad=0/4096 want=0 MATCH
EQUIV p7b_tcp_churn_v3: long n=8388613 seq=(-1,0,0x19CFF6A4002170D8) lane8=(-1,0,0x19CFF6A4002170D8) ctor_oracle=0x19CFF6A4002170D8 MATCH
EQUIV ... inj[0] 首字节 off=0 cnt=1 seq=(0,1) lane8=(0,1) state_eq=1 MATCH
EQUIV ... inj[1] 非 8 对齐单 bit off=12345 cnt=1 seq=(12345,1) lane8=(12345,1) state_eq=1 MATCH
EQUIV ... inj[2] 8 对齐块首整字节 off=65536 cnt=1 seq=(65536,1) lane8=(65536,1) state_eq=1 MATCH
EQUIV ... inj[3] 块尾 (i+7) off=65543 cnt=1 seq=(65543,1) lane8=(65543,1) state_eq=1 MATCH
EQUIV ... inj[4] 尾段最后一个字节 off=8388612 cnt=1 seq=(8388612,1) lane8=(8388612,1) state_eq=1 MATCH
EQUIV ... inj[5] 3 个相邻字节 off=100 cnt=3 seq=(100,3) lane8=(100,3) state_eq=1 MATCH
EQUIV ... xblk L=1048579 blocks=11 states=12/12 seq=(-1,0,0x13C199A4F551A1A4) lane8=(-1,0,0x13C199A4F551A1A4) MATCH
EQUIV ... dispatch seq=(-1,0) lane8=(-1,0) mode_name=lane8 direct_lane8=-1 MATCH
EQUIV p7b_tcp_churn_v3: PASS (checks=10 fail=0)
```

⇒ **lane8 与 seq 在长序列（8,388,613 B，非 8 对齐）、6 种注入、跨块 12 个中间态、
分派开关上逐位相同**（first_mismatch / mism_bytes / 末态三全等）。

### 3.4 校验器自检【已证】

```
VERIFY inv_init rows=64 basis=64 rand=1000 OK (B[0]=0x5088A2A8011EB0B6)
VERIFY clean chunk=1 n=65541 seq=(0,-1,-1,65541,0) lane8=(0,-1,-1,65541,0) state_eq=1 PASS
VERIFY clean_all ok=12/12 PASS
VERIFY inj single_bit_flip      off=12345   seq=(1,12345,12345) lane8=(1,12345,12345) PASS
VERIFY inj restart_to_offset0   off=100000  seq=(1,100000,100000) lane8=(1,100000,100000) PASS
VERIFY inj phase_jump_to_5000   off=200000  seq=(1,200000,200000) lane8=(1,200000,200000) PASS
VERIFY garbage budget=65536 seq=(deg=1,proc=65536,breaks=0) lane8=(deg=1,proc=65536,breaks=0) PASS
VERIFY_SELFTEST PASS checks=18 fails=0
SELFTEST_ALL PASS
```

解读（只讲读数，不裁定）：
* 干净流 12 种 chunk（1..1,048,576）⇒ 0 断点、`processed` = 输入长度、seq/lane8 末态相同；
* 单 bit 翻转 @12345 ⇒ **1 个断点 @12345**（两模式相同）；
* 重启到偏移 0 @100000 ⇒ **1 个断点 @100000**；
* 相位跳到偏移 5000 @200000 ⇒ **1 个断点 @200000**（该段由同一 LFSR 从偏移 5000 生成；
  ⚠️ 本自检**没有**用针扫描器复核"该段无针"，"无针"是按生成器语义的推断，不是本格的实测）；
* 非图案数据 + 预算 65536 ⇒ `vdegraded=1`、`processed=65536`（两模式相同）。

### 3.5 边界与 `--help`【已证】

17/17 条 v2 非法值 `rc=2 + stderr 非空`（原文 `selftest/boundary_checks.txt`，摘要）：

```
BAD interval0 rc=2 ... PASS   BAD intervalneg rc=2 ... PASS   BAD seconds0 rc=2 ... PASS
BAD rcvbuf_lo rc=2 ... PASS   BAD rcvbuf_hi rc=2 ... PASS     BAD prefixkb0 rc=2 ... PASS
BAD scan31 rc=2 ... PASS      BAD scan_toobig rc=2 ... PASS   BAD port0 rc=2 ... PASS
BAD localport_hi rc=2 ... PASS BAD dumpmax_neg rc=2 ... PASS  BAD maxconns0 rc=2 ... PASS
BAD hold_neg rc=2 ... PASS    BAD host_bogus rc=2 ... PASS    BAD dumpdir_miss rc=2 ... PASS
BAD unknown_arg rc=2 ... PASS BAD missing_val rc=2 ... PASS
BAD_SUMMARY_LEGACY PASS=17 FAIL=0
```

7/7 条 v3 新非法值同样 `rc=2`（`BAD_SUMMARY_V3 PASS=7 FAIL=0`）；
`HELP_RC=0 help_grep=3`；四条自检入口单独跑均 RC=0。

### 3.6 过程纪律（如实登记）

* **未发网络包、未碰板、未烧录、未碰 `/dev/xdma*`**；自检代码路径在 `main` 的参数解析之后就
  返回（`--selftest*`），不创建 socket。
* 对端当时有**另一条工作线的板级实验**（`p7b_tcp_sink --rcvbuf 2920 ...` + `tcpdump zw_...`）。
  最终编译与 `--selftest-all` 是在 `ps` 核对 **BUSY_CHECK=0** 的安静窗口里执行的；17 条边界
  检查同样先核对 `BUSY_CHECK=0`。⚠️ **第一次** `--selftest-all`（pre-fix 版）是在该实验已启动
  后跑的（CPU-only、自动绑核到 CPU 7），特此登记——它没有网络行为，但确实与实验共享了机器。
* 编译在独立目录 `/tmp/p3_tool_v3_20261017/`。`/tmp/p7b_biz/`（现役部署）**未写**。

---

## §4 未测 / 未判定 / 未定位（不许读成已收口）

| # | 项 | 状态 | 说明 |
|---|---|---|---|
| U1 | v2 的 56/77 条 socket 判据（T1–T5/T1b + E1/E2） | **【未测】** | 派单禁止任何网络收发；v3 只是 v2 的逐字路径 + 追加扫描调用。下一轮板级前应在允许的窗口重跑这两套门 |
| U2 | 板级行为 | **【未测】** | 本轮零板级、零烧录 |
| U3 | `--scan-all 1` 对 765 MB/s 读速的影响 | **【未测】** | 设计件 §5-U7 原样挂账；工具内有 `scanned=`/`CHURN_T scan_hits=` 可观测，但未做吞吐 A/B |
| U4 | `--verify-stream 1` 在真实板级速率下的 CPU 成本 | **【未测】** | 默认关；开启后的读速/事件率影响未知 |
| U5 | 33,000 连接 × 默认 64 KB 前缀的内存峰值 | **【未测】** | 上界已算（§1.4），未实测；长臂建议按 C1b2 实际下调 `--prefix-kb` |
| U6 | 32 B 针在干净非零相位流中的**数学唯一性** | **【未判定】** | 未证明；只有"两扫描器列表逐位相同（20×1 MiB）"与历史 0 误报 |
| U7 | 校验器断点偏移 = **首次失配**，不是严格相位切换点 | **【未判定】** | 前导字节恰好相同会晚几字节；重启的精确位置用针扫描 |
| U8 | 设计件 §4.1-B 的**末 64 KB 环形 dump**（`--tail-kb`/`--dump-tail-dir`） | **【未测/未实施】** | 本件只做 A（全流滚动针）。v3 **没有**这两个参数（传了会 `unknown arg` ⇒ RC=2，响亮）；候选的首 64 KB 仍由 v2 的 `--dump-prefix-dir` 落盘 |
| U9 | 设计件 §4.2 的离线分类器 `p3_sep.py` | **【未测/未实施】** | 不在本件范围；v3 只负责给出 `hits/first_needle/last_needle` 与 `CHURN_NEEDLES` 偏移列表 |
| U10 | Q2-A 的 2/40 复现与分类 | **【未测】** | 需要板级 300 s 臂 + 前持有者全流扫描，下一轮 |
| U11 | `vscanned` 的"检查"与"验证"区分 | **【已证（定义）】** | 断点后的 resync 段只算检查过；下游不得把 `vscanned` 当"已验证字节数" |
| U12 | `needle_trunc=1` 时的偏移列表 | **【已证（定义）】** | `hits` 计数仍完整；列表只到 `needle_max` 条。Q2 若只看 `last_needle`，需确认 `hits <= needle_max` 或 `trunc=0`，否则 `last_needle` 仍正确但中间偏移不全 |
| U13 | `--maxbytes 0` 坑 | **【已证（文档）】** | v3 **没有** `--maxbytes`；未知参数 ⇒ RC=2。不要从 `p7b_tcp_sink` 照搬"0 = 无限"的直觉 |
| U14 | `--seconds` 不终止已建连接 | **【已证（v2 语义）】** | 只停新建；退出时内核会对每条已建立连接发 1 个 FIN。真臂用 `--hold-s` 留窗 |
| U15 | `cmd /c` vs `cmd //c` 条件式陷阱 | **【已证（v2 轮）】** | Git Bash 下未加 `MSYS_NO_PATHCONV=1` 时 `/c` 被改写 ⇒ bat 静默不执行；判据 = mtime + 本次独有串；`MSYS_NO_PATHCONV=1` 与 `cmd //c` 并用会互相抵消 |
| U16 | 校验器对"非图案但恰好 17 B 可验证"的流 | **【未测】** | 理论误同步率约 2⁻⁷²；未构造对抗样本 |

---

## §5 部署与运行命令（下一轮板级用）

### 5.1 部署 + 编译（对端 `/tmp/p7b_biz/`；**不要**覆盖现役 v2）

```bash
P=/c/Users/zhxue/anaconda3/python.exe
B=D:/repo/XCKU5PMini/udp_hls_10g
# 0) 现役头文件指纹先核（应与 BUILD.md §3 一致；不一致先停）
$P tools/peer_ssh.py "md5sum /tmp/p7b_biz/p7b_pattern.h /tmp/p7b_biz/p7b_affinity.h /tmp/p7b_biz/p7b_io.h"
#    期望: b2f2e962… / b0322279… / 62b1257d…
# 1) 只上载新 .cpp（文件名必须保持 p7b_tcp_churn_v3.cpp）
MSYS_NO_PATHCONV=1 $P tools/peer_ssh.py --put \
  "$B/_proj_pcie/p7b_biz/p7b_tcp_churn_v3.cpp" /tmp/p7b_biz/p7b_tcp_churn_v3.cpp
# 2) 编译（BUILD.md §2 唯一口径）
$P tools/peer_ssh.py "cd /tmp/p7b_biz && g++ -O3 -pthread -o p7b_tcp_churn_v3 p7b_tcp_churn_v3.cpp"
# 3) 对指纹（源 44ccdb9a… / 产物 5ffab696…，203304 B）
$P tools/peer_ssh.py "md5sum /tmp/p7b_biz/p7b_tcp_churn_v3.cpp /tmp/p7b_biz/p7b_tcp_churn_v3"
```

⚠️ `peer_ssh.py --put/--get` 在 Git Bash 下需要 `MSYS_NO_PATHCONV=1`（本轮实测：不加时
`--put` 报 `FileNotFoundError`）。⚠️ 产物 md5 依赖**源文件名**（`.symtab` 的 `STT_FILE`）⇒
不要改名后再比 md5。

### 5.2 Q2-A 主臂（0x24 / C1b2 逐字参数 + v3 全流扫描）

```bash
ulimit -n 65536                      # C1b2 口径；120 s 至少 16384
mkdir -p /tmp/c1_dump_Q2A
/tmp/p7b_biz/p7b_tcp_churn_v3 --host 192.168.100.2 --port 8080 \
    --connect-interval-ms 10 --rcvbuf 1048576 --seconds 300 \
    --max-conns 33000 --dump-prefix-dir /tmp/c1_dump_Q2A --dump-max 8192 \
    --hold-s 5 \
    --scan-all 1 --needle-max 64 \
    > /tmp/c1_Q2A_churn.txt 2> /tmp/c1_Q2A_churn.err
```

### 5.3 M⁸ 相位连续性臂（可选，与 5.2 二选一或同轮分开）

```bash
/tmp/p7b_biz/p7b_tcp_churn_v3 ...（同上）... \
    --scan-all 1 --needle-max 64 \
    --verify-stream 1 --check lane8 --verify-degrade-bytes 1048576 --break-max 16
# 对照臂：--check seq（同参数，仅换引擎）
```

### 5.4 读数解析

```bash
# 每连接一行（既有字段 + 追加字段；新字段从 CPU_FREQ_KHZ= 之后开始）
grep '^CHURN conn=' /tmp/c1_Q2A_churn.txt | head -3
# 有针连接的完整偏移列表
grep '^CHURN_NEEDLES ' /tmp/c1_Q2A_churn.txt | head
# 校验器断点列表（仅 --verify-stream 1）
grep '^CHURN_VBREAKS ' /tmp/c1_Q2A_churn.txt | head
# 汇总
grep '^CHURN_SUM' /tmp/c1_Q2A_churn.txt
```

Q2 判据要用的三个量（每连接）：`bytes=`（P/C 的流长度）、
`hits=` + `scan_state=`（全流无针）、`last_needle=`（P 的最后重启偏移）。
`CHURN_NEEDLES` 给出全部（至多 `needle_max` 条）偏移。

### 5.5 已知坑（逐条）

* **`--maxbytes 0`**：v3 没有这个参数；未知参数 = RC=2。`p7b_tcp_sink` 的"0 不是无限、
  是立即退出 RC=1"不要照搬。
* **`--seconds`**：只停新建连接；不终止已建连接。退出时内核会对每条已建立连接发 1 个 FIN
  （真臂用 `--hold-s` 给板侧收数留窗）。
* **`cmd /c` vs `cmd //c`（条件式）**：Git Bash 下未加 `MSYS_NO_PATHCONV=1` 时 bat 静默不执行，
  你读到的 stdout 可能是上一 session 的陈旧件；判据 = **mtime + 本次独有字符串**。
  `MSYS_NO_PATHCONV=1` 与 `cmd //c` 并用会互相抵消。
* **`hits==0` 只在 `scan_state=full` 时有意义**；`short/none/off` 是**判不了**，不是"无重启"。
* **`needle_trunc=1`**：偏移列表不完整；`hits` 计数仍完整，但"中间每次出现"需 `trunc=0`。
* **`vdegraded=1`**：校验器在该连接上放弃了（预算耗尽）；针扫描结果仍独立有效；
  **不改变退出码**。
* **`vscanned`**：检查/搜索过的字节数，不是"已验证字节数"。

---

## §6 证据地图

| 件 | 内容 |
|---|---|
| `_proj_pcie/p7b_biz/p7b_tcp_churn_v3.cpp` | 源码（78,239 B / md5 `44ccdb9a…`） |
| `_proj_pcie/p7b_biz/p7b_tcp_churn.cpp` | v2（**未动**；md5 `388cd5d4…`） |
| `selftest/selftest_all_fixed.txt` | `--selftest-all` 原文（图案/扫描/等价/校验器） |
| `selftest/boundary_checks.txt` | 17 条 v2 + 7 条 v3 非法值 RC=2、`--help`、四条自检入口 原文 |
| `selftest/help_v3.txt` | `--help` 原文 |
| `env/env_build.txt` | 编译机/g++/命令/md5/尺寸 原文 |
| `env/wall_check.txt` | `-Wall -fsyntax-only` 原文（RC=0，无告警行） |
| `_proj_10g/notes/p9_p3_boost_design_20261017/README_FOR_TL.md` | Q2 规格 §4.1-A（本件的上游） |
| `_proj_10g/notes/p9_c1_churn_tool_20261017/README_FOR_TL.md` | v2 的 77 判据与 ERRATA（本件的对照基线） |
| `_proj_10g/notes/p9_c1_board_20261017/README_FOR_TL.md` | C1 板级两代臂（Q2 的候选来源） |
| `_proj_10g/notes/p7b_affinity/BUILD.md` | 编译配方（`g++ -O3 -pthread`） |

—— 完（本件 = 工具实施 + 自检件；板级 Q2-A/Q2-B 的排期与判据层裁定权在 TL/用户）
