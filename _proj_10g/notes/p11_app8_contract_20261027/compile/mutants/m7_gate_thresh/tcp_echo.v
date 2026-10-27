`timescale 1ns/1ps
// TCP echo: tcp_rx 载荷流 + meta + fend/ferr -> frame_fifo (坏帧回卷) -> tcp_tx_frame。
// 帧级判定 (fend) 后才开始转发 -> 端到端延迟 = 帧长 (echo 为测试件)。
//
// 与 udp_echo 的差异:
// - meta 只有 conn_id (寻址由 CAM/TCB 负责); conn_id 进独立 FIFO 随帧排队
//   (udp_echo 单 meta 寄存器在背靠背判定时会串扰, 此处无此问题)
// - tcp_rx 对纯 ACK 段也发 fend (无载荷), 用 has_data 跟踪过滤: 只有出现过
//   meta_valid 的帧才进判定 (tcp_rx 的 meta_valid 仅 plen>0 时发)
// - 零长数据帧不存在 (TCP 无零长数据段), 无 ztx 路径
// - 帧边界由 tcp_tx_frame 的 s_axis_tready 天然隔离 (S_WAIT 起 tready=0,
//   新帧首字被挡住直到 S_IDLE), 无需额外握手
// ---- P11 P3 (2026-10-18): D/AW 参数化 (设计件 §4.5) ----
//   默认 D=8192/AW=13 = 今天的 64KB frame_fifo + 14 位指针 —— **行为/端口宽度
//   与改动前逐位相同** (C1/C3 回归锚)。
//   C4 每口传 D=16384/AW=14 = 128KB: 8 条 12KB 连接全落一口 (8+0) 时
//   Σwinq = 96KB < 128KB, 满足"每口物理 RX 缓冲 >= 该口所有连接配额之和"。
//   D 必须是 2 的幂 (frame_fifo 的 NB=D/512 与指针回绕逻辑要求)。
module tcp_echo #(
    parameter integer D  = 8192,
    parameter integer AW = 13,
    // P11 APP8 v6 (REVIEW_V5): 每连接接收占用。默认 0 = 与现役逐位等价；
    // C4 8×12KB 修复臂 (0x35) = 1。参数必须由 wrapper 的 P11_APP8_OCC 宏下发。
    parameter         PER_CONN_OCC = 1'b0
) (
    input  wire        clk,
    input  wire        rst_n,
    // 来自 tcp_rx
    input  wire [63:0] s_axis_tdata,
    input  wire [7:0]  s_axis_tkeep,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,
    input  wire [1:0]  s_axis_tuser,   // [0]=crc_ok (TLAST 拍)
    input  wire        fend,
    input  wire        ferr,
    input  wire        meta_valid,
    input  wire [3:0]  meta_conn_id,
    input  wire [15:0] meta_len,
    // 到 tcp_tx_frame (载荷 + tid = meta_conn_id 随帧排队)
    output wire [63:0] m_axis_tdata,
    output wire [7:0]  m_axis_tkeep,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast,
    output wire [3:0]  m_axis_tid,
    // 统计
    output reg  [31:0] stat_echo,
    output reg  [31:0] stat_drop_crc,
    // P4b-7-P6 tlast 三计数探针 (定位 tlast 死于哪一级):
    //   stat_tlast_wr  = 帧末拍写入 frame_fifo 的次数 (accept && s_axis_tlast)
    //   stat_tlast_fwd = 帧末拍转发出去的次数 (fwd_rd && fdout[72])
    // 纯计数, 无行为耦合; 与 stat_tlast_in (tcp_tx_frame) 对账:
    //   wr>fwd  => tlast 死在 frame_fifo 内 / fwd<in => 死在 pipe
    output reg  [31:0] stat_tlast_wr,
    output reg  [31:0] stat_tlast_fwd,
    // P4b-7-P6 调试探针 (纯 assign, 不动逻辑): 帧 FIFO 满 (P4c: 8192 字 = 64KB)
    output wire        dbg_fifo_full,
    // P4b-7-P6 诊断 (UART RX 侧快照, 纯 assign): echo FSM + frame_fifo 深度/指针
    output wire [2:0]  dbg_state,          // echo FSM state (2 位有效, 3 位零扩)
    output wire        dbg_fifo_empty,     // frame_fifo empty
    output wire [AW:0] dbg_fifo_wptr,      // frame_fifo wptr[AW:0] (默认 AW=13: 14 位)
    output wire [AW:0] dbg_fifo_rptr,      // frame_fifo rptr[AW:0] (默认 AW=13: 14 位)
    // P4b-7-P6 tlast 位图转储 (UART 侧): 边存槽址 -> 该槽边存值 (bit8 = tlast);
    // 组合读, 上游 u_fifo mem_s (LUTRAM) 直通, 与 echo 逻辑零耦合
    input  wire [AW-1:0] dbg_rd_addr,      // frame_fifo 边存读址 (默认 AW=13: 13 位)
    output wire [8:0]  dbg_rd_side,        // 该址边存值 [8]=tlast [7:0]=tkeep
    // ---- P11 APP8 v6: 每连接占用 (PER_CONN_OCC=1) ----
    // 读口地址 = app_ctrl 的 o_winq_rd_id（与 winq 读口同址同拍）；输出在模块内
    // 打一拍并带 id（REVIEW_V5 F5），app_ctrl 用 id 匹配后再算 fq。
    input  wire [3:0]  i_occ_rd_id,
    output wire [16:0] o_occ_rd,          // 饱和到 17 位 (131,071)
    output wire [3:0]  o_occ_rd_id,       // 与 o_occ_rd 同拍的 id
    output wire [31:0] stat_occ_underflow,
    output wire [31:0] stat_cq_ovf
);

    localparam [1:0] S_IDLE = 2'd0, S_FWD = 2'd1;
    // 深度相关的计数宽度 (默认 8192 字 = 今天的 6 位; 16384 字 = 7 位)
    localparam integer FQW   = (D <= 8192) ? 6 : 7;   // 已判定好帧队列深度位宽
    localparam integer CQ_AW = (D <= 8192) ? 6 : 7;   // conn_id 队列深度/位宽
    localparam integer CQ_DEPTH = (1 << CQ_AW);       // 128 (D=16384) / 64 (D=8192)

    reg  [1:0]  state;
    reg         first_b;
    reg         has_data;               // 本帧有载荷 (meta_valid 见过)
    reg         pend;                   // fend 已见, 等载荷末字实际交付
    reg         p_err;                  // 本帧坏 (fend 拍锁存)
    reg         rback;                  // 回卷脉冲 (判定拍)
    reg  [FQW-1:0] fq;                  // 已判定好帧队列深度 (cq 深度冗余, fq 是权威计数;
                                        // 默认 6 位 (8192 字, 帧数上界 ~44); 16384 字 ⇒ 7 位)

    wire        accept = s_axis_tvalid && s_axis_tready;
    wire [72:0] fdin   = {s_axis_tlast, s_axis_tkeep, s_axis_tdata};
    wire [72:0] fdout;
    wire        fifo_empty, fifo_full;
    wire [3:0]  cq_dout;
    wire        cq_empty, cq_full;
    wire        fwd_rd  = (state == S_FWD) && m_axis_tvalid && m_axis_tready;
    wire        judged  = pend && (accept && s_axis_tlast);

    // s_axis_tready 由文件末尾 generate 按 PER_CONN_OCC 生成（默认分支逐字 = !fifo_full）
    assign m_axis_tdata  = (state == S_FWD) ? fdout[63:0] : 64'h0;
    assign m_axis_tkeep  = (state == S_FWD) ? fdout[71:64] : 8'h00;
    assign m_axis_tlast  = (state == S_FWD) ? fdout[72] : 1'b0;
    assign m_axis_tvalid = (state == S_FWD) && !fifo_empty;
    assign m_axis_tid    = cq_dout;

    // P4b-7 弹性实录: 重传回卷会话 (ring 每会话最多重发 RING_CAP 字节) 期间
    // tcp_tx_frame 只喂 ring 不接新帧 -> 回声管道被饿死; 2048 字 ≈ 11 帧 +
    // mac_rx 1 帧余量刚够单会话 (P3 gate 50: 0 丢失), 但 50+60 双会话背靠背
    // (≈17 帧) 差 1 帧 -> mac 丢 1 个 PC 数据帧, 静态 PC 永不重发 -> 永久空洞.
    // P4c: 窗 12KB -> 48KB (RING_CAP 0xBFFE = 49150B ≈ 34 帧), 深度同步加深到
    // 8192 字 = 64KB ≈ 44 帧 (双会话 ~68 帧的极端情形仍靠 PC RTO 自愈);
    // cq/fq 同步加宽防判定后入队截断 (cq 满则 judged 帧滞留 fifo 且 fq 失配).
    // 深度仍满足 ≥ 单帧 190 字.
    frame_fifo #(.W(73), .D(D), .AW(AW)) u_fifo (
        .clk(clk), .rst_n(rst_n),
        .wr(accept), .din(fdin),
        .snap(accept && first_b),
        .rollback(rback),
        .rd(fwd_rd), .dout(fdout),
        .empty(fifo_empty), .full(fifo_full),
        .dbg_wptr(dbg_fifo_wptr), .dbg_rptr(dbg_fifo_rptr),
        .dbg_empty(dbg_fifo_empty),
        .dbg_rd_addr(dbg_rd_addr), .dbg_rd_side(dbg_rd_side)
    );

    // conn_id 队列: 判定好帧推入, 转发完弹出 (与载荷帧同序)
    wire cq_push = judged && !p_err;
    wire cq_pop  = fwd_rd && fdout[72];
    fifo_sync #(.W(4), .D(1 << CQ_AW), .AW(CQ_AW)) u_cq (   // 与 frame_fifo 深度同比例
        .clk(clk), .rst_n(rst_n),
        .wr(cq_push && !cq_full), .din(meta_conn_id),
        .rd(cq_pop), .dout(cq_dout),
        .empty(cq_empty), .full(cq_full)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; first_b <= 1'b1;
            has_data <= 1'b0; pend <= 1'b0; p_err <= 1'b0; rback <= 1'b0;
            fq <= {FQW{1'b0}};
            stat_echo <= 0; stat_drop_crc <= 0;
            stat_tlast_wr <= 0; stat_tlast_fwd <= 0;
        end else begin
            rback <= 1'b0;
            // P4b-7-P6 tlast 探针: 写入拍 = 本帧末 beat 进 frame_fifo (每帧 1 次)
            if (accept && s_axis_tlast) stat_tlast_wr <= stat_tlast_wr + 32'd1;
            if (accept && first_b) first_b <= 1'b0;
            if (meta_valid) has_data <= 1'b1;

            // ---- 帧判定 (与转发并发, 不依赖 state); 纯 ACK 段 (无 meta) 不进 pend ----
            if (fend && has_data && !pend) begin
                pend <= 1'b1;
                p_err <= ferr;
            end else if (judged) begin
                pend <= 1'b0;
                // P4b-7-P6 审查 P1-7: judged 拍与下一帧 meta_valid 同拍时
                // (重传风暴 + fifo 满边缘时序), 旧写法 has_data<=0 后写覆盖
                // meta_valid 的置位 -> 新帧 has_data 丢失 -> 其 fend 不置
                // pend -> 帧不判定滞留 fifo。改: 同拍有 meta 则保留。
                has_data <= meta_valid;
                first_b <= 1'b1;
                if (p_err) begin
                    rback <= 1'b1;
                    stat_drop_crc <= stat_drop_crc + 1;
                end
                // 好帧: cq_push 入队 (组合, 本拍)
            end

            // fq 权威计数 (cq_empty 是弹前值, 不能用于帧尾判决)
            case ({cq_push, cq_pop})
                2'b10: fq <= fq + 1'b1;
                2'b01: fq <= fq - 1'b1;
                default: ;
            endcase

            // ---- 转发 ----
            case (state)
                S_IDLE: begin
                    if (fq != {FQW{1'b0}}) state <= S_FWD;
                end
                default: begin   // S_FWD: 顺序转发; 末字拍弹 conn, fq==1 则回 IDLE
                    if (fwd_rd && fdout[72]) begin
                        stat_echo <= stat_echo + 1;
                        stat_tlast_fwd <= stat_tlast_fwd + 32'd1;   // P4b-7-P6 末拍转发账
                        if (fq == 1) state <= S_IDLE;
                    end
                end
            endcase
        end
    end

    // ---- P4b-7-P6 调试探针 assign (纯线束, 与上述逻辑零耦合) ----
    assign dbg_fifo_full = fifo_full;
    assign dbg_state     = {1'b0, state};
    // dbg_fifo_empty/dbg_fifo_wptr/dbg_fifo_rptr: u_fifo 的 dbg_* 输出直通模块口
    // (实例输出 net == 模块输出 net, 无额外驱动)

    //=========================================================================
    // P11 APP8 v6: 每连接占用 (PER_CONN_OCC)
    //   occ[c] = 连接 c 在本口 echo FIFO 中未消费的物理字数 x 8。
    //   写 +8 = accept (与 frame_fifo.wr 同拍, tready = !fifo_full ⇒ accept ⇒ wr_ok)
    //   读 -8 = fwd_rd (与 frame_fifo.rd 同拍)
    //   回卷 -8*rb_words = rback 拍 (frame_fifo 同拍 wptr<=wsnap), 含末字
    //   ★ 主判据 (TB): 逐拍 sum(occ) == (wptr-rptr)<<3; 另配逐 tid 参考模型。
    //   ★ 读口在模块内寄存并带 id (REVIEW_V5 F5); app_ctrl 用 id 匹配后再算 fq。
    //   ★ 帧首门: fq<CQ_DEPTH-2 ⇒ 启动时 fq<=125, push 后 <=126 < 128; cq 永不满。
    //=========================================================================
    generate if (PER_CONN_OCC) begin : g_occ
        assign s_axis_tready = !fifo_full && !rback &&
                               (!first_b || (fq < CQ_DEPTH));

        reg [17:0] occ [0:15];
        reg [3:0]  cur_cid, rb_cid, occ_id_q;
        reg [13:0] cur_words, rb_words;
        reg [17:0] occ_rd_q;
        reg [31:0] stat_occ_underflow_r, stat_cq_ovf_r;

        wire [3:0]  cid_w  = first_b ? meta_conn_id : cur_cid;
        wire [13:0] cw_n   = first_b ? 14'd1 : cur_words + 14'd1;
        wire        wr_ev  = accept;
        wire        rd_ev  = fwd_rd;
        wire        rb_ev  = rback;
        wire [3:0]  rd_cid = cq_dout;

        integer k;
        reg signed [19:0] delta_k;
        reg signed [19:0] sum_k;

        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                cur_cid <= 4'd0; cur_words <= 14'd0;
                rb_cid  <= 4'd0; rb_words  <= 14'd0;
                occ_rd_q <= 18'd0; occ_id_q <= 4'd0;
                stat_occ_underflow_r <= 32'd0; stat_cq_ovf_r <= 32'd0;
                for (k = 0; k < 16; k = k + 1) occ[k] <= 18'd0;
            end else begin
                if (accept && first_b) cur_cid <= meta_conn_id;
                if (accept) begin
                    if (judged) cur_words <= 14'd0;
                    else        cur_words <= cw_n;
                end
                if (judged) begin
                    rb_cid   <= cid_w;
                    rb_words <= cw_n;          // 含末字; 单字帧 cw_n=1
                end
                if (judged && cq_full)         // 构造不可达 (帧首门); 只计数
                    stat_cq_ovf_r <= stat_cq_ovf_r + 32'd1;

                for (k = 0; k < 16; k = k + 1) begin
                    delta_k = 20'sd0;
                    if (wr_ev && (cid_w  == k[3:0])) delta_k = delta_k + 20'sd8;
                    if (rd_ev && (rd_cid == k[3:0])) delta_k = delta_k - 20'sd8;
                    if (rb_ev && (rb_cid == k[3:0]))
                        delta_k = delta_k - (20'sd8 * $signed({1'b0, rb_words}));
                    sum_k = $signed({2'b0, occ[k]}) + delta_k;
                    if (sum_k < 20'sd0) begin
                        occ[k] <= 18'd0;
                        stat_occ_underflow_r <= stat_occ_underflow_r + 32'd1;
                    end else if (sum_k > 20'sd262143) begin
                        occ[k] <= 18'h3FFFF;
                    end else begin
                        occ[k] <= sum_k[17:0];
                    end
                end

                // 读口寄存 (1 拍延迟) + id; app_ctrl 用 id 匹配
                occ_rd_q <= occ[i_occ_rd_id];
                occ_id_q <= i_occ_rd_id;
            end
        end

        assign o_occ_rd    = occ_rd_q[17] ? 17'h1FFFF : occ_rd_q[16:0];
        assign o_occ_rd_id = occ_id_q;
        assign stat_occ_underflow = stat_occ_underflow_r;
        assign stat_cq_ovf        = stat_cq_ovf_r;
    end else begin : g_noocc
        assign s_axis_tready = !fifo_full;   // 与 0x34 (OCC 关) 逐位等价
        assign o_occ_rd = 17'd0;
        assign o_occ_rd_id = 4'd0;
        assign stat_occ_underflow = 32'd0;
        assign stat_cq_ovf = 32'd0;
    end endgenerate

endmodule
