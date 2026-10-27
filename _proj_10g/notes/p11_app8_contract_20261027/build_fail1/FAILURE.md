# 0x34 构建失败 #2：`P7B_VERDICT = TIMING_FAIL`（证据与处置）

- 日期：2026-10-28
- 输入：`P11_CFG=c4 P11_APP8=1 P11_APP8_OCC=0 P11_IMPL_STRATEGY=Performance_ExtraTimingOpt`
- 位流：`wrapper_p4.bit.TIMING_FAIL`（quarantine；**禁烧**；本目录留档）
- 全量报告/日志：本目录（`SHA256SUMS.txt` 覆盖）；stdout = `p7b_ku5p_stdout.txt`

## 1. 读数（原件）

| 项 | 值 | 出处 |
|---|---|---|
| WNS | **−0.337 ns** | `p7b_ku5p_stdout.txt` `P7B_WNS`；`p7b_ku5p_timing.rpt:155` |
| TNS / setup 失败端点 | −973.039 ns / **6,642** | 同上 |
| WHS / hold 失败 | +0.008 ns / 0 | 同上 |
| PW 失败 | 0 | 同上 |
| 门 | `P7B_TIMING_GATE = FAIL (wns=-0.337 setup=6642 hold=0 pw=0)` | stdout:7896 |
| 其它门 | 模块解析/黑盒/CDC/ROM/HLS 全过；DRC 见 `p7b_ku5p_drc.rpt` | stdout |

## 2. 最差路径（`p7b_ku5p_timing.rpt:2048-2145`）

```
Slack (VIOLATED) = -0.337 ns
Source:      u_tcp_tx2/u_fifo_b/rptr_reg[0]_replica/C
Destination: u_tcb2/rcv_nxt_r_reg[9][11]/CE
Data Path: 6.597 ns (logic 1.690 / 25.6%, route 4.907 / 74.4%)
Logic Levels: 18 (CARRY8×2, LUT6×8, ...)
```

- 这是**既存 DP 族**（0x33 的 WNS 宿主就是同族 `u_tcp_tx2/u_fifo_b → u_retx_pool`，+0.008）。
- 0x34 新增的是 **8 × `app_pattern`（u_app = 15,328 LUT / 5,956 FF，synth 142,049 LUT = 65.5%）**，
  全部在同一个 `dp_clk` 域；DP 的 route 从 0x33 的余量变成 **4.907 ns / 74%** ⇒ −0.337。
- 形态 = **布线拥塞**（logic 只占 25.6%），不是逻辑级数爆炸。

## 3. 处置（按 DESIGN_OCC_V6 §6.5/§6.9 backstop）

1. **不烧板**；0x35（OCC=1）**不同批**；板级 A/B 暂停。
2. 本失败构建的报告/位流已归档（本目录），因为下一次 `create_project -force` 会清 `impl_1/`。
3. 首个修复实验（**新输入，不是"重跑到过"**）：
   `board/ku5p_p7b_app8.xdc` = 把 `u_app`（8×app 组）隔离到 `SLICE_X0Y0:SLICE_X49Y79`
   的 pblock，让 DP 的 tcb2/ackq/slow_cfg2 路径不再与 8 个 app 实例争布线。
   判决仍是**全构建 `P7B_TIMING_GATE`**（WNS>0 ∧ 0/0/0）；失败则再归档，不烧。
4. 其它候选（本轮不启用，登记）：
   - 8×app 组独立时钟域 + CDC（改动大）；
   - `app_multi8` 的 8 路聚合统计（4×8→1 的 32 位加）打拍（先看定向 STA 是否命中）；
   - 8 个 `app_pattern` 的 TX/RX 图案逻辑共享/降面积（产品级）。
5. 口径：本轮**没有**"8×12KB 板级已验"的任何读数；0x34/0x35 的板级、F1/OCC 的板级都**未做**。
   单元门与变异门（`tb_echo_occ`、`tb_slow_cfg_init`、`tb_app_ctrl_occ`、8 变异全红）仍成立。
