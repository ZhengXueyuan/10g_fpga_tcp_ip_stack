`timescale 1ns/1ps
//=============================================================================
// retx_pool_shared.v — P11 P3 (C4): 共享 8 槽 TCP 重传环 (128 tile)
//=============================================================================
// 设计件 §4.7: 8 x retx_ram #(.N(1)) + per-slot owner mux。
//   · 每槽只有一个属主口。属主 = `grant_port[slot]` —— **来自 win_pool_mgr**
//     (ev_up 时更新), **不是** slow_cfg_demux 的 `slot_port`。
//     ⭐ H-2 (P3 修复轮): `slow_cfg_demux` 在 ADD 路由拍就翻转 `slot_port`,
//     早于旧口 TCB 拆除完成; 若用它会在这个窗口里把旧口的 retx 读写判成
//     非属主 ⇒ 旧口重传读陈旧数据/写被丢弃。`grant_port` 在 ev_up 时更新:
//     旧口在 ev_up 前仍属主, 新口 ev_up 后接管。
//     `slot_port` 只用于 cfg DEL 路由 (慢路径), 不进本模块。
//   · 两口访问不同槽天然并行; 同槽访问在 owner 守卫下**结构性不可能**
//     (非属主访问被丢弃并计 stat_retx_owner_mismatch —— 不损坏数据)。
//   · 非属主**读**的 r_data 输出清零 (M-2/H-2: 不给下游陈旧数据; 旧实装
//     会把该槽 RAM 的旧内容送出去)。authorization 在**发起读的那一拍**采样,
//     与 2 拍读延迟同管道对齐。
//   · slot >= 8 的访问被丢弃并计 stat_slot_oor (cfg demux 已在上游守卫)。
//
// 读延迟: 与 retx_ram 相同 (rd_en 拍后 2 拍出数)。本模块在入口寄存读者槽号
//   两级 (d1/d2), 在出数拍用它选 8 个实例的输出 —— 不改变 2 拍延迟。
//
// 本模块是 C4 专用新件; C1/C2/C3 构建不例化。
//=============================================================================
module retx_pool_shared (
    input  wire        clk,
    input  wire        rst_n,
    // ---- 槽属主映射 (1 = port1/ch0; 0 = port0/ch1) —— win_pool_mgr.o_grant_port ----
    input  wire [7:0]  grant_port,
    // ---- port0 引擎 (tcp_tx_frame #0 的 EXTERNAL_RETX 端口) ----
    input  wire        wr_en0,
    input  wire [3:0]  w_conn0,
    input  wire [15:0] w_seq0,
    input  wire [63:0] w_data0,
    input  wire [3:0]  w_n0,
    input  wire        rd_en0,
    input  wire [3:0]  r_conn0,
    input  wire [15:0] r_seq0,
    output wire [63:0] r_data0,
    // ---- port1 引擎 ----
    input  wire        wr_en1,
    input  wire [3:0]  w_conn1,
    input  wire [15:0] w_seq1,
    input  wire [63:0] w_data1,
    input  wire [3:0]  w_n1,
    input  wire        rd_en1,
    input  wire [3:0]  r_conn1,
    input  wire [15:0] r_seq1,
    output wire [63:0] r_data1,
    // ---- 观测 ----
    output reg  [31:0] stat_retx_owner_mismatch,  // 非属主访问 (应恒 0)
    output reg  [31:0] stat_slot_oor              // 槽号 >= 8 (应恒 0)
);
    genvar gi;

    // 读者槽号 / 读授权延迟 (与 retx_ram 的 2 拍读延迟对齐)
    reg  [3:0] rd0_slot_d1, rd0_slot_d2;
    reg  [3:0] rd1_slot_d1, rd1_slot_d2;
    reg        rd0_ok_d1, rd0_ok_d2;
    reg        rd1_ok_d1, rd1_ok_d2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd0_slot_d1 <= 4'd0; rd0_slot_d2 <= 4'd0;
            rd1_slot_d1 <= 4'd0; rd1_slot_d2 <= 4'd0;
            rd0_ok_d1 <= 1'b0; rd0_ok_d2 <= 1'b0;
            rd1_ok_d1 <= 1'b0; rd1_ok_d2 <= 1'b0;
        end else begin
            if (rd_en0) begin
                rd0_slot_d1 <= r_conn0;
                rd0_ok_d1   <= (r_conn0 < 4'd8) && (grant_port[r_conn0] == 1'b0);
            end
            if (rd_en1) begin
                rd1_slot_d1 <= r_conn1;
                rd1_ok_d1   <= (r_conn1 < 4'd8) && (grant_port[r_conn1] == 1'b1);
            end
            rd0_slot_d2 <= rd0_slot_d1;
            rd1_slot_d2 <= rd1_slot_d1;
            rd0_ok_d2   <= rd0_ok_d1;
            rd1_ok_d2   <= rd1_ok_d1;
        end
    end

    // 每槽实例
    wire [63:0] s_rdata [0:7];
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin : g_slot
            wire       wr0_ok = wr_en0 && (w_conn0 == gi[3:0]) && (grant_port[gi] == 1'b0);
            wire       wr1_ok = wr_en1 && (w_conn1 == gi[3:0]) && (grant_port[gi] == 1'b1);
            wire       rd0_ok = rd_en0 && (r_conn0 == gi[3:0]) && (grant_port[gi] == 1'b0);
            wire       rd1_ok = rd_en1 && (r_conn1 == gi[3:0]) && (grant_port[gi] == 1'b1);
            // wr0_ok 与 wr1_ok 互斥 (grant_port 只有一位) ⇒ 无需写仲裁
            wire       wr_s   = wr0_ok | wr1_ok;
            wire [15:0] wseq_s = wr0_ok ? w_seq0 : w_seq1;
            wire [63:0] wdat_s = wr0_ok ? w_data0 : w_data1;
            wire [3:0]  wn_s   = wr0_ok ? w_n0   : w_n1;
            wire       rd_s   = rd0_ok | rd1_ok;
            wire [15:0] rseq_s = rd0_ok ? r_seq0 : r_seq1;
            retx_ram #(.N(1)) u_ram (
                .clk(clk), .rst_n(rst_n),
                .wr_en(wr_s), .w_conn(4'd0), .w_seq(wseq_s),
                .w_data(wdat_s), .w_n(wn_s),
                .rd_en(rd_s), .r_conn(4'd0), .r_seq(rseq_s),
                .r_data(s_rdata[gi])
            );
        end
    endgenerate

    // 出数选择 (按 2 拍前的读者槽号); 非授权读输出 0 (不给陈旧数据)
    reg [63:0] rd0_mux, rd1_mux;
    integer mi;
    always @(*) begin
        rd0_mux = 64'd0;
        rd1_mux = 64'd0;
        for (mi = 0; mi < 8; mi = mi + 1) begin
            if (rd0_slot_d2 == mi[3:0]) rd0_mux = s_rdata[mi];
            if (rd1_slot_d2 == mi[3:0]) rd1_mux = s_rdata[mi];
        end
    end
    assign r_data0 = rd0_ok_d2 ? rd0_mux : 64'd0;
    assign r_data1 = rd1_ok_d2 ? rd1_mux : 64'd0;

    // ---- 守卫与观测 ----
    wire wr0_oor = wr_en0 && (w_conn0 >= 4'd8);
    wire wr1_oor = wr_en1 && (w_conn1 >= 4'd8);
    wire rd0_oor = rd_en0 && (r_conn0 >= 4'd8);
    wire rd1_oor = rd_en1 && (r_conn1 >= 4'd8);
    wire wr0_mis = wr_en0 && (w_conn0 < 4'd8) && (grant_port[w_conn0] != 1'b0);
    wire wr1_mis = wr_en1 && (w_conn1 < 4'd8) && (grant_port[w_conn1] != 1'b1);
    wire rd0_mis = rd_en0 && (r_conn0 < 4'd8) && (grant_port[r_conn0] != 1'b0);
    wire rd1_mis = rd_en1 && (r_conn1 < 4'd8) && (grant_port[r_conn1] != 1'b1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stat_retx_owner_mismatch <= 32'd0;
            stat_slot_oor             <= 32'd0;
        end else begin
            if (wr0_mis || wr1_mis || rd0_mis || rd1_mis)
                stat_retx_owner_mismatch <= stat_retx_owner_mismatch + 32'd1;
            if (wr0_oor || wr1_oor || rd0_oor || rd1_oor)
                stat_slot_oor <= stat_slot_oor + 32'd1;
        end
    end

endmodule
