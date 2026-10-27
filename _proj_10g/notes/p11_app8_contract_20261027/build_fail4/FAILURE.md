# 0x34 构建 #5（Performance_NetDelay_high）：**显著更差**，策略方向被否定

- 日期：2026-10-28
- 输入：`P11_CFG=c4 P11_APP8=1 P11_APP8_OCC=0 P11_IMPL_STRATEGY=Performance_NetDelay_high`（无 pblock）
- 位流：`wrapper_p4.bit.TIMING_FAIL`（quarantine；**禁烧**；本目录留档）
- 全量报告/dcp/日志：本目录（`SHA256SUMS.txt` 覆盖）

## 1. 读数

| 项 | 值 |
|---|---|
| WNS | **−0.886 ns** |
| TNS / setup 失败端点 | **−6,930.864 ns / 14,630** |
| WHS / hold 失败 | +0.008 ns / 0 |
| PW 失败 | 0 |
| 门 | `P7B_TIMING_GATE = FAIL (wns=-0.886 setup=14630 hold=0 pw=0)` |

最差路径 = `u_tcp_tx/u_fifo_a/rptr_reg[4]/C → u_tcb/snd_nxt_r_reg[10][13]/CE`
（回到 port0 的 **TX→TCB 写使能族**；与 #4 的 `bank_rdy→app CE` 不同族）。

## 2. 五次输入对照（同一 RTL/合同）

| # | 输入 | WNS | setup 端点 | 判决 |
|---|---|---|---|---|
| 2 | `Performance_ExtraTimingOpt`，无 pblock | −0.337 | 6,642 | 基线 |
| 3 | #2 + `u_app` pblock（左下） | −0.644 | 13,282 | **否定**（pblock 反噬） |
| 4 | `Congestion_SpreadLogic_high`（AltSpreadLogic_high），无 pblock | **−0.205** | **5,162** | **最好的已知输入，但仍 FAIL** |
| 5 | `Performance_NetDelay_high`，无 pblock | **−0.886** | **14,630** | **显著更差 ⇒ 方向否定** |

## 3. 结论与处置

1. **策略/布局搜索到此为止**：最好的已知输入是 #4（−0.205），距门还差 0.205 ns；
   #5 证明 `ExtraNetDelay_high` 放置会把这族路径拉得更长。
2. **不烧板**；0x35（OCC=1）不构建；板级 A/B 暂停。
3. 下一轮 = **架构改动**（`NEXT_TIMING_STUDY.md` 方案 A：8×app 独立 156.25 MHz 域 +
   TX/RX 77-bit AXIS CDC + 事件/close/ready/统计 CDC + app 区 pblock），或方案 B（图案引擎共享）。
   两者都需独立设计 + 审查；不再"换策略重跑"。
4. 若未来需要一次快速对照：`P11_IMPL_STRATEGY=Congestion_SpreadLogic_high` 是当前最优输入，
   但它单独**过不了门**（−0.205）。
