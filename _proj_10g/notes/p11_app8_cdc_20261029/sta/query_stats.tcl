open_checkpoint D:/repo/XCKU5PMini/udp_hls_10g/vivado_prj/p7b_ku5p_prj.runs/impl_1/wrapper_p4_routed.dcp
puts "=== app stat regs (sample) ==="
set c [get_cells -hier -quiet -filter {NAME =~ *u_app/u_core/g_app[0]*stat_tx_bytes_reg*}]
puts "app0_stat_tx_bytes_cells=[llength $c]"
foreach x [lrange $c 0 2] { puts "  [get_property NAME $x]" }
puts "=== st_hold cells ==="
set h [get_cells -hier -quiet -filter {NAME =~ *u_app/st_hold_reg*}]
puts "st_hold_cells=[llength $h]"
set s [get_cells -hier -quiet -filter {NAME =~ *u_app/st_shadow_reg*}]
puts "st_shadow_cells=[llength $s]"
puts "=== core_tx_bytes net driver/loads ==="
set p [get_pins -hier -quiet -filter {NAME =~ *u_app/u_core/stat_tx_bytes*}]
puts "core_stat_tx_bytes_pins=[llength $p]"
foreach x [lrange $p 0 3] { puts "  PIN [get_property NAME $x]" }
close_design
exit 0
