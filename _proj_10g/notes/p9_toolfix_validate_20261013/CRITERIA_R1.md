# R1 实窗验证 — 判据（先写后跑）

> 本件落盘时刻 2026-10-13 23:2x（+0800），**早于**窗口启动 —— 判据"先写后跑"的物证 = 本件 mtime < 窗口 stdout 件 mtime。
> 轮次：修复版工具切换 + R1（B-1 dual 窗 READLOG 两段锁竞态 → 锁合并修复）真实 dual 窗验证。
> **本件不下 PASS/FAIL 裁定**；「未观测到」≠「不存在」。

## 窗口构型（与 0x24 板级轮主臂 S0 同构型）

- K=1 GiB · chunk 4 MiB · `--dual 2` · unpaced（源 `--mbps 0`）· `--readlog 1` · `--no-verify` ·
  `--src udp` · SECS=6 · SAMPLE_MS=1000 · BUFMB=1024 · FIXOFF=0（off=0）·
  NW=71 · EXPECT_BID=0x00000024 · TOOL=/tmp/p7b_biz/p7b_mir_dump（切换后 = 修复版 `48dcbcb2…`）。
- 主读数 = `MIR_STREAM_ACCT` 的 **ΔW70**（快照差分口径；不依赖 READLOG ⇒ 对 B-1 类竞态免疫）。

## 三道 READLOG 判据（R1-a / R1-b / R1-c）

### R1-a — 行级 uint32 回绕

- **判据式**：全部 READLOG 行 `dw70 < 2^31`（= 2,147,483,648）。
- **理由**：B-1 竞态的行级失效形态 = `dw70` 呈 `2^32 − δ`（δ 小）⇒ 必 ≥ 2^31。
- 附读数：`max(dw70)` / `min(dw70)` / 行数 / 打印序下 `dw70` 与相邻行 `w70` 差的形态描述。

### R1-b — 按 `t` 排序后链闭合率（期望 100%）+ 尾部对账

- **排序**：全部 READLOG 行按 `t` 升序（`t` = 锁内 commit 时刻 ⇒ 序 = 提交序）。
- **链判据式**（读法依据 = 工具 `print_readlog` 头注 B-1/R3 条，2026-10-13）：
  - 首行对基线（虚拟上一行 = ACCT 起点样本）：
    `(w70[0] − w70a) mod 2^32 == dw70[0]`；`(dma[0] − words0) mod 2^32 == ddma[0]`
  - 相邻行：`(w70[k] − w70[k−1]) mod 2^32 == dw70[k]`，k=1..n−1；dma 同款。
  - 闭合率 = 通过数 / n（含首行虚拟对）× 100%；**期望 100%**。
- **尾部对账（Σdw70 vs ACCT）**：
  `err = ΔW70 − Σdw70 − ((w70b − w70_last) mod 2^32)`，期望 **err == 0**
  （右项 = 末条 READLOG 采样 → ACCT 终样本之间的尾覆盖差；整体差额 ∈ {0, 尾覆盖差}）。
  dma 同款：`err2 = dwords − Σddma − ((words1 − dma_last) mod 2^32)`，期望 **err2 == 0**。
- ⚠️ **若出现异常就是 R1 要证的东西** —— 原样记录 + 保留 READLOG 原文；不涂改、不重跑挑数。

### R1-c — 与主臂同构窗并列（单窗，仅形态）

- 本窗 ΔW70 与 0x24 主臂 S0 的 **2,740,136 B**、11 窗分布（0.58–9.81 MB / 中位 2.41 MB /
  Σ36.85 MB —— 出处 `p9_board_0x24_20261013/REPORT.md` §3-5b）并列登记。
- **不作"更好/更坏"裁定**（单窗、无同会话 A/B、且 READLOG 口径与原主臂同源快照差分）。

## 前置/噪声见证（每条都记，缺一条按"未测"读）

- `TOOL_MD5`（窗口运行期现取）· `CARRIER_PRE` · Adaptive RX off / rx-usecs 0 ·
  发端 `PIN_CPU` / `SRC_RC` / `TOOL_RC` · `MIR_STREAM_DONE`（reads/partial/short/ended_early/read_error）·
  式A/式B（`closed_a`/`closed_b`）· `QUIESCE`（level_end/quiesced/premise_level0）。

## 分析器（判据的可执行化）

`_tools/r1_readlog_analyze.py` —— 本件判据的逐条实现（R1-a/b），**写于窗口运行之前**；
先用 0x24 主臂 S0 原文（`p9_board_0x24_20261013/runs/WIN_S0_*.txt`，旧工具）做**标定跑**：
标定预期 = 打印序链部分不闭合（历史见证 A1 126/253 同族形态）、按 `t` 排序 100% ——
即证明分析器对"链"这一维度**有判别力**（不是恒真）。
