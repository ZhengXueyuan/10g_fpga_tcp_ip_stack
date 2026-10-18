# P11 · P3 / 0x2F 构建报告（C4 甲·双栈，合同 2×48KB）

- 日期：2026-10-19 04:50–06:03（构建耗时约 73 min）
- 仓库根 `D:\repo\XCKU5PMini\udp_hls_10g`；输入基线 = `148a2f22`（BID/合同配置）+ 构建轮 Tcl 修复（未提交于构建时，见 §4）
- 构建入口：`P11_CFG=c4 cmd //c 'board\run_build_p7b_ku5p.bat'`（只走该入口；未碰 QSPI/板）
- 配置：`P11_CFG_INPUT=c4 (env)` · `HLS_VARIANT=p3_dual_max8` · `P11_CONFIG=c4 (dual)` · `P11_HLS_ADV_WND_HITS=3` · `P11_DUAL=1` · `P11_CFG_ENFORCE=1`
- HLS：`HLS_SRC_HASH=b7dd1542…`（15 文件）· `HLS_NET_HASH=125a71f8…`（176 文件，P3 双 IP MAX=8 + `i_tcp_adv_wnd`）
- 合同：`P11_EXPECTED_CONNS=2`（`WQ_CAP_5=0xC000` = 48KB/连接）；BID `0x2F`

## 1. 结论（先读）

**构建完成、位流已出，但时序门 FAIL ⇒ 禁止烧录。**

| 项 | 读数 |
|---|---|
| `P7B_VERDICT`（脚本） | **OK**（只判位流文件存在，**不判 WNS**） |
| 位流 | `088948dfa4effbd574fbc01e96d0b0ceb97002d81fe7791f4db33ed87fe3a1f0` · 15,431,261 B |
| **WNS / TNS** | **−6.456 ns / −55,816.719 ns** |
| **setup 失败端点** | **25,697 / 371,939** |
| WHS / hold 失败端点 | +0.010 ns / 0 |
| WPWS / PW 失败端点 | 0.000 / 0 |
| 时序结论 | **"Timing constraints are not met."** |

⇒ **本构建不满足设计构建门（WNS>0、三类失败端点 0/0/0）**；位流仅作废件留在 `vivado_prj/.../impl_1/`，**不得烧板**。

## 2. 最差路径（根因）

```
Slack -6.456 ns
Source:      u_app_ctrl/c_rcv_nxt_reg[9][4]/C      (FDCE, g_hw.clk_out0 6.400ns)
Destination: u_win_pool/port_win1_reg[0]/D          (FDCE, 同钟)
Data Path Delay: 13.137 ns (logic 4.788 / route 8.349)
Logic Levels: 42 (CARRY8=14, LUT2/3/4/5/6, MUXF7=3)
```

- 路径 = **app_ctrl 扫描态 → `o_quota_rel`（组合）→ `win_pool_mgr` 的授予/归还 17 位算术 → `port_win1`**。
- 0x2D 的 app_ctrl 扫描块已做过 3 拍流水（P5b 时序修复），但 **`EXT_QUOTA` 新增的 release/grant 路径没有流水**：扫描态直接组合进 manager 的加法/比较链。
- 25,697 个失败端点与这条链/`pool`/`winq_rd`/`grant_port` 的扇出同族（具体端点族待定向 `-from` 查询；本报告只记录首条路径）。
- 这是**新 C4 共享池路径的时序缺陷**，不是"0x2D 余量不够"的简单叠加。

## 3. 资源（placed）

| 资源 | 0x2F | 0x2D |
|---|---|---|
| CLB LUT | **122,366 (56.40%)** | 82,013 |
| CLB FF | **98,160 (22.62%)** | 77,361 |
| Block RAM Tile | **109 (22.71%)** | 346 |
| URAM | **17 (26.56%)** | 1 |
| DSP | 4 | 4 |

- BRAM 大幅下降、URAM 17：P3 HLS（MAX=8）与 128KB echo 的存储被映射到 URAM/分布式 RAM；**设计纸面的 BRAM 267/395 与 URAM=1 不成立**，需在资源账上订正（构建轮已观察到）。
- URAM 17/64 仍有余量；BRAM 109/480 余量充足。

## 4. 构建轮修掉的两个构建集成缺陷（前两次失败的原因）

1. **RTL 文件清单漏 5 个新件**：`build_p7b_ku5p.tcl` 的 `import_files` 未含 `win_pool_mgr/retx_pool_shared/slow_merge2/slow_demux2/slow_cfg_demux`；首跑 synth 报 `module 'slow_cfg_demux' not found`。已补齐。
2. **C4 module-resolve 门误判**：旧门硬性要求 `rx_merge2/tx_demux2 ≥1`；C4 中两者**按设计退役** ⇒ 第二跑 synth 成功后门误报 `P7B_MODULE_MISSING_OR_BLACKBOX`。已改为：C4 预期 `n1=n2=0`，并检查 5 个 P3 新件各 ≥1 且无黑盒；非 C4 保持原条件。
3. `board/p11_build_cfg.tcl` 的 `switch` 体内行内 `;#` 被 Tcl 解析成额外 pattern ⇒ 首跑早退；删除该注释后 `P11_BUILDCFG_GATE PASS`。

## 5. 已通过的门/读数

- IP 收敛：`P7B_CONVERGED_AT_ROUND = 2` · `P7B_IS_LOCKED_POSTGEN = 0`
- P3 模块：`win_pool_mgr=1 retx_pool_shared=1 slow_merge2=1 slow_demux2=1 slow_cfg_demux=1` · `P7B_BLACKBOX_COUNT 0`
- F-21 CDC：`P7B_SNAP_TOP5_SLOTS_OK = 2`（槽 39/40 各 32 cells）· `P7B_SNAP_TOP5_FANOUT_OK`（`hold_b=1` / `snap_din=0`）
- `P7B_BIT_EXISTS = 1`

## 6. 下一棒（按优先级）

0. **先补构建脚本的时序硬门**：本轮 `P7B_VERDICT=OK` 只判位流存在，**不判 WNS/失败端点** ⇒ 时序 FAIL 的位流也拿到 OK。下一轮构建前必须把 `WNS>0 ∧ setup/hold/PW 失败端点=0` 写成 `P7B_VERDICT` 的前置条件（或 bat 的 `P7B-TIMING-GATE`），否则同形误判会复发。
1. **给 release/grant 路径加流水**（首选）：`o_quota_rel` / `o_quota_rel_slot` 打 1 拍；`win_pool_mgr` 的事件捕获→算术→`pool/winq/port_win` 更新改成 1–2 拍流水（事件稀疏，延迟可接受）。目标：切断 `app_ctrl 扫描态 → port_win` 的组合链；重跑 `tb_win_pool_mgr` / `tb_p3_churn` 与定向 STA。
2. 若流水后仍不收敛：退 **M3（每口 48KB，无共享 manager）**，明确违背用户"共享池"语义；或对 `o_quota_rel` 只做寄存、manager 侧保持组合（先量哪一段占 13.137ns）。
3. **重建用新 BID（建议 0x30）**；0x2F 位流 `088948df…` **禁烧**。
4. 构建前先跑一次 **定向 STA 预检**（同网表 synth 后 `report_timing -from u_app_ctrl/c_rcv_nxt* -to u_win_pool/port_win*`），避免再花 73 min 才发现。
5. 资源账订正：BRAM 109 / URAM 17（设计 267/1 不成立），下一轮报告按实际写。

## 7. 边界

- 未上板；板仍 = 0x2D + `0x08=0` + carrier 1/1；QSPI 零写。
- 本构建的位流未入库（15.4 MB），sha/大小见 `BIT_SHA256.txt`；时序/资源/DRC 报告与完整 stdout 在本目录。
- 矩阵 41/41 FROZEN 是在 `148a2f22` + Tcl 修复前（buildcfg 门已单独重跑 PASS）；本构建的输入 = `148a2f22` + 本目录 §4 的三处 Tcl 修复。
