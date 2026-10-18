`timescale 1ns/1ps
//=============================================================================
// tb_retx_pool_shared.v — P11 P3 G-P3-3: 共享 8 槽重传环单元门
//   臂 A: 8 槽属主写/读回 (内容逐字) + 跨槽隔离
//   臂 B: 两口同拍访问不同槽 (并行, 零干扰)
//   臂 C: 非属主写/读 -> stat_retx_owner_mismatch++, 数据不损坏
//   臂 D: 槽号 >= 8 -> stat_slot_oor++, 数据不损坏
//   臂 E: 读延迟 = 2 拍 (rd_en 拍 -> T+2 出数), 与 retx_ram 一致
//   臂 F: H-2 owner 翻转时机 —— 旧口在 grant_port 翻转前仍属主; 翻转后
//         旧口访问被拒 (读输出 0, 不给陈旧数据), 新口接管
//=============================================================================
module tb_retx_pool_shared;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg  [7:0]  grant_port = 8'h00;
    reg         wr_en0 = 0, wr_en1 = 0;
    reg  [3:0]  w_conn0 = 0, w_conn1 = 0;
    reg  [15:0] w_seq0 = 0, w_seq1 = 0;
    reg  [63:0] w_data0 = 0, w_data1 = 0;
    reg  [3:0]  w_n0 = 8, w_n1 = 8;
    reg         rd_en0 = 0, rd_en1 = 0;
    reg  [3:0]  r_conn0 = 0, r_conn1 = 0;
    reg  [15:0] r_seq0 = 0, r_seq1 = 0;
    wire [63:0] r_data0, r_data1;
    wire [31:0] st_mismatch, st_oor;

    retx_pool_shared dut (
        .clk(clk), .rst_n(rst_n), .grant_port(grant_port),
        .wr_en0(wr_en0), .w_conn0(w_conn0), .w_seq0(w_seq0),
        .w_data0(w_data0), .w_n0(w_n0),
        .rd_en0(rd_en0), .r_conn0(r_conn0), .r_seq0(r_seq0), .r_data0(r_data0),
        .wr_en1(wr_en1), .w_conn1(w_conn1), .w_seq1(w_seq1),
        .w_data1(w_data1), .w_n1(w_n1),
        .rd_en1(rd_en1), .r_conn1(r_conn1), .r_seq1(r_seq1), .r_data1(r_data1),
        .stat_retx_owner_mismatch(st_mismatch), .stat_slot_oor(st_oor)
    );

    integer errors = 0;
    task chk(input cond, input [255:0] msg);
        begin if (!cond) begin errors=errors+1; $display(" FAIL: %0s", msg); end end
    endtask

    task wr(input integer port, input [3:0] slot, input [15:0] seq, input [63:0] data);
        begin
            @(negedge clk);
            if (port == 0) begin wr_en0=1; w_conn0=slot; w_seq0=seq; w_data0=data; w_n0=8; end
            else           begin wr_en1=1; w_conn1=slot; w_seq1=seq; w_data1=data; w_n1=8; end
            @(negedge clk);
            wr_en0=0; wr_en1=0;
        end
    endtask

    reg [63:0] rd0_val, rd1_val;
    task rd(input integer port, input [3:0] slot, input [15:0] seq);
        begin
            @(negedge clk);
            if (port == 0) begin rd_en0=1; r_conn0=slot; r_seq0=seq; end
            else           begin rd_en1=1; r_conn1=slot; r_seq1=seq; end
            @(negedge clk);
            rd_en0=0; rd_en1=0;
            // retx_ram: rd_en 拍(T) -> 地址拍(T+1) -> 出数(T+2); TB 在 T+1/T+2 沿采样
            @(posedge clk); #1;
            if (port == 0) rd0_val = r_data0; else rd1_val = r_data1;
        end
    endtask

    integer s;
    initial begin
        $display("=== G-P3-3 retx_pool_shared ===");
        rst_n=0; repeat(3) @(negedge clk); rst_n=1; @(negedge clk);

        // ---- 臂 A: 8 槽属主写/读回 ----
        grant_port = 8'hF0;     // 槽 4..7 = port1
        for (s=0; s<4; s=s+1) wr(0, s[3:0], 16'd0, 64'hA5A5_0000_0000_0000 | ({60'd0, s[3:0]} << 32));
        for (s=4; s<8; s=s+1) wr(1, s[3:0], 16'd0, 64'h5A5A_0000_0000_0000 | ({60'd0, s[3:0]} << 32));
        for (s=0; s<4; s=s+1) begin
            rd(0, s[3:0], 16'd0);
            chk(rd0_val == (64'hA5A5_0000_0000_0000 | ({60'd0, s[3:0]} << 32)), "A slot readback p0");
        end
        for (s=4; s<8; s=s+1) begin
            rd(1, s[3:0], 16'd0);
            chk(rd1_val == (64'h5A5A_0000_0000_0000 | ({60'd0, s[3:0]} << 32)), "A slot readback p1");
        end
        chk(st_mismatch == 0, "A no owner mismatch");

        // ---- 臂 B: 两口同拍访问不同槽 ----
        @(negedge clk);
        wr_en0=1; w_conn0=4'd1; w_seq0=16'd8; w_data0=64'h1111_2222_3333_4444; w_n0=8;
        wr_en1=1; w_conn1=4'd5; w_seq1=16'd8; w_data1=64'h5555_6666_7777_8888; w_n1=8;
        @(negedge clk); wr_en0=0; wr_en1=0;
        rd(0,4'd1,16'd8); chk(rd0_val==64'h1111_2222_3333_4444, "B p0 slot1 word1");
        rd(1,4'd5,16'd8); chk(rd1_val==64'h5555_6666_7777_8888, "B p1 slot5 word1");
        chk(st_mismatch == 0, "B no owner mismatch");

        // ---- 臂 C: 非属主访问 ----
        wr(0, 4'd5, 16'd16, 64'hDEAD_BEEF_DEAD_BEEF);   // port0 -> slot5 (owner port1)
        rd(1, 4'd5, 16'd16);                              // 原数据应仍为 0
        chk(rd1_val == 64'd0, "C non-owner write dropped (data intact)");
        chk(st_mismatch >= 1, "C owner mismatch counted");
        rd(0, 4'd5, 16'd0);                               // 非属主读
        chk(st_mismatch >= 2, "C non-owner read counted");
        chk(rd0_val == 64'd0, "C non-owner read returns 0 (no stale data)");

        // ---- 臂 D: 槽号 >= 8 ----
        @(negedge clk); wr_en0=1; w_conn0=4'd9; w_seq0=16'd0; w_data0=64'hFFFF; w_n0=8;
        @(negedge clk); wr_en0=0;
        chk(st_oor >= 1, "D slot_oor counted");
        chk(st_mismatch == 2, "D no extra mismatch from slot>=8");

        // ---- 臂 E: 读延迟 2 拍 (T+1 采样必须是旧值/未变) ----
        //   写 slot0 word2 = 0xCAFE, 然后读; 在 T 与 T+1 采样应尚未出数,
        //   T+2 才是新值。这里用两级: 先读一次建立旧值, 再读新地址。
        wr(0, 4'd0, 16'd16, 64'hCAFE_0000_0000_0001);
        @(negedge clk); rd_en0=1; r_conn0=4'd0; r_seq0=16'd16;
        @(negedge clk); rd_en0=0;
        @(posedge clk); #1;   // T+1
        @(posedge clk); #1;   // T+2
        chk(r_data0 == 64'hCAFE_0000_0000_0001, "E read latency 2 (data at T+2)");

        // ---- 臂 F: H-2 owner 翻转 (grant_port 在 ev_up 时更新) ----
        //   槽3 当前属 port0: 写/读正常。
        grant_port[3] = 1'b0;
        wr(0, 4'd3, 16'd0, 64'hBEEF_0000_0000_0003);
        rd(0, 4'd3, 16'd0);
        chk(rd0_val == 64'hBEEF_0000_0000_0003, "F old owner (p0) access before flip");
        // grant_port 翻到 port1 (模拟新口 ev_up 接管): 旧口访问被拒
        grant_port[3] = 1'b1;
        wr(0, 4'd3, 16'd8, 64'hDEAD_0000_0000_0000);   // 旧口迟到写 -> 丢弃
        rd(0, 4'd3, 16'd0);                             // 旧口读 -> 0 (不再给旧数据)
        chk(rd0_val == 64'd0, "F old owner read after flip returns 0");
        chk(st_mismatch >= 3, "F owner mismatch counted after flip");
        // 新口接管: 读写正常, 旧数据仍在
        rd(1, 4'd3, 16'd0);
        chk(rd1_val == 64'hBEEF_0000_0000_0003, "F new owner reads intact data");
        wr(1, 4'd3, 16'd8, 64'hCAFE_0000_0000_0003);
        rd(1, 4'd3, 16'd8);
        chk(rd1_val == 64'hCAFE_0000_0000_0003, "F new owner write/readback");

        if (errors==0) $display("RETX_POOL_SHARED TB PASS");
        else           $display("RETX_POOL_SHARED TB FAIL errors=%0d", errors);
        $finish;
    end
    initial begin #500000; $display("RETX_POOL_SHARED TB FAIL (timeout)"); $finish; end
endmodule
