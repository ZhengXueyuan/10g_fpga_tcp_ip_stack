`timescale 1ns/1ps
//=============================================================================
// tb_p11_c4_wrap.v — P11 P3 G-P3-6: C4 双栈 wrapper 全链门
//   配置: P7B_10G + P7B_SIM_NOPCS + PCIE_OBS + DEV_USP + APP_MODE + DP_156MHZ
//         + P6B_SIM_CLKGEN + UDP_TX_OVL + TCP_TX_OVL + SFP2_MODE_A + DUAL_SFP_A
//         + P11_DUAL + P11_CFG_C4 + P11_CFG_ENFORCE
//   臂:
//     A. ch0 注入 ARP request (target IP_B) => 回包只出现在 ch0 TX (port1 全链:
//        ch0 RX -> vlan -> classify -> udp_split2 -> slow_merge2 -> 单份 HLS
//        -> slow_tx_adp -> slow_demux2(按源 IP=IP_B) -> arb1 -> mac_tx_ch0)。
//        ✅ P3 修复轮 (M-1): 本门改用 **P3/P2 双 IP 网表 + P11_HLS_ADV_WND**,
//        IP_B 必须应答 (归档旧日志 `reply idx=13`; 旧报告"单 IP 不应答"是
//        网表/宏配对错误 —— 见 H-4)。本臂现在是**硬判据** (idx>=0/opcode=2/SPA=IP_B)。
//     B. ch1 注入 ARP request (target IP_A) => 回包只出现在 ch1 TX。
//     C. ch0 注入 SYN (dst IP_B) => SYN-ACK 只出现在 ch0 TX (源 IP=IP_B)。
//     D. ch1 注入 SYN (dst IP_A) => SYN-ACK 只出现在 ch1 TX。
//   注: 每个臂都要求**对端无该回包** (跨口隔离)。
//=============================================================================
module tb_p11_c4_wrap;
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

    localparam [31:0] IP_A = 32'hC0A86402;
    localparam [31:0] IP_B = 32'hC0A86404;

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
    reg [7:0] xb [0:2047];
    reg       xc [0:2047];
    integer   xn = 0;
    reg [31:0] fcs_calc;

    function [31:0] crc32_byte;
        input [31:0] crc; input [7:0] b;
        integer i; reg [31:0] x;
        begin
            x = crc ^ {24'h0, b};
            for (i=0;i<8;i=i+1)
                x = (x[0]) ? ((x >> 1) ^ 32'hEDB88320) : (x >> 1);
            crc32_byte = x;
        end
    endfunction

    task pack_xgmii_into;
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

    // 完整 XGMII 序列: /S/ + preamble + fb[0..flen) + FCS + /T/
    task finish_frame(input integer flen);
        integer i;
        begin
            fcs_calc = 32'hFFFFFFFF;
            for (i=0;i<flen;i=i+1) fcs_calc = crc32_byte(fcs_calc, fb[i]);
            fcs_calc = ~fcs_calc;
            xn = 0;
            xb[0]=8'hFB; xc[0]=1'b1; xn=1;
            for (i=0;i<6;i=i+1) begin xb[xn]=8'h55; xc[xn]=1'b0; xn=xn+1; end
            xb[xn]=8'hD5; xc[xn]=1'b0; xn=xn+1;
            for (i=0;i<flen;i=i+1) begin xb[xn]=fb[i]; xc[xn]=1'b0; xn=xn+1; end
            xb[xn]=fcs_calc[7:0];   xc[xn]=1'b0; xn=xn+1;
            xb[xn]=fcs_calc[15:8];  xc[xn]=1'b0; xn=xn+1;
            xb[xn]=fcs_calc[23:16]; xc[xn]=1'b0; xn=xn+1;
            xb[xn]=fcs_calc[31:24]; xc[xn]=1'b0; xn=xn+1;
            xb[xn]=8'hFD; xc[xn]=1'b1; xn=xn+1;
        end
    endtask

    task build_arp(input [31:0] tpa);
        integer i;
        reg [31:0] s;
        begin
            for (i=0;i<60;i=i+1) fb[i]=8'h00;
            for (i=0;i<6;i=i+1) fb[i]=8'hFF;
            fb[6]=8'h10;fb[7]=8'h11;fb[8]=8'h12;fb[9]=8'h13;fb[10]=8'h14;fb[11]=8'h15;
            fb[12]=8'h08; fb[13]=8'h06;                     // ARP
            fb[14]=0; fb[15]=1; fb[16]=8'h08; fb[17]=0;     // htype/ptype
            fb[18]=6; fb[19]=4; fb[20]=0; fb[21]=1;         // hlen/plen/op=request
            fb[22]=8'h10;fb[23]=8'h11;fb[24]=8'h12;fb[25]=8'h13;fb[26]=8'h14;fb[27]=8'h15;
            fb[28]=192;fb[29]=168;fb[30]=100;fb[31]=101;    // spa
            for (i=0;i<6;i=i+1) fb[32+i]=0;                 // tha
            fb[38]=(tpa>>24)&255;fb[39]=(tpa>>16)&255;fb[40]=(tpa>>8)&255;fb[41]=tpa&255;
            finish_frame(60);
        end
    endtask

    task build_syn(input [31:0] dip);
        integer i, j;
        reg [31:0] s;
        begin
            for (i=0;i<60;i=i+1) fb[i]=8'h00;
            for (i=0;i<6;i=i+1) fb[i]=8'hFF;
            fb[6]=8'h10;fb[7]=8'h11;fb[8]=8'h12;fb[9]=8'h13;fb[10]=8'h14;fb[11]=8'h15;
            fb[12]=8'h08;fb[13]=8'h00;
            fb[14]=8'h45;fb[15]=0; fb[16]=0; fb[17]=40;
            fb[18]=0; fb[19]=1; fb[20]=8'h40; fb[21]=0;
            fb[22]=64; fb[23]=6; fb[24]=0; fb[25]=0;
            fb[26]=192;fb[27]=168;fb[28]=100;fb[29]=101;
            fb[30]=(dip>>24)&255;fb[31]=(dip>>16)&255;fb[32]=(dip>>8)&255;fb[33]=dip&255;
            s=0; for (j=0;j<10;j=j+1) s=s+((fb[14+j*2]<<8)|fb[14+j*2+1]);
            while (s>>16) s=(s&16'hFFFF)+(s>>16);
            s=~s; fb[24]=(s>>8)&255; fb[25]=s&255;
            fb[34]=8'h5B;fb[35]=8'hE0; fb[36]=8'h1F;fb[37]=8'h90;
            fb[38]=0;fb[39]=0;fb[40]=0;fb[41]=0;
            fb[42]=0;fb[43]=0;fb[44]=0;fb[45]=0;
            fb[46]=8'h50;fb[47]=8'h02;fb[48]=8'h20;fb[49]=0;
            fb[50]=0;fb[51]=0;fb[52]=0;fb[53]=0;
            s = (192<<8 | 168) + (100<<8 | 101);
            s = s + (dip>>16) + (dip & 16'hFFFF) + 6 + 20;
            for (j=0;j<10;j=j+1) s=s+((fb[34+j*2]<<8)|fb[34+j*2+1]);
            while (s>>16) s=(s&16'hFFFF)+(s>>16);
            s=~s; fb[50]=(s>>8)&255; fb[51]=s&255;
            finish_frame(60);
        end
    endtask

    // ---------------- TX 捕获 (逐通道数据字节) ----------------
    reg [7:0] cap1 [0:8191]; integer cap1_n=0;
    reg [7:0] cap0 [0:8191]; integer cap0_n=0;
    always @(posedge u_dut.u_pcs.tx_clk) begin : cap
        integer l;
        for (l=0;l<8;l=l+1) begin
            if (u_dut.u_pcs.txcap_c1[l]===1'b0) begin
                if (cap1_n<8191) cap1[cap1_n] = u_dut.u_pcs.txcap_d1[l*8 +: 8];
                cap1_n = cap1_n + 1;
            end
        end
        for (l=0;l<8;l=l+1) begin
            if (u_dut.u_pcs.txcap_c0[l]===1'b0) begin
                if (cap0_n<8191) cap0[cap0_n] = u_dut.u_pcs.txcap_d0[l*8 +: 8];
                cap0_n = cap0_n + 1;
            end
        end
    end

    // 在通道字节流里找 board MAC + ethertype (偏移 i+6 起 = 帧首)
    function integer find_eth;
        input integer ch; input [15:0] etype;
        integer i, n;
        begin
            find_eth = -1;
            n = (ch==1) ? cap1_n : cap0_n;
            for (i=0; i<n-20; i=i+1) begin
                if (((ch==1)?cap1[i]:cap0[i]) == 8'h00 &&
                    ((ch==1)?cap1[i+1]:cap0[i+1]) == 8'h0A &&
                    ((ch==1)?cap1[i+2]:cap0[i+2]) == 8'h35 &&
                    ((ch==1)?cap1[i+3]:cap0[i+3]) == 8'h01 &&
                    ((ch==1)?cap1[i+4]:cap0[i+4]) == 8'hFE &&
                    ((ch==1)?cap1[i+5]:cap0[i+5]) == 8'hC0 &&
                    ((ch==1)?cap1[i+6]:cap0[i+6]) == etype[15:8] &&
                    ((ch==1)?cap1[i+7]:cap0[i+7]) == etype[7:0])
                    find_eth = i;   // 取最后一个匹配
            end
        end
    endfunction

    function [7:0] cb; input integer ch; input integer i;
        begin cb = (ch==1) ? cap1[i] : cap0[i]; end
    endfunction

    task clear_caps; begin cap0_n=0; cap1_n=0; end endtask

    task wait_tx(input integer n); begin repeat(n) @(posedge u_dut.u_pcs.tx_clk); end endtask

    integer idx;
    initial begin
        $display("=== G-P3-6 C4 wrapper ===");
        reset_n = 0;
        repeat (40) @(posedge u_dut.u_pcs.tx_clk);
        reset_n = 1;
        wait_tx(2000);

        // ---- 臂 B: ARP -> IP_A on ch1 ----
        clear_caps();
        build_arp(IP_A); pack_xgmii_into(1);
        wait_tx(4000);
        idx = find_eth(1, 16'h0806);
        chk(idx >= 0, "B ARP reply for IP_A present on ch1");
        if (idx >= 0) begin
            chk(cb(1, idx+8+6)==0 && cb(1, idx+8+7)==2, "B ARP opcode=reply");
            chk(cb(1, idx+8+14)==192 && cb(1, idx+8+15)==168 &&
                cb(1, idx+8+16)==100 && cb(1, idx+8+17)==2, "B ARP SPA = IP_A");
        end
        chk(find_eth(0, 16'h0806) < 0, "B no ARP reply on ch0 (cross-port isolation)");

        // ---- 臂 A: ARP -> IP_B on ch0 (双 IP 网表: 必须应答) ----
        clear_caps();
        build_arp(IP_B); pack_xgmii_into(0);
        wait_tx(4000);
        idx = find_eth(0, 16'h0806);
        chk(idx >= 0, "A ARP reply for IP_B present on ch0");
        if (idx >= 0) begin
            chk(cb(0, idx+8+6)==0 && cb(0, idx+8+7)==2, "A ARP opcode=reply");
            chk(cb(0, idx+8+14)==192 && cb(0, idx+8+15)==168 &&
                cb(0, idx+8+16)==100 && cb(0, idx+8+17)==4, "A ARP SPA = IP_B");
        end
        chk(find_eth(1, 16'h0806) < 0, "A no ARP reply on ch1 (cross-port isolation)");

        // ---- 臂 C: SYN -> IP_B on ch0 ----
        clear_caps();
        build_syn(IP_B); pack_xgmii_into(0);
        wait_tx(6000);
        idx = find_eth(0, 16'h0800);
        chk(idx >= 0, "C SYN-ACK for IP_B present on ch0");
        if (idx >= 0) begin
            chk(cb(0, idx+17)==6, "C IP proto = TCP");
            chk((cb(0, idx+8+20+13) & 8'h12) == 8'h12, "C TCP flags = SYN|ACK");
            chk(cb(0, idx+20)==192 && cb(0, idx+21)==168 &&
                cb(0, idx+22)==100 && cb(0, idx+23)==4, "C SYN-ACK src IP = IP_B");
        end
        chk(find_eth(1, 16'h0800) < 0, "C no SYN-ACK on ch1 (cross-port isolation)");

        // ---- 臂 D: SYN -> IP_A on ch1 ----
        clear_caps();
        build_syn(IP_A); pack_xgmii_into(1);
        wait_tx(6000);
        idx = find_eth(1, 16'h0800);
        chk(idx >= 0, "D SYN-ACK for IP_A present on ch1");
        if (idx >= 0) begin
            chk(cb(1, idx+17)==6, "D IP proto = TCP");
            chk((cb(1, idx+8+20+13) & 8'h12) == 8'h12, "D TCP flags = SYN|ACK");
            chk(cb(1, idx+20)==192 && cb(1, idx+21)==168 &&
                cb(1, idx+22)==100 && cb(1, idx+23)==2, "D SYN-ACK src IP = IP_A");
        end

        if (errs == 0) $display("P11_C4_WRAP TB PASS");
        else           $display("P11_C4_WRAP TB FAIL errs=%0d", errs);
        $finish;
    end
    initial begin #5000000; $display("P11_C4_WRAP TB FAIL (timeout)"); $finish; end
endmodule
