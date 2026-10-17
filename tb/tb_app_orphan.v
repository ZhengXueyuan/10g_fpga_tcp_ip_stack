`timescale 1ns/1ps
//=============================================================================
// tb_app_orphan: p9 orphan fix 单元门 (设计件 v4 §6.1, U1..U12 + U10')
//
// 结构: app_ctrl 单元 + TB 侧 16 槽 TCB 行为模型 (组合读口 C 的 mux 由 DUT 的
// rc_id 选) + 组合 gnt (fc_gnt = fc_upd_wr, 与 wrapper 的 sel_fc 同惯例).
// 另外并行例化 U10' 的冻结锚 (frozen/app_ctrl_head_cc7af9a8__as_app_ctrl_frozen.v,
// 模块名 app_ctrl_frozen) —— 只有 +SCEN=17 时比较输出.
//
// 参数 (xelab -generic_top):
//   ORPHAN_EN_TB / ORPHAN_ZW_EN_TB / ORPHAN_LIM_TB
// 场景 (+SCEN=n):
//    1 U1 健康推进      2 U2 孤儿模式A     3 U3 零窗负对照    4 U4 慢盆(abc)
//    5 U5 回卷重放      6 U5b 活动 retx   7 U6 ADD 竞态(pre/post)
//    8 U6b 双槽+交接    9 U6c state→CAM 窗口  10 U7 通知顺序
//   11 U8 DEL 竞态     12 U9 饱和        13 U10 EN=0 冒烟
//   14 U11 模式B       15 U12 模式B负对照 16 U12b 单次丢失
//   17 U10' 零回归 (冻结锚逐拍对比)   18 U9B to_push 碰撞
//
// 判定: TB_RESULT PASS / TB_RESULT FAIL (errs=N). 变异门期望 FAIL.
//=============================================================================
module tb_app_orphan #(
    parameter integer ORPHAN_EN_TB    = 1,
    parameter integer ORPHAN_ZW_EN_TB = 0,
    parameter [7:0]   ORPHAN_LIM_TB   = 8'd2
);
    localparam [7:0]  ORPHAN_ZW_LIM_TB = 8'd2;
    localparam integer TICK_BITS_TB    = 1;
    localparam integer ZW_TICK_BITS_TB = 1;

    reg clk = 0;
    always #4 clk = ~clk;               // 125MHz (8ns)

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

    integer scen;
    integer errs;
    integer i, k;
    reg [8*64-1:0] scen_name;

    //=========================================================================
    // TB 侧 TCB 行为模型 (主 DUT) + 冻结锚模型
    //=========================================================================
    reg [3:0]  t_state   [0:15];
    reg [31:0] t_nxt     [0:15];
    reg [31:0] t_una     [0:15];
    reg [31:0] t_rcv_nxt [0:15];
    reg [15:0] t_rcv_wnd [0:15];
    reg [15:0] t_snd_wnd [0:15];

    reg [3:0]  f_state   [0:15];
    reg [31:0] f_nxt     [0:15];
    reg [31:0] f_una     [0:15];
    reg [31:0] f_rcv_nxt [0:15];
    reg [15:0] f_rcv_wnd [0:15];
    reg [15:0] f_snd_wnd [0:15];

    // ---- 主 DUT ----
    wire [3:0]  rc_id;
    wire [31:0] rc_nxt, rc_una, rc_rcv_nxt;
    wire [15:0] rc_rcv_wnd, rc_snd_wnd;
    wire [3:0]  rc_state;
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
    wire [31:0] stat_orphan;
    wire        orphan_cam_clr;
    wire [3:0]  orphan_cam_slot;

    wire fc_gnt = fc_upd_wr;             // wrapper 的 sel_fc 同惯例 (组合)

    app_ctrl #(
        .WIN_CAP(16'hBFFE), .WIN_POOL(16'hC000), .WIN_Q_MAX(16'hC000),
        .WU_LEGACY(1'b0),
        .ORPHAN_EN(ORPHAN_EN_TB),
        .ORPHAN_LIM(ORPHAN_LIM_TB),
        .ORPHAN_TICK_BITS(TICK_BITS_TB),
        .ORPHAN_ZW_EN(ORPHAN_ZW_EN_TB),
        .ORPHAN_ZW_LIM(ORPHAN_ZW_LIM_TB),
        .ORPHAN_ZW_TICK_BITS(ZW_TICK_BITS_TB)
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
        .stat_orphan(stat_orphan),
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

    // ---- 冻结锚 (U10') ----
    wire [3:0]  frz_rc_id;
    reg  [31:0] f_mux_nxt, f_mux_una, f_mux_rcv_nxt;
    reg  [15:0] f_mux_rcv_wnd, f_mux_snd_wnd;
    reg  [3:0]  f_mux_state;
    always @(*) begin
        f_mux_nxt     = f_nxt[frz_rc_id];
        f_mux_una     = f_una[frz_rc_id];
        f_mux_rcv_nxt = f_rcv_nxt[frz_rc_id];
        f_mux_rcv_wnd = f_rcv_wnd[frz_rc_id];
        f_mux_snd_wnd = f_snd_wnd[frz_rc_id];
        f_mux_state   = f_state[frz_rc_id];
    end
    wire        frz_ev_up, frz_ev_down;
    wire [3:0]  frz_ev_slot;
    wire [15:0] frz_fin_req, frz_rst_req;
    wire        frz_fc_wr;
    wire [3:0]  frz_fc_id;
    wire [2:0]  frz_fc_sel;
    wire [31:0] frz_fc_val;
    wire        frz_wu_req;
    wire [3:0]  frz_wu_id;
    wire [31:0] frz_wu_val;
    wire [31:0] frz_rdata;
    wire [15:0] frz_tx_ready;
    wire [3:0]  frz_c0_state;
    wire [31:0] frz_c0_nxt, frz_c0_una, frz_c0_rcv, frz_redge0;
    wire [15:0] frz_c0_rwnd, frz_c0_swnd, frz_estab, frz_evcnt;
    wire [15:0] frz_winq0, frz_wumark0;
    wire [16:0] frz_pool;
    wire [31:0] frz_s_up, frz_s_down, frz_s_drop, frz_s_close, frz_s_abort;
    wire [31:0] frz_s_wu, frz_s_pexh, frz_s_fc, frz_s_reuse, frz_s_fcwait;
    wire frz_fc_gnt = frz_fc_wr;

    app_ctrl_frozen #(
        .WIN_CAP(16'hBFFE), .WIN_POOL(16'hC000), .WIN_Q_MAX(16'hC000),
        .WU_LEGACY(1'b0)
    ) u_frz (
        .clk(clk), .rst_n(rst_n),
        .ev_up(ev_up), .ev_down(ev_down), .ev_slot(ev_slot),
        .ev_peer_ip(ev_ip), .ev_peer_port(ev_port), .ev_peer_mac(ev_mac),
        .rc_id(frz_rc_id),
        .rc_snd_nxt(f_mux_nxt), .rc_snd_una(f_mux_una), .rc_rcv_nxt(f_mux_rcv_nxt),
        .rc_rcv_wnd(f_mux_rcv_wnd), .rc_snd_wnd(f_mux_snd_wnd), .rc_state(f_mux_state),
        .rx_occ_bytes(17'd0), .fin_sent(fin_sent_v), .rst_sent(rst_sent_v),
        .o_ev_up(frz_ev_up), .o_ev_down(frz_ev_down), .o_ev_slot(frz_ev_slot),
        .fin_req(frz_fin_req), .rst_req(frz_rst_req),
        .close_req(1'b0), .close_id(4'd0),
        .fc_upd_wr(frz_fc_wr), .fc_upd_id(frz_fc_id),
        .fc_upd_sel(frz_fc_sel), .fc_upd_val(frz_fc_val), .fc_gnt(frz_fc_gnt),
        .wu_req(frz_wu_req), .wu_id(frz_wu_id), .wu_val(frz_wu_val), .wu_gnt(1'b0),
        .reg_addr(8'd0), .reg_wr(1'b0), .reg_wdata(32'd0), .reg_rdata(frz_rdata),
        .app_tx_ready(frz_tx_ready),
        .dbg_c0_state(frz_c0_state), .dbg_c0_snd_nxt(frz_c0_nxt),
        .dbg_c0_snd_una(frz_c0_una), .dbg_c0_rcv_nxt(frz_c0_rcv),
        .dbg_c0_rcv_wnd(frz_c0_rwnd), .dbg_c0_snd_wnd(frz_c0_swnd),
        .dbg_estab_cnt(frz_estab), .dbg_ev_cnt(frz_evcnt),
        .dbg_redge0(frz_redge0), .dbg_winq0(frz_winq0),
        .dbg_wu_mark0(frz_wumark0), .dbg_pool(frz_pool),
        .stat_ev_up(frz_s_up), .stat_ev_down(frz_s_down),
        .stat_ev_drop(frz_s_drop), .stat_cmd_close(frz_s_close),
        .stat_cmd_abort(frz_s_abort), .stat_wu(frz_s_wu),
        .stat_pool_exhaust(frz_s_pexh), .stat_fc_upd(frz_s_fc),
        .stat_slot_reuse(frz_s_reuse), .stat_fc_wait_max(frz_s_fcwait)
    );

    // ---- TCB 写模型 (主 DUT / 冻结锚各一份, 只实现本次用到的 sel 3/5) ----
    always @(posedge clk) if (rst_n && fc_upd_wr) begin
        case (fc_upd_sel)
            3'd5: t_state[fc_upd_id]   <= fc_upd_val[3:0];
            3'd3: t_rcv_wnd[fc_upd_id] <= fc_upd_val[15:0];
            default: ;
        endcase
    end
    always @(posedge clk) if (rst_n && frz_fc_wr) begin
        case (frz_fc_sel)
            3'd5: f_state[frz_fc_id]   <= frz_fc_val[3:0];
            3'd3: f_rcv_wnd[frz_fc_id] <= frz_fc_val[15:0];
            default: ;
        endcase
    end

    //=========================================================================
    // 监视器 (per-run 计数; do_reset 清零)
    //=========================================================================
    integer n_wr [0:15];
    integer n_cam, n_down, n_up, n_orphan_pulse;
    reg [15:0] down_slots;
    reg cam_before_done, cam_in_busy, down_consec, o_down_d, to_push_collision;
    reg down_before_cam, down_before_done;
    reg ev_down_i_mismatch;
    integer n_cmp, n_mismatch;

    always @(posedge clk) if (rst_n) begin
        if (fc_upd_wr && (fc_upd_sel == 3'd5)) n_wr[fc_upd_id] = n_wr[fc_upd_id] + 1;
        if (orphan_cam_clr) begin
            n_cam = n_cam + 1;
            if (!u_dut.orph_state_done) cam_before_done = 1'b1;
            if (scfg_busy)              cam_in_busy     = 1'b1;
        end
        if (o_ev_down) begin
            n_down = n_down + 1;
            down_slots[o_ev_slot] = 1'b1;
            if (o_down_d) down_consec = 1'b1;
            if (n_cam == 0) down_before_cam = 1'b1;
            if (!u_dut.orph_state_done) down_before_done = 1'b1;
        end
        o_down_d <= o_ev_down;
        if (o_ev_up) n_up = n_up + 1;
        if (u_dut.orph_down_r) n_orphan_pulse = n_orphan_pulse + 1;
        // M9 牙: 孤儿投递拍不得与超时事件投递同拍 (o_ev_slot 会错配)
        if (u_dut.orph_down_i && u_dut.to_push) to_push_collision = 1'b1;
        // ORPHAN_EN=0 纪律: ev_down_i 必须 ≡ ev_down (逐拍)
        if (u_dut.ev_down_i !== ev_down) ev_down_i_mismatch = 1'b1;
        // U10' 逐拍逐位对比
        if (scen == 17) begin
            n_cmp = n_cmp + 1;
            if ((o_ev_up !== frz_ev_up) || (o_ev_down !== frz_ev_down) ||
                (o_ev_slot !== frz_ev_slot) || (s_ev_up !== frz_s_up) ||
                (s_ev_down !== frz_s_down) || (dbg_pool !== frz_pool) ||
                (dbg_winq0 !== frz_winq0) || (app_tx_ready !== frz_tx_ready)) begin
                n_mismatch = n_mismatch + 1;
                if (n_mismatch < 8)
                    $display("U10P MISMATCH t=%0t up=%b/%b dn=%b/%b slot=%0d/%0d su=%0d/%0d sd=%0d/%0d pool=%0d/%0d winq=%h/%h rdy=%h/%h",
                             $time, o_ev_up, frz_ev_up, o_ev_down, frz_ev_down,
                             o_ev_slot, frz_ev_slot, s_ev_up, frz_s_up, s_ev_down,
                             frz_s_down, dbg_pool, frz_pool, dbg_winq0, frz_winq0,
                             app_tx_ready, frz_tx_ready);
            end
        end
    end

    //=========================================================================
    // 任务
    //=========================================================================
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
        integer j;
        begin
            @(negedge clk);
            rst_n = 0;
            ev_up = 0; ev_down = 0; ev_slot = 0; ev_ip = 0; ev_port = 0; ev_mac = 0;
            retx_active = 0; retx_id = 0; una_adv = 0; una_adv_id = 0;
            ack_obs = 0; ack_obs_id = 0; scfg_busy = 0;
            fin_sent_v = 0; rst_sent_v = 0;
            for (j = 0; j < 16; j = j + 1) begin
                t_state[j] = 0; t_nxt[j] = 0; t_una[j] = 0; t_rcv_nxt[j] = 0;
                t_rcv_wnd[j] = 0; t_snd_wnd[j] = 0;
                f_state[j] = 0; f_nxt[j] = 0; f_una[j] = 0; f_rcv_nxt[j] = 0;
                f_rcv_wnd[j] = 0; f_snd_wnd[j] = 0;
                n_wr[j] = 0;
            end
            n_cam = 0; n_down = 0; n_up = 0; n_orphan_pulse = 0;
            down_slots = 0; cam_before_done = 0; cam_in_busy = 0;
            down_consec = 0; o_down_d = 0; to_push_collision = 0;
            down_before_cam = 0; down_before_done = 0;
            ev_down_i_mismatch = 0; n_cmp = 0; n_mismatch = 0;
            repeat (8) @(negedge clk);
            rst_n = 1;
            repeat (6) @(negedge clk);
        end
    endtask

    task set_slot;
        input [3:0]  s;
        input [3:0]  st;
        input [15:0] wnd;
        input [31:0] inflight;
        input [15:0] rcwnd;
        begin
            @(negedge clk);
            t_state[s]   = st;
            t_snd_wnd[s] = wnd;
            t_una[s]     = 32'h0001_0000 + {28'd0, s} * 32'h1000;
            t_nxt[s]     = t_una[s] + inflight;
            t_rcv_nxt[s] = 32'h2000_0000 + {28'd0, s} * 32'h1000;
            t_rcv_wnd[s] = rcwnd;
            // 冻结锚镜像
            f_state[s]   = st;
            f_snd_wnd[s] = wnd;
            f_una[s]     = t_una[s];
            f_nxt[s]     = t_nxt[s];
            f_rcv_nxt[s] = t_rcv_nxt[s];
            f_rcv_wnd[s] = rcwnd;
        end
    endtask

    task set_inflight;
        input [3:0]  s;
        input [31:0] inflight;
        begin
            @(negedge clk);
            t_nxt[s] = t_una[s] + inflight;
            f_nxt[s] = t_nxt[s];
        end
    endtask

    task pulse_retx;
        input [3:0] s;
        input integer ncyc;
        integer j;
        begin
            for (j = 0; j < ncyc; j = j + 1) begin
                @(negedge clk); retx_active = 1; retx_id = s;
            end
            @(negedge clk); retx_active = 0;
        end
    endtask

    task pulse_ack;
        input [3:0] s;
        begin
            @(negedge clk); ack_obs = 1; ack_obs_id = s;
            @(negedge clk); ack_obs = 0;
        end
    endtask

    task pulse_una_adv;
        input [3:0]  s;
        input [31:0] delta;
        begin
            @(negedge clk);
            t_una[s] = t_una[s] + delta;
            t_nxt[s] = t_nxt[s] + delta;
            f_una[s] = t_una[s];
            f_nxt[s] = t_nxt[s];
            una_adv = 1; una_adv_id = s;
            @(negedge clk);
            una_adv = 0;
        end
    endtask

    task pulse_ev_up;
        input [3:0] s;
        begin
            @(negedge clk); ev_up = 1; ev_slot = s;
            @(negedge clk); ev_up = 0;
        end
    endtask

    task pulse_ev_down;
        input [3:0] s;
        begin
            @(negedge clk); ev_down = 1; ev_slot = s;
            @(negedge clk); ev_down = 0;
        end
    endtask

    task wait_cycles;
        input integer ncyc;
        begin
            repeat (ncyc) @(negedge clk);
        end
    endtask

    task wait_rounds;
        input integer nrd;
        begin
            repeat (nrd * 256) @(negedge clk);
        end
    endtask

    task wait_down;
        input integer max_rounds;
        integer j;
        begin
            j = 0;
            while ((n_down == 0) && (j < max_rounds * 256)) begin
                @(negedge clk); j = j + 1;
            end
        end
    endtask

    task wait_stat;
        input integer want;
        input integer max_rounds;
        integer j;
        begin
            j = 0;
            while ((stat_orphan < want) && (j < max_rounds * 256)) begin
                @(negedge clk); j = j + 1;
            end
        end
    endtask

    task wait_fire;
        input integer max_rounds;
        integer j;
        begin
            j = 0;
            while (!u_dut.orph_state_req && (j < max_rounds * 256)) begin
                @(negedge clk); j = j + 1;
            end
        end
    endtask

    //=========================================================================
    // 主激励
    //=========================================================================
    initial begin
        rst_n = 0; ev_up = 0; ev_down = 0; ev_slot = 0; ev_ip = 0; ev_port = 0;
        ev_mac = 0; retx_active = 0; retx_id = 0; una_adv = 0; una_adv_id = 0;
        ack_obs = 0; ack_obs_id = 0; scfg_busy = 0; fin_sent_v = 0; rst_sent_v = 0;
        errs = 0;
        if (!$value$plusargs("SCEN=%d", scen)) scen = 1;
        scen_name = "U?";
        do_reset;

        case (scen)
        //------------------------------------------------ U1 健康推进
        1: begin
            scen_name = "U1";  // LIM=2: 每 round 一次 snd_una 推进 (>= 每 tick)
            set_slot(0, 4'd1, 16'hF000, 32'hF000, 16'hC000);
            for (i = 0; i < 8; i = i + 1) begin
                pulse_retx(0, 2);
                pulse_una_adv(0, 32'd1);
                wait_rounds(1);
            end
            chk(stat_orphan == 0, "U1 stat_orphan must be 0 (healthy progress)");
            chk(n_wr[0] == 0, "U1 no state write");
            chk(n_cam == 0, "U1 no CAM clear");
            chk(ev_down_i_mismatch == 0, "U1 ev_down_i mismatch");
        end
        //------------------------------------------------ U2 孤儿模式A
        2: begin
            scen_name = "U2";
            set_slot(0, 4'd1, 16'hF000, 32'hF000, 16'hC000);
            pulse_retx(0, 2);
            wait_stat(1, 30);
            wait_rounds(2);
            chk(stat_orphan == 1, "U2 exactly 1 orphan commit");
            chk(n_wr[0] == 1, "U2 exactly 1 state=0 write on slot0");
            chk(n_cam == 1, "U2 exactly 1 CAM clear");
            chk(cam_before_done == 0, "U2 CAM clear must follow orph_state_done");
            chk(n_down == 1 && down_slots[0], "U2 exactly 1 o_ev_down on slot0");
            chk(down_consec == 0, "U2 no multi-cycle o_ev_down");
            chk(t_state[0] == 4'd0, "U2 TCB state=0 landed");
        end
        //------------------------------------------------ U3 零窗负对照 (Mode A)
        3: begin
            scen_name = "U3";
            set_slot(0, 4'd1, 16'h0000, 32'hF000, 16'hC000);
            pulse_retx(0, 2);
            wait_rounds(8);
            chk(stat_orphan == 0, "U3 zero-window must not fire Mode A");
            chk(n_wr[0] == 0 && n_cam == 0 && n_down == 0, "U3 no side effects");
        end
        //------------------------------------------------ U4 慢盆 (a/b/c)
        4: begin
            scen_name = "U4";
            // U4a: 慢进度 (<LIM) + 小在飞
            set_slot(0, 4'd1, 16'hF000, 32'h100, 16'hC000);
            for (i = 0; i < 8; i = i + 1) begin
                pulse_una_adv(0, 32'd1);
                wait_rounds(1);
            end
            chk(stat_orphan == 0, "U4a slow basin must not fire");
            // U4b: 小在飞冻结, 无重传
            do_reset;
            set_slot(0, 4'd1, 16'hF000, 32'h100, 16'hC000);
            wait_rounds(6);
            chk(stat_orphan == 0, "U4b frozen-small no retx must not fire");
            // U4c: saw=1 后再小在飞冻结、无活动 retx (M4' 牙)
            do_reset;
            set_slot(0, 4'd1, 16'hF000, 32'h100, 16'hC000);
            pulse_retx(0, 2);
            wait_rounds(6);
            chk(stat_orphan == 0, "U4c saw=1 small inflight no active retx must not fire");
            chk(n_cam == 0 && n_wr[0] == 0, "U4c no recovery");
        end
        //------------------------------------------------ U5 回卷重放
        5: begin
            scen_name = "U5";
            // U5a: 回卷重放态 (nxt==una, retx_active) —— work 的 retx 覆盖必须让
            //      计数推进 (M3 牙: 删 retx 覆盖 ⇒ accrue=false ⇒ 不点火).
            set_slot(0, 4'd1, 16'hF000, 32'h0000, 16'hC000);
            @(negedge clk); retx_active = 1; retx_id = 0;
            wait_stat(1, 20);
            @(negedge clk); retx_active = 0;
            chk(stat_orphan == 1, "U5a replay (nxt==una, retx) must fire via retx witness");
            chk(n_wr[0] == 1 && n_cam == 1, "U5a recovery landed");
            // U5b: 回卷 LIM/2 ticks 后回到正常 ⇒ 计数不清零、按时点火
            do_reset;
            set_slot(0, 4'd1, 16'hF000, 32'h0000, 16'hC000);
            pulse_retx(0, 512);                 // LIM/2 ticks = 1 tick
            set_inflight(0, 32'hF000);          // 回到正常
            wait_stat(1, 30);
            chk(stat_orphan == 1, "U5b replay carry-over must fire");
            chk(n_wr[0] == 1 && n_cam == 1, "U5b recovery landed");
        end
        //------------------------------------------------ U5b 活动 retx 支
        6: begin
            scen_name = "U5b";
            set_slot(0, 4'd1, 16'hF000, 32'h100, 16'hC000);
            @(negedge clk); retx_active = 1; retx_id = 0;
            wait_stat(1, 30);
            @(negedge clk); retx_active = 0;
            chk(stat_orphan == 1, "U5b active-retx branch must fire (inflight<cap)");
            chk(n_wr[0] == 1, "U5b state write");
        end
        //------------------------------------------------ U6 ADD 竞态 pre/post
        7: begin
            scen_name = "U6";
            // pre-fire: cnt=LIM-1 时同槽 ev_up
            set_slot(0, 4'd1, 16'hF000, 32'hF000, 16'hC000);
            pulse_retx(0, 2);
            wait_rounds(2);                     // count -> 1
            u_dut.orph_cnt[0] = 8'd1;           // 层次赋值 (xsim 禁止 force 位选非网)
            @(negedge clk); @(negedge clk);
            pulse_ev_up(0);
            wait_rounds(4);
            chk(stat_orphan == 0, "U6 pre-fire: same-slot ev_up must abort (no orphan down)");
            chk(n_cam == 0, "U6 pre-fire: no CAM clear");
            chk(u_dut.st_pend[0] == 1'b0, "U6 pre-fire: st_pend cleared");
            // post-fire: state=0 已落地、CAM 清未发时同槽 ev_up
            do_reset;
            set_slot(0, 4'd1, 16'hF000, 32'hF000, 16'hC000);
            pulse_retx(0, 2);
            wait_fire(30);
            k = 0;
            while (!u_dut.orph_state_done && k < 200) begin
                @(negedge clk); k = k + 1;
            end
            chk(k < 200, "U6 post-fire: orph_state_done observed");
            scfg_busy = 1;                      // 同一 negedge 卡住下一拍的 CAM 清
            pulse_ev_up(0);                     // 同槽新会话接管
            wait_cycles(5);
            @(negedge clk); scfg_busy = 0;
            wait_rounds(6);
            chk(stat_orphan == 0, "U6 post-fire: ev_up must abort (no orphan commit)");
            chk(n_cam == 0, "U6 post-fire: no CAM clear");
            chk(n_down == 0, "U6 post-fire: no orphan o_ev_down");
            chk(u_dut.st_pend[0] == 1'b0, "U6 post-fire: st_pend cleared");
        end
        //------------------------------------------------ U6b 双槽 + 交接拍
        8: begin
            scen_name = "U6b";
            // (a) 相邻扫描拍双槽同时达限
            set_slot(0, 4'd1, 16'hF000, 32'hF000, 16'hC000);
            set_slot(1, 4'd1, 16'hF000, 32'hF000, 16'hC000);
            pulse_retx(0, 2); pulse_retx(1, 2);
            // 第一槽点火后把 FSM 卡在 CAM 清 (scfg_busy), 让相邻扫描拍的第二槽
            // 在 FSM 仍活跃时达限 —— 这才是 N3 的测试点 (FSM 本身 ~8 拍就完成,
            // 不卡住时相邻扫描拍根本不重叠).
            wait_fire(30);
            @(negedge clk); scfg_busy = 1;
            wait_cycles(40);
            @(negedge clk); scfg_busy = 0;
            wait_stat(2, 60);
            wait_rounds(2);
            chk(stat_orphan == 2, "U6b adjacent: both slots must complete (stat=2)");
            chk(n_wr[0] == 1 && n_wr[1] == 1, "U6b adjacent: each slot 1 state write");
            chk(n_cam == 2, "U6b adjacent: each slot 1 CAM clear");
            chk(down_slots[1:0] == 2'b11, "U6b adjacent: both o_ev_down");
            chk(t_state[0] == 0 && t_state[1] == 0, "U6b adjacent: both state=0");
            // (b) 交接拍臂: 第一槽停在 wait_cam→notify_pend 交接拍时第二槽达限
            do_reset;
            set_slot(0, 4'd1, 16'hF000, 32'hF000, 16'hC000);
            t_state[1] = 4'd0; f_state[1] = 4'd0;   // 第二槽暂不 accrue
            pulse_retx(0, 2);
            wait_fire(30);
            // 等 cam clr 回落拍 (cam_clr_done = wait_cam && !clr)
            k = 0;
            while (!(u_dut.orph_wait_cam && !u_dut.orphan_cam_clr_r) && k < 5000) begin
                @(negedge clk); k = k + 1;
            end
            chk(k < 5000, "U6b handoff: cam_clr_done observed");
            // 下一拍 = 交接拍 (正确实现 busy 由 notify_pend 保持; 拆两拍的变异为 0)
            @(negedge clk);
            set_slot(1, 4'd1, 16'hF000, 32'hF000, 16'hC000);
            u_dut.orph_cnt[1] = 8'd2;           // 层次赋值 (位选 non-net 不能 force)
            u_dut.orph_saw[1] = 1'b1;
            force u_dut.scan_tick  = 1'b1;      // 1 位网
            force u_dut.scan_id    = 4'd1;      // 整寄存器 (无位选)
            @(posedge clk);                     // 强制扫描 slot1 落在交接拍
            @(negedge clk);
            release u_dut.scan_tick;
            release u_dut.scan_id;
            wait_stat(2, 40);
            wait_rounds(2);
            chk(stat_orphan == 2, "U6b handoff: both slots complete (stat=2)");
            chk(n_wr[0] == 1 && n_wr[1] == 1, "U6b handoff: both state writes");
            chk(n_cam == 2, "U6b handoff: both CAM clears");
            chk(down_slots[1:0] == 2'b11, "U6b handoff: both o_ev_down (no half recovery)");
        end
        //------------------------------------------------ U6c state-gnt→CAM 窗口
        9: begin
            scen_name = "U6c";
            // (a) 无 busy: state_done 前不得有 CAM 清
            set_slot(0, 4'd1, 16'hF000, 32'hF000, 16'hC000);
            pulse_retx(0, 2);
            wait_stat(1, 30);
            wait_rounds(2);
            chk(cam_before_done == 0, "U6c(a): no CAM clear before orph_state_done");
            chk(n_cam == 1, "U6c(a): exactly 1 CAM clear");
            // (b) busy 保持 N 拍: busy 期间无 CAM 清, 释放后恰 1 个
            do_reset;
            set_slot(0, 4'd1, 16'hF000, 32'hF000, 16'hC000);
            pulse_retx(0, 2);
            wait_fire(30);
            @(negedge clk); scfg_busy = 1;
            wait_cycles(20);
            chk(n_cam == 0, "U6c(b): no CAM clear while scfg_busy");
            @(negedge clk); scfg_busy = 0;
            wait_stat(1, 30);
            chk(n_cam == 1, "U6c(b): exactly 1 CAM clear after busy release");
            chk(cam_in_busy == 0, "U6c(b): cam clear never while busy");
        end
        //------------------------------------------------ U7 通知顺序
        10: begin
            scen_name = "U7";
            set_slot(0, 4'd1, 16'hF000, 32'hF000, 16'hC000);
            pulse_retx(0, 2);
            wait_fire(30);
            @(negedge clk); scfg_busy = 1;
            wait_cycles(20);
            @(negedge clk); scfg_busy = 0;
            wait_stat(1, 30);
            wait_rounds(2);
            chk(stat_orphan == 1 && n_down == 1, "U7 exactly one notification");
            chk(down_consec == 0, "U7 no duplicate/consecutive o_ev_down");
            chk(n_cam == 1, "U7 CAM clear before notify");
            chk(cam_before_done == 0, "U7 CAM clear strictly after state_done");
            chk(cam_in_busy == 0, "U7 CAM clear not while busy");
            chk(down_before_cam == 0, "U7 notify strictly after CAM clear");
            chk(down_before_done == 0, "U7 notify strictly after state_done");
        end
        //------------------------------------------------ U8 DEL 竞态
        11: begin
            scen_name = "U8";
            set_slot(0, 4'd1, 16'hF000, 32'hF000, 16'hC000);
            pulse_retx(0, 2);
            wait_fire(30);
            @(negedge clk); scfg_busy = 1;
            wait_cycles(5);
            pulse_ev_down(0);                   // 等待期同槽 DEL
            wait_cycles(15);
            @(negedge clk); scfg_busy = 0;
            wait_rounds(5);
            chk(stat_orphan == 0, "U8 same-slot ev_down must abort (no orphan commit)");
            chk(n_cam == 0, "U8 no CAM clear");
            chk(n_down == 1 && down_slots[0], "U8 exactly the real ev_down notification");
            chk(u_dut.orph_state_req == 0 && u_dut.orph_cam_req == 0,
                "U8 pending cleared");
        end
        //------------------------------------------------ U9 饱和
        12: begin
            scen_name = "U9";
            // 自然饱和: 用 blocker FSM 保持 orph_busy, 另一槽计数 260 ticks (>255).
            set_slot(0, 4'd1, 16'hF000, 32'hF000, 16'hC000);
            set_slot(1, 4'd1, 16'hF000, 32'hF000, 16'hC000);
            pulse_retx(0, 2); pulse_retx(1, 2);
            wait_fire(30);                      // 先点火的那个成为 blocker
            @(negedge clk); scfg_busy = 1;      // 把当前 FSM 卡在 cam_req
            wait_cycles(20);
            if (u_dut.orph_slot == 4'd0) begin
                wait_rounds(520);               // 260 ticks: slot1 自然饱和
                chk(u_dut.orph_cnt[1] == 8'hFF, "U9 slot1 counter saturates at 0xFF (no wrap)");
            end else begin
                wait_rounds(520);
                chk(u_dut.orph_cnt[0] == 8'hFF, "U9 slot0 counter saturates at 0xFF (no wrap)");
            end
            @(negedge clk); scfg_busy = 0;
            wait_stat(2, 80);
            wait_rounds(3);
            chk(stat_orphan == 2, "U9 both slots recovered (one fire each)");
            chk(n_cam == 2, "U9 two CAM clears");
            wait_rounds(3);
            chk(stat_orphan == 2, "U9 no second fire (st_done guard)");
        end
        //------------------------------------------------ U10 EN=0 冒烟
        13: begin
            scen_name = "U10";
            // 注: 本场景必须用 -generic_top ORPHAN_EN_TB=0 编译
            set_slot(0, 4'd1, 16'hF000, 32'hF000, 16'hC000);
            pulse_retx(0, 2);
            wait_rounds(10);
            chk(ORPHAN_EN_TB == 0, "U10 requires ORPHAN_EN_TB=0");
            chk(stat_orphan == 0, "U10 stat_orphan == 0");
            chk(orphan_cam_clr == 0, "U10 orphan_cam_clr == 0");
            chk(n_wr[0] == 0 && n_cam == 0 && n_down == 0, "U10 no side effects");
            chk(ev_down_i_mismatch == 0, "U10 ev_down_i == ev_down");
        end
        //------------------------------------------------ U11 模式B 点火
        14: begin
            scen_name = "U11";
            chk(ORPHAN_ZW_EN_TB == 1, "U11 requires ORPHAN_ZW_EN_TB=1");
            set_slot(0, 4'd1, 16'h0000, 32'hF000, 16'hC000);
            wait_stat(1, 30);
            wait_rounds(2);
            chk(stat_orphan == 1, "U11 dead zero-window must fire Mode B");
            chk(n_wr[0] == 1 && n_cam == 1, "U11 recovery landed");
            chk(down_slots[0], "U11 o_ev_down slot0");
        end
        //------------------------------------------------ U12 模式B 负对照
        15: begin
            scen_name = "U12";
            chk(ORPHAN_ZW_EN_TB == 1, "U12 requires ORPHAN_ZW_EN_TB=1");
            set_slot(0, 4'd1, 16'h0000, 32'hF000, 16'hC000);
            for (i = 0; i < 8; i = i + 1) begin
                pulse_ack(0);
                wait_rounds(1);
            end
            chk(stat_orphan == 0, "U12 live zero-window (periodic acks) must not fire");
            chk(n_cam == 0 && n_wr[0] == 0, "U12 no recovery");
        end
        //------------------------------------------------ U12b 单次丢失
        16: begin
            scen_name = "U12b";
            chk(ORPHAN_ZW_EN_TB == 1, "U12b requires ORPHAN_ZW_EN_TB=1");
            set_slot(0, 4'd1, 16'h0000, 32'hF000, 16'hC000);
            for (i = 0; i < 8; i = i + 1) begin
                if (i != 3) pulse_ack(0);       // 只漏 1 次 (2 x ZW_LIM 窗内)
                wait_rounds(1);
            end
            chk(stat_orphan == 0, "U12b one missed ack (2-tick gap) tolerated");
            chk(n_cam == 0, "U12b no recovery");
        end
        //------------------------------------------------ U10' 零回归
        17: begin
            scen_name = "U10P";
            chk(ORPHAN_EN_TB == 0, "U10P requires ORPHAN_EN_TB=0");
            // 富激励: 事件/进度/窗口/重传/ack 混合 (两者同激励)
            set_slot(0, 4'd1, 16'hF000, 32'h4000, 16'hC000);
            set_slot(1, 4'd1, 16'h8000, 32'h0100, 16'hC000);
            set_slot(2, 4'd1, 16'h0000, 32'h2000, 16'hC000);
            for (i = 0; i < 12; i = i + 1) begin
                pulse_retx(0, 3);
                pulse_ack(2);
                pulse_una_adv(1, 32'd7);
                if (i == 3) pulse_ev_up(3);
                if (i == 6) pulse_ev_down(1);
                if (i == 9) pulse_ev_up(1);
                wait_rounds(1);
            end
            wait_rounds(4);
            chk(n_mismatch == 0, "U10P zero-regression: outputs differ from frozen anchor");
            chk(n_cmp > 1000, "U10P compare coverage");
            $display("U10P compared cycles=%0d mismatches=%0d", n_cmp, n_mismatch);
        end
        //------------------------------------------------ U9B to_push 碰撞 (M9 牙)
        18: begin
            scen_name = "U9B";
            set_slot(0, 4'd1, 16'hF000, 32'hF000, 16'hC000);
            pulse_retx(0, 2);
            wait_fire(30);
            // 等 notify_pend 置位 (投递门开的前一拍), 再在 down_r 高拍注入 to_pend
            // (太早会被 to_push 先消费掉, 落地不到同拍)
            k = 0;
            while (!u_dut.orph_notify_pend && k < 200) begin
                @(negedge clk); k = k + 1;
            end
            @(posedge clk);                     // 下一拍 = orph_down_r 高拍
            u_dut.to_pend[1] = 1'b1;
            #1;                                 // 让组合 to_push 落定
            if (u_dut.orph_down_i && u_dut.to_push) to_push_collision = 1'b1;
            @(negedge clk);
            u_dut.to_pend[1] = 1'b0;
            wait_rounds(2);
            chk(to_push_collision == 0, "U9B orphan delivery must not collide with to_push");
            chk(n_cam == 1, "U9B CAM clear ok");
        end
        default: begin
            scen_name = "BADSCEN";
            errs = errs + 1;
        end
        endcase

        wait_cycles(10);
        if (errs == 0) $display("TB_RESULT PASS %0s (stat=%0d wr0=%0d cam=%0d down=%0d)",
                                scen_name, stat_orphan, n_wr[0], n_cam, n_down);
        else           $display("TB_RESULT FAIL %0s errs=%0d (stat=%0d wr0=%0d cam=%0d down=%0d)",
                                scen_name, errs, stat_orphan, n_wr[0], n_cam, n_down);
        $finish;
    end

    // 全局超时 (防死等)
    initial begin
        #20_000_000;                        // 20 ms sim
        $display("TB_RESULT FAIL TIMEOUT");
        $finish;
    end
endmodule
