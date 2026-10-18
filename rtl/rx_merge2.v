`timescale 1ns/1ps
//=============================================================================
// rx_merge2.v — P11 P2-甲: 双口 RX 帧级合并 (工作保持 round-robin)
//=============================================================================
// 上游: 每口一个 fifo_async(76 x 256) 的 dp 域读口 (p0 = ch1/现役, p1 = ch0/新口)。
// 下游: vlan_strip -> rx_classify (零改动)。
//
// 【仲裁】帧级互斥 + 工作保持:
//   · !busy 拍选口: STRICT=1 时优先 p1 (只用于 G2 负控); STRICT=0 时优先"上一帧
//     未服务的口" (~rr), 若它无 tvalid 则服务另一口 (工作保持)。
//   · busy 期间锁定 sel; 只在 m_tlast 被消费后释放 ⇒ 一帧的字连续、绝不交织。
//   · 每帧末尾释放拍 = **1 拍重仲裁气泡** (大帧 ~0.5%, 最小帧 8 字 ~11%)。
//
// 【无内部丢帧路径】selected 口的反压直接回上游 FIFO; 未选中口 tready=0,
//   其 FIFO/上游 MAC 承担溢出计数 (W82/W4/W86)。
//
// 【可观测性边界】A-1 下 RX 合并流不携带端口标签 (身份 = 目的 IP) ⇒ 板内无法
//   回答"这一帧从哪个物理口进来"; 诊断靠对端每口 NIC 计数/拔插/TX_DIS 隔离。
//   stat_frames0/1 只给门用 (不进快照)。
//=============================================================================
module rx_merge2 #(
    parameter STRICT = 1'b0        // 1 = 严格优先 p1 (仅 G2 负控实例; wrapper 硬接 0)
) (
    input  wire        clk,
    input  wire        rst_n,
    // ---- p0 = ch1 (现役) ----
    input  wire [63:0] p0_tdata,
    input  wire [7:0]  p0_tkeep,
    input  wire        p0_tvalid,
    output wire        p0_tready,
    input  wire        p0_tlast,
    input  wire        p0_tuser,      // SOP
    input  wire        p0_tcrs,
    input  wire        p0_terr,
    // ---- p1 = ch0 (新口) ----
    input  wire [63:0] p1_tdata,
    input  wire [7:0]  p1_tkeep,
    input  wire        p1_tvalid,
    output wire        p1_tready,
    input  wire        p1_tlast,
    input  wire        p1_tuser,      // SOP
    input  wire        p1_tcrs,
    input  wire        p1_terr,
    // ---- 合并输出 ----
    output wire [63:0] m_tdata,
    output wire [7:0]  m_tkeep,
    output wire        m_tvalid,
    input  wire        m_tready,
    output wire        m_tlast,
    output wire        m_tuser,
    output wire        m_tcrs,
    output wire        m_terr,
    // ---- 统计 (门用; 不进快照) ----
    output reg  [31:0] stat_frames0,   // p0 帧数
    output reg  [31:0] stat_frames1,   // p1 帧数
    output reg  [31:0] stat_out,       // 输出帧数 (= frames0+frames1)
    output reg  [31:0] stat_bubble     // !busy 且两口都无 tvalid 的拍数
);

    reg        busy;      // 帧内锁
    reg        sel;       // 本帧口 (0 = p0, 1 = p1)
    reg        rr;        // 上一帧服务的口 (工作保持偏好 ~rr)

    // 空闲拍仲裁 (只决定下一拍 busy 的 sel)
    wire p0_av = p0_tvalid;
    wire p1_av = p1_tvalid;
    // rr = 上一帧服务的口 ⇒ 工作保持偏好**另一口** (~rr):
    //   rr==0 (上次 p0) ⇒ 优先 p1; rr==1 (上次 p1) ⇒ 优先 p0。
    wire pick1 = !busy && p1_av && (STRICT || !rr || !p0_av);
    wire pick0 = !busy && p0_av && !pick1;
    wire pick  = pick0 | pick1;

    // 忙拍数据通路
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

    wire frame_last = m_tvalid && m_tready && m_tlast;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0; sel <= 1'b0; rr <= 1'b0;
            stat_frames0 <= 32'd0; stat_frames1 <= 32'd0;
            stat_out <= 32'd0; stat_bubble <= 32'd0;
        end else begin
            if (pick) begin
                busy <= 1'b1;
                sel  <= pick1;
            end else if (frame_last) begin
                busy <= 1'b0;
                rr   <= sel;                 // 下一帧优先另一口
            end
            if (pick) begin
                // 选口拍不计帧 (帧末才计)
            end else if (!busy && !p0_av && !p1_av) begin
                stat_bubble <= stat_bubble + 32'd1;
            end
            if (frame_last) begin
                if (sel) stat_frames1 <= stat_frames1 + 32'd1;
                else     stat_frames0 <= stat_frames0 + 32'd1;
                stat_out <= stat_out + 32'd1;
            end
        end
    end

endmodule
