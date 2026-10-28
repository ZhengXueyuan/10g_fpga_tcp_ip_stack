open_checkpoint D:/repo/XCKU5PMini/udp_hls_10g/vivado_prj/p7b_ku5p_prj.runs/impl_1/wrapper_p4_routed.dcp
set c [get_cells -hier -quiet -filter {NAME =~ *u_core/g_app*stat_tx_bytes_reg* && REF_NAME == FDCE}]
set c0 [lindex $c 0]
puts "cell=[get_property NAME $c0]"
foreach pin {C CE R D} {
  set ps [get_pins -quiet -of_objects $c0 -filter "REF_PIN_NAME == $pin"]
  if {[llength $ps] == 0} { puts "pin $pin none"; continue }
  set n [get_nets -quiet -of_objects [lindex $ps 0]]
  if {[llength $n] == 0} { puts "pin $pin nonet"; continue }
  set nn [lindex $n 0]
  set drv [get_pins -quiet -leaf -of_objects $nn -filter {DIRECTION == OUT}]
  puts "pin $pin net=[get_property NAME $nn]"
  foreach d [lrange $drv 0 2] { puts "   <- [get_property NAME $d] ref=[get_property REF_NAME $d]" }
}
close_design
exit 0
