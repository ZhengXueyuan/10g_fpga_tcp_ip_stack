# p7bchain_src.f -- DECLARED compile file list for the p7b_chain gate (#22, P1 round).
#   gate bat : _proj_10g/p7b_chain/sim/run_tb_p7b_chain.bat
#   config   : P7B_10G + P7B_SIM_NOPCS + PCIE_OBS + DEV_USP + APP_MODE +
#              DP_156MHZ + P6B_SIM_CLKGEN + UDP_TX_OVL + TCP_TX_OVL
#              (the board build body: build_p7b_ku5p.tcl:286 + sim-only macros).
#
#   SCOPE OF THIS MANIFEST (read before quoting it):
#     * p4gate.py manifestcheck compares this list against the .v tokens that
#       appear LITERALLY on the gate bat's xvlog line. Every non-HLS compile
#       unit is in that literal list, so it is covered here.
#     * The HLS slow-path netlist (173 generated .v files under
#       hls/slowstack_prj/solution1/syn/verilog) is passed as a generated
#       `-f hls_p7bchain.f` list at run time and is therefore NOT visible to
#       manifestcheck. Pinning 173 generated names here would rot on every HLS
#       rebuild; the HLS inputs are pinned by the hls tree itself.
#     * Mutation runs (P7B_MUT=...) substitute wrapper_p4.v / MAC rtl and are
#       not expressible in this manifest -- they are standalone runs.
#   Entries are repo-relative; manifestcheck asserts this list == the literal
#   list in the gate .bat.
rtl/app_ctrl.v
rtl/app_pattern.v
rtl/app_rx_mirror.v
rtl/app_status_uart.v
rtl/app_udp_pattern.v
rtl/aximm_c2h_win.v
rtl/aximm_h2c_discard.v
rtl/axis_c2h_stream.v
rtl/axis_pipe.v
rtl/checksum16.v
rtl/clk_gen_p6b.v
rtl/crc32_8b.v
rtl/fifo_async.v
rtl/fifo_sync.v
rtl/frame_fifo.v
rtl/mac_rx_64.v
rtl/mac_tx_64.v
rtl/mir_dma_ring.v
rtl/mir_uram_fifo.v
rtl/retx_ram.v
rtl/rx_classify.v
rtl/slow_cfg_adp.v
rtl/slow_rx_adp.v
rtl/slow_tx_adp.v
rtl/snap_cdc.v
rtl/snap_seq.v
rtl/tcb.v
rtl/tcp_cam.v
rtl/tcp_echo.v
rtl/tcp_rx.v
rtl/tcp_synp.v
rtl/tcp_tx_frame.v
rtl/tx_arb.v
rtl/udp_echo.v
rtl/udp_rx.v
rtl/udp_split.v
rtl/udp_tx_cfg.v
rtl/udp_tx_frame.v
rtl/vlan_strip.v
board/wrapper_p4.v
board/util_gmii_to_rgmii_us.v
board/uart_dbg.v
board/p7b_pcs_stub.v
_proj_pcie/rtl/axi_regs.v
_proj_10g/p7b_mac/rtl/crc32_64.v
_proj_10g/p7b_mac/rtl/mac_rx_10g.v
_proj_10g/p7b_mac/rtl/mac_tx_10g.v
sim/p6e_pcie/xdma_0_sim_stub.v
_proj_10g/p7b_chain/sim/tb_p7b_chain.v
