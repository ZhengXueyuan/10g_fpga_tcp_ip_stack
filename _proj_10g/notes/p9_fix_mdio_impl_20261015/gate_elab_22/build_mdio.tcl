# build_mdio.tcl -- build the VIO-driven MDIO probe for xcku5p-ffvb676-1-e.
#
# Run:  vivado -mode batch -source build_mdio.tcl -nojournal -nolog
#
# This is the first project built for the KU5P on this machine, so besides the
# bitstream it also produces the timing baseline (gate G) and prints WNS/WHS.

set here [file normalize [file dirname [info script]]]
set proj [file join $here pj_mdio]

create_project -force mdio_prj $proj -part xcku5p-ffvb676-1-e
set_property target_language Verilog [current_project]

add_files -norecurse [list \
    [file join $here rtl mdio_master.v] \
    [file join $here rtl mdio_vio_top.v] ]
add_files -fileset constrs_1 -norecurse [file join $here xdc ku5p_mdio.xdc]

set_property top mdio_vio_top [current_fileset]
update_compile_order -fileset sources_1

# VIO is the register window: this board has no UART, and instantiating XDMA
# just to poke a register would drag in PCIe, AXI and a clock domain for
# nothing. VIO talks over the same JTAG cable we already have.
#
# Widths must match the probe packing in mdio_vio_top.v.
create_ip -name vio -vendor xilinx.com -library ip -module_name vio_0
set_property -dict [list \
    CONFIG.C_NUM_PROBE_IN    {1}  \
    CONFIG.C_PROBE_IN0_WIDTH {22} \
    CONFIG.C_NUM_PROBE_OUT   {5}  \
    CONFIG.C_PROBE_OUT0_WIDTH {1}  \
    CONFIG.C_PROBE_OUT1_WIDTH {2}  \
    CONFIG.C_PROBE_OUT2_WIDTH {5}  \
    CONFIG.C_PROBE_OUT3_WIDTH {5}  \
    CONFIG.C_PROBE_OUT4_WIDTH {16} \
] [get_ips vio_0]
generate_target all [get_ips vio_0]

puts "=== SYNTH ==="
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "synth_1 failed"
}

puts "=== IMPL ==="
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "impl_1 failed"
}

open_run impl_1
report_timing_summary -file [file join $proj timing_summary.rpt] -warn_on_violation
puts "TIMING_WNS [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]"
puts "TIMING_WHS [get_property SLACK [get_timing_paths -delay_type min -max_paths 1]]"
puts "TIMING_TNS [get_property SLACK [get_timing_paths -delay_type max -max_paths 1 -nworst 100]]"

set bit [file join $proj mdio_prj.runs impl_1 mdio_vio_top.bit]
if {[file exists $bit]} {
    puts "BITSTREAM $bit"
    puts "BITSTREAM_BYTES [file size $bit]"
} else {
    error "bitstream not produced"
}
puts "=== BUILD DONE ==="
