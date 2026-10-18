`timescale 1ns/1ps
//=============================================================================
// slow_merge2.v — P11 P3 (C4): 慢路径两端口 2:1 帧级合并 (单份 HLS)
//=============================================================================
// 设计件 §6.3 / §14.2-4: **不复用快速路径的 rx_merge2** (实例计数门按模块名
// 区分快速/慢速件); 行为与其同构:
//   · 上游 = 每口 udp_split 的透传口 (76 位 AXIS: tdata/tkeep/tuser/tlast/
//     tcrs/terr), 下游 = 单份 slow_rx_adp -> HLS。
//   · 帧级互斥 + 工作保持 RR; busy 期间锁口, 只在 m_tlast 被消费后释放
//     ⇒ 一帧的字连续、绝不交织 (帧原子)。
//   · 未选中口 tready=0, 反压停在上游 (slow 帧速率低, 无 HOL 风险)。
//
// 【P3 新增的跨口慢路径耦合】(如实): 两口慢流量同时打满时按帧 RR 交替;
//   单帧有界 ⇒ 互不无界阻塞。快速路径完全不受影响 (本模块只在 slow 侧)。
//
// TO_CYCLES: 半帧看门狗 (>0 生效) —— 停钟/半帧不再锁死另一口。
//=============================================================================
module slow_merge2 #(
    parameter STRICT    = 1'b0,     // 1 = 严格优先 p1 (仅门负控)
    parameter TO_CYCLES = 0         // >0 = 半帧看门狗 (dp_clk 拍)
) (
    input  wire        clk,
    input  wire        rst_n,
    // ---- p0 (port0 / ch1) ----
    input  wire [63:0] p0_tdata,
    input  wire [7:0]  p0_tkeep,
    input  wire        p0_tvalid,
    output wire        p0_tready,
    input  wire        p0_tlast,
    input  wire        p0_tuser,
    input  wire        p0_tcrs,
    input  wire        p0_terr,
    // ---- p1 (port1 / ch0) ----
    input  wire [63:0] p1_tdata,
    input  wire [7:0]  p1_tkeep,
    input  wire        p1_tvalid,
    output wire        p1_tready,
    input  wire        p1_tlast,
    input  wire        p1_tuser,
    input  wire        p1_tcrs,
    input  wire        p1_terr,
    // ---- 合并输出 (76 位 AXIS) ----
    output wire [63:0] m_tdata,
    output wire [7:0]  m_tkeep,
    output wire        m_tvalid,
    input  wire        m_tready,
    output wire        m_tlast,
    output wire        m_tuser,
    output wire        m_tcrs,
    output wire        m_terr,
    // ---- 统计 (门用) ----
    output reg  [31:0] stat_frames0,
    output reg  [31:0] stat_frames1,
    output reg  [31:0] stat_out,
    output reg  [31:0] stat_bubble,
    output reg  [31:0] stat_abort
);
    reg        busy;
    reg        sel;
    reg        rr;
    reg [31:0] to_cnt;

    wire p0_av = p0_tvalid;
    wire p1_av = p1_tvalid;
    wire pick1 = !busy && p1_av && (STRICT || !rr || !p0_av);
    wire pick0 = !busy && p0_av && !pick1;
    wire pick  = pick0 | pick1;

    wire sel_tvalid = sel ? p1_tvalid : p0_tvalid;
    assign p0_tready = busy && !sel && m_tready;
    assign p1_tready = busy &&  sel && m_tready;

    assign m_tdata  = sel ? p1_tdata : p0_tdata;
    assign m_tkeep  = sel ? p1_tkeep : p0_tkeep;
    assign m_tlast  = sel ? p1_tlast : p0_tlast;
    assign m_tuser  = sel ? p1_tuser : p0_tuser;
    assign m_tcrs   = sel ? p1_tcrs  : p0_tcrs;
    assign m_terr   = sel ? p1_terr  : p0_terr;
    assign m_tvalid = busy && sel_tvalid;

    wire frame_last  = m_tvalid && m_tready && m_tlast;
    wire sel_stalled = busy && !sel_tvalid;
    wire to_fire     = (TO_CYCLES > 0) && sel_stalled &&
                       ((to_cnt + 32'd1) >= TO_CYCLES);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0; sel <= 1'b0; rr <= 1'b0; to_cnt <= 32'd0;
            stat_frames0 <= 32'd0; stat_frames1 <= 32'd0;
            stat_out <= 32'd0; stat_bubble <= 32'd0; stat_abort <= 32'd0;
        end else begin
            if (pick) begin
                busy <= 1'b1;
                sel  <= pick1;
                to_cnt <= 32'd0;
            end else if (frame_last) begin
                busy <= 1'b0;
                rr   <= sel;
                to_cnt <= 32'd0;
            end else if (to_fire) begin
                busy <= 1'b0;
                to_cnt <= 32'd0;
                stat_abort <= stat_abort + 32'd1;
            end else if (!sel_stalled) begin
                to_cnt <= 32'd0;
            end else begin
                to_cnt <= to_cnt + 32'd1;
            end

            if (!busy && !p0_av && !p1_av) stat_bubble <= stat_bubble + 32'd1;
            if (frame_last) begin
                if (sel) stat_frames1 <= stat_frames1 + 32'd1;
                else     stat_frames0 <= stat_frames0 + 32'd1;
                stat_out <= stat_out + 32'd1;
            end
        end
    end

endmodule
