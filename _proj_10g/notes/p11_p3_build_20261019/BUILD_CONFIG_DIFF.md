# 0x2F 构建配置 —— 待应用差异（草稿；审查/修复收口后应用）

> 只列**构建轮**需要改的行；不改 RTL 功能。所有行号现读（2026-10-19 01:5x）。

## 1. `board/wrapper_p4.v`
- **合同宏**（当前 `:412` 硬编码 8）：
  ```verilog
  `ifdef P11_EXPECTED_CONNS_2
      localparam integer P11_EXPECTED_CONNS = 2;
  `else
      localparam integer P11_EXPECTED_CONNS = 8;
  `endif
  ```
  默认 8 → C3/既有门零变化；0x2F 构建定义 `P11_EXPECTED_CONNS_2=1`（wq_cap = 0xC000）。
- **BID**（`:6173`）：`32'h0000002D` → **`32'h0000002F`**（注释：C4 双栈 2×10G；0x2E 留乙）。

## 2. `board/build_p7b_ku5p.tcl`
- `:333` 当前：
  ```
  ... SFP2_MODE_A=1 DUAL_SFP_A=1 P11_CFG_C3=1 P11_CFG_ENFORCE=1
  ```
  0x2F 改为：
  ```
  ... SFP2_MODE_A=1 DUAL_SFP_A=1 P11_CFG_C4=1 P11_CFG_ENFORCE=1 P11_DUAL=1 P11_HLS_ADV_WND=1 P11_EXPECTED_CONNS_2=1
  ```
  （`P11_HLS_ADV_WND=1` 仅在 P3 HLS 网表已就位时；当前 P3 网表已生成，176 文件，`i_tcp_adv_wnd` 在位。）
- HLS 网表路径不变：`hls/slowstack_prj/solution1/syn/verilog/*.v|*.dat`；`HLS_NET_HASH` 将随 P3 网表变化，构建归档。

## 3. 读侧 `apply_readside_bid1c.py`（阶段 ⑲）
- 新增 `EDITS_2F`：按 0x2D 阶段的 BID 替换模板，把所有 `0x0000002D` 现役默认改为 **`0x0000002F`**；
  几何**不变** = **85 字 / 0x184**（BID-only）。
- `GEOM_TIERS` 顶端新增：
  `"85|0x0000002F|61 62|P11 P3 C4 双栈 (2026-10-19) 85 字 / BID 0x2F (C4 双栈 2×10G; W79 = ch0 MAC 好帧; 几何同 0x2D; 未实现地址 0x184)"`
- `STAGES` 追加 `(0x2F, 85, 0x184, EDITS_2F)`；`--assert --bid 0x2F` 要求 `0x2D` 已落盘。
- W79 标签：`P7B_BIZ_WINDOW.md` / `p6e_snap_check.sh` 的标签从“merge 输入 FIFO 接受”改为
  “C4: ch0 MAC RX 好帧（与 W0 同计数点）”；`check_window.py` 已接受 `ch0_w79_frames` 两源名。
- 回溯：0x2D 阶段（88→85 显式增量）已存在；0x2F 不改几何，只加一行 85/0x2F。

## 4. 构建后
- 读回 `HLS_SRC_HASH`/`HLS_NET_HASH`、`P11_CONFIG=dual`、BID 0x2F。
- 资源/时序读数对照 `HLS_CSYNTH_READINGS.txt`（csynth Δ +4.3k LUT / +6.1k FF / +6 BRAM18K）。
- 若 WNS<0 或端点非 0：按 `BUILD_PLAN.md` backstop 阶梯（每档新输入），不重跑到过。
