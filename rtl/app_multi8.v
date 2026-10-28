`timescale 1ns/1ps
//=============================================================================
// app_multi8: P11 APP8 — 8 会话 TCP 演示 app（8 × app_pattern + 帧级 mux/demux）
//=============================================================================
// 设计件 = _proj_10g/notes/p11_app8_contract_20261027/DESIGN.md
//
// 结构（全部新逻辑在 3 个可单测的小模块里）：
//   8 × app_pattern（逐字复用；每实例只收自己槽号的事件）
//     ├─ axis_frame_mux8   : 8→1 帧级轮询（不抢占；tlast 后才换源）
//     ├─ axis_tid_demux8   : 1→8 按 tid 帧级分发（tid>=N 消费丢弃并计数）
//     └─ app_close_arb8    : 8 个单拍 close_req → 逐拍发出，不丢
//
// 零回归：本模块只在 `P11_APP8` 宏下被 wrapper 例化；app_pattern 零改动。
// 边界：N 固定 8（retx 8 槽 / cid 0..7 对齐）；m_tid 在一帧内恒定。
//=============================================================================
module app_multi8 #(
    parameter integer N            = 8,
    parameter [31:0]  TX_BYTES     = 32'h0FFFFFFF,
    parameter [11:0]  TX_SEGSZ     = 12'd1460,
    parameter [63:0]  SEED         = 64'h9E3779B97F4A7C15,
    parameter         TX_CONTINUOUS= 1'b1,
    parameter         TX_SWCLOSE   = 1'b1
) (
    input  wire        clk,
    input  wire        rst_n,
    // 事件 (app_ctrl)
    input  wire        ev_up,
    input  wire        ev_down,
    input  wire [3:0]  ev_slot,
    // ---- TX: app -> stack (单条流) ----
    output wire [63:0] m_tdata,
    output wire [7:0]  m_tkeep,
    output wire        m_tvalid,
    input  wire        m_tready,
    output wire        m_tlast,
    output wire [3:0]  m_tid,
    input  wire [15:0] app_tx_ready,
    // 关闭请求 (app_ctrl)
    output wire        close_req,
    output wire [3:0]  close_id,
    // ---- RX: stack -> app ----
    input  wire [63:0] rx_tdata,
    input  wire [7:0]  rx_tkeep,
    input  wire        rx_tvalid,
    output wire        rx_tready,
    input  wire        rx_tlast,
    input  wire [3:0]  rx_tid,
    // ---- 故障注入 (每实例 16 位; 板级全 0) ----
    input  wire [N*16-1:0] i_bad_frame,
    // ---- 统计/状态 (聚合) ----
    output wire [31:0] stat_tx_bytes,
    output wire [31:0] stat_tx_frames,
    output wire [31:0] stat_rx_bytes,
    output wire [31:0] stat_mismatch,
    output wire        active,
    output wire [3:0]  act_id,          // 固定 0（保留端口）
    output wire        done,
    output wire [31:0] dbg_lfsr,        // 实例 0 的 lfsr（调试）
    output wire [3:0]  led,
    // 现有快照计数器（8 实例聚合）
    output wire [31:0] stat_frmwait_cyc,
    output wire [31:0] stat_bp_cyc,
    output wire [31:0] stat_up_ev,
    output wire [31:0] stat_sw_req,
    output wire [31:0] stat_sw_apply,
    output wire [31:0] stat_up_pend,
    // 本模块新增观测
    output wire [31:0] stat_arb_frames,
    output wire [31:0] stat_rx_orphan_frames,
    output wire [31:0] stat_rx_orphan_bytes,
    output wire [3:0]  stat_close_pend_max,
    // 每实例 mismatch（调试/TB；板级可不接）
    output wire [N*32-1:0] dbg_inst_mismatch
);
    // ---------------- 每实例 TX / RX 打包 ----------------
    wire [N*77-1:0] s_data;
    wire [N-1:0]    s_valid;
    wire [N-1:0]    s_ready;

    wire [N*77-1:0] r_data;
    wire [N-1:0]    r_valid;
    wire [N-1:0]    r_ready;

    wire [N-1:0]    s_crq;

    wire [N*32-1:0] s_tx_bytes, s_tx_frames, s_rx_bytes, s_mismatch;
    wire [N*32-1:0] s_frmwait, s_bp, s_upev, s_swreq, s_swapply, s_uppend;
    wire [N-1:0]    s_active, s_done, s_led;
    wire [N*32-1:0] s_lfsr;

    // ---------------- 8 × app_pattern ----------------
    genvar gi;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : g_app
            wire evu = ev_up   && (ev_slot == gi);
            wire evd = ev_down && (ev_slot == gi);
            wire [15:0] bad = i_bad_frame[gi*16 +: 16];

            wire [63:0] tdata;
            wire [7:0]  tkeep;
            wire        tlast;
            wire [3:0]  tid;
            wire [63:0] rxd;
            wire [7:0]  rxk;
            wire        rxl;
            wire [3:0]  rxi;
            wire [3:0]  led_i;     // app_pattern.led = [3:0]（输出端口不能接拼接）

            app_pattern #(
                .TX_BYTES     (TX_BYTES),
                .TX_SEGSZ     (TX_SEGSZ),
                .SEED         (SEED),
                .TX_CONTINUOUS(TX_CONTINUOUS),
                .TX_TAILCARRY (1'b0),
                .TX_SWCLOSE   (TX_SWCLOSE)
            ) u_app_i (
                .clk            (clk),
                .rst_n          (rst_n),
                .ev_up          (evu),
                .ev_down        (evd),
                .ev_slot        (ev_slot),
                .m_tdata        (tdata),
                .m_tkeep        (tkeep),
                .m_tvalid       (s_valid[gi]),
                .m_tready       (s_ready[gi]),
                .m_tlast        (tlast),
                .m_tid          (tid),
                .app_tx_ready   (app_tx_ready),
                .close_req      (s_crq[gi]),
                .close_id       (),
                .rx_tdata       (rxd),
                .rx_tkeep       (rxk),
                .rx_tvalid      (r_valid[gi]),
                .rx_tready      (r_ready[gi]),
                .rx_tlast       (rxl),
                .rx_tid         (rxi),
                .i_bad_frame    (bad),
                .stat_tx_bytes  (s_tx_bytes[gi*32 +: 32]),
                .stat_tx_frames (s_tx_frames[gi*32 +: 32]),
                .stat_bad_frames(),
                .stat_rx_bytes  (s_rx_bytes[gi*32 +: 32]),
                .stat_mismatch  (s_mismatch[gi*32 +: 32]),
                .active         (s_active[gi]),
                .act_id         (),
                .done           (s_done[gi]),
                .dbg_lfsr       (s_lfsr[gi*32 +: 32]),
                .led            (led_i),
                .stat_frmwait_cyc(s_frmwait[gi*32 +: 32]),
                .stat_bp_cyc     (s_bp[gi*32 +: 32]),
                .stat_up_ev      (s_upev[gi*32 +: 32]),
                .stat_sw_req     (s_swreq[gi*32 +: 32]),
                .stat_sw_apply   (s_swapply[gi*32 +: 32]),
                .stat_up_pend    (s_uppend[gi*32 +: 32])
            );

            assign s_led[gi] = led_i[0];   // 聚合 LED 只看每位实例的 bit0（原行为）
            assign s_data[gi*77 +: 77] = {tkeep, tlast, tdata, tid};
            assign {rxk, rxl, rxd, rxi} = r_data[gi*77 +: 77];
        end
    endgenerate

    // ---------------- TX mux / RX demux / close 仲裁 ----------------
    wire [76:0] m_pack;
    axis_frame_mux8 #(.N(N), .W(77)) u_mux (
        .clk(clk), .rst_n(rst_n),
        .s_data(s_data), .s_valid(s_valid), .s_ready(s_ready),
        .m_data(m_pack), .m_valid(m_tvalid), .m_ready(m_tready),
        .stat_frames(stat_arb_frames),
        .stat_abort_sel()
    );
    assign {m_tkeep, m_tlast, m_tdata, m_tid} = m_pack;

    wire [76:0] r_pack = {rx_tkeep, rx_tlast, rx_tdata, rx_tid};
    axis_tid_demux8 #(.N(N), .W(77)) u_demux (
        .clk(clk), .rst_n(rst_n),
        .s_data(r_pack), .s_valid(rx_tvalid), .s_ready(rx_tready),
        .m_data(r_data), .m_valid(r_valid), .m_ready(r_ready),
        .stat_orphan_frames(stat_rx_orphan_frames),
        .stat_orphan_bytes(stat_rx_orphan_bytes)
    );

    app_close_arb8 #(.N(N)) u_close (
        .clk(clk), .rst_n(rst_n),
        .i_req(s_crq), .o_req(close_req), .o_id(close_id),
        .stat_pend_max(stat_close_pend_max)
    );

    // ---------------- 聚合统计 ----------------
    integer j;
    reg [31:0] a_tx_bytes, a_tx_frames, a_rx_bytes, a_mismatch;
    reg [31:0] a_frmwait, a_bp, a_upev, a_swreq, a_swapply, a_uppend;
    always @* begin
        a_tx_bytes  = 32'd0; a_tx_frames = 32'd0;
        a_rx_bytes  = 32'd0; a_mismatch  = 32'd0;
        a_frmwait   = 32'd0; a_bp        = 32'd0;
        a_upev      = 32'd0; a_swreq     = 32'd0;
        a_swapply   = 32'd0; a_uppend    = 32'd0;
        for (j = 0; j < N; j = j + 1) begin
            a_tx_bytes  = a_tx_bytes  + s_tx_bytes [j*32 +: 32];
            a_tx_frames = a_tx_frames + s_tx_frames[j*32 +: 32];
            a_rx_bytes  = a_rx_bytes  + s_rx_bytes [j*32 +: 32];
            a_mismatch  = a_mismatch  + s_mismatch [j*32 +: 32];
            a_frmwait   = a_frmwait   + s_frmwait  [j*32 +: 32];
            a_bp        = a_bp        + s_bp       [j*32 +: 32];
            a_upev      = a_upev      + s_upev     [j*32 +: 32];
            a_swreq     = a_swreq     + s_swreq    [j*32 +: 32];
            a_swapply   = a_swapply   + s_swapply  [j*32 +: 32];
            a_uppend    = a_uppend    + s_uppend   [j*32 +: 32];
        end
    end

    assign dbg_inst_mismatch = s_mismatch;
    assign stat_tx_bytes    = a_tx_bytes;
    assign stat_tx_frames   = a_tx_frames;
    assign stat_rx_bytes    = a_rx_bytes;
    assign stat_mismatch    = a_mismatch;
    assign stat_frmwait_cyc = a_frmwait;
    assign stat_bp_cyc      = a_bp;
    assign stat_up_ev       = a_upev;
    assign stat_sw_req      = a_swreq;
    assign stat_sw_apply    = a_swapply;
    assign stat_up_pend     = a_uppend;

    assign active  = |s_active;
    assign done    = &s_done;
    assign act_id  = 4'd0;
    assign dbg_lfsr= s_lfsr[31:0];
    assign led     = {3'd0, |s_led};
endmodule
