open_checkpoint D:/repo/XCKU5PMini/udp_hls_10g/vivado_prj/p7b_ku5p_prj.runs/impl_1/wrapper_p4_routed.dcp
set q [get_pins -quiet -filter {NAME =~ *u_app/u_core/g_app\[0\].u_app_i/stat_tx_bytes_reg\[0\]/Q}]
puts "Q_pin=[get_property NAME $q]"
set nets [get_nets -quiet -of_objects $q]
foreach n $nets {
  puts "NET [get_property NAME $n]"
  set loads [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == IN}]
  puts "  loads=[llength $loads]"
  foreach l [lrange $loads 0 6] { puts "   -> [get_property NAME $l]" }
}
set ce [get_pins -quiet -filter {NAME =~ *u_app/u_core/g_app\[0\].u_app_i/stat_tx_bytes_reg\[0\]/CE}]
puts "CE_pin=[get_property NAME $ce]"
set cen [get_nets -quiet -of_objects $ce]
foreach n $cen {
  puts "CE_NET [get_property NAME $n]"
  set drv [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == OUT}]
  foreach d [lrange $drv 0 5] { puts "   drv [get_property NAME $d]" }
}
set h0 [get_pins -quiet -filter {NAME =~ *u_app/st_hold_reg\[0\]/D}]
puts "hold0_D=[get_property NAME $h0]"
set hn [get_nets -quiet -of_objects $h0]
foreach n $hn {
  puts "HOLD0_NET [get_property NAME $n]"
  set drv [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == OUT}]
  foreach d [lrange $drv 0 5] { puts "   drv [get_property NAME $d]" }
}
close_design
exit 0
