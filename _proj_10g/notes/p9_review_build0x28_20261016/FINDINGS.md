# 0x28 构建轮（`525d439`）对抗审查 FINDINGS（红队 · 只读）

> **agent 原件由平台拒写 .md ⇒ 全文回传、TL 代落盘**（本件正文 = agent 原文；文末 = TL 裁定折叠/亲证块）。
> 审查对象：提交 `525d439`（113 件 = 85 A + 28 M）· 轮目录 `_proj_10g/notes/p9_build_0x28/`
> 方法：全程只读；一切读数自原始件独立复算（自写 python / grep / `bash -n`）；未跑 xsim/xelab/vivado、未跑读侧工具任何模式（逐条文本核代替）、未碰对端机/未烧板
> 已落盘证据件（全在本目录）：`BASH_N_POST_0x28.txt` · `_selftest_pre_0x28.sh` · `_verify_target_sha.py` · `_check_edits_on_disk.py` · `_recompute_drift.py` · `_check_fp_universe.py` · `_probe_af08.py` · `_check_wlabel2.py` / `_count_tables.py` · `_residual_scan.py`

---

### ① 已证伪的声明 / 未报告的缺陷

**F1【高 · 交付件破损 · 判据无牙】`_proj_pcie/p7b_gate4_selftest.sh` 自本次提交起通不过 `bash -n`：外层 `if` 悬空**

- 复现（原件 = `BASH_N_POST_0x28.txt`）：
  - `bash -n _proj_pcie/p7b_gate4_selftest.sh` ⇒ `line 278: syntax error: unexpected end of file from 'if' command on line 73`，**RC=2**
  - 对照 1（提交前版本 `git show 4b22d1a:_proj_pcie/p7b_gate4_selftest.sh`，已落盘 `_selftest_pre_0x28.sh`）⇒ **RC=0**
  - 对照 2（另三个被改 .sh：negctrl / j6_r6fix / livefake）⇒ 全 RC=0；该文件**纯 LF**（CRLF=0）⇒ 排除环境干扰
- 定位：盘上 `:73` 新开 `if [ "$SW" -ge 75 ]`；`:89` `elif [ "$SW" -ge 71 ]; then`；**`:90` 紧接又一个 `if [ "$SW" -ge 71 ]; then`**（旧块被"逐字保留"式原样重放）。旧链唯一那个 `fi`（现 `:140`）只关了内层 ⇒ `:73` 的外层 `if/elif` **永远没有 `fi`** ⇒ 解析期即死（bash 先整段解析，零执行）
- 引入点 = 本轮 diff `git show 525d439 -- _proj_pcie/p7b_gate4_selftest.sh`（新增行 `+elif … -ge 71 ]; then` 紧接 context 行 ` if … -ge 71 ]; then`）；盘上 blob `7cf3eb3` = 提交内容（`git hash-object` 逐字相同）
- **为什么全轮绿灯没抓到**：`ASSERT_BID28_FINAL.txt` 对该件的 A 断言只数**文本**（`地址条数 = 15 / 期望 15 (末条 0x15C)` **PASS**）；`REHEARSE OK —— 全绿 ⇒ 清单完整且自洽` 的"自洽"= 文本编辑级，**不含"产生的文件能否被 bash 解析"这一面**。Report §②-1 自称的"新分支+旧分支逐字保留的构造式"**正是缺陷源**（"旧分支降为 elif"实际做成了"elif + 旧 if 完整重放"）
- 影响面：不为任何已报数字背书（不在常驻矩阵 19 门里；现跑的板级轮不引用它）；**但它是活工具**（12+ 笔记引用），下次谁跑谁在解析期硬失败。修复 = 在 `:140` 后补一个 `fi`（或改写配对）；建议把 `bash -n` 加进读侧 A 段对 .sh 的断言

**F2【低 · 报告与原件不符（转录）】** REPORT ②-2 assert 行写 "B 4 族 **436** 命中"，原件 `ASSERT_BID28_FINAL.txt:14-18` = `121+112+147+49`，末行 **"4 族 / 429 命中文件"**。436 是 dry-run 侧值（`DRYRUN_BID28_OUTPUT.txt:82` = 129+112+147+48）。实质结论（未登记 0）两侧原件都成立 ⇒ 只错在抄写

**F3【低 · 判据牙齿边界】** "一次收口（计数式）"三计数（`^P7B_ROUND #1` 恰 1 等）本身对"重跑"**无判别力**（bat `:70` 用 `>` 截断重定向 ⇒ 第二次调用会抹掉第一次 ⇒ "恰 1"是截断的必然产物）。我另找到两条独立旁证支持单次调用：`p7b_build_archive/20261016_*` **只有 `20261016_001456` 一个目录** + stdout 时间线连续 ⇒ "一次收口"结论**成立（旁证）**，但三条计数只该当"无重复痕迹"弱证据引用

**F4【低 · 预存工具缺陷 + 原件错误注记】** `MATRIX_TAIL_run1.txt` 的 `DIGEST_ALL(content)=af08f8ee…` 与 NOTE 是**误归因**：我逐值定位——`92510c51…`（stored/报告引用）= 对"sha relpath"**行**排序摘要；`af08f8ee…` = 按 **relpath 键**排序摘要；**两者都是 content-only，差异只在排序**；NOTE 声称的"pre-content-v1 scheme (included size/mtime)"**因果错误**（含 size 变体我算了 = `024e5041…`，无关）。该 NOTE 每次运行都会打印。p4gate.py 本轮未改（不在 7 漂移/28 M）⇒ 预存 wart；FROZEN 判决走哈希比对，不受影响

**F5【低 · 原件内部空小节】** `READINGS_BID28.txt` 的 "--- 三类失败端点 (routed) --" 小节为空；真值我已在 `board_rpt/p7b_ku5p_timing.rpt:157` 与 `MATRIX_TAIL` 的 `TIMING_SUMMARY:` 行复核 ⇒ REPORT ⑤ 说法成立，仅汇总件该格无值

**F6【低 · 登记】** "只并列不归因"最接近边界一句（判定未越界）：`REPORT.md:122` "…E12 恰好把这个阵列扩大了…⇒ 形态 = 整个阵列的复位网，不是 E12 字专属…⛔ 只并列、不归因（无拆刀臂）"。同段主动打断暗示链、末句显式拒因 ⇒ 合规；仅按"转述丢防线"纪律登记

---

### ② 复算一致（独立核过的清单）

**读侧面**
1. `TARGET_SHA_{BEFORE,AFTER}_BID28.txt`：20 件；**20/20 BEFORE≠AFTER**；**盘上 sha == AFTER 全 20**（`_verify_target_sha.py` 自算）
2. `EDITS_28_BLOCK.txt` = **63 条 = BID 24 + GEOM 39**（几何标题行切分）；逐条 ast 解析比对：**63/63 new 文本在盘上**（"报了但没改"=0）；59 条替换型 **old 残留 0**；4 条插入型按设计保留。⇒ 无"改了但没生效/报了但没改"
3. 几何不变量：`wrapper_p4.v:3296 SNAP_NW_P6E=75` ✓；`:3317 SNAP_P7BDP_NW=35`（31→35 ✓）；未实现 `0x15C`（派生式 0x20+4·75+16=0x15C ✓）；`p6e_snap_check.sh` WLABEL = **75** 条；negctrl V = **75** tokens（W51..W74 = 24 个 0 ✓）；selftest 新 FAKE_TAIL 枝 15 条/末条 0X15C ✓（**但见 F1：文件不可执行**）
4. 哨兵现读：`j6_r6fix:75/76`、`tcpreg_j6:69/70`、`p7b_snap:75/77`、`p6e_snap_check:60/72`、`gate4_accept:131/137`、`final_state:31` 全 = 0x28 / 75 ✓
5. `check_window.py`：`9+1+14 = 24 = 75−51` ✓
6. 残留 `0x00000027` 活行全扫：3 处"非注释"命中**全部是刻意历史**（GEOM_TIERS ×2 + livefake NW 字典）；无漏改活值 ✓
7. 语法面：11 个被改 .sh 中 10 个 RC=0（唯一 RC=2 = F1）；3 个 .py compile OK（`.bat` 无解析器，见 ③）

**矩阵/指纹面**
8. 漂移独立重算：**恰 7 CONTENT-CHANGED / ADDED 0 / GONE 0，272↔272**；7 件与 `FP_DRIFT_vs_0x27.txt` 逐名同；`before==after` 冻结 ✓；归档副本 sha == sim/p4sim 原件 ✓
9. ⭐ **"不在指纹宇宙"独立复现**：从 272 件名单直接判成员——**读侧 20 文件命中 0**、**`sim/p6e_pcie/*` 命中 0** ⇒ 两处"实测为空"成立
10. `DIGEST_ALL=92510c51…` 按写侧口径独立重算**逐字命中**（`DIGEST_COMPILE` 未复算，见 ③-注①）；`19/19 gates failed:0 FROZEN` 亲读；19 门名逐一数过；swc 门 8 条 RSRC 见证 + PASS ✓
11. `INPUT_HASHES_{BEFORE,AFTER}_GATES`：227 件，`diff` RC=0 ✓

**门面**
12. p6e 双门：**147/1 → 148/0 + PASS_ALL**；**25/1 → 26/0 + PASS_ALL**；唯一红 = BID 咬合见证（0x28 vs 0x27 / 40 vs 39）逐字命中；H 段读数两臂逐字相同 ✓

**构建面**
13. 计数式：`^P7B DONE$`=1、裸=2、`^P7B_ROUND #1 `=1、`Exiting Vivado`=3 ✓；WNS +0.065 / WHS +0.010 / CONVERGED=2；`#1=5→#2=0` 与 0x27 轮 stdout **逐字同** ✓
14. 三类失败端点（routed 报告亲读）：setup **0/261189** · hold **0/261189** · pulse **0/84774**；`Slack (VIOLATED)`=0；"All user specified timing constraints are met." ✓
15. 12 键硬门按 bat 定义逐键 grep = **全 0**；`-FAIL`=0；`BITSTREAM-OK` ✓
16. DRC **69 全 Warning / 0E0C / 五族 4-2-4-18-41**，与 0x27 轮+归档件**逐数相同** ✓；route 0 错 / 138098 fully routed ✓；XDMA 七行 + VERDICT=OK ✓
17. 位流三重一致 `79c9cf43…bec8`（15,431,261 B）；`.bit` 头逐字含 `SW_CRC=5a5cd561` + `wrapper_p4` + `xcku5p-ffvb676-1-e` + `2026/10/16 00:52:36` ✓；归档位流 = `5c17b14f…3385`（0x27，provenance 成立）✓；两份 SHA256SUMS 全对（轮目录 84 件 `sha256sum -c` 全 OK）✓
18. 构建窗口 287 件 0 变 ✓；资源四组现读命中、delta（−481/+533/−610/+514）算术成立，0x27 基线用**双原件**（0x27 轮报告 + 本轮归档件）核 ✓

**STA 面**
19. ⭐ 六个报告面对 `stat_up_ev|stat_sw_req|stat_sw_apply|stat_up_pend|biz_w7|app_up_ev` **各 0 命中**（独立复现）；松模式 `u_app` = 20(x27，全为 u_app_udp)/0(x28) ✓
20. 四族 ncell=37、from/to_worst 与 dp_to 范围**逐值命中**；网 36/36/36/36 + biz_w71..74=32×4 + app_*=0 + ev_up=69（两代同）+ ev_same/other=0 + sw_apply 0→36 ✓
21. WNS 宿主四行、位索引→字映射算术（2277→W71 含 E12 新字）、x27 侧 +0.069/lvl14、x28 DPWNS +0.068/lvl11、DP top10 组成（3×retx+7×fifo_a / 10×ackq）✓；`u_app` 2358→2496、`ref_snap_p7bdp` 1521→1776 / 0.142→0.067 ✓

**提交面**
23. `525d439` = **113 件（85 A + 28 M）**；28 M 与 REPORT ⑦-11 逐项吻合；wrapper **numstat 28/2、恰 1 hunk**、diff 内 `app_reg` 0 命中（禁碰区 `:1345-1347` 一字未动）✓；**CRLF 5025 / loneCR 0** ✓
24. 工作树**无 modified tracked**（已全部入库）；未跟踪 105 条（既有残渣 + 新轮目录）；wrapper/selftest blob 均 = commit 内容 ✓
25. "未烧板"间接证据：轮目录无 burn 产物；时间线全串行（门 23:40/23:42 → 矩阵 23:43–00:12 → 归档 00:14:56 → 构建 → STA 00:59/01:04 → 提交 01:12:19）；板级轮目录 01:15+ 为新开独立轮 ✓

---

### ③ 无法判定（缺件/缺环境）

- **板级行为**：未烧板（报告自认轮界）；E12 计数器"板上被激励"= 未观测
- **E12↔WNS 换宿主的因果**：无拆刀臂 ⇒ 结构上不可判（只确认"不同对象 + 不同检查类型 setup↔recovery"形态事实）
- **`DIGEST_COMPILE`（cf79c898…/221）**：复算需复建 manifests∪HLS 编译集，本轮未做 ⇒ 未独立复算。注①
- **②-1 的"生成器首版 G6 写错当场废弃"叙事**：归档件里只有最终版；"表长断言异常"字符串出现处 = dry-run/负控**预期红**（`DRYRUN_BID28_OUTPUT.txt:76`、`NEGCTL_table_0x28.txt:7`）⇒ 无法区分"废弃首版"与普通待改红，不可独立核（不影响结论）
- **4 个被改 .bat**：无解析器做整文件对照；仅文本级核（new 在盘 / old 无活行残留）⇒ "bat 面无新破坏"未证（既有限制）

### 与派单描述对账
- 派单说的"插入型编辑假 FAIL / `nnew_top` 派生式"先例：后者本轮现读成立无假 FAIL；但前者以**新形态**出现——F1 = 插入型编辑造成**真破坏**而文本门全绿（与"假 FAIL"相反方向）
- "改了但没生效 / 报了但没改"：**63/63 逐条盘上对照 0 例**；唯一"报了但东西是坏的"= F1（A 断言报 OK、文件不可解析）

**一句话**：本轮**数字面全部经独立复算成立**（63 处同步 0 漏改、几何不变量、矩阵 7/0/0 冻结、双门 148/0+26/0、构建 WNS +0.065/0/0/0、位流三重一致、STA 精确 0 命中、"不在指纹宇宙"属实、提交面/未烧板均吻合）；抓到 **1 条高 severity 未报告缺陷 = `p7b_gate4_selftest.sh` 被本轮的"插入+重放"构造搞成不能用（`bash -n` RC=2，提交前 RC=0），而该轮的文本级 A 断言/REHEARSE 结构性看不见它**；另有 4 条低 severity 报告-vs-原件不符/预存工具 wart 登记。

---

## TL 裁定折叠 / 亲证块（2026-10-16 01:4x–01:5x，TL 亲测亲修）

**F1 亲证（成立）**：
- `bash -n _proj_pcie/p7b_gate4_selftest.sh` ⇒ `line 278: syntax error: unexpected end of file from 'if' command on line 73` **RC=2**；`git show 4b22d1a:_proj_pcie/p7b_gate4_selftest.sh | bash -n /dev/stdin` ⇒ **RC=0** ⇒ 引入点与定位**逐字复核成立**（复盘结构 = `:73 if 75` → `:89 elif 71`（新）→ `:90 if 71`（旧行重放）→ 全链唯一 `fi` 只闭内层）。

**修复（提交随本件）= 两处**：
1. **语法**：删除 `:90` 重放的 `if [ "$SW" -ge 71 ]; then` 行（`git diff --numstat` = **0/1**）⇒ 恢复单一 `if/elif/else` 链。
2. ⚠️ **语法修好后暴露的第二条（审查未及，TL 新发现）**：`UNIMPL_A` 仍是 M1 前公式 `0x20+4*SW`（SW=75 ⇒ **0X14C**），而检查器默认 = `0x20+4*SW+16`（`p6e_snap_check.sh:73`，75 ⇒ **0x15C**）⇒ 正例断言③"读过未实现地址"**结构性 BAD（自 M1 起陈旧，非本轮引入）**；修复 = 分档公式（`SW≥71` 加 16，与末字/FAKE_TAIL/检查器三方一致）。
- **端到端验证**（本目录 `TL_selftest_preUNIMPLfix_run.txt` / `TL_selftest_final_run.txt`）：修前语法修后跑 = `OK=13 BAD=1`（BAD 即 0X14C）；两处修后跑 = **`自证汇总: OK=14 BAD=0` RC=0** —— 正例 0 FAIL（读末字 `0X148` ✓ 读未实现 `0X15C` ✓ 序列 75 个连续 ✓ W74 印出 ✓）+ 负对照 `0X15C` 回真数据 ⇒ `6.1 FAIL` 有牙 ✓。
- 修复件现读 sha256 = **`187c9d35e4774c867ca6c227f06dd9da7c156580f4747bebf43d978359ee9a0a`**（⚠️ 与 `TARGET_SHA_AFTER_BID28.txt` 记录不同 = 设计如此，修复件取代；`selftest/` 产物随之刷新入提交）。
- **读侧工具兼容性**：本修复只删 1 行重放 + 改写 1 行派生（净 +4 行）⇒ 读侧 A/B/C/D 断言所依赖的文本锚（表长 15 / 默认 0x28 / NW 75）全部不动 ⇒ 重跑 assert 不受影响（未复跑，登记）。

**过程登记（采纳审查建议）**：
- ⭐ **"文本级断言看不见文件不可解析"**= 本缺陷逃逸的唯一原因（A 断言只数文本、REHEARSE 只验编辑自洽、19 门矩阵不含本件）⇒ **建议把 `bash -n`（及 .py 的 `compile`）加进读侧 A 段对改动 .sh/.py 的断言** —— **登记，未实施**（改读侧工具 = 下一轮，避免此刻动已提交的同步件）。
- F2（436→429）已入 `p9_build_0x28/REPORT.md` **TL ERRATA E-2**；F3/F4/F5/F6 按"低/登记"处置（F3 旁证已核、F4 = p4gate.py 预存 wart 登记不改、F5 真值在 timing.rpt、F6 合规）。
- 本件修复不触及 B4 板级轮所用任何工具（其写面 = 自身轮目录）—— 无并发冲突。
