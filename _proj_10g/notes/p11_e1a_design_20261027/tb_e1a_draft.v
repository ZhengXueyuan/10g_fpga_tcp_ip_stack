`timescale 1ns/1ps
// ===========================================================================
// tb_e1a_draft.v -- E1a-1 unit gate (DRAFT; not yet wired into sim/).
//   DUT = tcp_tx_frame with TCP_TX_OVL + E1A_EN=1. Static rb_* / CAM inputs;
//   win_open is driven directly, m_axis_tready=1.
//   Checks:
//     A) frame 1: first word held 200 cycles with win_open=0 => 1 event,
//        e1a_sum == e1a_max, e1a_max in bin1 (128..255).
//     B) frame 2: no wait => 2 events, max unchanged (or larger), sum grows.
//     C) one pure ACK control frame => no E1a event (ctrl filtered).
//   The exact service time is not asserted; only hold+service bounds.
// ===========================================================================
module tb_e1a_draft;
    reg clk = 1'b0;
    always #3.2 clk = ~clk;            // 156.25 MHz
    reg rst_n = 1'b0;

    reg [63:0] s_tdata = 64'd0;
    reg [7:0]  s_tkeep = 8'hFF;
    reg        s_tvalid = 1'b0, s_tlast = 1'b0;
    reg [3:0]  s_tid = 4'd0;
    wire       s_tready;

    reg        ack_req = 1'b0, ack_syn = 1'b0;
    reg [3:0]  ack_id = 4'd0;
    reg [31:0] ack_val = 32'd0;
    reg [15:0] ack_seen_i = 16'hFFFF;
    reg        ack_fin = 1'b0, ack_rst = 1'b0;
    reg [15:0] fin_req = 16'd0, rst_req = 16'd0;
    reg        cfg_up = 1'b0;
    reg [3:0]  cfg_up_id = 4'd0;
    reg        wu_req = 1'b0;
    reg [3:0]  wu_id = 4'd0;
    reg [31:0] wu_val = 32'd0;
    wire       wu_gnt;

    wire [3:0]  rb_id;
    reg  [31:0] rb_snd_nxt = 32'd0, rb_rcv_nxt = 32'd0, rb_snd_una = 32'd0;
    reg  [15:0] rb_rcv_wnd = 16'hFFFF, rb_snd_wnd = 16'hFFFF;
    reg  [3:0]  rb_state = 4'd1;
    reg         win_open = 1'b0;
    reg  [15:0] win_inflight = 16'd0, win_wnd_eff = 16'hFFFF;

    reg         retx_req = 1'b0;
    reg  [3:0]  retx_id = 4'd0;
    wire        retx_gnt;
    wire [31:0] stat_retx, o_retx_hi;
    wire        o_retx_active;
    wire [3:0]  o_retx_id;
    wire        upd_wr;
    wire [3:0]  upd_id;
    wire [2:0]  upd_sel;
    wire [31:0] upd_val;

    wire [3:0]  cam_rd_id;
    reg  [47:0] cam_rd_dmac = 48'h0011_2233_4455;
    reg  [31:0] cam_rd_sip = 32'hC0A8_6401;
    reg  [15:0] cam_rd_sport = 16'd40000, cam_rd_dport = 16'd8080;
    reg  [31:0] cam_rd_dip = 32'hC0A8_6402;
    reg         cam_rd_port = 1'b0;
    reg  [47:0] cfg_src_mac = 48'h000A_3501_FEC0;
    reg  [31:0] cfg_src_ip = 32'hC0A8_6402;
    wire        o_port;

    wire        ext_retx_wr_en, ext_retx_rd_en;
    wire [3:0]  ext_retx_w_conn, ext_retx_w_n, ext_retx_r_conn;
    wire [15:0] ext_retx_w_seq, ext_retx_r_seq;
    wire [63:0] ext_retx_w_data;
    reg  [63:0] ext_retx_r_data = 64'd0;

    wire [63:0] m_tdata;
    wire [7:0]  m_tkeep;
    wire        m_tvalid, m_tlast;
    reg         m_tready = 1'b1;

    wire [31:0] stat_frames, stat_bytes, stat_ack, stat_ack_drop, stat_eend,
                stat_drop_len, stat_fin, stat_rst, stat_tlast_in,
                stat_winstall, stat_winstall_cap, stat_win_at;
    wire [319:0] e1a_hist;
    wire [31:0]  e1a_sum, e1a_max;

    tcp_tx_frame #(.RING_CAP(16'hF000), .PERSIST_EN(1'b0),
                   .E1A_EN(1'b1)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tdata(s_tdata), .s_axis_tkeep(s_tkeep),
        .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready),
        .s_axis_tlast(s_tlast), .s_axis_tid(s_tid),
        .ack_req(ack_req), .ack_id(ack_id), .ack_val(ack_val), .ack_syn(ack_syn),
        .ack_seen_i(ack_seen_i),
        .ack_fin(ack_fin), .ack_rst(ack_rst),
        .fin_req(fin_req), .rst_req(rst_req),
        .cfg_up(cfg_up), .cfg_up_id(cfg_up_id),
        .o_fin_sent(), .o_rst_sent(),
        .wu_req(wu_req), .wu_id(wu_id), .wu_val(wu_val), .wu_gnt(wu_gnt),
        .rb_id(rb_id), .rb_snd_nxt(rb_snd_nxt), .rb_rcv_nxt(rb_rcv_nxt),
        .rb_rcv_wnd(rb_rcv_wnd), .rb_snd_una(rb_snd_una),
        .rb_snd_wnd(rb_snd_wnd), .rb_state(rb_state),
        .win_open(win_open), .win_inflight(win_inflight), .win_wnd_eff(win_wnd_eff),
        .retx_req(retx_req), .retx_id(retx_id), .retx_gnt(retx_gnt),
        .stat_retx(stat_retx),
        .o_retx_hi(o_retx_hi), .o_retx_active(o_retx_active), .o_retx_id(o_retx_id),
        .upd_wr(upd_wr), .upd_id(upd_id), .upd_sel(upd_sel), .upd_val(upd_val),
        .cam_rd_id(cam_rd_id), .cam_rd_dmac(cam_rd_dmac), .cam_rd_sip(cam_rd_sip),
        .cam_rd_sport(cam_rd_sport), .cam_rd_dport(cam_rd_dport),
        .cam_rd_dip(cam_rd_dip), .cam_rd_port(cam_rd_port),
        .cfg_src_mac(cfg_src_mac), .cfg_src_ip(cfg_src_ip), .o_port(o_port),
        .ext_retx_wr_en(ext_retx_wr_en), .ext_retx_w_conn(ext_retx_w_conn),
        .ext_retx_w_seq(ext_retx_w_seq), .ext_retx_w_data(ext_retx_w_data),
        .ext_retx_w_n(ext_retx_w_n), .ext_retx_rd_en(ext_retx_rd_en),
        .ext_retx_r_conn(ext_retx_r_conn), .ext_retx_r_seq(ext_retx_r_seq),
        .ext_retx_r_data(ext_retx_r_data),
        .m_axis_tdata(m_tdata), .m_axis_tkeep(m_tkeep),
        .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready), .m_axis_tlast(m_tlast),
        .stat_frames(stat_frames), .stat_bytes(stat_bytes), .stat_ack(stat_ack),
        .stat_ack_drop(stat_ack_drop), .stat_eend(stat_eend),
        .stat_drop_len(stat_drop_len), .stat_fin(stat_fin), .stat_rst(stat_rst),
        .stat_tlast_in(stat_tlast_in),
        .stat_winstall(stat_winstall), .stat_winstall_cap(stat_winstall_cap),
        .o_win_at_winstall(stat_win_at),
        .dbg_wnd_open(), .dbg_pay_full(), .dbg_sready(), .dbg_saxis_tvalid(),
        .dbg_plen_r(), .dbg_state(), .dbg_pay_wptr(), .dbg_pay_rptr(),
        .dbg_pay_full2(), .dbg_pay_empty(), .dbg_plen(),
        .e1a_hist(e1a_hist), .e1a_sum_total(e1a_sum), .e1a_max_total(e1a_max)
    );

    integer cyc_assert_fail = 0;
    always @(posedge clk) begin
        // M-1: start_data (write tag) and done_ev (read tag) must never be same cycle
        if (rst_n && dut.start_data && dut.g_e1a.done_ev)
            cyc_assert_fail <= cyc_assert_fail + 1;
        if (rst_n && dut.tx_state == 3'd4 && (!dut.m_axis_tvalid || dut.m_axis_tready))
            $display("DBG_TD ctrl=%b isapp=%b bank=%b frames=%0d ack=%0d",
                     dut.tx_is_ctrl, dut.g_e1a.f_is_app_tx, dut.tx_bank,
                     stat_frames, stat_ack);
    end

    function [31:0] hist_total;
        input [319:0] h;
        integer k;
        begin
            hist_total = 32'd0;
            for (k = 0; k < 10; k = k + 1) hist_total = hist_total + h[k*32 +: 32];
        end
    endfunction

    task send_frame;
        input integer hold;
        input [63:0] w0;
        input [63:0] w1;
        integer t;
        begin
            // ⚠️ 数据只在 negedge 改: posedge 同拍改会让 DUT 采到旧字 (工程坑 17 同族).
            @(negedge clk);
            s_tdata = w0; s_tkeep = 8'hFF; s_tlast = 1'b0;
            s_tvalid = 1'b1; s_tid = 4'd0;
            for (t = 0; t < hold; t = t + 1) @(negedge clk);
            win_open = 1'b1;
            while (!s_tready) @(negedge clk);   // 下一 posedge 接受首字
            @(negedge clk);                     // 首字已被接受后才换第二字
            s_tdata = w1; s_tkeep = 8'hFF; s_tlast = 1'b1;
            while (!s_tready) @(negedge clk);   // 下一 posedge 接受末字
            @(negedge clk);
            s_tvalid = 1'b0;
            t = 0;
            while (stat_frames == 0 && t < 400) begin @(negedge clk); t = t + 1; end
        end
    endtask

    integer fail = 0;
    integer f0;
    initial begin
        #1;
        rst_n = 1'b0; win_open = 1'b0; s_tvalid = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // ---- A) one waited frame: 200-cycle hold ----
        send_frame(200, 64'h0102_0304_0506_0708, 64'h1112_1314_1516_1718);
        #20;
        f0 = hist_total(e1a_hist);
        $display("E1A_A hist_total=%0d sum=%0d max=%0d stat_frames=%0d",
                 f0, e1a_sum, e1a_max, stat_frames);
        if (f0 != 1) begin $display("FAIL A hist_total=%0d (want 1)", f0); fail = fail + 1; end
        if (e1a_sum != e1a_max) begin $display("FAIL A sum!=max"); fail = fail + 1; end
        if (e1a_max < 200 || e1a_max > 260) begin
            $display("FAIL A max=%0d not in [200,260]", e1a_max); fail = fail + 1;
        end
        if ((e1a_hist[3*32 +: 32]) != 1) begin
            $display("FAIL A bin3=%0d (want 1)", e1a_hist[3*32 +: 32]); fail = fail + 1;
        end

        // ---- B) no-wait frame: total 2, sum grows, max not smaller ----
        begin : b_frame
            integer t;
            reg [31:0] sum_before, max_before;
            sum_before = e1a_sum; max_before = e1a_max;
            @(negedge clk);
            s_tdata = 64'h2122_2324_2526_2728; s_tkeep = 8'hFF; s_tlast = 1'b0;
            s_tvalid = 1'b1; s_tid = 4'd0; win_open = 1'b1;
            while (!s_tready) @(negedge clk);
            @(negedge clk);
            s_tdata = 64'h3132_3334_3536_3738; s_tlast = 1'b1;
            while (!s_tready) @(negedge clk);
            @(negedge clk);
            s_tvalid = 1'b0;
            t = 0;
            while (stat_frames != 2 && t < 400) begin @(negedge clk); t = t + 1; end
            #20;
            $display("E1A_B hist_total=%0d sum=%0d max=%0d frames=%0d",
                     hist_total(e1a_hist), e1a_sum, e1a_max, stat_frames);
            if (hist_total(e1a_hist) != 2) begin
                $display("FAIL B hist_total=%0d (want 2)", hist_total(e1a_hist)); fail = fail + 1;
            end
            if (e1a_sum <= sum_before) begin $display("FAIL B sum did not grow"); fail = fail + 1; end
            if (e1a_max < max_before) begin $display("FAIL B max decreased"); fail = fail + 1; end
        end

        // ---- C) control frame must not count ----
        begin : c_ctrl
            integer t;
            reg [31:0] h_before, a_before;
            h_before = hist_total(e1a_hist);
            a_before = stat_ack;
            ack_req = 1'b1; ack_id = 4'd0; ack_val = 32'h1234_5678; ack_syn = 1'b0;
            @(posedge clk); ack_req = 1'b0;
            t = 0;
            while (stat_ack == a_before && t < 200) begin @(posedge clk); t = t + 1; end
            #20;
            $display("E1A_C hist_total=%0d (before=%0d) stat_ack=%0d",
                     hist_total(e1a_hist), h_before, stat_ack);
            if (stat_ack == a_before) begin $display("FAIL C no ACK sent"); fail = fail + 1; end
            if (hist_total(e1a_hist) != h_before) begin
                $display("FAIL C control frame counted"); fail = fail + 1;
            end
        end

        // ---- D) H-1: present -> withdraw -> re-present; stale pending must NOT count ----
        begin : d_withdraw
            integer t;
            reg [31:0] sum_before, max_before;
            sum_before = e1a_sum; max_before = e1a_max;
            @(negedge clk);
            s_tdata = 64'h4142_4344_4546_4748; s_tkeep = 8'hFF; s_tlast = 1'b0;
            s_tvalid = 1'b1; win_open = 1'b0;
            repeat (100) @(negedge clk);          // pending would latch here
            s_tvalid = 1'b0;                      // withdraw: pending must clear
            repeat (10) @(negedge clk);
            // re-present with win_open=1 immediately (no wait)
            s_tdata = 64'h5152_5354_5556_5758; s_tkeep = 8'hFF; s_tlast = 1'b0;
            s_tvalid = 1'b1; win_open = 1'b1;
            while (!s_tready) @(negedge clk);
            @(negedge clk);
            s_tdata = 64'h6162_6364_6566_6768; s_tlast = 1'b1;
            while (!s_tready) @(negedge clk);
            @(negedge clk); s_tvalid = 1'b0;
            t = 0;
            while (stat_frames != 4 && t < 400) begin @(negedge clk); t = t + 1; end
            #20;
            $display("E1A_D hist_total=%0d sum=%0d max=%0d frames=%0d",
                     hist_total(e1a_hist), e1a_sum, e1a_max, stat_frames);
            if (hist_total(e1a_hist) != 3) begin
                $display("FAIL D hist_total=%0d (want 3)", hist_total(e1a_hist)); fail = fail + 1;
            end
            // If stale pending survived, the re-presented frame's L would include the 100-cycle gap.
            if ((e1a_sum - sum_before) > 50) begin
                $display("FAIL D sum grew %0d > 50 (stale pending?)", e1a_sum - sum_before);
                fail = fail + 1;
            end
            if (e1a_max != max_before) begin
                $display("FAIL D max changed %0d -> %0d", max_before, e1a_max); fail = fail + 1;
            end
        end

        if (cyc_assert_fail != 0) begin
            $display("FAIL M1 start_data&&done_ev same-cycle n=%0d", cyc_assert_fail);
            fail = fail + 1;
        end
        if (fail == 0) $display("TB_E1A_PASS");
        else           $display("TB_E1A_FAIL n=%0d", fail);
        $finish;
    end

    // timeout guard
    initial begin
        #200000;
        $display("TB_E1A_TIMEOUT");
        $finish;
    end
endmodule
