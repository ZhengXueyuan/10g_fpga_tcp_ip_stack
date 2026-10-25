`timescale 1ns/1ps
// tb_hls_latency.v -- measure the P3 HLS udp_echo netlist's per-frame latency.
// Research-only; no product RTL change.  Feed hls_stim.memh at 1 byte/cycle
// (held-valid, accepted on TREADY) and record rx/tx frame timestamps.
// The clock is 6.4 ns (156.25 MHz) to match the P11 dp_clk domain.
// Single-frame stimuli (ARP-only / UDP-only) are produced by run_hls_latency.py
// so the rx/tx pairing is unambiguous; the full stimulus is also supported.
module tb_hls_latency;
    reg clk = 0, rst_n = 0;
    reg  [15:0] rx_tdata = 0;
    reg         rx_tvalid = 0;
    wire        rx_tready;
    wire [15:0] tx_tdata;
    wire        tx_tvalid;
    reg         tx_tready = 1;
    wire [31:0] cfg_tdata;
    wire        cfg_tvalid;
    reg  [15:0] adv_wnd = 16'd0;

    udp_echo dut (
        .ap_clk(clk), .ap_rst_n(rst_n), .reset_n(rst_n),
        .rx_stream_TDATA(rx_tdata), .rx_stream_TVALID(rx_tvalid),
        .rx_stream_TREADY(rx_tready),
        .tx_stream_TDATA(tx_tdata), .tx_stream_TVALID(tx_tvalid),
        .tx_stream_TREADY(tx_tready),
        .msg_stream_TDATA(), .msg_stream_TVALID(), .msg_stream_TREADY(1'b1),
        .cfg_stream_TDATA(cfg_tdata), .cfg_stream_TVALID(cfg_tvalid),
        .cfg_stream_TREADY(1'b1),
        .i_tcp_adv_wnd(adv_wnd),
        .led_d0(), .led_d1(), .led_d2(), .led_d3()
    );

    always #3.2 clk = ~clk;

    reg [7:0] stim  [0:4095];
    reg       slast [0:4095];
    integer   nstim, i, fd, k;
    integer   cyc = 0;
    integer   rx_frames = 0, tx_frames = 0;
    integer   rx_idx = 0, tx_idx = 0;
    integer   t_rx_first = 0, t_rx_last = 0;
    integer   t_tx_first = 0, t_tx_last = 0;
    reg       in_rx = 0, in_tx = 0;
    integer   rx_accepts = 0, rx_valid_cycles = 0, rx_wait_cycles = 0;
    integer   rx_first_arr [0:7];
    integer   rx_last_arr  [0:7];
    integer   tx_first_arr [0:7];
    integer   tx_last_arr  [0:7];
    integer   tx_bytes_arr [0:7];
    integer   tx_bytes = 0;

    initial begin
        $readmemh("hls_stim.memh", stim);
        $readmemh("hls_stim_last.memh", slast);
        nstim = 0;
        while (nstim < 4096 && stim[nstim] !== 8'hxx) nstim = nstim + 1;
        fd = $fopen("hls_latency_out.txt", "w");
        #200; rst_n = 1;
        wait (i >= nstim);
        repeat (200000) @(posedge clk);
        $fwrite(fd, "RX_TOTAL accepts=%0d valid_cycles=%0d wait_cycles=%0d cyc=%0d\n",
                rx_accepts, rx_valid_cycles, rx_wait_cycles, cyc);
        for (k = 0; k < rx_idx; k = k + 1)
            $fwrite(fd, "RX_FRAME idx=%0d first=%0d last=%0d dur=%0d\n",
                    k, rx_first_arr[k], rx_last_arr[k], rx_last_arr[k] - rx_first_arr[k]);
        for (k = 0; k < tx_idx; k = k + 1)
            $fwrite(fd, "TX_FRAME idx=%0d first=%0d last=%0d dur=%0d bytes=%0d\n",
                    k, tx_first_arr[k], tx_last_arr[k], tx_last_arr[k] - tx_first_arr[k], tx_bytes_arr[k]);
        $fwrite(fd, "END rx_frames=%0d tx_frames=%0d cyc=%0d\n", rx_frames, tx_frames, cyc);
        $fclose(fd);
        $finish;
    end

    // 1 byte/cycle feeder: i = index of the byte currently on the bus.
    always @(posedge clk) begin
        cyc <= cyc + 1;
        if (!rst_n) begin
            rx_tvalid <= 0; rx_tdata <= 0; i <= 0;
        end else begin
            if (rx_tvalid) begin
                rx_valid_cycles = rx_valid_cycles + 1;
                if (rx_tready) begin
                    rx_accepts = rx_accepts + 1;
                    if (!in_rx) begin
                        t_rx_first = cyc;
                        in_rx = 1;
                    end
                    if (slast[i]) begin
                        t_rx_last = cyc;
                        in_rx = 0;
                        rx_first_arr[rx_idx] = t_rx_first;
                        rx_last_arr[rx_idx]  = t_rx_last;
                        rx_idx = rx_idx + 1;
                        rx_frames = rx_frames + 1;
                    end
                    i <= i + 1;
                    if (i + 1 < nstim) begin
                        rx_tdata  <= {6'b0, slast[i+1], stim[i+1]};
                        rx_tvalid <= 1;
                    end else begin
                        rx_tvalid <= 0;
                    end
                end else begin
                    rx_wait_cycles = rx_wait_cycles + 1;
                end
            end else if (i < nstim) begin
                rx_tdata  <= {6'b0, slast[i], stim[i]};
                rx_tvalid <= 1;
            end
        end
    end

    always @(posedge clk) begin
        if (rst_n && tx_tvalid && tx_tready) begin
            tx_bytes = tx_bytes + 1;
            if (!in_tx) begin
                t_tx_first = cyc;
                in_tx = 1;
            end
            if (tx_tdata[8]) begin
                t_tx_last = cyc;
                in_tx = 0;
                tx_first_arr[tx_idx] = t_tx_first;
                tx_last_arr[tx_idx]  = t_tx_last;
                tx_bytes_arr[tx_idx] = tx_bytes;
                tx_bytes = 0;
                tx_idx = tx_idx + 1;
                tx_frames = tx_frames + 1;
            end
        end
    end
endmodule
