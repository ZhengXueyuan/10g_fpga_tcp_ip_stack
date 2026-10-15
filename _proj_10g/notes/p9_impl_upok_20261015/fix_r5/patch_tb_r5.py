#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""patch_tb_r5.py -- R5: 给 sim/p9_swc_gate/tb_p9_swc.v 加 (a) 闲置翼臂 idx10,
(b) 支配监视器, (c) nclw 拆分, (d) arm9 交接重定时。逐锚点硬断言, 全成或全不落。
"""
import io
import os
import hashlib
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TB = os.path.abspath(os.path.join(HERE, "..", "..", "..", "..", "sim", "p9_swc_gate", "tb_p9_swc.v"))

R = []


def rep(old, new, n=1, tag=""):
    R.append((old, new, n, tag))


# ---------- P1: 文件头臂表 ----------
rep("""//   9 u_swc5h : R3-1 序列 = frm_wait 冻结 + 同槽 ev_up -> rdy 拉低(收尾字停滞) ->
//               停滞期**异槽**(槽 1) ev_up (请求交接) -> 放开 rdy 且 tx_ok 与"收尾字被
//               接受拍"同拍回升; 判据加 TID
""",
"""//   9 u_swc5h : R3-1 序列 = frm_wait 冻结 + 同槽 ev_up -> rdy 拉低 -> 停滞期**异槽**
//               (槽 1) ev_up (请求交接) -> 放开 rdy 且 tx_ok 与收尾完成拍同拍回升; 判据加 TID
//               ⚠️ P9 R5 (裁决 B): frm_wait 态收尾变成"1 拍 else 支、不等 m_tready" ⇒
//               "停滞期交接"窗口收窄为**收尾完成拍 E+1**; 该臂 M7 判别力随之迁移
//               (见报告 §R5 变更表 / 咬点迁移到 idx10)
//  10 u_swcwing: **post-close 闲置翼** (设计件 v2r3 §5-1; R5 裁决 A 依据 (i)):
//               frm_wait 冻结 -> 同槽 ev_down (W3 收尾; app 转 idle 且 frm_wait 残留 1)
//               -> **idle 态拉高 tx_ok** (翼触发) -> 之后同槽 ev_up (合法新会话)
//               判据: 翼窗口内**不得有 active==0 时被接受的 opener** (流浪 opener)
""", 1, "P1")

# ---------- P2: NALL ----------
rep("    localparam integer NALL   = 10;", "    localparam integer NALL   = 11;", 1, "P2")

# ---------- P3: 见证引线声明 ----------
rep("    wire        w_act [0:NALL-1], w_done [0:NALL-1];",
    "    wire        w_act [0:NALL-1], w_done [0:NALL-1];\n"
    "    wire        w_fw  [0:NALL-1];   // DUT 的 frm_wait (见证: 收尾字分类)\n"
    "    wire        w_swa [0:NALL-1];   // DUT 的 sw_apply (见证: 支配关系)", 1, "P3")

# ---------- P4: idx10 激励 ----------
rep("""        if (u8_up2) o8b_done <= 1'b1;
    end
""",
"""        if (u8_up2) o8b_done <= 1'b1;
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
""", 1, "P4")

# ---------- P5..P11: 向量 ----------
rep("    assign rdy[9] = ~h8_low;",
    "    assign rdy[9] = ~h8_low;\n    assign rdy[10] = 1'b1;", 1, "P5")
rep("    assign txok[9] = !pk8 || h8_rel;                        // R3-1: 与 rdy 放开同拍 (C 拍高)",
    "    assign txok[9] = !pk8 || o8_done;                       // R3-1: 收尾完成拍 (E+1) 回升\n"
    "    assign txok[10] = !pk10 || w10_rel;                     // 闲置翼: idle 态回升", 1, "P6")
rep("    assign ev_u[9] = up_g | u8_up | u8_up2;",
    "    assign ev_u[9] = up_g | u8_up | u8_up2;\n    assign ev_u[10] = up_g | u10_up;", 1, "P7")
rep("    assign ev_d[9] = 1'b0;", "    assign ev_d[9] = 1'b0;\n    assign ev_d[10] = u10_dn;", 1, "P8")
rep("    wire [3:0] ev_slot0 = 4'd0;",
    "    wire [3:0] ev_slot0 = 4'd0;\n    wire [3:0] ev_slotw = 4'd0;   // 闲置翼臂 = 槽 0", 1, "P9")
rep("    assign ev_own[9] = u8_up;", "    assign ev_own[9] = u8_up;\n    assign ev_own[10] = u10_up;", 1, "P10")
rep("    assign up_w[9] = up_g | u8_up;", "    assign up_w[9] = up_g | u8_up;\n    assign up_w[10] = up_g | u10_up;", 1, "P11")

# ---------- P12: 例化 + 见证引线赋值 ----------
rep("""        .active(w_act[9]), .act_id(), .done(w_done[9]), .dbg_lfsr(), .led(),
        .stat_frmwait_cyc(), .stat_bp_cyc()
    );
""",
"""        .active(w_act[9]), .act_id(), .done(w_done[9]), .dbg_lfsr(), .led(),
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
    assign w_fw[0]  = u0.frm_wait;   assign w_swa[0]  = u0.sw_apply;
    assign w_fw[1]  = u1.frm_wait;   assign w_swa[1]  = u1.sw_apply;
    assign w_fw[2]  = u2.frm_wait;   assign w_swa[2]  = u2.sw_apply;
    assign w_fw[3]  = u3.frm_wait;   assign w_swa[3]  = u3.sw_apply;
    assign w_fw[4]  = u3b.frm_wait;  assign w_swa[4]  = u3b.sw_apply;
    assign w_fw[5]  = u4.frm_wait;   assign w_swa[5]  = u4.sw_apply;
    assign w_fw[6]  = u5a.frm_wait;  assign w_swa[6]  = u5a.sw_apply;
    assign w_fw[7]  = u5b.frm_wait;  assign w_swa[7]  = u5b.sw_apply;
    assign w_fw[8]  = u5c.frm_wait;  assign w_swa[8]  = u5c.sw_apply;
    assign w_fw[9]  = u5h.frm_wait;  assign w_swa[9]  = u5h.sw_apply;
    assign w_fw[10] = u10.frm_wait;  assign w_swa[10] = u10.sw_apply;
""", 1, "P12")

# ---------- P13: 记账寄存器 ----------
rep("    reg [31:0] M_nclw[0:NALL-1];      // 见证: 被接受的 W3 收尾字 (keep==0 && last==1) 数",
    "    reg [31:0] M_nclw[0:NALL-1];      // 见证: 被接受的 W3 收尾字 (keep==0 && last==1) 数\n"
    "    reg [31:0] M_nclwf[0:NALL-1];     //   ...其中 **frm_wait 态**那一类 (R5 裁决 B 后应恒 0)\n"
    "    reg [31:0] M_wbad[0:NALL-1];      // 闲置翼违规: active==0 时被接受的 opener 数\n"
    "    reg [31:0] M_domv[0:NALL-1];      // 支配违规: sw_apply && active (SWC_OK=1 下应恒 0)\n"
    "    reg        wing_win[0:NALL-1];    // 闲置翼窗口 (ev_down 开, 末次 ev_up 关)", 1, "P13")

rep("                M_pcv[gi] <= 0; M_nclw[gi] <= 0; pc_win[gi] <= 0; pc_fell[gi] <= 0;",
    "                M_pcv[gi] <= 0; M_nclw[gi] <= 0; M_nclwf[gi] <= 0; pc_win[gi] <= 0; pc_fell[gi] <= 0;\n"
    "                M_wbad[gi] <= 0; M_domv[gi] <= 0; wing_win[gi] <= 0;", 1, "P14")

# ---------- P15: nclw 拆分 + 翼违规 ----------
rep("                    if ((w_k[gi] == 8'h00) && w_l[gi]) M_nclw[gi] = M_nclw[gi] + 1;",
    """                    if ((w_k[gi] == 8'h00) && w_l[gi]) begin
                        if (w_fw[gi]) M_nclwf[gi] = M_nclwf[gi] + 1;   // frm_wait 态收尾字
                        else          M_nclw[gi]  = M_nclw[gi]  + 1;   // 非 frm_wait 收尾字
                    end
                    // 闲置翼违规 (仅 idx10 窗口内): active==0 时被接受的 opener
                    if (wing_win[gi] && (w_act[gi] == 1'b0) &&
                        (w_k[gi] == 8'h00) && !w_l[gi]) begin
                        M_wbad[gi] = M_wbad[gi] + 1;
                        $display("  [WING-VIOL] stray opener while idle arm=%0d cyc=%0d tid=%0d",
                                 gi, cyc, w_tid[gi]);
                    end""", 1, "P15")

# ---------- P16: 翼窗口 + 支配监视 ----------
rep("""                if (up_w[gi]) begin
                    pc_win[gi]  <= 1'b1;
                    pc_fell[gi] <= 1'b0;""",
"""                // ---- 闲置翼窗口 (idx10): ev_down 开, 末次 ev_up 关 ----
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
                    pc_fell[gi] <= 1'b0;""", 1, "P16")

# ---------- P17: 期望红集 ----------
rep("        exp_red[0] = 1'b1; exp_red[1] = 1'b1; exp_red[2] = 1'b1; exp_red[9] = 1'b1;",
    "        exp_red[0] = 1'b1; exp_red[1] = 1'b1; exp_red[2] = 1'b1;\n"
    "        exp_red[9] = 1'b1; exp_red[10] = 1'b1;   // R5: 闲置翼臂在未修 RTL 上同样红 (流浪 opener)",
    1, "P17a")
rep("""`ifdef P9_EXP_M7
        exp_red[9] = 1'b1;
`endif""",
    """`ifdef P9_EXP_M7
        exp_red[10] = 1'b1;   // R5: M7 (sw_pend 版守卫) 的咬点迁移到闲置翼臂 (见报告 §R5 变更表)
`endif""", 1, "P17b")

# ---------- P18: arm_red ----------
rep("""                9: begin                                    // P-C + TID
                    if (M_pcv[k] != 0) v = 1;
                    if (!(M_tidv[k] && (M_tid[k] == 4'd1))) v = 1;
                end""",
    """                9: begin                                    // P-C + TID
                    if (M_pcv[k] != 0) v = 1;
                    if (!(M_tidv[k] && (M_tid[k] == 4'd1))) v = 1;
                end
                10: if (M_wbad[k] != 0) v = 1;               // R5: 闲置翼 = 无流浪 opener""", 1, "P18")

# ---------- P19: 打印 + 判据 ----------
rep('        $display("TB_P9_SWC ARMNAMES 0=swc0 1=swc1 2=swc2 3=swc3 4=swc3b 5=swc4 6=swc5a 7=swc5b 8=swc5c 9=swc5h");',
    '        $display("TB_P9_SWC ARMNAMES 0=swc0 1=swc1 2=swc2 3=swc3 4=swc3b 5=swc4 6=swc5a 7=swc5b 8=swc5c 9=swc5h 10=swcwing");',
    1, "P19a")
rep("""            $sformat(lbl, "R%0d orc=%0d bb0=%02x bb0v=%0d nst=%0d pcv=%0d nclw=%0d tidv=%0d tid=%0d act=%0d done=%0d",
                     ii, M_orc[ii], M_bb0[ii], M_bb0v[ii], M_nst[ii], M_pcv[ii],
                     M_nclw[ii], M_tidv[ii], M_tid[ii], w_act[ii], w_done[ii]);""",
    """            $sformat(lbl, "R%0d orc=%0d bb0=%02x bb0v=%0d nst=%0d pcv=%0d nclw=%0d nclwf=%0d wbad=%0d domv=%0d tidv=%0d tid=%0d act=%0d done=%0d",
                     ii, M_orc[ii], M_bb0[ii], M_bb0v[ii], M_nst[ii], M_pcv[ii],
                     M_nclw[ii], M_nclwf[ii], M_wbad[ii], M_domv[ii],
                     M_tidv[ii], M_tid[ii], w_act[ii], w_done[ii]);""", 1, "P19b")
rep("""            $sformat(lbl, "C%0d P-A=%0d P-B=%0d P-C=%0d STARTS=%0d TID=%0d red=%0d exp_red=%0d",
                     ii, crit_a(ii), crit_b(ii),
                     ((ii>=6) ? (M_pcv[ii]==0) : 1'b1),
                     ((ii==2||ii==3||ii==4) ? (M_nst[ii]>=1) : 1'b1),
                     ((ii==9) ? (M_tidv[ii] && (M_tid[ii]==4'd1)) : 1'b1),
                     arm_red(ii), exp_red[ii]);""",
    """            $sformat(lbl, "C%0d P-A=%0d P-B=%0d P-C=%0d STARTS=%0d TID=%0d WING=%0d red=%0d exp_red=%0d",
                     ii, crit_a(ii), crit_b(ii),
                     ((ii>=6 && ii<=9) ? (M_pcv[ii]==0) : 1'b1),
                     ((ii==2||ii==3||ii==4) ? (M_nst[ii]>=1) : 1'b1),
                     ((ii==9) ? (M_tidv[ii] && (M_tid[ii]==4'd1)) : 1'b1),
                     ((ii==10) ? (M_wbad[ii]==0) : 1'b1),
                     arm_red(ii), exp_red[ii]);""", 1, "P19c")

# 新判据: frm_wait 收尾字恒 0 + 支配关系 + 翼
rep("""        $display("TB_P9_SWC_SUM errs=%0d", errs);""",
"""        // ---- R5 见证 2: frm_wait 态收尾字恒 0 (裁决 B 的牙; 全模式判) ----
        for (ii = 0; ii < NALL; ii = ii + 1) begin
            $sformat(lbl, "W2 arm%0d no frm_wait-state close word accepted (nclwf==0)", ii);
            chk(M_nclwf[ii] == 0, lbl);
        end
        // ---- R5 见证 1: 支配关系 (仅 SWC_OK=1 运行判; 其余模式 = n/a) ----
`ifdef P9_SWC_ARM
        for (ii = 0; ii < NALL; ii = ii + 1) begin
            $sformat(lbl, "W1 arm%0d dominance sw_apply => !active (no violation)", ii);
            chk(M_domv[ii] == 0, lbl);
        end
`else
        $display("  [ n/a ] W1 dominance check skipped (SWC_OK=0: sw_apply == up_do can be true while active)");
`endif

        $display("TB_P9_SWC_SUM errs=%0d", errs);""", 1, "P20")

out = io.open(TB, encoding="utf-8", newline="").read()
pre = hashlib.sha256(out.encode()).hexdigest()
print("TB pre-sha:", pre)
for old, new, n, tag in R:
    c = out.count(old)
    if c != n:
        print("ANCHOR FAIL %s: hits=%d expect=%d" % (tag, c, n))
        print("  old[:120]=%r" % old[:120])
        sys.exit(1)
    out = out.replace(old, new)
io.open(TB, "w", encoding="utf-8", newline="").write(out)
print("PATCH OK; TB post-sha:", hashlib.sha256(out.encode()).hexdigest())
