# B4 板级轮（提交 `a166b5e`）对抗审查 FINDINGS（红队，只读；⛔ 不下 PASS/FAIL 裁定）

> **agent 原件由平台拒写 .md ⇒ 全文回传、TL 代落盘**（本件正文 = agent 原文；文末 = TL 裁定折叠/亲证块）。
> 审查对象 = `_proj_10g/notes/p9_board_0x28_k0_20261016/`（REPORT.md + 全部本地原件）。
> 方法 = **从原始件独立复算**：自写 E12 环解析器、自写 K0 逐段绝对校验器（**不跑轮内工具**）、自算 sha256/md5、从对端**只读**取回 pcap（~2.0 GB）与 tcpdump `.err` 原件。
> 复算件全部在 `_proj_10g/notes/p9_review_board_b4_20261016/raw/`（含 `pcap/` 1.9 GB 原件；未进 git）。
> 口径：「未观测到」≠「不存在」；severity 为自评；本件不给 PASS/FAIL。

---

## 一、已证伪（与原件不符）

### F1. §3 表 B4P_S2 行的「一条 199,782,020」不在本轮原件里（转录错轮）· severity **低**
- 报告原文：`REPORT.md:45`「K0=0 ×6 · breaks=0 ×6 · verified=n ×6（n=200,002,480；**一条 199,782,020** 同式）」。
- 原件：`runs/an_B4P_S2.log` 六条连接**全部** `n=200002480 / verified_prefix=200002480 / breaks=0`（逐行核）。
- 199,782,020 的真实出处 = **B1 轮**：`p9_board_0x27_k0_20261015/runs/SUMMARY_TABLE.txt` → `K0P_S2_8080_34006.pcap: K0=0 n=199782020`（该跑 6 条里恰有一条此值）。
- 我方独立复算（`raw/k0_verify_B4P_S2.txt`）：六条 pcap 流长逐条 **= 200,002,480**，无一例外。
- 复现：`python raw/k0_verify2.py B4P_S2 raw/pcap/k0_B4P_S2_full.pcap0..4`

### F2. B4P_S3 的 ctl 抓包自报被写成「0/0/0（无 FIN/RST 命中）」——原件是 **0/1/0**（有 1 个命中未落盘）· severity **中**
- 报告/表原文：`REPORT.md:46`「ctl 0/0/0」；`runs/SUMMARY_TABLE.txt:27`「0/0/0 (无 FIN/RST 命中)」。
- 原件（两处）：`runs/run_B4P_S3.log` 的 `[ctl]` 块 = 「0 packets captured / **1 packet received by filter** / 0 packets dropped by kernel」；我方另从对端只读取回 `.err` 原件（`raw/k0_B4P_S3_ctl.err`）逐字相同。
- 含义差异：**确有 1 个 FIN/RST 命中过 BPF 过滤器**（收到但停抓时未落盘），不是「无命中」——这是**证据性质**差异（"不存在控制帧" vs "存在但未被捕获"），不是数值微差。
- 复现：`cat raw/k0_B4P_S3_ctl.err`；对照 `runs/run_B4P_S3.log` 尾。

### F3. §6-3 与 §4.2/§A 的「B4H2 用 B4H3 的 PRE 当 POST」与原件不符——H2 **有自己的 POST 读** · severity **低**
- 报告原文：`REPORT.md:101` §6-3「其 E12 读数用 **B4H3 的 PRE 当 POST**」；`REPORT.md:64` 行内注「（= 下一臂 PRE，§6-3）」；`SUMMARY_TABLE.txt` §A「B4H2(pilot) … POST (19,10,18,1)[=B4H3 PRE]」。
- 原件：`runs/run_B4H2.log` **内含 B4H2 自身 `SNAP_POST`（gen=1681，1792085629.287，sink 收尾后 4 ms）**，值 (19,10,18,1)；snap 工具 gen 守卫在 `snap_B4H3.log` 首行留痕「GEN_FAIL (1681 -> 1683)」（1681 正是 H2 POST 消耗的 gen）。
- 数值后果：**零**（H2 自身 POST 与 H3 PRE 同值；且 H2 结束→H3 开始 219.5 s 空档内确无事件，双读互证）。但「借下一臂 PRE 当 POST」的**方法与原件不符**（该等价性论证本轮实际未被需要）。
- 复现：`grep -n "SNAP_POST" runs/run_B4H2.log`；`head -3 runs/snap_B4H3.log`。

### F4. §4.3「**8 个** sw_req」与同报告 Δsw_req=+10 自相矛盾；「全部落在同一 slot」无仪器支撑 · severity **中**
- 报告原文：`REPORT.md:72`「⚠️ **8 个 sw_req** 全部落在同一 slot，与 `tcp_find` 的『最低空闲槽』分配一致……」（写在机理段，未标【推断】）。
- 同报告他处：§4.2/§A Δsw_req **= +10**；原始计数器 `ΔW72 = 0x14 − 0x0a = +10`（pre/post_B4H3.txt，我方解析复核）。8 与 10 不可能同时对。
- 另：E12 四计数器**均不携带槽号**（`rtl/app_pattern.v:581-593` 只 inc），「全部落在同一 slot」在现有仪器面**不可观测**。「最低空闲槽」引文本身核实无误（见 §二 A5）。
- 复现：`python raw/my_snap_parse.py`。

### F5. §5/§7「sink2 **首连接**收 0 字节」对 0x24 臂（N4H3）不完整——是 **2 条** 0 字节连接 · severity **低**
- 报告原文：`REPORT.md:87`「两臂 pcap 内连接数 < 实际连接数 = **sink2 首连接**收 0 字节（app 从未服务它）⇒ 无数据帧不入 pcap」。
- 原件：`runs/sink_N4H3_2.txt` 里 **conn0 与 conn3 两条都是 got=0**；N4H3 总连接 11、pcap 内 9 ⇒ 差 **2**。
- 我方独立 pcap 扫描（`raw/k0_verify_N4H3.txt`）：恰有 **2 个只有 SYN-ACK、零数据**的 dport（59732 / 49762）✓ 与 2 条 0 字节连接对账；H2/H3 各恰 1 个（「首连接」解释对这两臂成立）。
- 复现：`python raw/k0_verify2.py N4H3 raw/pcap/k0_N4H3_full.pcap0` + `sink_N4H3_2.txt`。

### F6. §6-8「wait 在涓流连接**自然完成后仍可能停住**（B4H3 实测）」——原件不支持该形态 · severity **低**
- 原件：`runs/sink_B4H3_1.txt` **以 `SINK_DONE` 正常收尾**（wall_s=438.424，conn5 正常 OK）；而 `runs/run_B4H3.log` 在两条 `SINK*_START` 后**再无任何输出**（无 SINK*_RC / 收尾段）⇒ 脚本是在涓流**完成之前**被人工终止的（旁证：tcpdump 停抓早于涓流结束 ~5.5 s，见 §三-C1）。可观测事实只是「脚本中途被停」；「涓流自然完成后 wait 仍停」本地**无任何见证**（不判真假，登记为**无法判定**）。
- 复现：`tail -3 runs/sink_B4H3_1.txt`；`cat runs/run_B4H3.log`。

### F7. `env/deploy_peer.sh` 的 7 条 `*_RC=$?` 全被管道屏蔽（结构性恒 0）——ALIGN2_NOARG 在**抛异常**时仍记 0 · severity **低**（判据无牙型；非本轮任何结论的承重件）
- 原件：`env/deploy_peer.sh:70-77`（`bash p7b_selftest.sh … | tail -4; echo SELFTEST_RC=$?` 等 6 条 + `g++ … | sed …` 后 `echo COMPILE_DONE_RC=$?`）；脚本只 `set -u`、**无 pipefail** ⇒ `$?` = 管道末件的 RC，**恒 0**。
- 实证：`env/DEPLOY_20261016.log:99-101` = `Traceback … align_check2_fixed.py` 紧接 `ALIGN2_NOARG_RC=0`（工具崩了、RC 报 0）。
- 影响面：真证据 = 各 `*_SUMMARY` 文本行（我方已逐项复核，见 §二 A7）；但 `REPORT.md:23` 引「`COMPILE_DONE_RC=0`」当见证语，须知该行**零信息量**（编译真实见证 = 无 `COMPILE_FAIL` 行 + 9 产物 md5 表，二者都在）。
- 复现：`sed -n '55,80p' env/deploy_peer.sh`；`sed -n '77,101p' env/DEPLOY_20261016.log`。

---

## 二、复算一致（独立复核通过的清单）

**方法独立声明**：E12 用自写解析器（`raw/my_snap_parse.py`）；K0 用自写「逐段绝对比对」法（`raw/k0_verify2.py`：图案在 26.2 万条 GF(2) 并行泳道上生成、每条 TCP 段按 `o=(seq−base)&0xFFFFFFFF` 逐字节对 `pattern[o:o+len]` —— **比轮内工具更强**：不吃「拼流+32B 找相位+有界重对齐」，任何单字节差/洞/重复段内容冲突都会现形；生成器与朴素顺序生成器前 1 MiB 位级互证）。

### A1. E12 四计数器（核心攻击面 1）—— 逐臂逐值全中
| 臂 | PRE(W71..74) | POST | ΔEv/Δreq/Δapply/Δpend | 三态恒等式 | 我方独立值 |
|---|---|---|---|---|---|
| B4P_S2 | (0,0,0,0) | (6,0,6,0) | +6/+0/+6/+0 | 6==6+0+0 ✓ | ✓ |
| B4P_S3 | (6,0,6,0) | (7,0,7,0) | +1/+0/+1/+0 | 1==1+0+0 ✓ | ✓ |
| B4H2 | (7,0,7,0) | (19,10,18,1) | +12/+10/+11/+1 | 12==1+10+1 ✓ | ✓ |
| B4H3 | (19,10,18,1) | (31,20,29,2) | +12/+10/+11/+1 | 同 H2 ✓ | ✓ |

- 环样本数/连续性：H2 = 1619 样本 gen 62→1680（环内无 gen 断档）；H3 = 1990 样本 gen 1684→3673（无断档）。H2 环首 (8,0,8,0)、尾 (19,10,18,1)=H2 POST；H3 环首 (20,10,19,1)、尾 (31,20,29,2)。
- **TIMELINE_B4H3.txt 逐行复现**：我方独立提取与轮内 12 行文件**数值与时刻全同**（t=0.43/3.45/…/30.39 s）。⚠️ 口径注解：时间线文件列 **11 条**事件行；第 12 个事件（+1 ev/+1 apply = clean）发生在 `pre_B4H3.txt`(19,10,18,1) 与环首样本 (20,10,19,1) 之间 ⇒ 报告「12 事件」对账含它，12=1(环外 clean)+1(pend)+10(req)，自洽。
- 「ΔEv=12 = 12 条连接（6×2）」：两臂均恰 12 条连接（我方 pcap 计数 11 有数据 + 1 零字节且发过 SYN-ACK ⇒ 也产生 ev_up）✓。
- `sw_apply` 双来源口径与 `rtl/app_pattern.v:544-592` **现读一致**：`up_ev = ev_up || up_pend_r || (SWC_OK&&sw_pend)`（:544）、`sw_apply = SWC_OK ? (idle_now && up_ev) : up_do`（:551）、`ev_same_act/ev_other_act`（:553-554）、计数器（:581-593）；「当拍应用 ∧ 三态互斥 ⇒ Δup_ev == Δ(ev_up∧sw_apply)+Δsw_req+Δup_pend」逐条成立。
- ⚠️ 附注（低·【推断】层）：§A/§4.2 追加分解「apply(11)==clean(1)+srq应用(10)」非计数器可判定式——「srq应用(9)+pend应用(1)」代数上同样给 11；行为证据（0 字节连接从未被服务）支持报告的分解，但该步应标【推断】。
- 四计数器**纯观测**核实：全仓 grep 仅 `board/wrapper_p4.v:1262-1265` + `:4104-4107/:4163-4166`（快照槽 31-34）消费，无控制用途 ✓。

### A2. K0 三列（核心攻击面 2）—— 五臂 38 条连接**全部** `K0=0 ∧ breaks=0 ∧ verified_prefix=n`（更强形式）
- 我方「逐段绝对比对」：**每条连接每个 TCP 段的载荷逐字节等于图案绝对偏移 0 起流** ⇒ 洞=0、重复段内容冲突=0、首失配=-1（五臂 38 条连接全体成立；`raw/k0_verify_*.txt`）。
- 连接数：S2 **6** ✓ / S3 **1** ✓ / H3 **11** ✓ / N4H3 **9** ✓ / H2 **11** ✓（H3/N4H3 另各 1/2 条零字节连接、pcap 内只有其 SYN-ACK）。
- **an_*.log per-连接表与 pcap 复算逐条一致**：五臂 38 条 `n` 全部逐值复现（H3 max 49,327,560、N4H3 max 49,987,480、S2 全 200,002,480、S3 400,028,175、H2 max 36,209,460）。
- 附加（中性）：S2 六条连接**每条线上恰 1 个重复段**（dup_bytes=1460，内容逐字节相同）；两个 trickle 连接重复段**零冲突**（H3 dport55352：53,807 段中 20,021 段重复 = **37.2%** ≈ 报告 §6-2「~40%」）。

### A3. sink 口径（攻击面 3）—— 逐值复现
- S2：6/6 OK 各 200,001,020 B、Σ=**1,200,006,120**、全 fm=-1/mism=0，墙钟 10.82 s / agg **887.017 Mbps** ✓；S3：1/1 **400,003,355 B** / **4,043.422 Mbps** ✓。
- H3：sink1 6 连（5 STALL+1 OK **50,000,620** B，trickle **408,091 ms**）+ sink2 6 连（6 STALL，conn0=0 B）✓；N4H3：sink1 **5 连**（4 STALL+1 OK，trickle **428,648 ms**）+ sink2 6 连（conn0/conn3=0 B）✓；H2：sink1 5 条已打印+conn5 中途中止（RC=143/SINK1_SUM_MISSING）+ sink2 6 连 ✓。
- pcap 流长 vs sink 收字节的增减方向逐条自洽（stalled 连接 = sink + n×1460 在飞；2920/49152 窗量级吻合）。

### A4. 烧录/身份（攻击面 4）—— 独立 sha256 + 原件逐条
- `burn/wrapper_p4_0x28.bit` = **`79c9cf434eb66723b97f654cbece9ea061632e2297c0a8ab0ea0dc198c43bec8`** ✓，与 `p9_build_0x28/wrapper_p4.bit` 与 `vivado_prj/.../impl_1/wrapper_p4.bit`（现读）**三处同**，15,431,261 B ✓。
- `burn/wrapper_p4_0x24.bit` = **`e3b07957aea0326a168b9db0238ef9dd933dc7a21884c92e50a7c3b0abadf1db`** ✓，与 `p9_build_0x24`、`p9_board_0x24_20261013/burn/…`、`p9_uram_ab_20261014/burn/…` **四处同** ✓。
- 三份 BURN 日志身份门逐项复核全中：0x28 = BID **0x28**/`0x15C=0xffffffff`/`0x08=0`/75 字 NFF=0/ID_RC=0；0x24 = BID **0x24**/`0x14C=0xffffffff`/71 字 NFF=0/ID_RC=0；场景 C 根端口级 remove+rescan 桥窗 **1M→2M** ✓。
- `env/FINAL_STATE_B4FINAL.txt`：BID 0x28 / 0x15C 未实现 / 0x08=0 / **E12 四计数器全 0（重烧生效独立见证，gen=1）** / 0 残留进程 ✓。
- `SHA256SUMS`(70 件) `sha256sum -c` **全 OK**（含两个 .bit）。

### A5. 机理引文（攻击面 5）—— 三处逐字核
- `rtl/app_pattern.v:544-592` ✓（见 A1）。
- `p7b_tcp_sink.cpp:353` = `for (int c = 0; c < conns; c++) {` ✓ 顺序连接（connect→读满→close→下一条；同件 :126 `while (got < a->maxbytes)` 逐 recv 累计）。部署件 md5 `6d9b14f2…` 与 B1 输入表所记源 `8d02ef64…`（= 本仓 `_proj_pcie/p7b_biz/p7b_tcp_sink.cpp`）配套 ✓。
- `hls/src/layer_tcp.cpp:142` = `tcp_find(...)` 定义行；「最低空闲槽」= 其循环体内 `if(state==T_FREE && free<0) free=i;`（:146）✓。
- 附：§5.3-2 引「设计件 v2 §1.4：A2 板构建窗口 ≈ 1 拍/帧」✓（`p9_fix_upok_design_20261014/DESIGN_v2.md:68-70`，且**带构型限定**，与该件纪律⑤一致）。

### A6. S-0 对账（攻击面 6）
- 0x1A（S0A）：`p7b_defect_board_20261011/runs/S0A_stdout.txt` 逐连接 = **3 条相位错**（conn1/2/5：fm=0、mism≈bytes−bytes/256）+ **3 条 STALL**（conn0/1/4）+ agg **90.220 Mbps** ⇒ §5.3-3「3/6 相位错 + 3 STALL + 90.2 Mbps」**逐字成立**。
- 0x24（B1 轮）：`p9_board_0x27_k0_20261015/runs/sink_K0N_S2.txt` = **6/6 clean、0 STALL、agg 862.137 Mbps** ⇒「0/6 + 0 STALL + 862 Mbps」成立。S0A 配置逐字 = rcvbuf 2920/conns 6/secs 60/maxbytes 200000000 ✓（B1 对照臂 secs=300 只是预算帽、未截断，实质同构）。
- ⚠️ 与 F1 呼应：B1 K0P_S2 的「一条 199,782,020」正是被误抄的那个值。

### A7. 抓包硬门 + 纪律面（攻击面 7）
- **H3 full 原件回取核对**：`raw/k0_B4H3_full.err`（对端原点）=「**57857 captured / 57955 received / 0 dropped**」✓ 与 §5.1 逐字；我方解析 = 57,857 包**逐包全账**（57,845 数据段 + 11 SYN-ACK + 1 无载荷 PSH+ACK）✓；H2 71154/71203/0 ✓；N4H3 88,920 captured（同数）✓；S2/S3 received==captured==0 ✓。
- arming 门五臂全在 ✓；优雅停 S2/S3/H2/N4H3 全在 ✓（H3 为人工停，见 §三-C1）。
- ctl 普查复核：S2 = 5×RST+ACK（peer→board；第 6 个尾损，received=6）✓；H2/H3/N4H3 = **FIN+ACK 指数退避重传**（0/0.2/0.6/1.5/3.1/6.4/13.3 s）、板侧全程无响应 ⇒ 支持 §6-2「对端 FIN 重传未被 ACK、板侧已移除」形态描述 ✓。
- 纪律面：PW 轮目录 grep = **0 命中**（只 `<pw>` 占位符）✓；bit/pcap **均未进 git** ✓；git 写入面与声明一致 ✓；工具身份链（对端现读=本仓副本=报告）：`p7b_snap.sh a257af82`/`align f14680ad`/`split fa4456d6`/`k0_arm_b4.sh 689c8357`/multi `7970742e`/`analyze `1aea5b05` 逐一相符 ✓；补齐四件 md5（`4154925a/a9b4a0c2/3b248ece/23a01d88`）与报告逐字相同 ✓；首轮四门红（17/13、26/22、32/6、6/25）→补齐后绿（30/0、48/0、42/0/SKIP=0、20/7）在 deploy/fix 日志中逐条可见 ✓；B1 的 pcapoff = 20/7 同款 ✓。
- 独立观察（中性）：板上每个连接 ISN 恒 `0x12345679`（对按 seq 拆流无影响）。

---

## 三、无法判定 / 缺件缺环境

### C1. H3 trickle 连接（dport 55352）的 pcap 覆盖**尾部截断**——「verified_prefix==n」对它是**截断流长** · severity **中（读法防线）**
- 事实（复算）：该连接 pcap 流 = `[0, 49,327,560)` 连续、逐字节全对；但 **sink 实收 50,000,620 B**（sink_B4H3_1.txt conn5），差 **673,060 B = 461 段**。
- 机理证据：capture 内该连接末段时刻 = 起流后 **402.53 s**，而 sink 连接时长 **408.09 s** ⇒ 停抓早于涓流结束 ~5.5 s；两口径速率逐位一致（122.55 vs 122.52 KB/s）⇒ 同一流、pcap 尾截。tcpdump 自报 received−captured = **98 < 461** ⇒ H3 缺失**不是**尾损冲刷，而是**停抓早**（操作者在涓流未结束时就停了 tcpdump）。
- 对照 N4H3（dport 34778）：pcap n=49,987,480 vs sink 50,000,620，差 **13,140 B = 9 段**；该臂自报 received−captured=**18** 包 ⇒ 与「停抓尾损」量级相容（机理未逐段定案）。
- 影响面：sink 侧独立口径（自偏移 0 全量、fm=-1）**兜底**了这两条尾部；但 §5.1 表「verified=n」的 `n` 是 **pcap 域截断值**，未读 §6 的读者可能把 `max n=49,327,560` 读成整连接长度（整连接 = 50,000,620）。建议下轮引用带此注（**不是**判据 FAIL、不改变任何读数）。
- 复现：`python raw/capture_order.py 55352 raw/pcap/k0_B4H3_full.pcap0`；`cat raw/k0_B4H3_full.err`。

### C2. §5.1「（H2+H3 合计）retrans +276 / FastRetrans +22 / OFO +12」的**口径**不可从字面核 · severity **低**
- `runs/nstat_post_B4H3.txt` **不存在**（H3 post 内核计数从未取；脚本被人工停）。三数逐位吻合的实真跨度 = **H2_PRE → N4H3_PRE**：453−177=**276**；73−51=**22**；396−384=**12**（逐值复算）。该跨度**包含** H2 收尾后→H3 开始前的 219 s 空档（其间 retrans **+27**、OFO +2、FastRetrans +0）。⇒ 数字精确，但「H2+H3 合计」会被读成「两臂各自 post 之和」；建议改记「H2PRE→N4H3PRE 跨段」。
- 复现：`cat runs/nstat_pre_B4H2.txt runs/nstat_post_B4H2.txt runs/nstat_pre_N4H3.txt`。

### C3. 其余（如实登记）
- H2 的 capture stop 时刻无独立见证（决定被杀连接 24.9 MB 的 pcap 尾部完整性不可终判；只可证 pcap n ≥ 已打印读数）。
- 「涓流机理」（每拍重发上一段 / 40% 重传）不在判据面，未复核。
- `run_B4H3.log` 被人工终止的确切时刻不可核（只可界定在 SINK2_START 后、涓流结束前）。

---

## 四、本次审查的动作披露（只读面）

- 对端仅两类操作：① `tools/peer_ssh.py --get`（sftp 只读拉取：11 个 pcap 分片 + 4 份 `.err`，全部在 `raw/`）；② 诊断取件失败时执行过一次**只读** `ls -la`/`ls /tmp | head`（无脚本、无状态改变）。
- ⚠️ 取件首次失败真因 = **MSYS 路径改写**（`--get /tmp/...` 远端参数被 Git Bash 改写成 Windows 路径）；`MSYS_NO_PATHCONV=1` 后全部成功（新坑一例，与全局 #72 同族）。
- 本机：未跑 xsim/xelab/vivado；未做任何 git 写操作；未改轮目录任何文件。
- `raw/` 内容与体积：`pcap/`（**1.9 GB**，S2 1.26G + S3 420M + N4H3 136M + H2 109M + H3 88.5M，**可整体删除、不影响本件**）；复算件 `my_snap_parse.py`/`k0_verify2.py`/`capture_order.py` + 5 份 `k0_verify_*.txt` + 4 份 `.err`。均不在 git 跟踪面内。

*（本件 = 红队读数清单；PASS/FAIL 裁定权在判据所有者。任何「一致」均指与我方独立复算一致，不等于判据层通过。）*

---

## 复核摘要（给 TL 的 5 行）

1. **核心读数全部独立复现**：E12 四臂（含三态恒等式、时间线 12 事件、gen 连续性）、K0 三列 38/38 连接（逐段绝对比对，比轮内工具更强、零失配）、sink 五臂逐值、两枚 bitstream sha256、三份烧录身份门、`SHA256SUMS -c` 全 OK、五臂抓包自报（H3 的 `.err` 已从对端回取原文核对）。
2. **7 条报告/原件不符**（§一）：跨轮误抄一个 n 值（F1）；S3 ctl 被写成「无 FIN/RST 命中」而原件有 1 个命中（F2）；H2 的 POST 方法描述与原件不符（F3，数值无影响）；§4.3「8 个 sw_req」与自身 +10 矛盾且槽数不可观测（F4）；N4H3 实为 2 条零字节连接（F5）；§6-8 的「wait 涓流后仍停」无见证（F6）；deploy 的 7 条 RC 全被管道屏蔽（F7，判据无牙型）。
3. **一条读法防线**（C1）：H3/N4H3 的 trickle 连接 pcap 尾截（461 段 / 9 段），其 `n` 是截断流长；全流内容由 sink 口径兜底。
4. **一条口径注解**（C2）：§5.1 的「H2+H3 合计」内核计数实为 H2PRE→N4H3PRE 跨段（含 219 s 空档 +27 retrans），数字逐位精确。
5. ⛔ 未下任何裁定；raw 复算件与 1.9 GB 原件在 `_proj_10g/notes/p9_review_board_b4_20261016/raw/`（可删/可留，未进 git）。

---

## TL 裁定折叠 / 亲证块（2026-10-16 03:0x，TL 亲核）

**抽证（TL 亲读原件）**：F1 ✓（`199782020` 在 B4 轮目录 **0 命中**、在 B1 `SUMMARY_TABLE.txt:12` 命中 = 跨轮误抄坐实）· F2 ✓（`run_B4P_S3.log` ctl 块 = `0 captured / 1 packet received by filter / 0 dropped`）· F3 ✓（`run_B4H2.log:42` 有自身 `SNAP_POST`）· F5 ✓（`sink_N4H3_2.txt` conn0 与 conn3 双双 `got=0`）· F7 ✓（`deploy_peer.sh:70-77` 管道后 `echo *_RC=$?`、无 pipefail）。**F4 由报告内部自相矛盾（8 vs +10）立即可判**；F6 与 C1/C2 采信审查复算（其 raw 复算件在案）。

**折叠处置（全部采纳，逐条落入 `p9_board_0x28_k0_20261016/REPORT.md` 的 TL ERRATA 块 E-1..E-7 + C-1/C-2）**：
- **核心结论不受任何一条影响**：触发面判据（Δsw_req+Δup_pend：B1 构型=0 / 并行换流构型=11>0）、三态恒等式、K0 三列 38/38、两臂同绿登记、0x24 负对照资格存疑 —— 全部经**更强的独立方法**复现成立。
- F4 的"同一 slot"**降级为【推断】**（槽号不可观测）；F6 的"wait 涓流后仍停"**降级为无法判定**（原文形态转为"脚本中途被停"）。
- C1（trickle pcap 尾截）写成**引用纪律**：今后引 H3/N4H3 的 `max n` 必须带"pcap 域截断值、sink 全长 50,000,620"注。
- 审查披露的 **MSYS 路径改写新实例**（`--get /tmp/…` 需 `MSYS_NO_PATHCONV=1`）登记入台账（与 #72 同族）。
- **归档决定**：`raw/pcap/`（1.9 GB）**留盘不入库**（.gitignore 已加一条针对性规则）；`raw/` 根下复算件（脚本/校验输出/.err）随本件入库 = **B4 轮全量大 pcap 的本地唯一归档**（原 B4 轮目录只有 ctl 小件——这条缺口由此处补上）。
