`timescale 1ns/1ps
//=============================================================================
// tb_win_pool_mgr.v — P11 P3 G-P3-1: win_pool_mgr 单元门 (P3 修复轮扩展)
//   臂 A: 基本授予/归还 + 不变量
//   臂 B: 8 槽 4+4 分布 (池抽干) + 第 9 次授予 (C18 同槽复用) 的原子归还
//   臂 C: port_cap 上限
//   臂 D: 同拍双口 ev_up (固定 port0->port1 顺序)
//   臂 E: 重复 rel -> stat_rel_dup (幂等 + 计数)
//   臂 F: 槽号 >= 8 -> stat_slot_oor, **状态逐项不变** (M-3)
//   臂 G: H-1 跨口同槽复用 + 旧口 rel 延迟 (ev_up1 先于 rel0)
//         断言: C18 old 从授出端口扣 / 新配额不被旧 rel 吞 /
//               stat_c18_cross_port=1 / stat_rel_stale_port=1 /
//               stat_port_win_underflow=0 / 不变量成立
//   臂 H: occ 非零 (0 / 0x17000 / >pool / 两口不同) (M-4)
//   臂 I: 同拍 ev_up + rel (不同槽 => 两者都处理; 同槽 => C18 吸收) (M-4)
//   臂 J: 8+0 与 6+2 分布 (M-4)
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
    wire [7:0]  gp;
    wire [31:0] st_grant_zero, st_slot_reuse, st_rel_dup, st_slot_oor;
    wire [31:0] st_c18_cross, st_pw_under, st_rel_stale;
    wire        dbg_busy;

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
        .o_grant_port(gp),
        .dbg_pool(dbg_pool), .dbg_port_win0(dbg_pw0), .dbg_port_win1(dbg_pw1),
        .stat_grant_zero(st_grant_zero), .stat_slot_reuse(st_slot_reuse),
        .stat_rel_dup(st_rel_dup), .stat_slot_oor(st_slot_oor),
        .stat_c18_cross_port(st_c18_cross),
        .stat_port_win_underflow(st_pw_under),
        .stat_rel_stale_port(st_rel_stale),
        .o_ev_up_done0(), .o_ev_up_done_slot0(),
        .o_ev_up_done1(), .o_ev_up_done_slot1(),
        .stat_ev_ovf(),
        .dbg_busy(dbg_busy), .dbg_ev_commit(), .dbg_ev_type(), .dbg_ev_slot()
    );

    integer errors = 0;
    reg [31:0] dup_before;
    task chk(input cond, input [255:0] msg);
        begin
            if (!cond) begin
                errors = errors + 1;
                $display(" FAIL: %0s (pool=%05x pw0=%05x pw1=%05x gp=%02x)",
                         msg, dbg_pool, dbg_pw0, dbg_pw1, gp);
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

    // 0x2F: 事件机是串行三拍 ⇒ 任何状态检查前先等 FIFO/引擎排空
    task wait_idle;
        begin
            while (dbg_busy) @(negedge clk);
            @(negedge clk);
        end
    endtask

    task check_inv(input [255:0] tag);
        begin
            wait_idle;
            read_all;
            chk((sum_w + dbg_pool) == WIN_POOL, "SUM winq + pool == WIN_POOL");
            chk((dbg_pw0 + dbg_pw1) == sum_w,    "SUM port_win == SUM winq");
            chk(dbg_pw0 <= port_cap,             "port0_win <= port_cap");
            chk(dbg_pw1 <= port_cap,             "port_win1 <= port_cap");
        end
    endtask

    task grant0(input [3:0] s); begin @(negedge clk); ev_up0=1; ev_slot0=s; @(negedge clk); ev_up0=0; @(negedge clk); wait_idle; end endtask
    task grant1(input [3:0] s); begin @(negedge clk); ev_up1=1; ev_slot1=s; @(negedge clk); ev_up1=0; @(negedge clk); wait_idle; end endtask
    task release0(input [3:0] s); begin @(negedge clk); rel0=1; rel_slot0=s; @(negedge clk); rel0=0; @(negedge clk); wait_idle; end endtask
    task release1(input [3:0] s); begin @(negedge clk); rel1=1; rel_slot1=s; @(negedge clk); rel1=0; @(negedge clk); wait_idle; end endtask

    // 状态快照 (M-3: 槽号越界前后逐项相等)
    reg [16:0] s_pool, s_pw0, s_pw1;
    reg [15:0] s_wq [0:7];
    reg [7:0]  s_gp;
    task snap;
        begin
            wait_idle;
            s_pool = dbg_pool; s_pw0 = dbg_pw0; s_pw1 = dbg_pw1; s_gp = gp;
            read_all;
            s_wq[0]=w0; s_wq[1]=w1; s_wq[2]=w2; s_wq[3]=w3;
            s_wq[4]=w4; s_wq[5]=w5; s_wq[6]=w6; s_wq[7]=w7;
        end
    endtask
    task chk_same_state(input [255:0] tag);
        begin
            chk(dbg_pool == s_pool, "state unchanged: pool");
            chk(dbg_pw0  == s_pw0,  "state unchanged: pw0");
            chk(dbg_pw1  == s_pw1,  "state unchanged: pw1");
            chk(gp       == s_gp,   "state unchanged: grant_port");
            read_all;
            chk(w0==s_wq[0] && w1==s_wq[1] && w2==s_wq[2] && w3==s_wq[3] &&
                w4==s_wq[4] && w5==s_wq[5] && w6==s_wq[6] && w7==s_wq[7],
                "state unchanged: winq[0..7]");
        end
    endtask

    task release_all;
        integer k;
        begin
            for (k=0;k<8;k=k+1) release0(k[3:0]);
            for (k=0;k<8;k=k+1) release1(k[3:0]);
            @(negedge clk);
        end
    endtask

    initial begin
        $display("=== G-P3-1 win_pool_mgr ===");
        rst_n = 0; repeat (3) @(negedge clk);
        rst_n = 1; @(negedge clk);
        check_inv("reset");
        chk(dbg_pool == WIN_POOL, "reset pool = WIN_POOL");
        chk(gp == 8'h00, "reset grant_port = 0");

        // ---- 臂 A: 基本授予/归还 ----
        grant0(4'd0);
        check_inv("A grant p0s0");
        chk(dbg_pw0 == 17'h3000, "A port0_win = 0x3000");
        chk(dbg_pool == WIN_POOL - 17'h3000, "A pool = 0x15000");
        chk(gp[0] == 1'b0, "A grant_port[0] = port0");
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
        chk(st_c18_cross == 0, "B same-port C18 does not count cross-port");

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

        // ---- 臂 F: 槽号 >= 8 -> 计数, 状态逐项不变 (M-3) ----
        snap();
        grant0(4'd9);
        chk_same_state("F slot oor grant");
        chk(st_slot_oor >= 1, "F stat_slot_oor counted");
        snap();
        release1(4'd12);
        chk_same_state("F slot oor rel");
        chk(st_slot_oor >= 2, "F stat_slot_oor counted (rel)");

        // ---- 臂 G: H-1 跨口同槽复用 + 旧口 rel 延迟 ----
        release_all;
        check_inv("G clean");
        grant0(4'd0);
        chk(dbg_pw0 == 17'h3000 && gp[0] == 1'b0, "G pre: p0 owns slot0");
        // ev_up1 复用同一槽: old 从 **授出端口 port0** 扣, 新配额记到 port1
        grant1(4'd0);
        check_inv("G cross-port C18");
        chk(dbg_pw0 == 17'd0, "G C18 old deducted from grant port (p0)");
        chk(dbg_pw1 == 17'h3000, "G new quota on p1");
        chk(w0 == 16'h3000, "G new quota in winq[0]");
        chk(gp[0] == 1'b1, "G grant_port[0] -> port1");
        chk(st_c18_cross == 1, "G stat_c18_cross_port = 1");
        // 旧口 rel 迟到 (ev_up1 之后): 非属主 => 忽略, 新配额不被吞
        release0(4'd0);
        check_inv("G stale rel0 ignored");
        chk(w0 == 16'h3000, "G stale rel did NOT eat new quota");
        chk(dbg_pw1 == 17'h3000, "G stale rel did NOT touch p1 port_win");
        chk(st_rel_stale >= 1, "G stat_rel_stale_port counted");
        chk(st_pw_under == 0, "G no port_win underflow");
        // 属主 rel (port1) 正常归还
        release1(4'd0);
        check_inv("G owner rel1");
        chk(dbg_pool == WIN_POOL, "G pool fully returned");
        chk(st_pw_under == 0, "G no port_win underflow (after owner rel)");

        // ---- 臂 H: occ 非零 (M-4) ----
        release_all;
        occ0 = 17'h17000;
        grant0(4'd0);
        check_inv("H occ reduces grant");
        chk(w0 == 16'h1000, "H g = pool - occ = 0x1000");
        release0(4'd0);
        occ0 = 17'h18000;           // occ == pool => avail 0
        grant0(4'd1);
        check_inv("H occ == pool");
        chk(w1 == 16'd0, "H zero grant when occ == pool");
        release0(4'd1);
        occ0 = 17'd0;
        // 两口不同 occ: p0 有额, p1 的 occ 吃掉几乎全部剩余池
        occ1 = 17'h15000;
        @(negedge clk); ev_up0=1; ev_slot0=4'd2; ev_up1=1; ev_slot1=4'd3;
        @(negedge clk); ev_up0=0; ev_up1=0;
        check_inv("H per-port occ");
        chk(w2 == 16'h3000, "H p0 granted full (occ0=0)");
        chk(w3 == 16'd0,    "H p1 zero grant (occ1 eats pool)");
        occ1 = 17'd0;
        release_all;

        // ---- 臂 I: 同拍 ev_up + rel (M-4) ----
        dup_before = st_rel_dup;
        grant0(4'd0);
        // 不同槽: slot0 rel + slot1 ev_up, 同拍
        @(negedge clk); rel0=1; rel_slot0=4'd0; ev_up0=1; ev_slot0=4'd1;
        @(negedge clk); rel0=0; ev_up0=0;
        check_inv("I same-cycle ev_up+rel diff slots");
        chk(w0 == 16'd0 && w1 == 16'h3000, "I rel and grant both processed");
        chk(st_rel_dup == dup_before, "I no spurious dup");
        // 同槽: ev_up 与 rel 同拍 => C18 吸收 (净效果 = 重新授予)
        @(negedge clk); rel0=1; rel_slot0=4'd1; ev_up0=1; ev_slot0=4'd1;
        @(negedge clk); rel0=0; ev_up0=0;
        check_inv("I same-cycle ev_up+rel same slot");
        chk(w1 == 16'h3000, "I same-slot C18 net grant");
        release0(4'd1);

        // ---- 臂 J: 8+0 / 6+2 (M-4) ----
        release_all;
        grant0(4'd0); grant0(4'd1); grant0(4'd2); grant0(4'd3);
        grant0(4'd4); grant0(4'd5); grant0(4'd6); grant0(4'd7);
        check_inv("J 8+0");
        chk(dbg_pool == 17'd0, "J 8+0 pool empty");
        chk(dbg_pw0 == WIN_POOL && dbg_pw1 == 17'd0, "J 8+0 all on port0");
        chk(st_grant_zero >= 3, "J zero-grant counter accumulated (C=1, H=2)");
        release_all;
        grant0(4'd0); grant0(4'd1); grant0(4'd2); grant0(4'd3);
        grant0(4'd4); grant0(4'd5);
        grant1(4'd6); grant1(4'd7);
        check_inv("J 6+2");
        chk(dbg_pw0 == 17'h12000 && dbg_pw1 == 17'h6000, "J 6+2 distribution");
        chk(dbg_pool == 17'd0, "J 6+2 pool empty");
        release_all;
        check_inv("J final");

        // 收尾: 读口越界返回 0
        rd_id = 4'd9; #1; chk(winq_rd0 == 16'd0, "F read slot>=8 returns 0");
        rd_id = 4'd0;

        if (errors == 0) $display("WIN_POOL_MGR TB PASS");
        else             $display("WIN_POOL_MGR TB FAIL errors=%0d", errors);
        $finish;
    end

    // 超时保护
    initial begin
        #400000;
        $display("WIN_POOL_MGR TB FAIL (timeout)");
        $finish;
    end
endmodule
