# 独立审查回灌（0x31 ROM 修复 / 0x32 构建+板级）

- 审查方式：独立只读 agent（Explore），对 `README_FOR_TL.md` + 原始日志逐条核对；2026-10-26
- 本件只记**处置**，不改审查原文的严重度；未完成项明确写“未做”。

| # | 审查发现（摘要） | 处置 | 当前状态 |
|---|---|---|---|
| H1 | TCB 定向门只覆盖 stack1；0x32 全局 WNS 宿主是 `u_tcp_tx2/u_fifo_b/rptr[0] → u_tcb2/rcv_wnd[9][0]`（+0.019） | `board/p11_sta_tcb_probe.tcl` 已加 A2–F2 + G2；build tcl 的 `P11_STA_TCB_GATE` 同步；0x32 DCP 重跑 v2 probe：A2=0.047 / C2=0.041 / **G2=0.019 = 全局 WNS**、TCB_MIN=0.019、GATE=PASS（`gates/sta_0x32_tcb_v2.txt`）；另加 `gates/gate_unit_test/`（抽真实 Tcl 块 + tclsh stub）覆盖 PASS/缺 pin/负 slack/SKIP 四臂 | **已做**（build tcl 的下一次构建执行新门；本轮未重建；单测 8/8 PASS 只证门逻辑，不证 Vivado 集成） |
| H2 | 0x31 隔离不完整：burn-dir + 两个 archive 仍有 `.bit`；`bits/SHA256.txt` 旧 | 三处全部改名 `*.HLS_ROM_FAIL`；`bits/QUARANTINE_0x31.txt` 增加清单；`bits/SHA256.txt` 重写为隔离件 + 0x32 合法件；全仓按 15,431,261 B + sha 扫描 0 个未隔离 0x31 | **已做**（扫描 `SCAN_DONE` 无 STILL_BAD） |
| H3 | 多处【已证·板级】数字无 raw 锚点（ping/UDP/TX_DIS/CLEAN_AFIRST/逐跑 W83/W84/0x31 +1/+2） | 已删除无锚的 CLEAN_AFIRST 行；W7/W20 改为终态锚点；W83/W84 逐跑改为“未归档，以 sink 原始日志为准”；0x31 purge 成分降为【未定位】；**ping/UDP echo 已落 `raw/PING_UDPECHO_0x32.txt`、TX_DIS 已落 `raw/TX_DIS_0x32.txt`**；ping 值更新为归档跑（0.073/0.093/0.117 与 0.064/0.066/0.070 ms） | **已做**（除 0x31 逐请求 W18 无法重跑：0x31 无效且已不在板；该条保留“未归档/未定位”） |
| H4 | 未解释 0 B/低率臂（BPORT/DP_A/STG_A_B/B_AFTER） | README 新增 §4.4a 逐臂登记：connect OK 0 B / 低率，`PIN_THREAD` 撞核见证；**未定位**；不作为板级判据；清洁证据 = B1/B2、SP3、D9R（raw 8.9367/8.9352G）；旧 D9 仅历史 | **已做** |
| M5 | 12.62G 是 host-side sum，不是板 aggregate；12.31 无锚 | 删除 12.31 行；旧 D9 的 `D9_A/D9_B` sink 日志 **0 B（03:09 capture failed）** ⇒ 8.798/8.925、17.72、`mism=0` 降为历史会话读数；**2026-10-27 D9R raw 重跑**：A 8.9367 / B 8.9352 Gbps、17.8719G host-side、`mism=0`、无 STALL（`raw/D9R_A_sink.txt`/`D9R_B_sink.txt`），板侧 W83/W84 各 +6.85M、W54=0；2×9.4G 仍【未判定】 | **已做（D9R raw 关闸）** |
| M6 | ROM 门只查失败，不要求正读 `8-3876`；不校验内容 hash | build tcl 已加 `P7B_HLS_ROM_READ_OK`（必须 ≥ 本次 `.dat` 数；否则 `HLS_ROM_READ_MISSING`）；`check_hls_rom_gate.py` 同时统计：0x31=6 命中/0 正读、0x32=0 命中/3 正读、PASS；`.dat` 内容 sha 见 `evidence/STRAY_DAT_SHA256.txt`；`gates/gate_unit_test/` 用真实 Tcl 块覆盖 good/`8-4445`/2 正读 3 `.dat`/日志缺失四臂 | **已做**（下一构建执行新门；本轮未重建；单测 8/8 PASS 只证门逻辑，不证 Vivado 集成） |
| M7 | 同一 `.dat` 回退 bug 仍在 10 个旧 build 脚本 | 12 个 `board/*.tcl`（10 个 review 列出的 + `timing_p5.tcl` + P7b）全部改为“唯一 `imports/*/udp_echo.v` + 硬失败 + copy/size 校验”；静态门 `gates/check_build_dat_pattern.py` = `OLD_PATTERN_HITS=none` / `ROBUST_FILES=12` / PASS | **已做（静态）**；未逐脚本重建（不在本轮构建范围） |
| M8 | 读侧默认 0x2D，J6 档表无 0x32，env override 仍失败 | 已同步 `p7b_snap.sh`/`p6e_snap_check.sh`/`p7b_gate4_accept.sh`/`final_state.sh`/`tb_biz_win.v`/`tb_p6e_pcie_*.v`/`gen_inputs.py` 默认；`j6_r6fix.sh`+`tcpreg_j6.sh` 加 0x32 顶档（26 档）；`apply_readside_bid1c.py` 加 `0x32` 空阶段 + ALLOW 历史轮；`--bid 0x32 --assert` **RC=0 / 0 fail**（`gates/readside_assert_0x32.log`） | **已做** |
| M9 | README 的 W7/W20 与终态快照不一致 | 改为 `W7=0x15` / `W20=0x68bb9f`（`FINAL_STATE_0x32.txt:18/31`） | **已做** |
| M10 | 40GB A 跑的板侧 W83/W84 不能从终态重建 | 单口表改为“逐跑 W83/W84 未归档；以 sink 原始日志为准”；D9 有前后快照与增量 | **已做** |
| M11 | 0x32 烧录日志仍名 `BURN_0x31_*` | `burn_0x32_board.sh` 文件名改为 `BURN_0x32_*`；已有 3 个日志改名 | **已做** |
| L12 | “0x32 是 BID-only”不精确 | 改为“BID + HLS ROM 初始化；快照几何 85/0x184 不变” | **已做** |
| L13 | MGR 行号引用错 | 改为 `sta_0x32_tcb.txt:138/142/146/151/161` | **已做** |
| L14 | “imports 下 0 .dat 现读复核”已不可复现 | 改为“0x31 构建时；现 0x32 工程已含 3 个 `.dat`，现场不可现读复核；物证 = synth 日志 + 散落 board/” | **已做** |
| L15 | 73–188 µs 上限无锚 | 改为 0x32 实测 0.073–0.148 ms；0.188 引用 0x2D 历史件 | **已做** |

## 审查确认成立、本轮不需要改的项

- 0x31 构建侧根因：6 条 ROM 命中、0x2D 对照 0 命中、0x32 3 条 `8-3876`、导入目录/`.dat` 哈希逐字一致。
- `.dat` 修复目录 = 综合实际读取目录（`build0x32/runme_synth_1.log:590/596/786`）；当前 c1/p2/p3/c4 三变体各有 3 个 `.dat`，不会因计数硬门误伤。
- 时序/TCB 数字在 build 日志、独立 probe、README 间一致；**但** A–F 覆盖不足（H1）。
- 资源/DRC/位流 sha、单口 sink 速率/`mism=0`、SYN-ACK 合同、身份终态、构建门 PASS 均有原件。
- 0x31 板级 W7=0/W20=0/W6/W16/W25/W17/0x08/carrier 读数可排除 reset/clock/config/TX_DIS 的明显替代解释；ROM 全 0 是充分原因。
