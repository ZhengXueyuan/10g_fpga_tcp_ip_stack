open_checkpoint D:/repo/XCKU5PMini/udp_hls_10g/vivado_prj/p7b_ku5p_prj.runs/impl_1/wrapper_p4_routed.dcp
set cells [get_cells -hier -quiet -filter {NAME =~ *u_app/st_hold_reg*}]
set c [lindex $cells 0]
puts "cell=[get_property NAME $c]"
foreach pin {C CE R D} {
  set ps [get_pins -quiet -of_objects $c -filter "REF_PIN_NAME == $pin"]
  if {[llength $ps] == 0} { puts "pin $pin none"; continue }
  set n [get_nets -quiet -of_objects [lindex $ps 0]]
  if {[llength $n] == 0} { puts "pin $pin nonet"; continue }
  set nn [lindex $n 0]
  set drv [get_pins -quiet -leaf -of_objects $nn -filter {DIRECTION == OUT}]
  puts "pin $pin net=[get_property NAME $nn] drv=[llength $drv]"
  foreach d [lrange $drv 0 2] { puts "    <- [get_property NAME $d] ref=[get_property REF_NAME $d]" }
}
# shadow CE
set sc [lindex [get_cells -hier -quiet -filter {NAME =~ *u_app/st_shadow_reg*}] 0]
puts "shadow=[get_property NAME $sc]"
foreach pin {C CE D R} {
  set ps [get_pins -quiet -of_objects $sc -filter "REF_PIN_NAME == $pin"]
  if {[llength $ps] == 0} { puts "s pin $pin none"; continue }
  set n [get_nets -quiet -of_objects [lindex $ps 0]]
  if {[llength $n] == 0} { puts "s pin $pin nonet"; continue }
  puts "s pin $pin net=[get_property NAME [lindex $n 0]]"
}
close_design
exit 0
