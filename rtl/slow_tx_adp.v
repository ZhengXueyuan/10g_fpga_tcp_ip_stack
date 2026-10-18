`timescale 1ns/1ps
// 慢路径 TX 适配器: HLS udp_echo 的 tx_stream (16bit, bit8=TLAST) -> 64bit 字流。
//
// HLS MAC TX 契约 (layer_mac.cpp): 完整线上帧 = 7x0x55+0xD5 前导 | dst..payload
// (含 pad 到 60B) | FCS 4B (LSB-first), tlast 在最后一个 FCS 字节。
// 本适配器: 剥前导 (跳过 0x55..0xD5), 4 字节回持剥 FCS, 剩余内容打包成左对齐字流。
// FCS 由 mac_tx_64 重新计算追加 — HLS 的 FCS 字节直接丢弃, 天然避免双重 FCS。
//
// 结构: tx_stream -> 9bit 字节 FIFO -> 字节 FSM (剥前导/剥 FCS/打包)
//       -> frame_fifo (整帧字缓冲, commit@tlast) -> AXIS 字流 -> tx_arb。
// 整帧字缓冲后才对 tx_arb 可见: 字节产生速率 (<=1B/拍, 带空洞) 远低于字消费
// 速率 (8B/拍), 不整帧缓冲会让 mac_tx_64 欠载中止。
module slow_tx_adp #(
    // P11 P2-甲: 1 = 从帧内容提取源 IP/ARP SPA 选出口端口位 (side FIFO);
    //             0 = 原行为 (o_port=0, side FIFO 不例化)
    parameter        PER_PORT = 1'b0,
    parameter [31:0] IP_B     = 32'hFFFFFFFF,
    parameter        SIDE_DEPTH = 128     // 1 位 x SIDE_DEPTH (纸面: 64 帧上限的 2x)
) (
    input  wire        clk,
    input  wire        rst_n,
    // HLS udp_echo tx_stream (TDATA = {6'b0, TLAST, byte})
    input  wire [15:0] hls_tx_tdata,
    input  wire        hls_tx_tvalid,
    output wire        hls_tx_tready,
    // AXIS 字流输出 (去 tx_arb)
    output wire [63:0] m_axis_tdata,
    output wire [7:0]  m_axis_tkeep,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast,
    output reg  [31:0] stat_frames,    // 成功转出帧数
    output reg  [31:0] stat_purge,     // 前导非法/fifo 满回卷帧数
    // P7B-latent (2026-09-30): 字 FIFO 拒写次数 —— **结构上恒 0** (契约见 fifo_sync.v
    // 头注释与 frame_fifo.v 的 full_next 注释)。非 0 = 有已计入的字被静默丢弃。
    output reg  [31:0] stat_fifo_ovf,   // u_wf 拒写次数 (恒 0; 非 0 = 静默丢失)
    // ---- P11 P2-甲: 每帧出口端口位 (帧内稳定; PER_PORT=0 恒 0) ----
    output wire        o_port,
    output reg  [31:0] stat_side_ovf,   // side FIFO 拒 push 次数 (正臂恒 0; 负控用)
    output wire [7:0]  side_level       // side FIFO 占用 (== committed 是硬不变式)
);
    // ---------------- HLS -> 9bit 字节 FIFO ----------------
    // FWFT 契约 (铁律 #4): rd 必须与消费同拍 (组合), 寄存器化 rd 会让同一字节
    // 在总线上挂 2 拍被二次处理 — 本模块曾因 i_rd/wf_rd 寄存器化双采被审查抓获。
    wire [8:0] i_dout;
    wire       i_empty, i_full;
    wire       i_rd;

    assign hls_tx_tready = !i_full;
    fifo_sync #(.W(9), .D(2048), .AW(11)) u_ififo (
        .clk(clk), .rst_n(rst_n),
        .wr(hls_tx_tvalid && hls_tx_tready), .din({hls_tx_tdata[8], hls_tx_tdata[7:0]}),
        .rd(i_rd), .dout(i_dout), .empty(i_empty), .full(i_full)
    );

    // ---------------- 字节 FSM 状态 ----------------
    localparam T_IDLE = 2'd0, T_PRE = 2'd1, T_DATA = 2'd2, T_PURGE = 2'd3;
    reg [1:0]  tstate;
    reg [3:0]  skip_cnt;
    reg [31:0] hold;          // 回持最近 4 字节 (帧尾 4 = FCS, 丢弃)
    reg [2:0]  hc;            // hold 有效数 0..4
    reg [63:0] pw;            // 打包字 (字节索引直写, 左对齐; 整字写出后清零)
    reg [3:0]  pc;            // 已打包字节数 0..7
    reg        abort;
    reg [7:0]  committed;
    reg        commit_pulse;

    // ---- P11 P2-甲: 源 IP / VLAN 提取 (PER_PORT=1 时活) ----
    reg  [5:0]  bpos;         // 帧内内容字节索引 (饱和 63)
    reg  [39:0] src_sr;       // 内容字节移位窗 (最近 5 字节)
    reg  [15:0] etype_r;      // 帧字节 12..13 (以太类型)
    reg  [31:0] src_ip_lat;   // IPv4 源 IP / ARP SPA
    reg         ip_seen;      // 本帧已识别源 IP
    reg         vlan_seen;    // 本帧出现 0x8100/0x88A8 (L-10; sticky 到帧末)
    reg         side_push;    // 提交拍: 本帧出口位
    reg         play_port;    // 正在播放帧的端口位

    // 输出播放器状态
    // committed 语义: 提交未开播的帧数; O_IDLE 开播拍即 -1 (不等播完) —
    // 与 slow_rx_adp 同病同药: 播完再减会让 O_IDLE 读到旧值幻影开播。
    localparam O_IDLE = 1'b0, O_SEND = 1'b1;
    reg        ostate;

    // 字 frame_fifo = {tlast, tkeep, tdata} 73 位; rd 组合 (FWFT 同拍消费)
    // ⚠️ 写口合同 (P7B-latent 修复, 2026-09-30): `wf_wr` 是**寄存器** (本轮决定、
    //    下拍落笔) ⇒ 空间门必须用 `wf_full_next` (**下一拍**的精确满值), 不能用本拍
    //    `wf_full`。用本拍 `full` 有一拍错位: "本拍 full=0 (511 占) + 本拍还有一笔在飞
    //    写" ⇒ 下拍 full=1 ⇒ 该笔写被 frame_fifo **静默丢弃**。命中相位时丢的正是
    //    **帧末字 (带 tlast)** ⇒ 帧已 commit (stat_frames++), 而线上该帧永远不闭合
    //    (与 app_udp_pattern 的 P7B-W9 同族; 同款修法先例 fifo_sync 头注释 /
    //    mac_rx_64.v:131 / app_udp_pattern.v:497)。可达性构造与反例双跑见
    //    `_proj_10g/notes/P7B_LATENT_FIFO_FIX.md`。
    reg         wf_wr, wf_snap, wf_rlbk;
    reg  [72:0] wf_din;
    wire [72:0] wf_dout;
    // wf_full 修复后**不再被读** (保留连线只为排障/未来使用; 空间门一律 full_next)。
    wire        wf_empty, wf_full, wf_full_next, wf_ovf;
    wire        wf_rd;

    frame_fifo #(.W(73), .D(512), .AW(9)) u_wf (
        .clk(clk), .rst_n(rst_n),
        .wr(wf_wr), .din(wf_din),
        .snap(wf_snap), .rollback(wf_rlbk),
        .rd(wf_rd), .dout(wf_dout), .empty(wf_empty), .full(wf_full),
        .dbg_rd_addr(9'd0), .dbg_rd_side(),  // P6c 诊断读口未用 (tcp_echo 实例才接)
        .full_next(wf_full_next),            // P7B-latent: 空间门 (下一拍满)
        .ovf_pulse(wf_ovf)                   // P7B-latent: 拒写脉冲 (自检, 恒 0)
    );
    // 无静默丢失自检回读 (合同: 生产侧必须把拒写接成计数器, 恒 0 才叫无丢字)。
    // 修复后**结构性恒 0** (写门 = !full_next ⇒ 落笔拍 full 必为 0); 一旦生产者判据
    // 回归本拍 `full`, 它立刻会响 ⇒ 这是一条有牙齿的回归守卫。
    // ⚠️ 板级可见性: 本计数器已是模块输出端口 (`stat_fifo_ovf`)。要进快照窗口需
    //    在 `board/wrapper_p4.v` 三处加 (① 端口连线 ② 快照字打包 ③ 文档表) ——
    //    本轮**未接** (该文件归另一个 agent), 见笔记 §可见性。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) stat_fifo_ovf <= 32'd0;
        else if (wf_ovf) stat_fifo_ovf <= stat_fifo_ovf + 32'd1;
    end

    wire start_play = (ostate == O_IDLE) && (committed != 8'd0) && !wf_empty;

    // ---- P11 P2-甲: side FIFO (1 位 x SIDE_DEPTH) + 端口位输出 ----
    // 写口: commit_pulse 拍把本帧 (ip_seen && !vlan_seen && src_ip_lat==IP_B) 入队;
    // 读口: start_play 拍弹出到 play_port (与 committed 同步, 每帧恰一次)。
    // side_level == committed 是硬不变式 (只在 PER_PORT=1 检查)。
    assign o_port = PER_PORT ? play_port : 1'b0;

    generate
    if (PER_PORT) begin : g_side
        localparam SW = $clog2(SIDE_DEPTH);
        reg        side_mem [0:SIDE_DEPTH-1];
        reg [SW-1:0] s_wr, s_rd;
        reg [SW:0]   s_level;
        wire side_empty = (s_level == 0);
        wire side_full  = (s_level == SIDE_DEPTH);
        wire side_do_push = commit_pulse && !side_full;
        wire side_do_pop  = start_play && !side_empty;

        assign side_level = s_level[7:0];

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                s_wr <= {SW{1'b0}}; s_rd <= {SW{1'b0}}; s_level <= 0;
                play_port <= 1'b0; stat_side_ovf <= 32'd0;
            end else begin
                if (side_do_push) side_mem[s_wr] <= side_push;
                if (side_do_pop)  play_port <= side_mem[s_rd];
                if (side_do_push && !side_do_pop) s_level <= s_level + 1'b1;
                else if (!side_do_push && side_do_pop) s_level <= s_level - 1'b1;
                if (side_do_push) begin
                    s_wr <= s_wr + 1'b1;
                end
                // P11 P2-甲 (G4 negative control): 计"提交拍侧表已满、端口位被丢"的次数。
                // ⛔ 原写法把 `if (side_full)` 嵌在 `if (side_do_push)` 里，而
                //    `side_do_push = commit_pulse && !side_full` ⇒ 该分支**结构性不可达**
                //    ⇒ `stat_side_ovf` 恒 0（G4 的 SIDE_DEPTH=16 负控把它抓了出来）。
                if (commit_pulse && side_full)
                    stat_side_ovf <= stat_side_ovf + 32'd1;
                if (side_do_pop) s_rd <= s_rd + 1'b1;
            end
        end
    end else begin : g_noside
        assign side_level = 8'd0;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                play_port <= 1'b0; stat_side_ovf <= 32'd0;
            end else begin
                play_port <= 1'b0; stat_side_ovf <= 32'd0;
            end
        end
    end
    endgenerate

    wire [7:0] in_b    = i_dout[7:0];
    wire       in_last = i_dout[8];
    // 组合 rd: T_PRE/T_DATA/T_PURGE 每拍消费当前字节 (T_IDLE 留住帧首字节待判)
    assign i_rd = (tstate != T_IDLE) && !i_empty;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tstate <= T_IDLE; skip_cnt <= 4'd0;
            hold <= 32'd0; hc <= 3'd0; pw <= 64'd0; pc <= 4'd0;
            abort <= 1'b0; committed <= 8'd0;
            wf_wr <= 1'b0; wf_snap <= 1'b0; wf_rlbk <= 1'b0;
            wf_din <= 73'd0; commit_pulse <= 1'b0;
            stat_frames <= 0; stat_purge <= 0;
            bpos <= 6'd0; src_sr <= 40'd0; etype_r <= 16'd0;
            src_ip_lat <= 32'd0; ip_seen <= 1'b0; vlan_seen <= 1'b0;
            side_push <= 1'b0;
        end else begin
            wf_wr <= 1'b0; wf_snap <= 1'b0; wf_rlbk <= 1'b0;
            commit_pulse <= 1'b0;

            case (tstate)
                T_IDLE: if (!i_empty) begin
                    wf_snap  <= 1'b1;          // 快照 = 即将写入的首字槽
                    skip_cnt <= 4'd0;
                    tstate   <= T_PRE;
                end
                T_PRE: if (!i_empty) begin
                    if (in_b == 8'h55 && skip_cnt < 4'd15) begin
                        skip_cnt <= skip_cnt + 4'd1;
                    end else if (in_b == 8'hD5 && skip_cnt >= 4'd4) begin
                        hc   <= 3'd0; pc <= 4'd0; pw <= 64'd0;
                        abort <= 1'b0;
                        // P11: 每帧开始清提取状态 (0x55/D5 已跳过 ⇒ 下一拍 = 内容字节 0)
                        bpos <= 6'd0; src_sr <= 40'd0; etype_r <= 16'd0;
                        ip_seen <= 1'b0; vlan_seen <= 1'b0;
                        tstate <= T_DATA;
                    end else begin
                        tstate <= T_PURGE;     // 前导非法: 吞到 tlast 回卷
                    end
                end
                T_DATA: if (!i_empty) begin
                    // ---- P11: 内容字节索引 + 源 IP/ARP SPA 提取 (零稳态代价:
                    //      与既有字节流水同拍, 只在 bpos 命中时锁存) ----
                    if (bpos != 6'd63) bpos <= bpos + 6'd1;
                    src_sr <= {src_sr[31:0], in_b};
                    if (bpos == 6'd13) begin
                        etype_r <= {src_sr[7:0], in_b};             // 帧字节 12..13
                        if (({src_sr[7:0], in_b} == 16'h8100) ||
                            ({src_sr[7:0], in_b} == 16'h88A8))
                            vlan_seen <= 1'b1;                      // L-10: 强制 o_port=0
                    end
                    if (bpos == 6'd29 && etype_r == 16'h0800) begin
                        src_ip_lat <= {src_sr[23:0], in_b};         // IPv4 源 IP
                        ip_seen    <= 1'b1;
                    end
                    if (bpos == 6'd31 && etype_r == 16'h0806) begin
                        src_ip_lat <= {src_sr[23:0], in_b};         // ARP SPA
                        ip_seen    <= 1'b1;
                    end
                    // 4 字节回持: 满 4 后每来 1 字节, 最老字节毕业进打包器。
                    // in_last 拍毕业字节直接合成末字 (tlast 必须落在帧的最后一个字)。
                    // ⚠️ 空间门用 `wf_full_next` (下一拍满), **不是** `wf_full` ——
                    //    wf_wr 是寄存器, 本拍判据必须预测"落笔那一拍"的满 (P7B-latent)。
                    if (hc == 3'd4 && !wf_full_next && !abort) begin
                        if (pc == 4'd7) begin
                            wf_wr  <= 1'b1;
                            wf_din <= {in_last, 8'hFF, pw[63:8], hold[31:24]};
                            pc     <= 4'd0;
                            pw     <= 64'd0;
                        end else if (in_last) begin
                            wf_wr <= 1'b1;
                            case (pc[2:0])
                                3'd0: wf_din <= {1'b1, 8'h80, hold[31:24], 56'b0};
                                3'd1: wf_din <= {1'b1, 8'hC0, pw[63:56], hold[31:24], 48'b0};
                                3'd2: wf_din <= {1'b1, 8'hE0, pw[63:48], hold[31:24], 40'b0};
                                3'd3: wf_din <= {1'b1, 8'hF0, pw[63:40], hold[31:24], 32'b0};
                                3'd4: wf_din <= {1'b1, 8'hF8, pw[63:32], hold[31:24], 24'b0};
                                3'd5: wf_din <= {1'b1, 8'hFC, pw[63:24], hold[31:24], 16'b0};
                                default: wf_din <= {1'b1, 8'hFE, pw[63:16], hold[31:24], 8'b0};
                            endcase
                        end else begin
                            case (pc[2:0])
                                3'd0: pw[63:56] <= hold[31:24];
                                3'd1: pw[55:48] <= hold[31:24];
                                3'd2: pw[47:40] <= hold[31:24];
                                3'd3: pw[39:32] <= hold[31:24];
                                3'd4: pw[31:24] <= hold[31:24];
                                3'd5: pw[23:16] <= hold[31:24];
                                3'd6: pw[15:8]  <= hold[31:24];
                                default: pw[7:0] <= hold[31:24];
                            endcase
                            pc <= pc + 4'd1;
                        end
                    end else if (hc == 3'd4) begin
                        abort <= 1'b1;               // 字 fifo 满: 本帧作废
                    end
                    hold <= {hold[23:0], in_b};
                    if (hc != 3'd4) hc <= hc + 3'd1;
                    if (in_last) begin
                        // hold 里 4 字节 = FCS, 已随回持丢弃 (永不毕业)
                        // 提交门同样用 full_next: 与"末字下拍一定落笔"同门 ⇒
                        // "commit 了但末字进不去" 这种静默态结构性不存在。
                        if (hc == 3'd4 && !abort && !wf_full_next) begin
                            commit_pulse <= 1'b1;
                            side_push    <= ip_seen && !vlan_seen && (src_ip_lat == IP_B);
                            stat_frames  <= stat_frames + 1;
                        end else begin
                            wf_rlbk    <= 1'b1;      // 退化帧 (内容 <1 字) 或写坏
                            stat_purge <= stat_purge + 1;
                        end
                        tstate <= T_IDLE;
                    end
                end
                T_PURGE: if (!i_empty) begin
                    if (in_last) begin
                        wf_rlbk    <= 1'b1;
                        stat_purge <= stat_purge + 1;
                        tstate     <= T_IDLE;
                    end
                end
                default: tstate <= T_IDLE;
            endcase

            // committed: +1 commit / -1 开播, 同拍互抵
            if (commit_pulse && !start_play)      committed <= committed + 8'd1;
            else if (!commit_pulse && start_play) committed <= committed - 8'd1;
        end
    end

    // ---------------- 输出播放器: 整帧字 -> AXIS ----------------
    assign m_axis_tdata  = wf_dout[63:0];
    assign m_axis_tkeep  = wf_dout[71:64];
    assign m_axis_tlast  = wf_dout[72];
    assign m_axis_tvalid = (ostate == O_SEND) && !wf_empty;
    assign wf_rd         = m_axis_tvalid && m_axis_tready;   // 组合, 同拍消费

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ostate <= O_IDLE;
        end else begin
            case (ostate)
                O_IDLE: if (start_play) ostate <= O_SEND;
                O_SEND: if (m_axis_tvalid && m_axis_tready) begin
                    if (wf_dout[72]) ostate <= O_IDLE;   // tlast 字被消费
                end
            endcase
        end
    end
endmodule
