`timescale 1ns/1ps
//=============================================================================
// axis_frame_mux8: 8→1 AXIS 帧级轮询仲裁（P11 APP8）
//=============================================================================
// 合同：
//   · data 布局 = {tkeep[7:0], tlast, tdata[63:0], tid[3:0]}（W=77，与 axis_pipe 同款）
//   · **帧级、非抢占**：一帧的第一拍被选中后，直到该帧 tlast 被接收才换源 ⇒
//     下游看到的 tid 在一帧内恒定。
//   · 选择拍不输出（busy 0→1 的下一拍才开始），代价 = 每帧 1 拍气泡。
//   · 轮询：每帧结束后 rr = 本帧源 + 1 ⇒ 8 个持续源在 8 帧窗口内各得 ≥1 帧。
//   · 活性：**首拍被接收前**若源撤 valid ⇒ 立即释放重仲裁（关闭/换流可发生在此窗口）；
//     首拍接收后必须等 tlast（app_pattern 的 W3 收尾保证会给）。
//   · 局限（已登记）：一条已进入下游帧器的帧若被零窗/死连接永久拒收，共享 TX 会停 —
//     这是"单帧器共享"的产品语义边界；mux 层无法撤销已交接的帧。
//=============================================================================
module axis_frame_mux8 #(
    parameter integer N = 8,
    parameter integer W = 77
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire [N*W-1:0] s_data,
    input  wire [N-1:0]   s_valid,
    output wire [N-1:0]   s_ready,
    output wire [W-1:0]   m_data,
    output wire           m_valid,
    input  wire           m_ready,
    // 观测：已发出帧数（首拍被接收 +1）；选择后源撤下的次数
    output reg  [31:0]    stat_frames,
    output reg  [31:0]    stat_abort_sel
);
    localparam [2:0] MSK3 = N - 1;

    reg        busy;
    reg        started;      // 首拍已被接收（帧正式占用 mux）
    reg [2:0]  sel;
    reg [2:0]  rr;

    integer k;
    reg [2:0] pick_idx;
    reg       any_v;
    always @* begin
        pick_idx = 3'd0;
        any_v    = 1'b0;
        for (k = 0; k < N; k = k + 1) begin
            if (!any_v && s_valid[(rr + k) & MSK3]) begin
                pick_idx = (rr + k) & MSK3;
                any_v    = 1'b1;
            end
        end
    end

    genvar gi;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : g_rdy
            assign s_ready[gi] = busy && (sel == gi) ? m_ready : 1'b0;
        end
    endgenerate

    assign m_data  = busy ? s_data[sel*W +: W] : {W{1'b0}};
    assign m_valid = busy && s_valid[sel];

    // tlast 位（布局固定）
    wire m_tlast = m_data[68];

    // 活性 (review H1): 选中后、**首拍被接收前**允许源撤 valid ⇒ 立即释放重仲裁。
    //   否则"选中同拍 ev_down 把 opener 撤下"会让 busy 永久锁死整条共享 TX。
    //   首拍接收后帧已进入下游流水，必须等 tlast（app_pattern 的 W3 保证会给）。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy    <= 1'b0;
            started <= 1'b0;
            sel     <= 3'd0;
            rr      <= 3'd0;
            stat_frames <= 32'd0;
            stat_abort_sel <= 32'd0;
        end else begin
            if (!busy) begin
                if (any_v) begin
                    busy    <= 1'b1;
                    started <= 1'b0;
                    sel     <= pick_idx;
                end
            end else if (!started) begin
                if (m_valid && m_ready) begin
                    stat_frames <= stat_frames + 32'd1;   // 只有首拍真的被接收才算一帧
                    if (m_tlast) begin
                        busy    <= 1'b0;
                        started <= 1'b0;
                        rr      <= (sel + 3'd1) & MSK3;
                    end else begin
                        started <= 1'b1;
                    end
                end else if (!s_valid[sel]) begin
                    // 源在首拍被接收前撤下（关闭/换流）⇒ 本帧未发出，释放
                    busy    <= 1'b0;
                    started <= 1'b0;
                    rr      <= (sel + 3'd1) & MSK3;
                    stat_abort_sel <= stat_abort_sel + 32'd1;
                end
            end else if (m_valid && m_ready && m_tlast) begin
                busy    <= 1'b0;
                started <= 1'b0;
                rr      <= (sel + 3'd1) & MSK3;
            end
        end
    end
endmodule
