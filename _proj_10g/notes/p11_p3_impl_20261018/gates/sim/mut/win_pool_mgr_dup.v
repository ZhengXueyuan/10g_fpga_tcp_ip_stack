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
//     **仅属主口**: 若事件口 != grant_port[slot] ⇒ 忽略 (计 stat_rel_stale_port)
//     否则 port_win[slot 的授出口] <= ... - winq[slot]; winq[slot] <= 0
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
// 同拍多事件的固定先后: **rel0 -> ev_up0 -> ev_up1 -> rel1** (§4.3 的
//   port0 -> port1 顺序; 同一口内 rel 先于 ev_up —— 两者同槽时与 C18
//   "旧配额先回池再授新"逐位等价)。同拍 ev_up 与 rel 落在**不同槽**时
//   两者都处理 (旧实装的 `else if` 会静默丢 rel ⇒ 配额泄漏; M-4 修复)。
//
// ⭐⭐ 0x2F 时序缺陷修复 (2026-10-19; 根因 = 42 级组合链 13.137ns):
//   旧实装把 **rel0 -> ev_up0 -> ev_up1 -> rel1** 四个事件 + 8 槽 winq 数组
//   的下状态**全部塞进一个 always @(*) 组合块** —— 最差路径
//   `u_app_ctrl/c_rcv_nxt_reg[9][4]/C -> u_win_pool/port_win1_reg[0]/D`
//   13.137ns (42 级, WNS -6.456, 25,697 失败端点)。定向 STA 另证:
//   **ev_up 自身路径仍有余量** (ev_up0 +0.323ns / ev_up1 +0.201ns) ⇒ 必须
//   切断的是 "app_ctrl 扫描态 rel -> manager 算术" 这条组合链, 不是整个池。
//
//   新实装 = **事件 FIFO + 串行三拍事件机**:
//     · 每个事件 (type+slot) 按固定先后压入 32 深 FIFO (最多 4 条/拍);
//     · 事件机逐条处理, 每条三拍:
//         S_LOAD  : 读 state (pool/port_win/winq[slot]/grant_port[slot]/occ)
//         S_CALC  : pool_after = pool + old ; pw_after = sat_sub(pw, old) ;
//                   avail/room
//         S_COMMIT: g = min(wq_cap, avail, room); 提交 pool/winq/port_win/
//                   grant_port; 打 stat; 对 ev_up 产生 done 脉冲 (见下)
//     · 三拍之间状态不被别的写者碰 (本模块是唯一属主) ⇒ 逐位等价于旧组合算式;
//       全局事件先后由 FIFO 保序 (同拍仍按 rel0/ev_up0/ev_up1/rel1 排队)。
//     · **grant-done 握手**: ev_up 的提交发生在 S_COMMIT 沿, 下一拍
//       `o_ev_up_doneN` 高 —— 该拍 winq[slot] 已是新配额。app_ctrl 的 init
//       **必须**等到对应 done 再读 (否则读到旧配额 ⇒ 零窗死锁)。
//       `o_ev_up_done_slotN` 让 app_ctrl 校验"这条 done 对应队列头事件"。
//     · FIFO 溢出 (理论上不可达: 服务 1 条/3 拍, 上游 HLS 事件远低于此)
//       不静默丢: `stat_ev_ovf` 计数, 且本拍所有 push 都不落地 (保序)。
//
//   不变量 (G-P3-1 / G-P3-1b 逐拍断言):
//     Σ winq + pool == WIN_POOL · Σ port_win == Σ winq · port_win[p] <= port_cap
//
// 槽号 >= 8 (M-3): 事件照常入 FIFO/出 FIFO, 但**不改任何状态** (只计
//   stat_slot_oor); ev_up 仍产生 done (app_ctrl 读到 0 配额, 与旧式一致)。
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
    output reg  [31:0] stat_rel_stale_port,  // 非属主口的 rel (跨口复用后的迟到事件; 应恒 0)
    // ---- 0x2F 时序修复新增: ev_up 提交完成握手 (app_ctrl init 用) ----
    output reg         o_ev_up_done0,        // 1 拍脉冲; 高电平那拍 winq 已是新配额
    output reg  [3:0]  o_ev_up_done_slot0,
    output reg         o_ev_up_done1,
    output reg  [3:0]  o_ev_up_done_slot1,
    output reg  [31:0] stat_ev_ovf,          // 事件 FIFO 溢出 (理论不可达; 非静默)
    // ---- TB 观测 ----
    output wire        dbg_busy,             // 事件机忙或有事件待处理
    output wire        dbg_ev_commit,        // 高 = 本拍在 S_COMMIT (TB 影子模型用)
    output wire [1:0]  dbg_ev_type,
    output wire [3:0]  dbg_ev_slot
);
    localparam NSLOT = 8;

    // 事件编码: 0=rel0, 1=ev_up0, 2=rel1, 3=ev_up1
    //   bit0 = 1 -> ev_up; bit1 = 口 (0/1)
    //   ⚠️ 不能按"0/1/2/3 = rel0/evup0/evup1/rel1"直排: 那样 bit0/bit1 的语义
    //      会随编号翻转 (ev_up1=10 会被判成 rel, rel1=11 会被判成 ev_up)。
    localparam [1:0] E_REL0  = 2'b00;
    localparam [1:0] E_EVUP0 = 2'b01;
    localparam [1:0] E_REL1  = 2'b10;
    localparam [1:0] E_EVUP1 = 2'b11;

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

    //=========================================================================
    // 事件 FIFO (32 深 x 6 位; 最多 4 条 push/拍, 1 条 pop/拍)
    //=========================================================================
    localparam EDEPTH = 32;
    localparam [5:0] EDEPTH_6 = 6'd32;

    reg  [5:0]  evq [0:EDEPTH-1];
    reg  [4:0]  evq_wr;
    reg  [4:0]  evq_rd;
    reg  [5:0]  evq_cnt;

    wire [5:0]  evq_head = evq[evq_rd];

    // 同拍 push 顺序 = rel0 -> ev_up0 -> ev_up1 -> rel1
    // 同口同槽 rel+ev_up 同拍: C18 吸收 (rel 不单独入队; 与旧实装逐位一致)
    //   同口同槽 rel+ev_up 同拍: C18 吸收 (rel 不单独入队; 与旧实装逐位一致)。
    //   OOR 事件不参与该抑制 (旧实装只对 slot<8 的 rel 做吸收, OOR 仍计 stat)。
    wire p_rel0 = rel0 && !(ev_up0 && (ev_up_slot0 < 4'd8) &&
                            (rel_slot0 < 4'd8) && (ev_up_slot0 == rel_slot0));
    wire p_up0  = ev_up0;
    wire p_up1  = ev_up1;
    wire p_rel1 = rel1 && !(ev_up1 && (ev_up_slot1 < 4'd8) &&
                            (rel_slot1 < 4'd8) && (ev_up_slot1 == rel_slot1));

    wire [2:0] push_cnt = {2'b0, p_rel0} + {2'b0, p_up0} +
                          {2'b0, p_up1} + {2'b0, p_rel1};
    wire [5:0] push_cnt_6 = {3'b0, push_cnt};

    // 事件机状态
    localparam [1:0] S_LOAD   = 2'd0;
    localparam [1:0] S_CALC   = 2'd1;
    localparam [1:0] S_COMMIT = 2'd2;

    reg  [1:0]  eng_state;
    reg  [1:0]  e_type;
    reg  [3:0]  e_slot;
    reg         e_port;
    reg         e_oor;

    // S_LOAD 采样的状态
    reg  [16:0] s_pool;
    reg  [16:0] s_pw0;
    reg  [16:0] s_pw1;
    reg  [15:0] s_q;
    reg         s_owner;
    reg  [16:0] s_occ;

    // S_CALC 结果
    reg  [16:0] s_pool_after;     // ev_up: pool + old ; rel: pool + q
    reg  [16:0] s_pw_after_ev;    // 事件端口 port_win 扣掉 old 后
    reg  [16:0] s_pw_after_own;   // 旧配额属主端口 port_win 扣掉 old 后
    reg  [16:0] s_avail;
    reg  [16:0] s_room;
    reg         s_sub_under;      // 本事件旧配额扣减发生下溢 (应恒 0)

    // 事件机 pop (S_LOAD 且 FIFO 非空)
    wire        do_pop   = (eng_state == S_LOAD) && (evq_cnt != 6'd0);
    wire [5:0]  room0    = EDEPTH_6 - evq_cnt + {5'b0, do_pop};
    wire        push_ok  = (push_cnt_6 <= room0);

    assign dbg_busy      = (eng_state != S_LOAD) || (evq_cnt != 6'd0);
    assign dbg_ev_commit = (eng_state == S_COMMIT);
    assign dbg_ev_type   = e_type;
    assign dbg_ev_slot   = e_slot;

    // 饱和扣减 (组合): pw > q ? pw-q : 0; 相等不算下溢
    function [16:0] sat_sub17;
        input [16:0] pw;
        input [15:0] q;
        begin
            if (pw > {1'b0, q}) sat_sub17 = pw - {1'b0, q};
            else                sat_sub17 = 17'd0;
        end
    endfunction

    // S_CALC 的并行前级 (全部来自 S_LOAD 锁存, 不碰 live 输入)
    wire [16:0] w_pool_add_q   = s_pool + {1'b0, s_q};
    wire [16:0] w_pw_ev_sub    = sat_sub17(e_port ? s_pw1 : s_pw0, s_q);
    wire [16:0] w_pw_own_sub   = sat_sub17(s_owner ? s_pw1 : s_pw0, s_q);
    wire [16:0] w_pw_after_ev  = (s_owner == e_port) ? w_pw_ev_sub
                                                      : (e_port ? s_pw1 : s_pw0);
    wire [16:0] w_pw_after_own = w_pw_own_sub;
    wire [16:0] w_avail        = (w_pool_add_q > s_occ) ? (w_pool_add_q - s_occ)
                                                         : 17'd0;
    wire [16:0] w_room         = (port_cap > w_pw_after_ev) ? (port_cap - w_pw_after_ev)
                                                            : 17'd0;
    wire        w_sub_under    = (s_q != 16'd0) &&
                                 ((s_owner ? s_pw1 : s_pw0) != {1'b0, s_q}) &&
                                 ((s_owner ? s_pw1 : s_pw0) <  {1'b0, s_q});

    // S_COMMIT 的授予量
    reg  [16:0] c_g;
    always @(*) begin
        c_g = {1'b0, wq_cap};
        if (s_avail < c_g) c_g = s_avail;
        if (s_room  < c_g) c_g = s_room;
    end

    integer i;

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
            stat_ev_ovf     <= 32'd0;
            for (i = 0; i < NSLOT; i = i + 1) winq[i] <= 16'd0;
            evq_wr    <= 5'd0;
            evq_rd    <= 5'd0;
            evq_cnt   <= 6'd0;
            eng_state <= S_LOAD;
            e_type    <= E_REL0;
            e_slot    <= 4'd0;
            e_port    <= 1'b0;
            e_oor     <= 1'b0;
            s_pool    <= 17'd0;
            s_pw0     <= 17'd0;
            s_pw1     <= 17'd0;
            s_q       <= 16'd0;
            s_owner   <= 1'b0;
            s_occ     <= 17'd0;
            s_pool_after   <= 17'd0;
            s_pw_after_ev  <= 17'd0;
            s_pw_after_own <= 17'd0;
            s_avail        <= 17'd0;
            s_room         <= 17'd0;
            s_sub_under    <= 1'b0;
            o_ev_up_done0 <= 1'b0; o_ev_up_done_slot0 <= 4'd0;
            o_ev_up_done1 <= 1'b0; o_ev_up_done_slot1 <= 4'd0;
            for (i = 0; i < EDEPTH; i = i + 1) evq[i] <= 6'd0;
        end else begin
            // 脉冲型输出每拍默认清零 (工程铁律)
            o_ev_up_done0 <= 1'b0;
            o_ev_up_done1 <= 1'b0;

            //-----------------------------------------------------------------
            // 事件 FIFO: push (多写) / pop (事件机 S_LOAD)
            //-----------------------------------------------------------------
            if (push_ok && (push_cnt != 3'd0) && (push_cnt_6 != 6'd0)) begin
                // 四条写口; 索引按已入队的条数偏移 (固定顺序)
                if (p_rel0) evq[evq_wr] <= {E_REL0,  rel_slot0};
                if (p_up0)  evq[evq_wr + {4'b0, p_rel0}] <= {E_EVUP0, ev_up_slot0};
                if (p_up1)  evq[evq_wr + {4'b0, p_rel0} + {4'b0, p_up0}]
                                <= {E_EVUP1, ev_up_slot1};
                if (p_rel1) evq[evq_wr + {4'b0, p_rel0} + {4'b0, p_up0} + {4'b0, p_up1}]
                                <= {E_REL1,  rel_slot1};
                evq_wr  <= evq_wr + {2'b0, push_cnt};
                evq_cnt <= evq_cnt + push_cnt_6 - {5'b0, do_pop};
            end else begin
                if (push_cnt != 3'd0) stat_ev_ovf <= stat_ev_ovf + push_cnt_6;
                evq_cnt <= evq_cnt - {5'b0, do_pop};
            end
            if (do_pop) evq_rd <= evq_rd + 5'd1;

            //-----------------------------------------------------------------
            // 事件机: S_LOAD -> S_CALC -> S_COMMIT -> S_LOAD
            //-----------------------------------------------------------------
            case (eng_state)
                S_LOAD: begin
                    if (evq_cnt != 6'd0) begin
                        e_type <= evq_head[5:4];
                        e_slot <= evq_head[3:0];
                        e_port <= evq_head[5];          // type[1] = 口
                        e_oor  <= (evq_head[3:0] >= 4'd8);
                        s_pool <= pool;
                        s_pw0  <= port_win0;
                        s_pw1  <= port_win1;
                        s_q    <= (evq_head[3:0] < 4'd8) ? winq[evq_head[3:0]]
                                                         : 16'd0;
                        s_owner<= (evq_head[3:0] < 4'd8) ? grant_port[evq_head[3:0]]
                                                         : 1'b0;
                        s_occ  <= evq_head[5] ? occ1 : occ0;
                        eng_state <= S_CALC;
                    end
                end

                S_CALC: begin
                    // 旧配额先回池 (C18) / rel 的归还, 两者都是 pool + q
                    s_pool_after   <= w_pool_add_q;
                    s_pw_after_ev  <= w_pw_after_ev;
                    s_pw_after_own <= w_pw_after_own;
                    s_avail        <= w_avail;
                    s_room         <= w_room;
                    s_sub_under    <= w_sub_under;
                    eng_state      <= S_COMMIT;
                end

                S_COMMIT: begin
                    if (e_oor) begin
                        // 槽号越界: 只计数, 状态逐项不变 (M-3)
                        stat_slot_oor <= stat_slot_oor + 32'd1;
                        if (e_type[0]) begin
                            if (e_port) begin
                                o_ev_up_done1      <= 1'b1;
                                o_ev_up_done_slot1 <= e_slot;
                            end else begin
                                o_ev_up_done0      <= 1'b1;
                                o_ev_up_done_slot0 <= e_slot;
                            end
                        end
                    end else if (!e_type[0]) begin
                        //========================= rel =========================
                        if (s_owner != e_port) begin
                            // 非属主口的迟到 rel: 忽略 (H-1)
                            stat_rel_stale_port <= stat_rel_stale_port + 32'd1;
                        end else if (s_q == 16'd0) begin
                            ;
                        end else begin
                            pool   <= s_pool + {1'b0, s_q};
                            if (e_port) port_win1 <= sat_sub17(s_pw1, s_q);
                            else        port_win0 <= sat_sub17(s_pw0, s_q);
                            winq[e_slot] <= 16'd0;
                        end
                        if (s_sub_under) stat_port_win_underflow <= stat_port_win_underflow + 32'd1;
                    end else begin
                        //======================== ev_up ========================
                        // g = min(wq_cap, avail, room) (c_g 在组合块算好)
                        pool <= s_pool_after - c_g;
                        winq[e_slot] <= c_g[15:0];
                        if (e_port) begin
                            port_win1 <= s_pw_after_ev + c_g;
                            if ((s_owner != 1'b1) && (s_q != 16'd0))
                                port_win0 <= s_pw_after_own;
                        end else begin
                            port_win0 <= s_pw_after_ev + c_g;
                            if ((s_owner != 1'b0) && (s_q != 16'd0))
                                port_win1 <= s_pw_after_own;
                        end
                        grant_port[e_slot] <= e_port;

                        if (c_g == 17'd0)
                            stat_grant_zero <= stat_grant_zero + 32'd1;
                        if (s_q != 16'd0) begin
                            stat_slot_reuse <= stat_slot_reuse + 32'd1;
                            if (s_owner != e_port)
                                stat_c18_cross_port <= stat_c18_cross_port + 32'd1;
                        end
                        if (s_sub_under)
                            stat_port_win_underflow <= stat_port_win_underflow + 32'd1;

                        // grant 已在本沿提交; 下一拍 done 高 + winq 可读
                        if (e_port) begin
                            o_ev_up_done1      <= 1'b1;
                            o_ev_up_done_slot1 <= e_slot;
                        end else begin
                            o_ev_up_done0      <= 1'b1;
                            o_ev_up_done_slot0 <= e_slot;
                        end
                    end
                    eng_state <= S_LOAD;
                end

                default: eng_state <= S_LOAD;
            endcase
        end
    end

endmodule
