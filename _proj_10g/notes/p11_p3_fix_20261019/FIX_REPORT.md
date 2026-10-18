# P11 · P3 实施修复轮 — FIX REPORT

- 日期：2026-10-19；仓库根 = `D:\repo\XCKU5PMini\udp_hls_10g`；**派单基线 HEAD = `cdd24667`**。
  ⚠️ 轮内 TL 提交了审查收口 `27513627`（只含 `P11_REVIEW_QUEUE.md` / 台账 / FINDINGS，未碰源码）⇒
  矩阵读数的 `GIT_HEAD = 27513627`，代码基线 = `cdd24667` + 本轮**未提交**工作树改动（**本轮未写 git**，改动由 TL 提交）。
- 依据：`p11_p3_impl_review_20261019/FINDINGS.md`（5 高 / 14 中 / 13 低）+ 设计件 v1.1 §4.3/§4.4/§4.7/§5.2/§9.1/§14
- 纪律：**只改源 + 门**；未跑 Vivado synth/impl/构建、未上板、未碰 QSPI/对端/license/`D:\repo\perfv`；未改 P2/P3 HLS 归档；xsim 门可跑。
- 判据层口径：本件**不下 PASS/FAIL 裁定**；读数与负控如实列出；未做/未测逐条登记。

---

## 0. 一句话

H-1/H-2/H-3/H-4/H-5 与 M-1/M-2/M-3/M-4/M-5/M-6/M-8/M-9/M-10/M-11/M-12/M-13/M-14 **全部有处置**：
H-1/H-2/H-3 的 RTL 修复 + 单元/churn/静态门与变异负控通过；H-4/M-14 的构建变体/配对硬门通过（含 6 条负控）；
H-5 三条 EXT=0 回归重跑并归档；M-1 C4 wrapper 门改用 P3 网表+宏后 arm A/C 成立、Error 硬门就位；
M-2 csim 机器判据（失败集合 == P2 基线）三臂通过。全 41 门矩阵见 §7（结果以该节为准）。

---

## 1. 逐项处置（H 档）

### H-1 跨口同槽 C18 / 迟到 rel —— ✅ 已修
**改动**：`rtl/win_pool_mgr.v`
- 新增 `grant_port[7:0]`（每槽**最近一次授予**的口；`o_grant_port` 输出）。
- C18 的 old 配额从 **`grant_port[slot]`** 的口扣（`sat_sub` 饱和），不再从事件端口扣；
  新增 `stat_c18_cross_port` / `stat_port_win_underflow` / `stat_rel_stale_port`。
- `rel` 只接受**属主口**的释放：`rel_p` 的 `grant_port[slot] != p` ⇒ 忽略 + `stat_rel_stale_port++`
  —— 跨口复用后旧口的迟到 rel **不会吞掉新口刚授出的配额**。
- 同口同拍 `ev_up` + `rel`（不同槽）：旧实装 `else if` 会丢 rel；现两者都处理（同槽由 C18 吸收）。
- **M-3 顺带**：槽号 `slot[3]==1` 时**只计 `stat_slot_oor`，不改任何状态**（旧算术按 `[2:0]` 别名到 0..7）。
- **L-1 顺带**：`stat_grant_zero` 改用本拍实际授予量 `g0_c/g1_c`（不再用事件前 pool 独立重算）。

**门读数**（`gates/sim/`）：
- `WIN_POOL_MGR TB PASS` — 臂 G（跨口复用 + 旧口 rel 延迟）：
  `C18 old 从 port0 扣 / 新配额在 winq[0]=0x3000 / grant_port[0]=1 / stale rel 后 winq 不变 /
  stat_c18_cross_port=1 / stat_rel_stale_port≥1 / underflow=0 / 不变量全成立`；
  另新增臂 H（occ=0x17000 / occ==pool / 两口不同 occ）、臂 I（同拍 ev_up+rel，不同槽与同槽）、
  臂 J（8+0 / 6+2）、臂 F 槽越界前后**逐项状态快照相等**。
- **负控**（`run_negctl_wpm.bat`，5/5 红）：`c18` / `pcap` / `dup` 既有 + **`c18owner`**（C18 old 按事件端口）
  + **`stale`**（接受跨口 rel）⇒ `WPM_NEGCTL_PASS`。
- churn 集成臂 5c（真实 2×app_ctrl + manager）：`P3_CHURN TB PASS`；负控 `run_negctl_p3fix.bat` 中
  `stale`/`m5single` 变异件均被 churn 拒绝。

**方法限制（如实）**：churn 5c 的"旧口迟到 rel"用 `force um.rel0` 注入（真实 app_ctrl 在 DEL 拍就发 rel，
无法自然产生"ev_up1 先于 rel0"的同会话事件）；这是定向激励，不是板级时序复现。

### H-2 retx owner 翻转时机 —— ✅ 已修
**改动**：
- `rtl/retx_pool_shared.v`：owner 输入改名 `slot_port` → **`grant_port`**（来自 `win_pool_mgr.o_grant_port`）；
  属主门控全部改用它；**非属主读的 `r_data` 清零**（读授权在发起拍采样，与 2 拍读延迟同管道）。
- `board/wrapper_p4.v`：`u_win_pool.o_grant_port → wp_grant_port → u_retx_pool.grant_port`；
  `cfg_slot_port` 不再进 retx（只留给 cfg DEL 路由）。

**门读数**：
- `RETX_POOL_SHARED TB PASS`；新增臂 F：旧口在翻转前正常、**翻转后旧口读返回 0**（不给陈旧数据）、
  mismatch 计数、新口接管读写且旧数据完整。
- 静态门 `P11_P3FIX_STATIC PASS`：`retx owner port is grant_port` / `wrapper wires o_grant_port -> grant_port` /
  `retx non-owner read returns 0` 全 OK。
- 负控：`retx_pool_shared_staleowner.v`（去掉写/读属主门）被 TB 拒绝（`RETX_POOL_SHARED TB FAIL`）；
  `m5single`（manager 单读口化）被 churn 拒绝。

### H-3 ACC_MARGIN 分口 —— ✅ 已修
**改动**：`board/wrapper_p4.v`
- 新增 `a2_estab_cnt`（提前声明）+ `acc_margin_n1` + `acc_margin_eff1` 寄存器；
  `u_tcp_rx`（port0）用 `acc_margin_eff`，**`u_tcp_rx2`（port1）用 `acc_margin_eff1`**。
- 重算预算并订正注释：64KB 时代 `N*ACC ≤ 10550`；**C4 128KB echo + 96KB 池**：
  `N*ACC ≤ 131072 − 98304 − 5834 = 26934`；8+0 ⇒ `8×3328 = 26624 ≤ 26934`（余 **310 B**）。
  旧实装（共用 port0 ESTAB=0 ⇒ margin=4096）⇒ `8×4096 = 32768`，物理预算 **136,906 B > 131,072 B（超 5,834 B）**。
- 加仿真期自检：`P11_ACC_MARGIN_SELFCHK`（n=8 必须 3328；只打 `$display`，门要求出现 OK 行）。
- 静态门：`gates/sim/run_accmargin_gate.bat`（7 条规则：两口接法 / 派生源 / 128KB 预算注释 / 自检行）；
  **负控** `run_negctl_accmargin.bat`：port1 改回 `acc_margin_eff` ⇒ 静态门 FAIL（7 条中 1 条红）。
- **行为读数**：C4 wrapper 门日志 `P11_ACC_MARGIN_SELFCHK OK n0=4096 n1=4096 n8=3328`
  （8+0 且 port0 ESTAB=0 时 port1 的 margin = 3328）。

### H-4 HLS 网表与 `P11_HLS_ADV_WND` 配对 —— ✅ 已修
**改动**：
- 新件 `board/p11_build_cfg.tcl`（纯 proc）：`p11_build_cfg_check` / `p11_hls_variant_dir` /
  `p11_default_variant` / `p11_adv_wnd_hits`。
- `board/build_p7b_ku5p.tcl`：构建**开头**选变体（`c1` / `p2_dual_max3` / `p3_dual_max8`，环境变量
  `P11_CFG`/`P11_HLS_VARIANT`，默认 c3→P2 归档）并按变体设 `hls_dir`；**构建前硬判**：
  `P11_DUAL=1 ⇒ 网表有 i_tcp_adv_wnd + 宏 P11_HLS_ADV_WND=1`；否则 `⇒ 无端口 + 无宏`；
  失败打印 `P7B_VERDICT = <原因>` + exit 1（不建工程）。
- C4 elab/wrap 门改用 **P3 归档网表** `_proj_10g/notes/p11_p3_build_20261019/hls_archive_p3_dual_ip_max8`
  + `-d P11_HLS_ADV_WND`（旧版权指向 live `solution1`，会被 HLS 重跑覆盖，且无宏 = 端口悬空）。
- **M-14**：build tcl 断言 `P11_CFG_ENFORCE=1` 且恰一个 `P11_CFG_C{1..4}`，打印
  `P11_CONFIG = <single|mirror|shared|dual>`；缺/多/未知 ⇒ 硬失败。

**门读数**（`gates/tcl/run_p11_buildcfg_gate.bat`，Vivado batch）：
- `P11_HLS_ADV_HITS c1=0 p2=0 p3=3`；`P11_BUILDCFG_POS c3=OK config=c3 ; c4=OK config=c4`；
  `P11_BUILDCFG_GATE PASS`（3 archive exists + 3 hit counts + 2 正控 + 5 build-tcl 静态 + 6 负控）。
- 负控（6/6）：`no-enforce` / `two-C` / `dual-no-macro` / `dual-p2-net` / `nondual-p3-net` / `nondual-macro`
  各自返回预期 verdict。
- **C4 elab**（P3 网表 + 宏）：`P11_C4_ELAB PASS`；**C4 wrapper**：`P11_C4_WRAP TB PASS`。

### H-5 EXT_QUOTA=0 回归证据 —— ✅ 已重跑并归档
- 重跑三条门（stdout 归档到 `gates/logs/`）：
  - `sim/p5sim/run_tb_p5_fc.bat` → RC=0，`P5 FC UNIT GATE PASS` → `h5_tb_p5_fc.txt`
  - `sim/p5sim/run_tb_p5_flow.bat` → RC=0，`P5 FLOW OK` → `h5_tb_p5_flow.txt`
  - `sim/p5wu/run_tb_app_wu.bat` → RC=0，`P7B WU GATE PASS` → `h5_tb_app_wu.txt`
- 自定位 wrapper gate `_proj_10g/notes/p11_p3_fix_20261019/gates/sim/run_p3_ext0_regress.bat`
  → `P11_EXT0_REGRESS PASS`；已注册进常驻矩阵（门名 `p11_ext0`，`-only p11_ext0` 实测 EXIT=0）。

---

## 2. 逐项处置（M 档）

| # | 状态 | 处置与读数 |
|---|---|---|
| **M-1** | ✅ 已修 | C4 wrap TB arm A 改为**硬判据**（`idx>=0 && opcode==2 && SPA=IP_B`），补 arm C（ch0 SYN/IP_B ⇒ SYN-ACK 源 IP=IP_B，ch1 无回包）；门改用 P3 网表+宏；加 `scan_xsim_errors.py --mode c4wrap` 硬门（唯一允许 `u_slow_rx.u_ff` 的 RAMB36E2-11，4 次 allowed/0 violation）与 `P11_ACC_MARGIN_SELFCHK OK` 断言；TB 头注释与 REPORT §2.7 已订正（归档日志 `reply idx=13` 与旧报告 `-1` 相反）。读数：臂 B/A/C/D 全部 `[ ok ]`，`P11_C4_WRAP TB PASS`。 |
| **M-2** | ✅ 已修 | `gates/csim/check_csim.py`：解析 `P11_SUMMARY`，断言 `failed==3` 且 FAIL 多重集 == `{got SYN-ACK ×2, all 2000 echo bytes received ×1}`；unexpected 才非 0。`run_csim_p3.bat` 现在返回检查器状态（exe RC=1 作为信息行打印）；`run_csim_p3_all.bat` 三臂：`CSIM_P3_ALL_PASS`（passed=75/72/51，failed=3 各）。 |
| **M-3** | ✅ 已修 | `win_pool_mgr` 算术分支外 `slot<8` gate；unit 臂 F `snap()`/`chk_same_state()` 对 pool/pw0/pw1/grant_port/winq[0..7] **逐项相等**断言；`stat_slot_oor` 仅计数。 |
| **M-4** | ✅ 已修 | unit 臂 H（occ=0 / 0x17000 / ==pool / 两口不同）、臂 I（同拍 ev_up+rel：不同槽两者都处理、同槽 C18 吸收）、臂 J（8+0 / 6+2）；churn §8 8+0、§9 6+2（真实 app_ctrl）。读数 `WIN_POOL_MGR TB PASS` / `P3_CHURN TB PASS`。 |
| **M-5** | ✅ 已修（以 churn 定向断言代替独立单元 TB） | churn 每拍断言：① manager 扫描口/事件口同 id 不同时各自返回 `winq[id]`；② app_ctrl 的 `pa_winq == winq[pa_sid]`（期望值在捕获沿之前的 negedge 采样，`init_pend` 拍跳过）。负控 `m5single`（port0 事件口别名到扫描口）⇒ churn FAIL。**未做**独立 app_ctrl 单元 TB（登记为方法差异）。 |
| **M-6** | ✅ 已修 | `mk_mut_slow.py` + `run_negctl_slow.bat`：`cfg_w2rev` / `cfg_delw2` / `sm2_mix`（tlast 拍取另一口数据）/ `sd2_nolock`。4/4 变红（TB FAIL errors=1/4/4/5），`SLOW_NEGCTL_PASS`。slot=8 显式断言在 cfg demux TB arm D（既有）。 |
| **M-7** | ⚠ 未做（不在本轮指派清单） | G-P3-6 的 8 连接/计数/TX_DIS 全链覆盖未补；本轮的 C4 wrap 扩了 arm A/C + 错误硬门，但**改名/补齐仍未做**。 |
| **M-8** | ✅ 已修 | `sim/p4gates/p11neg_src.f` / `p11cfggate_src.f`（无任何 bat 引用）已删除；所有 negctl 写成自定位 gate，并新增矩阵行：`p11_negctl_wpm` / `p11_negctl_churn` / `p11_negctl_cfg` / `p11_negctl_slow` / `p11_negctl_p3fix` / `p11_static` / `p11_accmargin` / `p11_buildcfg` / `p11_ext0`（空 manifest `p11negctl_src.f`，因为这些 bat 只代理、无自有 xvlog）。`-only` 逐行实测 EXIT=0。 |
| **M-9** | ✅ 已修（静态） | `slow_merge2.rst_n` 改 `dp_rst_n`（与上游 `udp_split`/`slow_rx_adp` 同源）；静态门规则 `slow_merge2 reset = dp_rst_n (M-9)`；负控 `wrapper_slowmerge_reset_bad.v` 被拒。**未做** MMCM 重锁行为门（无受控触发路径）。 |
| **M-10** | ✅ 已修 | wrapper 新增 5 条独立具名 elaboration 硬门：`P11_DUAL_REQUIRES_{DUAL_SFP_A,P7B_10G,DP_156MHZ,APP_MODE,SFP2_MODE_A}`（不依赖 `P11_CFG_ENFORCE`）；负控 11/11：新增 `P11-noDual` / `P11-noSFP2A` 均被对应门拒绝（`CFG_NEGCTL_PASS`）。 |
| **M-11** | ✅ 已修（文档） | `REPORT.md` §7 改为"**存储** `DIGEST_ALL=851d1343…`；`compare` **按路径排序重算** `e4367d75…`"，并说明根路径斜杠写法影响字符串；不再写成"两次运行的两个摘要"。 |
| **M-12** | ✅ 已修 | `gates/hls_fingerprint.py` 产出 `gates/hls_hash.txt`：`HLS_SRC_HASH=a1340a4a…`（17 文件）、`NET_HASH_C1=dd538264…`（176）、`NET_HASH_P2=82f06e8e…`（175）、`NET_HASH_P3=0830d729…`（176）、`LIVE_VS_P3 same=173 diff=0 missing=0`。`sim/p4gates/paths.txt` 的 FINGERPRINT_GLOBS 追加 `hls\tb\*.cpp|*.h`、`board\p11_build_cfg.tcl`、`board\build_p7b_ku5p.tcl`、`gates\csim\*.bat|*.py`、fix-round gate 目录。 |
| **M-13** | ✅ 已登记（未执行） | `build_p7b_ku5p.tcl` 新增 `P11_FRAME_FIFO_STA` 段：post-impl 枚举所有 `frame_fifo` 实例并打印 `P11_FRAME_FIFO_STA_CELLS/CELL`；注释登记 32 片选（D=16384⇒NB=32）、`+1.1–2.2k LUT` 未计风险与构建轮定向 STA 命令。**未跑构建**，故无实际读数。 |
| **M-14** | ✅ 已修 | 见 H-4：build tcl 断言 ENFORCE=1 + 恰一个 C + 打印 `P11_CONFIG`；buildcfg 门负控 `no-enforce`/`two-C` 均红。 |

低档：**L-1 已顺手修**（grant_zero 用实际 g）；L-2/L-3/L-4/L-5/L-6(部分)/L-7..L-13 **未做**（本轮优先序未覆盖；L-6 的死清单部分已删 2 个 manifest）。

---

## 3. 门清单与重现命令（全部自定位）

```bat
:: H-1/M-3/M-4 单元 + 5 条负控
_proj_10g\notes\p11_p3_impl_20261018\gates\sim\run_tb_win_pool_mgr.bat
_proj_10g\notes\p11_p3_impl_20261018\gates\sim\run_negctl_wpm.bat
:: H-1/M-4/M-5 churn 集成 + 变异
_proj_10g\notes\p11_p3_impl_20261018\gates\sim\run_tb_p3_churn.bat
_proj_10g\notes\p11_p3_impl_20261018\gates\sim\run_negctl_churn.bat
_proj_10g\notes\p11_p3_impl_20261018\gates\sim\run_negctl_p3fix.bat
:: H-2 retx
_proj_10g\notes\p11_p3_impl_20261018\gates\sim\run_tb_retx_pool_shared.bat
:: H-3
_proj_10g\notes\p11_p3_impl_20261018\gates\sim\run_negctl_accmargin.bat
:: H-4/M-14
_proj_10g\notes\p11_p3_impl_20261018\gates\tcl\run_p11_buildcfg_gate.bat
:: M-6
_proj_10g\notes\p11_p3_impl_20261018\gates\sim\run_negctl_slow.bat
:: M-1/H-4
_proj_10g\notes\p11_p3_impl_20261018\gates\sim\run_elab_c4.bat
_proj_10g\notes\p11_p3_impl_20261018\gates\sim\run_tb_p11_c4_wrap.bat
:: M-2
_proj_10g\notes\p11_p3_impl_20261018\gates\csim\run_csim_p3_all.bat
:: H-5 / 静态 / M-10
_proj_10g\notes\p11_p3_fix_20261019\gates\sim\run_p3_ext0_regress.bat
_proj_10g\notes\p11_p3_impl_20261018\gates\sim\run_p3fix_static_gate.bat
_proj_10g\notes\p11_p3_impl_20261018\gates\sim\run_negctl_cfg_c4.bat
:: M-12
<anaconda>\python.exe _proj_10g\notes\p11_p3_fix_20261019\gates\hls_fingerprint.py
```

**负控"有牙"汇总**：wpm 5/5、churn 4/4（既有）+ p3fix 4/4、cfg 11/11、slow 4/4、accmargin 1/1、
buildcfg 6/6。变异件读数均为对应门自身的 FAIL/拒绝行（见各 `negctl_*.log`）。

---

## 4. 残余 / 未做 / 需裁

1. **未跑 Vivado synth/impl/位流/时序/资源** —— 本轮边界。H-4 的构建变体只有静态门 + elab 验证；
   `P11_FRAME_FIFO_STA`（M-13）与 +30k LUT 的实际读数在构建轮。
2. **未上板**，无板级读数。
3. **M-5 无独立 app_ctrl 单元 TB**：用 churn 的定向断言代替；`redge/fc_wq/wu_mark` 的逐字断言未做
   （`pa_winq` 已断言）。**M-7**（G-P3-6 8 连接/计数/TX_DIS 覆盖与改名）**未做**。
4. **M-9 只有静态门 + 变异负控**；MMCM 重锁/软复位下的行为未构造。
5. **H-1 churn 的"迟到 rel"是 `force` 注入**（见 §1-H-1 方法限制）。
6. **H-2 集成路径**：`grant_port` 在 ev_up 更新这一行为由 churn 5c 的真实 app_ctrl+manager 覆盖；
   retx 的 owner 翻转臂是直接改 `grant_port` 的单元激励，未做 cfg-demux→ev_up→retx 的联合波形核对。
7. **全矩阵**：见 §7（本轮跑的是 41 门；结果以该节为准）。
8. **低档 L-2..L-13** 未做（L-1 已顺手修，L-6 仅删死清单）。
9. 既有未决（与 FINDINGS 同）："跨口复用产品语义（manager 支持 vs 准入层禁止）"仍是**用户/判据所有者裁定**项；
   本实装按 manager 支持 + 属主门实现。

---

## 5. 改动文件清单

**RTL / 构建（功能）**
- `rtl/win_pool_mgr.v`（H-1/M-3/L-1）
- `rtl/retx_pool_shared.v`（H-2）
- `board/wrapper_p4.v`（H-2 接线 / H-3 分口+自检 / M-9 reset / M-10 五门 / 注释）
- `board/build_p7b_ku5p.tcl`（H-4 变体+配对 / M-14 ENFORCE / M-13 STA 登记）
- `board/p11_build_cfg.tcl`（新，H-4/M-14）

**门 / 脚本**
- `_proj_10g/p11_dual/sim/scan_xsim_errors.py`（新增 `c4wrap` 模式，M-1）
- `_proj_10g/notes/p11_p3_impl_20261018/gates/sim/`：
  `tb_win_pool_mgr.v`、`tb_p3_churn.v`、`tb_retx_pool_shared.v`、`tb_p11_c4_wrap.v`、
  `run_tb_win_pool_mgr.bat`(未改)、`run_tb_p3_churn.bat`、`run_tb_retx_pool_shared.bat`、
  `run_tb_p11_c4_wrap.bat`、`run_elab_c4.bat`、`run_tb_slow_{merge2,demux2,cfg_demux}.bat`、
  `run_negctl_wpm.bat`、`run_negctl_cfg_c4.bat`、`run_cfg_gate_c4.bat`(未改)、
  `mk_mut_wpm.py`、`mk_mut_retx.py`(新)、`mk_mut_slow.py`(新)、`mk_mut_accmargin.py`(新)、
  `mk_mut_static.py`(新)、`check_accmargin.py`(新)、`check_p3fix_static.py`(新)、
  `run_accmargin_gate.bat`(新)、`run_negctl_accmargin.bat`(新)、`run_negctl_slow.bat`(新)、
  `run_negctl_p3fix.bat`(新)、`run_p3fix_static_gate.bat`(新)
- `_proj_10g/notes/p11_p3_impl_20261018/gates/csim/`：
  `check_csim.py`(新)、`run_csim_p3.bat`、`run_csim_p3_all.bat`(新)
- `_proj_10g/notes/p11_p3_impl_20261018/gates/tcl/`：
  `run_p11_buildcfg_gate.tcl`(新)、`run_p11_buildcfg_gate.bat`(新)
- `_proj_10g/notes/p11_p3_fix_20261019/gates/`：
  `sim/run_p3_ext0_regress.bat`(新)、`hls_fingerprint.py`(新)、`hls_hash.txt`(生成)、
  `logs/h5_*.txt`、`logs/full_matrix_console.txt`（本轮读数）
- `sim/p4gates/run_matrix_p4dfix.bat`（+9 门：p11_negctl_{wpm,churn,cfg,slow,p3fix} / p11_static /
  p11_accmargin / p11_buildcfg / p11_ext0）
- `sim/p4gates/paths.txt`（FINGERPRINT_GLOBS 扩 hls/tb、csim、build tcl、fix gates；
  **`HLS=` 从 live `hls/slowstack_prj/...` 改为归档 P2 双 IP MAX=3 网表** —— 见 §7.1）
- `sim/p4gates/p11negctl_src.f`（新）；**删除** `sim/p4gates/p11neg_src.f`、`sim/p4gates/p11cfggate_src.f`
- `_proj_10g/notes/p11_p3_impl_20261018/REPORT.md`（M-1 §2.7 / M-10 11/11 / M-11 digest 叙事订正）

**未改**：P2/P3 HLS 归档、HLS 源（未重跑 csynth）、任何 `D:\repo\perfv`/license/QSPI/位流。

---

## 6. 关键技术读数（供 TL 引用）

- 128KB 物理预算：`Σwinq(96KB=98,304) + N×ACC + 2816 + 1518 + 1500 ≤ 131,072`
  ⇒ `N×ACC ≤ 26,934`；N=8 ⇒ **26,624（余 310 B）**；旧共用 margin=4096 时 **136,906（超 5,834）**。
- HLS 端口配对：C1 归档 `i_tcp_adv_wnd` 命中 0，P2 归档 0，P3 归档 3；
  live solution1（2026-10-19 02:0x）与 P3 归档 **173/173 文件逐字节相同**。
- C4 wrap：`P11_ACC_MARGIN_SELFCHK OK n0=4096 n1=4096 n8=3328`；arm A/B/C/D 全 `[ ok ]`；
  `XSIM_ERROR_SCAN allowed=4 violations=0`（4 次均为 `u_slow_rx.u_ff` RAMB36E2-11 bypass）。
- csim：MAX8/DUAL1 `passed=75 failed=3`；MAX3/DUAL1 `72/3`；MAX3/DUAL0 `51/3`；FAIL 集合恰为 P2 基线。

---

## 7. 常驻矩阵（41 门）

本轮在 32 门基础上新增 9 门（见 §5）。**全矩阵运行结果**见本节下方（结果写入
`sim/p4sim/matrix_p4dfix.log` 与 `gates/logs/full_matrix_console.txt`）。

### 7.1 ⭐ 本轮发现并修掉一个矩阵基础设施缺陷（H-4 的"门侧"同构）

第一次全矩阵在 **`chain` 门即红**：`P4 CHAIN FAIL (2 errs)` / `MISMATCH: slow stream
['arp','icmp','udp'] != ['arp','icmp','udp','synack','arp']` / `SLOWTX got (3,0) exp (5,0)`。
根因**不是本轮 RTL**：所有 P4/P5 门经 `%HLS%` 编译的是 **live `hls/slowstack_prj/solution1/syn/verilog`**，
而该目录在审查期间被 HLS 重跑**换成了 P3 网表**（MAX=8 + `i_tcp_adv_wnd`）。现有 P4/P5 TB 的
`udp_echo` 例化没有这个端口 ⇒ 悬空输入（Z/X）⇒ SYN-ACK 通路行为改变。
这正是 H-4 要消灭的"网表/宏不配对"，只是发生在**门**而不是构建。

**修法**：`sim/p4gates/paths.txt` 的 `HLS=` 从可变 build 输出改为**归档 P2 双 IP MAX=3 网表**
（`_proj_10g/notes/p11_p3_build_20261019/hls_archive_p2_dual_ip_max3`，即 HEAD 矩阵当时的 175 文件）。
另有三个门**硬编码**了 live 路径，一并改钉归档 P2：
`_proj_10g/p11_dual/sim/run_tb_p11_dual.bat`（第一次全矩阵的唯一红 = `g6_p11_dual`）、
`_proj_10g/p7b_chain/sim/run_tb_p7b_chain.bat`、`sim/p5sim/run_tb_p5_wrapper.bat`。
C4 门继续显式用 P3 归档 + `P11_HLS_ADV_WND`。修后单跑 `-only chain` ⇒ `P4 CHAIN OK`，
三个硬编码门单跑全 `EXIT=0`，第二次全矩阵 41/41 / 0 failed / FROZEN。
⇒ **纪律建议**：任何门都不得指向 live HLS 输出；P2/P3/C1 三个归档是唯一稳定输入。

### 7.2 结果

- **全矩阵（41 门）= `gates run : 41 / 41` · `gates failed: 0` · `VERDICT: FROZEN`**
  （400 个哈希文件逐字节相同；私有 workdir `sim/p4gates/work_20261019_030550`）。
  `GIT_HEAD = 27513627`（TL 审查收口提交）。
  摘要口径（照 M-11 的教训分开写）：
  **存储** `DIGEST_ALL = 6770eea2…`（400 文件，pre-content-v1 方案，含 size/mtime）；
  **内容重算** `DIGEST_ALL(content) = 4f549789…`；`FILES_ALL = 400`；`DIGEST_COMPILE = 516712d5…`（258 文件）。
- 过程（如实）：第一次全矩阵（03:0x）**41/41 跑完、1 红 = `g6_p11_dual`**；根因见 §7.1 —— 同一 live-HLS
  漂移在三个门里还有**硬编码**路径（`run_tb_p11_dual.bat` / `run_tb_p7b_chain.bat` / `run_tb_p5_wrapper.bat`）。
  三处全部改钉 **P2 归档**后单跑三门口 `EXIT=0`，随后第二次全矩阵 = 上列 **41/41 / 0 failed / FROZEN**。
- 已单独经矩阵 runner 验证的新门（`-only`）：`p11_accmargin`、`p11_buildcfg`、`p11_ext0`、
  `p11_negctl_slow`、`p11_negctl_p3fix`、`p11_static` 全 EXIT=0；第二次全矩阵里 9 个新门也全 0。
- 指纹：M-12 的哈希见 §2/M-12；`paths.txt` 扩了 globs（382 → 400 文件；258 编译面不变）。

---

## 8. 提交注意（TL）

1. **新增文件均为 untracked**（本轮不写 git）：见 `git status` 的 `??` 清单 —— 包括
   `board/p11_build_cfg.tcl`、`sim/p4gates/p11negctl_src.f`、fix-round 全部 gate/脚本、
   `gates/tcl/`、`gates/csim/check_csim.py`、`run_csim_p3_all.bat`、各 `mk_mut_*.py`、
   `check_*.py`、`run_negctl_*.bat`、`mut/` 新变异件。
2. ⚠️ **HLS 归档是 build/gate 的新依赖且当前 untracked**：
   `_proj_10g/notes/p11_p3_build_20261019/hls_archive_p2_dual_ip_max3/`（175 文件）、
   `.../hls_archive_p3_dual_ip_max8/`（176 文件）在 `git ls-files` 下 **0 条**；
   `_proj_10g/notes/p11_build_0x2C_20261018/hls_archive_single_ip/` 只有 1 条 tracked。
   本轮的 `build_p7b_ku5p.tcl` 变体选择与三个 P4/P5/P7b 门都**指这几个归档** ⇒
   若 TL 不把归档一起入库，换一个 checkout 后默认构建/矩阵会报
   `P11_HLS_NETLIST_MISSING` / `P11_HLS_P2_ARCHIVE_MISSING`。**建议显式 `git add` 归档目录**
   （不做 `git add -A`，遵守仓库纪律）。
3. 已删除 `sim/p4gates/p11neg_src.f` / `p11cfggate_src.f`（D 状态），请随提交带走。
4. 门日志（`gates/sim/*.log`、`gates/logs/*`）多为 tracked 文件，本轮重跑已更新；
   若不希望入库日志 diff，可只提交脚本/报告（但那样 `gates/logs/` 的 H-5 证据会缺）。
