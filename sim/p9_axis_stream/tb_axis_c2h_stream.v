`timescale 1ns/1ps
//=============================================================================
// tb_axis_c2h_stream.v — P9「C2H AXIS 成形器」的**单元门** (自检式, 无 Python)
//=============================================================================
// 被测 = rtl/axis_c2h_stream.v (aux 2 字/拍 → 128 位 AXIS 拍 + tkeep/tlast 合同 + 取走计数)
// ⚠️ 判据名一律**纯 ASCII** (xsim 会把经 [255:0] 端口传的非 ASCII 逐字节损坏)。
//
// ⭐ 口径 (TL 2026-10-11 裁定 + **D4 修正轮**; 本门按它们钉):
//   · `dma_words`/`MIR_DMA_CNT` = **从 aux 口取走 (`dma_gnt`) 的 32 位字数** (每 grant +2),
//     **不是** tvalid&&tready 的下游字数; `clr` ⇒ 归零。
//   · 停流触发式 `stop = (!cap_en) || (!en)` —— 它是**允许收尾**, **不是立即收尾**
//     (D4 修正轮): 非 clr 停流期**继续按满 16 B 打包**把镜像 FIFO 排空, 只有当
//     "静置 N 拍 (`QUIET_N = 32`) 零成交 + 打包器里留着半拍"才把它作**唯一一拍短拍**
//     (keep=00FF / last=1) 送出; **其余一律 tlast=0** (含停流排空期成形的整拍)。
//   · ⭐ `clr` = **窗口边界 ⇒ 丢弃**打包器残留 (b + 两槽; **不发任何拍**) + 计数归零 +
//     clr 拍**不拉 `dma_req`** (⭐ **D4 板级修正轮**: 板级 0x22 抓到的形态 = clr→cap_en=1
//     起测瞬间残拍以短拍冒出 ⇒ **EOP 早关描述符 ⇒ 宿主首块出现洞/零填充/超时**;
//     件名 `p9_board_0x22_20261011/runs/D4_BOUNDARY.txt`)。旧口径"clr 立即送残拍"已废。
//   · nested/重复 stop 不重复发 (收尾拍成形即清两槽; 新残留必须先有新 grant)。
//
// 判据分组 (每条都对着一个具体失效模式):
//   G0  reset: tvalid=0 / dma_words=0
//   G1  正常打包: 2 次 grant (16 B) ⇒ **1 拍**; 内容锚 = {g2,g1} (低字在前); keep=FFFF; last=0
//   G2  半个拍**不成形** (en=1 & cap_en=1 ⇒ stop=0; 1 次 grant ⇒ tvalid=0)
//   G3 ⭐ 背压: tready=0 ⇒ ① 载荷稳定; ② 暂存满后**不拉 dma_req** (无空间不请求);
//       ③ 恢复 ⇒ 已持有的拍按序流出, 一拍不丢不错序
//   G4  `en` 1→0 停流 ⇒ **静置排空**后短末拍 (keep=00FF / last=1); 停流 12 拍内**不许**成形
//   G4c ⭐ `cap_en` 1→0 停流 (TL 点名的"采集被关") ⇒ 同样的静置排空 + 短末拍
//   G5  `en`=0 + 停流期成形的**整拍** ⇒ keep=FFFF + **last=0** (正常拍, 数据不丢;
//       收尾只由残拍短拍承担 —— D4 修正轮裁定 ③ 改变了旧版"停流期整拍打 last"的行为)
//   G6  `en`=0 ⇒ **dma_req 恒 0**
//   G7  ⭐ `clr` = 窗口边界 ⇒ **丢弃**残拍 (**0 拍**) + `dma_words` 归零 + 新窗口头部
//       **无 pre-clr 字节**; G7x = clr 连**已成形未交付**的拍也丢弃 (软复位式边界)
//   G8  吞吐: 无限 grant + tready=1 ⇒ rx_n >= 140 / 300 拍 (理论上限 150 / 实测 149;
//       ⭐ D7: 旧门"标签写 1/2 拍钟、断言却只 96" ⇒ 界收窄到与标签一致)
//   G9  `dma_words` 口径: 每 grant +2 (= 整拍 +4) / clr 归零
//   G10 末拍稳定性: 已成形的末拍在握手前**逐拍恒定** (跨 cap_en/en 撤销也不变)
//   G11 ⭐ 停流 + 多 grant 排空 ⇒ 满 16 B 打包 (整拍 last=0) + **只出一拍短拍** (tlast 总数 == 1)
//   G11b ⭐ 长排空 (41 grant): 排空期**零** tlast + 收尾恰一拍 (静置检测的牙)
//   G12 ⭐ 重复/nested stop ⇒ **不重复发** (rx_n / tlast 总数不变)
//
// run: sim/p9_axis_stream/run_tb_axis_c2h_stream.bat [real|mut_*]
//=============================================================================
module tb_axis_c2h_stream;

    // ---- 时钟: pcie_axi_aclk 250MHz (4ns; 与板上同) ----
    reg clk = 1'b0;
    always #2.0 clk = ~clk;

    integer fails = 0;
    task chk(input [255:0] name, input [31:0] got, input [31:0] exp);
        begin
            if (got === exp) $display("  [PASS] %0s = %08x", name, got);
            else begin $display("  [FAIL] %0s = %08x (期望 %08x)", name, got, exp); fails = fails + 1; end
        end
    endtask
    task chk128(input [255:0] name, input [127:0] got, input [127:0] exp);
        begin
            if (got === exp) $display("  [PASS] %0s = %032x", name, got);
            else begin $display("  [FAIL] %0s = %032x (期望 %032x)", name, got, exp); fails = fails + 1; end
        end
    endtask
    task chk1(input [255:0] name, input got, input exp);
        begin
            if (got === exp) $display("  [PASS] %0s = %b", name, got);
            else begin $display("  [FAIL] %0s = %b (期望 %b)", name, got, exp); fails = fails + 1; end
        end
    endtask

    // ---------------- DUT 端口 ----------------
    reg         rst_n   = 1'b0;
    reg         en      = 1'b0;
    reg         cap_en  = 1'b0;
    reg         clr     = 1'b0;
    reg         tready  = 1'b1;
    wire        dma_req;
    wire        dma_gnt;
    wire [63:0] dma_data;
    wire [127:0] t_data;
    wire [15:0]  t_keep;
    wire         t_last, t_valid;
    wire [31:0]  dma_words;

    axis_c2h_stream u_dut (
        .clk (clk), .rst_n (rst_n), .en (en), .cap_en (cap_en), .clr (clr),
        .dma_req (dma_req), .dma_gnt (dma_gnt), .dma_data (dma_data),
        .s_axis_c2h_tdata (t_data), .s_axis_c2h_tkeep (t_keep),
        .s_axis_c2h_tlast (t_last), .s_axis_c2h_tvalid (t_valid),
        .s_axis_c2h_tready (tready),
        .dma_words (dma_words)
    );

    // ---------------- TB 侧"镜像模型": grant 队列 + 组合成交 (与 aux 口合同同款) ----------------
    //   合同: `dma_req=1 && 队列非空` ⇒ 同拍 `dma_gnt=1` 且 `dma_data` = 队头。
    //   队列单元 = 64 位 = **一次 grant 的 8 B** (`[31:0]` = 先出的逻辑字)。
    //   ⚠️⚠️ 记账分权 (本门前两版都在这里翻过车: blocking 写 与 NBA 写同一变量 ⇒ 同一时步
    //      里 NBA 覆盖 blocking ⇒ "清不掉队列" / "入队丢失"):
    //        · `q_push_cnt` (累计入队数): **只由 task 用 blocking 写**, always 块只读;
    //        · `q_rd_abs` (读指针, 绝对坐标) / `gnt_seen`: **只由 always 块用 NBA 写**;
    //        · 空判据 = `q_push_cnt <= q_rd_abs` (两个 writer 不同 ⇒ 无竞争);
    //        · `q_clr` = 让 `q_rd_abs` 跳到当前 `q_push_cnt` (⇒ 丢弃已入队的全部),
    //          且在**下一拍**才做 (task 等一个 posedge, 避免与当拍成交的 NBA 撞车)。
    //   坐标: 所有索引都用"累计入队数"作绝对地址 (`& 4095` 取模) —— 清队列不搬数据。
    reg [63:0] q_mem [0:4095];
    integer    q_push_cnt = 0;        // task-only (blocking)
    integer    q_rd_abs   = 0;        // always-only (NBA)
    reg        q_clr_req  = 1'b0;
    reg        gr_hold    = 1'b0;     // 1 = 上游暂时无数据 (不成交; task-only)
    wire       q_empty = (gr_hold) || (q_push_cnt <= q_rd_abs);
    wire [63:0] q_head = q_mem[q_rd_abs & 4095];
    assign dma_gnt  = dma_req && !q_empty;
    assign dma_data = q_head;
    integer    gnt_seen = 0;          // always-only (NBA)
    always @(posedge clk) begin
        if (q_clr_req) begin
            q_rd_abs   <= q_push_cnt;   // 跳到队尾 = 清空 (同拍新 push 仍算新数据)
            gnt_seen   <= 0;
            q_clr_req  <= 1'b0;
        end else begin
            q_rd_abs   <= q_rd_abs + ((dma_gnt) ? 1 : 0);
            gnt_seen   <= gnt_seen + ((dma_gnt) ? 1 : 0);
        end
    end

    task q_push(input [63:0] d);
        begin
            q_mem[q_push_cnt & 4095] = d;   // 立即写入 (可见性由 q_push_cnt 决定)
            q_push_cnt = q_push_cnt + 1;
        end
    endtask
    task q_clr;                            // 下一拍生效 (与当拍成交的 NBA 不撞车)
        //   ⚠️ 必须**等到那个 posedge 之后的 negedge** 才返回: 否则紧随其后的 q_push 与
        //      清那一拍落在**同一时步** ⇒ 清分支读到的 q_push_cnt 已含新 push ⇒ 新数据被
        //      "清"掉 (实测: G1 的 2 个 push 被吸收 ⇒ rd_abs==push_cnt ⇒ 全程 0 次成交)。
        begin q_clr_req = 1'b1; @(posedge clk); @(negedge clk); end
    endtask

    // ---------------- TB 侧 beat 采集器 (独立于 DUT 计数) ----------------
    reg [127:0] rx_data [0:255];
    reg [15:0]  rx_keep [0:255];
    reg         rx_last [0:255];
    integer     rx_n = 0;
    integer     tlast_n = 0;              // ⭐ 带 tlast 的拍数 (D4 修正轮的"一事件一包尾"判据)
    always @(posedge clk) begin
        if (t_valid && tready) begin
            if (rx_n < 256) begin
                rx_data[rx_n] <= t_data; rx_keep[rx_n] <= t_keep; rx_last[rx_n] <= t_last;
            end
            rx_n = rx_n + 1;
            if (t_last) tlast_n = tlast_n + 1;
        end
    end
    task rx_clr; begin rx_n = 0; tlast_n = 0; end endtask

    // ⭐ clr 脉冲生成器: **在 negedge 驱动**(非阻塞) —— 工程坑 3/17 的同族:
    //   若写成 `clr = 1; @(posedge clk); clr = 0;`, 那个 `clr = 0` 与 **当拍 posedge**
    //   落在同一时步 ⇒ 与本 DUT 的 always 竞争 (实测: G9 的 clr 被吞, 计数不清零)。
    task do_clr;
        begin
            @(negedge clk); clr <= 1'b1;
            @(negedge clk); clr <= 1'b0;
        end
    endtask

    integer i, j;
    reg [127:0] stab_d; reg [15:0] stab_k; reg stab_l; reg stab_v;
    reg [31:0] w0;
    integer    gnt0;

    initial begin
        $display("=== tb_axis_c2h_stream: P9 C2H AXIS shaper unit gate ===");
        rst_n = 0; en = 0; cap_en = 0; clr = 0; tready = 1; q_clr;
        repeat (8) @(posedge clk);
        rst_n = 1;
        cap_en = 1;                       // 起测协议 = cap_en 先开 (采集使能)
        repeat (4) @(posedge clk);

        // ---------------- G0 reset ----------------
        $display("  --- G0: reset state ---");
        chk1("G0a tvalid == 0",  t_valid, 1'b0);
        chk ("G0b dma_words == 0", dma_words, 32'd0);

        // ---------------- G1: 正常打包 (2 grant = 1 拍) ----------------
        //   手算锚: grant1 = {0x22222222,0x11111111}; grant2 = {0x44444444,0x33333333}
        //   ⇒ 拍 = {grant2, grant1} = {0x44444444,0x33333333,0x22222222,0x11111111} (低字在前)
        $display("  --- G1: pack 2 grants into one 128-bit beat ---");
        rx_clr; q_clr;
        q_push({32'h22222222, 32'h11111111});
        q_push({32'h44444444, 32'h33333333});
        en = 1;
        repeat (12) @(posedge clk);
        $display("  [DBG] G1: push=%0d rd_abs=%0d q_empty=%b dma_req=%b dma_gnt=%b gnt_seen=%0d rx_n=%0d s0v=%b bv=%b",
                 q_push_cnt, q_rd_abs, q_empty, dma_req, dma_gnt, gnt_seen, rx_n, u_dut.s0_v, u_dut.b_v);
        chk ("G1a beats == 1", rx_n, 1);
        chk128("G1b beat == {g2,g1} (低字在前)", rx_data[0],
               {32'h44444444, 32'h33333333, 32'h22222222, 32'h11111111});
        chk ("G1c tkeep == FFFF (非末拍)", {16'd0, rx_keep[0]}, 32'hFFFF);
        chk1("G1d tlast == 0 (方案 A: 恒 0)", rx_last[0], 1'b0);
        chk ("G1e dma_words == 4 (2 grant x 2 字)", dma_words, 32'd4);
        chk ("G1f TB 侧 grant 数 == 2", gnt_seen, 2);

        // ---------------- G2: 半个拍不成形 (en=1 & cap_en=1) ----------------
        $display("  --- G2: a lone grant does NOT form a beat (stop=0) ---");
        rx_clr; q_clr; gnt0 = gnt_seen;
        q_push({32'h66666666, 32'h55555555});
        repeat (12) @(posedge clk);
        chk1("G2a tvalid == 0 (半个不吐)", t_valid, 1'b0);
        chk ("G2b beats == 0", rx_n, 0);
        chk ("G2c grant 被弹出 1 次 (暂存里)", gnt_seen - gnt0, 1);
        chk ("G2d dma_words 计到取走 (+2)", dma_words - 32'd4, 32'd2);

        // ---------------- G3: 背压 (tready=0) ----------------
        //   起始态: G2 留下的半个拍在槽 0 (grant 已在 G2 计入)。
        //   手算 (逐拍模型): P1 补齐成拍 → 进 B; P2/P3 进两槽; 此后 B 被 tready 顶住 ⇒
        //   **不再取** P4/P5 ⇒ 停收期 TB 只见 **3 次 grant**、**0 拍被收**。
        $display("  --- G3: backpressure -> no req when full -> resume in order ---");
        rx_clr; q_clr; gnt0 = gnt_seen;
        q_push({32'hB2B2B2B2, 32'hA1A1A1A1});   // P1: 补齐 G2 的半个 ⇒ 拍 A
        q_push({32'hB4B4B4B4, 32'hA3A3A3A3});   // P2
        q_push({32'hD2D2D2D2, 32'hC1C1C1C1});   // P3
        q_push({32'hD4D4D4D4, 32'hC3C3C3C3});   // P4 (越量: 必须**不被弹出**)
        q_push({32'hF2F2F2F2, 32'hE1E1E1E1});   // P5 (越量)
        tready = 0;                             // 下游停收
        repeat (40) @(posedge clk);
        chk ("G3a tvalid == 1 (有拍在等)", t_valid, 1'b1);
        chk ("G3b TB 侧 grant 数 == 3 (2 槽 + 1 已进 B = 32 B)", gnt_seen - gnt0, 3);
        chk1("G3c ⭐ 暂存满 ⇒ dma_req == 0 (无空间不请求)", dma_req, 1'b0);
        chk ("G3d beats == 0 (下游没接)", rx_n, 0);
        stab_d = t_data; stab_k = t_keep; stab_l = t_last; stab_v = t_valid;
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk);
            if ((t_data !== stab_d) || (t_keep !== stab_k) || (t_last !== stab_l) || (t_valid !== stab_v)) begin
                $display("  [FAIL] G3e 负载在 tready=0 期间发生变化 (AXIS 保持合同)"); fails = fails + 1; i = 100;
            end
        end
        if (i != 100) $display("  [PASS] G3e 载荷/valid 在停收期恒定 (AXIS 保持合同)");
        tready = 1; repeat (60) @(posedge clk);
        chk ("G3f 恢复: 三个半拍出成 3 拍", rx_n, 3);
        chk128("G3g 拍 1 == {P1, P0} (G2 的半个 + P1)", rx_data[0],
               {32'hB2B2B2B2, 32'hA1A1A1A1, 32'h66666666, 32'h55555555});
        chk128("G3h 拍 2 == {P3, P2}", rx_data[1],
               {32'hD2D2D2D2, 32'hC1C1C1C1, 32'hB4B4B4B4, 32'hA3A3A3A3});
        chk128("G3h2 拍 3 == {P5, P4} (停收期没丢, 恢复后按序补上)", rx_data[2],
               {32'hF2F2F2F2, 32'hE1E1E1E1, 32'hD4D4D4D4, 32'hC3C3C3C3});
        repeat (20) @(posedge clk);
        chk ("G3i 恢复后 dma_req 再拉 (还能请求)", {31'd0, dma_req}, 32'd1);

        // ---------------- G4: 停流收尾 (en 1→0; 半个拍) —— 静置排空后**一拍**短末拍 ----------------
        $display("  --- G4: stop-flow (en=0): quiet-drain then flush of a half beat ---");
        rx_clr; q_clr; gnt0 = gnt_seen; w0 = dma_words;
        q_push({32'h88888888, 32'h77777777});   // 一个 grant = 半个拍
        en = 1; repeat (12) @(posedge clk);
        chk ("G4a 半个仍不成形 (en=1/cap_en=1)", rx_n, 0);
        chk ("G4a2 取走计数已 +2 (口径 = aux 口)", dma_words - w0, 32'd2);
        en = 0; repeat (12) @(posedge clk);
        chk ("G4a3 stop 12cyc: no beat yet", rx_n, 0);
        repeat (36) @(posedge clk);
        chk ("G4b flush beat after quiet", rx_n, 1);
        chk128("G4c flush 拍 = {64'd0, 半拍}", rx_data[0], {64'd0, 32'h88888888, 32'h77777777});
        chk ("G4d flush 拍 keep == 00FF (挤 LSB 且非全 0)", {16'd0, rx_keep[0]}, 32'h00FF);
        chk1("G4e flush 拍 tlast == 1", rx_last[0], 1'b1);
        chk ("G4f 计数**不再**因 flush 变 (取走时已计)", dma_words, w0 + 32'd2);

        // ---------------- G4c: 停流收尾 (cap_en 1→0; TL 点名的"采集被关") —— 同样静置排空 ----------------
        $display("  --- G4c: stop-flow (cap_en=0): quiet-drain then flush of a half beat ---");
        rx_clr; q_clr; gnt0 = gnt_seen;
        en = 1; cap_en = 1; repeat (8) @(posedge clk);
        q_push({32'hAA55AA55, 32'h55AA55AA});   // 半个拍
        repeat (12) @(posedge clk);
        chk ("G4c-a 半个不成形 (cap_en=1)", rx_n, 0);
        cap_en = 0; repeat (12) @(posedge clk);
        chk ("G4c-b cap_en=0 12cyc: no beat", rx_n, 0);
        repeat (36) @(posedge clk);
        chk ("G4c-b2 short beat after quiet", rx_n, 1);
        chk128("G4c-c 短末拍 = {64'd0, 半拍}", rx_data[0], {64'd0, 32'hAA55AA55, 32'h55AA55AA});
        chk ("G4c-d 短末拍 keep == 00FF", {16'd0, rx_keep[0]}, 32'h00FF);
        chk1("G4c-e 短末拍 tlast == 1", rx_last[0], 1'b1);
        cap_en = 1;

        // ---------------- G5: 停流期整拍 ⇒ **正常拍** (D4 修正轮裁定 ③ 改口径) ----------------
        //   构造: tready=0 ⇒ 拍 A 进 B 被顶住; P3/P4 留在**两槽**; 此时 en=0 (停流) ⇒
        //   恢复后 A 先出 (停流**之前**成形的 ⇒ last=0), 槽里的 {P4,P3} 在停流期成形
        //   ⇒ **last=0** 且 keep=FFFF (整拍 = 正常拍, 数据一个不少) —— 收尾只由**残拍短拍**
        //   承担; 本例残留恰是整拍 ⇒ 本段**没有**收尾拍 (已登记边界: 该描述符等驱动超时)。
        $display("  --- G5: stop-flow: full beat formed during stop is a NORMAL beat (last=0) ---");
        rx_clr; q_clr; w0 = dma_words;
        en = 1; cap_en = 1; tready = 0; repeat (8) @(posedge clk);
        q_push({32'h22222222, 32'h11111111});   // P1
        q_push({32'h44444444, 32'h33333333});   // P2
        q_push({32'h66666666, 32'h55555555});   // P3
        q_push({32'h88888888, 32'h77777777});   // P4
        repeat (30) @(posedge clk);
        chk ("G5a 停收期 0 拍被收", rx_n, 0);
        en = 0; repeat (8) @(posedge clk);       // 停流 (此时槽里是 P3/P4 整拍)
        tready = 1; repeat (30) @(posedge clk);
        chk ("G5b 停流后收下 2 拍", rx_n, 2);
        chk128("G5c 拍 1 == {P2,P1} (停流前成形 ⇒ 非末拍)", rx_data[0],
               {32'h44444444, 32'h33333333, 32'h22222222, 32'h11111111});
        chk ("G5d 拍 1 keep == FFFF", {16'd0, rx_keep[0]}, 32'hFFFF);
        chk1("G5e 拍 1 last == 0", rx_last[0], 1'b0);
        chk128("G5f 拍 2 == {P4,P3} (停流期成形)", rx_data[1],
               {32'h88888888, 32'h77777777, 32'h66666666, 32'h55555555});
        chk ("G5g 拍 2 keep == FFFF (整拍不缩短)", {16'd0, rx_keep[1]}, 32'hFFFF);
        chk1("G5h full beat last == 0", rx_last[1], 1'b0);
        chk ("G5h2 tlast total == 0", tlast_n, 32'd0);
        chk ("G5i 取走计数 += 8 (4 grant x2)", dma_words - w0, 32'd8);

        // ---------------- G6: en=0 ⇒ 不拉 dma_req ----------------
        $display("  --- G6: en=0 -> dma_req stays 0 ---");
        en = 0; q_clr; repeat (4) @(posedge clk);
        q_push({32'hAAAA5555, 32'h5555AAAA});
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk);
            if (dma_req !== 1'b0) begin
                $display("  [FAIL] G6a en=0 时 dma_req 被拉起 (拍 %0d)", i); fails = fails + 1; i = 100;
            end
        end
        if (i != 100) $display("  [PASS] G6a en=0 期间 dma_req 恒 0 (20 拍)");
        repeat (4) @(posedge clk);
        chk ("G6b en=0 期间 grant 未被消费", q_push_cnt - q_rd_abs, 1);

        // ---------------- G7: clr = 窗口边界 ⇒ **丢弃**残拍 (不发短拍) + 计数归零 ----------------
        //   ⭐ D4 板级修正轮 (板级 0x22 实测: clr→cap_en=1 起测瞬间残拍以短拍冒出 ⇒ **EOP 早关
        //   描述符 ⇒ 宿主首块出现洞/零填充/超时**): clr 丢弃打包器残留 (b + 两槽), clr 拍不拉
        //   `dma_req` ⇒ **新窗口头部 = 0 B pre-clr 字节**。旧口径"clr 把残拍作短末拍送出"已废。
        $display("  --- G7: clr = window boundary -> DISCARD residue (no short beat) ---");
        rx_clr; q_clr; w0 = dma_words;
        en = 1; cap_en = 1; repeat (8) @(posedge clk);
        q_push({32'h12345678, 32'h9ABCDEF0});   // 半个拍在暂存里
        repeat (12) @(posedge clk);
        chk ("G7a half kept in slot (no beat)", rx_n, 0);
        chk ("G7b dma_words == w0+2 (taken)", dma_words - w0, 32'd2);
        do_clr;
        repeat (2) @(posedge clk);
        chk ("G7c0 clr: NO beat (<=2cyc)", rx_n, 0);
        repeat (40) @(posedge clk);
        chk ("G7c clr -> dma_words == 0", dma_words, 32'd0);
        chk ("G7d clr DISCARDS residue (0 beats)", rx_n, 0);
        chk ("G7e tlast total == 0", tlast_n, 32'd0);
        // 新窗口: 推入新数据 ⇒ 正常打包 (整拍 last=0; 头部无 pre-clr 字节)
        q_push({32'hBBBBBBBB, 32'hAAAAAAAA});
        q_push({32'hDDDDDDDD, 32'hCCCCCCCC});
        repeat (12) @(posedge clk);
        chk ("G7f new window: 1 full beat", rx_n, 1);
        chk128("G7g new head NO stale prefix", rx_data[0],
               {32'hDDDDDDDD, 32'hCCCCCCCC, 32'hBBBBBBBB, 32'hAAAAAAAA});
        chk ("G7h new beat keep == FFFF", {16'd0, rx_keep[0]}, 32'hFFFF);
        chk1("G7i new beat last == 0", rx_last[0], 1'b0);
        chk ("G7j dma_words == 4 (post-clr)", dma_words, 32'd4);

        // ---------------- G7x: clr 也丢弃**已成形未交付**的拍 (b; 窗口边界 = 软复位式) ----------------
        $display("  --- G7x: clr discards a FORMED-but-unhandshaken beat ---");
        rx_clr; q_clr; en = 1; cap_en = 1; tready = 0;
        q_push({32'h22222222, 32'h11111111});
        q_push({32'h44444444, 32'h33333333});
        repeat (8) @(posedge clk);
        chk1("G7x-a beat formed and held", t_valid, 1'b1);
        chk ("G7x-b 0 beats accepted (tready=0)", rx_n, 0);
        do_clr;
        repeat (4) @(posedge clk);
        chk1("G7x-c clr -> tvalid == 0 (discarded)", t_valid, 1'b0);
        tready = 1; repeat (8) @(posedge clk);
        chk ("G7x-d 0 beats after clr (no old tail)", rx_n, 0);
        q_push({32'h66666666, 32'h55555555});
        q_push({32'h88888888, 32'h77777777});
        repeat (12) @(posedge clk);
        chk ("G7x-e new window packs normally", rx_n, 1);
        chk128("G7x-f new content, no old tail", rx_data[0],
               {32'h88888888, 32'h77777777, 32'h66666666, 32'h55555555});

        // ---------------- G8: 吞吐 (无限 grant + tready=1) ----------------
        $display("  --- G8: sustained throughput (>=1 beat / 2 clocks) ---");
        rx_clr; q_clr; en = 1; cap_en = 1; tready = 1;
        for (i = 0; i < 512; i = i + 1) q_push({32'h1000_0000 + i, 32'h2000_0000 + i});
        repeat (300) @(posedge clk);
        $display("  [INFO] G8 beats=%0d grants=%0d (300 clk)", rx_n, gnt_seen);
        $display("  [DBG] G8-end queue push=%0d rd_abs=%0d used=%0d", q_push_cnt, q_rd_abs, q_push_cnt - q_rd_abs);
        // ⭐ D7: 旧版标签写 ">= 1 拍 / 2 拍钟" (=150) 而断言只有 96 (带太宽: 一个把吞吐砍到
        //   2/3 的缺陷仍会绿) ⇒ 界收到 140 (理论 150 / 实测 149; 余量 ~6%, 仍抓 2/3 级回归)。
        if (rx_n >= 140) $display("  [PASS] G8a 持续率 >= 140 拍 / 300 拍钟 (理论上限 150, 实测 149)");
        else begin $display("  [FAIL] G8a 持续率不足: %0d 拍 / 300 clk (界 = 140)", rx_n); fails = fails + 1; end
        for (j = 0; j < 4; j = j + 1) begin
            chk128("G8b 抽检拍 (顺序)", rx_data[j],
                   {32'h1000_0000 + 2*j+1, 32'h2000_0000 + 2*j+1,
                    32'h1000_0000 + 2*j,   32'h2000_0000 + 2*j});
        end

        // ---------------- G9: dma_words 口径 (取走计数 / clr 归零) ----------------
        $display("  --- G9: dma_words accounting (counted at the aux port) ---");
        // ⚠️ 先停一手 (`en`=0) 让下游流水归位; 再 clr (⭐ 新口径: clr **丢弃**残留, 不发拍)
        //    ⇒ 基线干净。(旧口径下"已取走未交付的尾巴会在 clr 之后才交出来 ⇒ 拍数多 1-2";
        //    该不确定性已被 D4 板级修正轮结构性消除。)
        en = 0; repeat (20) @(posedge clk);
        do_clr;
        repeat (4) @(posedge clk);
        rx_clr; q_clr; en = 1; cap_en = 1; tready = 1;
        for (i = 0; i < 8; i = i + 1) q_push({32'h30 + i, 32'h20 + i});
        repeat (60) @(posedge clk);
        chk ("G9a 4 拍 = 8 grant = 16 字", dma_words, 32'd16);
        chk ("G9b TB 侧拍数 == 4", rx_n, 4);
        chk ("G9c TB grant 数 == 8", gnt_seen, 8);

        // ---------------- G10: 末拍稳定性 (cap_en 中途撤销, 载荷不变) ----------------
        $display("  --- G10: pending flush beat stays stable across cap_en changes ---");
        rx_clr; q_clr; en = 1; cap_en = 1; tready = 0;
        q_push({32'hDEADBEEF, 32'hCAFEBABE});   // 半个拍
        repeat (8) @(posedge clk);
        cap_en = 0;                              // 停流 ⇒ 静置排空后它变成末拍 (下游没接)
        repeat (40) @(posedge clk);              // >= QUIET_N(32) ⇒ 收尾拍已成形
        chk1("G10a0 tail beat formed (tvalid)", t_valid, 1'b1);
        stab_d = t_data; stab_k = t_keep; stab_l = t_last; stab_v = t_valid;
        cap_en = 1;                              // cap_en 拉回: 已呈现的末拍**不许变**
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk);
            if ((t_data !== stab_d) || (t_keep !== stab_k) || (t_last !== stab_l) || (t_valid !== stab_v)) begin
                $display("  [FAIL] G10a cap_en 拉回后挂着的末拍发生变化 (AXIS 保持合同)"); fails = fails + 1; i = 100;
            end
        end
        if (i != 100) begin
            $display("  [PASS] G10a cap_en 拉回期间末拍保持 (last=1 / keep=00FF / data 不变)");
            chk ("G10b 保持的末拍 keep == 00FF", {16'd0, t_keep}, 32'h00FF);
            chk1("G10c 保持的末拍 last == 1",   t_last, 1'b1);
        end
        tready = 1; repeat (8) @(posedge clk);
        chk ("G10d 收下后拍数 == 1", rx_n, 1);
        chk128("G10e 内容 == 半个拍 (未损)", rx_data[0], {64'd0, 32'hDEADBEEF, 32'hCAFEBABE});

        // ---------------- G11: ⭐ 停流 + 多 grant 排空 ⇒ 满 16 B 打包 + 只出一拍短拍 ----------------
        //   D4 修正轮裁定 ②: 非 clr 停流**不碎片化** —— 停流期每 2 次 grant 照成 1 个整拍
        //   (keep=FFFF / last=0), 排空完成后**只**把最后的半拍作**一拍**短末拍 (00FF/last=1)。
        //   5 个 grant (奇数) = 2 整拍 + 1 半拍 ⇒ rx_n == 3 / tlast 总数 == 1。
        //   (旧版行为: 5 个 grant ⇒ 5 拍 8 B 的 tlast 包 —— 本用例就是它的牙。)
        $display("  --- G11: stop + multi-grant drain => full packing + ONE short tail ---");
        rx_clr; q_clr; en = 1; cap_en = 1; tready = 1; w0 = dma_words;
        repeat (8) @(posedge clk);
        gr_hold = 1'b1;                         // 上游暂供 (数据先入队; 排空确实发生在停流期)
        for (i = 0; i < 5; i = i + 1) q_push({32'hB000_0000 + i, 32'hA000_0000 + i});
        repeat (4) @(posedge clk);
        cap_en = 0;                             // 停流 (采集关; 5 个 grant 还没成交)
        gr_hold = 1'b0;                         // 放行 ⇒ 停流期排空
        repeat (20) @(posedge clk);             // 排空 (~5 拍); 静置还没满 ⇒ 无收尾拍
        chk ("G11a first 2 beats FULL", rx_n, 2);
        chk ("G11a2 full-beat keep == FFFF", {16'd0, rx_keep[0]}, 32'hFFFF);
        chk1("G11a3 full-beat last == 0", rx_last[0], 1'b0);
        chk128("G11a4 beat1 == {g2,g1}", rx_data[0],
               {32'hB000_0001, 32'hA000_0001, 32'hB000_0000, 32'hA000_0000});
        chk ("G11a5 tlast total == 0", tlast_n, 32'd0);
        repeat (48) @(posedge clk);             // 静置 (>= QUIET_N=32) ⇒ 残拍收尾
        chk ("G11b ONE short tail (3 beats)", rx_n, 3);
        chk ("G11b2 tail keep == 00FF", {16'd0, rx_keep[2]}, 32'h00FF);
        chk1("G11b3 tail last == 1", rx_last[2], 1'b1);
        chk128("G11b4 tail == {0, half}", rx_data[2], {64'd0, 32'hB000_0004, 32'hA000_0004});
        chk ("G11b5 tlast total == 1", tlast_n, 32'd1);
        chk ("G11b6 aux-take cnt == 10", dma_words - w0, 32'd10);

        // ---------------- G11b: 长排空 (41 grant): 排空期**零** tlast + 收尾恰一拍 ----------------
        //   41 个 grant (奇数) = 20 个整拍 + 1 个半拍。排空本身跨 >32 拍 ⇒ 静置计数必须
        //   在**每次 grant 上归零**, 否则会在排空中途误判"排空完成" ⇒ 中途多冒收尾拍。
        $display("  --- G11b: long drain (41 grants): zero tlast during drain, exactly one tail ---");
        rx_clr; q_clr; gnt0 = gnt_seen; w0 = dma_words; en = 1; cap_en = 1; tready = 1;
        repeat (8) @(posedge clk);
        gr_hold = 1'b1;
        for (i = 0; i < 41; i = i + 1) q_push({32'hD000_0000 + i, 32'hC000_0000 + i});
        repeat (4) @(posedge clk);
        cap_en = 0;
        gr_hold = 1'b0;
        repeat (140) @(posedge clk);            // 排空 ~41 拍 + 静置 32 拍 + 收尾
        chk ("G11b-a 21 beats (20F+1S)", rx_n, 21);
        chk ("G11b-b tlast total == 1", tlast_n, 32'd1);
        for (j = 0; j < 20; j = j + 1) begin
            if ((rx_keep[j] !== 16'hFFFF) || (rx_last[j] !== 1'b0)) begin
                $display("  [FAIL] G11b-j 排空期第 %0d 拍不是 (keep=FFFF, last=0) (keep=%04x last=%b)",
                         j, rx_keep[j], rx_last[j]);
                fails = fails + 1; j = 100;
            end
        end
        if (j != 100) $display("  [PASS] G11b-j 排空期 20 拍全部 (keep=FFFF, last=0)");
        chk ("G11b-c tail keep == 00FF", {16'd0, rx_keep[20]}, 32'h00FF);
        chk1("G11b-d tail last == 1", rx_last[20], 1'b1);
        chk ("G11b-e aux-take cnt == 82", dma_words - w0, 32'd82);

        // ---------------- G12: ⭐ 重复/nested stop ⇒ 不重复发 ----------------
        //   G11b 收尾后 stop 仍 = 1 (cap_en=0): 再静置 100 拍不许再冒拍;
        //   再 cap_en 1→0 二次停流 (无新数据 ⇒ 无新残留) 仍不许冒拍。
        $display("  --- G12: repeated/nested stop does NOT re-send ---");
        repeat (100) @(posedge clk);
        chk ("G12a hold stop 100cyc: same", rx_n, 21);
        chk1("G12b tvalid == 0", t_valid, 1'b0);
        cap_en = 1; repeat (8) @(posedge clk);
        cap_en = 0; repeat (48) @(posedge clk);
        chk ("G12c 2nd stop: no beat", rx_n, 21);
        chk ("G12d tlast total == 1", tlast_n, 32'd1);
        cap_en = 1; repeat (4) @(posedge clk);

        // ---------------- 收尾 ----------------
        en = 0; cap_en = 0; do_clr; repeat (4) @(posedge clk);
        if (fails == 0) $display("AXIS_C2H_STREAM_GATE: PASS_ALL");
        else            $display("AXIS_C2H_STREAM_GATE: FAIL (%0d checks failed)", fails);
        $display("=== done ===");
        $finish;
    end

    initial begin #2000000; $display("TIMEOUT"); $finish; end

endmodule
