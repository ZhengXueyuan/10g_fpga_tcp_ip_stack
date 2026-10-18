`timescale 1ns/1ps
//=============================================================================
// win_pool_mgr.v — P11 P3 (C4 甲·双栈): 单共享窗口信用池 (8 槽 / 2 口)
//=============================================================================
// 设计件 = _proj_10g/notes/p11_p3_dualstack_design_20261018/README_FOR_TL.md
//   §4.2 (96KB BDP) / §4.3 (预配额 + 6 类写点旁路 + 统一释放) / §9.1 G-P3-1。
//
// 语义 (用户约束: "两个 SFP+ 接口共用 8 个 TCP 连接的缓存资源"):
//   · pool       : 全系统剩余信用 (17 位; WIN_POOL = 96KB = 0x18000)
//   · winq[0:7]  : 每条连接 (全局 slot) 的**预配额** (16 位) —— 建连前授予, 连接
//                  存活期内不收回 (窗口一旦通告不可撤销), 因此本模块**没有**
//                  建连后动态借还, 也没有 app_ctrl 的 C15 增量补授。
//   · port_win   : 每口已授配额之和 (17 位) —— 只用于 port_cap 上限与观测。
//   · grant_port : 每个槽**最近一次授予**的口 (1 = port1 / 0 = port0)。
//                  ⭐ H-1 (P3 修复轮): rel 与 C18 的 old 一律从**授出端口**的
//                  port_win 扣, 而不是从事件端口扣。跨口同槽复用 (旧连接在
//                  port0 释放了槽、新连接在 port1 复用同一槽) 时, 旧口的 rel
//                  可能晚于新口的 ev_up ⇒ 若按事件端口扣, 会把**新口**刚授出
//                  的配额扣掉/下溢。grant_port 让旧 rel 正确归还到它当初被
//                  授予的那一口。
//
// 授予 (ev_up, 来自 slow_cfg_adp ADD 收尾; 与 app_ctrl 的 init 拍相邻):
//     g = min(wq_cap, max(pool - occ[p], 0), max(port_cap - port_win[p], 0))
//     winq[slot] <= g
//     old = winq[slot] (C18)
//     pool       <= pool - g + old
//     port_win[grant_port[slot]] <= port_win[grant_port[slot]] - old  (饱和)
//     port_win[p]<= port_win[p] + g
//     grant_port[slot] <= p
//   `occ[p]` = 该口 tcp_echo frame_fifo 当前占用字节 (17 位饱和) —— 零拷贝占用
//   不随 ev_down 释放, 故与 app_ctrl 的 C14 同语义从新配额里扣除。
//
// 归还 (rel, 来自 app_ctrl 的**统一释放** o_quota_rel/o_quota_rel_slot —
//   覆盖 外部 DEL / 孤儿回收 / 关闭超时 / abort+state=0 四条路径):
//     pool       <= pool + winq[slot]
//     port_win[grant_port[slot]] <= port_win[grant_port[slot]] - winq[slot] (饱和)
//     winq[slot] <= 0
//   同一槽重复 rel 幂等 (winq 已是 0 ⇒ 加 0); 非幂等事件计 stat_rel_dup。
//   ⚠️ rel **不**清 grant_port: 跨口复用时 grant_port 已指向新口。
//
// ⭐ 跨口复用的时序语义 (H-1 门覆盖):
//   旧连接 port0 slot N (winq=0x3000) → DEL → 新连接 port1 复用 N:
//   ① ev_up1 先到: C18 old=0x3000 从 **grant_port[N]=0 (port0)** 的 port_win
//      扣回池, 新配额 g 记到 port1, grant_port[N]<=1。
//   ② 旧口 rel0 后到: 事件口 port0 != grant_port[N]=1 ⇒ **非属主迟到释放**,
//      忽略并计 stat_rel_stale_port —— 不得把新口刚落地的配额吞掉。
//      (旧连接的配额已在 ① 被 C18 原子归还; 这条 rel 是上游应当抑制的重复
//      事件。即便它到达, 也只能影响"是否记录", 不能改状态。)
//   TB 断言: 新配额仍在 winq[N]、port_win 落在新口、不变量成立、
//   stat_rel_stale_port 递增、stat_port_win_underflow 恒 0。
//
// 同拍两口事件: 池算术按 **rel0 -> ev_up0 -> ev_up1(rel1 见下)** 的固定顺序
//   组合计算 (§4.3 的 port0 -> port1 顺序; 同一口内 rel 先于 ev_up —— 两者
//   同槽时与 C18 "旧配额先回池再授新"逐位等价)。同拍 ev_up 与 rel 落在
//   **不同槽**时两者都处理 (旧实装的 `else if` 会静默丢 rel ⇒ 配额泄漏;
//   M-4 修复)。
//
// 不变量 (G-P3-1 / G-P3-1b 逐拍断言):
//   Σ winq + pool == WIN_POOL · Σ port_win == Σ winq · port_win[p] <= port_cap
//
// 槽号 >= 8 (M-3): 事件只计 stat_slot_oor, **不改任何状态** (旧实装的算术
//   仍按 [2:0] 别名到 0..7 ⇒ 会静默改错槽)。
//
// 本模块是 C4 专用新件; C1/C2/C3 构建不例化 (设计件 §2.4)。
//=============================================================================
module win_pool_mgr #(
    parameter [16:0] WIN_POOL = 17'h18000,   // 96KB 单共享池
    parameter [16:0] PORT_CAP = 17'h18000    // 每口上限 (默认 = 全池; 可被 port_cap 输入覆盖)
) (
    input  wire        clk,
    input  wire        rst_n,
    // ---- 授予: ADD 收尾 (每口一套 slow_cfg_adp ev_up) ----
    input  wire        ev_up0,
    input  wire [3:0]  ev_up_slot0,
    input  wire        ev_up1,
    input  wire [3:0]  ev_up_slot1,
    // ---- 统一释放 (app_ctrl.o_quota_rel / o_quota_rel_slot) ----
    input  wire        rel0,
    input  wire [3:0]  rel_slot0,
    input  wire        rel1,
    input  wire [3:0]  rel_slot1,
    // ---- 每口 tcp_echo 占用字节 (17 位饱和) ----
    input  wire [16:0] occ0,
    input  wire [16:0] occ1,
    // ---- 合同常量 (构建常量 / boot writer; 本实装接常量) ----
    input  wire [15:0] wq_cap,        // 每连接配额 (8 连接 12KB / 2 连接 48KB)
    input  wire [16:0] port_cap,      // 每口上限 (默认 = WIN_POOL)
    // ---- 只读配额口 (每个 app_ctrl 两个: 扫描/init 口 + 事件口) ----
    // 为什么两个而不是一个: app_ctrl 的扫描采样拍 (`fq_scan` 用 scan_id) 与
    // ev_down/ev_up 事件拍可能落在**不同的槽**上; 单口无法同拍服务两个索引
    // ⇒ 会把一个槽的配额当成另一个槽的扫描结果 (redge 毒化)。设计件的"单读口
    // ID mux"在本实装里按此拆成两口 (读口加宽, 不动语义)。
    input  wire [3:0]  winq_rd_id0,      // port0 app_ctrl: 扫描/init 口
    output wire [15:0] winq_rd0,
    input  wire [3:0]  winq_rd_id0b,     // port0 app_ctrl: 事件口 (ev)
    output wire [15:0] winq_rd0b,
    input  wire [3:0]  winq_rd_id1,      // port1 app_ctrl: 扫描/init 口
    output wire [15:0] winq_rd1,
    input  wire [3:0]  winq_rd_id1b,     // port1 app_ctrl: 事件口 (ev)
    output wire [15:0] winq_rd1b,
    // ---- 槽属主映射 (H-2: retx_pool_shared 的 owner 用它, 不用 cfg demux 的
    //      slot_port —— 后者在 ADD 路由拍就翻, 早于旧口 TCB 拆除完成) ----
    output wire [7:0]  o_grant_port,
    // ---- 观测/状态 ----
    output wire [16:0] dbg_pool,
    output wire [16:0] dbg_port_win0,
    output wire [16:0] dbg_port_win1,
    output reg  [31:0] stat_grant_zero,      // 授予量 == 0 的次数 (准入合同被违反的信号)
    output reg  [31:0] stat_slot_reuse,      // ev_up 落在已占槽 (C18 防御路径)
    output reg  [31:0] stat_rel_dup,         // rel 时 winq == 0 (应恒 0)
    output reg  [31:0] stat_slot_oor,        // ev_up/rel 槽号 >= 8 (应恒 0; cfg demux 已守卫)
    output reg  [31:0] stat_c18_cross_port,  // C18 旧配额属主 != 事件端口 (跨口同槽复用)
    output reg  [31:0] stat_port_win_underflow, // port_win 饱和扣减 (应恒 0)
    output reg  [31:0] stat_rel_stale_port   // 非属主口的 rel (跨口复用后的迟到事件; 应恒 0)
);
    localparam NSLOT = 8;

    reg  [16:0] pool;
    reg  [15:0] winq [0:NSLOT-1];
    reg  [16:0] port_win0, port_win1;
    reg  [7:0]  grant_port;          // 1 = port1, 0 = port0 (最近一次 ev_up 授出的口)

    assign dbg_pool      = pool;
    assign dbg_port_win0 = port_win0;
    assign dbg_port_win1 = port_win1;
    assign o_grant_port  = grant_port;

    // 只读配额口 (组合; 槽号 >= 8 返回 0 —— 与 app_ctrl 的 4 位索引对齐)
    assign winq_rd0  = (winq_rd_id0  < 4'd8) ? winq[winq_rd_id0]  : 16'd0;
    assign winq_rd0b = (winq_rd_id0b < 4'd8) ? winq[winq_rd_id0b] : 16'd0;
    assign winq_rd1  = (winq_rd_id1  < 4'd8) ? winq[winq_rd_id1]  : 16'd0;
    assign winq_rd1b = (winq_rd_id1b < 4'd8) ? winq[winq_rd_id1b] : 16'd0;

    // ---- 组合下一状态 (rel0 -> ev_up0 -> ev_up1 -> rel1 固定顺序) ----
    reg  [16:0] pool_n;
    reg  [15:0] winq_n [0:NSLOT-1];
    reg  [16:0] pw0_n, pw1_n;
    reg  [7:0]  gp_n;
    reg  [15:0] old_q;
    reg         old_owner;
    reg  [16:0] avail, room, g;
    reg  [16:0] g0_c, g1_c;          // 本拍实际授予量 (stat_grant_zero 用; L-1)
    reg  [1:0]  uw_cnt;              // 本拍 port_win 下溢次数
    reg         dup0_c, dup1_c;      // 本拍 rel 撞 winq==0
    reg         c18x0_c, c18x1_c;    // 本拍 C18 跨口
    reg         stale0_c, stale1_c;  // 本拍 rel 来自非属主口 (迟到事件)
    integer     i;

    // 饱和扣减: pw >= q ? pw-q : 0 (后者同时置 uw_cnt)
    reg  [16:0] sub_r;
    task automatic sat_sub;
        input [16:0] pw; input [15:0] q;
        begin
            if (pw > {1'b0, q}) begin
                sub_r = pw - {1'b0, q};
            end else begin
                sub_r = 17'd0;
                if (pw != {1'b0, q}) uw_cnt = uw_cnt + 2'd1;
            end
        end
    endtask

    always @(*) begin
        pool_n = pool;
        for (i = 0; i < NSLOT; i = i + 1) winq_n[i] = winq[i];
        pw0_n  = port_win0;
        pw1_n  = port_win1;
        gp_n   = grant_port;
        g0_c   = 17'd0;
        g1_c   = 17'd0;
        uw_cnt = 2'd0;
        dup0_c = 1'b0;
        dup1_c = 1'b0;
        c18x0_c = 1'b0;
        c18x1_c = 1'b0;
        stale0_c = 1'b0;
        stale1_c = 1'b0;

        // ================= port0 rel (同口内先于 ev_up; 同槽时等价 C18) ======
        //   H-1: 只有**属主口**的 rel 才有意义。跨口复用后旧口的迟到 rel
        //   (事件口 != grant_port) 一律忽略并计数 —— 否则它会把新口刚落地的
        //   配额吞掉 ("新配额不被旧 rel 吞")。
        if (rel0 && !rel_slot0[3] &&
            !(ev_up0 && !ev_up_slot0[3] && (ev_up_slot0 == rel_slot0))) begin
            if (gp_n[rel_slot0[2:0]] != 1'b0) begin
                stale0_c = 1'b1;
            end else begin
                old_q = winq_n[rel_slot0[2:0]];
                if (old_q != 16'd0) begin
                    pool_n = pool_n + {1'b0, old_q};
                    pw0_n  = pw0_n - {1'b0, old_q};   // 属主 = port0; 不变式保证 pw0 >= q
                    winq_n[rel_slot0[2:0]] = 16'd0;
                end else begin
                    dup0_c = 1'b1;
                end
            end
        end

        // ================= port0 ev_up (C18: old 从**授出端口**扣) ==========
        if (ev_up0 && !ev_up_slot0[3]) begin
            old_q     = winq_n[ev_up_slot0[2:0]];
            old_owner = gp_n[ev_up_slot0[2:0]];
            if (old_q != 16'd0) begin
                pool_n = pool_n + {1'b0, old_q};
                if (old_owner != 1'b0) begin
                    sat_sub(pw1_n, old_q);
                    pw1_n = sub_r;
                end else begin
                    sat_sub(pw0_n, old_q);
                    pw0_n = sub_r;
                end
                if (old_owner != 1'b0) c18x0_c = 1'b1;   // 旧属 port1, 新授 port0
            end
            avail  = (pool_n > occ0) ? (pool_n - occ0) : 17'd0;
            room   = (port_cap > pw0_n) ? (port_cap - pw0_n) : 17'd0;
            g      = {1'b0, wq_cap};
            if (avail < g) g = avail;
            if (room  < g) g = room;
            winq_n[ev_up_slot0[2:0]] = g[15:0];
            pool_n = pool_n - g;
            pw0_n  = pw0_n + g;
            gp_n[ev_up_slot0[2:0]] = 1'b0;
            g0_c   = g;
        end

        // ================= port1 ev_up (使用 port0 之后的池) ===============
        if (ev_up1 && !ev_up_slot1[3]) begin
            old_q     = winq_n[ev_up_slot1[2:0]];
            old_owner = 1'b1;
            if (old_q != 16'd0) begin
                pool_n = pool_n + {1'b0, old_q};
                if (old_owner) begin
                    sat_sub(pw1_n, old_q);
                    pw1_n = sub_r;
                end else begin
                    sat_sub(pw0_n, old_q);
                    pw0_n = sub_r;
                end
                if (old_owner == 1'b0) c18x1_c = 1'b1;   // 旧属 port0, 新授 port1
            end
            avail  = (pool_n > occ1) ? (pool_n - occ1) : 17'd0;
            room   = (port_cap > pw1_n) ? (port_cap - pw1_n) : 17'd0;
            g      = {1'b0, wq_cap};
            if (avail < g) g = avail;
            if (room  < g) g = room;
            winq_n[ev_up_slot1[2:0]] = g[15:0];
            pool_n = pool_n - g;
            pw1_n  = pw1_n + g;
            gp_n[ev_up_slot1[2:0]] = 1'b1;
            g1_c   = g;
        end

        // ================= port1 rel (only owner port; see H-1 above) =========
        if (rel1 && !rel_slot1[3] &&
            !(ev_up1 && !ev_up_slot1[3] && (ev_up_slot1 == rel_slot1))) begin
            if (gp_n[rel_slot1[2:0]] != 1'b1) begin
                stale1_c = 1'b1;
            end else begin
                old_q = winq_n[rel_slot1[2:0]];
                if (old_q != 16'd0) begin
                    pool_n = pool_n + {1'b0, old_q};
                    pw1_n  = pw1_n - {1'b0, old_q};
                    winq_n[rel_slot1[2:0]] = 16'd0;
                end else begin
                    dup1_c = 1'b1;
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pool       <= WIN_POOL;
            port_win0  <= 17'd0;
            port_win1  <= 17'd0;
            grant_port <= 8'd0;
            stat_grant_zero <= 32'd0;
            stat_slot_reuse <= 32'd0;
            stat_rel_dup    <= 32'd0;
            stat_slot_oor   <= 32'd0;
            stat_c18_cross_port <= 32'd0;
            stat_port_win_underflow <= 32'd0;
            stat_rel_stale_port <= 32'd0;
            for (i = 0; i < NSLOT; i = i + 1) winq[i] <= 16'd0;
        end else begin
            pool       <= pool_n;
            port_win0  <= pw0_n;
            port_win1  <= pw1_n;
            grant_port <= gp_n;
            for (i = 0; i < NSLOT; i = i + 1) winq[i] <= winq_n[i];

            // 槽号越界: 只计数, 状态不变 (组合块已 gate `!slot[3]`)
            if (ev_up0 && (ev_up_slot0 >= 4'd8)) stat_slot_oor <= stat_slot_oor + 32'd1;
            if (ev_up1 && (ev_up_slot1 >= 4'd8)) stat_slot_oor <= stat_slot_oor + 32'd1;
            if (rel0    && (rel_slot0    >= 4'd8)) stat_slot_oor <= stat_slot_oor + 32'd1;
            if (rel1    && (rel_slot1    >= 4'd8)) stat_slot_oor <= stat_slot_oor + 32'd1;

            if (ev_up0 && (ev_up_slot0 < 4'd8)) begin
                if (g0_c == 17'd0) stat_grant_zero <= stat_grant_zero + 32'd1;
                if (winq[ev_up_slot0] != 16'd0) stat_slot_reuse <= stat_slot_reuse + 32'd1;
            end
            if (ev_up1 && (ev_up_slot1 < 4'd8)) begin
                if (g1_c == 17'd0) stat_grant_zero <= stat_grant_zero + 32'd1;
                if (winq[ev_up_slot1] != 16'd0) stat_slot_reuse <= stat_slot_reuse + 32'd1;
            end
            if (dup0_c) stat_rel_dup <= stat_rel_dup + 32'd1;
            if (dup1_c) stat_rel_dup <= stat_rel_dup + 32'd1;
            if (stale0_c) stat_rel_stale_port <= stat_rel_stale_port + 32'd1;
            if (stale1_c) stat_rel_stale_port <= stat_rel_stale_port + 32'd1;
            if (c18x0_c) stat_c18_cross_port <= stat_c18_cross_port + 32'd1;
            if (c18x1_c) stat_c18_cross_port <= stat_c18_cross_port + 32'd1;
            if (uw_cnt != 2'd0) stat_port_win_underflow <= stat_port_win_underflow + {30'd0, uw_cnt};
        end
    end

endmodule
