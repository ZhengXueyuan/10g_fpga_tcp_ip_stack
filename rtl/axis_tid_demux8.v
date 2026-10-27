`timescale 1ns/1ps
//=============================================================================
// axis_tid_demux8: 1→8 AXIS 按 tid 帧级分发（P11 APP8）
//=============================================================================
// 合同：
//   · data 布局 = {tkeep[7:0], tlast, tdata[63:0], tid[3:0]}（W=77）
//   · tid 在**一帧内稳定**（AXIS 侧边带合同）；本模块在帧边界锁存 cur_tid：
//       第一个 beat（!in_frame）用当拍 tid；之后用锁存值；tlast 接收后清 in_frame。
//   · 被选实例的 m_ready 反压整条流（与今天单实例语义一致，不丢字）。
//   · tid >= N（理论不可达；上游 MAX_TCP_CONN <= N）：整帧**消费并丢弃**，
//     计 orphan frames/bytes ⇒ 不会静默死锁。
//=============================================================================
module axis_tid_demux8 #(
    parameter integer N = 8,
    parameter integer W = 77
) (
    input  wire           clk,
    input  wire           rst_n,
    input  wire [W-1:0]   s_data,
    input  wire           s_valid,
    output wire           s_ready,
    output wire [N*W-1:0] m_data,
    output wire [N-1:0]   m_valid,
    input  wire [N-1:0]   m_ready,
    // 观测
    output reg  [31:0]    stat_orphan_frames,
    output reg  [31:0]    stat_orphan_bytes
);
    wire [3:0] s_tid   = s_data[3:0];
    wire       s_tlast = s_data[68];
    wire [7:0] s_tkeep = s_data[76:69];

    reg        in_frame;
    reg [3:0]  cur_tid;
    wire [3:0] eff_tid = in_frame ? cur_tid : s_tid;
    wire       orphan  = (eff_tid >= N);

    genvar gi;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : g_dm
            assign m_data [gi*W +: W] = s_data;
            assign m_valid[gi] = s_valid && !orphan && (eff_tid == gi);
        end
    endgenerate

    assign s_ready = orphan ? 1'b1 : m_ready[eff_tid];

    function [3:0] popc8;
        input [7:0] v;
        integer b;
        begin
            popc8 = 4'd0;
            for (b = 0; b < 8; b = b + 1) popc8 = popc8 + {3'd0, v[b]};
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_frame <= 1'b0;
            cur_tid  <= 4'd0;
            stat_orphan_frames <= 32'd0;
            stat_orphan_bytes  <= 32'd0;
        end else if (s_valid && s_ready) begin
            if (s_tlast) begin
                in_frame <= 1'b0;
                if (orphan) stat_orphan_frames <= stat_orphan_frames + 32'd1;
            end else if (!in_frame) begin
                in_frame <= 1'b1;
                cur_tid  <= s_tid;
            end
            if (orphan) stat_orphan_bytes <= stat_orphan_bytes + {28'd0, popc8(s_tkeep)};
        end
    end
endmodule
