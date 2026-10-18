`timescale 1ns/1ps
//=============================================================================
// slow_cfg_demux.v — P11 P3 (C4): HLS cfg 8 词记录 1:2 端口分流
//=============================================================================
// 设计件 §5.2 / §14.2-3: 单份双 IP HLS 的 cfg_stream -> 每口一套 slow_cfg_adp。
//
// 记录 = 定长 8 词 (同 slow_cfg_adp):
//   w0 = (wscale<<16)|(cmd<<8)|slot      cmd: 0=ADD / 1=DEL
//   w2 = local_ip (ADD: 本连接身份; DEL: 由 HLS 侧改传 c.local_ip —— 本模块
//        仍以 slot_port 为准, w2 仅作一致性校验)
//
// 路由:
//   · ADD: 按 w2 判口 (w2 == IP_B ⇒ port1/ch0, 否则 port0/ch1);
//          同时更新 slot_port[slot] (给 win_pool_mgr / retx_pool_shared)。
//   · DEL: **按 slot_port[slot]** 路由 (不依赖 w2; back-to-back DEL->ADD 时
//          DEL 先处理, 用的是旧映射); 若 w2 非 0 且与 slot_port 不一致 ⇒
//          stat_cfg_port_mismatch++ (应恒 0)。
//   · slot[3] == 1 (slot >= 8): 记录**整条丢弃** + stat_slot_oor++。
//     (HLS 是唯一建连源, 8 槽合同 ⇒ slot 0..7; 若槽号越界, CAM/TCB 会写 8..15
//      而共享 retx 的 8 槽会别名到 0..7 ⇒ 必须结构性挡住。)
//
// 结构:
//   · 输入 16 深 FIFO 承接 HLS 突发 (与 slow_cfg_adp 的既有深度/语义相同);
//     s_axis_tready = !full ⇒ HLS 不会被 cfg 反压卡死 (ap_ctrl_none)。
//   · 单记录缓冲 (8x32 FF): 捕获整条记录 -> S_ROUTE (1 拍判口/更新 slot_port)
//     -> S_PLAY (按目标口 tready 逐词播放) -> S_RECV。
//   · 单缓冲按记录顺序处理 ⇒ DEL->ADD 的顺序与映射更新顺序天然正确。
//
// 本模块是 C4 专用新件; C1/C2/C3 构建不例化。
//=============================================================================
module slow_cfg_demux #(
    parameter [31:0] IP_B = 32'hC0A86404   // 192.168.100.4 = ch0/J7 = port1
) (
    input  wire        clk,
    input  wire        rst_n,
    // ---- HLS cfg_stream ----
    input  wire [31:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    // ---- 到 slow_cfg_adp #0 (port0/ch1) ----
    output wire [31:0] d0_tdata,
    output wire        d0_tvalid,
    input  wire        d0_tready,
    // ---- 到 slow_cfg_adp #1 (port1/ch0) ----
    output wire [31:0] d1_tdata,
    output wire        d1_tvalid,
    input  wire        d1_tready,
    // ---- 槽属主映射 (1 = port1; 给 win_pool_mgr / retx_pool_shared) ----
    output reg  [7:0]  slot_port,
    // ---- 观测 ----
    output reg  [31:0] stat_slot_oor,           // slot >= 8 的记录数 (应恒 0)
    output reg  [31:0] stat_cfg_port_mismatch   // DEL 的 w2 与 slot_port 不一致 (应恒 0)
);
    localparam S_RECV = 2'd0, S_ROUTE = 2'd1, S_PLAY = 2'd2;

    reg  [1:0]  state;
    reg  [2:0]  wcnt;
    reg  [31:0] rec0, rec1, rec2, rec3, rec4, rec5, rec6, rec7;
    reg  [2:0]  pcnt;
    reg         dst_port;
    reg         do_play;

    wire [31:0] f_dout;
    wire        f_empty, f_full;
    wire        f_rd = (state == S_RECV) && !f_empty;
    assign      s_axis_tready = !f_full;

    fifo_sync #(.W(32), .D(16), .AW(4)) u_fifo (
        .clk(clk), .rst_n(rst_n),
        .wr(s_axis_tvalid && s_axis_tready), .din(s_axis_tdata),
        .rd(f_rd), .dout(f_dout),
        .empty(f_empty), .full(f_full)
    );

    wire [7:0]  cmd   = rec0[15:8];
    wire [3:0]  slot  = rec0[3:0];
    wire        is_add = (cmd == 8'd0);
    wire        is_del = (cmd == 8'd1);
    wire        ip_b_match = (rec2 == IP_B);

    // 当前播出词 (组合)
    reg [31:0] rec_mux;
    always @(*) begin
        case (pcnt)
            3'd0: rec_mux = rec0;
            3'd1: rec_mux = rec1;
            3'd2: rec_mux = rec2;
            3'd3: rec_mux = rec3;
            3'd4: rec_mux = rec4;
            3'd5: rec_mux = rec5;
            3'd6: rec_mux = rec6;
            default: rec_mux = rec7;
        endcase
    end
    assign d0_tdata  = rec_mux;
    assign d1_tdata  = rec_mux;
    assign d0_tvalid = (state == S_PLAY) && do_play && !dst_port;
    assign d1_tvalid = (state == S_PLAY) && do_play &&  dst_port;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_RECV; wcnt <= 3'd0; pcnt <= 3'd0;
            rec0 <= 0; rec1 <= 0; rec2 <= 0; rec3 <= 0;
            rec4 <= 0; rec5 <= 0; rec6 <= 0; rec7 <= 0;
            dst_port <= 1'b0; do_play <= 1'b0;
            slot_port <= 8'd0;
            stat_slot_oor <= 32'd0; stat_cfg_port_mismatch <= 32'd0;
        end else begin
            case (state)
                S_RECV: begin
                    do_play <= 1'b0;
                    if (!f_empty) begin
                        case (wcnt)
                            3'd0: rec0 <= f_dout;
                            3'd1: rec1 <= f_dout;
                            3'd2: rec2 <= f_dout;
                            3'd3: rec3 <= f_dout;
                            3'd4: rec4 <= f_dout;
                            3'd5: rec5 <= f_dout;
                            3'd6: rec6 <= f_dout;
                            default: rec7 <= f_dout;
                        endcase
                        if (wcnt == 3'd7) begin
                            wcnt  <= 3'd0;
                            state <= S_ROUTE;
                        end else begin
                            wcnt <= wcnt + 3'd1;
                        end
                    end
                end
                S_ROUTE: begin
                    // rec0..rec7 现已全部有效 (第 8 词在上一拍已写入)
                    pcnt <= 3'd0;
                    if (slot[3]) begin
                        // slot >= 8: 整条记录丢弃 (不更新 slot_port, 不播放)
                        stat_slot_oor <= stat_slot_oor + 32'd1;
                        do_play <= 1'b0;
                        state   <= S_RECV;
                    end else if (is_add) begin
                        dst_port <= ip_b_match;
                        slot_port[slot] <= ip_b_match;
                        do_play <= 1'b1;
                        state   <= S_PLAY;
                    end else if (is_del) begin
                        dst_port <= ip_b_match;
                        // w2 一致性: DEL 已改传 local_ip; 非 0 且与映射不符 ⇒ 计错
                        if ((rec2 != 32'd0) && (ip_b_match != slot_port[slot]))
                            stat_cfg_port_mismatch <= stat_cfg_port_mismatch + 32'd1;
                        do_play <= 1'b1;
                        state   <= S_PLAY;
                    end else begin
                        // 未知 cmd: 按 w2 判口播放 (保守; 不更新映射)
                        dst_port <= ip_b_match;
                        do_play <= 1'b1;
                        state   <= S_PLAY;
                    end
                end
                default: begin // S_PLAY
                    if (do_play && (dst_port ? d1_tready : d0_tready)) begin
                        if (pcnt == 3'd7) begin
                            do_play <= 1'b0;
                            state   <= S_RECV;
                        end else begin
                            pcnt <= pcnt + 3'd1;
                        end
                    end
                end
            endcase
        end
    end

endmodule
