`timescale 1ns/1ps
// ===========================================================================
// tb_p1_ch0_unit.v -- P11 / P1 ch0 (J7) focused unit gate (real wrapper).
//   Same DUT/compile configuration as tb_p7b_chain (board body + P7B_SIM_NOPCS),
//   but ONLY the P1 arms: ch0 tap/sink counters, W76 vs W39 independence,
//   LOS edge, snapshot gather timeout (double generation + recovery), TX idle.
//   Rationale: a fast, targeted gate for the P1 feature; the long chain gate
//   keeps its own copy of these arms as part of the standing regression.
// ===========================================================================
module tb_p1_ch0_unit;

    integer fails = 0, checks = 0;

    task chk;
        input [255:0] name;
        input         cond;
        input [255:0] src;
        begin
            checks = checks + 1;
            if (cond !== 1'b1) begin
                fails = fails + 1;
                $display("  [FAIL] %0s   src=%0s", name, src);
            end else begin
                $display("  [PASS] %0s   src=%0s", name, src);
            end
        end
    endtask

    // ---------------- clocks / reset / DUT --------------------------------
    reg reset_n = 0;
    reg pcie_sys_clk_p = 0, pcie_sys_clk_n = 1;
    reg sys_clk_p = 0, sys_clk_n = 1;
    always #5 pcie_sys_clk_p = ~pcie_sys_clk_p;
    always #5 pcie_sys_clk_n = ~pcie_sys_clk_n;
    always #5 sys_clk_p = ~sys_clk_p;
    always #5 sys_clk_n = ~sys_clk_p;

    reg [3:0] pcie_rxp = 0, pcie_rxn = 0;
    wire [3:0] pcie_txp, pcie_txn;
    reg gt_refclk_p = 0, gt_refclk_n = 1;
    reg sfp1_rxp = 0, sfp1_rxn = 0, sfp2_rxp = 0, sfp2_rxn = 0;
    wire sfp1_txp, sfp1_txn, sfp2_txp, sfp2_txn;
    reg  sfp1_rx_los = 1, sfp2_rx_los = 0;
    wire sfp1_tx_dis, sfp2_tx_dis;
    wire led_d0, led_d1, led_d2, led_d3, uart_txd;

    wrapper_p4 u_dut (
        .reset_n(reset_n),
        .pcie_sys_clk_p(pcie_sys_clk_p), .pcie_sys_clk_n(pcie_sys_clk_n),
        .pcie_txp(pcie_txp), .pcie_txn(pcie_txn),
        .pcie_rxp(pcie_rxp), .pcie_rxn(pcie_rxn),
        .sys_clk_p(sys_clk_p), .sys_clk_n(sys_clk_n),
        .gt_refclk_p(gt_refclk_p), .gt_refclk_n(gt_refclk_n),
        .sfp1_rxp(sfp1_rxp), .sfp1_rxn(sfp1_rxn),
        .sfp1_txp(sfp1_txp), .sfp1_txn(sfp1_txn),
        .sfp2_rxp(sfp2_rxp), .sfp2_rxn(sfp2_rxn),
        .sfp2_txp(sfp2_txp), .sfp2_txn(sfp2_txn),
        .sfp1_rx_los(sfp1_rx_los), .sfp2_rx_los(sfp2_rx_los),
        .sfp1_tx_dis(sfp1_tx_dis), .sfp2_tx_dis(sfp2_tx_dis),
        .led_d0(led_d0), .led_d1(led_d1), .led_d2(led_d2), .led_d3(led_d3),
        .uart_txd(uart_txd)
    );

    // ---------------- CRC-32 (bit serial, TB-side) ------------------------
    function [31:0] crc32_byte;
        input [31:0] c;
        input [7:0]  b;
        integer i;
        reg [31:0] x;
        begin
            x = c ^ {24'd0, b};
            for (i = 0; i < 8; i = i + 1)
                x = x[0] ? ((x >> 1) ^ 32'hEDB88320) : (x >> 1);
            crc32_byte = x;
        end
    endfunction

    // ---------------- ch0 XGMII injection queue ---------------------------
    reg [63:0] xq_d [0:4095];
    reg [7:0]  xq_c [0:4095];
    integer    xq_wr = 0, xq_rd = 0;
    wire       xq_empty = (xq_rd == xq_wr);
    always @(posedge u_dut.rx_clk_out_0) begin
        if (!xq_empty) xq_rd <= xq_rd + 1;
        u_dut.u_pcs.inj_d0 <= xq_empty ? 64'h0707070707070707 : xq_d[xq_rd];
        u_dut.u_pcs.inj_c0 <= xq_empty ? 8'hFF                 : xq_c[xq_rd];
    end

    reg [7:0] pat [0:255];
    integer   pi;
    task init_pat;
        begin
            for (pi = 0; pi < 256; pi = pi + 1) pat[pi] = pi[7:0];
            pat[0] = 8'h01; pat[1] = 8'h23; pat[2] = 8'h45; pat[3] = 8'h67;
        end
    endtask

    reg [7:0] wb [0:4095];
    reg       wc [0:4095];

    task pack_words;
        input integer n;
        integer i, k;
        reg [63:0] d;
        reg [7:0]  c;
        begin
            i = 0;
            while (i < n) begin
                d = 64'd0; c = 8'd0;
                for (k = 0; k < 8; k = k + 1) begin
                    if (i + k < n) begin d[k*8 +: 8] = wb[i+k]; c[k] = wc[i+k]; end
                    else           begin d[k*8 +: 8] = 8'h07;   c[k] = 1'b1;  end
                end
                xq_d[xq_wr] = d; xq_c[xq_wr] = c; xq_wr = xq_wr + 1;
                i = i + 8;
            end
        end
    endtask

    // preamble + n content bytes + FCS + /T/  (lane0 start)
    reg [31:0] fcs;
    task build_frame;
        input integer n;
        integer i, m;
        begin
            fcs = 32'hFFFFFFFF;
            for (i = 0; i < n; i = i + 1) fcs = crc32_byte(fcs, pat[i]);
            fcs = ~fcs;
            wb[0] = 8'hFB; wc[0] = 1;
            for (i = 0; i < 6; i = i + 1) begin wb[1+i] = 8'h55; wc[1+i] = 0; end
            wb[7] = 8'hD5; wc[7] = 0;
            m = 8;
            for (i = 0; i < n; i = i + 1) begin wb[m] = pat[i]; wc[m] = 0; m = m + 1; end
            wb[m] = fcs[7:0];   wc[m] = 0; m = m + 1;
            wb[m] = fcs[15:8];  wc[m] = 0; m = m + 1;
            wb[m] = fcs[23:16]; wc[m] = 0; m = m + 1;
            wb[m] = fcs[31:24]; wc[m] = 0; m = m + 1;
            wb[m] = 8'hFD; wc[m] = 1; m = m + 1;
            pack_words(m);
        end
    endtask

    // ---------------- snapshot helper (hard timeout) ----------------------
    reg [31:0] v;
    task snap_take;
        integer n;
        reg ok;
        begin
            u_dut.u_pcie_xdma.axil_write(32'h18, 32'h1);
            n = 0; ok = 1'b0;
            while (n < 12000) begin
                u_dut.u_pcie_xdma.axil_read(32'h1C, v);
                if (v[1] === 1'b1) begin ok = 1'b1; n = 12000; end
                else begin n = n + 1; @(posedge u_dut.pcie_axi_aclk); end
            end
            checks = checks + 1;
            if (!ok) begin
                fails = fails + 1;
                $display("  [FAIL] snap_take TIMEOUT (done not set within 12000 pcie cycles)");
            end
        end
    endtask

    integer b79, b80, b81, b82, a79, a80, a81, a82;
    integer evt0;

    initial begin
        init_pat;
        #3000;
        reset_n = 1;
        repeat (400) @(posedge u_dut.pcie_axi_aclk);
        repeat (100) @(posedge u_dut.dp_clk);

        // ---- 1. mode bit + real status -----------------------------------
        snap_take;
        u_dut.u_pcie_xdma.axil_read(32'h158, v);
        chk("1a mode = A (SFP2_MODE_B_SEL=0)", v[31] === 1'b0, "no SFP2_MODE_B macro");
        u_dut.u_pcie_xdma.axil_read(32'h150, v);
        chk("1b ch0 block_lock (stub default)", v[2] === 1'b1, "stub ch0 link-up");

        // ---- 2. W76 vs W39 independence (split stub status) --------------
        force u_dut.u_pcs.blk_lock_0 = 1'b1;
        force u_dut.u_pcs.hi_ber_0   = 1'b1;
        force u_dut.u_pcs.rerr_0     = 8'h5A;
        force u_dut.u_pcs.blk_lock_1 = 1'b0;
        force u_dut.u_pcs.hi_ber_1   = 1'b0;
        repeat (50) @(posedge u_dut.dp_clk);
        snap_take;
        u_dut.u_pcie_xdma.axil_read(32'h150, v);
        chk("2a W76 follows ch0 producers", ((v & 32'hBFFFFFFF) === 32'h200B501C),
            "blk/hi_ber/rerr forced on ch0");
        u_dut.u_pcie_xdma.axil_read(32'hBC, v);
        chk("2b W39 is NOT polluted by ch0", (v[2] === 1'b0) && (v[4] === 1'b0),
            "ch1 block_lock/hi_ber forced 0");
        release u_dut.u_pcs.blk_lock_0; release u_dut.u_pcs.hi_ber_0;
        release u_dut.u_pcs.rerr_0;
        release u_dut.u_pcs.blk_lock_1; release u_dut.u_pcs.hi_ber_1;
        repeat (50) @(posedge u_dut.dp_clk);

        // ---- 3. ch0 tap / sink good frames -------------------------------
        snap_take;
        u_dut.u_pcie_xdma.axil_read(32'h15C, b79);
        u_dut.u_pcie_xdma.axil_read(32'h160, b80);
        u_dut.u_pcie_xdma.axil_read(32'h164, b81);
        u_dut.u_pcie_xdma.axil_read(32'h168, b82);
        build_frame(100); build_frame(100);
        repeat (800) @(posedge u_dut.rx_clk_out_0);
        repeat (200) @(posedge u_dut.pcie_axi_aclk);
        snap_take;
        u_dut.u_pcie_xdma.axil_read(32'h15C, a79);
        u_dut.u_pcie_xdma.axil_read(32'h160, a80);
        u_dut.u_pcie_xdma.axil_read(32'h164, a81);
        u_dut.u_pcie_xdma.axil_read(32'h168, a82);
        chk("3a dW79 == 2", (a79 - b79) === 2, "2 good frames");
        chk("3b dW80 == 200", (a80 - b80) === 200, "2 x 100 content bytes");
        chk("3c dW81 == 0", (a81 - b81) === 0, "good FCS => no crc_err");
        chk("3d dW82 == 0", (a82 - b82) === 0, "no drops");

        // ---- 4. tready=0 => no delivery, drops rise ----------------------
        u_dut.u_pcie_xdma.axil_read(32'h15C, b79);
        u_dut.u_pcie_xdma.axil_read(32'h168, b82);
        force u_dut.ch0_rx_tready = 1'b0;
        build_frame(100); build_frame(100); build_frame(100); build_frame(100);
        repeat (800) @(posedge u_dut.rx_clk_out_0);
        repeat (200) @(posedge u_dut.pcie_axi_aclk);
        snap_take;
        u_dut.u_pcie_xdma.axil_read(32'h15C, a79);
        u_dut.u_pcie_xdma.axil_read(32'h168, a82);
        chk("4a tready=0: W79 flat", a79 === b79, "count point = sink delivery");
        chk("4b tready=0: W82 rises", (a82 - b82) > 0, "4 x 15 words vs 16-word FIFO");
        release u_dut.ch0_rx_tready;
        repeat (800) @(posedge u_dut.rx_clk_out_0);
        repeat (200) @(posedge u_dut.pcie_axi_aclk);

        // ---- 5. LOS rising edge only -------------------------------------
        snap_take;
        u_dut.u_pcie_xdma.axil_read(32'h158, v);
        evt0 = v[23:16];
        sfp1_rx_los = 1'b0; repeat (30) @(posedge u_dut.dp_clk);
        snap_take;
        u_dut.u_pcie_xdma.axil_read(32'h158, v);
        chk("5a falling edge: level=0, no event",
            (v[0] === 1'b0) && (((v[23:16] - evt0) & 8'hFF) === 0), "rising-edge definition");
        sfp1_rx_los = 1'b1; repeat (30) @(posedge u_dut.dp_clk);
        snap_take;
        u_dut.u_pcie_xdma.axil_read(32'h158, v);
        chk("5b rising edge: level=1, +1 event",
            (v[0] === 1'b1) && (((v[23:16] - evt0) & 8'hFF) === 1), "0->1 = +1");

        // ---- 6. timeout: stop ch0 clock, two generations, recovery -------
        force u_dut.u_pcs.rx_clk_0 = 1'b0;
        repeat (20) @(posedge u_dut.pcie_axi_aclk);
        snap_take;
        u_dut.u_pcie_xdma.axil_read(32'h1C, v);
        chk("6a gen1: SNAP_STATUS[7]=1, busy=0",
            (v[7] === 1'b1) && (v[0] === 1'b0), "ch0 bundle stale; busy excludes ch0");
        u_dut.u_pcie_xdma.axil_read(32'h150, v);
        chk("6b gen1: W76 readable", v[2] === 1'b1, "dp bundle unaffected");
        snap_take;
        u_dut.u_pcie_xdma.axil_read(32'h1C, v);
        chk("6c gen2: SNAP_STATUS[7]=1, busy=0",
            (v[7] === 1'b1) && (v[0] === 1'b0), "previous stuck => immediate stale");
        release u_dut.u_pcs.rx_clk_0;
        repeat (400) @(posedge u_dut.rx_clk_out_0);
        repeat (200) @(posedge u_dut.pcie_axi_aclk);
        snap_take;
        u_dut.u_pcie_xdma.axil_read(32'h1C, v);
        chk("6d recovery: SNAP_STATUS[7]=0", v[7] === 1'b0, "handshake completes");

        // ---- 7. ch0 TX stays constant IDLE -------------------------------
        chk("7a ch0 TX data = idle", u_dut.u_pcs.txcap_d0 === 64'h0707070707070707,
            "no ch0 TX MAC in P1");
        chk("7b ch0 TX control = /I/", u_dut.u_pcs.txcap_c0 === 8'hFF, "all lanes idle");

        $display("==== tb_p1_ch0_unit done: %0d checks, %0d fail ====", checks, fails);
        if (fails == 0) $display("UNIT VERDICT = PASS"); else $display("UNIT VERDICT = FAIL");
        $finish;
    end

    initial begin
        #2000000;
        $display("  [FAIL] WATCHDOG timeout");
        $display("UNIT VERDICT = FAIL");
        $finish;
    end

endmodule
