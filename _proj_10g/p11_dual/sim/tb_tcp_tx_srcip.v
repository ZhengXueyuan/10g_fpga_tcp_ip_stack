`timescale 1ns/1ps
//=============================================================================
// tb_tcp_tx_srcip.v — P11 P2-甲 G5: tcp_tx_frame per-connection 源 IP/端口位
//=============================================================================
// 同一 TB 编译两体: -d TCP_TX_OVL (板上体) / 无 (默认体); 均以
// PER_CONN_SRC_IP=1 例化。判据逐字节:
//   1) 数据帧: IP 头 src = cam_rd_dip (IP_B), IP csum 有效, TCP csum 有效
//      (伪头含 src IP), o_port = cam_rd_port。
//   2) 控制帧 (SYN-ACK): src IP = cam_rd_dip, 两校验和有效。
//   3) N-6 专项: 上一帧用 IP_A 锁存 lip/ctrl_lip 后, 当前控制帧用 IP_B ——
//      SYN-ACK 伪头必须按 IP_B (误用 lip_r/旧 ctrl_lip 的实现在此臂红)。
//   4) 重放帧 (retx 会话): src IP 来自该连接的 CAM (IP_B)。
//   5) o_port 在 tvalid && !tready 期间逐拍不变 (M-12)。
//   6) 错源 IP 变异 (mk_mut_srcip.py 生成的 DUT) 必须红。
//=============================================================================
module tb_tcp_tx_srcip;

    reg clk = 1'b0, rst_n = 1'b0;
    always #3.2 clk = ~clk;

    integer errs = 0;
    task chk;
        input cond;
        input [8*110-1:0] msg;
        begin
            if (!cond) begin errs = errs + 1; $display("  [FAIL] %0s", msg); end
            else       $display("  [ ok ] %0s", msg);
        end
    endtask

    // ---------------- DUT 激励侧 ----------------
    reg [63:0] s_tdata = 0; reg [7:0] s_tkeep = 0; reg s_tvalid = 0; reg s_tlast = 0;
    reg [3:0]  s_tid = 0;
    wire       s_tready;
    reg        ack_req = 0, ack_syn = 0, ack_fin = 0, ack_rst = 0;
    reg [3:0]  ack_id = 0; reg [31:0] ack_val = 0;
    reg [15:0] fin_req = 0, rst_req = 0;
    reg        cfg_up = 0; reg [3:0] cfg_up_id = 0;
    reg        wu_req = 0; reg [3:0] wu_id = 0; reg [31:0] wu_val = 0;
    wire       wu_gnt;
    wire [3:0] rb_id; wire [31:0] rb_snd_nxt, rb_rcv_nxt; wire [15:0] rb_rcv_wnd;
    reg  [31:0] rb_snd_nxt_i = 32'h0000_2000, rb_rcv_nxt_i = 32'h0000_8000;
    reg  [15:0] rb_rcv_wnd_i = 16'hFFF0;
    reg  [31:0] rb_snd_una_i = 32'h0000_2000;
    reg  [15:0] rb_snd_wnd_i = 16'hFFF0;
    reg  [3:0]  rb_state_i  = 4'd1;
    reg         win_open_i  = 1'b1;
    reg  [15:0] win_inflight_i = 16'd0, win_wnd_eff_i = 16'hFFF0;
    reg         retx_req = 0; reg [3:0] retx_id = 0;
    wire        retx_gnt;
    wire [31:0] stat_retx, o_retx_hi; wire o_retx_active; wire [3:0] o_retx_id;
    wire        upd_wr; wire [3:0] upd_id; wire [2:0] upd_sel; wire [31:0] upd_val;
    wire [3:0]  cam_rd_id;
    // CAM 返回 (TB 常量; DUT 的 cam_rd_id 被忽略 —— 单连接场景)
    reg  [47:0] cam_dmac = 48'h0011_2233_4455;
    reg  [31:0] cam_sip  = 32'hC0A8_6465;   // peer 192.168.100.101
    reg  [15:0] cam_sport= 16'h3039, cam_dport = 16'h1F90;
    reg  [31:0] cam_dip  = 32'hC0A8_6404;   // IP_B
    reg         cam_port = 1'b1;

    wire [63:0] m_tdata; wire [7:0] m_tkeep; wire m_tvalid; reg m_tready = 1'b1;
    wire        m_tlast;
    wire        o_port;
    wire [31:0] stat_frames, stat_bytes, stat_ack, stat_ack_drop, stat_eend;
    wire [31:0] stat_drop_len, stat_fin, stat_rst, stat_tlast_in, stat_winstall, stat_winstall_cap;
    wire [31:0] o_win_at_winstall;
    wire        dbg_wnd_open, dbg_pay_full, dbg_sready, dbg_saxis_tvalid;
    wire [11:0] dbg_plen_r; wire [2:0] dbg_state;
    wire [8:0]  dbg_pay_wptr, dbg_pay_rptr; wire dbg_pay_full2, dbg_pay_empty;
    wire [11:0] dbg_plen;
    wire [15:0] o_fin_sent, o_rst_sent;

    tcp_tx_frame #(.PER_CONN_SRC_IP(1'b1)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tdata(s_tdata), .s_axis_tkeep(s_tkeep), .s_axis_tvalid(s_tvalid),
        .s_axis_tready(s_tready), .s_axis_tlast(s_tlast), .s_axis_tid(s_tid),
        .ack_req(ack_req), .ack_id(ack_id), .ack_val(ack_val), .ack_syn(ack_syn),
        .ack_seen_i(16'hFFFF),
        .ack_fin(ack_fin), .ack_rst(ack_rst),
        .fin_req(fin_req), .rst_req(rst_req),
        .cfg_up(cfg_up), .cfg_up_id(cfg_up_id),
        .wu_req(wu_req), .wu_id(wu_id), .wu_val(wu_val), .wu_gnt(wu_gnt),
        .rb_id(rb_id), .rb_snd_nxt(rb_snd_nxt_i), .rb_rcv_nxt(rb_rcv_nxt_i),
        .rb_rcv_wnd(rb_rcv_wnd_i), .rb_snd_una(rb_snd_una_i), .rb_snd_wnd(rb_snd_wnd_i),
        .rb_state(rb_state_i),
        .win_open(win_open_i), .win_inflight(win_inflight_i), .win_wnd_eff(win_wnd_eff_i),
        .retx_req(retx_req), .retx_id(retx_id), .retx_gnt(retx_gnt),
        .stat_retx(stat_retx), .o_retx_hi(o_retx_hi), .o_retx_active(o_retx_active),
        .o_retx_id(o_retx_id),
        .upd_wr(upd_wr), .upd_id(upd_id), .upd_sel(upd_sel), .upd_val(upd_val),
        .cam_rd_id(cam_rd_id),
        .cam_rd_dmac(cam_dmac), .cam_rd_sip(cam_sip), .cam_rd_sport(cam_sport),
        .cam_rd_dport(cam_dport), .cam_rd_dip(cam_dip), .cam_rd_port(cam_port),
        .cfg_src_mac(48'h000A_3501_FEC0), .cfg_src_ip(32'hC0A8_6402),
        .o_port(o_port),
        .m_axis_tdata(m_tdata), .m_axis_tkeep(m_tkeep), .m_axis_tvalid(m_tvalid),
        .m_axis_tready(m_tready), .m_axis_tlast(m_tlast),
        .stat_frames(stat_frames), .stat_bytes(stat_bytes), .stat_ack(stat_ack),
        .stat_ack_drop(stat_ack_drop), .stat_eend(stat_eend),
        .stat_drop_len(stat_drop_len), .stat_fin(stat_fin), .stat_rst(stat_rst),
        .stat_tlast_in(stat_tlast_in), .stat_winstall(stat_winstall),
        .stat_winstall_cap(stat_winstall_cap), .o_win_at_winstall(o_win_at_winstall),
        .dbg_wnd_open(dbg_wnd_open), .dbg_pay_full(dbg_pay_full), .dbg_sready(dbg_sready),
        .dbg_saxis_tvalid(dbg_saxis_tvalid), .dbg_plen_r(dbg_plen_r), .dbg_state(dbg_state),
        .dbg_pay_wptr(dbg_pay_wptr), .dbg_pay_rptr(dbg_pay_rptr),
        .dbg_pay_full2(dbg_pay_full2), .dbg_pay_empty(dbg_pay_empty), .dbg_plen(dbg_plen)
    );

    // ---------------- TCB 模型: 把 DUT 的 snd_nxt 推进写落回输入 ----------------
    //   (真实系统里这些写进 tcb; 本 TB 用单寄存器模型。否则重放会话不会收敛:
    //    rb_snd_nxt 恒定 ⇒ ring_delta 恒非零 ⇒ DUT 无限重放。)
    always @(posedge clk) begin
        if (rst_n && upd_wr && (upd_sel == 3'd1) && (upd_id == 4'd0))
            rb_snd_nxt_i <= upd_val;
    end

    // ---------------- 输出抓取 ----------------
    localparam MAXF = 12;
    reg [7:0]  capb [0:MAXF*512-1];
    integer    cap_len [0:MAXF-1];
    integer    cap_n = 0;
    integer    cur_len = 0;
    reg [7:0]  cur_byte [0:511];
    function integer popc8; input [7:0] v; integer i;
        begin popc8=0; for(i=0;i<8;i=i+1) if (v[i]) popc8=popc8+1; end
    endfunction
    // 本项目 AXIS 合同: tkeep 从 bit7 向下连续; 字内字节从 bit63:56 顺序排列
    always @(posedge clk) begin
        if (rst_n && m_tvalid && m_tready) begin : grab
            integer k, n, j;
            n = popc8(m_tkeep);
            for (k=0;k<n;k=k+1) cur_byte[cur_len+k] = m_tdata[(7-k)*8 +: 8];
            if (m_tlast) begin
                cap_len[cap_n] = cur_len + n;
                for (j=0;j<cap_len[cap_n];j=j+1) capb[cap_n*512+j] = cur_byte[j];
                cap_n = cap_n + 1;
                cur_len = 0;
            end else begin
                cur_len = cur_len + n;
            end
        end
    end

    task wait_frames; input integer n; integer g;
        begin
            g=0; while (cap_n < n && g < 2000) begin @(posedge clk); g=g+1; end
        end
    endtask

    // (csum16 已删: Verilog-2001 不允许数组形参; 校验和直接在各臂内联计算)

    // 检查第 fi 个捕获帧: 期望 src ip = e_sip, TCP flags 高 8 位 e_flags (bit 同 TCP)
    integer last_checked = 0;
    task check_frame;
        input integer fi;
        input [31:0] e_sip;
        input [7:0]  e_flags;
        input [8*48-1:0] tag;
        integer p, tcpoff, seglen, i; reg [31:0] s; reg [15:0] got, exp;
        begin
            p = fi*512;
            chk(cap_len[fi] >= 54, "frame length >= 54");
            // src IP
            chk(({capb[p+26],capb[p+27],capb[p+28],capb[p+29]} === e_sip),
                "IP src == expected (per-connection)");
            // MAC src = cfg_src_mac
            chk((capb[p+6]==8'h00 && capb[p+7]==8'h0A && capb[p+8]==8'h35 &&
                 capb[p+9]==8'h01 && capb[p+10]==8'hFE && capb[p+11]==8'hC0),
                "Ethernet src MAC = cfg_src_mac");
            // IP checksum
            s = 0;
            for (i=0;i<10;i=i+1) s = s + ((capb[p+14+i*2]<<8) | capb[p+14+i*2+1]);
            while (s >> 16) s = (s & 16'hFFFF) + (s >> 16);
            chk(s[15:0] === 16'hFFFF, "IP header checksum valid");
            tcpoff = p + 14 + 20;
            seglen = ((capb[p+16]<<8)|capb[p+17]) - 20;   // TCP segment length
            // TCP checksum with pseudo-header using e_sip
            s = 6 + seglen;
            s = s + ((e_sip>>16)&16'hFFFF) + (e_sip&16'hFFFF);
            s = s + ((cam_sip>>16)&16'hFFFF) + (cam_sip&16'hFFFF);
            for (i=0;i<seglen-1;i=i+2) s = s + ((capb[tcpoff+i]<<8) | capb[tcpoff+i+1]);
            if (seglen & 1) s = s + (capb[tcpoff+seglen-1]<<8);
            while (s >> 16) s = (s & 16'hFFFF) + (s >> 16);
            chk(s[15:0] === 16'hFFFF, "TCP checksum valid (pseudo-header src = connection IP)");
            chk(capb[tcpoff+13] === e_flags, "TCP flags as expected");
            last_checked = fi + 1;
        end
    endtask

    // ---------------- 驱动任务 ----------------
    task send_data;
        input [31:0] dip; input port; input integer nbytes; input [7:0] b0;
        integer i, nbeat, rem;
        begin
            cam_dip = dip; cam_port = port;
            nbeat = (nbytes + 7) / 8;
            for (i=0;i<nbeat;i=i+1) begin
                @(negedge clk);
                s_tdata = 0; s_tkeep = 0;
                if (i < nbeat-1) begin
                    s_tkeep = 8'hFF;
                    s_tdata[63:56]=b0+i*8; s_tdata[55:48]=b0+i*8+1;
                    s_tdata[47:40]=b0+i*8+2; s_tdata[39:32]=b0+i*8+3;
                    s_tdata[31:24]=b0+i*8+4; s_tdata[23:16]=b0+i*8+5;
                    s_tdata[15:8]=b0+i*8+6;  s_tdata[7:0]=b0+i*8+7;
                end else begin
                    rem = nbytes - i*8;
                    s_tkeep = 8'hFF << (8-rem);
                    case (rem)
                        1: s_tdata = {b0+i*8, 56'b0};
                        2: s_tdata = {b0+i*8, b0+i*8+1, 48'b0};
                        3: s_tdata = {b0+i*8, b0+i*8+1, b0+i*8+2, 40'b0};
                        4: s_tdata = {b0+i*8, b0+i*8+1, b0+i*8+2, b0+i*8+3, 32'b0};
                        default: s_tdata = 64'h0;
                    endcase
                end
                s_tlast = (i == nbeat-1);
                s_tvalid = 1'b1;
                while (!s_tready) @(negedge clk);
                @(posedge clk);
            end
            @(negedge clk);
            s_tvalid = 1'b0; s_tlast = 1'b0;
        end
    endtask

    task send_ctrl_synack;
        input [31:0] dip; input port;
        begin
            @(negedge clk);
            cam_dip = dip; cam_port = port;
            ack_req = 1'b1; ack_syn = 1'b1; ack_id = 4'd0; ack_val = 32'd0;
            @(posedge clk);
            @(negedge clk);
            ack_req = 1'b0; ack_syn = 1'b0;
        end
    endtask

    integer i;

    initial begin
        $display("==== TB_TCP_TX_SRCIP (OVL=%0d) ====",
`ifdef TCP_TX_OVL 1
`else 0
`endif
        );
        rst_n = 1'b0; repeat(5) @(posedge clk); rst_n = 1'b1; repeat(3) @(posedge clk);

        // ---- Arm 1: data frame, IP_B ----
        send_data(32'hC0A8_6404, 1'b1, 6, 8'hA0);
        wait_frames(cap_n+1);
        check_frame(cap_n-1, 32'hC0A8_6404, 8'h18, "data-IPB");
        // o_port stability while stalled: 观察是组合锁存的, 这里只查值
        chk(o_port === 1'b1, "o_port = 1 for IP_B data frame");

        // ---- Arm 2: data frame, IP_A (port 0) ----
        send_data(32'hC0A8_6402, 1'b0, 4, 8'h10);
        wait_frames(cap_n+1);
        check_frame(cap_n-1, 32'hC0A8_6402, 8'h18, "data-IPA");
        chk(o_port === 1'b0, "o_port = 0 for IP_A data frame");

        // ---- Arm 3 (N-6): 上一帧 IP_A 已锁存 lip; 当前控制帧 IP_B ----
        send_ctrl_synack(32'hC0A8_6404, 1'b1);
        wait_frames(cap_n+1);
        check_frame(cap_n-1, 32'hC0A8_6404, 8'h12, "synack-IPB-after-IPA");
        chk(o_port === 1'b1, "o_port = 1 for IP_B SYN-ACK");
        chk(stat_ack >= 1, "stat_ack incremented");

        // ---- Arm 4: 纯 ACK 控制帧 IP_A ----
        send_ctrl_synack(32'hC0A8_6402, 1'b0);
        wait_frames(cap_n+1);
        check_frame(cap_n-1, 32'hC0A8_6402, 8'h12, "synack-IPA");
        chk(o_port === 1'b0, "o_port = 0 for IP_A SYN-ACK");

        // ---- Arm 5: 重放帧 src IP (retx) ----
        cam_dip = 32'hC0A8_6404; cam_port = 1'b1;
        rb_snd_una_i = 32'h0000_2008;
        win_open_i = 1'b0;   // 阻止 app 数据帧; 只让 svc/ring 走
        begin : retx_arm
            integer rg;
            @(negedge clk);
            retx_req = 1'b1; retx_id = 4'd0;
            rg = 0;
            while (!retx_gnt && rg < 500) begin @(negedge clk); rg = rg + 1; end
            @(posedge clk);               // svc 拍: ring_hi 锁存 (snd_nxt 仍 = 0x2004)
            @(negedge clk);
            retx_req = 1'b0;
        end
        wait_frames(cap_n+1);
        if (cap_n > last_checked) begin
            check_frame(cap_n-1, 32'hC0A8_6404, 8'h18, "replay-IPB");
            chk(o_port === 1'b1, "o_port = 1 for IP_B replay frame");
        end else chk(0, "replay frame emitted");
        win_open_i = 1'b1;

        // ---- Arm 6: o_port 稳定性 (tvalid && !tready 期间不变) ----
        //   简化: 在下一数据帧发送期间随机拉低 m_tready, 每个 stall 拍比对 o_port。
        begin : stab
            reg seen_stall; reg [1:0] saved; integer g;
            seen_stall = 0; saved = o_port;
            fork
                send_data(32'hC0A8_6404, 1'b1, 16, 8'h40);
                begin
                    for (g=0; g<400; g=g+1) begin
                        @(posedge clk);
                        m_tready <= ((g % 5) != 0);
                        if (m_tvalid && !m_tready) begin
                            seen_stall = 1;
                            if (o_port !== 1'b1) begin
                                errs=errs+1; $display("  [FAIL] o_port changed during tvalid&&!tready");
                            end
                        end
                    end
                    m_tready <= 1'b1;
                end
            join
            chk(seen_stall, "M-12: observed at least one tvalid&&!tready stall (o_port stable)");
        end
        wait_frames(cap_n+1);
        if (cap_n > last_checked) check_frame(cap_n-1, 32'hC0A8_6404, 8'h18, "data-after-stall");

        $display("frames_captured=%0d ack=%0d stat_frames=%0d stat_ack=%0d", cap_n, stat_ack, stat_frames, stat_ack);
        if (errs == 0) $display("SRCIP TB PASS");
        else           $display("SRCIP TB FAIL errs=%0d", errs);
        $finish;
    end

    initial begin
        #2000000;
        $display("SRCIP TB FAIL (timeout)");
        $finish;
    end
endmodule
