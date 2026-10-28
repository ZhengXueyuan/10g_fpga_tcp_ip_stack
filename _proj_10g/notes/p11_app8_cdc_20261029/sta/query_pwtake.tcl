open_checkpoint D:/repo/XCKU5PMini/udp_hls_10g/vivado_prj/p7b_ku5p_prj.runs/impl_1/wrapper_p4_routed.dcp
foreach netname {u_app/u_core/g_app\[0\].u_app_i/pw_take u_app/u_core/g_app\[0\].u_app_i/m_tready u_app/u_core/g_app\[0\].u_app_i/pw_valid} {
  set n [get_nets -quiet -filter "NAME == $netname"]
  if {[llength $n] == 0} { puts "NET $netname NOTFOUND"; continue }
  set nn [lindex $n 0]
  set drv [get_pins -quiet -leaf -of_objects $nn -filter {DIRECTION == OUT}]
  set ld  [get_pins -quiet -leaf -of_objects $nn -filter {DIRECTION == IN}]
  puts "NET $netname drv=[llength $drv] loads=[llength $ld]"
  foreach d [lrange $drv 0 3] { puts "   <- [get_property NAME $d] ([get_property REF_NAME $d])" }
}
close_design
exit 0
