`timescale 1ns/1ps
//=============================================================================
// app_rx_mirror.v — M1「载荷镜像」: snoop tap + 逐字节 ^XORC + 打包 64 位字 +
//                   跨域 FIFO (dp_clk → pcie axi) 的采集侧全链
//=============================================================================
// 设计件 = `_proj_10g/notes/P7B_PCIE_DATAPATH_DESIGN.md` (v1 §3.2/§3.7 + v2 §V1.1/§V1.3/§V1.4)。
// 用途: 把板上 app 收口 (现役接线 = UDP app RX 口 `app_udp_rx_*`) 的**载荷字节流**镜像出来,
//   → 逐字节变换 `^XORC` (默认 0xA5) → 压成 64 位字 → 异步 FIFO → 读侧拆 2×32 位字
//   (MIR_STATUS/MIR_DATA 读=弹出 / DMA 排空口 2 字/拍) → 主机侧工具落盘并与图案变换**逐字节对账**。
//
// ★ **snoop 合同 (第一优先级)**: 只采样 `s_tvalid && s_tready`, **永不驱动**任何握手信号
//   (s_tready 在本模块里是**只读**输入) ⇒ 对既有数据面逐位零影响。
//
// ⭐⭐ **写侧吞吐契约 (P8-STG 弹性暂存 2026-10-11 重写; 上一版 = 8 B **单槽** `pend`,
//   再上一版 = 4 B/拍 —— 见文末"旧契约"块)**:
//   · 新版 = **16 B 字节粒度弹性暂存** (`stg_data[127:0]` + `stg_cnt[4:0]`): 每拍把暂存头部的
//     `kk = min(8−acc_cnt, stg_cnt)` 个字节搬进累加器, **同一拍把源拍的 `n_b` 字节按字节粒度
//     追加到暂存尾部** ⇒ 源拍与累加器的 **1..7 B 错位 (相位 ≠ 0) 不再要求源拍让位**。
//   · ⚠️ **"结构吞吐类丢字节不可达"现在成立, 但前提必须逐条写清** (旧版那句话 (上一版
//     `:16-18`)"结构吞吐类丢字节对 ≤8 B/拍源不可达"的**范围说宽了**, 板级已实测: 旧单槽版
//     在相位 ≠0 时**恒丢 50%** —— 见 `_proj_10g/notes/p8_board_0x20_20261011/REPORT.md`):
//       ① **源一拍 ≤ 8 B** 且 keep 是**顶 n 连续** (合同见下);
//       ② **本模块对任意相位均可续接** (即"字节粒度追加"; 8 B 单槽版**不满足** ②);
//       ③ **未被 FIFO 满打停** (排空够快)。
//     ⇒ 真正剩下的丢字节来源 = **FIFO 满** (写空间不足) **+ `admit` 上限** (16 B 暂存装不下
//       当拍源拍 —— 正常态**结构上不可达**, 只在"满饱和期及其恢复沿"出现, 见下容量界)。
//   · **容量界 (设计件 §2.2 定理 1/2/3 + BFS 穷举复核)**:
//       · **正常态 `stg_cnt ≤ 15`** —— **紧界**: `phase = 7` 的可达轨迹 `(0,7) → (7,8) → (0,15)`
//         恰好达到追加需求 15; CAP=14 时该轨迹必丢 (模型实测), CAP=15 即可零丢。
//       · **FIFO 满饱和期可达 16** (= CAP, 由 `admit ⇔ keep + n_b ≤ 16` 规则封顶)。
//       · ⇒ **CAP = 16** = 128 位暂存的整数宽度 (1 B 裕量), **不多不少**。
//       · 满态**恢复沿** (变体 A): 释放那一拍仍可再丢 ≤1 拍源拍 (计入 `drop_bytes`, **不静默**)。
//   · ⚠️ **粒度随之变 8 字节** (旧版 4 字节): 输出字 = **64 位 = 2 个逻辑 32 位字**
//     (`[31:0]` = 先到的那个字)。发端总字节数 K 的**前置条件 = K % 8 == 0**;
//     尾部 1–7 B 会停在**暂存/累加器**里 (无读出通路) —— 与旧版 `<4 B` 同性质的**已知语义**,
//     不是缺陷。⚠️ **残余项口径位移 (P8-STG)**: 旧版残余 = `acc_cnt` (+ `pend`), 现为
//     **`acc_cnt_r + stg_cnt`** (0..24 B) —— 判据/工具侧的**身份式必须跟着改**, 否则假红/假绿。
//     字节账 (判据层): `offered == 8×(写入字数) + drop_bytes + (acc_cnt_r + stg_cnt)`。
//   · **无效位恒 0 (结构性不变式)**: `stg_data[127 : 8*stg_cnt] == 0` **恒成立** ——
//     源拍追加前先按 `n_b` 做字节掩码 (`nbmask`: 顶 n_b 字节为 1, 其余 0), 且"不追加"
//     分支灌 0 ⇒ 归纳可得 (不依赖任何时序巧合; TB 的 G20 直接断言它)。
//   · 读侧把 64 位拆回 2×32 位 ⇒ 下游 (`MIR_DATA` 读=弹出 / 环 `mir_dma_ring` 的逻辑字口径 /
//     工具的字节账) **逐字不变**; `MIR_STATUS.level` **单位仍是 32 位字** (见 `level` 注)。
//
// ⭐ 冻结语义 (v2; 偏离处就地登记):
//   · 字节序: `s_tdata[63:56]` = 该拍**首字节** (与 MAC/app 字流合同一致);
//     keep 合同 = **顶 n 字节有效** (0xFF<<(8-n); 与 `app_*.v` 的 kmask8/pop8 同款)。
//     ⛔ 非连续 keep (洞) **不在本合同内** (全仓两个生产者的 keep 都按此约定生成)。
//   · 变换: 只对有效字节做 `^XORC` (load 时整字异或 + `nbmask` 掩掉无效低字节 ——
//     无效字节的值既不进字节流、也不在暂存里留下垃圾位)。
//   · 打包: **跨拍/跨段续用累加器** (不在 tlast flush, v2 §V1.2) ⇒ 输出 = 纯字节流。
//   · 写门 = **组合** `wr_en = have && !full && cap_on` (v2 §V2-S6-④): 写使能是组合量时,
//     空间门必须用**本拍** `full` (用 full_next 才是错的) ⇒ 与 fifo_async 硬规则①一致。
//     ⚠️ **`&& cap_on` 是 P8 阶段三的第二个修复** (旧版漏了它): 旧版在
//        `cap_en=1 → 有一个整字被 FIFO 满握住 → cap_en=0` 这条序列上, 累加器被冻结
//        (acc_cnt 不回零) 而 `wr_en` 仍 = `have && !full` ⇒ FIFO 一有空位就把**同一个字**
//        反复写入 (最多 DEPTH 份)。本版把 `cap_on` 并进写门 ⇒ 冻结期**不写**,
//        被握住的字留在累加器里 (cap_en 回来再写) —— 与头注释"0 = 不写"逐字一致。
//   · 丢字节 `drop_bytes` (+1 bit sticky): **口径仍只有一类 = "当拍源拍进不了 FIFO 通路"**
//     (按字节计, **整拍拒收**、不部分接收, 与 PC 的字节账同量纲), 满足"不静默丢"。
//     该类在 P8-STG 下的两种形态: ① **FIFO 满** (字被握住写不进去, 暂存随后涨满);
//     ② **`admit` 上限** (`keep + n_b > 16`, 即暂存连当拍源拍都装不下) —— **正常态结构性
//     不可达** (定理 1), 只在满饱和期及其恢复沿出现。
//   · 使能 `cap_en`: 0 = 采集侧**整段冻结** (不暂存/不打包/不写/不计丢); FIFO 里已有
//     的字照常可读; `clr` 的冲刷/清零不受 cap_en 影响。
//     ⚠️ 中途关/开 cap_en 会让**暂存残余 + 累加器残余**跨过暂停拼进新流 ⇒ 正确用法 =
//        `clr` → `cap_en=1` 后**不再动**; 要重启就重走 `clr` (v2 §V1.3 的协议)。
//        **登记 (Q2 点名)**: 残余量 **正常态 ≤ 15 B** (满饱和冻结时 ≤ 16 B), 旧单槽版 ≤ 8 B
//        —— **性质不变、量变大**; 无下游按"≤8 B"设计 (无依赖)。
//   · `clr` (toggle): 写一次 ⇒ 跨到本域**恰好 1 个脉冲** (2FF + 沿检测) ⇒ 清 打包状态
//     (**暂存寄存器 `stg_data`/`stg_cnt`** + 累加器) + `any_drop` sticky (**按定义**:
//     被清掉的暂存/累加器残余字节算丢弃, 但**不计入 `drop_bytes`** —— 与旧版清 `pend`
//     残余同款, 登记口径); rd 域同步同一 toggle ⇒ 启动一次
//     **排空式冲刷** (读到空为止 —— 不碰 FIFO 复位, 遵守 fifo_async "两侧复位必须
//     同源同时断言"的硬契约)。`drop_bytes` (W70) **不归零** (v2 §V1.3 冻结清单未列它;
//     判据用 ΔW70, 不受影响 —— 登记口径)。
//   · 复位: 两侧都接板级 `reset_n` (P6B_SPEC §4.4 硬规则; 同 u_rxcdc/u_txcdc);
//     释放时刻不同步是允许的 (v2 §V2-S6-①)。空态哨兵由消费者按 `empty` 选路。
//   · `level` = **逻辑 32 位字**的可用数 = `2 × fifo_async.dbg_occ_r + stash_v`
//     (dbg_occ_r 是**读域 2FF 同步后的悲观占用** ⇒ 该式只少报、不多报 ⇒
//     "按 level 读若干字"不可能下溢 (v2 §V2-S6-③), 且不需要自造多比特 CDC)。
//     ⚠️ 9 位满量程 511 (< 2×256+1) ⇒ 顶端 **clamp 到 511** (仍只少报) —— 登记。
//
// ⚠️ 本模块**没有**自己的参数化宏开关: 例化与否由 wrapper 的三层 ifdef
//   (`APP_MODE` ∧ `PCIE_OBS` ∧ `DP_156MHZ`, v2 §V1.4) 决定。
//=============================================================================
module app_rx_mirror #(
    parameter [7:0] XORC = 8'hA5        // 逐字节变换常量 (可逆; PC 侧做同一个)
)(
    // ---- 采集侧 (dp_clk = 写域) ----
    input  wire        clk,             // dp_clk (156.25MHz 数据面)
    input  wire        rst_n,           // 采集侧复位 (板级 reset_n; 与 rd 侧**同源**)
    input  wire [63:0] s_tdata,         // snoop: 只读
    input  wire [7:0]  s_tkeep,         // snoop: 只读 (合同: 顶 n 字节有效)
    input  wire        s_tvalid,        // snoop: 只读
    input  wire        s_tready,        // snoop: **只读** (本模块从不驱动它)
    input  wire        s_tlast,         // snoop: 只读 (诊断保留; 打包**不**消费它)
    // ---- 控制 (pcie 域异步 → 本模块内部同步) ----
    input  wire        ctrl_cap_en,     // 电平 (2FF)
    input  wire        ctrl_clr_tgl,    // toggle (2FF + 沿检测 ⇒ 恰好 1 个 dp 脉冲)
    // ---- 读出侧 (rd_clk = pcie_axi_aclk ≈250MHz) ----
    input  wire        rd_clk,
    input  wire        rd_rst_n,        // 与采集侧同源 (板级 reset_n)
    input  wire        rd_en,           // 弹出 1 个逻辑字 (读=弹出; 由 axi_regs 与 !empty 同门给出)
    output wire [31:0] dout,            // FWFT 头逻辑字 (empty 时不定 —— 消费者按 empty 选哨兵)
    output wire        empty,
    output wire [8:0]  level,           // = 2*dbg_occ_r + stash_v (逻辑 32 位字; 见头注释)
    // ---- ⭐ 期 B (2026-10-11): 第二条读出口 = DMA 排空器 (与主机"读=弹出"**共享**同一读口) ----
    //   ⭐⭐ P8 阶段三: **本口 = 2 个逻辑字/拍** (旧版 = 1 字/拍) —— 8 B/拍源 ⇒ 1.25 GB/s,
    //   而 1 字/拍的出口上界只有 1 GB/s ⇒ 结构上不够 (新正判据"8 B/拍持续源 ⇒ drop==0"
    //   过不了)。现在的合同:
    //     · `dma_req` 拉高 + FIFO 非空 + 本拍主机没弹出 ⇒ `dma_gnt`=1, 同拍 `dma_data[63:0]`
    //       = **按序的下 2 个逻辑字** (`[31:0]` 先出, `[63:32]` 后出);
    //     · **主机弹出优先** (同时请求时 drainer 让位, 下拍重试);
    //     · 空态不弹 (`dma_gnt`=0)。
    //   ⇒ 环 (`mir_dma_ring`) 一拍写 2 个字, 写口 = 64 位 (语义: 逻辑字 L/L+1)。
    //   ⚠️ 语义边界 (登记): cap_en=1 且 dma_req 常高时, FIFO 被 drainer 持续抽干 ⇒ 主机侧
    //      `level`/`MIR_DATA` 读到的字与 drainer 抢同一队列 ⇒ **两条读出口不许混用**。
    //   ⚠️ **混用时的唯一停摆点 (登记)**: 主机先弹了 1 个字 (该 64 位字的低半) ⇒ 高半进 `stash`;
    //      此时若 FIFO 空, dma 口**弹不出成对的 2 字** (它不拆 stash 单走) ⇒ 停摆到 FIFO 再来字。
    //      ⇒ **不丢字** (字仍在 stash/FIFO 里, 主机侧照常可读, `level` 计着它), 但不是死锁
    //      (有主机读 / 有新数据即解)。挂 dma 单独用 (产品路径) 时 `stash_v` 恒 0 ⇒ 不停摆。
    input  wire        dma_req,         // pcie 域: 排空器请求 (推荐 = dma_en && 恒 1)
    output wire        dma_gnt,         // 1 拍: 本拍弹出了**2 个逻辑字** (dma_data 同拍有效)
    output wire [63:0] dma_data,        // ⭐ 新端口 (P8 阶段三): {后出的字, 先出的字}
    output wire        clr_pulse_rd,    // clr 的 rd 域脉冲 (→ DMA 环: 清计数/写指针)
    // ---- 观测 (dp 域寄存器输出 ⇒ 满足 snap_cdc 的 din_b 前提) ----
    output reg  [31:0] drop_bytes,      // 未进 FIFO 的字节数 (口径: 只剩 FIFO 满一类; 见头注释)
    output reg         any_drop,        // sticky (dp 域; clr 清)
    output wire        any_drop_rd      // any_drop 的 rd 域 2FF 电平同步版 (→ MIR_STATUS)
);

    // ---------------- 线网声明先行 (xvlog 先声明后用; 防隐式 1 位网 —— 工程坑 24) ----------------
    // ⚠️ 这几个**必须**在下面任何逻辑块之前声明: FIFO 的 full/empty/dout 被"写门"与
    //    读口引用, rd_go 被 FIFO 例化引用 —— 反过来写就是"引用后声明的标识符" ⇒
    //    xvlog 静默出隐式 1 位网 (multi/driv/unconnected 都不报), 写门直接失效。
    wire        fifo_full;
    wire        fifo_empty;
    wire [63:0] fifo_dout;
    wire [8:0]  fifo_occ_r;
    wire        rd_go;                  // FIFO 读使能 (冲刷优先于两条读出口; assign 在本文件末尾)
    // ---- 读侧拆分 (64 → 2×32; stash = 已弹出但后出的那个**高半**) ----
    reg         stash_v;                // stash 里有 1 个待出的逻辑字
    reg  [31:0] stash_d;
    wire [31:0] head_lo;                // FIFO 头 64 位字的低半 (= 先出的逻辑字)
    wire [31:0] head_hi;                // 高半 (= 后出的逻辑字)
    wire [31:0] dma_w0;                 // 本次 dma 弹出的**第 1 个**逻辑字 (先出)
    wire [31:0] dma_w1;                 // 第 2 个逻辑字
    wire        host_gnt_i;             // 主机弹出本拍成立
    wire        dma_gnt_i;              // DMA 弹出本拍成立

    // ---------------- 控制同步: pcie → dp ----------------
    (* ASYNC_REG = "TRUE" *) reg [1:0] cap_sr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) cap_sr <= 2'b00;
        else        cap_sr <= {cap_sr[0], ctrl_cap_en};
    end
    wire cap_on = cap_sr[1];

    // toggle → 沿检测 (3 级链: 2 级同步 + 1 级做沿比较) ⇒ 一次写恰好一个脉冲
    (* ASYNC_REG = "TRUE" *) reg [2:0] clrt_sr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) clrt_sr <= 3'd0;
        else        clrt_sr <= {clrt_sr[1:0], ctrl_clr_tgl};
    end
    wire clr_pulse = clrt_sr[2] ^ clrt_sr[1];

    // ---------------- 采集侧状态 (dp 域) ----------------
    // ⭐⭐ P8-STG (2026-10-11): 8 B 单槽 `pend` → **16 B 字节粒度弹性暂存**。
    //   `stg_data` 的**头部在 MSB 侧** (lane0 = `stg_data[127:120]` = 流的下一个字节);
    //   顶部 `stg_cnt` 个字节有效, **其余位结构上恒 0** (见头注释"无效位恒 0")。
    //   搬走侧 (`mv`/`acc_sh` 两表 + 写门 `wr_en`) **逐字不变** —— 只是 `b0..b7` 改从
    //   `stg_data` 头部取 (设计件 §4.1 的两个实现观察)。
    reg  [127:0] stg_data;       // 16 B 弹性暂存 (头部 = 流的下一个字节; 无效位恒 0)
    reg  [4:0]   stg_cnt;        // 0..16 (正常态 ≤15 / 满饱和 16 —— 容量界见头注释)
    reg  [63:0]  acc_r;          // 累加器 (64 位 = 2 个逻辑字): acc_r[7:0] = 本字**首字节**
    reg  [3:0]   acc_cnt_r;      // 0..8 (8 = 整字待写/等空间)

    // popcount(keep) —— 与 app_*.v 的 pop8 同款 (4 位: 0..8)
    function [3:0] pop8; input [7:0] k; integer i; begin
        pop8 = 4'd0;
        for (i = 0; i < 8; i = i + 1) pop8 = pop8 + k[i];
    end endfunction

    wire       src_beat  = s_tvalid && s_tready && cap_on;        // 被接受的拍 (snoop)
    wire [3:0] n_b       = src_beat ? pop8(s_tkeep) : 4'd0;       // 当拍源字节数 (0..8)
    wire [3:0] room      = 4'd8 - acc_cnt_r;                      // 累加器还能吃几个字节
    wire [3:0] sc4       = (stg_cnt >= 5'd8) ? 4'd8 : stg_cnt[3:0]; // min(stg_cnt, 8)
    wire [3:0] kk        = (sc4 < room) ? sc4 : room;             // 本拍搬 kk 个字节 (0..8)
    wire [4:0] keep      = stg_cnt - {1'b0, kk};                  // 搬走后留在暂存的字节数 (0..16)
    wire       admit     = src_beat && (keep + {1'b0, n_b} <= 5'd16); // ⭐ 追加能否装下 (CAP=16)
    wire       drop_now  = src_beat && !admit;                    // 拒收 (按字节计; 正常态不可达)
    wire [3:0] acc_have  = acc_cnt_r + kk;
    wire       have      = (acc_have == 4'd8);                    // 本拍凑满一个 64 位字
    wire       wr_en     = have && !fifo_full && cap_on;          // 冻结写门 (组合 + 本拍 full + cap_on)

    // 源拍有效性掩码 (顶 n_b 字节) —— 追加前先把无效低字节清零 ⇒ 暂存无效位恒 0
    // (与 app_*.v 的 bmask64/kmask8 同款; 无这一层时无效字节会以**垃圾值**残留在无效位上)
    reg [63:0] nbmask;
    always @* begin
        case (n_b)
            4'd0:    nbmask = 64'd0;
            4'd1:    nbmask = 64'hFF00000000000000;
            4'd2:    nbmask = 64'hFFFF000000000000;
            4'd3:    nbmask = 64'hFFFFFF0000000000;
            4'd4:    nbmask = 64'hFFFFFFFF00000000;
            4'd5:    nbmask = 64'hFFFFFFFFFF000000;
            4'd6:    nbmask = 64'hFFFFFFFFFFFF0000;
            4'd7:    nbmask = 64'hFFFFFFFFFFFFFF00;
            default: nbmask = 64'hFFFFFFFFFFFFFFFF;
        endcase
    end
    wire [63:0] xbeat = (s_tdata ^ {8{XORC}}) & nbmask;           // 变换 + 有效字节掩码

    // 暂存头部八字节 (b0 = 首字节 = `stg_data[127:120]`) —— 名字与旧版**同名** ⇒ `mv`/`acc_sh` 两表逐字不变
    wire [7:0]  b0 = stg_data[127:120];
    wire [7:0]  b1 = stg_data[119:112];
    wire [7:0]  b2 = stg_data[111:104];
    wire [7:0]  b3 = stg_data[103:96];
    wire [7:0]  b4 = stg_data[95:88];
    wire [7:0]  b5 = stg_data[87:80];
    wire [7:0]  b6 = stg_data[79:72];
    wire [7:0]  b7 = stg_data[71:64];           // ⚠️ lane7 = [71:64] (lane i = [127-8i -: 8])

    // mv = 本拍搬走的 kk 个字节 (b0 在 LSB, 即"首字节落在低位") —— 显式 case, 不用变量移位
    reg [63:0] mv;
    always @* begin
        case (kk)
            4'd0:    mv = 64'd0;
            4'd1:    mv = {56'd0, b0};
            4'd2:    mv = {48'd0, b1, b0};
            4'd3:    mv = {40'd0, b2, b1, b0};
            4'd4:    mv = {32'd0, b3, b2, b1, b0};
            4'd5:    mv = {24'd0, b4, b3, b2, b1, b0};
            4'd6:    mv = {16'd0, b5, b4, b3, b2, b1, b0};
            4'd7:    mv = {8'd0,  b6, b5, b4, b3, b2, b1, b0};
            default: mv = {b7, b6, b5, b4, b3, b2, b1, b0};
        endcase
    end
    // acc_sh = mv 上移到累加器当前顶端 (acc_cnt_r ∈ 0..7; ==8 时无空位 ⇒ 0)
    reg [63:0] acc_sh;
    always @* begin
        case (acc_cnt_r)
            4'd0:    acc_sh = mv;
            4'd1:    acc_sh = {mv[55:0], 8'd0};
            4'd2:    acc_sh = {mv[47:0], 16'd0};
            4'd3:    acc_sh = {mv[39:0], 24'd0};
            4'd4:    acc_sh = {mv[31:0], 32'd0};
            4'd5:    acc_sh = {mv[23:0], 40'd0};
            4'd6:    acc_sh = {mv[15:0], 48'd0};
            4'd7:    acc_sh = {mv[7:0],  56'd0};
            default: acc_sh = 64'd0;
        endcase
    end
    wire [63:0] acc_next = acc_r | acc_sh;

    // 暂存整体前移 kk 字节 (**搬走头部** kk 字节 ⇒ 剩下的 `keep` 字节重新头部对齐) —— 9 路 case
    reg [127:0] stg_ret;
    always @* begin
        case (kk)
            4'd0:    stg_ret = stg_data;
            4'd1:    stg_ret = {stg_data[119:0], 8'd0};
            4'd2:    stg_ret = {stg_data[111:0], 16'd0};
            4'd3:    stg_ret = {stg_data[103:0], 24'd0};
            4'd4:    stg_ret = {stg_data[95:0],  32'd0};
            4'd5:    stg_ret = {stg_data[87:0],  40'd0};
            4'd6:    stg_ret = {stg_data[79:0],  48'd0};
            4'd7:    stg_ret = {stg_data[71:0],  56'd0};
            4'd8:    stg_ret = {stg_data[63:0],  64'd0};
            default: stg_ret = 128'd0;                          // kk ∈ 0..8 ⇒ 不可达 (防御)
        endcase
    end
    // 源拍顶 n_b 字节贴到 `keep` 之后的尾部 (= {xbeat,64'd0} >> 8*keep; 17 路 case)
    reg [127:0] beat_pl;
    always @* begin
        case (keep)
            5'd0:  beat_pl = {xbeat[55:0], xbeat[63:56], 64'd0};   // MUTANT mut_apos0: keep=0 档尾部错位
            5'd1:  beat_pl = {8'd0,  xbeat, 56'd0};
            5'd2:  beat_pl = {16'd0, xbeat, 48'd0};
            5'd3:  beat_pl = {24'd0, xbeat, 40'd0};
            5'd4:  beat_pl = {32'd0, xbeat, 32'd0};
            5'd5:  beat_pl = {40'd0, xbeat, 24'd0};
            5'd6:  beat_pl = {48'd0, xbeat, 16'd0};
            5'd7:  beat_pl = {56'd0, xbeat, 8'd0};
            5'd8:  beat_pl = {64'd0, xbeat};
            5'd9:  beat_pl = {72'd0, xbeat[63:8]};
            5'd10: beat_pl = {80'd0, xbeat[63:16]};
            5'd11: beat_pl = {88'd0, xbeat[63:24]};
            5'd12: beat_pl = {96'd0, xbeat[63:32]};
            5'd13: beat_pl = {104'd0, xbeat[63:40]};
            5'd14: beat_pl = {112'd0, xbeat[63:48]};
            5'd15: beat_pl = {120'd0, xbeat[63:56]};
            5'd16: beat_pl = 128'd0;                            // keep=16 ⇒ 只有 n_b=0 才能 admit
            default: beat_pl = 128'd0;
        endcase
    end
    // lane 合并 (**掩码表达式**): i < keep 保留暂存剩余字节; 否则接源拍 (不接收 ⇒ 灌 0)。
    //   `keep_bmask` = 顶 keep 个字节为 1 的字节掩码 (由 `keep_msk` 每比特扩 8 位)。
    //   ⚠️ 2026-10-11 实现注记 (实测): 最初写成 `generate for` + 逐 lane 三元式
    //      `(gi < keep) ? stg_ret[8*gi +: 8] : …`, **xsim 里该结构取不到当拍的 `stg_ret`**
    //      (定向 dump: keep=4 / stg_ret=04050607… 都对, 而 stg_next 恒 = beat_pl ⇒
    //      "gi < keep" 分支从未被选中) —— 换成本式后同一激励下逐拍正确 (机理未定位, 只登记)。
    //      ⇒ 本式与逐 lane 三元式**语义逐位相同** (mask=1 处取 stg_ret, =0 处取 beat_pl/0)。
    wire [15:0]  keep_msk  = (16'd1 << keep) - 16'd1;   // keep 个低位为 1 (keep=16 ⇒ 0xFFFF)
    wire [127:0] keep_bmask = {{8{keep_msk[0]}},  {8{keep_msk[1]}},  {8{keep_msk[2]}},  {8{keep_msk[3]}},
                               {8{keep_msk[4]}},  {8{keep_msk[5]}},  {8{keep_msk[6]}},  {8{keep_msk[7]}},
                               {8{keep_msk[8]}},  {8{keep_msk[9]}},  {8{keep_msk[10]}}, {8{keep_msk[11]}},
                               {8{keep_msk[12]}}, {8{keep_msk[13]}}, {8{keep_msk[14]}}, {8{keep_msk[15]}}};
    wire [127:0] stg_next = (stg_ret & keep_bmask) | (admit ? (beat_pl & ~keep_bmask) : 128'd0);

    // ---- 打包状态推进 (单驱动块; clr 优先于一切) ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stg_data <= 128'd0; stg_cnt <= 5'd0;
            acc_r <= 64'd0; acc_cnt_r <= 4'd0;
        end else if (clr_pulse) begin
            stg_data <= 128'd0; stg_cnt <= 5'd0;
            acc_r <= 64'd0; acc_cnt_r <= 4'd0;
        end else if (cap_on) begin
            stg_data <= stg_next;
            stg_cnt  <= keep + (admit ? {1'b0, n_b} : 5'd0);    // ⭐ 容量界: ≤16
            if (wr_en) begin
                acc_r <= 64'd0; acc_cnt_r <= 4'd0;          // 整字被 FIFO 收下
            end else if (kk != 4'd0) begin
                acc_r <= acc_next; acc_cnt_r <= acc_have;   // (含 have=1 但 full=1 的"握字等空间")
            end
        end
    end

    // ---- 丢字节计数 + sticky (dp 域; 单驱动块) ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            drop_bytes <= 32'd0; any_drop <= 1'b0;
        end else if (clr_pulse) begin
            any_drop <= 1'b0;                    // 只清 sticky; drop_bytes 不归零 (登记口径)
        end else if (drop_now) begin
            drop_bytes <= drop_bytes + {28'd0, pop8(s_tkeep)};
            any_drop   <= 1'b1;
        end
    end

    // ---------------- 跨域 FIFO (64 位 × 256, FWFT) ----------------
    // ⭐ P8 阶段三: WIDTH 32→**64** (一拍收满 8 B), DEPTH 256 不变 ⇒ 缓冲 2 KB (旧 1 KB),
    //   深度取 256 是为了吸收"帧级突发"(app 播放器一帧 ~1472 B 连续 8 B/拍), 也为了让
    //   BAR 路径 (主机轮询, 无 drainer) 能整帧入缓冲。AW 必须跟着 DEPTH (参数自检会死)。
    // ⚠️ 探针端口逐条接全 (未接的端口 = 悬空; 本工程要求"要么接要么显式空接"—— 见下 ovf)。
    fifo_async #(.WIDTH(64), .DEPTH(256), .FWFT(1), .AW(8)) u_fifo (
        .wr_clk   (clk),
        .wr_rst_n (rst_n),
        .wr_en    (wr_en),
        .din      (acc_next),
        .full     (fifo_full),
        .rd_clk   (rd_clk),
        .rd_rst_n (rd_rst_n),
        .rd_en    (rd_go),
        .dout     (fifo_dout),
        .empty    (fifo_empty),
        .dbg_wbin (), .dbg_rbin (), .dbg_wgray (), .dbg_rgray (),
        .dbg_occ_w(), .dbg_occ_r(fifo_occ_r),
        .ovf_pulse(), .ovf_cnt()      // v2 §V2-S6-⑤: 不接 ovf (自算 drop_bytes; 拒写不再静默)
    );

    // ---------------- rd 域: 冲刷 (先声明/驱动 —— 下面的拆分逻辑引用它) ----------------
    // clr → 排空式冲刷: 把 FIFO 里已有的字全部读出丢弃 (到空为止)。
    // ⚠️ 不碰 FIFO 复位 (单侧复位 = 禁止用法); 冲刷期间若写侧还在灌, 冲刷会持续到
    //    追上空 (协议上 clr 之后才开 cap_en, 正常不会)。
    (* ASYNC_REG = "TRUE" *) reg [2:0] clrt_sr_r;
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) clrt_sr_r <= 3'd0;
        else           clrt_sr_r <= {clrt_sr_r[1:0], ctrl_clr_tgl};
    end
    wire clr_pulse_r = clrt_sr_r[2] ^ clrt_sr_r[1];

    reg flush_r;
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n)                       flush_r <= 1'b0;
        else if (clr_pulse_r)                flush_r <= 1'b1;
        else if (flush_r && fifo_empty)      flush_r <= 1'b0;
    end

    // ---------------- rd 域: 64 → 2×32 拆分 (stash) ----------------
    // 逻辑字流 = 把 FIFO 的每个 64 位字按 [31:0] → [63:32] 顺序展开。
    //   · 主机口: `stash_v=0` ⇒ 出低半 + 把高半存进 stash (本拍弹掉整个 64 位字);
    //             `stash_v=1` ⇒ 只出 stash (本拍**不弹** FIFO)。
    //   · DMA 口: 一次 `dma_gnt` 出 2 个字 (见端口注): `stash_v=1` ⇒ {stash, 低半} (弹 1 个
    //             64 位字, 高半继续留在 stash); `stash_v=0` ⇒ {低半, 高半} (弹 1 个字)。
    //             ⇒ **两种情形下 stash_v 都不变**, 且**顺序恒等于逻辑字流**。
    //   · 冲刷期 (flush_r) 只走整字弹出 + stash 清零 (不看门, 不拆半)。
    assign head_lo = fifo_dout[31:0];
    assign head_hi = fifo_dout[63:32];
    assign dout    = stash_v ? stash_d : head_lo;
    assign empty   = !stash_v && fifo_empty;
    assign dma_w0  = stash_v ? stash_d  : head_lo;    // 先出的字
    assign dma_w1  = stash_v ? head_lo  : head_hi;    // 后出的字
    assign dma_data = {dma_w1, dma_w0};
    // ⭐ 仲裁 (与阶段一/期 B 逐条同形): 冲刷 > 主机弹出 > DMA 排空器。
    //   ⚠️ `rd_en` (= mir_pop) 在 axi_regs 侧本就与 `!empty` 同门 (v2 §V1.1 TL 硬要求),
    //      这里把同一条件写实 ⇒ 未接线时 (dma_req=0) 逐位等价于阶段一。
    assign host_gnt_i = rd_en && !empty;
    assign dma_gnt_i  = dma_req && !fifo_empty && !rd_en && !flush_r;
    assign dma_gnt    = dma_gnt_i;
    assign rd_go = flush_r ? !fifo_empty : ((host_gnt_i && !stash_v) || dma_gnt_i);

    // stash 推进 (rd 域; 单驱动块)
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            stash_v <= 1'b0; stash_d <= 32'd0;
        end else if (clr_pulse_r || flush_r) begin
            stash_v <= 1'b0; stash_d <= 32'd0;              // clr/冲刷 ⇒ 半字也不留
        end else if (host_gnt_i) begin
            if (stash_v) stash_v <= 1'b0;                   // 消费 stash (本拍不弹 FIFO)
            else begin stash_v <= 1'b1; stash_d <= head_hi; end
        end else if (dma_gnt_i && stash_v) begin
            stash_d <= head_hi;                             // 成对搬走后高半接着进 stash
        end
    end

    // `level` = 逻辑 32 位字可用数 (悲观口径; 见头注释)。9 位满量程 clamp (只少报)。
    wire [9:0] lev10 = {fifo_occ_r, 1'b0} + {9'd0, stash_v};
    assign level = lev10[9] ? 9'h1FF : lev10[8:0];

    // ---------------- rd 域: clr 脉冲引出 + any_drop 电平同步 ----------------
    // ⭐ 期 B: `clr` 的 rd 域脉冲引出 (给 DMA 环: 清零字计数器 + 写指针 ⇒ "逻辑字 0" 从这一刻起算)
    assign clr_pulse_rd = clr_pulse_r;

    (* ASYNC_REG = "TRUE" *) reg [1:0] adrop_sr;
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) adrop_sr <= 2'd0;
        else           adrop_sr <= {adrop_sr[0], any_drop};   // any_drop 是 sticky 电平 ⇒ 不会漏
    end
    assign any_drop_rd = adrop_sr[1];

endmodule

//=============================================================================
// 变更登记 (P8-STG, 2026-10-11; 设计件 `_proj_10g/notes/p8_mir_stg_20261011/DESIGN.md`):
//   · 采集侧暂存: 8 B 单槽 `pend_valid/pend_data/pend_keep` → **16 B 字节粒度
//     `stg_data[127:0]` + `stg_cnt[4:0]`**; 新增 `sc4/keep/admit/nbmask/stg_ret/beat_pl/stg_next`。
//   · **逐字不变** 的三处: `mv` 表、`acc_sh` 表、写门 `wr_en = have && !fifo_full && cap_on`;
//     以及**端口表、读侧、FIFO、`level`、`drop_bytes` 口径** (下游语义 0 改动)。
//   · **口径位移** (判据/工具侧要跟): 残余项 `acc_cnt_r` → `acc_cnt_r + stg_cnt`。
//   · 设计件 §4.1 草图的 `beat_pl` 直接用未掩码的 `xbeat` ⇒ 无效低字节会以垃圾值留在
//     无效位上 (设计件 §2.1-② 声称的"无效位恒 0"在草图上**不成立**)。本实现补一层
//     `nbmask` (顶 n_b 字节掩码) ⇒ 该不变式成立、G20 结构性断言有牙。见 IMPL_REPORT 口径声明。
//=============================================================================
// 旧契约 (P8 阶段三之前; **已作废**, 逐字留档 —— 板级实测它就是恒丢 50% 的那条):
//   · 打包: 压成 **32 位字** (写口 32 位) + 跨拍累加器 4 B/拍;
//   · drop_bytes 两类: ① 暂存忙 —— 源一拍最多 8B, 而 FIFO 写口 = 32 位 ⇒ 持续采集上限
//     = **4B/拍** (156.25MHz ⇒ 625MB/s); 源平均速率 > 4B/拍时, 多出的拍被拒收;
//     ② FIFO 满 (排空不够快)。
//   ⇒ 对 8 B/拍连续源: 收、丢、收、丢… (恰好 50%)。板级读数 (p8_board_20261011/REPORT.md §9,
//     位流 0x1F): 丢字恒 = 采集量一半 / 偶数组全收奇数组全丢 / first_mismatch 恒 8。
//   · 前置条件 K % 4 == 0 (现为 K % 8 == 0)。
//   ⚠️ 中间还有一版 **8 B 单槽 `pend`** (位流 0x20; 写口 64 位, 但暂存只有 1 个 8 B 槽 ⇒
//     相位 ≠ 0 时"新拍必须等本拍把暂存整块搬空"才收 ⇒ 恒丢 50% 的变体; 板级臂 B
//     `--paylen 1470` 实测 `ΔW70 = 750,882 B = K 的 49.883%`)。本版 = 它的替代。
//=============================================================================
