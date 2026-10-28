open_checkpoint D:/repo/XCKU5PMini/udp_hls_10g/vivado_prj/p7b_ku5p_prj.runs/impl_1/wrapper_p4_routed.dcp
proc show {pat {pins {C CE R D Q}}} {
  set cs [get_cells -hier -quiet -filter "NAME =~ $pat"]
  puts "cells($pat)=[llength $cs]"
  set c [lindex $cs 0]
  if {[llength $cs] == 0} { return }
  puts "  first=[get_property NAME $c] ref=[get_property REF_NAME $c]"
  foreach pin $pins {
    set ps [get_pins -quiet -of_objects $c -filter "REF_PIN_NAME == $pin"]
    if {[llength $ps] == 0} { continue }
    set n [get_nets -quiet -of_objects [lindex $ps 0]]
    if {[llength $n] == 0} { continue }
    set nn [lindex $n 0]
    set drv [get_pins -quiet -leaf -of_objects $nn -filter {DIRECTION == OUT}]
    puts "    $pin net=[get_property NAME $nn] drv=[llength $drv]"
    foreach d [lrange $drv 0 2] { puts "       <- [get_property NAME $d] ref=[get_property REF_NAME $d]" }
  }
}
show "*u_app/st_req_reg*"
show "*u_app/st_wait_reg*"
show "*u_app/st_tick_reg*" {C CE R Q}
close_design
exit 0
