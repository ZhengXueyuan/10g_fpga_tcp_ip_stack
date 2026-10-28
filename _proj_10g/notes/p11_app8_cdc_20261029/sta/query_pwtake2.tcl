open_checkpoint D:/repo/XCKU5PMini/udp_hls_10g/vivado_prj/p7b_ku5p_prj.runs/impl_1/wrapper_p4_routed.dcp
set ns [get_nets -hier -quiet -filter {NAME =~ *pw_take*}]
puts "pw_take_nets=[llength $ns]"
foreach n [lrange $ns 0 8] {
  set nm [get_property NAME $n]
  set drv [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == OUT}]
  set ld [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == IN}]
  puts "NET $nm drv=[llength $drv] loads=[llength $ld]"
  foreach d [lrange $drv 0 2] { puts "   <- [get_property NAME $d] ref=[get_property REF_NAME $d]" }
}
# m_tready net of app0
set ms [get_nets -hier -quiet -filter {NAME =~ *g_app\[0\].u_app_i/m_tready*}]
puts "app0_m_tready_nets=[llength $ms]"
foreach n [lrange $ms 0 3] {
  set nm [get_property NAME $n]
  set drv [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == OUT}]
  puts "NET $nm drv=[llength $drv]"
  foreach d [lrange $drv 0 2] { puts "   <- [get_property NAME $d] ref=[get_property REF_NAME $d]" }
}
close_design
exit 0
