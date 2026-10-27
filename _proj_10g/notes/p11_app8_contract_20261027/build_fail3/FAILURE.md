# 0x34 构建 #4（Congestion_SpreadLogic_high）：仍 TIMING_FAIL，但读数明显改善

- 日期：2026-10-28
- 输入：`P11_CFG=c4 P11_APP8=1 P11_APP8_OCC=0 P11_IMPL_STRATEGY=Congestion_SpreadLogic_high`
  （无 pblock；`P11_APP8_PBLOCK` 默认 0）
- 该策略在实现中落为 `place_design -directive AltSpreadLogic_high`（`runme.log:305`）
- 位流：`wrapper_p4.bit.TIMING_FAIL`（quarantine；**禁烧**；本目录留档）
- 全量报告/dcp/日志：本目录（`SHA256SUMS.txt` 覆盖）

## 1. 读数（原件）

| 项 | 值 | 出处 |
|---|---|---|
| WNS | **−0.205 ns** | `wrapper_p4_timing_summary_routed.rpt` Design Timing Summary |
| TNS / setup 失败端点 | **−506.882 ns / 5,162** | 同上 |
| WHS / hold 失败 | +0.005 ns / 0 | 同上 |
| PW 失败 | 0 | 同上 |
| 失败时钟 | 仅 `g_hw.clk_out0`（DP） | 同表 Intra Clock Table |
| 门 | `P7B_TIMING_GATE = FAIL (wns=-0.205 setup=5162 hold=0 pw=0)` | build stdout |

## 2. 最差路径（与 #2 不同族）

```
Slack = -0.205 ns
Source:      u_tcp_tx/bank_rdy_reg[1]_replica/C
Destination: u_app/g_app[4].u_app_i/pw_data_reg[29]/CE
Data Path:   6.479 ns (logic 2.098 / 32.4%, route 4.381 / 67.6%)
Logic Levels: 22 (CARRY8×2, LUT6×10, MUXF7/MUXF8, ...)
```

最差 10 条里同一源还打到 `u_tcb/rcv_nxt_r_reg[14][*]/CE` —— **port0 的 TX bank-ready
扇出锥**（同一根 `bank_rdy` 同时驱动 TCB 写使能与 app 的 TX CE）。

## 3. 三次实验对照（全部同一 RTL/合同，仅布局/策略不同）

| # | 输入 | WNS | setup 端点 | 结论 |
|---|---|---|---|---|
| 2 | ExtraTimingOpt，无 pblock | −0.337 | 6,642 | 基线 |
| 3 | ExtraTimingOpt + `u_app` pblock（左下） | −0.644 | 13,282 | **否定**（pblock 反噬） |
| 4 | Congestion_SpreadLogic_high（AltSpreadLogic_high），无 pblock | **−0.205** | **5,162** | **改善但仍 FAIL** |

- 方向结论：**打散布局（spread）确实有效**（−0.132 ns / −1,480 端点），但幅度不足以补上
  8×app 进 DP 的边际代价（0x33 同族 +0.008）。
- 最差族从 「port1 `u_tcp_tx2/u_fifo_b → u_tcb2`」 变为 「port0 `u_tcp_tx/bank_rdy →
  tcb/app CE 锥」 ⇒ 说明这是**多点同时受压**，不是单根线可以救的。

## 4. 处置

1. **不烧板**；0x35（OCC=1）仍不构建；板级 A/B 继续暂停。
2. 下一实验（**新输入**）= `P11_IMPL_STRATEGY=Performance_NetDelay_high`（无 pblock）：
   最差路径 route 占 67.6%，该策略走 `ExtraNetDelay_high` 放置 + 激进 phys_opt + Explore 布线，
   直接压 net delay。判决仍为全构建 `P7B_TIMING_GATE`；失败则再归档，不烧。
3. 结构结论保持：即使这一轮策略能压过门，`0.345 ns / 7 app` 的边际意味着下一轮必须做
   **8×app 组独立时钟域 + AXIS CDC**（或 app 逻辑降面积/共享），不能依赖布局运气。
