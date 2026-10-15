`timescale 1ns/1ps
// ===========================================================================
// tb_p9_swc.v -- P9 换流门 (TX_SWCLOSE: close-out-then-switch) 行为门
// ---------------------------------------------------------------------------
// 设计件 = _proj_10g/notes/p9_fix_upok_design_20261014/DESIGN_v2r3.md
//   (§4.1 判据 / §4.2 臂表 / v2r2 §6 的 u_swc5 / v2r3 §2 的 u_swc5b)
//
// 判据 (逐条):
//   P-A : 自事件拍起, DUT 交付的每个载荷字节 == "以 SEED 重开"的 TB 模型 (M_orc==0)
//   P-B : 换流后第一个载荷字节 bb0 === 8'h7F  (= SEED[31:24]; 见下方 DISCREPANCY 注)
//   P-C : 自事件拍起至 active 回升拍之间, 不得接受任何 (tkeep==0 && tlast==0) 字
//         (= opener 不得早于应用拍呈现)
//   STARTS: 事件后新起帧数 (opener beat 数) >= 1
//   TID : (仅 u_swc5h / R3-1 序列) 首个被接受的 opener 必须携带 m_tid == 目标槽 (4'd1)
//   以上五条按臂的组合 = "该臂是否红"; 运行级判据 = **实测红集 == 期望红集** (见下)。
//
// 编译方式 (由 run_tb_p9_swc.bat 传 -d; 必须恰好一个 RTL 面 + 一个期望面):
//   -d P9_SWC_ARM   : 活 rtl/app_pattern.v + .TX_SWCLOSE(1'b1)  (主臂)
//   -d P9_SWC_OFF   : 活 rtl/app_pattern.v + .TX_SWCLOSE(1'b0)  (常量级负对照)
//   -d P9_HEAD_RTL  : 未修 RTL 冻结件 (该件无 TX_SWCLOSE 参数 => 本模式不传该参数)
//   -d P9_EXP_FIXED : 期望红 = {}
//   -d P9_EXP_HEAD  : 期望红 = {swc0, swc1, swc2, swc5h}
//   -d P9_EXP_M6    : 期望红 = 全部 (v1 字面方程连"空闲到达的会话起点"一起丢)
//   -d P9_EXP_M6B   : 期望红 = {swc3, swc3b}
//   -d P9_EXP_M7    : 期望红 = {swc5h}
//   可选 -d P7B_10G : A2 整字路构型 (与逐字节构型各跑一遍)
//
// 臂表 (NALL=10, idx = 生成块下标):
//   0 u_swc0  : 同槽 ev_up 打在"帧首字装载拍" = opener 被消费后第 1 个 m_tvalid==0 拍
//               (**第 2 帧**; 见下面 §偏差登记: 第 1 帧那个拍对 P-3 是空判据)
//   1 u_swc1  : 同槽 ev_up 打在本帧第 4 个 payload beat (帧中段)
//   2 u_swc2  : 同 u_swc1 的事件 + rdy 低 40 拍 + 停滞期内同槽 ev_down (撤销) + 放开
//   3 u_swc3  : 第 20 个 payload beat 发 ev_down + rdy 低 300 拍; k=40 发同槽 ev_up
//   4 u_swc3b : 同 u_swc3 但 k=240
//   5 u_swc4  : 第 1 个 tlast 后 +40 拍发 ev_down; 观察到 active 落 0 稳 3 拍后发同槽
//               ev_up (idle 到达)
//   6 u_swc5a : frm_wait 冻结态(帧尾拍拉低 app_tx_ready) + 同槽 ev_up; tx_ok 在收尾字
//               被接受拍同拍回升 (delta 0); m_tready 全程 1
//   7 u_swc5b : 同 u_swc5a 但 tx_ok 迟 1 拍回升 (delta +1)
//   8 u_swc5c : 同 u_swc5a 但 tx_ok 早 1 拍回升 (delta -1, 即事件拍当拍)
//   9 u_swc5h : R3-1 序列 = frm_wait 冻结 + 同槽 ev_up -> rdy 拉低 -> 停滞期**异槽**
//               (槽 1) ev_up (请求交接) -> 放开 rdy 且 tx_ok 与收尾完成拍同拍回升; 判据加 TID
//               ⚠️ P9 R5 (裁决 B): frm_wait 态收尾变成"1 拍 else 支、不等 m_tready" ⇒
//               "停滞期交接"窗口收窄为**收尾完成拍 E+1**; 该臂 M7 判别力随之迁移
//               (见报告 §R5 变更表 / 咬点迁移到 idx10)
//  10 u_swcwing: **post-close 闲置翼** (设计件 v2r3 §5-1; R5 裁决 A 依据 (i)):
//               frm_wait 冻结 -> 同槽 ev_down (W3 收尾; app 转 idle 且 frm_wait 残留 1)
//               -> **idle 态拉高 tx_ok** (翼触发) -> 之后同槽 ev_up (合法新会话)
//               判据: 翼窗口内**不得有 active==0 时被接受的 opener** (流浪 opener)
//
// ⚠️ 打印字符串一律 ASCII (xsim 写中文会变 0xFF)。
// ⚠️ 模型重置 (M_mdl<=SEED) 只发生在"全局起点拍"与"每臂第一个事件拍" —— 本设计里
//    "事件拍"与"新流起点"是同一条判据 (P-A 的语义); 交接型事件 (u_swc5h 的异槽拍)
//    不重置 (否则会把"交接之后的合法续流"误判成失配 = TB 自己造假红)。
// ⚠️ app_tx_ready / ev_slot 在 u_swc5* 臂上是**组合**驱动 (寄存器化会整体迟一拍,
//    扫不到"收尾完成拍"那一格; 本仓坑 3/17 的"时钟化非阻塞"针对的是与 DUT 竞争的
//    0 延迟竞争, 而这里只读 TB 自己的状态寄存器, 无竞争)。
// ===========================================================================

`ifdef P9_SWC_ARM
  `define P9_HAS_SWC 1
  `define P9_MODE_TAG "SWC_ARM"
`elsif P9_SWC_OFF
  `define P9_HAS_SWC 1
  `define P9_MODE_TAG "SWC_OFF"
`elsif P9_HEAD_RTL
  `define P9_MODE_TAG "HEAD_RTL"
`else
  `P9_MODE_NOT_DEFINED__pass_-d_P9_SWC_ARM_or_-d_P9_SWC_OFF_or_-d_P9_HEAD_RTL
`endif

`ifdef P9_HAS_SWC
  `ifdef P9_SWC_ARM
    `define P9_SWC_BIND .TX_SWCLOSE(1'b1),
  `else
    `define P9_SWC_BIND .TX_SWCLOSE(1'b0),
  `endif
`else
  `define P9_SWC_BIND
`endif

`ifdef P9_EXP_FIXED
  `define P9_EXP_TAG "EXP_FIXED"
`elsif P9_EXP_HEAD
  `define P9_EXP_TAG "EXP_HEAD"
`elsif P9_EXP_M6
  `define P9_EXP_TAG "EXP_M6"
`elsif P9_EXP_M6B
  `define P9_EXP_TAG "EXP_M6B"
`elsif P9_EXP_M7
  `define P9_EXP_TAG "EXP_M7"
`else
  `P9_EXP_NOT_DEFINED__pass_-d_P9_EXP_FIXED_or_-d_P9_EXP_HEAD_or_-d_P9_EXP_M6_or_-d_P9_EXP_M6B_or_-d_P9_EXP_M7
`endif

module tb_p9_swc;
    reg clk, rst_n;
    initial clk = 1'b0;
    always #3.2 clk = ~clk;                       // 6.4 ns = 156.25 MHz

    localparam [63:0] SEED = 64'h9E3779B97F4A7C15;
    localparam integer NALL   = 11;
    localparam integer CY_TOT = 8000;

    // ---- tb 侧图案模型 (与 app / peer 同一递推) ----
    function [63:0] xs_next;
        input [63:0] s;  reg [63:0] t;
        begin t = s ^ (s << 13); t = t ^ (t >> 7); t = t ^ (t << 17); xs_next = t; end
    endfunction

    // ================= 全局起点脉冲 (所有臂同一拍) =================
    reg [1:0] est;
    always @(posedge clk) if (!rst_n) est <= 2'd0;
    else est <= (est == 2'd3) ? 2'd3 : (est + 2'd1);
    wire up_g = (est == 2'd1);

    // ================= DUT 端口阵列 (声明必须先于任何使用: 本仓坑 22) ============
    wire [63:0] w_d [0:NALL-1];
    wire [7:0]  w_k [0:NALL-1];
    wire        w_v [0:NALL-1];
    wire        w_l [0:NALL-1];
    wire [3:0]  w_tid [0:NALL-1];
    wire [31:0] w_txb [0:NALL-1], w_txf [0:NALL-1];
    wire        w_act [0:NALL-1], w_done [0:NALL-1];
    wire        w_fw  [0:NALL-1];   // DUT 的 frm_wait (见证: 收尾字分类)
    wire        w_swa [0:NALL-1];   // DUT 的 sw_apply (见证: 支配关系)

    // ================= 每臂激励状态机 =================
    // m_tready: **组合**驱动 (仅由本 TB 的状态寄存器导出, 无 DUT 反馈 ⇒ 无竞争/无环)。
    // ⚠️ 寄存器化会整体迟一拍 ⇒ 停滞期在"事件拍后第 2 拍"才生效, 收尾字会在被拉低前
    //    就被接受 (首轮实测: arm2 的换流在 ev_down 之前完成 ⇒ 迟到的 ev_down 把新会话
    //    合法关掉 ⇒ nst=0 的假红)。臂 2/3/4/9 的停滞必须**事件拍后第 1 拍**生效。
    wire [NALL-1:0] rdy;      // 组合赋值放在各臂状态机之后 (引用 s2_low 等声明, 坑 22)

    // ---- u_swc0: opener 被消费后第 1 个 m_tvalid==0 拍 (**第 2 帧**的那个) ----
    // ⚠️ 偏差登记 (轮报告 §异常-2): 设计件 §4.2 的定位法 = "opener 已消费后第 1 个
    //   m_tvalid==0 拍"。按字面取**第 1 帧**那个拍时, 该臂**无判别力** (P-3 的自洽性):
    //   事件拍上 app 同时 (a) 把 gen_byte=SEED[31:24]=0x7F 装进 stg/bcnt、(b) 被覆盖写
    //   推到 xs_next(SEED) —— 两条路的净结果与"复位生效"**逐字节相同** (设计件 §1.4
    //   自己写明 P-3 "与事件从未发生不可区分") ⇒ 首轮实测 HEAD=绿 (orc=0 bb0=7f)。
    //   ⇒ 本门把它打到**第 2 帧**装载拍 (流位置 = 1460 ≠ 0): 此时"复位被丢"会让流从
    //   1460 续走, 与"从 SEED 重开"的模型必然失配 ⇒ 判别力恢复 (HEAD=红)。
    reg  o0_seen, o0_done; reg [3:0] o0_n;
    wire beat_op0 = w_v[0] && rdy[0] && (w_k[0] == 8'h00) && !w_l[0];
    wire u0_up    = o0_seen && !o0_done && !w_v[0];
    always @(posedge clk) if (!rst_n) begin
        o0_seen <= 1'b0; o0_done <= 1'b0; o0_n <= 4'd0;
    end else begin
        if (beat_op0) o0_n <= o0_n + 4'd1;
        if (beat_op0 && (o0_n == 4'd1)) o0_seen <= 1'b1;   // 第 2 个 opener
        if (u0_up)    o0_done <= 1'b1;
    end

    // ---- u_swc1: 第 4 个 payload beat ----
    reg [3:0] p1_n; reg o1_done;
    wire beat_pl1 = w_v[1] && rdy[1] && (w_k[1] != 8'h00);
    wire u1_up    = (p1_n == 4'd3) && beat_pl1 && !o1_done;
    always @(posedge clk) if (!rst_n) begin p1_n <= 4'd0; o1_done <= 1'b0; end
    else begin
        if (beat_pl1) p1_n <= p1_n + 4'd1;
        if (u1_up)    o1_done <= 1'b1;
    end

    // ---- u_swc2: 第 4 个 payload beat + 停滞 + 停滞期内 ev_down + 放开 ----
    reg [3:0] p2_n; reg o2_done, s2_low; reg [15:0] s2_t;
    wire beat_pl2 = w_v[2] && rdy[2] && (w_k[2] != 8'h00);
    wire u2_up    = (p2_n == 4'd3) && beat_pl2 && !o2_done;
    wire u2_dn    = s2_low && (s2_t == 16'd10);
    always @(posedge clk) if (!rst_n) begin
        p2_n <= 4'd0; o2_done <= 1'b0; s2_low <= 1'b0; s2_t <= 16'd0;
    end else begin
        if (beat_pl2) p2_n <= p2_n + 4'd1;
        if (u2_up) begin o2_done <= 1'b1; s2_low <= 1'b1; s2_t <= 16'd0; end
        else if (s2_low) begin
            s2_t <= s2_t + 16'd1;
            if (s2_t == 16'd40) s2_low <= 1'b0;
        end
    end

    // ---- u_swc3 (k=40) / u_swc3b (k=240): ev_down 在第 20 个 payload beat ----
    reg [4:0] p3_n, p3b_n; reg s3_low, s3b_low, s3_done, s3b_done;
    reg [15:0] s3_c, s3b_c; reg o3_done, o3b_done;
    wire beat_pl3  = w_v[3] && rdy[3] && (w_k[3] != 8'h00);
    wire beat_pl3b = w_v[4] && rdy[4] && (w_k[4] != 8'h00);
    wire u3_dn     = (p3_n  == 5'd19) && beat_pl3  && !s3_done;
    wire u3b_dn    = (p3b_n == 5'd19) && beat_pl3b && !s3b_done;
    wire u3_up     = s3_done  && (s3_c  == 16'd39)  && !o3_done;
    wire u3b_up    = s3b_done && (s3b_c == 16'd239) && !o3b_done;
    always @(posedge clk) if (!rst_n) begin
        p3_n <= 5'd0; s3_low <= 1'b0; s3_done <= 1'b0; s3_c <= 16'd0; o3_done <= 1'b0;
        p3b_n <= 5'd0; s3b_low <= 1'b0; s3b_done <= 1'b0; s3b_c <= 16'd0; o3b_done <= 1'b0;
    end else begin
        if (beat_pl3) p3_n <= p3_n + 5'd1;
        if (u3_dn) begin s3_done <= 1'b1; s3_low <= 1'b1; s3_c <= 16'd0; end
        else if (s3_done) begin
            s3_c <= s3_c + 16'd1;
            if (s3_c == 16'd299) s3_low <= 1'b0;
        end
        if (u3_up) o3_done <= 1'b1;

        if (beat_pl3b) p3b_n <= p3b_n + 5'd1;
        if (u3b_dn) begin s3b_done <= 1'b1; s3b_low <= 1'b1; s3b_c <= 16'd0; end
        else if (s3b_done) begin
            s3b_c <= s3b_c + 16'd1;
            if (s3b_c == 16'd299) s3b_low <= 1'b0;
        end
        if (u3b_up) o3b_done <= 1'b1;
    end

    // ---- u_swc4: 第 1 个 tlast 后 +40 拍 ev_down; active 落 0 稳 3 拍后同槽 ev_up ----
    reg tl4_seen, s4_dn_done, s4_up_done; reg [15:0] s4_c, s4_idle_c;
    reg s4_dn, s4_up;
    wire beat_tl4 = w_v[5] && rdy[5] && w_l[5];
    always @(posedge clk) if (!rst_n) begin
        tl4_seen <= 1'b0; s4_dn_done <= 1'b0; s4_up_done <= 1'b0;
        s4_c <= 16'd0; s4_idle_c <= 16'd0; s4_dn <= 1'b0; s4_up <= 1'b0;
    end else begin
        if (beat_tl4) tl4_seen <= 1'b1;
        if (tl4_seen) s4_c <= s4_c + 16'd1;
        s4_dn <= tl4_seen && (s4_c == 16'd40) && !s4_dn_done;
        if (s4_dn) s4_dn_done <= 1'b1;
        if (s4_dn_done && !w_act[5]) s4_idle_c <= s4_idle_c + 16'd1;
        else                         s4_idle_c <= 16'd0;
        s4_up <= (s4_idle_c == 16'd3) && !s4_up_done;
        if (s4_up) s4_up_done <= 1'b1;
    end

    // ---- u_swc5a/b/c: frm_wait 冻结态 + 同槽 ev_up + tx_ok 回升扫描 {delta 0/+1/-1} ----
    // 冻结: 帧尾字 (tlast) 被接受的**同拍**拉低 app_tx_ready => 收帧拍见 tx_ok=0 => frm_wait
    // 事件: 冻结后 40 拍发同槽 ev_up; m_tready 全程 1
    // 完成拍 C = 事件拍后第 1 拍 (收尾字 m_tready=1 即被接受)
    reg pk5, pk6, pk7; reg [15:0] s5_c, s6_c, s7_c, e6_c; reg o5_done, o6_done, o7_done;
    wire beat_tl5 = w_v[6] && rdy[6] && w_l[6];
    wire beat_tl6 = w_v[7] && rdy[7] && w_l[7];
    wire beat_tl7 = w_v[8] && rdy[8] && w_l[8];
    wire u5_up = pk5 && (s5_c == 16'd40) && !o5_done;
    wire u6_up = pk6 && (s6_c == 16'd40) && !o6_done;
    wire u7_up = pk7 && (s7_c == 16'd40) && !o7_done;
    always @(posedge clk) if (!rst_n) begin
        pk5 <= 1'b0; s5_c <= 16'd0; o5_done <= 1'b0;
        pk6 <= 1'b0; s6_c <= 16'd0; o6_done <= 1'b0; e6_c <= 16'd0;
        pk7 <= 1'b0; s7_c <= 16'd0; o7_done <= 1'b0;
    end else begin
        if (beat_tl5) pk5 <= 1'b1;
        if (pk5) s5_c <= s5_c + 16'd1;
        if (u5_up) o5_done <= 1'b1;

        if (beat_tl6) pk6 <= 1'b1;
        if (pk6) s6_c <= s6_c + 16'd1;
        if (u6_up) o6_done <= 1'b1;
        if (o6_done) e6_c <= e6_c + 16'd1;

        if (beat_tl7) pk7 <= 1'b1;
        if (pk7) s7_c <= s7_c + 16'd1;
        if (u7_up) o7_done <= 1'b1;
    end

    // ---- u_swc5h: R3-1 序列 ----
    reg pk8; reg [15:0] s8_c, h8_c; reg o8_done, o8b_done, h8_low, h8_rel;
    wire beat_tl8 = w_v[9] && rdy[9] && w_l[9];
    wire u8_up   = pk8 && (s8_c == 16'd40) && !o8_done;         // 同槽 (槽 0): 本臂"事件拍"
    wire u8_up2  = o8_done && (h8_c == 16'd0) && !o8b_done;     // 异槽 (槽 1) 事件 = 收尾完成拍 E+1
    //   ⚠️ P9 R5: 裁决 B 让 frm_wait 态收尾 = 1 拍 else 支 (不等 m_tready)
    //   ⇒ "交接落在收尾完成拍" 只能在 E+1 (旧值 = E+3 时应用已完成、事件退化成 A3 pending)
    always @(posedge clk) if (!rst_n) begin
        pk8 <= 1'b0; s8_c <= 16'd0; h8_c <= 16'd0; o8_done <= 1'b0; o8b_done <= 1'b0;
        h8_low <= 1'b0; h8_rel <= 1'b0;
    end else begin
        if (beat_tl8) pk8 <= 1'b1;
        if (pk8 && !o8_done) s8_c <= s8_c + 16'd1;
        if (u8_up) begin o8_done <= 1'b1; h8_low <= 1'b1; h8_c <= 16'd0; end
        else if (o8_done) h8_c <= h8_c + 16'd1;
        // 放开 rdy: 事件后第 5 拍置 h8_low<=0 => rdy 在 E+6 高 = 收尾字被接受拍
        if (o8_done && (h8_c == 16'd4)) begin h8_low <= 1'b0; h8_rel <= 1'b1; end
        if (u8_up2) o8b_done <= 1'b1;
    end

    // ---- u_swcwing (idx10): post-close 闲置翼 (设计件 v2r3 §5-1; R5 裁决 A 依据 (i)) ----
    //   1) 第 1 帧 tlast 拍拉低 tx_ok ⇒ frm_wait 冻结
    //   2) 冻结后 40 拍发同槽 ev_down ⇒ W3 收尾 ⇒ app idle 且 frm_wait 残留 1
    //   3) 观察到 active==0 稳 5 拍 ⇒ **拉高 tx_ok** (翼触发)
    //      固定设计: 守卫 (closing || !active) 拦住 :922 ⇒ 无动作;
    //      未修/旧守卫 (closing || sw_apply): 两项全假 ⇒ :922 抢置 ⇒ 以 active=0
    //      呈现"流浪 opener" (= M_wbad 违规计数, 本臂判据)
    //   4) 再过 20 拍发同槽 ev_up (合法新会话) ⇒ 从 SEED 重开 (P-A/P-B)
    reg pk10; reg [15:0] s10_c, i10_c, t10_c; reg o10_dn, o10_up, w10_rel;
    wire beat_tl10 = w_v[10] && rdy[10] && w_l[10];
    wire u10_dn = pk10 && (s10_c == 16'd40) && !o10_dn;
    wire u10_up = w10_rel && (t10_c == 16'd20) && !o10_up;
    always @(posedge clk) if (!rst_n) begin
        pk10 <= 1'b0; s10_c <= 16'd0; i10_c <= 16'd0; t10_c <= 16'd0;
        o10_dn <= 1'b0; o10_up <= 1'b0; w10_rel <= 1'b0;
    end else begin
        if (beat_tl10) pk10 <= 1'b1;
        if (pk10 && !o10_dn) s10_c <= s10_c + 16'd1;
        if (u10_dn) o10_dn <= 1'b1;
        if (o10_dn && !w_act[10]) i10_c <= i10_c + 16'd1;
        else                       i10_c <= 16'd0;
        if (i10_c == 16'd5) w10_rel <= 1'b1;
        if (w10_rel) t10_c <= t10_c + 16'd1;
        if (u10_up) o10_up <= 1'b1;
    end

    // ---- m_tready 组合赋值 (见文件头上方的"组合驱动"注) ----
    assign rdy[0] = 1'b1;
    assign rdy[1] = 1'b1;
    assign rdy[2] = ~s2_low;
    assign rdy[3] = ~s3_low;
    assign rdy[4] = ~s3b_low;
    assign rdy[5] = 1'b1;
    assign rdy[6] = 1'b1;
    assign rdy[7] = 1'b1;
    assign rdy[8] = 1'b1;
    assign rdy[9] = ~h8_low;
    assign rdy[10] = 1'b1;

    // ---- app_tx_ready (组合; 见文件头说明) ----
    wire [NALL-1:0] txok;
    assign txok[5:0] = 6'h3F;
    assign txok[6] = !pk5 || o5_done;                       // delta 0 (C 拍高)
    assign txok[7] = !pk6 || (o6_done && (e6_c >= 16'd1));  // delta +1 (C+1 拍高)
    assign txok[8] = !pk7 || (s7_c >= 16'd40);              // delta -1 (事件拍高 = C-1)
    assign txok[9] = !pk8 || o8_done;                       // R3-1: 收尾完成拍 (E+1) 回升
    assign txok[10] = !pk10 || w10_rel;                     // 闲置翼: idle 态回升

    // ---- 事件向量 ----
    wire [NALL-1:0] ev_u;
    wire [NALL-1:0] ev_d;
    assign ev_u[0] = up_g | u0_up;
    assign ev_u[1] = up_g | u1_up;
    assign ev_u[2] = up_g | u2_up;
    assign ev_u[3] = up_g | u3_up;
    assign ev_u[4] = up_g | u3b_up;
    assign ev_u[5] = up_g | s4_up;
    assign ev_u[6] = up_g | u5_up;
    assign ev_u[7] = up_g | u6_up;
    assign ev_u[8] = up_g | u7_up;
    assign ev_u[9] = up_g | u8_up | u8_up2;
    assign ev_u[10] = up_g | u10_up;
    assign ev_d[0] = 1'b0;
    assign ev_d[1] = 1'b0;
    assign ev_d[2] = u2_dn;
    assign ev_d[3] = u3_dn;
    assign ev_d[4] = u3b_dn;
    assign ev_d[5] = s4_dn;
    assign ev_d[6] = 1'b0;
    assign ev_d[7] = 1'b0;
    assign ev_d[8] = 1'b0;
    assign ev_d[9] = 1'b0;
    assign ev_d[10] = u10_dn;
    // 槽号 (组合): 全部槽 0; u_swc5h 的异槽事件用槽 1
    wire [3:0] ev_slot9 = u8_up2 ? 4'd1 : 4'd0;
    wire [3:0] ev_slot0 = 4'd0;
    wire [3:0] ev_slotw = 4'd0;   // 闲置翼臂 = 槽 0

    // ---- 模型重置点 = 全局起点 + 各臂第一个事件 (u_swc5h 的异槽拍不重置) ----
    wire [NALL-1:0] ev_own;   // 本臂自有事件 (不含全局起点) = P-B/TID 的捕获窗口起点
    assign ev_own[0] = u0_up;
    assign ev_own[1] = u1_up;
    assign ev_own[2] = u2_up;
    assign ev_own[3] = u3_up;
    assign ev_own[4] = u3b_up;
    assign ev_own[5] = s4_up;
    assign ev_own[6] = u5_up;
    assign ev_own[7] = u6_up;
    assign ev_own[8] = u7_up;
    assign ev_own[9] = u8_up;
    assign ev_own[10] = u10_up;
    wire [NALL-1:0] up_w;
    assign up_w[0] = up_g | u0_up;
    assign up_w[1] = up_g | u1_up;
    assign up_w[2] = up_g | u2_up;
    assign up_w[3] = up_g | u3_up;
    assign up_w[4] = up_g | u3b_up;
    assign up_w[5] = up_g | s4_up;
    assign up_w[6] = up_g | u5_up;
    assign up_w[7] = up_g | u6_up;
    assign up_w[8] = up_g | u7_up;
    assign up_w[9] = up_g | u8_up;
    assign up_w[10] = up_g | u10_up;

    // ================= DUT 阵列 (端口阵列声明在文件上部) =================
    app_pattern #(`P9_SWC_BIND .TX_BYTES(32'd3000), .TX_SEGSZ(12'd1460),
                  .AUTO_CLOSE(1'b0), .TX_CONTINUOUS(1'b1)) u0 (
        .clk(clk), .rst_n(rst_n), .ev_up(ev_u[0]), .ev_down(ev_d[0]), .ev_slot(ev_slot0),
        .m_tdata(w_d[0]), .m_tkeep(w_k[0]), .m_tvalid(w_v[0]), .m_tready(rdy[0]),
        .m_tlast(w_l[0]), .m_tid(w_tid[0]), .app_tx_ready({16{txok[0]}}),
        .close_req(), .close_id(),
        .rx_tdata(64'd0), .rx_tkeep(8'h00), .rx_tvalid(1'b0), .rx_tready(),
        .rx_tlast(1'b0), .rx_tid(4'd0), .i_bad_frame(16'd0),
        .stat_tx_bytes(w_txb[0]), .stat_tx_frames(w_txf[0]), .stat_bad_frames(),
        .stat_rx_bytes(), .stat_mismatch(),
        .active(w_act[0]), .act_id(), .done(w_done[0]), .dbg_lfsr(), .led(),
        .stat_frmwait_cyc(), .stat_bp_cyc()
    );
    app_pattern #(`P9_SWC_BIND .TX_BYTES(32'd3000), .TX_SEGSZ(12'd1460),
                  .AUTO_CLOSE(1'b0), .TX_CONTINUOUS(1'b1)) u1 (
        .clk(clk), .rst_n(rst_n), .ev_up(ev_u[1]), .ev_down(ev_d[1]), .ev_slot(ev_slot0),
        .m_tdata(w_d[1]), .m_tkeep(w_k[1]), .m_tvalid(w_v[1]), .m_tready(rdy[1]),
        .m_tlast(w_l[1]), .m_tid(w_tid[1]), .app_tx_ready({16{txok[1]}}),
        .close_req(), .close_id(),
        .rx_tdata(64'd0), .rx_tkeep(8'h00), .rx_tvalid(1'b0), .rx_tready(),
        .rx_tlast(1'b0), .rx_tid(4'd0), .i_bad_frame(16'd0),
        .stat_tx_bytes(w_txb[1]), .stat_tx_frames(w_txf[1]), .stat_bad_frames(),
        .stat_rx_bytes(), .stat_mismatch(),
        .active(w_act[1]), .act_id(), .done(w_done[1]), .dbg_lfsr(), .led(),
        .stat_frmwait_cyc(), .stat_bp_cyc()
    );
    app_pattern #(`P9_SWC_BIND .TX_BYTES(32'd3000), .TX_SEGSZ(12'd1460),
                  .AUTO_CLOSE(1'b0), .TX_CONTINUOUS(1'b1)) u2 (
        .clk(clk), .rst_n(rst_n), .ev_up(ev_u[2]), .ev_down(ev_d[2]), .ev_slot(ev_slot0),
        .m_tdata(w_d[2]), .m_tkeep(w_k[2]), .m_tvalid(w_v[2]), .m_tready(rdy[2]),
        .m_tlast(w_l[2]), .m_tid(w_tid[2]), .app_tx_ready({16{txok[2]}}),
        .close_req(), .close_id(),
        .rx_tdata(64'd0), .rx_tkeep(8'h00), .rx_tvalid(1'b0), .rx_tready(),
        .rx_tlast(1'b0), .rx_tid(4'd0), .i_bad_frame(16'd0),
        .stat_tx_bytes(w_txb[2]), .stat_tx_frames(w_txf[2]), .stat_bad_frames(),
        .stat_rx_bytes(), .stat_mismatch(),
        .active(w_act[2]), .act_id(), .done(w_done[2]), .dbg_lfsr(), .led(),
        .stat_frmwait_cyc(), .stat_bp_cyc()
    );
    app_pattern #(`P9_SWC_BIND .TX_BYTES(32'd3000), .TX_SEGSZ(12'd1460),
                  .AUTO_CLOSE(1'b0), .TX_CONTINUOUS(1'b1)) u3 (
        .clk(clk), .rst_n(rst_n), .ev_up(ev_u[3]), .ev_down(ev_d[3]), .ev_slot(ev_slot0),
        .m_tdata(w_d[3]), .m_tkeep(w_k[3]), .m_tvalid(w_v[3]), .m_tready(rdy[3]),
        .m_tlast(w_l[3]), .m_tid(w_tid[3]), .app_tx_ready({16{txok[3]}}),
        .close_req(), .close_id(),
        .rx_tdata(64'd0), .rx_tkeep(8'h00), .rx_tvalid(1'b0), .rx_tready(),
        .rx_tlast(1'b0), .rx_tid(4'd0), .i_bad_frame(16'd0),
        .stat_tx_bytes(w_txb[3]), .stat_tx_frames(w_txf[3]), .stat_bad_frames(),
        .stat_rx_bytes(), .stat_mismatch(),
        .active(w_act[3]), .act_id(), .done(w_done[3]), .dbg_lfsr(), .led(),
        .stat_frmwait_cyc(), .stat_bp_cyc()
    );
    app_pattern #(`P9_SWC_BIND .TX_BYTES(32'd3000), .TX_SEGSZ(12'd1460),
                  .AUTO_CLOSE(1'b0), .TX_CONTINUOUS(1'b1)) u3b (
        .clk(clk), .rst_n(rst_n), .ev_up(ev_u[4]), .ev_down(ev_d[4]), .ev_slot(ev_slot0),
        .m_tdata(w_d[4]), .m_tkeep(w_k[4]), .m_tvalid(w_v[4]), .m_tready(rdy[4]),
        .m_tlast(w_l[4]), .m_tid(w_tid[4]), .app_tx_ready({16{txok[4]}}),
        .close_req(), .close_id(),
        .rx_tdata(64'd0), .rx_tkeep(8'h00), .rx_tvalid(1'b0), .rx_tready(),
        .rx_tlast(1'b0), .rx_tid(4'd0), .i_bad_frame(16'd0),
        .stat_tx_bytes(w_txb[4]), .stat_tx_frames(w_txf[4]), .stat_bad_frames(),
        .stat_rx_bytes(), .stat_mismatch(),
        .active(w_act[4]), .act_id(), .done(w_done[4]), .dbg_lfsr(), .led(),
        .stat_frmwait_cyc(), .stat_bp_cyc()
    );
    app_pattern #(`P9_SWC_BIND .TX_BYTES(32'd3000), .TX_SEGSZ(12'd1460),
                  .AUTO_CLOSE(1'b0), .TX_CONTINUOUS(1'b1)) u4 (
        .clk(clk), .rst_n(rst_n), .ev_up(ev_u[5]), .ev_down(ev_d[5]), .ev_slot(ev_slot0),
        .m_tdata(w_d[5]), .m_tkeep(w_k[5]), .m_tvalid(w_v[5]), .m_tready(rdy[5]),
        .m_tlast(w_l[5]), .m_tid(w_tid[5]), .app_tx_ready({16{txok[5]}}),
        .close_req(), .close_id(),
        .rx_tdata(64'd0), .rx_tkeep(8'h00), .rx_tvalid(1'b0), .rx_tready(),
        .rx_tlast(1'b0), .rx_tid(4'd0), .i_bad_frame(16'd0),
        .stat_tx_bytes(w_txb[5]), .stat_tx_frames(w_txf[5]), .stat_bad_frames(),
        .stat_rx_bytes(), .stat_mismatch(),
        .active(w_act[5]), .act_id(), .done(w_done[5]), .dbg_lfsr(), .led(),
        .stat_frmwait_cyc(), .stat_bp_cyc()
    );
    app_pattern #(`P9_SWC_BIND .TX_BYTES(32'd3000), .TX_SEGSZ(12'd1460),
                  .AUTO_CLOSE(1'b0), .TX_CONTINUOUS(1'b1)) u5a (
        .clk(clk), .rst_n(rst_n), .ev_up(ev_u[6]), .ev_down(ev_d[6]), .ev_slot(ev_slot0),
        .m_tdata(w_d[6]), .m_tkeep(w_k[6]), .m_tvalid(w_v[6]), .m_tready(rdy[6]),
        .m_tlast(w_l[6]), .m_tid(w_tid[6]), .app_tx_ready({16{txok[6]}}),
        .close_req(), .close_id(),
        .rx_tdata(64'd0), .rx_tkeep(8'h00), .rx_tvalid(1'b0), .rx_tready(),
        .rx_tlast(1'b0), .rx_tid(4'd0), .i_bad_frame(16'd0),
        .stat_tx_bytes(w_txb[6]), .stat_tx_frames(w_txf[6]), .stat_bad_frames(),
        .stat_rx_bytes(), .stat_mismatch(),
        .active(w_act[6]), .act_id(), .done(w_done[6]), .dbg_lfsr(), .led(),
        .stat_frmwait_cyc(), .stat_bp_cyc()
    );
    app_pattern #(`P9_SWC_BIND .TX_BYTES(32'd3000), .TX_SEGSZ(12'd1460),
                  .AUTO_CLOSE(1'b0), .TX_CONTINUOUS(1'b1)) u5b (
        .clk(clk), .rst_n(rst_n), .ev_up(ev_u[7]), .ev_down(ev_d[7]), .ev_slot(ev_slot0),
        .m_tdata(w_d[7]), .m_tkeep(w_k[7]), .m_tvalid(w_v[7]), .m_tready(rdy[7]),
        .m_tlast(w_l[7]), .m_tid(w_tid[7]), .app_tx_ready({16{txok[7]}}),
        .close_req(), .close_id(),
        .rx_tdata(64'd0), .rx_tkeep(8'h00), .rx_tvalid(1'b0), .rx_tready(),
        .rx_tlast(1'b0), .rx_tid(4'd0), .i_bad_frame(16'd0),
        .stat_tx_bytes(w_txb[7]), .stat_tx_frames(w_txf[7]), .stat_bad_frames(),
        .stat_rx_bytes(), .stat_mismatch(),
        .active(w_act[7]), .act_id(), .done(w_done[7]), .dbg_lfsr(), .led(),
        .stat_frmwait_cyc(), .stat_bp_cyc()
    );
    app_pattern #(`P9_SWC_BIND .TX_BYTES(32'd3000), .TX_SEGSZ(12'd1460),
                  .AUTO_CLOSE(1'b0), .TX_CONTINUOUS(1'b1)) u5c (
        .clk(clk), .rst_n(rst_n), .ev_up(ev_u[8]), .ev_down(ev_d[8]), .ev_slot(ev_slot0),
        .m_tdata(w_d[8]), .m_tkeep(w_k[8]), .m_tvalid(w_v[8]), .m_tready(rdy[8]),
        .m_tlast(w_l[8]), .m_tid(w_tid[8]), .app_tx_ready({16{txok[8]}}),
        .close_req(), .close_id(),
        .rx_tdata(64'd0), .rx_tkeep(8'h00), .rx_tvalid(1'b0), .rx_tready(),
        .rx_tlast(1'b0), .rx_tid(4'd0), .i_bad_frame(16'd0),
        .stat_tx_bytes(w_txb[8]), .stat_tx_frames(w_txf[8]), .stat_bad_frames(),
        .stat_rx_bytes(), .stat_mismatch(),
        .active(w_act[8]), .act_id(), .done(w_done[8]), .dbg_lfsr(), .led(),
        .stat_frmwait_cyc(), .stat_bp_cyc()
    );
    app_pattern #(`P9_SWC_BIND .TX_BYTES(32'd3000), .TX_SEGSZ(12'd1460),
                  .AUTO_CLOSE(1'b0), .TX_CONTINUOUS(1'b1)) u5h (
        .clk(clk), .rst_n(rst_n), .ev_up(ev_u[9]), .ev_down(ev_d[9]), .ev_slot(ev_slot9),
        .m_tdata(w_d[9]), .m_tkeep(w_k[9]), .m_tvalid(w_v[9]), .m_tready(rdy[9]),
        .m_tlast(w_l[9]), .m_tid(w_tid[9]), .app_tx_ready({16{txok[9]}}),
        .close_req(), .close_id(),
        .rx_tdata(64'd0), .rx_tkeep(8'h00), .rx_tvalid(1'b0), .rx_tready(),
        .rx_tlast(1'b0), .rx_tid(4'd0), .i_bad_frame(16'd0),
        .stat_tx_bytes(w_txb[9]), .stat_tx_frames(w_txf[9]), .stat_bad_frames(),
        .stat_rx_bytes(), .stat_mismatch(),
        .active(w_act[9]), .act_id(), .done(w_done[9]), .dbg_lfsr(), .led(),
        .stat_frmwait_cyc(), .stat_bp_cyc()
    );
    app_pattern #(`P9_SWC_BIND .TX_BYTES(32'd3000), .TX_SEGSZ(12'd1460),
                  .AUTO_CLOSE(1'b0), .TX_CONTINUOUS(1'b1)) u10 (
        .clk(clk), .rst_n(rst_n), .ev_up(ev_u[10]), .ev_down(ev_d[10]), .ev_slot(ev_slotw),
        .m_tdata(w_d[10]), .m_tkeep(w_k[10]), .m_tvalid(w_v[10]), .m_tready(rdy[10]),
        .m_tlast(w_l[10]), .m_tid(w_tid[10]), .app_tx_ready({16{txok[10]}}),
        .close_req(), .close_id(),
        .rx_tdata(64'd0), .rx_tkeep(8'h00), .rx_tvalid(1'b0), .rx_tready(),
        .rx_tlast(1'b0), .rx_tid(4'd0), .i_bad_frame(16'd0),
        .stat_tx_bytes(w_txb[10]), .stat_tx_frames(w_txf[10]), .stat_bad_frames(),
        .stat_rx_bytes(), .stat_mismatch(),
        .active(w_act[10]), .act_id(), .done(w_done[10]), .dbg_lfsr(), .led(),
        .stat_frmwait_cyc(), .stat_bp_cyc()
    );

    // ---- 见证引线: frm_wait (收尾字分类) + sw_apply (支配关系监视) ----
    //   ⚠️ `sw_apply` 是 P9 新增网名 ⇒ 冻结件 (P9 前) **没有它** ⇒ 该模式必须钉 0,
    //      否则 R5 的 H/H10 运行会在 elaborate 期挂掉 (w_swa 引用了不存在的层次名)。
    //      支配判据本身只在 SWC_OK=1 运行 (`-d P9_SWC_ARM`) 上判 ⇒ 与钉 0 不相交。
    assign w_fw[0]  = u0.frm_wait;
    assign w_fw[1]  = u1.frm_wait;
    assign w_fw[2]  = u2.frm_wait;
    assign w_fw[3]  = u3.frm_wait;
    assign w_fw[4]  = u3b.frm_wait;
    assign w_fw[5]  = u4.frm_wait;
    assign w_fw[6]  = u5a.frm_wait;
    assign w_fw[7]  = u5b.frm_wait;
    assign w_fw[8]  = u5c.frm_wait;
    assign w_fw[9]  = u5h.frm_wait;
    assign w_fw[10] = u10.frm_wait;
`ifdef P9_HEAD_RTL
    assign w_swa[0]  = 1'b0;   // 冻结件无 sw_apply (P9 前) => 该模式支配判据 = n/a
    assign w_swa[1]  = 1'b0;
    assign w_swa[2]  = 1'b0;
    assign w_swa[3]  = 1'b0;
    assign w_swa[4]  = 1'b0;
    assign w_swa[5]  = 1'b0;
    assign w_swa[6]  = 1'b0;
    assign w_swa[7]  = 1'b0;
    assign w_swa[8]  = 1'b0;
    assign w_swa[9]  = 1'b0;
    assign w_swa[10] = 1'b0;
`else
    assign w_swa[0]  = u0.sw_apply;
    assign w_swa[1]  = u1.sw_apply;
    assign w_swa[2]  = u2.sw_apply;
    assign w_swa[3]  = u3.sw_apply;
    assign w_swa[4]  = u3b.sw_apply;
    assign w_swa[5]  = u4.sw_apply;
    assign w_swa[6]  = u5a.sw_apply;
    assign w_swa[7]  = u5b.sw_apply;
    assign w_swa[8]  = u5c.sw_apply;
    assign w_swa[9]  = u5h.sw_apply;
    assign w_swa[10] = u10.sw_apply;
`endif

    // ================= 全局时钟计数 =================
    reg [31:0] cyc;
    always @(posedge clk) if (!rst_n) cyc <= 32'd0; else cyc <= cyc + 32'd1;

    // ================= 每臂记账 =================
    reg [63:0] M_mdl [0:NALL-1];      // 图案模型
    reg [31:0] M_orc [0:NALL-1];      // P-A: 图案失配字节数
    reg [31:0] M_nst [0:NALL-1];      // STARTS: 事件后 opener (keep==0 && !last) 接受数
    reg [31:0] M_pcv [0:NALL-1];      // P-C: 窗口内接受的 opener 数 (违规计数)
    reg [31:0] M_nclw[0:NALL-1];      // 见证: 被接受的 W3 收尾字 (keep==0 && last==1) 数
    reg [31:0] M_nclwf[0:NALL-1];     //   ...其中 **frm_wait 态**那一类 (R5 裁决 B 后应恒 0)
    reg [31:0] M_wbad[0:NALL-1];      // 闲置翼违规: active==0 时被接受的 opener 数
    reg [31:0] M_domv[0:NALL-1];      // 支配违规: sw_apply && active (SWC_OK=1 下应恒 0)
    reg        wing_win[0:NALL-1];    // 闲置翼窗口 (ev_down 开, 末次 ev_up 关)
    reg        pc_win[0:NALL-1];      // P-C 窗口: 事件拍开, active **先落后再回升**才关
    reg        pc_fell[0:NALL-1];     // (见下面逐条注释: 只按"采到 active==1"关会漏计早 opener)
    reg        M_bb0v[0:NALL-1];      // P-B: bb0 已捕获
    reg [7:0]  M_bb0 [0:NALL-1];      // P-B: 事件后首个载荷字节
    reg        M_tidv[0:NALL-1];      // TID: 首个 opener 的 tid 已捕获
    reg [3:0]  M_tid [0:NALL-1];
    reg        ev_seen[0:NALL-1];     // 事件已发生 (sticky)

    genvar gi;
    generate
    for (gi = 0; gi < NALL; gi = gi + 1) begin : GB
        always @(posedge clk) begin
            if (!rst_n) begin
                M_mdl[gi] <= SEED; M_orc[gi] <= 0; M_nst[gi] <= 0;
                M_pcv[gi] <= 0; M_nclw[gi] <= 0; M_nclwf[gi] <= 0; pc_win[gi] <= 0; pc_fell[gi] <= 0;
                M_wbad[gi] <= 0; M_domv[gi] <= 0; wing_win[gi] <= 0;
                M_bb0v[gi] <= 0; M_bb0[gi] <= 0;
                M_tidv[gi] <= 0; M_tid[gi] <= 0; ev_seen[gi] <= 0;
            end else begin
                // ---- P-C 窗口: 事件拍开窗; 关窗条件 = "窗口内先见到 active==0,
                //      之后再见 active==1" (= active 的**回升**) ----
                //   ⚠️ 只按"采到 active==1 就关"是**哑判据**: 换流收尾期间 active 恒 1,
                //      而收尾完成拍上采到的仍是 1 (它在该拍末才落 0) ⇒ 窗口会在收尾完成
                //      拍提前关闭, 把"应用拍当拍呈现的早 opener"整个漏掉 (首轮实测:
                //      M7 突变臂上 P-C 报绿而 TID 报红)。回落沿采样比实际晚一拍, 必须
                //      用"先落后升"两态判定。
                // ---- 闲置翼窗口 (idx10): ev_down 开, 末次 ev_up 关 ----
                if (u10_dn) wing_win[gi] <= 1'b1;
                if (u10_up) wing_win[gi] <= 1'b0;

                // ---- R5 见证 1: 支配关系 (sw_apply ⇒ !active); 仅 SWC_OK=1 运行 ----
`ifdef P9_SWC_ARM
                if (w_swa[gi] && w_act[gi]) begin
                    M_domv[gi] = M_domv[gi] + 1;
                    if (M_domv[gi] <= 32'd4)
                        $display("  [DOM-VIOL] sw_apply && active arm=%0d cyc=%0d", gi, cyc);
                end
`endif
                if (up_w[gi]) begin
                    pc_win[gi]  <= 1'b1;
                    pc_fell[gi] <= 1'b0;
                end else if (pc_win[gi]) begin
                    if (w_act[gi] == 1'b1) begin
                        if (pc_fell[gi]) pc_win[gi] <= 1'b0;   // active 回升 ⇒ 关窗
                    end else begin
                        pc_fell[gi] <= 1'b1;                   // 窗口内见到 active=0
                    end
                end

                // ---- 接受一个 beat ----
                if (w_v[gi] && rdy[gi]) begin
                    // 帧起始拍 = opener (keep==0 且 !tlast); 0 载荷收尾字 (tlast) 不算
                    if ((w_k[gi] == 8'h00) && !w_l[gi]) begin
                        M_nst[gi] = M_nst[gi] + 1;
                        if (ev_seen[gi] && !M_tidv[gi]) begin
                            M_tid[gi] = w_tid[gi];
                            M_tidv[gi] = 1'b1;
                        end
                    end
                    if ((w_k[gi] == 8'h00) && w_l[gi]) begin
                        if (w_fw[gi]) M_nclwf[gi] = M_nclwf[gi] + 1;   // frm_wait 态收尾字
                        else          M_nclw[gi]  = M_nclw[gi]  + 1;   // 非 frm_wait 收尾字
                    end
                    // 闲置翼违规 (仅 idx10 窗口内): active==0 时被接受的 opener
                    if (wing_win[gi] && (w_act[gi] == 1'b0) &&
                        (w_k[gi] == 8'h00) && !w_l[gi]) begin
                        M_wbad[gi] = M_wbad[gi] + 1;
                        $display("  [WING-VIOL] stray opener while idle arm=%0d cyc=%0d tid=%0d",
                                 gi, cyc, w_tid[gi]);
                    end
                    // P-C 违规: 窗口内 (且 active 仍为 0) 接受的 opener
                    if (pc_win[gi] && (w_act[gi] == 1'b0) &&
                        (w_k[gi] == 8'h00) && !w_l[gi]) begin
                        M_pcv[gi] = M_pcv[gi] + 1;
                        $display("  [PC-VIOL] early opener arm=%0d cyc=%0d tid=%0d",
                                 gi, cyc, w_tid[gi]);
                    end
                    // P-B: 事件后首个载荷字节
                    if (ev_seen[gi] && !M_bb0v[gi] && (w_k[gi] != 8'h00)) begin
                        // ⚠️ DISCREPANCY (轮报告 §异常): 设计件 v2 §4.1 把 P-B 写成
                        //   `bb0 === 8'h9E (SEED>>24)` —— **字面错**: app 的字节提取是
                        //   `gen_byte = tx_lfsr[31:24]` (app_pattern.v:586 段), 而
                        //   SEED[31:24] = 8'h7F (SEED = 0x9E3779B9_7F4A7C15)。
                        //   (8'h9E = SEED>>56 = 最高字节, 不是流首字节。) 本门按 **RTL
                        //   真值 8'h7F** 判 (依据 = 五条臂 orc=0: 交付流逐字节 == 从 SEED
                        //   重开的模型, 即流首字节 = 模型的 M_mdl[31:24] 起点)。
                        M_bb0[gi]  = w_d[gi][63:56];
                        M_bb0v[gi] = 1'b1;
                    end
                    // P-A: 逐字节比对 (每有效字节记一次; 失配前 4 条打出来)
                    if (w_k[gi][7]) begin
                        if (w_d[gi][63:56] !== M_mdl[gi][31:24]) begin
                            M_orc[gi] = M_orc[gi] + 1;
                            if (M_orc[gi] <= 32'd4)
                                $display("  [MISMATCH] arm=%0d cyc=%0d got=%02x exp=%02x",
                                         gi, cyc, w_d[gi][63:56], M_mdl[gi][31:24]);
                        end
                        M_mdl[gi] = xs_next(M_mdl[gi]);
                    end
                    if (w_k[gi][6]) begin
                        if (w_d[gi][55:48] !== M_mdl[gi][31:24]) M_orc[gi] = M_orc[gi] + 1;
                        M_mdl[gi] = xs_next(M_mdl[gi]);
                    end
                    if (w_k[gi][5]) begin
                        if (w_d[gi][47:40] !== M_mdl[gi][31:24]) M_orc[gi] = M_orc[gi] + 1;
                        M_mdl[gi] = xs_next(M_mdl[gi]);
                    end
                    if (w_k[gi][4]) begin
                        if (w_d[gi][39:32] !== M_mdl[gi][31:24]) M_orc[gi] = M_orc[gi] + 1;
                        M_mdl[gi] = xs_next(M_mdl[gi]);
                    end
                    if (w_k[gi][3]) begin
                        if (w_d[gi][31:24] !== M_mdl[gi][31:24]) M_orc[gi] = M_orc[gi] + 1;
                        M_mdl[gi] = xs_next(M_mdl[gi]);
                    end
                    if (w_k[gi][2]) begin
                        if (w_d[gi][23:16] !== M_mdl[gi][31:24]) M_orc[gi] = M_orc[gi] + 1;
                        M_mdl[gi] = xs_next(M_mdl[gi]);
                    end
                    if (w_k[gi][1]) begin
                        if (w_d[gi][15:8] !== M_mdl[gi][31:24]) M_orc[gi] = M_orc[gi] + 1;
                        M_mdl[gi] = xs_next(M_mdl[gi]);
                    end
                    if (w_k[gi][0]) begin
                        if (w_d[gi][7:0] !== M_mdl[gi][31:24]) M_orc[gi] = M_orc[gi] + 1;
                        M_mdl[gi] = xs_next(M_mdl[gi]);
                    end
                end
                // ---- 事件拍: 模型重开 + 计数清零 (放在 beat 处理之后 = 该拍接受的字节
                //      仍按旧模型判, 与 tb_app_cont 同款语义) ----
                if (up_w[gi]) begin            // 全局起点 + 本臂事件 (模型重开点)
                    M_mdl[gi] = SEED;
                    M_nst[gi] = 0;
                end
                // ⚠️ bb0/tid 的捕获窗口起点 = **本臂自有事件** (ev_own), 不含全局起点:
                //    否则"全局会话起点"那一拍就会把第一个 bb0/tid 抓走 (本臂事件之前的字),
                //    P-B/TID 一律假绿 (首轮实测踩到)。
                if (ev_own[gi]) begin
                    ev_seen[gi] = 1'b1;
                end
            end
        end
    end
    endgenerate

    // ============ 逐臂判据 (每臂一红/绿) ============
    // 臂 idx -> 期望红 (1 = 该臂在本运行下应不过) —— 由 -d P9_EXP_* 选定
    reg exp_red [0:NALL-1];
    initial begin : EXP_INIT
        integer k;
        for (k = 0; k < NALL; k = k + 1) exp_red[k] = 1'b0;
`ifdef P9_EXP_HEAD
        exp_red[0] = 1'b1; exp_red[1] = 1'b1; exp_red[2] = 1'b1;
        exp_red[9] = 1'b1; exp_red[10] = 1'b1;   // R5: 闲置翼臂在未修 RTL 上同样红 (流浪 opener)
`endif
`ifdef P9_EXP_M6
        for (k = 0; k < NALL; k = k + 1) exp_red[k] = 1'b1;
`endif
`ifdef P9_EXP_M6B
        exp_red[3] = 1'b1; exp_red[4] = 1'b1;
`endif
`ifdef P9_EXP_M7
        exp_red[10] = 1'b1;   // R5: M7 (sw_pend 版守卫) 的咬点迁移到闲置翼臂 (见报告 §R5 变更表)
`endif
    end

    function integer crit_a;   // P-A: 图案流自事件拍起重开
        input integer k;
        begin crit_a = (M_orc[k] == 0); end
    endfunction
    function integer crit_b;   // P-B: bb0 == 0x9E
        input integer k;
        begin crit_b = (M_bb0v[k] && (M_bb0[k] == 8'h7F)); end
    endfunction
    function integer arm_red;  // 该臂实测红 (按设计件逐臂判据组合)
        input integer k;
        integer v;
        begin
            v = (!crit_a(k)) || (!crit_b(k)) ? 1 : 0;
            case (k)
                2, 3, 4: if (M_nst[k] < 1)  v = 1;          // STARTS
                6, 7, 8: if (M_pcv[k] != 0) v = 1;          // P-C
                9: begin                                    // P-C + TID
                    if (M_pcv[k] != 0) v = 1;
                    if (!(M_tidv[k] && (M_tid[k] == 4'd1))) v = 1;
                end
                10: if (M_wbad[k] != 0) v = 1;               // R5: 闲置翼 = 无流浪 opener
                default: ;
            endcase
            arm_red = v;
        end
    endfunction

    // ================= 收口 =================
    integer errs, ii;
    reg [1023:0] lbl;
    task chk;
        input cond;  input [1023:0] msg;
        begin
            if (!cond) begin errs = errs + 1; $display("  [FAIL] %0s", msg); end
            else         $display("  [ ok ] %0s", msg);
        end
    endtask

    initial begin
        errs = 0; rst_n = 1'b0; est = 2'd0; cyc = 0;
        o0_seen = 0; o0_done = 0; p1_n = 0; o1_done = 0;
        p2_n = 0; o2_done = 0; s2_low = 0; s2_t = 0;
        p3_n = 0; s3_low = 0; s3_done = 0; s3_c = 0; o3_done = 0;
        p3b_n = 0; s3b_low = 0; s3b_done = 0; s3b_c = 0; o3b_done = 0;
        tl4_seen = 0; s4_dn_done = 0; s4_up_done = 0; s4_c = 0; s4_idle_c = 0;
        s4_dn = 0; s4_up = 0;
        pk5 = 0; s5_c = 0; o5_done = 0;
        pk6 = 0; s6_c = 0; o6_done = 0; e6_c = 0;
        pk7 = 0; s7_c = 0; o7_done = 0;
        pk8 = 0; s8_c = 0; h8_c = 0; o8_done = 0; o8b_done = 0; h8_low = 0; h8_rel = 0;

`ifdef P7B_10G
        $display("TB_P9_SWC CFG=%0s EXP=%0s P7B_10G=1", `P9_MODE_TAG, `P9_EXP_TAG);
`else
        $display("TB_P9_SWC CFG=%0s EXP=%0s P7B_10G=0", `P9_MODE_TAG, `P9_EXP_TAG);
`endif
        $display("TB_P9_SWC ARMNAMES 0=swc0 1=swc1 2=swc2 3=swc3 4=swc3b 5=swc4 6=swc5a 7=swc5b 8=swc5c 9=swc5h 10=swcwing");

        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (CY_TOT) @(posedge clk);
        #0.1;

        // ---- 逐臂读数 (每臂一行, 供人复算) ----
        for (ii = 0; ii < NALL; ii = ii + 1) begin
            $sformat(lbl, "R%0d orc=%0d bb0=%02x bb0v=%0d nst=%0d pcv=%0d nclw=%0d nclwf=%0d wbad=%0d domv=%0d tidv=%0d tid=%0d act=%0d done=%0d",
                     ii, M_orc[ii], M_bb0[ii], M_bb0v[ii], M_nst[ii], M_pcv[ii],
                     M_nclw[ii], M_nclwf[ii], M_wbad[ii], M_domv[ii],
                     M_tidv[ii], M_tid[ii], w_act[ii], w_done[ii]);
            $display("  %0s", lbl);
        end
        // ---- 逐臂判据表 ----
        for (ii = 0; ii < NALL; ii = ii + 1) begin
            $sformat(lbl, "C%0d P-A=%0d P-B=%0d P-C=%0d STARTS=%0d TID=%0d WING=%0d red=%0d exp_red=%0d",
                     ii, crit_a(ii), crit_b(ii),
                     ((ii>=6 && ii<=9) ? (M_pcv[ii]==0) : 1'b1),
                     ((ii==2||ii==3||ii==4) ? (M_nst[ii]>=1) : 1'b1),
                     ((ii==9) ? (M_tidv[ii] && (M_tid[ii]==4'd1)) : 1'b1),
                     ((ii==10) ? (M_wbad[ii]==0) : 1'b1),
                     arm_red(ii), exp_red[ii]);
            $display("  %0s", lbl);
        end

        // ---- 运行级判据: 实测红集 == 期望红集 (逐臂一行, 一路贯彻到退出码) ----
        for (ii = 0; ii < NALL; ii = ii + 1) begin
            $sformat(lbl, "ARM%0d red=%0d exp_red=%0d", ii, arm_red(ii), exp_red[ii]);
            chk(arm_red(ii) === exp_red[ii], lbl);
        end

        // ---- R5 见证 2: frm_wait 态收尾字恒 0 (裁决 B 的牙) ----
        //   ⚠️ 只在 SWC_OK=1 运行上判: SWC_OK=0 (H/H10/OFF) 下 frm_wait 收尾字是
        //      **登记不修**的 HEAD 既存形态 (裁决 B 明示), 在那里它合法存在 (W2 会红
        //      ⇒ 那是"裁决 B 的牙"的**正控**, 由 OFF 运行单独读出, 不计入判据)。
`ifdef P9_SWC_ARM
        for (ii = 0; ii < NALL; ii = ii + 1) begin
            $sformat(lbl, "W2 arm%0d no frm_wait-state close word accepted (nclwf==0)", ii);
            chk(M_nclwf[ii] == 0, lbl);
        end
`else
        $display("  [ n/a ] W2 frm_wait-close-word check skipped (SWC_OK=0: HEAD-form, not fixed); nclwf arm10=%0d = positive control for ruling B", M_nclwf[10]);
`endif
        // ---- R5 见证 1: 支配关系 (仅 SWC_OK=1 运行判; 其余模式 = n/a) ----
`ifdef P9_SWC_ARM
        for (ii = 0; ii < NALL; ii = ii + 1) begin
            $sformat(lbl, "W1 arm%0d dominance sw_apply => !active (no violation)", ii);
            chk(M_domv[ii] == 0, lbl);
        end
`else
        $display("  [ n/a ] W1 dominance check skipped (SWC_OK=0: sw_apply == up_do can be true while active)");
`endif

        $display("TB_P9_SWC_SUM errs=%0d", errs);
        if (errs == 0) $display("TB_P9_SWC: OK");
        else           $display("TB_P9_SWC: FAIL errs=%0d", errs);
        $display("TB_P9_SWC DONE");
        $finish;
    end

    // ---- 可选调试轨迹 (仅 `-d P9_DBG` 时编译; 默认不参与任何运行) ----
`ifdef P9_DBG
    reg d2_act;
    initial d2_act = 1'b0;
    always @(posedge clk) if (rst_n) begin
        if (u2_up) $display("DBG cyc=%0d EV2UP  act=%0d closing=%0d sw_pend=%0d op_sent=%0d seg_sent=%0d rdy=%0d",
                            cyc, w_act[2], u2.closing, u2.sw_pend, u2.op_sent, u2.seg_sent, rdy[2]);
        if (u2_dn) $display("DBG cyc=%0d EV2DN  act=%0d closing=%0d sw_pend=%0d up_pend=%0d",
                            cyc, w_act[2], u2.closing, u2.sw_pend, u2.up_pend_r);
        if (w_v[2] && rdy[2] && (w_k[2] == 8'h00) && w_l[2])
                   $display("DBG cyc=%0d CLW2ACC act=%0d sw_pend=%0d", cyc, w_act[2], u2.sw_pend);
        if (w_act[2] !== d2_act) begin
            $display("DBG cyc=%0d ACT2 %0d->%0d closing=%0d sw_pend=%0d op_pend=%0d op_sent=%0d pwv=%0d rdy=%0d upok=%0d swapp=%0d upev=%0d",
                     cyc, d2_act, w_act[2], u2.closing, u2.sw_pend, u2.op_pend, u2.op_sent,
                     u2.pw_valid, rdy[2], u2.up_ok, u2.sw_apply, u2.up_ev);
        end
        d2_act <= w_act[2];
        if (u8_up2) $display("DBG cyc=%0d EV9HANDOFF slot=1 closing=%0d sw_pend=%0d up_pend=%0d",
                             cyc, u5h.closing, u5h.sw_pend, u5h.up_pend_r);
        if (w_v[9] && rdy[9] && (w_k[9] == 8'h00) && !w_l[9])
            $display("DBG cyc=%0d OP9 acc tid=%0d act=%0d", cyc, w_tid[9], w_act[9]);
    end
`endif
endmodule
