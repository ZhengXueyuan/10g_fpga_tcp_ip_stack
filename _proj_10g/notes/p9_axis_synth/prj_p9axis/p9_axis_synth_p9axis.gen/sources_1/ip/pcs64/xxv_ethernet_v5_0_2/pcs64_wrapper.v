// ------------------------------------------------------------------------------
//   (c) Copyright 2020-2021 Advanced Micro Devices, Inc. All rights reserved.
// 
//   This file contains confidential and proprietary information
//   of Advanced Micro Devices, Inc. and is protected under U.S. and
//   international copyright and other intellectual property
//   laws.
// 
//   DISCLAIMER
//   This disclaimer is not a license and does not grant any
//   rights to the materials distributed herewith. Except as
//   otherwise provided in a valid license issued to you by
//   AMD, and to the maximum extent permitted by applicable
//   law: (1) THESE MATERIALS ARE MADE AVAILABLE \"AS IS\" AND
//   WITH ALL FAULTS, AND AMD HEREBY DISCLAIMS ALL WARRANTIES
//   AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
//   BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
//   INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
//   (2) AMD shall not be liable (whether in contract or tort,
//   including negligence, or under any other theory of
//   liability) for any loss or damage of any kind or nature
//   related to, arising under or in connection with these
//   materials, including for any direct, or any indirect,
//   special, incidental, or consequential loss or damage
//   (including loss of data, profits, goodwill, or any type of
//   loss or damage suffered as a result of any action brought
//   by a third party) even if such damage or loss was
//   reasonably foreseeable or AMD had been advised of the
//   possibility of the same.
// 
//   CRITICAL APPLICATIONS
//   AMD products are not designed or intended to be fail-
//   safe, or for use in any application requiring fail-safe
//   performance, such as life-support or safety devices or
//   systems, Class III medical devices, nuclear facilities,
//   applications related to the deployment of airbags, or any
//   other applications that could lead to death, personal
//   injury, or severe property or environmental damage
//   (individually and collectively, \"Critical
//   Applications\"). Customer assumes the sole risk and
//   liability of any use of AMD products in Critical
//   Applications, subject only to applicable laws and
//   regulations governing limitations on product liability.
// 
//   THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
//   PART OF THIS FILE AT ALL TIMES.
//
// 
//
//       Owner:          
//       Revision:       $Id: $
//                       $Author: $
//                       $DateTime: $
//                       $Change: $
//       Description:
//
// 
////------------------------------------------------------------------------------


`timescale 1fs/1fs

(* DowngradeIPIdentifiedWarnings="yes" *)
module pcs64_wrapper

#(
    ////PHYSICAL LAYER OPTIONS
    parameter   C_LINE_RATE                      =   25,
    parameter   C_NUM_OF_CORES                   =   4,
    parameter   C_CLOCKING                       =   "Synchronous",
    parameter   C_DATA_PATH_INTERFACE            =   "AXI Stream",
    parameter   C_BASE_R_KR                      =   "BASE-KR",
    parameter   C_INCLUDE_FEC_LOGIC              =   0,
    parameter   C_INCLUDE_RSFEC_LOGIC            =   0,
    parameter   C_INCLUDE_HYBRID_CMAC_RSFEC_LOGIC=   0,
    parameter   C_INCLUDE_AUTO_NEG_LT_LOGIC      =   "None",
    parameter   C_INCLUDE_USER_FIFO              =   0,
    parameter   C_ENABLE_TX_FLOW_CONTROL_LOGIC   =   0,
    parameter   C_ENABLE_RX_FLOW_CONTROL_LOGIC   =   0,
    parameter   C_ENABLE_TIME_STAMPING           =   0,
    parameter   C_PTP_OPERATION_MODE             =   2,
    parameter   C_PTP_CLOCKING_MODE              =   0,
    parameter   C_TX_LATENCY_ADJUST              =   0,
    parameter   C_ENABLE_VLANE_ADJUST_MODE       =   0,
    parameter   C_GT_REF_CLK_FREQ                =   322.265625,
    parameter   C_GT_DRP_CLK                     =   100,
    parameter   C_GT_TYPE                        =   "GTY",
    parameter   C_LANE1_GT_LOC                   =   "X0Y0",
    parameter   C_LANE2_GT_LOC                   =   "X0Y1",
    parameter   C_LANE3_GT_LOC                   =   "X0Y2",
    parameter   C_LANE4_GT_LOC                   =   "X0Y3",
    parameter   C_ENABLE_PIPELINE_REG            =   0,
    parameter   C_ADD_GT_CNTRL_STS_PORTS         =   0,
    parameter   C_RUNTIME_SWITCH                 =   0,
    parameter   C_INCLUDE_SHARED_LOGIC           =   1
)
(
    input  wire gt_rxp_in_0,
    input  wire gt_rxn_in_0,
    output wire gt_txp_out_0,
    output wire gt_txn_out_0,
    input  wire gt_rxp_in_1,
    input  wire gt_rxn_in_1,
    output wire gt_txp_out_1,
    output wire gt_txn_out_1,
    output wire tx_mii_clk_0,
    input  wire rx_core_clk_0,
    output wire rx_clk_out_0,
    input  wire [2:0] gt_loopback_in_0,
//// RX_0 Signals
    input  wire rx_reset_0,
    output wire user_rx_reset_0,
    output wire rxrecclkout_0,
//// RX_0 User Interface Signals
    output wire [63:0] rx_mii_d_0,
    output wire [7:0] rx_mii_c_0,
//// RX_0 Control Signals
    input  wire ctl_rx_test_pattern_0,
    input  wire ctl_rx_test_pattern_enable_0,
    input  wire ctl_rx_data_pattern_select_0,
    input  wire ctl_rx_prbs31_test_pattern_enable_0,


//// RX_0 Stats Signals
    output wire stat_rx_block_lock_0,
    output wire stat_rx_framing_err_valid_0,
    output wire stat_rx_framing_err_0,
    output wire stat_rx_hi_ber_0,
    output wire stat_rx_valid_ctrl_code_0,
    output wire stat_rx_bad_code_0,
    output wire stat_rx_bad_code_valid_0,
    output wire stat_rx_error_valid_0,
    output wire [7:0] stat_rx_error_0,
    output wire stat_rx_fifo_error_0,
    output wire stat_rx_local_fault_0,
    output wire  stat_rx_status_0,


//// TX_0 Signals
    input  wire tx_reset_0,
    output wire user_tx_reset_0,

//// TX_0 User Interface Signals
    input  wire [63:0] tx_mii_d_0,
    input  wire [7:0] tx_mii_c_0,


//// TX_0 Control Signals
    input  wire ctl_tx_test_pattern_0,
    input  wire ctl_tx_test_pattern_enable_0,
    input  wire ctl_tx_test_pattern_select_0,
    input  wire ctl_tx_data_pattern_select_0,
    input  wire [57:0] ctl_tx_test_pattern_seed_a_0,
    input  wire [57:0] ctl_tx_test_pattern_seed_b_0,
    input  wire ctl_tx_prbs31_test_pattern_enable_0,


//// TX_0 Stats Signals
    output wire stat_tx_local_fault_0,







////GT Transceiver debug interface ports
//// GT Debug interface ports
////GT DRP ports 
    input wire gtwiz_reset_tx_datapath_0,
    input wire gtwiz_reset_rx_datapath_0,
    output wire gtpowergood_out_0,
    input wire [2:0] txoutclksel_in_0,
    input wire [2:0] rxoutclksel_in_0,
    input  wire ctl_rx_wdt_disable_0,
    output wire tx_mii_clk_1,
    input  wire rx_core_clk_1,
    output wire rx_clk_out_1,
    input  wire [2:0] gt_loopback_in_1,
//// RX_1 Signals
    input  wire rx_reset_1,
    output wire user_rx_reset_1,
    output wire rxrecclkout_1,
//// RX_1 User Interface Signals
    output wire [63:0] rx_mii_d_1,
    output wire [7:0] rx_mii_c_1,
//// RX_1 Control Signals
    input  wire ctl_rx_test_pattern_1,
    input  wire ctl_rx_test_pattern_enable_1,
    input  wire ctl_rx_data_pattern_select_1,
    input  wire ctl_rx_prbs31_test_pattern_enable_1,


//// RX_1 Stats Signals
    output wire stat_rx_block_lock_1,
    output wire stat_rx_framing_err_valid_1,
    output wire stat_rx_framing_err_1,
    output wire stat_rx_hi_ber_1,
    output wire stat_rx_valid_ctrl_code_1,
    output wire stat_rx_bad_code_1,
    output wire stat_rx_bad_code_valid_1,
    output wire stat_rx_error_valid_1,
    output wire [7:0] stat_rx_error_1,
    output wire stat_rx_fifo_error_1,
    output wire stat_rx_local_fault_1,
    output wire  stat_rx_status_1,


//// TX_1 Signals
    input  wire tx_reset_1,
    output wire user_tx_reset_1,

//// TX_1 User Interface Signals
    input  wire [63:0] tx_mii_d_1,
    input  wire [7:0] tx_mii_c_1,


//// TX_1 Control Signals
    input  wire ctl_tx_test_pattern_1,
    input  wire ctl_tx_test_pattern_enable_1,
    input  wire ctl_tx_test_pattern_select_1,
    input  wire ctl_tx_data_pattern_select_1,
    input  wire [57:0] ctl_tx_test_pattern_seed_a_1,
    input  wire [57:0] ctl_tx_test_pattern_seed_b_1,
    input  wire ctl_tx_prbs31_test_pattern_enable_1,


//// TX_1 Stats Signals
    output wire stat_tx_local_fault_1,







////GT Transceiver debug interface ports
//// GT Debug interface ports
////GT DRP ports 
    input wire gtwiz_reset_tx_datapath_1,
    input wire gtwiz_reset_rx_datapath_1,
    output wire gtpowergood_out_1,
    input wire [2:0] txoutclksel_in_1,
    input wire [2:0] rxoutclksel_in_1,
    input  wire ctl_rx_wdt_disable_1,
    input  wire gt_refclk_p,
    input  wire gt_refclk_n,
    output wire gt_refclk_out,
    input qpllreset_in_0,
    input  wire sys_reset,
    input  wire dclk

);

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


  wire [0:0]      gtrefclk00_in_0;
  wire [0:0]      gtrefclk00_int_0;
  wire [0:0]      gt_refclk;
  wire gt_refclkcopy;
 IBUFDS_GTE4 IBUFDS_GTE4_GTREFCLK0_INST (
    .I             (gt_refclk_p),
    .IB            (gt_refclk_n),
    .CEB           (1'b0),
    .O             (gt_refclk),
    .ODIV2         (gt_refclkcopy)
  );


  wire [9:0]     drpaddr_in_0;
  wire [15:0]    drpdi_in_0;
  wire [0:0]     drpen_in_0;
  wire [0:0]     drpwe_in_0;
  wire [0:0]     drpclk_in_0;
  wire [15:0]    drpdo_out_0;
  wire [0:0]     drprdy_out_0;
  wire [9:0]     drpaddr_in_1;
  wire [15:0]    drpdi_in_1;
  wire [0:0]     drpen_in_1;
  wire [0:0]     drpwe_in_1;
  wire [0:0]     drpclk_in_1;
  wire [15:0]    drpdo_out_1;
  wire [0:0]     drprdy_out_1;
  wire powergood_out;
  assign powergood_out = gtpowergood_out_0 & gtpowergood_out_1;

  assign gtwiz_reset_qpll0reset_out = ((~powergood_out)|qpllreset_in_0); 
  assign gtwiz_reset_qpll1reset_out = ((~powergood_out)|qpllreset_in_0); 


pcs64_common_wrapper i_pcs64_common_wrapper
(   .refclk(gt_refclk),
    .qpll0reset(gtwiz_reset_qpll0reset_out ),
    .qpll0lock(gtwiz_reset_qpll0lock_in),
    .qpll0outclk(qpll0clk_in),
    .qpll0outrefclk(qpll0refclk_in),
    .qpll1reset(gtwiz_reset_qpll1reset_out),
    .qpll1lock(gtwiz_reset_qpll1lock_in),
    .qpll1outclk(qpll1clk_in),
    .qpll1outrefclk(qpll1refclk_in)
);

     BUFG_GT refclk_bufg_gt_i
  (
      .I       (gt_refclkcopy),
      .CE      (powergood_out),
      .CEMASK  (1'b1),
      .CLR     (1'b0),
      .CLRMASK (1'b1),
      .DIV     (3'b000),
      .O       (gt_refclk_out)
  ); 



  localparam [28:0] MASTER_WATCHDOG_TIMER_RESET = (750000000 / (1000 / 100.00));
  reg [28:0] master_watchdog_0 = MASTER_WATCHDOG_TIMER_RESET;
  reg master_watchdog_barking_0 = 1'b0;
  wire master_watchdog_barking_sync_0;
  reg [28:0] master_watchdog_1 = MASTER_WATCHDOG_TIMER_RESET;
  reg master_watchdog_barking_1 = 1'b0;
  wire master_watchdog_barking_sync_1;



//// Insert GT interface here
  wire [0:0]      gt_rxn_int_0;
  wire [0:0]      gt_rxp_int_0;
  wire [0:0]      gt_txn_int_0;
  wire [0:0]      gt_txp_int_0;

  assign gt_rxn_int_0 = gt_rxn_in_0;
  assign gt_rxp_int_0 = gt_rxp_in_0;
  assign gt_txn_out_0 = gt_txn_int_0;
  assign gt_txp_out_0 = gt_txp_int_0;
  wire [0:0]      gt_rxn_int_1;
  wire [0:0]      gt_rxp_int_1;
  wire [0:0]      gt_txn_int_1;
  wire [0:0]      gt_txp_int_1;

  assign gt_rxn_int_1 = gt_rxn_in_1;
  assign gt_rxp_int_1 = gt_rxp_in_1;
  assign gt_txn_out_1 = gt_txn_int_1;
  assign gt_txp_out_1 = gt_txp_int_1;
 
  wire [0:0]      gtyrxn_in_0;
  wire [0:0]      gtyrxp_in_0;
      
  wire [0:0]      gtytxn_out_0;
  wire [0:0]      gtytxp_out_0;
  wire [0:0]      rxpmaresetdone_out_0;
  wire [0:0]      txprgdivresetdone_out_0;
  wire [0:0]      txpmaresetdone_out_0;

  wire [0:0]      rxprgdivresetdone_out_0;

  wire [0:0]      gtwiz_userclk_rx_usrclk_out_0;
  wire [0:0]      gtwiz_userclk_rx_srcclk_out_0;
  wire [0:0]      gtwiz_userclk_rx_usrclk2_out_0;
  wire [0:0]      txusrclk_in_0;
  wire [0:0]      txusrclk2_in_0;
  wire [0:0]      rxusrclk_in_0;
  wire [0:0]      rxusrclk2_in_0;

  wire [127:0]    txdata_in_0;
  wire [127:0]    rxdata_out_0;

  wire [0:0]      gtwiz_reset_rx_done_int_0;
  wire [0:0]      gtwiz_reset_rx_data_good_in_0;
  wire [0:0]      gtwiz_reset_clk_freerun_in_0;
  wire [0:0]      gtwiz_reset_all_in_0;
  wire [0:0]      gtwiz_reset_tx_pll_and_datapath_in_0;
  wire [0:0]      gtwiz_reset_tx_datapath_in_0;
  wire [0:0]      gtwiz_reset_tx_done_out_0;
  wire [0:0]      gtwiz_reset_rx_pll_and_datapath_in_0;
  wire [0:0]      gtwiz_reset_rx_datapath_in_0;
  wire [0:0]      gtwiz_reset_rx_cdr_stable_out_0;
  wire [0:0]      gtwiz_reset_rx_done_out_0;

  wire [0:0]      gtwiz_reset_tx_done_int_0;
  wire [0:0]      gtwiz_userclk_tx_active_in_0;
  wire [0:0]      core_gtwiz_userclk_tx_reset_in_0;
  wire [0:0]      gtwiz_userclk_tx_srcclk_out_0;
  wire [0:0]      gtwiz_userclk_tx_usrclk_out_0;
  wire [0:0]      gtwiz_userclk_tx_usrclk2_out_0;
  wire [0:0]      core_gtwiz_userclk_tx_active_out_0;

  wire [0:0]      gtwiz_userclk_rx_active_in_0;

  wire [0:0]      core_gtwiz_userclk_rx_reset_in_0;
  wire [0:0]      core_gtwiz_userclk_rx_active_out_0;

  wire [0:0]      rxgearboxslip_in_0;
  wire [1:0]      rxdatavalid_out_0;
  wire [5:0]      rxheader_out_0;
  wire [1:0]      rxheadervalid_out_0;

  wire [5:0]      txheader_in_0;
  wire [6:0]      txsequence_in_0 = 7'b0;

  wire [0:0]      rxlatclk_in_0;
  wire [0:0]      txlatclk_in_0;
  assign rxlatclk_in_0 = dclk;
  assign txlatclk_in_0 = dclk;
  assign    qpll0clk_in_0                = qpll0clk_in;
  assign    qpll0refclk_in_0             = qpll0refclk_in;
  assign    qpll1clk_in_0                = qpll1clk_in;
  assign    qpll1refclk_in_0             = qpll1refclk_in;
  assign    gtwiz_reset_qpll0lock_in_0   = gtwiz_reset_qpll0lock_in & (~gtwiz_reset_all_in_0);
  assign    gtwiz_reset_qpll1lock_in_0   = gtwiz_reset_qpll1lock_in & (~gtwiz_reset_all_in_0);
  wire [1:0]      rxstartofseq_out_0;

  wire [0:0]      rxlpmen_in_0;
  wire [0:0]      rxcdrhold_in_0;
  wire [0:0]      rxdfelfhold_in_0;
  wire [0:0]      rxlpmlfhold_in_0;
  wire [0:0]      rxdfelpmreset_in_0;     
  wire [0:0]      rxpmareset_in_0;
  assign rxdfelfhold_in_0 = 1'b0;
  assign rxlpmlfhold_in_0 = 1'b0;
  assign rxcdrhold_in_0 = 1'b0;
  assign rxdfelpmreset_in_0 = 1'b0;
  assign rxpmareset_in_0 = 1'b0;
  assign rxlpmen_in_0 = 1'b0;

  wire   rxrecclkout_out_0;
  assign rxrecclkout_0 = rxrecclkout_out_0;
  assign drpaddr_in_0 = 10'b0000000000;
  assign drprst_in_0 = 1'b0;
  assign drpdi_in_0 = 16'h0000;
  assign drpen_in_0 = 1'b0;
  assign drpwe_in_0 = 1'b0;
  assign drpclk_in_0 = dclk;

  assign gtwiz_reset_tx_datapath_in_0 = gtwiz_reset_tx_datapath_0;
  assign gtwiz_reset_rx_datapath_in_0 = gtwiz_reset_rx_datapath_0 | master_watchdog_barking_sync_0;

  assign gtwiz_reset_all_in_0 = sys_reset ;

  wire [2:0] loopback_in_0 = gt_loopback_in_0;

  ////assign inputs to GT
  assign gtwiz_reset_clk_freerun_in_0         = dclk;

  assign gtwiz_reset_tx_pll_and_datapath_in_0 = 1'b0;
  assign gtwiz_reset_rx_pll_and_datapath_in_0 = 1'b0;
  assign gtwiz_reset_rx_data_good_in_0        = 1'b1;
  assign gtyrxn_in_0                          = gt_rxn_int_0;
  assign gtyrxp_in_0                          = gt_rxp_int_0;

  ////outputs from GT
  assign gt_txn_int_0                         = gtytxn_out_0;
  assign gt_txp_int_0                         = gtytxp_out_0;
  assign gtwiz_reset_tx_done_int_0            = gtwiz_reset_tx_done_out_0;
  assign gtwiz_reset_rx_done_int_0            = gtwiz_reset_rx_done_out_0;

  //// ===================================================================================================================
  //// TX/RX USER CLOCKING Helper block integration
  //// ===================================================================================================================

  wire [0:0]      txoutclk_out_0;
  wire [0:0]      rxoutclk_out_0;

  //// ===================================================================================================================
  //// USER CLOCKING RESETS
  //// ===================================================================================================================

  //// The TX user clocking helper block should be held in reset until the clock source of that block is known to be
  //// stable. The following assignment is an example of how that stability can be determined, based on the selected TX
  //// user clock source. Replace the assignment with the appropriate signal or logic to achieve that behavior as needed.


  //// The RX user clocking helper block should be held in reset until the clock source of that block is known to be
  //// stable. The following assignment is an example of how that stability can be determined, based on the selected RX
  //// user clock source. Replace the assignment with the appropriate signal or logic to achieve that behavior as needed.
  //// Note that, if the clock source is derived from the received data, this is indicated by a combination of the
  //// appropriate reset done signal and the reset helper block's RX CDR stable indicator.

  //// ===================================================================================================================
  //// USER CLOCKING Source clocks
  //// ===================================================================================================================

  assign gtwiz_userclk_tx_srcclk_out_0             = txoutclk_out_0;
  assign gtwiz_userclk_rx_srcclk_out_0             = rxoutclk_out_0;

  //// Instantiate a single instance of the transmitter user clocking network helper block
  assign core_gtwiz_userclk_tx_reset_in_0 = ~((txprgdivresetdone_out_0) & (txpmaresetdone_out_0));
  assign core_gtwiz_userclk_rx_reset_in_0 = ~rxpmaresetdone_out_0;
  //// Generate a single module instance which is driven by a clock source associated with the master transmitter channel,
  //// and which drives TXUSRCLK and TXUSRCLK2 for all channels
  //// The source clock is TXOUTCLK from the master transmitter channel
  pcs64_ultrascale_tx_userclk
  #(
    .P_CONTENTS                     (0),
    .P_FREQ_RATIO_SOURCE_TO_USRCLK  (1),


    .P_FREQ_RATIO_USRCLK_TO_USRCLK2 (1)
  ) i_core_gtwiz_userclk_tx_inst_0 (
    .gtwiz_userclk_tx_srcclk_in   (gtwiz_userclk_tx_srcclk_out_0),
    .gtwiz_userclk_tx_reset_in    (core_gtwiz_userclk_tx_reset_in_0),
    .gtwiz_userclk_tx_usrclk_out  (gtwiz_userclk_tx_usrclk_out_0),
    .gtwiz_userclk_tx_usrclk2_out (gtwiz_userclk_tx_usrclk2_out_0),
    .gtwiz_userclk_tx_active_out  (core_gtwiz_userclk_tx_active_out_0)
  );

  //// Generate a single module instance which is driven by a clock source associated with the master receiver channel,
  //// and which drives RXUSRCLK and RXUSRCLK2 for all channels
  //// The source clock is RXOUTCLK from the master receiver channel
  pcs64_ultrascale_rx_userclk
  #(
    .P_CONTENTS                     (0),
    .P_FREQ_RATIO_SOURCE_TO_USRCLK  (1),
    .P_FREQ_RATIO_USRCLK_TO_USRCLK2 (1)
  ) i_core_gtwiz_userclk_rx_inst_0 (
      .gtwiz_userclk_rx_srcclk_in   (gtwiz_userclk_rx_srcclk_out_0),
      .gtwiz_userclk_rx_reset_in    (core_gtwiz_userclk_rx_reset_in_0),
      .gtwiz_userclk_rx_usrclk_out  (gtwiz_userclk_rx_usrclk_out_0),
      .gtwiz_userclk_rx_usrclk2_out (gtwiz_userclk_rx_usrclk2_out_0),
      .gtwiz_userclk_rx_active_out  (core_gtwiz_userclk_rx_active_out_0)
    );

  //// Drive TXUSRCLK and TXUSRCLK2 for all channels with the respective helper block outputs
  assign txusrclk_in_0                     = gtwiz_userclk_tx_usrclk_out_0;
  assign txusrclk2_in_0                    = gtwiz_userclk_tx_usrclk2_out_0;
  assign gtwiz_userclk_tx_active_in_0      = core_gtwiz_userclk_tx_active_out_0;

  //// Drive RXUSRCLK and RXUSRCLK2 for each channel with the respective outputs of the associated helper block
  assign rxusrclk_in_0                     = gtwiz_userclk_rx_usrclk_out_0;
  assign rxusrclk2_in_0                    = gtwiz_userclk_rx_usrclk2_out_0;
  assign gtwiz_userclk_rx_active_in_0      = core_gtwiz_userclk_rx_active_out_0;

  //// GT Subcore Instatiataion 
  pcs64_gt i_pcs64_gt
  (
   .drpaddr_in(drpaddr_in_0),
   .drpclk_in(drpclk_in_0),
   .drpdi_in(drpdi_in_0),
   .drpdo_out(drpdo_out_0),
   .drpen_in(drpen_in_0),
   .drprdy_out(drprdy_out_0),
   .drprst_in(drprst_in_0),
   .drpwe_in(drpwe_in_0),
   .gtpowergood_out(gtpowergood_out_0),
   .gtwiz_reset_all_in(gtwiz_reset_all_in_0),
   .gtwiz_reset_clk_freerun_in(gtwiz_reset_clk_freerun_in_0),
   .gtwiz_reset_qpll0lock_in(gtwiz_reset_qpll0lock_in_0),
   .gtwiz_reset_qpll0reset_out(gtwiz_reset_qpll0reset_out_0),
   .gtwiz_reset_rx_cdr_stable_out(gtwiz_reset_rx_cdr_stable_out_0),
   .gtwiz_reset_rx_datapath_in(gtwiz_reset_rx_datapath_in_0),
   .gtwiz_reset_rx_done_out(gtwiz_reset_rx_done_out_0),
   .gtwiz_reset_rx_pll_and_datapath_in(gtwiz_reset_rx_pll_and_datapath_in_0),
   .gtwiz_reset_tx_datapath_in(gtwiz_reset_tx_datapath_in_0),
   .gtwiz_reset_tx_done_out(gtwiz_reset_tx_done_out_0),
   .gtwiz_reset_tx_pll_and_datapath_in(gtwiz_reset_tx_pll_and_datapath_in_0),
   .gtwiz_userclk_rx_active_in(gtwiz_userclk_rx_active_in_0),
   .gtwiz_userclk_tx_active_in(gtwiz_userclk_tx_active_in_0),
   .gtyrxn_in(gtyrxn_in_0),
   .gtyrxp_in(gtyrxp_in_0),
   .gtytxn_out(gtytxn_out_0),
   .gtytxp_out(gtytxp_out_0),
   .loopback_in(loopback_in_0),
   .qpll0clk_in(qpll0clk_in_0),
   .qpll0refclk_in(qpll0refclk_in_0),
   .qpll1clk_in(qpll1clk_in_0),
   .qpll1refclk_in(qpll1refclk_in_0),
   .rxcdrhold_in(rxcdrhold_in_0),
   .rxdata_out(rxdata_out_0),
   .rxdatavalid_out(rxdatavalid_out_0),
   .rxdfelfhold_in(rxdfelfhold_in_0),
   .rxdfelpmreset_in(rxdfelpmreset_in_0),
   .rxgearboxslip_in(rxgearboxslip_in_0),
   .rxheader_out(rxheader_out_0),
   .rxheadervalid_out(rxheadervalid_out_0),
   .rxlatclk_in(rxlatclk_in_0),
   .rxlpmen_in(rxlpmen_in_0),
   .rxlpmlfhold_in(rxlpmlfhold_in_0),
   .rxoutclk_out(rxoutclk_out_0),
   .rxoutclksel_in(rxoutclksel_in_0),
   .rxpmareset_in(rxpmareset_in_0),
   .rxpmaresetdone_out(rxpmaresetdone_out_0),
   .rxprgdivresetdone_out(rxprgdivresetdone_out_0),
   .rxrecclkout_out(rxrecclkout_out_0),
   .rxstartofseq_out(rxstartofseq_out_0),
   .rxusrclk2_in(rxusrclk2_in_0),
   .rxusrclk_in(rxusrclk_in_0),
   .txdata_in(txdata_in_0),
   .txheader_in(txheader_in_0),
   .txlatclk_in(txlatclk_in_0),
   .txoutclk_out(txoutclk_out_0),
   .txoutclksel_in(txoutclksel_in_0),
   .txpmaresetdone_out(txpmaresetdone_out_0),
   .txprgdivresetdone_out(txprgdivresetdone_out_0),
   .txsequence_in(txsequence_in_0),
   .txusrclk2_in(txusrclk2_in_0),
   .txusrclk_in(txusrclk_in_0)
  );


  wire [0:0]      gtwiz_reset_tx_done_int_sync_0;
  wire [0:0]      gtwiz_reset_tx_done_int_sync_inv_0;
  wire [0:0]      gtwiz_reset_rx_done_int_sync_0;
  wire [0:0]      gtwiz_reset_rx_done_int_sync_inv_0;
  wire [0:0]      rx_reset_done_async_0;
  wire [0:0]      tx_reset_done_async_0;
  wire [0:0]      rx_serdes_clk_0;
  wire [0:0]      rx_serdes_reset_done_0;
  wire [0:0]      rx_reset_done_0;
  
  wire tx_reset_done_sync_0;
  pcs64_cdc_sync i_pcs64_core_cdc_sync_tx_resetdone_0
  (
   .clk              (rx_core_clk_0),
   .signal_in        (tx_reset_done_async_0), 
   .signal_out       (tx_reset_done_sync_0)
  );

  wire tx_reset_done_sync_dclk_0;
  wire rx_reset_done_sync_dclk_0;
  pcs64_cdc_sync i_pcs64_core_cdc_sync_tx_resetdone_dclk_0
  (
   .clk              (dclk),
   .signal_in        (tx_reset_done_async_0), 
   .signal_out       (tx_reset_done_sync_dclk_0)
  );

  pcs64_cdc_sync i_pcs64_core_cdc_sync_rx_resetdone_dclk_0
  (
   .clk              (dclk),
   .signal_in        (rx_reset_done_async_0), 
   .signal_out       (rx_reset_done_sync_dclk_0)
  );


  wire stat_rx_block_lock_dclk_0;
  pcs64_cdc_sync i_pcs64_core_cdc_sync_stat_rx_block_lock_dclk_0
  (
   .clk              (dclk),
   .signal_in        (stat_rx_block_lock_0), 
   .signal_out       (stat_rx_block_lock_dclk_0)
  );

  pcs64_cdc_sync i_pcs64_core_cdc_sync_watchdog_barking_sync_0
  (
   .clk              (dclk),
   .signal_in        (master_watchdog_barking_0), 
   .signal_out       (master_watchdog_barking_sync_0)
  );
  always @(posedge dclk)
  begin
    if ((tx_reset_done_sync_dclk_0 == 1'b0 && rx_reset_done_sync_dclk_0 == 1'b0 && stat_rx_block_lock_dclk_0 == 1'b1) || master_watchdog_0 == 0 || ctl_rx_prbs31_test_pattern_enable_0 == 1'b1)
      master_watchdog_0 <= MASTER_WATCHDOG_TIMER_RESET;
    else
      master_watchdog_0 <= master_watchdog_0 - 1;
    end

  wire ctl_rx_wdt_disable_sync_0;
  pcs64_cdc_sync i_pcs64_core_cdc_sync_axi_ctl_rx_wdt_disable_0
  (
   .clk              (dclk),
  
   .signal_in        (ctl_rx_wdt_disable_0), 

   .signal_out       (ctl_rx_wdt_disable_sync_0)
  );

  always @(posedge dclk)
  begin
    if (master_watchdog_0 == 0 && ctl_rx_wdt_disable_sync_0 == 0)
      master_watchdog_barking_0 <= 1'b1;
    else
      master_watchdog_barking_0 <= 1'b0;
  end

  assign tx_mii_clk_0     =  gtwiz_userclk_tx_usrclk2_out_0;
  assign rx_clk_out_0     =  gtwiz_userclk_rx_usrclk2_out_0;
  assign gt_txusrclk2_0   =  gtwiz_userclk_tx_usrclk2_out_0;
  assign gt_rxusrclk2_0   =  gtwiz_userclk_rx_usrclk2_out_0;
  wire [63:0]     tx_serdes_data0_0;
  wire [63:0]     tx_serdes_data0_int_0;
  wire [1:0]      tx_serdes_header0_0;
  wire [1:0]      tx_serdes_header0_int_0;
  wire [1:0]      tx_serdes_headervalid0_0;

  wire [63:0]     rx_serdes_data0_0;
  wire [1:0]      rx_serdes_header0_0;
  wire [63:0]     rx_serdes_data0_int_0;
  wire [1:0]      rx_serdes_header0_int_0;
  wire [0:0]      rx_serdes_bitslip_0 ;
  wire [0:0]      rx_serdes_headervalid_0 ;
  wire [0:0]      rx_serdes_datavalid_0 ;
  wire [0:0]      rx_serdes_headervalid_int_0;
  wire [0:0]      rx_serdes_datavalid_int_0;
  pcs64_cdc_sync i_pcs64_core_cdc_sync_gt_tx_resetdone_0
  (
   .clk              (gt_txusrclk2_0),
   .signal_in        (gtwiz_reset_tx_done_int_0), 
   .signal_out       (gtwiz_reset_tx_done_int_sync_0)
  );

  assign gtwiz_reset_tx_done_int_sync_inv_0   =  ~(gtwiz_reset_tx_done_int_sync_0);
  assign tx_reset_done_async_0                =  gtwiz_reset_tx_done_int_sync_inv_0 | tx_reset_0;
  assign user_tx_reset_0                      =  tx_reset_done_async_0;

  pcs64_cdc_sync i_pcs64_core_cdc_sync_gt_rx_resetdone_0
  (
   .clk              (gt_rxusrclk2_0),
   .signal_in        (gtwiz_reset_rx_done_int_0), 
   .signal_out       (gtwiz_reset_rx_done_int_sync_0)
  );

  assign gtwiz_reset_rx_done_int_sync_inv_0   =  ~(gtwiz_reset_rx_done_int_sync_0);
  assign rx_reset_done_async_0                =  gtwiz_reset_rx_done_int_sync_inv_0 | rx_reset_0;
 

 
  pcs64_cdc_sync i_pcs64_core_cdc_sync_gt_rx_serdes_resetdone_0
  (
   .clk              (rx_serdes_clk_0),
   .signal_in        (rx_reset_done_async_0), 
   .signal_out       (rx_serdes_reset_done_0)
  );
  
  pcs64_cdc_sync i_pcs64_core_cdc_sync_gt_rxreset_0
  (
   .clk              (rx_core_clk_0),
   .signal_in        (rx_reset_done_async_0), 
   .signal_out       (rx_reset_done_0)
  );


  assign user_rx_reset_0                      =  rx_reset_done_0;


  assign rx_serdes_clk_0                      =  gtwiz_userclk_rx_usrclk2_out_0;
 

 
  assign txdata_in_0                          =  {64'b0,tx_serdes_data0_int_0};
  assign txheader_in_0                        =  {4'b0,tx_serdes_header0_int_0};

 pcs64_gt_pipeline 
  #(
    .WIDTH        (64)
  ) i_pcs64_tx_64bit_gt_pipeline_serdes_data0_0 (
    .clk          (gt_txusrclk2_0),
    .data_in      (tx_serdes_data0_0),
    .data_out     (tx_serdes_data0_int_0)
  );

  pcs64_gt_pipeline 
  #(
    .WIDTH        (2)
  ) i_pcs64_tx_2bit_gt_pipeline_serdes_data0_0 (
    .clk          (gt_txusrclk2_0),
    .data_in      (tx_serdes_header0_0),
    .data_out     (tx_serdes_header0_int_0)
  );

   assign rx_serdes_data0_int_0             =  rxdata_out_0[63:0];
   assign rx_serdes_header0_int_0           =  rxheader_out_0[1:0];
   assign rxgearboxslip_in_0                =  rx_serdes_bitslip_0;
   assign rx_serdes_datavalid_int_0         =  rxdatavalid_out_0[0];
   assign rx_serdes_headervalid_int_0       =  rxheadervalid_out_0;


  pcs64_gt_pipeline 
  #(
    .WIDTH        (64)
  ) i_pcs64_rx_64bit_gt_pipeline_serdes_data0_0 (
    .clk          (rx_serdes_clk_0),
    .data_in      (rx_serdes_data0_int_0),
    .data_out     (rx_serdes_data0_0)
  );

  pcs64_gt_pipeline 
  #(
    .WIDTH        (2)
  ) i_pcs64_rx_2bit_gt_pipeline_serdes_header0_0 (
    .clk          (rx_serdes_clk_0),
    .data_in      (rx_serdes_header0_int_0),
    .data_out     (rx_serdes_header0_0)
  );

  pcs64_gt_pipeline 
  #(
    .WIDTH        (1)
  ) i_pcs64_rx_2bit_gt_pipeline_serdes_data_valid0_0 (
    .clk          (rx_serdes_clk_0),
    .data_in      (rx_serdes_datavalid_int_0),
    .data_out     (rx_serdes_datavalid_0)
  );
  pcs64_gt_pipeline 
  #(
    .WIDTH        (1)
  ) i_pcs64_rx_2bit_gt_pipeline_serdes_header_valid0_0 (
    .clk          (rx_serdes_clk_0),
    .data_in      (rx_serdes_headervalid_int_0),
    .data_out     (rx_serdes_headervalid_0)
  );

pcs64_top #(
  .SERDES_WIDTH ( 64 )
) i_pcs64_top_0 (
  .tx_mii_reset (tx_reset_done_async_0),
  .rx_mii_clk (rx_core_clk_0),
  .rx_mii_reset (rx_reset_done_0),
  .tx_serdes_refclk (gt_txusrclk2_0),
  .tx_serdes_refclk_reset (tx_reset_done_async_0),
  .rx_serdes_clk (rx_serdes_clk_0),
  .rx_serdes_reset (rx_serdes_reset_done_0),
//// RX AXIS Signals
  .rx_mii_d (rx_mii_d_0),
  .rx_mii_c (rx_mii_c_0),

//// RX Control Signals
  .ctl_rx_test_pattern (ctl_rx_test_pattern_0),
  .ctl_rx_test_pattern_enable (ctl_rx_test_pattern_enable_0),
  .ctl_rx_data_pattern_select (ctl_rx_data_pattern_select_0),
  .ctl_rx_prbs31_test_pattern_enable (ctl_rx_prbs31_test_pattern_enable_0),


//// RX Stats Signals
  .stat_rx_status  (stat_rx_status_0),
  .stat_rx_block_lock (stat_rx_block_lock_0),
  .stat_rx_framing_err_valid (stat_rx_framing_err_valid_0),
  .stat_rx_framing_err (stat_rx_framing_err_0),
  .stat_rx_hi_ber (stat_rx_hi_ber_0),
  .stat_rx_valid_ctrl_code (stat_rx_valid_ctrl_code_0),
  .stat_rx_bad_code (stat_rx_bad_code_0),
  .stat_rx_bad_code_valid (stat_rx_bad_code_valid_0),
  .stat_rx_error_valid (stat_rx_error_valid_0),
  .stat_rx_error (stat_rx_error_0),
  .stat_rx_fifo_error (stat_rx_fifo_error_0),
  .stat_rx_local_fault (stat_rx_local_fault_0),


//// TX AXIS Signals
  .tx_mii_d (tx_mii_d_0),
  .tx_mii_c (tx_mii_c_0),

//// TX Control Signals
  .ctl_tx_test_pattern (ctl_tx_test_pattern_0),
  .ctl_tx_test_pattern_enable (ctl_tx_test_pattern_enable_0),
  .ctl_tx_test_pattern_select (ctl_tx_test_pattern_select_0),
  .ctl_tx_data_pattern_select (ctl_tx_data_pattern_select_0),
  .ctl_tx_test_pattern_seed_a (ctl_tx_test_pattern_seed_a_0),
  .ctl_tx_test_pattern_seed_b (ctl_tx_test_pattern_seed_b_0),
  .ctl_tx_prbs31_test_pattern_enable (ctl_tx_prbs31_test_pattern_enable_0),


//// TX Stats Signals
  .stat_tx_local_fault (stat_tx_local_fault_0),



  .rx_serdes_datavalid0              (rx_serdes_datavalid_0),
  .rx_serdes_headervalid0            (rx_serdes_headervalid_0),
  .rx_serdes_bitslip0                (rx_serdes_bitslip_0),

  .rx_serdes_data0                   (rx_serdes_data0_0),
  .rx_serdes_header0                 (rx_serdes_header0_0),
  .tx_serdes_data0                   (tx_serdes_data0_0),
  .tx_serdes_header0                 (tx_serdes_header0_0)


);
  wire [0:0]      gtyrxn_in_1;
  wire [0:0]      gtyrxp_in_1;
      
  wire [0:0]      gtytxn_out_1;
  wire [0:0]      gtytxp_out_1;
  wire [0:0]      rxpmaresetdone_out_1;
  wire [0:0]      txprgdivresetdone_out_1;
  wire [0:0]      txpmaresetdone_out_1;

  wire [0:0]      rxprgdivresetdone_out_1;

  wire [0:0]      gtwiz_userclk_rx_usrclk_out_1;
  wire [0:0]      gtwiz_userclk_rx_srcclk_out_1;
  wire [0:0]      gtwiz_userclk_rx_usrclk2_out_1;
  wire [0:0]      txusrclk_in_1;
  wire [0:0]      txusrclk2_in_1;
  wire [0:0]      rxusrclk_in_1;
  wire [0:0]      rxusrclk2_in_1;

  wire [127:0]    txdata_in_1;
  wire [127:0]    rxdata_out_1;

  wire [0:0]      gtwiz_reset_rx_done_int_1;
  wire [0:0]      gtwiz_reset_rx_data_good_in_1;
  wire [0:0]      gtwiz_reset_clk_freerun_in_1;
  wire [0:0]      gtwiz_reset_all_in_1;
  wire [0:0]      gtwiz_reset_tx_pll_and_datapath_in_1;
  wire [0:0]      gtwiz_reset_tx_datapath_in_1;
  wire [0:0]      gtwiz_reset_tx_done_out_1;
  wire [0:0]      gtwiz_reset_rx_pll_and_datapath_in_1;
  wire [0:0]      gtwiz_reset_rx_datapath_in_1;
  wire [0:0]      gtwiz_reset_rx_cdr_stable_out_1;
  wire [0:0]      gtwiz_reset_rx_done_out_1;

  wire [0:0]      gtwiz_reset_tx_done_int_1;
  wire [0:0]      gtwiz_userclk_tx_active_in_1;
  wire [0:0]      core_gtwiz_userclk_tx_reset_in_1;
  wire [0:0]      gtwiz_userclk_tx_srcclk_out_1;
  wire [0:0]      gtwiz_userclk_tx_usrclk_out_1;
  wire [0:0]      gtwiz_userclk_tx_usrclk2_out_1;
  wire [0:0]      core_gtwiz_userclk_tx_active_out_1;

  wire [0:0]      gtwiz_userclk_rx_active_in_1;

  wire [0:0]      core_gtwiz_userclk_rx_reset_in_1;
  wire [0:0]      core_gtwiz_userclk_rx_active_out_1;

  wire [0:0]      rxgearboxslip_in_1;
  wire [1:0]      rxdatavalid_out_1;
  wire [5:0]      rxheader_out_1;
  wire [1:0]      rxheadervalid_out_1;

  wire [5:0]      txheader_in_1;
  wire [6:0]      txsequence_in_1 = 7'b0;

  wire [0:0]      rxlatclk_in_1;
  wire [0:0]      txlatclk_in_1;
  assign rxlatclk_in_1 = dclk;
  assign txlatclk_in_1 = dclk;
  assign    qpll0clk_in_1                = qpll0clk_in;
  assign    qpll0refclk_in_1             = qpll0refclk_in;
  assign    qpll1clk_in_1                = qpll1clk_in;
  assign    qpll1refclk_in_1             = qpll1refclk_in;
  assign    gtwiz_reset_qpll0lock_in_1   = gtwiz_reset_qpll0lock_in & (~gtwiz_reset_all_in_1);
  assign    gtwiz_reset_qpll1lock_in_1   = gtwiz_reset_qpll1lock_in & (~gtwiz_reset_all_in_1);
  wire [1:0]      rxstartofseq_out_1;

  wire [0:0]      rxlpmen_in_1;
  wire [0:0]      rxcdrhold_in_1;
  wire [0:0]      rxdfelfhold_in_1;
  wire [0:0]      rxlpmlfhold_in_1;
  wire [0:0]      rxdfelpmreset_in_1;     
  wire [0:0]      rxpmareset_in_1;
  assign rxdfelfhold_in_1 = 1'b0;
  assign rxlpmlfhold_in_1 = 1'b0;
  assign rxcdrhold_in_1 = 1'b0;
  assign rxdfelpmreset_in_1 = 1'b0;
  assign rxpmareset_in_1 = 1'b0;
  assign rxlpmen_in_1 = 1'b0;

  wire   rxrecclkout_out_1;
  assign rxrecclkout_1 = rxrecclkout_out_1;
  assign drpaddr_in_1 = 10'b0000000000;
  assign drprst_in_1 = 1'b0;
  assign drpdi_in_1 = 16'h0000;
  assign drpen_in_1 = 1'b0;
  assign drpwe_in_1 = 1'b0;
  assign drpclk_in_1 = dclk;

  assign gtwiz_reset_tx_datapath_in_1 = gtwiz_reset_tx_datapath_1;
  assign gtwiz_reset_rx_datapath_in_1 = gtwiz_reset_rx_datapath_1 | master_watchdog_barking_sync_1;

  assign gtwiz_reset_all_in_1 = sys_reset ;

  wire [2:0] loopback_in_1 = gt_loopback_in_1;

  ////assign inputs to GT
  assign gtwiz_reset_clk_freerun_in_1         = dclk;

  assign gtwiz_reset_tx_pll_and_datapath_in_1 = 1'b0;
  assign gtwiz_reset_rx_pll_and_datapath_in_1 = 1'b0;
  assign gtwiz_reset_rx_data_good_in_1        = 1'b1;
  assign gtyrxn_in_1                          = gt_rxn_int_1;
  assign gtyrxp_in_1                          = gt_rxp_int_1;

  ////outputs from GT
  assign gt_txn_int_1                         = gtytxn_out_1;
  assign gt_txp_int_1                         = gtytxp_out_1;
  assign gtwiz_reset_tx_done_int_1            = gtwiz_reset_tx_done_out_1;
  assign gtwiz_reset_rx_done_int_1            = gtwiz_reset_rx_done_out_1;

  //// ===================================================================================================================
  //// TX/RX USER CLOCKING Helper block integration
  //// ===================================================================================================================

  wire [0:0]      txoutclk_out_1;
  wire [0:0]      rxoutclk_out_1;

  //// ===================================================================================================================
  //// USER CLOCKING RESETS
  //// ===================================================================================================================

  //// The TX user clocking helper block should be held in reset until the clock source of that block is known to be
  //// stable. The following assignment is an example of how that stability can be determined, based on the selected TX
  //// user clock source. Replace the assignment with the appropriate signal or logic to achieve that behavior as needed.


  //// The RX user clocking helper block should be held in reset until the clock source of that block is known to be
  //// stable. The following assignment is an example of how that stability can be determined, based on the selected RX
  //// user clock source. Replace the assignment with the appropriate signal or logic to achieve that behavior as needed.
  //// Note that, if the clock source is derived from the received data, this is indicated by a combination of the
  //// appropriate reset done signal and the reset helper block's RX CDR stable indicator.

  //// ===================================================================================================================
  //// USER CLOCKING Source clocks
  //// ===================================================================================================================

  assign gtwiz_userclk_tx_srcclk_out_1             = txoutclk_out_1;
  assign gtwiz_userclk_rx_srcclk_out_1             = rxoutclk_out_1;

  //// Instantiate a single instance of the transmitter user clocking network helper block
  assign core_gtwiz_userclk_tx_reset_in_1 = ~((txprgdivresetdone_out_1) & (txpmaresetdone_out_1));
  assign core_gtwiz_userclk_rx_reset_in_1 = ~rxpmaresetdone_out_1;
  //// Generate a single module instance which is driven by a clock source associated with the master transmitter channel,
  //// and which drives TXUSRCLK and TXUSRCLK2 for all channels
  //// The source clock is TXOUTCLK from the master transmitter channel
  pcs64_ultrascale_tx_userclk
  #(
    .P_CONTENTS                     (0),
    .P_FREQ_RATIO_SOURCE_TO_USRCLK  (1),


    .P_FREQ_RATIO_USRCLK_TO_USRCLK2 (1)
  ) i_core_gtwiz_userclk_tx_inst_1 (
    .gtwiz_userclk_tx_srcclk_in   (gtwiz_userclk_tx_srcclk_out_1),
    .gtwiz_userclk_tx_reset_in    (core_gtwiz_userclk_tx_reset_in_1),
    .gtwiz_userclk_tx_usrclk_out  (gtwiz_userclk_tx_usrclk_out_1),
    .gtwiz_userclk_tx_usrclk2_out (gtwiz_userclk_tx_usrclk2_out_1),
    .gtwiz_userclk_tx_active_out  (core_gtwiz_userclk_tx_active_out_1)
  );

  //// Generate a single module instance which is driven by a clock source associated with the master receiver channel,
  //// and which drives RXUSRCLK and RXUSRCLK2 for all channels
  //// The source clock is RXOUTCLK from the master receiver channel
  pcs64_ultrascale_rx_userclk
  #(
    .P_CONTENTS                     (0),
    .P_FREQ_RATIO_SOURCE_TO_USRCLK  (1),
    .P_FREQ_RATIO_USRCLK_TO_USRCLK2 (1)
  ) i_core_gtwiz_userclk_rx_inst_1 (
      .gtwiz_userclk_rx_srcclk_in   (gtwiz_userclk_rx_srcclk_out_1),
      .gtwiz_userclk_rx_reset_in    (core_gtwiz_userclk_rx_reset_in_1),
      .gtwiz_userclk_rx_usrclk_out  (gtwiz_userclk_rx_usrclk_out_1),
      .gtwiz_userclk_rx_usrclk2_out (gtwiz_userclk_rx_usrclk2_out_1),
      .gtwiz_userclk_rx_active_out  (core_gtwiz_userclk_rx_active_out_1)
    );

  //// Drive TXUSRCLK and TXUSRCLK2 for all channels with the respective helper block outputs
  assign txusrclk_in_1                     = gtwiz_userclk_tx_usrclk_out_1;
  assign txusrclk2_in_1                    = gtwiz_userclk_tx_usrclk2_out_1;
  assign gtwiz_userclk_tx_active_in_1      = core_gtwiz_userclk_tx_active_out_1;

  //// Drive RXUSRCLK and RXUSRCLK2 for each channel with the respective outputs of the associated helper block
  assign rxusrclk_in_1                     = gtwiz_userclk_rx_usrclk_out_1;
  assign rxusrclk2_in_1                    = gtwiz_userclk_rx_usrclk2_out_1;
  assign gtwiz_userclk_rx_active_in_1      = core_gtwiz_userclk_rx_active_out_1;

  //// GT Subcore Instatiataion 
  pcs64_gt_1 i_pcs64_gt_1
  (
   .drpaddr_in(drpaddr_in_1),
   .drpclk_in(drpclk_in_1),
   .drpdi_in(drpdi_in_1),
   .drpdo_out(drpdo_out_1),
   .drpen_in(drpen_in_1),
   .drprdy_out(drprdy_out_1),
   .drprst_in(drprst_in_1),
   .drpwe_in(drpwe_in_1),
   .gtpowergood_out(gtpowergood_out_1),
   .gtwiz_reset_all_in(gtwiz_reset_all_in_1),
   .gtwiz_reset_clk_freerun_in(gtwiz_reset_clk_freerun_in_1),
   .gtwiz_reset_qpll0lock_in(gtwiz_reset_qpll0lock_in_1),
   .gtwiz_reset_qpll0reset_out(gtwiz_reset_qpll0reset_out_1),
   .gtwiz_reset_rx_cdr_stable_out(gtwiz_reset_rx_cdr_stable_out_1),
   .gtwiz_reset_rx_datapath_in(gtwiz_reset_rx_datapath_in_1),
   .gtwiz_reset_rx_done_out(gtwiz_reset_rx_done_out_1),
   .gtwiz_reset_rx_pll_and_datapath_in(gtwiz_reset_rx_pll_and_datapath_in_1),
   .gtwiz_reset_tx_datapath_in(gtwiz_reset_tx_datapath_in_1),
   .gtwiz_reset_tx_done_out(gtwiz_reset_tx_done_out_1),
   .gtwiz_reset_tx_pll_and_datapath_in(gtwiz_reset_tx_pll_and_datapath_in_1),
   .gtwiz_userclk_rx_active_in(gtwiz_userclk_rx_active_in_1),
   .gtwiz_userclk_tx_active_in(gtwiz_userclk_tx_active_in_1),
   .gtyrxn_in(gtyrxn_in_1),
   .gtyrxp_in(gtyrxp_in_1),
   .gtytxn_out(gtytxn_out_1),
   .gtytxp_out(gtytxp_out_1),
   .loopback_in(loopback_in_1),
   .qpll0clk_in(qpll0clk_in_1),
   .qpll0refclk_in(qpll0refclk_in_1),
   .qpll1clk_in(qpll1clk_in_1),
   .qpll1refclk_in(qpll1refclk_in_1),
   .rxcdrhold_in(rxcdrhold_in_1),
   .rxdata_out(rxdata_out_1),
   .rxdatavalid_out(rxdatavalid_out_1),
   .rxdfelfhold_in(rxdfelfhold_in_1),
   .rxdfelpmreset_in(rxdfelpmreset_in_1),
   .rxgearboxslip_in(rxgearboxslip_in_1),
   .rxheader_out(rxheader_out_1),
   .rxheadervalid_out(rxheadervalid_out_1),
   .rxlatclk_in(rxlatclk_in_1),
   .rxlpmen_in(rxlpmen_in_1),
   .rxlpmlfhold_in(rxlpmlfhold_in_1),
   .rxoutclk_out(rxoutclk_out_1),
   .rxoutclksel_in(rxoutclksel_in_1),
   .rxpmareset_in(rxpmareset_in_1),
   .rxpmaresetdone_out(rxpmaresetdone_out_1),
   .rxprgdivresetdone_out(rxprgdivresetdone_out_1),
   .rxrecclkout_out(rxrecclkout_out_1),
   .rxstartofseq_out(rxstartofseq_out_1),
   .rxusrclk2_in(rxusrclk2_in_1),
   .rxusrclk_in(rxusrclk_in_1),
   .txdata_in(txdata_in_1),
   .txheader_in(txheader_in_1),
   .txlatclk_in(txlatclk_in_1),
   .txoutclk_out(txoutclk_out_1),
   .txoutclksel_in(txoutclksel_in_1),
   .txpmaresetdone_out(txpmaresetdone_out_1),
   .txprgdivresetdone_out(txprgdivresetdone_out_1),
   .txsequence_in(txsequence_in_1),
   .txusrclk2_in(txusrclk2_in_1),
   .txusrclk_in(txusrclk_in_1)
  );


  wire [0:0]      gtwiz_reset_tx_done_int_sync_1;
  wire [0:0]      gtwiz_reset_tx_done_int_sync_inv_1;
  wire [0:0]      gtwiz_reset_rx_done_int_sync_1;
  wire [0:0]      gtwiz_reset_rx_done_int_sync_inv_1;
  wire [0:0]      rx_reset_done_async_1;
  wire [0:0]      tx_reset_done_async_1;
  wire [0:0]      rx_serdes_clk_1;
  wire [0:0]      rx_serdes_reset_done_1;
  wire [0:0]      rx_reset_done_1;
  
  wire tx_reset_done_sync_1;
  pcs64_cdc_sync i_pcs64_core_cdc_sync_tx_resetdone_1
  (
   .clk              (rx_core_clk_1),
   .signal_in        (tx_reset_done_async_1), 
   .signal_out       (tx_reset_done_sync_1)
  );

  wire tx_reset_done_sync_dclk_1;
  wire rx_reset_done_sync_dclk_1;
  pcs64_cdc_sync i_pcs64_core_cdc_sync_tx_resetdone_dclk_1
  (
   .clk              (dclk),
   .signal_in        (tx_reset_done_async_1), 
   .signal_out       (tx_reset_done_sync_dclk_1)
  );

  pcs64_cdc_sync i_pcs64_core_cdc_sync_rx_resetdone_dclk_1
  (
   .clk              (dclk),
   .signal_in        (rx_reset_done_async_1), 
   .signal_out       (rx_reset_done_sync_dclk_1)
  );


  wire stat_rx_block_lock_dclk_1;
  pcs64_cdc_sync i_pcs64_core_cdc_sync_stat_rx_block_lock_dclk_1
  (
   .clk              (dclk),
   .signal_in        (stat_rx_block_lock_1), 
   .signal_out       (stat_rx_block_lock_dclk_1)
  );

  pcs64_cdc_sync i_pcs64_core_cdc_sync_watchdog_barking_sync_1
  (
   .clk              (dclk),
   .signal_in        (master_watchdog_barking_1), 
   .signal_out       (master_watchdog_barking_sync_1)
  );
  always @(posedge dclk)
  begin
    if ((tx_reset_done_sync_dclk_1 == 1'b0 && rx_reset_done_sync_dclk_1 == 1'b0 && stat_rx_block_lock_dclk_1 == 1'b1) || master_watchdog_1 == 0 || ctl_rx_prbs31_test_pattern_enable_1 == 1'b1)
      master_watchdog_1 <= MASTER_WATCHDOG_TIMER_RESET;
    else
      master_watchdog_1 <= master_watchdog_1 - 1;
    end

  wire ctl_rx_wdt_disable_sync_1;
  pcs64_cdc_sync i_pcs64_core_cdc_sync_axi_ctl_rx_wdt_disable_1
  (
   .clk              (dclk),
  
   .signal_in        (ctl_rx_wdt_disable_1), 

   .signal_out       (ctl_rx_wdt_disable_sync_1)
  );

  always @(posedge dclk)
  begin
    if (master_watchdog_1 == 0 && ctl_rx_wdt_disable_sync_1 == 0)
      master_watchdog_barking_1 <= 1'b1;
    else
      master_watchdog_barking_1 <= 1'b0;
  end

  assign tx_mii_clk_1     =  gtwiz_userclk_tx_usrclk2_out_1;
  assign rx_clk_out_1     =  gtwiz_userclk_rx_usrclk2_out_1;
  assign gt_txusrclk2_1   =  gtwiz_userclk_tx_usrclk2_out_1;
  assign gt_rxusrclk2_1   =  gtwiz_userclk_rx_usrclk2_out_1;
  wire [63:0]     tx_serdes_data0_1;
  wire [63:0]     tx_serdes_data0_int_1;
  wire [1:0]      tx_serdes_header0_1;
  wire [1:0]      tx_serdes_header0_int_1;
  wire [1:0]      tx_serdes_headervalid0_1;

  wire [63:0]     rx_serdes_data0_1;
  wire [1:0]      rx_serdes_header0_1;
  wire [63:0]     rx_serdes_data0_int_1;
  wire [1:0]      rx_serdes_header0_int_1;
  wire [0:0]      rx_serdes_bitslip_1 ;
  wire [0:0]      rx_serdes_headervalid_1 ;
  wire [0:0]      rx_serdes_datavalid_1 ;
  wire [0:0]      rx_serdes_headervalid_int_1;
  wire [0:0]      rx_serdes_datavalid_int_1;
  pcs64_cdc_sync i_pcs64_core_cdc_sync_gt_tx_resetdone_1
  (
   .clk              (gt_txusrclk2_1),
   .signal_in        (gtwiz_reset_tx_done_int_1), 
   .signal_out       (gtwiz_reset_tx_done_int_sync_1)
  );

  assign gtwiz_reset_tx_done_int_sync_inv_1   =  ~(gtwiz_reset_tx_done_int_sync_1);
  assign tx_reset_done_async_1                =  gtwiz_reset_tx_done_int_sync_inv_1 | tx_reset_1;
  assign user_tx_reset_1                      =  tx_reset_done_async_1;

  pcs64_cdc_sync i_pcs64_core_cdc_sync_gt_rx_resetdone_1
  (
   .clk              (gt_rxusrclk2_1),
   .signal_in        (gtwiz_reset_rx_done_int_1), 
   .signal_out       (gtwiz_reset_rx_done_int_sync_1)
  );

  assign gtwiz_reset_rx_done_int_sync_inv_1   =  ~(gtwiz_reset_rx_done_int_sync_1);
  assign rx_reset_done_async_1                =  gtwiz_reset_rx_done_int_sync_inv_1 | rx_reset_1;
 

 
  pcs64_cdc_sync i_pcs64_core_cdc_sync_gt_rx_serdes_resetdone_1
  (
   .clk              (rx_serdes_clk_1),
   .signal_in        (rx_reset_done_async_1), 
   .signal_out       (rx_serdes_reset_done_1)
  );
  
  pcs64_cdc_sync i_pcs64_core_cdc_sync_gt_rxreset_1
  (
   .clk              (rx_core_clk_1),
   .signal_in        (rx_reset_done_async_1), 
   .signal_out       (rx_reset_done_1)
  );


  assign user_rx_reset_1                      =  rx_reset_done_1;


  assign rx_serdes_clk_1                      =  gtwiz_userclk_rx_usrclk2_out_1;
 

 
  assign txdata_in_1                          =  {64'b0,tx_serdes_data0_int_1};
  assign txheader_in_1                        =  {4'b0,tx_serdes_header0_int_1};

 pcs64_gt_pipeline 
  #(
    .WIDTH        (64)
  ) i_pcs64_tx_64bit_gt_pipeline_serdes_data0_1 (
    .clk          (gt_txusrclk2_1),
    .data_in      (tx_serdes_data0_1),
    .data_out     (tx_serdes_data0_int_1)
  );

  pcs64_gt_pipeline 
  #(
    .WIDTH        (2)
  ) i_pcs64_tx_2bit_gt_pipeline_serdes_data0_1 (
    .clk          (gt_txusrclk2_1),
    .data_in      (tx_serdes_header0_1),
    .data_out     (tx_serdes_header0_int_1)
  );

   assign rx_serdes_data0_int_1             =  rxdata_out_1[63:0];
   assign rx_serdes_header0_int_1           =  rxheader_out_1[1:0];
   assign rxgearboxslip_in_1                =  rx_serdes_bitslip_1;
   assign rx_serdes_datavalid_int_1         =  rxdatavalid_out_1[0];
   assign rx_serdes_headervalid_int_1       =  rxheadervalid_out_1;


  pcs64_gt_pipeline 
  #(
    .WIDTH        (64)
  ) i_pcs64_rx_64bit_gt_pipeline_serdes_data0_1 (
    .clk          (rx_serdes_clk_1),
    .data_in      (rx_serdes_data0_int_1),
    .data_out     (rx_serdes_data0_1)
  );

  pcs64_gt_pipeline 
  #(
    .WIDTH        (2)
  ) i_pcs64_rx_2bit_gt_pipeline_serdes_header0_1 (
    .clk          (rx_serdes_clk_1),
    .data_in      (rx_serdes_header0_int_1),
    .data_out     (rx_serdes_header0_1)
  );

  pcs64_gt_pipeline 
  #(
    .WIDTH        (1)
  ) i_pcs64_rx_2bit_gt_pipeline_serdes_data_valid0_1 (
    .clk          (rx_serdes_clk_1),
    .data_in      (rx_serdes_datavalid_int_1),
    .data_out     (rx_serdes_datavalid_1)
  );
  pcs64_gt_pipeline 
  #(
    .WIDTH        (1)
  ) i_pcs64_rx_2bit_gt_pipeline_serdes_header_valid0_1 (
    .clk          (rx_serdes_clk_1),
    .data_in      (rx_serdes_headervalid_int_1),
    .data_out     (rx_serdes_headervalid_1)
  );

pcs64_top #(
  .SERDES_WIDTH ( 64 )
) i_pcs64_top_1 (
  .tx_mii_reset (tx_reset_done_async_1),
  .rx_mii_clk (rx_core_clk_1),
  .rx_mii_reset (rx_reset_done_1),
  .tx_serdes_refclk (gt_txusrclk2_1),
  .tx_serdes_refclk_reset (tx_reset_done_async_1),
  .rx_serdes_clk (rx_serdes_clk_1),
  .rx_serdes_reset (rx_serdes_reset_done_1),
//// RX AXIS Signals
  .rx_mii_d (rx_mii_d_1),
  .rx_mii_c (rx_mii_c_1),

//// RX Control Signals
  .ctl_rx_test_pattern (ctl_rx_test_pattern_1),
  .ctl_rx_test_pattern_enable (ctl_rx_test_pattern_enable_1),
  .ctl_rx_data_pattern_select (ctl_rx_data_pattern_select_1),
  .ctl_rx_prbs31_test_pattern_enable (ctl_rx_prbs31_test_pattern_enable_1),


//// RX Stats Signals
  .stat_rx_status  (stat_rx_status_1),
  .stat_rx_block_lock (stat_rx_block_lock_1),
  .stat_rx_framing_err_valid (stat_rx_framing_err_valid_1),
  .stat_rx_framing_err (stat_rx_framing_err_1),
  .stat_rx_hi_ber (stat_rx_hi_ber_1),
  .stat_rx_valid_ctrl_code (stat_rx_valid_ctrl_code_1),
  .stat_rx_bad_code (stat_rx_bad_code_1),
  .stat_rx_bad_code_valid (stat_rx_bad_code_valid_1),
  .stat_rx_error_valid (stat_rx_error_valid_1),
  .stat_rx_error (stat_rx_error_1),
  .stat_rx_fifo_error (stat_rx_fifo_error_1),
  .stat_rx_local_fault (stat_rx_local_fault_1),


//// TX AXIS Signals
  .tx_mii_d (tx_mii_d_1),
  .tx_mii_c (tx_mii_c_1),

//// TX Control Signals
  .ctl_tx_test_pattern (ctl_tx_test_pattern_1),
  .ctl_tx_test_pattern_enable (ctl_tx_test_pattern_enable_1),
  .ctl_tx_test_pattern_select (ctl_tx_test_pattern_select_1),
  .ctl_tx_data_pattern_select (ctl_tx_data_pattern_select_1),
  .ctl_tx_test_pattern_seed_a (ctl_tx_test_pattern_seed_a_1),
  .ctl_tx_test_pattern_seed_b (ctl_tx_test_pattern_seed_b_1),
  .ctl_tx_prbs31_test_pattern_enable (ctl_tx_prbs31_test_pattern_enable_1),


//// TX Stats Signals
  .stat_tx_local_fault (stat_tx_local_fault_1),



  .rx_serdes_datavalid0              (rx_serdes_datavalid_1),
  .rx_serdes_headervalid0            (rx_serdes_headervalid_1),
  .rx_serdes_bitslip0                (rx_serdes_bitslip_1),

  .rx_serdes_data0                   (rx_serdes_data0_1),
  .rx_serdes_header0                 (rx_serdes_header0_1),
  .tx_serdes_data0                   (tx_serdes_data0_1),
  .tx_serdes_header0                 (tx_serdes_header0_1)


);


endmodule




(* DowngradeIPIdentifiedWarnings="yes" *)
  module pcs64_cdc_sync (
   input clk,
   input signal_in,
   output wire signal_out
  );
                               wire sig_in_cdc_from ;
      (* ASYNC_REG = "TRUE" *) reg  s_out_d2_cdc_to;
      (* ASYNC_REG = "TRUE" *) reg  s_out_d3;
      (* max_fanout = 500 *)   reg  s_out_d4;
      
// synthesis translate_off
      
      initial s_out_d2_cdc_to = 1'b0;
      initial s_out_d3        = 1'b0;
      initial s_out_d4        = 1'b0;
      
// synthesis translate_on   
   
      assign sig_in_cdc_from = signal_in;
      assign signal_out      = s_out_d4;
      
      always @(posedge clk) 
      begin
        s_out_d4         <= s_out_d3;
        s_out_d3         <= s_out_d2_cdc_to;
        s_out_d2_cdc_to  <= sig_in_cdc_from;
      end
  
  endmodule



  (* DowngradeIPIdentifiedWarnings="yes" *)
  module pcs64_multibit_cdc_sync (
   input clk,
   input [3:0] signal_in,
   output wire [3:0] signal_out
  );
                               wire [3:0] sig_in_cdc_from ;
      (* ASYNC_REG = "TRUE" *) reg [3:0] s_out_d2_cdc_to;
      (* ASYNC_REG = "TRUE" *) reg [3:0] s_out_d3;
                               reg [3:0] s_out_d4;
      
// synthesis translate_off
      
      initial s_out_d2_cdc_to = 4'b0;
      initial s_out_d3        = 4'b0;
      initial s_out_d4        = 4'b0;
      
// synthesis translate_on   
   
      assign sig_in_cdc_from = signal_in;
      assign signal_out      = s_out_d4;
      
      always @(posedge clk) 
      begin
        s_out_d4         <= s_out_d3;
        s_out_d3         <= s_out_d2_cdc_to;
        s_out_d2_cdc_to  <= sig_in_cdc_from;
      end
  
  endmodule



(* DowngradeIPIdentifiedWarnings="yes" *)
module pcs64_gt_pipeline
#(
 parameter WIDTH  = 1
)
(
 input  clk,
 input  [WIDTH-1:0] data_in,
 output wire [WIDTH-1:0]  data_out
);
    
    reg  [WIDTH-1:0] data_out_1d;
    reg  [WIDTH-1:0] data_out_2d;
    
    assign data_out      = data_out_2d;
    
    always @(posedge clk) 
    begin
        data_out_2d      <= data_out_1d;
        data_out_1d      <= data_in;
    end

endmodule


