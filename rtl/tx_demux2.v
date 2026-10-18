`timescale 1ns/1ps
//=============================================================================
// tx_demux2.v — P11 P2-甲: TX 帧级 1->2 端口分离 (方案 ② 的 demux 前移件)
//=============================================================================
// 每个生产者 (TCP tcp_tx_frame / UDP udp_tx_frame / HLS slow_tx_adp) 的输出各过
// 一个本模块; 下游是每口一套两级 tx_arb (TCP>UDP>HLS)。tx_arb 源码零改动。
//
// 【帧原子】帧首被接受的那一拍锁存 s_port -> port_r, 帧内一律用 port_r 选口
//   (不是组合 s_port)。⇒ 即使生产者在帧中途改变 s_port, 本帧也不会跨口分裂;
//   stat_port_change 计数该违规 (应恒 0 — 生产者侧 M-12 另有逐拍断言)。
//
// 【反压】纯组合 mux: 选中口的 tready 回传; 未选中口 tvalid=0。零缓冲、零吞吐
//   代价 (每口 arb 各自独立, 跨口无 HOL)。
//=============================================================================
module tx_demux2 (
    input  wire        clk,
    input  wire        rst_n,
    // ---- 输入 (生产者字流; s_port 须帧内稳定) ----
    input  wire [63:0] s_tdata,
    input  wire [7:0]  s_tkeep,
    input  wire        s_tvalid,
    output wire        s_tready,
    input  wire        s_tlast,
    input  wire        s_port,      // 1 = ch0/J7 (IP_B), 0 = ch1/J8 (IP_A)
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

    reg        busy;      // 帧在途
    reg        port_r;    // 本帧锁存口

    wire port_sel = busy ? port_r : s_port;
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
                port_r <= s_port;          // 帧首锁存
            end
            if (accept && s_tlast) begin
                busy <= 1'b0;
                // port_sel = 本拍口 (单拍帧时 busy 尚为 0, 直接用 s_port)
                if (port_sel) stat_frames1 <= stat_frames1 + 32'd1;
                else          stat_frames0 <= stat_frames0 + 32'd1;
            end
            if (busy && s_tvalid && (s_port != port_r))
                stat_port_change <= stat_port_change + 32'd1;
        end
    end

endmodule
