`timescale 1ns/1ps
//=============================================================================
// tb_tx_split.v — P11 P2-甲 G3: tx_demux2 + 每口 arb 单元门 (独立门, 不进矩阵)
//=============================================================================
// 臂:
//   A. 端口分离: 生产者的 s_port 0/1 帧只出现在对应口
//   B. 帧原子性: 帧内 s_port 翻转 ⇒ 整帧只走帧首锁存口; stat_port_change > 0
//   C. 口内优先级 (镜像 wrapper 两级 arb): TCP > UDP > HLS
//   D. 接线反转变异 (F-12): **第二份 tx_demux2 实例**把 d0/d1 输出交叉接到检查器
//      (同一激励): 正常件的判据 "port-0 帧只在 d0" 在变异件上必红 ⇒ 真变异证据
//=============================================================================
module tb_tx_split;
    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;
    integer errs = 0;
    task chk; input cond; input [8*100-1:0] msg;
        begin if (!cond) begin errs=errs+1; $display("  [FAIL] %0s", msg); end
              else $display("  [ ok ] %0s", msg); end endtask

    function [15:0] popc8; input [7:0] v; integer i;
        begin popc8=0; for(i=0;i<8;i=i+1) if(v[i]) popc8=popc8+1; end endfunction

    // ---------------- 生产者 ----------------
    reg [63:0] s_tdata=0; reg [7:0] s_tkeep=0; reg s_tvalid=0, s_tlast=0, s_port=0;
    wire s_tready;
    wire [63:0] d0_tdata, d1_tdata; wire [7:0] d0_tkeep, d1_tkeep;
    wire d0_tvalid, d1_tvalid, d0_tlast, d1_tlast;
    reg  d0_tready=1'b1, d1_tready=1'b1;
    wire [31:0] stat_pc, stat_f0, stat_f1;

    tx_demux2 u_demux (
        .clk(clk), .rst_n(rst_n),
        .s_tdata(s_tdata), .s_tkeep(s_tkeep), .s_tvalid(s_tvalid),
        .s_tready(s_tready), .s_tlast(s_tlast), .s_port(s_port),
        .d0_tdata(d0_tdata), .d0_tkeep(d0_tkeep), .d0_tvalid(d0_tvalid),
        .d0_tready(d0_tready), .d0_tlast(d0_tlast),
        .d1_tdata(d1_tdata), .d1_tkeep(d1_tkeep), .d1_tvalid(d1_tvalid),
        .d1_tready(d1_tready), .d1_tlast(d1_tlast),
        .stat_port_change(stat_pc), .stat_frames0(stat_f0), .stat_frames1(stat_f1)
    );

    // ---------------- D: 交叉接线的变异件 (同一激励, 第二份 demux) ----------------
    //   d0 输出端口接到检查器的 i1_*, d1 输出端口接到 i0_* ⇒ 端口反接。
    wire [63:0] i0_tdata, i1_tdata; wire [7:0] i0_tkeep, i1_tkeep;
    wire i0_tvalid, i1_tvalid, i0_tlast, i1_tlast;
    reg  i0_tready = 1'b1, i1_tready = 1'b1;
    tx_demux2 u_demux_inv (
        .clk(clk), .rst_n(rst_n),
        .s_tdata(s_tdata), .s_tkeep(s_tkeep), .s_tvalid(s_tvalid),
        .s_tready(), .s_tlast(s_tlast), .s_port(s_port),
        // ⚠️ 交叉: dut.d0 -> 检查器 i1_*; dut.d1 -> 检查器 i0_*
        .d0_tdata(i1_tdata), .d0_tkeep(i1_tkeep), .d0_tvalid(i1_tvalid),
        .d0_tready(i1_tready), .d0_tlast(i1_tlast),
        .d1_tdata(i0_tdata), .d1_tkeep(i0_tkeep), .d1_tvalid(i0_tvalid),
        .d1_tready(i0_tready), .d1_tlast(i0_tlast),
        .stat_port_change(), .stat_frames0(), .stat_frames1()
    );

    // 输出观察: 每拍记录 d0/d1 上的 beat (tag = 端口)
    integer n0=0, n1=0, n0i=0, n1i=0;
    integer seq0[0:63], seq1[0:63];
    reg [63:0] word0[0:63], word1[0:63];
    always @(posedge clk) begin
        if (d0_tvalid && d0_tready) begin word0[n0]=d0_tdata; seq0[n0]=d0_tdata[31:0]; n0<=n0+1; end
        if (d1_tvalid && d1_tready) begin word1[n1]=d1_tdata; seq1[n1]=d1_tdata[31:0]; n1<=n1+1; end
        if (i0_tvalid && i0_tready) n0i <= n0i+1;
        if (i1_tvalid && i1_tready) n1i <= n1i+1;
    end

    task send_frame; input integer port; input integer len; input integer tag; input flip;
        integer i;
        begin
            // 坑 3/17: 激励一律在 negedge 驱动, 规避与 DUT 同时钟沿的竞争
            for (i=0;i<len;i=i+1) begin
                @(negedge clk);
                s_tdata = {tag[7:0], 24'h0, i[31:0]};
                s_tkeep = 8'hFF; s_tlast = (i==len-1); s_tvalid = 1'b1;
                if (i==0) s_port = port[0];
                if (i==2 && flip) s_port = ~port[0];   // 帧中途翻转
                while (!s_tready) @(negedge clk);
                @(posedge clk);
            end
            @(negedge clk);
            s_tvalid=0; s_tlast=0;
        end
    endtask

    // ---------------- 两级 arb (镜像 wrapper) ----------------
    // prod A (TCP) / prod B (UDP) / prod C (HLS)
    reg [63:0] a_td=0,b_td=0,c_td=0; reg [7:0] a_tk=0,b_tk=0,c_tk=0;
    reg a_tv=0,b_tv=0,c_tv=0; reg a_tl=0,b_tl=0,c_tl=0;
    wire a_tr,b_tr,c_tr;
    wire [63:0] u_mrg_d, f_d; wire [7:0] u_mrg_k, f_k;
    wire u_mrg_v, u_mrg_r, u_mrg_l, f_v, f_r, f_l;
    tx_arb u_udp_arb (
        .clk(clk), .rst_n(rst_n),
        .s_fast_tdata(b_td), .s_fast_tkeep(b_tk), .s_fast_tvalid(b_tv),
        .s_fast_tready(b_tr), .s_fast_tlast(b_tl),
        .s_slow_tdata(c_td), .s_slow_tkeep(c_tk), .s_slow_tvalid(c_tv),
        .s_slow_tready(c_tr), .s_slow_tlast(c_tl),
        .m_axis_tdata(u_mrg_d), .m_axis_tkeep(u_mrg_k), .m_axis_tvalid(u_mrg_v),
        .m_axis_tready(u_mrg_r), .m_axis_tlast(u_mrg_l)
    );
    tx_arb u_final (
        .clk(clk), .rst_n(rst_n),
        .s_fast_tdata(a_td), .s_fast_tkeep(a_tk), .s_fast_tvalid(a_tv),
        .s_fast_tready(a_tr), .s_fast_tlast(a_tl),
        .s_slow_tdata(u_mrg_d), .s_slow_tkeep(u_mrg_k), .s_slow_tvalid(u_mrg_v),
        .s_slow_tready(u_mrg_r), .s_slow_tlast(u_mrg_l),
        .m_axis_tdata(f_d), .m_axis_tkeep(f_k), .m_axis_tvalid(f_v),
        .m_axis_tready(f_r), .m_axis_tlast(f_l)
    );
    reg f_ready = 1'b1;
    assign f_r = f_ready;
    integer prio[0:15], nprio=0;
    always @(posedge clk) if (f_v && f_r) begin
        prio[nprio] <= f_d[63:56];   // tag 高字节 = 生产者 id (1=A,2=B,3=C)
        nprio <= nprio+1;
    end

    always @(posedge clk) begin
        if (a_tv && a_tr) a_tv <= 1'b0;
        if (b_tv && b_tr) b_tv <= 1'b0;
        if (c_tv && c_tr) c_tv <= 1'b0;
    end

    integer i;
    initial begin
        $display("==== TB_TX_SPLIT ====");
        rst_n=0; repeat(3) @(posedge clk); rst_n=1; repeat(2) @(posedge clk);

        // ---- A: 端口分离 ----
        send_frame(0,4,1,0);
        send_frame(1,4,2,0);
        send_frame(0,4,3,0);
        @(posedge clk);
        chk(n0==8 && n1==4, "A: 2 frames on port0, 1 frame on port1");
        chk(word0[0][31:0]==0 && word0[1][31:0]==1 && word0[2][31:0]==2 && word0[3][31:0]==3,
            "A: port0 frame1 beats in order");
        chk(word1[0][31:0]==0 && word1[3][31:0]==3, "A: port1 frame beats in order");
        chk(stat_f0==2 && stat_f1==1, "A: stat_frames0=2 stat_frames1=1");
        chk(d1_tdata[63:56]==8'd2 || word1[0][63:56]==8'd2, "A: port1 frame carries the port-1 tag");

        // ---- B: 帧原子性 (帧内 s_port 翻转) ----
        n0=0; n1=0;
        send_frame(0,4,7,1);   // 帧首 0, 第 3 beat 翻成 1
        @(posedge clk);
        chk(n0==4 && n1==0, "B: whole frame stays on latched port 0 (no split)");
        chk(stat_pc > 0, "B: stat_port_change caught the mid-frame flip");

        // ---- C: 口内优先级 TCP > UDP > HLS ----
        nprio=0;
        // 同时呈三帧: A(tag 1) fast, B(tag 2) mid, C(tag 3) low
        a_td={8'h01,56'h0}; a_tk=8'hFF; a_tl=1; b_td={8'h02,56'h0}; b_tk=8'hFF; b_tl=1;
        c_td={8'h03,56'h0}; c_tk=8'hFF; c_tl=1;
        a_tv=1;b_tv=1;c_tv=1;
        // 等三帧都完成 (单拍帧)
        begin : waitc integer g; g=0; while (nprio<3 && g<100) begin @(posedge clk); g=g+1; end end
        a_tv=0;b_tv=0;c_tv=0;
        chk(nprio>=3 && prio[0]==1 && prio[1]==2 && prio[2]==3,
            "C: per-port priority TCP(A) > UDP(B) > HLS(C)");

        // ---- D: 接线反转变异 (F-12): 第二份 demux 把 d0/d1 交叉接线 ----
        begin : mut
            n0=0; n1=0; n0i=0; n1i=0;
            send_frame(0,4,9,0);
            @(posedge clk);
            chk(n0==4 && n1==0, "D: normal wiring: port-0 frame only on d0 (4 beats)");
            // 同一判据施加到交叉接线件: 端口 0 的 4 拍应落在检查器的 i1 线上
            // ⇒ "i0==4 && i1==0" 必不成立。若成立 = 变异没打中/接线没反。
            chk(!(n0i==4 && n1i==0),
                "D-mut: crossed d0/d1 wiring makes the same criterion RED (real mutation)");
            chk(n1i==4 && n0i==0, "D-mut: the inverted instance really put the port-0 frame on i1");
        end

        if (errs==0) $display("TX_SPLIT TB PASS");
        else         $display("TX_SPLIT TB FAIL errs=%0d", errs);
        $finish;
    end
    initial begin #2000000; $display("TX_SPLIT TB FAIL (timeout)"); $finish; end
endmodule
