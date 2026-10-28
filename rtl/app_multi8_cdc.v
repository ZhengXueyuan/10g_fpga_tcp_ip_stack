`timescale 1ns/1ps
//=============================================================================
// app_multi8_cdc: P11 APP8 的 8×app 跨时钟域包装
//=============================================================================
// 设计件 = _proj_10g/notes/p11_app8_cdc_20261029/DESIGN.md v4。
//
// 结构:
//   app_multi8 (clk_app)  ── TX 77b FIFO ──> DP (tcp_echo)
//                         <─ RX 77b FIFO ──  DP (tcp_echo / eco2)
//                         <─ ev  6b FIFO ──  DP (app_ctrl 事件)
//                         ── close 5b FIFO ─> DP (app_ctrl)
//   app_tx_ready[15:0] : DP 寄存 1 拍 -> app 侧逐位 2FF
//   stats 10×32 + close_pend_max[3:0] : hold/toggle 握手 -> DP shadow
//   W97 cdc_status[31:0] : [2] ev drop, [3] close drop, [4] stats stale,
//                          [5] locked_app, [6] app_rst_seen, [7] stats timeout,
//                          [15:8] per-conn mismatch sticky,
//                          [19:16] close_pend_max, [20] dp_rst_seen,
//                          [31:21] RX FIFO write-side occupancy (9b zero-ext)
//
// 硬规则 (设计件):
//   · 4 个 CDC FIFO 的 wr_rst_n/rd_rst_n **全部接板级 reset_n** (P6B 规则)。
//   · app_multi8 功能复位 = app_rst_n; DP 功能复位 = dp_rst_n。
//   · 事件读侧 rd_en 与 ev_* 同受 app_rst_n 门控 (H1)。
//   · TX/RX 无丢字依赖源保持契约 (M8) -- 由全链门 $stable 证明。
//=============================================================================
module app_multi8_cdc #(
    parameter integer N             = 8,
    parameter [31:0]  TX_BYTES      = 32'h0FFFFFFF,
    parameter [11:0]  TX_SEGSZ      = 12'd1460,
    parameter [63:0]  SEED          = 64'h9E3779B97F4A7C15,
    parameter         TX_CONTINUOUS = 1'b1,
    parameter         TX_SWCLOSE    = 1'b1
)(
    // ---- DP 侧 ----
    input  wire        dp_clk,
    input  wire        dp_rst_n,
    input  wire        reset_n,        // 板级复位（CDC FIFO 两侧都用它）
    input  wire        app_clk,
    input  wire        app_rst_n,      // 来自 app_clk_gen（低有效）
    input  wire        locked_app,     // 来自 app_clk_gen（W97[5]/app_alive）
    // 事件 (app_ctrl -> app)
    input  wire        ev_up,
    input  wire        ev_down,
    input  wire [3:0]  ev_slot,
    // TX: app -> DP (到 tcp_echo)
    output wire [63:0] m_tdata,
    output wire [7:0]  m_tkeep,
    output wire        m_tvalid,
    input  wire        m_tready,
    output wire        m_tlast,
    output wire [3:0]  m_tid,
    // TCP ready (DP -> app)
    input  wire [15:0] app_tx_ready,
    // close (app -> DP)
    output wire        close_req,
    output wire [3:0]  close_id,
    // RX: DP (tcp_echo/eco2) -> app
    input  wire [63:0] rx_tdata,
    input  wire [7:0]  rx_tkeep,
    input  wire        rx_tvalid,
    output wire        rx_tready,
    input  wire        rx_tlast,
    input  wire [3:0]  rx_tid,
    input  wire        rx_stall,       // 0x08 bit2（DP 域）
    // 统计（DP 侧 shadow）
    output wire [31:0] stat_tx_bytes,
    output wire [31:0] stat_tx_frames,
    output wire [31:0] stat_rx_bytes,
    output wire [31:0] stat_mismatch,
    output wire [31:0] stat_frmwait_cyc,
    output wire [31:0] stat_bp_cyc,
    output wire [31:0] stat_up_ev,
    output wire [31:0] stat_sw_req,
    output wire [31:0] stat_sw_apply,
    output wire [31:0] stat_up_pend,
    output wire [3:0]  stat_close_pend_max,
    output wire [3:0]  led,
    // CDC 健康字 -> W97
    output wire [31:0] cdc_status
);

    // ---------------------------------------------------------------- core
    wire [63:0] core_m_tdata;
    wire [7:0]  core_m_tkeep;
    wire        core_m_tvalid;
    wire        core_m_tready;
    wire        core_m_tlast;
    wire [3:0]  core_m_tid;
    wire        core_close_req;
    wire [3:0]  core_close_id;
    wire [63:0] core_rx_tdata;
    wire [7:0]  core_rx_tkeep;
    wire        core_rx_tvalid;
    wire        core_rx_tready;
    wire        core_rx_tlast;
    wire [3:0]  core_rx_tid;
    wire        core_ev_up, core_ev_down;
    wire [3:0]  core_ev_slot;
    wire [15:0] core_app_tx_ready;

    wire [31:0] core_tx_bytes, core_tx_frames, core_rx_bytes, core_mismatch;
    wire [31:0] core_frmwait, core_bp, core_up_ev, core_sw_req, core_sw_apply, core_up_pend;
    wire [3:0]  core_close_pend_max;
    wire [3:0]  core_led;
    wire [N*32-1:0] core_dbg_inst_mismatch;

    app_multi8 #(
        .N            (N),
        .TX_BYTES     (TX_BYTES),
        .TX_SEGSZ     (TX_SEGSZ),
        .SEED         (SEED),
        .TX_CONTINUOUS(TX_CONTINUOUS),
        .TX_SWCLOSE   (TX_SWCLOSE)
    ) u_core (
        .clk            (app_clk),
        .rst_n          (app_rst_n),
        .ev_up          (core_ev_up),
        .ev_down        (core_ev_down),
        .ev_slot        (core_ev_slot),
        .m_tdata        (core_m_tdata),
        .m_tkeep        (core_m_tkeep),
        .m_tvalid       (core_m_tvalid),
        .m_tready       (core_m_tready),
        .m_tlast        (core_m_tlast),
        .m_tid          (core_m_tid),
        .app_tx_ready   (core_app_tx_ready),
        .close_req      (core_close_req),
        .close_id       (core_close_id),
        .rx_tdata       (core_rx_tdata),
        .rx_tkeep       (core_rx_tkeep),
        .rx_tvalid      (core_rx_tvalid),
        .rx_tready      (core_rx_tready),
        .rx_tlast       (core_rx_tlast),
        .rx_tid         (core_rx_tid),
        .i_bad_frame    ({N*16{1'b0}}),
        .stat_tx_bytes  (core_tx_bytes),
        .stat_tx_frames (core_tx_frames),
        .stat_rx_bytes  (core_rx_bytes),
        .stat_mismatch  (core_mismatch),
        .active         (),
        .act_id         (),
        .done           (),
        .dbg_lfsr       (),
        .led            (core_led),
        .stat_frmwait_cyc(core_frmwait),
        .stat_bp_cyc     (core_bp),
        .stat_up_ev      (core_up_ev),
        .stat_sw_req     (core_sw_req),
        .stat_sw_apply   (core_sw_apply),
        .stat_up_pend    (core_up_pend),
        .stat_arb_frames (),
        .stat_rx_orphan_frames(),
        .stat_rx_orphan_bytes (),
        .stat_close_pend_max  (core_close_pend_max),
        .dbg_inst_mismatch    (core_dbg_inst_mismatch)
    );

    // ---------------------------------------------------------------- FIFOs
    // 全部 CDC FIFO: 两侧复位都接板级 reset_n（P6B 硬规则）。
    localparam integer DEPTH_AXIS = 256;
    localparam integer DEPTH_SMALL = 16;
    wire [8:0] rx_occ_w;   // RX FIFO 写域占用（W97[31:21]）

    wire [76:0] tx_din = {core_m_tkeep, core_m_tlast, core_m_tdata, core_m_tid};
    wire [76:0] tx_dout;
    wire        tx_full, tx_empty;
    wire        tx_wr = core_m_tvalid && !tx_full;
    wire        tx_rd = m_tready && dp_rst_n && !tx_empty;

    fifo_async #(.WIDTH(77), .DEPTH(DEPTH_AXIS), .FWFT(1)) u_tx (
        .wr_clk(app_clk), .wr_rst_n(reset_n), .wr_en(tx_wr), .din(tx_din), .full(tx_full),
        .rd_clk(dp_clk),  .rd_rst_n(reset_n), .rd_en(tx_rd),  .dout(tx_dout), .empty(tx_empty),
        .dbg_wbin(), .dbg_rbin(), .dbg_wgray(), .dbg_rgray(),
        .dbg_occ_w(), .dbg_occ_r(), .ovf_pulse(), .ovf_cnt()
    );
    assign core_m_tready = !tx_full;
    assign {m_tkeep, m_tlast, m_tdata, m_tid} = tx_dout;
    assign m_tvalid = !tx_empty;

    wire [76:0] rx_din = {rx_tkeep, rx_tlast, rx_tdata, rx_tid};
    wire [76:0] rx_dout;
    wire        rx_full, rx_empty;
    wire        rx_wr = rx_tvalid && !rx_full && !rx_stall;
    wire        rx_rd = core_rx_tready && !rx_empty;

    fifo_async #(.WIDTH(77), .DEPTH(DEPTH_AXIS), .FWFT(1)) u_rx (
        .wr_clk(dp_clk),  .wr_rst_n(reset_n), .wr_en(rx_wr), .din(rx_din), .full(rx_full),
        .rd_clk(app_clk), .rd_rst_n(reset_n), .rd_en(rx_rd), .dout(rx_dout), .empty(rx_empty),
        .dbg_wbin(), .dbg_rbin(), .dbg_wgray(), .dbg_rgray(),
        .dbg_occ_w(rx_occ_w), .dbg_occ_r(), .ovf_pulse(), .ovf_cnt()
    );
    assign rx_tready = !rx_full && !rx_stall;
    assign {core_rx_tkeep, core_rx_tlast, core_rx_tdata, core_rx_tid} = rx_dout;
    assign core_rx_tvalid = !rx_empty;

    wire [5:0] ev_din = {ev_up, ev_down, ev_slot};
    wire [5:0] ev_dout;
    wire       ev_full, ev_empty;
    wire       ev_wr = (ev_up || ev_down) && !ev_full;
    wire       ev_rd = !ev_empty && app_rst_n;      // H1: 与 ev_* 同沿门控
    wire       drop_ev = (ev_up || ev_down) && ev_full;

    fifo_async #(.WIDTH(6), .DEPTH(DEPTH_SMALL), .FWFT(1)) u_ev (
        .wr_clk(dp_clk),  .wr_rst_n(reset_n), .wr_en(ev_wr), .din(ev_din), .full(ev_full),
        .rd_clk(app_clk), .rd_rst_n(reset_n), .rd_en(ev_rd), .dout(ev_dout), .empty(ev_empty),
        .dbg_wbin(), .dbg_rbin(), .dbg_wgray(), .dbg_rgray(),
        .dbg_occ_w(), .dbg_occ_r(), .ovf_pulse(), .ovf_cnt()
    );
    assign core_ev_up   = !ev_empty && ev_dout[5] && app_rst_n;
    assign core_ev_down = !ev_empty && ev_dout[4] && app_rst_n;
    assign core_ev_slot = ev_dout[3:0];

    wire [4:0] cl_din = {core_close_req, core_close_id};
    wire [4:0] cl_dout;
    wire       cl_full, cl_empty;
    wire       cl_wr = core_close_req && !cl_full;
    wire       cl_rd = !cl_empty && dp_rst_n;
    wire       drop_cl = core_close_req && cl_full;

    fifo_async #(.WIDTH(5), .DEPTH(DEPTH_SMALL), .FWFT(1)) u_cl (
        .wr_clk(app_clk), .wr_rst_n(reset_n), .wr_en(cl_wr), .din(cl_din), .full(cl_full),
        .rd_clk(dp_clk),  .rd_rst_n(reset_n), .rd_en(cl_rd),  .dout(cl_dout), .empty(cl_empty),
        .dbg_wbin(), .dbg_rbin(), .dbg_wgray(), .dbg_rgray(),
        .dbg_occ_w(), .dbg_occ_r(), .ovf_pulse(), .ovf_cnt()
    );
    assign close_req = !cl_empty && dp_rst_n && cl_dout[4];
    assign close_id  = cl_dout[3:0];

    // 事件 FIFO 的 drop 在 **写域 DP**（F1/F5）；close 的 drop 在 app 域。
    // RX FIFO 写域占用（写域 = DP）用于 W97[31:21]（声明在上方 FIFO 段）。

    // ---------------------------------------------------- app_tx_ready CDC
    // F6: DP 先寄存 1 拍；F12: 32 位（2×16）移位寄存器。
    reg [15:0] app_tx_ready_dp_r;
    always @(posedge dp_clk or negedge dp_rst_n)
        if (!dp_rst_n) app_tx_ready_dp_r <= 16'd0;
        else           app_tx_ready_dp_r <= app_tx_ready;

    reg [31:0] ready_sr;
    always @(posedge app_clk or negedge app_rst_n)
        if (!app_rst_n) ready_sr <= 32'd0;
        else            ready_sr <= {ready_sr[15:0], app_tx_ready_dp_r};
    assign core_app_tx_ready = ready_sr[31:16];

    // ------------------------------------------------------- board resets
    // 粘滞位/arming 只由板级 reset_n 复位（H5）。
    reg [1:0] rstn_dp_sr;
    always @(posedge dp_clk or negedge reset_n)
        if (!reset_n) rstn_dp_sr <= 2'b00;
        else          rstn_dp_sr <= {rstn_dp_sr[0], 1'b1};
    wire rstn_dp_board = rstn_dp_sr[1];

    reg [1:0] rstn_app_sr;
    always @(posedge app_clk or negedge reset_n)
        if (!reset_n) rstn_app_sr <= 2'b00;
        else          rstn_app_sr <= {rstn_app_sr[0], 1'b1};
    wire rstn_app_board = rstn_app_sr[1];

    // ------------------------------------------------------ arming / edges
    reg [1:0] app_rst_sync;
    always @(posedge dp_clk or negedge rstn_dp_board)
        if (!rstn_dp_board) app_rst_sync <= 2'b11;
        else                app_rst_sync <= {app_rst_sync[0], app_rst_n};
    wire app_rst_n_dp = app_rst_sync[1];

    reg [1:0] locked_sync;
    always @(posedge dp_clk or negedge rstn_dp_board)
        if (!rstn_dp_board) locked_sync <= 2'b00;
        else                locked_sync <= {locked_sync[0], locked_app};
    wire locked_dp = locked_sync[1];

    reg [10:0] arm_cnt;
    always @(posedge dp_clk or negedge rstn_dp_board)
        if (!rstn_dp_board)                 arm_cnt <= 11'd0;
        else if (arm_cnt != 11'd1024)       arm_cnt <= arm_cnt + 11'd1;
    wire armed = (arm_cnt == 11'd1024);
    wire app_alive = armed && app_rst_n_dp;

    reg app_rst_prev, app_rst_seen;
    always @(posedge dp_clk or negedge rstn_dp_board) begin
        if (!rstn_dp_board) begin app_rst_prev <= 1'b1; app_rst_seen <= 1'b0; end
        else begin
            app_rst_prev <= app_rst_n_dp;
            if (armed && app_rst_prev && !app_rst_n_dp) app_rst_seen <= 1'b1;
        end
    end

    reg dp_rst_prev, dp_rst_seen;
    always @(posedge dp_clk or negedge rstn_dp_board) begin
        if (!rstn_dp_board) begin dp_rst_prev <= 1'b1; dp_rst_seen <= 1'b0; end
        else begin
            dp_rst_prev <= dp_rst_n;
            if (armed && dp_rst_prev && !dp_rst_n) dp_rst_seen <= 1'b1;
        end
    end

    // ------------------------------------------------------- drop sticky
    reg drop_ev_sticky;   // DP
    always @(posedge dp_clk or negedge rstn_dp_board)
        if (!rstn_dp_board) drop_ev_sticky <= 1'b0;
        else if (drop_ev)   drop_ev_sticky <= 1'b1;

    reg drop_cl_sticky;   // app
    always @(posedge app_clk or negedge rstn_app_board)
        if (!rstn_app_board) drop_cl_sticky <= 1'b0;
        else if (drop_cl)    drop_cl_sticky <= 1'b1;

    reg [1:0] drop_cl_sync;
    always @(posedge dp_clk or negedge rstn_dp_board)
        if (!rstn_dp_board) drop_cl_sync <= 2'b00;
        else                drop_cl_sync <= {drop_cl_sync[0], drop_cl_sticky};

    // per-conn mismatch sticky (app 域), 2FF 到 DP
    reg [7:0] mm_sticky;
    integer mi;
    always @(posedge app_clk or negedge rstn_app_board) begin
        if (!rstn_app_board) mm_sticky <= 8'd0;
        else begin
            for (mi = 0; mi < 8; mi = mi + 1)
                if (|core_dbg_inst_mismatch[mi*32 +: 32]) mm_sticky[mi] <= 1'b1;
        end
    end
    reg [7:0] mm_sync0, mm_sync;
    always @(posedge dp_clk or negedge rstn_dp_board)
        if (!rstn_dp_board) begin mm_sync0 <= 8'd0; mm_sync <= 8'd0; end
        else begin
            mm_sync0 <= mm_sticky;      // 第一级（可能亚稳）
            mm_sync  <= mm_sync0;       // 第二级（W97 只用这一级）
        end

    // LED 两级（不需要相干，只作"活着"指示）
    reg [3:0] led_sync0, led_sync;
    always @(posedge dp_clk or negedge rstn_dp_board)
        if (!rstn_dp_board) begin led_sync0 <= 4'd0; led_sync <= 4'd0; end
        else begin
            led_sync0 <= core_led;
            led_sync  <= led_sync0;
        end
    assign led = led_sync;

    // ----------------------------------------------------- stats handshake
    // hold: [31:0] tx_bytes ... [319:288] up_pend; [323:320] close_pend_max
    reg [323:0] st_hold;
    reg         st_ack;

    reg        st_req;
    reg [1:0]  st_ack_sync;
    reg        st_req_seen;
    reg [9:0]  st_tick;
    reg        st_wait;
    reg [12:0] st_to;
    reg        st_stale;
    reg        st_to_sticky;
    reg [323:0] st_shadow;

    reg [1:0] st_req_sync;
    always @(posedge app_clk or negedge rstn_app_board) begin
        if (!rstn_app_board) st_req_sync <= 2'b00;
        else                st_req_sync <= {st_req_sync[0], st_req};
    end

    always @(posedge app_clk or negedge rstn_app_board) begin
        if (!rstn_app_board) begin
            st_hold <= 324'd0;
            st_ack  <= 1'b0;
        end else if (st_req_sync[1] != st_ack) begin
            st_hold <= {core_close_pend_max, core_up_pend, core_sw_apply, core_sw_req,
                        core_up_ev, core_bp, core_frmwait, core_mismatch,
                        core_rx_bytes, core_tx_frames, core_tx_bytes};
            st_ack  <= st_req_sync[1];
        end
    end

    always @(posedge dp_clk or negedge rstn_dp_board) begin
        if (!rstn_dp_board) begin
            st_req <= 1'b0; st_ack_sync <= 2'b00; st_req_seen <= 1'b0;
            st_tick <= 10'd0; st_wait <= 1'b0; st_to <= 13'd0;
            st_stale <= 1'b0; st_to_sticky <= 1'b0; st_shadow <= 324'd0;
        end else begin
            st_ack_sync <= {st_ack_sync[0], st_ack};

            if (st_ack_sync[1] != st_req_seen) begin
                st_req_seen <= st_ack_sync[1];
                st_shadow   <= st_hold;         // hold 在 ack 前已稳定
                st_wait     <= 1'b0;
                st_stale    <= 1'b0;
                st_to       <= 13'd0;
            end else if (!st_wait) begin
                if (st_tick == 10'd1023) begin
                    st_tick <= 10'd0;
                    st_req  <= ~st_req;
                    st_wait <= 1'b1;
                    st_to   <= 13'd0;
                end else begin
                    st_tick <= st_tick + 10'd1;
                end
            end else if (app_alive) begin
                if (st_to != 13'd4095) begin
                    st_to <= st_to + 13'd1;
                end else begin
                    st_wait      <= 1'b0;
                    st_stale     <= 1'b1;
                    st_to_sticky <= 1'b1;
                    st_tick      <= 10'd0;
                end
            end
        end
    end

    assign stat_tx_bytes        = st_shadow[31:0];
    assign stat_tx_frames       = st_shadow[63:32];
    assign stat_rx_bytes        = st_shadow[95:64];
    assign stat_mismatch        = st_shadow[127:96];
    assign stat_frmwait_cyc     = st_shadow[159:128];
    assign stat_bp_cyc          = st_shadow[191:160];
    assign stat_up_ev           = st_shadow[223:192];
    assign stat_sw_req          = st_shadow[255:224];
    assign stat_sw_apply        = st_shadow[287:256];
    assign stat_up_pend         = st_shadow[319:288];
    assign stat_close_pend_max  = st_shadow[323:320];

    // ------------------------------------------------------------- W97
    // [0]/[1] = 0（TX/RX 无丢字由握手同式 + 静态门保证）
    // [2] ev drop; [3] close drop; [4] current stale; [5] locked;
    // [6] app reset seen; [7] timeout sticky;
    // [15:8] per-conn mismatch; [19:16] close_pend_max;
    // [20] dp reset seen; [31:21] RX FIFO occupancy (9b).
    assign cdc_status[0]  = 1'b0;
    assign cdc_status[1]  = 1'b0;
    assign cdc_status[2]  = drop_ev_sticky;
    assign cdc_status[3]  = drop_cl_sync[1];
    assign cdc_status[4]  = st_stale;
    assign cdc_status[5]  = locked_dp;
    assign cdc_status[6]  = app_rst_seen;
    assign cdc_status[7]  = st_to_sticky;
    assign cdc_status[15:8]  = mm_sync;
    assign cdc_status[19:16] = st_shadow[323:320];
    assign cdc_status[20] = dp_rst_seen;
    assign cdc_status[31:21] = {2'b0, rx_occ_w};

endmodule
