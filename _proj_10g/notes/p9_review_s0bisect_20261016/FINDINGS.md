# FINDINGS — S-0 bisect 板级轮（提交 `fc2c92f`）对抗审查（红队，只读）

> **agent 原件由平台拒写 .md ⇒ 全文回传、TL 代落盘**（本件正文 = agent 原文；文末 = TL 裁定折叠/亲证块）。
> 审查对象 = `_proj_10g/notes/p9_s0bisect_board_20261016/`（REPORT.md + 原件 144 件 / 105 MB）。
> 方法 = 全部原件独立复算 + 跨轮交叉核（B1 `p9_board_0x27_k0_20261015` / B4 `p9_board_0x28_k0_20261016` / `p7b_build_0x1C` / `p7b_build_0x1D` / `p7b_buildE_build` / 历史 S0A `p7b_defect_board_20261011`）+ `git log/show/merge-base` 只读核时间线与祖先关系。
> 姿态 = **找错**；**不下 PASS/FAIL 裁定**。复算脚本 = 本目录 `recompute_table.py`、`recompute_l2_snap.py`（均可直接复跑）。

## 总览（三分类）

- **① 已证伪 2 条**（F-1 中 / F-2 中）+ **口径不完整 1 条**（F-2b 低-中）。核心判决面**未找到**任何证伪项。
- **② 复算一致**：TABLE 10 行逐格 0 mismatch；判决链每步坐实；LEGACY 机制与同代对照；烧录面 8/8；相邻两代差异声明全链（含行号 / mtime / git 祖先）；NIC CRC 观测；抓包三门；历史 S0A 对账；FINAL_STATE；B4 E-8 errata 在位。
- **③ 无法判定 / 局限 8 条**（L1–L8；多数为报告已自认，逐条按实登记）。

---

## ① 已证伪 / 不实

### F-1【中】REPORT §⑦-2 的四个"板侧 300 s"读数无一可从原件复现；其中两个可定证为"原始样本值被当成窗口差值"

- 声明出处：`REPORT.md:99`（"板侧 300 s 内 `ΔW51=+107,099,940 B`…`ΔW20=+88,914`…`ΔW55 +14,951`、`ΔW57 +1.71e9`"）；**同一组数已转进 `P7B_OPEN_ITEMS.md:102`（§0-54②）** ⇒ 订正须同步两处。
- 原件（唯一证据源）：`runs/remote/S0_1D_L2_snap.log`（1534 样本 / gen 3..1536 / 无缺口无回卷 / 环首→环尾跨度 **299.79 s**）· `runs/S0_1D_L2_stdout.txt`（显式 SNAP_PRE gen=2 / SNAP_POST gen=1537，KW2 仅含 43 51 20 5 14 15）。
- 独立复算（两套端点口径，任一套均 ≠ 声称值）：

| 量 | 声称值 | 显式 PRE(gen2)→POST(gen1537) | 环首(gen3)→环尾(gen1536) | 定证 |
|---|---|---|---|---|
| ΔW51 | +107,099,940 | 107,069,100（0→0x0661BEAC） | 107,001,940（64,240→107,066,180） | 穷举全部样本对：**0 个匹配**（0x06623724 在 log 中 0 命中） |
| ΔW20 | +88,914 | 88,971（0→0x15B8B） | 88,710（254→88,964） | 全部样本对 **0 匹配**；`0x00015B52`=88,914 是 **gen=1535 行的 W20 原始值**（全 log 唯一一次出现，`snap.log:18391`） |
| ΔW55 | +14,951 | （KW2 无 W55） | 14,961（10→14,971） | 唯一命中对 = gen3(10)→**gen1535(14,961)** —— 端点与其余量不一致 |
| ΔW57 | +1.71e9 | （KW2 无 W57） | 106,985,880（305,484,137→412,470,017） | 单窗内 W57 **任何样本对最大差 = 106,985,880**（声称值约 16.0×，不可达）；`0x65E6894F`=1,709,607,247≈1.71e9 是 **gen=796 行的 W43（mtx_stat_tx_words）原始值**（`snap.log:9524`） |

- 逐字对的项：NIC +88,760 包 / +112,185,346 B（nicpre→nicpost 现算）；tcpdump 73,891 捕获 / 0 dropped；"≈2.85 Mbps" 在两套口径下都站得住（2.854–2.856 Mbps）。
- 性质：转抄/取数混列（原始值当差值、端点跨行不一致、跨列混入 W43 列）。**不影响 bisect 判决**（这四个数只作"涓流 hang"的形态描述），但其为已入 OPEN_ITEMS 的对外读数。
- 订正建议（供 TL）：改用"环首→环尾"一组（四字齐全、同一端点）：`ΔW51=+107,001,940 B`、`ΔW20=+88,710`、`ΔW55=+14,961`、`ΔW57=+106,985,880`（≈2.85 Mbps 不变）；或注明"显式 PRE→POST = 107,069,100 / 88,971"。
- 复现命令：`/c/Users/zhxue/anaconda3/python.exe _proj_10g/notes/p9_review_s0bisect_20261016/recompute_l2_snap.py`

### F-2【中】REPORT §⑤-2 "本轮新增：0x24 在 LEGACY 口径 = 6/6 洁净…" 不实 —— 该实验（含登记）在 B1 轮（2026-10-15，早 2 天）已做过两次

- 声明出处：`REPORT.md:80`（"**本轮新增**：0x24 在 LEGACY 口径 = **6/6 洁净 / 738.6 Mbps / 0 STALL** ⇒ '0x24 不可复现'不是新 sink 默认的假象"）。
- 原件（B1 轮）：
  - `p9_board_0x27_k0_20261015/runs/run_K0N_S2B.log`：`sink_extra='--rcvbuf-after-connect'`、rcvbuf=2920、conns=6、**ID_BID=0x00000024**（在跑内身份门）；对应 `sink_K0N_S2B.txt` = **6/6 洁净 / 730.591 Mbps / 0 STALL / RC=0**；SINK_MD5 = `6d9b14f24725fa326ffe5b169f77e30f`（与本轮逐字同）。
  - `run_K0N_S2C.log`：同 LEGACY + **conns=12** ⇒ **12/12 洁净 / 755.756 Mbps / RC=0**。
  - B1 轮自身登记：`p9_board_0x27_k0_20261015/REPORT.md:102`（"S2B = S2 同参 + `--rcvbuf-after-connect`（**S-0 当年台架语义**逐字复现；`RCVBUF_ORDER=after_connect_LEGACY`）"）、`:116-117`（读数行）、`:125`（"…③ 台架语义（**已用 `--rcvbuf-after-connect` 复现**、不解释）"）。
- ⇒ 本轮 0x24 LEGACY 读数（738.6）= **复现**（与 B1 的 730.6 差 1.1%，落在跑间散布），不是新证据。
- 边界说明：该点**不改变** ④/整链结论（0x24 不是判决链的承重点）；且 B1 的"好代 × LEGACY 洁净"与本届"坏代 × LEGACY 幽灵 / 坏代 × before 洁净"合起来才是完整的 2×2。订正建议：⑤-2 的"本轮新增"改为"本轮复现（B1 轮已有 S2B/S2C，均洁净）"并引 B1 件。

### F-2b【低-中】§⑤-1 与 TL E-8 块"B1 的 0x24 读数用现役新默认（before_connect）"表述不完整

- `REPORT.md:79` 与 `p9_board_0x28_k0_20261016/REPORT.md:171`（E-8）均如此措辞。
- 事实：B1 的 0x24 臂共 **3 跑** —— `S2`（before_connect，862.137）/ `S2B`（LEGACY，730.591）/ `S2C`（LEGACY，12 连，755.756）；B4 §5.3-3 引用的"862 Mbps"只对应 S2。
- 若"B1 的 0x24 读数"仅指 B4 所引那一条 ⇒ 表述成立；按字面全量读 ⇒ 不成立（漏两条 LEGACY）。B4"同一构型"的订正（历史 S0A 旧 sink 隐式 after-connect vs B4 所引读数 before_connect，跨口径）本身仍成立；但"LEGACY 口径下 0x24 也干净"这层 10-15 即在 B1 登记（见 F-2）。

---

## ② 复算一致（清单；全部由原件逐值重算）

1. **TABLE.txt 全表**：以 `runs/remote/*_sink.txt` 为主源重算（conns/stall/phase/clean/agg 五列）⇒ **10 行 0 mismatch**；与 `runs/S0_*_stdout.txt` 副本亦逐字一致。判据实现 = `mk_table.py:26` 的 `mm > by*250//256`（见 L8 与 F-3 说明）。
2. **RC 列**：`S0_1D_L2=124(timeout)` 原行在案（`### SINK_RC=124`，墙钟 300.002 s）；其余 8 跑 `### SINK_RC=` 逐行与 TABLE 一致（1/1/1/0/0/0/0/0）；S0_1A 的 0 为重建值（见 L5）。
3. **相位错判据算术**：全部 9 条相位错逐条核 `mism ≈ bytes−bytes/256`，|Δ| ∈ [0.67, 33.98]（含 199,219,795 / 199,219,800 档）——判据族核实成立（"≤30 B"措辞见 L8）。
4. **判决链（LEGACY）**：`1A 有`（S0_1A_L：5 conns / 4 STALL / 相位错 3 / 25.532 Mbps，n=1 + 历史 S0A 同代同签名）→ `1F 无`（6/6 洁净 782.392）→ `1D 无`（L、L3 两次**独立烧录**各 6/6 洁净，n=2 有效）→ `1C 有`（S0_1C_L 4 STALL+相位错 3；S0_1C_L2 2 STALL+相位错 3）⇒ 收敛带 (0x1C, 0x1D)。代序核实：1A(26)<1C(28)<1D(29)<1F(31)<24(36) ⇒ bisect 取点序列（0x1F→0x1D→0x1C）正确。
5. **0x1C_L 极端值原始行**：`SINK_SUM conns=4 … stall_conns=4 … poll_tmo=12 … agg_Mbps=0.012` + 4 条 `SINK_CONN n POLL_TIMEOUT 3 x 5000 ms`。conns=4 = 60 s 预算被 4×≈15.1 s 的 stall 周期截断（非请求数缺席）——四连接全 STALL、其中 3 条相位错（mism 23270/13088/10181）与 REPORT ③ 表逐字对。
6. **LEGACY 传参**：`_tools/arm_s0.sh:96-98` 主体**不含**该 flag，经第 8 参 `SINK_EXTRA` 传入；每跑 BEGIN 行逐字留证 `sink_extra='--rcvbuf-after-connect'`（S0_1A/S0_1C_B 为 `sink_extra=''` ⇒ RCVBUF_ORDER=before_connect，与 sink 自报一致）。
7. **sink 语义（前提声明的事实基础）**：`_proj_pcie/p7b_biz/p7b_tcp_sink.cpp:223-240`（默认 setsockopt 在 connect **前** = 小窗进 SYN；LEGACY 在 connect **后** = 首窗通告为默认大窗 64240，注释 `:203-219` 逐字登记）+ `:330-332`（RCVBUF_ORDER 打印）。两臂**只差 setsockopt 位置这一件事**（源码逐行核）。现役二进制 md5 6d9b14f2… 与 B1/B4/persist 诸轮逐字同。
8. **同代对照**：0x1A → `S0_1A`(before) 6/6 洁净 867.595；0x1C → `S0_1C_B`(before) 6/6 洁净 883.388。两代的对照/幽灵**位次相反**（0x1A：对照在前、幽灵在后；0x1C：幽灵×2 在前、对照在后）⇒ 结构性排除"跑位次/首跑效应"型混淆（残余见 L4）。
9. **历史 S0A 对账**：`p7b_defect_board_20261011/runs/S0A_stdout.txt` = `ID_BID 0x1a`；`SINK_MD5 c6b624205d64f1f4bd723d8fd5cc6414`（≠ 现役，旧 sink 成立）；conns=6（3 OK/3 STALL）；相位错 3（56,719 / 199,219,800 ×2）；90.220 Mbps；wall 53.214 ⇒ REPORT ⑥ 表两列逐值对上。
10. **烧录面**：8/8 `BURN_*.txt` 全过（sha256 门 → HIGH/DONE/路径/新鲜度/无 ABORT 五判据 → 场景 C 根端口 remove+rescan → 身份门 BID/NW/UNIMPL → 全窗扫描 NFF=0 → `0x08` 解锁）。`burn/` 7 份位流副本 sha256 **现算**与各构建轮归档件逐字对上：0x1A↔`p7b_buildF_build/F`（89e89f31…0f45）、0x1C↔`p7b_build_0x1C`（09c280e4…ecbf）、0x1D↔`p7b_build_0x1D`（b48dc7ee…0b1f，r3 副本同 sha）、0x1F↔`p7b_build_0x1F`（e365c5ca…0133）、0x24↔`p9_build_0x24`（e3b07957…f1db）、0x28↔`p9_build_0x28`（79c9cf43…bec8）。`BURN_INDEX.txt` 8 行与原件对账一致。`burn_gen.sh` 全文核：只走 JTAG（`run_program_tcpreg.bat`），无 `write_cfgmem`/QSPI 路径（轮目录 grep 亦 0）。
11. **相邻两代差异声明逐条**：现树 `.PERSIST_EN(1'b1)` 在 `board/wrapper_p4.v:2185`（"0x1D 轮记 :2159"出处 = `p7b_build_0x1D/REPORT.md:26,30`，两代并列口径**两个都对**）✓；参数默认 `rtl/tcp_tx_frame.v:299 = 1'b0` ✓、门控点 `:752`/`:1273` ✓；0x1D 位流 mtime = **2026-10-11 02:30:33.958**（声称 02:30:33 逐字）✓；`a38d4a4` 提交 02:41:30 且 `git merge-base --is-ancestor a38d4a4 6b7d00e` → **rc=1（非祖先）** ⇒ 不在 0x1D 树（0x1C 位流 mtime 00:48:21 同此排除）✓；"A3 修复在 0x19" = `p7b_buildE_build/READINGS.txt:9`（构建 E = BID 0x19）✓ ⇒ B4 的 A3 候选证伪逻辑（幽灵在 0x1A/0x1C 均在 0x19 之后）**成立**；"0x1C 惰性两腿" = `p7b_build_0x1C/REPORT.md:34-35` ✓；0x1C 树 HEAD=`50828c9`（`p7b_build_0x1C/REPORT.md:58`）→ 0x1D 树 HEAD=`6b7d00e`（`p7b_build_0x1D/REPORT.md:20`，= P-1 修复提交）；`git log 50828c9..6b7d00e -- rtl/ board/ hls/ tb/ sim/` 内**只有 6b7d00e 与 420230e（归档轮）**；净源码改 = `rtl/tcp_tx_frame.v`（P-1）+ `board/wrapper_p4.v`（PERSIST_EN/BID/注释）⇒ "功能差 = persist 翻面 + P-1"的表述与本核一致（常量项报告已按 #64 标注）。
12. **NIC CRC 观测**：逐跑 nicpre/nicpost 现算 —— **仅 S0_1D_L2** `Δrx_eth_crc_err=+14,820`（`port_rx_bad` 同 +14,820）；**其余 9 跑 Δ=0**（其后 S0_1D_L3 / S0_24_L 维持 14,820 不再增长）⇒ "0→+14,820 / 其余 9 跑全 0 / 含前后紧邻跑"逐跑坐实。
13. **抓包三门逐跑**：9 跑 stdout `TCPDUMP_ARMED`×2 + `STOPPED_GRACEFULLY`×2；10×`.err` 均 0 dropped；0x1A 由 `.err` 承载（`listening on` + stats 块 + 0 dropped）✓。
14. **收尾态**：`env/FINAL_STATE_S0BISECT.txt` = BID `0x28` / `0x15C`=0xffffffff / `0x08`=0 / CARRIER=1 / ID_RC=0 ✓；"对端 23:19 重启"由 0x1A burn log 的 dmesg 时间戳佐证（`identify_bars 1 BARs @1289.98 s`、rescan 后 `2 BARs @1436.5 s`，burn 时刻 23:43:56 ⇒ 内核寿命 ≈24.0 min ⇒ 重启 ≈23:19）✓。
15. **B4 E-8 errata 在位**：`p9_board_0x28_k0_20261016/REPORT.md:169-172`（TL 声称"已追加"属实；内容 = A3 证伪 + 口径订正 + "0x24 ⊃ 0x1D ⇒ 预期行为"）。
16. **自认面核实**：`_tools/k0_analyze.sh` 在位但轮目录无 K0 输出 ⇒ "K0 未做"属实；REPORT ⑦-5 各项（无 `--seconds 300`、未分析全帧 pcap、相位错无 RTL 级见证、persist 无单变量拆刀）与原件面无矛盾。

---

## ③ 无法判定 / 局限（按实登记）

- **L1（n 粒度）**：0x1D"无" = **n=2 有效**（两次独立烧录 L/L3；第 3 跑被涓流 hang 作废）；0x1A"有" = n=1（+ 历史同代旧 sink 1 跑同签名）；0x1F"无" = n=1；0x24（本轮）"无" = n=1（另有 B1 复现 3 跑，见 F-2）；before_connect 对照 = 每代 n=1。效应量极大（ghost 臂 0.012–166 Mbps vs clean 臂 716–883 Mbps）降低小 n 的风险，但"n=2 当结论"这一点应在头条结论上明示（REPORT ②/③ 已披露"n=2 有效"，TL 块未带）。
- **L2（消灭者收窄）**：0x1C→0x1D 至少含两件同树功能改（PERSIST_EN 翻面 + P-1 修复）+ 常量类改动，**无单变量拆刀** ⇒ 只能写"persist 刀"、【推断】不能收窄到其任一子件；#64 进一步禁止由位流行为反推具体改件。报告已按【推断】标注。
- **L3（相位错机制）**：REPORT ④(c) 的"相位错 = STALL 生命周期下游症状（换流门 `up_ok`）"为【推断】；`rtl/app_pattern.v:549` 行号引用**现核正确**（`wire up_ok = idle_now || (…);`），但机制本身无 RTL 级见证（报告 ⑦-5 已自认）。
- **L4（LEGACY 前提的证据强度）**：支持 = 2 代 × 1 同代对照（全洁净）+ 3 条 LEGACY 坏代跑（全幽灵）+ sink 源码级机制（旧行为 = 首窗 64240 → 小缓冲被冲，"微窗 stall 触发变量"，sinkfix 轮已登记）；第三解释候选（跑位次/首跑效应）被两代相反的位次排除。残余局限 = 对照臂每代 n=1、跨会话无重复、不能排除"与 rcvbuf 序共变的未记录环境差异"（低概率）。**评估：方向可信、按 n=small 携带**。
- **L5（0x1A 行两格为间接证据）**：S0_1A 的 in-run 身份门未落盘（stdout 丢，文件仅 peer_ssh GBK 报错行）⇒ 该行 BID 证据 = 烧录后 ID_OK（23:43:54，0x1a）+ 邻跑 S0_1A_L 的 in-run `ID_BID 0x0000001a`；该行 `SRC_RC=0` 为 mk_table.py 硬编码重建（TABLE 已带注；`SINK_DONE`+完整 SUM 佐证完成）。
- **L6（部署自检无产物）**：REPORT ① 的 selftest 四门读数（30/0 · 48/0 · 42/0/SKIP=0 · PASS）与"首轮四门假红⇒补齐（md5 与 B1 逐字同）"在本机**无落盘产物**（`deploy_peer.sh` 只做 tail 打印；deploy stdout 未归档）⇒ 本机不可复算（非判据输入，风险低）。
- **L7（pcap 未随轮归档；件数差 1）**：全部判决落在 sink 侧，pcap 只在 stdout 记 sha256/字节（报告自认"未分析全帧 pcap"）⇒"原始件全落盘"对 pcap 不成立。另：轮目录实际 **144 件**（`find . -type f | wc -l`；burn/ 实为 25 件 = 脚本+索引+8 日志+8 stdout 副本+7 位流），报告与 TL 块写 **143**（差 1，口径低危）。105 MB 体积核对 ✓（109,582,255 B）。
- **L8（判据文档 vs 实现不一致 + "≤30 B"边界歧义）**：(a) TABLE 表头写"phase error = `first_mismatch==0 AND mism ≈ bytes − bytes/256`"（≈0.99609·bytes），而 `mk_table.py:26` 实现为 `mm > by*250//256`（≈0.97656·bytes，更松）——本轮 9 条实测 mism/bytes ∈ [0.9957, 0.9961] 两口径同判（无实际影响），但**文档与实现应统一**，否则未来"前 98% 错、后 2% 对"的流两口径判反。(b) REPORT ⑥"算术逐条复核差 ≤30 B"：按该表两列全体（含历史 S0A 与 0x1C_L2 的 199,219,800 条目）最大 |Δ|=33.98；仅按本轮 S0_1A_L 三列则 ≤28.98 ⇒ 边界应写明。

---

## 附：备注（信息级，不列为 finding）

- `env/NIC_SETUP_20261016.txt` 有一行 `netlink error: Operation not permitted`（来源未注明；其后四行见证全落地：unmanaged / /32 / route / adaptive-off）——信息级。
- REPORT ① 的 "PEER_PW 只作前缀、轮目录 grep 0 命中"：实值 0 命中成立（无密码物料）；字面字符串 `PEER_PW` 有 3 处（`burn/burn_gen.sh:6,18` 变量名 + `REPORT.md:17` 自证行）——措辞可更精确。
- 0x1D 烧 3 次（第 5/7 次为同 sha 重烧）+ 0x24 一轮内 n=1：与"每次测量前必重烧"纪律一致，非问题。

## 裁定权声明

本件只给读数、复算与证据强度评估；**bisect 收敛、消灭者【推断】、A3 证伪、口径订正诸项是否采纳与如何改写，裁定权在 TL / 用户。**

---

**TL 接手要点（原文）**：核心判决面（逐跑表 / 判决链 / 烧录身份 / 两代差异声明 / CRC 观测）**逐值复核全对**；需要动作的只有两处 —— **F-1**：`REPORT.md:99` + `OPEN_ITEMS.md:102` 的四个 L2 板侧读数应订正为可复现值（环首→环尾一组：107,001,940 / 88,710 / 14,961 / 106,985,880）；**F-2/F-2b**：`REPORT.md:79-80` 的"本轮新增 / B1 用新默认"两处措辞应订正（B1 轮 S2B/S2C 已登记 0x24×LEGACY 洁净），并可在 B4 E-8 就地补一行。

---

## TL 裁定折叠 / 亲证块（2026-10-17 03:0x，TL 亲算）

- **F-1 亲证成立**：自写解析器直读 `runs/remote/S0_1D_L2_snap.log` 环首→环尾 ⇒ **W51: 64,240→107,066,180 = Δ107,001,940 · W20: 254→88,964 = Δ88,710 · W55: 10→14,971 = Δ14,961 · W57: 305,484,137→412,470,017 = Δ106,985,880** —— 与审查订正组**逐位一致**；原声称四值（107,099,940 / 88,914 / 14,951 / 1.71e9）无一对可复现（后两者定证 = 原始样本值）。
- **F-2/F-2b 亲证成立**：B1 `run_K0N_S2B.log` 首行 = `sink_extra='--rcvbuf-after-connect'` + `ID_BID 0x00000024` + `SINK_RCVBUF_ORDER=after_connect_LEGACY`，`sink_K0N_S2B.txt` = `clean_conns=6 / stall_conns=0 / wall_s=13.140` ⇒ "0x24×LEGACY 洁净"确在 B1 已登记。
- **折叠处置（全部采纳，同批落地）**：① bisect REPORT 追加 **TL ERRATA（E-1..E-3）**（F-1 四值订正 + F-2 "本轮新增"→"本轮复现" + F-2b 措辞收窄 + L1–L8 局限登记）；② `P7B_OPEN_ITEMS.md` §0-54② 四值**就地订正**（标注取证复算值）；③ B4 REPORT E-8 补一行（B1 三跑口径）。④ **核心裁决不变**：收敛（0x1C/0x1D）、persist【推断】、A3 证伪、LEGACY 口径订正 —— 均获逐值复核支持。
