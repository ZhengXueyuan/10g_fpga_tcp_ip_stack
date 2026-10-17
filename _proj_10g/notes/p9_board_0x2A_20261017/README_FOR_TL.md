# p9_board_0x2A_20261017 —— 0x2A 孤儿修复板级验证轮

> 件名 `_proj_10g/notes/p9_board_0x2A_20261017/README_FOR_TL.md` · 日期 **2026-10-17** · 施工窗口 ~14:44–15:32 CST
> 板 = XCKU5P Mini（KU5P）· 对端 = 192.168.0.38（Ubuntu 24.04，内核 7.x）· 4 次 JTAG 易失烧录 · **QSPI 零写入**
> 依据：`p9_orphan_fix_design_20261017/README_FOR_TL.md`（v4.1）· `p9_orphan_impl_20261017/README_FOR_TL.md`（F1 自愈）· `p9_build_0x2A_20261017/README_FOR_TL.md`（构建/身份）
> ⛔ **本件不下 PASS/FAIL 裁定**；状态词 = **【已证】/【未判定】/【未定位】/【未测】**。板级身份门读数照录。

---

## §0 一句话结果（先读这一节）

1. **0x2A 正臂【已证】`ΔW75 = +1`**，点火时刻 **t_rel = 61.68 s**（DROP 后；设计阈值 61.85 s，差 0.17 s ≈ 0.4 个 tick），**两次独立正臂**（B_POS 单边 DROP、B_POS2 **双向 DROP**）都命中；点火后**新连接 802.2 Mbps / 200 MB / `mism_bytes=0`**，槽恢复【已证】。
2. **0x28 负臂【已证】不回收**：无 W75；`W55` 在 DROP 后 **0.47 s 内 +20 然后 144 s 完全不变**；`W51/W52` 冻结；旧连接解除 DROP 后 **0 B/5 s**；槽保持占用。
3. ⛔ **与派单的一处实质不符（必须读）**：**总黑洞不产生"20 ms 周期重放不止"** —— 板在 DROP 后只重传 **16–21 个会话（约 0.35–0.47 s）** 即静默；`ΔW55` 在 130 s 窗内**不持续增长**。见 §2.3。**这改变了负臂的签名，但不改变正臂的判别力**（判别靠 `ΔW75` + 槽恢复，不靠 pcap 重放）。
4. **回归四臂全部 `ΔW75 = 0`**：C-fast 801 Mbps / C-basin 1.55 Mbps 爬行（141 s）/ C-zero-window 200 s（persist 60 s 档可见，恢复 891 Mbps）/ C-churn 12,000 连 120 s。
5. **收尾 = 0x28 现役**（BID 0x28 / 75 字 / `0x15C=ffffffff`）+ `0x08=0` + carrier=1；iptables 三条策略行、无规则；对端无残留。**0x2A 的"现役"资格按派单留用户裁定**（本轮已按 S9 烧回 0x28）。收尾健康探针：**0x28 上 8 MB / 0.092 s / 735.3 Mbps / mism=0**（`env/FINAL_HEALTH_PROBE.txt`）。

---

## §1 身份门（两代都核）

| 项 | 0x28（负臂基线） | 0x2A（正臂） |
|---|---|---|
| `0x00` MAGIC | **0x50360001** | **0x50360001** |
| `0x04` BID | **0x00000028** | **0x0000002a**（工具做大小写归一⇒ID_OK） |
| 快照字数 | **75**（`W0..W74 @0x20..0x148`） | **76**（`W0..W75 @0x20..0x14C`） |
| 未实现地址 | **`0x15C` = 0xffffffff** | **`0x160` = 0xffffffff** |
| `0x15C` 语义 | 未实现（SLVERR） | **MIR_DMA_CNT 真字**：现读 **0x00000000**（不是 ffffffff） |
| 窗口全扫 NFF | **0**（75 字） | **0**（76 字） |
| `0x14` MARKER | 0xdeadbeef | 0xdeadbeef |
| `0x08` SCRATCH | **0** | **0** |
| CARRIER | **1** | **1** |
| LnkSta | 5GT/s **x4**（downgraded） | 5GT/s **x4** |
| BARs | **2**（`identify_bars` config 1 / user 0） | **2** |

- 0x28 身份门在 **入口（未烧前）**、**烧 0x28 后**、**收尾烧回 0x28 后** 共核 3 次，全 `ID_OK`。
- 0x2A 身份门在 **两次 0x2A 构建烧录后** 各核 1 次（B 臂前 / C-零窗前），全 `ID_OK`；`0x15C` 两次都是 0x00000000。
- 每次烧录后都做了 **PCIe 设备级 `remove`+`rescan`**（两次日志均 `LnkSta x4` + `2 BARs` + `/dev/xdma0_user` 在位）；未触发根端口级升级。
- ⚠️ **0x2A 只有一个独立锚**：`p9_build_0x2A_20261017/build/wrapper_p4.bit`（sha256 **`aa44a0ed…a3b6`**，15,431,261 B）；盘上**没有**第二份独立来源。烧前核了该锚 = 期望值，烧前把本地副本写入 `burn/wrapper_p4_0x2A.bit` 并**再核 sha**（该副本不是独立锚，仅作本轮归档）。派单要求的"双锚"对 0x2A **部分满足**（0x28 是双独立锚，逐字相等）。

---

## §2 A/B 两臂（孤儿负/正）

### 2.1 构造（两段共用）

- 单 sink（`p7b_tcp_sink`，`--rcvbuf 2920 --conns 1 --check lane8`）先跑快，实测 **803.9 / 813.8 Mbps**（≥700 门槛）持续 ~1–2 s。
- **对端 iptables 双向 DROP 该连接四元组**：`-I INPUT … 192.168.100.2:8080 → 192.168.100.100:<port>`；`-I OUTPUT … 192.168.100.100:<port> → 192.168.100.2:8080`。
- sink 进程**保持存活不 close**（`--poll-ms 1000 --stall-n 500`）；观测 **140 s**（>2×LIM=123.7 s）。
- 观测后删规则、核 `iptables -S` 与基线逐字相同；然后做 5 s **RESUME_PROBE**（旧连接是否恢复）。
- 正臂另加 **B2**：杀旧 sink，用新 sink（新四元组）建连并跑 200 MB。

### 2.2 读数对比表

| 量 | **A 段 0x28 负臂**（A_NEG2） | **B 段 0x2A 正臂**（B_POS2） |
|---|---|---|
| DROP 端口/速率 | 53810 / 803.9 Mbps | 45740 / 813.8 Mbps |
| iptables 规则 | **INPUT 规则在位；OUTPUT 规则 ADD RC=2**（缺 `-p tcp`，见 §7-D1） | **INPUT + OUTPUT 两条都在位（RC=0/0）** |
| `W55` 起点→终点 | **17 → 38**（Δ=+20） | **17 → 34**（Δ=+17） |
| `W55` 时间分布 | 全部在 DROP 后 **0.47 s 内**（+8/+7/+1）；之后 **144 s 恒 38** | 全部在 DROP 后 **0.35 s 内**（+1/+8/+7）；之后 **140 s 恒 34** |
| `W75` | **不存在（0x28 无此字）** | **1 → 2（Δ=+1）**，点火在 **t_rel = 61.68 s** |
| `W51/W52` | DROP 后冻结：`0x11d37564 / 0x3202c`，140 s 不变 | DROP 后冻结：`0x11daad0c / 0x32170`，140 s 不变 |
| 旧连接 RESUME_PROBE | **0 B / 5 s**（不恢复） | **0 B / 5 s**（不恢复；回收已生效） |
| pcap（DROP 后旧四元组） | 6,554×1460 B 数据 + **16 个 20 ms 间隔包**；跨度 **0.407 s**；之后静默；板侧 FIN/RST=0 | 6,632×1460 B + **16 个 20 ms 间隔包**；之后静默；板侧 FIN/RST=0 |
| B2 新连接 | 未做（派单 A 段不做） | **SINK_CONN 0 OK**：802.218 Mbps / **200,001,020 B** / 1.994 s / `first_mismatch=-1` / **`mism_bytes=0`** |
| `W71/W73` | — | PRE 1/1 → POST 3/3（孤儿臂自身 ev_up + 新连接 ev_up） |
| iptables 收尾 | `IPTABLES_CLEAN_OK`（post==pre） | `IPTABLES_CLEAN_OK`（post==pre） |
| DROP 后 `ΔW75` | —（无此字） | **+1**；新连接后仍 = 2（不重复点火） |

- **正臂两次独立重复**：B_POS（INPUT-only，§7-D1）`ΔW75=+1`（POST W75=1）；B_POS2（双向 DROP）`ΔW75=+1`（POST W75=2）。两次点火都在 **~61.7–61.9 s**。
- **负臂两次**：A_NEG（sink 15 s 后因默认 `stall-n 3` 自己关了；FIN 被 OUTPUT 规则挡住/被 pcap 记为 P2B FIN 重传；已作废为"构造 v1"）与 **A_NEG2（sink 全程存活，主臂）**。A_NEG2 的 `ΔW55=+20`、冻结与 A_NEG 同形。
- ⚠️ **A_NEG2 的 OUTPUT 规则没装上**（`ADD_OUTPUT_RC=2`，`DEL_OUTPUT_RC=2`；原因=规则缺 `-p tcp`）。**对本臂的影响**：板→对端数据被 INPUT DROP 截断，对端收不到数据 ⇒ 不产生新 ACK；sink 存活、未发 FIN/RST；所以"板侧收不到 ACK"这一孤儿条件**成立**。但构造不是派单要求的严格双向 DROP ⇒ 按 **【已证（输入方向 DROP）】+ 构造偏离** 登记。**正臂 B_POS2 用双向 DROP 复现了 `ΔW75=+1`**，所以主结论不受该偏离影响。

### 2.3 ⛔ 与派单描述不符的一条（核心）

派单写"观测 >130 s：`ΔW55`（重放/RTO 计数）**持续增长**（旧行为=不回收）；pcap 可见 **20 ms 周期重放不止**"。

**实测不符**：在**总黑洞**（双向 DROP）下，板只重传 **16–21 个会话**（`W55` +17/+20）就**静默**；之后 140 s 内 `W51/W52/W55` 全冻结。
- pcap 直接读数（A_NEG2 / B_POS2 同形）：DROP 后先有 **6,554 / 6,632 个 1460 B 数据包**（这是 DROP 前最后一小段快相的尾巴，跨度 ~0.4 s），其中 **16 个包以 ~20 ms 间隔**发出；**此后到 140 s 无任何板侧数据包**。
- 因此"20 ms 周期重放不止"在本构造下 **【未观测到】**；`ΔW55` 在 130 s 窗内 **【已证】不增长**（只在头 0.5 s 增长）。
- **负臂的真实签名** = **不回收 + 槽静默卡死**（不是"永久重放"）。正臂的判别力来自 **`ΔW75=+1`（61.68 s）+ 槽恢复**，不依赖 pcap 重放；**pcap 在本构造下对 A/B 无判别力**（两臂的重放都在 ~0.4 s 就停了，远早于 61.85 s 的回收）⇒ "pcap 可见回收后重放停止"这一格按 **【未判定】**（因为回收前重放已经停了）。

### 2.4 F1「下一次 ADD 自愈」观测

- 正臂回收后：旧连接 **0 B/5 s**（TCB state=0 + CAM 清 ⇒ 不再发旧四元组）。
- **新连接（B2）802.218 Mbps / 200 MB / `mism_bytes=0` / 2.0 s** ⇒ **槽可用【已证】**；图案从连接首字节正确（`first_mismatch=-1`）⇒ app 的换流没有把旧会话相位带进新连接。
- `W71`/`W73` 各 +2（孤儿臂连接的 ev_up + 新连接 ev_up）；`W75` 新连接后保持 2（不重复点火）。
- ⚠️ **app 内部 `closing/active` 没有直接读数**（快照无此字）⇒ "`closing` 被新 ADD 清掉"是**行为面**（新连接收数据正确）【已证】；内部寄存器状态 **【未测】**。

---

## §3 C 段回归（0x2A）

| 臂 | 时长/构型 | 主读数 | `ΔW75` |
|---|---|---|---|
| **C-fast** | 30 s；单 sink `2920/c1/lane8` | ss 逐秒 **784.7–813.3 Mbps，中位 801.2，均值 799.9**（26 个采样）；`W55` 30 s 内 +9（正常重传） | **0** |
| **C-basin** | 140 s；2 sink / stagger 0.4 / `2920/c6/poll1000/stall500` | pcap：**27,283,020 B 载荷 / 140.4 s = 1.554 Mbps**（爬行）；IAT **37.3% 落 15–25 ms**（20 ms 簇）；`W55` 10 s 桶 **490–499（49–50/s）** | **0**（141 s 环） |
| **C-zero-window** | 200 s；sink 建立后 **SIGSTOP**（socket 不 close，内核回 win=0），`rcvbuf 2920` | 窗口内 pcap：**7 × 1 B persist 探询** + 78 × 1460 B 残余；**85 个对端 ACK**；IAT p99 = **60.000085 s**（60 s 封顶）；探询落在 **~15/35/75/135/195 s**（连接起算）；SIGCONT 后 **1,114,354,640 B / 10 s = 891 Mbps** | **0**（200 s） |
| **C-churn** | 120 s；C1 构型 `p7b_tcp_churn`（interval 10 ms / rcvbuf 1 MiB / max-conns 16000 / hold 5；**ulimit 16384**） | `CHURN_SUM`：**12,000 连 / 136 estab / connfail=0 / 9.15 GB / 100 conn/s**；候选 16（off0=25 / offk=4）；pcap **35,327,593 包、0 dropped**；末 16.2 s 板侧 **FIN/RST = 0** | **0** |

- **C-basin 的"盆在场"见证**：C_BASIN v1（入口臂，`stall-n 3`）第一条连接 **42.76 MB 快相后崩**，其后各连接 0.25–0.51 MB（0.33–0.45 Mbps）并在 ~3–9 s 判 STALL；sink2 conn0 = **0 B**。C_BASIN v1 的 141 s 环同样 `ΔW75=0`。C_BASIN2 用 `stall-n 500` 让 sink 存活整 140 s，pcap 的 **1.554 Mbps / 20 ms 簇 / W55 50/s** 与历史慢盆签名逐项同形。
- **盆的清除**：C_BASIN 后的一次 8 MB 探针 **60 s 超时**（快探针只需 0.1 s）⇒ 盆在场；**重烧 0x2A** 后快探针 **0.103 s / 652 Mbps** ⇒ **重烧清除【已证】**（与 `p9_slowbasin_gc_20261017` 的结论一致）。
- **C-zero-window 的 60 s 档**：p99 IAT **60.000085 s** 是直接读数（两次 60 s 间隔：75→135 s、135→195 s）。阈值 180.39 s 未被触发 ⇒ `ΔW75=0` 不构成"阈值余量已证"（只证明本 200 s 窗内未误杀）。
- **C-churn 的 ulimit**：v1 未抬 `ulimit -n`（soft=1024）⇒ EMFILE、只 1,021 连；**v2 抬到 16384** 后 12,000 连、connfail=0。v1 作废，v2 为主臂。
- **C-churn 前的盆见证（没有单独探针）**：依据 = 紧邻的 C_ZEROWIN2 单连恢复 **891 Mbps / 10 s**（盆在场时小窗单连会爬 ~1.5 Mbps）+ churn 本身是 **1 MB 大窗构型**（`p9_slowbasin_gc` 实测盆内免疫）。按"每臂前核盆不在场"的严格字面，**这一格缺一次独立二值探针**，如实登记为【已证（间接）/ 未单测】。C_BASIN 之后的重烧清除已由 C2_PROBE（0.103 s / 652 Mbps）直接见证。
- **pcap 三硬门**：各臂 `TCPDUMP_ARMED` + 优雅停止 + **`0 packets dropped by kernel`** 全部在位；orphan 臂用 DROP 时刻 swap 出的 `replay.pcap`（小文件），basin/zero/churn 用整窗 ring。
  - ⚠️ **C-churn 的 pcap 是 4 文件 ring（~950 MB）**；本轮只解析了**最后 16.2 s**（`pcap3`）的 FIN/RST=0。退出瞬间的 FIN 洪泛在 ring 之外 —— 与历史轮同款覆盖边界，登记。

---

## §4 iptables 快照与清理（本轮关键工具）

- 对端：`iptables v1.8.10 (nf_tables)`；**入口基线 = 仅三条默认策略行**（`-P INPUT/FORWARD/OUTPUT ACCEPT`，无规则）。
- 每次 DROP 前落 `iptables -S` 快照（`raw/*_iptables_pre.txt`），DROP 后落（`*_post.txt`），清理后落（`*_clean.txt`）并 **`diff pre clean`**：
  - A_NEG：clean OK；A_NEG2：clean OK；B_POS：clean OK；B_POS2：clean OK；C 段四臂不装规则，收尾前/后均核 `-S` 干净。
  - **最终现读**：`env/FINAL_LIVE_READ.txt` = 三条策略行、无规则。
- **D1 偏离（必须看）**：OUTPUT 规则第一版**缺 `-p tcp`** ⇒ `iptables -I OUTPUT … --sport` 报 `unknown option "--sport"`，ADD/DEL 都 RC=2；**A_NEG、A_NEG2、B_POS 三臂实际只有 INPUT 方向的 DROP**。**已在 B_POS2 前修复**（`-p tcp` 加进 ADD 与 DEL），B_POS2 与之后所有臂都是双向（或无需）规则。**A_NEG2 的负臂结论仍成立但构造按"单边 DROP"读**。
- 收尾状态：**无规则、无残留、`ss` 8080 established = 0**（最终读；`FINAL_LIVE_READ.txt` 里的那一行 `ss` 因引号被 sudo 层改写报了 `RTNETLINK Invalid argument`，随后用臂脚本同款写法复核为 0，见 `env/FINAL_SS_RECHECK.txt`）。

---

## §5 观测几何与读侧

- 快照工具 = `/tmp/b2a_snap.sh`（**本轮部署的 76 字版**；md5 `7d74e14d…d502`，与本地 `_proj_pcie/p7b_biz/p7b_snap.sh` 逐字相同）。对端 `/tmp/p7b_biz/p7b_snap.sh` 是 **Oct-16 的旧版**（md5 `a257af82…`，默认 75/0x28），**本轮没有覆盖共享工具**；读 0x2A 时全部显式传 `NW=76 EXPECT_BID=0x2A UNIMPL_ADDR=0x160`。
- 0x2A 的 KW = `5 20 43 51 52 55 63 64 71 72 73 74 75`；0x28 的 KW 同前、去掉 75。
- 身份/窗口读数：0x2A 76 字全扫 **NFF=0**；`0x160=ffffffff`；`0x15C=MIR_DMA_CNT=0x00000000`。
- 每臂的 `SNAP_PRE` 在环启动前显式取、`SNAP_POST` 在环停止后取；**环的每点都带 `SNAP_T` 时间戳**（解析器 `tools/parse_snap.py`），点火时刻用环的 `W75` 增量定位。

---

## §6 证据索引（本目录）

```
README_FOR_TL.md            本件
FINAL_STATE.txt             收尾态（0x28 + 0x08=0 + carrier=1 + iptables/进程/工具 md5）
burn/                       burn_round_b2a.sh + 4 次 BURN_*.txt + 两份位流（0x28 双锚、0x2A 单锚+本地副本）+ stdout 副本
runs/                       各臂 stdout（A_NEG/A_NEG2/B_POS/B_POS2/C0/C1/C2_PROBE/C_FAST/C_BASIN/C_BASIN2/C_ZEROWIN/C_ZEROWIN2/C_CHURN/C_CHURN2 + 4 次烧录驱动日志）
raw/                        各臂 snap.log / pre / post / ss.log / sink*.txt / nstat / iptables / replay.pcap（orphan）/ ctl.pcap（basin、zero-window 切片、churn 不在此，太大）
env/                        FINAL_LIVE_READ.txt + FINAL_SS_RECHECK.txt + 入口环境见证
tools/                      b2a_snap.sh（部署副本）· b2a_arm.sh（对端臂脚本）· parse_snap.py · parse_pcap.py · slice_pcap.py
```

- 文件名前缀规则：本地 `A_NEG*` / `B_POS*` / `C_*`；对端 `/tmp/b2a_<TAG>_*`。
- `raw/` 没放 churn 的 ~950 MB ring；需要时可从对端 `/tmp/b2a_C_CHURN2_ctl.pcap{0..3}` 取（FINAL_STATE 记录了对端路径）。
- 关键原始读数直接可从 `runs/*_stdout.txt` 复算（地址/命令逐行在 stdout 里）。

---

## §7 偏离 / 未判定 / 未定位（如实）

### D1（构造偏离，已修）OUTPUT iptables 规则缺 `-p tcp`
- 影响臂：A_NEG、A_NEG2、B_POS（仅 INPUT DROP）；**B_POS2 起修复**。
- 负臂影响界：板收不到 ACK（对端收不到数据），孤儿条件成立；但非严格双向。正臂用 B_POS2（双向）复现 ⇒ **主结论不受影响**。
- 证据：`runs/A_NEG2_stdout.txt` 的 `ADD_OUTPUT_RC=2 / DEL_OUTPUT_RC=2`；`raw/A_NEG2_iptables_post.txt` 只有 INPUT 规则。

### D2（实质与派单不符）总黑洞下"20 ms 重放不止"【未观测到】
- 板只重传 16–21 个会话（~0.35–0.47 s）即静默；`ΔW55` 140 s 内不增长（见 §2.3）。
- 因此负臂签名改为"**不回收 + 槽静默卡死**"；"回收后 pcap 重放停止"这一格 **【未判定】**（回收前已停）。正臂判别 = `ΔW75` + 槽恢复。

### D3（工具/流程，已修）
- **sink teardown**：`run_sink` 用 `timeout` 包裹，`kill $SINKPID` 杀的是 timeout 不是 sink ⇒ A_NEG2 结束后残留一个 sink 进程（烧 0x2A 前的 pgrep 看到 3155394，`--seconds 260` 自己退出）。**修法** = teardown 加 `pkill -9 -x p7b_tcp_sink`；后续臂无残留。该残留**未影响任何臂读数**（它只挂在一条已死连接上），但按纪律登记。
- **C_ZEROWIN v1 无效**：`SIGSTOP` 打到了 timeout 进程，sink 继续读并跑完 2 GB（`ZEROWIN_RESUME=0` 是假象）。**C_ZEROWIN2** 改为直接启动 sink（无 timeout）⇒ 200 s 零窗 + 60 s persist 档 + 恢复 891 Mbps。
- **C_BASIN v1**：`stall-n 3` 让 sink 在 3–9 s 内自己判 STALL；环仍覆盖 141 s（`ΔW75=0`），但**主臂用 C_BASIN2**（`stall-n 500`，sink 存活整窗）。
- **C_CHURN v1**：`ulimit -n` 未抬 ⇒ EMFILE（1,021 连）；**C_CHURN2** 抬到 16384（12,000 连，connfail=0）。

### D4（锚点）
- 0x2A 位流**只有一个独立锚**（构建目录）；第二份是本轮 burn/ 的字节副本，**不是独立来源**。0x28 双独立锚通过。
- 0x2A 的"现役"资格：按 S9 已烧回 0x28；**0x2A 是否转正由用户裁定**。

### 未判定 / 未测
- **app 内部 `closing/active` 寄存器**：无快照字 ⇒ 自愈只有行为面证据（新连接 802 Mbps + `mism=0`）。
- **"回收后重放停止"**：不可判（重放早在 ~0.4 s 已停）。
- **阈值余量**：零窗臂只跑 200 s（覆盖 135→195 的 60 s 间隔），**未跑 B5c 单次丢失臂 / 361 s 死对端臂**（派单 C 段未要求）。
- **F6-a（`inflight==0` 空闲死对端）**：未测（设计件也未闭）。
- **0x28 负臂后的新连接/槽复用**：A 段未做（派单未要求）；只能从"W51/W52 冻结 + 旧连接 0 B/5 s + 无 W75"推断槽仍被占。
- **churn 退出瞬间（FIN 洪泛）的 pcap**：ring 之外的覆盖缺口，未测。
- **`W55` 在总黑洞下的语义**：本轮读到它只计 `svc_rewind` 的重传会话（17–21 次）并在 ~0.5 s 后停；**"板为何在 ~0.5 s 后停止重传"未定位**（RTO 退避/重试上限的具体分支未查）。
- **peer P2B FIN 污染**：B_POS2 的 pcap 里 `P2B_FIN=2` 可能是上一臂旧四元组的 FIN 重传（parser 只按端口 8080 统计，不分 ephemeral port）⇒ **FIN 计数不单独作判据**；板侧 B2P FIN/RST=0 是干净的。

---

## §8 复算入口

```bash
# 对端臂脚本（已在 /tmp/b2a_arm.sh；本地副本 tools/b2a_arm.sh）
# orphan 负臂（0x28）
MSYS_NO_PATHCONV=1 PYTHONIOENCODING=utf-8 PEER_PW=... \
  /c/Users/zhxue/anaconda3/python.exe tools/peer_ssh.py --timeout 320 --sudo \
  "bash /tmp/b2a_arm.sh <TAG> 0x28 orphan"
# orphan 正臂（0x2A，含 B2 新连接）
... "RECOVER=1 bash /tmp/b2a_arm.sh <TAG> 0x2A orphan"
# 回归
... "DUR=30 MB=4000000000 SECS=150 bash /tmp/b2a_arm.sh <TAG> 0x2A fast"
... "DUR=140 NSINKS=2 STAGGER=0.4 RCVBUF=2920 CONNS=6 EXTRA='--poll-ms 1000 --stall-n 500' bash /tmp/b2a_arm.sh <TAG> 0x2A basin"
... "DUR=200 RCVBUF=2920 bash /tmp/b2a_arm.sh <TAG> 0x2A zerowin"
... "ulimit -n 16384; DUR=120 bash /tmp/b2a_arm.sh <TAG> 0x2A churn"
# 烧录
MSYS_NO_PATHCONV=1 PEER_PW=... bash burn/burn_round_b2a.sh <0x28|0x2A>
# 解析
python tools/parse_snap.py raw/<TAG>_snap.log --ref <DROP_EPOCH> --words 51,52,55,75
python tools/parse_pcap.py raw/<TAG>_replay.pcap
```
