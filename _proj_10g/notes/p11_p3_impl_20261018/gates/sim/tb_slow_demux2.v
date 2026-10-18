`timescale 1ns/1ps
//=============================================================================
// tb_slow_demux2.v — P11 P3 G-P3-4 (慢 demux): 帧级口分离 + 帧内锁口
//=============================================================================
module tb_slow_demux2;
    reg clk=0, rst_n=0; always #5 clk=~clk;
    reg [63:0] s_tdata=0; reg [7:0] s_tkeep=8'hFF;
    reg s_tvalid=0, s_tlast=0, s_port=0;
    reg d0_tready=1, d1_tready=1;
    wire s_tready, d0_tvalid, d1_tvalid, d0_tlast, d1_tlast;
    wire [63:0] d0_tdata, d1_tdata; wire [7:0] d0_tkeep, d1_tkeep;
    wire [31:0] st_pc, st_f0, st_f1;

    slow_demux2 dut (
        .clk(clk), .rst_n(rst_n),
        .s_tdata(s_tdata), .s_tkeep(s_tkeep), .s_tvalid(s_tvalid),
        .s_tready(s_tready), .s_tlast(s_tlast), .s_port(s_port),
        .d0_tdata(d0_tdata), .d0_tkeep(d0_tkeep), .d0_tvalid(d0_tvalid),
        .d0_tready(d0_tready), .d0_tlast(d0_tlast),
        .d1_tdata(d1_tdata), .d1_tkeep(d1_tkeep), .d1_tvalid(d1_tvalid),
        .d1_tready(d1_tready), .d1_tlast(d1_tlast),
        .stat_port_change(st_pc), .stat_frames0(st_f0), .stat_frames1(st_f1)
    );

    integer errors=0;
    task chk(input cond, input [255:0] msg);
        begin if(!cond) begin errors=errors+1; $display(" FAIL: %0s", msg); end end
    endtask

    integer d0_words=0, d1_words=0, tl0=0, tl1=0;
    reg bad_side=0;
    always @(posedge clk) begin
        if (rst_n && d0_tvalid && d0_tready) begin d0_words=d0_words+1; if (d1_tvalid) bad_side=1;
            if (d0_tlast) tl0=tl0+1; end
        if (rst_n && d1_tvalid && d1_tready) begin d1_words=d1_words+1; if (d0_tvalid) bad_side=1;
            if (d1_tlast) tl1=tl1+1; end
    end

    task automatic send(input integer port, input [7:0] id, input integer n, input integer chg_at);
        integer k;
        reg pbit;
        begin
            pbit = (port != 0);
            for (k=0;k<n;k=k+1) begin
                @(negedge clk);
                s_tdata={56'd0, k[7:0], id};
                s_tvalid=1; s_tlast=(k==n-1);
                // 帧内改口: 从 chg_at 拍起把 s_port 翻转 (帧应仍走锁存口)
                s_port=(chg_at>=0 && k>=chg_at) ? ~pbit : pbit;
                #0;
                while (!s_tready) @(negedge clk);
            end
            @(negedge clk); s_tvalid=0; s_tlast=0;
        end
    endtask

    initial begin
        $display("=== G-P3-4 slow_demux2 ===");
        rst_n=0; repeat(3) @(negedge clk); rst_n=1; @(negedge clk);
        send(0, 8'h10, 3, -1);
        repeat(2) @(negedge clk);
        chk(d0_words==3 && d1_words==0, "A port0 frame -> d0 only");
        send(1, 8'h20, 3, -1);
        repeat(2) @(negedge clk);
        chk(d0_words==3 && d1_words==3, "B port1 frame -> d1 only");
        // 帧内改口: 第 2 拍起 s_port 翻转, 整帧仍走锁存口 d0
        send(0, 8'h30, 4, 1);
        repeat(2) @(negedge clk);
        chk(d0_words==7 && d1_words==3, "C frame-internal port change stays on latched d0");
        chk(st_pc >= 1, "C stat_port_change counted");
        send(1, 8'h40, 2, -1);
        repeat(3) @(negedge clk);
        chk(d1_words==5, "D second port1 frame completes");
        chk(st_f0==2, "D frames0 = 2 (0x10,0x30)");
        chk(st_f1==2, "D frames1 = 2 (0x20,0x40)");
        chk(tl0==2 && tl1==2, "D tlast routed with each frame");
        chk(!bad_side, "D no simultaneous d0/d1 valid");

        if (errors==0) $display("SLOW_DEMUX2 TB PASS");
        else           $display("SLOW_DEMUX2 TB FAIL errors=%0d", errors);
        $finish;
    end
    initial begin #200000; $display("SLOW_DEMUX2 TB FAIL (timeout)"); $finish; end
endmodule
