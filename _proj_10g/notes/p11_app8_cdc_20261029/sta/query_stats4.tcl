open_checkpoint D:/repo/XCKU5PMini/udp_hls_10g/vivado_prj/p7b_ku5p_prj.runs/impl_1/wrapper_p4_routed.dcp
proc drivers {netname} {
  set n [get_nets -quiet -filter "NAME == $netname"]
  if {[llength $n] == 0} { puts "net $netname NOT FOUND"; return }
  set ps [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == OUT}]
  foreach p $ps { puts "  drv $netname <- [get_property NAME $p]" }
  puts "  loads=[llength [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == IN}]]"
}
puts "=== core_tx_bytes[0] driver ==="
drivers "u_app/core_tx_bytes[0]"
puts "=== st_shadow clock ==="
set sh [get_cells -hier -quiet -filter {NAME =~ *u_app/st_shadow_reg*}]
set c [lindex $sh 0]
set cp [get_pins -quiet -of_objects $c -filter {REF_PIN_NAME == "C"}]
set cn [get_nets -quiet -of_objects [lindex $cp 0]]
puts "st_shadow_first=[get_property NAME $c] clk=[get_property NAME [lindex $cn 0]]"
puts "=== app0 stat_tx_bytes_reg[0] ==="
set a [get_cells -hier -quiet -filter {NAME =~ *u_core/g_app*stat_tx_bytes_reg*}]
puts "cells=[llength $a]"
foreach x [lrange $a 0 3] { puts "  [get_property NAME $x] ref=[get_property REF_NAME $x]" }
set a0 [lindex $a 0]
foreach pin {C CE D Q} {
  set p [get_pins -quiet -of_objects $a0 -filter "REF_PIN_NAME == $pin"]
  if {[llength $p] > 0} {
    set nn [get_nets -quiet -of_objects [lindex $p 0]]
    set drv [get_pins -quiet -leaf -of_objects [lindex $nn 0] -filter {DIRECTION == OUT}]
    puts "  pin $pin net=[get_property NAME [lindex $nn 0]] drv=[llength $drv]"
    foreach d [lrange $drv 0 2] { puts "     <- [get_property NAME $d]" }
  }
}
close_design
exit 0
