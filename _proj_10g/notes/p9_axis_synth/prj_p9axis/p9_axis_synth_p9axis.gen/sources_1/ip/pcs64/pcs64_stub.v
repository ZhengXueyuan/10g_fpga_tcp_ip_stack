// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
// Date        : Sun Oct 11 21:30:01 2026
// Host        : xyz-intel running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               d:/repo/XCKU5PMini/udp_hls_10g/_proj_10g/notes/p9_axis_synth/prj_p9axis/p9_axis_synth_p9axis.gen/sources_1/ip/pcs64/pcs64_stub.v
// Design      : pcs64
// Purpose     : Stub declaration of top-level module interface
// Device      : xcku5p-ffvb676-1-e
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* CHECK_LICENSE_TYPE = "pcs64,xxv_ethernet_core,{}" *) (* CORE_GENERATION_INFO = "pcs64,xxv_ethernet_v5_0_2,{x_ipProduct=Vivado 2025.2,x_ipVendor=xilinx.com,x_ipLibrary=ip,x_ipName=xxv_ethernet,x_ipVersion=5.0,x_ipCoreRevision=2,x_ipLanguage=VERILOG,x_ipSimLanguage=MIXED,C_CORE=Ethernet PCS/PMA 64-bit,C_XGMII_INTERFACE=1,C_LINE_RATE=10,C_NUM_OF_CORES=2,C_CLOCKING=Asynchronous,C_DATA_PATH_INTERFACE=MII,C_RUNTIME_SWITCH=0,C_ENABLE_PREEMPTION=0,C_ENABLE_PREEMPTION_FIFO=0,C_ENABLE_DATAPATH_PARITY=0,C_BASE_R_KR=BASE-R,C_INCLUDE_FEC_LOGIC=0,C_INCLUDE_RSFEC_LOGIC=0,C_INCLUDE_HYBRID_CMAC_RSFEC_LOGIC=0,C_INCLUDE_AUTO_NEG_LT_LOGIC=None,C_ANLT_CLK_IN_MHZ=100,C_INCLUDE_AXI4_INTERFACE=0,C_INCLUDE_STATISTICS_COUNTERS=0,C_STATISTICS_REGS_TYPE=0,C_INCLUDE_USER_FIFO=0,C_ENABLE_TX_FLOW_CONTROL_LOGIC=0,C_ENABLE_RX_FLOW_CONTROL_LOGIC=0,C_ENABLE_TIME_STAMPING=0,C_PTP_OPERATION_MODE=2,C_PTP_CLOCKING_MODE=0,C_TX_LATENCY_ADJUST=0,C_ENABLE_VLANE_ADJUST_MODE=0,C_SYS_CLK=4000,C_GT_LOCATION=1,C_GT_REF_CLK_FREQ=156.25,C_GT_DRP_CLK=100.00,C_GT_TYPE=GTY,C_GT_GROUP_SELECT=Quad X0Y0,C_LANE1_GT_LOC=X0Y4,C_LANE2_GT_LOC=X0Y5,C_LANE3_GT_LOC=NA,C_LANE4_GT_LOC=NA,C_INS_LOSS_NYQ=30,C_RX_EQ_MODE=AUTO,C_ENABLE_PIPELINE_REG=0,C_ADD_GT_CNTRL_STS_PORTS=0,C_ENABLE_GT_BOARD_INTERFACE=0,C_INCLUDE_SHARED_LOGIC=1,C_FAST_SIM_MODE=0,C_SWITCH_1_10_25G=0,C_FAMILY_CHK=kintexuplus,IS_BOARD_PROJECT=0,VERSAL_GT_BOARD_FLOW=0,C_AXIS_TDATA_WIDTH=64,C_AXIS_TKEEP_WIDTH=7,C_TX_TOTAL_BYTES_WIDTH=4,C_GT_DIFFCTRL_WIDTH=4,C_MII_DATA_WIDTH=64,C_MII_CTRL_WIDTH=8,C_GTM_GROUP_SELECT=NA,C_CMAC_CORE_SELECT=CMACE4_X0Y0,C_GT_SETTINGS=internal,C_IS_GT_WIZ_OLD=0,x_ipLicense=xxv_eth_mac_pcs@2025.05(design_linking),x_ipLicense=xxv_eth_basekr@2025.05(design_linking),x_ipLicense=xxv_tsn_802d1cm@2025.05(design_linking)}" *) (* DowngradeIPIdentifiedWarnings = "yes" *) 
(* X_CORE_INFO = "xxv_ethernet_v5_0_2,Vivado 2025.2" *) 
module pcs64(gt_rxp_in_0, gt_rxn_in_0, gt_txp_out_0, 
  gt_txn_out_0, gt_rxp_in_1, gt_rxn_in_1, gt_txp_out_1, gt_txn_out_1, tx_mii_clk_0, 
  rx_core_clk_0, rx_clk_out_0, gt_loopback_in_0, rx_reset_0, user_rx_reset_0, rxrecclkout_0, 
  rx_mii_d_0, rx_mii_c_0, ctl_rx_test_pattern_0, ctl_rx_test_pattern_enable_0, 
  ctl_rx_data_pattern_select_0, ctl_rx_prbs31_test_pattern_enable_0, 
  stat_rx_block_lock_0, stat_rx_framing_err_valid_0, stat_rx_framing_err_0, 
  stat_rx_hi_ber_0, stat_rx_valid_ctrl_code_0, stat_rx_bad_code_0, 
  stat_rx_bad_code_valid_0, stat_rx_error_valid_0, stat_rx_error_0, stat_rx_fifo_error_0, 
  stat_rx_local_fault_0, stat_rx_status_0, tx_reset_0, user_tx_reset_0, tx_mii_d_0, 
  tx_mii_c_0, ctl_tx_test_pattern_0, ctl_tx_test_pattern_enable_0, 
  ctl_tx_test_pattern_select_0, ctl_tx_data_pattern_select_0, 
  ctl_tx_test_pattern_seed_a_0, ctl_tx_test_pattern_seed_b_0, 
  ctl_tx_prbs31_test_pattern_enable_0, stat_tx_local_fault_0, 
  gtwiz_reset_tx_datapath_0, gtwiz_reset_rx_datapath_0, gtpowergood_out_0, 
  txoutclksel_in_0, rxoutclksel_in_0, tx_mii_clk_1, rx_core_clk_1, rx_clk_out_1, 
  gt_loopback_in_1, rx_reset_1, user_rx_reset_1, rxrecclkout_1, rx_mii_d_1, rx_mii_c_1, 
  ctl_rx_test_pattern_1, ctl_rx_test_pattern_enable_1, ctl_rx_data_pattern_select_1, 
  ctl_rx_prbs31_test_pattern_enable_1, stat_rx_block_lock_1, 
  stat_rx_framing_err_valid_1, stat_rx_framing_err_1, stat_rx_hi_ber_1, 
  stat_rx_valid_ctrl_code_1, stat_rx_bad_code_1, stat_rx_bad_code_valid_1, 
  stat_rx_error_valid_1, stat_rx_error_1, stat_rx_fifo_error_1, stat_rx_local_fault_1, 
  stat_rx_status_1, tx_reset_1, user_tx_reset_1, tx_mii_d_1, tx_mii_c_1, 
  ctl_tx_test_pattern_1, ctl_tx_test_pattern_enable_1, ctl_tx_test_pattern_select_1, 
  ctl_tx_data_pattern_select_1, ctl_tx_test_pattern_seed_a_1, 
  ctl_tx_test_pattern_seed_b_1, ctl_tx_prbs31_test_pattern_enable_1, 
  stat_tx_local_fault_1, gtwiz_reset_tx_datapath_1, gtwiz_reset_rx_datapath_1, 
  gtpowergood_out_1, txoutclksel_in_1, rxoutclksel_in_1, gt_refclk_p, gt_refclk_n, 
  gt_refclk_out, qpllreset_in_0, ctl_rx_wdt_disable_0, ctl_rx_wdt_disable_1, sys_reset, dclk)
/* synthesis syn_black_box black_box_pad_pin="gt_rxp_in_0,gt_rxn_in_0,gt_txp_out_0,gt_txn_out_0,gt_rxp_in_1,gt_rxn_in_1,gt_txp_out_1,gt_txn_out_1,gt_loopback_in_0[2:0],rx_reset_0,user_rx_reset_0,rxrecclkout_0,rx_mii_d_0[63:0],rx_mii_c_0[7:0],ctl_rx_test_pattern_0,ctl_rx_test_pattern_enable_0,ctl_rx_data_pattern_select_0,ctl_rx_prbs31_test_pattern_enable_0,stat_rx_block_lock_0,stat_rx_framing_err_valid_0,stat_rx_framing_err_0,stat_rx_hi_ber_0,stat_rx_valid_ctrl_code_0,stat_rx_bad_code_0,stat_rx_bad_code_valid_0,stat_rx_error_valid_0,stat_rx_error_0[7:0],stat_rx_fifo_error_0,stat_rx_local_fault_0,stat_rx_status_0,tx_reset_0,user_tx_reset_0,tx_mii_d_0[63:0],tx_mii_c_0[7:0],ctl_tx_test_pattern_0,ctl_tx_test_pattern_enable_0,ctl_tx_test_pattern_select_0,ctl_tx_data_pattern_select_0,ctl_tx_test_pattern_seed_a_0[57:0],ctl_tx_test_pattern_seed_b_0[57:0],ctl_tx_prbs31_test_pattern_enable_0,stat_tx_local_fault_0,gtwiz_reset_tx_datapath_0,gtwiz_reset_rx_datapath_0,gtpowergood_out_0,txoutclksel_in_0[2:0],rxoutclksel_in_0[2:0],gt_loopback_in_1[2:0],rx_reset_1,user_rx_reset_1,rxrecclkout_1,rx_mii_d_1[63:0],rx_mii_c_1[7:0],ctl_rx_test_pattern_1,ctl_rx_test_pattern_enable_1,ctl_rx_data_pattern_select_1,ctl_rx_prbs31_test_pattern_enable_1,stat_rx_block_lock_1,stat_rx_framing_err_valid_1,stat_rx_framing_err_1,stat_rx_hi_ber_1,stat_rx_valid_ctrl_code_1,stat_rx_bad_code_1,stat_rx_bad_code_valid_1,stat_rx_error_valid_1,stat_rx_error_1[7:0],stat_rx_fifo_error_1,stat_rx_local_fault_1,stat_rx_status_1,tx_reset_1,user_tx_reset_1,tx_mii_d_1[63:0],tx_mii_c_1[7:0],ctl_tx_test_pattern_1,ctl_tx_test_pattern_enable_1,ctl_tx_test_pattern_select_1,ctl_tx_data_pattern_select_1,ctl_tx_test_pattern_seed_a_1[57:0],ctl_tx_test_pattern_seed_b_1[57:0],ctl_tx_prbs31_test_pattern_enable_1,stat_tx_local_fault_1,gtwiz_reset_tx_datapath_1,gtwiz_reset_rx_datapath_1,gtpowergood_out_1,txoutclksel_in_1[2:0],rxoutclksel_in_1[2:0],gt_refclk_p[0:0],gt_refclk_n[0:0],gt_refclk_out[0:0],qpllreset_in_0,ctl_rx_wdt_disable_0,ctl_rx_wdt_disable_1,sys_reset" */
/* synthesis syn_force_seq_prim="tx_mii_clk_0" */
/* synthesis syn_force_seq_prim="rx_core_clk_0" */
/* synthesis syn_force_seq_prim="rx_clk_out_0" */
/* synthesis syn_force_seq_prim="tx_mii_clk_1" */
/* synthesis syn_force_seq_prim="rx_core_clk_1" */
/* synthesis syn_force_seq_prim="rx_clk_out_1" */
/* synthesis syn_force_seq_prim="dclk" */;
  input gt_rxp_in_0;
  input gt_rxn_in_0;
  output gt_txp_out_0;
  output gt_txn_out_0;
  input gt_rxp_in_1;
  input gt_rxn_in_1;
  output gt_txp_out_1;
  output gt_txn_out_1;
  output tx_mii_clk_0 /* synthesis syn_isclock = 1 */;
  input rx_core_clk_0 /* synthesis syn_isclock = 1 */;
  output rx_clk_out_0 /* synthesis syn_isclock = 1 */;
  input [2:0]gt_loopback_in_0;
  input rx_reset_0;
  output user_rx_reset_0;
  output rxrecclkout_0;
  output [63:0]rx_mii_d_0;
  output [7:0]rx_mii_c_0;
  input ctl_rx_test_pattern_0;
  input ctl_rx_test_pattern_enable_0;
  input ctl_rx_data_pattern_select_0;
  input ctl_rx_prbs31_test_pattern_enable_0;
  output stat_rx_block_lock_0;
  output stat_rx_framing_err_valid_0;
  output stat_rx_framing_err_0;
  output stat_rx_hi_ber_0;
  output stat_rx_valid_ctrl_code_0;
  output stat_rx_bad_code_0;
  output stat_rx_bad_code_valid_0;
  output stat_rx_error_valid_0;
  output [7:0]stat_rx_error_0;
  output stat_rx_fifo_error_0;
  output stat_rx_local_fault_0;
  output stat_rx_status_0;
  input tx_reset_0;
  output user_tx_reset_0;
  input [63:0]tx_mii_d_0;
  input [7:0]tx_mii_c_0;
  input ctl_tx_test_pattern_0;
  input ctl_tx_test_pattern_enable_0;
  input ctl_tx_test_pattern_select_0;
  input ctl_tx_data_pattern_select_0;
  input [57:0]ctl_tx_test_pattern_seed_a_0;
  input [57:0]ctl_tx_test_pattern_seed_b_0;
  input ctl_tx_prbs31_test_pattern_enable_0;
  output stat_tx_local_fault_0;
  input gtwiz_reset_tx_datapath_0;
  input gtwiz_reset_rx_datapath_0;
  output gtpowergood_out_0;
  input [2:0]txoutclksel_in_0;
  input [2:0]rxoutclksel_in_0;
  output tx_mii_clk_1 /* synthesis syn_isclock = 1 */;
  input rx_core_clk_1 /* synthesis syn_isclock = 1 */;
  output rx_clk_out_1 /* synthesis syn_isclock = 1 */;
  input [2:0]gt_loopback_in_1;
  input rx_reset_1;
  output user_rx_reset_1;
  output rxrecclkout_1;
  output [63:0]rx_mii_d_1;
  output [7:0]rx_mii_c_1;
  input ctl_rx_test_pattern_1;
  input ctl_rx_test_pattern_enable_1;
  input ctl_rx_data_pattern_select_1;
  input ctl_rx_prbs31_test_pattern_enable_1;
  output stat_rx_block_lock_1;
  output stat_rx_framing_err_valid_1;
  output stat_rx_framing_err_1;
  output stat_rx_hi_ber_1;
  output stat_rx_valid_ctrl_code_1;
  output stat_rx_bad_code_1;
  output stat_rx_bad_code_valid_1;
  output stat_rx_error_valid_1;
  output [7:0]stat_rx_error_1;
  output stat_rx_fifo_error_1;
  output stat_rx_local_fault_1;
  output stat_rx_status_1;
  input tx_reset_1;
  output user_tx_reset_1;
  input [63:0]tx_mii_d_1;
  input [7:0]tx_mii_c_1;
  input ctl_tx_test_pattern_1;
  input ctl_tx_test_pattern_enable_1;
  input ctl_tx_test_pattern_select_1;
  input ctl_tx_data_pattern_select_1;
  input [57:0]ctl_tx_test_pattern_seed_a_1;
  input [57:0]ctl_tx_test_pattern_seed_b_1;
  input ctl_tx_prbs31_test_pattern_enable_1;
  output stat_tx_local_fault_1;
  input gtwiz_reset_tx_datapath_1;
  input gtwiz_reset_rx_datapath_1;
  output gtpowergood_out_1;
  input [2:0]txoutclksel_in_1;
  input [2:0]rxoutclksel_in_1;
  input [0:0]gt_refclk_p;
  input [0:0]gt_refclk_n;
  output [0:0]gt_refclk_out;
  input qpllreset_in_0;
  input ctl_rx_wdt_disable_0;
  input ctl_rx_wdt_disable_1;
  input sys_reset;
  input dclk /* synthesis syn_isclock = 1 */;
endmodule
