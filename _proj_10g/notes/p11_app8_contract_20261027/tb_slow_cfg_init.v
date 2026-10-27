`timescale 1ns/1ps
// tb_slow_cfg_init — F1 (REVIEW_V5): ADD 期 TCB rcv_wnd 初值 = RCV_WND_INIT
//   两臂: 0x3000 (C4 8x12KB) / 默认 0xC000 (2x48KB, 零回归).
//   变异门 (run_slowcfg_mut): 把 tcb_val_c 写死 0xC000 ⇒ 0x3000 臂必须红.
module tb_slow_cfg_init;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;

    reg  [31:0] tdata; reg tvalid; wire tready;
    wire upd_wr_a, upd_wr_b;
    wire [3:0]  upd_id_a, upd_id_b;
    wire [2:0]  upd_sel_a, upd_sel_b;
    wire [31:0] upd_val_a, upd_val_b;
    wire [31:0] stat_add_a, stat_add_b;
    wire ev_up_a, ev_up_b;

    slow_cfg_adp #(.RCV_WND_INIT(16'h3000)) u_a (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tdata(tdata), .s_axis_tvalid(tvalid), .s_axis_tready(tready),
        .cam_cfg_wr(), .cam_cfg_addr(), .cam_cfg_sip(), .cam_cfg_dip(),
        .cam_cfg_sport(), .cam_cfg_dport(), .cam_cfg_dmac(),
        .upd_wr(upd_wr_a), .upd_id(upd_id_a), .upd_sel(upd_sel_a),
        .upd_val(upd_val_a), .cfg_gnt(1'b1),
        .stat_add(stat_add_a), .stat_del(), .o_busy(),
        .ev_up(ev_up_a), .ev_down(), .ev_slot(),
        .ev_peer_ip(), .ev_peer_port(), .ev_peer_mac()
    );
    slow_cfg_adp u_b (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tdata(tdata), .s_axis_tvalid(tvalid), .s_axis_tready(),
        .cam_cfg_wr(), .cam_cfg_addr(), .cam_cfg_sip(), .cam_cfg_dip(),
        .cam_cfg_sport(), .cam_cfg_dport(), .cam_cfg_dmac(),
        .upd_wr(upd_wr_b), .upd_id(upd_id_b), .upd_sel(upd_sel_b),
        .upd_val(upd_val_b), .cfg_gnt(1'b1),
        .stat_add(stat_add_b), .stat_del(), .o_busy(),
        .ev_up(ev_up_b), .ev_down(), .ev_slot(),
        .ev_peer_ip(), .ev_peer_port(), .ev_peer_mac()
    );

    reg [31:0] val3_a, val3_b;
    always @(posedge clk) begin
        if (upd_wr_a && (upd_sel_a == 3'd3)) val3_a <= upd_val_a;
        if (upd_wr_b && (upd_sel_b == 3'd3)) val3_b <= upd_val_b;
    end

    integer errors=0, checks=0;
    task chk; input [255:0] m; input [31:0] g; input [31:0] e; begin
        checks=checks+1; if (g!==e) begin errors=errors+1;
        $display("FAIL %0s got=%08x exp=%08x", m, g, e); end end endtask

    integer i;
    reg [31:0] wd;
    initial begin
        tvalid=0; tdata=0;
        repeat (4) @(posedge clk);
        rst_n=1;
        @(negedge clk);
        // 8 词 ADD 记录: w0 cmd=0 slot=3, bits[19:16]=wscale=10
        for (i=0; i<8; i=i+1) begin
            case (i)
                0: wd = 32'h000A_0003;
                1: wd = 32'h0A010203; // smac[47:32]...
                2: wd = 32'h04050607;
                3: wd = 32'hC0A86401; // peer ip 192.168.100.1
                4: wd = 32'h00005000; // peer port 0x5000
                5: wd = 32'h0000FF00; // peer wnd
                6: wd = 32'h2000_0001;// rcv_nxt
                7: wd = 32'h3000_0001;// snd_nxt
            endcase
            @(negedge clk); tvalid=1; tdata=wd;
            @(posedge clk);
            while (!tready) begin @(negedge clk); @(posedge clk); end
        end
        @(negedge clk); tvalid=0;
        repeat (30) @(posedge clk);
        chk("A(0x3000) rcv_wnd", val3_a, 32'h0000_3000);
        chk("B(default) rcv_wnd", val3_b, 32'h0000_C000);
        chk("A stat_add", stat_add_a, 32'd1);
        chk("B stat_add", stat_add_b, 32'd1);
        repeat (4) @(posedge clk);
        if (errors==0) $display("TB_SLOW_CFG_PASS checks=%0d", checks);
        else           $display("TB_SLOW_CFG_FAIL errors=%0d", errors);
        $finish;
    end
    initial begin #200000; $display("TB_SLOW_CFG_FAIL timeout"); $finish; end
endmodule
