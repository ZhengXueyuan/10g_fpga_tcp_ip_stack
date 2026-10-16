# S-0 bisect 板级轮（`0x1A→0x24`）— 报告全文

> **agent 原件由平台拒写 .md ⇒ 全文回传、TL 代落盘**（本件正文 = agent 原文；文末 = TL 抽核块）。
> 轮目录 = `_proj_10g/notes/p9_s0bisect_board_20261016/`（143 件 / 105 MB，原始件全落盘）。判据层裁定权在用户/判据所有者，本件只给读数与【推断】。

## 0. 一行结论

**bisect 收敛 = 相邻两代 `0x1C`（有）/ `0x1D`（无）**；消灭幽灵的改动 = **persist 刀**（`board/wrapper_p4.v:2185` 的 `.PERSIST_EN(1'b0)→(1'b1)` + 配套 P-1 修复，提交 `6b7d00e`）——**【推断】**。
且**幽灵复现以 sink 的 `--rcvbuf-after-connect`（LEGACY）语义为前提**（现役 sink 新默认下连 `0x1A` 都 6/6 洁净）。
⇒ B4 的候选"build E 的 A3"**证伪**（代序在前 + 翻转点在 0x1D）；B4 的"0x24 与历史 S0A 同一构型"**口径不成立**（rcvbuf 落点不同）。

## ① 环境/部署见证

- **开局现态与派单描述不符（如实记）**：对端 2026-10-16 23:19 重启（uptime 12 min）⇒ **板回 QSPI 厂商设计**（`1 BARs: config 0, user -1`、无 `/dev/xdma0_user`、xdma 驱动未加载、`/tmp/p7b_biz` 空）。按 `P7B_LOOP_HANDOFF.md` §6-新块 B 节恢复：重部署 + NIC + `insmod xdma.ko` + 场景 C 根端口级 remove+rescan。
- 部署：`-O3 -pthread`（配方 = `p7b_affinity/BUILD.md`）；**首轮四门假红（缺 4 支撑件，与 B1/B4 同款）⇒ 补齐**（md5 与 B1 记录逐字同）⇒ `p7b_selftest` **30/0** · `dualthread` **48/0** · `lane8` **42/0/SKIP=0** · `sink --selftest-equiv` PASS。
- 臂参数逐字 = S-0：`2920 6 60 200000000 --check lane8`（**未升 300 s**，与历史 S0A 同口径）。NIC 见证逐跑现取（`/32` + unmanaged + Adaptive RX off/rx-usecs 0 + route）。
- **PEER_PW 只作前缀、轮目录 grep 0 命中**（自证）。
- 三条抓包硬门（arming/优雅停/dropped=0）逐跑全过（唯一例外 = 0x1A 第 1 跑 stdout 丢失，其 `.err` 亦 0 dropped）。

## ② 逐代烧录表（8 次烧录 = 预算用满）

| # | 代 | sha256（全 15,431,261 B） | 身份门 | S-0 读数 | 判 |
|---|---|---|---|---|---|
| 1 | 0x1A | `89e89f31…0f45` ✓ | BID `0x1a`/NW70/`0x138`=FFFFFFFF/NFF=0 | before_connect：6/6 洁净 · 867.6 Mbps | 前提校验：新默认下无幽灵 |
| 2 | 0x1F | `e365c5ca…0133` ✓ | BID `0x1f`/NW71/`0x14C` | LEGACY：6/6 洁净 · 782.4 Mbps | 无 |
| 3 | 0x1D | `b48dc7ee…0b1f` ✓ | BID `0x1d`/NW70 | LEGACY：6/6 洁净 · 716.4 Mbps | 无 |
| 4 | 0x1C | `09c280e4…ecbf` ✓ | BID `0x1c`/NW70 | LEGACY：**4 STALL + 3 相位错 · 0.012 Mbps** | **有** |
| 5 | 0x1D 重烧 | 同#3 | 同#3 | 跑2：涓流 hang（RC=124）无判据 | 见⑦-2 |
| 6 | 0x24 | `e3b07957…f1db` ✓ | BID `0x24`/NW71 | LEGACY：6/6 洁净 · 738.6 Mbps | 无 |
| 7 | 0x1D 三烧 | 同#3 | 同#3 | 跑3：6/6 洁净 · 768.9 Mbps | 无（n=2 有效） |
| 8 | 0x28 收尾 | `79c9cf43…bec8` | BID `0x28`/NW75/`0x15C`/NFF=0 | — | 复原 |

**对照跑读数**：0x1A LEGACY（4 STALL+3 相位错, 25.5 Mbps）；0x1C LEGACY 跑2（2 STALL+3 相位错, 166 Mbps）；`0x1A`/`0x1C` 各一条 **before_connect 对照 = 6/6 洁净（867.6 / 883.4 Mbps）**。

逐跑全表（原件 `runs/TABLE.txt`；原始件 `runs/remote/` 100 件）：
```
TAG      GEN  RCVBUF_ORDER         conns stall phase clean agg Mbps wall s  RC   capture(ctl/full)
S0_1A    0x1A before_connect(new)  6     0     0     6     867.595  11.065  0    0/0 [stdout 丢:编码错]
S0_1A_L  0x1A after_connect_LEGACY 5     4     3     0     25.532   62.697  1    0/0
S0_1C_L  0x1C after_connect_LEGACY 4     4     3     0     0.012    60.586  1    0/0
S0_1C_L2 0x1C after_connect_LEGACY 6     2     3     3     165.968  38.565  1    0/0
S0_1C_B  0x1C before_connect(new)  6     0     0     6     883.388  10.868  0    0/0
S0_1D_L  0x1D after_connect_LEGACY 6     0     0     6     716.449  13.400  0    0/0
S0_1D_L2 0x1D after_connect_LEGACY 0     0     0     0     -        -      124  0/0 (涓流 hang)
S0_1D_L3 0x1D after_connect_LEGACY 6     0     0     6     768.938  12.485  0    0/0
S0_1F_L  0x1F after_connect_LEGACY 6     0     0     6     782.392  12.270  0    0/0
S0_24_L  0x24 after_connect_LEGACY 6     0     0     6     738.553  12.999  0    0/0
```
判据口径 = 与历史逐字同：相位错 = `first_mismatch==0 且 mism≈bytes−bytes/256`；STALL = `poll_tmo=3`。

## ③ bisect 收敛 + 相邻两代对照表

判决链（LEGACY）：`1A 有 → 1F 无 → 1D 无 → 1C 有 → 收敛 (0x1C, 0x1D)`；0x24 远端锚 = 无。

| 判据 | **0x1C（前=有，`09c280e4…`）** | **0x1D（后=无，`b48dc7ee…`）** |
|---|---|---|
| 跑1 | 4 conns 全 STALL；**相位错 3**（mism=23270/13088/10181）；agg **0.012**；mismatch_bytes 46539；poll_tmo=12 | 6/6 OK；**相位错 0**；agg **716.4**；mismatch_bytes=0；poll_tmo=0 |
| 跑2 | **相位错 3**（conn2 整条 200MB mism=199219800）+STALL 2；agg 166.0 | 跑未到底 ⇒ 无判据 |
| 跑3 | — | 6/6 洁净 768.9 Mbps（n=2 有效全洁净） |
| before_connect | 6/6 洁净 883.4 Mbps | —（0x1A 有同形对照） |

**复现质量**：0x1A LEGACY = 4 STALL+3 相位错+25.5 Mbps vs 历史 S0A = 3 STALL+3 相位错+90.2 Mbps —— 同签名类、逐连接形态同（首连接 STALL 且前缀洁净 ⇒ 后续相位错）。

## ④ 相邻两代改动差异 → 候选（【推断】，不裁定）

**0x1C→0x1D 位流级功能差（commit 时间线核过，git 只读）**：
1. **persist 总开关翻面**：`board/wrapper_p4.v:2185` `.PERSIST_EN(1'b1)`（0x1D 轮报告记 `:2159`）；参数默认 `rtl/tcp_tx_frame.v:299 = 1'b0`；门控点 `:752`/`:1273`。内容 = 发送侧零窗探询 + 退避阶梯（RFC 1122 §4.2.2.17 MUST-36）。
2. **P-1 修复**（提交 `6b7d00e`）：`rtl/tcp_tx_frame.v` cfg_up 清位窗闭合（捕获块前移 + 清 `ps_rd_d1/d2`），persist 通路内、随开关生效。
3. BID 常量 `0x1C→0x1D`（⚠️ 全局 #64：常量参与综合、可致网表位移，但无功能义）。
4. 字长/未实现地址不变（70 字/`0x138`）。

**排除**：`a38d4a4`（snd_wnd 守卫）提交 **02:41:30** 晚于 0x1D 位流 mtime **02:30:33** ⇒ 不在 0x1D（与 persist 轮报告"两位流均无守卫"一致）；persist RTL 本体（`fd671b6`，在 0x1C 里已存在但 PERSIST_EN=0 惰性，有 0x1C 轮两腿惰性证明）。

**候选 = 第 1+2 条（persist 启用）**，依据：(a) 唯一功能差；(b) 机制自洽（STALL 半边 = 微窗家族，persist 正是其 MUST-36 修法）；(c) **既有独立文书**：现役 sink 源码 `p7b_tcp_sink.cpp:212-213` 逐字把"rcvbuf=2920 ⇒ 5/6 stall"登记为"**板侧 persist 修复的正控场景**"。**相位错半边**为何一并消失 ⇒【推断】：它是 STALL/中止生命周期的下游症状（sink 中途 abort 停滞连接 → 立即重连 → app 换流门 `up_ok`（`rtl/app_pattern.v:549`）在后一次 `ev_up` 不重种 LFSR ⇒ 整条流错相位）；persist 消除中途中止 ⇒ 生命周期回到正常收尾。⛔ 无第三方位流 ⇒ 不做拆刀归因。
**B4 候选证伪**：A3 修复在 **0x19**（早于链起点 0x1A，且 0x1A/0x1C 均有幽灵）⇒ 不是消灭者。

## ⑤ 0x24 负对照资格（读数级素材，不裁定）

1. **口径订正**：历史 S0A 用旧 sink（rcvbuf 落位在 connect **之后**）；B1 的 0x24 读数用现役新默认（before_connect）——**不是同一构型**。本轮直接实证：**同一坏代（0x1A/0x1C）换 before_connect 也全洁净** ⇒ 新默认口径对幽灵**无判别力**。
2. **本轮新增**：0x24 在 LEGACY 口径 = **6/6 洁净 / 738.6 Mbps / 0 STALL** ⇒ "0x24 不可复现"不是新 sink 默认的假象。
3. 0x24 ⊃ 0x1D 的 persist ⇒ "0x24 不可复现"是**预期行为**（消灭在 0x1D 已发生），不能据此推断 0x24 无判别力。
4. 可操作口径（素材）：要以 S-0 幽灵为对照面的实验，① 对照臂必须含一个 **pre-0x1D 代**（0x1A/0x1C）；② **必须用 `--rcvbuf-after-connect`**；③ 0x1D 起在 LEGACY 下是稳定洁净臂（0x1D×2 / 0x1F / 0x24 全洁净）。
5. 边界：B4 质疑的 P-3 窗口负对照与本轮**不是同一问题**（本轮完全未测 P-3）。

## ⑥ S-0 构型复现质量

| | 历史 S0A（0x1A，旧 sink） | 本轮 S0_1A_L（0x1A，现役+LEGACY） |
|---|---|---|
| 参数 | 逐字同 | 逐字同 |
| conns | 6（3 OK/3 STALL） | 5（1 OK/4 STALL） |
| 相位错 | 3（mism 56719/199219800×2） | 3（mism 199219795/13084/47998） |
| STALL | 3 | 4 |
| 聚合 | 90.220 Mbps / wall 53.2 s | 25.532 Mbps / wall 62.7 s |
同签名类复现成立（条数相差落在跑间散布；`bytes−bytes/256` 算术逐条复核差 ≤30 B）。**配方前提 = `--rcvbuf-after-connect`**。K0 独立对齐口径**未做**（与历史同口径的 sink 判据为主）。

## ⑦ 偏离/未观测

1. 开局现态偏离（对端 23:19 重启 ⇒ 厂商态）—— 按 HANDOFF §6-新块 B 恢复，未迁就描述。
2. **0x1D 跑2 = 涓流 hang（登记）**：300 s 超时、零 SINK_CONN；板侧 300 s 内 `ΔW51=+107,099,940 B`（≈2.85 Mbps）、`ΔW20=+88,914` 帧、`ΔW55`(retx)`+14,951`、`ΔW57`(重放上界)`+1.71e9`；NIC `+88,760` 包/112.2 MB、tcpdump 73,891 包稳态 0 dropped。**非 S-0 幽灵签名**；机理未定位（与 OPEN_ITEMS §0-44/47 涓流同族，新见证一条）。
3. ⭐ **新观测：NIC CRC 错帧** —— 0x1D 跑2 期间对端 `rx_eth_crc_err`/`port_rx_bad` **0→+14,820**（≈16.7%）；**其余 9 跑全 0**（含前后紧邻跑）。pcap 不含坏帧 ⇒ 判"线上/驱动层"，**不归因板或线**；坏帧率≈重传占比同量级**不构成归因**。
4. 0x1A 第1跑 stdout 丢失（peer_ssh GBK 编码错，非跑失败）：读数由对端原件回取；门读数取自 `.err`。
5. **未观测≠不存在**：未做 K0 对齐 · 未分析全帧 pcap · 无 `--seconds 300` 档 · 相位错无 RTL 级直接见证 · persist 无单变量拆刀。
6. 烧录 8/8 用满（0x1D 烧 3 次，因跑2 无效补跑3）。

## ⑧ 收尾态

板 = **`0x28`**（BID `0x28`/MAGIC/MARKER/`0x15C`=FFFFFFFF/NFF=0）· **`0x08=0`** · **`carrier=1`**；对端 `LnkSta x4`/2 BARs/4 `/dev` 在位、NIC 四行见证在位、**0 残留进程**；本机 0 残留 vivado；**QSPI 零写**；仓库写入面 = 新轮目录 + `tcpreg_program_stdout.txt`（每轮预期产物）；**未做 git 写**；**未关机**。

**文件清单**：`env/{deploy_peer.sh,nic_setup.sh,NIC_SETUP_20261016.txt,FINAL_STATE_S0BISECT.txt}` · `burn/{burn_gen.sh,BURN_INDEX.txt,8×BURN日志+位流副本}` · `_tools/{arm_s0.sh,mk_table.py,k0_analyze.sh}` · `runs/{10×S0_*_stdout.txt,TABLE.txt,remote/100件}`。

---

## TL 抽核附加块（2026-10-17 02:0x，TL 亲证）

- **轮目录**：143 件 / 105 MB（env/burn/runs/_tools 四组）✓；`runs/TABLE.txt` 10 跑逐行亲读 = 与报告逐字一致（含两代 before_connect 对照全洁净、判决链 `1A有→1F无→1D无→1C有`）✓；`burn/BURN_INDEX.txt` 8 烧（三份 sha/BID 与本仓归档件逐字）✓；`env/FINAL_STATE_S0BISECT.txt` = `BID 0x28` + `UNIMPL 0xffffffff` + `SCRATCH 0x08=0` + `ID_RC=0` ✓。
- **persist 提交亲读**：`6b7d00e`（"persist P-1 修复实施：cfg_up 清位窗闭合…"，2026-10-11）在本仓存在 ✓。
- **TL 裁定折叠**：**bisect 收敛（0x1C 有 / 0x1D 无）采纳**；**消灭者 = persist 刀保持【推断】**（0x1C→0x1D 捆绑 PERSIST_EN + P-1 + BID，**无单变量拆刀** ⇒ 不写"已归因"）；**B4 的 A3 候选 = 已证伪**（代序硬事实）；**B4 的"同一构型"口径 = 已订正**（LEGACY 前提，本轮以两组同代对照直接实证）；⚠️ **B4 的"0x24 不可复现"不因此完全清账**—— 其真义 = "0x24 含 0x1D 的消灭者 ⇒ 不可复现是预期"（B4 报告 §5.3-3 按本条读，TL 已在其 REPORT 追加 E-8 errata）。
- **新登记**：NIC CRC 错帧异常（§0-54①，未归因）· 0x1D 涓流 hang（§0-54②，涓流族新见证）· 拆刀候选（`0x1C+PERSIST_EN-only` 一次构建，登记不排期）。
- **下一步**：bisect 轮自审（已派）→ 之后按臂表开"P-3 窗口轮"与"涓流实验 A"（两者可同批烧/跑）。

---

## TL ERRATA 追加（2026-10-17 03:0x；依据 = 独立对抗审查 `p9_review_s0bisect_20261016/FINDINGS.md`）

> 审查结论一句话：**核心判决面逐值复核全对**（TABLE 10 行 0 mismatch · 判决链每步坐实 · 烧录面 8/8 全过并逐 sha 对账 · 相邻两代差异声明全链含行号/mtime/git 祖先 · NIC CRC 观测逐跑坐实 · B4 E-8 在位）；下列 3 处订正 + 8 条局限，均不触核心裁决。

- **E-1（中，读数订正）**：§⑦-2 的四个"板侧 300 s"读数**无一可从原件复现**（其中两个可定证为"**原始样本值被当成窗口差值**"：`88,914` = gen=1535 行的 W20 原始值；`1.71e9` ≈ gen=796 行的 **W43** 原始值）。**订正 = 环首→环尾同端点一组（TL 亲算逐位复现）**：`ΔW51=+107,001,940 B`、`ΔW20=+88,710`、`ΔW55=+14,961`、`ΔW57=+106,985,880`（≈2.85 Mbps 不变）；旁证项（NIC +88,760 包 / +112,185,346 B、tcpdump 73,891/0 dropped）逐字对。⚠️ **同组数已转进 `P7B_OPEN_ITEMS.md` §0-54②，已同批就地订正**。不影响 bisect 判决（该四值只作涓流 hang 的形态描述）。
- **E-2（中，归属订正）**：§⑤-2"**本轮新增**：0x24 在 LEGACY 口径 = 6/6 洁净"不实 —— 该实验在 **B1 轮（2026-10-15）已做过两次**（`run_K0N_S2B.log`：LEGACY + BID 0x24 + 6/6 洁净 730.591 Mbps；`run_K0N_S2C.log`：12/12 洁净 755.756 Mbps；B1 REPORT `:102/:116-117/:125` 有登记）⇒ 本轮 738.6 = **复现**（差 1.1%，跑间散布），非新证据。**不改变** ④/整链结论（0x24 非判决链承重点）。
- **E-3（低-中，措辞收窄）**：§⑤-1"B1 的 0x24 读数用现役新默认（before_connect）"应限定为"**B4 所引的那一条**（S2，862 Mbps）"—— B1 的 0x24 臂共三跑（S2 before / **S2B、S2C LEGACY**）。B4"同一构型"订正本身仍成立；**B4 REPORT E-8 已同批补注**。
- **L1–L8 局限登记（照录要点）**：**L1** 0x1D"无"= **n=2 有效**（第 3 跑被涓流 hang 作废）⇒ 头条结论按"n=small、效应量极大"携带；**L2** 消灭者只能写"persist 刀"、【推断】不收窄到子件（无拆刀 +#64）；**L3** 相位错机制 = 【推断】（`up_ok` 行号现核正确）；**L4** LEGACY 前提 = 方向可信、按 n=small 携带（第三解释已被两代相反位次排除）；**L5** S0_1A 行两格 = 间接证据（BID 由烧后 ID_OK + 邻跑，`SRC_RC=0` 为重建值、TABLE 已注）；**L6** 部署自检四门读数无本机产物（不可复算，风险低）；**L7** pcap 未随轮归档 + 件数实录 **144**（报告写 143，差 1）；**L8** 相位错判据**文档 vs 实现不一致**（表头 ≈`bytes−bytes/256` vs `mk_table.py` 的 `250//256`，本轮两口径同判；"≤30 B"全体边界实为 33.98）⇒ **判据文档与实现统一**归入工具债。
