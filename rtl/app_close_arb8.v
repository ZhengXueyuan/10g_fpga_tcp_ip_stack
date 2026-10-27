`timescale 1ns/1ps
//=============================================================================
// app_close_arb8: 8 路单拍 close_req → 单口逐拍发出（P11 APP8）
//=============================================================================
// app_pattern 的 close_req 是**单拍脉冲**，app_ctrl 每拍只受理一个。
// 8 个实例可能同拍申请 ⇒ 用 pending 位锁存，轮询逐拍发出，不丢。
//   · 同拍"新脉冲 + 发出同一位"：清位让位于新脉冲（保留到下一拍再发）。
//   · 连续模式（TX_CONTINUOUS=1）下 app_pattern 不产生 close_req；本模块仍通用。
//=============================================================================
module app_close_arb8 #(
    parameter integer N = 8
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [N-1:0] i_req,        // 单拍脉冲
    output reg         o_req,
    output reg  [3:0]  o_id,
    output reg  [3:0]  stat_pend_max  // 最大同时积压（饱和于 8）
);
    localparam [2:0] MSK3 = N - 1;

    reg [N-1:0] pend;
    reg [2:0]   rr;

    integer m;
    reg [2:0]   cidx;
    reg         cfound;
    always @* begin
        cidx   = 3'd0;
        cfound = 1'b0;
        for (m = 0; m < N; m = m + 1) begin
            if (!cfound && pend[(rr + m) & MSK3]) begin
                cidx   = (rr + m) & MSK3;
                cfound = 1'b1;
            end
        end
    end

    integer q;
    reg [3:0] pend_cnt;
    always @* begin
        pend_cnt = 4'd0;
        for (q = 0; q < N; q = q + 1) pend_cnt = pend_cnt + {3'd0, pend[q]};
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pend <= {N{1'b0}};
            rr   <= 3'd0;
            o_req <= 1'b0;
            o_id  <= 4'd0;
            stat_pend_max <= 4'd0;
        end else begin
            o_req <= 1'b0;
            for (m = 0; m < N; m = m + 1) begin
                if (i_req[m]) pend[m] <= 1'b1;
            end
            if (cfound) begin
                o_req <= 1'b1;
                o_id  <= cidx;
                rr    <= (cidx + 3'd1) & MSK3;
                if (!i_req[cidx]) pend[cidx] <= 1'b0;
            end
            if (pend_cnt > stat_pend_max) stat_pend_max <= pend_cnt;
        end
    end
endmodule
