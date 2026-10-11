`timescale 1ns/1ps
//=============================================================================
// axis_c2h_stream.v — P9: 镜像载荷 → XDMA **C2H AXI4-Stream** 的成形/搬运器
//=============================================================================
// 位置: 替代 P8 期 B 的三件套 (`mir_dma_ring` + `aximm_c2h_win` + `aximm_h2c_discard`)。
//   ⛔ **上游合同一字不改** —— 吃 `app_rx_mirror` 的 aux 读口:
//        `dma_req`(本模块→镜像, 电平) / `dma_gnt`(镜像→本模块, 同拍握手)
//        / `dma_data[63:0]` = **2 个逻辑 32 位字** (`[31:0]` = 先出的那个字);
//        空态不弹 / 主机弹出优先 (见 `rtl/app_rx_mirror.v` 头注释 + 单元门 G12a..k)。
//   下游 = XDMA 4.2 的 `s_axis_c2h_*` (128 位, 见 `xdma_st.sv` 生成件; 配置增量 = 1 行
//   `CONFIG.xdma_axi_intf_mm {AXI_Stream}`, 端口 75 → 50 根, 权威 = `p8_axis_conf_20261011/CONF.md` §3)。
//
// ---- 打包 (冻结口径) ----
//   · 一次 `dma_gnt` = 8 B (2 个逻辑字); 攒 **2 次 = 16 B = 1 个 128 位 AXIS 拍**。
//   · `tdata = {第 2 次 grant, 第 1 次 grant}` —— 即**先出的字落在低地址字节**
//     (`tdata[7:0]` = 流的第一个字节)。这与 `mir_dma_ring` 的行读口径**同代**
//     (环行 = `{mem3,mem2,mem1,mem0}` = 逻辑字 L 在 [31:0]) ⇒ 工具侧字节流语义不变。
//     ⚠️ **字节序的宿主侧落点 = 假设**: "XDMA 把 tdata 按小端写成宿主内存镜像" 未在本轮
//        EDN 证过 (PG195 不写字节序) ⇒ **板级首测必须逐字节对账**(失配形态 = 整拍内 8 B
//        交换, 一眼可辨)。登记为待验证项 (IMPL_REPORT 的"未定项")。
//   · `tkeep`: **非末拍恒 `16'hFFFF`** (PG195 v4.1 p.27 逐字: "The tkeep bits must be all 1s
//     except for the last data transfer of a packet")。末拍 (停流 flush, 只有半个 = 8 B):
//     **挤到 LSB** ⇒ `16'h00FF` (同页逐字: "The asserted tkeep bits need to be packed to the
//     lsb"); ⛔ 绝不用"全 0 的 keep + tlast" (同页: "If tlast is asserted and tkeep has all
//     zero's, this is not a valid combination")。
//   · `tlast` = **方案 A (恒 0 + 停流 flush 一拍)**: 正常全流 = **一个无限长包**
//     (宿主 `read(N)` 收满 N 字节即返回, 无短读)。唯一出 `tlast` 的时机 = **停流时把暂存
//     残拍成形那一拍** (关闭当前描述符; PG195 p.26–27: 描述符"填满 **或** 收到 EOP"都会
//     回写)。
//
// ---- ⭐ 停流 flush 的**具体触发式** (TL 2026-10-11 裁定; 逐字给出, 供工具侧对齐) ----
//        `stop = (!cap_en) || (!en) || clr`            ← **电平/脉冲的"或"**, 不是单一边沿
//        `mv_go(残拍成形)  = b_free && (mv_full || (stg_half && stop))`
//        `mv_last(末拍标记) = mv_full ? stop : 1'b1`
//   含义: ① `cap_en=0` (采集被关, MIR_CTRL[0], **电平**) 与 ② `clr` (镜像 rd 域脉冲)
//   是 TL 点名的两个停流事件; ③ `!en` (dma_en=0) 也一并算停流 (它本是"停排空" —— 少了
//   它, 宿主停排空时残拍会**无限期挂在暂存里**, 宿主的 `read()` 只能等驱动超时)。
//   ⛔ 三者**任一成立**即触发; `stop` 是电平 ⇒ "先停后到"的残拍也会立刻成形 (不会漏)。
//   ⚠️ `clr` 语义 (TL 裁定 ④): **不再丢弃残拍** —— clr 把残拍**作为短末拍送出去**
//   (因此 `packer 残留 == 0`, 账目式 `pc + ΔW70 + 残余 == K` 的残余项只剩镜像侧
//   `acc+stg ≤ 24 B`), 并且 **`clr` 使 `dma_words` 归零** (与镜像 `clr_pulse_rd` 对齐)。
//   ⚠️ 边界 (如实登记): 若 `clr` 发生在**流中途**, 该短末拍里是 **clr 之前的字节**
//   (≤16 B) ⇒ 宿主 post-clr 窗口的头部可能出现这一拍 (以 `tlast` 收尾)。协议上 clr
//   只在起测前写 (此时打包器空 ⇒ 无此拍); mid-capture clr 的工具侧处理见 IMPL_REPORT。
//   ⚠️ 边界: 若停流时**暂存全空**(最后一拍已整拍送出), 本模块**发不出空拍** (上面那条
//   tkeep≠全 0 的约束) ⇒ 最后一个未填满的描述符只能等驱动超时 (`c2h_timeout`)。不作承诺。
//   · **不加板内缓冲**: 暂存 = 2×8 B (槽) + 16 B (成形拍) ⇒ 突发容忍 ≈ 1 拍。这正是
//     **设计意图**: "宿主 read 之间的空档" 不被本模块吸收 ⇒ 镜像 FIFO 涨满 ⇒ 丢字节
//     **全部记在 `W70`**(`app_rx_mirror.drop_bytes`, dp 域寄存器输出)。⛔ **本模块不新增
//     任何丢字节计数器** (账目单一来源; 快照几何不扩)。
//     ⇒ 因果链: 宿主空档 → `tready` 低 → 本模块停止拉 `dma_req` → 镜像 FIFO 满 →
//       `admit` 失败 → `drop_bytes` 上涨。**"没读到" ≠ "没发生"**。
//
// ---- ⭐ `dma_words` / `MIR_DMA_CNT` 的口径 (TL 2026-10-11 裁定 ①; 冻结) ----
//   **计数点 = 上游 aux 口** —— 数**从镜像 aux 口取走 (`dma_gnt`) 的 32 位字数**
//   (一次 grant = 8 B = **+2**), **不是** `tvalid&&tready` 的下游字数。
//   理由 (TL 逐字): 本模块设计上**内部不丢** (无空间就不拉 `dma_req`) ⇒ "取走的字数"就是
//   "最终会交付的字数"; 且配合上面的 flush 规则, **暂存残留最终也会被送出去** ⇒
//   `packer 残留 == 0` ⇒ 账目单一来源。
//   `clr` ⇒ **归零** (与镜像 `clr_pulse_rd` 对齐 = "逻辑字 0 从这一刻起算")。
//
// ---- 时序/握手 ----
//   · `tvalid/tdata/tkeep/tlast` **全部寄存** (成形拍) ⇒ 天然满足 AXIS "tvalid 不依赖
//     tready、`tvalid&&!tready` 期间载荷稳定" (数据只在 `b_accept` 同拍被清)。
//   · `dma_req` 是**组合**量 (`en && 有容量`) ⇒ 与镜像的 `dma_gnt` 同拍成交; 无容量时
//     **不拉 req** (不丢字, 见上)。
//
// ---- 时钟/复位 ----
//   `clk/rst_n` = `pcie_axi_aclk` / `pcie_axi_aresetn` (与 `axi_regs`、XDMA AXIS 口同域)。
//   ⚠️ `cap_en`/`en`/`clr` 都来自**同钟** (pcie 域寄存器 / 镜像 rd 域脉冲) ⇒ 无 CDC。
//=============================================================================
module axis_c2h_stream (
    input  wire         clk,                // pcie_axi_aclk (250 MHz)
    input  wire         rst_n,              // pcie_axi_aresetn
    input  wire         en,                 // dma_en = MIR_CTRL[3]; 0 = 停排空 (+ 停流)
    input  wire         cap_en,             // ⭐ 采集使能 = MIR_CTRL[0]; 0 = 采集已关 (停流)
    input  wire         clr,                // 镜像 clr_pulse_rd: 停流(+flush) + 计数归零
    // ---- 上游: app_rx_mirror 的 aux 读口 (2 逻辑字 / 拍) ----
    output wire         dma_req,            // 电平: 有容量才拉 (无容量 ⇒ 让镜像 FIFO 满)
    input  wire         dma_gnt,            // 同拍握手 (镜像侧与 !empty/优先级合门)
    input  wire [63:0]  dma_data,           // {后出的字, 先出的字} (字 L 在 [31:0])
    // ---- 下游: XDMA C2H AXI4-Stream ----
    output wire [127:0] s_axis_c2h_tdata,
    output wire [15:0]  s_axis_c2h_tkeep,
    output wire         s_axis_c2h_tlast,
    output wire         s_axis_c2h_tvalid,
    input  wire         s_axis_c2h_tready,
    // ---- 观测 (→ MIR_DMA_CNT @0x148; 口径 = "从镜像 aux 口**取走**的 32 位字数") ----
    output reg  [31:0]  dma_words           // mod 2^32 自然回绕; clr 归零
);

    // ---------------- 线网声明先行 (xvlog 先声明后用; 防隐式 1 位网 —— 工程坑 24) ----------------
    reg  [63:0]  s0_data;      // 槽 0 = 本拍的**第 1 个** grant (8 B)
    reg  [63:0]  s1_data;      // 槽 1 = 本拍的**第 2 个** grant
    reg          s0_v, s1_v;
    reg  [127:0] b_data;       // 成形拍 (寄存)
    reg  [15:0]  b_keep;
    reg          b_last;
    reg          b_v;

    wire         b_accept;     // 成形拍本拍被下游收下
    wire         b_free;       // 本拍末成形拍可用
    wire         mv_full;      // 两槽齐 = 整拍
    wire         stg_half;     // 只有槽 0 = 半拍 (只在停流时成形)
    wire         stop;         // ⭐ 停流 (TL 裁定的触发式; 见头注释)
    wire         mv_go;        // 本拍成形 (槽 → 寄存拍)
    wire         gnt_go;       // 本拍 aux 成交 (写槽)
    wire         fill_s0;      // 新 grant 进槽 0 (否则进槽 1)
    wire [127:0] mv_data;
    wire [15:0]  mv_keep;
    wire         mv_last;

    // ---------------- ⭐ 停流触发式 (TL 2026-10-11 裁定; 逐字见头注释) ----------------
    //   `stop = (!cap_en) || (!en) || clr` —— 三者任一成立即视为"停流" ⇒ 残拍立刻成形
    //   (整拍则打 tlast)。⛔ 电平语义 (不是单一边沿): 保证"先停后到的残拍"也被收尾。
    assign stop = (!cap_en) || (!en) || clr;

    // ---------------- 成形条件 ----------------
    assign mv_full  = s0_v && s1_v;
    assign stg_half = s0_v && !s1_v;
    assign b_accept = b_v && s_axis_c2h_tready;
    assign b_free   = !b_v || b_accept;
    // 半拍**只在停流时**成形 (= flush 短末拍); 整拍随时可成形 (只要成形拍空)。
    assign mv_go    = b_free && (mv_full || (stg_half && stop));
    assign mv_data  = mv_full ? {s1_data, s0_data} : {64'd0, s0_data};
    assign mv_keep  = mv_full ? 16'hFFFF : 16'h00FF;
    // tlast: 半拍恒 1 (它只在停流时成形); 整拍 = 成形那一拍的 `stop` 采样
    //   (= "这一拍就发生在停流期间" ⇒ 它是本轮收尾拍)。⚠️ 用**成形同拍**采样, 之后
    //   `b_last` 是寄存器 ⇒ 呈现期间恒定 (满足 AXIS 载荷稳定合同)。
    assign mv_last  = 1'b0;   // MUT(mut_last): never tlast

    // ---------------- 请求 (有容量才拉; 无容量 ⇒ 让镜像 FIFO 满 ⇒ W70 记账) ----------------
    //   容量 = 有空槽 或 本拍正在成形 (成形把两槽同时清空 ⇒ 新字进槽 0)。
    //   `en` = 0 时**不拉**: 旧数据留在镜像 FIFO (槽里的残拍按上面的 stop 规则送出去)。
    assign dma_req  = en && (!s0_v || !s1_v || mv_go);
    assign gnt_go   = dma_req && dma_gnt;
    assign fill_s0  = (!s0_v) || mv_go;

    // ---------------- 成形拍寄存器 (tvalid/data/keep/last 全寄存) ----------------
    //   ⚠️ `clr` **不清它** (TL 裁定 ④): clr 只归零计数, 残拍照常送出; 已成形未握手的
    //      拍也照常等握手 (由上游 flush 语义收尾)。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            b_v <= 1'b0; b_data <= 128'd0; b_keep <= 16'd0; b_last <= 1'b0;
        end else if (mv_go) begin
            b_v <= 1'b1; b_data <= mv_data; b_keep <= mv_keep; b_last <= mv_last;
        end else if (b_accept) begin
            b_v <= 1'b0;
        end
    end

    // ---------------- 暂存槽 (2 × 8 B) ----------------
    //   ⚠️ `clr` **不清它** (残拍要送出去, 见上)。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s0_v <= 1'b0; s1_v <= 1'b0; s0_data <= 64'd0; s1_data <= 64'd0;
        end else begin
            // 先"成形清空", 再"新 grant 落槽" —— 同一 always 块内后写生效 (成形同拍进槽 0)
            if (mv_go) begin
                s0_v <= 1'b0; s1_v <= 1'b0;
            end
            if (gnt_go) begin
                if (fill_s0) begin s0_data <= dma_data; s0_v <= 1'b1; end
                else         begin s1_data <= dma_data; s1_v <= 1'b1; end
            end
        end
    end

    // ---------------- ⭐ 取走字数 (→ MIR_DMA_CNT; TL 裁定: 计数点 = 上游 aux 口) ----------------
    //   一次 `dma_gnt` = 8 B = **+2 个 32 位字**; `clr` ⇒ 归零 ("逻辑字 0" 从此刻起算)。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)          dma_words <= 32'd0;
        else if (clr)        dma_words <= 32'd0;
        else if (gnt_go)     dma_words <= dma_words + 32'd2;
    end

    // ---------------- AXIS 输出 (全部寄存器; 见头注释"时序/握手") ----------------
    assign s_axis_c2h_tvalid = b_v;
    assign s_axis_c2h_tdata  = b_data;
    assign s_axis_c2h_tkeep  = b_keep;
    assign s_axis_c2h_tlast  = b_last;

endmodule
