`timescale 1ns/1ps
//=============================================================================
// slow_demux2.v — P11 P3 (C4): 慢路径 HLS TX 1:2 端口分离
//=============================================================================
// 设计件 §6.3: `slow_tx_adp` 已输出帧内稳定的 `o_port` (源 IP 提取), 本模块
// 按帧把 73 位 AXIS (tdata/tkeep/tlast) 分到两口各自的 arb 树。
//
// 【帧原子】帧首被接受拍锁存 s_port -> port_r, 帧内一律用 port_r 选口 ——
//   即使生产者在帧中改变 s_port, 本帧也不会跨口分裂 (stat_port_change 计该
//   违规, 应恒 0; 生产者侧另有逐拍断言)。
// 【反压】纯组合 mux, 零缓冲: 选中口的 tready 回传, 未选中口 tvalid=0。
//
// 注: 与快速路径 tx_demux2 **分离成独立模块** (设计件 §14.2-4 的实例计数门
// 按模块名区分快/慢件; 不复用 fast 件)。
//=============================================================================
module slow_demux2 (
    input  wire        clk,
    input  wire        rst_n,
    // ---- 输入 (slow_tx_adp 输出) ----
    input  wire [63:0] s_tdata,
    input  wire [7:0]  s_tkeep,
    input  wire        s_tvalid,
    output wire        s_tready,
    input  wire        s_tlast,
    input  wire        s_port,        // 1 = port1/ch0 (IP_B), 0 = port0/ch1 (IP_A)
    // ---- 输出口 0 (ch1) ----
    output wire [63:0] d0_tdata,
    output wire [7:0]  d0_tkeep,
    output wire        d0_tvalid,
    input  wire        d0_tready,
    output wire        d0_tlast,
    // ---- 输出口 1 (ch0) ----
    output wire [63:0] d1_tdata,
    output wire [7:0]  d1_tkeep,
    output wire        d1_tvalid,
    input  wire        d1_tready,
    output wire        d1_tlast,
    // ---- 统计 (门用) ----
    output reg  [31:0] stat_port_change,   // 帧内 s_port != port_r 的拍数 (应恒 0)
    output reg  [31:0] stat_frames0,
    output reg  [31:0] stat_frames1
);
    reg        busy;
    reg        port_r;

    wire port_sel = s_port;
    wire accept   = s_tvalid && s_tready;

    assign d0_tvalid = s_tvalid && !port_sel;
    assign d1_tvalid = s_tvalid &&  port_sel;
    assign s_tready  = port_sel ? d1_tready : d0_tready;
    assign d0_tdata  = s_tdata;
    assign d1_tdata  = s_tdata;
    assign d0_tkeep  = s_tkeep;
    assign d1_tkeep  = s_tkeep;
    assign d0_tlast  = s_tlast;
    assign d1_tlast  = s_tlast;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0; port_r <= 1'b0;
            stat_port_change <= 32'd0; stat_frames0 <= 32'd0; stat_frames1 <= 32'd0;
        end else begin
            if (accept && !busy) begin
                busy   <= 1'b1;
                port_r <= s_port;
            end
            if (accept && s_tlast) begin
                busy <= 1'b0;
                if (port_sel) stat_frames1 <= stat_frames1 + 32'd1;
                else          stat_frames0 <= stat_frames0 + 32'd1;
            end
            if (busy && s_tvalid && (s_port != port_r))
                stat_port_change <= stat_port_change + 32'd1;
        end
    end

endmodule
