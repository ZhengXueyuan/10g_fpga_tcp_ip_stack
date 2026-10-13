# C 捆审查：0x24 构建面（快审）

**审查方**：Kimi 组（跨组对抗审查，owner 指派 `t_9b6fd090aff1`）
**日期**：2026-10-13 · **对象 commit**：`09e34a6`（构建 0x24 一次收口）· **方法**：git show 逐面核验 + 现行文件交叉验证

## 结论（不下 PASS/FAIL 裁定）

**本捆未发现 P0/P1/P2 级发现（覆盖面 = 提交 09e34a6 的三个声明面 + 交叉验证，不含构建内部流程）**。
三项报备声明逐条核验全部吻合，交叉验证无异常。

## 逐条核验（可复算）

### 1. `board/build_p7b_ku5p.tcl` +1 行导入 —— 吻合

`git show 09e34a6 -- board/build_p7b_ku5p.tcl`：功能性改动恰为 +1 行
（`${root_dir}/rtl/mir_uram_fifo.v` 挂入 read_verilog 清单，续 `axis_c2h_stream.v` 之后），
外加 4 行 ⚠️ 注释说明「缺它 = u_mir_buf 黑盒静默失效」与加件先例（173b18d）。
现行文件核：`grep -n 'mir_uram_fifo.v' board/build_p7b_ku5p.tcl` = 2 命中 = 1 行导入（:101）+ 1 行注释（:102），**无重复导入**。

### 2. `sim/p6e_pcie/mut_bwire.py` 锚点重对 —— 吻合且现行有效

- 旧锚点 `.src_data (mir_dma_data)` 在 173b18d 随旧例化整体删除（mut_bwire.py:17 自述，与 `git log -S` 口径一致）。
- 新锚点（mut_bwire.py:34）= `.dma_data       (mir_dma_data),       // ← 64 位 = {后出, 先出} (缓冲 FWFT 头字)`，
  与现行 `board/wrapper_p4.v:3894` **逐字一致**；同文件另有 3912/3931 两行 `wire mir_dma_data = 64'd0`（其他分支常量），
  不匹配锚点形态 ⇒ 工具自带 `anchor_hits==1` 自检（:46-48）在现行文件上**应恰命中 1**。
- 突变语义不变性声明（计数器照涨、只内容判据翻红）与锚点位置（数据线而非请求线）一致。

### 3. `board/wrapper_p4.v` BID 0x23→0x24 非注释行恰 1 —— 吻合

`git show 09e34a6 -- board/wrapper_p4.v` 去注释后功能性改动恰 1 行：
`.BUILD_ID_V (32'h00000023)` → `32'h00000024`（:3866 区域）。无夹带。

## 覆盖面声明

看了：提交 09e34a6 的 diff 全文（三个面）、现行 tcl/wrapper/mut_bwire 交叉验证。
**没看**：Vivado 构建过程本身（⛔ 不碰 Vivado）、矩阵 17/17 FROZEN 与门读数的重算（属 A 捆门质量面/独立复跑件）。
C 捆为快审定位，以上未发现不等于构建面无问题，构建正确性以 A 捆与复跑件为准。
