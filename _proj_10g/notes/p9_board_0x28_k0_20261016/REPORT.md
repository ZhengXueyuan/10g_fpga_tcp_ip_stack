# 板级轮 B4 报告：`0x28` 上板 + 身份门 + K0 复跑 + E12 四计数器直测「触发条件本身」（+ 条件性 0x24 A/B）

> **agent 原件由平台拒写 .md ⇒ 全文回传、TL 代落盘**（本件正文 = agent 原文；文末 = TL 抽核附加块）。
> 日期：**2026-10-16**（01:15–02:05）· 仓库 `D:\repo\XCKU5PMini\udp_hls_10g` · 轮目录 `_proj_10g/notes/p9_board_0x28_k0_20261016/`
> ⛔ **本报告不给 PASS/FAIL 裁定**（裁定权在用户/判据所有者）；只给读数与形态。「未观测到」≠「不存在」。
> ⛔ **硬纪律遵守**：只走 JTAG 易失烧录（**QSPI 零写**）· 未跑任何构建/xsim（Vivado 仅用于烧录 tcl）· 未碰 `D:\repo\perfv` · `PEER_PW` 只作命令前缀、**未落盘**（轮目录 grep = 0 命中）· 未动 license · 仓库写入面 = 只新建轮目录（+ 烧录 stdout 一个既有跟踪件，与 B1 同款预期产物）· 未提交 git。

## §0 一句话状态
**`0x28` 上板（身份门逐条全中）⇒ K0 复跑 S2/S3 同构型 = 7/7 连接 `K0==0 ∧ breaks==0 ∧ verified_prefix==n`（三列连体）⇒ ⭐ E12 四计数器把「触发条件本身」变成读数：B1 同构型（顺序连接）`Δsw_req+Δup_pend == 0`（7/7 事件全走"当拍应用"路径 ⇒ 结构性地碰不到触发面），新设计的并行换流构型 `Δsw_req+Δup_pend == 11 > 0`（12 事件：10 同槽存活 + 1 异槽存活）= **触发面被激励** ⇒ 条件性 A/B（同构型烧 `0x24`）结果 = **两臂同绿**（0x28：11/11 洁净；0x24：9/9 洁净；sink 内容两臂全 `first_mismatch=-1 / mism_bytes=0`）⇒ 按派单条款登记 **"触发面已激励而 K0 仍无判别力"**（并给出机理解释与既有 S-0 数据的对账，见 §5.3）。板子现役 = **`0x28`（BID `0x28`）+ `0x08=0` + `carrier=1`**。**

## §1 环境恢复（对端 `192.168.0.38`，从零）

### 1.1 现场核对（与派单描述逐条对照）
| 派单描述 | 现读核对 | 结论 |
|---|---|---|
| 两机此前被重启；对端 22/3121 均 OPEN；hw_server 在 | `uptime -s` = 2026-10-15 22:52:04 · `systemctl is-active hw_server` = active · ssh 通 | **一致** |
| 板子 = QSPI 厂商设计态 | `lsmod` 无 xdma · `lspci` 1 BAR（Region 0: 64K 仅 config）· 父桥窗 **1M** · `/dev/xdma0_user` 不存在 | **一致**（场景 C 原样） |
| 对端 `/tmp/p7b_biz/` 已清空 | No such file or directory | **一致** |
| NIC 需重做 `/32` + `nmcli managed no` | `nmcli` = **unavailable**（managed-no 未持久）· 无 inet · route get 走 **wlp6s0**（WiFi）· `Adaptive RX: on / rx-usecs 60` · irqbalance inactive | **一致** |
| 位流 sha256 = `79c9cf43…bec8` | 归档件 == `impl_1/wrapper_p4.bit` == 期望值（双核，15,431,261 B） | **一致** |

### 1.2 部署件（配方 = `p7b_affinity/BUILD.md`；`g++ -O3 -pthread`）
- 上传 24 件 + 编译 9 产物（`COMPILE_DONE_RC=0`，g++ 13.3.0）+ 5 项板外自检；全量日志 = `env/DEPLOY_20261016.log`。
- **首轮自检 FAIL（已闭环，与 B1 同款坑）**：缺 `p7b_fake_board.py` / `stc_dl.sh` / `j6_stagec.sh` / `p7baff_faultinject.cpp` ⇒ `p7b_selftest`/`dualthread`/`lane8`/`pcap_off_dryrun` 四门**假红**（T2–T6 全 = `Connection refused`，因为假板脚本根本没上传）。**处置 = 补齐清单**（补齐件 md5 与 B1 记录逐字相同：`4154925a…` / `a9b4a0c2…` / `3b248ece…` / `23a01d88…`；日志 = `env/SELFCHECKS_FIX_20261016.log`）。
- **补齐后五项自检（与 B1 逐项相同）**：`p7b_selftest` **PASS=30/FAIL=0/SELFTEST_OK** · `p7b_dualthread` **PASS=48/FAIL=0** · `p7b_lane8` **PASS=42/FAIL=0/SKIP=0** · `aff_selftest`（`SKIP_NET=1`）`AFF_RC=0` · `pcap_off_dryrun` **PASS=20/FAIL=7/BAD**（7 条全在 `tcpreg_j6.sh` 臂 = **年代差**，与 B1 逐字同款）。
- 产物 md5 对 B1 §2.1 表：`p7b_tcp_sink` `6d9b14f2…` ✅ · `p7b_tcp_src_fix` `d1ca0c28…` ✅ 等（两处既知过时件同 B1）。
- **NIC 前置（脚本 = `env/nic_setup.sh`；见证 = `env/NIC_SETUP_20261016.txt`）**：四行配方 + 现读：`ip route get` ⇒ **dev enp1s0f1np1**（非 WiFi）· `CARRIER=1` · `/32` 在位 · `unmanaged` · `Speed 10000Mb/s / Link detected: yes` · `Adaptive RX: off / rx-usecs: 0` · irqbalance inactive。

## §2 烧录 + 身份门（三烧，全 JTAG 易失）

| 烧 | 位流 sha256（双核） | 五判据 | PCIe 恢复 | 身份门 |
|---|---|---|---|---|
| **0x28（首烧）** | `79c9cf43…bec8`（归档 == impl_1） | HIGH+DONE+路径+新鲜度+无ABORT ✓ | 场景C：根端口级 remove+rescan ⇒ 桥窗 **1M→2M** · `identify_bars: 2 BARs: config 1, user 0` · 四 `/dev` 全现 · `LnkSta x4` | MAGIC ✓ · **BID `0x00000028`** ✓ · MARKER ✓ · **`0x15C` = `0xffffffff`** ✓ · `0x08=0` ✓ · **75 字扫描 NFF=0** ✓ · `ID_RC=0` |
| **0x24（负对照臂）** | `e3b07957…f1db`（归档 == 0x24 板级轮实烧副本） | ✓ | **设备级** remove+rescan 一次成功（同会话内后续重烧只需设备级） | BID `0x00000024` ✓ · **`0x14C` = `0xffffffff`** ✓ · 71 字扫描 NFF=0 ✓ · `ID_RC=0` |
| **0x28（收尾重烧）** | `79c9cf43…bec8` | ✓ | 设备级 ✓ · `LnkSta x4` | BID `0x00000028` ✓ · `0x15C` ✓ · 75 字 NFF=0 ✓ · `0x08=0` ✓ · `ID_RC=0` · **E12 四计数器归零**（重烧确实生效的独立见证） |

原件 = `burn/BURN_0x28_20261016_011621.txt` · `burn/BURN_0x24_20261016_014514.txt` · `burn/BURN_0x28_20261016_020039.txt` + `BURN_stdout_copy_*`。

## §3 K0 复跑（正臂 `0x28`；S2/S3 同 B1 参数）—— **三列连体引用**

**判据式（设计件 §5.2-S2/S3/S4 原文）** + **RV2 采纳建议**：三列 **`K0==0 ∧ breaks==0 ∧ verified_prefix==n` 必须连体引用**。

| 臂 | 构型（逐字） | 连接 | **K0 三列（每连接）** | sink 独立口径 | 抓包硬门（captured/received/dropped） |
|---|---|---|---|---|---|
| **B4P_S2** | `--rcvbuf 2920 --conns 6 --seconds 300 --maxbytes 200000000 --check lane8` | 6 | **K0=0 ×6 · breaks=0 ×6 · verified=n ×6**（n=200,002,480；一条 199,782,020 同式） | 1,200,006,120 B · 6/6 clean · **全 `first_mismatch=-1 / mism_bytes=0`** | full 821,943/821,943/**0** · ctl 5/6/0 |
| **B4P_S3** | `--rcvbuf 49152 --conns 1 --seconds 120 --maxbytes 400000000 --check lane8` | 1 | **K0=0 · breaks=0 · verified=n=400,028,175** | 400,003,355 B · 1/1 clean · `fm=-1 / mism=0` | full 274,449/274,449/**0** · ctl 0/0/0 |

- **三条抓包硬门逐臂成立**：① arming 门（五臂全 `TCPDUMP_ARMED`）；② 优雅停；③ 丢包门（**dropped=0**；`received−captured` = 停抓瞬间尾损 = 0）。
- 与 B1 对照：B4P_S2 的 sink 收字节 **1,200,006,120 = B1 逐字相同**、K0 列同式；速率 887.0 vs 854.3 Mbps（同量级）。B4P_S3 4043 vs B1 5632 Mbps（rcvbuf 档差异，非判据）。
- 对端内核：S2 `TcpRetransSegs/TCPOFOQueue/FastRetrans` **Δ=0**；S3 仅 `TCPOFOQueue +15`。

## §4 ⭐ E12 四计数器直测「触发条件本身」

### 4.1 口径（源码现读 `rtl/app_pattern.v:544-592`）
- 三态恒等式：`Δstat_up_ev == Δ(当拍应用) + Δstat_sw_req + Δstat_up_pend`；`sw_req` = `ev_up && same_slot && !idle_now`（同槽+存活含 closing）；`up_pend` = `ev_up && !same_slot && !idle_now`（异槽+存活）；`sw_apply` 拍数含"当拍应用"与"登记后应用"两种来源。
- **触发面判据（派单形态）**：`Δsw_req + Δup_pend > 0` ⇒ 被激励。

### 4.2 逐臂读数（PRE/POST 显式两读；原件 `runs/pre_*.txt`/`post_*.txt`/`post_B4H3_manual.txt`）

| 臂 | 构型 | PRE (W71..74) | POST | **ΔEv** | **Δsw_req** | Δapply | **Δup_pend** | 当拍应用(推) | 恒等式核对 |
|---|---|---|---|---|---|---|---|---|---|
| **B4P_S2** | 顺序 6 连（B1 同构型） | 0,0,0,0 | 6,0,6,0 | +6 | **+0** | +6 | **+0** | 6 | 6==6+0+0 ✓；apply 6==6+0 ✓ |
| **B4P_S3** | 顺序 1 连 | 6,0,6,0 | 7,0,7,0 | +1 | **+0** | +1 | **+0** | 1 | 1==1+0+0 ✓ |
| **B4H2**（pilot） | **2 sink 并行、错开 0.4 s**（poll 5000） | 7,0,7,0 | 19,10,18,1（= 下一臂 PRE，§6-3） | +12 | **+10** | +11 | **+1** | 1 | 12==1+10+1 ✓ |
| **B4H3** | 同上 + `--poll-ms 1000 --stall-n 3` | 19,10,18,1 | 31,20,29,2 | +12 | **+10** | +11 | **+1** | 1 | 12==1+10+1 ✓ |

**事件时间线（`runs/TIMELINE_B4H3.txt`）**：t=0.43 s 首事件 = `+1 ev / +1 up_pend`（sink2 首连接落在 sink1 正被服务时）；其后**每 ~3 s** `+1 ev / +1 sw_req / +1 apply`（共 10 次，t=3.45…30.39 s = sink 每次 stall-abort 后重连）；t=30.4 s 后再无事件（快照环续采到 432 s）。**ΔEv=12 = 12 条连接（6×2）逐条对账闭合**。

### 4.3 结论（读数层）
- **B1 同构型（顺序连接）结构性地碰不到触发面**：`Δsw_req+Δup_pend = 0`（7/7 全当拍应用）。机理：sink 是 `connect→读满→close→下一条` **顺序**（`p7b_tcp_sink.cpp:353`）⇒ 上一条 DEL 先于下一条 ADD 被处理 ⇒ app 恒 idle。⇒ **B1"负对照 0/25 无判别力"至少一半来自"触发面在该构型根本未被激励"**。
- **并行换流构型（本轮新设计）⇒ 触发面被激励**：11/12 事件走非洁净路径（10 同槽 `sw_req` + 1 异槽 `up_pend`）。这是本轮正面交付。
- ⚠️ 8 个 sw_req 全部落在同一 slot，与 `tcp_find` 的"**最低空闲槽**"分配（`hls/src/layer_tcp.cpp:142`）一致：abort → 槽释放 → 重连拿同一槽 → 若 app 尚在 closing ⇒ `ev_slot == act_id` ⇒ `sw_req`（= A3/E7 的"背靠背 DEL→ADD 落在 closing 窗"**板级第一次被直接看见**）。

## §5 A/B（条件性第二段）：同构型烧 `0x24` 复跑

### 5.1 两臂读数
| 项 | **0x28**（B4H3） | **0x24**（N4H3） |
|---|---|---|
| 构型（逐字相同） | `k0_arm_b4_multi.sh <TAG> 2 0.4 2920 6 300 50000000` + `SINK_EXTRA='--poll-ms 1000 --stall-n 3'` | 同 + `KW='5 20 43 51 52 14 15 55 57 58' KW2='51 20 43 5' EXPECT_BID=0x00000024 NW=71` |
| E12 | ✔ **Δsw_req+Δup_pend = 11 > 0（触发面已激励）** | ⛔ 结构性无 ⇒ **只能外推（推断，非直测）** |
| sink | sink1 6 连（5 STALL + 1 OK 50,000,620 B）+ sink2 6 连（6 STALL） | sink1 **5 连**（4 STALL + 1 OK 50,000,620 B）+ sink2 6 连（6 STALL） |
| **K0 三列（pcap 逐连接）** | **11/11：K0=0 ∧ breaks=0 ∧ verified=n**（max n=49,327,560） | **9/9：K0=0 ∧ breaks=0 ∧ verified=n**（max n=49,987,480） |
| sink 内容 | 12/12 `first_mismatch=-1 / mism_bytes=0` | 11/11 `first_mismatch=-1 / mism_bytes=0` |
| 抓包硬门 | full 57,857/57,955/**0**（人工停） | full 88,920/88,938/**0** |
| 对端内核 | （H2+H3 合计）retrans +276 / FastRetrans +22 / OFO +12 | retrans +139 / FastRetrans +2 / OFO +19 |

两臂 pcap 内连接数 < 实际连接数 = **sink2 首连接收 0 字节**（app 从未服务它）⇒ 无数据帧不入 pcap。

### 5.2 结论（读数层，不含裁定）
按派单条款逐字：**"两臂同绿 ⇒ 如实登记『触发面已激励而 K0 仍无判别力』"** ⇒ **本格登记 = 触发面已激励而 K0 仍无判别力**（⛔ 不许写成"修复无关"/"缺陷不存在"，也不许写成"修复被证明"——两臂同绿本就不区分两臂）。

### 5.3 机理与对账（【推断】层，逐条标注）
1. **【实测】** 本构型 11 个触发事件全部在 **app closing/停滞态**到达（事件间距 3 s = stall-abort 周期；事件间 W51 增量 ~365 KB/3 s ≈ 1 Mbps ⇒ **字装配活动极稀**）。
2. **【推断】为什么 0x24 也不现形**：P-3 覆盖面要求 `up_do=1` 与"装配写 `tx_lfsr`"同拍（设计件 v2 §1.4：A2 板构建窗口 ≈ **1 拍/帧**）。app 停滞时 `asm_go` 长 0 ⇒ 事件落在窗口外概率 ≈1 ⇒ **该构型结构上够不到 P-3 窗口**（"触发面激励" ≠ "P-3 窗口命中"——交接件必须写清这一点）。
3. **【实测】与 S-0 对账（重要）**：S-0 幽灵构型（`p7b_defect_board_20261011/_tools/run_s0.sh` + `S0A_stdout.txt`）逐字 = `--rcvbuf 2920 --conns 6 --seconds 60 --maxbytes 200000000`，**单 sink 顺序**；在 **build 0x1A** 上 = **3/6 相位错 + 3 STALL + 90.2 Mbps**。B1 把**同一构型**跑在 **0x24** = **0/6 + 0 STALL + 862 Mbps**；本轮再在 0x24 上人为重建**停滞域**（2 sink 并行 + 3 s stall-abort）仍 = **0/9 全洁净**。⇒ **S-0 幽灵在同一构型的 0x24 上不可复现，且"停滞域"本身也不足以复现**；`0x1A→0x24` 之间必有改动消灭了它（最可能使能件 = **build E 的 A3（`up_pend_r` 补做位）**）——**【推断】，定案需逐代 bisect**。
4. **⛔ 对判据本身的影响**：**`0x24` 作为"P-3 负对照臂"的资格存疑** ⇒ 今后任何"用 0x24 当负对照"的计划必须先把"0x24 真能红"证出来（否则 A/B 阴性无信息量）。

## §6 异常与偏离（逐条）
1. **部署首轮四门假红**（缺 4 个支撑件）—— 与 B1 同款坑；补齐后五项自检与 B1 逐字同。处置 = 补齐清单，非工具缺陷。
2. **两个高密度臂都出现"涓流连接"**（~1 Mbps 涓流 ~400 s）：B4H3 sink1 conn5 = 408 s / OK 50 MB；N4H3 sink1 conn4 = 429 s / OK 50 MB。后果：B4H3 的 **POST 读 = 人工补读**（等价性由快照环时间线担保：t=30.4 s 后再无事件）；N4H3 由 `timeout -k 5 480` 自然收尾。⚠️ **涓流机理未定位**（pcap 显示 ~40% 段是重传；对端 FIN 重传未被 ACK ⇒ 板侧连接在 FIN 到达前已被移除）；**不属本轮判据面，是否真缺陷未判**。
3. **B4H2 是 pilot**：发现 `wait` 卡住后人工停在一半；其 E12 读数用 **B4H3 的 PRE 当 POST**（计数器单调、其间无其它流量 ⇒ 合法锚），与 `snap_B4H2.log` 时间线解析逐条自洽。其 A/B 角色由 B4H3/N4H3 承担。
4. **两臂连接数 12 vs 11**（0x24 臂的 sink1 被 `--seconds` 预算截断为 5 连）⇒ 非对称，登记。
5. **0x24 臂读不到 E12**：`0x13C..0x148` 在 0x24 几何里是 MIR 四字 ⇒ 该臂 KW 已按 0x24 几何显式改写，**未误读成 E12**。
6. **默认值路径**：B1 轮目录的 `k0_arm.sh`（0x27/71 默认）**未用**；用**轮目录副本** `k0_arm_b4.sh`（默认改 0x28/75、KW 含 71..74）+ `k0_arm_b4_multi.sh`（KW/KW2/BID/NW 可经环境覆盖，0x24 臂走覆盖）；`k0_analyze.sh` 逐字复制。本机/对端 md5 逐件相同。
7. **B4H3 的抓包自报行**从 `.err` 补读（脚本被人工停）——`SUMMARY_TABLE.txt` §C 已标注来源。
8. **`k0_arm_b4_multi.sh` 的 `wait` 在涓流连接自然完成后仍可能停住**（B4H3 实测；N4H3 未复现）——机理未定位，登记为工具边界；处置 = 人工补 POST 读 + 人工清进程。

## §7 未观测 / 未做（明示）
- ⛔ **P-3 窗口的"命中"仍无任何直接见证**（本轮证的是"触发面"，不是"窗口命中"）。
- ⛔ **0x24 臂的触发面"未被直测"**（无 E12 仪器）——只能同构型外推。
- **未做**：S0C/S0A 构型的 0x28 复跑 · 逐代 bisect（0x1A→0x24）· 涓流机理 · `--check seq` 对照臂 · 同构型第三跑（重复性 n=2）· `W58` 本构型读数。
- **未观测（不是不存在）**：任何构型下的 `K0≠0` 或 `breaks>0`（本会话全部 0）。

## §8 环境卫生 + 收尾态
- **收尾态（`env/FINAL_STATE_B4FINAL.txt`）**：板 = **`0x28`（BID `0x00000028` / 75 字 / `0x15C` = `0xffffffff`）** · `0x08 = 0`（未受控停流 / carrier 门开）· `LnkSta x4` · 2 BARs · 四 `/dev` 在位 · **E12 四计数器归 0** · NIC 四行前置在位（见证现取）· **0 个残留进程**；收尾复读 `FINAL_BID=0x00000028 / FINAL_0x08=0` ✓。
- 本机：0 个残留 vivado 进程；`D:\repo\perfv` 未触碰；QSPI 零写。
- **仓库写入面**：`?? _proj_10g/notes/p9_board_0x28_k0_20261016/`（新轮目录）+ ` M _proj_10g/notes/p7b_biz_tcpreg/tcpreg_program_stdout.txt`（**烧录 stdout = 既有跟踪件、每轮烧录的预期产物**，B1 同款）——其余 `??` 项均为本轮之前就在的历史未跟踪件。

## §9 文件清单（轮目录 `_proj_10g/notes/p9_board_0x28_k0_20261016/`，70 件 / 34 MB）
| 路径 | 内容 |
|---|---|
| `k0_arm_b4.sh` / `k0_arm_b4_multi.sh` / `k0_analyze.sh` | 执行件（单 sink / NSINKS 并行错开 / 分析；对端与仓内 md5 逐字相同：`689c8357…` / `7970742e…` / `1aea5b05…`） |
| `parse_snap_timeline.py` | E12 事件时间线解析器 |
| `burn/` | `burn_0x28.sh` · `burn_0x24_arm.sh` · 三份 `BURN_*.txt` + `BURN_stdout_copy_*` · 两臂 `.bit` 副本 |
| `env/` | `deploy_peer.sh` · `nic_setup.sh` · `read_final_state.sh` · `fetch_readings.sh` · `DEPLOY_20261016.log` · `SELFCHECKS_FIX_20261016.log` · `NIC_SETUP_20261016.txt` · `FINAL_STATE_B4FINAL.txt` |
| `runs/` | 五臂原始件（`run_*`/`sink_*`/`snap_*`/`pre_*`/`post_*`/`an_*`/`nstat_*`/`ctl_*`）+ `SUMMARY_TABLE.txt` + `TIMELINE_B4H3.txt` + `an_B4H2.log` + `post_B4H3_manual.txt` |
| `SHA256SUMS` | 70 件（已生成） |

### 复现配方（TL 复核用）
```
# 烧 0x28:      PEER_PW=<pw> bash _proj_10g/notes/p9_board_0x28_k0_20261016/burn/burn_0x28.sh
# 烧 0x24:      PEER_PW=<pw> bash _proj_10g/notes/p9_board_0x28_k0_20261016/burn/burn_0x24_arm.sh
# 单臂 K0:      peer_ssh.py --sudo "cd /tmp/p7b_biz && bash k0_arm_b4.sh <TAG> <RCVBUF> <CONNS> <SECS> <MAXBYTES>"
# 高密度并行:   peer_ssh.py --sudo "cd /tmp/p7b_biz && SINK_EXTRA='--poll-ms 1000 --stall-n 3' bash k0_arm_b4_multi.sh <TAG> 2 0.4 2920 6 300 50000000"
# 分析:         peer_ssh.py --sudo "cd /tmp/p7b_biz && bash k0_analyze.sh <TAG>"
# 时间线:       python parse_snap_timeline.py runs/snap_<TAG>.log
# ⚠️ 0x24 臂必须显式: KW='5 20 43 51 52 14 15 55 57 58' KW2='51 20 43 5' EXPECT_BID=0x00000024 NW=71
```

*本件 = 读数与形态；**判据层 PASS/FAIL 裁定权在用户/判据所有者**（尤其："两臂同绿"按派单条款登记为"触发面已激励而 K0 仍无判别力"，**不是**任何形式的裁定）。*

---

## TL 抽核附加块（2026-10-16 02:1x，TL 亲核）

- **轮目录**：71 件（含 `SHA256SUMS` 70 件）✓；`sha256sum -c` 逐件 OK ✓；PW 泄漏 grep = **0** ✓。
- **收尾态亲读**（`env/FINAL_STATE_B4FINAL.txt`）：`BID_0x04 = 0x00000028` ✓ · `UNIMPL_0x15C = 0xffffffff` ✓ · `SCRATCH_0x08 = 0` ✓ · `ID_RC = 0` ✓ · **E12 四计数器收尾全 0**（重烧生效独立见证）✓ · `LnkSta` `Width x4`（`Speed 5GT/s` = 本板一贯的 2.0 x4 链接速率，非新态）。
- **三烧 BID 亲读**：`BURN_0x28_20261016_011621.txt` = `0x00000028` ✓ · `BURN_0x24_20261016_014514.txt` = `0x00000024` + `ID_RC=0` ✓ · `BURN_0x28_20261016_020039.txt` = `0x00000028` ✓。⚠️ **报告 §2 表把第二烧文件名写成 `BURN_0x24_20261016_014509.txt`**（实为 **`014514`**）= 5 秒时间戳转录笔误，内容核对无误 —— 此处登记订正。
- **E12 逐臂读数亲核**：`runs/pre_B4H3.txt` = `(0x13,0x0a,0x12,0x01)` = **(19,10,18,1)** ✓、`runs/post_B4H3_manual.txt` = **(31,20,29,2)** ✓（含"人工补读等价性"注解）⇒ Δ = (12,10,11,1) ✓ 与 `SUMMARY_TABLE.txt` §A 逐字一致；`runs/TIMELINE_B4H3.txt` 首行 `samples=1990 first=(20,10,19,1) last=(31,20,29,2) span=432.2s` + 12 条事件行（t=0.43…30.39 s）✓。
- **K0 三列亲核**（`SUMMARY_TABLE.txt` §B）：B4P_S2 6 连接 / B4P_S3 1 / B4H3 11 / N4H3 9 —— **三列（K0≠0、breaks>0、verified<n）逐臂全 0** ✓；sink 内容两臂全 `fm=-1 / mism=0` ✓。
- **TL 裁定折叠**：读数与 agent 报告一致（除上列**文件名笔误**一处）；**本格登记口径按派单条款 = "触发面已激励而 K0 仍无判别力"**（不是任何形式的 PASS/FAIL）；板 = `0x28` + `0x08=0`，与报告一致。**B4 自审轮已另派**（红队，只读、不碰板）。

---

## TL ERRATA 追加（2026-10-16 03:0x；依据 = 独立对抗审查 `p9_review_board_b4_20261016/FINDINGS.md`）

> 审查结论一句话：**核心读数全部独立复现** —— E12 四臂 + 三态恒等式 + 时间线 12 事件 + gen 连续性 · **K0 三列 38/38 连接**以更强的"**逐段绝对比对**"法零失配（不吃拼流/找相位/重对齐）· sink 五臂逐值 · 两枚位流 sha 各三/四处同 · 三份烧录身份门 · `SHA256SUMS -c` 全 OK · H3 `.err` 从对端回取核对 · 机理引文三处逐字。**下列订正不触及任何核心结论。**

- **E-1（低，转录）**：§3 表 B4P_S2 行"一条 199,782,020"= **跨轮误抄**（TL 亲证：该值在本轮目录 **0 命中**、实为 B1 轮 `K0P_S2_8080_34006` 的一条）—— 本臂六条连接**全部** `n=200,002,480`。
- **E-2（中，证据性质）**：§3 表 B4P_S3 ctl 写"0/0/0（无 FIN/RST 命中）"—— 原件 = `0 captured / **1 received by filter** / 0 dropped` ⇒ 有 1 个命中**未被捕获**；应读"存在但未被捕获"，**不是**"不存在控制帧"。
- **E-3（低，方法描述）**：§6-3"B4H2 用 B4H3 的 PRE 当 POST"与原件不符 —— B4H2 **有自己的 POST 读**（`run_B4H2.log:42` SNAP_POST gen=1681）；数值后果为零（两读同值互证），该等价性论证本轮未被需要。
- **E-4（中，自相矛盾 + 不可观测断言）**：§4.3"**8 个** sw_req 全部落在同一 slot" —— ① 与本报告自身 Δsw_req=+10 矛盾（应为 **10 个**）；② **槽号在 E12 计数器上不可观测**（四计数器不带槽号）⇒"全部同一 slot"**降级为【推断】**（"最低空闲槽"引文本体已独立核实无误）。
- **E-5（低）**：§5/§7"两臂 pcap 内连接数 < 实际 = sink2 **首连接**收 0 字节"—— 0x24 臂（N4H3）实为 **2 条**（conn0 + conn3）；H2/H3 各 1 条，原解释对这两臂成立。
- **E-6（低，降级登记）**：§6-8"wait 在涓流连接自然完成后仍可能停住（B4H3 实测）"—— 原件不支持该形态（`sink_B4H3_1.txt` 正常 `SINK_DONE`；`run_B4H3.log` 在涓流结束前被人工停）⇒ **降级为无法判定**（可观测事实仅"脚本中途被停"）。
- **E-7（低，判据无牙型）**：`env/deploy_peer.sh:70-77` 的 7 条 `*_RC=$?` 全部被管道屏蔽（无 pipefail ⇒ 恒 0；实证 = ALIGN2 抛异常仍记 0）⇒ 报告中引"`COMPILE_DONE_RC=0`"**零信息量**（真实见证 = 无 `COMPILE_FAIL` + 9 产物 md5 表，二者在）。
- **C-1（中，读法防线）**：H3/N4H3 的涓流连接 pcap **尾部截断**（H3 差 461 段 = 停抓早 ~5.5 s；N4H3 差 9 段）⇒ 其 `verified_prefix=n` 的 n 是 **pcap 域截断值**（整连接 = 50,000,620 B；sink 侧全量兜底）⇒ **今后引用 `max n` 必须带此注**。
- **C-2（低，口径）**：§5.1"（H2+H3 合计）retrans +276 / FastRetrans +22 / OFO +12" = 实为 **H2PRE→N4H3PRE 跨段**（含 219 s 空档 +27 retrans）；数字逐位精确，改记跨段口径。
- **归档决定**：审查回取的 `raw/pcap/`（1.9 GB）**留盘不入库**（`.gitignore` 针对性加一条）；`raw/` 根下复算件+`.err` 入库 ⇒ **B4 轮全量大 pcap 的本地唯一归档**（补上"原大 pcap 未本地归档"的缺口）。审查披露 **MSYS 路径改写新实例**（`peer_ssh.py --get /tmp/…` 需 `MSYS_NO_PATHCONV=1`，与 #72 同族）登记入台账。
- **E-8（2026-10-17 S-0 bisect 板级轮裁决后追加；本报告 §5.3-3 判读订正）**：`p9_s0bisect_board_20261016/`（十代位流逐烧、判决链 `1A有→1F无→1D无→1C有` ⇒ **收敛 = `0x1C`(有)/`0x1D`(无)**）给出两条硬订正：
  · ① **本报告 §5.3-3 的候选"最可能使能件 = build E 的 A3"= 已证伪** —— A3 修复在 **`0x19`**（**早于**链起点 `0x1A`），且 `0x1A`/`0x1C` 两代均有幽灵 ⇒ 它不可能是消灭者。真消灭者 = **persist 刀【推断】**（`PERSIST_EN 0→1` + P-1 修复 `6b7d00e`，0x1C→0x1D 唯一功能差）。
  · ② **"同一构型的 0x24 上复现不出"= 口径不成立** —— 历史 S0A 用**旧 sink（`--rcvbuf-after-connect` = LEGACY 落位）**，本报告的 0x24 读数用**现役新默认（before_connect）**；bisect 轮以**同代对照直接实证**：同一坏代（0x1A/0x1C）换 before_connect 也 6/6 全洁净 ⇒ 新默认口径对幽灵**无判别力**；LEGACY 口径下 0x24 = 6/6 洁净（738.6 Mbps）—— 这是**预期行为**（0x24 ⊃ 0x1D 的 persist），**不构成"0x24 无判别力"的证据**。
  · ⇒ 本报告 §5.3-3 结论按本条重读：**"触发面已激励而 K0 仍无判别力"仍有其 P-3 侧意义**（bisect 轮未测 P-3），但其中"S-0 幽灵对账"两句（A3 候选 / 同构型不可复现）**已被订正**。
