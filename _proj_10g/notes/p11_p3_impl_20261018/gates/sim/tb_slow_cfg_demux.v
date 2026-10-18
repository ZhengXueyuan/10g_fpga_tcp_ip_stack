`timescale 1ns/1ps
//=============================================================================
// tb_slow_cfg_demux.v — P11 P3 G-P3-4 (cfg 1:2 demux)
//   A: ADD 按 w2 判口 + slot_port 更新
//   B: DEL 按 slot_port 路由 (不依赖 w2)
//   C: DEL 的 w2 与 slot_port 不一致 -> stat_cfg_port_mismatch++
//   D: slot >= 8 -> 整条丢弃 + stat_slot_oor++
//   E: back-to-back DEL -> ADD: DEL 走旧口, ADD 走新口并更新映射
//   F: 反压 (d0 停) 时记录保持, 恢复后完整播出
//=============================================================================
module tb_slow_cfg_demux;
    localparam [31:0] IP_A = 32'hC0A86402;
    localparam [31:0] IP_B = 32'hC0A86404;
    reg clk=0, rst_n=0; always #5 clk=~clk;

    reg [31:0] s_tdata=0; reg s_tvalid=0; wire s_tready;
    wire [31:0] d0_tdata, d1_tdata;
    wire d0_tvalid, d1_tvalid;
    reg d0_tready=1, d1_tready=1;
    wire [7:0] slot_port;
    wire [31:0] st_oor, st_mis;

    slow_cfg_demux #(.IP_B(IP_B)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tdata(s_tdata), .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready),
        .d0_tdata(d0_tdata), .d0_tvalid(d0_tvalid), .d0_tready(d0_tready),
        .d1_tdata(d1_tdata), .d1_tvalid(d1_tvalid), .d1_tready(d1_tready),
        .slot_port(slot_port), .stat_slot_oor(st_oor),
        .stat_cfg_port_mismatch(st_mis)
    );

    integer errors=0;
    task chk(input cond, input [255:0] msg);
        begin if(!cond) begin errors=errors+1; $display(" FAIL: %0s", msg); end end
    endtask

    // 输出记录收集
    reg [31:0] q0 [0:63]; integer n0=0;
    reg [31:0] q1 [0:63]; integer n1=0;
    always @(posedge clk) begin
        if (rst_n && d0_tvalid && d0_tready) begin q0[n0]=d0_tdata; n0=n0+1; end
        if (rst_n && d1_tvalid && d1_tready) begin q1[n1]=d1_tdata; n1=n1+1; end
    end

    task automatic push(input integer cmd, input [3:0] slot, input [31:0] w2);
        integer k;
        begin
            for (k=0;k<8;k=k+1) begin
                @(negedge clk);
                s_tdata = (k==0) ? (32'h0 | (cmd[7:0] << 8) | slot[3:0]) :
                          (k==2) ? w2 : (32'h1000 + ({28'd0,slot}<<8) + k[7:0]);
                s_tvalid = 1;
                #0;
                while (!s_tready) @(negedge clk);
            end
            @(negedge clk); s_tvalid=0;
        end
    endtask

    task flush(input integer n); integer i; begin repeat(n) @(negedge clk); end endtask
    event ev_push;
    initial begin @ev_push; push(0, 4'd2, IP_A); end

    initial begin
        $display("=== G-P3-4 slow_cfg_demux ===");
        rst_n=0; repeat(3) @(negedge clk); rst_n=1; @(negedge clk);

        // A: ADD slot0 -> IP_A => d0
        push(0, 4'd0, IP_A); flush(12);
        chk(n0==8 && n1==0, "A ADD slot0/IP_A -> d0 (8 words)");
        chk(q0[0][15:8]==8'd0 && q0[0][3:0]==4'd0, "A d0 record header cmd/slot");
        chk(q0[2]==IP_A, "A d0 w2 = IP_A");
        chk(slot_port[0]==1'b0, "A slot_port[0] = 0");
        // A2: ADD slot1 -> IP_B => d1
        push(0, 4'd1, IP_B); flush(12);
        chk(n1==8, "A2 ADD slot1/IP_B -> d1");
        chk(slot_port[1]==1'b1, "A2 slot_port[1] = 1");

        // B: DEL slot1 (w2=IP_B) -> d1
        n0=0; n1=0;
        push(1, 4'd1, IP_B); flush(12);
        chk(n1==8 && n0==0, "B DEL slot1 -> d1 (slot_port)");

        // C: DEL slot1 with w2=IP_A (mismatch) -> still d1, counter++
        n0=0; n1=0;
        push(1, 4'd1, IP_A); flush(12);
        chk(n1==8 && n0==0, "C DEL mismatch still routes by slot_port -> d1");
        chk(st_mis==1, "C stat_cfg_port_mismatch = 1");

        // D: slot 8 -> dropped
        n0=0; n1=0;
        push(0, 4'd8, IP_A); flush(12);
        chk(n0==0 && n1==0, "D slot>=8 record dropped");
        chk(st_oor==1, "D stat_slot_oor = 1");
        chk(slot_port[0]==1'b0, "D mapping unchanged");

        // E: back-to-back DEL(slot0->old port0) + ADD(slot0->IP_B)
        n0=0; n1=0;
        // back-to-back = 记录之间无空闲 (顺序推两条; 输入 FIFO 承接第二条)
        push(1, 4'd0, 32'd0);
        push(0, 4'd0, IP_B);
        flush(24);
        chk(n0==8 && n1==8, "E DEL->d0 + ADD->d1 (both records played)");
        chk(slot_port[0]==1'b1, "E slot_port[0] updated to 1");
        // DEL 的 w2=0 => 不触发 mismatch
        chk(st_mis==1, "E w2=0 DEL does not count mismatch");

        // F: 反压: d0 停, 推一条 ADD(slot2->IP_A); 恢复后 8 词完整
        n0=0; n1=0; d0_tready=0;
        ->ev_push;
        flush(16);
        chk(n0==0 && d0_tvalid==1, "F record held under d0 backpressure");
        d0_tready=1;
        flush(20);
        chk(n0==8, "F record completes after d0 ready");

        if (errors==0) $display("SLOW_CFG_DEMUX TB PASS");
        else           $display("SLOW_CFG_DEMUX TB FAIL errors=%0d", errors);
        $finish;
    end
    initial begin #400000; $display("SLOW_CFG_DEMUX TB FAIL (timeout)"); $finish; end
endmodule
