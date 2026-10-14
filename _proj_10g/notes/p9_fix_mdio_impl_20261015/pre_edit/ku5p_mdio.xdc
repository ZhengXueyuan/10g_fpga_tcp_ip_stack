# ku5p_mdio.xdc -- VIO-driven MDIO probe on the XCKU5P Mini board.
#
# Pin provenance: the baseboard schematic gives net -> board-to-board connector
# pin (图纸/底板), the core board schematic gives connector pin -> FPGA ball
# (图纸/核心板). Crossing the two for all 15 RGMII nets reproduces the vendor
# PCIe.xdc assignment exactly, so that file is trustworthy for this block even
# though its SFP control pins were wrong (see AGENTS.md).

# --- 100 MHz system clock: Y1 differential oscillator (SG7050VAN-100.000000M),
#     SYS_CLK_P/N = T25/U25.
#
# Pin type is IO_L14P_T2L_N2_GC_A04_D20_65 / IO_L14N_T2L_N3_GC_A05_D21_65 --
# clock-capable (GC), bank/group **65**. Do NOT quote it as "GC_66": that name
# belongs to a different ball pair (H23/H24). Getting this wrong hides the fact
# that SYS_CLK lives in bank 65 (1.2 V, hence DIFF_POD12_DCI) while the RGMII
# and MDIO pins live in bank 86 (3.3 V, LVCMOS33) -- different banks, which is
# exactly why the two I/O standards do not conflict.
set_property -dict {PACKAGE_PIN T25 IOSTANDARD DIFF_POD12_DCI} [get_ports sys_clk_p]
set_property -dict {PACKAGE_PIN U25 IOSTANDARD DIFF_POD12_DCI} [get_ports sys_clk_n]
create_clock -period 10.000 -name sys_clk [get_ports sys_clk_p]

# --- RTL8211E management interface (baseboard net E_MDC / E_MDIO / E_RESET)
set_property -dict {PACKAGE_PIN G10 IOSTANDARD LVCMOS33} [get_ports eth_mdc]
set_property -dict {PACKAGE_PIN B9  IOSTANDARD LVCMOS33} [get_ports eth_mdio]
set_property -dict {PACKAGE_PIN A9  IOSTANDARD LVCMOS33} [get_ports eth_rstn]

# --- QSPI boot settings, copied verbatim from the vendor PCIe.xdc.
# This design is only ever loaded over JTAG, but keeping the flash parameters
# identical means the bitstream stays QSPI-compatible if that is ever wanted.
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 51.0 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
