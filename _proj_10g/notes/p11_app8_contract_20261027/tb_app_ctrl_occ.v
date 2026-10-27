`timescale 1ns/1ps
// tb_app_ctrl_occ — P11 APP8 v6 app_ctrl 每连接 fq (REVIEW_V5 O5)
//   判据: winq[0..7]=0x3000, occ[2]=0x3000, 其它 0
//         ⇒ redge[2]=rcv_nxt, redge[0]=rcv_nxt+0x3000
//         ⇒ TCB.rcv_wnd[2]=0, TCB.rcv_wnd[0]=0x3000
//   变异 (run_appocc_mut): occ_fq 改回 rx_occ_bytes ⇒ redge[2] 变 0x4000 ⇒ 必红.
module tb_app_ctrl_occ;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;

    wire [3:0] rc_id;
    reg  [31:0] rc_snd_nxt, rc_snd_una, rc_rcv_nxt;
    reg  [15:0] rc_snd_wnd;
    reg  [15:0] t_rcv_wnd [0:15];
    wire [15:0] rc_rcv_wnd = t_rcv_wnd[rc_id];
    wire [3:0]  rc_state = 4'd1; // ESTAB

    wire [3:0]  o_winq_rd_id;
    reg  [16:0] occ_tb [0:15];
    wire [16:0] i_occ_rd = occ_tb[o_winq_rd_id];

    wire fc_upd_wr, wu_req;
    wire [3:0] fc_upd_id, wu_id;
    wire [2:0] fc_upd_sel;
    wire [31:0] fc_upd_val, wu_val;

    app_ctrl #(.WIN_CAP(16'h3000), .WIN_POOL(16'h0000), .WIN_Q_MAX(16'h3000),
               .FIN_TO_LIM(18'd10), .PER_CONN_OCC(1'b1))
    u_dut (
        .clk(clk), .rst_n(rst_n),
        .ev_up(1'b0), .ev_down(1'b0), .ev_slot(4'd0),
        .ev_peer_ip(32'h0), .ev_peer_port(16'h0), .ev_peer_mac(48'h0),
        .rc_id(rc_id), .rc_snd_nxt(rc_snd_nxt), .rc_snd_una(rc_snd_una),
        .rc_rcv_nxt(rc_rcv_nxt), .rc_rcv_wnd(rc_rcv_wnd),
        .rc_snd_wnd(rc_snd_wnd), .rc_state(rc_state),
        .o_winq_rd_id(o_winq_rd_id), .i_winq_rd(16'd0),
        .o_winq_rd_id_ev(), .i_winq_rd_ev(16'd0),
        .o_quota_rel(), .o_quota_rel_slot(),
        .i_ev_up_done(1'b0), .i_ev_up_done_slot(4'd0),
        .rx_occ_bytes(17'd0),
        .fin_sent(16'd0), .rst_sent(16'd0),
        .fc_upd_wr(fc_upd_wr), .fc_upd_id(fc_upd_id), .fc_upd_sel(fc_upd_sel),
        .fc_upd_val(fc_upd_val), .fc_gnt(fc_upd_wr),
        .wu_req(wu_req), .wu_id(wu_id), .wu_val(wu_val), .wu_gnt(wu_req),
        .close_req(1'b0), .close_id(4'd0),
        .reg_addr(8'd0), .reg_wr(1'b0), .reg_wdata(32'd0), .reg_rdata(),
        .app_tx_ready(),
        .dbg_c0_state(), .dbg_c0_snd_nxt(), .dbg_c0_snd_una(),
        .dbg_c0_rcv_nxt(), .dbg_c0_rcv_wnd(), .dbg_c0_snd_wnd(),
        .dbg_estab_cnt(), .dbg_ev_cnt(),
        .dbg_redge0(), .dbg_winq0(), .dbg_wu_mark0(), .dbg_pool(),
        .stat_ev_up(), .stat_ev_down(), .stat_ev_drop(),
        .stat_cmd_close(), .stat_cmd_abort(),
        .stat_wu(), .stat_pool_exhaust(), .stat_fc_upd(),
        .stat_fc_wait_max(), .stat_slot_reuse(),
        .i_occ_rd(i_occ_rd), .i_occ_rd_id(o_winq_rd_id)
    );

    integer j, errors=0, checks=0;
    // TCB rcv_wnd model (fc 写)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (j = 0; j < 16; j = j + 1) t_rcv_wnd[j] <= 16'd0;
        end else if (fc_upd_wr) begin
            t_rcv_wnd[fc_upd_id] <= fc_upd_val[15:0];
        end
    end

    task chk; input [255:0] m; input [31:0] g; input [31:0] e; begin
        checks=checks+1; if (g!==e) begin errors=errors+1;
        $display("FAIL %0s got=%08x exp=%08x", m, g, e); end end endtask

    initial begin
        for (j = 0; j < 16; j = j + 1) occ_tb[j] = 17'd0;
        occ_tb[2] = 17'h3000;
        rc_snd_nxt = 32'h0000_2000; rc_snd_una = 32'h0000_2000;
        rc_rcv_nxt = 32'h0000_1000; rc_snd_wnd = 16'hFFFF;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);
        // 授权: 0..7 = 12KB (C4 8x12KB 合同); 8..15 = 0
        for (j = 0; j < 8; j = j + 1) u_dut.winq[j] = 16'h3000;
        for (j = 8; j < 16; j = j + 1) u_dut.winq[j] = 16'd0;
        repeat (400) @(posedge clk);
        $display("DBG redge0=%08x redge2=%08x rwnd0=%04x rwnd2=%04x",
                 u_dut.redge[0], u_dut.redge[2], t_rcv_wnd[0], t_rcv_wnd[2]);
        chk("O5 redge[2] = rcv_nxt (occ=winq)", u_dut.redge[2], 32'h0000_1000);
        chk("O5 redge[0] = rcv_nxt+winq",      u_dut.redge[0], 32'h0000_4000);
        chk("O5 redge[3] = rcv_nxt+winq",      u_dut.redge[3], 32'h0000_4000);
        chk("O5 TCB rcv_wnd[2]=0",             t_rcv_wnd[2], 16'h0000);
        chk("O5 TCB rcv_wnd[0]=winq",          t_rcv_wnd[0], 16'h3000);
        repeat (3) @(posedge clk);
        if (errors==0) $display("TB_APP_OCC_PASS checks=%0d", checks);
        else           $display("TB_APP_OCC_FAIL errors=%0d", errors);
        $finish;
    end
    initial begin #500000; $display("TB_APP_OCC_FAIL timeout"); $finish; end
endmodule
