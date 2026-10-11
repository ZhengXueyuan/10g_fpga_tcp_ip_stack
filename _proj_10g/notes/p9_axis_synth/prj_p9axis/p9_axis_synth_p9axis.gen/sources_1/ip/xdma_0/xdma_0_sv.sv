// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
// -------------------------------------------------------------------------------
// This file contains confidential and proprietary information
// of AMD and is protected under U.S. and international copyright
// and other intellectual property laws.
//
// DISCLAIMER
// This disclaimer is not a license and does not grant any
// rights to the materials distributed herewith. Except as
// otherwise provided in a valid license issued to you by
// AMD, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND AMD HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
// (2) AMD shall not be liable (whether in contract or tort,
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature
// related to, arising under or in connection with these
// materials, including for any direct, or any indirect,
// special, incidental, or consequential loss or damage
// (including loss of data, profits, goodwill, or any type of
// loss or damage suffered as a result of any action brought
// by a third party) even if such damage or loss was
// reasonably foreseeable or AMD had been advised of the
// possibility of the same.
//
// CRITICAL APPLICATIONS
// AMD products are not designed or intended to be fail-
// safe, or for use in any application requiring fail-safe
// performance, such as life-support or safety devices or
// systems, Class III medical devices, nuclear facilities,
// applications related to the deployment of airbags, or any
// other applications that could lead to death, personal
// injury, or severe property or environmental damage
// (individually and collectively, "Critical
// Applications"). Customer assumes the sole risk and
// liability of any use of AMD products in Critical
// Applications, subject only to applicable laws and
// regulations governing limitations on product liability.
//
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
// PART OF THIS FILE AT ALL TIMES.
//
// DO NOT MODIFY THIS FILE.

// MODULE VLNV: xilinx.com:ip:xdma:4.2

`timescale 1ps / 1ps

`include "vivado_interfaces.svh"

module xdma_0_sv (
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI_LITE" *)
  (* X_INTERFACE_MODE = "master M_AXI_LITE" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXI_LITE, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1, SUPPORTS_NARROW_BURST 0, DATA_WIDTH 32, PROTOCOL AXI4LITE, FREQ_HZ 100000000, ID_WIDTH 0, ADDR_WIDTH 32, AWUSER_WIDTH 0, ARUSER_WIDTH 0, WUSER_WIDTH 0, RUSER_WIDTH 0, BUSER_WIDTH 0, READ_WRITE_MODE READ_WRITE, HAS_BURST 0, HAS_LOCK 0, HAS_PROT 1, HAS_CACHE 0, HAS_QOS 0, HAS_REGION 0, HAS_WSTRB 1, HAS_BRESP 1, HAS_RRESP 1, MAX_BURST_LENGTH 1, PHASE 0.0, NUM_READ_THREADS 1, NUM_WRITE_THREADS 1, RUSER_BITS_PER_BYTE 0, WUSER_BITS_PER_BYTE 0, INSERT_VIP 0" *)
  vivado_axi4_lite_v1_0.master M_AXI_LITE,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_C2H_0" *)
  (* X_INTERFACE_MODE = "slave S_AXIS_C2H_0" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXIS_C2H_0, TDATA_NUM_BYTES 16, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 100000000, PHASE 0.0, LAYERED_METADATA undef, INSERT_VIP 0" *)
  vivado_axis_v1_0.slave S_AXIS_C2H_0,
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_H2C_0" *)
  (* X_INTERFACE_MODE = "master M_AXIS_H2C_0" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXIS_H2C_0, TDATA_NUM_BYTES 16, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 1, HAS_TLAST 1, FREQ_HZ 100000000, PHASE 0.0, LAYERED_METADATA undef, INSERT_VIP 0" *)
  vivado_axis_v1_0.master M_AXIS_H2C_0,
  (* X_INTERFACE_IGNORE = "true" *)
  input wire sys_clk,
  (* X_INTERFACE_IGNORE = "true" *)
  input wire sys_clk_gt,
  (* X_INTERFACE_IGNORE = "true" *)
  input wire sys_rst_n,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire user_lnk_up,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire [3:0] pci_exp_txp,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire [3:0] pci_exp_txn,
  (* X_INTERFACE_IGNORE = "true" *)
  input wire [3:0] pci_exp_rxp,
  (* X_INTERFACE_IGNORE = "true" *)
  input wire [3:0] pci_exp_rxn,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire axi_aclk,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire axi_aresetn,
  (* X_INTERFACE_IGNORE = "true" *)
  input wire [0:0] usr_irq_req,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire [0:0] usr_irq_ack,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire msi_enable,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire [2:0] msi_vector_width,
  (* X_INTERFACE_IGNORE = "true" *)
  input wire [18:0] cfg_mgmt_addr,
  (* X_INTERFACE_IGNORE = "true" *)
  input wire cfg_mgmt_write,
  (* X_INTERFACE_IGNORE = "true" *)
  input wire [31:0] cfg_mgmt_write_data,
  (* X_INTERFACE_IGNORE = "true" *)
  input wire [3:0] cfg_mgmt_byte_enable,
  (* X_INTERFACE_IGNORE = "true" *)
  input wire cfg_mgmt_read,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire [31:0] cfg_mgmt_read_data,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire cfg_mgmt_read_write_done
);

  // interface wire assignments
  assign M_AXIS_H2C_0.TDEST = 0;
  assign M_AXIS_H2C_0.TID = 0;
  assign M_AXIS_H2C_0.TSTRB = 0;
  assign M_AXIS_H2C_0.TUSER = 0;

  xdma_0 inst (
    .sys_clk(sys_clk),
    .sys_clk_gt(sys_clk_gt),
    .sys_rst_n(sys_rst_n),
    .user_lnk_up(user_lnk_up),
    .pci_exp_txp(pci_exp_txp),
    .pci_exp_txn(pci_exp_txn),
    .pci_exp_rxp(pci_exp_rxp),
    .pci_exp_rxn(pci_exp_rxn),
    .axi_aclk(axi_aclk),
    .axi_aresetn(axi_aresetn),
    .usr_irq_req(usr_irq_req),
    .usr_irq_ack(usr_irq_ack),
    .msi_enable(msi_enable),
    .msi_vector_width(msi_vector_width),
    .m_axil_awaddr(M_AXI_LITE.AWADDR),
    .m_axil_awprot(M_AXI_LITE.AWPROT),
    .m_axil_awvalid(M_AXI_LITE.AWVALID),
    .m_axil_awready(M_AXI_LITE.AWREADY),
    .m_axil_wdata(M_AXI_LITE.WDATA),
    .m_axil_wstrb(M_AXI_LITE.WSTRB),
    .m_axil_wvalid(M_AXI_LITE.WVALID),
    .m_axil_wready(M_AXI_LITE.WREADY),
    .m_axil_bvalid(M_AXI_LITE.BVALID),
    .m_axil_bresp(M_AXI_LITE.BRESP),
    .m_axil_bready(M_AXI_LITE.BREADY),
    .m_axil_araddr(M_AXI_LITE.ARADDR),
    .m_axil_arprot(M_AXI_LITE.ARPROT),
    .m_axil_arvalid(M_AXI_LITE.ARVALID),
    .m_axil_arready(M_AXI_LITE.ARREADY),
    .m_axil_rdata(M_AXI_LITE.RDATA),
    .m_axil_rresp(M_AXI_LITE.RRESP),
    .m_axil_rvalid(M_AXI_LITE.RVALID),
    .m_axil_rready(M_AXI_LITE.RREADY),
    .cfg_mgmt_addr(cfg_mgmt_addr),
    .cfg_mgmt_write(cfg_mgmt_write),
    .cfg_mgmt_write_data(cfg_mgmt_write_data),
    .cfg_mgmt_byte_enable(cfg_mgmt_byte_enable),
    .cfg_mgmt_read(cfg_mgmt_read),
    .cfg_mgmt_read_data(cfg_mgmt_read_data),
    .cfg_mgmt_read_write_done(cfg_mgmt_read_write_done),
    .s_axis_c2h_tdata_0(S_AXIS_C2H_0.TDATA),
    .s_axis_c2h_tlast_0(S_AXIS_C2H_0.TLAST),
    .s_axis_c2h_tvalid_0(S_AXIS_C2H_0.TVALID),
    .s_axis_c2h_tready_0(S_AXIS_C2H_0.TREADY),
    .s_axis_c2h_tkeep_0(S_AXIS_C2H_0.TKEEP),
    .m_axis_h2c_tdata_0(M_AXIS_H2C_0.TDATA),
    .m_axis_h2c_tlast_0(M_AXIS_H2C_0.TLAST),
    .m_axis_h2c_tvalid_0(M_AXIS_H2C_0.TVALID),
    .m_axis_h2c_tready_0(M_AXIS_H2C_0.TREADY),
    .m_axis_h2c_tkeep_0(M_AXIS_H2C_0.TKEEP)
  );

endmodule
