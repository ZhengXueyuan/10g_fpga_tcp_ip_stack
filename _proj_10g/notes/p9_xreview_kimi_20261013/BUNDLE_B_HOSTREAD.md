# B 捆对抗审查（Kimi 组 → Claude 组交付物）：宿主读循环修复（--dual / --aio / READLOG）

> **审查人**：跨组对抗审查员（Kimi 组，对 Claude 组交付做只读找茬）
> **审查日期**：2026-10-13
> **审查对象**：
> - 口径件：`_proj_10g/notes/p9_hostread_20261013/REPORT.md`（顶部「复核订正块」= 权威口径）+ 同目录 `REVIEW.md`
> - 代码：`_proj_pcie/p7b_biz/p7b_mir_dump.cpp`（现读件 md5 `b4833c55642120f093fa2ee9e2544aa8`，与订正块 C 表「改后源」逐字同 ⇒ 审的就是订正轮最终件）
> - **diff 区间**：`447f76f..7a22d97`（a9397b0 = 功能轮引入；7a22d97 = 订正轮收口）。本地 diff 留档 `/tmp/xreview_b_diff.txt`（1062 行）
> **本审查不下 PASS/FAIL 裁定**；「未观测到」不写成「不存在」；只读（本机读文件 + Python 复算/状态推演），未跑 xsim、未跑板级窗、未碰 `rtl/**` `board/**`，未 commit/push，未改任何既有文件。

**发现计数：P0 = 0 · P1 = 1 · P2 = 5 · P3 = 4（合计 10）**。已验证成立的关键安全论证 1 项（desc_lock 环安全）；负对照构造验证 3 组（脚本与输出见末节）。

---

## 0. 对「权威口径」本身的核对（先于找茬）

- REPORT 订正块 H-8 引用的驱动行号**逐字现读核实**（原件 = `runs/driver_libxdma.c`，md5 `7146d28c…` 与 REVIEW §3 一致）：
  - `mutex_lock(&engine->desc_lock)` 在 **:3553**；`transfer_init` :3560；`transfer_queue` :3584；等完成 `:3594-3600`；`mutex_unlock` :3680；解锁只在错误分支 :3562/:3586/:3676 与 `while(nents)` 之后。**"持锁覆盖建表→排队→等完成全程"成立**。
  - 单笔钳制：`transfer_init` :2967-2969 `min(剩余, desc_max)` + :2998-2999 环边界钳（`desc_idx + desc_max >= engine->desc_max` ⇒ 收缩）——**成立**。
  - `xdma_xfer_submit_nowait` 自 :3824 起，函数体内**无任何 desc_lock**（`grep desc_lock`：:3236 属另一函数 `xdma_xfer_aperture`，3824–4170 区间无锁）——"aio 多笔真同时在环 ⇒ 保留几何闸"的区分**成立**。
  - 同步路径 prologue/epilogue：`driver_cdev_sgdma.c` 现读 —— `char_sgdma_map_user_buf_to_sgl` 在 `xdma_xfer_submit` 之前、`char_sgdma_unmap_user_buf` 在其后（REVIEW 引 :414-422，现读同形）；`c2h_timeout=10` 默认在 :44 ✓。
  - 附带回证 H-6 候选路径：`default:` 分支 :3639-3663 = `engine_status_read` → `transfer_abort` → `xdma_engine_stop` → `-ETIMEDOUT`，与订正块措辞一致。
- ⇒ **订正后口径的脊梁（desc_lock 全程持锁 ⇒ 双缓冲环不可能溢出 ⇒ 不设几何门）在驱动副本面上成立**。本审查在此基础上找茬，发现的是该口径**没有覆盖到的边角**，不是推翻它。

---

## 1. 发现清单（按严重度排序）

### P1

**P1-1｜dual 窗 READLOG 的 dw70/ddma 存在两段锁窗口竞态：「区间增量」口径对 --dual 不成立，且 Σdw70 不再保证 == drop。REPORT 口径句未带此限定，而 §2.6「双模 dw70」分析恰恰消费了这些行。**
- 位置：`_proj_pcie/p7b_biz/p7b_mir_dump.cpp:1199-1210`（采样在 `dual_mmio_snap` 的独立临界区 :1125-1129；dw70 计算与 `rl_w70` 更新在**第二个**临界区 :1201-1212）。
- 证据：线程 A 在 snap（取到 w70n）与 relock 之间无原子性；若线程 B 在同隙完成「采样（更晚的 w70）+ 更新 rl_w70」，则 A 行 `dw70 = w70n_A - rl_w70_B` = uint32 回绕大数，`rl_w70` 还可能被 A **回写成一个更小的旧值**（:1210 无大小比较）。构造性推演（末节 V2）：确定性交错下 A 行 dw70 = `0xFFFFFE0C`（应为 0）；随机调度 2000 次共出现 186,170 个回绕行。真机窗口仅数条指令、概率极低，但代码无原子性保证。
- 连带后果：① REPORT:96 口径句「Δw70/Δdma 属 [上一条→本条] 整区间」对 dual 窗字面不成立（已登记的拼接注记 :1282-1284 只管**行序/gap**，没管 dw70 的原子性）；② Σdw70 在 dual 下不伸缩归零 ⇒ `READLOG_SUM dw70_total` 对 dual 窗**不是 drop 的独立复算**（T15 恒等式只在 mock 同步路径证明）；③ REPORT §2.6/中-6 的「逐块 dw70 双模交替」结论建立在 A1 的 READLOG 行上 —— 交替形态按块粒度大概率不受微量竞态影响，但该分析**没有**「我行 dw70 采样-基线原子」这道前提的见证。
- 建议：把 snap 与 dw70 计算/rl 更新并入**同一个**临界区（一行锁的挪动）；或在 print_readlog/dual 头注里把 dual 窗的 dw70/ddma 行标注为「无序并发样本差，仅供分布参考」。顺手把 REPORT:96 口径句对 dual 加限定。

### P2

**P2-1｜`--dual` 的值无门：`--dual 1` / `--dual 3` 被静默忽略，安静走同步路径（或 aio）。未登记。**
- 位置：`_proj_pcie/p7b_biz/p7b_mir_dump.cpp:1523`（解析）、`:2181-2190`（分派只认 `dual == 2`）；参数门块 `:1557-1587` 只有 aio/readlog 的闸。
- 证据：`--dual 1` ⇒ `dual==2` 假、`aio_depth==0` ⇒ 落入 else 同步分支，无任何告警；与 §5-12 已登记的「--dual 2 --aio N 静默走 dual」同族，但「--dual 非 2 值静默失效」**不在**登记清单里。usage 文本（:1533-1541）也只字未提 `--dual`/`--dual-stagger-ms`。
- 影响：操作者打错字（`--dual 1`）会得到一窗**没有任何 dual 结构**的数据，还以为在测修复臂；若该窗又带 `--no-verify`，字节账完全正常 ⇒ 静默负对照失效。
- 建议：`dual != 0 && dual != 2` ⇒ FATAL exit 2（一行闸，与 --readlog 0|1 闸同款）；usage 补两行。

**P2-2｜AIO 的 io_submit / io_getevents 失败只打 stderr `FAIL:`：不置 `read_error`、不进 `MIR_STREAM_DONE` 行、也不直接进退出码。**
- 位置：`_proj_pcie/p7b_biz/p7b_mir_dump.cpp:879-884`（submit 失败置局部 `fail`）、`:896-908`（getevents 失败置 `fail`）；主判定 :2272 只查 `sr.read_error`。
- 证据：`fail` 是 `run_stream_aio` 的局部变量，唯一外显 = stderr 一行 + 跳过尾段同步读。`MIR_STREAM_DONE read_error=0` 与 stderr 的 `FAIL: io_submit …` 可以**同跑并存**；退出码只能靠式A/式B/quiesce 间接变红（大概率红，但不保证——例：submit 失败发生在 inflight==0 且板侧恰好 quiesced 的理论形态）。按本工程 #53 纪律（判决要从判据行走到退出码），这条 FAIL 没有牙。
- 建议：`fail=true` 时置 `r.read_error = true`（或在 main 加 `sr.aio_failed` 见证并入 exit 判定）；至少在 DONE 行加 `aio_fail=%d`。

**P2-3｜「默认路径逐位不变」字面目不实：默认（无新选项）`--stream` 的输出字节流与 447f76f 版有 3 类差异；订正块「字段名与相对顺序一字未动」口径成立，但 REPORT 边界句（:3）仍写「逐位不变」。**
- 位置/证据（diff 全文逐 `-` 行核过，除下列 4 处外全部是纯插入）：
  1. `MIR_STREAM_BUF` 行被**就地改格式**：尾部追加 `huge=%d`（现 :2141-2142；旧件 `git show 447f76f` 该行无 `huge=`）⇒ 旧版输出 `…aligned=4096`，新版 `…aligned=4096 huge=0`。
  2. 每窗新增 2 条行：`MIR_STREAM_CFG2`（:2151-2152）、`READLOG_OFF`（:2259，**无 --readlog 也打**）。二者不在 REPORT:3 列举的新行清单（`READLOG/READLOG_SUM/MIR_STREAM_CFG2/AIO_*/DUAL_SUM`）字面内（READLOG_OFF 属于「等」的合理解读，但清单本身没列）。
  3. `--seconds` 看门狗语义被改：`alarm()` 单次 ⇒ `setitimer` 250 ms 周期（:2161-2168；D1M 实测坑的修复，方向正确、代码注释有说明，但 REPORT 变更清单未列）。**注意它改的是既有 --seconds 特性，不是新选项**。
  4. （卫生）缓冲释放 `free(buf)` ⇒ 条件释放（:2300）——行为等价。
- 影响：拿旧版输出做基线 diff 的下游解析器（如对 `MIR_STREAM_BUF` 行尾锚定的正则）会被 `huge=0` 磕到；把「逐位不变」当字面承诺复算 5ea97067↔7cebded7 输出会得出「不符」结论。
- 建议：把 REPORT:3 与 §0 边界句就地改成订正块口径（「**既有输出行字段名与相对顺序**一字未动；新增行清单补 READLOG_OFF/DUAL_SUM」），删「逐位」字样；--seconds 语义变更进变更清单。

**P2-4｜AIO「零在飞」保护只罩看门狗路径；外部终止信号（timeout 的 SIGTERM、Ctrl-C、SIGKILL）与 AIO_STUCK 的「无界等外部灌流」不在罩内 —— 正是 §0.1 实测钉死的 D 态挂死面。未登记。**
- 位置：`_proj_pcie/p7b_biz/p7b_mir_dump.cpp:960-977`（STUCK 无界等）、:2168（周期 SIGALRM 只处理 wd）；窗协议 `_tools/run_win_hw.sh` 用 `timeout` 包工具。
- 证据：EINTR+wd_fired 分支（:898-905）保证「看门狗响 ⇒ 收到零在飞才退」；但外部 SIGTERM/SIGINT 进不来这个分支（无 handler，默认动作直接死），`exit_aio` 遇在飞 iocb ⇒ 探针实测的 D 态（kill -9 无效）。STUCK 形态还要求**人工 flush 窗**才能收场——若操作者直接杀进程清场，同样落进 D 态。
- 影响：工具内部协议自洽（注释明写「需外部灌流」），但「杀 AIO 进程会 D 态挂死」这条操作纪律没写进 REPORT 的登记/未竟项；下轮有人 `pkill` 清残留就可能挂一个 D 态进程占着设备。
- 建议：登记（REPORT §5 或 run_win_hw.sh 头注）：「--aio 窗收尾期 ⛔ 不可杀进程；唯一安全收尾 = 喂满在飞 chunk；`timeout` 的 SIGTERM 同样不安全」。代码侧可在 AIO 档为 SIGTERM/SIGINT 装「转 wd_fired 同等处理」的 handler（把外部终止也收敛到零在飞路径）。

**P2-5｜dual 的中部短读（got<n、无错误）不停车：两线程继续读后续块 ⇒ 缓冲内容与流序错位，且把「块交换仅 verify 可抓」的窗口从"提交序颠倒"放大到"短读点之后的全部续流"。未登记。**
- 位置：`_proj_pcie/p7b_biz/p7b_mir_dump.cpp:1186-1194`（got<0/got==0 才 break；短正读落进记账后**继续循环**）；合并 :1265-1274。
- 证据（构造推演 V1-d）：chunk4 半块后，chunk5/6/7 缓冲装的是短读点之后的续流，`pc`（前缀和）仍 = 各块 got 之和 = 4.5 块（**计数正确**，V1 全场景 True）——但 buf[pc..] 内容相对流序错位且 verify 不查；若 chunk5/6 的提交序再颠倒，**[0,pc) 内部交换**，字节账依旧全绿，仅 verify 可抓。触发条件 = 驱动在 dual 中途返回短正读（C2H 流式 EOP/截短形态，本轮 20 窗未观测到 partial>0 的 dual 窗，属理论路径）。
- 建议：登记为 H-8 残余的放大形态；可选一行收紧：dual 下 `got < n` 时置 stop（与 got≤0 同处置），把语义钉成「dual 只接受满块」。

### P3

**P3-1｜READLOG_SUM 的中位数 = 上中位（`v[n/2]`），与交付分析器 `statistics.median`（两中位均值）不可互推；低-2 的 0.8 µs 缝同族。**
- 位置：`_proj_pcie/p7b_biz/p7b_mir_dump.cpp:1391-1395`（`med` lambda）；分析器 `_tools/analyze_readlog.py:69`。
- 证据（V3，真实窗 LAD_1048576，n=990）：工具打印 `read_us med=2856.9` = 上中位；`statistics.median=2858.8`；下中位 2857.7。非并列数据下该缝可任意大；READLOG_SUM 与 analyze_readlog.py 的各 med 列**没有互推关系**。
- 建议：README/报告层钉一句「READLOG_SUM 的 med = 上中位口径」；或工具改 `v.size()%2 ? v[n/2] : (v[n/2-1]+v[n/2])/2` 与分析器对齐。

**P3-2｜AIO 主循环里 `if (wd_fired() && inflight == 0)` 是死分支**（inflight==0 在循环顶部 :893 已 break，:getevents 之前 inflight 恒 >0）。位置 :899。卫生项，删除或改注释。

**P3-3｜AIO 越序完成时 `r.bytes` 按完成序累计：`pc` 的「流序前缀」语义在真 OOO 下不成立（仅打印 `MIR_STREAM_AIO_OOO` 登记）。** 位置 :929-938。单串行 C2H 引擎下结构性不可达（同 REVIEW 对 OOO 的定性），属潜在一致性问题；建议注释里补一句「OOO 时 pc 非流序前缀，仅计数有效」。

**P3-4｜selftest 的新恒等式（T15/T15b）只覆盖同步路径的 readlog；dual 的拼接语义、AIO 的 gap=0/生命期语义均无 mock 检验。** 位置 :1898-1950。T15/T15b 本身设计正确（含 readlog=0 ⇒ 零记录的负对照，正面确认），但 dual/aio 的仪器口径没有任何板外闸——本轮 dual 窗 READLOG 分析（含 P1-1 的竞态）在真实数据上裸跑。

---

## 2. 本捆**未发现**下列问题（各附覆盖面）

- **未发现「双缓冲环溢出」的真实通路**（覆盖面 = `runs/driver_libxdma.c` :3464-3690 全函数 + :2964-3024 transfer_init + `grep desc_lock` 全 10 处 + 工具侧 `dual_reader_body`/`run_stream_dual` 全分支）：desc_lock 跨等待持有、单笔双向钳制、错误分支（:3562/:3586/:3676）均释放锁——订正块 H-8 的「不设几何门 = 正确行为」**在驱动副本面上成立**。残余：该论证建立在 `runs/driver_*` 副本上，**对端现役驱动树与副本的一致性未核**（REVIEW §10-5 已登记，本审查同样够不到）；且 desc_lock 论证只管描述符环，user-buffer 侧（两线程写不重叠奇偶区间）无共享态——本审查已核 `dst + idx*chunk` 落址无重叠、无指针/角色交换。
- **未发现「半交换状态」**：实现为固定偏移奇偶分块，根本不存在缓冲指针交换；错误路径（ended=1/2/3，:1186-1190）`got_of` 留 0、`dual_wake_peer` 一次性停对端（`__atomic_exchange_n` 防双杀，:1148-1151）、`pthread_join` 收尸、锁全部释放（:1301-1303 后 :1309 destroy）。看门狗截断/读失败/读 0 三形态的退出态均已核。
- **未发现「字节重复计入/漏计」的代码路径**：dual 每块恰读一次、无重读分支（got<0/got==0 均 break 且不再读本块）；AIO 每 chunk 一次 io_submit、失败不补提（而是走 STUCK 收尸）；合并循环按块号前缀截断（V1 场景 a/b/c/d 全 True）。`taken`/`pc`/`ΔW70` 的记账点（dual_sample 锁内采样 vs 合并后 r.bytes）在交换/截断前后一致。
- **未发现默认路径被「借重构之名」改读循环**：`run_stream` 主循环的全部插入都在 `if (o.readlog > 0)` 门内或纯初始化（:682-705 逐行核）；now_s() 在 readlog=0 时不被调用（t_pre/t_post 置 0.0，无计时开销）；样本/静默窗/式A/式B 打印逐字未动。差异全在 §P2-3 列的 4 处。
- **未观测**（声明，不是否定）：真机 dual 窗 READLOG 行是否实际出现过 P1-1 的回绕行（概率极低、需板级复跑）；短正读（P2-5）在 dual 下的真实触发率；中间两代二进制（`441796f6`/`6d8345da`）的源码 diff（H-5 已登记未核）。

## 3. 负对照与构造性验证（脚本 `xreview_b_verify.py`，输出留档 `xreview_b_verify.out`）

**V1 — dual 合并状态机复算**（逐字复刻 :1266-1274）：
```
(a) 全满块 8/8:            pc=33554432 == 33554432 ? True
(b) wd 截断 (3 满, 后未尝试): pc=12582912 == 12582912 ? True
(c) OOO 完成 (记账序不变):  pc=33554432 == 33554432 ? True
(d) chunk4 半块 (无错继续): pc=18874368 == 18874368 ? True
```
⇒ **计数记账对完成次序/截断/短读全部不变**（「完全不可见」论证的构造性支持）；但 (d) 同时演示了 P2-5 的内容错位形态——**计数对、内容错**，verify 只查 [0,pc) 时的覆盖边界被钉了出来。

**V2 — dual READLOG dw70 竞态构造**：
```
确定性交错: A snap(1000) → B snap(1500) → B commit(dw70=500) → A commit
⇒ A 行 dw70 = 4294966796 = 0xFFFFFE0C (真区间增量应为 0)
随机调度 2000 次: 回绕 dw70 行数合计 = 186170
```
⇒ P1-1 不是理论洁癖：代码**允许**该交错存在（无任何原子性/序保护），Σdw70 在 dual 下因此不保证 == drop。

**V3 — READLOG_SUM 中位数口径实测**（真实窗 `runs/LAD_1048576.txt`，n=990）：
```
read_us  工具(上中位)=2856.9  statistics.median=2858.8  lower=2857.7
件内 READLOG_SUM 行打印 med=2856.9 (= 工具上中位口径 ✓ 自洽)
```
⇒ 仪器自洽但**与交付分析器不同口径**；「READLOG 无外部 oracle」的自证力在此打折扣（任务书 Q4 的 off-by-one 面：不是 ±1 行的错，是**中位数定义本身**的缝）。

## 4. 覆盖面声明

**看了**：diff 447f76f..7a22d97 全文（1062 行，逐 hunk）；现读 `p7b_mir_dump.cpp` 的 run_stream（646-780）、run_stream_aio（791-1055）、dual 全家（1069-1317）、print_readlog（1375-1411）、参数门（1523-1587）、selftest T15/T13b/T14 新增（1898-2047）、main stream 段（2121-2302）；驱动副本 `driver_libxdma.c`（:2964-3024、:3464-3690、:3810-3850、desc_lock 全 10 处 grep）与 `driver_cdev_sgdma.c`（:40-50、:405-425）；交付分析器 `analyze_readlog.py`；真实窗 `runs/LAD_1048576.txt` 的 READLOG/READLOG_SUM。

**没看/没跑**：xsim、任何板级测量窗（派单禁 + 本审查为只读）；对端现役驱动树与 `runs/driver_*` 的一致性；中间两代工具源码（`441796f6`/`6d8345da`）；`_tools/run_win_hw.sh` 本轮 md5（`7b40bcbb…`）的逐行 diff（只读引用其 `timeout` 包装事实）；`--buf-huge` 只在代码面审（MAP_HUGETLB 语义未跑）；Windows 构建分支只核了 `#ifndef _WIN32` 的完备性（aio/dual 在 Windows 下 FATAL exit 2，留档）。

---

*本件 = 跨组对抗审查（Kimi 组）。不下 PASS/FAIL 裁定；发现 P0=0 / P1=1 / P2=5 / P3=4；负对照构造验证 3 组全部留档（`xreview_b_verify.py` / `xreview_b_verify.out`）。*
