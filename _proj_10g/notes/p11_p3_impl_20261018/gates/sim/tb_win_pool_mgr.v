`timescale 1ns/1ps
//=============================================================================
// tb_win_pool_mgr.v — P11 P3 G-P3-1: win_pool_mgr 单元门
//   臂 A: 基本授予/归还 + 不变量
//   臂 B: 8 槽 4+4 分布 (池抽干) + 第 9 次授予 (C18 同槽复用) 的原子归还
//   臂 C: port_cap 上限
//   臂 D: 同拍双口 ev_up (固定 port0->port1 顺序)
//   臂 E: 重复 rel -> stat_rel_dup (幂等 + 计数)
//   臂 F: 槽号 >= 8 -> stat_slot_oor, 不改变状态
//   逐拍不变量: Σwinq+pool==WIN_POOL / Σport_win==Σwinq / port_win<=port_cap
//=============================================================================
module tb_win_pool_mgr;
    localparam [16:0] WIN_POOL = 17'h18000;
    localparam [16:0] PCAP     = 17'h18000;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg         ev_up0 = 0, ev_up1 = 0;
    reg  [3:0]  ev_slot0 = 0, ev_slot1 = 0;
    reg         rel0 = 0, rel1 = 0;
    reg  [3:0]  rel_slot0 = 0, rel_slot1 = 0;
    reg  [16:0] occ0 = 0, occ1 = 0;
    reg  [15:0] wq_cap = 16'h3000;
    reg  [16:0] port_cap = PCAP;
    wire [15:0] winq_rd0, winq_rd0b, winq_rd1, winq_rd1b;
    reg  [3:0]  rd_id = 0, rd_id_b = 0;
    wire [16:0] dbg_pool, dbg_pw0, dbg_pw1;
    wire [31:0] st_grant_zero, st_slot_reuse, st_rel_dup, st_slot_oor;

    win_pool_mgr #(.WIN_POOL(WIN_POOL), .PORT_CAP(PCAP)) dut (
        .clk(clk), .rst_n(rst_n),
        .ev_up0(ev_up0), .ev_up_slot0(ev_slot0),
        .ev_up1(ev_up1), .ev_up_slot1(ev_slot1),
        .rel0(rel0), .rel_slot0(rel_slot0),
        .rel1(rel1), .rel_slot1(rel_slot1),
        .occ0(occ0), .occ1(occ1),
        .wq_cap(wq_cap), .port_cap(port_cap),
        .winq_rd_id0(rd_id), .winq_rd0(winq_rd0),
        .winq_rd_id0b(rd_id_b), .winq_rd0b(winq_rd0b),
        .winq_rd_id1(rd_id), .winq_rd1(winq_rd1),
        .winq_rd_id1b(rd_id_b), .winq_rd1b(winq_rd1b),
        .dbg_pool(dbg_pool), .dbg_port_win0(dbg_pw0), .dbg_port_win1(dbg_pw1),
        .stat_grant_zero(st_grant_zero), .stat_slot_reuse(st_slot_reuse),
        .stat_rel_dup(st_rel_dup), .stat_slot_oor(st_slot_oor)
    );

    integer errors = 0;
    task chk(input cond, input [255:0] msg);
        begin
            if (!cond) begin
                errors = errors + 1;
                $display(" FAIL: %0s (pool=%05x pw0=%05x pw1=%05x)", msg, dbg_pool, dbg_pw0, dbg_pw1);
            end
        end
    endtask

    // 逐拍不变量 (期望值从 DUT 读口取: 8 个槽的和)
    reg [16:0] sum_w;
    reg [15:0] w0,w1,w2,w3,w4,w5,w6,w7;
    task read_all;
        begin
            rd_id = 4'd0; #1; w0 = winq_rd0;
            rd_id = 4'd1; #1; w1 = winq_rd0;
            rd_id = 4'd2; #1; w2 = winq_rd0;
            rd_id = 4'd3; #1; w3 = winq_rd0;
            rd_id = 4'd4; #1; w4 = winq_rd0;
            rd_id = 4'd5; #1; w5 = winq_rd0;
            rd_id = 4'd6; #1; w6 = winq_rd0;
            rd_id = 4'd7; #1; w7 = winq_rd0;
            rd_id = 4'd0;
            sum_w = {1'b0,w0}+{1'b0,w1}+{1'b0,w2}+{1'b0,w3}+
                    {1'b0,w4}+{1'b0,w5}+{1'b0,w6}+{1'b0,w7};
        end
    endtask

    task check_inv(input [255:0] tag);
        begin
            read_all;
            chk((sum_w + dbg_pool) == WIN_POOL, "SUM winq + pool == WIN_POOL");
            chk((dbg_pw0 + dbg_pw1) == sum_w,    "SUM port_win == SUM winq");
            chk(dbg_pw0 <= port_cap,             "port0_win <= port_cap");
            chk(dbg_pw1 <= port_cap,             "port_win1 <= port_cap");
        end
    endtask

    task grant0(input [3:0] s); begin @(negedge clk); ev_up0=1; ev_slot0=s; @(negedge clk); ev_up0=0; @(negedge clk); end endtask
    task grant1(input [3:0] s); begin @(negedge clk); ev_up1=1; ev_slot1=s; @(negedge clk); ev_up1=0; @(negedge clk); end endtask
    task release0(input [3:0] s); begin @(negedge clk); rel0=1; rel_slot0=s; @(negedge clk); rel0=0; @(negedge clk); end endtask
    task release1(input [3:0] s); begin @(negedge clk); rel1=1; rel_slot1=s; @(negedge clk); rel1=0; @(negedge clk); end endtask

    integer i;
    initial begin
        $display("=== G-P3-1 win_pool_mgr ===");
        rst_n = 0; repeat (3) @(negedge clk);
        rst_n = 1; @(negedge clk);
        check_inv("reset");
        chk(dbg_pool == WIN_POOL, "reset pool = WIN_POOL");

        // ---- 臂 A: 基本授予/归还 ----
        grant0(4'd0);
        check_inv("A grant p0s0");
        chk(dbg_pw0 == 17'h3000, "A port0_win = 0x3000");
        chk(dbg_pool == WIN_POOL - 17'h3000, "A pool = 0x15000");
        release0(4'd0);
        check_inv("A rel p0s0");
        chk(dbg_pool == WIN_POOL, "A pool restored");
        chk(st_rel_dup == 0, "A no rel dup");

        // ---- 臂 B: 8 槽 4+4 + C18 复用 ----
        grant0(4'd0); grant0(4'd1); grant0(4'd2); grant0(4'd3);
        grant1(4'd4); grant1(4'd5); grant1(4'd6); grant1(4'd7);
        check_inv("B full 4+4");
        chk(dbg_pool == 17'd0, "B pool exhausted");
        chk(dbg_pw0 == 17'hC000, "B port0 = 4x12KB");
        // C18: 同槽再 ev_up (旧配额先原子归还再授) —— 池已空, g = 0x3000 (旧额回池)
        grant0(4'd0);
        check_inv("B C18 reuse slot0");
        chk(dbg_pool == 17'd0, "B C18 net pool 0");
        chk(st_slot_reuse == 1, "B C18 stat_slot_reuse = 1");

        // ---- 臂 C: port_cap 上限 ----
        release0(4'd0); release0(4'd1); release0(4'd2); release0(4'd3);
        release1(4'd4); release1(4'd5); release1(4'd6); release1(4'd7);
        check_inv("C released all");
        port_cap = 17'h4000;
        grant0(4'd0);                // 0x3000
        grant0(4'd1);                // 只剩 0x1000
        check_inv("C port cap");
        chk(dbg_pw0 == 17'h4000, "C port0 capped at 0x4000");
        grant0(4'd2);                // 0
        chk(st_grant_zero >= 1, "C grant_zero counted");
        release0(4'd0); release0(4'd1);
        check_inv("C rel");
        port_cap = PCAP;

        // ---- 臂 D: 同拍双口 ev_up (port0 -> port1 固定顺序) ----
        @(negedge clk); ev_up0=1; ev_slot0=4'd3; ev_up1=1; ev_slot1=4'd4;
        @(negedge clk); ev_up0=0; ev_up1=0;
        check_inv("D dual same-cycle");
        chk(dbg_pw0 == 17'h3000 && dbg_pw1 == 17'h3000, "D both ports granted");

        // ---- 臂 E: 重复 rel ----
        release0(4'd3);              // 正常归还
        release0(4'd3);              // 重复 (winq 已 0)
        check_inv("E duplicate rel");
        chk(st_rel_dup == 1, "E stat_rel_dup = 1");

        // ---- 臂 F: 槽号 >= 8 ----
        grant0(4'd9);
        check_inv("F slot oor");
        chk(st_slot_oor >= 1, "F stat_slot_oor counted");

        // 收尾: 读口越界返回 0
        rd_id = 4'd9; #1; chk(winq_rd0 == 16'd0, "F read slot>=8 returns 0");
        rd_id = 4'd0;

        if (errors == 0) $display("WIN_POOL_MGR TB PASS");
        else             $display("WIN_POOL_MGR TB FAIL errors=%0d", errors);
        $finish;
    end

    // 超时保护
    initial begin
        #200000;
        $display("WIN_POOL_MGR TB FAIL (timeout)");
        $finish;
    end
endmodule
