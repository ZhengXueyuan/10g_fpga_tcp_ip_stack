`timescale 1ns/1ps
//=============================================================================
// tb_app_rx_mirror.v — M1「载荷镜像」的**单元门** (自检式, 无 Python)
//=============================================================================
// 被测 = rtl/app_rx_mirror.v (snoop tap + ^0xA5 + 打包 **64 位字** + 读侧 64→2×32 拆分
//        + fifo_async(dp→pcie) + DMA 排空口 **2 字/拍**)
// ⚠️ 判据名一律 **纯 ASCII** —— xsim 会把经 [255:0] 端口传的非 ASCII 逐字节损坏
//    (本工程实测, 见 tb_fifo_async.v 的同款注释)。
//
// ⭐⭐ 2026-10-11 (P8 阶段三): 本门按**新契约**重写。旧契约 = "写口 32 位 ⇒ 结构吞吐上限 4 B/拍"
//    (板级实测对 8 B/拍源恒丢 50%, 见 `_proj_10g/notes/p8_board_20261011/REPORT.md` §9);
//    新契约 = **源 ≤8 B/拍 ⇒ 结构吞吐类丢字节不可达, 只剩 FIFO 满一类**。
//    随之而来的三条**语义变更** (逐条都有判据钉着):
//      ① 输出粒度 4 B → **8 B** (FIFO 字 = 2 个逻辑字; K % 8 前置) —— G3 钉 (4 B 单独不进账);
//      ② DMA 口 1 字/拍 → **2 字/拍** (dma_data[63:0], `[31:0]` 先出) —— G12c/d 钉;
//      ③ `level` 内部 = 2×occ64 + stash (单位仍是**逻辑 32 位字**) —— G2/G12k/G8c 钉。
//
// 为什么必须有它 (设计件 v2 §V5-A-1):
//   ① **FIFO 写门是本模块的第一号判据** —— 本工程同类缺陷踩过两次 (app_udp_pattern
//      每帧静默丢 8B / 两个适配器 latent), 两次都是"写使能与空间门错拍 ⇒ 丢字不可观测"。
//   ② 字节打包的**字节序**是"错了也只会读出另一个看似合理的值"的一类错 (全链门看不见
//      模块内部), 必须有一处**手算锚**。
//   ③ snoop 合同: 只采样 tvalid && tready, 不驱动任何握手 —— 要有一条"tready=0 的拍
//      一个字都不许采"的断言。
//
// 判据分组 (每条都对着一个具体的失效模式):
//   G0  reset state (empty/level/drop/sticky all 0)
//   G1  cap_en=0 => zero capture (negative control)
//   G2  一个满 8 B 拍 = **1 个 FIFO 字 = 2 个逻辑字** (手算锚 0xF0C3D22D / 0xB48796E1)
//   G3  半拍 keep=0x0F (4 B) **不单独进账** (新粒度契约; level==0) —— 补第二个 4 B 才成字
//       (锚 0xE19687B4 / 0xF0C3D22D)
//   G4  跨拍累加器 1+0+2+1+4 字节 (锚 0x78691E0F / 0xE19687B4)
//   G5  tlast **不** flush (锚 0xF01E0FB4 / 0x691E0F3C)
//   G6  snoop: tready=0 的拍一个字都不许采 (negative control)
//   G7  字节账: offered == 4*字数 (no-drop phase)
//   G12 aux 口 (DMA 排空器): 2 字/拍 + 主机优先 + **混用时 stash 停摆点不丢字**
//   G13 ⭐ **8 B/拍持续源 + aux 排空 ⇒ drop_bytes == 0** (本刀的主判据; 手算账 8N == 4*排空字数)
//       + 每对字与 golden 字节流逐字对账 (锚 = 同一个 golden 模型)
//   G8  ⛔ 旧版是"8B/拍超 4B/拍结构上限 ⇒ 必丢" —— **该构造已随修复不可达** ⇒ 改为
//       **FIFO 满类**构造: 300 拍无排空 ⇒ drop>0 + any_drop + level 卡满量程 (clamp 见证),
//       再全排空 ⇒ 字节账恒等式 (手算: 256 字入 FIFO + 16 B 残余 ⇒ 排空 516 逻辑字 / 丢 336 B)
//   G11 写门在**满**态: 字节账恒等式 (offered == 4*排空字数 + Δdrop) —— 设计件 §V5-A-1 第一号判据
//   G14 **cap_en=0 冻结不复制被握住的字** (旧版缺陷: 冻结期 wr_en 仍 = have&&!full ⇒
//       FIFO 一有空位就重写同一个字, 最多 DEPTH 份) —— 手算: 满 = 256 字 = **512 逻辑字**
//   G9  clr: 排空式冲刷 (level->0) + any_drop 清 + 累加器清 (含 **stash** 清) + drop_bytes 不归零
//   G10 final state: level==0 && empty==1
//
// golden = TB-side byte-stream rebuild (top-n bytes, MSB->LSB order, ^0xA5);
//   ⚠️ golden and DUT are two implementations of the SAME rule => G2..G5/G9/G12/G13 each pin a
//   **hand-computed constant anchor** or a golden-stream comparison (G13).
//   ⚠️ keep contract = **top n bytes valid** (0xFF<<(8-n)); non-contiguous keep is out of
//   contract (module header says the same; 本门用 0x0F 只作为"popcount=4"的写法, 见 G3 注)。
// run: sim/p7b_mir/run_tb_app_rx_mirror.bat [real|mut_gate|mut_order|mut_cap4]
//=============================================================================
module tb_app_rx_mirror;

    // ---- clocks: write = dp_clk 156.25MHz (6.4ns) / read = pcie_axi_aclk 250MHz (4ns) ----
    reg clk_w = 1'b0, clk_r = 1'b0;
    always #3.2 clk_w = ~clk_w;
    always #2.0 clk_r = ~clk_r;

    integer fails = 0;

    task chk(input [255:0] name, input [31:0] got, input [31:0] exp);
        begin
            if (got === exp) $display("  [PASS] %0s = %08x", name, got);
            else begin $display("  [FAIL] %0s = %08x (exp %08x)", name, got, exp); fails = fails + 1; end
        end
    endtask
    task chk64(input [255:0] name, input [63:0] got, input [63:0] exp);
        begin
            if (got === exp) $display("  [PASS] %0s = %016x", name, got);
            else begin $display("  [FAIL] %0s = %016x (exp %016x)", name, got, exp); fails = fails + 1; end
        end
    endtask
    task chk1(input [255:0] name, input got, input exp);
        begin
            if (got === exp) $display("  [PASS] %0s = %b", name, got);
            else begin $display("  [FAIL] %0s = %b (exp %b)", name, got, exp); fails = fails + 1; end
        end
    endtask
    task chkc(input [255:0] name, input integer got, input integer exp);
        begin
            if (got === exp) $display("  [PASS] %0s = %0d", name, got);
            else begin $display("  [FAIL] %0s = %0d (exp %0d)", name, got, exp); fails = fails + 1; end
        end
    endtask

    // ---- DUT stimulus regs (all registered; negedge landing => zero race, traps 3/17) ----
    reg        rst_n = 1'b0;
    reg [63:0] tv_data  = 64'd0;
    reg [7:0]  tv_keep  = 8'd0;
    reg        tv_valid = 1'b0;
    reg        tv_ready = 1'b1;
    reg        tv_last  = 1'b0;
    reg        cap_en   = 1'b0;
    reg        clr_tgl  = 1'b0;
    reg        rd_en_r  = 1'b0;

    wire [31:0] dout;
    wire        empty;
    wire [8:0]  level;
    wire [31:0] drop_bytes;
    wire        any_drop, any_drop_rd;
    // ---- ⭐ 期 B: aux 读口 (DMA 排空器; P8 阶段三起 = 2 字/拍) ----
    reg         dma_req = 1'b0;
    wire        dma_gnt, clr_pulse_rd;
    wire [63:0] dma_data;

    app_rx_mirror #(.XORC(8'hA5)) u_dut (
        .clk          (clk_w),
        .rst_n        (rst_n),
        .s_tdata      (tv_data),
        .s_tkeep      (tv_keep),
        .s_tvalid     (tv_valid),
        .s_tready     (tv_ready),
        .s_tlast      (tv_last),
        .ctrl_cap_en  (cap_en),
        .ctrl_clr_tgl (clr_tgl),
        .rd_clk       (clk_r),
        .rd_rst_n     (rst_n),
        .rd_en        (rd_en_r),
        .dout         (dout),
        .empty        (empty),
        .level        (level),
        .dma_req      (dma_req),
        .dma_gnt      (dma_gnt),
        .dma_data     (dma_data),
        .clr_pulse_rd (clr_pulse_rd),
        .drop_bytes   (drop_bytes),
        .any_drop     (any_drop),
        .any_drop_rd  (any_drop_rd)
    );

    // ---------------- golden model (TB-side byte stream rebuild) ----------------
    localparam integer GMAX = 16384;
    reg  [7:0] gold [0:GMAX-1];
    integer    gold_n   = 0;
    reg        gold_on  = 1'b0;        // on only in no-drop phases
    integer    offered  = 0;           // sum of popcount(keep) over accepted beats

    // golden 逻辑字 k (小端: gold[4k] 是字内首字节 ⇒ 落在 LSB)
    function [31:0] gword(input integer k);
        begin
            gword = {gold[4*k+3], gold[4*k+2], gold[4*k+1], gold[4*k]};
        end
    endfunction

    integer bi, ob;
    integer dgt, tt;                   // ⭐ 期 B: aux 口判据的计数
    always @(posedge clk_w) begin
        // same cycle/value as the DUT (both read pre-edge values => same handshake view)
        // ⚠️ `u_dut.cap_on` 与 DUT 同拍判定 (cap_en=0 时注入的拍**不算** offered)
        if (tv_valid && tv_ready && u_dut.cap_on) begin
            for (ob = 0; ob < 8; ob = ob + 1) if (tv_keep[ob]) offered = offered + 1;
            if (gold_on) begin
                for (bi = 7; bi >= 0; bi = bi - 1) begin
                    if (tv_keep[bi]) begin
                        gold[gold_n] = tv_data[bi*8 +: 8] ^ 8'hA5;
                        gold_n = gold_n + 1;
                    end
                end
            end
        end
    end

    // ---- stimulus tasks ----
    task beat(input [63:0] d, input [7:0] k, input l);
        begin
            @(negedge clk_w); tv_data <= d; tv_keep <= k; tv_last <= l; tv_valid <= 1'b1;
            @(negedge clk_w); tv_valid <= 1'b0;
        end
    endtask
    task set_ready(input r);
        begin @(negedge clk_w); tv_ready <= r; end
    endtask
    task wait_w(input integer n);
        integer i; begin for (i = 0; i < n; i = i + 1) @(posedge clk_w); end
    endtask
    task wait_r(input integer n);
        integer i; begin for (i = 0; i < n; i = i + 1) @(posedge clk_r); end
    endtask

    // ---- readout (FWFT: dout valid while !empty; rd_en pulses one rd cycle) ----
    // ⚠️ 下面 task 引用的 `wv`/`ok_n`/`wc` 必须**先声明** (xvlog 先声明后用 —— 工程坑 22/24)
    integer    wc, ok_n, q, n_burst;
    reg [31:0] wv;
    integer p;
    task pop1(output [31:0] v, output integer ok);
        begin
            ok = 0; v = 32'hxxxxxxxx;
            for (p = 0; p < 4000; p = p + 1) begin
                @(negedge clk_r);
                if (!empty) begin
                    v = dout;
                    rd_en_r <= 1'b1;
                    @(negedge clk_r);
                    rd_en_r <= 1'b0;
                    ok = 1;
                    p = 100000;
                end
            end
        end
    endtask
    task clr_pulse;
        begin
            @(negedge clk_w); clr_tgl <= ~clr_tgl;
            wait_w(6);
        end
    endtask
    // 排空到空 (3 趟: "被握住的字"会在排空后才落笔) —— 返回排空到的**逻辑字数**
    task drain_all(output integer n);
        integer rr;
        begin
            n = 0;
            for (rr = 0; rr < 3; rr = rr + 1) begin
                while (!empty && n < 4000) begin pop1(wv, ok_n); n = n + 1; end
                wait_r(40);
            end
        end
    endtask

    integer    dsave;
    reg [63:0] bd;

    // ---- ⭐ G13 的 aux 排空监视: 计数 + 每对字与 golden 逐字对账 ----------------
    reg     dma_chk_on = 1'b0;
    integer dgnt = 0, dword_mis = 0;
    always @(posedge clk_r) begin
        if (dma_gnt) begin
            if (dma_chk_on) begin
                if ((dgnt*2 + 1) < gold_n) begin
                    if (dma_data[31:0] !== gword(dgnt*2))     dword_mis = dword_mis + 1;
                    if (dma_data[63:32] !== gword(dgnt*2 + 1)) dword_mis = dword_mis + 1;
                end else dword_mis = dword_mis + 1;      // golden 尚未记到 ⇒ 视为错 (不该发生)
            end
            dgnt = dgnt + 1;
        end
    end

    initial begin
        $display("=== tb_app_rx_mirror: M1 payload mirror unit gate (8B/beat contract) ===");
        tv_ready = 1'b1; cap_en = 1'b0; clr_tgl = 1'b0;
        repeat (20) @(posedge clk_w);
        rst_n = 1'b1;
        repeat (10) @(posedge clk_w);

        // ---- G0 reset state ----
        $display("  --- G0: reset state ---");
        chk1("G0a empty == 1", empty, 1'b1);
        chkc("G0b level == 0", level, 0);
        chk ("G0c drop_bytes == 0", drop_bytes, 32'd0);
        chk1("G0d any_drop == 0", any_drop, 1'b0);
        chk1("G0e any_drop_rd == 0", any_drop_rd, 1'b0);

        // ---- G1 cap_en=0 => no capture (negative control) ----
        $display("  --- G1: cap_en=0, inject beats, capture must stay off ---");
        gold_on = 1'b0;
        beat(64'h8877665544332211, 8'hFF, 1'b0);
        wait_w(4);
        beat(64'h0123456789ABCDEF, 8'h0F, 1'b0);
        wait_w(20);
        chkc("G1a cap_en=0 => no capture", level, 0);
        chk ("G1b drop_bytes == 0", drop_bytes, 32'd0);
        chk1("G1c empty == 1", empty, 1'b1);

        // ---- G2 one full 8B beat = 1 FIFO word = 2 logical words (hand anchors) ----
        // data=0x8877665544332211, keep=FF => bytes 88 77 66 55 44 33 22 11
        // word_a = {55',66',77',88'} = {F0,C3,D2,2D} = 0xF0C3D22D
        // word_b = {11',22',33',44'} = {B4,87,96,E1} = 0xB48796E1
        $display("  --- G2: cap_en=1, one full beat => 1 word (= 2 logical words) ---");
        clr_pulse();
        @(negedge clk_w); cap_en <= 1'b1;
        wait_w(6);
        gold_n = 0; offered = 0; gold_on = 1'b1;
        beat(64'h8877665544332211, 8'hFF, 1'b0);
        wait_w(6);
        wait_r(20);
        chkc("G2a level == 2 (2 logical words)", level, 2);
        pop1(wv, ok_n);
        chk ("G2b anchor: word_a == 0xF0C3D22D", wv, 32'hF0C3D22D);
        wait_r(6);
        chkc("G2c level == 1 after first pop", level, 1);
        pop1(wv, ok_n);
        chk ("G2d anchor: word_b == 0xB48796E1", wv, 32'hB48796E1);
        wait_r(10);
        chkc("G2e level == 0 after both pops", level, 0);

        // ---- G3 partial beat (4B) does NOT enqueue alone; a 2nd 4B completes the word ----
        // (新粒度契约的见证: 旧版 4 B 就出一个字, 本版要凑满 8 B)
        // beat1 data=0x1122334455667788 keep=0x0F => 4 bytes 11 22 33 44
        // beat2 data=0x5566778800000000 keep=0xF0 => 4 bytes 55 66 77 88
        // word_a = {44',33',22',11'} = {E1,96,87,B4} = 0xE19687B4
        // word_b = {88',77',66',55'} = {2D,D2,C3,F0} = 0x2DD2C3F0
        $display("  --- G3: 4B partial beat => no word yet (new granularity) ---");
        gold_n = 0; offered = 0;
        beat(64'h1122334455667788, 8'h0F, 1'b1);
        wait_w(8); wait_r(20);
        chkc("G3a level == 0 (4B: no word)", level, 0);
        beat(64'h5566778800000000, 8'hF0, 1'b1);
        wait_w(8); wait_r(20);
        chkc("G3b 2nd 4B completes word", level, 2);
        pop1(wv, ok_n);
        chk ("G3c anchor: word == 0xE19687B4", wv, 32'hE19687B4);
        wait_r(6);
        pop1(wv, ok_n);
        chk ("G3d anchor2 == 0x2DD2C3F0", wv, 32'h2DD2C3F0);
        wait_r(10);

        // ---- G4 cross-beat accumulator 1+0+2+1+4 ----
        $display("  --- G4: accumulator across beats (1+0+2+1+4) ---");
        gold_n = 0; offered = 0;
        beat(64'hAA00000000000000, 8'h80, 1'b0);      // 1 byte: 0xAA
        wait_w(4);
        beat(64'h0000000000000000, 8'h00, 1'b0);      // 0 bytes (no contribution)
        wait_w(4);
        beat(64'hBBCC000000000000, 8'hC0, 1'b0);      // 2 bytes: 0xBB, 0xCC
        wait_w(4);
        beat(64'hDD00000000000000, 8'h80, 1'b0);      // +1 byte: 0xDD => 4 B
        wait_w(6);
        chkc("G4a still <8B => level == 0", level, 0);
        beat(64'h1122334400000000, 8'hF0, 1'b0);      // +4 bytes => complete
        wait_w(6); wait_r(20);
        chkc("G4b complete => level == 2", level, 2);
        pop1(wv, ok_n);
        // stream AA BB CC DD 11 22 33 44 => word_a = {DD',CC',BB',AA'} = {78,69,1E,0F} = 0x78691E0F
        chk ("G4c anchor == 0x78691E0F", wv, 32'h78691E0F);
        wait_r(6);
        pop1(wv, ok_n);
        chk ("G4d anchor2 == 0xE19687B4", wv, 32'hE19687B4);
        chkc("G4e offered == 8", offered, 8);
        chkc("G4f gold_n == 8", gold_n, 8);
        wait_r(10);

        // ---- G5 tlast does not flush ----
        $display("  --- G5: tlast=1 mid-stream does not break the byte stream ---");
        gold_n = 0; offered = 0;
        beat(64'h1122334400000000, 8'h80, 1'b1);      // 1 byte 0x11 + tlast
        wait_w(4);
        beat(64'hAABBCCDD00000000, 8'hC0, 1'b1);      // 2 bytes 0xAA,0xBB + tlast
        wait_w(4);
        beat(64'h5566778800000000, 8'h80, 1'b1);      // 1 byte 0x55 + tlast => 4 B
        wait_w(4);
        chkc("G5a tlast is not flush", level, 0);
        beat(64'h99AABBCC00000000, 8'hF0, 1'b1);      // +4 B + tlast => complete
        wait_w(6); wait_r(20);
        chkc("G5b level == 2", level, 2);
        pop1(wv, ok_n);
        // stream 11 AA BB 55 99 AA BB CC => word_a = {55',BB',AA',11'} = {F0,1E,0F,B4} = 0xF01E0FB4
        chk ("G5c anchor: word == 0xF01E0FB4", wv, 32'hF01E0FB4);
        wait_r(6);
        pop1(wv, ok_n);
        chk ("G5d anchor2 == 0x691E0F3C", wv, 32'h691E0F3C);
        wait_r(10);
        chkc("G5e level == 0 before G6", level, 0);

        // ---- G6 snoop: tready=0 beats are never captured ----
        $display("  --- G6: tready=0 beats must not be captured ---");
        set_ready(1'b0);
        wait_w(2);
        gold_on = 1'b0;
        beat(64'hDEADBEEF00000000, 8'hFF, 1'b0);
        wait_w(4);
        beat(64'hCAFEBABE00000000, 8'hFF, 1'b0);
        wait_w(4);
        beat(64'h0011223300000000, 8'hFF, 1'b0);
        wait_w(6);
        chkc("G6a tready=0 => no capture", level, 0);
        chk1("G6b empty == 1", empty, 1'b1);
        set_ready(1'b1);
        wait_w(4);

        // ---- G7 byte account ----
        $display("  --- G7: byte account, offered == 4*words ---");
        gold_n = 0; offered = 0; gold_on = 1'b1;
        beat(64'h0102030405060708, 8'hFF, 1'b0);      // 8B => 1 word (2 logical)
        wait_w(10);
        beat(64'h1112131415161718, 8'hFF, 1'b0);      // 8B => +1 word
        wait_w(10);
        beat(64'h2122232425262728, 8'hFF, 1'b0);      // 8B => +1 word
        wait_w(10); wait_r(30);
        $display("  [INFO] G7 offered=%0d gold_n=%0d level=%0d drop=%0d", offered, gold_n, level, drop_bytes);
        chkc("G7a drop_bytes == 0", drop_bytes, 32'd0);
        chkc("G7b level == 6", level, 6);
        drain_all(wc);
        wait_r(10);
        chkc("G7c drained words == 6", wc, 6);
        chkc("G7d words*4 == offered", wc * 4, offered);
        chkc("G7e level == 0 after drain", level, 0);

        // =====================================================================
        // ---- G12 ⭐ 期 B / P8 阶段三: aux 口 = **2 字/拍** + 主机优先 + 混用停摆点 ----
        // =====================================================================
        $display("  --- G12: aux pop port (2 words/beat) + host-priority + stash stall ---");
        // (a) 空态: req 高也不弹
        dma_req = 1'b1;
        wait_r(10);
        chkc("G12a empty: dma_gnt == 0", dma_gnt, 0);
        dma_req = 1'b0;
        // (b) 一个字 (8B) ⇒ 1 次 gnt 弹 **2 个逻辑字**, 内容 = {word_b, word_a}
        beat(64'h8877665544332211, 8'hFF, 0);        // => 0xF0C3D22D / 0xB48796E1
        wait_w(20); wait_r(10);
        chkc("G12b level == 2 before aux", level, 2);
        begin : g12b
            integer g1; reg [63:0] d1;
            g1 = 0; d1 = 64'd0;
            @(negedge clk_r); dma_req <= 1'b1;
            for (tt = 0; tt < 200; tt = tt + 1) begin
                @(posedge clk_r);
                if (dma_gnt) begin g1 = g1 + 1; d1 = dma_data; end
                if (g1 == 1) tt = 4000;
            end
            @(negedge clk_r); dma_req <= 1'b0;
            chkc("G12c aux gnt count == 1", g1, 1);
            chk64("G12d aux data == {wb, wa}", d1, 64'hB48796E1F0C3D22D);
        end
        wait_r(10);
        chkc("G12e level == 0 after aux drain", level, 0);
        // (f) 主机优先: 两路同时请求 ⇒ dma_gnt 必须恒 0, 且不双弹
        beat(64'h8877665544332211, 8'hFF, 0);        // 2 逻辑字 (dma_req 仍 = 0)
        wait_w(20); wait_r(10);
        chkc("G12f level == 2 (req=0 holds)", level, 2);
        dma_req = 1'b1;
        @(negedge clk_r); rd_en_r <= 1'b1;
        dgt = 0;
        for (tt = 0; tt < 8; tt = tt + 1) begin
            @(posedge clk_r);
            if (dma_gnt) dgt = dgt + 1;
        end
        @(negedge clk_r); rd_en_r <= 1'b0;
        chkc("G12g host priority: dma_gnt == 0", dgt, 0);
        dma_req = 1'b0;
        wait_r(10);
        chkc("G12h exactly 2 words consumed", level, 0);
        // (i) ⭐ 混用停摆点: 主机弹 1 (低半) ⇒ 高半进 stash; aux 只能成对搬
        //     2 个字 ⇒ 搬走 {stash, 下一个字的低半} 并弹掉 FIFO 的字; 再剩 1 个高半
        //     留在 stash ⇒ aux **停摆** (不拆 stash 单走), 主机可读完 ⇒ 零丢字。
        beat(64'h0102030405060708, 8'hFF, 0);        // word0 = 0xA1A6A7A4, word1 = 0xADA2A3A0
        beat(64'h1112131415161718, 8'hFF, 0);        // word2 = 0xB1B6B7B4, word3 = 0xBDB2B3B0
        wait_w(20); wait_r(10);
        chkc("G12i level == 4 (16B = 4 words)", level, 4);
        pop1(wv, ok_n);                              // 主机吃第 0 个字
        chk ("G12j host pop0 == 0xA1A6A7A4", wv, 32'hA1A6A7A4);
        wait_r(6);
        chkc("G12k level == 3 (stash holds 1)", level, 3);
        begin : g12i
            integer g2; reg [63:0] d2;
            g2 = 0; d2 = 64'd0;
            @(negedge clk_r); dma_req <= 1'b1;
            for (tt = 0; tt < 60; tt = tt + 1) begin
                @(posedge clk_r);
                if (dma_gnt) begin g2 = g2 + 1; d2 = dma_data; end
            end
            @(negedge clk_r); dma_req <= 1'b0;
            chkc("G12l aux stalls: gnt count == 1", g2, 1);
            chk64("G12m aux pair == {word2, word1}", d2, 64'hB1B6B7B4ADA2A3A0);
        end
        wait_r(10);
        chkc("G12n level == 1 (stash, no loss)", level, 1);
        pop1(wv, ok_n);
        chk ("G12o stash drain == 0xBDB2B3B0", wv, 32'hBDB2B3B0);
        wait_r(10);
        chkc("G12p level == 0 (no loss)", level, 0);

        // =====================================================================
        // ---- G13 ⭐⭐ 主判据: 8 B/拍**持续源** + aux 排空 ⇒ drop_bytes == 0 ----
        // =====================================================================
        // 手算: N=600 拍 × 8B = 4800 B = 1200 个逻辑字; aux 2 字/拍 (= 2 GB/s @250MHz)
        //   > 源 1.25 GB/s ⇒ FIFO 结构上不会积压; 排空字数 == 2 × gnt == 1200;
        //   字节账 8N == 4 × 排空字数 (残余 0)。
        //   ⛔ **旧版 (4B/拍) 在这条构造下必丢一半** ⇒ 本判据 = "结构吞吐类丢字节不可达" 的直接牙。
        $display("  --- G13: sustained 8B/beat + aux drain => drop_bytes == 0 ---");
        dma_req = 1'b0;
        clr_pulse();                                  // 冲刷干净 + 清累加器/stash
        wait_r(40);
        gold_n = 0; offered = 0; gold_on = 1'b1;
        dgnt = 0; dword_mis = 0; dma_chk_on = 1'b1;
        dsave = drop_bytes;
        n_burst = 600;
        dma_req = 1'b1;                               // 排空器**先武装** (与产品路径一致)
        q = 0;
        bd = {(q[7:0]^8'h11), (q[7:0]^8'h22), (q[7:0]^8'h33), (q[7:0]^8'h44),
              (q[7:0]^8'h55), (q[7:0]^8'h66), (q[7:0]^8'h77), (q[7:0]^8'h88)};
        @(negedge clk_w); tv_keep <= 8'hFF; tv_last <= 1'b0; tv_data <= bd; tv_valid <= 1'b1;
        for (q = 1; q < n_burst; q = q + 1) begin     // 背靠背连续 600 拍 (真"持续 8B/拍")
            bd = {(q[7:0]^8'h11), (q[7:0]^8'h22), (q[7:0]^8'h33), (q[7:0]^8'h44),
                  (q[7:0]^8'h55), (q[7:0]^8'h66), (q[7:0]^8'h77), (q[7:0]^8'h88)};
            @(negedge clk_w); tv_data <= bd;
        end
        @(negedge clk_w); tv_valid <= 1'b0;
        // 等排空干净 (aux 持续在抽)
        for (tt = 0; tt < 6000; tt = tt + 1) begin
            @(posedge clk_r);
            if (level == 9'd0 && dgnt == n_burst) tt = 100000;
        end
        @(negedge clk_r); dma_req <= 1'b0;
        wait_r(20);
        dma_chk_on = 1'b0;
        $display("  [INFO] G13 offered=%0d gold_n=%0d gnt=%0d level=%0d d_drop=%0d dword_mis=%0d",
                 offered, gold_n, dgnt, level, drop_bytes - dsave, dword_mis);
        chkc("G13a offered == 4800 (600x8B)", offered, 4800);
        chkc("G13b gold_n == 4800", gold_n, 4800);
        chk ("G13c d_drop == 0 (struct gone)", drop_bytes, dsave);
        chkc("G13d aux gnt == 600", dgnt, 600);
        chkc("G13e drained == 1200 words", dgnt * 2, 1200);
        chkc("G13f pairs == golden stream", dword_mis, 0);
        chkc("G13g level == 0 after drain", level, 0);

        // =====================================================================
        // ---- G8 (重写): 丢字节计数的牙 —— 改为 **FIFO 满类** 构造 ----
        // =====================================================================
        // 旧构造 ("8B/拍超 4B/拍结构上限 ⇒ 必丢") 随修复**结构性不可达** ⇒ 换个能丢的构造:
        //   300 拍无排空 (300 字 = 2400 B > FIFO 256 字 = 2048 B) ⇒ 必满 ⇒ 丢字节 > 0。
        //   手算: 入 FIFO 256 字 (2048 B) + 残余 16 B (acc 8 + pend 8) ⇒ 丢 = 2400-2048-16 = 336 B;
        //   全排空后 = 258 字 = **516 逻辑字** ⇒ 恒等式 4*516 + 336 == 2400。
        //   顺带见证 **level 满量程 clamp**: occ=256 ⇒ 2*256 = 512 > 511 ⇒ 读 511。
        $display("  --- G8: FIFO-full drops have teeth (300-beat burst, no drain) ---");
        dma_req = 1'b0;
        clr_pulse();
        wait_r(40);
        gold_n = 0; offered = 0; gold_on = 1'b0;
        dsave = drop_bytes;
        q = 0;
        bd = 64'hB000000000000000 + q;
        @(negedge clk_w); tv_keep <= 8'hFF; tv_last <= 1'b0; tv_data <= bd; tv_valid <= 1'b1;
        for (q = 1; q < 300; q = q + 1) begin
            bd = 64'hB000000000000000 + q;
            @(negedge clk_w); tv_data <= bd;
        end
        @(negedge clk_w); tv_valid <= 1'b0;
        wait_w(10); wait_r(60);
        $display("  [INFO] G8 offered=%0d d_drop=%0d level=%0d", offered, drop_bytes - dsave, level);
        if ((drop_bytes - dsave) > 32'd0) $display("  [PASS] G8a drop_bytes > 0 (FIFO-full drops counted)");
        else begin $display("  [FAIL] G8a drop_bytes == 0 (full no-drop)"); fails = fails + 1; end
        chk1("G8b any_drop == 1", any_drop, 1'b1);
        chkc("G8c level == 511 (clamp witness)", level, 511);
        drain_all(wc);
        $display("  [INFO] G8 drained=%0d offered=%0d d_drop=%0d", wc, offered, drop_bytes - dsave);
        chkc("G8d byte identity holds", wc * 4 + (drop_bytes - dsave), offered);
        chkc("G8e drained == 516 words", wc, 516);
        chkc("G8f level == 0 after drain", level, 0);

        // =====================================================================
        // ---- G11 写门在**满**态: 字节账恒等式 (设计件 §V5-A-1 的第一号判据) ----
        // =====================================================================
        // 变异靶子 = mut_gate (`wr_en = have`, 丢掉 !full):
        //   FIFO 自身仍会拒写, 但**镜像把累加器清了**、而拒写只进 FIFO 的 ovf_cnt (本模块不接)
        //   ⇒ 那一字**静默消失**、drop_bytes 不动 ⇒ 只有这条"字节账恒等式"能抓它。
        // ⚠️ 必须确认真的压到 full (否则本相位是空判据 —— G11a 就是这个前置见证)。
        $display("  --- G11: write gate under full: byte identity holds (no silent loss) ---");
        clr_pulse();
        wait_r(40);
        gold_on = 1'b0; offered = 0; dsave = drop_bytes;
        begin : g11fill
            integer q2;
            for (q2 = 0; q2 < 600; q2 = q2 + 1) begin
                if (u_dut.fifo_full) q2 = 100000;
                else begin beat(64'hC000000000000000 + q2, 8'hFF, 1'b0); wait_w(1); end
            end
        end
        wait_w(6);
        chk1("G11a FIFO reached full", u_dut.fifo_full, 1'b1);
        chk ("G11b paced fill added no drops", drop_bytes, dsave);
        dsave = drop_bytes;
        beat(64'hD000000000000000, 8'hFF, 1'b0);       // 满态再注 1 拍 = 1 字 (8B)
        wait_w(10); wait_r(20);
        drain_all(wc);
        $display("  [INFO] G11 offered=%0d drained_words=%0d d_drop=%0d level=%0d",
                 offered, wc, drop_bytes - dsave, level);
        // 字节账恒等式: 每个被接受的字节要么进了 FIFO (4*逻辑字数), 要么被计进 drop_bytes
        //   —— **没有第三种去处**。mut_gate (`wr_en=have`) 在这里差 8B。
        chkc("G11c byte identity holds", wc * 4 + (drop_bytes - dsave), offered);
        chkc("G11d level == 0 after drain", level, 0);

        // =====================================================================
        // ---- G14 (新): cap_en=0 冻结**不复制**被握住的字 ----
        // =====================================================================
        // 旧版缺陷 (读码定案, 本轮修): 写门 = `have && !full` **不含 cap_on** ⇒ 若冻结时
        //   累加器正握着 1 个字 (FIFO 满), 冻结后一有空位 wr_en 就再拉高, 而 `acc_cnt_r`
        //   被 cap_on 冻住不回零 ⇒ **同一个字被反复写进 FIFO** (最多 DEPTH 份, 静默)。
        // 构造: 填满 ⇒ 冻结 (cap_en=0, 不 clr) ⇒ 全程排空 ⇒ 排空字数必须**恰好** = 256 字 = 512 逻辑字。
        $display("  --- G14: cap_en=0 freeze must not duplicate the held word ---");
        clr_pulse();
        wait_r(40);
        @(negedge clk_w); cap_en <= 1'b1;
        wait_w(6);
        gold_on = 1'b0; offered = 0;
        begin : g14fill
            integer q3;
            for (q3 = 0; q3 < 900; q3 = q3 + 1) begin
                if (u_dut.fifo_full) q3 = 100000;
                else begin beat(64'hE000000000000000 + q3, 8'hFF, 1'b0); wait_w(1); end
            end
        end
        wait_w(10); wait_r(30);
        chk1("G14a FIFO full", u_dut.fifo_full, 1'b1);
        chkc("G14b acc holds a whole word", u_dut.acc_cnt_r, 8);
        // 冻结: 只关 cap_en (协议上"不写"), **不 clr** (clr 会清掉累加器, 那就不测了)
        @(negedge clk_w); cap_en <= 1'b0;
        wait_w(6); wait_r(20);
        drain_all(wc);
        $display("  [INFO] G14 drained_words=%0d (expect 512 logical = 256 words)", wc);
        chkc("G14c drained == 512 (no dup)", wc, 512);
        @(negedge clk_w); cap_en <= 1'b1;             // 解冻 (后面的相位还要用)
        wait_w(6);
        clr_pulse();
        wait_r(40);
        drain_all(wc);

        // ---- G9 clr ----
        $display("  --- G9: clr (toggle) ---");
        gold_on = 1'b0; offered = 0;
        beat(64'h9988776655443322, 8'hFF, 1'b0);       // 8B => 1 word (2 logical)
        wait_w(8);
        beat(64'h000000000000ABCD, 8'hC0, 1'b0);       // 2B => accumulator only
        wait_w(8); wait_r(30);
        chkc("G9a pre: level == 2 (+2B resid)", level, 2);
        dsave = drop_bytes;
        clr_pulse();
        wait_r(60);
        chkc("G9b after clr: level == 0", level, 0);
        chk1("G9c after clr: any_drop == 0", any_drop, 1'b0);
        wait_r(10);
        chk1("G9d any_drop_rd == 0 (CDC clear)", any_drop_rd, 1'b0);
        chk ("G9e clr keeps drop_bytes", drop_bytes, dsave);
        // 累加器 (含 clr 前的 2B 残余) 真被清了: 只喂 8 个新鲜字节 ⇒ 两个字必须是它们
        gold_n = 0; offered = 0; gold_on = 1'b1;
        beat(64'h0102030405060708, 8'hFF, 1'b0);       // 8 bytes: 01..08
        wait_w(8); wait_r(30);
        chkc("G9f post-clr: level == 2", level, 2);
        pop1(wv, ok_n);
        // word = {04',03',02',01'} = {A1,A6,A7,A4} = 0xA1A6A7A4
        chk ("G9g post-clr word0 == 0xA1A6A7A4", wv, 32'hA1A6A7A4);
        wait_r(6);
        pop1(wv, ok_n);
        chk ("G9h post-clr word1 == 0xADA2A3A0", wv, 32'hADA2A3A0);

        // ---- G10 final state ----
        $display("  --- G10: final state ---");
        wait_r(40);
        chkc("G10a level == 0", level, 0);
        chk1("G10b empty == 1", empty, 1'b1);

        $display("");
        if (fails == 0) $display("APP_RX_MIRROR_GATE: PASS_ALL");
        else            $display("APP_RX_MIRROR_GATE: FAIL (%0d checks failed)", fails);
        $finish;
    end

    initial begin #8000000; $display("APP_RX_MIRROR_GATE: TIMEOUT"); $finish; end

endmodule
