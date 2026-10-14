`timescale 1ns/1ps
//=============================================================================
// tb_f3_resync.v -- F-3 修复门 G1 (设计件 = _proj_10g/notes/p9_fix_f3_design_20261014/
//                  DESIGN_v2.md §3.2-G1; 被测 = rtl/vlan_strip.v 的 RESYNC_EN 重同步门)
//=============================================================================
// 链路 (与 wrapper 双域形态同构, 同 t9 模型 agent_docs/audit_scratch/t9_f3restart):
//   GMII 帧源 -> mac_rx_64(FE 125MHz) -> fifo_async 76/256/FWFT (u_rxcdc 的等价物)
//   -> vlan_strip (真 RTL, DP 156.25MHz) -> DP 水槽 (按 TLAST 成帧, 逐帧记内容/长度/tcrs)
//
// 重启模型 = I-3 (TB 侧建模; 与 rtl/clk_gen_p6b.v 的"异步置位 / 同步释放"同形态):
//   停 DP 钟 + 断言 dp_rst_dp, 1500 gclk 后恢复钟、4 个 DP 沿释放。
//   ⚠️ 与 t9 的接线差异 (唯一一处, 见 §"TB 接线"注释): s_axis_tready 由 DUT 驱动
//     (t9 把它与 TB 的 assign 1'b1 并接 = 多驱动冒险); 本激励无 VLAN 帧 ⇒ 两者行为等价,
//     且本件用 J4 守恒式 (逐跑精确闭合) 反证等价。
//
// 臂 (编译期; bat 逐臂传 -d / 换源文件):
//   F     (默认)          : 新 RTL + RESYNC_EN=1        —— 期望 J1..J6 全绿
//   L     (-d F3_RESYNC_L): 新 RTL + RESYNC_EN=0        —— 负对照 (缺陷复现 ⇒ XFAIL)
//   M1/M2 (mut/mut_m*.v)  : 变异件 (fwd 谓词被改坏)     —— 必须红 (J1)
//   CTRL  (-d F3_STOP_IFG): RESYNC_EN=1 + 注入挪到帧间 IFG (FIFO 空 + FE 冻结)
//                           —— J3 正对照: 丢弃计数必须 = 0 (证明它不是恒正)
//
// 判据 (J1..J6; 逐条打印, 判定见 REPORT, 本 TB 不下 PASS/FAIL 裁定):
//   J1 片段不再交付: frag==0 && trunc_with_crs==0 && unrec==0
//   J2 首字是 SOP  : 第一个交付帧的**首字拍**直接采 vs_tuser == 1
//                    (⛔ 不用 t9 记录器 rec_tuser: 它测的是簿记断档, 见 DESIGN_v2 C9/L1;
//                      本 TB 保留该记录器为 dtuser[] 仅作伪影对照展示)
//   J3 门真的跑了  : stat_resync_words == TB 侧独立镜像计数 (且 F 臂要求 > 0)
//   J4 守恒 (I5)   : pop_post == taken_post + stat_resync_words  逐跑精确闭合
//                    (pop_post = 释放后 FIFO 弹出数; taken_post = 交付下游的字数)
//   J5 无重放      : stale_words==0 且"重启前已开始帧的非零偏移"交付计数==0
//                    (⚠️ stale_words 是钳位量, 不能当唯一判据 —— 主读数是 srco!=0 计数)
//   J6 回归未受伤  : 重启之后的源帧逐字节全等 (全 whole, 无 unrec)
//=============================================================================
module tb_f3_resync;

    // ---------------- 臂选择 ----------------
`ifdef F3_RESYNC_L
    localparam VS_RESYNC = 1'b0;        // L 臂: 负对照 (新 RTL + 门关)
`else
    localparam VS_RESYNC = 1'b1;        // F / M / CTRL 臂
`endif
`ifdef F3_STOP_IFG
    localparam ARM_CTRL = 1;            // J3 正对照 (注入挪到帧间)
`else
    localparam ARM_CTRL = 0;
`endif

    // ⚠️ 臂名用**编译期 define** 传, 不用 -testplusarg NAME=VALUE:
    //   xsim.bat 的 loader 会把含 `=` 的参数切开 ("Expected a switch but found ...")
    //   —— 本仓既存坑, 文档在 sim/d2run/p4prv/run_tb_p4_burst.bat:66-68。
    reg [8*8-1:0] arm_name;
    initial begin
`ifdef F3_ARMID_L
        arm_name = "L";
`elsif F3_ARMID_M1
        arm_name = "M1";
`elsif F3_ARMID_M2
        arm_name = "M2";
`elsif F3_ARMID_CTRL
        arm_name = "CTRL";
`else
        arm_name = "F";
`endif
        $display("F3R ARM=%0s resync_en=%0d ctrl_ifg=%0d", arm_name, VS_RESYNC, ARM_CTRL);
    end

    // ---------------- 时钟 / 复位 ----------------
    reg gclk = 0, dclk = 0;
    reg reset_n = 0, dp_clk_en = 1, dp_rst_dp = 0, fe_hold = 0;
    always #4.0 gclk = ~gclk;              // 125.00 MHz 前端
    always #3.2 dclk = ~dclk;              // 156.25 MHz 数据面
    wire dpc = dp_clk_en ? dclk : 1'b0;
    wire dp_rst_n = ~dp_rst_dp;

    // ---------------- 激励: 12 帧, 每帧 64B 内容, 内容 = cbyte(f, k) ----------------
    localparam integer NFR = 12, CLEN = 64, IFG = 24;
    localparam integer FBYTES = 8 + CLEN + 4;    // 前导8 + 内容 + FCS4
    localparam integer MAXB = NFR * (FBYTES + IFG) + 16;
    reg  [7:0] sd [0:MAXB-1];
    reg  [7:0] sv [0:MAXB-1];
    integer nstim, si;
    // 内容字节: (f*67 + k*29) & 0xFF —— 任 (帧,偏移) 组合唯一 (TB 侧独立反解, 非 DUT 自报)
    function [7:0] cbyte;
        input integer f; input integer k;
        begin cbyte = ((f * 67 + k * 29) & 8'hFF);
        end
    endfunction

    // 重启点 (两档):
    //  默认      = 第 3 帧内容中段 (K=3, 与 t9 逐字同点)
    //  CTRL 臂   = 第 3 帧的帧间 IFG 深处 (si=392 ∈ [376,399])
    localparam integer IDX_STOP    = 3*(FBYTES+IFG) + 8 + 32;   // = 340 (帧3 内容中段)
    localparam integer IDX_STOP_IFG = 3*(FBYTES+IFG) + FBYTES + 16;  // = 392 (帧3 IFG 内)

    function [31:0] cstep;
        input [31:0] c; input [7:0] bb;
        reg [31:0] rr; integer ii;
        begin
            rr = c;
            for (ii = 0; ii < 8; ii = ii + 1)
                rr = (rr[0] ^ bb[ii]) ? ((rr >> 1) ^ 32'hEDB88320) : (rr >> 1);
            cstep = rr;
        end
    endfunction

    integer f, k;
    reg [31:0] cr;
    reg [7:0]  fcs [0:3];
    initial begin
        nstim = 0;
        for (k = 0; k < MAXB; k = k + 1) begin sd[k] = 8'h07; sv[k] = 0; end
        for (f = 0; f < NFR; f = f + 1) begin
            for (k = 0; k < 7; k = k + 1) begin sd[nstim] = 8'h55; sv[nstim] = 1; nstim = nstim + 1; end
            sd[nstim] = 8'hD5; sv[nstim] = 1; nstim = nstim + 1;
            cr = 32'hFFFFFFFF;
            for (k = 0; k < CLEN; k = k + 1) begin
                sd[nstim] = cbyte(f, k); sv[nstim] = 1; nstim = nstim + 1;
                cr = cstep(cr, cbyte(f, k));
            end
            fcs[0] = cr[7:0] ^ 8'hFF; fcs[1] = cr[15:8] ^ 8'hFF;
            fcs[2] = cr[23:16] ^ 8'hFF; fcs[3] = cr[31:24] ^ 8'hFF;
            for (k = 0; k < 4; k = k + 1) begin
                sd[nstim] = fcs[k]; sv[nstim] = 1; nstim = nstim + 1;
                cr = cstep(cr, fcs[k]);
            end
            if (cr !== 32'hDEBB20E3) $display("F3R TB-CRC-SELFTEST-FAIL f=%0d res=%08x", f, cr);
            for (k = 0; k < IFG; k = k + 1) begin sd[nstim] = 8'h07; sv[nstim] = 0; nstim = nstim + 1; end
        end
        $display("F3R TB-STIM frames=%0d bytes=%0d stopIdx=%0d stopIdxIfg=%0d", NFR, nstim, IDX_STOP, IDX_STOP_IFG);
    end

    reg [7:0] gd; reg gdv, gerr;
    always @(posedge gclk) begin
        if (!reset_n) begin si <= 0; gd <= 8'h07; gdv <= 0; gerr <= 0; end
        else if (fe_hold) begin gd <= 8'h07; gdv <= 0; gerr <= 0; end   // CTRL 臂: 冻结激励
        else if (si < nstim) begin
            gd <= sd[si]; gdv <= sv[si]; gerr <= 0; si <= si + 1;
        end else begin
            gd <= 8'h07; gdv <= 0; gerr <= 0;
        end
    end

    // ---------------- DUT ----------------
    wire [63:0] m_tdata; wire [7:0] m_tkeep;
    wire m_tvalid, m_tlast, m_tuser, m_tcrs, m_terr, m_tready;
    wire [31:0] st_frames, st_crc, st_drop, st_bytes, st_dfull, st_dpart, st_orph, st_ovf, st_words;
    wire [63:0] rx_tdata; wire [7:0] rx_tkeep;
    wire rx_tvalid, rx_tlast, rx_tuser, rx_tcrs, rx_terr;
    wire [75:0] cdc_word;
    wire rx_full, rx_empty, cdc_rd;

    mac_rx_64 u_mac (
        .clk(gclk), .rst_n(reset_n),
        .gmii_rxd(gd), .gmii_rx_dv(gdv), .gmii_rx_er(gerr),
        .m_axis_tdata(m_tdata), .m_axis_tkeep(m_tkeep),
        .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready),
        .m_axis_tlast(m_tlast), .m_axis_tuser(m_tuser),
        .m_axis_terr(m_terr), .m_axis_tcrs(m_tcrs),
        .stat_frames(st_frames), .stat_crc_err(st_crc), .stat_drop(st_drop),
        .stat_bytes(st_bytes),
        .stat_drop_full(st_dfull), .stat_drop_partial(st_dpart),
        .stat_orphan_bytes(st_orph), .stat_fifo_ovf(st_ovf),
        .dbg_stat_words_out(st_words)
    );

    // 变体 A: 现行 wrapper 接线 (两侧复位都只接板级 reset_n) —— F-3 的真实前提
    wire rx_wr_rst_n = reset_n;
    wire rx_rd_rst_n = reset_n;

    fifo_async #(.WIDTH(76), .DEPTH(256), .FWFT(1), .AW(8)) u_rxcdc (
        .wr_clk(gclk), .wr_rst_n(rx_wr_rst_n), .wr_en(m_tvalid),
        .din({m_tdata, m_tkeep, m_tuser, m_tlast, m_tcrs, m_terr}),
        .full(rx_full),
        .rd_clk(dpc), .rd_rst_n(rx_rd_rst_n), .rd_en(cdc_rd),
        .dout(cdc_word), .empty(rx_empty),
        .dbg_wbin(), .dbg_rbin(), .dbg_wgray(), .dbg_rgray(), .dbg_occ_w(), .dbg_occ_r()
    );
    assign {rx_tdata, rx_tkeep, rx_tuser, rx_tlast, rx_tcrs, rx_terr} = cdc_word;
    assign rx_tvalid = ~rx_empty;
    assign m_tready  = ~rx_full;

    // TB 接线: read 请求 = 与真 wrapper 同款 (rd_en = rx_tvalid && vlan_strip.s_axis_tready);
    //   vlan_strip 的 s_axis_tready 是它的**输出**(S_TAIL 时 0) ⇒ 由 DUT 驱动, TB 不并接。
    wire vs_s_axis_tready;
    assign cdc_rd = rx_tvalid && vs_s_axis_tready;

    // vlan_strip (真 DP 首级; RESYNC_EN 由臂决定)
    wire [63:0] vs_tdata; wire [7:0] vs_tkeep;
    wire vs_tvalid, vs_tready, vs_tlast, vs_tuser, vs_tcrs, vs_terr;
    vlan_strip #(.RESYNC_EN(VS_RESYNC)) u_vs (
        .clk(dpc), .rst_n(dp_rst_n),
        .s_axis_tdata(rx_tdata), .s_axis_tkeep(rx_tkeep), .s_axis_tvalid(rx_tvalid),
        .s_axis_tready(vs_s_axis_tready), .s_axis_tlast(rx_tlast), .s_axis_tuser(rx_tuser),
        .s_axis_tcrs(rx_tcrs), .s_axis_terr(rx_terr),
        .m_axis_tdata(vs_tdata), .m_axis_tkeep(vs_tkeep), .m_axis_tvalid(vs_tvalid),
        .m_axis_tready(vs_tready), .m_axis_tlast(vs_tlast), .m_axis_tuser(vs_tuser),
        .m_axis_tcrs(vs_tcrs), .m_axis_terr(vs_terr),
        .stat_stripped(), .dbg_vlan()
    );
    assign vs_tready = 1'b1;               // 水槽永远能吞

    // ---------------- 仪器 1: 弹出/交付/复位窗 (TB 侧独立计数) ----------------
    // 相位: pre (rst_ever=0) / rst (dp_rst_dp=1) / post (rst_ever=1 && dp_rst_dp=0)
    //   本块只由 reset_n 复位 (不受 dp_rst_dp 影响) —— 否则复位窗内计数会被清掉。
    reg        rst_ever;
    reg        stall_mode;                      // TB 置: 停钟窗口 (witness: 该窗内 dpc 沿数)
    reg        rx_empty_r1, rx_empty_r2, rx_empty_r3;   // CTRL 臂预条件: FIFO 空的短历史
    reg [31:0] pop_pre, pop_rst, pop_post;      // FIFO 弹出 (按相位)
    reg [31:0] taken_post, taken_all;           // 交付下游 (vs_tvalid && vs_tready)
    reg [31:0] dpc_edges, stall_edges, rstwin_edges;
    always @(posedge dpc or negedge reset_n) begin
        if (!reset_n) begin
            rst_ever <= 0; pop_pre <= 0; pop_rst <= 0; pop_post <= 0;
            taken_post <= 0; taken_all <= 0;
            dpc_edges <= 0; stall_edges <= 0; rstwin_edges <= 0;
        end else begin
            dpc_edges <= dpc_edges + 32'd1;
            if (dp_rst_dp) rstwin_edges <= rstwin_edges + 32'd1;   // 复位窗内的活钟沿
            if (stall_mode) stall_edges <= stall_edges + 32'd1;    // 应恒 0 (钟真的停了)
            if (rx_tvalid && vs_s_axis_tready) begin
                if (dp_rst_dp)                 pop_rst  <= pop_rst  + 32'd1;
                else if (!rst_ever)            pop_pre  <= pop_pre  + 32'd1;
                else                           pop_post <= pop_post + 32'd1;
            end
            if (vs_tvalid && vs_tready) begin
                taken_all <= taken_all + 32'd1;
                if (rst_ever && !dp_rst_dp) taken_post <= taken_post + 32'd1;
            end
            if (dp_rst_dp) rst_ever <= 1'b1;
        end
    end

    // ---------------- 仪器 2: 丢弃数镜像 (J3 的 TB 侧独立复算) ----------------
    // 语义逐条镜像 DUT 的 rsw: 复位窗内不计 (DUT 的计数体在 rst_n==1 支内);
    // 释放后 未同步 且 非 SOP 的弹出 = 丢弃; 一旦收下过 SOP (或本拍是 SOP) 即同步。
    reg        tb_sync;
    reg [31:0] tb_drops;
    always @(posedge dpc or negedge reset_n) begin
        if (!reset_n) begin
            tb_sync <= 1'b0; tb_drops <= 32'd0;
        end else if (rst_ever && !dp_rst_dp) begin
            if (rx_tvalid && vs_s_axis_tready) begin
                if (tb_sync || rx_tuser) tb_sync <= 1'b1;
                else if (VS_RESYNC)      tb_drops <= tb_drops + 32'd1;  // 门关 (L 臂) ⇒ 镜像恒 0
            end
        end
    end

    // ---------------- 仪器 3: DP 水槽 (按 TLAST 成帧) ----------------
    localparam integer MAXF = 64;
    reg  [7:0] rbuf [0:511];
    reg  [7:0] deliv [0:MAXF*512-1];
    integer    dlen  [0:MAXF-1];
    reg        dcrs  [0:MAXF-1];
    reg        dtuser[0:MAXF-1];   // ⚠️ 旧记录器伪影 (t9 同款; 仅对照展示, 不作判据)
    reg        d_fu  [0:MAXF-1];   // J2 直采: 该帧**首字拍**的 vs_tuser (本件判据用)
    integer    ndel, rlen, p, q, off, found, srcf, srco;
    reg        in_frame;
    reg [31:0] n_frag, n_stale, n_whole, n_unrec, n_trunc_crs, n_srco_nz;
    integer    K_restart;
    // FE 侧静默丢字计数
    reg [8:0]  wbin_r;
    reg [31:0] fe_acc, fe_dut_acc;
    wire       wbin_moved = (u_rxcdc.dbg_wbin !== wbin_r);
    wire       acc_now    = m_tvalid && !rx_full;

    always @(posedge gclk or negedge reset_n) begin
        if (!reset_n) begin
            wbin_r <= 0; fe_acc <= 0; fe_dut_acc <= 0;
        end else begin
            if (acc_now) fe_acc <= fe_acc + 32'd1;
            if (wbin_moved) fe_dut_acc <= fe_dut_acc + 32'd1;
            wbin_r <= u_rxcdc.dbg_wbin;
        end
    end

    reg        rec_pend;
    reg [31:0] rec_len; reg rec_crs, rec_tuser, rec_fu; reg [7:0] rec_nb;
    reg [31:0] dw_all;
    reg [7:0]  nb;
    reg        ftu;        // 阻塞临时: 当前帧首字的 vs_tuser (J2 直采的源)
    always @(posedge dpc or negedge dp_rst_n) begin
        if (!dp_rst_n) begin
            rlen <= 0; in_frame <= 0; ndel <= 0; rec_pend <= 0; rec_len <= 0;
            rec_crs <= 0; rec_tuser <= 0; rec_fu <= 0; rec_nb <= 0; dw_all <= 0;
        end else begin
            nb = (vs_tkeep[0]?1'b1:1'b0)+(vs_tkeep[1]?1'b1:1'b0)+(vs_tkeep[2]?1'b1:1'b0)+(vs_tkeep[3]?1'b1:1'b0)
                +(vs_tkeep[4]?1'b1:1'b0)+(vs_tkeep[5]?1'b1:1'b0)+(vs_tkeep[6]?1'b1:1'b0)+(vs_tkeep[7]?1'b1:1'b0);
            // ---- 上一拍收尾的帧在这里落盘 (rbuf 已全部写完; 避开 NBA 竞争) ----
            if (rec_pend) begin
                rec_pend <= 1'b0;
                if (ndel < MAXF) begin
                    for (q = 0; q < 512; q = q + 1)
                        deliv[ndel*512 + q] <= rbuf[q];
                    dlen[ndel]   <= rec_len;
                    dcrs[ndel]   <= rec_crs;
                    dtuser[ndel] <= rec_tuser;
                    d_fu[ndel]   <= rec_fu;
                end
                ndel <= ndel + 1;
            end
            if (vs_tvalid) begin
                dw_all <= dw_all + 32'd1;
                for (p = 0; p < 8; p = p + 1)
                    if (vs_tkeep[7-p] && ((rlen + p) < 512)) rbuf[rlen+p] <= vs_tdata[63 - 8*p -: 8];
                // J2 直采: 帧首字拍 (in_frame 还是 0 的那一拍) 的 vs_tuser
                if (!in_frame) ftu = vs_tuser;
                if (!in_frame) in_frame <= 1'b1;
                if (vs_tlast) begin
                    rec_pend  <= 1'b1;
                    rec_len   <= rlen + nb;
                    rec_nb    <= nb;
                    rec_crs   <= vs_tcrs;
                    rec_fu    <= ftu;
                    rec_tuser <= (!in_frame) ? vs_tuser : 1'b0;   // ⚠️ 旧记录器 (伪影, 见 C9/L1)
                    rlen <= 0; in_frame <= 0;
                end else begin
                    rlen <= rlen + nb;
                end
            end
        end
    end

    // ---------------- 重启时序 + 终判 ----------------
    integer guard;
    reg [31:0] W_snap, dw_snap, pushes_after, stale_words;
    reg [31:0] stat_resync_final, tb_drops_final;
    reg        j1, j2, j3eq, j3pos, j4, j5, j6, allok;
    initial begin
        reset_n = 0; dp_clk_en = 1; dp_rst_dp = 0; fe_hold = 0; stall_mode = 0;
        repeat (20) @(posedge gclk);
        reset_n = 1;
        K_restart = 3;
        if (ARM_CTRL) begin
            // ---- CTRL 臂: 注入挪到帧间 IFG (FIFO 空 + FE 冻结 ⇒ 确定性) ----
            guard = 0;
            while ((si < IDX_STOP_IFG) && (guard < 2000000)) begin @(posedge gclk); guard = guard + 1; end
            fe_hold = 1;
            // 等 FIFO 真空 (4 个连续 dpc 沿 empty; 含 mac_rx_64 内部管线的自然排空)
            guard = 0;
            while (!(rx_empty && rx_empty_r1 && rx_empty_r2 && rx_empty_r3) && (guard < 100000)) begin
                @(posedge dpc); guard = guard + 1;
            end
            $display("F3R WITNESS ctrl-precond si=%0d (IFG=[%0d,%0d]) rx_empty=%b stable4=%b",
                     si, 3*(FBYTES+IFG)+FBYTES, 3*(FBYTES+IFG)+FBYTES+IFG-1,
                     rx_empty, (rx_empty && rx_empty_r1 && rx_empty_r2 && rx_empty_r3));
            if (!(rx_empty && rx_empty_r1 && rx_empty_r2 && rx_empty_r3))
                $display("F3R CTRL-PRECOND-FAIL (注入点不是干净的帧间隙)");
        end else begin
            // ---- F/L/M 臂: 跑到重启点 (FE 正在收第 3 帧的中段) ----
            guard = 0;
            while ((si < IDX_STOP) && (guard < 2000000)) begin @(posedge gclk); guard = guard + 1; end
        end
        W_snap = fe_dut_acc;
        $display("F3R STOP at si=%0d (frame K=%0d); W_snap=%0d fe_acc=%0d", si, K_restart, W_snap, fe_acc);
        dp_rst_dp = 1;                     // 失锁: 复位断言 (异步)
        $display("F3R WITNESS dp_rst_dp RISE at %0t (t0)", $time);
        repeat (2) @(posedge gclk);
        stall_mode = 1;
        dp_clk_en = 0;                     // 时钟停摆
        repeat (1500) @(posedge gclk);
        dp_clk_en = 1;                     // 重锁: 时钟恢复
        stall_mode = 0;
        repeat (4) @(posedge dclk);
        #0.1 dp_rst_dp = 0;                // 4 个 clk_dp 后释放
        // ⚠️ 这个 #0.1 是**必须**的 (不是随手加): 若在 dclk 沿上释放, 该沿对"TB 相位计数"
        //    与"DP 侧时序逻辑"是**两个不同视图** (xsim 同刻求值竞态, 本仓坑 17 同族) ——
        //    实测症状 = pop_post 比 taken_post + rsw 恰好多 1 (该沿弹掉 1 个字但 DUT 仍在
        //    复位 ⇒ 字被静默丢弃且不计入 rsw)。硬件上该沿对两侧都是"仍在复位"(FF 在沿上
        //    才更新) ⇒ 沿后 0.1ns 释放才是与硬件同视图的写法。
        $display("F3R WITNESS dp_rst_dp FALL at %0t (t1) stall_edges=%0d (应=0) rstwin_edges=%0d (应>0)",
                 $time, stall_edges, rstwin_edges);
        if (ARM_CTRL) fe_hold = 0;         // FE 恢复
        $display("F3R RELOCK: fe_acc=%0d dut_acc=%0d (窗口内静默丢 %0d)",
                 fe_acc, fe_dut_acc, fe_acc - fe_dut_acc);
        // 跑完所有帧 + 排空
        guard = 0;
        while ((si < nstim) && (guard < 4000000)) begin @(posedge gclk); guard = guard + 1; end
        repeat (4000) @(posedge gclk);
        stat_resync_final = u_vs.stat_resync_words;
        tb_drops_final    = tb_drops;
        // ---- 判定每个交付帧 ----
        n_frag = 0; n_stale = 0; n_whole = 0; n_unrec = 0; n_trunc_crs = 0; n_srco_nz = 0;
        for (p = 0; p < ndel && p < MAXF; p = p + 1) begin
            found = -1; srcf = -1; srco = -1;
            // 注意: 不能用 `found < 0` 做循环条件 —— 候选不匹配时 found 被置 0,
            // 会把循环一起终止 (t9 第一版 TB 的 bug, 导致全部报 UNRECOGNIZED)。
            for (f = 0; f < NFR; f = f + 1) begin
                for (off = 0; off <= CLEN; off = off + 8) begin
                    if (((off + dlen[p]) <= CLEN) && (srcf < 0)) begin
                        found = 1;
                        for (q = 0; q < dlen[p]; q = q + 1)
                            if (deliv[p*512 + q] !== cbyte(f, off + q)) found = 0;
                        if (found == 1) begin srcf = f; srco = off; end
                    end
                end
            end
            if (found != 1) begin
                n_unrec = n_unrec + 1;
                $display("F3R DELIV[%0d] len=%0d UNRECOGNIZED crs=%b", p, dlen[p], dcrs[p]);
                if (p < 2) begin
                    $write("   ACT: ");
                    for (q = 0; q < 16 && q < dlen[p]; q = q + 1) $write("%02x ", deliv[p*512+q]);
                    $write("   EXP(f3,24): ");
                    for (q = 0; q < 16; q = q + 1) $write("%02x ", cbyte(3, 24+q));
                    $write("   EXP(f4,0 ): ");
                    for (q = 0; q < 16; q = q + 1) $write("%02x ", cbyte(4, q));
                    $write("\n");
                end
            end else if ((srco == 0) && (dlen[p] == CLEN)) begin
                n_whole = n_whole + 1;
                $display("F3R DELIV[%0d] len=%0d WHOLE 帧%0d crs=%b tuser_direct=%b tuser_legacy=%b",
                         p, dlen[p], srcf, dcrs[p], d_fu[p], dtuser[p]);
            end else begin
                n_frag = n_frag + 1;
                if (srco != 0) n_srco_nz = n_srco_nz + 1;
                if (srcf <= K_restart) n_stale = n_stale + 1;
                if (dcrs[p]) n_trunc_crs = n_trunc_crs + 1;
                $display("F3R DELIV[%0d] len=%0d **片段** 源帧=%0d 偏移=%0d crs=%b tuser_direct=%b %s",
                         p, dlen[p], srcf, srco, dcrs[p], d_fu[p],
                         (srcf <= K_restart) ? "<== 陈字(重启前就开始收的帧)" : "(重启后才收到的字)");
            end
        end
        // ---- J1..J6 ----
        j1   = (n_frag == 0) && (n_trunc_crs == 0) && (n_unrec == 0);
        j2   = (ndel > 0) && (d_fu[0] === 1'b1);
        j3eq = (stat_resync_final == tb_drops_final);
        j3pos= (stat_resync_final > 0);
        j4   = (pop_post == taken_post + stat_resync_final);
        pushes_after = fe_dut_acc - W_snap;
        stale_words  = (dw_all > pushes_after) ? (dw_all - pushes_after) : 32'd0;
        j5   = (stale_words == 0) && (n_srco_nz == 0);
        j6   = (n_unrec == 0) && (n_whole == (NFR - K_restart - 1));
        allok= j1 && j2 && j3eq && j4 && j5 && j6 && (j3pos || (ARM_CTRL == 1));
        $display("F3R SHAPE ndel=%0d whole=%0d frag=%0d stale_frag=%0d trunc_with_crs=%0d unrec=%0d srco_nz=%0d",
                 ndel, n_whole, n_frag, n_stale, n_trunc_crs, n_unrec, n_srco_nz);
        $display("F3R PURPOSE fe_acc=%0d dut_acc=%0d silent_drop=%0d mac_frames=%0d mac_drop=%0d ovf=%0d",
                 fe_acc, fe_dut_acc, fe_acc - fe_dut_acc, st_frames, st_drop, st_ovf);
        $display("F3R POP-ACCT pop_pre=%0d pop_rst=%0d pop_post=%0d taken_all=%0d taken_post=%0d rsw=%0d mirror=%0d",
                 pop_pre, pop_rst, pop_post, taken_all, taken_post, stat_resync_final, tb_drops_final);
        $display("F3R STALE-CONSERV dw_all=%0d pushes_after=%0d => stale_words=%0d %s",
                 dw_all, pushes_after, stale_words,
                 (stale_words != 0) ? "<== 重启后交付了重启前的字!" : "(无陈字)");
        $display("F3R RESYNC-WIT resync_final=%b (F/CTRL 臂应=1; L/M1/M2 变体按各自语义) dpc_edges=%0d",
                 u_vs.resync, dpc_edges);
        $display("F3R J1 frag=%0d trunc_with_crs=%0d unrec=%0d => %s",
                 n_frag, n_trunc_crs, n_unrec, j1?"PASS":"FAIL");
        $display("F3R J2 first_frame_first_word_tuser=%b (direct) legacy=%b => %s",
                 d_fu[0], dtuser[0], j2?"PASS":"FAIL");
        $display("F3R J3 rsw=%0d mirror=%0d eq=%0d pos=%0d => %s",
                 stat_resync_final, tb_drops_final, j3eq, j3pos,
                 (j3eq ? ((j3pos||ARM_CTRL)?"PASS":"POS-FAIL") : "EQ-FAIL"));
        $display("F3R J4 pop_post=%0d taken_post=%0d rsw=%0d => %s",
                 pop_post, taken_post, stat_resync_final, j4?"PASS":"FAIL");
        $display("F3R J5 stale_words=%0d srco_nz=%0d => %s",
                 stale_words, n_srco_nz, j5?"PASS":"FAIL");
        $display("F3R J6 whole=%0d expected=%0d unrec=%0d => %s",
                 n_whole, NFR-K_restart-1, n_unrec, j6?"PASS":"FAIL");
        // 单行判据汇总 (bat 用**单一字面量** grep; 避免管道/括号在 cmd 里的脆弱点)
        $display("F3R CHK J1=%b J2=%b J3eq=%b J3pos=%b J4=%b J5=%b J6=%b ALL=%b",
                 j1, j2, j3eq, j3pos, j4, j5, j6, allok);
        if (!j1 && (n_frag >= 1) && (n_trunc_crs >= 1))
            $display("F3R XFAIL-REPRODUCED frag=%0d trunc_with_crs=%0d stale_frag=%0d",
                     n_frag, n_trunc_crs, n_stale);
        if (allok) $display("F3R ALL PASS");
        $finish;
    end

    // 真空探针 (在 while 循环里用): rx_empty 的短历史 (声明已在仪器 1 块内)
    always @(posedge dpc or negedge reset_n) begin
        if (!reset_n) begin rx_empty_r1 <= 1'b1; rx_empty_r2 <= 1'b1; rx_empty_r3 <= 1'b1; end
        else begin rx_empty_r1 <= rx_empty; rx_empty_r2 <= rx_empty_r1; rx_empty_r3 <= rx_empty_r2; end
    end

    initial begin
        #200000000;
        $display("F3R TIMEOUT si=%0d ndel=%0d", si, ndel);
        $finish;
    end
endmodule
