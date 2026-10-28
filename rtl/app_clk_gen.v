`timescale 1ns/1ps
//=============================================================================
// app_clk_gen: P11 APP8 CDC 的第二时钟域 (156.25 MHz, 输入 = clk_gen_p6b 的 clk_in_100)
//=============================================================================
// 设计件 = _proj_10g/notes/p11_app8_cdc_20261029/DESIGN.md v4 §2.1。
//
// 为什么独立成模块（而不是改 clk_gen_p6b）：
//   clk_gen_p6b 是共享件（board/wrapper_p4.v:990 + tb/tb_clk_gen_p6b.v 4 例 +
//   probe 工程 + 夹具副本）。本模块只吃它已有的 clk_in_100 输出 ⇒ 既有模块零改动。
//
// 时钟：MMCME4_BASE，参数与 clk_gen_p6b 相同
//   100 MHz × 12.5 / 8.0 = 156.25 MHz。
//   clk_in_100 已是 BUFG 输出；MMCM CLKIN1 由 BUFG 驱动是合法的。
//
// 复位：与 clk_gen_p6b 同款 —— 异步置位 / 4 拍同步释放
//   rst_app = ~locked | rst_ext（高有效）
//   注意：CDC FIFO 的复位**不接本模块的 rst_app**（P6B 硬规则：两侧都接板级 reset_n）。
//
// SIM_BYPASS=1：行为级模型（TB 用；不改参数时周期 = CLKIN1_PERIOD_NS * DIV *
//   CLKOUT0_DIVIDE_F / MULT = 10 * 1 * 8 / 12.5 = 6.4 ns）。
//=============================================================================
module app_clk_gen #(
    parameter integer SIM_BYPASS       = 0,
    parameter         CLKIN1_PERIOD_NS = 10.000,
    parameter         CLKFBOUT_MULT_F  = 12.500,
    parameter integer DIVCLK_DIVIDE    = 1,
    parameter         CLKOUT0_DIVIDE_F = 8.000,
    parameter         REF_JITTER1      = 0.010
)(
    input  wire clk_in_100,     // clk_gen_p6b 的 BUFG 输出 (= 100 MHz)
    input  wire rst_ext,        // 外部复位，高有效，异步置位
    output wire clk_app,        // 156.25 MHz
    output wire locked_app,     // 只作观测/复位释放门（勿当复位直用）
    output wire rst_app         // 高有效，异步置位 / 4 拍同步释放
);

    wire locked_raw;
    wire rst_async = (~locked_raw) | rst_ext;

    generate
    if (SIM_BYPASS != 0) begin : g_sim
        // 行为级：周期由参数算出；锁定时序简单化（8 拍后 locked=1）
        localparam real T_APP = CLKIN1_PERIOD_NS * DIVCLK_DIVIDE * CLKOUT0_DIVIDE_F
                              / CLKFBOUT_MULT_F;
        reg clk_r = 1'b0;
        always #(T_APP/2.0) clk_r = ~clk_r;
        assign clk_app = clk_r;

        reg [3:0] lock_cnt = 4'd0;
        always @(posedge clk_r) if (&lock_cnt) lock_cnt <= lock_cnt; else lock_cnt <= lock_cnt + 4'd1;
        assign locked_raw = &lock_cnt;
    end else begin : g_real
        wire clk_fb;
        wire clk_out0;

        MMCME4_BASE #(
            .BANDWIDTH          ("OPTIMIZED"),
            .CLKFBOUT_MULT_F    (CLKFBOUT_MULT_F),
            .CLKFBOUT_PHASE     (0.000),
            .CLKIN1_PERIOD      (CLKIN1_PERIOD_NS),
            .CLKOUT0_DIVIDE_F   (CLKOUT0_DIVIDE_F),
            .CLKOUT0_DUTY_CYCLE (0.500),
            .CLKOUT0_PHASE      (0.000),
            .DIVCLK_DIVIDE      (DIVCLK_DIVIDE),
            .REF_JITTER1        (REF_JITTER1),
            .STARTUP_WAIT       ("FALSE")
        ) u_mmcm (
            .CLKOUT0  (clk_out0),
            .CLKFBOUT (clk_fb),
            .CLKFBIN  (clk_fb),
            .CLKIN1   (clk_in_100),
            .LOCKED   (locked_raw),
            .PWRDWN   (1'b0),
            .RST      (1'b0)
        );

        BUFG u_bufg_out (
            .I (clk_out0),
            .O (clk_app)
        );
    end
    endgenerate

    assign locked_app = locked_raw;

    // 异步置位 / 同步释放（与 clk_gen_p6b 同结构）
    (* ASYNC_REG = "TRUE" *) reg [3:0] rel_sr;
    always @(posedge clk_app or posedge rst_async) begin
        if (rst_async) rel_sr <= 4'h0;
        else           rel_sr <= {rel_sr[2:0], 1'b1};
    end
    assign rst_app = ~rel_sr[3];

endmodule
