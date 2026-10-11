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
// ⭐⭐ **写侧吞吐契约 (P8 阶段三 2026-10-11 重写; 旧版 = 4 B/拍, 见文末"旧契约"块)**:
//   · **源一拍最多 8 B ⇒ 本模块一拍吸收 8 B** (暂存 64 位 + 累加器 64 位, 一拍搬 0..8 B,
//     凑满 8 B 即写一个字)。⇒ **"结构吞吐类"丢字节对 ≤8 B/拍的源不可达**;
//     唯一剩下的丢字节来源 = **② FIFO 满** (排空不够快)。故本版**删掉**旧版的
//     "①暂存忙/结构吞吐上限"那一类 (板级实测: 旧版对 8 B/拍源恒丢 50%)。
//   · ⚠️ **粒度随之变 8 字节** (旧版 4 字节): 输出字 = **64 位 = 2 个逻辑 32 位字**
//     (`[31:0]` = 先到的那个字)。发端总字节数 K 的**前置条件 = K % 8 == 0**;
//     尾部 1–7 B 会停在累加器里 (无读出通路) —— 与旧版 `<4 B` 同性质的**已知语义**, 不是缺陷。
//     字节账 (判据层): `offered == 8×(写入字数) + drop_bytes + 累加器残余`。
//   · 读侧把 64 位拆回 2×32 位 ⇒ 下游 (`MIR_DATA` 读=弹出 / 环 `mir_dma_ring` 的逻辑字口径 /
//     工具的字节账) **逐字不变**; `MIR_STATUS.level` **单位仍是 32 位字** (见 `level` 注)。
//
// ⭐ 冻结语义 (v2; 偏离处就地登记):
//   · 字节序: `s_tdata[63:56]` = 该拍**首字节** (与 MAC/app 字流合同一致);
//     keep 合同 = **顶 n 字节有效** (0xFF<<(8-n); 与 `app_*.v` 的 kmask8/pop8 同款)。
//     ⛔ 非连续 keep (洞) **不在本合同内** (全仓两个生产者的 keep 都按此约定生成)。
//   · 变换: 只对有效字节做 `^XORC` (load 时整字异或即可 —— 无效字节的值永不进入字节流)。
//   · 打包: **跨拍/跨段续用累加器** (不在 tlast flush, v2 §V1.2) ⇒ 输出 = 纯字节流。
//   · 写门 = **组合** `wr_en = have && !full && cap_on` (v2 §V2-S6-④): 写使能是组合量时,
//     空间门必须用**本拍** `full` (用 full_next 才是错的) ⇒ 与 fifo_async 硬规则①一致。
//     ⚠️ **`&& cap_on` 是 P8 阶段三的第二个修复** (旧版漏了它): 旧版在
//        `cap_en=1 → 有一个整字被 FIFO 满握住 → cap_en=0` 这条序列上, 累加器被冻结
//        (acc_cnt 不回零) 而 `wr_en` 仍 = `have && !full` ⇒ FIFO 一有空位就把**同一个字**
//        反复写入 (最多 DEPTH 份)。本版把 `cap_on` 并进写门 ⇒ 冻结期**不写**,
//        被握住的字留在累加器里 (cap_en 回来再写) —— 与头注释"0 = 不写"逐字一致。
//   · 丢字节 `drop_bytes` (+1 bit sticky): **只剩 FIFO 满一类** (按字节计, 与 PC 的字节账
//     同量纲), 满足"不静默丢"。旧版头注释里的 "①暂存忙 (4 B/拍结构上限)" 已随本版删除。
//   · 使能 `cap_en`: 0 = 采集侧**整段冻结** (不暂存/不打包/不写/不计丢); FIFO 里已有
//     的字照常可读; `clr` 的冲刷/清零不受 cap_en 影响。
//     ⚠️ 中途关/开 cap_en 会让累加器残余**跨过暂停**拼进新流 ⇒ 正确用法 = `clr` → `cap_en=1`
//        后**不再动**; 要重启就重走 `clr` (v2 §V1.3 的协议)。
//   · `clr` (toggle): 写一次 ⇒ 跨到本域**恰好 1 个脉冲** (2FF + 沿检测) ⇒ 清 打包状态
//     (暂存寄存器 + 累加器) + `any_drop` sticky; rd 域同步同一 toggle ⇒ 启动一次
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
    reg        pend_valid;
    reg [63:0] pend_data;        // 已 ^XORC 的源字 (无效字节的值永不使用)
    reg [7:0]  pend_keep;
    reg [63:0] acc_r;            // 累加器 (64 位 = 2 个逻辑字): acc_r[7:0] = 本字**首字节**
    reg [3:0]  acc_cnt_r;        // 0..8 (8 = 整字待写/等空间)

    // popcount(keep) —— 与 app_*.v 的 pop8 同款 (4 位: 0..8)
    function [3:0] pop8; input [7:0] k; integer i; begin
        pop8 = 4'd0;
        for (i = 0; i < 8; i = i + 1) pop8 = pop8 + k[i];
    end endfunction

    wire [3:0] n_cur     = pend_valid ? pop8(pend_keep) : 4'd0;   // 暂存里的有效字节数 (0..8)
    wire [3:0] room      = 4'd8 - acc_cnt_r;                      // 累加器还能吃几个字节
    wire [3:0] kk        = (n_cur < room) ? n_cur : room;         // 本拍搬 kk 个字节 (0..8)
    wire       drain_all = (kk == n_cur);                         // 本拍把暂存整块取走
    wire       pend_after = pend_valid && !drain_all;
    wire       src_beat  = s_tvalid && s_tready && cap_on;        // 被接受的拍 (snoop)
    wire       load      = src_beat && !pend_after;               // 收进暂存
    wire       drop_now  = src_beat && pend_after;                // 拒收 (按字节计)
    wire [3:0] acc_have  = acc_cnt_r + kk;
    wire       have      = (acc_have == 4'd8);                    // 本拍凑满一个 64 位字
    wire       wr_en     = have && !fifo_full && cap_on;          // 冻结写门 (组合 + 本拍 full + cap_on)

    // 源字八字节 (b0 = 首字节)
    wire [7:0]  b0 = pend_data[63:56];
    wire [7:0]  b1 = pend_data[55:48];
    wire [7:0]  b2 = pend_data[47:40];
    wire [7:0]  b3 = pend_data[39:32];
    wire [7:0]  b4 = pend_data[31:24];
    wire [7:0]  b5 = pend_data[23:16];
    wire [7:0]  b6 = pend_data[15:8];
    wire [7:0]  b7 = pend_data[7:0];

    // mv = 本拍搬走的 kk 个字节 (b0 在 LSB, 即"首字节落在低位") —— 显式 case, 不用变量移位
    reg [63:0] mv;
    always @* begin
        case (kk)
            4'd0:    mv = 64'd0;
            4'd1:    mv = {56'd0, b0};
            4'd2:    mv = {48'd0, b0, b1};   // MUTANT mut_order: b0/b1 swapped
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

    // 暂存移位 (搬走 kk 个字节) —— 显式 case
    reg [63:0] pend_sh;
    reg [7:0]  keep_sh;
    always @* begin
        case (kk)
            4'd0:    begin pend_sh = pend_data;                keep_sh = pend_keep;               end
            4'd1:    begin pend_sh = {pend_data[55:0], 8'd0};  keep_sh = {pend_keep[6:0], 1'b0};  end
            4'd2:    begin pend_sh = {pend_data[47:0], 16'd0}; keep_sh = {pend_keep[5:0], 2'b0};  end
            4'd3:    begin pend_sh = {pend_data[39:0], 24'd0}; keep_sh = {pend_keep[4:0], 3'b0};  end
            4'd4:    begin pend_sh = {pend_data[31:0], 32'd0}; keep_sh = {pend_keep[3:0], 4'b0};  end
            4'd5:    begin pend_sh = {pend_data[23:0], 40'd0}; keep_sh = {pend_keep[2:0], 5'b0};  end
            4'd6:    begin pend_sh = {pend_data[15:0], 48'd0}; keep_sh = {pend_keep[1:0], 6'b0};  end
            4'd7:    begin pend_sh = {pend_data[7:0],  56'd0}; keep_sh = {pend_keep[0],   7'b0};  end
            default: begin pend_sh = 64'd0;                    keep_sh = 8'd0;                    end
        endcase
    end

    // ---- 打包状态推进 (单驱动块; clr 优先于一切) ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pend_valid <= 1'b0; pend_data <= 64'd0; pend_keep <= 8'd0;
            acc_r <= 64'd0; acc_cnt_r <= 4'd0;
        end else if (clr_pulse) begin
            pend_valid <= 1'b0; pend_data <= 64'd0; pend_keep <= 8'd0;
            acc_r <= 64'd0; acc_cnt_r <= 4'd0;
        end else if (cap_on) begin
            if (load) begin
                pend_valid <= 1'b1;
                pend_data  <= s_tdata ^ {8{XORC}};
                pend_keep  <= s_tkeep;
            end else if (pend_valid) begin
                if (drain_all) pend_valid <= 1'b0;
                else begin pend_data <= pend_sh; pend_keep <= keep_sh; end
            end
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
// 旧契约 (P8 阶段三之前; **已作废**, 逐字留档 —— 板级实测它就是恒丢 50% 的那条):
//   · 打包: 压成 **32 位字** (写口 32 位) + 跨拍累加器 4 B/拍;
//   · drop_bytes 两类: ① 暂存忙 —— 源一拍最多 8B, 而 FIFO 写口 = 32 位 ⇒ 持续采集上限
//     = **4B/拍** (156.25MHz ⇒ 625MB/s); 源平均速率 > 4B/拍时, 多出的拍被拒收;
//     ② FIFO 满 (排空不够快)。
//   ⇒ 对 8 B/拍连续源: 收、丢、收、丢… (恰好 50%)。板级读数 (p8_board_20261011/REPORT.md §9,
//     位流 0x1F): 丢字恒 = 采集量一半 / 偶数组全收奇数组全丢 / first_mismatch 恒 8。
//   · 前置条件 K % 4 == 0 (现为 K % 8 == 0)。
//=============================================================================
