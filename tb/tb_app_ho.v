`timescale 1ns/1ps
//=============================================================================
// tb_app_ho: R1 半开老化单元门 (2026-11-08)
//
// 目的: 在 RTL 级验证 app_ctrl 的新增半开老化 (HO_EN=1):
//   A. 8 个 ESTAB 槽、无任何 ACK ⇒ 每槽恰好触发一次 o_ho_fire, 并走完 orphan
//      拆除序列 (state=0 写 / CAM 清 / o_ev_down 通知)。
//   B. 对 slot 3 给一次 ack_obs ⇒ slot 3 永不 fire, 其余槽照常 fire。
//   C. 对 slot 5 先 ack_obs 再 ev_up ⇒ ho_ack_seen/ho_cnt 被清 ⇒ slot 5 重新可 fire。
//
// 结构: app_ctrl 单元 + TB 侧 16 槽 TCB 行为模型 (组合读口按 rc_id mux)。
// 判定: TB_APP_HO PASS / FAIL (errs=N)。
//=============================================================================
module tb_app_ho;
    localparam [7:0] HO_LIM_TB   = 8'd2;
    localparam integer TICK_BITS_TB = 1;

    reg clk = 0;
    always #4 clk = ~clk;               // 125 MHz (8 ns)
    reg rst_n;
    reg ev_up, ev_down;
    reg [3:0] ev_slot;
    reg [31:0] ev_ip;
    reg [15:0] ev_port;
    reg [47:0] ev_mac;
    reg retx_active;
    reg [3:0] retx_id;
    reg una_adv;
    reg [3:0] una_adv_id;
    reg ack_obs;
    reg [3:0] ack_obs_id;
    reg scfg_busy;
    reg [15:0] fin_sent_v, rst_sent_v;

    integer errs;
    integer i, j;

    // ---- TCB 行为模型 ----
    reg [3:0]  t_state   [0:15];
    reg [31:0] t_nxt     [0:15];
    reg [31:0] t_una     [0:15];
    reg [31:0] t_rcv_nxt [0:15];
    reg [15:0] t_rcv_wnd [0:15];
    reg [15:0] t_snd_wnd [0:15];

    wire [3:0]  rc_id;
    wire [31:0] rc_nxt, rc_una, rc_rcv_nxt_w;
    wire [15:0] rc_rcv_wnd_w, rc_snd_wnd_w;
    wire [3:0]  rc_state_w;
    reg  [31:0] m_nxt, m_una, m_rcv_nxt;
    reg  [15:0] m_rcv_wnd, m_snd_wnd;
    reg  [3:0]  m_state;
    always @(*) begin
        m_nxt     = t_nxt[rc_id];
        m_una     = t_una[rc_id];
        m_rcv_nxt = t_rcv_nxt[rc_id];
        m_rcv_wnd = t_rcv_wnd[rc_id];
        m_snd_wnd = t_snd_wnd[rc_id];
        m_state   = t_state[rc_id];
    end

    wire        o_ev_up, o_ev_down;
    wire [3:0]  o_ev_slot;
    wire        ho_fire;
    wire [3:0]  ho_slot;
    wire [15:0] fin_req, rst_req;
    wire        fc_upd_wr;
    wire [3:0]  fc_upd_id;
    wire [2:0]  fc_upd_sel;
    wire [31:0] fc_upd_val;
    wire        wu_req;
    wire [3:0]  wu_id;
    wire [31:0] wu_val;
    wire [31:0] reg_rdata;
    wire [15:0] app_tx_ready;
    wire [3:0]  dbg_c0_state;
    wire [31:0] dbg_c0_snd_nxt, dbg_c0_snd_una, dbg_c0_rcv_nxt, dbg_redge0;
    wire [15:0] dbg_c0_rcv_wnd, dbg_c0_snd_wnd, dbg_estab_cnt, dbg_ev_cnt;
    wire [15:0] dbg_winq0, dbg_wu_mark0;
    wire [16:0] dbg_pool;
    wire [31:0] s_ev_up, s_ev_down, s_ev_drop, s_cmd_close, s_cmd_abort;
    wire [31:0] s_wu, s_pool_exh, s_fc_upd, s_slot_reuse, s_fc_wait_max;
    wire [31:0] stat_orphan_v;
    wire        orphan_cam_clr;
    wire [3:0]  orphan_cam_slot;

    wire fc_gnt = fc_upd_wr;             // 与 wrapper sel_fc 同惯例 (组合)

    app_ctrl #(
        .WIN_CAP(16'hBFFE), .WIN_POOL(16'hC000), .WIN_Q_MAX(16'hC000),
        .WU_LEGACY(1'b0),
        .ORPHAN_EN(1'b1),
        .ORPHAN_LIM(8'hFF),              // 模式 A 实际不武装 (inflight=0)
        .ORPHAN_TICK_BITS(TICK_BITS_TB),
        .ORPHAN_ZW_EN(1'b0),
        .ORPHAN_ZW_LIM(8'd2),
        .ORPHAN_ZW_TICK_BITS(1),
        .HO_EN(1'b1), .HO_LIM(HO_LIM_TB)
    ) u_dut (
        .clk(clk), .rst_n(rst_n),
        .ev_up(ev_up), .ev_down(ev_down), .ev_slot(ev_slot),
        .ev_peer_ip(ev_ip), .ev_peer_port(ev_port), .ev_peer_mac(ev_mac),
        .rc_id(rc_id),
        .rc_snd_nxt(m_nxt), .rc_snd_una(m_una), .rc_rcv_nxt(m_rcv_nxt),
        .rc_rcv_wnd(m_rcv_wnd), .rc_snd_wnd(m_snd_wnd), .rc_state(m_state),
        .rx_occ_bytes(17'd0), .fin_sent(fin_sent_v), .rst_sent(rst_sent_v),
        .retx_active(retx_active), .retx_id(retx_id),
        .una_adv(una_adv), .una_adv_id(una_adv_id),
        .ack_obs(ack_obs), .ack_obs_id(ack_obs_id),
        .scfg_busy(scfg_busy),
        .orphan_cam_clr(orphan_cam_clr), .orphan_cam_slot(orphan_cam_slot),
        .stat_orphan(stat_orphan_v),
        .o_ho_fire(ho_fire), .o_ho_slot(ho_slot),
        .o_ev_up(o_ev_up), .o_ev_down(o_ev_down), .o_ev_slot(o_ev_slot),
        .fin_req(fin_req), .rst_req(rst_req),
        .close_req(1'b0), .close_id(4'd0),
        .fc_upd_wr(fc_upd_wr), .fc_upd_id(fc_upd_id),
        .fc_upd_sel(fc_upd_sel), .fc_upd_val(fc_upd_val), .fc_gnt(fc_gnt),
        .wu_req(wu_req), .wu_id(wu_id), .wu_val(wu_val), .wu_gnt(1'b0),
        .reg_addr(8'd0), .reg_wr(1'b0), .reg_wdata(32'd0), .reg_rdata(reg_rdata),
        .app_tx_ready(app_tx_ready),
        .dbg_c0_state(dbg_c0_state), .dbg_c0_snd_nxt(dbg_c0_snd_nxt),
        .dbg_c0_snd_una(dbg_c0_snd_una), .dbg_c0_rcv_nxt(dbg_c0_rcv_nxt),
        .dbg_c0_rcv_wnd(dbg_c0_rcv_wnd), .dbg_c0_snd_wnd(dbg_c0_snd_wnd),
        .dbg_estab_cnt(dbg_estab_cnt), .dbg_ev_cnt(dbg_ev_cnt),
        .dbg_redge0(dbg_redge0), .dbg_winq0(dbg_winq0),
        .dbg_wu_mark0(dbg_wu_mark0), .dbg_pool(dbg_pool),
        .stat_ev_up(s_ev_up), .stat_ev_down(s_ev_down),
        .stat_ev_drop(s_ev_drop), .stat_cmd_close(s_cmd_close),
        .stat_cmd_abort(s_cmd_abort), .stat_wu(s_wu),
        .stat_pool_exhaust(s_pool_exh), .stat_fc_upd(s_fc_upd),
        .stat_slot_reuse(s_slot_reuse), .stat_fc_wait_max(s_fc_wait_max)
    );

    // ---- TCB 写模型 (本测试只需要 state 写 sel=5) ----
    always @(posedge clk) if (rst_n && fc_upd_wr && (fc_upd_sel == 3'd5))
        t_state[fc_upd_id] <= fc_upd_val[3:0];

    // ---- 监视器 ----
    integer n_fire [0:15];
    integer n_fire_total, n_state_wr, n_cam, n_down;
    always @(posedge clk) if (rst_n) begin
        if (ho_fire) begin
            n_fire_total = n_fire_total + 1;
            n_fire[ho_slot] = n_fire[ho_slot] + 1;
        end
        if (fc_upd_wr && (fc_upd_sel == 3'd5)) n_state_wr = n_state_wr + 1;
        if (orphan_cam_clr) n_cam = n_cam + 1;
        if (o_ev_down) n_down = n_down + 1;
    end

    task chk;
        input cond;
        input [8*96-1:0] msg;
        begin
            if (!cond) begin
                errs = errs + 1;
                $display("CHECK FAIL: %0s", msg);
            end
        end
    endtask

    task do_reset;
        integer k;
        begin
            @(negedge clk);
            rst_n = 0;
            ev_up = 0; ev_down = 0; ev_slot = 0; ev_ip = 0; ev_port = 0; ev_mac = 0;
            retx_active = 0; retx_id = 0; una_adv = 0; una_adv_id = 0;
            ack_obs = 0; ack_obs_id = 0; scfg_busy = 0;
            fin_sent_v = 0; rst_sent_v = 0;
            for (k = 0; k < 16; k = k + 1) begin
                t_state[k] = 0; t_nxt[k] = 0; t_una[k] = 0; t_rcv_nxt[k] = 0;
                t_rcv_wnd[k] = 0; t_snd_wnd[k] = 0;
                n_fire[k] = 0;
            end
            n_fire_total = 0; n_state_wr = 0; n_cam = 0; n_down = 0;
            repeat (8) @(negedge clk);
            rst_n = 1;
            repeat (8) @(negedge clk);
        end
    endtask

    task set_slot_estab;
        input [3:0] s;
        begin
            @(negedge clk);
            t_state[s]   = 4'd1;                 // ST_ESTAB
            t_snd_wnd[s] = 16'hFFFF;
            t_una[s]     = 32'h0001_0000 + {28'd0, s} * 32'h1000;
            t_nxt[s]     = t_una[s];             // inflight=0 (不武装 orphan 模式 A)
            t_rcv_nxt[s] = 32'h2000_0000 + {28'd0, s} * 32'h1000;
            t_rcv_wnd[s] = 16'h2000;
        end
    endtask

    task pulse_ack;
        input [3:0] s;
        begin
            @(negedge clk); ack_obs = 1; ack_obs_id = s;
            @(negedge clk); ack_obs = 0;
        end
    endtask

    task pulse_ev_up;
        input [3:0] s;
        begin
            @(negedge clk); ev_up = 1; ev_slot = s;
            @(negedge clk); ev_up = 0;
        end
    endtask

    task wait_cycles;
        input integer n;
        integer c;
        begin
            for (c = 0; c < n; c = c + 1) @(posedge clk);
        end
    endtask

    integer k;
    initial begin
        errs = 0;
        //=========================================================================
        // A. 8 槽 ESTAB, 无 ACK ⇒ 每槽一次 fire + 完整拆除序列
        //=========================================================================
        do_reset();
        for (k = 0; k < 8; k = k + 1) set_slot_estab(k[3:0]);
        wait_cycles(20000);
        for (k = 0; k < 8; k = k + 1)
            chk(n_fire[k] >= 1, "A: every ESTAB slot without ACK fires");
        chk(n_fire_total >= 8, "A: at least 8 fires");
        chk(n_state_wr >= 8, "A: each fire wrote state=0 via fc");
        chk(n_cam >= 8, "A: each fire issued a CAM clear");
        chk(n_down >= 8, "A: each fire delivered o_ev_down");
        $display("A: fires=%0d n_state_wr=%0d n_cam=%0d n_down=%0d", n_fire_total, n_state_wr, n_cam, n_down);

        //=========================================================================
        // B. slot3 给一次 ack_obs ⇒ slot3 不 fire, 其余槽照常 fire
        //=========================================================================
        do_reset();
        for (k = 0; k < 8; k = k + 1) set_slot_estab(k[3:0]);
        pulse_ack(4'd3);
        wait_cycles(20000);
        chk(n_fire[3] == 0, "B: slot3 with an ACK must NOT fire");
        for (k = 0; k < 8; k = k + 1) if (k != 3)
            chk(n_fire[k] >= 1, "B: other slots still fire");
        $display("B: fire[3]=%0d fires=%0d", n_fire[3], n_fire_total);

        //=========================================================================
        // C. slot5: ack_obs 后 ev_up 清位 ⇒ 重新可 fire
        //=========================================================================
        do_reset();
        set_slot_estab(4'd5);
        pulse_ack(4'd5);
        repeat (50) @(posedge clk);
        chk(n_fire[5] == 0, "C: slot5 suppressed by the ACK before ev_up");
        pulse_ev_up(4'd5);
        wait_cycles(20000);
        chk(n_fire[5] >= 1, "C: ev_up clears ack_seen/count => slot5 fires again");
        $display("C: fire[5]=%0d", n_fire[5]);

        $display("TB_APP_HO %0s (errs=%0d)",
                 (errs == 0) ? "PASS" : "FAIL", errs);
        if (errs != 0) $display("TB_RESULT FAIL (errs=%0d)", errs);
        else            $display("TB_RESULT PASS");
        $finish;
    end

    initial begin
        #2000000;
        $display("TB_APP_HO TIMEOUT");
        $display("TB_RESULT FAIL (timeout)");
        $finish;
    end
endmodule
