`timescale 1ns/1ps
//=============================================================================
// tb_echo_occ — P11 APP8 v6 tcp_echo 每连接占用单元门 (REVIEW_V5 O1/O2/O3/O4/O9)
//=============================================================================
// 判据:
//   · 逐拍 sum(occ[i]) == (fifo_wptr - fifo_rptr) << 3        (结构恒等式)
//   · 逐拍 occ[i] == TB 参考模型 (按 TB 已知帧/读/回卷事件)
//   · stat_occ_underflow == 0, stat_cq_ovf == 0, fq <= 126
//   · T1: 2 tid 交错 + 同拍读写净额 0 + 读口 (id,值) 对齐
//   · T2: 单字/多字坏帧回卷精确; 末字计入; cid 正确
//   · T2b: 坏帧回卷拍不得接受新写 (!rback 门; 变异 O9-⑥ 的有牙项)
//   · T3: 128x1B 好帧 + app 停读 -> 帧首门; 放行后全收; 门关闭周期 > 0
// 驱动约定: negedge 先采样 s_tready, 再置 valid; 下一 posedge 握手 (无重复拍).
//=============================================================================
module tb_echo_occ;
    localparam integer D  = 16384;
    localparam integer AW = 14;
    localparam integer PTRM = (1 << (AW+1)) - 1;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg  [63:0] s_tdata;
    reg  [7:0]  s_tkeep;
    reg         s_tvalid;
    wire        s_tready;
    reg         s_tlast;
    reg  [1:0]  s_tuser;
    reg         fend, ferr, meta_valid;
    reg  [3:0]  meta_conn_id;
    reg  [15:0] meta_len;
    wire [63:0] m_tdata;
    wire [7:0]  m_tkeep;
    wire        m_tvalid;
    reg         m_tready;
    wire        m_tlast;
    wire [3:0]  m_tid;
    wire [31:0] stat_echo, stat_drop_crc, stat_tlast_wr, stat_tlast_fwd;
    wire        dbg_fifo_full;
    wire [2:0]  dbg_state;
    wire        dbg_fifo_empty;
    wire [AW:0] dbg_wptr, dbg_rptr;
    wire [AW-1:0] dbg_rd_addr = {AW{1'b0}};
    wire [8:0]  dbg_rd_side;
    reg  [3:0]  i_occ_rd_id;
    wire [16:0] o_occ_rd;
    wire [3:0]  o_occ_rd_id;
    wire [31:0] stat_occ_underflow, stat_cq_ovf;

    tcp_echo #(.D(D), .AW(AW), .PER_CONN_OCC(1'b1)) u_dut (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tdata(s_tdata), .s_axis_tkeep(s_tkeep),
        .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready),
        .s_axis_tlast(s_tlast), .s_axis_tuser(s_tuser),
        .fend(fend), .ferr(ferr),
        .meta_valid(meta_valid), .meta_conn_id(meta_conn_id), .meta_len(meta_len),
        .m_axis_tdata(m_tdata), .m_axis_tkeep(m_tkeep),
        .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready),
        .m_axis_tlast(m_tlast), .m_axis_tid(m_tid),
        .stat_echo(stat_echo), .stat_drop_crc(stat_drop_crc),
        .stat_tlast_wr(stat_tlast_wr), .stat_tlast_fwd(stat_tlast_fwd),
        .dbg_fifo_full(dbg_fifo_full), .dbg_state(dbg_state),
        .dbg_fifo_empty(dbg_fifo_empty),
        .dbg_fifo_wptr(dbg_wptr), .dbg_fifo_rptr(dbg_rptr),
        .dbg_rd_addr(dbg_rd_addr), .dbg_rd_side(dbg_rd_side),
        .i_occ_rd_id(i_occ_rd_id),
        .o_occ_rd(o_occ_rd), .o_occ_rd_id(o_occ_rd_id),
        .stat_occ_underflow(stat_occ_underflow),
        .stat_cq_ovf(stat_cq_ovf)
    );

    //-------------------------------------------------------------------------
    // TB 参考模型 / 计分
    //-------------------------------------------------------------------------
    reg [19:0] exp_occ [0:15];
    integer errors, checks;
    integer k, j;
    reg [3:0] cur_cid;
    reg [3:0] bad_cid;
    integer   bad_words;
    integer   gate_cycles;
    integer   rd_beats, rd_bytes, rd_frames;
    reg [3:0] good_cids [0:255];
    integer   good_n;

    wire dut_accept = s_tvalid && s_tready;
    wire dut_fwd    = m_tvalid && m_tready;

    function [23:0] sum_occ;
        input integer dummy;
        integer ii;
        begin
            sum_occ = 24'd0;
            for (ii = 0; ii < 16; ii = ii + 1)
                sum_occ = sum_occ + u_dut.g_occ.occ[ii];
        end
    endfunction

    function integer popcount8;
        input [7:0] v;
        integer b;
        begin
            popcount8 = 0;
            for (b = 0; b < 8; b = b + 1) popcount8 = popcount8 + v[b];
        end
    endfunction

    integer kk;
    reg signed [19:0] dd;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (kk = 0; kk < 16; kk = kk + 1) exp_occ[kk] <= 20'd0;
        end else begin
            for (kk = 0; kk < 16; kk = kk + 1) begin
                dd = 20'sd0;
                if (dut_accept && (cur_cid == kk[3:0])) dd = dd + 20'sd8;
                if (dut_fwd    && (m_tid   == kk[3:0])) dd = dd - 20'sd8;
                if (u_dut.rback && (bad_cid == kk[3:0]))
                    dd = dd - (20'sd8 * bad_words);
                exp_occ[kk] <= exp_occ[kk] + dd;
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n && dut_fwd) begin
            rd_beats = rd_beats + 1;
            rd_bytes = rd_bytes + popcount8(m_tkeep);
            if (m_tlast) begin
                rd_frames = rd_frames + 1;
                if (rd_frames > good_n) begin
                    errors = errors + 1;
                    $display("FAIL_READ_ORDER extra frame=%0d tid=%0d", rd_frames, m_tid);
                end else if (m_tid !== good_cids[rd_frames-1]) begin
                    errors = errors + 1;
                    $display("FAIL_READ_CID frame=%0d got=%0d exp=%0d",
                             rd_frames, m_tid, good_cids[rd_frames-1]);
                end
            end
        end
    end

    // 负沿: DUT 寄存器已稳定
    always @(negedge clk) begin
        if (rst_n) begin
            for (k = 0; k < 16; k = k + 1) begin
                checks = checks + 1;
                if (u_dut.g_occ.occ[k] !== exp_occ[k][17:0]) begin
                    errors = errors + 1;
                    if (errors < 25)
                        $display("FAIL_OCC t=%0t cid=%0d dut=%0d exp=%0d",
                                 $time, k, u_dut.g_occ.occ[k], exp_occ[k]);
                end
            end
            checks = checks + 1;
            if (sum_occ(0) !== ((((dbg_wptr - dbg_rptr) & PTRM) << 3))) begin
                errors = errors + 1;
                if (errors < 25)
                    $display("FAIL_SUM t=%0t sum=%0d fifo=%0d (w=%0d r=%0d)",
                             $time, sum_occ(0), (((dbg_wptr - dbg_rptr) & PTRM) << 3),
                             dbg_wptr, dbg_rptr);
            end
            checks = checks + 1;
            if (stat_occ_underflow !== 32'd0) begin
                errors = errors + 1;
                $display("FAIL_UNDERFLOW t=%0t n=%0d", $time, stat_occ_underflow);
            end
            checks = checks + 1;
            if (stat_cq_ovf !== 32'd0) begin
                errors = errors + 1;
                $display("FAIL_CQ_OVF t=%0t n=%0d", $time, stat_cq_ovf);
            end
            checks = checks + 1;
            if (u_dut.fq > 126) begin
                errors = errors + 1;
                $display("FAIL_FQ t=%0t fq=%0d", $time, u_dut.fq);
            end
            if (u_dut.first_b && (u_dut.fq == 126) && !s_tready)
                gate_cycles = gate_cycles + 1;
        end
    end

    //-------------------------------------------------------------------------
    // 任务
    //-------------------------------------------------------------------------
    task fail;
        input [255:0] msg;
        begin
            errors = errors + 1;
            $display("FAIL_TASK t=%0t %0s", $time, msg);
        end
    endtask

    task check_eq;
        input [31:0] got;
        input [31:0] exp;
        input [255:0] msg;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("FAIL_CHK t=%0t %0s got=%0d exp=%0d", $time, msg, got, exp);
            end
        end
    endtask

    task do_reset;
        begin
            rst_n = 1'b0;
            s_tvalid = 1'b0; s_tlast = 1'b0; s_tuser = 2'b00;
            s_tdata = 64'd0; s_tkeep = 8'd0;
            fend = 1'b0; ferr = 1'b0; meta_valid = 1'b0;
            meta_conn_id = 4'd0; meta_len = 16'd0;
            m_tready = 1'b0;
            i_occ_rd_id = 4'd0;
            errors = 0; checks = 0; gate_cycles = 0;
            rd_beats = 0; rd_bytes = 0; rd_frames = 0; good_n = 0;
            bad_cid = 4'd0; bad_words = 0;
            repeat (6) @(posedge clk);
            rst_n = 1'b1;
            @(negedge clk);
            repeat (2) @(posedge clk);
        end
    endtask

    // 单拍: 在 negedge 先等 ready, 再置 valid; 下一 posedge 握手
    task beat;
        input [63:0] data;
        input [7:0]  keep;
        input        last;
        begin
            @(negedge clk);
            while (!s_tready) @(negedge clk);
            s_tvalid = 1'b1; s_tdata = data; s_tkeep = keep;
            s_tlast = last; s_tuser = 2'b01;
            @(posedge clk);                 // 握手 (DUT 在本沿采样 valid)
            @(negedge clk);                 // 沿后再撤 valid (避免 0 延迟竞争)
            s_tvalid = 1'b0; s_tlast = 1'b0;
        end
    endtask

    // meta 一拍 -> fend/ferr 一拍 -> nwords 拍载荷
    task send_frame;
        input [3:0] cid;
        input integer nwords;
        input bad;
        integer b;
        reg [63:0] wd;
        reg [7:0]  kp;
        begin
            cur_cid = cid;
            if (bad) begin bad_cid = cid; bad_words = nwords; end
            @(negedge clk); meta_valid = 1'b1; meta_conn_id = cid; meta_len = nwords*8;
            @(negedge clk); meta_valid = 1'b0; fend = 1'b1; ferr = bad;
            @(negedge clk); fend = 1'b0; ferr = 1'b0;
            for (b = 0; b < nwords; b = b + 1) begin
                wd = {cid, 4'h0, b[7:0], 24'hA5A5A5, 24'h5A5A5A};
                kp = (b == nwords-1) ? ((nwords == 1) ? 8'h01 : 8'hFF) : 8'hFF;
                beat(wd, kp, (b == nwords-1));
            end
            if (!bad) begin
                good_cids[good_n] = cid; good_n = good_n + 1;
            end
            @(negedge clk);
        end
    endtask

    // 坏帧: 末拍 posedge 后立即返回 (供 T2b 在 rback 拍预置下一帧首拍)
    task send_frame_nogap;
        input [3:0] cid;
        input integer nwords;
        integer b;
        reg [63:0] wd;
        reg [7:0]  kp;
        begin
            cur_cid = cid;
            bad_cid = cid; bad_words = nwords;
            @(negedge clk); meta_valid = 1'b1; meta_conn_id = cid; meta_len = nwords*8;
            @(negedge clk); meta_valid = 1'b0; fend = 1'b1; ferr = 1'b1;
            @(negedge clk); fend = 1'b0; ferr = 1'b0;
            for (b = 0; b < nwords; b = b + 1) begin
                wd = {cid, 4'h0, b[7:0], 24'hA5A5A5, 24'h5A5A5A};
                kp = (b == nwords-1) ? ((nwords == 1) ? 8'h01 : 8'hFF) : 8'hFF;
                beat(wd, kp, (b == nwords-1));
            end
        end
    endtask

    task chk_rd;
        input [3:0] cid;
        input [16:0] exp;
        begin
            @(negedge clk);
            i_occ_rd_id = cid;
            @(posedge clk);
            @(posedge clk);
            @(negedge clk);
            check_eq(o_occ_rd, exp, "o_occ_rd");
            check_eq(o_occ_rd_id, cid, "o_occ_rd_id");
        end
    endtask

    //-------------------------------------------------------------------------
    // 主序列
    //-------------------------------------------------------------------------
    integer f;
    integer rd_target;
    initial begin
        do_reset();

        //================ T1: 2 tid 交错 + 读口 ================
        $display("P_T1_SEND_START t=%0t", $time);
        send_frame(4'd2, 4, 1'b0);
        send_frame(4'd5, 1, 1'b0);
        send_frame(4'd2, 1, 1'b0);
        $display("P_T1_SENT t=%0t fq=%0d occ2=%0d occ5=%0d", $time, u_dut.fq,
                 u_dut.g_occ.occ[2], u_dut.g_occ.occ[5]);
        repeat (3) @(posedge clk);
        check_eq(u_dut.g_occ.occ[2], 17'd40, "T1 occ2=5words");
        check_eq(u_dut.g_occ.occ[5], 17'd8,  "T1 occ5=1word");
        check_eq(dbg_wptr - dbg_rptr, 15'd6,  "T1 fifo=6words");
        chk_rd(4'd2, 17'd40);
        chk_rd(4'd5, 17'd8);
        i_occ_rd_id = 4'd0;
        // 放行: 4+1+1 beats, 3 frames, bytes 32+1+8=41
        @(negedge clk); m_tready = 1'b1;
        while (rd_beats < 6) @(negedge clk);
        $display("P_T1_READ t=%0t beats=%0d frames=%0d bytes=%0d", $time, rd_beats, rd_frames, rd_bytes);
        repeat (3) @(posedge clk);
        @(negedge clk); m_tready = 1'b0;
        check_eq(rd_beats, 6, "T1 read beats");
        check_eq(rd_bytes, 34, "T1 read bytes");   // 32 + 1 + 1 (C 为 1B 短段)
        check_eq(rd_frames, 3, "T1 read frames");
        check_eq(u_dut.g_occ.occ[2], 17'd0, "T1 occ2 drained");
        check_eq(u_dut.g_occ.occ[5], 17'd0, "T1 occ5 drained");

        //================ T2: 坏帧回卷 (多字 + 单字) ================
        $display("P_T2_SEND_START t=%0t", $time);
        send_frame(4'd7, 3, 1'b1);
        send_frame(4'd7, 1, 1'b0);
        $display("P_T2_SENT t=%0t occ7=%0d fq=%0d drop=%0d", $time,
                 u_dut.g_occ.occ[7], u_dut.fq, stat_drop_crc);
        repeat (3) @(posedge clk);
        check_eq(u_dut.g_occ.occ[7], 17'd8, "T2 occ7 after rollback");
        check_eq(stat_drop_crc, 32'd1, "T2 drop_crc=1");
        chk_rd(4'd7, 17'd8);
        @(negedge clk); m_tready = 1'b1;
        while (rd_frames < 4) @(negedge clk);   // T1 3 + T2 1
        $display("P_T2_READ t=%0t frames=%0d occ7=%0d", $time, rd_frames, u_dut.g_occ.occ[7]);
        repeat (3) @(posedge clk);
        @(negedge clk); m_tready = 1'b0;
        check_eq(u_dut.g_occ.occ[7], 17'd0, "T2 occ7 drained");
        send_frame(4'd4, 1, 1'b1);
        repeat (3) @(posedge clk);
        check_eq(u_dut.g_occ.occ[4], 17'd0, "T2 single-word rollback");
        check_eq(stat_drop_crc, 32'd2, "T2 drop_crc=2");

        //================ T2b: 回卷拍不得接受新写 (!rback) ================
        send_frame_nogap(4'd6, 2);
        // 任务在坏帧末拍 posedge 后返回; 下一拍 = rback.
        // 立即预置下一帧 cid9 的 meta + 首拍 (valid 覆盖 rback 拍)
        cur_cid = 4'd9;
        meta_valid = 1'b1; meta_conn_id = 4'd9; meta_len = 16'd16;
        s_tvalid = 1'b1; s_tdata = 64'h9999_0000_0000_0001;
        s_tkeep = 8'hFF; s_tlast = 1'b0; s_tuser = 2'b01;
        // 当前时刻 = 坏帧末拍 posedge 后的 negedge; 本拍即 rback 的 ready 采样拍
        while (!s_tready) @(negedge clk);   // 正常: rback 拍低; 变异: 高->立即
        @(posedge clk);                     // 首拍握手
        @(negedge clk);                     // 沿后撤 valid (无竞争)
        s_tvalid = 1'b0; s_tlast = 1'b0;
        meta_valid = 1'b0; fend = 1'b1;
        @(posedge clk);                     // fend 采样 (pend)
        @(negedge clk); fend = 1'b0;
        // 第二拍 (末拍)
        while (!s_tready) @(negedge clk);
        s_tvalid = 1'b1; s_tdata = 64'h9999_0000_0000_0002;
        s_tkeep = 8'h01; s_tlast = 1'b1; s_tuser = 2'b01;
        @(posedge clk);
        @(negedge clk); s_tvalid = 1'b0; s_tlast = 1'b0;
        good_cids[good_n] = 4'd9; good_n = good_n + 1;
        repeat (3) @(posedge clk);
        check_eq(u_dut.g_occ.occ[9], 17'd16, "T2b occ9=2words");
        $display("P_T2B_DONE t=%0t occ9=%0d occ6=%0d fq=%0d", $time,
                 u_dut.g_occ.occ[9], u_dut.g_occ.occ[6], u_dut.fq);
        // 读掉 T2b 的好帧 (fq 归 0; T3 才能从 0 起测 126 门)
        @(negedge clk); m_tready = 1'b1;
        while (rd_frames < 5) @(negedge clk);
        repeat (2) @(posedge clk);
        @(negedge clk); m_tready = 1'b0;
        check_eq(u_dut.g_occ.occ[9], 17'd0, "T2b occ9 drained");

        //================ T3: 128x1B + app 停读 -> 帧首门 ================
        @(negedge clk); m_tready = 1'b0;
        for (f = 0; f < 126; f = f + 1) send_frame(4'd1, 1, 1'b0);
        $display("P_T3_126 t=%0t fq=%0d occ1=%0d good_n=%0d", $time, u_dut.fq,
                 u_dut.g_occ.occ[1], good_n);
        repeat (3) @(posedge clk);
        check_eq(u_dut.fq, 126, "T3 fq=126");
        fork
            begin
                send_frame(4'd1, 1, 1'b0);
            end
            begin
                repeat (8) @(posedge clk);
                if (s_tready !== 1'b0) fail("T3 gate did not block first beat");
                @(negedge clk); m_tready = 1'b1;
            end
        join
        $display("P_T3_FORK_DONE t=%0t fq=%0d gate_cycles=%0d", $time, u_dut.fq, gate_cycles);
        send_frame(4'd1, 1, 1'b0);
        $display("P_T3_128 t=%0t fq=%0d good_n=%0d", $time, u_dut.fq, good_n);
        rd_target = 133;
        while (rd_frames < rd_target) begin
            @(negedge clk);
            if ((rd_frames % 16) == 0)
                $display("P_T3_RD t=%0t frames=%0d beats=%0d", $time, rd_frames, rd_beats);
        end
        repeat (10) @(posedge clk);
        check_eq(u_dut.fq, 0, "T3 fq drained");
        check_eq(stat_cq_ovf, 32'd0, "T3 cq_ovf=0");
        if (gate_cycles == 0) fail("T3 gate_cycles==0 (no gate close observed)");
        check_eq(rd_frames, 133, "T3 read frames");
        check_eq(u_dut.g_occ.occ[1], 17'd0, "T3 occ1 drained");

        //================ 汇总 ================
        repeat (5) @(posedge clk);
        if (errors == 0) begin
            $display("TB_ECHO_OCC_PASS checks=%0d frames=%0d beats=%0d gate_cycles=%0d drop_crc=%0d",
                     checks, rd_frames, rd_beats, gate_cycles, stat_drop_crc);
        end else begin
            $display("TB_ECHO_OCC_FAIL errors=%0d checks=%0d", errors, checks);
        end
        $finish;
    end

    initial begin
        #2000000;
        $display("TB_ECHO_OCC_FAIL timeout");
        $finish;
    end

endmodule
