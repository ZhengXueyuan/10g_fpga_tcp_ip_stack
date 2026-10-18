`timescale 1ns/1ps
//=============================================================================
// tb_p3_churn.v — P11 P3 G-P3-1b: 8 连接 churn / 释放恰好一次
//   真实 2x app_ctrl(EXT_QUOTA=1) + win_pool_mgr + 行为级 mini-TCB。
//   逐拍不变量 (独立影子模型, 不读 DUT 内部):
//     shadow Σwinq + pool == WIN_POOL · Σport_win == Σwinq · port_win <= port_cap
//   释放路径覆盖: 外部 DEL / 关闭超时 to_fire / abort+state=0 st_req_now /
//                 孤儿回收 orph_down_i / C18 同槽复用。
//   判据: 每条**非零**配额的槽恰好 1 次 o_quota_rel; stat_rel_dup == 0。
//=============================================================================
module tb_p3_churn;
    localparam [16:0] WIN_POOL = 17'h18000;
    localparam [16:0] PCAP     = 17'h18000;
    localparam [15:0] WQ       = 16'h3000;

    reg clk=0, rst_n=0; always #5 clk=~clk;

    // ---- 两套 app_ctrl 的共用线 ----
    reg         ev0_up=0, ev0_down=0; reg [3:0] ev0_slot=0;
    reg         ev1_up=0, ev1_down=0; reg [3:0] ev1_slot=0;
    wire [3:0]  rc0_id, rc1_id;
    reg  [31:0] rc0_nxt,rc0_una,rc0_rn; reg [15:0] rc0_rw,rc0_sw; reg [3:0] rc0_st;
    reg  [31:0] rc1_nxt,rc1_una,rc1_rn; reg [15:0] rc1_rw,rc1_sw; reg [3:0] rc1_st;
    reg  [15:0] fin_sent0=0, rst_sent0=0, fin_sent1=0, rst_sent1=0;
    reg         retx_act=0; reg [3:0] retx_id=0;
    wire [15:0] app0_tx_ready, app1_tx_ready;
    wire        fc0_wr, fc1_wr;
    wire [3:0]  fc0_id, fc1_id;
    wire [2:0]  fc0_sel, fc1_sel;
    wire [31:0] fc0_val, fc1_val;
    wire        fc0_gnt = fc0_wr;
    wire        fc1_gnt = fc1_wr;
    wire        wu0_req, wu1_req;
    wire [3:0]  wu0_id, wu1_id;
    wire [31:0] wu0_val, wu1_val;
    wire        wu0_gnt = wu0_req;
    wire        wu1_gnt = wu1_req;
    wire        orph0_clr, orph1_clr;
    wire [3:0]  orph0_slot, orph1_slot;
    wire [31:0] st0_orph, st1_orph;
    wire [3:0]  wq0_rid, wq0_rid_ev, wq1_rid, wq1_rid_ev;
    wire [15:0] wq0_rd, wq0_rd_ev, wq1_rd, wq1_rd_ev;
    wire        qrel0, qrel1; wire [3:0] qrel0_slot, qrel1_slot;
    wire [31:0] app0_stat_wu, app1_stat_wu, app0_stat_slot_reuse, app1_stat_slot_reuse;
    wire [3:0]  a0_c0st, a1_c0st;

    app_ctrl #(
        .WIN_CAP(16'hF000), .EXT_QUOTA(1'b1),
        .FIN_TO_LIM(18'd8), .FIN_GRACE(18'd300),
        .ORPHAN_EN(1'b1), .ORPHAN_LIM(8'd2), .ORPHAN_TICK_BITS(1)
    ) u0 (
        .clk(clk), .rst_n(rst_n),
        .ev_up(ev0_up), .ev_down(ev0_down), .ev_slot(ev0_slot),
        .ev_peer_ip(32'd0), .ev_peer_port(16'd0), .ev_peer_mac(48'd0),
        .rc_id(rc0_id), .rc_snd_nxt(rc0_nxt), .rc_snd_una(rc0_una),
        .rc_rcv_nxt(rc0_rn), .rc_rcv_wnd(rc0_rw), .rc_snd_wnd(rc0_sw), .rc_state(rc0_st),
        .o_winq_rd_id(wq0_rid), .i_winq_rd(wq0_rd),
        .o_winq_rd_id_ev(wq0_rid_ev), .i_winq_rd_ev(wq0_rd_ev),
        .o_quota_rel(qrel0), .o_quota_rel_slot(qrel0_slot),
        .rx_occ_bytes(17'd0), .fin_sent(fin_sent0), .rst_sent(rst_sent0),
        .retx_active(retx_act), .retx_id(retx_id),
        .una_adv(1'b0), .una_adv_id(4'd0), .ack_obs(1'b0), .ack_obs_id(4'd0),
        .scfg_busy(1'b0),
        .orphan_cam_clr(orph0_clr), .orphan_cam_slot(orph0_slot),
        .stat_orphan(st0_orph),
        .o_ev_up(), .o_ev_down(), .o_ev_slot(),
        .fin_req(), .rst_req(),
        .close_req(1'b0), .close_id(4'd0),
        .fc_upd_wr(fc0_wr), .fc_upd_id(fc0_id), .fc_upd_sel(fc0_sel),
        .fc_upd_val(fc0_val), .fc_gnt(fc0_gnt),
        .wu_req(wu0_req), .wu_id(wu0_id), .wu_val(wu0_val), .wu_gnt(wu0_gnt),
        .reg_addr(8'h00), .reg_wr(1'b0), .reg_wdata(32'd0), .reg_rdata(),
        .app_tx_ready(app0_tx_ready),
        .dbg_c0_state(a0_c0st), .dbg_c0_snd_nxt(), .dbg_c0_snd_una(),
        .dbg_c0_rcv_nxt(), .dbg_c0_rcv_wnd(), .dbg_c0_snd_wnd(),
        .dbg_estab_cnt(), .dbg_ev_cnt(),
        .dbg_redge0(), .dbg_winq0(), .dbg_wu_mark0(), .dbg_pool(),
        .stat_ev_up(), .stat_ev_down(), .stat_ev_drop(), .stat_cmd_close(),
        .stat_cmd_abort(), .stat_wu(app0_stat_wu), .stat_pool_exhaust(),
        .stat_fc_upd(), .stat_slot_reuse(app0_stat_slot_reuse), .stat_fc_wait_max()
    );

    app_ctrl #(
        .WIN_CAP(16'hF000), .EXT_QUOTA(1'b1),
        .FIN_TO_LIM(18'd8), .FIN_GRACE(18'd300),
        .ORPHAN_EN(1'b1), .ORPHAN_LIM(8'd2), .ORPHAN_TICK_BITS(1)
    ) u1 (
        .clk(clk), .rst_n(rst_n),
        .ev_up(ev1_up), .ev_down(ev1_down), .ev_slot(ev1_slot),
        .ev_peer_ip(32'd0), .ev_peer_port(16'd0), .ev_peer_mac(48'd0),
        .rc_id(rc1_id), .rc_snd_nxt(rc1_nxt), .rc_snd_una(rc1_una),
        .rc_rcv_nxt(rc1_rn), .rc_rcv_wnd(rc1_rw), .rc_snd_wnd(rc1_sw), .rc_state(rc1_st),
        .o_winq_rd_id(wq1_rid), .i_winq_rd(wq1_rd),
        .o_winq_rd_id_ev(wq1_rid_ev), .i_winq_rd_ev(wq1_rd_ev),
        .o_quota_rel(qrel1), .o_quota_rel_slot(qrel1_slot),
        .rx_occ_bytes(17'd0), .fin_sent(fin_sent1), .rst_sent(rst_sent1),
        .retx_active(retx_act), .retx_id(retx_id),
        .una_adv(1'b0), .una_adv_id(4'd0), .ack_obs(1'b0), .ack_obs_id(4'd0),
        .scfg_busy(1'b0),
        .orphan_cam_clr(orph1_clr), .orphan_cam_slot(orph1_slot),
        .stat_orphan(st1_orph),
        .o_ev_up(), .o_ev_down(), .o_ev_slot(),
        .fin_req(), .rst_req(),
        .close_req(1'b0), .close_id(4'd0),
        .fc_upd_wr(fc1_wr), .fc_upd_id(fc1_id), .fc_upd_sel(fc1_sel),
        .fc_upd_val(fc1_val), .fc_gnt(fc1_gnt),
        .wu_req(wu1_req), .wu_id(wu1_id), .wu_val(wu1_val), .wu_gnt(wu1_gnt),
        .reg_addr(8'h00), .reg_wr(1'b0), .reg_wdata(32'd0), .reg_rdata(),
        .app_tx_ready(app1_tx_ready),
        .dbg_c0_state(a1_c0st), .dbg_c0_snd_nxt(), .dbg_c0_snd_una(),
        .dbg_c0_rcv_nxt(), .dbg_c0_rcv_wnd(), .dbg_c0_snd_wnd(),
        .dbg_estab_cnt(), .dbg_ev_cnt(),
        .dbg_redge0(), .dbg_winq0(), .dbg_wu_mark0(), .dbg_pool(),
        .stat_ev_up(), .stat_ev_down(), .stat_ev_drop(), .stat_cmd_close(),
        .stat_cmd_abort(), .stat_wu(app1_stat_wu), .stat_pool_exhaust(),
        .stat_fc_upd(), .stat_slot_reuse(app1_stat_slot_reuse), .stat_fc_wait_max()
    );

    wire [16:0] dbg_pool, dbg_pw0, dbg_pw1;
    wire [31:0] st_gzero, st_sreuse, st_rdup, st_oor;
    win_pool_mgr #(.WIN_POOL(WIN_POOL), .PORT_CAP(PCAP)) um (
        .clk(clk), .rst_n(rst_n),
        .ev_up0(ev0_up), .ev_up_slot0(ev0_slot),
        .ev_up1(ev1_up), .ev_up_slot1(ev1_slot),
        .rel0(qrel0), .rel_slot0(qrel0_slot),
        .rel1(qrel1), .rel_slot1(qrel1_slot),
        .occ0(17'd0), .occ1(17'd0),
        .wq_cap(WQ), .port_cap(PCAP),
        .winq_rd_id0(wq0_rid), .winq_rd0(wq0_rd),
        .winq_rd_id0b(wq0_rid_ev), .winq_rd0b(wq0_rd_ev),
        .winq_rd_id1(wq1_rid), .winq_rd1(wq1_rd),
        .winq_rd_id1b(wq1_rid_ev), .winq_rd1b(wq1_rd_ev),
        .dbg_pool(dbg_pool), .dbg_port_win0(dbg_pw0), .dbg_port_win1(dbg_pw1),
        .stat_grant_zero(st_gzero), .stat_slot_reuse(st_sreuse),
        .stat_rel_dup(st_rdup), .stat_slot_oor(st_oor)
    );

    // ---- 行为级 mini-TCB x2 (16 槽; 只实现 app_ctrl 消费的字段) ----
    reg [3:0]  st0 [0:15]; reg [31:0] nxt0[0:15], una0[0:15], rn0[0:15];
    reg [15:0] rw0 [0:15], sw0[0:15];
    reg [3:0]  st1 [0:15]; reg [31:0] nxt1[0:15], una1[0:15], rn1[0:15];
    reg [15:0] rw1 [0:15], sw1[0:15];
    integer i;
    always @(*) begin
        rc0_nxt=32'd0; rc0_una=32'd0; rc0_rn=32'd0; rc0_rw=16'd0; rc0_sw=16'd0; rc0_st=4'd0;
        for (i=0;i<16;i=i+1) if (rc0_id==i[3:0]) begin
            rc0_nxt=nxt0[i]; rc0_una=una0[i]; rc0_rn=rn0[i]; rc0_rw=rw0[i];
            rc0_sw=sw0[i]; rc0_st=st0[i];
        end
        rc1_nxt=32'd0; rc1_una=32'd0; rc1_rn=32'd0; rc1_rw=16'd0; rc1_sw=16'd0; rc1_st=4'd0;
        for (i=0;i<16;i=i+1) if (rc1_id==i[3:0]) begin
            rc1_nxt=nxt1[i]; rc1_una=una1[i]; rc1_rn=rn1[i]; rc1_rw=rw1[i];
            rc1_sw=sw1[i]; rc1_st=st1[i];
        end
    end

    // fc 写落地 (sel=5 拆 state; sel=3 写 rcv_wnd)
    always @(posedge clk) begin
        if (rst_n && fc0_wr && fc0_gnt) begin
            if (fc0_sel==3'd5) st0[fc0_id] <= 4'd0;
            else if (fc0_sel==3'd3) rw0[fc0_id] <= fc0_val[15:0];
        end
        if (rst_n && fc1_wr && fc1_gnt) begin
            if (fc1_sel==3'd5) st1[fc1_id] <= 4'd0;
            else if (fc1_sel==3'd3) rw1[fc1_id] <= fc1_val[15:0];
        end
    end

    // ---- 影子模型 + 逐拍不变量 + rel 计数 ----
    reg [16:0] sh_pool; reg [15:0] sh_w [0:7]; reg [16:0] sh_pw0, sh_pw1;
    integer rel_cnt0 [0:7]; integer rel_cnt1 [0:7];
    reg [16:0] sumw;
    integer errors=0;
    task chk(input cond, input [255:0] msg);
        begin if(!cond) begin errors=errors+1; $display(" FAIL: %0s", msg); end end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            sh_pool <= WIN_POOL; sh_pw0 <= 0; sh_pw1 <= 0;
            for (i=0;i<8;i=i+1) begin sh_w[i] <= 0; rel_cnt0[i] <= 0; rel_cnt1[i] <= 0; end
        end else begin
            // rel 事件 (与本拍 app_ctrl 输出同沿) -> 先记数/更新影子
            if (qrel0) begin
                rel_cnt0[qrel0_slot] <= rel_cnt0[qrel0_slot] + 1;
                sh_pool <= sh_pool + sh_w[qrel0_slot];
                sh_pw0  <= sh_pw0 - sh_w[qrel0_slot];
                sh_w[qrel0_slot] <= 0;
            end
            if (qrel1) begin
                rel_cnt1[qrel1_slot] <= rel_cnt1[qrel1_slot] + 1;
                sh_pool <= sh_pool + sh_w[qrel1_slot];
                sh_pw1  <= sh_pw1 - sh_w[qrel1_slot];
                sh_w[qrel1_slot] <= 0;
            end
            // ev_up 授予 (旧额先回池, 再按 min 授新)
            if (ev0_up) begin
                // occ=0 / port_cap 足够 ⇒ g = WQ; 旧额先回池
                sh_pool <= sh_pool + sh_w[ev0_slot] - WQ;
                sh_pw0  <= sh_pw0  - sh_w[ev0_slot] + WQ;
                sh_w[ev0_slot] <= WQ;
            end
            if (ev1_up) begin
                sh_pool <= sh_pool + sh_w[ev1_slot] - WQ;
                sh_pw1  <= sh_pw1  - sh_w[ev1_slot] + WQ;
                sh_w[ev1_slot] <= WQ;
            end
            // 逐拍不变量 (影子 vs DUT 调试口)
            chk(dbg_pool == sh_pool, "inv: DUT pool == shadow pool");
            chk(dbg_pw0 == sh_pw0, "inv: DUT port_win0 == shadow");
            chk(dbg_pw1 == sh_pw1, "inv: DUT port_win1 == shadow");
            chk((sh_pw0 + sh_pw1) <= WIN_POOL, "inv: sum port_win <= WIN_POOL");
            // DUT 内部逐拍不变量 (TB 专用层次读; 判据是方程本身)
            sumw = 17'd0;
            for (i=0;i<8;i=i+1) sumw = sumw + um.winq[i];
            chk((sumw + dbg_pool) == WIN_POOL, "inv: SUM winq + pool == WIN_POOL");
            chk(sumw == (dbg_pw0 + dbg_pw1),   "inv: SUM port_win == SUM winq");
        end
    end
    // 每拍结束时校验 DUT 不变量: Σwinq 通过 read 口逐一读 (每 8 拍一轮)
    reg [16:0] rd_sum; reg [2:0] rd_i=0;
    always @(posedge clk) begin
        if (rst_n) begin
            rd_i <= rd_i + 1;
        end
    end

    task t_ev(input integer port, input [3:0] slot);
        begin
            @(negedge clk);
            if (port==0) begin ev0_up=1; ev0_slot=slot; end
            else         begin ev1_up=1; ev1_slot=slot; end
            @(negedge clk);
            ev0_up=0; ev1_up=0;
            if (port==0) begin st0[slot] <= 4'd1; nxt0[slot] <= 32'h1000; una0[slot] <= 32'h0;
                              sw0[slot] <= 16'h1000; fin_sent0[slot] <= 1'b0; rst_sent0[slot] <= 1'b0; end
            else         begin st1[slot] <= 4'd1; nxt1[slot] <= 32'h1000; una1[slot] <= 32'h0;
                              sw1[slot] <= 16'h1000; fin_sent1[slot] <= 1'b0; rst_sent1[slot] <= 1'b0; end
            @(negedge clk);
        end
    endtask
    task t_down(input integer port, input [3:0] slot);
        begin
            @(negedge clk);
            if (port==0) begin ev0_down=1; ev0_slot=slot; st0[slot] <= 4'd0; end
            else         begin ev1_down=1; ev1_slot=slot; st1[slot] <= 4'd0; end
            @(negedge clk);
            ev0_down=0; ev1_down=0;
            @(negedge clk);
        end
    endtask
    task wait_rel(input integer port, input [3:0] slot, input integer maxcyc);
        integer k; reg seen;
        begin
            seen=0;
            for (k=0;k<maxcyc;k=k+1) begin
                @(negedge clk);
                if (port==0 && rel_cnt0[slot]>0) seen=1;
                if (port==1 && rel_cnt1[slot]>0) seen=1;
                if (seen) k=maxcyc;
            end
            chk(seen, "wait_rel timeout");
        end
    endtask

    initial begin
        $display("=== G-P3-1b churn ===");
        rst_n=0; repeat(4) @(negedge clk); rst_n=1;
        for (i=0;i<16;i=i+1) begin
            st0[i]=0; nxt0[i]=0; una0[i]=0; rn0[i]=0; rw0[i]=0; sw0[i]=0;
            st1[i]=0; nxt1[i]=0; una1[i]=0; rn1[i]=0; rw1[i]=0; sw1[i]=0;
        end
        repeat(2) @(negedge clk);

        // 1) 4+4 建连
        t_ev(0,4'd0); t_ev(0,4'd1); t_ev(0,4'd2); t_ev(0,4'd3);
        t_ev(1,4'd4); t_ev(1,4'd5); t_ev(1,4'd6); t_ev(1,4'd7);
        repeat(4) @(negedge clk);
        chk(dbg_pool==17'd0, "1) 8x12KB exhausts 96KB pool");
        chk(dbg_pw0==17'hC000 && dbg_pw1==17'hC000, "1) 4+4 distribution");

        // 2) 外部 DEL (port0 slot0 / port1 slot4)
        t_down(0,4'd0); t_down(1,4'd4);
        repeat(4) @(negedge clk);
        chk(rel_cnt0[0]==1 && rel_cnt1[4]==1, "2) DEL releases exactly once");
        chk(dbg_pool==17'h6000, "2) pool +2x12KB");

        // 3) 关闭超时 (port0 slot1, fin_sent=1, 无进展)
        fin_sent0[1] <= 1'b1;
        wait_rel(0, 4'd1, 4000);
        repeat(4) @(negedge clk);
        chk(rel_cnt0[1]==1, "3) timeout to_fire releases exactly once");
        rst_sent0[1] <= 1'b1;   // 让 st_req_now 正常收尾 (不会再 rel)
        repeat(80) @(negedge clk);
        t_down(0,4'd1);
        repeat(4) @(negedge clk);
        chk(rel_cnt0[1]==1, "3b) later DEL does NOT double-release");

        // 4) abort+state=0 (port0 slot2: rst_sent 上升 -> st_req_now)
        rst_sent0[2] <= 1'b1;
        wait_rel(0, 4'd2, 2000);
        repeat(4) @(negedge clk);
        chk(rel_cnt0[2]==1, "4) abort st_req_now releases exactly once");
        t_down(0,4'd2);
        repeat(4) @(negedge clk);
        chk(rel_cnt0[2]==1, "4b) later DEL does NOT double-release");

        // 5) C18 同槽复用 (port0 slot3 二次 ev_up)
        t_ev(0,4'd3);
        repeat(4) @(negedge clk);
        chk(rel_cnt0[3]==0, "5) C18 reuse emits no rel");
        chk(dbg_pool==17'hC000, "5) C18 re-grant keeps pool unchanged (0xC000)");
        t_down(0,4'd3);
        repeat(4) @(negedge clk);
        chk(rel_cnt0[3]==1, "5b) final DEL releases once");

        // 6) 孤儿回收 (port1 slot5): state ESTAB + 在飞 + retx 见证
        retx_act <= 1'b1; retx_id <= 4'd5;
        nxt1[5] <= 32'h2000; una1[5] <= 32'h0; sw1[5] <= 16'h1000; st1[5] <= 4'd1;
        wait_rel(1, 4'd5, 8000);
        repeat(4) @(negedge clk);
        chk(rel_cnt1[5]==1, "6) orphan recovery releases exactly once");
        retx_act <= 1'b0;
        t_down(1,4'd5);
        repeat(4) @(negedge clk);
        chk(rel_cnt1[5]==1, "6b) later DEL does NOT double-release");

        // 7) 收尾: 释放剩余 (p1 slot6/7), 校验每条非零配额恰一次
        t_down(1,4'd6); t_down(1,4'd7);
        repeat(8) @(negedge clk);
        chk(rel_cnt1[6]==1 && rel_cnt1[7]==1, "7) remaining slots release once");
        chk(st_rdup==0, "7) stat_rel_dup == 0");
        chk(st_oor==0, "7) stat_slot_oor == 0");
        chk(dbg_pool==WIN_POOL, "7) pool fully returned");
        chk(st_gzero==0, "7) no zero grants (contract never violated)");

        if (errors==0) $display("P3_CHURN TB PASS");
        else           $display("P3_CHURN TB FAIL errors=%0d", errors);
        $finish;
    end
    initial begin #2000000; $display("P3_CHURN TB FAIL (timeout)"); $finish; end
endmodule
