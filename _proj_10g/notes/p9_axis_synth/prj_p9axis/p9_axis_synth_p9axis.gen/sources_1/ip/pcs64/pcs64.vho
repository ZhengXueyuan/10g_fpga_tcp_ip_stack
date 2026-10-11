-- (c) Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- (c) Copyright 2022-2026 Advanced Micro Devices, Inc. All rights reserved.
-- 
-- This file contains confidential and proprietary information
-- of AMD and is protected under U.S. and international copyright
-- and other intellectual property laws.
-- 
-- DISCLAIMER
-- This disclaimer is not a license and does not grant any
-- rights to the materials distributed herewith. Except as
-- otherwise provided in a valid license issued to you by
-- AMD, and to the maximum extent permitted by applicable
-- law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
-- WITH ALL FAULTS, AND AMD HEREBY DISCLAIMS ALL WARRANTIES
-- AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
-- BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
-- INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
-- (2) AMD shall not be liable (whether in contract or tort,
-- including negligence, or under any other theory of
-- liability) for any loss or damage of any kind or nature
-- related to, arising under or in connection with these
-- materials, including for any direct, or any indirect,
-- special, incidental, or consequential loss or damage
-- (including loss of data, profits, goodwill, or any type of
-- loss or damage suffered as a result of any action brought
-- by a third party) even if such damage or loss was
-- reasonably foreseeable or AMD had been advised of the
-- possibility of the same.
-- 
-- CRITICAL APPLICATIONS
-- AMD products are not designed or intended to be fail-
-- safe, or for use in any application requiring fail-safe
-- performance, such as life-support or safety devices or
-- systems, Class III medical devices, nuclear facilities,
-- applications related to the deployment of airbags, or any
-- other applications that could lead to death, personal
-- injury, or severe property or environmental damage
-- (individually and collectively, "Critical
-- Applications"). Customer assumes the sole risk and
-- liability of any use of AMD products in Critical
-- Applications, subject only to applicable laws and
-- regulations governing limitations on product liability.
-- 
-- THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
-- PART OF THIS FILE AT ALL TIMES.
-- 
-- DO NOT MODIFY THIS FILE.
-- IP VLNV: xilinx.com:ip:xxv_ethernet:5.0
-- IP Revision: 2

-- The following code must appear in the VHDL architecture header.

------------- Begin Cut here for COMPONENT Declaration ------ COMP_TAG
COMPONENT pcs64
  PORT (
    gt_rxp_in_0 : IN STD_LOGIC;
    gt_rxp_in_1 : IN STD_LOGIC;
    gt_rxn_in_0 : IN STD_LOGIC;
    gt_rxn_in_1 : IN STD_LOGIC;
    gt_txp_out_0 : OUT STD_LOGIC;
    gt_txp_out_1 : OUT STD_LOGIC;
    gt_txn_out_0 : OUT STD_LOGIC;
    gt_txn_out_1 : OUT STD_LOGIC;
    rx_core_clk_0 : IN STD_LOGIC;
    rx_core_clk_1 : IN STD_LOGIC;
    txoutclksel_in_0 : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    rxoutclksel_in_0 : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    txoutclksel_in_1 : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    rxoutclksel_in_1 : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    gtwiz_reset_tx_datapath_0 : IN STD_LOGIC;
    gtwiz_reset_tx_datapath_1 : IN STD_LOGIC;
    gtwiz_reset_rx_datapath_0 : IN STD_LOGIC;
    gtwiz_reset_rx_datapath_1 : IN STD_LOGIC;
    rxrecclkout_0 : OUT STD_LOGIC;
    rxrecclkout_1 : OUT STD_LOGIC;
    sys_reset : IN STD_LOGIC;
    dclk : IN STD_LOGIC;
    tx_mii_clk_0 : OUT STD_LOGIC;
    tx_mii_clk_1 : OUT STD_LOGIC;
    rx_clk_out_0 : OUT STD_LOGIC;
    rx_clk_out_1 : OUT STD_LOGIC;
    gt_refclk_p : IN STD_LOGIC;
    gt_refclk_n : IN STD_LOGIC;
    gt_refclk_out : OUT STD_LOGIC;
    gtpowergood_out_0 : OUT STD_LOGIC;
    gtpowergood_out_1 : OUT STD_LOGIC;
    rx_reset_0 : IN STD_LOGIC;
    rx_reset_1 : IN STD_LOGIC;
    user_rx_reset_0 : OUT STD_LOGIC;
    user_rx_reset_1 : OUT STD_LOGIC;
    rx_mii_d_0 : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
    rx_mii_d_1 : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
    rx_mii_c_0 : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    rx_mii_c_1 : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    ctl_rx_test_pattern_0 : IN STD_LOGIC;
    ctl_rx_test_pattern_1 : IN STD_LOGIC;
    ctl_rx_data_pattern_select_0 : IN STD_LOGIC;
    ctl_rx_data_pattern_select_1 : IN STD_LOGIC;
    ctl_rx_test_pattern_enable_0 : IN STD_LOGIC;
    ctl_rx_test_pattern_enable_1 : IN STD_LOGIC;
    ctl_rx_prbs31_test_pattern_enable_0 : IN STD_LOGIC;
    ctl_rx_prbs31_test_pattern_enable_1 : IN STD_LOGIC;
    stat_rx_framing_err_0 : OUT STD_LOGIC;
    stat_rx_framing_err_1 : OUT STD_LOGIC;
    stat_rx_framing_err_valid_0 : OUT STD_LOGIC;
    stat_rx_framing_err_valid_1 : OUT STD_LOGIC;
    stat_rx_local_fault_0 : OUT STD_LOGIC;
    stat_rx_local_fault_1 : OUT STD_LOGIC;
    stat_rx_block_lock_0 : OUT STD_LOGIC;
    stat_rx_block_lock_1 : OUT STD_LOGIC;
    stat_rx_valid_ctrl_code_0 : OUT STD_LOGIC;
    stat_rx_valid_ctrl_code_1 : OUT STD_LOGIC;
    stat_rx_status_0 : OUT STD_LOGIC;
    stat_rx_status_1 : OUT STD_LOGIC;
    stat_rx_hi_ber_0 : OUT STD_LOGIC;
    stat_rx_hi_ber_1 : OUT STD_LOGIC;
    stat_rx_bad_code_0 : OUT STD_LOGIC;
    stat_rx_bad_code_1 : OUT STD_LOGIC;
    stat_rx_bad_code_valid_0 : OUT STD_LOGIC;
    stat_rx_bad_code_valid_1 : OUT STD_LOGIC;
    stat_rx_error_0 : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    stat_rx_error_1 : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    stat_rx_error_valid_0 : OUT STD_LOGIC;
    stat_rx_error_valid_1 : OUT STD_LOGIC;
    stat_rx_fifo_error_0 : OUT STD_LOGIC;
    stat_rx_fifo_error_1 : OUT STD_LOGIC;
    tx_reset_0 : IN STD_LOGIC;
    tx_reset_1 : IN STD_LOGIC;
    user_tx_reset_0 : OUT STD_LOGIC;
    user_tx_reset_1 : OUT STD_LOGIC;
    tx_mii_d_0 : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    tx_mii_d_1 : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    tx_mii_c_0 : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    tx_mii_c_1 : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    stat_tx_local_fault_0 : OUT STD_LOGIC;
    stat_tx_local_fault_1 : OUT STD_LOGIC;
    ctl_tx_test_pattern_0 : IN STD_LOGIC;
    ctl_tx_test_pattern_1 : IN STD_LOGIC;
    ctl_tx_test_pattern_enable_0 : IN STD_LOGIC;
    ctl_tx_test_pattern_enable_1 : IN STD_LOGIC;
    ctl_tx_test_pattern_select_0 : IN STD_LOGIC;
    ctl_tx_test_pattern_select_1 : IN STD_LOGIC;
    ctl_tx_data_pattern_select_0 : IN STD_LOGIC;
    ctl_tx_data_pattern_select_1 : IN STD_LOGIC;
    ctl_tx_test_pattern_seed_a_0 : IN STD_LOGIC_VECTOR(57 DOWNTO 0);
    ctl_tx_test_pattern_seed_a_1 : IN STD_LOGIC_VECTOR(57 DOWNTO 0);
    ctl_tx_test_pattern_seed_b_0 : IN STD_LOGIC_VECTOR(57 DOWNTO 0);
    ctl_tx_test_pattern_seed_b_1 : IN STD_LOGIC_VECTOR(57 DOWNTO 0);
    ctl_tx_prbs31_test_pattern_enable_0 : IN STD_LOGIC;
    ctl_tx_prbs31_test_pattern_enable_1 : IN STD_LOGIC;
    gt_loopback_in_0 : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    gt_loopback_in_1 : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    qpllreset_in_0 : IN STD_LOGIC;
    ctl_rx_wdt_disable_0 : IN STD_LOGIC;
    ctl_rx_wdt_disable_1 : IN STD_LOGIC 
  );
END COMPONENT;
-- COMP_TAG_END ------ End COMPONENT Declaration ------------

-- The following code must appear in the VHDL architecture
-- body. Substitute your own instance name and net names.

------------- Begin Cut here for INSTANTIATION Template ----- INST_TAG
your_instance_name : pcs64
  PORT MAP (
    gt_rxp_in_0 => gt_rxp_in_0,
    gt_rxp_in_1 => gt_rxp_in_1,
    gt_rxn_in_0 => gt_rxn_in_0,
    gt_rxn_in_1 => gt_rxn_in_1,
    gt_txp_out_0 => gt_txp_out_0,
    gt_txp_out_1 => gt_txp_out_1,
    gt_txn_out_0 => gt_txn_out_0,
    gt_txn_out_1 => gt_txn_out_1,
    rx_core_clk_0 => rx_core_clk_0,
    rx_core_clk_1 => rx_core_clk_1,
    txoutclksel_in_0 => txoutclksel_in_0,
    rxoutclksel_in_0 => rxoutclksel_in_0,
    txoutclksel_in_1 => txoutclksel_in_1,
    rxoutclksel_in_1 => rxoutclksel_in_1,
    gtwiz_reset_tx_datapath_0 => gtwiz_reset_tx_datapath_0,
    gtwiz_reset_tx_datapath_1 => gtwiz_reset_tx_datapath_1,
    gtwiz_reset_rx_datapath_0 => gtwiz_reset_rx_datapath_0,
    gtwiz_reset_rx_datapath_1 => gtwiz_reset_rx_datapath_1,
    rxrecclkout_0 => rxrecclkout_0,
    rxrecclkout_1 => rxrecclkout_1,
    sys_reset => sys_reset,
    dclk => dclk,
    tx_mii_clk_0 => tx_mii_clk_0,
    tx_mii_clk_1 => tx_mii_clk_1,
    rx_clk_out_0 => rx_clk_out_0,
    rx_clk_out_1 => rx_clk_out_1,
    gt_refclk_p => gt_refclk_p,
    gt_refclk_n => gt_refclk_n,
    gt_refclk_out => gt_refclk_out,
    gtpowergood_out_0 => gtpowergood_out_0,
    gtpowergood_out_1 => gtpowergood_out_1,
    rx_reset_0 => rx_reset_0,
    rx_reset_1 => rx_reset_1,
    user_rx_reset_0 => user_rx_reset_0,
    user_rx_reset_1 => user_rx_reset_1,
    rx_mii_d_0 => rx_mii_d_0,
    rx_mii_d_1 => rx_mii_d_1,
    rx_mii_c_0 => rx_mii_c_0,
    rx_mii_c_1 => rx_mii_c_1,
    ctl_rx_test_pattern_0 => ctl_rx_test_pattern_0,
    ctl_rx_test_pattern_1 => ctl_rx_test_pattern_1,
    ctl_rx_data_pattern_select_0 => ctl_rx_data_pattern_select_0,
    ctl_rx_data_pattern_select_1 => ctl_rx_data_pattern_select_1,
    ctl_rx_test_pattern_enable_0 => ctl_rx_test_pattern_enable_0,
    ctl_rx_test_pattern_enable_1 => ctl_rx_test_pattern_enable_1,
    ctl_rx_prbs31_test_pattern_enable_0 => ctl_rx_prbs31_test_pattern_enable_0,
    ctl_rx_prbs31_test_pattern_enable_1 => ctl_rx_prbs31_test_pattern_enable_1,
    stat_rx_framing_err_0 => stat_rx_framing_err_0,
    stat_rx_framing_err_1 => stat_rx_framing_err_1,
    stat_rx_framing_err_valid_0 => stat_rx_framing_err_valid_0,
    stat_rx_framing_err_valid_1 => stat_rx_framing_err_valid_1,
    stat_rx_local_fault_0 => stat_rx_local_fault_0,
    stat_rx_local_fault_1 => stat_rx_local_fault_1,
    stat_rx_block_lock_0 => stat_rx_block_lock_0,
    stat_rx_block_lock_1 => stat_rx_block_lock_1,
    stat_rx_valid_ctrl_code_0 => stat_rx_valid_ctrl_code_0,
    stat_rx_valid_ctrl_code_1 => stat_rx_valid_ctrl_code_1,
    stat_rx_status_0 => stat_rx_status_0,
    stat_rx_status_1 => stat_rx_status_1,
    stat_rx_hi_ber_0 => stat_rx_hi_ber_0,
    stat_rx_hi_ber_1 => stat_rx_hi_ber_1,
    stat_rx_bad_code_0 => stat_rx_bad_code_0,
    stat_rx_bad_code_1 => stat_rx_bad_code_1,
    stat_rx_bad_code_valid_0 => stat_rx_bad_code_valid_0,
    stat_rx_bad_code_valid_1 => stat_rx_bad_code_valid_1,
    stat_rx_error_0 => stat_rx_error_0,
    stat_rx_error_1 => stat_rx_error_1,
    stat_rx_error_valid_0 => stat_rx_error_valid_0,
    stat_rx_error_valid_1 => stat_rx_error_valid_1,
    stat_rx_fifo_error_0 => stat_rx_fifo_error_0,
    stat_rx_fifo_error_1 => stat_rx_fifo_error_1,
    tx_reset_0 => tx_reset_0,
    tx_reset_1 => tx_reset_1,
    user_tx_reset_0 => user_tx_reset_0,
    user_tx_reset_1 => user_tx_reset_1,
    tx_mii_d_0 => tx_mii_d_0,
    tx_mii_d_1 => tx_mii_d_1,
    tx_mii_c_0 => tx_mii_c_0,
    tx_mii_c_1 => tx_mii_c_1,
    stat_tx_local_fault_0 => stat_tx_local_fault_0,
    stat_tx_local_fault_1 => stat_tx_local_fault_1,
    ctl_tx_test_pattern_0 => ctl_tx_test_pattern_0,
    ctl_tx_test_pattern_1 => ctl_tx_test_pattern_1,
    ctl_tx_test_pattern_enable_0 => ctl_tx_test_pattern_enable_0,
    ctl_tx_test_pattern_enable_1 => ctl_tx_test_pattern_enable_1,
    ctl_tx_test_pattern_select_0 => ctl_tx_test_pattern_select_0,
    ctl_tx_test_pattern_select_1 => ctl_tx_test_pattern_select_1,
    ctl_tx_data_pattern_select_0 => ctl_tx_data_pattern_select_0,
    ctl_tx_data_pattern_select_1 => ctl_tx_data_pattern_select_1,
    ctl_tx_test_pattern_seed_a_0 => ctl_tx_test_pattern_seed_a_0,
    ctl_tx_test_pattern_seed_a_1 => ctl_tx_test_pattern_seed_a_1,
    ctl_tx_test_pattern_seed_b_0 => ctl_tx_test_pattern_seed_b_0,
    ctl_tx_test_pattern_seed_b_1 => ctl_tx_test_pattern_seed_b_1,
    ctl_tx_prbs31_test_pattern_enable_0 => ctl_tx_prbs31_test_pattern_enable_0,
    ctl_tx_prbs31_test_pattern_enable_1 => ctl_tx_prbs31_test_pattern_enable_1,
    gt_loopback_in_0 => gt_loopback_in_0,
    gt_loopback_in_1 => gt_loopback_in_1,
    qpllreset_in_0 => qpllreset_in_0,
    ctl_rx_wdt_disable_0 => ctl_rx_wdt_disable_0,
    ctl_rx_wdt_disable_1 => ctl_rx_wdt_disable_1
  );
-- INST_TAG_END ------ End INSTANTIATION Template ---------

-- You must compile the wrapper file pcs64.vhd when simulating
-- the core, pcs64. When compiling the wrapper file, be sure to
-- reference the VHDL simulation library.



