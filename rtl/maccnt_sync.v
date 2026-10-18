`timescale 1ns/1ps
//=============================================================================
// maccnt_sync.v — P11 P2-甲 (N-4): 多比特计数器跨域事件镜像 (4 相 toggle/ack)
//=============================================================================
// 用途: 把源时钟域的自由回卷计数器 (rx cdc ovf / ch0 MAC TX frames+abort)
// 安全地镜像到 dp_clk 域进快照束 (snap_cdc 的前提 = din_b 必须是 dp 域寄存器)。
//
// ⛔ 禁止裸 2FF 多比特同步: 计数器进位时多 bit 同拍变化, 2FF 可能采到中间值。
//    本模块在源域**锁存**一份值 (src_lat), 只有它稳定后才翻 req_tgl; 目的域在
//    req 两级同步 + 一级稳定后采样, 取完回 ack_tgl ⇒ 源域才允许发起下一次。
//
// 协议 (标准 4 相):
//   源: !busy && src_tick ⇒ src_lat<=src_val; req_tgl<=~req_tgl; busy<=1
//       busy && (ack_s2==req_tgl) ⇒ busy<=0
//   目的: req_s1<=req_tgl; req_s2<=req_s1; req_s3<=req_s2;
//         data_s1<=src_lat; data_s2<=data_s1;
//         (req_s2 != ack_tgl && req_s3 == req_s2) ⇒ dst_val<=data_s2; ack_tgl<=req_s2
//   ⇒ req 稳定 ≥1 拍后采样, 数据已跨两级; 采样误差 ≤ 采样周期 + 握手延迟。
//
// 复位: 两侧各自 rst_n; 目的域复位后 dst_val=0 / ack_tgl=0; 源域 req_tgl=0。
// 采样节流由调用者给 src_tick (可恒 1; 源事件率须 < clk/8, 见设计 §3.4)。
//=============================================================================
module maccnt_sync #(
    parameter W = 32
) (
    // ---- 源域 ----
    input  wire         src_clk,
    input  wire         src_rst_n,
    input  wire [W-1:0] src_val,     // 源域当前计数值 (寄存器输出)
    input  wire         src_tick,    // 采样节流脉冲 (源域)
    // ---- 目的域 ----
    input  wire         dst_clk,
    input  wire         dst_rst_n,
    output reg  [W-1:0] dst_val      // 最近一次成功采样 (目的域寄存器)
);

    // ---------------- 源域侧 ----------------
    reg  [W-1:0] src_lat;
    reg          req_tgl;
    reg          busy;
    reg          ack_s1, ack_s2;    // ack_tgl (目的域) -> 源域

    // ---------------- 目的域侧 ----------------
    reg          req_s1, req_s2, req_s3;
    reg          ack_tgl;
    reg  [W-1:0] data_s1, data_s2;

    wire ack_ok   = (ack_s2 == req_tgl);
    wire dst_new  = (req_s2 != ack_tgl) && (req_s3 == req_s2);

    // 源域
    always @(posedge src_clk or negedge src_rst_n) begin
        if (!src_rst_n) begin
            src_lat <= {W{1'b0}};
            req_tgl <= 1'b0;
            busy    <= 1'b0;
            ack_s1  <= 1'b0;
            ack_s2  <= 1'b0;
        end else begin
            ack_s1 <= ack_tgl;      // 跨域: ack_tgl 由目的域寄存器产生
            ack_s2 <= ack_s1;
            if (!busy) begin
                if (src_tick) begin
                    src_lat <= src_val;
                    req_tgl <= ~req_tgl;
                    busy    <= 1'b1;
                end
            end else if (ack_ok) begin
                busy <= 1'b0;
            end
        end
    end

    // 目的域
    always @(posedge dst_clk or negedge dst_rst_n) begin
        if (!dst_rst_n) begin
            req_s1  <= 1'b0;
            req_s2  <= 1'b0;
            req_s3  <= 1'b0;
            ack_tgl <= 1'b0;
            data_s1 <= {W{1'b0}};
            data_s2 <= {W{1'b0}};
            dst_val <= {W{1'b0}};
        end else begin
            req_s1  <= req_tgl;     // 跨域: req_tgl 由源域寄存器产生
            req_s2  <= req_s1;
            req_s3  <= req_s2;
            data_s1 <= src_lat;     // 跨域: src_lat 在 req 变化前稳定
            data_s2 <= data_s1;
            if (dst_new) begin
                dst_val <= data_s2;
                ack_tgl <= req_s2;
            end
        end
    end

endmodule
