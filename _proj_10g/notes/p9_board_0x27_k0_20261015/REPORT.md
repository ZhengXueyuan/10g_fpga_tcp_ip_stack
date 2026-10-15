# 板级轮 B1：板态全恢复 + `0x27` 上板 + 身份门 + 换流门 K0 判据（含负对照）

> **agent 原件由平台拒写 .md ⇒ 全文回传、TL 代落盘**（本件正文 = agent 原文；文末「TL 附加」= TL 独立抽核记录）。
> - 日期：**2026-10-15**（11:0x–12:3x）· 仓库 `D:\repo\XCKU5PMini\udp_hls_10g` · 轮目录 `_proj_10g/notes/p9_board_0x27_k0_20261015/`
> - 依据（一手，按序读过）：① `P7B_LONGSEND_HANDOFF.md` §2–§4 · ② `P7B_LOOP_HANDOFF.md` §6（恢复清单）· ③ 台账 §10-64（板态订正+恢复五件）/§10-69/§10-70 · ④ **`p9_fix_upok_design_20261014/DESIGN_v2.md` §5.2（K0 判据原文；v2r2/v2r3/v2r4 链逐字沿袭未改 §5）+ §5.3（工具修正规格）** · ⑤ `p9_impl_upok_20261015/fix_r5/REPORT_FIX_R5.md`
> - ⛔ **本报告不给 PASS/FAIL 裁定**（裁定权在用户/判据所有者）；只给读数与形态。
> - ⛔ **硬约束遵守**：只走 JTAG 易失烧录（**QSPI 零写**）· **未跑任何 Vivado 构建**（只用烧录 tcl）· 未碰 `D:\repo\perfv` · `PEER_PW` 只作前缀、**未落盘**（轮目录 grep=0）· 对端操作全走 `tools/peer_ssh.py` · **未提交 git** · `MSYS_NO_PATHCONV=1` 与 `cmd //c` 未并用（烧录 = `cmd /c` + 该 env，先例 burn_0x24.sh）。

## §0 一句话状态
**板态全恢复 ⇒ `0x27` 上板（身份门逐条全中）；K0 正臂 7/7 `K0=0`/0 断点/全流逐字节验完/sink `mism_bytes=0`；负对照臂 0/25（本会话无判别力，按设计件 §5.2 条款登记）；板子现役 = `0x27` + `0x08=0`（未受控停流）+ `carrier=1`。**

## §1 工具修复（K0 前置件）：`align_check2.py` 绝对相位口径

### 1.1 选哪份 / 怎么修（依据 = 设计件 §5.3-② 逐字）
- **两处现读副本 sha256 完全相同**（`6e04d6b1…e94b6d`，4372 B）⇒ "选哪份"为伪问题；以它为基（存 `_tools/align_check2_orig.py`，sha 逐字相同），**未改动那两份历史副本**。
- 设计件修法原文（§5.3-②，M-6 采信版）："真缺口 = 断点后的重对齐（`:119-127`：`c = K0 + j ± d, d ∈ [0, 65536]`，且只在 `bp..bp+257` 窗口内找）⇒ 结构性到不了'绝对相位 0'（S0A 的 `UNALIGNED_REST` 即此）⇒ **修法 = 重对齐改绝对锚（或 `d` 扩到含 `−(K0+j)` 的绝对扫描）+ 把搜索窗口从 257 B 放宽**"。
- **实现**（`_tools/patch_align_check2.py`，5 锚点、每处恰命中 1 次否则响亮失败）⇒ `_tools/align_check2_fixed.py`（sha256 `db77dd3c…3ec38e` / md5 `f14680ad…e49d7`）：
  1. **改动 1 = 绝对锚分支**：断点后对窗口内每个 `j` 先在**图案绝对偏移 [0, 2^22]** 内直扫 32 字节窗（与首扫 `head=gen_pattern(0,1<<22)` 同界 = v1 §5.3 的"绝对偏移 0..2^22 扫描"）；扫不到才走原相对候选（原样保留为兜底）。
  2. **改动 2 = 重对齐窗口 257 → 65536**（设计件未给数值；取值 = 与 `d` 同量级；**登记为轮内选择**）。
  3. **改动 3 = 基址更新 `K0 = newK` → `K0 = newK − j2`**（⚠️ 设计件未写，本件实测发现，见 §1.3-a）。
  4. **改动 4 = 图案生成长度 `K0+n` → `ABS_HEAD + n + 2*REALIGN_WIN + 32`**（⚠️ 设计件未写，本件实测发现，见 §1.3-b）。
  - 首扫（本来就是绝对的）与"头上限 4 MB"（§5.3-③ 登记项）**未动**；输出仅 newK 行追加 `how=abs/rel` 诊断字段，**既有字段一字未改**。

### 1.2 自检门（合成件；替代"旧 pcap 复算 S0C"）
- **偏差登记**：设计件 §5.3 末条要求"改完先在旧 pcap 上复算 S-0 的 S0C（应重现 `K0=37960`）"。⛔ **旧 S0C 全帧 pcap 不在仓内**（当时只在对端 `/tmp/p7b_ghost/`，对端 10-14 22:10 重启被清）⇒ **该条无法执行**。
- **替代（更强）**：`_tools/selftest_align_fixed.py` 造 5 个合成 pcap（`synth_pcap/` 存档），orig/fixed 并跑、硬断言 9 条（原件 = `_tools/selftest_align_out.txt`，sha256 `bd4588e0…`）：
  | case | 内容 | orig | fixed |
  |---|---|---|---|
  | A | 干净流 @phase 37960（= S0C 读数形态） | `K0=37960/breaks=0/全流验完` | **同**（等价复算 + 不回归） |
  | B | 残差前缀 r=1440（旧相位 2,000,000）+ pattern[0..] | 寻不到（newK=None） | `newK=0 (abs)/breaks=1/全流验完` |
  | C | 残差前缀 + pattern[1000000..] | 寻不到 | `newK=1000000 (abs)/全流验完` |
  | D | 随机流（负对照） | `K0=-1` | `K0=-1` |
  | E | 相位变更 +10000 @1440（orig 候选**可达**） | **候选找到但验证停摆**（`verified_prefix=1440/breaks=3`，同一 newK 连打三次） | `breaks=1/全流验完` |
  ⇒ **`SELFTEST_ALIGN_FAILS=0 / PASS`**（RC=0）。⚠️ case A 是"等价件非原件"（旧件灭失，如实登记）。

### 1.3 ⭐ 两个"设计件未写、本件实测发现"的工具缺陷
- **(a) 重对齐基址更新在 `j2>0` 时结构性停摆**：`align_ok(i,·,K)` 口径 = "K 是流位置 0 处的相位"（首扫即此义），原版命中 `(j2, c)` 后置 `K0=c` ⇒ 下一轮比较必失配 ⇒ 同拍再断、三连后停（case E 实测：orig 与"只加绝对锚的中间版"都停在 `verified_prefix=1440/breaks=3`）⇒ 即便绝对锚"找到" c=0 也拿不到"断点后全流验完"。修 = `K0 = c − j2`（一行算术）。
- **(b) 图案覆盖不足 ⇒ 尾部假断点**：原版按初相位生成 PAT ⇒ 当 `c − j2 > K0初`（前向相位跳变/绝对锚落点）时流尾撞越界 ⇒ 假断点（case E：`BREAK @92873` = PAT 耗尽点、newK=None）。
- **口径**：两条都是"让 spec 指定机制**可观测地成立**"所必需的算术，不是新机制；若只认字面 spec ⇒ 行为差异 = 断点后的**继续验证**能力（起点 K0/断点位置/新相位三条读数两版相同）。**裁定权在用户**。

## §2 环境恢复（对端 `192.168.0.38`，从零）

### 2.1 部署件（配方 = `p7b_affinity/BUILD.md` §1–§3/§6；`g++ -O3 -pthread`）
- 上传 22 件 + 编译 9 产物（`COMPILE_DONE_RC=0`，g++ 13.3.0）+ 5 项板外自检。全量日志 = `env/DEPLOY_PEER_20261015_1107*.log`；md5 对端现读与仓内逐件相同。

| 产物 | md5（对端现读=仓内重编值） | vs BUILD.md §3 表 |
|---|---|---|
| `p7b_tcp_sink` | `6d9b14f24725fa326ffe5b169f77e30f` | ✅ |
| `p7b_tcp_src` | `79be2a09024206b7c678dc13a3b9051d` | ⚠️ 表值 `48d066a0…`（查因见下） |
| `p7b_udp_src` | `e0d4da5834cb95d67afb0cc523d1f92f` | ⚠️ 表值 `a3faafd3…`（查因见下） |
| `p7b_tcp_src_fix` | `d1ca0c288efe6723488e4c1a6960d1b5` | ✅ |
| `p7b_tcp_sink_rate` | `ca6900fd54036be7fe1d337ca9ef83b8` | ✅ |
| `p7b_tcp_src_rate` | `a76b2b4b1e44d6c9edcaa301d90aabcb` | ✅ |
| `p7b_tcp_src_diag` | `430ed36ade4ec64ba6f5cb52e5f4f335` | ✅ |
| `p7b_rate2_bench` | `1e956072f30a25f3e547e8c42107afb3` | ✅ |
| `p7b_mir_dump`（仪器） | `48dcbcb26a4db45f576fc9664638a089` | §3 表不含；与 10-13 记录不同（查因见下） |

- **两条不符的查因**：`p7b_tcp_src.cpp`（`7a6191fc…`）/`p7b_udp_src.cpp`（`f5ff3172…`）在 **`fb23ad4`（P8 板级轮，10-11）** 改过（`--bytes K` 续发语义 + TIOCOUTQ 排空；`git status` 干净）⇒ **§3 表过时**，以现读值为新指纹。**`p7b_mir_dump`**：现源 `464006d9…` ≠ 宿主读轮 `b4833c55…` = 后续 `d58c654`（修复轮）又改过（该轮明示不覆盖现役）⇒ 二进制 `48dcbcb2…` ≠ `7cebded7…`（预期；B1 不用它）。
- **输入 12 件**（全部与表逐字一致）：`p7b_affinity.h` `b0322279…` · `p7b_io.h` `62b1257d…` · `p7b_spsc.h` `3132db49…` · `p7b_pattern.h` `b2f2e962…` · `p7b_tcp_sink.cpp` `8d02ef64…` · `p7b_tcp_src_fix.cpp` `21ca7fa9…` · `p7b_tcp_src_diag.cpp` `217a0e48…` · `p7b_tcp_src_rate.cpp` `c3b9b01c…` · `p7b_tcp_sink_rate.cpp` `92ef5b45…` · `p7b_rate2_bench.cpp` `b9c18a76…` · `p7b_fake_board.py` `4154925a…` · `p7baff_faultinject.cpp` `23a01d88…`。
- **台架/门脚本（现树值）**：`p7b_snap.sh` `32b97715…`（已同步 0x27；默认 `NW=71/EXPECT_BID=0x00000027` 现读正确）· `stc_dl.sh` `a9b4a0c2…` · `j6_stagec.sh` `3b248ece…` · `tcpreg_j6.sh` `209e0d59…` · `pcap_off_dryrun.sh` `3be0e9d7…` · 5 个自检脚本 md5 见表（全绿）。
- **本轮新件**：`align_check2_fixed.py` md5 `f14680ad…` · `split_conn_pcap.py` md5 `fa4456d6…` · `k0_arm.sh` md5 `00653037…` · `k0_analyze.sh` md5 `1aea5b05…`（对端/仓内逐字相同）。

### 2.2 板外自检 5 项
| 门 | 读数 |
|---|---|
| `p7b_selftest.sh` | **PASS=30 / FAIL=0 / SELFTEST_OK** |
| `p7b_dualthread_selftest.sh` | **PASS=48 / FAIL=0** |
| `p7b_lane8_selftest.sh` | **PASS=42 / FAIL=0 / SKIP=0**（部署 faultinject 后 L15/L16 不再 SKIP） |
| `aff_selftest.sh`（不带 SKIP_NET） | 全过；含 **CASE Q `PIN_FAIL END_MISMATCH`+`_exit(2)` 硬门** |
| `pcap_off_dryrun.sh` | **PASS=20 / FAIL=7 / BAD** ⚠️ 7 条全在 `tcpreg_j6.sh` 臂 = **年代差**（dryrun 传 `EXPECT_BID=0x00000009` 而现役脚本默认 `NW=71` ⇒ 档表不认 ⇒ **`J6_GEOM_FAIL` 响亮 exit 3**）；stc_dl/j6_stagec 两臂全 PASS。⚠️ 同批登记 `tcpreg_j6.sh:77`（0x27 档描述）**含反引号 ⇒ 命令替换噪声**（功能/匹配不受影响）—— 均登记不修 |

- ⚠️ 首轮自检失败（已闭环）：缺 `p7b_fake_board.py`/`stc_dl.sh`/`j6_stagec.sh` ⇒ 三门假红 ⇒ 补齐后全绿（处置=补齐清单，非工具缺陷）。

### 2.3 NIC / 网络前置（现读；供 B2/B3 照抄）
```bash
ip link set enp1s0f1np1 up
ip addr add 192.168.100.100/32 dev enp1s0f1np1
ip route add 192.168.100.2/32 dev enp1s0f1np1
nmcli device set enp1s0f1np1 managed no            # 现读 = unmanaged
ethtool -C enp1s0f1np1 adaptive-rx off rx-usecs 0  # 本轮全程 off
```
现读：`ip route get` ⇒ dev enp1s0f1np1（非 WiFi）· `CARRIER=1` · 10Gb/s link yes · `/32` 在位 · `irqbalance=inactive` · `Adaptive RX: off / rx-usecs: 0`。⚠️ 中断合并留 off（测量最优）；复原 = `ethtool -C enp1s0f1np1 adaptive-rx on rx-usecs 60`。

## §3 烧录 + 身份门（两臂 + 收尾，全 JTAG 易失）
### 3.1 正臂 `0x27`（含从"厂商设计态"恢复）
- sha256 双核：归档件 == `impl_1` 原件 == **`5c17b14f0656cf6680b7d16f7f1659faa4ca9225cf0cb0461765be7a91943385`**（`.bit` 头 `SW_CRC=20c4e8b8`）✓
- 烧录五判据：路径匹配 + EXISTS + mtime 新鲜(age=134s) + **`End of startup status: HIGH`** + `TCPREG_PROG_DONE` + 无 ABORT ✓
- **场景 C**：根端口级 remove+rescan ⇒ 桥窗 **1M→2M** · 双 Region · dmesg `identify_bars: 2 BARs: config 1, user 0` · `/dev/xdma0_{user,control,c2h_0,h2c_0}` 全现 · LnkSta x4 ✓
- **身份门**：MAGIC `0x50360001` ✓ · **BID `0x27`** ✓ · MARKER `0xdeadbeef` ✓ · **`0x14C=0xffffffff`** ✓ · `0x08=0` ✓ · `p7b_snap id`=ID_OK ✓ · **71 字扫描 NFF=0** ✓
### 3.2 负对照臂 `0x24`
- sha256 双核：归档件 == `p9_board_0x24_20261013/burn/wrapper_p4_0x24.bit`（10-13 实烧件）== **`e3b07957…f1db`** ✓（⚠️ 首次尝试用 `impl_1` 当第二锚被脚本**拒绝**——它已被 0x27 覆盖；改用实烧副本，如实留档）
- 烧录五判据 ✓；PCIe **设备级**一次成功；身份门 BID `0x24`/其余逐条 ✓
### 3.3 收尾重烧 `0x27`
五判据 + 身份门全中（BID `0x27`，NFF=0，`0x08=0`）✓；FINAL_STATE 见 §7。

## §4 ⭐ K0 判据读数（判据式 = 设计件 §5.2-S2/S3/S4）
### 4.1 执行构型（每臂同参同顺序；`k0_arm.sh` + `k0_analyze.sh`）
| 段 | 参数（逐字） |
|---|---|
| **S2** | `--rcvbuf 2920 --conns 6 --seconds 300 --maxbytes 200000000 --check lane8`（**before_connect 默认语义**） |
| **S3** | `--rcvbuf 49152 --conns 1 --seconds 120 --maxbytes 400000000 --check lane8` |
| **S2B** | S2 同参 + **`--rcvbuf-after-connect`**（**S-0 当年台架语义**逐字复现；`RCVBUF_ORDER=after_connect_LEGACY`） |
| **S2C** | S2B 同参 + **`--conns 12`**（设计件"加连接数"条款） |
| 抓包 | 环形全帧 `-B 262144 -C 300 -W 8`（板→对端）+ FIN/RST 普查 + 0.15 s 快照环 |
| 分析 | `split_conn_pcap.py`（按 dport 拆，**plumbing**）+ `align_check2_fixed.py`（**每连接** K0/breaks/verified，测量逻辑 100% 在此） |

- ⚠️ **两条抓包硬门**（K0 可用的前提）：① **arming 门** = 等 `listening on`（首跑未等 ⇒ 丢头 4 段 ⇒ **K0 假 5840**，而 sink 自报 `-1` ⇒ **= S-0 M-1 伪影同族**，已修）；② **优雅停** = `kill -INT` 等退出（首跑 kill 错 PID ⇒ 尾部 ~130 包滞留）。③ 口径差异（vs S-0 run_s0.sh）：去 `-U`、`-B 65536→262144 KiB`。

### 4.2 逐跑读数表（原件 = `runs/`；全表 = `runs/SUMMARY_TABLE.txt`）
| 跑 | 臂 | BID | 构型 | conns | sink bytes | `mism_bytes` | agg | **每连接 K0** | breaks | 抓包 captured/received/dropped |
|---|---|---|---|---|---|---|---|---|---|---|
| `K0P_S2` | **正** | 0x27 | 2920 before | 6 | 1,200,006,120 | **0** | 854.3 Mbps | **0×6** | 0×6 | 821,794/821,945/**0** |
| `K0P_S3` | **正** | 0x27 | 49152 before | 1 | 400,000,435 | **0** | 5,632.3 Mbps | **0×1** | 0 | 274,168/274,210/**0** |
| `K0N_S2` | 负 | 0x24 | 2920 before | 6 | 1,200,006,120 | **0** | 862.1 Mbps | **0×6** | 0×6 | 821,839/821,945/**0** |
| `K0N_S3` | 负 | 0x24 | 49152 before | 1 | 400,007,735 | **0** | 4,439.8 Mbps | **0×1** | 0 | 274,343/274,343/**0** |
| `K0N_S2B` | 负 | 0x24 | 2920 **after** | 6 | 1,200,006,120 | **0** | 730.6 Mbps | **0×6** | 0×6 | 823,140/823,254/**0** |
| `K0N_S2C` | 负 | 0x24 | 2920 after **conns=12** | 12 | 2,400,012,240 | **0** | 755.8 Mbps | **0×12** | 0×12 | 1,646,473/1,646,604/**0** |

**三条独立口径互证（每跑都在）**：① sink（每连接 `first_mismatch=-1 / mism_bytes=0` = 从字节 0 起逐字节等于 `pattern[0..]`）；② pcap 相位校正（`K0=0` + `breaks=0` + `verified_prefix==n`）；③ 板侧快照（正臂 S2：`ΔW51=1,200,014,880` vs sink `1,200,006,120`，差 8,760 B = 收尾在飞；`ΔW20=821,945` = tcpdump `received by filter` **逐位相等**）。**控制帧普查**：**板侧 FIN/RST=0**（两臂同）；只见对端 RST（S2=5、S2C=12，= sink abortive close）。`nstat`：`TcpRetransSegs`/`TCPOFOQueue` 两臂两跑内**零增量**。

### 4.3 对照结论（读数层，不含裁定）
- **正臂（0x27）**：**7/7 连接满足合格形态 `K0==0`** ∧ 0 断点 ∧ 全流验完 ∧ sink `mism_bytes=0`。
- **负对照臂（0x24）**：**4 跑 25 连接，`K0≠0`=0 条**——缺陷本会话未现形（连 S-0 语义臂与 conns=12 都没现形）。
- ⇒ 按设计件 §5.2 判别力条款逐字：**"负对照臂若 0 条 ⇒ 该轮判'无判别力'（登记，不许判 PASS/FAIL），加跑一轮或加连接数"** ⇒ 本轮回登记 = **"负对照 0/25 ⇒ 本会话无判别力"**（≠"修复无关"，≠"缺陷不存在"）。
- ⚠️ **与 S-0 反差登记**：S-0（**build F/0x1A**，10-11）同类构型 = **S0A 3/6 + S0C 1/1**；本轮（0x24）0/25。**三候选差异（未分离）**：① 构建代差（0x1A→0x24 之间 app_pattern 历经 A3 重连修复 / A7 R-1 T+2 重定时等 ⇒ ev_up→装载拍时序关系可能已变）；② 速率量级（S-0 ≈181 Mbps vs 本轮 730–950 Mbps/连接，且本轮**全程零 stall**，S-0 有微窗 stall 家族）；③ 台架语义（已用 `--rcvbuf-after-connect` 复现、**不解释**）。建议 next：把"触发条件本身（raw ev_up 何时命中装载拍）"立项（设计件 E12 四计数器正是为此，**本轮未构建**）。
- ⚠️ 不许读过头：① `mism_bytes` 相位正确时有判别力、相位错时无（设计件 §5.1）；② 负臂 0 条**不能**写"0x24 相位缺陷不存在"；③ 正臂全绿**也**不能单独归因给换流门修复（**两臂同绿** ⇒ 本会话该判据**没有区分两臂**）。

## §5 异常与偏离（逐条）
1. **"旧 pcap 复算 S0C"无法执行**（旧件不在仓内）⇒ 用 5-case 合成自检替代（等价件非原件）。
2. **工具两处"设计件未写"缺陷** ⇒ 已修+单独登记（§1.3），裁定权在用户。
3. **重对齐窗口 257→65536 = 轮内参数选择**；绝对锚扫描面 [0, 2^22]（= v1 §5.3 提出面 + 与首扫同界）。
4. **首跑三连坑（已闭环、全留档）**：① 非 root ⇒ 读数全空/`Permission denied`（且 `fs.protected_regular` 令后来的 root 也写不进别人拥有的旧 `/tmp` 件）⇒ 加 root 前置硬门+清命名空间；② **自建命名空间把 run log 也删了**（`/tmp/k0_<TAG>_*` 命中 `/tmp/k0_<TAG>_run.log`）⇒ run log 改 `/tmp/k0run_<TAG>.log`（"陈旧/空件被当新读数"家族）；③ **tcpdump 未 armed 就开跑 ⇒ K0 假 5840**（= S-0 M-1 伪影同族）⇒ 加 arming 门。
5. **0x24 烧录第二锚换件**（impl_1 已被 0x27 覆盖 ⇒ 首次被拒）⇒ 改用 0x24 板级轮实烧副本。
6. **BUILD.md §3 表对两件源过时**（查因到 `fb23ad4`）+ `p7b_mir_dump` 与 10-13 记录不同（查因到 `d58c654`）—— 均非本轮引入。
7. **`pcap_off_dryrun.sh` 的 tcpreg 臂 7 条 FAIL = 年代差**（响亮 `J6_GEOM_FAIL` exit 3，非静默）⇒ 登记不修；同批登记 `tcpreg_j6.sh:77` 反引号噪声。
8. **负对照 0/25（最大一条）**：见 §4.3。
9. **进程/磁盘卫生**：全轮零残留进程（收尾核）；对端 `/tmp` 现存本轮 pcaps ~6.5 GB（保留供复算；盘余 1.5 T）。
10. **S2C 速率略降**（755.8 vs 862.1 Mbps）——未归因，只登记。

## §6 未观测 / 未做
- **负对照的缺陷现形 = 未观测到（0/25）**（不写"不存在"）。
- **触发条件（raw ev_up 命中装载拍）无任何直接见证**（E12 四计数器未构建；S6"读四计数器"= 未做，设计件已登记 deferral）。
- **"再加跑"未做**（设计件给了"加跑一轮**或**加连接数"，本轮取后者）。
- `mism_bytes` 的相位错边界**本轮未被有效激励**（无相位错连接）。
- **速率/时延类读数不属本判据**（只作台架健康见证：0.73–5.63 Gbps）。
- **尾部落盘截断**：每跑 42–151 包在停抓瞬间未落盘（dropped=0）；头完整性由 arming 门保证。
- `W51` 冻结形态未单独判（增量对账已给）。

## §7 环境状态交接块（供 B2/B3 直接用）
```
[板]  位流 = 0x27（sha256 5c17b14f…3385；BID 0x27 / 71 字 / 0x14C=SLVERR）
     0x08 = 0（未受控停流）· carrier = 1 · LnkSta x4 · 2 BARs · /dev/xdma0_{user,control,c2h_0,h2c_0} 在位
     烧录入口 = …/p9_board_0x27_k0_20261015/burn/burn_0x27.sh（换位流改 WANT/SRC/BIT_WIN 三处，照 burn_0x24_arm.sh 先例）
[对端 192.168.0.38] /tmp/p7b_biz/ 已按现树重部署 + 编译 9 产物（md5=§2.1）；板外自检 30/48/42 全绿
     NIC: enp1s0f1np1 up · 192.168.100.100/32 · nmcli=unmanaged · Adaptive RX off/rx-usecs 0 · irqbalance inactive · carrier=1
     网络前置 = §2.3 四行（每次重启重做；每次测量前现取 ip route get）
     残留（可复用/可删）: /tmp/k0_*（pcaps+日志）· /tmp/k0an_* · /tmp/k0run_* · /tmp/k0_split_*；盘余 1.5 T
[B2] 0x25 = faefa444…（p9_build_0x25/）· 0x26 = 34e553ee…（p9_build_0x26/）均在盘
[B3] hw_server(3121) active；烧录/reg_rw 路径 = /home/a/xdma_test/dma_ip_drivers-patched/...（重启不清）
[纪律] 绝不写 QSPI；构建走 board/run_build_p7b_ku5p.bat；cmd /c 需配 MSYS_NO_PATHCONV=1（勿与 cmd //c 并用）
```

## §8 文件清单（轮目录 `_proj_10g/notes/p9_board_0x27_k0_20261015/`）
| 路径 | 内容 |
|---|---|
| `k0_arm.sh` / `k0_analyze.sh` | K0 执行件/分析件（对端与仓内同 md5） |
| `burn/` | `burn_0x27.sh` · `burn_0x24_arm.sh` · `BURN_0x27_*.txt`（首烧+收尾重烧）· `BURN_0x24_*.txt`（含被拒的首跑）· `BURN_stdout_copy_*` · 两臂 `.bit` 副本 |
| `env/` | `DEPLOY_PEER_*.log`（含首轮失败留档）· 5 项自检日志 · `nic_setup.txt` · `FINAL_STATE_20261015_1233.txt` · `deploy_peer.sh` / `read_final_state.sh` / `fetch_readings.sh` |
| `_tools/` | `align_check2_orig.py`（`6e04d6b1…`）· `align_check2_fixed.py`（`db77dd3c…`）· `patch_align_check2.py` · `selftest_align_fixed.py` · `selftest_align_out.txt` · `synth_pcap/` · `split_conn_pcap.py` · `splitter_selftest.txt` |
| `runs/` | 6 跑原始件（`run_*`/`sink_*`/`snap_*`/`ctl_*`/`nstat_*`/`an_*`）+ `SUMMARY_TABLE.txt` + `CTL_CENSUS.txt` + 冒烟轮留档（含 K0 假 5840 的伪影 pcap） |
| `SHA256SUMS` | 84 件（本件已生成；`.bit`/pcaps 按仓规留盘） |

*本件 = 读数与形态；**判据层 PASS/FAIL 裁定权在用户/判据所有者**。*

----------------------------------------------------------------

## TL 附加（2026-10-15 13:0x；独立抽核 + 裁定）

- **现场核**：`git status` = 轮目录（85 件 / 35 MB）+ `_proj_10g/notes/p7b_biz_tcpreg/tcpreg_program_stdout.txt`（烧录 stdout，预期产物）；对端 `/tmp/p7b_biz/` = 37 件在位 ✓；`resource0` 只读核（`-rw------- root`）——**看门狗探针属 root**，非异常。
- **裁定与口径**：① **K0 正臂 7/7 合格形态 = 读数层收口**；② ⛔ **负对照 0/25 ⇒ 按设计件 §5.2 判别力条款 = "本会话无判别力"（登记，不判 PASS/FAIL）** —— TL 确认该处置**正确**（不许写"修复无关/缺陷不存在/正臂可归因换流门"任何一条）；③ 工具两处"设计件未写"缺陷（基址更新 `K0=c−j2`、图案覆盖）—— **采纳**（属"让 spec 机制可观测成立"的必需算术；设计件在 fold-4 轮出 v2r4，此两处应作为 **errata E-upok-5/6** 登记，本轮先记台账）；④ 旧 pcap 复算不可执行 ⇒ 合成 5-case 替代 — 采纳（旧件灭失为环境事实）。
- **入库面**：轮目录 + 烧录 stdout；ledger §10-71；**下一棒 = B2（RFC 注入 A/B）**（环境交接块 §7 直接用）；B3（mdio）在其后；全部完成后按用户指令关机（先远程、后本机）。
