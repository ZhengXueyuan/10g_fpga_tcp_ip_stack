open_checkpoint D:/repo/XCKU5PMini/udp_hls_10g/vivado_prj/p7b_ku5p_prj.runs/synth_1/wrapper_p4.dcp
puts "=== MMCM cells ==="
foreach c [get_cells -hier -quiet -filter {REF_NAME =~ MMCME4*}] {
    puts "CELL [get_property NAME $c] REF=[get_property REF_NAME $c]"
}
puts "=== CLKOUT0 pins ==="
foreach p [get_pins -hier -quiet -filter {NAME =~ *CLKOUT0}] {
    puts "PIN [get_property NAME $p]"
}
puts "=== BUFG cells ==="
foreach c [get_cells -hier -quiet -filter {REF_NAME =~ BUFG*}] {
    puts "BUFG [get_property NAME $c]"
}
close_design
exit 0
