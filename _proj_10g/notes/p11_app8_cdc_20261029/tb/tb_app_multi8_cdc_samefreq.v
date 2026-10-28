`timescale 1ns/1ps
//=============================================================================
// tb_app_multi8_cdc: P11 APP8 CDC 单元门（DP 侧 negedge 驱动 / posedge 监视）
//   A. axis_frame_mux8  : 帧级轮询 / 不抢占 / 单源空闲不阻塞（DP 单域，原门搬入）
//   B. axis_tid_demux8  : 按 tid 分发 / 无串扰 / tid>=8 丢弃计数（DP 单域）
//   C. app_close_arb8   : 8 个同拍脉冲全部发出，无丢失（DP 单域）
//   D. app_multi8_cdc   : app_clk 与 dp_clk 异频（相位漂移）；TX/RX/事件/close 全走 CDC；
//                         统计经 hold/toggle 握手到 DP shadow（等待 ≥1 刷新周期再判）。
//   D3. CDC 健康字     : W97 粘滞位/armed 位在正常路径必须为 0/已置位。
// 运行：tb/run_tb_app_multi8_cdc.bat（期望 TB_APP8_CDC_PASS / XSIM_RC=0）
//=============================================================================
module tb_app_multi8_cdc_samefreq;
    // DP 侧 6.4 ns（156.25 MHz）；app 侧 6.23 ns（≈160.5 MHz）⇒ 相位持续漂移，
    // 覆盖同步器/灰码指针的整圈相位关系（真实 MMCM 两路同频不同相只是这里的特例）。
    reg dp_clk = 1'b0;
    reg app_clk = 1'b0;
    reg rst_n = 1'b0;
    always #3.2 dp_clk = ~dp_clk;
    initial begin
        app_clk = 1'b0;
        #1.6;
        forever #3.2 app_clk = ~app_clk;
    end

    // app 域复位：异步置位 / 3 级同步释放（与 app_clk_gen 的契约同形）
    reg [2:0] app_rst_sr = 3'b000;
    always @(posedge app_clk or negedge rst_n)
        if (!rst_n) app_rst_sr <= 3'b000;
        else        app_rst_sr <= {app_rst_sr[1:0], 1'b1};
    reg app_rst_n = 1'b0;
    always @(posedge app_clk) app_rst_n <= app_rst_sr[2];

    // locked_app：复位后第 8 个 app 沿起为 1（W97[5] 应恒 1）
    reg [3:0] lock_cnt = 4'd0;
    always @(posedge app_clk or negedge rst_n)
        if (!rst_n) lock_cnt <= 4'd0;
        else if (lock_cnt != 4'hF) lock_cnt <= lock_cnt + 4'd1;
    reg locked_app = 1'b0;
    always @(posedge app_clk) locked_app <= (lock_cnt == 4'hF);

    localparam W = 77;
    integer errors = 0;

    task fail; input [255:0] msg; begin
        errors = errors + 1;
        $display("  [FAIL] %0s (t=%0t)", msg, $time);
    end endtask
    task okmsg; input [255:0] msg; begin
        $display("  [PASS] %0s", msg);
    end endtask

    function [W-1:0] mkbeat;
        input [3:0] tid; input last; input [63:0] data;
        begin mkbeat = {8'hFF, last, data, tid}; end
    endfunction

    function [63:0] xs;
        input [63:0] s;
        reg [63:0] t;
        begin
            t = s ^ (s << 13);
            t = t ^ (t >> 7);
            t = t ^ (t << 17);
            xs = t;
        end
    endfunction

    // ================= A. mux =================
    reg  [8*W-1:0] A_sdata;
    reg  [7:0]     A_svalid;
    wire [7:0]     A_sready;
    wire [W-1:0]   A_mdata;
    wire           A_mvalid;
    reg            A_mready = 1'b1;
    wire [31:0]    A_frames, A_aborts;
    reg            a_src_en = 1'b1;

    axis_frame_mux8 #(.N(8), .W(W)) u_mux (
        .clk(dp_clk), .rst_n(rst_n),
        .s_data(A_sdata), .s_valid(A_svalid), .s_ready(A_sready),
        .m_data(A_mdata), .m_valid(A_mvalid), .m_ready(A_mready),
        .stat_frames(A_frames), .stat_abort_sel(A_aborts)
    );

    // 源模型：每源循环发 2-beat 帧（beat0 tlast=0 / beat1 tlast=1），negedge 驱动
    reg [7:0] a_beat;
    integer ai;
    always @(negedge dp_clk) begin
        if (!rst_n) begin
            A_svalid <= 8'h00; a_beat <= 8'h00;
            for (ai = 0; ai < 8; ai = ai + 1)
                A_sdata[ai*W +: W] <= mkbeat(ai, 1'b0, 64'hA000 + ai);
        end else if (!a_src_en) begin
            // 手动模式：源模型不驱动，保持外部赋值（A3 用）
        end else if (A_svalid == 8'h00) begin
            // 启动/恢复：8 源全部呈现 beat0
            for (ai = 0; ai < 8; ai = ai + 1) begin
                A_sdata[ai*W +: W] <= mkbeat(ai, 1'b0, 64'hA000 + ai);
                a_beat[ai] <= 1'b0;
            end
            A_svalid <= 8'hFF;
        end else begin
            for (ai = 0; ai < 8; ai = ai + 1) begin
                if (A_sready[ai]) begin
                    if (a_beat[ai] == 1'b0) begin
                        A_sdata[ai*W +: W] <= mkbeat(ai, 1'b1, 64'hA100 + ai);
                        a_beat[ai] <= 1'b1;
                    end else begin
                        A_sdata[ai*W +: W] <= mkbeat(ai, 1'b0, 64'hA200 + ai);
                        a_beat[ai] <= 1'b0;
                    end
                end
            end
        end
    end

    reg [127:0] a_frames_per_tid;   // 8 x 16
    reg [3:0]  a_cur_tid;
    integer    a_beats, a_bad_mid;
    integer    a_frame_cnt;
    // 在 posedge 用 NBA 捕获"该拍被接收的输出"（RHS 取沿前值），negedge 处理 ⇒ 无竞争
    reg        a_cap_v;
    reg [W-1:0] a_cap_d;
    always @(posedge dp_clk) begin
        a_cap_v <= rst_n && A_mvalid && A_mready;
        a_cap_d <= A_mdata;
    end
    always @(negedge dp_clk) begin
        if (a_cap_v) begin
            if (a_beats == 0) begin
                a_cur_tid = a_cap_d[3:0]; a_beats = 1;
            end else begin
                if (a_cap_d[3:0] !== a_cur_tid) begin
                    a_bad_mid = a_bad_mid + 1;
                    $display("  [FAIL] mux mid-frame tid change %0d->%0d", a_cur_tid, a_cap_d[3:0]);
                end
                a_beats = a_beats + 1;
            end
            if (a_cap_d[68]) begin
                a_frames_per_tid[a_cur_tid*16 +: 16] = a_frames_per_tid[a_cur_tid*16 +: 16] + 16'd1;
                a_frame_cnt = a_frame_cnt + 1;
                a_beats = 0;
            end
        end
    end

    // ================= B. demux =================
    reg  [W-1:0]   B_sdata;
    reg            B_svalid;
    wire           B_sready;
    wire [8*W-1:0] B_mdata;
    wire [7:0]     B_mvalid;
    reg  [7:0]     B_mready;
    wire [31:0]    B_orph_f, B_orph_b;

    axis_tid_demux8 #(.N(8), .W(W)) u_demux (
        .clk(dp_clk), .rst_n(rst_n),
        .s_data(B_sdata), .s_valid(B_svalid), .s_ready(B_sready),
        .m_data(B_mdata), .m_valid(B_mvalid), .m_ready(B_mready),
        .stat_orphan_frames(B_orph_f), .stat_orphan_bytes(B_orph_b)
    );

    reg [127:0] b_beats_per_tid;    // 8 x 16
    integer    b_bad_cross, bi;
    reg [7:0]      b_cap_v;
    reg [8*W-1:0]  b_cap_d;
    always @(posedge dp_clk) begin
        b_cap_v <= rst_n ? (B_mvalid & B_mready) : 8'h00;
        b_cap_d <= B_mdata;
    end
    always @(negedge dp_clk) begin
        for (bi = 0; bi < 8; bi = bi + 1) begin
            if (b_cap_v[bi]) begin
                if (b_cap_d[bi*W +: 4] !== bi) begin
                    b_bad_cross = b_bad_cross + 1;
                    $display("  [FAIL] demux cross-talk: out%0d got tid%0d", bi, b_cap_d[bi*W +: 4]);
                end
                b_beats_per_tid[bi*16 +: 16] = b_beats_per_tid[bi*16 +: 16] + 16'd1;
            end
        end
    end

    // B 激励任务：negedge 驱动，posedge 采样 ready
    task b_send_beat;
        input [3:0] tid; input last; input [63:0] data;
        begin
            @(negedge dp_clk);
            B_sdata = mkbeat(tid, last, data); B_svalid = 1'b1;
            @(posedge dp_clk);
            while (!B_sready) begin
                @(negedge dp_clk); @(posedge dp_clk);
            end
        end
    endtask

    task b_send_frame;
        input [3:0] tid; input [63:0] tag;
        begin
            b_send_beat(tid, 1'b0, tag);
            b_send_beat(tid, 1'b1, tag + 64'h100);
            @(negedge dp_clk); B_svalid = 1'b0;
        end
    endtask

    // ================= C. close arb =================
    reg  [7:0] C_req;
    wire       C_out;
    wire [3:0] C_id;
    wire [3:0] C_pendmax;
    reg  [7:0] c_seen;
    integer    c_pulses;

    app_close_arb8 #(.N(8)) u_close (
        .clk(dp_clk), .rst_n(rst_n),
        .i_req(C_req), .o_req(C_out), .o_id(C_id),
        .stat_pend_max(C_pendmax)
    );

    reg c_cap;
    reg [3:0] c_cap_id;
    always @(posedge dp_clk) begin
        c_cap    <= rst_n && C_out;
        c_cap_id <= C_id;
    end
    always @(negedge dp_clk) begin
        if (c_cap) begin
            c_seen[c_cap_id] = c_seen[c_cap_id] + 1;
            c_pulses = c_pulses + 1;
        end
    end

    // ================= D. app_multi8_cdc =================
    reg  [127:0] D_bad = 128'd0;
    wire [63:0]  D_tdata;
    wire [7:0]   D_tkeep;
    wire         D_tvalid, D_tlast;
    wire [3:0]   D_tid;
    reg          D_tready = 1'b1;
    reg  [15:0]  D_tx_ready = 16'h00FF;
    wire         D_crq;
    wire [3:0]   D_cid;

    reg  [63:0]  D_rdata;
    reg  [7:0]   D_rkeep;
    reg          D_rvalid, D_rlast;
    reg  [3:0]   D_rtid;
    wire         D_rready;

    reg          D_ev_up, D_ev_down;
    reg  [3:0]   D_ev_slot;

    // 统计输出 = DP 域 shadow（每 1024 dp_clk 刷新一次）⇒ 判前必须等刷新。
    wire [31:0]  D_tx_bytes, D_tx_frames, D_rx_bytes, D_mismatch;
    wire [31:0]  D_frmwait, D_bp, D_upev, D_swreq, D_swapply, D_uppend;
    wire [3:0]   D_pendmax, D_led;
    wire [31:0]  D_cdc;

    // core 内部同域计数（用于 arb==tx 关系；CDC 顶部不导出）
    wire [31:0]  D_arb_frames    = dut.u_core.stat_arb_frames;
    wire [31:0]  D_core_tx_frames= dut.u_core.stat_tx_frames;
    wire [255:0] D_inst_mismatch = dut.u_core.dbg_inst_mismatch;

    app_multi8_cdc #(
        .TX_BYTES(32'h0FFFFFFF), .TX_SEGSZ(12'd64),
        .TX_CONTINUOUS(1'b1), .TX_SWCLOSE(1'b1)
    ) dut (
        .dp_clk(dp_clk), .dp_rst_n(rst_n), .reset_n(rst_n),
        .app_clk(app_clk), .app_rst_n(app_rst_n), .locked_app(locked_app),
        .ev_up(D_ev_up), .ev_down(D_ev_down), .ev_slot(D_ev_slot),
        .m_tdata(D_tdata), .m_tkeep(D_tkeep), .m_tvalid(D_tvalid),
        .m_tready(D_tready), .m_tlast(D_tlast), .m_tid(D_tid),
        .app_tx_ready(D_tx_ready),
        .close_req(D_crq), .close_id(D_cid),
        .rx_tdata(D_rdata), .rx_tkeep(D_rkeep), .rx_tvalid(D_rvalid),
        .rx_tready(D_rready), .rx_tlast(D_rlast), .rx_tid(D_rtid),
        .rx_stall(1'b0),
        .stat_tx_bytes(D_tx_bytes), .stat_tx_frames(D_tx_frames),
        .stat_rx_bytes(D_rx_bytes), .stat_mismatch(D_mismatch),
        .stat_frmwait_cyc(D_frmwait), .stat_bp_cyc(D_bp),
        .stat_up_ev(D_upev), .stat_sw_req(D_swreq),
        .stat_sw_apply(D_swapply), .stat_up_pend(D_uppend),
        .stat_close_pend_max(D_pendmax),
        .led(D_led),
        .cdc_status(D_cdc)
    );

    // 等一个完整 stats 刷新周期（1024 dp 沿）+ 同步余量
    task wait_stats;
        begin
            repeat (1200) @(posedge dp_clk);
        end
    endtask

    reg [127:0] d_frames_per_tid;   // 8 x 16
    reg [3:0]  d_cur_tid;
    integer    d_beats, d_bad_mid;
    reg        d_cap_v;
    reg [4:0]  d_cap;   // {tlast, tid}
    always @(posedge dp_clk) begin
        d_cap_v <= rst_n && D_tvalid && D_tready;
        d_cap   <= {D_tlast, D_tid};
    end
    always @(negedge dp_clk) begin
        if (d_cap_v) begin
            if (d_beats == 0) begin
                d_cur_tid = d_cap[3:0]; d_beats = 1;
            end else begin
                if (d_cap[3:0] !== d_cur_tid) begin
                    d_bad_mid = d_bad_mid + 1;
                    $display("  [FAIL] DUT mid-frame tid change %0d->%0d", d_cur_tid, d_cap[3:0]);
                end
                d_beats = d_beats + 1;
            end
            if (d_cap[4]) begin
                d_frames_per_tid[d_cur_tid*16 +: 16] = d_frames_per_tid[d_cur_tid*16 +: 16] + 16'd1;
                d_beats = 0;
            end
        end
    end

    reg [63:0] rx_st [0:7];

    task rx_reset_all;
        integer qq;
        begin
            for (qq = 0; qq < 8; qq = qq + 1) rx_st[qq] = 64'h9E3779B97F4A7C15;
        end
    endtask

    task rx_word;
        input [3:0] tid; input [63:0] word; input last;
        begin
            @(negedge dp_clk);
            D_rdata = word; D_rkeep = 8'hFF; D_rlast = last;
            D_rtid = tid; D_rvalid = 1'b1;
            @(posedge dp_clk);
            while (!D_rready) begin
                @(negedge dp_clk); @(posedge dp_clk);
            end
        end
    endtask

    task rx_send_frame;
        input [3:0] tid;
        input       inject_err;
        input [1:0] err_word;
        input [2:0] err_byte;
        integer ww, bb;
        reg [63:0] st, word;
        reg [7:0]  by;
        begin
            for (ww = 0; ww < 4; ww = ww + 1) begin
                st = rx_st[tid]; word = 64'd0;
                for (bb = 0; bb < 8; bb = bb + 1) begin
                    by = st[31:24];
                    if (inject_err && (ww == err_word) && (bb == err_byte)) by = by ^ 8'h5A;
                    word = {word[55:0], by};
                    st = xs(st);
                end
                rx_st[tid] = st;
                rx_word(tid, word, (ww == 3));
            end
            @(negedge dp_clk); D_rvalid = 1'b0; D_rlast = 1'b0;
        end
    endtask

    // ================= 主流程 =================
    integer t, n, kk, seen_tid, a3_before;
    initial begin
        a_frames_per_tid = 0; a_cur_tid = 0; a_beats = 0; a_bad_mid = 0; a_frame_cnt = 0;
        b_beats_per_tid = 0; b_bad_cross = 0;
        c_seen = 0; c_pulses = 0;
        d_frames_per_tid = 0; d_cur_tid = 0; d_beats = 0; d_bad_mid = 0;
        C_req = 0; D_ev_up = 0; D_ev_down = 0; D_ev_slot = 0;
        B_svalid = 0; B_sdata = 0; B_mready = 8'hFF;
        D_rvalid = 0; D_rlast = 0; D_rtid = 0; D_rdata = 0; D_rkeep = 0;
        rx_reset_all();
        repeat (10) @(posedge dp_clk);
        rst_n = 1'b1;
        repeat (10) @(posedge dp_clk);

        // ---- A ----
        $display("=== A. axis_frame_mux8 ===");
        repeat (600) @(posedge dp_clk);
        if (a_bad_mid != 0) fail("A: mid-frame tid change");
        else okmsg("A: no mid-frame tid change");
        seen_tid = 0;
        for (kk = 0; kk < 8; kk = kk + 1) if (a_frames_per_tid[kk*16 +: 16] > 0) seen_tid = seen_tid + 1;
        if (a_frame_cnt < 16 || seen_tid != 8) begin
            $display("  [FAIL] A: frames=%0d tids=%0d", a_frame_cnt, seen_tid);
            errors = errors + 1;
        end else okmsg("A: round-robin serves all 8 sources");
        $display("  A frames per tid: %0d %0d %0d %0d %0d %0d %0d %0d",
                 a_frames_per_tid[0*16 +: 16],a_frames_per_tid[1*16 +: 16],
                 a_frames_per_tid[2*16 +: 16],a_frames_per_tid[3*16 +: 16],
                 a_frames_per_tid[4*16 +: 16],a_frames_per_tid[5*16 +: 16],
                 a_frames_per_tid[6*16 +: 16],a_frames_per_tid[7*16 +: 16]);

        // A2: 只保留一个源有 valid ⇒ 其余不应阻塞
        @(negedge dp_clk); A_svalid = 8'h00;
        repeat (4) @(posedge dp_clk);
        @(negedge dp_clk); A_svalid = 8'h08;
        repeat (40) @(posedge dp_clk);
        @(negedge dp_clk); A_svalid = 8'h00;
        repeat (4) @(posedge dp_clk);
        okmsg("A2: single-source case no hang");

        // ---- A3: 首拍被接收前源撤 valid ⇒ mux 必须释放并服务其它源 (review H1) ----
        $display("=== A3. withdraw-before-first-accept ===");
        @(negedge dp_clk); a_src_en = 1'b0; A_svalid = 8'h00; A_mready = 1'b0;
        repeat (2) @(posedge dp_clk);
        @(negedge dp_clk);
        A_sdata[0*W +: W] = mkbeat(0, 1'b0, 64'hF000);
        A_svalid = 8'h01;
        repeat (4) @(posedge dp_clk);            // mux 选中 src0，但 mready=0 ⇒ 未接收
        @(negedge dp_clk); A_svalid = 8'h00;     // 首拍接收前撤下
        repeat (3) @(posedge dp_clk);
        if (A_aborts == 0) fail("A3: abort not counted");
        else okmsg("A3: withdraw-before-accept counted");
        if (A_mvalid) fail("A3: mux still driving after abort");
        else okmsg("A3: mux released after abort");
        a3_before = a_frames_per_tid[1*16 +: 16];
        @(negedge dp_clk); A_mready = 1'b1;
        A_sdata[1*W +: W] = mkbeat(1, 1'b1, 64'hF100); A_svalid = 8'h02;
        repeat (6) @(posedge dp_clk);
        @(negedge dp_clk);   // 让 negedge 监视器处理最后一拍捕获
        if (a_frames_per_tid[1*16 +: 16] == a3_before) fail("A3: other source not served");
        else okmsg("A3: other source served after abort");
        @(negedge dp_clk); A_svalid = 8'h00;
        repeat (2) @(posedge dp_clk);
        a_src_en = 1'b1;

        // reset before B (清 mux 残留 busy)
        @(negedge dp_clk); rst_n = 1'b0;
        repeat (6) @(posedge dp_clk);
        @(negedge dp_clk); rst_n = 1'b1; B_mready = 8'hFF;
        repeat (4) @(posedge dp_clk);

        // ---- B ----
        $display("=== B. axis_tid_demux8 ===");
        for (t = 0; t < 8; t = t + 1) begin
            for (n = 0; n < 2; n = n + 1) b_send_frame(t, 64'hC000 + t*16 + n);
        end
        repeat (6) @(posedge dp_clk);
        for (kk = 0; kk < 8; kk = kk + 1) begin
            if (b_beats_per_tid[kk*16 +: 16] != 4) begin
                $display("  [FAIL] B: out%0d beats=%0d (want 4)", kk, b_beats_per_tid[kk*16 +: 16]);
                errors = errors + 1;
            end
        end
        if (b_bad_cross != 0) fail("B: cross-talk");
        else okmsg("B: 8 tids isolated (4 beats each)");

        // B2: tid=9 帧被丢弃并计数
        b_send_beat(4'd9, 1'b0, 64'hD000);
        b_send_beat(4'd9, 1'b1, 64'hD100);
        @(negedge dp_clk); B_svalid = 1'b0;
        repeat (4) @(posedge dp_clk);
        if (B_orph_f != 1 || B_orph_b != 16) begin
            $display("  [FAIL] B: orphan f=%0d b=%0d (want 1/16)", B_orph_f, B_orph_b);
            errors = errors + 1;
        end else okmsg("B: tid>=8 frame dropped and counted");
        // 后续合法帧仍通
        b_send_frame(4'd0, 64'hE000);
        repeat (4) @(posedge dp_clk);
        if (b_beats_per_tid[0*16 +: 16] != 6) begin
            $display("  [FAIL] B: after orphan out0 beats=%0d (want 6)", b_beats_per_tid[0*16 +: 16]);
            errors = errors + 1;
        end else okmsg("B: legal frames continue after orphan");

        // ---- C ----
        $display("=== C. app_close_arb8 ===");
        @(negedge dp_clk); C_req = 8'hFF;
        @(negedge dp_clk); C_req = 8'h00;
        repeat (16) @(posedge dp_clk);
        if (c_pulses != 8) begin
            $display("  [FAIL] C: pulses=%0d (want 8)", c_pulses); errors = errors + 1;
        end else okmsg("C: 8 simultaneous requests all issued");
        for (kk = 0; kk < 8; kk = kk + 1) begin
            if (c_seen[kk] != 1) begin
                $display("  [FAIL] C: id%0d seen=%0d", kk, c_seen[kk]); errors = errors + 1;
            end
        end
        okmsg("C: each id issued once");

        // reset before D
        @(negedge dp_clk); rst_n = 1'b0;
        repeat (6) @(posedge dp_clk);
        @(negedge dp_clk); rst_n = 1'b1;
        repeat (4) @(posedge dp_clk);

        // ---- D ----
        $display("=== D. app_multi8 integration ===");
        for (kk = 0; kk < 8; kk = kk + 1) begin
            @(negedge dp_clk); D_ev_slot = kk; D_ev_up = 1'b1;
            @(negedge dp_clk); D_ev_up = 1'b0;
            repeat (2) @(posedge dp_clk);
        end
        repeat (5000) @(posedge dp_clk);
        wait_stats;   // stats shadow 刷新（1024 dp 沿）+ 余量
        if (d_bad_mid != 0) fail("D: mid-frame tid change");
        else okmsg("D: TX frames never change tid mid-frame");
        seen_tid = 0;
        for (kk = 0; kk < 8; kk = kk + 1) if (d_frames_per_tid[kk*16 +: 16] > 0) seen_tid = seen_tid + 1;
        if (seen_tid != 8) begin
            $display("  [FAIL] D: only %0d tids got TX frames", seen_tid); errors = errors + 1;
        end else okmsg("D: all 8 connections transmit");
        // arb==tx 用 core 同域计数（shadow 有 ≤1 刷新周期的滞后，不可作相等判据）
        if ((D_arb_frames < D_core_tx_frames) || (D_arb_frames > D_core_tx_frames + 8)) begin
            $display("  [FAIL] D: tx_frames=%0d arb_frames=%0d", D_core_tx_frames, D_arb_frames);
            errors = errors + 1;
        end else okmsg("D: agg tx_frames == arb_frames (in-flight <=8)");
        // stats 握手：shadow 必须已在动，且滞后有界（连续发送下 lag 远小于 1 个刷新窗）
        if ((D_tx_frames == 0) || (D_tx_frames > D_core_tx_frames) ||
            ((D_core_tx_frames - D_tx_frames) > 32'd250)) begin
            $display("  [FAIL] D: stats shadow tx_frames=%0d core=%0d", D_tx_frames, D_core_tx_frames);
            errors = errors + 1;
        end else okmsg("D: stats handshake live (bounded lag)");

        // ---- D3: CDC 健康字（W97 语义的单元版）----
        $display("=== D3. cdc_status ===");
        if (D_cdc[5] !== 1'b1) begin
            $display("  [FAIL] D3: locked_app sync bit=%0b", D_cdc[5]); errors = errors + 1;
        end else okmsg("D3: locked_app visible in DP domain");
        if (D_cdc[2] | D_cdc[3] | D_cdc[4] | D_cdc[6] | D_cdc[7] | D_cdc[20]) begin
            $display("  [FAIL] D3: cdc_status=%08x (drop/stale/seen bits)", D_cdc);
            errors = errors + 1;
        end else okmsg("D3: no drop / no stats stale / no unexpected reset seen");

        // RX clean
        rx_reset_all();
        for (t = 0; t < 8; t = t + 1) rx_send_frame(t, 1'b0, 2'd0, 3'd0);
        wait_stats;
        if (D_mismatch != 0) begin
            $display("  [FAIL] D: mismatch=%0d after clean RX", D_mismatch);
            errors = errors + 1;
        end else okmsg("D: 8-connection RX pattern clean");

        // RX 注入 1 错字节到 tid2
        rx_send_frame(4'd2, 1'b1, 2'd1, 3'd3);
        wait_stats;
        if (D_mismatch != 1) begin
            $display("  [FAIL] D: mismatch=%0d (want 1)", D_mismatch);
            errors = errors + 1;
        end else okmsg("D: injected error counted once");
        if (D_inst_mismatch[2*32 +: 32] != 1) begin
            $display("  [FAIL] D: inst2 mismatch=%0d", D_inst_mismatch[2*32 +: 32]);
            errors = errors + 1;
        end
        for (kk = 0; kk < 8; kk = kk + 1) begin
            if (kk != 2 && D_inst_mismatch[kk*32 +: 32] != 0) begin
                $display("  [FAIL] D: cross-talk into inst%0d mismatch=%0d",
                         kk, D_inst_mismatch[kk*32 +: 32]);
                errors = errors + 1;
            end
        end
        okmsg("D: error isolated to its connection");
        if (D_cdc[8 + 2] !== 1'b1) begin
            $display("  [FAIL] D3: mismatch sticky bit2=%0b cdc=%08x", D_cdc[10], D_cdc);
            errors = errors + 1;
        end else okmsg("D3: per-conn mismatch sticky propagated to DP");

        // ---- D2: 反压 + ev_down（关闭帧在背压下收尾，其它连接恢复）----
        $display("=== D2. backpressure + ev_down ===");
        begin : d2_blk
            reg [127:0] snap;
            integer seen2;
            snap = d_frames_per_tid;
            @(negedge dp_clk); D_tready = 1'b0;          // 下游长反压
            repeat (300) @(posedge dp_clk);
            @(negedge dp_clk); D_ev_slot = 4'd0; D_ev_down = 1'b1;
            @(negedge dp_clk); D_ev_down = 1'b0;
            repeat (300) @(posedge dp_clk);
            @(negedge dp_clk); D_tready = 1'b1;          // 释放
            repeat (2000) @(posedge dp_clk);
            seen2 = 0;
            for (kk = 0; kk < 8; kk = kk + 1)
                if (d_frames_per_tid[kk*16 +: 16] > snap[kk*16 +: 16]) seen2 = seen2 + 1;
            if (seen2 < 6) begin
                $display("  [FAIL] D2: only %0d tids resumed after backpressure+ev_down", seen2);
                errors = errors + 1;
            end else okmsg("D2: >=6 connections resume after backpressure+ev_down");
            okmsg("D2: no deadlock (simulation progressed)");
        end

        repeat (20) @(posedge dp_clk);
        if (errors == 0) begin
            $display("TB_APP8_CDC_PASS");
        end else begin
            $display("TB_APP8_CDC_FAIL errors=%0d", errors);
            $fatal(1, "TB_APP8_CDC_FAIL");
        end
        $finish;
    end

    initial begin
        #5_000_000;
        $display("TB_APP8_CDC_FAIL timeout errors=%0d", errors);
        $fatal(1, "TB_APP8_CDC_TIMEOUT");
    end
endmodule
