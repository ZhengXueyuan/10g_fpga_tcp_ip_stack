`timescale 1ns/1ps
//=============================================================================
// tb_tx_arb_starve: tx_arb 慢路径饿死判别 (P11 §0-83 根因)
//
//   源:
//     fast = 组合连续帧源 (tvalid 恒 1; 每 4 字一帧, 帧间零气泡)
//            —— 模拟 tcp_tx_frame 在持续 TCP 洪泛下输出 AXIS 永不放 valid 的形态
//     slow = 单帧、held-valid (第 200 ns 到齐) —— 模拟 HLS slow_tx_adp 的 SYN-ACK
//
//   判决:
//     legacy tx_arb (fast 严格优先): slow_txn == 0 ⇒ STARVE_CONFIRMED
//     加 guard 后 (见 rtl/tx_arb.v 参数 STARVE_GUARD): slow_txn >= 4 ⇒ SLOW_SERVED
//
//   本 TB 只做"有没有服务"的判别; 数据完整性由既有 tb_tx_arb + 刺激比对覆盖。
//=============================================================================
module tb_tx_arb_starve;

    reg clk = 0;
    reg rst_n = 0;

    // ---- fast: continuous 4-word frames, no gap ----
    reg  [31:0] fi = 32'd0;
    wire [63:0] f_tdata = {32'hF0000000, fi};
    wire [7:0]  f_tkeep = 8'hFF;
    wire        f_tlast = (fi[1:0] == 2'd3);
    reg         f_tvalid = 1'b0;
    wire        f_tready;

    // ---- slow: one 4-word frame, held until served ----
    reg  [31:0] si = 32'd0;
    wire [63:0] s_tdata = {32'h50000000, si};
    wire [7:0]  s_tkeep = 8'hFF;
    wire        s_tlast = (si[1:0] == 2'd3);
    reg         s_tvalid = 1'b0;
    wire        s_tready;

    wire [63:0] m_tdata;
    wire [7:0]  m_tkeep;
    wire        m_tvalid, m_tlast;
    reg         m_rdy = 1'b1;

    integer fast_txn = 0;
    integer slow_txn = 0;
    integer cycles   = 0;

`ifdef TB_GUARD
    tx_arb #(.STARVE_GUARD(1)) dut (
`else
    tx_arb #(.STARVE_GUARD(0)) dut (
`endif
        .clk(clk), .rst_n(rst_n),
        .s_fast_tdata(f_tdata), .s_fast_tkeep(f_tkeep),
        .s_fast_tvalid(f_tvalid), .s_fast_tready(f_tready),
        .s_fast_tlast(f_tlast),
        .s_slow_tdata(s_tdata), .s_slow_tkeep(s_tkeep),
        .s_slow_tvalid(s_tvalid), .s_slow_tready(s_tready),
        .s_slow_tlast(s_tlast),
        .m_axis_tdata(m_tdata), .m_axis_tkeep(m_tkeep),
        .m_axis_tvalid(m_tvalid), .m_axis_tready(m_rdy),
        .m_axis_tlast(m_tlast)
    );

    always #4 clk = ~clk;

`ifdef TB_REALGAP
    // Realistic fast source: `tcp_tx_frame` has a 2-cycle tvalid=0 hole at every
    // frame boundary (T_DONE + T_HDR; DESIGN §9.1). With this arm the LEGACY
    // strict-priority arbiter MUST serve the pending slow frame -> refutes hunger.
    reg [1:0] fgap = 2'd0;
    always @(posedge clk) begin
        if (!rst_n) begin
            f_tvalid <= 1'b0; fgap <= 2'd0;
        end else if (f_tvalid && f_tready && f_tlast) begin
            f_tvalid <= 1'b0; fgap <= 2'd2;      // frame-end: 2 idle cycles
        end else if (!f_tvalid) begin
            if (fgap != 2'd0) fgap <= fgap - 2'd1;
            else              f_tvalid <= 1'b1;
        end
    end
`endif

    // source word advance (held-valid, zero inter-word gap)
    always @(posedge clk) begin
        if (!rst_n) begin
            fi <= 32'd0;
            si <= 32'd0;
        end else begin
            if (f_tvalid && f_tready) fi <= fi + 32'd1;
            if (s_tvalid && s_tready) si <= si + 32'd1;
        end
    end

    integer dbg = 0;
    integer cyc2 = 0;
    always @(posedge clk) begin
        if (rst_n) begin
            cycles <= cycles + 1;
            cyc2 = cyc2 + 1;
            if (m_tvalid && m_rdy) begin
                if (dbg < 12) begin
                    $display("HS cyc=%0d data=%016h last=%b sel_fast=%b fi=%0d",
                             cyc2, m_tdata, m_tlast, dut.sel_fast, fi);
                    dbg = dbg + 1;
                end
                if (m_tlast && m_tdata[63:32] == 32'hF0000000)
                    fast_txn <= fast_txn + 1;
                if (m_tlast && m_tdata[63:32] == 32'h50000000)
                    slow_txn <= slow_txn + 1;
            end
        end
    end

    initial begin
        #100 rst_n = 1;
        @(posedge clk);
`ifndef TB_REALGAP
        f_tvalid = 1'b1;          // zero-gap pathological source
`endif
        #200;
        s_tvalid = 1'b1;          // slow frame arrives and stays pending
        #20000;                   // ~2500 cycles
        $display("STARVE_RESULT cycles=%0d fast_frames=%0d slow_frames=%0d",
                 cycles, fast_txn, slow_txn);
        if (slow_txn == 0)
            $display("LEGACY_STARVE_CONFIRMED slow_frames=0 while fast streams");
        else
            $display("SLOW_SERVED slow_frames=%0d", slow_txn);
`ifdef TB_REALGAP
        if (slow_txn >= 1)
            $display("LEGACY_SERVES_WITH_GAP slow_frames=%0d (starve root-cause refuted)", slow_txn);
        else
            $display("LEGACY_STILL_STARVES_WITH_GAP");
`endif
        $finish;
    end

endmodule
