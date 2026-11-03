`timescale 1ns/1ps
// TX 帧级 2:1 仲裁: fast (tcp_tx_frame) 对 slow (slow_tx_adp)。
//
//   STARVE_GUARD = 0 (默认): **fast 严格优先** —— 与历史逐位一致。
//     已知边界: fast 连续不断帧时 (P11 8×TCP app 洪泛), slow 永远拿不到线
//     ⇒ SYN-ACK/FIN/RST 饿死 (2026-11-03 板级 + tb_tx_arb_starve 已证)。
//
//   STARVE_GUARD = 1 (P11 C4 构建): 饥饿保护 —— slow 在 **一个 fast 帧期间**
//     已挂起 (slow_wait=1), 则下一个帧边界无条件让 slow 先发一帧。
//     上限 = 至多等一个 fast 帧 (10G 最大帧 ~1.2 µs); slow 不挂起时 fast 仍
//     100% 独占。slow 连续挂起时 fast/slow 帧级交替 (1:1), 这是有意的公平性,
//     不是优先级反转。slow_wait 在 slow 帧服务期间/源撤 valid 时清零。
//
// 空闲时按请求选择并寄存, 锁定到 TLAST 消费拍; 帧间 1 拍重仲裁气泡。
// 纯组合数据通路 (无时钟延迟), II=1。
module tx_arb #(
    parameter integer STARVE_GUARD = 0
) (
    input  wire        clk,
    input  wire        rst_n,
    // fast (TCP)
    input  wire [63:0] s_fast_tdata,
    input  wire [7:0]  s_fast_tkeep,
    input  wire        s_fast_tvalid,
    output wire        s_fast_tready,
    input  wire        s_fast_tlast,
    // slow (HLS 慢路径)
    input  wire [63:0] s_slow_tdata,
    input  wire [7:0]  s_slow_tkeep,
    input  wire        s_slow_tvalid,
    output wire        s_slow_tready,
    input  wire        s_slow_tlast,
    // 去 mac_tx_64
    output wire [63:0] m_axis_tdata,
    output wire [7:0]  m_axis_tkeep,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast
);
    reg busy, sel_fast;

    assign m_axis_tdata  = sel_fast ? s_fast_tdata : s_slow_tdata;
    assign m_axis_tkeep  = sel_fast ? s_fast_tkeep : s_slow_tkeep;
    assign m_axis_tlast  = sel_fast ? s_fast_tlast : s_slow_tlast;
    assign m_axis_tvalid = busy && (sel_fast ? s_fast_tvalid : s_slow_tvalid);
    assign s_fast_tready = busy &&  sel_fast && m_axis_tready;
    assign s_slow_tready = busy && !sel_fast && m_axis_tready;

    wire fin = m_axis_tvalid && m_axis_tready && m_axis_tlast;

    generate
    if (STARVE_GUARD == 0) begin : g_legacy
        // 历史严格优先: 逐位不变
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                busy <= 1'b0; sel_fast <= 1'b0;
            end else begin
                if (!busy) begin
                    if (s_fast_tvalid) begin
                        busy <= 1'b1; sel_fast <= 1'b1;
                    end else if (s_slow_tvalid) begin
                        busy <= 1'b1; sel_fast <= 1'b0;
                    end
                end else if (fin) begin
                    busy <= 1'b0;
                end
            end
        end
    end else begin : g_guard
        // 饥饿保护: slow 在上一 fast 帧内挂起过 ⇒ 本帧边界让 slow 先发一帧.
        reg slow_wait;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                busy <= 1'b0; sel_fast <= 1'b0; slow_wait <= 1'b0;
            end else begin
                if (!busy) begin
                    if (s_slow_tvalid && slow_wait) begin
                        // 已在 fast 帧内等过 ⇒ 无条件让 slow (优先于 fast)
                        busy <= 1'b1; sel_fast <= 1'b0; slow_wait <= 1'b0;
                    end else if (s_fast_tvalid) begin
                        busy <= 1'b1; sel_fast <= 1'b1;
                        // 本边界如果 slow 也在挂起, 记到下一帧边界
                        slow_wait <= s_slow_tvalid;
                    end else if (s_slow_tvalid) begin
                        busy <= 1'b1; sel_fast <= 1'b0; slow_wait <= 1'b0;
                    end else begin
                        slow_wait <= 1'b0;
                    end
                end else begin
                    if (!sel_fast)                slow_wait <= 1'b0;  // 正在服务 slow
                    else if (s_slow_tvalid)       slow_wait <= 1'b1;  // fast 帧内 slow 挂起
                    if (fin) busy <= 1'b0;
                end
            end
        end
    end
    endgenerate
endmodule
