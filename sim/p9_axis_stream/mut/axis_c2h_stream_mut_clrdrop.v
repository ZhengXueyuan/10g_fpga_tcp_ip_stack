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
//   · `tlast` = **方案 A (恒 0 + 停流收尾一拍)**: 正常全流 = **一个无限长包**
//     (宿主 `read(N)` 收满 N 字节即返回, 无短读)。**唯一出 `tlast` 的时机只有一处**
//     (⭐ 2026-10-11 **D4 板级修正轮**; 逐字触发式见下"停流收尾"块):
//       **非 `clr` 停流 ⇒ 静置排空后把最后半拍作唯一一拍短拍** (流尾的自然"数据结束");
//     **其余一律 0** —— 含停流排空期间成形的**整拍** (正常拍) 与**正常采集期** (无短拍)。
//     ⛔ `clr` **不出任何拍** (它是窗口边界 ⇒ **丢弃**残留, 见下) —— 旧口径"clr 立即送残拍"
//     已被板级实测推翻 (件名与后果链见下 clr 块)。
//     (关闭当前描述符; PG195 p.26–27: 描述符"填满 **或** 收到 EOP"都会回写)。
//
// ---- ⭐ 停流收尾的**具体触发式** (TL 2026-10-11 裁定 ①; **D4 板级修正轮**改口径) ----
//        `stop = (!cap_en) || (!en)`                          ← 非 clr 停流 (电平; ⛔ 不含 clr)
//        `drain_wait = stop && (dma_req || !en)`               ← 停流期"还想要下一字"
//        `qcnt: 连续几拍 drain_wait 且零成交` (grant 或 drain_wait 撤销 ⇒ 归零)
//        `quiet = (qcnt == QUIET_N)`   (`QUIET_N = 32`; 取值理由见下)
//        `mv_go(一拍成形)  = b_free && (mv_full || (stg_half && stop && quiet))`
//        `mv_last(末拍标记) = mv_full ? 1'b0 : 1'b1`   (整拍恒 0; 只有收尾短拍 1)
//   含义: ① `cap_en=0` (采集被关, MIR_CTRL[0], **电平**) 与 ② `!en` (dma_en=0, "停排空";
//   少了它, 宿主停排空时残拍会**无限期挂在暂存里**, 宿主的 `read()` 只能等驱动超时)
//   是两个停流事件; ⛔ `clr` **不算停流** (D4 板级修正轮: 它改为"丢弃", 见下 clr 块)。
//   ⛔ `stop` 是**电平** ⇒ "先停后到"的残拍也会被收尾 (不会漏)。
//   ⭐ **停流 ≠ 立即碎片化 (D4 修正轮, 本块的主改动)**: `stop` 只是"允许收尾", **不是**
//   "立即收尾" —— 非 clr 停流期**继续按满 16 B 打包**把镜像 FIFO 排空 (2 次 grant ⇒
//   1 个整拍, 整拍**不打 `tlast`**); 只有当"**排空完成** (连续 `QUIET_N` 拍 `drain_wait`
//   且零成交) + 打包器里还留着半个拍"才把它作**唯一一拍短拍**送出去 (打 `tlast`)。
//   核心理由 = **一个停流事件只允许产生一个包尾**: 旧式"见 stop 就把半拍成形"会让停流
//   期**每个取走单位各自成一拍 8 B 的 `tlast` 包** (镜像 FIFO 残余最多 ~2 KB ⇒ 最多
//   ~256 个极小 EOP 包), 而引擎/驱动对"一串 8 B 完成记录"的行为**未证** (登记:
//   IMPL_REPORT §8.5) ⇒ 改成"排空 + 一次收尾"。
//   ⛔ nested/重复的 `stop` **不会重复发**: 收尾拍一成形就清空两槽, 新残留必须先有**新
//   grant** ⇒ 同一个停流事件内没有第二拍可发 (重复断言 `stop` 也不改变这一点)。
//   ⚠️ `QUIET_N = 32` 的取值理由: aux 口是**同拍组合成交** (镜像 FIFO 非空且主机没弹出
//   就成交) ⇒ "拉了 req 却连续 32 拍无成交"在合同内只可能是**源已空**; 而"最后一字还在
//   路上"的最长延迟 = cap_en 的 2FF 同步 (~3 拍) + 镜像弹性暂存尾字落 FIFO + FIFO 指针
//   2FF 回来 (~3 拍) ≈ ≤ 8 拍 ⇒ 32 留 ≥4x 余量; 代价 = 收尾延迟 32×4 ns = 128 ns
//   (对宿主 ms 级节奏不可见)。⛔ 只有"连续"才算 —— 任一 grant 都归零 (排空期每拍都可能
//   有 grant, 计数器根本涨不上去)。
//   ⚠️ `clr` 语义 = **窗口边界 ⇒ 丢弃** (⭐ **D4 板级修正轮**, 取代旧"clr 立即送残拍"):
//   板级原始件 = `_proj_10g/notes/p9_board_0x22_20261011/runs/D4_BOUNDARY.txt` —— 旧实现
//   (clr 把残拍作短拍送出) 在 `clr → cap_en=1` 起测瞬间冒一拍 **8 B 短拍 (`tlast=1`)** ⇒
//   **EOP 早关描述符** ⇒ 宿主首块 `[8,4096)` 全零 + 尾部截断 8,176 B + 第二次 read 超时 10 s
//   (内容本身无损: 偏移 ≥4096 处 0 失配)。⇒ clr 改为**丢弃**:
//     · 清 `b` (已成形未交付的拍) + 清两槽 —— 残留属"上一窗口的尾巴", 发出去会在**新窗口
//       头部挖洞/掺旧字节** (正是板级抓到的形态);
//     · `clr` 拍**不拉 `dma_req`** ⇒ clr 拍不取走任何字 (不留"已取走既不计也不交付"的余数);
//     · `dma_words` 归零 (与镜像 `clr_pulse_rd` 对齐 = "逻辑字 0 从这一刻起算")。
//   ⇒ **post-clr 窗口头部 = 0 B pre-clr 字节** (旧口径的"≤16 B / ≤40 B"界随之作废)。
//   依据 = clr 语义上就是窗口边界: 镜像侧 clr 也丢弃 FIFO 里 ≤2 KB 内容 + `acc/stg` (≤24 B);
//   本模块丢弃的在飞 ≤32 B (见下"不加板内缓冲")同款 = "按定义丢弃、不计 `W70`" (登记口径)。
//   ⚠️ 与 AXIS 合同的偏差 (如实登记): 若 clr 落在"一拍已呈现、下游还没收"的时刻, 本模块
//   会**无握手地撤销 `tvalid`** (窗口边界 = 软复位式事件) —— C2H 引擎按"该拍从未发生"处理
//   (无半拍传递, 不损坏引擎状态); 上一窗口未闭的描述符则回到既有的"等驱动超时"边界 (下条)。
//   ⚠️ 边界: 若停流时**打包器全空** (最后一拍已整拍送出、无半拍残留), 本模块**发不出
//   空拍** (上面那条 tkeep≠全 0 的约束) ⇒ 最后一个未填满的描述符只能等驱动超时
//   (`c2h_timeout`)。不作承诺 (排空期**整拍**也不打 `tlast` —— 收尾只由残拍短拍承担;
//   clr 亦不关描述符 ⇒ 窗口边界处未满的描述符同样落回本边界)。
//   · **不加板内缓冲**: 暂存 = 2×8 B (槽) + 16 B (成形拍) ⇒ 突发容忍 ≈ 1 拍。这正是
//     **设计意图**: "宿主 read 之间的空档" 不被本模块吸收 ⇒ 镜像 FIFO 涨满 ⇒ 丢字节
//     **全部记在 `W70`**(`app_rx_mirror.drop_bytes`, dp 域寄存器输出)。⛔ **本模块不新增
//     任何丢字节计数器** (账目单一来源; 快照几何不扩)。
//     ⇒ 因果链: 宿主空档 → `tready` 低 → 本模块停止拉 `dma_req` → 镜像 FIFO 满 →
//       `admit` 失败 → `drop_bytes` 上涨。**"没读到" ≠ "没发生"**。
//     ⭐ **在飞 (已取走未交付) 上界 = 32 B** (D5 核实, 现读 RTL): `b_data` = 128 位
//     (= 16 B) + `s0_data`/`s1_data` 各 64 位 (= 2×8 B) —— 全模块**只有这三份载荷
//     寄存器** (其余都是计数器/指针) ⇒ 在飞 ≤ 16+8+8 = 32 B; 且"两槽满 + `b` 满"
//     可达 (tready 慢时) ⇒ 32 是紧界。工具侧 `--resid-max-shaper` 默认 32 = 按本上界设。
//
// ---- ⭐ `dma_words` / `MIR_DMA_CNT` 的口径 (TL 2026-10-11 裁定 ①; 冻结) ----
//   **计数点 = 上游 aux 口** —— 数**从镜像 aux 口取走 (`dma_gnt`) 的 32 位字数**
//   (一次 grant = 8 B = **+2**), **不是** `tvalid&&tready` 的下游字数。
//   理由 (TL 逐字): 本模块设计上**内部不丢** (无空间就不拉 `dma_req`) ⇒ "取走的字数"就是
//   "最终会交付的字数"; 且配合上面的收尾规则 (**停流静置排空一次** / "残拍并入下一个整拍" /
//   **clr 边界丢弃**) 三条路径, 每一拍的去向都可枚举 ⇒ 稳态 `packer 残留 == 0` ⇒ 账目单一来源。
//   `clr` ⇒ **归零** (与镜像 `clr_pulse_rd` 对齐 = "逻辑字 0 从这一刻起算")。
//   ⚠️ 两个**已登记**的边界偏差 (不是静默丢): ① **clr 边界丢弃** (本模块 ≤32 B + 镜像侧
//   ≤2 KB/24 B, 窗口边界定义, 既不计也不交付; ⭐ D4 板级修正轮后 clr 拍已不取数 ⇒ 无
//   "未计数取走"); ② `rst_n` 清空一切 (计数与在飞同时归零)。
//   ⇒ 工具侧闭合式必须按"计数点 = aux 取走"写 (残余带 `[0,32]` B), **不是**
//   `tvalid&&tready` 握手口径 —— 两口径的**速率巧合相同**, 但**计数时刻**不同。
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
    input  wire         clr,                // 镜像 clr_pulse_rd: **窗口边界 = 丢弃残拍** + 计数归零
                                            //   (⭐ D4 板级修正轮: 旧"停流收尾送残拍"已废; 见头注释)
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
    wire         stg_half;     // 只有槽 0 = 半拍 (只在停流**收尾**时成形)
    wire         stop;         // ⭐ 停流 (TL 裁定的触发式; 见头注释)
    wire         mv_go;        // 本拍成形 (槽 → 寄存拍)
    wire         gnt_go;       // 本拍 aux 成交 (写槽)
    wire         fill_s0;      // 新 grant 进槽 0 (否则进槽 1)
    wire [127:0] mv_data;
    wire [15:0]  mv_keep;
    wire         mv_last;

    // ---------------- ⭐ 停流触发式 (TL 2026-10-11 裁定 ①; D4 板级修正轮改口径) ----------------
    //   `stop = (!cap_en) || (!en)` —— 非 clr 停流 (= **允许收尾**; ⛔ 不含 `clr`)。
    //   ⛔ 电平语义 (不是单一边沿): 保证"先停后到的残拍"也被收尾 (不会漏)。
    //   ⭐ `stop` ≠ "立即收尾" (D4 修正轮): 非 clr 停流要等**静置排空** ⇒ 见下。
    //   ⭐ `clr` **不在** stop 里 (D4 板级修正轮): clr 改为"**丢弃**"(见下 clr_drop)。
    assign stop = (!cap_en) || (!en);

    // ---------------- ⭐ clr = 窗口边界 ⇒ **丢弃** (D4 板级修正轮; 单点 alias 供突变臂) ----------------
    //   板级证据 (EOP 早关描述符 ⇒ 洞/零填充/超时) 与理由见头注释; 三处用法:
    //   ① b 块清残拍 ② 槽块清两槽 ③ `dma_req` 门 (clr 拍不取数)。
    wire clr_drop = 1'b0;   // MUT(mut_clrdrop): clr no longer discards residue

    // ---------------- ⭐ 静置排空检测 (D4 修正轮裁定 ②; 触发式/取值理由见头注释) ----------------
    //   `drain_wait` = 停流期"我们还想要下一字" (拉了 req 而没成交; 或 en=0 无从拉 req)。
    //   `qcnt` = 连续多少拍 `drain_wait` 且**零成交**; 满 `QUIET_N` ⇒ `quiet` (排空完成)。
    //   任一 grant 或 `drain_wait` 撤销 ⇒ 归零 (⛔ 只有**连续**无成交才算"源已空")。
    localparam [5:0] QUIET_N = 6'd32;
    wire       drain_wait = stop && (dma_req || !en);
    reg  [5:0] qcnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)               qcnt <= 6'd0;
        else if (!drain_wait)     qcnt <= 6'd0;
        else if (gnt_go)          qcnt <= 6'd0;
        else if (qcnt != QUIET_N) qcnt <= qcnt + 6'd1;
    end
    wire quiet = (qcnt == QUIET_N);

    // ---------------- 成形条件 ----------------
    assign mv_full  = s0_v && s1_v;
    assign stg_half = s0_v && !s1_v;
    assign b_accept = b_v && s_axis_c2h_tready;
    assign b_free   = !b_v || b_accept;
    // 半拍**只在"停流 + 静置排空完成"**时成形 (= 唯一收尾短拍); 整拍随时可成形。
    assign mv_go    = b_free && (mv_full || (stg_half && stop && quiet));
    assign mv_data  = mv_full ? {s1_data, s0_data} : {64'd0, s0_data};
    assign mv_keep  = mv_full ? 16'hFFFF : 16'h00FF;
    // tlast (D4 板级修正轮 —— "唯一出 tlast 的时机"只有一处): **半拍恒 1** (半拍只可能是
    //   停流收尾拍); 整拍**恒 0** (正常拍/排空期成形的整拍都不关描述符; clr 不再出拍)。
    //   ⚠️ 用**成形同拍**采样, 之后 `b_last` 是寄存器 ⇒ 呈现期间恒定 (AXIS 载荷稳定合同)。
    assign mv_last  = mv_full ? 1'b0 : 1'b1;

    // ---------------- 请求 (有容量才拉; 无容量 ⇒ 让镜像 FIFO 满 ⇒ W70 记账) ----------------
    //   容量 = 有空槽 或 本拍正在成形 (成形把两槽同时清空 ⇒ 新字进槽 0)。
    //   `en` = 0 时**不拉**: 旧数据留在镜像 FIFO (槽里的残拍按上面的停流收尾规则送出去)。
    //   ⭐ `clr` 拍**不拉** (D4 板级修正轮): 窗口边界不取数 ⇒ 不留"已取走既不计也不交付"的余数。
    assign dma_req  = en && !clr_drop && (!s0_v || !s1_v || mv_go);
    assign gnt_go   = dma_req && dma_gnt;
    assign fill_s0  = (!s0_v) || mv_go;

    // ---------------- 成形拍寄存器 (tvalid/data/keep/last 全寄存) ----------------
    //   ⭐ `clr` **清它** (D4 板级修正轮; 优先级最高): 窗口边界 ⇒ 已成形未交付的拍也丢弃。
    //      代价 = 无握手撤销 `tvalid` (软复位式边界; 见头注释"与 AXIS 合同的偏差"登记)。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            b_v <= 1'b0; b_data <= 128'd0; b_keep <= 16'd0; b_last <= 1'b0;
        end else if (clr_drop) begin
            b_v <= 1'b0;                       // 丢弃残拍 (clr 拍不拉 req ⇒ 也不会有新拍进 b)
        end else if (mv_go) begin
            b_v <= 1'b1; b_data <= mv_data; b_keep <= mv_keep; b_last <= mv_last;
        end else if (b_accept) begin
            b_v <= 1'b0;
        end
    end

    // ---------------- 暂存槽 (2 × 8 B) ----------------
    //   ⭐ `clr` **清两槽** (D4 板级修正轮: 窗口边界 ⇒ 丢弃残拍)。clr 拍不拉 req ⇒ 无 grant
    //      竞争 (旧"成形清空 + 新 grant 落槽"的两步只在非 clr 拍发生)。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s0_v <= 1'b0; s1_v <= 1'b0; s0_data <= 64'd0; s1_data <= 64'd0;
        end else if (clr_drop) begin
            s0_v <= 1'b0; s1_v <= 1'b0;        // 只清 valid (data 由 valid 门控, 不必清)
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

    // ---------------- ⭐ tdata → 宿主字节序的**唯一映射点** (板级首测用具; 只翻这一行) ----------------
    //   现状 = **恒等**: `b_data` 已按 {第 2 grant, 第 1 grant} 打包 ⇒ `tdata[7:0]` = 流首字节,
    //   与镜像 aux 口 / 环 / 工具三处口径一致 (见头注释"打包")。
    //   ⚠️ 唯一未证环 = "XDMA 把 `tdata` 按小端写进宿主内存镜像" (PG195 不写字节序) ⇒
    //   板级首测若报"整段一致的确定性错排", **只改下面这一行 assign 的 RHS**。候选 (按下行
    //   替换): (a) 8 B 半交换 `{b_data[63:0], b_data[127:64]}`; (b) 16 B 整拍反序;
    //   (c) 4 B 字序反序 —— 三者在"首字节失配+mism≈100%"上不可分, 判别协议 = 取落盘
    //   前 16 B 与图案的三个候选变换对照 (REVIEW §7-3; ⛔ 别只按一种先验查)。
    wire [127:0] c2h_tdata_map;
    assign c2h_tdata_map = b_data;             // ← ⭐ 唯一映射点 (恒等; "一行翻转"就改本行 RHS)

    // ---------------- AXIS 输出 (全部寄存器; 见头注释"时序/握手") ----------------
    assign s_axis_c2h_tvalid = b_v;
    assign s_axis_c2h_tdata  = c2h_tdata_map;
    assign s_axis_c2h_tkeep  = b_keep;
    assign s_axis_c2h_tlast  = b_last;

endmodule
