`timescale 1ns/1ps
//=============================================================================
// tb_rx_merge2.v — P11 P2-甲 G2: rx_merge2 单元门 (xsim, 自检)
//=============================================================================
// 臂:
//   A. 单口工作保持 (p0 三帧全出, p1 零帧)
//   B. 双口逐帧 RR 交替 (STRICT=0: rr 复位 0 ⇒ 首个服务 p1, 之后交替)
//   C. 随机反压下的帧原子性 (帧内 beat 连续、绝不交织) + 完整计数
//   D. 复位 (帧中途 rst, 输出静默)
//   E. STRICT=1 负控 (N-13): 高优先口 p1 **持有效帧且 tready=0 ≥16 拍**,
//      低优先口 p0 持续注入 ≥2 个最大帧 (190 beats) 到 DEPTH=4 的模型 FIFO
//      ⇒ 断言 p0_tready 持续 0 且 p0 溢出增长 (负控有牙)
//   F. STRICT=1 正臂: 先服务完 p1 全部帧, 再服务 p0
// 帧字: [72]=tlast [71:64]=tkeep [63]=port [62:56]=0 [55:32]=idx [31:0]=beat
//=============================================================================
module tb_rx_merge2;

    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;

    integer errs = 0;
    task chk;
        input cond;
        input [8*96-1:0] msg;
        begin
            if (!cond) begin errs = errs + 1; $display("  [FAIL] %0s", msg); end
            else       $display("  [ ok ] %0s", msg);
        end
    endtask

    // ---------------- TB 模型 FIFO ----------------
    localparam QD = 1024;
    reg [72:0] q0 [0:QD-1];
    reg [72:0] q1 [0:QD-1];
    integer h0=0,t0=0,h1=0,t1=0;
    integer ovf0=0,ovf1=0;
    integer depth0=QD, depth1=QD;
    wire p0_v = (t0 > h0);
    wire p1_v = (t1 > h1);
    wire [72:0] p0_q = q0[h0];
    wire [72:0] p1_q = q1[h1];

    integer flen0 [0:255];
    integer flen1 [0:255];

    reg  arm_strict = 1'b0;
    reg  m_ready = 1'b1;

    wire p0_ready_r, p1_ready_r, p0_ready_s, p1_ready_s;
    wire p0_rd = arm_strict ? p0_ready_s : p0_ready_r;
    wire p1_rd = arm_strict ? p1_ready_s : p1_ready_r;
    always @(posedge clk) begin
        if (p0_v && p0_rd) h0 <= h0 + 1;
        if (p1_v && p1_rd) h1 <= h1 + 1;
    end

    // ---------------- DUT: STRICT=0 (RR) ----------------
    wire [63:0] m0_d; wire [7:0] m0_k; wire m0_v, m0_l, m0_u, m0_c, m0_e;
    wire [31:0] sf0_r, sf1_r, so_r, sb_r;
    rx_merge2 #(.STRICT(1'b0)) u_dut (
        .clk(clk), .rst_n(rst_n),
        .p0_tdata(p0_q[63:0]), .p0_tkeep(p0_q[71:64]), .p0_tvalid(p0_v),
        .p0_tready(p0_ready_r), .p0_tlast(p0_q[72]), .p0_tuser(1'b0), .p0_tcrs(1'b1), .p0_terr(1'b0),
        .p1_tdata(p1_q[63:0]), .p1_tkeep(p1_q[71:64]), .p1_tvalid(p1_v),
        .p1_tready(p1_ready_r), .p1_tlast(p1_q[72]), .p1_tuser(1'b0), .p1_tcrs(1'b1), .p1_terr(1'b0),
        .m_tdata(m0_d), .m_tkeep(m0_k), .m_tvalid(m0_v), .m_tready(m_ready),
        .m_tlast(m0_l), .m_tuser(m0_u), .m_tcrs(m0_c), .m_terr(m0_e),
        .stat_frames0(sf0_r), .stat_frames1(sf1_r), .stat_out(so_r), .stat_bubble(sb_r)
    );

    // ---------------- DUT: STRICT=1 (负控/正臂) ----------------
    wire [63:0] m1_d; wire [7:0] m1_k; wire m1_v, m1_l, m1_u, m1_c, m1_e;
    wire [31:0] sf0_s, sf1_s, so_s, sb_s;
    rx_merge2 #(.STRICT(1'b1)) u_strict (
        .clk(clk), .rst_n(rst_n),
        .p0_tdata(p0_q[63:0]), .p0_tkeep(p0_q[71:64]), .p0_tvalid(p0_v),
        .p0_tready(p0_ready_s), .p0_tlast(p0_q[72]), .p0_tuser(1'b0), .p0_tcrs(1'b1), .p0_terr(1'b0),
        .p1_tdata(p1_q[63:0]), .p1_tkeep(p1_q[71:64]), .p1_tvalid(p1_v),
        .p1_tready(p1_ready_s), .p1_tlast(p1_q[72]), .p1_tuser(1'b0), .p1_tcrs(1'b1), .p1_terr(1'b0),
        .m_tdata(m1_d), .m_tkeep(m1_k), .m_tvalid(m1_v), .m_tready(m_ready),
        .m_tlast(m1_l), .m_tuser(m1_u), .m_tcrs(m1_c), .m_terr(m1_e),
        .stat_frames0(sf0_s), .stat_frames1(sf1_s), .stat_out(so_s), .stat_bubble(sb_s)
    );

    // ---------------- 输出检查 ----------------
    wire        ov_v = arm_strict ? m1_v : m0_v;
    wire [63:0] ov_d = arm_strict ? m1_d : m0_d;
    wire        ov_l = arm_strict ? m1_l : m0_l;
    wire        ov_rd= ov_v && m_ready;

    integer frames_seen = 0, o_open = 0, o_port = 0, o_idx = 0, o_beat = 0, o_len = 0;
    integer hist_port [0:255];
    integer nhist = 0;
    reg [255:0] seen0, seen1;

    always @(posedge clk) begin
        if (rst_n && ov_rd) begin
            if (!o_open) begin
                // 帧首拍: 记口/帧号/长度; beat 索引 = 0
                o_open <= 1;
                o_port <= ov_d[63]; o_idx <= ov_d[55:32]; o_beat <= 0;
                o_len  <= ov_d[63] ? flen1[ov_d[55:32]] : flen0[ov_d[55:32]];
                if (ov_d[31:0] !== 32'd0) begin errs=errs+1; $display("  [FAIL] first beat idx != 0"); end
                hist_port[nhist] <= ov_d[63]; nhist <= nhist + 1;
                if (ov_d[63]) seen1[ov_d[55:32]] <= 1'b1; else seen0[ov_d[55:32]] <= 1'b1;
                if (ov_l) begin
                    if (o_len !== 1 && (ov_d[63] ? flen1[ov_d[55:32]] : flen0[ov_d[55:32]]) !== 1)
                        begin errs=errs+1; $display("  [FAIL] single-beat frame with len != 1"); end
                    o_open <= 0; frames_seen <= frames_seen + 1;
                end
            end else begin
                // 帧内后续拍: 口/帧号必须不变, beat 必须连续
                if (ov_d[63] !== o_port || ov_d[55:32] !== o_idx || ov_d[31:0] !== (o_beat+1))
                    begin errs=errs+1; $display("  [FAIL] interleave/beat order p=%0d i=%0d b=%0d", ov_d[63], ov_d[55:32], ov_d[31:0]); end
                if (ov_l) begin
                    if ((o_beat + 1) !== (o_len - 1))
                        begin errs=errs+1; $display("  [FAIL] tlast at beat %0d (len %0d)", o_beat+1, o_len); end
                    o_open <= 0; frames_seen <= frames_seen + 1;
                end else begin
                    o_beat <= o_beat + 1;
                end
            end
        end
    end

    // ---------------- 任务 ----------------
    function [72:0] pack;
        input integer port; input integer idx; input integer b; input last;
        begin
            pack = {last, 8'hFF, port[0], 7'b0, idx[23:0], b[31:0]};
        end
    endfunction

    task push0; input integer idx; input integer len; integer b;
        begin
            flen0[idx] = len;
            for (b=0;b<len;b=b+1) begin
                if ((t0-h0) >= depth0) ovf0 = ovf0 + 1;
                else begin q0[t0] = pack(0, idx, b, (b==len-1)); t0 = t0 + 1; end
            end
        end
    endtask

    task push1; input integer idx; input integer len; integer b;
        begin
            flen1[idx] = len;
            for (b=0;b<len;b=b+1) begin
                if ((t1-h1) >= depth1) ovf1 = ovf1 + 1;
                else begin q1[t1] = pack(1, idx, b, (b==len-1)); t1 = t1 + 1; end
            end
        end
    endtask

    task do_reset;
        begin
            rst_n = 1'b0; m_ready = 1'b1;
            h0=0;t0=0;h1=0;t1=0;ovf0=0;ovf1=0;
            depth0=QD; depth1=QD;
            frames_seen=0; o_open=0; nhist=0;
            seen0 = 0; seen1 = 0;
            repeat(3) @(posedge clk);
            rst_n = 1'b1;
            repeat(2) @(posedge clk);
        end
    endtask

    integer i, guard;

    initial begin
        $display("==== TB_RX_MERGE2 ====");
        do_reset();

        // ---------- A ----------
        arm_strict = 1'b0;
        push0(0,4); push0(1,4); push0(2,4);
        guard=0; while (frames_seen < 3 && guard < 200) begin @(posedge clk); guard=guard+1; end
        chk(frames_seen == 3, "A: 3 frames out (single port, work-conserving)");
        chk(sf0_r == 3 && sf1_r == 0, "A: stat_frames0=3 stat_frames1=0");
        chk(nhist >= 3 && hist_port[0]==0, "A: all served from p0");

        // ---------- B ----------
        do_reset();
        push0(0,4); push0(1,4); push0(2,4);
        push1(0,4); push1(1,4); push1(2,4);
        guard=0; while (frames_seen < 6 && guard < 300) begin @(posedge clk); guard=guard+1; end
        chk(frames_seen == 6, "B: 6 frames out (both ports)");
        chk(sf0_r == 3 && sf1_r == 3, "B: 3+3 frames");
        chk(nhist == 6, "B: 6 frame starts");
        chk(hist_port[0]==1 && hist_port[1]==0 && hist_port[2]==1 && hist_port[3]==0 &&
            hist_port[4]==1 && hist_port[5]==0, "B: strict frame-level alternation p1,p0,...");

        // ---------- C ----------
        do_reset();
        push0(0,4); push0(1,4); push0(2,4);
        push1(0,4); push1(1,4); push1(2,4);
        guard=0;
        while (frames_seen < 6 && guard < 600) begin
            @(posedge clk);
            m_ready <= ((guard % 7) != 0) && ((guard % 11) != 0);
            guard=guard+1;
        end
        m_ready <= 1'b1;
        chk(frames_seen == 6, "C: 6 frames out under random backpressure (atomic)");

        // ---------- D ----------
        do_reset();
        push0(0,4);
        @(posedge clk); @(posedge clk);
        rst_n = 1'b0; repeat(3) @(posedge clk);
        chk(m0_v === 1'b0, "D: m_tvalid low during reset");
        rst_n = 1'b1; repeat(2) @(posedge clk);

        // ---------- E ----------
        do_reset();
        arm_strict = 1'b1;
        push1(0,4);
        m_ready = 1'b1;
        @(posedge clk); @(posedge clk);
        m_ready = 1'b0;
        depth0 = 4;
        push0(0,190); push0(1,190);
        begin : neg_wait
            integer k; reg p0_seen_rd;
            p0_seen_rd = 0;
            for (k=0;k<24;k=k+1) begin
                @(posedge clk);
                if (p0_ready_s !== 1'b0) p0_seen_rd = 1;
            end
            chk(p0_seen_rd == 0, "E: low-priority p0 tready stayed 0 while p1 stalled (>=24 cycles)");
        end
        chk(ovf0 > 0, "E: p0 model FIFO overflow > 0 (DEPTH=4 negative control armed)");
        m_ready = 1'b1;
        guard=0; while (frames_seen < 1 && guard < 800) begin @(posedge clk); guard=guard+1; end
        arm_strict = 1'b0;
        depth0 = QD;

        // ---------- F ----------
        do_reset();
        arm_strict = 1'b1;
        push1(0,4); push1(1,4);
        push0(0,4); push0(1,4);
        guard=0; while (frames_seen < 4 && guard < 400) begin @(posedge clk); guard=guard+1; end
        chk(frames_seen == 4, "F: 4 frames out");
        chk(nhist == 4 && hist_port[0]==1 && hist_port[1]==1 && hist_port[2]==0 && hist_port[3]==0,
            "F: STRICT serves all p1 frames before p0");
        arm_strict = 1'b0;

        if (errs == 0) $display("RX_MERGE2 TB PASS");
        else           $display("RX_MERGE2 TB FAIL errs=%0d", errs);
        $finish;
    end

    initial begin
        #4000000;
        $display("RX_MERGE2 TB FAIL (timeout)");
        $finish;
    end
endmodule
