`timescale 1ns/1ps
//=============================================================================
// tb_p11_dual.v — P11 P2-甲 G6: 真 wrapper + DUAL 双口全链门
//=============================================================================
// 配置: P7B_10G + P7B_SIM_NOPCS + PCIE_OBS + DEV_USP + APP_MODE + DP_156MHZ
//       + P6B_SIM_CLKGEN + UDP_TX_OVL + TCP_TX_OVL + **DUAL_SFP_A**
//
// 臂:
//   A. HLS 真实握手 (现役 HLS 网表是 **P11 前**的单 IP 版 ⇒ 只对 IP_A 有判别力):
//      ch1(J8) 注入 SYN -> IP_A ⇒ SYN-ACK 只出现在 ch1 TX; ch0 TX 无该帧。
//      ⛔ IP_B 的 HLS 握手需双 IP 重综合网表 ⇒ **登记到构建轮** (见报告)。
//   B. force 快臂 (三个 demux 输入, 不 force txsrc): tx_/utx2_/stx_ 各一帧带
//      端口位 ⇒ 只出现在对应 TX 通道; W83/W84 计数器各自 +1。
//   C. maccnt_sync: 源域 +1 -> 目的域 +1; 常值不重复增加;
//      裸 2FF 变异件必须出现"混合值" (负控有牙)。
//=============================================================================
module tb_p11_dual;

    reg reset_n = 1'b0;
    reg gt_refclk_p = 0, gt_refclk_n = 1;
    always #3.2 gt_refclk_p = ~gt_refclk_p;
    always #3.2 gt_refclk_n = ~gt_refclk_n;
    reg sys_clk_p = 0, sys_clk_n = 1;
    always #5.0 sys_clk_p = ~sys_clk_p;
    always #5.0 sys_clk_n = ~sys_clk_n;
    reg pcie_clk_p = 0, pcie_clk_n = 1;
    always #5.0 pcie_clk_p = ~pcie_clk_p;
    always #5.0 pcie_clk_n = ~pcie_clk_n;

    wire led_d0, led_d1, led_d2, led_d3, uart_txd;
    wire sfp1_txp, sfp1_txn, sfp2_txp, sfp2_txn, sfp1_tx_dis, sfp2_tx_dis;

    wrapper_p4 u_dut (
        .reset_n(reset_n),
        .led_d0(led_d0), .led_d1(led_d1), .led_d2(led_d2), .led_d3(led_d3),
        .uart_txd(uart_txd),
        .gt_refclk_p(gt_refclk_p), .gt_refclk_n(gt_refclk_n),
        .sfp1_rxp(1'b0), .sfp1_rxn(1'b1),
        .sfp1_txp(sfp1_txp), .sfp1_txn(sfp1_txn),
        .sfp2_rxp(1'b0), .sfp2_rxn(1'b1),
        .sfp2_txp(sfp2_txp), .sfp2_txn(sfp2_txn),
        .sfp1_rx_los(1'b0), .sfp1_tx_dis(sfp1_tx_dis),
        .sfp2_rx_los(1'b0), .sfp2_tx_dis(sfp2_tx_dis),
        .pcie_sys_clk_p(pcie_clk_p), .pcie_sys_clk_n(pcie_clk_n),
        .pcie_txp(), .pcie_txn(),
        .pcie_rxp(4'b0), .pcie_rxn(4'b1),
        .sys_clk_p(sys_clk_p), .sys_clk_n(sys_clk_n)
    );

    integer errs = 0;
    task chk; input cond; input [8*110-1:0] msg;
        begin if (!cond) begin errs=errs+1; $display("  [FAIL] %0s", msg); end
              else $display("  [ ok ] %0s", msg); end endtask

    // ---------------- RX 注入队列 (lane0 = 首字节) ----------------
    reg [63:0] q1_d [0:16383]; reg [7:0] q1_c [0:16383];
    integer q1_wr=0, q1_rd=0;
    wire q1_empty = (q1_rd==q1_wr);
    always @(posedge u_dut.rx_clk_out_1) begin
        if (!q1_empty) q1_rd <= q1_rd+1;
        u_dut.u_pcs.inj_d1 <= q1_empty ? 64'h0707070707070707 : q1_d[q1_rd];
        u_dut.u_pcs.inj_c1 <= q1_empty ? 8'hFF : q1_c[q1_rd];
    end
    reg [63:0] q0_d [0:16383]; reg [7:0] q0_c [0:16383];
    integer q0_wr=0, q0_rd=0;
    wire q0_empty = (q0_rd==q0_wr);
    always @(posedge u_dut.rx_clk_out_0) begin
        if (!q0_empty) q0_rd <= q0_rd+1;
        u_dut.u_pcs.inj_d0 <= q0_empty ? 64'h0707070707070707 : q0_d[q0_rd];
        u_dut.u_pcs.inj_c0 <= q0_empty ? 8'hFF : q0_c[q0_rd];
    end

    reg [7:0] fb [0:2047];
    integer flen;
    integer dip = 32'hC0A86402;

    task pack_into;   // 把 fb[0..n) 按 lane0=首字节打包进指定队列 (sh=0)
        input integer n; input integer which;
        integer i,k; reg [63:0] d; reg [7:0] c;
        begin
            i=0;
            while (i<n) begin
                d=64'd0; c=8'd0;
                for (k=0;k<8;k=k+1) begin
                    if (i+k<n) begin d[k*8 +: 8]=fb[i+k]; c[k]=1'b0; end
                    else       begin d[k*8 +: 8]=8'h07;   c[k]=1'b1; end
                end
                if (which==1) begin q1_d[q1_wr]=d; q1_c[q1_wr]=c; q1_wr=q1_wr+1; end
                else          begin q0_d[q0_wr]=d; q0_c[q0_wr]=c; q0_wr=q0_wr+1; end
                i=i+8;
            end
        end
    endtask

    // CRC32 (per-byte, reflected 0xEDB88320) — 与 tb_p7b_chain 同款
    function [31:0] crc32_byte;
        input [31:0] crc;
        input [7:0]  b;
        integer i;
        reg [31:0] x;
        begin
            x = crc ^ {24'h0, b};
            for (i=0;i<8;i=i+1)
                x = (x[0]) ? ((x >> 1) ^ 32'hEDB88320) : (x >> 1);
            crc32_byte = x;
        end
    endfunction

    reg [7:0] xb [0:2047];
    reg       xc [0:2047];
    integer   xn = 0;
    reg [31:0] fcs_calc;

    task pack_xgmii_into;   // 把 xb/xc[0..xn) 按 lane0=首字节打包进队列
        input integer which;
        integer i,k; reg [63:0] d; reg [7:0] c;
        begin
            i=0;
            while (i<xn) begin
                d=64'd0; c=8'd0;
                for (k=0;k<8;k=k+1) begin
                    if (i+k<xn) begin d[k*8 +: 8]=xb[i+k]; c[k]=xc[i+k]; end
                    else        begin d[k*8 +: 8]=8'h07;   c[k]=1'b1; end
                end
                if (which==1) begin q1_d[q1_wr]=d; q1_c[q1_wr]=c; q1_wr=q1_wr+1; end
                else          begin q0_d[q0_wr]=d; q0_c[q0_wr]=c; q0_wr=q0_wr+1; end
                i=i+8;
            end
        end
    endtask

    task build_syn;   // SYN: .101:23456 -> dip:8080; 产完整 XGMII 序列 xb/xc
        integer i, j;
        reg [31:0] s;
        begin
            for (i=0;i<60;i=i+1) fb[i]=8'h00;
            for (i=0;i<6;i=i+1) fb[i]=8'hFF;             // dst broadcast
            fb[6]=8'h10;fb[7]=8'h11;fb[8]=8'h12;fb[9]=8'h13;fb[10]=8'h14;fb[11]=8'h15;
            fb[12]=8'h08;fb[13]=8'h00;
            fb[14]=8'h45;fb[15]=0; fb[16]=0; fb[17]=40;  // total len 40
            fb[18]=0; fb[19]=1; fb[20]=8'h40; fb[21]=0;
            fb[22]=64; fb[23]=6; fb[24]=0; fb[25]=0;
            fb[26]=192;fb[27]=168;fb[28]=100;fb[29]=101;
            fb[30]=(dip>>24)&255;fb[31]=(dip>>16)&255;fb[32]=(dip>>8)&255;fb[33]=dip&255;
            // IP checksum
            begin : ipc
                integer k;
                s=0; for (k=0;k<10;k=k+1) s=s+((fb[14+k*2]<<8)|fb[14+k*2+1]);
                while (s>>16) s=(s&16'hFFFF)+(s>>16);
                s=~s; fb[24]=(s>>8)&255; fb[25]=s&255;
            end
            fb[34]=8'h5B;fb[35]=8'hE0; fb[36]=8'h1F;fb[37]=8'h90; // sport 23456 -> 8080
            fb[38]=0;fb[39]=0;fb[40]=0;fb[41]=0;              // seq
            fb[42]=0;fb[43]=0;fb[44]=0;fb[45]=0;              // ack
            fb[46]=8'h50;fb[47]=8'h02;fb[48]=8'h20;fb[49]=0;     // SYN
            fb[50]=0;fb[51]=0;fb[52]=0;fb[53]=0;              // csum (下面算)
            // TCP checksum (pseudo-header): 源 IP .101 -> dip, proto 6, len 20
            s = (192<<8 | 168) + (100<<8 | 101);
            s = s + (dip>>16) + (dip & 16'hFFFF) + 6 + 20;
            for (j=0;j<10;j=j+1) s=s+((fb[34+j*2]<<8)|fb[34+j*2+1]);
            while (s>>16) s=(s&16'hFFFF)+(s>>16);
            s=~s; fb[50]=(s>>8)&255; fb[51]=s&255;
            flen=54;
            // ---- XGMII 序列: /S/ + preamble + content + FCS + /T/ ----
            fcs_calc = 32'hFFFFFFFF;
            for (i=0;i<flen;i=i+1) fcs_calc = crc32_byte(fcs_calc, fb[i]);
            fcs_calc = ~fcs_calc;
            xn = 0;
            xb[0]=8'hFB; xc[0]=1'b1; xn=1;                   // /S/
            for (i=0;i<6;i=i+1) begin xb[xn]=8'h55; xc[xn]=1'b0; xn=xn+1; end
            xb[xn]=8'hD5; xc[xn]=1'b0; xn=xn+1;
            for (i=0;i<flen;i=i+1) begin xb[xn]=fb[i]; xc[xn]=1'b0; xn=xn+1; end
            xb[xn]=fcs_calc[7:0];   xc[xn]=1'b0; xn=xn+1;
            xb[xn]=fcs_calc[15:8];  xc[xn]=1'b0; xn=xn+1;
            xb[xn]=fcs_calc[23:16]; xc[xn]=1'b0; xn=xn+1;
            xb[xn]=fcs_calc[31:24]; xc[xn]=1'b0; xn=xn+1;
            xb[xn]=8'hFD; xc[xn]=1'b1; xn=xn+1;              // /T/
        end
    endtask

    // ---------------- TX 捕获 (逐通道字节流 + 帧间 gap 标记) ----------------
    reg [7:0] cap1 [0:8191]; integer cap1_n=0; integer cap1_gap=0;
    reg [7:0] cap0 [0:8191]; integer cap0_n=0; integer cap0_gap=0;
    always @(posedge u_dut.u_pcs.tx_clk) begin : cap
        integer l, any;
        any=0;
        for (l=0;l<8;l=l+1) begin
            if (u_dut.u_pcs.txcap_c1[l]===1'b0) begin
                if (cap1_n<8191) cap1[cap1_n] = u_dut.u_pcs.txcap_d1[l*8 +: 8];
                cap1_n = cap1_n + 1; any=1;
            end
        end
        if (!any) begin
            if (cap1_gap<64) cap1_gap=cap1_gap+1;
            if (cap1_gap==4) begin cap1[cap1_n] = 8'hEE; cap1_n=cap1_n+1; end // 帧界标记
        end else cap1_gap=0;
        any=0;
        for (l=0;l<8;l=l+1) begin
            if (u_dut.u_pcs.txcap_c0[l]===1'b0) begin
                if (cap0_n<8191) cap0[cap0_n] = u_dut.u_pcs.txcap_d0[l*8 +: 8];
                cap0_n = cap0_n + 1; any=1;
            end
        end
        if (!any) begin
            if (cap0_gap<64) cap0_gap=cap0_gap+1;
            if (cap0_gap==4) begin cap0[cap0_n] = 8'hEE; cap0_n=cap0_n+1; end
        end else cap0_gap=0;
    end

    // 在通道字节流里找 "src MAC 00 0A 35 01 FE C0 + ethertype + 可选 tag"
    function integer find_sig;
        input integer ch; input [15:0] etype; input [7:0] tag; input use_tag;
        integer i, n;
        begin
            find_sig = -1;
            n = (ch==1) ? cap1_n : cap0_n;
            for (i=6; i<n-20; i=i+1) begin
                if (((ch==1)?cap1[i]:cap0[i]) == 8'h00 &&
                    ((ch==1)?cap1[i+1]:cap0[i+1]) == 8'h0A &&
                    ((ch==1)?cap1[i+2]:cap0[i+2]) == 8'h35 &&
                    ((ch==1)?cap1[i+3]:cap0[i+3]) == 8'h01 &&
                    ((ch==1)?cap1[i+4]:cap0[i+4]) == 8'hFE &&
                    ((ch==1)?cap1[i+5]:cap0[i+5]) == 8'hC0) begin
                    if ((((ch==1)?cap1[i+6]:cap0[i+6]) == etype[15:8]) &&
                        (((ch==1)?cap1[i+7]:cap0[i+7]) == etype[7:0])) begin
                        if (!use_tag || (((ch==1)?cap1[i+8]:cap0[i+8]) == tag))
                            find_sig = i;
                    end
                end
            end
        end
    endfunction

    // ---------------- force 快臂: 驱动器 ----------------
    reg [63:0] f_d=0; reg [7:0] f_k=0; reg f_v=0, f_l=0, f_p=0;
    task force_frame; input integer which; input integer port; input [7:0] tag;
        integer i;
        begin
            for (i=0;i<4;i=i+1) begin
                @(negedge u_dut.dp_clk);
                // 帧: dst 00*6 | src 00 0A 35 01 FE C0 | ethertype 1234 | tag ...
                case (i)
                    0: f_d = {8'h00,8'h00,8'h00,8'h00,8'h00,8'h00, 8'h00,8'h0A};
                    1: f_d = {8'h35,8'h01,8'hFE,8'hC0, 8'h12,8'h34, tag, 8'h11};
                    2: f_d = {8'h22, 8'h33, 8'h44, 8'h55, 8'h66, 8'h77, 8'h88, 8'h99};
                    3: f_d = {8'hAA, 8'hBB, 8'hCC, 8'hDD, 8'hEE, 8'hFF, 8'h00, 8'h00};
                endcase
                f_k = 8'hFF; f_l = (i==3); f_v = 1'b1; f_p = port[0];
                case (which)
                    0: begin force u_dut.tx_tdata=f_d; force u_dut.tx_tkeep=f_k;
                             force u_dut.tx_tvalid=f_v; force u_dut.tx_tlast=f_l;
                             force u_dut.tx_port=f_p; end
                    1: begin force u_dut.utx2_tdata=f_d; force u_dut.utx2_tkeep=f_k;
                             force u_dut.utx2_tvalid=f_v; force u_dut.utx2_tlast=f_l;
                             force u_dut.utx_port=f_p; end
                    2: begin force u_dut.stx_tdata=f_d; force u_dut.stx_tkeep=f_k;
                             force u_dut.stx_tvalid=f_v; force u_dut.stx_tlast=f_l;
                             force u_dut.stx_port=f_p; end
                endcase
                // 遵守握手: 只在该拍 s_tready=1 时才前移 (在 negedge 采样, 避开竞争)
                case (which)
                    0: while (!u_dut.tx_tready)   @(negedge u_dut.dp_clk);
                    1: while (!u_dut.utx2_tready) @(negedge u_dut.dp_clk);
                    2: while (!u_dut.stx_tready)  @(negedge u_dut.dp_clk);
                endcase
                @(posedge u_dut.dp_clk);
            end
            @(negedge u_dut.dp_clk);
            f_v=0;
            case (which)
                0: begin release u_dut.tx_tdata; release u_dut.tx_tkeep;
                         release u_dut.tx_tvalid; release u_dut.tx_tlast; release u_dut.tx_port; end
                1: begin release u_dut.utx2_tdata; release u_dut.utx2_tkeep;
                         release u_dut.utx2_tvalid; release u_dut.utx2_tlast; release u_dut.utx_port; end
                2: begin release u_dut.stx_tdata; release u_dut.stx_tkeep;
                         release u_dut.stx_tvalid; release u_dut.stx_tlast; release u_dut.stx_port; end
            endcase
        end
    endtask

    // ---------------- C: maccnt_sync 活性/常值 + 2FF 变异 (F-3 改写) ----------------
    reg src_clk=0, dst_clk=0; always #5 src_clk=~src_clk; always #3.5 dst_clk=~dst_clk;
    reg [7:0] src_val=8'h00;
    wire [7:0] good_dst;
    reg [7:0] m1, m2;
    reg        mut_arm = 1'b0;       // 1 = 把 DUT 的 dst_val 换成常 0 (变异臂)
    wire [7:0] obs_val = mut_arm ? 8'h00 : good_dst;
    maccnt_sync #(.W(8)) u_mac (
        .src_clk(src_clk), .src_rst_n(reset_n), .src_val(src_val), .src_tick(1'b1),
        .dst_clk(dst_clk), .dst_rst_n(reset_n), .dst_val(good_dst)
    );
    always @(posedge dst_clk or negedge reset_n) begin
        if (!reset_n) begin m1<=0; m2<=0; end
        else begin m1<=src_val; m2<=m1; end
    end
    integer good_bad=0, mut_bad=0;
    always @(posedge dst_clk) begin
        if (reset_n) begin
            if (good_dst !== 8'h00 && good_dst !== 8'hFF) good_bad=good_bad+1;
            if (m2 !== 8'h00 && m2 !== 8'hFF) mut_bad=mut_bad+1;
        end
    end

    // F-3: 活性判据 (旧臂 C 只查"无混合值" ⇒ dst 恒 0/恒 0xFF 也能 PASS)
    //   wait_obs : 期望值必须在 ≤maxc 个**目的域**时钟内被 dst 精确追到
    //   hold_chk : 源域冻结后, dst 在 n 拍内**逐拍**保持同一值 (不重复增加)
    task wait_obs; input [7:0] v; input integer maxc; output ok;
        integer c;
        begin
            ok = 0;
            for (c=0; c<maxc; c=c+1) begin
                @(posedge dst_clk);
                if (obs_val === v) begin ok = 1; c = maxc; end
            end
        end
    endtask
    task hold_chk; input [7:0] v; input integer ncyc; output ok;
        integer c;
        begin
            ok = 1;
            for (c=0; c<ncyc; c=c+1) begin
                @(posedge dst_clk);
                if (obs_val !== v) ok = 0;
            end
        end
    endtask
    integer ramp_fail=0, hold_fail=0, mut_fail=0, cok=0;
    task ramp_track; input integer enable_mut; input [7:0] base; input integer nstep;
        integer v;
        begin
            mut_arm = (enable_mut != 0);
            for (v=0; v<nstep; v=v+1) begin
                @(negedge src_clk); src_val = base + v[7:0];
                wait_obs(base + v[7:0], 32, cok);
                if (!cok) begin
                    if (enable_mut) mut_fail = mut_fail + 1;
                    else            ramp_fail = ramp_fail + 1;
                    $display("  [info] ramp %s: expected %0d not seen", enable_mut ? "MUT" : "GOOD", base+v);
                end
            end
        end
    endtask

    integer i, g;
    initial begin
        $display("==== TB_P11_DUAL ====");
        reset_n = 1'b0; repeat(20) @(posedge u_dut.dp_clk); reset_n = 1'b1;
        repeat(50) @(posedge u_dut.dp_clk);

        // ---------- C: maccnt_sync (F-3: 活性 + 常值 + 强制常 0 变异) ----------
        fork
            begin
                for (i=0;i<400;i=i+1) begin
                    @(posedge src_clk);
                    // 逐位错开 0.05 ns: 多比特同步器在目的域采样时能看到"混合值"
                    // (物理上 = 各 bit 到达时间不同; 同步改动则本负控无牙)
                    #0.4;
                    src_val[0]=(i%2); #0.05; src_val[1]=(i%2); #0.05;
                    src_val[2]=(i%2); #0.05; src_val[3]=(i%2); #0.05;
                    src_val[4]=(i%2); #0.05; src_val[5]=(i%2); #0.05;
                    src_val[6]=(i%2); #0.05; src_val[7]=(i%2);
                end
            end
            begin #3000; end
        join
        chk(good_bad==0, "C: maccnt_sync dst never shows a mixed value");
        chk(mut_bad>0, "C: bare-2FF mutant DOES show mixed values (negative control has teeth)");
        // C-live: 斜坡追踪 —— dst 必须在 ≤32 个目的域拍内追到**精确中间值**
        @(negedge src_clk); src_val = 8'd0;
        repeat(20) @(posedge dst_clk);
        ramp_track(0, 8'd1, 4);          // 期望 1 -> 2 -> 3 -> 4
        chk(ramp_fail==0, "C-live: dst tracks src to exact values 1..4 within <=32 dst cycles");
        hold_chk(8'd4, 120, cok);
        chk(cok, "C-live: src frozen at 4 => dst stays exactly 4 for >=120 dst cycles");
        // C-mut: dst 被强制常 0 ⇒ 同一活性判据必须红 (证明判据有牙)
        ramp_track(1, 8'd5, 4);          // 期望 5..8, 恒 0 下全都追不到
        chk(mut_fail>0, "C-mut: dst forced to constant 0 => liveness criterion goes RED");
        mut_arm = 1'b0;

        // ---------- A: HLS 真实握手 (IP_A, ch1) ----------
        build_syn();
        pack_xgmii_into(1);
        // 等 HLS 处理 + 组帧 (HLS 约 1B/拍, 给它足够时间)
        repeat(200000) @(posedge u_dut.dp_clk);
        begin : armA
            integer p1, p0, tcp;
            p1 = find_sig(1, 16'h0800, 8'h12, 1);   // 按 ethertype 找; tag 仅占位
            // SYN-ACK: IP proto 6 + TCP flags 0x12 at offset src+8+...; 用宽松判据:
            //   在 ch1 里找 src MAC + 0800; 再核 TCP flags
            p1 = find_sig(1, 16'h0800, 8'h00, 0);
            p0 = find_sig(0, 16'h0800, 8'h00, 0);
            chk(p1 >= 0, "A: ch1 TX carries an IPv4 frame after SYN to IP_A");
            chk(p0 < 0,  "A: ch0 TX is silent (no cross-port TX)");
            if (p1 >= 0) begin
                // find_sig 返回的是**源 MAC** 的索引 (帧偏移 6) ⇒ 帧首 = p1-6
                tcp = p1 - 6 + 14 + 20;
                chk(cap1[tcp+13] === 8'h12, "A: TCP flags = SYN|ACK on ch1");
                chk(cap1[p1-6+14+12] === 192 && cap1[p1-6+14+13] === 168 &&
                    cap1[p1-6+14+14] === 100 && cap1[p1-6+14+15] === 2,
                    "A: SYN-ACK source IP = IP_A (192.168.100.2)");
            end
        end

        // ---------- B: force 快臂 ----------
        begin : armB
            integer w83_b, w84_b;
            w83_b = u_dut.tx_p0_frames_r; w84_b = u_dut.tx_p1_frames_r;
            // 1) TCP producer -> port1 (ch0)
            force_frame(0, 1, 8'hA1);
            repeat(400) @(posedge u_dut.dp_clk);
            chk(find_sig(0, 16'h1234, 8'hA1, 1) >= 0, "B1: tx_* port=1 appears on ch0 TX");
            chk(find_sig(1, 16'h1234, 8'hA1, 1) < 0, "B1: tx_* port=1 does NOT appear on ch1 TX");
            // 2) UDP producer -> port0 (ch1)
            force_frame(1, 0, 8'hA2);
            repeat(400) @(posedge u_dut.dp_clk);
            chk(find_sig(1, 16'h1234, 8'hA2, 1) >= 0, "B2: utx2_* port=0 appears on ch1 TX");
            chk(find_sig(0, 16'h1234, 8'hA2, 1) < 0, "B2: utx2_* port=0 does NOT appear on ch0 TX");
            // 3) HLS producer -> port1 (ch0)
            force_frame(2, 1, 8'hA3);
            repeat(400) @(posedge u_dut.dp_clk);
            chk(find_sig(0, 16'h1234, 8'hA3, 1) >= 0, "B3: stx_* port=1 appears on ch0 TX");
            chk(find_sig(1, 16'h1234, 8'hA3, 1) < 0, "B3: stx_* port=1 does NOT appear on ch1 TX");
            chk(u_dut.tx_p1_frames_r == (w84_b + 2), "B: W84 (ch0 TX frames) +2");
            chk(u_dut.tx_p0_frames_r == (w83_b + 1), "B: W83 (ch1 TX frames) +1");
        end

        // ---------- D: UDP peer_my_ip -> o_src_ip/o_port 一致性 (F-13) ----------
        //   真 wrapper 里的 u_udp_tx_cfg: peer 表写入 IP_B 的学习帧 ⇒ 源 IP=IP_B 且
        //   端口位=1; 再写 IP_A ⇒ 源 IP=IP_A 且端口位=0。拦的缺陷形态 = o_port 用了
        //   peer_ip 而不是 peer_my_ip (两者在这里刻意不同)。
        begin : armD
            integer g;
            // 1) peer_my_ip = IP_B (0xC0A86404)
            @(negedge u_dut.dp_clk);
            force u_dut.udp_meta_valid   = 1'b1;
            force u_dut.udp_meta_src_mac = 48'h001122334455;
            force u_dut.udp_meta_src_ip  = 32'hC0A86465;   // 对端 .101 (≠ 板 IP)
            force u_dut.udp_meta_dst_ip  = 32'hC0A86404;   // IP_B
            @(posedge u_dut.dp_clk);
            @(negedge u_dut.dp_clk);
            release u_dut.udp_meta_valid;
            release u_dut.udp_meta_src_mac;
            release u_dut.udp_meta_src_ip;
            release u_dut.udp_meta_dst_ip;
            g=0; while ((u_dut.utx_cfg_src_ip !== 32'hC0A86404) && g<20000)
                begin @(posedge u_dut.dp_clk); g=g+1; end
            chk(u_dut.utx_cfg_src_ip === 32'hC0A86404,
                "D: udp_tx_cfg o_src_ip = IP_B after an IP_B learning frame");
            chk(u_dut.utx_port === 1'b1, "D: udp_tx_cfg o_port = 1 for IP_B");
            // 2) peer_my_ip = IP_A (0xC0A86402)
            //    ⚠️ cfg 只在**空闲**拍刷新 (frame_busy=0) ⇒ 学到 peer 后 app 立刻开始连发,
            //    cfg 会被帧窗冻住。先停 app (i_tx_ready=0) 让当前帧收尾, 再写第二笔。
            force u_dut.u_app_udp.i_tx_ready = 1'b0;
            @(negedge u_dut.dp_clk);
            force u_dut.udp_meta_valid   = 1'b1;
            force u_dut.udp_meta_src_mac = 48'h001122334466;
            force u_dut.udp_meta_src_ip  = 32'hC0A86466;
            force u_dut.udp_meta_dst_ip  = 32'hC0A86402;   // IP_A
            @(posedge u_dut.dp_clk);
            @(negedge u_dut.dp_clk);
            release u_dut.udp_meta_valid;
            release u_dut.udp_meta_src_mac;
            release u_dut.udp_meta_src_ip;
            release u_dut.udp_meta_dst_ip;
            g=0; while ((u_dut.utx_cfg_src_ip !== 32'hC0A86402) && g<20000)
                begin @(posedge u_dut.dp_clk); g=g+1; end
            release u_dut.u_app_udp.i_tx_ready;
            chk(u_dut.utx_cfg_src_ip === 32'hC0A86402,
                "D: udp_tx_cfg o_src_ip = IP_A after an IP_A learning frame");
            chk(u_dut.utx_port === 1'b0, "D: udp_tx_cfg o_port = 0 for IP_A");
        end

        if (errs==0) $display("P11_DUAL TB PASS");
        else         $display("P11_DUAL TB FAIL errs=%0d", errs);
        $finish;
    end
    initial begin #4000000; $display("P11_DUAL TB FAIL (timeout)"); $finish; end
endmodule
