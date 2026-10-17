`timescale 1ns/1ps
//=============================================================================
// tb_p5_orphan_wrapper: p9 orphan fix 全链门 (设计件 v4 §6.2)
//
//   臂 A (无 TCP_TX_OVL): C1 / C2a / C3 / C4 —— wrapper_p4 ORPHAN_EN_5=1,
//                          ORPHAN_ZW_EN_5=0, LIM=2, TICK_BITS=1.
//   臂 B (定义 TCP_TX_OVL): C2b —— ORPHAN_ZW_EN_5=1; ack_obs 用**真纯 ACK 帧**
//                          注入 (force u_dut.e_rxd/e_rxdv, 不用 force ack_obs).
//   基线臂 = tb_p5_wrapper (ORPHAN_EN_5=0/ZW_EN_5=0) 原门.
//
// 场景 (+SCEN): 1 C1  2 C2a  3 C3  4 C4  5 C2b-live+dead
// 判定: TB_RESULT PASS / FAIL. 仅在 -d TCP_TX_OVL 构建上跑 scen=5.
//=============================================================================
module tb_p5_orphan_wrapper #(
    parameter integer ZW_EN_TB = 0
);
    localparam [31:0] TB_ISS   = 32'h12345678;
    localparam [31:0] ISN0     = TB_ISS + 32'd1;
    localparam [31:0] PEER_ISN = 32'h20000000;
    localparam [47:0] BOARD_MAC = 48'h000A3501FEC0;
    localparam [47:0] PEER_MAC  = 48'h112233445566;
    localparam [31:0] PEER_IP   = 32'hC0A86401;
    localparam [31:0] BOARD_IP  = 32'hC0A86402;
    localparam [15:0] PEER_PORT = 16'h3039;
    localparam [15:0] APP_PORT  = 16'h1F90;

    reg        reset_n, fpga_gclk, phy1_rxc;
    reg  [3:0] phy1_rxd;
    reg        phy1_rxctl;
    wire       phy1_txc;
    wire [3:0] phy1_txd;
    wire       phy1_txctl;
    wire       led_d0, led_d1, led_d2, led_d3;
    wire       uart_txd;

    wrapper_p4 #(
        .ORPHAN_EN_5(1'b1),
        .ORPHAN_LIM_5(8'd2),
        .ORPHAN_TICK_BITS_5(1),
        .ORPHAN_ZW_EN_5(ZW_EN_TB[0]),
        .ORPHAN_ZW_LIM_5(8'd2),
        .ORPHAN_ZW_TICK_BITS_5(1)
    ) u_dut (
        .reset_n(reset_n), .fpga_gclk(fpga_gclk),
        .phy1_rxc(phy1_rxc), .phy1_rxd(phy1_rxd), .phy1_rxctl(phy1_rxctl),
        .phy1_txc(phy1_txc), .phy1_txd(phy1_txd), .phy1_txctl(phy1_txctl),
        .led_d0(led_d0), .led_d1(led_d1), .led_d2(led_d2), .led_d3(led_d3),
        .uart_txd(uart_txd)
    );

    always #10 fpga_gclk = ~fpga_gclk;   // 50MHz
    always #4  phy1_rxc   = ~phy1_rxc;   // 125MHz -> gmii_clk

    integer scen, errs, i, k;
    reg [31:0] frm_before;
    reg [8*64-1:0] scen_name;

    task chk;
        input cond;
        input [8*96-1:0] msg;
        begin
            if (!cond) begin errs = errs + 1; $display("CHECK FAIL: %0s", msg); end
        end
    endtask

    // ---- TCB/CAM 预置 (与 tb_p5_wrapper 同惯例: 层次赋值) ----
    task preset_conn;
        begin
            u_dut.u_tcb.rcv_nxt_r[0] = PEER_ISN + 32'd1;
            u_dut.u_tcb.snd_nxt_r[0] = ISN0;
            u_dut.u_tcb.snd_una_r[0] = ISN0;
            u_dut.u_tcb.rcv_wnd_r[0] = 16'hC000;
            u_dut.u_tcb.snd_wnd_r[0] = 16'h4000;
            u_dut.u_tcb.state_r[0]   = 4'd1;
            u_dut.u_cam.sip_r[0]     = PEER_IP;
            u_dut.u_cam.dip_r[0]     = BOARD_IP;
            u_dut.u_cam.sport_r[0]   = PEER_PORT;
            u_dut.u_cam.dport_r[0]   = APP_PORT;
            u_dut.u_cam.dmac_r[0]    = PEER_MAC;
        end
    endtask

    // ---- C1: 持续把槽 0 钉在"窗满 + snd_una 冻结" (每 negedge 重写) ----
    reg hold_orphan;
    always @(negedge u_dut.gmii_clk) if (reset_n && hold_orphan) begin
        u_dut.u_tcb.state_r[0]   = 4'd1;
        u_dut.u_tcb.snd_wnd_r[0] = 16'hF000;
        u_dut.u_tcb.snd_una_r[0] = ISN0;
        u_dut.u_tcb.snd_nxt_r[0] = ISN0 + 32'hF000;
        u_dut.u_tcb.rcv_wnd_r[0] = 16'hC000;
    end
    // ---- C2a 零窗 / C2b: 持续钉住零窗 TCB (tcp_rx 会按 ACK 写 snd_wnd) ----
    reg hold_zw;
    always @(negedge u_dut.gmii_clk) if (reset_n && hold_zw) begin
        u_dut.u_tcb.state_r[0]   = 4'd1;
        u_dut.u_tcb.snd_wnd_r[0] = 16'h0000;
        u_dut.u_tcb.snd_una_r[0] = ISN0;
        u_dut.u_tcb.snd_nxt_r[0] = ISN0 + 32'h4000;
        u_dut.u_tcb.rcv_nxt_r[0] = PEER_ISN + 32'd1;
        u_dut.u_tcb.rcv_wnd_r[0] = 16'hC000;
    end

    // ---- 纯 ACK 帧注入 (RX 路径, 同 tb_p5e_udp_wrapper 的 e_rxd/e_rxdv 手法) ----
    reg [7:0] rbuf [0:127];
    integer   rlen;
    function [31:0] crc32_byte;
        input [31:0] c;
        input [7:0]  d;
        integer b;
        reg [31:0] x;
        begin
            x = c ^ {24'd0, d};
            for (b = 0; b < 8; b = b + 1)
                x = (x[0]) ? ((x >> 1) ^ 32'hEDB88320) : (x >> 1);
            crc32_byte = x;
        end
    endfunction

    task build_ack;
        reg [31:0] c;
        integer j;
        begin
            for (j = 0; j < 7; j = j + 1) rbuf[j] = 8'h55;
            rbuf[7] = 8'hD5;
            rbuf[8+0]=BOARD_MAC[47:40]; rbuf[8+1]=BOARD_MAC[39:32];
            rbuf[8+2]=BOARD_MAC[31:24]; rbuf[8+3]=BOARD_MAC[23:16];
            rbuf[8+4]=BOARD_MAC[15:8];  rbuf[8+5]=BOARD_MAC[7:0];
            rbuf[8+6]=PEER_MAC[47:40];  rbuf[8+7]=PEER_MAC[39:32];
            rbuf[8+8]=PEER_MAC[31:24];  rbuf[8+9]=PEER_MAC[23:16];
            rbuf[8+10]=PEER_MAC[15:8];  rbuf[8+11]=PEER_MAC[7:0];
            rbuf[8+12]=8'h08; rbuf[8+13]=8'h00;
            rbuf[8+14]=8'h45; rbuf[8+15]=8'h00;
            rbuf[8+16]=8'h00; rbuf[8+17]=8'd40;       // total length 40
            rbuf[8+18]=8'h12; rbuf[8+19]=8'h34;
            rbuf[8+20]=8'h40; rbuf[8+21]=8'h00;
            rbuf[8+22]=8'd64; rbuf[8+23]=8'h06;       // proto TCP
            rbuf[8+24]=8'h00; rbuf[8+25]=8'h00;
            rbuf[8+26]=PEER_IP[31:24];  rbuf[8+27]=PEER_IP[23:16];
            rbuf[8+28]=PEER_IP[15:8];   rbuf[8+29]=PEER_IP[7:0];
            rbuf[8+30]=BOARD_IP[31:24]; rbuf[8+31]=BOARD_IP[23:16];
            rbuf[8+32]=BOARD_IP[15:8];  rbuf[8+33]=BOARD_IP[7:0];
            c = 32'd0;
            for (j = 0; j < 10; j = j + 1)
                c = c + {16'b0, rbuf[8+14+2*j], rbuf[8+15+2*j]};
            c = (c & 32'hFFFF) + (c >> 16);
            c = (c & 32'hFFFF) + (c >> 16);
            c = ~c;
            rbuf[8+24]=c[15:8]; rbuf[8+25]=c[7:0];
            // TCP: sport/dport/seq/ack/doff/flags/win/csum/urg
            rbuf[8+34]=PEER_PORT[15:8]; rbuf[8+35]=PEER_PORT[7:0];
            rbuf[8+36]=APP_PORT[15:8];  rbuf[8+37]=APP_PORT[7:0];
            rbuf[8+38]=PEER_ISN[31:24]; rbuf[8+39]=PEER_ISN[23:16];
            rbuf[8+40]=PEER_ISN[15:8];  rbuf[8+41]=PEER_ISN[7:0];
            rbuf[8+42]=ISN0[31:24];     rbuf[8+43]=ISN0[23:16];
            rbuf[8+44]=ISN0[15:8];      rbuf[8+45]=ISN0[7:0];
            rbuf[8+46]=8'h50; rbuf[8+47]=8'h10;       // doff=5, ACK
            rbuf[8+48]=8'h40; rbuf[8+49]=8'h00;       // win
            rbuf[8+50]=8'h00; rbuf[8+51]=8'h00;       // tcp csum (rx 不判)
            rbuf[8+52]=8'h00; rbuf[8+53]=8'h00;
            c = 32'hFFFFFFFF;
            for (j = 8; j < 8+14+20+20; j = j + 1) c = crc32_byte(c, rbuf[j]);
            c = ~c;
            rlen = 8 + 14 + 20 + 20 + 4;
            rbuf[8+54]=c[7:0]; rbuf[8+55]=c[15:8];
            rbuf[8+56]=c[23:16]; rbuf[8+57]=c[31:24];
        end
    endtask

    reg inj_on;
    reg [15:0] inj_i;
    always @(posedge u_dut.gmii_clk) if (inj_on) inj_i <= inj_i + 16'd1;
    wire inj_dv = inj_on && (inj_i < rlen);
    wire [7:0] inj_byte = (inj_i < rlen) ? rbuf[inj_i] : 8'h00;
    task inject_ack;
        begin
            inj_i = 0; inj_on = 1'b1;
            repeat (rlen + 20) @(posedge u_dut.gmii_clk);
            inj_on = 1'b0;
        end
    endtask
    always @(negedge u_dut.gmii_clk) begin
        force u_dut.e_rxd  = inj_byte;
        force u_dut.e_rxdv = inj_dv;
        force u_dut.e_rxer = 1'b0;
    end

    // ---- 监视器 ----
    integer n_ack_obs, n_cam_clr, n_collision, n_early_cam;
    reg cam_clr_d;
    always @(posedge u_dut.gmii_clk) if (reset_n) begin
        if (u_dut.rx_ack_obs) n_ack_obs = n_ack_obs + 1;
        if (u_dut.orphan_cam_clr) begin
            n_cam_clr = n_cam_clr + 1;
            if (!u_dut.u_app_ctrl.orph_state_done) n_early_cam = n_early_cam + 1;
            if (u_dut.scfg_cam_wr) n_collision = n_collision + 1;
        end
        cam_clr_d <= u_dut.orphan_cam_clr;
        // C3 ①: 结构上不得出现同拍 orphan 清与 scfg 写 (busy 门)
        if (u_dut.orphan_cam_clr && u_dut.scfg_cam_wr) n_collision = n_collision + 1;
    end

    task wait_cycles;
        input integer n;
        begin repeat (n) @(negedge u_dut.gmii_clk); end
    endtask

    task wait_stat;
        input integer want;
        input integer maxc;
        integer j;
        begin
            j = 0;
            while ((u_dut.app_stat_orphan < want) && (j < maxc)) begin
                @(negedge u_dut.gmii_clk); j = j + 1;
            end
        end
    endtask

    // ---- 抓 retx 见证: force tcp_tx_frame 的输出线 ----
    task pulse_retx;
        begin
            force u_dut.tx_retx_active = 1'b1;
            force u_dut.tx_retx_id_o   = 4'd0;
            repeat (16) @(negedge u_dut.gmii_clk);
            release u_dut.tx_retx_active;
            release u_dut.tx_retx_id_o;
        end
    endtask

    initial begin
        reset_n = 0; fpga_gclk = 0; phy1_rxc = 0; phy1_rxd = 0; phy1_rxctl = 0;
        inj_on = 0; inj_i = 0; hold_orphan = 0; hold_zw = 0;
        errs = 0; n_ack_obs = 0; n_cam_clr = 0; n_collision = 0; n_early_cam = 0;
        if (!$value$plusargs("SCEN=%d", scen)) scen = 1;
        scen_name = "C?";
        #400; reset_n = 1;
        repeat (4000) @(posedge u_dut.gmii_clk);    // MMCM/复位稳定
        preset_conn;
        repeat (600) @(posedge u_dut.gmii_clk);

        case (scen)
        //---------------------------------------------------- C1
        1: begin
            scen_name = "C1";
            // 先钉住"窗满 + snd_una 冻结"再启动 app: app active 但开不出帧
            // (窗满门) ⇒ 孤儿回收时 app 帧内**零字交付** ⇒ W3 直接回 idle
            // (active=0). (若先让 app 发帧再拆连, 帧器 S_IDLE 接受门要求
            //  wnd_open, state=0 后收尾字永远进不去 —— 那是另一个形态, 见
            //  README_FOR_TL 的 C1 记录.)
            hold_orphan = 1;
            repeat (300) @(posedge u_dut.gmii_clk);
            // 启动 app (CONN_UP)
            force u_dut.u_app_ctrl.o_ev_up = 1'b1;
            @(posedge u_dut.gmii_clk);
            release u_dut.u_app_ctrl.o_ev_up;
            repeat (500) @(posedge u_dut.gmii_clk);
            pulse_retx;
            wait_stat(1, 20000);
            repeat (300) @(posedge u_dut.gmii_clk);
            chk(u_dut.app_stat_orphan == 1, "C1 orphan commit (stat=1)");
            chk(u_dut.u_app.closing == 1'b1 || u_dut.u_app.active == 1'b0,
                "C1 app saw CONN_DOWN (closing/active=0)");
            // 释放钉住的 TCB, 让 state=0 (孤儿回收的写) 真正生效 ⇒ tcp_tx_frame
            // 中止当前帧 ⇒ app 的 W3 收尾能排空 (否则窗满门会永远卡住 m_tready).
            @(negedge u_dut.gmii_clk);
            hold_orphan = 0;
            u_dut.u_tcb.state_r[0] = 4'd0;
            // app 收尾完成 -> active=0
            repeat (12000) @(posedge u_dut.gmii_clk);
            $display("C1 app state: active=%b closing=%b pw_valid=%b op_sent=%b seg_sent=%b m_tready=%b",
                     u_dut.u_app.active, u_dut.u_app.closing, u_dut.u_app.pw_valid,
                     u_dut.u_app.op_sent, u_dut.u_app.seg_sent,
                     u_dut.u_app.m_tready);
            chk(u_dut.u_app.active == 1'b0, "C1 app inactive after orphan down");
            // 新会话: 恢复健康 TCB + ev_up (force scfg ADD 收尾脉冲)
            hold_orphan = 0;
            @(negedge u_dut.gmii_clk);
            u_dut.u_tcb.state_r[0]   = 4'd1;
            u_dut.u_tcb.snd_wnd_r[0] = 16'h4000;
            u_dut.u_tcb.snd_una_r[0] = ISN0;
            u_dut.u_tcb.snd_nxt_r[0] = ISN0;
            force u_dut.scfg_ev_up   = 1'b1;
            force u_dut.scfg_ev_slot = 4'd0;
            @(posedge u_dut.gmii_clk);
            @(negedge u_dut.gmii_clk);
            release u_dut.scfg_ev_up;
            release u_dut.scfg_ev_slot;
            frm_before = u_dut.u_app.stat_tx_frames;
            repeat (3000) @(posedge u_dut.gmii_clk);
            chk(u_dut.u_app.active == 1'b1, "C1 new session applied (app active)");
            chk(u_dut.u_app.closing == 1'b0, "C1 app not closing after re-add");
            chk(u_dut.u_app.stat_tx_frames > frm_before,
                "C1 new session emits frames again");
        end
        //---------------------------------------------------- C2a
        2: begin
            scen_name = "C2a";
            // (a) 健康推进: 窗满 + 每 round snd_una/nxt 前进 + 一次 retx
            hold_orphan = 0;
            for (i = 0; i < 8; i = i + 1) begin
                @(negedge u_dut.gmii_clk);
                u_dut.u_tcb.state_r[0]   = 4'd1;
                u_dut.u_tcb.snd_wnd_r[0] = 16'hF000;
                u_dut.u_tcb.snd_una_r[0] = ISN0 + i[31:0];
                u_dut.u_tcb.snd_nxt_r[0] = ISN0 + i[31:0] + 32'hF000;
                // 模拟 tcp_rx 的 snd_una 推进授权 (una_adv = rx_upd_gnt && sel==2)
                force u_dut.rx_upd_gnt = 1'b1;
                force u_dut.rx_upd_sel = 3'd2;
                force u_dut.rx_upd_id  = 4'd0;
                @(posedge u_dut.gmii_clk);
                @(negedge u_dut.gmii_clk);
                release u_dut.rx_upd_gnt;
                release u_dut.rx_upd_sel;
                release u_dut.rx_upd_id;
                if (i == 2) pulse_retx;
                repeat (256) @(negedge u_dut.gmii_clk);
            end
            chk(u_dut.app_stat_orphan == 0, "C2a healthy: no Mode A fire");
            // (b) 零窗 (Mode A 排除; Mode B 本门关闭)
            hold_zw = 1;
            for (i = 0; i < 8; i = i + 1) begin
                @(negedge u_dut.gmii_clk);
                if (i == 1) pulse_retx;
                repeat (256) @(negedge u_dut.gmii_clk);
            end
            hold_zw = 0;
            chk(u_dut.app_stat_orphan == 0, "C2a zero-window: no Mode A fire");
            // (c) 慢盆: 小在飞 + 每 2 ticks 一次进度 + 一次 retx
            for (i = 0; i < 16; i = i + 1) begin
                @(negedge u_dut.gmii_clk);
                u_dut.u_tcb.state_r[0]   = 4'd1;
                u_dut.u_tcb.snd_wnd_r[0] = 16'hF000;
                u_dut.u_tcb.snd_una_r[0] = ISN0 + i[31:0];
                u_dut.u_tcb.snd_nxt_r[0] = ISN0 + i[31:0] + 32'h100;
                if (i == 1) pulse_retx;
                repeat (256) @(negedge u_dut.gmii_clk);
            end
            chk(u_dut.app_stat_orphan == 0, "C2a slow basin: no Mode A fire");
            chk(n_cam_clr == 0, "C2a no CAM clear");
        end
        //---------------------------------------------------- C3
        3: begin
            scen_name = "C3";
            hold_orphan = 1;
            pulse_retx;
            wait_stat(1, 20000);
            repeat (200) @(posedge u_dut.gmii_clk);
            chk(n_collision == 0, "C3-1 no orphan_cam_clr && scfg_cam_wr");
            chk(n_early_cam == 0, "C3-3 orphan_cam_clr only after orph_state_done");
            // C3-2: 强制同拍碰撞, mux 必须选 scfg 值
            @(negedge u_dut.gmii_clk);
            force u_dut.scfg_cam_wr   = 1'b1;
            force u_dut.scfg_cam_addr = 4'd5;
            force u_dut.scfg_cam_sip  = 32'hDEADBEEF;
            force u_dut.scfg_cam_dip  = 32'hCAFEBABE;
            force u_dut.scfg_cam_sport= 16'h1111;
            force u_dut.scfg_cam_dport= 16'h2222;
            force u_dut.scfg_cam_dmac = 48'hAABBCCDDEEFF;
            force u_dut.orphan_cam_clr  = 1'b1;
            force u_dut.orphan_cam_slot = 4'd5;
            @(posedge u_dut.gmii_clk);
            @(negedge u_dut.gmii_clk);
            release u_dut.scfg_cam_wr;
            release u_dut.scfg_cam_addr;
            release u_dut.scfg_cam_sip;
            release u_dut.scfg_cam_dip;
            release u_dut.scfg_cam_sport;
            release u_dut.scfg_cam_dport;
            release u_dut.scfg_cam_dmac;
            release u_dut.orphan_cam_clr;
            release u_dut.orphan_cam_slot;
            repeat (2) @(posedge u_dut.gmii_clk);
            chk(u_dut.u_cam.sip_r[5] == 32'hDEADBEEF, "C3-2 CAM mux picks scfg value on collision");
            chk(u_dut.u_cam.dmac_r[5] == 48'hAABBCCDDEEFF, "C3-2 CAM dmac from scfg");
        end
        //---------------------------------------------------- C4
        4: begin
            scen_name = "C4";
            hold_orphan = 1;
            pulse_retx;
            // 等 FSM 进入 "state_done + cam_req 待发"
            k = 0;
            while (!(u_dut.u_app_ctrl.orph_cam_req &&
                     u_dut.u_app_ctrl.orph_state_done) && k < 20000) begin
                @(negedge u_dut.gmii_clk); k = k + 1;
            end
            chk(k < 20000, "C4 FSM reached cam_req+state_done");
            force u_dut.scfg_busy = 1'b1;       // 同一 negedge (下一拍 posedge 前)
            repeat (32) @(negedge u_dut.gmii_clk);
            chk(n_cam_clr == 0, "C4 no CAM clear while scfg_busy held");
            release u_dut.scfg_busy;
            wait_stat(1, 20000);
            chk(n_cam_clr >= 1, "C4 CAM clear after busy release");
            // wcnt != 0 也算 busy
            @(negedge u_dut.gmii_clk);
            force u_dut.u_slow_cfg.wcnt = 3'd3;
            @(negedge u_dut.gmii_clk);
            chk(u_dut.scfg_busy == 1'b1, "C4 wcnt!=0 counts as busy");
            release u_dut.u_slow_cfg.wcnt;
        end
        //---------------------------------------------------- C2b (OVL only)
        5: begin
            scen_name = "C2b";
            chk(ZW_EN_TB == 1, "C2b requires ZW_EN_TB=1 (TCP_TX_OVL build)");
            build_ack;
            hold_zw = 1;
            // ---- 活零窗: 每 256 拍注入一次真纯 ACK, 跑 4 ticks ----
            for (i = 0; i < 4; i = i + 1) begin
                @(negedge u_dut.gmii_clk);
                inject_ack;
            end
            $display("C2b inj diag: mac_frames=%0d mac_crc=%0d pass=%0d drop_seq=%0d drop_nm=%0d drop_ipc=%0d ackobs=%0d",
                     u_dut.u_mac_rx.stat_frames, u_dut.u_mac_rx.stat_crc_err,
                     u_dut.u_tcp_rx.stat_pass, u_dut.u_tcp_rx.stat_drop_seq,
                     u_dut.u_tcp_rx.stat_drop_nonmatch, u_dut.u_tcp_rx.stat_drop_ipcsum,
                     n_ack_obs);
            chk(n_ack_obs >= 2, "C2b precondition: real ACK frames produced ack_obs pulses");
            chk(u_dut.app_stat_orphan == 0, "C2b live zero-window: no fire");
            // ---- 死零窗: 不再注入, 跑 4 ticks ----
            for (i = 0; i < 6; i = i + 1) begin
                repeat (256) @(negedge u_dut.gmii_clk);
            end
            wait_stat(1, 20000);
            chk(u_dut.app_stat_orphan == 1, "C2b dead zero-window: Mode B fires");
            chk(n_cam_clr >= 1, "C2b dead zero-window: CAM clear issued");
        end
        default: begin scen_name = "BADSCEN"; errs = errs + 1; end
        endcase

        wait_cycles(10);
        if (errs == 0) $display("TB_RESULT PASS %0s (stat=%0d cam=%0d ackobs=%0d)",
                                scen_name, u_dut.app_stat_orphan, n_cam_clr, n_ack_obs);
        else           $display("TB_RESULT FAIL %0s errs=%0d (stat=%0d cam=%0d ackobs=%0d)",
                                scen_name, errs, u_dut.app_stat_orphan, n_cam_clr, n_ack_obs);
        $finish;
    end

    initial begin
        #50_000_000;
        $display("TB_RESULT FAIL TIMEOUT");
        $finish;
    end
endmodule
