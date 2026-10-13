`timescale 1ns/1ps
//=============================================================================
// mir_uram_fifo.v — 镜像 aux 口 ↔ C2H AXIS 成形器 之间的 **URAM 板内缓冲**
//=============================================================================
// 轮次: P9 追加轮 (URAM 板内缓冲; 设计件/报告 = `_proj_10g/notes/p9_uram_20261013/REPORT.md`)
//
// ---- 位置与"为什么是这个位置" (接口位置的选择理由) ----
//   接线点 = `board/wrapper_p4.v` 的 **M1/P9 真支** (APP_MODE ∧ PCIE_OBS ∧ DP_156MHZ):
//     u_mir (`app_rx_mirror`) 的 **aux 读口** ──(本模块)──> u_mir_axis (`axis_c2h_stream`) 的 aux 口
//   · 两个 aux 口的合同**一字未改**:
//       上游 (对镜像) = 旧合同逐字: 有空间才拉 `up_req`; 镜像同拍给 `up_gnt` + `up_data`
//                      (= 1 个 64 位字 = 2 个逻辑 32 位字 = 8 B);
//       下游 (对成形器) = **镜像当年的角色**: 成形器拉 `dn_req`, 本模块同拍给 `dn_gnt` +
//                      `dn_data` (FWFT 头字, 8 B) ⇒ 成形器一行未改.
//   · ⭐ **两侧同钟 (pcie_axi_aclk = 250 MHz) ⇒ 本模块不是 CDC 部件**:
//     数据面 dp_clk(156.25MHz) → pcie 域的跨域在 **u_mir 内部** (其 `u_fifo` = `fifo_async`
//     64b×256) 已经完成; aux 口及其消费者都在 **rd_clk = pcie_axi_aclk** (证据: wrapper 里
//     `u_mir` 的 `.rd_clk(pcie_axi_aclk)` 与 `u_mir_axis` 的 `.clk(pcie_axi_aclk)`).
//     ⇒ 设计基线里"写侧 dp_clk / 读侧 pcie ⇒ 自定义异步 FIFO (灰码指针)"描述的是 **u_mir
//     内部那条边界**; 本模块在它**之后** ⇒ **单时钟**、无灰码指针、无 CDC 风险 (登记为与
//     基线的偏离 + 理由, 见 REPORT §1.2)。⛔ 本模块**不引入任何新的时钟域或 CDC**。
//   · 换法 A (替换 `axis_c2h_stream` 内部暂存) **否决**: 成形器的"2 slot + 16 B 成形拍"是
//     G1–G12 逐拍判过的时序合同 (2 grant ⇒ 同拍进槽 ⇒ 攒 2 次成形), 而 URAM 读本就 ≥3 拍
//     ⇒ 要动它的 handshake 与时序语义 = 改动面/回归面大得多, 且 `dma_words` 计数点、
//     "clr 丢弃"、QUIET_N 排空全部要重判 (REPORT §1.2 有对照表)。
//
// ---- 容量与"吸收多久" ----
//   · 存储 = **1 个 URAM288** (4096 字 × 64 位 = **32 KB 载荷**; URAM288 本体 = 288 Kb = 36 KB,
//     其中 64/72 位当载荷, 其余位不用)。
//   · 另加下游弹性寄存器堆 `OQ` 字 + 读流水在飞 `LAT-1` 字 (都**不占** URAM 地址空间).
//   · 吸收时间: 32 KB ÷ 1.25 GB/s (镜像源上界 8 B/156.25 MHz) ≈ **25.6 µs**
//     (对照: 改前 = 镜像 FIFO 2 KB ⇒ ≈1.6 µs + 成形器 32 B) ⇒ **×16**。
//   · 拍数账: 4096 字 ÷ (1 字/拍 @250 MHz) = 4096 拍 = 16.4 µs; 按源速率 0.625 字/拍 = 6554 拍.
//
// ---- 数据通路 (单时钟; 全部寄存器在同一 always 块, 见"驱动纪律") ----
//   [镜像 aux 口] --up_gnt/up_data--> **URAM288** (xpm_memory_sdpram, ultra, READ_LATENCY_B=3)
//        --enb=issue / addrb=rp--> 读流水 3 级 --(v_sr[2] 有效)--> 弹性寄存器堆 OQ 深 (FWFT)
//        --dn_gnt/dn_data--> [成形器 aux 口]
//
// ---- 不变式 (设计级; 仿真里由本文件末尾的 FATAL 守卫 + 单元门 G 组双向监视) ----
//   ① **发出未弹走的总字数** `inv = o_occ + popcount(v_sr) ≤ CAP (= OQ)`;
//      写门 `up_req = rst_n && en && !clr && (occ < 2^AW)` —— 复位期/满时**不拉** ⇒ 上游不会给字 ⇒
//      **本模块不丢字** (丢字节仍只记在镜像 `W70`; 本模块**不新增任何丢字节计数器**)。
//      ⚠️ F2 修复 (2026-10-13 复核轮): 旧式 = `en && !clr && !ufull` **不含 `rst_n`** ——
//        复位窗内 `occ` 被清零 ⇒ `!ufull` 为真 ⇒ 会拉 req 并**收下**上游的字, 而 `wp` 被
//        复位钳住 ⇒ 该字"被取走却永不可读出" (静默丢字通道; 当时仅靠跨模块隐式不变量
//        `en`/`rst_n` 同复位域 + `mir_ctrl_r` 复位 0 闭合)。并入 `rst_n` 后该通道**结构性关闭**;
//        不变量的**登记**见写门处注释 (防"改一处静默打开")。
//   ② **到达安全**: 到达拍必有 `inflight ≥ 1` ⇒ `o_occ ≤ CAP-1 < OQ` ⇒ 弹性堆永不满 ⇒ 不覆盖。
//   ③ **存储回收点 = 读发起**(不是弹走): `rp` 在 issue 那拍推进 ⇒ URAM 地址在该拍即空出;
//      写地址与读发起地址在同一拍相撞只可能发生在 `occ == 0`(空) 或 `occ == 2^AW`(满),
//      而空时无 issue、满时 `up_req=0` 无写 ⇒ **结构性不相撞** (read_first 模式的安全性前提)。
//
// ---- clr (窗口边界 = 丢弃; 与 `axis_c2h_stream` D4 修正轮同口径) ----
//   · clr 拍: 指针/valid 链/弹性堆**全清** + **不拉 `up_req`** (⇒ 镜像那侧也不成交 ⇒
//     "clr 拍不取数"是**结构性的**, 不留"已取走既不计也不交付"的余数; 与成形器 `clr_drop` 同款)。
//   · ⭐ clr 拍 **dn 侧 = 不交付** (F3 修复, 2026-10-13 复核轮): `pop` 并入 `!clr` ⇒ clr 拍
//     `dn_gnt` **强制 0**。旧式 (`pop = dn_req && o_occ!=0`) 因 `o_occ` 到沿才清 ⇒ clr 拍会把
//     **上一窗口的头字**弹给下游 —— 那时"clr 拍不弹旧字"只由下游 (`axis_c2h_stream` 的
//     `!clr_drop` 关 req) 承担, 本模块自己的 clr 语义**不自足** (板级 D4 抓到的同族形态)。
//     口径封定 = "clr 拍全清 ⇒ 一个字都不进不出": 下游若在 clr 拍违约保持 `dn_req`, 只被
//     **忽略一拍** (FWFT 合同只削发行、不引入数据冒险, 方向安全), 下拍无数据自然继续 0。
//   · 在飞的读 (v_sr 里的 ≤3 字) 靠**清 valid 链**丢弃 (数据落在 ram_dout 上但 `v_sr[2]=0`
//     ⇒ 不算到达) ⇒ 不会有"上一窗口的尾巴漏进新窗口" (即板级 D4 抓到的那个形态)。
//   · 被 clr 丢掉的字**按定义丢弃、不计数** (与成形器丢 `b`+两槽、镜像丢 FIFO 内容同款登记)。
//
// ---- en (dma_en = MIR_CTRL[3]) ----
//   · `en=0` (停排空): **不拉 `up_req`** ⇒ 不从镜像取数 ⇒ 镜像 FIFO 保持原样 ⇒
//     `MIR_STATUS.level` / `MIR_DATA` (主机 BAR 读出口) 的**读侧语义一字不变** ✓。
//   · `en=1 ∧ cap_en=0` (停采集): 本模块**照常取数** —— 与成形器 `dma_req` 的门同款
//     (它也只门 `en`), 这正是"非 clr 停流期把镜像 FIFO 排空直到静置"所要求的 ✓。
//
// ---- 复位 ----
//   `rst_n` = **pcie_axi_aresetn** (与 `u_mir_axis` 同一条; 与 `axi_regs`/XDMA 的 AXIS 口同域).
//   ⚠️ 登记: `u_mir` 的 **rd 侧**用板级 `reset_n` (既存边界, wrapper 注释逐字"同钟不同复位域的
//      既存边界一字未变") ⇒ 本模块**沿用成形器那条** (本模块在功能上是成形器 aux 消费侧的延伸),
//      与既存边界同类、不加宽 (REPORT §5 有分析)。URAM 本体**不复位** (内容无关; 有效性由
//      `v_sr`/`o_occ` 记账保证 ⇒ 空态读出的旧值永远不会被当成字弹给下游)。
//
// ---- 时序 ----
//   全部寄存器 = 1 级 (指针/计数/valid 链/弹性堆); 组合面 = 3 个短加法器 (`occ`/`inflight`/`inv`)
//   + 一条 `inv` 比较 + 4:1 的 64 位 FWFT 读出 mux。**无乘法/无宽移位/无 case 大表**。
//   ⚠️ 新锥清单与"要定向查什么"见 REPORT §4 (构建后由 TL 定向查 `u_mir_buf` 族)。
//=============================================================================
module mir_uram_fifo #(
    // ---- 深度 = 2^AW 字 (64 位/字) ----
    //   ⚠️ `AW` 同时进 XPM 的 `ADDR_WIDTH_A/B` 与 `MEMORY_SIZE = 64 * 2^AW` ⇒ 改深度只改这里
    //      (但 `2^AW > 4096` 会落到**第二个 URAM**; 4096 恰 = 单个 URAM288 的整数深度)。
    parameter AW  = 12,
    // ---- XPM 读延迟 (URAM 下界 = 3; 本模块的 valid 延迟链固定 3 级 ⇒ 两处必须同步改) ----
    //   `LAT != 3` 在仿真里**响亮地死** (见文件末尾参数自检) —— 防"改了这里忘改 v_sr 深度"。
    parameter LAT = 3,
    // ---- 下游弹性寄存器堆深度 = "发出未弹走"的总字上限 CAP (2..7; 3 位计数) ----
    //   取值理由: CAP ≥ 2 才能"边弹边发"维持 1 字/拍 (稳态 = 1 在飞 + 1 在堆);
    //   CAP 越大越能吸收"下游节奏抖动", 但只会挤占**在飞**余量而不增容量 (容量在 URAM 里)。
    parameter OQ  = 4
)(
    // ---- 时钟/复位 (pcie_axi_aclk / pcie_axi_aresetn) ----
    input  wire        clk,
    input  wire        rst_n,
    // ---- 控制 ----
    input  wire        en,          // dma_en = MIR_CTRL[3] (0 = 不取数, 见头注释)
    input  wire        clr,         // 窗口边界脉冲 (= 镜像 `clr_pulse_rd`, 同钟直连)
    // ---- 上游: 镜像 aux 读口 (本模块 = 消费者; 逐字同旧合同) ----
    output wire        up_req,      // 有空间才拉 (满 ⇒ 不拉 ⇒ 镜像 FIFO 自然满 ⇒ W70 记账)
    input  wire        up_gnt,      // 1 拍: 本拍写入 1 个字 (8 B = 2 个逻辑字)
    input  wire [63:0] up_data,     // {后出的字, 先出的字}
    // ---- 下游: 成形器 aux 口 (本模块 = 生产端; 与镜像同款同拍 FWFT 合同) ----
    input  wire        dn_req,      // 成形器的 dma_req
    output wire        dn_gnt,      // 1 拍: 本拍弹出 1 个字 (8 B); 空态恒 0
    output wire [63:0] dn_data,     // 与 dn_gnt **同拍**有效 (= FWFT 头字)
    // ---- 观测 (纯线束; wrapper 里显式空接 —— 接进快照会改几何, 不在本刀范围) ----
    output wire [AW:0] dbg_occ,     // URAM 内"待发起读"的字数 (不含在飞/弹性堆)
    output wire [2:0]  dbg_oocc     // 弹性寄存器堆占用 (字)
);

`ifndef SYNTHESIS
    // 参数自检 (同 fifo_async 手法): 仿真里参数非法**响亮地死**, 不静默跑一个错配置。
    //   ⚠️ `LAT` 与 `v_sr` 的 3 级是**写死的耦合** ⇒ 改 LAT 必须同改 v_sr (本检查是那道防线)。
    initial begin
        if (LAT != 3 || OQ < 2 || OQ > 7 || AW < 4) begin
            $display("FATAL mir_uram_fifo: 参数非法 AW=%0d LAT=%0d OQ=%0d (要求 LAT==3 [valid 链固定 3 级], 2<=OQ<=7, AW>=4)",
                     AW, LAT, OQ);
            $finish;
        end
    end
`endif

    // ---------------- 线网声明先行 (xvlog 先声明后用; 防隐式 1 位网 —— 工程坑 24) ----------------
    //   弹性堆指针位宽 = OQ 的 clog2 (OQ=2 ⇒ 1 位, 3..4 ⇒ 2 位, 5..7 ⇒ 3 位) —— 必须先于下面的 reg 声明。
    //   ⚠️ F7 订正 (2026-10-13 复核轮): 本注释与 `op_w/op_r` 处旧注**都曾与代码不符且互相矛盾**
    //      (旧句一对写"2..4 ⇒ 1 位"、另一对写"2..4 ⇒ 2 位"; 代码判据 = `OQ<=2 ? 1 : (OQ<=4 ? 2 : 3)`)。
    localparam OW = (OQ <= 2) ? 1 : ((OQ <= 4) ? 2 : 3);
    reg  [AW:0]  wp;            // 写入字数 (含绕回位) —— 唯一驱动: 下面的单驱动块
    reg  [AW:0]  rp;            // **读发起**字数 (存储回收点 = 读发起, 见不变式 ③)
    reg  [2:0]   v_sr;          // 读发起 valid 延迟链: v_sr[2] = 本拍 `ram_dout` 携带有效字
    reg  [63:0]  o_mem [0:OQ-1];// 弹性寄存器堆 (FWFT; 单驱动块内按 op_w 写)
    reg  [OW-1:0] op_w, op_r;   // 弹性堆写/读指针 (位宽由 OQ 定: OQ=2 ⇒ 1 位, 3..4 ⇒ 2 位, 5..7 ⇒ 3 位)
    reg  [2:0]   o_occ;         // 弹性堆占用 0..OQ
    wire [63:0]  ram_dout;      // XPM 读出口 (3 拍延迟; 有效与否看 v_sr[2])

    localparam [3:0]  CAP  = OQ;                      // "发出未弹走"上限 (= 弹性堆深度)
    localparam [2:0]  OQ3  = OQ;                      // 3 位视图 (供与 o_occ 同宽比较; 禁参数位选)
    localparam [AW:0] UFULL= {1'b1, {AW{1'b0}}};      // occ 满值 = 2^AW

    // ---------------- 组合: 占用账 ----------------
    wire [AW:0] occ      = wp - rp;                                   // URAM 内待发起读的字数 0..2^AW
    wire        ufull    = (occ == UFULL);
    wire [2:0]  inflight = {2'd0, v_sr[0]} + {2'd0, v_sr[1]} + {2'd0, v_sr[2]};  // 已发起未到达
    wire [3:0]  inv      = {1'b0, o_occ} + {1'b0, inflight};          // 发出未弹走 = 弹性堆 + 在飞
    // 本拍弹走 1 字 (FWFT 头字)。`!clr` = **clr 拍不交付** —— F3 修复 (2026-10-13 复核轮):
    //   `o_occ` 到沿才清 ⇒ 不门 clr 时, clr 拍 `dn_gnt` 会带**上一窗口的头字**弹给下游
    //   (那时"clr 拍不弹旧字"只由下游 `axis_c2h_stream` 的 `!clr_drop` 承担 ⇒ 本模块的
    //   clr 语义不自足; 板级 D4 抓到的正是同族形态)。方向安全 = 只削发行、不引入数据冒险。
    wire        pop      = dn_req && (o_occ != 3'd0) && !clr;
    // 读发起 = ① URAM 里有已写未发起的字 ② 发出未弹走的账还有余量 ③ 不在 clr 拍
    //   ⚠️ ② 是本设计**唯一**防"到达覆盖弹性堆"的机制 (不变式 ②): 改成无条件发起 = 静默丢字。
    wire        issue    = (occ != {(AW+1){1'b0}}) && !clr;   // MUT(mut_issue_free)
    // 上游取数门: 有空间才拉 (且复位期**不取数**)。`!clr` = clr 拍不取数 (结构性; 见头注释 clr 段)。
    // ⭐ F2 修复 (2026-10-13 复核轮): 并入 `rst_n` —— 复位窗内 `occ` 被清零 ⇒ `!ufull` 为真 ⇒
    //   旧式会在复位期拉 req 并**收下**上游的字, 而 `wp` 被复位钳住 ⇒ 该字"被取走却永不可
    //   读出" (静默丢字通道; 三条 FATAL 守卫都不覆盖它)。并入后通道**结构性关闭**。
    // ⚠️ 不变量登记 (跨模块、隐式; 复核点名"改任何一处就静默打开"): 现役配置里 `en`
    //   (= mirror `mir_ctrl[3]`) 与 `en` 的载体 `axi_regs` 的复位都挂在**同一条**
    //   `pcie_axi_aresetn` 上, 且 `mir_ctrl_r` 复位值 = `32'd0` (来源 = board/wrapper_p4.v
    //   的 u_mir_buf 例化附近注释 + `_proj_pcie/rtl/axi_regs.v`) ⇒ 复位期 `en` 本也 = 0。
    //   `rst_n` 并门后本模块**不再依赖**这条不变量而安全; 但若改 `en` 的来源/复位域/复位值
    //   **或**改 wrapper 里本模块的例化接线 (尤其 `rst_n`/`en` 两条), 必须重推本段。
    assign      up_req   = rst_n && en && !clr && !ufull;
    wire        u_wr     = up_gnt && !clr;                            // 上游同拍成交 ⇒ 写入 (防御性再门 clr)
    wire        arr_v    = v_sr[2] && !clr;                           // 本拍 ram_dout 上是有效字
    assign      dn_gnt   = pop;
    assign      dn_data  = o_mem[op_r];
    assign      dbg_occ  = occ;
    assign      dbg_oocc = o_occ;

    // ---------------- 存储体: 1 个 URAM288 (XPM; 读延迟 3 — 与 v_sr 链同拍) ----------------
    // 为什么用 XPM_MEMORY 而**不是** `(* ram_style="ultra" *)`:
    //   · URAM 的读出**必须 ≥3 级流水** (本仓既有实测: `Synth 8-6793` "Minimum required
    //     pipeline stages = 3"); 只加 `ram_style` 会**被工具拒**或**静默落回 BRAM**
    //     (BRAM 已用 348/480 ⇒ 静默回退是"安静失效", 本工程最贵的一类)。
    //   · XPM 把"READ_LATENCY_B=3"写成**合同**: 综合按该合同展开 (同一份 `xpm_memory.sv`),
    //     xsim 用同一份行为模型 ⇒ **单元门测的就是要综合的那份源**。
    //   · ⚠️ 实测 (2026-10-13, xsim 行为模型): `enb=1` 那拍给出的地址, 数据恰在 **+3 拍**
    //     出现在 `doutb` (背靠背 1 字/拍; 空闲时 `doutb` **保持**旧值 ⇒ 靠 `v_sr` 判有效)。
    //     ⛔ 预编译 `-L xpm` 库在本机 **elaborate 失败** (`rstb_val is not constant`) ⇒
    //     门里必须**先把 `xpm_memory.sv` 以 `-sv` 编进本地 `xpm` 库** (见 sim/p9_uram 的 bat)。
    //   · `READ_FIRST`: 写读不同址是结构性保证的 (不变式 ③); UF/WF 之间选 RF 是为了不去
    //     依赖 write-first 的旁路时序 (READ_LATENCY_B=3 时两者 XPM 都收)。
    xpm_memory_sdpram #(
        .MEMORY_SIZE        (64 * (1 << AW)),      // 262144 bit = 4096 × 64
        .MEMORY_PRIMITIVE   ("ultra"),             // ⛔ 不用 "auto" (会让工具自己挑 BRAM)
        .CLOCKING_MODE      ("common_clock"),      // URAM 要求同钟 (XPM DRC 40-3)
        .ECC_MODE           ("no_ecc"),
        .WRITE_DATA_WIDTH_A (64),
        .BYTE_WRITE_WIDTH_A (64),
        .ADDR_WIDTH_A       (AW),
        .READ_DATA_WIDTH_B  (64),
        .READ_LATENCY_B     (LAT),                 // = 3 (URAM 下界)
        .WRITE_MODE_B       ("read_first"),        // URAM 的 SDP 只允许 RF/WF (XPM DRC 40-8)
        .ADDR_WIDTH_B       (AW),
        .READ_RESET_VALUE_B ("0"),
        .USE_MEM_INIT       (0),
        .MEMORY_INIT_FILE   ("none"),
        .SIM_ASSERT_CHK     (0),
        .RST_MODE_B         ("SYNC"),
        .CASCADE_HEIGHT     (0),
        .AUTO_SLEEP_TIME    (0),
        .WAKEUP_TIME        ("disable_sleep"),
        .MEMORY_OPTIMIZATION("true"),
        .USE_EMBEDDED_CONSTRAINT (0)
    ) u_ram (
        .clka   (clk), .ena (u_wr), .wea (u_wr), .addra (wp[AW-1:0]), .dina (up_data),
        .clkb   (clk), .enb (issue), .addrb (rp[AW-1:0]), .regceb (1'b1), .rstb (1'b0),
        .doutb  (ram_dout),
        .injectsbiterra (1'b0), .injectdbiterra (1'b0), .sleep (1'b0),
        .sbiterrb (), .dbiterrb ()                          // 显式空接 (no_ecc ⇒ 恒 0)
    );

    // ---------------- 全部寄存器: 一个单驱动块 (指针/valid 链/弹性堆/占用) ----------------
    //   ⚠️ 驱动纪律 (本工程坑): 每个寄存器**只有一个** always 块驱动它;
    //      `rst_n` 与 `clr` 都是"整块清零" (同款语义: 丢弃 + 记账归零), 优先级 = rst > clr > 正常。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wp <= {(AW+1){1'b0}};  rp <= {(AW+1){1'b0}};  v_sr <= 3'd0;
            op_w <= {OW{1'b0}};    op_r <= {OW{1'b0}};     o_occ <= 3'd0;
        end else if (clr) begin
            wp <= {(AW+1){1'b0}};  rp <= {(AW+1){1'b0}};  v_sr <= 3'd0;
            op_w <= {OW{1'b0}};    op_r <= {OW{1'b0}};     o_occ <= 3'd0;
        end else begin
            if (u_wr)  wp <= wp + {{AW{1'b0}}, 1'b1};
            if (issue) rp <= rp + {{AW{1'b0}}, 1'b1};
            v_sr <= {v_sr[1:0], issue};                    // 与 XPM 的 3 级读流水同拍
            if (arr_v) begin o_mem[op_w] <= ram_dout; op_w <= op_w + {{(OW-1){1'b0}}, 1'b1}; end
            if (pop)   op_r <= op_r + {{(OW-1){1'b0}}, 1'b1};
            o_occ <= o_occ + {2'd0, arr_v} - {2'd0, pop};
        end
    end

`ifndef SYNTHESIS
    // ---------------- 结构性守卫 (仿真专属; 违反 = 不变式被破坏 ⇒ 会**静默丢字**) ----------------
    //   ① 到达拍弹性堆已满  ② 满态还写 URAM (覆盖未读字)  ③ 上游违契 (无 req 也给 gnt)
    //   ⚠️ 只 `$display` 不 `$finish`: 让单元门继续跑完并打它自己的 [FAIL] (判决留给门)。
    //   ⭐ 有牙验证 (2026-10-13 复核轮补): 守卫③ 的"真会响"由单元门 arm `guard_rogue` 直接测
    //     (TB 违约驱动 `up_gnt=1` 而上游无 req ⇒ 必须命中本串; 其对照臂 = `mut_guard_off`
    //     删本 `$display` ⇒ 该 arm 必须**看不见**此串)。守卫①/② 的牙由 `mut_issue_free` /
    //     `mut_full_off` 两臂命中 (见 sim/p9_uram 的臂表)。
    always @(posedge clk) begin
        if (rst_n && !clr) begin
            if (arr_v && (o_occ == OQ3))
                $display("FATAL mir_uram_fifo: arrival into FULL elastic FIFO (t=%0t)", $time);
            if (u_wr && ufull)
                $display("FATAL mir_uram_fifo: URAM write while FULL (t=%0t)", $time);
            if (up_gnt && !up_req)
                $display("FATAL mir_uram_fifo: upstream grant without req (violates aux contract, t=%0t)", $time);
        end
    end
`endif

endmodule

//=============================================================================
// 变更登记 / 口径登记 (P9 追加轮, 2026-10-13; 设计件 = REPORT §1)
//   · 新文件, **不改任何既有 RTL 的对外合同**: `app_rx_mirror.v` / `axis_c2h_stream.v` 均 0 改动;
//     `board/wrapper_p4.v` 只做"把 3 根 aux 线改接到本模块 + 新增本模块例化" (最小 diff)。
//   · `MIR_DMA_CNT` **不由本模块计数** ⇒ 口径登记: 成形器数的是"从**本缓冲**取走的字数";
//     与本缓冲"从镜像取走的字数"之差 = 本缓冲占用 (`dbg_occ + dbg_oocc + 在飞`), 上界 **4100 字
//     (= 32800 B)** [⛔ 2026-10-13 订正 (验证 A-K1, 文本级): 原写"上界 4099 字 (= 32.8 KB)"
//     —— 低估 1 字 (8 B); 真上界 = DEPTH(4096) + CAP(=OQ=4) 且 „occ==4096 ∧ inv==4" 联合可达
//     (BFS 穷举 + 逐拍模型, 见 A 捆验证报告 §1) ⇒ **这句话错、单元门 G2b 的 [4096,4100] 本就是对的**;
//     本轮只改本注释, RTL 逻辑与 TB 判据均未动]。
//     静默/排空终态下两者相等 (成形器停流排空会一路拉到本模块空) ⇒ **两条工具
//     恒等式 (式 A / 式 B) 在"排空到 early-stop"的终态下逐字成立**; 中途评估的差额 = 缓冲占用
//     (≤32800 B; 式 B 的中途精化上界 = 32800 + 镜像 FIFO ≤2048 + acc/stg ≤24 ⇒ **≤34872 B**)
//     —— 见 REPORT §3 的逐条论证。
//   · 不新增丢字节计数器: 满 ⇒ 不拉 `up_req` ⇒ 丢字节仍只记 `W70` (镜像 `drop_bytes`)。
//   · 潜在后续 (本轮**未做**, 登记): ① 加 `AW=13` 用 2 个 URAM (64 KB); ② 深度实测读数
//     接快照 (会改窗口几何 ⇒ 不在本刀); ③ 若构建轮发现 XPM 未落 URAM (utilization 里
//     URAM 数 = 0), 先查 `MEMORY_PRIMITIVE` 是否被改写 —— **不许**退回 `ram_style`.
//=============================================================================
