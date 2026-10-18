`timescale 1ns/1ps
//=============================================================================
// win_pool_mgr.v — P11 P3 (C4 甲·双栈): 单共享窗口信用池 (8 槽 / 2 口)
//=============================================================================
// 设计件 = _proj_10g/notes/p11_p3_dualstack_design_20261018/README_FOR_TL.md
//   §4.2 (96KB BDP) / §4.3 (预配额 + 6 类写点旁路 + 统一释放) / §9.1 G-P3-1。
//
// 语义 (用户约束: "两个 SFP+ 接口共用 8 个 TCP 连接的缓存资源"):
//   · pool     : 全系统剩余信用 (17 位; WIN_POOL = 96KB = 0x18000)
//   · winq[0:7]: 每条连接 (全局 slot) 的**预配额** (16 位) —— 建连前授予, 连接
//                存活期内不收回 (窗口一旦通告不可撤销), 因此本模块**没有**
//                建连后动态借还, 也没有 app_ctrl 的 C15 增量补授。
//   · port_win : 每口已授配额之和 (17 位) —— 只用于 port_cap 上限与观测。
//
// 授予 (ev_up, 来自 slow_cfg_adp ADD 收尾; 与 app_ctrl 的 init 拍相邻):
//     g = min(wq_cap, max(pool - occ[p], 0), max(port_cap - port_win[p], 0))
//     winq[slot] <= g
//     pool       <= pool - g + old_winq[slot]      (C18: 旧配额原子归还)
//     port_win[p]<= port_win[p] - old_winq[slot] + g
//   `occ[p]` = 该口 tcp_echo frame_fifo 当前占用字节 (17 位饱和) —— 零拷贝占用
//   不随 ev_down 释放, 故与 app_ctrl 的 C14 同语义从新配额里扣除。
//
// 归还 (rel, 来自 app_ctrl 的**统一释放** o_quota_rel/o_quota_rel_slot —
//   覆盖 外部 DEL / 孤儿回收 / 关闭超时 / abort+state=0 四条路径):
//     pool       <= pool + winq[slot]
//     port_win[p]<= port_win[p] - winq[slot]
//     winq[slot] <= 0
//   同一槽重复 rel 幂等 (winq 已是 0 ⇒ 加 0); 非幂等事件计 stat_rel_dup。
//
// 同拍两口事件: 池算术按 **port0 -> port1** 固定顺序组合计算 (§4.3);
//   事件稀疏 ⇒ 不引入额外握手, 也不改变单口时序。
//
// 不变量 (G-P3-1 / G-P3-1b 逐拍断言):
//   Σ winq + pool == WIN_POOL · Σ port_win == Σ winq · port_win[p] <= port_cap
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
    // ---- 观测/状态 ----
    output wire [16:0] dbg_pool,
    output wire [16:0] dbg_port_win0,
    output wire [16:0] dbg_port_win1,
    output reg  [31:0] stat_grant_zero,      // 授予量 == 0 的次数 (准入合同被违反的信号)
    output reg  [31:0] stat_slot_reuse,      // ev_up 落在已占槽 (C18 防御路径)
    output reg  [31:0] stat_rel_dup,         // rel 时 winq == 0 (应恒 0)
    output reg  [31:0] stat_slot_oor        // ev_up/rel 槽号 >= 8 (应恒 0; cfg demux 已守卫)
);
    localparam NSLOT = 8;

    reg  [16:0] pool;
    reg  [15:0] winq [0:NSLOT-1];
    reg  [16:0] port_win0, port_win1;

    assign dbg_pool      = pool;
    assign dbg_port_win0 = port_win0;
    assign dbg_port_win1 = port_win1;

    // 只读配额口 (组合; 槽号 >= 8 返回 0 —— 与 app_ctrl 的 4 位索引对齐)
    assign winq_rd0  = (winq_rd_id0  < 4'd8) ? winq[winq_rd_id0]  : 16'd0;
    assign winq_rd0b = (winq_rd_id0b < 4'd8) ? winq[winq_rd_id0b] : 16'd0;
    assign winq_rd1  = (winq_rd_id1  < 4'd8) ? winq[winq_rd_id1]  : 16'd0;
    assign winq_rd1b = (winq_rd_id1b < 4'd8) ? winq[winq_rd_id1b] : 16'd0;

    // ---- 组合下一状态 (port0 -> port1 固定顺序) ----
    reg  [16:0] pool_n;
    reg  [15:0] winq_n [0:NSLOT-1];
    reg  [16:0] pw0_n, pw1_n;
    reg  [15:0] old_q;
    reg  [16:0] avail, room, g;
    reg         ev0_v, ev1_v;
    integer     i;

    always @(*) begin
        pool_n = pool;
        for (i = 0; i < NSLOT; i = i + 1) winq_n[i] = winq[i];
        pw0_n  = port_win0;
        pw1_n  = port_win1;

        // ---------------- port0 ----------------
        // ev_up 优先于 rel (同一口同一拍不可能两者皆有; 防御性优先)
        if (ev_up0) begin
            // C18: **旧配额先回池, 再授新** (设计件 §4.3 "原子完成")
            old_q  = winq_n[ev_up_slot0[2:0]];
            avail  = (pool_n > occ0) ? (pool_n - occ0) : 17'd0;
            room   = (port_cap > pw0_n) ? (port_cap - pw0_n) : 17'd0;
            g      = {1'b0, wq_cap};
            if (avail < g) g = avail;
            if (room  < g) g = room;
            winq_n[ev_up_slot0[2:0]] = g[15:0];
            pool_n = pool_n - g;
            pw0_n  = pw0_n + g;
        end else if (rel0) begin
            old_q = winq_n[rel_slot0[2:0]];
            pool_n = pool_n + {1'b0, old_q};
            pw0_n  = pw0_n - {1'b0, old_q};
            winq_n[rel_slot0[2:0]] = 16'd0;
        end

        // ---------------- port1 (使用 port0 之后的池) ----------------
        if (ev_up1) begin
            old_q  = winq_n[ev_up_slot1[2:0]];
            pool_n = pool_n + {1'b0, old_q};
            pw1_n  = pw1_n - {1'b0, old_q};
            avail  = (pool_n > occ1) ? (pool_n - occ1) : 17'd0;
            room   = (port_cap > pw1_n) ? (port_cap - pw1_n) : 17'd0;
            g      = {1'b0, wq_cap};
            if (avail < g) g = avail;
            if (room  < g) g = room;
            winq_n[ev_up_slot1[2:0]] = g[15:0];
            pool_n = pool_n - g;
            pw1_n  = pw1_n + g;
        end else if (rel1) begin
            old_q = winq_n[rel_slot1[2:0]];
            pool_n = pool_n + {1'b0, old_q};
            pw1_n  = pw1_n - {1'b0, old_q};
            winq_n[rel_slot1[2:0]] = 16'd0;
        end
    end

    // 授予量 == 0 的检测 (组合块内的中间量不可靠 —— 顺序赋值; 这里独立重算一级
    // 算术, 只喂计数寄存器, 不影响授予数据通路)。
    wire [16:0] pool0_o  = pool + {1'b0, winq[ev_up_slot0]};
    wire [16:0] pw0_eff  = port_win0 - {1'b0, winq[ev_up_slot0]};
    wire [16:0] avail0_o = (pool0_o > occ0) ? (pool0_o - occ0) : 17'd0;
    wire [16:0] room0_o  = (port_cap > pw0_eff) ? (port_cap - pw0_eff) : 17'd0;
    wire [16:0] g0_o     = (avail0_o < {1'b0, wq_cap}) ? avail0_o : {1'b0, wq_cap};
    wire [16:0] g_dummy0 = (room0_o < g0_o) ? room0_o : g0_o;
    wire [16:0] pool1_o  = pool + {1'b0, winq[ev_up_slot1]};
    wire [16:0] pw1_eff  = port_win1 - {1'b0, winq[ev_up_slot1]};
    wire [16:0] avail1_o = (pool1_o > occ1) ? (pool1_o - occ1) : 17'd0;
    wire [16:0] room1_o  = (port_cap > pw1_eff) ? (port_cap - pw1_eff) : 17'd0;
    wire [16:0] g1_o     = (avail1_o < {1'b0, wq_cap}) ? avail1_o : {1'b0, wq_cap};
    wire [16:0] g_dummy1 = (room1_o < g1_o) ? room1_o : g1_o;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pool       <= WIN_POOL;
            port_win0  <= 17'd0;
            port_win1  <= 17'd0;
            stat_grant_zero <= 32'd0;
            stat_slot_reuse <= 32'd0;
            stat_rel_dup    <= 32'd0;
            stat_slot_oor   <= 32'd0;
            for (i = 0; i < NSLOT; i = i + 1) winq[i] <= 16'd0;
        end else begin
            pool      <= pool_n;
            port_win0 <= pw0_n;
            port_win1 <= pw1_n;
            for (i = 0; i < NSLOT; i = i + 1) winq[i] <= winq_n[i];

            if (ev_up0 && (ev_up_slot0 >= 4'd8)) stat_slot_oor <= stat_slot_oor + 32'd1;
            if (ev_up1 && (ev_up_slot1 >= 4'd8)) stat_slot_oor <= stat_slot_oor + 32'd1;
            if (rel0    && (rel_slot0    >= 4'd8)) stat_slot_oor <= stat_slot_oor + 32'd1;
            if (rel1    && (rel_slot1    >= 4'd8)) stat_slot_oor <= stat_slot_oor + 32'd1;

            if (ev_up0 && (ev_up_slot0 < 4'd8)) begin
                if (g_dummy0 == 17'd0) stat_grant_zero <= stat_grant_zero + 32'd1;
                if (winq[ev_up_slot0] != 16'd0) stat_slot_reuse <= stat_slot_reuse + 32'd1;
            end
            if (ev_up1 && (ev_up_slot1 < 4'd8)) begin
                if (g_dummy1 == 17'd0) stat_grant_zero <= stat_grant_zero + 32'd1;
                if (winq[ev_up_slot1] != 16'd0) stat_slot_reuse <= stat_slot_reuse + 32'd1;
            end
            if (rel0 && (rel_slot0 < 4'd8) && (winq[rel_slot0] == 16'd0))
                stat_rel_dup <= stat_rel_dup + 32'd1;
            if (rel1 && (rel_slot1 < 4'd8) && (winq[rel_slot1] == 16'd0))
                stat_rel_dup <= stat_rel_dup + 32'd1;
        end
    end

endmodule
