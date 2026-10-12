`timescale 1ns/1ps
//=============================================================================
// tb_mir_uram_fifo.v — URAM 板内缓冲 (rtl/mir_uram_fifo.v) 的**单元门** (自检式, 无 Python)
//=============================================================================
// 被测 = rtl/mir_uram_fifo.v (镜像 aux 口 ↔ C2H AXIS 成形器 之间的 URAM 缓冲)
// ⚠️ 判据名一律**纯 ASCII 且 ≤ 32 字符** (xsim 经 [255:0] 端口传字符串: 非 ASCII 逐字节损坏;
//    超 32 字符会**从左侧截断** ⇒ 判据 ID 前缀消失 —— 2026-10-13 复核轮 F5 教训;
//    bat 里有 NAME-TRUNC 守卫: 每条 [PASS]/[FAIL] 行都必须以 "] G" 开头接 ID)。
//
// ⭐ 本门的两条**独立**口径 (缺一条都属于"判据没牙"):
//   ① **流完整性 (黑盒)**: 把"被取走的字序列"记进期望队列, 每次 `dn_gnt` 拿 `dn_data`
//      与队列头**逐字比对** ⇒ 丢字/重复/错序/相位错**全部**被抓 (不是只查总数)。
//   ② **结构性监视 (白盒, hierarchical)**: 直读 DUT 内部的三条"静默丢字"不变式
//      (到达拍弹性堆满 / 满态还写 URAM / clr 拍取数) + 幻影弹 + `wp` 外部流水账互核
//      + ⭐ clr 拍弹字 (F3) + ⭐ 复位期取数 (F2)。
//   ⚠️ `dn_gnt` 必须**同拍**给出正确数据 (成形器就按这个合同吃字): 本门比的正是
//      `dn_data` 在 `dn_gnt` 那一拍的值, 不做延迟采样。
//
// 判据分组 (每条对着一个具体失效模式):
//   G0  复位态: en=0 ⇒ up_req=0; 空 ⇒ dn_gnt=0
//   G1  基本流: 源无限 + 下游快弹 ⇒ 逐字一致零错
//   G2  ⭐ **恰好满 + 长停收 + 释放**: ① 停在 **occ == 4096 (DEPTH)** (白盒钉容量)
//       ② 取走字数 ∈ [DEPTH, DEPTH+OQ] ③ 满态 up_req 恒 0 (20 拍) ④ 弹 1 字 ⇒ ≤3 拍内 req 回来
//       ⑤ 释放后**全序列**逐字出来 (弹性堆/在飞里的字一个不少)
//   G3  ⭐ **恰空 + 首字延迟**: 空态 req=1 也不弹 (30 拍); 源放行 ⇒ 首字 2..6 拍内到且正确
//   G4  相位/节奏扫描: 源空档与下游停收各用**独立 LFSR** (互不成简单比例) ⇒ 3000 拍零错
//   G5  ⭐ **clr = 窗口边界 ⇒ 丢弃**: (a) clr 拍**不取数** (结构性)  (b) clr 后弹出的第一个字
//       必须是 **post-clr** 的字 (期望队列已重同步 ⇒ 漏出旧字必 seq_err)  (c) 丢弃量 > 0
//   G5b clr 时弹性堆/在飞里还有未弹字 ⇒ 同样必须丢干净
//   G6  `en=0` (停排空) ⇒ up_req 恒 0 (镜像 FIFO 保持 ⇒ MIR_STATUS/MIR_DATA 读侧语义不变)
//   G7  吞吐: 稳态 **1 字/拍** (300 拍里 >= 270 个弹出; 理论上限 300)
//   G8  长流跨绕回: 双侧随机空档跑 24000 拍 (> 2*DEPTH 字, 多次绕回) ⇒ 零错 + 全核销
//   GR  ⭐ (2026-10-13 F2) **复位中途**: en=1 期间拉低 rst_n ⇒ **不许取数** (up_req/dn 全 0);
//       释放后窗口重置 + 零错 + 流照常 (判据锚 = "复位期一个字都不进")
//   GC  ⭐ (2026-10-13 F3) **dn_req 保持 1 横穿 clr 拍**: clr 拍 **dn_gnt 必须 0**
//       (旧式会把上一窗口头字弹出去 —— 该组合在旧 TB 里零覆盖, 复核 F3 点名)
//   GB  ⭐ (2026-10-13 F4) **连续两拍 clr** (背靠背): 不取数/不弹字/清零后流完好
//   G9  监视/互核总计: arr_full / wr_full / clr_take / clr_pop / rst_take / 幻影弹 / `wp`-流水账**全 0 差**
//   RG  (仅 `-d URAM_TB_ROGUE`) guard 有牙臂: 违约驱动 up_gnt ⇒ 必须命中 RTL 守卫 `$display`
//
// 接线模型 (两侧都按**真实对手**的合同):
//   · 上游 = 镜像 aux 口的**生产端**: 源字是"虚拟无限队列"(组合出字, 序号入低位) +
//     任务/LFSR 控制的空档; 成交判据 = `up_req && !src_hold` (**无 req 绝不成交**, 同镜像)。
//   · 下游 = 成形器: `dn_req` 由任务/LFSR 驱动, **只在 `dn_gnt` 那拍取 `dn_data`**。
//   ⚠️ 激励纪律 (工程坑 3/17): task 侧电平变化一律在 **negedge** 落笔, 不在 posedge 同一步
//      阻塞赋值 (那会与 DUT 采样竞争)。
//
// 白盒引用 (hierarchical): `u_dut.occ / inv / o_occ / arr_v / u_wr / ufull / v_sr / wp` ——
//   只用于**监视**与"恰好满/恰空"两个结构性锚, 不参与激励。
//
// run: sim/p9_uram/run_tb_mir_uram_fifo.bat [real|guard_rogue|mut_*]
//=============================================================================
module tb_mir_uram_fifo;

    localparam AW = 12, DEPTH = (1 << AW), OQ = 4;      // 必须与 wrapper 例化参数一致
    localparam [2:0] OQ3 = OQ;

    // ---- 时钟: pcie_axi_aclk 250MHz (4ns; 与板上同) ----
    reg clk = 1'b0;
    always #2.0 clk = ~clk;

    integer fails = 0;
    task chk(input [255:0] name, input [31:0] got, input [31:0] exp);
        begin
            if (got === exp) $display("  [PASS] %0s = %0d", name, got);
            else begin $display("  [FAIL] %0s = %0d (期望 %0d)", name, got, exp); fails = fails + 1; end
        end
    endtask
    task chk1(input [255:0] name, input got, input exp);
        begin
            if (got === exp) $display("  [PASS] %0s = %b", name, got);
            else begin $display("  [FAIL] %0s = %b (期望 %b)", name, got, exp); fails = fails + 1; end
        end
    endtask
    task chk_range(input [255:0] name, input integer got, input integer lo, input integer hi);
        begin
            if ((got >= lo) && (got <= hi)) $display("  [PASS] %0s = %0d (带 [%0d,%0d])", name, got, lo, hi);
            else begin $display("  [FAIL] %0s = %0d (期望 %0d..%0d)", name, got, lo, hi); fails = fails + 1; end
        end
    endtask

    // ---------------- DUT ----------------
    reg         rst_n    = 1'b0;
    reg         en       = 1'b0;
    reg         clr_m    = 1'b0;
    reg         src_hold = 1'b1;      // 任务控制 (negedge 落笔): 1 = 源暂停
    reg         dn_req_m = 1'b0;      // 任务控制 (negedge 落笔)
    reg         dn_pat   = 1'b0;      // 1 = dn_req 走 LFSR 随机停收
    reg         src_rand = 1'b0;      // 1 = 源空档走 LFSR 随机
    wire        up_req, up_gnt, dn_gnt;
    wire [63:0] up_data, dn_data;
    wire [AW:0] dbg_occ;
    wire [2:0]  dbg_oocc;

    // 两个独立 LFSR (确定性伪随机; 多项式/种子都不同 ⇒ 相位不成简单比例)
    reg [15:0] lfsr_src = 16'h1ACE;
    reg [15:0] lfsr_dst = 16'h2BDF;
    always @(posedge clk) begin
        lfsr_src <= {lfsr_src[14:0], lfsr_src[15] ^ lfsr_src[13] ^ lfsr_src[12] ^ lfsr_src[10]};
        lfsr_dst <= {lfsr_dst[14:0], lfsr_dst[15] ^ lfsr_dst[14] ^ lfsr_dst[12] ^ lfsr_dst[11]};
    end
    wire src_hold_v = src_rand ? (lfsr_src[9] & lfsr_src[5]) : src_hold;   // ~25% 空档
    wire dn_req_v   = dn_pat  ? lfsr_dst[7] : dn_req_m;                    // ~50% 停收

    mir_uram_fifo #(.AW(AW), .LAT(3), .OQ(OQ)) u_dut (
        .clk (clk), .rst_n (rst_n), .en (en), .clr (clr_m),
        .up_req (up_req), .up_gnt (up_gnt), .up_data (up_data),
        .dn_req (dn_req_v), .dn_gnt (dn_gnt), .dn_data (dn_data),
        .dbg_occ (dbg_occ), .dbg_oocc (dbg_oocc)
    );

    // ---------------- 上游源模型 (镜像 aux 生产端; **虚拟无限队列**) ----------------
    //   字 = 组合量, 低位嵌入绝对序号 ⇒ 丢字/重复/错序都会与期望队列**逐字**不等。
    //   成交判据 = `up_req && !src_hold_v` (镜像同款: 无 req 绝不成交)。
    integer sq_r = 0;                                   // 已成交字数 (本块唯一写者)
    wire [63:0] src_word = {32'hC0DE_0000 + sq_r[15:0], 32'hBEEF_0000 + sq_r[15:0]};
`ifdef URAM_TB_ROGUE
    // ⭐ guard 有牙臂专用 (仅 `-d URAM_TB_ROGUE`; real/mut 臂的源模型逐字不变):
    //   违约驱动 —— `src_rogue=1` 时 up_gnt=1 而**不看** up_req (上游违契) ⇒ RTL 守卫必须响。
    reg src_rogue = 1'b0;
    assign up_gnt  = src_rogue ? 1'b1 : (up_req && !src_hold_v);
    assign up_data = src_rogue ? 64'hDEAD_BEEF_CAFE_F00D : src_word;
`else
    assign up_gnt  = up_req && !src_hold_v;
    assign up_data = src_word;
`endif
    always @(posedge clk) if (up_gnt) sq_r <= sq_r + 1;

    // ---------------- 期望队列 + 对账 + 结构性监视 (单一 always 块; 一个变量一个写者) ----------------
    reg  [63:0] eq_mem [0:65535];
    integer     eq_w = 0, eq_r = 0;        // 取走数 / 已核销数
    integer     eq_drop = 0;               // clr/复位按定义丢弃的悬空字总数
    integer     seq_err = 0, over_err = 0;
    integer     arr_full = 0, wr_full = 0, clr_take = 0, pop_empty = 0;
    integer     clr_pop = 0;               // ⭐ F3: clr 拍 dn_gnt (结构上必须恒 0)
    integer     rst_take = 0;              // ⭐ F2: 复位期取数 (up_req||up_gnt; 必须恒 0)
    reg         clr_sync_req = 1'b0;       // task-only (negedge 置; 本块清)
    reg         dbg_trace = 1'b0;          // 诊断开关 (块内 print 用; 必须先声明 —— 工程坑 24)
    always @(posedge clk) begin
        if (clr_sync_req) begin
            eq_drop <= eq_drop + (eq_w - eq_r);            // 窗口边界/复位: 悬空字按定义丢弃
            eq_r    <= eq_w;
            clr_sync_req <= 1'b0;
            if (dbg_trace) $display("  [DBG-SYNC] t=%0t eq_w=%0d eq_r=%0d eq_drop=%0d", $time, eq_w, eq_r, eq_drop);
        end else if (dn_gnt) begin
            if (eq_r >= eq_w) over_err <= over_err + 1;    // 弹出多于取走 (幻影弹)
            else begin
                if (dn_data !== eq_mem[eq_r & 65535]) seq_err <= seq_err + 1;
                eq_r <= eq_r + 1;
            end
        end
        if (up_gnt) begin eq_mem[eq_w & 65535] <= up_data; eq_w <= eq_w + 1; end
        // ---- 结构性监视 (白盒; 三条"静默丢字"不变式 + 幻影弹 + clr 拍取数 + F2/F3) ----
        if (rst_n && !clr_m) begin
            if (u_dut.arr_v && (u_dut.o_occ == OQ3))  arr_full  <= arr_full + 1;
            if (u_dut.u_wr && u_dut.ufull)            wr_full   <= wr_full + 1;
            if (dn_gnt && (u_dut.o_occ == 3'd0))      pop_empty <= pop_empty + 1;
        end
        if (clr_m && (up_req || up_gnt)) clr_take <= clr_take + 1;   // clr 拍取数 = 静默丢字
        if (clr_m && dn_gnt)             clr_pop  <= clr_pop + 1;    // ⭐ F3: clr 拍弹字
        if (!rst_n && en && (up_req || up_gnt)) rst_take <= rst_take + 1;  // ⭐ F2: 复位期取数
    end

    // ---------------- 激励助手 (全部在 negedge 落笔; 工程坑 3/17) ----------------
    task set_src_hold(input v); begin @(negedge clk); src_hold = v; @(negedge clk); end endtask
    task set_dn_req (input v); begin @(negedge clk); dn_req_m = v; @(negedge clk); end endtask
    task do_clr;
        // 时序 (逐拍): [N] clr=1 ⇒ [N+1] 上升沿 = clr 拍 (DUT 清零, 上游 req=0 不成交)
        //   ⇒ 同一 cycle 的 negedge 撤 clr + 置 sync_req ⇒ [N+2] 上升沿把期望队列跳到"当前取走数"
        //   (此刻 post-clr 的第一次成交尚未落账 ⇒ 只丢 pre-clr 悬空字, 不误丢新字)。
        begin
            @(negedge clk); clr_m = 1'b1;
            @(negedge clk); clr_m = 1'b0; clr_sync_req = 1'b1;
            @(posedge clk);                       // 同步拍
            @(negedge clk);
        end
    endtask

    integer i, j, t_wait, first_gnt_cyc, first_gnt_seen, w0, r0, p0;
    integer clr_pop0, clr_take0, rst_req_viol;

    initial begin
        $display("=== tb_mir_uram_fifo: P9 URAM 板内缓冲单元门 ===");
        rst_n = 0; en = 0; clr_m = 0; src_hold = 1; dn_req_m = 0; dn_pat = 0; src_rand = 0;
        repeat (8) @(posedge clk);

        // ---------------- G0: 复位态 ----------------
        $display("  --- G0: reset state (en=0 / 空) ---");
        chk1("G0a up_req == 0 (en=0)", up_req, 1'b0);
        chk1("G0b dn_gnt == 0 (empty)",   dn_gnt, 1'b0);
        chk ("G0c dbg_occ == 0", dbg_occ, 32'd0);
        rst_n = 1;
        repeat (4) @(posedge clk);

        // ---------------- G1: 基本流 ----------------
        $display("  --- G1: basic flow (源无限 + 下游快弹) ---");
        set_src_hold(0); set_dn_req(1); en = 1'b1;
        w0 = eq_w; r0 = eq_r;
        repeat (200) @(posedge clk);
        $display("  [DBG] G1: taken=%0d popped=%0d seq_err=%0d over_err=%0d", eq_w - w0, eq_r - r0, seq_err, over_err);
        chk_range("G1a taken >= 150 words", eq_w - w0, 150, 200);
        chk ("G1b word-by-word: seq_err", seq_err, 0);
        chk ("G1c no phantom pop: over_err",    over_err, 0);

        // ---------------- G2: 恰好满 + 长停收 + 释放 ----------------
        $display("  --- G2: exact-full + long stall + release ---");
        dbg_trace = 1'b1;
        do_clr;
        w0 = eq_w; r0 = eq_r; p0 = eq_w - eq_r;
        $display("  [DBG] G2-start: eq_w=%0d eq_r=%0d p0=%0d eq_drop=%0d over_err=%0d", eq_w, eq_r, p0, eq_drop, over_err);
        src_rand = 0; set_src_hold(0); set_dn_req(0);          // 下游停收 ⇒ 只进不出
        t_wait = 0;
        while ((up_req !== 1'b0) && (t_wait < (DEPTH + 200))) begin @(posedge clk); t_wait = t_wait + 1; end
        $display("  [DBG] G2: require-drop after %0d cyc; occ=%0d inv=%0d taken=%0d",
                 t_wait, u_dut.occ, u_dut.inv, eq_w - w0);
        chk ("G2a CAPACITY-PIN: occ == 4096", u_dut.occ, DEPTH);
        chk_range("G2b taken in [DEPTH, DEPTH+OQ]", eq_w - w0, DEPTH, DEPTH + OQ);
        j = 0;
        for (i = 0; i < 20; i = i + 1) begin @(posedge clk); if (up_req !== 1'b0) j = j + 1; end
        chk ("G2c full-state up_req stays 0", j, 0);
        set_dn_req(1);                                         // 弹 1 个字 ⇒ req 应很快回来
        j = 0;                                                 // (从 dn_req 落笔那刻起数拍)
        first_gnt_seen = 0;
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk);
            if (!first_gnt_seen && (up_req === 1'b1)) begin first_gnt_seen = 1; j = i; end
        end
        chk ("G2d req back after pop <= 8cyc", first_gnt_seen, 1);
        chk_range("G2d2 req re-assert cyc in [0,6]", j, 0, 6);
        chk_range("G2e occ in DEPTH-8..DEPTH-1", u_dut.occ, DEPTH - 8, DEPTH - 1);
        set_src_hold(1);                                       // ⭐ 先停源, 再全排空 (否则缓冲永远满)
        repeat (DEPTH + 600) @(posedge clk);
        $display("  [DBG] G2-end: taken=%0d popped=%0d occ=%0d inv=%0d",
                 eq_w - w0, eq_r - r0, u_dut.occ, u_dut.inv);
        $display("  [DBG] G2-acc: eq_w=%0d eq_r=%0d eq_drop=%0d over_err=%0d", eq_w, eq_r, eq_drop, over_err);
        dbg_trace = 1'b0;
        // ⭐ 身份式 (窗口起始悬空 p0 已计入; 排空后悬空 0 ⇒ taken == popped + p0)
        //    —— 一个字被取走后静默丢失 ⇒ 该式永久不闭合。
        chk ("G2f drain: popped-taken == p0",
             (eq_r - r0) - (eq_w - w0), p0);
        chk ("G2g word-by-word zero error", seq_err, 0);

        // ---------------- G3: 恰空 + 首字延迟 ----------------
        $display("  --- G3: exact-empty + first-word latency ---");
        set_src_hold(1);                                       // ⭐ 先停源, 再清 (否则空态是假的)
        do_clr;
        set_dn_req(1);
        r0 = eq_r; w0 = eq_w;
        repeat (30) @(posedge clk);
        chk ("G3a empty+req: 0 pops / 30cyc", eq_r - r0, 0);
        chk1("G3b empty dn_gnt == 0", dn_gnt, 1'b0);
        set_src_hold(0);                                       // 源放行 ⇒ 首字应在 2..6 拍内
        first_gnt_cyc = 0; first_gnt_seen = 0;
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk);
            if (!first_gnt_seen && dn_gnt) begin first_gnt_seen = 1; first_gnt_cyc = i; end
        end
        chk ("G3c first word popped <= 20cyc", first_gnt_seen, 1);
        chk_range("G3d first-word cyc in [2,6]", first_gnt_cyc, 2, 6);
        chk ("G3e word-by-word zero error", seq_err, 0);
        chk_range("G3f outstanding words in [0,5]", eq_w - eq_r, 0, OQ + 1);

        // ---------------- G4: 双侧独立随机空档 (相位扫描) ----------------
        $display("  --- G4: independent random gaps on both sides (3000 cyc) ---");
        src_rand = 1; dn_pat = 1;
        w0 = eq_w; r0 = eq_r;
        repeat (3000) @(posedge clk);
        src_rand = 0; dn_pat = 0; set_dn_req(1); set_src_hold(0);
        repeat (400) @(posedge clk);                           // 部分排空 (不做全核销)
        $display("  [DBG] G4: taken=%0d popped=%0d seq_err=%0d over_err=%0d",
                 eq_w - w0, eq_r - r0, seq_err, over_err);
        chk_range("G4a taken >= 500 (stream alive)", eq_w - w0, 500, 100000);
        chk ("G4b word-by-word zero error", seq_err, 0);
        chk ("G4c no phantom pop", over_err, 0);

        // ---------------- G5: clr = 窗口边界 ⇒ 丢弃 ----------------
        $display("  --- G5: clr = window boundary -> DISCARD (no stale, no take) ---");
        set_dn_req(0); set_src_hold(0);                        // 先攒出"悬空字" (取走还没弹走)
        repeat (40) @(posedge clk);
        chk_range("G5a outstanding words at stall", eq_w - eq_r, 1, 1000000);
        do_clr;                                                // clr 拍的结构性检查在监视块
        $display("  [DBG] G5: eq_drop=%0d (clr 丢弃的悬空字)", eq_drop);
        chk_range("G5b clr drops outstanding words", eq_drop, 1, 1000000);
        chk ("G5c no take on clr cycle", clr_take, 0);
        set_dn_req(1); set_src_hold(0);                        // 新窗口: 不许有 pre-clr 字节
        repeat (200) @(posedge clk);
        chk ("G5d new window: zero error", seq_err, 0);

        // ---------------- G5b: clr 时弹性堆/在飞里有未弹字 ----------------
        $display("  --- G5b: clr while elastic/in-flight holds unpopped words ---");
        set_dn_req(0); set_src_hold(0);
        repeat (12) @(posedge clk);
        chk_range("G5b-a unpopped words (inv>=2)", {29'd0, u_dut.inv}, 2, OQ);
        do_clr;
        set_dn_req(1); set_src_hold(0);
        repeat (200) @(posedge clk);
        chk ("G5b-b post-clr zero error", seq_err, 0);
        chk ("G5b-c no phantom pop", over_err, 0);

        // ---------------- G6: en=0 ⇒ 不取数 ----------------
        $display("  --- G6: en=0 -> up_req stays 0 (镜像 FIFO 保持) ---");
        set_dn_req(0);
        en = 1'b0;
        repeat (4) @(posedge clk);
        j = 0;
        for (i = 0; i < 30; i = i + 1) begin @(posedge clk); if (up_req !== 1'b0) j = j + 1; end
        chk ("G6a up_req stays 0 while en=0", j, 0);
        en = 1'b1;
        repeat (8) @(posedge clk);
        chk1("G6b up_req re-asserts after en=1", up_req, 1'b1);

        // ---------------- G7: 吞吐 (稳态 1 字/拍) ----------------
        $display("  --- G7: sustained throughput (target: ~1 word/cycle) ---");
        set_dn_req(1); set_src_hold(0);
        repeat (50) @(posedge clk);                            // 预热
        r0 = eq_r;
        repeat (300) @(posedge clk);
        $display("  [DBG] G7: popped=%0d / 300 cyc", eq_r - r0);
        chk_range("G7a pops/300cyc >= 270", eq_r - r0, 270, 400);
        chk ("G7b word-by-word zero error", seq_err, 0);

        // ---------------- G8: 长流跨绕回 ----------------
        $display("  --- G8: long stream across wrap (24000 cyc, both sides random) ---");
        do_clr;
        src_rand = 1; dn_pat = 1;
        w0 = eq_w; r0 = eq_r; p0 = eq_w - eq_r;
        repeat (24000) @(posedge clk);
        src_rand = 0; dn_pat = 0; set_dn_req(1); set_src_hold(1);   // ⭐ 先停源, 再全排空
        repeat (2*DEPTH + 600) @(posedge clk);                 // 全排空 (缓冲最多存 DEPTH+OQ)
        $display("  [DBG] G8: taken=%0d popped=%0d seq_err=%0d over_err=%0d",
                 eq_w - w0, eq_r - r0, seq_err, over_err);
        chk_range("G8a taken > 2*DEPTH (wraps)", eq_w - w0, 2*DEPTH + 1, 10000000);
        chk ("G8b word-by-word zero error", seq_err, 0);
        chk ("G8c no phantom pop", over_err, 0);
        chk ("G8d drained: popped-taken == p0", (eq_r - r0) - (eq_w - w0), p0);

        // ---------------- GR: 复位中途 (F2 修复的判据; en=1 期间拉低 rst_n) ----------------
        //   ⭐ 复位期"一个字都不进": 写门含 rst_n ⇒ up_req 恒 0 ⇒ 上游不成交 (旧式会在复位期
        //   把字收进 `wp` 被钳住的缓冲 = "取走但永不交付"的静默丢字通道, 复核 F2)。
        $display("  --- GR: reset mid-stream (rst_n low while en=1) ---");
        set_dn_req(0); set_src_hold(0);                        // 源持续就绪 + 下游停收 ⇒ 攒悬空字
        repeat (40) @(posedge clk);
        chk_range("GR0 outstanding words pre-reset", eq_w - eq_r, 1, 1000000);
        rst_req_viol = 0;
        @(negedge clk); rst_n = 1'b0;
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk);
            if ((up_req !== 1'b0) || (up_gnt !== 1'b0)) rst_req_viol = rst_req_viol + 1;
        end
        chk ("GR1 no take/req in rst (10cyc)", rst_req_viol, 0);
        @(negedge clk); rst_n = 1'b1; clr_sync_req = 1'b1;
        @(posedge clk);                                        // 同步拍 (DUT 同时出复位)
        @(negedge clk);
        chk ("GR2 post-reset zero error", seq_err, 0);
        w0 = eq_w;
        set_dn_req(1);
        repeat (200) @(posedge clk);
        chk_range("GR3 post-reset stream alive", eq_w - w0, 50, 1000000);

        // ---------------- GC: dn_req 保持 1 横穿 clr 拍 (F3 修复的判据) ----------------
        //   ⭐ clr 拍 **dn 侧不交付**: 旧式 `pop = dn_req && o_occ!=0` (不含 !clr) 会在 clr 拍
        //   把上一窗口的头字弹出去 (`o_occ` 到沿才清) —— 旧 TB 在 do_clr 前总先 set_dn_req(0)
        //   ⇒ 该组合零覆盖 (复核 F3)。本场景把 dn_req 保持 1 横穿 clr 拍。
        $display("  --- GC: dn_req held high across clr (F3) ---");
        set_dn_req(0); set_src_hold(0);
        repeat (40) @(posedge clk);                            // 攒悬空字 (dn_req=0 ⇒ 只进不出)
        chk_range("GC0 outstanding words pre-clr", eq_w - eq_r, 1, 1000000);
        clr_pop0 = clr_pop;
        @(negedge clk); dn_req_m = 1'b1;                       // dn_req 保持 1 (含 clr 拍)
        @(negedge clk); clr_m = 1'b1;                          // 下一拍 = clr 拍
        @(negedge clk); clr_m = 1'b0; clr_sync_req = 1'b1;
        @(posedge clk);                                        // 同步拍
        @(negedge clk);
        chk ("GC1 clr_pop monitor == 0", clr_pop - clr_pop0, 0);
        w0 = eq_w;
        set_dn_req(1); set_src_hold(0);
        repeat (200) @(posedge clk);
        chk ("GC2 clr: no stale leak", seq_err, 0);
        chk_range("GC3 clr: stream alive after", eq_w - w0, 50, 1000000);

        // ---------------- GB: 连续两拍 clr (F4 补臂; 背靠背) ----------------
        $display("  --- GB: back-to-back clr (2 cycles high) ---");
        set_dn_req(0); set_src_hold(0);
        repeat (40) @(posedge clk);
        chk_range("GB0 outstanding words pre-2clr", eq_w - eq_r, 1, 1000000);
        clr_take0 = clr_take; clr_pop0 = clr_pop;
        @(negedge clk); clr_m = 1'b1;
        @(posedge clk);                                        // clr 拍 #1
        @(negedge clk);                                        // clr 保持高 (不撤)
        @(posedge clk);                                        // clr 拍 #2 (背靠背)
        @(negedge clk); clr_m = 1'b0; clr_sync_req = 1'b1;
        @(posedge clk);                                        // 同步拍
        @(negedge clk);
        chk ("GB1 2clr: no clr_take", clr_take - clr_take0, 0);
        chk ("GB2 2clr: no clr_pop",  clr_pop  - clr_pop0,  0);
        w0 = eq_w;
        set_dn_req(1); set_src_hold(0);
        repeat (200) @(posedge clk);
        chk ("GB3 2clr: post-clr zero err", seq_err, 0);
        chk_range("GB4 2clr: stream still alive", eq_w - w0, 50, 1000000);
        set_src_hold(1);                                       // ⭐ 停源 ⇒ 全排空 (G9e 终态账)
        repeat (DEPTH + 600) @(posedge clk);
        chk ("GB5 2clr: drained account closed", eq_w - eq_r, 0);

        // ---------------- G9: 监视与互核 ----------------
        $display("  --- G9: structural monitors + cross-accounting ---");
        chk ("G9a arr_full (arrival vs full)",    arr_full, 0);
        chk ("G9b wr_full (write vs full)",       wr_full, 0);
        chk ("G9c pop_empty (phantom pop)",       pop_empty, 0);
        chk ("G9d clr_take (take on clr cycle)",  clr_take, 0);
        chk ("G9f clr_pop total == 0",            clr_pop, 0);
        chk ("G9g rst_take total == 0",           rst_take, 0);
        // ⭐ 全局账 (终态源停 + 已排空): **取走总数 == 核销总数** ⇒ 无字卡在模块里。
        //   —— 静默丢字检测器: 任一个字被取走后没弹出, `eq_w != eq_r` 就永久不闭合。
        //   (⚠️ 不能用 `eq_r + eq_drop == eq_w`: 同步跳变已把 eq_drop 计进 eq_r, 会双重计。)
        chk ("G9e FINAL: eq_w == eq_r closed", eq_w, eq_r);

        // ---------------- 收尾 ----------------
        set_dn_req(0); set_src_hold(1);
        repeat (8) @(posedge clk);
        if (fails == 0) $display("URAM_FIFO_GATE: PASS_ALL");
        else            $display("URAM_FIFO_GATE: FAIL (%0d checks failed)", fails);
`ifdef URAM_TB_ROGUE
        // ================= RG: guard 有牙臂 (仅 -d URAM_TB_ROGUE) =================
        // 目的 = 证明 RTL 守卫 `FATAL mir_uram_fifo: upstream grant without req` **真的会响**。
        //   en=0 ⇒ up_req 恒 0 ⇒ `src_rogue=1` 时 up_gnt=1 而**上游无 req** ⇒ 必须命中该守卫串。
        //   ⚠️ 本块**故意破坏 DUT 记账** (u_wr 写入) ⇒ 只允许 arm `guard_rogue` 使用;
        //   对照臂 `mut_guard_off` (删守卫 `$display`) 在本块下**必须看不见**该串
        //   (bat 侧: `guard_rogue` 期望串出现 / `mut_guard_off` 期望串不出现 —— 互为牙)。
        $display("  --- RG: rogue up_gnt without up_req (guard teeth) ---");
        set_dn_req(0); set_src_hold(1);
        en = 1'b0;
        repeat (4) @(posedge clk);
        src_rogue = 1'b1;
        repeat (4) @(posedge clk);
        src_rogue = 1'b0;
        $display("  [DBG] RG: rogue window done (up_req stayed 0; guard must have fired)");
`endif
        $display("=== done ===");
        $finish;
    end

    initial begin #8000000; $display("TIMEOUT"); $finish; end

endmodule
