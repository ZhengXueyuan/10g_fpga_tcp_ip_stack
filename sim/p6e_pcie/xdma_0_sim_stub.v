`timescale 1ns/1ps
//=============================================================================
// xdma_0_sim_stub.v — **仅仿真用**的 xdma_0 替身 (模块名故意就叫 xdma_0)
//=============================================================================
// 为什么需要: P6e 合体把 XDMA IP 例化进了 wrapper, 而 IP 的功能模型只在 Vivado 工程里
//   生成 (且带加密/黑盒) ⇒ 在工程 TB 目录里没法 xelab 一个例化了真 IP 的 wrapper。
//   工程坑 8 要求"每个 ifdef 构建配置都有一个例化**真 wrapper** 的全链门" ⇒ 必须有替身。
//
// 替身做什么:
//   · 产生 axi_aclk (250MHz) / axi_aresetn / user_lnk_up / msi_*, 让 wrapper 跑起来;
//   · 实现一个最小 **AXI4-Lite 主机**, 用两个**层次任务**暴露给 TB:
//         u_dut.u_pcie_xdma.axil_read (addr, data);
//         u_dut.u_pcie_xdma.axil_write(addr, data);
//     用任务而不是端口, 是因为 TB 只能层次**读**子模块端口, 不能对 input wire 做过程赋值
//     (要驱动就得 force, 那才容易踩 TB 竞争坑)。
//   ⚠️ 端口名/位宽与真 IP **逐字一致** (来源: `_proj_10g/notes/p8_axis_conf_20261011/
//      work/evidence/xdma_st.sv` 的 `module xdma_st (...)` 端口清单 —— **P9 (2026-10-11)
//      AXI4-Stream 版, 50 根**) —— 名字对不上 wrapper 就连不上, 而"连不上"正是本门要抓的
//      那类错, 所以不能靠猜。
//   ⚠️ 本文件**只给仿真**, 绝不能出现在构建的文件清单里 (构建用真 IP)。
//
// ⭐ P9 (2026-10-11) 重写: 接口从 **m_axi (AXI4-MM, 35 根)** 换成 **AXIS (10 根)**。
//   从"TB 主动发 AR/AW 事务"反过来: **C2H 是 DUT → 替身** (替身 = 消费者), 所以替身做:
//     · C2H: 按 `str_tready_r` 收拍 (可被 TB 用它造**背压**), 逐拍记进数组 + 计数器;
//     · H2C: 由 `h2c_valid_r` 造 tvalid; 数"被吞噬"的拍 (见证 wrapper 的恒 tready=1);
//   ⚠️ 全部等待有界 (TB 侧的 `axis_wait_beats` 超时置 `str_to=1` ⇒ 响红, 不许挂死)。
//=============================================================================
module xdma_0 (
    input  wire        sys_clk,
    input  wire        sys_clk_gt,
    input  wire        sys_rst_n,
    output wire [3:0]  pci_exp_txp,
    output wire [3:0]  pci_exp_txn,
    input  wire [3:0]  pci_exp_rxp,
    input  wire [3:0]  pci_exp_rxn,
    output wire        user_lnk_up,
    output wire        axi_aclk,
    output wire        axi_aresetn,
    input  wire [0:0]  usr_irq_req,
    output wire [0:0]  usr_irq_ack,
    output wire        msi_enable,
    output wire [2:0]  msi_vector_width,
    // ---- C2H AXI4-Stream (⭐ P9: DUT → 替身; 替身 = 消费者, 用 str_tready_r 造背压) ----
    input  wire [127:0] s_axis_c2h_tdata_0,
    input  wire         s_axis_c2h_tlast_0,
    input  wire         s_axis_c2h_tvalid_0,
    output wire         s_axis_c2h_tready_0,
    input  wire [15:0]  s_axis_c2h_tkeep_0,
    // ---- H2C AXI4-Stream (⭐ P9: 替身 → DUT; wrapper 恒 tready=1 吞噬) ----
    output wire [127:0] m_axis_h2c_tdata_0,
    output wire         m_axis_h2c_tlast_0,
    output wire         m_axis_h2c_tvalid_0,
    input  wire         m_axis_h2c_tready_0,
    output wire [15:0]  m_axis_h2c_tkeep_0,
    // ---- user BAR (AXI4-Lite master) ----
    output wire [31:0] m_axil_awaddr,
    output wire [2:0]  m_axil_awprot,
    output wire        m_axil_awvalid,
    input  wire        m_axil_awready,
    output wire [31:0] m_axil_wdata,
    output wire [3:0]  m_axil_wstrb,
    output wire        m_axil_wvalid,
    input  wire        m_axil_wready,
    input  wire        m_axil_bvalid,
    input  wire [1:0]  m_axil_bresp,
    output wire        m_axil_bready,
    output wire [31:0] m_axil_araddr,
    output wire [2:0]  m_axil_arprot,
    output wire        m_axil_arvalid,
    input  wire        m_axil_arready,
    input  wire [31:0] m_axil_rdata,
    input  wire [1:0]  m_axil_rresp,
    input  wire        m_axil_rvalid,
    output wire        m_axil_rready,
    // ---- cfg mgmt (不实现) ----
    input  wire [18:0] cfg_mgmt_addr,
    input  wire        cfg_mgmt_write,
    input  wire [31:0] cfg_mgmt_write_data,
    input  wire [3:0]  cfg_mgmt_byte_enable,
    input  wire        cfg_mgmt_read,
    output wire [31:0] cfg_mgmt_read_data,
    output wire        cfg_mgmt_read_write_done
);

    // ---------------- 时钟: 真实板上是链路速率定的; 最小版实测 ≈250MHz (Gen2 x4) ----------------
    reg aclk = 1'b0;
    always #2 aclk = ~aclk;                 // 250 MHz
    assign axi_aclk = aclk;

    // ---------------- 复位/链路: sys_rst_n 落 ⇒ 复位; 释放后等一段再报 link up ----------------
    reg [11:0] rst_cnt = 12'd0;
    reg        aresetn_r = 1'b0;
    reg        lnk_r     = 1'b0;
    always @(posedge aclk) begin
        if (!sys_rst_n) begin
            rst_cnt <= 12'd0; aresetn_r <= 1'b0; lnk_r <= 1'b0;
        end else begin
            if (rst_cnt != 12'hFFF) rst_cnt <= rst_cnt + 12'd1;
            aresetn_r <= (rst_cnt >= 12'd16);      // 复位后 16 拍释放 (够 snap_cdc 的同步器跑完)
            lnk_r     <= (rst_cnt >= 12'd256);
        end
    end
    assign axi_aresetn = aresetn_r;
    assign user_lnk_up = lnk_r;

    assign usr_irq_ack   = 1'b0;
    assign msi_enable    = 1'b1;
    assign msi_vector_width = 3'd1;
    assign pci_exp_txp   = 4'd0;
    assign pci_exp_txn   = 4'd0;
    assign cfg_mgmt_read_data = 32'd0;
    assign cfg_mgmt_read_write_done = 1'b0;

    // ---------------- AXI4-Lite 主机 (任务驱动; 见头注释) ----------------
    reg [31:0] awaddr_r = 0, wdata_r = 0, araddr_r = 0;
    reg [3:0]  wstrb_r  = 4'hF;
    reg        awvalid_r = 0, wvalid_r = 0, bready_r = 0, arvalid_r = 0, rready_r = 0;
    reg [31:0] rd_data  = 0;
    reg [1:0]  wr_resp  = 0;
    // 最近一次读/写的响应码 (TB 可以层次读它来验 SLVERR —— 真 XDMA 在错误时把**数据**
    // 填 0xffffffff, 那是主机 IP 的行为、不是 axi_regs 的行为, 替身不模仿那一段)
    reg [1:0]  last_rresp = 2'd0;
    reg [1:0]  last_bresp = 2'd0;

    assign m_axil_awaddr  = awaddr_r;
    assign m_axil_awprot  = 3'd0;
    assign m_axil_awvalid = awvalid_r;
    assign m_axil_wdata   = wdata_r;
    assign m_axil_wstrb   = wstrb_r;
    assign m_axil_wvalid  = wvalid_r;
    assign m_axil_bready  = bready_r;
    assign m_axil_araddr  = araddr_r;
    assign m_axil_arprot  = 3'd0;
    assign m_axil_arvalid = arvalid_r;
    assign m_axil_rready  = rready_r;

    //=========================================================================
    // ⭐ P9: C2H AXIS 消费者 (可背压) + 观测面
    //-------------------------------------------------------------------------
    // 合同照抄 PG195 (CONF §4.3): 每拍 `tvalid && tready` 收**一整拍** 16 B; `tlast` 界定
    // 一个包 (方案 A: 只在停流 flush 出现); 非末拍 `tkeep` 必须全 1。
    // 观测面 (TB 层次读 `u_dut.u_pcie_xdma.str_*`):
    //   str_n       = 收到的拍数        str_bytes = 收下的**有效字节数** (Σ popcount(tkeep))
    //   str_last_n  = 带 tlast 的拍数   str_keep_bad = **非末拍 keep != FFFF 的次数** (合同牙)
    //   str_data[i] = 第 i 拍原文       str_last[i] / str_keep[i] 同拍边带
    //   str_to      = 1 = TB 的等待越界 (响红)
    //=========================================================================
    reg         str_tready_r = 1'b1;         // TB 用 axis_tready_set 改它造背压
    reg  [127:0] str_data  [0:255];
    reg  [15:0]  str_keep  [0:255];
    reg          str_last  [0:255];
    integer      str_n       = 0;
    integer      str_bytes   = 0;
    integer      str_last_n  = 0;
    integer      str_keep_bad = 0;
    integer      str_to      = 0;

    assign s_axis_c2h_tready_0 = str_tready_r;

    wire str_go = s_axis_c2h_tvalid_0 && str_tready_r;
    always @(posedge aclk) begin
        if (str_go) begin
            if (str_n < 256) begin
                str_data[str_n] <= s_axis_c2h_tdata_0;
                str_keep[str_n] <= s_axis_c2h_tkeep_0;
                str_last[str_n] <= s_axis_c2h_tlast_0;
            end
            str_n      = str_n + 1;
            str_bytes  = str_bytes + s_axis_c2h_tkeep_0[0] + s_axis_c2h_tkeep_0[1]
                                   + s_axis_c2h_tkeep_0[2] + s_axis_c2h_tkeep_0[3]
                                   + s_axis_c2h_tkeep_0[4] + s_axis_c2h_tkeep_0[5]
                                   + s_axis_c2h_tkeep_0[6] + s_axis_c2h_tkeep_0[7]
                                   + s_axis_c2h_tkeep_0[8] + s_axis_c2h_tkeep_0[9]
                                   + s_axis_c2h_tkeep_0[10] + s_axis_c2h_tkeep_0[11]
                                   + s_axis_c2h_tkeep_0[12] + s_axis_c2h_tkeep_0[13]
                                   + s_axis_c2h_tkeep_0[14] + s_axis_c2h_tkeep_0[15];
            if (s_axis_c2h_tlast_0) str_last_n = str_last_n + 1;
            // 非末拍 keep 必须全 1 (PG195 p.27 合同; "同拍 tlast 或全 1" 之外都记一次)
            if (!s_axis_c2h_tlast_0 && (s_axis_c2h_tkeep_0 !== 16'hFFFF)) str_keep_bad = str_keep_bad + 1;
            // 末拍 keep 不允许全 0 (PG195 p.27: "tlast 且 keep 全 0 不是合法组合")
            if (s_axis_c2h_tlast_0 && (s_axis_c2h_tkeep_0 === 16'h0000)) str_keep_bad = str_keep_bad + 1;
        end
    end

    task axis_tready_set(input v);
        begin str_tready_r <= v; end
    endtask

    task axis_mon_clear;
        begin
            str_n = 0; str_bytes = 0; str_last_n = 0; str_keep_bad = 0; str_to = 0;
        end
    endtask

    // 等 n 拍被收下 (有界; 越界 ⇒ str_to=1, 不挂死)
    task axis_wait_beats(input integer n, input integer tmo);
        integer i, j;
        begin
            j = 0;
            while ((str_n < n) && (j < tmo)) begin @(posedge aclk); j = j + 1; end
            if (str_n < n) str_to = 1;
        end
    endtask

    //=========================================================================
    // ⭐ P9: H2C AXIS 生产者 (见证 wrapper 的"恒 tready=1 吞噬")
    //   tvalid 由 TB 经 h2c_valid_set 造; 每拍 `tvalid && tready` 记一次 h2c_go_n。
    //=========================================================================
    reg         h2c_valid_r = 1'b0;
    integer     h2c_go_n    = 0;             // 被吞噬 (即 tready=1) 的拍数
    assign m_axis_h2c_tdata_0  = 128'hC0DE_0000_0000_0000_0000_0000_0000_ABCD;
    assign m_axis_h2c_tkeep_0  = 16'hFFFF;
    assign m_axis_h2c_tlast_0  = 1'b1;
    assign m_axis_h2c_tvalid_0 = h2c_valid_r;

    always @(posedge aclk) begin
        if (h2c_valid_r && m_axis_h2c_tready_0) h2c_go_n = h2c_go_n + 1;
    end

    task h2c_valid_set(input v);
        begin h2c_valid_r <= v; end
    endtask

    task h2c_mon_clear;
        begin h2c_go_n = 0; end
    endtask

    // AXI4-Lite 写: AW/W 同拍发, 等 B (与 tb_axi_regs 的主机同风格)
    task axil_write(input [31:0] a, input [31:0] d);
        begin
            @(negedge aclk);
            awaddr_r <= a;  awvalid_r <= 1'b1;
            wdata_r  <= d;  wstrb_r   <= 4'hF; wvalid_r <= 1'b1;
            bready_r <= 1'b1;
            while (!m_axil_bvalid) @(posedge aclk);
            @(negedge aclk);
            awvalid_r <= 1'b0; wvalid_r <= 1'b0;
            wr_resp   <= m_axil_bresp;
            last_bresp = m_axil_bresp;
            bready_r  <= 1'b0;
            @(posedge aclk);
        end
    endtask

    // AXI4-Lite 读
    task axil_read(input [31:0] a, output [31:0] d);
        begin
            @(negedge aclk);
            araddr_r <= a; arvalid_r <= 1'b1; rready_r <= 1'b1;
            while (!m_axil_rvalid) @(posedge aclk);
            d = m_axil_rdata;
            last_rresp = m_axil_rresp;
            @(negedge aclk);
            arvalid_r <= 1'b0; rready_r <= 1'b0;
            @(posedge aclk);
        end
    endtask

endmodule
