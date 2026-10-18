`timescale 1ns/1ps
//=============================================================================
// tb_slow_tx_port.v — P11 P2-甲 G4: slow_tx_adp 端口提取 (独立门, 不进矩阵)
//=============================================================================
// 臂:
//   A. IPv4 src=IP_B ⇒ o_port=1; src=IP_A ⇒ 0
//   B. ARP SPA=IP_B ⇒ 1; SPA=IP_A ⇒ 0
//   C. 未识别 ethertype / 短帧 ⇒ 0 (安全口)
//   D. L-10 VLAN TPID 0x8100/0x88A8 ⇒ vlan_seen sticky ⇒ o_port=0 (即使内容像 IP_B)
//   E. 偏移负控: IP_B 字节放在 30..33 (错误偏移) ⇒ o_port=0
//   F. H-3 长阻塞: m_axis_tready=0, 提交 60 个 8 字最小帧 (480 字 < 512)
//      ⇒ side_level == committed 且 side_ovf == 0; 放行后逐帧 o_port 正确
//   G. SIDE_DEPTH=16 负控: 同一长阻塞 ⇒ side_ovf > 0 且 side_level != committed
//=============================================================================
module tb_slow_tx_port;
    reg clk = 1'b0, rst_n = 1'b0;
    always #3.2 clk = ~clk;
    integer errs = 0;
    task chk; input cond; input [8*110-1:0] msg;
        begin if (!cond) begin errs=errs+1; $display("  [FAIL] %0s", msg); end
              else $display("  [ ok ] %0s", msg); end endtask

    // ---------------- 主 DUT (SIDE_DEPTH=128) ----------------
    reg  [15:0] h_td=0; reg h_tv=0; wire h_tr;
    reg         phase_g = 1'b0;      // 0 = 主 DUT 收流; 1 = u_small 收流
    wire [15:0] h_td_m = phase_g ? 16'd0 : h_td;
    wire        h_tv_m = phase_g ? 1'b0  : h_tv;
    wire [15:0] h_td_s = phase_g ? h_td : 16'd0;
    wire        h_tv_s = phase_g ? h_tv : 1'b0;
    wire [63:0] m_td, m_td_s; wire [7:0] m_tk, m_tk_s;
    wire m_tv, m_tv_s; reg m_tr=1'b1; reg m_tr_s=1'b1;
    wire m_tl, m_tl_s;
    wire o_port, o_port_s;
    wire [31:0] sf, sp, sfo, sfo_s;
    wire [7:0]  lvl, lvl_s;
    wire        h_tr_s;
    wire [31:0] sfo_s_unused;
    integer frames_out=0;
    integer out_port_hist[0:255];
    integer nhist=0;

    slow_tx_adp #(.PER_PORT(1'b1), .IP_B(32'hC0A8_6404), .SIDE_DEPTH(128)) u_dut (
        .clk(clk), .rst_n(rst_n),
        .hls_tx_tdata(h_td_m), .hls_tx_tvalid(h_tv_m), .hls_tx_tready(h_tr),
        .m_axis_tdata(m_td), .m_axis_tkeep(m_tk), .m_axis_tvalid(m_tv),
        .m_axis_tready(m_tr), .m_axis_tlast(m_tl),
        .stat_frames(sf), .stat_purge(sp), .stat_fifo_ovf(sfo),
        .o_port(o_port), .stat_side_ovf(sfo_s), .side_level(lvl)
    );
    // 第二个 DUT (SIDE_DEPTH=16, G 臂)
    slow_tx_adp #(.PER_PORT(1'b1), .IP_B(32'hC0A8_6404), .SIDE_DEPTH(16)) u_small (
        .clk(clk), .rst_n(rst_n),
        .hls_tx_tdata(h_td_s), .hls_tx_tvalid(h_tv_s), .hls_tx_tready(h_tr_s),
        .m_axis_tdata(m_td_s), .m_axis_tkeep(m_tk_s), .m_axis_tvalid(m_tv_s),
        .m_axis_tready(m_tr_s), .m_axis_tlast(m_tl_s),
        .stat_frames(), .stat_purge(), .stat_fifo_ovf(),
        .o_port(o_port_s), .stat_side_ovf(sfo_s_unused), .side_level(lvl_s)
    );

    // 输出侧记录每帧 o_port (帧首拍)
    always @(posedge clk) begin
        if (m_tv && m_tr && m_tl) begin
            frames_out <= frames_out + 1;
            out_port_hist[nhist] <= o_port;
            nhist <= nhist + 1;
        end
    end

    // ---------------- HLS 流驱动 ----------------
    // 帧 = 8B preamble + content + 4B FCS; content 至少 60B (HLS 最小帧)
    reg [7:0] fb [0:255];
    integer flen;
    task build_frame; input integer kind;
        integer i;
        begin
            for (i=0;i<8;i=i+1) fb[i] = (i<7) ? 8'h55 : 8'hD5;
            // content: 默认全 0, len 60
            for (i=8;i<8+64;i=i+1) fb[i] = 8'h00;
            // dst/src MAC
            for (i=0;i<6;i=i+1) begin fb[8+i]=8'h00; fb[14+i]=8'h10+i; end
            fb[8+6]=8'h0A; fb[8+7]=8'h35; fb[8+8]=8'h01; fb[8+9]=8'hFE; fb[8+10]=8'hC0;
            case (kind)
                0: begin fb[8+12]=8'h08; fb[8+13]=8'h00;       // IPv4
                          fb[8+26]=192; fb[8+27]=168; fb[8+28]=100; fb[8+29]=2; end
                1: begin fb[8+12]=8'h08; fb[8+13]=8'h00;
                          fb[8+26]=192; fb[8+27]=168; fb[8+28]=100; fb[8+29]=4; end
                2: begin fb[8+12]=8'h08; fb[8+13]=8'h06;       // ARP, SPA @ 28..31
                          fb[8+28]=192; fb[8+29]=168; fb[8+30]=100; fb[8+31]=4; end
                3: begin fb[8+12]=8'h08; fb[8+13]=8'h06;
                          fb[8+28]=192; fb[8+29]=168; fb[8+30]=100; fb[8+31]=2; end
                4: begin fb[8+12]=8'h12; fb[8+13]=8'h34; end   // unknown ethertype
                5: begin fb[8+12]=8'h81; fb[8+13]=8'h00;       // VLAN TPID
                          fb[8+26]=192; fb[8+27]=168; fb[8+28]=100; fb[8+29]=4; end
                6: begin fb[8+12]=8'h08; fb[8+13]=8'h00;       // wrong offset: IP_B @ 30..33
                          fb[8+30]=192; fb[8+31]=168; fb[8+32]=100; fb[8+33]=4; end
                default: ;
            endcase
            flen = 8 + 60 + 4;
        end
    endtask
    task feed_frame; input integer kind;
        integer i;
        begin
            build_frame(kind);
            for (i=0;i<flen;i=i+1) begin
                h_td = {7'b0, (i==flen-1), fb[i]}; h_tv = 1'b1;
                @(posedge clk);
                while (!(phase_g ? h_tr_s : h_tr)) @(posedge clk);
            end
            h_tv = 1'b0;
            // 等这一帧从播放器出来
        end
    endtask
    task wait_frames; input integer n; integer g;
        begin g=0; while (frames_out < n && g < 4000) begin @(posedge clk); g=g+1; end end
    endtask
    task feed_to; input integer kind; input integer n; integer i;
        begin for (i=0;i<n;i=i+1) feed_frame(kind); end
    endtask

    integer i;
    initial begin
        $display("==== TB_SLOW_TX_PORT ====");
        rst_n=0; repeat(3) @(posedge clk); rst_n=1; repeat(3) @(posedge clk);

        // ---- A..E: 单帧端口判定 ----
        // 注意: u_small 也在监听 h_td/h_tv; 它的 h_tr_s 未接 (悬空) —— 为避免双驱动,
        // 这里只把主 DUT 的 h_tr 接回; u_small 的 hls_tx_tready 悬空 = 它不消费,
        // 不影响主 DUT。G 臂时单独喂 (见下)。
        begin : single
            integer kinds [0:6];
            integer k;
            kinds[0]=0; kinds[1]=1; kinds[2]=2; kinds[3]=3; kinds[4]=4; kinds[5]=5; kinds[6]=6;
            for (k=0;k<7;k=k+1) begin
                feed_frame(kinds[k]);
                wait_frames(frames_out+1);
                chk(nhist >= 1, "frame delivered");
                chk(out_port_hist[nhist-1] === ((kinds[k]==1 || kinds[k]==2) ? 1 : 0),
                    "port decode matches expected for kind");
            end
        end

        // ---- F: 长阻塞 + 60 最小帧 ----
        m_tr = 1'b0;
        for (i=0;i<60;i=i+1) feed_frame(i%2);   // 交替 IP_A/IP_B (8 字内容)
        repeat(200) @(posedge clk);
        chk(u_dut.side_level == u_dut.committed, "F: side_level == committed under long block");
        chk(u_dut.stat_side_ovf == 0, "F: side FIFO overflow == 0 (depth 128)");
        m_tr = 1'b1;
        wait_frames(frames_out+60);
        begin : verify
            integer k, base;
            base = nhist - 60;
            for (k=0;k<60;k=k+1)
                if (out_port_hist[base+k] !== (k%2)) begin
                    errs=errs+1; $display("  [FAIL] F: frame %0d port=%0d exp=%0d", k, out_port_hist[base+k], k%2);
                end
            chk(1, "F: 60 blocked frames released with correct per-frame o_port");
        end

        // ---- G: SIDE_DEPTH=16 负控 ----
        //   主 DUT 已被 F 用满; 用 u_small 单跑同一形态 (它没被前面的单帧喂过).
        //   注意 u_small 与 u_dut 共享 h_td/h_tv; 上面 F 期间 u_small 也看到了同样的
        //   字节 (其 hls_tx_tready 悬空 ⇒ 它按自己的 FIFO 满丢弃, 不消费主 DUT 流).
        //   这里重新复位, 只喂 u_small: 通过 m_tr_s=0 阻塞它, 主 DUT 的 m_tr=0 也保持.
        rst_n = 1'b0; phase_g = 1'b1; repeat(3) @(posedge clk); rst_n = 1'b1; repeat(3) @(posedge clk);
        frames_out = 0; nhist = 0; m_tr = 1'b0; m_tr_s = 1'b0;
        for (i=0;i<60;i=i+1) feed_frame(i%2);
        repeat(200) @(posedge clk);
        chk(u_small.stat_side_ovf > 0, "G: SIDE_DEPTH=16 overflow > 0 (negative control armed)");
        chk(u_small.side_level != u_small.committed, "G: side_level != committed (invariant violated as expected)");
        m_tr = 1'b1; m_tr_s = 1'b1;

        if (errs==0) $display("SLOW_TX_PORT TB PASS");
        else         $display("SLOW_TX_PORT TB FAIL errs=%0d", errs);
        $finish;
    end
    initial begin #4000000; $display("SLOW_TX_PORT TB FAIL (timeout)"); $finish; end
endmodule
